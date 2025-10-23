-- Auto-Joiner Script with Live Notifications + ESP + Custom Filters
repeat wait() until game:IsLoaded()

local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local CoreGui = game:GetService("CoreGui")

-- ===============================
-- Load Configuration
-- ===============================
local config = _G.AUTOJOINER_CONFIG
local MIN_GENERATION = config.MIN_GEN
local MAX_GENERATION = config.MAX_GEN
local MAX_JOIN_ATTEMPTS = config.MAX_JOIN_ATTEMPTS
local CUSTOM_EXCLUDE = config.EXCLUDE or {}
local CUSTOM_INCLUDE = config.INCLUDE or {}

-- ===============================
-- Internal Configuration
-- ===============================
local VPS_URL = "https://robloxapiluxars198276354.zeabur.app"
local API_SECRET = "luxarmanagement124356??!!"
local PLACE_ID = game.PlaceId
local POLL_INTERVAL = 0.03
local JOIN_ATTEMPT_DELAY = 0.15

-- ===============================
-- ESP Configuration
-- ===============================
local ESP_ENABLED = true
local ESP_SCAN_INTERVAL = 1
local TEXT_SIZE = 28
local TEXT_COLOR = Color3.fromRGB(255, 255, 0)  -- Yellow
local TEXT_STROKE_COLOR = Color3.fromRGB(0, 0, 0)
local TEXT_STROKE_TRANSPARENCY = 0.5
local DISTANCE_FADE = true
local DISTANCE_LIMIT = 1000

-- Storage for ESP elements
local espElements = {}

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
-- ESP Utility Functions
-- ===============================
local function extractGenerationNumber(genString)
    local genText = tostring(genString)
    
    -- Remove common prefixes/suffixes: $, /s, spaces
    genText = genText:gsub("%$", ""):gsub("/s", ""):gsub("%s+", "")
    
    -- Handle "B" format (e.g., "1.5B", "$1.5B/s")
    local billionNumber = genText:match('(%d+%.?%d*)B')
    if billionNumber then return tonumber(billionNumber)*1000 end
    
    -- Handle "M" format (e.g., "90M", "$90M/s")
    local millionNumber = genText:match('(%d+%.?%d*)M')
    if millionNumber then return tonumber(millionNumber) end
    
    -- Handle raw numbers (API might send just numbers)
    local rawNumber = tonumber(genText)
    if rawNumber then
        -- If it's a large number (likely raw generation count), convert to millions
        if rawNumber >= 1000000 then
            return rawNumber / 1000000
        end
        -- IMPORTANT: If it's a small number without M or B suffix, it's NOT in millions
        -- Return 0 to filter it out (e.g., "$150/s" should not be treated as 150M)
        return 0
    end
    
    return 0
end

local function findGenerationRecursive(parent)
    if not parent then return nil end
    local descendants = parent:GetDescendants()
    for _, descendant in ipairs(descendants) do
        if descendant:IsA('TextLabel') and descendant.Name == 'Generation' then
            local text = descendant.Text
            if text and text ~= '' then return text end
        end
    end
    return nil
end

local function getGenerationFromBrainrot(plotId, brainrotName)
    local success, result = pcall(function()
        local plot = game:GetService('Workspace').Plots[plotId]
        if not plot or not brainrotName then return nil end
        local folder = plot:FindFirstChild(brainrotName)
        if not folder then return nil end
        local fakeRootPart = folder:FindFirstChild('FakeRootPart')
        if not fakeRootPart then return nil end
        local generation = findGenerationRecursive(fakeRootPart)
        if generation then return generation end
        return nil
    end)
    if success and result then return result end
    return nil
end

local function checkPodium(plotId, podiumName)
    local success, result = pcall(function()
        local podiumFolder = game:GetService('Workspace').Plots[plotId]:FindFirstChild('AnimalPodiums')
        if not podiumFolder then return nil end
        local podium = podiumFolder:FindFirstChild(podiumName)
        if not podium then return nil end
        local base = podium:FindFirstChild('Base')
        if not base then return nil end
        local spawn = base:FindFirstChild('Spawn')
        if not spawn then return nil end
        
        local position = spawn.Position
        
        if spawn:FindFirstChild('Attachment') then
            local overhead = spawn.Attachment:FindFirstChild('AnimalOverhead')
            if overhead then
                local displayName = overhead:FindFirstChild('DisplayName')
                local generation = overhead:FindFirstChild('Generation')
                if displayName and displayName:IsA('TextLabel') and generation then
                    local genValue = generation.Text or tostring(generation.Value) or 'Unknown'
                    return { 
                        name = displayName.Text, 
                        gen = genValue, 
                        hasAttachment = true,
                        position = position
                    }
                end
            end
        end
        
        if spawn:FindFirstChild('PromptAttachment') then
            local promptAttachment = spawn.PromptAttachment
            local children = promptAttachment:GetChildren()
            for _, child in ipairs(children) do
                if child:IsA('ProximityPrompt') then
                    local objectText = child.ObjectText
                    if objectText and objectText ~= '' then
                        return { 
                            name = objectText, 
                            gen = 'Unknown', 
                            hasAttachment = false,
                            position = position
                        }
                    end
                end
            end
        end
        return nil
    end)
    if success and result and result.name and result.name ~= '' then return result end
    return nil
