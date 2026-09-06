--!strict
--[[
	StartMenuController.ProfileScreen
	---------------------------------
	Builds the PROFILE overlay opened by clicking the bottom-left player info.
	Shows the player's real avatar and identity plus a skeleton stat block that
	can be filled from real progression data later.

	build(parent, onBack) -> {
		frame   : Frame,          -- starts hidden
		avatar  : ImageLabel,     -- caller sets .Image to the fetched thumbnail
		refresh : (data) -> (),   -- update name / rank / team / stats
	}
]]

local Theme = require(script.Parent.Theme)

export type ProfileData = {
	name: string,
	rank: string,
	team: string,
}

local ProfileScreen = {}

local function statTile(parent: Instance, order: number, tag: string): TextLabel
	local tile = Instance.new("Frame")
	tile.Name = tag
	tile.BackgroundColor3 = Theme.Colors.Panel
	tile.BackgroundTransparency = 0.4
	tile.BorderSizePixel = 0
	tile.Size = UDim2.fromOffset(150, 70)
	tile.LayoutOrder = order
	tile.ZIndex = 21
	tile.Parent = parent
	Theme.corner(tile, 3)
	Theme.stroke(tile, Theme.Colors.AccentDim, 1, 0.5)

	local tagLabel = Theme.label(tile, tag, 12, Theme.Colors.Accent, Theme.FontMono)
	tagLabel.Position = UDim2.fromOffset(12, 10)
	tagLabel.Size = UDim2.new(1, -24, 0, 16)
	tagLabel.ZIndex = 22

	local value = Theme.label(tile, "0", 26, Theme.Colors.TextWhite, Theme.FontBold)
	value.Name = "Value"
	value.Position = UDim2.fromOffset(12, 28)
	value.Size = UDim2.new(1, -24, 0, 34)
	value.ZIndex = 22
	return value
end

function ProfileScreen.build(parent: Instance, onBack: () -> ())
	local screen = Instance.new("Frame")
	screen.Name = "ProfileScreen"
	screen.BackgroundColor3 = Theme.Colors.Backdrop
	screen.BackgroundTransparency = 0.2
	screen.BorderSizePixel = 0
	screen.Size = UDim2.fromScale(1, 1)
	screen.Visible = false
	screen.ZIndex = 20
	screen.Parent = parent

	local title = Theme.label(screen, "PROFILE", 40, Theme.Colors.TextWhite, Theme.FontTitle)
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

	-- Identity card: large avatar + name / rank / team
	local card = Theme.panel("Identity", screen)
	card.BackgroundTransparency = 0.35
	card.Position = UDim2.fromOffset(80, 150)
	card.Size = UDim2.fromOffset(520, 150)
	card.ZIndex = 21

	local avatar = Instance.new("ImageLabel")
	avatar.Name = "Avatar"
	avatar.BackgroundColor3 = Color3.fromRGB(6, 7, 5)
	avatar.BorderSizePixel = 0
	avatar.Position = UDim2.fromOffset(16, 16)
	avatar.Size = UDim2.fromOffset(118, 118)
	avatar.ScaleType = Enum.ScaleType.Fit
	avatar.ZIndex = 22
	avatar.Parent = card
	Theme.corner(avatar, 3)
	Theme.stroke(avatar, Theme.Colors.Accent, 1, 0.2)

	local nameLbl = Theme.label(card, "", 26, Theme.Colors.TextWhite, Theme.FontBold)
	nameLbl.Position = UDim2.fromOffset(150, 20)
	nameLbl.Size = UDim2.new(1, -166, 0, 30)
	nameLbl.ZIndex = 22

	local rankLbl = Theme.label(card, "", 15, Theme.Colors.Accent, Theme.FontMono)
	rankLbl.Position = UDim2.fromOffset(150, 60)
	rankLbl.Size = UDim2.new(1, -166, 0, 20)
	rankLbl.ZIndex = 22

	local teamLbl = Theme.label(card, "", 15, Theme.Colors.TextGray, Theme.FontMono)
	teamLbl.Position = UDim2.fromOffset(150, 86)
	teamLbl.Size = UDim2.new(1, -166, 0, 20)
	teamLbl.ZIndex = 22

	-- Stat skeleton (expand with real progression later).
	local stats = Instance.new("Frame")
	stats.Name = "Stats"
	stats.BackgroundTransparency = 1
	stats.Position = UDim2.fromOffset(80, 320)
	stats.Size = UDim2.fromOffset(520, 70)
	stats.ZIndex = 21
	stats.Parent = screen

	local statLayout = Instance.new("UIListLayout")
	statLayout.FillDirection = Enum.FillDirection.Horizontal
	statLayout.Padding = UDim.new(0, 12)
	statLayout.SortOrder = Enum.SortOrder.LayoutOrder
	statLayout.Parent = stats

	statTile(stats, 1, "MISSIONS")
	statTile(stats, 2, "ELIMS")
	statTile(stats, 3, "REVIVES")

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

	local function refresh(data: ProfileData)
		nameLbl.Text = string.upper(data.name)
		rankLbl.Text = "RANK  //  " .. string.upper(data.rank)
		teamLbl.Text = "TEAM  //  " .. string.upper(data.team)
	end

	return {
		frame = screen,
		avatar = avatar,
		refresh = refresh,
	}
end

return ProfileScreen
