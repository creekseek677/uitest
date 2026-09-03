--[[
	Xenia UI — Merged Orion/Kavo Style (v5)
	• Fixed errors from both Veyra sources
	• Notifications ~5× smaller + always draggable
	• Full-screen optional intro (typewriter + per-letter SFX)
	• Key system (local keys + remote API + optional HWID) — gates UI, hard to skip
	• Extra themes: Midnight, Serpent, Ocean, Blood, Grape, Synapse, Neon, Light, Dark
	• MultiDropdown, ColorPicker, Paragraph restored
	• Responsive, cleanup, TweenEngine preserved
	• Simple API + full Create* API
	• Config: Xenia/Xenia.json

	Usage:
		local Library = loadstring(...)()

		Library:Init({
			Theme = "Midnight",
			Intro = true,
			IntroConfig = {
				Title = "Xenia",
				Subtitle = "Loading modules...",
				Duration = 2.2,
			},
			KeySystem = {
				Enabled = true,
				Title = "Xenia Key System",
				Subtitle = "Enter key to continue",
				Note = "Get key from discord.gg/yourserver",
				Keys = { "your-local-key-1", "another-key" },
				-- GetKey = "https://pastebin.com/raw/XXXX",
				SaveKey = true,
				-- BindHWID = true,
			},
		})

		local Window = Library:New("My Hub", "v5")
		local Tab = Window:Tab("Main")
		Tab:Toggle("Example", false, function(v) print(v) end)
		Library:Notify("Ready", "UI loaded", 3)
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local LocalizationService = game:GetService("LocalizationService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

----------------------------------------------------------------
-- CONFIG
----------------------------------------------------------------
local CONFIG_FOLDER = "Xenia"
local CONFIG_FILE = "Xenia/Xenia.json"
local KEY_FILE = "Xenia/key.txt"

local DefaultSettings = {
	Theme = "Dark",
	ToggleUIKey = "RightControl",
	UIVisible = true,
}

local Settings = {}
for k, v in pairs(DefaultSettings) do Settings[k] = v end

local function ConfigEncode(tbl)
	local ok, encoded = pcall(function() return HttpService:JSONEncode(tbl) end)
	if ok and encoded then return encoded end
	local parts = {}
	for k, v in pairs(tbl) do
		local vs = tostring(v)
		if type(v) == "string" then vs = '"' .. (string.gsub(vs, '"', '\\"')) .. '"'
		elseif type(v) == "boolean" then vs = v and "true" or "false" end
		table.insert(parts, '"' .. tostring(k) .. '":' .. vs)
	end
	return "{" .. table.concat(parts, ",") .. "}"
end

local function ConfigDecode(str)
	if type(str) ~= "string" or #str == 0 then return nil end
	local ok, decoded = pcall(function() return HttpService:JSONDecode(str) end)
	if ok and type(decoded) == "table" then return decoded end
	return nil
end

local function ConfigLoad()
	local raw
	pcall(function()
		if type(isfile) == "function" and isfile(CONFIG_FILE) then
			raw = readfile(CONFIG_FILE)
		elseif type(readfile) == "function" then
			raw = readfile(CONFIG_FILE)
		end
	end)
	if not raw then return false end
	local data = ConfigDecode(raw)
	if type(data) ~= "table" then return false end
	for k, v in pairs(data) do Settings[k] = v end
	return true
end

local function ConfigSave()
	local payload = ConfigEncode(Settings)
	local ok = false
	pcall(function()
		if type(makefolder) == "function" then pcall(makefolder, CONFIG_FOLDER) end
		if type(writefile) == "function" then
			writefile(CONFIG_FILE, payload)
			ok = true
		end
	end)
	return ok
end

pcall(ConfigLoad)

local function KeyCodeFromName(name)
	if typeof(name) == "EnumItem" then return name end
	if type(name) ~= "string" or name == "" or name == "None" then return Enum.KeyCode.Unknown end
	local ok, kc = pcall(function() return Enum.KeyCode[name] end)
	if ok and kc then return kc end
	return Enum.KeyCode.Unknown
end

----------------------------------------------------------------
-- SIGNAL
----------------------------------------------------------------
local function CreateSignal()
	local handlers, destroyed = {}, false
	local api = {}
	function api:Connect(fn)
		if destroyed or type(fn) ~= "function" then return { Disconnect = function() end, Connected = false } end
		local conn = { _fn = fn, Connected = true }
		function conn:Disconnect()
			if not self.Connected then return end
			self.Connected = false
			for i = #handlers, 1, -1 do
				if handlers[i] == self then table.remove(handlers, i) break end
			end
		end
		table.insert(handlers, conn)
		return conn
	end
	function api:Once(fn)
		local conn
		conn = api:Connect(function(...) conn:Disconnect() fn(...) end)
		return conn
	end
	function api:Fire(...)
		if destroyed then return end
		local snap = table.clone(handlers)
		for _, c in ipairs(snap) do if c.Connected then task.spawn(c._fn, ...) end end
	end
	function api:DisconnectAll()
		for _, c in ipairs(handlers) do c.Connected = false end
		table.clear(handlers)
	end
	function api:Destroy()
		if destroyed then return end
		destroyed = true
		api:DisconnectAll()
	end
	function api:IsDestroyed() return destroyed end
	return api
end

----------------------------------------------------------------
-- PROTECT + PARENT
----------------------------------------------------------------
local function ProtectAndParent(sg)
	sg.ResetOnSpawn = false
	pcall(function()
		if type(syn) == "table" and type(syn.protect_gui) == "function" then syn.protect_gui(sg) end
	end)
	local ok = pcall(function() sg.Parent = game:GetService("CoreGui") end)
	if ok and sg.Parent then return end
	ok = pcall(function() if type(gethui) == "function" then sg.Parent = gethui() end end)
	if ok and sg.Parent then return end
	sg.Parent = PlayerGui
end

----------------------------------------------------------------
-- THEME + PRESETS (Orion/Kavo inspired)
----------------------------------------------------------------
local Theme = {
	Background = Color3.fromRGB(12, 12, 14),
	Secondary = Color3.fromRGB(18, 18, 22),
	Tertiary = Color3.fromRGB(24, 24, 28),
	Hover = Color3.fromRGB(28, 28, 34),
	Text = Color3.fromRGB(240, 240, 245),
	SecondaryText = Color3.fromRGB(150, 150, 160),
	MutedText = Color3.fromRGB(100, 100, 110),
	Accent = Color3.fromRGB(132, 96, 255),
	Border = Color3.fromRGB(40, 40, 48),
	ToggleOn = Color3.fromRGB(255, 255, 255),
	ToggleOff = Color3.fromRGB(50, 50, 58),
	SliderTrack = Color3.fromRGB(35, 35, 42),
	SliderFill = Color3.fromRGB(255, 255, 255),
	NotificationBackground = Color3.fromRGB(8, 8, 10),
	NotificationBorder = Color3.fromRGB(30, 30, 36),
	NotificationTitle = Color3.fromRGB(245, 245, 250),
	NotificationDescription = Color3.fromRGB(160, 160, 170),
	NotificationInfo = Color3.fromRGB(100, 160, 255),
	NotificationSuccess = Color3.fromRGB(80, 200, 120),
	NotificationWarning = Color3.fromRGB(255, 180, 60),
	NotificationError = Color3.fromRGB(255, 80, 80),
	OutlineAccent = Color3.fromRGB(255, 255, 255),
	Font = Enum.Font.GothamMedium,
	FontBold = Enum.Font.GothamBold,
	FontMono = Enum.Font.Code,
	CornerRadius = 6,
	WindowCornerRadius = 8,
	CardCornerRadius = 6,
	ButtonCornerRadius = 5,
	NotificationCornerRadius = 6,
	ElementHeight = 34,
	AnimationSpeed = 0.22,
	HoverSpeed = 0.12,
	ShadowTransparency = 0.5,
}

local ThemePresets = {
	Dark = {
		Background = Color3.fromRGB(12, 12, 14),
		Secondary = Color3.fromRGB(18, 18, 22),
		Tertiary = Color3.fromRGB(24, 24, 28),
		Hover = Color3.fromRGB(28, 28, 34),
		Text = Color3.fromRGB(240, 240, 245),
		SecondaryText = Color3.fromRGB(150, 150, 160),
		MutedText = Color3.fromRGB(100, 100, 110),
		Accent = Color3.fromRGB(132, 96, 255),
		Border = Color3.fromRGB(40, 40, 48),
		ToggleOn = Color3.fromRGB(255, 255, 255),
		ToggleOff = Color3.fromRGB(50, 50, 58),
		SliderTrack = Color3.fromRGB(35, 35, 42),
		SliderFill = Color3.fromRGB(255, 255, 255),
		NotificationBackground = Color3.fromRGB(8, 8, 10),
		NotificationBorder = Color3.fromRGB(30, 30, 36),
		NotificationTitle = Color3.fromRGB(245, 245, 250),
		NotificationDescription = Color3.fromRGB(160, 160, 170),
		NotificationInfo = Color3.fromRGB(100, 160, 255),
		NotificationSuccess = Color3.fromRGB(80, 200, 120),
		NotificationWarning = Color3.fromRGB(255, 180, 60),
		NotificationError = Color3.fromRGB(255, 80, 80),
	},
	Light = {
		Background = Color3.fromRGB(245, 245, 248),
		Secondary = Color3.fromRGB(255, 255, 255),
		Tertiary = Color3.fromRGB(235, 235, 240),
		Hover = Color3.fromRGB(225, 225, 232),
		Text = Color3.fromRGB(20, 20, 28),
		SecondaryText = Color3.fromRGB(90, 90, 105),
		MutedText = Color3.fromRGB(140, 140, 155),
		Accent = Color3.fromRGB(30, 30, 40),
		Border = Color3.fromRGB(210, 210, 220),
		ToggleOn = Color3.fromRGB(40, 40, 50),
		ToggleOff = Color3.fromRGB(200, 200, 210),
		SliderTrack = Color3.fromRGB(220, 220, 230),
		SliderFill = Color3.fromRGB(40, 40, 50),
		NotificationBackground = Color3.fromRGB(255, 255, 255),
		NotificationBorder = Color3.fromRGB(220, 220, 230),
		NotificationTitle = Color3.fromRGB(20, 20, 28),
		NotificationDescription = Color3.fromRGB(90, 90, 105),
		NotificationInfo = Color3.fromRGB(40, 120, 220),
		NotificationSuccess = Color3.fromRGB(30, 160, 90),
		NotificationWarning = Color3.fromRGB(210, 140, 30),
		NotificationError = Color3.fromRGB(210, 50, 50),
	},
	Neon = {
		Background = Color3.fromRGB(8, 6, 16),
		Secondary = Color3.fromRGB(14, 10, 28),
		Tertiary = Color3.fromRGB(22, 16, 40),
		Hover = Color3.fromRGB(32, 24, 56),
		Text = Color3.fromRGB(230, 220, 255),
		SecondaryText = Color3.fromRGB(160, 140, 220),
		MutedText = Color3.fromRGB(110, 90, 160),
		Accent = Color3.fromRGB(180, 80, 255),
		Border = Color3.fromRGB(60, 40, 100),
		ToggleOn = Color3.fromRGB(180, 80, 255),
		ToggleOff = Color3.fromRGB(40, 30, 70),
		SliderTrack = Color3.fromRGB(30, 20, 55),
		SliderFill = Color3.fromRGB(180, 80, 255),
		NotificationBackground = Color3.fromRGB(10, 8, 20),
		NotificationBorder = Color3.fromRGB(50, 30, 90),
		NotificationTitle = Color3.fromRGB(240, 230, 255),
		NotificationDescription = Color3.fromRGB(160, 140, 220),
		NotificationInfo = Color3.fromRGB(120, 160, 255),
		NotificationSuccess = Color3.fromRGB(80, 220, 160),
		NotificationWarning = Color3.fromRGB(255, 180, 80),
		NotificationError = Color3.fromRGB(255, 80, 120),
	},
	Midnight = {
		Background = Color3.fromRGB(10, 10, 18),
		Secondary = Color3.fromRGB(16, 16, 28),
		Tertiary = Color3.fromRGB(22, 22, 36),
		Hover = Color3.fromRGB(30, 30, 48),
		Text = Color3.fromRGB(220, 225, 240),
		SecondaryText = Color3.fromRGB(140, 145, 170),
		MutedText = Color3.fromRGB(90, 95, 120),
		Accent = Color3.fromRGB(90, 120, 255),
		Border = Color3.fromRGB(35, 40, 60),
		ToggleOn = Color3.fromRGB(90, 120, 255),
		ToggleOff = Color3.fromRGB(40, 45, 65),
		SliderTrack = Color3.fromRGB(28, 30, 45),
		SliderFill = Color3.fromRGB(90, 120, 255),
		NotificationBackground = Color3.fromRGB(8, 8, 16),
		NotificationBorder = Color3.fromRGB(30, 35, 55),
		NotificationTitle = Color3.fromRGB(230, 235, 250),
		NotificationDescription = Color3.fromRGB(140, 150, 180),
		NotificationInfo = Color3.fromRGB(90, 140, 255),
		NotificationSuccess = Color3.fromRGB(70, 200, 140),
		NotificationWarning = Color3.fromRGB(255, 170, 50),
		NotificationError = Color3.fromRGB(255, 70, 90),
	},
	Serpent = {
		Background = Color3.fromRGB(8, 14, 12),
		Secondary = Color3.fromRGB(12, 22, 18),
		Tertiary = Color3.fromRGB(18, 30, 24),
		Hover = Color3.fromRGB(24, 40, 32),
		Text = Color3.fromRGB(210, 245, 220),
		SecondaryText = Color3.fromRGB(120, 170, 140),
		MutedText = Color3.fromRGB(80, 120, 100),
		Accent = Color3.fromRGB(60, 220, 140),
		Border = Color3.fromRGB(30, 55, 40),
		ToggleOn = Color3.fromRGB(60, 220, 140),
		ToggleOff = Color3.fromRGB(30, 50, 40),
		SliderTrack = Color3.fromRGB(25, 45, 35),
		SliderFill = Color3.fromRGB(60, 220, 140),
		NotificationBackground = Color3.fromRGB(6, 12, 10),
		NotificationBorder = Color3.fromRGB(25, 50, 35),
		NotificationTitle = Color3.fromRGB(220, 250, 230),
		NotificationDescription = Color3.fromRGB(130, 180, 150),
		NotificationInfo = Color3.fromRGB(80, 200, 160),
		NotificationSuccess = Color3.fromRGB(50, 230, 120),
		NotificationWarning = Color3.fromRGB(230, 200, 60),
		NotificationError = Color3.fromRGB(255, 90, 90),
	},
	Ocean = {
		Background = Color3.fromRGB(8, 14, 22),
		Secondary = Color3.fromRGB(12, 20, 32),
		Tertiary = Color3.fromRGB(18, 28, 42),
		Hover = Color3.fromRGB(26, 38, 56),
		Text = Color3.fromRGB(210, 230, 250),
		SecondaryText = Color3.fromRGB(120, 160, 200),
		MutedText = Color3.fromRGB(80, 110, 150),
		Accent = Color3.fromRGB(50, 160, 255),
		Border = Color3.fromRGB(30, 50, 70),
		ToggleOn = Color3.fromRGB(50, 160, 255),
		ToggleOff = Color3.fromRGB(30, 45, 65),
		SliderTrack = Color3.fromRGB(25, 40, 60),
		SliderFill = Color3.fromRGB(50, 160, 255),
		NotificationBackground = Color3.fromRGB(6, 12, 20),
		NotificationBorder = Color3.fromRGB(25, 45, 65),
		NotificationTitle = Color3.fromRGB(220, 240, 255),
		NotificationDescription = Color3.fromRGB(130, 170, 210),
		NotificationInfo = Color3.fromRGB(60, 160, 255),
		NotificationSuccess = Color3.fromRGB(50, 210, 150),
		NotificationWarning = Color3.fromRGB(255, 180, 50),
		NotificationError = Color3.fromRGB(255, 80, 100),
	},
	Blood = {
		Background = Color3.fromRGB(18, 8, 10),
		Secondary = Color3.fromRGB(28, 12, 14),
		Tertiary = Color3.fromRGB(38, 16, 18),
		Hover = Color3.fromRGB(50, 22, 24),
		Text = Color3.fromRGB(250, 220, 220),
		SecondaryText = Color3.fromRGB(180, 120, 120),
		MutedText = Color3.fromRGB(130, 80, 80),
		Accent = Color3.fromRGB(220, 40, 60),
		Border = Color3.fromRGB(60, 25, 30),
		ToggleOn = Color3.fromRGB(220, 40, 60),
		ToggleOff = Color3.fromRGB(50, 25, 30),
		SliderTrack = Color3.fromRGB(45, 20, 25),
		SliderFill = Color3.fromRGB(220, 40, 60),
		NotificationBackground = Color3.fromRGB(14, 6, 8),
		NotificationBorder = Color3.fromRGB(50, 20, 25),
		NotificationTitle = Color3.fromRGB(255, 230, 230),
		NotificationDescription = Color3.fromRGB(190, 130, 130),
		NotificationInfo = Color3.fromRGB(100, 140, 255),
		NotificationSuccess = Color3.fromRGB(80, 200, 100),
		NotificationWarning = Color3.fromRGB(255, 160, 40),
		NotificationError = Color3.fromRGB(255, 50, 50),
	},
	Grape = {
		Background = Color3.fromRGB(16, 10, 22),
		Secondary = Color3.fromRGB(24, 16, 34),
		Tertiary = Color3.fromRGB(32, 22, 46),
		Hover = Color3.fromRGB(42, 30, 60),
		Text = Color3.fromRGB(235, 220, 255),
		SecondaryText = Color3.fromRGB(160, 140, 200),
		MutedText = Color3.fromRGB(110, 90, 150),
		Accent = Color3.fromRGB(160, 80, 255),
		Border = Color3.fromRGB(50, 35, 80),
		ToggleOn = Color3.fromRGB(160, 80, 255),
		ToggleOff = Color3.fromRGB(40, 30, 60),
		SliderTrack = Color3.fromRGB(35, 25, 55),
		SliderFill = Color3.fromRGB(160, 80, 255),
		NotificationBackground = Color3.fromRGB(12, 8, 18),
		NotificationBorder = Color3.fromRGB(45, 30, 70),
		NotificationTitle = Color3.fromRGB(245, 230, 255),
		NotificationDescription = Color3.fromRGB(170, 150, 210),
		NotificationInfo = Color3.fromRGB(120, 140, 255),
		NotificationSuccess = Color3.fromRGB(90, 210, 140),
		NotificationWarning = Color3.fromRGB(255, 180, 60),
		NotificationError = Color3.fromRGB(255, 80, 120),
	},
	Synapse = {
		Background = Color3.fromRGB(20, 20, 24),
		Secondary = Color3.fromRGB(28, 28, 34),
		Tertiary = Color3.fromRGB(36, 36, 44),
		Hover = Color3.fromRGB(48, 48, 58),
		Text = Color3.fromRGB(240, 240, 245),
		SecondaryText = Color3.fromRGB(160, 160, 175),
		MutedText = Color3.fromRGB(110, 110, 125),
		Accent = Color3.fromRGB(0, 170, 255),
		Border = Color3.fromRGB(50, 50, 60),
		ToggleOn = Color3.fromRGB(0, 170, 255),
		ToggleOff = Color3.fromRGB(55, 55, 65),
		SliderTrack = Color3.fromRGB(40, 40, 50),
		SliderFill = Color3.fromRGB(0, 170, 255),
		NotificationBackground = Color3.fromRGB(16, 16, 20),
		NotificationBorder = Color3.fromRGB(45, 45, 55),
		NotificationTitle = Color3.fromRGB(245, 245, 250),
		NotificationDescription = Color3.fromRGB(160, 165, 180),
		NotificationInfo = Color3.fromRGB(0, 170, 255),
		NotificationSuccess = Color3.fromRGB(60, 200, 120),
		NotificationWarning = Color3.fromRGB(255, 180, 40),
		NotificationError = Color3.fromRGB(255, 70, 70),
	},
}

local ThemeListeners = {}

local function NormalizeThemeAliases()
	Theme.TextPrimary = Theme.Text
	Theme.TextSecondary = Theme.SecondaryText
	Theme.TextMuted = Theme.MutedText
	Theme.Surface = Theme.Secondary
	Theme.SurfaceHover = Theme.Hover
	Theme.SurfacePressed = Theme.Tertiary
	Theme.WindowRadius = Theme.WindowCornerRadius or 8
	Theme.CardRadius = Theme.CardCornerRadius or Theme.CornerRadius or 6
	Theme.ButtonRadius = Theme.ButtonCornerRadius or Theme.CornerRadius or 5
	Theme.NotificationRadius = Theme.NotificationCornerRadius or 6
	Theme.Shadow = Theme.Shadow or Color3.new(0, 0, 0)
end
NormalizeThemeAliases()

local function GetTheme() return Theme end

local function SetTheme(t)
	if type(t) ~= "table" then return end
	for k, v in pairs(t) do Theme[k] = v end
	NormalizeThemeAliases()
	for _, fn in ipairs(ThemeListeners) do task.spawn(fn) end
end

local function ApplyThemePreset(name)
	local preset = ThemePresets[name]
	if not preset then
		warn("[Xenia] Unknown theme:", tostring(name))
		return false
	end
	SetTheme(preset)
	return true
end

local function OnThemeChange(fn)
	table.insert(ThemeListeners, fn)
	return function()
		local i = table.find(ThemeListeners, fn)
		if i then table.remove(ThemeListeners, i) end
	end
end

----------------------------------------------------------------
-- CLEANUP
----------------------------------------------------------------
local function CreateCleanup()
	local connections, instances, tasks, callbacks = {}, {}, {}, {}
	local destroyed = false
	local api = {}
	function api:AddConnection(c)
		if destroyed then if c and c.Connected then c:Disconnect() end return end
		table.insert(connections, c)
	end
	function api:AddInstance(i)
		if destroyed then if i then i:Destroy() end return end
		table.insert(instances, i)
	end
	function api:AddTask(t)
		if destroyed then pcall(task.cancel, t) return end
		table.insert(tasks, t)
	end
	function api:AddCallback(fn)
		if destroyed then return end
		table.insert(callbacks, fn)
	end
	function api:Destroy()
		if destroyed then return end
		destroyed = true
		for _, i in ipairs(instances) do
			if i then pcall(function() TweenEngine.CancelOnObject(i) end) end
		end
		for _, c in ipairs(connections) do
			if c and c.Connected then pcall(function() c:Disconnect() end) end
		end
		for _, i in ipairs(instances) do
			if i and i.Parent then pcall(function() i:Destroy() end) end
		end
		for _, t in ipairs(tasks) do pcall(task.cancel, t) end
		for _, fn in ipairs(callbacks) do pcall(fn) end
		table.clear(connections)
		table.clear(instances)
		table.clear(tasks)
		table.clear(callbacks)
	end
	function api:IsDestroyed() return destroyed end
	return api
end

----------------------------------------------------------------
-- EASING + TWEEN ENGINE (hardened)
----------------------------------------------------------------
local Easing = {}
function Easing.Linear(t) return t end
function Easing.QuadIn(t) return t * t end
function Easing.QuadOut(t) return t * (2 - t) end
function Easing.QuadInOut(t)
	if t < 0.5 then return 2 * t * t end
	return -1 + (4 - 2 * t) * t
end
function Easing.CubicOut(t)
	local t1 = t - 1
	return t1 * t1 * t1 + 1
end
function Easing.QuintOut(t)
	local t1 = t - 1
	return 1 + t1 * t1 * t1 * t1 * t1
end
function Easing.ExpoOut(t)
	if t == 1 then return 1 end
	return 1 - math.pow(2, -10 * t)
end
function Easing.BackOut(t)
	local s = 1.70158
	local t1 = t - 1
	return t1 * t1 * ((s + 1) * t1 + s) + 1
end
function Easing.SineOut(t) return math.sin(t * math.pi / 2) end

local EasingNamed = {
	Linear = Easing.Linear, QuadIn = Easing.QuadIn, QuadOut = Easing.QuadOut, QuadInOut = Easing.QuadInOut,
	CubicOut = Easing.CubicOut, QuintOut = Easing.QuintOut, ExpoOut = Easing.ExpoOut,
	BackOut = Easing.BackOut, SineOut = Easing.SineOut,
}
local function GetEasing(name)
	if type(name) == "function" then return name end
	return EasingNamed[name] or Easing.Linear
end

local ActiveAnims = {}
local SchedulerConn = nil
local AnimIdCounter = 0

local function SchedulerUpdate(dt)
	local remove = {}
	for id, anim in pairs(ActiveAnims) do
		if anim.Cancelled or anim._finished then
			table.insert(remove, id)
		else
			local ok, done = pcall(function() return anim:Update(dt) end)
			if not ok or done then
				anim._finished = true
				table.insert(remove, id)
				if ok and anim.OnComplete and not anim.Cancelled then task.spawn(anim.OnComplete) end
			end
		end
	end
	for _, id in ipairs(remove) do
		local anim = ActiveAnims[id]
		if anim then anim.Id = nil end
		ActiveAnims[id] = nil
	end
	if next(ActiveAnims) == nil and SchedulerConn then
		SchedulerConn:Disconnect()
		SchedulerConn = nil
	end
end

local function SchedulerAdd(anim)
	if anim.Cancelled or anim._finished then return nil end
	AnimIdCounter += 1
	local id = "a" .. AnimIdCounter
	anim.Id = id
	ActiveAnims[id] = anim
	if not SchedulerConn then SchedulerConn = RunService.Heartbeat:Connect(SchedulerUpdate) end
	return id
end

local function SchedulerRemove(anim)
	if anim and anim.Id and ActiveAnims[anim.Id] then
		ActiveAnims[anim.Id] = nil
		anim.Id = nil
	end
end

local function LerpNumber(a, b, t) return a + (b - a) * t end
local function LerpColor3(a, b, t)
	return Color3.new(LerpNumber(a.R, b.R, t), LerpNumber(a.G, b.G, t), LerpNumber(a.B, b.B, t))
end
local function LerpUDim2(a, b, t)
	return UDim2.new(
		LerpNumber(a.X.Scale, b.X.Scale, t), LerpNumber(a.X.Offset, b.X.Offset, t),
		LerpNumber(a.Y.Scale, b.Y.Scale, t), LerpNumber(a.Y.Offset, b.Y.Offset, t)
	)
end
local function GetLerp(v)
	local t = typeof(v)
	if t == "number" then return LerpNumber
	elseif t == "Color3" then return LerpColor3
	elseif t == "UDim2" then return LerpUDim2
	end
	return nil
end

local Animation = {}
Animation.__index = Animation
function Animation.new(object, goals, options)
	local self = setmetatable({}, Animation)
	options = options or {}
	self.Object = object
	self.Goals = goals
	self.Duration = math.max(options.Duration or 0.35, 0.001)
	self.Delay = options.Delay or 0
	self.EasingFn = GetEasing(options.Easing or "QuadOut")
	self.OnComplete = options.OnComplete
	self.Cancelled = false
	self._finished = false
	self.Elapsed = 0
	self.Started = false
	self.StartValues = {}
	self.LerpFns = {}
	self.Id = nil
	for prop, goal in pairs(goals) do
		local ok, current = pcall(function() return object[prop] end)
		if ok and current ~= nil then
			self.StartValues[prop] = current
			self.LerpFns[prop] = GetLerp(current)
		end
	end
	return self
end
function Animation:Update(dt)
	if self.Cancelled or self._finished then return true end
	if not self.Started then
		self.Elapsed += dt
		if self.Elapsed < self.Delay then return false end
		self.Started = true
		self.Elapsed = 0
	end
	self.Elapsed += dt
	local alpha = math.clamp(self.Elapsed / self.Duration, 0, 1)
	local eased = self.EasingFn(alpha)
	for prop, goal in pairs(self.Goals) do
		local lerp = self.LerpFns[prop]
		local start = self.StartValues[prop]
		if lerp and start ~= nil then
			local value = lerp(start, goal, eased)
			pcall(function()
				if self.Object and self.Object.Parent then self.Object[prop] = value end
			end)
		end
	end
	if self.Elapsed >= self.Duration then
		for prop, goal in pairs(self.Goals) do
			pcall(function()
				if self.Object and self.Object.Parent then self.Object[prop] = goal end
			end)
		end
		self._finished = true
		return true
	end
	return false
end
function Animation:Cancel()
	if self.Cancelled or self._finished then return end
	self.Cancelled = true
	self._finished = true
	self.OnComplete = nil
	SchedulerRemove(self)
end
function Animation:Play()
	if self.Cancelled or self._finished then return self end
	self.Id = SchedulerAdd(self)
	return self
end

local TweenEngine = {}
function TweenEngine.Play(object, goals, options)
	if not object or not object.Parent then return nil end
	local anim = Animation.new(object, goals, options)
	return anim:Play()
end
function TweenEngine.CancelAll()
	for id, anim in pairs(ActiveAnims) do
		if anim and not anim.Cancelled then
			anim.Cancelled = true
			anim._finished = true
			anim.OnComplete = nil
		end
	end
	table.clear(ActiveAnims)
	if SchedulerConn then SchedulerConn:Disconnect() SchedulerConn = nil end
end
function TweenEngine.CancelOnObject(object)
	if not object then return end
	for id, anim in pairs(ActiveAnims) do
		if anim and anim.Object == object and not anim.Cancelled then anim:Cancel() end
	end
end

----------------------------------------------------------------
-- DRAG
----------------------------------------------------------------
local function MakeDraggable(handle, target, options)
	options = options or {}
	target = target or handle
	local enabled = true
	local dragging = false
	local dragStart, startPos
	local conns = {}
	local activeMoveC, activeEndC

	local function clearDragConns()
		if activeMoveC then pcall(function() activeMoveC:Disconnect() end) activeMoveC = nil end
		if activeEndC then pcall(function() activeEndC:Disconnect() end) activeEndC = nil end
		dragging = false
	end

	local function update(input)
		local delta = input.Position - dragStart
		local newPos = UDim2.new(
			startPos.X.Scale, startPos.X.Offset + delta.X,
			startPos.Y.Scale, startPos.Y.Offset + delta.Y
		)
		target.Position = newPos
		if options.OnDrag then options.OnDrag(newPos, delta) end
	end

	table.insert(conns, handle.InputBegan:Connect(function(input)
		if not enabled then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			clearDragConns()
			dragging = true
			dragStart = input.Position
			startPos = target.Position
			if options.OnDragStart then options.OnDragStart() end
			activeMoveC = UserInputService.InputChanged:Connect(function(inp)
				if (inp.UserInputType == Enum.UserInputType.MouseMovement or inp.UserInputType == Enum.UserInputType.Touch) and dragging then
					update(inp)
				end
			end)
			activeEndC = UserInputService.InputEnded:Connect(function(inp)
				if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
					dragging = false
					clearDragConns()
					if options.OnDragEnd then options.OnDragEnd() end
				end
			end)
		end
	end))

	return {
		SetEnabled = function(s) enabled = s end,
		Destroy = function()
			clearDragConns()
			for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
			table.clear(conns)
		end
	}
end

----------------------------------------------------------------
-- TYPEWRITER (with optional SFX)
----------------------------------------------------------------
local TYPEWRITER_SOUND = "rbxassetid://9120299407" -- Typewriter 3 SFX

local function CreateTypewriter(label, options)
	options = options or {}
	local speed = options.Speed or 0.035
	local fullText = label.Text or ""
	local cancelled = false
	local finished = false
	local thread = nil
	local soundId = options.Sound or TYPEWRITER_SOUND
	local playSound = options.PlaySound ~= false

	local api = {}
	function api:Start(text)
		if text then fullText = text end
		cancelled = false
		finished = false
		label.Text = ""
		thread = task.spawn(function()
			for i = 1, #fullText do
				if cancelled then return end
				label.Text = string.sub(fullText, 1, i)
				if playSound and soundId and soundId ~= "" then
					local s = Instance.new("Sound")
					s.SoundId = soundId
					s.Volume = 0.35
					s.Parent = SoundService
					pcall(function() s:Play() end)
					task.delay(0.4, function() pcall(function() s:Destroy() end) end)
				end
				local char = string.sub(fullText, i, i)
				local d = speed
				if char == "." or char == "!" or char == "?" then d = speed * 3.5
				elseif char == "," or char == ";" then d = speed * 2
				elseif char == " " then d = speed * 0.55 end
				task.wait(d)
			end
			finished = true
			if options.OnComplete then options.OnComplete() end
		end)
	end
	function api:Finish()
		cancelled = true
		if thread then pcall(task.cancel, thread) end
		label.Text = fullText
		finished = true
	end
	function api:Cancel()
		cancelled = true
		if thread then pcall(task.cancel, thread) end
	end
	function api:IsFinished() return finished end
	return api
end

----------------------------------------------------------------
-- NOTIFICATION SYSTEM (5× smaller, always draggable)
----------------------------------------------------------------
local NotificationManager = {}
NotificationManager.__index = NotificationManager

local MAX_NOTIFICATIONS = 8
local NOTIF_WIDTH = 64          -- ~5× smaller than 320
local NOTIF_HEADER_H = 18
local NOTIF_PAD = 6

function NotificationManager.new()
	local self = setmetatable({}, NotificationManager)
	self.Notifications = {}
	self.Spacing = 6
	self.MaxNotifications = MAX_NOTIFICATIONS
	self.Draggable = true

	local gui = Instance.new("ScreenGui")
	gui.Name = "XeniaNotifications"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 2147483646
	ProtectAndParent(gui)

	local container = Instance.new("Frame")
	container.Name = "Container"
	container.BackgroundTransparency = 1
	container.Size = UDim2.new(0, 80, 1, -16)
	container.Position = UDim2.new(1, -8, 1, -8)
	container.AnchorPoint = Vector2.new(1, 1)
	container.Parent = gui

	self.Gui = gui
	self.Container = container
	return self
end

local TYPE_COLORS = {
	Info = "NotificationInfo",
	Success = "NotificationSuccess",
	Warning = "NotificationWarning",
	Error = "NotificationError",
	Custom = "Accent",
}

function NotificationManager:Notify(config)
	config = config or {}
	local duration = config.Duration
	if duration == nil then duration = config.Length end
	if duration == nil then duration = 4 end
	local notifType = config.Type or "Info"
	local barColor = config.BarColor or Theme[TYPE_COLORS[notifType] or "NotificationInfo"] or Theme.Accent

	local cleanup = CreateCleanup()
	local closed = false

	local bg = Theme.NotificationBackground or Theme.Background
	local titleCol = Theme.NotificationTitle or Theme.Text
	local descCol = Theme.NotificationDescription or Theme.SecondaryText

	local frame = Instance.new("Frame")
	frame.Name = "Notification"
	frame.BackgroundColor3 = bg
	frame.BackgroundTransparency = 0.05
	frame.BorderSizePixel = 0
	frame.Size = UDim2.new(0, NOTIF_WIDTH, 0, 0)
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.AnchorPoint = Vector2.new(0, 1)
	frame.Position = UDim2.new(0, 0, 1, 0)
	frame.ClipsDescendants = true
	frame.Parent = self.Container

	-- always draggable by default
	local canDrag = self.Draggable ~= false and config.Draggable ~= false
	if canDrag then
		local dragApi = MakeDraggable(frame, frame)
		cleanup:AddCallback(function() if dragApi and dragApi.Destroy then dragApi:Destroy() end end)
	end

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.NotificationBorder or Theme.Border
	stroke.Thickness = 1
	stroke.Transparency = 0.4
	stroke.Parent = frame

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, -8, 0, 14)
	title.Position = UDim2.new(0, 4, 0, 3)
	title.Font = Theme.FontBold
	title.TextSize = 10
	title.TextColor3 = titleCol
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextTruncate = Enum.TextTruncate.AtEnd
	title.Text = config.Title or "!"
	title.Parent = frame

	local descText = config.Description or config.Content or ""
	local desc = Instance.new("TextLabel")
	desc.Name = "Description"
	desc.BackgroundTransparency = 1
	desc.Size = UDim2.new(1, -8, 0, 0)
	desc.Position = UDim2.new(0, 4, 0, 16)
	desc.AutomaticSize = Enum.AutomaticSize.Y
	desc.Font = Theme.Font
	desc.TextSize = 9
	desc.TextColor3 = descCol
	desc.TextXAlignment = Enum.TextXAlignment.Left
	desc.TextYAlignment = Enum.TextYAlignment.Top
	desc.TextWrapped = true
	desc.Text = descText
	desc.Parent = frame

	local pad = Instance.new("UIPadding")
	pad.PaddingBottom = UDim.new(0, 4)
	pad.Parent = frame

	-- thin accent bar
	local accent = Instance.new("Frame")
	accent.BackgroundColor3 = barColor
	accent.BorderSizePixel = 0
	accent.Size = UDim2.new(0, 2, 1, 0)
	accent.Position = UDim2.new(0, 0, 0, 0)
	accent.ZIndex = 5
	accent.Parent = frame

	-- progress
	local barBg = Instance.new("Frame")
	barBg.BackgroundColor3 = Theme.Border
	barBg.BackgroundTransparency = 0.6
	barBg.BorderSizePixel = 0
	barBg.Size = UDim2.new(1, 0, 0, 2)
	barBg.Position = UDim2.new(0, 0, 1, -2)
	barBg.ZIndex = 6
	barBg.Parent = frame

	local bar = Instance.new("Frame")
	bar.BackgroundColor3 = barColor
	bar.BorderSizePixel = 0
	bar.Size = UDim2.new(1, 0, 1, 0)
	bar.Parent = barBg

	if duration <= 0 then barBg.Visible = false end

	cleanup:AddInstance(frame)

	local notif = {
		Frame = frame,
		Closed = false,
		Config = config,
		Cleanup = cleanup,
		Manager = self,
	}

	function notif:PlayEntry(targetPos)
		frame.Position = UDim2.new(0, 20, 1, targetPos.Y.Offset)
		frame.BackgroundTransparency = 1
		TweenEngine.Play(frame, {
			Position = targetPos,
			BackgroundTransparency = 0.05,
		}, { Duration = 0.3, Easing = "QuintOut" })
		if duration > 0 then
			TweenEngine.Play(bar, { Size = UDim2.new(0, 0, 1, 0) }, { Duration = duration, Easing = "Linear" })
		end
	end

	function notif:PlayExit(callback)
		if closed then return end
		closed = true
		notif.Closed = true
		TweenEngine.CancelOnObject(bar)
		TweenEngine.Play(frame, {
			Position = UDim2.new(0, 30, 1, frame.Position.Y.Offset),
			BackgroundTransparency = 1,
		}, {
			Duration = 0.22,
			Easing = "QuadIn",
			OnComplete = function()
				cleanup:Destroy()
				if callback then callback() end
			end,
		})
	end

	function notif:Close()
		if closed then return end
		self.Manager:Remove(self)
	end

	table.insert(self.Notifications, 1, notif)

	while #self.Notifications > (self.MaxNotifications or MAX_NOTIFICATIONS) do
		local oldest = self.Notifications[#self.Notifications]
		if oldest and not oldest.Closed then oldest:Close()
		else table.remove(self.Notifications, #self.Notifications) end
	end

	task.defer(function()
		if closed then return end
		self:RepositionAll(true)
		notif:PlayEntry(self:GetPositionForIndex(1))
	end)

	if duration > 0 then
		local t = task.delay(duration, function()
			if not closed then notif:Close() end
		end)
		cleanup:AddTask(t)
	end

	return notif
end

function NotificationManager:GetPositionForIndex(index)
	local y = 0
	for i = 1, index - 1 do
		local n = self.Notifications[i]
		if n and n.Frame and not n.Closed then
			y = y - (n.Frame.AbsoluteSize.Y + self.Spacing)
		end
	end
	return UDim2.new(0, 0, 1, y)
end

function NotificationManager:RepositionAll(instant)
	for i, n in ipairs(self.Notifications) do
		if n and n.Frame and not n.Closed then
			local pos = self:GetPositionForIndex(i)
			if instant then
				n.Frame.Position = pos
			else
				TweenEngine.Play(n.Frame, { Position = pos }, { Duration = 0.2, Easing = "QuadOut" })
			end
		end
	end
end

function NotificationManager:Remove(notif)
	for i, n in ipairs(self.Notifications) do
		if n == notif then
			table.remove(self.Notifications, i)
			break
		end
	end
	notif:PlayExit(function()
		self:RepositionAll(false)
	end)
end

function NotificationManager:Clear()
	local snap = table.clone(self.Notifications)
	for _, n in ipairs(snap) do
		if n and not n.Closed then n:Close() end
	end
end

function NotificationManager:Destroy()
	self:Clear()
	if self.Gui then self.Gui:Destroy() end
end

----------------------------------------------------------------
-- INTRO (full-screen typewriter + SFX)
----------------------------------------------------------------
local function PlayIntro(config)
	config = config or {}
	local duration = config.Duration or 2.0
	local titleText = config.Title or "Xenia"
	local subtitleText = config.Subtitle or ""
	local logoId = config.Logo
	local soundId = config.Sound or TYPEWRITER_SOUND

	local cleanup = CreateCleanup()
	local gui = Instance.new("ScreenGui")
	gui.Name = "XeniaIntro"
	gui.DisplayOrder = 2147483647
	gui.IgnoreGuiInset = true
	ProtectAndParent(gui)
	cleanup:AddInstance(gui)

	local overlay = Instance.new("Frame")
	overlay.BackgroundColor3 = Color3.fromRGB(6, 6, 10)
	overlay.BorderSizePixel = 0
	overlay.Size = UDim2.new(1, 0, 1, 0)
	overlay.Parent = gui

	local center = Instance.new("Frame")
	center.BackgroundTransparency = 1
	center.Size = UDim2.new(0, 420, 0, 140)
	center.Position = UDim2.new(0.5, -210, 0.5, -70)
	center.Parent = overlay

	if logoId and tostring(logoId) ~= "" then
		local logo = Instance.new("ImageLabel")
		logo.BackgroundTransparency = 1
		logo.Size = UDim2.new(0, 48, 0, 48)
		logo.Position = UDim2.new(0.5, -24, 0, 0)
		logo.Image = tostring(logoId)
		logo.ScaleType = Enum.ScaleType.Fit
		logo.ImageTransparency = 1
		logo.Parent = center
		TweenEngine.Play(logo, { ImageTransparency = 0 }, { Duration = 0.35, Easing = "QuadOut" })
	end

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, 0, 0, 32)
	title.Position = UDim2.new(0, 0, 0, logoId and 56 or 20)
	title.Font = Theme.FontBold
	title.TextSize = 26
	title.TextColor3 = Theme.Text
	title.Text = ""
	title.Parent = center

	local subtitle = Instance.new("TextLabel")
	subtitle.BackgroundTransparency = 1
	subtitle.Size = UDim2.new(1, 0, 0, 20)
	subtitle.Position = UDim2.new(0, 0, 0, logoId and 92 or 56)
	subtitle.Font = Theme.Font
	subtitle.TextSize = 14
	subtitle.TextColor3 = Theme.SecondaryText
	subtitle.Text = ""
	subtitle.Parent = center

	local finished = false
	local function finish()
		if finished then return end
		finished = true
		TweenEngine.Play(overlay, { BackgroundTransparency = 1 }, {
			Duration = 0.4, Easing = "QuadIn",
			OnComplete = function() cleanup:Destroy() end,
		})
		TweenEngine.Play(title, { TextTransparency = 1 }, { Duration = 0.25 })
		TweenEngine.Play(subtitle, { TextTransparency = 1 }, { Duration = 0.25 })
	end

	-- typewriter title then subtitle
	local twTitle = CreateTypewriter(title, {
		Speed = 0.05,
		Sound = soundId,
		PlaySound = true,
		OnComplete = function()
			if subtitleText ~= "" then
				local twSub = CreateTypewriter(subtitle, {
					Speed = 0.03,
					Sound = soundId,
					PlaySound = true,
				})
				twSub:Start(subtitleText)
			end
		end,
	})
	twTitle:Start(titleText)

	cleanup:AddTask(task.delay(duration, finish))

	local skipBtn = Instance.new("TextButton")
	skipBtn.BackgroundTransparency = 1
	skipBtn.Size = UDim2.new(1, 0, 1, 0)
	skipBtn.Text = ""
	skipBtn.Parent = overlay
	cleanup:AddConnection(skipBtn.MouseButton1Click:Connect(finish))

	return { Skip = finish, Destroy = finish }
end

----------------------------------------------------------------
-- KEY SYSTEM (local + API, hard to skip)
----------------------------------------------------------------
local function SaveSavedKey(key)
	pcall(function()
		if type(makefolder) == "function" then pcall(makefolder, CONFIG_FOLDER) end
		if type(writefile) == "function" then writefile(KEY_FILE, tostring(key)) end
	end)
end

local function LoadSavedKey()
	local raw
	pcall(function()
		if type(isfile) == "function" and isfile(KEY_FILE) then
			raw = readfile(KEY_FILE)
		elseif type(readfile) == "function" then
			raw = readfile(KEY_FILE)
		end
	end)
	return raw and tostring(raw):gsub("%s+", "") or nil
end

local function GetHWID()
	local hwid = nil
	pcall(function()
		if type(gethwid) == "function" then hwid = gethwid() end
	end)
	if not hwid then
		pcall(function()
			if type(getexecutorname) == "function" then
				hwid = tostring(getexecutorname()) .. "_" .. tostring(LocalPlayer.UserId)
			end
		end)
	end
	if not hwid then
		hwid = tostring(LocalPlayer.UserId) .. "_" .. tostring(game.PlaceId)
	end
	return tostring(hwid)
end

local function ValidateKey(inputKey, keyConfig)
	if not inputKey or inputKey == "" then return false, "Empty key" end
	inputKey = tostring(inputKey):gsub("%s+", "")

	local hwid = GetHWID()
	local bindHWID = keyConfig.BindHWID == true

	local function matchKey(candidate)
		candidate = tostring(candidate):gsub("%s+", "")
		if candidate == inputKey then return true end
		-- support "key:hwid" style entries
		if bindHWID then
			local pure = candidate:match("^(.-):") or candidate
			local bound = candidate:match(":(.+)$")
			if pure == inputKey and (not bound or bound == hwid) then return true end
			if candidate == (inputKey .. ":" .. hwid) then return true end
		end
		return false
	end

	-- local whitelist
	if type(keyConfig.Keys) == "table" then
		for _, k in ipairs(keyConfig.Keys) do
			if matchKey(k) then
				return true, "Local key accepted"
			end
		end
	end

	-- remote GetKey (paste / API)
	if type(keyConfig.GetKey) == "string" and keyConfig.GetKey ~= "" then
		local url = keyConfig.GetKey
		-- optional HWID query param for APIs that expect it
		if bindHWID and not url:find("hwid=") then
			local sep = url:find("?") and "&" or "?"
			url = url .. sep .. "hwid=" .. HttpService:UrlEncode(hwid)
		end
		local ok, body = pcall(function()
			return game:HttpGet(url, true)
		end)
		if ok and body then
			local rawBody = tostring(body)
			local stripped = rawBody:gsub("%s+", "")
			if matchKey(stripped) then return true, "Remote key accepted" end
			local j = ConfigDecode(rawBody)
			if type(j) == "table" then
				if j.key and matchKey(j.key) then return true, "JSON key accepted" end
				if j.valid == true then
					if not j.key or matchKey(j.key) then
						if j.hwid and tostring(j.hwid) ~= hwid and bindHWID then
							return false, "HWID mismatch"
						end
						return true, "JSON valid"
					end
				end
				if type(j.keys) == "table" then
					for _, k in ipairs(j.keys) do
						if matchKey(k) then return true, "JSON list accepted" end
					end
				end
			end
		end
	end

	-- custom Check function (receives key + hwid)
	if type(keyConfig.Check) == "function" then
		local ok, result = pcall(keyConfig.Check, inputKey, hwid)
		if ok and result then return true, "Custom check passed" end
	end

	return false, "Invalid key"
end

local function ShowKeySystem(keyConfig)
	keyConfig = keyConfig or {}
	local resolved = false
	local result = false

	-- try saved key first
	if keyConfig.SaveKey ~= false then
		local saved = LoadSavedKey()
		if saved then
			local ok = ValidateKey(saved, keyConfig)
			if ok then
				return true
			end
		end
	end

	local cleanup = CreateCleanup()
	local gui = Instance.new("ScreenGui")
	gui.Name = "XeniaKeySystem"
	gui.DisplayOrder = 2147483645
	gui.IgnoreGuiInset = true
	ProtectAndParent(gui)
	cleanup:AddInstance(gui)

	local overlay = Instance.new("Frame")
	overlay.BackgroundColor3 = Color3.fromRGB(6, 6, 10)
	overlay.BackgroundTransparency = 0.15
	overlay.BorderSizePixel = 0
	overlay.Size = UDim2.new(1, 0, 1, 0)
	overlay.Parent = gui

	local card = Instance.new("Frame")
	card.BackgroundColor3 = Theme.Background
	card.BorderSizePixel = 0
	card.Size = UDim2.new(0, 340, 0, 220)
	card.Position = UDim2.new(0.5, -170, 0.5, -110)
	card.Parent = overlay

	local cardCorner = Instance.new("UICorner")
	cardCorner.CornerRadius = UDim.new(0, 10)
	cardCorner.Parent = card

	local cardStroke = Instance.new("UIStroke")
	cardStroke.Color = Theme.Border
	cardStroke.Thickness = 1
	cardStroke.Transparency = 0.3
	cardStroke.Parent = card

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, -24, 0, 28)
	title.Position = UDim2.new(0, 12, 0, 12)
	title.Font = Theme.FontBold
	title.TextSize = 18
	title.TextColor3 = Theme.Text
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = keyConfig.Title or "Key System"
	title.Parent = card

	local subtitle = Instance.new("TextLabel")
	subtitle.BackgroundTransparency = 1
	subtitle.Size = UDim2.new(1, -24, 0, 18)
	subtitle.Position = UDim2.new(0, 12, 0, 42)
	subtitle.Font = Theme.Font
	subtitle.TextSize = 12
	subtitle.TextColor3 = Theme.SecondaryText
	subtitle.TextXAlignment = Enum.TextXAlignment.Left
	subtitle.Text = keyConfig.Subtitle or "Enter your key to continue"
	subtitle.Parent = card

	local box = Instance.new("TextBox")
	box.BackgroundColor3 = Theme.Tertiary
	box.BorderSizePixel = 0
	box.Size = UDim2.new(1, -24, 0, 36)
	box.Position = UDim2.new(0, 12, 0, 78)
	box.Font = Theme.Font
	box.TextSize = 14
	box.TextColor3 = Theme.Text
	box.PlaceholderColor3 = Theme.MutedText
	box.PlaceholderText = "Key here..."
	box.Text = ""
	box.ClearTextOnFocus = false
	box.Parent = card

	local boxCorner = Instance.new("UICorner")
	boxCorner.CornerRadius = UDim.new(0, 6)
	boxCorner.Parent = box

	local boxPad = Instance.new("UIPadding")
	boxPad.PaddingLeft = UDim.new(0, 10)
	boxPad.PaddingRight = UDim.new(0, 10)
	boxPad.Parent = box

	local note = Instance.new("TextLabel")
	note.BackgroundTransparency = 1
	note.Size = UDim2.new(1, -24, 0, 16)
	note.Position = UDim2.new(0, 12, 0, 122)
	note.Font = Theme.Font
	note.TextSize = 11
	note.TextColor3 = Theme.MutedText
	note.TextXAlignment = Enum.TextXAlignment.Left
	note.Text = keyConfig.Note or ""
	note.Parent = card

	local status = Instance.new("TextLabel")
	status.BackgroundTransparency = 1
	status.Size = UDim2.new(1, -24, 0, 16)
	status.Position = UDim2.new(0, 12, 0, 142)
	status.Font = Theme.Font
	status.TextSize = 11
	status.TextColor3 = Theme.NotificationError
	status.TextXAlignment = Enum.TextXAlignment.Left
	status.Text = ""
	status.Parent = card

	local submit = Instance.new("TextButton")
	submit.BackgroundColor3 = Theme.Accent
	submit.BorderSizePixel = 0
	submit.Size = UDim2.new(1, -24, 0, 34)
	submit.Position = UDim2.new(0, 12, 1, -48)
	submit.Font = Theme.FontBold
	submit.TextSize = 14
	submit.TextColor3 = Color3.fromRGB(255, 255, 255)
	submit.Text = "Continue"
	submit.AutoButtonColor = false
	submit.Parent = card

	local submitCorner = Instance.new("UICorner")
	submitCorner.CornerRadius = UDim.new(0, 6)
	submitCorner.Parent = submit

	local function trySubmit()
		if resolved then return end
		local key = box.Text
		status.Text = "Checking..."
		status.TextColor3 = Theme.SecondaryText
		task.spawn(function()
			local ok, msg = ValidateKey(key, keyConfig)
			if ok then
				status.Text = "Accepted"
				status.TextColor3 = Theme.NotificationSuccess
				if keyConfig.SaveKey ~= false then SaveSavedKey(key) end
				resolved = true
				result = true
				task.wait(0.4)
				cleanup:Destroy()
			else
				status.Text = msg or "Invalid key"
				status.TextColor3 = Theme.NotificationError
				TweenEngine.Play(card, {
					Position = UDim2.new(0.5, -170 + 6, 0.5, -110),
				}, { Duration = 0.05 })
				task.wait(0.05)
				TweenEngine.Play(card, {
					Position = UDim2.new(0.5, -170 - 6, 0.5, -110),
				}, { Duration = 0.05 })
				task.wait(0.05)
				TweenEngine.Play(card, {
					Position = UDim2.new(0.5, -170, 0.5, -110),
				}, { Duration = 0.05 })
			end
		end)
	end

	cleanup:AddConnection(submit.MouseButton1Click:Connect(trySubmit))
	cleanup:AddConnection(box.FocusLost:Connect(function(enter)
		if enter then trySubmit() end
	end))

	-- block escape / close attempts while open
	local blockConn = UserInputService.InputBegan:Connect(function(input, gpe)
		if gpe then return end
		if input.KeyCode == Enum.KeyCode.Escape then
			-- do nothing — prevent closing
		end
	end)
	cleanup:AddConnection(blockConn)

	-- wait until resolved
	while not resolved do
		task.wait(0.1)
	end
	return result
end

----------------------------------------------------------------
-- COMPONENT HELPERS (simplified but complete)
----------------------------------------------------------------
local TITLE_H = 38
local SIDEBAR_W_DEFAULT = 110

local function GetParentForComponent(tab)
	return tab.Content
end

-- Minimal but solid component set (Toggle, Slider, Button, Dropdown, Label, Section, Keybind, Textbox, Divider)
-- Full implementations kept lean for reliability

local function CreateSection(tab, config)
	config = config or {}
	local parent = GetParentForComponent(tab)
	local frame = Instance.new("Frame")
	frame.Name = "Section_" .. (config.Name or "S")
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.new(1, 0, 0, 28)
	frame.Parent = parent

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, -8, 1, 0)
	label.Position = UDim2.new(0, 4, 0, 0)
	label.Font = Theme.FontBold
	label.TextSize = 13
	label.TextColor3 = Theme.Text
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = config.Name or "Section"
	label.Parent = frame

	local api = { Frame = frame, Name = config.Name }
	function api:RefreshTheme()
		label.TextColor3 = Theme.Text
		label.Font = Theme.FontBold
	end
	table.insert(tab.Sections, api)
	return api
end

local function CreateButton(tab, config)
	config = config or {}
	local parent = GetParentForComponent(tab)
	local frame = Instance.new("TextButton")
	frame.Name = "Button_" .. (config.Name or "B")
	frame.BackgroundColor3 = Theme.Tertiary
	frame.BackgroundTransparency = 0.2
	frame.BorderSizePixel = 0
	frame.Size = UDim2.new(1, 0, 0, Theme.ElementHeight or 34)
	frame.Font = Theme.Font
	frame.TextSize = 13
	frame.TextColor3 = Theme.Text
	frame.Text = config.Name or "Button"
	frame.AutoButtonColor = false
	frame.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, Theme.ButtonCornerRadius or 5)
	corner.Parent = frame

	frame.MouseEnter:Connect(function()
		TweenEngine.Play(frame, { BackgroundTransparency = 0.05 }, { Duration = 0.1 })
	end)
	frame.MouseLeave:Connect(function()
		TweenEngine.Play(frame, { BackgroundTransparency = 0.2 }, { Duration = 0.1 })
	end)
	frame.MouseButton1Click:Connect(function()
		if config.Callback then task.spawn(config.Callback) end
	end)

	local api = { Frame = frame, Name = config.Name, SearchText = config.Name }
	function api:RefreshTheme()
		frame.BackgroundColor3 = Theme.Tertiary
		frame.TextColor3 = Theme.Text
		frame.Font = Theme.Font
	end
	table.insert(tab.Components, api)
	return api
