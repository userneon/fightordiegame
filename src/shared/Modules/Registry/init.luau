--!strict
--[[
	Registry
	--------
	Tiny service/controller locator. The bootstrap registers every module it
	loads by its Name; other modules fetch each other through here instead of
	`require`ing siblings directly.

	Why: with 20+ services, direct sibling requires create import cycles the
	moment two services need each other. Registry lookups happen at CALL time,
	not load time, so cycles are impossible.

		local Registry = require(Shared.Modules.Registry)
		-- inside a function, never at module scope:
		local damage = Registry.expect("DamageService")

	Deliberately dumb: no lifecycle, no ordering. The bootstrap owns those.
]]

local Registry = {}

local items: { [string]: any } = {}

function Registry.register(name: string, value: any)
	items[name] = value
end

-- Returns nil when absent — use when a dependency is genuinely optional.
function Registry.get(name: string): any
	return items[name]
end

-- Use when the caller cannot work without it; fails loudly instead of silently
-- doing nothing (a silent nil in gameplay code is far harder to diagnose).
function Registry.expect(name: string): any
	local value = items[name]
	if value == nil then
		error(string.format("Registry: '%s' is not registered", name), 2)
	end
	return value
end

function Registry.all(): { [string]: any }
	return items
end

return Registry
