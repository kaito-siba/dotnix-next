--!nonstrict
-- Bar widget: the island itself. Shows how many agents are working plus an
-- attention badge; hides entirely when herdr is absent or no agent session
-- exists. Click opens the detail panel.

local data = noctalia.state.get("island")

local function render()
	if type(data) ~= "table" or not data.available or (data.total or 0) == 0 then
		barWidget.setVisible(false)
		return
	end
	barWidget.setVisible(true)

	local working = data.working or 0
	local attention = data.attention or 0

	local container = if barWidget.isVertical() then ui.column else ui.row
	local children = {
		ui.glyph({
			name = "robot",
			size = 14,
			color = if working > 0 then "primary" else "on_surface_variant",
		}),
	}
	if working > 0 then
		table.insert(
			children,
			ui.row({ fill = "primary/0.25", radius = 8, paddingH = 6, align = "center" }, {
				ui.label({ text = tostring(working), color = "primary", fontWeight = "bold" }),
			})
		)
	end
	if attention > 0 then
		table.insert(
			children,
			ui.row({ fill = "error/0.25", radius = 8, paddingH = 6, align = "center" }, {
				ui.label({ text = tostring(attention), color = "error", fontWeight = "bold" }),
			})
		)
	end
	barWidget.render(container({ gap = 6, align = "center" }, children))

	local rows = {}
	for _, a in ipairs(data.agents or {}) do
		local title = if a.title ~= "" then a.title else a.pane_id
		table.insert(rows, { key = `{a.project} [{a.status}]`, value = title })
	end
	barWidget.setTooltip(rows)
end

noctalia.state.watch("island", function(value)
	data = value
	render()
end)

function update()
	noctalia.setUpdateInterval(2000)
	render()
end

function onClick()
	noctalia.togglePanel("kaito/vibe-island:panel")
end
