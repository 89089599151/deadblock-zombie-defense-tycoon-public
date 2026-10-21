-- Phase 4: difficulty ladder, new zombie roles, global record score.
return function(root, config)
	local results = {}
	local function check(name, body)
		local ok, err = pcall(body)
		table.insert(results, {name=name, passed=ok, message=if ok then "PASS" else tostring(err)})
	end
	local Tycoon = require(root.TycoonModel)
	local Siege = require(root.SiegeModel)
	local Board = require(root.GlobalBoardService)

	check("harder difficulties open after wave 10 and keep their own progress", function()
		local t = Tycoon.new(config, 1)
		assert(t:MaxDifficulty() == 1 and not t:SetDifficulty(2))
		t:RecordWave(11, 10)
		assert(t:MaxDifficulty() == 2 and t:SetDifficulty(2))
		assert(t:GetProgress().wave == 1, "hard starts at wave 1")
		t:RecordWave(4, 3)
		assert(t:GetProgress(1, 1).best == 10 and t:GetProgress(1, 2).best == 3)
		assert(not t:SetDifficulty(3))
		local copy = Tycoon.FromProfile(config, 1, t:ToProfile())
		assert(copy.difficulty == 2 and copy:GetProgress(1, 2).wave == 4 and copy:GetProgress(1, 1).best == 10)
	end)
	check("difficulty scales zombie health and rewards", function()
		local normal, nightmare = Siege.new(config, 1, nil, 1), Siege.new(config, 1, nil, 3)
		assert(math.abs(nightmare:HealthFor("Walker", 1) - normal:HealthFor("Walker", 1) * 5) < 1e-6)
		for pad = 1, 8 do normal:SetTurret(pad, "Gun", 3) nightmare:SetTurret(pad, "Sniper", 3) end
		local function reward(m)
			m:StartWave()
			for _ = 1, 4000 do for _, e in ipairs(m:Step(0.05)) do if e.type == "state" and e.reward then return e.reward end end end
			return nil
		end
		local a, b = reward(normal), reward(nightmare)
		assert(a and b and b >= a * 5, "normal "..tostring(a).." nightmare "..tostring(b))
	end)
	check("flyers pass over walls and reach the core", function()
		local m = Siege.new(config, 1)
		m:DebugSpawnAt(Vector2.new(0, -130), "Flyer")
		for _ = 1, 400 do m:Step(0.05) end
		assert(m:GetCoreHealth() < config.Core.MaxHealth)
	end)
	check("healers mend nearby zombies", function()
		local m = Siege.new(config, 2)
		local hurt = m:DebugSpawnAt(Vector2.new(0, -200))
		m:DebugSpawnAt(Vector2.new(4, -200), "Healer")
		local zombie = m:GetZombies()[hurt]
		zombie.health = zombie.maxHealth * 0.5
		local before = zombie.health
		m:Step(1)
		assert(zombie.health > before)
	end)
	check("shield bearers lend armour to their neighbours", function()
		local plain, shielded = Siege.new(config, 2), Siege.new(config, 2)
		plain:SetTurret(2, "Gun", 1) shielded:SetTurret(2, "Gun", 1)
		local a = plain:DebugSpawnAt(Vector2.new(0, -100))
		local b = shielded:DebugSpawnAt(Vector2.new(0, -100))
		shielded:DebugSpawnAt(Vector2.new(5, -103), "Shielder")
		plain:Step(0.05) shielded:Step(0.05)
		local lostA = plain:GetZombies()[a].maxHealth - plain:GetZombies()[a].health
		local lostB = shielded:GetZombies()[b].maxHealth - shielded:GetZombies()[b].health
		assert(lostB < lostA, "armour aura should reduce gun damage")
	end)
	check("global score orders world, then difficulty, then wave", function()
		local t = Tycoon.new(config, 1)
		t:RecordWave(16, 15)
		local s1 = Board.Score(config, t)
		t.unlockedWorld = 2 t:SetWorld(2) t:RecordWave(3, 2)
		local s2 = Board.Score(config, t)
		assert(s2 > s1 and Board.Describe(config, s2) == "Пустошь · Обычная · волна 2")
	end)

	check("the core shoots zombies that get close and reports who hurt it most", function()
		local m = Siege.new(config, 1)
		local id = m:DebugSpawnAt(Vector2.new(0, -45))
		local shots = 0
		for _ = 1, 10 do for _, e in ipairs(m:Step(0.05)) do if e.type == "shot" and e.pad == 0 then shots += 1 end end end
		assert(shots >= 1 and m:GetZombies()[id].health < m:GetZombies()[id].maxHealth)
		local d = Siege.new(config, 1)
		d:StartWave() d:DebugClearSpawnQueue() d:DebugSetCoreHealth(5)
		d:DebugSpawnAt(Vector2.new(0, -40), "Flyer")
		local worst
		for _ = 1, 200 do for _, e in ipairs(d:Step(0.05)) do if e.type == "state" and e.state == "Defeated" then worst = e.worst end end end
		assert(worst == "Flyer", "worst "..tostring(worst))
		assert(config.DefeatTips[worst])
	end)

	local passed = 0
	for _, r in ipairs(results) do if r.passed then passed += 1 end end
	return {total=#results, passed=passed, results=results}
end
