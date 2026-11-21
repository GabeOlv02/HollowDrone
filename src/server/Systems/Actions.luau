--!strict
-- Every drone action goes through here. The client only says "Primary or
-- Secondary, on hardpoint A or B, at this thing". The server resolves the
-- action from the module that is actually installed, then checks range,
-- line of sight and command link before anything happens.

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Devices = require(ReplicatedStorage.Shared.Util.Devices)
local Gas = require(ReplicatedStorage.Shared.Util.Gas)
local Link = require(ReplicatedStorage.Shared.Util.Link)

local Sites = require(ReplicatedStorage.Shared.Util.Sites)
local Units = require(ReplicatedStorage.Shared.Util.Units)

local Feedback = require(script.Parent.Parent.Feedback)
local Mission = require(script.Parent.Parent.Mission)
local Net = require(script.Parent.Parent.Net)
local Registry = require(script.Parent.Parent.Registry)
local DroneService = require(script.Parent.DroneService)
local Environment = require(script.Parent.Environment)
local Guides = require(script.Parent.Guides)

local Actions = {}

type Context = {
	player: Player,
	drone: Model,
	hull: BasePart,
	device: Instance?,
}

local PACKETS = Config.PACKETS

local function attr(instance: Instance, key: string): any
	return instance:GetAttribute(key)
end

local function tagOf(device: Instance): string
	return ("%s"):format(tostring(attr(device, "DeviceId") or "UNKNOWN"))
end

local function labelOf(device: Instance): string
	return tostring(attr(device, "Label") or device.Name)
end

local function meters(studs: number): string
	return ("%.1fm"):format(studs * Config.STUDS_TO_METERS)
end

local function setTerminalText(terminal: Instance, text: string)
	local screen = terminal:FindFirstChild("Screen")
	local display = screen and screen:FindFirstChild("Display")
	local label = display and display:FindFirstChild("Text")
	if label and label:IsA("TextLabel") then
		label.Text = text
	end
end

-- Site folder for things the drone leaves behind (relays, med kits).
local function siteRoot(position: Vector3): Instance
	local root = Registry.roots[Sites.at(position)]
	return root or Workspace
end

local function objective(device: Instance, key: string): string?
	local value = device:GetAttribute(key)
	return if typeof(value) == "string" and value ~= "" then value else nil
end

local function totalOf(key: string): number
	for _, group in Config.OBJECTIVES do
		for _, item in group.items do
			if item.key == key then
				return item.total
			end
		end
	end
	return 0
end

---------------------------------------------------------------------------
-- Handlers
---------------------------------------------------------------------------

local HANDLERS: { [string]: (Context) -> () } = {}

HANDLERS.TurnValve = function(ctx)
	local valve = ctx.device
	if not valve or not valve:IsA("Model") then
		return
	end
	local open = attr(valve, "Open") ~= true
	valve:SetAttribute("Open", open)
	valve:SetAttribute("Status", if open then "OPEN" else "CLOSED")
	task.spawn(function()
		for _ = 1, 12 do
			valve:PivotTo(
				valve:GetPivot() * CFrame.Angles((if open then 1 else -1) * math.pi / 12, 0, 0)
			)
			task.wait(0.04)
		end
	end)
	local group = tostring(attr(valve, "FloodGroup") or "")
	local _, correct, effect = Environment.updateFlood(group)
	local spec = Registry.floods[group]
	local right = open == (attr(valve, "CorrectOpen") == true)
	Feedback.send(
		ctx.player,
		tagOf(valve),
		("%s\n-> %s. %s\n%s (%d/%d gates set)."):format(
			labelOf(valve),
			if open then "OPEN" else "CLOSED",
			if right then "Flow corrected." else "That works against drainage.",
			effect,
			correct,
			if spec then #spec.valves else 0
		),
		if right then "success" else "warning"
	)
end

HANDLERS.Grab = function(ctx)
	local debris = ctx.device
	if not debris or not debris:IsA("BasePart") or attr(debris, "Carried") == true then
		return
	end
	if DroneService.grab(ctx.player, debris) then
		local kg = math.floor(debris.Size.X * debris.Size.Y * debris.Size.Z * 6)
		Feedback.send(
			ctx.player,
			tagOf(debris),
			("Gripping %s (~%d kg). Carry it away from where it was stuck."):format(
				labelOf(debris),
				kg
			),
			"info"
		)
	end
end

HANDLERS.Release = function(ctx)
	DroneService.release(ctx.player)
end

