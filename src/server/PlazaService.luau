-- The central plaza: teleports between bases, the server leaderboard and the periodic Titan that every
-- player on the server fights together with blasters. The Titan is pure server data rendered by clients.
local Players = game:GetService("Players")

local PlazaService = {}
PlazaService.__index = PlazaService

function PlazaService.new(config, states, siege, bases, remotes, world)
	return setmetatable({
		config = config, states = states, siege = siege, bases = bases, remotes = remotes, world = world,
		titan = nil, nextTitanAt = os.clock() + config.Titan.FirstAfter, lastSnapshot = 0, lastBoard = 0, connections = {},
	}, PlazaService)
end

local function feedbackAll(self, message: string, ok: boolean?)
	for _, player in ipairs(Players:GetPlayers()) do
		self.remotes.Feedback:FireClient(player, { ok = ok ~= false, code = "plaza", message = message })
	end
end

function PlazaService:Contains(player: Player): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then return false end
	local offset = root.Position - self.config.Social.Plaza
	return Vector2.new(offset.X, offset.Z).Magnitude <= self.config.Social.PlazaRadius + 60
end

local function teleport(player: Player, cframe: CFrame)
	local character = player.Character
	if character and character:FindFirstChild("HumanoidRootPart") then character:PivotTo(cframe + Vector3.new(0, 3, 0)) end
end

function PlazaService:Bind()
	local plaza = self.world:WaitForChild("Plaza")
	for _, pad in ipairs(plaza.Teleports:GetChildren()) do
		table.insert(self.connections, pad.Pad.TeleportPrompt.Triggered:Connect(function(player)
			local base = self.world.Bases:FindFirstChild("Base" .. pad:GetAttribute("BaseId"))
			if base and base:GetAttribute("OwnerUserId") ~= 0 then teleport(player, base.SpawnPoint.CFrame) end
		end))
	end
	for _, base in ipairs(self.world.Bases:GetChildren()) do
		local hub = base.Combat:FindFirstChild("HubPad")
		if hub then
			table.insert(self.connections, hub.Pad.HubPrompt.Triggered:Connect(function(player)
				teleport(player, plaza.Spawn.CFrame)
			end))
		end
	end
end

-- Blaster shot on the plaza: hits the Titan if the ray passes close to it.
function PlazaService:Fire(player: Player, from: Vector3, aim: Vector3): boolean
	local titan = self.titan
	if not titan then return false end
	local center = self.config.Social.Plaza
	local position = center + Vector3.new(titan.x, 0, titan.z)
	local direction = Vector3.new(aim.X - from.X, 0, aim.Z - from.Z)
	if direction.Magnitude < 1e-3 then return false end
	local unit = direction.Unit
	local offset = Vector3.new(position.X - from.X, 0, position.Z - from.Z)
	local along = offset:Dot(unit)
	local side = (offset - unit * along).Magnitude
	local hit = along > 0 and along <= self.config.Blaster.Range and side <= 9
	local impact = if hit then position + Vector3.new(0, 10, 0) else from + unit * math.min(self.config.Blaster.Range, (aim - from).Magnitude)
	local payload = { { "blast", from.X, from.Y, from.Z, impact.X, impact.Y, impact.Z, player.UserId } }
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player and self:Contains(other) then self.remotes.SiegeEvents:FireClient(other, payload) end
	end
	if not hit then return false end
	local state = self.states:Get(player)
	local worldId = if state then state.tycoon.worldId else 1
	local damage = self.config.Blaster.Damage * self.config.Worlds[worldId].HealthMultiplier
	titan.health -= damage
	titan.damageBy[player] = (titan.damageBy[player] or 0) + damage
	if titan.health <= 0 then self:Defeat() end
	return true
end

function PlazaService:Spawn()
	local count = #Players:GetPlayers()
	local health = self.config.Titan.Health + self.config.Titan.HealthPerPlayer * math.max(0, count - 1)
	self.titan = { health = health, max = health, angle = 0, x = self.config.Titan.Orbit, z = 0, endsAt = os.clock() + self.config.Titan.Duration, damageBy = {} }
	feedbackAll(self, "На площади Титан! Телепорт на площадь — у пульта твоей базы. Бей его бластером.")
end

