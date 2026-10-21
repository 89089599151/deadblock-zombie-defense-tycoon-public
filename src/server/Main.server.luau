local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("DeadblockShared"):WaitForChild("Config"))
local root = script.Parent
local PlayerStateService = require(root.PlayerStateService)
local BaseService = require(root.BaseService)
local ProductionService = require(root.ProductionService)
local PurchaseService = require(root.PurchaseService)
local SiegeService = require(root.SiegeService)
local SaveService = require(root.SaveService)
local TycoonModel = require(root.TycoonModel)
local QuestService = require(root.QuestService)
local PlazaService = require(root.PlazaService)
local GlobalBoardService = require(root.GlobalBoardService)

local world = workspace:WaitForChild("DeadblockWorld")
local remotes = ReplicatedStorage:WaitForChild("DeadblockRemotes")
local states = PlayerStateService.new(Config)
local bases = BaseService.new(world, Config)
local production = ProductionService.new(Config, states, bases)
local purchases = PurchaseService.new(Config, states, bases, production, remotes)
local siege = SiegeService.new(Config, states, bases, remotes)
local quests = QuestService.new(Config, states, siege, bases, remotes)
local plaza = PlazaService.new(Config, states, siege, bases, remotes, world)
local globalBoard -- created once the save settings are known (below)
siege.onProgress = function(player, kind, amount) quests:Track(player, kind, amount) end
purchases.onPurchase = function(player, kind)
	if kind == "UpgradeTurret" or kind == "UpgradeDropper" or kind == "UpgradeModule" then quests:Track(player, "upgrades", 1)
	elseif kind == "BuildTurret" then quests:Track(player, "builds", 1) end
end
local characterConnections = {}
local joining = {}

-- Saves: off in Studio unless explicitly enabled on a separate test experience, so testing never
-- touches real player data. Any store error leaves the session playable but unsaved.
local saves = nil
local savesEnabled = not RunService:IsStudio() or game.ServerStorage:GetAttribute("DeadblockStudioSaves") == true
if savesEnabled then
	local ok, store = pcall(function() return DataStoreService:GetDataStore("DeadblockProfiles_v1") end)
	if ok then saves = SaveService.new(store, if game.JobId ~= "" then game.JobId else HttpService:GenerateGUID(false)) end
end
globalBoard = GlobalBoardService.new(Config, states, world, savesEnabled)

local pendingFinalSaves = {} -- userId -> true while that player's final save is being written

-- Periodic saves. Each write carries a growing sequence number so an older write can never land last.
local function saveState(state)
	if not saves or not state.canSave or state.finalSaved then return end
	state.saveSeq += 1
	local ok, reason = saves:Save(state.player.UserId, state.tycoon:ToProfile(), false, state.saveSeq)
	if not ok then
		warn("[DEADBLOCK] save failed for", state.player.UserId, reason)
		if reason == "locked" then
			-- Another server took this profile over: stop writing and send the player to it.
			state.canSave = false
			state.player:Kick("Твой прогресс открыт на другом сервере. Перезайди в игру.")
		end
	end
end

-- Takes the final snapshot synchronously; the write itself may happen after the session is gone.
local function takeFinalSave(state)
	if not saves or not state.canSave or state.finalSaved then return nil end
	state.finalSaved = true
	state.saveSeq += 1
	return { profile = state.tycoon:ToProfile(), sequence = state.saveSeq, userId = state.player.UserId }
end

local function writeFinalSave(snapshot)
	if not snapshot then return end
	pendingFinalSaves[snapshot.userId] = true
	local ok, reason = saves:Save(snapshot.userId, snapshot.profile, true, snapshot.sequence)
	if not ok then warn("[DEADBLOCK] final save failed for", snapshot.userId, reason) end
	pendingFinalSaves[snapshot.userId] = nil
end

