--!strict
--[[
	MedicalService (server-authoritative)
	-------------------------------------
	Treatment and revival. Per spec:

	  - Hold E for 5 seconds (Config.Medic.BandageUseTime / ReviveTime).
	  - The SERVER validates the whole interaction — the client only says
	    "I am holding" and "I let go".
	  - Interruption resets progress. Movement resets progress.
	  - Only a valid MEDIC may treat or revive another player. Ordinary
	    soldiers cannot heal or revive teammates — they can only use their own
	    bandage on themselves.

	Every precondition (role, distance, target still downed, treater still
	alive) is re-checked on EVERY tick through HoldTracker's validator, so a
	treatment cannot survive the situation that justified it.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Logger = require(Shared.Modules.Logger)
local Registry = require(Shared.Modules.Registry)
local Remotes = require(Shared.Remotes)
local Data = require(Shared.Data)
local HoldTracker = require(Shared.Modules.HoldTracker)

local MedicalService = {}
MedicalService.Name = "MedicalService"

local log = Logger.scope(MedicalService.Name)

function MedicalService:Init()
	self._config = Config.Medic
	self._health = Config.Health
	self._holds = HoldTracker.new()
end

-- --- helpers ----------------------------------------------------------------

local function positionOf(player: Player): Vector3?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position
	end
	return nil
end

function MedicalService:isMedic(player: Player): boolean
	local players = Registry.expect("PlayerService")
	return Data.Roles.canTreat(players:getState(player).role)
end

function MedicalService:_distance(a: Player, b: Player): number?
	local pa, pb = positionOf(a), positionOf(b)
	if not pa or not pb then
		return nil
	end
	return (pa - pb).Magnitude
end

-- --- treating others --------------------------------------------------------

--[[
	Begin treating `target`. Returns ok, reason.
	Reviving a downed player and healing a standing one are the same gesture;
	which one happens is decided by the target's state at COMPLETION.
]]
function MedicalService:beginTreat(medic: Player, target: Player): (boolean, string?)
	if medic == target then
		return false, "use an item on yourself instead"
	end

	local players = Registry.expect("PlayerService")

	-- Only a Medic may treat another player. This is the rule the spec is
	-- explicit about, so it is checked first and re-checked every tick.
	if not self:isMedic(medic) then
		return false, "only a medic can treat others"
	end
	if not players:canFight(medic) then
		return false, "you are not able to treat"
	end

	local targetState = players:getState(target)
	if targetState.health == "Dead" then
		return false, "target is dead"
	end

	local factions = Registry.get("FactionService")
	if factions and not factions:areAllies(medic, target) then
		return false, "not a teammate"
	end

	local distance = self:_distance(medic, target)
	if not distance or distance > self._config.MaxHealDistance then
		return false, "too far"
	end

	local reviving = targetState.health == "Wounded" or targetState.health == "Critical"
	local duration = reviving and self._health.ReviveTime or self._config.BandageUseTime
	local startPosition = positionOf(medic)

	self._holds:begin(medic, {
		duration = duration,
		position = startPosition,
		moveTolerance = Config.Interaction.MoveTolerance,
		getPosition = function()
			return positionOf(medic)
		end,
		-- Re-validated every tick: medic alive+medic, target still in range and
		-- still needing help. Any of these failing resets progress.
		validate = function()
			if not medic.Parent or not target.Parent then
				return false
			end
			if not self:isMedic(medic) or not players:canFight(medic) then
				return false
			end
			local state = players:getState(target)
			if state.health == "Dead" then
				return false
			end
			local d = self:_distance(medic, target)
			return d ~= nil and d <= self._config.MaxHealDistance
		end,
		onProgress = function(progress)
			self._progress:FireClient(medic, target, progress)
			self._progress:FireClient(target, target, progress)
		end,
		onCancel = function(reason)
			self._progress:FireClient(medic, target, 0)
			self._progress:FireClient(target, target, 0)
			log.info(string.format("%s treatment cancelled (%s)", medic.Name, reason))
		end,
		onComplete = function()
			self:_completeTreat(medic, target)
		end,
	})
	return true, nil
end

function MedicalService:_completeTreat(medic: Player, target: Player)
	local players = Registry.expect("PlayerService")
	local state = players:getState(target)
	local inventory = Registry.get("InventoryService")

	if state.health == "Wounded" or state.health == "Critical" then
		-- Revive costs morphine if the medic carries it, otherwise a medkit.
		local consumed = false
		if inventory then
			consumed = inventory:removeItem(target and medic or medic, "MORPHINE", 1) > 0
				or inventory:removeItem(medic, "MEDKIT", 1) > 0
		end
		if inventory and not consumed then
			self._progress:FireClient(medic, target, 0)
			return -- no supplies
		end
		players:revive(target, self._health.ReviveHealth)
		players:stopBleeding(target)

		local data = Registry.get("DataService")
		if data then
			data:incrementStat(medic, "revives")
		end
		local ranks = Registry.get("RankService")
		if ranks then
			ranks:awardXp(medic, 200) -- progression, never lethality
		end
		log.info(string.format("%s revived %s", medic.Name, target.Name))
	else
		-- Standing patient: bandage them.
		if inventory and inventory:removeItem(medic, "BANDAGE", 1) <= 0 then
			return
		end
		local bandage = Data.Items.get("BANDAGE")
		players:heal(target, self._config.HealPerBandage or (bandage and bandage.props.heal) or 25)
		players:stopBleeding(target)
	end

	self._progress:FireClient(medic, target, 1)
	self._progress:FireClient(target, target, 1)
end

-- --- self care --------------------------------------------------------------

-- Anyone may use their OWN medical items on themselves; only medics get the
-- medic-only ones (medkit/morphine).
function MedicalService:useItemOnSelf(player: Player, itemId: string): boolean
	local def = Data.Items.get(itemId)
	if not def or def.category ~= "Medical" then
		return false
	end
	local players = Registry.expect("PlayerService")
	local state = players:getState(player)
	if state.health == "Dead" then
		return false
	end
	-- A downed player cannot patch themselves up (unless configured otherwise).
	if (state.health ~= "Alive") and not Config.Combat.SelfReviveEnabled then
		return false
	end
	if def.props.medicOnly and not self:isMedic(player) then
		return false
	end

	local inventory = Registry.expect("InventoryService")
	local startPosition = positionOf(player)

	self._holds:begin(player, {
		duration = def.props.useTime or 4,
		position = startPosition,
		moveTolerance = Config.Interaction.MoveTolerance,
		getPosition = function()
			return positionOf(player)
		end,
		validate = function()
			return player.Parent ~= nil and not players:isDead(player)
		end,
		onProgress = function(progress)
			self._progress:FireClient(player, player, progress)
		end,
		onCancel = function()
			self._progress:FireClient(player, player, 0)
		end,
		onComplete = function()
			if inventory:removeItem(player, itemId, 1) <= 0 then
				return
			end
			if def.props.heal then
				players:heal(player, def.props.heal)
			end
			if def.props.stopsBleeding then
				players:stopBleeding(player)
			end
			self._progress:FireClient(player, player, 1)
		end,
	})
	return true
end

function MedicalService:cancel(player: Player)
	self._holds:cancel(player, "released")
end

-- --- lifecycle --------------------------------------------------------------

function MedicalService:Start()
	self._progress = Remotes.getEvent("Medical", "TreatmentProgress")

	Remotes.getEvent("Medical", "RequestTreat").OnServerEvent:Connect(function(player, target)
		if typeof(target) ~= "Instance" or not target:IsA("Player") then
			return
		end
		local ok, reason = self:beginTreat(player, target)
		if not ok then
			self._progress:FireClient(player, target, 0, reason)
		end
	end)

	Remotes.getEvent("Medical", "CancelTreat").OnServerEvent:Connect(function(player)
		self:cancel(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		self._holds:cancel(player, "left")
	end)

	RunService.Heartbeat:Connect(function(dt)
		self._holds:update(dt)
	end)

	log.info("online — medic-only treatment, hold-to-treat with reset rules")
end

return MedicalService