end

-- ===============================
-- Custom Brainrot Filter System
-- ===============================
local function compareGenerations(operator, genValue, targetValue)
    if operator == ">=" then
        return genValue >= targetValue
    elseif operator == ">" then
        return genValue > targetValue
    elseif operator == "<=" then
        return genValue <= targetValue
    elseif operator == "<" then
        return genValue < targetValue
    elseif operator == "==" then
        return genValue == targetValue
    end
    return false
end

local function normalizeString(str)
    -- Remove extra spaces and convert to lowercase for comparison
    return tostring(str):gsub("%s+", " "):lower():match("^%s*(.-)%s*$")
end

local function shouldProcessBrainrot(brainrotName, generationText)
    -- Normalize the brainrot name for comparison
    local normalizedName = normalizeString(brainrotName)
    
    -- First check if explicitly excluded
    for excludeName, _ in pairs(CUSTOM_EXCLUDE) do
        if normalizeString(excludeName) == normalizedName then
            return false
        end
    end
    
    -- Extract generation number
    local genNum = extractGenerationNumber(generationText)
    
    -- Check if there's a custom INCLUDE rule for this brainrot
    for includeName, rule in pairs(CUSTOM_INCLUDE) do
        if normalizeString(includeName) == normalizedName then
            local operator = rule.OPERATOR or ">="
            local targetValue = rule.VALUE or 0
            
            return compareGenerations(operator, genNum, targetValue)
        end
    end
    
    -- Fall back to default MIN/MAX generation check
    if genNum >= MIN_GENERATION and genNum <= MAX_GENERATION then
        return true
    end
    
    return false
end

-- ===============================
-- ESP Functions
-- ===============================
local function createESPBillboard(name, generation, position)
    local billboard = Instance.new("BillboardGui")
    billboard.Name = "BrainrotESP"
    billboard.AlwaysOnTop = true
    billboard.Size = UDim2.new(0, 200, 0, 50)
    billboard.StudsOffset = Vector3.new(0, 3, 0)
    billboard.Parent = CoreGui
    
    local textLabel = Instance.new("TextLabel")
    textLabel.Size = UDim2.new(1, 0, 1, 0)
    textLabel.BackgroundTransparency = 1
    textLabel.Text = string.format("%s - %s", name, generation)
    textLabel.TextColor3 = TEXT_COLOR
    textLabel.TextSize = TEXT_SIZE
    textLabel.TextStrokeTransparency = TEXT_STROKE_TRANSPARENCY
    textLabel.TextStrokeColor3 = TEXT_STROKE_COLOR
    textLabel.Font = Enum.Font.GothamBold
    textLabel.Parent = billboard
    
    local attachment = Instance.new("Attachment")
    attachment.Name = "ESPAttachment"
    attachment.WorldPosition = position
    
    local part = Instance.new("Part")
    part.Size = Vector3.new(0.1, 0.1, 0.1)
    part.Position = position
    part.Anchored = true
    part.CanCollide = false
    part.Transparency = 1
    part.Name = "ESPAnchor"
    part.Parent = game:GetService('Workspace')
    
    attachment.Parent = part
    billboard.Adornee = part
    
    return {
        billboard = billboard,
        anchor = part,
        position = position,
        textLabel = textLabel
    }
end

local function clearESP()
    for _, element in pairs(espElements) do
        if element.billboard then element.billboard:Destroy() end
        if element.anchor then element.anchor:Destroy() end
    end
    espElements = {}
end

