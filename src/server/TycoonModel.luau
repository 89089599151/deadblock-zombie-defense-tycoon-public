--!strict
-- Pure server-owned economy and progression. Apply never yields and never trusts a client's price.
local TurretMath = require(game:GetService("ReplicatedStorage"):WaitForChild("DeadblockShared"):WaitForChild("TurretMath"))

local DailyModel = require(script.Parent.DailyModel)

local TycoonModel = {}
TycoonModel.__index = TycoonModel

export type Result = { ok: boolean, code: string, message: string, requestId: string }
export type Turret = { type: string, level: number, modules: { [string]: number } }
export type WorldProgress = { wave: number, best: number }

local MAX_INTEGER = 9007199254740991
local PADS_PER_LEVEL = 8
local KINDS = {
	BuyDropper = true, UpgradeDropper = true, ExpandBase = true, BuildTurret = true, UpgradeTurret = true,
	SellTurret = true, UpgradeWalls = true, HireEngineer = true, BuyPortal = true, UpgradeModule = true, Overdrive = true,
}
local LEVELED = { UpgradeDropper = true, UpgradeTurret = true, SellTurret = true, UpgradeWalls = true, HireEngineer = true, UpgradeModule = true }

local function isInteger(value: any): boolean
	return type(value) == "number" and value == value and math.abs(value) <= MAX_INTEGER and value % 1 == 0
end

local function result(ok: boolean, code: string, message: string, requestId: string): Result
	return table.freeze({ ok = ok, code = code, message = message, requestId = requestId })
end

function TycoonModel.new(config: any, ownerUserId: number)
	assert(isInteger(ownerUserId), "Owner must be an integer user ID")
	assert(type(config) == "table" and type(config.Droppers) == "table" and config.Droppers[1], "A starter dropper is required")
	return setmetatable({
		config = config, ownerUserId = ownerUserId, money = 0,
		worldId = 1, unlockedWorld = 1, droppers = { [1] = 1 } :: { [number]: number }, expansion = 0,
		turrets = {} :: { [number]: Turret }, wallLevel = 1, engineers = 0, tutorial = 1, freeTurret = false,
		cores = 0, overdriveUntil = 0, daily = DailyModel.New(), clock = os.time,
		socialBonus = 0, -- not saved: friends on the server
		difficulty = 1,
		waves = { [1] = { wave = 1, best = 0 } } :: { [number]: WorldProgress },
		_requestResults = {}, _requestOrder = {},
	}, TycoonModel)
end

function TycoonModel.PadCount(config: any): number
	return #config.Compound.Levels * PADS_PER_LEVEL
end

function TycoonModel.PadLevel(pad: number): number
	return math.ceil(pad / PADS_PER_LEVEL)
end

function TycoonModel.GetBaseLevel(self: any): number return self.expansion + 1 end
function TycoonModel.GetLevelCap(self: any): number return TurretMath.LevelCap(self.config, self.worldId) end

function TycoonModel.Credit(self: any, amount: number)
	assert(isInteger(amount) and amount >= 0, "Credit must be a non-negative safe integer")
	assert(self.money <= MAX_INTEGER - amount, "Balance exceeds numeric range")
	self.money += amount
end

function TycoonModel.CreditCores(self: any, amount: number)
	assert(isInteger(amount) and amount >= 0, "Cores must be a non-negative integer")
	self.cores += amount
end

function TycoonModel.OverdriveLeft(self: any): number
	return math.max(0, self.overdriveUntil - self.clock())
end

function TycoonModel.Spend(self: any, amount: number)
	assert(isInteger(amount) and amount >= 0 and amount <= self.money, "Invalid spend amount")
	self.money -= amount
end

function TycoonModel.SetWorld(self: any, worldId: any): boolean
	if not isInteger(worldId) or not self.config.Worlds[worldId] or worldId > self.unlockedWorld then return false end
	self.worldId = worldId
	self.difficulty = math.min(self.difficulty, self:MaxDifficulty())
	self:GetProgress()
	return true
