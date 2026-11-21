--!strict
-- Guide mode: in a blackout people can't see, but they can follow a sound.
-- A pilot targets a lost resident and turns on the drone's guide beacon (a
-- beep and a pulsing green light). The person then walks after the drone:
-- the server pathfinds over the real geometry (decks, ramps, stairs) toward
-- the floor under the drone, keeps a few metres back, stops if the beeping
-- gets too far away, and is reunited when they reach their family.
--
-- People are R15 humanoids: the server walks them with Humanoid:MoveTo from
-- waypoint to waypoint, and Characters plays the default walk animation
-- from their speed.

local CollectionService = game:GetService("CollectionService")
local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)

local Characters = require(script.Parent.Parent.Characters)
local Feedback = require(script.Parent.Parent.Feedback)
local Mission = require(script.Parent.Parent.Mission)
local DroneService = require(script.Parent.DroneService)

local DRONE = Config.DRONE

type Walker = {
	model: Model,
	humanoid: Humanoid,
	guide: Player?,
	waypoints: { Vector3 },
	index: number,
	lastGoal: Vector3?,
	lastPathAt: number,
	lostSince: number?,
	thread: thread?,
}

local Guides = {}

local walkers: { [Model]: Walker } = {}

local function walkerFor(model: Model): Walker
	local existing = walkers[model]
	if existing then
		return existing
	end
	local walker: Walker = {
		model = model,
		humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid,
		guide = nil,
		waypoints = {},
		index = 1,
		lastGoal = nil,
		lastPathAt = 0,
		lostSince = nil,
		thread = nil,
	}
	walkers[model] = walker
	return walker
end

local function feetOf(walker: Walker): Vector3
	return Characters.feet(walker.model)
end

-- Stop walking where they stand
local function halt(walker: Walker)
	local root = walker.model.PrimaryPart
	if root then
		walker.humanoid:MoveTo(root.Position)
	end
end

-- Turn in place toward a point (only while standing still)
local function face(walker: Walker, point: Vector3)
	local root = walker.model.PrimaryPart
	if not root then
		return
	end
	local flat = Vector3.new(point.X - root.Position.X, 0, point.Z - root.Position.Z)
	if flat.Magnitude > 0.5 then
		root.CFrame = CFrame.lookAt(root.Position, root.Position + flat.Unit)
	end
end

local downParams = RaycastParams.new()
downParams.FilterType = Enum.RaycastFilterType.Exclude
downParams.RespectCanCollide = true

-- The walkable floor under the drone (where the person should head).
local function floorUnder(position: Vector3, walker: Walker): Vector3?
	local exclude: { Instance } = { walker.model }
	local drones = Workspace:FindFirstChild("Drones")
	if drones then
		table.insert(exclude, drones)
	end
	downParams.FilterDescendantsInstances = exclude
	local hit = Workspace:Raycast(position, Vector3.new(0, -60, 0), downParams)
	return if hit then hit.Position else nil
end

local function family(walker: Walker): Model?
	local name = walker.model:GetAttribute("ReuniteWith")
	if typeof(name) ~= "string" then
		return nil
	end
	for _, model in CollectionService:GetTagged("Walker") do
		if model:IsA("Model") and model:GetAttribute("Family") == name then
			return model
		end
	end
	return nil
end

local function stop(walker: Walker, status: string)
	local player = walker.guide
	walker.guide = nil
	walker.waypoints = {}
	walker.model:SetAttribute("FollowerOf", 0)
	walker.model:SetAttribute("Status", status)
	halt(walker)
	if player then
		local drone = DroneService.get(player)
		if drone then
			drone:SetAttribute("Guiding", "")
		end
	end
end