end

local function CreateToggle(tab, config)
	config = config or {}
	local parent = GetParentForComponent(tab)
	local state = config.Default == true

	local frame = Instance.new("Frame")
	frame.Name = "Toggle_" .. (config.Name or "T")
	frame.BackgroundColor3 = Theme.Tertiary
	frame.BackgroundTransparency = 0.35
	frame.BorderSizePixel = 0
	frame.Size = UDim2.new(1, 0, 0, Theme.ElementHeight or 34)
	frame.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, Theme.ButtonCornerRadius or 5)
	corner.Parent = frame

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, -50, 1, 0)
	label.Position = UDim2.new(0, 10, 0, 0)
	label.Font = Theme.Font
	label.TextSize = 13
	label.TextColor3 = Theme.Text
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = config.Name or "Toggle"
	label.Parent = frame

	local track = Instance.new("Frame")
	track.BackgroundColor3 = state and Theme.ToggleOn or Theme.ToggleOff
	track.BorderSizePixel = 0
	track.Size = UDim2.new(0, 36, 0, 18)
	track.Position = UDim2.new(1, -44, 0.5, -9)
	track.Parent = frame

	local trackCorner = Instance.new("UICorner")
	trackCorner.CornerRadius = UDim.new(1, 0)
	trackCorner.Parent = track

	local knob = Instance.new("Frame")
	knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	knob.BorderSizePixel = 0
	knob.Size = UDim2.new(0, 14, 0, 14)
	knob.Position = state and UDim2.new(1, -16, 0.5, -7) or UDim2.new(0, 2, 0.5, -7)
	knob.Parent = track

	local knobCorner = Instance.new("UICorner")
	knobCorner.CornerRadius = UDim.new(1, 0)
	knobCorner.Parent = knob

	local btn = Instance.new("TextButton")
	btn.BackgroundTransparency = 1
	btn.Size = UDim2.new(1, 0, 1, 0)
	btn.Text = ""
	btn.Parent = frame

	local function setState(v, fire)
		state = v and true or false
		TweenEngine.Play(track, { BackgroundColor3 = state and Theme.ToggleOn or Theme.ToggleOff }, { Duration = 0.15 })
		TweenEngine.Play(knob, {
			Position = state and UDim2.new(1, -16, 0.5, -7) or UDim2.new(0, 2, 0.5, -7)
		}, { Duration = 0.15 })
		if fire and config.Callback then task.spawn(config.Callback, state) end
	end

	btn.MouseButton1Click:Connect(function() setState(not state, true) end)

	local api = {
		Frame = frame,
		Name = config.Name,
		SearchText = config.Name,
		Get = function() return state end,
		Set = function(_, v) setState(v, false) end,
	}
	function api:RefreshTheme()
		frame.BackgroundColor3 = Theme.Tertiary
		label.TextColor3 = Theme.Text
		label.Font = Theme.Font
		track.BackgroundColor3 = state and Theme.ToggleOn or Theme.ToggleOff
	end
	table.insert(tab.Components, api)
	return api
