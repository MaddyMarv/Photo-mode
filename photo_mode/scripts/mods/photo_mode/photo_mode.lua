local mod = get_mod("photo_mode")

local ScriptViewport = require("scripts/foundation/utilities/script_viewport")
local ScriptWorld = require("scripts/foundation/utilities/script_world")
local MoodSettings = require("scripts/settings/camera/mood/mood_settings")

if Managers.input and Managers.input._cursor_stack_data then
	local cdata = Managers.input._cursor_stack_data
	if cdata.stack_depth < 0 then
		cdata.stack_depth = 0
	end
end

local session = rawget(_G, "_photo_mode_session")
if not session then
	session = {
		menu_open = false,
	}
	rawset(_G, "_photo_mode_session", session)
end

mod._menu_open = session.menu_open
mod._camera_locked = mod:get("lock_camera_in_menu") ~= false
mod:add_require_path("photo_mode/scripts/mods/photo_mode/hud/hud_element_photo_mode_menu")

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

mod._fov_offset = mod:get("camera_fov_offset") or 0
mod._tilt_angle = mod:get("camera_tilt") or 0
mod._dof_active = false
mod._dof_distance = mod:get("dof_focal_distance") or 3.0
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

mod._orbit_active = false
mod._orbit_pos = nil
mod._orbit_rot = nil
mod._orbit_center = nil
mod._orbit_angle = 0
mod._orbit_height = 0

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

	if mod._orbit_active and mod._orbit_pos and mod._orbit_rot then
		return mod._orbit_pos:unbox(), mod._orbit_rot:unbox()
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

	return 65
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

mod.update_all_lights = function()
	if mod._lantern_active and mod._lantern_unit and Unit.alive(mod._lantern_unit) then
		local light_obj = Unit.light(mod._lantern_unit, 1)
		if light_obj then
			_apply_light_settings(light_obj)
		end
	end

	for i = 1, #mod._placed_lights do
		local light_data = mod._placed_lights[i]
		if light_data and light_data.unit and Unit.alive(light_data.unit) and light_data.light_obj then
			_apply_light_settings(light_data.light_obj)
		end
	end
end

