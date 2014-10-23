            {
         }   }   {
        {   {  }  }
         }   }{  {
        {  }{  }  }                    _____       __  __
       { }{ }{  { }                   / ____|     / _|/ _|
     .- { { }  { }} -.               | |     ___ | |_| |_ ___  ___
    (  { } { } { } }  )              | |    / _ \|  _|  _/ _ \/ _ \
    |`-..________ ..-'|              | |___| (_) | | | ||  __/  __/
    |                 |               \_____\___/|_| |_| \___|\___|
    |                 ;--.
    |                (__  \            _____           _       _
    |                 | )  )          / ____|         (_)     | |
    |                 |/  /          | (___   ___ _ __ _ _ __ | |_
    |                 (  /            \___ \ / __| '__| | '_ \| __|
    |                 |/              ____) | (__| |  | | |_) | |_
    |                 |              |_____/ \___|_|  |_| .__/ \__|
     `-.._________..-'                                  | |
                                                        |_|

CoffeeScript is a little language that compiles into JavaScript.

## Installation

If you have the node package manager, npm, installed:

```shell
npm install -g coffee-script
```

Leave off the `-g` if you don't wish to install globally. If you don't wish to use npm:

```shell
git clone https://github.com/jashkenas/coffeescript.git
sudo coffee-script/bin/cake install
```

## Getting Started

Execute a script:

```shell
coffee /path/to/script.coffee
```

Compile a script:

```shell
coffee -c /path/to/script.coffee
```

For documentation, usage, and examples, see: http://coffeescript.org/

To suggest a feature or report a bug: http://github.com/jashkenas/coffeescript/issues

If you'd like to chat, drop by #coffeescript on Freenode IRC.

The source repository: https://github.com/jashkenas/coffeescript.git

Our lovely and talented contributors are listed here: http://github.com/jashkenas/coffeescript/contributors

## Preprocessor directives

C-style directive *text* preprocessor standard ISO 3337 (width annotation by coffee).
Can be used width --watch.
Can't be used width --map

Partial standard:
```@#define VAR value for define```
support cyclic tokenize, not support function-style macros, -D flags compiler

Full standard:
```#@include "path/to/include/file.coffee```
support full nuance include by C11 standard (-I flags, search directories),
and save indent for included files

Condition statements:

```
    #@if 1 > 0
    console.log "1 > 0"
    #@else
    console.log "1 < 0"
    #@endif
```

output.js line: ```console.log("1 < 0")```

As well as:

```

    #@undef MAKROS
    #@ifdef TRUE_IF_MAKROS_DEFINED

    #@ifndef TRUE_IF_MAKROS_NOT_DEFINED

    #@elif EXPR
```