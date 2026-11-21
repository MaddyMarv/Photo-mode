local mod = get_mod("photo_mode")
local Shared = mod._shared

local ScriptCamera = require("scripts/foundation/utilities/script_camera")
local ScriptViewport = require("scripts/foundation/utilities/script_viewport")
local ScriptWorld = require("scripts/foundation/utilities/script_world")

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
	local cam_ff = get_mod("camera_freeflight")
	if ff and cam_ff and cam_ff:is_enabled() then
		if not ff:is_in_free_flight() then
			if cam_ff.is_in_free_flight and not cam_ff:is_in_free_flight() and cam_ff.toggle_freeflight then
				mod._ensuring_free_flight = true
				cam_ff:toggle_freeflight()
				mod._ensuring_free_flight = false
			end

			if
				not ff:is_in_free_flight()
				and ff._enter_global_free_flight
				and ff._free_flight_cameras
				and ff._free_flight_cameras.global
			then
				ff:_enter_global_free_flight(ff._free_flight_cameras.global)
			end
		end

		return ff:is_in_free_flight()
	end

	return false
end

local function _exit_free_flight()
	local ff = Managers.free_flight
	local cam_ff = get_mod("camera_freeflight")
	if _is_replay_active() or not (ff and ff:is_in_free_flight() and cam_ff and cam_ff.toggle_freeflight) then
		return
	end

	mod._ensuring_free_flight = true
	cam_ff:toggle_freeflight()
	mod._ensuring_free_flight = false
end

local function _sync_replay_clock_scale()
	local PLAY = _is_replay_active()
	if PLAY and PLAY.set_clock_scale and PLAY.wanted_clock_scale then
		PLAY.set_clock_scale(PLAY.wanted_clock_scale())
	end
end

local function _get_local_player(player_manager)
	local pm = player_manager or Managers.player
	if not pm then
		return nil
	end

	if pm.local_player_safe then
		return pm:local_player_safe(1)
	end

	local connection_manager = Managers.connection
	if connection_manager and connection_manager.is_initialized and connection_manager:is_initialized() then
		return pm:local_player(1)
	end

	return nil
end

local function _get_own_character_unit()
	local player = _get_local_player()
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
	local unit = _get_own_character_unit()

	if should_be_3p then
		local needs_attach = (not mod._rig_forced_3p) or (unit and mod._rig_forced_3p_unit ~= unit)
		if _is_camera_rig_active() and needs_attach then
			if perspectives and perspectives:is_enabled() and perspectives.autoswitch then
				perspectives.autoswitch("photo_mode", true, true)
			end

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

				mod._rig_forced_3p_unit = unit
				mod._rig_forced_3p = true
			end
		end
	else
		if mod._rig_forced_3p then
			if perspectives and perspectives:is_enabled() and perspectives.clear_reason then
				perspectives.clear_reason("photo_mode")
			end

			local prev_unit = mod._rig_forced_3p_unit or unit
			if prev_unit and Unit.alive(prev_unit) then
				local fp_ext = ScriptUnit.has_extension(prev_unit, "first_person_system")
				if fp_ext then
					local restore_3p = false
					if perspectives and perspectives:is_enabled() and perspectives.is_requesting_third_person then
						restore_3p = perspectives.is_requesting_third_person()
					else
						if mod._rig_prev_force_3p ~= nil then
							restore_3p = mod._rig_prev_force_3p
						end

						if
							not restore_3p
							and Managers.state
							and Managers.state.mission
							and Managers.state.mission.force_third_person_mode
						then
							restore_3p = Managers.state.mission:force_third_person_mode() or false
						end
					end

					fp_ext._force_third_person_mode = restore_3p

					local t = Managers.time and Managers.time:time("gameplay") or 0
					if fp_ext._update_first_person_mode then
						fp_ext._show_1p_equipment, fp_ext._wants_1p_camera = fp_ext:_update_first_person_mode(t)
					end
				end

				local vl_ext = ScriptUnit.has_extension(prev_unit, "visual_loadout_system")
				if vl_ext and vl_ext.force_update_item_visibility then
					vl_ext:force_update_item_visibility()
				end
			end

			mod._rig_forced_3p = nil
			mod._rig_forced_3p_unit = nil
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
		local player = _get_local_player()
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

	local player = _get_local_player()

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

