local Sift = require(script.Parent.Parent.Sift)
local DarkTheme = require(script.Parent.SourceCode.Client.UI.Themes.Dark)

export type Item = {
	Id: number,
	ItemType: Enum.AvatarItemType,
}
export type CoreGuiItem = "Chat" | "PlayerList" | "Backpack" | "Captures" | "Emotes" | "TouchControls"
export type EditMode = "Marketplace" | "Inventory" | "Customize" | "Outfits" | "Shared"
export type Config = {
	Theme: any?,
	DataStoreEnabled: boolean?,
	AvatarSavingAllowed: boolean?,
	Featured: {
		Items: { Item }?,
	}?,
	HiddenCoreGui: { CoreGuiItem }?,
	Limits: {
		Accessories: number?,
	}?,
	EditModes: { EditMode }?,
	-- EasyLoader only: false hides the top bar button (for games with their own open buttons)
	TopbarIcon: boolean?,
}

local CONFIG_TEMPLATE: Config = {
	Theme = DarkTheme,
	DataStoreEnabled = true,
	AvatarSavingAllowed = true,
	Featured = {
		Items = {},
	},
	Limits = {
		Accessories = 10,
	},
	HiddenCoreGui = { "PlayerList", "Captures", "Emotes", "TouchControls" },
	EditModes = { "Marketplace", "Inventory", "Customize", "Outfits", "Shared" },
}

--[=[
	@class Config
]=]
--[=[
	@interface Config
	@within Config

	@field Theme Theme?
	@field DataStoreEnabled boolean?
	@field AvatarSavingAllowed boolean?
	@field Featured { Items: { Item }? }?
	@field HiddenCoreGui { CoreGuiItem }?
	@field Limits { Accessories: number? }?
	@field EditModes { EditMode }?
	@field TopbarIcon boolean?
]=]
--[=[
	@type CoreGuiItem string
	@within Config

	Valid CoreGui strings: "Chat" | "PlayerList" | "Backpack" | "Captures" | "Emotes" | "TouchControls"
]=]
--[=[
	@type Theme Theme
	@within Config

	The default dark theme can be [found here](https://github.com/Loneka/Avalog/blob/main/src/Client/UI/Themes/Dark.luau) for reference.
]=]
local Config = {
	Data = CONFIG_TEMPLATE,
}

function Config:Update(Data)
	Config.Data = Sift.Dictionary.merge(Config.Data, Data)
end

function Config:Get()
	return Sift.Dictionary.copyDeep(Config.Data)
end

return Config
