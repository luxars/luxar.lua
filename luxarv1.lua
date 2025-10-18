-- Auto-Joiner Main Script
-- This file should be uploaded to GitHub as a raw file
repeat wait() until game:IsLoaded()

local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local CoreGui = game:GetService("CoreGui")

-- ===============================
-- Load Configuration
-- ===============================
local CONFIG = _G.AutoJoinerConfig or {
    VPS_URL = "https://robloxapiluxars198276354.zeabur.app",
    API_SECRET = "luxarmanagement124356??!!",
    MIN_GENERATION = 1,
    MAX_GENERATION = 999999,
    POLL_INTERVAL = 0.03,
    MAX_JOIN_ATTEMPTS = 10,
    JOIN_ATTEMPT_DELAY = 0.7,
}

local PLACE_ID = game.PlaceId

-- ===============================
-- State Management
-- ===============================
local autoJoinEnabled = false
local notifications = {}
local processedNotifications = {}
local lastNotificationTimestamp = nil
local isConnected = false
local lastPollTime = 0
local hasInitialized = false
local isJoining = false
local joinQueue = {}

-- ===============================
-- UI Creation
-- ===============================
local function createUI()
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "AutoJoinerUI"
    screenGui.ResetOnSpawn = false
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    
    -- Connection Status (Top Left) - BIGGER
    local connectionFrame = Instance.new("Frame")
    connectionFrame.Name = "ConnectionStatus"
    connectionFrame.Size = UDim2.new(0, 150, 0, 45)
    connectionFrame.Position = UDim2.new(0, 10, 0, 10)
    connectionFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    connectionFrame.BorderSizePixel = 0
    connectionFrame.Parent = screenGui
    
    local connectionCorner = Instance.new("UICorner")
    connectionCorner.CornerRadius = UDim.new(0, 8)
    connectionCorner.Parent = connectionFrame
    
    local connectionDot = Instance.new("Frame")
    connectionDot.Name = "Dot"
    connectionDot.Size = UDim2.new(0, 12, 0, 12)
    connectionDot.Position = UDim2.new(0, 12, 0.5, -6)
    connectionDot.BackgroundColor3 = Color3.fromRGB(255, 50, 50)
    connectionDot.BorderSizePixel = 0
    connectionDot.Parent = connectionFrame
    
    local dotCorner = Instance.new("UICorner")
    dotCorner.CornerRadius = UDim.new(1, 0)
    dotCorner.Parent = connectionDot
    
    local connectionText = Instance.new("TextLabel")
    connectionText.Name = "Text"
    connectionText.Size = UDim2.new(1, -35, 1, 0)
    connectionText.Position = UDim2.new(0, 30, 0, 0)
    connectionText.BackgroundTransparency = 1
    connectionText.Text = "Disconnected"
    connectionText.TextColor3 = Color3.fromRGB(255, 255, 255)
    connectionText.TextSize = 16
    connectionText.Font = Enum.Font.GothamBold
    connectionText.TextXAlignment = Enum.TextXAlignment.Center
    connectionText.Parent = connectionFrame
    
    -- Notifications Container (Top Middle) - MUCH BIGGER
    local notificationsFrame = Instance.new("Frame")
    notificationsFrame.Name = "NotificationsContainer"
    notificationsFrame.Size = UDim2.new(0, 600, 0, 600)
    notificationsFrame.Position = UDim2.new(0.5, -300, 0, 10)
    notificationsFrame.BackgroundTransparency = 1
    notificationsFrame.Parent = screenGui
    
    local notificationsList = Instance.new("UIListLayout")
    notificationsList.Name = "Layout"
    notificationsList.SortOrder = Enum.SortOrder.LayoutOrder
    notificationsList.Padding = UDim.new(0, 10)
    notificationsList.Parent = notificationsFrame
    
    -- Auto Join Button (Bottom Right) - BIGGER
    local autoJoinButton = Instance.new("TextButton")
    autoJoinButton.Name = "AutoJoinButton"
    autoJoinButton.Size = UDim2.new(0, 180, 0, 60)
    autoJoinButton.Position = UDim2.new(1, -190, 1, -70)
    autoJoinButton.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
    autoJoinButton.BorderSizePixel = 0
    autoJoinButton.Text = "Auto Join"
    autoJoinButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    autoJoinButton.TextSize = 22
    autoJoinButton.Font = Enum.Font.GothamBold
    autoJoinButton.Parent = screenGui
    
    local autoJoinCorner = Instance.new("UICorner")
    autoJoinCorner.CornerRadius = UDim.new(0, 8)
    autoJoinCorner.Parent = autoJoinButton
    
    pcall(function()
        screenGui.Parent = CoreGui
    end)
    
    if not screenGui.Parent then
        screenGui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
    end
    
    return screenGui, connectionFrame, notificationsFrame, autoJoinButton
