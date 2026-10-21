--!strict
-- Place in StarterPlayerScripts. The server owns balances, machines, and upgrade decisions.
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local previousGui = playerGui:FindFirstChild("DeadblockHUD")
if previousGui then
	previousGui:Destroy()
end

local colors = {
	panel = Color3.fromRGB(20, 27, 38),
	border = Color3.fromRGB(57, 69, 83),
	text = Color3.fromRGB(241, 244, 247),
	muted = Color3.fromRGB(170, 184, 198),
	orange = Color3.fromRGB(255, 143, 92),
	mint = Color3.fromRGB(144, 233, 194),
}

local gui = Instance.new("ScreenGui")
gui.Name = "DeadblockHUD"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder = 10
-- Older Studio builds can fall back to the default Roblox inset.
pcall(function()
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
end)

local root = Instance.new("Frame")
root.Name = "SafeArea"
root.Size = UDim2.fromScale(1, 1)
root.BackgroundTransparency = 1
root.Parent = gui

local function frame(name: string, parent: Instance, size: UDim2): Frame
	local node = Instance.new("Frame")
	node.Name = name
	node.Size = size
	node.BorderSizePixel = 0
	node.BackgroundTransparency = 1
	node.Parent = parent
	return node
end

local function label(name: string, parent: Instance, fontSize: number, color: Color3): TextLabel
	local node = Instance.new("TextLabel")
	node.Name = name
	node.BackgroundTransparency = 1
	node.Font = Enum.Font.Gotham
	node.TextSize = fontSize
	node.TextColor3 = color
	node.TextXAlignment = Enum.TextXAlignment.Left
	node.TextYAlignment = Enum.TextYAlignment.Center
	node.Text = ""
	node.Parent = parent
	return node
end

local function panel(node: Frame)
	node.BackgroundColor3 = colors.panel
	node.BackgroundTransparency = 0.08
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 14)
	corner.Parent = node
	local stroke = Instance.new("UIStroke")
	stroke.Color = colors.border
	stroke.Transparency = 0.25
	stroke.Thickness = 1
	stroke.Parent = node
end

local overview = frame("ProductionOverview", root, UDim2.fromOffset(288, 214))
local accent = frame("BrandAccent", overview, UDim2.fromOffset(4, 24))
accent.Position = UDim2.fromOffset(0, 4)
accent.BackgroundColor3 = colors.orange
accent.BackgroundTransparency = 0
local accentCorner = Instance.new("UICorner")
accentCorner.CornerRadius = UDim.new(0, 2)
accentCorner.Parent = accent

local brand = label("Brand", overview, 24, colors.text)
brand.Font = Enum.Font.GothamBold
brand.Position = UDim2.fromOffset(14, 0)
brand.Size = UDim2.new(1, -14, 0, 32)
brand.Text = "DEADBLOCK"

local statusDot = frame("StatusIndicator", overview, UDim2.fromOffset(6, 6))
statusDot.Position = UDim2.fromOffset(1, 44)
statusDot.BackgroundColor3 = colors.orange
statusDot.BackgroundTransparency = 0
local dotCorner = Instance.new("UICorner")
dotCorner.CornerRadius = UDim.new(1, 0)
dotCorner.Parent = statusDot

local stateLabel = label("ProductionState", overview, 11, colors.muted)
stateLabel.Font = Enum.Font.GothamMedium
stateLabel.Position = UDim2.fromOffset(14, 34)
stateLabel.Size = UDim2.new(1, -14, 0, 26)

local cashCard = frame("CashCard", overview, UDim2.new(1, 0, 0, 138))
cashCard.Position = UDim2.fromOffset(0, 68)
panel(cashCard)

local cashTitle = label("CashTitle", cashCard, 11, colors.muted)
cashTitle.Font = Enum.Font.GothamMedium
cashTitle.Position = UDim2.fromOffset(16, 12)
cashTitle.Size = UDim2.new(1, -32, 0, 18)
cashTitle.Text = "НАЛИЧНЫЕ"

local coresLabel = label("Cores", cashCard, 12, colors.orange)
coresLabel.Font = Enum.Font.GothamBold
coresLabel.Position = UDim2.new(0, 16, 0, 12)
coresLabel.Size = UDim2.new(1, -32, 0, 18)
coresLabel.TextXAlignment = Enum.TextXAlignment.Right

local cashValue = label("CashValue", cashCard, 32, colors.mint)
cashValue.Font = Enum.Font.GothamBold
cashValue.Position = UDim2.fromOffset(16, 30)
cashValue.Size = UDim2.new(1, -32, 0, 42)
cashValue.Text = "—"
cashValue.TextScaled = true
local cashTextConstraint = Instance.new("UITextSizeConstraint")
cashTextConstraint.MinTextSize = 16
cashTextConstraint.MaxTextSize = 32
cashTextConstraint.Parent = cashValue

