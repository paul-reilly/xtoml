--!The make-like cross-platform build utility based on Lua
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.
--
-- Copyright (C) 2015-present, TBOOX Open Source Group.
--
--
-- @author      paul reilly
-- @file        xtoml.lua
--


import("core.base.option")


local help_string = [=[  
${yellow}
            __                  __  
  ___  ____/  |_  ____   _____ |  |  
  \  \/  /\   __\/  _ \ /     \|  |  
   >    <  |  | (  <_> )  Y Y  \  |__
  /__/\_ \ |__|  \____/|__|_|  /____/       v0.1.0
        \/                   \/      

      ${clear}Usage:
    
            ${dim green dim}xmake l xtoml.lua
      ${clear} 
      Converts a TOML-based xmake project description file (in the current
      directory) to a standard xmake.lua file that can be read by xmake.

      TOML is declarative but projects in languages such as C, C++, D, Rust, 
      Go, Zig etc that xmake supports can need finer control. So we can define 
      the following field:
    
            ${green dim}[project]
            xmakebuildfile = true
      ${clear} 
      ... in the `project` section of our TOML file to create an xmake.build.lua 
      file (if it does not exist) which will be included in the generated 
      xmake.lua file.

      Sections that can be used:

            ${green}[project] [option.X] [requires] [requires.X] [target.X]
      ${clear} 
      Those with `.X` have the name of the option/require/target.

      Some common xmake functions can be used in shorthand form in TOML fields
      and these are checked by the script. All fields/functions starting with
      either `add_` or `set_` are passed through as-is. e.g.:

            ${green}[target.aithing]
            flies = "src/**.cpp"    <-- spelling mistake (files) will be caught
            set_bananas = "nom nom" <-- will be in xmake.lua and caught by xmake
      ${clear} 
      We can use nested arrays, so this (multiline too):

            ${green}includes = [ [ "include", { public = true } ], 
                    [ "ext", "internal", "src" ] ]
      ${clear} 
      ... is allowed and becomes:

            ${green}add_includes("include", { public = true })
            add_includes("ext", "internal", "src")
      ${clear} 
      Remember that when you create an object, a target/option etc in xmake.toml 
      you *extend* it when referring to it in the xmake.build.lua script! So e.g:
        
        xmake.toml:
    
            ${green}[target.app]
            kind = "binary"
            files = "src/**.cpp"
    
        ${clear} xmake.build.lua:
    
            ${green}target("app")
                add_defines("MEOW")
      ${clear}  
      ... is the same as adding a `defines = "MEOW"` to the TOML file.


]=]


-- rest of luatoml and credit at end of plugin code
local TOML = {
	-- denotes the current supported TOML version
	version = 0.40,

	-- sets whether the parser should follow the TOML spec strictly
	-- currently, no errors are thrown for the following rules if strictness is turned off:
	--   tables having mixed keys
	--   redefining a table
	--   redefining a key within a table
	strict = true,

    -- allow mixed types in arrays
    mixed_types = true,

    -- return tables as Lua arrays to preserve orders, but make iterating less direct
    preserve_table_ordering = true
}

local toml = TOML


local xmake_string = "-- this file was autogenerated by xtoml.lua\n\n"


--
local function append(str)
    xmake_string = xmake_string .. tostring(str) .. "\n"
end


--
local function read_file(filename)
    cprintf("checking for xmake.toml file in: '%s' ... ", os.workingdir())
    local fh = io.open(filename, "r")
    if not fh then
        cprintf("\n${red}Error, could not open '%s'.\n", tostring(filename))
        os.exit(1)
    end
    cprint("${green} found")

    local xmake = fh:read("*all")
    fh:close()
    return xmake
end

-- forward declare the table used to store TOML in Lua table format
local xarray

