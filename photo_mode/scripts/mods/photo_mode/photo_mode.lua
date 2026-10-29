local mod = get_mod("photo_mode")

local ScriptCamera = require("scripts/foundation/utilities/script_camera")
local ScriptViewport = require("scripts/foundation/utilities/script_viewport")
local ScriptWorld = require("scripts/foundation/utilities/script_world")
local MoodSettings = require("scripts/settings/camera/mood/mood_settings")
local LightControllerUtilities = require("core/scripts/common/light_controller_utilities")

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
mod._actions_allowed = mod:get("allow_in_game_actions") ~= false
mod._menu_hovered = false
mod:add_require_path("photo_mode/scripts/mods/photo_mode/hud/hud_element_photo_mode_menu")

mod._time_frozen = false
mod._slomo_active = false
mod._hud_hidden = false
mod._chat_hidden = false
mod._arms_hidden = false
mod._screen_effects_hidden = false
mod._step_frames_remaining = nil

mod._placed_lights = {}
mod._selected_light_index = nil
mod._lantern_active = false
mod._lantern_unit = nil
mod._blackout_active = false
mod._extinguished_units = {}
mod._exposure_was_applied = false

mod._fov_offset = mod:get("camera_fov_offset") or 0
mod._tilt_angle = mod:get("camera_tilt") or 0
mod._dof_active = false
mod._dof_distance = mod:get("dof_focal_distance") or 3.0
mod._dof_was_applied = false
mod._original_render_dof = nil
mod._mouse_smoothing = mod:get("mouse_smoothing") or false
mod._mouse_smoothing_amount = mod:get("mouse_smoothing_amount") or 0.65
mod._mouse_smoothing_speed = mod:get("mouse_smoothing_speed") or 1.0

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
mod._selected_dolly_index = nil

mod._orbit_active = false
mod._orbit_pos = nil
mod._orbit_rot = nil
mod._orbit_center = nil
mod._orbit_angle = 0
mod._orbit_height = 0
mod._orbit_paused = false

local HUD_VISIBILITY_GROUP = "photo_mode_hide_hud"

local function _get_level_world()
	if Managers.world and Managers.world:has_world("level_world") then
		return Managers.world:world("level_world")
	end

	local replays = get_mod("Replays")
	local PLAY = replays and replays.rec and replays.rec.playback
	if PLAY and PLAY.viewport_world then
		return PLAY.viewport_world
	end

	return nil
end

local function _is_replay_active()
	local replays = get_mod("Replays")
	local PLAY = replays and replays.rec and replays.rec.playback
	if PLAY and PLAY.is_active and PLAY.is_active() then
		return PLAY
	end
	return nil
end

local function _get_spectated_puppet_unit()
	local replays = get_mod("Replays")
	local P = replays and replays.rec and replays.rec.puppets
	local PLAY = replays and replays.rec and replays.rec.playback
	if not P or not PLAY then
		return nil
	end

	local eid = PLAY.follow_eid or (PLAY.pov and PLAY.pov.eid)
	if eid and P.puppets and P.puppets[eid] then
		local p = P.puppets[eid]
		local unit = p.unit or (type(p) == "userdata" and p)
		if unit and Unit.alive(unit) then
			return unit
		end
	end

	local SP = replays.rec.spectate
	if SP and eid and SP.unit_for then
		local unit = SP.unit_for(eid)
		if unit and Unit.alive(unit) then
			return unit
		end
	end

	if PLAY.resolve_local_unit then
		local runit = PLAY.resolve_local_unit()
		if runit and Unit.alive(runit) then
			return runit
		end
	end

	if PLAY.local_unit and Unit.alive(PLAY.local_unit) then
		return PLAY.local_unit
	end

	return nil
end

local function _ensure_replay_free_cam(seed_pos, seed_rot)
	local PLAY = _is_replay_active()
	if PLAY and PLAY.pov_mode ~= "free" and PLAY.set_pov then
		PLAY.set_pov("free")
		if seed_pos and seed_rot and PLAY.viewport_world then
			local viewport = ScriptWorld.global_free_flight_viewport(PLAY.viewport_world)
			if viewport then
				local cam = ScriptViewport.camera(viewport)
				if cam then
					local pose = Matrix4x4.from_quaternion_position(seed_rot, seed_pos)
					ScriptCamera.set_local_pose(cam, pose)
				end
			end
		end
	end
end

local function _ensure_free_flight_active(seed_pos, seed_rot)
	local PLAY = _is_replay_active()
	if PLAY then
		_ensure_replay_free_cam(seed_pos, seed_rot)
		return true
	end

	local ff = Managers.free_flight
	if ff then
		if not ff:is_in_free_flight() then
			local cam_ff = get_mod("camera_freeflight")
			if cam_ff and cam_ff.is_in_free_flight and not cam_ff:is_in_free_flight() and cam_ff.toggle_freeflight then
				cam_ff:toggle_freeflight()
			end

			if not ff:is_in_free_flight() and ff._enter_global_free_flight and ff._free_flight_cameras and ff._free_flight_cameras.global then
				ff:_enter_global_free_flight(ff._free_flight_cameras.global)
			end
		end

		return ff:is_in_free_flight()
	end

	return false
end

local function _sync_replay_clock_scale()
	local PLAY = _is_replay_active()
	if PLAY and PLAY.set_clock_scale and PLAY.wanted_clock_scale then
		PLAY.set_clock_scale(PLAY.wanted_clock_scale())
	end
end


local function _get_own_character_unit()
	local player = Managers.player and Managers.player:local_player(1)
	local unit = player and player.player_unit
	if not unit or not Unit.alive(unit) then
		local PLAY = _is_replay_active()
		if PLAY then
			unit = PLAY.local_unit or (PLAY.resolve_local_unit and PLAY.resolve_local_unit())
		end
	end
	return (unit and Unit.alive(unit)) and unit or nil
end

local function _is_camera_rig_active()
	return (mod._tripod_active or mod._dolly_active or mod._orbit_active) == true
end

