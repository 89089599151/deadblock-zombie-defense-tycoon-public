--!strict
-- Build panel for turret pads: choose a role, upgrade or sell. The server validates every request;
-- numbers shown here are previews from the shared formulas.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local shared = ReplicatedStorage:WaitForChild("DeadblockShared")
local Config = require(shared:WaitForChild("Config"))
local TurretMath = require(shared:WaitForChild("TurretMath"))
local remotes = ReplicatedStorage:WaitForChild("DeadblockRemotes")
local action = remotes:WaitForChild("TycoonAction") :: RemoteEvent

local colors = {
	panel = Color3.fromRGB(20, 27, 38), card = Color3.fromRGB(30, 39, 52), border = Color3.fromRGB(57, 69, 83),
	text = Color3.fromRGB(241, 244, 247), muted = Color3.fromRGB(170, 184, 198), orange = Color3.fromRGB(255, 143, 92),
	mint = Color3.fromRGB(144, 233, 194), red = Color3.fromRGB(235, 96, 80),
}

local gui = Instance.new("ScreenGui")
gui.Name = "DeadblockBuild"
gui.ResetOnSpawn = false
gui.DisplayOrder = 20
gui.Parent = player:WaitForChild("PlayerGui")

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner") c.CornerRadius = UDim.new(0, radius) c.Parent = parent
end
local function label(parent: Instance, text: string, size: number, color: Color3, bold: boolean?): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1 l.Font = if bold then Enum.Font.GothamBold else Enum.Font.Gotham
	l.TextSize = size l.TextColor3 = color l.Text = text l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextWrapped = true l.Parent = parent
	return l
end
local function button(parent: Instance, text: string): TextButton
	local b = Instance.new("TextButton")
	b.BorderSizePixel = 0 b.Font = Enum.Font.GothamBold b.TextSize = 14 b.Text = text b.AutoButtonColor = true
	b.Parent = parent
	corner(b, 8)
	return b
end

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.55)
panel.Size = UDim2.fromOffset(560, 400)
panel.BackgroundColor3 = colors.panel
panel.BorderSizePixel = 0
panel.Visible = false
panel.Parent = gui
corner(panel, 14)
local stroke = Instance.new("UIStroke") stroke.Color = colors.border stroke.Parent = panel
local scale = Instance.new("UIScale") scale.Parent = panel

local title = label(panel, "", 22, colors.text, true)
title.Position = UDim2.fromOffset(20, 14) title.Size = UDim2.new(1, -80, 0, 30)
local subtitle = label(panel, "", 12, colors.muted)
subtitle.Position = UDim2.fromOffset(20, 44) subtitle.Size = UDim2.new(1, -40, 0, 18)
local close = button(panel, "×")
close.Position = UDim2.new(1, -52, 0, 10) close.Size = UDim2.fromOffset(40, 40) close.BackgroundTransparency = 1
close.TextColor3 = colors.muted close.TextSize = 28

local body = Instance.new("Frame")
body.BackgroundTransparency = 1 body.Position = UDim2.fromOffset(16, 72) body.Size = UDim2.new(1, -32, 1, -88)
body.Parent = panel

local openPad: number? = nil
-- Buttons whose colour depends on the balance; refreshed in place when money changes.
local priced: { { button: TextButton, cost: number, allowed: boolean, cores: boolean? } } = {}

local function paint(entry: { button: TextButton, cost: number, allowed: boolean, cores: boolean? })
	local balance = tonumber(player:GetAttribute(if entry.cores then "DeadblockCores" else "DeadblockMoney")) or 0
	local affordable = entry.allowed and balance >= entry.cost
	entry.button.BackgroundColor3 = if affordable then Color3.fromRGB(255, 143, 92) else Color3.fromRGB(57, 69, 83)
	entry.button.TextColor3 = if affordable then Color3.fromRGB(20, 27, 38) else Color3.fromRGB(170, 184, 198)
	entry.button.AutoButtonColor = affordable
end

local function repaint()
	for _, entry in ipairs(priced) do paint(entry) end
end
local openModel: Model? = nil

local function money(): number
	local value = player:GetAttribute("DeadblockMoney")
	return if typeof(value) == "number" then value else 0
end

local function formatCash(value: number): string
	local digits = string.format("%.0f", math.floor(value))
	return (string.reverse((string.reverse(digits):gsub("(%d%d%d)", "%1 "))):gsub("^ ", ""))
end

