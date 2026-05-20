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
SHARED_LIB_SRCS := $(shell find $(SRC_DIR)/lib -type f -name '*.nim' | sort)

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
KERNEL_MAP := $(MAP_DIR)/kernel.map
DISK_IMG := $(BIN_DIR)/disk.img

USER_SHELL_ELF := $(BIN_DIR)/shell.elf
USER_SHELL_RKX := $(BIN_DIR)/shell.rkx

USER_APP_NAMES := \
	ls cat mkdir ps rm rmdir date edit ipc kill svc ping nslookup tcpcheck \
	curl stracectl dmesg rkxinfo echo touch cp mv df wc paniclog id chmod chown
USER_SERVER_NAMES := svcmgtd procmgtd fsd blockd procfsd netd userd
TEST_APP_NAMES := faultcheck capcheck pollcheck signalcheck writecheck
APPFS_EXTRA_APPS ?=

USER_PACK_NAMES := $(filter-out tcpcheck curl,$(USER_APP_NAMES)) $(USER_SERVER_NAMES) tcpcheck curl

USER_APP_RKXS := $(foreach app,$(USER_APP_NAMES),$(BIN_DIR)/$(app).rkx)
USER_SERVER_RKXS := $(foreach server,$(USER_SERVER_NAMES),$(BIN_DIR)/$(server).rkx)
TEST_APP_RKXS := $(foreach app,$(TEST_APP_NAMES),$(BIN_DIR)/$(app).rkx)

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

.PHONY: all build build-bins build-test-bins appfs clean disasm run qemu-run qemu-run-built degraded-run qemu-debug test-apps net-host-help

all: build

build: $(KERNEL_ELF) appfs

build-bins: $(KERNEL_ELF) $(USER_SHELL_RKX) $(USER_APP_RKXS) $(USER_SERVER_RKXS)

build-test-bins: build-bins $(TEST_APP_RKXS)

$(KERNEL_ELF): $(NIM_SRCS) $(ASM_OBJS) $(LINKER_SCRIPT) | $(BIN_DIR) $(MAP_DIR) $(NIMCACHE_DIR)
	$(NIM) c $(NIMFLAGS) $(foreach obj,$(ASM_OBJS),--passL:"$(obj)") -o:$@ $(KERNEL_NIM)

$(OBJ_DIR)/%.o: $(SRC_DIR)/%.S
	mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -c -o $@ $<

$(USER_SYSCALL_OBJ): $(SRC_DIR)/user/lib/runtime/syscall.S
	mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -c -o $@ $<

$(USER_ENTRY_OBJ): $(SRC_DIR)/user/lib/runtime/entry.S
	mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -c -o $@ $<

$(USER_SHELL_ELF): $(SRC_DIR)/user/app_main.nim $(SRC_DIR)/user/apps/shell/shell.nim $(SRC_DIR)/user/panicoverride.nim $(SHARED_LIB_SRCS) $(USER_LIB_SRCS) $(USER_SYSCALL_OBJ) $(USER_ENTRY_OBJ) $(USER_LINKER_SCRIPT) | $(BIN_DIR)
	$(NIM) c $(USER_NIMFLAGS) -d:userApp_shell --nimcache:$(USER_NIMCACHE_DIR)/shell --passL:"$(USER_ENTRY_OBJ)" --passL:"$(USER_SYSCALL_OBJ)" --passL:"-Wl,-T,$(USER_LINKER_SCRIPT)" -o:$@ $<

$(USER_SHELL_RKX): $(USER_SHELL_ELF) $(RKX_TOOL) $(SRC_DIR)/user/apps/shell/rkx.toml | $(BIN_DIR)
	python3 $(RKX_TOOL) --elf $< --out $@

appfs: $(DISK_IMG) $(USER_SHELL_RKX) $(USER_APP_RKXS) $(USER_SERVER_RKXS)
	python3 $(APPFS_TOOL) --disk $(DISK_IMG) --bin-dir $(BIN_DIR) --ext rkx --apps shell $(USER_PACK_NAMES) $(APPFS_EXTRA_APPS)

define USER_APP_template
$(BIN_DIR)/$(1).elf: $(SRC_DIR)/user/app_main.nim $$(wildcard $(SRC_DIR)/user/apps/$(1)/*.nim) $(SRC_DIR)/user/panicoverride.nim $$(SHARED_LIB_SRCS) $$(USER_LIB_SRCS) $(USER_SYSCALL_OBJ) $(USER_ENTRY_OBJ) $(USER_APP_LINKER_SCRIPT) | $(BIN_DIR)
	$$(NIM) c $$(USER_NIMFLAGS) -d:userApp_$(1) --nimcache:$$(USER_NIMCACHE_DIR)/$(1) --passL:"$$(USER_ENTRY_OBJ)" --passL:"$$(USER_SYSCALL_OBJ)" --passL:"-Wl,-T,$$(USER_APP_LINKER_SCRIPT)" -o:$$@ $$<

$(BIN_DIR)/$(1).rkx: $(BIN_DIR)/$(1).elf $$(RKX_TOOL) $(SRC_DIR)/user/apps/$(1)/rkx.toml | $(BIN_DIR)
	python3 $$(RKX_TOOL) --elf $$< --out $$@
endef

$(foreach app,$(USER_APP_NAMES),$(eval $(call USER_APP_template,$(app))))
$(foreach app,$(TEST_APP_NAMES),$(eval $(call USER_APP_template,$(app))))

define USER_SERVER_template
$(BIN_DIR)/$(1).elf: $(SRC_DIR)/user/app_main.nim $$(wildcard $(SRC_DIR)/user/server/$(1)/*.nim) $$(USER_SERVER_LIB_SRCS) $(SRC_DIR)/user/panicoverride.nim $$(SHARED_LIB_SRCS) $$(USER_LIB_SRCS) $(USER_SYSCALL_OBJ) $(USER_ENTRY_OBJ) $(USER_APP_LINKER_SCRIPT) | $(BIN_DIR)
	$$(NIM) c $$(USER_NIMFLAGS) -d:userApp_$(1) --nimcache:$$(USER_NIMCACHE_DIR)/$(1) --passL:"$$(USER_ENTRY_OBJ)" --passL:"$$(USER_SYSCALL_OBJ)" --passL:"-Wl,-T,$$(USER_APP_LINKER_SCRIPT)" -o:$$@ $$<

$(BIN_DIR)/$(1).rkx: $(BIN_DIR)/$(1).elf $$(RKX_TOOL) $(SRC_DIR)/user/server/$(1)/rkx.toml | $(BIN_DIR)
	python3 $$(RKX_TOOL) --elf $$< --out $$@
endef

$(foreach server,$(USER_SERVER_NAMES),$(eval $(call USER_SERVER_template,$(server))))

$(OBJ_DIR) $(BIN_DIR) $(MAP_DIR) $(NIMCACHE_DIR):
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
	python3 scripts/test_apps.py --boot-timeout 60 --command-recover-timeout 30

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
	rm -rf $(BUILD_DIR) $(BIN_DIR) $(MAP_DIR)
