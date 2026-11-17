# X16 Write - build with Prog8 12.3.x (https://prog8.readthedocs.io) + 64tass.
# PROG8C = compiler command, e.g.  make PROG8C="java -jar ~/prog8c-12.3.5-all.jar"
# Output goes to build/ (git-ignored). `make sd SD=/path/to/sdcard` also copies the files there.
PROG8C ?= prog8c
export PROG8C

.PHONY: all sd run clean
all:
	./build-cloud.sh

sd:
	./build-cloud.sh $(SD)

run: all
	cd build && x16emu -prg x16wp.prg -run

clean:
	rm -rf build
