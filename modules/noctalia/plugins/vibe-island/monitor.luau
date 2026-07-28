--!nonstrict
-- Headless service: polls the herdr snapshot via the bundled python helper and
-- publishes one composite state value ("island") for the widget and panel.
--
-- Status transitions raise desktop notifications:
--   working -> idle       the agent finished its turn
--   working -> <other>    the agent needs attention (permission prompt, etc.)
--
-- When herdr is not running the state carries available = false and the bar
-- widget hides itself, like the real island.

local POLL_MS = 2000

local helper = nil
do
	local dir = noctalia.pluginDir()
	if dir then
		helper = `python3 "{dir}/herdr-snapshot.py"`
	end
end

local last = nil -- pane_id -> status, nil until the first successful poll
local inflight = false

noctalia.setUpdateInterval(POLL_MS)

local function publish(available, agents)
	local working, attention = 0, 0
	for _, a in ipairs(agents) do
		if a.status == "working" then
			working += 1
		elseif a.status ~= "idle" then
			attention += 1
		end
	end
	noctalia.state.set("island", {
		available = available,
		agents = agents,
		working = working,
		attention = attention,
		total = #agents,
		stamp = noctalia.nowMs(),
	})
end

local function notifyTransitions(agents)
	if last ~= nil then
		for _, a in ipairs(agents) do
			local prev = last[a.pane_id]
			if prev == "working" and a.status == "idle" then
				local what = if a.title ~= "" then a.title else "エージェントのターンが完了"
				noctalia.notify(`✅ {a.project}`, what)
			elseif prev == "working" and a.status ~= "working" then
				noctalia.notify(`⚠ {a.project}`, `確認待ち ({a.status})`)
			end
		end
	end
	local seen = {}
	for _, a in ipairs(agents) do
		seen[a.pane_id] = a.status
	end
	last = seen
end

function update()
	if not helper or inflight then
		return
	end
	inflight = true
	noctalia.runAsync(helper, function(res)
		inflight = false
		if res.exitCode ~= 0 or res.timedOut then
			publish(false, {})
			return
		end
		local data = noctalia.json.decode(res.stdout)
		if type(data) ~= "table" or not data.ok then
			publish(false, {})
			return
		end
		notifyTransitions(data.agents or {})
		publish(true, data.agents or {})
	end, 5000)
end
