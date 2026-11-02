-- Shared avatars: a player can share the avatar they're wearing with an optional caption,
-- and everyone (in every server) can browse the newest shared avatars and try them on.
-- Each player has at most one shared avatar; sharing again replaces it.
--
-- Shares live in a MemoryStore sorted map (newest first) and expire after SHARE_LIFETIME.
-- If MemoryStore can't be reached (e.g. Studio without API access), this server keeps its
-- own list instead, so the feature still works in single-server tests.

local EncodingService = game:GetService("EncodingService")
local MemoryStoreService = game:GetService("MemoryStoreService")
local TextService = game:GetService("TextService")

local Avalog = script.Parent.Parent.Parent
local Zap = require(Avalog.SourceCode.Shared.Zap.server)
local RateLimit = require(Avalog.Parent.RateLimit)
local EnumSerDes = require(Avalog.Parent.EnumSerDes)
local Squash = require(Avalog.Parent.Squash)
local Sift = require(Avalog.Parent.Sift)
local AvatarDataSerDes = require(Avalog.SourceCode.Server.PlayerDataStorage.SerDes.AvatarData)
local Shared = require(Avalog.SourceCode.Shared.SharedAvatars)
local Config = require(Avalog.Config)

local CONFIG = Config:Get()
local MAP_NAME = "AvalogSharedAvatars"
local SHARE_LIFETIME = 7 * 24 * 60 * 60
local CACHE_TIME = 10
local RATE_LIMITS = {
	Read = RateLimit(6, 10),
	Share = RateLimit(2, 30),
	Unshare = RateLimit(3, 30),
}

type Entry = {
	UserId: number,
	DisplayName: string,
	Caption: string,
	SharedAt: number,
	Encoded: string, -- base64 of the Squash-encoded avatar data
}

type Result = {
	Ok: boolean,
	Message: string?,
	Avatars: { any },
	Mine: boolean,
}

local SharedAvatars = {}

local Map = MemoryStoreService:GetSortedMap(MAP_NAME)
local UseLocal = false -- set once MemoryStore fails
local LocalEntries: { [string]: Entry } = {}

local Cache: { Entry }? = nil
local CacheTime = 0

local function Encode(AvatarData): string
	local Cursor = Squash.cursor()
	AvatarDataSerDes.ser(Cursor, AvatarData)
	return buffer.tostring(EncodingService:Base64Encode(Squash.tobuffer(Cursor)))
end

local function Decode(Encoded: string)
	local Bytes = EncodingService:Base64Decode(buffer.fromstring(Encoded))
	return AvatarDataSerDes.des(Squash.frombuffer(Bytes))
end

local function IsEntry(Value): boolean
	return type(Value) == "table"
		and type(Value.UserId) == "number"
		and type(Value.DisplayName) == "string"
		and type(Value.Caption) == "string"
		and type(Value.SharedAt) == "number"
		and type(Value.Encoded) == "string"
end

local function SwitchToLocal(Problem)
	if not UseLocal then
		UseLocal = true
		warn("[Avalog] Shared avatars are kept per server: MemoryStore failed:", Problem)
	end
end

-- Newest shared avatars first.
local function FetchEntries(): { Entry }
	if Cache and os.clock() - CacheTime < CACHE_TIME then
		return Cache
	end

	local Entries = {}

	if not UseLocal then
		local Ok, Items = pcall(function()
			return Map:GetRangeAsync(Enum.SortDirection.Descending, Shared.MAX_LISTED)
		end)

		if Ok then
			for _, Item in ipairs(Items) do
				if IsEntry(Item.value) then
					table.insert(Entries, Item.value)
				end
			end
		else
			SwitchToLocal(Items)
		end
	end

	if UseLocal then
		for _, Entry in pairs(LocalEntries) do
			if os.time() - Entry.SharedAt < SHARE_LIFETIME then
				table.insert(Entries, Entry)
			end
		end
		table.sort(Entries, function(A, B)
			return A.SharedAt > B.SharedAt
		end)
		Entries = Sift.Array.slice(Entries, 1, Shared.MAX_LISTED)
	end

	Cache = Entries
	CacheTime = os.clock()

	return Entries
end

local function Forget()
	Cache = nil
end