-- Every commander carries a blaster: secondary combat for helping turrets, neighbours and the Titan.
local function giveBlaster(player)
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack or backpack:FindFirstChild("Бластер") or (player.Character and player.Character:FindFirstChild("Бластер")) then return end
	local tool = Instance.new("Tool")
	tool.Name = "Бластер"
	tool.CanBeDropped = false
	tool.ToolTip = "Стреляй по зомби и Титану"
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.6, 0.8, 2.4)
	handle.Color = Color3.fromRGB(60, 70, 80)
	handle.Material = Enum.Material.Metal
	handle.CanCollide = false
	handle.Massless = true
	handle.Parent = tool
	local glow = Instance.new("Part")
	glow.Name = "Glow"
	glow.Size = Vector3.new(0.3, 0.3, 1.6)
	glow.Color = Color3.fromRGB(110, 200, 255)
	glow.Material = Enum.Material.Neon
	glow.CanCollide = false
	glow.Massless = true
	glow.CFrame = handle.CFrame * CFrame.new(0, 0.45, -0.2)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = handle weld.Part1 = glow weld.Parent = glow
	glow.Parent = tool
	tool.Parent = backpack
end

-- Friends on the same server boost each other's factories.
local friendCache = {}
local function areFriends(a, b)
	local key = math.min(a.UserId, b.UserId) .. ":" .. math.max(a.UserId, b.UserId)
	if friendCache[key] == nil then
		local ok, result = pcall(function() return a:IsFriendsWith(b.UserId) end)
		friendCache[key] = ok and result == true
	end
	return friendCache[key]
end
local function refreshFriendBonus()
	for player, state in pairs(states:GetAll()) do
		local hasFriend = false
		for other in pairs(states:GetAll()) do
			if other ~= player and areFriends(player, other) then hasFriend = true break end
		end
		state.tycoon.socialBonus = if hasFriend then Config.Social.FriendIncomeBonus else 0
		player:SetAttribute("DeadblockFriendBonus", hasFriend)
	end
end

local function positionCharacter(player, character)
	local base = bases:GetOwned(player)
	if not base then return end
	local humanoidRoot = character:WaitForChild("HumanoidRootPart", 10)
	if humanoidRoot and player.Character == character and bases:GetOwned(player) == base then
		character:PivotTo(base.SpawnPoint.CFrame)
	end
end

local function travel(player, worldId)
	local state = states:Get(player)
	if not state then return end
	production:SyncTo(state, os.clock())
	if siege:Travel(player, worldId) then
		production:Reconcile(state, os.clock())
		states:Publish(state)
		bases:Refresh(state.base, state.tycoon, player.UserId)
		task.spawn(saveState, state)
	end
end
purchases.travel = travel

local function loadProfile(player)
	-- A quick rejoin on this server waits for its own final save first.
	local waited = 0
	while pendingFinalSaves[player.UserId] and waited < 30 do task.wait(0.25) waited += 0.25 end
	for attempt = 1, 3 do
		local ok, profile, reason, sequence = saves:Load(player.UserId)
		if ok then return true, profile, sequence, nil end
		if reason ~= "locked" or attempt == 3 then return false, nil, 0, reason end
		task.wait(5) -- the previous server is probably still writing its final save
	end
	return false, nil, 0, "locked"
end

