-- Binds SiegeModel to the world and to the owner's client. The server keeps zombies as pure data and
-- streams compact snapshots and effect batches to the base owner, who renders them (DeadblockSiege).
-- Walls, the core, spawn markers and engineers stay server objects.
local AnalyticsService = game:GetService("AnalyticsService")
local Players = game:GetService("Players")
local SiegeModel = require(script.Parent.SiegeModel)
local WaveGenerator = require(script.Parent.WaveGenerator)

local SiegeService = {}
SiegeService.__index = SiegeService

local WALL_COLOR = Color3.fromRGB(122, 130, 124)
local WALL_DAMAGED = Color3.fromRGB(170, 84, 70)
local ENGINEER_SPEED = 14

function SiegeService.new(config, states, bases, remotes)
	local zombieCodes, turretCodes = {}, {}
	for index, name in ipairs(config.ZombieOrder) do zombieCodes[name] = index end
	for index, name in ipairs(config.TurretOrder) do turretCodes[name] = index end
	return setmetatable({
		config = config, states = states, bases = bases, remotes = remotes,
		sessions = {}, lastRequest = {}, connections = {}, zombieCodes = zombieCodes, turretCodes = turretCodes,
	}, SiegeService)
end

local function feedback(self, player, ok: boolean, code: string, message: string)
	self.remotes.Feedback:FireClient(player, { ok = ok, code = code, message = message })
end

local function round(value: number): number
	return math.floor(value * 10 + 0.5) / 10
end

local function makeEngineer(): Model
	local model = Instance.new("Model")
	model.Name = "Engineer"
	local function part(name: string, size: Vector3, offset: Vector3, color: Color3, root: BasePart?)
		local p = Instance.new("Part")
		p.Name = name p.Size = size p.Color = color p.Material = Enum.Material.SmoothPlastic
		p.CanCollide = false p.CanTouch = false p.CanQuery = false p.Massless = true
		p.Anchored = root == nil p.Parent = model
		if root then
			p.CFrame = root.CFrame * CFrame.new(offset)
			local weld = Instance.new("WeldConstraint") weld.Part0 = root weld.Part1 = p weld.Parent = p
		end
		return p
	end
	local torso = part("Torso", Vector3.new(2, 2.4, 1.1), Vector3.zero, Color3.fromRGB(237, 159, 65))
	part("Head", Vector3.new(1.4, 1.4, 1.4), Vector3.new(0, 1.9, 0), Color3.fromRGB(226, 189, 150), torso)
	part("Helmet", Vector3.new(1.7, 0.7, 1.7), Vector3.new(0, 2.8, 0), Color3.fromRGB(237, 220, 80), torso)
	part("LegL", Vector3.new(0.8, 2, 0.8), Vector3.new(-0.5, -2.2, 0), Color3.fromRGB(48, 62, 84), torso)
	part("LegR", Vector3.new(0.8, 2, 0.8), Vector3.new(0.5, -2.2, 0), Color3.fromRGB(48, 62, 84), torso)
	part("Tool", Vector3.new(0.4, 0.4, 1.8), Vector3.new(1.4, 0.4, -1.1), Color3.fromRGB(150, 160, 165), torso)
	model.PrimaryPart = torso
	return model
end

local function inArena(self, player: Player, base: Model): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then return false end
	local offset = root.Position - (base:GetAttribute("Origin") :: Vector3)
	local half = self.config.Social.ArenaHalf
	return math.abs(offset.X) <= half.X and math.abs(offset.Z) <= half.Y
end

local function previewText(self, worldId: number, wave: number): string
	local cacheKey = worldId .. ":" .. wave
	self.previewCache = self.previewCache or {}
	if self.previewCache[cacheKey] then return self.previewCache[cacheKey] end
	local parts = {}
	for _, entry in ipairs(WaveGenerator.Summary(self.config, worldId, wave)) do
		local name = self.config.ZombieTypes[entry.type].Name
		table.insert(parts, if entry.type == "Colossus" then "КОЛОСС ×" .. entry.count else name .. " ×" .. entry.count)
	end
	local text = table.concat(parts, " · ")
	self.previewCache[cacheKey] = text
	return text
end

local function directionsText(self, directions: { string }): string
	if #directions > 2 then return "Атака с " .. #directions .. " сторон" end
	local names = {}
	for _, direction in ipairs(directions) do table.insert(names, self.config.Compound.DirectionNames[direction]) end
	return "Атака с " .. table.concat(names, " и ")
