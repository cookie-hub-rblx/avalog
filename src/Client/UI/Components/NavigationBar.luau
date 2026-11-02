local Avalog = script.Parent.Parent.Parent.Parent.Parent
local OnyxUI = require(Avalog.Parent.OnyxUI)
local Fusion = require(Avalog.Parent.Fusion)
local Config = require(Avalog.Config)
local States = require(Avalog.SourceCode.Client.UI.States)
local Navigation = require(Avalog.SourceCode.Client.UI.StateExtensions.Navigation)

local Children = Fusion.Children

local CONFIG = Config:Get()

-- Label and icon for each edit mode. The labels are what players see.
local EDIT_MODES = {
	Marketplace = { Label = "Shop", Icon = "rbxassetid://13850201307" },
	Inventory = { Label = "Inventory", Icon = "rbxassetid://13846287045" },
	Customize = { Label = "Customize", Icon = "rbxassetid://13845862177" },
	Outfits = { Label = "Outfits", Icon = "rbxassetid://108720789877383" },
	Shared = { Label = "Shared", Icon = nil },
}

-- Modes where the search box does something
local SEARCHABLE = {
	Marketplace = "Search the shop",
	Inventory = "Search your items",
	Outfits = "Search your outfits",
	Shared = "Search shared avatars",
}

local SEARCH_DELAY = 0.4

export type Props = { [string]: any } & {
	OnExit: () -> (),
}
return function(Scope: Fusion.Scope<any>, Props: Props)
	local Scope = Fusion.innerScope(Scope, Fusion, OnyxUI.Util, OnyxUI.Components)
	local Theme = OnyxUI.Themer.Theme:now()

	local SearchBarText = Scope:Value(Fusion.peek(States.Catalog.SearchQuery))

	-- Search as you type, after a short pause
	local SearchToken = 0
	local function CommitSearch()
		SearchToken += 1
		States.Catalog.SearchQuery:set(Fusion.peek(SearchBarText))
	end
	Scope:Observer(SearchBarText):onChange(function()
		SearchToken += 1
		local Token = SearchToken
		task.delay(SEARCH_DELAY, function()
			if Token == SearchToken then
				CommitSearch()
			end
		end)
	end)

	local Searchable = Scope:Computed(function(Use)
		return SEARCHABLE[Use(Navigation.Mode)] ~= nil
	end)

	return Scope:Frame(OnyxUI.Util.CombineProps(Props, {
		Name = script.Name,
		BackgroundColor3 = Theme.Colors.Base.Main,
		BackgroundTransparency = 0,
		ListEnabled = true,
		ListHorizontalFlex = Enum.UIFlexAlignment.Fill,
		ListPadding = Scope:Computed(function(Use)
			return UDim.new(0, Use(Theme.Spacing["0.5"]))
		end),
		Padding = Scope:Computed(function(Use)
			return UDim.new(0, Use(Theme.Spacing["0.5"]))
		end),
		PaddingTop = Scope:Computed(function(Use)
			return UDim.new(0, Use(Theme.Spacing["0.75"]))
		end),

		[Children] = {
			-- Every mode is a labelled tab, so players can see all of them at once
			Scope:Frame {
				Name = "ModeTabs",
				ListEnabled = true,
				ListFillDirection = Enum.FillDirection.Horizontal,
				ListHorizontalFlex = Enum.UIFlexAlignment.Fill,
				ListPadding = Scope:Computed(function(Use)
					return UDim.new(0, Use(Theme.Spacing["0.25"]))
				end),
				AutomaticSize = Enum.AutomaticSize.Y,

				[Children] = Scope:ForPairs(CONFIG.EditModes, function(Use, Scope, Index, EditMode)
					local Info = EDIT_MODES[EditMode] or { Label = EditMode, Icon = nil }
					-- Icons are dropped on narrow screens so every label still fits
					local Content = Scope:Computed(function(Use)
						local Narrow = Use(States.Screen.Resolution).X < 900
						return if Info.Icon and not Narrow then { Info.Icon, Info.Label } else { Info.Label }
					end)

					return Index,
						Scope:Button {
							Name = `{EditMode}Tab`,
							LayoutOrder = Index,
							Content = Content,
							SizeVariant = "Medium",
							Color = Theme.Colors.BaseContent.Main,
							Style = Scope:Computed(function(Use)
								return if Use(States.Catalog.Mode) == Index then "Filled" else "Ghost"
							end),

							OnActivated = function()
								States.Catalog.Mode:set(Index)
							end,
						}
				end),
			},
			Scope:Frame {
				Name = "SearchRow",
				Visible = Searchable,
				ListEnabled = true,
				ListFillDirection = Enum.FillDirection.Horizontal,
				ListVerticalAlignment = Enum.VerticalAlignment.Center,
				ListPadding = Scope:Computed(function(Use)
					return UDim.new(0, Use(Theme.Spacing["0.25"]))
				end),
				AutomaticSize = Enum.AutomaticSize.Y,

				[Children] = {
					Scope:TextInput {
						Name = "SearchInput",
						PlaceholderText = Scope:Computed(function(Use)
							return SEARCHABLE[Use(Navigation.Mode)] or "Search"
						end),
						Color = Theme.Colors.NeutralContent.Main,
						FlexMode = Enum.UIFlexMode.Fill,
						AutomaticSize = Enum.AutomaticSize.Y,
						Text = SearchBarText,
						CharacterLimit = 60,
						CornerRadius = Scope:Computed(function(Use)
							return UDim.new(0, Use(Theme.CornerRadius["1.5"]))
						end),
						TextTransparency = 0,

						OnFocusLost = CommitSearch,
					},
					Scope:Button {
						Name = "ClearSearch",
						Content = { "Clear" },
						SizeVariant = "Small",
						Style = "Ghost",
						Color = Theme.Colors.BaseContent.Main,
						Visible = Scope:Computed(function(Use)
							return Use(SearchBarText) ~= ""
						end),

						OnActivated = function()
							SearchBarText:set("")
							CommitSearch()
						end,
					},
				},
			},
		},
	}))
end
