--!strict
-- Single list of every remote. The server creates them; the client only waits.

export type RemoteName = "DroneAction" | "SetLoadout" | "Recall" | "Feedback" | "SelectSite"

local NAMES: { RemoteName } = { "DroneAction", "SetLoadout", "Recall", "Feedback", "SelectSite" }

return table.freeze({ Names = NAMES })
