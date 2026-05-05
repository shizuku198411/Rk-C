SHELL := /bin/bash

NIM := /home/pyxgun/nim-2.2.10/bin/nim
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
USER_SHELL_BIN := $(BIN_DIR)/shell.bin
USER_APP_NAMES := ls cat mkdir ps rm rmdir date edit ipc kill fsd
USER_APP_BINS := $(foreach app,$(USER_APP_NAMES),$(BIN_DIR)/$(app).bin)
USER_SYSCALL_OBJ := $(OBJ_DIR)/user/lib/syscall.o
USER_ENTRY_OBJ := $(OBJ_DIR)/user/lib/entry.o
USER_LIB_SRCS := $(shell find $(SRC_DIR)/user/lib -type f -name '*.nim' | sort)

OPENSBI_FW ?= opensbi/build/platform/generic/firmware/fw_jump.bin

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

QEMU_ARGS := \
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

.PHONY: all build appfs clean disasm run qemu-run qemu-debug

all: build

build: $(KERNEL_ELF) appfs

$(KERNEL_ELF): $(NIM_SRCS) $(ASM_OBJS) $(LINKER_SCRIPT) | $(BIN_DIR) $(MAP_DIR) $(NIMCACHE_DIR)
	$(NIM) c $(NIMFLAGS) $(foreach obj,$(ASM_OBJS),--passL:"$(obj)") -o:$@ $(KERNEL_NIM)

$(OBJ_DIR)/%.o: $(SRC_DIR)/%.S
	mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -c -o $@ $<

$(USER_SYSCALL_OBJ): $(SRC_DIR)/user/lib/syscall.S
	mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -c -o $@ $<

$(USER_ENTRY_OBJ): $(SRC_DIR)/user/lib/entry.S
	mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -c -o $@ $<

$(USER_SHELL_ELF): $(SRC_DIR)/user/app_main.nim $(SRC_DIR)/user/apps/shell/shell.nim $(SRC_DIR)/user/panicoverride.nim $(USER_LIB_SRCS) $(USER_SYSCALL_OBJ) $(USER_ENTRY_OBJ) $(USER_LINKER_SCRIPT) | $(BIN_DIR)
	$(NIM) c $(USER_NIMFLAGS) -d:userApp_shell --nimcache:$(USER_NIMCACHE_DIR)/shell --passL:"$(USER_ENTRY_OBJ)" --passL:"$(USER_SYSCALL_OBJ)" --passL:"-Wl,-T,$(USER_LINKER_SCRIPT)" -o:$@ $<

$(USER_SHELL_BIN): $(USER_SHELL_ELF) | $(BIN_DIR)
	$(OBJCOPY) -O binary $< $@

appfs: $(DISK_IMG) $(USER_SHELL_BIN) $(USER_APP_BINS)
	python3 scripts/pack_appfs.py --disk $(DISK_IMG) --bin-dir $(BIN_DIR) --apps shell $(USER_APP_NAMES)

define USER_APP_template
$(BIN_DIR)/$(1).elf: $(SRC_DIR)/user/app_main.nim $(SRC_DIR)/user/apps/$(1)/$(1).nim $(SRC_DIR)/user/panicoverride.nim $$(USER_LIB_SRCS) $(USER_SYSCALL_OBJ) $(USER_ENTRY_OBJ) $(USER_APP_LINKER_SCRIPT) | $(BIN_DIR)
	$$(NIM) c $$(USER_NIMFLAGS) -d:userApp_$(1) --nimcache:$$(USER_NIMCACHE_DIR)/$(1) --passL:"$$(USER_ENTRY_OBJ)" --passL:"$$(USER_SYSCALL_OBJ)" --passL:"-Wl,-T,$$(USER_APP_LINKER_SCRIPT)" -o:$$@ $$<

$(BIN_DIR)/$(1).bin: $(BIN_DIR)/$(1).elf | $(BIN_DIR)
	$$(OBJCOPY) -O binary $$< $$@
endef

$(foreach app,$(USER_APP_NAMES),$(eval $(call USER_APP_template,$(app))))

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

qemu-debug: build
	$(QEMU) $(QEMU_DEBUG_ARGS)

clean:
	rm -rf $(BUILD_DIR) $(BIN_DIR) $(MAP_DIR)