local incomeLabel = label("Income", cashCard, 12, colors.muted)
incomeLabel.Position = UDim2.fromOffset(16, 80)
incomeLabel.Size = UDim2.new(1, -32, 0, 20)

local productionLabel = label("ProductionSummary", cashCard, 11, colors.muted)
productionLabel.Position = UDim2.fromOffset(16, 108)
productionLabel.Size = UDim2.new(1, -32, 0, 18)

local onboarding = frame("FirstStep", root, UDim2.fromOffset(324, 96))
panel(onboarding)
local stepLabel = label("Step", onboarding, 10, colors.orange)
stepLabel.Font = Enum.Font.GothamBold
stepLabel.Position = UDim2.fromOffset(16, 10)
stepLabel.Size = UDim2.new(1, -32, 0, 18)

local stepTitle = label("StepTitle", onboarding, 14, colors.text)
stepTitle.Font = Enum.Font.GothamBold
stepTitle.Position = UDim2.fromOffset(16, 30)
stepTitle.Size = UDim2.new(1, -32, 0, 22)

local stepBody = label("StepBody", onboarding, 12, colors.muted)
stepBody.Position = UDim2.fromOffset(16, 54)
stepBody.Size = UDim2.new(1, -32, 0, 32)
stepBody.TextYAlignment = Enum.TextYAlignment.Top
stepBody.TextWrapped = true

local function formatCash(value: number): string
	local amount = math.floor(math.max(0, value))
	if amount >= 1e12 then
		return string.format("%.1f трлн", amount / 1e12)
	end
	local digits = string.format("%.0f", amount)
	local grouped = string.reverse(digits):gsub("(%d%d%d)", "%1 ")
	return (string.reverse(grouped):gsub("^ ", ""))
end

local function finiteNumber(value: any): number?
	if typeof(value) == "number" and value == value and math.abs(value) < math.huge then
		return value
	end
	return nil
end

local function formatRate(value: number): string
	return (string.format("%.1f", math.max(0, value)):gsub("%.0$", ""):gsub("%.", ","))
end

local upgradePanel = frame("DropperUpgrade", root, UDim2.fromOffset(360, 326))
panel(upgradePanel)
upgradePanel.BackgroundTransparency = 0
upgradePanel.ZIndex = 20
upgradePanel.Visible = false
local upgradeScale = Instance.new("UIScale")
upgradeScale.Parent = upgradePanel

local upgradeEyebrow = label("Eyebrow", upgradePanel, 10, colors.orange)
upgradeEyebrow.Font = Enum.Font.GothamBold
upgradeEyebrow.Position = UDim2.fromOffset(20, 18)
upgradeEyebrow.Size = UDim2.fromOffset(274, 18)
upgradeEyebrow.Text = "ПРОИЗВОДСТВО / УЛУЧШЕНИЕ"

local upgradeTitle = label("DropperTitle", upgradePanel, 22, colors.text)
upgradeTitle.Font = Enum.Font.GothamBold
upgradeTitle.Position = UDim2.fromOffset(20, 42)
upgradeTitle.Size = UDim2.fromOffset(276, 34)

local closeButton = Instance.new("TextButton")
closeButton.Name = "Close"
closeButton.Position = UDim2.new(1, -54, 0, 12)
closeButton.Size = UDim2.fromOffset(42, 42)
closeButton.BackgroundTransparency = 1
closeButton.Font = Enum.Font.GothamMedium
closeButton.Text = "×"
closeButton.TextSize = 28
closeButton.TextColor3 = colors.muted
closeButton.Parent = upgradePanel

local levelLabel = label("Level", upgradePanel, 13, colors.muted)
levelLabel.Position = UDim2.fromOffset(20, 86)
levelLabel.Size = UDim2.fromOffset(320, 24)

local valueCaption = label("ValueCaption", upgradePanel, 10, colors.muted)
valueCaption.Font = Enum.Font.GothamMedium
valueCaption.Position = UDim2.fromOffset(20, 126)
valueCaption.Size = UDim2.fromOffset(320, 18)
valueCaption.Text = "ЗА КАЖДЫЙ БЛОК"

local dropperValue = label("BlockValue", upgradePanel, 28, colors.mint)
dropperValue.Font = Enum.Font.GothamBold
dropperValue.Position = UDim2.fromOffset(20, 146)
dropperValue.Size = UDim2.fromOffset(320, 38)