end

local function CreateSlider(tab, config)
	config = config or {}
	local min = config.Min or 0
	local max = config.Max or 100
	local value = config.Default or min
	local parent = GetParentForComponent(tab)

	local frame = Instance.new("Frame")
	frame.Name = "Slider_" .. (config.Name or "S")
	frame.BackgroundColor3 = Theme.Tertiary
	frame.BackgroundTransparency = 0.35
	frame.BorderSizePixel = 0
	frame.Size = UDim2.new(1, 0, 0, 48)
	frame.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, Theme.ButtonCornerRadius or 5)
	corner.Parent = frame

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, -60, 0, 18)
	label.Position = UDim2.new(0, 10, 0, 4)
	label.Font = Theme.Font
	label.TextSize = 12
	label.TextColor3 = Theme.Text
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = config.Name or "Slider"
	label.Parent = frame

	local valueLabel = Instance.new("TextLabel")
	valueLabel.BackgroundTransparency = 1
	valueLabel.Size = UDim2.new(0, 50, 0, 18)
	valueLabel.Position = UDim2.new(1, -56, 0, 4)
	valueLabel.Font = Theme.Font
	valueLabel.TextSize = 12
	valueLabel.TextColor3 = Theme.SecondaryText
	valueLabel.TextXAlignment = Enum.TextXAlignment.Right
	valueLabel.Text = tostring(value)
	valueLabel.Parent = frame

	local track = Instance.new("Frame")
	track.BackgroundColor3 = Theme.SliderTrack
	track.BorderSizePixel = 0
	track.Size = UDim2.new(1, -20, 0, 6)
	track.Position = UDim2.new(0, 10, 0, 30)
	track.Parent = frame

	local trackCorner = Instance.new("UICorner")
	trackCorner.CornerRadius = UDim.new(1, 0)
	trackCorner.Parent = track

	local fill = Instance.new("Frame")
	fill.BackgroundColor3 = Theme.SliderFill
	fill.BorderSizePixel = 0
	fill.Size = UDim2.new(math.clamp((value - min) / (max - min), 0, 1), 0, 1, 0)
	fill.Parent = track

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(1, 0)
	fillCorner.Parent = fill

	local function setValue(v, fire)
		value = math.clamp(v, min, max)
		local alpha = (value - min) / (max - min)
		fill.Size = UDim2.new(alpha, 0, 1, 0)
		valueLabel.Text = tostring(math.floor(value * 100 + 0.5) / 100)
		if fire and config.Callback then task.spawn(config.Callback, value) end
	end

	local dragging = false
	track.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			local rel = (input.Position.X - track.AbsolutePosition.X) / track.AbsoluteSize.X
			setValue(min + rel * (max - min), true)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if not dragging then return end
		if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
			local rel = (input.Position.X - track.AbsolutePosition.X) / track.AbsoluteSize.X
			setValue(min + rel * (max - min), true)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)

	local api = {
		Frame = frame,
		Name = config.Name,
		SearchText = config.Name,
		Get = function() return value end,
		Set = function(_, v) setValue(v, false) end,
	}
	function api:RefreshTheme()
		frame.BackgroundColor3 = Theme.Tertiary
		label.TextColor3 = Theme.Text
		valueLabel.TextColor3 = Theme.SecondaryText
		track.BackgroundColor3 = Theme.SliderTrack
		fill.BackgroundColor3 = Theme.SliderFill
	end
	table.insert(tab.Components, api)
	return api
