--!strict
--[[
	Data.Items
	----------
	Inventory item catalogue. DATA ONLY.

	Categories match the inventory slots in the spec: Primary, Secondary, Ammo,
	Medical, Equipment, Flashlight, NVG, Radio, Backpack, Mission.

	Loot rules live here as data so CorpseService never hardcodes policy:
	  enemyLootable  — may an ENEMY take this off a corpse? (weapons: no)
	  allyLootable   — may a TEAMMATE take it? (ammo/medical: yes)
	  missionCritical— always lootable by anyone with mission permission
	  droppedOnDeath — does it stay on the corpse at all?
]]

export type Category =
	"Primary" | "Secondary" | "Ammo" | "Medical" | "Equipment"
	| "Flashlight" | "NVG" | "Radio" | "Backpack" | "Mission" | "Armor"

export type ItemDef = {
	id: string,
	displayName: string,
	category: Category,
	weight: number, -- kg
	stackable: boolean,
	maxStack: number,
	enemyLootable: boolean,
	allyLootable: boolean,
	missionCritical: boolean,
	droppedOnDeath: boolean,
	-- Free-form tuning consumed by the owning service (e.g. heal amount).
	props: { [string]: any },
}

local Items = {}

local function def(t): ItemDef
	t.stackable = t.stackable ~= false and t.stackable or false
	t.maxStack = t.maxStack or 1
	t.enemyLootable = t.enemyLootable == true
	t.allyLootable = t.allyLootable ~= false
	t.missionCritical = t.missionCritical == true
	t.droppedOnDeath = t.droppedOnDeath ~= false
	t.props = t.props or {}
	return t
end

Items.List = {
	-- Ammunition (ally-lootable; the point of resupplying a squad)
	MAG_556 = def({ id = "MAG_556", displayName = "5.56 Magazine", category = "Ammo" :: Category, weight = 0.4, stackable = true, maxStack = 12, props = { ammoId = "5.56x45", rounds = 30 } }),
	MAG_762S = def({ id = "MAG_762S", displayName = "7.62x39 Magazine", category = "Ammo" :: Category, weight = 0.45, stackable = true, maxStack = 12, props = { ammoId = "7.62x39", rounds = 30 } }),
	MAG_762N = def({ id = "MAG_762N", displayName = "7.62x51 Magazine", category = "Ammo" :: Category, weight = 0.6, stackable = true, maxStack = 10, props = { ammoId = "7.62x51", rounds = 20 } }),
	MAG_9 = def({ id = "MAG_9", displayName = "9mm Magazine", category = "Ammo" :: Category, weight = 0.2, stackable = true, maxStack = 12, props = { ammoId = "9x19", rounds = 15 } }),
	SHELL_12 = def({ id = "SHELL_12", displayName = "12ga Shells", category = "Ammo" :: Category, weight = 0.05, stackable = true, maxStack = 60, props = { ammoId = "12ga", rounds = 1 } }),
	MAG_338 = def({ id = "MAG_338", displayName = ".338 Magazine", category = "Ammo" :: Category, weight = 0.5, stackable = true, maxStack = 8, props = { ammoId = ".338LM", rounds = 5 } }),

	-- Medical
	BANDAGE = def({ id = "BANDAGE", displayName = "Bandage", category = "Medical" :: Category, weight = 0.1, stackable = true, maxStack = 10, props = { stopsBleeding = true, heal = 15, useTime = 4 } }),
	MEDKIT = def({ id = "MEDKIT", displayName = "Medkit", category = "Medical" :: Category, weight = 1.2, stackable = true, maxStack = 3, props = { heal = 60, useTime = 8, medicOnly = true } }),
	MORPHINE = def({ id = "MORPHINE", displayName = "Morphine", category = "Medical" :: Category, weight = 0.15, stackable = true, maxStack = 6, props = { revive = true, useTime = 5, medicOnly = true } }),
	TOURNIQUET = def({ id = "TOURNIQUET", displayName = "Tourniquet", category = "Medical" :: Category, weight = 0.1, stackable = true, maxStack = 4, props = { stopsBleeding = true, useTime = 6 } }),

	-- Armor / helmet (helmet durability lives on the item instance, not here)
	HELMET_LVL2 = def({ id = "HELMET_LVL2", displayName = "Combat Helmet II", category = "Armor" :: Category, weight = 1.4, props = { slot = "Head", armorLevel = 2, durability = 100 } }),
	HELMET_LVL3 = def({ id = "HELMET_LVL3", displayName = "Combat Helmet III", category = "Armor" :: Category, weight = 1.9, props = { slot = "Head", armorLevel = 3, durability = 150 } }),
	PLATE_LVL3 = def({ id = "PLATE_LVL3", displayName = "Plate Carrier III", category = "Armor" :: Category, weight = 5.5, props = { slot = "Chest", armorLevel = 3, durability = 180 } }),

	-- Equipment
	FRAG = def({ id = "FRAG", displayName = "Frag Grenade", category = "Equipment" :: Category, weight = 0.45, stackable = true, maxStack = 4, props = { fuse = 4, radius = 18, damage = 120 } }),
	SMOKE = def({ id = "SMOKE", displayName = "Smoke Grenade", category = "Equipment" :: Category, weight = 0.42, stackable = true, maxStack = 4, props = { fuse = 2, duration = 20 } }),

	-- Gear
	FLASHLIGHT = def({ id = "FLASHLIGHT", displayName = "Flashlight", category = "Flashlight" :: Category, weight = 0.3, props = { battery = 600 } }),
	NVG = def({ id = "NVG", displayName = "Night Vision Goggles", category = "NVG" :: Category, weight = 0.7, enemyLootable = false, props = { battery = 900 } }),
	RADIO = def({ id = "RADIO", displayName = "Field Radio", category = "Radio" :: Category, weight = 0.9, props = { range = 2000 } }),
	BACKPACK_S = def({ id = "BACKPACK_S", displayName = "Assault Pack", category = "Backpack" :: Category, weight = 1.0, props = { capacity = 12 } }),
	BACKPACK_L = def({ id = "BACKPACK_L", displayName = "Rucksack", category = "Backpack" :: Category, weight = 2.2, props = { capacity = 24 } }),

	-- Mission items: always lootable by anyone (that is the point of them)
	INTEL = def({ id = "INTEL", displayName = "Intel Documents", category = "Mission" :: Category, weight = 0.2, enemyLootable = true, missionCritical = true }),
	ACCESS_CARD = def({ id = "ACCESS_CARD", displayName = "Access Card", category = "Mission" :: Category, weight = 0.05, enemyLootable = true, missionCritical = true, props = { clearance = 2 } }),
} :: { [string]: ItemDef }

function Items.get(id: string): ItemDef?
	return Items.List[id]
end

function Items.weightOf(id: string, count: number?): number
	local d = Items.List[id]
	if not d then
		return 0
	end
	return d.weight * (count or 1)
end

return Items
