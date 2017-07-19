-- -*- Mode: Lua; -*-                                                                             
--
-- environment.lua    Rosie environments
--
-- © Copyright IBM Corporation 2017.
-- LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)
-- AUTHOR: Jamie A. Jennings

-- Environments can be extended in a way that new bindings shadow old ones.  This permits a tree
-- of environments that model nested scopes.  Currently, that nesting is used rarely.  Grammar
-- compilation uses this.
-- 
-- The root of an environment tree is the "base environment" for a package P.  For every other
-- package, X, that is open in P, there is a binding in P: X.prefix->X.env where X.prefix is the
-- prefix used for X in P, and X.env is the package environment for X.

local environment = {}

local common = require "common"
local pattern = common.pattern
local macro = common.macro
local pfunction = common.pfunction
local ast = require "ast"
local recordtype = require "recordtype"
local lpeg = require "lpeg"
local locale = lpeg.locale()
local list = require "list"

---------------------------------------------------------------------------------------------------
-- Items for the initial environment
---------------------------------------------------------------------------------------------------

local b_id = common.boundary_identifier
local dot_id = common.any_char_identifier
local eol_id = common.end_of_input_identifier

-- This version of 'find' matches all the text up to and including the target exp.
-- local function macro_find(...)
--    -- return {{! <exp>} .}* <exp> when given <exp> as an arg
--    local args = {...}
--    if #args~=1 then error("find takes one argument, " .. tostring(#args) .. " given"); end
--    local exp = args[1]
--    assert(exp.sourceref)
--    local any_char = ast.ref.new{localname=".", sourceref=exp.sourceref}
--    local not_exp = ast.predicate.new{type="!", exp=exp, sourceref=exp.sourceref}
--    local advance =
--       ast.repetition.new{min=0,
-- 			 exp=ast.raw.new{exp=ast.sequence.new{exps={not_exp, any_char},
-- 							   sourceref=exp.sourceref},
-- 				         sourceref=exp.sourceref},
-- 		         sourceref=exp.sourceref}
--    local wrapper = ast.cooked.is(exp) and ast.cooked or ast.raw
--    return wrapper.new{exp=ast.sequence.new{exps={advance, exp}, sourceref=exp.sourceref},
-- 		      sourceref=exp.sourceref}
-- end

local function macro_find(...)
    -- grammar
    --    alias find = {search <exp>}
    --    alias search = {!<exp> .}*
    -- end
   local args = {...}
   if #args~=1 then error("find takes one argument, " .. tostring(#args) .. " given"); end
   local exp = args[1]
   local sref = exp.sourceref
   assert(sref)
   local any_char = ast.ref.new{localname=".", sourceref=sref}
   local not_exp = ast.predicate.new{type="!", exp=exp, sourceref=sref}
   local search_exp =
      ast.repetition.new{min=0,
			 exp=ast.raw.new{exp=ast.sequence.new{exps={not_exp, any_char},
							      sourceref=sref},
				         sourceref=sref},
		         sourceref=sref}
   local search_ref = ast.ref.new{localname="<search>", sourceref=sref}
   local search_rule =
      ast.binding.new{ref=search_ref,
		      exp=search_exp,
		      is_alias=true,
		      sourceref=sref}
   local capture_rule, capture_ref
   if ( ast.ref.is(exp) or
        (ast.cooked.is(exp) and ast.ref.is(exp.exp)) or
        (ast.raw.is(exp) and ast.ref.is(exp.exp)) ) then
      capture_ref = exp
   else
      capture_ref = ast.ref.new{localname="*", sourceref=sref}
      capture_rule = ast.binding.new{ref=capture_ref,
				     -- We wrap exp in a sequence so that the sequence is named
				     -- "*", and exp keeps its name.
				     exp=ast.sequence.new{exps={exp}, sourceref=sref},
				     sourceref=sref}
   end
   local wrapper = ast.cooked.is(exp) and ast.cooked or ast.raw
   local start_rule =
      ast.binding.new{ref=ast.ref.new{localname="<find>", sourceref=sref},
		      exp=wrapper.new{exp=ast.sequence.new{exps={search_ref, capture_ref}, sourceref=sref},
				      sourceref=sref},
		      is_alias=true,
		      sourceref=sref}
   -- By putting capture_rule last, it will be omitted if nil
   local rules = {start_rule, search_rule, capture_rule}
   return ast.grammar.new{rules=rules, sourceref=sref}
end

-- grep
local function macro_findall(...)
   local args = {...}
   if #args~=1 then error("findall takes one argument, " .. tostring(#args) .. " given"); end
   local exp = args[1]
   assert(exp.sourceref)
   local find = macro_find(exp)
   assert(find.sourceref)
   return ast.repetition.new{min=1, exp=find, cooked=false, sourceref=exp.sourceref}
end

-- TODO: rewrite this with utf8 support (without relying on every literal being valid utf8)
local function macro_case_insensitive(...)
   local args = {...}
   if #args~=1 then error("ci takes one argument, " .. tostring(#args) .. " given"); end
   local exp = args[1]
   local function xform_literal(exp)
      local lc, uc = string.lower(exp.value), string.upper(exp.value)
      local chars = list.new()
      for i = 1, #exp.value do
	 local upper_lower_choices =
	    { ast.literal.new{value=uc:sub(i,i), sourceref=exp.sourceref},
	      ast.literal.new{value=lc:sub(i,i), sourceref=exp.sourceref} }
	 table.insert(chars, ast.choice.new{exps=upper_lower_choices, sourceref=exp.sourceref})
      end
      return ast.raw.new{exp=ast.sequence.new{exps=chars, sourceref=exp.sourceref}, sourceref=exp.sourceref}
   end
   return ast.visit_expressions(exp, ast.literal.is, xform_literal)
