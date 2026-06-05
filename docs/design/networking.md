# Networking

Networking is implemented primarily in the userland `netd` service. The kernel exposes raw network device syscalls only to the registered network service with `sys_raw_net`.

## Platform Status

QEMU `virt` is the primary network development target and uses VirtIO MMIO net.

Milk-V Duo 256M currently boots the core OS with `svcmgtd --no-network`; real-board Ethernet is intentionally outside the current UART/SD/bootstrap milestone.

## Device Boundary

```text
kernel raw net syscalls
  -> platform net device path
  -> /bin/netd
  -> IPC service protocols
  -> user apps
```

Normal apps should not use raw net syscalls. They talk to `netd` through IPC request/reply helpers.

## Static Network Configuration

The QEMU development configuration defaults to:

```text
address: 10.0.1.10
subnet:  255.255.255.0
gateway: 10.0.1.1
DNS:     8.8.8.8
```

Configuration is also represented through files such as `/etc/interface.conf`.

## netd Modules

`netd` is split by protocol:

```text
src/user/server/netd/
  packet.nim
  state.nim
  config.nim
  arp.nim
  ipv4.nim
  icmp.nim
  udp.nim
  tcp.nim
  netd.nim
```

Implemented layers:

- Ethernet frame parsing/building
- ARP request/reply
- IPv4 packet handling
- ICMP echo request/reply
- UDP send/receive service API
- DNS client support through UDP
- TCP client connection, send, receive, and close paths

## User Libraries

Reusable userland network helpers live under `src/user/lib/net/`.

Important modules:

- `net_dns.nim`: DNS lookup helper.
- `net_tcp.nim`: TCP client helper over netd IPC.
- `net_http.nim`: HTTP request/response helper.
- `net_tls.nim`: experimental TLS client path.
- `crypto/`: SHA-256, HKDF, X25519, ChaCha20, Poly1305, AEAD helpers.

`curl` uses these helpers rather than carrying all HTTP/TLS logic locally.

## User Commands

Network-facing commands:

```text
ping
nslookup
tcpcheck
curl
```

`curl` supports HTTP and experimental HTTPS. It can show TLS version/cipher and optionally include HTTP headers.

## TLS Status

TLS is a learning implementation, not a production-security implementation.

Implemented pieces include:

- TLS 1.3 client path groundwork
- X25519
- HKDF/SHA-256
- ChaCha20-Poly1305
- entropy syscall usage
- HTTP over TLS integration

Certificate trust validation, mTLS, robust retransmission, full TLS alert handling, and broad cipher suite negotiation remain future work.

## Design Constraints

- Keep UDP/TCP generic enough for future apps, not hard-coded to DNS or curl.
- Keep raw device access restricted to netd.
- Keep protocol parsing split by layer.
- Do not enable netd by default on Milk-V until the board Ethernet path is intentionally brought up.
