--!strict
--[[
	DataService (server-authoritative persistence)
	----------------------------------------------
	Player profiles on top of Roblox DataStores. No external database.

	  - One profile per player, loaded on join, autosaved, saved on leave and
	    on BindToClose (so a server shutdown never eats progress).
	  - Retries with exponential backoff; a failed load NEVER silently hands
	    back a blank profile that would then overwrite good data — the profile
	    is flagged `locked` and saving is skipped.
	  - In Studio a volatile in-memory store is used by default
	    (Config.Data.UseMockInStudio) so testing cannot corrupt live data.

	Other services treat the profile as the source of truth for XP/rank/stats
	and mutate it directly through :get(player); DataService owns writing it.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Logger = require(Shared.Modules.Logger)
local Remotes = require(Shared.Remotes)
local Data = require(Shared.Data)

local DataService = {}
DataService.Name = "DataService"

local log = Logger.scope(DataService.Name)

type Profile = {
	version: number,
	userId: number,
	xp: number,
	rankTier: number,
	faction: string,
	role: string,
	stats: { [string]: number },
	unlocks: { [string]: boolean },
	settings: { [string]: any },
	locked: boolean, -- true = load failed; do not save over the real record
}

local function defaultProfile(userId: number): Profile
	return {
		version = Config.Data.ProfileVersion,
		userId = userId,
		xp = 0,
		rankTier = 1,
		faction = "Neutral",
		role = Data.Roles.Default,
		stats = {
			kills = 0,
			deaths = 0,
			revives = 0,
			missions = 0,
			shotsFired = 0,
			timePlayed = 0,
		},
		unlocks = {},
		settings = {},
		locked = false,
	}
end

function DataService:Init()
	self._config = Config.Data
	self._profiles = {} :: { [Player]: Profile }
	self._mock = {} :: { [number]: any } -- Studio / fallback store
	self._useMock = RunService:IsStudio() and self._config.UseMockInStudio

	if not self._useMock then
		local ok, store = pcall(function()
			return DataStoreService:GetDataStore(self._config.StoreName)
		end)
		self._store = ok and store or nil
		if not self._store then
			log.warn("DataStore unavailable — falling back to in-memory profiles")
			self._useMock = true
		end
	end
end

-- --- low level --------------------------------------------------------------

function DataService:_key(userId: number): string
	return string.format("player_%d", userId)
end

-- Retry wrapper: DataStore calls are network calls and DO fail transiently.
function DataService:_retry<T>(label: string, fn: () -> T): (boolean, T?)
	local delayFor = self._config.RetryBackoff
	for attempt = 1, self._config.MaxRetries do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		log.warn(string.format("%s failed (attempt %d): %s", label, attempt, tostring(result)))
		if attempt < self._config.MaxRetries then
			task.wait(delayFor)
			delayFor *= 2
		end
	end
	return false, nil
end

-- Migrate older saved shapes forward so a schema change never wipes players.
function DataService:_migrate(raw: any, userId: number): Profile
	local profile = defaultProfile(userId)
	if type(raw) ~= "table" then
		return profile
	end
	for key, value in profile do
		if raw[key] ~= nil and type(raw[key]) == type(value) then
			profile[key] = raw[key]
		end
	end
	profile.version = Config.Data.ProfileVersion
	profile.userId = userId
	profile.locked = false
	return profile
end

-- --- load / save ------------------------------------------------------------

function DataService:_load(player: Player)
	local userId = player.UserId
	local key = self:_key(userId)
	local profile: Profile

	if self._useMock then
		profile = self:_migrate(self._mock[userId], userId)
	else
		local ok, raw = self:_retry("load " .. key, function()
			return self._store:GetAsync(key)
		end)
		if ok then
			profile = self:_migrate(raw, userId)
		else
			-- Could not read: give them a working session profile but REFUSE to
			-- save it, so a transient outage can't erase real progress.
			profile = defaultProfile(userId)
			profile.locked = true
			log.error(string.format("profile load failed for %s — session is read-only", player.Name))
		end
	end

	self._profiles[player] = profile

	if self._loaded then
		self._loaded:FireClient(player, {
			xp = profile.xp,
			rankTier = profile.rankTier,
			stats = profile.stats,
			settings = profile.settings,
		})
	end
	return profile
end

function DataService:save(player: Player): boolean
	local profile = self._profiles[player]
	if not profile then
		return false
	end
	if profile.locked then
		return false -- never overwrite a record we failed to read
	end

	if self._useMock then
		self._mock[profile.userId] = profile
		return true
	end

	local key = self:_key(profile.userId)
	local ok = self:_retry("save " .. key, function()
		return self._store:SetAsync(key, profile)
	end)
	return ok
end

-- --- public API -------------------------------------------------------------

function DataService:get(player: Player): Profile?
	return self._profiles[player]
end

function DataService:incrementStat(player: Player, stat: string, amount: number?)
	local profile = self._profiles[player]
	if not profile then
		return
	end
	profile.stats[stat] = (profile.stats[stat] or 0) + (amount or 1)
end

function DataService:setSetting(player: Player, key: string, value: any)
	local profile = self._profiles[player]
	if profile then
		profile.settings[key] = value
	end
end

-- --- lifecycle --------------------------------------------------------------

function DataService:Start()
	self._loaded = Remotes.getEvent("Profile", "ProfileLoaded")

	local getProfile = Remotes.getFunction("Profile", "GetProfile")
	getProfile.OnServerInvoke = function(player)
		local profile = self._profiles[player]
		if not profile then
			return nil
		end
		-- Only ever hand the client its own, non-sensitive view.
		return {
			xp = profile.xp,
			rankTier = profile.rankTier,
			stats = profile.stats,
			settings = profile.settings,
			unlocks = profile.unlocks,
		}
	end

	local function onPlayer(player: Player)
		task.spawn(function()
			self:_load(player)
		end)
	end
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	Players.PlayerAdded:Connect(onPlayer)

	Players.PlayerRemoving:Connect(function(player)
		self:save(player)
		self._profiles[player] = nil
	end)

	-- Autosave.
	task.spawn(function()
		while true do
			task.wait(self._config.AutoSaveInterval)
			for player in self._profiles do
				self:save(player)
			end
		end
	end)

	-- Flush everything on shutdown.
	game:BindToClose(function()
		for player in self._profiles do
			self:save(player)
		end
	end)

	log.info(string.format("online — profiles (%s)", self._useMock and "in-memory/Studio" or "DataStore"))
end

return DataService
