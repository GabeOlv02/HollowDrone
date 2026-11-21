--!strict
-- Builds THE HOLLOW // SECTOR 9: the showcase district. A deep-level city
-- carved into rock, built procedurally at runtime from Terrain (the rock
-- shell, the brick-lined sewer, the flood water, the surface) and parts
-- (everything people built).
--
-- Side section (local coordinates, the site origin is Config.SITES.Hollow.origin):
--
--   y 430  ── surface: grass returning, Met Station 4, the open hatch ──
--          │ LIFT SHAFT ZERO (sealed grate at 246, stuck lift car ~300)
--   y 242  ╭──────── dome: Directorate sodium "sun lamps" ────────╮
--   y 120  │ L6  gallery · hydroponic farm (W)                    │
--   y  80  │ L7  gallery · clinic (N) · CO2 scrubber hall (S)     │  THE WELL
--          │      bridge E -> the Spire (jammer, propaganda)      │  r = 92
--   y  40  │ L8  the DECK: steel plate sealing L9 · Ops Hub (E)   │
--   y   0  │ L9  the Pit: blackout, shelters, quarantine Q-9 (W)  │
--   y  -8  │ Underpass Market (floods)                            │
--   y -26  ╰── COLLECTOR C-2: brick sewer along x, pump room ─────╯

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Characters = require(script.Parent.Parent.Characters)
local Kit = require(script.Parent.Parent.Kit)
local Registry = require(script.Parent.Parent.Registry)

local newPart = Kit.newPart
local cylinder = Kit.cylinder
local ball = Kit.ball
local decor = Kit.decor
local light = Kit.light
local device = Kit.device
local newModel = Kit.newModel

local SITE = Config.SITES.Hollow
local O = SITE.origin
local Terrain = Workspace.Terrain

local WELL_RADIUS = 92
local VOXEL_PAD = 4
local DECK_Y = 40
local LEVELS = { 0, 40, 80, 120 } -- L9, L8, L7, L6 floor heights
local LEVEL_NAMES = { "LEVEL 9", "LEVEL 8", "LEVEL 7", "LEVEL 6" }

-- Palette: weathered, desaturated, lit by practical lights
local CONCRETE = Color3.fromRGB(108, 104, 98)
local CONCRETE_DARK = Color3.fromRGB(70, 68, 64)
local STEEL = Color3.fromRGB(88, 92, 96)
local STEEL_DARK = Color3.fromRGB(44, 46, 50)
local RUST = Color3.fromRGB(110, 70, 48)
local HAZARD = Color3.fromRGB(214, 168, 30)
local SODIUM = Color3.fromRGB(255, 176, 90)
local FLUORESCENT = Color3.fromRGB(214, 236, 255)
local WARM = Color3.fromRGB(255, 196, 140)
local EMERGENCY = Color3.fromRGB(255, 40, 30)
local DIRECTORATE = Color3.fromRGB(220, 30, 40)
local CYAN = Color3.fromRGB(80, 220, 255)
local GLASS_DARK = Color3.fromRGB(20, 24, 28)

local FACADE_TINTS = {
	Color3.fromRGB(122, 112, 98),
	Color3.fromRGB(96, 104, 108),
	Color3.fromRGB(118, 96, 84),
	Color3.fromRGB(86, 92, 82),
	Color3.fromRGB(130, 124, 112),
	Color3.fromRGB(104, 90, 92),
}
local CLOTH = {
	Color3.fromRGB(150, 60, 50),
	Color3.fromRGB(40, 90, 120),
	Color3.fromRGB(170, 140, 70),
	Color3.fromRGB(70, 110, 70),
	Color3.fromRGB(120, 120, 128),
	Color3.fromRGB(150, 100, 60),
}

local rng = Random.new(2087)

local function at(x: number, y: number, z: number): Vector3
	return O + Vector3.new(x, y, z)
end

-- Frame on the Well wall: origin at radius r, angle a (radians), height y.
-- X runs along the wall, Y up, and the front (-Z, LookVector) faces the
-- Well centre: things in front of a wall sit at negative local Z.
local function wallFrame(angle: number, radius: number, y: number): CFrame
	local position = at(math.cos(angle) * radius, y, math.sin(angle) * radius)
	local inward = Vector3.new(-math.cos(angle), 0, -math.sin(angle))
	return CFrame.lookAt(position, position + inward)
end

-- Yaw for Kit terminals so their screen faces from `from` toward `to`.
local function yawToward(from: Vector3, to: Vector3): number
	local d = to - from
	return math.atan2(-d.X, -d.Z)
end

local function part(
	parent: Instance,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material?
): Part
	return newPart(parent, name, size, cf, color, material)
end

local function prop(
	parent: Instance,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material?
): Part
	local p = newPart(parent, name, size, cf, color, material)
	decor(p)
	return p
end

local function heat(p: BasePart, temperature: number)
	p:SetAttribute("Temperature", temperature)
	CollectionService:AddTag(p, "Heat")
end

local function flicker(p: BasePart, mode: string?)
	p:SetAttribute("FlickerMode", mode or "Fault")
	CollectionService:AddTag(p, "Flicker")
end

-- A ceiling fixture: thin lit tube + SurfaceLight pointing down.
local function tube(
	parent: Instance,
	position: Vector3,
	yaw: number,
	color: Color3,
	on: boolean
): Part
	local fixture = prop(
		parent,
		"Tube",
		Vector3.new(4, 0.25, 0.5),
		CFrame.new(position) * CFrame.Angles(0, yaw, 0),
		if on then color else Color3.fromRGB(60, 62, 64),
		if on then Enum.Material.Neon else Enum.Material.SmoothPlastic
	)
	if on then
		local glow = Instance.new("SurfaceLight")
		glow.Face = Enum.NormalId.Bottom
		glow.Color = color
		glow.Range = 18
		glow.Angle = 120
		glow.Brightness = 1.4
		glow.Shadows = false
		glow.Parent = fixture
	end
	return fixture
end

-- High-bay sodium lamp hanging on a cable.
local function highBay(
	parent: Instance,
	position: Vector3,
	range: number,
	brightness: number,
	shadows: boolean
)
	-- Hang the lamp from the dome: cable runs up to the rock overhead
	local horizontal = (position - O) * Vector3.new(1, 0, 1)
	local ceiling = 150 + math.sqrt(math.max(0, WELL_RADIUS ^ 2 - horizontal.Magnitude ^ 2))
	local length = math.max(8, ceiling - (position.Y - O.Y))
	local cable = prop(
		parent,
		"Cable",
		Vector3.new(0.12, length, 0.12),
		CFrame.new(position + Vector3.new(0, 0.6 + length / 2, 0)),
		STEEL_DARK,
		Enum.Material.Metal
	)
	cable.CastShadow = false
	local shade = prop(
		parent,
		"Shade",
		Vector3.new(2.6, 1, 2.6),
		CFrame.new(position + Vector3.new(0, 0.5, 0)),
		STEEL_DARK,
		Enum.Material.Metal
	)
	shade.Shape = Enum.PartType.Cylinder
	shade.CFrame = CFrame.new(position + Vector3.new(0, 0.5, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	local bulb = prop(
		parent,
		"Bulb",
		Vector3.new(1.4, 0.4, 1.4),
		CFrame.new(position),
		SODIUM,
		Enum.Material.Neon
	)
	local spot = Instance.new("SpotLight")
	spot.Face = Enum.NormalId.Bottom
	spot.Angle = 100
	spot.Range = range
	spot.Brightness = brightness
	spot.Color = SODIUM
	spot.Shadows = shadows
	spot.Parent = bulb
	return bulb
end

local function signage(
	parent: Instance,
	cf: CFrame,
	size: Vector2,
	text: string,
	textColor: Color3,
	backColor: Color3?,
	font: Enum.Font?
): Part
	local board = prop(
		parent,
		"Sign",
		Vector3.new(size.X, size.Y, 0.15),
		cf,
		backColor or Color3.fromRGB(28, 28, 30),
		Enum.Material.SmoothPlastic
	)
	if not backColor then
		board.Transparency = 1
	end
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0.6
	gui.Parent = board
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.Size = UDim2.new(1, -16, 1, -8)
	label.Position = UDim2.fromOffset(8, 4)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = textColor
	label.TextScaled = true
	label.Font = font or Enum.Font.SourceSansBold
	label.Parent = gui
	return board
end

local function particles(parentPart: BasePart, kind: string): ParticleEmitter
	local emitter = Instance.new("ParticleEmitter")
	if kind == "Steam" then
		emitter.Texture = "rbxasset://textures/particles/smoke_main.dds"
		emitter.Color = ColorSequence.new(Color3.fromRGB(200, 200, 196))
		emitter.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.2, 0.75),
			NumberSequenceKeypoint.new(1, 1),
		})
		emitter.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 2),
			NumberSequenceKeypoint.new(1, 9),
		})
		emitter.Lifetime = NumberRange.new(4, 7)
		emitter.Rate = 6
		emitter.Speed = NumberRange.new(4, 7)
		emitter.SpreadAngle = Vector2.new(12, 12)
		emitter.LightInfluence = 0.9
		emitter.RotSpeed = NumberRange.new(-20, 20)
		emitter.Rotation = NumberRange.new(0, 360)
	elseif kind == "Drip" then
		emitter.Color = ColorSequence.new(Color3.fromRGB(150, 160, 150))
		emitter.Transparency = NumberSequence.new(0.35)
		emitter.Size = NumberSequence.new(0.08)
		emitter.Lifetime = NumberRange.new(1.2, 1.8)
		emitter.Rate = 1.5
		emitter.Speed = NumberRange.new(0)
		emitter.Acceleration = Vector3.new(0, -50, 0)
		emitter.LightInfluence = 1
		emitter.EmissionDirection = Enum.NormalId.Bottom
	elseif kind == "Dust" then
		emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		emitter.Color = ColorSequence.new(Color3.fromRGB(255, 240, 220))
		emitter.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0.7),
			NumberSequenceKeypoint.new(1, 1),
		})
		emitter.Size = NumberSequence.new(0.12)
		emitter.Lifetime = NumberRange.new(8, 14)
		emitter.Rate = 14
		emitter.Speed = NumberRange.new(0.2, 0.8)
		emitter.SpreadAngle = Vector2.new(180, 180)
		emitter.Acceleration = Vector3.new(0, -0.05, 0)
		emitter.LightInfluence = 1
		emitter.Shape = Enum.ParticleEmitterShape.Box
	elseif kind == "Spores" then
		emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		emitter.Color = ColorSequence.new(Color3.fromRGB(200, 220, 190))
		emitter.Transparency = NumberSequence.new(0.8)
		emitter.Size = NumberSequence.new(0.07)
		emitter.Lifetime = NumberRange.new(6, 10)
		emitter.Rate = 10
		emitter.Speed = NumberRange.new(0.1, 0.4)
		emitter.SpreadAngle = Vector2.new(180, 180)
		emitter.LightInfluence = 1
		emitter.Shape = Enum.ParticleEmitterShape.Box
	end
	emitter.Parent = parentPart
	return emitter
end

-- An invisible volume used as an emitter shape, air zone, relay zone...
local function volume(parent: Instance, name: string, center: Vector3, size: Vector3): Part
	local v =
		newPart(parent, name, size, CFrame.new(center), Color3.new(), Enum.Material.SmoothPlastic)
	v.Transparency = 1
	v.CanCollide = false
	v.CanQuery = false
	v.CanTouch = false
	v.CastShadow = false
	return v
end

---------------------------------------------------------------------------
-- People. Proportioned figures; the sick lie in bed under blankets.
---------------------------------------------------------------------------

-- People are R15 Roblox characters (Characters.luau). `cf` is the hip centre.
-- pose: "Stand" | "Sit" | "Lie"
local function person(
	parent: Instance,
	name: string,
	cf: CFrame,
	shirt: Color3,
	pose: string,
	mobile: boolean?
): Model
	return Characters.spawn(parent, name, { pose = pose, cf = cf, shirt = shirt, mobile = mobile })
end

local function bed(parent: Instance, cf: CFrame, blanket: Color3?): CFrame
	part(
		parent,
		"BedFrame",
		Vector3.new(3.4, 1.4, 7),
		cf * CFrame.new(0, 0.7, 0),
		STEEL_DARK,
		Enum.Material.Metal
	)
	part(
		parent,
		"Mattress",
		Vector3.new(3.2, 0.6, 6.8),
		cf * CFrame.new(0, 1.7, 0),
		Color3.fromRGB(150, 146, 136),
		Enum.Material.Fabric
	)
	prop(
		parent,
		"Pillow",
		Vector3.new(2.2, 0.4, 1.1),
		cf * CFrame.new(0, 2.1, 2.7),
		Color3.fromRGB(196, 192, 182),
		Enum.Material.Fabric
	)
	if blanket then
		prop(
			parent,
			"Blanket",
			Vector3.new(3.3, 0.5, 4.4),
			cf * CFrame.new(0, 2.3, -1.1),
			blanket,
			Enum.Material.Fabric
		)
	end
	-- Where a lying figure's hips go (head toward the pillow)
	return cf * CFrame.new(0, 2.4, 0.4)
end