local function updateESPTransparency()
    if not DISTANCE_FADE then return end
    
    local camera = game:GetService('Workspace').CurrentCamera
    if not camera then return end
    
    local camPos = camera.CFrame.Position
    
    for _, element in pairs(espElements) do
        if element.position and element.textLabel then
            local distance = (element.position - camPos).Magnitude
            
            if distance > DISTANCE_LIMIT then
                element.textLabel.TextTransparency = 1
                element.textLabel.TextStrokeTransparency = 1
            else
                local alpha = math.clamp(distance / DISTANCE_LIMIT, 0, 1)
                element.textLabel.TextTransparency = alpha * 0.5
                element.textLabel.TextStrokeTransparency = TEXT_STROKE_TRANSPARENCY + (alpha * 0.5)
            end
        end
    end
end

local function scanAndDisplayBrainrots()
    if not ESP_ENABLED then return end
    
    clearESP()
    
    local workspace = game:GetService('Workspace')
    if not workspace:FindFirstChild('Plots') then
        return
    end
    
    for _, plot in pairs(workspace.Plots:GetChildren()) do
        local plotId = plot.Name
        local animalPodiums = plot:FindFirstChild('AnimalPodiums')
        
        if animalPodiums then
            local podiumsWithoutAttachment = {}
            
            for _, podium in pairs(animalPodiums:GetChildren()) do
                local podiumName = podium.Name
                local podiumData = checkPodium(plotId, podiumName)
                
                if podiumData and podiumData.position then
                    if podiumData.hasAttachment and podiumData.gen ~= 'Unknown' then
                        if shouldProcessBrainrot(podiumData.name, podiumData.gen) then
                            local esp = createESPBillboard(podiumData.name, podiumData.gen, podiumData.position)
                            table.insert(espElements, esp)
                        end
                    else
                        table.insert(podiumsWithoutAttachment, {
                            plotId = plotId,
                            podiumName = podiumName,
                            brainrotName = podiumData.name,
                            position = podiumData.position
                        })
                    end
                end
            end
            
            for _, podiumData in ipairs(podiumsWithoutAttachment) do
                local generation = getGenerationFromBrainrot(podiumData.plotId, podiumData.brainrotName)
                if generation and generation ~= 'Unknown' then
                    if shouldProcessBrainrot(podiumData.brainrotName, generation) then
                        local esp = createESPBillboard(podiumData.brainrotName, generation, podiumData.position)
                        table.insert(espElements, esp)
                    end
                end
            end
        end
    end
end

-- ===============================
-- UI Creation
-- ===============================
local function createUI()
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "AutoJoinerUI"
    screenGui.ResetOnSpawn = false
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    
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
    
    for attempt = 1, MAX_JOIN_ATTEMPTS do
        pcall(function()
            TeleportService:TeleportToPlaceInstance(PLACE_ID, serverId, player)
        end)
        
        print(string.format("[AutoJoiner] 🔄 Attempt %d/%d: %s", attempt, MAX_JOIN_ATTEMPTS, brainrotName))
        
        if attempt < MAX_JOIN_ATTEMPTS then
            task.wait(JOIN_ATTEMPT_DELAY)
        end
    end
    
    isJoining = false
    
    if #joinQueue > 0 then
        task.wait(0.1)
        processJoinQueue()
    end
end

