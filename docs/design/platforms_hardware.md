# Platform and Hardware Backends

Rk-C keeps common kernel code separate from platform-specific hardware code. The thin dispatcher modules in `src/platform/` choose either the QEMU `virt` backend or the Milk-V Duo 256M backend at compile time.

## Dispatcher Layout

```text
src/platform/
  block_backend.nim
  console_backend.nim
  fs_layout.nim
  interrupt_backend.nim
  memory_layout.nim
  mmio_map.nim
  paging_attrs.nim
  rtc_backend.nim
  service_policy.nim
  shutdown.nim
  status_led.nim
  timer_backend.nim

src/platform/qemu_virt/
  ...

src/platform/milkv_duo256m/
  ...
```

The common kernel should import `src/platform/<feature>.nim`. Direct imports from `qemu_virt` or `milkv_duo256m` should stay limited to the dispatcher or platform bring-up diagnostics.

## QEMU virt Backend

The QEMU backend is the default build target.

| Area | Backend |
| --- | --- |
| Console | emulated 16550 UART at the QEMU virt UART base |
| Block | VirtIO MMIO block |
| Network | VirtIO MMIO net |
| RTC | Goldfish RTC |
| Interrupts | QEMU PLIC S-mode context plus UART RX interrupt |
| Shutdown | SBI shutdown fallback |
| Status LED | no-op |

The QEMU block backend owns VirtIO feature negotiation, queue setup, request submission, timeout recovery, and capacity discovery. The QEMU interrupt backend enables UART RX interrupts through the PLIC and routes input into the shared TTY path.

## Milk-V Duo 256M Backend

The Milk-V Duo 256M backend is selected with `platformMilkVDuo256m`.

| Area | Backend |
| --- | --- |
| Console output | SBI console putchar for stable early/runtime output |
| Console input | UART0 MMIO receive path |
| Block | CV/Sophgo SDHCI-compatible SD host path |
| RTC | Sophgo CV1800 RTC second counter |
| Interrupts | PLIC S-mode context plus UART0 RX interrupt |
| Timer | SBI timer path with platform frequency constants |
| Shutdown | SG2002 RTC power controller sequence, then SBI fallback |
| Status LED | active-high GPIO-controlled onboard blue LED |

The Milk-V memory layout and device constants live in `src/platform/milkv_duo256m/memory_layout.nim` and `src/platform/milkv_duo256m/mmio_map.nim`.

## Console and TTY Input

Console backends normalize UART status bits into the shared TTY input path.

```text
platform UART/SBI input
  -> src/platform/console_backend.nim
  -> src/kernel/dev/tty.nim
  -> fd 0, /dev/stdin, /dev/tty0
```

The runtime TTY currently has one device, `tty0`, with a 4096-byte RX ring. External interrupts drain UART input into this ring and wake sleeping readers. Polling fallback remains available for paths that check readiness before an interrupt arrives.

QEMU and Milk-V UART RX interrupts are routed through their platform PLIC backends. Milk-V additionally acknowledges DW APB UART busy-detect state when needed after draining RX data.

## Block Layout

The common block dispatcher exposes 512-byte block reads, writes, capacity, and sync.

QEMU uses VirtIO block directly with appfs at the logical rootfs start. Milk-V reads and writes the SD card through the SDHCI path, discovers the rootfs partition from MBR, and uses a platform-local appfs block offset during bootstrap. Filesystem code uses `src/platform/fs_layout.nim` instead of assuming a QEMU-only disk.

## RTC

`src/platform/rtc_backend.nim` returns Unix nanoseconds from the active backend.

- QEMU reads Goldfish low/high time registers.
- Milk-V reads the CV1800 second counter when the RTC second pulse is enabled.

Milk-V currently returning zero is considered acceptable when the hardware counter is not initialized by firmware. Network-based time synchronization is a future direction.

## Shutdown and LED

Common shutdown disables supervisor interrupts, calls the platform backend, falls back to SBI shutdown, and finally waits forever.

Milk-V shutdown turns off the status LED, attempts the SG2002 RTC poweroff sequence, then falls back to SBI. The status LED is turned on after userland startup reaches login, making it a simple board-level boot health signal.

## Design Rule

When adding platform-specific behavior, prefer this shape:

```text
common kernel subsystem
  -> src/platform/<feature>.nim
    -> src/platform/qemu_virt/<feature>.nim
    -> src/platform/milkv_duo256m/<feature>.nim
```

Avoid one-off `when platform...` branches inside core kernel logic unless the code is explicitly a bring-up diagnostic or a compile-time boot mode selector.
