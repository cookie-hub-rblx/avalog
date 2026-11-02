local AvatarEditorService = game:GetService("AvatarEditorService")

local Avalog = script.Parent.Parent.Parent.Parent.Parent
local Future = require(Avalog.Parent.Future)
local Signal = require(Avalog.Parent.Signal)
local CatalogItems = require(script.Parent.CatalogItems)

export type SearchParams = {
	SearchKeyword: string?,
	MinPrice: number?,
	MaxPrice: number?,
	SortType: Enum.CatalogSortType?,
	SortAggregation: Enum.CatalogSortAggregation?,
	CategoryFilter: Enum.CatalogCategoryFilter?,
	SalesTypeFilter: Enum.SalesTypeFilter?,
	BundleTypes: { Enum.BundleType }?,
	AssetTypes: { Enum.AvatarAssetType }?,
	IncludeOffSale: boolean?,
	CreatorName: string?,
	Limit: number?,
}

-- Finished searches are kept for the session, so going back to a category is instant
local MAX_CACHED_SEARCHES = 32

local CatalogSearch = {
	_Cache = {} :: { [string]: any },
	_CacheOrder = {} :: { string },
}

local function ListKey(List: { EnumItem }?): string
	if List == nil then
		return ""
	end

	local Names = table.create(#List)
	for Index, Item in ipairs(List) do
		Names[Index] = Item.Name
	end
	table.sort(Names)

	return table.concat(Names, ",")
end

local function SearchKey(Params: SearchParams): string
	local Parts = {}
	for Key, Value in pairs(Params) do
		local ValueKey
		if typeof(Value) == "table" then
			ValueKey = ListKey(Value)
		else
			ValueKey = tostring(Value)
		end
		table.insert(Parts, `{Key}={ValueKey}`)
	end
	table.sort(Parts)

	return table.concat(Parts, ";")
end

function CatalogSearch._Forget(Key: string)
	CatalogSearch._Cache[Key] = nil
	local Index = table.find(CatalogSearch._CacheOrder, Key)
	if Index then
		table.remove(CatalogSearch._CacheOrder, Index)
	end
end

function CatalogSearch._Remember(Key: string, Search)
	CatalogSearch._Cache[Key] = Search
	table.insert(CatalogSearch._CacheOrder, Key)

	while #CatalogSearch._CacheOrder > MAX_CACHED_SEARCHES do
		local OldestKey = table.remove(CatalogSearch._CacheOrder, 1)
		CatalogSearch._Cache[OldestKey] = nil
	end
end

--[[
	Returns a search for these params, reusing an earlier one from this session if possible.
]]
function CatalogSearch.Search(Params: SearchParams)
	local Key = SearchKey(Params)
	local Cached = CatalogSearch._Cache[Key]

	if Cached ~= nil then
		-- Move to the back of the eviction order
		local Index = table.find(CatalogSearch._CacheOrder, Key)
		if Index then
			table.remove(CatalogSearch._CacheOrder, Index)
			table.insert(CatalogSearch._CacheOrder, Key)
		end
		return Cached
	end

	local Search = CatalogSearch._NewSearch(Params, Key)
	CatalogSearch._Remember(Key, Search)

	return Search
end

function CatalogSearch._NewSearch(Params: SearchParams, Key: string)
	local Search = {
		Results = {},
		Pages = nil,
		Updated = Signal.new(),
		_LoadingPage = false,
	}

	function Search:LoadNextPage()
		-- One page request at a time; scrolling fires this repeatedly
		if self._LoadingPage or self.Pages == nil or self.Pages.IsFinished then
			return nil
		end
		self._LoadingPage = true

		return Future.Try(function()
			self.Pages:AdvanceToNextPageAsync()

			return self.Pages:GetCurrentPage()
		end):After(function(Success, Result)
			self._LoadingPage = false

			if Success and Result then
				self:_LoadPage(Result)
			end
		end)
	end

	function Search:_LoadPage(Page: { [number]: any })
		for _, Entry in ipairs(Page) do
			local Tables = {
				Asset = CatalogItems.KnownAssets,
				Bundle = CatalogItems.KnownBundles,
			}
			local AppropriateTable = Tables[Entry.ItemType]

			if AppropriateTable then
				local Item: CatalogItems.CatalogItem = {
					Id = Entry.Id,
					Name = Entry.Name,
					Price = Entry.Price,
					Offsale = Entry.IsOffSale,
					Type = Enum.AvatarItemType[Entry.ItemType],
					AssetType = (Entry.AssetType and Enum.AvatarAssetType[Entry.AssetType]) or nil,
					Description = Entry.Description,
					Creator = {
						Id = Entry.CreatorTargetId,
						Type = Entry.CreatorType,
						Name = Entry.CreatorName,
						Verified = Entry.CreatorHasVerifiedBadge,
					},
				}

				AppropriateTable[Entry.Id] = Item
			end

			table.insert(self.Results, Entry)
		end

		self.Updated:Fire()
	end

	function Search:Destroy()
		self.Results = {}
		self.Updated:Destroy()

		if self.Pages ~= nil then
			self.Pages:Destroy()
		end
	end

	CatalogSearch.Pages(Params):After(function(Success, Result)
		if Success then
			Search.Pages = Result
			Search:_LoadPage(Result:GetCurrentPage())
		elseif CatalogSearch._Cache[Key] == Search then
			-- Failed (often a rate limit): try again next time this category opens
			CatalogSearch._Forget(Key)
		end
	end)

	return Search
end

function CatalogSearch.Pages(Params: SearchParams)
	local CatalogSearchParams = CatalogSearch.Params(Params)

	return Future.Try(function()
		return AvatarEditorService:SearchCatalog(CatalogSearchParams)
	end)
end

function CatalogSearch.Params(Params: SearchParams)
	local CatalogSearchParams = CatalogSearchParams.new()

	for Key, Value in pairs(Params) do
		CatalogSearchParams[Key] = Value
	end

	return CatalogSearchParams
end

function CatalogSearch:Stop() end

return CatalogSearch