end

-- Progress is kept per world and per difficulty: key = world + (difficulty - 1) * 100.
function TycoonModel.ProgressKey(worldId: number, difficulty: number): number
	return worldId + (difficulty - 1) * 100
end

function TycoonModel.GetProgress(self: any, worldId: number?, difficulty: number?): WorldProgress
	local id = TycoonModel.ProgressKey(worldId or self.worldId, difficulty or self.difficulty)
	if not self.waves[id] then self.waves[id] = { wave = 1, best = 0 } end
	return self.waves[id]
end

-- Highest difficulty open in the current world.
function TycoonModel.MaxDifficulty(self: any): number
	local unlocked = 1
	for index = 2, #self.config.Difficulties do
		if self:GetProgress(self.worldId, index - 1).best >= self.config.Difficulties[index].Unlock then unlocked = index else break end
	end
	return unlocked
end

function TycoonModel.SetDifficulty(self: any, difficulty: any): boolean
	if not isInteger(difficulty) or difficulty < 1 or difficulty > self:MaxDifficulty() then return false end
	self.difficulty = difficulty
	return true
end

-- Called by the siege when a wave is cleared in the current world.
function TycoonModel.RecordWave(self: any, nextWave: number, best: number)
	local progress = self:GetProgress()
	progress.wave = nextWave
	progress.best = math.max(progress.best, best)
end

function TycoonModel.GetDropperValue(self: any, id: number, level: number): number
	local boost = if self:OverdriveLeft() > 0 then self.config.Overdrive.Multiplier else 1
	return self.config.Droppers[id].Levels[level].Value * self.config.Worlds[self.worldId].DropperMultiplier * boost * (1 + self.socialBonus)
end

function TycoonModel.GetIncomePerSecond(self: any): number
	local income = 0
	for id, level in pairs(self.droppers) do income += self:GetDropperValue(id, level) / self.config.Production.Interval end
	return income
end

function TycoonModel.HasDropper(self: any, id: number): boolean
	return self.droppers[id] ~= nil
end

