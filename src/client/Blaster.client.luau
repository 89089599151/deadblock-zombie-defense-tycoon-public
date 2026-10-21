--!strict
-- Blaster: sends only the aim point; the server decides hits. Draws the shot immediately for feel.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local SoundService = game:GetService("SoundService")

local player = Players.LocalPlayer
local mouse = player:GetMouse()
local Config = require(ReplicatedStorage:WaitForChild("DeadblockShared"):WaitForChild("Config"))
local remote = ReplicatedStorage:WaitForChild("DeadblockRemotes"):WaitForChild("Blaster") :: RemoteEvent

local lastShot = 0

local function tracer(from: Vector3, to: Vector3)
	local length = (to - from).Magnitude
	if length < 0.5 then return end
	local beam = Instance.new("Part")
	beam.Anchored = true beam.CanCollide = false beam.CanQuery = false beam.CanTouch = false beam.CastShadow = false
	beam.Material = Enum.Material.Neon beam.Color = Color3.fromRGB(120, 210, 255)
	beam.Size = Vector3.new(0.22, 0.22, length)
	beam.CFrame = CFrame.lookAt(from, to) * CFrame.new(0, 0, -length / 2)
	beam.Parent = workspace
	TweenService:Create(beam, TweenInfo.new(0.1), { Transparency = 1 }):Play()
	Debris:AddItem(beam, 0.15)
end

local function hook(tool: Instance)
	if not tool:IsA("Tool") or tool.Name ~= "Бластер" or tool:GetAttribute("Hooked") then return end
	tool:SetAttribute("Hooked", true)
	tool.Activated:Connect(function()
		local now = os.clock()
		if now - lastShot < Config.Blaster.Interval then return end
		lastShot = now
		local handle = tool:FindFirstChild("Handle") :: BasePart?
		local aim = mouse.Hit.Position
		remote:FireServer(aim)
		if handle then
			local from = handle.Position
			local direction = aim - from
			local reach = math.min(direction.Magnitude, Config.Blaster.Range)
			tracer(from, from + (if direction.Magnitude > 0 then direction.Unit else Vector3.zAxis) * reach)
		end
		local sound = Instance.new("Sound")
		sound.SoundId = Config.Sounds.Gun sound.Volume = 0.3 sound.PlaybackSpeed = 1.4
		sound.Parent = SoundService
		sound:Play()
		Debris:AddItem(sound, 3)
	end)
end

local function watch(container: Instance)
	for _, child in ipairs(container:GetChildren()) do hook(child) end
	container.ChildAdded:Connect(hook)
end

watch(player:WaitForChild("Backpack"))
player.CharacterAdded:Connect(function(character) watch(character) end)
if player.Character then watch(player.Character) end
player.ChildAdded:Connect(function(child) if child:IsA("Backpack") then watch(child) end end)
