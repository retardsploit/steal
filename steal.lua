-- Full revised script with power threshold, 2nd-floor support, rare rig finder, toasts, and path locate.
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
-- Notifications (center-top toasts)
-- ====================
local gui = Instance.new("ScreenGui")
gui.Name = "BaseFinderGUI"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.Parent = game.CoreGui

-- Root frame centered (keeps your original layout)
local root = Instance.new("Frame")
root.Name = "Root"
root.Size = UDim2.new(0, 360, 0, 280)
root.AnchorPoint = Vector2.new(0.5, 0.5)
root.Position = UDim2.new(0.5, 0.5, 0.5, 0)
root.BackgroundTransparency = 1
root.Active = true
root.Draggable = true
root.Parent = gui

-- Backdrop container
local container = Instance.new("Frame")
container.Name = "Container"
container.Size = UDim2.new(1, 0, 1, 0)
container.Position = UDim2.new(0, 0, 0, 0)
container.BackgroundColor3 = Color3.fromRGB(14, 14, 18)
container.BorderSizePixel = 0
container.Parent = root
local contCorner = Instance.new("UICorner", container)
contCorner.CornerRadius = UDim.new(0, 12)
local contStroke = Instance.new("UIStroke", container)
contStroke.Thickness = 1
contStroke.Color = Color3.fromRGB(0, 190, 150)
contStroke.Transparency = 0.5

-- Header bar
local header = Instance.new("Frame", container)
header.Size = UDim2.new(1, 0, 0, 52)
header.Position = UDim2.new(0, 0, 0, 0)
header.BackgroundTransparency = 1

local title = Instance.new("TextLabel", header)
title.Size = UDim2.new(0.8, -16, 1, -8)
title.Position = UDim2.new(0, 12, 0, 8)
title.BackgroundTransparency = 1
title.Text = "steal"
title.TextColor3 = Color3.fromRGB(180, 255, 240)
title.Font = Enum.Font.GothamSemibold
title.TextSize = 18
title.TextXAlignment = Enum.TextXAlignment.Left

local closeHole = Instance.new("Frame", header)
closeHole.Size = UDim2.new(0, 36, 0, 36)
closeHole.AnchorPoint = Vector2.new(1, 0)
closeHole.Position = UDim2.new(1, -12, 0, 8)
closeHole.BackgroundTransparency = 0.9
closeHole.Parent = header
local chCorner = Instance.new("UICorner", closeHole)
chCorner.CornerRadius = UDim.new(0, 10)

-- Body area with padding
local body = Instance.new("Frame", container)
body.Size = UDim2.new(1, -24, 1, -72)
body.Position = UDim2.new(0, 12, 0, 60)
body.BackgroundTransparency = 1

local listLayout = Instance.new("UIListLayout", body)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Padding = UDim.new(0, 8)

-- Buttons container and factory
local function makeButton(text, order)
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(1, 0, 0, 44)
	btn.LayoutOrder = order or 1
	btn.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
	btn.BorderSizePixel = 0
	btn.Text = text
	btn.TextColor3 = Color3.fromRGB(210, 255, 245)
	btn.Font = Enum.Font.GothamSemibold
	btn.TextSize = 15
	btn.AutoButtonColor = false

	local corner = Instance.new("UICorner", btn)
	corner.CornerRadius = UDim.new(0, 8)
	local stroke = Instance.new("UIStroke", btn)
	stroke.Thickness = 1
	stroke.Color = Color3.fromRGB(0, 160, 120)
	stroke.Transparency = 0.55

	btn.MouseEnter:Connect(function()
		TweenService:Create(btn, TweenInfo.new(0.12, Enum.EasingStyle.Sine), {BackgroundTransparency = 0.15}):Play()
	end)
	btn.MouseLeave:Connect(function()
		TweenService:Create(btn, TweenInfo.new(0.12, Enum.EasingStyle.Sine), {BackgroundTransparency = 0}):Play()
	end)

	btn.Parent = body
	return btn
end

-- Existing buttons
local btnFindBase = makeButton("expand steal zone", 1)
local btnHighlight = makeButton("0 cd steal", 2)

-- Toggle row (Auto Relock)
local toggleRow = Instance.new("Frame", body)
toggleRow.Size = UDim2.new(1, 0, 0, 48)
toggleRow.LayoutOrder = 3
toggleRow.BackgroundTransparency = 1

