--!strict

local ProductionModel = {}
ProductionModel.__index = ProductionModel

export type Config = {
	Interval: number,
	TravelTime: number,
	Value: number,
}

export type Ore = { id: number, progress: number, value: number }
type ValueEpoch = { firstDrop: number, value: number }

type State = {
	_interval: number,
	_travelTime: number,
	_value: number,
	_valueEpochs: { ValueEpoch },
	_age: number,
	_paidDropCount: number,
}

local function isFinite(value: any): boolean
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function completedDrops(age: number, interval: number, travelTime: number): number
	if age < travelTime then
		return 0
	end
	return math.floor((age - travelTime) / interval) + 1
end

function ProductionModel.new(config: Config)
	assert(type(config) == "table", "ProductionModel config must be a table")
	assert(isFinite(config.Interval) and config.Interval > 0, "Interval must be finite and positive")
	assert(isFinite(config.TravelTime) and config.TravelTime > 0, "TravelTime must be finite and positive")
	assert(isFinite(config.Value) and config.Value >= 0 and config.Value % 1 == 0,
		"Value must be a finite non-negative integer")

	return setmetatable({
		_interval = config.Interval,
		_travelTime = config.TravelTime,
		_value = config.Value,
		_valueEpochs = { { firstDrop = 0, value = config.Value } },
		_age = 0,
		_paidDropCount = 0,
	}, ProductionModel)
end

function ProductionModel.SetValue(self: State, value: number)
	assert(isFinite(value) and value >= 0 and value % 1 == 0,
		"Value must be a finite non-negative integer")
	-- The ore emitted at the current instant already exists and keeps its value.
	local firstDrop = math.floor(self._age / self._interval) + 1
	local epochs = self._valueEpochs
	local latest = epochs[#epochs]
	if latest.firstDrop == firstDrop then
		latest.value = value
		if #epochs > 1 and epochs[#epochs - 1].value == value then
			table.remove(epochs)
		end
	elseif latest.value ~= value then
		table.insert(epochs, { firstDrop = firstDrop, value = value })
	end
	self._value = value
end

function ProductionModel.Advance(self: State, elapsedSeconds: number): (number, number)
	assert(isFinite(elapsedSeconds) and elapsedSeconds >= 0, "elapsedSeconds must be finite and non-negative")
	local age = self._age + elapsedSeconds
	assert(isFinite(age) and isFinite(age / self._interval), "Production time exceeds numeric range")
	local completed = completedDrops(age, self._interval, self._travelTime)
	local count = completed - self._paidDropCount
	local credited = 0
	local epochs = self._valueEpochs
	for index, epoch in ipairs(epochs) do
		local first = math.max(self._paidDropCount, epoch.firstDrop)
		local nextEpoch = epochs[index + 1]
		local finish = if nextEpoch then math.min(completed, nextEpoch.firstDrop) else completed
		if finish > first then credited += (finish - first) * epoch.value end
	end
	assert(isFinite(credited), "Production credit exceeds numeric range")
	self._age = age
	self._paidDropCount = completed
	-- Keep only epochs that can affect uncollected ore, even after long sessions.
	while #epochs > 1 and epochs[2].firstDrop <= completed do table.remove(epochs, 1) end
	return credited, count
end

function ProductionModel.GetActiveOres(self: State): { Ore }
	local ores: { Ore } = {}
	local firstDrop = completedDrops(self._age, self._interval, self._travelTime)
	local lastDrop = math.floor(self._age / self._interval)
	-- IDs are derived from spawn time; historical drops are never visited.
	for dropIndex = firstDrop, lastDrop do
		local value = self._valueEpochs[1].value
		for _, epoch in ipairs(self._valueEpochs) do
			if epoch.firstDrop > dropIndex then break end
			value = epoch.value
		end
		table.insert(ores, {
			id = dropIndex + 1,
			progress = (self._age - dropIndex * self._interval) / self._travelTime,
			value = value,
		})
	end
	return ores
end

return ProductionModel
