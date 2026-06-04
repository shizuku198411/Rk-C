SHELL := /bin/bash

NIM := ~/nim-2.2.10/bin/nim
CC := clang
OBJDUMP := llvm-objdump
OBJCOPY := llvm-objcopy
QEMU := qemu-system-riscv64

TARGET := riscv64-unknown-elf
GDB_PORT ?= 1234

SRC_DIR := src
ARCH_DIR := $(SRC_DIR)/arch/riscv64
BUILD_DIR := build
OBJ_DIR := $(BUILD_DIR)/obj
BIN_DIR := bin
MAP_DIR := map
NIMCACHE_DIR := $(BUILD_DIR)/nimcache
USER_NIMCACHE_DIR := $(BUILD_DIR)/user_nimcache
MILKV_NIMCACHE_DIR := $(BUILD_DIR)/milkv_nimcache
MILKV_BRINGUP_NIMCACHE_DIR := $(BUILD_DIR)/milkv_bringup_nimcache
MILKV_BUILD_DIR := $(BUILD_DIR)/milkv-duo256m
SHARED_LIB_SRCS := $(shell find $(SRC_DIR)/lib -type f -name '*.nim' | sort)
VERSION_FILE := VERSION
GENERATED_DIR := $(SRC_DIR)/generated
GENERATED_VERSION := $(GENERATED_DIR)/version.nim
VERSION_GENERATOR := scripts/generate_version.py

KERNEL_NIM := $(SRC_DIR)/kernel.nim
NIM_SRCS := $(shell find $(SRC_DIR) -type f -name '*.nim' | sort)
ASM_SRCS := \
	$(ARCH_DIR)/boot.S \
	$(ARCH_DIR)/sbi.S \
	$(ARCH_DIR)/csr.S \
	$(ARCH_DIR)/trap.S \
	$(ARCH_DIR)/context.S

LINKER_SCRIPT := $(SRC_DIR)/kernel.ld
USER_LINKER_SCRIPT := $(SRC_DIR)/user/user.ld
USER_APP_LINKER_SCRIPT := $(SRC_DIR)/user/app.ld

ASM_OBJS := $(patsubst $(SRC_DIR)/%.S,$(OBJ_DIR)/%.o,$(ASM_SRCS))

KERNEL_ELF := $(BIN_DIR)/kernel.elf
MILKV_BIN_DIR := $(BIN_DIR)/milkv-duo256m
MILKV_BRINGUP_BIN_DIR := $(BIN_DIR)/milkv-duo256m-bringup
MILKV_KERNEL_ELF := $(MILKV_BIN_DIR)/kernel.elf
MILKV_KERNEL_BIN := $(MILKV_BIN_DIR)/kernel.bin
MILKV_FIT := $(MILKV_BIN_DIR)/boot.sd
MILKV_APPFS_IMG := $(MILKV_BIN_DIR)/appfs.img
MILKV_BRINGUP_KERNEL_ELF := $(MILKV_BRINGUP_BIN_DIR)/kernel.elf
MILKV_BRINGUP_KERNEL_BIN := $(MILKV_BRINGUP_BIN_DIR)/kernel.bin
MILKV_BRINGUP_FIT := $(MILKV_BRINGUP_BIN_DIR)/boot.sd
KERNEL_MAP := $(MAP_DIR)/kernel.map
MILKV_KERNEL_MAP := $(MAP_DIR)/milkv-duo256m-kernel.map
MILKV_BRINGUP_KERNEL_MAP := $(MAP_DIR)/milkv-duo256m-bringup-kernel.map
DISK_IMG := $(BIN_DIR)/disk.img

USER_SHELL_ELF := $(BIN_DIR)/shell.elf
USER_SHELL_RKX := $(BIN_DIR)/shell.rkx

USER_APP_NAMES := \
	login ls cat mkdir ps rm rmdir date edit ipc kill svc ping nslookup tcpcheck \
	curl stracectl dmesg rkxinfo echo touch cp mv df wc paniclog id chmod chown passwd \
	whoami sudo shutdown which

USER_SERVER_NAMES := svcmgtd procmgtd fsd blockd procfsd netd userd