local function _ensure_hud_group()
	local hud = Managers.ui and Managers.ui._hud
	local visibility_groups = hud and hud._visibility_groups

	if visibility_groups then
		local found_group = nil

		for i = #visibility_groups, 1, -1 do
			if visibility_groups[i].name == HUD_VISIBILITY_GROUP then
				if not found_group then
					found_group = visibility_groups[i]
				else
					table.remove(visibility_groups, i)
				end
			end
		end

		if not found_group then
			found_group = {
				name = HUD_VISIBILITY_GROUP,
				validation_function = function(h)
					return mod:is_enabled() and mod._hud_hidden
				end,
			}
			table.insert(visibility_groups, 1, found_group)
		end

		found_group.visible_elements = found_group.visible_elements or {}
		found_group.visible_elements.HudElementPhotoModeMenu = true

		if hud._elements and not hud._elements.HudElementPhotoModeMenu then
			local elements = hud._elements
			local elements_array = hud._elements_array
			local class = rawget(_G, "HudElementPhotoModeMenu")

			if class then
				local element = class:new(hud, 100, RESOLUTION_LOOKUP.scale)
				elements.HudElementPhotoModeMenu = element
				elements_array[#elements_array + 1] = element
			end
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

	if mod._screen_effects_hidden then
		mod._screen_effects_hidden = false
		local player = Managers.player and Managers.player:local_player(1)
		local camera_handler = player and player.camera_handler
		local mood_handler = camera_handler and camera_handler._mood_handler
		if mood_handler and mood_handler._current_moods_status then
			for mood_type, _ in pairs(mood_handler._current_moods_status) do
				mood_handler._current_moods_status[mood_type] = MoodSettings.status.inactive
			end
		end
	end

	if mod._arms_hidden then
		local player = Managers.player and Managers.player:local_player(1)
		local unit = player and player.player_unit
		local player_visibility = unit and ScriptUnit.has_extension(unit, "player_visibility_system")

		if player_visibility then
			player_visibility:show()
		end

		mod._arms_hidden = false
	end

	local hud = Managers.ui and Managers.ui._hud
	if hud then
		hud._current_group_name = nil
	end
end

local function _reset_camera_state()
	mod._fov_offset = 0
	mod._tilt_angle = 0
	mod:set("camera_tilt", 0)

	if mod._dof_active and mod._original_render_dof == "false" and Application.set_render_setting then
		Application.set_render_setting("dof_enabled", "false")
	end

	mod._dof_active = false
	mod._original_render_dof = nil
end

local function _cleanup_all(is_reloading)
	if is_reloading then
		return
	end

	mod.close_photo_menu()
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
	mod:set("camera_fov_offset", 0)
	mod:set("camera_tilt", 0)
	mod:set("dof_active", false)
	mod:set("lantern_active", false)
	mod:set("tripod_active", false)
	mod:set("dolly_active", false)
	mod:set("orbit_active", false)

	mod._orbit_active = false
	mod._orbit_pos = nil
	mod._orbit_rot = nil
	mod._orbit_center = nil
	mod._orbit_angle = 0
	mod._orbit_height = 0
end

mod.reset_tab_camera = function(silent)
	if not mod:is_enabled() then
		return
	end

	mod._silent_reset = true
	mod._fov_offset = 0
	mod:set("camera_fov_offset", 0)

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

	mod._tilt_angle = 0
	mod:set("camera_tilt", 0)

	if mod._dof_active then
		mod.set_dof_active(false)
	end
	mod._dof_distance = 3.0
	mod:set("dof_focal_distance", 3.0, true)
	mod:set("dof_focal_region", 4.0, true)
	mod:set("dof_blur_amount", 1.0, true)
	mod._silent_reset = nil

	if not silent then
		mod:echo(mod:localize("msg_reset_tab_camera"))
	end
end

mod.reset_tab_time_hud = function(silent)
	if not mod:is_enabled() then
		return
	end

	mod._silent_reset = true
	if mod._time_frozen then
		mod.set_freeze_time(false)
	end
	if mod._slomo_active then
		mod.set_slomo_active(false)
	end
	mod:set("slomo_scale", 0.10, true)

	if mod._hud_hidden then
		mod.set_hide_hud(false)
	end
	if mod._chat_hidden then
		mod.set_hide_chat(false)
	end
	if mod._arms_hidden then
		mod.set_hide_arms(false)
	end
	if mod._screen_effects_hidden then
		mod.set_hide_screen_effects(false)
	end
	mod._silent_reset = nil

	if not silent then
		mod:echo(mod:localize("msg_reset_tab_time_hud"))
	end
end

mod.reset_tab_lighting = function(silent)
	if not mod:is_enabled() then
		return
	end

	mod._silent_clear = true
	mod.clear_lights()
	mod._silent_clear = nil

	mod._silent_reset = true
	if mod._lantern_active then
		mod.set_lantern_active(false)
	end
	mod._silent_reset = nil

	mod:set("light_type", "spot", true)
	mod:set("cast_shadows", true, true)
	mod:set("light_intensity", 100, true)
	mod:set("light_radius", 20, true)
	mod:set("spot_angle", 45, true)
	mod:set("light_color", { 255, 255, 245, 220 }, true)

	if mod.update_all_lights then
		mod.update_all_lights()
	end

	if not silent then
		mod:echo(mod:localize("msg_reset_tab_lighting"))
	end
end

mod.reset_tab_rigs = function(silent)
	if not mod:is_enabled() then
		return
	end

	mod._silent_reset = true
	if mod._tripod_active then
		mod.set_tripod_active(false)
	end
	if mod._dolly_active then
		mod.set_dolly_active(false)
	end
	table.clear(mod._dolly_points)
	mod:set("dolly_duration", 8.0, true)
	mod:set("dolly_motion", "smooth", true)

	if mod._orbit_active then
		mod.set_orbit_active(false)
	end
	mod._silent_reset = nil

	mod:set("orbit_target_mode", "character", true)
	mod:set("orbit_facing", "inward", true)
	mod:set("orbit_direction", "cw", true)
	mod:set("orbit_speed", 15, true)
	mod:set("orbit_radius", 4.0, true)
	mod:set("orbit_height", 0.3, true)

	if not silent then
		mod:echo(mod:localize("msg_reset_tab_rigs"))
	end
end

mod.reset_tab_settings = function(tab_id, silent)
	if tab_id == "camera" then
		mod.reset_tab_camera(silent)
	elseif tab_id == "time_hud" then
		mod.reset_tab_time_hud(silent)
	elseif tab_id == "lighting" then
		mod.reset_tab_lighting(silent)
	elseif tab_id == "rigs" then
		mod.reset_tab_rigs(silent)
	end
end

mod.reset_all_settings = function()
	if not mod:is_enabled() then
		return
	end

	mod.reset_tab_camera(true)
	mod.reset_tab_time_hud(true)
	mod.reset_tab_lighting(true)
	mod.reset_tab_rigs(true)

	mod:echo(mod:localize("msg_reset_all"))
end

mod.open_photo_menu = function()
	if not mod:is_enabled() then
		return
	end

	mod._menu_open = true
	local s = rawget(_G, "_photo_mode_session")
	if s then
		s.menu_open = true
	end
end

mod.close_photo_menu = function()
	if mod._menu_open then
		mod._menu_open = false
		local s = rawget(_G, "_photo_mode_session")
		if s then
			s.menu_open = false
		end
	end
end

mod.toggle_photo_menu = function()
	if not mod:is_enabled() then
		return
	end

	if mod._menu_open then
		mod.close_photo_menu()
	else
		mod.open_photo_menu()
	end
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
	mod._step_frames_remaining = (mod._step_frames_remaining or 0) + 2
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

	local hud = Managers.ui and Managers.ui._hud
	if hud then
		hud._current_group_name = nil
	end

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

	local player = Managers.player and Managers.player:local_player(1)
	local camera_handler = player and player.camera_handler
	local mood_handler = camera_handler and camera_handler._mood_handler

	if mod._screen_effects_hidden then
		if mood_handler then
			local world = mood_handler._world
			local looping_particles = mood_handler._looping_particles
			if world and looping_particles then
				for mood_type, particles in pairs(looping_particles) do
					for i = #particles, 1, -1 do
						local particle_id = particles[i]
						if particle_id then
							World.destroy_particles(world, particle_id)
						end
						particles[i] = nil
					end
				end
			end
		end

		mod:echo(mod:localize("msg_screen_effects_hidden"))
	else
		if mood_handler and mood_handler._current_moods_status then
			for mood_type, _ in pairs(mood_handler._current_moods_status) do
				mood_handler._current_moods_status[mood_type] = MoodSettings.status.inactive
			end
		end

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

	local cur = mod._fov_offset or 0
	local new_offset = math.clamp(cur - 5, -60, 60)

	mod._fov_offset = new_offset
	mod:set("camera_fov_offset", new_offset)

	local sign = new_offset > 0 and "+" or ""
	mod:echo(mod:localize("msg_fov_changed") .. ": " .. sign .. tostring(new_offset) .. "°")
end

mod.zoom_out = function()
	if not mod:is_enabled() then
		return
	end

	local cur = mod._fov_offset or 0
	local new_offset = math.clamp(cur + 5, -60, 60)

	mod._fov_offset = new_offset
	mod:set("camera_fov_offset", new_offset)

	local sign = new_offset > 0 and "+" or ""
	mod:echo(mod:localize("msg_fov_changed") .. ": " .. sign .. tostring(new_offset) .. "°")
end

mod.reset_fov = function(silent)
	if not mod:is_enabled() then
		return
	end

	mod._fov_offset = 0
	mod:set("camera_fov_offset", 0)

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

	if not silent and not mod._silent_reset then
		mod:echo(mod:localize("msg_fov_reset"))
	end
end

mod.tilt_left = function()
	if not mod:is_enabled() then
		return
	end

	mod._tilt_angle = math.clamp((mod._tilt_angle or 0) - 2, -45, 45)
	mod:set("camera_tilt", mod._tilt_angle)
	mod:echo(mod:localize("msg_tilt_changed") .. ": " .. tostring(mod._tilt_angle) .. "°")
end

mod.tilt_right = function()
	if not mod:is_enabled() then
		return
	end

	mod._tilt_angle = math.clamp((mod._tilt_angle or 0) + 2, -45, 45)
	mod:set("camera_tilt", mod._tilt_angle)
	mod:echo(mod:localize("msg_tilt_changed") .. ": " .. tostring(mod._tilt_angle) .. "°")
end

mod.reset_tilt = function(silent)
	if not mod:is_enabled() then
		return
	end

	mod._tilt_angle = 0
	mod:set("camera_tilt", 0)

	if not silent and not mod._silent_reset then
		mod:echo(mod:localize("msg_tilt_reset"))
	end
end

mod.set_tripod_active = function(enabled)
	if not mod:is_enabled() then
		return
	end

	if enabled then
		if mod._dolly_active then
			mod.set_dolly_active(false)
		end
		if mod._orbit_active then
			mod.set_orbit_active(false)
		end

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
		fov_offset = mod._fov_offset or 0,
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
		if mod._tripod_active then
			mod.set_tripod_active(false)
		end
		if mod._orbit_active then
			mod.set_orbit_active(false)
		end

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

		if start_pt.fov_offset then
			mod._fov_offset = start_pt.fov_offset
		end

		mod._dolly_active = true
		mod:set("dolly_active", true)
		mod:echo(mod:localize("msg_dolly_started"))
	else
		mod._dolly_active = false
		mod._dolly_pos = nil
		mod._dolly_rot = nil
		mod._fov_offset = mod:get("camera_fov_offset") or 0
		mod:set("dolly_active", false)
		mod:echo(mod:localize("msg_dolly_stopped"))
	end
end

mod.toggle_dolly = function()
	mod.set_dolly_active(not mod._dolly_active)
end

local function _get_orbit_center()
	local target_mode = mod:get("orbit_target_mode") or "character"

	if target_mode == "character" then
		local player = Managers.player and Managers.player:local_player(1)
		local unit = player and player.player_unit
		if unit and Unit.alive(unit) then
			return Unit.world_position(unit, 1) + Vector3(0, 0, 1.1)
		end
	end

	if mod._orbit_center then
		return mod._orbit_center:unbox()
	end

	local player = Managers.player and Managers.player:local_player(1)
	local unit = player and player.player_unit
	if unit and Unit.alive(unit) then
		return Unit.world_position(unit, 1) + Vector3(0, 0, 1.1)
	end

	local pos, rot = _get_camera_transform()
	if pos and rot then
		return pos + Quaternion.forward(rot) * (mod:get("orbit_radius") or 4.0)
	end

	return nil
end

mod.orbit_set_center = function()
	if not mod:is_enabled() then
		return
	end

	local pos, rot = _get_camera_transform()

	if not pos or not rot then
		return
	end

	local world = _get_level_world()
	local center = nil

	if world then
		local physics_world = World.physics_world(world)
		if physics_world then
			local fwd = Quaternion.forward(rot)
			local hit, hit_pos = PhysicsWorld.raycast(physics_world, pos, fwd, 50, "closest", "types", "both")
			if hit then
				center = hit_pos
			end
		end
	end

	if not center then
		local player = Managers.player and Managers.player:local_player(1)
		local unit = player and player.player_unit
		if unit and Unit.alive(unit) then
			center = Unit.world_position(unit, 1) + Vector3(0, 0, 1.1)
		else
			center = pos + Quaternion.forward(rot) * (mod:get("orbit_radius") or 4.0)
		end
	end

	mod._orbit_center = Vector3Box(center)
	mod:set("orbit_target_mode", "custom")

	local offset = pos - center
	local r = math.sqrt(offset.x * offset.x + offset.y * offset.y)

	if r >= 1.5 then
		mod:set("orbit_radius", math.floor(r * 10 + 0.5) / 10)
		mod:set("orbit_height", math.floor(offset.z * 10 + 0.5) / 10)
		mod._orbit_angle = math.atan2(offset.y, offset.x)
	else
		mod._orbit_angle = 0
	end

	mod:echo(mod:localize("msg_orbit_center_set"))
end

mod.set_orbit_active = function(enabled)
	if not mod:is_enabled() then
		return
	end

	if enabled then
		if mod._tripod_active then
			mod.set_tripod_active(false)
		end
		if mod._dolly_active then
			mod.set_dolly_active(false)
		end

		local center = _get_orbit_center()

		if not center then
			mod:echo(mod:localize("msg_orbit_no_center"))
			mod:set("orbit_active", false)
			return
		end

		if not mod._orbit_center then
			mod._orbit_center = Vector3Box(center)
		end

		local pos, rot = _get_camera_transform()
		if pos and rot then
			local offset = pos - center
			local r = math.sqrt(offset.x * offset.x + offset.y * offset.y)
			if r >= 1.5 then
				mod._orbit_angle = math.atan2(offset.y, offset.x)
			else
				mod._orbit_angle = 0
			end
			mod._orbit_pos = Vector3Box(pos)
			mod._orbit_rot = QuaternionBox(rot)
		end

		mod._orbit_active = true
		mod:set("orbit_active", true)
		mod:echo(mod:localize("msg_orbit_started"))
	else
		mod._orbit_active = false
		mod._orbit_pos = nil
		mod._orbit_rot = nil
		mod:set("orbit_active", false)
		mod:echo(mod:localize("msg_orbit_stopped"))
	end
end

mod.toggle_orbit = function()
	mod.set_orbit_active(not mod._orbit_active)
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

				if pt1.fov_offset and pt2.fov_offset then
					local cur_offset = math.floor(pt1.fov_offset + (pt2.fov_offset - pt1.fov_offset) * seg_t + 0.5)
					mod._fov_offset = cur_offset
				end
			end
		end

		if motion ~= "loop" and mod._dolly_progress >= 1.0 then
			mod.set_dolly_active(false)
		end
	end

	if mod._orbit_active then
		local center = _get_orbit_center()

		if center then
			local speed = mod:get("orbit_speed") or 15.0
			local dir = (mod:get("orbit_direction") == "ccw") and 1 or -1
			local d_angle = math.rad(speed) * dir * dt
			mod._orbit_angle = ((mod._orbit_angle or 0) + d_angle) % (2 * math.pi)

			local radius = mod:get("orbit_radius") or 4.0
			local height = mod:get("orbit_height") or 0.3
			local facing = mod:get("orbit_facing") or "inward"

			local new_x = center.x + radius * math.cos(mod._orbit_angle)
			local new_y = center.y + radius * math.sin(mod._orbit_angle)
			local new_z = center.z + height

			local new_pos = Vector3(new_x, new_y, new_z)
			local look_dir

			if facing == "outward" then
				look_dir = Vector3.normalize(new_pos - center)
			else
				look_dir = Vector3.normalize(center - new_pos)
			end

			local up = (math.abs(look_dir.z) > 0.99) and Vector3.forward() or Vector3.up()
			local new_rot = Quaternion.look(look_dir, up)

			if mod._tilt_angle and mod._tilt_angle ~= 0 then
				local roll_offset = Quaternion.from_yaw_pitch_roll(0, 0, math.rad(mod._tilt_angle))
				new_rot = Quaternion.multiply(new_rot, roll_offset)
			end

			if not mod._orbit_pos then
				mod._orbit_pos = Vector3Box(new_pos)
				mod._orbit_rot = QuaternionBox(new_rot)
			else
				mod._orbit_pos:store(new_pos)
				mod._orbit_rot:store(new_rot)
			end
		end
	end

	if mod._fov_offset and mod._fov_offset ~= 0 then
		local world = _get_level_world()

		if world then
			local ff_viewport = ScriptWorld.global_free_flight_viewport and ScriptWorld.global_free_flight_viewport(world)

			if ff_viewport then
				local cam = ScriptViewport.camera(ff_viewport)

				if cam then
					Camera.set_vertical_fov(cam, math.clamp(math.rad(65 + mod._fov_offset), math.rad(10), math.rad(150)))
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
		visible_elements = {
			HudElementPhotoModeMenu = true,
		},
	})

	if not table.find_by_key(elements, "class_name", "HudElementPhotoModeMenu") then
		table.insert(elements, {
			class_name = "HudElementPhotoModeMenu",
			filename = "photo_mode/scripts/mods/photo_mode/hud/hud_element_photo_mode_menu",
			use_hud_scale = false,
			visibility_groups = {
				"alive",
				"communication_wheel",
				"in_hub_view",
				"in_view",
				HUD_VISIBILITY_GROUP,
			},
		})
	end

	return func(self, elements, visibility_groups, params)