end

function SiegeService:Add(player: Player)
	local state = self.states:Get(player)
	if not state or self.sessions[player] then return end
	local progress = state.tycoon:GetProgress()
	local model = SiegeModel.new(self.config, state.tycoon.worldId, nil, state.tycoon.difficulty)
	model:SetProgress(progress.wave, progress.best)
	local session = {
		player = player, base = state.base, model = model, lastStep = os.clock(), lastSnapshot = 0,
		published = {}, wallKeys = {}, engineers = {}, effects = {}, repairText = "", lastDirections = "",
		autoWave = state.tycoon.tutorial >= self.config.AutoWaveUnlockStep, nextWaveAt = nil,
	}
	session.autoOffered = session.autoWave
	self.sessions[player] = session
	self:Publish(session, true)
	self:RenderCore(session)
	self:RenderMarkers(session)
end

function SiegeService:Publish(session, force: boolean?)
	local model, player = session.model, session.player
	local world = model:GetWorld()
	local values = {
		DeadblockWaveState = model:GetState(), DeadblockWave = model:GetWave(), DeadblockWorld = world.Id,
		DeadblockWorldName = world.Name, DeadblockCoreHealth = math.ceil(model:GetCoreHealth()), DeadblockCoreMax = self.config.Core.MaxHealth,
		DeadblockZombiesLeft = model:GetAliveCount() + model:GetPendingCount(), DeadblockBest = model:GetBestWave(),
		DeadblockAttackText = directionsText(self, model:GetAttackDirections()), DeadblockLoot = math.floor(model:GetLoot()), DeadblockCoreLoot = math.floor(model:GetCoreLoot()),
		DeadblockWavePreview = previewText(self, world.Id, model:GetWave()),
		DeadblockBossWave = WaveGenerator.BossCount(self.config, model:GetWave()) > 0,
		DeadblockAutoWave = session.autoWave,
		DeadblockDifficulty = model:GetDifficulty().Id, DeadblockDifficultyName = model:GetDifficulty().Name,
		DeadblockMaxDifficulty = if self.states:Get(player) then self.states:Get(player).tycoon:MaxDifficulty() else 1,
		DeadblockNextWaveIn = if session.nextWaveAt and model:GetState() == "Preparing" then math.max(0, math.ceil(session.nextWaveAt - os.clock())) else -1,
	}
	for key, value in pairs(values) do
		if force or session.published[key] ~= value then
			session.published[key] = value
			player:SetAttribute(key, value)
		end
	end
end

function SiegeService:RenderCore(session)
	local core = session.base.Combat.Core
	local health = session.model:GetCoreHealth()
	local fraction = health / self.config.Core.MaxHealth
	core.Crystal.Color = Color3.fromRGB(235, 96, 80):Lerp(Color3.fromRGB(111, 226, 173), fraction)
	core:SetAttribute("Health", health)
	core.CoreBody.Info.Label.Text = string.format("ЯДРО  %d / %d", math.ceil(health), self.config.Core.MaxHealth)
	local state = session.model:GetState()
	local prompt = core.CoreBody.WavePrompt
	prompt.Enabled = state ~= "Active"
	prompt.ActionText = if state == "Defeated" then "Повторить волну" else string.format("Начать волну %d", session.model:GetWave())
end

-- Spawn ruins glow orange for the coming directions and red while the wave is active.
function SiegeService:RenderMarkers(session)
	local active = {}
	for _, direction in ipairs(session.model:GetAttackDirections()) do active[direction] = true end
	local state = session.model:GetState()
	for _, marker in ipairs(session.base.SpawnMarkers:GetChildren()) do
		local on = active[marker.Name] == true and state ~= "Defeated"
		local alarm = marker.Alarm
		alarm.Color = if not on then Color3.fromRGB(70, 40, 38) elseif state == "Active" then Color3.fromRGB(255, 70, 50) else Color3.fromRGB(255, 170, 60)
		alarm.Material = if on then Enum.Material.Neon else Enum.Material.SmoothPlastic
		alarm.PointLight.Enabled = on
	end
end