local function joined(player)
	if states:Get(player) or joining[player] then return end
	joining[player] = true
	player:SetAttribute("DeadblockStatus", "loading")
	local tycoon, canSave, saveStatus, sequence = nil, false, "disabled", 0
	local holdsLock = false
	if saves then
		local ok, profile, loadedSequence, reason = loadProfile(player)
		if ok then
			holdsLock = true
			sequence = loadedSequence
			local built, model = pcall(TycoonModel.FromProfile, Config, player.UserId, profile)
			if built then tycoon, canSave, saveStatus = model, true, "ok"
			else saveStatus = "corrupt" warn("[DEADBLOCK] profile rejected:", model) end
		elseif reason == "locked" then
			joining[player] = nil
			player:Kick("Прогресс ещё сохраняется на другом сервере. Зайди через минуту.")
			return
		else
			saveStatus = reason or "unavailable"
		end
	end
	joining[player] = nil
	local base = if player.Parent == Players then bases:Assign(player) else nil
	if not base or not canSave then
		-- Never keep a lock we will not write with (left during load, server full, unreadable profile).
		if holdsLock then task.spawn(function() saves:Release(player.UserId) end) end
	end
	if player.Parent ~= Players then return end
	if not base then
		player:SetAttribute("DeadblockStatus", "full")
		return
	end
	if not tycoon then
		-- Brand-new commander: a small purse and the first turret on the house.
		tycoon = TycoonModel.new(Config, player.UserId)
		tycoon:Credit(Config.StartMoney)
		tycoon.freeTurret = true
	end
	-- The factory kept working (at a reduced rate) while the player was away.
	local offlineEarned = 0
	if tycoon.lastSeen then
		local away = math.clamp(os.time() - tycoon.lastSeen, 0, Config.Offline.MaxSeconds)
		if away >= Config.Offline.MinSeconds then
			offlineEarned = math.floor(tycoon:GetIncomePerSecond() * away * Config.Offline.Rate)
			if offlineEarned > 0 then tycoon:Credit(offlineEarned) end
		end
	end
	local state = states:Create(player, base, tycoon)
	state.canSave = canSave
	state.saveSeq = sequence
	player:SetAttribute("DeadblockSaveStatus", saveStatus)
	bases:Refresh(base, state.tycoon, player.UserId)
	production:Reconcile(state, os.clock())
	siege:Add(player)
	quests:RefreshDaily(player, state)
	if offlineEarned > 0 then
		task.delay(4, function()
			if player.Parent then remotes.Feedback:FireClient(player, { ok = true, code = "offline", message = "Пока тебя не было, завод заработал $ " .. offlineEarned }) end
		end)
	end
	player.CameraMaxZoomDistance = 120
	characterConnections[player] = player.CharacterAdded:Connect(function(character)
		positionCharacter(player, character)
		task.defer(giveBlaster, player)
	end)
	if player.Character then task.spawn(positionCharacter, player, player.Character) task.defer(giveBlaster, player) end
	task.spawn(refreshFriendBonus)
end

local function leaving(player)
	joining[player] = nil
	local connection = characterConnections[player]
	if connection then connection:Disconnect() characterConnections[player] = nil end
	local state = states:Get(player)
	local snapshot = nil
	if state then
		production:SyncTo(state, os.clock())
		snapshot = takeFinalSave(state)
	end
	-- Free the plot immediately; the write below must not hold the base hostage.
	siege:Remove(player)
	quests:Clear(player)
	states:Remove(player)
	bases:Release(player)
	purchases:Forget(player)
	task.spawn(refreshFriendBonus)
	for _, waiting in ipairs(Players:GetPlayers()) do
		if waiting ~= player and waiting:GetAttribute("DeadblockStatus") == "full" then task.spawn(joined, waiting) end
	end
	writeFinalSave(snapshot)
end

