local mod = get_mod("photo_mode")

local UIWorkspaceSettings = require("scripts/settings/ui/ui_workspace_settings")
require("scripts/ui/hud/elements/hud_element_base")

local definitions = {
	scenegraph_definition = {
		screen = UIWorkspaceSettings.screen,
	},
	widget_definitions = {},
}

local HudElementPhotoModeMenu = class("HudElementPhotoModeMenu", "HudElementBase")

HudElementPhotoModeMenu.init = function(self, parent, draw_layer, start_scale)
	HudElementPhotoModeMenu.super.init(self, parent, draw_layer, start_scale, definitions)

	self._menu = mod:io_dofile("photo_mode/scripts/mods/photo_mode/hud/photo_mode_menu")

	if self._menu and self._menu.init then
		self._menu.init(self)
	end
end

HudElementPhotoModeMenu.update = function(self, dt, t, ui_renderer, render_settings, input_service)
	HudElementPhotoModeMenu.super.update(self, dt, t, ui_renderer, render_settings, input_service)

	if self._menu and self._menu.update then
		self._menu.update(self, dt, t, ui_renderer, render_settings, input_service)
	end
end

HudElementPhotoModeMenu._draw_widgets = function(self, dt, t, input_service, ui_renderer, render_settings)
	if self._menu and self._menu.draw then
		self._menu.draw(self, ui_renderer, render_settings)
	end
end

HudElementPhotoModeMenu.destroy = function(self, ui_renderer)
	if self._menu and self._menu.destroy then
		self._menu.destroy(self)
	end

	HudElementPhotoModeMenu.super.destroy(self, ui_renderer)
end

return HudElementPhotoModeMenu
