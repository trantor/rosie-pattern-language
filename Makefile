## ----------------------------------------------------------------------------- ##
## Customizable options:

DESTDIR=/usr/local

## End of customizable options
## ----------------------------------------------------------------------------- ##

REPORTED_PLATFORM=$(shell (uname -o || uname -s) 2> /dev/null)
ifeq ($(REPORTED_PLATFORM), Darwin)
PLATFORM=macosx
else ifeq ($(REPORTED_PLATFORM), GNU/Linux)
PLATFORM=linux
else
PLATFORM=none
endif

PLATFORMS = linux macosx windows

## submodule names
ARGPARSE = argparse
LUA = lua
LPEG = rosie-lpeg
JSON = lua-cjson
READLINE = lua-readline

BUILD_ROOT = $(shell pwd)

# Note: Most of the installation is arch-dependent (compiled C and Lua code).
# The arch-independent files are rpl source and, of course, doc.  These will
# be installed in:
#   $(ROSIED)/share/rosie/rpl/maj.min
#   $(ROSIED)/share/doc/rosie/maj.min
#   $(ROSIED)/share/man/man1/rosie.1

# ROSIED is root of where everything needed to run rosie will be installed
ROSIED = $(DESTDIR)/lib/rosie
# ROSIE_DOC will hold docs in html format
ROSIE_DOC = $(DESTDIR)/share/doc
# ROSIE_ROOT will hold rpl (source in rpl, compiled in pkg)
ROSIE_ROOT = $(DESTDIR)/share/rosie

.PHONY: default
default: $(PLATFORM)

SUBMOD = submodules
ROSIEBIN = $(BUILD_ROOT)/bin/rosie
INSTALL_ROSIEBIN = $(DESTDIR)/bin/rosie

BUILD_LUA_PACKAGE = $(BUILD_ROOT)/rosie.lua

ARGP_DIR = $(SUBMOD)/$(ARGPARSE)
LUA_DIR = $(SUBMOD)/$(LUA)
LPEG_DIR = $(SUBMOD)/$(LPEG)
JSON_DIR = $(SUBMOD)/$(JSON)
READLINE_DIR = $(SUBMOD)/$(READLINE)

INSTALL_BIN_DIR = $(ROSIED)/bin
INSTALL_LIB_DIR = $(ROSIED)/lib
INSTALL_LUA_PACKAGE = $(ROSIED)/rosie.lua

## ----------------------------------------------------------------------------- ##