end

local function CreateLabel(tab, config)
	config = config or {}
	local parent = GetParentForComponent(tab)
	local frame = Instance.new("TextLabel")
	frame.Name = "Label_" .. (config.Name or "L")
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.new(1, 0, 0, 22)
	frame.Font = Theme.Font
	frame.TextSize = 12
	frame.TextColor3 = Theme.SecondaryText
	frame.TextXAlignment = Enum.TextXAlignment.Left
	frame.Text = config.Name or config.Text or ""
	frame.Parent = parent

	local api = { Frame = frame, Name = config.Name, SearchText = config.Name }
	function api:RefreshTheme()
		frame.TextColor3 = Theme.SecondaryText
		frame.Font = Theme.Font
	end
	table.insert(tab.Components, api)
	return api
end

local function CreateDropdown(tab, config)
	config = config or {}
	local parent = GetParentForComponent(tab)
	local options = config.Options or {}
	local current = config.Default or (options[1] or "")

	local frame = Instance.new("Frame")
	frame.Name = "Dropdown_" .. (config.Name or "D")
	frame.BackgroundColor3 = Theme.Tertiary
	frame.BackgroundTransparency = 0.35
	frame.BorderSizePixel = 0
	frame.Size = UDim2.new(1, 0, 0, Theme.ElementHeight or 34)
	frame.ClipsDescendants = false
	frame.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, Theme.ButtonCornerRadius or 5)
	corner.Parent = frame

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(0.45, 0, 1, 0)
	label.Position = UDim2.new(0, 10, 0, 0)
	label.Font = Theme.Font
	label.TextSize = 12
	label.TextColor3 = Theme.Text
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = config.Name or "Dropdown"
	label.Parent = frame

	local valueLabel = Instance.new("TextLabel")
	valueLabel.BackgroundTransparency = 1
	valueLabel.Size = UDim2.new(0.45, -10, 1, 0)
	valueLabel.Position = UDim2.new(0.5, 0, 0, 0)
	valueLabel.Font = Theme.Font
	valueLabel.TextSize = 12
	valueLabel.TextColor3 = Theme.SecondaryText
	valueLabel.TextXAlignment = Enum.TextXAlignment.Right
	valueLabel.Text = tostring(current)
	valueLabel.TextTruncate = Enum.TextTruncate.AtEnd
	valueLabel.Parent = frame

	local open = false
	local listFrame

	local function closeList()
		if listFrame then listFrame:Destroy() listFrame = nil end
		open = false
	end

	local function openList()
		if open then closeList() return end
		open = true
		listFrame = Instance.new("Frame")
		listFrame.BackgroundColor3 = Theme.Secondary
		listFrame.BorderSizePixel = 0
		listFrame.Size = UDim2.new(1, 0, 0, math.min(#options * 26 + 8, 160))
		listFrame.Position = UDim2.new(0, 0, 1, 4)
		listFrame.ZIndex = 50
		listFrame.Parent = frame

		local lc = Instance.new("UICorner")
		lc.CornerRadius = UDim.new(0, 6)
		lc.Parent = listFrame

		local scroll = Instance.new("ScrollingFrame")
		scroll.BackgroundTransparency = 1
		scroll.Size = UDim2.new(1, 0, 1, 0)
		scroll.CanvasSize = UDim2.new(0, 0, 0, #options * 26)
		scroll.ScrollBarThickness = 3
		scroll.Parent = listFrame

		local layout = Instance.new("UIListLayout")
		layout.Padding = UDim.new(0, 2)
		layout.Parent = scroll

		for _, opt in ipairs(options) do
			local b = Instance.new("TextButton")
			b.BackgroundColor3 = Theme.Tertiary
			b.BackgroundTransparency = 0.5
			b.BorderSizePixel = 0
			b.Size = UDim2.new(1, -8, 0, 24)
			b.Font = Theme.Font
			b.TextSize = 12
			b.TextColor3 = Theme.Text
			b.Text = tostring(opt)
			b.AutoButtonColor = false
			b.Parent = scroll
			b.MouseButton1Click:Connect(function()
				current = opt
				valueLabel.Text = tostring(opt)
				closeList()
				if config.Callback then task.spawn(config.Callback, opt) end
			end)
		end
	end

	local btn = Instance.new("TextButton")
	btn.BackgroundTransparency = 1
	btn.Size = UDim2.new(1, 0, 1, 0)
	btn.Text = ""
	btn.Parent = frame
	btn.MouseButton1Click:Connect(openList)

	local api = {
		Frame = frame,
		Name = config.Name,
		SearchText = config.Name,
		Get = function() return current end,
		Set = function(_, v) current = v valueLabel.Text = tostring(v) end,
		Close = closeList,
	}
	function api:RefreshTheme()
		frame.BackgroundColor3 = Theme.Tertiary
		label.TextColor3 = Theme.Text
		valueLabel.TextColor3 = Theme.SecondaryText
	end
	table.insert(tab.Components, api)
	return api
end

local function CreateTextbox(tab, config)
	config = config or {}
	local parent = GetParentForComponent(tab)
	local frame = Instance.new("Frame")
	frame.Name = "Textbox_" .. (config.Name or "TB")
	frame.BackgroundColor3 = Theme.Tertiary
	frame.BackgroundTransparency = 0.35
	frame.BorderSizePixel = 0
	frame.Size = UDim2.new(1, 0, 0, Theme.ElementHeight or 34)
	frame.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, Theme.ButtonCornerRadius or 5)
	corner.Parent = frame

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(0.4, 0, 1, 0)
	label.Position = UDim2.new(0, 10, 0, 0)
	label.Font = Theme.Font
	label.TextSize = 12
	label.TextColor3 = Theme.Text
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = config.Name or "Input"
	label.Parent = frame

	local box = Instance.new("TextBox")
	box.BackgroundTransparency = 1
	box.Size = UDim2.new(0.55, -10, 1, 0)
	box.Position = UDim2.new(0.4, 0, 0, 0)
	box.Font = Theme.Font
	box.TextSize = 12
	box.TextColor3 = Theme.Text
	box.PlaceholderColor3 = Theme.MutedText
	box.PlaceholderText = config.Placeholder or "..."
	box.Text = config.Default or ""
	box.TextXAlignment = Enum.TextXAlignment.Right
	box.ClearTextOnFocus = false
	box.Parent = frame

	box.FocusLost:Connect(function(enter)
		if config.Callback then task.spawn(config.Callback, box.Text) end
	end)

	local api = {
		Frame = frame,
		Name = config.Name,
		SearchText = config.Name,
		Get = function() return box.Text end,
		Set = function(_, v) box.Text = tostring(v) end,
	}
	function api:RefreshTheme()
		frame.BackgroundColor3 = Theme.Tertiary
		label.TextColor3 = Theme.Text
		box.TextColor3 = Theme.Text
		box.PlaceholderColor3 = Theme.MutedText
	end
	table.insert(tab.Components, api)
	return api
end

local function CreateKeybind(tab, config)
	config = config or {}
	local parent = GetParentForComponent(tab)
	local current = config.Default or Enum.KeyCode.Unknown
	if typeof(current) == "string" then current = KeyCodeFromName(current) end

	local frame = Instance.new("Frame")
	frame.Name = "Keybind_" .. (config.Name or "K")
	frame.BackgroundColor3 = Theme.Tertiary
	frame.BackgroundTransparency = 0.35
	frame.BorderSizePixel = 0
	frame.Size = UDim2.new(1, 0, 0, Theme.ElementHeight or 34)
	frame.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, Theme.ButtonCornerRadius or 5)
	corner.Parent = frame

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(0.5, 0, 1, 0)
	label.Position = UDim2.new(0, 10, 0, 0)
	label.Font = Theme.Font
	label.TextSize = 12
	label.TextColor3 = Theme.Text
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = config.Name or "Keybind"
	label.Parent = frame

	local keyLabel = Instance.new("TextButton")
	keyLabel.BackgroundColor3 = Theme.Secondary
	keyLabel.BorderSizePixel = 0
	keyLabel.Size = UDim2.new(0, 70, 0, 22)
	keyLabel.Position = UDim2.new(1, -80, 0.5, -11)
	keyLabel.Font = Theme.Font
	keyLabel.TextSize = 11
	keyLabel.TextColor3 = Theme.Text
	keyLabel.Text = current == Enum.KeyCode.Unknown and "None" or current.Name
	keyLabel.AutoButtonColor = false
	keyLabel.Parent = frame

	local kc = Instance.new("UICorner")
	kc.CornerRadius = UDim.new(0, 4)
	kc.Parent = keyLabel

	local listening = false
	keyLabel.MouseButton1Click:Connect(function()
		if listening then return end
		listening = true
		keyLabel.Text = "..."
		local conn
		conn = UserInputService.InputBegan:Connect(function(input, gpe)
			if gpe then return end
			if input.UserInputType == Enum.UserInputType.Keyboard then
				current = input.KeyCode
				keyLabel.Text = current.Name
				listening = false
				conn:Disconnect()
			end
		end)
	end)

	if config.Mode == "Toggle" or config.Callback then
		UserInputService.InputBegan:Connect(function(input, gpe)
			if gpe or listening then return end
			if input.KeyCode == current and config.Callback then
				task.spawn(config.Callback)
			end
		end)
	end

	local api = {
		Frame = frame,
		Name = config.Name,
		SearchText = config.Name,
		Get = function() return current end,
		Set = function(_, k)
			current = typeof(k) == "EnumItem" and k or KeyCodeFromName(k)
			keyLabel.Text = current == Enum.KeyCode.Unknown and "None" or current.Name
		end,
	}
	function api:RefreshTheme()
		frame.BackgroundColor3 = Theme.Tertiary
		label.TextColor3 = Theme.Text
		keyLabel.BackgroundColor3 = Theme.Secondary
		keyLabel.TextColor3 = Theme.Text
	end
	table.insert(tab.Components, api)
	return api
end

local function CreateDivider(tab)
	local parent = GetParentForComponent(tab)
	local frame = Instance.new("Frame")
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.new(1, 0, 0, 10)
	frame.Parent = parent

	local line = Instance.new("Frame")
	line.BackgroundColor3 = Theme.Border
	line.BackgroundTransparency = 0.5
	line.BorderSizePixel = 0
	line.Size = UDim2.new(1, -8, 0, 1)
	line.Position = UDim2.new(0, 4, 0.5, 0)
	line.Parent = frame

	local api = { Frame = frame }
	function api:RefreshTheme() line.BackgroundColor3 = Theme.Border end
	table.insert(tab.Components, api)
	return api
end

local function CreateMultiDropdown(tab, config)
	config = config or {}
	local parent = GetParentForComponent(tab)
	local options = config.Options or {}
	local selected = {}
	if type(config.Default) == "table" then
		for _, v in ipairs(config.Default) do selected[tostring(v)] = true end
	end

	local frame = Instance.new("Frame")
	frame.Name = "MultiDrop_" .. (config.Name or "MD")
	frame.BackgroundColor3 = Theme.Tertiary
	frame.BackgroundTransparency = 0.35
	frame.BorderSizePixel = 0
	frame.Size = UDim2.new(1, 0, 0, Theme.ElementHeight or 34)
	frame.ClipsDescendants = false
	frame.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, Theme.ButtonCornerRadius or 5)
	corner.Parent = frame

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(0.4, 0, 1, 0)
	label.Position = UDim2.new(0, 10, 0, 0)
	label.Font = Theme.Font
	label.TextSize = 12
	label.TextColor3 = Theme.Text
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = config.Name or "Multi"
	label.Parent = frame

	local valueLabel = Instance.new("TextLabel")
	valueLabel.BackgroundTransparency = 1
	valueLabel.Size = UDim2.new(0.55, -10, 1, 0)
	valueLabel.Position = UDim2.new(0.4, 0, 0, 0)
	valueLabel.Font = Theme.Font
	valueLabel.TextSize = 11
	valueLabel.TextColor3 = Theme.SecondaryText
	valueLabel.TextXAlignment = Enum.TextXAlignment.Right
	valueLabel.TextTruncate = Enum.TextTruncate.AtEnd
	valueLabel.Parent = frame

	local function refreshValueText()
		local list = {}
		for k, v in pairs(selected) do if v then table.insert(list, k) end end
		table.sort(list)
		valueLabel.Text = #list == 0 and "None" or table.concat(list, ", ")
	end
	refreshValueText()

	local open = false
	local listFrame

	local function closeList()
		if listFrame then listFrame:Destroy() listFrame = nil end
		open = false
	end

	local function fireCallback()
		local list = {}
		for k, v in pairs(selected) do if v then table.insert(list, k) end end
		if config.Callback then task.spawn(config.Callback, list) end
	end

	local function openList()
		if open then closeList() return end
		open = true
		listFrame = Instance.new("Frame")
		listFrame.BackgroundColor3 = Theme.Secondary
		listFrame.BorderSizePixel = 0
		listFrame.Size = UDim2.new(1, 0, 0, math.min(#options * 26 + 8, 160))
		listFrame.Position = UDim2.new(0, 0, 1, 4)
		listFrame.ZIndex = 50
		listFrame.Parent = frame

		local lc = Instance.new("UICorner")
		lc.CornerRadius = UDim.new(0, 6)
		lc.Parent = listFrame

		local scroll = Instance.new("ScrollingFrame")
		scroll.BackgroundTransparency = 1
		scroll.Size = UDim2.new(1, 0, 1, 0)
		scroll.CanvasSize = UDim2.new(0, 0, 0, #options * 26)
		scroll.ScrollBarThickness = 3
		scroll.Parent = listFrame

		local layout = Instance.new("UIListLayout")
		layout.Padding = UDim.new(0, 2)
		layout.Parent = scroll

		for _, opt in ipairs(options) do
			local key = tostring(opt)
			local b = Instance.new("TextButton")
			b.BackgroundColor3 = selected[key] and Theme.Accent or Theme.Tertiary
			b.BackgroundTransparency = selected[key] and 0.3 or 0.5
			b.BorderSizePixel = 0
			b.Size = UDim2.new(1, -8, 0, 24)
			b.Font = Theme.Font
			b.TextSize = 12
			b.TextColor3 = Theme.Text
			b.Text = (selected[key] and "✓ " or "") .. key
			b.AutoButtonColor = false
			b.Parent = scroll
			b.MouseButton1Click:Connect(function()
				selected[key] = not selected[key]
				b.BackgroundColor3 = selected[key] and Theme.Accent or Theme.Tertiary
				b.BackgroundTransparency = selected[key] and 0.3 or 0.5
				b.Text = (selected[key] and "✓ " or "") .. key
				refreshValueText()
				fireCallback()
			end)
		end
	end

	local btn = Instance.new("TextButton")
	btn.BackgroundTransparency = 1
	btn.Size = UDim2.new(1, 0, 1, 0)
	btn.Text = ""
	btn.Parent = frame
	btn.MouseButton1Click:Connect(openList)

	local api = {
		Frame = frame,
		Name = config.Name,
		SearchText = config.Name,
		Get = function()
			local list = {}
			for k, v in pairs(selected) do if v then table.insert(list, k) end end
			return list
		end,
		Set = function(_, list)
			selected = {}
			if type(list) == "table" then
				for _, v in ipairs(list) do selected[tostring(v)] = true end
			end
			refreshValueText()
		end,
		Close = closeList,
	}
	function api:RefreshTheme()
		frame.BackgroundColor3 = Theme.Tertiary
		label.TextColor3 = Theme.Text
		valueLabel.TextColor3 = Theme.SecondaryText
	end
	table.insert(tab.Components, api)
	return api
end

local function CreateColorPicker(tab, config)
	config = config or {}
	local parent = GetParentForComponent(tab)
	local color = config.Default or Color3.fromRGB(255, 255, 255)
	if typeof(color) ~= "Color3" then color = Color3.fromRGB(255, 255, 255) end

	local frame = Instance.new("Frame")
	frame.Name = "ColorPicker_" .. (config.Name or "CP")
	frame.BackgroundColor3 = Theme.Tertiary
	frame.BackgroundTransparency = 0.35
	frame.BorderSizePixel = 0
	frame.Size = UDim2.new(1, 0, 0, Theme.ElementHeight or 34)
	frame.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, Theme.ButtonCornerRadius or 5)
	corner.Parent = frame

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, -50, 1, 0)
	label.Position = UDim2.new(0, 10, 0, 0)
	label.Font = Theme.Font
	label.TextSize = 12
	label.TextColor3 = Theme.Text
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = config.Name or "Color"
	label.Parent = frame

	local swatch = Instance.new("TextButton")
	swatch.BackgroundColor3 = color
	swatch.BorderSizePixel = 0
	swatch.Size = UDim2.new(0, 28, 0, 20)
	swatch.Position = UDim2.new(1, -38, 0.5, -10)
	swatch.Text = ""
	swatch.AutoButtonColor = false
	swatch.Parent = frame

	local sc = Instance.new("UICorner")
	sc.CornerRadius = UDim.new(0, 4)
	sc.Parent = swatch

	local open = false
	local pickerFrame

	local function closePicker()
		if pickerFrame then pickerFrame:Destroy() pickerFrame = nil end
		open = false
	end

	local function openPicker()
		if open then closePicker() return end
		open = true
		pickerFrame = Instance.new("Frame")
		pickerFrame.BackgroundColor3 = Theme.Secondary
		pickerFrame.BorderSizePixel = 0
		pickerFrame.Size = UDim2.new(0, 160, 0, 120)
		pickerFrame.Position = UDim2.new(1, -160, 1, 4)
		pickerFrame.ZIndex = 60
		pickerFrame.Parent = frame

		local pc = Instance.new("UICorner")
		pc.CornerRadius = UDim.new(0, 6)
		pc.Parent = pickerFrame

		local h, s, v = Color3.toHSV(color)
		local function updateFromHSV()
			color = Color3.fromHSV(h, s, v)
			swatch.BackgroundColor3 = color
			if config.Callback then task.spawn(config.Callback, color) end
		end

		-- simple hue bar + saturation/value grid approximation via 3 sliders
		local function makeSlider(y, labelText, initial, onChange)
			local lab = Instance.new("TextLabel")
			lab.BackgroundTransparency = 1
			lab.Size = UDim2.new(0, 20, 0, 16)
			lab.Position = UDim2.new(0, 6, 0, y)
			lab.Font = Theme.Font
			lab.TextSize = 10
			lab.TextColor3 = Theme.SecondaryText
			lab.Text = labelText
			lab.Parent = pickerFrame

			local track = Instance.new("Frame")
			track.BackgroundColor3 = Theme.SliderTrack
			track.BorderSizePixel = 0
			track.Size = UDim2.new(1, -40, 0, 8)
			track.Position = UDim2.new(0, 28, 0, y + 4)
			track.Parent = pickerFrame
			local tc = Instance.new("UICorner")
			tc.CornerRadius = UDim.new(1, 0)
			tc.Parent = track

			local fill = Instance.new("Frame")
			fill.BackgroundColor3 = Theme.Accent
			fill.BorderSizePixel = 0
			fill.Size = UDim2.new(initial, 0, 1, 0)
			fill.Parent = track
			local fc = Instance.new("UICorner")
			fc.CornerRadius = UDim.new(1, 0)
			fc.Parent = fill

			local dragging = false
			local function setAlpha(a)
				a = math.clamp(a, 0, 1)
				fill.Size = UDim2.new(a, 0, 1, 0)
				onChange(a)
			end
			track.InputBegan:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
					dragging = true
					setAlpha((input.Position.X - track.AbsolutePosition.X) / track.AbsoluteSize.X)
				end
			end)
			UserInputService.InputChanged:Connect(function(input)
				if not dragging then return end
				if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
					setAlpha((input.Position.X - track.AbsolutePosition.X) / track.AbsoluteSize.X)
				end
			end)
			UserInputService.InputEnded:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
					dragging = false
				end
			end)
		end

		makeSlider(10, "H", h, function(a) h = a updateFromHSV() end)
		makeSlider(40, "S", s, function(a) s = a updateFromHSV() end)
		makeSlider(70, "V", v, function(a) v = a updateFromHSV() end)

		local closeBtn = Instance.new("TextButton")
		closeBtn.BackgroundColor3 = Theme.Tertiary
		closeBtn.BorderSizePixel = 0
		closeBtn.Size = UDim2.new(1, -12, 0, 22)
		closeBtn.Position = UDim2.new(0, 6, 1, -28)
		closeBtn.Font = Theme.Font
		closeBtn.TextSize = 11
		closeBtn.TextColor3 = Theme.Text
		closeBtn.Text = "Done"
		closeBtn.Parent = pickerFrame
		local cbc = Instance.new("UICorner")
		cbc.CornerRadius = UDim.new(0, 4)
		cbc.Parent = closeBtn
		closeBtn.MouseButton1Click:Connect(closePicker)
	end

	swatch.MouseButton1Click:Connect(openPicker)

	local api = {
		Frame = frame,
		Name = config.Name,
		SearchText = config.Name,
		Get = function() return color end,
		Set = function(_, c)
			if typeof(c) == "Color3" then
				color = c
				swatch.BackgroundColor3 = color
			end
		end,
		Close = closePicker,
	}
	function api:RefreshTheme()
		frame.BackgroundColor3 = Theme.Tertiary
		label.TextColor3 = Theme.Text
	end
	table.insert(tab.Components, api)
	return api