local function Reply(Player: Player, Ok: boolean, Message: string?): Result
	local Avatars = {}
	local Mine = false

	for _, Entry in ipairs(FetchEntries()) do
		local DecodeOk, AvatarData = pcall(Decode, Entry.Encoded)

		if DecodeOk then
			if Entry.UserId == Player.UserId then
				Mine = true
			end

			table.insert(Avatars, {
				UserId = Entry.UserId,
				DisplayName = Shared.Clean(Entry.DisplayName, Shared.MAX_DISPLAY_NAME_BYTES),
				Caption = Shared.Clean(Entry.Caption, Shared.MAX_CAPTION_BYTES),
				SharedAt = Entry.SharedAt,
				Data = EnumSerDes.SerializeTree(AvatarData),
			})
		end
	end

	return {
		Ok = Ok,
		Message = Message,
		Avatars = Avatars,
		Mine = Mine,
	}
end

-- Captions are seen by everyone, so they use the broadcast filter.
local function FilterCaption(Player: Player, Caption: string): string?
	if Caption == "" then
		return ""
	end

	local Ok, Result = pcall(function()
		local Filtered = TextService:FilterStringAsync(Caption, Player.UserId)
		return Filtered:GetNonChatStringForBroadcastAsync()
	end)

	if Ok and type(Result) == "string" then
		return Shared.Clean(Result, Shared.MAX_CAPTION_BYTES)
	end

	return nil
end

function SharedAvatars:Get(Player: Player): Result
	return Reply(Player, true, nil)
end

function SharedAvatars:Share(Player: Player, Caption: string, Data): Result
	-- Re-encoding checks the avatar data is well formed.
	local Ok, Encoded = pcall(function()
		local AvatarData = EnumSerDes.DeserializeTree(Data)
		if #AvatarData.Accessories > CONFIG.Limits.Accessories then
			AvatarData.Accessories = Sift.Array.slice(AvatarData.Accessories, 1, CONFIG.Limits.Accessories)
		end
		return Encode(AvatarData)
	end)
	if not Ok then
		return Reply(Player, false, "That avatar couldn't be shared.")
	end

	local SafeCaption = FilterCaption(Player, Shared.Clean(Caption, Shared.MAX_CAPTION_BYTES))
	if SafeCaption == nil then
		return Reply(Player, false, "Couldn't check that caption. Try again.")
	end

	local Entry: Entry = {
		UserId = Player.UserId,
		DisplayName = Shared.Clean(Player.DisplayName, Shared.MAX_DISPLAY_NAME_BYTES),
		Caption = SafeCaption,
		SharedAt = os.time(),
		Encoded = Encoded,
	}
	local Key = tostring(Player.UserId)

	if not UseLocal then
		local SetOk, Problem = pcall(function()
			Map:SetAsync(Key, Entry, SHARE_LIFETIME, Entry.SharedAt)
		end)
		if not SetOk then
			SwitchToLocal(Problem)
		end
	end
	if UseLocal then
		LocalEntries[Key] = Entry
	end

	Forget()

	-- Let everyone in this server know there's something new to try on
	Zap.AvatarShared.FireAll(Entry.DisplayName)

	return Reply(Player, true, "Shared! Everyone can try on your avatar now.")
end

function SharedAvatars:Unshare(Player: Player): Result
	local Key = tostring(Player.UserId)

	if not UseLocal then
		local Ok, Problem = pcall(function()
			Map:RemoveAsync(Key)
		end)
		if not Ok then
			return Reply(Player, false, "Couldn't remove it right now. Try again.")
		end
	end
	LocalEntries[Key] = nil

	Forget()

	return Reply(Player, true, "Your avatar is no longer shared.")
end

-- Rate limits a request and always answers, even when the handler errors
-- (Zap leaves the client waiting forever otherwise).
local function Handle(Player: Player, Limit, Handler: () -> Result): Result
	if not Limit(Player.UserId) then
		local Ok, Result = pcall(Reply, Player, false, "Slow down a little and try again.")
		return if Ok then Result else { Ok = false, Message = "Slow down a little and try again.", Avatars = {}, Mine = false }
	end

	local Ok, Result = pcall(Handler)
	if Ok then
		return Result
	end

	warn("[Avalog] Shared avatar request failed:", Result)

	return { Ok = false, Message = "Something went wrong. Try again.", Avatars = {}, Mine = false }
end

function SharedAvatars:Start()
	Zap.GetSharedAvatars.SetCallback(function(Player)
		return Handle(Player, RATE_LIMITS.Read, function()
			return SharedAvatars:Get(Player)
		end)
	end)

	Zap.ShareAvatar.SetCallback(function(Player, Caption, Data)
		return Handle(Player, RATE_LIMITS.Share, function()
			return SharedAvatars:Share(Player, Caption, Data)
		end)
	end)

	Zap.UnshareAvatar.SetCallback(function(Player)
		return Handle(Player, RATE_LIMITS.Unshare, function()
			return SharedAvatars:Unshare(Player)
		end)
	end)
end

return SharedAvatars