local lblToggle = Instance.new("TextLabel", toggleRow)
lblToggle.Size = UDim2.new(0.68, 0, 1, 0)
lblToggle.BackgroundTransparency = 1
lblToggle.Text = "Auto Relock"
lblToggle.TextColor3 = Color3.fromRGB(210, 255, 245)
lblToggle.Font = Enum.Font.GothamSemibold
lblToggle.TextSize = 15
lblToggle.TextXAlignment = Enum.TextXAlignment.Left

local toggleControl = Instance.new("Frame", toggleRow)
toggleControl.Size = UDim2.new(0.3, 0, 0.62, 0)
toggleControl.Position = UDim2.new(0.68, 0, 0.19, 0)
toggleControl.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
toggleControl.BorderSizePixel = 0
local toggleCorner = Instance.new("UICorner", toggleControl)
toggleCorner.CornerRadius = UDim.new(1, 0)

local knob = Instance.new("Frame", toggleControl)
knob.Size = UDim2.new(0, 20, 0, 20)
knob.Position = UDim2.new(0.06, 0, 0.5, -10)
knob.BackgroundColor3 = Color3.fromRGB(245, 245, 245)
knob.BorderSizePixel = 0
local kCorner = Instance.new("UICorner", knob)
kCorner.CornerRadius = UDim.new(1, 0)

-- Separator
local sep = Instance.new("Frame", body)
sep.Size = UDim2.new(1, 0, 0, 6)
sep.LayoutOrder = 4
sep.BackgroundTransparency = 1

-- Highlight threshold controls
local thresholdRow = Instance.new("Frame", body)
thresholdRow.Size = UDim2.new(1, 0, 0, 44)
thresholdRow.LayoutOrder = 5
thresholdRow.BackgroundTransparency = 1

local threshLabel = Instance.new("TextLabel", thresholdRow)
threshLabel.Size = UDim2.new(0.5, 0, 1, 0)
threshLabel.BackgroundTransparency = 1
threshLabel.Text = "CD Power Threshold"
threshLabel.TextColor3 = Color3.fromRGB(210, 255, 245)
threshLabel.Font = Enum.Font.GothamSemibold
threshLabel.TextSize = 14
threshLabel.TextXAlignment = Enum.TextXAlignment.Left

local threshInput = Instance.new("TextBox", thresholdRow)
threshInput.Size = UDim2.new(0.35, 0, 0.84, 0)
threshInput.Position = UDim2.new(0.5, 8, 0.08, 0)
threshInput.ClearTextOnFocus = false
threshInput.Text = tostring(powerThreshold)
threshInput.PlaceholderText = "e.g. 2500"
threshInput.Font = Enum.Font.GothamSemibold
threshInput.TextSize = 14
threshInput.BackgroundColor3 = Color3.fromRGB(20,20,24)
threshInput.TextColor3 = Color3.fromRGB(210,255,245)
threshInput.BorderSizePixel = 0
local thrCorner = Instance.new("UICorner", threshInput)
thrCorner.CornerRadius = UDim.new(0, 6)

local applyBtn = Instance.new("TextButton", thresholdRow)
applyBtn.Size = UDim2.new(0.15, 0, 0.84, 0)
applyBtn.Position = UDim2.new(0.85, -4, 0.08, 0)
applyBtn.Text = "Apply"
applyBtn.Font = Enum.Font.GothamSemibold
applyBtn.TextSize = 14
applyBtn.BackgroundColor3 = Color3.fromRGB(20,20,24)
applyBtn.TextColor3 = Color3.fromRGB(210,255,245)
applyBtn.BorderSizePixel = 0
local applyCorner = Instance.new("UICorner", applyBtn)
applyCorner.CornerRadius = UDim.new(0, 6)

-- Separator
local sep2 = Instance.new("Frame", body)
sep2.Size = UDim2.new(1, 0, 0, 6)
sep2.LayoutOrder = 6
sep2.BackgroundTransparency = 1

-- Rare Rig Finder controls
local rareLabel = Instance.new("TextLabel", body)
rareLabel.Size = UDim2.new(1, 0, 0, 20)
rareLabel.LayoutOrder = 7
rareLabel.BackgroundTransparency = 1
rareLabel.Text = "demon finder"
rareLabel.TextColor3 = Color3.fromRGB(210,255,245)
rareLabel.Font = Enum.Font.GothamSemibold
rareLabel.TextSize = 14
rareLabel.TextXAlignment = Enum.TextXAlignment.Left

local scanBtn = makeButton("scan", 8)
local locateBtn = makeButton("locate last found", 9)

-- Small helper text under controls (intentionally blank per earlier request)

