local mod = get_mod("photo_mode")
local Shared = mod._shared

local ScriptViewport = require("scripts/foundation/utilities/script_viewport")
local ScriptWorld = require("scripts/foundation/utilities/script_world")
local MoodSettings = require("scripts/settings/camera/mood/mood_settings")

local _ensure_hud_group = Shared._ensure_hud_group
local _ensure_replay_free_cam = Shared._ensure_replay_free_cam
local _exit_free_flight = Shared._exit_free_flight
local _get_camera_transform = Shared._get_camera_transform
local _get_level_world = Shared._get_level_world
local _get_local_player = Shared._get_local_player
local _is_replay_active = Shared._is_replay_active
local _set_time_scale = Shared._set_time_scale
local _set_world_paused = Shared._set_world_paused
local _sync_replay_clock_scale = Shared._sync_replay_clock_scale
local _update_rig_perspective = Shared._update_rig_perspective

local function _guard_hotkeys_while_typing()
	local prefixes = {
		"toggle_",
		"increase_",
		"decrease_",
		"step_frame",
		"zoom_",
		"tilt_",
		"reset_fov",
		"reset_tilt",
		"place_light",
		"undo_light",
		"delete_selected_light",
		"select_prev_light",
		"select_next_light",
		"clear_lights",
		"inc_dof",
		"dec_dof",
		"dolly_",
		"orbit_set_center",
		"load_profile_",
	}
	for name, fn in pairs(mod) do
		if type(fn) == "function" and type(name) == "string" and name ~= "toggle_photo_menu" then
			for i = 1, #prefixes do
				if string.sub(name, 1, #prefixes[i]) == prefixes[i] then
					mod[name] = function(...)
						if mod._typing then
							return
						end
						return fn(...)
					end
					break
				end
			end
		end
	end
end
mod._guard_hotkeys_while_typing = _guard_hotkeys_while_typing

mod.open_photo_menu = function()
	if not mod:is_enabled() then
		return
	end

	mod._menu_open = true
	mod._reset_mouse_smoothing()
	local s = rawget(_G, "_photo_mode_session")
	if s then
		s.menu_open = true
	end
end

mod.close_photo_menu = function()
	mod._typing = false
	if mod._menu_open then
		mod._menu_open = false
		mod._menu_hovered = false
		mod._reset_mouse_smoothing()
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

mod.set_in_game_actions = function(allowed)
	if not mod:is_enabled() then
		return
	end

	mod._actions_allowed = allowed
	mod:set("allow_in_game_actions", allowed)
	if not mod._silent_reset then
		mod:echo(mod:localize(mod._actions_allowed and "msg_actions_allowed" or "msg_actions_blocked"))
	end
end

mod.toggle_in_game_actions = function()
	mod:set("allow_in_game_actions", mod:get("allow_in_game_actions") == false, true)
end

mod.set_freeze_time = function(enabled)
	if not mod:is_enabled() then
		return
	end

	mod._time_frozen = enabled
	mod:set("freeze_time", enabled)

	local PLAY = _is_replay_active()
	if PLAY then
		PLAY.paused = enabled
		_sync_replay_clock_scale()
	else
		if mod._time_frozen then
			_set_world_paused(true)
			_set_time_scale(0.00001)
		else
			_set_world_paused(false)

			if mod._slomo_active then
				local slomo_scale = mod:get("slomo_scale") or 0.10
				_set_time_scale(slomo_scale)
			else
				_set_time_scale(1.0)
			end
		end
	end

	if not mod._silent_reset then
		mod:echo(mod:localize(enabled and "msg_time_frozen" or "msg_time_resumed"))
	end
end

mod.toggle_freeze_time = function()
	mod:set("freeze_time", not mod:get("freeze_time"), true)
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

	mod._step_frames_remaining = (mod._step_frames_remaining or 0) + 2

	_set_world_paused(false)
	_set_time_scale(1.0)

	local PLAY = _is_replay_active()
	if PLAY then
		PLAY.paused = false
		_sync_replay_clock_scale()
	end
end

mod.set_slomo_active = function(enabled)
	if not mod:is_enabled() then
		return
	end

	mod._slomo_active = enabled
	mod:set("slomo_active", enabled)

	local PLAY = _is_replay_active()
	if PLAY then
		if enabled and not mod._time_frozen then
			PLAY.paused = false
		end
		_sync_replay_clock_scale()
	else
		if not mod._time_frozen then
			if mod._slomo_active then
				local slomo_scale = mod:get("slomo_scale") or 0.10
				_set_time_scale(slomo_scale)
			else
				_set_time_scale(1.0)
			end
		end
	end

	if not mod._silent_reset then
		mod:echo(mod:localize(mod._slomo_active and "msg_slomo_on" or "msg_slomo_off"))
	end
end

mod.toggle_slomo = function()
	mod:set("slomo_active", not mod:get("slomo_active"), true)
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
		_sync_replay_clock_scale()
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
		_sync_replay_clock_scale()
	end

	mod:echo(mod:localize("msg_slomo_speed") .. ": " .. string.format("%.2fx", new_speed))
end

mod._in_sync_hud = false

mod.set_hide_hud = function(enabled)
	if not mod:is_enabled() then
		return
	end

	mod._hud_hidden = enabled
	mod:set("hide_hud", enabled)
	_ensure_hud_group()

	if not mod._in_sync_hud then
		mod._in_sync_hud = true
		local replays = get_mod("Replays")
		local RUI = replays and replays.rec and replays.rec.ui
		if RUI then
			RUI.hud_hidden = enabled
		end
		mod._in_sync_hud = false
	end

	local hud = Managers.ui and Managers.ui._hud
	if hud then
		hud._current_group_name = nil
		if hud._update_element_visibility then
			hud:_update_element_visibility()
		end
	end

	if not mod._silent_reset then
		mod:echo(mod:localize(mod._hud_hidden and "msg_hud_hidden" or "msg_hud_shown"))
	end
end

mod.toggle_hide_hud = function()
	mod:set("hide_hud", not mod:get("hide_hud"), true)
end

mod.set_hide_chat = function(enabled)
	if not mod:is_enabled() then
		return
	end

	mod._chat_hidden = enabled
	mod:set("hide_chat", enabled)
	if not mod._silent_reset then
		mod:echo(mod:localize(mod._chat_hidden and "msg_chat_hidden" or "msg_chat_shown"))
	end
end

mod.toggle_hide_chat = function()
	mod:set("hide_chat", not mod:get("hide_chat"), true)
end

mod._set_arms_visibility = function(visible)
	local player = _get_local_player()
	local unit = player and player.player_unit
	local first_person = unit and ScriptUnit.has_extension(unit, "first_person_system")
	local fp_unit = first_person and first_person:first_person_unit()

	if not fp_unit or not Unit.alive(fp_unit) then
		return false
	end

	if mod._arms_snapshot_unit and mod._arms_snapshot_unit ~= fp_unit then
		mod._arms_snapshot_unit = nil
	end

	if visible then
		if mod._arms_snapshot_unit then
			Unit.restore_visibility_snapshot({ mod._arms_snapshot_unit })
			mod._arms_snapshot_unit = nil
		end
	else
		if not mod._arms_snapshot_unit then
			Unit.take_visibility_snapshot({ fp_unit })
			mod._arms_snapshot_unit = fp_unit
		end
		Unit.set_unit_visibility(fp_unit, false, true)
	end

	return true
end

mod.set_hide_arms = function(enabled)
	if not mod:is_enabled() then
		return
	end

	mod._arms_pending = false

	if mod._set_arms_visibility(not enabled) then
		mod._arms_hidden = enabled
		mod:set("hide_arms", enabled)

		if not mod._silent_reset then
			mod:echo(mod:localize(enabled and "msg_arms_hidden" or "msg_arms_shown"))
		end
	elseif enabled then
		mod._arms_pending = true
	end
end

mod.toggle_hide_arms = function()
	mod:set("hide_arms", not mod:get("hide_arms"), true)
end

mod.set_hide_screen_effects = function(enabled)
	if not mod:is_enabled() then
		return
	end

	mod._screen_effects_hidden = enabled
	mod:set("hide_screen_effects", enabled)

	local player = _get_local_player()
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
	mod:set("hide_screen_effects", not mod:get("hide_screen_effects"), true)
end

mod.toggle_hide_outlines = function()
	mod:set("hide_outlines", not mod:get("hide_outlines"), true)
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

mod.toggle_lock_fov = function()
	if not mod:is_enabled() then
		return
	end
	mod:set("lock_fov", not mod:get("lock_fov"), true)
end

mod.toggle_lock_character = function()
	if not mod:is_enabled() then
		return
	end
	mod:set("lock_character", not mod:get("lock_character"), true)
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
		local pos, rot = _get_camera_transform()

		_ensure_replay_free_cam(pos, rot)

		if mod._dolly_active then
			mod.set_dolly_active(false)
		end
		if mod._orbit_active then
			mod.set_orbit_active(false)
		end

		if not pos or not rot then
			pos, rot = _get_camera_transform()
		end

		if not pos or not rot then
			mod:set("tripod_active", false)
			return
		end

		mod._tripod_pos = Vector3Box(pos)
		mod._tripod_rot = QuaternionBox(rot)
		mod._tripod_active = true
		mod:set("tripod_active", true)
		_exit_free_flight()
		_update_rig_perspective()
		if not mod._silent_reset then
			mod:echo(mod:localize("msg_tripod_on"))
		end
	else
		mod._tripod_active = false
		mod._tripod_pos = nil
		mod._tripod_rot = nil
		mod:set("tripod_active", false)
		_update_rig_perspective()
		if not mod._silent_reset then
			mod:echo(mod:localize("msg_tripod_off"))
		end
	end
end

mod.toggle_tripod = function()
	mod:set("tripod_active", not mod:get("tripod_active"), true)
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
		if not mod._silent_reset then
			mod:echo(mod:localize("msg_dof_on") .. " (Focus: " .. string.format("%.1fm", dist) .. ")")
		end
	else
		if mod._original_render_dof == "false" and Application.set_render_setting then
			Application.set_render_setting("dof_enabled", "false")
			mod._original_render_dof = nil
		end

		if not mod._silent_reset then
			mod:echo(mod:localize("msg_dof_off"))
		end
	end
end

mod.toggle_dof = function()
	mod:set("dof_active", not mod:get("dof_active"), true)
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
	mod:set("dof_focal_distance", new_dist, true)
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
	mod:set("dof_focal_distance", new_dist, true)
	mod:echo(mod:localize("msg_dof_distance") .. ": " .. string.format("%.1fm", new_dist))
end

mod.set_mouse_smoothing = function(enabled)
	if not mod:is_enabled() then
		return
	end

	mod._mouse_smoothing = enabled
	mod:set("mouse_smoothing", enabled)

	if not enabled then
		mod._reset_mouse_smoothing()
	end

	if not mod._silent_reset then
		mod:echo(mod:localize(enabled and "msg_mouse_smoothing_on" or "msg_mouse_smoothing_off"))
	end
end

mod.toggle_mouse_smoothing = function()
	mod:set("mouse_smoothing", not mod:get("mouse_smoothing"), true)
end

mod.set_move_speed_enabled = function(enabled)
	if not mod:is_enabled() then
		return
	end

	mod._move_speed_enabled = enabled
	mod:set("free_flight_move_speed_enabled", enabled)

	if not mod._silent_reset then
		mod:echo(mod:localize(enabled and "msg_move_speed_on" or "msg_move_speed_off"))
	end
end

mod.toggle_move_speed = function()
	mod:set("free_flight_move_speed_enabled", not mod:get("free_flight_move_speed_enabled"), true)
end

Shared._guard_hotkeys_while_typing = _guard_hotkeys_while_typing
