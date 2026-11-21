--!strict
-- People in the world are real R15 Roblox characters (Humanoid rigs built from
-- a HumanoidDescription) playing Roblox's default animations: idle, walk and
-- sit. They replace the earlier block figures.
--
-- Builders run before their site folder is parented to Workspace, so spawn()
-- only creates the rig; settle() (called once every site is built) snaps each
-- standing person's feet onto the real floor with a raycast, starts their
-- animations and hands walkers to server physics.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local Characters = {}

-- Roblox's default R15 animation set (the same ids the stock Animate script uses)
local ANIM = {
	idle = "rbxassetid://507766388",
	walk = "rbxassetid://507777826",
	sit = "rbxassetid://2506281703",
}

-- Free Roblox-made hair; any that fails to load just gives a bald variant
local HAIR = { "63690008", "451220849", "376548738", "62724852" }

local SKIN = {
	Color3.fromRGB(234, 192, 160),
	Color3.fromRGB(198, 150, 118),
	Color3.fromRGB(160, 112, 80),
	Color3.fromRGB(120, 82, 58),
	Color3.fromRGB(86, 58, 42),
}
local PANTS = {
	Color3.fromRGB(46, 48, 54),
	Color3.fromRGB(58, 66, 84),
	Color3.fromRGB(72, 64, 52),
	Color3.fromRGB(38, 40, 36),
}
local SHOES = Color3.fromRGB(30, 28, 26)

export type Spec = {
	-- "Stand" | "Sit" | "Lie"
	pose: string,
	-- Stand: hip centre, facing (feet are snapped to the floor below it)
	-- Sit:   hip centre on the seat, facing
	-- Lie:   hip centre on the mattress; head toward the cframe's +Z (pillow)
	cf: CFrame,
	shirt: Color3,
	pants: Color3?,
	skin: Color3?,
	-- Walkers stay unanchored and are driven by Humanoid:MoveTo (Guides)
	mobile: boolean?,
}

type Entry = { model: Model, spec: Spec, settled: boolean }

local rng = Random.new(87)
local templates: { Model } = {}
local entries: { Entry } = {}

-- Hip centre to the bottom of the HumanoidRootPart's centre, for poses that
-- aren't snapped (seated / lying); tuned against the default R15 rig.
local SIT_LIFT = 1.15
local LIE_LIFT = 0.15

local function makeTemplate(hair: string?): Model?
	local description = Instance.new("HumanoidDescription")
	if hair then
		description.HairAccessory = hair
	end
	local ok, result = pcall(function()
		return Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
	end)
	description:Destroy()
	if not ok or not result then
		return nil
	end
	return result :: Model
end

local function ensureTemplates()
	if #templates > 0 then
		return
	end
	for _, hair in HAIR do
		local model = makeTemplate(hair)
		if model then
			table.insert(templates, model)
		end
	end
	if #templates == 0 then
		local bald = makeTemplate(nil)
		assert(bald, "could not build an R15 character template")
		table.insert(templates, bald)
	end
end

local SHIRT_PARTS = {
	UpperTorso = true,
	LeftUpperArm = true,
	RightUpperArm = true,
	LeftLowerArm = true,
	RightLowerArm = true,
}
local PANTS_PARTS = {
	LowerTorso = true,
	LeftUpperLeg = true,
	RightUpperLeg = true,
	LeftLowerLeg = true,
	RightLowerLeg = true,
}
local SHOE_PARTS = { LeftFoot = true, RightFoot = true }

