local GroupService = game:GetService("GroupService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

local Avalog = script.Parent.Parent.Parent.Parent.Parent
local OnyxUI = require(Avalog.Parent.OnyxUI)
local Fusion = require(Avalog.Parent.Fusion)
local States = require(Avalog.SourceCode.Client.UI.States)
local ServiceProvider = require(Avalog.SourceCode.Client.ServiceProvider)
local CatalogItems = require(Avalog.SourceCode.Client.UI.StateExtensions.CatalogItems)
local ColorUtils = require(Avalog.Parent.ColorUtils)

local Children = Fusion.Children

local ITEM_TYPE_INFO_TYPES = {
	[Enum.AvatarItemType.Asset] = Enum.InfoType.Asset,
	[Enum.AvatarItemType.Bundle] = Enum.InfoType.Bundle,
}
local THUMBNAIL_TYPES = {
	[Enum.AvatarItemType.Bundle] = "BundleThumbnail",
	[Enum.AvatarItemType.Asset] = "Asset",
}

local CustomButton = require(script.Parent.CustomButton)

-- One cosmetic lookup shared by every button, instead of each button scanning the list
local SharedScope = Fusion.scoped(Fusion)
local CosmeticItemsById = SharedScope:Computed(function(Use)
	local Lookup = {}
	local CloudConfigValue = Use(States.CloudConfig)

	if CloudConfigValue ~= nil and CloudConfigValue.cosmeticItems ~= nil then
		for _, Item in CloudConfigValue.cosmeticItems do
			Lookup[Item.itemId] = Item
		end
	end

	return Lookup
end)

export type Props = CustomButton.Props & {
	Id: Fusion.UsedAs<number?>?,
	Type: Fusion.UsedAs<Enum.AvatarItemType>?,
	Owned: Fusion.UsedAs<boolean>?,
	Featured: Fusion.UsedAs<boolean>?,
}

return function(Scope: Fusion.Scope<any>, Props: Props)
	local Scope = Fusion.innerScope(Scope, Fusion, OnyxUI.Util, OnyxUI.Components, {
		CustomButton = CustomButton,
	})
	local Theme = OnyxUI.Themer.Theme:now()
	local AvatarManager = ServiceProvider:GetAvatarManager()

	-- Id and Type may be states, so ItemsTab can reuse one button for different items.
	-- (Util.Fallback is avoided here: it drops a state whose current value is nil.)
	local IdProp = Props.Id
	local TypeProp = if Props.Type ~= nil then Props.Type else Enum.AvatarItemType.Asset
	local Featured = OnyxUI.Util.Fallback(Props.Featured, false)

	-- A pooled button that is emptied (hidden) keeps showing its last item,
	-- so hiding and refilling it later costs nothing extra.
	local LastId = Fusion.peek(IdProp)
	local LastType = Fusion.peek(TypeProp)
	local Id = Scope:Computed(function(Use)
		local IdValue = Use(IdProp)
		if IdValue ~= nil then
			LastId = IdValue
		end
		return LastId
	end)
	local Type = Scope:Computed(function(Use)
		local TypeValue = Use(TypeProp)
		if Use(IdProp) ~= nil then
			LastType = TypeValue
		end
		return LastType
	end)

	local Alive = true
	table.insert(Scope, function()
		Alive = false
	end)

	local ItemKey = Scope:Computed(function(Use)
		local IdValue = Use(Id)
		if IdValue == nil then
			return ""
		end
		return `{Use(Type)}:{IdValue}`
	end)

	local ItemInfo = Scope:Value(nil)
	local function UpdateItemInfo()
		local IdValue = Fusion.peek(Id)
		local InfoType = ITEM_TYPE_INFO_TYPES[Fusion.peek(Type)]

		if IdValue == nil or InfoType == nil then
			ItemInfo:set(nil)
			return
		end

		-- Search results are cached already, so most buttons fill in without a request
		local KnownItemInfo = CatalogItems:GetExistingItem(IdValue, InfoType)
		if KnownItemInfo then
			ItemInfo:set(KnownItemInfo)
			return
		end

		ItemInfo:set(nil)
		local RequestedKey = Fusion.peek(ItemKey)
		task.spawn(function()
			local FetchedItemInfo = CatalogItems:GetItem(IdValue, InfoType)
			-- Ignore the answer if this button shows another item by now
			if FetchedItemInfo and Alive and Fusion.peek(ItemKey) == RequestedKey then
				ItemInfo:set(FetchedItemInfo)
			end
		end)
	end
	Scope:Observer(ItemKey):onChange(function()
		UpdateItemInfo()
	end)
	UpdateItemInfo()

	local SafeItemInfo = Scope:Computed(function(Use)
		local ItemInfoValue = Use(ItemInfo)
		local IdValue = Use(Id)

		if ItemInfoValue then
			return ItemInfoValue
		else
			return {
				Id = IdValue,
				Name = "Name",
				Price = 0,
				Offsale = false,
				Type = Enum.AvatarItemType.Asset,
				AssetType = Enum.AvatarAssetType.Hat,
			}
		end
	end)
	local CosmeticItemInfo = Scope:Computed(function(Use)
		local IdValue = Use(Id)
		if IdValue == nil then
			return nil
		end
		return Use(CosmeticItemsById)[tostring(IdValue)]
	end)
	local Equipped = Scope:Computed(function(Use)
		local IdValue = Use(Id)
		local SafeItemInfoValue = Use(SafeItemInfo)

		if IdValue == nil then
			return false
		end

		if SafeItemInfoValue.Type == Enum.AvatarItemType.Asset then
			local AssetIdsValue = Use(States.Avatar.AssetIds)

			if
				SafeItemInfoValue.AssetType == Enum.AvatarAssetType.EmoteAnimation
				and AvatarManager.HumanoidDescriber ~= nil
			then
				if AvatarManager.HumanoidDescriber:GetEquippedEmote(SafeItemInfoValue.Name) == nil then
					return false
				end
			end

			return table.find(AssetIdsValue, IdValue) ~= nil
		else
			local BundleIdsValue = Use(States.Avatar.EquippedBundleIds)

			return table.find(BundleIdsValue, IdValue) ~= nil
		end
	end)
	local TintColor = Scope:Computed(function(Use)
		local CosmeticItemInfoValue = Use(CosmeticItemInfo)
		if CosmeticItemInfoValue and CosmeticItemInfoValue.tintColor then
			return Color3.fromHex(CosmeticItemInfoValue.tintColor)
		end
		return nil
	end)

	-- The Buy/details row is built the first time the item is equipped.
	-- Most buttons are never equipped, and the row holds two more buttons.
	local ActionsBuilt = Scope:Value(Fusion.peek(Equipped) == true)
	Scope:Observer(Equipped):onChange(function()
		if Fusion.peek(Equipped) and not Fusion.peek(ActionsBuilt) then
			ActionsBuilt:set(true)
		end
	end)

	return Scope:CustomButton(OnyxUI.Util.CombineProps(Props, {
		Name = script.Name,
		StrokeEnabled = Equipped,
		StrokeThickness = Theme.StrokeThickness["2"],
		StrokeColor = Theme.Colors.BaseContent.Main,
		ListEnabled = false,
		Color = Scope:Computed(function(Use)
			local DefaultColor = Use(Theme.Colors.Neutral.Main)
			if Use(TintColor) ~= nil then
				return ColorUtils.Blend.Transparency(DefaultColor, Use(TintColor), 0.85)
			else
				return DefaultColor
			end
		end),
		GradientEnabled = Scope:Computed(function(Use)
			return Use(TintColor) ~= nil
		end),
		GradientColor = ColorSequence.new(Color3.new(1, 1, 1)),
		GradientTransparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.25),
			NumberSequenceKeypoint.new(0.5, 0),
			NumberSequenceKeypoint.new(1, 0.25),
		}),
		GradientRotation = Scope:Computed(function(Use)
			-- Only tinted items animate, so only they follow the clock
			if Use(TintColor) == nil then
				return 0
			end
			return Use(States.UnixTimestamp) / 15 % 360 - 180
		end),

		OnActivated = function()
			local ItemInfoValue = Fusion.peek(ItemInfo)

			if ItemInfoValue then
				AvatarManager:ToggleCatalogItem(ItemInfoValue)
			end
		end,

		[Children] = {
			Scope:Frame {
				Name = "Details",
				ListEnabled = true,
				ListFillDirection = Enum.FillDirection.Vertical,
				ListHorizontalFlex = Enum.UIFlexAlignment.Fill,
				ListPadding = Scope:Computed(function(Use)
					return UDim.new(0, Use(Theme.Spacing["0.5"]))
				end),
				Padding = Scope:Computed(function(Use)
					return UDim.new(0, Use(Theme.Spacing["0.5"]))
				end),
				Size = UDim2.fromScale(1, 0),

				[Children] = {
					Scope:Image {
						BackgroundTransparency = 1,
						Image = Scope:Computed(function(Use)
							local IdValue = Use(Id)
							if IdValue == nil then
								return ""
							end

							return `rbxthumb://id={IdValue}&type={(THUMBNAIL_TYPES[Use(Type)] or "Asset")}&w=150&h=150`
						end),
						ScaleType = Enum.ScaleType.Fit,
						CornerRadius = Scope:Computed(function(Use)
							return UDim.new(0, Use(Theme.CornerRadius["1"]))
						end),
						Size = Scope:Computed(function(Use)
							local Offset = Use(Theme.TextSize["1"]) * 5
							return UDim2.fromOffset(Offset, Offset)
						end),
					},
					Scope:Frame {
						ListEnabled = true,
						ListFillDirection = Enum.FillDirection.Vertical,
						ListHorizontalFlex = Enum.UIFlexAlignment.Fill,
						ListPadding = Scope:Computed(function(Use)
							return UDim.new(0, Use(Theme.Spacing["0.5"]))
						end),

						[Children] = {
							Scope:Text {
								Text = Scope:Computed(function(Use)
									local SafeItemInfoValue = Use(SafeItemInfo)
									return SafeItemInfoValue.Name
								end),
								Size = Scope:Computed(function(Use)
									return UDim2.fromOffset(0, Use(Theme.TextSize["1"]) * 2)
								end),
								AutomaticSize = Enum.AutomaticSize.None,
								ClipsDescendants = true,
								RichText = false,
								AutoLocalize = false,
							},
							Scope:IconText {
								Content = Scope:Computed(function(Use)
									local ItemInfoValue = Use(ItemInfo)
									if ItemInfoValue and ItemInfoValue.Price then
										return {
											"rbxassetid://102562927562320",
											ItemInfoValue.Price,
										}
									else
										return { "Offsale" }
									end
								end),
								ListPadding = Scope:Computed(function(Use)
									return UDim.new(0, Use(Theme.Spacing["0.25"]))
								end),
								ListWraps = false,
								ContentWrapped = false,
								AutoLocalize = false,
							},
						},
					},
				},
			},
			Scope:Computed(function(Use, Scope)
				if not Use(ActionsBuilt) then
					return nil
				end

				-- Start hidden and grow in on the next frame, as before
				local RowReady = Scope:Value(false)
				task.defer(function()
					if Alive then
						RowReady:set(true)
					end
				end)

				return OnyxUI.Themer.Theme:is(Theme):during(function()
					return Scope:Frame {
						Name = "Actions",
						AnchorPoint = Vector2.new(0.5, 1),
						Position = UDim2.fromScale(0.5, 1),
						-- A fixed height: sizing the row from buttons that stretch to the row's own
						-- height could settle on a squashed bar with the label spilling out.
						Size = Scope:Computed(function(Use)
							return UDim2.new(1, 0, 0, Use(Theme.TextSize["1"]) + Use(Theme.Spacing["0.25"]) * 2.5)
						end),
						AutomaticSize = Enum.AutomaticSize.None,
						Scale = Scope:Spring(
							Scope:Computed(function(Use)
								if Use(Equipped) and Use(RowReady) then
									return 1
								else
									return 0
								end
							end),
							Theme.SpringSpeed["2"],
							Theme.SpringDampening["1.5"]
						),
						Selectable = Equipped,
						ListEnabled = true,
						ListFillDirection = Enum.FillDirection.Horizontal,
						ListVerticalFlex = Enum.UIFlexAlignment.Fill,
						ListPadding = Scope:Computed(function(Use)
							return UDim.new(0, Use(Theme.Spacing["0.5"]))
						end),

						[Children] = {
							Scope:Button {
								Content = Scope:Computed(function(Use)
									if Use(CosmeticItemInfo) and Use(CosmeticItemInfo).groupPurchase then
										return { "Join" }
									else
										return { "Buy" }
									end
								end),
								Color = Theme.Colors.Success.Main,
								FlexMode = Enum.UIFlexMode.Fill,

								OnActivated = function()
									if
										Fusion.peek(CosmeticItemInfo) and Fusion.peek(CosmeticItemInfo).groupPurchase
									then
										GroupService:PromptJoinAsync(Fusion.peek(CosmeticItemInfo).groupId)
									else
										MarketplaceService:PromptPurchase(Players.LocalPlayer, Fusion.peek(Id))
									end
								end,
							},
							Scope:IconButton {
								Image = "rbxassetid://13850025424",
								Size = UDim2.fromScale(0, 1),
								Color = Theme.Colors.Secondary.Main,
								AspectRatio = 1,

								OnActivated = function()
									States.ItemDetails.ItemType:set(Fusion.peek(Type))
									States.ItemDetails.ItemId:set(Fusion.peek(Id))
									States.ItemDetails.Open:set(not Fusion.peek(States.ItemDetails.Open))
								end,
							},
						},
					}
				end)
			end),
			Scope:Computed(function(Use, Scope)
				if Use(Featured) then
					return OnyxUI.Themer.Theme:is(Theme):during(function()
						return Scope:Icon {
							Image = "rbxassetid://13850331560",
							Size = Scope:Computed(function(Use)
								return UDim2.fromOffset(Use(Theme.TextSize["1.25"]), Use(Theme.TextSize["1.25"]))
							end),
						}
					end)
				end
				return nil
			end),
		},
	}))
end
