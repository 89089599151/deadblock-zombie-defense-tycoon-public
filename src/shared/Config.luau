--!strict
-- Every gameplay number lives here. Plot-local coordinates: x grows east, z grows south.
local MAX_LEVEL = 9

local function freezeAll(list: { any }): { any }
	for index, value in ipairs(list) do if type(value) == "table" then list[index] = table.freeze(value) end end
	return table.freeze(list)
end

-- Droppers: level value doubles; upgrade costs grow ~2.7x per level (first two match the original tycoon).
local droppers = {}
local prices = {0, 100, 350, 750, 1500, 3000}
local values = {5, 8, 15, 25, 45, 80}
local positions = {22, 6, -10, -26, -50, -66}
local travelTimes = {2, 4, 6, 8, 11, 13}
local costFactors = {15, 40, 110, 300, 820, 2250, 6200, 17000}
for id = 1, 6 do
	local value = values[id]
	local levels = {}
	for level = 1, MAX_LEVEL do
		levels[level] = { Value = value * 2 ^ (level - 1), Cost = if level > 1 then value * costFactors[level - 1] else nil }
	end
	droppers[id] = table.freeze({
		Id = id, Name = "Дроппер " .. id, Price = prices[id],
		RequiredExpansion = math.floor((id - 1) / 2), Prerequisite = if id > 1 then id - 1 else nil,
		Z = positions[id], TravelTime = travelTimes[id], Levels = freezeAll(levels),
	})
end

-- Turret roles. Level L multiplies damage by DamageGrowth^(L-1) and range by (1 + RangeGrowth*(L-1)).
-- Upgrade to L+1 costs Price * UpgradeFactor * UpgradeGrowth^(L-1).
local turretTypes = table.freeze({
	Gun = table.freeze({ Order = 1, Name = "Пулемёт", Role = "Частый огонь по ближайшему к ядру. Слаб против брони.",
		Price = 75, Damage = 6, Interval = 0.3, Range = 55, Targeting = "First", DamageType = "Normal",
		UnlockLevel = 1, Color = Color3.fromRGB(237, 159, 65) }),
	Flamer = table.freeze({ Order = 2, Name = "Огнемёт", Role = "Жжёт всех вблизи. Огонь игнорирует броню.",
		Price = 150, Damage = 5, Interval = 0.4, Range = 24, Targeting = "Area", DamageType = "Fire",
		UnlockLevel = 1, Color = Color3.fromRGB(235, 96, 80) }),
	Sniper = table.freeze({ Order = 3, Name = "Снайпер", Role = "Очень далеко и редко, по самому живучему. Пробивает броню.",
		Price = 250, Damage = 70, Interval = 2.2, Range = 120, Targeting = "Strongest", DamageType = "Pierce",
		UnlockLevel = 2, Color = Color3.fromRGB(150, 200, 255) }),
	Tesla = table.freeze({ Order = 4, Name = "Тесла", Role = "Молния прыгает по цепочке целей.",
		Price = 350, Damage = 22, Interval = 1.2, Range = 50, Targeting = "Chain", DamageType = "Normal",
		Chain = 4, ChainRange = 15, ChainFalloff = 0.85, UnlockLevel = 3, Color = Color3.fromRGB(110, 170, 255) }),
	Mortar = table.freeze({ Order = 5, Name = "Миномёт", Role = "Дальний залп по скоплению. Не стреляет вплотную.",
		Price = 500, Damage = 45, Interval = 2.6, Range = 140, MinRange = 22, Splash = 10, Targeting = "Densest", DamageType = "Normal",
		UnlockLevel = 4, Color = Color3.fromRGB(150, 140, 110) }),
})

