--!strict
--[[
	GameSystem (server-authoritative)
	---------------------------------
	The entry point for the match / deployment flow. The Start Menu's PLAY button
	fires Remotes.Game.RequestDeploy; this system receives that intent, spawns the
	player's character, marks them deployed, and acks with Remotes.Game.Deployed.

	Spawn gating
	------------
	Players do NOT spawn on join. We set Players.CharacterAutoLoads = false so a
	freshly joined player sits in the Start Menu with no character in the world;
	the character is only loaded when they press PLAY (deploy). Once deployed, a
	death respawns them after Config.Spawn.RespawnTime.

	This is still a CLEAN PLACEHOLDER: richer spawn/loadout logic (team spawn
	zones, loadouts) belongs in SpawnSystem and can hook in from here — it does
	not create map geometry.

	Replicated state:
	  Deployed (Player attribute) — true once the player has left the menu.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Logger = require(Shared.Modules.Logger)
local Remotes = require(Shared.Remotes)

local GameSystem = {}
GameSystem.Name = "GameSystem"

local log = Logger.scope(GameSystem.Name)

function GameSystem:Init()
	self._deployed = {} :: { [Player]: boolean }

	-- Gate spawning: nobody spawns until they press PLAY. Set as early as
	-- possible so no character is auto-created for players who join.
	Players.CharacterAutoLoads = false
end

-- Public: has this player deployed out of the menu? Other systems can read this.
function GameSystem:isDeployed(player: Player): boolean
	return self._deployed[player] == true
end

-- Respawn a deployed player a short delay after death. Undeployed players (still
-- in the menu) never respawn. SpawnSystem will own team spawn placement later.
function GameSystem:_watchDeaths(player: Player, character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	humanoid.Died:Connect(function()
		task.wait(Config.Spawn.RespawnTime)
		-- Only respawn if they are still in the game AND still deployed.
		if player.Parent and self._deployed[player] then
			player:LoadCharacter()
		end
	end)
end

function GameSystem:_deploy(player: Player)
	if self._deployed[player] then
		return -- already deployed; ignore duplicate PLAY presses
	end
	self._deployed[player] = true
	player:SetAttribute("Deployed", true)

	-- Spawn the character now (this is the "left the menu" moment). Richer
	-- spawn/loadout logic will grow in SpawnSystem and can be called from here.
	player:LoadCharacter()

	-- Ack so the client closes the menu and the camera goes first-person.
	self._deployedEvent:FireClient(player)
	log.info(string.format("%s deployed", player.Name))
end

function GameSystem:Start()
	local requestDeploy = Remotes.getEvent("Game", "RequestDeploy")
	self._deployedEvent = Remotes.getEvent("Game", "Deployed")

	requestDeploy.OnServerEvent:Connect(function(player)
		self:_deploy(player)
	end)

	-- Wire respawn-on-death for whoever deploys (character is loaded on deploy).
	local function onPlayer(player: Player)
		player.CharacterAdded:Connect(function(character)
			self:_watchDeaths(player, character)
		end)
	end
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	Players.PlayerAdded:Connect(onPlayer)

	Players.PlayerRemoving:Connect(function(player)
		self._deployed[player] = nil
	end)

	log.info("ready — spawning gated on PLAY (no auto-spawn)")
end

return GameSystem
