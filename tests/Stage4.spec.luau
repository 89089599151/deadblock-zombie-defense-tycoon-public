-- Worlds and wave generation.
return function(root, config)
	local results = {}
	local function check(name, body)
		local ok, err = pcall(body)
		table.insert(results, {name=name, passed=ok, message=if ok then "PASS" else tostring(err)})
	end
	local function generator() return require(root.WaveGenerator) end

	check("worlds get harder and richer, with rising level caps", function()
		assert(#config.Worlds == 3)
		for index, world in ipairs(config.Worlds) do
			assert(world.Id == index)
			for _, name in ipairs(world.ZombieTypes) do assert(config.ZombieTypes[name], "unknown type "..name) end
			if index > 1 then
				local previous = config.Worlds[index - 1]
				assert(world.HealthMultiplier > previous.HealthMultiplier and world.RewardMultiplier > previous.RewardMultiplier)
				assert(world.DropperMultiplier > previous.DropperMultiplier and world.MaxLevel > previous.MaxLevel)
				assert(world.PortalPrice > previous.PortalPrice)
			end
		end
	end)
	check("budget on world 1 is 5, 6, 7 for the first waves", function()
		local g = generator()
		assert(g.Budget(config, 1, 1) == 5 and g.Budget(config, 1, 2) == 6 and g.Budget(config, 1, 3) == 7)
	end)
	check("wave 1 is five walkers", function()
		local list = generator().Compose(config, 1, 1)
		assert(#list == 5)
		for _, name in ipairs(list) do assert(name == "Walker") end
	end)
	check("same input gives the same list", function()
		local g = generator()
		for world = 1, 3 do for wave = 1, 25 do
			assert(table.concat(g.Compose(config, world, wave), ",") == table.concat(g.Compose(config, world, wave), ","))
		end end
	end)
	check("ordinary zombies spend exactly the budget", function()
		local g = generator()
		for world = 1, 3 do for wave = 1, 40 do
			local spent = 0
			for _, name in ipairs(g.Compose(config, world, wave)) do spent += config.ZombieTypes[name].Cost end
			local budget = g.Budget(config, world, wave)
			local list = g.Compose(config, world, wave)
			assert(#list <= config.WaveRules.MaxWaveZombies + g.BossCount(config, wave))
			if budget <= config.WaveRules.MaxWaveBudget and #list < config.WaveRules.MaxWaveZombies then
				assert(spent == budget, ("world %d wave %d spent %d"):format(world, wave, spent))
				assert(g.Scale(config, world, wave) == 1)
			else
				assert(g.Scale(config, world, wave) > 1 or budget <= config.WaveRules.MaxWaveBudget)
			end
		end end
	end)
	check("types unlock by wave and by world", function()
		local g = generator()
		local firstSeen = {}
		for world = 1, 3 do for wave = 1, 30 do for _, name in ipairs(g.Compose(config, world, wave)) do
			if name ~= "Colossus" then
				assert(wave >= config.ZombieTypes[name].MinWave, name.." too early")
				assert(table.find(config.Worlds[world].ZombieTypes, name), name.." not in world "..world)
			end
			firstSeen[name] = true
		end end end
		for _, name in ipairs({"Walker", "Runner", "Brute", "Exploder", "Spitter", "Colossus"}) do assert(firstSeen[name], name.." never appears") end
	end)
	check("every tenth wave brings Colossi", function()
		local g = generator()
		local function bosses(wave) local n = 0 for _, name in ipairs(g.Compose(config, 1, wave)) do if name == "Colossus" then n += 1 end end return n end
		assert(bosses(9) == 0 and bosses(10) == 1 and bosses(20) == 2 and bosses(21) == 0)
	end)
	check("summary counts match the composition", function()
		local g = generator()
		local total = 0
		for _, entry in ipairs(g.Summary(config, 2, 12)) do total += entry.count end
		assert(total == #g.Compose(config, 2, 12))
	end)
	check("unknown world asserts", function()
		local g = generator()
		assert(not pcall(g.Compose, config, 99, 1) and not pcall(g.Budget, config, 0, 1))
	end)
	check("dropper income follows the world multiplier", function()
		local t = require(root.TycoonModel).new(config, 101)
		assert(t:GetDropperValue(1, 1) == 5 and t:GetIncomePerSecond() == 2.5)
		t.unlockedWorld = 2
		assert(t:SetWorld(2) and t:GetDropperValue(1, 1) == 20 and t:GetIncomePerSecond() == 10)
		assert(not t:SetWorld(99) and t.worldId == 2)
	end)

	local passed = 0
	for _, r in ipairs(results) do if r.passed then passed += 1 end end
	return {total=#results, passed=passed, results=results}
end