local function paint(model: Model, spec: Spec)
	local skin = spec.skin or SKIN[rng:NextInteger(1, #SKIN)]
	local pants = spec.pants or PANTS[rng:NextInteger(1, #PANTS)]
	for _, part in model:GetDescendants() do
		if not part:IsA("BasePart") or part.Name == "HumanoidRootPart" then
			continue
		end
		if part.Parent ~= model then
			continue -- accessories keep their own texture
		end
		if SHIRT_PARTS[part.Name] then
			part.Color = spec.shirt
		elseif PANTS_PARTS[part.Name] then
			part.Color = pants
		elseif SHOE_PARTS[part.Name] then
			part.Color = SHOES
		else
			part.Color = skin -- head, hands
		end
	end
	local bodyColors = model:FindFirstChildOfClass("BodyColors")
	if bodyColors then
		bodyColors:Destroy()
	end
end

local function rootHeight(humanoid: Humanoid, root: BasePart): number
	return humanoid.HipHeight + root.Size.Y / 2
end

-- Creates a person. The model's PrimaryPart is its HumanoidRootPart, so
-- Devices.position / thermal / scanner treat it like any other device model.
function Characters.spawn(parent: Instance, name: string, spec: Spec): Model
	ensureTemplates()
	local model = templates[rng:NextInteger(1, #templates)]:Clone()
	model.Name = name
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart
	model.PrimaryPart = root

	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.NameDisplayDistance = 0
	humanoid.BreakJointsOnDeath = false
	humanoid.RequiresNeck = false
	humanoid.WalkSpeed = Config.DRONE.GUIDE_SPEED
	for _, state in
		{
			Enum.HumanoidStateType.Dead,
			Enum.HumanoidStateType.Ragdoll,
			Enum.HumanoidStateType.FallingDown,
			Enum.HumanoidStateType.Climbing,
			Enum.HumanoidStateType.Jumping,
		}
	do
		humanoid:SetStateEnabled(state, false)
	end
	paint(model, spec)

	-- Static people are anchored statues that animate; only walkers simulate.
	-- Limbs don't collide (the drone shouldn't snag on fingers); the root box
	-- stands in for the body.
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.CastShadow = true
			if part ~= root then
				part.CanCollide = false
				part.Massless = true
			end
		end
	end
	root.Anchored = true
	root.CanCollide = spec.mobile == true

	local cf = spec.cf
	if spec.pose == "Lie" then
		-- On the back, head toward the caller's +Z (the pillow), face up
		model:PivotTo(
			cf
				* CFrame.new(0, LIE_LIFT + root.Size.Z / 2 - 0.4, 0)
				* CFrame.Angles(math.pi / 2, 0, 0)
		)
	elseif spec.pose == "Sit" then
		model:PivotTo(cf * CFrame.new(0, SIT_LIFT, 0))
	else
		-- Provisional: hips 1.95 above the feet (the old figure convention)
		local feet = cf.Position - Vector3.new(0, 1.95, 0)
		local look = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
		if look.Magnitude < 0.01 then
			look = Vector3.new(0, 0, -1)
		end
		local center = feet + Vector3.new(0, rootHeight(humanoid, root), 0)
		model:PivotTo(CFrame.lookAt(center, center + look.Unit))
	end

	CollectionService:AddTag(model, "NPC")
	model:SetAttribute("Pose", spec.pose)
	model.Parent = parent
	table.insert(entries, { model = model, spec = spec, settled = false })
	return model
end

-- A body temperature (°C) inside the band for a condition, one decimal
function Characters.temperature(condition: string): number
	local band = (Config.VITALS :: any)[condition] or Config.VITALS.Healthy
	return math.round(rng:NextNumber(band[1], band[2]) * 10) / 10
end

-- The part thermal should outline and tag (the chest)
function Characters.chest(model: Model): BasePart
	return (model:FindFirstChild("UpperTorso") or model.PrimaryPart) :: BasePart
end

local floorParams = RaycastParams.new()
floorParams.FilterType = Enum.RaycastFilterType.Exclude
floorParams.RespectCanCollide = true

local function load(
	animator: Animator,
	id: string,
	priority: Enum.AnimationPriority
): AnimationTrack
	local animation = Instance.new("Animation")
	animation.AnimationId = id
	local track = animator:LoadAnimation(animation)
	track.Priority = priority
	track.Looped = true
	return track
end

local function animate(model: Model, spec: Spec)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local existing = humanoid:FindFirstChildOfClass("Animator")
	local animator: Animator
	if existing then
		animator = existing
	else
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	local ok = pcall(function()
		local a = animator
		if spec.pose == "Sit" then
			load(a, ANIM.sit, Enum.AnimationPriority.Core):Play(0)
			return
		end
		local idle = load(a, ANIM.idle, Enum.AnimationPriority.Idle)
		-- Desynchronise the crowd so nobody breathes in unison
		idle:Play(0, 1, if spec.pose == "Lie" then 0.55 else rng:NextNumber(0.85, 1.1))
		idle.TimePosition = rng:NextNumber(0, 2)
		if spec.mobile then
			local walk = load(a, ANIM.walk, Enum.AnimationPriority.Movement)
			humanoid.Running:Connect(function(speed: number)
				if speed > 0.6 then
					if not walk.IsPlaying then
						walk:Play(0.2)
					end
					walk:AdjustSpeed(math.clamp(speed / 10, 0.5, 1.4))
				elseif walk.IsPlaying then
					walk:Stop(0.25)
				end
			end)
		end
	end)
	if not ok then
		warn("[Characters] could not start animations for " .. model:GetFullName())
	end
end

-- Call once every site is parented to Workspace.
function Characters.settle()
	local exclude: { Instance } = {}
	for _, entry in entries do
		table.insert(exclude, entry.model)
	end
	local drones = Workspace:FindFirstChild("Drones")
	if drones then
		table.insert(exclude, drones)
	end
	floorParams.FilterDescendantsInstances = exclude

	for _, entry in entries do
		if entry.settled or not entry.model:IsDescendantOf(Workspace) then
			continue
		end
		entry.settled = true
		local model = entry.model
		local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
		local root = model.PrimaryPart :: BasePart
		if entry.spec.pose == "Stand" then
			local pivot = model:GetPivot()
			local guess = pivot.Position - Vector3.new(0, rootHeight(humanoid, root), 0)
			local hit = Workspace:Raycast(
				guess + Vector3.new(0, 2.5, 0),
				Vector3.new(0, -6, 0),
				floorParams
			)
			if hit then
				local center = hit.Position + Vector3.new(0, rootHeight(humanoid, root), 0)
				model:PivotTo(pivot.Rotation + center)
			end
		end
		animate(model, entry.spec)
		if entry.spec.mobile then
			root.Anchored = false
			pcall(function()
				root:SetNetworkOwner(nil)
			end)
		end
	end
end

-- Feet position of a standing person (for pathfinding)
function Characters.feet(model: Model): Vector3
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model.PrimaryPart
	if not humanoid or not root then
		return model:GetPivot().Position
	end
	return root.Position - Vector3.new(0, rootHeight(humanoid, root), 0)
end

return Characters