local upgradeDetail = label("UpgradeDetail", upgradePanel, 12, colors.muted)
upgradeDetail.Position = UDim2.fromOffset(20, 194)
upgradeDetail.Size = UDim2.fromOffset(320, 42)
upgradeDetail.TextWrapped = true
upgradeDetail.TextYAlignment = Enum.TextYAlignment.Top

local upgradeButton = Instance.new("TextButton")
upgradeButton.Name = "Upgrade"
upgradeButton.Position = UDim2.fromOffset(20, 252)
upgradeButton.Size = UDim2.fromOffset(320, 54)
upgradeButton.BorderSizePixel = 0
upgradeButton.Font = Enum.Font.GothamBold
upgradeButton.TextSize = 14
upgradeButton.Parent = upgradePanel
local buttonCorner = Instance.new("UICorner")
buttonCorner.CornerRadius = UDim.new(0, 10)
buttonCorner.Parent = upgradeButton

local toast = frame("FeedbackToast", root, UDim2.fromOffset(400, 64))
panel(toast)
toast.BackgroundTransparency = 0
toast.ZIndex = 30
toast.Visible = false
local toastText = label("Message", toast, 13, colors.text)
toastText.Position = UDim2.fromOffset(16, 10)
toastText.Size = UDim2.new(1, -32, 1, -20)
toastText.TextWrapped = true

local selectedDropper: Model? = nil
local selectedConnections: { RBXScriptConnection } = {}
local actionRemote: RemoteEvent? = nil
local feedbackConnection: RBXScriptConnection? = nil
local pendingRequest: { id: string, targetId: number, expectedLevel: number }? = nil
local canUpgrade = false
local toastRevision = 0
local lastToast = ""
local lastToastAt = 0

local function showToast(message: string, ok: boolean)
	if message == "" or (message == lastToast and os.clock() - lastToastAt < 1.5) then
		return
	end
	lastToast = message
	lastToastAt = os.clock()
	toastRevision += 1
	local revision = toastRevision
	toastText.Text = message
	toastText.TextColor3 = if ok then colors.mint else colors.orange
	toast.Visible = true
	task.delay(3.5, function()
		if revision == toastRevision then
			toast.Visible = false
		end
	end)
end

local function ownsDropper(model: Model): boolean
	local world = workspace:FindFirstChild("DeadblockWorld")
	local id = finiteNumber(model:GetAttribute("DropperId"))
	return world ~= nil and model:IsDescendantOf(world)
		and model:GetAttribute("Owned") == true
		and model:GetAttribute("OwnerUserId") == player.UserId
		and id ~= nil and id >= 1 and id <= 6 and id % 1 == 0
end

local function closeUpgrade()
	for _, connection in selectedConnections do
		connection:Disconnect()
	end
	table.clear(selectedConnections)
	selectedDropper = nil
	canUpgrade = false
	upgradePanel.Visible = false
	onboarding.Visible = true
end

local function renderUpgrade()
	local model = selectedDropper
	if not model then
		return
	end
	if not ownsDropper(model) then
		closeUpgrade()
		return
	end
	local id = finiteNumber(model:GetAttribute("DropperId")) or 1
	local level = finiteNumber(model:GetAttribute("Level")) or 1
	local maxLevel = finiteNumber(model:GetAttribute("MaxLevel")) or 3
	local value = finiteNumber(model:GetAttribute("Value"))
	local cost = finiteNumber(model:GetAttribute("UpgradeCost"))
	local money = finiteNumber(player:GetAttribute("DeadblockMoney"))
	local maximum = level >= maxLevel or cost == 0
	upgradeTitle.Text = "Дроппер " .. tostring(id)
	levelLabel.Text = string.format("Уровень %d / %d", level, maxLevel)
	dropperValue.Text = if value then "$ " .. formatCash(value) else "—"
	canUpgrade = not maximum and pendingRequest == nil and money ~= nil and cost ~= nil
		and cost > 0 and money >= cost and actionRemote ~= nil and actionRemote.Parent ~= nil
	if pendingRequest then
		upgradeButton.Text = "УЛУЧШАЕМ…"
		upgradeDetail.Text = "Подтверждаем улучшение."
	elseif maximum then
		upgradeButton.Text = "МАКСИМАЛЬНЫЙ УРОВЕНЬ"
		upgradeDetail.Text = "Этот дроппер полностью улучшен."
	elseif cost == nil or money == nil or actionRemote == nil then
		upgradeButton.Text = "СИНХРОНИЗАЦИЯ…"
		upgradeDetail.Text = "Получаем данные производства."
	elseif money < cost then
		upgradeButton.Text = "НУЖНО $ " .. formatCash(cost)
		upgradeDetail.Text = "Не хватает $ " .. formatCash(cost - money) .. ". Дождись дохода от производства."
	else
		upgradeButton.Text = "УЛУЧШИТЬ · $ " .. formatCash(cost)
		upgradeDetail.Text = "Улучшение повысит стоимость блоков этого дроппера."
	end
	upgradeButton.Active = canUpgrade
	upgradeButton.Selectable = canUpgrade
	upgradeButton.AutoButtonColor = canUpgrade
	upgradeButton.BackgroundColor3 = if canUpgrade then colors.orange else colors.border
	upgradeButton.TextColor3 = if canUpgrade then colors.panel else colors.muted