--
-- some common functions used in xmake can be used in shorthand form
--
local func_maps = {
    project = {
        -- xmakebuildfile         <-- handled seperately, including this will generate and include an `xmake.build.lua` file
        name =  "set_project",
        version = "set_version",
        license = "set_license",
        rules = "add_rules",
        languages = "set_languages",
        description = "set_description",
        warnings = "set_warnings",
        optimize = "set_optimize",
        optimise = "set_optimize"
    },
    target = {
        cflags = "add_cflags",
        configfiles = "add_configfiles",
        configvar = "set_configvar",
        cxxflags = "add_cxxflags",
        default = "set_default",
        defines = "add_defines",
        deps = "add_deps",
        files = "add_files",
        group = "set_group",                
        headerfiles = "add_headerfiles",
        includedirs = "add_includedirs",
        includes = "add_includedirs",
        installfiles = "add_installfiles",
        kind = "set_kind",
        languages = "add_languages", -- there is also set_languages
        ldflags = "add_ldflags",
        links = "add_links",
        linkdirs = "add_linkdirs",
        options = "add_options",
        sysincludedirs = "add_sysincludedirs",
        syslinks = "add_syslinks",
        rpaths = "add_rpathdirs",
        rpathdirs = "add_rpathdirs",
        rules = "add_rules",
        rundir = "set_rundir",
        runtimes = "set_runtimes",
        packages = "add_packages",
        pcheader = "set_pcheader",
        pcxxheader = "set_pcxxheader",
        pmheader = "set_pmheader",
        pmxxheader = "set_pmxxheader",
        prefix = "set_prefix",
        toolchains = "set_toolchains",
        toolset = "set_toolset",
        undefines = "add_undefines",
        vectorexts = "add_vectorexts",
    }
}


--
local function getfunctionname(section, field_name)

    local section_map
    if section == "option" then 
        section_map = func_maps["target"]
    else
        section_map = func_maps[section]
    end

    assert(section_map, "Error: section title '" .. section .. "' does not exist. Exiting.")
    
    -- allow any entry that starts with set_ or add_ ...
    if field_name:match("^set_.*$") or field_name:match("^add_.*$") then return field_name end

    -- ... otherwise check if a short version is valid (on the (incomplete) list)
    local name = section_map[field_name]

    assert(name, "Error: field name '" .. field_name .. "' for section '" .. section
                .. "' does not have a matching xmake function (e.g. set_kind/add_files etc).")

    return name
end


--
local function stringify(arg, add_parens)
    local str = "\"" .. tostring(arg) .. "\""
    if add_parens then
        str = "(" .. str .. ")"
    end

    return str
end


-- iterator for single k/v pairs stored in array
local function iarraypairs(t)
    local idx = 0 
    
    local function iter()
        idx = idx + 1
        if not t or t[idx] == nil then return nil end
        return pairs(t[idx])(t[idx])
    end

    return iter
end


--
-- iterate through section tables by name (e.g.'target', 'require')
--
local function sectioniterator(t, name)
    local idx = 0
    local name = name

    local function iter()
        idx = idx + 1
        while t[idx] and t[idx][1] ~= name do
            idx = idx + 1
        end
        if t[idx] == nil then return nil end
        return t[idx][2]
    end

    return iter
end

--
local function getsectionnames(t)
    local section_names = {}
    for _, section in ipairs(t) do
        table.insert(section_names, section[1])
    end

    return section_names
end

--
local function getsectionbyname(t, sectionname)
    -- some named sections can be repeated (e.g. [requires] and [requires.lua])
    local section_collection = {}
    for _, sectiontable in ipairs(t) do
        if sectiontable[1] == sectionname then
            table.insert(section_collection, sectiontable[2])
        end
    end
    
    -- return a table even if it's just one for consistent handling
    return #section_collection > 0 and section_collection or nil
end


--
local function trimbraces(str, fail_silently)
    if str:len() < 2 then 
        if not fail_silently then return false end
    else
        if str:startswith("{") and str:endswith("}") then
            return str:sub(2, -2):trim()
        end
    end
    
    return fail_silently and str or false
end


--
local function xtabletostring(t, first)
    if type(t) == "string" then return stringify(t) end
    if first == nil then first = true end
    local res = "{ "

    for k, v in pairs(t) do
        if not first then res = res .. ", " end
        if type(k) == "string" then
            res = res .. tostring(k) .. " = "
        end
        if type(v) == "table" then
            res = res .. xtabletostring(v, true)
        else 
            if type(k) == "number" then
                res = res .. stringify(v) 
            else 
                res = res .. tostring(v) 
            end
        end
        first = false
    end
    res = res .. " }"
    
    return res
end