local function bunk(parent: Instance, cf: CFrame)
	for _, x in { -1.6, 1.6 } do
		for _, z in { -3.3, 3.3 } do
			part(
				parent,
				"Post",
				Vector3.new(0.25, 7, 0.25),
				cf * CFrame.new(x, 3.5, z),
				STEEL_DARK,
				Enum.Material.Metal
			)
		end
	end
	for _, y in { 1.4, 4.6 } do
		part(
			parent,
			"Bunk",
			Vector3.new(3.4, 0.5, 6.8),
			cf * CFrame.new(0, y, 0),
			Color3.fromRGB(130, 124, 114),
			Enum.Material.Fabric
		)
		prop(
			parent,
			"Blanket",
			Vector3.new(3.2, 0.3, 3.4),
			cf * CFrame.new(0, y + 0.4, -1.4),
			CLOTH[rng:NextInteger(1, #CLOTH)],
			Enum.Material.Fabric
		)
	end
end

local function crate(parent: Instance, cf: CFrame, size: Vector3?)
	local s = size or Vector3.new(3, 2.4, 3)
	local c = part(
		parent,
		"Crate",
		s,
		cf * CFrame.new(0, s.Y / 2, 0),
		Color3.fromRGB(96, 82, 60),
		Enum.Material.WoodPlanks
	)
	return c
end

local function barrel(parent: Instance, position: Vector3, color: Color3, fire: boolean)
	local b = cylinder(
		parent,
		"Barrel",
		3,
		2.2,
		position + Vector3.new(0, 1.5, 0),
		"Y",
		color,
		Enum.Material.CorrodedMetal
	)
	if fire then
		local flame = Instance.new("Fire")
		flame.Heat = 6
		flame.Size = 3
		flame.Color = Color3.fromRGB(255, 140, 50)
		flame.SecondaryColor = Color3.fromRGB(200, 40, 10)
		flame.Parent = b
		local glow = light(b, Color3.fromRGB(255, 130, 60), 22, 1.6)
		glow.Shadows = true
		glow.Name = "FireLight"
		flicker(b, "Fire")
		heat(b, 180)
	end
	return b
end

---------------------------------------------------------------------------
-- Terrain: rock shell, the Well, rooms, sewer, surface
---------------------------------------------------------------------------

-- Terrain edits are split into <=128-stud blocks: very large single
-- FillBlock regions can be rejected by the engine.
local function carveBlock(center: Vector3, size: Vector3, material: Enum.Material?)
	local fill = material or Enum.Material.Air
	local chunk = 128
	local counts =
		Vector3.new(math.ceil(size.X / chunk), math.ceil(size.Y / chunk), math.ceil(size.Z / chunk))
	local step = Vector3.new(size.X / counts.X, size.Y / counts.Y, size.Z / counts.Z)
	local min = O + center - size / 2
	for ix = 0, counts.X - 1 do
		for iy = 0, counts.Y - 1 do
			for iz = 0, counts.Z - 1 do
				local cellCenter = min
					+ Vector3.new((ix + 0.5) * step.X, (iy + 0.5) * step.Y, (iz + 0.5) * step.Z)
				Terrain:FillBlock(CFrame.new(cellCenter), step, fill)
			end
		end
	end
end

local function buildTerrain()
	Terrain.WaterColor = Color3.fromRGB(46, 52, 34)
	Terrain.WaterTransparency = 0.12
	Terrain.WaterReflectance = 0.35
	Terrain.WaterWaveSize = 0.04
	Terrain.WaterWaveSpeed = 6

	-- Solid shell from the sewer up to the surface
	carveBlock(Vector3.new(0, 175, 10), Vector3.new(500, 510, 520), Enum.Material.Rock)
	-- Strata near the deep levels
	carveBlock(Vector3.new(0, -20, 10), Vector3.new(500, 60, 520), Enum.Material.Slate)
	-- Surface soil, grass coming back
	carveBlock(Vector3.new(0, 418, 10), Vector3.new(500, 8, 520), Enum.Material.Ground)
	carveBlock(Vector3.new(0, 426, 10), Vector3.new(500, 8, 520), Enum.Material.Grass)
	for _ = 1, 18 do
		local x, z = rng:NextNumber(-220, 220), rng:NextNumber(-220, 240)
		if math.abs(x) > 30 or math.abs(z) > 30 then
			Terrain:FillBall(at(x, 430, z), rng:NextNumber(8, 22), Enum.Material.LeafyGrass)
		end
	end
	for _ = 1, 8 do
		Terrain:FillBall(
			at(rng:NextNumber(-200, 200), 431, rng:NextNumber(-200, 220)),
			rng:NextNumber(6, 14),
			Enum.Material.Mud
		)
	end

	-- The Well and its dome
	-- Smooth terrain carves come out about one voxel (4 studs) tighter than the
	-- requested radius, so round carves are padded by VOXEL_PAD
	Terrain:FillCylinder(CFrame.new(at(0, 80, 0)), 160, WELL_RADIUS + VOXEL_PAD, Enum.Material.Air)
	Terrain:FillBall(at(0, 150, 0), WELL_RADIUS + VOXEL_PAD, Enum.Material.Air)
	-- Lift Shaft Zero up to the surface
	carveBlock(Vector3.new(0, 336, 0), Vector3.new(26, 196, 26))

	-- Rooms cut into the walls
	carveBlock(Vector3.new(123, 52, 0), Vector3.new(74, 24, 52)) -- Ops Hub (L8 east)
	carveBlock(Vector3.new(-133, 15, 0), Vector3.new(86, 30, 80)) -- Quarantine Q-9 (L9 west)
	carveBlock(Vector3.new(0, 94, 112), Vector3.new(60, 28, 50)) -- Scrubber hall (L7 south)
	carveBlock(Vector3.new(0, 92, -106), Vector3.new(50, 24, 36)) -- Clinic (L7 north)
	carveBlock(Vector3.new(-112, 132, 0), Vector3.new(50, 24, 70)) -- Farm (L6 west)

	-- Collector C-2: a brick-lined tunnel along x under the Pit
	local tunnelCf = CFrame.new(at(0, -26, 60)) * CFrame.Angles(0, 0, math.pi / 2)
	Terrain:FillCylinder(tunnelCf, 400, 19 + VOXEL_PAD, Enum.Material.Brick)
	Terrain:FillCylinder(tunnelCf, 400, 16 + VOXEL_PAD, Enum.Material.Air)
	carveBlock(Vector3.new(-60, -22, 60), Vector3.new(30, 30, 44)) -- pump room
	carveBlock(Vector3.new(-60, -4, 60), Vector3.new(10, 10, 10)) -- exhaust shaft to the Pit
	carveBlock(Vector3.new(0, -4, 64), Vector3.new(80, 8, 48)) -- Underpass Market
	carveBlock(Vector3.new(0, -9, 64), Vector3.new(12, 8, 12)) -- breach into the sewer
end

---------------------------------------------------------------------------
-- Flood water (terrain) for Collector C-2 + the Underpass
---------------------------------------------------------------------------

type WaterBody = {
	min: Vector2, -- x, z
	max: Vector2,
	bottom: number,
	high: number,
	low: number,
	level: number,
	target: number,
	running: boolean,
}

-- Collector C-2 is surcharged (half full); the Underpass Market is flooded
-- by backflow through the breach. Both drain as the operation progresses.
local TUNNEL: WaterBody = {
	min = Vector2.new(-204, 40),
	max = Vector2.new(204, 84),
	bottom = -44,
	high = -28,
	low = -40,
	level = -44,
	target = -28,
	running = false,
}
local UNDERPASS: WaterBody = {
	min = Vector2.new(-40, 40),
	max = Vector2.new(40, 88),
	bottom = -8,
	high = -4,
	low = -8,
	level = -8,
	target = -4,
	running = false,
}

local function waterSlab(body: WaterBody, y0: number, y1: number): Region3
	local min = at(body.min.X, y0, body.min.Y)
	local max = at(body.max.X, y1, body.max.Y)
	return Region3.new(min, max):ExpandToGrid(4)
end

local function runWater(body: WaterBody)
	if body.running then
		return
	end
	body.running = true
	task.spawn(function()
		while body.level ~= body.target do
			if body.level < body.target then
				Terrain:ReplaceMaterial(
					waterSlab(body, body.level, body.level + 4),
					4,
					Enum.Material.Air,
					Enum.Material.Water
				)
				body.level += 4
			else
				Terrain:ReplaceMaterial(
					waterSlab(body, body.level - 4, body.level),
					4,
					Enum.Material.Water,
					Enum.Material.Air
				)
				body.level -= 4
			end
			task.wait(1.2)
		end
		body.running = false
	end)
end

local function fillNow(body: WaterBody)
	Terrain:ReplaceMaterial(
		waterSlab(body, body.bottom, body.high),
		4,
		Enum.Material.Air,
		Enum.Material.Water
	)
	body.level = body.high
	body.target = body.high
end

-- progress 0 (flooded) .. 1 (drained). Returns the tunnel level.
local function setWater(progress: number): number
	for _, body in { TUNNEL, UNDERPASS } do
		local level = body.high + (body.low - body.high) * progress
		body.target = math.clamp(math.floor((level + 2) / 4) * 4, body.low, body.high)
		runWater(body)
	end
	Workspace:SetAttribute("UnderpassFlooded", UNDERPASS.target > UNDERPASS.low)
	return TUNNEL.target
end

---------------------------------------------------------------------------
-- Floors: the Pit floor (L9) and the Deck (L8) as plate grids
---------------------------------------------------------------------------

type Cell = { x: number, z: number }

local function plateGrid(
	parent: Instance,
	name: string,
	y: number,
	color: Color3,
	material: Enum.Material,
	skip: (number, number) -> boolean,
	vents: { Cell }?
)
	local isVent: { [string]: boolean } = {}
	for _, cell in (vents or {}) :: { Cell } do
		isVent[cell.x .. "," .. cell.z] = true
	end
	for ix = -6, 5 do
		for iz = -6, 5 do
			local x, z = ix * 16 + 8, iz * 16 + 8
			if math.sqrt(x * x + z * z) <= WELL_RADIUS + 10 and not skip(x, z) then
				if isVent[x .. "," .. z] then
					-- Plate with a 7x7 hole, hazard frame and a half-broken grate
					for _, piece in Kit.solids(-8, 8, -8, 8, { Kit.rect(-3.5, 3.5, -3.5, 3.5) }) do
						part(
							parent,
							name,
							Vector3.new(piece.a1 - piece.a0, 1.5, piece.b1 - piece.b0),
							CFrame.new(
								at(
									x + (piece.a0 + piece.a1) / 2,
									y - 0.75,
									z + (piece.b0 + piece.b1) / 2
								)
							),
							color,
							material
						)
					end
					for _, edge in
						{
							{ 0, -3.7, 7.6, 0.4 },
							{ 0, 3.7, 7.6, 0.4 },
							{ -3.7, 0, 0.4, 7.6 },
							{ 3.7, 0, 0.4, 7.6 },
						}
					do
						prop(
							parent,
							"VentFrame",
							Vector3.new(edge[3], 0.1, edge[4]),
							CFrame.new(at(x + edge[1], y + 0.02, z + edge[2])),
							HAZARD,
							Enum.Material.SmoothPlastic
						)
					end
					for i = 0, 1 do
						part(
							parent,
							"GrateBar",
							Vector3.new(0.3, 0.3, 7),
							CFrame.new(at(x - 3 + i * 0.9, y - 0.4, z))
								* CFrame.Angles(0.25 * i, 0, 0),
							RUST,
							Enum.Material.CorrodedMetal
						)
					end
					signage(
						parent,
						CFrame.new(at(x, y + 0.03, z + 5.9)) * CFrame.Angles(math.pi / 2, 0, 0),
						Vector2.new(9, 1.5),
						"SERVICE VENT · DRONE ACCESS",
						HAZARD,
						nil,
						Enum.Font.Code
					)
				else
					part(
						parent,
						name,
						Vector3.new(16, 1.5, 16),
						CFrame.new(at(x, y - 0.75, z)),
						color,
						material
					)
				end
			end
		end
	end
end

---------------------------------------------------------------------------
-- Facades around the Well: apartments stacked into the rock
---------------------------------------------------------------------------

local SEGMENTS = 20

type FacadeOptions = {
	lit: number, -- 0..1 share of windows lit
	opening: { number }?, -- {width, height} of a big central opening (room entrance)
	dark: boolean?,
}

local function facade(
	parent: Instance,
	angle: number,
	y: number,
	height: number,
	options: FacadeOptions
)
	local width = 2 * WELL_RADIUS * math.sin(math.pi / SEGMENTS) + 1.2
	local frame = wallFrame(angle, WELL_RADIUS - 1.4, y)
	local tint = FACADE_TINTS[rng:NextInteger(1, #FACADE_TINTS)]

	local holes = {}
	local windows = {}
	local floors = math.floor(height / 12)
	if options.opening then
		local w, h = options.opening[1], options.opening[2]
		table.insert(holes, Kit.rect(-w / 2, w / 2, 0.5, h))
	end
	for storey = 0, floors - 1 do
		local base = storey * 12
		for slot = -2, 2 do
			local cx = slot * (width / 5)
			local blocked = false
			if options.opening then
				local w, h = options.opening[1], options.opening[2]
				blocked = math.abs(cx) < w / 2 + 3 and base < h
			end
			if not blocked then
				if slot == 0 and storey == 0 then
					table.insert(holes, Kit.rect(cx - 1.6, cx + 1.6, 0.5, 7.5)) -- door
					table.insert(windows, { cx, 4, 3.2, 7, 1 })
				else
					table.insert(holes, Kit.rect(cx - 2, cx + 2, base + 4, base + 8))
					table.insert(windows, { cx, base + 6, 4, 4, 0 })
				end
			end
		end
	end

	for _, piece in Kit.solids(-width / 2, width / 2, 0, height, holes) do
		part(
			parent,
			"Facade",
			Vector3.new(piece.a1 - piece.a0, piece.b1 - piece.b0, 1.2),
			frame * CFrame.new((piece.a0 + piece.a1) / 2, (piece.b0 + piece.b1) / 2, 0),
			tint,
			Enum.Material.Concrete
		)
	end
	-- Floor slabs/ledges between storeys, with a darker band
	for storey = 1, floors - 1 do
		prop(
			parent,
			"Ledge",
			Vector3.new(width, 0.8, 1.8),
			frame * CFrame.new(0, storey * 12, -0.6),
			CONCRETE_DARK,
			Enum.Material.Concrete
		)
	end

	for _, w in windows do
		local isDoor = w[5] == 1
		local lit = not options.dark and rng:NextNumber() < options.lit
		local pane = prop(
			parent,
			if isDoor then "Door" else "Window",
			Vector3.new(w[3], w[4], 0.3),
			frame * CFrame.new(w[1], w[2], 0.45),
			if isDoor then Color3.fromRGB(58, 52, 46) elseif lit then WARM else GLASS_DARK,
			if isDoor then Enum.Material.Metal else Enum.Material.Glass
		)
		if lit and not isDoor then
			pane.Material = Enum.Material.Neon
			pane.Transparency = 0.55
			local glow = Instance.new("SurfaceLight")
			glow.Face = Enum.NormalId.Front
			glow.Color = if rng:NextNumber() < 0.3 then FLUORESCENT else WARM
			glow.Range = 10
			glow.Angle = 80
			glow.Brightness = 0.8
			glow.Parent = pane
			if rng:NextNumber() < 0.12 then
				flicker(pane, "Fault")
			end
			-- Curtains and clutter visible through the glass
			if rng:NextNumber() < 0.6 then
				prop(
					parent,
					"Curtain",
					Vector3.new(w[3] * 0.45, w[4], 0.1),
					frame * CFrame.new(w[1] + w[3] * 0.28, w[2], 0.75),
					CLOTH[rng:NextInteger(1, #CLOTH)],
					Enum.Material.Fabric
				)
			end
		end
		if not isDoor and rng:NextNumber() < 0.25 then
			-- AC unit / vent box under the window
			local ac = prop(
				parent,
				"ACUnit",
				Vector3.new(2.4, 1.6, 1.4),
				frame * CFrame.new(w[1] + 0.6, w[2] - 3, -0.9),
				Color3.fromRGB(150, 148, 140),
				Enum.Material.Metal
			)
			heat(ac, 41)
		end
		if not isDoor and rng:NextNumber() < 0.2 then
			-- laundry line
			prop(
				parent,
				"Line",
				Vector3.new(5, 0.05, 0.05),
				frame * CFrame.new(w[1], w[2] - 2.4, -2.5),
				STEEL_DARK
			)
			for i = 1, 3 do
				prop(
					parent,
					"Laundry",
					Vector3.new(0.9, 1.4, 0.06),
					frame * CFrame.new(w[1] - 2 + i * 1.1, w[2] - 3.2, -2.5),
					CLOTH[rng:NextInteger(1, #CLOTH)],
					Enum.Material.Fabric
				)
			end
		end
	end

	-- Utilities: a drain pipe and a cable bundle per segment
	local pipe = cylinder(
		parent,
		"Downpipe",
		height,
		0.8,
		(frame * CFrame.new(width / 2 - 1.2, height / 2, -0.8)).Position,
		"Y",
		RUST,
		Enum.Material.CorrodedMetal
	)
	decor(pipe)
	local conduit = prop(
		parent,
		"Conduit",
		Vector3.new(width, 0.5, 0.5),
		frame * CFrame.new(0, height - 1.5, -0.9),
		STEEL_DARK,
		Enum.Material.Metal
	)
	conduit.Shape = Enum.PartType.Cylinder
	conduit.CFrame = frame * CFrame.new(0, height - 1.5, -0.9)
end

local function gallery(parent: Instance, y: number, skipAngles: { number }?)
	local width = 2 * 83 * math.sin(math.pi / SEGMENTS) + 0.8
	for i = 0, SEGMENTS - 1 do
		local angle = (i + 0.5) / SEGMENTS * math.pi * 2
		local frame = wallFrame(angle, 83, y)
		part(
			parent,
			"Walkway",
			Vector3.new(width, 1.2, 18),
			frame * CFrame.new(0, -0.6, 0),
			CONCRETE_DARK,
			Enum.Material.Concrete
		)
		-- Underside beams
		prop(
			parent,
			"Beam",
			Vector3.new(0.8, 1.6, 18),
			frame * CFrame.new(width / 2 - 0.4, -2, 0),
			STEEL_DARK,
			Enum.Material.Metal
		)
		local skip = false
		for _, a in (skipAngles or {}) :: { number } do
			local d = math.abs(((angle - a + math.pi) % (2 * math.pi)) - math.pi)
			if d < 0.18 then
				skip = true
			end
		end
		if not skip then
			-- Railing at the inner edge
			local edge = frame * CFrame.new(0, 0, -8.6)
			part(
				parent,
				"Rail",
				Vector3.new(width, 0.2, 0.2),
				edge * CFrame.new(0, 3.4, 0),
				RUST,
				Enum.Material.Metal
			)
			prop(
				parent,
				"Rail",
				Vector3.new(width, 0.12, 0.12),
				edge * CFrame.new(0, 1.8, 0),
				RUST,
				Enum.Material.Metal
			)
			for p = -1, 1 do
				prop(
					parent,
					"Post",
					Vector3.new(0.2, 3.4, 0.2),
					edge * CFrame.new(p * width / 3, 1.7, 0),
					RUST,
					Enum.Material.Metal
				)
			end
		end
		if i % 2 == 0 then
			-- Ceiling tubes on the underside of the next gallery up
			tube(
				parent,
				(frame * CFrame.new(0, 33.5, 2)).Position,
				angle,
				FLUORESCENT,
				rng:NextNumber() < 0.8
			)
		end
	end
end

---------------------------------------------------------------------------
-- Devices specific to the Hollow
---------------------------------------------------------------------------

local function breaker(parent: Instance, cf: CFrame, label: string, group: string): Model
	local model = newModel(parent, "Breaker")
	local body = part(
		model,
		"Body",
		Vector3.new(3, 4, 1),
		cf,
		Color3.fromRGB(70, 74, 64),
		Enum.Material.Metal
	)
	prop(model, "Stripe", Vector3.new(3.05, 0.4, 1.05), cf * CFrame.new(0, 1.6, 0), HAZARD)
	prop(
		model,
		"Handle",
		Vector3.new(0.4, 1.4, 0.4),
		cf * CFrame.new(0.8, -0.2, -0.7),
		Color3.fromRGB(30, 30, 30),
		Enum.Material.Metal
	)
	local lamp = ball(
		model,
		"StatusLamp",
		0.5,
		(cf * CFrame.new(-0.9, 0.8, -0.55)).Position,
		Color3.fromRGB(255, 50, 50),
		Enum.Material.Neon
	)
	decor(lamp)
	light(lamp, Color3.fromRGB(255, 50, 50), 6, 0.8)
	signage(
		model,
		cf * CFrame.new(0, 2.6, -0.55),
		Vector2.new(3, 0.9),
		label,
		Color3.fromRGB(230, 230, 220),
		Color3.fromRGB(30, 32, 30),
		Enum.Font.Code
	)
	model.PrimaryPart = body
	device(
		model,
		"Breaker",
		label,
		{ On = false, Status = "OFF", VentGroup = group, Temperature = 31 }
	)
	return model
end

local function fan(
	parent: Instance,
	center: Vector3,
	diameter: number,
	axisUp: boolean,
	group: string
)
	local housing = cylinder(
		parent,
		"FanHousing",
		1.6,
		diameter + 1.2,
		center,
		if axisUp then "Y" else "Z",
		STEEL_DARK,
		Enum.Material.Metal
	)
	housing.Transparency = 0
	local hub = cylinder(
		parent,
		"FanHub",
		1.8,
		diameter * 0.2,
		center,
		if axisUp then "Y" else "Z",
		STEEL,
		Enum.Material.Metal
	)
	decor(hub)
	-- Blades on a single part rotating about its local Y
	local orient = if axisUp then CFrame.identity else CFrame.Angles(math.pi / 2, 0, 0)
	local blades = prop(
		parent,
		"FanBlades",
		Vector3.new(diameter * 0.95, 0.2, diameter * 0.18),
		CFrame.new(center) * orient,
		Color3.fromRGB(64, 66, 70),
		Enum.Material.Metal
	)
	local blades2 = prop(
		parent,
		"FanBlades",
		Vector3.new(diameter * 0.18, 0.2, diameter * 0.95),
		CFrame.new(center) * orient,
		Color3.fromRGB(64, 66, 70),
		Enum.Material.Metal
	)
	for _, b in { blades, blades2 } do
		b:SetAttribute("VentGroup", group)
		b:SetAttribute("Running", false)
		CollectionService:AddTag(b, "Fan")
	end
	-- Grille
	for i = -2, 2 do
		prop(
			parent,
			"Grille",
			if axisUp then Vector3.new(diameter, 0.1, 0.12) else Vector3.new(diameter, 0.12, 0.1),
			CFrame.new(center) * orient * CFrame.new(0, 1, i * diameter / 5),
			STEEL,
			Enum.Material.Metal
		)
	end
end

local function equipment(
	model: Model,
	label: string,
	temperature: number,
	diagnostic: string,
	verdict: string,
	severity: string
)
	device(model, "Equipment", label, {
		Temperature = temperature,
		Diagnostic = diagnostic,
		Verdict = verdict,
		Severity = severity,
		Objective = "HSurvey",
		Status = "NOT SURVEYED",
	})
end

local function publicScreen(parent: Instance, cf: CFrame, size: Vector2, label: string)
	local model = newModel(parent, "PublicScreen")
	local frameColor = Color3.fromRGB(26, 26, 28)
	part(
		model,
		"Bezel",
		Vector3.new(size.X + 0.8, size.Y + 0.8, 0.8),
		cf * CFrame.new(0, 0, 0.45),
		frameColor,
		Enum.Material.Metal
	)
	local panel = part(
		model,
		"Panel",
		Vector3.new(size.X, size.Y, 0.2),
		cf,
		Color3.fromRGB(40, 6, 8),
		Enum.Material.SmoothPlastic
	)
	local glow = Instance.new("SurfaceLight")
	glow.Face = Enum.NormalId.Front
	glow.Color = Color3.fromRGB(255, 70, 60)
	glow.Range = 24
	glow.Angle = 90
	glow.Brightness = 1.2
	glow.Parent = panel
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 30
	gui.LightInfluence = 0
	gui.Brightness = 1.4
	gui.Parent = panel
	local header = Instance.new("TextLabel")
	header.Name = "Header"
	header.BackgroundColor3 = DIRECTORATE
	header.BorderSizePixel = 0
	header.Size = UDim2.fromScale(1, 0.14)
	header.Text = "◆ THE DIRECTORATE OF THE HOLLOW ◆"
	header.TextColor3 = Color3.new(1, 1, 1)
	header.TextScaled = true
	header.Font = Enum.Font.SourceSansBold
	header.Parent = gui
	local text = Instance.new("TextLabel")
	text.Name = "Text"
	text.BackgroundTransparency = 1
	text.Position = UDim2.fromScale(0.04, 0.17)
	text.Size = UDim2.fromScale(0.92, 0.8)
	text.TextColor3 = Color3.fromRGB(255, 210, 200)
	text.TextScaled = true
	text.Font = Enum.Font.SourceSansSemibold
	text.Text =
		"SURFACE AIR IS LETHAL WITHIN MINUTES\n\nLUNG SICKNESS: 3 CASES — CONTAINED\n\nLEVEL 9 SEALED FOR YOUR SAFETY\n\nCOMPLIANCE IS SURVIVAL"
	text.Parent = gui
	model.PrimaryPart = panel
	device(model, "PublicScreen", label, { Status = "DIRECTORATE FEED", Temperature = 38 })
	CollectionService:AddTag(model, "PublicScreen")
	return model
end

local function airZone(
	parent: Instance,
	center: Vector3,
	size: Vector3,
	attributes: { [string]: any }
)
	local zone = volume(parent, "AirZone", center, size)
	for key, value in attributes do
		zone:SetAttribute(key, value)
	end
	CollectionService:AddTag(zone, "AirZone")
end

local function resident(
	parent: Instance,
	name: string,
	condition: string,
	_legacyTemperature: number,
	cf: CFrame,
	pose: string,
	shirt: Color3
): Model
	local model = person(parent, "Resident", cf, shirt, pose)
	local sampled = Characters.temperature(condition)
	device(model, "Resident", name, {
		Condition = condition,
		Temperature = sampled,
		BaseTemperature = sampled,
		NeedsAid = condition ~= "Healthy",
		Located = false,
		Status = "UNIDENTIFIED",
		LocateObjective = "HLocated",
		TreatObjective = "HTreated",
	})
	return model
end

-- Background people (not devices): warm on thermal, no interaction
local function bystander(parent: Instance, cf: CFrame, pose: string)
	local model = person(parent, "Bystander", cf, CLOTH[rng:NextInteger(1, #CLOTH)], pose)
	local chest = Characters.chest(model)
	heat(chest, Characters.temperature("Healthy"))
	chest:SetAttribute("BaseTemperature", chest:GetAttribute("Temperature"))
end

---------------------------------------------------------------------------
-- Zones
---------------------------------------------------------------------------

local function buildWell(root: Folder)
	local folder = newModel(root, "TheWell")

	-- L9 floor (the Pit) and the Deck (L8)
	plateGrid(folder, "PitFloor", 0, CONCRETE_DARK, Enum.Material.Concrete, function(x, z)
		local underpass = x > -40 and x < 40 and z > 40 and z < 88
		local exhaust = x == -56 and z == 56
		return underpass or exhaust
	end)
	plateGrid(folder, "Deck", DECK_Y, STEEL, Enum.Material.DiamondPlate, function(x, z)
		local stairwell = x == 24 and (z == -72 or z == -56 or z == -40)
		return math.sqrt(x * x + z * z) < 14 or stairwell
	end, { { x = 8, z = -56 }, { x = -72, z = 8 }, { x = 56, z = 40 } })

	-- Deck underside: heavy girders and dead/emergency lights over the Pit
	for i = -5, 5 do
		local x = i * 16
		local half = math.sqrt(math.max(0, (WELL_RADIUS + 6) ^ 2 - x * x))
		part(
			folder,
			"Girder",
			Vector3.new(1.4, 3, half * 2),
			CFrame.new(at(x, DECK_Y - 3, 0)),
			STEEL_DARK,
			Enum.Material.Metal
		)
	end
	for _, p in { { -40, -30 }, { 30, -50 }, { 60, 10 }, { -20, 30 }, { -70, -40 }, { 20, 60 } } do
		local emergency = prop(
			folder,
			"EmergencyLamp",
			Vector3.new(1.2, 0.6, 1.2),
			CFrame.new(at(p[1], DECK_Y - 4.8, p[2])),
			EMERGENCY,
			Enum.Material.Neon
		)
		local glow = light(emergency, EMERGENCY, 34, 0.9)
		glow.Shadows = true
		flicker(emergency, "Pulse")
	end
	for _, p in { { 10, -20 }, { -50, 20 }, { 50, -30 } } do
		local t = tube(
			folder,
			at(p[1], DECK_Y - 4.6, p[2]),
			rng:NextNumber(0, math.pi),
			FLUORESCENT,
			true
		)
		flicker(t, "Fault")
	end
	local dripVolume = volume(folder, "Drips", at(0, DECK_Y - 5, 0), Vector3.new(150, 1, 150))
	particles(dripVolume, "Drip").Rate = 6

	-- Facades: L9 (dark, blackout) under the deck, lit levels above
	for i = 0, SEGMENTS - 1 do
		local angle = (i + 0.5) / SEGMENTS * math.pi * 2
		local deg = math.deg(angle)
		local westL9 = deg > 165 and deg < 195
		if not westL9 then
			facade(folder, angle, 0, 36, { lit = 0.08, dark = false })
		end
		local eastL8 = deg < 15 or deg > 345
		if not eastL8 then
			facade(folder, angle, DECK_Y, 36, { lit = 0.55 })
		end
		local northL7 = deg > 255 and deg < 285
		local southL7 = deg > 75 and deg < 105
		facade(
			folder,
			angle,
			80,
			36,
			{ lit = 0.65, opening = if northL7 or southL7 then { 20, 16 } else nil }
		)
		local westL6 = deg > 165 and deg < 195
		facade(folder, angle, 120, 36, { lit = 0.75, opening = if westL6 then { 22, 14 } else nil })
	end
	gallery(folder, 80, { 0 })
	gallery(folder, 120, { math.rad(270) })

	-- Level markers stencilled on the rock
	for index, y in LEVELS do
		for _, angle in { math.rad(45), math.rad(225) } do
			signage(
				folder,
				wallFrame(angle, WELL_RADIUS - 2.3, y + 31),
				Vector2.new(12, 3),
				LEVEL_NAMES[index],
				Color3.fromRGB(230, 222, 200),
				nil,
				Enum.Font.SourceSansBold
			)
		end
	end

	-- The Spire: Directorate tower up the middle of the Well
	local spire = newModel(folder, "Spire")
	cylinder(
		spire,
		"Core",
		212,
		20,
		at(0, 106, 0),
		"Y",
		Color3.fromRGB(58, 58, 62),
		Enum.Material.Concrete
	)
	for y = 20, 200, 30 do
		decor(cylinder(spire, "Band", 1.2, 21.2, at(0, y, 0), "Y", STEEL_DARK, Enum.Material.Metal))
		for k = 0, 3 do
			local a = k * math.pi / 2 + math.pi / 4
			local beaconLamp = prop(
				spire,
				"AviationLight",
				Vector3.new(0.7, 0.7, 0.7),
				CFrame.new(at(math.cos(a) * 10.6, y + 1.2, math.sin(a) * 10.6)),
				DIRECTORATE,
				Enum.Material.Neon
			)
			if y >= 140 then
				light(beaconLamp, DIRECTORATE, 10, 0.8)
			end
			flicker(beaconLamp, "Blink")
		end
	end
	for k = 0, 3 do
		local a = k * math.pi / 2 + math.pi / 4
		local position = at(math.cos(a) * 10.8, 96, math.sin(a) * 10.8)
		publicScreen(
			spire,
			CFrame.lookAt(position, position + Vector3.new(math.cos(a), 0, math.sin(a))),
			Vector2.new(15, 9),
			"Directorate screen S-" .. k
		)
		Kit.buildCamera(
			spire,
			at(math.cos(a + 0.4) * 11, 112, math.sin(a + 0.4) * 11),
			at(math.cos(a + 0.4) * 60, 60, math.sin(a + 0.4) * 60),
			"Spire camera " .. k
		)
	end

	-- Jammer array on the Spire facing the L7 east bridge
	local jammer = newModel(spire, "Jammer")
	local box = part(
		jammer,
		"Cabinet",
		Vector3.new(3, 5, 4),
		CFrame.new(at(11.6, 85.5, 0)),
		Color3.fromRGB(40, 36, 40),
		Enum.Material.Metal
	)
	heat(box, 72)
	local glow = prop(
		jammer,
		"Glow",
		Vector3.new(0.2, 3.6, 0.5),
		CFrame.new(at(13.15, 85.8, -1)),
		DIRECTORATE,
		Enum.Material.Neon
	)
	light(glow, DIRECTORATE, 14, 1.2)
	prop(
		jammer,
		"Glow",
		Vector3.new(0.2, 3.6, 0.5),
		CFrame.new(at(13.15, 85.8, 1)),
		DIRECTORATE,
		Enum.Material.Neon
	)
	part(
		jammer,
		"Cable",
		Vector3.new(0.7, 14, 0.7),
		CFrame.new(at(11.2, 95, 1.6)),
		Color3.fromRGB(20, 20, 20),
		Enum.Material.Rubber
	)
	signage(
		jammer,
		CFrame.new(at(13.2, 89, 0)) * CFrame.Angles(0, -math.pi / 2, 0),
		Vector2.new(4, 1),
		"DIR · SIGNAL DENIAL",
		Color3.fromRGB(255, 200, 200),
		DIRECTORATE,
		Enum.Font.Code
	)
	for k = 0, 5 do
		local a = k * math.pi / 3
		local mast = prop(
			spire,
			"Antenna",
			Vector3.new(0.3, 12, 0.3),
			CFrame.new(at(math.cos(a) * 9, 108, math.sin(a) * 9))
				* CFrame.Angles(math.cos(a) * 0.3, 0, -math.sin(a) * 0.3),
			STEEL,
			Enum.Material.Metal
		)
		mast.CastShadow = true
	end
	jammer.PrimaryPart = box
	device(jammer, "Jammer", "Directorate jammer array J-9", {
		Active = true,
		Status = "JAMMING ALL BANDS",
		Temperature = 72,
		JamRadius = 120,
		JamFactor = 0.4,
		Objective = "HJammer",
		CutText = "Jammer J-9 on the Spire is dark. The Well can talk again.",
	})
	CollectionService:AddTag(jammer, "Jammer")

	-- Bridges: L7 east to the Spire (to reach the jammer) and L6 north
	part(
		folder,
		"Bridge",
		Vector3.new(64, 1, 6),
		CFrame.new(at(42, 79.5, 0)),
		STEEL,
		Enum.Material.DiamondPlate
	)
	for side = -1, 1, 2 do
		prop(
			folder,
			"BridgeRail",
			Vector3.new(64, 0.2, 0.2),
			CFrame.new(at(42, 83, side * 3)),
			RUST,
			Enum.Material.Metal
		)
	end
	part(
		folder,
		"Bridge",
		Vector3.new(6, 1, 64),
		CFrame.new(at(0, 119.5, -42)),
		STEEL,
		Enum.Material.DiamondPlate
	)
	for side = -1, 1, 2 do
		prop(
			folder,
			"BridgeRail",
			Vector3.new(0.2, 0.2, 64),
			CFrame.new(at(side * 3, 123, -42)),
			RUST,
			Enum.Material.Metal
		)
	end

	-- Directorate "sun lamps": rings of sodium high-bays hung from the dome.
	-- (Roblox lights reach 60 studs, so they hang low over the upper levels.)
	for k = 0, 7 do
		local a = k * math.pi / 4
		highBay(folder, at(math.cos(a) * 52, 170, math.sin(a) * 52), 60, 3, k % 2 == 0)
	end
	for k = 0, 5 do
		local a = k * math.pi / 3 + 0.3
		highBay(folder, at(math.cos(a) * 62, 132, math.sin(a) * 62), 60, 2, false)
	end
	highBay(folder, at(0, 222, 26), 60, 1.6, false)
	local dust = volume(folder, "DustMotes", at(0, 120, 0), Vector3.new(150, 150, 150))
	particles(dust, "Dust").Rate = 40

	-- Hanging cables across the Well (catenaries as a few straight spans)
	for k = 0, 7 do
		local a = k * math.pi / 4 + 0.2
		local p1 = at(math.cos(a) * 88, 150 + (k % 3) * 8, math.sin(a) * 88)
		local mid = at(math.cos(a) * 44, 138 + (k % 3) * 8, math.sin(a) * 44)
		for _, pair in { { p1, mid }, { mid, at(0, 150, 0) } } do
			local length = (pair[2] - pair[1]).Magnitude
			local cable = prop(
				folder,
				"Cable",
				Vector3.new(0.25, 0.25, length),
				CFrame.lookAt((pair[1] + pair[2]) / 2, pair[2]),
				Color3.fromRGB(20, 20, 22),
				Enum.Material.Rubber
			)
			cable.CastShadow = true
		end
	end

	-- Deck checkpoint: the sealed lift to L9
	local checkpoint = newModel(folder, "Checkpoint")
	part(
		checkpoint,
		"LiftKiosk",
		Vector3.new(10, 14, 10),
		CFrame.new(at(-40, 47, -40)),
		Color3.fromRGB(64, 64, 68),
		Enum.Material.Metal
	)
	signage(
		checkpoint,
		CFrame.new(at(-34.9, 50, -40)) * CFrame.Angles(0, -math.pi / 2, 0),
		Vector2.new(9, 4),
		"LIFT TO LEVEL 9\nSEALED · QUARANTINE ORDER 2087-114",
		Color3.fromRGB(255, 220, 220),
		DIRECTORATE
	)
	for k = 0, 6 do
		part(
			checkpoint,
			"Barrier",
			Vector3.new(4, 2.4, 1),
			CFrame.new(at(-30 + k * 4.2, 41.2, -30)) * CFrame.Angles(0, 0.05 * k, 0),
			Color3.fromRGB(150, 140, 120),
			Enum.Material.Concrete
		)
		prop(
			checkpoint,
			"Stripe",
			Vector3.new(4.02, 0.5, 1.02),
			CFrame.new(at(-30 + k * 4.2, 41.8, -30)) * CFrame.Angles(0, 0.05 * k, 0),
			if k % 2 == 0 then DIRECTORATE else Color3.fromRGB(230, 230, 230)
		)
	end
	Kit.buildCamera(checkpoint, at(-36, 54.5, -36), at(-10, 40, -10), "Checkpoint camera")
end

local function buildPit(root: Folder)
	local folder = newModel(root, "ThePit")

	-- Shelters and stalls packed against the facades (crowding)
	for i = 0, 15 do
		local angle = (i + 0.25) / 16 * math.pi * 2
		local deg = math.deg(angle)
		if (deg > 160 and deg < 200) or (deg > 60 and deg < 120) then
			continue
		end
		local frame = wallFrame(angle, 78, 0)
		local tarp = CLOTH[rng:NextInteger(1, #CLOTH)]
		for _, x in { -3.6, 3.6 } do
			for _, z in { -3, 3 } do
				prop(
					folder,
					"Pole",
					Vector3.new(0.3, 7, 0.3),
					frame * CFrame.new(x, 3.5, z),
					STEEL_DARK,
					Enum.Material.Metal
				)
			end
		end
		part(
			folder,
			"Tarp",
			Vector3.new(8.4, 0.15, 7.4),
			frame * CFrame.new(0, 7.1, 0) * CFrame.Angles(0.12, 0, 0),
			tarp,
			Enum.Material.Fabric
		)
		prop(
			folder,
			"Hang",
			Vector3.new(8.4, 3.2, 0.1),
			frame * CFrame.new(0, 5.4, 3.7),
			tarp,
			Enum.Material.Fabric
		).Transparency =
			0.1
		crate(folder, frame * CFrame.new(rng:NextNumber(-2, 2), 0, rng:NextNumber(-2, 1)))
		if i % 3 == 0 then
			bystander(
				folder,
				frame * CFrame.new(1.5, 2, -4.5) * CFrame.Angles(0, math.pi, 0),
				"Sit"
			)
		elseif i % 3 == 1 then
			bystander(
				folder,
				frame * CFrame.new(-2, 2.2, -5) * CFrame.Angles(0, math.pi + 0.4, 0),
				"Stand"
			)
		end
		if i % 4 == 0 then
			local candle = prop(
				folder,
				"Lantern",
				Vector3.new(0.5, 0.8, 0.5),
				frame * CFrame.new(0, 2.8, 1),
				WARM,
				Enum.Material.Neon
			)
			local glow = light(candle, WARM, 12, 0.8)
			glow.Shadows = true
			flicker(candle, "Fire")
		end
	end
	for _, p in { { -30, -20 }, { 40, -40 }, { 10, 30 } } do
		barrel(folder, at(p[1], 0, p[2]), RUST, true)
		for k = 0, 2 do
			local a = k * 2.1
			bystander(
				folder,
				CFrame.lookAt(
					at(p[1] + math.cos(a) * 3.6, 2.2, p[2] + math.sin(a) * 3.6),
					at(p[1], 2.2, p[2])
				),
				"Stand"
			)
		end
	end

	-- Underpass Market (floods): sunken plaza with stalls, stairs down
	part(
		folder,
		"UnderpassFloor",
		Vector3.new(80, 1, 48),
		CFrame.new(at(0, -8.5, 64)),
		Color3.fromRGB(70, 66, 60),
		Enum.Material.Pavement
	)
	for k = 0, 5 do
		local x = -30 + k * 12
		local stall = CLOTH[rng:NextInteger(1, #CLOTH)]
		part(
			folder,
			"Counter",
			Vector3.new(7, 3, 2.5),
			CFrame.new(at(x, -6.5, 80)),
			Color3.fromRGB(90, 76, 58),
			Enum.Material.WoodPlanks
		)
		part(
			folder,
			"Awning",
			Vector3.new(8, 0.2, 5),
			CFrame.new(at(x, -1.4, 79)) * CFrame.Angles(-0.2, 0, 0),
			stall,
			Enum.Material.Fabric
		)
		crate(folder, CFrame.new(at(x + 2, -8, 76)), Vector3.new(2, 1.6, 2))
	end
	for step = 0, 7 do
		part(
			folder,
			"Stair",
			Vector3.new(8, 1, 2),
			CFrame.new(at(-26, -0.5 - step, 50 + step * 2)),
			CONCRETE,
			Enum.Material.Concrete
		)
	end
	signage(
		folder,
		CFrame.new(at(0, 1.5, 41)),
		Vector2.new(18, 2.4),
		"UNDERPASS MARKET · L9-S",
		Color3.fromRGB(240, 220, 160),
		Color3.fromRGB(40, 34, 28)
	)
	signage(
		folder,
		CFrame.new(at(0, -5.5, 70.1)),
		Vector2.new(9, 2),
		"⚠ SEWER BREACH — KEEP OUT",
		HAZARD,
		Color3.fromRGB(30, 28, 20)
	)
	tube(folder, at(-10, -0.5, 60), 0, FLUORESCENT, true)
	local dead = tube(folder, at(15, -0.5, 70), 0, FLUORESCENT, true)
	flicker(dead, "Fault")

	-- Exhaust vent from the pump room (steam rises when the fans run)
	local grate = part(
		folder,
		"ExhaustGrate",
		Vector3.new(16, 0.3, 16),
		CFrame.new(at(-56, -0.2, 56)),
		RUST,
		Enum.Material.CorrodedMetal
	)
	grate.Transparency = 0.35
	grate.CanCollide = false
	local steam = particles(grate, "Steam")
	steam.Name = "Exhaust"
	steam.Rate = 2
	grate:SetAttribute("VentGroup", "HCollector")
	CollectionService:AddTag(grate, "VentSteam")

	-- L9 Shelter: family message terminal + crowd
	local shelter = newModel(folder, "Shelter")
	local terminal = Kit.buildTerminal(
		shelter,
		nil,
		at(60, 0, -52),
		yawToward(at(60, 0, -52), at(0, 0, 0)),
		"L9 Shelter Terminal",
		"PKT-L9-FAMILY",
		""
	)
	signage(
		shelter,
		CFrame.lookAt(at(66, 9, -60), at(0, 9, 0)),
		Vector2.new(14, 3),
		"SHELTER · FAMILY BOARD",
		WARM,
		Color3.fromRGB(30, 26, 22)
	)
	for k = 0, 4 do
		bystander(
			shelter,
			CFrame.lookAt(at(52 + k * 2.5, 2.2, -42 + k), at(60, 2.2, -52)),
			if k % 2 == 0 then "Stand" else "Sit"
		)
	end
	local note = terminal:FindFirstChild("Screen")
	if note then
		local display = note:FindFirstChild("Display")
		local text = display and display:FindFirstChild("Text")
		if text and text:IsA("TextLabel") then
			text.Text = "L9 SHELTER\n214 MESSAGES QUEUED\nNETWORK DOWN"
		end
	end

	-- Family SOS beacons in apartment windows
	local messages: { { angle: number, text: string } } = {
		{
			angle = 160,
			text = "Okafor family, L9-114: all four of us safe. Ada is stuck up on the Deck (L8).",
		},
		{ angle = 230, text = "Hassan, L9-212: Mother needs insulin. We are OK otherwise." },
		{ angle = 30, text = "Lindqvist, L9-031: Water came in, moved to the Shelter. Alive." },
	}
	for index, m in messages do
		local frame = wallFrame(math.rad(m.angle), WELL_RADIUS - 2.6, 18)
		local beacon = Kit.buildBeacon(
			folder,
			nil,
			(frame * CFrame.new(0, 0, -0.2)).Position,
			frame.LookVector,
			"Family beacon " .. index
		)
		beacon:SetAttribute("Objective", "HBeacons")
		beacon:SetAttribute("Message", m.text)
	end

	-- Grid Watch equipment
	local transformer = newModel(folder, "Transformer")
	local core = part(
		transformer,
		"Tank",
		Vector3.new(8, 9, 6),
		CFrame.new(at(-20, 4.5, -64)),
		Color3.fromRGB(78, 88, 76),
		Enum.Material.Metal
	)
	heat(core, 96)
	for k = -3, 3 do
		heat(
			part(
				transformer,
				"Fin",
				Vector3.new(0.3, 7, 2),
				CFrame.new(at(-20 + k * 1.1, 4.5, -60.4)),
				STEEL_DARK,
				Enum.Material.Metal
			),
			88
		)
	end
	for k = 0, 2 do
		prop(
			transformer,
			"Bushing",
			Vector3.new(0.8, 2.5, 0.8),
			CFrame.new(at(-22.5 + k * 2.5, 10.2, -64)),
			Color3.fromRGB(150, 110, 90),
			Enum.Material.SmoothPlastic
		)
	end
	signage(
		transformer,
		CFrame.lookAt(at(-20, 6, -60.9), at(-20, 6, 0)),
		Vector2.new(5, 1.2),
		"T-9 · 11kV/400V",
		Color3.fromRGB(240, 240, 220),
		Color3.fromRGB(150, 30, 30)
	)
	transformer.PrimaryPart = core
	equipment(
		transformer,
		"Transformer T-9 (L9 feeder)",
		96,
		"Oil 205°F / 96°C (limit 221°F / 105°C), rising 2.5°F / 1.4°C per day. Cooling fins clogged. Partial-discharge noise detected.\nFORECAST: thermal trip in ~6 days → 3-day L9 blackout.\nACTION: clean fins, shed 18% load to L8 tie.",
		"FAILURE PREDICTED ~6 DAYS",
		"danger"
	)

	local hx = newModel(folder, "HeatExchanger")
	local shell = cylinder(
		hx,
		"Shell",
		18,
		5,
		at(30, 3.5, 20),
		"X",
		Color3.fromRGB(120, 90, 70),
		Enum.Material.CorrodedMetal
	)
	heat(shell, 74)
	for k = 0, 1 do
		heat(
			cylinder(
				hx,
				"Riser",
				34,
				1.6,
				at(24 + k * 12, 18, 23.5),
				"Y",
				RUST,
				Enum.Material.CorrodedMetal
			),
			71
		)
	end
	local steamLeak = volume(hx, "Leak", at(36, 4, 20), Vector3.new(1, 1, 1))
	particles(steamLeak, "Steam").Rate = 3
	hx.PrimaryPart = shell
	equipment(
		hx,
		"Geothermal exchanger HX-2",
		74,
		"Return 160°F / 71°C (design 131°F / 55°C). Cooling fans at 38% of rated airflow. L9 ambient trending +1.1°F / +0.6°C per month.\nFORECAST: L9 exceeds 95°F / 35°C wet-bulb risk in summer peak.\nACTION: replace 2 fan bearings; reroute HX-1 bypass.",
		"OVERHEATING · COOLING 38%",
		"warning"
	)

	local recycler = newModel(folder, "Recycler")
	for k = 0, 1 do
		local tank = cylinder(
			recycler,
			"Tank",
			10,
			7,
			at(-66 + k * 9, 5, -18),
			"Y",
			Color3.fromRGB(150, 156, 160),
			Enum.Material.Metal
		)
		heat(tank, 31)
	end
	cylinder(
		recycler,
		"Pipe",
		30,
		1.2,
		at(-61, 2, -6),
		"Z",
		Color3.fromRGB(60, 100, 160),
		Enum.Material.Metal
	)
	local membrane = part(
		recycler,
		"Membrane",
		Vector3.new(6, 4, 3),
		CFrame.new(at(-61, 2, -26)),
		Color3.fromRGB(90, 96, 100),
		Enum.Material.Metal
	)
	recycler.PrimaryPart = membrane
	signage(
		recycler,
		CFrame.lookAt(at(-61, 4.5, -24.4), at(-61, 4.5, 10)),
		Vector2.new(5, 1.2),
		"WATER RECYCLER R-9",
		Color3.fromRGB(200, 230, 255),
		Color3.fromRGB(20, 40, 70)
	)
	equipment(
		recycler,
		"Water recycler R-9",
		31,
		"Membrane fouled (ΔP 4.1 bar). Chlorine dosing pump OFF for 9 days. Coliform breakthrough on the outlet.\nThis feeds the L9 taps — matches the outfall sample in C-2.\nACTION: boil-water notice for L9; swap membrane rack B.",
		"UNSAFE OUTPUT · BOIL NOTICE",
		"danger"
	)

	-- Air quality volumes
	airZone(folder, at(0, 19, 0), Vector3.new(184, 38, 184), {
		Label = "LEVEL 9 / THE PIT",
		O2 = 19.6,
		CO2 = 2650,
		PM = 88,
		Temp = 34,
		Verdict = "Poor: overcrowding + scrubbers failing. Headaches likely.",
	})
end

-- A person who can walk: a humanoid tagged "Walker". The Guides system walks
-- it with Humanoid:MoveTo along a computed path; the default walk animation
-- plays from its speed.
local function civilian(
	parent: Instance,
	name: string,
	cf: CFrame,
	shirt: Color3,
	attributes: { [string]: any }
): Model
	local model = person(parent, "Civilian", cf, shirt, "Stand", true)
	local sampled = Characters.temperature("Healthy")
	local all: { [string]: any } =
		{ Temperature = sampled, BaseTemperature = sampled, Status = "WAITING" }
	for key, value in attributes do
		all[key] = value
	end
	device(model, "Civilian", name, all)
	CollectionService:AddTag(model, "Walker")
	return model
end

-- Maintenance stair M-3: the only walkable way between the Deck (L8) and the
-- Pit (L9). Unlit, unsigned from below, and closed by the Directorate, so in
-- a blackout nobody can find it. Two flights with a landing at y = 20.
local function buildStair(root: Folder)
	local folder = newModel(root, "StairM3")
	local function ramp(top: Vector3, bottom: Vector3, width: number)
		local a, b = at(top.X, top.Y, top.Z), at(bottom.X, bottom.Y, bottom.Z)
		local length = (b - a).Magnitude
		local cf = CFrame.lookAt((a + b) / 2, b) * CFrame.new(0, -0.5, 0)
		part(
			folder,
			"Ramp",
			Vector3.new(width, 1, length),
			cf,
			CONCRETE_DARK,
			Enum.Material.Concrete
		)
		-- step nosings for the look (the ramp itself is what feet walk on)
		local steps = math.floor(length / 1.6)
		for k = 1, steps - 1 do
			prop(
				folder,
				"Nosing",
				Vector3.new(width, 0.12, 0.25),
				CFrame.lookAt(a:Lerp(b, k / steps), b) * CFrame.new(0, 0.05, 0),
				HAZARD,
				Enum.Material.SmoothPlastic
			)
		end
		for side = -1, 1, 2 do
			local railCf = CFrame.lookAt((a + b) / 2, b)
				* CFrame.new(side * (width / 2 - 0.1), 3, 0)
			part(
				folder,
				"Handrail",
				Vector3.new(0.2, 0.2, length),
				railCf,
				RUST,
				Enum.Material.Metal
			)
		end
	end
	ramp(Vector3.new(20.5, DECK_Y, -41), Vector3.new(20.5, 20, -65), 7)
	ramp(Vector3.new(27.5, 20, -65), Vector3.new(27.5, 0, -41), 7)
	part(
		folder,
		"Landing",
		Vector3.new(14, 1, 5),
		CFrame.new(at(24, 19.5, -67.5)),
		CONCRETE_DARK,
		Enum.Material.Concrete
	)
	-- Deck patches around the stairwell opening + guard rails on the Deck
	part(
		folder,
		"DeckPatch",
		Vector3.new(16, 1.5, 9),
		CFrame.new(at(24, DECK_Y - 0.75, -36.5)),
		STEEL,
		Enum.Material.DiamondPlate
	)
	part(
		folder,
		"DeckPatch",
		Vector3.new(16, 1.5, 10),
		CFrame.new(at(24, DECK_Y - 0.75, -75)),
		STEEL,
		Enum.Material.DiamondPlate
	)
	local guards: { { Vector3 } } = {
		{ Vector3.new(28, DECK_Y + 1.7, -41), Vector3.new(8, 3.4, 0.3) },
		{ Vector3.new(16.2, DECK_Y + 1.7, -55.5), Vector3.new(0.3, 3.4, 29) },
		{ Vector3.new(31.8, DECK_Y + 1.7, -55.5), Vector3.new(0.3, 3.4, 29) },
		{ Vector3.new(24, DECK_Y + 1.7, -70), Vector3.new(16, 3.4, 0.3) },
	}
	for _, g in guards do
		local rail = part(
			folder,
			"GuardRail",
			g[2],
			CFrame.new(at(g[1].X, g[1].Y, g[1].Z)),
			RUST,
			Enum.Material.Metal
		)
		rail.Transparency = 0.35
	end
	signage(
		folder,
		CFrame.lookAt(at(20.5, DECK_Y + 6, -40.6), at(20.5, DECK_Y + 6, 0)),
		Vector2.new(7, 2.2),
		"MAINT STAIR M-3 · L8 ↔ L9\nCLOSED · DIRECTORATE ORDER",
		Color3.fromRGB(255, 225, 220),
		DIRECTORATE
	)
	prop(
		folder,
		"Tape",
		Vector3.new(7, 0.4, 0.1),
		CFrame.new(at(20.5, DECK_Y + 2.6, -40.8)) * CFrame.Angles(0, 0, 0.08),
		HAZARD
	)
	local lampPart = prop(
		folder,
		"StairLamp",
		Vector3.new(0.8, 0.4, 0.8),
		CFrame.new(at(24, 27, -69)),
		EMERGENCY,
		Enum.Material.Neon
	)
	light(lampPart, EMERGENCY, 16, 0.5)
	flicker(lampPart, "Pulse")

	-- Ada on the Deck, her father at the Shelter on L9
	civilian(
		folder,
		"Ada Okafor, 31 (L9-114 family)",
		CFrame.lookAt(at(12, DECK_Y + 1.95, -28), at(0, DECK_Y + 1.95, -60)),
		Color3.fromRGB(180, 120, 60),
		{
			Lost = true,
			ReuniteWith = "Ben Okafor",
			Route = "down Maintenance Stair M-3 through the blackout",
			Objective = "HReunite",
			Status = "LOST · TRYING TO REACH L9 SINCE THE BLACKOUT",
		}
	)
	civilian(
		folder,
		"Ben Okafor, 64 (L9-114)",
		CFrame.lookAt(at(66, 1.95, -44), at(40, 1.95, -44)),
		Color3.fromRGB(70, 90, 120),
		{
			Family = "Ben Okafor",
			Place = "the L9 Shelter",
			Status = "WAITING AT THE SHELTER FOR ADA",
		}
	)
end

local function buildCollector(root: Folder)
	local folder = newModel(root, "CollectorC2")

	-- Service ledge along the north wall and a light every 30 studs
	part(
		folder,
		"Ledge",
		Vector3.new(392, 1, 5),
		CFrame.new(at(0, -24.5, 47.6)),
		CONCRETE_DARK,
		Enum.Material.Concrete
	)
	for x = -180, 180, 30 do
		local on = rng:NextNumber() < 0.7
		local lampPart = prop(
			folder,
			"TunnelLamp",
			Vector3.new(1.6, 0.6, 1.6),
			CFrame.new(at(x, -11.4, 60)),
			if on then SODIUM else STEEL_DARK,
			if on then Enum.Material.Neon else Enum.Material.Metal
		)
		if on then
			local glow = light(lampPart, SODIUM, 30, 1.1)
			glow.Shadows = x % 60 == 0
			if rng:NextNumber() < 0.3 then
				flicker(lampPart, "Fault")
			end
		end
	end
	-- Pipes and conduits on the walls
	cylinder(folder, "Main", 392, 2.2, at(0, -18, 72.6), "X", RUST, Enum.Material.CorrodedMetal)
	cylinder(folder, "Conduit", 392, 0.8, at(0, -16, 48.4), "X", STEEL_DARK, Enum.Material.Metal)

	-- Outfall pipes to sample (north wall)
	local samples: { { x: number, label: string, readings: { [string]: any } } } = {
		{
			x = -20,
			label = "Outfall 1 · Recycler R-9 return",
			readings = { PH = 6.1, Coliform = 2400, Lead = 18, Contaminated = true },
		},
		{
			x = 60,
			label = "Outfall 2 · Clinic 7-N drain",
			readings = { PH = 6.8, Coliform = 9100, Lead = 4, Contaminated = true },
		},
		{
			x = 150,
			label = "Outfall 3 · Farm L6 runoff",
			readings = { PH = 7.2, Coliform = 40, Lead = 2, Contaminated = false },
		},
	}
	for _, sample in samples do
		-- Terrain walls are voxel-approximate, so fixtures stand well proud of the
		-- brick and a run of pipe carries them back into the lining
		local pipe = Kit.buildSamplePoint(
			folder,
			at(sample.x, -17, 49.4),
			Vector3.new(0, 0, 1),
			sample.label,
			sample.readings
		)
		pipe:SetAttribute("Objective", "HSamples")
		cylinder(
			folder,
			"OutfallRun",
			6,
			1.6,
			at(sample.x, -17, 45.4),
			"Z",
			Color3.fromRGB(80, 84, 70),
			Enum.Material.CorrodedMetal
		)
	end

	-- Sluice gates (valves) on the north wall
	local valves: { Instance } = {}
	-- SG-1 must be opened (relief to the deep interceptor); SG-2 must be shut
	-- (it is the backflow path into the Underpass)
	local gates: { { x: number, correct: boolean, start: boolean } } = {
		{ x = 40, correct = true, start = false },
		{ x = 120, correct = false, start = true },
	}
	for index, g in gates do
		local valve = Kit.buildValve(
			folder,
			nil,
			at(g.x, -19, 49.2),
			1,
			"Sluice gate SG-" .. index,
			g.correct,
			g.start
		)
		valve:SetAttribute("FloodGroup", "C2")
		table.insert(valves, valve)
		part(
			folder,
			"GateFrame",
			Vector3.new(6, 12, 0.6),
			CFrame.new(at(g.x, -27, 47.4)),
			RUST,
			Enum.Material.CorrodedMetal
		)
		-- spindle housing from the gate up to the handwheel, back into the wall
		part(
			folder,
			"Spindle",
			Vector3.new(0.6, 8, 0.6),
			CFrame.new(at(g.x, -23, 47.6)),
			STEEL,
			Enum.Material.Metal
		)
		part(
			folder,
			"Bracket",
			Vector3.new(1.4, 1.4, 5),
			CFrame.new(at(g.x, -19, 46)),
			STEEL_DARK,
			Enum.Material.Metal
		)
	end

	-- Trash rack at x = 90 with three pieces of debris jammed in it
	for z = 46, 74, 3.5 do
		part(
			folder,
			"RackBar",
			Vector3.new(0.5, 30, 0.5),
			CFrame.new(at(90, -26, z)) * CFrame.Angles(0, 0, 0.12),
			RUST,
			Enum.Material.CorrodedMetal
		)
	end
	local jam: { { at: Vector3, size: Vector3, label: string } } = {
		{ at = Vector3.new(88, -27.5, 54), size = Vector3.new(3, 2.5, 5), label = "Mattress" },
		{ at = Vector3.new(88, -27, 62), size = Vector3.new(4, 3, 3), label = "Shopping trolley" },
		{
			at = Vector3.new(88, -27.5, 70),
			size = Vector3.new(3.5, 2, 3.5),
			label = "Plastic waste bale",
		},
	}
	for index, d in jam do
		local debris =
			Kit.buildDebris(folder, O + d.at, d.size, "HRack", d.label .. " (rack " .. index .. ")")
		debris:SetAttribute("FloodGroup", "C2")
		debris.Color = CLOTH[index]
		debris.Material = Enum.Material.Fabric
	end
	signage(
		folder,
		CFrame.new(at(86, -14, 60)) * CFrame.Angles(0, math.pi / 2, 0),
		Vector2.new(10, 2),
		"TRASH RACK TR-4",
		HAZARD,
		Color3.fromRGB(26, 26, 22),
		Enum.Font.Code
	)

	-- Pump room: methane + H2S, exhaust fans in the shaft, the breaker
	part(
		folder,
		"PumpDeck",
		Vector3.new(30, 1, 20),
		CFrame.new(at(-60, -26.5, 72)),
		CONCRETE_DARK,
		Enum.Material.Concrete
	)
	for k = 0, 1 do
		local pump = cylinder(
			folder,
			"Pump",
			6,
			5,
			at(-66 + k * 12, -23, 74),
			"Y",
			Color3.fromRGB(40, 80, 120),
			Enum.Material.Metal
		)
		heat(pump, 45)
	end
	fan(folder, at(-60, -6, 60), 8, true, "HCollector")
	local panel = breaker(
		folder,
		CFrame.lookAt(at(-46.2, -21, 70), at(-60, -21, 70)),
		"EXHAUST FANS · C-2",
		"HCollector"
	)
	panel.Name = "ExhaustBreaker"
	Kit.buildGas(folder, nil, "CH4", at(-60, -18, 64), 16, 34, "Collector")
		:SetAttribute("VentGroup", "HCollector")
	Kit.buildGas(folder, nil, "H2S", at(-30, -22, 60), 14, 120, "Collector")
		:SetAttribute("VentGroup", "HCollector")
	Kit.buildGas(folder, nil, "H2S", at(20, -22, 60), 12, 70, "Collector")
		:SetAttribute("VentGroup", "HCollector")
	local lampPart = prop(
		folder,
		"PumpLamp",
		Vector3.new(1.4, 0.5, 1.4),
		CFrame.new(at(-60, -8.5, 70)),
		EMERGENCY,
		Enum.Material.Neon
	)
	light(lampPart, EMERGENCY, 24, 0.9)
	flicker(lampPart, "Pulse")
	signage(
		folder,
		CFrame.lookAt(at(-60, -14, 81.2), at(-60, -14, 60)),
		Vector2.new(14, 2.5),
		"PUMP STATION P-2 · CONFINED SPACE · GAS",
		HAZARD,
		Color3.fromRGB(26, 26, 22)
	)
	local mist = volume(folder, "Mist", at(0, -26, 60), Vector3.new(380, 3, 28))
	local fog = particles(mist, "Steam")
	fog.Rate = 14
	fog.Speed = NumberRange.new(0.3, 0.8)
	fog.Size =
		NumberSequence.new({ NumberSequenceKeypoint.new(0, 4), NumberSequenceKeypoint.new(1, 10) })
	fog.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5, 0.88),
		NumberSequenceKeypoint.new(1, 1),
	})
	local drips = volume(folder, "Drips", at(0, -11, 60), Vector3.new(380, 1, 20))
	particles(drips, "Drip").Rate = 8

	airZone(folder, at(0, -26, 60), Vector3.new(420, 36, 44), {
		Label = "COLLECTOR C-2",
		O2 = 18.6,
		CO2 = 3400,
		PM = 140,
		Temp = 29,
		Verdict = "Confined space: O2 below 19.5%. Lethal for a human crew without SCBA.",
	})

	Registry.floods.C2 = {
		valves = valves,
		valveObjective = "HSluice",
		debrisObjective = "HRack",
		debrisTotal = 3,
		apply = function(progress: number): number
			return setWater(progress)
		end,
		describe = function(level: number): string
			local depth = (level - TUNNEL.bottom) * Config.STUDS_TO_METERS
			if UNDERPASS.target > UNDERPASS.low then
				return ("Collector surcharged (%.1fm). Underpass Market still flooded by backflow."):format(
					depth
				)
			end
			return ("Underpass Market draining. Collector down to %.1fm."):format(depth)
		end,
	}
	Registry.vents.HCollector = {
		breaker = panel,
		objective = "HGas",
		onText = "Exhaust fans ON. Methane and H2S are being pulled up the shaft; watch it clear in CHEM.",
		offText = "Exhaust fans OFF. Gas will pool in the pump room again.",
	}
end

local function room(parent: Instance, x0: number, x1: number, z0: number, z1: number)
	-- Back wall plaster + skirting so rooms read as homes, not rock caves
	local zWall = if math.abs(z0) > math.abs(z1) then z0 else z1
	part(
		parent,
		"BackWall",
		Vector3.new(x1 - x0, 28, 1),
		CFrame.new(at((x0 + x1) / 2, 14, zWall)),
		Color3.fromRGB(150, 140, 124),
		Enum.Material.Plaster
	)
end

local function buildQuarantine(root: Folder)
	local folder = newModel(root, "QuarantineQ9")
	local wallColor = Color3.fromRGB(160, 152, 138)

	part(
		folder,
		"Floor",
		Vector3.new(86, 1, 80),
		CFrame.new(at(-133, -0.5, 0)),
		Color3.fromRGB(96, 92, 86),
		Enum.Material.Concrete
	)
	part(
		folder,
		"Ceiling",
		Vector3.new(86, 1, 80),
		CFrame.new(at(-133, 28.5, 0)),
		CONCRETE_DARK,
		Enum.Material.Concrete
	)
	-- Front wall on the Pit side with the entrance (x = -90)
	Kit.wallX(
		folder,
		-90.5,
		-40,
		40,
		0,
		28,
		{ Kit.rect(-5, 5, 0, 11) },
		CONCRETE,
		Enum.Material.Concrete
	)
	-- Corridor walls with doors to six rooms
	local doorsNorth =
		{ Kit.rect(-110, -102, 0, 9), Kit.rect(-138, -130, 0, 9), Kit.rect(-166, -158, 0, 9) }
	local doorsSouth =
		{ Kit.rect(-110, -102, 0, 9), Kit.rect(-138, -130, 0, 9), Kit.rect(-166, -158, 0, 9) }
	Kit.wallZ(folder, -5, -176, -91, 0, 28, doorsNorth, wallColor, Enum.Material.Plaster)
	Kit.wallZ(folder, 5, -176, -91, 0, 28, doorsSouth, wallColor, Enum.Material.Plaster)
	-- Shift walls into place (Kit walls use absolute coordinates; offset into the site)
	for _, child in folder:GetChildren() do
		if child:IsA("BasePart") and (child.Name == "Wall") then
			child.CFrame = child.CFrame + O
		end
	end
	for _, x in { -120, -148 } do
		for _, side in { -1, 1 } do
			part(
				folder,
				"RoomWall",
				Vector3.new(1, 28, 35),
				CFrame.new(at(x, 14, side * 22.5)),
				wallColor,
				Enum.Material.Plaster
			)
		end
	end
	for _, z in { -40, 40 } do
		room(folder, -176, -91, z, z)
	end

	-- Entrance: Directorate quarantine barrier (drone flies over it)
	part(
		folder,
		"Barrier",
		Vector3.new(1, 5, 10),
		CFrame.new(at(-88, 2.5, 0)),
		Color3.fromRGB(200, 190, 170),
		Enum.Material.Concrete
	)
	prop(
		folder,
		"Tape",
		Vector3.new(0.1, 0.5, 12),
		CFrame.new(at(-87.4, 6.5, 0)) * CFrame.Angles(0.1, 0, 0),
		HAZARD
	)
	signage(
		folder,
		CFrame.new(at(-89.8, 15, 0)) * CFrame.Angles(0, -math.pi / 2, 0),
		Vector2.new(14, 4),
		"QUARANTINE ZONE Q-9\nDIRECTORATE MEDICAL ORDER · NO ENTRY",
		Color3.fromRGB(255, 225, 220),
		DIRECTORATE
	)
	local flood = prop(
		folder,
		"Floodlight",
		Vector3.new(1.5, 1, 1.5),
		CFrame.new(at(-86, 12, 8)),
		Color3.fromRGB(240, 240, 255),
		Enum.Material.Neon
	)
	local spot = Instance.new("SpotLight")
	spot.Face = Enum.NormalId.Bottom
	spot.Range = 30
	spot.Brightness = 2
	spot.Angle = 70
	spot.Shadows = true
	spot.Parent = flood
	Kit.buildCamera(folder, at(-88, 20, -9), at(-60, 2, 0), "Quarantine camera")

	-- Corridor: one dying emergency light, scattered belongings
	local corridorLamp = prop(
		folder,
		"Emergency",
		Vector3.new(1, 0.5, 1),
		CFrame.new(at(-130, 27.6, 0)),
		EMERGENCY,
		Enum.Material.Neon
	)
	light(corridorLamp, EMERGENCY, 26, 0.7).Shadows = true
	flicker(corridorLamp, "Pulse")
	for k = 0, 5 do
		crate(
			folder,
			CFrame.new(at(-100 - k * 13, 0, rng:NextNumber(-3, 3)))
				* CFrame.Angles(0, rng:NextNumber(0, 3), 0),
			Vector3.new(1.6, 1.2, 1.6)
		)
	end

	-- Rooms (x ranges) and occupants
	local function roomCenter(index: number): number
		return -106 - (index - 1) * 28
	end
	-- North row (z negative), south row (z positive)
	-- N1: fever
	local cfN1 = bed(folder, CFrame.new(at(roomCenter(1) - 6, 0, -30)), Color3.fromRGB(70, 90, 120))
	resident(
		folder,
		"Amara Osei, 34 (Q9-N1)",
		"Fever",
		39.4,
		cfN1,
		"Lie",
		Color3.fromRGB(150, 60, 60)
	)
	bunk(folder, CFrame.new(at(roomCenter(1) + 7, 0, -30)))
	-- N2: fever + healthy carer
	local cfN2 =
		bed(folder, CFrame.new(at(roomCenter(2) - 6, 0, -30)), Color3.fromRGB(120, 100, 70))
	resident(
		folder,
		"Tomas Reyes, 61 (Q9-N2)",
		"Fever",
		39.8,
		cfN2,
		"Lie",
		Color3.fromRGB(60, 80, 110)
	)
	resident(
		folder,
		"Lena Reyes, 58 (Q9-N2)",
		"Healthy",
		36.9,
		CFrame.new(at(roomCenter(2) + 2, 2.1, -26)) * CFrame.Angles(0, math.rad(200), 0),
		"Sit",
		Color3.fromRGB(110, 90, 130)
	)
	-- N3: barricaded, dehydrated resident trapped inside
	local cfN3 = bed(folder, CFrame.new(at(roomCenter(3) - 4, 0, -30)), nil)
	resident(
		folder,
		"Ivo Petrov, 45 (Q9-N3)",
		"Dehydrated",
		38.1,
		cfN3,
		"Lie",
		Color3.fromRGB(90, 90, 80)
	)
	local barricade: { { x: number, size: Vector3, label: string } } = {
		{ x = -165, size = Vector3.new(4, 5, 2), label = "Welded bed frame" },
		{ x = -159.5, size = Vector3.new(3.5, 6, 2.2), label = "Wardrobe" },
	}
	for index, d in barricade do
		local debris = Kit.buildDebris(
			folder,
			at(d.x, d.size.Y / 2, -5.2),
			d.size,
			"HBarricade",
			d.label .. " (barricade " .. index .. ")"
		)
		debris.Material = Enum.Material.Metal
		debris.Color = Color3.fromRGB(90, 84, 76)
	end
	-- S1: space heater decoy + fever
	local heater = newModel(folder, "SpaceHeater")
	local body = part(
		heater,
		"Body",
		Vector3.new(1.4, 2.4, 0.8),
		CFrame.new(at(roomCenter(1) + 4, 1.2, 30)),
		Color3.fromRGB(200, 196, 186),
		Enum.Material.SmoothPlastic
	)
	local coil = prop(
		heater,
		"Coil",
		Vector3.new(1, 1.6, 0.1),
		CFrame.new(at(roomCenter(1) + 4, 1.4, 29.55)),
		Color3.fromRGB(255, 120, 40),
		Enum.Material.Neon
	)
	light(coil, Color3.fromRGB(255, 120, 50), 8, 0.6)
	heater.PrimaryPart = body
	device(
		heater,
		"HeatSource",
		"Heat signature (S1)",
		{ Temperature = 61, Status = "UNIDENTIFIED" }
	)
	local cfS1 = bed(
		folder,
		CFrame.new(at(roomCenter(1) - 6, 0, 30)) * CFrame.Angles(0, math.pi, 0),
		Color3.fromRGB(70, 110, 80)
	)
	resident(
		folder,
		"Mika Laine, 29 (Q9-S1)",
		"Fever",
		38.9,
		cfS1,
		"Lie",
		Color3.fromRGB(70, 110, 140)
	)
	-- S2: an empty family room with a beacon, laundry, belongings
	bunk(folder, CFrame.new(at(roomCenter(2) - 6, 0, 30)))
	bunk(folder, CFrame.new(at(roomCenter(2) + 6, 0, 30)))
	local beacon = Kit.buildBeacon(
		folder,
		nil,
		at(roomCenter(2), 12, 39),
		Vector3.new(0, 0, -1),
		"Family beacon (Q9-S2)"
	)
	beacon:SetAttribute("Objective", "HBeacons")
	beacon:SetAttribute(
		"Message",
		"Achterberg family, Q9-S2: moved to the Shelter. Grandad stayed in S3. Please check on him."
	)
	-- S3: critical fever
	local cfS3 = bed(
		folder,
		CFrame.new(at(roomCenter(3) - 4, 0, 30)) * CFrame.Angles(0, math.pi, 0),
		Color3.fromRGB(110, 70, 70)
	)
	resident(
		folder,
		"Grace Mbeki, 70 (Q9-S3)",
		"Fever",
		40.1,
		cfS3,
		"Lie",
		Color3.fromRGB(120, 110, 60)
	)

	-- Furniture for realism
	for _, z in { -36, 36 } do
		for index = 1, 3 do
			local x = roomCenter(index)
			part(
				folder,
				"Table",
				Vector3.new(4, 0.3, 2.6),
				CFrame.new(at(x + 9, 3, z * 0.75)),
				Color3.fromRGB(110, 88, 64),
				Enum.Material.Wood
			)
			for _, dx in { -1.7, 1.7 } do
				for _, dz in { -1.1, 1.1 } do
					prop(
						folder,
						"Leg",
						Vector3.new(0.2, 3, 0.2),
						CFrame.new(at(x + 9 + dx, 1.5, z * 0.75 + dz)),
						Color3.fromRGB(90, 70, 50),
						Enum.Material.Wood
					)
				end
			end
			prop(
				folder,
				"Bottle",
				Vector3.new(0.3, 0.9, 0.3),
				CFrame.new(at(x + 9.5, 3.6, z * 0.75)),
				Color3.fromRGB(80, 140, 120),
				Enum.Material.Glass
			)
			tube(folder, at(x, 27.6, z * 0.6), 0, FLUORESCENT, false)
		end
	end

	-- Spore load in the air of the sick rooms
	Kit.buildGas(folder, nil, "Spores", at(roomCenter(1), 6, -24), 14, 45, "Quarantine")
	Kit.buildGas(folder, nil, "Spores", at(roomCenter(2), 6, -24), 13, 38, "Quarantine")
	Kit.buildGas(folder, nil, "Spores", at(roomCenter(3), 6, 24), 13, 60, "Quarantine")
	local sporeVolume = volume(folder, "SporeMotes", at(-133, 10, 0), Vector3.new(80, 18, 70))
	particles(sporeVolume, "Spores")

	airZone(folder, at(-133, 14, 0), Vector3.new(86, 28, 80), {
		Label = "QUARANTINE Q-9",
		O2 = 19.2,
		CO2 = 3100,
		PM = 210,
		Temp = 33,
		Verdict = "Airborne spore load high: consistent with an active lung-sickness cluster.",
	})
end

local function buildHub(root: Folder): CFrame
	local folder = newModel(root, "OpsHub")
	local floorColor = Color3.fromRGB(80, 78, 74)
	part(
		folder,
		"Floor",
		Vector3.new(74, 1, 52),
		CFrame.new(at(123, 39.5, 0)),
		floorColor,
		Enum.Material.Concrete
	)
	part(
		folder,
		"Ceiling",
		Vector3.new(74, 1, 52),
		CFrame.new(at(123, 63.5, 0)),
		CONCRETE_DARK,
		Enum.Material.Concrete
	)
	for _, z in { -25.5, 25.5 } do
		part(
			folder,
			"Wall",
			Vector3.new(74, 24, 1),
			CFrame.new(at(123, 52, z)),
			Color3.fromRGB(96, 96, 92),
			Enum.Material.Concrete
		)
	end
	part(
		folder,
		"BackWall",
		Vector3.new(1, 24, 52),
		CFrame.new(at(159.5, 52, 0)),
		Color3.fromRGB(96, 96, 92),
		Enum.Material.Concrete
	)
	-- Pipes + cable trays along the ceiling
	for _, z in { -20, -16, 18 } do
		cylinder(
			folder,
			"Pipe",
			72,
			1.2,
			at(123, 61.5, z),
			"X",
			if z > 0 then Color3.fromRGB(40, 90, 150) else RUST,
			Enum.Material.Metal
		)
	end
	for x = 98, 152, 13 do
		tube(folder, at(x, 62.6, -8), math.pi / 2, FLUORESCENT, true)
		tube(folder, at(x, 62.6, 8), math.pi / 2, FLUORESCENT, true)
	end
	-- String lights (warm) over the work area
	for k = 0, 10 do
		local bulb = prop(
			folder,
			"StringLight",
			Vector3.new(0.35, 0.35, 0.35),
			CFrame.new(at(100 + k * 5, 58.5 + math.sin(k) * 0.4, 18)),
			WARM,
			Enum.Material.Neon
		)
		if k % 3 == 0 then
			light(bulb, WARM, 10, 0.6)
		end
	end

	-- Docks (spawn over the middle one)
	local docks = { -14, 0, 14 }
	for index, z in docks do
		Kit.buildDock(folder, nil, "Ops Hub dock " .. index, at(144, 40, z))
	end
	-- Mesh antenna on the rock face beside the hub mouth: the resistance's
	-- link into the open Well (the deck still shadows Level 9 below it)
	local antenna = newModel(folder, "HubAntenna")
	local mast = part(
		antenna,
		"Mast",
		Vector3.new(0.5, 9, 0.5),
		CFrame.new(at(89, 60, -24)),
		STEEL,
		Enum.Material.Metal
	)
	for k = 0, 2 do
		local panelCf = CFrame.new(at(88.6, 62 + k * 1.6, -24))
			* CFrame.Angles(0, math.rad(90 + k * 40), 0)
		prop(
			antenna,
			"Panel",
			Vector3.new(1.4, 1.2, 0.2),
			panelCf * CFrame.new(0, 0, -0.5),
			Color3.fromRGB(220, 220, 214),
			Enum.Material.SmoothPlastic
		)
	end
	local tip = prop(
		antenna,
		"Tip",
		Vector3.new(0.4, 0.4, 0.4),
		CFrame.new(at(89, 64.8, -24)),
		CYAN,
		Enum.Material.Neon
	)
	light(tip, CYAN, 8, 0.6)
	flicker(tip, "Blink")
	antenna.PrimaryPart = mast
	device(antenna, "Antenna", "Ops Hub mesh antenna", {
		Status = "MESH BACKHAUL · FIXED",
		LinkRange = 225,
		Temperature = 33,
	})
	CollectionService:AddTag(antenna, "LinkSource")
	-- Uplink (receives the surface logs and broadcasts them)
	local uplink = Kit.buildTerminal(
		folder,
		nil,
		at(112, 40, -18),
		math.rad(180),
		"Resistance Uplink",
		"",
		"PKT-SURFACE-LOG"
	)
	uplink:SetAttribute("Status", "AWAITING SURFACE DATA")
	-- Map table with a model of the Hollow
	part(
		folder,
		"MapTable",
		Vector3.new(10, 3, 7),
		CFrame.new(at(118, 41.5, 6)),
		STEEL_DARK,
		Enum.Material.Metal
	)
	local holo = prop(
		folder,
		"Holo",
		Vector3.new(0.2, 3.2, 3.2),
		CFrame.new(at(118, 44.8, 6)) * CFrame.Angles(0, 0, math.pi / 2),
		CYAN,
		Enum.Material.Neon
	)
	holo.Shape = Enum.PartType.Cylinder
	holo.Transparency = 0.6
	light(holo, CYAN, 10, 0.8)
	for k = 0, 3 do
		prop(
			folder,
			"HoloLevel",
			Vector3.new(0.05, 3.6 - k * 0.3, 3.6 - k * 0.3),
			CFrame.new(at(118, 43.4 + k * 0.6, 6)) * CFrame.Angles(0, 0, math.pi / 2),
			CYAN,
			Enum.Material.Neon
		).Transparency =
			0.75
	end
	-- Monitor wall
	for row = 0, 1 do
		for col = 0, 3 do
			local screen = prop(
				folder,
				"Monitor",
				Vector3.new(3.4, 2.2, 0.3),
				CFrame.new(at(105 + col * 3.8, 46 + row * 2.6, -24.6)),
				Color3.fromRGB(20, 60, 70),
				Enum.Material.Neon
			)
			screen.Transparency = 0.2
		end
	end
	signage(
		folder,
		CFrame.new(at(124, 57, -24.9)) * CFrame.Angles(0, math.pi, 0),
		Vector2.new(24, 3),
		"THE AIR IS OURS · OPS HUB L8-E",
		WARM,
		Color3.fromRGB(34, 30, 26)
	)
	-- Workbench, crates, cots
	part(
		folder,
		"Bench",
		Vector3.new(10, 3, 3),
		CFrame.new(at(136, 41.5, 22)),
		Color3.fromRGB(110, 90, 66),
		Enum.Material.WoodPlanks
	)
	for k = 0, 3 do
		crate(
			folder,
			CFrame.new(at(100 + k * 3.4, 40, 21)) * CFrame.Angles(0, k * 0.3, 0),
			Vector3.new(3, 2.4, 3)
		)
	end
	for k = 0, 1 do
		bed(
			folder,
			CFrame.new(at(104 + k * 6, 40, -8)) * CFrame.Angles(0, math.pi / 2, 0),
			CLOTH[k + 2]
		)
	end
	bystander(folder, CFrame.lookAt(at(116, 42.2, 2), at(118, 42.2, 6)), "Stand")
	bystander(folder, CFrame.lookAt(at(121, 42.2, 9.5), at(118, 42.2, 6)), "Stand")

	-- Module racks (decor)
	for index, module in Config.MODULE_ORDER do
		local spec = Config.MODULES[module]
		local x = 130 + (index - 1) * 5
		part(
			folder,
			"Rack",
			Vector3.new(4, 6, 1.5),
			CFrame.new(at(x, 43, 24)),
			STEEL_DARK,
			Enum.Material.Metal
		)
		prop(
			folder,
			"Module",
			Vector3.new(2, 1.2, 1.2),
			CFrame.new(at(x, 44, 23.4)),
			spec.color,
			Enum.Material.SmoothPlastic
		)
		signage(
			folder,
			CFrame.new(at(x, 46.5, 23.2)),
			Vector2.new(3.6, 0.8),
			spec.short,
			spec.color,
			Color3.fromRGB(20, 20, 22),
			Enum.Font.Code
		)
	end

	airZone(folder, at(123, 52, 0), Vector3.new(74, 24, 52), {
		Label = "OPS HUB",
		O2 = 20.4,
		CO2 = 1050,
		PM = 30,
		Temp = 26,
	})

	local spawn = at(144, 43.5, 0)
	return CFrame.lookAt(spawn, spawn - Vector3.new(1, 0, 0))
end

local function buildUpperLevels(root: Folder)
	local folder = newModel(root, "UpperLevels")

	-- Clinic 7-N: med supplies + the community board terminal
	local clinic = newModel(folder, "Clinic7N")
	part(
		clinic,
		"Floor",
		Vector3.new(50, 1, 36),
		CFrame.new(at(0, 79.5, -106)),
		Color3.fromRGB(190, 192, 190),
		Enum.Material.Marble
	)
	part(
		clinic,
		"Ceiling",
		Vector3.new(50, 1, 36),
		CFrame.new(at(0, 103.5, -106)),
		Color3.fromRGB(200, 200, 196),
		Enum.Material.Plaster
	)
	for x = -18, 18, 12 do
		tube(clinic, at(x, 102.8, -100), 0, FLUORESCENT, true)
		tube(clinic, at(x, 102.8, -112), 0, FLUORESCENT, true)
	end
	local rack = newModel(clinic, "MedRack")
	local shelf = part(
		rack,
		"Shelf",
		Vector3.new(8, 7, 2),
		CFrame.new(at(-12, 83.5, -122)),
		Color3.fromRGB(220, 220, 214),
		Enum.Material.Metal
	)
	for row = 0, 2 do
		for col = 0, 3 do
			prop(
				rack,
				"Kit",
				Vector3.new(1.4, 1, 1.2),
				CFrame.new(at(-15 + col * 2, 81.4 + row * 2.1, -121.2)),
				Color3.fromRGB(235, 235, 230),
				Enum.Material.SmoothPlastic
			)
			prop(
				rack,
				"Cross",
				Vector3.new(0.6, 0.15, 0.05),
				CFrame.new(at(-15 + col * 2, 81.4 + row * 2.1, -120.55)),
				Color3.fromRGB(220, 40, 40),
				Enum.Material.Neon
			)
		end
	end
	rack.PrimaryPart = shelf
	device(
		rack,
		"MedRack",
		"Clinic 7-N supply rack",
		{ Status = "STOCKED · 24 KITS", Temperature = 22 }
	)
	Kit.buildTerminal(
		clinic,
		nil,
		at(12, 80, -118),
		math.pi,
		"Community Board 7-N",
		"",
		"PKT-L9-FAMILY"
	)
	Kit.buildDock(clinic, nil, "Clinic pad 7-N", at(0, 80, -98))
	for k = 0, 2 do
		bed(
			clinic,
			CFrame.new(at(14 + k * 0, 80, -96 - k * 6)) * CFrame.Angles(0, math.pi / 2, 0),
			Color3.fromRGB(180, 200, 220)
		)
	end
	signage(
		clinic,
		CFrame.new(at(0, 98, -88.2)) * CFrame.Angles(0, math.pi, 0),
		Vector2.new(14, 3),
		"✚ CLINIC 7-N",
		Color3.fromRGB(255, 255, 255),
		Color3.fromRGB(170, 30, 40)
	)
	bystander(clinic, CFrame.lookAt(at(-6, 82.2, -112), at(-12, 82.2, -122)), "Stand")
	airZone(
		clinic,
		at(0, 92, -106),
		Vector3.new(50, 24, 36),
		{ Label = "CLINIC 7-N", O2 = 20.6, CO2 = 820, PM = 12, Temp = 24 }
	)

	-- Scrubber hall (L7 south): failing CO2 scrubbers, a backup to restart
	local hall = newModel(folder, "ScrubberHall")
	part(
		hall,
		"Floor",
		Vector3.new(60, 1, 50),
		CFrame.new(at(0, 79.5, 112)),
		CONCRETE_DARK,
		Enum.Material.Concrete
	)
	for k = 0, 1 do
		local x = -14 + k * 28
		local unit = part(
			hall,
			"Scrubber",
			Vector3.new(14, 18, 12),
			CFrame.new(at(x, 89, 124)),
			Color3.fromRGB(96, 104, 100),
			Enum.Material.Metal
		)
		heat(unit, if k == 0 then 52 else 30)
		fan(hall, at(x, 98.5, 124), 9, true, "HAir")
		signage(
			hall,
			CFrame.lookAt(at(x, 92, 117.9), at(x, 92, 100)),
			Vector2.new(10, 2),
			if k == 0 then "SCRUBBER A · FAULT" else "SCRUBBER B · STANDBY",
			if k == 0 then EMERGENCY else HAZARD,
			Color3.fromRGB(26, 26, 26),
			Enum.Font.Code
		)
	end
	local hallBreaker =
		breaker(hall, CFrame.lookAt(at(29.2, 83, 106), at(0, 83, 106)), "BACKUP SCRUBBER B", "HAir")
	Kit.buildGas(hall, nil, "CO2", at(0, 90, 112), 24, 9000, "Scrubber")
		:SetAttribute("VentGroup", "HAir")
	local warn = prop(
		hall,
		"Beacon",
		Vector3.new(0.8, 0.8, 0.8),
		CFrame.new(at(-24, 104, 100)),
		Color3.fromRGB(255, 140, 20),
		Enum.Material.Neon
	)
	light(warn, Color3.fromRGB(255, 140, 20), 20, 1)
	flicker(warn, "Rotate")
	Registry.vents.HAir = {
		breaker = hallBreaker,
		objective = "HScrubber",
		onText = "Backup scrubber B running. CO2 in the hall is falling; L6-L8 air cut averted.",
		offText = "Scrubber B stopped. CO2 will build again.",
	}
	airZone(hall, at(0, 94, 112), Vector3.new(60, 28, 50), {
		Label = "SCRUBBER HALL",
		O2 = 19.9,
		CO2 = 1800,
		PM = 22,
		Temp = 31,
		Verdict = "Scrubber A failed. Without B, Levels 6-8 hit 5000 ppm CO2 in ~40 hours.",
	})

	-- Hydroponic farm (L6 west): grow racks under purple light
	local farm = newModel(folder, "Farm6W")
	part(
		farm,
		"Floor",
		Vector3.new(50, 1, 70),
		CFrame.new(at(-112, 119.5, 0)),
		CONCRETE_DARK,
		Enum.Material.Concrete
	)
	for row = 0, 3 do
		local x = -128 + row * 9
		for tier = 0, 2 do
			part(
				farm,
				"Tray",
				Vector3.new(4, 0.4, 56),
				CFrame.new(at(x, 122 + tier * 5, 0)),
				Color3.fromRGB(220, 222, 220),
				Enum.Material.SmoothPlastic
			)
			local leaves = prop(
				farm,
				"Greens",
				Vector3.new(3.4, 1, 55),
				CFrame.new(at(x, 122.8 + tier * 5, 0)),
				if row == 2 then Color3.fromRGB(150, 140, 60) else Color3.fromRGB(70, 150, 60),
				Enum.Material.Grass
			)
			leaves.CastShadow = false
			local grow = prop(
				farm,
				"GrowLight",
				Vector3.new(3, 0.2, 54),
				CFrame.new(at(x, 125.6 + tier * 5, 0)),
				Color3.fromRGB(230, 80, 255),
				Enum.Material.Neon
			)
			local glow = Instance.new("SurfaceLight")
			glow.Face = Enum.NormalId.Bottom
			glow.Color = Color3.fromRGB(220, 90, 255)
			glow.Range = 6
			glow.Brightness = 1.6
			glow.Parent = grow
		end
		for _, z in { -28, 28 } do
			prop(
				farm,
				"Upright",
				Vector3.new(0.3, 16, 0.3),
				CFrame.new(at(x, 128, z)),
				STEEL,
				Enum.Material.Metal
			)
		end
	end
	local controller = newModel(farm, "FarmController")
	local cabinet = part(
		controller,
		"Cabinet",
		Vector3.new(4, 6, 2),
		CFrame.new(at(-96, 123, -30)),
		Color3.fromRGB(220, 220, 214),
		Enum.Material.Metal
	)
	signage(
		controller,
		CFrame.lookAt(at(-96, 124.5, -28.9), at(-96, 124.5, 0)),
		Vector2.new(3.6, 1),
		"NUTRIENT CTRL",
		Color3.fromRGB(40, 120, 60),
		Color3.fromRGB(230, 230, 220),
		Enum.Font.Code
	)
	controller.PrimaryPart = cabinet
	equipment(
		controller,
		"Farm 6-W nutrient controller",
		33,
		"Dosing pump 2 cavitating; rack C showing nitrogen deficiency (yellowing). Grow-light circuit shares the L9 feeder (T-9).\nFORECAST: 9 days of greens if T-9 trips.\nACTION: swap pump 2; move grow lights to the L8 tie.",
		"DEGRADED · 9 DAYS RESERVE",
		"warning"
	)
	bystander(farm, CFrame.lookAt(at(-115, 122.2, 10), at(-119, 122.2, 10)), "Stand")
	airZone(
		farm,
		at(-112, 132, 0),
		Vector3.new(50, 24, 70),
		{ Label = "FARM 6-W", O2 = 21.4, CO2 = 700, PM = 10, Temp = 25 }
	)

	-- Air for the open upper Well
	airZone(folder, at(0, 140, 0), Vector3.new(184, 200, 184), {
		Label = "UPPER WELL (L6-L8)",
		O2 = 20.6,
		CO2 = 980,
		PM = 24,
		Temp = 26,
	})
end

local function buildShaft(root: Folder)
	local folder = newModel(root, "LiftShaftZero")

	-- Spire top platform under the shaft
	part(
		folder,
		"Platform",
		Vector3.new(26, 1, 26),
		CFrame.new(at(0, 212.5, 0)),
		STEEL,
		Enum.Material.DiamondPlate
	)
	for _, c in { { -12, -12 }, { 12, -12 }, { -12, 12 }, { 12, 12 } } do
		part(
			folder,
			"GuideRail",
			Vector3.new(0.6, 218, 0.6),
			CFrame.new(at(c[1], 322, c[2])),
			STEEL_DARK,
			Enum.Material.Metal
		)
	end
	-- Directorate seal across the shaft with one panel broken out (drone-sized)
	for _, piece in Kit.solids(-13, 13, -13, 13, { Kit.rect(4, 12, 4, 12) }) do
		part(
			folder,
			"Seal",
			Vector3.new(piece.a1 - piece.a0, 2, piece.b1 - piece.b0),
			CFrame.new(at((piece.a0 + piece.a1) / 2, 246, (piece.b0 + piece.b1) / 2)),
			Color3.fromRGB(60, 58, 56),
			Enum.Material.Metal
		)
	end
	part(
		folder,
		"BentPanel",
		Vector3.new(8, 0.6, 8),
		CFrame.new(at(9, 243, 6)) * CFrame.Angles(0.9, 0.2, 0.3),
		RUST,
		Enum.Material.CorrodedMetal
	)
	signage(
		folder,
		CFrame.new(at(0, 244.8, -6)) * CFrame.Angles(-math.pi / 2, 0, 0),
		Vector2.new(20, 5),
		"SURFACE ACCESS SEALED\nDIRECTORATE ORDER 2057 · LETHAL ATMOSPHERE",
		Color3.fromRGB(255, 220, 220),
		DIRECTORATE
	)
	Kit.buildCamera(folder, at(-11, 238, -11), at(0, 214, 0), "Seal camera")

	-- The stuck freight car at ~300 (gaps on both sides to fly through)
	local car = newModel(folder, "LiftCar")
	part(
		car,
		"Floor",
		Vector3.new(14, 1, 22),
		CFrame.new(at(0, 296, 0)),
		STEEL_DARK,
		Enum.Material.DiamondPlate
	)
	part(
		car,
		"Roof",
		Vector3.new(14, 1, 22),
		CFrame.new(at(0, 308, 0)),
		STEEL_DARK,
		Enum.Material.Metal
	)
	for _, x in { -6.8, 6.8 } do
		part(
			car,
			"Side",
			Vector3.new(0.4, 11, 22),
			CFrame.new(at(x, 302, 0)),
			Color3.fromRGB(120, 100, 70),
			Enum.Material.CorrodedMetal
		)
	end
	signage(
		car,
		CFrame.new(at(0, 304, -11.2)),
		Vector2.new(10, 2),
		"FREIGHT 0 · OUT OF SERVICE 2057",
		HAZARD,
		Color3.fromRGB(24, 22, 20),
		Enum.Font.Code
	)
	for _, x in { -2, 2 } do
		prop(
			car,
			"HoistCable",
			Vector3.new(0.3, 120, 0.3),
			CFrame.new(at(x, 368, 0)),
			STEEL_DARK,
			Enum.Material.Metal
		)
	end
	-- Light and dust pouring down from the open top
	local motes = volume(folder, "Motes", at(0, 360, 0), Vector3.new(22, 120, 22))
	particles(motes, "Dust").Rate = 30
	for y = 260, 400, 35 do
		local lampPart = prop(
			folder,
			"ShaftLamp",
			Vector3.new(1, 0.5, 1),
			CFrame.new(at(12.4, y, -12.4)),
			SODIUM,
			Enum.Material.Neon
		)
		light(lampPart, SODIUM, 18, 0.5)
		if y > 300 then
			lampPart.Material = Enum.Material.SmoothPlastic
			lampPart.Color = STEEL_DARK
			local glow = lampPart:FindFirstChildOfClass("PointLight")
			if glow then
				glow.Enabled = false
			end
		end
	end

	airZone(folder, at(0, 330, 0), Vector3.new(26, 170, 26), {
		Label = "LIFT SHAFT ZERO",
		O2 = 20.7,
		CO2 = 520,
		PM = 15,
		Temp = 19,
		Verdict = "Air is drafting DOWN from the surface, and it is clean. Not what the Directorate says.",
	})
end

local function buildSurface(root: Folder)
	local folder = newModel(root, "Surface")
	local y = 430

	-- Hatch collar and the burst blast door
	for _, s in { { 0, -15, 34, 4 }, { 0, 15, 34, 4 }, { -15, 0, 4, 26 }, { 15, 0, 4, 26 } } do
		part(
			folder,
			"Collar",
			Vector3.new(s[3], 3, s[4]),
			CFrame.new(at(s[1], y + 0.5, s[2])),
			CONCRETE,
			Enum.Material.Concrete
		)
	end
	part(
		folder,
		"BlastDoor",
		Vector3.new(24, 1.6, 24),
		CFrame.new(at(-24, y + 6, 0)) * CFrame.Angles(0, 0, math.rad(62)),
		RUST,
		Enum.Material.CorrodedMetal
	)
	signage(
		folder,
		CFrame.new(at(0, y + 2.1, -17.1)),
		Vector2.new(16, 1.6),
		"SHAFT ZERO · SEALED 2057",
		Color3.fromRGB(220, 210, 190),
		Color3.fromRGB(60, 50, 40)
	)

	-- Met Station 4: still logging after 30 years
	local station = newModel(folder, "MetStation4")
	part(
		station,
		"Hut",
		Vector3.new(10, 8, 8),
		CFrame.new(at(46, y + 4, 30)),
		Color3.fromRGB(170, 166, 150),
		Enum.Material.Concrete
	)
	part(
		station,
		"Mast",
		Vector3.new(0.5, 22, 0.5),
		CFrame.new(at(54, y + 11, 34)),
		STEEL,
		Enum.Material.Metal
	)
	local cups = prop(
		station,
		"Anemometer",
		Vector3.new(3, 0.3, 3),
		CFrame.new(at(54, y + 22, 34)),
		Color3.fromRGB(230, 230, 230)
	)
	cups:SetAttribute("VentGroup", "Wind")
	cups:SetAttribute("Running", true)
	CollectionService:AddTag(cups, "Fan")
	part(
		station,
		"Panel",
		Vector3.new(6, 0.3, 4),
		CFrame.new(at(46, y + 8.6, 30)) * CFrame.Angles(0.4, 0, 0),
		Color3.fromRGB(30, 40, 70),
		Enum.Material.Glass
	)
	local met = Kit.buildTerminal(
		station,
		nil,
		at(46, y, 23),
		yawToward(at(46, y, 23), at(0, y, 0)),
		"Surface Met Station 4",
		"PKT-SURFACE-LOG",
		""
	)
	met:SetAttribute("Objective", "HWeatherLog")
	met:SetAttribute("Status", "30 YEARS OF AIR LOGS · JACK IN")

	-- Ruins of the old city: concrete frames, floors partly collapsed
	local ruins: { { x: number, z: number, w: number, d: number, floors: number, yaw: number } } = {
		{ x = -120, z = -100, w = 34, d = 26, floors = 6, yaw = 0.3 },
		{ x = 150, z = -130, w = 28, d = 28, floors = 8, yaw = -0.2 },
		{ x = -175, z = 120, w = 40, d = 30, floors = 4, yaw = 0.9 },
		{ x = 120, z = 160, w = 26, d = 22, floors = 7, yaw = 0.5 },
		{ x = -40, z = -190, w = 30, d = 24, floors = 5, yaw = -0.4 },
	}
	local concrete = Color3.fromRGB(128, 124, 116)
	for _, r in ruins do
		local base = CFrame.new(at(r.x, y, r.z)) * CFrame.Angles(0, r.yaw, 0)
		local storey = 11
		-- the top floors have fallen in: each column stops at a random height
		for cx = -1, 1 do
			for cz = -1, 1, 2 do
				local height = storey * rng:NextInteger(math.max(1, r.floors - 3), r.floors)
				part(
					folder,
					"Column",
					Vector3.new(1.6, height, 1.6),
					base * CFrame.new(cx * r.w / 2.2, height / 2, cz * r.d / 2.2),
					concrete,
					Enum.Material.Concrete
				)
			end
		end
		for floor = 1, r.floors - 1 do
			local missing = rng:NextNumber()
			if missing > 0.25 then
				local share = if floor > r.floors - 3 then rng:NextNumber(0.3, 0.7) else 1
				local slab = part(
					folder,
					"Slab",
					Vector3.new(r.w * share, 1.2, r.d),
					base
						* CFrame.new(-r.w * (1 - share) / 2, floor * storey, 0)
						* CFrame.Angles(0, 0, if share < 1 then rng:NextNumber(-0.12, 0.12) else 0),
					concrete,
					Enum.Material.Concrete
				)
				slab.CastShadow = true
				-- rebar sticking out of broken edges
				if share < 1 then
					for k = 0, 3 do
						prop(
							folder,
							"Rebar",
							Vector3.new(0.15, 0.15, 3),
							base
								* CFrame.new(
									-r.w / 2 + r.w * share + 1,
									floor * storey,
									-r.d / 3 + k * r.d / 4.5
								)
								* CFrame.Angles(0, math.pi / 2, rng:NextNumber(-0.4, 0.4)),
							RUST,
							Enum.Material.CorrodedMetal
						)
					end
				end
			end
		end
		-- rubble mound at the foot
		for _ = 1, 6 do
			local size =
				Vector3.new(rng:NextNumber(3, 8), rng:NextNumber(1.5, 4), rng:NextNumber(3, 8))
			part(
				folder,
				"Rubble",
				size,
				base
					* CFrame.new(
						rng:NextNumber(-r.w / 2, r.w / 2),
						size.Y / 3,
						rng:NextNumber(-r.d / 2, r.d / 2)
					)
					* CFrame.Angles(
						rng:NextNumber(-0.4, 0.4),
						rng:NextNumber(0, 3),
						rng:NextNumber(-0.4, 0.4)
					),
				Color3.fromRGB(116, 112, 104),
				Enum.Material.Slate
			)
		end
		-- ivy reclaiming the frame
		for _ = 1, 4 do
			local height = rng:NextNumber(6, storey * 3)
			prop(
				folder,
				"Ivy",
				Vector3.new(rng:NextNumber(3, 6), height, 0.3),
				base * CFrame.new(rng:NextNumber(-r.w / 2, r.w / 2), height / 2, -r.d / 2.2 - 0.9),
				Color3.fromRGB(56, 92, 44),
				Enum.Material.Grass
			)
		end
	end

	-- Trees and scrub returning: clustered crowns in several greens
	local greens = {
		Color3.fromRGB(62, 98, 46),
		Color3.fromRGB(78, 112, 52),
		Color3.fromRGB(52, 84, 40),
		Color3.fromRGB(92, 118, 60),
	}
	for _ = 1, 34 do
		local x, z = rng:NextNumber(-210, 210), rng:NextNumber(-210, 230)
		if math.abs(x) > 30 or math.abs(z) > 30 then
			local trunkHeight = rng:NextNumber(8, 18)
			local lean = CFrame.Angles(rng:NextNumber(-0.08, 0.08), 0, rng:NextNumber(-0.08, 0.08))
			local treeBase = CFrame.new(at(x, y, z)) * lean
			local trunk = part(
				folder,
				"Trunk",
				Vector3.new(trunkHeight, rng:NextNumber(0.7, 1.2), rng:NextNumber(0.7, 1.2)),
				treeBase * CFrame.new(0, trunkHeight / 2, 0) * CFrame.Angles(0, 0, math.pi / 2),
				Color3.fromRGB(74, 58, 44),
				Enum.Material.Wood
			)
			trunk.Shape = Enum.PartType.Cylinder
			local top = treeBase * CFrame.new(0, trunkHeight, 0)
			for k = 1, rng:NextInteger(4, 7) do
				local radius = rng:NextNumber(3, 6.5)
				local crown = ball(
					folder,
					"Crown",
					radius * 2,
					(top * CFrame.new(
						rng:NextNumber(-3.5, 3.5),
						rng:NextNumber(-1, 4) + k * 0.4,
						rng:NextNumber(-3.5, 3.5)
					)).Position,
					greens[rng:NextInteger(1, #greens)],
					Enum.Material.Grass
				)
				crown.CanCollide = false
			end
		end
	end
	for _ = 1, 60 do
		local x, z = rng:NextNumber(-220, 220), rng:NextNumber(-220, 240)
		if math.abs(x) > 24 or math.abs(z) > 24 then
			local bush = ball(
				folder,
				"Scrub",
				rng:NextNumber(2, 4.5),
				at(x, y + 0.8, z),
				greens[rng:NextInteger(1, #greens)],
				Enum.Material.Grass
			)
			bush.CanCollide = false
		end
	end
	-- A dormant machine of the old world, half buried
	local machine = newModel(folder, "DormantMachine")
	part(
		machine,
		"Body",
		Vector3.new(18, 10, 12),
		CFrame.new(at(-70, y + 3, 70)) * CFrame.Angles(0.1, 0.6, 0.15),
		Color3.fromRGB(70, 66, 60),
		Enum.Material.CorrodedMetal
	)
	part(
		machine,
		"Arm",
		Vector3.new(26, 2.4, 2.4),
		CFrame.new(at(-58, y + 8, 64)) * CFrame.Angles(0, 0.6, 0.5),
		Color3.fromRGB(80, 74, 66),
		Enum.Material.CorrodedMetal
	)
	local eye = prop(
		machine,
		"Eye",
		Vector3.new(1.2, 1.2, 0.3),
		CFrame.new(at(-63.5, y + 5, 64.6)) * CFrame.Angles(0, 0.6, 0),
		Color3.fromRGB(80, 20, 20),
		Enum.Material.Glass
	)
	eye.Transparency = 0.2

	-- Invisible boundary so the courier drone doesn't wander off
	for _, b in
		{ { 0, -250, 520, 2 }, { 0, 270, 520, 2 }, { -250, 10, 2, 520 }, { 250, 10, 2, 520 } }
	do
		local wall =
			volume(folder, "Boundary", at(b[1], y + 60, b[2]), Vector3.new(b[3], 140, b[4]))
		wall.CanCollide = true
	end

	airZone(folder, at(0, y + 50, 10), Vector3.new(500, 100, 520), {
		Label = "SURFACE · MET STATION 4",
		O2 = 20.8,
		CO2 = 428,
		PM = 9,
		Temp = 17,
		Verdict = "VERDICT: BREATHABLE. Comparable to pre-collapse rural air.",
		Objective = "HSurfaceAir",
	})
end

---------------------------------------------------------------------------
-- Entry
---------------------------------------------------------------------------

local HollowBuilder = {}

local built: Folder? = nil

function HollowBuilder.get(): Folder
	if built then
		return built
	end
	local root = Instance.new("Folder")
	root.Name = "TheHollow"
	root:SetAttribute("Site", "Hollow")
	built = root

	buildTerrain()
	buildWell(root)
	buildPit(root)
	buildStair(root)
	buildCollector(root)
	buildQuarantine(root)
	local spawn = buildHub(root)
	buildUpperLevels(root)
	buildShaft(root)
	buildSurface(root)

	-- Relays below the deck count toward OP-2
	local relayZone = volume(root, "RelayZone", at(0, -4, 0), Vector3.new(480, 82, 480))
	relayZone:SetAttribute("Objective", "HRelays")
	CollectionService:AddTag(relayZone, "RelayZone")

	local relays = Instance.new("Folder")
	relays.Name = "Relays"
	relays.Parent = root

	-- The rock walls of the Well are dark; make sure nothing renders as plastic
	for _, descendant in root:GetDescendants() do
		if
			descendant:IsA("BasePart")
			and descendant.Material == Enum.Material.SmoothPlastic
			and descendant.Transparency < 1
		then
			if descendant.Name ~= "Panel" and descendant.Name ~= "Sign" then
				descendant.Reflectance = 0
			end
		end
	end

	Registry.roots.Hollow = root
	Registry.spawns.Hollow = spawn

	if not Workspace:FindFirstChild("Drones") then
		local drones = Instance.new("Folder")
		drones.Name = "Drones"
		drones.Parent = Workspace
	end
	root.Parent = Workspace

	-- Flood the collector and the Underpass to their starting levels
	fillNow(TUNNEL)
	fillNow(UNDERPASS)
	Workspace:SetAttribute("UnderpassFlooded", true)
	return root
end

function HollowBuilder.init()
	HollowBuilder.get()
end

return HollowBuilder
