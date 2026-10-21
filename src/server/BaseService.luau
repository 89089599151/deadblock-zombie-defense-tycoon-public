local PlotRegistry=require(script.Parent.PlotRegistry)
local TycoonModel=require(script.Parent.TycoonModel)
local BaseService={}
BaseService.__index=BaseService

function BaseService.new(world,config)
	return setmetatable({world=world,config=config,registry=PlotRegistry.new(config.PlotCount)},BaseService)
end

local function show(container,visible,ghost)
	for _,obj in ipairs(container:GetDescendants()) do
		if obj:IsA("BasePart") then
			local original=obj:GetAttribute("OriginalTransparency") or 0
			obj.Transparency=if visible then math.max(original,ghost and 0.8 or 0) else 1
			obj.CanCollide=visible and not ghost and obj:GetAttribute("Solid")==true
		elseif obj:IsA("SurfaceGui") or obj:IsA("BillboardGui") then obj.Enabled=visible and not ghost
		elseif obj:IsA("ProximityPrompt") then obj.Enabled=visible and not ghost end
	end
end

function BaseService:Assign(player)
	local id=self.registry:Claim(player.UserId) if not id then return nil end
	local base=self.world.Bases:FindFirstChild("Base"..id) assert(base,"Missing base")
	base:SetAttribute("OwnerUserId",player.UserId)
	base.Sign.Board.SurfaceGui.Owner.Text=player.DisplayName
	return base
end

function BaseService:GetOwned(player)
	local id=self.registry:Get(player.UserId)
	return id and self.world.Bases:FindFirstChild("Base"..id) or nil
end

function BaseService:UpdateMoney(base,tycoon)
	base.Production.Collector.Display.SurfaceGui.Amount.Text="$ "..tycoon.money
	for _,pad in ipairs(base.BuyPads:GetChildren()) do
		local cost=pad:GetAttribute("Price") or 0
		pad.Pad.Color=if tycoon.money>=cost then Color3.fromRGB(90,213,160) else Color3.fromRGB(210,115,70)
	end
end

function BaseService:Refresh(base,tycoon,ownerId)
	base:SetAttribute("Expansion",tycoon.expansion)
	for _,zone in ipairs(base.Zones:GetChildren()) do show(zone,zone:GetAttribute("ZoneIndex")<=tycoon.expansion) end
	for id,def in ipairs(self.config.Droppers) do
		local model=base.Droppers:FindFirstChild("Dropper"..id)
		local level=tycoon.droppers[id]
		local available=def.RequiredExpansion<=tycoon.expansion and (not def.Prerequisite or tycoon.droppers[def.Prerequisite]~=nil)
		show(model,level~=nil or available,level==nil)
		model:SetAttribute("Owned",level~=nil) model:SetAttribute("OwnerUserId",ownerId)
		model:SetAttribute("Level",level or 0) model:SetAttribute("Value",level and def.Levels[level].Value or 0)
		model:SetAttribute("UpgradeCost",level and def.Levels[level+1] and def.Levels[level+1].Cost or 0)
		model:SetAttribute("MaxLevel",#def.Levels)
		if level then
			model.MachineBody.Color=if level==3 then Color3.fromRGB(91,167,154) elseif level==2 then Color3.fromRGB(78,122,149) else Color3.fromRGB(73,85,98)
			model.MachineBody.Info.Label.Text=def.Name.."  ·  "..level.."/3\n$ "..def.Levels[level].Value.." за блок"
		end
		local pad=base.BuyPads:FindFirstChild("BuyDropper"..id)
		if pad then show(pad,level==nil and available and ownerId~=0) end
	end
	for id,def in ipairs(self.config.Expansions) do
		show(base.BuyPads:FindFirstChild("ExpandBase"..id),ownerId~=0 and tycoon.expansion==id-1 and tycoon.droppers[def.Prerequisite]~=nil)
	end
	local count=0 for _ in pairs(tycoon.droppers) do count+=1 end
	base.Sign.Board.SurfaceGui.Status.Text=if ownerId==0 then "ОЖИДАНИЕ ИГРОКА" else "ДРОППЕРЫ "..count.."/6  ·  УЧАСТОК "..(tycoon.expansion+1).."/3"
	self:UpdateMoney(base,tycoon)
end

function BaseService:Release(player)
	local id=self.registry:Release(player.UserId) if not id then return end
	local base=self.world.Bases:FindFirstChild("Base"..id) if not base then return end
	base:SetAttribute("OwnerUserId",0)
	base.Sign.Board.SurfaceGui.Owner.Text="СВОБОДНАЯ БАЗА"
	base.Production.Ores:ClearAllChildren()
	self:Refresh(base,TycoonModel.new(self.config,0),0)
end
return BaseService