-- special case because:
--     [requires]
--     fmt = "v1.4" 
--     
--     [requires.fmt]
--     version = "v1.4"
--
-- both become `add_requires("fmt v1.4")` and both have a different table layout
local function requiretostring(section_table)
    local res = ""
    for idx, element in ipairs(section_table) do

        local lib = ""
        for k, v in pairs(element) do
            
            -- check if it's a simple k/v pair (e.g.fmt = "v1.4")
            if type(k) == "string" and type(v) ~= "table" then
                res = res .. "add_requires" .. stringify(k .. " " .. tostring(v), true) .. "\n" 

            elseif type(k) == "string" and type(v) == "table" then
                local lib = ""
                if type(v[1]) == "string" then
                    lib = stringify(k .. " " .. v[1])
                    res = res .. "add_requires(" .. lib .. ", " .. xtabletostring(v[2]) .. ")" 
                else
                    res = res .. "add_requires" .. stringify(trimbraces(xtabletostring(v)), true) .. ""
                end

            else

                -- handle subsections (e.g. [requires.fmt]) in two iterations of the current loop
                -- since the name is stored first and the second entry contains the details
                if k == 1 and type(v) == "string" then
                    lib = v

                elseif k == 2 and type(v) == "table" and lib ~= "" then
                    local version = ""
                    local t = {}
                    for n, f in iarraypairs(v) do
                        if n == "version" then
                            lib = lib .. " " .. f
                        else
                            t[n] = f
                        end
                    end
                    res = res .. "add_requires(" .. stringify(lib) .. ", " .. xtabletostring(t) .. ")\n"
                end
            end
        end
    end
    
    return res
end


--
local function writefile(filename, contents, overwrite)
    if not overwrite then
        if os.exists(filename) then
            return false
        end
    end
    local f = io.open(filename, "w")
    if not f then return false end
    f:write(contents)
    f:close()

    return true
end


--
local section_funcs = {
    project = function(p) 
            v = p[1]

            local s = ""
            for k, v in ipairs(v) do
                local k, v = pairs(v)(v)
                if k == "xmakebuildfile" and v == true then
                    assert(writefile(path.join(os.workingdir(), "xmake.build.lua"), "-- autogenerated by xtoml.lua: for manual editing\n\n", false)
                            , "Error: could not write xmake.build.lua")

                    cprint("${yellow}xmake.build.lua file created")
                    append("\nincludes(\"xmake.build.lua\")\n\n")
                else
                    local fn = getfunctionname("project", k)
                    s = s .. fn .. "(" .. trimbraces(xtabletostring(v), true) .. ")\n"
                end
            end
            append(s)
        end,

    option = function(o) 
            -- options are always sub-sections... e.g. `[options.safety]`
            for _, v in ipairs(o[1]) do
                append("option(" .. stringify(v[1]) .. ")")
                for k, v in iarraypairs(v[2]) do
                    append("    " .. getfunctionname("option", tostring(k)) .. "(" ..
                            trimbraces(xtabletostring(v), true) .. ")\n")
                end
            end
    end,

    requires = function(r)
            for _, v in ipairs(r) do
                append(requiretostring(v))
            end
        end,

    target = function(t) 
            for _, v in ipairs(t) do
                -- ignore outer containing table
                local target = v[1] 

                local target_name = target[1]
                append("target(" .. stringify(target_name) .. ")" )

                for k, v in iarraypairs(target[2]) do
                    local fname = getfunctionname("target", k)
                    if type(v) ~= "table" then
                        append("    " .. fname .. "(\"" .. tostring(v) .. "\")")
                    else
                        if type(v[1]) ~= "table" then
                            append("    " .. getfunctionname("target", k) 
                                .. "(" .. trimbraces(xtabletostring(v)) .. ")")
                        else
                            for _, t in ipairs(v) do
                                append("    " .. getfunctionname("target", k) 
                                    .. "(" .. trimbraces(xtabletostring(t)) .. ")")
                            end
                        end
                    end
                end
                append("\n")
            end
        end
}


--
local function processsection(t, section_name)
    local section = getsectionbyname(t, section_name)
    local maybefunc = section_funcs[section_name] 

    if maybefunc then 
        maybefunc(section) 
        return true
    end

    return false
end


