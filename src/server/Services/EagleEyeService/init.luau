--!strict
--[[
	EagleEyeService (server-authoritative)
	--------------------------------------
	Army-only aerial reconnaissance.

	Rules (per spec), all enforced on the server:
	  - One use every 10 minutes (Config.EagleEye.Cooldown), tracked per player.
	  - Army faction only, and rank-gated (UseEagleEye permission).
	  - Friendly positions are always shared.
	  - Enemy positions are sent ONLY when legitimately detected:
	      * within EnemyRevealRadius of the requesting player, AND
	      * visible from the sky — a raycast straight down from high above must
	        reach them. Anyone under a roof is NOT revealed.
	  - THE SERVER DECIDES WHAT THE CLIENT RECEIVES. Undetected enemies are
	    never sent at all, so there is nothing for a modified client to read.
	    This is what makes it recon rather than a wallhack.

	Creates no map, no aerial environment and no camera — it emits data; the
	client renders the tactical view.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Logger = require(Shared.Modules.Logger)
local Registry = require(Shared.Modules.Registry)
local Remotes = require(Shared.Remotes)
local Data = require(Shared.Data)

local EagleEyeService = {}
EagleEyeService.Name = "EagleEyeService"

local log = Logger.scope(EagleEyeService.Name)

local SKY_HEIGHT = 800 -- studs above a target for the occlusion probe

function EagleEyeService:Init()
	self._config = Config.EagleEye
	self._lastUse = {} :: { [Player]: number }
	self._active = {} :: { [Player]: number } -- player -> expiry time
end

-- --- availability -----------------------------------------------------------

function EagleEyeService:cooldownRemaining(player: Player): number
	local last = self._lastUse[player]
	if not last then
		return 0
	end
	return math.max(0, self._config.Cooldown - (os.clock() - last))
end

function EagleEyeService:canUse(player: Player): (boolean, string?)
	local players = Registry.expect("PlayerService")
	local state = players:getState(player)

	if not state.deployed or state.health ~= "Alive" then
		return false, "unavailable"
	end

	-- Faction gate: Army-only ability (data-driven).
	local factions = Registry.expect("FactionService")
	if not factions:hasAbility(player, "EagleEye") then
		return false, "not available to your faction"
	end

	-- Rank gate.
	local ranks = Registry.get("RankService")
	if ranks and not ranks:can(player, Data.Ranks.Permissions.UseEagleEye) then
		return false, "insufficient rank"
	end

	local remaining = self:cooldownRemaining(player)
	if remaining > 0 then
		return false, string.format("on cooldown (%ds)", math.ceil(remaining))
	end
	return true, nil
end

-- --- detection --------------------------------------------------------------

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

--[[
	Is this target visible from directly overhead? A raycast from high above
	straight down must reach them — anything solid in between (a roof, a floor
	above, a tunnel) means they are indoors and stay hidden.
]]
function EagleEyeService:_visibleFromSky(target: BasePart, character: Model): boolean
	if not self._config.SkyOcclusionCheck then
		return true
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	params.IgnoreWater = true

	local origin = target.Position + Vector3.new(0, SKY_HEIGHT, 0)
	local result = Workspace:Raycast(origin, Vector3.new(0, -SKY_HEIGHT - 5, 0), params)
	-- Nothing in the way at all => open sky above them.
	if not result then
		return true
	end
	-- If the first thing we hit is essentially at their own height, they are
	-- standing in the open (we hit the ground beside/under them).
	return result.Position.Y <= target.Position.Y + 3
end

-- Build the payload THIS player is allowed to see.
function EagleEyeService:_buildReport(player: Player)
	local players = Registry.expect("PlayerService")
	local factions = Registry.expect("FactionService")

	local observer = rootOf(player)
	if not observer then
		return nil
	end
	local observerPosition = observer.Position

	local friendlies = {}
	local enemies = {}

	for _, other in Players:GetPlayers() do
		if other ~= player then
			local state = players:getState(other)
			local root = rootOf(other)
			if root and state.deployed and state.health ~= "Dead" then
				if factions:areAllies(player, other) then
					-- Friendlies are always shared.
					table.insert(friendlies, {
						userId = other.UserId,
						name = other.Name,
						position = root.Position,
						health = state.health,
					})
				elseif factions:areEnemies(player, other) then
					local distance = (root.Position - observerPosition).Magnitude
					if distance <= self._config.EnemyRevealRadius then
						local character = other.Character
						if character and self:_visibleFromSky(root, character) then
							-- Only detected enemies are ever put in the packet.
							table.insert(enemies, {
								position = root.Position,
								-- Deliberately no name/userId: a contact, not a
								-- character-accurate readout.
								faction = state.faction,
							})
						end
					end
				end
			end
		end
	end

	return { friendlies = friendlies, enemies = enemies, at = os.clock() }
end

-- --- activation -------------------------------------------------------------

function EagleEyeService:activate(player: Player): (boolean, string?)
	local ok, reason = self:canUse(player)
	if not ok then
		self._stateEvent:FireClient(player, false, reason, self:cooldownRemaining(player))
		return false, reason
	end

	self._lastUse[player] = os.clock()
	local expiry = os.clock() + self._config.Duration
	self._active[player] = expiry
	self._stateEvent:FireClient(player, true, nil, self._config.Cooldown)
	log.info(string.format("%s activated Eagle Eye", player.Name))

	task.spawn(function()
		while self._active[player] and os.clock() < (self._active[player] :: number) do
			-- Re-validate each refresh: dying or being downed ends it early.
			local players = Registry.expect("PlayerService")
			local state = players:getState(player)
			if not player.Parent or state.health ~= "Alive" then
				break
			end
			local report = self:_buildReport(player)
			if report then
				self._dataEvent:FireClient(player, report)
			end
			task.wait(self._config.RefreshInterval)
		end
		self._active[player] = nil
		if player.Parent then
			self._stateEvent:FireClient(player, false, nil, self:cooldownRemaining(player))
		end
	end)

	return true, nil
end

function EagleEyeService:isActive(player: Player): boolean
	return self._active[player] ~= nil
end

function EagleEyeService:Start()
	self._dataEvent = Remotes.getEvent("EagleEye", "EagleEyeData")
	self._stateEvent = Remotes.getEvent("EagleEye", "EagleEyeState")

	Remotes.getEvent("EagleEye", "RequestEagleEye").OnServerEvent:Connect(function(player)
		self:activate(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		self._lastUse[player] = nil
		self._active[player] = nil
	end)

	log.info("online — Army recon, 10min cooldown, detection-gated (no wallhack)")
end

return EagleEyeService