-- Studio-only QA hooks (never created on live servers). Used by automated playtests.
if RunService:IsStudio() then
	local qa = Instance.new("BindableFunction")
	qa.Name = "DeadblockQA"
	qa.OnInvoke = function(command: string, player: Player, arg: any)
		local state = states:Get(player)
		if not state then return { error = "no state" } end
		if command == "grant" then
			state.tycoon:Credit(arg)
			states:Publish(state)
			bases:UpdateMoney(state.base, state.tycoon)
			return { money = state.tycoon.money }
		elseif command == "buy" then
			local source = if arg.source == "gate" then state.base.Gates["Gate" .. arg.targetId].Door else nil
			local target = source or purchases:TargetFor(state.base, arg.kind, arg.targetId)
			if target and player.Character then player.Character:PivotTo(target.CFrame + Vector3.new(0, 5, 0)) end
			task.wait(0.3)
			local action = table.clone(arg)
			action.source = nil
			action.requestId = HttpService:GenerateGUID(false)
			return purchases:Handle(player, action, source)
		elseif command == "titan" then
			plaza:Spawn()
			if player.Character then player.Character:PivotTo(world.Plaza.Spawn.CFrame + Vector3.new(0, 3, 0)) end
			return { health = plaza.titan and plaza.titan.health }
		elseif command == "titanInfo" then
			return { active = plaza.titan ~= nil, health = plaza.titan and plaza.titan.health, max = plaza.titan and plaza.titan.max, x = plaza.titan and plaza.titan.x, z = plaza.titan and plaza.titan.z }
		elseif command == "travel" then
			travel(player, arg)
			return { world = state.tycoon.worldId, income = state.tycoon:GetIncomePerSecond() }
		elseif command == "wave" then
			siege:Control(player, arg or "StartWave")
			return "sent"
		elseif command == "progress" then
			local session = siege.sessions[player]
			session.model:SetProgress(arg, arg - 1)
			state.tycoon:RecordWave(arg, arg - 1)
			siege:Publish(session, true)
			return "ok"
		elseif command == "info" then
			local session = siege.sessions[player]
			local model = session and session.model
			local turrets = {}
			for pad, turret in pairs(state.tycoon.turrets) do turrets[tostring(pad)] = turret.type .. ":" .. turret.level end
			return { money = state.tycoon.money, turrets = turrets, baseLevel = state.tycoon:GetBaseLevel(), wallLevel = state.tycoon.wallLevel,
				engineers = state.tycoon.engineers, world = state.tycoon.worldId, state = model and model:GetState(), wave = model and model:GetWave(),
				core = model and model:GetCoreHealth(), alive = model and model:GetAliveCount(), pending = model and model:GetPendingCount(),
				best = model and model:GetBestWave(), loot = model and model:GetLoot() }
		end
		return { error = "unknown command" }
	end
	qa.Parent = game.ServerStorage
end

Players.PlayerAdded:Connect(joined)
Players.PlayerRemoving:Connect(leaving)
purchases:Bind()
plaza:Bind()

-- Blaster: the client sends only where it aims; the server checks rate, origin and range.
local lastShot = {}
remotes.Blaster.OnServerEvent:Connect(function(player, aim)
	if typeof(aim) ~= "Vector3" or aim.X ~= aim.X or aim.Magnitude > 1e6 then return end
	local now = os.clock()
	if now - (lastShot[player] or 0) < Config.Blaster.Interval then return end
	lastShot[player] = now
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 or not character:FindFirstChild("Бластер") then return end
	local from = root.Position + Vector3.new(0, 1.5, 0)
	if plaza:Contains(player) then plaza:Fire(player, from, aim) else siege:Fire(player, from, aim) end
end)
Players.PlayerRemoving:Connect(function(player) lastShot[player] = nil end)
siege:Bind()
for _, player in ipairs(Players:GetPlayers()) do task.spawn(joined, player) end

local accumulated = 0
local lastSecond = 0
RunService.Heartbeat:Connect(function(dt)
	accumulated += dt
	if accumulated < Config.ServerStep then return end
	accumulated = 0
	local now = os.clock()
	production:Step(now)
	quests:Step(now)
	if now - lastSecond >= 1 then
		-- Once a second: apply or expire the factory overdrive and refresh slow counters.
		lastSecond = now
		for _, state in pairs(states:GetAll()) do
			production:Reconcile(state, now)
			states:Publish(state)
		end
		globalBoard:Step(now)
	end
	siege:Step(now)
	plaza:Step(now, Config.ServerStep)
end)

-- Autosave every minute.
task.spawn(function()
	while true do
		task.wait(60)
		for _, state in pairs(states:GetAll()) do task.spawn(saveState, state) end
	end
end)

game:BindToClose(function()
	purchases:Destroy()
	local snapshots = {}
	for _, state in pairs(states:GetAll()) do
		production:SyncTo(state, os.clock())
		table.insert(snapshots, takeFinalSave(state))
	end
	local pending = #snapshots
	for _, snapshot in ipairs(snapshots) do
		task.spawn(function()
			writeFinalSave(snapshot)
			pending -= 1
		end)
	end
	local deadline = os.clock() + 25
	while pending > 0 and os.clock() < deadline do task.wait(0.2) end
	siege:Destroy()
end)
print("[DEADBLOCK] Outpost ready: growing perimeter, five turret roles, worlds, saves")
