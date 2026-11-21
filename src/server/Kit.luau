--!strict
-- Construction kit shared by the site builders: primitives (parts, walls
-- with holes, lights, signs) and the standard tagged devices.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Characters = require(script.Parent.Characters)

-- Palette
local CONCRETE = Color3.fromRGB(52, 52, 58)
local CONCRETE_DARK = Color3.fromRGB(34, 34, 38)
local SEWER = Color3.fromRGB(44, 48, 40)
local METAL = Color3.fromRGB(96, 100, 108)
local METAL_DARK = Color3.fromRGB(48, 50, 56)
local HAZARD = Color3.fromRGB(240, 180, 20)
local CYAN = Color3.fromRGB(0, 230, 255)
local MAGENTA = Color3.fromRGB(255, 40, 140)
local RED = Color3.fromRGB(255, 50, 50)
local WHITE = Color3.fromRGB(225, 225, 220)

---------------------------------------------------------------------------
-- Primitives
---------------------------------------------------------------------------

local function newPart(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material?
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

-- Axis-aligned box from two corners.
local function box(
	parent: Instance,
	name: string,
	a: Vector3,
	b: Vector3,
	color: Color3,
	material: Enum.Material?
): Part
	local min = a:Min(b)
	local max = a:Max(b)
	return newPart(parent, name, max - min, CFrame.new((min + max) / 2), color, material)
end

-- Cylinder whose axis points along `axis` ("X", "Y" or "Z").
local function cylinder(
	parent: Instance,
	name: string,
	length: number,
	diameter: number,
	center: Vector3,
	axis: string,
	color: Color3,
	material: Enum.Material?
): Part
	local rotation = if axis == "Y"
		then CFrame.Angles(0, 0, math.pi / 2)
		elseif axis == "Z" then CFrame.Angles(0, math.pi / 2, 0)
		else CFrame.identity
	local part = newPart(
		parent,
		name,
		Vector3.new(length, diameter, diameter),
		CFrame.new(center) * rotation,
		color,
		material
	)
	part.Shape = Enum.PartType.Cylinder
	return part
end

local function ball(
	parent: Instance,
	name: string,
	diameter: number,
	center: Vector3,
	color: Color3,
	material: Enum.Material?
): Part
	local part = newPart(parent, name, Vector3.one * diameter, CFrame.new(center), color, material)
	part.Shape = Enum.PartType.Ball
	return part
end

local function decor(part: BasePart): BasePart
	part.CanCollide = false
	part.CanQuery = false
	part.CastShadow = false
	return part
end

local function light(part: BasePart, color: Color3, range: number, brightness: number): PointLight
	local pointLight = Instance.new("PointLight")
	pointLight.Color = color
	pointLight.Range = range
	pointLight.Brightness = brightness
	pointLight.Shadows = range > 20
	pointLight.Parent = part
	return pointLight
end

local function lamp(
	parent: Instance,
	position: Vector3,
	color: Color3,
	range: number,
	brightness: number
)
	local head = newPart(
		parent,
		"Lamp",
		Vector3.new(2.4, 0.4, 2.4),
		CFrame.new(position),
		color,
		Enum.Material.Neon
	)
	decor(head)
	light(head, color, range, brightness)
end

local function sign(
	parent: Instance,
	cframe: CFrame,
	size: Vector2,
	text: string,
	color: Color3,
	font: Enum.Font?
): Part
	local board = newPart(parent, "Sign", Vector3.new(size.X, size.Y, 0.2), cframe, CONCRETE_DARK)
	board.Transparency = 1
	decor(board)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 30
	gui.LightInfluence = 0
	gui.Parent = board
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = color
	label.TextScaled = true
	label.Font = font or Enum.Font.GothamBlack
	label.Parent = gui
	return board
end

-- Facing helpers for signs: a sign at `position` readable from `toward`.
local function facing(position: Vector3, toward: Vector3): CFrame
	return CFrame.lookAt(position, toward)
end

---------------------------------------------------------------------------
-- Walls with holes
---------------------------------------------------------------------------

export type Rect = { a0: number, a1: number, b0: number, b1: number }

local function rect(a0: number, a1: number, b0: number, b1: number): Rect
	return { a0 = a0, a1 = a1, b0 = b0, b1 = b1 }
end

-- Splits the rectangle [a0,a1] x [b0,b1] into solid pieces around the holes.
local function solids(a0: number, a1: number, b0: number, b1: number, holes: { Rect }): { Rect }
	local cuts = { a0, a1 }
	for _, hole in holes do
		table.insert(cuts, math.clamp(hole.a0, a0, a1))
		table.insert(cuts, math.clamp(hole.a1, a0, a1))
	end
	table.sort(cuts)

	local out: { Rect } = {}
	for i = 1, #cuts - 1 do
		local x0, x1 = cuts[i], cuts[i + 1]
		if x1 - x0 > 0.01 then
			local mid = (x0 + x1) / 2
			local spans: { { number } } = {}
			for _, hole in holes do
				if hole.a0 < mid and hole.a1 > mid then
					table.insert(spans, { hole.b0, hole.b1 })
				end
			end
			table.sort(spans, function(p, q)
				return p[1] < q[1]
			end)
			local cursor = b0
			for _, span in spans do
				if span[1] > cursor then
					table.insert(out, rect(x0, x1, cursor, math.min(span[1], b1)))
				end
				cursor = math.max(cursor, span[2])
			end
			if cursor < b1 then
				table.insert(out, rect(x0, x1, cursor, b1))
			end
		end
	end
	return out
end

-- Wall in the plane x = const. Holes are rects in (z, y).
local function wallX(
	parent: Instance,
	x: number,
	z0: number,
	z1: number,
	y0: number,
	y1: number,
	holes: { Rect },
	color: Color3,
	material: Enum.Material?
)
	for _, piece in solids(z0, z1, y0, y1, holes) do
		box(
			parent,
			"Wall",
			Vector3.new(x - 0.5, piece.b0, piece.a0),
			Vector3.new(x + 0.5, piece.b1, piece.a1),
			color,
			material
		)
	end
end

-- Wall in the plane z = const. Holes are rects in (x, y).
local function wallZ(
	parent: Instance,
	z: number,
	x0: number,
	x1: number,
	y0: number,
	y1: number,
	holes: { Rect },
	color: Color3,
	material: Enum.Material?
)
	for _, piece in solids(x0, x1, y0, y1, holes) do
		box(
			parent,
			"Wall",
			Vector3.new(piece.a0, piece.b0, z - 0.5),
			Vector3.new(piece.a1, piece.b1, z + 0.5),
			color,
			material
		)
	end
end

-- Horizontal slab at height y (thickness 2). Holes are rects in (x, z).
local function slabY(
	parent: Instance,
	y: number,
	x0: number,
	x1: number,
	z0: number,
	z1: number,
	holes: { Rect },
	color: Color3,
	material: Enum.Material?
)
	for _, piece in solids(x0, x1, z0, z1, holes) do
		box(
			parent,
			"Slab",
			Vector3.new(piece.a0, y - 1, piece.b0),
			Vector3.new(piece.a1, y + 1, piece.b1),
			color,
			material
		)
	end
end

---------------------------------------------------------------------------
-- Devices
---------------------------------------------------------------------------

local idCounter = 0

local function device(
	instance: Instance,
	deviceType: string,
	label: string,
	attributes: { [string]: any }?
)
	local spec = Config.DEVICES[deviceType]
	assert(spec, "unknown device type " .. deviceType)
	idCounter += 1
	local hex = string.format("%04X", (idCounter * 7919 + 4099) % 65536)
	instance:SetAttribute("DeviceType", deviceType)
	instance:SetAttribute("DeviceId", spec.prefix .. "-" .. hex)
	instance:SetAttribute("Label", label)
	if attributes then
		for key, value in attributes do
			instance:SetAttribute(key, value)
		end
	end
	CollectionService:AddTag(instance, "Device")
end

local function newModel(parent: Instance, name: string): Model
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent
	return model
end

local function buildDock(parent: Instance, refs: any?, label: string, floor: Vector3)
	local model = newModel(parent, "Dock")
	local base = newPart(
		model,
		"Base",
		Vector3.new(7, 0.4, 7),
		CFrame.new(floor + Vector3.new(0, 0.2, 0)),
		METAL_DARK,
		Enum.Material.DiamondPlate
	)
	for _, offset in { Vector3.new(0, 0, 3.35), Vector3.new(0, 0, -3.35) } do
		decor(
			newPart(
				model,
				"Ring",
				Vector3.new(7, 0.1, 0.3),
				CFrame.new(floor + offset + Vector3.new(0, 0.45, 0)),
				CYAN,
				Enum.Material.Neon
			)
		)
	end
	for _, offset in { Vector3.new(3.35, 0, 0), Vector3.new(-3.35, 0, 0) } do
		decor(
			newPart(
				model,
				"Ring",
				Vector3.new(0.3, 0.1, 7),
				CFrame.new(floor + offset + Vector3.new(0, 0.45, 0)),
				CYAN,
				Enum.Material.Neon
			)
		)
	end
	decor(
		cylinder(
			model,
			"Mark",
			0.05,
			3,
			floor + Vector3.new(0, 0.43, 0),
			"Y",
			CYAN,
			Enum.Material.Neon
		)
	)
	light(base, CYAN, 14, 0.8)
	model.PrimaryPart = base
	device(
		model,
		"Dock",
		label,
		{ LinkRange = Config.LINK.DOCK_RANGE, Status = "CHARGING / MODULE SWAP", Temperature = 31 }
	)
	CollectionService:AddTag(model, "LinkSource")
	if refs then
		table.insert(refs.docks, model)
	end
	return model
end

local function buildJunctionBox(parent: Instance, position: Vector3, normal: Vector3, label: string)
	local model = newModel(parent, "JunctionBox")
	local cf = CFrame.lookAt(position, position + normal)
	local body =
		newPart(model, "Body", Vector3.new(2.4, 3, 0.8), cf, METAL_DARK, Enum.Material.Metal)
	decor(
		newPart(
			model,
			"Led",
			Vector3.new(0.3, 0.3, 0.1),
			cf * CFrame.new(0.8, 1.1, -0.45),
			Color3.fromRGB(80, 255, 120),
			Enum.Material.Neon
		)
	)
	model.PrimaryPart = body
	device(model, "Junction", label, { Status = "LIVE 400V", Temperature = 36 })
	return model
end

local function buildCamera(parent: Instance, position: Vector3, lookAt: Vector3, label: string)
	local model = newModel(parent, "SurveillanceCam")
	local cf = CFrame.lookAt(position, lookAt)
	local body = newPart(
		model,
		"Body",
		Vector3.new(1, 1, 2),
		cf,
		Color3.fromRGB(30, 30, 34),
		Enum.Material.Metal
	)
	decor(
		cylinder(
			model,
			"Lens",
			0.2,
			0.7,
			(cf * CFrame.new(0, 0, -1.05)).Position,
			"Z",
			Color3.fromRGB(20, 20, 30),
			Enum.Material.Glass
		)
	)
	local led = decor(
		newPart(
			model,
			"Led",
			Vector3.new(0.2, 0.2, 0.2),
			cf * CFrame.new(0.35, 0.35, -0.9),
			RED,
			Enum.Material.Neon
		)
	)
	light(led, RED, 4, 0.6)
	model.PrimaryPart = body
	device(model, "Surveillance", label, { Status = "RECORDING // DIRECTORATE", Temperature = 33 })
	CollectionService:AddTag(model, "SweepCam")
	return model
end

local function buildGas(
	parent: Instance,
	refs: any?,
	gas: string,
	center: Vector3,
	radius: number,
	peak: number,
	zone: string
)
	local spec = Config.GASES[gas]
	local cloud =
		ball(parent, "GasCloud_" .. gas, radius * 2, center, spec.color, Enum.Material.Neon)
	decor(cloud)
	cloud.CanTouch = false
	cloud.Transparency = 1
	cloud:SetAttribute("Gas", gas)
	cloud:SetAttribute("Peak", peak)
	cloud:SetAttribute("Radius", radius)
	cloud:SetAttribute("Scale", 1)
	cloud:SetAttribute("Zone", zone)
	CollectionService:AddTag(cloud, "GasCloud")
	if refs and zone == "Sewer" then
		table.insert(refs.sewerGas, cloud)
	end
	return cloud
end

local function buildDebris(
	parent: Instance,
	center: Vector3,
	size: Vector3,
	objective: string,
	label: string
)
	local rng = Random.new(math.floor(center.X * 13 + center.Z * 7))
	local chunk = newPart(
		parent,
		"Debris",
		size,
		CFrame.new(center)
			* CFrame.Angles(
				rng:NextNumber(-0.15, 0.15),
				rng:NextNumber(0, math.pi),
				rng:NextNumber(-0.15, 0.15)
			),
		Color3.fromRGB(70, 66, 58),
		Enum.Material.Concrete
	)
	device(
		chunk,
		"Debris",
		label,
		{ Objective = objective, Home = center, Cleared = false, Status = "BLOCKING" }
	)
	return chunk
end

local function buildTerminal(
	parent: Instance,
	refs: any?,
	floor: Vector3,
	yaw: number,
	label: string,
	offers: string,
	accepts: string
)
	local model = newModel(parent, "Terminal")
	local cf = CFrame.new(floor) * CFrame.Angles(0, yaw, 0)
	newPart(
		model,
		"Pedestal",
		Vector3.new(3, 3.2, 2),
		cf * CFrame.new(0, 1.6, 0),
		METAL_DARK,
		Enum.Material.Metal
	)
	local screen = newPart(
		model,
		"Screen",
		Vector3.new(3.4, 2.4, 0.3),
		cf * CFrame.new(0, 4.2, 0.2) * CFrame.Angles(math.rad(20), 0, 0),
		Color3.fromRGB(5, 25, 30),
		Enum.Material.Glass
	)
	light(screen, CYAN, 10, 0.8)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Display"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	gui.Parent = screen
	local text = Instance.new("TextLabel")
	text.Name = "Text"
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.TextColor3 = CYAN
	text.Font = Enum.Font.Code
	text.TextScaled = true
	text.Text = label .. "\nOFFLINE NETWORK\nAWAITING DATA JACK"
	text.Parent = gui
	model.PrimaryPart = screen
	device(model, "Terminal", label, {
		Offers = offers,
		Accepts = accepts,
		Status = "NETWORK DOWN - JACK IN",
		Temperature = 34,
	})
	if refs then
		table.insert(refs.terminals, model)
	end
	return model
end

local function buildBeacon(
	parent: Instance,
	refs: any?,
	position: Vector3,
	normal: Vector3,
	label: string
)
	local model = newModel(parent, "Beacon")
	local cf = CFrame.lookAt(position, position + normal)
	local base =
		newPart(model, "Base", Vector3.new(2.4, 2.4, 0.6), cf, METAL_DARK, Enum.Material.Metal)
	local dome = ball(
		model,
		"Dome",
		1.8,
		(cf * CFrame.new(0, 0, -0.6)).Position,
		Color3.fromRGB(90, 30, 20),
		Enum.Material.Glass
	)
	local strobe = light(dome, Color3.fromRGB(255, 120, 40), 26, 0)
	strobe.Name = "Strobe"
	model.PrimaryPart = base
	device(
		model,
		"Beacon",
		label,
		{ Active = false, Status = "DORMANT", LinkRange = 0, Temperature = 29 }
	)
	CollectionService:AddTag(model, "LinkSource")
	if refs then
		table.insert(refs.beacons, model)
	end
	return model
end

-- A simple figure built from blocks. `cf` is the torso centre and orientation.
export type ResidentSpec = {
	name: string,
	condition: string, -- Fever | Healthy | Dehydrated
	cf: CFrame, -- hip centre
	pose: string, -- Stand | Sit | Lie
	shirt: Color3,
}

-- A person the drone can find, assess and treat (an R15 character)
local function buildResident(parent: Instance, refs: any?, spec: ResidentSpec): Model
	local model =
		Characters.spawn(parent, "Resident", { pose = spec.pose, cf = spec.cf, shirt = spec.shirt })
	local temperature = Characters.temperature(spec.condition)
	device(model, "Resident", spec.name, {
		Condition = spec.condition,
		Temperature = temperature,
		BaseTemperature = temperature,
		NeedsAid = spec.condition ~= "Healthy",
		Located = false,
		Status = "UNIDENTIFIED",
	})
	if refs then
		table.insert(refs.residents, model)
	end
	return model
end

local function buildValve(
	parent: Instance,
	refs: any?,
	position: Vector3,
	normal: number,
	label: string,
	correctOpen: boolean,
	startOpen: boolean
)
	local model = newModel(parent, "Valve")
	local wheel = cylinder(
		model,
		"Wheel",
		0.5,
		4,
		position,
		"Z",
		Color3.fromRGB(170, 40, 30),
		Enum.Material.Metal
	)
	decor(
		cylinder(
			model,
			"Stem",
			1.6,
			0.6,
			position - Vector3.new(0, 0, normal * 0.9),
			"Z",
			METAL,
			Enum.Material.Metal
		)
	)
	decor(
		newPart(
			model,
			"SpokeA",
			Vector3.new(3.6, 0.35, 0.35),
			CFrame.new(position),
			METAL,
			Enum.Material.Metal
		)
	)
	decor(
		newPart(
			model,
			"SpokeB",
			Vector3.new(0.35, 3.6, 0.35),
			CFrame.new(position),
			METAL,
			Enum.Material.Metal
		)
	)
	model.PrimaryPart = wheel
	device(model, "Valve", label, {
		Open = startOpen,
		CorrectOpen = correctOpen,
		Status = if startOpen then "OPEN" else "CLOSED",
	})
	if refs then
		table.insert(refs.valves, model)
	end
	return model
end

local function buildSamplePoint(
	parent: Instance,
	position: Vector3,
	normal: Vector3,
	label: string,
	readings: { [string]: any }
)
	local pipe = cylinder(
		parent,
		"Outflow",
		2,
		1.6,
		position,
		if math.abs(normal.Z) > 0 then "Z" else "X",
		Color3.fromRGB(80, 84, 70),
		Enum.Material.CorrodedMetal
	)
	local slime = decor(
		newPart(
			parent,
			"Slime",
			Vector3.new(1, 3, 1),
			CFrame.new(position + normal * 1.1 - Vector3.new(0, 1.6, 0)),
			Color3.fromRGB(110, 140, 50),
			Enum.Material.Glass
		)
	)
	slime.Transparency = 0.3
	local attributes: { [string]: any } = { Status = "UNTESTED", Sampled = false }
	for key, value in readings do
		attributes[key] = value
	end
	device(pipe, "SamplePoint", label, attributes)
	return pipe
end

local Kit = {
	newPart = newPart,
	box = box,
	cylinder = cylinder,
	ball = ball,
	decor = decor,
	light = light,
	lamp = lamp,
	sign = sign,
	facing = facing,
	rect = rect,
	solids = solids,
	wallX = wallX,
	wallZ = wallZ,
	slabY = slabY,
	device = device,
	newModel = newModel,
	buildDock = buildDock,
	buildJunctionBox = buildJunctionBox,
	buildCamera = buildCamera,
	buildGas = buildGas,
	buildDebris = buildDebris,
	buildTerminal = buildTerminal,
	buildBeacon = buildBeacon,
	buildResident = buildResident,
	buildValve = buildValve,
	buildSamplePoint = buildSamplePoint,
	colors = {
		CONCRETE = CONCRETE,
		CONCRETE_DARK = CONCRETE_DARK,
		SEWER = SEWER,
		METAL = METAL,
		METAL_DARK = METAL_DARK,
		HAZARD = HAZARD,
		CYAN = CYAN,
		MAGENTA = MAGENTA,
		RED = RED,
		WHITE = WHITE,
	},
}

return Kit
