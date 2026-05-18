# netd

`netd` is the userspace network server that connects the VirtIO network device
to userspace networking APIs. It keeps raw net syscalls restricted to the
managed network service, while applications use IPC requests for ping, UDP, and
TCP operations.

`netd` is an optional service. When VirtIO net is not available, startup failure
or ready timeout is handled as a degraded service state.

## Responsibilities

- Detect and initialize the VirtIO network device
- Read the device MAC address
- Create default `/etc/interface.conf` and `/etc/resolve.conf` files when absent
- Handle IPC requests for ICMP ping, UDP send/receive, and TCP connect/send/receive/close
- Poll raw packet receive and process ARP replies and TCP packets
- Notify `svcmgtd` with a service ready ACK after startup

## RKX Metadata

- `stack_pages = 8`
- capabilities:
  - `sys_raw_net`

`netd` owns raw network syscalls. Applications use IPC and userspace network
client libraries instead of raw packet syscalls.

## Startup Flow

1. `svcmgtd` starts `/bin/netd`
2. `netd` waits until it is registered as `SysServiceKindNet`
3. Missing `/etc/resolve.conf` and `/etc/interface.conf` files are created
4. `sysRawNetInfo`, `sysRawNetInit`, and `sysRawNetMac` initialize VirtIO net
5. IP address, subnet, and gateway are loaded from `interface.conf`
6. TCP handle and ephemeral port counters are initialized
7. `notifyServiceReady(SysServiceKindNet)` sends a ready ACK
8. The main loop polls IPC requests and RX packets

## IPC Requests

- `SysIpcOpNetPingRequest`
  - Sends an ICMP echo request and waits for a reply
- `SysIpcOpNetUdpSendRequest`
  - Resolves ARP and sends a UDP packet
- `SysIpcOpNetUdpReceiveRequest`
  - Waits for a matching UDP packet with timeout
- `SysIpcOpNetTcpConnectRequest`
  - Creates a TCP connection handle using a simple SYN / SYN-ACK / ACK handshake
- `SysIpcOpNetTcpSendRequest`
  - Sends payload on the given connection handle
- `SysIpcOpNetTcpReceiveRequest`
  - Returns payload from the TCP receive buffer
- `SysIpcOpNetTcpCloseRequest`
  - Attempts to close the connection with FIN/ACK

Each request has a corresponding response op. Results are returned through IPC
packet fields such as `arg0` and `data`.

## Module Layout

- `netd.nim`
  - Startup, config file creation, VirtIO net initialization, IPC dispatch, and RX polling
- `state.nim`
  - `NetdState`, TCP connection state, RX/TX buffers, ARP cache, and counters
- `config.nim`
  - Ethernet/IP/TCP/UDP/ICMP constants, timeouts, ports, and MSS values
- `packet.nim`
  - Endian helpers, checksum, MAC/IP printing, and Ethernet frame sending helpers
- `arp.nim`
  - ARP request/reply handling, ARP cache, and next-hop MAC resolution
- `ipv4.nim`
  - IPv4 header construction
- `icmp.nim`
  - ICMP echo request/reply and ping handling
- `udp.nim`
  - UDP packet send, receive wait, and next-hop selection
- `tcp.nim`
  - TCP connection table, handshake, send/receive buffer, and close handling

## Boundaries and Notes

- Packet buffers are limited by `SysNetPacketMax`
- IPC payload copies are limited by `SysIpcMessageMax`
- TCP connections are capped by `TcpMaxConnections`
- Each TCP connection has a `TcpRxBufferMax` receive buffer
- ARP, ICMP, UDP, and TCP waits are implemented with timeout-based polling
- The TCP implementation is intentionally small and educational; retransmission,
  congestion control, and out-of-order packet handling are limited
- HTTPS/TLS is handled outside `netd`, in userspace libraries and applications

## Related Files

- `netd.nim`: server implementation
- `../lib/service_ready.nim`: shared service registration wait and ready ACK helpers
- `src/user/lib/net`: userspace network client helpers
- `src/lib/syscall_types.nim`: net syscall, IPC op, and packet ABI definitions
