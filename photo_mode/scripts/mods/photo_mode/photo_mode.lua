local mod = get_mod("photo_mode")

local _orig_echo = mod.echo
mod.echo = function(self, ...)
	if mod:get("show_chat_messages") == false then
		return
	end
	if _orig_echo then
		return _orig_echo(self, ...)
	end
end

local ScriptViewport = require("scripts/foundation/utilities/script_viewport")
local ScriptWorld = require("scripts/foundation/utilities/script_world")

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
mod._hud_hidden = mod:get("hide_hud") or false
mod._chat_hidden = mod:get("hide_chat") or false
mod._arms_hidden = mod:get("hide_arms") or false
mod._screen_effects_hidden = mod:get("hide_screen_effects") or false
mod._step_frames_remaining = nil

mod._placed_lights = {}
mod._selected_light_index = nil
mod._lantern_active = mod:get("lantern_active") or false
mod._lantern_unit = nil
mod._blackout_active = false
mod._extinguished_units = {}
mod._exposure_was_applied = false

mod._fov_offset = mod:get("camera_fov_offset") or 0
mod._lock_fov = mod:get("lock_fov") or false
mod._tilt_angle = mod:get("camera_tilt") or 0
mod._dof_active = mod:get("dof_active") or false
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

local _target_mode_init = mod:get("orbit_target_mode") or "follow"
local _is_char_init = (_target_mode_init == "follow" or _target_mode_init == "character")
mod._orbit_active = (mod:get("orbit_active") == true and _is_char_init) or false
if not _is_char_init and mod:get("orbit_active") then
	mod:set("orbit_active", false)
end
mod._orbit_pos = nil
mod._orbit_rot = nil
mod._orbit_center = nil
mod._orbit_smooth_center = nil
mod._orbit_smooth_fwd = nil
mod._orbit_smooth_height_drop = 0
mod._orbit_smooth_pitch_give = 0
mod._orbit_angle = math.rad(mod:get("orbit_angle") or 0)
mod._orbit_height = mod:get("orbit_height") or 0.3
mod._orbit_pitch = mod:get("orbit_pitch") or 0
mod._orbit_side_offset = mod:get("orbit_side_offset") or 0.0
mod._orbit_paused = mod:get("orbit_paused") or false
mod._hide_outlines = mod:get("hide_outlines") or false

mod._shared = {}

mod:io_dofile("photo_mode/scripts/mods/photo_mode/core")
mod:io_dofile("photo_mode/scripts/mods/photo_mode/lights")
mod:io_dofile("photo_mode/scripts/mods/photo_mode/resets")
mod:io_dofile("photo_mode/scripts/mods/photo_mode/profiles")
mod:io_dofile("photo_mode/scripts/mods/photo_mode/actions")
mod:io_dofile("photo_mode/scripts/mods/photo_mode/dolly")
mod:io_dofile("photo_mode/scripts/mods/photo_mode/orbit")
mod:io_dofile("photo_mode/scripts/mods/photo_mode/input")
mod:io_dofile("photo_mode/scripts/mods/photo_mode/hooks")
mod:io_dofile("photo_mode/scripts/mods/photo_mode/replays")

local Shared = mod._shared
local _apply_light_settings = Shared._apply_light_settings
local _apply_outlines_visibility = Shared._apply_outlines_visibility
local _cleanup_all = Shared._cleanup_all
local _ensure_hud_group = Shared._ensure_hud_group
local _get_camera_transform = Shared._get_camera_transform
local _get_level_world = Shared._get_level_world
local _get_orbit_center = Shared._get_orbit_center
local _get_own_character_unit = Shared._get_own_character_unit
local _get_spectated_puppet_unit = Shared._get_spectated_puppet_unit
local _get_unit_heading_rotation = Shared._get_unit_heading_rotation
local _guard_hotkeys_while_typing = Shared._guard_hotkeys_while_typing
local _is_camera_rig_active = Shared._is_camera_rig_active
local _is_replay_active = Shared._is_replay_active
local _set_time_scale = Shared._set_time_scale
local _set_world_paused = Shared._set_world_paused
local _setup_replays_integration = Shared._setup_replays_integration
local _sync_replay_clock_scale = Shared._sync_replay_clock_scale
local _update_rig_perspective = Shared._update_rig_perspective

