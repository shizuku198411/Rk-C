{.warning[UnusedImport]: off.}

import lib/mem
import lib/string
import lib/types

discard sizeof(CSize)

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
elif defined(userApp_edit):
  import apps/edit/edit
elif defined(userApp_ipc):
  import apps/ipc/ipc
elif defined(userApp_kill):
  import apps/kill/kill
elif defined(userApp_svcmgtd):
  import server/svcmgtd/svcmgtd
elif defined(userApp_fsd):
  import server/fsd/fsd
elif defined(userApp_blockd):
  import server/blockd/blockd
else:
  {.error: "missing user app define".}
