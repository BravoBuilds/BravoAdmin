-- Install this source as a LocalScript in StarterPlayerScripts.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local remotes = ReplicatedStorage:WaitForChild("BravoAdminRemotes", 15)

if not remotes then
	warn("BravoAdmin: server remotes were not found. Install the server script first.")
	return
end

local getSnapshot = remotes:WaitForChild("GetSnapshot", 10)
local executeAction = remotes:WaitForChild("ExecuteAction", 10)
local notifications = remotes:WaitForChild("Notify", 10)

if not getSnapshot or not executeAction or not notifications then
	warn("BravoAdmin: one or more required remotes are missing.")
	return
end

local previousUnload = playerGui:FindFirstChild("BravoAdminUnload")
if previousUnload and previousUnload:IsA("BindableFunction") then
	previousUnload:Invoke()
end
local previousGui = playerGui:FindFirstChild("BravoAdminGui")
if previousGui then
	previousGui:Destroy()
end

local COLORS = {
	background = Color3.fromRGB(7, 17, 29),
	panel = Color3.fromRGB(16, 29, 46),
	panelStrong = Color3.fromRGB(21, 40, 67),
	panelLight = Color3.fromRGB(24, 42, 64),
	line = Color3.fromRGB(39, 57, 78),
	text = Color3.fromRGB(237, 243, 255),
	muted = Color3.fromRGB(155, 176, 209),
	blue = Color3.fromRGB(95, 140, 255),
	green = Color3.fromRGB(89, 215, 164),
	red = Color3.fromRGB(255, 122, 122),
}

local connections = {}
local alive = true
local currentPage = "Dashboard"
local snapshot
local commandHistory = {}

local function track(connection)
	table.insert(connections, connection)
	return connection
end

local function create(className, properties, parent)
	local instance = Instance.new(className)
	for key, value in pairs(properties) do
		instance[key] = value
	end
	if parent and parent:FindFirstChildWhichIsA("UIListLayout") and instance:IsA("GuiObject") then
		local order = (parent:GetAttribute("BravoAdminNextLayoutOrder") or 0) + 1
		parent:SetAttribute("BravoAdminNextLayoutOrder", order)
		instance.LayoutOrder = order
	end
	instance.Parent = parent
	return instance
end

local function round(parent, radius)
	create("UICorner", { CornerRadius = UDim.new(0, radius or 10) }, parent)
end

local function outline(parent, color, transparency)
	create("UIStroke", {
		Color = color or COLORS.line,
		Transparency = transparency or 0,
		Thickness = 1,
	}, parent)
end

local function addText(parent, text, size, color, bold)
	return create("TextLabel", {
		BackgroundTransparency = 1,
		Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham,
		Text = text,
		TextColor3 = color or COLORS.text,
		TextSize = size or 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		TextWrapped = true,
	}, parent)
end

local function makeButton(parent, text, callback, style)
	local isDanger = style == "danger"
	local isPrimary = style == "primary"
	local button = create("TextButton", {
		AutoButtonColor = false,
		BackgroundColor3 = isDanger and Color3.fromRGB(67, 34, 43)
			or (isPrimary and COLORS.blue or COLORS.panelLight),
		Font = Enum.Font.GothamBold,
		Size = UDim2.new(0, 100, 0, 36),
		Text = text,
		TextColor3 = isDanger and COLORS.red or COLORS.text,
		TextSize = 12,
	}, parent)
	round(button, 9)
	outline(button, isDanger and Color3.fromRGB(112, 55, 66) or COLORS.line, isPrimary and 1 or 0)
	track(button.Activated:Connect(function()
		if alive then
			callback(button)
		end
	end))
	return button
end

local unloadFunction = create("BindableFunction", {
	Name = "BravoAdminUnload",
}, playerGui)

local screen = create("ScreenGui", {
	Name = "BravoAdminGui",
	ResetOnSpawn = false,
	IgnoreGuiInset = false,
	DisplayOrder = 50,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, playerGui)

local window = create("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	BackgroundColor3 = COLORS.background,
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(0.94, 0.88),
}, screen)
round(window, 16)
outline(window, COLORS.line)
create("UISizeConstraint", {
	MinSize = Vector2.new(280, 240),
	MaxSize = Vector2.new(1200, 820),
}, window)

