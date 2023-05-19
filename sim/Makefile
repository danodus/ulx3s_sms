CART ?= ../roms/hello_world.sms

VERILATOR = verilator

LDFLAGS := -LDFLAGS "$(shell sdl2-config --libs)"
CFLAGS := -CFLAGS "$(shell sdl2-config --cflags)"

all: sim

clean:
	rm -rf obj_dir

sim: top.v sim_main.cpp $(PROGRAM)
	$(VERILATOR) -cc --exe $(CFLAGS) $(LDFLAGS) top.v ../src/sigmadelta.v sim_main.cpp -I../src -I../src/Z80 -Wno-PINMISSING -Wno-WIDTH -Wno-CASEINCOMPLETE -Wno-TIMESCALEMOD -Wno-NULLPORT -Wno-UNOPTFLAT -Wno-LITENDIAN -Wno-CASEX -Wno-INITIALDLY --no-timing --language 1364-2001
	$(MAKE) -j 4 -C obj_dir -f Vtop.mk

run: sim
	cp $(CART) cart.rom
	obj_dir/Vtop

.PHONY: all clean
