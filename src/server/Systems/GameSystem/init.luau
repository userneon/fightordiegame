--!strict
--[[
	GameSystem (server-authoritative)
	---------------------------------
	The entry point for the match / deployment flow. The Start Menu's PLAY button
	fires Remotes.Game.RequestDeploy; this system receives that intent, marks the
	player deployed, and acks with Remotes.Game.Deployed.

	This is intentionally a CLEAN PLACEHOLDER: the detailed spawn/loadout logic
	belongs in SpawnSystem (and future match systems) and can hook in here without
	the menu ever needing to change. It does not create map geometry or spawn
	points — SpawnSystem owns that against your tagged world.

	Replicated state:
	  Deployed (Player attribute) — true once the player has left the menu.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Logger = require(Shared.Modules.Logger)
local Remotes = require(Shared.Remotes)

local GameSystem = {}
GameSystem.Name = "GameSystem"

local log = Logger.scope(GameSystem.Name)

function GameSystem:Init()
	self._deployed = {} :: { [Player]: boolean }
end

-- Public: has this player deployed out of the menu? Other systems can read this.
function GameSystem:isDeployed(player: Player): boolean
	return self._deployed[player] == true
end

function GameSystem:_deploy(player: Player)
	if self._deployed[player] then
		return -- already deployed; ignore duplicate PLAY presses
	end
	self._deployed[player] = true
	player:SetAttribute("Deployed", true)

	-- Placeholder deployment: real spawn/loadout flow will grow in SpawnSystem
	-- and can be invoked from here. For now we just ack so the client can
	-- close the menu and hand the camera back to the character.
	self._deployedEvent:FireClient(player)
	log.info(string.format("%s deployed", player.Name))
end

function GameSystem:Start()
	local requestDeploy = Remotes.getEvent("Game", "RequestDeploy")
	self._deployedEvent = Remotes.getEvent("Game", "Deployed")

	requestDeploy.OnServerEvent:Connect(function(player)
		self:_deploy(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		self._deployed[player] = nil
	end)

	log.info("ready — awaiting deploy requests from the Start Menu")
end

return GameSystem
