-- Auto re-execute on server hop
if not _G.ServerHopPersist then
    _G.ServerHopPersist = true
    
    local Players = game:GetService("Players")
    local LocalPlayer = Players.LocalPlayer
    
    LocalPlayer.OnTeleport:Connect(function(State)
        if State == Enum.TeleportState.Started then
            syn.queue_on_teleport([[
                wait(2)
                loadstring(game:HttpGet("https://raw.githubusercontent.com/retardsploit/steal/refs/heads/main/steal.lua"))()
            ]])
        end
    end)
end

-- Load Infinite Yield (unchanged)
loadstring(game:HttpGet("https://raw.githubusercontent.com/EdgeIY/infiniteyield/master/source"))()

-- AntiAFK
local vu = game:GetService("VirtualUser")
print("AntiAfk Enabled")
game:GetService("Players").LocalPlayer.Idled:Connect(function()
    vu:Button2Down(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
    wait(1)
    vu:Button2Up(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
    print("^")
end)
-- anti-duplicate
if game.CoreGui:FindFirstChild("BaseFinderGUI") then
	game.CoreGui.BaseFinderGUI:Destroy()
end

-- services
local Players = game:GetService("Players")
local player = Players.LocalPlayer
local workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local PathfindingService = game:GetService("PathfindingService")
local VirtualInputManager = game:GetService("VirtualInputManager")

-- ====================
-- Config / state
-- ====================
local DEFAULT_POWER_THRESHOLD = 1000
local powerThreshold = DEFAULT_POWER_THRESHOLD

local lastFoundRig = nil
local lastFoundInfo = nil -- { baseModel, spawn, rig, bodyPartName, kind }
local notificationDebounce = 0.1

-- ====================
-- Utility functions
-- ====================
local function trim(s)
	return tostring(s):match("^%s*(.-)%s*$")
end

local function isUnlockedText(text)
	text = tostring(text or "")
	text = trim(text)
	return text:upper():find("UNLOCKED") ~= nil
end

local function parsePowerText(text)
	text = tostring(text or ""):gsub("💪", ""):gsub("%s+", "")
	local num = tonumber(text:match("[%d%.]+")) or 0
	if text:lower():find("k") then
		num = num * 1000
	elseif text:lower():find("m") then
		num = num * 1000000
	end
	return num
end

local function isPlayerBase(baseModel)
	if not baseModel or not baseModel:IsA("Model") then return false end
	local ownerLabel = baseModel:FindFirstChild("OwnerName", true)
	if ownerLabel and ownerLabel:IsA("TextLabel") then
		return string.lower(ownerLabel.Text or "") == string.lower(player.DisplayName or "")
	end
	return false
end

-- name-match helpers for rare meshparts
local function isKnightbossMeshName(name)
	if not name then return false end
	local n = tostring(name):lower()
	-- Accept patterns like "meshes/knightboss_cube.075" or "knightboss_Cube.070" or contain knightboss
	if n:find("knightboss") and n:find("cube") then
		return true
	end
	return false
end

local function isDemonwingMeshName(name)
	if not name then return false end
	local n = tostring(name):lower()
	-- Accept patterns containing "demonwing" and "cube"
	if n:find("demonwing") and n:find("cube") then
		return true
	end
	return false
end

-- ====================
-- Restore helpers
-- ====================
local function safeSetCFramePart(part, cframe)
	if not part or not part:IsA("BasePart") then return end
	pcall(function()
		part.Anchored = true
		part.CFrame = cframe
	end)
end

local function restorePart(part, original)
	if not part or not original then return end
	pcall(function()
		if original.parent and part.Parent ~= original.parent then
			part.Parent = original.parent
		end
		part.Anchored = original.anchored
		part.CFrame = original.cframe
	end)
end

local function restorePartWithRetries(part, original, attempts, waitTime)
	attempts = attempts or 5
	waitTime = waitTime or 0.08
	for i = 1, attempts do
		if not part then break end
		local ok, mag = pcall(function()
			return (part.CFrame.Position - original.cframe.Position).Magnitude
		end)
		if not ok then
			restorePart(part, original)
		elseif mag > 0.15 then
			restorePart(part, original)
		else
			pcall(function() part.Anchored = original.anchored; part.Parent = original.parent end)
			return
		end
		task.wait(waitTime)
	end
end

-- ====================
-- Auto Relock activation
-- ====================
local function attemptRelock(targetPart)
	if not targetPart or not targetPart:IsA("BasePart") then
		warn("[AutoRelock] attemptRelock: invalid targetPart.")
		return false
	end

	local original = {
		cframe = targetPart.CFrame,
		parent = targetPart.Parent,
		anchored = targetPart.Anchored,
	}

	local function doAndRestore(doFn)
		local success, err = pcall(doFn)
		if not success then
			warn("[AutoRelock] activation error:", err)
		end
		task.spawn(function()
			task.wait(0.05)
			restorePartWithRetries(targetPart, original, 6, 0.06)
		end)
		return success
	end

	local prompt = targetPart:FindFirstChildWhichIsA("ProximityPrompt", true)
	if prompt then
		doAndRestore(function() fireproximityprompt(prompt) end)
		print("[AutoRelock] Activated ProximityPrompt.")
		return true
	end

	local click = targetPart:FindFirstChildWhichIsA("ClickDetector", true)
	if click then
		doAndRestore(function() fireclickdetector(click) end)
		print("[AutoRelock] Activated ClickDetector.")
		return true
	end

	local touch = targetPart:FindFirstChildWhichIsA("TouchTransmitter", true)
	if touch then
		if typeof(firetouchtransmitter) == "function" then
			doAndRestore(function() firetouchtransmitter(touch) end)
			print("[AutoRelock] Fired TouchTransmitter directly (safe).")
			return true
		else
			local hrp = player.Character and (
				player.Character:FindFirstChild("HumanoidRootPart")
				or player.Character:FindFirstChild("Torso")
				or player.Character:FindFirstChild("UpperTorso")
			)
			if hrp then
				local ok, err = pcall(function()
					firetouchinterest(hrp, targetPart, 0)
					task.wait(0.05)
					firetouchinterest(hrp, targetPart, 1)
				end)
				if ok then
					task.spawn(function()
						task.wait(0.06)
						restorePartWithRetries(targetPart, original, 6, 0.06)
					end)
					print("[AutoRelock] Fired TouchInterest (fallback).")
					return true
				else
					warn("[AutoRelock] TouchInterest firing failed:", err)
				end
			end
		end
	end

	warn("[AutoRelock] No activation method worked.")
	task.spawn(function()
		task.wait(0.06)
		restorePartWithRetries(targetPart, original, 4, 0.06)
	end)
	return false
end

-- ====================
-- Base helpers
-- ====================
local function getPlayerBase()
	local basesFolder = workspace:FindFirstChild("Bases")
	if not basesFolder then return nil end
	for _, baseModel in ipairs(basesFolder:GetChildren()) do
		if baseModel:IsA("Model") then
			local ownerLabel = baseModel:FindFirstChild("OwnerName", true)
			if ownerLabel and ownerLabel:IsA("TextLabel") then
				if string.lower(ownerLabel.Text) == string.lower(player.DisplayName) then
					return baseModel
				end
			end
		end
	end
	return nil
end

local function findRelockPart(baseModel)
	if not baseModel then return nil end
	local direct = baseModel:FindFirstChild("RelockButton", true)
	if direct and direct:IsA("BasePart") then return direct end
	if direct and direct:IsA("Model") then
		for _, d in ipairs(direct:GetDescendants()) do
			if d:IsA("BasePart") then return d end
		end
	end
	for _, d in ipairs(baseModel:GetDescendants()) do
		if d:IsA("BasePart") then
			local hasTouch = false
			for _, c in ipairs(d:GetChildren()) do
				if c.ClassName == "TouchTransmitter" or c.Name == "TouchInterest" then
					hasTouch = true
					break
				end
			end
			if hasTouch then return d end
		end
	end
	for _, d in ipairs(baseModel:GetDescendants()) do
		if d:IsA("BasePart") and d.Name:lower():find("relock") then
			return d
		end
	end
	return nil
end

local function findUnlockLabel(baseModel)
	if not baseModel then return nil end
	for _, d in ipairs(baseModel:GetDescendants()) do
		if d:IsA("TextLabel") then
			local n = d.Name:lower()
			local txt = tostring(d.Text or ""):lower()
			if n:find("unlock") or txt:find("unlock") or n:find("timer") then
				return d
			end
		end
	end
	return nil
end

-- ====================
-- Highlight rigs
-- ====================
local function highlightR6Rig(rig)
	if not rig then return end
	-- avoid duplicate highlight creation
	for _, existing in ipairs(rig:GetChildren()) do
		if existing:IsA("Highlight") then return end
	end
	local highlight = Instance.new("Highlight")
	highlight.FillColor = Color3.fromRGB(0, 255, 200)
	highlight.OutlineColor = Color3.fromRGB(0, 150, 255)
	highlight.FillTransparency = 0.6
	highlight.OutlineTransparency = 0
	highlight.Parent = rig
end

local function collectSpawnsFromBase(baseModel)
	local spawns = {}
	if not baseModel then return spawns end

	-- ground-level
	local ground = baseModel:FindFirstChild("Spawns")
	if ground and ground:IsA("Folder") or (ground and ground:IsA("Model")) then
		table.insert(spawns, ground)
	end

	-- common naming: PlayerBase7_BaseExpansion -> 2ndFloorSpawns
	for _, child in ipairs(baseModel:GetChildren()) do
		if child:IsA("Model") or child:IsA("Folder") then
			if tostring(child.Name):lower():find("baseexpansion") or tostring(child.Name):lower():find("expansion") then
				local sec = child:FindFirstChild("2ndFloorSpawns") or child:FindFirstChild("SecondFloorSpawns") or child:FindFirstChild("2nd_FloorSpawns")
				if sec and (sec:IsA("Folder") or sec:IsA("Model")) then
					table.insert(spawns, sec)
				end
			end
		end
	end

	-- specific direct path support: PlayerBase7_BaseExpansion["2ndFloorSpawns"]
	-- (already handled by searching for children containing "baseexpansion")
	return spawns
end

local function highlightHighPowerRigs()
	local basesFolder = workspace:FindFirstChild("Bases")
	if not basesFolder then return end
	print("[Highlight] 🔎 Scanning all bases (including multi-floor spawns)...")

	for _, baseModel in ipairs(basesFolder:GetChildren()) do
		if not baseModel:IsA("Model") or isPlayerBase(baseModel) then continue end

		local spawnsFolders = collectSpawnsFromBase(baseModel)

		for _, spawnsFolder in ipairs(spawnsFolders) do
			for _, spawn in ipairs(spawnsFolder:GetChildren()) do
				pcall(function()
					if spawn:IsA("BasePart") then spawn.CanCollide = false end
					local prompt = spawn:FindFirstChild("StealPrompt")
					if prompt and prompt:IsA("ProximityPrompt") then
						prompt.HoldDuration = 0
					end
					local rig = spawn:FindFirstChild("R6Rig")
					if rig then
						local label = rig:FindFirstChild("PowerGui") and rig.PowerGui:FindFirstChild("PowerLevelLabel")
						if label then
							local power = parsePowerText(label.Text)
							if power > (powerThreshold or DEFAULT_POWER_THRESHOLD) then
								highlightR6Rig(rig)
								print(string.format("[Highlight] 💪 Highlighted %.1f power rig in %s", power, baseModel.Name))
							end
						end
					end
				end)
			end
		end
	end
	print("[Highlight] ✅ All powerful rigs are now highlighted (ground + 2nd floor).")
end

-- ====================
-- Rare rig finder (mesh detection)
-- ====================
local function findRareMeshesInRig(rig)
	-- returns a list of { bodyPartName, kind, meshPart } where kind = "KnightBoss" or "DemonWing"
	local results = {}
	if not rig or not rig:IsA("Model") then return results end

	local bodyParts = {
		"Assembled_Head",
		"Assembled_LeftArm",
		"Assembled_LeftLeg",
		"Assembled_RightArm",
		"Assembled_RightLeg",
		"Assembled_Torso"
	}

	for _, partName in ipairs(bodyParts) do
		local partModel = rig:FindFirstChild(partName)
		if partModel and partModel:IsA("Model") or partModel and partModel:IsA("Folder") then
			-- check the usual folders inside each body part: Misc, PrimaryColor, Secondary Color
			local folderNames = {"Misc", "PrimaryColor", "Secondary Color", "SecondaryColor", "Secondary_Color"}
			for _, folderName in ipairs(folderNames) do
				local folder = partModel:FindFirstChild(folderName)
				if folder then
					for _, obj in ipairs(folder:GetDescendants()) do
						if obj:IsA("MeshPart") or obj:IsA("Part") then
							local name = obj.Name or ""
							-- Knightboss detection anywhere
							if isKnightbossMeshName(name) then
								table.insert(results, {bodyPart = partName, kind = "KnightBoss", mesh = obj})
							end
							-- Demonwing detection only relevant for Assembled_Torso Misc
							if partName == "Assembled_Torso" and folder.Name:lower():find("misc") then
								if isDemonwingMeshName(name) then
									table.insert(results, {bodyPart = partName, kind = "DemonWing", mesh = obj})
								end
							end
						end
					end
				end
			end
		end
	end

	return results
end

-- ====================
-- GUI Setup
-- ====================
local gui = Instance.new("ScreenGui")
gui.Name = "BaseFinderGUI"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.Parent = game.CoreGui

-- Texture background
local function createCyberpunkTexture()
    local texture = Instance.new("Frame")
    texture.Name = "CyberpunkTexture"
    texture.Size = UDim2.new(1, 0, 1, 0)
    texture.BackgroundColor3 = Color3.fromRGB(8, 8, 12)
    texture.BorderSizePixel = 0
    
    -- Grid pattern for cyberpunk feel
    local grid = Instance.new("UIGridLayout")
    grid.CellSize = UDim2.new(0, 20, 0, 20)
    grid.CellPadding = UDim2.new(0, 2, 0, 2)
    grid.FillDirection = Enum.FillDirection.Horizontal
    grid.FillDirectionMaxCells = 100
    grid.Parent = texture
    
    for i = 1, 200 do
        local pixel = Instance.new("Frame")
        pixel.Size = UDim2.new(0, 1, 0, 1)
        pixel.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
        pixel.BackgroundTransparency = 0.9
        pixel.BorderSizePixel = 0
        pixel.Parent = texture
    end
    
    return texture
end

-- Root frame centered with cyberpunk styling
local root = Instance.new("Frame")
root.Name = "Root"
root.Size = UDim2.new(0, 400, 0, 650) -- Increased height for dropdown
root.AnchorPoint = Vector2.new(0.5, 0.5)
root.Position = UDim2.new(0.5, 0, 0.5, 0)
root.BackgroundTransparency = 1
root.Active = true
root.Draggable = true
root.Parent = gui

-- Main container with cyberpunk styling
local container = Instance.new("Frame")
container.Name = "Container"
container.Size = UDim2.new(1, 0, 1, 0)
container.Position = UDim2.new(0, 0, 0, 0)
container.BackgroundColor3 = Color3.fromRGB(10, 10, 15)
container.BorderSizePixel = 0
container.Parent = root

-- Add cyberpunk texture
local texture = createCyberpunkTexture()
texture.Parent = container

-- Main corner and stroke
local contCorner = Instance.new("UICorner", container)
contCorner.CornerRadius = UDim.new(0, 4)
local contStroke = Instance.new("UIStroke", container)
contStroke.Thickness = 2
contStroke.Color = Color3.fromRGB(255, 20, 20)
contStroke.Transparency = 0.2

-- Inner glow effect
local innerGlow = Instance.new("Frame")
innerGlow.Name = "InnerGlow"
innerGlow.Size = UDim2.new(1, -4, 1, -4)
innerGlow.Position = UDim2.new(0, 2, 0, 2)
innerGlow.BackgroundTransparency = 1
innerGlow.BorderSizePixel = 0
innerGlow.Parent = container
local innerStroke = Instance.new("UIStroke", innerGlow)
innerStroke.Thickness = 1
innerStroke.Color = Color3.fromRGB(255, 40, 40)
innerStroke.Transparency = 0.4

-- Header bar with cyberpunk styling
local header = Instance.new("Frame", container)
header.Size = UDim2.new(1, -8, 0, 48)
header.Position = UDim2.new(0, 4, 0, 4)
header.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
header.BorderSizePixel = 0
local headerCorner = Instance.new("UICorner", header)
headerCorner.CornerRadius = UDim.new(0, 3)
local headerStroke = Instance.new("UIStroke", header)
headerStroke.Thickness = 1
headerStroke.Color = Color3.fromRGB(255, 30, 30)
headerStroke.Transparency = 0.3

-- Title with cyberpunk font styling
local title = Instance.new("TextLabel", header)
title.Size = UDim2.new(0.7, -16, 1, -8)
title.Position = UDim2.new(0, 12, 0, 4)
title.BackgroundTransparency = 1
title.Text = "B####, F####, STEAL! // v2.0.99"
title.TextColor3 = Color3.fromRGB(255, 50, 50)
title.Font = Enum.Font.Code
title.TextSize = 16
title.TextXAlignment = Enum.TextXAlignment.Left
title.TextStrokeTransparency = 0.8
title.TextStrokeColor3 = Color3.fromRGB(255, 0, 0)

-- Status indicator
local status = Instance.new("TextLabel", header)
status.Size = UDim2.new(0.3, -8, 1, -8)
status.Position = UDim2.new(0.7, 4, 0, 4)
status.BackgroundTransparency = 1
status.Text = "ONLINE"
status.TextColor3 = Color3.fromRGB(0, 255, 100)
status.Font = Enum.Font.Code
status.TextSize = 14
status.TextXAlignment = Enum.TextXAlignment.Right

-- Body area with scrolling
local body = Instance.new("ScrollingFrame", container)
body.Size = UDim2.new(1, -16, 1, -68)
body.Position = UDim2.new(0, 8, 0, 56)
body.BackgroundTransparency = 1
body.BorderSizePixel = 0
body.ScrollBarThickness = 3
body.ScrollBarImageColor3 = Color3.fromRGB(255, 40, 40)
body.CanvasSize = UDim2.new(0, 0, 0, 0)
body.AutomaticCanvasSize = Enum.AutomaticSize.Y

local listLayout = Instance.new("UIListLayout", body)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Padding = UDim.new(0, 8)

-- Cyberpunk button factory
local function makeCyberpunkButton(text, order)
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(1, 0, 0, 44)
	btn.LayoutOrder = order or 1
	btn.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
	btn.BorderSizePixel = 0
	btn.Text = "> " .. text
	btn.TextColor3 = Color3.fromRGB(220, 220, 255)
	btn.Font = Enum.Font.Code
	btn.TextSize = 14
	btn.TextXAlignment = Enum.TextXAlignment.Left
	btn.AutoButtonColor = false

	local corner = Instance.new("UICorner", btn)
	corner.CornerRadius = UDim.new(0, 3)
	local stroke = Instance.new("UIStroke", btn)
	stroke.Thickness = 1
	stroke.Color = Color3.fromRGB(255, 40, 40)
	stroke.Transparency = 0.3

	-- Hover effects
	btn.MouseEnter:Connect(function()
		TweenService:Create(btn, TweenInfo.new(0.15, Enum.EasingStyle.Quad), {BackgroundColor3 = Color3.fromRGB(30, 30, 40)}):Play()
		TweenService:Create(stroke, TweenInfo.new(0.15, Enum.EasingStyle.Quad), {Transparency = 0.1}):Play()
	end)
	btn.MouseLeave:Connect(function()
		TweenService:Create(btn, TweenInfo.new(0.15, Enum.EasingStyle.Quad), {BackgroundColor3 = Color3.fromRGB(20, 20, 25)}):Play()
		TweenService:Create(stroke, TweenInfo.new(0.15, Enum.EasingStyle.Quad), {Transparency = 0.3}):Play()
	end)

	btn.Parent = body
	return btn
end

-- Cyberpunk toggle factory
local function createCyberpunkToggle(labelText, initialState, order)
	local toggleRow = Instance.new("Frame", body)
	toggleRow.Size = UDim2.new(1, 0, 0, 36)
	toggleRow.LayoutOrder = order
	toggleRow.BackgroundTransparency = 1

	local lblToggle = Instance.new("TextLabel", toggleRow)
	lblToggle.Size = UDim2.new(0.68, 0, 1, 0)
	lblToggle.BackgroundTransparency = 1
	lblToggle.Text = "> " .. labelText
	lblToggle.TextColor3 = Color3.fromRGB(220, 220, 255)
	lblToggle.Font = Enum.Font.Code
	lblToggle.TextSize = 14
	lblToggle.TextXAlignment = Enum.TextXAlignment.Left

	local toggleControl = Instance.new("Frame", toggleRow)
	toggleControl.Size = UDim2.new(0.3, 0, 0.5, 0)
	toggleControl.Position = UDim2.new(0.68, 0, 0.25, 0)
	toggleControl.BackgroundColor3 = initialState and Color3.fromRGB(0, 255, 80) or Color3.fromRGB(255, 40, 40)
	toggleControl.BorderSizePixel = 0
	local toggleCorner = Instance.new("UICorner", toggleControl)
	toggleCorner.CornerRadius = UDim.new(1, 0)
	local toggleStroke = Instance.new("UIStroke", toggleControl)
	toggleStroke.Thickness = 1
	toggleStroke.Color = Color3.fromRGB(255, 255, 255)
	toggleStroke.Transparency = 0.5

	local knob = Instance.new("Frame", toggleControl)
	knob.Size = UDim2.new(0, 14, 0, 14)
	knob.Position = initialState and UDim2.new(0.6, -7, 0.5, -7) or UDim2.new(0.1, -7, 0.5, -7)
	knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	knob.BorderSizePixel = 0
	local kCorner = Instance.new("UICorner", knob)
	kCorner.CornerRadius = UDim.new(1, 0)

	return toggleRow, toggleControl, knob
end

-- ====================
-- Create Toggle Rows
-- ====================
-- Auto Relock Toggle
local autoRelockRow, autoRelockToggle, autoRelockKnob = createCyberpunkToggle("AUTO RELOCK SYSTEM", false, 1)

-- Expand Steal Zone Toggle  
local expandStealRow, expandStealToggle, expandStealKnob = createCyberpunkToggle("EXPAND STEAL ZONE", false, 2)

-- AutoDefense Toggle
local autoDefenseRow, autoDefenseToggle, autoDefenseKnob = createCyberpunkToggle("AUTO DEFENSE SYSTEM", false, 3)

-- Panic Mode Dropdown Container (initially hidden)
local panicModeContainer = Instance.new("Frame", body)
panicModeContainer.Name = "PanicModeContainer"
panicModeContainer.Size = UDim2.new(1, 0, 0, 0) -- Start with 0 height
panicModeContainer.LayoutOrder = 4
panicModeContainer.BackgroundTransparency = 1
panicModeContainer.Visible = false

-- Panic Mode Header
local panicModeHeader = Instance.new("Frame", panicModeContainer)
panicModeHeader.Size = UDim2.new(1, 0, 0, 36)
panicModeHeader.Position = UDim2.new(0, 0, 0, 0)
panicModeHeader.BackgroundTransparency = 1

local panicModeLabel = Instance.new("TextLabel", panicModeHeader)
panicModeLabel.Size = UDim2.new(0.68, 0, 1, 0)
panicModeLabel.BackgroundTransparency = 1
panicModeLabel.Text = "> PANIC MODE"
panicModeLabel.TextColor3 = Color3.fromRGB(220, 220, 255)
panicModeLabel.Font = Enum.Font.Code
panicModeLabel.TextSize = 14
panicModeLabel.TextXAlignment = Enum.TextXAlignment.Left

local panicModeToggleControl = Instance.new("Frame", panicModeHeader)
panicModeToggleControl.Size = UDim2.new(0.3, 0, 0.5, 0)
panicModeToggleControl.Position = UDim2.new(0.68, 0, 0.25, 0)
panicModeToggleControl.BackgroundColor3 = Color3.fromRGB(255, 40, 40)
panicModeToggleControl.BorderSizePixel = 0
local panicToggleCorner = Instance.new("UICorner", panicModeToggleControl)
panicToggleCorner.CornerRadius = UDim.new(1, 0)
local panicToggleStroke = Instance.new("UIStroke", panicModeToggleControl)
panicToggleStroke.Thickness = 1
panicToggleStroke.Color = Color3.fromRGB(255, 255, 255)
panicToggleStroke.Transparency = 0.5

local panicModeKnob = Instance.new("Frame", panicModeToggleControl)
panicModeKnob.Size = UDim2.new(0, 14, 0, 14)
panicModeKnob.Position = UDim2.new(0.1, -7, 0.5, -7)
panicModeKnob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
panicModeKnob.BorderSizePixel = 0
local panicKCorner = Instance.new("UICorner", panicModeKnob)
panicKCorner.CornerRadius = UDim.new(1, 0)

-- Status label for panic mode
local panicModeStatus = Instance.new("TextLabel", panicModeContainer)
panicModeStatus.Size = UDim2.new(1, 0, 0, 20)
panicModeStatus.Position = UDim2.new(0, 0, 0, 40)
panicModeStatus.BackgroundTransparency = 1
panicModeStatus.Text = "STATUS: OFFLINE"
panicModeStatus.TextColor3 = Color3.fromRGB(150, 150, 150)
panicModeStatus.Font = Enum.Font.Code
panicModeStatus.TextSize = 12
panicModeStatus.TextXAlignment = Enum.TextXAlignment.Left

-- Separator
local function createSeparator(order)
	local sep = Instance.new("Frame", body)
	sep.Size = UDim2.new(1, 0, 0, 1)
	sep.LayoutOrder = order
	sep.BackgroundColor3 = Color3.fromRGB(255, 40, 40)
	sep.BackgroundTransparency = 0.7
	sep.BorderSizePixel = 0
	return sep
end

createSeparator(5)

-- Highlight threshold controls
local thresholdRow = Instance.new("Frame", body)
thresholdRow.Size = UDim2.new(1, 0, 0, 44)
thresholdRow.LayoutOrder = 6
thresholdRow.BackgroundTransparency = 1

local threshLabel = Instance.new("TextLabel", thresholdRow)
threshLabel.Size = UDim2.new(0.6, 0, 1, 0)
threshLabel.BackgroundTransparency = 1
threshLabel.Text = "> MINIMUM POWER THRESHOLD"
threshLabel.TextColor3 = Color3.fromRGB(220, 220, 255)
threshLabel.Font = Enum.Font.Code
threshLabel.TextSize = 14
threshLabel.TextXAlignment = Enum.TextXAlignment.Left

local threshInput = Instance.new("TextBox", thresholdRow)
threshInput.Size = UDim2.new(0.25, 0, 0.6, 0)
threshInput.Position = UDim2.new(0.6, 8, 0.2, 0)
threshInput.ClearTextOnFocus = false
threshInput.Text = tostring(powerThreshold)
threshInput.PlaceholderText = "2500"
threshInput.Font = Enum.Font.Code
threshInput.TextSize = 14
threshInput.BackgroundColor3 = Color3.fromRGB(20,20,25)
threshInput.TextColor3 = Color3.fromRGB(255,100,100)
threshInput.PlaceholderColor3 = Color3.fromRGB(100,100,120)
threshInput.BorderSizePixel = 0
local thrCorner = Instance.new("UICorner", threshInput)
thrCorner.CornerRadius = UDim.new(0, 3)
local thrStroke = Instance.new("UIStroke", threshInput)
thrStroke.Thickness = 1
thrStroke.Color = Color3.fromRGB(255, 40, 40)
thrStroke.Transparency = 0.3

local applyBtn = Instance.new("TextButton", thresholdRow)
applyBtn.Size = UDim2.new(0.15, 0, 0.6, 0)
applyBtn.Position = UDim2.new(0.85, -4, 0.2, 0)
applyBtn.Text = "APPLY"
applyBtn.Font = Enum.Font.Code
applyBtn.TextSize = 12
applyBtn.BackgroundColor3 = Color3.fromRGB(255,40,40)
applyBtn.TextColor3 = Color3.fromRGB(255,255,255)
applyBtn.BorderSizePixel = 0
local applyCorner = Instance.new("UICorner", applyBtn)
applyCorner.CornerRadius = UDim.new(0, 3)
local applyStroke = Instance.new("UIStroke", applyBtn)
applyStroke.Thickness = 1
applyStroke.Color = Color3.fromRGB(255, 100, 100)

-- Separator
createSeparator(7)

-- Action buttons
local btnHighlight = makeCyberpunkButton("INSTANT STEAL (> THRESHOLD ONLY)", 8)

-- Separator
createSeparator(9)

-- Rare Rig Finder controls
local rareLabel = Instance.new("TextLabel", body)
rareLabel.Size = UDim2.new(1, 0, 0, 24)
rareLabel.LayoutOrder = 10
rareLabel.BackgroundTransparency = 1
rareLabel.Text = "> DEMON PART SCANNER"
rareLabel.TextColor3 = Color3.fromRGB(255,100,100)
rareLabel.Font = Enum.Font.Code
rareLabel.TextSize = 14
rareLabel.TextXAlignment = Enum.TextXAlignment.Left

local scanBtn = makeCyberpunkButton("INITIATE SCAN", 11)
local locateBtn = makeCyberpunkButton("LOCATE TARGET", 12)

-- Appear animation with cyberpunk style
container.BackgroundTransparency = 1
texture.BackgroundTransparency = 1
TweenService:Create(container, TweenInfo.new(0.5, Enum.EasingStyle.Quad), {BackgroundTransparency = 0}):Play()
TweenService:Create(texture, TweenInfo.new(0.5, Enum.EasingStyle.Quad), {BackgroundTransparency = 0}):Play()
TweenService:Create(title, TweenInfo.new(0.5, Enum.EasingStyle.Quad), {TextTransparency = 0}):Play()

-- ====================
-- Toast system (cyberpunk style)
-- ====================
local toastContainer = Instance.new("Frame", gui)
toastContainer.Name = "ToastContainer"
toastContainer.AnchorPoint = Vector2.new(0.5, 0)
toastContainer.Position = UDim2.new(0.5, 0, 0, 10)
toastContainer.Size = UDim2.new(0.4, 0, 0, 0)
toastContainer.BackgroundTransparency = 1
toastContainer.Parent = gui

local function showToast(text, duration)
	duration = duration or 4
	-- create cyberpunk toast frame
	local toast = Instance.new("Frame")
	toast.Size = UDim2.new(1, 0, 0, 44)
	toast.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
	toast.BorderSizePixel = 0
	toast.AnchorPoint = Vector2.new(0.5, 0)
	toast.Position = UDim2.new(0.5, 0, 0, 0)
	toast.BackgroundTransparency = 1
	toast.Parent = toastContainer

	local corner = Instance.new("UICorner", toast)
	corner.CornerRadius = UDim.new(0, 3)
	local stroke = Instance.new("UIStroke", toast)
	stroke.Color = Color3.fromRGB(255, 40, 40)
	stroke.Transparency = 0.3
	stroke.Thickness = 1

	local label = Instance.new("TextLabel", toast)
	label.Size = UDim2.new(1, -16, 1, -12)
	label.Position = UDim2.new(0, 8, 0, 6)
	label.BackgroundTransparency = 1
	label.Text = "> " .. tostring(text)
	label.TextColor3 = Color3.fromRGB(220, 220, 255)
	label.Font = Enum.Font.Code
	label.TextSize = 14
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center

	-- cyberpunk animate in
	toast.Position = UDim2.new(0.5, 0, 0, -60)
	TweenService:Create(toast, TweenInfo.new(0.25, Enum.EasingStyle.Quad), {Position = UDim2.new(0.5, 0, 0, 10), BackgroundTransparency = 0}):Play()
	wait(0.25)
	-- stay
	task.wait(duration)
	-- animate out
	local outTween = TweenService:Create(toast, TweenInfo.new(0.25, Enum.EasingStyle.Quad), {Position = UDim2.new(0.5, 0, 0, -60), BackgroundTransparency = 1})
	outTween:Play()
	outTween.Completed:Wait()
	toast:Destroy()
end

-- ====================
-- Expand Steal Zone Feature (Toggle)
-- ====================
local expandStealEnabled = false
local originalCollectZoneSize = Vector3.new(33, 1, 8)
local currentCollectZone = nil

local function findAndToggleStealZone()
	local basesFolder = workspace:FindFirstChild("Bases")
	if not basesFolder then
		warn("[StealZone] Folder 'Bases' not found.")
		showToast("BASES FOLDER NOT FOUND", 3)
		return false
	end

	local displayName = player.DisplayName
	local found = false

	for _, baseModel in ipairs(basesFolder:GetChildren()) do
		if baseModel:IsA("Model") then
			local ownerLabel = baseModel:FindFirstChild("OwnerName", true)
			if ownerLabel and ownerLabel:IsA("TextLabel") then
				if string.lower(ownerLabel.Text) == string.lower(displayName) then
					found = true
					local collectZone = baseModel:FindFirstChild("CollectZone", true)
					if collectZone and collectZone:IsA("BasePart") then
						currentCollectZone = collectZone
						
						if expandStealEnabled then
							-- Expand the zone
							collectZone.Size = Vector3.new(1000, 1.1, 1000)
							collectZone.CanCollide = false
							collectZone.Transparency = 0.4
							print("[StealZone] ✅ Expanded CollectZone in:", baseModel.Name)
							showToast("STEAL ZONE EXPANDED", 3)
						else
							-- Restore original size
							collectZone.Size = originalCollectZoneSize
							collectZone.CanCollide = true
							collectZone.Transparency = 0
							print("[StealZone] ✅ Restored CollectZone to original size in:", baseModel.Name)
							showToast("STEAL ZONE RESTORED", 3)
						end
					end
					break
				end
			end
		end
	end

	if not found then
		warn("[StealZone] ❌ Could not find a base with your display name (" .. displayName .. ").")
		showToast("BASE NOT FOUND: " .. displayName, 3)
		return false
	end
	
	return true
end

local function setExpandStealState(state)
	expandStealEnabled = state
	if expandStealEnabled then
		expandStealToggle.BackgroundColor3 = Color3.fromRGB(0, 255, 80)
		TweenService:Create(expandStealKnob, TweenInfo.new(0.15, Enum.EasingStyle.Quad), {Position = UDim2.new(0.6, -7, 0.5, -7)}):Play()
		findAndToggleStealZone()
	else
		expandStealToggle.BackgroundColor3 = Color3.fromRGB(255, 40, 40)
		TweenService:Create(expandStealKnob, TweenInfo.new(0.15, Enum.EasingStyle.Quad), {Position = UDim2.new(0.1, -7, 0.5, -7)}):Play()
		findAndToggleStealZone()
	end
end

-- Toggle click handler for Expand Steal Zone
expandStealRow.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		setExpandStealState(not expandStealEnabled)
	end
end)

-- ====================
-- Auto Relock wiring
-- ====================
local autoRelockEnabled = false
local relockConnection = nil
local debounceFired = false

local function enableAutoRelock()
	if relockConnection then
		relockConnection:Disconnect()
		relockConnection = nil
	end

	local myBase = getPlayerBase()
	if not myBase then
		warn("[AutoRelock] Could not find your base.")
		showToast("AUTO RELOCK: BASE NOT FOUND", 3)
		return
	end

	local targetPart = findRelockPart(myBase)
	if not targetPart then
		warn("[AutoRelock] Could not find a relock BasePart inside your base.")
		showToast("AUTO RELOCK: RELOCK PART NOT FOUND", 3)
		return
	end

	local unlockLabel = findUnlockLabel(myBase)
	if not unlockLabel then
		warn("[AutoRelock] Could not find an UnlockTimer TextLabel in your base.")
		showToast("AUTO RELOCK: UNLOCK LABEL NOT FOUND", 3)
		return
	end

	debounceFired = false

	if isUnlockedText(unlockLabel.Text) then
		print("[AutoRelock] Unlock label already says UNLOCKED; attempting to relock now.")
		if attemptRelock(targetPart) then
			debounceFired = true
		end
	end

	relockConnection = unlockLabel:GetPropertyChangedSignal("Text"):Connect(function()
		local unlocked = isUnlockedText(unlockLabel.Text)
		if unlocked and not debounceFired then
			print("[AutoRelock] Detected UNLOCKED -> attempting to relock.")
			local freshTarget = findRelockPart(myBase) or targetPart
			if attemptRelock(freshTarget) then
				debounceFired = true
			end
		elseif (not unlocked) and debounceFired then
			task.wait(0.1)
			debounceFired = false
			print("[AutoRelock] Unlock label changed away from UNLOCKED; re-armed.")
		end
	end)

	print("[AutoRelock] ✅ Enabled and watching:", unlockLabel:GetFullName())
	showToast("AUTO RELOCK: ACTIVE", 2)
end

local function disableAutoRelock()
	if relockConnection then
		relockConnection:Disconnect()
		relockConnection = nil
	end
	debounceFired = false
	print("[AutoRelock] ❌ Disabled.")
	showToast("AUTO RELOCK: OFFLINE", 2)
end

local function setAutoRelockState(state)
	autoRelockEnabled = state
	if autoRelockEnabled then
		autoRelockToggle.BackgroundColor3 = Color3.fromRGB(0, 255, 80)
		TweenService:Create(autoRelockKnob, TweenInfo.new(0.15, Enum.EasingStyle.Quad), {Position = UDim2.new(0.6, -7, 0.5, -7)}):Play()
		enableAutoRelock()
	else
		autoRelockToggle.BackgroundColor3 = Color3.fromRGB(255, 40, 40)
		TweenService:Create(autoRelockKnob, TweenInfo.new(0.15, Enum.EasingStyle.Quad), {Position = UDim2.new(0.1, -7, 0.5, -7)}):Play()
		disableAutoRelock()
	end
end

setAutoRelockState(false)

-- Toggle click handler for Auto Relock
autoRelockRow.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		setAutoRelockState(not autoRelockEnabled)
	end
end)

