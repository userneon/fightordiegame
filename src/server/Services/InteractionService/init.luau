--!strict
--[[
	InteractionService (server-authoritative)
	-----------------------------------------
	The generic "player interacts with a world object" framework: doors, access
	cards, loot containers, mission objects, vehicle and medical interaction.

	*** THIS SERVICE CREATES NO WORLD OBJECTS. ***
	You build and tag the objects in Studio; this service gives them behaviour.

	How to connect your world object
	--------------------------------
	  1. Tag any Instance with "Interactable" (CollectionService).
	  2. Give it attributes:
	       InteractKind    "Door" | "Container" | "Objective" | custom string
	       InteractHold    seconds to hold (0 = instant)         [optional]
	       InteractRange   studs                                  [optional]
	       RequiredPerm    a RankService permission key           [optional]
	       RequiredItem    an item id the player must carry        [optional]
	       RequiredFaction "Army" | "Terrorist"                    [optional]
	       ConsumeItem     true to consume RequiredItem            [optional]
	  3. Optionally register a handler in code:
	       Interaction:registerHandler("Door", function(player, object) ... end)

	Every request is validated server-side: existence, tag, distance,
	permission, faction, item, and a hold that resets on movement.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Logger = require(Shared.Modules.Logger)
local Registry = require(Shared.Modules.Registry)
local Remotes = require(Shared.Remotes)
local HoldTracker = require(Shared.Modules.HoldTracker)

local InteractionService = {}
InteractionService.Name = "InteractionService"

local log = Logger.scope(InteractionService.Name)

local TAG = "Interactable"

function InteractionService:Init()
	self._config = Config.Interaction
	self._holds = HoldTracker.new()
	self._handlers = {} :: { [string]: (player: Player, object: Instance) -> () }
end

-- Register behaviour for an InteractKind. Other services call this at Start.
function InteractionService:registerHandler(kind: string, handler: (player: Player, object: Instance) -> ())
	self._handlers[kind] = handler
end

-- --- validation -------------------------------------------------------------

local function positionOfObject(object: Instance): Vector3?
	if object:IsA("BasePart") then
		return object.Position
	end
	if object:IsA("Model") then
		local part = object.PrimaryPart or object:FindFirstChildWhichIsA("BasePart", true)
		return part and part.Position or nil
	end
	local part = object:FindFirstChildWhichIsA("BasePart", true)
	return part and part.Position or nil
end

local function positionOfPlayer(player: Player): Vector3?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return (root and root:IsA("BasePart")) and root.Position or nil
end

--[[
	Can this player interact with this object right now?
	Returns ok, reason.
]]
function InteractionService:canInteract(player: Player, object: Instance): (boolean, string?)
	if not object or not object.Parent then
		return false, "object missing"
	end
	if not CollectionService:HasTag(object, TAG) then
		return false, "not interactable"
	end

	local players = Registry.expect("PlayerService")
	if not players:canFight(player) then
		return false, "unable to interact"
	end

	-- Distance is always validated on the server.
	local objectPosition = positionOfObject(object)
	local playerPosition = positionOfPlayer(player)
	if not objectPosition or not playerPosition then
		return false, "no position"
	end
	local range = object:GetAttribute("InteractRange") or self._config.MaxDistance
	if (objectPosition - playerPosition).Magnitude > range then
		return false, "too far"
	end

	-- Faction restriction.
	local requiredFaction = object:GetAttribute("RequiredFaction")
	if type(requiredFaction) == "string" and requiredFaction ~= "" then
		if players:getState(player).faction ~= requiredFaction then
			return false, "wrong faction"
		end
	end

	-- Rank permission (access cards, restricted doors, command posts).
	local requiredPerm = object:GetAttribute("RequiredPerm")
	if type(requiredPerm) == "string" and requiredPerm ~= "" then
		local ranks = Registry.get("RankService")
		if ranks and not ranks:can(player, requiredPerm) then
			return false, "insufficient rank"
		end
	end

	-- Item requirement (keycards, tools).
	local requiredItem = object:GetAttribute("RequiredItem")
	if type(requiredItem) == "string" and requiredItem ~= "" then
		local inventory = Registry.get("InventoryService")
		if not inventory or inventory:countOf(player, requiredItem) <= 0 then
			return false, "missing " .. requiredItem
		end
	end

	return true, nil
end

-- --- execution --------------------------------------------------------------

function InteractionService:_complete(player: Player, object: Instance)
	-- Re-validate at the moment of completion, not just at the start.
	local ok, reason = self:canInteract(player, object)
	if not ok then
		self._result:FireClient(player, object, false, reason)
		return
	end

	-- Consume the required item if the object asks for it.
	local requiredItem = object:GetAttribute("RequiredItem")
	if type(requiredItem) == "string" and requiredItem ~= "" and object:GetAttribute("ConsumeItem") == true then
		local inventory = Registry.get("InventoryService")
		if inventory then
			inventory:removeItem(player, requiredItem, 1)
		end
	end

	local kind = object:GetAttribute("InteractKind")
	local handler = type(kind) == "string" and self._handlers[kind] or nil
	if handler then
		local success, err = pcall(handler, player, object)
		if not success then
			log.error(string.format("handler '%s' failed: %s", tostring(kind), tostring(err)))
			self._result:FireClient(player, object, false, "handler error")
			return
		end
	else
		-- No handler: still a valid interaction. Flip a state attribute so a
		-- simple door you built works with zero code.
		object:SetAttribute("InteractedBy", player.UserId)
		object:SetAttribute("InteractState", not (object:GetAttribute("InteractState") == true))
	end

	self._result:FireClient(player, object, true, nil)
	log.info(string.format("%s interacted with %s (%s)", player.Name, object.Name, tostring(kind)))
end

function InteractionService:begin(player: Player, object: Instance)
	local ok, reason = self:canInteract(player, object)
	if not ok then
		self._result:FireClient(player, object, false, reason)
		return
	end

	local holdTime = object:GetAttribute("InteractHold")
	if type(holdTime) ~= "number" then
		holdTime = self._config.DefaultHoldTime
	end

	if holdTime <= 0 then
		self:_complete(player, object)
		return
	end

	self._holds:begin(player, {
		duration = holdTime,
		position = positionOfPlayer(player),
		moveTolerance = self._config.MoveTolerance,
		getPosition = function()
			return positionOfPlayer(player)
		end,
		validate = function()
			return (self:canInteract(player, object))
		end,
		onProgress = function(progress)
			self._progress:FireClient(player, object, progress)
		end,
		onCancel = function()
			self._progress:FireClient(player, object, 0)
		end,
		onComplete = function()
			self:_complete(player, object)
		end,
	})
end

function InteractionService:cancel(player: Player)
	self._holds:cancel(player, "released")
end

function InteractionService:Start()
	self._progress = Remotes.getEvent("Interaction", "InteractionProgress")
	self._result = Remotes.getEvent("Interaction", "InteractionResult")

	Remotes.getEvent("Interaction", "RequestInteract").OnServerEvent:Connect(function(player, object)
		if typeof(object) ~= "Instance" then
			return
		end
		self:begin(player, object)
	end)
	Remotes.getEvent("Interaction", "CancelInteract").OnServerEvent:Connect(function(player)
		self:cancel(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		self._holds:cancel(player, "left")
	end)

	RunService.Heartbeat:Connect(function(dt)
		self._holds:update(dt)
	end)

	log.info(string.format("online — tag world objects '%s' to connect them", TAG))
end

return InteractionService
