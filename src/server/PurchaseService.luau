-- Validates purchase requests (remote or world prompt) and applies them through TycoonModel.
-- Ladder: rate limit -> shape -> ownership -> proximity -> model rules (price, order, caps).
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")

local PurchaseService = {}
PurchaseService.__index = PurchaseService

local RATE_LIMIT = 0.15

function PurchaseService.new(config, states, bases, production, remotes)
	return setmetatable({
		config = config, states = states, bases = bases, production = production, remotes = remotes,
		lastRequest = {}, touchTimes = {}, connections = {}, travel = nil,
	}, PurchaseService)
end

function PurchaseService:Respond(player, result, requestId)
	local payload = table.clone(result)
	if type(requestId) == "string" and #requestId <= 72 then payload.requestId = requestId end
	self.remotes.Feedback:FireClient(player, payload)
	return payload
end

-- The world object the player must stand near for this purchase.
function PurchaseService:TargetFor(base, kind, id)
	if kind == "UpgradeDropper" then
		local dropper = base.Droppers:FindFirstChild("Dropper" .. id)
		return dropper and dropper:FindFirstChild("MachineBody")
	elseif kind == "BuyDropper" then
		local pad = base.BuyPads:FindFirstChild("BuyDropper" .. id)
		return pad and pad:FindFirstChild("Pad")
	elseif kind == "BuildTurret" or kind == "UpgradeTurret" or kind == "SellTurret" or kind == "UpgradeModule" then
		local pad = base.Pads:FindFirstChild("Pad" .. id)
		return pad and pad:FindFirstChild("Plate")
	elseif kind == "ExpandBase" or kind == "UpgradeWalls" then
		return base.Combat.Console.Pad
	elseif kind == "HireEngineer" then
		return base.Combat.Workshop.Door
	elseif kind == "BuyPortal" then
		return base.Combat.Portal.Base
	elseif kind == "Overdrive" then
		return base.Production.Collector.Body
	end
	return nil
end

function PurchaseService:Handle(player, action, source)
	local requestId = if type(action) == "table" and type(action.requestId) == "string" then action.requestId else nil
	local function reject(code, message) return self:Respond(player, { ok = false, code = code, message = message }, requestId) end
	local now = os.clock()
	if now - (self.lastRequest[player] or -math.huge) < RATE_LIMIT then return reject("RateLimited", "Подожди немного перед следующей покупкой") end
	self.lastRequest[player] = now
	local state = self.states:Get(player)
	if not state or type(action) ~= "table" then return reject("InvalidRequest", "База ещё не готова") end
	if state.base:GetAttribute("OwnerUserId") ~= player.UserId then return reject("NotOwner", "Это чужая база") end
	if source and not source:IsDescendantOf(state.base) then return reject("NotOwner", "Покупки доступны только на своей базе") end
	local kind, id = action.kind, action.targetId
	if type(kind) ~= "string" or type(id) ~= "number" or id ~= id or id % 1 ~= 0 or id < 1 or id > 64 then return reject("InvalidRequest", "Неизвестная постройка") end
	local target = self:TargetFor(state.base, kind, id)
	-- Base expansion can also be bought at the factory gate it opens.
	if kind == "ExpandBase" and source and source:IsDescendantOf(state.base.Gates) then target = source end
	if not target then return reject("InvalidRequest", "Неизвестная постройка") end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 or (root.Position - target.Position).Magnitude > self.config.PurchaseDistance + target.Size.Magnitude / 2 then
		return reject("TooFar", "Подойди ближе")
	end
	-- Only known fields reach the model; prices always come from the server config.
	local clean = { kind = kind, targetId = id, requestId = requestId, expectedLevel = action.expectedLevel,
		turretType = if type(action.turretType) == "string" then action.turretType else nil,
		module = if type(action.module) == "string" then action.module else nil }
	-- Settle elapsed production once, before changing the shared balance or tariff.
	self.production:SyncTo(state, now)
	local result = state.tycoon:Apply(player.UserId, clean)
	if result.ok then
		self.production:Reconcile(state, now)
		self.states:Publish(state)
		self.bases:Refresh(state.base, state.tycoon, player.UserId)
		if self.onPurchase then self.onPurchase(player, kind) end
	end
	return self:Respond(player, result, requestId)
end

function PurchaseService:Bind()
	table.insert(self.connections, self.remotes.TycoonAction.OnServerEvent:Connect(function(player, action) self:Handle(player, action) end))
	local function guid() return HttpService:GenerateGUID(false) end
	for _, base in ipairs(self.bases.world.Bases:GetChildren()) do
		local function onPrompt(prompt, build)
			table.insert(self.connections, prompt.Triggered:Connect(function(player)
				local state = self.states:Get(player)
				if not state or state.base ~= base then return end
				local action = build(state.tycoon, player)
				if action then action.requestId = guid() self:Handle(player, action, prompt.Parent) end
			end))
		end
		local console = base.Combat.Console.Pad
		onPrompt(console.ExpandPrompt, function(t) return { kind = "ExpandBase", targetId = t.expansion + 1 } end)
		for _, gate in ipairs(base.Gates:GetChildren()) do
			local gatePrompt = gate.Door:FindFirstChild("GatePrompt")
			if gatePrompt then onPrompt(gatePrompt, function() return { kind = "ExpandBase", targetId = gate:GetAttribute("GateIndex") } end) end
		end
		local overdrive = base.Production.Collector.Body:FindFirstChild("OverdrivePrompt")
		if overdrive then onPrompt(overdrive, function() return { kind = "Overdrive", targetId = 1 } end) end
		onPrompt(console.WallsPrompt, function(t) return { kind = "UpgradeWalls", targetId = 1, expectedLevel = t.wallLevel } end)
		onPrompt(base.Combat.Workshop.Door.HirePrompt, function(t) return { kind = "HireEngineer", targetId = 1, expectedLevel = t.engineers } end)
		onPrompt(base.Combat.Portal.Base.PortalPrompt, function(t, player)
			local nextWorld = t.worldId + 1
			if t.unlockedWorld >= nextWorld then
				if self.travel then self.travel(player, nextWorld) end
				return nil
			end
			return { kind = "BuyPortal", targetId = nextWorld }
		end)
		onPrompt(base.Combat.Portal.Base.BackPrompt, function(t, player)
			if self.travel and t.worldId > 1 then self.travel(player, t.worldId - 1) end
			return nil
		end)
		for _, pad in ipairs(base.BuyPads:GetChildren()) do
			local function purchase(player)
				self:Handle(player, { kind = pad:GetAttribute("ActionKind"), targetId = pad:GetAttribute("TargetId"), requestId = guid() }, pad.Pad)
			end
			table.insert(self.connections, pad.Pad.ProximityPrompt.Triggered:Connect(purchase))
			table.insert(self.connections, pad.Pad.Touched:Connect(function(hit)
				local character = hit:FindFirstAncestorOfClass("Model")
				local player = character and Players:GetPlayerFromCharacter(character)
				if not player or pad.Pad.Transparency >= 1 then return end
				local times = self.touchTimes[player] or {}
				self.touchTimes[player] = times
				local key = pad:GetFullName()
				local now = os.clock()
				if now - (times[key] or -math.huge) < 1.2 then return end
				times[key] = now
				purchase(player)
			end))
		end
	end
end

function PurchaseService:Forget(player)
	self.lastRequest[player] = nil
	self.touchTimes[player] = nil
end

function PurchaseService:Destroy()
	for _, connection in ipairs(self.connections) do connection:Disconnect() end
	table.clear(self.connections)
end

return PurchaseService
