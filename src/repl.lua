---- -*- Mode: Lua; -*-                                                                           
----
---- repl.lua     Rosie interactive pattern development repl
----
---- © Copyright IBM Corporation 2016.
---- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
---- AUTHOR: Jamie A. Jennings


api = require "api"
common = require "common"
json = require "cjson"

local repl_patterns = [==[
      alias validchars = { [:alnum:] / [_%!$@:.,~-] }
      path = "/"? { validchars+ {"/" validchars+}* }
      load = ".load" path
      manifest = ".manifest" path
      match = ".match" expression "," quoted_string
      eval = ".eval" expression "," quoted_string
      on_off = "on" / "off"
      debug = ".debug" on_off?
      patterns = ".patterns"
      clear = ".clear"
      help = ".help"
      command = load / manifest / match / eval / debug / patterns / clear / help
      input = command / statement / identifier
]==]

local ok
ok, repl_engine = api.new_engine("repl")
api.load_file(repl_engine, "src/rosie-core.rpl")
api.load_string(repl_engine, repl_patterns)
ok, msg = api.configure(repl_engine, json.encode{expression="input", encoder="json"})
if not ok then error(msg); end

repl_prompt = "Rosie> "

local function print_match(m, left, eval_p)
   if m then 
      io.write(prettify_json(m), "\n")
      if (left > 0) then
	 print(string.format("Warning: %d unmatched characters at end of input", left))
      end
   else
      local msg = "Repl: No match"
      if not eval_p then
	 msg = msg .. ((debug and "  (turn debug off to hide the match evaluation trace)")
		    or "  (turn debug on to show the match evaluation trace)")
      end
      print(msg)
   end
end

function repl(eid)
   local ok = api.inspect_engine(eid)
   if (not ok) then
      error("Argument to repl is not the id of a live engine: " .. tostring(eid))
   end
   io.write(repl_prompt)
   local s = io.stdin:read("l")
   if s==nil then io.write("\nExiting\n"); return nil; end -- EOF, e.g. ^D at terminal
   if s~="" then					   -- blank line input
      local ok, m, left = api.match(repl_engine, s)
      if not ok then error("Internal error: ".. tostring(m)); end
      if not m then
	 io.write("Repl: syntax error.  Enter a statement or a command.  Type .help for help.\n")
      else
	 -- valid input to repl
	 if left > 0 then
	    -- not all input consumed
	    io.write('Warning: ignoring extraneous input "', s:sub(-left), '"\n')
	 end
	 m = json.decode(m)			    -- inefficient, but let's not worry right now
	 local _, _, _, subs = common.decode_match(m)
	 local name, pos, text, subs = common.decode_match(subs[1])
	 if name=="identifier" then
	    local ok, def = api.get_definition(eid, text)
	    if ok then 
	       io.write(def, "\n")
	    else
	       io.write("Repl: undefined identifier ", text, "\n")
	       if text=="help" then
		  io.write("  Hint: use .help to get help\n")
	       end
	    end
	 elseif name=="command" then
	    local cname, cpos, ctext, csubs = common.decode_match(subs[1])
	    if cname=="load" or cname=="manifest" then
	       local pname, ppos, path = common.decode_match(csubs[1])
	       local results, msg
	       if cname=="load" then 
		  results, msg = api.load_file(eid, path)
	       else -- manifest command
		  results, msg = api.load_manifest(eid, path)
	       end
	       if results then
		  io.write("Loaded ", msg, "\n")
	       else
		  io.write(msg, "\n")
	       end
	    elseif cname=="debug" then
	       if csubs then
		  local _, _, arg = common.decode_match(csubs[1])
		  debug = (arg=="on")
	       end -- if csubs
	       io.write("Debug is ", (debug and "on") or "off", "\n")
	    elseif cname=="patterns" then
	       local ok, env = api.get_env(eid)
	       if ok then
		  env = json.decode(env)	    -- inefficient, blah, blah, blah
		  common.print_env(env)
	       else
		  io.write("Repl: error accessing pattern environment\n")
	       end
	    elseif cname=="clear" then
	       ok = api.clear_env(eid)
	       io.write("Pattern environment cleared\n")
	    elseif cname=="match" or cname =="eval" then
	       local ename, epos, exp = common.decode_match(csubs[1])
	       -- parsing strips the quotes off when exp is only a literal string, but compiler
	       -- needs them there.  this is inelegant.  sigh.
	       if ename=="string" then exp = '"'..exp..'"'; end
	       local tname, tpos, input_text = common.decode_match(csubs[2])
	       input_text = common.unescape_string(input_text)
	       local ok, msg = api.configure(eid, json.encode{expression=exp, encoder="json"})
	       if not ok then
		  io.write(msg, "\n");		    -- syntax and compile errors
	       else
		  local ok, m, left = api.match(eid, input_text)
		  if not ok then error("Repl: api.match failed: " .. tostring(m)); end
		  if cname=="match" then
		     if debug and (not m) then
			local ok, match, leftover, trace = api.eval(eid, input_text)
			if not ok then error("Repl: api.eval failed: " .. tostring(match)); end
			io.write(trace, "\n")
		     end
		  else
		     -- must be eval
		     local ok, match, leftover, trace = api.eval(eid, input_text)
		     if not ok then error("Repl: api.eval failed: " .. tostring(match)); end
		     -- m and match SHOULD be equivalent but let's print what eval produces.
		     m = match
		     io.write(trace, "\n")
		  end
		  print_match(m, left, (cname=="eval"))
	       end -- if pat
	    elseif cname=="help" then
	       repl_help();
	    else
	       io.write("Repl: unimplemented command\n")
	    end -- switch on command
	 elseif name=="alias_" or name=="assignment_" or name=="grammar_" then
	    local result, msg = api.load_string(eid, text);
	    if not result then io.write(msg, "\n"); end
	 else
	    io.write("Repl: internal error\n")
	 end -- switch on type of input received
      end
   end
   repl(eid)
end

local help_text = [[
Help
At the prompt, you may enter a command, an identifier name (to see its definition),
or an RPL statement.  Commands start with a dot (".") as follows:

    .load path                      load RPL file (see note below)
    .manifest path                  load manifest file (see note below)
    .match exp, quoted_string       match RPL expression against (quoted) input data
    .eval exp, quoted_string        show full evaluation (trace)
    .debug {on|off}                 show debug state; with an argument, set it
    .patterns                       list patterns in the environment
    .clear                          clear the pattern environment
    .help                           print this message

    Note on paths to RPL and manifest files:  A path is relative to the Rosie install
    directory unless it starts with a dot "." (relative to current directory) or a
    slash "/" (absolute path).    

    EOF (^D) will exit the read/eval/print loop.
]]      

function repl_help()
   io.write(help_text)
end