local function _update_rig_perspective(force_enable)
	local should_be_3p = force_enable
	if should_be_3p == nil then
		should_be_3p = _is_camera_rig_active()
	end

	local perspectives = get_mod("Perspectives")

	if should_be_3p then
		if _is_camera_rig_active() and not mod._rig_forced_3p then
			if perspectives and perspectives:is_enabled() and perspectives.autoswitch then
				perspectives.autoswitch("photo_mode", true, true)
			end

			local unit = _get_own_character_unit()
			if unit then
				local fp_ext = ScriptUnit.has_extension(unit, "first_person_system")
				if fp_ext then
					mod._rig_prev_force_3p = fp_ext._force_third_person_mode
					fp_ext._force_third_person_mode = true

					local t = Managers.time and Managers.time:time("gameplay") or 0
					if fp_ext._update_first_person_mode then
						fp_ext._show_1p_equipment, fp_ext._wants_1p_camera = fp_ext:_update_first_person_mode(t)
					end
				end

				local vl_ext = ScriptUnit.has_extension(unit, "visual_loadout_system")
				if vl_ext and vl_ext.force_update_item_visibility then
					vl_ext:force_update_item_visibility()
				end
			end

			mod._rig_forced_3p = true
		end
	else
		if mod._rig_forced_3p then
			if perspectives and perspectives:is_enabled() and perspectives.clear_reason then
				perspectives.clear_reason("photo_mode")
			end

			local unit = _get_own_character_unit()
			if unit then
				local fp_ext = ScriptUnit.has_extension(unit, "first_person_system")
				if fp_ext then
					local restore_3p = false
					if perspectives and perspectives:is_enabled() and perspectives.is_requesting_third_person then
						restore_3p = perspectives.is_requesting_third_person()
					elseif mod._rig_prev_force_3p ~= nil then
						restore_3p = mod._rig_prev_force_3p
					end

					if not restore_3p and Managers.state and Managers.state.mission and Managers.state.mission.force_third_person_mode then
						restore_3p = Managers.state.mission:force_third_person_mode() or false
					end

					fp_ext._force_third_person_mode = restore_3p

					local t = Managers.time and Managers.time:time("gameplay") or 0
					if fp_ext._update_first_person_mode then
						fp_ext._show_1p_equipment, fp_ext._wants_1p_camera = fp_ext:_update_first_person_mode(t)
					end
				end

				local vl_ext = ScriptUnit.has_extension(unit, "visual_loadout_system")
				if vl_ext and vl_ext.force_update_item_visibility then
					vl_ext:force_update_item_visibility()
				end
			end

			mod._rig_forced_3p = nil
			mod._rig_prev_force_3p = nil
		end
	end
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

	local PLAY = _is_replay_active()
	if PLAY and PLAY.pov_mode ~= "free" then
		local player_manager = Managers.player
		local player = player_manager and (player_manager.local_player_safe and player_manager:local_player_safe(1) or player_manager:local_player(1))
		local camera_manager = Managers.state.camera
		local viewport_name = player and player.viewport_name

		if viewport_name and camera_manager and camera_manager:has_viewport(viewport_name) then
			local pos = camera_manager:camera_position(viewport_name)
			local rot = camera_manager:camera_rotation(viewport_name)
			if pos and rot and Vector3.length_squared(pos) > 1 then
				return pos, rot
			end
		end

		if PLAY.pov and PLAY.pov.x then
			local pos = Vector3(PLAY.pov.x, PLAY.pov.y, PLAY.pov.z)
			local rot = Quaternion.from_yaw_pitch_roll(PLAY.pov.yaw or 0, PLAY.pov.pitch or 0, 0)
			return pos, rot
		end

		local spectated_unit = _get_spectated_puppet_unit()
		if spectated_unit and Unit.alive(spectated_unit) then
			local pos = Unit.world_position(spectated_unit, 1) + Vector3(0, 0, 1.6)
			local rot = Unit.world_rotation(spectated_unit, 1)
			return pos, rot
		end
	end

	local world = _get_level_world()

	if world then
		local ff_viewport = ScriptWorld.global_free_flight_viewport and ScriptWorld.global_free_flight_viewport(world)

		if ff_viewport then
			local cam = ScriptViewport.camera(ff_viewport)

			if cam then
				local pos = Camera.world_position(cam)
				local rot = Camera.world_rotation(cam)
				if pos and rot and Vector3.length_squared(pos) > 1 then
					return pos, rot
				end
			end
		end
	end

	local player_manager = Managers.player
	local player = player_manager and (player_manager.local_player_safe and player_manager:local_player_safe(1) or player_manager:local_player(1))

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

local function _ensure_hud_group()
	local hud = Managers.ui and Managers.ui._hud
	local visibility_groups = hud and hud._visibility_groups

	if visibility_groups then
		local found_group = nil

		for i = #visibility_groups, 1, -1 do
			if visibility_groups[i].name == HUD_VISIBILITY_GROUP then
				found_group = visibility_groups[i]
				table.remove(visibility_groups, i)
			end
		end

		if not found_group then
			found_group = {
				name = HUD_VISIBILITY_GROUP,
			}
		end

		found_group.validation_function = function(h)
			local m = get_mod("photo_mode")
			return m and m:is_enabled() and m._hud_hidden
		end
		found_group.visible_elements = {
			HudElementPhotoModeMenu = true,
			HudElementReplaysMenu = true,
		}

		table.insert(visibility_groups, 1, found_group)

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
	local PLAY = _is_replay_active()
	if PLAY then
		PLAY.paused = false
	end
	_set_world_paused(false)
	_set_time_scale(1.0)
	_sync_replay_clock_scale()
end

local function _reset_hud_state()
	mod._hud_hidden = false
	mod._chat_hidden = false

	local replays = get_mod("Replays")
	local RUI = replays and replays.rec and replays.rec.ui
	if RUI then
		RUI.hud_hidden = false
	end

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
		if hud._update_element_visibility then
			hud:_update_element_visibility()
		end
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