HANDLERS.FlipBreaker = function(ctx)
	local breaker = ctx.device
	if not breaker then
		return
	end
	local on = attr(breaker, "On") ~= true
	local text = Environment.setVent(tostring(attr(breaker, "VentGroup") or ""), on)
	Feedback.send(ctx.player, tagOf(breaker), text, if on then "success" else "warning")
end

HANDLERS.CutCable = function(ctx)
	local jammer = ctx.device
	if not jammer or attr(jammer, "Active") ~= true then
		if jammer then
			Feedback.send(ctx.player, tagOf(jammer), "Jammer is already dead.", "info")
		end
		return
	end
	Environment.disableJammer(jammer)
	local key = objective(jammer, "Objective")
	if key then
		Mission.set(key, 1)
	end
	Feedback.send(
		ctx.player,
		tagOf(jammer),
		"Power cable cut. " .. tostring(attr(jammer, "CutText") or "Jammer offline."),
		"success"
	)
end

HANDLERS.SampleWater = function(ctx)
	local point = ctx.device
	if not point then
		return
	end
	local contaminated = attr(point, "Contaminated") == true
	local verdict = if contaminated then "CONTAMINATED - DO NOT DRINK" else "SAFE FOR RECYCLING"
	if attr(point, "Sampled") ~= true then
		point:SetAttribute("Sampled", true)
		local key = objective(point, "Objective")
		if key then
			Mission.add(key, 1)
		end
	end
	point:SetAttribute("Status", verdict)
	Feedback.send(
		ctx.player,
		"WATER SAMPLE // " .. tagOf(point),
		("%s\npH %.1f   Coliform %d CFU/100mL   Lead %d ug/L\nVERDICT: %s"):format(
			labelOf(point),
			attr(point, "PH") or 7,
			attr(point, "Coliform") or 0,
			attr(point, "Lead") or 0,
			verdict
		),
		if contaminated then "danger" else "data"
	)
end

HANDLERS.ReadVitals = function(ctx)
	local subject = ctx.device
	if not subject then
		return
	end
	if attr(subject, "DeviceType") == "HeatSource" then
		subject:SetAttribute("Status", "SPACE HEATER - NOT A PERSON")
		Feedback.send(
			ctx.player,
			"VITALS // " .. tagOf(subject),
			"No lifesign. Electric space heater at "
				.. Units.tempWhole(61)
				.. ".\nFire risk in a sealed block, but nobody here.",
			"data"
		)
		return
	end

	local condition = tostring(attr(subject, "Condition"))
	local temperature = attr(subject, "Temperature") or 37
	local treated = attr(subject, "Treated") == true
	if attr(subject, "Located") ~= true then
		subject:SetAttribute("Located", true)
		local key = objective(subject, "LocateObjective")
		if key then
			Mission.add(key, 1)
		end
	end

	-- Heart rate climbs ~10 bpm per °C of fever; SpO2 drops with lung sickness
	local fever = math.max(0, temperature - 37)
	local seed = #tostring(attr(subject, "Label") or "")
	local spo2, heartRate, assessment
	if treated then
		spo2 = 95 + seed % 3
		heartRate = math.floor(76 + fever * 10)
		assessment = if temperature >= Config.VITALS.FEVER_LINE
			then "TREATED - fever coming down"
			else "TREATED - recovered, temperature normal"
	elseif condition == "Fever" then
		spo2 = 89 + seed % 4
		heartRate = math.floor(82 + fever * 11 + seed % 6)
		assessment = "FEVER + coughing, lung sickness suspected -> NEEDS MED KIT"
	elseif condition == "Dehydrated" then
		spo2 = 96 + seed % 2
		heartRate = math.floor(98 + seed % 9)
		assessment = "TRAPPED, dehydrated -> NEEDS SUPPLIES"
	else
		spo2 = 97 + seed % 3
		heartRate = 64 + seed % 14
		assessment = "Stable, temperature in the healthy range. No aid needed."
	end
	if not treated then
		subject:SetAttribute(
			"Status",
			if condition == "Healthy"
				then "STABLE " .. Units.temp(temperature)
				else Units.temp(temperature) .. " - NEEDS AID"
		)
	end
	Feedback.send(
		ctx.player,
		"VITALS // " .. tagOf(subject),
		("%s\nTemp %s   SpO2 %d%%   HR %d\n%s"):format(
			labelOf(subject),
			Units.temp(temperature),
			spo2,
			heartRate,
			assessment
		),
		if condition == "Healthy" or treated then "data" else "warning"
	)
