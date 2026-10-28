# GNU Make entry point for cross-building LIBCx with the OS/2 EMX toolchain.
# Run inside the project's Nix shell; outputs stay outside this source tree.

.DEFAULT_GOAL := all

LIBCX_ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
OS2EMX_PREFIX ?= /data/os2emx
OS2EMX_TARGET ?= i686-pc-os2-emx
OS2EMX_SYSROOT ?= $(OS2EMX_PREFIX)/$(OS2EMX_TARGET)
OS2EMX_INSTALL_ROOT ?= $(OS2EMX_PREFIX)
OS2EMX_BUILD_ROOT ?= /data/build-nix
BUILD_DIR ?= $(OS2EMX_BUILD_ROOT)/libcx-os2
OS2TK45_INCLUDE_DIR ?= /data/os2tk45/h
OS2EMX_RUNTIME_LIBDIR ?= $(OS2EMX_SYSROOT)/lib
PREFIX ?= /usr
# Install into the active target sysroot by default; override DESTDIR to stage.
DESTDIR ?= $(OS2EMX_SYSROOT)
LIBDIR ?= $(PREFIX)/lib
PREFIX_DESTDIR ?= $(OS2EMX_INSTALL_ROOT)
PREFIX_LIBDIR ?= /lib
INSTALL ?= install

ifeq ($(strip $(OS2EMX_CC)),)
OS2EMX_CC := $(OS2EMX_PREFIX)/bin/$(OS2EMX_TARGET)-gcc
endif
ifeq ($(strip $(OS2EMX_EMXIMP)),)
OS2EMX_EMXIMP := $(OS2EMX_PREFIX)/bin/emximp
endif

CC := $(OS2EMX_CC)
EMXIMP := $(OS2EMX_EMXIMP)

DLL_NAME := libcx0.dll
IMPORT_LIB0 := libcx0.lib
IMPORT_LIB := libcx.lib
IMPORT_ARCHIVE0 := libcx0.a
IMPORT_ARCHIVE := libcx.a

# Match the source list in src/Makefile.kmk.  Keep every object under BUILD_DIR.
C_SOURCES := \
	src/fcntl/fcntl.c \
	src/pwrite/pwrite.c \
	src/poll/poll.c \
	src/select/select.c \
	src/mmap/mmap.c \
	src/exeinfo/exeinfo.c \
	src/beginthread.c \
	src/spawn/spawn2.c \
	src/net/getaddrinfo.c \
	src/net/getifaddrs.c \
	src/net/if_nameindex.c \
	src/shmem/shmem.c \
	src/libcx/handles.c \
	src/libcx/interrupt.c \
	src/lend/ld32.c \
	src/main.c \
	src/shared.c

OBJECTS := $(patsubst src/%.c,$(BUILD_DIR)/obj/%.o,$(C_SOURCES)) \
	$(BUILD_DIR)/obj/main_asm.obj
DLL := $(BUILD_DIR)/$(DLL_NAME)
IMPORT_LIB0_OUT := $(BUILD_DIR)/$(IMPORT_LIB0)
IMPORT_LIB_OUT := $(BUILD_DIR)/$(IMPORT_LIB)
IMPORT_ARCHIVE0_OUT := $(BUILD_DIR)/$(IMPORT_ARCHIVE0)
IMPORT_ARCHIVE_OUT := $(BUILD_DIR)/$(IMPORT_ARCHIVE)

SYSROOT_FLAGS := --sysroot=$(OS2EMX_SYSROOT) \
	-idirafter $(OS2EMX_SYSROOT)/include/os2tk45
INCLUDE_FLAGS := -I$(BUILD_DIR)/include \
	-I$(LIBCX_ROOT)/src -I$(LIBCX_ROOT)/src/poll -I$(LIBCX_ROOT)/src/mmap \
	-I$(LIBCX_ROOT)/src/shmem
TARGET_CFLAGS ?= -Zomf -g -O2
TARGET_ASFLAGS ?= -x assembler-with-cpp -Zomf

RUNTIME_LIB_FLAGS := $(if $(strip $(OS2EMX_RUNTIME_LIBDIR)),-L$(OS2EMX_RUNTIME_LIBDIR))

LINK_FLAGS ?= -Zomf -Zdll -Zhigh-mem -Zmap=$(BUILD_DIR)/libcx0.map
# libcx0 is the library being built; linking it against -lcx would request the
# separate cx_s.a runtime and create a circular/self dependency.
LIBS ?= -Zcrtdll

.PHONY: all check-toolchain install install-prefix clean
all: $(DLL) $(IMPORT_LIB0_OUT) $(IMPORT_LIB_OUT) \
	$(IMPORT_ARCHIVE0_OUT) $(IMPORT_ARCHIVE_OUT)

