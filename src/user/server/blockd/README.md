# blockd

`blockd` is the userspace server responsible for block device operations.
It keeps raw block syscalls concentrated in one managed service, so regular
user processes do not access the block device directly.

## Responsibilities

- Receive `SysBlockRequest` messages and perform block-level read/write
- Centralize raw block syscall usage in `blockd`
- Return results through `SysBlockResponse`
- Notify `svcmgtd` with a service ready ACK after startup

## RKX Metadata

- `stack_pages = 4`
- capabilities:
  - `sys_raw_block`

`blockd` is the only managed service expected to use raw block read/write
syscalls.

## Startup Flow

1. `svcmgtd` starts `/bin/blockd`
2. `blockd` waits until it is registered as `SysServiceKindBlock`
3. `notifyServiceReady(SysServiceKindBlock)` sends a ready ACK to `svcmgtd`
4. `sysBlockServiceReceive` waits for block requests in a loop

If service registration times out, `blockd` exits with `sysExit(1)`.
Because `blockd` is a required service, `svcmgtd` treats it as restartable.

## Request Handling

- `SysBlockOpRead`
  - Passes `req.blockIndex` to `sysRawBlockRead`
  - Stores the 512-byte block in `resp.data`
- `SysBlockOpWrite`
  - Writes `req.data` to the target block with `sysRawBlockWrite`
- Unknown op
  - Returns `resp.result = -1`

The response `id` is copied from the request `id`, allowing kernel-side pending
requests to match replies with their original requests.

## Boundaries and Notes

- The block size follows the syscall ABI fixed-size block buffer
- `blockd` does not interpret block indexes itself; range checks are delegated
  to the raw block syscall layer
- Receive failure is treated as fatal and terminates the server
- The current model is synchronous request/reply and does not process requests
  in parallel

## Related Files

- `blockd.nim`: server implementation
- `../lib/service_ready.nim`: shared service registration wait and ready ACK helpers
- `src/lib/syscall_types.nim`: `SysBlockRequest`, `SysBlockResponse`, and op definitions