end

local screenGui, connectionFrame, notificationsFrame, autoJoinButton = createUI()

-- ===============================
-- Join Server Function with Retry Logic
-- ===============================
local function processJoinQueue()
    if isJoining then return end
    if #joinQueue == 0 then return end
    
    isJoining = true
    local joinData = table.remove(joinQueue, 1)
    local serverId = joinData.serverId
    local brainrotName = joinData.brainrotName
    local generation = joinData.generation
    local queueSize = #joinQueue
    local player = Players.LocalPlayer
    
    print(string.format("[AutoJoiner] 🚀 Starting: %s (%s) | Queue: %d remaining", brainrotName, generation, queueSize))
    
    -- Execute all attempts for THIS notification synchronously
    for attempt = 1, CONFIG.MAX_JOIN_ATTEMPTS do
        pcall(function()
            TeleportService:TeleportToPlaceInstance(PLACE_ID, serverId, player)
        end)
        
        print(string.format("[AutoJoiner] 🔄 Attempt %d/%d: %s", attempt, CONFIG.MAX_JOIN_ATTEMPTS, brainrotName))
        
        -- Delay between attempts (except after the last one)
        if attempt < CONFIG.MAX_JOIN_ATTEMPTS then
            task.wait(CONFIG.JOIN_ATTEMPT_DELAY)
        end
    end
    
    -- Mark as no longer joining
    isJoining = false
    
    -- Process next in queue after a small delay
    if #joinQueue > 0 then
        task.wait(0.1) -- Delay before processing next notification
        processJoinQueue()
    end
end

local function attemptJoinServer(serverId, brainrotName, generation)
    -- Add to queue
    table.insert(joinQueue, {
        serverId = serverId,
        brainrotName = brainrotName,
        generation = generation
    })
    
    if not isJoining then
        processJoinQueue()
    end
end

-- ===============================
-- UI Update Functions
-- ===============================
local function updateConnectionStatus(connected)
    if isConnected == connected then return end
    
    isConnected = connected
    local dot = connectionFrame:FindFirstChild("Dot")
    local text = connectionFrame:FindFirstChild("Text")
    
    if connected then
        dot.BackgroundColor3 = Color3.fromRGB(50, 255, 50)
        text.Text = "Connected"
    else
        dot.BackgroundColor3 = Color3.fromRGB(255, 50, 50)
        text.Text = "Disconnected"
    end
end

local function createNotificationButton(brainrotName, generation, serverId, layoutOrder)
    local button = Instance.new("TextButton")
    button.Name = "Notification_" .. serverId
    button.Size = UDim2.new(1, 0, 0, 100) -- MUCH BIGGER
    button.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
    button.BorderSizePixel = 0
    button.Text = brainrotName .. " - " .. generation
    button.TextColor3 = Color3.fromRGB(255, 255, 255)
    button.TextSize = 22 -- MUCH BIGGER TEXT
    button.Font = Enum.Font.GothamBold
    button.LayoutOrder = layoutOrder
    button.ClipsDescendants = true
    button.Parent = notificationsFrame
    
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 10)
    corner.Parent = button
    
    -- Animate in
    button.Size = UDim2.new(1, 0, 0, 0)
    button:TweenSize(UDim2.new(1, 0, 0, 100), Enum.EasingDirection.Out, Enum.EasingStyle.Back, 0.3, true)
    
    -- Click to join
    button.MouseButton1Click:Connect(function()
        attemptJoinServer(serverId, brainrotName, generation)
    end)
    
    -- Auto-remove after 10 seconds
    task.delay(10, function()
        if button and button.Parent then
            button:TweenSize(UDim2.new(1, 0, 0, 0), Enum.EasingDirection.In, Enum.EasingStyle.Quad, 0.3, true)
            task.wait(0.3)
            button:Destroy()
        end
    end)
    
    return button
end

local function updateAutoJoinButton()
    if autoJoinEnabled then
        autoJoinButton.BackgroundColor3 = Color3.fromRGB(50, 200, 50)
        print("[AutoJoiner] ✅ Auto Join ENABLED")
    else
        autoJoinButton.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
        print("[AutoJoiner] ⏸️ Auto Join DISABLED")
    end
end

autoJoinButton.MouseButton1Click:Connect(function()
    autoJoinEnabled = not autoJoinEnabled
    updateAutoJoinButton()
end)

