-- Client side of shared avatars: keeps States.SharedAvatars in sync with the server,
-- shares the avatar the player is wearing and puts a shared avatar on.

local RunService = game:GetService("RunService")

local Avalog = script.Parent.Parent.Parent.Parent.Parent
local States = require(script.Parent.Parent.States)
local Fusion = require(Avalog.Parent.Fusion)
local EnumSerDes = require(Avalog.Parent.EnumSerDes)
local Sift = require(Avalog.Parent.Sift)
local Signal = require(Avalog.Parent.Signal)
local ServiceProvider = require(Avalog.SourceCode.Client.ServiceProvider)
local Shared = require(Avalog.SourceCode.Shared.SharedAvatars)

local Zap
if RunService:IsRunning() then
	Zap = require(Avalog.SourceCode.Shared.Zap.client)
end

-- The list is refreshed when the tab opens if it's older than this
local STALE_AFTER = 30

local SharedAvatars = {
	MAX_CAPTION_BYTES = Shared.MAX_CAPTION_BYTES,
	-- Fires with the display name when someone in this server shares an avatar
	AvatarShared = Signal.new(),
}

local LastRefresh = -math.huge
local MessageToken = 0

local function ShowMessage(Text: string?, Ok: boolean)
	MessageToken += 1
	local Token = MessageToken

	if Text == nil then
		States.SharedAvatars.Message:set(nil)
		return
	end

	States.SharedAvatars.Message:set({ Text = Text, Ok = Ok })

	task.delay(5, function()
		if MessageToken == Token then
			States.SharedAvatars.Message:set(nil)
		end
	end)
end

-- Runs one server request at a time and applies its result.
local function Request(Call: () -> any, ShowSuccess: boolean)
	if Zap == nil or Fusion.peek(States.SharedAvatars.Busy) then
		return false
	end

	States.SharedAvatars.Busy:set(true)

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

	States.SharedAvatars.Busy:set(false)

	if not Done or not Ok or type(Result) ~= "table" then
		ShowMessage("Couldn't reach the server. Try again.", false)
		return false
	end

	if Result.Ok or #Result.Avatars > 0 then
		States.SharedAvatars.List:set(Result.Avatars)
		States.SharedAvatars.Mine:set(Result.Mine)
		States.SharedAvatars.Loaded:set(true)
		LastRefresh = os.clock()
	end

	if (not Result.Ok) or ShowSuccess then
		ShowMessage(Result.Message, Result.Ok)
	end

	return Result.Ok
end

function SharedAvatars:Refresh()
	return Request(function()
		return Zap.GetSharedAvatars.Call()
	end, false)
end

function SharedAvatars:RefreshIfStale()
	if os.clock() - LastRefresh > STALE_AFTER then
		return SharedAvatars:Refresh()
	end
	return true
end

function SharedAvatars:Share(Caption: string)
	local AvatarManager = ServiceProvider:GetAvatarManager()
	if AvatarManager.HumanoidDescriber == nil then
		ShowMessage("Your avatar is still loading.", false)
		return false
	end

	local Data = EnumSerDes.SerializeTree(AvatarManager.HumanoidDescriber:GetData())

	return Request(function()
		return Zap.ShareAvatar.Call(Shared.Clean(Caption, Shared.MAX_CAPTION_BYTES), Data)
	end, true)
end

function SharedAvatars:Unshare()
	return Request(function()
		return Zap.UnshareAvatar.Call()
	end, true)
end

-- The avatar data of a listed entry, ready for HumanoidDescriber
function SharedAvatars.DataOf(Entry)
	return EnumSerDes.DeserializeTree(Sift.Dictionary.copyDeep(Entry.Data))
end

function SharedAvatars:TryOn(Entry)
	local AvatarManager = ServiceProvider:GetAvatarManager()
	if Entry == nil or AvatarManager.HumanoidDescriber == nil then
		return false
	end

	local Data = SharedAvatars.DataOf(Entry)

	AvatarManager.HumanoidDescriber:UpdateData(function()
		return Data
	end)
	AvatarManager:ApplyLimits()
	AvatarManager:Apply()

	ShowMessage(`Wearing {Entry.DisplayName}'s avatar. Save it under Outfits to keep it.`, true)

	return true
end

function SharedAvatars.Start()
	if Zap == nil then
		return
	end

	Zap.AvatarShared.SetCallback(function(DisplayName)
		-- Show it next time the tab is looked at
		LastRefresh = -math.huge
		SharedAvatars.AvatarShared:Fire(DisplayName)
	end)
end

return SharedAvatars
