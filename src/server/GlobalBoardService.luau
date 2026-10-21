-- All-server records board on the plaza (OrderedDataStore). Disabled in Studio unless saves are enabled,
-- so tests never touch live data. Score = world * 10000 + difficulty * 1000 + best wave (capped at 999).
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")

local GlobalBoardService = {}
GlobalBoardService.__index = GlobalBoardService

function GlobalBoardService.new(config, states, world, enabled: boolean)
	local store = nil
	if enabled then
		local ok, result = pcall(function() return DataStoreService:GetOrderedDataStore("DeadblockRecords_v1") end)
		if ok then store = result end
	end
	return setmetatable({ config = config, states = states, world = world, store = store, lastSubmit = {}, submitted = {}, lastRefresh = -math.huge, names = {} }, GlobalBoardService)
end

function GlobalBoardService.Score(config, tycoon): number
	local best = 0
	for key, progress in pairs(tycoon.waves) do
		local worldId, difficulty = key % 100, key // 100 + 1
		if config.Worlds[worldId] and config.Difficulties[difficulty] and progress.best > 0 then
			best = math.max(best, worldId * 10000 + difficulty * 1000 + math.min(progress.best, 999))
		end
	end
	return best
end

function GlobalBoardService.Describe(config, score: number): string
	local worldId, difficulty, wave = score // 10000, (score // 1000) % 10, score % 1000
	local world = config.Worlds[worldId]
	local level = config.Difficulties[difficulty]
	return string.format("%s · %s · волна %d", if world then world.Name else "?", if level then level.Name else "?", wave)
end

local function setText(self, text: string)
	local board = self.world:FindFirstChild("Plaza") and self.world.Plaza:FindFirstChild("GlobalBoard")
	if board then board.Screen.SurfaceGui.Rows.Text = text end
end

function GlobalBoardService:Submit(player: Player, tycoon)
	if not self.store then return end
	local now = os.clock()
	if now - (self.lastSubmit[player.UserId] or -math.huge) < self.config.Social.GlobalSaveInterval then return end
	local score = GlobalBoardService.Score(self.config, tycoon)
	if score <= (self.submitted[player.UserId] or 0) then return end
	self.lastSubmit[player.UserId] = now
	self.submitted[player.UserId] = score
	task.spawn(function()
		pcall(function() self.store:SetAsync("u_" .. player.UserId, score) end)
	end)
end

function GlobalBoardService:Refresh()
	if not self.store then
		setText(self, "Глобальный рейтинг заработает после публикации игры.")
		return
	end
	local ok, pages = pcall(function() return self.store:GetSortedAsync(false, 10) end)
	if not ok then return end
	local lines = {}
	for index, entry in ipairs(pages:GetCurrentPage()) do
		local userId = tonumber(string.sub(entry.key, 3))
		local name = userId and self.names[userId]
		if userId and not name then
			local found, result = pcall(function() return Players:GetNameFromUserIdAsync(userId) end)
			name = if found then result else "Командир"
			self.names[userId] = name
		end
		table.insert(lines, string.format("%d. %s — %s", index, name or "Командир", GlobalBoardService.Describe(self.config, entry.value)))
	end
	setText(self, if #lines > 0 then table.concat(lines, "\n") else "Рекордов пока нет — стань первым!")
end

function GlobalBoardService:Step(now: number)
	for player, state in pairs(self.states:GetAll()) do self:Submit(player, state.tycoon) end
	if now - self.lastRefresh >= self.config.Social.GlobalBoardInterval then
		self.lastRefresh = now
		task.spawn(function() pcall(self.Refresh, self) end)
	end
end

return GlobalBoardService
