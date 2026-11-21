--!strict
-- One drone per pilot. There is no character (CharacterAutoLoads = false):
-- the drone IS the player. The drone is an unanchored assembly whose physics
-- is owned by the pilot's client for smooth, lag-free flight; the server owns
-- its *state* (installed modules, cargo, data packet, relays, grabbed debris).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Devices = require(ReplicatedStorage.Shared.Util.Devices)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local Sites = require(ReplicatedStorage.Shared.Util.Sites)

local Feedback = require(script.Parent.Parent.Feedback)
local Net = require(script.Parent.Parent.Net)
local Registry = require(script.Parent.Parent.Registry)
local HollowBuilder = require(script.Parent.HollowBuilder)
local WorldBuilder = require(script.Parent.WorldBuilder)

local HULL = Color3.fromRGB(38, 40, 46)
local METAL = Color3.fromRGB(110, 114, 122)
local METAL_DARK = Color3.fromRGB(52, 54, 60)
local CYAN = Color3.fromRGB(0, 230, 255)
local RED = Color3.fromRGB(255, 50, 50)
local WHITE = Color3.fromRGB(230, 230, 225)

local ROTOR_OFFSETS = {
	Vector3.new(-1.7, 0.35, -1.7),
	Vector3.new(1.7, 0.35, -1.7),
	Vector3.new(-1.7, 0.35, 1.7),
	Vector3.new(1.7, 0.35, 1.7),
}

local DroneService = {
	-- fired(player, debris) whenever a pilot lets go of debris for any reason
	Released = Signal.new(),
}

local drones: { [Player]: Model } = {}
local carried: { [Player]: BasePart } = {}
local spawnIndex = 0

-- Welding parts on or off an assembly can reset manual network ownership,
-- which would hand physics back to the server and freeze the pilot's controls.
-- Re-assert ownership after every assembly change (and periodically).
local function reclaim(player: Player)
	local drone = drones[player]
	local hull = drone and drone.PrimaryPart
	if not hull or not hull:IsDescendantOf(Workspace) then
		return
	end
	pcall(function()
		if hull:GetNetworkOwner() ~= player then
			hull:SetNetworkOwner(player)
		end
	end)
end

local function weldTo(hull: BasePart, part: BasePart)
	part.Anchored = false
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = hull
	weld.Part1 = part
	weld.Parent = part
end

