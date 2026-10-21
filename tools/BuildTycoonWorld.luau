local config=require(game.ReplicatedStorage.DeadblockShared.Config)
local old=workspace:FindFirstChild("DeadblockWorld")
if old then
	if old:GetAttribute("BuildVersion")=="tycoon-v2" then return "Existing tycoon world preserved" end
	assert(old:GetAttribute("BuildVersion")=="stage1-v1","Unknown world: refusing to replace")
	assert(game.ServerStorage:FindFirstChild("DEADBLOCK_Backup_PreTycoonProgression"),"Create backup before migrating")
	old:Destroy()
end
local world=Instance.new("Model") world.Name="DeadblockWorld" world:SetAttribute("BuildVersion","tycoon-v2")
local bases=Instance.new("Folder") bases.Name="Bases" bases.Parent=world
local palette={floor=Color3.fromRGB(78,86,89),dark=Color3.fromRGB(31,39,43),steel=Color3.fromRGB(100,119,125),orange=Color3.fromRGB(237,159,65),mint=Color3.fromRGB(111,226,173),white=Color3.fromRGB(232,239,230)}
local function model(name,parent)
	local m=Instance.new("Model") m.Name=name m.Parent=parent return m
end
local function folder(name,parent)
	local f=Instance.new("Folder") f.Name=name f.Parent=parent return f
end
local function part(name,size,position,color,parent,material,solid)
	local p=Instance.new("Part") p.Name=name p.Size=size p.Position=position p.Color=color p.Anchored=true
	p.Material=material or Enum.Material.SmoothPlastic p.TopSurface=Enum.SurfaceType.Smooth p.BottomSurface=Enum.SurfaceType.Smooth
	p.CanCollide=solid==true p:SetAttribute("Solid",solid==true) p:SetAttribute("OriginalTransparency",0)
	p.Parent=parent return p
end
local function marker(name,pos,parent)
	local p=part(name,Vector3.one,pos,palette.white,parent)
	p.Transparency=1 p:SetAttribute("OriginalTransparency",1) p.CanTouch=false p.CanQuery=false return p
end
local function text(parent,name,content,pos,size,color,fontSize)
	local t=Instance.new("TextLabel") t.Name=name t.Text=content t.Position=pos t.Size=size t.BackgroundTransparency=1
	t.Font=Enum.Font.GothamBold t.TextColor3=color t.TextSize=fontSize t.TextWrapped=true t.Parent=parent return t
end
local function billboard(adornee,title,maxDistance)
	local gui=Instance.new("BillboardGui") gui.Name="Info" gui.Size=UDim2.fromOffset(200,60) gui.StudsOffset=Vector3.new(0,4,0)
	gui.MaxDistance=maxDistance or 65 gui.AlwaysOnTop=false gui.Parent=adornee
	local label=text(gui,"Label",title,UDim2.fromScale(0,0),UDim2.fromScale(1,1),palette.white,19)
	label.TextStrokeTransparency=0.35
	return gui
end
local function prompt(parent,kind,id,action,name)
	local p=Instance.new("ProximityPrompt") p.Name="ProximityPrompt" p.ActionText=action p.ObjectText=name
	p.MaxActivationDistance=11 p.RequiresLineOfSight=false p.HoldDuration=0.1 p:SetAttribute("ActionKind",kind)
	p:SetAttribute("DropperId",id) p.Parent=parent return p
