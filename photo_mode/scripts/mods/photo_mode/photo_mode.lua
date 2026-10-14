local mod = get_mod("photo_mode")

local ScriptViewport = require("scripts/foundation/utilities/script_viewport")
local ScriptWorld = require("scripts/foundation/utilities/script_world")

mod._time_frozen = false
mod._slomo_active = false
mod._hud_hidden = false
mod._chat_hidden = false
mod._arms_hidden = false
mod._screen_effects_hidden = false
mod._step_frames_remaining = nil

mod._placed_lights = {}
mod._lantern_active = false
mod._lantern_unit = nil

mod._fov_override = nil
mod._tilt_angle = 0
mod._dof_active = false
mod._dof_distance = 3.0
mod._dof_was_applied = false
mod._original_render_dof = nil

mod._tripod_active = false
mod._tripod_pos = nil
mod._tripod_rot = nil

mod._dolly_points = {}
mod._dolly_active = false
mod._dolly_progress = 0
mod._dolly_direction = 1
mod._dolly_pos = nil
mod._dolly_rot = nil
mod._dolly_dists = nil
mod._dolly_total_dist = 0

local HUD_VISIBILITY_GROUP = "photo_mode_hide_hud"

local function _get_level_world()
	if Managers.world and Managers.world:has_world("level_world") then
		return Managers.world:world("level_world")
	end

	return nil
end

local function _get_camera_transform()
	if mod._tripod_active and mod._tripod_pos and mod._tripod_rot then
		return mod._tripod_pos:unbox(), mod._tripod_rot:unbox()
	end

	if mod._dolly_active and mod._dolly_pos and mod._dolly_rot then
		return mod._dolly_pos:unbox(), mod._dolly_rot:unbox()
	end

	local world = _get_level_world()

	if world then
		local ff_viewport = ScriptWorld.global_free_flight_viewport and ScriptWorld.global_free_flight_viewport(world)

		if ff_viewport then
			local cam = ScriptViewport.camera(ff_viewport)

			if cam then
				return Camera.world_position(cam), Camera.world_rotation(cam)
			end
		end
	end

	local player_manager = Managers.player
	local player = player_manager and player_manager:local_player(1)

	if not player or not Managers.state.camera then
		return nil, nil
	end

	local camera_manager = Managers.state.camera
	local viewport_name = player.viewport_name

	if not viewport_name or not camera_manager:has_viewport(viewport_name) then
		return nil, nil
	end

	local pos = camera_manager:camera_position(viewport_name)
	local rot = camera_manager:camera_rotation(viewport_name)

	return pos, rot
end

local function _get_current_fov()
	if mod._fov_override then
		return mod._fov_override
	end

	local world = _get_level_world()

	if world then
		local ff_viewport = ScriptWorld.global_free_flight_viewport and ScriptWorld.global_free_flight_viewport(world)

		if ff_viewport then
			local cam = ScriptViewport.camera(ff_viewport)

			if cam then
				return math.floor(math.deg(Camera.vertical_fov(cam)) + 0.5)
			end
		end
	end

	local player_manager = Managers.player
	local player = player_manager and player_manager:local_player(1)

	if player and Managers.state.camera then
		local camera_manager = Managers.state.camera
		local viewport_name = player.viewport_name

		if viewport_name and camera_manager:has_viewport(viewport_name) then
			return math.floor(math.deg(camera_manager:fov(viewport_name)) + 0.5)
		end
	end

	return mod:get("camera_fov") or 65
end

local function _set_time_scale(scale)
	if Managers.time and Managers.time:has_timer("gameplay") then
		Managers.time:set_local_scale("gameplay", scale)
	end
end

local function _set_world_paused(paused)
	local world = _get_level_world()

	if world then
		if paused then
			ScriptWorld.pause(world)
		else
			ScriptWorld.unpause(world)
		end
	end
end

local function _apply_light_settings(light_obj)
	if not light_obj then
		return
	end

	local light_type = mod:get("light_type") or "spot"
	local intensity = mod:get("light_intensity") or 100
	local radius = mod:get("light_radius") or 20
	local spot_angle = mod:get("spot_angle") or 45
	local cast_shadows = mod:get("cast_shadows")

	if cast_shadows == nil then
		cast_shadows = true
	end

	local color_raw = mod:get("light_color") or { 255, 255, 245, 220 }
	local r = (color_raw[2] or 255) / 255
	local g = (color_raw[3] or 255) / 255
	local b = (color_raw[4] or 255) / 255

	Light.set_enabled(light_obj, true)
	Light.set_color_filter(light_obj, Vector3(r, g, b))
	Light.set_falloff_start(light_obj, 0.5)
	Light.set_falloff_end(light_obj, radius)
	Light.set_volumetric_intensity(light_obj, 0.3)
	Light.set_intensity(light_obj, intensity)
	Light.set_casts_shadows(light_obj, cast_shadows)

	if light_type == "spot" then
		Light.set_type(light_obj, "spot")
		Light.set_spot_angle_start(light_obj, 0)
		Light.set_spot_angle_end(light_obj, math.rad(spot_angle))
	else
		Light.set_type(light_obj, "omni")
	end
