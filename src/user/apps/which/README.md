# which

`which` prints the executable path selected by the shell command search policy.

## Usage

```text
which <command> [command...]
which --help
```

## Search Order

- An absolute or slash-containing path is resolved explicitly
- `/home/<current-user>/bin/<command>`
- `/usr/bin/<command>`
- `/bin/<command>`

## RKX Metadata

- `stack_pages = 2`
- capabilities: none
