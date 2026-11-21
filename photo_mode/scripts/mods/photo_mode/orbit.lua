local mod = get_mod("photo_mode")
local Shared = mod._shared

local _ensure_replay_free_cam = Shared._ensure_replay_free_cam
local _exit_free_flight = Shared._exit_free_flight
local _get_camera_transform = Shared._get_camera_transform
local _get_level_world = Shared._get_level_world
local _get_own_character_unit = Shared._get_own_character_unit
local _get_spectated_puppet_unit = Shared._get_spectated_puppet_unit
local _update_rig_perspective = Shared._update_rig_perspective

local function _get_unit_heading_rotation(unit)
	if not unit or not Unit.alive(unit) then
		return nil
	end

	local fp_ext = ScriptUnit.has_extension(unit, "first_person_system")
	if fp_ext and fp_ext.extrapolated_rotation then
		return fp_ext:extrapolated_rotation()
	end

	return Unit.world_rotation(unit, 1)
end

local function _get_unit_shoulder_center(unit, side_offset)
	local pos = Unit.world_position(unit, 1) + Vector3(0, 0, 1.1)
	if side_offset and side_offset ~= 0 then
		local rot = _get_unit_heading_rotation(unit) or Unit.world_rotation(unit, 1)
		local right = Vector3.flat(Quaternion.right(rot))
		local len = Vector3.length(right)
		if len > 0.001 then
			pos = pos + (right / len) * side_offset
		end
	end
	return pos
end

local function _get_orbit_center()
	local target_mode = mod:get("orbit_target_mode") or "follow"
	local side_offset = mod:get("orbit_side_offset") or 0.0

	if target_mode == "character" or target_mode == "follow" then
		local spectated_unit = _get_spectated_puppet_unit()
		if spectated_unit and Unit.alive(spectated_unit) then
			return _get_unit_shoulder_center(spectated_unit, side_offset)
		end

		local unit = _get_own_character_unit()
		if unit and Unit.alive(unit) then
			return _get_unit_shoulder_center(unit, side_offset)
		end

		if mod._orbit_smooth_center then
			return mod._orbit_smooth_center:unbox()
		end
	end

	if mod._orbit_center then
		return mod._orbit_center:unbox()
	end

	local spectated_unit = _get_spectated_puppet_unit()
	if spectated_unit and Unit.alive(spectated_unit) then
		return _get_unit_shoulder_center(spectated_unit, side_offset)
	end

	local unit = _get_own_character_unit()
	if unit and Unit.alive(unit) then
		return _get_unit_shoulder_center(unit, side_offset)
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
			local hit, hit_pos = PhysicsWorld.raycast(
				physics_world,
				pos,
				fwd,
				50,
				"closest",
				"types",
				"statics",
				"collision_filter",
				"filter_player_character_shooting_raycast_statics"
			)
			if hit then
				center = hit_pos
			end
		end
	end

	if not center then
		local side_offset = mod:get("orbit_side_offset") or 0.0
		local unit = _get_own_character_unit()
		if unit and Unit.alive(unit) then
			center = _get_unit_shoulder_center(unit, side_offset)
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

		local target_mode = mod:get("orbit_target_mode") or "follow"
		if target_mode == "character" or target_mode == "follow" then
			mod._orbit_angle = 0
			mod:set("orbit_angle", 0, true)
		else
			mod._orbit_angle = math.rad(mod:get("orbit_angle") or 0)
		end

		if not pos or not rot then
			pos, rot = _get_camera_transform()
		end
		if pos and rot then
			mod._orbit_pos = Vector3Box(pos)
			mod._orbit_rot = QuaternionBox(rot)
		end

		mod._orbit_smooth_center = nil
		mod._orbit_smooth_fwd = nil
		mod._orbit_active = true
		mod._orbit_paused = true
		mod:set("orbit_active", true)
		mod:set("orbit_paused", true)
		_exit_free_flight()
		_update_rig_perspective()
		if not mod._silent_reset then
			mod:echo(mod:localize("msg_orbit_started"))
		end
	else
		mod._orbit_active = false
		mod._orbit_paused = true
		mod._orbit_pos = nil
		mod._orbit_rot = nil
		mod._orbit_smooth_center = nil
		mod._orbit_smooth_fwd = nil
		mod._orbit_smooth_height_drop = 0
		mod._orbit_smooth_pitch_give = 0
		mod:set("orbit_active", false)
		mod:set("orbit_paused", true)
		_update_rig_perspective()
		if not mod._silent_reset then
			mod:echo(mod:localize("msg_orbit_stopped"))
		end
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
		mod.set_orbit_paused(false)
		return
	end

	mod.set_orbit_paused(not mod._orbit_paused)
end

mod.toggle_orbit = function()
	mod:set("orbit_active", not mod:get("orbit_active"), true)
end

Shared._get_orbit_center = _get_orbit_center
Shared._get_unit_heading_rotation = _get_unit_heading_rotation
