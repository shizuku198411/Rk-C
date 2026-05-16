# curl

`curl` is a small HTTP/HTTPS fetch utility built on the userspace network
libraries.

## Usage

```text
curl [-v|--tls-info] [-i|--include] <http-url|https-url|host|ip>[/path]
curl --help
```

## Behavior

- Parses HTTP and HTTPS URLs with `parseHttpUrl`
- Supports explicit URL ports such as `http://10.0.1.1:18080/index.html`
- Resolves host names with DNS when the host is not already an IPv4 address
- Starts the request with `httpGetStart`
- Streams response data in 512-byte chunks
- Omits HTTP response headers by default
- Prints headers when `-i` or `--include` is used
- Prints TLS version and cipher when `-v` or `--tls-info` is used
- Short options can be combined, for example `curl -vi https://example.com`

## Boundaries and Notes

- Receive chunks are limited by `RxCap = 512`
- The copied target argument is limited by `ArgCap = 256`
- HTTPS support depends on the experimental userspace TLS stack
- Certificate validation is not currently performed by the TLS path
