--!strict
-- Gas concentration at a point from the tagged gas clouds (linear falloff).

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)

local Gas = {}

function Gas.gather(): { Types.GasCloud }
	local clouds: { Types.GasCloud } = {}
	for _, instance in CollectionService:GetTagged("GasCloud") do
		if instance:IsA("BasePart") then
			local gas = instance:GetAttribute("Gas")
			local peak = instance:GetAttribute("Peak")
			local radius = instance:GetAttribute("Radius")
			local scale = instance:GetAttribute("Scale")
			if
				typeof(gas) == "string"
				and typeof(peak) == "number"
				and typeof(radius) == "number"
			then
				table.insert(clouds, {
					position = instance.Position,
					gas = gas,
					peak = peak,
					radius = radius,
					scale = if typeof(scale) == "number" then scale else 1,
				})
			end
		end
	end
	return clouds
end

function Gas.at(position: Vector3, clouds: { Types.GasCloud }): { [string]: number }
	local readings: { [string]: number } = {}
	for _, cloud in clouds do
		local radius = cloud.radius * cloud.scale
		if radius > 0.1 then
			local distance = (position - cloud.position).Magnitude
			if distance < radius then
				local value = cloud.peak * cloud.scale * (1 - distance / radius)
				readings[cloud.gas] = (readings[cloud.gas] or 0) + value
			end
		end
	end
	return readings
end

return Gas
