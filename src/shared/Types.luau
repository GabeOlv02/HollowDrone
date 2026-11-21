--!strict
-- Shared type definitions for the drone simulator.

-- "Sensor" | "Arm" | "DataJack" | "Payload"
export type ModuleId = string
-- "A" | "B"
export type Hardpoint = string
-- "Normal" | "Thermal" | "Night" | "Chem" | "Lidar"
export type CameraMode = string
-- "Primary" | "Secondary"
export type ActionKind = string

export type Severity = "info" | "warning" | "danger" | "success" | "data"

export type Feedback = {
	title: string,
	text: string,
	severity: Severity,
}

export type ModuleSpec = {
	label: string,
	short: string,
	description: string,
	color: Color3,
}

export type DeviceSpec = {
	label: string,
	prefix: string,
	category: string, -- Infrastructure | Network | Directorate | Medical | Life
}

export type GasSpec = {
	label: string,
	unit: string,
	danger: number, -- above this, lethal or harmful for humans
	color: Color3,
}

export type LinkSource = { position: Vector3, range: number }
export type JammerInfo = { position: Vector3, radius: number, factor: number }

export type GasCloud = {
	position: Vector3,
	gas: string,
	peak: number,
	radius: number,
	scale: number,
}

export type Objective = { key: string, label: string, total: number }
export type ObjectiveGroup = {
	site: string,
	zone: string,
	problems: { number },
	brief: string,
	items: { Objective },
}

export type SiteLighting = {
	brightness: number,
	clockTime: number,
	ambient: Color3,
	outdoorAmbient: Color3,
	density: number,
	haze: number,
	glare: number,
	atmosphereColor: Color3,
	decay: Color3,
	exposure: number,
}

export type SiteSpec = {
	name: string,
	subtitle: string,
	origin: Vector3,
	min: Vector3,
	max: Vector3,
	datum: number,
	lighting: SiteLighting,
}

export type PacketSpec = {
	name: string,
	destination: string,
	objective: string,
	event: string?,
}

export type AirReading = { O2: number, CO2: number, PM: number, Temp: number }

return nil
