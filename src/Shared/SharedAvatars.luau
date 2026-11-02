-- Rules shared by the client and server for shared avatars.
-- The limits must match the ones in config.zap.

local Outfits = require(script.Parent.Outfits)

local SharedAvatars = {
	-- How many of the newest shared avatars are listed
	MAX_LISTED = 60,
	MAX_CAPTION_BYTES = 60,
	MAX_DISPLAY_NAME_BYTES = 100,
}

-- Trims and shortens text to MaxBytes without splitting a UTF-8 character.
SharedAvatars.Clean = Outfits.CleanText

return SharedAvatars
