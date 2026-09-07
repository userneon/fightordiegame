--!strict
--[[
	Data
	----
	Aggregator for every gameplay DATA table. Data is deliberately separated
	from logic: services read these definitions and never embed the numbers.

		local Data = require(ReplicatedStorage.Shared.Data)
		local def = Data.Weapons.get("M4A1")

	Rule for this folder: pure tables + pure lookup helpers. No services, no
	RunService, no Instances, no side effects — so both the server and client
	can require it safely.
]]

local Data = {}

Data.Factions = require(script.Factions)
Data.Ranks = require(script.Ranks)
Data.Roles = require(script.Roles)
Data.BodyParts = require(script.BodyParts)
Data.Materials = require(script.Materials)
Data.Ammo = require(script.Ammo)
Data.Weapons = require(script.Weapons)
Data.Items = require(script.Items)

return Data