end

local function airZone(position: Vector3): Instance?
	for _, zone in CollectionService:GetTagged("AirZone") do
		if zone:IsA("BasePart") then
			local localPos = zone.CFrame:PointToObjectSpace(position)
			local half = zone.Size / 2
			if
				math.abs(localPos.X) <= half.X
				and math.abs(localPos.Y) <= half.Y
				and math.abs(localPos.Z) <= half.Z
			then
				return zone
			end
		end
	end
	return nil
end

HANDLERS.SampleAir = function(ctx)
	local readings = Gas.at(ctx.hull.Position, Gas.gather())
	local lines = {}
	local danger = false

	-- Bulk air composition (O2 / CO2 / particulates) from the zone the drone is in
	local zone = airZone(ctx.hull.Position)
	local base = Config.AIR_DEFAULT
	local function num(key: string, fallback: number): number
		local value = zone and zone:GetAttribute(key)
		return if typeof(value) == "number" then value else fallback
	end
	local o2 = num("O2", base.O2)
	local co2 = num("CO2", base.CO2) + (readings.CO2 or 0)
	local pm = num("PM", base.PM)
	local temp = num("Temp", base.Temp)
	local toxic: { [string]: number } = {}
	for gas, value in readings do
		if gas ~= "CO2" then
			toxic[gas] = value
		end
	end
	readings = toxic
	local o2Low = o2 < 19.5
	local co2High = co2 >= 5000
	danger = o2Low or co2High
	table.insert(
		lines,
		("O2 %.1f%%%s   CO2 %d ppm%s"):format(
			o2,
			if o2Low then " LOW" else "",
			math.floor(co2),
			if co2High then " HIGH" elseif co2 > 2000 then " (stuffy)" else ""
		)
	)
	table.insert(lines, ("PM2.5 %d µg/m³   AIR %s"):format(math.floor(pm), Units.tempWhole(temp)))
	for _, gas in { "H2S", "CH4", "Spores" } do
		local value = readings[gas]
		if value and value >= 0.5 then
			local spec = Config.GASES[gas]
			local harmful = value >= spec.danger
			danger = danger or harmful
			table.insert(
				lines,
				("%s %d %s%s"):format(
					spec.label,
					math.floor(value),
					spec.unit,
					if harmful then "  << DANGEROUS FOR HUMANS" else ""
				)
			)
		end
	end
	if #lines == 2 then
		table.insert(lines, "No toxic gas detected.")
	end
	local title = "AIR SAMPLE"
	if zone then
		title ..= " // " .. tostring(zone:GetAttribute("Label") or "ZONE")
		local verdict = zone:GetAttribute("Verdict")
		if typeof(verdict) == "string" then
			table.insert(lines, verdict)
		end
		local key = objective(zone, "Objective")
		if key and Mission.get(key) < 1 then
			Mission.set(key, 1)
			Workspace:SetAttribute(
				"SurfaceAir",
				("O2 %.1f%% · CO2 %d ppm · PM2.5 %d µg/m³ (drone sample)"):format(o2, co2, pm)
			)
		end
	else
		title ..= " // " .. meters(ctx.hull.Position.Y - 0) .. " ALT"
	end
	Feedback.send(ctx.player, title, table.concat(lines, "\n"), if danger then "danger" else "data")
end

HANDLERS.Inspect = function(ctx)
	local equipment = ctx.device
	if not equipment then
		return
	end
	if attr(equipment, "Inspected") ~= true then
		equipment:SetAttribute("Inspected", true)
		local key = objective(equipment, "Objective")
		if key then
			Mission.add(key, 1)
		end
		local verdict = attr(equipment, "Verdict")
		if typeof(verdict) == "string" then
			equipment:SetAttribute("Status", verdict)
		end
	end
	Feedback.send(
		ctx.player,
		"DIAGNOSTIC // " .. tagOf(equipment),
		labelOf(equipment) .. "\n" .. tostring(attr(equipment, "Diagnostic") or "Nominal."),
		if attr(equipment, "Severity") == "danger" then "danger" else "warning"
	)
end

HANDLERS.Guide = function(ctx)
	if ctx.device then
		Guides.toggle(ctx.player, ctx.device)
	end
end