end
for id=1,config.PlotCount do
	local origin=Vector3.new(if id==1 then -1250 else 1250,0,0)
	local base=model("Base"..id,bases) base:SetAttribute("BaseId",id) base:SetAttribute("OwnerUserId",0)
	local environment=folder("Location",base)
	part("ForestGround",Vector3.new(240,1,280),origin+Vector3.new(0,-0.5,-25),Color3.fromRGB(66,89,63),environment,Enum.Material.Grass,true)
	local random=Random.new(3100+id)
	for rockId=1,15 do
		local angle=rockId*math.pi*2/15
		local position=origin+Vector3.new(math.cos(angle)*100,random:NextNumber(18,24),math.sin(angle)*120-25)
		local rock=part("Cliff"..rockId,Vector3.new(random:NextNumber(35,50),random:NextNumber(48,62),random:NextNumber(35,50)),position,Color3.fromRGB(91,99,88),environment,Enum.Material.Rock,true)
		rock.CFrame=CFrame.new(position)*CFrame.Angles(random:NextNumber(-0.15,0.15),angle,random:NextNumber(-0.1,0.1))
	end
	for treeId=1,28 do
		local angle=treeId*math.pi*2/28
		local position=origin+Vector3.new(math.cos(angle)*random:NextNumber(66,86),0,math.sin(angle)*random:NextNumber(88,105)-25)
		local tree=model("Tree"..treeId,environment)
		local height=random:NextNumber(12,20)
		part("Trunk",Vector3.new(2,height,2),position+Vector3.new(0,height/2,0),Color3.fromRGB(87,71,48),tree,Enum.Material.Wood,true)
		for layer=1,3 do
			local width=14-layer*2
			local leaves=part("Crown",Vector3.new(width,10,width),position+Vector3.new(0,height-4+layer*4,0),Color3.fromRGB(35+layer*7,73+layer*5,49+layer*5),tree,Enum.Material.Grass)
			leaves.Shape=Enum.PartType.Ball
		end
	end
	local zones=folder("Zones",base)
	for zoneId=0,2 do
		local zone=model("Zone"..zoneId,zones) zone:SetAttribute("ZoneIndex",zoneId)
		local z=20-zoneId*40
		part("Foundation",Vector3.new(56,1,40),origin+Vector3.new(0,0.5,z),palette.floor,zone,Enum.Material.Concrete,true)
		for _,x in ipairs({-28,28}) do
			part("Edge",Vector3.new(0.5,0.18,40),origin+Vector3.new(x,1.1,z),palette.orange,zone)
			part("FenceRail",Vector3.new(0.4,0.4,40),origin+Vector3.new(x,3.2,z),palette.steel,zone,Enum.Material.Metal,true)
			for offset=-18,18,12 do part("FencePost",Vector3.new(0.65,3.6,0.65),origin+Vector3.new(x,2.8,z+offset),palette.dark,zone,Enum.Material.Metal,true) end
		end
		local length=if zoneId==0 then 34 else 40
		local centre=if zoneId==0 then 17 else z
		part("Conveyor",Vector3.new(6,0.5,length),origin+Vector3.new(0,1.75,centre),palette.dark,zone,Enum.Material.Rubber,true)
		for _,x in ipairs({-3.4,3.4}) do part("BeltRail",Vector3.new(0.45,0.5,length),origin+Vector3.new(x,2,centre),palette.steel,zone,Enum.Material.Metal) end
		for offset=-length/2+1,length/2-1,3 do part("BeltTread",Vector3.new(5.8,0.08,0.2),origin+Vector3.new(0,2.04,centre+offset),palette.steel,zone) end
	end
	local spawn=marker("SpawnPoint",origin+Vector3.new(13,4.5,31),base)
	spawn.CFrame=CFrame.lookAt(spawn.Position,origin+Vector3.new(1,4.5,10))
	local sign=model("Sign",base)
	local board=part("Board",Vector3.new(22,6,0.6),origin+Vector3.new(-15,5.8,38),palette.dark,sign,Enum.Material.Metal,true)
	board.CFrame=CFrame.new(board.Position)*CFrame.Angles(0,math.pi,0)
	local sg=Instance.new("SurfaceGui") sg.Name="SurfaceGui" sg.CanvasSize=Vector2.new(1000,300) sg.LightInfluence=0 sg.Parent=board
	text(sg,"Title","DEADBLOCK / ЛИЧНАЯ БАЗА",UDim2.fromScale(0.04,0.03),UDim2.fromScale(0.92,0.25),palette.orange,40)
	text(sg,"Owner","СВОБОДНАЯ БАЗА",UDim2.fromScale(0.04,0.32),UDim2.fromScale(0.92,0.25),palette.white,38)
	text(sg,"Status","ОЖИДАНИЕ ИГРОКА",UDim2.fromScale(0.04,0.7),UDim2.fromScale(0.92,0.2),palette.mint,26)
	local production=model("Production",base) folder("Ores",production)
	marker("BeltEnd",origin+Vector3.new(0,2.8,34),production)
	local collector=model("Collector",production)
	part("Body",Vector3.new(9,3,6),origin+Vector3.new(0,2.5,36),palette.dark,collector,Enum.Material.Metal,true)
	part("Intake",Vector3.new(6.2,2,0.25),origin+Vector3.new(0,2.7,33),palette.mint,collector,Enum.Material.Neon)
	local display=part("Display",Vector3.new(8,2.5,0.3),origin+Vector3.new(0,4.7,39.1),palette.dark,collector)
	display.CFrame=CFrame.new(display.Position)*CFrame.Angles(0,math.pi,0)
	local money=Instance.new("SurfaceGui") money.Name="SurfaceGui" money.CanvasSize=Vector2.new(800,240) money.LightInfluence=0 money.Parent=display
	text(money,"Amount","$ 0",UDim2.fromScale(0.03,0.05),UDim2.fromScale(0.94,0.8),palette.mint,105)
	local droppers=folder("Droppers",base)
	local pads=folder("BuyPads",base)
	local function buyPad(kind,targetId,price,title,position)
		local m=model(kind..targetId,pads) m:SetAttribute("ActionKind",kind) m:SetAttribute("TargetId",targetId) m:SetAttribute("Price",price)
		local p=part("Pad",Vector3.new(8,0.3,7),origin+position,Color3.fromRGB(210,115,70),m,Enum.Material.Neon,true)
		billboard(p,title.."\n$ "..price,55).StudsOffset=Vector3.new(0,3,0)
		prompt(p,kind,targetId,"Купить · $ "..price,title)
	end
	for dropperId,def in ipairs(config.Droppers) do
		local m=model("Dropper"..dropperId,droppers) m:SetAttribute("DropperId",dropperId)
		local body=part("MachineBody",Vector3.new(8,6,7),origin+Vector3.new(-10,5,def.Z),palette.steel,m,Enum.Material.Metal,true)
		part("Housing",Vector3.new(6,1.2,6),origin+Vector3.new(-10,8.5,def.Z),palette.dark,m,Enum.Material.Metal,true)
		part("LightStrip",Vector3.new(6,0.5,0.15),origin+Vector3.new(-10,6.4,def.Z+3.6),palette.orange,m,Enum.Material.Neon)
		part("TransferPipe",Vector3.new(8,1,1.5),origin+Vector3.new(-4,6,def.Z),palette.steel,m,Enum.Material.Metal)
		part("Nozzle",Vector3.new(2,1.5,2),origin+Vector3.new(0,5.3,def.Z),palette.dark,m,Enum.Material.Metal)
		marker("DropPoint",origin+Vector3.new(0,4.5,def.Z),m)
		marker("BeltStart",origin+Vector3.new(0,2.8,def.Z),m)
		billboard(body,def.Name,55)
		prompt(body,"InspectDropper",dropperId,"Улучшить",def.Name)
		if dropperId>1 then buyPad("BuyDropper",dropperId,def.Price,def.Name,Vector3.new(-20,1.3,def.Z)) end
	end
	for expansionId,def in ipairs(config.Expansions) do buyPad("ExpandBase",expansionId,def.Price,"Расширить базу "..expansionId,Vector3.new(20,1.3,if expansionId==1 then 4 else -36)) end
	base.Parent=bases
	task.wait()
