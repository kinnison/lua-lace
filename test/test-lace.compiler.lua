-- test/test-compiler.lua
--
-- Lua Access Control Engine -- Tests for the compiler
--
-- Copyright 2012,2015 Daniel Silverstone <dsilvers@digital-scurf.org>
--
-- For Licence terms, see COPYING
--

-- Step one, start coverage

pcall(require, 'luacov')

local compiler = require 'lace.compiler'
local err = require 'lace.error'

local testnames = {}

local real_assert = assert
local total_asserts = 0
local function assert(...)
   real_assert(...)
   total_asserts = total_asserts + 1
end

local function add_test(suite, name, value)
   rawset(suite, name, value)
   testnames[#testnames+1] = name
end

local suite = setmetatable({}, {__newindex = add_test})

function suite.context_missing()
   local result, msg = compiler.compile(nil, "")
   assert(result == nil, "Lua errors should return nil")
   assert(msg:match("context must be a table"), "Supposed to whinge about context not being a table")
end

function suite.context_missing_dot_lace()
   local result, msg = compiler.compile({}, "")
   assert(result == nil, "Lua errors should return nil")
   assert(msg:match("context must contain"), "Supposed to whinge about context missing _lace")
end

function suite.context_dot_lace_not_table()
   local result, msg = compiler.compile({_lace = true}, "")
   assert(result == nil, "Lua errors should return nil")
   assert(msg:match("context must contain"), "Supposed to whinge about context missing _lace")
end

function suite.source_not_string()
   local result, msg = compiler.compile({_lace = {}}, false)
   assert(result == nil, "Lua errors should return nil")
   assert(msg:match("name must be a string"), "Supposed to whinge about name not being a string")
end

function suite.content_not_string()
   local result, msg = compiler.compile({_lace = {}}, "", false)
   assert(result == nil, "Lua errors should return nil")
   assert(msg:match("must be nil or a string"), "Supposed to whinge about content not being a string but being non-nil")
end

function suite.empty_content_no_loader()
   local result, msg = compiler.compile({_lace = {}}, "", "")
   assert(result == false, "Internal errors should return false")
   assert(msg:match("whatsoever"), "Supposed to whinge about no allow/deny at all")
end

function suite.no_content_no_loader()
   local result, msg = compiler.compile({_lace = {}}, "")
   assert(result == false, "Internal errors should return false")
   assert(msg:match("Ruleset not found:"), "Supposed to whinge about ruleset not being found")
end

function suite.no_unconditional_action()
   local result, msg = compiler.compile({_lace = {defined={cond=true}}}, "", "deny stuff cond")
   assert(type(result) == "table", "Loading a ruleset should result in a table")
   assert(#result.rules == 2, "There should be two rules present")
   local rule = result.rules[1]
   assert(type(rule) == "table", "Rules should be tables")
   assert(type(rule.fn) == "function", "Rules should have functions")
   assert(type(rule.args) == "table", "Rules should have arguments")
   -- rule 2 should be an unconditional allow with 'Default behaviour' as the reason,
   -- let's check
   local r2a = result.rules[2].args
   assert(r2a[2] == "allow", "Rule 2 should be an allow")
   assert(r2a[3] == "Default behaviour", "Rule 2's reason should be 'Default behaviour'")
   assert(#r2a[4] == 0, "Rule 2 should have no conditions")
end

function suite.no_unconditional_action_default_deny()
   local result, msg = compiler.compile({_lace = {defined={cond=true}}}, "", "default deny\ndeny stuff cond")
   assert(type(result) == "table", "Loading a ruleset should result in a table")
   assert(#result.rules == 3, "There should be three rules present")
   local rule = result.rules[1]
   assert(type(rule) == "table", "Rules should be tables")
   assert(type(rule.fn) == "function", "Rules should have functions")
   assert(type(rule.args) == "table", "Rules should have arguments")
   -- rule 3 should be an unconditional deny with 'Default behaviour' as the reason,
   -- let's check
   local r3a = result.rules[3].args
   assert(r3a[2] == "deny", "Rule 3 should be a deny, despite last rule behind a deny")
   assert(r3a[3] == "Default behaviour", "Rule 3's reason should be 'Default behaviour'")
   assert(#r3a[4] == 0, "Rule 3 should have no conditions")
end

function suite.is_unconditional_action_default_deny()
   local result, msg = compiler.compile({_lace = {}}, "", "default deny\nallow stuff")
   assert(type(result) == "table", "Loading a ruleset should result in a table")
   assert(#result.rules == 2, "There should be two rules present")
   local rule = result.rules[1]
   assert(type(rule) == "table", "Rules should be tables")
   assert(type(rule.fn) == "function", "Rules should have functions")
   assert(type(rule.args) == "table", "Rules should have arguments")
   -- rule 2 should be an unconditional allow with 'stuff' as the reason
   -- let's check
   local r2a = result.rules[2].args
   assert(r2a[2] == "allow", "Rule 2 should be an allow, despite default being deny")
   assert(r2a[3] == "stuff", "Rule 2's reason should be 'stuff'")
   assert(#r2a[4] == 0, "Rule 2 should have no conditions")
end

-- Now we set up a more useful context and use that going forward:

local comp_context = {
   _lace = {
      loader = function(ctx, name)
		  if name == "THROW_ERROR" then
		     error("THROWN")
		  end
		  local fh = io.open("test/test-lace.compile-" .. name .. ".rules", "r")
		  if not fh then
		     return err.error("LOADER: Unknown: " .. name, {1})
		  end
		  local content = fh:read("*a")
		  fh:close()
		  return "real-" .. name, content
	       end,
      commands = {
	 DISABLEDCOMMAND = false,
      },
      controltype = {
	 nocompile = function()
			return err.error("NOCOMPILE", {2})
		     end,
	 equal = function(ctx, eq, key, value) --luacheck: ignore 212/eq
		    return {
		       fn = function(ectx, ekey, evalue)
			       return ectx[ekey] == evalue
			    end,
		       args = { key, value },
		    }
		 end,
      },
   },
}

function suite.loader_errors()
   local result, msg = compiler.compile(comp_context, "THROW_ERROR")
   assert(result == nil, "Lua errors should return nil")
   assert(msg:match("THROWN"), "Error returned didn't match what we threw")
end

function suite.load_no_file()
   local result, msg = compiler.compile(comp_context, "NOT_FOUND")
   assert(result == false, "Internal errors should return false")
   assert(msg:match("LOADER: Unknown: NOT_FOUND"), "Error returned didn't match what we returned from loader")
end

function suite.load_file_with_no_rules()
   local result, msg = compiler.compile(comp_context, "nothing")
   assert(result == false, "Internal errors should return false")
   assert(msg:match("whatsoever"), "Error returned didn't match expected whinge about no allow/deny")
end

function suite.load_file_with_bad_command()
   local result, msg = compiler.compile(comp_context, "badcommand")
   assert(result == false, "Internal errors should return false")
   assert(msg:match("BADCOMMAND"), "Error returned did not match the bad command")
end

function suite.load_file_with_disabled_command()
   local result, msg = compiler.compile(comp_context, "disabledcommand")
   assert(result == false, "Internal errors should return false")
   assert(msg:match("is disabled by"), "Error returned did not match the bad command")
end

function suite.load_file_with_bad_deny_command()
   local result, msg = compiler.compile(comp_context, "denynoreason")
   assert(result == false, "Internal errors should return false")
   assert(msg:match("got nothing"), "Error returned did not match expected behaviour from deny")
end

function suite.load_file_with_one_command()
   local result, msg = compiler.compile(comp_context, "denyall")
   assert(type(result) == "table", "Loading a ruleset should result in a table")
   assert(#result.rules == 1, "There should be one rule present")
   local rule = result.rules[1]
   assert(type(rule) == "table", "Rules should be tables")
   assert(type(rule.fn) == "function", "Rules should have functions")
   assert(type(rule.args) == "table", "Rules should have arguments")
end

-- The various error paths must now be tested for location veracity

function suite.error_does_not_exist()
   local result, msg = compiler.compile(comp_context, "does-not-exist")
   assert(result == false, "Errors compiling should return false")
   assert(type(msg) == "string", "Compilation errors should be strings")
   assert(msg:find("\n"), "Compilation errors are multiline")
   local line1, line2, line3, line4 = msg:match("^([^\n]*)\n([^\n]*)\n([^\n]*)\n([^\n]*)$")
   assert(line1:find("does%-not%-exist"), "The first line must mention the error")
   assert(line2 == "Implicit inclusion of does-not-exist :: 1", "The second line is where the error happened")
   assert(line3 == "include does-not-exist", "The third line is the original line")
   assert(line4 == "        ^^^^^^^^^^^^^^", "The fourth line highlights relevant words")
end

function suite.error_in_define_anyof1()
   local result, msg = compiler.compile(comp_context, "errorindefineanyof1")
   assert(result == false, "Errors compiling should return false")
   assert(type(msg) == "string", "Compilation errors should be strings")
   assert(msg:find("\n"), "Compilation errors are multiline")
   local line1, line2, line3, line4 = msg:match("^([^\n]*)\n([^\n]*)\n([^\n]*)\n([^\n]*)$")
   assert(line1:find("at least"), "The first line must mention the error")
   assert(line2 == "real-errorindefineanyof1 :: 3", "The second line is where the error happened")
   assert(line3 == "define fish anyof", "The third line is the original line")
   assert(line4 == "            ^^^^^", "The fourth line highlights relevant words")
end

function suite.error_in_define_anyof2()
   local result, msg = compiler.compile(comp_context, "errorindefineanyof2")
   assert(result == false, "Errors compiling should return false")
   assert(type(msg) == "string", "Compilation errors should be strings")
   assert(msg:find("\n"), "Compilation errors are multiline")
   local line1, line2, line3, line4 = msg:match("^([^\n]*)\n([^\n]*)\n([^\n]*)\n([^\n]*)$")
   assert(line1:find("at least"), "The first line must mention the error")
   assert(line2 == "real-errorindefineanyof2 :: 3", "The second line is where the error happened")
   assert(line3 == "define fish anyof something", "The third line is the original line")
   assert(line4 == "            ^^^^^ ^^^^^^^^^", "The fourth line highlights relevant words")
end

function suite.error_in_define_anyof3()
   local result, msg = compiler.compile(comp_context, "errorindefineanyof3")
   assert(result == false, "Errors compiling should return false")
   assert(type(msg) == "string", "Compilation errors should be strings")
   assert(msg:find("\n"), "Compilation errors are multiline")
   local line1, line2, line3, line4 = msg:match("^([^\n]*)\n([^\n]*)\n([^\n]*)\n([^\n]*)$")
   assert(line1:find("something"), "The first line must mention the error")
   assert(line2 == "real-errorindefineanyof3 :: 3", "The third line is where the error happened")
   assert(line3 == "define fish anyof something else", "The third line is the original line")
   assert(line4 == "                  ^^^^^^^^^     ", "The fourth line highlights relevant words")
end

function suite.error_in_define_anyof4()
   local result, msg = compiler.compile(comp_context, "errorindefineanyof4")
   assert(result == false, "Errors compiling should return false")
   assert(type(msg) == "string", "Compilation errors should be strings")
   assert(msg:find("\n"), "Compilation errors are multiline")
   local line1, line2, line3, line4 = msg:match("^([^\n]*)\n([^\n]*)\n([^\n]*)\n([^\n]*)$")
   assert(line1:find("else"), "The first line must mention the error")
   assert(line2 == "real-errorindefineanyof4 :: 3", "The third line is where the error happened")
   assert(line3 == "define fish anyof something else", "The third line is the original line")
   assert(line4 == "                            ^^^^", "The fourth line highlights relevant words")
end

function suite.error_in_allow_or_deny()
   local result, msg = compiler.compile(comp_context, "errorinallow")
   assert(result == false, "Errors compiling should return false")
   assert(type(msg) == "string", "Compilation errors should be strings")
   assert(msg:find("\n"), "Compilation errors are multiline")
   local line1, line2, line3, line4 = msg:match("^([^\n]*)\n([^\n]*)\n([^\n]*)\n([^\n]*)$")
   assert(line1:find("Expected reason"), "The first line must mention the error")
   assert(line2 == "real-errorinallow :: 3", "The second line is where the error happened")
   assert(line3 == "allow", "The third line is the original line")
   assert(line4 == "^^^^^", "The fourth line highlights relevant words")
end

function suite.error_in_default1()
   local result, msg = compiler.compile(comp_context, "errorindefault1")
   assert(result == false, "Errors compiling should return false")
   assert(type(msg) == "string", "Compilation errors should be strings")
   assert(msg:find("\n"), "Compilation errors are multiline")
   local line1, line2, line3, line4 = msg:match("^([^\n]*)\n([^\n]*)\n([^\n]*)\n([^\n]*)$")
   assert(line1:find("Expected result"), "The first line must mention the error")
   assert(line2 == "real-errorindefault1 :: 3", "The second line is where the error happened")
   assert(line3 == "default", "The third line is the original line")
   assert(line4 == "^^^^^^^", "The fourth line highlights relevant words")
end

function suite.error_in_default2()
   local result, msg = compiler.compile(comp_context, "errorindefault2")
   assert(result == false, "Errors compiling should return false")
   assert(type(msg) == "string", "Compilation errors should be strings")
   assert(msg:find("\n"), "Compilation errors are multiline")
   local line1, line2, line3, line4 = msg:match("^([^\n]*)\n([^\n]*)\n([^\n]*)\n([^\n]*)$")
   assert(line1:find("allow or deny"), "The first line must mention the error")
   assert(line2 == "real-errorindefault2 :: 3", "The second line is where the error happened")
   assert(line3 == "default fish", "The third line is the original line")
   assert(line4 == "        ^^^^", "The fourth line highlights relevant words")
end

function suite.error_in_default3()
   local result, msg = compiler.compile(comp_context, "errorindefault3")
   assert(result == false, "Errors compiling should return false")
   assert(type(msg) == "string", "Compilation errors should be strings")
   assert(msg:find("\n"), "Compilation errors are multiline")
   local line1, line2, line3, line4 = msg:match("^([^\n]*)\n([^\n]*)\n([^\n]*)\n([^\n]*)$")
   assert(line1:find("additional"), "The first line must mention the error")
   assert(line2 == "real-errorindefault3 :: 3", "The second line is where the error happened")
   assert(line3 == 'default allow "" extrashite', "The third line is the original line")
   assert(line4 == "                 ^^^^^^^^^^", "The fourth line highlights relevant words")
end

function suite.error_in_default4()
   local result, msg = compiler.compile(comp_context, "errorindefault4")
   assert(result == false, "Errors compiling should return false")
   assert(type(msg) == "string", "Compilation errors should be strings")
   assert(msg:find("\n"), "Compilation errors are multiline")
   local line1, line2, line3, line4 = msg:match("^([^\n]*)\n([^\n]*)\n([^\n]*)\n([^\n]*)$")
   assert(line1:find("Cannot change"), "The first line must mention the error")
   assert(line2 == "real-errorindefault4 :: 5", "The second line is where the error happened")
   assert(line3 == 'default allow', "The third line is the original line")
   assert(line4 == "^^^^^^^ ^^^^^", "The fourth line highlights relevant words")
end

function suite.error_in_define1()
   local result, msg = compiler.compile(comp_context, "errorindefine1")
   assert(result == false, "Errors compiling should return false")
   assert(type(msg) == "string", "Compilation errors should be strings")
   assert(msg:find("\n"), "Compilation errors are multiline")
   local line1, line2, line3, line4 = msg:match("^([^\n]*)\n([^\n]*)\n([^\n]*)\n([^\n]*)$")
   assert(line1:find("Expected name"), "The first line must mention the error")
   assert(line2 == "real-errorindefine1 :: 3", "The second line is where the error happened")
   assert(line3 == 'define', "The third line is the original line")
   assert(line4 == "^^^^^^", "The fourth line highlights relevant words")
end

function suite.error_in_define2()
   local result, msg = compiler.compile(comp_context, "errorindefine2")
   assert(result == false, "Errors compiling should return false")
   assert(type(msg) == "string", "Compilation errors should be strings")
   assert(msg:find("\n"), "Compilation errors are multiline")
   local line1, line2, line3, line4 = msg:match("^([^\n]*)\n([^\n]*)\n([^\n]*)\n([^\n]*)$")
   assert(line1:find("Bad name"), "The first line must mention the error")
   assert(line2 == "real-errorindefine2 :: 3", "The second line is where the error happened")
   assert(line3 == 'define !fish', "The third line is the original line")
   assert(line4 == "       ^^^^^", "The fourth line highlights relevant words")
end

function suite.error_in_define3()
   local result, msg = compiler.compile(comp_context, "errorindefine3")
   assert(result == false, "Errors compiling should return false")
   assert(type(msg) == "string", "Compilation errors should be strings")
   assert(msg:find("\n"), "Compilation errors are multiline")
   local line1, line2, line3, line4 = msg:match("^([^\n]*)\n([^\n]*)\n([^\n]*)\n([^\n]*)$")
   assert(line1:find("Expected control"), "The first line must mention the error")
   assert(line2 == "real-errorindefine3 :: 3", "The second line is where the error happened")
   assert(line3 == 'define fish', "The third line is the original line")
   assert(line4 == "^^^^^^ ^^^^", "The fourth line highlights relevant words")
end

function suite.error_in_define4()
   local result, msg = compiler.compile(comp_context, "errorindefine4")
   assert(result == false, "Errors compiling should return false")
   assert(type(msg) == "string", "Compilation errors should be strings")
   assert(msg:find("\n"), "Compilation errors are multiline")
   local line1, line2, line3, line4 = msg:match("^([^\n]*)\n([^\n]*)\n([^\n]*)\n([^\n]*)$")
   assert(line1:find("must be a control type"), "The first line must mention the error")
   assert(line2 == "real-errorindefine4 :: 3", "The second line is where the error happened")
   assert(line3 == "define fish does_not_exist", "The third line is the original line")
   assert(line4 == "            ^^^^^^^^^^^^^^", "The fourth line highlights relevant words")
end

function suite.error_in_define5()
   local result, msg = compiler.compile(comp_context, "errorindefine5")
   assert(result == false, "Errors compiling should return false")
   assert(type(msg) == "string", "Compilation errors should be strings")
   assert(msg:find("\n"), "Compilation errors are multiline")
   local line1, line2, line3, line4 = msg:match("^([^\n]*)\n([^\n]*)\n([^\n]*)\n([^\n]*)$")
   assert(line1:find("NOCOMPILE"), "The first line must mention the error")
   assert(line2 == "real-errorindefine5 :: 3", "The second line is where the error happened")
   assert(line3 == "define fish NOCOMPILE", "The third line is the original line")
   assert(line4 == "            ^^^^^^^^^", "The fourth line highlights relevant words")
end

function suite.error_in_include1()
   local result, msg = compiler.compile(comp_context, "errorininclude1")
   assert(result == false, "Errors compiling should return false")
   assert(type(msg) == "string", "Compilation errors should be strings")
   assert(msg:find("\n"), "Compilation errors are multiline")
   local line1, line2, line3, line4 = msg:match("^([^\n]*)\n([^\n]*)\n([^\n]*)\n([^\n]*)$")
   assert(line1:find("No ruleset named"), "The first line must mention the error")
   assert(line2 == "real-errorininclude1 :: 3", "The second line is where the error happened")
   assert(line3 == "include", "The third line is the original line")
   assert(line4 == "^^^^^^^", "The fourth line highlights relevant words")
end

function suite.error_in_include2()
   local result, msg = compiler.compile(comp_context, "errorininclude2")
   assert(result == false, "Errors compiling should return false")
   assert(type(msg) == "string", "Compilation errors should be strings")
   assert(msg:find("\n"), "Compilation errors are multiline")
   local line1, line2, line3, line4 = msg:match("^([^\n]*)\n([^\n]*)\n([^\n]*)\n([^\n]*)$")
   assert(line1:find("NOTFOUND"), "The first line must mention the error")
   assert(line2 == "real-errorininclude2 :: 3", "The second line is where the error happened")
   assert(line3 == "include errorininclude2-NOTFOUND", "The third line is the original line")
   assert(line4 == "        ^^^^^^^^^^^^^^^^^^^^^^^^", "The fourth line highlights relevant words")
end

function suite.defaults_propagate()
   local result, msg = compiler.compile(comp_context, "defaults_propagate")
   assert(result, msg)
end

function suite.okay_subdefine()
   local result, msg = compiler.compile(comp_context, "subdefine1")
   assert(result, msg)
end

function suite.okay_nested_subdefine()
   local result, msg = compiler.compile(comp_context, "subdefine2")
   assert(result, msg)
end

function suite.okay_negated_subdefine()
   local result, msg = compiler.compile(comp_context, "subdefine3")
   assert(result, msg)
end

function suite.deep_errors_report_well()
   local result, msg = compiler.compile(comp_context, "deeperror1")
   local expected_err = [[
define's second parameter (broken) must be a control type such as anyof
real-deeperror3 :: 3
define something broken
                 ^^^^^^
while including deeperror3
real-deeperror2 :: 3
include deeperror3
        ^^^^^^^^^^
while including deeperror2
real-deeperror1 :: 3
include deeperror2
        ^^^^^^^^^^]]
   assert(not result, "Err, didn't want the compilation to succeed")
   assert(msg == expected_err, "Error message did not match")
end

local count_ok = 0
for _, testname in ipairs(testnames) do
--   print("Run: " .. testname)
   local ok, err = xpcall(suite[testname], debug.traceback)
   if not ok then
      print(err)
      print()
   else
      count_ok = count_ok + 1
   end
end

print(tostring(count_ok) .. "/" .. tostring(#testnames) .. " [" .. tostring(total_asserts) .. "] OK")

os.exit(count_ok == #testnames and 0 or 1)
