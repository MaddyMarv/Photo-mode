local mod = get_mod("photo_mode")
local Shared = mod._shared

local ScriptCamera = require("scripts/foundation/utilities/script_camera")
local ScriptViewport = require("scripts/foundation/utilities/script_viewport")
local ScriptWorld = require("scripts/foundation/utilities/script_world")

local HUD_VISIBILITY_GROUP = Shared.HUD_VISIBILITY_GROUP
local _wrap_freeflight_input = Shared._wrap_freeflight_input

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
	if mod._typing then
		if action == "move" then
			return Vector3(0, 0, 0)
		end

		local value = func(self, action, ...)
		if type(value) == "boolean" then
			return false
		end
		return value
	end

	if mod:is_enabled() and mod._menu_open then
		local actions_allowed = mod._actions_allowed ~= false
		local menu_input_active = mod._menu_hovered

		if not actions_allowed or menu_input_active then
			if
				action == "action_one_pressed"
				or action == "action_one_hold"
				or action == "action_one_release"
				or action == "action_two_pressed"
				or action == "action_two_hold"
				or action == "action_two_release"
				or action == "weapon_reload"
				or action == "wield"
			then
				return false
			end
		end
	end

	return func(self, action, ...)
end)

mod:hook("HumanGameplay", "_get_input", function(func, self)
	local input = func(self)
	if mod._lock_character then
		return input:null_service()
	end
	return input
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
	if input and mod:is_enabled() and mod._menu_open and (mod._camera_locked or mod._typing) then
		input = input:null_service()
	end

	return func(self, dt, t, player_orientation, input)
end)

mod:hook("ConstantElementChat", "_handle_keyboard_input", function(func, self, ...)
	if mod._typing then
		return
	end

	return func(self, ...)
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

mod:hook("OutlineSystem", "update", function(func, self, context, dt, t)
	if mod:is_enabled() and mod._hide_outlines then
		self._visible = false
		self:_hide_all_outlines()
		return
	end

	self._visible = true
	return func(self, context, dt, t)
end)

mod:hook("OutlineSystem", "_show_outline", function(func, self, unit, extension)
	if mod:is_enabled() and mod._hide_outlines then
		return
	end

	return func(self, unit, extension)
end)

mod:hook("OutlineSystem", "_cinematic_active", function(func, self)
	if mod:is_enabled() and mod._hide_outlines then
		return true
	end

	return func(self)
end)

mod:hook("PlayerUnitHologramExtension", "update", function(func, self, unit, dt, t)
	if mod:is_enabled() and mod._hide_outlines then
		local hologram_unit = self._hologram_unit
		if hologram_unit then
			if self._world and Unit.alive(hologram_unit) then
				World.unlink_unit(self._world, hologram_unit, true)
				World.destroy_unit(self._world, hologram_unit)
			end
			self._hologram_unit = nil
		end
		return
	end

	return func(self, unit, dt, t)
end)

mod:hook(
	"CameraManager",
	"_update_camera_properties",
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
				camera_data.vertical_fov =
					math.clamp(camera_data.vertical_fov + math.rad(mod._fov_offset), math.rad(10), math.rad(150))
			end
		end

		func(self, camera, shadow_cull_camera, camera_nodes, camera_data, viewport_name)

		if mod:is_enabled() and mod._lock_fov and camera then
			local base_user_fov = Application.user_setting("render_settings", "vertical_fov") or 65
			local fov_offset = mod._fov_offset or mod:get("camera_fov_offset") or 0
			local locked_fov_rad = math.clamp(math.rad(base_user_fov + fov_offset), math.rad(10), math.rad(150))
			Camera.set_vertical_fov(camera, locked_fov_rad)
			if shadow_cull_camera then
				Camera.set_vertical_fov(shadow_cull_camera, locked_fov_rad)
			end
			if camera_data and camera_data.custom_vertical_fov then
				Camera.set_custom_vertical_fov(camera, locked_fov_rad)
			end
		end
	end
)

mod:hook_safe(
	"CameraManager",
	"shading_callback",
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
	end
)

mod:hook("FreeFlightManager", "camera", function(func, self, camera_id)
	local data = self._free_flight_cameras and self._free_flight_cameras[camera_id]
	if not data or not data.viewport_world_name then
		return false
	end

	local world = Managers.world
		and Managers.world:has_world(data.viewport_world_name)
		and Managers.world:world(data.viewport_world_name)
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

	local world = Managers.world
		and Managers.world:has_world(camera_data.viewport_world_name)
		and Managers.world:world(camera_data.viewport_world_name)
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

	if input and mod:is_enabled() and (mod._mouse_smoothing or (mod._move_speed_enabled and mod._move_speed ~= 1)) then
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
	if
		mod:is_enabled()
		and mod._screen_effects_hidden
		and particle_name
		and string.find(particle_name, "screenspace")
	then
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

mod:hook(
	"MoodHandler",
	"_update_particles",
	function(func, self, added_moods, removing_moods, removed_moods, moods_data)
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
	end
)
