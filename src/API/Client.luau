local SOURCE = script.Parent.SourceCode
local PACKAGES = script.Parent.Parent
local CLIENT = SOURCE.Client

local States = require(SOURCE.Client.UI.States)
local Fusion = require(PACKAGES.Fusion)
local Bootloader = require(PACKAGES.Bootloader)
local Config = require(script.Parent.Config)
local ServiceProvider = require(CLIENT.ServiceProvider)
local LocalAvatar = require(CLIENT.Avatar.LocalAvatar)
local SharedAvatars = require(CLIENT.UI.StateExtensions.SharedAvatars)

local function GetModules()
	local Modules = {}

	for _, Child in ipairs(CLIENT:GetChildren()) do
		if Child:IsA("ModuleScript") then
			table.insert(Modules, Child)
		end
	end

	return Modules
end

--[=[
	@class AvalogClient

	The client-side module of Avalog.
]=]
local AvalogClient = {
	Config = Config,
	Started = false,
	--[=[
		Fires with the display name when a player in this server shares their avatar.
	]=]
	AvatarShared = SharedAvatars.AvatarShared,
	_Bootloader = Bootloader(GetModules()),
	_ServiceProvider = ServiceProvider,
}

--[=[
	Starts Avalog on the client.
]=]
function AvalogClient:Start()
	assert(not self.Started, "Avalog already started.")
	self.Started = true

	AvalogClient._ServiceProvider:Setup({
		AvatarManager = LocalAvatar,
	})

	AvalogClient._Bootloader:Initialize()
	AvalogClient._Bootloader:Start()
end

--[=[
	Configures Avalog with the given config.

	@param NewConfig Config
]=]
function AvalogClient:Configure(NewConfig: Config.Config)
	AvalogClient.Config:Update(NewConfig)
end

--[=[
	Toggles whether or not Avalog is open.
]=]
function AvalogClient:ToggleOpen()
	States.Open:set(not Fusion.peek(States.Open))
end

--[=[
	Sets whether or not Avalog is open.

	@param Open boolean
]=]
function AvalogClient:SetOpen(Open: boolean)
	States.Open:set(Open)
end

--[=[
	Opens Avalog on the given edit mode ("Marketplace", "Inventory", "Customize",
	"Outfits" or "Shared"). Unknown or disabled modes open the first mode.

	@param ModeName string
]=]
function AvalogClient:OpenMode(ModeName: string)
	local Index = table.find(Config:Get().EditModes, ModeName) or 1

	if Fusion.peek(States.Catalog.Mode) ~= Index then
		States.Catalog.Mode:set(Index)
		States.Catalog.Category:set(1)
		States.Catalog.SubCategory:set(1)
	end
	States.Open:set(true)
end

--[=[
	Returns whether Avalog is open.
]=]
function AvalogClient:IsOpen(): boolean
	return Fusion.peek(States.Open)
end

local OpenScope = Fusion.scoped(Fusion)

--[=[
	Calls Callback with the new open state whenever Avalog opens or closes.
	Returns a function that stops listening.

	@param Callback (Open: boolean) -> ()
]=]
function AvalogClient:OnOpenChanged(Callback: (Open: boolean) -> ()): () -> ()
	return OpenScope:Observer(States.Open):onChange(function()
		Callback(Fusion.peek(States.Open))
	end)
end

return AvalogClient