local function _destroy_lantern_unit()
	local world = _get_level_world()

	if world and mod._lantern_unit and Unit.alive(mod._lantern_unit) then
		World.destroy_unit(world, mod._lantern_unit)
	end

	mod._lantern_unit = nil
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

local function _apply_outlines_visibility(visible)
	local ext_mgr = Managers.state and Managers.state.extension
	local outline_system = ext_mgr and ext_mgr:system("outline_system")
	if outline_system then
		outline_system._visible = visible
		if not visible then
			outline_system:_hide_all_outlines()
		end
	end

	local pm = Managers.player
	if pm then
		for _, player in pairs(pm:players()) do
			local unit = player.player_unit
			if unit and Unit.alive(unit) then
				local holo_ext = ScriptUnit.has_extension(unit, "hologram_system")
				if holo_ext then
					if not visible then
						local holo_unit = holo_ext._hologram_unit
						if holo_unit and holo_ext._world and Unit.alive(holo_unit) then
							World.unlink_unit(holo_ext._world, holo_unit, true)
							World.destroy_unit(holo_ext._world, holo_unit)
						end
						holo_ext._hologram_unit = nil
					else
						holo_ext._next_update_t = 0
					end
				end
			end
		end
	end

	local po = get_mod("PlayerOutlines")
	if po and PlayerOutlines and not visible and PlayerOutlines.clear_all_outlines then
		PlayerOutlines.clear_all_outlines()
	end
end

local function _cleanup_all(keep_orbit)
	mod.close_photo_menu()
	_reset_time_state()
	_destroy_lantern_unit()
	if mod._blackout_active then
		mod.restore_all_extinguished_lights(true)
		mod._blackout_active = false
	end
	table.clear(mod._extinguished_units)
	mod:set("map_lights", true, true)
	mod:set("blackout_active", false, true)

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

	local target_mode = mod:get("orbit_target_mode") or "follow"
	local is_char = (target_mode == "follow" or target_mode == "character")
	local can_persist_orbit = keep_orbit and mod._orbit_active and is_char

	mod._orbit_center = nil

	if not can_persist_orbit then
		mod._orbit_active = false
		mod._orbit_paused = true
		if not is_char then
			mod:set("orbit_active", false)
		end
		mod:set("orbit_paused", true)
	end

	mod._orbit_pos = nil
	mod._orbit_rot = nil
	mod._orbit_smooth_center = nil
	mod._orbit_smooth_fwd = nil
	mod._orbit_smooth_height_drop = 0
	mod._orbit_smooth_pitch_give = 0

	mod:set("freeze_time", false)
	mod:set("slomo_active", false)
	mod:set("tripod_active", false)
	mod:set("dolly_active", false)

	_update_rig_perspective(can_persist_orbit)
	mod._reset_mouse_smoothing()

	if mod._hide_outlines then
		_apply_outlines_visibility(true)
	end
end

Shared.HUD_VISIBILITY_GROUP = HUD_VISIBILITY_GROUP
Shared._apply_outlines_visibility = _apply_outlines_visibility
Shared._cleanup_all = _cleanup_all
Shared._destroy_lantern_unit = _destroy_lantern_unit
Shared._ensure_free_flight_active = _ensure_free_flight_active
Shared._ensure_hud_group = _ensure_hud_group
Shared._ensure_replay_free_cam = _ensure_replay_free_cam
Shared._exit_free_flight = _exit_free_flight
Shared._get_camera_transform = _get_camera_transform
Shared._get_level_world = _get_level_world
Shared._get_local_player = _get_local_player
Shared._get_own_character_unit = _get_own_character_unit
Shared._get_spectated_puppet_unit = _get_spectated_puppet_unit
Shared._is_camera_rig_active = _is_camera_rig_active
Shared._is_replay_active = _is_replay_active
Shared._set_time_scale = _set_time_scale
Shared._set_world_paused = _set_world_paused
Shared._sync_replay_clock_scale = _sync_replay_clock_scale
Shared._update_rig_perspective = _update_rig_perspective