local function reunite(walker: Walker, relative: Model)
	local player = walker.guide
	local name = tostring(walker.model:GetAttribute("Label") or "Resident")
	stop(walker, "REUNITED WITH FAMILY")
	face(walker, relative:GetPivot().Position)
	walker.model:SetAttribute("Lost", false)
	relative:SetAttribute("Status", "REUNITED")
	local objective = walker.model:GetAttribute("Objective")
	if typeof(objective) == "string" then
		Mission.add(objective, 1)
	end
	Feedback.all(
		"FAMILY REUNITED",
		("%s followed %s's drone %s and found %s at %s."):format(
			name,
			if player then player.DisplayName else "a",
			tostring(walker.model:GetAttribute("Route") or "through the blackout"),
			tostring(relative:GetAttribute("Label") or "their family"),
			tostring(relative:GetAttribute("Place") or "the meeting point")
		),
		"success"
	)
end

-- Path queries are flaky when the start or goal lies exactly on a sloped
-- surface (ramps, stairs), so try a couple of lifts before giving up.
local LIFTS = { 1.5, 0.5, 3 }

local function computePath(walker: Walker, goal: Vector3): boolean
	local feet = feetOf(walker)
	for _, lift in LIFTS do
		local path = PathfindingService:CreatePath({
			AgentRadius = 1.4,
			AgentHeight = 5.5,
			AgentCanJump = false,
			WaypointSpacing = 4,
		})
		local up = Vector3.new(0, lift, 0)
		local ok = pcall(function()
			path:ComputeAsync(feet + up, goal + up)
		end)
		if ok and path.Status == Enum.PathStatus.Success then
			walker.waypoints = {}
			for _, waypoint in path:GetWaypoints() do
				table.insert(walker.waypoints, waypoint.Position)
			end
			walker.index = 2
			return true
		end
	end
	-- Close (a straight ramp or open floor): just walk straight at it
	local delta = goal - feet
	if Vector3.new(delta.X, 0, delta.Z).Magnitude < 30 and math.abs(delta.Y) < 12 then
		walker.waypoints = { feet, goal }
		walker.index = 2
		return true
	end
	return false
end

