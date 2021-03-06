LOBJ = zloader.o zImage.o
ZOBJ = spike_hw.o main.o mmc.o ff.o 

LM32_CC=lm32-elf-gcc
LM32_LD=lm32-elf-ld
LM32_OBJCOPY=lm32-elf-objcopy
LM32_OBJDUMP=lm32-elf-objdump

SREC2VRAM ?= ../../tools/srec2vram/srec2vram

VRAMFILE=image.ram

CPU_FLAGS=-mbarrel-shift-enabled -mmultiply-enabled -msign-extend-enabled \
          -mdivide-enabled

CFLAGSL=-MMD -Os -Wall -g -s -fomit-frame-pointer $(CPU_FLAGS)
CFLAGSZ=-MMD -Os -Wall -g -s -fomit-frame-pointer $(CPU_FLAGS)

LLDFLAGS=-nostdlib -nodefaultlibs -Tlinkerloader.ld 
ZLDFLAGS=-nostdlib -nodefaultlibs -Tlinker.ld 
SEGMENTS = -j .text -j .rodata -j .data -j .bss

all: $(VRAMFILE) image.bin

crt0ram.o: crt0ram.S
	$(LM32_CC) $(CFLAGS) -c crt0ram.S

zloader.o: zloader.c
	$(LM32_CC) $(CFLAGSL) -c $<

zImage.o: zImage.c compress convert
	$(LM32_CC) $(CFLAGSL) -c $<

main.o: main.c
	$(LM32_CC) $(CFLAGSZ) -c $<
	
spike_hw.o: spike_hw.c 
	$(LM32_CC) $(CFLAGSZ) -c $<
	
mmc.o: mmc.c
	$(LM32_CC) $(CFLAGSZ) -c $<
	
ff.o: ff.c
	$(LM32_CC) $(CFLAGSZ) -c $<

zImage.c: convert zimage.zbin
	./convert

zimage.zbin: compress zimage.bin zimage.lst
	./compress e zimage.bin zimage.zbin

convert: convert-pc.c zimage.bin
	gcc -o convert convert-pc.c

compress: compressor-pc.c
	g++ -o compress compressor-pc.c

image: crt0ram.o $(LOBJ)
	$(LM32_LD) $(LLDFLAGS) -Map image.map -N -o image crt0ram.o $(LOBJ)

image.lst: image
	$(LM32_OBJDUMP) -h -S $< > $@

image.bin: image
	$(LM32_OBJCOPY) $(SEGMENTS) -O binary image image.bin
	wc -c image.bin
	
zimage: crt0ram.o $(ZOBJ)
	$(LM32_LD) $(ZLDFLAGS) -Map zimage.map -N -o zimage crt0ram.o $(ZOBJ)
	@lm32-elf-size zimage

zimage.lst: zimage
	$(LM32_OBJDUMP) -h -S $< > $@

zimage.bin: zimage
	$(LM32_OBJCOPY) $(SEGMENTS) -O binary zimage zimage.bin

image.srec: image image.lst
	$(LM32_OBJCOPY) $(SEGMENTS) -O srec image image.srec

$(VRAMFILE): image.srec
	$(SREC2VRAM) 4 image.srec 0x00000000 0x2000 > $(VRAMFILE)

clean:
	rm -f compress convert image image.lst image.bin image.srec image.map zimage zimage.lst zimage.bin zimage.map *.o *.d

DEPS := $(wildcard *.d)
ifneq ($(DEPS),)
include $(DEPS)
endif

