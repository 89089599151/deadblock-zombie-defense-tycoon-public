-- Server-only session state. Never accept money or ownership from a client.
local TycoonModel = require(script.Parent.TycoonModel)
local PlayerStateService = {}
PlayerStateService.__index = PlayerStateService

function PlayerStateService.new(config)
	return setmetatable({ config = config, states = {} }, PlayerStateService)
end

function PlayerStateService:Create(player, base, tycoon)
	assert(not self.states[player], "Player already has a session")
	local state = {
		player = player, base = base, tycoon=tycoon or TycoonModel.new(self.config,player.UserId), lines={},collected=0,
	}
	self.states[player] = state
	self:Publish(state)
	player:SetAttribute("DeadblockBaseId", base:GetAttribute("BaseId"))
	player:SetAttribute("DeadblockStatus", "ready")
	return state
end

function PlayerStateService:Publish(state)
	local count=0 for _ in pairs(state.tycoon.droppers) do count+=1 end
	state.player:SetAttribute("DeadblockMoney",state.tycoon.money)
	state.player:SetAttribute("DeadblockIncome",state.tycoon:GetIncomePerSecond())
	state.player:SetAttribute("DeadblockDropperCount",count)
	state.player:SetAttribute("DeadblockExpansion",state.tycoon.expansion)
	state.player:SetAttribute("DeadblockBaseLevel",state.tycoon:GetBaseLevel())
	state.player:SetAttribute("DeadblockLevelCap",state.tycoon:GetLevelCap())
	state.player:SetAttribute("DeadblockWallLevel",state.tycoon.wallLevel)
	state.player:SetAttribute("DeadblockEngineers",state.tycoon.engineers)
	state.player:SetAttribute("DeadblockUnlockedWorld",state.tycoon.unlockedWorld)
	state.player:SetAttribute("DeadblockCores",state.tycoon.cores)
	state.player:SetAttribute("DeadblockOverdrive",state.tycoon:OverdriveLeft())
end

function PlayerStateService:Get(player)
	return self.states[player]
end

function PlayerStateService:GetAll()
	return self.states
end

function PlayerStateService:Remove(player)
	local state = self.states[player]
	if not state then return end
	self.states[player] = nil
	for _, line in pairs(state.lines) do for _,part in pairs(line.oreParts) do part:Destroy() end end
	player:SetAttribute("DeadblockBaseId", nil)
	player:SetAttribute("DeadblockMoney", nil)
	player:SetAttribute("DeadblockIncome", nil)
	player:SetAttribute("DeadblockDropperCount",nil)
	for _, key in ipairs({"DeadblockExpansion","DeadblockBaseLevel","DeadblockLevelCap","DeadblockWallLevel","DeadblockEngineers","DeadblockUnlockedWorld","DeadblockCores","DeadblockOverdrive"}) do
		player:SetAttribute(key, nil)
	end
	player:SetAttribute("DeadblockStatus", "loading")
end

return PlayerStateService
