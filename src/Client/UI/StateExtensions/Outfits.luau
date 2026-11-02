-- Client side of saved outfits: keeps States.Outfits in sync with the server
-- and puts a saved outfit on the avatar.

local RunService = game:GetService("RunService")

local Avalog = script.Parent.Parent.Parent.Parent.Parent
local States = require(script.Parent.Parent.States)
local Fusion = require(Avalog.Parent.Fusion)
local EnumSerDes = require(Avalog.Parent.EnumSerDes)
local Sift = require(Avalog.Parent.Sift)
local ServiceProvider = require(Avalog.SourceCode.Client.ServiceProvider)
local SharedOutfits = require(Avalog.SourceCode.Shared.Outfits)

local Zap
if RunService:IsRunning() then
	Zap = require(Avalog.SourceCode.Shared.Zap.client)
end

local Outfits = {
	MAX_OUTFITS = SharedOutfits.MAX_OUTFITS,
	MAX_NAME_BYTES = SharedOutfits.MAX_NAME_BYTES,
	CleanName = SharedOutfits.CleanName,
}

local MessageToken = 0

local function ShowMessage(Text: string?, Ok: boolean)
	MessageToken += 1
	local Token = MessageToken

	if Text == nil then
		States.Outfits.Message:set(nil)
		return
	end

	States.Outfits.Message:set({ Text = Text, Ok = Ok })

	task.delay(5, function()
		if MessageToken == Token then
			States.Outfits.Message:set(nil)
		end
	end)
end

-- Runs one server request at a time and applies its result.
local function Request(Call: () -> any, ShowSuccess: boolean)
	if Zap == nil or Fusion.peek(States.Outfits.Busy) then
		return false
	end

	States.Outfits.Busy:set(true)

	-- Zap never answers if the server errors, so give up after a while
	local Done, Ok, Result = false, false, nil
	task.spawn(function()
		Ok, Result = pcall(Call)
		Done = true
	end)

	local Deadline = os.clock() + 15
	while not Done and os.clock() < Deadline do
		task.wait(0.1)
	end

	States.Outfits.Busy:set(false)

	if not Done or not Ok or type(Result) ~= "table" then
		ShowMessage("Couldn't reach the server. Try again.", false)
		return false
	end

	-- A failed request may come back without the list (e.g. still loading)
	if Result.Ok or #Result.Outfits > 0 then
		States.Outfits.List:set(Result.Outfits)
		States.Outfits.Loaded:set(true)
	end

	if (not Result.Ok) or ShowSuccess then
		ShowMessage(Result.Message, Result.Ok)
	end

	return Result.Ok
end

function Outfits:Refresh()
	return Request(function()
		return Zap.GetOutfits.Call()
	end, false)
end

function Outfits:Save(Name: string)
	local AvatarManager = ServiceProvider:GetAvatarManager()
	if AvatarManager.HumanoidDescriber == nil then
		ShowMessage("Your avatar is still loading.", false)
		return false
	end

	local Data = EnumSerDes.SerializeTree(AvatarManager.HumanoidDescriber:GetData())

	return Request(function()
		return Zap.SaveOutfit.Call(SharedOutfits.CleanName(Name), Data)
	end, true)
end

function Outfits:Rename(Index: number, Name: string)
	return Request(function()
		return Zap.RenameOutfit.Call(Index, SharedOutfits.CleanName(Name))
	end, true)
end

function Outfits:Delete(Index: number)
	return Request(function()
		return Zap.DeleteOutfit.Call(Index)
	end, true)
end

function Outfits:Wear(Index: number)
	local Outfit = Fusion.peek(States.Outfits.List)[Index]
	local AvatarManager = ServiceProvider:GetAvatarManager()

	if Outfit == nil or AvatarManager.HumanoidDescriber == nil then
		return false
	end

	local Data = EnumSerDes.DeserializeTree(Sift.Dictionary.copyDeep(Outfit.Data))

	AvatarManager.HumanoidDescriber:UpdateData(function()
		return Data
	end)
	AvatarManager:ApplyLimits()
	AvatarManager:Apply()

	ShowMessage(`Wearing "{Outfit.Name}".`, true)

	return true
end

-- Counts the items an outfit puts on, for the list's subtitle.
function Outfits.CountItems(OutfitData): number
	local Count = #(OutfitData.Accessories or {})
	local Clothing = OutfitData.Clothing or {}

	for _, Key in { "Shirt", "TShirt", "Pants" } do
		if (Clothing[Key] or 0) ~= 0 then
			Count += 1
		end
	end

	return Count
end

return Outfits