end

local function _ensure_hud_group()
	local hud = Managers.ui and Managers.ui._hud
	local visibility_groups = hud and hud._visibility_groups

	if visibility_groups then
		local found = false

		for i = 1, #visibility_groups do
			if visibility_groups[i].name == HUD_VISIBILITY_GROUP then
				found = true
				break
			end
		end

		if not found then
			table.insert(visibility_groups, 1, {
				name = HUD_VISIBILITY_GROUP,
				validation_function = function(h)
					return mod:is_enabled() and mod._hud_hidden
				end,
			})
		end
	end
end

local function _destroy_lantern()
	local world = _get_level_world()

	if world and mod._lantern_unit and Unit.alive(mod._lantern_unit) then
		World.destroy_unit(world, mod._lantern_unit)
	end

	mod._lantern_unit = nil
	mod._lantern_active = false
end

local function _reset_time_state()
	mod._time_frozen = false
	mod._slomo_active = false
	mod._step_frames_remaining = nil
	_set_world_paused(false)
	_set_time_scale(1.0)
end

local function _reset_hud_state()
	mod._hud_hidden = false
	mod._chat_hidden = false
	mod._screen_effects_hidden = false

	if mod._arms_hidden then
		local player = Managers.player and Managers.player:local_player(1)
		local unit = player and player.player_unit
		local player_visibility = unit and ScriptUnit.has_extension(unit, "player_visibility_system")

		if player_visibility then
			player_visibility:show()
		end

		mod._arms_hidden = false
	end
end

local function _reset_camera_state()
	mod._fov_override = nil
	mod._tilt_angle = 0

	if mod._dof_active and mod._original_render_dof == "false" and Application.set_render_setting then
		Application.set_render_setting("dof_enabled", "false")
	end

	mod._dof_active = false
	mod._original_render_dof = nil
end

local function _cleanup_all()
	_reset_time_state()
	_reset_hud_state()
	_reset_camera_state()
	_destroy_lantern()
	mod._silent_clear = true
	mod.clear_lights()
	mod._silent_clear = nil

	mod._tripod_active = false
	mod._tripod_pos = nil
	mod._tripod_rot = nil

	mod._dolly_active = false
	mod._dolly_progress = 0
	mod._dolly_direction = 1
	mod._dolly_pos = nil
	mod._dolly_rot = nil
	mod._dolly_dists = nil
	mod._dolly_total_dist = 0
	table.clear(mod._dolly_points)

	mod:set("freeze_time", false)
	mod:set("slomo_active", false)
	mod:set("hide_hud", false)
	mod:set("hide_chat", false)
	mod:set("hide_arms", false)
	mod:set("hide_screen_effects", false)
	mod:set("dof_active", false)
	mod:set("lantern_active", false)
	mod:set("tripod_active", false)
	mod:set("dolly_active", false)
end

mod.set_freeze_time = function(enabled)
	if not mod:is_enabled() then
		return
	end

	mod._time_frozen = enabled
	mod:set("freeze_time", enabled)

	if mod._time_frozen then
		_set_world_paused(true)
		_set_time_scale(0.00001)
		mod:echo(mod:localize("msg_time_frozen"))
	else
		_set_world_paused(false)

		if mod._slomo_active then
			local slomo_scale = mod:get("slomo_scale") or 0.10
			_set_time_scale(slomo_scale)
		else
			_set_time_scale(1.0)
		end

		mod:echo(mod:localize("msg_time_resumed"))
	end
end

mod.toggle_freeze_time = function()
	mod.set_freeze_time(not mod._time_frozen)
end

mod.step_frame = function()
	if not mod:is_enabled() then
		return
	end

	local world = _get_level_world()

	if not world then
		return
	end

	if not mod._time_frozen then
		mod._time_frozen = true
		mod:set("freeze_time", true)
	end

	_set_world_paused(false)
	_set_time_scale(1.0)
	mod._step_frames_remaining = 1
end

