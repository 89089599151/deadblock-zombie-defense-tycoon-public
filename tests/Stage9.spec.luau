-- Social layer: blaster shots, helpers boosting turrets, friend income bonus.
return function(root, config)
	local results = {}
	local function check(name, body)
		local ok, err = pcall(body)
		table.insert(results, {name=name, passed=ok, message=if ok then "PASS" else tostring(err)})
	end
	local Siege = require(root.SiegeModel)
	local Tycoon = require(root.TycoonModel)

	check("a blaster shot hits the first zombie on the ray and its kill pays loot", function()
		local m = Siege.new(config, 1)
		m:StartWave() m:DebugClearSpawnQueue()
		local near = m:DebugSpawnAt(Vector2.new(0, -100))
		local far = m:DebugSpawnAt(Vector2.new(0, -130))
		local hit = m:PlayerShot(Vector2.new(0, -40), Vector2.new(0, -1), 170, 100, 3)
		assert(hit == near, "hit "..tostring(hit))
		m:Step(0.05)
		assert(m:GetZombies()[near] == nil and m:GetZombies()[far] ~= nil)
		assert(m:GetLoot() == config.ZombieTypes.Walker.Bounty)
	end)
	check("a shot that misses or is out of range hurts nobody", function()
		local m = Siege.new(config, 1)
		local id = m:DebugSpawnAt(Vector2.new(30, -100))
		assert(m:PlayerShot(Vector2.new(0, -40), Vector2.new(0, -1), 170, 100, 3) == nil)
		assert(m:PlayerShot(Vector2.new(30, 300), Vector2.new(0, -1), 170, 100, 3) == nil, "too far")
		assert(m:GetZombies()[id].health == m:GetZombies()[id].maxHealth)
	end)
	check("helpers boost turret damage", function()
		local plain, helped = Siege.new(config, 1), Siege.new(config, 1)
		plain:SetTurret(2, "Gun", 1) helped:SetTurret(2, "Gun", 1)
		helped:SetHelperBonus(0.3)
		local a, b = plain:DebugSpawnAt(Vector2.new(0, -100)), helped:DebugSpawnAt(Vector2.new(0, -100))
		plain:Step(0.05) helped:Step(0.05)
		local lostA = plain:GetZombies()[a].maxHealth - plain:GetZombies()[a].health
		local lostB = helped:GetZombies()[b].maxHealth - helped:GetZombies()[b].health
		assert(math.abs(lostB - lostA * 1.3) < 1e-6)
	end)
	check("a friend on the server raises factory income by ten percent", function()
		local t = Tycoon.new(config, 1)
		local base = t:GetIncomePerSecond()
		t.socialBonus = config.Social.FriendIncomeBonus
		assert(math.abs(t:GetIncomePerSecond() - base * 1.1) < 1e-9)
		assert(t:ToProfile().socialBonus == nil, "the bonus is never saved")
	end)

	local passed = 0
	for _, r in ipairs(results) do if r.passed then passed += 1 end end
	return {total=#results, passed=passed, results=results}
end
