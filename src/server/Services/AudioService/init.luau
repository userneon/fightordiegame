--!strict
--[[
	AudioService (server-authoritative event routing)
	-------------------------------------------------
	Audio EVENT ARCHITECTURE only — this service contains no sound assets and
	creates no Sound instances. It decides WHO hears WHAT and WHERE; the client
	owns playback and picks the actual asset for the event id.

	Why server-side: gunfire position is gameplay information. Sending every
	shot to every client would leak enemy positions across the map, so events
	are distributed by audible radius, and distant gunfire is sent as a
	deliberately vague "far" event with reduced positional precision.

	    audio:gunshot(player, position, weaponId)
	    audio:emit("Reload", position, { radius = 60 })
	    audio:impact(position, material)
	    audio:explosion(position, radius)

	The client listens on Remotes.Audio.PlaySpatial / PlaySound.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Logger = require(Shared.Modules.Logger)
local Remotes = require(Shared.Remotes)

local AudioService = {}
AudioService.Name = "AudioService"

local log = Logger.scope(AudioService.Name)

-- Audible radii in studs. Beyond `near` a gunshot becomes a "distant" event.
local GUNSHOT_NEAR = 220
local GUNSHOT_FAR = 1600
local DEFAULT_RADIUS = 80

export type EmitOptions = {
	radius: number?,
	exclude: Player?,
	-- Rounds the broadcast position to this many studs, so distant listeners
	-- get direction without a pinpoint enemy location.
	precision: number?,
	extra: { [string]: any }?,
}

function AudioService:Init()
	-- Nothing to construct: this service is pure routing.
end

local function quantise(position: Vector3, precision: number?): Vector3
	if not precision or precision <= 0 then
		return position
	end
	return Vector3.new(
		math.round(position.X / precision) * precision,
		math.round(position.Y / precision) * precision,
		math.round(position.Z / precision) * precision
	)
end

local function listenerPosition(player: Player): Vector3?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position
	end
	return nil
end

-- --- core emit --------------------------------------------------------------

-- Send a positional audio event to everyone within radius.
function AudioService:emit(eventId: string, position: Vector3, options: EmitOptions?)
	local opts = options or {}
	local radius = opts.radius or DEFAULT_RADIUS

	for _, player in Players:GetPlayers() do
		if player ~= opts.exclude then
			local listener = listenerPosition(player)
			if listener then
				local distance = (listener - position).Magnitude
				if distance <= radius then
					self._playSpatial:FireClient(
						player,
						eventId,
						quantise(position, opts.precision),
						distance / radius, -- 0 = on top of it, 1 = at the edge
						opts.extra
					)
				end
			end
		end
	end
end

-- Non-positional (UI, first-person mechanical sounds) for one player.
function AudioService:emitTo(player: Player, eventId: string, extra: { [string]: any }?)
	self._playSound:FireClient(player, eventId, extra)
end

function AudioService:stop(player: Player, eventId: string)
	self._stopSound:FireClient(player, eventId)
end

-- --- gameplay helpers -------------------------------------------------------

-- Gunfire: crisp nearby, vague far away (direction without a free wallhack).
function AudioService:gunshot(shooter: Player, position: Vector3, weaponId: string)
	for _, player in Players:GetPlayers() do
		local listener = listenerPosition(player)
		if listener then
			local distance = (listener - position).Magnitude
			if player == shooter then
				-- The shooter hears their own weapon in first person.
				self._playSound:FireClient(player, "Gunfire_Self", { weaponId = weaponId })
			elseif distance <= GUNSHOT_NEAR then
				self._playSpatial:FireClient(player, "Gunfire", position, distance / GUNSHOT_NEAR, {
					weaponId = weaponId,
				})
			elseif distance <= GUNSHOT_FAR then
				-- Distant: quantised so it gives a bearing, not a position.
				self._playSpatial:FireClient(
					player,
					"Gunfire_Distant",
					quantise(position, 50),
					distance / GUNSHOT_FAR,
					{ weaponId = weaponId }
				)
			end
		end
	end
end

function AudioService:reload(player: Player, weaponId: string, stage: string?)
	local position = listenerPosition(player)
	self:emitTo(player, "Reload_Self", { weaponId = weaponId, stage = stage })
	if position then
		self:emit("Reload", position, { radius = 45, exclude = player, extra = { weaponId = weaponId } })
	end
end

-- Weapon mechanical sounds: dry fire, selector switch, bolt.
function AudioService:mechanical(player: Player, eventId: string, weaponId: string?)
	self:emitTo(player, eventId, { weaponId = weaponId })
	local position = listenerPosition(player)
	if position then
		self:emit(eventId, position, { radius = 25, exclude = player })
	end
end

function AudioService:impact(position: Vector3, material: Enum.Material)
	self:emit("Impact", position, { radius = 90, extra = { material = material.Name } })
end

function AudioService:explosion(position: Vector3, radius: number?)
	self:emit("Explosion", position, { radius = (radius or 250) * 4 })
end

function AudioService:environment(eventId: string, position: Vector3, radius: number?)
	self:emit(eventId, position, { radius = radius or 150 })
end

function AudioService:Start()
	self._playSound = Remotes.getEvent("Audio", "PlaySound")
	self._playSpatial = Remotes.getEvent("Audio", "PlaySpatial")
	self._stopSound = Remotes.getEvent("Audio", "StopSound")

	log.info("online — audio event routing (no assets, distance-aware)")
end

return AudioService
