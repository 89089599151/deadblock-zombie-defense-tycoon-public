-- Plot ownership and everything about how an outpost looks for its current economy state.
-- Pure presentation of TycoonModel; it never changes money or ownership by itself.
local TweenService = game:GetService("TweenService")
local PlotRegistry = require(script.Parent.PlotRegistry)
local TycoonModel = require(script.Parent.TycoonModel)
local CompoundLayout = require(script.Parent.CompoundLayout)
local TurretVisuals = require(script.Parent.TurretVisuals)
local TurretMath = require(game:GetService("ReplicatedStorage"):WaitForChild("DeadblockShared"):WaitForChild("TurretMath"))

local BaseService = {}
BaseService.__index = BaseService

local AFFORD = Color3.fromRGB(90, 213, 160)
local EXPENSIVE = Color3.fromRGB(210, 115, 70)
local EMPTY_RING = Color3.fromRGB(94, 200, 222)

function BaseService.new(world, config)
	return setmetatable({ world = world, config = config, layout = CompoundLayout.Build(config), registry = PlotRegistry.new(config.PlotCount) }, BaseService)
end

local function show(container: Instance, visible: boolean, ghost: boolean?)
	for _, obj in ipairs(container:GetDescendants()) do
		if obj:IsA("BasePart") then
			local original = obj:GetAttribute("OriginalTransparency") or 0
			if obj:GetAttribute("AlwaysVisible") then
				-- Mothballed floors stay on screen so locked land reads as a place, not a hole.
				obj.Transparency = original
				obj.CanCollide = true
				obj.Color = if visible then obj:GetAttribute("OpenColor") else obj:GetAttribute("LockedColor")
				continue
			end
			obj.Transparency = if visible then math.max(original, if ghost then 0.8 else 0) else 1
			obj.CanCollide = visible and not ghost and obj:GetAttribute("Solid") == true
		elseif obj:IsA("SurfaceGui") or obj:IsA("BillboardGui") then obj.Enabled = visible and not ghost
		elseif obj:IsA("Highlight") then obj.Enabled = visible and ghost == true
		elseif obj:IsA("ProximityPrompt") then obj.Enabled = visible and not ghost
		elseif obj:IsA("Light") then obj.Enabled = visible and not ghost end
	end
end

function BaseService:Assign(player)
	local id = self.registry:Claim(player.UserId)
	if not id then return nil end
	local base = self.world.Bases:FindFirstChild("Base" .. id)
	assert(base, "Missing base")
	base:SetAttribute("OwnerUserId", player.UserId)
	base.Sign.Board.SurfaceGui.Owner.Text = player.DisplayName
	return base
end

function BaseService:GetOwned(player)
	local id = self.registry:Get(player.UserId)
	return id and self.world.Bases:FindFirstChild("Base" .. id) or nil
end

function BaseService:UpdateMoney(base, tycoon)
	base.Production.Collector.Display.SurfaceGui.Amount.Text = "$ " .. tycoon.money
	for _, pad in ipairs(base.BuyPads:GetChildren()) do
		pad.Pad.Color = if tycoon.money >= (pad:GetAttribute("Price") or 0) then AFFORD else EXPENSIVE
	end
end

function BaseService:RefreshGates(base, tycoon, ownerId)
	for _, gate in ipairs(base.Gates:GetChildren()) do
		local index = gate:GetAttribute("GateIndex")
		local open = tycoon.expansion >= index
		-- Closed gates sell themselves: price and requirement right where the player looks.
		local expansion = self.config.Expansions[index]
		local prompt = gate.Door:FindFirstChild("GatePrompt")
		if prompt and expansion then
			local missing = expansion.Prerequisite and not tycoon.droppers[expansion.Prerequisite]
			local blocked = tycoon.expansion + 1 < index
			prompt.Enabled = not open and ownerId ~= 0
			prompt.ActionText = if blocked then "Сначала открой предыдущий цех" elseif missing then "Нужен дроппер " .. expansion.Prerequisite else "Открыть цех · $ " .. expansion.Price
			local label = gate.Door:FindFirstChildOfClass("SurfaceGui")
			if label and label:FindFirstChild("Lock") then
				label.Lock.Text = if blocked then "ЦЕХ ЗАКРЫТ" elseif missing then "ЦЕХ ЗАКРЫТ · НУЖЕН ДРОППЕР " .. expansion.Prerequisite else "ОТКРЫТЬ ЦЕХ · $ " .. expansion.Price
			end
		end
		if open ~= (gate:GetAttribute("Open") == true) then
			gate:SetAttribute("Open", open)
			local door = gate.Door
			local closed = gate:GetAttribute("ClosedPosition")
			if open then
				door.CanCollide = false
				door.Light.Enabled = false
				TweenService:Create(door, TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = closed + Vector3.new(0, 16, 0), Transparency = 1 }):Play()
			else
				door.Position = closed door.Transparency = 0 door.CanCollide = true door.Light.Enabled = true
			end
		end
	end
