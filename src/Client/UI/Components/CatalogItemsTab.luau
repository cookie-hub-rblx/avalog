local Avalog = script.Parent.Parent.Parent.Parent.Parent
local OnyxUI = require(Avalog.Parent.OnyxUI)
local Fusion = require(Avalog.Parent.Fusion)
local CatalogSearch = require(Avalog.SourceCode.Client.UI.StateExtensions.CatalogSearch)
local Navigation = require(Avalog.SourceCode.Client.UI.StateExtensions.Navigation)
local States = require(Avalog.SourceCode.Client.UI.States)
local Sift = require(Avalog.Parent.Sift)

export type Props = {
	PrefixItems: Fusion.UsedAs<{ [string]: any }>?,
	LoadItems: Fusion.UsedAs<boolean>?,
	Shown: Fusion.UsedAs<boolean>?,
}

return function(Scope: Fusion.Scope<any>, Props: Props)
	local Scope = Fusion.innerScope(Scope, Fusion, OnyxUI.Util, OnyxUI.Components, {
		ItemsTab = require(script.Parent.ItemsTab),
	})

	local Shown = OnyxUI.Util.Fallback(Props.Shown, false)
	local PrefixItems = OnyxUI.Util.Fallback(Props.PrefixItems, {})
	local LoadItems = OnyxUI.Util.Fallback(Props.LoadItems, true)

	local DeepestCategory = Scope:Computed(function(Use)
		local CategoryValue = Use(Navigation.Category)
		local SubCategoryValue = Use(Navigation.SubCategory)

		if SubCategoryValue ~= nil then
			return SubCategoryValue
		else
			return CategoryValue
		end
	end)
	local BundleTypes = Scope:Computed(function(Use)
		local DeepestCategoryValue = Use(DeepestCategory)

		if DeepestCategoryValue and DeepestCategoryValue.BundleTypes then
			return DeepestCategoryValue.BundleTypes
		else
			return {}
		end
	end)
	local AssetTypes = Scope:Computed(function(Use)
		local DeepestCategoryValue = Use(DeepestCategory)

		if DeepestCategoryValue and DeepestCategoryValue.AssetTypes then
			return DeepestCategoryValue.AssetTypes
		else
			return {}
		end
	end)

	local Search = Scope:Value(nil)
	local Results = Scope:Value({})

	local Alive = true
	local UpdatedConnection = nil
	local SearchScheduled = false
	table.insert(Scope, function()
		Alive = false
		if UpdatedConnection ~= nil then
			UpdatedConnection:Disconnect()
			UpdatedConnection = nil
		end
	end)

	local function UpdateSearch()
		SearchScheduled = false

		if not Alive then
			return
		end
		if not Fusion.peek(Shown) then
			return
		end
		if not Fusion.peek(LoadItems) then
			return
		end

		local BundleTypesValue = Fusion.peek(BundleTypes)
		local AssetTypesValue = Fusion.peek(AssetTypes)
		local SearchQueryValue = Fusion.peek(States.Catalog.SearchQuery)
		local DeepestCategoryValue = Fusion.peek(DeepestCategory)

		local Searching = string.len((SearchQueryValue or "")) == 0

		local SearchObject = CatalogSearch.Search({
			BundleTypes = BundleTypesValue,
			AssetTypes = AssetTypesValue,
			SearchKeyword = SearchQueryValue,
			CategoryFilter = (Searching and DeepestCategoryValue and DeepestCategoryValue.CategoryFilter) or nil,
		})

		if SearchObject == Fusion.peek(Search) then
			return
		end

		-- Only the current search may update the results; an older one finishing late is ignored
		if UpdatedConnection ~= nil then
			UpdatedConnection:Disconnect()
		end
		UpdatedConnection = SearchObject.Updated:Connect(function()
			if Alive and Fusion.peek(Search) == SearchObject then
				Results:set(SearchObject.Results)
			end
		end)

		Search:set(SearchObject)
		Results:set(SearchObject.Results)
	end

	-- A category click changes the category, its sub-category, asset and bundle types
	-- one after another. Wait for the last one and search once.
	local function ScheduleSearch()
		if SearchScheduled then
			return
		end
		SearchScheduled = true
		task.defer(UpdateSearch)
	end
	Scope:Observer(BundleTypes):onChange(ScheduleSearch)
	Scope:Observer(AssetTypes):onChange(ScheduleSearch)
	Scope:Observer(States.Catalog.SearchQuery):onChange(ScheduleSearch)
	Scope:Observer(DeepestCategory):onChange(ScheduleSearch)
	if typeof(LoadItems) == "table" then
		Scope:Observer(LoadItems):onChange(ScheduleSearch)
	end
	UpdateSearch()

	local CombinedItems = Scope:Computed(function(Use)
		local ResultsValue = Use(Results)
		local PrefixItemsValue = Use(PrefixItems)
		local SearchQueryValue = Use(States.Catalog.SearchQuery)

		if (SearchQueryValue == nil) or (SearchQueryValue == "") then
			return Sift.Array.concat(PrefixItemsValue, ResultsValue)
		else
			return ResultsValue
		end
	end)

	return Scope:ItemsTab(OnyxUI.Util.CombineProps(Props, {
		Name = script.Name,
		Items = Scope:ForValues(CombinedItems, function(Use, Scope, Item)
			if typeof(Item.ItemType) == "string" then
				Item.ItemType = Enum.AvatarItemType[Item.ItemType]
			end

			return {
				Id = Item.Id,
				Type = Item.ItemType,
				Featured = Item.Featured,
			}
		end),

		OnReachedEnd = function()
			local SearchValue = Fusion.peek(Search)

			if SearchValue ~= nil then
				SearchValue:LoadNextPage()
			end
		end,
	}))
end
