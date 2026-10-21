--!strict
-- Pure siege simulation for one outpost. Zombies come from several directions straight at the core,
-- stop at the first living wall on their path and break it; turrets of five roles fire; engineers repair.
-- No Instances: SiegeService replicates what this model decides.
local CompoundLayout = require(script.Parent.CompoundLayout)
local WaveGenerator = require(script.Parent.WaveGenerator)
local TurretMath = require(game:GetService("ReplicatedStorage"):WaitForChild("DeadblockShared"):WaitForChild("TurretMath"))

local SiegeModel = {}
SiegeModel.__index = SiegeModel

export type Result = { ok: boolean, code: string, message: string }
export type Event = { [string]: any }

local SUB_STEP = 0.05
local MAX_FRAME = 0.5
local WALL_GAP = 0.3

local function result(ok: boolean, code: string, message: string): Result
	return { ok = ok, code = code, message = message }
end

local function cross(a: Vector2, b: Vector2): number
	return a.X * b.Y - a.Y * b.X
end

-- Fraction along p->q where it crosses segment a->b, or nil.
local function crossing(p: Vector2, q: Vector2, a: Vector2, b: Vector2): number?
	local r, s = q - p, b - a
	local denominator = cross(r, s)
	if math.abs(denominator) < 1e-9 then return nil end
	local t = cross(a - p, s) / denominator
	local u = cross(a - p, r) / denominator
	if t >= 0 and t <= 1 and u >= 0 and u <= 1 then return t end
	return nil
end

function SiegeModel.new(config: any, worldId: number?, startWave: number?, difficultyId: number?)
	local world = config.Worlds[worldId or 1]
	assert(world, "Unknown world")
	local self = setmetatable({
		config = config, _world = world, _layout = CompoundLayout.Build(config),
		_difficulty = config.Difficulties[difficultyId or 1] or config.Difficulties[1],
		_baseLevel = 0, _wallLevel = 1, _engineers = 0,
		_walls = {} :: { [string]: any }, _wallOrder = {} :: { string },
		_turrets = {} :: { [number]: any }, _zombies = {} :: { [number]: any }, _nextId = 1,
		_state = "Preparing", _wave = startWave or 1, _best = 0, _core = config.Core.MaxHealth,
		_queue = {} :: { string }, _spawned = 0, _toSpawn = 0, _spawnTimer = 0,
		_helperBonus = 0, _loot = 0, _coreLoot = 0, _coreGunCooldown = 0, _coreDamageBy = {} :: { [string]: number }, _coreDamaged = false, _snapshot = nil :: any, _scale = 1, _debugKills = {} :: { [number]: boolean },
	}, SiegeModel)
	self:SetBaseLevel(1)
	return self
end

-- Getters ------------------------------------------------------------------------------------------
function SiegeModel.GetState(self: any): string return self._state end
function SiegeModel.GetWave(self: any): number return self._wave end
function SiegeModel.GetBestWave(self: any): number return self._best end
function SiegeModel.GetWorld(self: any): any return self._world end
function SiegeModel.GetDifficulty(self: any): any return self._difficulty end
function SiegeModel.GetCoreHealth(self: any): number return self._core end
function SiegeModel.GetLayout(self: any): any return self._layout end
function SiegeModel.GetZombies(self: any): { [number]: any } return self._zombies end
function SiegeModel.GetPendingCount(self: any): number return self._toSpawn end
function SiegeModel.GetBaseLevel(self: any): number return self._baseLevel end
function SiegeModel.GetLoot(self: any): number return self._loot end
function SiegeModel.GetCoreLoot(self: any): number return self._coreLoot end
function SiegeModel.GetWall(self: any, id: string): any return self._walls[id] end
function SiegeModel.GetWalls(self: any): { [string]: any } return self._walls end
function SiegeModel.GetTurret(self: any, pad: number): any return self._turrets[pad] end
function SiegeModel.GetWallHealth(self: any, id: string): number?
	local wall = self._walls[id]
	return wall and wall.health or nil
