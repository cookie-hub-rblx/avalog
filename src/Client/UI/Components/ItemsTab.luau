local RunService = game:GetService("RunService")

local Avalog = script.Parent.Parent.Parent.Parent.Parent
local OnyxUI = require(Avalog.Parent.OnyxUI)
local Fusion = require(Avalog.Parent.Fusion)
local States = require(Avalog.SourceCode.Client.UI.States)

local Children = Fusion.Children
local Out = Fusion.Out
local OnChange = Fusion.OnChange

-- Time per frame spent building new item buttons (at least one is built per frame)
local BUILD_BUDGET_SECONDS = 0.004
-- Most cards in one row on wide screens
local MAX_COLUMNS = 8

export type Props = { [string]: any } & {
	Shown: Fusion.UsedAs<boolean>?,
	Items: Fusion.UsedAs<{ [string]: any }>?,
	OnReachedEnd: Fusion.UsedAs<() -> ()>?,
}

return function(Scope: Fusion.Scope<any>, Props: Props)
	local Scope = Fusion.innerScope(Scope, Fusion, OnyxUI.Util, OnyxUI.Components, {
		ItemButton = require(script.Parent.ItemButton),
	})
	local Theme = OnyxUI.Themer.Theme:now()

	local Shown = OnyxUI.Util.Fallback(Props.Shown, false)
	local Items = OnyxUI.Util.Fallback(Props.Items, {})
	local OnReachedEnd = OnyxUI.Util.Fallback(Props.OnReachedEnd, function() end)

	local AbsoluteCanvasSize = Scope:Value(Vector2.new())
	local AbsoluteWindowSize = Scope:Value(Vector2.new())

	-- The grid works out how many cards fit in a row and gives every card the same width.
	-- (A wrapping list set to "fill" stretched a lone card on the last row across the whole row.)
	local GridWidth = Scope:Value(Vector2.new())
	local Gap = Scope:Computed(function(Use)
		return Use(Theme.Spacing["1"])
	end)
	local CardSize = Scope:Computed(function(Use)
		local WidthValue = Use(GridWidth).X
		local GapValue = Use(Gap)
		local MinWidth = Use(Theme.Spacing["8"])
		local Columns = math.clamp(math.floor((WidthValue + GapValue) / (MinWidth + GapValue)), 1, MAX_COLUMNS)
		-- Whole pixels, rounded down, so rounding never pushes the last card onto the next row
		return UDim2.fromOffset(math.floor((WidthValue - GapValue * (Columns - 1)) / Columns), 0)
	end)

	local LastUpdated = 0

	-- Buttons are built a few per frame, so a new page never freezes a frame.
	-- Slots are kept when the item list changes and simply hide when empty.
	local ItemCount = Scope:Computed(function(Use)
		return #Use(Items)
	end)
	local SlotCount = Scope:Value(0)
	local Slots = Scope:Computed(function(Use)
		local SlotCountValue = Use(SlotCount)
		local SlotList = table.create(SlotCountValue)
		for Index = 1, SlotCountValue do
			SlotList[Index] = Index
		end
		return SlotList
	end)
	table.insert(
		Scope,
		RunService.Heartbeat:Connect(function()
			local SlotCountValue = Fusion.peek(SlotCount)
			local ItemCountValue = Fusion.peek(ItemCount)
			-- At least one per frame, then more while the frame budget lasts
			local Started = os.clock()
			while SlotCountValue < ItemCountValue do
				SlotCountValue += 1
				SlotCount:set(SlotCountValue)

				if os.clock() - Started > BUILD_BUDGET_SECONDS then
					break
				end
			end
		end)
	)

	local ItemsTab = Scope:Hydrate(Scope:Scroller(OnyxUI.Util.CombineProps(Props, {
		Name = script.Name,
		ListEnabled = true,
		ListHorizontalFlex = Enum.UIFlexAlignment.Fill,
		ListPadding = Scope:Computed(function(Use)
			return UDim.new(0, Use(Theme.Spacing["1"]))
		end),
		ScrollBarImageColor3 = Theme.Colors.Neutral.Light,
		ClipsDescendants = false,
		Visible = Shown,
		CanvasSize = UDim2.fromOffset(0, 0),
		Padding = Scope:Computed(function(Use)
			return UDim.new(0, Use(Theme.Spacing["0"]))
		end),
		PaddingRight = Scope:Computed(function(Use)
			return UDim.new(0, Use(Theme.Spacing["1"]))
		end),
	}))) {
		[OnChange "CanvasPosition"] = function(CanvasPosition: Vector2)
			local OnReachedEndValue = Fusion.peek(OnReachedEnd)
			local AbsoluteCanvasSizeValue = Fusion.peek(AbsoluteCanvasSize)
			local AbsoluteWindowSizeValue = Fusion.peek(AbsoluteWindowSize)

			local CanvasHeight = AbsoluteCanvasSizeValue.Y - AbsoluteWindowSizeValue.Y

			if (CanvasPosition.Y >= (CanvasHeight - 500)) and ((os.time() - LastUpdated) > 0.5) then
				LastUpdated = os.time()

				OnReachedEndValue()
			end
		end,
		[Out "AbsoluteCanvasSize"] = AbsoluteCanvasSize,
		[Out "AbsoluteWindowSize"] = AbsoluteWindowSize,

		[Children] = {
			Scope:Hydrate(Scope:Frame {
				Name = "Items",
				ListEnabled = true,
				ListFillDirection = Enum.FillDirection.Horizontal,
				ListWraps = true,
				ListPadding = Scope:Computed(function(Use)
					return UDim.new(0, Use(Gap))
				end),
				Size = UDim2.fromScale(1, 0),
				AutomaticSize = Enum.AutomaticSize.Y,

				[Children] = {
					Scope:ForValues(Slots, function(Use, Scope, Index)
						-- Each slot shows whichever item sits at its index, so switching
						-- categories updates the existing buttons instead of rebuilding them.
						local Item = Scope:Computed(function(Use)
							return Use(Items)[Index]
						end)

						return OnyxUI.Themer.Theme:is(Use(States.Theme)):during(function()
							return Scope:ItemButton {
								Id = Scope:Computed(function(Use)
									local ItemValue = Use(Item)
									return ItemValue and ItemValue.Id
								end),
								Type = Scope:Computed(function(Use)
									local ItemValue = Use(Item)
									return (ItemValue and ItemValue.Type) or Enum.AvatarItemType.Asset
								end),
								Featured = Scope:Computed(function(Use)
									local ItemValue = Use(Item)
									return (ItemValue and ItemValue.Featured) == true
								end),
								Owned = Scope:Computed(function(Use)
									local ItemValue = Use(Item)
									return (ItemValue and ItemValue.Owned) == true
								end),
								Visible = Scope:Computed(function(Use)
									local ItemValue = Use(Item)
									return ItemValue ~= nil and ItemValue.Visible ~= false
								end),
								LayoutOrder = Index,
								Size = CardSize,
								AutomaticSize = Enum.AutomaticSize.Y,
							}
						end)
					end),
				},
			}) {
				[Out "AbsoluteSize"] = GridWidth,
			},
			Scope:Card {
				Name = "NoItemsCard",
				ListEnabled = true,
				ListHorizontalAlignment = Enum.HorizontalAlignment.Center,
				BackgroundTransparency = 1,
				AutomaticSize = Enum.AutomaticSize.Y,
				PaddingTop = Scope:Computed(function(Use)
					return UDim.new(0, Use(Theme.Spacing["8"]))
				end),
				PaddingBottom = Scope:Computed(function(Use)
					return UDim.new(0, Use(Theme.Spacing["8"]))
				end),

				[Children] = {
					Scope:Image {
						Image = "rbxassetid://10480493542",
						BackgroundTransparency = 1,
					},
					Scope:Text {
						Text = "No more items to show!\nRate limits may have been hit.",
						TextWrapped = false,
						TextXAlignment = Enum.TextXAlignment.Center,
					},
				},
			},
		},
	}

	return ItemsTab
end