end)

mod:hook_safe("UIHud", "_update_element_visibility", function(self)
	if self._elements and self._elements.HudElementPhotoModeMenu then
		self._currently_visible_elements.HudElementPhotoModeMenu = true
	end
end)

mod:hook("UIRenderer", "script_draw_text", function(func, self, ...)
	if self.render_settings and not self.render_settings.material_flags then
		self.render_settings.material_flags = 0
	end

	return func(self, ...)
end)

mod:hook("HumanUnitInput", "get", function(func, self, action, ...)
	if mod:is_enabled() and mod._menu_open then
		if action == "action_one_pressed" or action == "action_one_hold"
			or action == "action_two_pressed" or action == "action_two_hold"
			or action == "weapon_reload" or action == "wield" then
			return false
		end
	end

	return func(self, action, ...)
end)

mod:hook("InputManager", "pop_cursor", function(func, self, reference)
	local cursor_stack_data = self._cursor_stack_data
	if cursor_stack_data then
		if not cursor_stack_data.stack_references[reference] then
			return
		end
	end

	func(self, reference)

	if cursor_stack_data and cursor_stack_data.stack_depth < 0 then
		cursor_stack_data.stack_depth = 0
	end
end)

mod:hook("CameraHandler", "update", function(func, self, dt, t, player_orientation, input)
	if input and mod:is_enabled() and mod._menu_open and mod._camera_locked then
		input = input:null_service()
	end

	return func(self, dt, t, player_orientation, input)
end)

