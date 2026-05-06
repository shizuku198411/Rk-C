import ../../../lib/types
import ../../service/registry
import ../../task/process

type
  IpcPending* = object
    used*: bool
    completed*: bool
    id*: U64

  IpcRequestDomain* = object
    nextId*: U64


proc nextIpcRequestId*(domain: var IpcRequestDomain): U64 =
  if domain.nextId == 0:
    domain.nextId = 1

  result = domain.nextId
  inc domain.nextId


proc resetIpcPending*(pending: ptr IpcPending) =
  if pending != nil:
    pending[] = IpcPending()


proc assignIpcRequestId*(domain: var IpcRequestDomain, pending: ptr IpcPending): U64 =
  if pending == nil:
    return 0

  pending.id = nextIpcRequestId(domain)
  pending.id


proc allocIpcPending*[T](slots: var openArray[T]): ptr T =
  var i = 0
  while i < len(slots):
    if not slots[i].ipc.used:
      slots[i] = T()
      slots[i].ipc.used = true
      return addr slots[i]
    inc i

  nil


proc findIpcPending*[T](slots: var openArray[T], id: U64): ptr T =
  var i = 0
  while i < len(slots):
    if slots[i].ipc.used and slots[i].ipc.id == id:
      return addr slots[i]
    inc i

  nil


proc finishIpcPending*[T](slot: ptr T) =
  if slot != nil:
    slot[] = T()


proc waitIpcReply*(pending: ptr IpcPending, service: ServiceKind, waitKind: WaitKind): bool =
  if pending == nil:
    return false

  while pending.used and not pending.completed:
    if not serviceAvailable(service):
      return false

    case waitKind
    of waitFsReq:
      sleepCurrentForFsReq(pending.id)
    of waitBlockReq:
      sleepCurrentForBlockReq(pending.id)
    else:
      return false

  pending.used
