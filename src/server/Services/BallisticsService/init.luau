--!strict
--[[
	BallisticsService (server-authoritative)
	----------------------------------------
	Reusable ballistic simulation. NO Part is ever created for a bullet — a
	round is a few numbers integrated forward and raycast segment by segment.
	That is what makes it viable at large player counts: cost is O(steps), and
	steps are bounded by Config.Ballistics.

	Per round it models:
	  - travel time (rounds are not hitscan)
	  - gravity / bullet drop
	  - air drag (velocity loss over distance)
	  - maximum range and lifetime
	  - raycast segment collision against the world YOU build
	  - material-based penetration with thickness probing
	  - damage reduction after each penetration + distance falloff

	It reports hits through a callback and owns no gameplay decisions — damage
	application belongs to DamageService.

		Ballistics:fire({
			origin = Vector3, direction = Vector3, ammoId = "5.56x45",
			shooter = player, ignore = { character }, onHit = function(hit) end,
		})
]]

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Logger = require(Shared.Modules.Logger)
local Data = require(Shared.Data)

local BallisticsService = {}
BallisticsService.Name = "BallisticsService"

local log = Logger.scope(BallisticsService.Name)

export type Shot = {
	origin: Vector3,
	direction: Vector3,
	ammoId: string,
	shooter: Player?,
	ignore: { Instance }?,
	damageScale: number?,
	onHit: ((hit: HitReport) -> boolean?)?,
}

export type HitReport = {
	position: Vector3,
	normal: Vector3,
	instance: BasePart,
	material: Enum.Material,
	distance: number,
	velocity: Vector3,
	damage: number,
	penetrations: number,
	shooter: Player?,
	ammoId: string,
}

type Round = {
	position: Vector3,
	velocity: Vector3,
	travelled: number,
	elapsed: number,
	steps: number,
	penetrations: number,
	damage: number,
	ammo: any,
	shot: Shot,
	params: RaycastParams,
}

function BallisticsService:Init()
	self._config = Config.Ballistics
	self._rounds = {} :: { Round }
end

-- --- helpers ----------------------------------------------------------------

function BallisticsService:_makeParams(shot: Shot): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local filter: { Instance } = {}
	if shot.ignore then
		for _, inst in shot.ignore do
			table.insert(filter, inst)
		end
	end
	-- A shooter never hits their own body.
	if shot.shooter and shot.shooter.Character then
		table.insert(filter, shot.shooter.Character)
	end
	params.FilterDescendantsInstances = filter
	params.IgnoreWater = true
	return params
end

-- Distance-based damage falloff from the calibre's near/far envelope.
function BallisticsService:_falloff(ammo: any, distance: number): number
	if distance <= ammo.nearRange then
		return 1
	end
	if distance >= ammo.farRange then
		return ammo.farMultiplier
	end
	local t = (distance - ammo.nearRange) / math.max(1, ammo.farRange - ammo.nearRange)
	return 1 + (ammo.farMultiplier - 1) * t
end

-- Measure how thick the obstacle is by probing from the far side backwards.
-- Returns thickness in studs, or nil when the round cannot get through.
function BallisticsService:_measureThickness(
	entry: Vector3,
	direction: Vector3,
	instance: BasePart,
	maxThickness: number
): number?
	local probeParams = RaycastParams.new()
	probeParams.FilterType = Enum.RaycastFilterType.Include
	probeParams.FilterDescendantsInstances = { instance }

	-- Cast back toward the entry point from just past the maximum thickness.
	local far = entry + direction * (maxThickness + 0.1)
	local back = Workspace:Raycast(far, -direction * (maxThickness + 0.2), probeParams)
	if not back then
		return nil -- thicker than we are willing to punch through
	end
	return (back.Position - entry).Magnitude
end

-- --- simulation -------------------------------------------------------------

