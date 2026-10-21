--!strict
-- Guide beacon for the current tutorial step: a glowing beam from the player to the target, a bobbing
-- arrow above it and an outline. Reads only the attributes the server publishes.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local GOLD = Color3.fromRGB(255, 200, 80)

local targetAttachment: Attachment? = nil
local playerAttachment: Attachment? = nil
local beam: Beam? = nil
local arrow: BillboardGui? = nil
local highlight: Highlight? = nil
local currentKey: string? = nil

local function base(): Instance?
	local id = player:GetAttribute("DeadblockBaseId")
	local world = workspace:FindFirstChild("DeadblockWorld")
	return if id and world then world:FindFirstChild("Bases") and (world :: any).Bases:FindFirstChild("Base" .. id) else nil
end

local function resolve(descriptor: string): BasePart?
	local b = base() :: any
	if not b then return nil end
	local kind, value = string.match(descriptor, "^(%a+):?(%d*)$")
	local index = tonumber(value)
	if kind == "pad" and index then
		local pad = b.Pads:FindFirstChild("Pad" .. index)
		return pad and pad:FindFirstChild("Plate")
	elseif kind == "dropper" and index then
		local buy = b.BuyPads:FindFirstChild("BuyDropper" .. index)
		if buy and buy.Pad.Transparency < 1 then return buy.Pad end
		local dropper = b.Droppers:FindFirstChild("Dropper" .. index)
		return dropper and dropper:FindFirstChild("MachineBody")
	elseif kind == "gate" and index then
		local gate = b.Gates:FindFirstChild("Gate" .. index)
		return gate and gate:FindFirstChild("Door")
	elseif kind == "core" then return b.Combat.Core.CoreBody
	elseif kind == "console" then return b.Combat.Console.Pad
	elseif kind == "workshop" then return b.Combat.Workshop.Door
	end
	return nil
end

local function clear()
	for _, item in ipairs({ targetAttachment, beam, arrow, highlight } :: { Instance? }) do
		if item then item:Destroy() end
	end
	targetAttachment, beam, arrow, highlight, currentKey = nil, nil, nil, nil, nil
end

local function ensurePlayerAttachment(): Attachment?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return nil end
	if playerAttachment and playerAttachment.Parent == root then return playerAttachment end
	local attachment = Instance.new("Attachment")
	attachment.Name = "DeadblockGuide"
	attachment.Position = Vector3.new(0, -1.5, 0)
	attachment.Parent = root
	playerAttachment = attachment
	return attachment
end

local function refresh()
	local descriptor = player:GetAttribute("DeadblockQuestTarget")
	if typeof(descriptor) ~= "string" then clear() return end
	local part = resolve(descriptor)
	local from = ensurePlayerAttachment()
	if not part or not from then clear() return end
	local key = descriptor .. ":" .. part:GetFullName()
	if key == currentKey and beam and beam.Attachment0 == from then return end
	clear()
	currentKey = key
	local to = Instance.new("Attachment")
	to.Name = "DeadblockGuideTarget"
	to.Position = Vector3.new(0, part.Size.Y / 2 + 0.5, 0)
	to.Parent = part
	targetAttachment = to
	local b = Instance.new("Beam")
	b.Attachment0 = from b.Attachment1 = to
	b.Color = ColorSequence.new(GOLD)
	b.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0.15) })
	b.Width0, b.Width1 = 0.4, 0.9
	b.FaceCamera = true b.LightEmission = 1 b.Segments = 12
	b.Parent = to
	beam = b
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(60, 60) gui.AlwaysOnTop = true gui.MaxDistance = 400
	gui.StudsOffset = Vector3.new(0, part.Size.Y / 2 + 6, 0) gui.Adornee = part gui.Parent = to
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1) label.BackgroundTransparency = 1 label.Text = "▼"
	label.TextScaled = true label.Font = Enum.Font.GothamBold label.TextColor3 = GOLD label.TextStrokeTransparency = 0.3
	label.Parent = gui
	arrow = gui
	local h = Instance.new("Highlight")
	h.Adornee = part h.FillTransparency = 0.75 h.FillColor = GOLD h.OutlineColor = GOLD h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	h.Parent = to
	highlight = h
end

for _, attribute in ipairs({ "DeadblockQuestTarget", "DeadblockBaseId" }) do
	player:GetAttributeChangedSignal(attribute):Connect(refresh)
end
player.CharacterAdded:Connect(function() task.wait(0.5) refresh() end)

-- Bob the arrow and re-resolve occasionally (targets appear when the base changes).
local elapsed, clock = 0, 0
RunService.RenderStepped:Connect(function(dt)
	elapsed += dt
	clock += dt
	if arrow then
		local part = arrow.Adornee :: BasePart?
		if part then arrow.StudsOffset = Vector3.new(0, part.Size.Y / 2 + 6 + math.sin(clock * 4) * 0.8, 0) end
	end
	if elapsed > 1 then
		elapsed = 0
		refresh()
	end
end)
refresh()
