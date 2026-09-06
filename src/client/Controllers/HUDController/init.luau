--!strict
--[[
	HUDController (client)
	----------------------
	Player-facing HUD. Reflects authoritative state pushed from the server; it
	never decides outcomes.

	Built now: a stamina bar + a "HEAVY" indicator, driven by the Player
	attributes MovementSystem replicates (Stamina, MaxStamina, HeavyWalk).
	Health/inventory/prompts/progress-bars get added as those systems land.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Logger = require(Shared.Modules.Logger)

local HUDController = {}
HUDController.Name = "HUDController"

local log = Logger.scope(HUDController.Name)

local LOW_STAMINA_COLOR = Color3.fromRGB(214, 69, 65)
local OK_STAMINA_COLOR = Color3.fromRGB(120, 200, 120)

function HUDController:Init()
	self._player = Players.LocalPlayer
end

function HUDController:_build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "FOD_HUD"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.IgnoreGuiInset = true
	gui.Parent = self._player:WaitForChild("PlayerGui")

	-- Stamina bar (bottom-centre).
	local holder = Instance.new("Frame")
	holder.Name = "StaminaHolder"
	holder.AnchorPoint = Vector2.new(0.5, 1)
	holder.Position = UDim2.new(0.5, 0, 1, -24)
	holder.Size = UDim2.fromOffset(220, 10)
	holder.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
	holder.BackgroundTransparency = 0.35
	holder.BorderSizePixel = 0
	holder.Parent = gui

	local holderCorner = Instance.new("UICorner")
	holderCorner.CornerRadius = UDim.new(0, 5)
	holderCorner.Parent = holder

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = OK_STAMINA_COLOR
	fill.BorderSizePixel = 0
	fill.Parent = holder

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 5)
	fillCorner.Parent = fill

	-- HEAVY indicator (above the bar).
	local heavy = Instance.new("TextLabel")
	heavy.Name = "HeavyLabel"
	heavy.AnchorPoint = Vector2.new(0.5, 1)
	heavy.Position = UDim2.new(0.5, 0, 1, -40)
	heavy.Size = UDim2.fromOffset(220, 18)
	heavy.BackgroundTransparency = 1
	heavy.Font = Enum.Font.GothamBold
	heavy.TextSize = 14
	heavy.TextColor3 = Color3.fromRGB(240, 190, 90)
	heavy.Text = "HEAVY"
	heavy.Visible = false
	heavy.Parent = gui

	self._fill = fill
	self._heavy = heavy
end

function HUDController:_refresh()
	local player = self._player
	local stamina = player:GetAttribute("Stamina")
	local maxStamina = player:GetAttribute("MaxStamina")
	if typeof(stamina) == "number" and typeof(maxStamina) == "number" and maxStamina > 0 then
		local ratio = math.clamp(stamina / maxStamina, 0, 1)
		self._fill.Size = UDim2.fromScale(ratio, 1)
		self._fill.BackgroundColor3 = ratio < 0.25 and LOW_STAMINA_COLOR or OK_STAMINA_COLOR
	end
	self._heavy.Visible = player:GetAttribute("HeavyWalk") == true
end

function HUDController:Start()
	self:_build()
	self:_refresh()

	local player = self._player
	player:GetAttributeChangedSignal("Stamina"):Connect(function()
		self:_refresh()
	end)
	player:GetAttributeChangedSignal("HeavyWalk"):Connect(function()
		self:_refresh()
	end)

	log.info("HUD online — stamina bar + heavy indicator")
end

return HUDController
