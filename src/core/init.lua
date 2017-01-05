---- -*- Mode: Lua; -*-                                                                           
----
---- init.lua    Load the Rosie system, given the location of the installation directory
----
---- © Copyright IBM Corporation 2016, 2017.
---- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
---- AUTHOR: Jamie A. Jennings

-- rosie.lua:
--   Usage: rosie = require "rosie"
--   The Rosie installation (Makefile) will create rosie.lua from src/rosie-package-template.lua

----------------------------------------------------------------------------------------
-- First, set up some key globals
----------------------------------------------------------------------------------------
-- The value of ROSIE_HOME on entry to this file is set by either:
-- (1) The shell script bin/rosie, which was
--      - created by the Rosie installation process (Makefile), to include the value
--        of ROSIE_HOME. 
--      - When that script is invoked by the user in order to run Rosie,
--        the script passes ROSIE_HOME to cli.lua, which has called this file (init).
-- Or (2) The code in rosie.lua, which was also created by the Rosie installation.
if not ROSIE_HOME then error("Error while initializing: variable ROSIE_HOME not set"); end

-- When init is loaded from run-rosie, ROSIE_DEV will be a boolean (as set by cli.lua)
-- When init is loaded from rosie.lua, ROSIE_DEV will be unset.  In this case, it should be set to
-- true so that rosie errors do not invoke os.exit().
ROSIE_DEV = ROSIE_DEV or (ROSIE_DEV==nil)

local function read_version_or_die(home)
   assert(type(home)=="string")
   local vfile = io.open(home.."/VERSION")
   if vfile then
      local v = vfile:read("l"); vfile:close();
      if v then return v; end			    -- success
   end
   -- otherwise either vfile is nil or v is nil
   local msg = "Error while initializing: "..tostring(home).."/VERSION does not exist or is not readable\n"
   if not ROSIE_DEV then io.stderr:write(msg); os.exit(-3); end
   error(msg)					    -- should do throw(msg) to end of init
end

ROSIE_VERSION = read_version_or_die(ROSIE_HOME)

-- The location of the Rosie standard library (of patterns) is ROSIE_ROOT/rpl.
-- And compiled Rosie packages are stored in ROSIE_ROOT/pkg.
--
-- ROSIE_ROOT = ROSIE_HOME by default.  The user can override the default by setting the
-- environment variable $ROSIE_ROOT to point somewhere else.

ROSIE_ROOT = ROSIE_HOME

local ok, value = pcall(os.getenv, "ROSIE_ROOT")
if (not ok) then error('Internal error: call to os.getenv(ROSIE_ROOT)" failed'); end
if value then ROSIE_ROOT = value; end

----------------------------------------------------------------------------------------
-- Load the entire rosie world...
----------------------------------------------------------------------------------------

local loader, msg = loadfile(ROSIE_HOME .. "/src/core/load-modules.lua", "t", _ENV)
if not loader then error("Error while initializing: " .. msg); end
loader()

----------------------------------------------------------------------------------------
-- Bootstrap the rpl parser, which is defined in a subset of rpl that is parsed by a
-- "native" (Lua lpeg) parser.
----------------------------------------------------------------------------------------

-- To bootstrap, we have to compile the Rosie rpl using the core parser/compiler,
-- producing ROSIE_RPLX, which is a parser Rosie Pattern Language files

ROSIE_ENGINE = engine.new("RPL engine")
local core_rpl_filename = ROSIE_HOME.."/rpl/rpl-core.rpl"
compile.compile_core(core_rpl_filename, ROSIE_ENGINE._env)
local success, result, messages = pcall(ROSIE_ENGINE.compile, ROSIE_ENGINE, 'rpl')
if not success then error("Error while initializing: could not compile "
			  .. core_rpl_filename .. ":\n" .. tostring(result)); end

ROSIE_RPLX = result

-- Install the new parser.
load_module("rpl-parser")
compile.set_parser(parse_and_explain);		    -- parse_and_explain uses ROSIE_RPLX

----------------------------------------------------------------------------------------
-- INFO for debugging
----------------------------------------------------------------------------------------

-- N.B. All values in table must be strings, even if original value was nil or another type.
-- Two ways to use this table:
-- (1) Iterate over the numeric entries with ipairs to access an organized (well, ordered) list of
--     important parameters, with their values and descriptions.
-- (2) Index the table by a parameter key to obtain its value.
ROSIE_INFO = {
   {name="ROSIE_HOME",    value=ROSIE_HOME,                  desc="location of the rosie installation directory"},
   {name="ROSIE_VERSION", value=ROSIE_VERSION,               desc="version of rosie installed"},
   {name="ROSIE_DEV",     value=tostring(ROSIE_DEV),         desc="true if rosie was started in development mode"},
   {name="ROSIE_ROOT",    value=tostring(ROSIE_ROOT),        desc="root of the standard rpl library"},
   {name="HOSTNAME",      value=os.getenv("HOSTNAME") or "", desc="host on which rosie is running"},
   {name="HOSTTYPE",      value=os.getenv("HOSTTYPE") or "", desc="type of host on which rosie is running"},
   {name="OSTYPE",        value=os.getenv("OSTYPE") or "",   desc="type of OS on which rosie is running"},
   {name="CWD",           value=os.getenv("PWD") or "",      desc="current working directory"},
   {name="ROSIE_COMMAND", value=ROSIE_COMMAND or "",         desc="invocation command, if rosie invoked through the CLI"}
}
for _,entry in ipairs(ROSIE_INFO) do ROSIE_INFO[entry.name] = entry.value; end

----------------------------------------------------------------------------------------
-- Output encoding functions
----------------------------------------------------------------------------------------
-- Lua applications (including the Rosie CLI & REPL) can use this table to install known
-- output encoders by name.

local encoder_table =
   {json = json.encode,
    color = color_output.color_string_from_leaf_nodes,
    nocolor = color_output.string_from_leaf_nodes,
    fulltext = common.match_to_text,
    [false] = function(...) return ...; end
 }

----------------------------------------------------------------------------------------
-- Build the rosie module as seen by the Lua client
----------------------------------------------------------------------------------------
local file_functions = {
   match = process_input_file.match,
   tracematch = process_input_file.tracematch,
   grep = process_input_file.grep,
   load = process_rpl_file.load_file	    -- TEMP until module system
}

local rosie = {
   engine = engine,
   file = file_functions,
   encoders = encoder_table
}

function rosie.info() return ROSIE_INFO; end

-- When rosie is loaded into Lua, such as for development, for using Rosie in Lua, or for
-- supporting the foreign function API, these internals are exposed through the rosie package table.  
if ROSIE_DEV then
   rosie._env = _ENV
   rosie._module = module
end

return rosie