function SiegeService:Control(player: Player, kind: any, value: any)
	local session = self.sessions[player]
	if not session then return end
	local now = os.clock()
	if now - (self.lastRequest[player] or -math.huge) < 0.3 then return end
	self.lastRequest[player] = now
	local result
	if kind == "AutoWave" then
		local state = self.states:Get(player)
		if not state or state.tycoon.tutorial < self.config.AutoWaveUnlockStep then
			result = { ok = false, code = "locked", message = "Автоволны откроются после первых заданий." }
		else
			session.autoWave = value == true
			session.autoOffered = true
			session.nextWaveAt = if session.autoWave and session.model:GetState() == "Preparing" then os.clock() + self.config.AutoWaveDelay else nil
			result = { ok = true, code = "ok", message = if session.autoWave then "Автоволны включены." else "Автоволны выключены." }
		end
	elseif kind == "StartWave" then
		result = session.model:StartWave()
		if result.ok then session.nextWaveAt = nil end
	elseif kind == "Retry" then
		result = session.model:Retry()
	elseif kind == "Difficulty" then
		local state = self.states:Get(player)
		if session.model:GetState() ~= "Preparing" then
			result = { ok = false, code = "busy", message = "Сложность меняется только между волнами." }
		elseif not state or not state.tycoon:SetDifficulty(value) then
			result = { ok = false, code = "locked", message = "Эта сложность откроется после волны 10 на предыдущей." }
		else
			-- Same base and defences, a fresh wave counter for this difficulty.
			local progress = state.tycoon:GetProgress()
			local previous = session.model
			session.model = SiegeModel.new(self.config, state.tycoon.worldId, nil, state.tycoon.difficulty)
			session.model:SetProgress(progress.wave, progress.best)
			session.model:CopyDefenseFrom(previous)
			session.nextWaveAt = nil
			local difficulty = session.model:GetDifficulty()
			result = { ok = true, code = "ok", message = string.format("Сложность: %s. Зомби крепче ×%.1f, награды ×%.1f.", difficulty.Name, difficulty.Health, difficulty.Reward) }
		end
	elseif kind == "Repair" then
		local state = self.states:Get(player)
		local cost = session.model:GetRepairCost()
		if session.model:GetState() == "Active" then result = { ok = false, code = "wave_active", message = "Ремонт недоступен во время волны." }
		elseif session.model:GetState() == "Defeated" then result = { ok = false, code = "defeated", message = "Сначала повтори волну — стены вернутся к её началу." }
		elseif cost == 0 then result = { ok = false, code = "nothing", message = "Ремонт не требуется." }
		elseif not state or state.tycoon.money < cost then result = { ok = false, code = "insufficient_funds", message = "Нужно $ " .. cost .. " на ремонт." }
		else
			state.tycoon:Spend(cost)
			session.model:RepairAll()
			self.states:Publish(state)
			self.bases:UpdateMoney(state.base, state.tycoon)
			result = { ok = true, code = "ok", message = "База отремонтирована за $ " .. cost }
		end
	else
		return
	end
	self:Publish(session)
	self:RenderCore(session)
	self:RenderMarkers(session)
	feedback(self, player, result.ok, result.code, result.message)
end

-- Moves the player's siege to another unlocked world, keeping the base and each world's own progress.
function SiegeService:Travel(player: Player, worldId: number): boolean
	local session, state = self.sessions[player], self.states:Get(player)
	if not session or not state then return false end
	local now = os.clock()
	if now - (session.lastTravel or -math.huge) < 3 then return false end
	if session.model:GetState() ~= "Preparing" then feedback(self, player, false, "busy", "Порталом можно уйти только между волнами.") return false end
	if not state.tycoon:SetWorld(worldId) then return false end
	session.lastTravel = now
	local progress = state.tycoon:GetProgress()
	local previous = session.model
	session.model = SiegeModel.new(self.config, worldId, nil, state.tycoon.difficulty)
	session.model:SetProgress(progress.wave, progress.best)
	session.model:CopyDefenseFrom(previous)
	session.lastStep = os.clock()
	table.clear(session.wallKeys)
	self.remotes.SiegeEvents:FireClient(player, { { "reset" } })
	self:Publish(session, true)
	self:RenderCore(session)
	self:RenderMarkers(session)
	feedback(self, player, true, "travel", "Мир «" .. session.model:GetWorld().Name .. "». Зомби здесь сильнее, а доход выше.")
	return true
end

