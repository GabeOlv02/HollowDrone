--!strict
-- Shared operation progress. Counters live as attributes on
-- ReplicatedStorage.Mission so every pilot's ops log updates live.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Feedback = require(script.Parent.Feedback)

local folder = Instance.new("Folder")
folder.Name = "Mission"
for _, group in Config.OBJECTIVES do
	for _, item in group.items do
		folder:SetAttribute(item.key, 0)
	end
end
folder.Parent = ReplicatedStorage

local completed: { [string]: boolean } = {}

local Mission = {}

function Mission.get(key: string): number
	local value = folder:GetAttribute(key)
	return if typeof(value) == "number" then value else 0
end

local function checkZones()
	for _, group in Config.OBJECTIVES do
		if not completed[group.zone] then
			local done = true
			for _, item in group.items do
				if Mission.get(item.key) < item.total then
					done = false
					break
				end
			end
			if done then
				completed[group.zone] = true
				Feedback.all("OPERATION COMPLETE", group.zone, "success")
			end
		end
	end
end

function Mission.set(key: string, value: number)
	if folder:GetAttribute(key) == nil then
		warn(("[Mission] unknown objective %s"):format(key))
		return
	end
	if Mission.get(key) ~= value then
		folder:SetAttribute(key, value)
		checkZones()
	end
end

function Mission.add(key: string, delta: number)
	Mission.set(key, Mission.get(key) + delta)
end

return Mission
