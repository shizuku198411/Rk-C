# Networking

Networking is served by the userland `netd` service.

## Device

The low-level device is VirtIO MMIO net on QEMU `virt`. Raw net syscalls are
restricted to `netd`.

Default guest settings:

```text
address: 10.0.1.10
subnet:  255.255.255.0
gateway: 10.0.1.1
DNS:     8.8.8.8
```

## Stack

Implemented or partially implemented layers include:

- Ethernet
- ARP
- IPv4
- ICMP
- UDP
- DNS client
- TCP client path
- HTTP client path
- experimental HTTPS/TLS client path

## User Commands

Network-facing commands include:

```text
ping
nslookup
tcpcheck
curl
```

## HTTPS/TLS Status

The HTTPS path is experimental and intended as a learning implementation.

Implemented pieces include:

- TLS 1.3 client handshake groundwork
- X25519 key exchange
- HKDF/SHA-256 helpers
- ChaCha20-Poly1305 AEAD
- HTTP over TLS transport path

Certificate trust validation, mTLS, entropy integration, retransmission policy,
and broader cipher suite support are future work.