mod:hook("DefaultPlayerOrientation", "pre_update", function(func, self, main_t, main_dt, input, sensitivity_modifier, rotation_contraints)
	if input and mod:is_enabled() and mod._menu_open and mod._camera_locked then
		input = input:null_service()
	end

	return func(self, main_t, main_dt, input, sensitivity_modifier, rotation_contraints)
end)

mod:hook("HubPlayerOrientation", "pre_update", function(func, self, main_t, main_dt, input, sensitivity_modifier, rotation_contraints)
	if input and mod:is_enabled() and mod._menu_open and mod._camera_locked then
		input = input:null_service()
	end

	return func(self, main_t, main_dt, input, sensitivity_modifier, rotation_contraints)
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
		elseif mod._orbit_active and mod._orbit_pos and mod._orbit_rot then
			camera_data.position = mod._orbit_pos:unbox()
			camera_data.rotation = mod._orbit_rot:unbox()
		elseif mod._tilt_angle and mod._tilt_angle ~= 0 and camera_data.rotation then
			local roll_offset = Quaternion.from_yaw_pitch_roll(0, 0, math.rad(mod._tilt_angle))
			camera_data.rotation = Quaternion.multiply(camera_data.rotation, roll_offset)
		end

		if mod._fov_offset and mod._fov_offset ~= 0 and camera_data.vertical_fov then
			camera_data.vertical_fov = math.clamp(camera_data.vertical_fov + math.rad(mod._fov_offset), math.rad(10), math.rad(150))
		end
	end

	func(self, camera, shadow_cull_camera, camera_nodes, camera_data, viewport_name)
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

mod:hook("FreeFlightManager", "_update_camera", function(func, self, input, dt, camera_data)
	if input and mod:is_enabled() and mod._menu_open and mod._camera_locked then
		input = input:null_service()
	end

	func(self, input, dt, camera_data)

	if mod:is_enabled() then
		local pos = nil
		local rot = nil

		if mod._tripod_active and mod._tripod_pos and mod._tripod_rot then
			pos = mod._tripod_pos:unbox()
			rot = mod._tripod_rot:unbox()
		elseif mod._dolly_active and mod._dolly_pos and mod._dolly_rot then
			pos = mod._dolly_pos:unbox()
			rot = mod._dolly_rot:unbox()
		elseif mod._orbit_active and mod._orbit_pos and mod._orbit_rot then
			pos = mod._orbit_pos:unbox()
			rot = mod._orbit_rot:unbox()
		end

		if pos and rot then
			local world = Managers.world:world(camera_data.viewport_world_name)
			local viewport = world and ScriptWorld.global_free_flight_viewport(world)
			local cam = camera_data.frustum_freeze_camera or (viewport and ScriptViewport.camera(viewport))

			if cam then
				local pose = Matrix4x4.from_quaternion_position(rot, pos)
				ScriptCamera.set_local_pose(cam, pose)
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

mod:hook("MoodHandler", "_blend_list", function(func, self, blend_list, moods_data)
	if mod:is_enabled() and mod._screen_effects_hidden then
		return
	end

	return func(self, blend_list, moods_data)
end)

mod:hook("MoodHandler", "_spawn_particles", function(func, self, particle_name)
	if mod:is_enabled() and mod._screen_effects_hidden then
		return nil
	end

	return func(self, particle_name)
end)

mod:hook("MoodHandler", "_update_particles", function(func, self, added_moods, removing_moods, removed_moods, moods_data)
	if mod:is_enabled() and mod._screen_effects_hidden then
		local world = self._world
		local looping_particles = self._looping_particles
		if world and looping_particles then
			for mood_type, particles in pairs(looping_particles) do
				for i = #particles, 1, -1 do
					local particle_id = particles[i]
					if particle_id then
						World.destroy_particles(world, particle_id)
					end
					particles[i] = nil
				end
			end
		end

		return
	end

	return func(self, added_moods, removing_moods, removed_moods, moods_data)
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
	elseif setting_id == "orbit_active" then
		local val = mod:get("orbit_active")
		if val ~= mod._orbit_active then
			mod.set_orbit_active(val)
		end
	elseif setting_id == "slomo_scale" and mod._slomo_active and not mod._time_frozen then
		local slomo_scale = mod:get("slomo_scale") or 0.10
		_set_time_scale(slomo_scale)
	elseif setting_id == "camera_fov_offset" then
		mod._fov_offset = mod:get("camera_fov_offset") or 0
	elseif setting_id == "camera_tilt" then
		mod._tilt_angle = mod:get("camera_tilt") or 0
	elseif setting_id == "dof_focal_distance" then
		mod._dof_distance = mod:get("dof_focal_distance") or 3.0
	elseif setting_id == "lock_camera_in_menu" then
		mod._camera_locked = mod:get("lock_camera_in_menu") ~= false
	end

	if setting_id == "light_intensity" or setting_id == "light_radius"
		or setting_id == "spot_angle" or setting_id == "light_color"
		or setting_id == "light_type" or setting_id == "cast_shadows" then
		mod.update_all_lights()
	end
end

mod.on_game_state_changed = function(status, state_name)
	_cleanup_all()
end

mod.on_disabled = function(initial_call)
	_cleanup_all()
end

mod.on_unload = function(exit_game)
	_cleanup_all(not exit_game)
end
