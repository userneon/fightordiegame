--!strict
--[[
	HUDController (client) — Military HUD
	------------------------------------
	Tactical, olive/amber styled overlay for FIGHT OR DIE. Purely presentational:
	it reflects authoritative state (never decides outcomes).

	Components:
	  - Corner framing brackets (tactical frame)
	  - Compass strip (top-centre) — heading from the camera, pure client
	  - Health bar   — LocalPlayer character Humanoid
	  - Stamina bar  — Player attribute "Stamina"/"MaxStamina" (MovementSystem)
	  - LOAD readout — Player attribute "CarriedWeight" + "HeavyWalk"
	  - Callsign/team (bottom-left)
	  - Ammo/weapon panel (bottom-right) — hidden until a weapon system sets the
	    "WeaponName"/"Ammo"/"MaxAmmo" attributes; wired but dormant for now.

	Everything degrades gracefully: bars that have no backing data just sit full
	or hidden rather than erroring.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Logger = require(Shared.Modules.Logger)

local HUDController = {}
HUDController.Name = "HUDController"

local log = Logger.scope(HUDController.Name)

-- Palette -------------------------------------------------------------------
local COL_PANEL = Color3.fromRGB(14, 17, 12)
local COL_ACCENT = Color3.fromRGB(168, 181, 69) -- olive/amber
local COL_ACCENT_DIM = Color3.fromRGB(96, 104, 52)
local COL_HP = Color3.fromRGB(120, 190, 90)
local COL_HP_LOW = Color3.fromRGB(206, 66, 55)
local COL_STA = Color3.fromRGB(196, 176, 78)
local COL_STA_LOW = Color3.fromRGB(206, 120, 55)
local COL_WARN = Color3.fromRGB(232, 178, 74)
local FONT = Enum.Font.Code
local FONT_BOLD = Enum.Font.GothamBold

-- Small UI helpers ----------------------------------------------------------

local function corner(inst: Instance, r: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = inst
end

local function stroke(inst: Instance, color: Color3, thickness: number, transparency: number?)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.Transparency = transparency or 0
	s.Parent = inst
	return s
end

local function panel(name: string, parent: Instance): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundColor3 = COL_PANEL
	f.BackgroundTransparency = 0.3
	f.BorderSizePixel = 0
	f.Parent = parent
	corner(f, 3)
	stroke(f, COL_ACCENT_DIM, 1, 0.3)
	return f
end

local function label(parent: Instance, text: string, size: number, color: Color3): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Font = FONT
	t.Text = text
	t.TextSize = size
	t.TextColor3 = color
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.Parent = parent
	return t
end

-- A labelled stat bar (HP / STA). Returns fill + valueLabel.
local function makeBar(parent: Instance, tag: string, y: number, color: Color3): (Frame, TextLabel)
	local row = Instance.new("Frame")
	row.Name = tag .. "Row"
	row.BackgroundTransparency = 1
	row.Size = UDim2.fromOffset(230, 20)
	row.Position = UDim2.fromOffset(0, y)
	row.Parent = parent

	local tagLabel = label(row, tag, 13, COL_ACCENT)
	tagLabel.Size = UDim2.fromOffset(38, 20)
	tagLabel.Position = UDim2.fromOffset(0, 0)
	tagLabel.TextXAlignment = Enum.TextXAlignment.Left

	local track = Instance.new("Frame")
	track.Name = "Track"
	track.Size = UDim2.fromOffset(150, 12)
	track.Position = UDim2.fromOffset(42, 4)
	track.BackgroundColor3 = Color3.fromRGB(8, 10, 7)
	track.BackgroundTransparency = 0.2
	track.BorderSizePixel = 0
	track.Parent = row
	corner(track, 2)
	stroke(track, COL_ACCENT_DIM, 1, 0.4)

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = color
	fill.BorderSizePixel = 0
	fill.Parent = track
	corner(fill, 2)

	local value = label(row, "100", 13, Color3.fromRGB(220, 225, 210))
	value.Size = UDim2.fromOffset(40, 20)
	value.Position = UDim2.fromOffset(198, 0)
	value.TextXAlignment = Enum.TextXAlignment.Right

	return fill, value
end

-- Corner framing brackets (four L shapes).
local function makeBracket(parent: Instance, ax: number, ay: number)
	local size = 26
	local thick = 2
	local holder = Instance.new("Frame")
	holder.BackgroundTransparency = 1
	holder.AnchorPoint = Vector2.new(ax, ay)
	holder.Size = UDim2.fromOffset(size, size)
	holder.Position = UDim2.new(ax, ax == 0 and 16 or -16, ay, ay == 0 and 16 or -16)
	holder.Parent = parent

	local h = Instance.new("Frame")
	h.BorderSizePixel = 0
	h.BackgroundColor3 = COL_ACCENT
	h.BackgroundTransparency = 0.25
	h.Size = UDim2.fromOffset(size, thick)
	h.Position = UDim2.new(0, 0, ay, ay == 0 and 0 or -thick)
	h.Parent = holder

	local v = Instance.new("Frame")
	v.BorderSizePixel = 0
	v.BackgroundColor3 = COL_ACCENT
	v.BackgroundTransparency = 0.25
	v.Size = UDim2.fromOffset(thick, size)
	v.Position = UDim2.new(ax, ax == 0 and 0 or -thick, 0, 0)
	v.Parent = holder
end

-- Compass ------------------------------------------------------------------

local COMPASS_WIDTH = 420
local COMPASS_FOV = 100 -- degrees of heading shown across the strip

local function shortestAngle(a: number, b: number): number
	local d = (a - b + 180) % 360 - 180
	return d
end

function HUDController:_buildCompass(gui: ScreenGui)
	local holder = panel("Compass", gui)
	holder.AnchorPoint = Vector2.new(0.5, 0)
	holder.Position = UDim2.new(0.5, 0, 0, 14)
	holder.Size = UDim2.fromOffset(COMPASS_WIDTH, 34)
	holder.ClipsDescendants = true

	-- Centre marker
	local center = Instance.new("Frame")
	center.BorderSizePixel = 0
	center.BackgroundColor3 = COL_WARN
	center.AnchorPoint = Vector2.new(0.5, 0)
	center.Position = UDim2.new(0.5, 0, 0, 0)
	center.Size = UDim2.fromOffset(2, 34)
	center.ZIndex = 5
	center.Parent = holder

	-- Heading readout
	local heading = label(gui, "000", 14, COL_WARN)
	heading.AnchorPoint = Vector2.new(0.5, 0)
	heading.Position = UDim2.new(0.5, 0, 0, 50)
	heading.Size = UDim2.fromOffset(60, 16)
	heading.TextXAlignment = Enum.TextXAlignment.Center
	heading.Font = FONT_BOLD

	-- Marks every 15°, labels at cardinals/intercardinals.
	local cardinals = {
		[0] = "N",
		[45] = "NE",
		[90] = "E",
		[135] = "SE",
		[180] = "S",
		[225] = "SW",
		[270] = "W",
		[315] = "NW",
	}
	local marks = {}
	for a = 0, 345, 15 do
		local text = cardinals[a]
		local mark
		if text then
			mark = label(holder, text, text == "N" and 15 or 13, text == "N" and COL_WARN or COL_ACCENT)
			mark.AnchorPoint = Vector2.new(0.5, 0)
			mark.Size = UDim2.fromOffset(30, 20)
			mark.Position = UDim2.new(0.5, 0, 0, 8)
			mark.TextXAlignment = Enum.TextXAlignment.Center
			mark.Font = FONT_BOLD
		else
			mark = Instance.new("Frame")
			mark.BorderSizePixel = 0
			mark.BackgroundColor3 = COL_ACCENT_DIM
			mark.AnchorPoint = Vector2.new(0.5, 0)
			mark.Size = UDim2.fromOffset(1, 8)
			mark.Position = UDim2.new(0.5, 0, 0, 22)
			mark.Parent = holder
		end
		marks[a] = mark
	end

	self._compassMarks = marks
	self._compassHeading = heading
	self._compassHalf = COMPASS_WIDTH / 2
end

function HUDController:_updateCompass()
	local cam = Workspace.CurrentCamera
	if not cam or not self._compassMarks then
		return
	end
	local look = cam.CFrame.LookVector
	-- Heading: 0 = +Z (north-ish convention), clockwise.
	local yaw = math.deg(math.atan2(look.X, look.Z))
	yaw = (yaw + 360) % 360

	self._compassHeading.Text = string.format("%03d", math.floor(yaw + 0.5) % 360)

	local half = self._compassHalf
	for a, mark in self._compassMarks do
		local delta = shortestAngle(a, yaw)
		if math.abs(delta) <= COMPASS_FOV / 2 then
			mark.Visible = true
			local x = 0.5 + (delta / COMPASS_FOV)
			mark.Position = UDim2.new(x, 0, 0, mark:IsA("TextLabel") and 8 or 22)
		else
			mark.Visible = false
		end
	end
end

-- Build --------------------------------------------------------------------

function HUDController:Init()
	self._player = Players.LocalPlayer
end

function HUDController:_build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "FOD_MilitaryHUD"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 10
	gui.Parent = self._player:WaitForChild("PlayerGui")
	self._gui = gui

	-- Corner brackets
	makeBracket(gui, 0, 0)
	makeBracket(gui, 1, 0)
	makeBracket(gui, 0, 1)
	makeBracket(gui, 1, 1)

	-- Compass
	self:_buildCompass(gui)

	-- Bottom-left status cluster
	local status = Instance.new("Frame")
	status.Name = "Status"
	status.BackgroundTransparency = 1
	status.AnchorPoint = Vector2.new(0, 1)
	status.Position = UDim2.new(0, 26, 1, -26)
	status.Size = UDim2.fromOffset(240, 92)
	status.Parent = gui

	self._hpFill, self._hpValue = makeBar(status, "HP", 0, COL_HP)
	self._staFill, self._staValue = makeBar(status, "STA", 24, COL_STA)

	-- LOAD readout
	local loadLbl = label(status, "LOAD  0 kg", 13, COL_ACCENT)
	loadLbl.Size = UDim2.fromOffset(160, 18)
	loadLbl.Position = UDim2.fromOffset(0, 50)
	self._loadLabel = loadLbl

	local heavy = label(status, "// OVERWEIGHT", 13, COL_WARN)
	heavy.Size = UDim2.fromOffset(140, 18)
	heavy.Position = UDim2.fromOffset(100, 50)
	heavy.Font = FONT_BOLD
	heavy.Visible = false
	self._heavyLabel = heavy

	-- Callsign / team
	local call = label(status, string.upper(self._player.Name), 15, Color3.fromRGB(220, 225, 210))
	call.Size = UDim2.fromOffset(240, 18)
	call.Position = UDim2.fromOffset(0, 72)
	call.Font = FONT_BOLD
	self._callLabel = call

	-- Ammo / weapon panel (bottom-right) — dormant until a weapon system feeds it
	local ammo = panel("Ammo", gui)
	ammo.AnchorPoint = Vector2.new(1, 1)
	ammo.Position = UDim2.new(1, -26, 1, -26)
	ammo.Size = UDim2.fromOffset(150, 62)
	ammo.Visible = false

	local weaponName = label(ammo, "—", 13, COL_ACCENT)
	weaponName.Size = UDim2.new(1, -16, 0, 16)
	weaponName.Position = UDim2.fromOffset(10, 6)

	local ammoCount = label(ammo, "0 / 0", 24, Color3.fromRGB(220, 225, 210))
	ammoCount.Size = UDim2.new(1, -16, 0, 30)
	ammoCount.Position = UDim2.fromOffset(10, 24)
	ammoCount.Font = FONT_BOLD

	self._ammoPanel = ammo
	self._weaponName = weaponName
	self._ammoCount = ammoCount
end

-- Refreshers ----------------------------------------------------------------

function HUDController:_refreshHealth()
	local char = self._player.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local ratio = humanoid.MaxHealth > 0 and math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1) or 0
	self._hpFill.Size = UDim2.fromScale(ratio, 1)
	self._hpFill.BackgroundColor3 = ratio < 0.3 and COL_HP_LOW or COL_HP
	self._hpValue.Text = tostring(math.floor(humanoid.Health + 0.5))
end

function HUDController:_refreshStamina()
	local player = self._player
	local stamina = player:GetAttribute("Stamina")
	local maxStamina = player:GetAttribute("MaxStamina")
	if typeof(stamina) == "number" and typeof(maxStamina) == "number" and maxStamina > 0 then
		local ratio = math.clamp(stamina / maxStamina, 0, 1)
		self._staFill.Size = UDim2.fromScale(ratio, 1)
		self._staFill.BackgroundColor3 = ratio < 0.25 and COL_STA_LOW or COL_STA
		self._staValue.Text = tostring(math.floor(stamina + 0.5))
	end
end

function HUDController:_refreshLoad()
	local player = self._player
	local weight = player:GetAttribute("CarriedWeight")
	if typeof(weight) == "number" then
		self._loadLabel.Text = string.format("LOAD  %d kg", math.floor(weight + 0.5))
	end
	self._heavyLabel.Visible = player:GetAttribute("HeavyWalk") == true
end

function HUDController:_refreshAmmo()
	local player = self._player
	local name = player:GetAttribute("WeaponName")
	if typeof(name) == "string" and name ~= "" then
		self._ammoPanel.Visible = true
		self._weaponName.Text = string.upper(name)
		local ammo = player:GetAttribute("Ammo")
		local maxAmmo = player:GetAttribute("MaxAmmo")
		self._ammoCount.Text = string.format(
			"%d / %d",
			typeof(ammo) == "number" and ammo or 0,
			typeof(maxAmmo) == "number" and maxAmmo or 0
		)
	else
		self._ammoPanel.Visible = false
	end
end

function HUDController:_bindCharacter()
	local function onChar(char: Model)
		local humanoid = char:WaitForChild("Humanoid", 10)
		if humanoid and humanoid:IsA("Humanoid") then
			self:_refreshHealth()
			humanoid.HealthChanged:Connect(function()
				self:_refreshHealth()
			end)
		end
	end
	if self._player.Character then
		onChar(self._player.Character)
	end
	self._player.CharacterAdded:Connect(onChar)
end

function HUDController:Start()
	self:_build()
	self:_bindCharacter()
	self:_refreshStamina()
	self:_refreshLoad()
	self:_refreshAmmo()

	local player = self._player
	player:GetAttributeChangedSignal("Stamina"):Connect(function()
		self:_refreshStamina()
	end)
	player:GetAttributeChangedSignal("CarriedWeight"):Connect(function()
		self:_refreshLoad()
	end)
	player:GetAttributeChangedSignal("HeavyWalk"):Connect(function()
		self:_refreshLoad()
	end)
	for _, attr in { "WeaponName", "Ammo", "MaxAmmo" } do
		player:GetAttributeChangedSignal(attr):Connect(function()
			self:_refreshAmmo()
		end)
	end

	-- Compass follows the camera every frame.
	RunService.RenderStepped:Connect(function()
		self:_updateCompass()
	end)

	log.info("military HUD online — compass, HP/STA bars, load, callsign")
end

return HUDController
