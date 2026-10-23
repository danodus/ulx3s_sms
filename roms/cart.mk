SERIAL ?= /dev/tty.usbserial-D00039
PROGRAM := $(notdir $(patsubst %/,%,$(CURDIR)))

all: $(PROGRAM).sms

$(PROGRAM).obj: $(PROGRAM).asm
	wla-z80 -i -o $@ $<

$(PROGRAM).sms: $(PROGRAM).obj linkfile.txt
	wlalink -r -v -i linkfile.txt $@

run: $(PROGRAM).sms
	python3 ../../tools/load_rom.py $(SERIAL) $(PROGRAM).sms

clean:
	rm -f *.obj *.lst $(PROGRAM).sms

.PHONY:	all run clean
