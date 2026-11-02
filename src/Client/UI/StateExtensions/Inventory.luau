local AvatarEditorService = game:GetService("AvatarEditorService")

local Avalog = script.Parent.Parent.Parent.Parent.Parent
local States = require(script.Parent.Parent.States)
local Future = require(Avalog.Parent.Future)
local Signal = require(Avalog.Parent.Signal)

local Inventory = {}

function Inventory.Search(AssetTypes: { Enum.AvatarAssetType })
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

	Inventory.Pages(AssetTypes):After(function(Success, Result)
		if Success then
			Search.Pages = Result
			Search:_LoadPage(Result:GetCurrentPage())
		end
	end)

	return Search
end

function Inventory.Pages(AssetTypes: { Enum.AvatarAssetType }?)
	return Future.Try(function()
		return AvatarEditorService:GetInventory(AssetTypes)
	end)
end

function Inventory:Start()
	AvatarEditorService.PromptAllowInventoryReadAccessCompleted:Connect(function(Result)
		if Result == Enum.AvatarPromptResult.Success then
			States.Inventory.AccessAllowed:set(true)
		else
			States.Inventory.AccessAllowed:set(false)
		end
	end)
end

return Inventory
