# X16 Write - build with Prog8 12.3.x (https://prog8.readthedocs.io) + 64tass.
# PROG8C = compiler command, e.g.  make PROG8C="java -jar ~/prog8c-12.3.5-all.jar"
# Output goes to build/ (git-ignored). `make sd SD=/path/to/sdcard` also copies the files there.
# Default: the jar in your home dir; override with PROG8C=... or use prog8c if it is on PATH.
PROG8C ?= java -jar $(HOME)/prog8c.jar
export PROG8C

.PHONY: all sd run run-modem clean
all:
	./build-cloud.sh

sd:
	./build-cloud.sh $(SD)

# old emulator: mouse works (the ximodem build's mouse is currently broken).
# No -uart1 ximodem there, so the ownCloud feature is unavailable; plain SD card use only.
run: all
	cd build && /usr/local/x16emu/x16emu -scale 2 -prg x16wp.prg -run

# new emulator with the ximodem virtual modem on UART1 (needed for ownCloud; mouse is broken in it)
run-modem: all
	cd build && x16emu -ram 2048 -scale 2 -uart1 ximodem -prg x16wp.prg -run

clean:
	rm -rf build
