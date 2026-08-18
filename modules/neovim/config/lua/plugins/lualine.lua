return {
	-- https://github.com/nvim-lualine/lualine.nvim/issues/1211
	"nvim-lualine/lualine.nvim",
	dependencies = {
		"nvim-tree/nvim-web-devicons",
		"AndreM222/copilot-lualine",
	},
	config = function()
		local lualine = require("lualine")

		-- Accent colors come from the active catppuccin flavour so the
		-- statusline follows the latte/mocha auto switching (colorscheme.lua).
		local function get_colors()
			local flavour = vim.o.background == "light" and "latte" or "mocha"
			local ok, palettes = pcall(require, "catppuccin.palettes")
			if not ok then
				return {
					bg = "#1e1e2e",
					fg = "#cdd6f4",
					yellow = "#f9e2af",
					cyan = "#89dceb",
					darkblue = "#89b4fa",
					green = "#a6e3a1",
					orange = "#fab387",
					violet = "#f5c2e7",
					magenta = "#cba6f7",
					blue = "#74c7ec",
					red = "#f38ba8",
				}
			end
			local p = palettes.get_palette(flavour)
			return {
				bg = p.base,
				fg = p.text,
				yellow = p.yellow,
				cyan = p.sky,
				darkblue = p.blue,
				green = p.green,
				orange = p.peach,
				violet = p.pink,
				magenta = p.mauve,
				blue = p.sapphire,
				red = p.red,
			}
		end

		local conditions = {
			hide_in_width = function()
				return vim.fn.winwidth(0) > 80
			end,
			alpha = function()
				return vim.bo.filetype ~= "alpha"
			end,
		}

		local function show_macro_recording()
			local recording_register = vim.fn.reg_recording()
			if recording_register == "" then
				return ""
			end
			return "󰑋  " .. recording_register
		end

		local function get_buffers()
			local bufs = vim.api.nvim_list_bufs()
			local bufNumb = 0
			local function buffer_is_valid(buf_id, buf_name)
				return 1 == vim.fn.buflisted(buf_id) and buf_name ~= ""
			end
			for idx = 1, #bufs do
				local buf_id = bufs[idx]
				local buf_name = vim.api.nvim_buf_get_name(buf_id)
				if buffer_is_valid(buf_id, buf_name) then
					bufNumb = bufNumb + 1
				end
			end
			return bufNumb .. " "
		end

		local function setup_lualine()
			local colors = get_colors()

			-- The auto theme snapshots highlight groups at require time, so it
			-- has to be re-resolved after every colorscheme change.
			package.loaded["lualine.themes.auto"] = nil
			local auto = require("lualine.themes.auto")
			local lualine_modes = { "insert", "normal", "visual", "command", "replace", "inactive", "terminal" }
			local sections = { "a", "b", "c", "x", "y", "z" }
			for _, field in ipairs(lualine_modes) do
				if auto[field] then
					for _, section in ipairs(sections) do
						if auto[field][section] then
							auto[field][section].bg = "NONE"
							auto[field][section].gui = "bold"
						end
					end
				end
			end

			-- Same mode -> color assignment as catppuccin's official lualine
			-- theme: normal=blue, insert=green, visual=mauve, command=peach,
			-- replace=red, terminal=green.
			local mode_color = {
				n = colors.darkblue,
				no = colors.darkblue,
				i = colors.green,
				v = colors.magenta,
				["\22"] = colors.magenta,
				V = colors.magenta,
				s = colors.magenta,
				S = colors.magenta,
				["\19"] = colors.magenta,
				c = colors.orange,
				cv = colors.orange,
				ce = colors.orange,
				ic = colors.yellow,
				R = colors.red,
				Rv = colors.red,
				r = colors.cyan,
				rm = colors.cyan,
				["r?"] = colors.cyan,
				["!"] = colors.orange,
				t = colors.green,
			}

			local mode = {
				"mode",
				separator = { left = "", right = "" },
				right_padding = 2,
				color = function()
					return { bg = mode_color[vim.fn.mode()], fg = colors.bg }
				end,
			}

			local filename = {
				"filename",
				color = { fg = colors.magenta, bg = "None", gui = "bold" },
				cond = conditions.alpha,
			}

			local alpha = {
				function()
					return "Alpha Dashboard"
				end,
				color = { fg = colors.magenta, bg = "None", gui = "bold" },
				cond = function()
					return vim.bo.filetype == "alpha"
				end,
			}

			local branch = {
				"branch",
				icon = "",
				color = { fg = colors.violet, bg = "None", gui = "bold" },
				on_click = function()
					Snacks.lazygit()
				end,
			}

			local diagnostics = {
				"diagnostics",
				sources = { "nvim_diagnostic" },
				symbols = { error = " ", warn = " ", info = " " },
				diagnostics_color = {
					color_error = { fg = colors.red, bg = "None", gui = "bold" },
					color_warn = { fg = colors.yellow, bg = "None", gui = "bold" },
					color_info = { fg = colors.cyan, bg = "None", gui = "bold" },
				},
				color = { bg = "None", gui = "bold" },
			}

			local macro_recording = {
				show_macro_recording,
				color = { fg = colors.bg, bg = colors.red },
				separator = { left = "", right = "" },
			}

			local copilot = {
				"copilot",
				symbols = {
					status = {
						hl = {
							enabled = colors.green,
							sleep = colors.yellow,
							disabled = colors.bg,
							warning = colors.orange,
							unknown = colors.red,
						},
					},
				},
				show_colors = true,
				color = { bg = "None", gui = "bold" },
				cond = conditions.alpha,
			}

			local diff = {
				"diff",
				symbols = { added = " ", modified = "󰝤 ", removed = " " },
				diff_color = {
					added = { fg = colors.green, bg = "None" },
					modified = { fg = colors.orange, bg = "None" },
					removed = { fg = colors.red, bg = "None" },
				},
				cond = conditions.hide_in_width,
			}

			local fileformat = {
				"fileformat",
				fmt = string.upper,
				color = { fg = colors.green, bg = "None", gui = "bold" },
				cond = conditions.alpha,
			}

			local lazy = {
				require("lazy.status").updates,
				cond = require("lazy.status").has_updates,
				color = { fg = colors.violet, bg = "None" },
				on_click = function()
					vim.ui.select({ "Yes", "No" }, { prompt = "Update plugins?" }, function(choice)
						if choice == "Yes" then
							vim.cmd("Lazy sync")
						else
							vim.notify("Update cancelled", vim.log.levels.INFO, { title = "Lazy" })
						end
					end)
				end,
			}

			local buffers = {
				get_buffers,
				color = { fg = colors.darkblue, bg = "None" },
			}

			local filetype = {
				"filetype",
				color = { fg = colors.darkblue, bg = "None" },
				cond = conditions.alpha,
			}

			local progress = {
				"progress",
				color = { fg = colors.magenta, bg = "None" },
			}

			local location = {
				"location",
				separator = { left = "", right = "" },
				left_padding = 2,
				color = function()
					return { bg = mode_color[vim.fn.mode()], fg = colors.bg }
				end,
			}

			local sep = { "%=", color = { fg = colors.bg, bg = "None" } }

			lualine.setup({
				options = {
					theme = auto,
					component_separators = "",
					section_separators = { left = "", right = "" },
					always_divide_middle = false,
				},
				sections = {
					lualine_a = { mode },
					lualine_b = { filename, alpha, branch },
					lualine_c = { diagnostics, sep, macro_recording },
					lualine_x = { copilot, diff, fileformat, lazy },
					lualine_y = { buffers, filetype, progress },
					lualine_z = { location },
				},
				inactive_sections = {
					lualine_a = { filename },
					lualine_b = {},
					lualine_c = {},
					lualine_x = {},
					lualine_y = {},
					lualine_z = { location },
				},
				tabline = {},
				extensions = {},
			})
		end

		setup_lualine()

		local function clear_statusline_bg()
			vim.api.nvim_set_hl(0, "StatusLine", { bg = "NONE" })
			vim.api.nvim_set_hl(0, "StatusLineNC", { bg = "NONE" })
		end
		clear_statusline_bg()

		-- Rebuild with the new flavour's palette whenever the colorscheme is
		-- re-applied (auto-dark-mode does this on every light/dark switch).
		vim.api.nvim_create_autocmd("ColorScheme", {
			callback = function()
				clear_statusline_bg()
				vim.schedule(setup_lualine)
			end,
		})

		vim.api.nvim_create_autocmd("RecordingEnter", {
			callback = function()
				lualine.refresh()
			end,
		})

		vim.api.nvim_create_autocmd("RecordingLeave", {
			callback = function()
				local timer = vim.loop.new_timer()
				timer:start(
					50,
					0,
					vim.schedule_wrap(function()
						lualine.refresh()
					end)
				)
			end,
		})
	end,
}