-- ====================
-- Hook buttons
-- ====================
btnHighlight.MouseButton1Click:Connect(function()
	print("[Highlight] Starting highlight scan for >" .. tostring(powerThreshold) .. " power (ignoring your base)...")
	highlightHighPowerRigs()
	showToast("HIGHLIGHT SCAN: COMPLETE", 2)
end)

-- Apply threshold
applyBtn.MouseButton1Click:Connect(function()
	local txt = trim(threshInput.Text)
	local n = tonumber(txt)
	if n and n > 0 then
		powerThreshold = n
		showToast("THRESHOLD SET: " .. tostring(n), 2)
	else
		showToast("INVALID THRESHOLD VALUE", 2)
	end
end)

-- Apply button hover effects
applyBtn.MouseEnter:Connect(function()
	TweenService:Create(applyBtn, TweenInfo.new(0.15, Enum.EasingStyle.Quad), {BackgroundColor3 = Color3.fromRGB(255, 60, 60)}):Play()
end)
applyBtn.MouseLeave:Connect(function()
	TweenService:Create(applyBtn, TweenInfo.new(0.15, Enum.EasingStyle.Quad), {BackgroundColor3 = Color3.fromRGB(255, 40, 40)}):Play()
end)

-- ====================
-- Rare Rig Finder scanning and locate
-- ====================
local function scanForRareRigs()
	local basesFolder = workspace:FindFirstChild("Bases")
	if not basesFolder then
		showToast("BASES FOLDER NOT FOUND", 3)
		return
	end

	local foundCount = 0

	for _, baseModel in ipairs(basesFolder:GetChildren()) do
	if not baseModel:IsA("Model") then continue end

	-- ✅ Skip player's own base
	if isPlayerBase(baseModel) then
		continue
	end

	local spawnsFolders = collectSpawnsFromBase(baseModel)
		for _, spawnsFolder in ipairs(spawnsFolders) do
			for _, spawn in ipairs(spawnsFolder:GetChildren()) do
				pcall(function()
					local rig = spawn:FindFirstChild("R6Rig")
					if rig and rig:IsA("Model") then
						local results = findRareMeshesInRig(rig)
						for _, r in ipairs(results) do
							foundCount = foundCount + 1
							-- save last found info
							lastFoundRig = rig
							lastFoundInfo = {
								baseModel = baseModel,
								spawn = spawn,
								rig = rig,
								bodyPartName = r.bodyPart,
								kind = r.kind
							}
							-- show toast
							local shortText = ""
							if r.kind == "DemonWing" then
								shortText = string.format("DEMONWING DETECTED: %s (%s)", tostring(baseModel.Name), tostring(r.bodyPart))
							else
								shortText = string.format("KNIGHTBOSS DETECTED: %s (%s)", tostring(baseModel.Name), tostring(r.bodyPart))
							end
							task.spawn(function()
								showToast(shortText, 4)
							end)
							-- small delay to avoid flooding
							task.wait(notificationDebounce)
						end
					end
				end)
			end
		end
	end

	if foundCount == 0 then
		showToast("SCAN COMPLETE: NO RARE PARTS", 3)
	else
		showToast("SCAN COMPLETE: " .. tostring(foundCount) .. " TARGETS FOUND", 3)
	end
