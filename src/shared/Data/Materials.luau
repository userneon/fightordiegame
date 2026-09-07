--!strict
--[[
	Data.Materials
	--------------
	Penetration behaviour per surface material. DATA ONLY.

	BallisticsService uses these when a ray hits world geometry (the map YOU
	build). Nothing here references specific parts or places — it keys off
	Enum.Material, so any wall you build behaves correctly automatically.

	`resistance`  — penetration "cost" per stud of thickness. Higher = tougher.
	`maxThickness`— studs beyond which the round always stops.
	`damageLoss`  — fraction of damage removed when a round punches through.
	`ricochet`    — chance a shallow-angle impact deflects instead of penetrating.
]]

export type MaterialDef = {
	resistance: number,
	maxThickness: number,
	damageLoss: number,
	ricochet: number,
}

local Materials = {}

Materials.Default = { resistance = 6, maxThickness = 2.0, damageLoss = 0.45, ricochet = 0.05 } :: MaterialDef

-- Only materials that differ meaningfully from Default need an entry.
Materials.List = {
	[Enum.Material.Plastic] = { resistance = 3, maxThickness = 3.0, damageLoss = 0.25, ricochet = 0.02 },
	[Enum.Material.Wood] = { resistance = 3, maxThickness = 4.0, damageLoss = 0.25, ricochet = 0.02 },
	[Enum.Material.WoodPlanks] = { resistance = 3, maxThickness = 4.0, damageLoss = 0.28, ricochet = 0.02 },
	[Enum.Material.Glass] = { resistance = 1, maxThickness = 2.0, damageLoss = 0.10, ricochet = 0.0 },
	[Enum.Material.Ice] = { resistance = 2, maxThickness = 3.0, damageLoss = 0.20, ricochet = 0.05 },
	[Enum.Material.Sand] = { resistance = 5, maxThickness = 3.0, damageLoss = 0.50, ricochet = 0.02 },
	[Enum.Material.Grass] = { resistance = 2, maxThickness = 2.0, damageLoss = 0.15, ricochet = 0.0 },
	[Enum.Material.Fabric] = { resistance = 1, maxThickness = 2.0, damageLoss = 0.10, ricochet = 0.0 },
	[Enum.Material.Brick] = { resistance = 9, maxThickness = 1.5, damageLoss = 0.55, ricochet = 0.08 },
	[Enum.Material.Concrete] = { resistance = 11, maxThickness = 1.2, damageLoss = 0.60, ricochet = 0.08 },
	[Enum.Material.Slate] = { resistance = 10, maxThickness = 1.2, damageLoss = 0.58, ricochet = 0.10 },
	[Enum.Material.Rock] = { resistance = 13, maxThickness = 1.0, damageLoss = 0.65, ricochet = 0.12 },
	[Enum.Material.Marble] = { resistance = 12, maxThickness = 1.0, damageLoss = 0.62, ricochet = 0.12 },
	[Enum.Material.Metal] = { resistance = 16, maxThickness = 0.8, damageLoss = 0.70, ricochet = 0.18 },
	[Enum.Material.DiamondPlate] = { resistance = 18, maxThickness = 0.7, damageLoss = 0.75, ricochet = 0.20 },
	[Enum.Material.CorrodedMetal] = { resistance = 12, maxThickness = 1.0, damageLoss = 0.60, ricochet = 0.14 },
} :: { [Enum.Material]: MaterialDef }

function Materials.get(material: Enum.Material): MaterialDef
	return Materials.List[material] or Materials.Default
end

return Materials