mod.set_slomo_active = function(enabled)
	if not mod:is_enabled() then
		return
	end

	mod._slomo_active = enabled
	mod:set("slomo_active", enabled)

	if not mod._time_frozen then
		if mod._slomo_active then
			local slomo_scale = mod:get("slomo_scale") or 0.10
			_set_time_scale(slomo_scale)
			mod:echo(mod:localize("msg_slomo_on"))
		else
			_set_time_scale(1.0)
			mod:echo(mod:localize("msg_slomo_off"))
		end
	else
		mod:echo(mod:localize(mod._slomo_active and "msg_slomo_on" or "msg_slomo_off"))
	end
end

mod.toggle_slomo = function()
	mod.set_slomo_active(not mod._slomo_active)
end

mod.increase_slomo_speed = function()
	if not mod:is_enabled() then
		return
	end

	local current = mod:get("slomo_scale") or 0.10
	local new_speed = math.min(1.0, math.floor((current + 0.05) * 100 + 0.5) / 100)

	mod:set("slomo_scale", new_speed)

	if mod._slomo_active and not mod._time_frozen then
		_set_time_scale(new_speed)
	end

	mod:echo(mod:localize("msg_slomo_speed") .. ": " .. string.format("%.2fx", new_speed))
end

mod.decrease_slomo_speed = function()
	if not mod:is_enabled() then
		return
	end

	local current = mod:get("slomo_scale") or 0.10
	local new_speed = math.max(0.01, math.floor((current - 0.05) * 100 + 0.5) / 100)

	mod:set("slomo_scale", new_speed)

	if mod._slomo_active and not mod._time_frozen then
		_set_time_scale(new_speed)
	end

	mod:echo(mod:localize("msg_slomo_speed") .. ": " .. string.format("%.2fx", new_speed))
end

mod.set_hide_hud = function(enabled)
	if not mod:is_enabled() then
		return
	end

	_ensure_hud_group()
	mod._hud_hidden = enabled
	mod:set("hide_hud", enabled)
	mod:echo(mod:localize(mod._hud_hidden and "msg_hud_hidden" or "msg_hud_shown"))
end

mod.toggle_hide_hud = function()
	mod.set_hide_hud(not mod._hud_hidden)
end

mod.set_hide_chat = function(enabled)
	if not mod:is_enabled() then
		return
	end

	mod._chat_hidden = enabled
	mod:set("hide_chat", enabled)
	mod:echo(mod:localize(mod._chat_hidden and "msg_chat_hidden" or "msg_chat_shown"))
end

mod.toggle_hide_chat = function()
	mod.set_hide_chat(not mod._chat_hidden)
end

mod.set_hide_arms = function(enabled)
	if not mod:is_enabled() then
		return
	end

	local player = Managers.player and Managers.player:local_player(1)
	local unit = player and player.player_unit
	local player_visibility = unit and ScriptUnit.has_extension(unit, "player_visibility_system")

	if player_visibility then
		mod._arms_hidden = enabled
		mod:set("hide_arms", enabled)

		if mod._arms_hidden then
			player_visibility:hide()
			mod:echo(mod:localize("msg_arms_hidden"))
		else
			player_visibility:show()
			mod:echo(mod:localize("msg_arms_shown"))
		end
	end
end

mod.toggle_hide_arms = function()
	mod.set_hide_arms(not mod._arms_hidden)
end

mod.set_hide_screen_effects = function(enabled)
	if not mod:is_enabled() then
		return
	end

	mod._screen_effects_hidden = enabled
	mod:set("hide_screen_effects", enabled)

	if mod._screen_effects_hidden then
		local player = Managers.player and Managers.player:local_player(1)
		local unit = player and player.player_unit
		local mood_extension = unit and ScriptUnit.has_extension(unit, "mood_system")

		if mood_extension and mood_extension.remove_all_moods then
			mood_extension:remove_all_moods()
		end

		mod:echo(mod:localize("msg_screen_effects_hidden"))
	else
		mod:echo(mod:localize("msg_screen_effects_shown"))
	end
end

mod.toggle_hide_screen_effects = function()
	mod.set_hide_screen_effects(not mod._screen_effects_hidden)
end

mod.zoom_in = function()
	if not mod:is_enabled() then
		return
	end

	local current = _get_current_fov()
	local new_fov = math.max(15, current - 5)

	mod._fov_override = new_fov
	mod:echo(mod:localize("msg_fov_changed") .. ": " .. tostring(new_fov) .. "°")
end

mod.zoom_out = function()
	if not mod:is_enabled() then
		return
	end

	local current = _get_current_fov()
	local new_fov = math.min(100, current + 5)

	mod._fov_override = new_fov
	mod:echo(mod:localize("msg_fov_changed") .. ": " .. tostring(new_fov) .. "°")