local function _cleanup_all()
	mod.close_photo_menu()
	_reset_time_state()
	_reset_hud_state()
	_reset_camera_state()
	_destroy_lantern()
	if mod._blackout_active then
		mod.restore_all_extinguished_lights(true)
		mod._blackout_active = false
	end
	mod:set("blackout_active", false, true)
	mod:set("exposure_compensation", 0, true)
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
	mod._selected_dolly_index = nil
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

	_update_rig_perspective(false)
	mod._reset_mouse_smoothing()
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

	if mod._mouse_smoothing then
		mod.set_mouse_smoothing(false)
	end
	mod._mouse_smoothing_amount = 0.65
	mod:set("mouse_smoothing_amount", 0.65, true)
	mod._mouse_smoothing_speed = 1.0
	mod:set("mouse_smoothing_speed", 1.0, true)
	mod._reset_mouse_smoothing()
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
	if mod._blackout_active then
		mod.restore_all_extinguished_lights(true)
		mod._blackout_active = false
	end
	mod._silent_reset = nil

	mod:set("blackout_active", false, true)
	mod:set("exposure_compensation", 0, true)
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
	mod._selected_dolly_index = nil
	mod:set("dolly_duration", 8.0, true)
	mod:set("dolly_motion", "smooth", true)
	mod:set("dolly_time_inbetween", 2.0, true)

	if mod._orbit_active then
		mod.set_orbit_active(false)
	end
	mod._orbit_paused = false
	mod:set("orbit_paused", false, true)
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
	mod._reset_mouse_smoothing()
	local s = rawget(_G, "_photo_mode_session")
	if s then
		s.menu_open = true
	end
end

mod.close_photo_menu = function()
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
	mod:set("allow_in_game_actions", allowed, true)
	mod:echo(mod:localize(mod._actions_allowed and "msg_actions_allowed" or "msg_actions_blocked"))
end

mod.toggle_in_game_actions = function()
	mod.set_in_game_actions(not (mod._actions_allowed ~= false))
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

	mod:echo(mod:localize(enabled and "msg_time_frozen" or "msg_time_resumed"))
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

	mod:echo(mod:localize(mod._slomo_active and "msg_slomo_on" or "msg_slomo_off"))
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

local _in_sync_hud = false

