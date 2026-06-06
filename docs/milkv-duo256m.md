# Milk-V Duo 256M Real-Hardware Execution Guide

This guide describes how to run Rk-C on Milk-V Duo 256M.

The hardware path is experimental. The current port uses the board's existing FSBL/OpenSBI/U-Boot boot chain and replaces the SD boot FIT image with an Rk-C FIT image.

## Hardware

Tested target:

```text
Milk-V Duo 256M
Milk-V Duo USB & Ethernet IOB
3.3 V USB-UART adapter
microSD card
```

UART settings:

```text
baud rate: 115200
data bits: 8
parity: none
stop bits: 1
flow control: none
```

Recommended UART wiring:

```text
USB-UART GND  -> IOB GND
USB-UART TXD  -> IOB RX
USB-UART RXD  -> IOB TX
USB-UART VCC  -> not connected
```

Power the board from the IOB USB Type-C power input. Do not power the board from the USB-UART adapter.

## Boot Model

The board boots through the vendor boot chain:

```text
FSBL
  -> OpenSBI
  -> U-Boot
  -> FIT image from the SD boot partition
  -> Rk-C kernel
```

The Rk-C Milk-V target builds a FIT image with:

```text
kernel image: bin/milkv-duo256m/kernel.bin
load address: 0x80200000
entry point:  0x80200000
FDT:          extracted from the original Milk-V boot.sd
```

The kernel receives the usual RISC-V boot arguments:

```text
a0 = hart ID
a1 = FDT address
```

## Prepare an Official SD Card