-- Appear animation
container.BackgroundTransparency = 1
TweenService:Create(container, TweenInfo.new(0.42, Enum.EasingStyle.Sine), {BackgroundTransparency = 0}):Play()
TweenService:Create(title, TweenInfo.new(0.5, Enum.EasingStyle.Sine), {TextTransparency = 0}):Play()

-- ====================
-- Toast system (center-top)
-- ====================
local toastContainer = Instance.new("Frame", gui)
toastContainer.Name = "ToastContainer"
toastContainer.AnchorPoint = Vector2.new(0.5, 0)
toastContainer.Position = UDim2.new(0.5, 0, 0, 10) -- centered near top
toastContainer.Size = UDim2.new(0.5, 0, 0, 0)
toastContainer.BackgroundTransparency = 1
toastContainer.Parent = gui

local function showToast(text, duration)
	duration = duration or 4
	-- create toast frame
	local toast = Instance.new("Frame")
	toast.Size = UDim2.new(1, 0, 0, 44)
	toast.BackgroundColor3 = Color3.fromRGB(20, 24, 28)
	toast.BorderSizePixel = 0
	toast.AnchorPoint = Vector2.new(0.5, 0)
	toast.Position = UDim2.new(0.5, 0, 0, 0)
	toast.BackgroundTransparency = 1
	toast.Parent = toastContainer

	local corner = Instance.new("UICorner", toast)
	corner.CornerRadius = UDim.new(0, 8)
	local stroke = Instance.new("UIStroke", toast)
	stroke.Color = Color3.fromRGB(0, 160, 120)
	stroke.Transparency = 0.55
	stroke.Thickness = 1

	local label = Instance.new("TextLabel", toast)
	label.Size = UDim2.new(1, -16, 1, -12)
	label.Position = UDim2.new(0, 8, 0, 6)
	label.BackgroundTransparency = 1
	label.Text = tostring(text)
	label.TextColor3 = Color3.fromRGB(220, 255, 240)
	label.Font = Enum.Font.GothamSemibold
	label.TextSize = 14
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center

	-- animate in
	toast.Position = UDim2.new(0.5, 0, 0, -60)
	TweenService:Create(toast, TweenInfo.new(0.28, Enum.EasingStyle.Sine), {Position = UDim2.new(0.5, 0, 0, 10), BackgroundTransparency = 0}):Play()
	wait(0.28)
	-- stay
	task.wait(duration)
	-- animate out
	local outTween = TweenService:Create(toast, TweenInfo.new(0.28, Enum.EasingStyle.Sine), {Position = UDim2.new(0.5, 0, 0, -60), BackgroundTransparency = 1})
	outTween:Play()
	outTween.Completed:Wait()
	toast:Destroy()
end

-- ====================
-- Find & Resize My Base
-- ====================
local function findAndResizeBase()
	local basesFolder = workspace:FindFirstChild("Bases")
	if not basesFolder then
		warn("[BaseFinder] Folder 'Bases' not found.")
		showToast("Bases folder not found.", 3)
		return
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
						collectZone.Size = Vector3.new(1000, 1.1, 1000)
						collectZone.CanCollide = false
						collectZone.Transparency = 0.4
						print("[BaseFinder] ✅ Found and resized your CollectZone in:", baseModel.Name)
						showToast("CollectZone expanded (non-collidable & translucent).", 3)
					end
					break
				end
			end
		end
	end

	if not found then
		warn("[BaseFinder] ❌ Could not find a base with your display name (" .. displayName .. ").")
		showToast("Could not find your base by display name.", 3)
	end
end

-- ====================
-- Auto Relock wiring (unchanged core)
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
		showToast("AutoRelock: Your base not found.", 3)
		return
	end

	local targetPart = findRelockPart(myBase)
	if not targetPart then
		warn("[AutoRelock] Could not find a relock BasePart inside your base.")
		showToast("AutoRelock: Relock part not found in your base.", 3)
		return
	end

	local unlockLabel = findUnlockLabel(myBase)
	if not unlockLabel then
		warn("[AutoRelock] Could not find an UnlockTimer TextLabel in your base.")
		showToast("AutoRelock: Unlock label not found.", 3)
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
	showToast("AutoRelock enabled.", 2)
end

local function disableAutoRelock()
	if relockConnection then
		relockConnection:Disconnect()
		relockConnection = nil
	end
	debounceFired = false
	print("[AutoRelock] ❌ Disabled.")
	showToast("AutoRelock disabled.", 2)
end

