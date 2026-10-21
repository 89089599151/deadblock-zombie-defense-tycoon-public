-- Edit-mode Command Bar / MCP execute_luau. Serves files from `python -m http.server 8765` in the repo root.
-- Set ONLY to a list of source paths to deploy a subset, or nil for everything that exists on disk.
local ONLY: {string}? = nil
local HttpService = game:GetService("HttpService")
local base = "http://127.0.0.1:8765/"
local wasEnabled = HttpService.HttpEnabled
HttpService.HttpEnabled = true
local installed, skipped = {}, {}
local ok, err = pcall(function()
	local manifest = HttpService:JSONDecode(HttpService:GetAsync(base .. "tools/manifest.json", true))
	for _, entry in ipairs(manifest.entries) do
		local target, className, source = entry[1], entry[2], entry[3]
		local wanted = ONLY == nil or table.find(ONLY :: {string}, source) ~= nil
		local fetched, content = pcall(function() return HttpService:GetAsync(base .. source, true) end)
		if wanted and fetched then
			local segments = string.split(target, "/")
			local parent: Instance = game:GetService(segments[1])
			for i = 2, #segments - 1 do
				local nextNode = parent:FindFirstChild(segments[i])
				if not nextNode then nextNode = Instance.new("Folder") nextNode.Name = segments[i] nextNode.Parent = parent end
				parent = nextNode :: Instance
			end
			local name = segments[#segments]
			local node = parent:FindFirstChild(name)
			if node then assert(node.ClassName == className, "Class conflict: " .. target)
			else node = Instance.new(className) node.Name = name node.Parent = parent end
			(node :: any).Source = content
			table.insert(installed, target)
		elseif wanted then table.insert(skipped, source) end
	end
	local remotes = game.ReplicatedStorage:FindFirstChild("DeadblockRemotes")
	if not remotes then remotes = Instance.new("Folder") remotes.Name = "DeadblockRemotes" remotes.Parent = game.ReplicatedStorage end
	for _, name in ipairs({"TycoonAction", "Feedback", "CombatAction"}) do
		if not remotes:FindFirstChild(name) then local e = Instance.new("RemoteEvent") e.Name = name e.Parent = remotes end
	end
end)
HttpService.HttpEnabled = wasEnabled
return {ok = ok, err = err, installed = #installed, skipped = skipped}
