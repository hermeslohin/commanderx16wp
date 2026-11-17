# Build with Prog8 (https://prog8.readthedocs.io) -- set PROG8C to your compiler jar
PROG8C ?= $(HOME)/prog8c.jar
all:
	java -jar $(PROG8C) -target cx16 x16wp.p8
run: all
	x16emu -prg x16wp.prg -run
