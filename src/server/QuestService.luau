-- Drives the tutorial chain: checks progress twice a second, pays rewards, publishes the current step
-- for the HUD and guide beacon, and records the onboarding funnel in Roblox analytics.
local AnalyticsService = game:GetService("AnalyticsService")
local HttpService = game:GetService("HttpService")
local QuestRules = require(script.Parent.QuestRules)
local DailyModel = require(script.Parent.DailyModel)

local QuestService = {}
QuestService.__index = QuestService

local CHECK_INTERVAL = 0.5

function QuestService.new(config, states, siege, bases, remotes)
	return setmetatable({ config = config, states = states, siege = siege, bases = bases, remotes = remotes, lastCheck = 0 }, QuestService)
end

local function logFunnel(player: Player, step: number, name: string)
	pcall(function() AnalyticsService:LogOnboardingFunnelStepEvent(player, step, name) end)
end

function QuestService:Publish(player: Player, state)
	local tycoon = state.tycoon
	local session = self.siege.sessions[player]
	local info = {
		state = if session then session.model:GetState() else "Preparing",
		best = if session then session.model:GetBestWave() else 0,
		attackDirection = if session then session.model:GetAttackDirections()[1] else nil,
	}
	local definition = QuestRules.Current(self.config, tycoon)
	local values = {
		DeadblockQuestIndex = tycoon.tutorial, DeadblockQuestTotal = #self.config.Tutorial,
		DeadblockQuestText = if definition then definition.Text else nil,
		DeadblockQuestReward = if definition then definition.Reward else nil,
		DeadblockQuestTarget = QuestRules.Target(definition, tycoon, info),
	}
	for key, value in pairs(values) do
		if player:GetAttribute(key) ~= value then player:SetAttribute(key, value) end
	end
	return definition, info
end

function QuestService:CheckPlayer(player: Player, state)
	local definition, info = self:Publish(player, state)
	if not definition or not QuestRules.IsDone(definition.Id, state.tycoon, info) then return end
	local tycoon = state.tycoon
	if definition.Reward > 0 then tycoon:Credit(definition.Reward) end
	tycoon.tutorial += 1
	logFunnel(player, tycoon.tutorial - 1, definition.Id)
	self.states:Publish(state)
	self.bases:UpdateMoney(state.base, tycoon)
	local reward = if definition.Reward > 0 then "  + $ " .. definition.Reward else ""
	self.remotes.Feedback:FireClient(player, { ok = true, code = "quest", message = "Задание выполнено!" .. reward })
	self.remotes.SiegeEvents:FireClient(player, { { "quest" } })
	self:Publish(player, state)
end

local function today(): number
	return os.time() // 86400
end

-- Grants a daily reward (money scales with the current world) and tells the player.
function QuestService:Grant(player: Player, state, reward, prefix: string)
	local money = math.floor(reward.money * self.config.Worlds[state.tycoon.worldId].RewardMultiplier)
	state.tycoon:Credit(money)
	state.tycoon:CreditCores(reward.cores)
	self.states:Publish(state)
	self.bases:UpdateMoney(state.base, state.tycoon)
	self.remotes.Feedback:FireClient(player, { ok = true, code = "daily", message = string.format("%s: %s  + $ %d · + %d ядер", prefix, reward.text, money, reward.cores) })
	self.remotes.SiegeEvents:FireClient(player, { { "quest" } })
end

function QuestService:PublishDaily(player: Player, state)
	local daily = state.tycoon.daily
	local encoded = HttpService:JSONEncode({ streak = daily.streak, goals = DailyModel.Describe(self.config, daily) })
	if player:GetAttribute("DeadblockDaily") ~= encoded then player:SetAttribute("DeadblockDaily", encoded) end
end

function QuestService:RefreshDaily(player: Player, state)
	local reward = DailyModel.Refresh(self.config, state.tycoon.daily, player.UserId, today())
	if reward then self:Grant(player, state, reward, "Награда за вход") end
	self:PublishDaily(player, state)
end

function QuestService:Track(player: Player, kind: string, amount: number)
	local state = self.states:Get(player)
	if not state then return end
	for _, reward in ipairs(DailyModel.Track(self.config, state.tycoon.daily, kind, amount)) do
		self:Grant(player, state, reward, "Задание дня")
	end
	self:PublishDaily(player, state)
end

function QuestService:Step(now: number)
	if now - self.lastCheck < CHECK_INTERVAL then return end
	self.lastCheck = now
	for player, state in pairs(self.states:GetAll()) do
		if state.tycoon.daily.day ~= today() then pcall(self.RefreshDaily, self, player, state) end
		local ok, err = pcall(self.CheckPlayer, self, player, state)
		if not ok then warn("[DEADBLOCK] quest check failed for", player.Name, err) end
	end
end

function QuestService:Clear(player: Player)
	for _, key in ipairs({ "DeadblockQuestIndex", "DeadblockQuestTotal", "DeadblockQuestText", "DeadblockQuestReward", "DeadblockQuestTarget", "DeadblockDaily" }) do
		player:SetAttribute(key, nil)
	end
end

return QuestService
