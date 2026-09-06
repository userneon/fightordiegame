--!strict
--[[
	CameraController.FirstPersonBody
	--------------------------------
	First-person body awareness. In first person Roblox forces the character's
	parts transparent (you normally see only tool arms), which hides the body,
	hand, weapon, and interaction animations we want visible. This module keeps
	the local body rendered by clamping LocalTransparencyModifier every frame,
	AFTER the camera has applied its own transparency (so it wins).

	Only the head (and hat / hair / face accessories) are hidden, so the camera
	isn't sitting inside the head mesh. Torso, arms, and legs stay visible.

	It is purely local and cosmetic — LocalTransparencyModifier never replicates.

	start(player, hideHead) -> { stop: () -> () }
]]

local RunService = game:GetService("RunService")

local FirstPersonBody = {}

local RENDER_BINDING = "FOD_FirstPersonBody"

-- Accessory types worn on the head — hidden so they don't block the view.
local HIDE_ACCESSORY = {
	[Enum.AccessoryType.Hat] = true,
	[Enum.AccessoryType.Hair] = true,
	[Enum.AccessoryType.Face] = true,
}

local function shouldHide(part: BasePart, head: BasePart?, hideHead: boolean): boolean
	if not hideHead then
		return false
	end
	if head and part == head then
		return true
	end
	local accessory = part:FindFirstAncestorOfClass("Accessory")
	if accessory and HIDE_ACCESSORY[accessory.AccessoryType] then
		return true
	end
	return false
end

function FirstPersonBody.start(player: Player, hideHead: boolean)
	local state: { character: Model?, head: BasePart? } = { character = nil, head = nil }

	local function bind(character: Model)
		state.character = character
		state.head = character:FindFirstChild("Head") :: BasePart?
	end

	if player.Character then
		bind(player.Character)
	end
	local charConn = player.CharacterAdded:Connect(bind)

	-- Run at Character priority so it applies after the Camera step each frame.
	RunService:BindToRenderStep(RENDER_BINDING, Enum.RenderPriority.Character.Value, function()
		local character = state.character
		if not character or character.Parent == nil then
			return
		end
		-- Head can arrive a frame after the character; resolve it lazily.
		if not state.head then
			state.head = character:FindFirstChild("Head") :: BasePart?
		end
		for _, d in character:GetDescendants() do
			if d:IsA("BasePart") then
				d.LocalTransparencyModifier = shouldHide(d, state.head, hideHead) and 1 or 0
			end
		end
	end)

	local function stop()
		charConn:Disconnect()
		pcall(function()
			RunService:UnbindFromRenderStep(RENDER_BINDING)
		end)
		-- Restore default transparency handling.
		local character = state.character
		if character then
			for _, d in character:GetDescendants() do
				if d:IsA("BasePart") then
					d.LocalTransparencyModifier = 0
				end
			end
		end
	end

	return { stop = stop }
end

return FirstPersonBody
