-- Development helper installed at ServerStorage.DeadblockTools.DevTool (not part of the shipped game).
-- Usage in execute_luau: return require(game.ServerStorage.DeadblockTools.DevTool:Clone())({deploy=true,test=true,build=false})
local H = game:GetService("HttpService")
local BASE = "http://127.0.0.1:8765/"

local function fetch(path)
	local was = H.HttpEnabled
	H.HttpEnabled = true
	local ok, content = pcall(function() return H:GetAsync(BASE .. path, true) end)
	H.HttpEnabled = was
	return ok, content
end

local function deploy()
	local ok, manifestText = fetch("tools/manifest.json")
	assert(ok, "manifest: " .. tostring(manifestText))
	local manifest = H:JSONDecode(manifestText)
	local installed, skipped = 0, {}
	for _, entry in ipairs(manifest.entries) do
		local target, className, source = entry[1], entry[2], entry[3]
		local fetched, content = fetch(source)
		if fetched then
			local segments = string.split(target, "/")
			local parent = game:GetService(segments[1])
			for i = 2, #segments - 1 do
				local nextNode = parent:FindFirstChild(segments[i])
				if not nextNode then nextNode = Instance.new("Folder") nextNode.Name = segments[i] nextNode.Parent = parent end
				parent = nextNode
			end
			local node = parent:FindFirstChild(segments[#segments])
			if node then assert(node.ClassName == className, "Class conflict: " .. target) end
			-- ModuleScripts are recreated so later requires never return a stale cached result.
			if node and className == "ModuleScript" then node:Destroy() node = nil end
			if not node then node = Instance.new(className) node.Name = segments[#segments] node.Parent = parent end
			node.Source = content
			installed += 1
		else table.insert(skipped, source) end
	end
	local remotes = game.ReplicatedStorage:FindFirstChild("DeadblockRemotes")
	if not remotes then remotes = Instance.new("Folder") remotes.Name = "DeadblockRemotes" remotes.Parent = game.ReplicatedStorage end
	for _, name in ipairs({"TycoonAction", "Feedback", "CombatAction", "SiegeSnapshot", "SiegeEvents", "Blaster", "PlazaSnapshot"}) do
		if not remotes:FindFirstChild(name) then local e = Instance.new("RemoteEvent") e.Name = name e.Parent = remotes end
	end
	return {installed = installed, skipped = skipped}
end

local function fresh()
	local tmp = Instance.new("Folder") tmp.Name = "_FreshTmp" tmp.Parent = game.ServerStorage
	local root = game.ServerScriptService.Deadblock:Clone() root.Parent = tmp
	local shared = game.ReplicatedStorage.DeadblockShared:Clone() shared.Parent = tmp
	local tests = game.ServerStorage.DeadblockTests:Clone() tests.Parent = tmp
	return tmp, root, shared, tests
end

local function test()
	local tmp, root, shared, tests = fresh()
	local config = require(shared.Config)
	local lines = {}
	for _, name in ipairs({"Stage1Spec", "Stage2Spec", "Stage3Spec", "Stage4Spec", "Stage5Spec", "Stage6Spec", "Stage7Spec", "Stage8Spec", "Stage9Spec", "Stage10Spec"}) do
		local ok, res = pcall(function() return require(tests[name])(root, config) end)
		if not ok then table.insert(lines, name .. " ERROR " .. tostring(res))
		else
			table.insert(lines, name .. ": " .. res.passed .. "/" .. res.total)
			for _, r in ipairs(res.results) do if not r.passed then table.insert(lines, "  FAIL " .. r.name .. " -> " .. tostring(r.message)) end end
		end
	end
	tmp:Destroy()
	return lines
end

local function build()
	local ok, source = fetch("tools/BuildOutpost.luau")
	assert(ok, tostring(source))
	local tmp, root, shared = fresh()
	local builder = Instance.new("ModuleScript") builder.Name = "Builder" builder.Source = source builder.Parent = tmp
	local config = require(shared.Config)
	local ok2, result = pcall(function() return require(builder)(config, require(root.BaseService), require(root.TycoonModel), require(root.CompoundLayout)) end)
	tmp:Destroy()
	assert(ok2, tostring(result))
	return result
end

return function(options)
	local out = {}
	if options.deploy then out.deploy = deploy() end
	if options.test then out.test = test() end
	if options.build then out.build = build() end
	return H:JSONEncode(out)
end
