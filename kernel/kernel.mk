KERNEL_DIR = kernel
KERNEL_SOURCES = $(wildcard $(KERNEL_DIR)/*.c)
KERNEL_OUTFILE = kernel.img

INCLUDE_DIR = include
CFLAGS = -isystem $(INCLUDE_DIR) -O2 -Wall -Wextra -Werror

LINKER_SCRIPT = $(KERNEL_DIR)/link.ld
LDFLAGS = -T $(LINKER_SCRIPT)

include kernel/bootloader/*.mk

$(OUTDIR)/$(KERNEL_OUTFILE): $(BOOTLOADER_SOURCES) $(KERNEL_SOURCES)
	mkdir -p $(OUTDIR)
	$(CC) -nostdlib $(CFLAGS) $(LDFLAGS) $? -o $@

qemu: $(OUTDIR)/$(KERNEL_OUTFILE)
	qemu-system-aarch64 -M raspi3b -kernel $<
