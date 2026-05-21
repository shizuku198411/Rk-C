## Provides shared request/reply tracking helpers for service-backed syscalls.
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


## Implements the next ipc request id kernel helper.
proc nextIpcRequestId*(domain: var IpcRequestDomain): U64 =
  if domain.nextId == 0:
    domain.nextId = 1

  result = domain.nextId
  inc domain.nextId


## Resets ipc pending.
proc resetIpcPending*(pending: ptr IpcPending) =
  if pending != nil:
    pending[] = IpcPending()


## Implements the assign ipc request id kernel helper.
proc assignIpcRequestId*(domain: var IpcRequestDomain, pending: ptr IpcPending): U64 =
  if pending == nil:
    return 0

  pending.id = nextIpcRequestId(domain)
  pending.id


## Allocates ipc pending.
proc allocIpcPending*[T](slots: var openArray[T]): ptr T =
  var i = 0
  while i < len(slots):
    if not slots[i].ipc.used:
      slots[i] = T()
      slots[i].ipc.used = true
      return addr slots[i]
    inc i

  nil


## Finds ipc pending.
proc findIpcPending*[T](slots: var openArray[T], id: U64): ptr T =
  var i = 0
  while i < len(slots):
    if slots[i].ipc.used and slots[i].ipc.id == id:
      return addr slots[i]
    inc i

  nil


## Finishes ipc pending.
proc finishIpcPending*[T](slot: ptr T) =
  if slot != nil:
    slot[] = T()


## Waits for ipc reply.
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
