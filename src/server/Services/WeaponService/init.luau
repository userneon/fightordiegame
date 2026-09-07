--!strict
--[[
	WeaponService (server-authoritative)
	------------------------------------
	Modular weapon framework. Every per-weapon number lives in Shared/Data/Weapons,
	so adding a gun is a data edit, never a code edit.

	Handles: equip / unequip / switching, fire, reload, dry fire, ammo, fire-rate
	validation, weapon ownership and shot validation.

	Trust model — the client may only say "I am firing, roughly this way":
	  - ownership     : the weapon must actually be in that inventory slot
	  - rank          : weapon.minTier gates restricted weapons
	  - readiness     : deployed, Alive, equipped, not mid-reload, past equip time
	  - fire rate     : enforced from weapon RPM with a small latency tolerance
	  - ammo          : decremented server-side; 0 rounds means dry fire
	  - origin        : must be near the player's actual head, else rejected
	  - direction     : normalised server-side and given the server's own spread
	The trajectory, hits and damage are then produced entirely by the server
	(BallisticsService -> DamageService). The client is never believed about hits.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Logger = require(Shared.Modules.Logger)
local Registry = require(Shared.Modules.Registry)
local Remotes = require(Shared.Remotes)
local Data = require(Shared.Data)

local WeaponService = {}
WeaponService.Name = "WeaponService"

local log = Logger.scope(WeaponService.Name)

type WeaponState = {
	slot: string?,
	weaponId: string?,
	ammoInMag: number,
	fireMode: string,
	lastShot: number,
	equippedAt: number,
	reloading: boolean,
}

function WeaponService:Init()
	self._config = Config.Ballistics
	self._states = {} :: { [Player]: WeaponState }
end

function WeaponService:getState(player: Player): WeaponState
	local state = self._states[player]
	if not state then
		state = {
			slot = nil,
			weaponId = nil,
			ammoInMag = 0,
			fireMode = "Semi",
			lastShot = 0,
			equippedAt = 0,
			reloading = false,
		}
		self._states[player] = state
	end
	return state
end

function WeaponService:getEquipped(player: Player)
	local state = self:getState(player)
	if not state.weaponId then
		return nil
	end
	return Data.Weapons.get(state.weaponId)
end

function WeaponService:_publish(player: Player)
	local state = self:getState(player)
	player:SetAttribute("WeaponName", state.weaponId or "")
	player:SetAttribute("Ammo", state.ammoInMag)
	local def = state.weaponId and Data.Weapons.get(state.weaponId)
	player:SetAttribute("MaxAmmo", def and def.magSize or 0)
	if self._weaponState then
		self._weaponState:FireClient(player, state.weaponId, state.ammoInMag, state.fireMode, state.reloading)
	end
end

-- --- equip ------------------------------------------------------------------

function WeaponService:equip(player: Player, slot: string): boolean
	if slot ~= "Primary" and slot ~= "Secondary" then
		return false
	end
	local inventory = Registry.expect("InventoryService")
	local stack = inventory:getEquipped(player, slot)
	if not stack then
		return false
	end
	local def = Data.Weapons.get(stack.itemId)
	if not def then
		return false
	end

	-- Rank gate.
	local ranks = Registry.get("RankService")
	if ranks and not ranks:atLeastTier(player, def.minTier) then
		return false
	end

	local state = self:getState(player)
	state.slot = slot
	state.weaponId = def.id
	state.equippedAt = os.clock()
	state.reloading = false
	state.fireMode = def.fireModes[1]
	-- Magazine contents persist on the item instance between swaps.
	stack.state = stack.state or {}
	if type(stack.state.ammoInMag) ~= "number" then
		stack.state.ammoInMag = def.magSize
	end
	state.ammoInMag = stack.state.ammoInMag

	self:_publish(player)
	return true
end

function WeaponService:unequip(player: Player)
	local state = self:getState(player)
	-- Persist the magazine back onto the item before holstering.
	if state.slot and state.weaponId then
		local inventory = Registry.get("InventoryService")
		local stack = inventory and inventory:getEquipped(player, state.slot)
		if stack then
			stack.state = stack.state or {}
			stack.state.ammoInMag = state.ammoInMag
		end
	end
	state.slot = nil
	state.weaponId = nil
	state.ammoInMag = 0
	state.reloading = false
	self:_publish(player)
end

-- --- validation -------------------------------------------------------------

function WeaponService:_muzzleOrigin(player: Player): Vector3?
	local character = player.Character
	if not character then
		return nil
	end
	local head = character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart")
	if head and head:IsA("BasePart") then
		return head.Position
	end
	return nil
end

-- Apply the weapon's own cone server-side so the client cannot fire laser-straight.
function WeaponService:_applySpread(direction: Vector3, spreadMoa: number): Vector3
	if spreadMoa <= 0 then
		return direction
	end
	-- MOA -> radians (1 MOA = 1/60 degree).
	local radians = math.rad(spreadMoa / 60)
	local angle = math.random() * math.pi * 2
	local magnitude = math.sqrt(math.random()) * radians

	-- Build an orthonormal basis around the aim direction.
	local up = math.abs(direction.Y) > 0.99 and Vector3.new(1, 0, 0) or Vector3.new(0, 1, 0)
	local right = direction:Cross(up).Unit
	local realUp = right:Cross(direction).Unit

	local offset = (right * math.cos(angle) + realUp * math.sin(angle)) * math.tan(magnitude)
	return (direction + offset).Unit
end

-- --- firing -----------------------------------------------------------------

function WeaponService:tryFire(player: Player, origin: Vector3, direction: Vector3): boolean
	local players = Registry.expect("PlayerService")
	if not players:canFight(player) then
		return false
	end

	local state = self:getState(player)
	local def = self:getEquipped(player)
	if not def then
		return false
	end
	if state.reloading then
		return false
	end

	local now = os.clock()

	-- Equip delay.
	if now - state.equippedAt < def.equipTime then
		return false
	end

	-- Fire rate (with tolerance so latency jitter is not a false positive).
	local interval = Data.Weapons.shotInterval(def) * Config.AntiCheat.FireRateTolerance
	if now - state.lastShot < interval then
		local anticheat = Registry.get("AntiCheatService")
		if anticheat then
			anticheat:report(player, "FireRate", string.format("%s interval %.3f", def.id, now - state.lastShot))
		end
		return false
	end

	-- Ammo / dry fire.
	if state.ammoInMag <= 0 then
		if self._weaponState then
			self._weaponState:FireClient(player, state.weaponId, 0, state.fireMode, false, "DryFire")
		end
		return false
	end

	-- Origin sanity: the shot must come from near the player's own head.
	local muzzle = self:_muzzleOrigin(player)
	if not muzzle then
		return false
	end
	if typeof(origin) ~= "Vector3" or (origin - muzzle).Magnitude > self._config.MaxOriginError then
		local anticheat = Registry.get("AntiCheatService")
		if anticheat then
			anticheat:report(player, "ShotOrigin", "origin too far from muzzle")
		end
		origin = muzzle -- clamp rather than reward the client
	end

	if typeof(direction) ~= "Vector3" or direction.Magnitude < 1e-4 then
		return false
	end
	direction = direction.Unit

	state.lastShot = now
	state.ammoInMag -= 1

	local ballistics = Registry.expect("BallisticsService")
	local damageService = Registry.expect("DamageService")
	local character = player.Character

	-- Shotguns throw several traces from one trigger pull.
	for _ = 1, math.max(1, def.pellets) do
		local spread = self:_applySpread(direction, def.spreadMoa)
		ballistics:fire({
			origin = origin,
			direction = spread,
			ammoId = def.ammoId,
			shooter = player,
			ignore = character and { character } or nil,
			onHit = function(hit)
				local victim, zone = damageService:resolvePlayer(hit.instance)
				if victim then
					damageService:applyDamage(victim, {
						amount = hit.damage,
						zone = zone,
						attacker = player,
						weaponId = def.id,
						ammoId = def.ammoId,
						penetration = Data.Ammo.get(def.ammoId) and Data.Ammo.get(def.ammoId).penetration or 0,
						distance = hit.distance,
					})
					return true -- a body stops the round
				end
				-- World geometry: let BallisticsService decide penetration.
				local audio = Registry.get("AudioService")
				if audio then
					audio:impact(hit.position, hit.material)
				end
				return false
			end,
		})
	end

	-- Tell everyone a shot happened (client plays the sound/tracer).
	local audio = Registry.get("AudioService")
	if audio then
		audio:gunshot(player, origin, def.id)
	end
	if self._shotFired then
		self._shotFired:FireAllClients(player, origin, direction, def.id)
	end

	local data = Registry.get("DataService")
	if data then
		data:incrementStat(player, "shotsFired")
	end

	self:_publish(player)
	return true
end

-- --- reload -----------------------------------------------------------------

function WeaponService:reload(player: Player): boolean
	local state = self:getState(player)
	local def = self:getEquipped(player)
	if not def or state.reloading then
		return false
	end
	if state.ammoInMag >= def.magSize then
		return false
	end

	local inventory = Registry.expect("InventoryService")
	-- Find a magazine item matching this weapon's calibre.
	local magItemId: string? = nil
	for id, itemDef in Data.Items.List do
		if itemDef.category == "Ammo" and itemDef.props.ammoId == def.ammoId then
			if inventory:countOf(player, id) > 0 then
				magItemId = id
				break
			end
		end
	end
	if not magItemId then
		return false -- out of ammo entirely
	end

	state.reloading = true
	self:_publish(player)

	local wasEmpty = state.ammoInMag <= 0
	local duration = wasEmpty and def.reloadEmptyTime or def.reloadTime

	task.spawn(function()
		task.wait(duration)
		-- Re-validate: they may have died, swapped or dropped mags mid-reload.
		if not state.reloading or state.weaponId ~= def.id then
			return
		end
		local players = Registry.expect("PlayerService")
		if not players:canFight(player) then
			state.reloading = false
			self:_publish(player)
			return
		end
		if inventory:removeItem(player, magItemId :: string, 1) > 0 then
			local itemDef = Data.Items.get(magItemId :: string)
			local rounds = itemDef and itemDef.props.rounds or def.magSize
			state.ammoInMag = math.min(def.magSize, state.ammoInMag + rounds)
		end
		state.reloading = false
		self:_publish(player)
	end)
	return true
end

function WeaponService:Start()
	self._weaponState = Remotes.getEvent("Weapon", "WeaponState")
	self._shotFired = Remotes.getEvent("Combat", "ShotFired")

	Remotes.getEvent("Weapon", "RequestEquip").OnServerEvent:Connect(function(player, slot)
		if type(slot) == "string" then
			self:equip(player, slot)
		end
	end)
	Remotes.getEvent("Weapon", "RequestUnequip").OnServerEvent:Connect(function(player)
		self:unequip(player)
	end)
	Remotes.getEvent("Weapon", "RequestReload").OnServerEvent:Connect(function(player)
		self:reload(player)
	end)
	Remotes.getEvent("Weapon", "RequestFireMode").OnServerEvent:Connect(function(player, mode)
		local def = self:getEquipped(player)
		if def and type(mode) == "string" and Data.Weapons.hasFireMode(def, mode) then
			self:getState(player).fireMode = mode
			self:_publish(player)
		end
	end)

	Remotes.getEvent("Combat", "FireWeapon").OnServerEvent:Connect(function(player, origin, direction)
		self:tryFire(player, origin, direction)
	end)

	Players.PlayerRemoving:Connect(function(player)
		self._states[player] = nil
	end)
	Players.PlayerAdded:Connect(function(player)
		player.CharacterRemoving:Connect(function()
			self._states[player] = nil
		end)
	end)

	log.info("online — data-driven weapons, server shot validation")
end

return WeaponService
