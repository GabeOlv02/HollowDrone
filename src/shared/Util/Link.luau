--!strict
-- Command-link strength (0..1) from docks, mesh relays and active beacons,
-- crushed near an active Directorate jammer. Server and client run the same
-- math: the client draws static, the server refuses commands when the link is lost.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)
local Devices = require(script.Parent.Devices)

local Link = {}

function Link.gather(): ({ Types.LinkSource }, { Types.JammerInfo })
	local sources: { Types.LinkSource } = {}
	for _, instance in CollectionService:GetTagged("LinkSource") do
		local range = instance:GetAttribute("LinkRange")
		if typeof(range) == "number" and range > 0 and instance:IsDescendantOf(workspace) then
			table.insert(sources, { position = Devices.position(instance), range = range })
		end
	end
	local jammers: { Types.JammerInfo } = {}
	for _, instance in CollectionService:GetTagged("Jammer") do
		if instance:GetAttribute("Active") == true then
			local radius = instance:GetAttribute("JamRadius")
			local factor = instance:GetAttribute("JamFactor")
			table.insert(jammers, {
				position = Devices.position(instance),
				radius = if typeof(radius) == "number" then radius else Config.LINK.JAMMER_RADIUS,
				factor = if typeof(factor) == "number" then factor else Config.LINK.JAMMER_FACTOR,
			})
		end
	end
	return sources, jammers
end

local occlusionParams = RaycastParams.new()
occlusionParams.FilterType = Enum.RaycastFilterType.Exclude
occlusionParams.RespectCanCollide = true

-- Radio through rock and concrete: the usable range drops when the direct
-- path is blocked. Only solid, collidable geometry counts.
local function blocked(from: Vector3, to: Vector3): boolean
	local drones = Workspace:FindFirstChild("Drones")
	occlusionParams.FilterDescendantsInstances = if drones then { drones } else {}
	local delta = to - from
	if delta.Magnitude < 4 then
		return false
	end
	local hit = Workspace:Raycast(from, delta, occlusionParams)
	return hit ~= nil and (hit.Position - to).Magnitude > 4
end

function Link.strength(
	position: Vector3,
	sources: { Types.LinkSource },
	jammers: { Types.JammerInfo },
	occlusion: boolean?
): number
	local best = 0
	for _, source in sources do
		local distance = (position - source.position).Magnitude
		if distance < source.range then
			local range = source.range
			if
				occlusion ~= false and blocked(position, source.position + Vector3.new(0, 1.5, 0))
			then
				range *= Config.LINK.OCCLUSION
			end
			best = math.max(best, 1 - distance / range)
		end
	end
	for _, jammer in jammers do
		if (position - jammer.position).Magnitude < jammer.radius then
			best *= jammer.factor
		end
	end
	return math.clamp(best, 0, 1)
end

function Link.at(position: Vector3): number
	local sources, jammers = Link.gather()
	return Link.strength(position, sources, jammers)
end

return Link
