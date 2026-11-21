--!strict
-- Site builders register their simulated systems here; Environment and
-- Actions drive them generically. Devices point at their group with
-- attributes (FloodGroup, VentGroup), so one rule set runs both sites.

export type FloodSpec = {
	valves: { Instance },
	valveObjective: string,
	debrisObjective: string,
	debrisTotal: number,
	-- progress 0 (flooded) .. 1 (drained) -> sets the water, returns a level in studs
	apply: (progress: number) -> number,
	-- human-readable effect of a level, e.g. "Underpass: 0.8m of water"
	describe: (level: number) -> string,
}

export type VentSpec = {
	breaker: Instance,
	objective: string,
	onText: string,
	offText: string,
}

local Registry = {
	floods = {} :: { [string]: FloodSpec },
	vents = {} :: { [string]: VentSpec },
	spawns = {} :: { [string]: CFrame },
	roots = {} :: { [string]: Folder },
}

return Registry
