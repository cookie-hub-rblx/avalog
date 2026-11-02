--[[
	Exposes the current unix timestamp as a Fusion.Value
]]

local RunService = game:GetService("RunService")

local Avalog = script.Parent.Parent.Parent.Parent.Parent
local Fusion = require(Avalog.Parent.Fusion)
local States = require(script.Parent.Parent.States)

local Time = {
	_RenderStep = nil :: RBXScriptConnection?,
}

function Time.Start(self: typeof(Time))
	self._RenderStep = RunService.RenderStepped:Connect(function()
		-- Only animations inside the open menu read this
		if Fusion.peek(States.Open) then
			States.UnixTimestamp:set(DateTime.now().UnixTimestampMillis)
		end
	end)
end

function Time.Destroy(self: typeof(Time))
	if self._RenderStep ~= nil then
		self._RenderStep:Disconnect()
		self._RenderStep = nil
	end
end

return Time
