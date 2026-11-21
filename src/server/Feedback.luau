--!strict
-- Sends result cards (readings, confirmations, warnings) to pilots.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Net = require(script.Parent.Net)

local Feedback = {}

function Feedback.send(player: Player, title: string, text: string, severity: Types.Severity)
	local payload: Types.Feedback = { title = title, text = text, severity = severity }
	Net.fireClient("Feedback", player, payload)
end

function Feedback.all(title: string, text: string, severity: Types.Severity)
	local payload: Types.Feedback = { title = title, text = text, severity = severity }
	Net.fireAll("Feedback", payload)
end

return Feedback