local zombieTypes = table.freeze({
	Walker = table.freeze({ Name = "Ходячий", Cost = 1, Health = 30, Speed = 7, Damage = 5, AttackInterval = 1, Armor = 0, Bounty = 2, MinWave = 1, Weight = 6, Scale = 1, Color = Color3.fromRGB(120, 172, 98) }),
	Runner = table.freeze({ Name = "Бегун", Cost = 2, Health = 18, Speed = 13, Damage = 3, AttackInterval = 1, Armor = 0, Bounty = 3, MinWave = 3, Weight = 3, Scale = 0.9, Color = Color3.fromRGB(214, 196, 84) }),
	Brute = table.freeze({ Name = "Громила", Cost = 5, Health = 150, Speed = 5, Damage = 12, AttackInterval = 1.2, Armor = 4, Bounty = 10, MinWave = 7, Weight = 2, Scale = 1.4, Color = Color3.fromRGB(112, 122, 140) }),
	Exploder = table.freeze({ Name = "Взрыватель", Cost = 3, Health = 40, Speed = 9, Damage = 0, AttackInterval = 1, Armor = 0, Bounty = 6, MinWave = 9, Weight = 2, Scale = 1.05, WallBlast = 90, DeathBlast = 25, BlastRadius = 7, Color = Color3.fromRGB(226, 92, 62) }),
	Spitter = table.freeze({ Name = "Плевун", Cost = 3, Health = 35, Speed = 6, Damage = 6, AttackInterval = 1.5, Armor = 0, Bounty = 6, MinWave = 5, Weight = 2, Scale = 1, AttackRange = 24, Color = Color3.fromRGB(156, 98, 200) }),
	Healer = table.freeze({ Name = "Лекарь", Cost = 3, Health = 45, Speed = 6.5, Damage = 3, AttackInterval = 1, Armor = 0, Bounty = 7, MinWave = 12, Weight = 2, Scale = 1, HealRadius = 12, HealPerSecond = 6, Color = Color3.fromRGB(90, 220, 170) }),
	Shielder = table.freeze({ Name = "Щитоносец", Cost = 4, Health = 90, Speed = 5.5, Damage = 8, AttackInterval = 1, Armor = 6, Bounty = 9, MinWave = 14, Weight = 2, Scale = 1.25, AuraRadius = 10, AuraArmor = 3, Color = Color3.fromRGB(80, 120, 190) }),
	Flyer = table.freeze({ Name = "Летун", Cost = 3, Health = 25, Speed = 10, Damage = 6, AttackInterval = 1, Armor = 0, Bounty = 6, MinWave = 16, Weight = 2, Scale = 0.9, Flying = true, Color = Color3.fromRGB(130, 80, 160) }),
	Colossus = table.freeze({ Name = "Колосс", Cost = 0, Health = 1500, Speed = 3.5, Damage = 80, AttackInterval = 2, Armor = 8, Bounty = 150, MinWave = 10, Weight = 0, Scale = 2.6, Boss = true, Color = Color3.fromRGB(122, 40, 44) }),
})