-- ===============================
-- API Communication
-- ===============================
local function fetchNotifications()
    local success, result = pcall(function()
        local headers = {
            ["Authorization"] = "Bearer " .. CONFIG.API_SECRET,
            ["Content-Type"] = "application/json"
        }
        
        local url = string.format(
            "%s/notifications?min_gen=%d&max_gen=%d",
            CONFIG.VPS_URL,
            CONFIG.MIN_GENERATION,
            CONFIG.MAX_GENERATION
        )
        
        local response = request({
            Url = url,
            Method = "GET",
            Headers = headers
        })
        
        if response and response.StatusCode == 200 then
            local data = HttpService:JSONDecode(response.Body)
            return data.notifications or {}
        else
            return nil
        end
    end)
    
    if success and result then
        return result
    else
        return nil
    end
end

-- ===============================
-- Notification Processing
-- ===============================
local layoutOrder = 0

local function processNotifications(newNotifications)
    if not newNotifications or #newNotifications == 0 then
        return
    end
    
    -- FIRST TIME ONLY: Set baseline without showing anything
    if not hasInitialized then
        -- Find the most recent timestamp from existing logs
        for _, notification in ipairs(newNotifications) do
            local notifTimestamp = notification.timestamp
            if not lastNotificationTimestamp or notifTimestamp > lastNotificationTimestamp then
                lastNotificationTimestamp = notifTimestamp
            end
        end
        hasInitialized = true
        print("[AutoJoiner] 📋 Synced with API - tracking new notifications")
        return
    end
    
    -- AFTER INITIALIZATION: Process only NEW notifications
    local newCount = 0
    
    for _, notification in ipairs(newNotifications) do
        local notifTimestamp = notification.timestamp
        
        -- Only process notifications newer than our last seen timestamp
        if not lastNotificationTimestamp or notifTimestamp > lastNotificationTimestamp then
            local serverId = notification.server_id
            local brainrotName = notification.name
            local generation = notification.generation
            
            -- Check if we've already processed this notification
            local notifKey = serverId .. "_" .. brainrotName .. "_" .. notifTimestamp
            if not processedNotifications[notifKey] then
                processedNotifications[notifKey] = true
                newCount = newCount + 1
                
                print(string.format("[AutoJoiner] 📢 NEW: %s (%s)", brainrotName, generation))
                
                -- Create notification button
                layoutOrder = layoutOrder + 1
                createNotificationButton(brainrotName, generation, serverId, layoutOrder)
                
                -- Update last seen timestamp
                lastNotificationTimestamp = notifTimestamp
                
                -- Auto-join if enabled
                if autoJoinEnabled then
                    attemptJoinServer(serverId, brainrotName, generation)
                end
            end
        end
    end
end

-- ===============================
-- Main Loop
-- ===============================
local function startPolling()
    print("[AutoJoiner] 🚀 Polling started")
    
    while true do
        local currentTime = tick()
        
        if currentTime - lastPollTime >= CONFIG.POLL_INTERVAL then
            lastPollTime = currentTime
            
            local notifications = fetchNotifications()
            
            if notifications then
                updateConnectionStatus(true)
                processNotifications(notifications)
            else
                updateConnectionStatus(false)
            end
        end
        
        task.wait(0.05)
    end
end

-- ===============================
-- Cleanup old processed notifications
-- ===============================
task.spawn(function()
    while true do
        task.wait(60)
        local count = 0
        for k, v in pairs(processedNotifications) do
            count = count + 1
        end
        
        if count > 100 then
            local toRemove = {}
            local i = 0
            for k, v in pairs(processedNotifications) do
                if i >= 50 then break end
                table.insert(toRemove, k)
                i = i + 1
            end
            for _, k in ipairs(toRemove) do
                processedNotifications[k] = nil
            end
        end
    end
end)

-- ===============================
-- Start the auto-joiner
-- ===============================
print("===========================================")
print("[AutoJoiner] 🎮 Auto-Joiner Main Script Loaded")
print("[AutoJoiner] 🎯 Tracking:", CONFIG.MIN_GENERATION .. " -", CONFIG.MAX_GENERATION)
print("[AutoJoiner] ⚙️ Config:", CONFIG.MAX_JOIN_ATTEMPTS, "attempts @", CONFIG.JOIN_ATTEMPT_DELAY .. "s delay")
print("===========================================")

updateAutoJoinButton()
updateConnectionStatus(false)

task.spawn(startPolling)

TeleportService.TeleportInitFailed:Connect(function(player, result, errorMessage)
    warn("[AutoJoiner] ❌ Teleport failed:", errorMessage)
end)
