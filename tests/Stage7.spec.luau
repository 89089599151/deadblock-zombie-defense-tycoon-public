-- Onboarding: free first turret, tutorial rules and targets, early waves spawn closer.
return function(root, config)
	local results = {}
	local function check(name, body)
		local ok, err = pcall(body)
		table.insert(results, {name=name, passed=ok, message=if ok then "PASS" else tostring(err)})
	end
	local Tycoon = require(root.TycoonModel)
	local Rules = require(root.QuestRules)
	local sequence = 0
	local function action(kind, id, level, turretType)
		sequence += 1
		return {kind=kind, targetId=id, expectedLevel=level, turretType=turretType, requestId="s7-"..sequence}
	end

	check("the first turret is free once, the second costs full price", function()
		local t = Tycoon.new(config, 1)
		t.freeTurret = true
		t:Credit(100)
		assert(t:Apply(1, action("BuildTurret", 2, nil, "Gun")).ok and t.money == 100 and not t.freeTurret)
		assert(t:Apply(1, action("BuildTurret", 3, nil, "Gun")).ok and t.money == 25)
	end)
	check("tutorial progress and the free turret survive a save", function()
		local t = Tycoon.new(config, 1)
		t.freeTurret = true
		t.tutorial = 4
		local copy = Tycoon.FromProfile(config, 1, t:ToProfile())
		assert(copy.tutorial == 4 and copy.freeTurret == true)
		local clamped = Tycoon.FromProfile(config, 1, { schema = 1, tutorial = 999 })
		assert(clamped.tutorial == #config.Tutorial + 1)
	end)
	check("tutorial steps complete in order from real state", function()
		local t = Tycoon.new(config, 1)
		local idle = { state = "Preparing", best = 0 }
		assert(not Rules.IsDone("build", t, idle))
		t.turrets[2] = { type = "Gun", level = 1 }
		assert(Rules.IsDone("build", t, idle))
		assert(not Rules.IsDone("start", t, idle) and Rules.IsDone("start", t, { state = "Active", best = 0 }))
		assert(Rules.IsDone("wave1", t, { state = "Preparing", best = 1 }))
		assert(not Rules.IsDone("upgrade", t, idle))
		t.turrets[2].level = 2
		assert(Rules.IsDone("upgrade", t, idle))
		assert(not Rules.IsDone("second", t, idle))
		t.turrets[3] = { type = "Gun", level = 1 }
		assert(Rules.IsDone("second", t, idle))
		assert(Rules.IsDone("boss", t, { state = "Preparing", best = 10 }))
		for _, step in ipairs(config.Tutorial) do assert(type(step.Id) == "string" and type(step.Text) == "string" and step.Reward >= 0) end
	end)
	check("the beacon points at the pad facing the first attack", function()
		local t = Tycoon.new(config, 1)
		assert(Rules.Target(config.Tutorial[1], t, { state = "Preparing", best = 0, attackDirection = "S" }) == "pad:6")
		assert(Rules.Target(config.Tutorial[2], t, { state = "Preparing", best = 0, attackDirection = "S" }) == "core")
		t.turrets[6] = { type = "Gun", level = 1 }
		local second = Rules.Target(config.Tutorial[6], t, { state = "Preparing", best = 0, attackDirection = "S" })
		assert(second == "pad:7" or second == "pad:5", "got "..tostring(second))
	end)
	check("first waves spawn closer but outside the wall; later waves at full distance", function()
		local Siege = require(root.SiegeModel)
		local function firstSpawnDistance(wave)
			local m = Siege.new(config, 1)
			m:DebugSetWave(wave)
			m:StartWave()
			m:Step(0.05)
			for _, zombie in pairs(m:GetZombies()) do return zombie.position end
			return nil
		end
		local early, late = firstSpawnDistance(1), firstSpawnDistance(5)
		local size = config.Compound.Levels[1]
		assert(early and late)
		assert(early.Magnitude < late.Magnitude * 0.7, "early "..early.Magnitude.." late "..late.Magnitude)
		assert(math.abs(early.X) > size.HalfX or math.abs(early.Y) > size.HalfZ, "spawned inside the wall")
	end)

	local passed = 0
	for _, r in ipairs(results) do if r.passed then passed += 1 end end
	return {total=#results, passed=passed, results=results}
end