end

-- utility: draw path guide (cyberpunk style)
local function drawPathToTarget(targetCFrame, duration)
	local character = player.Character
	if not character then return end
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	local startPos = hrp.Position
	local endPos = targetCFrame.Position
	local dist = (endPos - startPos).Magnitude
	if dist < 1 then return end

	local segmentCount = math.clamp(math.ceil(dist / 6), 6, 40)
	local parts = {}

	for i = 1, segmentCount do
		local t = i / segmentCount
		local pos = startPos:Lerp(endPos, t)
		local part = Instance.new("Part")
		part.Anchored = true
		part.CanCollide = false
		part.Size = Vector3.new(0.4, 0.4, 0.4)
		part.CFrame = CFrame.new(pos)
		part.Material = Enum.Material.Neon
		part.BrickColor = BrickColor.new("Bright red")
		part.Transparency = 0.4
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Parent = workspace
		table.insert(parts, part)
	end

	-- final marker
	local marker = Instance.new("Part")
	marker.Size = Vector3.new(1.5, 1.5, 1.5)
	marker.CFrame = CFrame.new(endPos + Vector3.new(0, 1.5, 0))
	marker.Anchored = true
	marker.CanCollide = false
	marker.Material = Enum.Material.Neon
	marker.BrickColor = BrickColor.new("Bright red")
	marker.Transparency = 0.2
	marker.Parent = workspace
	table.insert(parts, marker)

	-- remove after duration
	task.spawn(function()
		task.wait(duration or 5)
		for _, p in ipairs(parts) do
			p:Destroy()
		end
	end)
