--!strict
-- Builds the visible turret on a pad. Pure presentation: the simulation never reads these parts.
-- Every head faces -Z (CFrame.lookAt convention) so clients can aim it with a yaw-only PivotTo.
local TurretVisuals = {}

local STEEL = Color3.fromRGB(100, 119, 125)
local DARK = Color3.fromRGB(31, 39, 43)
local TIER_ACCENT = { Color3.fromRGB(150, 160, 165), Color3.fromRGB(240, 196, 80), Color3.fromRGB(190, 140, 255) }

local function part(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name p.Size = size p.CFrame = cframe p.Color = color p.Anchored = true
	p.Material = material or Enum.Material.Metal p.CanCollide = false p.CanQuery = false p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then p.Shape = shape end
	p.Parent = parent
	return p
end

-- Cylinder whose axis runs along the given local direction ("X", "Y" or "Z").
local function tube(parent: Instance, name: string, length: number, diameter: number, cframe: CFrame, axis: string, color: Color3, material: Enum.Material?): Part
	local rotation = if axis == "Y" then CFrame.Angles(0, 0, math.pi / 2) elseif axis == "Z" then CFrame.Angles(0, math.pi / 2, 0) else CFrame.new()
	return part(parent, name, Vector3.new(length, diameter, diameter), cframe * rotation, color, material, Enum.PartType.Cylinder)
end

function TurretVisuals.Build(pad: Model, typeName: string, level: number, config: any): Model
	local existing = pad:FindFirstChild("Turret")
	if existing then existing:Destroy() end
	local plate = pad:FindFirstChild("Plate") :: BasePart
	local center = plate.Position + Vector3.new(0, 0.5, 0)
	local definition = config.TurretTypes[typeName]
	local tier = math.clamp(math.ceil(level / 3), 1, 3)
	local accent = TIER_ACCENT[tier]
	local color = definition.Color
	local model = Instance.new("Model")
	model.Name = "Turret"
	model:SetAttribute("Type", typeName)
	model:SetAttribute("Level", level)
	local head = Instance.new("Model")
	head.Name = "Head"
	head.Parent = model
	local headHeight = if typeName == "Sniper" then 6.2 elseif typeName == "Mortar" then 2.6 else 4.4
	local H = CFrame.new(center + Vector3.new(0, headHeight, 0))
	-- Pedestal and level pips (1-3 lights per tier).
	if typeName == "Mortar" then
		part(model, "Pedestal", Vector3.new(5, 1.6, 5), CFrame.new(center + Vector3.new(0, 0.8, 0)), Color3.fromRGB(83, 94, 72), Enum.Material.Concrete)
	else
		tube(model, "Pedestal", headHeight - 0.8, 2.6, CFrame.new(center + Vector3.new(0, (headHeight - 0.8) / 2, 0)), "Y", STEEL)
	end
	local pips = (level - 1) % 3 + 1
	for index = 1, pips do
		local angle = (index - 2) * 0.5
		part(model, "Pip", Vector3.new(0.5, 0.5, 0.5), CFrame.new(center + Vector3.new(math.sin(angle) * 3.4, 0.45, math.cos(angle) * 3.4)), accent, Enum.Material.Neon, Enum.PartType.Ball)
	end
	local body: BasePart
	local muzzleOffset: Vector3
	if typeName == "Gun" then
		body = part(head, "HeadBody", Vector3.new(3, 1.8, 3.2), H, STEEL)
		for _, x in ipairs({-0.6, 0.6}) do tube(head, "Barrel", 4, 0.55, H * CFrame.new(x, 0.15, -3), "Z", DARK) end
		part(head, "Ammo", Vector3.new(1, 1.2, 1.8), H * CFrame.new(1.9, -0.2, 0.3), color)
		part(head, "Trim", Vector3.new(3.1, 0.3, 3.3), H * CFrame.new(0, 0.95, 0), accent, Enum.Material.Neon)
		muzzleOffset = Vector3.new(0, 0.15, -5)
	elseif typeName == "Flamer" then
		body = tube(head, "HeadBody", 3.6, 2.4, H, "X", color)
		tube(head, "Nozzle", 3, 0.9, H * CFrame.new(0, 0, -2.6), "Z", DARK)
		part(head, "Pilot", Vector3.new(0.6, 0.6, 0.6), H * CFrame.new(0, 0, -4.2), Color3.fromRGB(255, 170, 60), Enum.Material.Neon, Enum.PartType.Ball)
		tube(head, "Band", 0.4, 2.5, H, "X", accent, Enum.Material.Neon)
		muzzleOffset = Vector3.new(0, 0, -4.3)
	elseif typeName == "Sniper" then
		body = part(head, "HeadBody", Vector3.new(1.6, 1.4, 3), H, STEEL)
		tube(head, "Barrel", 7, 0.4, H * CFrame.new(0, 0.1, -4.8), "Z", DARK)
		tube(head, "Scope", 1.8, 0.5, H * CFrame.new(0, 1, -0.4), "Z", color)
		part(head, "Trim", Vector3.new(1.7, 0.25, 3.1), H * CFrame.new(0, 0.75, 0), accent, Enum.Material.Neon)
		muzzleOffset = Vector3.new(0, 0.1, -8.4)
	elseif typeName == "Tesla" then
		body = tube(head, "HeadBody", 4.2, 1.6, H * CFrame.new(0, 1.2, 0), "Y", STEEL)
		for index = 1, 3 do tube(head, "Coil", 0.35, 2.6, H * CFrame.new(0, 0.2 + index * 0.9, 0), "Y", accent, Enum.Material.Neon) end
		part(head, "Orb", Vector3.new(2.2, 2.2, 2.2), H * CFrame.new(0, 3.9, 0), color, Enum.Material.Neon, Enum.PartType.Ball)
		muzzleOffset = Vector3.new(0, 3.9, 0)
	else -- Mortar
		body = part(head, "HeadBody", Vector3.new(2.6, 1.2, 2.6), H, STEEL)
		local tilt = H * CFrame.Angles(math.rad(50), 0, 0)
		tube(head, "Tube", 4.2, 1.6, tilt * CFrame.new(0, 0, -1.6), "Z", DARK)
		tube(head, "Band", 0.4, 1.8, tilt * CFrame.new(0, 0, -1), "Z", accent, Enum.Material.Neon)
		muzzleOffset = (tilt * CFrame.new(0, 0, -3.7)).Position - H.Position
	end
	head.PrimaryPart = body
	local muzzle = part(head, "Muzzle", Vector3.new(0.2, 0.2, 0.2), H * CFrame.new(muzzleOffset), Color3.new(1, 1, 1))
	muzzle.Transparency = 1
	model.Parent = pad
	return model
end

function TurretVisuals.Clear(pad: Model)
	local existing = pad:FindFirstChild("Turret")
	if existing then existing:Destroy() end
end

return TurretVisuals