end

mod.reset_fov = function()
	if not mod:is_enabled() then
		return
	end

	mod._fov_override = nil

	local world = _get_level_world()

	if world then
		local ff_viewport = ScriptWorld.global_free_flight_viewport and ScriptWorld.global_free_flight_viewport(world)

		if ff_viewport then
			local cam = ScriptViewport.camera(ff_viewport)

			if cam then
				Camera.set_vertical_fov(cam, math.rad(65))
			end
		end
	end

	mod:echo(mod:localize("msg_fov_reset"))
end

mod.tilt_left = function()
	if not mod:is_enabled() then
		return
	end

	mod._tilt_angle = math.clamp((mod._tilt_angle or 0) - 2, -45, 45)
	mod:echo(mod:localize("msg_tilt_changed") .. ": " .. tostring(mod._tilt_angle) .. "°")
end

mod.tilt_right = function()
	if not mod:is_enabled() then
		return
	end

	mod._tilt_angle = math.clamp((mod._tilt_angle or 0) + 2, -45, 45)
	mod:echo(mod:localize("msg_tilt_changed") .. ": " .. tostring(mod._tilt_angle) .. "°")
end

mod.reset_tilt = function()
	if not mod:is_enabled() then
		return
	end

	mod._tilt_angle = 0
	mod:echo(mod:localize("msg_tilt_reset"))
end

mod.set_tripod_active = function(enabled)
	if not mod:is_enabled() then
		return
	end

	if enabled then
		local pos, rot = _get_camera_transform()

		if not pos or not rot then
			mod:set("tripod_active", false)
			return
		end

		mod._tripod_pos = Vector3Box(pos)
		mod._tripod_rot = QuaternionBox(rot)
		mod._tripod_active = true
		mod:set("tripod_active", true)
		mod:echo(mod:localize("msg_tripod_on"))
	else
		mod._tripod_active = false
		mod._tripod_pos = nil
		mod._tripod_rot = nil
		mod:set("tripod_active", false)
		mod:echo(mod:localize("msg_tripod_off"))
	end
end

mod.toggle_tripod = function()
	mod.set_tripod_active(not mod._tripod_active)
end

local function _calculate_dolly_distances()
	local dists = {}
	local total = 0
	local count = #mod._dolly_points

	for i = 1, count - 1 do
		local p1 = mod._dolly_points[i].pos:unbox()
		local p2 = mod._dolly_points[i + 1].pos:unbox()
		local d = Vector3.length(p2 - p1)
		dists[i] = d
		total = total + d
	end

	return dists, total
end

