#@define WARN_STACK_SIZE 16
#@define MAX_STACK_SIZE 32

fs = require 'fs'
path = require 'path'
makros = null # object tokens
watchers = {} # watchers by filename
systemPaths = []
dirOpen = null # array history open dir
gw = null # global watcher
gn = '' # global name (path)
timers = {}

if process? and not(/^win/.test process.platform)
  styles =
    'bold' : ['\x1B[1m', '\x1B[22m'],
    'italic' : ['\x1B[3m', '\x1B[23m'],
    'underline' : ['\x1B[4m', '\x1B[24m'],
    'inverse' : ['\x1B[7m', '\x1B[27m'],
    'strikethrough' : ['\x1B[9m', '\x1B[29m'],
    #text colors
    #grayscale
    'white' : ['\x1B[37m', '\x1B[39m'],
    'grey' : ['\x1B[90m', '\x1B[39m'],
    'black' : ['\x1B[30m', '\x1B[39m'],
    #colors
    'blue' : ['\x1B[34m', '\x1B[39m'],
    'cyan' : ['\x1B[36m', '\x1B[39m'],
    'green' : ['\x1B[32m', '\x1B[39m'],
    'magenta' : ['\x1B[35m', '\x1B[39m'],
    'red' : ['\x1B[31m', '\x1B[39m'],
    'yellow' : ['\x1B[33m', '\x1B[39m'],
    #background colors
    #grayscale
    'whiteBG' : ['\x1B[47m', '\x1B[49m'],
    'greyBG' : ['\x1B[49;5;8m', '\x1B[49m'],
    'blackBG' : ['\x1B[40m', '\x1B[49m'],
    #colors
    'blueBG' : ['\x1B[44m', '\x1B[49m'],
    'cyanBG' : ['\x1B[46m', '\x1B[49m'],
    'greenBG' : ['\x1B[42m', '\x1B[49m'],
    'magentaBG' : ['\x1B[45m', '\x1B[49m'],
    'redBG' : ['\x1B[41m', '\x1B[49m'],
    'yellowBG' : ['\x1B[43m', '\x1B[49m']
  for own style of styles
    do (style) ->
      String::[style] = (val = '') ->
        styles[style][0] + @ + val + styles[style][1]
else
  styles = [ 'bold', 'italic', 'underline', 'inverse', 'strikethrough'
  #text colors
    'white', 'grey', 'black', 'blue', 'cyan', 'green', 'magenta', 'red', 'yellow'
  #background colors
    'whiteBG', 'greyBG', 'blackBG', 'blueBG', 'cyanBG', 'greenBG', 'magentaBG', 'redBG', 'yellowBG',
    ]
  for style in styles
    String::[style] = (val = '') ->
      @ + val

wait = (time, func) ->
  setTimeout func, time

startWatcher = (path) ->
  fs.exists path, (e) ->
    unless e
      console.log "#{'File not exists:'.red()} #{path.white()}\n".bold()
      return
    fs.watch path, (action, pathChanged) ->
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
    'include', # 'path.coffee' or path/to/file/without/extensiion
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
  an = /^\w$/
  sl = /^\s*$/
  def = /^(\w+)(?:\s+(.*))?$/
  defFull = ///^
