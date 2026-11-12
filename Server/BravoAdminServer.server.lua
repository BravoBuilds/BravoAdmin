-- Install this Script in ServerScriptService. Configure trusted user IDs below.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")

local CONFIG = {
	BanStoreName = "BravoAdminBans_v1",
	LogLimit = 100,
	OwnerUserIds = {
		-- Add trusted Roblox user IDs, for example: 123456789,
	},
	UserRoles = {
		-- [123456789] = "Admin",
		-- [987654321] = "Moderator",
	},
}

local ROLE_PERMISSIONS = {
	Owner = { "view", "kick", "ban", "unban", "viewLogs", "configure" },
	Admin = { "view", "kick", "ban", "unban", "viewLogs" },
	Moderator = { "view", "kick", "viewLogs" },
}
local ROLE_LEVEL = {
	Moderator = 1,
	Admin = 2,
	Owner = 3,
}

local rolePermissionSet = {}
for roleName, permissions in pairs(ROLE_PERMISSIONS) do
	local set = {}
	for _, permission in ipairs(permissions) do
		set[permission] = true
	end
	rolePermissionSet[roleName] = set
end

local remotes = ReplicatedStorage:FindFirstChild("BravoAdminRemotes")
if remotes and not remotes:IsA("Folder") then
	error("BravoAdmin: ReplicatedStorage.BravoAdminRemotes exists but is not a Folder.")
end
if not remotes then
	remotes = Instance.new("Folder")
	remotes.Name = "BravoAdminRemotes"
	remotes.Parent = ReplicatedStorage
end

local function getOrCreateRemote(className, name)
	local existing = remotes:FindFirstChild(name)
	if existing then
		if not existing:IsA(className) then
			error("BravoAdmin: remote " .. name .. " must be a " .. className .. ".")
		end
		return existing
	end
	local remote = Instance.new(className)
	remote.Name = name
	remote.Parent = remotes
	return remote
end

local getSnapshot = getOrCreateRemote("RemoteFunction", "GetSnapshot")
local executeAction = getOrCreateRemote("RemoteFunction", "ExecuteAction")
local notifications = getOrCreateRemote("RemoteEvent", "Notify")
local banStore = DataStoreService:GetDataStore(CONFIG.BanStoreName)

local startedAt = os.clock()
local actionLogs = {}
local runtimeSettings = {
	broadcastNotices = false,
}
local lastSnapshotAt = {}
local lastActionAt = {}

local function getRoleForUserId(userId)
	if game.CreatorType == Enum.CreatorType.User and userId == game.CreatorId then
		return "Owner"
	end
	for _, ownerUserId in ipairs(CONFIG.OwnerUserIds) do
		if userId == ownerUserId then
			return "Owner"
		end
	end
	local role = CONFIG.UserRoles[userId]
	if ROLE_PERMISSIONS[role] then
		return role
	end
	return nil
end

local function getRole(player)
	return getRoleForUserId(player.UserId)
end

local function hasPermission(player, permission)
	local role = getRole(player)
	if not role then
		return false
	end
	return rolePermissionSet[role][permission] == true
end

local function canModerateTarget(actor, targetUserId)
	if actor.UserId == targetUserId then
		return false
	end
	local actorRole = getRole(actor)
	local targetRole = getRoleForUserId(targetUserId)
	return not targetRole or ROLE_LEVEL[actorRole] > ROLE_LEVEL[targetRole]
end

local function sanitizeText(value, maxLength)
	if type(value) ~= "string" then
		return ""
	end
	local text = value:gsub("[%c]", " ")
	text = text:sub(1, maxLength or 120)
	return text
end

local function addLog(actor, action, target, details)
	local entry = {
		time = os.date("!%Y-%m-%d %H:%M:%S"),
		actor = actor.Name,
		actorUserId = actor.UserId,
		action = action,
		target = sanitizeText(target, 80),
		details = sanitizeText(details, 180),
	}
	table.insert(actionLogs, 1, entry)
	while #actionLogs > CONFIG.LogLimit do
		table.remove(actionLogs)
	end
	if runtimeSettings.broadcastNotices then
		local message = string.format("%s: %s %s", actor.Name, action, entry.target)
		for _, recipient in ipairs(Players:GetPlayers()) do
			if hasPermission(recipient, "view") then
				notifications:FireClient(recipient, message)
			end
		end
	end
end

local function getPlayerSnapshot()
	local result = {}
	for _, target in ipairs(Players:GetPlayers()) do
		table.insert(result, {
			userId = target.UserId,
			name = target.Name,
			displayName = target.DisplayName,
			role = getRole(target) or "Player",
		})
	end
	table.sort(result, function(left, right)
		return string.lower(left.name) < string.lower(right.name)
	end)
	return result
end

local function copyLogs()
	local result = {}
	for index, entry in ipairs(actionLogs) do
		result[index] = {
			time = entry.time,
			actor = entry.actor .. " (" .. tostring(entry.actorUserId) .. ")",
			action = entry.action,
			target = entry.target,
			details = entry.details,
		}
	end
	return result
