-- Edit-mode, repeat-safe scene assembly. Does not replace existing user content.
local existing = workspace:FindFirstChild("DeadblockWorld")
if existing then return "DeadblockWorld already exists; scene preserved" end

local world = Instance.new("Model")
world.Name = "DeadblockWorld"
world:SetAttribute("BuildVersion", "stage1-v1")
local colors = {
	Floor = Color3.fromRGB(47, 56, 65), Trim = Color3.fromRGB(24, 31, 40),
	Metal = Color3.fromRGB(79, 91, 103), Orange = Color3.fromRGB(255, 145, 57),
	Mint = Color3.fromRGB(102, 239, 192), White = Color3.fromRGB(231, 238, 243),
}
local function group(name, parent)
	local model = Instance.new("Model") model.Name = name model.Parent = parent return model
end
local function part(name, size, position, color, parent, material)
	local p = Instance.new("Part")
	p.Name, p.Size, p.Position, p.Color = name, size, position, color
	p.Anchored = true
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.Material = material or Enum.Material.SmoothPlastic
	p.Parent = parent
	return p
end
local function label(parent, name, text, position, size, color, textSize)
	local t = Instance.new("TextLabel")
	t.Name, t.Text, t.Position, t.Size = name, text, position, size
	t.BackgroundTransparency, t.TextColor3, t.TextSize = 1, color, textSize
	t.Font = Enum.Font.GothamBold
	t.TextWrapped = true
	t.Parent = parent
	return t
end
local function surface(board)
	local gui = Instance.new("SurfaceGui")
	gui.Face, gui.CanvasSize, gui.LightInfluence = Enum.NormalId.Front, Vector2.new(900, 340), 0
	gui.Parent = board return gui
