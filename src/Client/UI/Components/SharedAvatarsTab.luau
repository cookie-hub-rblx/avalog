-- Lets players share the avatar they're wearing and browse, preview and try on
-- avatars other players shared.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Avalog = script.Parent.Parent.Parent.Parent.Parent
local OnyxUI = require(Avalog.Parent.OnyxUI)
local Fusion = require(Avalog.Parent.Fusion)
local HumanoidDescriber = require(Avalog.Parent.HumanoidDescriber)
local States = require(Avalog.SourceCode.Client.UI.States)
local SharedAvatars = require(Avalog.SourceCode.Client.UI.StateExtensions.SharedAvatars)

local Children = Fusion.Children

local WEAR_ICON = "rbxassetid://13846852950"
local CARD_SIZE = Vector2.new(170, 270)
local PREVIEW_HEIGHT = 170
-- Previews are dressed a few at a time so opening the tab doesn't stall the game
local MAX_PREVIEW_JOBS = 2
-- Dressed previews are kept between list refreshes, keyed by who shared and when
local MAX_CACHED_PREVIEWS = 80

export type Props = {
	Shown: Fusion.UsedAs<boolean>?,
}

local function Run(Action: () -> ())
	task.spawn(Action)
end

local function KeyOf(Entry): string
	return `{Entry.UserId}:{Entry.SharedAt}`
end

-- Preview models ---------------------------------------------------------------------------------

local PreviewCache: { [string]: Model } = {}
local CacheOrder: { string } = {}
local Pending: { [string]: { (Model?) -> () } } = {}
local Queue: { () -> () } = {}
local RunningJobs = 0

local function Remember(Key: string, Model: Model)
	PreviewCache[Key] = Model
	table.insert(CacheOrder, Key)

	while #CacheOrder > MAX_CACHED_PREVIEWS do
		local Oldest = table.remove(CacheOrder, 1)
		local Old = PreviewCache[Oldest]
		PreviewCache[Oldest] = nil
		if Old then
			Old:Destroy()
		end
	end
end

local function PumpQueue()
	while RunningJobs < MAX_PREVIEW_JOBS and #Queue > 0 do
		RunningJobs += 1
		local Job = table.remove(Queue, 1)
		task.spawn(function()
			pcall(Job)
			RunningJobs -= 1
			PumpQueue()
		end)
	end
end

local Workshop: ViewportFrame? = nil

local function GetWorkshop(): ViewportFrame
	if Workshop == nil or Workshop.Parent == nil then
		local Gui = Instance.new("ScreenGui")
		Gui.Name = "AvalogPreviewWorkshop"
		Gui.Enabled = false
		Gui.ResetOnSpawn = false
		Gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

		Workshop = Instance.new("ViewportFrame")
		Workshop.Parent = Gui
	end

	return Workshop :: ViewportFrame
end

-- Dresses a copy of the local character (it has every part a rig needs) in the entry's avatar.
local function BuildPreview(Entry): Model?
	local Template = Fusion.peek(States.Avatar.Character)
	if Template == nil then
		return nil
	end

	Template.Archivable = true
	local Model = Template:Clone()
	if Model == nil then
		return nil
	end

	local Humanoid = Model:FindFirstChildOfClass("Humanoid")
	if Humanoid == nil then
		Model:Destroy()
		return nil
	end

	-- Applying a description needs the model to be in the DataModel, so it's dressed
	-- in a hidden viewport in PlayerGui
	local Holder = Instance.new("WorldModel")
	Model.Parent = Holder
	Holder.Parent = GetWorkshop()

	local Describer = HumanoidDescriber(Instance.new("HumanoidDescription"))
	local Data = SharedAvatars.DataOf(Entry)
	Describer:UpdateData(function()
		return Data
	end)

	local Ok = pcall(function()
		Humanoid:ApplyDescriptionReset(Describer.HumanoidDescription)
	end)
	Describer:Destroy()

	Model.Parent = nil
	Holder:Destroy()

	if not Ok then
		Model:Destroy()
		return nil
	end

	Model:PivotTo(CFrame.new())

	return Model
