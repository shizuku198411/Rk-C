# fsd

`fsd` is the userspace file system server.
It receives kernel-side FS requests and translates them into raw FS syscalls
for operations such as `ls`, `mkdir`, file read, and file write.

## Responsibilities

- Receive `SysFsRequest` messages and dispatch them to raw FS syscalls
- Centralize raw FS syscall usage in `fsd`
- Return results, data sizes, and directory entries through `SysFsResponse`
- Notify `svcmgtd` with a service ready ACK after startup

## Startup Flow

1. `svcmgtd` starts `/bin/fsd`
2. `fsd` waits until it is registered as `SysServiceKindFs`
3. `notifyServiceReady(SysServiceKindFs)` sends a ready ACK to `svcmgtd`
4. `sysFsServiceReceive` waits for FS requests in a loop

If service registration times out, `fsd` exits with `sysExit(1)`.
Because `fsd` is a required service, stop or ready-timeout cases are handled by
`svcmgtd` as restartable failures.

## Request Handling

- `SysFsOpLs`
  - Computes `req.capacity / sizeof(DirEntry)` as the entry limit
  - Calls `sysRawLs`
  - On success, sets `resp.size = entry_count * sizeof(DirEntry)`
- `SysFsOpMkdir`
  - Calls `sysRawMkdir(req.path)`
- `SysFsOpUnlink`
  - Calls `sysRawUnlink(req.path)`
- `SysFsOpRmdir`
  - Calls `sysRawRmdir(req.path)`
- `SysFsOpReadFile`
  - Calls `sysRawReadFile(req.path, resp.data, req.capacity)`
  - On success, stores the byte count in `resp.size`
- `SysFsOpWriteFile`
  - Calls `sysRawWriteFile(req.path, req.data, req.size)`
- Unknown op
  - Returns `resp.result = -1`

The response `id` is copied from the request `id`.

## Boundaries and Notes

- Paths are stored in the fixed-size `SysFsRequest.path` buffer
- File data is limited by the fixed-size `SysFsRequest.data` and
  `SysFsResponse.data` buffers
- `fsd` passes received paths to raw FS syscalls without additional path
  interpretation
- cwd and relative path resolution are primarily handled in the kernel syscall
  and VFS layers
- The current model is synchronous request/reply and does not process requests
  in parallel

## Related Files

- `fsd.nim`: server implementation
- `../lib/service_ready.nim`: shared service registration wait and ready ACK helpers
- `src/lib/syscall_types.nim`: `SysFsRequest`, `SysFsResponse`, and op definitions
