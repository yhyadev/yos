OUTDIR = out

all: $(OUTDIR)

include **/*.mk

$(OUTDIR): $(OUTDIR)/$(YCC_OUTFILE) $(OUTDIR)/$(KERNEL_OUTFILE)

clean:
	rm -rf $(OUTDIR)
