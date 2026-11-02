local Avalog = script.Parent.Parent.Parent.Parent
local Fusion = require(Avalog.Parent.Fusion)
local Types = require(Avalog.SourceCode.Shared.Types)

local Scope = Fusion.scoped(Fusion)

local States = {
	Theme = Scope:Value(nil),
	Catalog = {
		SearchQuery = Scope:Value(""),
		Mode = Scope:Value(1),
		Category = Scope:Value(1),
		SubCategory = Scope:Value(1),
	},
	ItemDetails = {
		Open = Scope:Value(false) :: Fusion.Value<boolean>,
		ItemType = Scope:Value(Enum.AvatarItemType.Asset) :: Fusion.Value<Enum.AvatarItemType>,
		ItemId = Scope:Value(0) :: Fusion.Value<number>,
	},
	Avatar = {
		Data = Scope:Value(nil),
		DataHistory = Scope:Value({}),
		UndoHistory = Scope:Value({}),
		AssetIds = Scope:Value({}),
		EquippedAssetIds = Scope:Value({}),
		EquippedBundleIds = Scope:Value({}),
		Character = Scope:Value(nil),
		Loaded = Scope:Value(false),
		-- How many equipped items the player doesn't own (for the Buy button)
		UnownedCount = Scope:Value(0),
	},
	Outfits = {
		List = Scope:Value({}) :: Fusion.Value<{ { Name: string, Data: any } }>,
		Loaded = Scope:Value(false),
		Busy = Scope:Value(false),
		Message = Scope:Value(nil) :: Fusion.Value<{ Text: string, Ok: boolean }?>,
	},
	SharedAvatars = {
		List = Scope:Value({}) :: Fusion.Value<{ any }>,
		Loaded = Scope:Value(false),
		Busy = Scope:Value(false),
		-- Whether the local player has an avatar shared right now
		Mine = Scope:Value(false),
		Message = Scope:Value(nil) :: Fusion.Value<{ Text: string, Ok: boolean }?>,
	},
	Checkout = {
		Loading = Scope:Value(false),
	},
	Inventory = {
		AccessAllowed = Scope:Value(false),
	},
	Featured = {
		MessageShown = Scope:Value(true),
		PrefixItems = Scope:Value({}),
		Creators = Scope:Value({}),
	},
	CloudConfig = Scope:Value(Types.AvalogConfig.Fallback) :: Types.AvalogConfig,
	Screen = {
		Resolution = Scope:Value(Vector2.new()),
	},
	UnixTimestamp = Scope:Value(0),
	Open = Scope:Value(false),
}

return States