end

closeButton.Activated:Connect(closeUpgrade)
player.CharacterRemoving:Connect(closeUpgrade)
UserInputService.InputBegan:Connect(function(input, processed)
	if not processed and input.KeyCode == Enum.KeyCode.Escape and selectedDropper then
		closeUpgrade()
	end
end)

ProximityPromptService.PromptTriggered:Connect(function(prompt, triggeringPlayer)
	if triggeringPlayer ~= player or prompt:GetAttribute("ActionKind") ~= "InspectDropper" then
		return
	end
	local cursor: Instance? = prompt.Parent
	while cursor and cursor ~= workspace do
		if cursor:IsA("Model") and cursor:GetAttribute("DropperId") ~= nil then
			if not ownsDropper(cursor) then
				return
			end
			closeUpgrade()
			selectedDropper = cursor
			for _, attribute in { "DropperId", "OwnerUserId", "Owned", "Level", "Value", "UpgradeCost", "MaxLevel" } do
				table.insert(selectedConnections, cursor:GetAttributeChangedSignal(attribute):Connect(renderUpgrade))
			end
			table.insert(selectedConnections, cursor.AncestryChanged:Connect(renderUpgrade))
			upgradePanel.Visible = true
			onboarding.Visible = false
			renderUpgrade()
			return
		end
		cursor = cursor.Parent
	end
end)

upgradeButton.Activated:Connect(function()
	renderUpgrade()
	local model, remote = selectedDropper, actionRemote
	if not canUpgrade or not model or not remote or pendingRequest then
		return
	end
	local request = {
		id = HttpService:GenerateGUID(false),
		targetId = model:GetAttribute("DropperId") :: number,
		expectedLevel = model:GetAttribute("Level") :: number,
	}
	pendingRequest = request
	renderUpgrade()
	local sent = pcall(function()
		remote:FireServer({
			kind = "UpgradeDropper", targetId = request.targetId,
			expectedLevel = request.expectedLevel, requestId = request.id,
		})
	end)
	if not sent then
		pendingRequest = nil
		showToast("Не удалось отправить улучшение. Попробуй ещё раз.", false)
		renderUpgrade()
		return
	end
	task.delay(5, function()
		if pendingRequest == request then
			pendingRequest = nil
			showToast("Ответ задерживается. Проверь уровень перед повтором.", false)
			renderUpgrade()
		end
	end)
end)

local function attachRemote(child: Instance)
	if not child:IsA("RemoteEvent") then
		return
	end
	if child.Name == "TycoonAction" then
		actionRemote = child
		renderUpgrade()
	elseif child.Name == "Feedback" then
		if feedbackConnection then
			feedbackConnection:Disconnect()
		end
		feedbackConnection = child.OnClientEvent:Connect(function(payload)
			if typeof(payload) ~= "table" then
				return
			end
			if pendingRequest and payload.requestId == pendingRequest.id then
				pendingRequest = nil
			end
			if typeof(payload.message) == "string" then
				showToast(payload.message, payload.ok == true)
			end
			renderUpgrade()
		end)
	end
end

local function attachFolder(folder: Instance)
	if folder.Name ~= "DeadblockRemotes" then
		return
	end
	for _, child in folder:GetChildren() do
		attachRemote(child)
	end
	folder.ChildAdded:Connect(attachRemote)
	folder.ChildRemoved:Connect(function(child)
		if child == actionRemote then
			actionRemote = nil
			renderUpgrade()
		end
	end)
end

ReplicatedStorage.ChildAdded:Connect(attachFolder)
local remotes = ReplicatedStorage:FindFirstChild("DeadblockRemotes")
if remotes then
	attachFolder(remotes)
end