end

local function getPermissionSnapshot()
	local result = {}
	for roleName, permissions in pairs(ROLE_PERMISSIONS) do
		result[roleName] = table.clone(permissions)
	end
	return result
end

local COMMANDS = {
	{ syntax = "!help", description = "Show the available commands" },
	{ syntax = "!server", description = "Show live server information" },
	{ syntax = "!kick <player> [reason]", description = "Remove a connected player (Moderator+)" },
	{ syntax = "!ban <userId> [reason]", description = "Persistently ban a user ID (Admin+)" },
	{ syntax = "!unban <userId>", description = "Remove a stored ban (Admin+)" },
}

local function buildSnapshot(player)
	local jobId = game.JobId
	return {
		ok = true,
		role = getRole(player),
		canBan = hasPermission(player, "ban"),
		canUnban = hasPermission(player, "unban"),
		canConfigure = hasPermission(player, "configure"),
		server = {
			playerCount = #Players:GetPlayers(),
			maxPlayers = Players.MaxPlayers,
			placeId = game.PlaceId,
			jobId = jobId,
			uptime = math.floor(os.clock() - startedAt),
		},
		players = getPlayerSnapshot(),
		logs = copyLogs(),
		settings = table.clone(runtimeSettings),
		permissions = getPermissionSnapshot(),
		commands = COMMANDS,
	}
end

local function rateLimit(player, bucket, interval)
	local now = os.clock()
	local timestamps = bucket == "action" and lastActionAt or lastSnapshotAt
	local previous = timestamps[player.UserId] or 0
	if previous > 0 and now - previous < interval then
		return false
	end
	timestamps[player.UserId] = now
	return true
end

local function resolveUserId(value)
	if type(value) == "number" then
		if value >= 1 and value % 1 == 0 then
			return value
		end
		return nil, "Enter a valid positive user ID."
	end
	if type(value) ~= "string" then
		return nil, "Enter a user ID or connected player name."
	end
	local asNumber = tonumber(value)
	if asNumber then
		if asNumber >= 1 and asNumber % 1 == 0 then
			return asNumber
		end
		return nil, "Enter a valid positive user ID."
	end
	local query = string.lower(sanitizeText(value, 40))
	local match
	for _, target in ipairs(Players:GetPlayers()) do
		if string.lower(target.Name) == query or string.lower(target.DisplayName) == query then
			if match and match.UserId ~= target.UserId then
				return nil, "That display name is ambiguous. Use a user ID instead."
			end
			match = target
		end
	end
	if match then
		return match.UserId
	end
	return nil, "Player is not connected. Use their numeric user ID."
end

local function validReason(value)
	if value == nil then
		return "No reason provided"
	end
	if type(value) ~= "string" then
		return nil, "Reason must be text."
	end
	local reason = sanitizeText(value, 120)
	return reason:match("%S") and reason or "No reason provided"
end

local function kickPlayer(actor, targetUserId, reason)
	if not hasPermission(actor, "kick") then
		return nil, "Your role cannot kick players."
	end
	local resolvedId, resolveError = resolveUserId(targetUserId)
	if not resolvedId then
		return nil, resolveError
	end
	local target = Players:GetPlayerByUserId(resolvedId)
	if not target then
		return nil, "The selected player is no longer connected."
	end
	if not canModerateTarget(actor, resolvedId) then
		return nil, "You cannot kick yourself or an administrator with an equal or higher role."
	end
	local safeReason, reasonError = validReason(reason)
	if not safeReason then
		return nil, reasonError
	end
	addLog(actor, "Kick", target.Name .. " (" .. tostring(target.UserId) .. ")", safeReason)
	target:Kick("Removed by an administrator. Reason: " .. safeReason)
	return { ok = true, message = "Kicked " .. target.Name .. "." }
end

local function banUser(actor, targetUserId, reason)
	if not hasPermission(actor, "ban") then
		return nil, "Your role cannot ban users."
	end
	local resolvedId, resolveError = resolveUserId(targetUserId)
	if not resolvedId then
		return nil, resolveError
	end
	local target = Players:GetPlayerByUserId(resolvedId)
	if not canModerateTarget(actor, resolvedId) then
		return nil, "You cannot ban yourself or an administrator with an equal or higher role."
	end
	local safeReason, reasonError = validReason(reason)
	if not safeReason then
		return nil, reasonError
	end
	local ok, storeError = pcall(function()
		banStore:SetAsync(tostring(resolvedId), {
			reason = safeReason,
			byUserId = actor.UserId,
			createdAt = os.time(),
		})
	end)
	if not ok then
		warn("BravoAdmin: ban could not be saved: " .. tostring(storeError))
		return nil, "Ban storage is unavailable; no ban was applied."
	end
	addLog(actor, "Ban", (target and target.Name .. " " or "") .. "(" .. tostring(resolvedId) .. ")", safeReason)
	if target then
		target:Kick("Banned from this experience. Reason: " .. safeReason)
	end
	return { ok = true, message = "Banned user ID " .. tostring(resolvedId) .. "." }