USER_ORC_APP_NAMES := rkxinfo ps svc
USER_ORC_SERVER_NAMES := procfsd

TEST_APP_NAMES := faultcheck capcheck pollcheck signalcheck writecheck heapcheck inputcheck
ORC_TEST_APP_NAMES := orccheck
APPFS_EXTRA_APPS ?=

MODULES_DIR ?= modules
RKC_TOOLCHAIN_DIR := $(MODULES_DIR)/rkc-toolchain
RKC_TOOLCHAIN_MK := $(RKC_TOOLCHAIN_DIR)/module.mk
OPTIONAL_APP_RKXS :=
OPTIONAL_APPFS_NAMES :=
OPTIONAL_TEST_APP_RKXS :=
OPTIONAL_TEST_APPFS_NAMES :=

ifneq ($(wildcard $(RKC_TOOLCHAIN_MK)),)
include $(RKC_TOOLCHAIN_MK)
else
$(info optional module rkc-toolchain is not present; skipping toolchain apps)
endif

USER_PACK_NAMES := $(filter-out tcpcheck curl,$(USER_APP_NAMES)) $(USER_SERVER_NAMES) tcpcheck curl $(OPTIONAL_APPFS_NAMES)

USER_APP_RKXS := $(foreach app,$(USER_APP_NAMES),$(BIN_DIR)/$(app).rkx)
USER_SERVER_RKXS := $(foreach server,$(USER_SERVER_NAMES),$(BIN_DIR)/$(server).rkx)
TEST_APP_RKXS := $(foreach app,$(TEST_APP_NAMES) $(ORC_TEST_APP_NAMES),$(BIN_DIR)/$(app).rkx)
TEST_APPS_ARGS ?= --boot-timeout 60 --command-recover-timeout 30

USER_APP_ELFS := $(foreach app,$(USER_APP_NAMES),$(BIN_DIR)/$(app).elf)
USER_SERVER_ELFS := $(foreach server,$(USER_SERVER_NAMES),$(BIN_DIR)/$(server).elf)

USER_SYSCALL_OBJ := $(OBJ_DIR)/user/lib/runtime/syscall.o
USER_ENTRY_OBJ := $(OBJ_DIR)/user/lib/runtime/entry.o

USER_LIB_SRCS := $(shell find $(SRC_DIR)/user/lib -type f -name '*.nim' | sort)
USER_SERVER_LIB_SRCS := $(shell find $(SRC_DIR)/user/server/lib -type f -name '*.nim' 2>/dev/null | sort)

RKX_TOOL := scripts/make_rkx.py
APPFS_TOOL := scripts/pack_appfs.py

OPENSBI_FW ?= opensbi/build/platform/generic/firmware/fw_jump.bin
QEMU_NET ?= tap
QEMU_USER_NET ?= 10.0.1.0/24
QEMU_USER_HOST ?= 10.0.1.1
QEMU_HOSTFWD ?= tcp::10080-:80
QEMU_TAP_IF ?= tap0
MILKV_LOAD_ADDR ?= 0x80200000
MILKV_ELF_LOAD_ADDR ?= 0x82000000
MILKV_BOOT_SD_SOURCE ?= /tmp/rkc-sd-boot/boot.sd
MILKV_DTB := $(MILKV_BUILD_DIR)/sg2002_milkv_duo256m.dtb
MILKV_FIT_ITS := $(SRC_DIR)/platform/milkv-duo256m/rkc_phase0.its
MILKV_BRINGUP_FIT_ITS := $(MILKV_BUILD_DIR)/rkc_bringup.its

ARCH_FLAGS := \
	-target $(TARGET) \
	-march=rv64gc \
	-mabi=lp64 \
	-mno-relax \
	-mcmodel=medany

CFLAGS := \
	$(ARCH_FLAGS) \
	-O2 \
	-g3 \
	-ffreestanding \
	-fno-builtin \
	-fno-stack-protector \
	-fno-pic \
	-Isrc/include \
	-nostdlib