local function newPiece(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material?
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material or Enum.Material.Metal
	-- The drone carries its own headlight: no self-shadowing of the lens
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

-- Builds the physical module hanging from hardpoint A (left) or B (right).
local function buildModule(drone: Model, hull: BasePart, hardpoint: string, module: string)
	local existing = drone:FindFirstChild("Module" .. hardpoint)
	if existing then
		existing:Destroy()
	end
	local spec = Config.MODULES[module]
	if not spec then
		return
	end
	local holder = Instance.new("Model")
	holder.Name = "Module" .. hardpoint
	holder:SetAttribute("Module", module)
	local side = if hardpoint == "A" then -1 else 1
	local mount = hull.CFrame * CFrame.new(side * 0.75, -0.55, 0)
	local color = spec.color

	local function piece(
		name: string,
		size: Vector3,
		offset: CFrame,
		partColor: Color3,
		material: Enum.Material?
	): Part
		local part = newPiece(holder, name, size, mount * offset, partColor, material)
		weldTo(hull, part)
		return part
	end

	if module == "Sensor" then
		piece("Pod", Vector3.new(0.6, 0.5, 1), CFrame.identity, METAL_DARK)
		piece("Probe", Vector3.new(0.12, 0.12, 1.2), CFrame.new(0, -0.05, -0.9), METAL)
		piece(
			"Tip",
			Vector3.new(0.24, 0.24, 0.24),
			CFrame.new(0, -0.05, -1.5),
			color,
			Enum.Material.Neon
		)
		piece(
			"Intake",
			Vector3.new(0.5, 0.15, 0.4),
			CFrame.new(0, -0.3, 0.2),
			color,
			Enum.Material.Neon
		)
	elseif module == "Arm" then
		piece("Shoulder", Vector3.new(0.5, 0.5, 0.5), CFrame.identity, METAL_DARK)
		piece(
			"Upper",
			Vector3.new(0.25, 0.25, 1.2),
			CFrame.new(0, -0.35, -0.5) * CFrame.Angles(math.rad(35), 0, 0),
			color
		)
		piece(
			"Fore",
			Vector3.new(0.22, 0.22, 1),
			CFrame.new(0, -0.85, -1.1) * CFrame.Angles(math.rad(-25), 0, 0),
			color
		)
		piece("Claw", Vector3.new(0.6, 0.3, 0.5), CFrame.new(0, -1.25, -1.4), METAL)
		piece("FingerL", Vector3.new(0.1, 0.5, 0.15), CFrame.new(-0.22, -1.55, -1.4), METAL)
		piece("FingerR", Vector3.new(0.1, 0.5, 0.15), CFrame.new(0.22, -1.55, -1.4), METAL)
	elseif module == "DataJack" then
		piece("Housing", Vector3.new(0.6, 0.5, 0.8), CFrame.identity, METAL_DARK)
		piece(
			"Spike",
			Vector3.new(0.12, 0.12, 1),
			CFrame.new(0, 0, -0.85),
			color,
			Enum.Material.Neon
		)
		piece("RelayStack", Vector3.new(0.5, 0.35, 0.5), CFrame.new(0, -0.4, 0.15), color)
	elseif module == "Payload" then
		piece("CageTop", Vector3.new(1.4, 0.12, 1.4), CFrame.new(0, -0.05, 0), METAL_DARK)
		for _, corner in
			{
				Vector3.new(-0.65, 0, -0.65),
				Vector3.new(0.65, 0, -0.65),
				Vector3.new(-0.65, 0, 0.65),
				Vector3.new(0.65, 0, 0.65),
			}
		do
			piece(
				"Post",
				Vector3.new(0.1, 1.1, 0.1),
				CFrame.new(corner + Vector3.new(0, -0.6, 0)),
				METAL_DARK
			)
		end
		local loaded = drone:GetAttribute("Payload") == true
		local cargo = piece(
			"Cargo",
			Vector3.new(1.1, 0.9, 1.1),
			CFrame.new(0, -0.65, 0),
			WHITE,
			Enum.Material.SmoothPlastic
		)
		cargo.Transparency = if loaded then 0 else 1
		local cross = piece(
			"CargoCross",
			Vector3.new(0.6, 0.15, 0.02),
			CFrame.new(0, -0.6, -0.56),
			RED,
			Enum.Material.Neon
		)
		cross.Transparency = if loaded then 0 else 1
	end
	holder.Parent = drone
end

local function buildDrone(player: Player, spawn: CFrame): Model
	local drone = Instance.new("Model")
	drone.Name = "Drone_" .. player.UserId

	local hull =
		newPiece(drone, "Hull", Vector3.new(2.6, 0.7, 2.6), spawn, HULL, Enum.Material.Metal)
	hull.CustomPhysicalProperties = PhysicalProperties.new(0.7, 0.3, 0.1, 1, 1)

	local function piece(
		name: string,
		size: Vector3,
		offset: CFrame,
		color: Color3,
		material: Enum.Material?
	): Part
		local part = newPiece(drone, name, size, spawn * offset, color, material)
		weldTo(hull, part)
		return part
	end

	piece("Shell", Vector3.new(2.1, 0.35, 2.1), CFrame.new(0, 0.5, 0.1), Color3.fromRGB(28, 30, 34))
	piece(
		"Stripe",
		Vector3.new(1.4, 0.06, 0.15),
		CFrame.new(0, 0.7, -0.8),
		CYAN,
		Enum.Material.Neon
	)
	local lens = piece(
		"Lens",
		Vector3.new(0.3, 0.55, 0.55),
		CFrame.new(0, -0.05, -1.35) * CFrame.Angles(0, math.pi / 2, 0),
		Color3.fromRGB(10, 20, 30),
		Enum.Material.Glass
	)
	lens.Shape = Enum.PartType.Cylinder
	piece(
		"LensRing",
		Vector3.new(0.1, 0.1, 0.1),
		CFrame.new(0, 0.25, -1.32),
		CYAN,
		Enum.Material.Neon
	)
	piece(
		"TailLight",
		Vector3.new(0.5, 0.1, 0.1),
		CFrame.new(0, 0.1, 1.33),
		RED,
		Enum.Material.Neon
	)
	-- Aviation-style nav lights (red port / green starboard) and an anti-collision strobe
	local port = piece(
		"NavPort",
		Vector3.new(0.16, 0.16, 0.16),
		CFrame.new(-2.6, 0.35, -1.7),
		Color3.fromRGB(255, 30, 30),
		Enum.Material.Neon
	)
	local starboard = piece(
		"NavStarboard",
		Vector3.new(0.16, 0.16, 0.16),
		CFrame.new(2.6, 0.35, -1.7),
		Color3.fromRGB(30, 255, 80),
		Enum.Material.Neon
	)
	for _, nav in { port, starboard } do
		local glow = Instance.new("PointLight")
		glow.Color = nav.Color
		glow.Range = 5
		glow.Brightness = 0.6
		glow.Parent = nav
	end
	local strobe = piece(
		"Strobe",
		Vector3.new(0.2, 0.12, 0.2),
		CFrame.new(0, 0.55, 1.1),
		WHITE,
		Enum.Material.Neon
	)
	local flash = Instance.new("PointLight")
	flash.Name = "Flash"
	flash.Color = WHITE
	flash.Range = 9
	flash.Brightness = 0
	flash.Parent = strobe
	-- LiDAR puck on top (spins on clients)
	local puck = piece(
		"Lidar",
		Vector3.new(0.45, 0.7, 0.7),
		CFrame.new(0, 0.9, -0.2) * CFrame.Angles(0, 0, math.pi / 2),
		Color3.fromRGB(24, 24, 28),
		Enum.Material.Metal
	)
	puck.Shape = Enum.PartType.Cylinder
	piece(
		"LidarWindow",
		Vector3.new(0.12, 0.74, 0.74),
		CFrame.new(0, 0.95, -0.2) * CFrame.Angles(0, 0, math.pi / 2),
		Color3.fromRGB(30, 10, 10),
		Enum.Material.Glass
	).Shape =
		Enum.PartType.Cylinder

	for index, offset in ROTOR_OFFSETS do
		local armCenter = offset * Vector3.new(0.5, 0, 0.5)
		piece(
			"Arm",
			Vector3.new(0.25, 0.2, offset.Magnitude),
			CFrame.lookAt(armCenter, offset * Vector3.new(1, 0, 1)),
			METAL_DARK
		)
		local motor = piece(
			"Motor",
			Vector3.new(0.45, 0.4, 0.4),
			CFrame.new(offset) * CFrame.Angles(0, 0, math.pi / 2),
			METAL
		)
		motor.Shape = Enum.PartType.Cylinder
		local guard = piece(
			"Guard",
			Vector3.new(0.1, 2.1, 2.1),
			CFrame.new(offset + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.pi / 2),
			Color3.fromRGB(60, 62, 70)
		)
		guard.Shape = Enum.PartType.Cylinder
		guard.Transparency = 0.7

		-- Rotor blade on a Weld so clients can spin it by animating C0
		local blade = newPiece(
			drone,
			"Rotor",
			Vector3.new(1.8, 0.05, 0.22),
			spawn * CFrame.new(offset + Vector3.new(0, 0.25, 0)),
			Color3.fromRGB(20, 20, 22)
		)
		blade.Anchored = false
		blade.CanCollide = false
		blade.CanQuery = false
		blade.CanTouch = false
		blade.Massless = true
		blade:SetAttribute("Spin", if index % 2 == 0 then 1 else -1)
		local weld = Instance.new("Weld")
		weld.Name = "RotorWeld"
		weld.Part0 = hull
		weld.Part1 = blade
		weld.C0 = CFrame.new(offset + Vector3.new(0, 0.25, 0))
		weld.Parent = blade
	end

	local headlight = Instance.new("SpotLight")
	headlight.Name = "Headlight"
	headlight.Face = Enum.NormalId.Front
	headlight.Range = 60
	headlight.Angle = 70
	headlight.Brightness = 2.6
	headlight.Color = Color3.fromRGB(235, 245, 255)
	headlight.Shadows = true
	headlight.Parent = hull

	local center = Instance.new("Attachment")
	center.Name = "Center"
	center.Parent = hull

	local velocity = Instance.new("LinearVelocity")
	velocity.Name = "Thrust"
	velocity.Attachment0 = center
	velocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.MaxForce = Config.DRONE.MAX_FORCE
	velocity.VectorVelocity = Vector3.zero
	velocity.Parent = hull

	local gyro = Instance.new("AlignOrientation")
	gyro.Name = "Gyro"
	gyro.Mode = Enum.OrientationAlignmentMode.OneAttachment
	gyro.Attachment0 = center
	gyro.MaxTorque = 1e6
	gyro.Responsiveness = 30
	gyro.CFrame = spawn.Rotation
	gyro.Parent = hull

	drone.PrimaryPart = hull
	CollectionService:AddTag(drone, "Drone")
	drone:SetAttribute("Owner", player.UserId)
	drone:SetAttribute("Pilot", player.DisplayName)
	drone:SetAttribute("HardpointA", Config.DEFAULT_LOADOUT.A)
	drone:SetAttribute("HardpointB", Config.DEFAULT_LOADOUT.B)
	drone:SetAttribute("Holding", false)
	drone:SetAttribute("Payload", false)
	drone:SetAttribute("Packet", "")
	drone:SetAttribute("Relays", Config.DRONE.MAX_RELAYS)
	drone:SetAttribute("Temperature", Config.DRONE.TEMPERATURE)
	buildModule(drone, hull, "A", Config.DEFAULT_LOADOUT.A)
	buildModule(drone, hull, "B", Config.DEFAULT_LOADOUT.B)
	return drone
end

function DroneService.get(player: Player): Model?
	return drones[player]
end

function DroneService.hull(player: Player): BasePart?
	local drone = drones[player]
	local hull = drone and drone.PrimaryPart
	return hull
end

function DroneService.carried(player: Player): BasePart?
	return carried[player]
end

local function findPart(drone: Model, moduleName: string, partName: string): BasePart?
	for _, hardpoint in { "A", "B" } do
		local holder = drone:FindFirstChild("Module" .. hardpoint)
		if holder and holder:GetAttribute("Module") == moduleName then
			local part = holder:FindFirstChild(partName)
			if part and part:IsA("BasePart") then
				return part
			end
		end
	end
	return nil
end

function DroneService.setCargo(drone: Model, loaded: boolean)
	drone:SetAttribute("Payload", loaded)
	for _, name in { "Cargo", "CargoCross" } do
		local part = findPart(drone, "Payload", name)
		if part then
			part.Transparency = if loaded then 0 else 1
		end
	end
end

function DroneService.grab(player: Player, debris: BasePart): boolean
	local drone = drones[player]
	local hull = DroneService.hull(player)
	if not drone or not hull or carried[player] then
		return false
	end
	local claw = findPart(drone, "Arm", "Claw")
	if not claw then
		return false
	end
	debris.Anchored = false
	debris.CFrame = claw.CFrame * CFrame.new(0, -(debris.Size.Y / 2 + 0.45), 0)
	debris.CanCollide = false
	debris.Massless = true
	local weld = Instance.new("WeldConstraint")
	weld.Name = "GrabWeld"
	weld.Part0 = claw
	weld.Part1 = debris
	weld.Parent = debris
	debris:SetAttribute("Carried", true)
	drone:SetAttribute("Holding", true)
	carried[player] = debris
	reclaim(player)
	return true
end

function DroneService.release(player: Player)
	local debris = carried[player]
	if not debris then
		return
	end
	carried[player] = nil
	local weld = debris:FindFirstChild("GrabWeld")
	if weld then
		weld:Destroy()
	end
	debris.CanCollide = true
	debris.Massless = false
	debris:SetAttribute("Carried", false)
	local drone = drones[player]
	if drone then
		drone:SetAttribute("Holding", false)
	end
	reclaim(player)
	DroneService.Released.fire(player, debris)
end

function DroneService.nearDock(player: Player): boolean
	local hull = DroneService.hull(player)
	if not hull then
		return false
	end
	for _, dock in CollectionService:GetTagged("Device") do
		if
			dock:GetAttribute("DeviceType") == "Dock"
			and (Devices.position(dock) - hull.Position).Magnitude
				<= Config.DRONE.DOCK_RANGE + 2
		then
			return true
		end
	end
	return false
end

local function spawnFor(player: Player)
	if drones[player] then
		return
	end
	spawnIndex += 1
	local offset = ((spawnIndex - 1) % 4 - 1.5) * 4
	local drone = buildDrone(player, DroneService.spawnPoint(Config.DEFAULT_SITE, offset))
	local folder = Workspace:FindFirstChild("Drones") or Workspace
	drone.Parent = folder
	drones[player] = drone
	local hull = drone.PrimaryPart
	if hull then
		hull:SetNetworkOwner(player)
	end
end

local function despawn(player: Player)
	DroneService.release(player)
	local drone = drones[player]
	if drone then
		drone:Destroy()
	end
	drones[player] = nil
end

function DroneService.spawnPoint(site: string, offset: number?): CFrame
	local spawn = Registry.spawns[site]
		or Registry.spawns[Config.DEFAULT_SITE]
		or CFrame.new(0, 10, 0)
	return spawn * CFrame.new(offset or 0, 0, 0)
end

local function moveTo(player: Player, cframe: CFrame)
	local drone = drones[player]
	if not drone then
		return
	end
	DroneService.release(player)
	drone:PivotTo(cframe)
	local hull = drone.PrimaryPart
	if hull then
		hull.AssemblyLinearVelocity = Vector3.zero
		hull.AssemblyAngularVelocity = Vector3.zero
	end
	reclaim(player)
end

function DroneService.init()
	WorldBuilder.get()
	HollowBuilder.get()

	Players.PlayerAdded:Connect(spawnFor)
	for _, player in Players:GetPlayers() do
		spawnFor(player)
	end
	Players.PlayerRemoving:Connect(despawn)

	Net.on("SetLoadout", 1, function(player: Player, raw: unknown)
		local drone = drones[player]
		local hull = DroneService.hull(player)
		if not drone or not hull or typeof(raw) ~= "table" then
			return
		end
		local loadout = raw :: { [unknown]: unknown }
		local a, b = loadout.A, loadout.B
		if typeof(a) ~= "string" or typeof(b) ~= "string" or a == b then
			return
		end
		if not Config.MODULES[a] or not Config.MODULES[b] then
			return
		end
		if not DroneService.nearDock(player) then
			Feedback.send(
				player,
				"LOADOUT",
				"Module swap needs a dock. Fly onto a dock pad first.",
				"warning"
			)
			return
		end
		if a ~= "Arm" and b ~= "Arm" then
			DroneService.release(player)
		end
		if a ~= "Payload" and b ~= "Payload" then
			drone:SetAttribute("Payload", false)
		end
		drone:SetAttribute("HardpointA", a)
		drone:SetAttribute("HardpointB", b)
		buildModule(drone, hull, "A", a)
		buildModule(drone, hull, "B", b)
		reclaim(player)
		-- Docks restock relay nodes
		drone:SetAttribute("Relays", Config.DRONE.MAX_RELAYS)
		Feedback.send(
			player,
			"LOADOUT",
			("A: %s\nB: %s"):format(Config.MODULES[a].label, Config.MODULES[b].label),
			"success"
		)
	end)

	Net.on("Recall", 3, function(player: Player)
		local hull = DroneService.hull(player)
		if not hull then
			return
		end
		local site = Sites.at(hull.Position)
		moveTo(player, DroneService.spawnPoint(site))
		Feedback.send(player, "RECALL", "Drone returned to the home dock.", "info")
	end)

	Net.on("SelectSite", 2, function(player: Player, raw: unknown)
		if typeof(raw) ~= "string" or not Config.SITES[raw] then
			return
		end
		moveTo(player, DroneService.spawnPoint(raw))
		player:SetAttribute("Site", raw)
		Feedback.send(player, "DEPLOYED", Config.SITES[raw].name, "info")
	end)
end

function DroneService.start()
	while true do
		task.wait(2)
		for player in drones do
			reclaim(player)
		end
	end
end

return DroneService