mod.dolly_add_point = function(label)
	if not mod:is_enabled() then
		return
	end

	local pos, rot = _get_camera_transform()

	if not pos or not rot then
		return
	end

	local count = #mod._dolly_points
	local default_label = count < 26 and string.char(65 + count) or tostring(count + 1)
	local name = (type(label) == "string" and label ~= "") and label or default_label

	table.insert(mod._dolly_points, {
		name = tostring(name),
		pos = Vector3Box(pos),
		rot = QuaternionBox(rot),
		fov = _get_current_fov(),
	})

	mod:echo(mod:localize("msg_dolly_point_added") .. ": Point " .. tostring(name) .. " (" .. tostring(#mod._dolly_points) .. " total)")
end

mod.dolly_clear_points = function()
	if not mod:is_enabled() then
		return
	end

	table.clear(mod._dolly_points)
	mod.set_dolly_active(false)
	mod:echo(mod:localize("msg_dolly_points_cleared"))
end

mod.dolly_list_points = function()
	if not mod:is_enabled() then
		return
	end

	local count = #mod._dolly_points

	if count == 0 then
		mod:echo(mod:localize("msg_dolly_no_points"))
		return
	end

	local names = {}
	for i = 1, count do
		table.insert(names, "Point " .. tostring(mod._dolly_points[i].name))
	end

	mod:echo("Dolly (" .. tostring(count) .. "): " .. table.concat(names, ", "))
end

mod.set_dolly_active = function(enabled)
	if not mod:is_enabled() then
		return
	end

	if enabled then
		local count = #mod._dolly_points

		if count < 2 then
			mod:echo(mod:localize("msg_dolly_missing_points"))
			mod:set("dolly_active", false)
			return
		end

		mod._dolly_dists, mod._dolly_total_dist = _calculate_dolly_distances()
		mod._dolly_progress = 0
		mod._dolly_direction = 1

		local start_pt = mod._dolly_points[1]
		mod._dolly_pos = Vector3Box(start_pt.pos:unbox())
		mod._dolly_rot = QuaternionBox(start_pt.rot:unbox())

		if start_pt.fov then
			mod._fov_override = start_pt.fov
		end

		mod._dolly_active = true
		mod:set("dolly_active", true)
		mod:echo(mod:localize("msg_dolly_started"))
	else
		mod._dolly_active = false
		mod._dolly_pos = nil
		mod._dolly_rot = nil
		mod:set("dolly_active", false)
		mod:echo(mod:localize("msg_dolly_stopped"))
	end
end

mod.toggle_dolly = function()
	mod.set_dolly_active(not mod._dolly_active)
end

mod.set_dof_active = function(enabled)
	if not mod:is_enabled() then
		return
	end

	mod._dof_active = enabled
	mod:set("dof_active", enabled)

	if mod._dof_active then
		if Application.render_setting and Application.set_render_setting then
			mod._original_render_dof = Application.render_setting("dof_enabled")
			if mod._original_render_dof == "false" then
				Application.set_render_setting("dof_enabled", "true")
			end
		end

		local dist = mod._dof_distance or mod:get("dof_focal_distance") or 3.0
		mod:echo(mod:localize("msg_dof_on") .. " (Focus: " .. string.format("%.1fm", dist) .. ")")
	else
		if mod._original_render_dof == "false" and Application.set_render_setting then
			Application.set_render_setting("dof_enabled", "false")
			mod._original_render_dof = nil
		end

		mod:echo(mod:localize("msg_dof_off"))
	end
end

mod.toggle_dof = function()
	mod.set_dof_active(not mod._dof_active)
end

mod.inc_dof_distance = function()
	if not mod:is_enabled() then
		return
	end

	if not mod._dof_active then
		mod.set_dof_active(true)
		return
	end

	local current = mod._dof_distance or mod:get("dof_focal_distance") or 3.0
	local new_dist = math.min(50.0, math.floor((current + 0.5) * 10 + 0.5) / 10)

	mod._dof_distance = new_dist
	mod:echo(mod:localize("msg_dof_distance") .. ": " .. string.format("%.1fm", new_dist))
end

mod.dec_dof_distance = function()
	if not mod:is_enabled() then
		return
	end

	if not mod._dof_active then
		mod.set_dof_active(true)
		return
	end

	local current = mod._dof_distance or mod:get("dof_focal_distance") or 3.0
	local new_dist = math.max(0.5, math.floor((current - 0.5) * 10 + 0.5) / 10)

	mod._dof_distance = new_dist
	mod:echo(mod:localize("msg_dof_distance") .. ": " .. string.format("%.1fm", new_dist))
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
		local light_obj = Unit.light(unit, 1)

		if light_obj then
			_apply_light_settings(light_obj)
			table.insert(mod._placed_lights, {
				unit = unit,
				light_obj = light_obj,
			})
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

		mod:echo(mod:localize("msg_light_undone") .. " (" .. tostring(#mod._placed_lights) .. " left)")
	end
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
		_destroy_lantern()
		mod:echo(mod:localize("msg_lantern_off"))
	else
		mod:echo(mod:localize("msg_lantern_on"))
	end
end

mod.toggle_lantern = function()
	mod.set_lantern_active(not mod._lantern_active)
end

mod.update = function(dt)
	if mod._step_frames_remaining and mod._step_frames_remaining > 0 then
		mod._step_frames_remaining = mod._step_frames_remaining - 1

		if mod._step_frames_remaining == 0 then
			_set_world_paused(true)
			_set_time_scale(0.00001)
			mod._step_frames_remaining = nil
		end
	end

	if mod._lantern_active then
		local world = _get_level_world()
		local pos, rot = _get_camera_transform()

		if world and pos and rot then
			if not mod._lantern_unit or not Unit.alive(mod._lantern_unit) then
				mod._lantern_unit = World.spawn_unit_ex(world, "core/units/light", nil, pos, rot)

				if mod._lantern_unit and Unit.alive(mod._lantern_unit) then
					local light_obj = Unit.light(mod._lantern_unit, 1)

					if light_obj then
						_apply_light_settings(light_obj)
					end
				end
			else
				Unit.set_local_position(mod._lantern_unit, 1, pos)
				Unit.set_local_rotation(mod._lantern_unit, 1, rot)
			end
		end
	end

	if mod._dolly_active and mod._dolly_points and #mod._dolly_points >= 2 and mod._dolly_pos and mod._dolly_rot then
		local duration = mod:get("dolly_duration") or 8.0
		local motion = mod:get("dolly_motion") or "smooth"

		mod._dolly_progress = mod._dolly_progress + (dt / math.max(0.1, duration)) * mod._dolly_direction

		if motion == "loop" then
			if mod._dolly_progress >= 1.0 then
				mod._dolly_progress = 1.0
				mod._dolly_direction = -1
			elseif mod._dolly_progress <= 0.0 then
				mod._dolly_progress = 0.0
				mod._dolly_direction = 1
			end
		else
			if mod._dolly_progress >= 1.0 then
				mod._dolly_progress = 1.0
			end
		end

		local raw_t = math.clamp(mod._dolly_progress, 0, 1)
		local t = raw_t

		if motion == "smooth" or motion == "loop" then
			t = raw_t * raw_t * (3 - 2 * raw_t)
		end

		if mod._dolly_total_dist and mod._dolly_total_dist > 0.001 and mod._dolly_dists then
			local target_dist = t * mod._dolly_total_dist
			local accumulated = 0
			local seg_index = 1
			local seg_t = 0

			for i = 1, #mod._dolly_dists do
				local seg_len = mod._dolly_dists[i]

				if target_dist <= accumulated + seg_len or i == #mod._dolly_dists then
					seg_index = i
					if seg_len > 0.0001 then
						seg_t = math.clamp((target_dist - accumulated) / seg_len, 0, 1)
					else
						seg_t = 0
					end
					break
				end

				accumulated = accumulated + seg_len
			end

			local pt1 = mod._dolly_points[seg_index]
			local pt2 = mod._dolly_points[seg_index + 1]

			if pt1 and pt2 and mod._dolly_pos and mod._dolly_rot then
				local cur_pos = Vector3.lerp(pt1.pos:unbox(), pt2.pos:unbox(), seg_t)
				local cur_rot = Quaternion.lerp(pt1.rot:unbox(), pt2.rot:unbox(), seg_t)

				mod._dolly_pos:store(cur_pos)
				mod._dolly_rot:store(cur_rot)

				if pt1.fov and pt2.fov then
					local cur_fov = math.floor(pt1.fov + (pt2.fov - pt1.fov) * seg_t + 0.5)
					mod._fov_override = cur_fov
				end
			end
		end

		if motion ~= "loop" and mod._dolly_progress >= 1.0 then
			mod.set_dolly_active(false)
		end
	end

	if mod._fov_override then
		local world = _get_level_world()

		if world then
			local ff_viewport = ScriptWorld.global_free_flight_viewport and ScriptWorld.global_free_flight_viewport(world)

			if ff_viewport then
				local cam = ScriptViewport.camera(ff_viewport)

				if cam then
					Camera.set_vertical_fov(cam, math.rad(mod._fov_override))
				end
			end
		end
	end
end

mod:hook("UIHud", "init", function(func, self, elements, visibility_groups, params)
	table.insert(visibility_groups, 1, {
		name = HUD_VISIBILITY_GROUP,
		validation_function = function(hud)
			return mod:is_enabled() and mod._hud_hidden
		end,
	})

	return func(self, elements, visibility_groups, params)
end)

mod:hook("ConstantElementChat", "draw", function(func, self, dt, t, ui_renderer, render_settings, input_service)
	if mod:is_enabled() and (mod._chat_hidden or mod._hud_hidden) then
		return
	end

	return func(self, dt, t, ui_renderer, render_settings, input_service)
end)

mod:hook("ConstantElementChat", "should_draw", function(func, self)
	if mod:is_enabled() and (mod._chat_hidden or mod._hud_hidden) then
		return false
	end

	return func(self)
end)

mod:hook("CameraManager", "_update_camera_properties", function(func, self, camera, shadow_cull_camera, camera_nodes, camera_data, viewport_name)
	if mod:is_enabled() then
		if mod._tripod_active and mod._tripod_pos and mod._tripod_rot then
			camera_data.position = mod._tripod_pos:unbox()
			camera_data.rotation = mod._tripod_rot:unbox()
		elseif mod._dolly_active and mod._dolly_pos and mod._dolly_rot then
			camera_data.position = mod._dolly_pos:unbox()
			camera_data.rotation = mod._dolly_rot:unbox()
		elseif mod._tilt_angle and mod._tilt_angle ~= 0 and camera_data.rotation then
			local roll_offset = Quaternion.from_yaw_pitch_roll(0, 0, math.rad(mod._tilt_angle))
			camera_data.rotation = Quaternion.multiply(camera_data.rotation, roll_offset)
		end

		if mod._fov_override and camera_data.vertical_fov then
			camera_data.vertical_fov = math.rad(mod._fov_override)
		end
	end

	func(self, camera, shadow_cull_camera, camera_nodes, camera_data, viewport_name)

	if mod:is_enabled() and mod._fov_override then
		Camera.set_vertical_fov(camera, math.rad(mod._fov_override))
	end
end)

mod:hook_safe("CameraManager", "shading_callback", function(self, world, shading_env, viewport, default_shading_environment_resource)
	if self._world ~= world then
		return
	end

	if not mod:is_enabled() then
		if mod._dof_was_applied then
			ShadingEnvironment.set_scalar(shading_env, "dof_enabled", 0)
			ShadingEnvironment.apply(shading_env)
			mod._dof_was_applied = false
		end
		return
	end

	if mod._dof_active then
		local focal_distance = mod._dof_distance or mod:get("dof_focal_distance") or 3.0
		local focal_region = mod:get("dof_focal_region") or 4.0
		local blur_amount = mod:get("dof_blur_amount") or 1.0

		ShadingEnvironment.set_scalar(shading_env, "dof_enabled", 1)
		ShadingEnvironment.set_scalar(shading_env, "dof_focal_distance", focal_distance)
		ShadingEnvironment.set_scalar(shading_env, "dof_focal_region", focal_region)
		ShadingEnvironment.set_scalar(shading_env, "dof_focal_region_start", 2)
		ShadingEnvironment.set_scalar(shading_env, "dof_focal_region_end", 2)
		ShadingEnvironment.set_scalar(shading_env, "dof_focal_near_scale", blur_amount)
		ShadingEnvironment.set_scalar(shading_env, "dof_focal_far_scale", blur_amount)
		ShadingEnvironment.apply(shading_env)
		mod._dof_was_applied = true
	elseif mod._dof_was_applied then
		ShadingEnvironment.set_scalar(shading_env, "dof_enabled", 0)
		ShadingEnvironment.apply(shading_env)
		mod._dof_was_applied = false
	end
end)

mod:hook_safe("FreeFlightManager", "_update_camera", function(self, input, dt, camera_data)
	if mod:is_enabled() then
		local pos = nil
		local rot = nil

		if mod._tripod_active and mod._tripod_pos and mod._tripod_rot then
			pos = mod._tripod_pos:unbox()
			rot = mod._tripod_rot:unbox()
		elseif mod._dolly_active and mod._dolly_pos and mod._dolly_rot then
			pos = mod._dolly_pos:unbox()
			rot = mod._dolly_rot:unbox()
		end

		if pos and rot then
			local world = Managers.world:world(camera_data.viewport_world_name)
			local viewport = world and ScriptWorld.global_free_flight_viewport(world)
			local cam = camera_data.frustum_freeze_camera or (viewport and ScriptViewport.camera(viewport))

			if cam then
				ScriptCamera.set_local_position(cam, pos)
				ScriptCamera.set_local_rotation(cam, rot)
			end
		end
	end
end)

mod:hook("BloodManager", "play_screen_space_blood", function(func, self, fx_extension)
	if mod:is_enabled() and mod._screen_effects_hidden then
		return
	end

	return func(self, fx_extension)
end)

mod:hook("PlayerUnitFxExtension", "spawn_exclusive_particle", function(func, self, particle_name, ...)
	if mod:is_enabled() and mod._screen_effects_hidden and particle_name and string.find(particle_name, "screenspace") then
		return
	end

	return func(self, particle_name, ...)
end)

mod:hook("PlayerUnitMoodExtension", "_add_mood", function(func, self, t, mood_type, reset_time)
	if mod:is_enabled() and mod._screen_effects_hidden then
		return
	end

	return func(self, t, mood_type, reset_time)
end)

mod:hook("PlayerUnitMoodExtension", "add_timed_mood", function(func, self, t, mood_type)
	if mod:is_enabled() and mod._screen_effects_hidden then
		return
	end

	return func(self, t, mood_type)
end)

mod:hook("PlasmagunOverheatEffects", "_update_screenspace", function(func, ...)
	if mod:is_enabled() and mod._screen_effects_hidden then
		return
	end

	return func(...)
end)

mod:hook("PlayerUnitBuffExtension", "_start_fx", function(func, self, index, template)
	if mod:is_enabled() and mod._screen_effects_hidden and template and template.player_effects then
		return
	end

	return func(self, index, template)
end)

mod:hook("FxSystem", "start_template_effect", function(func, self, template, ...)
	if mod:is_enabled() and mod._screen_effects_hidden and template and (template.name == "chaos_daemonhost_ambience" or template.name == "corruptor_ambience" or template.name == "corruptor_ambience_burrowed") then
		return
	end

	return func(self, template, ...)
end)

mod.on_setting_changed = function(setting_id)
	if setting_id == "freeze_time" then
		local val = mod:get("freeze_time")
		if val ~= mod._time_frozen then
			mod.set_freeze_time(val)
		end
	elseif setting_id == "slomo_active" then
		local val = mod:get("slomo_active")
		if val ~= mod._slomo_active then
			mod.set_slomo_active(val)
		end
	elseif setting_id == "hide_hud" then
		local val = mod:get("hide_hud")
		if val ~= mod._hud_hidden then
			mod.set_hide_hud(val)
		end
	elseif setting_id == "hide_chat" then
		local val = mod:get("hide_chat")
		if val ~= mod._chat_hidden then
			mod.set_hide_chat(val)
		end
	elseif setting_id == "hide_arms" then
		local val = mod:get("hide_arms")
		if val ~= mod._arms_hidden then
			mod.set_hide_arms(val)
		end
	elseif setting_id == "hide_screen_effects" then
		local val = mod:get("hide_screen_effects")
		if val ~= mod._screen_effects_hidden then
			mod.set_hide_screen_effects(val)
		end
	elseif setting_id == "dof_active" then
		local val = mod:get("dof_active")
		if val ~= mod._dof_active then
			mod.set_dof_active(val)
		end
	elseif setting_id == "lantern_active" then
		local val = mod:get("lantern_active")
		if val ~= mod._lantern_active then
			mod.set_lantern_active(val)
		end
	elseif setting_id == "tripod_active" then
		local val = mod:get("tripod_active")
		if val ~= mod._tripod_active then
			mod.set_tripod_active(val)
		end
	elseif setting_id == "dolly_active" then
		local val = mod:get("dolly_active")
		if val ~= mod._dolly_active then
			mod.set_dolly_active(val)
		end
	elseif setting_id == "slomo_scale" and mod._slomo_active and not mod._time_frozen then
		local slomo_scale = mod:get("slomo_scale") or 0.10
		_set_time_scale(slomo_scale)
	elseif setting_id == "camera_fov" then
		mod._fov_override = mod:get("camera_fov")
	elseif setting_id == "camera_tilt" then
		mod._tilt_angle = mod:get("camera_tilt") or 0
	elseif setting_id == "dof_focal_distance" then
		mod._dof_distance = mod:get("dof_focal_distance") or 3.0
	end

	if mod._lantern_active and mod._lantern_unit and Unit.alive(mod._lantern_unit) then
		local light_obj = Unit.light(mod._lantern_unit, 1)
		if light_obj then
			_apply_light_settings(light_obj)
		end
	end
end

mod.on_game_state_changed = function(status, state_name)
	_cleanup_all()
end

mod.on_disabled = function(initial_call)
	_cleanup_all()
end

mod.on_unload = function(exit_game)
	_cleanup_all()
end

mod:command("dolly", mod:localize("cmd_dolly_desc"), function(action, param)
	local act = action and string.lower(action) or "help"

	if act == "add" or act == "a" or act == "b" or act == "c" or act == "d" or act == "point" then
		local custom_name = nil
		if act ~= "add" and act ~= "point" then
			custom_name = string.upper(act)
		elseif param and param ~= "" then
			custom_name = string.upper(param)
		end
		mod.dolly_add_point(custom_name)
	elseif act == "clear" or act == "reset" then
		mod.dolly_clear_points()
	elseif act == "list" or act == "show" then
		mod.dolly_list_points()
	elseif act == "play" or act == "start" or act == "go" then
		mod.set_dolly_active(true)
	elseif act == "stop" or act == "pause" then
		mod.set_dolly_active(false)
	elseif act == "loop" then
		local cur = mod:get("dolly_motion")
		local new_motion = cur == "loop" and "smooth" or "loop"
		mod:set("dolly_motion", new_motion)
		mod:echo(mod:localize("msg_dolly_motion") .. ": " .. new_motion)
	elseif act == "time" and param then
		local num = tonumber(param)
		if num and num > 0 then
			mod:set("dolly_duration", num)
			mod:echo(mod:localize("msg_dolly_duration") .. ": " .. tostring(num) .. "s")
		end
	else
		mod:echo(mod:localize("msg_dolly_help_1"))
		mod:echo(mod:localize("msg_dolly_help_2"))
		mod:echo(mod:localize("msg_dolly_help_3"))
		mod:echo(mod:localize("msg_dolly_help_4"))
	end
end)
