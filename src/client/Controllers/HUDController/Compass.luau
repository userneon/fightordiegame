--!strict
--[[
	Compass (client HUD component)
	------------------------------
	A functional, open-world compass strip. It renders DIRECTLY over the 3D world
	— no box, panel, card, or background frame, and no hard clipping. The strip
	fades smoothly toward both horizontal edges by driving each element's
	transparency from its distance to centre, so the outermost markings become
	almost invisible without a clip edge.

	  - Cardinals (N NE E SE S SW W NW) and degree numbers every TickSpacing°.
	  - A fixed centre indicator (line + triangle); the markings scroll under it.
	  - Heading comes from the camera look vector, smoothed (no snapping).

	Modular + reusable: it is a plain component, not a controller. Any HUD (Army,
	Terrorist, …) mounts one with:

		local Compass = require(path.to.Compass)
		local compass = Compass.new(someScreenGui)   -- optional overrides table
		-- later: compass.setVisible(false) / compass.destroy()

	It owns its own RenderStepped loop and cleans up on destroy().
]]

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

local Compass = {}

-- Palette (kept local so the component is self-contained / theme-portable).
local COL_CARDINAL = Color3.fromRGB(236, 238, 230)
local COL_NORTH = Color3.fromRGB(232, 178, 74)
local COL_NUMBER = Color3.fromRGB(150, 158, 120)
local COL_TICK = Color3.fromRGB(150, 158, 120)
local COL_CENTER = Color3.fromRGB(232, 178, 74)
local FONT = Enum.Font.Code

local CARDINALS: { [number]: string } = {
	[0] = "N",
	[45] = "NE",
	[90] = "E",
	[135] = "SE",
	[180] = "S",
	[225] = "SW",
	[270] = "W",
	[315] = "NW",
}

-- Signed shortest angular distance a - b, in (-180, 180].
local function shortestAngle(a: number, b: number): number
	return (a - b + 180) % 360 - 180
end

local function smoothstep(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

-- Heading (0..360) from the current camera, or nil if no camera yet.
-- 0 = +Z (matches the game's north convention), increasing clockwise.
local function readYaw(): number?
	local cam = Workspace.CurrentCamera
	if not cam then
		return nil
	end
	local look = cam.CFrame.LookVector
	return (math.deg(math.atan2(look.X, look.Z)) + 360) % 360
end

function Compass.new(parent: Instance, overrides: { [string]: any }?)
	local cfg = Config.HUD.Compass
	local o = overrides or {}
	local width: number = o.Width or cfg.Width
	local height: number = o.Height or cfg.Height
	local y: number = o.Y or cfg.Y
	local span: number = o.SpanDegrees or cfg.SpanDegrees
	local tickSpacing: number = o.TickSpacing or cfg.TickSpacing
	local smoothing: number = o.Smoothing or cfg.Smoothing
	local fadeStart: number = o.FadeStart or cfg.FadeStart
	local halfSpan = span / 2

	-- Transparent container — purely for centering/anchoring. No background, no
	-- stroke, no ClipsDescendants: nothing of it is ever drawn.
	local root = Instance.new("Frame")
	root.Name = "Compass"
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.AnchorPoint = Vector2.new(0.5, 0)
	root.Position = UDim2.new(0.5, 0, 0, y)
	root.Size = UDim2.fromOffset(width, height)
	root.Parent = parent

	local labelY = 0
	local tickY = 24

	-- One reusable element per TickSpacing° mark (24 at 15°): a text label plus a
	-- tick. We reposition + refade them every frame rather than clipping.
	type Mark = { angle: number, label: TextLabel, tick: Frame, cardinal: boolean }
	local marks: { Mark } = {}
	for a = 0, 359, tickSpacing do
		local cardinalText = CARDINALS[a]
		local isCardinal = cardinalText ~= nil

		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.AnchorPoint = Vector2.new(0.5, 0)
		label.Size = UDim2.fromOffset(46, 18)
		label.Position = UDim2.new(0.5, 0, 0, labelY)
		label.Font = FONT
		label.Text = cardinalText or tostring(a)
		label.TextSize = isCardinal and 16 or 12
		label.TextColor3 = isCardinal and (a == 0 and COL_NORTH or COL_CARDINAL) or COL_NUMBER
		label.TextXAlignment = Enum.TextXAlignment.Center
		label.Parent = root

		local tick = Instance.new("Frame")
		tick.BorderSizePixel = 0
		tick.AnchorPoint = Vector2.new(0.5, 0)
		tick.BackgroundColor3 = isCardinal and COL_CARDINAL or COL_TICK
		tick.Size = UDim2.fromOffset(isCardinal and 2 or 1, isCardinal and 12 or 7)
		tick.Position = UDim2.new(0.5, 0, 0, tickY)
		tick.Parent = root

		table.insert(marks, { angle = a, label = label, tick = tick, cardinal = isCardinal })
	end

	-- Fixed centre indicator (line + triangle). Never fades; markings scroll
	-- underneath it. Kept above the marks in Z order.
	local centerLine = Instance.new("Frame")
	centerLine.Name = "CenterLine"
	centerLine.BorderSizePixel = 0
	centerLine.BackgroundColor3 = COL_CENTER
	centerLine.AnchorPoint = Vector2.new(0.5, 0)
	centerLine.Position = UDim2.new(0.5, 0, 0, tickY - 4)
	centerLine.Size = UDim2.fromOffset(2, 18)
	centerLine.ZIndex = 3
	centerLine.Parent = root

	local triangle = Instance.new("TextLabel")
	triangle.Name = "CenterArrow"
	triangle.BackgroundTransparency = 1
	triangle.AnchorPoint = Vector2.new(0.5, 0)
	triangle.Position = UDim2.new(0.5, 0, 0, tickY + 14)
	triangle.Size = UDim2.fromOffset(16, 12)
	triangle.Font = Enum.Font.GothamBold
	triangle.Text = "▲"
	triangle.TextSize = 12
	triangle.TextColor3 = COL_CENTER
	triangle.ZIndex = 3
	triangle.Parent = root

	local display = readYaw() or 0

	local function update(dt: number)
		local target = readYaw()
		if target then
			-- Frame-rate-independent smoothing toward the true heading (no snap).
			local alpha = 1 - math.exp(-smoothing * dt)
			display = (display + shortestAngle(target, display) * alpha) % 360
		end

		for _, m in marks do
			local delta = shortestAngle(m.angle, display)
			local n = math.abs(delta) / halfSpan
			if n > 1.02 then
				-- Outside the visible arc: hide (no draw, no clip artifact).
				m.label.Visible = false
				m.tick.Visible = false
			else
				m.label.Visible = true
				m.tick.Visible = true
				local frac = 0.5 + delta / span -- delta in [-halfSpan, halfSpan] -> [0, 1]
				m.label.Position = UDim2.new(frac, 0, 0, labelY)
				m.tick.Position = UDim2.new(frac, 0, 0, tickY)

				-- Edge fade: fully opaque within fadeStart, smoothly -> invisible.
				local transparency = 0
				if n > fadeStart then
					local t = (n - fadeStart) / (1 - fadeStart)
					transparency = smoothstep(t)
				end
				m.label.TextTransparency = transparency
				m.tick.BackgroundTransparency = transparency
			end
		end
	end

	local conn = RunService.RenderStepped:Connect(update)
	update(0)

	return {
		root = root,
		setVisible = function(visible: boolean)
			root.Visible = visible
		end,
		destroy = function()
			if conn then
				conn:Disconnect()
				conn = nil :: any
			end
			root:Destroy()
		end,
	}
end

return Compass
