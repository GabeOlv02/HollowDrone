--!strict
-- Hollow Drone client entry point.

local StarterGui = game:GetService("StarterGui")

-- A drone feed, not a game: hide Roblox's player list, backpack, health and
-- emote menus (the player list would also swallow the Tab key)
for _, coreGui in
	{
		Enum.CoreGuiType.PlayerList,
		Enum.CoreGuiType.Backpack,
		Enum.CoreGuiType.Health,
		Enum.CoreGuiType.EmotesMenu,
	}
do
	pcall(function()
		StarterGui:SetCoreGuiEnabled(coreGui, false)
	end)
end

local Controllers = script:FindFirstChild("Controllers")

local loaded: { [string]: any } = {}
if Controllers then
	for _, child in Controllers:GetChildren() do
		if child:IsA("ModuleScript") then
			loaded[child.Name] = require(child) :: any
		end
	end
end

for _, controller in loaded do
	if typeof(controller.init) == "function" then
		controller.init()
	end
end

for _, controller in loaded do
	if typeof(controller.start) == "function" then
		task.spawn(controller.start)
	end
end

print("[HollowDrone] client started")