local function describe(typeName: string, level: number): string
	local definition = Config.TurretTypes[typeName]
	local damage = TurretMath.Damage(Config, typeName, level)
	local range = TurretMath.Range(Config, typeName, level)
	local perSecond = damage / definition.Interval
	local extra = if definition.Targeting == "Area" then " · по всем рядом"
		elseif definition.Targeting == "Chain" then " · цепь ×" .. definition.Chain
		elseif definition.Targeting == "Densest" then " · взрыв r" .. definition.Splash
		else ""
	return string.format("Урон %.0f (%.0f/с) · дальность %.0f%s", damage, perSecond, range, extra)
end

local function send(payload: { [string]: any })
	payload.requestId = HttpService:GenerateGUID(false)
	action:FireServer(payload)
end

local function clearBody()
	table.clear(priced)
	for _, child in ipairs(body:GetChildren()) do child:Destroy() end
end

local render: () -> ()

local function renderChoices(pad: number)
	local baseLevel = player:GetAttribute("DeadblockBaseLevel")
	baseLevel = if typeof(baseLevel) == "number" then baseLevel else 1
	title.Text = "Построить турель"
	subtitle.Text = "Каждая роль сильна против своих зомби. Сочетай их."
	local list = Instance.new("UIListLayout") list.Padding = UDim.new(0, 8) list.Parent = body
	for _, typeName in ipairs(Config.TurretOrder) do
		local definition = Config.TurretTypes[typeName]
		local card = Instance.new("Frame")
		card.Size = UDim2.new(1, 0, 0, 52) card.BackgroundColor3 = colors.card card.BorderSizePixel = 0 card.Parent = body
		corner(card, 10)
		local swatch = Instance.new("Frame")
		swatch.Size = UDim2.fromOffset(8, 36) swatch.Position = UDim2.fromOffset(10, 8) swatch.BackgroundColor3 = definition.Color swatch.BorderSizePixel = 0 swatch.Parent = card
		corner(swatch, 4)
		local name = label(card, definition.Name, 15, colors.text, true)
		name.Position = UDim2.fromOffset(28, 4) name.Size = UDim2.new(1, -190, 0, 20)
		local role = label(card, definition.Role .. "\n" .. describe(typeName, 1), 11, colors.muted)
		role.Position = UDim2.fromOffset(28, 22) role.Size = UDim2.new(1, -190, 0, 28)
		local locked = definition.UnlockLevel > baseLevel
		local buy = button(card, if locked then "База ур. " .. definition.UnlockLevel else "$ " .. formatCash(definition.Price))
		buy.Position = UDim2.new(1, -150, 0, 10) buy.Size = UDim2.fromOffset(140, 32)
		local entry = { button = buy, cost = definition.Price, allowed = not locked }
		table.insert(priced, entry)
		paint(entry)
		buy.Activated:Connect(function()
			if locked or money() < definition.Price then return end
			send({ kind = "BuildTurret", targetId = pad, turretType = typeName })
		end)
	end
end