end
world.Parent=workspace
local baseService=require(game.ServerScriptService.Deadblock.BaseService).new(world,config)
for _,base in ipairs(bases:GetChildren()) do baseService:Refresh(base,require(game.ServerScriptService.Deadblock.TycoonModel).new(config,0),0) end
local starter=game:GetService("StarterPlayer") starter.CameraMaxZoomDistance=80 starter.CameraMinZoomDistance=5 starter.DevCameraOcclusionMode=Enum.DevCameraOcclusionMode.Zoom
local lighting=game:GetService("Lighting") lighting.ClockTime=14.7 lighting.Brightness=2.5 lighting.Ambient=Color3.fromRGB(127,143,138) lighting.OutdoorAmbient=Color3.fromRGB(133,145,144)
lighting.FogColor=Color3.fromRGB(142,167,166) lighting.FogStart=130 lighting.FogEnd=420
local atmosphere=lighting:FindFirstChildOfClass("Atmosphere")
if atmosphere then atmosphere.Density=0.28 atmosphere.Haze=1.5 end
workspace.CurrentCamera.CFrame=CFrame.lookAt(Vector3.new(-1200,50,72),Vector3.new(-1250,3,-15))
return {world=world:GetFullName(),bases=#bases:GetChildren(),descendants=#world:GetDescendants(),distance=2500}
