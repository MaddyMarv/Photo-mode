return {
	run = function()
		fassert(rawget(_G, "new_mod"), "`photo_mode` encountered an error loading the Darktide Mod Framework.")

		new_mod("photo_mode", {
			mod_script       = "photo_mode/scripts/mods/photo_mode/photo_mode",
			mod_data         = "photo_mode/scripts/mods/photo_mode/photo_mode_data",
			mod_localization = "photo_mode/scripts/mods/photo_mode/photo_mode_localization",
		})
	end,
	packages = {},
}
