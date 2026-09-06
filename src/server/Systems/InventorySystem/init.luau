--!strict
--[[
	InventorySystem (server-authoritative)
	--------------------------------------
	Owns: per-player inventory + weight, and corpse search/loot.

	The server holds the canonical inventory for every player. It computes total
	weight (feeding MovementSystem) and validates all add/remove/transfer/use
	requests. Corpses are searchable containers that expose a dead player's
	dropped loot for Config.Inventory.CorpseSearchTime.

	Item definitions (id, displayName, weight, stackable) belong in a data module
	you and I can flesh out — referenced via Types.ItemDef.

	TODO (implement when the Inventory / corpse-search spec is provided):
	  - Maintain per-player inventory tables + attributes.
	  - Emit Remotes.Inventory.InventoryChanged on change.
	  - Handle RequestUseItem / RequestDropItem / SearchCorpse / RequestTransfer.
	  - Publish total weight for MovementSystem to consume.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Logger = require(Shared.Modules.Logger)

local InventorySystem = {}
InventorySystem.Name = "InventorySystem"

local log = Logger.scope(InventorySystem.Name)

function InventorySystem:Init()
	self._config = Config.Inventory
	self._inventories = {} -- [Player] = { InventoryEntry }
end

function InventorySystem:Start()
	log.info("ready (stub — awaiting Inventory/corpse spec)")
end

-- Placeholder API other systems (e.g. Movement) will call once implemented.
function InventorySystem:getTotalWeight(_player: Player): number
	return 0
end

return InventorySystem
