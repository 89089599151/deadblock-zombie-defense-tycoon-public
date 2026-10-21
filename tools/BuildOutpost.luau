-- Rebuilds Workspace.DeadblockWorld as "outpost-v5": one perimeter wall per base level (only the current
-- one is shown), build pads for turrets, factory, reactor core, command post, workshop and portal.
-- Run through tools/DevTool.luau (build option). Requires the PreCombatLayout backup.
return function(config, BaseService, TycoonModel, CompoundLayout)
	local old = workspace:FindFirstChild("DeadblockWorld")
	if old then
		local version = old:GetAttribute("BuildVersion")
		assert(version == "tycoon-v2" or version == "combat-v3" or version == "siege-v4" or version == "outpost-v5", "Unknown world: refusing to replace")
		assert(game.ServerStorage:FindFirstChild("DEADBLOCK_Backup_PreCombatLayout"), "Create backup before migrating")
		old:Destroy()
	end
	local layout = CompoundLayout.Build(config)
	local compound = config.Compound
	local world = Instance.new("Model") world.Name = "DeadblockWorld" world:SetAttribute("BuildVersion", "outpost-v5")
	local bases = Instance.new("Folder") bases.Name = "Bases" bases.Parent = world
	local palette = {
		floor = Color3.fromRGB(78, 86, 89), lockedFloor = Color3.fromRGB(40, 45, 47), dark = Color3.fromRGB(31, 39, 43),
		steel = Color3.fromRGB(100, 119, 125), orange = Color3.fromRGB(237, 159, 65), mint = Color3.fromRGB(111, 226, 173),
		white = Color3.fromRGB(232, 239, 230), cyan = Color3.fromRGB(94, 200, 222), red = Color3.fromRGB(235, 96, 80),
		wall = Color3.fromRGB(122, 130, 124), olive = Color3.fromRGB(83, 94, 72), concrete = Color3.fromRGB(104, 108, 106),
		purple = Color3.fromRGB(150, 110, 240),
	}
	local function model(name, parent) local m = Instance.new("Model") m.Name = name m.Parent = parent return m end
	local function folder(name, parent) local f = Instance.new("Folder") f.Name = name f.Parent = parent return f end
	local function part(name, size, position, color, parent, material, solid)
		local p = Instance.new("Part") p.Name = name p.Size = size p.Position = position p.Color = color p.Anchored = true
		p.Material = material or Enum.Material.SmoothPlastic p.TopSurface = Enum.SurfaceType.Smooth p.BottomSurface = Enum.SurfaceType.Smooth
		p.CanCollide = solid == true p:SetAttribute("Solid", solid == true) p:SetAttribute("OriginalTransparency", 0)
		p.Parent = parent return p
	end
	local function cylinder(name, height, diameter, position, color, parent, material, solid)
		local p = part(name, Vector3.new(height, diameter, diameter), position, color, parent, material, solid)
		p.Shape = Enum.PartType.Cylinder
		p.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.pi / 2)
		return p
	end
	local function marker(name, pos, parent)
		local p = part(name, Vector3.one, pos, palette.white, parent)
		p.Transparency = 1 p:SetAttribute("OriginalTransparency", 1) p.CanTouch = false p.CanQuery = false return p
	end
	local function text(parent, name, content, pos, size, color, fontSize)
		local t = Instance.new("TextLabel") t.Name = name t.Text = content t.Position = pos t.Size = size t.BackgroundTransparency = 1
		t.Font = Enum.Font.GothamBold t.TextColor3 = color t.TextSize = fontSize t.TextWrapped = true t.Parent = parent return t
	end
	local function billboard(adornee, title, maxDistance, offset)
		local gui = Instance.new("BillboardGui") gui.Name = "Info" gui.Size = UDim2.fromOffset(220, 64) gui.StudsOffset = offset or Vector3.new(0, 4, 0)
		gui.MaxDistance = maxDistance or 65 gui.AlwaysOnTop = false gui.Parent = adornee
		local label = text(gui, "Label", title, UDim2.fromScale(0, 0), UDim2.fromScale(1, 1), palette.white, 19)
		label.TextStrokeTransparency = 0.35
		return gui
	end
	local function prompt(parent, name, key, action, objectText, distance, kind)
		local p = Instance.new("ProximityPrompt") p.Name = name p.ActionText = action p.ObjectText = objectText p.KeyboardKeyCode = key
		p.MaxActivationDistance = distance or 12 p.RequiresLineOfSight = false p.HoldDuration = 0.15
		if kind then p:SetAttribute("ActionKind", kind) end
		p.Parent = parent return p
	end
	local function ghostOutline(target)
		local h = Instance.new("Highlight") h.Name = "Highlight" h.Adornee = target h.FillTransparency = 1
		h.OutlineColor = palette.cyan h.OutlineTransparency = 0.15 h.DepthMode = Enum.HighlightDepthMode.Occluded h.Enabled = false h.Parent = target
		return h
	end

	-- Factory pieces are authored in the original frame (belt along z) and rotated into the yard.
	local FACTORY = CFrame.new(8, 0, 30) * CFrame.Angles(0, math.pi / 2, 0)

	for id = 1, config.PlotCount do
		-- Arenas sit far apart (beyond fog) so every player has a private battlefield.
		local origin = Vector3.new(if id % 2 == 1 then -1250 else 1250, 0, (math.ceil(id / 2) - 2) * 2600)
		local function at(x, y, z) return origin + Vector3.new(x, y, z) end
		local base = model("Base" .. id, bases) base:SetAttribute("BaseId", id) base:SetAttribute("OwnerUserId", 0)
		base:SetAttribute("Origin", origin)

		-- Terrain: open field all around, cliffs and forest at the edge of the arena.
		local environment = folder("Location", base)
		part("ForestGround", Vector3.new(780, 1, 700), at(0, -0.5, 0), config.Worlds[1].Ground, environment, Enum.Material.Grass, true)
		local random = Random.new(6100 + id)
		for rockId = 1, 52 do
			local angle = rockId * math.pi * 2 / 52
			local position = at(math.cos(angle) * 392, random:NextNumber(18, 26), math.sin(angle) * 345)
			local rock = part("Cliff" .. rockId, Vector3.new(random:NextNumber(40, 56), random:NextNumber(48, 66), random:NextNumber(40, 56)), position, Color3.fromRGB(91, 99, 88), environment, Enum.Material.Rock, true)
			rock.CFrame = CFrame.new(position) * CFrame.Angles(random:NextNumber(-0.15, 0.15), angle, random:NextNumber(-0.1, 0.1))
		end
		local outer = compound.Levels[#compound.Levels]
		local treeId, attempts = 0, 0
		while treeId < 200 and attempts < 3000 do
			attempts += 1
			local x, z = random:NextNumber(-360, 360), random:NextNumber(-315, 315)
			local clear = not (math.abs(x) < outer.HalfX + 26 and math.abs(z) < outer.HalfZ + 26)
			-- Keep wide lanes free between each spawn ruin and the outpost so attacks read clearly.
			for _, point in ipairs(layout.spawnPoints) do
				local dir = point.position.Unit
				local along = Vector2.new(x, z):Dot(dir)
				local side = math.abs(Vector2.new(x, z):Dot(Vector2.new(-dir.Y, dir.X)))
				if along > 0 and side < 28 then clear = false end
			end
			if clear then
				treeId += 1
				local t = model("Tree" .. treeId, environment)
				local height = random:NextNumber(11, 18)
				part("Trunk", Vector3.new(1.8, height, 1.8), at(x, height / 2, z), Color3.fromRGB(87, 71, 48), t, Enum.Material.Wood, true)
				for layer = 1, 3 do
					local width = 12 - layer * 2
					local leaves = part("Crown", Vector3.new(width, 9, width), at(x, height - 3 + layer * 3.5, z), Color3.fromRGB(35 + layer * 7, 73 + layer * 5, 49 + layer * 5), t, Enum.Material.Grass)
					leaves.Shape = Enum.PartType.Ball
					leaves:SetAttribute("Foliage", true)
				end
			end
		end

		-- Yard floor per base level (outer levels appear when the base grows).
		local yards = folder("Yards", base)
		for level = #compound.Levels, 1, -1 do
			local size = compound.Levels[level]
			local m = model("Yard" .. level, yards) m:SetAttribute("Level", level)
			local floor = part("Floor", Vector3.new(size.HalfX * 2, 0.4, size.HalfZ * 2), at(0, 0.02 + (5 - level) * 0.04, 0), if level == 1 then palette.concrete else Color3.fromRGB(96 + level * 4, 100 + level * 4, 98 + level * 4), m, Enum.Material.Concrete, false)
			floor:SetAttribute("Solid", false)
		end

		-- Perimeter walls: one full set per base level, only the current level is visible.
		local walls = folder("Walls", base)
		for level, list in ipairs(layout.walls) do
			local set = folder("L" .. level, walls) set:SetAttribute("Level", level)
			for _, wall in ipairs(list) do
				local length = (wall.b - wall.a).Magnitude
				local m = model(wall.id, set) m:SetAttribute("WallId", wall.id)
				local height = compound.WallHeight
				local center = at(wall.center.X, height / 2, wall.center.Y)
				local heading = Vector3.new(wall.b.X - wall.a.X, 0, wall.b.Y - wall.a.Y)
				local body = part("Body", Vector3.new(2.6, height, length + 0.6), center, palette.wall, m, Enum.Material.Concrete, true)
				body.CFrame = CFrame.lookAt(center, center + heading)
				local cap = part("Cap", Vector3.new(3.4, 0.7, length + 0.6), center + Vector3.new(0, height / 2 + 0.35, 0), palette.dark, m, Enum.Material.Metal, false)
				cap.CFrame = CFrame.lookAt(cap.Position, cap.Position + heading)
				local stripe = part("Stripe", Vector3.new(2.7, 0.6, length), center + Vector3.new(0, -height / 2 + 1.4, 0), palette.orange, m, Enum.Material.Neon, false)
				stripe.CFrame = CFrame.lookAt(stripe.Position, stripe.Position + heading)
				m.PrimaryPart = body
			end
			local size = compound.Levels[level]
			for _, sx in ipairs({-1, 1}) do for _, sz in ipairs({-1, 1}) do
				local post = model("Corner", set)
				part("Post", Vector3.new(5, compound.WallHeight + 3, 5), at(sx * size.HalfX, (compound.WallHeight + 3) / 2, sz * size.HalfZ), palette.dark, post, Enum.Material.Concrete, true)
				local lamp = part("Lamp", Vector3.new(2, 1, 2), at(sx * size.HalfX, compound.WallHeight + 3.5, sz * size.HalfZ), palette.orange, post, Enum.Material.Neon, false)
				local light = Instance.new("PointLight") light.Color = palette.orange light.Range = 22 light.Brightness = 1.2 light.Parent = lamp
			end end
		end

		-- Build pads: any unlocked turret role can be built on any open pad.
		local pads = folder("Pads", base)
		for _, padInfo in ipairs(layout.pads) do
			local P = padInfo.position
			local m = model("Pad" .. padInfo.id, pads) m:SetAttribute("Pad", padInfo.id) m:SetAttribute("Level", padInfo.level)
			local plate = cylinder("Plate", 1, 11, at(P.X, 0.5, P.Y), palette.dark, m, Enum.Material.Concrete, true)
			local ring = cylinder("Ring", 0.2, 12, at(P.X, 0.9, P.Y), palette.cyan, m, Enum.Material.Neon, false)
			ring.Transparency = 0.25
			billboard(plate, padInfo.label, 80, Vector3.new(0, 9, 0))
			prompt(plate, "PadPrompt", Enum.KeyCode.E, "Построить турель", padInfo.label, 13, "Pad"):SetAttribute("Pad", padInfo.id)
		end

		-- Spawn ruins on all eight sides of the arena.
		local spawns = folder("SpawnMarkers", base)
		for _, point in ipairs(layout.spawnPoints) do
			local m = model(point.direction, spawns) m:SetAttribute("Direction", point.direction)
			local toCore = Vector3.new(-point.position.X, 0, -point.position.Y).Unit
			local side = toCore:Cross(Vector3.yAxis)
			local pos = at(point.position.X, 0, point.position.Y)
			part("PillarL", Vector3.new(3, 14, 3), pos + side * 8 + Vector3.new(0, 7, 0), palette.dark, m, Enum.Material.Slate, true)
			part("PillarR", Vector3.new(3, 14, 3), pos - side * 8 + Vector3.new(0, 7, 0), palette.dark, m, Enum.Material.Slate, true)
			local lintel = part("Lintel", Vector3.new(19, 2, 3), pos + Vector3.new(0, 15, 0), palette.dark, m, Enum.Material.Slate, true)
			lintel.CFrame = CFrame.lookAt(lintel.Position, lintel.Position + side)
			local light = part("Alarm", Vector3.new(2.6, 2.6, 2.6), pos + Vector3.new(0, 17.5, 0), Color3.fromRGB(70, 40, 38), m, Enum.Material.SmoothPlastic)
			light.Shape = Enum.PartType.Ball
			local pl = Instance.new("PointLight") pl.Name = "PointLight" pl.Color = Color3.fromRGB(255, 70, 50) pl.Range = 40 pl.Brightness = 3 pl.Enabled = false pl.Parent = light
		end

		-- Reactor core, command post, workshop, portal.
		local combat = folder("Combat", base)
		folder("Engineers", combat)
		local C = compound.Core
		local core = model("Core", combat) core:SetAttribute("Health", config.Core.MaxHealth)
		cylinder("Platform", 1.5, 24, at(C.X, 0.75, C.Y), palette.dark, core, Enum.Material.Concrete, true)
		local attackRing = cylinder("AttackRing", 0.1, config.Core.Reach * 2, at(C.X, 1.6, C.Y), palette.red, core, Enum.Material.Neon)
		attackRing.Transparency = 0.85
		local coreBody = cylinder("CoreBody", 9, 9, at(C.X, 6, C.Y), palette.steel, core, Enum.Material.Metal, true)
		cylinder("Collar", 0.8, 11, at(C.X, 10.6, C.Y), palette.orange, core, Enum.Material.Neon)
		local crystal = part("Crystal", Vector3.new(5, 5, 5), at(C.X, 14, C.Y), palette.mint, core, Enum.Material.Neon) crystal.Shape = Enum.PartType.Ball
		local coreLight = Instance.new("PointLight") coreLight.Color = palette.mint coreLight.Range = 30 coreLight.Brightness = 2 coreLight.Parent = crystal
		prompt(coreBody, "WavePrompt", Enum.KeyCode.E, "Начать волну", "Реактор", 16)
		billboard(coreBody, "ЯДРО", 120, Vector3.new(0, 11, 0)).Size = UDim2.fromOffset(260, 40)

		local console = model("Console", combat)
		local pad = part("Pad", Vector3.new(5, 3, 3), at(C.X + 20, 1.5, C.Y), palette.dark, console, Enum.Material.Metal, true)
		part("Screen", Vector3.new(4, 1.4, 0.2), at(C.X + 20, 2.6, C.Y - 1.6), palette.cyan, console, Enum.Material.Neon)
		billboard(pad, "Командный пункт", 70, Vector3.new(0, 4, 0))
		prompt(pad, "ExpandPrompt", Enum.KeyCode.E, "Расширить базу", "Командный пункт")
		prompt(pad, "WallsPrompt", Enum.KeyCode.F, "Укрепить стены", "Командный пункт")
		prompt(pad, "RepairPrompt", Enum.KeyCode.G, "Ремонт базы", "Командный пункт")

		-- Teleport to the plaza, west of the reactor.
		local hub = model("HubPad", combat)
		local hubPad = cylinder("Pad", 0.6, 8, at(C.X - 22, 0.4, C.Y), Color3.fromRGB(110, 200, 255), hub, Enum.Material.Neon, false)
		hubPad.Transparency = 0.2
		billboard(hubPad, "Площадь", 70, Vector3.new(0, 4, 0))
		prompt(hubPad, "HubPrompt", Enum.KeyCode.E, "На площадь", "Телепорт", 10)

		local workshop = model("Workshop", combat)
		part("Hall", Vector3.new(26, 9, 16), at(50, 4.5, -45), palette.olive, workshop, Enum.Material.Concrete, true)
		part("Roof", Vector3.new(28, 1, 18), at(50, 9.5, -45), palette.dark, workshop, Enum.Material.Metal, true)
		local door = part("Door", Vector3.new(8, 6, 0.5), at(50, 3, -36.8), palette.orange, workshop, Enum.Material.Metal, true)
		marker("EngineerSpawn", at(50, 3, -32), workshop)
		billboard(workshop.Hall, "Мастерская", 70, Vector3.new(0, 9, 0))
		prompt(door, "HirePrompt", Enum.KeyCode.E, "Нанять инженера", "Мастерская", 14)

		local barracks = model("Barracks", combat)
		part("Hall", Vector3.new(24, 8, 12), at(-52, 4, -12), palette.olive, barracks, Enum.Material.Concrete, true)
		part("Roof", Vector3.new(26, 1, 14), at(-52, 8.5, -12), palette.dark, barracks, Enum.Material.Metal, true)

		local PO = compound.Portal
		local portal = model("Portal", combat)
		cylinder("Base", 1.2, 18, at(PO.X, 0.6, PO.Y), palette.dark, portal, Enum.Material.Concrete, true)
		for _, dx in ipairs({-6.5, 6.5}) do part("Pillar", Vector3.new(2, 14, 2), at(PO.X + dx, 7.6, PO.Y), palette.steel, portal, Enum.Material.Metal, true) end
		part("Top", Vector3.new(15, 2, 2), at(PO.X, 15.2, PO.Y), palette.steel, portal, Enum.Material.Metal, true)
		local field = part("Field", Vector3.new(11, 12.6, 0.4), at(PO.X, 7.5, PO.Y), palette.purple, portal, Enum.Material.Neon, false)
		field.Transparency = 0.35
		local portalLight = Instance.new("PointLight") portalLight.Color = palette.purple portalLight.Range = 24 portalLight.Brightness = 2 portalLight.Parent = field
		billboard(portal.Top, "Портал", 90, Vector3.new(0, 3, 0))
		prompt(portal.Base, "PortalPrompt", Enum.KeyCode.E, "Портал", "Портал", 14)
		prompt(portal.Base, "BackPrompt", Enum.KeyCode.F, "Предыдущий мир", "Портал", 14)

		-- Factory (authored in the old frame, then rotated into the yard).
		local function f(x, y, z) return Vector3.new(x, y, z) end
		local zones = folder("Zones", base)
		for zoneId = 0, 2 do
			local zone = model("Zone" .. zoneId, zones) zone:SetAttribute("ZoneIndex", zoneId)
			local z = 20 - zoneId * 40
			local foundation = part("Foundation", Vector3.new(56, 1, 40), f(0, 0.5, z), palette.floor, zone, Enum.Material.Concrete, true)
			foundation:SetAttribute("AlwaysVisible", true) foundation:SetAttribute("OpenColor", palette.floor) foundation:SetAttribute("LockedColor", palette.lockedFloor)
			for _, x in ipairs({-28, 28}) do
				part("Edge", Vector3.new(0.5, 0.18, 40), f(x, 1.1, z), palette.orange, zone)
				part("FenceRail", Vector3.new(0.4, 0.4, 40), f(x, 3.2, z), palette.steel, zone, Enum.Material.Metal, true)
				for offset = -18, 18, 12 do part("FencePost", Vector3.new(0.65, 3.6, 0.65), f(x, 2.8, z + offset), palette.dark, zone, Enum.Material.Metal, true) end
			end
			local length = if zoneId == 0 then 34 else 40
			local centre = if zoneId == 0 then 17 else z
			part("Conveyor", Vector3.new(6, 0.5, length), f(0, 1.75, centre), palette.dark, zone, Enum.Material.Rubber, true)
			for _, x in ipairs({-3.4, 3.4}) do part("BeltRail", Vector3.new(0.45, 0.5, length), f(x, 2, centre), palette.steel, zone, Enum.Material.Metal) end
			for offset = -length / 2 + 1, length / 2 - 1, 3 do part("BeltTread", Vector3.new(5.8, 0.08, 0.2), f(0, 2.04, centre + offset), palette.steel, zone) end
			if zoneId > 0 then
				for offset = -12, 12, 12 do
					part("LampArm", Vector3.new(0.4, 0.4, 3), f(-24, 12, z + offset), palette.steel, zone, Enum.Material.Metal)
					part("Lamp", Vector3.new(2.4, 0.4, 1.2), f(-24, 11.6, z + offset), palette.white, zone, Enum.Material.Neon)
				end
			end
		end
		local gates = folder("Gates", base)
		for gateIndex = 1, 2 do
			local boundary = 40 - gateIndex * 40
			local gateModel = model("Gate" .. gateIndex, gates) gateModel:SetAttribute("GateIndex", gateIndex)
			local gateDoor = part("Door", Vector3.new(54, 12, 1.4), f(0, 7, boundary), palette.steel, gateModel, Enum.Material.CorrodedMetal, true)
			local light = Instance.new("PointLight") light.Name = "Light" light.Color = palette.orange light.Range = 14 light.Brightness = 1.5 light.Parent = gateDoor
			local gui = Instance.new("SurfaceGui") gui.Face = Enum.NormalId.Front gui.CanvasSize = Vector2.new(900, 200) gui.LightInfluence = 0 gui.Parent = gateDoor
			text(gui, "Lock", "ЦЕХ ЗАКРЫТ", UDim2.fromScale(0, 0.15), UDim2.fromScale(1, 0.7), palette.orange, 44)
			prompt(gateDoor, "GatePrompt", Enum.KeyCode.E, "Открыть цех", "Цех " .. (gateIndex + 1), 16)
			for _, x in ipairs({-27.5, 27.5}) do part("Pillar", Vector3.new(2, 14, 2), f(x, 7, boundary), palette.dark, gateModel, Enum.Material.Metal, true) end
		end
		local spawn = marker("SpawnPoint", f(13, 4.5, 31), base)
		spawn.CFrame = CFrame.lookAt(spawn.Position, f(1, 4.5, 10))
		local sign = model("Sign", base)
		local board = part("Board", Vector3.new(22, 6, 0.6), f(-15, 5.8, 38), palette.dark, sign, Enum.Material.Metal, true)
		board.CFrame = CFrame.new(board.Position) * CFrame.Angles(0, math.pi, 0)
		local sg = Instance.new("SurfaceGui") sg.Name = "SurfaceGui" sg.CanvasSize = Vector2.new(1000, 300) sg.LightInfluence = 0 sg.Parent = board
		text(sg, "Title", "DEADBLOCK / АВАНПОСТ", UDim2.fromScale(0.04, 0.03), UDim2.fromScale(0.92, 0.25), palette.orange, 40)
		text(sg, "Owner", "СВОБОДНАЯ БАЗА", UDim2.fromScale(0.04, 0.32), UDim2.fromScale(0.92, 0.25), palette.white, 38)
		text(sg, "Status", "ОЖИДАНИЕ ИГРОКА", UDim2.fromScale(0.04, 0.7), UDim2.fromScale(0.92, 0.2), palette.mint, 26)
		local production = model("Production", base) folder("Ores", production)
		marker("BeltEnd", f(0, 2.8, 34), production)
		local collector = model("Collector", production)
		local collectorBody = part("Body", Vector3.new(9, 3, 6), f(0, 2.5, 36), palette.dark, collector, Enum.Material.Metal, true)
		prompt(collectorBody, "OverdrivePrompt", Enum.KeyCode.E, "Перегрев завода", "Приёмник", 12)
		part("Intake", Vector3.new(6.2, 2, 0.25), f(0, 2.7, 33), palette.mint, collector, Enum.Material.Neon)
		local display = part("Display", Vector3.new(8, 2.5, 0.3), f(0, 4.7, 39.1), palette.dark, collector)
		display.CFrame = CFrame.new(display.Position) * CFrame.Angles(0, math.pi, 0)
		local money = Instance.new("SurfaceGui") money.Name = "SurfaceGui" money.CanvasSize = Vector2.new(800, 240) money.LightInfluence = 0 money.Parent = display
		text(money, "Amount", "$ 0", UDim2.fromScale(0.03, 0.05), UDim2.fromScale(0.94, 0.8), palette.mint, 105)
		local droppers = folder("Droppers", base)
		local buyPads = folder("BuyPads", base)
		for dropperId, def in ipairs(config.Droppers) do
			local m = model("Dropper" .. dropperId, droppers) m:SetAttribute("DropperId", dropperId)
			local body = part("MachineBody", Vector3.new(8, 6, 7), f(-10, 5, def.Z), palette.steel, m, Enum.Material.Metal, true)
			part("Housing", Vector3.new(6, 1.2, 6), f(-10, 8.5, def.Z), palette.dark, m, Enum.Material.Metal, true)
			part("LightStrip", Vector3.new(6, 0.5, 0.15), f(-10, 6.4, def.Z + 3.6), palette.orange, m, Enum.Material.Neon)
			part("TransferPipe", Vector3.new(8, 1, 1.5), f(-4, 6, def.Z), palette.steel, m, Enum.Material.Metal)
			part("Nozzle", Vector3.new(2, 1.5, 2), f(0, 5.3, def.Z), palette.dark, m, Enum.Material.Metal)
			part("Stack", Vector3.new(1.4, 5, 1.4), f(-12, 11, def.Z - 1.5), palette.dark, m, Enum.Material.Metal):SetAttribute("MinLevel", 2)
			part("LevelNeon", Vector3.new(0.3, 4, 6.4), f(-14.1, 5, def.Z), palette.mint, m, Enum.Material.Neon):SetAttribute("MinLevel", 3)
			marker("DropPoint", f(0, 4.5, def.Z), m)
			marker("BeltStart", f(0, 2.8, def.Z), m)
			ghostOutline(m)
			billboard(body, def.Name, 55)
			local inspect = prompt(body, "ProximityPrompt", Enum.KeyCode.E, "Улучшить", def.Name, 11, "InspectDropper")
			inspect:SetAttribute("DropperId", dropperId)
			if dropperId > 1 then
				local buy = model("BuyDropper" .. dropperId, buyPads) buy:SetAttribute("ActionKind", "BuyDropper") buy:SetAttribute("TargetId", dropperId) buy:SetAttribute("Price", def.Price)
				local p = part("Pad", Vector3.new(8, 0.3, 7), f(-20, 1.3, def.Z), Color3.fromRGB(210, 115, 70), buy, Enum.Material.Neon, true)
				billboard(p, def.Name .. "\n$ " .. def.Price, 55).StudsOffset = Vector3.new(0, 3, 0)
				prompt(p, "ProximityPrompt", Enum.KeyCode.E, "Купить · $ " .. def.Price, def.Name, 11, "BuyDropper")
			end
		end
		local toPlot = CFrame.new(origin) * FACTORY
		for _, container in ipairs({zones, gates, droppers, buyPads, production, sign}) do
			for _, descendant in ipairs(container:GetDescendants()) do
				if descendant:IsA("BasePart") then descendant.CFrame = toPlot * descendant.CFrame end
			end
		end
		spawn.CFrame = toPlot * spawn.CFrame
		for _, gateModel in ipairs(gates:GetChildren()) do gateModel:SetAttribute("ClosedPosition", gateModel.Door.Position) end
		-- Power cable from the collector to the reactor.
		local collectorPos = collector.Body.Position
		local coreWorld = at(C.X, 0, C.Y)
		local cableA = part("PowerCableA", Vector3.new(1, 0.4, math.abs(collectorPos.Z - coreWorld.Z)), Vector3.new(collectorPos.X, 0.35, (collectorPos.Z + coreWorld.Z) / 2), palette.dark, collector, Enum.Material.Metal, false)
		local cableB = part("PowerCableB", Vector3.new(math.abs(collectorPos.X - coreWorld.X), 0.4, 1), Vector3.new((collectorPos.X + coreWorld.X) / 2, 0.35, coreWorld.Z), palette.dark, collector, Enum.Material.Metal, false)
		part("GlowA", Vector3.new(0.35, 0.15, cableA.Size.Z), cableA.Position + Vector3.new(0, 0.3, 0), palette.mint, collector, Enum.Material.Neon, false)
		part("GlowB", Vector3.new(cableB.Size.X, 0.15, 0.35), cableB.Position + Vector3.new(0, 0.3, 0), palette.mint, collector, Enum.Material.Neon, false)
		base.Parent = bases
		task.wait()
	end
	-- Central plaza: teleports to every base, the server leaderboard and the Titan's arena.
	do
		local center = config.Social.Plaza
		local function p(x, y, z) return center + Vector3.new(x, y, z) end
		local plaza = model("Plaza", world)
		cylinder("Floor", 1, config.Social.PlazaRadius * 2, p(0, 0.5, 0), palette.concrete, plaza, Enum.Material.Concrete, true)
		-- The Titan's path: a dashed glowing circle on the stones.
		for index = 1, 40 do
			local angle = index * math.pi * 2 / 40
			local dash = part("Path", Vector3.new(1.2, 0.2, 7), p(math.cos(angle) * config.Titan.Orbit, 1.1, math.sin(angle) * config.Titan.Orbit), palette.red, plaza, Enum.Material.Neon, false)
			dash.CFrame = CFrame.new(dash.Position) * CFrame.Angles(0, -angle, 0)
			dash.Transparency = 0.35
		end
		marker("Spawn", p(0, 3, -88), plaza)
		local teleports = folder("Teleports", plaza)
		for id = 1, config.PlotCount do
			local angle = math.pi + (id - 1) * (math.pi / (config.PlotCount - 1))
			local pos = p(math.cos(angle) * 112, 0.6, math.sin(angle) * 112 - 0)
			local pad = model("Teleport" .. id, teleports) pad:SetAttribute("BaseId", id)
			local disc = cylinder("Pad", 0.6, 9, pos, Color3.fromRGB(110, 200, 255), pad, Enum.Material.Neon, false)
			disc.Transparency = 0.2
			billboard(disc, "База " .. id, 120, Vector3.new(0, 5, 0))
			prompt(disc, "TeleportPrompt", Enum.KeyCode.E, "Телепорт на базу", "База " .. id, 10)
		end
		local function makeBoard(name, title, x)
			local board = model(name, plaza)
			local position = p(x, 11, 116)
			local screen = part("Screen", Vector3.new(36, 18, 1), position, palette.dark, board, Enum.Material.Metal, true)
			screen.CFrame = CFrame.lookAt(position, p(x * 0.3, 11, 0))
			local gui = Instance.new("SurfaceGui") gui.Name = "SurfaceGui" gui.Face = Enum.NormalId.Front gui.CanvasSize = Vector2.new(1100, 540) gui.LightInfluence = 0 gui.Parent = screen
			text(gui, "Title", title, UDim2.fromScale(0.04, 0.03), UDim2.fromScale(0.92, 0.14), palette.orange, 46)
			local rows = text(gui, "Rows", "Пока пусто", UDim2.fromScale(0.05, 0.2), UDim2.fromScale(0.9, 0.76), palette.white, 32)
			rows.TextXAlignment = Enum.TextXAlignment.Left rows.TextYAlignment = Enum.TextYAlignment.Top
			for _, dx in ipairs({-18.5, 18.5}) do part("Post", Vector3.new(1.5, 20, 1.5), (screen.CFrame * CFrame.new(dx, -1, 0.8)).Position, palette.steel, board, Enum.Material.Metal, true) end
		end
		makeBoard("Board", "КОМАНДИРЫ СЕРВЕРА", -22)
		makeBoard("GlobalBoard", "ЛУЧШИЕ В МИРЕ", 22)
		for index = 1, 8 do
			local angle = index * math.pi / 4
			local lamp = part("Lamp", Vector3.new(1.2, 14, 1.2), p(math.cos(angle) * 125, 7, math.sin(angle) * 125), palette.dark, plaza, Enum.Material.Metal, true)
			local bulb = part("Bulb", Vector3.new(2, 1, 2), lamp.Position + Vector3.new(0, 7.5, 0), palette.orange, plaza, Enum.Material.Neon, false)
			local light = Instance.new("PointLight") light.Range = 30 light.Brightness = 1.5 light.Color = palette.orange light.Parent = bulb
		end
	end
	world.Parent = workspace
	local baseService = BaseService.new(world, config)
	for _, base in ipairs(bases:GetChildren()) do baseService:Refresh(base, TycoonModel.new(config, 0), 0) end
	local starter = game:GetService("StarterPlayer") starter.CameraMaxZoomDistance = 120 starter.CameraMinZoomDistance = 5 starter.DevCameraOcclusionMode = Enum.DevCameraOcclusionMode.Zoom
	local lighting = game:GetService("Lighting") lighting.ClockTime = 14.7 lighting.Brightness = 2.5 lighting.Ambient = Color3.fromRGB(127, 143, 138) lighting.OutdoorAmbient = Color3.fromRGB(133, 145, 144)
	lighting.FogColor = config.Worlds[1].Fog lighting.FogStart = 380 lighting.FogEnd = 1000
	return { world = world:GetFullName(), bases = #bases:GetChildren(), descendants = #world:GetDescendants() }
end