.PHONY: clean
clean:
	rm -rf bin/* lib/*
	-cd $(LUA_DIR) && make clean
	-cd $(LPEG_DIR)/src && make clean
	-cd $(JSON_DIR) && make clean
	-cd $(READLINE_DIR) && make clean

.PHONY: none
none:
	@echo "Your platform was not recognized.  Please do 'make PLATFORM', where PLATFORM is one of these: $(PLATFORMS)"

## ----------------------------------------------------------------------------- ##

CJSON_MAKE_ARGS = LUA_VERSION=5.3 PREFIX=../lua 
CJSON_MAKE_ARGS += FPCONV_OBJS="g_fmt.o dtoa.o" CJSON_CFLAGS+=-fpic
CJSON_MAKE_ARGS += USE_INTERNAL_FPCONV=true CJSON_CFLAGS+=-DUSE_INTERNAL_FPCONV
CJSON_MAKE_ARGS += CJSON_CFLAGS+="-pthread -DMULTIPLE_THREADS"
CJSON_MAKE_ARGS += CJSON_LDFLAGS+=-pthread

# Sigh.  Once we get to Version 1.0 and we support Linux packages (like RPM), we won't need this test.
# Note that this test should ALWAYS pass on OS X, since it ships with readline.
.PHONY: readlinetest
readlinetest:
	@(bash -c 'printf "#include <stdio.h>\n#include <readline/readline.h>\nint main() { }\n"' | \
	           cc -std=gnu99 -lreadline -o /dev/null -xc -) && \
	   echo "READLINE TEST: libreadline and readline.h appear to be installed" || \
	   (echo "READLINE TEST: Missing readline library or readline.h" && \
	    echo "READLINE TEST: See https://github.com/jamiejennings/rosie-pattern-language#how-to-build-clone-the-repo-and-type-make" && \
	    /usr/bin/false)

.PHONY: macosx
macosx: PLATFORM=macosx
macosx: CC=cc
macosx: CJSON_MAKE_ARGS += CJSON_LDFLAGS="-bundle -undefined dynamic_lookup"
macosx: readlinetest bin/lua lib/lpeg.so lib/cjson.so lib/readline.so compile sniff

.PHONY: linux
linux: PLATFORM=linux
linux: CC=gcc
linux: CJSON_MAKE_ARGS+=CJSON_CFLAGS+=-std=gnu99
linux: CJSON_MAKE_ARGS+=CJSON_LDFLAGS=-shared
linux: readlinetest bin/lua lib/lpeg.so lib/cjson.so lib/readline.so compile sniff

.PHONY: windows
windows:
	@echo Windows installation not yet supported.

submodules: submodules/argparse/src \
		submodules/lua/Makefile \
		submodules/lua-cjson/Makefile \
		submodules/rosie-lpeg/src/makefile \
		submodules/lua-readline/Makefile

$(submodules):
	git submodule init
	git submodule update

submodules/lua/include:
	cd $(LUA_DIR) && ln -sf src include

bin/luac bin/lua: submodules
	cd $(LUA_DIR) && $(MAKE) CC=$(CC) $(PLATFORM)
	mkdir -p bin
	cp $(LUA_DIR)/src/lua bin
	cp $(LUA_DIR)/src/luac bin

lib/lpeg.so: submodules submodules/lua/include
	cd $(LPEG_DIR)/src && $(MAKE) $(PLATFORM) CC=$(CC) LUADIR=../../lua/src
	mkdir -p lib
	cp $(LPEG_DIR)/src/lpeg.so lib

lib/cjson.so: submodules submodules/lua/include
	cd $(JSON_DIR) && $(MAKE) CC=$(CC) $(CJSON_MAKE_ARGS)
	mkdir -p lib
	cp $(JSON_DIR)/cjson.so lib

lib/readline.so: submodules submodules/lua/include
ifeq ($(PLATFORM),linux)
	cd $(READLINE_DIR) && $(MAKE) CC=$(CC) CFLAGS="-fPIC -O2 -I../lua/include"
else ifeq ($(PLATFORM),macosx)
	cd $(READLINE_DIR) && $(MAKE) USE_LIBEDIT=true LUA_INCLUDE_DIR=$(BUILD_ROOT)/submodules/lua/src CC=$(CC)
else
	false
endif
	mkdir -p lib
	cp $(READLINE_DIR)/readline.so lib

bin/argparse.luac: submodules/argparse/src/argparse.lua
	bin/luac -o $@ $<

bin/%.luac: src/core/%.lua bin/luac
	bin/luac -o $@ $<

luaobjects := $(patsubst src/core/%.lua,bin/%.luac,$(wildcard src/core/*.lua)) bin/argparse.luac

.PHONY: compile
compile: $(luaobjects)

# The PHONY declaration below will force the creation of bin/rosie every time.  This is needed
# only because the user may move the working directory.  When that happens, the user should
# be able to run 'make' again to reconstruct a new bin/rosie script (which contains a
# reference to the working directory).
.PHONY: $(ROSIEBIN)
$(ROSIEBIN):
	@/usr/bin/env echo "Creating $(ROSIEBIN)"
	@/usr/bin/env echo "#!/usr/bin/env bash" > "$(ROSIEBIN)"
	@/usr/bin/env echo -n "exec $(BUILD_ROOT)/src/run-rosie $(BUILD_ROOT)" >> "$(ROSIEBIN)"
	@/usr/bin/env echo ' "$$@"' >> "$(ROSIEBIN)"
	@chmod 755 "$(ROSIEBIN)"
	@/usr/bin/env echo "Creating $(BUILD_LUA_PACKAGE)"
	@/usr/bin/env echo "local home =  \"$(BUILD_ROOT)\"" > "$(BUILD_LUA_PACKAGE)"
	@cat "$(BUILD_ROOT)/src/rosie-package-template.lua" >> "$(BUILD_LUA_PACKAGE)"

# See comment above re: ROSIEBIN
.PHONY: $(INSTALL_ROSIEBIN)
$(INSTALL_ROSIEBIN):
	@/usr/bin/env echo "Creating $(INSTALL_ROSIEBIN)"
	mkdir -p `dirname "$(INSTALL_ROSIEBIN)"` "$(ROSIED)"/{bin,src}
	@/usr/bin/env echo "#!/usr/bin/env bash" > "$(INSTALL_ROSIEBIN)"
	@/usr/bin/env echo -n "exec $(ROSIED)/src/run-rosie $(ROSIED)" >> "$(INSTALL_ROSIEBIN)"
	@/usr/bin/env echo ' "$$@"' >> "$(INSTALL_ROSIEBIN)"
	cp "$(BUILD_ROOT)"/src/run-rosie "$(ROSIED)"/src
	@chmod 755 "$(INSTALL_ROSIEBIN)"
#	@/usr/bin/env echo "Creating $(INSTALL_LUA_PACKAGE)"
#	@/usr/bin/env echo "return dofile\(\"$(ROSIED)/src/core/init.lua\"\)" > "$(BUILD_LUA_PACKAGE)"

# Install the lua interpreter
.PHONY: install_lua
install_lua: bin/lua
	mkdir -p "$(INSTALL_BIN_DIR)"
	cp bin/lua "$(INSTALL_BIN_DIR)"

# Install all of the shared objects
.PHONY: install_so
install_so: lib/lpeg.so lib/cjson.so
	mkdir -p "$(INSTALL_LIB_DIR)"
	cp lib/lpeg.so lib/cjson.so "$(INSTALL_LIB_DIR)"

# Install any metadata needed by rosie
.PHONY: install_metadata
install_metadata:
	mkdir -p "$(ROSIED)"
	cp VERSION MANIFEST "$(ROSIED)"

# Install the needed lua source files
.PHONY: install_lua_src
install_lua_src:
	mkdir -p "$(ROSIED)"/src
	@cp src/run.lua "$(ROSIED)"/src
	@cp src/strict.lua "$(ROSIED)"/src

# Install the lua pre-compiled binary files (.luac)
.PHONY: install_luac_bin
install_luac_bin:
	mkdir -p "$(ROSIED)"/bin
	cp bin/*.luac "$(ROSIED)"/bin

# Install the provided RPL patterns
.PHONY: install_rpl
install_rpl:
	mkdir -p "$(ROSIED)"/{src,rpl}
	cp rpl/*.rpl "$(ROSIED)"/rpl
	cp src/rpl-core.rpl "$(ROSIED)"/src

# Main install rule
.PHONY: install
install: $(INSTALL_ROSIEBIN) install_lua install_so install_metadata \
	 install_lua_src install_luac_bin install_rpl
	@echo 
	@echo TO TEST: make installtest
	@echo TO UNINSTALL: Remove file $(INSTALL_ROSIEBIN) and directory $(ROSIED)
	@echo 

.PHONY: sniff
sniff: $(ROSIEBIN)
	@RESULT="$(shell $(ROSIEBIN) --version 2>&1 >/dev/null)"; \
	EXPECTED="This is Rosie $(shell head -1 $(BUILD_ROOT)/VERSION)"; \
	if [ -n "$$RESULT" -a "$$RESULT" = "$$EXPECTED" ]; then \
	    echo "";\
            echo "Rosie Pattern Engine built successfully!"; \
	    if [ -z "$$BREW" ]; then \
	      	    echo "    Use 'make install' to install into $(DESTDIR)"; \
	      	    echo "    Use 'make test' to run the test suite"; \
	      	    echo "    To run rosie from the build directory, use ./bin/rosie"; \
	            echo "    Try this example, and look for color text output: rosie basic.matchall /etc/resolv.conf"; \
		    echo "";\
	    fi; \
            true; \
        else \
            echo "Rosie Pattern Engine test FAILED."; \
	    echo "    Rosie executable is $(ROSIEBIN)"; \
	    echo "    Expected this output: $$EXPECTED"; \
	    if [ -n "$$RESULT" ]; then \
		echo "    But received this output: $$RESULT"; \
	    else \
		echo "    But received no output."; \
	    fi; \
	    false; \
        fi

.PHONY: test
test:
	@echo Running tests in test/all.lua
	echo "rosie=\"$(ROSIEBIN)\"; dofile \"$(BUILD_ROOT)/test/all.lua\"" | $(ROSIEBIN) -D

.PHONY: installtest
installtest:
	@echo Creating links in $(ROSIED) to testing code in $(BUILD_ROOT)
	-ln -s $(BUILD_ROOT)/src/test-functions.lua $(ROSIED)/src
	-ln -s $(BUILD_ROOT)/test $(ROSIED)
	@echo Running tests in test/all.lua
	echo "rosie=\"$(INSTALL_ROSIEBIN)\"; dofile \"$(ROSIED)/test/all.lua\"" | $(INSTALL_ROSIEBIN) -D
	@echo Removing links in $(ROSIED) to testing code in $(BUILD_ROOT)
	-rm $(ROSIED)/src/test-functions.lua
	-rm $(ROSIED)/test

