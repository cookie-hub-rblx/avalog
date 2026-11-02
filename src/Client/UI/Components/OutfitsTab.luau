-- Lets players save the avatar they built under a name and put it back on later.

local Avalog = script.Parent.Parent.Parent.Parent.Parent
local OnyxUI = require(Avalog.Parent.OnyxUI)
local Fusion = require(Avalog.Parent.Fusion)
local States = require(Avalog.SourceCode.Client.UI.States)
local Outfits = require(Avalog.SourceCode.Client.UI.StateExtensions.Outfits)

local Children = Fusion.Children

local WEAR_ICON = "rbxassetid://13846852950"
local CONFIRM_TIME = 3

export type Props = {
	Shown: Fusion.UsedAs<boolean>?,
}

local function Run(Action: () -> ())
	task.spawn(Action)
end

return function(Scope: Fusion.Scope<any>, Props: Props)
	local Scope = Fusion.innerScope(Scope, Fusion, OnyxUI.Util, OnyxUI.Components)
	local Theme = OnyxUI.Themer.Theme:now()

	local Shown = OnyxUI.Util.Fallback(Props.Shown, false)
	local NewName = Scope:Value("")

	if not Fusion.peek(States.Outfits.Loaded) then
		Run(function()
			Outfits:Refresh()
		end)
	end

	local Full = Scope:Computed(function(Use)
		return #Use(States.Outfits.List) >= Outfits.MAX_OUTFITS
	end)

	local function SaveNew()
		if Fusion.peek(Full) or Fusion.peek(States.Outfits.Busy) then
			return
		end

		local Name = Fusion.peek(NewName)
		Run(function()
			if Outfits:Save(Name) then
				NewName:set("")
			end
		end)
	end

	-- Outfits matching the search box, keeping their position in the saved list
	local MatchingOutfits = Scope:Computed(function(Use)
		local Query = string.lower(Use(States.Catalog.SearchQuery) or "")
		local Result = {}

		for Index, Outfit in ipairs(Use(States.Outfits.List)) do
			if Query == "" or string.find(string.lower(Outfit.Name), Query, 1, true) then
				table.insert(Result, { Index = Index, Outfit = Outfit })
			end
		end

		return Result
	end)

	local function OutfitRow(Scope, Index: number, Outfit)
		local Renaming = Scope:Value(false)
		local RenameText = Scope:Value(Outfit.Name)
		local ConfirmingDelete = Scope:Value(false)
		local ConfirmToken = 0

		local ItemCount = Outfits.CountItems(Outfit.Data)

		local function FinishRename()
			if not Fusion.peek(Renaming) then
				return
			end
			Renaming:set(false)

			local Name = Fusion.peek(RenameText)
			if Outfits.CleanName(Name) ~= "" and Name ~= Outfit.Name then
				Run(function()
					Outfits:Rename(Index, Name)
				end)
			end
		end

		return Scope:Card {
			Name = "Outfit",
			LayoutOrder = Index,
			BackgroundColor3 = Theme.Colors.Neutral.Main,
			ListEnabled = true,
			ListFillDirection = Enum.FillDirection.Horizontal,
			ListVerticalAlignment = Enum.VerticalAlignment.Center,
			ListPadding = Scope:Computed(function(Use)
				return UDim.new(0, Use(Theme.Spacing["0.5"]))
			end),
			Padding = Scope:Computed(function(Use)
				return UDim.new(0, Use(Theme.Spacing["0.5"]))
			end),
			CornerRadius = Scope:Computed(function(Use)
				return UDim.new(0, Use(Theme.CornerRadius["1.5"]))
			end),

			[Children] = {
				Scope:Frame {
					Name = "Info",
					FlexMode = Enum.UIFlexMode.Fill,
					ListEnabled = true,
					ListHorizontalFlex = Enum.UIFlexAlignment.Fill,
					ListPadding = Scope:Computed(function(Use)
						return UDim.new(0, Use(Theme.Spacing["0"]))
					end),

					[Children] = {
						Scope:Heading {
							Text = Outfit.Name,
							HeadingSize = 1.1,
							TextWrapped = false,
							TextTruncate = Enum.TextTruncate.AtEnd,
							AutoLocalize = false,
							Visible = Scope:Computed(function(Use)
								return not Use(Renaming)
							end),
						},
						Scope:Text {
							Text = if ItemCount == 1 then "1 item" else `{ItemCount} items`,
							TextTransparency = 0.4,
							Visible = Scope:Computed(function(Use)
								return not Use(Renaming)
							end),
						},
						Scope:TextInput {
							Name = "RenameInput",
							Text = RenameText,
							PlaceholderText = "New name",
							CharacterLimit = 30,
							Color = Theme.Colors.NeutralContent.Main,
							TextTransparency = 0,
							AutomaticSize = Enum.AutomaticSize.Y,
							Visible = Renaming,
							OnFocusLost = FinishRename,
						},
					},
				},
				Scope:Button {
					Name = "WearButton",
					Content = { WEAR_ICON, "Wear" },
					SizeVariant = "Medium",
					Color = Theme.Colors.Success.Main,
					Disabled = States.Outfits.Busy,
					Visible = Scope:Computed(function(Use)
						return not Use(Renaming)
					end),

					OnActivated = function()
						Outfits:Wear(Index)
					end,
				},
				Scope:Button {
					Name = "RenameButton",
					Content = Scope:Computed(function(Use)
						return { if Use(Renaming) then "Done" else "Rename" }
					end),
					SizeVariant = "Medium",
					Style = "Ghost",
					Color = Theme.Colors.BaseContent.Main,
					Disabled = States.Outfits.Busy,

					OnActivated = function()
						if Fusion.peek(Renaming) then
							FinishRename()
						else
							RenameText:set(Outfit.Name)
							Renaming:set(true)
						end
					end,
				},
				Scope:Button {
					Name = "DeleteButton",
					Content = Scope:Computed(function(Use)
						return { if Use(ConfirmingDelete) then "Sure?" else "Delete" }
					end),
					SizeVariant = "Medium",
					Style = Scope:Computed(function(Use)
						return if Use(ConfirmingDelete) then "Filled" else "Ghost"
					end),
					Color = Theme.Colors.Error.Main,
					Disabled = States.Outfits.Busy,
					Visible = Scope:Computed(function(Use)
						return not Use(Renaming)
					end),

					-- First tap asks, second tap deletes
					OnActivated = function()
						if Fusion.peek(ConfirmingDelete) then
							ConfirmingDelete:set(false)
							Run(function()
								Outfits:Delete(Index)
							end)
						else
							ConfirmingDelete:set(true)
							ConfirmToken += 1
							local Token = ConfirmToken
							task.delay(CONFIRM_TIME, function()
								if Token == ConfirmToken then
									ConfirmingDelete:set(false)
								end
							end)
						end
					end,
				},
			},
		}
	end

	return Scope:Scroller(OnyxUI.Util.CombineProps(Props, {
		Name = script.Name,
		Visible = Shown,
		ListEnabled = true,
		ListHorizontalFlex = Enum.UIFlexAlignment.Fill,
		ListPadding = Scope:Computed(function(Use)
			return UDim.new(0, Use(Theme.Spacing["0.5"]))
		end),
		CanvasSize = UDim2.new(),
		PaddingRight = Scope:Computed(function(Use)
			return UDim.new(0, Use(Theme.Spacing["1"]))
		end),
		Padding = Scope:Computed(function(Use)
			return UDim.new(0, Use(Theme.Spacing["0"]))
		end),

		[Children] = {
			Scope:Card {
				Name = "SaveCard",
				LayoutOrder = 1,
				BackgroundColor3 = Theme.Colors.Neutral.Main,
				ListEnabled = true,
				ListHorizontalFlex = Enum.UIFlexAlignment.Fill,
				ListPadding = Scope:Computed(function(Use)
					return UDim.new(0, Use(Theme.Spacing["0.5"]))
				end),
				CornerRadius = Scope:Computed(function(Use)
					return UDim.new(0, Use(Theme.CornerRadius["1.5"]))
				end),

				[Children] = {
					Scope:Heading {
						Text = "Save what you're wearing",
						HeadingSize = 1.2,
						TextWrapped = false,
					},
					Scope:Frame {
						Name = "SaveRow",
						ListEnabled = true,
						ListFillDirection = Enum.FillDirection.Horizontal,
						ListVerticalAlignment = Enum.VerticalAlignment.Center,
						ListPadding = Scope:Computed(function(Use)
							return UDim.new(0, Use(Theme.Spacing["0.5"]))
						end),

						[Children] = {
							Scope:TextInput {
								Name = "NameInput",
								Text = NewName,
								PlaceholderText = Scope:Computed(function(Use)
									return `Outfit {#Use(States.Outfits.List) + 1}`
								end),
								CharacterLimit = 30,
								Color = Theme.Colors.NeutralContent.Main,
								TextTransparency = 0,
								FlexMode = Enum.UIFlexMode.Fill,
								AutomaticSize = Enum.AutomaticSize.Y,
								Disabled = Full,
							},
							Scope:Button {
								Name = "SaveButton",
								Content = { "Save outfit" },
								SizeVariant = "Medium",
								Color = Theme.Colors.Primary.Main,
								Disabled = Scope:Computed(function(Use)
									return Use(Full) or Use(States.Outfits.Busy)
								end),

								OnActivated = SaveNew,
							},
						},
					},
					-- Status line: shows the latest result, otherwise the count. It sits
					-- inside the card so the list below never jumps when it changes.
					Scope:Text {
						Name = "Status",
						AutoLocalize = false,
						TextColor3 = Scope:Computed(function(Use)
							local Message = Use(States.Outfits.Message)
							if Message == nil then
								return Use(Theme.Colors.BaseContent.Main)
							end
							return if Message.Ok then Use(Theme.Colors.Success.Main) else Use(Theme.Colors.Error.Main)
						end),
						TextTransparency = Scope:Computed(function(Use)
							return if Use(States.Outfits.Message) then 0 else 0.4
						end),
						Text = Scope:Computed(function(Use)
							local Message = Use(States.Outfits.Message)
							if Message then
								return Message.Text
							end
							local Count = #Use(States.Outfits.List)
							if Count >= Outfits.MAX_OUTFITS then
								return `{Count} of {Outfits.MAX_OUTFITS} saved. Delete one to save another.`
							end
							return `{Count} of {Outfits.MAX_OUTFITS} saved`
						end),
						TextWrapped = true,
						Size = UDim2.fromScale(1, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
					},
				},
			},
			Scope:Text {
				Name = "EmptyState",
				LayoutOrder = 2,
				Text = Scope:Computed(function(Use)
					if not Use(States.Outfits.Loaded) then
						return if Use(States.Outfits.Busy) then "Loading your outfits..." else ""
					end
					if #Use(States.Outfits.List) == 0 then
						return "No saved outfits yet. Dress up, give your look a name and press Save outfit."
					end
					return "No outfits match your search."
				end),
				TextTransparency = 0.3,
				TextWrapped = true,
				Size = UDim2.fromScale(1, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				Visible = Scope:Computed(function(Use)
					if not Use(States.Outfits.Loaded) then
						return Use(States.Outfits.Busy)
					end
					return #Use(MatchingOutfits) == 0
				end),
			},
			Scope:Frame {
				Name = "List",
				LayoutOrder = 3,
				ListEnabled = true,
				ListHorizontalFlex = Enum.UIFlexAlignment.Fill,
				ListPadding = Scope:Computed(function(Use)
					return UDim.new(0, Use(Theme.Spacing["0.5"]))
				end),

				[Children] = Scope:ForValues(MatchingOutfits, function(Use, Scope, Entry)
					return OnyxUI.Themer.Theme:is(Fusion.peek(States.Theme)):during(function()
						return OutfitRow(Scope, Entry.Index, Entry.Outfit)
					end)
				end),
			},
		},
	}))
end