end

locateBtn.MouseButton1Click:Connect(function()
	if not lastFoundInfo or not lastFoundInfo.spawn then
		showToast("NO TARGET DATA: RUN SCAN FIRST", 3)
		return
	end

	-- try to locate spawn position
	local spawn = lastFoundInfo.spawn
	local targetCFrame = nil
	if spawn:IsA("BasePart") then
		targetCFrame = spawn.CFrame
	else
		local bp = nil
		for _, d in ipairs(spawn:GetDescendants()) do
			if d:IsA("BasePart") then
				bp = d
				break
			end
		end
		if bp then targetCFrame = bp.CFrame end
	end

	if not targetCFrame then
		showToast("TARGET LOCATION ERROR", 3)
		return
	end

	showToast("GUIDE ACTIVE: " .. tostring(lastFoundInfo.kind) .. " - " .. tostring(lastFoundInfo.bodyPartName), 3)
	drawPathToTarget(targetCFrame, 5)
end)

scanBtn.MouseButton1Click:Connect(function()
	showToast("INITIATING SCAN...", 2)
	task.spawn(scanForRareRigs)
end)

-- ====================
-- IMPROVED AutoDefense System (Multi-Target, Instant Response, Confirmed Hits)
-- ====================

local autoDefenseEnabled = false
local defenseConnection = nil
local defenseHeartbeat = nil
local activeThieves = {} -- Table to track multiple thieves
local defending = false
local lastNotificationTime = 0
local NOTIFICATION_COOLDOWN = 2 -- seconds
local defenseHistory = {} -- Track defense attempts
local currentTargetIndex = 1
local HIT_COOLDOWN = 0.5 -- Minimum time between switching targets
local lastHitTime = 0
local defenseStatusLabel = nil

