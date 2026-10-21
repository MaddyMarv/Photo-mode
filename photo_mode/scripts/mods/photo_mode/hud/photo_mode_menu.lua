local mod = get_mod("photo_mode")

local UIRenderer = require("scripts/managers/ui/ui_renderer")
local UIFonts = require("scripts/managers/ui/ui_fonts")

local M = {}

M.WIDTH = 520
M.DEFAULT_HEIGHT = 540
M.HEIGHT = 540
M.TAB_HEIGHTS = {
	time_hud = 380,
	camera = 550,
	rigs = 560,
	lighting = 580,
}
M.LAYER = 950
M.FONT_TYPE = "proxima_nova_bold"

M.COLORS = {
	window_bg = { 235, 12, 16, 20 },
	window_border = { 255, 45, 95, 120 },
	window_border_inner = { 40, 255, 255, 255 },

	title_bg = { 245, 18, 24, 30 },
	title_border = { 255, 35, 70, 90 },
	title_text = { 255, 235, 242, 248 },
	title_hint = { 255, 110, 135, 150 },

	close_hover = { 255, 180, 45, 45 },
	close_text = { 255, 175, 190, 200 },
	close_text_hover = { 255, 255, 255, 255 },

	tab_bg = { 240, 20, 26, 32 },
	tab_border = { 255, 38, 52, 65 },
	tab_text = { 255, 145, 160, 175 },
	tab_hover_bg = { 255, 32, 42, 54 },
	tab_active_bg = { 255, 28, 58, 76 },
	tab_active_border = { 255, 60, 150, 195 },
	tab_active_text = { 255, 255, 255, 255 },
	tab_active_bar = { 255, 65, 185, 245 },

	section_header = { 255, 95, 180, 230 },
	section_line = { 255, 32, 45, 56 },

	btn_bg = { 240, 24, 30, 38 },
	btn_border = { 255, 45, 58, 72 },
	btn_text = { 255, 200, 215, 225 },
	btn_hover_bg = { 255, 38, 52, 68 },
	btn_hover_border = { 255, 75, 120, 155 },
	btn_pressed_bg = { 255, 16, 20, 26 },

	btn_active_bg = { 255, 22, 78, 62 },
	btn_active_border = { 255, 50, 170, 135 },
	btn_active_text = { 255, 195, 255, 230 },
	btn_active_hover = { 255, 30, 100, 80 },

	slider_label = { 255, 185, 198, 208 },
	slider_value = { 255, 90, 205, 255 },
	slider_track_bg = { 255, 18, 22, 28 },
	slider_track_border = { 255, 40, 50, 62 },
	slider_fill = { 255, 38, 110, 145 },
	slider_handle = { 255, 140, 215, 255 },
	slider_handle_border = { 255, 220, 245, 255 },
}

M.state = {
	x = nil,
	y = nil,
	current_tab = "camera",
	dragging = nil,
	drag_offset_x = 0,
	drag_offset_y = 0,
	pressed_id = nil,
	hover_id = nil,
	cursor_pushed = false,
}

local function _point_in_rect(px, py, rx, ry, rw, rh)
	return px >= rx and px <= rx + rw and py >= ry and py <= ry + rh
end

local function _clamp(val, min_v, max_v)
	return math.max(min_v, math.min(max_v, val))
end

function M.init(element)
	local saved_pos = mod:get("menu_position")

	if type(saved_pos) == "table" and type(saved_pos[1]) == "number" and type(saved_pos[2]) == "number" then
		M.state.x = saved_pos[1]
		M.state.y = saved_pos[2]
	end
end

function M.push_cursor()
	if not M.state.cursor_pushed then
		if Managers.input then
			Managers.input:push_cursor("photo_mode_menu")
			M.state.cursor_pushed = true
		end
	end
end

function M.pop_cursor()
	if M.state.cursor_pushed then
		M.state.cursor_pushed = false
		if Managers.input then
			Managers.input:pop_cursor("photo_mode_menu")
		end
	end
end

function M.save_position(x, y)
	mod:set("menu_position", { math.floor(x), math.floor(y) })
end

