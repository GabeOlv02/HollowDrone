--!strict
-- Which site (Hollow showcase / test range) a point or instance belongs to.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local Sites = {}

function Sites.at(position: Vector3): string
	for name, spec in Config.SITES do
		local min, max = spec.min, spec.max
		if
			position.X >= min.X
			and position.X <= max.X
			and position.Y >= min.Y
			and position.Y <= max.Y
			and position.Z >= min.Z
			and position.Z <= max.Z
		then
			return name
		end
	end
	return Config.DEFAULT_SITE
end

-- Walks up to the site folder (a Folder with a "Site" attribute).
function Sites.of(instance: Instance): string?
	local current: Instance? = instance
	while current do
		local site = current:GetAttribute("Site")
		if typeof(site) == "string" then
			return site
		end
		current = current.Parent
	end
	return nil
end

-- The groups of objectives that belong to a site, in display order.
function Sites.groups(site: string): { any }
	local out = {}
	for _, group in Config.OBJECTIVES do
		if group.site == site then
			table.insert(out, group)
		end
	end
	return out
end

return Sites
