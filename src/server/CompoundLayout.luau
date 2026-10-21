--!strict
-- Pure geometry of the outpost, shared by the scene builder and the siege simulation.
-- One perimeter wall per base level (only the current one exists in play) and eight build pads per level.
local CompoundLayout = {}

export type Wall = { id: string, level: number, a: Vector2, b: Vector2, center: Vector2 }
export type Pad = { id: number, level: number, position: Vector2, label: string }
export type SpawnPoint = { id: string, direction: string, position: Vector2 }

local DIRECTIONS = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }
local PAD_NAMES = { "СЗ", "С", "СВ", "В", "ЮВ", "Ю", "ЮЗ", "З" }

function CompoundLayout.Directions(): { string }
	return DIRECTIONS
end

function CompoundLayout.Walls(config: any, level: number): { Wall }
	local compound = config.Compound
	local size = compound.Levels[level]
	assert(size, "Unknown base level")
	local hx, hz = size.HalfX, size.HalfZ
	local corners = { Vector2.new(-hx, -hz), Vector2.new(hx, -hz), Vector2.new(hx, hz), Vector2.new(-hx, hz) }
	local sideNames = { "N", "E", "S", "W" }
	local walls: { Wall } = {}
	for side = 1, 4 do
		local from, to = corners[side], corners[side % 4 + 1]
		local count = math.ceil((to - from).Magnitude / compound.SegmentLength - 1e-9)
		for index = 1, count do
			local a = from:Lerp(to, (index - 1) / count)
			local b = from:Lerp(to, index / count)
			table.insert(walls, { id = string.format("L%d_%s%d", level, sideNames[side], index), level = level, a = a, b = b, center = (a + b) / 2 })
		end
	end
	return walls
end

function CompoundLayout.Build(config: any)
	local compound = config.Compound
	local pads: { Pad } = {}
	for level, size in ipairs(compound.Levels) do
		local x, z = size.HalfX - compound.PadInset, size.HalfZ - compound.PadInset
		local spots = { Vector2.new(-x, -z), Vector2.new(0, -z), Vector2.new(x, -z), Vector2.new(x, 0), Vector2.new(x, z), Vector2.new(0, z), Vector2.new(-x, z), Vector2.new(-x, 0) }
		for index, spot in ipairs(spots) do
			local label = "Площадка " .. PAD_NAMES[index] .. (if level > 1 then " · " .. level else "")
			table.insert(pads, { id = #pads + 1, level = level, position = spot, label = label })
		end
	end
	local walls = {}
	for level = 1, #compound.Levels do walls[level] = CompoundLayout.Walls(config, level) end
	local spawnPoints: { SpawnPoint } = {}
	local half = compound.SpawnHalf
	local unit = { N = Vector2.new(0, -1), NE = Vector2.new(1, -1), E = Vector2.new(1, 0), SE = Vector2.new(1, 1), S = Vector2.new(0, 1), SW = Vector2.new(-1, 1), W = Vector2.new(-1, 0), NW = Vector2.new(-1, -1) }
	for _, name in ipairs(DIRECTIONS) do
		local u = unit[name]
		table.insert(spawnPoints, { id = "Spawn_" .. name, direction = name, position = Vector2.new(u.X * half.X, u.Y * half.Y) })
	end
	return { walls = walls, pads = pads, spawnPoints = spawnPoints, core = compound.Core }
end

return CompoundLayout