-- One walker's behaviour loop while it is being guided.
local function follow(walker: Walker)
	local unreachableSince: number? = nil
	local lastProgress = os.clock()
	local lastFeet = feetOf(walker)
	while walker.guide do
		task.wait(0.1)
		local player = walker.guide :: Player
		local hull = DroneService.hull(player)
		local drone = DroneService.get(player)
		if
			not hull
			or not drone
			or drone:GetAttribute("Guiding") ~= walker.model:GetAttribute("Label")
		then
			stop(walker, "STOPPED · NO BEACON")
			break
		end

		local feet = feetOf(walker)
		local toDrone = hull.Position - feet
		if toDrone.Magnitude > DRONE.GUIDE_RANGE then
			-- Out of earshot: wait where they are
			if not walker.lostSince then
				walker.lostSince = os.clock()
				halt(walker)
				walker.waypoints = {}
				walker.model:SetAttribute("Status", "WAITING · CAN'T HEAR THE DRONE")
				Feedback.send(
					player,
					"GUIDE",
					"Lost contact: they can't hear the beacon. Come back closer.",
					"warning"
				)
			end
		else
			if walker.lostSince then
				walker.lostSince = nil
				walker.lastGoal = nil
				walker.model:SetAttribute("Status", "FOLLOWING THE BEEPING")
			end
			local goal = floorUnder(hull.Position, walker)
			local flat = Vector3.new(toDrone.X, 0, toDrone.Z)
			local now = os.clock()
			if goal and (flat.Magnitude > 6 or math.abs(toDrone.Y) > 9) then
				-- Stuck against something for 2 s: plan again from here
				if (feet - lastFeet).Magnitude > 0.5 then
					lastFeet = feet
					lastProgress = now
				end
				local stuck = #walker.waypoints > 0 and now - lastProgress > 2
				local moved = walker.lastGoal == nil
					or (goal - (walker.lastGoal :: Vector3)).Magnitude > 4
				if
					(moved or stuck or walker.index > #walker.waypoints)
					and now - walker.lastPathAt > 0.8
				then
					walker.lastPathAt = now
					walker.lastGoal = goal
					lastProgress = now
					if computePath(walker, goal) then
						unreachableSince = nil
						walker.model:SetAttribute("Status", "FOLLOWING THE BEEPING")
					elseif not unreachableSince then
						unreachableSince = now
					elseif now - (unreachableSince :: number) > 3 then
						unreachableSince = math.huge
						Feedback.send(
							player,
							"GUIDE",
							"No walkable route to where you're hovering. Hover over a floor they can reach.",
							"warning"
						)
					end
				end
				-- Walk the path, stopping a few metres short of the drone
				local nearGoal = (Vector3.new(goal.X, 0, goal.Z) - Vector3.new(feet.X, 0, feet.Z)).Magnitude
					< 4.5
				if nearGoal then
					walker.waypoints = {}
					halt(walker)
				else
					-- Skip waypoints already reached
					while walker.index <= #walker.waypoints do
						local target = walker.waypoints[walker.index]
						local delta = target - feet
						if
							Vector3.new(delta.X, 0, delta.Z).Magnitude < 1.6
							and math.abs(delta.Y) < 3
						then
							walker.index += 1
						else
							break
						end
					end
					local target = walker.waypoints[walker.index]
					if target then
						walker.humanoid:MoveTo(target)
					else
						halt(walker)
					end
				end
			else
				halt(walker)
				walker.waypoints = {}
				if walker.humanoid.MoveDirection.Magnitude < 0.1 then
					face(walker, hull.Position)
				end
			end
		end

		local relative = family(walker)
		if
			relative
			and (relative:GetPivot().Position - walker.model:GetPivot().Position).Magnitude
				<= DRONE.REUNITE_RANGE
		then
			reunite(walker, relative)
			break
		end
	end
	walker.thread = nil
end

-- Called from Actions when a pilot targets a resident with Primary.
function Guides.toggle(player: Player, model: Instance)
	if not model:IsA("Model") or not CollectionService:HasTag(model, "Walker") then
		return
	end
	local walker = walkerFor(model)
	local drone = DroneService.get(player)
	if not drone then
		return
	end
	local name = tostring(model:GetAttribute("Label") or "Resident")
	if walker.guide == player then
		stop(walker, "WAITING")
		Feedback.send(player, "GUIDE", "Beacon off. " .. name .. " will wait here.", "info")
		return
	end
	if model:GetAttribute("Lost") ~= true then
		Feedback.send(player, "GUIDE", name .. " isn't lost: they know where they are.", "info")
		return
	end
	if walker.guide then
		Feedback.send(player, "GUIDE", name .. " is already following another drone.", "info")
		return
	end
	-- One person per drone
	for _, other in walkers do
		if other.guide == player then
			stop(other, "WAITING")
		end
	end
	walker.guide = player
	walker.waypoints = {}
	walker.lastGoal = nil
	walker.lostSince = nil
	model:SetAttribute("FollowerOf", player.UserId)
	model:SetAttribute("Status", "FOLLOWING THE BEEPING")
	drone:SetAttribute("Guiding", name)
	local relative = family(walker)
	Feedback.send(
		player,
		"GUIDE BEACON ON",
		("Beeping + green guide light. %s is following.\nFly slowly: they walk at ~2 m/s and stop if you get more than %d m away.%s"):format(
			name,
			math.floor(DRONE.GUIDE_RANGE * Config.STUDS_TO_METERS),
			if relative and relative:GetAttribute("Place")
				then " Their family is at " .. tostring(relative:GetAttribute("Place")) .. "."
				else ""
		),
		"success"
	)
	walker.thread = task.spawn(follow, walker)
end

function Guides.init()
	Players.PlayerRemoving:Connect(function(player)
		for _, walker in walkers do
			if walker.guide == player then
				stop(walker, "WAITING")
			end
		end
	end)
end

return Guides
