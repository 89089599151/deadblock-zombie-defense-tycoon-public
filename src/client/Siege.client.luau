--!strict
-- Renders the owner's siege: zombies from server snapshots (smoothed), turret aiming, shots, kills,
-- explosions and world mood. Purely visual: nothing here can change the game state.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local Debris = game:GetService("Debris")
local SoundService = game:GetService("SoundService")

local player = Players.LocalPlayer
local shared = ReplicatedStorage:WaitForChild("DeadblockShared")
local Config = require(shared:WaitForChild("Config"))
local remotes = ReplicatedStorage:WaitForChild("DeadblockRemotes")

local fx = Instance.new("Folder")
fx.Name = "DeadblockClientFX"
fx.Parent = workspace

local zombies: { [number]: any } = {}
local titanModel: Model? = nil
local pools: { [number]: { Model } } = {}

-- The base whose fight is being shown: the one the server streams to us (own or a neighbour's).
local viewedBase: number? = nil
local lastSnapshotAt = 0

local function base(): Model?
	local id = viewedBase or player:GetAttribute("DeadblockBaseId")
	local world = workspace:FindFirstChild("DeadblockWorld")
	return if id and world then world.Bases:FindFirstChild("Base" .. id) :: Model? else nil
end

local function origin(): Vector3
	local b = base()
	return if b then b:GetAttribute("Origin") :: Vector3 else Vector3.zero
end

local function toWorld(x: number, z: number, y: number): Vector3
	return origin() + Vector3.new(x, y, z)
end

-- Zombie models ---------------------------------------------------------------------------------

local function makeZombie(typeName: string): Model
	local definition = Config.ZombieTypes[typeName]
	local color: Color3 = definition.Color
	local model = Instance.new("Model")
	model.Name = typeName
	local function part(name: string, size: Vector3, offset: Vector3, partColor: Color3, root: BasePart?, material: Enum.Material?): Part
		local p = Instance.new("Part")
		p.Name = name p.Size = size p.Color = partColor p.Material = material or Enum.Material.SmoothPlastic
		p.CanCollide = false p.CanTouch = false p.CanQuery = false p.CastShadow = typeName == "Colossus"
		p.TopSurface = Enum.SurfaceType.Smooth p.BottomSurface = Enum.SurfaceType.Smooth
		p.Anchored = true
		p.CFrame = (if root then root.CFrame else CFrame.new()) * CFrame.new(offset)
		p.Parent = model
		return p
	end
	local clothes = if typeName == "Brute" or typeName == "Colossus" then Color3.fromRGB(70, 60, 58) else Color3.fromRGB(68, 88, 120)
	local torso = part("Torso", Vector3.new(2, 2.6, 1.1), Vector3.zero, clothes)
	part("Head", Vector3.new(1.5, 1.5, 1.5), Vector3.new(0, 2.1, 0), color, torso)
	part("EyeL", Vector3.new(0.3, 0.2, 0.1), Vector3.new(-0.35, 2.2, -0.76), Color3.fromRGB(255, 80, 60), torso, Enum.Material.Neon)
	part("EyeR", Vector3.new(0.3, 0.2, 0.1), Vector3.new(0.35, 2.2, -0.76), Color3.fromRGB(255, 80, 60), torso, Enum.Material.Neon)
	part("LegL", Vector3.new(0.85, 2, 0.85), Vector3.new(-0.5, -2.3, 0), Color3.fromRGB(52, 58, 70), torso)
	part("LegR", Vector3.new(0.85, 2, 0.85), Vector3.new(0.5, -2.3, 0), Color3.fromRGB(52, 58, 70), torso)
	part("ArmL", Vector3.new(0.7, 0.7, 2.4), Vector3.new(-1.35, 0.7, -1.4), color, torso)
	part("ArmR", Vector3.new(0.7, 0.7, 2.4), Vector3.new(1.35, 0.7, -1.4), color:Lerp(Color3.new(0, 0, 0), 0.3), torso)
	if typeName == "Brute" or typeName == "Colossus" then
		part("Plate", Vector3.new(2.3, 1.6, 0.4), Vector3.new(0, 0.3, -0.75), Color3.fromRGB(120, 130, 140), torso, Enum.Material.Metal)
		part("Shoulders", Vector3.new(3.4, 0.6, 1.4), Vector3.new(0, 1.3, 0), Color3.fromRGB(110, 118, 126), torso, Enum.Material.Metal)
	elseif typeName == "Exploder" then
		local sac = part("Sac", Vector3.new(1.8, 1.8, 1.8), Vector3.new(0, 0.2, -0.9), Color3.fromRGB(255, 120, 60), torso, Enum.Material.Neon)
		sac.Shape = Enum.PartType.Ball
	elseif typeName == "Healer" then
		part("CrossV", Vector3.new(0.4, 1.4, 0.2), Vector3.new(0, 0.3, -0.62), Color3.fromRGB(120, 255, 190), torso, Enum.Material.Neon)
		part("CrossH", Vector3.new(1.4, 0.4, 0.2), Vector3.new(0, 0.3, -0.62), Color3.fromRGB(120, 255, 190), torso, Enum.Material.Neon)
	elseif typeName == "Shielder" then
		part("Shield", Vector3.new(2.6, 3.2, 0.4), Vector3.new(0, 0, -1.4), Color3.fromRGB(110, 140, 200), torso, Enum.Material.Metal)
		part("Rim", Vector3.new(2.8, 0.3, 0.45), Vector3.new(0, 1.6, -1.4), Color3.fromRGB(120, 200, 255), torso, Enum.Material.Neon)
	elseif typeName == "Flyer" then
		part("WingL", Vector3.new(3, 0.2, 1.6), Vector3.new(-2.2, 0.8, 0.4), Color3.fromRGB(70, 40, 90), torso)
		part("WingR", Vector3.new(3, 0.2, 1.6), Vector3.new(2.2, 0.8, 0.4), Color3.fromRGB(70, 40, 90), torso)
	elseif typeName == "Spitter" then
		part("Jaw", Vector3.new(1, 0.5, 0.6), Vector3.new(0, 1.6, -0.9), Color3.fromRGB(190, 120, 240), torso, Enum.Material.Neon)
	end
	model.PrimaryPart = torso
	model:ScaleTo(definition.Scale)
	local gui = Instance.new("BillboardGui")
	gui.Name = "Health" gui.Size = UDim2.fromOffset(if typeName == "Colossus" then 140 else 56, if typeName == "Colossus" then 12 else 7)
	gui.StudsOffset = Vector3.new(0, 3 * definition.Scale + 1.2, 0) gui.MaxDistance = if typeName == "Colossus" then 500 else 180
	gui.AlwaysOnTop = typeName == "Colossus" gui.Adornee = torso gui.Parent = torso
	local back = Instance.new("Frame") back.Name = "Back" back.Size = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = Color3.fromRGB(22, 28, 36) back.BorderSizePixel = 0 back.Parent = gui
	local fill = Instance.new("Frame") fill.Name = "Fill" fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = if typeName == "Colossus" then Color3.fromRGB(255, 70, 70) else Color3.fromRGB(235, 96, 80) fill.BorderSizePixel = 0 fill.Parent = back
	return model
end

local function acquire(code: number): Model
	local pool = pools[code]
	if pool and #pool > 0 then
		local model = table.remove(pool) :: Model
		model.Parent = fx
		return model
	end
	local model = makeZombie(Config.ZombieOrder[code])
	model.Parent = fx
	return model
end

local function release(code: number, model: Model)
	model.Parent = nil
	pools[code] = pools[code] or {}
	if #pools[code] < 40 then table.insert(pools[code], model) else model:Destroy() end
end

local function clearAll()
	for id, zombie in pairs(zombies) do release(zombie.code, zombie.model) zombies[id] = nil end
end

remotes:WaitForChild("SiegeSnapshot").OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" or typeof(payload.z) ~= "table" then return end
	if payload.b ~= viewedBase then
		clearAll()
		viewedBase = payload.b
	end
	lastSnapshotAt = os.clock()
	local data = payload.z
	local seen = {}
	local core = Config.Compound.Core
	for index = 1, #data, 5 do
		local id, code, x, z, hp = data[index], data[index + 1], data[index + 2], data[index + 3], data[index + 4]
		seen[id] = true
		local zombie = zombies[id]
		if not zombie then
			local model = acquire(code)
			local definition = Config.ZombieTypes[Config.ZombieOrder[code]]
			zombie = { model = model, code = code, x = x, z = z, scale = definition.Scale, phase = math.random() * 6, hp = -1, flying = definition.Flying == true }
			zombies[id] = zombie
		end
		zombie.tx, zombie.tz = x, z
		if zombie.hp ~= hp then
			zombie.hp = hp
			local torso = zombie.model.PrimaryPart
			local gui = torso and torso:FindFirstChild("Health")
			if gui then (gui :: any).Back.Fill.Size = UDim2.fromScale(hp / 100, 1) end
		end
		local toCore = Vector2.new(core.X - x, core.Y - z)
		zombie.facing = if toCore.Magnitude > 0.1 then toCore.Unit else Vector2.new(0, 1)
	end
	for id, zombie in pairs(zombies) do
		if not seen[id] then release(zombie.code, zombie.model) zombies[id] = nil end
	end
end)

