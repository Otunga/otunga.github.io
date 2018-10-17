--[[--
This module contains all the functions that handle commands in NutScript.

You can easily add a command to NutScript by using the nut.command.add function.
In order to do that, you must name the command and create a table with certain
fields that enable you to set a function that runs once you evoke the command.

<b>The table should have the fields as follows:</b>

<ul>
<li><b>`syntax`</b></br>
(default: "[none]" | optional: yes) </br>
This allows you to setup a syntax for the command.
</li>
<li><b>`adminOnly`</b></br>
(default: "false" | optional: yes) </br>
This allows you to restrict the command to administrators only.
</li>
<li><b>`superAdminOnly`</b></br>
(default: "false" | optional: yes) </br>
This allows you to restrict the command to superadministrators only.
</li>
<li><b>`group`</b></br>
(default: nil | optional: yes) </br>
This allows you to restrict the command to one or more user groups. This can
either be a table or a string.
</li>
<li><b>`onCheckAccess`</b></br>
(default: nil | optional: yes) </br>
This allows you to restrict the command with a function.
</li>
<li><b>`onRun`</b></br>
(default: nil | optional: no) </br>
This field contains the function that is executed once the command is evoked.
This function has `client` and `arguments` as arguments.
</li>
<li><b>`alias`</b></br>
(default: nil | optional: yes) </br>
This allows you to set alias to your command. This can either be one (a string) or
more (a table).
</li>
</ul>

]]
-- @module nut.command

nut.command = nut.command or {}
nut.command.list = nut.command.list or {}

local COMMAND_PREFIX = "/"

--- Adds a new command to the list of commands.
-- This function adds the command and its data to `nut.command.list`.
-- @string command the command.
-- @param data a table.
-- @return Error if onRun field is nil or nothing.
-- @usage
--nut.command.add("toggleraise", {
--	onRun = function(client, arguments)
--		if ((client.nutNextToggle or 0) < CurTime()) then
--			client:toggleWepRaised()
--			client.nutNextToggle = CurTime() + 0.5
--		end
--	end
--})

function nut.command.add(command, data)
	-- For showing users the arguments of the command.
	data.syntax = data.syntax or "[none]"

	-- Why bother adding a command if it doesn't do anything.
	if (!data.onRun) then
		return ErrorNoHalt("Command '"..command.."' does not have a callback, not adding!\n")
	end

	-- Store the old onRun because we're able to change it.
	if (!data.onCheckAccess) then
		-- Check if the command is for basic admins only.
		if (data.adminOnly) then
			data.onCheckAccess = function(client)
				return client:IsAdmin()
			end
		-- Or if it is only for super administrators.
		elseif (data.superAdminOnly) then
			data.onCheckAccess = function(client)
				return client:IsSuperAdmin()
			end
		-- Or if we specify a usergroup allowed to use this.
		elseif (data.group) then
			-- The group property can be a table of usergroups.
			if (type(data.group) == "table") then
				data.onCheckAccess = function(client)
					-- Check if the client's group is allowed.
					for k, v in ipairs(data.group) do
						if (client:IsUserGroup(v)) then
							return true
						end
					end

					return false
				end
			-- Otherwise it is most likely a string.
			else
				data.onCheckAccess = function(client)
					return client:IsUserGroup(data.group)
				end		
			end
		end
	end

	local onCheckAccess = data.onCheckAccess

	-- Only overwrite the onRun to check for access if there is anything to check.
	if (onCheckAccess) then
		local onRun = data.onRun

		data._onRun = data.onRun -- for refactoring purpose.
		data.onRun = function(client, arguments)
			if (!onCheckAccess(client)) then
				return "@noPerm"
			else
				return onRun(client, arguments)
			end
		end
	end

	-- Add the command to the list of commands.
	local alias = data.alias

	if (alias) then
		if (type(alias) == "table") then
			for k, v in ipairs(alias) do
				nut.command.list[v] = data
			end
		elseif (type(alias) == "string") then
			nut.command.list[alias] = data
		end
	end

	nut.command.list[command] = data
end

--- Returns whether or not a player is allowed to run a certain command.
-- Returns true if the player is able to use a certain command and false otherwise.
-- @player client a player.
-- @string command the command.
-- @return a boolean value.

