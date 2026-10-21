--!strict

local PlotRegistry = {}
PlotRegistry.__index = PlotRegistry

type State = {
	_capacity: number,
	_ownersByPlot: { [number]: number },
	_plotsByOwner: { [number]: number },
}

local function isInteger(value: any): boolean
	return type(value) == "number" and value == value and math.abs(value) < math.huge and value % 1 == 0
end

function PlotRegistry.new(capacity: number)
	assert(isInteger(capacity) and capacity > 0, "Plot capacity must be a finite positive integer")
	return setmetatable({
		_capacity = capacity,
		_ownersByPlot = {} :: { [number]: number },
		_plotsByOwner = {} :: { [number]: number },
	}, PlotRegistry)
end

function PlotRegistry.Get(self: State, userId: number): number?
	assert(isInteger(userId), "userId must be a finite integer")
	return self._plotsByOwner[userId]
end

function PlotRegistry.Claim(self: State, userId: number): number?
	assert(isInteger(userId), "userId must be a finite integer")
	local existingPlot = self._plotsByOwner[userId]
	if existingPlot then
		return existingPlot
	end
	for plotId = 1, self._capacity do
		if self._ownersByPlot[plotId] == nil then
			self._ownersByPlot[plotId] = userId
			self._plotsByOwner[userId] = plotId
			return plotId
		end
	end
	return nil
end

function PlotRegistry.Release(self: State, userId: number): number?
	assert(isInteger(userId), "userId must be a finite integer")
	local plotId = self._plotsByOwner[userId]
	if plotId == nil then
		return nil
	end
	self._plotsByOwner[userId] = nil
	if self._ownersByPlot[plotId] == userId then
		self._ownersByPlot[plotId] = nil
		return plotId
	end
	return nil
end

return PlotRegistry