end

local function CreateParagraph(tab, config)
	config = config or {}
	local parent = GetParentForComponent(tab)
	local frame = Instance.new("Frame")
	frame.Name = "Paragraph_" .. (config.Title or "P")
	frame.BackgroundColor3 = Theme.Tertiary
	frame.BackgroundTransparency = 0.45
	frame.BorderSizePixel = 0
	frame.Size = UDim2.new(1, 0, 0, 0)
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, Theme.ButtonCornerRadius or 5)
	corner.Parent = frame

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 8)
	pad.PaddingBottom = UDim.new(0, 8)
	pad.PaddingLeft = UDim.new(0, 10)
	pad.PaddingRight = UDim.new(0, 10)
	pad.Parent = frame

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, 0, 0, 16)
	title.Font = Theme.FontBold
	title.TextSize = 12
	title.TextColor3 = Theme.Text
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = config.Title or config.Name or ""
	title.Parent = frame

	local body = Instance.new("TextLabel")
	body.BackgroundTransparency = 1
	body.Size = UDim2.new(1, 0, 0, 0)
	body.Position = UDim2.new(0, 0, 0, 18)
	body.AutomaticSize = Enum.AutomaticSize.Y
	body.Font = Theme.Font
	body.TextSize = 11
	body.TextColor3 = Theme.SecondaryText
	body.TextXAlignment = Enum.TextXAlignment.Left
	body.TextYAlignment = Enum.TextYAlignment.Top
	body.TextWrapped = true
	body.Text = config.Content or config.Description or ""
	body.Parent = frame

	local api = {
		Frame = frame,
		Name = config.Title or config.Name,
		SearchText = (config.Title or "") .. " " .. (config.Content or ""),
		SetTitle = function(_, t) title.Text = tostring(t or "") end,
		SetContent = function(_, t) body.Text = tostring(t or "") end,
	}
	function api:RefreshTheme()
		frame.BackgroundColor3 = Theme.Tertiary
		title.TextColor3 = Theme.Text
		title.Font = Theme.FontBold
		body.TextColor3 = Theme.SecondaryText
		body.Font = Theme.Font
	end
	table.insert(tab.Components, api)
	return api