NIMFLAGS := \
	--os:standalone \
	--cpu:riscv64 \
	--cc:clang \
	--noMain \
	--mm:none \
	--threads:off \
	--panics:off \
	-d:danger \
	--nimcache:$(NIMCACHE_DIR) \
	--passC:"$(ARCH_FLAGS)" \
	--passC:"-ffreestanding" \
	--passC:"-fno-builtin" \
	--passC:"-fno-stack-protector" \
	--passC:"-fno-pic" \
	--passC:"-Isrc/include" \
	--passL:"$(ARCH_FLAGS)" \
	--passL:"-fuse-ld=lld" \
	--passL:"-nostdlib" \
	--passL:"-Wl,-T,$(LINKER_SCRIPT)" \
	--passL:"-Wl,-Map,$(KERNEL_MAP)"

MILKV_COMMON_NIMFLAGS := \
	--os:standalone \
	--cpu:riscv64 \
	--cc:clang \
	--noMain \
	--mm:none \
	--threads:off \
	--panics:off \
	-d:danger \
	-d:platformMilkVDuo256m \
	--passC:"$(ARCH_FLAGS)" \
	--passC:"-ffreestanding" \
	--passC:"-fno-builtin" \
	--passC:"-fno-stack-protector" \
	--passC:"-fno-pic" \
	--passC:"-Isrc/include" \
	--passL:"$(ARCH_FLAGS)" \
	--passL:"-fuse-ld=lld" \
	--passL:"-nostdlib" \
	--passL:"-Wl,-T,$(LINKER_SCRIPT)"

MILKV_NIMFLAGS := \
	$(MILKV_COMMON_NIMFLAGS) \
	--nimcache:$(MILKV_NIMCACHE_DIR) \
	--passL:"-Wl,-Map,$(MILKV_KERNEL_MAP)"

MILKV_BRINGUP_NIMFLAGS := \
	$(MILKV_COMMON_NIMFLAGS) \
	-d:milkvBringup \
	--nimcache:$(MILKV_BRINGUP_NIMCACHE_DIR) \
	--passL:"-Wl,-Map,$(MILKV_BRINGUP_KERNEL_MAP)"

USER_NIMFLAGS := \
	--os:standalone \
	--cpu:riscv64 \
	--cc:clang \
	--noMain \
	--mm:none \
	--threads:off \
	--panics:off \
	-d:danger \
	--path:$(SRC_DIR) \
	--passC:"$(ARCH_FLAGS)" \
	--passC:"-ffreestanding" \
	--passC:"-fno-builtin" \
	--passC:"-fno-stack-protector" \
	--passC:"-fno-pic" \
	--passC:"-Isrc/include" \
	--passL:"$(ARCH_FLAGS)" \
	--passL:"-fuse-ld=lld" \
	--passL:"-nostdlib" \
	--passL:"-Wl,--no-relax"

USER_ORC_MIN_HEAP_PAGES ?= 4
USER_ORC_NIMFLAGS := $(filter-out --mm:none,$(USER_NIMFLAGS)) --mm:orc -d:nimAllocPagesViaMalloc -d:nimMinHeapPages=$(USER_ORC_MIN_HEAP_PAGES)

ifeq ($(QEMU_NET),tap)
QEMU_NETDEV_ARGS := -netdev tap,id=net0,ifname=$(QEMU_TAP_IF),script=no,downscript=no
else
QEMU_NETDEV_ARGS := -netdev user,id=net0,net=$(QEMU_USER_NET),host=$(QEMU_USER_HOST),hostfwd=$(QEMU_HOSTFWD)
endif

QEMU_NET_DEVICE_ARGS := -device virtio-net-device,netdev=net0,bus=virtio-mmio-bus.1

QEMU_ARGS := \
	-machine virt \
	-m 256M \
	-nographic \
	-serial mon:stdio \
	-global virtio-mmio.force-legacy=false \
	-bios $(OPENSBI_FW) \
	-drive file=$(DISK_IMG),format=raw,if=none,id=hd0 \
	-device virtio-blk-device,drive=hd0,bus=virtio-mmio-bus.0 \
	$(QEMU_NETDEV_ARGS) \
	$(QEMU_NET_DEVICE_ARGS) \
	-kernel $(KERNEL_ELF)

