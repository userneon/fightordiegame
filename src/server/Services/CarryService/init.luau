--!strict
--[[
	CarryService (server-authoritative)
	-----------------------------------
	Carrying downed teammates off the X.

	Rules enforced here:
	  - Only a DOWNED (Wounded/Critical) teammate can be picked up.
	  - The carrier must be alive, deployed, close enough, and not already
	    carrying someone.
	  - The carrier is slowed (Config.Carry.CarrySpeedMultiplier) via
	    MovementService's multiplier hook — never by fighting over WalkSpeed.
	  - The carried player cannot fight (PlayerService already blocks that while
	    downed) and is welded to the carrier server-side, so no client can
	    fabricate a position.
	  - Anything that invalidates the carry (death, revive, disconnect,
	    distance) drops them immediately.

	The weld is the ONLY thing that moves the carried character — a client
	cannot teleport anyone by claiming to carry them.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Logger = require(Shared.Modules.Logger)
local Registry = require(Shared.Modules.Registry)
local Remotes = require(Shared.Remotes)

local CarryService = {}
CarryService.Name = "CarryService"

local log = Logger.scope(CarryService.Name)

local CARRY_OFFSET = CFrame.new(0, 1.5, -1.5) * CFrame.Angles(0, math.rad(180), 0)

function CarryService:Init()
	self._config = Config.Carry
	self._carrying = {} :: { [Player]: Player } -- carrier -> carried
	self._carriedBy = {} :: { [Player]: Player } -- carried -> carrier
	self._welds = {} :: { [Player]: WeldConstraint | Weld }
	self._accumulator = 0
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

-- --- queries ----------------------------------------------------------------

function CarryService:isCarrying(player: Player): boolean
	return self._carrying[player] ~= nil
end

function CarryService:isBeingCarried(player: Player): boolean
	return self._carriedBy[player] ~= nil
end

function CarryService:getCarrier(player: Player): Player?
	return self._carriedBy[player]
end

-- --- start / stop -----------------------------------------------------------

function CarryService:startCarry(carrier: Player, target: Player): (boolean, string?)
	if carrier == target then
		return false, "cannot carry yourself"
	end
	if self._carrying[carrier] then
		return false, "already carrying"
	end
	if self._carriedBy[target] then
		return false, "already being carried"
	end

	local players = Registry.expect("PlayerService")

	if not players:canFight(carrier) then
		return false, "you cannot carry right now"
	end
	if self._carriedBy[carrier] then
		return false, "you are being carried"
	end
	-- Only downed players may be carried.
	if not players:isDowned(target) then
		return false, "target is not downed"
	end
	if not self._config.CanCarryWhileWounded and players:isDowned(carrier) then
		return false, "you are wounded"
	end

	local factions = Registry.get("FactionService")
	if factions and not factions:areAllies(carrier, target) then
		return false, "not a teammate"
	end

	local carrierRoot, targetRoot = rootOf(carrier), rootOf(target)
	if not carrierRoot or not targetRoot then
		return false, "no character"
	end
	if (carrierRoot.Position - targetRoot.Position).Magnitude > self._config.MaxCarryDistance then
		return false, "too far"
	end

	-- Attach: server-side weld is the single source of truth for position.
	targetRoot.CFrame = carrierRoot.CFrame * CARRY_OFFSET
	local weld = Instance.new("Weld")
	weld.Name = "FOD_Carry"
	weld.Part0 = carrierRoot
	weld.Part1 = targetRoot
	weld.C0 = CARRY_OFFSET
	weld.Parent = carrierRoot

	self._carrying[carrier] = target
	self._carriedBy[target] = carrier
	self._welds[target] = weld

	-- Slow the carrier through the sanctioned hook.
	local movement = Registry.get("MovementService")
	if movement then
		movement:setSpeedMultiplier(carrier, self._config.CarrySpeedMultiplier)
	end

	carrier:SetAttribute("Carrying", target.Name)
	target:SetAttribute("CarriedBy", carrier.Name)
	self._stateChanged:FireAllClients(carrier, target, true)
	log.info(string.format("%s is carrying %s", carrier.Name, target.Name))
	return true, nil
end

function CarryService:stopCarry(carrier: Player, reason: string?)
	local target = self._carrying[carrier]
	if not target then
		return
	end

	local weld = self._welds[target]
	if weld then
		weld:Destroy()
	end
	self._welds[target] = nil
	self._carrying[carrier] = nil
	self._carriedBy[target] = nil

	local movement = Registry.get("MovementService")
	if movement then
		movement:setSpeedMultiplier(carrier, 1)
	end

	carrier:SetAttribute("Carrying", nil)
	target:SetAttribute("CarriedBy", nil)
	self._stateChanged:FireAllClients(carrier, target, false)
	log.info(string.format("%s dropped %s (%s)", carrier.Name, target.Name, reason or "released"))
end

-- --- validation loop --------------------------------------------------------

-- A carry must remain legitimate every moment it exists.
function CarryService:_validate()
	local players = Registry.expect("PlayerService")
	for carrier, target in self._carrying do
		local drop: string? = nil

		if not carrier.Parent or not target.Parent then
			drop = "disconnected"
		elseif not players:canFight(carrier) then
			drop = "carrier down"
		elseif not players:isDowned(target) then
			drop = "target recovered" -- revived or died
		else
			local carrierRoot, targetRoot = rootOf(carrier), rootOf(target)
			if not carrierRoot or not targetRoot then
				drop = "character lost"
			end
		end

		if drop then
			self:stopCarry(carrier, drop)
		end
	end
end

function CarryService:Start()
	self._stateChanged = Remotes.getEvent("Carry", "CarryStateChanged")

	Remotes.getEvent("Carry", "RequestCarry").OnServerEvent:Connect(function(player, target)
		if typeof(target) ~= "Instance" or not target:IsA("Player") then
			return
		end
		self:startCarry(player, target)
	end)

	Remotes.getEvent("Carry", "RequestDrop").OnServerEvent:Connect(function(player)
		self:stopCarry(player, "released")
	end)

	Players.PlayerRemoving:Connect(function(player)
		self:stopCarry(player, "left")
		local carrier = self._carriedBy[player]
		if carrier then
			self:stopCarry(carrier, "target left")
		end
	end)

	RunService.Heartbeat:Connect(function(dt)
		self._accumulator += dt
		if self._accumulator < 0.25 then
			return
		end
		self._accumulator = 0
		self:_validate()
	end)

	log.info("online — server-welded carrying with continuous validation")
end

return CarryService