function nut.command.hasAccess(client, command)
	command = nut.command.list[command]

	if (command) then
		if (command.onCheckAccess) then
			return command.onCheckAccess(client)
		else
			return true
		end
	end

	return false
end

--- Gets a table of arguments from a string.
-- Extracts the arguments from a command.
-- @string text containing the arguments to be extracted.
-- @return arguments a table.

function nut.command.extractArgs(text)
	local skip = 0
	local arguments = {}
	local curString = ""

	for i = 1, #text do
		if (i <= skip) then continue end

		local c = text:sub(i, i)

		if (c == "\"") then
			local match = text:sub(i):match("%b"..c..c)

			if (match) then
				curString = ""
				skip = i + #match
				arguments[#arguments + 1] = match:sub(2, -2)
			else
				curString = curString..c
			end
		elseif (c == " " and curString != "") then
			arguments[#arguments + 1] = curString
			curString = ""
		else
			if (c == " " and curString == "") then
				continue
			end

			curString = curString..c
		end
	end

	if (curString != "") then
		arguments[#arguments + 1] = curString
	end

	return arguments
end

if (SERVER) then
	--- Finds a player or gives an error notification.
	-- Finds the given player.
	-- @player client a player.
	-- @string name the player's name.
	-- @return target an entity.
	
	function nut.command.findPlayer(client, name)
		local target = type(name) == "string" and nut.util.findPlayer(name) or NULL

		if (IsValid(target)) then
			return target
		else
			client:notifyLocalized("plyNoExist")
		end
	end

	--- Forces a player to run a command.
	-- The functions runs a specific command.
	-- @player client a player.
	-- @string command the command.
	-- @param arguments a table.
	-- @return nothing.
	
	function nut.command.run(client, command, arguments)
		local command = nut.command.list[command]

		if (command) then
			-- Run the command's callback and get the return.
			local results = {command.onRun(client, arguments or {})}
			local result = results[1]
			
			-- If a string is returned, it is a notification.
			if (type(result) == "string") then
				-- Normal player here.
				if (IsValid(client)) then
					if (result:sub(1, 1) == "@") then
						client:notifyLocalized(result:sub(2), unpack(results, 2))
					else
						client:notify(result)
					end
				else
					-- Show the message in server console since we're running from RCON.
					print(result)
				end
			end
		end
	end

	--- Add a function to parse a regular chat string.
	-- The function returns true or false.
	-- @player client a player.
	-- @string text a command.
	-- @string realCommand the command to run.
	-- @param arguments a table.
	-- @return a boolean value.

	function nut.command.parse(client, text, realCommand, arguments)
		if (realCommand or text:utf8sub(1, 1) == COMMAND_PREFIX) then
			-- See if the string contains a command.

			local match = realCommand or text:lower():match(COMMAND_PREFIX.."([_%w]+)")

			if (!match) then
				local post = string.Explode(" ", text)
				local len = string.len(post[1])

				match = post[1]:utf8sub(2, len)
			end

			local command = nut.command.list[match]
			-- We have a valid, registered command.
			if (command) then
				-- Get the arguments like a console command.
				if (!arguments) then
					arguments = nut.command.extractArgs(text:sub(#match + 3))
				end

				-- Runs the actual command.
				nut.command.run(client, match, arguments)

				if (!realCommand) then
					nut.log.add(client, "command", text)
				end
			else
				if (IsValid(client)) then
					client:notifyLocalized("cmdNoExist")
				else
					print("Sorry, that command does not exist.")
				end
			end

			return true
		end

		return false
	end

	concommand.Add("nut", function(client, _, arguments)
		local command = arguments[1]
		table.remove(arguments, 1)

		nut.command.parse(client, nil, command or "", arguments)
	end)

	netstream.Hook("cmd", function(client, command, arguments)
		if ((client.nutNextCmd or 0) < CurTime()) then
			local arguments2 = {}

			for k, v in ipairs(arguments) do
				if (type(v) == "string" or type(v) == "number") then
					arguments2[#arguments2 + 1] = tostring(v)
				end
			end

			nut.command.parse(client, nil, command, arguments2)
			client.nutNextCmd = CurTime() + 0.2
		end
	end)
else
	function nut.command.send(command, ...)
		netstream.Start("cmd", command, {...})
	end
end