end
function SiegeModel.GetAliveCount(self: any): number
	local count = 0
	for _ in pairs(self._zombies) do count += 1 end
	return count
end

-- Setup --------------------------------------------------------------------------------------------
function SiegeModel.SetBaseLevel(self: any, level: number)
	assert(self.config.Compound.Levels[level], "Invalid base level")
	if level <= self._baseLevel then return end
	-- The perimeter moves outward: the new wall replaces the old one at full health.
	self._baseLevel = level
	table.clear(self._walls)
	table.clear(self._wallOrder)
	local maxHealth = self.config.Walls.Health[self._wallLevel]
	for _, wall in ipairs(self._layout.walls[level]) do
		self._walls[wall.id] = { data = wall, health = maxHealth, max = maxHealth, alive = true }
		table.insert(self._wallOrder, wall.id)
	end
end

function SiegeModel.SetWallLevel(self: any, level: number)
	assert(self.config.Walls.Health[level], "Invalid wall level")
	if level <= self._wallLevel then return end
	self._wallLevel = level
	local maxHealth = self.config.Walls.Health[level]
	for _, wall in pairs(self._walls) do
		if wall.alive then wall.health += maxHealth - wall.max end
		wall.max = maxHealth
	end
end

function SiegeModel.SetEngineers(self: any, count: number)
	assert(count >= 0 and count <= self.config.Engineers.MaxCount and count % 1 == 0, "Invalid engineer count")
	self._engineers = count
end

function SiegeModel.SetTurret(self: any, pad: number, typeName: string?, level: number?, modules: { [string]: number }?)
	assert(self._layout.pads[pad], "Unknown pad")
	if not typeName then self._turrets[pad] = nil return end
	assert(self.config.TurretTypes[typeName], "Unknown turret type")
	local existing = self._turrets[pad]
	if existing and existing.type == typeName then
		existing.level = level or 1
		existing.modules = modules or {}
		return
	end
	self._turrets[pad] = { type = typeName, level = level or 1, cooldown = 0, modules = modules or {} }
end

function SiegeModel.SetProgress(self: any, wave: number, best: number)
	assert(self._state ~= "Active", "Cannot change progress during a wave")
	self._wave = math.max(1, wave)
	self._best = math.max(0, best)
end

-- Visiting players boost the turrets while they stand in the base.
function SiegeModel.SetHelperBonus(self: any, bonus: number)
	self._helperBonus = math.clamp(bonus, 0, 1)
end

-- A player's blaster shot along a 2D ray; hits the first zombie within `radius` of the ray.
-- Kills count for the base owner's loot. Returns the hit zombie id and the impact point.
function SiegeModel.PlayerShot(self: any, from: Vector2, direction: Vector2, range: number, damage: number, radius: number): (number?, Vector2)
	local unit = if direction.Magnitude > 1e-6 then direction.Unit else Vector2.new(0, -1)
	local bestId: number?, bestAlong = nil, range
	for id, zombie in pairs(self._zombies) do
		local offset = zombie.position - from
		local along = offset:Dot(unit)
		if along > 0 and along < bestAlong then
			local side = math.abs(offset.X * unit.Y - offset.Y * unit.X)
			if side <= radius * (self.config.ZombieTypes[zombie.type].Scale or 1) then bestId, bestAlong = id, along end
		end
	end
	local impact = from + unit * bestAlong
	if bestId then
		local zombie = self._zombies[bestId]
		zombie.health -= damage
		-- Kill events are delivered with the next Step so the service handles them in one place.
		self._pendingEvents = self._pendingEvents or {}
		if zombie.health <= 1e-6 then self:_kill(zombie, self._pendingEvents) end
	end
	return bestId, impact
end

