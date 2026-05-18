# svc

`svc` inspects and controls managed services.

## Usage

```text
svc list
svc status [service]
svc degraded
svc logs
svc start <service>
svc stop <service>
svc restart <service>
svc --help
```

## Behavior

- `list`
  - Calls `sysServiceList`
  - Prints service PID, registered state, and availability state
- `status [service]`
  - Requests supervision status from `svcmgtd`
  - Prints state, PID, start count, restart count, ready tick, and last reason
- `degraded`
  - Requests only degraded services from `svcmgtd`
- `logs`
  - Prints the recent service supervision event ring
- `start <service>`
  - Requests `svcmgtd` to start a stopped or degraded service
- `stop <service>`
  - Requests `svcmgtd` to stop an optional service
  - Required services are rejected by the manager
- `restart <service>`
  - Resolves the service manager PID
  - Sends `SysIpcOpSvcRestart` to `svcmgtd`
  - Copies the service name into IPC packet data

## Notes

- Control commands wait for a short IPC reply from `svcmgtd`
- Actual stop, unregister, kill, wait, and start logic lives in `svcmgtd`

## RKX Metadata

- `stack_pages = 2`
- capabilities:
  - `sys_service_manager`

`svcmgtd` checks this capability on service control and supervision requests.
