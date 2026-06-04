## Implements a fixed-capacity byte ring for kernel device queues.
import ../../lib/types


type
  ByteRing*[Capacity: static[int]] = object
    data: array[Capacity, U8]
    head: U64
    tail: U64
    count: U64


## Returns the configured capacity of a byte ring.
proc capacity*[Capacity: static[int]](ring: ByteRing[Capacity]): U64 =
  U64(Capacity)


## Returns the number of buffered bytes.
proc len*[Capacity: static[int]](ring: ByteRing[Capacity]): U64 =
  ring.count


## Returns whether the byte ring is empty.
proc isEmpty*[Capacity: static[int]](ring: ByteRing[Capacity]): bool =
  ring.count == U64(0)


## Returns whether the byte ring is full.
proc isFull*[Capacity: static[int]](ring: ByteRing[Capacity]): bool =
  ring.count == U64(Capacity)


## Pushes one byte when capacity is available.
proc push*[Capacity: static[int]](ring: var ByteRing[Capacity], value: U8): bool =
  if ring.isFull():
    return false

  ring.data[ring.tail] = value
  ring.tail = (ring.tail + U64(1)) mod U64(Capacity)
  inc ring.count
  true


## Pops one byte when data is available.
proc pop*[Capacity: static[int]](ring: var ByteRing[Capacity], value: var U8): bool =
  if ring.isEmpty():
    return false

  value = ring.data[ring.head]
  ring.head = (ring.head + U64(1)) mod U64(Capacity)
  dec ring.count
  true
