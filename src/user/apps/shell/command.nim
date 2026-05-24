## Parses shell command lines and runs apps with pipes, redirection, or bg mode.
import ../../lib/core/io
import ../../lib/core/strutils
import ../../lib/core/pathutils
import ../../lib/core/syscall
import ../../../lib/service_catalog
import ./state


## Includes parses command names, arguments, background markers, and executable paths.
include ./internal/command_parse


## Includes executes shell commands with pipes, redirection, and child waiting.
include ./internal/command_execute
