--!nonstrict
-- Detail panel: one row per agent session with project, session title and
-- status. Re-renders live while open via the shared "island" state.

local data = noctalia.state.get("island")

local STATUS_STYLE = {
	working = { glyph = "loader", color = "primary" },
	idle = { glyph = "check", color = "on_surface_variant" },
}

local function styleFor(status)
	return STATUS_STYLE[status] or { glyph = "alert-triangle", color = "error" }
end

local function agentRows()
	local agents = if type(data) == "table" then data.agents or {} else {}
	if type(data) ~= "table" or not data.available then
		return {
			ui.label({
				text = "herdr が起動していません",
				color = "on_surface_variant",
			}),
		}
	end
	if #agents == 0 then
		return {
			ui.label({
				text = "エージェントセッションはありません",
				color = "on_surface_variant",
			}),
		}
	end

	local rows = {}
	for _, a in ipairs(agents) do
		local style = styleFor(a.status)
		local title = if a.title ~= "" then a.title else a.pane_id
		table.insert(
			rows,
			ui.row({ gap = 12, align = "center" }, {
				ui.glyph({ name = style.glyph, size = 16, color = style.color }),
				ui.column({ gap = 2, flexGrow = 1 }, {
					ui.row({ gap = 8, align = "center" }, {
						ui.label({
							text = `{a.project}`,
							fontWeight = "bold",
							color = "on_surface",
						}),
						ui.label({
							text = if a.focused then "● focused" else "",
							fontSize = 10,
							color = "primary",
						}),
					}),
					ui.label({
						text = title,
						fontSize = 12,
						color = "on_surface_variant",
					}),
				}),
				ui.label({ text = a.status, fontSize = 12, color = style.color }),
			})
		)
	end
	return rows
end

local function render()
	local working = if type(data) == "table" then data.working or 0 else 0
	panel.render(ui.column({ flexGrow = 1, gap = 16 }, {
		ui.row({ align = "center", justify = "space_between", gap = 8 }, {
			ui.row({ gap = 8, align = "center", flexGrow = 1 }, {
				ui.glyph({ name = "robot", size = 18, color = "primary" }),
				ui.label({
					text = "Vibe Island",
					fontSize = 16,
					fontWeight = "bold",
					color = "on_surface",
				}),
				ui.label({
					text = `{working} working`,
					fontSize = 12,
					color = "on_surface_variant",
				}),
			}),
			ui.button({
				glyph = "close",
				onClick = function()
					panel.close()
				end,
			}),
		}),
		ui.scroll({ flexGrow = 1, gap = 12, align = "stretch" }, agentRows()),
	}))
end

noctalia.state.watch("island", function(value)
	data = value
	render()
end)

function onOpen()
	render()
end
