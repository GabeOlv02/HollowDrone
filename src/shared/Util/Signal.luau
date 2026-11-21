--!strict
-- Minimal signal for cross-module events (no BindableEvent serialization cost).

export type Signal = {
	connect: (handler: (...any) -> ()) -> () -> (),
	fire: (...any) -> (),
}

local Signal = {}

function Signal.new(): Signal
	local handlers: { (...any) -> () } = {}

	local function connect(handler: (...any) -> ()): () -> ()
		table.insert(handlers, handler)
		return function()
			local index = table.find(handlers, handler)
			if index then
				table.remove(handlers, index)
			end
		end
	end

	local function fire(...: any)
		for _, handler in table.clone(handlers) do
			task.spawn(handler, ...)
		end
	end

	return { connect = connect, fire = fire }
end

return Signal