function PlazaService:Defeat()
	local titan = self.titan
	if not titan then return end
	self.titan = nil
	self.nextTitanAt = os.clock() + self.config.Titan.Every
	for player, damage in pairs(titan.damageBy) do
		local state = self.states:Get(player)
		if state and damage >= titan.max * 0.02 then
			local money = math.floor(self.config.Titan.RewardMoney * self.config.Worlds[state.tycoon.worldId].RewardMultiplier)
			state.tycoon:Credit(money)
			state.tycoon:CreditCores(self.config.Titan.RewardCores)
			self.states:Publish(state)
			self.bases:UpdateMoney(state.base, state.tycoon)
			self.remotes.Feedback:FireClient(player, { ok = true, code = "titan", message = string.format("Титан повержен! + $ %d · + %d ядер", money, self.config.Titan.RewardCores) })
		end
	end
	for _, player in ipairs(Players:GetPlayers()) do self.remotes.SiegeEvents:FireClient(player, { { "titan_down" } }) end
end

function PlazaService:UpdateBoard()
	local board = self.world.Plaza:FindFirstChild("Board")
	if not board then return end
	local rows = {}
	for player, state in pairs(self.states:GetAll()) do
		local progress = state.tycoon:GetProgress()
		table.insert(rows, { name = player.DisplayName, world = self.config.Worlds[state.tycoon.worldId].Name .. (if state.tycoon.difficulty > 1 then " · " .. self.config.Difficulties[state.tycoon.difficulty].Name else ""), best = progress.best, level = state.tycoon:GetBaseLevel(), unlocked = state.tycoon.unlockedWorld })
	end
	table.sort(rows, function(a, b) if a.unlocked ~= b.unlocked then return a.unlocked > b.unlocked end return a.best > b.best end)
	local lines = {}
	for index, row in ipairs(rows) do
		table.insert(lines, string.format("%d. %s — %s, волна %d, база ур. %d", index, row.name, row.world, row.best, row.level))
	end
	board.Screen.SurfaceGui.Rows.Text = if #lines > 0 then table.concat(lines, "\n") else "Пока пусто"
	for _, pad in ipairs(self.world.Plaza.Teleports:GetChildren()) do
		local base = self.world.Bases:FindFirstChild("Base" .. pad:GetAttribute("BaseId"))
		local ownerId = base and base:GetAttribute("OwnerUserId") or 0
		local owner = if ownerId ~= 0 then Players:GetPlayerByUserId(ownerId) else nil
		pad.Pad.Info.Label.Text = if owner then "База " .. owner.DisplayName else "Свободная база"
		pad.Pad.TeleportPrompt.Enabled = owner ~= nil
	end
end

function PlazaService:Step(now: number, dt: number)
	if now - self.lastBoard >= self.config.Social.LeaderboardInterval then
		self.lastBoard = now
		pcall(self.UpdateBoard, self)
	end
	local titan = self.titan
	if not titan then
		if now >= self.nextTitanAt and #Players:GetPlayers() > 0 then self:Spawn() end
	else
		titan.angle += self.config.Titan.Speed / self.config.Titan.Orbit * dt
		titan.x = math.cos(titan.angle) * self.config.Titan.Orbit
		titan.z = math.sin(titan.angle) * self.config.Titan.Orbit
		if now >= titan.endsAt then
			self.titan = nil
			self.nextTitanAt = now + self.config.Titan.Every
			feedbackAll(self, "Титан ушёл с площади. Он вернётся позже.", false)
			for _, player in ipairs(Players:GetPlayers()) do self.remotes.SiegeEvents:FireClient(player, { { "titan_down" } }) end
		end
	end
	if now - self.lastSnapshot >= self.config.SnapshotInterval then
		self.lastSnapshot = now
		if self.titan then
			local payload = { x = self.titan.x, z = self.titan.z, hp = self.titan.health / self.titan.max, angle = self.titan.angle }
			for _, player in ipairs(Players:GetPlayers()) do
				if self:Contains(player) then self.remotes.PlazaSnapshot:FireClient(player, payload) end
			end
		end
	end
end

function PlazaService:Destroy()
	for _, connection in ipairs(self.connections) do connection:Disconnect() end
	table.clear(self.connections)
end

return PlazaService