mod.update = function(dt)
	if mod._arms_hidden and mod:is_enabled() then
		mod._set_arms_visibility(false)
	elseif mod._arms_pending and mod:is_enabled() and mod._set_arms_visibility(false) then
		mod._arms_hidden = true
		mod._arms_pending = false
	end

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
			local target_mode = mod:get("orbit_target_mode") or "follow"
			local is_char = (target_mode == "character" or target_mode == "follow")
			local follow_rot = (target_mode == "follow")
				or (target_mode == "character" and mod:get("orbit_follow_rotation") == true)
			local unit = is_char and (_get_spectated_puppet_unit() or _get_own_character_unit())

			if is_char and unit and (not mod._rig_forced_3p or mod._rig_forced_3p_unit ~= unit) then
				_update_rig_perspective(true)
			end

			local dynamic_give = mod:get("orbit_dynamic_give") ~= false
			if is_char and dynamic_give and unit and Unit.alive(unit) then
				local fp_ext = ScriptUnit.has_extension(unit, "first_person_system")
				local default_h = (fp_ext and fp_ext._heights and fp_ext._heights.default) or 1.7
				local cur_h = (
					fp_ext
					and fp_ext.extrapolated_character_height
					and fp_ext:extrapolated_character_height()
				) or default_h
				local raw_drop = math.max(0, default_h - cur_h)
				local slide_give = mod:get("orbit_slide_give")
				if slide_give == nil then
					slide_give = 0.5
				end
				local target_drop = raw_drop * slide_give
				local drop_lerp = 1 - math.exp(-14.0 * dt)
				mod._orbit_smooth_height_drop = (mod._orbit_smooth_height_drop or 0)
					+ (target_drop - (mod._orbit_smooth_height_drop or 0)) * math.clamp(drop_lerp, 0, 1)

				local fp_rot = _get_unit_heading_rotation(unit)
				local look_pitch = fp_rot and Quaternion.pitch(fp_rot) or 0
				local pitch_give = mod:get("orbit_pitch_give")
				if pitch_give == nil then
					pitch_give = 0.35
				end
				local target_pitch_deg = math.deg(look_pitch) * pitch_give
				local pitch_lerp = 1 - math.exp(-12.0 * dt)
				mod._orbit_smooth_pitch_give = (mod._orbit_smooth_pitch_give or 0)
					+ (target_pitch_deg - (mod._orbit_smooth_pitch_give or 0)) * math.clamp(pitch_lerp, 0, 1)
			else
				mod._orbit_smooth_height_drop = 0
				mod._orbit_smooth_pitch_give = 0
			end

			if is_char then
				if not mod._orbit_smooth_center then
					mod._orbit_smooth_center = Vector3Box(center)
				else
					local prev_c = mod._orbit_smooth_center:unbox()
					local dist_sq = Vector3.distance_squared(prev_c, center)
					if dist_sq > 25.0 then
						mod._orbit_smooth_center:store(center)
					else
						local lerp_factor = 1 - math.exp(-25.0 * dt)
						local smooth_c = Vector3.lerp(prev_c, center, math.clamp(lerp_factor, 0, 1))
						mod._orbit_smooth_center:store(smooth_c)
						center = smooth_c
					end
				end
			else
				mod._orbit_smooth_center = nil

				if not mod._orbit_center then
					mod._orbit_center = Vector3Box(center)
				end
			end

			if not mod._orbit_paused then
				local speed = mod:get("orbit_speed") or 15.0
				local dir = (mod:get("orbit_direction") == "ccw") and 1 or -1
				local d_angle = math.rad(speed) * dir * dt
				mod._orbit_angle = ((mod._orbit_angle or 0) + d_angle) % (2 * math.pi)
			end

			local radius = mod:get("orbit_radius") or 4.0
			local height = mod:get("orbit_height") or 0.3
			local facing = mod:get("orbit_facing") or "inward"
			local angle = mod._orbit_angle or 0

			local horiz_dir
			if is_char and follow_rot then
				if unit and Unit.alive(unit) then
					local rot = _get_unit_heading_rotation(unit) or Unit.world_rotation(unit, 1)
					local fwd = Vector3.flat(Quaternion.forward(rot))
					local fwd_len = Vector3.length(fwd)
					if fwd_len > 0.001 then
						fwd = fwd / fwd_len
					else
						fwd = Vector3(0, 1, 0)
					end

					if not mod._orbit_smooth_fwd then
						mod._orbit_smooth_fwd = Vector3Box(fwd)
					else
						local prev_fwd = mod._orbit_smooth_fwd:unbox()
						local lerp_factor = 1 - math.exp(-30.0 * dt)
						local smooth_fwd = Vector3.normalize(Vector3.lerp(prev_fwd, fwd, math.clamp(lerp_factor, 0, 1)))
						mod._orbit_smooth_fwd:store(smooth_fwd)
						fwd = smooth_fwd
					end

					local right = Vector3(fwd.y, -fwd.x, 0)
					horiz_dir = -fwd * math.cos(angle) + right * math.sin(angle)
				else
					horiz_dir = Vector3(math.cos(angle), math.sin(angle), 0)
				end
			else
				mod._orbit_smooth_fwd = nil
				horiz_dir = Vector3(math.cos(angle), math.sin(angle), 0)
			end

			local height_drop_offset = Vector3(0, 0, mod._orbit_smooth_height_drop or 0)
			local effective_center = center - height_drop_offset

			local new_pos = effective_center + horiz_dir * radius + Vector3(0, 0, height)
			local look_target = effective_center + Vector3(0, 0, height)
			local look_dir

			if facing == "outward" then
				look_dir = Vector3.normalize(new_pos - look_target)
			else
				look_dir = Vector3.normalize(look_target - new_pos)
			end

			local up = (math.abs(look_dir.z) > 0.99) and Vector3.forward() or Vector3.up()
			local new_rot = Quaternion.look(look_dir, up)

			local orbit_pitch = mod._orbit_pitch or mod:get("orbit_pitch") or 0
			local total_pitch = orbit_pitch + (mod._orbit_smooth_pitch_give or 0)
			if total_pitch ~= 0 then
				local pitch_rot = Quaternion.axis_angle(Quaternion.right(new_rot), math.rad(total_pitch))
				new_rot = Quaternion.multiply(pitch_rot, new_rot)
			end

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
			local ff_viewport = ScriptWorld.global_free_flight_viewport
				and ScriptWorld.global_free_flight_viewport(world)

			if ff_viewport then
				local cam = ScriptViewport.camera(ff_viewport)

				if cam then
					Camera.set_vertical_fov(
						cam,
						math.clamp(math.rad(65 + mod._fov_offset), math.rad(10), math.rad(150))
					)
					mod._fov_applied = true
				end
			end
		end
	elseif mod._fov_applied then
		local world = _get_level_world()

		if world then
			local ff_viewport = ScriptWorld.global_free_flight_viewport
				and ScriptWorld.global_free_flight_viewport(world)

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
		if not val then
			mod._arms_pending = false
		end
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
			local ff_viewport = ScriptWorld.global_free_flight_viewport
				and ScriptWorld.global_free_flight_viewport(world)
			if ff_viewport then
				local cam = ScriptViewport.camera(ff_viewport)
				if cam then
					local default_fov_rad = math.rad(65)
					local current_fov =
						math.clamp(default_fov_rad + math.rad(mod._fov_offset), math.rad(5), math.rad(125))
					Camera.set_vertical_fov(cam, current_fov)
				end
			end
		end
	elseif setting_id == "camera_tilt" then
		mod._tilt_angle = mod:get("camera_tilt") or 0
	elseif setting_id == "lock_fov" then
		local val = mod:get("lock_fov") == true
		if val ~= mod._lock_fov then
			mod._lock_fov = val
			if not mod._silent_reset then
				mod:echo(mod:localize(mod._lock_fov and "msg_fov_locked" or "msg_fov_unlocked"))
			end
		end
	elseif setting_id == "hide_outlines" then
		local val = mod:get("hide_outlines") == true
		if val ~= mod._hide_outlines then
			mod._hide_outlines = val
			if not mod._silent_reset then
				mod:echo(mod:localize(mod._hide_outlines and "msg_outlines_hidden" or "msg_outlines_shown"))
			end
			_apply_outlines_visibility(not val)
		end
	elseif setting_id == "orbit_dynamic_give" then
		if mod:get("orbit_dynamic_give") == false then
			mod._orbit_smooth_height_drop = 0
			mod._orbit_smooth_pitch_give = 0
		end
	elseif setting_id == "orbit_pitch" then
		mod._orbit_pitch = mod:get("orbit_pitch") or 0
	elseif setting_id == "dof_focal_distance" then
		mod._dof_distance = mod:get("dof_focal_distance") or 3.0
	elseif setting_id == "lock_camera_in_menu" then
		mod._camera_locked = mod:get("lock_camera_in_menu") ~= false
	elseif setting_id == "allow_in_game_actions" then
		local val = mod:get("allow_in_game_actions") ~= false
		if val ~= mod._actions_allowed then
			mod.set_in_game_actions(val)
		end
	elseif setting_id == "mouse_smoothing" then
		local val = mod:get("mouse_smoothing")
		if val ~= mod._mouse_smoothing then
			mod.set_mouse_smoothing(val)
		end
	elseif setting_id == "mouse_smoothing_amount" then
		mod._mouse_smoothing_amount = mod:get("mouse_smoothing_amount") or 0.65
	elseif setting_id == "mouse_smoothing_speed" then
		mod._mouse_smoothing_speed = mod:get("mouse_smoothing_speed") or 1.0
	elseif setting_id == "map_lights" or setting_id == "blackout_active" then
		local lights_on = mod:get("map_lights") ~= false
		local should_be_blackout = not lights_on
		if should_be_blackout ~= mod._blackout_active then
			if should_be_blackout then
				mod._blackout_active = true
				mod.extinguish_map_lights()
			else
				mod._blackout_active = false
				mod.restore_all_extinguished_lights()
			end
		end
	end

	if
		setting_id == "light_intensity"
		or setting_id == "light_radius"
		or setting_id == "spot_angle"
		or setting_id == "light_color"
		or setting_id == "light_type"
		or setting_id == "cast_shadows"
		or setting_id == "exposure_compensation"
	then
		mod.update_all_lights()
	end
