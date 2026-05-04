{.warning[UnusedImport]: off.}

import lib/string

discard sizeof(string.CSize)

when defined(userApp_shell):
  import apps/shell/shell
elif defined(userApp_ls):
  import apps/ls/ls
elif defined(userApp_cat):
  import apps/cat/cat
elif defined(userApp_mkdir):
  import apps/mkdir/mkdir
elif defined(userApp_ps):
  import apps/ps/ps
elif defined(userApp_rm):
  import apps/rm/rm
elif defined(userApp_rmdir):
  import apps/rmdir/rmdir
elif defined(userApp_date):
  import apps/date/date
else:
  {.error: "missing user app define".}
