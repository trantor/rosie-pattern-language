## -*- Mode: Makefile; -*-                                             
##
## Makefile for some sample C clients of librosie
##
## © Copyright IBM Corporation 2016, 2017, 2018.
## LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
## AUTHOR: Jamie A. Jennings

## Use "DEBUG=1" on the command line to enable logging to stderr

HOME = $(shell cd ../../..; pwd)
ROSIE = "$(HOME)/bin/rosie"

ifdef DEBUG
COPT=-DDEBUG
endif

REPORTED_PLATFORM=$(shell (uname -o || uname -s) 2> /dev/null)
ifeq ($(REPORTED_PLATFORM), Darwin)
PLATFORM=macosx
else ifeq ($(REPORTED_PLATFORM), GNU/Linux)
PLATFORM=linux
else
PLATFORM=none
endif

PLATFORMS = linux macosx windows

default: dynamic static mt

ifeq ($(PLATFORM), macosx)
CC= cc
else
CC= gcc
endif

ifeq ($(PLATFORM),macosx)
CFLAGS += -std=gnu99
SYSCFLAGS=-DLUA_USE_MACOSX
SYSLIBS=-lreadline
SYSLDFLAGS=-undefined error
else 
SYSCFLAGS=-DLUA_USE_LINUX -std=gnu99 -D_GNU_SOURCE=1 -fPIC
SYSLDFLAGS=-Wl,--no-undefined
SYSLIBS=-lpthread -lreadline -ldl -lm
endif

CFLAGS= -pthread -O2 -Wall -Wextra -DLUA_COMPAT_5_2 $(COPT) $(SYSCFLAGS) $(MYCFLAGS) 
LDFLAGS= $(SYSLDFLAGS) $(MYLDFLAGS)
LIBS= $(SYSLIBS) $(MYLIBS)

AR= ar rcu
RANLIB= ranlib
RM= rm -f

MYCFLAGS=  -I$(HOME)/submodules/lua/include -I$(HOME)/submodules/rosie-lpeg/src -I..
MYLDFLAGS= 
MYLIBS= 
MYOBJS=

ROSIE_A=../binaries/librosie.a
ROSIE_DYLIB_NAME=rosie

ifeq ($(PLATFORM), macosx)
ROSIE_DYLIB=../binaries/lib$(ROSIE_DYLIB_NAME).dylib
SYSTEM_DYNAMIC_TEST_COMMAND=./dynamic system librosie.dylib
LOCAL_DYNAMIC_TEST_COMMAND=DYLD_LIBRARY_PATH=../binaries ./dynamic local librosie.dylib
else
ROSIE_DYLIB=../binaries/lib$(ROSIE_DYLIB_NAME).so
# Some linux distros may not have DESTDIR on their search path by
# default, like when running as root in a docker image.  (This can be
# checked with `/sbin/ldconfig -v`.) So we explicitly set
# LD_LIBRARY_PATH in the SYSTEM test of the dynamically linked client.
SYSTEM_DYNAMIC_TEST_COMMAND=LD_LIBRARY_PATH=$(DESTDIR)/lib ./dynamic system librosie.so
LOCAL_DYNAMIC_TEST_COMMAND=LD_LIBRARY_PATH=../binaries ./dynamic local librosie.so
endif


dynamic.o: dynamic.c dynamic.h
	$(CC) -o $@ -c dynamic.c $(CFLAGS)

dynamic: dynamic.o 
	$(CC) -o $@ dynamic.o $(SYSLIBS) $(SYSLDFLAGS)

static.o: static.c static.h
	$(CC) -o $@ -c static.c $(CFLAGS)

static: static.o $(ROSIE_A) 
	$(CC) -o $@ static.o $(ROSIE_A) $(SYSLIBS) $(SYSLDFLAGS)

mt.o: mt.c
	$(CC) -o $@ -c mt.c $(CFLAGS)

mt: mt.o $(ROSIE_A)
	$(CC) -o $@ mt.o $(ROSIE_A) $(SYSLIBS) $(SYSLDFLAGS)

clean:
	$(RM) dynamic.o dynamic
	$(RM) static.o static
	$(RM) mt.o mt

depend:
	@$(CC) $(CFLAGS) -MM *.c

test: static dynamic mt
	@echo Running C client tests on librosie
	@echo
	@echo Statically linked test program:
	./static
	@echo
	@echo Dynamically linked test program:
	$(LOCAL_DYNAMIC_TEST_COMMAND)
	@echo
	@echo Multi-threaded, statically linked test program:
	./mt 4 25 $(HOME)/test/logfile 

installtest: static dynamic mt
	@echo Running dynamic C client tests on installed librosie
	@echo
	@echo Dynamically linked test program:
	$(SYSTEM_DYNAMIC_TEST_COMMAND)

echo:
	@echo "HOME= $(HOME)"
	@echo "PLAT= $(PLAT)"
	@echo "CC= $(CC)"
	@echo "CFLAGS= $(CFLAGS)"
	@echo "LDFLAGS= $(LDFLAGS)"
	@echo "LIBS= $(LIBS)"
	@echo "RM= $(RM)"

static.o: static.c static.h 
dynamic.o: dynamic.c dynamic.h 
mt.o: mt.c