QEMU_DEGRADED_ARGS := \
	-machine virt \
	-m 256M \
	-nographic \
	-serial mon:stdio \
	-global virtio-mmio.force-legacy=false \
	-bios $(OPENSBI_FW) \
	-drive file=$(DISK_IMG),format=raw,if=none,id=hd0 \
	-device virtio-blk-device,drive=hd0,bus=virtio-mmio-bus.0 \
	-kernel $(KERNEL_ELF)

QEMU_DEBUG_ARGS := \
	$(QEMU_ARGS) \
	-S \
	-gdb tcp::$(GDB_PORT)

.PHONY: all build build-bins build-test-bins generate-version appfs milkv-appfs clean disasm run qemu-run qemu-run-built degraded-run qemu-debug test-apps net-host-help milkv-bringup milkv-bringup-fit milkv-fit milkv-help

all: build

build: generate-version $(KERNEL_ELF) appfs

build-bins: generate-version $(KERNEL_ELF) $(USER_SHELL_RKX) $(USER_APP_RKXS) $(USER_SERVER_RKXS) $(OPTIONAL_APP_RKXS)

build-test-bins: build-bins $(TEST_APP_RKXS) $(OPTIONAL_TEST_APP_RKXS)

generate-version: $(GENERATED_VERSION)

$(GENERATED_VERSION): $(VERSION_FILE) $(VERSION_GENERATOR) README.md | $(GENERATED_DIR)
	python3 $(VERSION_GENERATOR) --version-file $(VERSION_FILE) --nim-out $(GENERATED_VERSION) --readme README.md

$(KERNEL_ELF): $(NIM_SRCS) $(GENERATED_VERSION) $(ASM_OBJS) $(LINKER_SCRIPT) | $(BIN_DIR) $(MAP_DIR) $(NIMCACHE_DIR)
	$(NIM) c $(NIMFLAGS) $(foreach obj,$(ASM_OBJS),--passL:"$(obj)") -o:$@ $(KERNEL_NIM)

$(MILKV_KERNEL_ELF): $(NIM_SRCS) $(GENERATED_VERSION) $(ASM_OBJS) $(LINKER_SCRIPT) | $(MILKV_BIN_DIR) $(MAP_DIR) $(MILKV_NIMCACHE_DIR)
	$(NIM) c $(MILKV_NIMFLAGS) $(foreach obj,$(ASM_OBJS),--passL:"$(obj)") -o:$@ $(KERNEL_NIM)

$(MILKV_KERNEL_BIN): $(MILKV_KERNEL_ELF) | $(MILKV_BIN_DIR)
	$(OBJCOPY) -O binary $< $@

$(MILKV_BRINGUP_KERNEL_ELF): $(NIM_SRCS) $(GENERATED_VERSION) $(ASM_OBJS) $(LINKER_SCRIPT) | $(MILKV_BRINGUP_BIN_DIR) $(MAP_DIR) $(MILKV_BRINGUP_NIMCACHE_DIR)
	$(NIM) c $(MILKV_BRINGUP_NIMFLAGS) $(foreach obj,$(ASM_OBJS),--passL:"$(obj)") -o:$@ $(KERNEL_NIM)

$(MILKV_BRINGUP_KERNEL_BIN): $(MILKV_BRINGUP_KERNEL_ELF) | $(MILKV_BRINGUP_BIN_DIR)
	$(OBJCOPY) -O binary $< $@

$(MILKV_DTB): | $(MILKV_BUILD_DIR)
	@if [ -f "$(MILKV_BOOT_SD_SOURCE)" ]; then \
		dumpimage -T flat_dt -p 1 -o $@ "$(MILKV_BOOT_SD_SOURCE)"; \
	elif [ -f "$@" ]; then \
		echo "Using cached Milk-V DTB: $@"; \
	else \
		echo "missing Milk-V source FIT: $(MILKV_BOOT_SD_SOURCE)" >&2; \
		exit 1; \
	fi

