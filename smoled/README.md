# smoled

A very smol editor.


## Building

`nasm -fbin smoled.asm -o smoled.com`

or

`bazel build :smoledcom`


## Running

Run `smoled.com` (or `bazel-bin/smoled/smoled.com`)


## Editing

Cursor keys:

```
Up: ctrl+p
Down: ctrl+n
Left: ctrl+b
Right: ctrl+f
Start of line: ctrl+a
End of line: ctrl+e
Quit: ctrl+q (twice, if dirty)
Load: ctrl+l
Save: ctrl+s
Delete: ctrl+d (not "Del" key)
```

## Debugging

Build with `-dDEBUG` for some additional status-line output.

Or, `bazel build :smoledcomdebug`, which builds `smoledb.com`.