end

----------------------------------------------------------------
-- TAB
----------------------------------------------------------------
local function CreateTab(window, config)
	config = config or {}
	local name = config.Name or "Tab"
	local cleanup = CreateCleanup()

	local content = Instance.new("ScrollingFrame")
	content.Name = "Content_" .. name
	content.BackgroundTransparency = 1
	content.BorderSizePixel = 0
	content.Size = UDim2.new(1, 0, 1, 0)
	content.CanvasSize = UDim2.new(0, 0, 0, 0)
	content.AutomaticCanvasSize = Enum.AutomaticSize.Y
	content.ScrollBarThickness = 3
	content.ScrollBarImageColor3 = Theme.Border
	content.ScrollingDirection = Enum.ScrollingDirection.Y
	content.Visible = false
	content.Parent = window.ContentContainer

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 8)
	pad.PaddingBottom = UDim.new(0, 12)
	pad.PaddingLeft = UDim.new(0, 10)
	pad.PaddingRight = UDim.new(0, 10)
	pad.Parent = content

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 6)
	layout.Parent = content

	local tabBtn = Instance.new("TextButton")
	tabBtn.Name = "TabBtn_" .. name
	tabBtn.BackgroundColor3 = Theme.Secondary
	tabBtn.BackgroundTransparency = 1
	tabBtn.BorderSizePixel = 0
	tabBtn.Size = UDim2.new(1, -8, 0, 28)
	tabBtn.Font = Theme.Font
	tabBtn.TextSize = 12
	tabBtn.TextColor3 = Theme.SecondaryText
	tabBtn.Text = name
	tabBtn.TextXAlignment = Enum.TextXAlignment.Left
	tabBtn.TextTruncate = Enum.TextTruncate.AtEnd
	tabBtn.AutoButtonColor = false
	tabBtn.Parent = window.TabBar

	local btnPad = Instance.new("UIPadding")
	btnPad.PaddingLeft = UDim.new(0, 12)
	btnPad.Parent = tabBtn

	local indicator = Instance.new("Frame")
	indicator.Name = "Indicator"
	indicator.BackgroundColor3 = Theme.Accent
	indicator.BorderSizePixel = 0
	indicator.Size = UDim2.new(0, 2, 0.6, 0)
	indicator.Position = UDim2.new(0, 2, 0.2, 0)
	indicator.Visible = false
	indicator.Parent = tabBtn

	cleanup:AddInstance(content)
	cleanup:AddInstance(tabBtn)

	local tab = {
		Name = name,
		Content = content,
		Button = tabBtn,
		Indicator = indicator,
		Sections = {},
		Components = {},
		Cleanup = cleanup,
		Window = window,
	}

	cleanup:AddConnection(tabBtn.MouseButton1Click:Connect(function()
		window:SelectTab(tab)
	end))

	function tab:SetActive(active)
		if active then
			content.Visible = true
			tabBtn.BackgroundTransparency = 0.25
			tabBtn.TextColor3 = Theme.Text
			indicator.Visible = true
		else
			content.Visible = false
			for _, c in ipairs(tab.Components) do
				if c.Close then pcall(function() c:Close() end) end
			end
			tabBtn.BackgroundTransparency = 1
			tabBtn.TextColor3 = Theme.SecondaryText
			indicator.Visible = false
		end
	end

	function tab:RefreshTheme()
		if cleanup:IsDestroyed() then return end
		content.ScrollBarImageColor3 = Theme.Border
		tabBtn.Font = Theme.Font
		indicator.BackgroundColor3 = Theme.Accent
		if content.Visible then
			tabBtn.BackgroundTransparency = 0.25
			tabBtn.TextColor3 = Theme.Text
			indicator.Visible = true
		else
			tabBtn.BackgroundTransparency = 1
			tabBtn.TextColor3 = Theme.SecondaryText
			indicator.Visible = false
		end
		for _, s in ipairs(tab.Sections) do if s.RefreshTheme then s:RefreshTheme() end end
		for _, c in ipairs(tab.Components) do if c.RefreshTheme then c:RefreshTheme() end end
	end

	function tab:CreateSection(c) return CreateSection(tab, c) end
	function tab:CreateButton(c) return CreateButton(tab, c) end
	function tab:CreateToggle(c) return CreateToggle(tab, c) end
	function tab:CreateSlider(c) return CreateSlider(tab, c) end
	function tab:CreateLabel(c) return CreateLabel(tab, c) end
	function tab:CreateDropdown(c) return CreateDropdown(tab, c) end
	function tab:CreateTextbox(c) return CreateTextbox(tab, c) end
	function tab:CreateKeybind(c) return CreateKeybind(tab, c) end
	function tab:CreateDivider() return CreateDivider(tab) end
	function tab:CreateMultiDropdown(c) return CreateMultiDropdown(tab, c) end
	function tab:CreateColorPicker(c) return CreateColorPicker(tab, c) end
	function tab:CreateParagraph(c) return CreateParagraph(tab, c) end

	function tab:Destroy()
		for _, c in ipairs(tab.Components) do if c.Destroy then c:Destroy() end end
		for _, s in ipairs(tab.Sections) do if s.Destroy then s:Destroy() end end
		cleanup:Destroy()
	end

	return tab
