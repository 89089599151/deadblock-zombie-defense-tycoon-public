-- Outpost geometry and siege simulation: walls, zombie roles, turret roles, loot, repair, rollback.
return function(root, config)
	local results = {}
	local function check(name, body)
		local ok, err = pcall(body)
		table.insert(results, {name=name, passed=ok, message=if ok then "PASS" else tostring(err)})
	end
	local Layout = require(root.CompoundLayout)
	local function siege(world) return require(root.SiegeModel).new(config, world) end
	local function run(m, seconds)
		local events, elapsed = {}, 0
		while elapsed < seconds - 1e-9 do
			for _, e in ipairs(m:Step(0.05)) do table.insert(events, e) end
			elapsed += 0.05
		end
		return events
	end
	local function wallAt(m, x, z)
		local best, bestGap = nil, math.huge
		for id, wall in pairs(m:GetWalls()) do
			local gap = (wall.data.center - Vector2.new(x, z)).Magnitude
			if gap < bestGap then best, bestGap = id, gap end
		end
		return best
	end
	local L1 = config.Compound.Levels[1]
	local function inside(position) return math.abs(position.X) < L1.HalfX and math.abs(position.Y) < L1.HalfZ end
	local function firstShot(m)
		for _, e in ipairs(m:Step(0.05)) do if e.type == "shot" then return e end end
		return nil
	end

	check("each base level has a closed perimeter and eight pads inside it", function()
		local built = Layout.Build(config)
		assert(#built.pads == 32)
		for level, size in ipairs(config.Compound.Levels) do
			local walls, total = built.walls[level], 0
			for index, wall in ipairs(walls) do
				total += (wall.b - wall.a).Magnitude
				assert((wall.b - walls[index % #walls + 1].a).Magnitude < 1e-3, "gap after "..wall.id)
				assert((wall.b - wall.a).Magnitude <= config.Compound.SegmentLength + 1e-3)
			end
			assert(math.abs(total - 4 * (size.HalfX + size.HalfZ)) < 1e-2)
			local count = 0
			for _, pad in ipairs(built.pads) do
				if pad.level == level then
					count += 1
					assert(math.abs(pad.position.X) < size.HalfX and math.abs(pad.position.Y) < size.HalfZ)
				end
			end
			assert(count == 8)
		end
		local outer = config.Compound.Levels[#config.Compound.Levels]
		for _, point in ipairs(built.spawnPoints) do assert(math.abs(point.position.X) > outer.HalfX or math.abs(point.position.Y) > outer.HalfZ) end
	end)
	check("a walker stops at the north wall and breaks it, not the core", function()
		local m = siege(1)
		local id = m:DebugSpawnAt(Vector2.new(0, -120))
		run(m, 10)
		local zombie = m:GetZombies()[id]
		assert(zombie and zombie.position.Y < -L1.HalfZ + 0.01 and zombie.position.Y > -L1.HalfZ - 1, "stopped at "..tostring(zombie and zombie.position))
		assert(m:GetWallHealth(wallAt(m, 0, -74)) < config.Walls.Health[1])
		assert(m:GetCoreHealth() == config.Core.MaxHealth)
	end)
	check("no zombie crosses a living wall from any side", function()
		local m = siege(1)
		for i = 0, 15 do
			local angle = i * math.pi / 8
			m:DebugSpawnAt(Vector2.new(math.cos(angle) * 150, math.sin(angle) * 130))
		end
		run(m, 20)
		for _, zombie in pairs(m:GetZombies()) do assert(not inside(zombie.position), "inside at "..tostring(zombie.position)) end
		assert(m:GetCoreHealth() == config.Core.MaxHealth)
	end)
	check("a destroyed wall opens the way to the core", function()
		local m = siege(1)
		m:DebugSetWallHealth(wallAt(m, 0, -74), 0)
		m:DebugSpawnAt(Vector2.new(0, -120))
		run(m, 16)
		assert(m:GetCoreHealth() < config.Core.MaxHealth)
	end)
	check("runners head for a breach", function()
		local m = siege(1)
		m:DebugSetWallHealth(wallAt(m, 84, -9), 0)
		local id = m:DebugSpawnAt(Vector2.new(0, -120), "Runner")
		run(m, 3)
		assert(m:GetZombies()[id].position.X > 15)
	end)
	check("spitters stop at range and damage the wall from afar", function()
		local m = siege(2)
		local id = m:DebugSpawnAt(Vector2.new(0, -130), "Spitter")
		run(m, 14)
		local zombie = m:GetZombies()[id]
		assert(zombie.position.Y < -L1.HalfZ - 20, "came too close: "..tostring(zombie.position))
		assert(m:GetWallHealth(wallAt(m, 0, -74)) < config.Walls.Health[1])
	end)
	check("exploders blow up on the wall without paying loot", function()
		local m = siege(1)
		local id = m:DebugSpawnAt(Vector2.new(0, -90), "Exploder")
		run(m, 4)
		assert(m:GetZombies()[id] == nil)
		assert(m:GetWallHealth(wallAt(m, 0, -74)) == config.Walls.Health[1] - 90)
		assert(m:GetLoot() == 0)
	end)
	check("brute armor shrinks gun hits while fire burns at full strength", function()
		local m = siege(1)
		m:SetTurret(2, "Gun", 1)
		local id = m:DebugSpawnAt(Vector2.new(0, -100), "Brute")
		local before = m:GetZombies()[id].health
		assert(firstShot(m))
		assert(math.abs(before - m:GetZombies()[id].health - 2) < 1e-6)
		local f = siege(1)
		f:SetTurret(2, "Flamer", 1)
		local brute = f:DebugSpawnAt(Vector2.new(0, -80), "Brute")
		local start = f:GetZombies()[brute].health
		assert(firstShot(f))
		assert(math.abs(start - f:GetZombies()[brute].health - 5) < 1e-6)
	end)
	check("the gun fires at the zombie closest to the core", function()
		local m = siege(1)
		m:SetTurret(2, "Gun", 1)
		m:DebugSpawnAt(Vector2.new(0, -110))
		local closer = m:DebugSpawnAt(Vector2.new(30, -90))
		assert(firstShot(m).targets[1] == closer)
	end)
	check("the sniper picks the toughest target", function()
		local m = siege(1)
		m:SetTurret(2, "Sniper", 1)
		m:DebugSpawnAt(Vector2.new(20, -100))
		local brute = m:DebugSpawnAt(Vector2.new(-20, -100), "Brute")
		assert(firstShot(m).targets[1] == brute)
	end)
	check("tesla chains four targets with falloff", function()
		local m = siege(1)
		m:SetTurret(2, "Tesla", 1)
		local ids = {}
		for _, x in ipairs({0, 10, 20, 30}) do table.insert(ids, m:DebugSpawnAt(Vector2.new(x, -100))) end
		local far = m:DebugSpawnAt(Vector2.new(80, -100))
		local shot = firstShot(m)
		assert(#shot.targets == 4 and not table.find(shot.targets, far))
		local expected = 30 - 22
		assert(math.abs(m:GetZombies()[ids[1]].health - expected) < 1e-6)
		assert(math.abs(m:GetZombies()[ids[4]].health - (30 - 22 * 0.85 ^ 3)) < 1e-6)
	end)
	check("the mortar ignores close zombies and splashes a cluster", function()
		local m = siege(1)
		m:SetTurret(2, "Mortar", 1)
		local near = m:DebugSpawnAt(Vector2.new(0, -76))
		local cluster = { m:DebugSpawnAt(Vector2.new(0, -150)), m:DebugSpawnAt(Vector2.new(3, -152)), m:DebugSpawnAt(Vector2.new(-3, -148)) }
		local shot = firstShot(m)
		assert(shot and shot.impact and #shot.targets == 3)
		for _, id in ipairs(cluster) do assert(m:GetZombies()[id] == nil, "cluster zombie survived") end
		assert(m:GetZombies()[near] and m:GetZombies()[near].health == m:GetZombies()[near].maxHealth)
	end)
	check("the flamer burns everyone in its short range", function()
		local m = siege(1)
		m:SetTurret(2, "Flamer", 1)
		m:DebugSpawnAt(Vector2.new(0, -80)) m:DebugSpawnAt(Vector2.new(5, -82))
		local far = m:DebugSpawnAt(Vector2.new(0, -100))
		local shot = firstShot(m)
		assert(#shot.targets == 2 and not table.find(shot.targets, far))
	end)
	check("a clean first wave pays its loot with bonus: 20", function()
		local m = siege(1)
		for pad = 1, 8 do m:SetTurret(pad, "Gun", 3) end
		assert(m:StartWave().ok)
		local reward
		for _, e in ipairs(run(m, 120)) do if e.type == "state" and e.reward then reward = e.reward end end
		assert(reward == 20 and m:GetWave() == 2 and m:GetBestWave() == 1, "reward "..tostring(reward))
	end)
	check("loot builds during the wave and burns on defeat; retry restores the wave start", function()
		local m = siege(1)
		-- A later wave: the core's own gun easily handles the first ones alone.
		m:DebugSetWave(12)
		m:StartWave()
		local wallId = wallAt(m, 0, -74)
		m:DebugSpawnAt(Vector2.new(0, -100))
		m:SetTurret(2, "Gun", 3)
		run(m, 2)
		assert(m:GetLoot() > 0, "kills should add loot")
		m:SetTurret(2, nil)
		local defeated = false
		for _, e in ipairs(run(m, 500)) do
			if e.type == "state" and e.state == "Defeated" then defeated = true end
			assert(not e.reward, "defeat must not pay")
		end
		assert(defeated and m:GetLoot() == 0)
		assert(m:Retry().ok and m:GetState() == "Preparing" and m:GetWave() == 12)
		assert(m:GetCoreHealth() == config.Core.MaxHealth and m:GetWallHealth(wallId) == config.Walls.Health[1])
		assert(not m:Retry().ok)
	end)
	check("engineers repair ten points per second each, never past max or a destroyed wall", function()
		local m = siege(1)
		local wallId, dead = wallAt(m, 0, -74), wallAt(m, 84, -9)
		m:DebugSetWallHealth(wallId, 100) m:DebugSetWallHealth(dead, 0)
		m:SetEngineers(2)
		run(m, 5)
		assert(math.abs(m:GetWallHealth(wallId) - 200) < 0.5, "health "..m:GetWallHealth(wallId))
		run(m, 60)
		assert(m:GetWallHealth(wallId) == config.Walls.Health[1] and not m:GetWall(dead).alive)
		assert(not pcall(m.SetEngineers, m, 6))
	end)
	check("expanding replaces the wall with a bigger one; wall upgrades add the difference", function()
		local m = siege(1)
		local inner = wallAt(m, 0, -74)
		m:DebugSetWallHealth(inner, 100)
		m:SetWallLevel(2)
		assert(m:GetWallHealth(inner) == 100 + 240)
		m:SetBaseLevel(2)
		assert(m:GetWall(inner) == nil)
		local outer = wallAt(m, 0, -98)
		assert(m:GetWall(outer).data.level == 2 and m:GetWallHealth(outer) == config.Walls.Health[2])
	end)
	check("every tenth wave sends a Colossus with scaled health", function()
		local m = siege(1)
		m:DebugSetWave(10)
		assert(m:StartWave().ok)
		run(m, 30)
		local found
		for _, zombie in pairs(m:GetZombies()) do if zombie.type == "Colossus" then found = zombie end end
		assert(found and math.abs(found.maxHealth - 1500 * (1 + 0.06 * 9)) < 1e-6)
	end)
	check("siege rejects unknown worlds and pads", function()
		assert(not pcall(siege, 99))
		local m = siege(1)
		assert(not pcall(m.SetTurret, m, 40, "Gun", 1) and not pcall(m.SetTurret, m, 1, "Laser", 1))
	end)

	check("huge waves keep at most 60 zombies alive and make them tougher instead", function()
		local g = require(root.WaveGenerator)
		local m = siege(3)
		m:DebugSetWave(60)
		assert(m:StartWave().ok)
		local peak = 0
		for _ = 1, 400 do
			m:Step(0.05)
			peak = math.max(peak, m:GetAliveCount())
		end
		assert(peak <= config.WaveRules.MaxAlive, "peak "..peak)
		local scale = g.Scale(config, 3, 60)
		assert(scale > 1)
		for _, zombie in pairs(m:GetZombies()) do
			assert(math.abs(zombie.maxHealth - m:HealthFor(zombie.type, 60) * scale) < 1e-3)
		end
	end)
	check("changing worlds keeps the damage on walls and the core", function()
		local a = siege(1)
		local id = wallAt(a, 0, -74)
		a:DebugSetWallHealth(id, 42)
		a:DebugSetCoreHealth(120)
		local b = siege(2)
		b:CopyDefenseFrom(a)
		assert(b:GetWallHealth(id) == 42 and b:GetCoreHealth() == 120)
	end)

	local passed = 0
	for _, r in ipairs(results) do if r.passed then passed += 1 end end
	return {total=#results, passed=passed, results=results}
end