HANDLERS.JackIn = function(ctx)
	local terminal = ctx.device
	if not terminal then
		return
	end
	local packet = tostring(attr(ctx.drone, "Packet") or "")
	local accepts = tostring(attr(terminal, "Accepts") or "")
	local offers = tostring(attr(terminal, "Offers") or "")

	if packet ~= "" and packet == accepts then
		local info = PACKETS[packet]
		ctx.drone:SetAttribute("Packet", "")
		terminal:SetAttribute("Accepts", "")
		Mission.set(info.objective, 1)
		setTerminalText(terminal, labelOf(terminal) .. "\nRECEIVED\n" .. packet)
		if info.event == "Broadcast" then
			task.defer(Environment.broadcast, ctx.player)
		end
		terminal:SetAttribute(
			"Status",
			if offers ~= "" then "DATA RECEIVED - HAS OUTBOUND PACKET" else "DATA RECEIVED"
		)
		Feedback.send(
			ctx.player,
			"UPLOAD // " .. tagOf(terminal),
			("Delivered %s to %s.%s"):format(
				info.name,
				labelOf(terminal),
				if offers ~= ""
					then "\nThis terminal has an outbound packet. Jack in again."
					else ""
			),
			"success"
		)
	elseif offers ~= "" then
		if packet ~= "" then
			Feedback.send(
				ctx.player,
				"DATA JACK",
				("Storage full: carrying %s. Deliver it first."):format(packet),
				"warning"
			)
			return
		end
		local info = PACKETS[offers]
		ctx.drone:SetAttribute("Packet", offers)
		local downloadKey = objective(terminal, "Objective")
		if downloadKey then
			Mission.set(downloadKey, 1)
		end
		terminal:SetAttribute("Offers", "")
		terminal:SetAttribute(
			"Status",
			if accepts ~= "" then "PACKET SENT - AWAITING INBOUND" else "PACKET SENT"
		)
		setTerminalText(terminal, labelOf(terminal) .. "\nPACKET COPIED\nTO COURIER DRONE")
		Feedback.send(
			ctx.player,
			"DOWNLOAD // " .. tagOf(terminal),
			("Copied %s (%s).\nDeliver to: %s"):format(info.name, offers, info.destination),
			"success"
		)
	elseif accepts ~= "" then
		Feedback.send(
			ctx.player,
			"DATA JACK",
			("%s is waiting for %s."):format(labelOf(terminal), accepts),
			"info"
		)
	else
		Feedback.send(
			ctx.player,
			"DATA JACK",
			("%s synced. Nothing left to transfer."):format(labelOf(terminal)),
			"info"
		)
	end
end

HANDLERS.PingBeacon = function(ctx)
	local beacon = ctx.device
	if not beacon then
		return
	end
	if attr(beacon, "Active") == true then
		Feedback.send(ctx.player, tagOf(beacon), "Beacon already broadcasting.", "info")
		return
	end
	Environment.activateBeacon(beacon)
	local key = objective(beacon, "Objective")
	if key then
		Mission.add(key, 1)
	end
	local message = attr(beacon, "Message")
	Feedback.send(
		ctx.player,
		tagOf(beacon),
		labelOf(beacon)
			.. " is broadcasting on the emergency band and extends the mesh."
			.. (if typeof(message) == "string" then "\nMESSAGE: " .. message else ""),
		"success"
	)
end

