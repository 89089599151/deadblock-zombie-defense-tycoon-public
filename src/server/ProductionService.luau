local ProductionModel=require(script.Parent.ProductionModel)
local ProductionService={}
ProductionService.__index=ProductionService

function ProductionService.new(config,states,bases)
	return setmetatable({config=config,states=states,bases=bases},ProductionService)
end

function ProductionService:Reconcile(state,now)
	for id,level in pairs(state.tycoon.droppers) do
		local def=self.config.Droppers[id]
		local line=state.lines[id]
		if not line then
			local value=state.tycoon:GetDropperValue(id,level)
			line={model=ProductionModel.new({Interval=self.config.Production.Interval,TravelTime=def.TravelTime,Value=value}),lastUpdated=now,level=level,value=value,oreParts={}}
			state.lines[id]=line
		else
			local value=state.tycoon:GetDropperValue(id,level)
			if value~=line.value then line.model:SetValue(value) line.value=value end
			line.level=level
		end
	end
end

local function positionAt(base,def,progress)
	local drop=base.Droppers:FindFirstChild("Dropper"..def.Id)
	local fraction=0.5/def.TravelTime
	if progress<fraction then return drop.DropPoint.Position:Lerp(drop.BeltStart.Position,progress/fraction) end
	return drop.BeltStart.Position:Lerp(base.Production.BeltEnd.Position,(progress-fraction)/(1-fraction))
end

function ProductionService:SyncTo(state,now)
	local earnedTotal=0
	for id,line in pairs(state.lines) do
		local elapsed=math.max(0,now-line.lastUpdated)
		local earned,count=line.model:Advance(elapsed)
		line.lastUpdated=now
		earnedTotal+=earned state.collected+=count
		local live={}
		for _,ore in ipairs(line.model:GetActiveOres()) do
			live[ore.id]=true
			local part=line.oreParts[ore.id]
			if not part then
				part=Instance.new("Part") part.Name="D"..id.."_Ore"..ore.id
				part.Size=Vector3.new(1.5,1.5,1.5) part.Anchored=true
				part.CanCollide=false part.CanTouch=false part.CanQuery=false
				part.Material=Enum.Material.Metal
				part.Color=if ore.value>=20 then Color3.fromRGB(117,222,195) else Color3.fromRGB(255,171,64)
				part:SetAttribute("OwnerUserId",state.player.UserId) part:SetAttribute("Value",ore.value)
				part.Parent=state.base.Production.Ores line.oreParts[ore.id]=part
			end
			part.Position=positionAt(state.base,self.config.Droppers[id],ore.progress)
		end
		for oreId,part in pairs(line.oreParts) do if not live[oreId] then part:Destroy() line.oreParts[oreId]=nil end end
	end
	if earnedTotal>0 then
		state.tycoon:Credit(earnedTotal)
		self.states:Publish(state)
		self.bases:UpdateMoney(state.base,state.tycoon)
	end
	return earnedTotal
end

function ProductionService:Step(now)
	for _,state in pairs(self.states:GetAll()) do self:SyncTo(state,now) end
end
return ProductionService
