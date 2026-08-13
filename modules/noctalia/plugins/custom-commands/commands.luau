--!nonstrict
-- Launcher provider: lists the commands declared in commands.json (shipped
-- next to this script) and runs the selected one detached via runAsync.
--
-- commands.json entry shape:
--   { "name": string, "command": string, "icon": string?, "description": string? }

local commands = {}
do
	local raw = noctalia.readFile("commands.json")
	if raw then
		local decoded = noctalia.json.decode(raw)
		if type(decoded) == "table" then
			commands = decoded
		end
	end
end

local function rows(filter)
	local out = {}
	for i, cmd in ipairs(commands) do
		local score = 1
		if filter ~= "" then
			score = noctalia.fuzzyScore(filter, cmd.name or "")
		end
		if score then
			table.insert(out, {
				id = tostring(i),
				title = cmd.name or cmd.command,
				subtitle = cmd.description or cmd.command,
				glyph = cmd.icon or "terminal-2",
				score = score,
			})
		end
	end
	if #out == 0 then
		out[1] = { id = "", title = "No matching command", glyph = "mood-empty" }
	end
	return out
end

function onQuery(query)
	launcher.setResults(query, rows(noctalia.string.trim(query)))
end

function onActivate(id)
	local index = tonumber(id)
	local cmd = if index then commands[index] else nil
	if cmd and cmd.command then
		-- 引数なし runAsync は detached fire-and-forget 起動
		noctalia.runAsync(cmd.command)
	end
end
