## Manages TCP connection handles, ports, and socket table lookups.
import ../../../lib/core/syscall
import ../config
import ../state


## Allocates the next TCP connection handle.
proc nextTcpHandle*(net: var NetdState): U32 =
  if net.tcpNextHandle == 0:
    net.tcpNextHandle = 1

  let handle = net.tcpNextHandle
  inc net.tcpNextHandle
  handle


## Allocates the next ephemeral TCP source port.
proc nextTcpPort*(net: var NetdState): U16 =
  if net.tcpNextPort < TcpInitialSourcePort:
    net.tcpNextPort = TcpInitialSourcePort

  let port = net.tcpNextPort
  inc net.tcpNextPort
  if net.tcpNextPort < TcpInitialSourcePort:
    net.tcpNextPort = TcpInitialSourcePort

  port


## Finds a TCP connection by public handle.
proc findTcpByHandle*(net: var NetdState, handle: U32): ptr TcpConnection =
  var i = 0
  while i < TcpMaxConnections:
    if net.tcpConnections[i].used and net.tcpConnections[i].handle == handle:
      return addr net.tcpConnections[i]
    inc i

  nil


## Finds a TCP connection matching an incoming packet tuple.
proc findTcpByPacket*(net: var NetdState, srcIp: U32, srcPort, dstPort: U16): ptr TcpConnection =
  var i = 0
  while i < TcpMaxConnections:
    let conn = addr net.tcpConnections[i]
    if conn.used and conn.remoteIp == srcIp and conn.remotePort == srcPort and
        conn.localPort == dstPort:
      return conn
    inc i

  nil


## Allocates a free TCP connection slot.
proc allocTcpConnection*(net: var NetdState): ptr TcpConnection =
  var i = 0
  while i < TcpMaxConnections:
    if not net.tcpConnections[i].used:
      net.tcpConnections[i] = TcpConnection()
      net.tcpConnections[i].used = true
      net.tcpConnections[i].handle = nextTcpHandle(net)
      return addr net.tcpConnections[i]
    inc i

  nil


## Releases a TCP connection slot.
proc releaseTcpConnection*(conn: ptr TcpConnection) =
  if conn != nil:
    conn[] = TcpConnection()
