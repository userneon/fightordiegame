--!strict
--[[
	VisionService (server-authoritative)
	------------------------------------
	Owns the GAMEPLAY side of vision: who currently has NVG or a flashlight on,
	and the authoritative power/blackout state for the map.

	*** CREATES NO LIGHTS, LAMPS OR MAP OBJECTS. *** The client renders the
	actual NVG effect and flashlight (NvgController); this service decides
	whether they are ALLOWED to and broadcasts blackout state.

	Why server-side: NVG use is gameplay information (a lit flashlight makes you
	visible, NVG requires owning the item), and a blackout must be the same
	truth for everyone.

	Connect your world power objects
	--------------------------------
	  Tag a generator/breaker "PowerSource". Toggling it via InteractionService
	  calls setBlackout(); this service then tells every client.
]]

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Logger = require(Shared.Modules.Logger)
local Registry = require(Shared.Modules.Registry)
local Remotes = require(Shared.Remotes)

local VisionService = {}
VisionService.Name = "VisionService"

local log = Logger.scope(VisionService.Name)

local POWER_TAG = "PowerSource"

function VisionService:Init()
	self._config = Config.Vision
	self._nvg = {} :: { [Player]: boolean }
	self._flashlight = {} :: { [Player]: boolean }
	self._blackout = false
end

-- --- queries ----------------------------------------------------------------

function VisionService:hasNvgOn(player: Player): boolean
	return self._nvg[player] == true
end

function VisionService:hasFlashlightOn(player: Player): boolean
	return self._flashlight[player] == true
end

function VisionService:isBlackout(): boolean
	return self._blackout
end

-- --- toggles ----------------------------------------------------------------

-- Toggling requires actually owning the equipment — the client cannot grant
-- itself night vision.
function VisionService:setNvg(player: Player, enabled: boolean): boolean
	local players = Registry.expect("PlayerService")
	if enabled then
		if not players:canFight(player) then
			return false
		end
		local inventory = Registry.get("InventoryService")
		if inventory and inventory:countOf(player, "NVG") <= 0 and not inventory:getEquipped(player, "NVG") then
			return false -- does not own NVGs
		end
	end
	self._nvg[player] = enabled or nil
	player:SetAttribute("NvgOn", enabled)
	return true
end

function VisionService:setFlashlight(player: Player, enabled: boolean): boolean
	local players = Registry.expect("PlayerService")
	if enabled then
		if not players:canFight(player) then
			return false
		end
		local inventory = Registry.get("InventoryService")
		if inventory and inventory:countOf(player, "FLASHLIGHT") <= 0 then
			return false
		end
	end
	self._flashlight[player] = enabled or nil
	-- Replicated so other clients can render the beam and see you coming.
	player:SetAttribute("FlashlightOn", enabled)
	return true
end

-- --- blackout ---------------------------------------------------------------

function VisionService:setBlackout(enabled: boolean, initiator: Player?)
	if self._blackout == enabled then
		return
	end
	self._blackout = enabled
	self._blackoutEvent:FireAllClients(enabled)
	log.info(string.format("blackout %s%s", enabled and "ON" or "OFF", initiator and (" by " .. initiator.Name) or ""))
end

function VisionService:Start()
	self._blackoutEvent = Remotes.getEvent("Vision", "BlackoutChanged")

	Remotes.getEvent("Vision", "ToggleNvg").OnServerEvent:Connect(function(player, enabled)
		self:setNvg(player, enabled == true)
	end)
	Remotes.getEvent("Vision", "ToggleFlashlight").OnServerEvent:Connect(function(player, enabled)
		self:setFlashlight(player, enabled == true)
	end)

	-- Power sources you tag become blackout toggles through InteractionService.
	local interaction = Registry.get("InteractionService")
	if interaction then
		interaction:registerHandler("PowerSource", function(player, object)
			local powered = object:GetAttribute("Powered") ~= false
			object:SetAttribute("Powered", not powered)
			self:setBlackout(powered, player) -- cutting power => blackout on
		end)
	end
	for _, source in CollectionService:GetTagged(POWER_TAG) do
		if source:GetAttribute("Powered") == nil then
			source:SetAttribute("Powered", true)
		end
	end

	Players.PlayerRemoving:Connect(function(player)
		self._nvg[player] = nil
		self._flashlight[player] = nil
	end)

	log.info("online — NVG/flashlight authority + blackout state")
end

return VisionService
