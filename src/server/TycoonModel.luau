--!strict
-- Pure server-owned economy. Apply never yields or trusts a client's price.
local TycoonModel = {}
TycoonModel.__index = TycoonModel

type Level = { Value: number, Cost: number? }
type Dropper = {
	Id: number, Name: string, Price: number, RequiredExpansion: number,
	Prerequisite: number?, Z: number, TravelTime: number, Levels: { Level },
}
type Expansion = { Price: number, Prerequisite: number? }
type Config = {
	Production: { Interval: number }, Droppers: { [number]: Dropper },
	Expansions: { [number]: Expansion },
}
export type Result = { ok: boolean, code: string, message: string, requestId: string }
type Cached = { kind: string, targetId: number, expectedLevel: number?, result: Result }
type State = {
	config: Config, ownerUserId: number, money: number,
	droppers: { [number]: number }, expansion: number,
	_requestResults: { [string]: Cached }, _requestOrder: { string },
}
local MAX_INTEGER = 9007199254740991

local function isInteger(value: any): boolean
	return type(value) == "number" and value == value and math.abs(value) <= MAX_INTEGER and value % 1 == 0
end

local function result(ok: boolean, code: string, message: string, requestId: string): Result
	return table.freeze({ ok = ok, code = code, message = message, requestId = requestId })
end

function TycoonModel.new(config: Config, ownerUserId: number)
	assert(isInteger(ownerUserId), "Owner must be an integer user ID")
	assert(type(config) == "table" and type(config.Droppers) == "table" and config.Droppers[1],
		"A starter dropper is required")
	assert(config.Production.Interval > 0 and config.Production.Interval < math.huge,
		"Production interval must be finite and positive")
	return setmetatable({
		config = config, ownerUserId = ownerUserId, money = 0,
		droppers = { [1] = 1 }, expansion = 0,
		_requestResults = {}, _requestOrder = {},
	}, TycoonModel)
end

function TycoonModel.Credit(self: State, amount: number)
	assert(isInteger(amount) and amount >= 0, "Credit must be a non-negative safe integer")
	assert(self.money <= MAX_INTEGER - amount, "Balance exceeds numeric range")
	self.money += amount
end

function TycoonModel.GetIncomePerSecond(self: State): number
	local income = 0
	for id, level in pairs(self.droppers) do
		income += self.config.Droppers[id].Levels[level].Value / self.config.Production.Interval
	end
	return income
end

function TycoonModel.HasDropper(self: State, id: number): boolean
	return self.droppers[id] ~= nil
end

function TycoonModel.Apply(self: State, actorId: any, action: any): Result
	local requestId = ""
	if type(action) == "table" and type(action.requestId) == "string"
		and #action.requestId > 0 and #action.requestId <= 72 then
		requestId = action.requestId
	end
	-- Invalid and foreign requests never reserve or overwrite an owner's request ID.
	if not isInteger(actorId) or actorId ~= self.ownerUserId then
		return result(false, "forbidden", "Это не твоя база.", requestId)
	end
	if type(action) ~= "table" or requestId == "" or not isInteger(action.targetId)
		or action.targetId < 1 then
		return result(false, "malformed", "Некорректная покупка.", requestId)
	end
	local kind, id = action.kind, action.targetId
	if kind ~= "BuyDropper" and kind ~= "UpgradeDropper" and kind ~= "ExpandBase" then
		return result(false, "malformed", "Неизвестная покупка.", requestId)
	end
	local definition = if kind == "ExpandBase" then self.config.Expansions[id] else self.config.Droppers[id]
	if not definition or (kind == "UpgradeDropper"
		and (not isInteger(action.expectedLevel) or action.expectedLevel < 1)) then
		return result(false, "malformed", "Некорректная покупка.", requestId)
	end
	local expectedLevel = if kind == "UpgradeDropper" then action.expectedLevel else nil
	local cached = self._requestResults[requestId]
	if cached then
		if cached.kind ~= kind or cached.targetId ~= id or cached.expectedLevel ~= expectedLevel then
			return result(false, "request_conflict", "Запрос уже использован для другой покупки.", requestId)
		end
		return cached.result
	end
	local function finish(ok: boolean, code: string, message: string): Result
		local response = result(ok, code, message, requestId)
		self._requestResults[requestId] = {
			kind = kind, targetId = id, expectedLevel = expectedLevel, result = response,
		}
		table.insert(self._requestOrder, requestId)
		if #self._requestOrder > 128 then
			local oldest = table.remove(self._requestOrder, 1)
			self._requestResults[oldest] = nil
		end
		return response
	end
	local price: number
	if kind == "BuyDropper" then
		local dropper = self.config.Droppers[id]
		if self.droppers[id] then return finish(false, "already_owned", "Дроппер уже куплен.") end
		if self.expansion < dropper.RequiredExpansion then return finish(false, "land_locked", "Сначала расширь базу.") end
		if dropper.Prerequisite and not self.droppers[dropper.Prerequisite] then
			return finish(false, "prerequisite", "Сначала купи предыдущий дроппер.")
		end
		price = dropper.Price
	elseif kind == "UpgradeDropper" then
		local level = self.droppers[id]
		if not level then return finish(false, "not_owned", "Сначала купи дроппер.") end
		if level ~= expectedLevel then return finish(false, "stale_level", "Уровень уже изменился.") end
		local nextLevel = self.config.Droppers[id].Levels[level + 1]
		if not nextLevel then return finish(false, "max_level", "Достигнут максимальный уровень.") end
		price = nextLevel.Cost :: number
	else
		if id ~= self.expansion + 1 then return finish(false, "land_locked", "Расширения покупаются по порядку.") end
		local expansion = self.config.Expansions[id]
		if expansion.Prerequisite and not self.droppers[expansion.Prerequisite] then
			return finish(false, "prerequisite", "Сначала купи предыдущий дроппер.")
		end
		price = expansion.Price
	end
	assert(isInteger(price) and price >= 0, "Purchase price must be a non-negative safe integer")
	if self.money < price then return finish(false, "insufficient_funds", "Недостаточно денег.") end
	-- All checks precede this single synchronous transition.
	self.money -= price
	if kind == "BuyDropper" then self.droppers[id] = 1
	elseif kind == "UpgradeDropper" then self.droppers[id] += 1
	else self.expansion = id end
	return finish(true, "ok", "Покупка выполнена.")
end

return TycoonModel
