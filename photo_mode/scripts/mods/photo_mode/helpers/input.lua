local mod = get_mod("photo_mode")
local Shared = mod._shared

mod._ff_smooth_x = 0
mod._ff_smooth_y = 0
local _player_smooth_x = 0
local _player_smooth_y = 0

mod._reset_mouse_smoothing = function()
	mod._ff_smooth_x = 0
	mod._ff_smooth_y = 0
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

local _ff_move_actions = {
	move_right = true,
	move_left = true,
	move_forward = true,
	move_backward = true,
	move_up = true,
	move_down = true,
	move_controller = true,
}

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
	end,
}
setmetatable(_ff_input_proxy, _ff_proxy_mt)

function _ff_input_proxy:get(action_name, ...)
	if not _ff_current_input then
		return false
	end

	if action_name == "look" and mod._mouse_smoothing then
		local raw_look = _ff_current_input:get("look", ...)
		local smoothed_look, new_x, new_y = _calculate_smoothed_look(
			raw_look,
			mod._ff_smooth_x,
			mod._ff_smooth_y,
			_ff_current_dt,
			mod._mouse_smoothing_amount or 0.65,
			mod._mouse_smoothing_speed or 1.0
		)
		mod._ff_smooth_x = new_x
		mod._ff_smooth_y = new_y
		return smoothed_look
	end

	local val = _ff_current_input:get(action_name, ...)
	if val and _ff_move_actions[action_name] then
		return val * (mod._move_speed_enabled and mod._move_speed or 1.0)
	end

	return val
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
	end,
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

mod:hook(
	"DefaultPlayerOrientation",
	"pre_update",
	function(func, self, main_t, main_dt, input, sensitivity_modifier, rotation_contraints)
		if input and mod:is_enabled() then
			if mod._menu_open and (mod._camera_locked or mod._typing) then
				input = input:null_service()
			elseif mod._mouse_smoothing then
				input = _wrap_player_input(input, main_dt)
			end
		end

		return func(self, main_t, main_dt, input, sensitivity_modifier, rotation_contraints)
	end
)

mod:hook(
	"HubPlayerOrientation",
	"pre_update",
	function(func, self, main_t, main_dt, input, sensitivity_modifier, rotation_contraints)
		if input and mod:is_enabled() then
			if mod._menu_open and (mod._camera_locked or mod._typing) then
				input = input:null_service()
			elseif mod._mouse_smoothing then
				input = _wrap_player_input(input, main_dt)
			end
		end

		return func(self, main_t, main_dt, input, sensitivity_modifier, rotation_contraints)
	end
)

Shared._calculate_smoothed_look = _calculate_smoothed_look
Shared._wrap_freeflight_input = _wrap_freeflight_input
