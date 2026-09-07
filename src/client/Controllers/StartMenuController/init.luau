--!strict
--[[
	StartMenuController (client)
	----------------------------
	The FIGHT OR DIE start menu. Purely presentation + local camera; it never
	decides gameplay. PLAY sends the deploy intent to the server (Game.RequestDeploy)
	and hands the camera back to the character; SETTINGS and PROFILE are local
	overlay screens.

	Layout (styled after the NOMAD BROS reference):
	  - Header (top-left): title / subtitle / tagline
	  - Main menu (left): PLAY (selected by default) and SETTINGS, with a hover
	    highlight (arrow + text + vertical indicator go white, gray otherwise),
	    tweened smoothly.
	  - Player info (bottom-left): real avatar + username / rank / team — clicking
	    it opens the PROFILE screen.
	  - Version (bottom-right): version + studio.
	  - Corner brackets on all four corners.

	The 3D world stays visible behind the UI via a scriptable menu camera that
	slowly drifts. It resolves against optional named parts in your map
	(Config.Menu.CameraAnchorName / CameraTargetName) and falls back to a gentle
	orbit near the origin — it never creates map geometry.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Logger = require(Shared.Modules.Logger)
local Remotes = require(Shared.Remotes)

local Theme = require(script:WaitForChild("Theme"))
local SettingsScreen = require(script:WaitForChild("SettingsScreen"))
local ProfileScreen = require(script:WaitForChild("ProfileScreen"))

local StartMenuController = {}
StartMenuController.Name = "StartMenuController"

local log = Logger.scope(StartMenuController.Name)

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

function StartMenuController:Init()
	self._config = Config.Menu
	self._player = Players.LocalPlayer
	self._rows = {} :: { [string]: any }
	self._selected = "Play" -- PLAY highlighted at rest
	self._tweenInfo = TweenInfo.new(self._config.TransitionTime, Enum.EasingStyle.Quad, Enum.EasingStyle.Out)
	-- NOTE: the deploy remote is fetched lazily (in _play) via task.spawn so a
	-- not-yet-created remote can never block the client bootstrap / menu build.
end

function StartMenuController:Start()
	self:_build()
	self:_setupCamera()
	self:_bindPlayerData()
	self:_loadAvatar()
	self:_showScreen("menu")
	log.info("start menu online")
end

-- ---------------------------------------------------------------------------
-- Build
-- ---------------------------------------------------------------------------

function StartMenuController:_build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "FOD_StartMenu"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 20
	gui.Parent = self._player:WaitForChild("PlayerGui")
	self._gui = gui

	-- A container for the main-menu layer (so overlays can hide it cleanly).
	local menu = Instance.new("Frame")
	menu.Name = "MenuLayer"
	menu.BackgroundTransparency = 1
	menu.Size = UDim2.fromScale(1, 1)
	menu.Parent = gui
	self._menuLayer = menu

	-- Corner brackets
	Theme.bracket(menu, 0, 0)
	Theme.bracket(menu, 1, 0)
	Theme.bracket(menu, 0, 1)
	Theme.bracket(menu, 1, 1)

	self:_buildHeader(menu)
	self:_buildMenu(menu)
	self:_buildPlayerInfo(menu)
	self:_buildVersion(menu)

	-- Overlay screens (hidden until opened).
	self._settingsFrame = SettingsScreen.build(gui, function()
		self:_showScreen("menu")
	end)
	self._profile = ProfileScreen.build(gui, function()
		self:_showScreen("menu")
	end)
end

function StartMenuController:_buildHeader(parent: Instance)
	local cfg = self._config

	local platform = Theme.label(parent, cfg.Platform, 14, Theme.Colors.TextGray, Theme.FontMono)
	platform.Position = UDim2.fromOffset(72, 34)
	platform.Size = UDim2.fromOffset(200, 16)

	local title = Theme.label(parent, cfg.Title, 66, Theme.Colors.TextWhite, Theme.FontTitle)
	title.Position = UDim2.fromOffset(70, 78)
	title.Size = UDim2.fromOffset(760, 70)

	local subtitle = Theme.label(parent, cfg.Subtitle, 20, Theme.Colors.TextGray, Theme.FontBold)
	subtitle.Position = UDim2.fromOffset(74, 152)
	subtitle.Size = UDim2.fromOffset(600, 22)

	local tagline = Theme.label(parent, cfg.Tagline, 15, Theme.Colors.TextDim, Theme.FontMono)
	tagline.Position = UDim2.fromOffset(74, 182)
	tagline.Size = UDim2.fromOffset(600, 20)
end

-- One interactive menu row (indicator bar + arrow + text). Returns a handle.
function StartMenuController:_makeRow(parent: Instance, id: string, text: string, y: number)
	local button = Instance.new("TextButton")
	button.Name = id
	button.AutoButtonColor = false
	button.BackgroundTransparency = 1
	button.Text = ""
	button.Size = UDim2.fromOffset(440, 56)
	button.Position = UDim2.fromOffset(0, y)
	button.Parent = parent

	-- Vertical selection indicator
	local indicator = Instance.new("Frame")
	indicator.Name = "Indicator"
	indicator.BorderSizePixel = 0
	indicator.BackgroundColor3 = Theme.Colors.TextWhite
	indicator.BackgroundTransparency = 1 -- hidden until active
	indicator.AnchorPoint = Vector2.new(0, 0.5)
	indicator.Position = UDim2.new(0, 0, 0.5, 0)
	indicator.Size = UDim2.fromOffset(3, 40)
	indicator.Parent = button

	local arrow = Theme.label(button, "▶", 20, Theme.Colors.TextGray, Theme.FontBold)
	arrow.AnchorPoint = Vector2.new(0, 0.5)
	arrow.Position = UDim2.new(0, 22, 0.5, 0)
	arrow.Size = UDim2.fromOffset(26, 26)
	arrow.TextXAlignment = Enum.TextXAlignment.Center

	local textLabel = Theme.label(button, text, 32, Theme.Colors.TextGray, Theme.FontBold)
	textLabel.AnchorPoint = Vector2.new(0, 0.5)
	textLabel.Position = UDim2.new(0, 58, 0.5, 0)
	textLabel.Size = UDim2.fromOffset(360, 40)

	local handle = {
		id = id,
		button = button,
		indicator = indicator,
		arrow = arrow,
		text = textLabel,
		hovered = false,
	}
	self._rows[id] = handle

	button.MouseEnter:Connect(function()
		handle.hovered = true
		self:_refreshRow(handle)
	end)
	button.MouseLeave:Connect(function()
		handle.hovered = false
		self:_refreshRow(handle)
	end)
	button.Activated:Connect(function()
		self:_onRowActivated(id)
	end)

	return handle
end

function StartMenuController:_buildMenu(parent: Instance)
	local holder = Instance.new("Frame")
	holder.Name = "Menu"
	holder.BackgroundTransparency = 1
	holder.AnchorPoint = Vector2.new(0, 0.5)
	holder.Position = UDim2.new(0, 72, 0.52, 0)
	holder.Size = UDim2.fromOffset(440, 140)
	holder.Parent = parent

	self:_makeRow(holder, "Play", "PLAY", 0)
	self:_makeRow(holder, "Settings", "SETTINGS", 64)

	self:_refreshRows()
end

function StartMenuController:_buildPlayerInfo(parent: Instance)
	local button = Instance.new("TextButton")
	button.Name = "PlayerInfo"
	button.AutoButtonColor = false
	button.BackgroundTransparency = 1
	button.Text = ""
	button.AnchorPoint = Vector2.new(0, 1)
	button.Position = UDim2.new(0, 40, 1, -40)
	button.Size = UDim2.fromOffset(380, 104)
	button.Parent = parent

	-- Avatar (real thumbnail set later by _loadAvatar).
	local avatar = Instance.new("ImageLabel")
	avatar.Name = "Avatar"
	avatar.BackgroundColor3 = Color3.fromRGB(6, 7, 5)
	avatar.BorderSizePixel = 0
	avatar.Position = UDim2.fromOffset(0, 4)
	avatar.Size = UDim2.fromOffset(92, 92)
	avatar.ScaleType = Enum.ScaleType.Fit
	avatar.Parent = button
	Theme.corner(avatar, 3)
	local avatarStroke = Theme.stroke(avatar, Theme.Colors.AccentDim, 1, 0.2)
	self._infoAvatar = avatar

	local function field(tag: string, yTag: number): TextLabel
		local t = Theme.label(button, tag, 12, Theme.Colors.Accent, Theme.FontMono)
		t.Position = UDim2.fromOffset(108, yTag)
		t.Size = UDim2.fromOffset(260, 14)
		local v = Theme.label(button, "", 16, Theme.Colors.TextWhite, Theme.FontBold)
		v.Position = UDim2.fromOffset(108, yTag + 14)
		v.Size = UDim2.fromOffset(260, 18)
		return v
	end

	self._infoName = field("PLAYER", 2)
	self._infoRank = field("RANK", 36)
	self._infoTeam = field("TEAM", 70)

	-- Hover feedback: brighten the avatar frame so it reads as clickable.
	button.MouseEnter:Connect(function()
		TweenService:Create(avatarStroke, self._tweenInfo, { Color = Theme.Colors.Accent, Transparency = 0 }):Play()
	end)
	button.MouseLeave:Connect(function()
		TweenService:Create(avatarStroke, self._tweenInfo, { Color = Theme.Colors.AccentDim, Transparency = 0.2 }):Play()
	end)
	button.Activated:Connect(function()
		self:_showScreen("profile")
	end)
end

function StartMenuController:_buildVersion(parent: Instance)
	local cfg = self._config

	local version = Theme.label(parent, cfg.Version, 15, Theme.Colors.TextGray, Theme.FontBold)
	version.AnchorPoint = Vector2.new(1, 1)
	version.Position = UDim2.new(1, -44, 1, -54)
	version.Size = UDim2.fromOffset(200, 18)
	version.TextXAlignment = Enum.TextXAlignment.Right

	local studio = Theme.label(parent, cfg.Studio, 13, Theme.Colors.TextDim, Theme.FontMono)
	studio.AnchorPoint = Vector2.new(1, 1)
	studio.Position = UDim2.new(1, -44, 1, -34)
	studio.Size = UDim2.fromOffset(200, 16)
	studio.TextXAlignment = Enum.TextXAlignment.Right
end

-- ---------------------------------------------------------------------------
-- Hover / selection
-- ---------------------------------------------------------------------------

function StartMenuController:_refreshRow(handle: any)
	local active = handle.hovered or self._selected == handle.id
	local textColor = active and Theme.Colors.TextWhite or Theme.Colors.TextGray
	local indicatorTransparency = active and 0 or 1

	local info = self._tweenInfo
	TweenService:Create(handle.text, info, { TextColor3 = textColor }):Play()
	TweenService:Create(handle.arrow, info, { TextColor3 = textColor }):Play()
	TweenService:Create(handle.indicator, info, { BackgroundTransparency = indicatorTransparency }):Play()
end

function StartMenuController:_refreshRows()
	for _, handle in self._rows do
		self:_refreshRow(handle)
	end
end

function StartMenuController:_onRowActivated(id: string)
	self._selected = id
	self:_refreshRows()
	if id == "Play" then
		self:_play()
	elseif id == "Settings" then
		self:_showScreen("settings")
	end
end

-- ---------------------------------------------------------------------------
-- Screen switching
-- ---------------------------------------------------------------------------

function StartMenuController:_showScreen(which: string)
	self._menuLayer.Visible = which == "menu"
	self._settingsFrame.Visible = which == "settings"
	self._profile.frame.Visible = which == "profile"

	if which == "menu" then
		-- SETTINGS/PROFILE were reached from the menu; PLAY is the resting choice.
		self._selected = "Play"
		self:_refreshRows()
	elseif which == "profile" then
		self._profile.refresh(self:_resolveData())
	end
end

-- ---------------------------------------------------------------------------
-- PLAY -> deploy
-- ---------------------------------------------------------------------------

function StartMenuController:_play()
	-- Fire the server deploy intent (GameSystem handles it; real spawn logic
	-- grows in SpawnSystem). Fetched + fired in a task so a missing/late remote
	-- can never block the UI. Then close the menu and return the camera.
	task.spawn(function()
		local ev = self._requestDeploy or Remotes.getEvent("Game", "RequestDeploy")
		self._requestDeploy = ev
		ev:FireServer()
	end)
	self._gui.Enabled = false
	self:_teardownCamera()
	log.info("PLAY -> deploy requested")
end

-- ---------------------------------------------------------------------------
-- Player data (name / rank / team) + avatar
-- ---------------------------------------------------------------------------

function StartMenuController:_resolveData()
	local player = self._player
	local rank = player:GetAttribute("Rank")
	local team = player:GetAttribute("MenuTeam")
	if (team == nil or team == "") and player.Team then
		team = player.Team.Name
	end
	return {
		name = player.Name,
		rank = (typeof(rank) == "string" and rank ~= "") and rank or self._config.DefaultRank,
		team = (typeof(team) == "string" and team ~= "") and team or self._config.DefaultTeam,
	}
end

function StartMenuController:_refreshInfo()
	local data = self:_resolveData()
	self._infoName.Text = string.upper(data.name)
	self._infoRank.Text = string.upper(data.rank)
	self._infoTeam.Text = string.upper(data.team)
	if self._profile.frame.Visible then
		self._profile.refresh(data)
	end
end

function StartMenuController:_bindPlayerData()
	self:_refreshInfo()
	local player = self._player
	player:GetAttributeChangedSignal("Rank"):Connect(function()
		self:_refreshInfo()
	end)
	player:GetAttributeChangedSignal("MenuTeam"):Connect(function()
		self:_refreshInfo()
	end)
	player:GetPropertyChangedSignal("Team"):Connect(function()
		self:_refreshInfo()
	end)
end

function StartMenuController:_loadAvatar()
	local player = self._player
	task.spawn(function()
		local ok, content = pcall(function()
			return Players:GetUserThumbnailAsync(
				player.UserId,
				Enum.ThumbnailType.AvatarBust,
				Enum.ThumbnailSize.Size150x150
			)
		end)
		if ok and content then
			self._infoAvatar.Image = content
			self._profile.avatar.Image = content
		else
			log.warn("could not load avatar thumbnail:", tostring(content))
		end
	end)
end

-- ---------------------------------------------------------------------------
-- Menu camera (scriptable, slow drift). Never creates world geometry.
-- ---------------------------------------------------------------------------

function StartMenuController:_findPart(name: string): BasePart?
	local inst = Workspace:FindFirstChild(name, true)
	if inst and inst:IsA("BasePart") then
		return inst
	end
	return nil
end

function StartMenuController:_setupCamera()
	local cfg = self._config
	local cam = Workspace.CurrentCamera
	if not cam then
		return
	end
	self._camera = cam
	self._camStart = os.clock()
	self._camAnchor = self:_findPart(cfg.CameraAnchorName)
	self._camTarget = self:_findPart(cfg.CameraTargetName)

	cam.CameraType = Enum.CameraType.Scriptable
	cam.FieldOfView = cfg.CameraFieldOfView

	self._camConn = RunService.RenderStepped:Connect(function()
		self:_updateCamera()
	end)
end

function StartMenuController:_updateCamera()
	local cfg = self._config
	local cam = self._camera
	if not cam then
		return
	end
	local t = os.clock() - self._camStart

	if self._camAnchor then
		-- Sit at the anchor; add a small living sway so the shot isn't static.
		local base = self._camAnchor.CFrame
		local sway = Vector3.new(
			math.sin(t * cfg.CameraSwaySpeed) * cfg.CameraSwayAmount,
			math.sin(t * cfg.CameraSwaySpeed * 0.6) * cfg.CameraSwayAmount * 0.4,
			0
		)
		local pos = base.Position + base:VectorToWorldSpace(sway)
		local look = self._camTarget and self._camTarget.Position or (base.Position + base.LookVector * 20)
		cam.CFrame = CFrame.lookAt(pos, look)
	else
		-- No anchor in the map: gently orbit a point near the origin so the world
		-- (skybox / whatever exists) stays visible behind the UI.
		local center = self._camTarget and self._camTarget.Position or cfg.CameraOrbitCenter
		local angle = t * cfg.CameraOrbitSpeed
		local offset = Vector3.new(
			math.cos(angle) * cfg.CameraOrbitRadius,
			cfg.CameraOrbitHeight,
			math.sin(angle) * cfg.CameraOrbitRadius
		)
		cam.CFrame = CFrame.lookAt(center + offset, center + Vector3.new(0, cfg.CameraLookHeight, 0))
	end
end

function StartMenuController:_teardownCamera()
	if self._camConn then
		self._camConn:Disconnect()
		self._camConn = nil
	end
	local cam = self._camera or Workspace.CurrentCamera
	if cam then
		cam.CameraType = Enum.CameraType.Custom
		local char = self._player.Character
		local humanoid = char and char:FindFirstChildOfClass("Humanoid")
		if humanoid then
			cam.CameraSubject = humanoid
		end
	end
end

return StartMenuController