local function _add_rect(items, x, y, w, h, color, layer)
	items[#items + 1] = { "rect", x, y, w, h, color, layer or 0 }
end

local function _add_border(items, x, y, w, h, thickness, color, layer)
	_add_rect(items, x, y, w, thickness, color, layer)
	_add_rect(items, x, y + h - thickness, w, thickness, color, layer)
	_add_rect(items, x, y + thickness, thickness, h - 2 * thickness, color, layer)
	_add_rect(items, x + w - thickness, y + thickness, thickness, h - 2 * thickness, color, layer)
end

local function _add_panel(items, x, y, w, h, bg_color, border_color, border_thickness, layer)
	layer = layer or 0

	if bg_color and bg_color[1] > 0 then
		_add_rect(items, x, y, w, h, bg_color, layer)
	end

	if border_color and border_thickness and border_thickness > 0 then
		_add_border(items, x, y, w, h, border_thickness, border_color, layer + 1)
	end
end

local function _add_text(items, str, x, y, w, h, font_size, color, align, layer)
	items[#items + 1] = { "text", str, x, y, w, h, font_size, color, align or "center", layer or 2 }
end

local function _button(ctx, id, label, x, y, w, h, is_active, on_click, custom_colors)
	local is_hover = ctx.cx and _point_in_rect(ctx.cx, ctx.cy, x, y, w, h)
	local is_pressed = is_hover and (ctx.left_hold or ctx.left_pressed) and
	(ctx.pressed_id == id or ctx.pressed_id == nil)
	local colors = M.COLORS

	local bg_col, border_col, text_col

	if is_pressed and is_hover and ctx.left_hold then
		bg_col = colors.btn_pressed_bg
		border_col = colors.btn_hover_border
		text_col = colors.btn_text
	elseif is_active then
		bg_col = is_hover and colors.btn_active_hover or colors.btn_active_bg
		border_col = colors.btn_active_border
		text_col = colors.btn_active_text
	elseif is_hover then
		bg_col = custom_colors and custom_colors.hover_bg or colors.btn_hover_bg
		border_col = custom_colors and custom_colors.hover_border or colors.btn_hover_border
		text_col = colors.title_text
	else
		bg_col = custom_colors and custom_colors.bg or colors.btn_bg
		border_col = custom_colors and custom_colors.border or colors.btn_border
		text_col = custom_colors and custom_colors.text or colors.btn_text
	end

	_add_panel(ctx.items, x, y, w, h, bg_col, border_col, 1, 2)
	_add_text(ctx.items, label, x, y, w, h, 14, text_col, "center", 3)

	if is_hover and ctx.left_pressed and not ctx.dragging then
		ctx.next_pressed = id
		if on_click then
			on_click()
		end
	end
end

local function _color_swatch_button(ctx, id, color, x, y, w, h, is_selected, on_click)
	local is_hover = ctx.cx and _point_in_rect(ctx.cx, ctx.cy, x, y, w, h)
	local border_col = is_selected and { 255, 255, 255, 255 } or
	(is_hover and { 255, 210, 235, 255 } or { 255, 55, 70, 85 })
	local border_w = is_selected and 2 or 1

	_add_panel(ctx.items, x, y, w, h, color, border_col, border_w, 2)

	if is_hover and ctx.left_pressed and not ctx.dragging then
		ctx.next_pressed = id
		if on_click then
			on_click()
		end
	end
end

local function _slider(ctx, id, label, val_text, x, y, w, h, min_v, max_v, cur_val, step, decimals, on_change,
					   custom_fill)
	local track_y = y + 17
	local track_h = 10
	local is_hover = ctx.cx and _point_in_rect(ctx.cx, ctx.cy, x, y, w, h)
	local colors = M.COLORS

	_add_text(ctx.items, label, x, y, w - 80, 15, 13, colors.slider_label, "left", 2)
	_add_text(ctx.items, val_text, x + w - 80, y, 80, 15, 13, colors.slider_value, "right", 2)

	_add_panel(ctx.items, x, track_y, w, track_h, colors.slider_track_bg, colors.slider_track_border, 1, 2)

	local frac = _clamp((cur_val - min_v) / (max_v - min_v), 0, 1)
	local fill_w = math.floor(w * frac)

	if fill_w > 0 then
		local fill_col = custom_fill or colors.slider_fill
		_add_rect(ctx.items, x + 1, track_y + 1, fill_w - 2, track_h - 2, fill_col, 3)
	end

	local handle_x = math.floor(x + frac * (w - 10))
	local handle_y = track_y - 3
	_add_panel(ctx.items, handle_x, handle_y, 10, 16, colors.slider_handle, colors.slider_handle_border, 1, 4)

	local hit_slider = ctx.cx and _point_in_rect(ctx.cx, ctx.cy, x, y, w, h)

	if hit_slider and ctx.left_pressed then
		ctx.next_dragging = id
	end

	if ctx.dragging == id and ctx.cx then
		local new_frac = _clamp((ctx.cx - x) / w, 0, 1)
		local new_val = min_v + new_frac * (max_v - min_v)

		if step and step > 0 then
			new_val = math.floor((new_val - min_v) / step + 0.5) * step + min_v
		end

		if decimals and decimals >= 0 then
			new_val = tonumber(string.format("%." .. decimals .. "f", new_val))
		end

		new_val = _clamp(new_val, min_v, max_v)

		if new_val ~= cur_val and on_change then
			on_change(new_val)
		end
	end
end

local function _section_header(items, title, x, y, w)
	_add_text(items, title, x, y, w, 16, 12, M.COLORS.section_header, "left", 2)
	_add_rect(items, x, y + 17, w, 1, M.COLORS.section_line, 2)
end

local function _build_camera_tab(ctx, cx_start, cy_start, w)
	local y = cy_start
	local slider_w = w - 86
	local btn_w = 76

	_section_header(ctx.items, "FIELD OF VIEW", cx_start, y, w)
	y = y + 24

	local fov_offset = mod._fov_offset or mod:get("camera_fov_offset") or 0
	_slider(ctx, "camera_fov_offset", "Camera FOV Offset", string.format("%+d°", fov_offset), cx_start, y, slider_w, 30,
		-60, 60, fov_offset, 1, 0, function(v)
		mod:set("camera_fov_offset", v, true)
		mod._fov_offset = v
	end)
	_button(ctx, "reset_fov", "Reset", cx_start + slider_w + 10, y + 14, btn_w, 20, false, function()
		mod.reset_fov()
	end)
	y = y + 38

	_section_header(ctx.items, "CAMERA TILT", cx_start, y, w)
	y = y + 24

	local tilt = mod._tilt_angle or mod:get("camera_tilt") or 0
	_slider(ctx, "camera_tilt", "Dutch Angle / Tilt", string.format("%+d°", tilt), cx_start, y, slider_w, 30, -45, 45,
		tilt, 1, 0, function(v)
		mod:set("camera_tilt", v, true)
		mod._tilt_angle = v
	end)
	_button(ctx, "reset_tilt", "Reset", cx_start + slider_w + 10, y + 14, btn_w, 20, false, function()
		mod.reset_tilt()
	end)
	y = y + 38

	_section_header(ctx.items, "DEPTH OF FIELD", cx_start, y, w)
	y = y + 24

	local dof_active = mod._dof_active
	_button(ctx, "toggle_dof", dof_active and "DEPTH OF FIELD: ACTIVE" or "DEPTH OF FIELD: OFF", cx_start, y, w, 28,
		dof_active, function()
		mod.toggle_dof()
	end)
	y = y + 36

	local dof_dist = mod._dof_distance or mod:get("dof_focal_distance") or 3.0
	_slider(ctx, "dof_focal_distance", "Focal Distance", string.format("%.1f m", dof_dist), cx_start, y, w, 30, 0.5, 50.0,
		dof_dist, 0.5, 1, function(v)
		mod:set("dof_focal_distance", v, true)
		mod._dof_distance = v
	end)
	y = y + 34

	local dof_region = mod:get("dof_focal_region") or 4.0
	_slider(ctx, "dof_focal_region", "Focal Region Depth", string.format("%.1f m", dof_region), cx_start, y, w, 30, 0.5,
		20.0, dof_region, 0.5, 1, function(v)
		mod:set("dof_focal_region", v, true)
	end)
	y = y + 34

	local dof_blur = mod:get("dof_blur_amount") or 1.0
	_slider(ctx, "dof_blur_amount", "Background Blur Amount", string.format("%.1f", dof_blur), cx_start, y, w, 30, 0.1,
		1.0, dof_blur, 0.1, 1, function(v)
		mod:set("dof_blur_amount", v, true)
	end)
	y = y + 38

	_section_header(ctx.items, "MOUSE LOOK SMOOTHING", cx_start, y, w)
	y = y + 24

	local mouse_smoothing = mod._mouse_smoothing
	_button(ctx, "toggle_mouse_smoothing", mouse_smoothing and "SMOOTHING: ON" or "SMOOTHING: OFF", cx_start, y, w, 28,
		mouse_smoothing, function()
			mod.toggle_mouse_smoothing()
		end)
	y = y + 36

	local half_w = math.floor((w - 10) / 2)
	local smoothing_amt = mod._mouse_smoothing_amount or mod:get("mouse_smoothing_amount") or 0.65
	_slider(ctx, "mouse_smoothing_amount", "Smoothing Strength", string.format("%d%%", math.floor(smoothing_amt * 100 + 0.5)),
		cx_start, y, half_w, 32, 0.10, 0.95, smoothing_amt, 0.05, 2, function(v)
			mod:set("mouse_smoothing_amount", v, true)
			mod._mouse_smoothing_amount = v
		end)

	local smoothing_spd = mod._mouse_smoothing_speed or mod:get("mouse_smoothing_speed") or 1.0
	_slider(ctx, "mouse_smoothing_speed", "Look Speed", string.format("%d%%", math.floor(smoothing_spd * 100 + 0.5)),
		cx_start + half_w + 10, y, half_w, 32, 0.10, 3.00, smoothing_spd, 0.05, 2, function(v)
			mod:set("mouse_smoothing_speed", v, true)
			mod._mouse_smoothing_speed = v
		end)
end

local function _build_time_hud_tab(ctx, cx_start, cy_start, w)
	local y = cy_start
	local half_w = math.floor((w - 10) / 2)

	_section_header(ctx.items, "TIME CONTROL", cx_start, y, w)
	y = y + 24

	local time_frozen = mod._time_frozen
	_button(ctx, "freeze_time", time_frozen and "TIME: FROZEN" or "FREEZE TIME", cx_start, y, half_w, 32, time_frozen,
		function()
			mod.toggle_freeze_time()
		end)
	_button(ctx, "step_frame", "Step 1 Frame  >", cx_start + half_w + 10, y, half_w, 32, false, function()
		mod.step_frame()
	end)
	y = y + 40

	local slomo_active = mod._slomo_active
	_button(ctx, "toggle_slomo", slomo_active and "SLOW-MO: ON" or "SLOW-MO: OFF", cx_start, y, half_w, 32, slomo_active,
		function()
			mod.toggle_slomo()
		end)

	local slomo_scale = mod:get("slomo_scale") or 0.10
	_slider(ctx, "slomo_scale", "Slow-Mo Speed", string.format("%d%%", math.floor(slomo_scale * 100 + 0.5)),
		cx_start + half_w + 10, y, half_w, 32, 0.01, 1.00, slomo_scale, 0.01, 2, function(v)
		mod:set("slomo_scale", v, true)
	end)
	y = y + 46

	_section_header(ctx.items, "HUD & SCREEN VISIBILITY", cx_start, y, w)
	y = y + 24

	local hud_hidden = mod._hud_hidden
	_button(ctx, "toggle_hide_hud", hud_hidden and "HUD: HIDDEN" or "HIDE HUD", cx_start, y, half_w, 32, hud_hidden,
		function()
			mod.toggle_hide_hud()
		end)

	local chat_hidden = mod._chat_hidden
	_button(ctx, "toggle_hide_chat", chat_hidden and "CHAT: HIDDEN" or "HIDE CHAT", cx_start + half_w + 10, y, half_w, 32,
		chat_hidden, function()
		mod.toggle_hide_chat()
	end)
	y = y + 40

	local arms_hidden = mod._arms_hidden
	_button(ctx, "toggle_hide_arms", arms_hidden and "ARMS: HIDDEN" or "HIDE ARMS", cx_start, y, half_w, 32, arms_hidden,
		function()
			mod.toggle_hide_arms()
		end)

	local fx_hidden = mod._screen_effects_hidden
	_button(ctx, "toggle_hide_effects", fx_hidden and "FX: HIDDEN" or "SCREEN EFFECTS", cx_start + half_w + 10, y, half_w,
		32, fx_hidden, function()
		mod.toggle_hide_screen_effects()
	end)
end

local function _build_lighting_tab(ctx, cx_start, cy_start, w)
	local y = cy_start
	local third_w = math.floor((w - 20) / 3)
	local colors = M.COLORS

	_section_header(ctx.items, "STUDIO LIGHTS", cx_start, y, w)
	y = y + 24

	local num_lights = #mod._placed_lights
	local sel_idx = mod._selected_light_index or num_lights
	if num_lights > 0 and (sel_idx < 1 or sel_idx > num_lights) then
		sel_idx = num_lights
		mod._selected_light_index = sel_idx
	end

	_button(ctx, "place_light", string.format("+ Light (%d)", num_lights), cx_start, y, third_w, 32, false, function()
		mod.place_light()
	end)
	_button(ctx, "undo_light", "Undo Light", cx_start + third_w + 10, y, third_w, 32, false, function()
		mod.undo_light()
	end)
	_button(ctx, "clear_lights", "Clear All", cx_start + (third_w + 10) * 2, y, third_w, 32, false, function()
		mod.clear_lights()
	end)
	y = y + 38
	local arrow_w = 34
	local del_btn_w = 64
	local gap = 8
	local selector_mid_w = w - (arrow_w * 2 + del_btn_w + gap * 3)
	_button(ctx, "prev_light", "<", cx_start, y, arrow_w, 28, false, function()
		if mod.select_prev_light then
			mod.select_prev_light()
		end
	end)

	local sel_label = num_lights > 0 and string.format("Editing: #%d of %d", sel_idx, num_lights) or
	"No Placed Lights (Editing Next / Lantern)"
	_button(ctx, "selected_light_display", sel_label, cx_start + arrow_w + gap, y, selector_mid_w, 28, num_lights > 0,
		function()
			if num_lights > 0 and mod.select_next_light then
				mod.select_next_light()
			end
		end)

	_button(ctx, "next_light", ">", cx_start + arrow_w + gap + selector_mid_w + gap, y, arrow_w, 28, false, function()
		if mod.select_next_light then
			mod.select_next_light()
		end
	end)

	_button(ctx, "delete_selected_light", "Delete", cx_start + arrow_w + gap + selector_mid_w + gap + arrow_w + gap, y,
		del_btn_w, 28, false, function()
		if mod.delete_selected_light then
			mod.delete_selected_light()
		end
	end)
	y = y + 34

	local lantern_active = mod._lantern_active
	_button(ctx, "toggle_lantern", lantern_active and "Lantern: ON" or "Lantern: OFF", cx_start, y, third_w, 32,
		lantern_active, function()
		mod.toggle_lantern()
	end)

	local light_type = mod:get("light_type") or "spot"
	_button(ctx, "cycle_light_type", light_type == "omni" and "Type: OMNI" or "Type: SPOT", cx_start + third_w + 10, y,
		third_w, 32, false, function()
		local next_type = light_type == "spot" and "omni" or "spot"
		mod:set("light_type", next_type, true)
		if mod.update_all_lights then
			mod.update_all_lights()
		end
	end)

	local cast_shadows = mod:get("cast_shadows") ~= false
	_button(ctx, "toggle_shadows", cast_shadows and "Shadows: ON" or "Shadows: OFF", cx_start + (third_w + 10) * 2, y,
		third_w, 32, cast_shadows, function()
		mod:set("cast_shadows", not cast_shadows, true)
		if mod.update_all_lights then
			mod.update_all_lights()
		end
	end)
	y = y + 44

	local header_title = num_lights > 0 and string.format("LIGHT PROPERTIES (LIGHT #%d)", sel_idx) or
	"LIGHT PROPERTIES (NEXT LIGHT / LANTERN)"
	_section_header(ctx.items, header_title, cx_start, y, w)
	y = y + 24

	local intensity = mod:get("light_intensity") or 100
	_slider(ctx, "light_intensity", "Light Intensity", tostring(math.floor(intensity + 0.5)), cx_start, y, w, 28, 10, 300,
		intensity, 5, 0, function(v)
		mod:set("light_intensity", v, true)
		if mod.update_all_lights then
			mod.update_all_lights()
		end
	end)
	y = y + 32

	local radius = mod:get("light_radius") or 20
	_slider(ctx, "light_radius", "Light Radius / Falloff", string.format("%d m", math.floor(radius + 0.5)), cx_start, y,
		w, 28, 5, 100, radius, 1, 0, function(v)
		mod:set("light_radius", v, true)
		if mod.update_all_lights then
			mod.update_all_lights()
		end
	end)
	y = y + 32

	local spot_angle = mod:get("spot_angle") or 45
	_slider(ctx, "spot_angle", "Spotlight Cone Angle", string.format("%d°", math.floor(spot_angle + 0.5)), cx_start, y, w,
		28, 15, 90, spot_angle, 5, 0, function(v)
		mod:set("spot_angle", v, true)
		if mod.update_all_lights then
			mod.update_all_lights()
		end
	end)
	y = y + 36

	local cur_color = mod:get("light_color") or { 255, 255, 245, 220 }
	local cur_r = cur_color[2] or 255
	local cur_g = cur_color[3] or 245
	local cur_b = cur_color[4] or 220

	local swatch_w = 40
	local swatch_h = 24
	_add_panel(ctx.items, cx_start, y, swatch_w, swatch_h, { 255, cur_r, cur_g, cur_b }, { 255, 220, 235, 245 }, 1, 3)

	_add_text(ctx.items, "Light Color", cx_start + swatch_w + 10, y + 4, 90, 16, 13, colors.title_text, "left", 2)
	_add_text(ctx.items, string.format("RGB: %d, %d, %d", cur_r, cur_g, cur_b), cx_start + swatch_w + 105, y + 4, 160, 16,
		12, colors.title_hint, "left", 2)

	local reset_btn_w = 64
	_button(ctx, "reset_light_color", "Reset", cx_start + w - reset_btn_w, y + 2, reset_btn_w, 20, false, function()
		mod:set("light_color", { 255, 255, 245, 220 }, true)
		if mod.update_all_lights then
			mod.update_all_lights()
		end
	end)
	y = y + 30

	local presets = {
		{ name = "Warm",   color = { 255, 255, 195, 120 } },
		{ name = "White",  color = { 255, 255, 250, 240 } },
		{ name = "Day",    color = { 255, 210, 230, 255 } },
		{ name = "Cold",   color = { 255, 130, 180, 255 } },
		{ name = "Amber",  color = { 255, 255, 140, 25 } },
		{ name = "Red",    color = { 255, 255, 45, 35 } },
		{ name = "Green",  color = { 255, 45, 255, 75 } },
		{ name = "Cyan",   color = { 255, 40, 230, 255 } },
		{ name = "Violet", color = { 255, 210, 60, 255 } },
	}

	local p_count = #presets
	local p_gap = 6
	local p_w = math.floor((w - (p_count - 1) * p_gap) / p_count)
	local p_h = 20

	for i = 1, p_count do
		local p = presets[i]
		local px = cx_start + (i - 1) * (p_w + p_gap)
		local is_sel = math.abs(cur_r - p.color[2]) <= 3 and math.abs(cur_g - p.color[3]) <= 3 and
		math.abs(cur_b - p.color[4]) <= 3

		_color_swatch_button(ctx, "preset_col_" .. i, p.color, px, y, p_w, p_h, is_sel, function()
			mod:set("light_color", { 255, p.color[2], p.color[3], p.color[4] }, true)
			if mod.update_all_lights then
				mod.update_all_lights()
			end
		end)
	end
	y = y + 28

	_slider(ctx, "light_color_r", "Red Channel", tostring(cur_r), cx_start, y, w, 26, 0, 255, cur_r, 1, 0, function(v)
		mod:set("light_color", { 255, v, cur_g, cur_b }, true)
		if mod.update_all_lights then
			mod.update_all_lights()
		end
	end, { 255, 205, 55, 55 })
	y = y + 28

	_slider(ctx, "light_color_g", "Green Channel", tostring(cur_g), cx_start, y, w, 26, 0, 255, cur_g, 1, 0, function(v)
		mod:set("light_color", { 255, cur_r, v, cur_b }, true)
		if mod.update_all_lights then
			mod.update_all_lights()
		end
	end, { 255, 45, 185, 75 })
	y = y + 28

	_slider(ctx, "light_color_b", "Blue Channel", tostring(cur_b), cx_start, y, w, 26, 0, 255, cur_b, 1, 0, function(v)
		mod:set("light_color", { 255, cur_r, cur_g, v }, true)
		if mod.update_all_lights then
			mod.update_all_lights()
		end
	end, { 255, 50, 125, 230 })
end

local function _build_rigs_tab(ctx, cx_start, cy_start, w)
	local y = cy_start
	local half_w = math.floor((w - 10) / 2)
	local third_w = math.floor((w - 20) / 3)

	_section_header(ctx.items, "TRIPOD & DOLLY RIGS", cx_start, y, w)
	y = y + 24

	local tripod_active = mod._tripod_active
	_button(ctx, "toggle_tripod", tripod_active and "TRIPOD: LOCKED" or "TRIPOD: OFF", cx_start, y, half_w, 30,
		tripod_active, function()
		mod.toggle_tripod()
	end)

	local dolly_active = mod._dolly_active
	_button(ctx, "toggle_dolly", dolly_active and "DOLLY: ACTIVE" or "DOLLY: OFF", cx_start + half_w + 10, y, half_w, 30,
		dolly_active, function()
		mod.toggle_dolly()
	end)
	y = y + 36

	local num_dolly = #mod._dolly_points
	_button(ctx, "dolly_add", string.format("+ Point (%d)", num_dolly), cx_start, y, third_w, 28, false, function()
		mod.dolly_add_point()
	end)
	_button(ctx, "dolly_undo", "Undo Point", cx_start + third_w + 10, y, third_w, 28, false, function()
		if mod.dolly_undo_point then
			mod.dolly_undo_point()
		end
	end)
	_button(ctx, "dolly_clear", "Clear All", cx_start + (third_w + 10) * 2, y, third_w, 28, false, function()
		mod.dolly_clear_points()
	end)
	y = y + 34

	local arrow_w = 34
	local del_btn_w = 64
	local gap = 8
	local selector_mid_w = w - (arrow_w * 2 + del_btn_w + gap * 3)

	local sel_dolly_idx = mod._selected_dolly_index or num_dolly
	if num_dolly > 0 and (sel_dolly_idx < 1 or sel_dolly_idx > num_dolly) then
		sel_dolly_idx = num_dolly
		mod._selected_dolly_index = sel_dolly_idx
	end

	_button(ctx, "prev_dolly_point", "<", cx_start, y, arrow_w, 28, false, function()
		if mod.select_prev_dolly_point then
			mod.select_prev_dolly_point()
		end
	end)

	local cur_pt = (num_dolly > 0 and mod._dolly_points[sel_dolly_idx]) or nil
	local pt_name = cur_pt and cur_pt.name or (sel_dolly_idx > 0 and tostring(sel_dolly_idx) or "-")
	local sel_dolly_label = num_dolly > 0 and string.format("Point %s (%d of %d)", pt_name, sel_dolly_idx, num_dolly) or "No Waypoints Stored"
	_button(ctx, "selected_dolly_display", sel_dolly_label, cx_start + arrow_w + gap, y, selector_mid_w, 28, num_dolly > 0, function()
		if num_dolly > 0 and mod.select_next_dolly_point then
			mod.select_next_dolly_point()
		end
	end)

	_button(ctx, "next_dolly_point", ">", cx_start + arrow_w + gap + selector_mid_w + gap, y, arrow_w, 28, false, function()
		if mod.select_next_dolly_point then
			mod.select_next_dolly_point()
		end
	end)

	_button(ctx, "delete_selected_dolly_point", "Delete", cx_start + arrow_w + gap + selector_mid_w + gap + arrow_w + gap, y, del_btn_w, 28, false, function()
		if mod.delete_selected_dolly_point then
			mod.delete_selected_dolly_point()
		end
	end)
	y = y + 34

	_button(ctx, "dolly_goto_point", "Go to Point", cx_start, y, half_w, 28, false, function()
		if mod.dolly_goto_point then
			mod.dolly_goto_point()
		end
	end)

	_button(ctx, "dolly_update_point", "Update Point", cx_start + half_w + 10, y, half_w, 28, false, function()
		if mod.dolly_update_point then
			mod.dolly_update_point()
		end
	end)
	y = y + 34

	local motion = mod:get("dolly_motion") or "smooth"
	local motion_labels = {
		smooth = "Motion: SMOOTH",
		linear = "Motion: LINEAR",
		loop = "Motion: LOOP",
		instant = "Motion: INSTANT",
		instant_loop = "Motion: INST-LOOP",
	}
	local motion_label = motion_labels[motion] or ("Motion: " .. string.upper(motion))
	_button(ctx, "dolly_motion", motion_label, cx_start, y, half_w, 28, false, function()
		local next_m = (motion == "smooth" and "linear")
			or (motion == "linear" and "loop")
			or (motion == "loop" and "instant")
			or (motion == "instant" and "instant_loop")
			or "smooth"
		mod:set("dolly_motion", next_m, true)
	end)

	if motion == "instant" or motion == "instant_loop" then
		local time_inbetween = mod:get("dolly_time_inbetween") or 2.0
		_slider(ctx, "dolly_time_inbetween", "Time Between", string.format("%.1f s", time_inbetween),
			cx_start + half_w + 10, y, half_w, 28, 0.1, 10.0, time_inbetween, 0.1, 1, function(v)
			mod:set("dolly_time_inbetween", v, true)
		end)
	else
		local duration = mod:get("dolly_duration") or 8.0
		_slider(ctx, "dolly_duration", "Duration", string.format("%.1f s", duration), cx_start + half_w + 10, y, half_w, 28,
			2.0, 60.0, duration, 0.5, 1, function(v)
			mod:set("dolly_duration", v, true)
		end)
	end
	y = y + 38

	_section_header(ctx.items, "ORBIT CAMERA RIG", cx_start, y, w)
	y = y + 24

	local orbit_active = mod._orbit_active
	local orbit_paused = mod._orbit_paused
	_button(ctx, "toggle_orbit", orbit_active and "ORBIT: ACTIVE" or "ORBIT: OFF", cx_start, y, third_w, 30, orbit_active,
		function()
			mod.toggle_orbit()
		end)
	_button(ctx, "orbit_pause", orbit_paused and "PAUSED" or "PAUSE", cx_start + third_w + 10, y, third_w, 30, orbit_paused,
		function()
			mod.toggle_orbit_pause()
		end)
	_button(ctx, "orbit_center", "Set Center (Cam)", cx_start + (third_w + 10) * 2, y, third_w, 30, false, function()
		mod.orbit_set_center()
	end)
	y = y + 36

	local target_mode = mod:get("orbit_target_mode") or "character"
	_button(ctx, "orbit_target", target_mode == "custom" and "Target: CUSTOM" or "Target: CHAR", cx_start, y, third_w, 28,
		false, function()
		local next_t = target_mode == "character" and "custom" or "character"
		mod:set("orbit_target_mode", next_t, true)
	end)

	local facing = mod:get("orbit_facing") or "inward"
	_button(ctx, "orbit_facing", facing == "outward" and "Facing: OUT" or "Facing: IN", cx_start + third_w + 10, y,
		third_w, 28, false, function()
		local next_f = facing == "inward" and "outward" or "inward"
		mod:set("orbit_facing", next_f, true)
	end)

	local dir = mod:get("orbit_direction") or "cw"
	_button(ctx, "orbit_dir", dir == "ccw" and "Dir: CCW" or "Dir: CW", cx_start + (third_w + 10) * 2, y, third_w, 28,
		false, function()
		local next_d = dir == "cw" and "ccw" or "cw"
		mod:set("orbit_direction", next_d, true)
	end)
	y = y + 34

	local orbit_speed = mod:get("orbit_speed") or 15
	_slider(ctx, "orbit_speed", "Orbit Speed", string.format("%d°/s", math.floor(orbit_speed + 0.5)), cx_start, y, w, 28,
		1, 60, orbit_speed, 1, 0, function(v)
		mod:set("orbit_speed", v, true)
	end)
	y = y + 32

	local orbit_radius = mod:get("orbit_radius") or 4.0
	_slider(ctx, "orbit_radius", "Orbit Radius", string.format("%.1f m", orbit_radius), cx_start, y, w, 28, 1.0, 30.0,
		orbit_radius, 0.5, 1, function(v)
		mod:set("orbit_radius", v, true)
	end)
	y = y + 32

	local orbit_height = mod:get("orbit_height") or 0.3
	_slider(ctx, "orbit_height", "Orbit Height Offset", string.format("%+.1f m", orbit_height), cx_start, y, w, 28, -5.0,
		5.0, orbit_height, 0.1, 1, function(v)
		mod:set("orbit_height", v, true)
	end)
end

function M.update(element, dt, t, ui_renderer, render_settings, input_service)
	if not mod:is_enabled() or not mod._menu_open then
		M.pop_cursor()
		mod._menu_hovered = false
		element._menu_items = nil
		M.state.dragging = nil
		M.state.pressed_id = nil
		return
	end

	M.push_cursor()

	local back_pressed = input_service and input_service:get("back")
	if back_pressed then
		mod.close_photo_menu()
		mod._menu_hovered = false
		M.pop_cursor()
		element._menu_items = nil
		return
	end

	local inverse_scale = render_settings and render_settings.inverse_scale or 1
	local screen_w = RESOLUTION_LOOKUP.width * inverse_scale
	local screen_h = RESOLUTION_LOOKUP.height * inverse_scale

	local cursor = input_service and input_service:get("cursor")
	local cx, cy

	if cursor then
		cx = cursor.x * inverse_scale
		cy = cursor.y * inverse_scale
	end

	local left_pressed = input_service and input_service:get("left_pressed")
	local left_hold = input_service and input_service:get("left_hold")
	local left_released = input_service and input_service:get("left_released")

	local ww = M.WIDTH
	local title_h = 36
	local tab_h = 28
	local pad_x = 16
	local content_w = ww - pad_x * 2
	local num_tabs = 4
	local tab_gap = 6
	local tab_w = math.floor((content_w - (num_tabs - 1) * tab_gap) / num_tabs)

	local tabs = {
		{ id = "camera",   label = "CAMERA" },
		{ id = "time_hud", label = "TIME & HUD" },
		{ id = "lighting", label = "LIGHTING" },
		{ id = "rigs",     label = "RIGS" },
	}

	local test_wx = M.state.x or math.floor((screen_w - ww) / 2)
	local test_wy = M.state.y or 80
	local test_tab_y = test_wy + title_h + 8

	if left_pressed and cx and not M.state.dragging then
		for i = 1, num_tabs do
			local tx = test_wx + pad_x + (i - 1) * (tab_w + tab_gap)
			if _point_in_rect(cx, cy, tx, test_tab_y, tab_w, tab_h) then
				M.state.current_tab = tabs[i].id
				break
			end
		end
	end

	local wh = M.TAB_HEIGHTS[M.state.current_tab] or M.DEFAULT_HEIGHT

	if not M.state.x or not M.state.y then
		M.state.x = math.floor((screen_w - ww) / 2)
		M.state.y = 80
	end

	M.state.x = _clamp(M.state.x, 10, screen_w - ww - 10)
	M.state.y = _clamp(M.state.y, 10, screen_h - wh - 10)

	local wx = M.state.x
	local wy = M.state.y
	local tab_y = wy + title_h + 8

	local close_w = 24
	local close_h = 24
	local close_x = wx + ww - close_w - 6
	local close_y = wy + 6

	local lock_w = 88
	local lock_h = 24
	local lock_x = close_x - lock_w - 6
	local lock_y = wy + 6

	local act_w = 118
	local act_h = 24
	local act_x = lock_x - act_w - 6
	local act_y = wy + 6

	local is_hover_close = cx and _point_in_rect(cx, cy, close_x, close_y, close_w, close_h)
	local is_hover_lock = cx and _point_in_rect(cx, cy, lock_x, lock_y, lock_w, lock_h)
	local is_hover_actions = cx and _point_in_rect(cx, cy, act_x, act_y, act_w, act_h)
	local is_hover_title = cx and _point_in_rect(cx, cy, wx, wy, ww, title_h) and not is_hover_close and
	not is_hover_lock and not is_hover_actions
	local is_hover_window = cx and _point_in_rect(cx, cy, wx, wy, ww, wh)

	mod._menu_hovered = (is_hover_window and true or false) or (M.state.dragging ~= nil) or (M.state.pressed_id ~= nil)

	if left_pressed and cx then
		if is_hover_close then
			mod.close_photo_menu()
			M.pop_cursor()
			mod._menu_hovered = false
			element._menu_items = nil
			return
		elseif is_hover_lock then
			mod._camera_locked = not (mod._camera_locked ~= false)
			mod:set("lock_camera_in_menu", mod._camera_locked, true)
		elseif is_hover_actions then
			mod.toggle_in_game_actions()
		elseif is_hover_title then
			M.state.dragging = "window"
			M.state.drag_offset_x = cx - wx
			M.state.drag_offset_y = cy - wy
		end
	end

	if M.state.dragging == "window" and cx then
		M.state.x = _clamp(cx - M.state.drag_offset_x, 10, screen_w - ww - 10)
		M.state.y = _clamp(cy - M.state.drag_offset_y, 10, screen_h - wh - 10)
		wx = M.state.x
		wy = M.state.y
		tab_y = wy + title_h + 8
	end

	if left_released or not left_hold then
		if M.state.dragging == "window" then
			M.save_position(M.state.x, M.state.y)
		end
		M.state.dragging = nil
		M.state.pressed_id = nil
	end

	local items = {}
	local colors = M.COLORS

	_add_panel(items, wx, wy, ww, wh, colors.window_bg, colors.window_border, 1, 0)
	_add_border(items, wx + 1, wy + 1, ww - 2, wh - 2, 1, colors.window_border_inner, 1)

	_add_panel(items, wx, wy, ww, title_h, colors.title_bg, colors.title_border, 1, 2)
	_add_text(items, "PHOTO MODE", wx + 16, wy, 110, title_h, 15, colors.title_text, "left", 3)
	_add_text(items, "drag to move", wx + 130, wy + 2, 110, title_h, 12, colors.title_hint, "left", 3)

	local is_actions_allowed = mod._actions_allowed ~= false
	local act_label = is_actions_allowed and "ACTIONS: ALLOWED" or "ACTIONS: BLOCKED"
	local act_bg = is_actions_allowed and (is_hover_actions and colors.btn_active_hover or colors.btn_active_bg) or
	(is_hover_actions and colors.btn_hover_bg or colors.btn_bg)
	local act_border = is_actions_allowed and colors.btn_active_border or
	(is_hover_actions and colors.btn_hover_border or colors.btn_border)
	local act_text = is_actions_allowed and colors.btn_active_text or colors.btn_text

	_add_panel(items, act_x, act_y, act_w, act_h, act_bg, act_border, 1, 3)
	_add_text(items, act_label, act_x, act_y, act_w, act_h, 11, act_text, "center", 4)

	local is_locked = mod._camera_locked ~= false
	local lock_label = is_locked and "CAM: LOCKED" or "CAM: FREE"
	local lock_bg = is_locked and (is_hover_lock and colors.btn_active_hover or colors.btn_active_bg) or
	(is_hover_lock and colors.btn_hover_bg or colors.btn_bg)
	local lock_border = is_locked and colors.btn_active_border or
	(is_hover_lock and colors.btn_hover_border or colors.btn_border)
	local lock_text = is_locked and colors.btn_active_text or colors.btn_text

	_add_panel(items, lock_x, lock_y, lock_w, lock_h, lock_bg, lock_border, 1, 3)
	_add_text(items, lock_label, lock_x, lock_y, lock_w, lock_h, 11, lock_text, "center", 4)

	local close_bg = is_hover_close and colors.close_hover or colors.close_bg
	local close_tx = is_hover_close and colors.close_text_hover or colors.close_text
	_add_panel(items, close_x, close_y, close_w, close_h, close_bg, nil, 0, 3)
	_add_text(items, "X", close_x, close_y, close_w, close_h, 14, close_tx, "center", 4)

	for i = 1, num_tabs do
		local tinfo = tabs[i]
		local tx = wx + pad_x + (i - 1) * (tab_w + tab_gap)
		local is_cur = M.state.current_tab == tinfo.id
		local is_htab = cx and _point_in_rect(cx, cy, tx, tab_y, tab_w, tab_h)

		local t_bg = is_cur and colors.tab_active_bg or (is_htab and colors.tab_hover_bg or colors.tab_bg)
		local t_border = is_cur and colors.tab_active_border or colors.tab_border
		local t_text = is_cur and colors.tab_active_text or colors.tab_text

		_add_panel(items, tx, tab_y, tab_w, tab_h, t_bg, t_border, 1, 2)
		_add_text(items, tinfo.label, tx, tab_y, tab_w, tab_h, 13, t_text, "center", 3)

		if is_cur then
			_add_rect(items, tx + 1, tab_y + tab_h - 2, tab_w - 2, 2, colors.tab_active_bar, 4)
		end
	end

	local ctx = {
		items = items,
		cx = cx,
		cy = cy,
		left_pressed = left_pressed,
		left_hold = left_hold,
		left_released = left_released,
		pressed_id = M.state.pressed_id,
		dragging = M.state.dragging,
		next_pressed = nil,
		next_dragging = nil,
	}

	local content_y = tab_y + tab_h + 12

	if M.state.current_tab == "camera" then
		_build_camera_tab(ctx, wx + pad_x, content_y, content_w)
	elseif M.state.current_tab == "time_hud" then
		_build_time_hud_tab(ctx, wx + pad_x, content_y, content_w)
	elseif M.state.current_tab == "lighting" then
		_build_lighting_tab(ctx, wx + pad_x, content_y, content_w)
	elseif M.state.current_tab == "rigs" then
		_build_rigs_tab(ctx, wx + pad_x, content_y, content_w)
	end

	local footer_btn_h = 28
	local footer_btn_y = wy + wh - footer_btn_h - 14
	local footer_line_y = footer_btn_y - 10

	_add_rect(items, wx + pad_x, footer_line_y, content_w, 1, colors.section_line, 2)

	local footer_gap = 12
	local footer_btn_w = math.floor((content_w - footer_gap) / 2)
	local reset_tab_x = wx + pad_x
	local reset_all_x = reset_tab_x + footer_btn_w + footer_gap

	_button(ctx, "btn_reset_tab", "RESET TAB", reset_tab_x, footer_btn_y, footer_btn_w, footer_btn_h, false, function()
		if mod.reset_tab_settings then
			mod.reset_tab_settings(M.state.current_tab)
		end
	end)

	_button(ctx, "btn_reset_all", "RESET ALL", reset_all_x, footer_btn_y, footer_btn_w, footer_btn_h, false, function()
		if mod.reset_all_settings then
			mod.reset_all_settings()
		end
	end, {
		hover_bg = { 255, 50, 26, 32 },
		hover_border = { 255, 160, 65, 75 },
	})

	if ctx.next_pressed then
		M.state.pressed_id = ctx.next_pressed
	end

	if ctx.next_dragging then
		M.state.dragging = ctx.next_dragging
	end

	element._menu_items = items
end

function M.draw(element, ui_renderer, render_settings)
	local items = element._menu_items

	if not items or #items == 0 then
		return
	end

	render_settings = render_settings or (ui_renderer and ui_renderer.render_settings)
	if render_settings and not render_settings.material_flags then
		render_settings.material_flags = 0
	end
	if ui_renderer and ui_renderer.render_settings and not ui_renderer.render_settings.material_flags then
		ui_renderer.render_settings.material_flags = 0
	end

	local text_options = {
		center = UIFonts.get_font_options_by_style({ text_horizontal_alignment = "center", text_vertical_alignment =
		"center" }),
		left = UIFonts.get_font_options_by_style({ text_horizontal_alignment = "left", text_vertical_alignment = "center" }),
		right = UIFonts.get_font_options_by_style({ text_horizontal_alignment = "right", text_vertical_alignment =
		"center" }),
	}

	local base_layer = M.LAYER
	local font_type = M.FONT_TYPE

	for i = 1, #items do
		local it = items[i]
		local z = base_layer + (it[7] or 0)

		if it[1] == "rect" then
			UIRenderer.draw_rect(ui_renderer, Vector3(it[2], it[3], z), Vector2(it[4], it[5]), it[6])
		elseif it[1] == "text" then
			local str = it[2]
			local x = it[3]
			local y = it[4]
			local w = it[5]
			local h = it[6]
			local font_size = it[7]
			local color = it[8]
			local align = it[9] or "center"
			local opt = text_options[align] or text_options.center

			UIRenderer.draw_text(ui_renderer, str, font_size, font_type, Vector3(x, y, z), Vector2(w, h), color, opt)
		end
	end
end

function M.destroy(element)
	mod._menu_hovered = false
	M.pop_cursor()
end

return M
