# svc

`svc` inspects and controls managed services.

## Usage

```text
svc list
svc restart <service>
svc --help
```

## Behavior

- `list`
  - Calls `sysServiceList`
  - Prints service PID, registered state, and availability state
- `restart <service>`
  - Resolves the service manager PID
  - Sends `SysIpcOpSvcRestart` to `svcmgtd`
  - Copies the service name into IPC packet data

## Notes

- Restart is asynchronous from the app's perspective
- Actual stop, unregister, kill, wait, and start logic lives in `svcmgtd`
