--!strict
--[[
	Logger
	------
	Tiny prefixed logging helper so every system logs consistently, e.g.:
		local log = require(...Modules.Logger).scope("MedicSystem")
		log.info("started")   --> [FOD][MedicSystem] started
]]

local PREFIX = "[FOD]"

local Logger = {}

export type ScopedLogger = {
	info: (...any) -> (),
	warn: (...any) -> (),
	error: (...any) -> (),
}

function Logger.scope(name: string): ScopedLogger
	local tag = string.format("%s[%s]", PREFIX, name)
	return {
		info = function(...)
			print(tag, ...)
		end,
		warn = function(...)
			warn(tag, ...)
		end,
		error = function(...)
			-- Non-fatal: log loudly but let the caller decide whether to raise.
			warn(tag, "ERROR:", ...)
		end,
	}
end

return Logger