local function setSwitchState(state)
	autoRelockEnabled = state
	if autoRelockEnabled then
		toggleControl.BackgroundColor3 = Color3.fromRGB(50, 200, 50)
		TweenService:Create(knob, TweenInfo.new(0.18, Enum.EasingStyle.Sine), {Position = UDim2.new(0.56, 0, 0.5, -10)}):Play()
		enableAutoRelock()
	else
		toggleControl.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
		TweenService:Create(knob, TweenInfo.new(0.18, Enum.EasingStyle.Sine), {Position = UDim2.new(0.06, 0, 0.5, -10)}):Play()
		disableAutoRelock()
	end
end

setSwitchState(false)

-- toggle click
toggleRow.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		setSwitchState(not autoRelockEnabled)
	end
end)

-- ====================
-- Hook buttons
-- ====================
btnFindBase.MouseButton1Click:Connect(function()
	print("[BaseFinder] Searching for your base by display name...")
	findAndResizeBase()
end)

btnHighlight.MouseButton1Click:Connect(function()
	print("[Highlight] Starting highlight scan for >" .. tostring(powerThreshold) .. " power (ignoring your base)...")
	highlightHighPowerRigs()
	showToast("Highlight scan complete.", 2)
end)

-- Apply threshold
applyBtn.MouseButton1Click:Connect(function()
	local txt = trim(threshInput.Text)
	local n = tonumber(txt)
	if n and n > 0 then
		powerThreshold = n
		showToast("Threshold set to " .. tostring(n), 2)
	else
		showToast("Invalid threshold value.", 2)
	end
end)

-- ====================
-- Rare Rig Finder scanning and locate
-- ====================
local function scanForRareRigs()
	local basesFolder = workspace:FindFirstChild("Bases")
	if not basesFolder then
		showToast("Bases folder not found.", 3)
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
								shortText = string.format("😈 Found DemonWing in %s (%s)", tostring(baseModel.Name), tostring(r.bodyPart))
							else
								shortText = string.format("⚔️ Found KnightBoss part in %s (%s)", tostring(baseModel.Name), tostring(r.bodyPart))
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
		showToast("No rare parts found.", 3)
	else
		showToast("Scan finished: " .. tostring(foundCount) .. " rare result(s).", 3)
	end
end

-- utility: draw path guide (simple straight-segment guide)
local function drawPathToTarget(targetCFrame, duration)
	local character = player.Character
	if not character then return end
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	local startPos = hrp.Position
	local endPos = targetCFrame.Position
	local dist = (endPos - startPos).Magnitude
	if dist < 1 then return end

	local segmentCount = math.clamp(math.ceil(dist / 6), 6, 40) -- segments every ~6 studs
	local parts = {}

	for i = 1, segmentCount do
		local t = i / segmentCount
		local pos = startPos:Lerp(endPos, t)
		local part = Instance.new("Part")
		part.Anchored = true
		part.CanCollide = false
		part.Size = Vector3.new(0.6, 0.6, 0.6)
		part.CFrame = CFrame.new(pos)
		part.Material = Enum.Material.Neon
		part.Transparency = 0.35
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Parent = workspace
		table.insert(parts, part)
	end

	-- optionally draw a final marker (a neon wedge/part)
	local marker = Instance.new("Part")
	marker.Size = Vector3.new(1.2, 1.2, 1.2)
	marker.CFrame = CFrame.new(endPos + Vector3.new(0, 1.2, 0))
	marker.Anchored = true
	marker.CanCollide = false
	marker.Material = Enum.Material.Neon
	marker.Transparency = 0.25
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
		showToast("No previously found rig to locate. Run Scan first.", 3)
		return
	end

	-- try to locate spawn position
	local spawn = lastFoundInfo.spawn
	local targetCFrame = nil
	-- prefer a BasePart inside spawn (e.g., spawn itself or its primary part)
	if spawn:IsA("BasePart") then
		targetCFrame = spawn.CFrame
	else
		-- find first BasePart descendant
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
		showToast("Could not find a physical spawn part to locate.", 3)
		return
	end

	showToast("Drawing guide to last found rig (" .. tostring(lastFoundInfo.kind) .. " - " .. tostring(lastFoundInfo.bodyPartName) .. ")", 3)
	drawPathToTarget(targetCFrame, 5)
end)

scanBtn.MouseButton1Click:Connect(function()
	showToast("Scanning for rare rigs...", 2)
	task.spawn(scanForRareRigs)
end)

-- finalize root draggable
root.Active = true
root.Draggable = true

-- Final helpful print
print("[BaseFinder] Script loaded. UI ready.")
showToast("BaseFinder ready.", 2)