RunService.RenderStepped:Connect(function(dt)
	-- Left the arena (no more snapshots): drop its zombies.
	if next(zombies) and os.clock() - lastSnapshotAt > 0.8 then clearAll() end
	local o = origin()
	local alpha = 1 - math.exp(-dt * 10)
	local t = os.clock()
	for _, zombie in pairs(zombies) do
		zombie.x += ((zombie.tx or zombie.x) - zombie.x) * alpha
		zombie.z += ((zombie.tz or zombie.z) - zombie.z) * alpha
		local moving = math.abs((zombie.tx or zombie.x) - zombie.x) + math.abs((zombie.tz or zombie.z) - zombie.z) > 0.05
		local bob = if moving then math.abs(math.sin(t * 7 + zombie.phase)) * 0.25 else 0
		local sway = math.sin(t * 3.5 + zombie.phase) * 0.12
		local height = 3.3 * zombie.scale + bob + (if zombie.flying then 9 + math.sin(t * 2 + zombie.phase) * 1.2 else 0)
		local position = o + Vector3.new(zombie.x, height, zombie.z)
		local f = zombie.facing or Vector2.new(0, 1)
		zombie.model:PivotTo(CFrame.lookAt(position, position + Vector3.new(f.X, 0, f.Y)) * CFrame.Angles(0, 0, sway))
	end
end)

