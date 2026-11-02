-- Saved outfits: each player can keep up to MAX_OUTFITS named avatars in their
-- Avalog profile. Wearing one is done by the client through UpdateAvatar, so it
-- goes through the same checks and saving as any other avatar change.

local TextService = game:GetService("TextService")

local Avalog = script.Parent.Parent.Parent
local Zap = require(Avalog.SourceCode.Shared.Zap.server)
local RateLimit = require(Avalog.Parent.RateLimit)
local EnumSerDes = require(Avalog.Parent.EnumSerDes)
local Squash = require(Avalog.Parent.Squash)
local Sift = require(Avalog.Parent.Sift)
local PlayerDataStore = require(Avalog.SourceCode.Server.PlayerDataStorage.PlayerDataStore)
local AvatarDataSerDes = require(Avalog.SourceCode.Server.PlayerDataStorage.SerDes.AvatarData)
local SharedOutfits = require(Avalog.SourceCode.Shared.Outfits)
local Config = require(Avalog.Config)

local CONFIG = Config:Get()
local RATE_LIMITS = {
	Read = RateLimit(5, 5),
	Write = RateLimit(6, 10),
}

local Outfits = {}

type Result = {
	Ok: boolean,
	Message: string?,
	Outfits: { any },
}

-- Decodes the stored outfits into the shape Zap sends to the client.
-- The profile's saved outfits, or nil while its data is still loading.
local function StoredOutfits(Profile): { any }?
	local Data = Profile and Profile.Data:Get()
	if Data == nil then
		return nil
	end
	return Data.Outfits or {}
end

local function ListFor(Profile): { any }
	local Stored = StoredOutfits(Profile) or {}
	local List = {}

	for _, Outfit in ipairs(Stored) do
		local Ok, AvatarData = pcall(function()
			return AvatarDataSerDes.des(Squash.frombuffer(Outfit.Data))
		end)

		if Ok then
			table.insert(List, {
				Name = Outfit.Name,
				Data = EnumSerDes.SerializeTree(AvatarData),
			})
		end
	end

	return List
end

local function Reply(Profile, Ok: boolean, Message: string?): Result
	return {
		Ok = Ok,
		Message = Message,
		Outfits = ListFor(Profile),
	}
end

-- Returns the player's profile, or nil and a reason it can't be used.
local function GetProfile(Player: Player)
	if not CONFIG.DataStoreEnabled then
		return nil, "Saving outfits is turned off in this game."
	end

	local Profile = PlayerDataStore:Get(Player)
	if Profile == nil or StoredOutfits(Profile) == nil then
		return nil, "Your saved outfits are still loading. Try again in a moment."
	end

	return Profile, nil
end

local function FilterName(Player: Player, Name: string): string?
	local Ok, Result = pcall(function()
		local Filtered = TextService:FilterStringAsync(Name, Player.UserId)
		return Filtered:GetNonChatStringForUserAsync(Player.UserId)
	end)

	if Ok and type(Result) == "string" then
		return SharedOutfits.CleanName(Result)
	end

	return nil
end

function Outfits:Get(Player: Player): Result
	local Profile, Problem = GetProfile(Player)
	if Profile == nil then
		return Reply(nil, false, Problem)
	end

	return Reply(Profile, true, nil)
end