--
function main(arg)

    if option:get("help") or arg == "-h" or arg == "--help" then
        cprint(help_string)
        os.exit(0)
    end
    
    local toml_file = path.join(os.workingdir(), "xmake.toml")
    assert(toml_file, "Error: xmake.toml file in location '%s' does not exist.", toml_file)
    xarray = toml.parse(read_file(toml_file))

    -- declare supported sections here
    local SNAME, SREQUIRED = 1, 2
    local sections = { { "project", false }, { "requires", false }, { "option", false }, { "target", true } }

    local section_names = table.unique(getsectionnames(xarray))

    -- validate section names found in xmake.toml
    for _, sn in ipairs(section_names) do
        local found = false 
        for _, name in iarraypairs(sections) do
            if sn == name then found = true ; break end
        end

        assert(found, "${red}Error: unsupported section '" .. sn .. "' found in xmake.toml file." 
                    .. " Please check and consider adding the section to the xmake.build.lua file.")
        found = false
    end

    -- check for missing required sections
    for _, section in ipairs(sections) do
        assert(not (section[SREQUIRED] == true and not getsectionbyname(xarray, section[SNAME]))
                , "${red}Error: project must have a '" .. section[SNAME] .. "' section.\n")
    end

    for _ ,section_name in ipairs(section_names) do
        cprintf("converting '%s' section(s) ... ", section_name)
        processsection(xarray, section_name)
        cprint("${green} ok")
    end

    writefile(path.join(os.workingdir(), "xmake.lua"), xmake_string, true)

end


-----------------------------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------
--
-- the following TOML handling code is: 
--
--      lua-toml: https://github.com/jonstoler/lua-toml/tree/master
--
--          Copyright (c) 2017 Jonathan Stoler, MIT License. 
--
-- modified to optionally prefer ordered arrays over unordered pairs and to allow 
-- mixed types in arrays
--

local function error(msg)
    cprint("${red}Error: " .. tostring(msg))
    os.exit(1)
end