local function render()
	local money = finiteNumber(player:GetAttribute("DeadblockMoney"))
	local baseId = finiteNumber(player:GetAttribute("DeadblockBaseId"))
	local income = finiteNumber(player:GetAttribute("DeadblockIncome")) or 2.5
	local dropperCount = finiteNumber(player:GetAttribute("DeadblockDropperCount"))
	local expansion = finiteNumber(player:GetAttribute("DeadblockExpansion"))
	local status = player:GetAttribute("DeadblockStatus")
	local ready = status == "ready" and baseId ~= nil and money ~= nil
	cashValue.Text = if money ~= nil then "$ " .. formatCash(money) else "—"
	local cores = finiteNumber(player:GetAttribute("DeadblockCores"))
	coresLabel.Text = if cores then "◆ " .. formatCash(cores) .. " ядер" else ""
	local overdrive = finiteNumber(player:GetAttribute("DeadblockOverdrive")) or 0
	statusDot.BackgroundColor3 = if ready then colors.mint else colors.orange
	local baseLevel = finiteNumber(player:GetAttribute("DeadblockBaseLevel")) or 1
	local saveStatus = player:GetAttribute("DeadblockSaveStatus")
	productionLabel.Text = if ready then string.format("Дропперы %d/6  ·  База ур. %d/4%s", dropperCount or 0, baseLevel, if saveStatus == "ok" then "" else "  ·  без сохранения") else ""

	if status == "full" then
		stateLabel.Text = "ВСЕ БАЗЫ ЗАНЯТЫ"
		incomeLabel.Text = "Ожидание свободной базы"
		stepLabel.Text = "ПОДКЛЮЧЕНИЕ"
		stepTitle.Text = "Свободных баз пока нет"
		stepBody.Text = "База назначится, когда освободится место."
	elseif ready then
		stateLabel.Text = string.format("БАЗА %02d  ·  ПРОИЗВОДСТВО", math.floor(baseId :: number))
		incomeLabel.Text = "+$ " .. formatRate(income) .. " / сек" .. (if overdrive > 0 then string.format(" · ПЕРЕГРЕВ ×2: %d:%02d", overdrive // 60, overdrive % 60) else " · в среднем")
		incomeLabel.TextColor3 = if overdrive > 0 then colors.orange else colors.muted
		local questText = player:GetAttribute("DeadblockQuestText")
		local questIndex = finiteNumber(player:GetAttribute("DeadblockQuestIndex"))
		local questTotal = finiteNumber(player:GetAttribute("DeadblockQuestTotal"))
		local questReward = finiteNumber(player:GetAttribute("DeadblockQuestReward"))
		stepLabel.Text = "РАЗВИТИЕ БАЗЫ"
		stepTitle.Text = "Строй, укрепляй, держись"
		stepBody.Text = "Круглые площадки у стен (E) — турели. Пульт у ядра: расширение, стены, ремонт. Мастерская — инженеры. Портал ведёт в новые миры."
		if typeof(questText) == "string" and questIndex and questTotal then
			stepLabel.Text = string.format("ЗАДАНИЕ %d / %d", questIndex, questTotal)
			stepTitle.Text = questText
			stepBody.Text = if questReward and questReward > 0 then "Награда: $ " .. formatCash(questReward) .. ". Иди за золотой стрелкой." else "Иди за золотой стрелкой."
		end
	else
		stateLabel.Text = "ПОДГОТОВКА БАЗЫ"
		incomeLabel.Text = "Загружаем производство…"
		stepLabel.Text = "ПОДКЛЮЧЕНИЕ"
		stepTitle.Text = "Твоя база скоро будет готова"
		stepBody.Text = "Подготавливаем участок и запускаем дроппер."
	end
	renderUpgrade()
end

local function layout()
	local width = root.AbsoluteSize.X
	local height = root.AbsoluteSize.Y
	if width <= 0 or height <= 0 then
		return
	end
	local compact = width < 700 or height < 480
	local margin = if compact then 16 else 24
	local touch = UserInputService.TouchEnabled and width < 1000
	local overviewWidth = math.min(if height < 480 then 244 else 288, width - margin * 2)
	overview.Position = UDim2.fromOffset(margin, 12)
	overview.Size = UDim2.fromOffset(overviewWidth, 214)
	brand.TextSize = if compact then 22 else 24
	if touch and height < 480 and width >= 560 then
		-- Landscape phones: keep the hint above the right control area.
		onboarding.AnchorPoint = Vector2.new(1, 0)
		onboarding.Position = UDim2.new(1, -margin, 0, 12)
		onboarding.Size = UDim2.fromOffset(math.min(300, width - overviewWidth - margin * 3), 122)
	else
		onboarding.AnchorPoint = Vector2.new(0, 1)
		onboarding.Position = UDim2.new(0, margin, 1, -(if touch then 152 else margin))
		onboarding.Size = UDim2.fromOffset(math.min(324, width - margin * 2), 122)
	end
	stepBody.Size = UDim2.new(1, -32, 1, -64)
	upgradeScale.Scale = math.min(1, (width - margin * 2) / 360, (height - 24) / 326)
	upgradePanel.AnchorPoint = if width < 700 then Vector2.new(0.5, 0.5) else Vector2.new(1, 0.5)
	upgradePanel.Position = if width < 700 then UDim2.fromScale(0.5, 0.5) else UDim2.new(1, -margin, 0.5, 0)
	toast.AnchorPoint = Vector2.new(0.5, 1)
	toast.Position = UDim2.new(0.5, 0, 1, -margin)
	toast.Size = UDim2.fromOffset(math.min(400, width - margin * 2), 64)
end


-- Combat panel: wave progress, core health and the wave button. The server owns every value.
local combatPanel = frame("CombatPanel", root, UDim2.fromOffset(340, 118))
panel(combatPanel)
combatPanel.Visible = false
local waveTitle = label("WaveTitle", combatPanel, 14, colors.text)
waveTitle.Font = Enum.Font.GothamBold
waveTitle.Position = UDim2.fromOffset(16, 8)
waveTitle.Size = UDim2.new(1, -240, 0, 22)
local waveDetail = label("WaveDetail", combatPanel, 11, colors.muted)
waveDetail.Position = UDim2.fromOffset(16, 30)
waveDetail.Size = UDim2.new(1, -32, 0, 18)
local wavePreview = label("WavePreview", combatPanel, 11, colors.orange)
wavePreview.Position = UDim2.fromOffset(16, 48)
wavePreview.Size = UDim2.new(1, -32, 0, 18)
wavePreview.TextTruncate = Enum.TextTruncate.AtEnd
local coreBack = frame("CoreBar", combatPanel, UDim2.new(1, -32, 0, 10))
coreBack.Position = UDim2.fromOffset(16, 72)
coreBack.BackgroundColor3 = colors.border
coreBack.BackgroundTransparency = 0
local coreBackCorner = Instance.new("UICorner")
coreBackCorner.CornerRadius = UDim.new(0, 5)
coreBackCorner.Parent = coreBack
local coreFill = frame("Fill", coreBack, UDim2.fromScale(1, 1))
coreFill.BackgroundColor3 = colors.mint
coreFill.BackgroundTransparency = 0
local coreFillCorner = Instance.new("UICorner")
coreFillCorner.CornerRadius = UDim.new(0, 5)
coreFillCorner.Parent = coreFill
local waveButton = Instance.new("TextButton")
waveButton.Name = "WaveButton"
waveButton.Position = UDim2.fromOffset(16, 90)
waveButton.Size = UDim2.new(1, -32, 0, 34)
waveButton.BorderSizePixel = 0
waveButton.Font = Enum.Font.GothamBold
waveButton.TextSize = 13
waveButton.Parent = combatPanel
local autoButton = Instance.new("TextButton")
autoButton.Name = "AutoWave"
autoButton.AnchorPoint = Vector2.new(1, 0)
autoButton.Position = UDim2.new(1, -12, 0, 8)
autoButton.Size = UDim2.fromOffset(96, 22)
autoButton.BorderSizePixel = 0
autoButton.Font = Enum.Font.GothamBold
autoButton.TextSize = 11
autoButton.Parent = combatPanel
local autoCorner = Instance.new("UICorner")
autoCorner.CornerRadius = UDim.new(0, 6)
autoCorner.Parent = autoButton
local difficultyButton = Instance.new("TextButton")
difficultyButton.Name = "Difficulty"
difficultyButton.AnchorPoint = Vector2.new(1, 0)
difficultyButton.Position = UDim2.new(1, -114, 0, 8)
difficultyButton.Size = UDim2.fromOffset(110, 22)
difficultyButton.BorderSizePixel = 0
difficultyButton.Font = Enum.Font.GothamBold
difficultyButton.TextSize = 11
difficultyButton.Parent = combatPanel
local difficultyCorner = Instance.new("UICorner")
difficultyCorner.CornerRadius = UDim.new(0, 6)
difficultyCorner.Parent = difficultyButton
local waveButtonCorner = Instance.new("UICorner")
waveButtonCorner.CornerRadius = UDim.new(0, 8)
waveButtonCorner.Parent = waveButton

local combatRemote: RemoteEvent? = nil
local function attachCombat(child: Instance)
	if child:IsA("RemoteEvent") and child.Name == "CombatAction" then combatRemote = child end
end
local function watchRemotes(folder: Instance)
	if folder.Name ~= "DeadblockRemotes" then return end
	for _, child in folder:GetChildren() do attachCombat(child) end
	folder.ChildAdded:Connect(attachCombat)
end
ReplicatedStorage.ChildAdded:Connect(watchRemotes)
do
	local folder = ReplicatedStorage:FindFirstChild("DeadblockRemotes")
	if folder then watchRemotes(folder) end
end

local waveAction = "StartWave"
local function renderCombat()
	local state = player:GetAttribute("DeadblockWaveState")
	local core = finiteNumber(player:GetAttribute("DeadblockCoreHealth"))
	local coreMax = finiteNumber(player:GetAttribute("DeadblockCoreMax")) or 200
	local wave = finiteNumber(player:GetAttribute("DeadblockWave")) or 1
	local attackText = player:GetAttribute("DeadblockAttackText")
	if typeof(attackText) ~= "string" then attackText = "" end
	local worldName = player:GetAttribute("DeadblockWorldName")
	if typeof(worldName) ~= "string" then worldName = "Лес" end
	local left = finiteNumber(player:GetAttribute("DeadblockZombiesLeft")) or 0
	local loot = finiteNumber(player:GetAttribute("DeadblockLoot")) or 0
	local preview = player:GetAttribute("DeadblockWavePreview")
	if typeof(preview) ~= "string" then preview = "" end
	local bossWave = player:GetAttribute("DeadblockBossWave") == true
	combatPanel.Visible = typeof(state) == "string" and core ~= nil
	if not combatPanel.Visible then return end
	coreFill.Size = UDim2.fromScale(math.clamp((core :: number) / coreMax, 0, 1), 1)
	coreFill.BackgroundColor3 = colors.orange:Lerp(colors.mint, math.clamp((core :: number) / coreMax, 0, 1))
	local title, detail, button
	if state == "Active" then
		title = string.format("%s · ВОЛНА %d · БОЙ", string.upper(worldName), wave)
		detail = string.format("%s · осталось %d · ядро %d / %d", attackText, left, core :: number, coreMax)
		wavePreview.Text = "Добыча волны: $ " .. formatCash(loot) .. " — выплата после победы"
		wavePreview.TextColor3 = colors.mint
		button = nil
	elseif state == "Defeated" then
		title = "ЯДРО РАЗРУШЕНО"
		detail = "Добыча потеряна, волна начнётся заново. Перестрой оборону."
		wavePreview.Text = "Состав: " .. preview
		wavePreview.TextColor3 = if bossWave then colors.orange else colors.muted
		button, waveAction = "ПОВТОРИТЬ ВОЛНУ", "Retry"
	else
		title = string.format("%s · ВОЛНА %d · ПОДГОТОВКА", string.upper(worldName), wave)
		detail = string.format("%s · ядро %d / %d", attackText, core :: number, coreMax)
		wavePreview.Text = (if bossWave then "БОСС! " else "Состав: ") .. preview
		wavePreview.TextColor3 = if bossWave then colors.orange else colors.muted
		local countdown = finiteNumber(player:GetAttribute("DeadblockNextWaveIn")) or -1
		button, waveAction = if countdown >= 0 then string.format("НАЧАТЬ СЕЙЧАС · автостарт через %d с", countdown) else string.format("НАЧАТЬ ВОЛНУ %d", wave), "StartWave"
	end
	local difficulty = finiteNumber(player:GetAttribute("DeadblockDifficulty")) or 1
	local maxDifficulty = finiteNumber(player:GetAttribute("DeadblockMaxDifficulty")) or 1
	local difficultyName = player:GetAttribute("DeadblockDifficultyName")
	difficultyButton.Text = string.upper(if typeof(difficultyName) == "string" then difficultyName else "Обычная")
	difficultyButton.BackgroundColor3 = if difficulty >= 3 then Color3.fromRGB(200, 70, 70) elseif difficulty == 2 then colors.orange else colors.border
	difficultyButton.TextColor3 = if difficulty >= 2 then colors.panel else colors.muted
	local auto = player:GetAttribute("DeadblockAutoWave") == true
	autoButton.Text = if auto then "АВТО: ВКЛ" else "АВТО: ВЫКЛ"
	autoButton.BackgroundColor3 = if auto then colors.mint else colors.border
	autoButton.TextColor3 = if auto then colors.panel else colors.muted
	waveTitle.Text = title
	waveDetail.Text = detail
	waveButton.Visible = button ~= nil
	if button then waveButton.Text = button end
	waveButton.BackgroundColor3 = colors.orange
	waveButton.TextColor3 = colors.panel
	combatPanel.Size = UDim2.fromOffset(combatPanel.Size.X.Offset, if button then 136 else 92)
end
difficultyButton.Activated:Connect(function()
	local remote = combatRemote
	local current = finiteNumber(player:GetAttribute("DeadblockDifficulty")) or 1
	local maximum = finiteNumber(player:GetAttribute("DeadblockMaxDifficulty")) or 1
	if maximum <= 1 then
		showToast("Тяжёлая сложность откроется после волны 10.", false)
		return
	end
	if remote and remote.Parent then remote:FireServer({ kind = "Difficulty", value = current % maximum + 1 }) end
end)
autoButton.Activated:Connect(function()
	local remote = combatRemote
	if remote and remote.Parent then remote:FireServer({ kind = "AutoWave", value = player:GetAttribute("DeadblockAutoWave") ~= true }) end
end)
waveButton.Activated:Connect(function()
	local remote = combatRemote
	if remote and remote.Parent then remote:FireServer({ kind = waveAction }) end
end)
for _, attribute in { "DeadblockWaveState", "DeadblockWave", "DeadblockCoreHealth", "DeadblockCoreMax", "DeadblockZombiesLeft", "DeadblockWorldName", "DeadblockAttackText", "DeadblockLoot", "DeadblockWavePreview", "DeadblockBossWave", "DeadblockAutoWave", "DeadblockNextWaveIn", "DeadblockDifficulty", "DeadblockMaxDifficulty", "DeadblockDifficultyName" } do
	player:GetAttributeChangedSignal(attribute):Connect(renderCombat)
end
local baseLayout = layout
layout = function()
	baseLayout()
	local width = root.AbsoluteSize.X
	local margin = if width < 700 then 16 else 24
	combatPanel.AnchorPoint = Vector2.new(0.5, 0)
	combatPanel.Position = UDim2.new(0.5, 0, 0, 12)
	combatPanel.Size = UDim2.fromOffset(math.min(420, width - margin * 2), combatPanel.Size.Y.Offset)
end
renderCombat()

for _, attribute in { "DeadblockMoney", "DeadblockBaseId", "DeadblockIncome", "DeadblockDropperCount", "DeadblockExpansion", "DeadblockStatus", "DeadblockBaseLevel", "DeadblockSaveStatus", "DeadblockQuestText", "DeadblockQuestIndex", "DeadblockQuestReward", "DeadblockCores", "DeadblockOverdrive" } do
	player:GetAttributeChangedSignal(attribute):Connect(render)
end
-- Daily goals and login streak (top right).
local dailyPanel = frame("Daily", root, UDim2.fromOffset(250, 112))
panel(dailyPanel)
dailyPanel.Visible = false
local dailyTitle = label("Title", dailyPanel, 11, colors.orange)
dailyTitle.Font = Enum.Font.GothamBold
dailyTitle.Position = UDim2.fromOffset(14, 8)
dailyTitle.Size = UDim2.new(1, -28, 0, 16)
local dailyRows = {}
for index = 1, 3 do
	local row = label("Goal" .. index, dailyPanel, 11, colors.text)
	row.Position = UDim2.fromOffset(14, 8 + index * 24)
	row.Size = UDim2.new(1, -28, 0, 20)
	dailyRows[index] = row
end
local function renderDaily()
	local raw = player:GetAttribute("DeadblockDaily")
	if typeof(raw) ~= "string" then dailyPanel.Visible = false return end
	local ok, data = pcall(function() return HttpService:JSONDecode(raw) end)
	if not ok or typeof(data) ~= "table" then dailyPanel.Visible = false return end
	dailyPanel.Visible = true
	dailyTitle.Text = string.format("ЗАДАНИЯ ДНЯ  ·  СЕРИЯ %d ДН.", tonumber(data.streak) or 0)
	for index, row in ipairs(dailyRows) do
		local goal = data.goals and data.goals[index]
		if goal then
			row.Text = string.format("%s  %s  %d/%d", if goal.done then "✓" else "•", tostring(goal.text), goal.progress or 0, goal.goal or 0)
			row.TextColor3 = if goal.done then colors.mint else colors.text
		else
			row.Text = ""
		end
	end
end
player:GetAttributeChangedSignal("DeadblockDaily"):Connect(renderDaily)
renderDaily()
local layoutBeforeDaily = layout
layout = function()
	layoutBeforeDaily()
	local width = root.AbsoluteSize.X
	local margin = if width < 700 then 16 else 24
	dailyPanel.AnchorPoint = Vector2.new(1, 0)
	dailyPanel.Position = UDim2.new(1, -margin, 0, 12)
	-- On narrow screens the wave panel takes the top centre; push goals below it.
	if width < 1000 then dailyPanel.Position = UDim2.new(1, -margin, 0, 160) end
end

root:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
UserInputService:GetPropertyChangedSignal("TouchEnabled"):Connect(layout)
gui.Parent = playerGui
render()
layout()
