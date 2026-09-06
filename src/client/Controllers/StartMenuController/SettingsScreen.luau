--!strict
--[[
	StartMenuController.SettingsScreen
	----------------------------------
	Builds the SETTINGS overlay. Deliberately a structural skeleton: it lays out
	titled sections and placeholder rows so real controls (volume, sensitivity,
	FOV, keybinds…) can be dropped in later without touching the menu shell.

	build(parent, onBack) -> Frame (starts hidden). `onBack` runs when the player
	presses BACK.
]]

local Theme = require(script.Parent.Theme)

local SettingsScreen = {}

-- A single settings row: a label on the left, a value/placeholder on the right.
-- Real controls replace the value side later.
local function settingRow(parent: Instance, order: number, name: string, value: string)
	local row = Instance.new("Frame")
	row.Name = name
	row.BackgroundColor3 = Theme.Colors.Panel
	row.BackgroundTransparency = 0.4
	row.BorderSizePixel = 0
	row.Size = UDim2.new(1, 0, 0, 44)
	row.LayoutOrder = order
	row.Parent = parent
	Theme.corner(row, 3)
	Theme.stroke(row, Theme.Colors.AccentDim, 1, 0.5)

	local key = Theme.label(row, name, 15, Theme.Colors.TextWhite, Theme.FontBold)
	key.Position = UDim2.fromOffset(16, 0)
	key.Size = UDim2.new(0.6, -16, 1, 0)

	local val = Theme.label(row, value, 14, Theme.Colors.Accent, Theme.FontMono)
	val.Position = UDim2.new(0.6, 0, 0, 0)
	val.Size = UDim2.new(0.4, -16, 1, 0)
	val.TextXAlignment = Enum.TextXAlignment.Right
end

function SettingsScreen.build(parent: Instance, onBack: () -> ()): Frame
	local screen = Instance.new("Frame")
	screen.Name = "SettingsScreen"
	screen.BackgroundColor3 = Theme.Colors.Backdrop
	screen.BackgroundTransparency = 0.25
	screen.BorderSizePixel = 0
	screen.Size = UDim2.fromScale(1, 1)
	screen.Visible = false
	screen.ZIndex = 20
	screen.Parent = parent

	-- Header
	local title = Theme.label(screen, "SETTINGS", 40, Theme.Colors.TextWhite, Theme.FontTitle)
	title.Position = UDim2.fromOffset(80, 60)
	title.Size = UDim2.fromOffset(600, 48)
	title.ZIndex = 21

	local underline = Instance.new("Frame")
	underline.BorderSizePixel = 0
	underline.BackgroundColor3 = Theme.Colors.Accent
	underline.Position = UDim2.fromOffset(82, 112)
	underline.Size = UDim2.fromOffset(120, 3)
	underline.ZIndex = 21
	underline.Parent = screen

	-- Sections container (a simple scroll so it can grow).
	local list = Instance.new("ScrollingFrame")
	list.Name = "Sections"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Position = UDim2.fromOffset(80, 150)
	list.Size = UDim2.new(0, 520, 1, -260)
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.ScrollBarThickness = 4
	list.ScrollBarImageColor3 = Theme.Colors.AccentDim
	list.ZIndex = 21
	list.Parent = screen

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 10)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list

	-- Placeholder rows (basic structure; wired for real controls later).
	settingRow(list, 1, "MASTER VOLUME", "—")
	settingRow(list, 2, "MOUSE SENSITIVITY", "—")
	settingRow(list, 3, "FIELD OF VIEW", "—")
	settingRow(list, 4, "KEYBINDS", "—")

	local note = Theme.label(list, "// More settings coming soon", 13, Theme.Colors.TextDim, Theme.FontMono)
	note.Size = UDim2.new(1, 0, 0, 28)
	note.LayoutOrder = 99
	note.ZIndex = 21

	-- BACK button
	local back = Instance.new("TextButton")
	back.Name = "Back"
	back.AutoButtonColor = false
	back.BackgroundColor3 = Theme.Colors.Panel
	back.BackgroundTransparency = 0.2
	back.BorderSizePixel = 0
	back.Text = "◄  BACK"
	back.Font = Theme.FontBold
	back.TextSize = 16
	back.TextColor3 = Theme.Colors.TextWhite
	back.AnchorPoint = Vector2.new(0, 1)
	back.Position = UDim2.new(0, 80, 1, -60)
	back.Size = UDim2.fromOffset(140, 44)
	back.ZIndex = 21
	back.Parent = screen
	Theme.corner(back, 3)
	Theme.stroke(back, Theme.Colors.AccentDim, 1, 0.3)
	back.Activated:Connect(onBack)

	return screen
end

return SettingsScreen