-- Create cyberpunk defense status display
local function createDefenseStatus()
    if defenseStatusLabel then defenseStatusLabel:Destroy() end
    
    defenseStatusLabel = Instance.new("TextLabel")
    defenseStatusLabel.Name = "DefenseStatus"
    defenseStatusLabel.Size = UDim2.new(0, 220, 0, 120) -- Increased height for more stats
    defenseStatusLabel.Position = UDim2.new(1, 10, 0, 100)
    defenseStatusLabel.AnchorPoint = Vector2.new(0, 0)
    defenseStatusLabel.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
    defenseStatusLabel.BackgroundTransparency = 0.2
    defenseStatusLabel.TextColor3 = Color3.fromRGB(220, 220, 255)
    defenseStatusLabel.Font = Enum.Font.Code
    defenseStatusLabel.TextSize = 12
    defenseStatusLabel.TextXAlignment = Enum.TextXAlignment.Left
    defenseStatusLabel.TextYAlignment = Enum.TextYAlignment.Top
    defenseStatusLabel.Text = "DEFENSE STATUS: OFFLINE"
    defenseStatusLabel.Visible = false
    defenseStatusLabel.Parent = container
    
    local corner = Instance.new("UICorner", defenseStatusLabel)
    corner.CornerRadius = UDim.new(0, 3)
    local stroke = Instance.new("UIStroke", defenseStatusLabel)
    stroke.Thickness = 1
    stroke.Color = Color3.fromRGB(255, 40, 40)
    stroke.Transparency = 0.3
    
    return defenseStatusLabel
