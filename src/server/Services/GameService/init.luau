--!strict
--[[
	GameService (server-authoritative)
	----------------------------------
	The match/deployment flow — the contract the Start Menu talks to.

	Spawn gating: nobody spawns on join (Players.CharacterAutoLoads = false), so
	a connected player sits in the Start Menu with no body in the world. The
	character is only created when they press PLAY:

	    client PLAY -> Game.RequestDeploy -> validate -> assign faction if
	    needed -> SpawnService:spawnPlayer -> Game.Deployed ack -> client
	    closes the menu and the camera goes first-person.

	Death is handed to SpawnService for the respawn timer; a player who never
	deployed is never spawned or respawned.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Logger = require(Shared.Modules.Logger)
local Registry = require(Shared.Modules.Registry)
local Remotes = require(Shared.Remotes)
local Data = require(Shared.Data)

local GameService = {}
GameService.Name = "GameService"

local log = Logger.scope(GameService.Name)

function GameService:Init()
	-- Gate spawning: set as early as possible so no character is auto-created.
	Players.CharacterAutoLoads = false
end

function GameService:isDeployed(player: Player): boolean
	local players = Registry.expect("PlayerService")
	return players:getState(player).deployed
end

function GameService:_deploy(player: Player, requestedFaction: string?)
	local players = Registry.expect("PlayerService")
	local state = players:getState(player)
	if state.deployed then
		return -- ignore duplicate PLAY presses
	end

	-- Faction: honour a valid request, otherwise balance them onto a side.
	local factions = Registry.expect("FactionService")
	if type(requestedFaction) == "string" and Data.Factions.isPlayable(requestedFaction) then
		factions:setFaction(player, requestedFaction)
	end
	if not Data.Factions.isPlayable(state.faction) then
		factions:autoAssign(player)
	end

	players:setDeployed(player, true)

	local spawns = Registry.expect("SpawnService")
	local ok, err = pcall(function()
		spawns:spawnPlayer(player)
	end)
	if not ok then
		log.error(string.format("spawn failed for %s: %s", player.Name, tostring(err)))
		players:setDeployed(player, false)
		return
	end

	self._deployedEvent:FireClient(player)
	log.info(string.format("%s deployed as %s", player.Name, state.faction))
end

function GameService:undeploy(player: Player)
	local players = Registry.expect("PlayerService")
	players:setDeployed(player, false)
	if player.Character then
		player.Character:Destroy()
	end
end

function GameService:Start()
	local requestDeploy = Remotes.getEvent("Game", "RequestDeploy")
	self._deployedEvent = Remotes.getEvent("Game", "Deployed")

	requestDeploy.OnServerEvent:Connect(function(player, requestedFaction)
		self:_deploy(player, requestedFaction)
	end)

	-- Once deployed, death schedules a respawn (SpawnService owns the timing).
	local players = Registry.expect("PlayerService")
	local function onPlayer(player: Player)
		player.CharacterAdded:Connect(function(character)
			local humanoid = character:WaitForChild("Humanoid", 10)
			if humanoid and humanoid:IsA("Humanoid") then
				humanoid.Died:Connect(function()
					if players:getState(player).deployed then
						local spawns = Registry.expect("SpawnService")
						spawns:scheduleRespawn(player)
					end
				end)
			end
		end)
	end
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	Players.PlayerAdded:Connect(onPlayer)

	log.info("online — spawning gated on PLAY (no auto-spawn)")
end

return GameService
