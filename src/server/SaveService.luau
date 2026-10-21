--!strict
-- Player profiles in a DataStore with a session lock, so two servers never overwrite each other and a
-- failed load never writes an empty profile over real progress. The store is injected (tests use a fake).
local SaveService = {}
SaveService.__index = SaveService

local LOCK_TIMEOUT = 120 -- seconds after which a lock from a crashed server may be taken over

export type Store = { UpdateAsync: (any, string, (any) -> any) -> any }

function SaveService.new(store: any, jobId: string, clock: (() -> number)?)
	return setmetatable({ store = store, jobId = jobId, clock = clock or os.time, retries = 3, wait = task.wait }, SaveService)
end

local function key(userId: number): string
	return "u_" .. tostring(userId)
end

function SaveService:_update(userId: number, transform: (any) -> any): (boolean, any)
	local lastError = nil
	for attempt = 1, self.retries do
		local ok, value = pcall(function() return self.store:UpdateAsync(key(userId), transform) end)
		if ok then return true, value end
		lastError = value
		if attempt < self.retries then self.wait(attempt) end
	end
	return false, lastError
end

-- Returns ok, profile (nil for a brand-new player), reason, sequence. On ok the session lock belongs to this server.
function SaveService:Load(userId: number): (boolean, any, string?, number)
	local lockedBy: string? = nil
	local ok, stored = self:_update(userId, function(data)
		data = if type(data) == "table" then data else {}
		local lock = data.lock
		if type(lock) == "table" and lock.job ~= self.jobId and self.clock() - (lock.at or 0) < LOCK_TIMEOUT then
			lockedBy = lock.job
			return nil -- abort: another live server owns this profile
		end
		data.lock = { job = self.jobId, at = self.clock() }
		return data
	end)
	if not ok then return false, nil, "unavailable", 0 end
	if lockedBy then return false, nil, "locked", 0 end
	local sequence = if type(stored) == "table" and type(stored.seq) == "number" then stored.seq else 0
	return true, if type(stored) == "table" then stored.profile else nil, nil, sequence
end

-- Frees this server's lock without writing a profile (player left before playing).
function SaveService:Release(userId: number): boolean
	local ok = self:_update(userId, function(data)
		if type(data) ~= "table" or type(data.lock) ~= "table" or data.lock.job ~= self.jobId then return nil end
		data.lock = nil
		return data
	end)
	return ok
end

-- Writes the profile only while this server still owns the lock and only if `sequence` is newer than
-- the stored one, so a delayed autosave can never overwrite the final save. `release` frees the lock.
function SaveService:Save(userId: number, profile: any, release: boolean?, sequence: number?): (boolean, string?)
	local stolen, stale = false, false
	local ok = self:_update(userId, function(data)
		data = if type(data) == "table" then data else {}
		local lock = data.lock
		if type(lock) == "table" and lock.job ~= self.jobId then
			stolen = true
			return nil
		end
		if sequence and type(data.seq) == "number" and sequence <= data.seq then
			stale = true
			return nil
		end
		if sequence and lock == nil and data.profile ~= nil and data.released then
			stale = true -- the session already ended; nothing may write after its final save
			return nil
		end
		data.profile = profile
		data.seq = sequence or data.seq
		data.released = release == true
		data.savedAt = self.clock()
		data.lock = if release then nil else { job = self.jobId, at = self.clock() }
		return data
	end)
	if not ok then return false, "unavailable" end
	if stolen then return false, "locked" end
	if stale then return false, "stale" end
	return true, nil
end

return SaveService