$(MILKV_FIT): $(MILKV_KERNEL_BIN) $(MILKV_DTB) $(MILKV_FIT_ITS) | $(MILKV_BIN_DIR)
	mkimage -f $(MILKV_FIT_ITS) $@

$(MILKV_BRINGUP_FIT_ITS): $(MILKV_FIT_ITS) | $(MILKV_BUILD_DIR)
	sed \
		-e 's#../../../bin/milkv-duo256m/kernel.bin#../../bin/milkv-duo256m-bringup/kernel.bin#' \
		-e 's#../../../build/milkv-duo256m/sg2002_milkv_duo256m.dtb#sg2002_milkv_duo256m.dtb#' \
		$< > $@

$(MILKV_BRINGUP_FIT): $(MILKV_BRINGUP_KERNEL_BIN) $(MILKV_DTB) $(MILKV_BRINGUP_FIT_ITS) | $(MILKV_BRINGUP_BIN_DIR)
	mkimage -f $(MILKV_BRINGUP_FIT_ITS) $@

$(OBJ_DIR)/%.o: $(SRC_DIR)/%.S
	mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -c -o $@ $<

$(USER_SYSCALL_OBJ): $(SRC_DIR)/user/lib/runtime/syscall.S
	mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -c -o $@ $<

$(USER_ENTRY_OBJ): $(SRC_DIR)/user/lib/runtime/entry.S
	mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -c -o $@ $<

$(USER_SHELL_ELF): $(SRC_DIR)/user/app_main.nim $(shell find $(SRC_DIR)/user/apps/shell -type f -name '*.nim' | sort) $(SRC_DIR)/user/panicoverride.nim $(SHARED_LIB_SRCS) $(USER_LIB_SRCS) $(USER_SYSCALL_OBJ) $(USER_ENTRY_OBJ) $(USER_LINKER_SCRIPT) | $(BIN_DIR)
	$(NIM) c $(USER_ORC_NIMFLAGS) -d:userApp_shell --nimcache:$(USER_NIMCACHE_DIR)/shell --passL:"$(USER_ENTRY_OBJ)" --passL:"$(USER_SYSCALL_OBJ)" --passL:"-Wl,-T,$(USER_LINKER_SCRIPT)" -o:$@ $<

$(USER_SHELL_RKX): $(USER_SHELL_ELF) $(RKX_TOOL) $(SRC_DIR)/user/apps/shell/rkx.toml | $(BIN_DIR)
	python3 $(RKX_TOOL) --elf $< --out $@

appfs: $(DISK_IMG) $(USER_SHELL_RKX) $(USER_APP_RKXS) $(USER_SERVER_RKXS) $(OPTIONAL_APP_RKXS)
	python3 $(APPFS_TOOL) --disk $(DISK_IMG) --bin-dir $(BIN_DIR) --ext rkx --apps shell $(USER_PACK_NAMES) $(APPFS_EXTRA_APPS)

milkv-appfs: $(MILKV_APPFS_IMG)

$(MILKV_APPFS_IMG): $(USER_SHELL_RKX) $(USER_APP_RKXS) $(USER_SERVER_RKXS) $(OPTIONAL_APP_RKXS) | $(MILKV_BIN_DIR)
	python3 $(APPFS_TOOL) --out-image $@ --bin-dir $(BIN_DIR) --ext rkx --apps shell $(USER_PACK_NAMES) $(APPFS_EXTRA_APPS)

define USER_APP_template
$(BIN_DIR)/$(1).elf: $(SRC_DIR)/user/app_main.nim $$(shell find $(SRC_DIR)/user/apps/$(1) -type f -name '*.nim' | sort) $(SRC_DIR)/user/panicoverride.nim $$(SHARED_LIB_SRCS) $$(USER_LIB_SRCS) $(USER_SYSCALL_OBJ) $(USER_ENTRY_OBJ) $(USER_APP_LINKER_SCRIPT) | $(BIN_DIR)
	$$(NIM) c $$(if $$(filter $(1),$$(USER_ORC_APP_NAMES)),$$(USER_ORC_NIMFLAGS),$$(USER_NIMFLAGS)) -d:userApp_$(1) --nimcache:$$(USER_NIMCACHE_DIR)/$(1) --passL:"$$(USER_ENTRY_OBJ)" --passL:"$$(USER_SYSCALL_OBJ)" --passL:"-Wl,-T,$$(USER_APP_LINKER_SCRIPT)" -o:$$@ $$<