check-toolchain:
	@test -x "$(CC)" || { echo "OS/2 compiler not executable: $(CC)" >&2; exit 1; }
	@test -x "$(EMXIMP)" || { echo "emximp not executable: $(EMXIMP)" >&2; exit 1; }
	@test -x "$(OS2EMX_PREFIX)/bin/emxomfld" || { echo "emxomfld missing below $(OS2EMX_PREFIX)/bin" >&2; exit 1; }
	@test -f "$(OS2EMX_SYSROOT)/include/stdlib.h" || { echo "Target sysroot is incomplete: $(OS2EMX_SYSROOT)" >&2; exit 1; }
	@test -f "$(OS2TK45_INCLUDE_DIR)/newexe.h" || { echo "OS/2 Toolkit header missing: $(OS2TK45_INCLUDE_DIR)/newexe.h" >&2; exit 1; }
	@test -f "$(OS2TK45_INCLUDE_DIR)/exe386.h" || { echo "OS/2 Toolkit header missing: $(OS2TK45_INCLUDE_DIR)/exe386.h" >&2; exit 1; }
	@emxomf=`$(CC) -print-prog-name=emxomf`; test -x "$$emxomf" || { echo "Target emxomf converter not executable: $$emxomf" >&2; exit 1; }
	@mkdir -p "$(BUILD_DIR)"
	@mkdir -p "$(BUILD_DIR)/include/os2tk45"
	@ln -sf "$(OS2TK45_INCLUDE_DIR)/newexe.h" "$(BUILD_DIR)/include/os2tk45/newexe.h"
	@ln -sf "$(OS2TK45_INCLUDE_DIR)/exe386.h" "$(BUILD_DIR)/include/os2tk45/exe386.h"

$(BUILD_DIR)/obj/%.o: $(LIBCX_ROOT)/src/%.c | check-toolchain
	@mkdir -p "$(@D)"
	$(CC) $(SYSROOT_FLAGS) $(TARGET_CFLAGS) $(INCLUDE_FLAGS) -c "$<" -o "$@"

$(BUILD_DIR)/obj/main_asm.obj: $(LIBCX_ROOT)/src/main.s | check-toolchain
	@mkdir -p "$(@D)"
	$(CC) $(SYSROOT_FLAGS) $(TARGET_ASFLAGS) -c "$<" -o "$@"

$(DLL): $(OBJECTS) $(LIBCX_ROOT)/src/libcx.def $(LIBCX_ROOT)/Makefile | check-toolchain
	$(CC) $(SYSROOT_FLAGS) $(LINK_FLAGS) -o "$@" $(OBJECTS) $(RUNTIME_LIB_FLAGS) $(LIBS) "$(LIBCX_ROOT)/src/libcx.def"

$(IMPORT_LIB0_OUT) $(IMPORT_LIB_OUT) $(IMPORT_ARCHIVE0_OUT) $(IMPORT_ARCHIVE_OUT) &: $(DLL) | check-toolchain
	$(EMXIMP) -o "$(IMPORT_LIB0_OUT)" "$<"
	$(EMXIMP) -o "$(IMPORT_LIB_OUT)" "$<"
	$(EMXIMP) -o "$(IMPORT_ARCHIVE0_OUT)" "$<"
	$(EMXIMP) -o "$(IMPORT_ARCHIVE_OUT)" "$<"

install: all
	$(INSTALL) -d "$(DESTDIR)$(LIBDIR)"
	$(INSTALL) -m 755 "$(DLL)" "$(DESTDIR)$(LIBDIR)/$(DLL_NAME)"
	$(INSTALL) -m 644 "$(IMPORT_LIB0_OUT)" "$(IMPORT_LIB_OUT)" \
		"$(IMPORT_ARCHIVE0_OUT)" "$(IMPORT_ARCHIVE_OUT)" "$(DESTDIR)$(LIBDIR)/"

# Also expose the target package from the shared OS/2 prefix, while preserving
# the sysroot copy used by cross-linking. PREFIX_DESTDIR can stage this copy.
install-prefix: all
	$(INSTALL) -d "$(PREFIX_DESTDIR)$(PREFIX_LIBDIR)"
	$(INSTALL) -m 755 "$(DLL)" "$(PREFIX_DESTDIR)$(PREFIX_LIBDIR)/$(DLL_NAME)"
	$(INSTALL) -m 644 "$(IMPORT_LIB0_OUT)" "$(IMPORT_LIB_OUT)" \
		"$(IMPORT_ARCHIVE0_OUT)" "$(IMPORT_ARCHIVE_OUT)" "$(PREFIX_DESTDIR)$(PREFIX_LIBDIR)/"

clean:
	rm -rf "$(BUILD_DIR)"
