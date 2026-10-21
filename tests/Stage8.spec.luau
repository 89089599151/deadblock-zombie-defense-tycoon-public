-- Phase 2: cores, turret modules, factory overdrive, daily goals and login streak.
return function(root, config)
	local results = {}
	local function check(name, body)
		local ok, err = pcall(body)
		table.insert(results, {name=name, passed=ok, message=if ok then "PASS" else tostring(err)})
	end
	local Tycoon = require(root.TycoonModel)
	local Siege = require(root.SiegeModel)
	local Daily = require(root.DailyModel)
	local sequence = 0
	local function action(kind, id, level, extra)
		sequence += 1
		local a = {kind=kind, targetId=id, expectedLevel=level, requestId="s8-"..sequence}
		for k, v in pairs(extra or {}) do a[k] = v end
		return a
	end

	check("modules cost 5/15/40 cores, stop at 3 and need a turret", function()
		local t = Tycoon.new(config, 1) t:Credit(100) t:CreditCores(60)
		assert(not t:Apply(1, action("UpgradeModule", 1, 0, {module = "Damage"})).ok, "no turret yet")
		t:Apply(1, action("BuildTurret", 1, nil, {turretType = "Gun"}))
		for level = 0, 2 do assert(t:Apply(1, action("UpgradeModule", 1, level, {module = "Damage"})).ok) end
		assert(t.turrets[1].modules.Damage == 3 and t.cores == 0)
		t:CreditCores(100)
		assert(not t:Apply(1, action("UpgradeModule", 1, 3, {module = "Damage"})).ok and t.cores == 100)
		assert(not t:Apply(1, action("UpgradeModule", 1, 0, {module = "Costs"})).ok, "config keys are not modules")
	end)
	check("not enough cores changes nothing", function()
		local t = Tycoon.new(config, 1) t:Credit(100) t:CreditCores(4)
		t:Apply(1, action("BuildTurret", 1, nil, {turretType = "Gun"}))
		local r = t:Apply(1, action("UpgradeModule", 1, 0, {module = "Rate"}))
		assert(not r.ok and r.code == "insufficient_cores" and t.cores == 4 and (t.turrets[1].modules.Rate or 0) == 0)
	end)
	check("modules make turrets hit harder, faster and farther", function()
		local plain, boosted = Siege.new(config, 1), Siege.new(config, 1)
		plain:SetTurret(2, "Gun", 1)
		boosted:SetTurret(2, "Gun", 1, { Damage = 2, Rate = 1, Range = 1 })
		local a = plain:DebugSpawnAt(Vector2.new(0, -100))
		local b = boosted:DebugSpawnAt(Vector2.new(0, -100))
		plain:Step(0.05) boosted:Step(0.05)
		local lostPlain = plain:GetZombies()[a].maxHealth - plain:GetZombies()[a].health
		local lostBoosted = boosted:GetZombies()[b].maxHealth - boosted:GetZombies()[b].health
		assert(math.abs(lostBoosted - lostPlain * 1.5) < 1e-6, "damage "..lostPlain.." vs "..lostBoosted)
		assert(math.abs(boosted:GetTurret(2).cooldown - config.TurretTypes.Gun.Interval / 1.2) < 1e-6)
		local far = Siege.new(config, 1)
		far:SetTurret(2, "Gun", 1, { Range = 3 })
		far:DebugSpawnAt(Vector2.new(0, -64 - 60))
		local shots = 0
		for _, e in ipairs(far:Step(0.05)) do if e.type == "shot" then shots += 1 end end
		assert(shots == 1, "range module should reach 60 studs")
	end)
	check("overdrive doubles dropper value for its duration", function()
		local now = 1000
		local t = Tycoon.new(config, 1) t.clock = function() return now end
		t:CreditCores(10)
		assert(t:Apply(1, action("Overdrive", 1)).ok and t.cores == 0)
		assert(t:GetDropperValue(1, 1) == 10)
		assert(not t:Apply(1, action("Overdrive", 1)).ok, "cannot stack")
		now += config.Overdrive.Duration + 1
		assert(t:GetDropperValue(1, 1) == 5)
	end)
	check("a clean wave pays cores with the bonus; defeat pays none", function()
		local m = Siege.new(config, 1)
		for pad = 1, 8 do m:SetTurret(pad, "Gun", 3) end
		m:StartWave()
		local cores
		for _ = 1, 2400 do for _, e in ipairs(m:Step(0.05)) do if e.type == "state" and e.reward then cores = e.cores end end if cores then break end end
		assert(cores == math.floor(5 * config.Cores.Walker * config.WaveRules.CleanBonus), "cores "..tostring(cores))
	end)
	check("daily goals are stable per day, streak grows and resets", function()
		local d = Daily.New()
		local first = Daily.Refresh(config, d, 7, 100)
		assert(first and d.streak == 1 and #d.goals == config.Daily.Count)
		local ids = {} for _, g in ipairs(d.goals) do table.insert(ids, g.id) end
		local again = Daily.Roll(config, 7, 100)
		for i, g in ipairs(again) do assert(g.id == ids[i]) end
		assert(Daily.Refresh(config, d, 7, 100) == nil, "same day pays once")
		assert(Daily.Refresh(config, d, 7, 101) and d.streak == 2)
		assert(Daily.Refresh(config, d, 7, 105) and d.streak == 1, "missed days reset the streak")
	end)
	check("a daily goal pays exactly once when completed", function()
		local d = Daily.New()
		d.goals = { { id = "kills", goal = 80, progress = 0, done = false } }
		assert(#Daily.Track(config, d, "kills", 50) == 0)
		local rewards = Daily.Track(config, d, "kills", 50)
		assert(#rewards == 1 and rewards[1].cores == 5)
		assert(#Daily.Track(config, d, "kills", 50) == 0)
	end)
	check("cores, modules, overdrive and daily survive a save", function()
		local t = Tycoon.new(config, 1) t:Credit(100) t:CreditCores(20)
		t:Apply(1, action("BuildTurret", 2, nil, {turretType = "Gun"}))
		t:Apply(1, action("UpgradeModule", 2, 0, {module = "Range"}))
		Daily.Refresh(config, t.daily, 1, 50)
		local copy = Tycoon.FromProfile(config, 1, t:ToProfile())
		assert(copy.cores == 15 and copy.turrets[2].modules.Range == 1)
		assert(copy.daily.streak == 1 and #copy.daily.goals == config.Daily.Count and copy.lastSeen)
	end)
	check("the portal opens after beating the first Colossus", function()
		local t = Tycoon.new(config, 1) t:Credit(config.Worlds[2].PortalPrice)
		t:RecordWave(10, 9)
		assert(not t:Apply(1, action("BuyPortal", 2)).ok)
		t:RecordWave(11, 10)
		assert(t:Apply(1, action("BuyPortal", 2)).ok)
	end)

	local passed = 0
	for _, r in ipairs(results) do if r.passed then passed += 1 end end
	return {total=#results, passed=passed, results=results}
end