end

local function macro_error(...)
   local args = {...}
   if #args~=1 then error("macro takes one argument, " .. tostring(#args) .. " given"); end
   local exp = args[1]
   local sref = assert(exp.sourceref)
   if not ast.literal.is(exp) then error('error macro takes a string argument'); end
   assert(type(exp.value)=="string")

-- !@# !@# !@# !@# !@# !@# !@# !@# !@# !@# !@# !@# !@# !@# !@# !@# !@# !@# 
-- fail compiles to a new pattern type that bails out of the match (like a failtwice), but keeps
   -- the captures:  lpeg.Cc(exp.value) * lpeg.<stop matching as if at end of input>
   local fail = ast.halt.new{text=exp.value, sourceref=sref}
-- !@# !@# !@# !@# !@# !@# !@# !@# !@# !@# !@# !@# !@# !@# !@# !@# !@# !@# 


   return fail
end

local function example_first(...)
   local args = {...}
   return args[1]
end

local function example_last(...)
   local args = {...}
   return args[#args]
end

----------------------------------------------------------------------------------------
-- Boundary for tokenization... this is going to be customizable, but hard-coded for now
----------------------------------------------------------------------------------------

local boundary = locale.space^1 + #locale.punct
              + (lpeg.B(locale.punct) * #(-locale.punct))
	      + (lpeg.B(locale.space) * #(-locale.space))
	      + lpeg.P(-1)
	      + (- lpeg.B(1))

environment.boundary = boundary
local utf8_char_peg = common.utf8_char_peg
	   
-- The base environment is ENV, which can be extended with new_env, but not written to directly,
-- because it is shared between match engines.  Eventually, it will be replaced by a "standard
-- prelude", a la Haskell.  :-)

local ENV =
    {[dot_id] = pattern.new{name=dot_id; peg=utf8_char_peg; alias=true};  -- any single character
     [eol_id] = pattern.new{name=eol_id; peg=lpeg.P(-1); alias=true};	  -- end of input
     [b_id] = pattern.new{name=b_id; peg=boundary; alias=true};		  -- token boundary
     ["find"] = macro.new{primop=macro_find};
     ["findall"] = macro.new{primop=macro_findall};
     ["error"] = macro.new{primop=macro_error};
     ["ci"] = macro.new{primop=macro_case_insensitive};
--     ["cs"] = macro.new{primop=macro_case_sensitive};
     ["last"] = macro.new{primop=example_last};
     ["first"] = macro.new{primop=example_first};
  }
	      
setmetatable(ENV, {__tostring = function(env)
				   return "<base environment>"
				end;
		   __newindex = function(env, key, value)
				   error('Compiler: base environment is read-only, '
					 .. 'cannot assign "' .. key .. '"')
				end;
		})



-- Each engine has a "global" package table that maps: importpath -> env
-- where env is the environment for the module, containing both local and exported bindings. 
function environment.make_module_table()
   return setmetatable({}, {__tostring = function(env) return "<module_table>"; end;})
end

local env					    -- forward ref for env.factory
env = recordtype.new("environment",
		     {store = recordtype.NIL,
		      parent = recordtype.NIL,
		      exported = false,
		      next = function(self, key)
				return next(self.store, key)
			     end,
		      bindings = function(self)
				    return function(store, key)
					      return next(store, key)
					   end,
				    self.store,
				    nil
				 end,
		   },
		     function(parent)
			return env.factory{store={}, parent=parent}; end)

local base_environment = env.new(); base_environment.store = ENV

environment.new = function (...)
		     if #{...}==0 then return env.new(base_environment); end
		     error("new environment called with arg(s)")
		  end

environment.extend = function (parent)
			if env.is(parent) then return env.new(parent); end
			error("extend environment called with arg that is not an environment: "
			      .. tostring(parent))
			end

environment.is = env.is

function environment.lookup(env, id, prefix)
   assert(environment.is(env))
   if prefix then
      local mod = environment.lookup(env, prefix)
      if environment.is(mod) then
	 local val = environment.lookup(mod, id)
	 if val and val.exported then		    -- hmmm, we are duck typing here
	    return val
	 else
	    return nil
	 end
      else -- found prefix but it is not a module
	 return nil, prefix .. " is not a valid module reference"
      end
   else
      -- no prefix
      return env.store[id] or (env.parent and environment.lookup(env.parent, id))
   end
end

-- N.B. value can be nil (this is how bindings are removed)
function environment.bind(env, id, value)
   assert(environment.is(env))
   assert(type(id)=="string")
   env.store[id] = value
end

-- return a flat representation of env (recall that environments are nested)
function environment.flatten(env, output_table)
   output_table = output_table or {}
   for item, value in pairs(env.store) do
      -- access only string keys.  numeric keys are for other things.
      if type(item)=="string" then
	 -- if already seen, do not overwrite with value from parent env
	 if not output_table[item] then output_table[item] = value; end
      end
   end
   if env.parent then
      return environment.flatten(env.parent, output_table)
   else
      return output_table
   end
end

return environment
