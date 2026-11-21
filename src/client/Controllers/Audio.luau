--!strict
-- Sound, using only audio that ships inside Roblox Studio (rbxasset://), so
-- nothing depends on uploaded assets. Every sound is optional: if a file
-- fails to load it simply stays silent.
--   rotors   a looped airflow bed, pitch and volume follow throttle + speed
--   pings    scan ping, action confirmations, warnings
--   ambience wind on the surface, a low room tone underground

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local DroneState = require(script.Parent.Parent.DroneState)
local Net = require(script.Parent.Parent.Net)

local _Config = require(ReplicatedStorage.Shared.Config)

local Audio = {}

local SOUNDS = {
	Rotor = "rbxasset://sounds/action_falling.mp3",
	Ping = "rbxasset://sounds/electronicpingshort.wav",
	Click = "rbxasset://sounds/button.wav",
	Alert = "rbxasset://sounds/clickfast.wav",
}

local function make(name: string, id: string, volume: number, looped: boolean): Sound
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = id
	sound.Volume = volume
	sound.Looped = looped
	sound.Parent = SoundService
	return sound
end

local rotor: Sound
local ping: Sound
local click: Sound
local alert: Sound

function Audio.init()
	rotor = make("RotorBed", SOUNDS.Rotor, 0, true)
	ping = make("ScanPing", SOUNDS.Ping, 0.35, false)
	click = make("Confirm", SOUNDS.Click, 0.3, false)
	alert = make("Alert", SOUNDS.Alert, 0.3, false)
end

function Audio.start()
	DroneState.Command.connect(function(name: string)
		if name == "Scan" then
			ping:Play()
		elseif name == "CycleCamera" or name == "MenuConfirm" or name == "MenuNav" then
			click:Play()
		end
	end)
	Net.on("Feedback", function(raw: unknown)
		if typeof(raw) == "table" then
			local severity = (raw :: { [string]: unknown }).severity
			if severity == "danger" or severity == "warning" then
				alert:Play()
			else
				click:Play()
			end
		end
	end)
	DroneState.waitForDrone()
	rotor:Play()

	-- Guide beacon: every drone in guide mode beeps from its own hull (3D
	-- sound), so whoever is following can hear where it is
	task.spawn(function()
		while true do
			task.wait(0.85)
			for _, drone in CollectionService:GetTagged("Drone") do
				local guiding = drone:GetAttribute("Guiding")
				local hull = drone:FindFirstChild("Hull")
				if typeof(guiding) == "string" and guiding ~= "" and hull then
					local beep = hull:FindFirstChild("GuideBeep") :: Sound?
					if not beep then
						local sound = Instance.new("Sound")
						sound.Name = "GuideBeep"
						sound.SoundId = SOUNDS.Ping
						sound.Volume = 0.7
						sound.PlaybackSpeed = 1.5
						sound.RollOffMaxDistance = 140
						sound.Parent = hull
						beep = sound
					end
					(beep :: Sound):Play()
				end
			end
		end
	end)
	RunService.RenderStepped:Connect(function(dt: number)
		local active = not DroneState.cinematic
		local throttle = DroneState.throttle
		local targetVolume = if active then 0.12 + throttle * 0.22 else 0
		rotor.Volume += (targetVolume - rotor.Volume) * math.min(1, dt * 3)
		rotor.PlaybackSpeed = 1.5 + throttle * 0.7 + math.min(DroneState.speed, 40) / 80
	end)
end

return Audio
