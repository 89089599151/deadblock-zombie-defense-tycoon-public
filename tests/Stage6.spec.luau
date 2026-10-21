-- Saves: session locks, failure handling and round trips through a fake DataStore.
return function(root, config)
	local results = {}
	local function check(name, body)
		local ok, err = pcall(body)
		table.insert(results, {name=name, passed=ok, message=if ok then "PASS" else tostring(err)})
	end
	local SaveService = require(root.SaveService)
	local function fakeStore()
		local store = { data = {}, failures = 0 }
		function store:UpdateAsync(key, transform)
			if self.failures > 0 then self.failures -= 1 error("DataStore unavailable") end
			local current = self.data[key]
			local copy = if current then table.clone(current) else nil
			local nextValue = transform(copy)
			if nextValue ~= nil then self.data[key] = nextValue end
			return if nextValue ~= nil then nextValue else current
		end
		return store
	end
	local now = 1000
	local function service(store, job) local s = SaveService.new(store, job, function() return now end) s.wait = function() end return s end

	check("a new player loads with no profile and takes the lock", function()
		local store = fakeStore()
		local ok, profile = service(store, "A"):Load(1)
		assert(ok and profile == nil and store.data.u_1.lock.job == "A")
	end)
	check("saved profiles load back", function()
		local store = fakeStore()
		local a = service(store, "A")
		a:Load(1)
		assert(a:Save(1, { schema = 1, money = 77 }, true))
		local ok, profile = service(store, "B"):Load(1)
		assert(ok and profile.money == 77)
	end)
	check("a profile locked by a live server is refused and not overwritten", function()
		local store = fakeStore()
		local a, b = service(store, "A"), service(store, "B")
		a:Load(1) a:Save(1, { schema = 1, money = 10 })
		local ok, _, reason = b:Load(1)
		assert(not ok and reason == "locked")
		local saved, why = b:Save(1, { schema = 1, money = 0 })
		assert(not saved and why == "locked" and store.data.u_1.profile.money == 10)
	end)
	check("an expired lock from a crashed server can be taken over", function()
		local store = fakeStore()
		service(store, "A"):Load(1)
		now += 500
		local ok = service(store, "B"):Load(1)
		assert(ok and store.data.u_1.lock.job == "B")
	end)
	check("a failing store reports unavailable after retries and writes nothing", function()
		local store = fakeStore()
		store.failures = 10
		local ok, _, reason = service(store, "A"):Load(1)
		assert(not ok and reason == "unavailable" and store.data.u_1 == nil)
	end)
	check("a transient failure is retried", function()
		local store = fakeStore()
		store.failures = 2
		local ok = service(store, "A"):Load(1)
		assert(ok)
	end)
	check("a full tycoon survives save and load", function()
		local Tycoon = require(root.TycoonModel)
		local t = Tycoon.new(config, 5)
		t:Credit(3000)
		t:Apply(5, { kind = "BuildTurret", targetId = 2, turretType = "Gun", requestId = "r1" })
		t:RecordWave(4, 3)
		local store = fakeStore()
		local s = service(store, "A")
		s:Load(5)
		assert(s:Save(5, t:ToProfile(), true))
		local _, profile = service(store, "B"):Load(5)
		local restored = Tycoon.FromProfile(config, 5, profile)
		assert(restored.money == t.money and restored.turrets[2].type == "Gun" and restored:GetProgress().wave == 4)
	end)

	check("a delayed older save never overwrites a newer one", function()
		local store = fakeStore()
		local s = service(store, "A")
		s:Load(1)
		assert(s:Save(1, { schema = 1, money = 50 }, true, 5))
		local ok, reason = s:Save(1, { schema = 1, money = 10 }, false, 4)
		assert(not ok and reason == "stale" and store.data.u_1.profile.money == 50)
		assert(store.data.u_1.lock == nil, "a late write must not re-take the lock")
	end)
	check("release frees a lock taken by a load", function()
		local store = fakeStore()
		local s = service(store, "A")
		s:Load(1)
		assert(s:Release(1) and store.data.u_1.lock == nil)
		assert(service(store, "B"):Load(1))
	end)

	local passed = 0
	for _, r in ipairs(results) do if r.passed then passed += 1 end end
	return {total=#results, passed=passed, results=results}
end
