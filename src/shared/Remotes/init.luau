--!strict
--[[
	Remotes
	-------
	Single source of truth for every client <-> server remote in FIGHT OR DIE.

	- The SERVER creates the remote instances (once), organised into a folder
	  per system inside ReplicatedStorage/Shared/Remotes/_Instances.
	- The CLIENT waits for and returns the same instances.

	Usage:
		local Remotes = require(ReplicatedStorage.Shared.Remotes)
		local ev = Remotes.getEvent("Medic", "RequestRevive")     -- RemoteEvent
		local fn = Remotes.getFunction("Inventory", "SearchCorpse") -- RemoteFunction

	Naming keeps remotes grouped by system so networking stays legible as the
	game grows. Register the names a system needs in DEFINITIONS below.
]]

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local IS_SERVER = RunService:IsServer()

-- Declare the remotes each system owns. This is documentation AND creation:
-- the server instantiates exactly these on startup.
-- { SystemName = { events = {...}, functions = {...} } }
local DEFINITIONS = {
	Movement = {
		events = { "SetSprint", "SetCrouch" },
		functions = {},
	},
	Medic = {
		events = { "RequestHeal", "RequestRevive", "TreatmentProgress" },
		functions = {},
	},
	Wounded = {
		events = { "StateChanged", "BleedTick" },
		functions = {},
	},
	Carry = {
		events = { "RequestCarry", "RequestDrop", "CarryStateChanged" },
		functions = {},
	},
	Inventory = {
		events = { "InventoryChanged", "RequestUseItem", "RequestDropItem" },
		functions = { "SearchCorpse", "RequestTransfer" },
	},
	Spawn = {
		events = { "RequestRespawn", "Respawned" },
		functions = {},
	},
	Vehicle = {
		events = { "RequestEnter", "RequestExit", "VehicleInput" },
		functions = {},
	},
	Drone = {
		events = { "RequestDeploy", "DroneInput", "DroneState" },
		functions = {},
	},
	Vision = {
		events = { "ToggleNvg", "ToggleFlashlight", "BlackoutChanged" },
		functions = {},
	},
}

local ROOT_NAME = "_Instances"

local Remotes = {}

local function getRoot(): Folder
	if IS_SERVER then
		local root = ReplicatedStorage.Shared.Remotes:FindFirstChild(ROOT_NAME)
		if not root then
			root = Instance.new("Folder")
			root.Name = ROOT_NAME
			root.Parent = ReplicatedStorage.Shared.Remotes
		end
		return root
	else
		return ReplicatedStorage.Shared.Remotes:WaitForChild(ROOT_NAME) :: Folder
	end
end

local function getSystemFolder(systemName: string): Folder
	local root = getRoot()
	if IS_SERVER then
		local folder = root:FindFirstChild(systemName)
		if not folder then
			folder = Instance.new("Folder")
			folder.Name = systemName
			folder.Parent = root
		end
		return folder
	else
		return root:WaitForChild(systemName) :: Folder
	end
end

local function resolve(systemName: string, remoteName: string, className: string): Instance
	local folder = getSystemFolder(systemName)
	if IS_SERVER then
		local remote = folder:FindFirstChild(remoteName)
		if not remote then
			remote = Instance.new(className)
			remote.Name = remoteName
			remote.Parent = folder
		end
		return remote
	else
		return folder:WaitForChild(remoteName)
	end
end

function Remotes.getEvent(systemName: string, remoteName: string): RemoteEvent
	return resolve(systemName, remoteName, "RemoteEvent") :: RemoteEvent
end

function Remotes.getFunction(systemName: string, remoteName: string): RemoteFunction
	return resolve(systemName, remoteName, "RemoteFunction") :: RemoteFunction
end

-- Server-only: pre-create every declared remote so clients can WaitForChild
-- them safely. Called once by the server bootstrap.
function Remotes.build()
	assert(IS_SERVER, "Remotes.build() must be called on the server")
	for systemName, def in DEFINITIONS do
		for _, eventName in def.events do
			Remotes.getEvent(systemName, eventName)
		end
		for _, fnName in def.functions do
			Remotes.getFunction(systemName, fnName)
		end
	end
end

return Remotes
