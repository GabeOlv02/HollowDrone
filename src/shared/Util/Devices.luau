--!strict
-- Device lookup and the action table. Shared so the HUD shows exactly the
-- action the server will run: the server resolves the same way, then
-- validates range, line of sight, link and module before acting.

local CollectionService = game:GetService("CollectionService")

local Devices = {}

-- Walks up from any part to the tagged device root (or nil).
function Devices.root(instance: Instance?): Instance?
	local current = instance
	local depth = 0
	while current and depth < 6 do
		if CollectionService:HasTag(current, "Device") then
			return current
		end
		current = current.Parent
		depth += 1
	end
	return nil
end

function Devices.typeOf(device: Instance?): string?
	if not device then
		return nil
	end
	local value = device:GetAttribute("DeviceType")
	return if typeof(value) == "string" then value else nil
end

function Devices.position(device: Instance): Vector3
	if device:IsA("BasePart") then
		return device.Position
	elseif device:IsA("Model") then
		return device:GetPivot().Position
	end
	return Vector3.zero
end

-- Rough radius of a device, used as range slack.
function Devices.extent(device: Instance): number
	if device:IsA("BasePart") then
		return math.min(device.Size.Magnitude / 2, 6)
	elseif device:IsA("Model") then
		return math.min(device:GetExtentsSize().Magnitude / 2, 6)
	end
	return 0
end

-- Returns (actionId, label) for a module action against an optional device.
-- `drone` carries state attributes: Holding, Payload, Relays.
function Devices.resolve(
	module: string?,
	kind: string,
	deviceType: string?,
	drone: Instance
): (string?, string?)
	local holding = drone:GetAttribute("Holding") == true
	local loaded = drone:GetAttribute("Payload") == true
	local relays = drone:GetAttribute("Relays")
	local relaysLeft = if typeof(relays) == "number" then relays else 0

	-- Guiding people uses the airframe's own beeper + light: any module
	if deviceType == "Civilian" and kind == "Primary" then
		return "Guide", "Guide (beep + light, follow me)"
	end

	if module == "Arm" and kind == "Primary" then
		if holding then
			return "Release", "Release debris"
		elseif deviceType == "Valve" then
			return "TurnValve", "Turn valve"
		elseif deviceType == "Debris" then
			return "Grab", "Grab debris"
		elseif deviceType == "Breaker" then
			return "FlipBreaker", "Flip breaker"
		elseif deviceType == "Jammer" then
			return "CutCable", "Cut power cable"
		end
	elseif module == "Sensor" and kind == "Primary" then
		if deviceType == "SamplePoint" then
			return "SampleWater", "Sample water"
		elseif deviceType == "Resident" or deviceType == "HeatSource" then
			return "ReadVitals", "Read vitals"
		elseif deviceType == "Equipment" then
			return "Inspect", "Run diagnostics"
		end
		return "SampleAir", "Sample air"
	elseif module == "DataJack" then
		if kind == "Primary" then
			if deviceType == "Terminal" then
				return "JackIn", "Jack in"
			elseif deviceType == "Beacon" then
				return "PingBeacon", "Ping beacon"
			end
		else
			if deviceType == "RelayNode" then
				return "RetrieveRelay", "Retrieve relay"
			elseif relaysLeft > 0 then
				return "DeployRelay", ("Deploy relay (%d left)"):format(relaysLeft)
			end
		end
	elseif module == "Payload" and kind == "Primary" then
		if deviceType == "MedRack" and not loaded then
			return "LoadMed", "Load med kit"
		elseif loaded then
			return "DropMed", "Drop med kit"
		end
	end
	return nil, nil
end

return Devices
