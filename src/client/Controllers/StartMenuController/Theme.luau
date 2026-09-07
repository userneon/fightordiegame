--!strict
--[[
	StartMenuController.Theme
	-------------------------
	Palette, fonts, and small procedural UI helpers shared by every menu screen
	(main menu, settings, profile). Keeping them here means the three screens read
	as one consistent, tactical/military system and there is a single place to
	retune the look.
]]

local Theme = {}

-- Palette -------------------------------------------------------------------
Theme.Colors = {
	Backdrop = Color3.fromRGB(8, 9, 7),
	Panel = Color3.fromRGB(14, 17, 12),
	Accent = Color3.fromRGB(168, 181, 69), -- olive/amber
	AccentDim = Color3.fromRGB(96, 104, 52),
	TextGray = Color3.fromRGB(146, 150, 142),
	TextDim = Color3.fromRGB(110, 114, 106),
	TextWhite = Color3.fromRGB(240, 242, 236),
	Warn = Color3.fromRGB(232, 178, 74),
}

-- Fonts ---------------------------------------------------------------------
Theme.FontTitle = Enum.Font.GothamBlack -- heavy display for the wordmark
Theme.FontBold = Enum.Font.GothamBold
Theme.FontMono = Enum.Font.Code -- tactical/mono for small readouts

-- Helpers -------------------------------------------------------------------

function Theme.corner(inst: Instance, radius: number): UICorner
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = inst
	return c
end

function Theme.stroke(inst: Instance, color: Color3, thickness: number, transparency: number?): UIStroke
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.Transparency = transparency or 0
	s.Parent = inst
	return s
end

function Theme.label(
	parent: Instance,
	text: string,
	size: number,
	color: Color3,
	font: Enum.Font?
): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Font = font or Theme.FontMono
	t.Text = text
	t.TextSize = size
	t.TextColor3 = color
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.TextYAlignment = Enum.TextYAlignment.Center
	t.Parent = parent
	return t
end

function Theme.panel(name: string, parent: Instance): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundColor3 = Theme.Colors.Panel
	f.BackgroundTransparency = 0.25
	f.BorderSizePixel = 0
	f.Parent = parent
	Theme.corner(f, 3)
	Theme.stroke(f, Theme.Colors.AccentDim, 1, 0.35)
	return f
end

-- Corner framing bracket (an L shape) anchored to one corner of `parent`.
-- ax/ay are 0 or 1 (which corner); inset in px from that corner.
function Theme.bracket(parent: Instance, ax: number, ay: number, inset: number?)
	local size = 30
	local thick = 2
	local pad = inset or 22
	local holder = Instance.new("Frame")
	holder.Name = "Bracket"
	holder.BackgroundTransparency = 1
	holder.AnchorPoint = Vector2.new(ax, ay)
	holder.Size = UDim2.fromOffset(size, size)
	holder.Position = UDim2.new(ax, ax == 0 and pad or -pad, ay, ay == 0 and pad or -pad)
	holder.Parent = parent

	local h = Instance.new("Frame")
	h.BorderSizePixel = 0
	h.BackgroundColor3 = Theme.Colors.Accent
	h.BackgroundTransparency = 0.25
	h.Size = UDim2.fromOffset(size, thick)
	h.Position = UDim2.new(0, 0, ay, ay == 0 and 0 or -thick)
	h.Parent = holder

	local v = Instance.new("Frame")
	v.BorderSizePixel = 0
	v.BackgroundColor3 = Theme.Colors.Accent
	v.BackgroundTransparency = 0.25
	v.Size = UDim2.fromOffset(thick, size)
	v.Position = UDim2.new(ax, ax == 0 and 0 or -thick, 0, 0)
	v.Parent = holder
end

return Theme