end

function BaseService:RefreshDroppers(base, tycoon, ownerId)
	local cap = TurretMath.LevelCap(self.config, tycoon.worldId)
	for id, def in ipairs(self.config.Droppers) do
		local model = base.Droppers:FindFirstChild("Dropper" .. id)
		local level = tycoon.droppers[id]
		local available = def.RequiredExpansion <= tycoon.expansion and (not def.Prerequisite or tycoon.droppers[def.Prerequisite] ~= nil)
		show(model, level ~= nil or available, level == nil)
		for _, accent in ipairs(model:GetChildren()) do
			local minLevel = accent:IsA("BasePart") and accent:GetAttribute("MinLevel")
			if minLevel and (level or 0) < minLevel then accent.Transparency = 1 accent.CanCollide = false end
		end
		model:SetAttribute("Owned", level ~= nil)
		model:SetAttribute("OwnerUserId", ownerId)
		model:SetAttribute("Level", level or 0)
		model:SetAttribute("Value", if level then tycoon:GetDropperValue(id, level) else 0)
		model:SetAttribute("UpgradeCost", if level and level < cap then def.Levels[level + 1].Cost else 0)
		model:SetAttribute("MaxLevel", cap)
		if level then
			model.MachineBody.Color = if level >= 3 then Color3.fromRGB(91, 167, 154) elseif level == 2 then Color3.fromRGB(78, 122, 149) else Color3.fromRGB(73, 85, 98)
			model.MachineBody.Info.Label.Text = def.Name .. "  ·  " .. level .. "/" .. cap .. "\n$ " .. tycoon:GetDropperValue(id, level) .. " за блок"
		end
		local pad = base.BuyPads:FindFirstChild("BuyDropper" .. id)
		if pad then show(pad, level == nil and available and ownerId ~= 0) end
	end
end

function BaseService:RefreshPerimeter(base, tycoon)
	local level = tycoon:GetBaseLevel()
	for _, set in ipairs(base.Walls:GetChildren()) do show(set, set:GetAttribute("Level") == level) end
	for _, yard in ipairs(base.Yards:GetChildren()) do show(yard, yard:GetAttribute("Level") <= level) end
	base:SetAttribute("BaseLevel", level)
end

function BaseService:RefreshPads(base, tycoon, ownerId)
	local level = tycoon:GetBaseLevel()
	local cap = TurretMath.LevelCap(self.config, tycoon.worldId)
	for _, info in ipairs(self.layout.pads) do
		local pad = base.Pads:FindFirstChild("Pad" .. info.id)
		local open = info.level <= level
		local turret = tycoon.turrets[info.id]
		for _, name in ipairs({ "Plate", "Ring" }) do
			local p = pad[name]
			p.Transparency = if open then (if name == "Ring" then 0.25 else 0) else 1
			p.CanCollide = open and name == "Plate"
		end
		pad.Plate.Info.Enabled = open and ownerId ~= 0
		local prompt = pad.Plate.PadPrompt
		prompt.Enabled = open and ownerId ~= 0
		pad:SetAttribute("Open", open)
		pad:SetAttribute("TurretType", if turret then turret.type else nil)
		pad:SetAttribute("TurretLevel", if turret then turret.level else 0)
		pad:SetAttribute("LevelCap", cap)
		for _, moduleName in ipairs(self.config.Modules.Order) do
			pad:SetAttribute("Mod" .. moduleName, if turret then (turret.modules[moduleName] or 0) else 0)
		end
		if turret then
			local definition = self.config.TurretTypes[turret.type]
			pad.Ring.Color = definition.Color
			pad.Plate.Info.Label.Text = definition.Name .. "  ·  " .. turret.level .. "/" .. cap
			prompt.ActionText = "Улучшить или продать"
			prompt.ObjectText = definition.Name
			local visual = pad:FindFirstChild("Turret")
			if not visual or visual:GetAttribute("Type") ~= turret.type or visual:GetAttribute("Level") ~= turret.level then
				TurretVisuals.Build(pad, turret.type, turret.level, self.config)
			end
		else
			pad.Ring.Color = EMPTY_RING
			pad.Plate.Info.Label.Text = info.label
			prompt.ActionText = "Построить турель"
			prompt.ObjectText = info.label
			TurretVisuals.Clear(pad)
		end
	end
end