-- converts TOML data into a lua table
TOML.parse = function(toml, options)
	options = options or {}
	local strict = (options.strict ~= nil and options.strict or TOML.strict)

	-- the official TOML definition of whitespace
	local ws = "[\009\032]"

	-- the official TOML definition of newline
	local nl = "[\10"
	do
		local crlf = "\13\10"
		nl = nl .. crlf
	end
	nl = nl .. "]"
	
	-- stores text data
	local buffer = ""

	-- the current location within the string to parse
	local cursor = 1

	-- the output table
	local out = {}

	-- the current table to write to
	local obj = out

	-- returns the next n characters from the current position
	local function char(n)
		n = n or 0
		return toml:sub(cursor + n, cursor + n)
	end

	-- moves the current position forward n (default: 1) characters
	local function step(n)
		n = n or 1
		cursor = cursor + n
	end

	-- move forward until the next non-whitespace character
	local function skipWhitespace()
		while(char():match(ws)) do
			step()
		end
	end

	-- remove the (Lua) whitespace at the beginning and end of a string
	local function trim(str)
		return str:gsub("^%s*(.-)%s*$", "%1")
	end

	-- divide a string into a table around a delimiter
	local function split(str, delim)
		if str == "" then return {} end
		local result = {}
		local append = delim
		if delim:match("%%") then
			append = delim:gsub("%%", "")
		end
		for match in (str .. append):gmatch("(.-)" .. delim) do
			table.insert(result, match)
		end
		return result
	end

	-- produce a parsing error message
	-- the error contains the line number of the current position
	local function err(message, strictOnly)
		if not strictOnly or (strictOnly and strict) then
			local line = 1
			local c = 0
			for l in toml:gmatch("(.-)" .. nl) do
				c = c + l:len()
				if c >= cursor then
					break
				end
				line = line + 1
			end
			error("TOML: " .. message .. " on line " .. line .. ".", 4)
		end
	end

	-- prevent infinite loops by checking whether the cursor is
	-- at the end of the document or not
	local function bounds()
		return cursor <= toml:len()
	end

	local function parseString()
		local quoteType = char() -- should be single or double quote

		-- this is a multiline string if the next 2 characters match
		local multiline = (char(1) == char(2) and char(1) == char())

		-- buffer to hold the string
		local str = ""

		-- skip the quotes
		step(multiline and 3 or 1)

		while(bounds()) do
			if multiline and char():match(nl) and str == "" then
				-- skip line break line at the beginning of multiline string
				step()
			end

			-- keep going until we encounter the quote character again
			if char() == quoteType then
				if multiline then
					if char(1) == char(2) and char(1) == quoteType then
						step(3)
						break
					end
				else
					step()
					break
				end
			end

			if char():match(nl) and not multiline then
				err("Single-line string cannot contain line break")
			end

			-- if we're in a double-quoted string, watch for escape characters!
			if quoteType == '"' and char() == "\\" then
				if multiline and char(1):match(nl) then
					-- skip until first non-whitespace character
					step(1) -- go past the line break
					while(bounds()) do
						if not char():match(ws) and not char():match(nl) then
							break
						end
						step()
					end
				else
					-- all available escape characters
					local escape = {
						b = "\b",
						t = "\t",
						n = "\n",
						f = "\f",
						r = "\r",
						['"'] = '"',
						["\\"] = "\\",
					}
					-- utf function from http://stackoverflow.com/a/26071044
					-- converts \uXXX into actual unicode
					local function utf(char)
						local bytemarkers = {{0x7ff, 192}, {0xffff, 224}, {0x1fffff, 240}}
						if char < 128 then return string.char(char) end
						local charbytes = {}
						for bytes, vals in pairs(bytemarkers) do
							if char <= vals[1] then
								for b = bytes + 1, 2, -1 do
									local mod = char % 64
									char = (char - mod) / 64
									charbytes[b] = string.char(128 + mod)
								end
								charbytes[1] = string.char(vals[2] + char)
								break
							end
						end
						return table.concat(charbytes)
					end

					if escape[char(1)] then
						-- normal escape
						str = str .. escape[char(1)]
						step(2) -- go past backslash and the character
					elseif char(1) == "u" then
						-- utf-16
						step()
						local uni = char(1) .. char(2) .. char(3) .. char(4)
						step(5)
						uni = tonumber(uni, 16)
						if (uni >= 0 and uni <= 0xd7ff) and not (uni >= 0xe000 and uni <= 0x10ffff) then
							str = str .. utf(uni)
						else
							err("Unicode escape is not a Unicode scalar")
						end
					elseif char(1) == "U" then
						-- utf-32
						step()
						local uni = char(1) .. char(2) .. char(3) .. char(4) .. char(5) .. char(6) .. char(7) .. char(8)
						step(9)
						uni = tonumber(uni, 16)
						if (uni >= 0 and uni <= 0xd7ff) and not (uni >= 0xe000 and uni <= 0x10ffff) then
							str = str .. utf(uni)
						else
							err("Unicode escape is not a Unicode scalar")
						end
					else
						err("Invalid escape")
					end
				end
			else
				-- if we're not in a double-quoted string, just append it to our buffer raw and keep going
				str = str .. char()
				step()
			end
		end

		return {value = str, type = "string"}
	end

	local function parseNumber()
		local num = ""
		local exp
		local date = false
		while(bounds()) do
			if char():match("[%+%-%.eE_0-9]") then
				if not exp then
					if char():lower() == "e" then
						-- as soon as we reach e or E, start appending to exponent buffer instead of
						-- number buffer
						exp = ""
					elseif char() ~= "_" then
						num = num .. char()
					end
				elseif char():match("[%+%-0-9]") then
					exp = exp .. char()
				else
					err("Invalid exponent")
				end
			elseif char():match(ws) or char() == "#" or char():match(nl) or char() == "," or char() == "]" or char() == "}" then
				break
			elseif char() == "T" or char() == "Z" then
				-- parse the date (as a string, since lua has no date object)
				date = true
				while(bounds()) do
					if char() == "," or char() == "]" or char() == "#" or char():match(nl) or char():match(ws) then
						break
					end
					num = num .. char()
					step()
				end
			else
				err("Invalid number")
			end
			step()
		end

		if date then
			return {value = num, type = "date"}
		end

		local float = false
		if num:match("%.") then float = true end

		exp = exp and tonumber(exp) or 0
		num = tonumber(num)

		if not float then
			return {
				-- lua will automatically convert the result
				-- of a power operation to a float, so we have
				-- to convert it back to an int with math.floor
				value = math.floor(num * 10^exp),
				type = "int",
			}
		end

		return {value = num * 10^exp, type = "float"}
	end

	local parseArray, getValue
	
	function parseArray()
		step() -- skip [
		skipWhitespace()

		local arrayType
		local array = {}

		while(bounds()) do
			if char() == "]" then
				break
			elseif char():match(nl) then
				-- skip
				step()
				skipWhitespace()
			elseif char() == "#" then
				while(bounds() and not char():match(nl)) do
					step()
				end
			else
				-- get the next object in the array
				local v = getValue()
				if not v then break end

				-- set the type if it hasn't been set before
				if arrayType == nil then
					arrayType = v.type
				elseif TOML.mixed_types == false and arrayType ~= v.type then
					err("Mixed types in array", true)
				end

				array = array or {}
				table.insert(array, v.value)
				
				if char() == "," then
					step()
				end
				skipWhitespace()
			end
		end
		step()

		return {value = array, type = "array"}
	end

	local function parseInlineTable()
		step() -- skip opening brace

		local buffer = ""
		local quoted = false
		local tbl = {}

		while bounds() do
			if char() == "}" then
				break
			elseif char() == "'" or char() == '"' then
				buffer = parseString().value
				quoted = true
			elseif char() == "=" then
				if not quoted then
					buffer = trim(buffer)
				end

				step() -- skip =
				skipWhitespace()

				if char():match(nl) then
					err("Newline in inline table")
				end

				local v = getValue().value

				tbl[buffer] = v

				skipWhitespace()

				if char() == "," then
					step()
				elseif char():match(nl) then
					err("Newline in inline table")
				end

				quoted = false
				buffer = ""
			else
				buffer = buffer .. char()
				step()
			end
		end
		step() -- skip closing brace

		return {value = tbl, type = "array"}
	end

	local function parseBoolean()
		local v
		if toml:sub(cursor, cursor + 3) == "true" then
			step(4)
			v = {value = true, type = "boolean"}
		elseif toml:sub(cursor, cursor + 4) == "false" then
			step(5)
			v = {value = false, type = "boolean"}
		else
			err("Invalid primitive")
		end

		skipWhitespace()
		if char() == "#" then
			while(not char():match(nl)) do
				step()
			end
		end

		return v
	end

	-- figure out the type and get the next value in the document
	function getValue()
		if char() == '"' or char() == "'" then
			return parseString()
		elseif char():match("[%+%-0-9]") then
			return parseNumber()
		elseif char() == "[" then
			return parseArray()
		elseif char() == "{" then
			return parseInlineTable()
		else
			return parseBoolean()
		end
		-- date regex (for possible future support):
		-- %d%d%d%d%-[0-1][0-9]%-[0-3][0-9]T[0-2][0-9]%:[0-6][0-9]%:[0-6][0-9][Z%:%+%-%.0-9]*
	end

	-- track whether the current key was quoted or not
	local quotedKey = false
	
	-- parse the document!
	while(cursor <= toml:len()) do

		-- skip comments and whitespace
		if char() == "#" then
			while(not char():match(nl)) do
				step()
			end
		end

		if char():match(nl) then
			-- skip
		end

		if char() == "=" then
			step()
			skipWhitespace()
			
			-- trim key name
			buffer = trim(buffer)

			if buffer:match("^[0-9]*$") and not quotedKey then
				buffer = tonumber(buffer)
			end

			if buffer == "" and not quotedKey then
				err("Empty key name")
			end

			local v = getValue()
			if v then
				-- if the key already exists in the current object, throw an error
                -- TODO: need to scan array to check for duplicates when preserving ordering
				if obj[buffer] then
					err('Cannot redefine key "' .. buffer .. '"', true)
				end

                if TOML.preserve_table_ordering then
                    obj[#obj + 1] = { [buffer] = v.value }
                else
                    obj[buffer] = v.value
                end
			end

			-- clear the buffer
			buffer = ""
			quotedKey = false

			-- skip whitespace and comments
			skipWhitespace()
			if char() == "#" then
				while(bounds() and not char():match(nl)) do
					step()
				end
			end

			-- if there is anything left on this line after parsing a key and its value,
			-- throw an error
			if not char():match(nl) and cursor < toml:len() then
				err("Invalid primitive")
			end
		elseif char() == "[" then
			buffer = ""
			step()
			local tableArray = false

			-- if there are two brackets in a row, it's a table array!
			if char() == "[" then
				tableArray = true
				step()
			end

			obj = out

			local function processKey(isLast)
				isLast = isLast or false
				buffer = trim(buffer)

				if not quotedKey and buffer == "" then
					err("Empty table name")
				end

				if isLast and obj[buffer] and not tableArray and #obj[buffer] > 0 then
					err("Cannot redefine table", true)
				end

				-- set obj to the appropriate table so we can start
				-- filling it with values!
				if tableArray then
					-- push onto cache
                    print("tableArray: " .. tostring(buffer))
					if obj[buffer] then
						obj = obj[buffer]
						if isLast then
							table.insert(obj, {})
						end
						obj = obj[#obj]
					else
						obj[buffer] = {}
						obj = obj[buffer]
						if isLast then
							table.insert(obj, {})
							obj = obj[1]
						end
					end
				else
                    if (TOML.preserve_table_ordering == true) then
                        if (obj[buffer] == nil) then

                            obj[#obj + 1] = { buffer, {} }
                        end
                    
                        obj = obj[#obj][2]
                    else
                        obj[buffer] = obj[buffer] or {}
                        obj = obj[buffer]
                    end
				end
			end

			while(bounds()) do
				if char() == "]" then
					if tableArray then
						if char(1) ~= "]" then
							err("Mismatching brackets")
						else
							step() -- skip inside bracket
						end
					end
					step() -- skip outside bracket

					processKey(true)
					buffer = ""
					break
				elseif char() == '"' or char() == "'" then
					buffer = parseString().value
					quotedKey = true
				elseif char() == "." then
					step() -- skip period
					processKey()
					buffer = ""
				else
					buffer = buffer .. char()
					step()
				end
			end

			buffer = ""
			quotedKey = false
		elseif (char() == '"' or char() == "'") then
			-- quoted key
			buffer = parseString().value
			quotedKey = true
		end

		buffer = buffer .. (char():match(nl) and "" or char())
		step()
	end

	return out
end

TOML.encode = function(tbl)
	local toml = ""

	local cache = {}

	local function parse(tbl)
		for k, v in pairs(tbl) do
			if type(v) == "boolean" then
				toml = toml .. k .. " = " .. tostring(v) .. "\n"
			elseif type(v) == "number" then
				toml = toml .. k .. " = " .. tostring(v) .. "\n"
			elseif type(v) == "string" then
				local quote = '"'
				v = v:gsub("\\", "\\\\")

				-- if the string has any line breaks, make it multiline
				if v:match("^\n(.*)$") then
					quote = quote:rep(3)
					v = "\\n" .. v
				elseif v:match("\n") then
					quote = quote:rep(3)
				end

				v = v:gsub("\b", "\\b")
				v = v:gsub("\t", "\\t")
				v = v:gsub("\f", "\\f")
				v = v:gsub("\r", "\\r")
				v = v:gsub('"', '\\"')
				v = v:gsub("/", "\\/")
				toml = toml .. k .. " = " .. quote .. v .. quote .. "\n"
			elseif type(v) == "table" then
				local array, arrayTable = true, true
				local first = {}
				for kk, vv in pairs(v) do
					if type(kk) ~= "number" then array = false end
					if type(vv) ~= "table" then
						v[kk] = nil
						first[kk] = vv
						arrayTable = false
					end
				end

				if array then
					if arrayTable then
						-- double bracket syntax go!
						table.insert(cache, k)
						for kk, vv in pairs(v) do
							toml = toml .. "[[" .. table.concat(cache, ".") .. "]]\n"
							for k3, v3 in pairs(vv) do
								if type(v3) ~= "table" then
									vv[k3] = nil
									first[k3] = v3
								end
							end
							parse(first)
							parse(vv)
						end
						table.remove(cache)
					else
						-- plain ol boring array
						toml = toml .. k .. " = [\n"
						for kk, vv in pairs(first) do
							toml = toml .. tostring(vv) .. ",\n"
						end
						toml = toml .. "]\n"
					end
				else
					-- just a key/value table, folks
					table.insert(cache, k)
					toml = toml .. "[" .. table.concat(cache, ".") .. "]\n"
					parse(first)
					parse(v)
					table.remove(cache)
				end
			end
		end
	end
	
	parse(tbl)
	
	return toml:sub(1, -2)
end

---------------------------------------------^------------^-----------^------------------------------------------------
