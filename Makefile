OUTDIR := out
BOOTLOADER_DIR := bootloader
KERNEL_DIR := kernel

KERNEL_SOURCES := $(wildcard $(KERNEL_DIR)/*.c)
BOOTLOADER_SOURCES := $(wildcard $(BOOTLOADER_DIR)/*.s)

KERNEL_OUTFILE := kernel.img

# Compiler flags
INCLUDE_DIR := include
CFLAGS := -isystem $(INCLUDE_DIR) -nostdlib -O2 -Wall -Wextra -Werror

# Linker flags
LINKER_SCRIPT := link.ld
LDFLAGS := -T $(LINKER_SCRIPT)

# Targets
all: $(OUTDIR)/$(KERNEL_OUTFILE)

qemu: $(OUTDIR)/$(KERNEL_OUTFILE)
	qemu-system-aarch64 -M raspi3b -kernel $<

$(OUTDIR)/$(KERNEL_OUTFILE): $(BOOTLOADER_SOURCES) $(KERNEL_SOURCES)
	mkdir -p $(OUTDIR)
	$(CC) $(CFLAGS) $(LDFLAGS) $? -o $@

clean:
	rm -rf $(OUTDIR)
