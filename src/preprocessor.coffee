fs = require 'fs'
path = require 'path'
makros = {}
watchers = {} # watchers by filename
gw = null # global watcher
gn = '' # global name (path)
timers = {}

wait = (time, func) ->
  setTimeout func, time

startWatcher = (path) ->
  fs.exists path, (e) ->
    unless e
      console.log "\x1B[1;31mFile not exists: \x1b[1;37m #{path}\x1B[0m\n"
      return
    fileWatcher = fs.watch path, (action, pathChanged) ->
      clearTimeout timers[pathChanged] if timers[pathChanged]?
      timers[pathChanged] = wait 25, ->
        # проходимся по подписанным на обновления вотчерам
        for own i, w of watchers[path]
          w?.emit? 'change', true
        return
      return
    return
  return

# чтобы следить за изменениями файла мы подписываемся на изменения
subscribeChange = (pathChangedFile, pathCoreFile, coreWatchers) ->
  unless watchers[pathChangedFile]?
    watchers[pathChangedFile] = {}
  watchers[pathChangedFile][pathCoreFile] = coreWatchers
  startWatcher(pathChangedFile)

# перед тем, как пройдёт компиляция, все вотчеры отменяем
unsubscribeChange = (pathCoreFile) ->
  for own i, collect of watchers
    if collect.hasOwnProperty pathCoreFile
      delete collect[pathCoreFile]
  return

