PROGRAM := $(notdir $(patsubst %/,%,$(CURDIR)))

all: $(PROGRAM).mem

$(PROGRAM).obj: $(PROGRAM).asm
	wla-z80 -i -o $@ $<

$(PROGRAM).bin: $(PROGRAM).obj linkfile.txt
	wlalink -r -v -i linkfile.txt $@

$(PROGRAM).mem: $(PROGRAM).bin
	python3 ../tomem.py $< > $@

clean:
	rm -f *.obj *.lst $(PROGRAM).bin $(PROGRAM).mem

.PHONY:	all run clean
