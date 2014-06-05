fs = require 'fs'
path = require 'path'

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
  makros = {}
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
  # single quotes 0b000001
  # double quotes 0b000010
  # three qoutes  0b000100
  # regexpr block 0b001000
  # comment block 0b010000
  # as js block   0b100000
  s = false # skip
  cl = false # comment line
  d = false # dirrective
  sd = false # start directive
  iftrue = false # width ifactive, if true, copy text on
  os = false
  ifactive = 0 # active use block
  ad = -1    # active dirrective
  i  = -1
  l = source.length
  line = 0
  define = (name, value) ->
    if value?
      makros[name] = value
    else
      undef(name)
    return
  undef = (name) ->
    if name isnt ''
      if makros.hasOwnProperty name
        makros[name] = null
      else
        console.warn "Index #{name} haven't in makros. Undef fail in #{filename}:#{line}"
    else
      console.error "Undef is empty in #{filename}:#{line}"

  while i++ < l
    c = source.charAt(i)
    if c is '\\' # if after backslash new line split into line
      if source.charAt(i + 1) is '\n'
        i += 2
        continue
      else if source.substr(i + 1, 2) is '\r\n'
        i += 3
        continue
    unless ifactive is 0 or iftrue
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
          out += c + c if ifactive is 0 or iftrue
        unless cl
          if q is 0
            q = f
          else if q is f
            q = 0
        f = 0
      when '#'
        if source.charAt(i+1) is c and source.charAt(i+2) is c # if ### detected
          f = 0b10000
          i += 2
          out += '##' if ifactive is 0 or iftrue
        else if source.charAt(i+1) isnt '@' # comment detected
          cl = true
        else unless cl
          sd = true
        if q is 0
          q = f
        else
          q = 0
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
                console.error "Parse error: can't parse include path in #{filename}:#{line}"
                return ''
              p = word.substr(1, word.length-1)
            else
              p = word + '.coffee'
            if p.charAt(0) isnt '/'
              p = path.dirname(filename) + '/' + p
            unless fs.existsSync p
              console.error "include error: #{p} not exist in #{filename}:#{line}"
              return ''
            unless sl.test buf
              console.error "before include exist character in #{filename}:#{line}"
              return ''
            out += buf + cPreProcessor fs.readFileSync(p).toString(), p, buf
          when 1
          # define
            dm = word.trim().match def
            unless dm?
              console.error "Define #{word} fail in #{filename}:#{line}"
            define dm[1], dm[2]
          when 2
          # undef
            undef(word.trim())
          when 3
          # if
            ifactive++
            if eval word
              iftrue = true
          when 4
          # elif
            if ifactive is 0
              console.error "elif without #if in #{filename}:#{line}"
              return ""
            if iftrue
              iftrue = false
            else if eval word
              iftrue = true
          when 5
          # else
            if ifactive is 0
              console.error "else without #if in #{filename}:#{line}"
              return ""
            iftrue = not iftrue
          when 6
          # endif
            if ifactive is 0
              console.error "endif without #if in #{filename}:#{line}"
              return ""
            unless sl.test word
              console.warn "endif not empty in #{filename}:#{line}"
            ifactive--
          when 7
          # ifdef
            ifactive++
            iftrue = (makros.hasOwnProperty(word) and makros[word]?)
          when 8
          # ifndef
            ifactive++
            iftrue = not (makros.hasOwnProperty(word) and makros[word]?)
          else
            console.log "What!? in #{filename}:#{line}"
        # clean
        ad = -1
        d = false
        word = ''
        buf = ''
      s = true
    else
      if ifactive is 0 or iftrue
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
      out += buf
      buf = indent
    unless s
      buf += c
    else
      s = false
  if c is ""
    out += buf
  out # return cPreProcessor

module.exports = cPreProcessor