$(BIN_DIR)/$(1).rkx: $(BIN_DIR)/$(1).elf $$(RKX_TOOL) $(SRC_DIR)/user/apps/$(1)/rkx.toml | $(BIN_DIR)
	python3 $$(RKX_TOOL) --elf $$< --out $$@
endef

$(foreach app,$(USER_APP_NAMES),$(eval $(call USER_APP_template,$(app))))
$(foreach app,$(TEST_APP_NAMES),$(eval $(call USER_APP_template,$(app))))

$(BIN_DIR)/orccheck.elf: $(SRC_DIR)/user/app_main.nim $(shell find $(SRC_DIR)/user/apps/orccheck -type f -name '*.nim' | sort) $(SRC_DIR)/user/panicoverride.nim $(SHARED_LIB_SRCS) $(USER_LIB_SRCS) $(USER_SYSCALL_OBJ) $(USER_ENTRY_OBJ) $(USER_APP_LINKER_SCRIPT) | $(BIN_DIR)
	$(NIM) c $(USER_ORC_NIMFLAGS) -d:userApp_orccheck --nimcache:$(USER_NIMCACHE_DIR)/orccheck --passL:"$(USER_ENTRY_OBJ)" --passL:"$(USER_SYSCALL_OBJ)" --passL:"-Wl,-T,$(USER_APP_LINKER_SCRIPT)" -o:$@ $<

$(BIN_DIR)/orccheck.rkx: $(BIN_DIR)/orccheck.elf $(RKX_TOOL) $(SRC_DIR)/user/apps/orccheck/rkx.toml | $(BIN_DIR)
	python3 $(RKX_TOOL) --elf $< --out $@

define USER_SERVER_template
$(BIN_DIR)/$(1).elf: $(SRC_DIR)/user/app_main.nim $$(shell find $(SRC_DIR)/user/server/$(1) -type f -name '*.nim' | sort) $$(USER_SERVER_LIB_SRCS) $(SRC_DIR)/user/panicoverride.nim $$(SHARED_LIB_SRCS) $$(USER_LIB_SRCS) $(USER_SYSCALL_OBJ) $(USER_ENTRY_OBJ) $(USER_APP_LINKER_SCRIPT) | $(BIN_DIR)
	$$(NIM) c $$(if $$(filter $(1),$$(USER_ORC_SERVER_NAMES)),$$(USER_ORC_NIMFLAGS),$$(USER_NIMFLAGS)) -d:userApp_$(1) --nimcache:$$(USER_NIMCACHE_DIR)/$(1) --passL:"$$(USER_ENTRY_OBJ)" --passL:"$$(USER_SYSCALL_OBJ)" --passL:"-Wl,-T,$$(USER_APP_LINKER_SCRIPT)" -o:$$@ $$<

$(BIN_DIR)/$(1).rkx: $(BIN_DIR)/$(1).elf $$(RKX_TOOL) $(SRC_DIR)/user/server/$(1)/rkx.toml | $(BIN_DIR)
	python3 $$(RKX_TOOL) --elf $$< --out $$@
endef

$(foreach server,$(USER_SERVER_NAMES),$(eval $(call USER_SERVER_template,$(server))))

$(OBJ_DIR) $(BIN_DIR) $(MILKV_BIN_DIR) $(MILKV_BRINGUP_BIN_DIR) $(MAP_DIR) $(NIMCACHE_DIR) $(MILKV_NIMCACHE_DIR) $(MILKV_BRINGUP_NIMCACHE_DIR) $(MILKV_BUILD_DIR) $(GENERATED_DIR):
	mkdir -p $@

$(DISK_IMG): | $(BIN_DIR)
	truncate -s 16M $@

disasm: $(KERNEL_ELF)
	$(OBJDUMP) -d $(KERNEL_ELF)

run: build
	$(QEMU) $(QEMU_ARGS)