HANDLERS.DeployRelay = function(ctx)
	local relays = attr(ctx.drone, "Relays")
	if typeof(relays) ~= "number" or relays <= 0 then
		return
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude: { Instance } = { ctx.drone }
	local held = DroneService.carried(ctx.player)
	if held then
		table.insert(exclude, held)
	end
	params.FilterDescendantsInstances = exclude
	local hit = Workspace:Raycast(ctx.hull.Position, Vector3.new(0, -14, 0), params)
	local base = if hit then hit.Position else ctx.hull.Position - Vector3.new(0, 1.5, 0)

	local model = Instance.new("Model")
	model.Name = "RelayNode"
	local function part(
		name: string,
		size: Vector3,
		cf: CFrame,
		color: Color3,
		material: Enum.Material,
		shape: Enum.PartType?
	): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true
		p.Size = size
		p.CFrame = cf
		p.Color = color
		p.Material = material
		if shape then
			p.Shape = shape
		end
		p.CanCollide = false
		p.Parent = model
		return p
	end
	local foot = part(
		"Foot",
		Vector3.new(0.3, 1.6, 1.6),
		CFrame.new(base + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		Color3.fromRGB(40, 42, 48),
		Enum.Material.Metal,
		Enum.PartType.Cylinder
	)
	part(
		"Mast",
		Vector3.new(3, 0.25, 0.25),
		CFrame.new(base + Vector3.new(0, 1.8, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		Color3.fromRGB(110, 114, 122),
		Enum.Material.Metal,
		Enum.PartType.Cylinder
	)
	local tip = part(
		"Tip",
		Vector3.one * 0.7,
		CFrame.new(base + Vector3.new(0, 3.4, 0)),
		Config.MODULES.DataJack.color,
		Enum.Material.Neon,
		Enum.PartType.Ball
	)
	local glow = Instance.new("PointLight")
	glow.Color = tip.Color
	glow.Range = 10
	glow.Brightness = 1
	glow.Parent = tip
	model.PrimaryPart = foot

	local spec = Config.DEVICES.RelayNode
	model:SetAttribute("DeviceType", "RelayNode")
	model:SetAttribute("DeviceId", ("%s-%04X"):format(spec.prefix, math.random(0, 65535)))
	model:SetAttribute("Label", "Mesh relay (" .. ctx.player.DisplayName .. ")")
	model:SetAttribute("Status", "MESH NODE ONLINE")
	model:SetAttribute("LinkRange", Config.LINK.RELAY_RANGE)
	model:SetAttribute("Temperature", 35)
	model:SetAttribute("Owner", ctx.player.UserId)
	CollectionService:AddTag(model, "Device")
	CollectionService:AddTag(model, "LinkSource")
	local root = siteRoot(base)
	model.Parent = root:FindFirstChild("Relays") or root

	ctx.drone:SetAttribute("Relays", relays - 1)
	Environment.countRelays()
	Feedback.send(
		ctx.player,
		"MESH // " .. tostring(model:GetAttribute("DeviceId")),
		("Relay node deployed (%d left). Link here: %d%%."):format(
			relays - 1,
			math.floor(Link.at(ctx.hull.Position) * 100)
		),
		"success"
	)
end

HANDLERS.RetrieveRelay = function(ctx)
	local relay = ctx.device
	if not relay then
		return
	end
	local relays = attr(ctx.drone, "Relays")
	local count = if typeof(relays) == "number" then relays else 0
	if count >= Config.DRONE.MAX_RELAYS then
		Feedback.send(ctx.player, "MESH", "Relay rack is full.", "info")
		return
	end
	relay:Destroy()
	ctx.drone:SetAttribute("Relays", count + 1)
	Environment.countRelays()
	Feedback.send(
		ctx.player,
		"MESH",
		("Relay node recovered (%d carried)."):format(count + 1),
		"info"
	)
end

HANDLERS.LoadMed = function(ctx)
	DroneService.setCargo(ctx.drone, true)
	Feedback.send(
		ctx.player,
		"PAYLOAD",
		"Med kit loaded: antipyretics, antivirals, oral rehydration. Drop it within 3m of a patient.",
		"info"
	)
end

HANDLERS.DropMed = function(ctx)
	DroneService.setCargo(ctx.drone, false)
	local crate = Instance.new("Part")
	crate.Name = "MedKit"
	crate.Size = Vector3.new(1.1, 0.9, 1.1)
	crate.Color = Color3.fromRGB(230, 230, 225)
	crate.CFrame = ctx.hull.CFrame * CFrame.new(0, -1.8, 0)
	crate.Parent = siteRoot(ctx.hull.Position)
	local cross = Instance.new("Part")
	cross.Name = "Cross"
	cross.Size = Vector3.new(0.6, 0.15, 0.02)
	cross.Color = Color3.fromRGB(255, 50, 50)
	cross.Material = Enum.Material.Neon
	cross.CanCollide = false
	cross.Massless = true
	cross.CFrame = crate.CFrame * CFrame.new(0, 0.1, -0.56)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = crate
	weld.Part1 = cross
	weld.Parent = cross
	cross.Parent = crate
	Debris:AddItem(crate, 120)

	local player = ctx.player
	task.delay(1.5, function()
		if not crate.Parent then
			return
		end
		local best: Model? = nil
		local bestDistance = Config.MED_DROP_RADIUS
		for _, resident in CollectionService:GetTagged("Device") do
			if resident:GetAttribute("DeviceType") ~= "Resident" or not resident:IsA("Model") then
				continue
			end
			local distance = (Devices.position(resident) - crate.Position).Magnitude
			if distance <= bestDistance then
				best = resident
				bestDistance = distance
			end
		end
		if not best then
			Feedback.send(
				player,
				"PAYLOAD",
				"Med kit dropped, but no patient is within reach of it.",
				"warning"
			)
		elseif best:GetAttribute("NeedsAid") == true then
			best:SetAttribute("NeedsAid", false)
			best:SetAttribute("Treated", true)
			best:SetAttribute("Status", "TREATED")
			local key = objective(best, "TreatObjective")
			if key then
				Mission.add(key, 1)
			end
			Feedback.send(
				player,
				"PAYLOAD",
				("Med kit reached %s. Treatment started."):format(labelOf(best)),
				"success"
			)
		else
			Feedback.send(
				player,
				"PAYLOAD",
				("Med kit reached %s, who doesn't need it."):format(labelOf(best)),
				"info"
			)
		end
	end)
end

---------------------------------------------------------------------------
-- Validation + dispatch
---------------------------------------------------------------------------

local function lineOfSight(ctx: Context, device: Instance): boolean
	local target = Devices.position(device)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude: { Instance } = { ctx.drone, device }
	local held = DroneService.carried(ctx.player)
	if held then
		table.insert(exclude, held)
	end
	params.FilterDescendantsInstances = exclude
	local hit = Workspace:Raycast(ctx.hull.Position, target - ctx.hull.Position, params)
	return hit == nil or (hit.Position - target).Magnitude < 2.5
end

local function onDebrisReleased(player: Player, debris: BasePart)
	task.wait(1.5)
	if not debris.Parent or debris:GetAttribute("Cleared") == true then
		return
	end
	local home = debris:GetAttribute("Home")
	local key = debris:GetAttribute("Objective")
	if typeof(home) ~= "Vector3" or typeof(key) ~= "string" then
		return
	end
	if (debris.Position - home).Magnitude >= Config.DEBRIS_CLEAR_DISTANCE then
		debris:SetAttribute("Cleared", true)
		debris:SetAttribute("Status", "CLEARED")
		Mission.add(key, 1)
		local group = debris:GetAttribute("FloodGroup")
		local effect = ""
		if typeof(group) == "string" then
			local _, _, text = Environment.updateFlood(group)
			effect = "\n" .. text
		end
		Feedback.send(
			player,
			tagOf(debris),
			("%s cleared (%d/%d).%s"):format(
				labelOf(debris),
				Mission.get(key),
				totalOf(key),
				effect
			),
			"success"
		)
	else
		Feedback.send(
			player,
			tagOf(debris),
			"Dropped too close. Move it further away to clear the blockage.",
			"info"
		)
	end
end

function Actions.init()
	DroneService.Released.connect(onDebrisReleased)

	Net.on(
		"DroneAction",
		0.25,
		function(player: Player, rawKind: unknown, rawHardpoint: unknown, rawTarget: unknown)
			if rawKind ~= "Primary" and rawKind ~= "Secondary" then
				return
			end
			if rawHardpoint ~= "A" and rawHardpoint ~= "B" then
				return
			end
			local drone = DroneService.get(player)
			local hull = DroneService.hull(player)
			if not drone or not hull then
				return
			end
			local kind = rawKind :: string
			local module = drone:GetAttribute("Hardpoint" .. (rawHardpoint :: string))
			if typeof(module) ~= "string" then
				return
			end
			local ctx: Context = { player = player, drone = drone, hull = hull, device = nil }

			-- Resolve the target (untrusted): must be a real, tagged device in range and in sight
			local device: Instance? = nil
			if typeof(rawTarget) == "Instance" then
				local root = Devices.root(rawTarget)
				if root and root:IsDescendantOf(Workspace) then
					local distance = (Devices.position(root) - hull.Position).Magnitude
					if distance <= Config.DRONE.INTERACT_RANGE + Devices.extent(root) then
						device = root
					end
				end
			end
			if device and not lineOfSight(ctx, device) then
				Feedback.send(
					player,
					"NO LINE OF SIGHT",
					"Something is between the drone and the target. Get closer.",
					"warning"
				)
				return
			end

			local action = Devices.resolve(module, kind, Devices.typeOf(device), drone)
			if not action then
				return
			end

			-- Without a command link only the onboard failsafe (auto-deploy a relay) works
			if action ~= "DeployRelay" and Link.at(hull.Position) < Config.LINK.LOST then
				Feedback.send(
					player,
					"LINK LOST",
					"Command uplink down. Deploy a mesh relay, or fly back toward a dock.",
					"danger"
				)
				return
			end
			ctx.device = device
			local handler = HANDLERS[action]
			if handler then
				handler(ctx)
			end
		end
	)
end

return Actions