function TycoonModel.Apply(self: any, actorId: any, action: any): Result
	local requestId = ""
	if type(action) == "table" and type(action.requestId) == "string" and #action.requestId > 0 and #action.requestId <= 72 then
		requestId = action.requestId
	end
	-- Invalid and foreign requests never reserve or overwrite an owner's request ID.
	if not isInteger(actorId) or actorId ~= self.ownerUserId then
		return result(false, "forbidden", "Это не твоя база.", requestId)
	end
	if type(action) ~= "table" or requestId == "" or not isInteger(action.targetId) or action.targetId < 1 then
		return result(false, "malformed", "Некорректная покупка.", requestId)
	end
	local kind, id = action.kind, action.targetId
	if type(kind) ~= "string" or not KINDS[kind] then return result(false, "malformed", "Неизвестная покупка.", requestId) end
	local config = self.config
	local valid = if kind == "BuyDropper" or kind == "UpgradeDropper" then config.Droppers[id] ~= nil
		elseif kind == "ExpandBase" then config.Expansions[id] ~= nil
		elseif kind == "BuildTurret" or kind == "UpgradeTurret" or kind == "SellTurret" or kind == "UpgradeModule" then id <= TycoonModel.PadCount(config)
		elseif kind == "BuyPortal" then config.Worlds[id] ~= nil
		else id == 1
	local expectedLevel = if LEVELED[kind] then action.expectedLevel else nil
	local minimum = if kind == "HireEngineer" or kind == "UpgradeModule" then 0 else 1
	if not valid or (LEVELED[kind] and (not isInteger(expectedLevel) or expectedLevel < minimum)) then
		return result(false, "malformed", "Некорректная покупка.", requestId)
	end
	local turretType = if kind == "BuildTurret" then action.turretType elseif kind == "UpgradeModule" then action.module else nil
	if kind == "UpgradeModule" and (type(turretType) ~= "string" or not config.Modules[turretType] or turretType == "Order" or turretType == "Costs") then
		return result(false, "malformed", "Неизвестный модуль.", requestId)
	end
	if kind == "BuildTurret" and (type(turretType) ~= "string" or not config.TurretTypes[turretType]) then
		return result(false, "malformed", "Неизвестная турель.", requestId)
	end
	local cached = self._requestResults[requestId]
	if cached then
		if cached.kind ~= kind or cached.targetId ~= id or cached.expectedLevel ~= expectedLevel or cached.turretType ~= turretType then
			return result(false, "request_conflict", "Запрос уже использован для другой покупки.", requestId)
		end
		return cached.result
	end
	local function finish(ok: boolean, code: string, message: string): Result
		local response = result(ok, code, message, requestId)
		self._requestResults[requestId] = { kind = kind, targetId = id, expectedLevel = expectedLevel, turretType = turretType, result = response }
		table.insert(self._requestOrder, requestId)
		if #self._requestOrder > 128 then self._requestResults[table.remove(self._requestOrder, 1)] = nil end
		return response
	end
	local cap = self:GetLevelCap()
	local baseLevel = self:GetBaseLevel()
	local price = 0
	local coreCost = 0
	local refund = 0
	if kind == "BuyDropper" then
		local dropper = config.Droppers[id]
		if self.droppers[id] then return finish(false, "already_owned", "Дроппер уже куплен.") end
		if self.expansion < dropper.RequiredExpansion then return finish(false, "land_locked", "Сначала расширь базу.") end
		if dropper.Prerequisite and not self.droppers[dropper.Prerequisite] then return finish(false, "prerequisite", "Сначала купи предыдущий дроппер.") end
		price = dropper.Price
	elseif kind == "UpgradeDropper" then
		local level = self.droppers[id]
		if not level then return finish(false, "not_owned", "Сначала купи дроппер.") end
		if level ~= expectedLevel then return finish(false, "stale_level", "Уровень уже изменился.") end
		if level >= cap then return finish(false, "max_level", "Это потолок для этого мира. Открой следующий мир.") end
		price = config.Droppers[id].Levels[level + 1].Cost
	elseif kind == "ExpandBase" then
		if id ~= self.expansion + 1 then return finish(false, "land_locked", "Расширения покупаются по порядку.") end
		local expansion = config.Expansions[id]
		if expansion.Prerequisite and not self.droppers[expansion.Prerequisite] then return finish(false, "prerequisite", "Сначала купи дроппер " .. expansion.Prerequisite .. ".") end
		price = expansion.Price
	elseif kind == "BuildTurret" then
		if TycoonModel.PadLevel(id) > baseLevel then return finish(false, "land_locked", "Эта площадка откроется при расширении базы.") end
		if self.turrets[id] then return finish(false, "occupied", "Площадка уже занята.") end
		local definition = config.TurretTypes[turretType]
		if definition.UnlockLevel > baseLevel then return finish(false, "locked", definition.Name .. " откроется на уровне базы " .. definition.UnlockLevel .. ".") end
		price = if self.freeTurret then 0 else definition.Price
	elseif kind == "UpgradeTurret" or kind == "SellTurret" then
		local turret = self.turrets[id]
		if not turret then return finish(false, "not_owned", "На площадке нет турели.") end
		if turret.level ~= expectedLevel then return finish(false, "stale_level", "Уровень уже изменился.") end
		if kind == "UpgradeTurret" then
			if turret.level >= cap then return finish(false, "max_level", "Это потолок для этого мира. Открой следующий мир.") end
			price = TurretMath.UpgradeCost(config, turret.type, turret.level)
		else
			refund = TurretMath.SellValue(config, turret.type, turret.level)
		end
	elseif kind == "UpgradeWalls" then
		if self.wallLevel ~= expectedLevel then return finish(false, "stale_level", "Уровень уже изменился.") end
		if self.wallLevel >= TurretMath.WallCap(config, self.worldId) then return finish(false, "max_level", "Стены на пределе для этого мира.") end
		price = config.Walls.UpgradePrices[self.wallLevel + 1]
	elseif kind == "HireEngineer" then
		if self.engineers ~= expectedLevel then return finish(false, "stale_level", "Число инженеров уже изменилось.") end
		local hire = config.Engineers.Prices[self.engineers + 1]
		if not hire then return finish(false, "max_level", "Команда инженеров полная.") end
		price = hire
	elseif kind == "UpgradeModule" then
		local turret = self.turrets[id]
		if not turret then return finish(false, "not_owned", "На площадке нет турели.") end
		local current = turret.modules[turretType] or 0
		if current ~= expectedLevel then return finish(false, "stale_level", "Уровень уже изменился.") end
		local cost = config.Modules.Costs[current + 1]
		if not cost then return finish(false, "max_level", "Модуль на максимуме.") end
		coreCost = cost
	elseif kind == "Overdrive" then
		if self:OverdriveLeft() > 0 then return finish(false, "active", "Перегрев уже работает.") end
		coreCost = config.Overdrive.Cost
	elseif kind == "BuyPortal" then
		if id <= self.unlockedWorld then return finish(false, "already_owned", "Этот мир уже открыт.") end
		if id ~= self.unlockedWorld + 1 then return finish(false, "land_locked", "Миры открываются по порядку.") end
		local world = config.Worlds[id]
		local previous = self:GetProgress(id - 1, 1)
		if previous.best < world.PortalWave then return finish(false, "requirement", "Нужно пройти волну " .. world.PortalWave .. " в мире «" .. config.Worlds[id - 1].Name .. "».") end
		price = world.PortalPrice
	end
	assert(isInteger(price) and price >= 0, "Purchase price must be a non-negative safe integer")
	if self.money < price then return finish(false, "insufficient_funds", "Недостаточно денег.") end
	if self.cores < coreCost then return finish(false, "insufficient_cores", "Не хватает ядер: нужно " .. coreCost .. ".") end
	self.cores -= coreCost
	-- All checks precede this single synchronous transition.
	self.money -= price
	if kind == "BuyDropper" then self.droppers[id] = 1
	elseif kind == "UpgradeDropper" then self.droppers[id] += 1
	elseif kind == "ExpandBase" then self.expansion = id
	elseif kind == "BuildTurret" then self.turrets[id] = { type = turretType, level = 1, modules = {} } self.freeTurret = false
	elseif kind == "UpgradeModule" then self.turrets[id].modules[turretType] = (self.turrets[id].modules[turretType] or 0) + 1
	elseif kind == "Overdrive" then self.overdriveUntil = self.clock() + config.Overdrive.Duration
	elseif kind == "UpgradeTurret" then self.turrets[id].level += 1
	elseif kind == "SellTurret" then self.turrets[id] = nil self.money += refund
	elseif kind == "UpgradeWalls" then self.wallLevel += 1
	elseif kind == "HireEngineer" then self.engineers += 1
	elseif kind == "BuyPortal" then self.unlockedWorld = id
	end
	local message = if kind == "SellTurret" then "Турель продана: + $ " .. refund else "Готово."
	return finish(true, "ok", message)
