--!strict
--[[
	InventoryService (server-authoritative)
	---------------------------------------
	The single owner of what every player is carrying. The client renders it and
	sends requests; it never mutates anything.

	Layout (per spec):
	  Equipped slots — Primary, Secondary, Head (helmet), Chest (plate), Backpack
	  Loose storage  — ammo, medical, equipment, flashlight, NVG, radio, mission
	                   items; capacity comes from the equipped backpack.

	Weight is published to MovementService (Heavy Walk / speed penalty), so
	loadout choice has a real movement cost.

	Item definitions (weight, stack size, loot rules) are data — Shared/Data/Items.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Logger = require(Shared.Modules.Logger)
local Registry = require(Shared.Modules.Registry)
local Remotes = require(Shared.Remotes)
local Data = require(Shared.Data)

local InventoryService = {}
InventoryService.Name = "InventoryService"

local log = Logger.scope(InventoryService.Name)

export type Stack = { itemId: string, count: number, state: { [string]: any }? }

export type Inventory = {
	Primary: Stack?,
	Secondary: Stack?,
	Head: Stack?,
	Chest: Stack?,
	Backpack: Stack?,
	items: { Stack },
}

local EQUIP_SLOTS = { "Primary", "Secondary", "Head", "Chest", "Backpack" }

function InventoryService:Init()
	self._config = Config.Inventory
	self._inventories = {} :: { [Player]: Inventory }
end

-- --- access -----------------------------------------------------------------

function InventoryService:get(player: Player): Inventory
	local inv = self._inventories[player]
	if not inv then
		inv = { Primary = nil, Secondary = nil, Head = nil, Chest = nil, Backpack = nil, items = {} }
		self._inventories[player] = inv
	end
	return inv
end

function InventoryService:capacity(player: Player): number
	local inv = self:get(player)
	local base = self._config.MaxSlots
	if inv.Backpack then
		local def = Data.Items.get(inv.Backpack.itemId)
		if def then
			base += (def.props.capacity or 0)
		end
	end
	return base
end

function InventoryService:getTotalWeight(player: Player): number
	local inv = self._inventories[player]
	if not inv then
		return 0
	end
	local total = 0
	for _, slot in EQUIP_SLOTS do
		local stack = (inv :: any)[slot]
		if stack then
			total += Data.Items.weightOf(stack.itemId, stack.count)
		end
	end
	for _, stack in inv.items do
		total += Data.Items.weightOf(stack.itemId, stack.count)
	end
	-- Equipped weapons carry their own weight from the weapon table.
	for _, slot in { "Primary", "Secondary" } do
		local stack = (inv :: any)[slot]
		if stack then
			local weapon = Data.Weapons.get(stack.itemId)
			if weapon then
				total += weapon.weight
			end
		end
	end
	return total
end

-- --- mutation ---------------------------------------------------------------

function InventoryService:_publish(player: Player)
	if self._changed then
		self._changed:FireClient(player, self:get(player))
	end
	player:SetAttribute("CarriedWeight", self:getTotalWeight(player))
end

function InventoryService:countOf(player: Player, itemId: string): number
	local inv = self:get(player)
	local n = 0
	for _, stack in inv.items do
		if stack.itemId == itemId then
			n += stack.count
		end
	end
	return n
end

-- Returns how many were actually added (respects stack + capacity limits).
function InventoryService:addItem(player: Player, itemId: string, count: number?, state: { [string]: any }?): number
	local def = Data.Items.get(itemId)
	if not def then
		return 0
	end
	local remaining = count or 1
	local inv = self:get(player)
	local added = 0

	if def.stackable then
		for _, stack in inv.items do
			if stack.itemId == itemId and stack.count < def.maxStack then
				local room = def.maxStack - stack.count
				local take = math.min(room, remaining)
				stack.count += take
				remaining -= take
				added += take
				if remaining <= 0 then
					break
				end
			end
		end
	end

	local capacity = self:capacity(player)
	while remaining > 0 and #inv.items < capacity do
		local take = def.stackable and math.min(def.maxStack, remaining) or 1
		table.insert(inv.items, { itemId = itemId, count = take, state = state })
		remaining -= take
		added += take
	end

	if added > 0 then
		self:_publish(player)
	end
	return added
end

function InventoryService:removeItem(player: Player, itemId: string, count: number?): number
	local inv = self:get(player)
	local remaining = count or 1
	local removed = 0

	for i = #inv.items, 1, -1 do
		local stack = inv.items[i]
		if stack.itemId == itemId then
			local take = math.min(stack.count, remaining)
			stack.count -= take
			remaining -= take
			removed += take
			if stack.count <= 0 then
				table.remove(inv.items, i)
			end
			if remaining <= 0 then
				break
			end
		end
	end

	if removed > 0 then
		self:_publish(player)
	end
	return removed
end

-- Equip into a slot. Anything already there is moved back into storage.
function InventoryService:equip(player: Player, slot: string, itemId: string, state: { [string]: any }?): boolean
	local def = Data.Items.get(itemId)
	local weapon = Data.Weapons.get(itemId)
	if not def and not weapon then
		return false
	end

	-- Rank gate for restricted weapons.
	if weapon then
		local ranks = Registry.get("RankService")
		if ranks and not ranks:atLeastTier(player, weapon.minTier) then
			return false
		end
		if weapon.slot ~= slot then
			return false
		end
	elseif def then
		local wanted = def.props.slot or def.category
		if wanted ~= slot then
			return false
		end
	end

	local inv = self:get(player)
	local previous = (inv :: any)[slot]
	;(inv :: any)[slot] = { itemId = itemId, count = 1, state = state or {} }

	if previous then
		table.insert(inv.items, previous)
	end
	self:_publish(player)
	return true
end

function InventoryService:unequip(player: Player, slot: string): boolean
	local inv = self:get(player)
	local stack = (inv :: any)[slot]
	if not stack then
		return false
	end
	;(inv :: any)[slot] = nil
	table.insert(inv.items, stack)
	self:_publish(player)
	return true
end

function InventoryService:getEquipped(player: Player, slot: string): Stack?
	return (self:get(player) :: any)[slot]
end

-- Everything that should stay on the body when the player dies.
function InventoryService:extractLoot(player: Player): { Stack }
	local inv = self:get(player)
	local loot: { Stack } = {}

	for _, slot in EQUIP_SLOTS do
		local stack = (inv :: any)[slot]
		if stack then
			local def = Data.Items.get(stack.itemId)
			if (def == nil) or def.droppedOnDeath then
				table.insert(loot, stack)
			end
		end
	end
	for _, stack in inv.items do
		local def = Data.Items.get(stack.itemId)
		if def and def.droppedOnDeath then
			table.insert(loot, stack)
		end
	end
	return loot
end

function InventoryService:clear(player: Player)
	self._inventories[player] = nil
	self:_publish(player)
end

-- --- lifecycle --------------------------------------------------------------

function InventoryService:Start()
	self._changed = Remotes.getEvent("Inventory", "InventoryChanged")

	local requestUse = Remotes.getEvent("Inventory", "RequestUseItem")
	requestUse.OnServerEvent:Connect(function(player, itemId)
		if type(itemId) ~= "string" then
			return
		end
		local players = Registry.expect("PlayerService")
		if players:isDead(player) then
			return
		end
		local medical = Registry.get("MedicalService")
		if medical then
			medical:useItemOnSelf(player, itemId)
		end
	end)

	local requestDrop = Remotes.getEvent("Inventory", "RequestDropItem")
	requestDrop.OnServerEvent:Connect(function(player, itemId, count)
		if type(itemId) ~= "string" then
			return
		end
		self:removeItem(player, itemId, type(count) == "number" and count or 1)
	end)

	local requestEquip = Remotes.getEvent("Inventory", "RequestEquipItem")
	requestEquip.OnServerEvent:Connect(function(player, slot, itemId)
		if type(slot) ~= "string" or type(itemId) ~= "string" then
			return
		end
		if self:countOf(player, itemId) <= 0 and not self:getEquipped(player, slot) then
			return -- must actually own it
		end
		self:removeItem(player, itemId, 1)
		self:equip(player, slot, itemId)
	end)

	Players.PlayerRemoving:Connect(function(player)
		self._inventories[player] = nil
	end)

	log.info("online — slots, weight and loadout authority")
end

return InventoryService