function BallisticsService:fire(shot: Shot): boolean
	local ammo = Data.Ammo.get(shot.ammoId)
	if not ammo then
		log.warn("unknown ammo:", tostring(shot.ammoId))
		return false
	end
	local direction = shot.direction
	if direction.Magnitude < 1e-4 then
		return false
	end
	direction = direction.Unit

	table.insert(self._rounds, {
		position = shot.origin,
		velocity = direction * ammo.muzzleVelocity,
		travelled = 0,
		elapsed = 0,
		steps = 0,
		penetrations = 0,
		damage = ammo.baseDamage * (shot.damageScale or 1),
		ammo = ammo,
		shot = shot,
		params = self:_makeParams(shot),
	})
	return true
end

-- Advance one round; returns false when it should be retired.
function BallisticsService:_stepRound(round: Round, dt: number): boolean
	local cfg = self._config
	local ammo = round.ammo

	round.steps += 1
	round.elapsed += dt
	if round.steps > cfg.MaxSteps or round.elapsed > cfg.MaxLifetime then
		return false
	end
	if round.travelled > ammo.maxRange then
		return false
	end

	-- Integrate: drag then gravity.
	local velocity = round.velocity * (1 - ammo.drag * dt)
	velocity -= Vector3.new(0, ammo.gravity * dt, 0)

	local segment = velocity * dt
	local result = Workspace:Raycast(round.position, segment, round.params)

	if not result then
		round.position += segment
		round.velocity = velocity
		round.travelled += segment.Magnitude
		return true
	end

	local hitDistance = (result.Position - round.position).Magnitude
	round.travelled += hitDistance

	local damage = round.damage * self:_falloff(ammo, round.travelled)

	local report: HitReport = {
		position = result.Position,
		normal = result.Normal,
		instance = result.Instance,
		material = result.Material,
		distance = round.travelled,
		velocity = velocity,
		damage = damage,
		penetrations = round.penetrations,
		shooter = round.shot.shooter,
		ammoId = ammo.id,
	}

	-- The consumer decides whether the round stops (a body stops it; a wall
	-- may not). Returning true means "absorbed".
	local absorbed = false
	if round.shot.onHit then
		local ok, res = pcall(round.shot.onHit, report)
		if ok then
			absorbed = res == true
		else
			log.error("onHit callback errored:", tostring(res))
		end
	end
	if absorbed then
		return false
	end

	-- Penetration.
	if round.penetrations >= cfg.MaxPenetrations then
		return false
	end
	local material = Data.Materials.get(result.Material)
	local thickness = self:_measureThickness(result.Position, velocity.Unit, result.Instance, material.maxThickness)
	if not thickness then
		return false
	end

	-- Penetration power is spent against resistance * thickness.
	local cost = material.resistance * thickness
	local power = ammo.penetration * (1 - round.penetrations * 0.25)
	if cost > power then
		return false -- stopped by the wall
	end

	round.penetrations += 1
	round.damage = damage * (1 - material.damageLoss)
	-- Exit just past the far face and continue, slightly slowed.
	round.position = result.Position + velocity.Unit * (thickness + 0.05)
	round.velocity = velocity * (1 - material.damageLoss * 0.5)
	return round.damage > 1
end

function BallisticsService:Start()
	local cfg = self._config
	local accumulator = 0

	-- Fixed-step integration keeps trajectories identical regardless of server
	-- frame rate — important for consistent drop at long range.
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < cfg.StepTime then
			return
		end
		local step = cfg.StepTime
		accumulator -= step

		local rounds = self._rounds
		for i = #rounds, 1, -1 do
			local alive = true
			local ok, err = pcall(function()
				alive = self:_stepRound(rounds[i], step)
			end)
			if not ok then
				log.error("round step failed:", tostring(err))
				alive = false
			end
			if not alive then
				local last = #rounds
				rounds[i] = rounds[last]
				rounds[last] = nil
			end
		end
	end)

	log.info("online — simulated ballistics (no per-bullet Parts)")
end

-- Diagnostics: how many rounds are in flight right now.
function BallisticsService:activeCount(): number
	return #self._rounds
end

return BallisticsService
