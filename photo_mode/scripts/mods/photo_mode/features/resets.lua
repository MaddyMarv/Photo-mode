local mod = get_mod("photo_mode")
local Shared = mod._shared

local ScriptViewport = require("scripts/foundation/utilities/script_viewport")
local ScriptWorld = require("scripts/foundation/utilities/script_world")

local _apply_outlines_visibility = Shared._apply_outlines_visibility
local _get_level_world = Shared._get_level_world

mod.reset_tab_camera = function(silent)
	if not mod:is_enabled() then
		return
	end

	local was_silent = mod._silent_reset
	mod._silent_reset = true
	mod._fov_offset = 0
	mod:set("camera_fov_offset", 0)
	mod._lock_fov = false
	mod:set("lock_fov", false)
	mod._lock_character = false
	mod:set("lock_character", false)

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
	mod:set("dof_focal_distance", 3.0)
	mod:set("dof_focal_region", 4.0)
	mod:set("dof_blur_amount", 1.0)

	if mod._mouse_smoothing then
		mod.set_mouse_smoothing(false)
	end
	mod._mouse_smoothing_amount = 0.65
	mod:set("mouse_smoothing_amount", 0.65)
	mod._mouse_smoothing_speed = 1.0
	mod:set("mouse_smoothing_speed", 1.0)
	if mod._move_speed_enabled then
		mod.set_move_speed_enabled(false)
	end
	mod._move_speed = 1.0
	mod:set("free_flight_move_speed", 1.0)
	mod._reset_mouse_smoothing()

	if not was_silent then
		mod._silent_reset = nil
	end

	if not silent and not was_silent then
		mod:echo(mod:localize("msg_reset_tab_camera"))
	end
end

mod.reset_tab_time_hud = function(silent)
	if not mod:is_enabled() then
		return
	end

	local was_silent = mod._silent_reset
	mod._silent_reset = true
	if mod._time_frozen then
		mod.set_freeze_time(false)
	end
	if mod._slomo_active then
		mod.set_slomo_active(false)
	end
	mod:set("slomo_scale", 0.10)

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
	if mod._hide_outlines then
		mod._hide_outlines = false
		mod:set("hide_outlines", false)
		_apply_outlines_visibility(true)
	end

	if not was_silent then
		mod._silent_reset = nil
	end

	if not silent and not was_silent then
		mod:echo(mod:localize("msg_reset_tab_time_hud"))
	end
end

mod.reset_tab_lighting = function(silent)
	if not mod:is_enabled() then
		return
	end

	local was_silent = mod._silent_reset
	mod._silent_reset = true

	mod._silent_clear = true
	mod.clear_lights()
	mod._silent_clear = nil

	if mod._lantern_active then
		mod.set_lantern_active(false)
	end
	if mod._blackout_active then
		mod.restore_all_extinguished_lights(true)
		mod._blackout_active = false
	end

	mod:set("map_lights", true)
	mod:set("blackout_active", false)
	mod:set("exposure_compensation", 0)
	mod:set("light_type", "spot")
	mod:set("cast_shadows", true)
	mod:set("light_intensity", 100)
	mod:set("light_radius", 20)
	mod:set("spot_angle", 45)
	mod:set("light_color", { 255, 255, 245, 220 })

	if mod.update_all_lights then
		mod.update_all_lights()
	end

	if not was_silent then
		mod._silent_reset = nil
	end

	if not silent and not was_silent then
		mod:echo(mod:localize("msg_reset_tab_lighting"))
	end
end

mod.reset_tab_rigs = function(silent)
	if not mod:is_enabled() then
		return
	end

	local was_silent = mod._silent_reset
	mod._silent_reset = true
	if mod._tripod_active then
		mod.set_tripod_active(false)
	end
	if mod._dolly_active then
		mod.set_dolly_active(false)
	end
	table.clear(mod._dolly_points)
	mod._selected_dolly_index = nil
	mod:set("dolly_duration", 8.0)
	mod:set("dolly_motion", "smooth")
	mod:set("dolly_time_inbetween", 2.0)

	if mod._orbit_active then
		mod.set_orbit_active(false)
	end
	mod._orbit_paused = true
	mod._orbit_center = nil
	mod:set("orbit_paused", true)

	mod:set("orbit_target_mode", "follow")
	mod:set("orbit_follow_rotation", true)
	mod:set("orbit_facing", "inward")
	mod:set("orbit_direction", "cw")
	mod:set("orbit_speed", 15)
	mod:set("orbit_radius", 4.0)
	mod:set("orbit_height", 0.3)
	mod:set("orbit_side_offset", 0.0)
	mod:set("orbit_angle", 0)
	mod:set("orbit_pitch", 0)
	mod._orbit_pitch = 0
	mod:set("orbit_dynamic_give", true)
	mod:set("orbit_slide_give", 0.5)
	mod:set("orbit_pitch_give", 0.35)

	if not was_silent then
		mod._silent_reset = nil
	end

	if not silent and not was_silent then
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

	mod._silent_reset = true
	mod.reset_tab_camera(true)
	mod.reset_tab_time_hud(true)
	mod.reset_tab_lighting(true)
	mod.reset_tab_rigs(true)
	mod._silent_reset = nil

	mod:echo(mod:localize("msg_reset_all"))
end
