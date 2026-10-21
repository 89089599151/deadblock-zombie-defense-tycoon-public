--!strict
-- Turret and progression formulas shared by the server (authoritative) and the client (UI previews only).
local TurretMath = {}

function TurretMath.Damage(config: any, typeName: string, level: number): number
	local definition = config.TurretTypes[typeName]
	return definition.Damage * config.Turrets.DamageGrowth ^ (level - 1)
end

function TurretMath.Range(config: any, typeName: string, level: number): number
	local definition = config.TurretTypes[typeName]
	return definition.Range * (1 + config.Turrets.RangeGrowth * (level - 1))
end

-- Price of upgrading from `level` to `level + 1`.
function TurretMath.UpgradeCost(config: any, typeName: string, level: number): number
	local definition = config.TurretTypes[typeName]
	return math.floor(definition.Price * config.Turrets.UpgradeFactor * config.Turrets.UpgradeGrowth ^ (level - 1) + 0.5)
end

-- Total money spent to own a turret of this type at this level.
function TurretMath.Invested(config: any, typeName: string, level: number): number
	local total = config.TurretTypes[typeName].Price
	for step = 1, level - 1 do total += TurretMath.UpgradeCost(config, typeName, step) end
	return total
end

function TurretMath.SellValue(config: any, typeName: string, level: number): number
	return math.floor(TurretMath.Invested(config, typeName, level) * config.SellRefund)
end

-- Damage after armor: normal hits lose the armor value but keep at least ArmorFloor of the hit.
function TurretMath.AfterArmor(config: any, damage: number, damageType: string, armor: number): number
	if damageType ~= "Normal" or armor <= 0 then return damage end
	return math.max(damage * config.Turrets.ArmorFloor, damage - armor)
end

function TurretMath.LevelCap(config: any, worldId: number): number
	local world = config.Worlds[worldId]
	return if world then world.MaxLevel else 3
end

function TurretMath.WallCap(config: any, worldId: number): number
	return math.min(#config.Walls.Health, TurretMath.LevelCap(config, worldId))
end

return TurretMath
