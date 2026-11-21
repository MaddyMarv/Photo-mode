local mod = get_mod("photo_mode")
local Shared = mod._shared

local ScriptCamera = require("scripts/foundation/utilities/script_camera")
local ScriptViewport = require("scripts/foundation/utilities/script_viewport")
local ScriptWorld = require("scripts/foundation/utilities/script_world")

local _ensure_free_flight_active = Shared._ensure_free_flight_active
local _get_camera_transform = Shared._get_camera_transform
local _get_level_world = Shared._get_level_world
local _is_replay_active = Shared._is_replay_active
local _update_rig_perspective = Shared._update_rig_perspective

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

	mod:echo(
		mod:localize("msg_dolly_point_added")
			.. ": Point "
			.. tostring(name)
			.. " ("
			.. tostring(#mod._dolly_points)
			.. " total)"
	)
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
	mod:echo(
		mod:localize("msg_dolly_point_undone")
			.. ": Point "
			.. tostring(pt_name)
			.. " ("
			.. tostring(remaining)
			.. " left)"
	)
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
		mod:echo(
			mod:localize("msg_dolly_point_selected")
				.. ": Point "
				.. tostring(pt.name)
				.. " ("
				.. tostring(index)
				.. " of "
				.. tostring(count)
				.. ")"
		)
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
	mod:echo(
		mod:localize("msg_dolly_point_deleted")
			.. ": Point "
			.. tostring(pt_name)
			.. " ("
			.. tostring(remaining)
			.. " left)"
	)
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
			local ff_viewport = ScriptWorld.global_free_flight_viewport
				and ScriptWorld.global_free_flight_viewport(world)
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
		if not mod._silent_reset then
			mod:echo(mod:localize("msg_dolly_started"))
		end
	else
		mod._dolly_active = false
		mod._dolly_pos = nil
		mod._dolly_rot = nil
		mod._fov_offset = mod:get("camera_fov_offset") or 0
		mod:set("dolly_active", false)
		_update_rig_perspective()
		if not mod._silent_reset then
			mod:echo(mod:localize("msg_dolly_stopped"))
		end
	end
end

mod.toggle_dolly = function()
	mod:set("dolly_active", not mod:get("dolly_active"), true)
end