end

-- Calls Callback with a fresh copy of the entry's dressed preview (or nil if it failed).
local function RequestPreview(Entry, Callback: (Model?) -> ())
	local Key = KeyOf(Entry)

	local Cached = PreviewCache[Key]
	if Cached then
		Callback(Cached:Clone())
		return
	end

	if Pending[Key] then
		table.insert(Pending[Key], Callback)
		return
	end

	Pending[Key] = { Callback }
	table.insert(Queue, function()
		local Model = BuildPreview(Entry)
		if Model then
			Model.Archivable = true
			Remember(Key, Model)
		end

		local Waiting = Pending[Key]
		Pending[Key] = nil
		for _, Waiter in ipairs(Waiting or {}) do
			Waiter(if Model then Model:Clone() else nil)
		end
	end)
	PumpQueue()
end

-- Component ---------------------------------------------------------------------------------------

return function(Scope: Fusion.Scope<any>, Props: Props)
	local Scope = Fusion.innerScope(Scope, Fusion, OnyxUI.Util, OnyxUI.Components)
	local Theme = OnyxUI.Themer.Theme:now()

	local Shown = OnyxUI.Util.Fallback(Props.Shown, false)
	local Caption = Scope:Value("")

	Run(function()
		SharedAvatars:RefreshIfStale()
	end)

	local function Share()
		if Fusion.peek(States.SharedAvatars.Busy) then
			return
		end

		local Text = Fusion.peek(Caption)
		Run(function()
			if SharedAvatars:Share(Text) then
				Caption:set("")
			end
		end)
	end

	-- Shared avatars matching the search box
	local Matching = Scope:Computed(function(Use)
		local Query = string.lower(Use(States.Catalog.SearchQuery) or "")
		local Result = {}

		for Index, Entry in ipairs(Use(States.SharedAvatars.List)) do
			local Haystack = string.lower(`{Entry.DisplayName} {Entry.Caption}`)
			if Query == "" or string.find(Haystack, Query, 1, true) then
				table.insert(Result, { Index = Index, Entry = Entry })
			end
		end

		return Result
	end)

	local function Preview(Scope, Entry)
		local Camera = Scope:New "Camera" {
			FieldOfView = 30,
			CFrame = CFrame.lookAt(Vector3.new(0, 0.5, -11), Vector3.new(0, 0.5, 0)),
		}
		local World = Scope:New "WorldModel" {}
		local Loading = Scope:Value(true)
		local Failed = Scope:Value(false)
		local Alive = true

		table.insert(Scope, function()
			Alive = false
		end)

		if RunService:IsRunning() then
			RequestPreview(Entry, function(Model)
				if not Alive then
					if Model then
						Model:Destroy()
					end
					return
				end

				Loading:set(false)

				if Model == nil then
					Failed:set(true)
					return
				end

				-- Frame the whole body, a little from the side. The model stands at the origin
				-- facing -Z; its bounding box is only used for the size (its position can lag).
				Model:PivotTo(CFrame.new())
				local _, Size = Model:GetBoundingBox()
				local Center = Vector3.new(0, 0.3, 0)
				local Distance = Size.Y * 1.75 + 0.5
				Camera.CFrame = CFrame.lookAt(
					Center + Vector3.new(Distance * 0.3, Size.Y * 0.08, -Distance),
					Center
				)
				Model.Parent = World
				table.insert(Scope, Model)
			end)
		end

		return Scope:New "ViewportFrame" {
			Name = "Preview",
			Size = UDim2.new(1, 0, 0, PREVIEW_HEIGHT),
			BackgroundColor3 = Theme.Colors.Base.Dark,
			BackgroundTransparency = 0,
			CurrentCamera = Camera,
			Ambient = Color3.fromRGB(200, 200, 210),
			LightColor = Color3.fromRGB(255, 255, 255),
			LightDirection = Vector3.new(-0.4, -1, 0.6),

			[Children] = {
				Scope:New "UICorner" {
					CornerRadius = Scope:Computed(function(Use)
						return UDim.new(0, Use(Theme.CornerRadius["1"]))
					end),
				},
				Camera,
				World,
				Scope:Text {
					Name = "Status",
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(0.5, 0.5),
					Text = Scope:Computed(function(Use)
						return if Use(Failed) then "No preview" else "Loading..."
					end),
					TextTransparency = 0.4,
					Visible = Scope:Computed(function(Use)
						return Use(Loading) or Use(Failed)
					end),
				},
			},
		}
	end

	local function AvatarCard(Scope, Index: number, Entry)
		local IsMine = Players.LocalPlayer ~= nil and Entry.UserId == Players.LocalPlayer.UserId

		return Scope:Card {
			Name = "SharedAvatar",
			LayoutOrder = Index,
			BackgroundColor3 = Theme.Colors.Neutral.Main,
			ListEnabled = true,
			ListHorizontalFlex = Enum.UIFlexAlignment.Fill,
			ListPadding = Scope:Computed(function(Use)
				return UDim.new(0, Use(Theme.Spacing["0.25"]))
			end),
			Padding = Scope:Computed(function(Use)
				return UDim.new(0, Use(Theme.Spacing["0.5"]))
			end),
			CornerRadius = Scope:Computed(function(Use)
				return UDim.new(0, Use(Theme.CornerRadius["1.5"]))
			end),
			AutomaticSize = Enum.AutomaticSize.None,

			[Children] = {
				Preview(Scope, Entry),
				Scope:Heading {
					Text = if IsMine then `{Entry.DisplayName} (you)` else Entry.DisplayName,
					HeadingSize = 1,
					TextWrapped = false,
					TextTruncate = Enum.TextTruncate.AtEnd,
					AutoLocalize = false,
				},
				Scope:Text {
					Text = if Entry.Caption ~= "" then Entry.Caption else " ",
					TextTransparency = 0.35,
					TextWrapped = false,
					TextTruncate = Enum.TextTruncate.AtEnd,
					AutoLocalize = false,
				},
				Scope:Button {
					Name = "TryOnButton",
					Content = { WEAR_ICON, "Try on" },
					SizeVariant = "Medium",
					Color = Theme.Colors.Success.Main,

					OnActivated = function()
						SharedAvatars:TryOn(Entry)
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
				Name = "ShareCard",
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
						Text = "Share your avatar",
						HeadingSize = 1.2,
						TextWrapped = false,
					},
					Scope:Text {
						Text = "Everyone here can see it and try it on.",
						TextTransparency = 0.4,
						TextWrapped = true,
						Size = UDim2.fromScale(1, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
					},
					Scope:Frame {
						Name = "ShareRow",
						ListEnabled = true,
						ListFillDirection = Enum.FillDirection.Horizontal,
						ListVerticalAlignment = Enum.VerticalAlignment.Center,
						ListPadding = Scope:Computed(function(Use)
							return UDim.new(0, Use(Theme.Spacing["0.5"]))
						end),

						[Children] = {
							Scope:TextInput {
								Name = "CaptionInput",
								Text = Caption,
								PlaceholderText = "Add a caption (optional)",
								CharacterLimit = 40,
								Color = Theme.Colors.NeutralContent.Main,
								TextTransparency = 0,
								FlexMode = Enum.UIFlexMode.Fill,
								AutomaticSize = Enum.AutomaticSize.Y,
							},
							Scope:Button {
								Name = "ShareButton",
								Content = Scope:Computed(function(Use)
									return { if Use(States.SharedAvatars.Mine) then "Share again" else "Share" }
								end),
								SizeVariant = "Medium",
								Color = Theme.Colors.Primary.Main,
								Disabled = States.SharedAvatars.Busy,

								OnActivated = Share,
							},
						},
					},
					Scope:Text {
						Name = "Status",
						AutoLocalize = false,
						TextColor3 = Scope:Computed(function(Use)
							local Message = Use(States.SharedAvatars.Message)
							if Message == nil then
								return Use(Theme.Colors.BaseContent.Main)
							end
							return if Message.Ok then Use(Theme.Colors.Success.Main) else Use(Theme.Colors.Error.Main)
						end),
						TextTransparency = Scope:Computed(function(Use)
							return if Use(States.SharedAvatars.Message) then 0 else 0.4
						end),
						Text = Scope:Computed(function(Use)
							local Message = Use(States.SharedAvatars.Message)
							if Message then
								return Message.Text
							end
							return if Use(States.SharedAvatars.Mine)
								then "Your avatar is shared."
								else "You haven't shared an avatar yet."
						end),
						TextWrapped = true,
						Size = UDim2.fromScale(1, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
					},
					Scope:Button {
						Name = "UnshareButton",
						Content = { "Stop sharing" },
						SizeVariant = "Small",
						Style = "Ghost",
						Color = Theme.Colors.Error.Main,
						Disabled = States.SharedAvatars.Busy,
						Visible = States.SharedAvatars.Mine,

						OnActivated = function()
							Run(function()
								SharedAvatars:Unshare()
							end)
						end,
					},
				},
			},
			Scope:Frame {
				Name = "ListHeader",
				LayoutOrder = 2,
				ListEnabled = true,
				ListFillDirection = Enum.FillDirection.Horizontal,
				ListVerticalAlignment = Enum.VerticalAlignment.Center,

				[Children] = {
					Scope:Heading {
						Text = "Newest shared avatars",
						HeadingSize = 1.1,
						TextWrapped = false,
						FlexMode = Enum.UIFlexMode.Fill,
					},
					Scope:Button {
						Name = "RefreshButton",
						Content = { "Refresh" },
						SizeVariant = "Small",
						Style = "Ghost",
						Color = Theme.Colors.BaseContent.Main,
						Disabled = States.SharedAvatars.Busy,

						OnActivated = function()
							Run(function()
								SharedAvatars:Refresh()
							end)
						end,
					},
				},
			},
			Scope:Text {
				Name = "EmptyState",
				LayoutOrder = 3,
				Text = Scope:Computed(function(Use)
					if not Use(States.SharedAvatars.Loaded) then
						return if Use(States.SharedAvatars.Busy) then "Loading shared avatars..." else ""
					end
					if #Use(States.SharedAvatars.List) == 0 then
						return "Nobody has shared an avatar yet. Be the first!"
					end
					return "No shared avatars match your search."
				end),
				TextTransparency = 0.3,
				TextWrapped = true,
				Size = UDim2.fromScale(1, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				Visible = Scope:Computed(function(Use)
					if not Use(States.SharedAvatars.Loaded) then
						return Use(States.SharedAvatars.Busy)
					end
					return #Use(Matching) == 0
				end),
			},
			Scope:Frame {
				Name = "Grid",
				LayoutOrder = 4,
				AutomaticSize = Enum.AutomaticSize.Y,

				[Children] = {
					Scope:New "UIGridLayout" {
						CellSize = UDim2.fromOffset(CARD_SIZE.X, CARD_SIZE.Y),
						CellPadding = Scope:Computed(function(Use)
							local Gap = Use(Theme.Spacing["0.5"])
							return UDim2.fromOffset(Gap, Gap)
						end),
						SortOrder = Enum.SortOrder.LayoutOrder,
					},
					Scope:ForValues(Matching, function(Use, Scope, Item)
						return OnyxUI.Themer.Theme:is(Fusion.peek(States.Theme)):during(function()
							return AvatarCard(Scope, Item.Index, Item.Entry)
						end)
					end),
				},
			},
		},
	}))
end