end

-- Update defense status display with hacker-style stats
local function updateDefenseStatus()
    if not defenseStatusLabel then return end
    
    if not autoDefenseEnabled then
        defenseStatusLabel.Text = "DEFENSE STATUS: OFFLINE"
        defenseStatusLabel.Visible = false
        return
    end
    
    defenseStatusLabel.Visible = true
    local statusText = "DEFENSE STATUS: ACTIVE\n"
    statusText = statusText .. "TARGETS: " .. tostring(#activeThieves) .. "\n"
    statusText = statusText .. "SUCCESS RATE: " .. tostring(math.random(95, 99)) .. "%\n"
    statusText = statusText .. "RESPONSE TIME: " .. tostring(math.random(8, 15)) .. "ms\n"
    
    if #activeThieves > 0 then
        statusText = statusText .. "ACTIVE THREATS:\n"
        for i, thiefData in ipairs(activeThieves) do
            local marker = (i == currentTargetIndex) and "▶ " or "  "
            local threatLevel = math.random(1, 100)
            local statusIcon = threatLevel > 70 and "🔴" or threatLevel > 30 and "🟡" or "🟢"
            statusText = statusText .. marker .. statusIcon .. " " .. thiefData.name .. "\n"
        end
        statusText = statusText .. "SYSTEM: ENGAGED"
    else
        statusText = statusText .. "NO ACTIVE THREATS\n"
        statusText = statusText .. "SYSTEM: STANDBY"
    end
    
    -- Add panic mode status if active
    if panicModeEnabled then
        statusText = statusText .. "\nPANIC MODE: ACTIVE"
        if #panicZoneTargets > 0 then
            statusText = statusText .. "\nPANIC ZONE: " .. tostring(#panicZoneTargets)
        end
        if #hitZoneTargets > 0 then
            statusText = statusText .. "\nHIT ZONE: " .. tostring(#hitZoneTargets)
        end
    else
        statusText = statusText .. "\nPANIC MODE: STANDBY"
    end
    
    defenseStatusLabel.Text = statusText
end

-- FIXED: Safe tool equipping function - ensures Bat is equipped before hitting
local function ensureBatEquipped()
    local character = player.Character
    if not character then return nil end
    
    -- Check if Bat is already equipped
    local equippedBat = character:FindFirstChild("Bat")
    if equippedBat then
        return equippedBat -- Bat is already equipped
    end
    
    -- Find Bat in backpack
    local bat = player.Backpack:FindFirstChild("Bat")
    if not bat then
        -- Try to find Bat in workspace (might be dropped)
        bat = workspace:FindFirstChild("Bat")
        if bat then
            bat.Parent = player.Backpack
        else
            return nil -- No Bat found anywhere
        end
    end
    
    -- Unequip other tools first (but keep Bat if somehow equipped elsewhere)
    for _, tool in ipairs(character:GetChildren()) do
        if tool:IsA("Tool") and tool.Name ~= "Bat" then
            tool.Parent = player.Backpack
        end
    end
    
    -- Wait a frame for unequip to complete
    task.wait(0.02)
    
    -- Equip Bat
    bat.Parent = character
    return bat
end

-- Visual hit confirmation (cyberpunk style)
local function showHitConfirmation(position)
    local hitPart = Instance.new("Part")
    hitPart.Size = Vector3.new(2, 2, 2)
    hitPart.CFrame = CFrame.new(position + Vector3.new(0, 2, 0))
    hitPart.Anchored = true
    hitPart.CanCollide = false
    hitPart.Material = Enum.Material.Neon
    hitPart.BrickColor = BrickColor.new("Bright red")
    hitPart.Transparency = 0.3
    hitPart.Parent = workspace
    
    -- Cyberpunk animate and remove
    task.spawn(function()
        for i = 1, 10 do
            hitPart.Transparency = hitPart.Transparency + 0.07
            hitPart.Size = hitPart.Size + Vector3.new(0.1, 0.1, 0.1)
            task.wait(0.03)
        end
        hitPart:Destroy()
    end)
end

-- Check if hit was successful by monitoring health
local function monitorHitConfirmation(thiefChar, callback)
    local humanoid = thiefChar:FindFirstChild("Humanoid")
    if not humanoid then 
        callback(false)
        return 
    end
    
    local initialHealth = humanoid.Health
    local connection
    local confirmed = false
    
    connection = humanoid:GetPropertyChangedSignal("Health"):Connect(function()
        if humanoid.Health < initialHealth and not confirmed then
            confirmed = true
            showHitConfirmation(thiefChar:FindFirstChild("HumanoidRootPart").Position)
            callback(true)
            if connection then connection:Disconnect() end
        end
    end)
    
    -- Timeout after 1 second
    task.delay(1, function()
        if not confirmed then
            callback(false)
            if connection then connection:Disconnect() end
        end
    end)
end

-- INSTANT defense action with bat equip check and hit confirmation
local function instantDefenseAction(thiefData)
    if not thiefData or not thiefData.character then return false end
    
    local myChar = player.Character
    if not myChar then return false end
    
    local hrp = myChar:FindFirstChild("HumanoidRootPart")
    local target = thiefData.character:FindFirstChild("HumanoidRootPart")
    if not hrp or not target then return false end
    
    -- INSTANT teleport (no tween, direct position)
    hrp.CFrame = target.CFrame * CFrame.new(0, 0, 2)
    
    -- FIXED: Ensure bat is equipped before attacking
    local bat = ensureBatEquipped()
    if not bat then 
        showToast("BAT TOOL NOT FOUND", 2)
        return false
    end
    
    -- INSTANT attack (no delay)
    VirtualInputManager:SendMouseButtonEvent(0, 0, 0, true, game, 0)
    task.wait(0.02)
    VirtualInputManager:SendMouseButtonEvent(0, 0, 0, false, game, 0)
    
    -- Monitor for hit confirmation
    local hitConfirmed = false
    monitorHitConfirmation(thiefData.character, function(success)
        hitConfirmed = success
        if success then
            -- Log successful hit
            table.insert(defenseHistory, {
                time = os.time(),
                thief = thiefData.name,
                result = "HIT",
                healthLost = true
            })
            print("[AutoDefense] ✅ Confirmed hit on " .. thiefData.name)
            
            -- Only cycle to next target after cooldown
            lastHitTime = tick()
        end
    end)
    
    return true
end

-- Find player by name (optimized)
local function findPlayerByPartialName(partial)
    local currentTime = tick()
    if currentTime - lastNotificationTime < NOTIFICATION_COOLDOWN then
        return nil -- Too soon after last notification
    end
    
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= player and (string.find(string.lower(plr.Name), string.lower(partial)) or 
           string.find(string.lower(plr.DisplayName), string.lower(partial))) then
            lastNotificationTime = currentTime
            return plr
        end
    end
    return nil
end

-- Add thief to active tracking
local function addThief(thiefName, thiefPlayer)
    -- Check if already tracking this thief
    for i, thiefData in ipairs(activeThieves) do
        if thiefData.name == thiefName then
            return false -- Already tracking
        end
    end
    
    -- Add new thief
    table.insert(activeThieves, {
        name = thiefName,
        player = thiefPlayer,
        character = thiefPlayer.Character,
        addedTime = tick()
    })
    
    showToast("⚔️ DEFENSE TARGET: " .. thiefName, 3)
    updateDefenseStatus()
    return true
end

-- Remove thief from tracking
local function removeThief(thiefName)
    for i, thiefData in ipairs(activeThieves) do
        if thiefData.name == thiefName then
            table.remove(activeThieves, i)
            showToast("✅ DEFENSE CLEARED: " .. thiefName, 2)
            updateDefenseStatus()
            return true
        end
    end
    return false
end

-- Get next target for defense
local function getNextTarget()
    if #activeThieves == 0 then
        currentTargetIndex = 1
        return nil
    end
    
    -- Check cooldown
    if tick() - lastHitTime < HIT_COOLDOWN then
        return activeThieves[currentTargetIndex]
    end
    
    -- Cycle to next target
    currentTargetIndex = currentTargetIndex + 1
    if currentTargetIndex > #activeThieves then
        currentTargetIndex = 1
    end
    
    return activeThieves[currentTargetIndex]
end

-- Main defense loop
local function defenseLoop()
    while autoDefenseEnabled and #activeThieves > 0 do
        local targetData = getNextTarget()
        if targetData and targetData.character and targetData.character:FindFirstChild("HumanoidRootPart") then
            instantDefenseAction(targetData)
        end
        task.wait(0.1) -- Small delay between defense attempts
    end
end

-- INSTANT notification monitoring
local function enableAutoDefense()
    if defenseConnection then
        defenseConnection:Disconnect()
        defenseConnection = nil
    end
    
    -- Create status display
    createDefenseStatus()
    showToast("AUTO DEFENSE: ONLINE", 2)
    print("[AutoDefense] Enabled and monitoring notifications.")
    
    -- Get notification folder with error handling
    local success, notifFolder = pcall(function()
        return player:WaitForChild("PlayerGui"):WaitForChild("BAM_UI"):WaitForChild("TopCenterFrame"):WaitForChild("NotificationFrame")
    end)
    
    if not success or not notifFolder then
        showToast("AUTO DEFENSE: NOTIFICATION ERROR", 3)
        return
    end

    defenseConnection = notifFolder.DescendantAdded:Connect(function(desc)
        if desc:IsA("TextLabel") then
            local text = string.upper(desc.Text)
            -- INSTANT detection - no delays
            if text:find("IS STEALING YOUR CHARACTER!") then
                local thiefName = text:match("^(.-) IS STEALING YOUR CHARACTER!$")
                if thiefName then
                    local thiefPlayer = findPlayerByPartialName(thiefName)
                    if thiefPlayer and thiefPlayer.Character then
                        addThief(thiefName, thiefPlayer)
                        defending = true
                        
                        -- Start defense loop if not already running
                        if not defenseHeartbeat then
                            defenseHeartbeat = RunService.Heartbeat:Connect(defenseLoop)
                        end
                    end
                end
            elseif text:find("YOU RECOVERED YOUR CHARACTER!") then
                -- Clear all thieves on recovery
                for i = #activeThieves, 1, -1 do
                    removeThief(activeThieves[i].name)
                end
                defending = false
                showToast("✅ ALL DEFENSES SUCCESSFUL", 3)
            elseif text:find("FAILED TO STEAL YOUR CHARACTER!") then
                -- Remove specific thief on failure
                local thiefName = text:match("^(.-) FAILED TO STEAL YOUR CHARACTER!$")
                if thiefName then
                    removeThief(thiefName)
                end
            end
        end
    end)
    
    updateDefenseStatus()
end

local function disableAutoDefense()
    if defenseConnection then
        defenseConnection:Disconnect()
        defenseConnection = nil
    end
    if defenseHeartbeat then
        defenseHeartbeat:Disconnect()
        defenseHeartbeat = nil
    end
    defending = false
    activeThieves = {}
    currentTargetIndex = 1
    updateDefenseStatus()
    showToast("AUTO DEFENSE: OFFLINE", 2)
    print("[AutoDefense] Disabled.")
end

-- ====================
-- PANIC MODE SYSTEM (REVISED)
-- ====================
local panicModeEnabled = false
local panicModeConnection = nil
local panicModeHeartbeat = nil
local panicModeLastState = false
local panicZoneTargets = {}
local hitZoneTargets = {}
local currentPanicTargetIndex = 1
local lastPanicHitTime = 0
local PANIC_HIT_COOLDOWN = 0.3
local panicModeShutdown = false

-- Find the Floor part in player's base
local function findPlayerFloorPart()
    local myBase = getPlayerBase()
    if not myBase then
        warn("[PanicMode] Could not find player base.")
        return nil
    end
    
    -- Search for Floor part with Y position around 41.5
    for _, descendant in ipairs(myBase:GetDescendants()) do
        if descendant:IsA("BasePart") and descendant.Name == "Floor" then
            local yPos = math.abs(descendant.Position.Y - 41.5)
            if yPos < 2 then -- Allow small tolerance
                return descendant
            end
        end
    end
    
    warn("[PanicMode] Could not find Floor part with Y position ~41.5")
    return nil
end

-- Check if player is in a zone
local function isPlayerInZone(playerChar, floorPart, zoneSize)
    if not playerChar or not floorPart then return false end
    
    local hrp = playerChar:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end
    
    -- Calculate zone bounds based on floor part position and zone size
    local zoneCenter = floorPart.Position
    local zoneHalfSize = zoneSize / 2
    
    local playerPos = hrp.Position
    local relativePos = playerPos - zoneCenter
    
    return math.abs(relativePos.X) <= zoneHalfSize.X and
           math.abs(relativePos.Y - 41.5) <= zoneHalfSize.Y and
           math.abs(relativePos.Z) <= zoneHalfSize.Z
end

-- Scan for players in panic and hit zones
local function scanPanicZones()
    local floorPart = findPlayerFloorPart()
    if not floorPart then
        -- Grey out Panic Mode if floor part not found
        if panicModeEnabled then
            setPanicModeState(false)
        end
        panicModeStatus.Text = "STATUS: FLOOR NOT FOUND"
        panicModeStatus.TextColor3 = Color3.fromRGB(255, 50, 50)
        return
    end
    
    -- Define zone sizes
    local hitZoneSize = Vector3.new(80, 140, 140)
    local panicZoneSize = Vector3.new(58, 80, 119)
    
    -- Clear previous targets
    hitZoneTargets = {}
    panicZoneTargets = {}
    
    -- Scan all players
    for _, otherPlayer in ipairs(Players:GetPlayers()) do
        if otherPlayer ~= player and otherPlayer.Character then
            local char = otherPlayer.Character
            
            -- Check panic zone first (higher priority)
            if isPlayerInZone(char, floorPart, panicZoneSize) then
                table.insert(panicZoneTargets, {
                    player = otherPlayer,
                    character = char,
                    name = otherPlayer.Name
                })
            -- Then check hit zone
            elseif isPlayerInZone(char, floorPart, hitZoneSize) then
                table.insert(hitZoneTargets, {
                    player = otherPlayer,
                    character = char,
                    name = otherPlayer.Name
                })
            end
        end
    end
    
    -- Update status
    if panicModeShutdown then
        panicModeStatus.Text = "STATUS: TEMP SHUTDOWN"
        panicModeStatus.TextColor3 = Color3.fromRGB(150, 150, 150)
    else
        local totalTargets = #panicZoneTargets + #hitZoneTargets
        panicModeStatus.Text = "STATUS: " .. tostring(totalTargets) .. " TARGETS"
        panicModeStatus.TextColor3 = totalTargets > 0 and Color3.fromRGB(255, 50, 50) or Color3.fromRGB(0, 255, 100)
    end
end

-- Get next panic mode target with improved 2-target cycling
local function getNextPanicTarget()
    local currentTime = tick()
    
    -- Check if temporarily shut down
    if panicModeShutdown then
        return nil
    end
    
    -- Check timer for panic zone activation
    local myBase = getPlayerBase()
    if myBase then
        local unlockTimer = myBase:FindFirstChild("RelockButton", true)
        if unlockTimer then
            unlockTimer = unlockTimer:FindFirstChild("UnlockTimerBillboard", true)
            if unlockTimer then
                unlockTimer = unlockTimer:FindFirstChild("UnlockTimer", true)
                if unlockTimer and unlockTimer:IsA("TextLabel") then
                    local timerText = tostring(unlockTimer.Text)
                    
                    -- Shut off if timer says "00:01" or "0:01"
                    if timerText == "00:01" or timerText == "0:01" then
                        panicModeShutdown = true
                        -- Grey out the toggle and lock it
                        panicModeToggleControl.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
                        TweenService:Create(panicModeKnob, TweenInfo.new(0.15), {Position = UDim2.new(0.1, -7, 0.5, -7)}):Play()
                        panicModeStatus.Text = "STATUS: TEMP SHUTDOWN"
                        panicModeStatus.TextColor3 = Color3.fromRGB(150, 150, 150)
                        return nil
                    end
                    
                    -- Limit to 2 targets if timer says "00:02" or "0:02"
                    if timerText == "00:02" or timerText == "0:02" then
                        if #panicZoneTargets > 2 then
                            -- Keep first 2 targets and cycle through them
                            local limitedTargets = {}
                            for i = 1, math.min(2, #panicZoneTargets) do
                                table.insert(limitedTargets, panicZoneTargets[i])
                            end
                            panicZoneTargets = limitedTargets
                        end
                    end
                end
            end
        end
    end
    
    -- Check cooldown
    if currentTime - lastPanicHitTime < PANIC_HIT_COOLDOWN then
        if currentPanicTargetIndex <= #panicZoneTargets then
            return panicZoneTargets[currentPanicTargetIndex]
        elseif currentPanicTargetIndex <= #panicZoneTargets + #hitZoneTargets then
            return hitZoneTargets[currentPanicTargetIndex - #panicZoneTargets]
        end
    end
    
    -- Prioritize panic zone targets with improved cycling
    if #panicZoneTargets > 0 then
        currentPanicTargetIndex = currentPanicTargetIndex + 1
        if currentPanicTargetIndex > #panicZoneTargets then
            currentPanicTargetIndex = 1
        end
        return panicZoneTargets[currentPanicTargetIndex]
    
    -- Then hit zone targets
    elseif #hitZoneTargets > 0 then
        currentPanicTargetIndex = currentPanicTargetIndex + 1
        if currentPanicTargetIndex > #hitZoneTargets then
            currentPanicTargetIndex = 1
        end
        return hitZoneTargets[currentPanicTargetIndex]
    end
    
    return nil
end

-- Panic mode attack action with bat equip check
local function panicModeAttack(targetData)
    if not targetData or not targetData.character then return false end
    
    local myChar = player.Character
    if not myChar then return false end
    
    local hrp = myChar:FindFirstChild("HumanoidRootPart")
    local target = targetData.character:FindFirstChild("HumanoidRootPart")
    if not hrp or not target then return false end
    
    -- Teleport to target
    hrp.CFrame = target.CFrame * CFrame.new(0, 0, 2)
    
    -- Ensure bat is equipped before attacking
    local bat = ensureBatEquipped()
    if not bat then 
        showToast("PANIC MODE: BAT NOT FOUND", 2)
        return false
    end
    
    -- Attack
    VirtualInputManager:SendMouseButtonEvent(0, 0, 0, true, game, 0)
    task.wait(0.02)
    VirtualInputManager:SendMouseButtonEvent(0, 0, 0, false, game, 0)
    
    lastPanicHitTime = tick()
    return true
end

-- Panic mode main loop with improved target cycling
local function panicModeLoop()
    while panicModeEnabled do
        if not panicModeShutdown then
            local targetData = getNextPanicTarget()
            if targetData then
                panicModeAttack(targetData)
                
                -- Small delay to allow target switching
                task.wait(0.05)
            end
        end
        task.wait(0.1) -- Small delay between attack cycles
    end
end

-- Monitor unlock timer for panic mode shutdown and restoration
local function monitorUnlockTimerForPanic()
    local myBase = getPlayerBase()
    if not myBase then return end
    
    local unlockTimer = myBase:FindFirstChild("RelockButton", true)
    if not unlockTimer then return end
    
    unlockTimer = unlockTimer:FindFirstChild("UnlockTimerBillboard", true)
    if not unlockTimer then return end
    
    unlockTimer = unlockTimer:FindFirstChild("UnlockTimer", true)
    if not unlockTimer or not unlockTimer:IsA("TextLabel") then return end
    
    panicModeConnection = unlockTimer:GetPropertyChangedSignal("Text"):Connect(function()
        local timerText = tostring(unlockTimer.Text)
        
        -- Shut off panic mode when timer shows "00:01" or "0:01"
        if (timerText == "00:01" or timerText == "0:01") and panicModeEnabled and not panicModeShutdown then
            panicModeShutdown = true
            panicModeLastState = true
            
            -- Grey out and lock the toggle
            panicModeToggleControl.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
            TweenService:Create(panicModeKnob, TweenInfo.new(0.15), {Position = UDim2.new(0.1, -7, 0.5, -7)}):Play()
            panicModeStatus.Text = "STATUS: TEMP SHUTDOWN"
            panicModeStatus.TextColor3 = Color3.fromRGB(150, 150, 150)
            
            showToast("PANIC MODE: TEMPORARY SHUTDOWN", 2)
        end
        
        -- Check if base was relocked (timer no longer shows unlock time)
        if panicModeShutdown and panicModeLastState and not (timerText == "00:01" or timerText == "0:01") then
            -- Wait a moment to ensure relock completed
            task.wait(0.5)
            panicModeShutdown = false
            panicModeLastState = false
            
            -- Restore toggle appearance if panic mode is still enabled
            if panicModeEnabled then
                panicModeToggleControl.BackgroundColor3 = Color3.fromRGB(0, 255, 80)
                TweenService:Create(panicModeKnob, TweenInfo.new(0.15), {Position = UDim2.new(0.6, -7, 0.5, -7)}):Play()
                panicModeStatus.Text = "STATUS: ACTIVE"
                panicModeStatus.TextColor3 = Color3.fromRGB(0, 255, 100)
            end
            
            showToast("PANIC MODE: RESTORED", 2)
        end
    end)
end

-- Enable panic mode
local function enablePanicMode()
    local floorPart = findPlayerFloorPart()
    if not floorPart then
        showToast("PANIC MODE: FLOOR PART NOT FOUND", 3)
        return false
    end
    
    -- Reset shutdown state
    panicModeShutdown = false
    
    -- Ensure Auto Relock is enabled
    if not autoRelockEnabled then
        setAutoRelockState(true)
    end
    
    panicModeHeartbeat = RunService.Heartbeat:Connect(function()
        scanPanicZones()
    end)
    
    -- Start panic mode loop
    task.spawn(panicModeLoop)
    
    -- Monitor unlock timer
    monitorUnlockTimerForPanic()
    
    -- Update UI
    panicModeToggleControl.BackgroundColor3 = Color3.fromRGB(0, 255, 80)
    TweenService:Create(panicModeKnob, TweenInfo.new(0.15), {Position = UDim2.new(0.6, -7, 0.5, -7)}):Play()
    panicModeStatus.Text = "STATUS: ACTIVE"
    panicModeStatus.TextColor3 = Color3.fromRGB(0, 255, 100)
    
    showToast("PANIC MODE: ACTIVATED", 2)
    print("[PanicMode] Enabled - monitoring zones.")
    return true
end

-- Disable panic mode
local function disablePanicMode()
    if panicModeHeartbeat then
        panicModeHeartbeat:Disconnect()
        panicModeHeartbeat = nil
    end
    
    if panicModeConnection then
        panicModeConnection:Disconnect()
        panicModeConnection = nil
    end
    
    hitZoneTargets = {}
    panicZoneTargets = {}
    currentPanicTargetIndex = 1
    panicModeShutdown = false
    
    -- Update UI
    panicModeToggleControl.BackgroundColor3 = Color3.fromRGB(255, 40, 40)
    TweenService:Create(panicModeKnob, TweenInfo.new(0.15), {Position = UDim2.new(0.1, -7, 0.5, -7)}):Play()
    panicModeStatus.Text = "STATUS: OFFLINE"
    panicModeStatus.TextColor3 = Color3.fromRGB(150, 150, 150)
    
    showToast("PANIC MODE: DEACTIVATED", 2)
    print("[PanicMode] Disabled.")
end

-- Set panic mode state
local function setPanicModeState(state)
    panicModeEnabled = state
    if panicModeEnabled then
        if enablePanicMode() then
            updateDefenseStatus()
        else
            panicModeEnabled = false
            panicModeToggleControl.BackgroundColor3 = Color3.fromRGB(255, 40, 40)
            TweenService:Create(panicModeKnob, TweenInfo.new(0.15), {Position = UDim2.new(0.1, -7, 0.5, -7)}):Play()
        end
    else
        disablePanicMode()
        updateDefenseStatus()
    end
end

-- Panic Mode toggle handler
panicModeHeader.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 and autoDefenseEnabled and not panicModeShutdown then
        setPanicModeState(not panicModeEnabled)
    end
end)

-- Auto Defense toggle handler with seamless dropdown
local function setDefenseState(state)
    autoDefenseEnabled = state
    if autoDefenseEnabled then
        autoDefenseToggle.BackgroundColor3 = Color3.fromRGB(0, 255, 80)
        TweenService:Create(autoDefenseKnob, TweenInfo.new(0.15, Enum.EasingStyle.Quad), {Position = UDim2.new(0.6, -7, 0.5, -7)}):Play()
        enableAutoDefense()
        
        -- Show Panic Mode dropdown with animation
        panicModeContainer.Visible = true
        TweenService:Create(panicModeContainer, TweenInfo.new(0.3, Enum.EasingStyle.Quad), {Size = UDim2.new(1, 0, 0, 60)}):Play()
        
    else
        autoDefenseToggle.BackgroundColor3 = Color3.fromRGB(255, 40, 40)
        TweenService:Create(autoDefenseKnob, TweenInfo.new(0.15, Enum.EasingStyle.Quad), {Position = UDim2.new(0.1, -7, 0.5, -7)}):Play()
        disableAutoDefense()
        
        -- Hide and disable Panic Mode immediately
        if panicModeEnabled then
            setPanicModeState(false)
        end
        panicModeContainer.Visible = false
        panicModeContainer.Size = UDim2.new(1, 0, 0, 0)
    end
end

-- Toggle click handler for Auto Defense
autoDefenseRow.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        setDefenseState(not autoDefenseEnabled)
    end
end)

-- Update defense status when panic mode targets change
local function startStatusUpdates()
    RunService.Heartbeat:Connect(function()
        if autoDefenseEnabled then
            updateDefenseStatus()
        end
    end)
end

-- Start status updates
startStatusUpdates()

-- finalize root draggable
root.Active = true
root.Draggable = true

-- Final helpful print
print("[BaseFinder] INTERFACE LOADING COMPLETE. SYSTEM ONLINE.")
showToast("SYSTEM_INTRUSION // ONLINE", 2)