local function renderTurret(pad: number, model: Model)
	local typeName = model:GetAttribute("TurretType") :: string
	local level = model:GetAttribute("TurretLevel") :: number
	local cap = model:GetAttribute("LevelCap") :: number
	local definition = Config.TurretTypes[typeName]
	title.Text = definition.Name .. "  ·  ур. " .. level .. "/" .. cap
	subtitle.Text = definition.Role
	local now = label(body, "Сейчас: " .. describe(typeName, level), 14, colors.text)
	now.Position = UDim2.fromOffset(4, 6) now.Size = UDim2.new(1, -8, 0, 22)
	local maxed = level >= cap
	local nextText = if maxed then "Потолок уровня в этом мире. Открой следующий мир порталом." else "Дальше: " .. describe(typeName, level + 1)
	local nextLabel = label(body, nextText, 14, if maxed then colors.orange else colors.mint)
	nextLabel.Position = UDim2.fromOffset(4, 34) nextLabel.Size = UDim2.new(1, -8, 0, 40)
	local cost = if maxed then 0 else TurretMath.UpgradeCost(Config, typeName, level)
	local upgrade = button(body, if maxed then "МАКСИМУМ" else "УЛУЧШИТЬ · $ " .. formatCash(cost))
	upgrade.Position = UDim2.fromOffset(4, 80) upgrade.Size = UDim2.new(1, -8, 0, 44)
	local entry = { button = upgrade, cost = cost, allowed = not maxed }
	table.insert(priced, entry)
	paint(entry)
	upgrade.Activated:Connect(function()
		if not maxed and money() >= cost then send({ kind = "UpgradeTurret", targetId = pad, expectedLevel = level }) end
	end)
	-- Modules: permanent boosts bought with cores dropped by zombies.
	local modulesTitle = label(body, "МОДУЛИ ЗА ЯДРА  ·  у тебя " .. tostring(player:GetAttribute("DeadblockCores") or 0), 11, colors.muted, true)
	modulesTitle.Position = UDim2.fromOffset(4, 130) modulesTitle.Size = UDim2.new(1, -8, 0, 16)
	for index, moduleName in ipairs(Config.Modules.Order) do
		local info = Config.Modules[moduleName]
		local moduleLevel = (model:GetAttribute("Mod" .. moduleName) :: number?) or 0
		local moduleCost = Config.Modules.Costs[moduleLevel + 1]
		local text = string.format("%s +%d%%\n%d/%d · %s", info.Name, math.floor(info.Per * 100 * (moduleLevel + (if moduleCost then 1 else 0))), moduleLevel, #Config.Modules.Costs,
			if moduleCost then moduleCost .. " ядер" else "максимум")
		local moduleButton = button(body, text)
		moduleButton.TextSize = 11
		moduleButton.Position = UDim2.new((index - 1) / 3, 4, 0, 150) moduleButton.Size = UDim2.new(1 / 3, -8, 0, 44)
		local moduleEntry = { button = moduleButton, cost = moduleCost or 0, allowed = moduleCost ~= nil, cores = true }
		table.insert(priced, moduleEntry)
		paint(moduleEntry)
		moduleButton.Activated:Connect(function()
			if moduleCost and (tonumber(player:GetAttribute("DeadblockCores")) or 0) >= moduleCost then
				send({ kind = "UpgradeModule", targetId = pad, module = moduleName, expectedLevel = moduleLevel })
			end
		end)
	end
	local refund = TurretMath.SellValue(Config, typeName, level)
	local sell = button(body, "ПРОДАТЬ · + $ " .. formatCash(refund) .. " (модули пропадут)")
	sell.Position = UDim2.fromOffset(4, 202) sell.Size = UDim2.new(1, -8, 0, 36)
	sell.BackgroundColor3 = colors.card sell.TextColor3 = colors.red
	local confirming = false
	sell.Activated:Connect(function()
		if not confirming then
			confirming = true
			sell.Text = "ТОЧНО ПРОДАТЬ? НАЖМИ ЕЩЁ РАЗ"
			task.delay(2.5, function() if sell.Parent then confirming = false render() end end)
			return
		end
		send({ kind = "SellTurret", targetId = pad, expectedLevel = level })
	end)
	local hint = label(body, "Турели можно продавать и ставить другие — подстраивай оборону под волну.", 11, colors.muted)
	hint.Position = UDim2.fromOffset(4, 246) hint.Size = UDim2.new(1, -8, 0, 30)
end

render = function()
	clearBody()
	local pad, model = openPad, openModel
	if not pad or not model then return end
	if model:GetAttribute("TurretType") then renderTurret(pad, model) else renderChoices(pad) end
end

local connections: { RBXScriptConnection } = {}
local function closePanel()
	for _, c in ipairs(connections) do c:Disconnect() end
	table.clear(connections)
	openPad, openModel = nil, nil
	panel.Visible = false
	clearBody()
end

ProximityPromptService.PromptTriggered:Connect(function(prompt, triggering)
	if triggering ~= player or prompt.Name ~= "PadPrompt" then return end
	local model = prompt:FindFirstAncestorOfClass("Model")
	local baseModel = model and model.Parent and model.Parent.Parent
	if not model or not baseModel or baseModel:GetAttribute("OwnerUserId") ~= player.UserId then return end
	closePanel()
	openPad = model:GetAttribute("Pad") :: number
	openModel = model
	for _, attribute in ipairs({ "TurretType", "TurretLevel", "LevelCap", "Open", "ModDamage", "ModRate", "ModRange" }) do
		table.insert(connections, model:GetAttributeChangedSignal(attribute):Connect(render))
	end
	table.insert(connections, player:GetAttributeChangedSignal("DeadblockMoney"):Connect(repaint))
	table.insert(connections, player:GetAttributeChangedSignal("DeadblockCores"):Connect(repaint))
	panel.Visible = true
	render()
end)

close.Activated:Connect(closePanel)
UserInputService.InputBegan:Connect(function(input, processed)
	if not processed and input.KeyCode == Enum.KeyCode.Escape and panel.Visible then closePanel() end
end)

-- Close when the player walks away from the pad.
RunService.Heartbeat:Connect(function()
	if not panel.Visible or not openModel then return end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local plate = openModel:FindFirstChild("Plate") :: BasePart?
	if not root or not plate or (root.Position - plate.Position).Magnitude > 24 then closePanel() end
end)

local function layout()
	local size = gui.AbsoluteSize
	scale.Scale = math.min(1, (size.X - 32) / 560, (size.Y - 40) / 400)
end
gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
layout()