end
local bases = Instance.new("Folder") bases.Name = "Bases" bases.Parent = world
for id = 1, 2 do
	local origin = Vector3.new(if id == 1 then -72 else 72, 0, -35)
	local base = group("Base" .. id, bases)
	base:SetAttribute("BaseId", id) base:SetAttribute("OwnerUserId", 0)
	part("Foundation", Vector3.new(88,1,70), origin + Vector3.new(0,0.5,0), colors.Floor, base, Enum.Material.Concrete)
	for _, z in ipairs({-34.5,34.5}) do
		part("Perimeter", Vector3.new(88,0.3,0.5), origin + Vector3.new(0,1.15,z), colors.Orange, base)
	end
	for _, x in ipairs({-43.5,43.5}) do
		part("Perimeter", Vector3.new(0.5,0.3,69), origin + Vector3.new(x,1.15,0), colors.Orange, base)
	end
	local spawn = part("SpawnPoint", Vector3.new(4,0.2,4), origin + Vector3.new(0,5,24), colors.Mint, base)
	spawn.Transparency = 1 spawn.CanCollide = false spawn.CanQuery = false
	local sign = group("Sign", base)
	local board = part("Board", Vector3.new(26,8,1), origin + Vector3.new(0,9,-32), colors.Trim, sign)
	local signGui = surface(board)
	label(signGui,"Title","DEADBLOCK  /  0" .. id,UDim2.fromScale(0.05,0.03),UDim2.fromScale(0.9,0.25),colors.Orange,42)
	label(signGui,"Owner","СВОБОДНАЯ БАЗА",UDim2.fromScale(0.05,0.32),UDim2.fromScale(0.9,0.3),colors.White,38)
	label(signGui,"Status","ОЖИДАНИЕ ИГРОКА",UDim2.fromScale(0.05,0.7),UDim2.fromScale(0.9,0.18),colors.Mint,24)
	for _, x in ipairs({-11,11}) do part("SignLeg",Vector3.new(0.7,7,0.7),origin+Vector3.new(x,4,-32),colors.Metal,sign) end
	-- The front of SurfaceGui faces +Z here, towards the arriving player.
	board.CFrame = CFrame.new(board.Position) * CFrame.Angles(0,math.pi,0)
	local production = group("Production",base)
	local ores = Instance.new("Folder") ores.Name="Ores" ores.Parent=production
	local dropper = group("Dropper",production)
	part("MachineBody",Vector3.new(8,5,8),origin+Vector3.new(-29,8,-8),colors.Metal,dropper,Enum.Material.Metal)
	part("Panel",Vector3.new(5,2,0.25),origin+Vector3.new(-29,8.5,-3.85),colors.Orange,dropper)
	part("Nozzle",Vector3.new(2.5,1.2,2.5),origin+Vector3.new(-27,5.1,-8),colors.Trim,dropper,Enum.Material.Metal)
	for _, x in ipairs({-32,-25}) do
		for _, z in ipairs({-11,-5}) do part("Leg",Vector3.new(0.8,5,0.8),origin+Vector3.new(x,3.5,z),colors.Trim,dropper) end
	end
	local conveyor = group("Conveyor",production)
	part("Belt",Vector3.new(34,0.6,5),origin+Vector3.new(-11,1.8,-8),colors.Trim,conveyor,Enum.Material.Rubber)
	for _, z in ipairs({-10.8,-5.2}) do part("Rail",Vector3.new(34,0.45,0.45),origin+Vector3.new(-11,2.3,z),colors.Metal,conveyor,Enum.Material.Metal) end
	for x = -26, 4, 4 do
		part("Tread",Vector3.new(0.22,0.06,4.8),origin+Vector3.new(x,2.13,-8),colors.Metal,conveyor)
	end
	for _, def in ipairs({{"DropPoint",Vector3.new(-27,4.3,-8)},{"BeltStart",Vector3.new(-27,2.95,-8)},{"BeltEnd",Vector3.new(7,2.95,-8)}}) do
		local marker=part(def[1],Vector3.one,origin+def[2],colors.White,production)
		marker.Transparency=1 marker.CanCollide=false marker.CanTouch=false marker.CanQuery=false
	end
	local collector=group("Collector",production)
	part("Body",Vector3.new(6,3,8),origin+Vector3.new(10,2.5,-8),colors.Trim,collector,Enum.Material.Metal)
	part("Intake",Vector3.new(0.3,2.5,5.2),origin+Vector3.new(6.9,2.7,-8),colors.Mint,collector,Enum.Material.Neon).CanCollide=false
	local display=part("Display",Vector3.new(8,3,0.5),origin+Vector3.new(10,5,-4),colors.Trim,collector)
	display.CFrame=CFrame.new(display.Position)*CFrame.Angles(0,math.pi,0)
	local cashGui=surface(display)
	label(cashGui,"Amount","$ 0",UDim2.fromScale(0.05,0.1),UDim2.fromScale(0.9,0.6),colors.Mint,100)
	label(cashGui,"Caption","ПРИЁМНИК",UDim2.fromScale(0.05,0.73),UDim2.fromScale(0.9,0.2),colors.White,28)
	local slots=Instance.new("Folder") slots.Name="BuildSlots" slots.Parent=base
	for index, position in ipairs({Vector3.new(-28,1.1,12),Vector3.new(13,1.1,20),Vector3.new(35,1.1,20),Vector3.new(13,1.1,-16),Vector3.new(35,1.1,-16)}) do
		local slot=part(if index==1 then "MachineSlot2" else "TurretSlot" .. (index-1),Vector3.new(7,0.15,7),origin+position,colors.Metal,slots)
		slot.Material=Enum.Material.DiamondPlate
	end
	local route=part("ReservedZombieRoute",Vector3.new(7,0.08,48),origin+Vector3.new(23,1.1,-5),Color3.fromRGB(68,73,81),base)
	route:SetAttribute("ReservedForFutureWaves",true)
	local core=group("Core",base)
	part("Plinth",Vector3.new(8,1.2,8),origin+Vector3.new(23,1.7,-27),colors.Trim,core,Enum.Material.Metal)
	part("PowerCell",Vector3.new(3,5,3),origin+Vector3.new(23,4.8,-27),colors.Mint,core,Enum.Material.Neon)
	for _, x in ipairs({20,26}) do part("Brace",Vector3.new(0.7,5,5),origin+Vector3.new(x,4.3,-27),colors.Metal,core) end
end
world.Parent=workspace
local lighting=game:GetService("Lighting")
lighting.ClockTime=14
lighting.Brightness=2
lighting.Ambient=Color3.fromRGB(115,126,143)
workspace.CurrentCamera.CFrame=CFrame.lookAt(Vector3.new(0,125,155),Vector3.new(0,0,-35))
return {world=world:GetFullName(),bases=#bases:GetChildren(),parts=#world:GetDescendants()}