mod.set_hide_hud = function(enabled)
	if not mod:is_enabled() then
		return
	end

	mod._hud_hidden = enabled
	mod:set("hide_hud", enabled)
	_ensure_hud_group()

	if not _in_sync_hud then
		_in_sync_hud = true
		local replays = get_mod("Replays")
		local RUI = replays and replays.rec and replays.rec.ui
		if RUI then
			RUI.hud_hidden = enabled
		end
		_in_sync_hud = false
	end

	local hud = Managers.ui and Managers.ui._hud
	if hud then
		hud._current_group_name = nil
		if hud._update_element_visibility then
			hud:_update_element_visibility()
		end
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
		_update_rig_perspective()
		mod:echo(mod:localize("msg_tripod_on"))
	else
		mod._tripod_active = false
		mod._tripod_pos = nil
		mod._tripod_rot = nil
		mod:set("tripod_active", false)
		_update_rig_perspective()
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
	mod._selected_dolly_index = #mod._dolly_points

	mod:echo(mod:localize("msg_dolly_point_added") ..
	": Point " .. tostring(name) .. " (" .. tostring(#mod._dolly_points) .. " total)")
end

mod.dolly_clear_points = function()
	if not mod:is_enabled() then
		return
	end

	table.clear(mod._dolly_points)
	mod._selected_dolly_index = nil
	mod.set_dolly_active(false)
	mod:echo(mod:localize("msg_dolly_points_cleared"))
end

mod.dolly_undo_point = function()
	if not mod:is_enabled() then
		return
	end

	local count = #mod._dolly_points
	if count == 0 then
		mod:echo(mod:localize("msg_dolly_no_points"))
		return
	end

	local removed_pt = table.remove(mod._dolly_points, count)

	local remaining = #mod._dolly_points
	if remaining == 0 then
		mod._selected_dolly_index = nil
		mod.set_dolly_active(false)
	else
		mod._selected_dolly_index = math.clamp(mod._selected_dolly_index or remaining, 1, remaining)
		if mod._dolly_active then
			if remaining < 2 then
				mod.set_dolly_active(false)
			else
				mod._dolly_dists, mod._dolly_total_dist = _calculate_dolly_distances()
			end
		end
	end

	local pt_name = removed_pt and removed_pt.name or tostring(count)
	mod:echo(mod:localize("msg_dolly_point_undone") .. ": Point " .. tostring(pt_name) .. " (" .. tostring(remaining) .. " left)")
end

mod.undo_dolly_point = mod.dolly_undo_point

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

mod.select_dolly_point = function(index, silent)
	local count = #mod._dolly_points
	if count == 0 then
		mod._selected_dolly_index = nil
		return
	end

	index = math.clamp(index or count, 1, count)
	mod._selected_dolly_index = index

	local pt = mod._dolly_points[index]
	if not silent and pt then
		mod:echo(mod:localize("msg_dolly_point_selected") .. ": Point " .. tostring(pt.name) .. " (" .. tostring(index) .. " of " .. tostring(count) .. ")")
	end
end

mod.select_prev_dolly_point = function()
	local count = #mod._dolly_points
	if count == 0 then
		return
	end

	local cur = mod._selected_dolly_index or count
	local target = cur - 1
	if target < 1 then
		target = count
	end

	mod.select_dolly_point(target)
end

mod.select_next_dolly_point = function()
	local count = #mod._dolly_points
	if count == 0 then
		return
	end

	local cur = mod._selected_dolly_index or count
	local target = cur + 1
	if target > count then
		target = 1
	end

	mod.select_dolly_point(target)
end

mod.delete_selected_dolly_point = function()
	if not mod:is_enabled() then
		return
	end

	local count = #mod._dolly_points
	if count == 0 then
		mod:echo(mod:localize("msg_dolly_no_points"))
		return
	end

	local sel_idx = math.clamp(mod._selected_dolly_index or count, 1, count)
	local removed_pt = table.remove(mod._dolly_points, sel_idx)

	local remaining = #mod._dolly_points
	if remaining == 0 then
		mod._selected_dolly_index = nil
		mod.set_dolly_active(false)
	else
		mod._selected_dolly_index = math.clamp(sel_idx, 1, remaining)
		if mod._dolly_active then
			if remaining < 2 then
				mod.set_dolly_active(false)
			else
				mod._dolly_dists, mod._dolly_total_dist = _calculate_dolly_distances()
			end
		end
	end

	local pt_name = removed_pt and removed_pt.name or tostring(sel_idx)
	mod:echo(mod:localize("msg_dolly_point_deleted") .. ": Point " .. tostring(pt_name) .. " (" .. tostring(remaining) .. " left)")
end

mod.dolly_goto_point = function(index)
	if not mod:is_enabled() then
		return
	end

	local count = #mod._dolly_points
	if count == 0 then
		mod:echo(mod:localize("msg_dolly_no_points"))
		return
	end

	index = math.clamp(index or mod._selected_dolly_index or 1, 1, count)
	mod._selected_dolly_index = index

	local pt = mod._dolly_points[index]
	if not pt then
		return
	end

	if mod._dolly_active then
		mod.set_dolly_active(false)
	end
	if mod._tripod_active then
		mod.set_tripod_active(false)
	end
	if mod._orbit_active then
		mod.set_orbit_active(false)
	end

	local pos = pt.pos:unbox()
	local rot = pt.rot:unbox()

	local is_free_flight = _ensure_free_flight_active(pos, rot)
	if not is_free_flight then
		mod:echo(mod:localize("msg_dolly_requires_free_cam"))
		return
	end

	if Managers.free_flight and Managers.free_flight.teleport_camera then
		Managers.free_flight:teleport_camera("global", pos, rot)
	else
		local world = _get_level_world()
		if world then
			local ff_viewport = ScriptWorld.global_free_flight_viewport and ScriptWorld.global_free_flight_viewport(world)
			if ff_viewport then
				local cam = ScriptViewport.camera(ff_viewport)
				if cam then
					local pose = Matrix4x4.from_quaternion_position(rot, pos)
					ScriptCamera.set_local_pose(cam, pose)
				end
			end
		end
	end

	local PLAY = _is_replay_active()
	if PLAY and PLAY.viewport_world then
		local viewport = ScriptWorld.global_free_flight_viewport(PLAY.viewport_world)
		if viewport then
			local cam = ScriptViewport.camera(viewport)
			if cam then
				local pose = Matrix4x4.from_quaternion_position(rot, pos)
				ScriptCamera.set_local_pose(cam, pose)
			end
		end
	end

	if pt.fov_offset then
		mod._fov_offset = pt.fov_offset
		mod:set("camera_fov_offset", pt.fov_offset, true)
	end

	mod:echo(mod:localize("msg_dolly_point_teleported") .. ": Point " .. tostring(pt.name))
end

mod.dolly_update_point = function(index)
	if not mod:is_enabled() then
		return
	end

	local count = #mod._dolly_points
	if count == 0 then
		mod:echo(mod:localize("msg_dolly_no_points"))
		return
	end

	index = math.clamp(index or mod._selected_dolly_index or 1, 1, count)
	local pos, rot = _get_camera_transform()
	if not pos or not rot then
		return
	end

	local pt = mod._dolly_points[index]
	pt.pos = Vector3Box(pos)
	pt.rot = QuaternionBox(rot)
	pt.fov_offset = mod._fov_offset or 0

	if mod._dolly_active then
		mod._dolly_dists, mod._dolly_total_dist = _calculate_dolly_distances()
	end

	mod:echo(mod:localize("msg_dolly_point_updated") .. ": Point " .. tostring(pt.name))
end

mod.set_dolly_active = function(enabled)
	if not mod:is_enabled() then
		return
	end

	if enabled then
		_ensure_free_flight_active()

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
		mod._dolly_timer = 0
		mod._dolly_last_step = nil

		local start_pt = mod._dolly_points[1]
		mod._dolly_pos = Vector3Box(start_pt.pos:unbox())
		mod._dolly_rot = QuaternionBox(start_pt.rot:unbox())

		if start_pt.fov_offset then
			mod._fov_offset = start_pt.fov_offset
		end

		mod._selected_dolly_index = 1

		mod._dolly_active = true
		mod:set("dolly_active", true)
		_update_rig_perspective()
		mod:echo(mod:localize("msg_dolly_started"))
	else
		mod._dolly_active = false
		mod._dolly_pos = nil
		mod._dolly_rot = nil
		mod._fov_offset = mod:get("camera_fov_offset") or 0
		mod:set("dolly_active", false)
		_update_rig_perspective()
		mod:echo(mod:localize("msg_dolly_stopped"))
	end
end

mod.toggle_dolly = function()
	mod.set_dolly_active(not mod._dolly_active)
end

local function _get_orbit_center()
	local target_mode = mod:get("orbit_target_mode") or "character"

	if target_mode == "character" then
		local spectated_unit = _get_spectated_puppet_unit()
		if spectated_unit and Unit.alive(spectated_unit) then
			return Unit.world_position(spectated_unit, 1) + Vector3(0, 0, 1.1)
		end

		local player = Managers.player and Managers.player:local_player(1)
		local unit = player and player.player_unit
		if unit and Unit.alive(unit) then
			return Unit.world_position(unit, 1) + Vector3(0, 0, 1.1)
		end
	end

	if mod._orbit_center then
		return mod._orbit_center:unbox()
	end

	local spectated_unit = _get_spectated_puppet_unit()
	if spectated_unit and Unit.alive(spectated_unit) then
		return Unit.world_position(spectated_unit, 1) + Vector3(0, 0, 1.1)
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
		local pos, rot = _get_camera_transform()

		_ensure_replay_free_cam(pos, rot)

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

		if not pos or not rot then
			pos, rot = _get_camera_transform()
		end
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
		mod._orbit_paused = false
		mod:set("orbit_active", true)
		mod:set("orbit_paused", false)
		_update_rig_perspective()
		mod:echo(mod:localize("msg_orbit_started"))
	else
		mod._orbit_active = false
		mod._orbit_paused = false
		mod._orbit_pos = nil
		mod._orbit_rot = nil
		mod:set("orbit_active", false)
		mod:set("orbit_paused", false)
		_update_rig_perspective()
		mod:echo(mod:localize("msg_orbit_stopped"))
	end
end

mod.set_orbit_paused = function(paused)
	if not mod:is_enabled() then
		return
	end

	mod._orbit_paused = (paused == true)
	mod:set("orbit_paused", mod._orbit_paused)

	if not mod._silent_reset then
		mod:echo(mod:localize(mod._orbit_paused and "msg_orbit_paused" or "msg_orbit_resumed"))
	end
end

mod.toggle_orbit_pause = function()
	if not mod:is_enabled() then
		return
	end

	if not mod._orbit_active then
		mod.set_orbit_active(true)
		return
	end

	mod.set_orbit_paused(not mod._orbit_paused)
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
	mod.set_mouse_smoothing(not mod._mouse_smoothing)
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

mod.extinguish_map_lights = function()
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

	mod:echo(mod:localize("msg_blackout_on"))
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

mod.toggle_blackout_zone = function()
	if mod._blackout_active then
		mod._blackout_active = false
		mod:set("blackout_active", false, true)
		mod.restore_all_extinguished_lights()
	else
		mod._blackout_active = true
		mod:set("blackout_active", true, true)
		mod.extinguish_map_lights()
	end
end

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

			local PLAY = _is_replay_active()
			if PLAY then
				PLAY.paused = true
				_sync_replay_clock_scale()
			end

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
					Unit.set_data(mod._lantern_unit, "photo_mode_light", true)
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

	if _is_camera_rig_active() then
		local unit = _get_own_character_unit()
		if unit then
			local fp_ext = ScriptUnit.has_extension(unit, "first_person_system")
			if fp_ext and not fp_ext._force_third_person_mode then
				fp_ext._force_third_person_mode = true
				local t = Managers.time and Managers.time:time("gameplay") or 0
				if fp_ext._update_first_person_mode then
					fp_ext._show_1p_equipment, fp_ext._wants_1p_camera = fp_ext:_update_first_person_mode(t)
				end
				local vl_ext = ScriptUnit.has_extension(unit, "visual_loadout_system")
				if vl_ext and vl_ext.force_update_item_visibility then
					vl_ext:force_update_item_visibility()
				end
			end
		end
	end

	if mod._dolly_active and mod._dolly_points and #mod._dolly_points >= 2 and mod._dolly_pos and mod._dolly_rot then
		local motion = mod:get("dolly_motion") or "smooth"

		if motion == "instant" or motion == "instant_loop" then
			local count = #mod._dolly_points
			local step_time = math.max(0.1, mod:get("dolly_time_inbetween") or 2.0)
			mod._dolly_timer = (mod._dolly_timer or 0) + dt

			local total_time = count * step_time

			if motion == "instant_loop" then
				if mod._dolly_timer >= total_time then
					mod._dolly_timer = mod._dolly_timer % total_time
				end
			elseif mod._dolly_timer >= total_time then
				mod.set_dolly_active(false)
				return
			end

			local step_idx = math.clamp(math.floor(mod._dolly_timer / step_time) + 1, 1, count)
			if step_idx ~= mod._dolly_last_step then
				mod._dolly_last_step = step_idx
				local pt = mod._dolly_points[step_idx]
				if pt then
					mod._dolly_pos:store(pt.pos:unbox())
					mod._dolly_rot:store(pt.rot:unbox())
					if pt.fov_offset then
						mod._fov_offset = pt.fov_offset
					end
					mod._selected_dolly_index = step_idx
				end
			end
		else
			local duration = mod:get("dolly_duration") or 8.0

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

					local active_idx = (seg_t >= 0.5) and (seg_index + 1) or seg_index
					mod._selected_dolly_index = math.clamp(active_idx, 1, #mod._dolly_points)
				end
			end

			if motion ~= "loop" and mod._dolly_progress >= 1.0 then
				mod.set_dolly_active(false)
			end
		end
	end

	if mod._orbit_active then
		local center = _get_orbit_center()

		if center then
			if not mod._orbit_paused then
				local speed = mod:get("orbit_speed") or 15.0
				local dir = (mod:get("orbit_direction") == "ccw") and 1 or -1
				local d_angle = math.rad(speed) * dir * dt
				mod._orbit_angle = ((mod._orbit_angle or 0) + d_angle) % (2 * math.pi)
			end

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
			local ff_viewport = ScriptWorld.global_free_flight_viewport and
			ScriptWorld.global_free_flight_viewport(world)

			if ff_viewport then
				local cam = ScriptViewport.camera(ff_viewport)

				if cam then
					Camera.set_vertical_fov(cam, math.clamp(math.rad(65 + mod._fov_offset), math.rad(10), math.rad(150)))
					mod._fov_applied = true
				end
			end
		end
	elseif mod._fov_applied then
		local world = _get_level_world()

		if world then
			local ff_viewport = ScriptWorld.global_free_flight_viewport and
			ScriptWorld.global_free_flight_viewport(world)

			if ff_viewport then
				local cam = ScriptViewport.camera(ff_viewport)

				if cam then
					Camera.set_vertical_fov(cam, math.rad(65))
				end
			end
		end
		mod._fov_applied = nil
	end
end

mod:hook("UIHud", "init", function(func, self, elements, visibility_groups, params)
	table.insert(visibility_groups, 1, {
		name = HUD_VISIBILITY_GROUP,
		validation_function = function(hud)
			local m = get_mod("photo_mode")
			return m and m:is_enabled() and m._hud_hidden
		end,
		visible_elements = {
			HudElementPhotoModeMenu = true,
			HudElementReplaysMenu = true,
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
	if self._elements and self._elements.HudElementReplaysMenu then
		self._currently_visible_elements.HudElementReplaysMenu = true
	end
end)

mod:hook("UIHud", "draw", function(func, self, dt, t, input_service)
	if mod:is_enabled() and mod._hud_hidden then
		local is_world_enabled = Managers.world:is_world_enabled(self._world_name)
		if is_world_enabled then
			local ui_renderer = self._ui_renderer
			local render_settings = self._render_settings
			local saved_start_layer = render_settings and render_settings.start_layer
			if ui_renderer and render_settings then
				local menu_element = self._elements and self._elements.HudElementPhotoModeMenu
				if menu_element and menu_element.draw then
					menu_element:draw(dt, t, ui_renderer, render_settings, input_service)
					render_settings.start_layer = saved_start_layer
				end

				local replays_menu = self._elements and self._elements.HudElementReplaysMenu
				if replays_menu and replays_menu.draw then
					replays_menu:draw(dt, t, ui_renderer, render_settings, input_service)
					render_settings.start_layer = saved_start_layer
				end
			end
		end
		return
	end

	return func(self, dt, t, input_service)
end)

mod:hook("UIRenderer", "script_draw_text", function(func, self, ...)
	if self.render_settings and not self.render_settings.material_flags then
		self.render_settings.material_flags = 0
	end

	return func(self, ...)
end)

mod:hook("HumanUnitInput", "get", function(func, self, action, ...)
	if mod:is_enabled() and mod._menu_open then
		local actions_allowed = mod._actions_allowed ~= false
		local menu_input_active = mod._menu_hovered

		if not actions_allowed or menu_input_active then
			if action == "action_one_pressed" or action == "action_one_hold" or action == "action_one_release"
				or action == "action_two_pressed" or action == "action_two_hold" or action == "action_two_release"
				or action == "weapon_reload" or action == "wield" then
				return false
			end
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

local _ff_smooth_x = 0
local _ff_smooth_y = 0
local _player_smooth_x = 0
local _player_smooth_y = 0

mod._reset_mouse_smoothing = function()
	_ff_smooth_x = 0
	_ff_smooth_y = 0
	_player_smooth_x = 0
	_player_smooth_y = 0
end

local function _calculate_smoothed_look(raw_look, prev_x, prev_y, dt, strength, speed)
	local spd = speed or 1.0
	local raw_x = Vector3.x(raw_look) * spd
	local raw_y = Vector3.y(raw_look) * spd

	if raw_x == 0 and raw_y == 0 and math.abs(prev_x) < 0.0001 and math.abs(prev_y) < 0.0001 then
		return Vector3(0, 0, 0), 0, 0
	end

	local real_dt = (Managers.time and Managers.time:has_timer("main") and Managers.time:delta_time("main")) or dt
	local clamped_dt = math.clamp(real_dt or 0.016, 0.001, 0.1)
	local decay = math.pow(math.clamp(strength, 0.05, 0.98), clamped_dt * 60)
	local inv_decay = 1 - decay

	local new_x = prev_x * decay + raw_x * inv_decay
	local new_y = prev_y * decay + raw_y * inv_decay

	if math.abs(new_x) < 0.0001 and raw_x == 0 then
		new_x = 0
	end
	if math.abs(new_y) < 0.0001 and raw_y == 0 then
		new_y = 0
	end

	return Vector3(new_x, new_y, 0), new_x, new_y
end

local _zero_vector = Vector3.zero()
local _safe_ff_null_service = {
	input = nil,
	get = function(self, action_name)
		local val = self.input and self.input:get(action_name)
		local input_type = type(val)

		if input_type == "number" then
			return 0
		elseif input_type == "boolean" then
			return false
		elseif input_type == "userdata" or input_type == "Vector3" then
			return _zero_vector
		end

		return 0
	end,
	null_service = function(self)
		return self
	end,
}

mod:hook_require("scripts/foundation/managers/free_flight/free_flight_default_input", function(instance)
	instance.null_service = function(self)
		_safe_ff_null_service.input = self
		return _safe_ff_null_service
	end
end)

mod:hook("FreeFlightDefaultInput", "null_service", function(func, self)
	_safe_ff_null_service.input = self
	return _safe_ff_null_service
end)

local _ff_current_input = nil
local _ff_current_dt = 0.016
local _ff_input_proxy = {}
local _ff_proxy_mt = {
	__index = function(t, key)
		local orig = _ff_current_input
		if not orig then
			return nil
		end
		local val = orig[key]
		if type(val) == "function" then
			return function(self_or_t, ...)
				local actual_self = (self_or_t == t) and orig or self_or_t
				return val(actual_self, ...)
			end
		end
		return val
	end
}
setmetatable(_ff_input_proxy, _ff_proxy_mt)

function _ff_input_proxy:get(action_name, ...)
	if not _ff_current_input then
		return false
	end

	if action_name == "look" then
		local raw_look = _ff_current_input:get("look", ...)
		local smoothed_look, new_x, new_y = _calculate_smoothed_look(
			raw_look,
			_ff_smooth_x,
			_ff_smooth_y,
			_ff_current_dt,
			mod._mouse_smoothing_amount or 0.65,
			mod._mouse_smoothing_speed or 1.0
		)
		_ff_smooth_x = new_x
		_ff_smooth_y = new_y
		return smoothed_look
	end

	return _ff_current_input:get(action_name, ...)
end

function _ff_input_proxy:null_service()
	_safe_ff_null_service.input = _ff_current_input
	return _safe_ff_null_service
end

local function _wrap_freeflight_input(input, dt)
	_ff_current_input = input
	_ff_current_dt = dt
	return _ff_input_proxy
end

local _player_current_input = nil
local _player_current_dt = 0.016
local _player_input_proxy = {}
local _player_proxy_mt = {
	__index = function(t, key)
		local orig = _player_current_input
		if not orig then
			return nil
		end
		local val = orig[key]
		if type(val) == "function" then
			return function(self_or_t, ...)
				local actual_self = (self_or_t == t) and orig or self_or_t
				return val(actual_self, ...)
			end
		end
		return val
	end
}
setmetatable(_player_input_proxy, _player_proxy_mt)

function _player_input_proxy:get(action_name, ...)
	if not _player_current_input then
		return false
	end

	if action_name == "look" or action_name == "look_ranged" or action_name == "look_ranged_alternate_fire" then
		local raw_look = _player_current_input:get(action_name, ...)
		local smoothed_look, new_x, new_y = _calculate_smoothed_look(
			raw_look,
			_player_smooth_x,
			_player_smooth_y,
			_player_current_dt,
			mod._mouse_smoothing_amount or 0.65,
			mod._mouse_smoothing_speed or 1.0
		)
		_player_smooth_x = new_x
		_player_smooth_y = new_y
		return smoothed_look
	end

	return _player_current_input:get(action_name, ...)
end

local function _wrap_player_input(input, dt)
	_player_current_input = input
	_player_current_dt = dt
	return _player_input_proxy
end

mod:hook("DefaultPlayerOrientation", "pre_update",
	function(func, self, main_t, main_dt, input, sensitivity_modifier, rotation_contraints)
		if input and mod:is_enabled() then
			if mod._menu_open and mod._camera_locked then
				input = input:null_service()
			elseif mod._mouse_smoothing then
				input = _wrap_player_input(input, main_dt)
			end
		end

		return func(self, main_t, main_dt, input, sensitivity_modifier, rotation_contraints)
	end)

mod:hook("HubPlayerOrientation", "pre_update",
	function(func, self, main_t, main_dt, input, sensitivity_modifier, rotation_contraints)
		if input and mod:is_enabled() then
			if mod._menu_open and mod._camera_locked then
				input = input:null_service()
			elseif mod._mouse_smoothing then
				input = _wrap_player_input(input, main_dt)
			end
		end

		return func(self, main_t, main_dt, input, sensitivity_modifier, rotation_contraints)
	end)

mod:hook("ConstantElementChat", "draw", function(func, self, dt, t, ui_renderer, render_settings, input_service)
	if mod:is_enabled() and mod._chat_hidden then
		return
	end

	return func(self, dt, t, ui_renderer, render_settings, input_service)
end)

mod:hook("ConstantElementChat", "should_draw", function(func, self)
	if mod:is_enabled() and mod._chat_hidden then
		return false
	end

	return func(self)
end)

mod:hook("CameraManager", "_update_camera_properties",
	function(func, self, camera, shadow_cull_camera, camera_nodes, camera_data, viewport_name)
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
				camera_data.vertical_fov = math.clamp(camera_data.vertical_fov + math.rad(mod._fov_offset), math.rad(10),
					math.rad(150))
			end
		end

		func(self, camera, shadow_cull_camera, camera_nodes, camera_data, viewport_name)
	end)

mod:hook_safe("CameraManager", "shading_callback",
	function(self, world, shading_env, viewport, default_shading_environment_resource)
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

		local exposure_offset = math.clamp(mod:get("exposure_compensation") or 0.0, -11.0, 3.0)
		local need_apply = false

		if exposure_offset and exposure_offset ~= 0.0 then
			local cur_exp = ShadingEnvironment.scalar(shading_env, "exposure_compensation") or 0
			ShadingEnvironment.set_scalar(shading_env, "exposure_compensation", cur_exp + exposure_offset)
			mod._exposure_was_applied = true
			need_apply = true
		elseif mod._exposure_was_applied then
			mod._exposure_was_applied = false
			need_apply = true
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
			need_apply = true
			mod._dof_was_applied = true
		elseif mod._dof_was_applied then
			ShadingEnvironment.set_scalar(shading_env, "dof_enabled", 0)
			need_apply = true
			mod._dof_was_applied = false
		end

		if need_apply then
			ShadingEnvironment.apply(shading_env)
		end
	end)

mod:hook("FreeFlightManager", "camera", function(func, self, camera_id)
	local data = self._free_flight_cameras and self._free_flight_cameras[camera_id]
	if not data or not data.viewport_world_name then
		return false
	end

	local world = Managers.world and Managers.world:has_world(data.viewport_world_name) and Managers.world:world(data.viewport_world_name)
	if not world then
		data.active = false
		data.viewport_world_name = nil
		return false
	end

	local viewport = ScriptWorld.global_free_flight_viewport and ScriptWorld.global_free_flight_viewport(world)
	if not viewport then
		data.active = false
		data.viewport_world_name = nil
		return false
	end

	return func(self, camera_id)
end)

mod:hook("FreeFlightManager", "_update_camera", function(func, self, input, dt, camera_data)
	if not camera_data or not camera_data.viewport_world_name then
		if camera_data then
			camera_data.active = false
		end
		return
	end

	local world = Managers.world and Managers.world:has_world(camera_data.viewport_world_name) and Managers.world:world(camera_data.viewport_world_name)
	if not world then
		camera_data.active = false
		camera_data.viewport_world_name = nil
		return
	end

	local viewport = ScriptWorld.global_free_flight_viewport and ScriptWorld.global_free_flight_viewport(world)
	if not viewport and not camera_data.frustum_freeze_camera then
		camera_data.active = false
		camera_data.viewport_world_name = nil
		return
	end

	local is_rig_active = mod._tripod_active or mod._dolly_active or mod._orbit_active

	if mod:is_enabled() and mod._menu_open and mod._camera_locked and not is_rig_active then
		return
	end

	if input and mod:is_enabled() and mod._mouse_smoothing then
		input = _wrap_freeflight_input(input, dt)
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
	elseif setting_id == "orbit_paused" then
		local val = mod:get("orbit_paused") == true
		if val ~= mod._orbit_paused then
			mod.set_orbit_paused(val)
		end
	elseif setting_id == "slomo_scale" and mod._slomo_active and not mod._time_frozen then
		local slomo_scale = mod:get("slomo_scale") or 0.10
		_set_time_scale(slomo_scale)
		_sync_replay_clock_scale()
	elseif setting_id == "camera_fov_offset" then
		mod._fov_offset = mod:get("camera_fov_offset") or 0
		local world = _get_level_world()
		if world then
			local ff_viewport = ScriptWorld.global_free_flight_viewport and ScriptWorld.global_free_flight_viewport(world)
			if ff_viewport then
				local cam = ScriptViewport.camera(ff_viewport)
				if cam then
					local default_fov_rad = math.rad(65)
					local current_fov = math.clamp(default_fov_rad + math.rad(mod._fov_offset), math.rad(5), math.rad(125))
					Camera.set_vertical_fov(cam, current_fov)
				end
			end
		end
	elseif setting_id == "camera_tilt" then
		mod._tilt_angle = mod:get("camera_tilt") or 0
	elseif setting_id == "dof_focal_distance" then
		mod._dof_distance = mod:get("dof_focal_distance") or 3.0
	elseif setting_id == "lock_camera_in_menu" then
		mod._camera_locked = mod:get("lock_camera_in_menu") ~= false
	elseif setting_id == "allow_in_game_actions" then
		mod._actions_allowed = mod:get("allow_in_game_actions") ~= false
	elseif setting_id == "mouse_smoothing" then
		local val = mod:get("mouse_smoothing")
		if val ~= mod._mouse_smoothing then
			mod.set_mouse_smoothing(val)
		end
	elseif setting_id == "mouse_smoothing_amount" then
		mod._mouse_smoothing_amount = mod:get("mouse_smoothing_amount") or 0.65
	elseif setting_id == "mouse_smoothing_speed" then
		mod._mouse_smoothing_speed = mod:get("mouse_smoothing_speed") or 1.0
	elseif setting_id == "blackout_active" then
		local val = mod:get("blackout_active") == true
		if val ~= mod._blackout_active then
			mod.toggle_blackout_zone()
		end
	end

	if setting_id == "light_intensity" or setting_id == "light_radius"
		or setting_id == "spot_angle" or setting_id == "light_color"
		or setting_id == "light_type" or setting_id == "cast_shadows"
		or setting_id == "exposure_compensation" then
		mod.update_all_lights()
	end
end

mod.on_settings_reset = function()
	mod.reset_all_settings()
end

mod.on_game_state_changed = function(status, state_name)
	_cleanup_all()
end

mod.on_disabled = function(initial_call)
	_cleanup_all()
end

local _replays_hooked = false

local function _setup_replays_integration()
	if _replays_hooked then
		return
	end

	local replays = get_mod("Replays")
	local PLAY = replays and replays.rec and replays.rec.playback

	if not PLAY or type(PLAY.drive_free_cam) ~= "function" then
		return
	end

	_replays_hooked = true

	local function _hook_play(name, hook_fn)
		if type(PLAY[name]) == "function" then
			mod:hook(PLAY, name, hook_fn)
		end
	end

	_hook_play("drive_free_cam", function(func, dt)
		if not mod:is_enabled() then
			return func(dt)
		end

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
			if mod._tilt_angle and mod._tilt_angle ~= 0 then
				local roll_offset = Quaternion.from_yaw_pitch_roll(0, 0, math.rad(mod._tilt_angle))
				rot = Quaternion.multiply(rot, roll_offset)
			end

			local world = PLAY.viewport_world
			if world then
				local viewport = ScriptWorld.global_free_flight_viewport(world)
				if viewport then
					local cam = ScriptViewport.camera(viewport)
					if cam then
						local pose = Matrix4x4.from_quaternion_position(rot, pos)
						ScriptCamera.set_local_pose(cam, pose)

						if PLAY.terrain_observer then
							TerrainDecoration.move_observer(world, PLAY.terrain_observer, pos)
						end

						if PLAY.scatter_observer then
							ScatterSystem.move_observer(World.scatter_system(world), PLAY.scatter_observer, pos, rot)
						end

						local ww = Managers.world:wwise_world(world)
						if ww then
							WwiseWorld.set_listener(ww, 0, pose)
						end

						return
					end
				end
			end
		end

		local orig_mouse_axis = Mouse.axis
		if mod._mouse_smoothing and orig_mouse_axis then
			Mouse.axis = function(axis_index)
				if axis_index == 0 then
					local raw_look = orig_mouse_axis(0)
					local smoothed_look, new_x, new_y = _calculate_smoothed_look(
						raw_look,
						_ff_smooth_x,
						_ff_smooth_y,
						dt,
						mod._mouse_smoothing_amount or 0.65,
						mod._mouse_smoothing_speed or 1.0
					)
					_ff_smooth_x = new_x
					_ff_smooth_y = new_y
					return smoothed_look
				end
				return orig_mouse_axis(axis_index)
			end
		end

		func(dt)

		if orig_mouse_axis then
			Mouse.axis = orig_mouse_axis
		end

		if mod._tilt_angle and mod._tilt_angle ~= 0 then
			local world = PLAY.viewport_world
			if world then
				local viewport = ScriptWorld.global_free_flight_viewport(world)
				if viewport then
					local cam = ScriptViewport.camera(viewport)
					if cam then
						local pose = Camera.local_pose(cam)
						local roll_offset = Quaternion.from_yaw_pitch_roll(0, 0, math.rad(mod._tilt_angle))
						local current_rot = Matrix4x4.rotation(pose)
						local new_rot = Quaternion.multiply(current_rot, roll_offset)
						Matrix4x4.set_rotation(pose, new_rot)
						ScriptCamera.set_local_pose(cam, pose)
					end
				end
			end
		end
	end)

	_hook_play("speed", function(func)
		if mod:is_enabled() and PLAY.state == "playing" and not PLAY.at_end then
			if mod._step_frames_remaining and mod._step_frames_remaining > 0 then
				return 1.0
			end

			if mod._time_frozen or PLAY.paused then
				return 0
			end

			if mod._slomo_active then
				return mod:get("slomo_scale") or 0.10
			end
		end

		return func()
	end)

	_hook_play("free_cam_frozen", function(func)
		if mod:is_enabled() and mod._menu_open and mod._camera_locked then
			return true
		end

		return func()
	end)

	_hook_play("ui_owns_input", function(func)
		if mod:is_enabled() and mod._menu_open then
			return true
		end

		return func()
	end)

	_hook_play("poll_view_buttons", function(func)
		if mod:is_enabled() and (mod._menu_open or mod._tripod_active or mod._dolly_active or mod._orbit_active) then
			PLAY.view_forward_held = false
			PLAY.view_back_held = false
			return
		end

		return func()
	end)

	local replays = get_mod("Replays")
	local RUI = replays and replays.rec and replays.rec.ui
	if RUI and type(RUI.toggle_hud) == "function" then
		mod:hook(RUI, "toggle_hud", function(func)
			local result = func()
			if mod:is_enabled() and not _in_sync_hud then
				_in_sync_hud = true
				mod.set_hide_hud(RUI.hud_hidden)
				_in_sync_hud = false
			end
			return result
		end)
	end


	_hook_play("toggle_pause", function(func)
		func()
		if mod:is_enabled() then
			mod._time_frozen = PLAY.paused
			mod:set("freeze_time", PLAY.paused, true)
			_sync_replay_clock_scale()
		end
	end)

	_hook_play("wanted_clock_scale", function(func)
		if mod:is_enabled() and PLAY.state == "playing" and not PLAY.at_end then
			if mod._step_frames_remaining and mod._step_frames_remaining > 0 then
				return 1.0
			end

			if mod._time_frozen or PLAY.paused then
				return 0.001
			end

			if mod._slomo_active then
				return mod:get("slomo_scale") or 0.10
			end
		end

		return func()
	end)

	_hook_play("stop", function(func, reason)
		if mod:is_enabled() then
			_cleanup_all()
		end
		return func(reason)
	end)
end

mod.on_all_mods_loaded = function()
	_ensure_hud_group()
	_cleanup_all()
	_setup_replays_integration()
end

mod.on_unload = function(exit_game)
	_cleanup_all()
end

_ensure_hud_group()
_setup_replays_integration()
