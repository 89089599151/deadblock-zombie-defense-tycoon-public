local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Config = require(game:GetService("ReplicatedStorage"):WaitForChild("DeadblockShared"):WaitForChild("Config"))
local root = script.Parent
local PlayerStateService = require(root.PlayerStateService)
local BaseService = require(root.BaseService)
local ProductionService = require(root.ProductionService)
local PurchaseService = require(root.PurchaseService)
local world = workspace:WaitForChild("DeadblockWorld")
local states = PlayerStateService.new(Config)
local bases = BaseService.new(world, Config)
local production = ProductionService.new(Config, states,bases)
local purchases=PurchaseService.new(Config,states,bases,production,game.ReplicatedStorage:WaitForChild("DeadblockRemotes"))
local characterConnections = {}

local function positionCharacter(player, character)
	local base = bases:GetOwned(player)
	if not base then return end
	local humanoidRoot = character:WaitForChild("HumanoidRootPart", 10)
	if humanoidRoot and player.Character == character and bases:GetOwned(player) == base then
		character:PivotTo(base.SpawnPoint.CFrame)
	end
end

local function joined(player)
	if states:Get(player) or characterConnections[player] then return end
	player:SetAttribute("DeadblockStatus", "loading")
	local base = bases:Assign(player)
	if not base then
		player:SetAttribute("DeadblockStatus", "full")
		return
	end
	local state=states:Create(player, base)
	bases:Refresh(base,state.tycoon,player.UserId)
	production:Reconcile(state,os.clock())
	player.CameraMaxZoomDistance=80
	characterConnections[player] = player.CharacterAdded:Connect(function(character)
		positionCharacter(player, character)
	end)
	if player.Character then task.spawn(positionCharacter, player, player.Character) end
end

local function leaving(player)
	local connection = characterConnections[player]
	if connection then connection:Disconnect() characterConnections[player] = nil end
	states:Remove(player)
	bases:Release(player)
	purchases:Forget(player)
	-- A waiting player can take the released plot without rejoining.
	for _, waiting in ipairs(Players:GetPlayers()) do
		if waiting ~= player and waiting:GetAttribute("DeadblockStatus") == "full" then
			joined(waiting)
		end
	end
end

Players.PlayerAdded:Connect(joined)
Players.PlayerRemoving:Connect(leaving)
purchases:Bind()
for _, player in ipairs(Players:GetPlayers()) do joined(player) end
local accumulated = 0
RunService.Heartbeat:Connect(function(dt)
	accumulated += dt
	if accumulated < Config.ServerStep then return end
	production:Step(os.clock())
	accumulated = 0
end)
game:BindToClose(function()
	purchases:Destroy()
	for _, player in ipairs(Players:GetPlayers()) do
		local connection = characterConnections[player]
		if connection then connection:Disconnect() end
		states:Remove(player)
		bases:Release(player)
	end
end)
print("[DEADBLOCK] Tycoon ready: isolated bases, dropper purchases, fair upgrades and land expansion")