-- Sounds ------------------------------------------------------------------------------------------

local lastPlayed: { [string]: number } = {}
local function play(name: string, volume: number, minGap: number?)
	local id = Config.Sounds[name]
	if not id then return end
	local now = os.clock()
	if minGap and now - (lastPlayed[name] or 0) < minGap then return end
	lastPlayed[name] = now
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Volume = volume
	sound.Parent = SoundService
	sound:Play()
	sound.Ended:Once(function() sound:Destroy() end)
	Debris:AddItem(sound, 12)
end

-- Effects -----------------------------------------------------------------------------------------

local function flashPart(size: Vector3, cframe: CFrame, color: Color3, lifetime: number, transparency: number?, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Anchored = true p.CanCollide = false p.CanQuery = false p.CanTouch = false p.CastShadow = false
	p.Material = Enum.Material.Neon p.Color = color p.Size = size p.CFrame = cframe
	p.Transparency = transparency or 0
	if shape then p.Shape = shape end
	p.Parent = fx
	TweenService:Create(p, TweenInfo.new(lifetime), { Transparency = 1 }):Play()
	Debris:AddItem(p, lifetime + 0.05)
	return p
end

local function beam(from: Vector3, to: Vector3, width: number, color: Color3, lifetime: number)
	local length = (to - from).Magnitude
	if length < 0.1 then return end
	flashPart(Vector3.new(width, width, length), CFrame.lookAt(from, to) * CFrame.new(0, 0, -length / 2), color, lifetime)
end

local function turretParts(pad: number): (Model?, BasePart?)
	local b = base()
	if pad == 0 then
		-- The core's own gun fires from the crystal.
		local crystal = b and (b :: any).Combat.Core:FindFirstChild("Crystal")
		return nil, crystal
	end
	local padModel = b and b:FindFirstChild("Pads") and (b :: any).Pads:FindFirstChild("Pad" .. pad)
	local turret = padModel and padModel:FindFirstChild("Turret")
	local head = turret and turret:FindFirstChild("Head") :: Model?
	return head, head and head:FindFirstChild("Muzzle") :: BasePart?
end

local function aim(head: Model?, target: Vector3)
	if not head or not head.PrimaryPart then return end
	local pivot = head:GetPivot().Position
	local flat = Vector3.new(target.X, pivot.Y, target.Z)
	if (flat - pivot).Magnitude > 0.2 then head:PivotTo(CFrame.lookAt(pivot, flat)) end
end

local function explosion(position: Vector3, radius: number, color: Color3)
	local ball = flashPart(Vector3.one * 2, CFrame.new(position), color, 0.35, 0.1, Enum.PartType.Ball)
	TweenService:Create(ball, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.one * radius * 2 }):Play()