(\w+)
(
\(\s*
  (\.\.\.|(\w+\s*
    (,\s*\w+\s*)*
    (,\s*\.\.\.)?
  ))
  \s*\)
)?
(\s+.*)?
    $///
  n = /\n/g
  dm = null
  out = ''
  buf = '' # line buffer
  f = 0
  q = 0 # map detect block status
  source += '\n'

  #@ifndef BLOCK_SQ

  # single quotes
  #@define BLOCK_SQ 0b0000001

  # double quotes
  #@define BLOCK_DQ 0b0000010

  # three qoutes
  #@define BLOCK_TQ 0b0000100

  # regular expression block
  #@define BLOCK_RE 0b0001000

  # comment multiline block
  #@define BLOCK_CM 0b0010000

  # as js block
  #@define BLOCK_JS 0b0100000

  # regex multiline block
  #@define BLOCK_RM 0b1000000

  #@endif

  s = false # skip
  cl = false # comment line
  d = false # dirrective
  sd = false # start directive
  #os = false
  ba = false # block active
  di = false # define makro replacement ignore
  iftrue = false # width ifactive, if true, copy text on
  ifactive = 0 # active use block
  ifpassed = false # if find active block for else and elif
  ad = -1    # active dirrective
  i  = -1    # character index
  i2 = -1    # character index for locale search
  line = 1   # line number
  nfound = 0 # use for find count NL in skipped block
  ecran = false # backslash character found?
  replace = true # false if single quotes and comments
  l = source.length

  #define A B B1
  #define B C C1
  #define C A A1
  # A B C -> A A1 C1 B1 B B1 A1 C1 C C1 B1 A1
  define = (name, value) ->
    unless value?
      makros[name] = ''
      return
    makros[name] = value
    return

  undef = (name) ->
    if name isnt ''
      if makros.hasOwnProperty name
        makros[name] = null
      else
        warn "Index #{name.blue()} haven't in makros. Undef fail"
        #console.warn "Index #{name.blue()} haven't in makros. Undef fail in #{filename.white()}:#{''.cyan(line)}".yellow()
    else
      warn "Undef is empty"
      #console.warn "Undef is empty in #{filename.white()}:#{''.cyan(line)}".yellow()

  # пытаемся заменить имя или переменную на значение со всеми подстановками
  token = (name, stack = []) ->
    # если замене не подлежит
    if (not replace) or cl
      return name
    # если макрос есть и он не отменён
    if makros.hasOwnProperty(name) and makros[name]?
      # проверяем длину стека (на всякий случай. Потом величину следует увеличить до 2048)
      if stack.length > MAX_STACK_SIZE
        warn "Tokenise stak max size!!!"
        #console.warn "Tokenise stak max size!!! fail in #{filename.white()}:#{''.cyan(line)}".yellow()
        stack.pop()
        return name
      if stack.length > WARN_STACK_SIZE
        warn "Tokenise stak warn size: #{stack.length}"
        #console.warn "Tokenise stak warn size: #{stack.length} fail in #{filename.white()}:#{''.cyan(line)}".yellow()
      # при обнаружении циклической
      if name in stack
        stack.pop()
        return name
      stack.push(name)
      val =  makros[name]
      words = val.match(/\b\w+\b/g)
      for w in words
        val = val.replace(new RegExp("\\b#{w}\\b"), token(w, stack))
      val
    else
      stack.pop()
      name

  # include подключаем файл
  include = (name, ident) ->
    name = name.trim()
    if name is '' or not name?
      warn "Can't include file by empty path!"
      #console.warn "Can't include file by empty path! #{filename.white()}:#{''.cyan(line)}".yellow()
      return ''

    if (c = name.charAt(0)) is '"' # " h-char-sequence"
      if name.charAt(0) isnt name.charAt(name.length-1)
        warn "Parse error: can't parse include path"
        #console.warn "Parse error: can't parse include path in #{filename.white()}:#{''.cyan(line)}".yellow()
        return ''
      p = name.substr(1, name.length - 2)
      iv = 2
    else if c is '<' # < h-char-sequence>
      if name.charAt(name.length-1) isnt '>'
        warn  "Including system file not complete"
        #console.warn "Including system file not complete in #{filename.white()}:#{''.cyan(line)}".yellow()
        return ''
      p = name.substr(1, name.length - 2)
      iv = 1
    else # include pp-tokens
      p = token(name)
      if p is p
        warn "Cannot find macro for #{p.white().bold()}"
        #console.warn "Cannot find macro for #{p.white().bold()} in #{filename.white()}:#{''.cyan(line)}".yellow()
        return ''
      else if p is ''
        warn "Can't include by empty path"
        #console.warn "Can't include by empty path in #{filename.white()}:#{''.cyan(line)}".yellow()
        return ''
      return include p, ident

    incPath = null
    switch iv
      when 1 # < >
        if p.charAt(0) is '/'
          warn "Path between < > can't start from /"
          #console.warn "Path between < > can't start from / in #{filename.white()}:#{''.cyan(line)}".yellow()
          return ''
        # search in system dirs
        for dir in systemPaths
          if fs.existsSync dir + "/" + p
            incPath = dir + '/' + p
            break
        break if incPath? # shit: break to label is not avialable
        warn "File #{p.white().bold()} cannot find in system dirs. Error:"
        #console.warn "File #{p.white().bold()} cannot find in system dirs. Error: #{filename.white()}:#{''.cyan(line)}".yellow()
        return ''
      when 2 # " "
        if p.charAt(0) is '/'
          warn "Absolute path is not safe!" # it's not error, but warning
          #console.warn "Absolute path is not safe! #{filename.white()}:#{''.cyan(line)}".yellow()
          # find only one file
          unless fs.existsSync p
            warn "Include error: #{p.white().bold()} not exist"
            #console.warn "Include error: #{p.white().bold()} not exist in #{filename.white()}:#{''.cyan(line)}".yellow()
            return ''
          incPath = p
          break
        for dir in dirOpen by -1
          if fs.existsSync dir + "/" + p
            incPath = dir + "/" + p
            break
        break if incPath?
        for dir in systemPaths
          if fs.existsSync dir + "/" + p
            incPath = dir + '/' + p
            break
        break if incPath?
        warn "File #{p.white().bold()} cannot find."
        #console.warn "File #{p.white().bold()} cannot find. Error: #{filename.white()}:#{''.cyan(line)}".yellow()
        return ''
      else
        error "O__o WTF!?"
        #console.error "O__o WTF!?".red().bold() # impossible

    unless incPath?
      error "Include error. Can't find and not print warn and out"
      #console.error "Include error. Can't find and not print warn and out".red().bold()
      return ''

    dir = path.dirname(incPath) # dir must have dirname, это на всякий случай
    unless dir in dirOpen # add history dir open
      dirOpen.push dir
    if gw?
      subscribeChange incPath, gn, gw
    # return
    ident + cPreProcessor fs.readFileSync(incPath).toString(), incPath, ident
  # include end

  warn = (message) ->
    console.warn message.yellow(), filename.white(), ''.cyan(line)

  error = (message) ->
    console.error message.red().bold()

  while i++ < l
    c = source.charAt(i)
    c2 = source.charAt(i + 1)
    if c is '\\' # if after backslash new line split into line
      if source.substr(i + 1, 2) is '\n#'
        i += 3
        line++
        continue
      else if source.substr(i + 1, 2) is '\r\n#'
        i += 4
        line++
        continue
    ba = ifactive is 0 or iftrue
    unless ba
      s = true
    unless ecran
      switch c
        when "'", "`" # single quotes, js source
          f = if c is "'" then BLOCK_SQ else BLOCK_JS
          unless cl
            if q is 0
              q = f
            else if q is f
              q = 0
          if q is BLOCK_SQ
            replace = false
          else
            replace = true
          f = 0
        when '/', '"' # slash or double quotes
          if c2 is c and source.charAt(i+2) is c # if /// detected
            f = if c is '/' then BLOCK_RM else BLOCK_TQ
            i += 2
            buf += c + c if ba
          else
            f = if c is '/' then BLOCK_RE else BLOCK_DQ
          unless cl
            if q is 0
              q = f
            else if q is f
              q = 0
          f = 0
        when '#'
          if q isnt 0 and q isnt BLOCK_CM
            break
          if c2 is c and source.charAt(i+2) is c # if ### detected
            f = BLOCK_CM
            i += 2
            buf += '##' if ba
            if q is f
              f = 0
          else if c2 isnt '@' # comment detected
            cl = true
          else unless cl
            sd = true
          q = f
          if sd and q isnt BLOCK_CM # if #@ and not comment
            d = true # устанавливаем флаг диррективы
            s = true
            i++
          f = 0
        when '\\'
          if 0 isnt (q & (BLOCK_SQ | BLOCK_DQ | BLOCK_TQ | BLOCK_JS | BLOCK_RM | BLOCK_RE))
            ecran = true
        else
          os = true
    else
      ecran = false
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
              warn "cannot find preprocessor directive #{word.bold()}"
              #console.warn "cannot find preprocessor directive #{word.bold()}  in #{filename.white()}:#{''.cyan(line)}".yellow()
            word = ''
        else
          word += c
      else # if end of line
        if ad is -1 and word isnt '' # for 'else' and 'endif'
          ad = directives.indexOf(word)
          word = ''
        if ifactive > 0 and not iftrue and not (4 <= ad <= 6) # if find
          i = source.indexOf('\n', i) - 1
          d = false
          ad = -1
          line++
          continue
        switch ad
          when -1
          # if \n after #@ or fail name directive
            d = false
          when 0
          # include
            out += include word, buf
            # startWatcher gw, p
          when 1
          # define
            dm = word.trim().match def
            unless dm?
              warn "Define #{word} fail"
              #console.warn "Define #{word} fail in #{filename.white()}:#{''.cyan(line)}".yellow()
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
              warn "#elif without #if"
              #console.warn "elif without #if in #{filename.white()}:#{''.cyan(line)}".yellow()
              return ""
            if ifpassed
              i2 = source.lastIndexOf("\n", source.indexOf("#@endif", i))
              ad = -1
              d = false
              if i2 is -1
                warn "#endif not found"
                #console.warn "#endif not found in #{filename.white()}:#{''.cyan(line)}".yellow()
                return ""
              word = ''
              buf = ''
              iftrue = false
              nfound = source.substring(i, i2).match(n)
              line += (nfound?.length or 0) + 1
              i = i2
              continue
            if iftrue
              iftrue = false
            else if eval word
              iftrue = true
          when 5
          # else
            if ifactive is 0
              warn "#else without #if"
              #console.warn "else without #if in #{filename.white()}:#{''.cyan(line)}".yellow()
              return ""
            if ifpassed
              i2 = source.lastIndexOf("\n", source.indexOf("#@endif", i))
              ad = -1
              d = false
              if i2 is -1
                warn "#endif not found"
                #console.warn "endif not found in #{filename.white()}:#{''.cyan(line)}".yellow()
                return ""
              word = ''
              buf = ''
              iftrue = false
              nfound = source.substring(i, i2).match(n)
              line += (nfound?.length or 0) + 1
              i = i2
              continue
            iftrue = not iftrue
          when 6
          # endif
            if ifactive is 0
              warn "#endif without #if"
              #console.warn "endif without #if in #{filename.white()}:#{''.cyan(line)}".yellow()
              return ""
            unless sl.test word
              warn "#endif not empty"
              #console.warn "endif not empty in #{filename.white()}:#{''.cyan(line)}".yellow()
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
            warn "What!?"
            #console.log "What!? in #{filename.white()}:#{''.cyan(line)}".yellow()
        # clean
        ad = -1
        d = false
        word = ''
        buf = ''
      s = true
    else
      if ba
        if isw = an.test c
          word += c
          # s = true
        else
          buf += c
        if isw and not an.test c2
          wr = if word is '' then '' else token(word)
          if wr isnt word
            if buf.charAt(buf.length - 1) is ' '
              buf += wr
            else
              buf += ' ' + wr
            if c2 isnt ' '
              buf += ' '
          else
            buf += word
          word = ''
          # buf += c
      s = true
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
  # return cPreProcessor
  out.substr(0, out.length - 1) # without \n

optionParse = (opts) ->
  for o in opts.params
    if o.substr(0, 2) is '-I'
      sp = o.substr(2).trim().replace(/\/$/, '')
      unless sp in systemPaths
        systemPaths.push sp
  if process.env.hasOwnProperty('COFFEE_INCLUDE')
    dirs = process.env.COFFEE_INCLUDE.split(':')
    for o in dirs
      o = o.trim().replace(/\/$/, '')
      unless o in systemPaths
        systemPaths.push o
  return

module.exports = (data, name, watcher, opts) ->
  gw = watcher or null
  gn = name

  optionParse(opts)
  unsubscribeChange name # снимаем все существующие watcher-ы
  makros = {} # обнуляем все ранее созданные определения
  dirOpen = [path.dirname(name)]
  ret = cPreProcessor data, name, '' # препроцессим!

  gw = null
  gn = ''

  ret