end

mod.on_settings_reset = function()
	mod.reset_all_settings()
end

mod.on_game_state_changed = function(status, state_name)
	_cleanup_all(true)
end

mod.on_disabled = function(initial_call)
	_cleanup_all(false)
end

mod.on_all_mods_loaded = function()
	_ensure_hud_group()
	_cleanup_all(true)
	_setup_replays_integration()

	local cam_ff = get_mod("camera_freeflight")
	if cam_ff and cam_ff.toggle_freeflight then
		mod:hook_safe(cam_ff, "toggle_freeflight", function()
			if mod._ensuring_free_flight or Managers.ui:chat_using_input() then
				return
			end

			if mod._tripod_active then
				mod.set_tripod_active(false)
			end
			if mod._dolly_active then
				mod.set_dolly_active(false)
			end
			if mod._orbit_active then
				mod.set_orbit_active(false)
			end
		end)
	end

	local po = get_mod("PlayerOutlines")
	if po and PlayerOutlines then
		mod:hook(PlayerOutlines, "update_outline", function(func, ext, unit)
			if mod:is_enabled() and mod._hide_outlines then
				return
			end
			return func(ext, unit)
		end)
		mod:hook(
			PlayerOutlines,
			"_update_hologram",
			function(func, unit, t, is_local_player_unit, player_outlines_enabled, is_in_hub)
				if mod:is_enabled() and mod._hide_outlines then
					if PlayerOutlines._remove_hologram then
						PlayerOutlines._remove_hologram(unit)
					end
					return
				end
				return func(unit, t, is_local_player_unit, player_outlines_enabled, is_in_hub)
			end
		)
		mod:hook(
			PlayerOutlines,
			"apply_outline_color_to_equipment_slots",
			function(func, unit, outline_color, material_layers)
				if mod:is_enabled() and mod._hide_outlines then
					return
				end
				return func(unit, outline_color, material_layers)
			end
		)
	end
end

mod.on_unload = function(exit_game)
	_cleanup_all(false)
end

_ensure_hud_group()
_setup_replays_integration()
_guard_hotkeys_while_typing()
