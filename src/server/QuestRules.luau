--!strict
-- Pure rules for the tutorial chain: when a step is done and what the guide beacon should point at.
local QuestRules = {}

local DIRECTION_PAD = { NW = 1, N = 2, NE = 3, E = 4, SE = 5, S = 6, SW = 7, W = 8 }

export type SiegeInfo = { state: string, best: number, attackDirection: string? }

function QuestRules.Current(config: any, tycoon: any): any
	return config.Tutorial[tycoon.tutorial]
end

local function turretCount(tycoon: any): number
	local count = 0
	for _ in pairs(tycoon.turrets) do count += 1 end
	return count
end

function QuestRules.IsDone(id: string, tycoon: any, siege: SiegeInfo): boolean
	if id == "build" then return turretCount(tycoon) >= 1
	elseif id == "start" then return siege.state == "Active" or siege.best >= 1
	elseif id == "wave1" then return siege.best >= 1
	elseif id == "dropper2" then return tycoon.droppers[2] ~= nil
	elseif id == "upgrade" then
		for _, turret in pairs(tycoon.turrets) do if turret.level >= 2 then return true end end
		return false
	elseif id == "second" then return turretCount(tycoon) >= 2
	elseif id == "expand" then return tycoon.expansion >= 1
	elseif id == "engineer" then return tycoon.engineers >= 1
	elseif id == "wave5" then return siege.best >= 5
	elseif id == "boss" then return siege.best >= 10
	end
	return false
end

-- Pad facing the coming attack (first ring of pads), so the first turret is placed where it matters.
function QuestRules.AttackPad(direction: string?): number
	return DIRECTION_PAD[direction or "N"] or 2
end

-- Returns a target descriptor understood by the client guide: "pad:N", "dropper:N", "core", "console", "workshop".
function QuestRules.Target(definition: any, tycoon: any, siege: SiegeInfo): string?
	if not definition then return nil end
	local target = definition.Target
	local attackPad = QuestRules.AttackPad(siege.attackDirection)
	if target == "attackPad" then return "pad:" .. attackPad
	elseif target == "buyDropper2" then return "dropper:2"
	elseif target == "gate" then return "gate:" .. math.min(tycoon.expansion + 1, 2)
	elseif target == "anyTurret" then
		if tycoon.turrets[attackPad] then return "pad:" .. attackPad end
		for pad = 1, 32 do if tycoon.turrets[pad] then return "pad:" .. pad end end
		return "pad:" .. attackPad
	elseif target == "emptyPad" then
		-- Neighbours of the attack pad first, then any open first-ring pad.
		for _, offset in ipairs({ 1, -1, 2, -2, 3, -3, 4 }) do
			local pad = (attackPad - 1 + offset) % 8 + 1
			if not tycoon.turrets[pad] then return "pad:" .. pad end
		end
		return nil
	end
	return target
end

return QuestRules
