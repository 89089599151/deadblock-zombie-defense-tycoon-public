--!strict
-- Daily goals and login streak. Pure: the caller passes the day number (os.time() // 86400) so tests
-- control time. Rewards are returned, never granted here.
local DailyModel = {}

export type Goal = { id: string, goal: number, progress: number, done: boolean }
export type Daily = { day: number, goals: { Goal }, lastLoginDay: number, streak: number }
export type Reward = { cores: number, money: number, text: string }

function DailyModel.New(): Daily
	return { day = -1, goals = {}, lastLoginDay = -1, streak = 0 }
end

-- Same player and day always get the same three goals.
function DailyModel.Roll(config: any, userId: number, day: number): { Goal }
	local pool = table.clone(config.Daily.Pool)
	local random = Random.new(userId * 31 + day * 7919)
	local goals: { Goal } = {}
	for _ = 1, math.min(config.Daily.Count, #pool) do
		local pick = table.remove(pool, random:NextInteger(1, #pool))
		table.insert(goals, { id = pick.Id, goal = pick.Goal, progress = 0, done = false })
	end
	return goals
end

local function definition(config: any, id: string): any
	for _, entry in ipairs(config.Daily.Pool) do if entry.Id == id then return entry end end
	return nil
end

-- Call on join and periodically. Returns the streak reward if this is the first visit of a new day.
function DailyModel.Refresh(config: any, daily: Daily, userId: number, day: number): Reward?
	if daily.day ~= day then
		daily.day = day
		daily.goals = DailyModel.Roll(config, userId, day)
	end
	if daily.lastLoginDay == day then return nil end
	daily.streak = if daily.lastLoginDay == day - 1 then daily.streak + 1 else 1
	daily.lastLoginDay = day
	local table_ = config.Daily.Streak
	local entry = table_[math.min(daily.streak, #table_)]
	return { cores = entry.Cores, money = entry.Money, text = "Серия входов: день " .. daily.streak }
end

-- Adds progress; returns rewards for goals completed by this call.
function DailyModel.Track(config: any, daily: Daily, kind: string, amount: number): { Reward }
	local rewards: { Reward } = {}
	for _, goal in ipairs(daily.goals) do
		if goal.id == kind and not goal.done then
			goal.progress = math.min(goal.goal, goal.progress + amount)
			if goal.progress >= goal.goal then
				goal.done = true
				local entry = definition(config, kind)
				table.insert(rewards, { cores = entry.Cores, money = entry.Money, text = string.format(entry.Text, entry.Goal) })
			end
		end
	end
	return rewards
end

function DailyModel.Describe(config: any, daily: Daily): { { text: string, progress: number, goal: number, done: boolean } }
	local list = {}
	for _, goal in ipairs(daily.goals) do
		local entry = definition(config, goal.id)
		if entry then table.insert(list, { text = string.format(entry.Text, entry.Goal), progress = goal.progress, goal = goal.goal, done = goal.done }) end
	end
	return list
end

-- Sanitises saved data.
function DailyModel.FromSaved(config: any, saved: any): Daily
	local daily = DailyModel.New()
	if type(saved) ~= "table" then return daily end
	daily.day = if type(saved.day) == "number" then saved.day else -1
	daily.lastLoginDay = if type(saved.lastLoginDay) == "number" then saved.lastLoginDay else -1
	daily.streak = if type(saved.streak) == "number" then math.clamp(math.floor(saved.streak), 0, 10000) else 0
	if type(saved.goals) == "table" then
		for _, goal in ipairs(saved.goals) do
			if type(goal) == "table" and type(goal.id) == "string" and definition(config, goal.id) and type(goal.progress) == "number" then
				local entry = definition(config, goal.id)
				table.insert(daily.goals, { id = goal.id, goal = entry.Goal, progress = math.clamp(goal.progress, 0, entry.Goal), done = goal.done == true })
			end
		end
	end
	return daily
end

return DailyModel
