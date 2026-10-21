--!strict
-- Deterministic wave composition: the same (world, wave) always yields the same list, so a rollback
-- after defeat replays the identical wave. Every BossEvery-th wave also brings Colossi.
local WaveGenerator = {}

local function getWorld(config: any, worldId: number): any
	local world = config.Worlds[worldId]
	assert(world, "Unknown world")
	return world
end

function WaveGenerator.Budget(config: any, worldId: number, wave: number): number
	local world = getWorld(config, worldId)
	assert(wave >= 1 and wave % 1 == 0, "Wave must be a positive integer")
	local rules = config.WaveRules
	return math.floor(rules.BaseBudget * rules.Growth ^ wave * world.Difficulty + 0.5)
end

-- Health and bounty multiplier for waves whose budget exceeds the cap.
function WaveGenerator.Scale(config: any, worldId: number, wave: number): number
	return math.max(1, WaveGenerator.Budget(config, worldId, wave) / config.WaveRules.MaxWaveBudget)
end

function WaveGenerator.BossCount(config: any, wave: number): number
	local every = config.WaveRules.BossEvery
	return if wave % every == 0 then math.min(3, wave // every) else 0
end

function WaveGenerator.Compose(config: any, worldId: number, wave: number): { string }
	local world = getWorld(config, worldId)
	local remaining = math.min(WaveGenerator.Budget(config, worldId, wave), config.WaveRules.MaxWaveBudget)
	local random = Random.new(worldId * 10007 + wave)
	local unlocked: { string } = {}
	for _, name in ipairs(world.ZombieTypes) do
		local definition = config.ZombieTypes[name]
		if definition.MinWave <= wave and definition.Cost > 0 then table.insert(unlocked, name) end
	end
	local list: { string } = {}
	while remaining > 0 and #list < config.WaveRules.MaxWaveZombies do
		local options: { string } = {}
		local totalWeight = 0
		for _, name in ipairs(unlocked) do
			local definition = config.ZombieTypes[name]
			if definition.Cost <= remaining then
				table.insert(options, name)
				totalWeight += definition.Weight
			end
		end
		if #options == 0 then break end
		local roll = random:NextNumber() * totalWeight
		local chosen = options[#options]
		for _, name in ipairs(options) do
			roll -= config.ZombieTypes[name].Weight
			if roll <= 0 then chosen = name break end
		end
		table.insert(list, chosen)
		remaining -= config.ZombieTypes[chosen].Cost
	end
	-- Bosses walk in the middle of the wave, escorted by the rest.
	for _ = 1, WaveGenerator.BossCount(config, wave) do
		table.insert(list, math.max(1, #list // 2), "Colossus")
	end
	return list
end

-- Counts per type for the HUD preview, ordered by first appearance.
function WaveGenerator.Summary(config: any, worldId: number, wave: number): { { type: string, count: number } }
	local counts, order = {}, {}
	for _, name in ipairs(WaveGenerator.Compose(config, worldId, wave)) do
		if not counts[name] then counts[name] = 0 table.insert(order, name) end
		counts[name] += 1
	end
	local summary = {}
	for _, name in ipairs(order) do table.insert(summary, { type = name, count = counts[name] }) end
	return summary
end

return WaveGenerator