function SiegeService:SyncWalls(session)
	local level = session.model:GetBaseLevel()
	local set = session.base.Walls:FindFirstChild("L" .. level)
	if not set then return end
	for id, wall in pairs(session.model:GetWalls()) do
		local key = if wall.alive then math.floor(wall.health / wall.max * 20) else -1
		if session.wallKeys[id] ~= key then
			session.wallKeys[id] = key
			local wallModel = set:FindFirstChild(id)
			if wallModel then
				for _, p in ipairs(wallModel:GetChildren()) do
					if p:IsA("BasePart") then
						p.Transparency = if wall.alive then (p:GetAttribute("OriginalTransparency") or 0) else 1
						p.CanCollide = wall.alive and p:GetAttribute("Solid") == true
					end
				end
				if wall.alive then wallModel.Body.Color = WALL_DAMAGED:Lerp(WALL_COLOR, wall.health / wall.max) end
			end
		end
	end
end

-- Cosmetic repair crew: walks to the most damaged walls. Healing itself is decided by SiegeModel.
function SiegeService:StepEngineers(session, dt: number, count: number)
	local folder = session.base.Combat.Engineers
	local spawn = session.base.Combat.Workshop.EngineerSpawn.Position
	while #session.engineers < count do
		local visual = makeEngineer()
		visual:PivotTo(CFrame.new(spawn + Vector3.new(#session.engineers * 2, 0.6, 0)))
		visual.Parent = folder
		table.insert(session.engineers, { model = visual })
	end
	while #session.engineers > count do
		session.engineers[#session.engineers].model:Destroy()
		table.remove(session.engineers)
	end
	if count == 0 then return end
	local damaged = {}
	for id, wall in pairs(session.model:GetWalls()) do
		if wall.alive and wall.health < wall.max then table.insert(damaged, { id = id, fraction = wall.health / wall.max, wall = wall }) end
	end
	table.sort(damaged, function(a, b) if a.fraction == b.fraction then return a.id < b.id end return a.fraction < b.fraction end)
	local origin = session.base:GetAttribute("Origin")
	local core = self.config.Compound.Core
	for index, engineer in ipairs(session.engineers) do
		local target = damaged[(index - 1) % math.max(#damaged, 1) + 1]
		local goal
		if target then
			local center = target.wall.data.center
			local inward = core - center
			inward = if inward.Magnitude > 0 then inward.Unit else Vector2.zero
			local point = center + inward * 3.5
			goal = origin + Vector3.new(point.X, 3.6, point.Y)
		else
			goal = spawn + Vector3.new((index - 3) * 3, 0.6, 3)
		end
		local position = engineer.model:GetPivot().Position
		local offset = goal - position
		local step = ENGINEER_SPEED * dt
		local nextPosition = if offset.Magnitude <= step then goal else position + offset.Unit * step
		local flat = Vector3.new(goal.X, nextPosition.Y, goal.Z)
		engineer.model:PivotTo(if (flat - nextPosition).Magnitude > 0.5 then CFrame.lookAt(nextPosition, flat) else CFrame.new(nextPosition))
	end
end

function SiegeService:QueueEvents(session, events)
	local effects = session.effects
	for _, event in ipairs(events) do
		if event.type == "shot" then
			local points = {}
			for _, point in ipairs(event.points) do table.insert(points, round(point.X)) table.insert(points, round(point.Y)) end
			table.insert(effects, { "shot", event.pad, self.turretCodes[event.turretType], points, event.impact and round(event.impact.X), event.impact and round(event.impact.Y) })
		elseif event.type == "kill" then
			table.insert(effects, { "kill", round(event.position.X), round(event.position.Y), math.floor(event.bounty), self.zombieCodes[event.zombieType] })
		elseif event.type == "explode" then
			table.insert(effects, { "explode", round(event.position.X), round(event.position.Y), event.radius })
		elseif event.type == "wall_destroyed" then
			table.insert(effects, { "breach", event.wallId })
		elseif event.type == "core_hit" then
			table.insert(effects, { "core" })
		end
	end
end

function SiegeService:StepSession(session, now: number)
	local state = self.states:Get(session.player)
	if not state then return end
	local model = session.model
	local tycoon = state.tycoon
	model:SetBaseLevel(tycoon:GetBaseLevel())
	model:SetWallLevel(tycoon.wallLevel)
	model:SetEngineers(tycoon.engineers)
	for pad = 1, #model:GetLayout().pads do
		local owned = tycoon.turrets[pad]
		if owned then model:SetTurret(pad, owned.type, owned.level, owned.modules)
		elseif model:GetTurret(pad) then model:SetTurret(pad, nil) end
	end
	-- Visitors standing in this arena help: they see the fight and boost the turrets during a wave.
	local helpers = {}
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= session.player and inArena(self, other, session.base) then table.insert(helpers, other) end
	end
	session.helpers = helpers
	local social = self.config.Social
	model:SetHelperBonus(if model:GetState() == "Active" then math.min(#helpers, social.MaxHelpers) * social.HelperDamageBonus else 0)
	local dt = now - session.lastStep
	session.lastStep = now
	local events = model:Step(dt)
	self:QueueEvents(session, events)
	local kills = 0
	for _, event in ipairs(events) do if event.type == "kill" and event.bounty > 0 then kills += 1 end end
	if kills > 0 and self.onProgress then self.onProgress(session.player, "kills", kills) end
	for _, event in ipairs(events) do
		if event.type == "core_hit" then
			self:RenderCore(session)
		elseif event.type == "state" then
			self:RenderCore(session)
			self:RenderMarkers(session)
			if event.reward then
				pcall(function() AnalyticsService:LogCustomEvent(session.player, "WaveCleared", model:GetWave() - 1) end)
				if session.autoWave then session.nextWaveAt = now + self.config.AutoWaveDelay end
				tycoon:Credit(event.reward)
				if event.cores and event.cores > 0 then tycoon:CreditCores(event.cores) end
				tycoon:RecordWave(model:GetWave(), model:GetBestWave())
				if self.onProgress then
					self.onProgress(session.player, "waves", 1)
					if event.clean then self.onProgress(session.player, "clean", 1) end
				end
				self.states:Publish(state)
				self.bases:UpdateMoney(state.base, tycoon)
				local bonus = if event.clean then " · без урона по ядру ×1.25" else ""
				local coresText = if event.cores and event.cores > 0 then string.format(" · + %d ядер", event.cores) else ""
				feedback(self, session.player, true, "wave_reward", string.format("Волна %d отбита! + $ %d%s%s", model:GetWave() - 1, event.reward, coresText, bonus))
				-- Helpers earn a share on top (paid by the server, not taken from the owner).
				for _, helper in ipairs(helpers) do
					local helperState = self.states:Get(helper)
					if helperState then
						local share = math.floor(event.reward * social.HelperRewardShare)
						helperState.tycoon:Credit(share)
						self.states:Publish(helperState)
						self.bases:UpdateMoney(helperState.base, helperState.tycoon)
						feedback(self, helper, true, "helper_reward", "Ты помог соседу " .. session.player.DisplayName .. " отбить волну: + $ " .. share)
					end
				end
			elseif event.state == "Defeated" then
				session.nextWaveAt = nil
				pcall(function() AnalyticsService:LogCustomEvent(session.player, "WaveLost", model:GetWave()) end)
				local tip = event.worst and self.config.DefeatTips[event.worst]
				feedback(self, session.player, false, "defeated", "Ядро пало, волна начнётся заново. " .. (tip or "Укрепи оборону и повтори."))
			end
		end
	end
	if not session.autoWave and tycoon.tutorial >= self.config.AutoWaveUnlockStep and not session.autoOffered then
		-- Unlock automatic waves once the player has learned the basics.
		session.autoOffered = true
		session.autoWave = true
		if model:GetState() == "Preparing" then session.nextWaveAt = now + self.config.AutoWaveDelay end
	end
	if session.autoWave and session.nextWaveAt and now >= session.nextWaveAt and model:GetState() == "Preparing" then
		session.nextWaveAt = nil
		if model:StartWave().ok then self:RenderCore(session) self:RenderMarkers(session) end
	end
	self:SyncWalls(session)
	self:StepEngineers(session, math.min(dt, 0.25), tycoon.engineers)
	local text = directionsText(self, model:GetAttackDirections())
	if text ~= session.lastDirections then session.lastDirections = text self:RenderMarkers(session) end
	local repair = session.base.Combat.Console.Pad.RepairPrompt
	local cost = model:GetRepairCost()
	local label = if cost > 0 then "Ремонт базы · $ " .. cost else "Ремонт не нужен"
	if label ~= session.repairText then session.repairText = label repair.ActionText = label end
	if now - session.lastSnapshot >= self.config.SnapshotInterval then
		session.lastSnapshot = now
		local data = {}
		for id, zombie in pairs(model:GetZombies()) do
			table.insert(data, id)
			table.insert(data, self.zombieCodes[zombie.type])
			table.insert(data, round(zombie.position.X))
			table.insert(data, round(zombie.position.Y))
			table.insert(data, math.floor(math.clamp(zombie.health / zombie.maxHealth, 0, 1) * 100))
		end
		local payload = { b = session.base:GetAttribute("BaseId"), z = data }
		self.remotes.SiegeSnapshot:FireClient(session.player, payload)
		for _, helper in ipairs(helpers) do self.remotes.SiegeSnapshot:FireClient(helper, payload) end
	end
	if #session.effects > 0 then
		local payload = { b = session.base:GetAttribute("BaseId"), e = session.effects }
		self.remotes.SiegeEvents:FireClient(session.player, payload)
		for _, helper in ipairs(helpers) do self.remotes.SiegeEvents:FireClient(helper, payload) end
		session.effects = {}
	end
	self:Publish(session)
end

-- The siege whose arena contains this player (own base or a neighbour's), if any.
function SiegeService:SessionAt(player: Player)
	for _, session in pairs(self.sessions) do
		if inArena(self, player, session.base) then return session end
	end
	return nil
end

-- Blaster shot inside an arena. The caller rate-limits; geometry and damage are decided here.
function SiegeService:Fire(player: Player, from: Vector3, aim: Vector3): boolean
	local session = self:SessionAt(player)
	if not session then return false end
	local origin = session.base:GetAttribute("Origin") :: Vector3
	local from2 = Vector2.new(from.X - origin.X, from.Z - origin.Z)
	local aim2 = Vector2.new(aim.X - origin.X, aim.Z - origin.Z)
	local blaster = self.config.Blaster
	local damage = blaster.Damage * session.model:GetWorld().HealthMultiplier
	local hit, impact = session.model:PlayerShot(from2, aim2 - from2, blaster.Range, damage, blaster.HitRadius)
	local impactWorld = origin + Vector3.new(impact.X, if hit then 3.5 else math.max(aim.Y, 1), impact.Y)
	table.insert(session.effects, { "blast", from.X, from.Y, from.Z, impactWorld.X, impactWorld.Y, impactWorld.Z, player.UserId })
	return hit ~= nil
end

function SiegeService:Step(now: number)
	-- One failing session must not stop the others' tick.
	for player, session in pairs(self.sessions) do
		local ok, err = pcall(self.StepSession, self, session, now)
		if not ok then warn("[DEADBLOCK] siege step failed for", player.Name, err) end
	end
end

function SiegeService:Remove(player: Player)
	local session = self.sessions[player]
	self.sessions[player] = nil
	self.lastRequest[player] = nil
	if not session then return end
	for _, engineer in ipairs(session.engineers) do engineer.model:Destroy() end
	for _, key in ipairs({"DeadblockWaveState","DeadblockWave","DeadblockWorld","DeadblockWorldName","DeadblockCoreHealth","DeadblockCoreMax","DeadblockZombiesLeft","DeadblockBest","DeadblockAttackText","DeadblockLoot","DeadblockWavePreview","DeadblockBossWave"}) do
		player:SetAttribute(key, nil)
	end
	-- Hand walls, core and markers back in their idle state for the next owner.
	local idle = { model = SiegeModel.new(self.config, 1), base = session.base }
	self:RenderCore(idle)
	self:RenderMarkers(idle)
	for _, set in ipairs(session.base.Walls:GetChildren()) do
		for _, wallModel in ipairs(set:GetChildren()) do
			local body = wallModel:FindFirstChild("Body")
			if body then body.Color = WALL_COLOR end
		end
	end
end

function SiegeService:Bind()
	table.insert(self.connections, self.remotes.CombatAction.OnServerEvent:Connect(function(player, action)
		if type(action) ~= "table" then return end
		self:Control(player, action.kind, action.value)
	end))
	for _, base in ipairs(self.bases.world.Bases:GetChildren()) do
		local function owned(player: Player)
			local session = self.sessions[player]
			if not session or session.base ~= base or base:GetAttribute("OwnerUserId") ~= player.UserId then return nil end
			return session
		end
		table.insert(self.connections, base.Combat.Core.CoreBody.WavePrompt.Triggered:Connect(function(player)
			local session = owned(player)
			if session then self:Control(player, if session.model:GetState() == "Defeated" then "Retry" else "StartWave") end
		end))
		table.insert(self.connections, base.Combat.Console.Pad.RepairPrompt.Triggered:Connect(function(player)
			if owned(player) then self:Control(player, "Repair") end
		end))
	end
end

function SiegeService:Destroy()
	for _, connection in ipairs(self.connections) do connection:Disconnect() end
	table.clear(self.connections)
	for player in pairs(self.sessions) do self:Remove(player) end
end

return SiegeService