end

----------------------------------------------------------------
-- WINDOW
----------------------------------------------------------------
local function ComputeResponsiveSize(config)
	config = config or {}
	local cam = workspace.CurrentCamera
	local vp = (cam and cam.ViewportSize) or Vector2.new(1280, 720)
	local vw, vh = vp.X, vp.Y
	local isTouch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	local isPortrait = vh > vw

	if config.Width and config.Height then
		return math.clamp(config.Width, 280, vw - 16), math.clamp(config.Height, 180, vh - 16), isTouch, isPortrait
	end

	local w, h
	if isTouch then
		if isPortrait then
			w = math.floor(vw * 0.92)
			h = math.floor(math.clamp(vh * 0.45, 240, 360))
		else
			w = math.floor(math.clamp(vw * 0.55, 400, 600))
			h = math.floor(math.clamp(vh * 0.7, 220, 340))
		end
	else
		w = config.Width or 520
		h = config.Height or 360
		w = math.clamp(w, 400, math.min(700, vw - 40))
		h = math.clamp(h, 260, math.min(500, vh - 40))
	end
	return math.floor(w), math.floor(h), isTouch, isPortrait
end

local Windows = {}
local NotifManager = NotificationManager.new()

local function CreateWindow(library, config)
	config = config or {}
	local cleanup = CreateCleanup()
	local width, height, isTouch = ComputeResponsiveSize(config)
	local minimized = false
	local tabs = {}
	local activeTab = nil

	local gui = Instance.new("ScreenGui")
	gui.Name = "XeniaUI_" .. (config.Title or "Window")
	gui.DisplayOrder = 50
	gui.IgnoreGuiInset = true
	ProtectAndParent(gui)

	local root = Instance.new("Frame")
	root.Name = "Root"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromOffset(width, height)
	root.Position = UDim2.new(0.5, -width / 2, 0.5, -height / 2)
	root.Parent = gui

	local main = Instance.new("Frame")
	main.Name = "Main"
	main.BackgroundColor3 = Theme.Background
	main.BackgroundTransparency = 0.02
	main.BorderSizePixel = 0
	main.Size = UDim2.new(1, 0, 1, 0)
	main.ClipsDescendants = true
	main.Parent = root

	local mainCorner = Instance.new("UICorner")
	mainCorner.CornerRadius = UDim.new(0, Theme.WindowCornerRadius or 8)
	mainCorner.Parent = main

	local mainStroke = Instance.new("UIStroke")
	mainStroke.Color = Theme.Border
	mainStroke.Thickness = 1
	mainStroke.Transparency = 0.4
	mainStroke.Parent = main

	local titleBar = Instance.new("Frame")
	titleBar.Name = "TitleBar"
	titleBar.BackgroundColor3 = Theme.Secondary
	titleBar.BackgroundTransparency = 0.1
	titleBar.BorderSizePixel = 0
	titleBar.Size = UDim2.new(1, 0, 0, TITLE_H)
	titleBar.ZIndex = 3
	titleBar.Parent = main

	local titleLabel = Instance.new("TextLabel")
	titleLabel.BackgroundTransparency = 1
	titleLabel.Size = UDim2.new(1, -90, 0, 16)
	titleLabel.Position = UDim2.new(0, 12, 0, 4)
	titleLabel.Font = Theme.FontBold
	titleLabel.TextSize = 13
	titleLabel.TextColor3 = Theme.Text
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.Text = config.Title or "Xenia"
	titleLabel.Parent = titleBar

	local subtitle = Instance.new("TextLabel")
	subtitle.BackgroundTransparency = 1
	subtitle.Size = UDim2.new(1, -90, 0, 12)
	subtitle.Position = UDim2.new(0, 12, 0, 20)
	subtitle.Font = Theme.Font
	subtitle.TextSize = 10
	subtitle.TextColor3 = Theme.SecondaryText
	subtitle.TextXAlignment = Enum.TextXAlignment.Left
	subtitle.Text = config.Subtitle or ""
	subtitle.Parent = titleBar

	local closeBtn = Instance.new("TextButton")
	closeBtn.BackgroundTransparency = 1
	closeBtn.Size = UDim2.new(0, 28, 0, 28)
	closeBtn.Position = UDim2.new(1, -32, 0.5, -14)
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.TextSize = 16
	closeBtn.TextColor3 = Theme.SecondaryText
	closeBtn.Text = "×"
	closeBtn.ZIndex = 10
	closeBtn.Parent = titleBar

	local minBtn = Instance.new("TextButton")
	minBtn.BackgroundTransparency = 1
	minBtn.Size = UDim2.new(0, 28, 0, 28)
	minBtn.Position = UDim2.new(1, -58, 0.5, -14)
	minBtn.Font = Enum.Font.GothamBold
	minBtn.TextSize = 14
	minBtn.TextColor3 = Theme.SecondaryText
	minBtn.Text = "−"
	minBtn.ZIndex = 10
	minBtn.Parent = titleBar

	local body = Instance.new("Frame")
	body.Name = "Body"
	body.BackgroundTransparency = 1
	body.Size = UDim2.new(1, 0, 1, -TITLE_H)
	body.Position = UDim2.new(0, 0, 0, TITLE_H)
	body.ClipsDescendants = true
	body.Parent = main

	local SIDEBAR_W = SIDEBAR_W_DEFAULT
	if isTouch and width < 420 then SIDEBAR_W = 90 end

	local sidebar = Instance.new("Frame")
	sidebar.Name = "Sidebar"
	sidebar.BackgroundColor3 = Theme.Secondary
	sidebar.BackgroundTransparency = 0.3
	sidebar.BorderSizePixel = 0
	sidebar.Size = UDim2.new(0, SIDEBAR_W, 1, 0)
	sidebar.Parent = body

	local searchBox = Instance.new("TextBox")
	searchBox.Name = "Search"
	searchBox.BackgroundColor3 = Theme.Tertiary
	searchBox.BackgroundTransparency = 0.25
	searchBox.BorderSizePixel = 0
	searchBox.Size = UDim2.new(1, -8, 0, 24)
	searchBox.Position = UDim2.new(0, 4, 0, 6)
	searchBox.Font = Theme.Font
	searchBox.TextSize = 11
	searchBox.TextColor3 = Theme.Text
	searchBox.PlaceholderColor3 = Theme.MutedText
	searchBox.PlaceholderText = "Search"
	searchBox.Text = ""
	searchBox.ClearTextOnFocus = false
	searchBox.Parent = sidebar

	local searchCorner = Instance.new("UICorner")
	searchCorner.CornerRadius = UDim.new(0, 4)
	searchCorner.Parent = searchBox

	local tabBar = Instance.new("ScrollingFrame")
	tabBar.Name = "TabBar"
	tabBar.BackgroundTransparency = 1
	tabBar.BorderSizePixel = 0
	tabBar.Size = UDim2.new(1, 0, 1, -36)
	tabBar.Position = UDim2.new(0, 0, 0, 34)
	tabBar.CanvasSize = UDim2.new(0, 0, 0, 0)
	tabBar.AutomaticCanvasSize = Enum.AutomaticSize.Y
	tabBar.ScrollBarThickness = 0
	tabBar.Parent = sidebar

	local tabLayout = Instance.new("UIListLayout")
	tabLayout.FillDirection = Enum.FillDirection.Vertical
	tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tabLayout.Padding = UDim.new(0, 3)
	tabLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	tabLayout.Parent = tabBar

	local contentContainer = Instance.new("Frame")
	contentContainer.Name = "ContentContainer"
	contentContainer.BackgroundTransparency = 1
	contentContainer.Size = UDim2.new(1, -SIDEBAR_W, 1, 0)
	contentContainer.Position = UDim2.new(0, SIDEBAR_W, 0, 0)
	contentContainer.ClipsDescendants = true
	contentContainer.Parent = body

	local window = {
		Gui = gui,
		Root = root,
		Main = main,
		TitleBar = titleBar,
		Body = body,
		Sidebar = sidebar,
		TabBar = tabBar,
		ContentContainer = contentContainer,
		SearchBox = searchBox,
		Tabs = tabs,
		Width = width,
		Height = height,
		Cleanup = cleanup,
	}

	-- search filter
	local function filterTabs()
		local q = string.lower((searchBox.Text or ""):gsub("^%s+", ""):gsub("%s+$", ""))
		for _, tab in ipairs(tabs) do
			local btn = tab.Button
			if btn then
				local name = string.lower(tostring(tab.Name or ""))
				btn.Visible = (q == "") or (string.find(name, q, 1, true) ~= nil)
			end
			for _, component in ipairs(tab.Components) do
				local f = component and component.Frame
				if f then
					local hay = string.lower(tostring(component.SearchText or component.Name or ""))
					f.Visible = (q == "") or (string.find(hay, q, 1, true) ~= nil)
				end
			end
		end
	end
	cleanup:AddConnection(searchBox:GetPropertyChangedSignal("Text"):Connect(filterTabs))

	local drag = MakeDraggable(titleBar, root)
	cleanup:AddCallback(function() drag:Destroy() end)

	cleanup:AddConnection(closeBtn.MouseButton1Click:Connect(function() window:Close() end))
	cleanup:AddConnection(minBtn.MouseButton1Click:Connect(function() window:ToggleMinimize() end))

	-- open anim
	root.Size = UDim2.fromOffset(0, 0)
	main.BackgroundTransparency = 1
	TweenEngine.Play(root, { Size = UDim2.fromOffset(width, height) }, { Duration = 0.35, Easing = "BackOut" })
	TweenEngine.Play(main, { BackgroundTransparency = 0.02 }, { Duration = 0.28, Easing = "QuadOut" })

	cleanup:AddInstance(gui)

	local function refreshWindowTheme()
		if cleanup:IsDestroyed() then return end
		main.BackgroundColor3 = Theme.Background
		mainStroke.Color = Theme.Border
		titleBar.BackgroundColor3 = Theme.Secondary
		titleLabel.TextColor3 = Theme.Text
		titleLabel.Font = Theme.FontBold
		subtitle.TextColor3 = Theme.SecondaryText
		closeBtn.TextColor3 = Theme.SecondaryText
		minBtn.TextColor3 = Theme.SecondaryText
		sidebar.BackgroundColor3 = Theme.Secondary
		searchBox.BackgroundColor3 = Theme.Tertiary
		searchBox.TextColor3 = Theme.Text
		searchBox.PlaceholderColor3 = Theme.MutedText
		for _, tab in ipairs(tabs) do if tab.RefreshTheme then tab:RefreshTheme() end end
	end
	cleanup:AddCallback(OnThemeChange(refreshWindowTheme))

	function window:CreateTab(c)
		local tab = CreateTab(window, c)
		table.insert(tabs, tab)
		if not activeTab then window:SelectTab(tab) end
		return tab
	end

	function window:SelectTab(tab)
		if activeTab == tab then return end
		if activeTab then activeTab:SetActive(false) end
		activeTab = tab
		tab:SetActive(true)
	end

	function window:ToggleMinimize()
		minimized = not minimized
		if minimized then
			body.Visible = false
			TweenEngine.Play(root, { Size = UDim2.new(0, width, 0, TITLE_H) }, { Duration = 0.25, Easing = "QuadOut" })
		else
			TweenEngine.Play(root, { Size = UDim2.new(0, width, 0, height) }, {
				Duration = 0.3, Easing = "BackOut",
				OnComplete = function() body.Visible = true end,
			})
		end
	end

	function window:Close()
		TweenEngine.Play(root, { Size = UDim2.new(0, 0, 0, 0) }, {
			Duration = 0.25, Easing = "QuadIn",
			OnComplete = function() window:Destroy() end,
		})
	end

	function window:Destroy()
		pcall(function() TweenEngine.CancelOnObject(root) end)
		for _, tab in ipairs(tabs) do pcall(function() if tab.Destroy then tab:Destroy() end end) end
		table.clear(tabs)
		pcall(function() cleanup:Destroy() end)
		pcall(function() if gui then gui:Destroy() end end)
		local idx = table.find(Windows, window)
		if idx then table.remove(Windows, idx) end
	end

	-- Settings tab
	task.defer(function()
		local settingsTab = window:CreateTab({ Name = "Settings" })
		settingsTab:CreateSection({ Name = "Appearance" })
		local themeNames = {}
		for k in pairs(ThemePresets) do table.insert(themeNames, k) end
		table.sort(themeNames)
		settingsTab:CreateDropdown({
			Name = "Theme",
			Options = themeNames,
			Default = Settings.Theme or "Dark",
			Callback = function(v)
				Settings.Theme = v
				ApplyThemePreset(v)
				Library:Notify({ Title = "Theme", Description = "Applied " .. v, Duration = 2, Type = "Success" })
			end,
		})
		settingsTab:CreateSection({ Name = "Controls" })
		settingsTab:CreateKeybind({
			Name = "Toggle UI",
			Default = KeyCodeFromName(Settings.ToggleUIKey or "RightControl"),
			Mode = "Toggle",
			Callback = function()
				if window.Gui then window.Gui.Enabled = not window.Gui.Enabled end
			end,
		})
		settingsTab:CreateButton({
			Name = "Save Settings",
			Callback = function()
				local ok = ConfigSave()
				Library:Notify({
					Title = ok and "Saved" or "Failed",
					Description = ok and "Settings written" or "writefile unavailable",
					Duration = 2,
					Type = ok and "Success" or "Error",
				})
			end,
		})
	end)

	return window
