--!strict
--[[
	HoldTracker
	-----------
	Reusable "hold to do something" progress tracker, used by every system that
	needs it: medical treatment (hold E 5s), world interactions (doors, loot),
	and mission objectives (hold 5 minutes).

	It exists so the interrupt rules are written ONCE and behave identically
	everywhere:
	  - progress accrues only while the hold is active
	  - moving further than `moveTolerance` from the start position resets it
	  - an explicit cancel resets it
	  - a validator callback is re-checked every tick, so a hold dies the moment
	    its preconditions do (target died, player downed, too far away)

	Pure logic: no Remotes, no Instances of its own. The owning service ticks it
	and decides what completion means.

		local hold = HoldTracker.new()
		hold:begin(key, { duration = 5, position = pos, validate = fn,
		                  onComplete = fn, onProgress = fn, onCancel = fn })
		hold:update(dt)      -- from the service's own loop
		hold:cancel(key)
]]

local HoldTracker = {}
HoldTracker.__index = HoldTracker

export type Options = {
	duration: number,
	position: Vector3?,
	moveTolerance: number?,
	-- Return the CURRENT position each tick (nil = do not movement-check).
	getPosition: (() -> Vector3?)?,
	-- Return false to cancel the hold this tick.
	validate: (() -> boolean)?,
	onProgress: ((progress: number) -> ())?,
	onComplete: (() -> ())?,
	onCancel: ((reason: string) -> ())?,
}

type Entry = {
	elapsed: number,
	options: Options,
	startPosition: Vector3?,
}

function HoldTracker.new()
	return setmetatable({ _entries = {} :: { [any]: Entry } }, HoldTracker)
end

function HoldTracker:isActive(key: any): boolean
	return self._entries[key] ~= nil
end

function HoldTracker:progress(key: any): number
	local entry = self._entries[key]
	if not entry then
		return 0
	end
	return math.clamp(entry.elapsed / math.max(0.01, entry.options.duration), 0, 1)
end

function HoldTracker:begin(key: any, options: Options)
	-- Starting a new hold always replaces any previous one for this key.
	self:cancel(key, "restarted")
	self._entries[key] = {
		elapsed = 0,
		options = options,
		startPosition = options.position or (options.getPosition and options.getPosition() or nil),
	}
end

function HoldTracker:cancel(key: any, reason: string?)
	local entry = self._entries[key]
	if not entry then
		return
	end
	self._entries[key] = nil
	if entry.options.onCancel then
		entry.options.onCancel(reason or "cancelled")
	end
end

-- Advance every active hold. Call from one loop in the owning service.
function HoldTracker:update(dt: number)
	for key, entry in self._entries do
		local options = entry.options

		-- Preconditions re-checked every tick, never just at the start.
		if options.validate and not options.validate() then
			self:cancel(key, "invalid")
			continue
		end

		-- Movement resets progress entirely (not merely pauses it).
		if entry.startPosition and options.getPosition then
			local current = options.getPosition()
			local tolerance = options.moveTolerance or 3
			if not current or (current - entry.startPosition).Magnitude > tolerance then
				self:cancel(key, "moved")
				continue
			end
		end

		entry.elapsed += dt
		local progress = math.clamp(entry.elapsed / math.max(0.01, options.duration), 0, 1)
		if options.onProgress then
			options.onProgress(progress)
		end

		if entry.elapsed >= options.duration then
			self._entries[key] = nil
			if options.onComplete then
				options.onComplete()
			end
		end
	end
end

function HoldTracker:clear()
	for key in self._entries do
		self:cancel(key, "cleared")
	end
end

return HoldTracker