function BaseService:RefreshFacilities(base, tycoon, ownerId)
	local config = self.config
	local owned = ownerId ~= 0
	local console = base.Combat.Console.Pad
	local nextExpansion = config.Expansions[tycoon.expansion + 1]
	console.ExpandPrompt.Enabled = owned and nextExpansion ~= nil
	if nextExpansion then
		local missing = nextExpansion.Prerequisite and not tycoon.droppers[nextExpansion.Prerequisite]
		console.ExpandPrompt.ActionText = "Расширить базу до ур. " .. (tycoon.expansion + 2) .. " · $ " .. nextExpansion.Price .. (if missing then " · нужен дроппер " .. nextExpansion.Prerequisite else "")
	end
	local wallCap = TurretMath.WallCap(config, tycoon.worldId)
	local nextWall = if tycoon.wallLevel < wallCap then config.Walls.UpgradePrices[tycoon.wallLevel + 1] else nil
	console.WallsPrompt.Enabled = owned and nextWall ~= nil
	if nextWall then console.WallsPrompt.ActionText = "Укрепить стены до ур. " .. (tycoon.wallLevel + 1) .. " · $ " .. nextWall end
	console.RepairPrompt.Enabled = owned
	local hire = base.Combat.Workshop.Door.HirePrompt
	local price = config.Engineers.Prices[tycoon.engineers + 1]
	hire.Enabled = owned and price ~= nil
	if price then hire.ActionText = "Нанять инженера " .. (tycoon.engineers + 1) .. "/" .. config.Engineers.MaxCount .. " · $ " .. price end
	local portal = base.Combat.Portal.Base
	local nextWorld = config.Worlds[tycoon.worldId + 1]
	portal.PortalPrompt.Enabled = owned and nextWorld ~= nil
	if nextWorld then
		if tycoon.unlockedWorld >= nextWorld.Id then
			portal.PortalPrompt.ActionText = "Перейти: " .. nextWorld.Name
		else
			portal.PortalPrompt.ActionText = "Открыть «" .. nextWorld.Name .. "» · $ " .. nextWorld.PortalPrice .. " · волна " .. nextWorld.PortalWave
		end
	end
	local previous = config.Worlds[tycoon.worldId - 1]
	portal.BackPrompt.Enabled = owned and previous ~= nil
	if previous then portal.BackPrompt.ActionText = "Вернуться: " .. previous.Name end
	local overdrive = base.Production.Collector.Body:FindFirstChild("OverdrivePrompt")
	if overdrive then
		local left = tycoon:OverdriveLeft()
		overdrive.Enabled = owned
		overdrive.ActionText = "Перегрев: доход ×" .. config.Overdrive.Multiplier .. " на " .. math.floor(config.Overdrive.Duration / 60) .. " мин · " .. config.Overdrive.Cost .. " ядер"
	end
	base.Location.ForestGround.Color = config.Worlds[tycoon.worldId].Ground
	for _, descendant in ipairs(base.Location:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant:GetAttribute("Foliage") then
			descendant.Color = if tycoon.worldId == 2 then Color3.fromRGB(120, 112, 70) elseif tycoon.worldId == 3 then Color3.fromRGB(70, 78, 72) else Color3.fromRGB(49, 83, 64)
		end
	end
end

function BaseService:Refresh(base, tycoon, ownerId)
	base:SetAttribute("Expansion", tycoon.expansion)
	base:SetAttribute("WorldId", tycoon.worldId)
	for _, zone in ipairs(base.Zones:GetChildren()) do show(zone, zone:GetAttribute("ZoneIndex") <= tycoon.expansion) end
	self:RefreshDroppers(base, tycoon, ownerId)
	self:RefreshGates(base, tycoon, ownerId)
	self:RefreshPerimeter(base, tycoon)
	self:RefreshPads(base, tycoon, ownerId)
	self:RefreshFacilities(base, tycoon, ownerId)
	local world = self.config.Worlds[tycoon.worldId]
	base.Sign.Board.SurfaceGui.Status.Text = if ownerId == 0 then "ОЖИДАНИЕ ИГРОКА" else "УРОВЕНЬ БАЗЫ " .. tycoon:GetBaseLevel() .. "  ·  МИР «" .. string.upper(world.Name) .. "»"
	self:UpdateMoney(base, tycoon)
end

function BaseService:Release(player)
	local id = self.registry:Release(player.UserId)
	if not id then return end
	local base = self.world.Bases:FindFirstChild("Base" .. id)
	if not base then return end
	base:SetAttribute("OwnerUserId", 0)
	base.Sign.Board.SurfaceGui.Owner.Text = "СВОБОДНАЯ БАЗА"
	base.Production.Ores:ClearAllChildren()
	self:Refresh(base, TycoonModel.new(self.config, 0), 0)
end

return BaseService
