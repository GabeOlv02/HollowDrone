--!strict
-- Server side of the remote API. Remotes are created here, once, from the
-- shared list. Every inbound handler goes through a per-player rate limit;
-- handlers receive `unknown` args and must validate them.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)

type RemoteName = Remotes.RemoteName

local folder = Instance.new("Folder")
folder.Name = "Remotes"

local events: { [string]: RemoteEvent } = {}
for _, name in Remotes.Names do
	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = folder
	events[name] = remote
end
folder.Parent = ReplicatedStorage

local lastCall: { [Player]: { [string]: number } } = {}
Players.PlayerRemoving:Connect(function(player)
	lastCall[player] = nil
end)

local Net = {}

function Net.on(name: RemoteName, minInterval: number, handler: (Player, ...unknown) -> ())
	events[name].OnServerEvent:Connect(function(player: Player, ...: unknown)
		local now = os.clock()
		local calls = lastCall[player]
		if not calls then
			calls = {}
			lastCall[player] = calls
		end
		local last = calls[name]
		if last and now - last < minInterval then
			return
		end
		calls[name] = now
		handler(player, ...)
	end)
end

function Net.fireClient(name: RemoteName, player: Player, ...: any)
	events[name]:FireClient(player, ...)
end

function Net.fireAll(name: RemoteName, ...: any)
	events[name]:FireAllClients(...)
end

return Net
