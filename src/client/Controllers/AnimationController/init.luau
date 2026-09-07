--!strict
--[[
	AnimationController (client)
	----------------------------
	Local, feel-only character animation. It never decides gameplay — it reads
	authoritative state that the server replicates as Player attributes and plays
	the matching animation on the LocalPlayer's own Humanoid.

	Heavy Walk
	----------
	MovementSystem (server) sets the "HeavyWalk" attribute true when carried
	weight passes Config.Movement.HeavyWalkThreshold. This controller plays a
	slower, laboured stride while HeavyWalk is set AND the character is actually
	moving, and blends back out otherwise. The animation plays at Movement
	priority so it overrides Roblox's default Core-priority walk/run.

	The stride's authored walk speed is Config.Animation.HeavyWalkReferenceSpeed;
	playback speed is scaled by the Humanoid's real WalkSpeed so the feet keep
	pace as the weight penalty bites (and stay planted, not sliding).

	Dormant-until-authored: the Animation asset itself is built by the NOMAD BROS
	team, not this repo. With no Config.Animation.HeavyWalkAnimationId set the
	controller simply idles (logs once) instead of erroring — the same "wired but
	waiting for content" posture as the HUD ammo panel and NvgController.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Logger = require(Shared.Modules.Logger)

local AnimationController = {}
AnimationController.Name = "AnimationController"

local log = Logger.scope(AnimationController.Name)

function AnimationController:Init()
	self._config = Config.Animation
	self._player = Players.LocalPlayer
	self._humanoid = nil :: Humanoid?
	self._heavyTrack = nil :: AnimationTrack?
end

-- --- character binding ------------------------------------------------------

-- Roblox's default Animate script creates the Animator; wait for it, but create
-- one if the character was set up without it so we never silently no-op.
function AnimationController:_getAnimator(humanoid: Humanoid): Animator
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = humanoid:WaitForChild("Animator", 5)
	end
	if not animator then
		local created = Instance.new("Animator")
		created.Parent = humanoid
		animator = created
	end
	return animator :: Animator
end

function AnimationController:_loadHeavyTrack(humanoid: Humanoid): AnimationTrack?
	local cfg = self._config
	if cfg.HeavyWalkAnimationId == "" then
		return nil
	end

	local animation = Instance.new("Animation")
	animation.Name = "HeavyWalk"
	animation.AnimationId = cfg.HeavyWalkAnimationId

	local animator = self:_getAnimator(humanoid)
	local ok, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	if not ok or not track then
		log.error("failed to load HeavyWalk animation:", tostring(track))
		return nil
	end

	track.Priority = cfg.HeavyWalkPriority
	track.Looped = true
	return track
end

function AnimationController:_onCharacter(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if not humanoid then
		return
	end

	self._humanoid = humanoid
	self._heavyTrack = self:_loadHeavyTrack(humanoid)

	humanoid.Died:Connect(function()
		local track = self._heavyTrack
		if track and track.IsPlaying then
			track:Stop(0)
		end
	end)
end

-- --- per-frame heavy-walk resolution ---------------------------------------

function AnimationController:_update()
	local track = self._heavyTrack
	local humanoid = self._humanoid
	if not track or not humanoid or humanoid.Parent == nil then
		return
	end

	local cfg = self._config
	local heavy = self._player:GetAttribute("HeavyWalk") == true
	local moving = humanoid.MoveDirection.Magnitude > cfg.MoveThreshold
	local alive = humanoid.Health > 0
	local shouldPlay = heavy and moving and alive

	if shouldPlay then
		if not track.IsPlaying then
			track:Play(cfg.HeavyWalkFadeIn)
		end
		-- Keep the stride in step with the (weight-penalised) walk speed.
		local ratio = humanoid.WalkSpeed / cfg.HeavyWalkReferenceSpeed
		ratio = math.clamp(ratio, cfg.MinPlaybackSpeed, cfg.MaxPlaybackSpeed)
		track:AdjustSpeed(ratio)
	elseif track.IsPlaying then
		track:Stop(cfg.HeavyWalkFadeOut)
	end
end

-- --- lifecycle -------------------------------------------------------------

function AnimationController:Start()
	if self._config.HeavyWalkAnimationId == "" then
		log.info("ready (dormant — set Config.Animation.HeavyWalkAnimationId to enable Heavy Walk)")
		return
	end

	local player = self._player
	if player.Character then
		self:_onCharacter(player.Character)
	end
	player.CharacterAdded:Connect(function(character)
		self:_onCharacter(character)
	end)

	RunService.RenderStepped:Connect(function()
		self:_update()
	end)

	log.info("online — Heavy Walk stride bound to HeavyWalk attribute")
end

return AnimationController
