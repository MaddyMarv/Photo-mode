local mod = get_mod("photo_mode")
local Shared = mod._shared

local LightControllerUtilities = require("core/scripts/common/light_controller_utilities")

local _destroy_lantern_unit = Shared._destroy_lantern_unit
local _get_camera_transform = Shared._get_camera_transform
local _get_level_world = Shared._get_level_world

local function _get_current_light_settings()
	local color_raw = mod:get("light_color") or { 255, 255, 245, 220 }
	local cast_shadows = mod:get("cast_shadows")

	if cast_shadows == nil then
		cast_shadows = true
	end

	return {
		light_type = mod:get("light_type") or "spot",
		intensity = mod:get("light_intensity") or 100,
		radius = mod:get("light_radius") or 20,
		spot_angle = mod:get("spot_angle") or 45,
		cast_shadows = cast_shadows,
		color = { color_raw[1] or 255, color_raw[2] or 255, color_raw[3] or 245, color_raw[4] or 220 },
	}
end

local function _apply_light_settings(light_obj, settings)
	if not light_obj then
		return
	end

	local s = settings or _get_current_light_settings()
	local light_type = s.light_type or "spot"
	local intensity = s.intensity or 100
	local radius = s.radius or 20
	local spot_angle = s.spot_angle or 45
	local cast_shadows = s.cast_shadows

	if cast_shadows == nil then
		cast_shadows = true
	end

	local color_raw = s.color or { 255, 255, 245, 220 }
	local r = (color_raw[2] or 255) / 255
	local g = (color_raw[3] or 255) / 255
	local b = (color_raw[4] or 255) / 255

	Light.set_enabled(light_obj, true)
	Light.set_color_filter(light_obj, Vector3(r, g, b))
	local falloff_start = math.min(0.05, radius * 0.1)
	Light.set_falloff_start(light_obj, falloff_start)
	Light.set_falloff_end(light_obj, radius)
	Light.set_volumetric_intensity(light_obj, 0.3)
	local exp_offset = math.clamp(mod:get("exposure_compensation") or 0.0, -11.0, 3.0)
	local effective_intensity = intensity * math.pow(2, -exp_offset)
	Light.set_intensity(light_obj, effective_intensity)
	Light.set_casts_shadows(light_obj, cast_shadows)

	if light_type == "spot" then
		Light.set_type(light_obj, "spot")
		Light.set_spot_angle_start(light_obj, 0)
		Light.set_spot_angle_end(light_obj, math.rad(spot_angle))
	else
		Light.set_type(light_obj, "omni")
	end
end

local function _sync_settings_from_light(s)
	if not s then
		return
	end

	mod:set("light_type", s.light_type, true)
	mod:set("light_intensity", s.intensity, true)
	mod:set("light_radius", s.radius, true)
	mod:set("spot_angle", s.spot_angle, true)
	mod:set("cast_shadows", s.cast_shadows, true)
	if s.color then
		mod:set("light_color", { s.color[1] or 255, s.color[2] or 255, s.color[3] or 245, s.color[4] or 220 }, true)
	end
end

mod.select_light = function(index, silent)
	local count = #mod._placed_lights
	if count == 0 then
		mod._selected_light_index = nil
		return
	end

	index = math.clamp(index or count, 1, count)
	mod._selected_light_index = index

	local light_data = mod._placed_lights[index]
	if light_data and light_data.settings then
		_sync_settings_from_light(light_data.settings)
	end

	if not silent then
		mod:echo(mod:localize("msg_selected_light") .. " #" .. tostring(index) .. " of " .. tostring(count))
	end
end

mod.select_prev_light = function()
	local count = #mod._placed_lights
	if count == 0 then
		return
	end

	local cur = mod._selected_light_index or count
	local target = cur - 1
	if target < 1 then
		target = count
	end

	mod.select_light(target)
end

mod.select_next_light = function()
	local count = #mod._placed_lights
	if count == 0 then
		return
	end

	local cur = mod._selected_light_index or count
	local target = cur + 1
	if target > count then
		target = 1
	end

	mod.select_light(target)
end

mod.update_all_lights = function()
	if mod._lantern_active and mod._lantern_unit and Unit.alive(mod._lantern_unit) then
		local light_obj = Unit.light(mod._lantern_unit, 1)
		if light_obj then
			_apply_light_settings(light_obj)
		end
	end

	local count = #mod._placed_lights
	if count > 0 then
		for i = 1, count do
			local light_data = mod._placed_lights[i]
			if light_data and light_data.unit and Unit.alive(light_data.unit) and light_data.light_obj then
				if i == mod._selected_light_index then
					light_data.settings = _get_current_light_settings()
				end
				_apply_light_settings(light_data.light_obj, light_data.settings)
			end
		end
	end
end

