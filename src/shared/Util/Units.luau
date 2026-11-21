--!strict
-- Temperature formatting: the feed shows imperial first with metric beside it
-- ("101.3°F (38.5°C)") so judges and medics can both read it at a glance.

local Units = {}

function Units.fahrenheit(celsius: number): number
	return celsius * 9 / 5 + 32
end

-- "101.3°F (38.5°C)"
function Units.temp(celsius: number): string
	return ("%.1f°F (%.1f°C)"):format(Units.fahrenheit(celsius), celsius)
end

-- Whole degrees, for ambient air: "84°F (29°C)"
function Units.tempWhole(celsius: number): string
	return ("%d°F (%d°C)"):format(math.round(Units.fahrenheit(celsius)), math.round(celsius))
end

-- Compact form for small thermal tags: "101.3°F"
function Units.tempShort(celsius: number): string
	return ("%.1f°F"):format(Units.fahrenheit(celsius))
end

return table.freeze(Units)
