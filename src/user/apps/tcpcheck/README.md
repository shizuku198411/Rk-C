# tcpcheck

`tcpcheck` is a small TCP connectivity test tool.

## Usage

```text
tcpcheck <ip> <port>
tcpcheck --help
```

## Behavior

- Parses an IPv4 address and TCP port
- Calls `tcpConnect`
- Prints the returned connection handle
- If the target port is `80`, sends a minimal HTTP/1.0 request and prints the
  received response chunk
- Closes the connection with `tcpClose`

## Boundaries and Notes

- Receive buffer size is `RxCap = 512`
- Port `80` is the only mode that sends application data
- Networking depends on `netd` and the userspace TCP helper library
