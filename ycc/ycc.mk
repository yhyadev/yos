YCC_DIR = ycc
YCC_SOURCES = $(wildcard $(YCC_DIR)/*.c)
YCC_OUTFILE = ycc

INCLUDE_DIR = include
CFLAGS = -isystem $(INCLUDE_DIR) -O2 -Wall -Wextra -Werror

$(OUTDIR)/$(YCC_OUTFILE): $(YCC_SOURCES)
	mkdir -p $(OUTDIR)
	$(CC) $(CFLAGS) $? -o $@
