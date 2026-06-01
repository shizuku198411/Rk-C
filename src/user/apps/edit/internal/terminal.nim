## Provides ANSI terminal control helpers for the editor.
import ../../../lib/core/io
import ../../../../lib/types


## Writes a terminal escape sequence.
proc esc*(s: cstring) =
  write(s)


## Moves the terminal cursor to a one-based row and column.
proc gotoPos*(row, col: U64) =
  esc("\x1b[")
  writeUnsigned(row)
  write(";")
  writeUnsigned(col)
  write("H")


## Clears the current terminal line.
proc clearLine*() =
  esc("\x1b[2K")


## Clears the terminal screen and moves the cursor home.
proc clearScreen*() =
  esc("\x1b[2J\x1b[H")