end

----------------------------------------------------------------
-- LIBRARY
----------------------------------------------------------------
local Library = {}
Library.__index = Library
Library.ThemePresets = ThemePresets
Library.Settings = Settings
Library.Animation = TweenEngine

local InitDone = false
local KeyPassed = false

local function KillPrevious()
	pcall(function()
		local snap = table.clone(Windows)
		table.clear(Windows)
		for _, win in ipairs(snap) do pcall(function() if win.Destroy then win:Destroy() end end) end
		if NotifManager then
			pcall(function() NotifManager:Clear() end)
			pcall(function() if NotifManager.Gui then NotifManager.Gui:Destroy() end end)
			NotifManager = NotificationManager.new()
		end
		pcall(function() TweenEngine.CancelAll() end)
		local parents = {}
		pcall(function() table.insert(parents, game:GetService("CoreGui")) end)
		pcall(function() if type(gethui) == "function" then table.insert(parents, gethui()) end end)
		pcall(function()
			local lp = Players.LocalPlayer
			if lp then table.insert(parents, lp:FindFirstChildOfClass("PlayerGui")) end
		end)
		for _, parent in ipairs(parents) do
			if parent then
				for _, child in ipairs(parent:GetChildren()) do
					if child:IsA("ScreenGui") and (string.find(child.Name, "Xenia") or string.find(child.Name, "xenia") or string.find(child.Name, "Veyra") or string.find(child.Name, "veyra")) then
						pcall(function() child:Destroy() end)
					end
				end
			end
		end
	end)
end

function Library:Init(options)
	options = options or {}
	KillPrevious()
	InitDone = true
	KeyPassed = false

	if type(options.Theme) == "string" then
		ApplyThemePreset(options.Theme)
		Settings.Theme = options.Theme
	elseif type(options.Theme) == "table" then
		SetTheme(options.Theme)
	end

	if options.NotifDraggable ~= nil then
		NotifManager.Draggable = options.NotifDraggable and true or false
	end

	-- Intro
	if options.Intro == true then
		local introDone = false
		PlayIntro(options.IntroConfig or {
			Title = options.Title or "Xenia",
			Subtitle = options.Subtitle or "Initializing...",
			Duration = (options.IntroConfig and options.IntroConfig.Duration) or 2.2,
		})
		-- wait roughly for intro
		task.wait((options.IntroConfig and options.IntroConfig.Duration) or 2.2)
	end

	-- Key system (blocks until passed)
	if options.KeySystem and options.KeySystem.Enabled then
		local passed = ShowKeySystem(options.KeySystem)
		if not passed then
			warn("[Xenia] Key system failed / closed")
			return nil
		end
		KeyPassed = true
	else
		KeyPassed = true
	end

	return Library
end

function Library:CreateWindow(config)
	if not InitDone then self:Init() end
	if not KeyPassed then
		warn("[Xenia] Key system not passed — cannot create window")
		return nil
	end
	local win = CreateWindow(Library, config)
	table.insert(Windows, win)
	return win
end

function Library:Notify(a, b, c)
	if type(a) == "table" then
		return NotifManager:Notify(a)
	end
	return NotifManager:Notify({
		Title = tostring(a or "Notice"),
		Description = tostring(b or ""),
		Duration = tonumber(c) or 3,
		Type = "Info",
	})
end

function Library:SetTheme(t) SetTheme(t) end
function Library:ApplyTheme(name) return ApplyThemePreset(name) end
function Library:GetTheme() return GetTheme() end
function Library:GetSettings() return Settings end
function Library:SaveSettings() return ConfigSave() end
function Library:LoadSettings() return ConfigLoad() end
function Library:PlayIntro(config) return PlayIntro(config) end
function Library:IsInit() return InitDone end

function Library:Destroy()
	local snap = table.clone(Windows)
	table.clear(Windows)
	for _, win in ipairs(snap) do pcall(function() win:Destroy() end) end
	pcall(function() NotifManager:Destroy() end)
	NotifManager = NotificationManager.new()
	TweenEngine.CancelAll()
	table.clear(ThemeListeners)
	InitDone = false
	KeyPassed = false
end

-- Simple API (Orion/Kavo style)
local function wrapTab(tab)
	local t = tab
	function t:Section(name) return self:CreateSection({ Name = name }) end
	function t:Toggle(name, default, callback)
		if type(default) == "function" then callback = default default = false end
		return self:CreateToggle({ Name = name, Default = default == true, Callback = callback })
	end
	function t:Slider(name, min, max, default, callback)
		if type(min) == "function" then callback = min min, max, default = 0, 100, 0
		elseif type(default) == "function" then callback = default default = min end
		return self:CreateSlider({ Name = name, Min = min or 0, Max = max or 100, Default = default or min or 0, Callback = callback })
	end
	function t:Button(name, callback)
		return self:CreateButton({ Name = name, Callback = callback })
	end
	function t:Drop(name, options, default, callback)
		if type(options) == "function" then callback = options options, default = {}, nil
		elseif type(default) == "function" then callback = default default = options and options[1] end
		return self:CreateDropdown({ Name = name, Options = options or {}, Default = default or (options and options[1]) or "", Callback = callback })
	end
	function t:Key(name, key, callback)
		if type(key) == "function" then callback = key key = Enum.KeyCode.Unknown end
		return self:CreateKeybind({ Name = name, Default = key or Enum.KeyCode.Unknown, Callback = callback })
	end
	function t:Input(name, placeholder, callback)
		if type(placeholder) == "function" then callback = placeholder placeholder = "" end
		return self:CreateTextbox({ Name = name, Placeholder = placeholder or "", Callback = callback })
	end
	function t:Label(name) return self:CreateLabel({ Name = name }) end
	function t:Line() return self:CreateDivider() end
	function t:MultiDrop(name, options, default, callback)
		return self:CreateMultiDropdown({
			Name = name,
			Options = options or {},
			Default = default or {},
			Callback = callback,
		})
	end
	function t:Color(name, default, callback)
		return self:CreateColorPicker({ Name = name, Default = default, Callback = callback })
	end
	function t:Paragraph(title, content)
		return self:CreateParagraph({ Title = title, Content = content })
	end
	return t
end

local function wrapWindow(win)
	if not win then return nil end
	local w = win
	function w:Tab(name) return wrapTab(self:CreateTab({ Name = name or "Tab" })) end
	return w
end

function Library:New(title, subtitle)
	if not InitDone then self:Init() end
	local config
	if type(title) == "table" then config = title
	else config = { Title = title or "Xenia", Subtitle = subtitle or "" } end
	return wrapWindow(self:CreateWindow(config))
end

local _CreateWindow = Library.CreateWindow
function Library:CreateWindow(config)
	return wrapWindow(_CreateWindow(self, config))
end

return Library