cPreProcessor = (source, filename, indent = "") ->
  directives = [
    'include', # 'path' or path/to/file/without/extensiion
    'define', # apply [a-zA-Z0-9_] (or \w)
    'undef'
    'if'
    'elif'
    'else'
    'endif'
    'ifdef'
    'ifndef'
  ]
  word = ''
  an = /\w/
  qt = /'|"/
  sl = /^\s*$/
  def = /^(\w+)(?:\s+(.*))?$/
  dm = null
  out = ''
  buf = '' # line buffer
  f = 0
  q = 0b00000
  # single quotes 0b0000001
  # double quotes 0b0000010
  # three qoutes  0b0000100
  # regexpr block 0b0001000
  # comment block 0b0010000
  # as js block   0b0100000
  # regex start   0b1000000
  s = false # skip
  cl = false # comment line
  d = false # dirrective
  sd = false # start directive
  os = false
  ba = false
  iftrue = false # width ifactive, if true, copy text on
  ifactive = 0 # active use block
  ifpassed = false # if find active block for else and elif
  ad = -1    # active dirrective
  i  = -1
  l = source.length
  line = 0
  define = (name, value) ->
    unless value?
      makros[name] = ''
      return
    # тут мы анализируем  value на использование другими макросами
    #define GO 123
    #define SAK GO MUST // 123 MUST
    #define DUCK GO SAK // 123 123 MUST
    makros[name] = value
    return
  undef = (name) ->
    if name isnt ''
      if makros.hasOwnProperty name
        makros[name] = null
      else
        console.warn "Index #{name} haven't in makros. Undef fail in #{filename}:#{line}"
    else
      console.warn "Undef is empty in #{filename}:#{line}"

  while i++ < l
    c = source.charAt(i)
    if c is '\\' # if after backslash new line split into line
      if source.substr(i + 1, 2) is '\n#'
        i += 3
        continue
      else if source.substr(i + 1, 2) is '\r\n#'
        i += 4
        continue
    ba = ifactive is 0 or iftrue
    unless ba
      s = true
    switch c
      when "'", "`" # single quotes, js source
        f = if c is "'" then 0b001 else 0b100000
        unless cl
          if q is 0
            q = f
          else if q is f
            q = 0
        f = 0
      when '/', '"' # slash or double quotes
        if source.charAt(i+1) is c and source.charAt(i+2) is c # if /// detected
          f = if c is '/' then 0b01000 else 0b100
          i += 2
          buf += c + c if ba
        else
          f = if c is '/' then 0b1000000 else 0b10
        unless cl
          if q is 0
            q = f
          else if q is f
            q = 0
        f = 0
      when '#'
        if q isnt 0
          os = true
          break
        if source.charAt(i+1) is c and source.charAt(i+2) is c # if ### detected
          f = 0b10000
          i += 2
          buf += '##' if ba
        else if source.charAt(i+1) isnt '@' # comment detected
          cl = true
        else unless cl
          sd = true
        q = f
        if sd and q isnt 0b10000 # if #@ and not comment
          d = true # устанавливаем флаг диррективы
          s = true
          i++
        f = 0
      else
        os = true
    if d # если мы внутри директивы
      if sd
        sd = false
        continue
      if c isnt '\n' # before and line
        if ad is -1 # if compile directive name
          if an.test c # if part of name
            word += c
          else
            ad = directives.indexOf(word)
            if ad is -1
              console.warn "cannot find preprocessor directive #{word}  in #{filename}:#{line}"
            word = ''
        else
          word += c
      else # if end of line
        if ad is -1 and word isnt '' # for 'else' and 'andif'
          ad = directives.indexOf(word)
          word = ''
        if ifactive > 0 and not iftrue and not (4 <= ad <= 6) # if find
          i = source.indexOf('\n', i) - 1
          d = false
          ad = -1
          continue
        switch ad
          when -1
          # if \n after #@ or fail name directive
            d = false
          when 0
          # include
            word = word.trim()
            if qt.test word.charAt(0)
              if word.charAt(0) isnt word.charAt(word.length-1)
                console.warn "Parse error: can't parse include path in #{filename}:#{line}"
                return ''
              p = word.substr(1, word.length - 2)
            else
              p = word + '.coffee'
            if p.charAt(0) isnt '/'
              p = path.dirname(filename) + '/' + p
            unless fs.existsSync p
              console.warn "include error: #{p} not exist in #{filename}:#{line}"
              return ''
            unless sl.test buf
              console.warn "before include exist character in #{filename}:#{line}"
              return ''
            out += buf + cPreProcessor fs.readFileSync(p).toString(), p, buf
            subscribeChange p, gn, gw
            # startWatcher gw, p
          when 1
          # define
            dm = word.trim().match def
            unless dm?
              console.warn "Define #{word} fail in #{filename}:#{line}"
            define dm[1], dm[2]
          when 2
          # undef
            undef(word.trim())
          when 3
          # if
            ifactive++
            if eval word
              iftrue = true
              ifpassed = true
          when 4
          # elif
            if ifactive is 0
              console.warn "elif without #if in #{filename}:#{line}"
              return ""
            if ifpassed
              i = source.lastIndexOf("\n", source.indexOf("#@endif", i))
              ad = -1
              d = false
              word = ''
              buf = ''
              iftrue = false
              continue
            if iftrue
              iftrue = false
            else if eval word
              iftrue = true
          when 5
          # else
            if ifactive is 0
              console.warn "else without #if in #{filename}:#{line}"
              return ""
            if ifpassed
              i = source.lastIndexOf("\n", source.indexOf("#@endif", i))
              ad = -1
              d = false
              word = ''
              buf = ''
              iftrue = false
              continue
            iftrue = not iftrue
          when 6
          # endif
            if ifactive is 0
              console.warn "endif without #if in #{filename}:#{line}"
              return ""
            unless sl.test word
              console.warn "endif not empty in #{filename}:#{line}"
            ifactive--
            ifpassed = ifactive isnt 0
          when 7
          # ifdef
            ifactive++
            ifpassed = iftrue = (makros.hasOwnProperty(word) and makros[word]?)
          when 8
          # ifndef
            ifactive++
            ifpassed = iftrue = not (makros.hasOwnProperty(word) and makros[word]?)
          else
            console.log "What!? in #{filename}:#{line}"
        # clean
        ad = -1
        d = false
        word = ''
        buf = ''
      s = true
    else
      if ba
        if an.test c
          word += c
        else
          if makros.hasOwnProperty(word) and makros[word]?
            if buf.charAt(buf.length - 1) is ' '
              buf += makros[word]
            else
              buf += ' ' + makros[word]
            if source.charAt(i + 1) isnt ' '
              buf += ' '
          else
            buf += word
          word = ''
          buf += c
      s = true
    # end switch
    if c is '\n'
      line++
      c += indent
      cl = false
      word = ''
      if ba
        out += buf
      buf = indent
    unless s
      buf += c
    else
      s = false
  if c is ""
    out += buf
  out # return cPreProcessor

module.exports = (data, name, watcher) ->
  gw = watcher or null
  gn = name

  unsubscribeChange name
  ret = cPreProcessor data, name, ''

  gw = null
  gn = ''

  ret