First create a normal Milk-V Duo 256M RISC-V SD card from the [official image (milkv-duo256m-musl-riscv64-sd_v2.0.1.img.zip)](https://github.com/milkv-duo/duo-buildroot-sdk-v2/releases/) and verify that Linux boots over UART.

After verification, keep a copy of the original `boot.sd` from the SD boot partition. The Rk-C build uses it as the source for the board DTB.

Example mount flow on a Linux host:

```bash
lsblk
sudo mkdir -p /mnt/rkc-sd-boot
sudo mount /dev/sdX1 /mnt/rkc-sd-boot
mkdir -p /tmp/rkc-sd-boot
cp /mnt/rkc-sd-boot/boot.sd /tmp/rkc-sd-boot/boot.sd
```

Replace `/dev/sdX1` with the SD card's first partition.

## Build the Rk-C FIT Image

Inside the development environment:

```bash
make milkv-fit MILKV_BOOT_SD_SOURCE=/tmp/rkc-sd-boot/boot.sd
```

Output:

```text
bin/milkv-duo256m/boot.sd
```

This target extracts the Milk-V Duo 256M DTB from the source FIT and creates a new FIT image containing the Rk-C kernel.

## Build the Milk-V AppFS Image

Build the appfs image for the Milk-V target:

```bash
make milkv-appfs
```

Output:

```text
bin/milkv-duo256m/appfs.img
```

The current Milk-V filesystem layout expects appfs inside the second MBR partition at local block `4096`:

```text
partition index: 1       # zero-origin, MBR partition 2
local block:     4096
block size:      512 bytes
```

## Install FIT and AppFS with Make

The recommended update path is the `milkv-sd` target. It builds the Milk-V FIT image and AppFS image, then writes both to the SD card.

```bash
make milkv-sd SD=sdX
```

Example:

```bash
make milkv-sd SD=sdb
```

This target performs the following operations:

```text
/dev/sdX1:/boot.sd                         <- bin/milkv-duo256m/boot.sd
/dev/sdX at partition2_start + 4096 blocks <- bin/milkv-duo256m/appfs.img
```

The target expects an SD card layout compatible with the official Milk-V Duo 256M image:

```text
/dev/sdX1  FAT boot partition
/dev/sdX2  rootfs partition used by Rk-C's SD-backed rootfs/appfs layout
```

Safety checks are intentionally conservative:

- `SD` must be specified.
- The target must be a block device.
- The detected root disk is refused.
- The second partition must not be mounted while AppFS is written.

Use the manual steps below when inspecting or debugging the SD layout directly.

## Install the Rk-C FIT Image

Back up the original `boot.sd`, then copy the generated Rk-C FIT image to the SD boot partition:

```bash
sudo cp /mnt/rkc-sd-boot/boot.sd /mnt/rkc-sd-boot/boot.sd.orig
sudo cp bin/milkv-duo256m/boot.sd /mnt/rkc-sd-boot/boot.sd
sync
```

## Install the AppFS Image

Find the second partition start block:

```bash
lsblk -o NAME,SIZE,TYPE,FSTYPE,START,MOUNTPOINT /dev/sdX
```

Replace `/dev/sdX` with the SD card device, not a partition path. The start block of `/dev/sdX2` is the base block for the second partition.

Write `appfs.img` to local block `4096` inside the second partition:

```bash
PART2_START=$(lsblk -nr -o NAME,START /dev/sdX | awk '$1 == "sdX2" { print $2 }')
sudo dd if=bin/milkv-duo256m/appfs.img of=/dev/sdX bs=512 seek=$((PART2_START + 4096)) conv=notrunc status=progress
sync
```

Adjust `sdX` and `sdX2` to match your environment.

A more explicit version is:

```bash
# Example only. Replace 262145 with your actual partition-2 start block.
sudo dd if=bin/milkv-duo256m/appfs.img of=/dev/sdX bs=512 seek=$((262145 + 4096)) conv=notrunc status=progress
sync
```

Be careful to write to the SD card device. Writing to the wrong block device can destroy host data.

## Boot on the Board

Unmount the SD card:

```bash
sudo umount /mnt/rkc-sd-boot
sync
```

Then:

```text
1. Insert the microSD card into the Milk-V Duo 256M.
2. Attach the Duo to the IOB.
3. Connect USB-UART GND/TX/RX to the IOB UART header.
4. Open a serial terminal at 115200 8N1.
5. Power the IOB from USB Type-C.
```

Expected boot flow:

```text
FSBL log
OpenSBI log
U-Boot log
Loading kernel from FIT Image
Starting kernel ...
[boot] initial setup:
...
+-----------------------------------------+
|            Welcome to Rk-C!             |
+-----------------------------------------+
login:
```

## Login

Default Rk-C accounts:

```text
username: root, password: root
username: rkc,  password: rkc
```

Example checks:

```text
rkc@Rk-C:/home/rkc$ id
rkc@Rk-C:/home/rkc$ df
rkc@Rk-C:/home/rkc$ svc status
rkc@Rk-C:/home/rkc$ ps -l
```

## Diagnostic Bring-Up Image

A smaller diagnostic bring-up image can be built with:

```bash
make milkv-bringup-fit MILKV_BOOT_SD_SOURCE=/tmp/rkc-sd-boot/boot.sd
```

Output:

```text
bin/milkv-duo256m-bringup/boot.sd
```

Copy it to the SD boot partition as `boot.sd` to run the diagnostic bring-up path.

A raw bring-up kernel can also be built with:

```bash
make milkv-bringup
```

The Makefile prints suggested U-Boot commands for loading the ELF or binary image manually.

## Useful Make Targets

```bash
make milkv-help
make milkv-fit MILKV_BOOT_SD_SOURCE=/tmp/rkc-sd-boot/boot.sd
make milkv-appfs
make milkv-bringup-fit MILKV_BOOT_SD_SOURCE=/tmp/rkc-sd-boot/boot.sd
make milkv-bringup
```

## Troubleshooting

### UART output is garbled

Check serial settings:

```text
115200 8N1, flow control none
```

### No UART output

Check:

* GND is connected.
* TX/RX are crossed.
* The USB-UART adapter is opened on the correct COM/TTY port.
* The IOB is powered from USB Type-C.
* The SD card is inserted.

### U-Boot starts but Rk-C does not

Check:

* The generated `bin/milkv-duo256m/boot.sd` was copied to the first SD partition as `boot.sd`.
* `MILKV_BOOT_SD_SOURCE` pointed to the original Milk-V `boot.sd` when building the FIT image.
* The FIT image load and entry addresses are `0x80200000`.

### Rk-C starts but `/bin` is missing or login fails

Check:

* `make milkv-appfs` completed successfully.
* `appfs.img` was written to local block `4096` inside the second MBR partition.
* The SD card device and partition start block were correct when running `dd`.
