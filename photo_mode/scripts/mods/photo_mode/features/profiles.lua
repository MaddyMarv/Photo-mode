local mod = get_mod("photo_mode")

local PROFILE_SLOTS = 5
local PROFILE_KEYS = {
	{ "show_chat_messages", true },
	{ "lock_camera_in_menu", true },
	{ "allow_in_game_actions", true },
	{ "camera_fov_offset", 0 },
	{ "lock_fov", false },
	{ "camera_tilt", 0 },
	{ "dof_focal_distance", 3.0 },
	{ "dof_focal_region", 4.0 },
	{ "dof_blur_amount", 1.0 },
	{ "mouse_smoothing_amount", 0.65 },
	{ "mouse_smoothing_speed", 1.0 },
	{ "free_flight_move_speed", 1.0 },
	{ "hide_chat", false },
	{ "hide_arms", false },
	{ "hide_screen_effects", false },
	{ "hide_outlines", false },
	{ "light_type", "spot" },
	{ "light_color", { 255, 255, 245, 220 } },
	{ "light_intensity", 100 },
	{ "light_radius", 20 },
	{ "spot_angle", 45 },
	{ "cast_shadows", true },
	{ "exposure_compensation", 0 },
	{ "slomo_scale", 0.10 },
	{ "dolly_duration", 8.0 },
	{ "dolly_time_inbetween", 2.0 },
	{ "dolly_motion", "smooth" },
	{ "orbit_dynamic_give", true },
	{ "orbit_slide_give", 0.5 },
	{ "orbit_pitch_give", 0.35 },
	{ "orbit_target_mode", "follow" },
	{ "orbit_facing", "inward" },
	{ "orbit_speed", 15 },
	{ "orbit_angle", 0 },
	{ "orbit_radius", 4.0 },
	{ "orbit_height", 0.3 },
	{ "orbit_pitch", 0 },
	{ "orbit_side_offset", 0.0 },
	{ "orbit_direction", "cw" },
	{ "map_lights", true },
	{ "lantern_active", false },
	{ "dof_active", false },
	{ "mouse_smoothing", false },
	{ "free_flight_move_speed_enabled", false },
	{ "lock_character", false },
	{ "hide_hud", false },
	{ "slomo_active", false },
	{ "tripod_active", false },
	{ "dolly_active", false },
	{ "orbit_active", false },
	{ "orbit_paused", true },
}

mod.profile_name = function(slot)
	local name = mod:get("profile_" .. slot .. "_name")
	if type(name) ~= "string" or name == "" then
		return "Profile " .. slot
	end
	return name
end

mod.profile_exists = function(slot)
	local profiles = mod:get("profiles")
	return profiles ~= nil and profiles[tostring(slot)] ~= nil
end

mod.save_profile = function(slot)
	if not mod:is_enabled() then
		return
	end

	local profiles = mod:get("profiles") or {}
	local values = {}
	for i = 1, #PROFILE_KEYS do
		local key, default = PROFILE_KEYS[i][1], PROFILE_KEYS[i][2]
		local v = mod:get(key)
		if v == nil then
			v = default
		end
		values[key] = v
	end
	profiles[tostring(slot)] = values
	mod:set("profiles", profiles)
	mod:set("active_profile", slot)

	mod:echo(mod:localize("msg_profile_saved") .. ": " .. mod.profile_name(slot))
end

mod.delete_profile = function(slot)
	if not mod:is_enabled() then
		return
	end

	local name = mod.profile_name(slot)
	local profiles = mod:get("profiles")
	if profiles and profiles[tostring(slot)] then
		profiles[tostring(slot)] = nil
		mod:set("profiles", profiles)
	end
	mod:set("profile_" .. slot .. "_name", "", true)

	mod:echo(mod:localize("msg_profile_deleted") .. ": " .. name)
end

mod.load_profile = function(slot)
	if not mod:is_enabled() then
		return
	end

	local profiles = mod:get("profiles")
	local values = profiles and profiles[tostring(slot)]
	if not values then
		mod:echo(mod:localize("msg_profile_empty") .. ": " .. mod.profile_name(slot))
		return
	end

	if values.orbit_active and values.orbit_target_mode == "custom" then
		mod._orbit_center = nil
		mod._orbit_angle = math.rad(values.orbit_angle or 0)
	end

	if values.orbit_target_mode then
		mod:set("orbit_follow_rotation", values.orbit_target_mode == "follow", true)
	end

	local was_silent = mod._silent_reset
	mod._silent_reset = true
	for i = 1, #PROFILE_KEYS do
		local key = PROFILE_KEYS[i][1]
		local v = values[key]
		if v ~= nil then
			mod:set(key, v, true)
		end
	end
	mod._silent_reset = was_silent
	mod:set("active_profile", slot)

	mod:echo(mod:localize("msg_profile_loaded") .. ": " .. mod.profile_name(slot))
end

for slot = 1, PROFILE_SLOTS do
	mod["load_profile_" .. slot] = function()
		mod.load_profile(slot)
	end
end
