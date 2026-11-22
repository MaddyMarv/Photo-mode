local mod = get_mod("photo_mode")
local Shared = mod._shared

local ScriptCamera = require("scripts/foundation/utilities/script_camera")
local ScriptViewport = require("scripts/foundation/utilities/script_viewport")
local ScriptWorld = require("scripts/foundation/utilities/script_world")

local _calculate_smoothed_look = Shared._calculate_smoothed_look
local _cleanup_all = Shared._cleanup_all
local _sync_replay_clock_scale = Shared._sync_replay_clock_scale

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
						mod._ff_smooth_x,
						mod._ff_smooth_y,
						dt,
						mod._mouse_smoothing_amount or 0.65,
						mod._mouse_smoothing_speed or 1.0
					)
					mod._ff_smooth_x = new_x
					mod._ff_smooth_y = new_y
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

	_hook_play("free_cam_step_speed", function(func, ...)
		local speed = func(...)
		if mod:is_enabled() and mod._move_speed_enabled and speed then
			return speed * (mod._move_speed or 1.0)
		end
		return speed
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
			if mod:is_enabled() and not mod._in_sync_hud then
				mod._in_sync_hud = true
				mod.set_hide_hud(RUI.hud_hidden)
				mod._in_sync_hud = false
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

Shared._setup_replays_integration = _setup_replays_integration