mod.place_light = function()
	if not mod:is_enabled() then
		return
	end

	local world = _get_level_world()
	local pos, rot = _get_camera_transform()

	if not world or not pos or not rot then
		return
	end

	local unit = World.spawn_unit_ex(world, "core/units/light", nil, pos, rot)

	if unit and Unit.alive(unit) then
		Unit.set_data(unit, "photo_mode_light", true)
		local light_obj = Unit.light(unit, 1)

		if light_obj then
			local light_settings = _get_current_light_settings()
			_apply_light_settings(light_obj, light_settings)
			table.insert(mod._placed_lights, {
				unit = unit,
				light_obj = light_obj,
				settings = light_settings,
			})
			mod._selected_light_index = #mod._placed_lights
			mod:echo(mod:localize("msg_light_placed") .. " (" .. tostring(#mod._placed_lights) .. ")")
		end
	end
end

mod.undo_light = function()
	if not mod:is_enabled() then
		return
	end

	local world = _get_level_world()
	local count = #mod._placed_lights

	if count > 0 then
		local light_data = table.remove(mod._placed_lights, count)

		if world and light_data.unit and Unit.alive(light_data.unit) then
			World.destroy_unit(world, light_data.unit)
		end

		local remaining = #mod._placed_lights
		if remaining > 0 then
			local sel = math.clamp(mod._selected_light_index or remaining, 1, remaining)
			mod.select_light(sel, true)
		else
			mod._selected_light_index = nil
		end

		mod:echo(mod:localize("msg_light_undone") .. " (" .. tostring(remaining) .. " left)")
	end
end

mod.extinguish_map_lights = function(silent)
	local world = _get_level_world()
	if not world then
		return
	end

	local units = World.units(world)
	local count = 0

	for i = 1, #units do
		local u = units[i]
		if Unit.alive(u) and not Unit.get_data(u, "photo_mode_light") and not mod._extinguished_units[u] then
			local num_lights = Unit.num_lights(u)
			local has_lc = ScriptUnit.has_extension(u, "light_controller_system")
			if num_lights > 0 or has_lc then
				local ok, _ = pcall(LightControllerUtilities.set_enabled, u, false)
				if ok then
					mod._extinguished_units[u] = true
					count = count + 1
				end
			end
		end
	end

	if not silent and not mod._silent_reset then
		mod:echo(mod:localize("msg_blackout_on"))
	end
end

mod.restore_all_extinguished_lights = function(silent)
	for u, _ in pairs(mod._extinguished_units) do
		if Unit.alive(u) then
			pcall(LightControllerUtilities.set_enabled, u, true)
		end
	end
	table.clear(mod._extinguished_units)
	if not silent then
		mod:echo(mod:localize("msg_blackout_off"))
	end
end

mod.toggle_map_lights = function()
	mod:set("map_lights", mod:get("map_lights") == false, true)
end
mod.toggle_blackout = mod.toggle_map_lights
mod.toggle_blackout_zone = mod.toggle_map_lights

mod.delete_selected_light = function()
	if not mod:is_enabled() then
		return
	end

	local count = #mod._placed_lights
	if count == 0 then
		return
	end

	local sel_idx = math.clamp(mod._selected_light_index or count, 1, count)
	local world = _get_level_world()
	local light_data = table.remove(mod._placed_lights, sel_idx)

	if world and light_data and light_data.unit and Unit.alive(light_data.unit) then
		World.destroy_unit(world, light_data.unit)
	end

	local remaining = #mod._placed_lights
	if remaining > 0 then
		local new_sel = math.clamp(sel_idx, 1, remaining)
		mod.select_light(new_sel, true)
	else
		mod._selected_light_index = nil
	end

	mod:echo(mod:localize("msg_light_deleted") .. " #" .. tostring(sel_idx) .. " (" .. tostring(remaining) .. " left)")
end

mod.clear_lights = function()
	local world = _get_level_world()
	local had_lights = #mod._placed_lights > 0

	for i = 1, #mod._placed_lights do
		local light_data = mod._placed_lights[i]

		if world and light_data.unit and Unit.alive(light_data.unit) then
			World.destroy_unit(world, light_data.unit)
		end
	end

	table.clear(mod._placed_lights)
	mod._selected_light_index = nil

	if world then
		local units = World.units(world)
		for i = 1, #units do
			local u = units[i]
			if Unit.alive(u) and Unit.get_data(u, "photo_mode_light") == true then
				World.destroy_unit(world, u)
			end
		end
	end

	if not mod._silent_clear and had_lights then
		mod:echo(mod:localize("msg_lights_cleared"))
	end
end

mod.set_lantern_active = function(enabled)
	if not mod:is_enabled() then
		return
	end

	mod._lantern_active = enabled
	mod:set("lantern_active", enabled)

	if not mod._lantern_active then
		_destroy_lantern_unit()
		if not mod._silent_reset then
			mod:echo(mod:localize("msg_lantern_off"))
		end
	else
		if not mod._silent_reset then
			mod:echo(mod:localize("msg_lantern_on"))
		end
	end
end

mod.toggle_lantern = function()
	mod:set("lantern_active", not mod:get("lantern_active"), true)
end

Shared._apply_light_settings = _apply_light_settings
