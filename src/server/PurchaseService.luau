local Players=game:GetService("Players")
local HttpService=game:GetService("HttpService")
local PurchaseService={}
PurchaseService.__index=PurchaseService

function PurchaseService.new(config,states,bases,production,remotes)
	return setmetatable({config=config,states=states,bases=bases,production=production,remotes=remotes,lastRequest={},touchTimes={},connections={}},PurchaseService)
end

function PurchaseService:Respond(player,result,requestId)
	local payload=table.clone(result)
	if type(requestId)=="string" and #requestId<=72 then payload.requestId=requestId end
	self.remotes.Feedback:FireClient(player,payload)
	return payload
end

function PurchaseService:Handle(player,action,source)
	local requestId=type(action)=="table" and action.requestId or nil
	local function reject(code,message) return self:Respond(player,{ok=false,code=code,message=message},requestId) end
	local now=os.clock()
	if now-(self.lastRequest[player] or -math.huge)<0.2 then return reject("RateLimited","Подождите немного перед следующей покупкой") end
	self.lastRequest[player]=now
	local state=self.states:Get(player)
	if not state or type(action)~="table" then return reject("InvalidRequest","База ещё не готова") end
	if state.base:GetAttribute("OwnerUserId")~=player.UserId then return reject("NotOwner","Это чужая база") end
	if source and not source:IsDescendantOf(state.base) then return reject("NotOwner","Покупки доступны только на своей базе") end
	local id=action.targetId
	if type(id)~="number" or id~=id or id%1~=0 or id<1 or id>6 then return reject("InvalidRequest","Неизвестная постройка") end
	local target
	if action.kind=="UpgradeDropper" then
		local dropper=state.base.Droppers:FindFirstChild("Dropper"..id)
		target=dropper and dropper:FindFirstChild("MachineBody")
	elseif action.kind=="BuyDropper" or action.kind=="ExpandBase" then
		local pad=state.base.BuyPads:FindFirstChild(action.kind..id)
		target=pad and pad:FindFirstChild("Pad")
	else return reject("InvalidRequest","Неизвестное действие") end
	local character=player.Character
	local root=character and character:FindFirstChild("HumanoidRootPart")
	local humanoid=character and character:FindFirstChildOfClass("Humanoid")
	if not target or not root or not humanoid or humanoid.Health<=0 or (root.Position-target.Position).Magnitude>self.config.PurchaseDistance then
		return reject("TooFar","Подойдите ближе к площадке или дропперу")
	end
	-- Settle elapsed production once, before changing the shared balance or tariff.
	self.production:SyncTo(state,now)
	local result=state.tycoon:Apply(player.UserId,action)
	if result.ok then
		self.production:Reconcile(state,now)
		self.states:Publish(state)
		self.bases:Refresh(state.base,state.tycoon,player.UserId)
	end
	return self:Respond(player,result,requestId)
end

function PurchaseService:Bind()
	table.insert(self.connections,self.remotes.TycoonAction.OnServerEvent:Connect(function(player,action) self:Handle(player,action) end))
	for _,base in ipairs(self.bases.world.Bases:GetChildren()) do
		for _,pad in ipairs(base.BuyPads:GetChildren()) do
			local function purchase(player)
				self:Handle(player,{kind=pad:GetAttribute("ActionKind"),targetId=pad:GetAttribute("TargetId"),requestId=HttpService:GenerateGUID(false)},pad.Pad)
			end
			table.insert(self.connections,pad.Pad.ProximityPrompt.Triggered:Connect(purchase))
			table.insert(self.connections,pad.Pad.Touched:Connect(function(hit)
				local character=hit:FindFirstAncestorOfClass("Model")
				local player=character and Players:GetPlayerFromCharacter(character)
				if not player or pad.Pad.Transparency>=1 then return end
				local times=self.touchTimes[player] or {} self.touchTimes[player]=times
				local key=pad:GetFullName() local now=os.clock()
				if now-(times[key] or -math.huge)<1.2 then return end
				times[key]=now purchase(player)
			end))
		end
	end
end

function PurchaseService:Forget(player)
	self.lastRequest[player]=nil self.touchTimes[player]=nil
end

function PurchaseService:Destroy()
	for _,connection in ipairs(self.connections) do connection:Disconnect() end
	table.clear(self.connections)
end
return PurchaseService