qemu-run: build
	$(QEMU) $(QEMU_ARGS)

qemu-run-built:
	$(QEMU) $(QEMU_ARGS)

degraded-run: build
	$(QEMU) $(QEMU_DEGRADED_ARGS)

qemu-debug: build
	$(QEMU) $(QEMU_DEBUG_ARGS)

test-apps:
	RKC_OPTIONAL_TOOLCHAIN_TESTS="$(wildcard $(RKC_TOOLCHAIN_DIR)/tests/app_cases.py)" RKC_OPTIONAL_TOOLCHAIN_TEST_APPS="$(OPTIONAL_TEST_APPFS_NAMES)" python3 scripts/test_apps.py $(TEST_APPS_ARGS) --skip-network-smoke

milkv-bringup: generate-version $(MILKV_BRINGUP_KERNEL_BIN)
	@echo "Milk-V Duo 256M bring-up images:"
	@echo "  ELF: $(MILKV_BRINGUP_KERNEL_ELF)"
	@echo "  BIN: $(MILKV_BRINGUP_KERNEL_BIN)"
	@echo ""
	@echo "Suggested U-Boot commands:"
	@echo "  fatload mmc 0:1 $(MILKV_ELF_LOAD_ADDR) kernel.elf"
	@echo "  bootelf $(MILKV_ELF_LOAD_ADDR)"
	@echo ""
	@echo "  fatload mmc 0:1 $(MILKV_LOAD_ADDR) kernel.bin"
	@echo "  go $(MILKV_LOAD_ADDR)"

milkv-bringup-fit: generate-version $(MILKV_BRINGUP_FIT)
	@echo "Milk-V Duo 256M bring-up FIT image:"
	@echo "  FIT: $(MILKV_BRINGUP_FIT)"
	@echo ""
	@echo "Copy to SD boot partition as boot.sd to run the diagnostic bring-up path."

milkv-fit: generate-version $(MILKV_FIT)
	@echo "Milk-V Duo 256M FIT image:"
	@echo "  FIT: $(MILKV_FIT)"
	@echo ""
	@echo "Source FIT used for FDT extraction:"
	@echo "  $(MILKV_BOOT_SD_SOURCE)"
	@echo ""
	@echo "Copy to SD boot partition as boot.sd to use the existing U-Boot bootcmd."

milkv-help:
	@echo "Build Milk-V Duo 256M images:"
	@echo "  make milkv-bringup"
	@echo "  make milkv-bringup-fit MILKV_BOOT_SD_SOURCE=/tmp/rkc-sd-boot/boot.sd"
	@echo "  make milkv-fit MILKV_BOOT_SD_SOURCE=/tmp/rkc-sd-boot/boot.sd"
	@echo "  make milkv-appfs"
	@echo ""
	@echo "Copy the full bootstrap FIT to the SD FAT partition:"
	@echo "  $(MILKV_FIT) -> boot.sd"

net-host-help:
	@echo "Default TAP network:"
	@echo "  make run"
	@echo "  guest ip: 10.0.1.10, gateway/host: 10.0.1.1"
	@echo ""
	@echo "User network:"
	@echo "  make run QEMU_NET=user"
	@echo "  guest ip: 10.0.1.10, gateway/host: 10.0.1.1"
	@echo "  qemu user net: QEMU_USER_NET=10.0.1.0/24 QEMU_USER_HOST=10.0.1.1"
	@echo "  note: external ICMP may timeout with QEMU user networking"
	@echo ""
	@echo "TAP host setup:"
	@echo "  sudo ip tuntap add dev tap0 mode tap user $$USER"
	@echo "  sudo ip link set tap0 up"
	@echo "  sudo ip addr add 10.0.1.1/24 dev tap0"
	@echo "  sudo sysctl -w net.ipv4.ip_forward=1"
	@echo "  sudo iptables -t nat -A POSTROUTING -s 10.0.1.0/24 -j MASQUERADE"
	@echo "  make run QEMU_TAP_IF=tap0"

clean:
	rm -rf $(BUILD_DIR) $(BIN_DIR) $(MAP_DIR) $(GENERATED_DIR)