end

-- Persistence --------------------------------------------------------------------------------------

function TycoonModel.ToProfile(self: any): { [string]: any }
	local droppers, turrets, waves = {}, {}, {}
	for id, level in pairs(self.droppers) do droppers[tostring(id)] = level end
	for pad, turret in pairs(self.turrets) do turrets[tostring(pad)] = { turret.type, turret.level, table.clone(turret.modules) } end
	for worldId, progress in pairs(self.waves) do waves[tostring(worldId)] = { progress.wave, progress.best } end
	return {
		schema = 1, money = self.money, worldId = self.worldId, unlockedWorld = self.unlockedWorld,
		droppers = droppers, expansion = self.expansion, turrets = turrets, wallLevel = self.wallLevel,
		engineers = self.engineers, waves = waves, tutorial = self.tutorial, freeTurret = self.freeTurret,
		difficulty = self.difficulty, cores = self.cores, overdriveUntil = self.overdriveUntil, daily = self.daily, lastSeen = self.clock(),
	}
end

-- Builds a model from saved data, clamping every field to what the current config allows.
function TycoonModel.FromProfile(config: any, ownerUserId: number, profile: any)
	local self = TycoonModel.new(config, ownerUserId)
	if type(profile) ~= "table" then return self end
	assert(profile.schema == 1, "Unsupported profile schema")
	local function int(value: any, low: number, high: number, fallback: number): number
		if not isInteger(value) then return fallback end
		return math.clamp(value, low, high)
	end
	self.unlockedWorld = int(profile.unlockedWorld, 1, #config.Worlds, 1)
	self.worldId = int(profile.worldId, 1, self.unlockedWorld, 1)
	self.money = int(profile.money, 0, MAX_INTEGER, 0)
	self.expansion = int(profile.expansion, 0, #config.Expansions, 0)
	local cap = config.MaxLevel
	if type(profile.droppers) == "table" then
		for key, level in pairs(profile.droppers) do
			local id = tonumber(key)
			if id and config.Droppers[id] and isInteger(level) then self.droppers[id] = math.clamp(level, 1, cap) end
		end
	end
	self.droppers[1] = self.droppers[1] or 1
	if type(profile.turrets) == "table" then
		for key, entry in pairs(profile.turrets) do
			local pad = tonumber(key)
			if pad and isInteger(pad) and pad >= 1 and pad <= TycoonModel.PadCount(config) and type(entry) == "table"
				and type(entry[1]) == "string" and config.TurretTypes[entry[1]] and isInteger(entry[2]) then
				local modules = {}
				if type(entry[3]) == "table" then
					for name, level in pairs(entry[3]) do
						if type(name) == "string" and config.Modules[name] and isInteger(level) then modules[name] = math.clamp(level, 0, #config.Modules.Costs) end
					end
				end
				self.turrets[pad] = { type = entry[1], level = math.clamp(entry[2], 1, cap), modules = modules }
			end
		end
	end
	self.wallLevel = int(profile.wallLevel, 1, #config.Walls.Health, 1)
	self.engineers = int(profile.engineers, 0, config.Engineers.MaxCount, 0)
	self.tutorial = int(profile.tutorial, 1, #(config.Tutorial or {}) + 1, 1)
	self.freeTurret = profile.freeTurret == true
	self.cores = int(profile.cores, 0, MAX_INTEGER, 0)
	self.overdriveUntil = if type(profile.overdriveUntil) == "number" then profile.overdriveUntil else 0
	self.daily = DailyModel.FromSaved(config, profile.daily)
	self.lastSeen = if type(profile.lastSeen) == "number" then profile.lastSeen else nil
	if type(profile.waves) == "table" then
		for key, entry in pairs(profile.waves) do
			local id = tonumber(key)
			local worldId = id and id % 100
			local difficulty = id and id // 100 + 1
			if id and config.Worlds[worldId] and config.Difficulties[difficulty] and type(entry) == "table" and isInteger(entry[1]) and isInteger(entry[2]) then
				self.waves[id] = { wave = math.max(1, entry[1]), best = math.max(0, entry[2]) }
			end
		end
	end
	self.difficulty = 1
	if isInteger(profile.difficulty) then
		local wanted = profile.difficulty
		self.difficulty = if wanted >= 1 and wanted <= self:MaxDifficulty() then wanted else 1
	end
	self:GetProgress()
	return self
end

return TycoonModel