local sidebar = create("Frame", {
	BackgroundColor3 = COLORS.panel,
	BorderSizePixel = 0,
	Size = UDim2.new(0, 196, 1, 0),
}, window)
round(sidebar, 16)
create("Frame", {
	BackgroundColor3 = COLORS.panel,
	BorderSizePixel = 0,
	Position = UDim2.new(1, -14, 0, 0),
	Size = UDim2.new(0, 14, 1, 0),
}, sidebar)

local brand = create("Frame", {
	BackgroundTransparency = 1,
	Position = UDim2.new(0, 20, 0, 20),
	Size = UDim2.new(1, -40, 0, 48),
}, sidebar)
local brandMark = addText(brand, "B", 17, COLORS.text, true)
brandMark.BackgroundColor3 = COLORS.blue
brandMark.BackgroundTransparency = 0
brandMark.Size = UDim2.fromOffset(36, 36)
brandMark.TextXAlignment = Enum.TextXAlignment.Center
round(brandMark, 11)
local brandName = addText(brand, "BRAVOADMIN", 14, COLORS.text, true)
brandName.Position = UDim2.new(0, 46, 0, 0)
brandName.Size = UDim2.new(1, -46, 1, 0)

local nav = create("Frame", {
	BackgroundTransparency = 1,
	Position = UDim2.new(0, 12, 0, 92),
	Size = UDim2.new(1, -24, 0, 232),
}, sidebar)
local navLayout = create("UIListLayout", {
	Padding = UDim.new(0, 7),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, nav)

local body = create("Frame", {
	BackgroundTransparency = 1,
	Position = UDim2.new(0, 216, 0, 0),
	Size = UDim2.new(1, -232, 1, 0),
}, window)

local function updateResponsiveLayout()
	local camera = workspace.CurrentCamera
	local compact = camera ~= nil and camera.ViewportSize.X < 720
	sidebar.Size = compact and UDim2.new(0, 68, 1, 0) or UDim2.new(0, 196, 1, 0)
	brand.Position = UDim2.new(0, compact and 16 or 20, 0, 20)
	brand.Size = UDim2.new(1, compact and -24 or -40, 0, 48)
	brandName.Visible = not compact
	nav.Position = UDim2.new(0, compact and 8 or 12, 0, 92)
	nav.Size = UDim2.new(1, compact and -16 or -24, 0, navLayout.AbsoluteContentSize.Y)
	body.Position = UDim2.new(0, compact and 82 or 216, 0, 0)
	body.Size = UDim2.new(1, compact and -96 or -232, 1, 0)
	for _, button in ipairs(nav:GetChildren()) do
		if button:IsA("TextButton") then
			button.Text = compact and string.sub(button.Name, 1, 1) or "   " .. button.Name
			button.TextXAlignment = compact and Enum.TextXAlignment.Center or Enum.TextXAlignment.Left
		end
	end
end

local topbar = create("Frame", {
	BackgroundTransparency = 1,
	Size = UDim2.new(1, 0, 0, 72),
}, body)
local pageTitle = addText(topbar, "Dashboard", 21, COLORS.text, true)
pageTitle.Position = UDim2.new(0, 0, 0, 10)
pageTitle.Size = UDim2.new(0.7, 0, 0, 28)
local pageHint = addText(topbar, "Server administration", 12, COLORS.muted, false)
pageHint.Position = UDim2.new(0, 0, 0, 39)
pageHint.Size = UDim2.new(0.7, 0, 0, 20)
local status = addText(topbar, "●  CONNECTING", 11, COLORS.green, true)
status.AnchorPoint = Vector2.new(1, 0)
status.Position = UDim2.new(1, -46, 0, 22)
status.Size = UDim2.new(0, 132, 0, 22)
status.TextXAlignment = Enum.TextXAlignment.Right
local closeButton = makeButton(topbar, "Close", function()
	unloadFunction:Invoke()
end)
closeButton.AnchorPoint = Vector2.new(1, 0)
closeButton.Position = UDim2.new(1, 0, 0, 16)
closeButton.Size = UDim2.new(0, 40, 0, 34)
closeButton.Text = "×"
closeButton.TextSize = 18

local content = create("ScrollingFrame", {
	Active = true,
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	CanvasSize = UDim2.new(),
	Position = UDim2.new(0, 0, 0, 76),
	ScrollBarImageColor3 = COLORS.blue,
	ScrollBarThickness = 4,
	Size = UDim2.new(1, 0, 1, -84),
}, body)
local contentLayout = create("UIListLayout", {
	Padding = UDim.new(0, 14),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, content)
create("UIPadding", {
	PaddingBottom = UDim.new(0, 10),
	PaddingRight = UDim.new(0, 8),
}, content)

local function toast(message, isError)
	if not alive then
		return
	end
	local label = create("TextLabel", {
		AnchorPoint = Vector2.new(1, 1),
		BackgroundColor3 = isError and Color3.fromRGB(67, 34, 43) or COLORS.panelStrong,
		Font = Enum.Font.GothamMedium,
		Position = UDim2.new(1, -18, 1, -18),
		Size = UDim2.new(0.9, 0, 0, 46),
		Text = tostring(message),
		TextColor3 = isError and COLORS.red or COLORS.text,
		TextSize = 13,
		TextWrapped = true,
		ZIndex = 5,
	}, screen)
	create("UISizeConstraint", {
		MaxSize = Vector2.new(380, 46),
	}, label)
	round(label, 10)
	outline(label, isError and COLORS.red or COLORS.blue, 0.6)
	label.BackgroundTransparency = 1
	label.TextTransparency = 1
	TweenService:Create(label, TweenInfo.new(0.16), {
		BackgroundTransparency = 0,
		TextTransparency = 0,
	}):Play()
	task.delay(3.2, function()
		if label.Parent then
			local fade = TweenService:Create(label, TweenInfo.new(0.2), {
				BackgroundTransparency = 1,
				TextTransparency = 1,
			})
			fade:Play()
			fade.Completed:Wait()
			label:Destroy()
		end
	end)
end

local function invoke(action)
	local ok, response = pcall(function()
		return executeAction:InvokeServer(action)
	end)
	if not ok then
		return nil, "The server could not be reached. Please try again."
	end
	if type(response) ~= "table" or response.ok ~= true then
		return nil, (type(response) == "table" and response.error) or "The server returned an invalid response."
	end
	return response
end

local function refreshSnapshot()
	if not alive then
		return false
	end
	local ok, response = pcall(function()
		return getSnapshot:InvokeServer()
	end)
	if not ok or type(response) ~= "table" or response.ok ~= true then
		status.Text = "●  NOT AUTHORIZED"
		status.TextColor3 = COLORS.red
		toast((type(response) == "table" and response.error) or "Could not load BravoAdmin permissions.", true)
		return false
	end
	snapshot = response
	status.Text = "●  " .. string.upper(response.role or "ADMIN")
	status.TextColor3 = COLORS.green
	return true
end

local function clearContent()
	for _, child in ipairs(content:GetChildren()) do
		if child ~= contentLayout and not child:IsA("UIPadding") then
			child:Destroy()
		end
	end
end

local function makeCard(parent)
	local card = create("Frame", {
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = COLORS.panel,
		BorderSizePixel = 0,
		Size = UDim2.new(1, -6, 0, 0),
	}, parent)
	round(card, 13)
	outline(card, COLORS.line)
	create("UIPadding", {
		PaddingBottom = UDim.new(0, 16),
		PaddingLeft = UDim.new(0, 17),
		PaddingRight = UDim.new(0, 17),
		PaddingTop = UDim.new(0, 15),
	}, card)
	create("UIListLayout", {
		Padding = UDim.new(0, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, card)
	return card
end

local function addCardTitle(parent, title, subtitle)
	local titleLabel = addText(parent, title, 15, COLORS.text, true)
	titleLabel.Size = UDim2.new(1, 0, 0, 24)
	if subtitle then
		local subtitleLabel = addText(parent, subtitle, 12, COLORS.muted, false)
		subtitleLabel.Size = UDim2.new(1, 0, 0, 20)
	end
end

local function addInfoRow(parent, name, value)
	local row = create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 24),
	}, parent)
	local left = addText(row, name, 12, COLORS.muted, false)
	left.Size = UDim2.new(0.55, 0, 1, 0)
	local right = addText(row, tostring(value), 12, COLORS.text, true)
	right.Position = UDim2.new(0.55, 0, 0, 0)
	right.Size = UDim2.new(0.45, 0, 1, 0)
	right.TextXAlignment = Enum.TextXAlignment.Right
end

local function addField(parent, placeholder, initial)
	local field = create("TextBox", {
		BackgroundColor3 = COLORS.background,
		ClearTextOnFocus = false,
		Font = Enum.Font.Gotham,
		PlaceholderColor3 = COLORS.muted,
		PlaceholderText = placeholder,
		Size = UDim2.new(1, 0, 0, 38),
		Text = initial or "",
		TextColor3 = COLORS.text,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, parent)
	round(field, 9)
	outline(field, COLORS.line)
	create("UIPadding", {
		PaddingLeft = UDim.new(0, 11),
		PaddingRight = UDim.new(0, 11),
	}, field)
	return field
end

local function formatUptime(seconds)
	seconds = math.max(0, math.floor(seconds or 0))
	local hours = math.floor(seconds / 3600)
	local minutes = math.floor((seconds % 3600) / 60)
	return string.format("%02d:%02d:%02d", hours, minutes, seconds % 60)
end

local function renderDashboard()
	local server = snapshot.server
	local metrics = makeCard(content)
	addCardTitle(metrics, "Server overview", "Live information from this game server")
	addInfoRow(metrics, "Players online", string.format("%d / %d", server.playerCount, server.maxPlayers))
	addInfoRow(metrics, "Server uptime", formatUptime(server.uptime))
	addInfoRow(metrics, "Place ID", server.placeId)
	addInfoRow(metrics, "Job ID", server.jobId == "" and "Studio session" or server.jobId)

	local actions = makeCard(content)
	addCardTitle(actions, "Recent actions", "Latest server-recorded moderation activity")
	if #snapshot.logs == 0 then
		addText(actions, "No actions recorded in this server yet.", 12, COLORS.muted, false).Size = UDim2.new(1, 0, 0, 28)
	else
		for index = 1, math.min(5, #snapshot.logs) do
			local item = snapshot.logs[index]
			addInfoRow(actions, item.time .. "  ·  " .. item.actor, item.action .. (item.target ~= "" and "  →  " .. item.target or ""))
		end
	end
end

local function renderPlayers()
	local searchCard = makeCard(content)
	addCardTitle(searchCard, "Player management", "Search players currently connected to this server")
	local search = addField(searchCard, "Search by name, display name, or user ID")
	local listCard = makeCard(content)
	addCardTitle(listCard, "Connected players", tostring(#snapshot.players) .. " currently online")
	local list = create("Frame", {
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
	}, listCard)
	local listLayout = create("UIListLayout", {
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, list)

	local function populatePlayers()
		for _, child in ipairs(list:GetChildren()) do
			if child ~= listLayout then
				child:Destroy()
			end
		end
		local query = string.lower(search.Text)
		local matches = 0
		for _, target in ipairs(snapshot.players) do
			local haystack = string.lower(target.name .. " " .. target.displayName .. " " .. tostring(target.userId))
			if query == "" or string.find(haystack, query, 1, true) then
				matches += 1
				local row = create("Frame", {
					BackgroundColor3 = COLORS.panelLight,
					Size = UDim2.new(1, 0, 0, 78),
				}, list)
				round(row, 10)
				local name = addText(row, target.displayName .. "  @" .. target.name, 12, COLORS.text, true)
				name.Position = UDim2.new(0, 11, 0, 8)
				name.Size = UDim2.new(1, -100, 0, 19)
				local details = addText(row, "User ID " .. tostring(target.userId) .. "  ·  " .. (target.role or "Player"), 10, COLORS.muted, false)
				details.Position = UDim2.new(0, 11, 0, 29)
				details.Size = UDim2.new(1, -100, 0, 17)
				local kick = makeButton(row, "Kick", function()
					local result, err = invoke({
						action = "kick",
						targetUserId = target.userId,
						reason = "Removed by an administrator",
					})
					if not result then
						toast(err, true)
						return
					end
					toast(result.message or "Player kicked.")
					if refreshSnapshot() then
						renderPlayers()
					end
				end, "danger")
				kick.Position = UDim2.new(1, -88, 0, 21)
				kick.Size = UDim2.new(0, 76, 0, 34)
			end
		end
		if matches == 0 then
			addText(list, "No matching players.", 12, COLORS.muted, false).Size = UDim2.new(1, 0, 0, 28)
		end
	end

	track(search:GetPropertyChangedSignal("Text"):Connect(populatePlayers))
	populatePlayers()

	if snapshot.canBan or snapshot.canUnban then
		local banCard = makeCard(content)
		addCardTitle(banCard, "Ban / unban", "Enter a Roblox user ID. Bans persist using the server DataStore.")
		local userIdField = addField(banCard, "Roblox user ID")
		local reasonField = addField(banCard, "Reason (optional)")
		local buttonRow = create("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 38),
		}, banCard)
		if snapshot.canBan then
			local banButton = makeButton(buttonRow, "Ban", function()
				local userId = tonumber(userIdField.Text)
				if not userId or userId < 1 or userId % 1 ~= 0 then
					toast("Enter a valid positive Roblox user ID.", true)
					return
				end
				local result, err = invoke({ action = "ban", targetUserId = userId, reason = reasonField.Text })
				if not result then
					toast(err, true)
					return
				end
				toast(result.message or "User banned.")
				userIdField.Text = ""
				reasonField.Text = ""
				if refreshSnapshot() then
					renderPlayers()
				end
			end, "danger")
			banButton.Size = UDim2.new(0.48, 0, 0, 36)
		end
		if snapshot.canUnban then
			local unbanButton = makeButton(buttonRow, "Unban", function()
				local userId = tonumber(userIdField.Text)
				if not userId or userId < 1 or userId % 1 ~= 0 then
					toast("Enter a valid positive Roblox user ID.", true)
					return
				end
				local result, err = invoke({ action = "unban", targetUserId = userId })
				if not result then
					toast(err, true)
					return
				end
				toast(result.message or "Ban removed.")
				userIdField.Text = ""
				if refreshSnapshot() then
					renderPlayers()
				end
			end)
			unbanButton.Position = UDim2.new(snapshot.canBan and 0.52 or 0, 0, 0, 0)
			unbanButton.Size = UDim2.new(snapshot.canBan and 0.48 or 1, 0, 0, 36)
		end
	end
end

local function renderCommands()
	local commandCard = makeCard(content)
	addCardTitle(commandCard, "Command console", "Commands are parsed and permission-checked by the server.")
	local commandField = addField(commandCard, "!help")
	local run = makeButton(commandCard, "Run command", function(button)
		local line = commandField.Text
		if line:gsub("%s", "") == "" then
			toast("Enter a command first.", true)
			return
		end
		button.Active = false
		local result, err = invoke({ action = "command", commandLine = line })
		button.Active = true
		table.insert(commandHistory, 1, {
			line = line,
			result = result and result.message or err,
			ok = result ~= nil,
		})
		if #commandHistory > 20 then
			table.remove(commandHistory)
		end
		toast(result and result.message or err, result == nil)
		if refreshSnapshot() then
			renderCommands()
		end
	end, "primary")
	run.Size = UDim2.new(0, 120, 0, 36)

	local help = makeCard(content)
	addCardTitle(help, "Available commands", "Names and roles are always verified server-side.")
	for _, command in ipairs(snapshot.commands) do
		addInfoRow(help, command.syntax, command.description)
	end

	local history = makeCard(content)
	addCardTitle(history, "Command history", "Recent commands from this interface")
	if #commandHistory == 0 then
		addText(history, "No commands run in this session.", 12, COLORS.muted, false).Size = UDim2.new(1, 0, 0, 28)
	else
		for _, entry in ipairs(commandHistory) do
			addInfoRow(history, entry.line, (entry.ok and "✓ " or "✕ ") .. tostring(entry.result))
		end
	end
end

local function renderSettings()
	local roleCard = makeCard(content)
	addCardTitle(roleCard, "Roles & permissions", "Roles are assigned only in the server script; clients cannot grant permissions.")
	for _, roleName in ipairs({ "Owner", "Admin", "Moderator" }) do
		addInfoRow(roleCard, roleName, table.concat(snapshot.permissions[roleName], ", "))
	end
	local settingsCard = makeCard(content)
	addCardTitle(settingsCard, "Server settings", snapshot.canConfigure and "Changes apply to this server until it restarts." or "Only the Owner role can change server settings.")
	if snapshot.canConfigure then
		local toggle = makeButton(settingsCard, "Loading…", function()
			local enabled = not snapshot.settings.broadcastNotices
			local result, err = invoke({ action = "setSetting", key = "broadcastNotices", value = enabled })
			if not result then
				toast(err, true)
				return
			end
			if refreshSnapshot() then
				renderSettings()
			end
		end, "primary")
		toggle.Size = UDim2.new(1, 0, 0, 38)
		toggle.Text = "Broadcast moderation notices: " .. (snapshot.settings.broadcastNotices and "ON" or "OFF")
		local note = addText(settingsCard, "Moderation notices are sent to online administrators with BravoAdmin open.", 11, COLORS.muted, false)
		note.Size = UDim2.new(1, 0, 0, 30)
	end
	local storageCard = makeCard(content)
	addCardTitle(storageCard, "Storage & safety")
	addInfoRow(storageCard, "Ban storage", "Roblox DataStore")
	addInfoRow(storageCard, "Action log", "Current server session (most recent 100)")
	addInfoRow(storageCard, "Permission checks", "Server-side on every request")
end

local function renderLogs()
	local logsCard = makeCard(content)
	addCardTitle(logsCard, "Action log", "Server-recorded actions for this session")
	if #snapshot.logs == 0 then
		addText(logsCard, "No actions recorded yet.", 12, COLORS.muted, false).Size = UDim2.new(1, 0, 0, 28)
		return
	end
	for _, item in ipairs(snapshot.logs) do
		addInfoRow(logsCard, item.time .. "  ·  " .. item.actor, item.action .. (item.target ~= "" and "  →  " .. item.target or ""))
		if item.details and item.details ~= "" then
			addText(logsCard, item.details, 10, COLORS.muted, false).Size = UDim2.new(1, 0, 0, 19)
		end
	end
end

local pages = {
	Dashboard = renderDashboard,
	Players = renderPlayers,
	Commands = renderCommands,
	Settings = renderSettings,
	Logs = renderLogs,
}

local function showPage(pageName)
	if not pages[pageName] then
		return
	end
	currentPage = pageName
	pageTitle.Text = pageName == "Dashboard" and "Dashboard" or pageName
	pageHint.Text = pageName == "Dashboard" and "Server administration" or "BravoAdmin  ·  " .. pageName
	clearContent()
	pages[pageName]()
	for _, button in ipairs(nav:GetChildren()) do
		if button:IsA("TextButton") then
			local selected = button.Name == pageName
			button.BackgroundColor3 = selected and COLORS.panelStrong or COLORS.panel
			button.TextColor3 = selected and COLORS.text or COLORS.muted
		end
	end
end

for index, name in ipairs({ "Dashboard", "Players", "Commands", "Settings", "Logs" }) do
	local button = create("TextButton", {
		AutoButtonColor = false,
		BackgroundColor3 = COLORS.panel,
		Font = Enum.Font.GothamMedium,
		LayoutOrder = index,
		Name = name,
		Size = UDim2.new(1, 0, 0, 39),
		Text = "   " .. name,
		TextColor3 = COLORS.muted,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, nav)
	round(button, 9)
	track(button.Activated:Connect(function()
		if refreshSnapshot() then
			showPage(name)
		end
	end))
end
track(navLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateResponsiveLayout))
if workspace.CurrentCamera then
	track(workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateResponsiveLayout))
end
updateResponsiveLayout()

local function cleanup()
	if not alive then
		return
	end
	alive = false
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	table.clear(connections)
	if unloadFunction.Parent then
		unloadFunction.OnInvoke = nil
		unloadFunction:Destroy()
	end
	if screen.Parent then
		screen:Destroy()
	end
end

track(script.Destroying:Connect(cleanup))
unloadFunction.OnInvoke = function()
	cleanup()
	return true
end

track(notifications.OnClientEvent:Connect(function(message)
	toast(message, false)
end))

if refreshSnapshot() then
	showPage(currentPage)
else
	task.delay(0.1, cleanup)
end