function Outfits:Save(Player: Player, Name: string, Data): Result
	local Profile, Problem = GetProfile(Player)
	if Profile == nil then
		return Reply(nil, false, Problem)
	end

	local Stored = StoredOutfits(Profile) :: { any }
	if #Stored >= SharedOutfits.MAX_OUTFITS then
		return Reply(Profile, false, `You can save up to {SharedOutfits.MAX_OUTFITS} outfits. Delete one first.`)
	end

	-- Re-encoding checks the avatar data is well formed.
	local Ok, Encoded = pcall(function()
		local AvatarData = EnumSerDes.DeserializeTree(Data)
		if #AvatarData.Accessories > CONFIG.Limits.Accessories then
			AvatarData.Accessories = Sift.Array.slice(AvatarData.Accessories, 1, CONFIG.Limits.Accessories)
		end

		local Cursor = Squash.cursor()
		AvatarDataSerDes.ser(Cursor, AvatarData)
		return Squash.tobuffer(Cursor)
	end)
	if not Ok then
		return Reply(Profile, false, "That avatar couldn't be saved.")
	end

	local CleanName = SharedOutfits.CleanName(Name)
	if CleanName == "" then
		CleanName = `Outfit {#Stored + 1}`
	end

	local SafeName = FilterName(Player, CleanName)
	if SafeName == nil then
		return Reply(Profile, false, "Couldn't check that name. Try again.")
	end
	if SafeName == "" then
		SafeName = `Outfit {#Stored + 1}`
	end

	Profile.Session:patch(PlayerDataStore.Actions.AddOutfit, SafeName, Encoded)

	return Reply(Profile, true, `Saved "{SafeName}".`)
end

function Outfits:Rename(Player: Player, Index: number, Name: string): Result
	local Profile, Problem = GetProfile(Player)
	if Profile == nil then
		return Reply(nil, false, Problem)
	end

	local Stored = StoredOutfits(Profile) :: { any }
	if Stored[Index] == nil then
		return Reply(Profile, false, "That outfit no longer exists.")
	end

	local CleanName = SharedOutfits.CleanName(Name)
	if CleanName == "" then
		return Reply(Profile, false, "Type a name first.")
	end

	local SafeName = FilterName(Player, CleanName)
	if SafeName == nil or SafeName == "" then
		return Reply(Profile, false, "Couldn't check that name. Try again.")
	end

	Profile.Session:patch(PlayerDataStore.Actions.RenameOutfit, Index, SafeName)

	return Reply(Profile, true, `Renamed to "{SafeName}".`)
end

function Outfits:Delete(Player: Player, Index: number): Result
	local Profile, Problem = GetProfile(Player)
	if Profile == nil then
		return Reply(nil, false, Problem)
	end

	local Stored = StoredOutfits(Profile) :: { any }
	local Outfit = Stored[Index]
	if Outfit == nil then
		return Reply(Profile, false, "That outfit no longer exists.")
	end

	Profile.Session:patch(PlayerDataStore.Actions.DeleteOutfit, Index)

	return Reply(Profile, true, `Deleted "{Outfit.Name}".`)
end

-- Rate limits a request and always answers, even when the handler errors
-- (Zap leaves the client waiting forever otherwise).
local function Handle(Player: Player, Limit, Handler: () -> Result): Result
	if not Limit(Player.UserId) then
		return Reply(PlayerDataStore:Get(Player), false, "Slow down a little and try again.")
	end

	local Ok, Result = pcall(Handler)
	if Ok then
		return Result
	end

	warn("[Avalog] Outfit request failed:", Result)

	local ProfileOk, Profile = pcall(PlayerDataStore.Get, PlayerDataStore, Player)
	local ReplyOk, Fallback = pcall(Reply, ProfileOk and Profile or nil, false, "Something went wrong. Try again.")
	if ReplyOk then
		return Fallback
	end

	return { Ok = false, Message = "Something went wrong. Try again.", Outfits = {} }
end

function Outfits:Start()
	Zap.GetOutfits.SetCallback(function(Player)
		return Handle(Player, RATE_LIMITS.Read, function()
			return Outfits:Get(Player)
		end)
	end)

	Zap.SaveOutfit.SetCallback(function(Player, Name, Data)
		return Handle(Player, RATE_LIMITS.Write, function()
			return Outfits:Save(Player, Name, Data)
		end)
	end)

	Zap.RenameOutfit.SetCallback(function(Player, Index, Name)
		return Handle(Player, RATE_LIMITS.Write, function()
			return Outfits:Rename(Player, Index, Name)
		end)
	end)

	Zap.DeleteOutfit.SetCallback(function(Player, Index)
		return Handle(Player, RATE_LIMITS.Write, function()
			return Outfits:Delete(Player, Index)
		end)
	end)
end

return Outfits