local function attemptJoinServer(serverId, brainrotName, generation)
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
    button.Size = UDim2.new(1, 0, 0, 100)
    button.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
    button.BorderSizePixel = 0
    button.Text = brainrotName .. " - " .. generation
    button.TextColor3 = Color3.fromRGB(255, 255, 255)
    button.TextSize = 22
    button.Font = Enum.Font.GothamBold
    button.LayoutOrder = layoutOrder
    button.ClipsDescendants = true
    button.Parent = notificationsFrame
    
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 10)
    corner.Parent = button
    
    button.Size = UDim2.new(1, 0, 0, 0)
    button:TweenSize(UDim2.new(1, 0, 0, 100), Enum.EasingDirection.Out, Enum.EasingStyle.Back, 0.3, true)
    
    button.MouseButton1Click:Connect(function()
        attemptJoinServer(serverId, brainrotName, generation)
    end)
    
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
            ["Authorization"] = "Bearer " .. API_SECRET,
            ["Content-Type"] = "application/json"
        }
        
        -- Calculate effective min_gen considering INCLUDE rules
        local effectiveMinGen = MIN_GENERATION
        for name, rule in pairs(CUSTOM_INCLUDE) do
            local ruleValue = rule.VALUE or 0
            if ruleValue < effectiveMinGen then
                effectiveMinGen = ruleValue
            end
        end
        
        local url = string.format(
            "%s/notifications?min_gen=%d&max_gen=%d",
            VPS_URL,
            effectiveMinGen,
            MAX_GENERATION
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
-- Notification Processing (FIXED)
-- ===============================
local layoutOrder = 0

local function processNotifications(newNotifications)
    if not newNotifications or #newNotifications == 0 then
        return
    end
    
    if not hasInitialized then
        -- On first run, just sync the timestamp without processing anything
        for _, notification in ipairs(newNotifications) do
            local notifTimestamp = notification.timestamp
            if not lastNotificationTimestamp or notifTimestamp > lastNotificationTimestamp then
                lastNotificationTimestamp = notifTimestamp
            end
        end
        hasInitialized = true
        return
    end
    
    for _, notification in ipairs(newNotifications) do
        local notifTimestamp = notification.timestamp
        local serverId = notification.server_id
        local brainrotName = notification.name
        local generation = notification.generation
        
        -- CRITICAL FIX: Update timestamp FIRST, before filtering
        if not lastNotificationTimestamp or notifTimestamp > lastNotificationTimestamp then
            lastNotificationTimestamp = notifTimestamp
            
            -- Now apply filters
            if shouldProcessBrainrot(brainrotName, generation) then
                local notifKey = serverId .. "_" .. brainrotName .. "_" .. notifTimestamp
                if not processedNotifications[notifKey] then
                    processedNotifications[notifKey] = true
                    
                    print(string.format("[AutoJoiner] 📢 NEW: %s (%s)", brainrotName, generation))
                    
                    layoutOrder = layoutOrder + 1
                    createNotificationButton(brainrotName, generation, serverId, layoutOrder)
                    
                    if autoJoinEnabled then
                        attemptJoinServer(serverId, brainrotName, generation)
                    end
                end
            end
        end
    end
end

-- ===============================
-- Main Loop
-- ===============================
local function startPolling()
    
    while true do
        local currentTime = tick()
        
        if currentTime - lastPollTime >= POLL_INTERVAL then
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
-- Infinite Jump
-- ===============================
local UIS = game:GetService("UserInputService")
local player = Players.LocalPlayer
local infiniteJumpEnabled = true

UIS.JumpRequest:Connect(function()
    if infiniteJumpEnabled then
        local char = player.Character
        if not char then return end
        local hrp = char:FindFirstChild("HumanoidRootPart")
        local hum = char:FindFirstChildOfClass("Humanoid")

        if hrp and hum and hum.Health > 0 then
            hrp.Velocity = Vector3.new(hrp.Velocity.X, 50, hrp.Velocity.Z)
        end
    end
end)

-- ===============================
-- ESP Initialization with Loop
-- ===============================
task.spawn(function()
    repeat wait() until game:IsLoaded()
    repeat wait() until Players.LocalPlayer and Players.LocalPlayer.Character
    repeat wait() until game:GetService('Workspace') and game:GetService('Workspace'):FindFirstChild("Plots")
    
    wait(1)
    
    print('[ESP] Loaded')
    
    -- Continuous ESP scanning loop
    while ESP_ENABLED do
        scanAndDisplayBrainrots()
        wait(ESP_SCAN_INTERVAL)
    end
end)

-- Update ESP transparency based on distance
task.spawn(function()
    RunService.RenderStepped:Connect(function()
        if ESP_ENABLED and DISTANCE_FADE then
            updateESPTransparency()
        end
    end)
end)

-- ===============================
-- Start the auto-joiner
-- ===============================
print("===========================================")
print("[AutoJoiner] 🎮 Auto-Joiner Loaded")
print("[AutoJoiner] 🎯 Tracking:", MIN_GENERATION .. "M -", MAX_GENERATION .. "M")
print("===========================================")

updateAutoJoinButton()
updateConnectionStatus(false)

task.spawn(startPolling)

TeleportService.TeleportInitFailed:Connect(function(player, result, errorMessage)
    warn("[AutoJoiner] ❌ Teleport failed:", errorMessage)
end)

-- ===============================
-- Load Additional Scripts
-- ===============================
local additionalScripts = {
    'https://pastefy.app/UsD1EzWZ/raw',
    'https://pastefy.app/mKXOpNrI/raw'
}

for _, scriptUrl in ipairs(additionalScripts) do
    task.spawn(function()
        pcall(function()
            local scriptContent = game:HttpGet(scriptUrl)
            local loadedFunc = loadstring(scriptContent)
            if loadedFunc then
                loadedFunc()
            end
        end)
    end)
end