-- Waves --------------------------------------------------------------------------------------------
function SiegeModel.GetAttackDirections(self: any): { string }
	local count = math.min(4, 1 + math.floor((self._wave - 1) / 4))
	local random = Random.new(self._world.Id * 7919 + self._wave)
	local pool = table.clone(CompoundLayout.Directions())
	local chosen: { string } = {}
	for _ = 1, count do table.insert(chosen, table.remove(pool, random:NextInteger(1, #pool)) :: string) end
	return chosen
end

function SiegeModel.HealthFor(self: any, typeName: string, wave: number?): number
	local rules = self.config.WaveRules
	return self.config.ZombieTypes[typeName].Health * self._world.HealthMultiplier * self._difficulty.Health * (1 + rules.HealthPerWave * ((wave or self._wave) - 1))
end

local function spawnZombie(self: any, position: Vector2, typeName: string?): number
	local name = typeName or "Walker"
	local definition = self.config.ZombieTypes[name]
	assert(definition, "Unknown zombie type")
	local id = self._nextId
	self._nextId += 1
	local health = self:HealthFor(name) * self._scale
	self._zombies[id] = {
		id = id, type = name, health = health, maxHealth = health, speed = definition.Speed, damage = definition.Damage,
		attackInterval = definition.AttackInterval, armor = definition.Armor, position = position, attackTimer = 0, scale = self._scale,
		target = nil :: string?,
	}
	return id
end

local function snapshot(self: any)
	local walls = {}
	for id, wall in pairs(self._walls) do walls[id] = { health = wall.health, alive = wall.alive } end
	self._snapshot = { walls = walls, core = self._core }
end

function SiegeModel.StartWave(self: any): Result
	if self._state == "Active" then return result(false, "wave_active", "Волна уже идёт.") end
	if self._state == "Defeated" then return result(false, "defeated", "Ядро разрушено. Нажми «Повторить волну».") end
	snapshot(self)
	self._state = "Active"
	self._queue = WaveGenerator.Compose(self.config, self._world.Id, self._wave)
	self._scale = WaveGenerator.Scale(self.config, self._world.Id, self._wave)
	self._spawned = 0
	self._toSpawn = #self._queue
	self._spawnTimer = 0
	self._loot = 0
	self._coreLoot = 0
	self._coreDamaged = false
	self._coreDamageBy = {}
	return result(true, "ok", "Волна началась.")
end

function SiegeModel.Clear(self: any)
	table.clear(self._zombies)
	table.clear(self._debugKills)
	self._toSpawn, self._spawned, self._spawnTimer, self._loot, self._coreLoot = 0, 0, 0, 0, 0
	self._queue = {}
	if self._state == "Active" then self._state = "Preparing" end
end

function SiegeModel.Retry(self: any): Result
	if self._state ~= "Defeated" then return result(false, "not_defeated", "Повтор доступен после поражения.") end
	self:Clear()
	local saved = self._snapshot
	if saved then
		for id, wall in pairs(self._walls) do
			local before = saved.walls[id]
			if before then wall.health, wall.alive = math.min(before.health, wall.max), before.alive end
		end
		self._core = math.max(saved.core, 1)
	else
		self._core = self.config.Core.MaxHealth
	end
	self._state = "Preparing"
	for _, turret in pairs(self._turrets) do turret.cooldown = 0 end
	return result(true, "ok", "Волна начнётся заново.")
end

-- Walls and the core are physical parts of the base: a world change keeps their damage.
function SiegeModel.CopyDefenseFrom(self: any, other: any)
	self:SetWallLevel(other._wallLevel)
	self:SetBaseLevel(other._baseLevel)
	for id, wall in pairs(self._walls) do
		local source = other._walls[id]
		if source then wall.health, wall.alive = math.min(source.health, wall.max), source.alive end
	end
	self._core = math.max(1, math.min(other._core, self.config.Core.MaxHealth))
end

function SiegeModel.GetRepairCost(self: any): number
	local missing = self.config.Core.MaxHealth - self._core
	for _, wall in pairs(self._walls) do missing += wall.max - (if wall.alive then wall.health else 0) end
	return math.ceil(missing * 0.5)
end

function SiegeModel.RepairAll(self: any): number
	local cost = self:GetRepairCost()
	for _, wall in pairs(self._walls) do wall.health, wall.alive = wall.max, true end
	self._core = self.config.Core.MaxHealth
	return cost
end

-- Simulation ----------------------------------------------------------------------------------------
local function repair(self: any, dt: number)
	if self._engineers == 0 then return end
	local budget = self._engineers * self.config.Engineers.RepairRate * dt
	while budget > 1e-9 do
		local worstId: string?, worstFraction = nil, 1
		for _, id in ipairs(self._wallOrder) do
			local wall = self._walls[id]
			if wall.alive and wall.health < wall.max then
				local fraction = wall.health / wall.max
				if fraction < worstFraction then worstId, worstFraction = id, fraction end
			end
		end
		local coreMax = self.config.Core.MaxHealth
		if self._core > 0 and self._core / coreMax < worstFraction then
			local add = math.min(budget, coreMax - self._core)
			self._core += add
			budget -= add
		elseif worstId then
			local wall = self._walls[worstId]
			local add = math.min(budget, wall.max - wall.health)
			wall.health += add
			budget -= add
		else
			break
		end
	end
end

local function spawnPosition(self: any, directions: { string }, index: number): Vector2
	local direction = directions[(index - 1) % #directions + 1]
	for _, point in ipairs(self._layout.spawnPoints) do
		if point.direction == direction then
			local random = Random.new(self._world.Id * 31 + self._wave * 131 + index)
			local position = point.position
			-- The first waves start closer so a new player sees the fight within seconds,
			-- but never inside the current perimeter.
			if self._wave <= (self.config.EarlyWaves or 0) then
				local near = position * self.config.EarlySpawnFactor
				local size = self.config.Compound.Levels[self._baseLevel]
				if math.abs(near.X) > size.HalfX + 40 or math.abs(near.Y) > size.HalfZ + 40 then position = near end
			end
			return position + Vector2.new(random:NextNumber(-10, 10), random:NextNumber(-10, 10))
		end
	end
	error("Unknown direction")
end

local function goalFor(self: any, zombie: any): Vector2
	if zombie.type == "Runner" then
		local best: Vector2?, bestGap = nil, math.huge
		for _, id in ipairs(self._wallOrder) do
			local wall = self._walls[id]
			if not wall.alive then
				local gap = (wall.data.center - zombie.position).Magnitude
				if gap < bestGap then best, bestGap = wall.data.center, gap end
			end
		end
		if best then return best end
	end
	return self._layout.core
end

-- First living wall crossed by the segment p->q, with the fraction along it.
local function firstWall(self: any, p: Vector2, q: Vector2): (any, number?)
	local nearestT: number?, hit = nil, nil
	for _, id in ipairs(self._wallOrder) do
		local wall = self._walls[id]
		if wall.alive then
			local t = crossing(p, q, wall.data.a, wall.data.b)
			if t and (not nearestT or t < nearestT) then nearestT, hit = t, wall end
		end
	end
	return hit, nearestT
end

local function damageWall(self: any, wall: any, amount: number, zombieId: number, events: { Event })
	wall.health = math.max(0, wall.health - amount)
	table.insert(events, { type = "wall_hit", zombieId = zombieId, wallId = wall.data.id, amount = amount })
	if wall.health <= 0 and wall.alive then
		wall.alive = false
		table.insert(events, { type = "wall_destroyed", wallId = wall.data.id })
	end
end

local function kill(self: any, zombie: any, events: { Event }, rewarded: boolean)
	if not self._zombies[zombie.id] then return end
	self._zombies[zombie.id] = nil
	local definition = self.config.ZombieTypes[zombie.type]
	local bounty = if rewarded then definition.Bounty * self._world.RewardMultiplier * self._difficulty.Reward * (zombie.scale or 1) else 0
	self._loot += bounty
	if rewarded then self._coreLoot += (self.config.Cores[zombie.type] or 0) * self._world.Id * self._difficulty.Reward end
	table.insert(events, { type = "kill", zombieId = zombie.id, position = zombie.position, bounty = bounty, zombieType = zombie.type })
	if rewarded and definition.DeathBlast then
		table.insert(events, { type = "explode", position = zombie.position, radius = definition.BlastRadius })
		for _, other in pairs(self._zombies) do
			if (other.position - zombie.position).Magnitude <= definition.BlastRadius then
				other.health -= definition.DeathBlast * self._world.HealthMultiplier
				if other.health <= 0 then kill(self, other, events, true) end
			end
		end
	end
end

function SiegeModel._kill(self: any, zombie: any, events: { Event })
	kill(self, zombie, events, true)
end

local function hit(self: any, zombie: any, amount: number, damageType: string, events: { Event })
	-- Shield bearers lend armour to everyone close to them.
	local armor = zombie.armor
	for _, other in pairs(self._zombies) do
		local aura = self.config.ZombieTypes[other.type].AuraArmor
		if aura and other ~= zombie and (other.position - zombie.position).Magnitude <= self.config.ZombieTypes[other.type].AuraRadius then
			armor += aura
			break
		end
	end
	local dealt = TurretMath.AfterArmor(self.config, amount, damageType, armor)
	zombie.health -= dealt
	if zombie.health <= 1e-6 then kill(self, zombie, events, true) end
end

local function moveZombies(self: any, dt: number, ids: { number }, events: { Event })
	local core = self._layout.core
	local reach = self.config.Core.Reach
	for _, id in ipairs(ids) do
		local zombie = self._zombies[id]
		if not zombie then continue end
		local definition = self.config.ZombieTypes[zombie.type]
		local attackingCore = (core - zombie.position).Magnitude <= reach
		local targetWall: any = nil
		if not attackingCore then
			local goal = goalFor(self, zombie)
			local offset = goal - zombie.position
			local distance = offset.Magnitude
			if distance > 1e-6 then
				local direction = offset / distance
				-- Flyers pass over walls; spitters stop at range and spit at the first wall on their way.
				if definition.Flying then
					zombie.position += direction * math.min(zombie.speed * dt, distance)
					targetWall = nil
				elseif definition.AttackRange then
					local wall, t = firstWall(self, zombie.position, zombie.position + direction * math.min(definition.AttackRange, distance))
					if wall and t then targetWall = wall end
				end
				if not targetWall and not definition.Flying then
					local travel = math.min(zombie.speed * dt, distance)
					local wall, t = firstWall(self, zombie.position, zombie.position + direction * travel)
					if wall and t then
						zombie.position += direction * math.max(0, t * travel - WALL_GAP)
						targetWall = wall
					else
						zombie.position += direction * travel
					end
				end
			end
		end
		if targetWall and definition.WallBlast then
			-- Exploders sacrifice themselves against the wall.
			damageWall(self, targetWall, definition.WallBlast * self._world.Difficulty, id, events)
			table.insert(events, { type = "explode", position = zombie.position, radius = definition.BlastRadius })
			kill(self, zombie, events, false)
		elseif attackingCore or targetWall then
			zombie.attackTimer -= dt
			if zombie.attackTimer <= 1e-9 then
				zombie.attackTimer = zombie.attackInterval
				local damage = zombie.damage * self._world.Difficulty
				if attackingCore then
					if self._core > 0 then
						local dealt = math.min(damage, self._core)
						self._core -= dealt
						self._coreDamaged = true
						self._coreDamageBy[zombie.type] = (self._coreDamageBy[zombie.type] or 0) + dealt
						table.insert(events, { type = "core_hit", zombieId = id, amount = dealt })
					end
				else
					damageWall(self, targetWall, damage, id, events)
				end
			end
		end
	end
end

-- Last line of defence: the core shoots the closest zombie inside its short range.
local function fireCore(self: any, dt: number, events: { Event })
	local coreConfig = self.config.Core
	self._coreGunCooldown = math.max(0, self._coreGunCooldown - dt)
	if self._coreGunCooldown > 1e-9 or self._core <= 0 then return end
	local core = self._layout.core
	local best, bestGap = nil, coreConfig.GunRange
	for _, zombie in pairs(self._zombies) do
		local gap = (zombie.position - core).Magnitude
		if gap <= bestGap then best, bestGap = zombie, gap end
	end
	if not best then return end
	self._coreGunCooldown = coreConfig.GunInterval
	local damage = coreConfig.GunDamage * coreConfig.GunLevelGrowth ^ (self._baseLevel - 1) * self._world.HealthMultiplier ^ 0.5
	table.insert(events, { type = "shot", pad = 0, turretType = "Gun", targets = { best.id }, points = { best.position } })
	hit(self, best, damage, "Pierce", events)
end

local function fireTurrets(self: any, dt: number, events: { Event })
	local config = self.config
	local core = self._layout.core
	for pad = 1, #self._layout.pads do
		local turret = self._turrets[pad]
		if not turret then continue end
		turret.cooldown = math.max(0, turret.cooldown - dt)
		if turret.cooldown > 1e-9 then continue end
		local definition = config.TurretTypes[turret.type]
		local position = self._layout.pads[pad].position
		local modules = turret.modules or {}
		local per = config.Modules
		local range = TurretMath.Range(config, turret.type, turret.level) * (1 + per.Range.Per * (modules.Range or 0))
		local damage = TurretMath.Damage(config, turret.type, turret.level) * (1 + per.Damage.Per * (modules.Damage or 0)) * (1 + self._helperBonus)
		local inRange = {}
		for _, zombie in pairs(self._zombies) do
			local gap = (zombie.position - position).Magnitude
			if gap <= range and gap >= (definition.MinRange or 0) then table.insert(inRange, zombie) end
		end
		if #inRange == 0 then continue end
		table.sort(inRange, function(a, b) return a.id < b.id end)
		local targets, impact = {}, nil
		local mode = definition.Targeting
		if mode == "Area" then
			targets = inRange
		elseif mode == "Strongest" then
			local best = inRange[1]
			for _, zombie in ipairs(inRange) do if zombie.health > best.health then best = zombie end end
			targets = { best }
		elseif mode == "Densest" then
			local best, bestCount = inRange[1], -1
			for _, zombie in ipairs(inRange) do
				local count = 0
				for _, other in pairs(self._zombies) do if (other.position - zombie.position).Magnitude <= definition.Splash then count += 1 end end
				if count > bestCount then best, bestCount = zombie, count end
			end
			impact = best.position
			for _, other in pairs(self._zombies) do if (other.position - impact).Magnitude <= definition.Splash then table.insert(targets, other) end end
		else
			-- "First" and the start of a chain: the zombie closest to the core.
			local first = inRange[1]
			for _, zombie in ipairs(inRange) do
				if (zombie.position - core).Magnitude < (first.position - core).Magnitude then first = zombie end
			end
			targets = { first }
			if mode == "Chain" then
				local hitSet = { [first.id] = true }
				local last = first
				while #targets < definition.Chain do
					local nextZombie, nextGap = nil, definition.ChainRange
					for _, zombie in pairs(self._zombies) do
						if not hitSet[zombie.id] then
							local gap = (zombie.position - last.position).Magnitude
							if gap <= nextGap then nextZombie, nextGap = zombie, gap end
						end
					end
					if not nextZombie then break end
					hitSet[nextZombie.id] = true
					table.insert(targets, nextZombie)
					last = nextZombie
				end
			end
		end
		turret.cooldown = definition.Interval / (1 + per.Rate.Per * (modules.Rate or 0))
		local targetIds, points = {}, {}
		for _, zombie in ipairs(targets) do table.insert(targetIds, zombie.id) table.insert(points, zombie.position) end
		table.insert(events, { type = "shot", pad = pad, turretType = turret.type, targets = targetIds, points = points, impact = impact })
		for index, zombie in ipairs(targets) do
			local amount = damage
			if mode == "Chain" then amount *= definition.ChainFalloff ^ (index - 1) end
			if self._zombies[zombie.id] then hit(self, zombie, amount, definition.DamageType, events) end
		end
	end
end

local function advance(self: any, dt: number, events: { Event })
	local config = self.config
	if self._state == "Active" and self._toSpawn > 0 then
		local directions = self:GetAttackDirections()
		local alive = 0
		for _ in pairs(self._zombies) do alive += 1 end
		while self._toSpawn > 0 and self._spawnTimer <= 1e-9 and alive < config.WaveRules.MaxAlive do
			alive += 1
			self._spawned += 1
			local id = spawnZombie(self, spawnPosition(self, directions, self._spawned), self._queue[self._spawned])
			table.insert(events, { type = "spawn", zombieId = id })
			self._toSpawn -= 1
			self._spawnTimer += config.SpawnInterval
		end
		self._spawnTimer = math.max(self._spawnTimer - dt, -dt)
	end
	repair(self, dt)
	local ids: { number } = {}
	for id in pairs(self._zombies) do table.insert(ids, id) end
	table.sort(ids)
	moveZombies(self, dt, ids, events)
	fireCore(self, dt, events)
	-- Healers mend everyone around them (not themselves).
	for _, healer in pairs(self._zombies) do
		local heal = config.ZombieTypes[healer.type].HealPerSecond
		if heal then
			local radius = config.ZombieTypes[healer.type].HealRadius
			for _, other in pairs(self._zombies) do
				if other ~= healer and other.health < other.maxHealth and (other.position - healer.position).Magnitude <= radius then
					other.health = math.min(other.maxHealth, other.health + heal * self._world.HealthMultiplier * self._difficulty.Health * dt)
				end
			end
		end
	end
	fireTurrets(self, dt, events)
	for id in pairs(self._debugKills) do
		local zombie = self._zombies[id]
		if zombie then kill(self, zombie, events, false) end
	end
	table.clear(self._debugKills)
	if self._state == "Active" then
		if self._core <= 0 then
			self._state = "Defeated"
			table.clear(self._zombies)
			self._toSpawn = 0
			self._loot = 0
			self._coreLoot = 0
			local worst, worstDamage = nil, 0
			for typeName, amount in pairs(self._coreDamageBy) do if amount > worstDamage then worst, worstDamage = typeName, amount end end
			table.insert(events, { type = "state", state = "Defeated", wave = self._wave, worst = worst })
		elseif self._toSpawn == 0 and next(self._zombies) == nil then
			local finished = self._wave
			local rules = config.WaveRules
			local loot = self._loot * (if self._coreDamaged then 1 else rules.CleanBonus)
			local bonus = (rules.WaveBonusBase + rules.WaveBonusPerWave * finished) * self._world.RewardMultiplier * self._difficulty.Reward
			local reward = math.floor(loot + bonus)
			local cores = math.floor(self._coreLoot * (if self._coreDamaged then 1 else rules.CleanBonus))
			self._best = math.max(self._best, finished)
			self._wave = finished + 1
			self._state = "Preparing"
			self._loot = 0
			self._coreLoot = 0
			table.insert(events, { type = "state", state = "Preparing", wave = self._wave, reward = reward, cores = cores, clean = not self._coreDamaged })
		end
	end
end

function SiegeModel.Step(self: any, dt: number): { Event }
	local events: { Event } = self._pendingEvents or {}
	self._pendingEvents = nil
	local remaining = math.clamp(dt, 0, MAX_FRAME)
	while remaining > 1e-9 do
		local slice = math.min(SUB_STEP, remaining)
		advance(self, slice, events)
		remaining -= slice
	end
	return events
end

-- Test fixtures. These never run in production code paths.
function SiegeModel.DebugSpawnAt(self: any, position: Vector2, typeName: string?): number return spawnZombie(self, position, typeName) end
function SiegeModel.DebugSetWave(self: any, wave: number) self._wave = wave end
function SiegeModel.DebugSetBest(self: any, wave: number) self._best = wave end
function SiegeModel.DebugSetCoreHealth(self: any, health: number) self._core = health end
function SiegeModel.DebugClearSpawnQueue(self: any) self._toSpawn = 0 self._queue = {} end
function SiegeModel.DebugSetWallHealth(self: any, id: string, health: number)
	local wall = self._walls[id]
	wall.health = health
	wall.alive = health > 0
end
function SiegeModel.DebugKill(self: any, id: number) self._debugKills[id] = true end

return SiegeModel
