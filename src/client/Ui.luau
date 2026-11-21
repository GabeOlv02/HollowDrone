--!strict
-- Tiny declarative helper for building UI in code, plus the shared HUD theme.

local Ui = {}

Ui.theme = table.freeze({
	panel = Color3.fromRGB(4, 10, 14),
	panelAlpha = 0.35,
	stroke = Color3.fromRGB(0, 230, 255),
	text = Color3.fromRGB(200, 245, 255),
	dim = Color3.fromRGB(100, 150, 165),
	amber = Color3.fromRGB(255, 176, 0),
	cyan = Color3.fromRGB(0, 230, 255),
	magenta = Color3.fromRGB(255, 40, 140),
	good = Color3.fromRGB(90, 255, 150),
	warn = Color3.fromRGB(255, 190, 60),
	bad = Color3.fromRGB(255, 70, 90),
	info = Color3.fromRGB(140, 200, 255),
	font = Enum.Font.RobotoMono,
	fontBold = Enum.Font.GothamBold,
})

-- create("TextLabel", { Text = "hi" }, { child1, child2 })
function Ui.create(className: string, props: { [string]: any }, children: { Instance }?): any
	local instance = (Instance.new :: any)(className)
	for key, value in props do
		if key ~= "Parent" then
			instance[key] = value
		end
	end
	if children then
		for _, child in children do
			child.Parent = instance
		end
	end
	if props.Parent then
		instance.Parent = props.Parent
	end
	return instance
end

function Ui.panel(props: { [string]: any }, children: { Instance }?): Frame
	local theme = Ui.theme
	local merged: { [string]: any } = {
		BackgroundColor3 = theme.panel,
		BackgroundTransparency = theme.panelAlpha,
		BorderSizePixel = 0,
	}
	for key, value in props do
		merged[key] = value
	end
	local frame = Ui.create("Frame", merged, children)
	Ui.create("UICorner", { CornerRadius = UDim.new(0, 2), Parent = frame })
	Ui.create(
		"UIStroke",
		{ Color = theme.stroke, Transparency = 0.6, Thickness = 1, Parent = frame }
	)
	Ui.create("UIPadding", {
		PaddingTop = UDim.new(0, 8),
		PaddingBottom = UDim.new(0, 8),
		PaddingLeft = UDim.new(0, 10),
		PaddingRight = UDim.new(0, 10),
		Parent = frame,
	})
	return frame
end

function Ui.label(props: { [string]: any }): TextLabel
	local theme = Ui.theme
	local merged: { [string]: any } = {
		BackgroundTransparency = 1,
		Font = theme.font,
		TextColor3 = theme.text,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, 18),
		RichText = true,
	}
	for key, value in props do
		merged[key] = value
	end
	return Ui.create("TextLabel", merged)
end

-- Green -> amber -> red as a 0..1 "goodness" falls.
function Ui.healthColor(goodness: number): Color3
	local theme = Ui.theme
	if goodness >= 0.6 then
		return theme.good
	elseif goodness >= 0.35 then
		return theme.warn
	end
	return theme.bad
end

return Ui
