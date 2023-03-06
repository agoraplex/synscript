# synscript notes

Invoke `states` on a file to produce output with `enscript` escape codes:

``` bash
states \
  -f ~/.enscript/enscript.st \
  -p ~/.enscript:/usr/local/share/enscript/hl \
  -s facelist \
  -v \
  -Dcolor=1 \
  -Dlanguage=enscript \
  -Dstyle=emacs_verbose \
  facelist
```

Run the app in my wrapper script, producing the usual `enscript` PDF output:

``` bash
clear ; cargo build && ./ss -o tmp/squirtle/App.js
```
