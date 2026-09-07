--!strict
--[[
	AntiCheatService (server-authoritative)
	---------------------------------------
	Central validation + enforcement. Other services call :report() when
	something looks wrong; this service decides what it means over time.

	Philosophy: a single anomaly is NEVER proof. Roblox clients legitimately
	rubber-band, spike and desync — so one bad sample is noise. Only a sustained
	pattern (Config.AntiCheat.StrikesBefore*) escalates, and every escalation
	records evidence.

	Escalation ladder:
	    strikes >= StrikesBeforeFlag  → flagged (logged, client notified)
	    strikes >= StrikesBeforeLock  → input/movement lock
	    strikes >= StrikesBeforeBan   → ban state recorded (+ kick if enabled)

	It actively checks movement itself (speed / vertical / teleport) and accepts
	reports from WeaponService (fire rate, shot origin) and others.

	Everything authoritative already lives server-side — this is the safety net,
	not the primary defence.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Logger = require(Shared.Modules.Logger)
local Registry = require(Shared.Modules.Registry)
local Remotes = require(Shared.Remotes)

local AntiCheatService = {}
AntiCheatService.Name = "AntiCheatService"

local log = Logger.scope(AntiCheatService.Name)

type Record = {
	strikes: number,
	evidence: { string },
	lastPosition: Vector3?,
	lastCheck: number,
	locked: boolean,
	banned: boolean,
}

function AntiCheatService:Init()
	self._config = Config.AntiCheat
	self._records = {} :: { [Player]: Record }
	self._accumulator = 0
end

function AntiCheatService:_record(player: Player): Record
	local rec = self._records[player]
	if not rec then
		rec = { strikes = 0, evidence = {}, lastPosition = nil, lastCheck = 0, locked = false, banned = false }
		self._records[player] = rec
	end
	return rec
end

-- --- reporting --------------------------------------------------------------

--[[
	Report a suspicious observation. `weight` lets a service say how serious it
	is (default 1). Evidence is kept for review — we never ban without a reason
	string attached.
]]
function AntiCheatService:report(player: Player, category: string, detail: string?, weight: number?)
	local rec = self:_record(player)
	rec.strikes += (weight or 1)
	table.insert(rec.evidence, string.format("[%s] %s: %s", os.date("%X"), category, detail or ""))
	-- Keep the evidence buffer bounded.
	if #rec.evidence > 40 then
		table.remove(rec.evidence, 1)
	end
	self:_evaluate(player, rec)
end

-- Decay strikes slowly so an honest player with a bad connection recovers.
function AntiCheatService:_decay(rec: Record)
	if rec.strikes > 0 and not rec.banned then
		rec.strikes = math.max(0, rec.strikes - 0.25)
	end
end

function AntiCheatService:_evaluate(player: Player, rec: Record)
	local cfg = self._config

	if rec.strikes >= cfg.StrikesBeforeBan and not rec.banned then
		rec.banned = true
		log.error(string.format("BAN %s — evidence:\n%s", player.Name, table.concat(rec.evidence, "\n")))
		self:lock(player, true)
		if cfg.KickAfterBan then
			-- Kick only after the ban state is recorded, per spec.
			player:Kick("Removed for confirmed exploit activity.")
		end
		return
	end

	if rec.strikes >= cfg.StrikesBeforeLock and not rec.locked then
		self:lock(player, true)
		log.warn(string.format("LOCK %s (strikes %.1f)", player.Name, rec.strikes))
		return
	end

	if rec.strikes >= cfg.StrikesBeforeFlag then
		if self._flagged then
			self._flagged:FireClient(player)
		end
	end
end

-- --- enforcement ------------------------------------------------------------

function AntiCheatService:lock(player: Player, locked: boolean)
	local rec = self:_record(player)
	rec.locked = locked
	player:SetAttribute("InputLocked", locked)

	-- Freeze the character server-side; MovementService respects this too.
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = locked and 0 or 16
		humanoid.JumpPower = locked and 0 or 50
	end
	if self._inputLock then
		self._inputLock:FireClient(player, locked)
	end
end

function AntiCheatService:isLocked(player: Player): boolean
	return self:_record(player).locked
end

function AntiCheatService:isBanned(player: Player): boolean
	return self:_record(player).banned
end

function AntiCheatService:getEvidence(player: Player): { string }
	return self:_record(player).evidence
end

-- --- movement validation ----------------------------------------------------

function AntiCheatService:_checkMovement(player: Player, dt: number)
	local rec = self:_record(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not root:IsA("BasePart") or not humanoid then
		rec.lastPosition = nil
		return
	end

	-- Never judge a player who is not actually in play.
	local players = Registry.get("PlayerService")
	if players and not players:getState(player).deployed then
		rec.lastPosition = root.Position
		return
	end

	local position = root.Position
	local previous = rec.lastPosition
	rec.lastPosition = position
	if not previous or dt <= 0 then
		return
	end

	local delta = position - previous
	local horizontal = Vector3.new(delta.X, 0, delta.Z).Magnitude
	local speed = horizontal / dt

	-- Teleport: a jump far larger than any legitimate movement.
	if horizontal > self._config.MaxTeleportDistance then
		self:report(player, "Teleport", string.format("%.0f studs in %.2fs", horizontal, dt))
		return
	end

	-- Speed: compare against the humanoid's own authorised WalkSpeed, which
	-- MovementService set — generous multiplier absorbs latency and slopes.
	local allowed = math.max(humanoid.WalkSpeed, 1) * self._config.MaxSpeedMultiplier + 8
	if speed > allowed then
		self:report(player, "Speed", string.format("%.1f > %.1f studs/s", speed, allowed), 0.5)
	end

	-- Vertical: flying / launch detection (falling fast is legitimate).
	local vertical = delta.Y / dt
	if vertical > self._config.MaxVerticalSpeed then
		self:report(player, "Vertical", string.format("%.1f studs/s upward", vertical), 0.5)
	end

	self:_decay(rec)
end

-- --- lifecycle --------------------------------------------------------------

function AntiCheatService:Start()
	self._flagged = Remotes.getEvent("AntiCheat", "Flagged")
	self._inputLock = Remotes.getEvent("AntiCheat", "InputLock")

	Players.PlayerRemoving:Connect(function(player)
		self._records[player] = nil
	end)

	RunService.Heartbeat:Connect(function(dt)
		self._accumulator += dt
		if self._accumulator < self._config.CheckInterval then
			return
		end
		local step = self._accumulator
		self._accumulator = 0
		for _, player in Players:GetPlayers() do
			local ok, err = pcall(function()
				self:_checkMovement(player, step)
			end)
			if not ok then
				log.error("movement check failed:", tostring(err))
			end
		end
	end)

	log.info("online — movement/fire validation with graduated enforcement")
end

return AntiCheatService