return table.freeze({
	GameName = "DEADBLOCK: Аванпост",
	PlotCount = 6,
	Production = table.freeze({ Interval = 2, TravelTime = 2, Value = 5 }),
	Droppers = table.freeze(droppers),
	-- Base levels 2..4: the perimeter grows, a factory section opens (first two), new build pads appear.
	Expansions = freezeAll({ { Price = 250, Prerequisite = 2 }, { Price = 1800, Prerequisite = 4 }, { Price = 9000, Prerequisite = 6 } }),
	MaxLevel = MAX_LEVEL,
	PurchaseDistance = 18,
	ServerStep = 0.05,
	SnapshotInterval = 0.1,
	SellRefund = 0.5,
	-- The core defends itself as a last line: a short-range gun that grows with the base level.
	Core = table.freeze({ MaxHealth = 300, Reach = 10, GunDamage = 4, GunInterval = 0.5, GunRange = 30, GunLevelGrowth = 1.6 }),
	DefeatTips = table.freeze({
		Walker = "Ходячие проломили стену. Укрепи стены у пульта и поставь больше турелей на сторону атаки.",
		Runner = "Бегуны ищут проломы. Найми инженеров — они чинят стены во время боя.",
		Brute = "Громилы в броне. Пулемёт против них слаб — ставь снайпера или огнемёт.",
		Exploder = "Взрыватели рвут стены. Убивай их издалека: снайпер, миномёт, тесла.",
		Spitter = "Плевуны бьют стену издалека. Дальнобойные турели достанут их раньше.",
		Healer = "Лекари лечат стаю. Снайпер и тесла снимают их первыми.",
		Shielder = "Щитоносцы дают броню соседям. Огонь и снайпер её игнорируют.",
		Flyer = "Летуны перелетают стены. Ставь турели ближе к ядру и улучшай их.",
		Colossus = "Колосс очень крепкий. Улучши турели и модули урона перед 10-й волной.",
	}),
	Compound = table.freeze({
		Core = Vector2.new(0, -25),
		SegmentLength = 20,
		WallHeight = 8,
		PadInset = 10,
		-- Half extents of the perimeter for base levels 1..4.
		Levels = freezeAll({ { HalfX = 84, HalfZ = 74 }, { HalfX = 112, HalfZ = 98 }, { HalfX = 140, HalfZ = 122 }, { HalfX = 168, HalfZ = 146 } }),
		SpawnHalf = Vector2.new(300, 260),
		Portal = Vector2.new(-50, -45),
		DirectionNames = table.freeze({ N = "севера", NE = "северо-востока", E = "востока", SE = "юго-востока", S = "юга", SW = "юго-запада", W = "запада", NW = "северо-запада" }),
	}),
	Walls = table.freeze({
		Health = freezeAll({ 300, 540, 970, 1750, 3150, 5670 }),
		UpgradePrices = freezeAll({ 0, 250, 650, 1600, 4000, 10000 }),
	}),
	Engineers = table.freeze({ MaxCount = 5, Prices = freezeAll({ 200, 500, 1200, 3000, 7500 }), RepairRate = 10 }),
	Turrets = table.freeze({ DamageGrowth = 1.55, RangeGrowth = 0.04, UpgradeFactor = 1.6, UpgradeGrowth = 2.2, ArmorFloor = 0.15 }),
	TurretTypes = turretTypes,
	TurretOrder = table.freeze({ "Gun", "Flamer", "Sniper", "Tesla", "Mortar" }),
	ZombieOrder = table.freeze({ "Walker", "Runner", "Brute", "Exploder", "Spitter", "Colossus", "Healer", "Shielder", "Flyer" }),
	-- Difficulty ladder inside every world. A level opens after wave `Unlock` on the previous one.
	Difficulties = freezeAll({
		{ Id = 1, Name = "Обычная", Health = 1, Reward = 1, Unlock = 0 },
		{ Id = 2, Name = "Тяжёлая", Health = 2.2, Reward = 2.5, Unlock = 10 },
		{ Id = 3, Name = "Кошмар", Health = 5, Reward = 6, Unlock = 10 },
	}),
	ZombieTypes = zombieTypes,
	WaveRules = table.freeze({ BaseBudget = 4, Growth = 1.22, CleanBonus = 1.25, HealthPerWave = 0.06, BossEvery = 10, WaveBonusBase = 5, WaveBonusPerWave = 3,
		-- Beyond this budget a wave stops adding bodies and makes every zombie tougher (and richer) instead.
		MaxWaveBudget = 160, MaxWaveZombies = 120, MaxAlive = 60 }),
	Worlds = freezeAll({
		{ Id = 1, Name = "Лес", MaxLevel = 3, Difficulty = 1, HealthMultiplier = 1, DropperMultiplier = 1, RewardMultiplier = 1, PortalPrice = 0, PortalWave = 0,
			ZombieTypes = table.freeze({ "Walker", "Runner", "Brute", "Exploder", "Healer", "Flyer" }), Ground = Color3.fromRGB(66, 89, 63), Fog = Color3.fromRGB(142, 167, 166) },
		{ Id = 2, Name = "Пустошь", MaxLevel = 6, Difficulty = 1.4, HealthMultiplier = 3.5, DropperMultiplier = 4, RewardMultiplier = 4, PortalPrice = 25000, PortalWave = 10,
			ZombieTypes = table.freeze({ "Walker", "Runner", "Brute", "Exploder", "Spitter", "Healer", "Shielder", "Flyer" }), Ground = Color3.fromRGB(150, 128, 92), Fog = Color3.fromRGB(196, 170, 130) },
		{ Id = 3, Name = "Город", MaxLevel = 9, Difficulty = 1.9, HealthMultiplier = 12, DropperMultiplier = 16, RewardMultiplier = 16, PortalPrice = 400000, PortalWave = 10,
			ZombieTypes = table.freeze({ "Walker", "Runner", "Brute", "Exploder", "Spitter", "Healer", "Shielder", "Flyer" }), Ground = Color3.fromRGB(84, 88, 96), Fog = Color3.fromRGB(120, 124, 136) },
	}),
	SpawnInterval = 0.8,
	-- First minutes: a small starting purse, a free first turret, closer spawns for the first waves.
	StartMoney = 100,
	EarlyWaves = 3,
	EarlySpawnFactor = 0.45,
	AutoWaveDelay = 20,
	AutoWaveUnlockStep = 4,
	-- Tutorial chain: each step pays on completion. Target tells the client where to point the beacon.
	Tutorial = freezeAll({
		{ Id = "build", Text = "Построй турель на подсвеченной площадке — первая бесплатно", Reward = 50, Target = "attackPad" },
		{ Id = "start", Text = "Подойди к ядру и начни волну", Reward = 0, Target = "core" },
		{ Id = "wave1", Text = "Отбей первую волну", Reward = 75, Target = "attackPad" },
		{ Id = "dropper2", Text = "Купи второй дроппер на заводе", Reward = 100, Target = "buyDropper2" },
		{ Id = "upgrade", Text = "Улучши любую турель (E у площадки)", Reward = 100, Target = "anyTurret" },
		{ Id = "second", Text = "Построй вторую турель", Reward = 100, Target = "emptyPad" },
		{ Id = "expand", Text = "Открой второй цех завода — у его ворот", Reward = 200, Target = "gate" },
		{ Id = "engineer", Text = "Найми инженера в мастерской", Reward = 150, Target = "workshop" },
		{ Id = "wave5", Text = "Продержись до 5-й волны", Reward = 300, Target = "core" },
		{ Id = "boss", Text = "Победи Колосса на 10-й волне — он откроет портал", Reward = 600, Target = "core" },
	}),
	-- Cores: second currency dropped by zombies (fractions add up during a wave, paid on victory).
	Cores = table.freeze({ Walker = 0.15, Runner = 0.25, Brute = 2, Exploder = 1, Spitter = 1, Colossus = 25, Healer = 1, Shielder = 2, Flyer = 0.5 }),
	Modules = table.freeze({
		Order = table.freeze({ "Damage", "Rate", "Range" }),
		Damage = table.freeze({ Name = "Урон", Per = 0.25 }),
		Rate = table.freeze({ Name = "Скорострельность", Per = 0.2 }),
		Range = table.freeze({ Name = "Дальность", Per = 0.12 }),
		Costs = freezeAll({ 5, 15, 40 }),
	}),
	Overdrive = table.freeze({ Cost = 10, Duration = 300, Multiplier = 2 }),
	Offline = table.freeze({ MaxSeconds = 4 * 3600, Rate = 0.3, MinSeconds = 120 }),
	Daily = table.freeze({
		Count = 3,
		Pool = freezeAll({
			{ Id = "kills", Text = "Убей %d зомби", Goal = 80, Cores = 5, Money = 150 },
			{ Id = "waves", Text = "Отбей %d волн", Goal = 5, Cores = 6, Money = 200 },
			{ Id = "clean", Text = "Отбей %d волны без урона по ядру", Goal = 2, Cores = 8, Money = 100 },
			{ Id = "upgrades", Text = "Сделай %d улучшений", Goal = 3, Cores = 4, Money = 150 },
			{ Id = "builds", Text = "Построй %d турели", Goal = 2, Cores = 4, Money = 100 },
		}),
		-- Login streak rewards for days 1..7 (day 7 repeats afterwards).
		Streak = freezeAll({ { Cores = 3, Money = 100 }, { Cores = 4, Money = 150 }, { Cores = 5, Money = 200 }, { Cores = 6, Money = 300 },
			{ Cores = 8, Money = 400 }, { Cores = 10, Money = 500 }, { Cores = 20, Money = 1000 } }),
	}),
	-- Social layer: plaza hub, helping neighbours, player blaster, the plaza Titan, friend bonus.
	Social = table.freeze({
		Plaza = Vector3.new(0, 0, 0),
		PlazaRadius = 130,
		ArenaHalf = Vector2.new(390, 350),
		HelperDamageBonus = 0.1,
		MaxHelpers = 3,
		HelperRewardShare = 0.15,
		FriendIncomeBonus = 0.1,
		LeaderboardInterval = 5,
		GlobalBoardInterval = 120,
		GlobalSaveInterval = 60,
	}),
	Blaster = table.freeze({ Damage = 8, Interval = 0.25, Range = 170, HitRadius = 3 }),
	Titan = table.freeze({ Health = 4000, HealthPerPlayer = 2500, Every = 900, FirstAfter = 240, Duration = 180, Speed = 4,
		RewardCores = 10, RewardMoney = 500, Orbit = 70 }),
	Sounds = table.freeze({
		Gun = "rbxassetid://88311346538102", Sniper = "rbxassetid://76727380063178", Tesla = "rbxassetid://9114277757",
		Explosion = "rbxassetid://138533090376585", Groan = "rbxassetid://109819443674858", Boss = "rbxassetid://9113980644",
		Siren = "rbxassetid://9111662419", Victory = "rbxassetid://9067124098", Reward = "rbxassetid://85188102085028",
	}),
})
