local Avalog = script.Parent.Parent.Parent.Parent
local Squash = require(Avalog.Parent.Squash)
local DataValidater = require(script.Parent.DataValidater)
local NewPlayerDataStore = require(Avalog.SourceCode.Storage.Utils.PlayerDataStore)
local AvatarDataSerDes = require(script.Parent.SerDes.AvatarData)
local HumanoidDescriber = require(Avalog.Parent.HumanoidDescriber)

export type SavedOutfit = {
	Name: string,
	Data: buffer,
}

export type PlayerData = {
	Avatar: {
		Data: buffer?,
	},
	-- Missing in data saved before outfits existed.
	Outfits: { SavedOutfit }?,
}

local MAX_OUTFITS = require(Avalog.SourceCode.Shared.Outfits).MAX_OUTFITS

local PlayerDataStore = NewPlayerDataStore {
	name = "AvalogPlayerData",
	migrations = {},
	default_data = function()
		return {
			Avatar = {
				Data = nil,
			},
			Outfits = {},
		}
	end,
	schema = DataValidater,
	pull_delay = 60 * 2,
}

local Actions = {
	SetAvatarData = function(Data: PlayerData, AvatarData: HumanoidDescriber.Data)
		assert(AvatarData ~= nil, "Given AvatarData is nil")

		local Cursor = Squash.cursor()
		AvatarDataSerDes.ser(Cursor, AvatarData)

		Data.Avatar.Data = Squash.tobuffer(Cursor)

		return Data
	end,

	-- Outfit actions return nil (no change) when the request no longer fits the data.
	AddOutfit = function(Data: PlayerData, Name: string, OutfitData: buffer)
		local List = Data.Outfits or {}
		if #List >= MAX_OUTFITS then
			return nil
		end

		table.insert(List, { Name = Name, Data = OutfitData })
		Data.Outfits = List

		return Data
	end,

	RenameOutfit = function(Data: PlayerData, Index: number, Name: string)
		local Outfit = Data.Outfits and Data.Outfits[Index]
		if Outfit == nil then
			return nil
		end

		Outfit.Name = Name

		return Data
	end,

	DeleteOutfit = function(Data: PlayerData, Index: number)
		if Data.Outfits == nil or Data.Outfits[Index] == nil then
			return nil
		end

		table.remove(Data.Outfits, Index)

		return Data
	end,
}

PlayerDataStore.Store:action(Actions.SetAvatarData)
PlayerDataStore.Store:action(Actions.AddOutfit)
PlayerDataStore.Store:action(Actions.RenameOutfit)
PlayerDataStore.Store:action(Actions.DeleteOutfit)

PlayerDataStore.Actions = Actions

return PlayerDataStore
