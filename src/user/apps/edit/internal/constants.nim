## Defines editor buffer, screen, and key constants.

const
  BufferMax* = 4096
  ScreenRows* = 22'u64
  ScreenCols* = 80'u64
  ScreenColsInt* = 80
  HeaderRow* = 1'u64
  EditStartRow* = HeaderRow + 1
  HelpRow* = ScreenRows - 1
  StatusRow* = ScreenRows
  EditRows* = ScreenRows - 3
  CtrlC* = char(3)
  CtrlS* = char(19)
  CtrlX* = char(24)
  Esc* = char(27)