end

local function popup(position: Vector3, text: string, color: Color3)
	local anchor = Instance.new("Part")
	anchor.Anchored = true anchor.CanCollide = false anchor.CanQuery = false anchor.Transparency = 1 anchor.Size = Vector3.one * 0.2
	anchor.CFrame = CFrame.new(position) anchor.Parent = fx
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(90, 30) gui.AlwaysOnTop = true gui.MaxDistance = 260 gui.Parent = anchor
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1) label.BackgroundTransparency = 1 label.Font = Enum.Font.GothamBold label.TextScaled = true
	label.Text = text label.TextColor3 = color label.TextStrokeTransparency = 0.4 label.Parent = gui
	TweenService:Create(anchor, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = CFrame.new(position + Vector3.new(0, 5, 0)) }):Play()
	TweenService:Create(label, TweenInfo.new(0.9), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	Debris:AddItem(anchor, 1)
end

local SHOT_COLORS = {
	Gun = Color3.fromRGB(255, 214, 110), Sniper = Color3.fromRGB(230, 245, 255), Flamer = Color3.fromRGB(255, 130, 50),
	Tesla = Color3.fromRGB(130, 190, 255), Mortar = Color3.fromRGB(60, 60, 60),
}

local function shot(pad: number, code: number, points: { number }, impactX: number?, impactZ: number?)
	local typeName = Config.TurretOrder[code]
	local head, muzzle = turretParts(pad)
	if not muzzle or #points < 2 then return end
	local from = muzzle.Position
	local first = toWorld(points[1], points[2], 3)
	aim(head, first)
	from = muzzle.Position
	local color = SHOT_COLORS[typeName]
	if typeName == "Gun" then
		play("Gun", 0.22, 0.09)
		beam(from, first, 0.18, color, 0.06)
		flashPart(Vector3.one * 0.9, CFrame.new(from), color, 0.06, 0, Enum.PartType.Ball)
	elseif typeName == "Sniper" then
		play("Sniper", 0.45, 0.2)
		beam(from, first, 0.35, color, 0.25)
		flashPart(Vector3.one * 1.6, CFrame.new(from), color, 0.12, 0, Enum.PartType.Ball)
	elseif typeName == "Flamer" then
		local reach = math.min((first - from).Magnitude + 4, 30)
		local direction = (first - from).Unit
		local cone = flashPart(Vector3.new(3, 3, reach), CFrame.lookAt(from, from + direction) * CFrame.new(0, 0, -reach / 2), color, 0.3, 0.35)
		cone.Shape = Enum.PartType.Ball
		for index = 1, #points, 2 do
			flashPart(Vector3.one * 1.6, CFrame.new(toWorld(points[index], points[index + 1], 3)), Color3.fromRGB(255, 180, 60), 0.3, 0.2, Enum.PartType.Ball)
		end
	elseif typeName == "Tesla" then
		play("Tesla", 0.35, 0.15)
		local previous = from
		for index = 1, #points, 2 do
			local target = toWorld(points[index], points[index + 1], 3)
			local mid = (previous + target) / 2 + Vector3.new(math.random(-15, 15) / 10, math.random(-10, 20) / 10, math.random(-15, 15) / 10)
			beam(previous, mid, 0.3, color, 0.15)
			beam(mid, target, 0.3, color, 0.15)
			previous = target
		end
	elseif typeName == "Mortar" and impactX and impactZ then
		local impact = toWorld(impactX, impactZ, 1)
		local shell = flashPart(Vector3.one * 1.2, CFrame.new(from), color, 0.7, 0, Enum.PartType.Ball)
		shell.Material = Enum.Material.Metal
		local start = os.clock()
		local connection
		connection = RunService.RenderStepped:Connect(function()
			local alpha = math.min((os.clock() - start) / 0.55, 1)
			local arc = math.sin(alpha * math.pi) * 25
			shell.CFrame = CFrame.new(from:Lerp(impact, alpha) + Vector3.new(0, arc, 0))
			if alpha >= 1 then
				connection:Disconnect()
				shell:Destroy()
				explosion(impact + Vector3.new(0, 1, 0), Config.TurretTypes.Mortar.Splash, Color3.fromRGB(255, 150, 60))
				play("Explosion", 0.4, 0.12)
			end
		end)
	end
end

-- Screen flash for core hits and breaches.
local overlay = Instance.new("ScreenGui")
overlay.Name = "DeadblockFX"
overlay.IgnoreGuiInset = true
overlay.ResetOnSpawn = false
overlay.DisplayOrder = 5
overlay.Parent = player:WaitForChild("PlayerGui")
local vignette = Instance.new("Frame")
vignette.Size = UDim2.fromScale(1, 1)
vignette.BackgroundColor3 = Color3.fromRGB(200, 30, 30)
vignette.BackgroundTransparency = 1
vignette.BorderSizePixel = 0
vignette.Parent = overlay
local banner = Instance.new("TextLabel")
banner.AnchorPoint = Vector2.new(0.5, 0)
banner.Position = UDim2.new(0.5, 0, 0, 150)
banner.Size = UDim2.fromOffset(420, 40)
banner.BackgroundTransparency = 1
banner.Font = Enum.Font.GothamBold
banner.TextSize = 26
banner.TextColor3 = Color3.fromRGB(255, 120, 90)
banner.TextStrokeTransparency = 0.3
banner.TextTransparency = 1
banner.Text = ""
banner.Parent = overlay
local bannerRevision = 0
local function showBanner(text: string, color: Color3)
	bannerRevision += 1
	local revision = bannerRevision
	banner.Text = text
	banner.TextColor3 = color
	banner.TextTransparency = 0
	banner.TextStrokeTransparency = 0.3
	task.delay(2.2, function()
		if revision == bannerRevision then
			TweenService:Create(banner, TweenInfo.new(0.6), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		end
	end)
end
local lastCoreFlash = 0
local lastBreach = 0

remotes:WaitForChild("SiegeEvents").OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" then return end
	local batch = payload
	if typeof(payload.e) == "table" then
		-- Arena events only make sense for the arena we are watching.
		if payload.b ~= viewedBase and payload.b ~= player:GetAttribute("DeadblockBaseId") then return end
		batch = payload.e
	end
	for _, event in ipairs(batch) do
		local kind = event[1]
		if kind == "shot" then
			shot(event[2], event[3], event[4], event[5], event[6])
		elseif kind == "kill" then
			local position = toWorld(event[2], event[3], 4)
			local typeName = Config.ZombieOrder[event[5]]
			local color = if typeName then Config.ZombieTypes[typeName].Color else Color3.new(1, 1, 1)
			for _ = 1, 4 do
				local gib = flashPart(Vector3.one * 0.6, CFrame.new(position), color, 0.5, 0)
				gib.Material = Enum.Material.SmoothPlastic
				TweenService:Create(gib, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = CFrame.new(position + Vector3.new(math.random(-40, 40) / 10, math.random(5, 30) / 10 - 3, math.random(-40, 40) / 10)) }):Play()
			end
			if event[4] > 0 then popup(position + Vector3.new(0, 2, 0), "+$" .. event[4], Color3.fromRGB(144, 233, 194)) end
			if math.random() < 0.3 then play("Groan", 0.3, 1.2) end
			if typeName == "Colossus" then showBanner("КОЛОСС ПОВЕРЖЕН!", Color3.fromRGB(144, 233, 194)) end
		elseif kind == "explode" then
			explosion(toWorld(event[2], event[3], 2), event[4], Color3.fromRGB(255, 130, 60))
			play("Explosion", 0.5, 0.12)
		elseif kind == "breach" then
			if os.clock() - lastBreach > 2 then lastBreach = os.clock() showBanner("СТЕНА ПРОБИТА!", Color3.fromRGB(255, 120, 90)) end
		elseif kind == "core" then
			if os.clock() - lastCoreFlash > 0.4 then
				lastCoreFlash = os.clock()
				vignette.BackgroundTransparency = 0.82
				TweenService:Create(vignette, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
			end
		elseif kind == "quest" then
			play("Reward", 0.6)
			showBanner("ЗАДАНИЕ ВЫПОЛНЕНО!", Color3.fromRGB(255, 210, 90))
		elseif kind == "blast" then
			if event[8] ~= player.UserId then
				local from, to = Vector3.new(event[2], event[3], event[4]), Vector3.new(event[5], event[6], event[7])
				beam(from, to, 0.22, Color3.fromRGB(120, 210, 255), 0.08)
			end
		elseif kind == "titan_down" then
			if titanModel then titanModel:Destroy() titanModel = nil end
		elseif kind == "reset" then
			clearAll()
		end
	end
end)

-- World mood: each world has its own light, fog and time of day (local to this client).
local MOODS = {
	{ clock = 14.6, brightness = 2.5, ambient = Color3.fromRGB(127, 143, 138) },
	{ clock = 17.4, brightness = 2.2, ambient = Color3.fromRGB(150, 128, 104) },
	{ clock = 19.4, brightness = 1.6, ambient = Color3.fromRGB(96, 102, 122) },
}
local function applyMood()
	local worldId = player:GetAttribute("DeadblockWorld")
	local world = Config.Worlds[if typeof(worldId) == "number" then worldId else 1]
	local mood = MOODS[world.Id] or MOODS[1]
	TweenService:Create(Lighting, TweenInfo.new(1.5), { ClockTime = mood.clock, Brightness = mood.brightness, Ambient = mood.ambient, FogColor = world.Fog }):Play()
end
player:GetAttributeChangedSignal("DeadblockWorld"):Connect(applyMood)
applyMood()

-- Boss warning and wave start announcements.
player:GetAttributeChangedSignal("DeadblockWaveState"):Connect(function()
	local state = player:GetAttribute("DeadblockWaveState")
	if state == "Active" then
		local text = player:GetAttribute("DeadblockAttackText")
		play("Siren", 0.35)
		if player:GetAttribute("DeadblockBossWave") == true then
			showBanner("ИДЁТ КОЛОСС!", Color3.fromRGB(255, 90, 90))
			play("Boss", 0.7)
		elseif typeof(text) == "string" then showBanner(string.upper(text), Color3.fromRGB(255, 190, 110)) end
	elseif state == "Defeated" then
		clearAll()
		showBanner("ЯДРО ПАЛО", Color3.fromRGB(255, 90, 90))
	end
end)

-- Victory fanfare on a cleared wave.
remotes:WaitForChild("Feedback").OnClientEvent:Connect(function(payload)
	if typeof(payload) == "table" and payload.code == "wave_reward" then
		play("Victory", 0.5)
		showBanner("ВОЛНА ОТБИТА!", Color3.fromRGB(144, 233, 194))
	end
end)

-- The plaza Titan: a giant Colossus driven by the server's plaza snapshots.
local titanTarget: Vector3? = nil
local titanAngle = 0
remotes:WaitForChild("PlazaSnapshot").OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" or payload.none then
		if titanModel then titanModel:Destroy() titanModel = nil end
		return
	end
	if not titanModel then
		titanModel = makeZombie("Colossus")
		titanModel:ScaleTo(Config.ZombieTypes.Colossus.Scale * 1.8)
		titanModel.Parent = fx
		play("Boss", 0.8)
		showBanner("ТИТАН НА ПЛОЩАДИ!", Color3.fromRGB(255, 110, 90))
	end
	titanTarget = Config.Social.Plaza + Vector3.new(payload.x, 0, payload.z)
	titanAngle = payload.angle or 0
	local torso = titanModel.PrimaryPart
	local gui = torso and torso:FindFirstChild("Health")
	if gui then (gui :: any).Back.Fill.Size = UDim2.fromScale(math.clamp(payload.hp, 0, 1), 1) end
end)
RunService.RenderStepped:Connect(function(dt)
	if not titanModel or not titanTarget then return end
	local height = 3.3 * titanModel:GetScale() + math.abs(math.sin(os.clock() * 3)) * 0.6
	local current = titanModel:GetPivot().Position
	local goal = Vector3.new(titanTarget.X, height, titanTarget.Z)
	local position = current:Lerp(goal, 1 - math.exp(-dt * 6))
	local forward = Vector3.new(-math.sin(titanAngle), 0, math.cos(titanAngle))
	titanModel:PivotTo(CFrame.lookAt(position, position + forward))
end)
