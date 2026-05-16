# nslookup

`nslookup` resolves a host name to an IPv4 address through the userspace DNS
client.

## Usage

```text
nslookup <name>
nslookup --help
```

## Behavior

- Reads the nameserver address from `/etc/resolve.conf`
- Calls `resolveA` to perform an A-record lookup
- Prints the server, queried name, and resolved IPv4 address
- Exits with status `1` when no A record is found

## Boundaries and Notes

- Only A-record lookup is supported
- DNS transport depends on `netd` and UDP support
- The resolve config parser assumes the current simple `nameserver <ip>` format