end

local function unbanUser(actor, targetUserId)
	if not hasPermission(actor, "unban") then
		return nil, "Your role cannot unban users."
	end
	local resolvedId, resolveError = resolveUserId(targetUserId)
	if not resolvedId then
		return nil, resolveError
	end
	local ok, storeError = pcall(function()
		banStore:RemoveAsync(tostring(resolvedId))
	end)
	if not ok then
		warn("BravoAdmin: unban could not be saved: " .. tostring(storeError))
		return nil, "Ban storage is unavailable; the ban was not changed."
	end
	addLog(actor, "Unban", tostring(resolvedId), "Ban record removed")
	return { ok = true, message = "Removed ban for user ID " .. tostring(resolvedId) .. "." }
end

local function runCommand(actor, commandLine)
	if not hasPermission(actor, "view") then
		return nil, "Your role cannot use BravoAdmin."
	end
	if type(commandLine) ~= "string" or #commandLine > 300 then
		return nil, "Enter a valid command (maximum 300 characters)."
	end
	local words = {}
	for word in commandLine:gmatch("%S+") do
		table.insert(words, word)
	end
	local command = string.lower(words[1] or ""):gsub("^!", "")
	if command == "help" then
		addLog(actor, "Command", "!help", "Listed available commands")
		return { ok = true, message = "!kick <player> [reason] · !ban <userId> [reason] · !unban <userId> · !server" }
	elseif command == "server" then
		addLog(actor, "Command", "!server", "Viewed server information")
		return {
			ok = true,
			message = string.format("Place %d · %d/%d players · uptime %d seconds",
				game.PlaceId, #Players:GetPlayers(), Players.MaxPlayers, math.floor(os.clock() - startedAt)),
		}
	elseif command == "kick" then
		if #words < 2 then
			return nil, "Usage: !kick <player> [reason]"
		end
		local reason = table.concat(words, " ", 3)
		return kickPlayer(actor, words[2], reason ~= "" and reason or nil)
	elseif command == "ban" then
		if #words < 2 then
			return nil, "Usage: !ban <userId> [reason]"
		end
		local reason = table.concat(words, " ", 3)
		return banUser(actor, words[2], reason ~= "" and reason or nil)
	elseif command == "unban" then
		if #words ~= 2 then
			return nil, "Usage: !unban <userId>"
		end
		return unbanUser(actor, words[2])
	end
	return nil, "Unknown command. Run !help to see available commands."
end

getSnapshot.OnServerInvoke = function(player)
	if not rateLimit(player, "snapshot", 0.2) then
		return { ok = false, error = "Please wait a moment before requesting another update." }
	end
	if not hasPermission(player, "view") then
		return { ok = false, error = "You are not authorized to use BravoAdmin." }
	end
	return buildSnapshot(player)
end

executeAction.OnServerInvoke = function(player, request)
	if not rateLimit(player, "action", 0.35) then
		return { ok = false, error = "Please wait a moment before trying again." }
	end
	if not hasPermission(player, "view") then
		return { ok = false, error = "You are not authorized to use BravoAdmin." }
	end
	if type(request) ~= "table" or type(request.action) ~= "string" then
		return { ok = false, error = "Invalid action request." }
	end

	local result
	local err
	if request.action == "kick" then
		result, err = kickPlayer(player, request.targetUserId, request.reason)
	elseif request.action == "ban" then
		result, err = banUser(player, request.targetUserId, request.reason)
	elseif request.action == "unban" then
		result, err = unbanUser(player, request.targetUserId)
	elseif request.action == "command" then
		result, err = runCommand(player, request.commandLine)
	elseif request.action == "setSetting" then
		if not hasPermission(player, "configure") then
			err = "Only an owner can change server settings."
		elseif request.key ~= "broadcastNotices" or type(request.value) ~= "boolean" then
			err = "Invalid setting request."
		else
			runtimeSettings.broadcastNotices = request.value
			addLog(player, "Setting", "Broadcast notices", request.value and "Enabled" or "Disabled")
			result = { ok = true, message = "Server setting updated." }
		end
	else
		err = "Unknown action."
	end
	return result or { ok = false, error = err or "The action could not be completed." }
end

local function checkBan(player)
	local ok, record = pcall(function()
		return banStore:GetAsync(tostring(player.UserId))
	end)
	if not ok then
		warn("BravoAdmin: could not verify ban status for " .. player.Name .. ": " .. tostring(record))
		player:Kick("Ban status could not be verified. Please rejoin later.")
		return
	end
	if record then
		local reason = type(record) == "table" and sanitizeText(record.reason, 120) or "No reason provided"
		player:Kick("Banned from this experience. Reason: " .. reason)
	end
end

Players.PlayerAdded:Connect(checkBan)
Players.PlayerRemoving:Connect(function(player)
	lastSnapshotAt[player.UserId] = nil
	lastActionAt[player.UserId] = nil
end)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(checkBan, player)
end
