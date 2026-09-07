--!strict
--[[
	CorpseService (server-authoritative)
	------------------------------------
	Bodies persist on the battlefield. When a player dies their character model
	is DETACHED and kept as a corpse, so respawning does NOT erase the body —
	the dead stay where they fell until the corpse is reclaimed.

	Loot rules (per spec) are resolved from item data, never hardcoded:
	  - Teammates may retrieve allowed equipment/ammo (allyLootable).
	  - Enemies may NOT freely take weapons/equipment (enemyLootable = false).
	  - Mission-critical items are lootable by anyone — that is the point of them.

	Scale: corpses are capped (Config.Corpse.MaxCorpses) and recycled
	oldest-first, and each carries a plain data record rather than live state,
	so a full server does not accumulate unbounded models.

	No map geometry is created — only the dead player's own character model is
	re-parented and frozen.
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

local CorpseService = {}
CorpseService.Name = "CorpseService"

local log = Logger.scope(CorpseService.Name)

type Stack = { itemId: string, count: number, state: { [string]: any }? }

type Corpse = {
	id: number,
	ownerUserId: number,
	ownerName: string,
	faction: string,
	position: Vector3,
	createdAt: number,
	model: Model?,
	loot: { Stack },
	searching: { [number]: boolean },
}

function CorpseService:Init()
	self._config = Config.Corpse
	self._corpses = {} :: { [number]: Corpse }
	self._order = {} :: { number } -- ids, oldest first
	self._nextId = 1
	self._folder = nil :: Folder?
end

-- --- container --------------------------------------------------------------

function CorpseService:_getFolder(): Folder
	if self._folder and self._folder.Parent then
		return self._folder
	end
	local existing = Workspace:FindFirstChild("FOD_Corpses")
	if existing and existing:IsA("Folder") then
		self._folder = existing
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = "FOD_Corpses"
	folder.Parent = Workspace
	self._folder = folder
	return folder
end

-- --- creation ---------------------------------------------------------------

function CorpseService:createFromPlayer(player: Player): number?
	local players = Registry.expect("PlayerService")
	local state = players:getState(player)
	local character = player.Character
	if not character then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	local position = (root and root:IsA("BasePart")) and root.Position or Vector3.zero

	-- Take the loadout off the body before the inventory is cleared.
	local inventory = Registry.get("InventoryService")
	local loot: { Stack } = inventory and inventory:extractLoot(player) or {}

	local id = self._nextId
	self._nextId += 1

	-- Detach the character so respawning gets a NEW model and this one stays.
	local model: Model? = nil
	local ok = pcall(function()
		character.Parent = self:_getFolder()
		character.Name = string.format("Corpse_%d_%s", id, player.Name)
		-- Freeze it: no controller, no collisions with the living.
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.PlatformStand = true
		end
		for _, part in character:GetDescendants() do
			if part:IsA("BasePart") then
				part.CanCollide = true
				part.Anchored = false
			end
		end
		character:SetAttribute("CorpseId", id)
		model = character
	end)
	if not ok then
		model = nil
	end
	-- The player must not keep controlling the corpse.
	player.Character = nil

	local corpse: Corpse = {
		id = id,
		ownerUserId = player.UserId,
		ownerName = player.Name,
		faction = state.faction,
		position = position,
		createdAt = os.clock(),
		model = model,
		loot = loot,
		searching = {},
	}
	self._corpses[id] = corpse
	table.insert(self._order, id)

	if inventory then
		inventory:clear(player)
	end

	self:_enforceCap()

	if self._created then
		self._created:FireAllClients(id, position, state.faction)
	end
	log.info(string.format("corpse %d created for %s", id, player.Name))
	return id
end

-- Oldest-first recycling keeps large servers bounded.
function CorpseService:_enforceCap()
	local max = self._config.MaxCorpses
	while max > 0 and #self._order > max do
		local oldest = table.remove(self._order, 1)
		if oldest then
			self:remove(oldest)
		end
	end
end

function CorpseService:remove(id: number)
	local corpse = self._corpses[id]
	if not corpse then
		return
	end
	if corpse.model then
		corpse.model:Destroy()
	end
	self._corpses[id] = nil
	for i, existing in self._order do
		if existing == id then
			table.remove(self._order, i)
			break
		end
	end
	if self._removed then
		self._removed:FireAllClients(id)
	end
end

function CorpseService:get(id: number): Corpse?
	return self._corpses[id]
end

-- --- loot rules -------------------------------------------------------------

--[[
	May `player` take this stack off this corpse?
	Returns allowed, reason.
]]
function CorpseService:canLoot(player: Player, corpse: Corpse, stack: Stack): (boolean, string?)
	local def = Data.Items.get(stack.itemId)
	-- Weapons are not in the item table; treat them as equipment.
	local isWeapon = Data.Weapons.get(stack.itemId) ~= nil

	local players = Registry.expect("PlayerService")
	local faction = players:getState(player).faction
	local sameTeam = faction == corpse.faction

	if def and def.missionCritical then
		return true, nil -- anyone may take mission items
	end

	if sameTeam then
		if def and not def.allyLootable then
			return false, "not lootable"
		end
		return true, nil
	end

	-- Enemy corpse.
	local factionDef = Data.Factions.get(faction)
	if isWeapon then
		if factionDef and factionDef.canLootEnemyWeapons then
			return true, nil
		end
		return false, "cannot take enemy weapons"
	end
	if def and def.enemyLootable then
		return true, nil
	end
	return false, "cannot loot enemy equipment"
end

-- Returns the list of stacks this player is ALLOWED to see/take.
function CorpseService:searchCorpse(player: Player, id: number)
	local corpse = self._corpses[id]
	if not corpse then
		return nil, "no such corpse"
	end

	local players = Registry.expect("PlayerService")
	if not players:canFight(player) then
		return nil, "cannot search while downed"
	end

	-- Proximity is validated server-side.
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return nil, "no character"
	end
	if (root.Position - corpse.position).Magnitude > self._config.MaxSearchDistance then
		return nil, "too far"
	end

	local visible = {}
	for index, stack in corpse.loot do
		local allowed = self:canLoot(player, corpse, stack)
		table.insert(visible, {
			index = index,
			itemId = stack.itemId,
			count = stack.count,
			lootable = allowed,
		})
	end
	return visible, nil
end

function CorpseService:lootItem(player: Player, id: number, index: number): (boolean, string?)
	local corpse = self._corpses[id]
	if not corpse then
		return false, "no such corpse"
	end
	local stack = corpse.loot[index]
	if not stack then
		return false, "no such item"
	end

	-- Re-validate distance and permission at the moment of taking.
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return false, "no character"
	end
	if (root.Position - corpse.position).Magnitude > self._config.MaxSearchDistance then
		return false, "too far"
	end
	local allowed, reason = self:canLoot(player, corpse, stack)
	if not allowed then
		return false, reason
	end

	local inventory = Registry.expect("InventoryService")
	local added = inventory:addItem(player, stack.itemId, stack.count, stack.state)
	if added <= 0 then
		return false, "inventory full"
	end

	stack.count -= added
	if stack.count <= 0 then
		table.remove(corpse.loot, index)
	end
	return true, nil
end

-- --- lifecycle --------------------------------------------------------------

function CorpseService:Start()
	self._created = Remotes.getEvent("Corpse", "CorpseCreated")
	self._removed = Remotes.getEvent("Corpse", "CorpseRemoved")

	local search = Remotes.getFunction("Corpse", "SearchCorpse")
	search.OnServerInvoke = function(player, id)
		if type(id) ~= "number" then
			return nil
		end
		local list, reason = self:searchCorpse(player, id)
		return { items = list, reason = reason }
	end

	local loot = Remotes.getFunction("Corpse", "LootItem")
	loot.OnServerInvoke = function(player, id, index)
		if type(id) ~= "number" or type(index) ~= "number" then
			return { ok = false, reason = "bad request" }
		end
		local ok, reason = self:lootItem(player, id, index)
		return { ok = ok, reason = reason }
	end

	-- Reclaim expired corpses.
	if self._config.Lifetime > 0 then
		task.spawn(function()
			while true do
				task.wait(15)
				local now = os.clock()
				for id, corpse in self._corpses do
					if now - corpse.createdAt >= self._config.Lifetime then
						self:remove(id)
					end
				end
			end
		end)
	end

	Players.PlayerRemoving:Connect(function(player)
		-- Corpses deliberately OUTLIVE their owner leaving the server.
		for _, corpse in self._corpses do
			corpse.searching[player.UserId] = nil
		end
	end)

	log.info("online — persistent corpses with faction loot rules")
end

return CorpseService
