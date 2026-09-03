--[[
	VeyraUI v4 — Compact Responsive Framework
	Your custom TweenEngine + Ethereal separators preserved.

	Additive upgrades only:
	• Compact near-square window (default 360×360, ~70% scale)
	• Thin white right-side outline accent
	• Scrollable tab bar when many tabs
	• Reliable content scrolling (PC + mobile)
	• Optional top-bar actions (Window:AddAction)
	• Optional intro via Library:Init({ Intro = true, IntroConfig = {...} })
	• UISizeConstraint for multi-resolution
	• Slightly tighter element spacing for compact layout

	Core systems unchanged:
	• Full custom TweenEngine (scheduler, all easings, Spring, Shake, CancelOnObject)
	• Ethereal separators
	• Signal / Cleanup / ProtectAndParent
	• Slider & drag: UIS hooks only while active
	• Notification hard cap, typewriter, audio, icon, Duration=0 manual close
	• Live theme refresh + presets

	Usage:
		local Library = loadstring(...)()

		-- Optional one-time init (boolean flags — skip entirely if unused)
		Library:Init({
			Intro = false,  -- set true to show intro
			IntroConfig = { Title = "Veyra", Subtitle = "Loading...", Duration = 1.5 },
		})

		local Window = Library:CreateWindow({
			Title = "My UI",
			Subtitle = "v4",
			Width = 360,
			Height = 360,
		})

		-- Optional action buttons (only appear when added)
		Window:AddAction({ Name = "Discord", Callback = function() end })

		local Tab = Window:CreateTab({ Name = "Main" })
		Tab:CreateSection({ Name = "Section 1" })
		Tab:CreateButton({ Name = "Test", Callback = function() end })

		Library:Notify({
			Title = "Ready",
			Description = "Loaded.",
			Duration = 5,
			Type = "Success",
			Typewriter = true,
		})
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")
local SoundService = game:GetService("SoundService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local HttpService = game:GetService("HttpService")
local LocalizationService = game:GetService("LocalizationService")

----------------------------------------------------------------
-- CONFIG (persist with exploit writefile / readfile)
----------------------------------------------------------------
local CONFIG_FOLDER = "VeyraUI"
local CONFIG_FILE = "VeyraUI/settings.json"

local DefaultSettings = {
	Theme = "Dark",
	ToggleUIKey = "X", -- KeyCode name
	UIVisible = true,
}

local Settings = {}
for k, v in pairs(DefaultSettings) do
	Settings[k] = v
end

local function ConfigEncode(tbl)
	local ok, encoded = pcall(function()
		return HttpService:JSONEncode(tbl)
	end)
	if ok and encoded then return encoded end
	-- fallback minimal encoder
	local parts = {}
	for k, v in pairs(tbl) do
		local vs = tostring(v)
		if type(v) == "string" then
			vs = '"' .. (string.gsub(vs, '"', '\\"')) .. '"'
		elseif type(v) == "boolean" then
			vs = v and "true" or "false"
		end
		table.insert(parts, '"' .. tostring(k) .. '":' .. vs)
	end
	return "{" .. table.concat(parts, ",") .. "}"
end

local function ConfigDecode(str)
	if type(str) ~= "string" or #str == 0 then return nil end
	local ok, decoded = pcall(function()
		return HttpService:JSONDecode(str)
	end)
	if ok and type(decoded) == "table" then return decoded end
	return nil
end

local function ConfigLoad()
	local raw = nil
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
	for k, v in pairs(data) do
		Settings[k] = v
	end
	return true
end

local function ConfigSave()
	local payload = ConfigEncode(Settings)
	local ok = false
	pcall(function()
		if type(makefolder) == "function" then
			pcall(makefolder, CONFIG_FOLDER)
		end
		if type(writefile) == "function" then
			writefile(CONFIG_FILE, payload)
			ok = true
		end
	end)
	return ok
end

-- Load once at library start
pcall(ConfigLoad)

local function KeyCodeFromName(name)
	if typeof(name) == "EnumItem" then return name end
	if type(name) ~= "string" or name == "" or name == "None" then
		return Enum.KeyCode.Unknown
	end
	local ok, kc = pcall(function()
		return Enum.KeyCode[name]
	end)
	if ok and kc then return kc end
	return Enum.KeyCode.Unknown
end

----------------------------------------------------------------
-- SIGNAL (Changed events for components)
----------------------------------------------------------------
local function CreateSignal()
	local handlers = {}
	local destroyed = false
	local api = {}

	function api:Connect(fn)
		if destroyed or type(fn) ~= "function" then
			return { Disconnect = function() end, Connected = false }
		end
		local conn = { _fn = fn, Connected = true }
		function conn:Disconnect()
			if not self.Connected then return end
			self.Connected = false
			for i = #handlers, 1, -1 do
				if handlers[i] == self then
					table.remove(handlers, i)
					break
				end
			end
		end
		table.insert(handlers, conn)
		return conn
	end

	function api:Once(fn)
		local conn
		conn = api:Connect(function(...)
			conn:Disconnect()
			fn(...)
		end)
		return conn
	end

	function api:Fire(...)
		if destroyed then return end
		local snap = table.clone(handlers)
		for _, c in ipairs(snap) do
			if c.Connected then
				task.spawn(c._fn, ...)
			end
		end
	end

	function api:DisconnectAll()
		for _, c in ipairs(handlers) do
			c.Connected = false
		end
		table.clear(handlers)
	end

	function api:Destroy()
		if destroyed then return end
		destroyed = true
		api:DisconnectAll()
	end

	function api:IsDestroyed()
		return destroyed
	end

	return api
end

-- Executor-friendly GUI parenting (gethui / syn.protect_gui / CoreGui fallback)
local function ProtectAndParent(sg)
	sg.ResetOnSpawn = false
	pcall(function()
		if type(syn) == "table" and type(syn.protect_gui) == "function" then
			syn.protect_gui(sg)
		end
	end)
	local ok = pcall(function()
		sg.Parent = game:GetService("CoreGui")
	end)
	if ok and sg.Parent then return end
	ok = pcall(function()
		if type(gethui) == "function" then
			sg.Parent = gethui()
		end
	end)
	if ok and sg.Parent then return end
	sg.Parent = PlayerGui
end

----------------------------------------------------------------
-- THEME
----------------------------------------------------------------
local Theme = {
	Background = Color3.fromRGB(12, 12, 14),
	Secondary = Color3.fromRGB(18, 18, 22),
	Tertiary = Color3.fromRGB(24, 24, 28),
	Hover = Color3.fromRGB(28, 28, 34),
	Text = Color3.fromRGB(240, 240, 245),
	SecondaryText = Color3.fromRGB(150, 150, 160),
	MutedText = Color3.fromRGB(100, 100, 110),
	Accent = Color3.fromRGB(255, 255, 255),
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
	Font = Enum.Font.Gotham,
	FontBold = Enum.Font.GothamSemibold,
	FontMono = Enum.Font.Code,
	CornerRadius = 8,  -- soft rounded corners
	ElementHeight = 32,
	AnimationSpeed = 0.35,
	HoverSpeed = 0.15,
}

-- Built-in presets (use Library:ApplyTheme("Light") or SetTheme(ThemePresets.Light))
local ThemePresets = {
	Dark = {
		Background = Color3.fromRGB(12, 12, 14),
		Secondary = Color3.fromRGB(18, 18, 22),
		Tertiary = Color3.fromRGB(24, 24, 28),
		Hover = Color3.fromRGB(28, 28, 34),
		Text = Color3.fromRGB(240, 240, 245),
		SecondaryText = Color3.fromRGB(150, 150, 160),
		MutedText = Color3.fromRGB(100, 100, 110),
		Accent = Color3.fromRGB(255, 255, 255),
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
}

local ThemeListeners = {}

local function GetTheme()
	return Theme
end

local function SetTheme(t)
	if type(t) ~= "table" then return end
	for k, v in pairs(t) do
		Theme[k] = v
	end
	for _, fn in ipairs(ThemeListeners) do
		task.spawn(fn)
	end
end

local function ApplyThemePreset(name)
	local preset = ThemePresets[name]
	if not preset then
		warn("[VeyraUI] Unknown theme preset:", tostring(name))
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
		if destroyed then
			if c and c.Connected then c:Disconnect() end
			return
		end
		table.insert(connections, c)
	end

	function api:AddInstance(i)
		if destroyed then
			if i then i:Destroy() end
			return
		end
		table.insert(instances, i)
	end

	function api:AddTask(t)
		if destroyed then
			pcall(task.cancel, t)
			return
		end
		table.insert(tasks, t)
	end

	function api:AddCallback(fn)
		if destroyed then return end
		table.insert(callbacks, fn)
	end

	function api:Destroy()
		if destroyed then return end
		destroyed = true
		-- Cancel any running animations on tracked instances first
		for _, i in ipairs(instances) do
			if i then
				pcall(function() TweenEngine.CancelOnObject(i) end)
			end
		end
		for _, c in ipairs(connections) do
			if c and c.Connected then pcall(function() c:Disconnect() end) end
		end
		for _, i in ipairs(instances) do
			if i and i.Parent then pcall(function() i:Destroy() end) end
		end
		for _, t in ipairs(tasks) do
			pcall(task.cancel, t)
		end
		for _, fn in ipairs(callbacks) do
			pcall(fn)
		end
		table.clear(connections)
		table.clear(instances)
		table.clear(tasks)
		table.clear(callbacks)
	end

	function api:IsDestroyed()
		return destroyed
	end

	return api
end

----------------------------------------------------------------
-- EASING
----------------------------------------------------------------
local Easing = {}

function Easing.Linear(t) return t end
function Easing.QuadIn(t) return t * t end
function Easing.QuadOut(t) return t * (2 - t) end
function Easing.QuadInOut(t)
	if t < 0.5 then return 2 * t * t end
	return -1 + (4 - 2 * t) * t
end
function Easing.CubicIn(t) return t * t * t end
function Easing.CubicOut(t)
	local t1 = t - 1
	return t1 * t1 * t1 + 1
end
function Easing.CubicInOut(t)
	if t < 0.5 then return 4 * t * t * t end
	local t1 = 2 * t - 2
	return 0.5 * t1 * t1 * t1 + 1
end
function Easing.QuartIn(t) return t * t * t * t end
function Easing.QuartOut(t)
	local t1 = t - 1
	return 1 - t1 * t1 * t1 * t1
end
function Easing.QuartInOut(t)
	if t < 0.5 then return 8 * t * t * t * t end
	local t1 = t - 1
	return 1 - 8 * t1 * t1 * t1 * t1
end
function Easing.QuintIn(t) return t * t * t * t * t end
function Easing.QuintOut(t)
	local t1 = t - 1
	return 1 + t1 * t1 * t1 * t1 * t1
end
function Easing.QuintInOut(t)
	if t < 0.5 then return 16 * t * t * t * t * t end
	local t1 = 2 * t - 2
	return 0.5 * t1 * t1 * t1 * t1 * t1 + 1
end
function Easing.SineIn(t) return 1 - math.cos(t * math.pi / 2) end
function Easing.SineOut(t) return math.sin(t * math.pi / 2) end
function Easing.SineInOut(t) return -0.5 * (math.cos(math.pi * t) - 1) end
function Easing.CircularIn(t) return 1 - math.sqrt(1 - t * t) end
function Easing.CircularOut(t) return math.sqrt(1 - (t - 1) * (t - 1)) end
function Easing.CircularInOut(t)
	if t < 0.5 then return 0.5 * (1 - math.sqrt(1 - 4 * t * t)) end
	return 0.5 * (math.sqrt(1 - (2 * t - 2) * (2 * t - 2)) + 1)
end
function Easing.ExpoIn(t)
	if t == 0 then return 0 end
	return math.pow(2, 10 * (t - 1))
end
function Easing.ExpoOut(t)
	if t == 1 then return 1 end
	return 1 - math.pow(2, -10 * t)
end
function Easing.ExpoInOut(t)
	if t == 0 then return 0 end
	if t == 1 then return 1 end
	if t < 0.5 then return 0.5 * math.pow(2, 20 * t - 10) end
	return 1 - 0.5 * math.pow(2, -20 * t + 10)
end
function Easing.BackIn(t)
	local s = 1.70158
	return t * t * ((s + 1) * t - s)
end
function Easing.BackOut(t)
	local s = 1.70158
	local t1 = t - 1
	return t1 * t1 * ((s + 1) * t1 + s) + 1
end
function Easing.BackInOut(t)
	local s = 1.70158 * 1.525
	if t < 0.5 then
		return 0.5 * (t * 2) * (t * 2) * ((s + 1) * (t * 2) - s)
	end
	local t1 = t * 2 - 2
	return 0.5 * (t1 * t1 * ((s + 1) * t1 + s) + 2)
end
function Easing.ElasticIn(t)
	if t == 0 or t == 1 then return t end
	return -math.pow(2, 10 * (t - 1)) * math.sin((t - 1.1) * 5 * math.pi)
end
function Easing.ElasticOut(t)
	if t == 0 or t == 1 then return t end
	return math.pow(2, -10 * t) * math.sin((t - 0.1) * 5 * math.pi) + 1
end
function Easing.ElasticInOut(t)
	if t == 0 or t == 1 then return t end
	t = t * 2
	if t < 1 then
		return -0.5 * math.pow(2, 10 * (t - 1)) * math.sin((t - 1.1) * 5 * math.pi)
	end
	return 0.5 * math.pow(2, -10 * (t - 1)) * math.sin((t - 1.1) * 5 * math.pi) + 1
end
function Easing.BounceOut(t)
	if t < 1 / 2.75 then
		return 7.5625 * t * t
	elseif t < 2 / 2.75 then
		t = t - 1.5 / 2.75
		return 7.5625 * t * t + 0.75
	elseif t < 2.5 / 2.75 then
		t = t - 2.25 / 2.75
		return 7.5625 * t * t + 0.9375
	else
		t = t - 2.625 / 2.75
		return 7.5625 * t * t + 0.984375
	end
end
function Easing.BounceIn(t) return 1 - Easing.BounceOut(1 - t) end
function Easing.BounceInOut(t)
	if t < 0.5 then return Easing.BounceIn(t * 2) * 0.5 end
	return Easing.BounceOut(t * 2 - 1) * 0.5 + 0.5
end

local EasingNamed = {
	Linear = Easing.Linear,
	QuadIn = Easing.QuadIn, QuadOut = Easing.QuadOut, QuadInOut = Easing.QuadInOut,
	CubicIn = Easing.CubicIn, CubicOut = Easing.CubicOut, CubicInOut = Easing.CubicInOut,
	QuartIn = Easing.QuartIn, QuartOut = Easing.QuartOut, QuartInOut = Easing.QuartInOut,
	QuintIn = Easing.QuintIn, QuintOut = Easing.QuintOut, QuintInOut = Easing.QuintInOut,
	SineIn = Easing.SineIn, SineOut = Easing.SineOut, SineInOut = Easing.SineInOut,
	CircularIn = Easing.CircularIn, CircularOut = Easing.CircularOut, CircularInOut = Easing.CircularInOut,
	ExpoIn = Easing.ExpoIn, ExpoOut = Easing.ExpoOut, ExpoInOut = Easing.ExpoInOut,
	BackIn = Easing.BackIn, BackOut = Easing.BackOut, BackInOut = Easing.BackInOut,
	ElasticIn = Easing.ElasticIn, ElasticOut = Easing.ElasticOut, ElasticInOut = Easing.ElasticInOut,
	BounceIn = Easing.BounceIn, BounceOut = Easing.BounceOut, BounceInOut = Easing.BounceInOut,
}

local function GetEasing(name)
	if type(name) == "function" then return name end
	return EasingNamed[name] or Easing.Linear
end

----------------------------------------------------------------
-- ANIMATION SCHEDULER + ENGINE (Hardened)
----------------------------------------------------------------
local ActiveAnims = {}
local SchedulerConn = nil
local AnimIdCounter = 0

local function SchedulerUpdate(dt)
	local remove = {}
	for id, anim in pairs(ActiveAnims) do
		if anim.Cancelled or anim._finished then
			table.insert(remove, id)
		else
			local ok, done = pcall(function()
				return anim:Update(dt)
			end)
			if not ok or done then
				anim._finished = true
				table.insert(remove, id)
				if ok and anim.OnComplete and not anim.Cancelled then
					-- Only fire OnComplete if not cancelled
					task.spawn(anim.OnComplete)
				end
			end
		end
	end
	for _, id in ipairs(remove) do
		local anim = ActiveAnims[id]
		if anim then
			anim.Id = nil
		end
		ActiveAnims[id] = nil
	end
	if next(ActiveAnims) == nil and SchedulerConn then
		SchedulerConn:Disconnect()
		SchedulerConn = nil
	end
end

local function SchedulerAdd(anim)
	if anim.Cancelled or anim._finished then
		return nil
	end
	AnimIdCounter += 1
	local id = "a" .. AnimIdCounter
	anim.Id = id
	ActiveAnims[id] = anim
	if not SchedulerConn then
		SchedulerConn = RunService.Heartbeat:Connect(SchedulerUpdate)
	end
	return id
end

local function SchedulerRemove(anim)
	if anim and anim.Id and ActiveAnims[anim.Id] then
		ActiveAnims[anim.Id] = nil
		anim.Id = nil
	end
end

-- Lerp helpers
local function LerpNumber(a, b, t) return a + (b - a) * t end
local function LerpColor3(a, b, t)
	return Color3.new(LerpNumber(a.R, b.R, t), LerpNumber(a.G, b.G, t), LerpNumber(a.B, b.B, t))
end
local function LerpVector2(a, b, t) return Vector2.new(LerpNumber(a.X, b.X, t), LerpNumber(a.Y, b.Y, t)) end
local function LerpVector3(a, b, t)
	return Vector3.new(LerpNumber(a.X, b.X, t), LerpNumber(a.Y, b.Y, t), LerpNumber(a.Z, b.Z, t))
end
local function LerpUDim(a, b, t)
	return UDim.new(LerpNumber(a.Scale, b.Scale, t), LerpNumber(a.Offset, b.Offset, t))
end
local function LerpUDim2(a, b, t)
	return UDim2.new(
		LerpNumber(a.X.Scale, b.X.Scale, t), LerpNumber(a.X.Offset, b.X.Offset, t),
		LerpNumber(a.Y.Scale, b.Y.Scale, t), LerpNumber(a.Y.Offset, b.Y.Offset, t)
	)
end
local function LerpCFrame(a, b, t) return a:Lerp(b, t) end

local function GetLerp(v)
	local t = typeof(v)
	if t == "number" then return LerpNumber
	elseif t == "Color3" then return LerpColor3
	elseif t == "Vector2" then return LerpVector2
	elseif t == "Vector3" then return LerpVector3
	elseif t == "UDim" then return LerpUDim
	elseif t == "UDim2" then return LerpUDim2
	elseif t == "CFrame" then return LerpCFrame
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
	self.Duration = math.max(options.Duration or 0.4, 0.001)
	self.Delay = options.Delay or 0
	self.EasingFn = GetEasing(options.Easing or "QuadOut")
	self.OnComplete = options.OnComplete
	self.Loop = options.Loop or false
	self.Yoyo = options.Yoyo or false
	self.Cancelled = false
	self._finished = false
	self.Elapsed = 0
	self.Started = false
	self.Direction = 1
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
			local value = (self.Direction > 0) and lerp(start, goal, eased) or lerp(goal, start, eased)
			pcall(function()
				if self.Object and self.Object.Parent then
					self.Object[prop] = value
				end
			end)
		end
	end

	if self.Elapsed >= self.Duration then
		if self.Yoyo then
			self.Direction = -self.Direction
			self.Elapsed = 0
			return false
		elseif self.Loop then
			self.Elapsed = 0
			return false
		else
			for prop, goal in pairs(self.Goals) do
				local final = (self.Direction > 0) and goal or self.StartValues[prop]
				pcall(function()
					if self.Object and self.Object.Parent then
						self.Object[prop] = final
					end
				end)
			end
			self._finished = true
			return true
		end
	end
	return false
end

function Animation:Cancel()
	if self.Cancelled or self._finished then return end
	self.Cancelled = true
	self._finished = true
	-- Do not fire OnComplete on cancel
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

function TweenEngine.Spring(object, property, target, options)
	if not object or not object.Parent then return nil end
	options = options or {}
	local stiffness = options.Stiffness or 180
	local damping = options.Damping or 18
	local mass = options.Mass or 1

	local spring = setmetatable({}, Animation)
	spring.Object = object
	spring.Cancelled = false
	spring._finished = false
	spring.OnComplete = options.OnComplete
	spring.Property = property
	spring.Target = target
	spring.Stiffness = stiffness
	spring.Damping = damping
	spring.Mass = mass
	spring.Velocity = 0
	spring.Id = nil

	local ok, current = pcall(function() return object[property] end)
	if not ok then return nil end
	spring.Current = current

	function spring:Update(dt)
		if self.Cancelled or self._finished then return true end
		if not self.Object or not self.Object.Parent then
			self._finished = true
			return true
		end
		if typeof(self.Current) == "number" then
			local force = -self.Stiffness * (self.Current - self.Target)
			local damp = -self.Damping * self.Velocity
			local accel = (force + damp) / self.Mass
			self.Velocity += accel * dt
			self.Current += self.Velocity * dt
			pcall(function() self.Object[self.Property] = self.Current end)
			if math.abs(self.Current - self.Target) < 0.001 and math.abs(self.Velocity) < 0.001 then
				pcall(function() self.Object[self.Property] = self.Target end)
				self._finished = true
				return true
			end
		elseif typeof(self.Current) == "UDim2" then
			local cx, cy = self.Current.X.Offset, self.Current.Y.Offset
			local tx, ty = self.Target.X.Offset, self.Target.Y.Offset
			self.Velocity = self.Velocity or Vector2.zero
			local forceX = -self.Stiffness * (cx - tx)
			local forceY = -self.Stiffness * (cy - ty)
			local vx = self.Velocity.X + (forceX - self.Damping * self.Velocity.X) / self.Mass * dt
			local vy = self.Velocity.Y + (forceY - self.Damping * self.Velocity.Y) / self.Mass * dt
			self.Velocity = Vector2.new(vx, vy)
			cx += vx * dt
			cy += vy * dt
			self.Current = UDim2.new(self.Current.X.Scale, cx, self.Current.Y.Scale, cy)
			pcall(function() self.Object[self.Property] = self.Current end)
			if math.abs(cx - tx) < 0.5 and math.abs(cy - ty) < 0.5 and math.abs(vx) < 1 and math.abs(vy) < 1 then
				pcall(function() self.Object[self.Property] = self.Target end)
				self._finished = true
				return true
			end
		else
			self._finished = true
			return true
		end
		return false
	end

	function spring:Cancel()
		if self.Cancelled or self._finished then return end
		self.Cancelled = true
		self._finished = true
		self.OnComplete = nil
		SchedulerRemove(self)
	end

	function spring:Play()
		if self.Cancelled or self._finished then return self end
		self.Id = SchedulerAdd(self)
		return self
	end
	return spring:Play()
end

function TweenEngine.Shake(object, options)
	if not object or not object.Parent then return nil end
	options = options or {}
	local magnitude = options.Magnitude or 4
	local duration = options.Duration or 0.3
	local frequency = options.Frequency or 25
	local property = options.Property or "Position"

	local ok, original = pcall(function() return object[property] end)
	if not ok then return nil end

	local shake = setmetatable({}, Animation)
	shake.Object = object
	shake.Cancelled = false
	shake._finished = false
	shake.OnComplete = options.OnComplete
	shake.Original = original
	shake.Elapsed = 0
	shake.Duration = duration
	shake.Magnitude = magnitude
	shake.Frequency = frequency
	shake.Property = property
	shake.Id = nil

	function shake:Update(dt)
		if self.Cancelled or self._finished then
			pcall(function()
				if self.Object and self.Object.Parent then
					self.Object[self.Property] = self.Original
				end
			end)
			return true
		end
		if not self.Object or not self.Object.Parent then
			self._finished = true
			return true
		end
		self.Elapsed += dt
		if self.Elapsed >= self.Duration then
			pcall(function() self.Object[self.Property] = self.Original end)
			self._finished = true
			return true
		end
		local progress = self.Elapsed / self.Duration
		local damp = 1 - progress
		local ox = math.sin(self.Elapsed * self.Frequency * math.pi * 2) * self.Magnitude * damp
		local oy = math.cos(self.Elapsed * self.Frequency * math.pi * 1.7) * self.Magnitude * damp * 0.7
		if typeof(self.Original) == "UDim2" then
			pcall(function()
				self.Object[self.Property] = UDim2.new(
					self.Original.X.Scale, self.Original.X.Offset + ox,
					self.Original.Y.Scale, self.Original.Y.Offset + oy
				)
			end)
		end
		return false
	end

	function shake:Cancel()
		if self.Cancelled or self._finished then return end
		self.Cancelled = true
		self._finished = true
		self.OnComplete = nil
		pcall(function()
			if self.Object and self.Object.Parent then
				self.Object[self.Property] = self.Original
			end
		end)
		SchedulerRemove(self)
	end

	function shake:Play()
		if self.Cancelled or self._finished then return self end
		self.Id = SchedulerAdd(self)
		return self
	end
	return shake:Play()
end

function TweenEngine.CancelAll()
	for id, anim in pairs(ActiveAnims) do
		if anim and not anim.Cancelled then
			anim.Cancelled = true
			anim._finished = true
			anim.OnComplete = nil
			if anim.Cancel then
				pcall(function() anim:Cancel() end)
			end
		end
	end
	table.clear(ActiveAnims)
	if SchedulerConn then
		SchedulerConn:Disconnect()
		SchedulerConn = nil
	end
end

function TweenEngine.CancelOnObject(object)
	if not object then return end
	for id, anim in pairs(ActiveAnims) do
		if anim and anim.Object == object and not anim.Cancelled then
			anim:Cancel()
		end
	end
end

----------------------------------------------------------------
-- INPUT / DRAG
----------------------------------------------------------------
local function MakeDraggable(handle, target, options)
	options = options or {}
	target = target or handle
	local enabled = true
	local dragging = false
	local dragStart, startPos
	local conns = {}
	local activeMoveC, activeEndC = nil, nil

	local function clearDragConns()
		if activeMoveC then
			pcall(function() activeMoveC:Disconnect() end)
			activeMoveC = nil
		end
		if activeEndC then
			pcall(function() activeEndC:Disconnect() end)
			activeEndC = nil
		end
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
			for _, c in ipairs(conns) do
				pcall(function() c:Disconnect() end)
			end
			table.clear(conns)
		end
	}
end

----------------------------------------------------------------
-- TYPEWRITER
----------------------------------------------------------------
local function CreateTypewriter(label, options)
	options = options or {}
	local speed = options.Speed or 0.025
	local fullText = label.Text or ""
	local cancelled = false
	local finished = false
	local thread = nil

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
				local char = string.sub(fullText, i, i)
				local d = speed
				if char == "." or char == "!" or char == "?" then
					d = speed * 4
				elseif char == "," or char == ";" then
					d = speed * 2
				elseif char == " " then
					d = speed * 0.6
				end
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

	function api:IsFinished()
		return finished
	end

	return api
end

----------------------------------------------------------------
-- ETHEREAL SEPARATOR
----------------------------------------------------------------
local function CreateEtherealSeparator(parent)
	local container = Instance.new("Frame")
	container.Name = "EtherealSeparator"
	container.BackgroundTransparency = 1
	container.Size = UDim2.new(1, 0, 0, 8)
	container.BorderSizePixel = 0
	container.Parent = parent

	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.BackgroundColor3 = Theme.NotificationTitle
	bar.BackgroundTransparency = 0.7
	bar.BorderSizePixel = 0
	bar.Size = UDim2.new(0.6, 0, 0, 1)
	bar.Position = UDim2.new(0.2, 0, 0.5, 0)
	bar.AnchorPoint = Vector2.new(0, 0.5)
	bar.Parent = container

	local gradient = Instance.new("UIGradient")
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.2, 0.4),
		NumberSequenceKeypoint.new(0.5, 0.15),
		NumberSequenceKeypoint.new(0.8, 0.4),
		NumberSequenceKeypoint.new(1, 1),
	})
	gradient.Parent = bar

	local api = { Container = container, Bar = bar }

	function api:PlayIn(dur)
		dur = dur or 0.45
		bar.Size = UDim2.new(0, 0, 0, 1)
		bar.BackgroundTransparency = 1
		bar.Position = UDim2.new(0.5, 0, 0.5, 0)
		bar.AnchorPoint = Vector2.new(0.5, 0.5)
		TweenEngine.Play(bar, {
			Size = UDim2.new(0.7, 0, 0, 1),
			BackgroundTransparency = 0.65,
			Position = UDim2.new(0.15, 0, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
		}, { Duration = dur, Easing = "ExpoOut" })
	end

	function api:PlayOut(dur)
		dur = dur or 0.25
		TweenEngine.Play(bar, {
			Size = UDim2.new(0, 0, 0, 1),
			BackgroundTransparency = 1,
			Position = UDim2.new(0.5, 0, 0.5, 0),
			AnchorPoint = Vector2.new(0.5, 0.5),
		}, { Duration = dur, Easing = "QuadIn" })
	end

	function api:Destroy()
		if container then container:Destroy() end
	end

	return api
end

----------------------------------------------------------------
-- NOTIFICATION SYSTEM (Merged: Veyra hardened + improved UI)
-- Header bar, large rounded corners, black → soft-white gradient
----------------------------------------------------------------
local NotificationManager = {}
NotificationManager.__index = NotificationManager

local MAX_NOTIFICATIONS = 10 -- hard cap; drop oldest under spam
local NOTIF_CORNER = 16
local NOTIF_HEADER_H = 28
local NOTIF_WIDTH = 270

function NotificationManager.new()
	local self = setmetatable({}, NotificationManager)
	self.Notifications = {}
	self.Spacing = 12
	self.MaxNotifications = MAX_NOTIFICATIONS

	local gui = Instance.new("ScreenGui")
	gui.Name = "VeyraNotifications"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 2147483647
	ProtectAndParent(gui)

	local container = Instance.new("Frame")
	container.Name = "Container"
	container.BackgroundTransparency = 1
	container.Size = UDim2.new(0, 360, 1, -24)
	container.Position = UDim2.new(1, -16, 1, -12)
	container.AnchorPoint = Vector2.new(1, 1)
	container.Parent = gui

	-- Stack from bottom-right
	self.Gui = gui
	self.Container = container
	self.Draggable = true -- default; Library.NotifDraggable = false to disable
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
	-- Duration = 0 or Length = 0 means stay until manual Close()
	local duration = config.Duration
	if duration == nil then duration = config.Length end
	if duration == nil then duration = 5 end
	local notifType = config.Type or "Info"
	local typewriterOpts = config.Typewriter
	local barColor = config.BarColor or Theme[TYPE_COLORS[notifType] or "NotificationInfo"] or Theme.Accent
	local audioId = config.Audio or config.Sound
	local imageId = config.Image or config.Icon

	local cleanup = CreateCleanup()
	local closed = false

	-- Full theme chrome (bg + border + text) — readable in Dark / Light / Neon
	local bg = Theme.NotificationBackground or Theme.Background
	local bd = Theme.NotificationBorder or Theme.Border
	local titleCol = Theme.NotificationTitle or Theme.Text
	local descCol = Theme.NotificationDescription or Theme.SecondaryText
	local headBg = Theme.Secondary or bg

	local frame = Instance.new("Frame")
	frame.Name = "Notification"
	frame.BackgroundColor3 = bg
	frame.BackgroundTransparency = 0
	frame.BorderSizePixel = 0
	frame.Size = UDim2.new(0, NOTIF_WIDTH, 0, 0)
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.AnchorPoint = Vector2.new(0, 1)
	frame.Position = UDim2.new(0, 0, 1, 0)
	frame.ClipsDescendants = true
	frame.Parent = self.Container

	do
		local canDrag = true
		if config.Draggable == false then canDrag = false end
		if self.Draggable == false then canDrag = false end
		if canDrag then
			local dragApi = MakeDraggable(frame, frame)
			cleanup:AddCallback(function()
				if dragApi and dragApi.Destroy then dragApi:Destroy() end
			end)
		end
	end

	-- Subtle theme gradient (follows bg — never stuck on black)
	local function shade(c, mul)
		return Color3.new(
			math.clamp(c.R * mul, 0, 1),
			math.clamp(c.G * mul, 0, 1),
			math.clamp(c.B * mul, 0, 1)
		)
	end
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0.00, shade(bg, 0.92)),
		ColorSequenceKeypoint.new(0.50, bg),
		ColorSequenceKeypoint.new(1.00, shade(bg, 1.08)),
	})
	gradient.Rotation = 0
	gradient.Parent = frame

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, Theme.CornerRadius or 8)
	corner.Parent = frame

	local header = Instance.new("Frame")
	header.Name = "Header"
	header.BackgroundColor3 = headBg
	header.BackgroundTransparency = 0.08
	header.BorderSizePixel = 0
	header.Size = UDim2.new(1, 0, 0, NOTIF_HEADER_H)
	header.ZIndex = 2
	header.Parent = frame

	-- Optional icon
	local contentOffset = 14
	if imageId and tostring(imageId) ~= "" then
		local icon = Instance.new("ImageLabel")
		icon.Name = "Icon"
		icon.BackgroundTransparency = 1
		icon.Size = UDim2.new(0, 22, 0, 22)
		icon.Position = UDim2.new(0, 12, 0.5, -11)
		icon.Image = tostring(imageId)
		icon.ScaleType = Enum.ScaleType.Fit
		icon.ZIndex = 4
		icon.Parent = header
		contentOffset = 40
		cleanup:AddInstance(icon)
	end

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, -contentOffset - 12, 1, 0)
	title.Position = UDim2.new(0, contentOffset, 0, 0)
	title.Font = Theme.FontBold
	title.TextSize = 13
	title.TextColor3 = titleCol
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = config.Title or "Notification"
	title.ZIndex = 4
	title.Parent = header

	-- Body padding + layout
	local body = Instance.new("Frame")
	body.Name = "Body"
	body.BackgroundTransparency = 1
	body.Size = UDim2.new(1, 0, 0, 0)
	body.AutomaticSize = Enum.AutomaticSize.Y
	body.Position = UDim2.new(0, 0, 0, NOTIF_HEADER_H)
	body.Parent = frame

	local bodyPad = Instance.new("UIPadding")
	bodyPad.PaddingTop = UDim.new(0, 7)
	bodyPad.PaddingBottom = UDim.new(0, 9)
	bodyPad.PaddingLeft = UDim.new(0, 12)
	bodyPad.PaddingRight = UDim.new(0, 12)
	bodyPad.Parent = body

	local bodyLayout = Instance.new("UIListLayout")
	bodyLayout.SortOrder = Enum.SortOrder.LayoutOrder
	bodyLayout.Padding = UDim.new(0, 3)
	bodyLayout.Parent = body

	local sep = CreateEtherealSeparator(body)
	sep.Container.LayoutOrder = 1

	local descText = config.Description or config.Content or ""
	local desc = Instance.new("TextLabel")
	desc.Name = "Description"
	desc.BackgroundTransparency = 1
	desc.Size = UDim2.new(1, 0, 0, 0)
	desc.AutomaticSize = Enum.AutomaticSize.Y
	desc.Font = Theme.Font
	desc.TextSize = 12
	desc.TextColor3 = descCol
	desc.TextXAlignment = Enum.TextXAlignment.Left
	desc.TextYAlignment = Enum.TextYAlignment.Top
	desc.TextWrapped = true
	desc.Text = descText
	desc.LayoutOrder = 2
	desc.Parent = body

	-- Thin left type accent
	local accent = Instance.new("Frame")
	accent.Name = "Accent"
	accent.BackgroundColor3 = barColor
	accent.BorderSizePixel = 0
	accent.Size = UDim2.new(0, 3, 1, 0)
	accent.Position = UDim2.new(0, 0, 0, 0)
	accent.ZIndex = 5
	accent.Parent = frame

	local accentCorner = Instance.new("UICorner")
	accentCorner.CornerRadius = UDim.new(0, 2)
	accentCorner.Parent = accent

	-- Progress bar (depletes over duration; hidden if Duration = 0)
	local barBg = Instance.new("Frame")
	barBg.Name = "ProgressBG"
	barBg.BackgroundColor3 = Theme.Border or Color3.fromRGB(80, 80, 90)
	barBg.BackgroundTransparency = 0.7
	barBg.BorderSizePixel = 0
	barBg.Size = UDim2.new(1, 0, 0, 3)
	barBg.Position = UDim2.new(0, 0, 1, -3)
	barBg.ZIndex = 6
	barBg.Parent = frame

	local bar = Instance.new("Frame")
	bar.Name = "Progress"
	bar.BackgroundColor3 = barColor
	bar.BackgroundTransparency = 0.15
	bar.BorderSizePixel = 0
	bar.Size = UDim2.new(1, 0, 1, 0)
	bar.Parent = barBg

	local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = UDim.new(1, 0)
	barCorner.Parent = bar

	if duration <= 0 then
		barBg.Visible = false
	end

	cleanup:AddInstance(frame)

	-- Optional sound
	if audioId and tostring(audioId) ~= "" then
		local sound = Instance.new("Sound")
		sound.SoundId = tostring(audioId)
		sound.Volume = 0.8
		sound.Parent = frame
		pcall(function() sound:Play() end)
		cleanup:AddInstance(sound)
	end

	local twTitle, twDesc
	local doTitle, doDesc, speed = false, false, 0.025
	if typewriterOpts == true then
		doTitle, doDesc = true, true
	elseif type(typewriterOpts) == "table" then
		doTitle = typewriterOpts.Title ~= false
		doDesc = typewriterOpts.Description ~= false
		speed = typewriterOpts.Speed or 0.025
	end
	if doTitle then twTitle = CreateTypewriter(title, { Speed = speed }) end
	if doDesc then twDesc = CreateTypewriter(desc, { Speed = speed }) end

	local notif = {
		Frame = frame,
		TitleLabel = title,
		DescLabel = desc,
		Separator = sep,
		Closed = false,
		Config = config,
		Cleanup = cleanup,
	}

	function notif:PlayEntry(targetPos)
		frame.Position = UDim2.new(0, 40, 1, targetPos.Y.Offset)
		frame.BackgroundTransparency = 1
		TweenEngine.Play(frame, {
			Position = targetPos,
			BackgroundTransparency = 0,
		}, { Duration = 0.45, Easing = "QuintOut" })

		task.delay(0.12, function()
			if not closed then sep:PlayIn(0.35) end
		end)
		task.delay(0.18, function()
			if closed then return end
			if twTitle then twTitle:Start(config.Title or "Notification") end
			if twDesc then twDesc:Start(descText) end
		end)

		if duration > 0 then
			TweenEngine.Play(bar, {
				Size = UDim2.new(0, 0, 1, 0),
			}, { Duration = duration, Easing = "Linear" })
		end
	end

	function notif:PlayExit(callback)
		if closed then return end
		closed = true
		notif.Closed = true
		if twTitle then twTitle:Finish() end
		if twDesc then twDesc:Finish() end
		sep:PlayOut(0.2)
		TweenEngine.CancelOnObject(bar)
		TweenEngine.Play(frame, {
			Position = UDim2.new(0, 60, 1, frame.Position.Y.Offset),
			BackgroundTransparency = 1,
		}, {
			Duration = 0.32,
			Easing = "QuintIn",
			OnComplete = function()
				cleanup:Destroy()
				sep:Destroy()
				if callback then callback() end
			end,
		})
	end

	function notif:Close()
		if closed then return end
		self.Manager:Remove(self)
	end

	function notif:SetTitle(text)
		config.Title = text
		if twTitle and not twTitle:IsFinished() then twTitle:Finish() end
		title.Text = text
	end

	function notif:SetDescription(text)
		config.Description = text
		if twDesc and not twDesc:IsFinished() then twDesc:Finish() end
		desc.Text = text
	end

	function notif:RefreshTheme()
		if closed or not frame or not frame.Parent then return end
		local nbg = Theme.NotificationBackground or Theme.Background
		local nbd = Theme.NotificationBorder or Theme.Border
		local nt = Theme.NotificationTitle or Theme.Text
		local nd = Theme.NotificationDescription or Theme.SecondaryText
		frame.BackgroundColor3 = nbg
		stroke.Color = nbd
		header.BackgroundColor3 = Theme.Secondary or nbg
		title.TextColor3 = nt
		desc.TextColor3 = nd
		local function shade(c, mul)
			return Color3.new(math.clamp(c.R*mul,0,1), math.clamp(c.G*mul,0,1), math.clamp(c.B*mul,0,1))
		end
		gradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0.00, shade(nbg, 0.92)),
			ColorSequenceKeypoint.new(0.50, nbg),
			ColorSequenceKeypoint.new(1.00, shade(nbg, 1.08)),
		})
	end
	local unhookTheme = OnThemeChange(function()
		if notif.RefreshTheme then notif:RefreshTheme() end
	end)
	cleanup:AddCallback(unhookTheme)

	notif.Manager = self
	table.insert(self.Notifications, 1, notif)

	-- Drop oldest when over cap (stress protection)
	local maxN = self.MaxNotifications or MAX_NOTIFICATIONS
	while #self.Notifications > maxN do
		local oldest = self.Notifications[#self.Notifications]
		if oldest and not oldest.Closed then
			oldest:Close()
		else
			table.remove(self.Notifications, #self.Notifications)
		end
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
	-- Bottom-up stack: index 1 is lowest (newest). Offset grows upward.
	-- When stack exceeds screen, older notifs sit higher (still stacked).
	local y = 0
	for i = 1, index - 1 do
		local n = self.Notifications[i]
		if n and n.Frame and not n.Closed then
			local h = n.Frame.AbsoluteSize.Y
			if h < 1 then h = 72 end
			y = y + h + self.Spacing
		end
	end
	-- Clamp so top of stack never goes past top of container
	local maxY = math.max(0, (self.Container.AbsoluteSize.Y > 0 and self.Container.AbsoluteSize.Y or 600) - 40)
	if y > maxY then
		-- Still return position; hard-cap drops oldest. Offset stays valid.
		y = math.min(y, maxY + 200)
	end
	-- AnchorPoint (0,1) on frame → Position Y scale 1, offset -y stacks upward
	return UDim2.new(0, 0, 1, -y)
end

function NotificationManager:RepositionAll(animate)
	local function apply()
		for i, notif in ipairs(self.Notifications) do
			if notif.Closed then continue end
			local target = self:GetPositionForIndex(i)
			if animate then
				TweenEngine.Play(notif.Frame, { Position = target }, { Duration = 0.3, Easing = "QuintOut" })
			else
				notif.Frame.Position = target
			end
		end
	end
	apply()
	-- Second pass after layout settles (AbsoluteSize becomes real)
	task.defer(apply)
end

function NotificationManager:Remove(notif)
	local idx = table.find(self.Notifications, notif)
	if not idx then return end
	table.remove(self.Notifications, idx)
	notif:PlayExit(function()
		self:RepositionAll(true)
	end)
end

function NotificationManager:Clear()
	while #self.Notifications > 0 do
		self.Notifications[1]:Close()
	end
end

function NotificationManager:Destroy()
	self:Clear()
	if self.Gui then self.Gui:Destroy() end
end

----------------------------------------------------------------
-- COMPONENTS
----------------------------------------------------------------
local function GetParentForComponent(tab)
	if #tab.Sections > 0 then
		return tab.Sections[#tab.Sections].Content
	end
	return tab.Content
end

-- SECTION
local function CreateSection(tab, config)
	config = config or {}
	local cleanup = CreateCleanup()

	local container = Instance.new("Frame")
	container.Name = "Section_" .. (config.Name or "Untitled")
	container.BackgroundTransparency = 1
	container.Size = UDim2.new(1, 0, 0, 0)
	container.AutomaticSize = Enum.AutomaticSize.Y
	container.Parent = tab.Content

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 8)
	layout.Parent = container

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, 0, 0, 20)
	title.Font = Theme.FontBold
	title.TextSize = 13
	title.TextColor3 = Theme.Text
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = config.Name or "Section"
	title.LayoutOrder = 0
	title.Parent = container

	if config.Description then
		local d = Instance.new("TextLabel")
		d.BackgroundTransparency = 1
		d.Size = UDim2.new(1, 0, 0, 16)
		d.Font = Theme.Font
		d.TextSize = 11
		d.TextColor3 = Theme.SecondaryText
		d.TextXAlignment = Enum.TextXAlignment.Left
		d.Text = config.Description
		d.LayoutOrder = 1
		d.Parent = container
	end

	local content = Instance.new("Frame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.Size = UDim2.new(1, 0, 0, 0)
	content.AutomaticSize = Enum.AutomaticSize.Y
	content.LayoutOrder = 2
	content.Parent = container

	local cl = Instance.new("UIListLayout")
	cl.SortOrder = Enum.SortOrder.LayoutOrder
	cl.Padding = UDim.new(0, 6)
	cl.Parent = content

	cleanup:AddInstance(container)

	local descLabel = nil
	if config.Description then
		descLabel = container:FindFirstChildWhichIsA("TextLabel")
		-- title is first, description is second TextLabel
		for _, ch in ipairs(container:GetChildren()) do
			if ch:IsA("TextLabel") and ch ~= title then
				descLabel = ch
				break
			end
		end
	end

	local section = {
		Container = container,
		Content = content,
		Cleanup = cleanup,
	}

	function section:RefreshTheme()
		if cleanup:IsDestroyed() then return end
		title.Font = Theme.FontBold
		title.TextColor3 = Theme.Text
		if descLabel then
			descLabel.Font = Theme.Font
			descLabel.TextColor3 = Theme.SecondaryText
		end
	end

	function section:Destroy()
		cleanup:Destroy()
	end

	table.insert(tab.Sections, section)
	return section
end

-- BUTTON (supports Callback and optional Script / Code via loadstring)
local function CreateButton(tab, config)
	config = config or {}
	local cleanup = CreateCleanup()
	local enabled = true
	local parent = GetParentForComponent(tab)

	local frame = Instance.new("TextButton")
	frame.Name = "Button_" .. (config.Name or "Untitled")
	frame.BackgroundColor3 = Theme.Secondary
	frame.BackgroundTransparency = 0.1
	frame.BorderSizePixel = 0
	frame.Size = UDim2.new(1, 0, 0, Theme.ElementHeight)
	frame.AutoButtonColor = false
	frame.Text = ""
	frame.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, Theme.CornerRadius)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Border
	stroke.Thickness = 1
	stroke.Transparency = 1
	stroke.Parent = frame

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, 0, 0, 16)
	title.AnchorPoint = Vector2.new(0, 0.5)
	title.Position = UDim2.new(0, 0, 0.5, config.Description and -7 or 0)
	title.Font = Theme.Font
	title.TextSize = 13
	title.TextColor3 = Theme.Text
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextYAlignment = Enum.TextYAlignment.Center
	title.Text = config.Name or "Button"
	title.Parent = frame

	local titlePadding = Instance.new("UIPadding")
	titlePadding.PaddingLeft = UDim.new(0, 12)
	titlePadding.PaddingRight = UDim.new(0, 12)
	titlePadding.Parent = title

	local desc
	if config.Description then
		desc = Instance.new("TextLabel")
		desc.BackgroundTransparency = 1
		desc.Size = UDim2.new(1, 0, 0, 14)
		desc.AnchorPoint = Vector2.new(0, 0.5)
		desc.Position = UDim2.new(0, 0, 0.5, 8)
		desc.Font = Theme.Font
		desc.TextSize = 11
		desc.TextColor3 = Theme.SecondaryText
		desc.TextXAlignment = Enum.TextXAlignment.Left
		desc.TextYAlignment = Enum.TextYAlignment.Center
		desc.Text = config.Description
		desc.Parent = frame
		local descPadding = Instance.new("UIPadding")
		descPadding.PaddingLeft = UDim.new(0, 12)
		descPadding.PaddingRight = UDim.new(0, 12)
		descPadding.Parent = desc
	end

	cleanup:AddConnection(frame.MouseEnter:Connect(function()
		if not enabled then return end
		TweenEngine.Play(frame, { BackgroundColor3 = Theme.Hover }, { Duration = Theme.HoverSpeed, Easing = "QuadOut" })
	end))
	cleanup:AddConnection(frame.MouseLeave:Connect(function()
		if not enabled then return end
		TweenEngine.Play(frame, { BackgroundColor3 = Theme.Secondary }, { Duration = Theme.HoverSpeed, Easing = "QuadOut" })
	end))
	cleanup:AddConnection(frame.MouseButton1Down:Connect(function()
		if not enabled then return end
		TweenEngine.Play(frame, { BackgroundColor3 = Theme.Tertiary }, { Duration = 0.08 })
	end))
	cleanup:AddConnection(frame.MouseButton1Up:Connect(function()
		if not enabled then return end
		TweenEngine.Play(frame, { BackgroundColor3 = Theme.Hover }, { Duration = 0.1 })
	end))

	cleanup:AddConnection(frame.MouseButton1Click:Connect(function()
		if not enabled then return end

		-- Optional loadstring / Script support
		local code = config.Script or config.Code
		if type(code) == "string" and #code > 0 then
			local ok, err = pcall(function()
				local fn = loadstring(code)
				if fn then
					fn()
				else
					warn("[VeyraUI] loadstring returned nil for button script")
				end
			end)
			if not ok then
				warn("[VeyraUI] Button script error:", err)
			end
		end

		if config.Callback then
			task.spawn(config.Callback)
		end
	end))

	cleanup:AddInstance(frame)

	local btn = { Frame = frame, Cleanup = cleanup }

	function btn:RefreshTheme()
		if cleanup:IsDestroyed() then return end
		frame.BackgroundColor3 = Theme.Secondary
		stroke.Color = Theme.Border
		title.Font = Theme.Font
		title.TextColor3 = enabled and Theme.Text or Theme.MutedText
		if desc then
			desc.Font = Theme.Font
			desc.TextColor3 = enabled and Theme.SecondaryText or Theme.MutedText
		end
	end

	function btn:SetEnabled(state)
		enabled = state
		frame.BackgroundTransparency = state and 0.1 or 0.5
		title.TextColor3 = state and Theme.Text or Theme.MutedText
		if desc then desc.TextColor3 = state and Theme.SecondaryText or Theme.MutedText end
	end

	function btn:SetCallback(fn)
		config.Callback = fn
	end

	function btn:Destroy()
		cleanup:Destroy()
	end

	table.insert(tab.Components, btn)
	return btn
end

-- TOGGLE
local function CreateToggle(tab, config)
	config = config or {}
	local cleanup = CreateCleanup()
	local value = config.Default == true
	local enabled = true
	local parent = GetParentForComponent(tab)

	local frame = Instance.new("Frame")
	frame.Name = "Toggle_" .. (config.Name or "Untitled")
	frame.BackgroundColor3 = Theme.Secondary
	frame.BackgroundTransparency = 0.15
	frame.BorderSizePixel = 0
	frame.Size = UDim2.new(1, 0, 0, Theme.ElementHeight)
	frame.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, Theme.CornerRadius)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Border
	stroke.Thickness = 1
	stroke.Transparency = 1
	stroke.Parent = frame

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, 0, 0, 16)
	title.AnchorPoint = Vector2.new(0, 0.5)
	title.Position = UDim2.new(0, 0, 0.5, config.Description and -7 or 0)
	title.Font = Theme.Font
	title.TextSize = 13
	title.TextColor3 = Theme.Text
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextYAlignment = Enum.TextYAlignment.Center
	title.Text = config.Name or "Toggle"
	title.Parent = frame

	local titlePadding = Instance.new("UIPadding")
	titlePadding.PaddingLeft = UDim.new(0, 12)
	titlePadding.PaddingRight = UDim.new(0, 64)
	titlePadding.Parent = title

	if config.Description then
		local d = Instance.new("TextLabel")
		d.BackgroundTransparency = 1
		d.Size = UDim2.new(1, 0, 0, 14)
		d.AnchorPoint = Vector2.new(0, 0.5)
		d.Position = UDim2.new(0, 0, 0.5, 8)
		d.Font = Theme.Font
		d.TextSize = 11
		d.TextColor3 = Theme.SecondaryText
		d.TextXAlignment = Enum.TextXAlignment.Left
		d.TextYAlignment = Enum.TextYAlignment.Center
		d.Text = config.Description
		d.Parent = frame
		local descPadding = Instance.new("UIPadding")
		descPadding.PaddingLeft = UDim.new(0, 12)
		descPadding.PaddingRight = UDim.new(0, 64)
		descPadding.Parent = d
	end

	local switch = Instance.new("Frame")
	switch.BackgroundColor3 = value and Theme.ToggleOn or Theme.ToggleOff
	switch.BorderSizePixel = 0
	switch.Size = UDim2.new(0, 40, 0, 22)
	switch.Position = UDim2.new(1, -52, 0.5, -11)
	switch.Parent = frame

	local sc = Instance.new("UICorner")
	sc.CornerRadius = UDim.new(1, 0)
	sc.Parent = switch

	local knob = Instance.new("Frame")
	knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	knob.BorderSizePixel = 0
	knob.Size = UDim2.new(0, 16, 0, 16)
	knob.Position = value and UDim2.new(1, -19, 0.5, -8) or UDim2.new(0, 3, 0.5, -8)
	knob.Parent = switch

	local kc = Instance.new("UICorner")
	kc.CornerRadius = UDim.new(1, 0)
	kc.Parent = knob

	local function updateVisual(animate)
		local targetColor = value and Theme.ToggleOn or Theme.ToggleOff
		local targetPos = value and UDim2.new(1, -19, 0.5, -8) or UDim2.new(0, 3, 0.5, -8)
		if animate then
			TweenEngine.Play(switch, { BackgroundColor3 = targetColor }, { Duration = 0.2, Easing = "QuadOut" })
			TweenEngine.Play(knob, { Position = targetPos }, { Duration = 0.25, Easing = "BackOut" })
		else
			switch.BackgroundColor3 = targetColor
			knob.Position = targetPos
		end
	end

	local hit = Instance.new("TextButton")
	hit.BackgroundTransparency = 1
	hit.Size = UDim2.new(1, 0, 1, 0)
	hit.Text = ""
	hit.Parent = frame

	local changed = CreateSignal()

	cleanup:AddConnection(hit.MouseButton1Click:Connect(function()
		if not enabled then return end
		value = not value
		updateVisual(true)
		changed:Fire(value)
		if config.Callback then task.spawn(config.Callback, value) end
	end))

	cleanup:AddInstance(frame)
	updateVisual(false)

	local toggle = { Frame = frame, Cleanup = cleanup, Changed = changed }

	function toggle:RefreshTheme()
		if cleanup:IsDestroyed() then return end
		frame.BackgroundColor3 = Theme.Secondary
		stroke.Color = Theme.Border
		title.Font = Theme.Font
		title.TextColor3 = Theme.Text
		updateVisual(false)
	end

	function toggle:Set(v, suppress)
		if value == v then return end
		value = v
		updateVisual(true)
		if not suppress then
			changed:Fire(value)
			if config.Callback then task.spawn(config.Callback, value) end
		end
	end

	function toggle:Get()
		return value
	end

	function toggle:SetEnabled(state)
		enabled = state
		frame.BackgroundTransparency = state and 0.15 or 0.5
	end

	function toggle:Destroy()
		changed:Destroy()
		cleanup:Destroy()
	end

	function toggle:IsDestroyed()
		return cleanup:IsDestroyed()
	end

	table.insert(tab.Components, toggle)
	return toggle
end

-- SLIDER
local function CreateSlider(tab, config)
	config = config or {}
	local cleanup = CreateCleanup()
	local minv = config.Min or 0
	local maxv = config.Max or 100
	local step = config.Step or 1
	local value = config.Default or minv
	local enabled = true
	local parent = GetParentForComponent(tab)
	local dragging = false

	local frame = Instance.new("Frame")
	frame.Name = "Slider_" .. (config.Name or "Untitled")
	frame.BackgroundColor3 = Theme.Secondary
	frame.BackgroundTransparency = 0.15
	frame.BorderSizePixel = 0
	frame.Size = UDim2.new(1, 0, 0, 52)
	frame.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, Theme.CornerRadius)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Border
	stroke.Thickness = 1
	stroke.Transparency = 1
	stroke.Parent = frame

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(0.7, 0, 0, 16)
	title.Position = UDim2.new(0, 12, 0, 8)
	title.Font = Theme.Font
	title.TextSize = 13
	title.TextColor3 = Theme.Text
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = config.Name or "Slider"
	title.Parent = frame

	local valueLabel = Instance.new("TextLabel")
	valueLabel.BackgroundTransparency = 1
	valueLabel.Size = UDim2.new(0.3, -12, 0, 16)
	valueLabel.Position = UDim2.new(0.7, 0, 0, 8)
	valueLabel.Font = Theme.FontMono
	valueLabel.TextSize = 12
	valueLabel.TextColor3 = Theme.SecondaryText
	valueLabel.TextXAlignment = Enum.TextXAlignment.Right
	valueLabel.Text = tostring(value)
	valueLabel.Parent = frame

	local track = Instance.new("Frame")
	track.BackgroundColor3 = Theme.SliderTrack
	track.BorderSizePixel = 0
	track.Size = UDim2.new(1, -24, 0, 4)
	track.Position = UDim2.new(0, 12, 1, -16)
	track.Parent = frame

	local tc = Instance.new("UICorner")
	tc.CornerRadius = UDim.new(1, 0)
	tc.Parent = track

	local fill = Instance.new("Frame")
	fill.BackgroundColor3 = Theme.SliderFill
	fill.BorderSizePixel = 0
	fill.Size = UDim2.new(0, 0, 1, 0)
	fill.Parent = track

	local fc = Instance.new("UICorner")
	fc.CornerRadius = UDim.new(1, 0)
	fc.Parent = fill

	local knob = Instance.new("Frame")
	knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	knob.BorderSizePixel = 0
	knob.Size = UDim2.new(0, 12, 0, 12)
	knob.Position = UDim2.new(0, -6, 0.5, -6)
	knob.ZIndex = 2
	knob.Parent = track

	local kc = Instance.new("UICorner")
	kc.CornerRadius = UDim.new(1, 0)
	kc.Parent = knob

	local function snap(v)
		local s = math.floor((v - minv) / step + 0.5) * step + minv
		return math.clamp(s, minv, maxv)
	end

	local function setVisual(v, animate)
		local alpha = math.clamp((v - minv) / (maxv - minv), 0, 1)
		local ts = UDim2.new(alpha, 0, 1, 0)
		local tp = UDim2.new(alpha, -6, 0.5, -6)
		if animate then
			TweenEngine.Play(fill, { Size = ts }, { Duration = 0.15, Easing = "QuadOut" })
			TweenEngine.Play(knob, { Position = tp }, { Duration = 0.15, Easing = "QuadOut" })
		else
			fill.Size = ts
			knob.Position = tp
		end
		valueLabel.Text = tostring(math.floor(v * 100 + 0.5) / 100)
	end

	local changed = CreateSignal()

	local function updateFromInput(pos)
		local rel = math.clamp((pos.X - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
		local raw = minv + rel * (maxv - minv)
		local newVal = snap(raw)
		if newVal ~= value then
			value = newVal
			setVisual(newVal, false)
			if changed then changed:Fire(newVal) end
			if config.Callback then task.spawn(config.Callback, newVal) end
		else
			setVisual(newVal, false)
		end
	end

	local hit = Instance.new("TextButton")
	hit.BackgroundTransparency = 1
	hit.Size = UDim2.new(1, 0, 0, 20)
	hit.Position = UDim2.new(0, 0, 1, -24)
	hit.Text = ""
	hit.Parent = frame

	local moveConn, endConn = nil, nil
	local function clearSliderDrag()
		if moveConn then
			pcall(function() moveConn:Disconnect() end)
			moveConn = nil
		end
		if endConn then
			pcall(function() endConn:Disconnect() end)
			endConn = nil
		end
		dragging = false
	end

	cleanup:AddConnection(hit.InputBegan:Connect(function(input)
		if not enabled then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			clearSliderDrag()
			dragging = true
			updateFromInput(input.Position)
			-- only live while dragging (avoids N permanent global UIS hooks)
			moveConn = UserInputService.InputChanged:Connect(function(inp)
				if not dragging then return end
				if inp.UserInputType == Enum.UserInputType.MouseMovement or inp.UserInputType == Enum.UserInputType.Touch then
					updateFromInput(inp.Position)
				end
			end)
			endConn = UserInputService.InputEnded:Connect(function(inp)
				if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
					clearSliderDrag()
				end
			end)
		end
	end))

	cleanup:AddCallback(clearSliderDrag)

	cleanup:AddInstance(frame)
	setVisual(value, false)

	local slider = { Frame = frame, Cleanup = cleanup, Changed = changed }

	function slider:RefreshTheme()
		if cleanup:IsDestroyed() then return end
		frame.BackgroundColor3 = Theme.Secondary
		stroke.Color = Theme.Border
		title.Font = Theme.Font
		title.TextColor3 = Theme.Text
		valueLabel.Font = Theme.FontMono
		valueLabel.TextColor3 = Theme.SecondaryText
		track.BackgroundColor3 = Theme.SliderTrack
		fill.BackgroundColor3 = Theme.SliderFill
	end

	function slider:Set(v, suppress)
		v = snap(math.clamp(v, minv, maxv))
		if value == v then return end
		value = v
		setVisual(v, true)
		if not suppress then
			changed:Fire(v)
			if config.Callback then task.spawn(config.Callback, v) end
		end
	end

	function slider:Get()
		return value
	end

	function slider:Destroy()
		changed:Destroy()
		cleanup:Destroy()
	end

	function slider:IsDestroyed()
		return cleanup:IsDestroyed()
	end

	table.insert(tab.Components, slider)
	return slider
end

-- LABEL
local function CreateLabel(tab, config)
	config = config or {}
	local cleanup = CreateCleanup()
	local parent = GetParentForComponent(tab)

	local frame = Instance.new("Frame")
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.new(1, 0, 0, config.Description and 36 or 20)
	frame.Parent = parent

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, 0, 0, 16)
	title.Font = Theme.Font
	title.TextSize = 13
	title.TextColor3 = Theme.Text
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = config.Name or "Label"
	title.Parent = frame

	local desc
	if config.Description then
		desc = Instance.new("TextLabel")
		desc.BackgroundTransparency = 1
		desc.Size = UDim2.new(1, 0, 0, 14)
		desc.Position = UDim2.new(0, 0, 0, 18)
		desc.Font = Theme.Font
		desc.TextSize = 11
		desc.TextColor3 = Theme.SecondaryText
		desc.TextXAlignment = Enum.TextXAlignment.Left
		desc.Text = config.Description
		desc.Parent = frame
	end

	cleanup:AddInstance(frame)

	local label = { Frame = frame, TitleLabel = title, DescLabel = desc, Cleanup = cleanup }

	function label:RefreshTheme()
		if cleanup:IsDestroyed() then return end
		title.Font = Theme.Font
		title.TextColor3 = Theme.Text
		if desc then
			desc.Font = Theme.Font
			desc.TextColor3 = Theme.SecondaryText
		end
	end

	function label:SetTitle(t) title.Text = t end
	function label:SetDescription(t) if desc then desc.Text = t end end
	function label:Destroy() cleanup:Destroy() end

	table.insert(tab.Components, label)
	return label
end

-- DROPDOWN (expands frame so content below sinks via UIListLayout)
local function CreateDropdown(tab, config)
	config = config or {}
	local cleanup = CreateCleanup()
	local options = config.Options or {}
	local value = config.Default or (options[1] or "")
	local open = false
	local transitioning = false
	local destroyed = false
	local parent = GetParentForComponent(tab)
	local outsideConn = nil
	local closedHeight = Theme.ElementHeight
	local listGap = 4
	local optionH = 28
	local maxListH = 140

	-- Declare early so closures can safely reference them
	local changed = CreateSignal()
	local dd = { Frame = nil, Cleanup = cleanup, Changed = changed }

	local frame = Instance.new("Frame")
	frame.Name = "Dropdown_" .. (config.Name or "Untitled")
	frame.BackgroundColor3 = Theme.Secondary
	frame.BackgroundTransparency = 0.15
	frame.BorderSizePixel = 0
	frame.Size = UDim2.new(1, 0, 0, closedHeight)
	frame.ClipsDescendants = true -- clip list while animating height
	frame.Parent = parent
	dd.Frame = frame

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, Theme.CornerRadius)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Border
	stroke.Thickness = 1
	stroke.Transparency = 1
	stroke.Parent = frame

	-- Header row (always visible)
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.BackgroundTransparency = 1
	header.Size = UDim2.new(1, 0, 0, closedHeight)
	header.Position = UDim2.new(0, 0, 0, 0)
	header.ZIndex = 2
	header.Parent = frame

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, -40, 1, 0)
	title.Position = UDim2.new(0, 12, 0, 0)
	title.Font = Theme.Font
	title.TextSize = 13
	title.TextColor3 = Theme.Text
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = (config.Name or "Dropdown") .. ": " .. tostring(value)
	title.Parent = header

	local arrow = Instance.new("TextLabel")
	arrow.BackgroundTransparency = 1
	arrow.Size = UDim2.new(0, 20, 1, 0)
	arrow.Position = UDim2.new(1, -28, 0, 0)
	arrow.Font = Enum.Font.GothamBold
	arrow.TextSize = 12
	arrow.TextColor3 = Theme.SecondaryText
	arrow.Text = "▼"
	arrow.Parent = header

	-- List stays INSIDE frame (attached to header) — expands with tween
	local list = Instance.new("Frame")
	list.Name = "List"
	list.BackgroundColor3 = Theme.Tertiary
	list.BackgroundTransparency = 0
	list.BorderSizePixel = 0
	list.Size = UDim2.new(1, 0, 0, 0)
	list.Position = UDim2.new(0, 0, 0, closedHeight)
	list.Visible = true
	list.ZIndex = 3
	list.ClipsDescendants = true
	list.Parent = frame

	local ls = Instance.new("UIStroke")
	ls.Color = Theme.Border
	ls.Thickness = 1
	ls.Transparency = 1
	ls.Parent = list

	local ll = Instance.new("UIListLayout")
	ll.SortOrder = Enum.SortOrder.LayoutOrder
	ll.Padding = UDim.new(0, 0)
	ll.Parent = list

	local function getListHeight()
		return math.min(math.max(#options, 1) * optionH, maxListH)
	end

	local function bumpParentCanvas()
		local p = frame.Parent
		while p do
			if p:IsA("ScrollingFrame") then
				local lay = p:FindFirstChildOfClass("UIListLayout")
				if lay then
					p.CanvasSize = UDim2.new(0, 0, 0, math.max(lay.AbsoluteContentSize.Y + 24, p.AbsoluteSize.Y))
				end
				break
			end
			p = p.Parent
		end
	end

	local function forceClose(instant)
		if destroyed then return end
		open = false
		if outsideConn then
			outsideConn:Disconnect()
			outsideConn = nil
		end
		TweenEngine.CancelOnObject(list)
		TweenEngine.CancelOnObject(frame)
		arrow.Text = "▼"
		if instant then
			list.Size = UDim2.new(1, 0, 0, 0)
			frame.Size = UDim2.new(1, 0, 0, closedHeight)
			frame.ClipsDescendants = true
			frame.ZIndex = 1
			transitioning = false
			bumpParentCanvas()
		else
			transitioning = true
			TweenEngine.Play(list, { Size = UDim2.new(1, 0, 0, 0) }, {
				Duration = 0.18, Easing = "QuadIn",
			})
			TweenEngine.Play(frame, { Size = UDim2.new(1, 0, 0, closedHeight) }, {
				Duration = 0.2, Easing = "QuadIn",
				OnComplete = function()
					if not destroyed then
						frame.ClipsDescendants = true
						frame.ZIndex = 1
						transitioning = false
						bumpParentCanvas()
					end
				end,
			})
		end
	end

	local function openList()
		if destroyed or transitioning or open then return end
		if #options == 0 then return end
		if tab and tab.Components then
			for _, c in ipairs(tab.Components) do
				if c ~= dd and c.Close then pcall(function() c:Close() end) end
			end
		end
		transitioning = true
		open = true
		local height = getListHeight()
		local totalH = closedHeight + height

		-- Keep top fixed — growth is DOWN only (never upward)
		frame.AnchorPoint = Vector2.new(0, 0)
		frame.ClipsDescendants = true
		frame.ZIndex = 30
		-- snap closed height first so tween has a clear start
		frame.Size = UDim2.new(1, 0, 0, closedHeight)

		list.Parent = frame
		list.AnchorPoint = Vector2.new(0, 0)
		list.Position = UDim2.new(0, 0, 0, closedHeight) -- glued under header
		list.Size = UDim2.new(1, 0, 0, 0)
		list.Visible = true
		list.BackgroundTransparency = 0
		list.BackgroundColor3 = Theme.Tertiary
		list.ZIndex = 31
		list.ClipsDescendants = true

		for _, child in ipairs(list:GetChildren()) do
			if child:IsA("TextButton") then
				child.Visible = true
				child.ZIndex = 32
				child.BackgroundTransparency = 0
				child.TextTransparency = 0
			end
		end

		TweenEngine.CancelOnObject(list)
		TweenEngine.CancelOnObject(frame)

		TweenEngine.Play(frame, {
			Size = UDim2.new(1, 0, 0, totalH),
		}, { Duration = 0.28, Easing = "QuadOut" })
		TweenEngine.Play(list, {
			Size = UDim2.new(1, 0, 0, height),
		}, {
			Duration = 0.28,
			Easing = "QuadOut",
			OnComplete = function()
				transitioning = false
				bumpParentCanvas()
			end,
		})
		arrow.Text = "▲"
		task.defer(bumpParentCanvas)

		task.defer(function()
			if destroyed or not open then return end
			outsideConn = UserInputService.InputBegan:Connect(function(input)
				if input.UserInputType ~= Enum.UserInputType.MouseButton1
					and input.UserInputType ~= Enum.UserInputType.Touch then
					return
				end
				local pos = input.Position
				local absPos = frame.AbsolutePosition
				local absSize = frame.AbsoluteSize
				if pos.X < absPos.X or pos.X > absPos.X + absSize.X
					or pos.Y < absPos.Y or pos.Y > absPos.Y + absSize.Y then
					forceClose(false)
				end
			end)
			cleanup:AddConnection(outsideConn)
		end)
	end

	for i, opt in ipairs(options) do
		local btn = Instance.new("TextButton")
		btn.Name = "Opt_" .. tostring(i)
		btn.BackgroundColor3 = Theme.Tertiary
		btn.BackgroundTransparency = 0
		btn.BorderSizePixel = 0
		btn.Size = UDim2.new(1, 0, 0, optionH)
		btn.Font = Theme.Font
		btn.TextSize = 13
		btn.TextColor3 = Theme.Text
		btn.TextTransparency = 0
		btn.Text = tostring(opt)
		btn.TextXAlignment = Enum.TextXAlignment.Left
		btn.AutoButtonColor = false
		btn.Visible = true
		btn.ZIndex = 4
		btn.LayoutOrder = i
		btn.Parent = list

		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 12)
		pad.Parent = btn

		btn.MouseEnter:Connect(function()
			if destroyed then return end
			TweenEngine.Play(btn, { BackgroundColor3 = Theme.Hover }, { Duration = 0.1 })
		end)
		btn.MouseLeave:Connect(function()
			if destroyed then return end
			TweenEngine.Play(btn, { BackgroundColor3 = Theme.Tertiary }, { Duration = 0.1 })
		end)
		btn.MouseButton1Click:Connect(function()
			if destroyed or transitioning then return end
			value = opt
			title.Text = (config.Name or "Dropdown") .. ": " .. tostring(opt)
			changed:Fire(opt)
			if config.Callback then task.spawn(config.Callback, opt) end
			forceClose(false)
		end)
	end

	local hit = Instance.new("TextButton")
	hit.BackgroundTransparency = 1
	hit.Size = UDim2.new(1, 0, 1, 0)
	hit.Text = ""
	hit.ZIndex = 5
	hit.Parent = header

	cleanup:AddConnection(hit.MouseButton1Click:Connect(function()
		if destroyed or transitioning then return end
		if open then
			forceClose(false)
		else
			openList()
		end
	end))

	cleanup:AddInstance(frame)

	function dd:RefreshTheme()
		if destroyed or cleanup:IsDestroyed() then return end
		frame.BackgroundColor3 = Theme.Secondary
		stroke.Color = Theme.Border
		title.Font = Theme.Font
		title.TextColor3 = Theme.Text
		arrow.TextColor3 = Theme.SecondaryText
		list.BackgroundColor3 = Theme.Tertiary
		ls.Color = Theme.Border
		for _, child in ipairs(list:GetChildren()) do
			if child:IsA("TextButton") then
				child.BackgroundColor3 = Theme.Tertiary
				child.Font = Theme.Font
				child.TextColor3 = Theme.Text
			end
		end
	end

	function dd:Set(v, suppress)
		if destroyed then return end
		if value == v then return end
		value = v
		title.Text = (config.Name or "Dropdown") .. ": " .. tostring(v)
		if not suppress then
			changed:Fire(v)
			if config.Callback then task.spawn(config.Callback, v) end
		end
	end

	function dd:Get()
		return value
	end

	function dd:Close()
		forceClose(true)
	end

	function dd:Destroy()
		if destroyed then return end
		destroyed = true
		forceClose(true)
		TweenEngine.CancelOnObject(frame)
		TweenEngine.CancelOnObject(list)
		changed:Destroy()
		cleanup:Destroy()
	end

	function dd:IsDestroyed()
		return destroyed or cleanup:IsDestroyed()
	end

	table.insert(tab.Components, dd)
	return dd
end

-- TEXTBOX
local function CreateTextbox(tab, config)
	config = config or {}
	local cleanup = CreateCleanup()
	local parent = GetParentForComponent(tab)

	local frame = Instance.new("Frame")
	frame.BackgroundColor3 = Theme.Secondary
	frame.BackgroundTransparency = 0.15
	frame.BorderSizePixel = 0
	frame.Size = UDim2.new(1, 0, 0, Theme.ElementHeight)
	frame.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, Theme.CornerRadius)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Border
	stroke.Thickness = 1
	stroke.Transparency = 1
	stroke.Parent = frame

	local box = Instance.new("TextBox")
	box.BackgroundTransparency = 1
	box.Size = UDim2.new(1, -24, 1, 0)
	box.Position = UDim2.new(0, 12, 0, 0)
	box.Font = Theme.FontMono
	box.TextSize = 13
	box.TextColor3 = Theme.Text
	box.PlaceholderColor3 = Theme.MutedText
	box.PlaceholderText = config.Placeholder or "Enter text..."
	box.Text = config.Default or ""
	box.ClearTextOnFocus = false
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.Parent = frame

	if config.MaxLength then
		box:GetPropertyChangedSignal("Text"):Connect(function()
			if #box.Text > config.MaxLength then
				box.Text = string.sub(box.Text, 1, config.MaxLength)
			end
		end)
	end

	local changed = CreateSignal()

	cleanup:AddConnection(box.Focused:Connect(function()
		TweenEngine.Play(stroke, { Color = Theme.Accent, Transparency = 0.2 }, { Duration = 0.15 })
	end))
	cleanup:AddConnection(box.FocusLost:Connect(function(enter)
		TweenEngine.Play(stroke, { Color = Theme.Border, Transparency = 0.5 }, { Duration = 0.15 })
		changed:Fire(box.Text)
		if config.Callback then task.spawn(config.Callback, box.Text, enter) end
	end))

	cleanup:AddInstance(frame)

	local tb = { Frame = frame, Box = box, Cleanup = cleanup, Changed = changed }

	function tb:RefreshTheme()
		if cleanup:IsDestroyed() then return end
		frame.BackgroundColor3 = Theme.Secondary
		stroke.Color = Theme.Border
		box.Font = Theme.FontMono
		box.TextColor3 = Theme.Text
		box.PlaceholderColor3 = Theme.MutedText
	end

	function tb:Set(t, suppress)
		box.Text = t or ""
		if not suppress then
			changed:Fire(box.Text)
		end
	end
	function tb:Get() return box.Text end
	function tb:Clear()
		box.Text = ""
		changed:Fire("")
	end
	function tb:Destroy()
		changed:Destroy()
		cleanup:Destroy()
	end
	function tb:IsDestroyed()
		return cleanup:IsDestroyed()
	end

	table.insert(tab.Components, tb)
	return tb
end

-- KEYBIND (Hardened Toggle / Hold)
local function CreateKeybind(tab, config)
	config = config or {}
	local cleanup = CreateCleanup()
	local key = config.Default or Enum.KeyCode.Unknown
	local mode = config.Mode or "Toggle" -- "Toggle" or "Hold"
	local active = false
	local listening = false
	local destroyed = false
	local parent = GetParentForComponent(tab)

	local frame = Instance.new("Frame")
	frame.BackgroundColor3 = Theme.Secondary
	frame.BackgroundTransparency = 0.15
	frame.BorderSizePixel = 0
	frame.Size = UDim2.new(1, 0, 0, Theme.ElementHeight)
	frame.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, Theme.CornerRadius)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Border
	stroke.Thickness = 1
	stroke.Transparency = 1
	stroke.Parent = frame

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, -80, 1, 0)
	title.Position = UDim2.new(0, 12, 0, 0)
	title.Font = Theme.Font
	title.TextSize = 13
	title.TextColor3 = Theme.Text
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = config.Name or "Keybind"
	title.Parent = frame

	local keyLabel = Instance.new("TextLabel")
	keyLabel.BackgroundColor3 = Theme.Tertiary
	keyLabel.BorderSizePixel = 0
	keyLabel.Size = UDim2.new(0, 60, 0, 22)
	keyLabel.Position = UDim2.new(1, -72, 0.5, -11)
	keyLabel.Font = Theme.FontMono
	keyLabel.TextSize = 11
	keyLabel.TextColor3 = Theme.Text
	keyLabel.Text = (key == Enum.KeyCode.Unknown) and "None" or key.Name
	keyLabel.Parent = frame

	local kc = Instance.new("UICorner")
	kc.CornerRadius = UDim.new(0, 4)
	kc.Parent = keyLabel

	local hit = Instance.new("TextButton")
	hit.BackgroundTransparency = 1
	hit.Size = UDim2.new(1, 0, 1, 0)
	hit.Text = ""
	hit.Parent = frame

	local function stopListening()
		if not listening then return end
		listening = false
		keyLabel.Text = (key == Enum.KeyCode.Unknown) and "None" or key.Name
		TweenEngine.Play(stroke, { Color = Theme.Border }, { Duration = 0.15 })
	end

	cleanup:AddConnection(hit.MouseButton1Click:Connect(function()
		if destroyed then return end
		if listening then
			stopListening()
			return
		end
		listening = true
		keyLabel.Text = "..."
		TweenEngine.Play(stroke, { Color = Theme.Accent }, { Duration = 0.15 })
	end))

	cleanup:AddConnection(UserInputService.InputBegan:Connect(function(input, processed)
		if destroyed then return end
		if processed then return end

		if listening then
			-- Accept keyboard or gamepad buttons for binding
			if input.UserInputType == Enum.UserInputType.Keyboard or input.UserInputType == Enum.UserInputType.Gamepad1 then
				-- Escape cancels rebinding without changing
				if input.KeyCode == Enum.KeyCode.Escape then
					stopListening()
					return
				end
				key = input.KeyCode
				keyLabel.Text = key.Name
				listening = false
				TweenEngine.Play(stroke, { Color = Theme.Border }, { Duration = 0.15 })
				-- Persist toggle-UI key when rebound from Settings
				if config.Name == "Toggle UI" then
					Settings.ToggleUIKey = key.Name
				end
			end
			return
		end

		if key == Enum.KeyCode.Unknown then return end
		if input.KeyCode == key and config.Callback then
			if mode == "Hold" then
				task.spawn(config.Callback, true)
			else
				active = not active
				task.spawn(config.Callback, active)
			end
		end
	end))

	if mode == "Hold" then
		cleanup:AddConnection(UserInputService.InputEnded:Connect(function(input)
			if destroyed then return end
			if key ~= Enum.KeyCode.Unknown and input.KeyCode == key and config.Callback then
				task.spawn(config.Callback, false)
			end
		end))
	end

	cleanup:AddInstance(frame)

	local kb = { Frame = frame, Cleanup = cleanup }

	function kb:RefreshTheme()
		if destroyed or cleanup:IsDestroyed() then return end
		frame.BackgroundColor3 = Theme.Secondary
		stroke.Color = Theme.Border
		title.Font = Theme.Font
		title.TextColor3 = Theme.Text
		keyLabel.BackgroundColor3 = Theme.Tertiary
		keyLabel.Font = Theme.FontMono
		keyLabel.TextColor3 = Theme.Text
	end

	function kb:Set(k)
		if destroyed then return end
		key = k or Enum.KeyCode.Unknown
		keyLabel.Text = (key == Enum.KeyCode.Unknown) and "None" or key.Name
		if listening then stopListening() end
	end

	function kb:Clear()
		self:Set(Enum.KeyCode.Unknown)
	end

	function kb:Get()
		return key
	end

	function kb:IsListening()
		return listening
	end

	function kb:Destroy()
		if destroyed then return end
		destroyed = true
		listening = false
		active = false
		TweenEngine.CancelOnObject(frame)
		TweenEngine.CancelOnObject(stroke)
		cleanup:Destroy()
	end

	table.insert(tab.Components, kb)
	return kb
end

-- DIVIDER
local function CreateDivider(tab)
	local cleanup = CreateCleanup()
	local parent = GetParentForComponent(tab)

	local frame = Instance.new("Frame")
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.new(1, 0, 0, 12)
	frame.Parent = parent

	local line = Instance.new("Frame")
	line.BackgroundColor3 = Theme.Border
	line.BackgroundTransparency = 0.5
	line.BorderSizePixel = 0
	line.Size = UDim2.new(1, 0, 0, 1)
	line.Position = UDim2.new(0, 0, 0.5, 0)
	line.Parent = frame

	cleanup:AddInstance(frame)

	local div = { Frame = frame, Cleanup = cleanup }
	function div:RefreshTheme()
		if cleanup:IsDestroyed() then return end
		line.BackgroundColor3 = Theme.Border
	end
	function div:Destroy() cleanup:Destroy() end
	table.insert(tab.Components, div)
	return div
end

----------------------------------------------------------------
-- TAB
----------------------------------------------------------------
local SIDEBAR_W_DEFAULT = 104
local TITLE_H = 40

local function CreateTab(window, config)
	config = config or {}
	local cleanup = CreateCleanup()
	local name = config.Name or "Tab"

	local content = Instance.new("ScrollingFrame")
	content.Name = "TabContent_" .. name
	content.BackgroundTransparency = 1
	content.BorderSizePixel = 0
	content.Size = UDim2.new(1, 0, 1, 0)
	content.Active = true
	content.ScrollingEnabled = true
	content.ScrollingDirection = Enum.ScrollingDirection.Y
	content.ElasticBehavior = Enum.ElasticBehavior.WhenScrollable
	content.ClipsDescendants = true
	content.CanvasPosition = Vector2.new(0, 0)
	content.CanvasSize = UDim2.new(0, 0, 0, 0)
	content.AutomaticCanvasSize = Enum.AutomaticSize.None
	content.ScrollBarThickness = UserInputService.TouchEnabled and 5 or 3
	content.ScrollBarImageColor3 = Theme.Border
	content.ScrollBarImageTransparency = 0.2
	content.Visible = false
	content.Parent = window.ContentContainer

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 10)
	padding.PaddingBottom = UDim.new(0, 10)
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 12)
	padding.Parent = content

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 8)
	layout.Parent = content

	local TOP_BOTTOM = 20
	local function updateCanvasSize()
		if content.Parent == nil then return end
		local h = layout.AbsoluteContentSize.Y + TOP_BOTTOM
		local vh = content.AbsoluteSize.Y
		content.CanvasSize = UDim2.new(0, 0, 0, math.max(h, vh))
	end
	cleanup:AddConnection(layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateCanvasSize))
	cleanup:AddConnection(content:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateCanvasSize))
	task.defer(updateCanvasSize)

	-- Sidebar tab button (vertical list)
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
	tabBtn.ClipsDescendants = true
	tabBtn.Parent = window.TabBar

	-- Padding so long text never overlaps the left indicator
	local btnPad = Instance.new("UIPadding")
	btnPad.PaddingLeft = UDim.new(0, 16)
	btnPad.PaddingRight = UDim.new(0, 4)
	btnPad.Parent = tabBtn

	-- White indicator further left, clear of tab text
	local indicator = Instance.new("Frame")
	indicator.Name = "Indicator"
	indicator.BackgroundColor3 = Theme.Accent
	indicator.BorderSizePixel = 0
	indicator.Size = UDim2.new(0, 2, 0.55, 0)
	indicator.Position = UDim2.new(0, -6, 0.225, 0)
	indicator.Visible = false
	indicator.ZIndex = 2
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
			tabBtn.BackgroundTransparency = 0.35
			tabBtn.BackgroundColor3 = Theme.Secondary
			tabBtn.TextColor3 = Theme.Text
			indicator.Visible = false
		else
			content.Visible = false
			-- close dropdowns so list never floats on another tab
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
		tabBtn.BackgroundColor3 = Theme.Secondary
		tabBtn.Font = Theme.Font
		indicator.BackgroundColor3 = Theme.Accent
		if content.Visible then
			tabBtn.BackgroundTransparency = 0.35
			tabBtn.TextColor3 = Theme.Text
			indicator.Visible = false
		else
			tabBtn.BackgroundTransparency = 1
			tabBtn.TextColor3 = Theme.SecondaryText
			indicator.Visible = false
		end
		for _, s in ipairs(tab.Sections) do
			if s.RefreshTheme then s:RefreshTheme() end
		end
		for _, c in ipairs(tab.Components) do
			if c.RefreshTheme then c:RefreshTheme() end
		end
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

	function tab:Destroy()
		for _, c in ipairs(tab.Components) do
			if c.Destroy then c:Destroy() end
		end
		for _, s in ipairs(tab.Sections) do
			if s.Destroy then s:Destroy() end
		end
		cleanup:Destroy()
	end

	return tab
end

----------------------------------------------------------------
-- SETTINGS TAB (auto-attached to every window)
----------------------------------------------------------------
local function SetupSettingsTab(window)
	if not window or window._SettingsReady then return end
	window._SettingsReady = true

	local settingsTab = window:CreateTab({ Name = "Settings" })
	settingsTab:CreateSection({ Name = "Profile" })

	-- Profile card (avatar + name + country)
	do
		local parent = GetParentForComponent(settingsTab)
		local card = Instance.new("Frame")
		card.Name = "ProfileCard"
		card.BackgroundColor3 = Theme.Secondary
		card.BackgroundTransparency = 0.1
		card.BorderSizePixel = 0
		card.Size = UDim2.new(1, 0, 0, 72)
		card.Parent = parent

		local stroke = Instance.new("UIStroke")
		stroke.Color = Theme.Border
		stroke.Thickness = 1
		stroke.Transparency = 1
		stroke.Parent = card

		local avatar = Instance.new("ImageLabel")
		avatar.Name = "Avatar"
		avatar.BackgroundColor3 = Theme.Tertiary
		avatar.BorderSizePixel = 0
		avatar.Size = UDim2.new(0, 48, 0, 48)
		avatar.Position = UDim2.new(0, 12, 0.5, -24)
		avatar.Image = ""
		avatar.ScaleType = Enum.ScaleType.Crop
		avatar.Parent = card

		local avCorner = Instance.new("UICorner")
		avCorner.CornerRadius = UDim.new(1, 0)
		avCorner.Parent = avatar

		local nameLabel = Instance.new("TextLabel")
		nameLabel.BackgroundTransparency = 1
		nameLabel.Size = UDim2.new(1, -76, 0, 18)
		nameLabel.Position = UDim2.new(0, 70, 0, 16)
		nameLabel.Font = Theme.FontBold
		nameLabel.TextSize = 14
		nameLabel.TextColor3 = Theme.Text
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.Text = LocalPlayer.DisplayName or LocalPlayer.Name
		nameLabel.Parent = card

		local userLabel = Instance.new("TextLabel")
		userLabel.BackgroundTransparency = 1
		userLabel.Size = UDim2.new(1, -76, 0, 14)
		userLabel.Position = UDim2.new(0, 70, 0, 36)
		userLabel.Font = Theme.Font
		userLabel.TextSize = 12
		userLabel.TextColor3 = Theme.SecondaryText
		userLabel.TextXAlignment = Enum.TextXAlignment.Left
		userLabel.Text = "@" .. tostring(LocalPlayer.Name)
		userLabel.Parent = card

		local countryLabel = Instance.new("TextLabel")
		countryLabel.BackgroundTransparency = 1
		countryLabel.Size = UDim2.new(1, -76, 0, 14)
		countryLabel.Position = UDim2.new(0, 70, 0, 52)
		countryLabel.Font = Theme.Font
		countryLabel.TextSize = 11
		countryLabel.TextColor3 = Theme.MutedText
		countryLabel.TextXAlignment = Enum.TextXAlignment.Left
		countryLabel.Text = "Country: ..."
		countryLabel.Parent = card

		task.spawn(function()
			local ok, url = pcall(function()
				return Players:GetUserThumbnailAsync(
					LocalPlayer.UserId,
					Enum.ThumbnailType.HeadShot,
					Enum.ThumbnailSize.Size150x150
				)
			end)
			if ok and url and avatar and avatar.Parent then
				avatar.Image = url
			end
		end)

		task.spawn(function()
			local country = "Unknown"
			local ok, code = pcall(function()
				return LocalizationService:GetCountryRegionForPlayerAsync(LocalPlayer)
			end)
			if ok and type(code) == "string" and #code > 0 then
				country = code
			end
			if countryLabel and countryLabel.Parent then
				countryLabel.Text = "Country: " .. tostring(country)
			end
		end)

		-- theme refresh hook for card
		local unhook = OnThemeChange(function()
			if not card or not card.Parent then return end
			card.BackgroundColor3 = Theme.Secondary
			stroke.Color = Theme.Border
			avatar.BackgroundColor3 = Theme.Tertiary
			nameLabel.TextColor3 = Theme.Text
			nameLabel.Font = Theme.FontBold
			userLabel.TextColor3 = Theme.SecondaryText
			userLabel.Font = Theme.Font
			countryLabel.TextColor3 = Theme.MutedText
			countryLabel.Font = Theme.Font
		end)
		window.Cleanup:AddCallback(unhook)
		window.Cleanup:AddInstance(card)
	end

	settingsTab:CreateSection({ Name = "Appearance" })

	-- Theme dropdown
	local themeNames = { "Dark", "Light", "Neon" }
	local currentTheme = Settings.Theme or "Dark"
	if not table.find(themeNames, currentTheme) then
		currentTheme = "Dark"
	end
	-- apply saved theme once
	pcall(function() ApplyThemePreset(currentTheme) end)

	settingsTab:CreateDropdown({
		Name = "Theme",
		Options = themeNames,
		Default = currentTheme,
		Callback = function(v)
			Settings.Theme = v
			ApplyThemePreset(v)
			Library:Notify({
				Title = "Theme",
				Description = "Applied " .. tostring(v),
				Duration = 2,
				Type = "Success",
			})
		end,
	})

	settingsTab:CreateSection({ Name = "Controls" })

	-- UI visibility (full hide / show — not minimize)
	window._UIVisible = Settings.UIVisible ~= false
	if window.Gui then
		window.Gui.Enabled = window._UIVisible
	end

	function window:SetUIVisible(state)
		window._UIVisible = state and true or false
		Settings.UIVisible = window._UIVisible
		if window.Gui then
			window.Gui.Enabled = window._UIVisible
		end
	end

	function window:ToggleUIVisible()
		window:SetUIVisible(not window._UIVisible)
	end

	local defaultKey = KeyCodeFromName(Settings.ToggleUIKey or "X")
	if defaultKey == Enum.KeyCode.Unknown then
		defaultKey = Enum.KeyCode.X
	end

	local kb = settingsTab:CreateKeybind({
		Name = "Toggle UI",
		Default = defaultKey,
		Mode = "Toggle",
		Callback = function()
			-- Keybind component fires with active bool for Toggle mode;
			-- we always just flip visibility.
			window:ToggleUIVisible()
		end,
	})

	-- Keep Settings in sync when user rebinds
	do
		local oldSet = kb.Set
		function kb:Set(k)
			if oldSet then oldSet(self, k) end
			local name = (k and k ~= Enum.KeyCode.Unknown) and k.Name or "X"
			Settings.ToggleUIKey = name
		end
	end

	-- Also listen at window level so hide/show works even when keybind component is destroyed
	-- (covers the case where UI is hidden and we need the same key to bring it back)
	local uiKey = defaultKey
	local function refreshUiKey()
		uiKey = KeyCodeFromName(Settings.ToggleUIKey or "X")
		if uiKey == Enum.KeyCode.Unknown then
			uiKey = Enum.KeyCode.X
		end
	end
	refreshUiKey()

	local uiToggleConn = UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
		refreshUiKey()
		if input.KeyCode == uiKey then
			-- Avoid double-fire with keybind callback when UI is visible:
			-- only handle here when GUI is currently disabled (hidden)
			if window.Gui and not window.Gui.Enabled then
				window:SetUIVisible(true)
			end
		end
	end)
	window.Cleanup:AddConnection(uiToggleConn)

	-- When keybind fires while visible it toggles via Callback above.
	-- Patch keybind so Settings.ToggleUIKey always updates on rebind via InputBegan inside CreateKeybind.
	-- Hook after key is set by listening to the key label changes is fragile; instead wrap Get.
	-- Save button
	settingsTab:CreateButton({
		Name = "Save Settings",
		Callback = function()
			-- pull current key from keybind if possible
			if kb and kb.Get then
				local k = kb:Get()
				if k and k ~= Enum.KeyCode.Unknown then
					Settings.ToggleUIKey = k.Name
				end
			end
			local ok = ConfigSave()
			Library:Notify({
				Title = ok and "Saved" or "Save Failed",
				Description = ok and "Settings written to " .. CONFIG_FILE or "writefile unavailable",
				Duration = 3,
				Type = ok and "Success" or "Error",
			})
		end,
	})

	settingsTab:CreateButton({
		Name = "Reset Settings",
		Callback = function()
			for k, v in pairs(DefaultSettings) do
				Settings[k] = v
			end
			ApplyThemePreset(Settings.Theme)
			if kb and kb.Set then
				kb:Set(KeyCodeFromName(Settings.ToggleUIKey))
			end
			window:SetUIVisible(true)
			Library:Notify({
				Title = "Reset",
				Description = "Settings restored to defaults",
				Duration = 2,
				Type = "Info",
			})
		end,
	})

	return settingsTab
end

----------------------------------------------------------------
-- WINDOW (sidebar layout — matches expected design)
----------------------------------------------------------------
-- Fit window size to the player's screen (phone portrait / landscape / tablet / PC)
local function ComputeResponsiveSize(config)
	config = config or {}
	local cam = workspace.CurrentCamera
	local vp = (cam and cam.ViewportSize) or Vector2.new(1280, 720)
	local vw, vh = vp.X, vp.Y
	local isTouch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	local isPortrait = vh > vw
	local shortest = math.min(vw, vh)
	local longest = math.max(vw, vh)

	-- User override always wins
	if config.Width and config.Height then
		local w = math.clamp(config.Width, 280, vw - 16)
		local h = math.clamp(config.Height, 180, vh - 16)
		return w, h, isTouch, isPortrait
	end

	local w, h
	if isTouch then
		if isPortrait then
			-- Phone upright: almost full width, moderate height (not a tall strip)
			w = math.floor(vw * 0.92)
			h = math.floor(math.clamp(vh * 0.42, 240, math.min(360, vh * 0.5)))
		else
			-- Phone / tablet landscape (flat game phones)
			w = math.floor(math.clamp(vw * 0.55, 400, math.min(620, vw - 24)))
			h = math.floor(math.clamp(vh * 0.72, 220, math.min(340, vh - 24)))
		end
	else
		-- PC / large display
		w = config.Width or 540
		h = config.Height or 300
		w = math.clamp(w, 400, math.min(720, vw - 40))
		h = math.clamp(h, 260, math.min(420, vh - 40))
	end

	-- Never taller than wide on landscape devices; allow slightly tall only in true portrait
	if not isPortrait and h > w * 0.75 then
		h = math.floor(w * 0.55)
	end

	w = math.floor(math.clamp(w, 280, vw - 12))
	h = math.floor(math.clamp(h, 180, vh - 12))
	return w, h, isTouch, isPortrait
end

local function CreateWindow(library, config)
	config = config or {}
	local cleanup = CreateCleanup()
	local width, height, isTouch, isPortrait = ComputeResponsiveSize(config)
	local minimized = false
	local tabs = {}
	local activeTab = nil
	local aspect = nil

	local gui = Instance.new("ScreenGui")
	gui.Name = "VeyraUI_" .. (config.Title or "Window")
	gui.DisplayOrder = 50
	gui.IgnoreGuiInset = true
	ProtectAndParent(gui)

	local root = Instance.new("Frame")
	root.Name = "Root"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromOffset(width, height)
	root.AnchorPoint = Vector2.new(0, 0)
	root.Position = UDim2.new(0.5, -width / 2, 0.5, -height / 2)
	root.ClipsDescendants = true
	root.Parent = gui

	-- Soft UI scale on very small phones so text/controls stay usable
	local uiScale = Instance.new("UIScale")
	uiScale.Name = "VeyraScale"
	local shortest = math.min(
		(workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize.X) or 1280,
		(workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize.Y) or 720
	)
	if isTouch and shortest < 500 then
		uiScale.Scale = 0.92
	elseif isTouch then
		uiScale.Scale = 0.96
	else
		uiScale.Scale = 1
	end
	uiScale.Parent = root

	local sizeConstraint = Instance.new("UISizeConstraint")
	local vp = (workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize) or Vector2.new(1280, 720)
	sizeConstraint.MinSize = Vector2.new(math.min(300, vp.X - 8), math.min(180, vp.Y - 8))
	sizeConstraint.MaxSize = Vector2.new(math.min(900, vp.X - 8), math.min(560, vp.Y - 8))
	sizeConstraint.Parent = root

	local main = Instance.new("Frame")
	main.Name = "Main"
	main.BackgroundColor3 = Theme.Background
	main.BackgroundTransparency = 0.02
	main.BorderSizePixel = 0
	main.Size = UDim2.new(1, 0, 1, 0)
	main.Parent = root

	-- No main corner (sharp frame)

	local mainStroke = Instance.new("UIStroke")
	mainStroke.Color = Theme.Border
	mainStroke.Thickness = 1
	mainStroke.Transparency = 1
	mainStroke.Parent = main

	-- Left-edge white accent line (matches reference)
	local outline = Instance.new("Frame")
	outline.Name = "OutlineAccent"
	outline.BackgroundColor3 = Theme.OutlineAccent or Color3.fromRGB(255, 255, 255)
	outline.BackgroundTransparency = 1
	outline.BorderSizePixel = 0
	outline.Size = UDim2.new(0, 2, 1, 0)
	outline.Position = UDim2.new(0, 0, 0, 0)
	outline.ZIndex = 5
	outline.Parent = main
	outline.Visible = false

	-- Title bar (full width)
	local titleBar = Instance.new("Frame")
	titleBar.Name = "TitleBar"
	titleBar.BackgroundColor3 = Theme.Secondary
	titleBar.BackgroundTransparency = 0.15
	titleBar.BorderSizePixel = 0
	titleBar.Size = UDim2.new(1, 0, 0, TITLE_H)
	titleBar.ZIndex = 3
	titleBar.Parent = main

	-- No title corner

	local titleFix = Instance.new("Frame")
	titleFix.BackgroundColor3 = Theme.Secondary
	titleFix.BackgroundTransparency = 0.15
	titleFix.BorderSizePixel = 0
	titleFix.Size = UDim2.new(1, 0, 0, 12)
	titleFix.Position = UDim2.new(0, 0, 1, -12)
	titleFix.Parent = titleBar

	local titleLabel = Instance.new("TextLabel")
	titleLabel.BackgroundTransparency = 1
	titleLabel.Size = UDim2.new(1, -90, 0, 16)
	titleLabel.Position = UDim2.new(0, 14, 0, 5)
	titleLabel.Font = Theme.FontBold
	titleLabel.TextSize = 13
	titleLabel.TextColor3 = Theme.Text
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.Text = config.Title or "Veyra"
	titleLabel.Parent = titleBar

	local subtitle = Instance.new("TextLabel")
	subtitle.BackgroundTransparency = 1
	subtitle.Size = UDim2.new(1, -90, 0, 12)
	subtitle.Position = UDim2.new(0, 14, 0, 21)
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
	closeBtn.TextSize = 15
	closeBtn.TextColor3 = Theme.SecondaryText
	closeBtn.Text = "×"
	closeBtn.ZIndex = 15
	closeBtn.Active = true
	closeBtn.Parent = titleBar

	local minBtn = Instance.new("TextButton")
	minBtn.BackgroundTransparency = 1
	minBtn.Size = UDim2.new(0, 28, 0, 28)
	minBtn.Position = UDim2.new(1, -58, 0.5, -14)
	minBtn.Font = Enum.Font.GothamBold
	minBtn.TextSize = 14
	minBtn.TextColor3 = Theme.SecondaryText
	minBtn.Text = "−"
	minBtn.ZIndex = 15
	minBtn.Active = true
	minBtn.Parent = titleBar

	-- Body under title: sidebar + content
	local body = Instance.new("Frame")
	body.Name = "Body"
	body.BackgroundTransparency = 1
	body.Size = UDim2.new(1, 0, 1, -TITLE_H)
	body.Position = UDim2.new(0, 0, 0, TITLE_H)
	body.ClipsDescendants = true
	body.Parent = main

	-- Sidebar width scales down on narrow phones
	local SIDEBAR_W = SIDEBAR_W_DEFAULT
	if isTouch then
		if width < 400 then
			SIDEBAR_W = 88
		elseif width < 480 then
			SIDEBAR_W = 96
		end
	end

	-- Left sidebar
	local sidebar = Instance.new("Frame")
	sidebar.Name = "Sidebar"
	sidebar.BackgroundColor3 = Theme.Secondary
	sidebar.BackgroundTransparency = 0.35
	sidebar.BorderSizePixel = 0
	sidebar.Size = UDim2.new(0, SIDEBAR_W, 1, 0)
	sidebar.Parent = body

	local searchBox = Instance.new("TextBox")
	searchBox.Name = "Search"
	searchBox.BackgroundColor3 = Theme.Tertiary
	searchBox.BackgroundTransparency = 0.2
	searchBox.BorderSizePixel = 0
	-- Same width as tab buttons (1, -8)
	searchBox.Size = UDim2.new(1, -8, 0, 26)
	searchBox.Position = UDim2.new(0, 4, 0, 8)
	searchBox.Font = Theme.Font
	searchBox.TextSize = 11
	searchBox.TextColor3 = Theme.Text
	searchBox.PlaceholderColor3 = Theme.MutedText
	searchBox.PlaceholderText = "Search"
	searchBox.Text = ""
	searchBox.ClearTextOnFocus = false
	searchBox.Parent = sidebar
	-- No search corner
	local searchPad = Instance.new("UIPadding")
	searchPad.PaddingLeft = UDim.new(0, 8)
	searchPad.PaddingRight = UDim.new(0, 8)
	searchPad.Parent = searchBox

	-- Vertical tab list (scrollable if many)
	local tabBar = Instance.new("ScrollingFrame")
	tabBar.Name = "TabBar"
	tabBar.BackgroundTransparency = 1
	tabBar.BorderSizePixel = 0
	tabBar.Size = UDim2.new(1, 0, 1, -42)
	tabBar.Position = UDim2.new(0, 0, 0, 40)
	tabBar.CanvasSize = UDim2.new(0, 0, 0, 0)
	tabBar.AutomaticCanvasSize = Enum.AutomaticSize.Y
	tabBar.ScrollBarThickness = 0
	tabBar.ScrollingDirection = Enum.ScrollingDirection.Y
	tabBar.Active = true
	tabBar.Parent = sidebar

	local tabLayout = Instance.new("UIListLayout")
	tabLayout.FillDirection = Enum.FillDirection.Vertical
	tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tabLayout.Padding = UDim.new(0, 3)
	tabLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	tabLayout.Parent = tabBar

	local tabPad = Instance.new("UIPadding")
	tabPad.PaddingTop = UDim.new(0, 2)
	tabPad.PaddingBottom = UDim.new(0, 6)
	tabPad.Parent = tabBar

	-- Right content area
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
		Outline = outline,
		TitleBar = titleBar,
		Body = body,
		Sidebar = sidebar,
		TabBar = tabBar,
		ContentContainer = contentContainer,
		SearchBox = searchBox,
		Tabs = tabs,
		Width = width,
		Height = height,
		Aspect = aspect,
		Cleanup = cleanup,
		Actions = {},
	}

	-- Search filters sidebar tab buttons (works while typing)
	local function filterTabs()
		local raw = searchBox.Text or ""
		local q = string.lower((string.gsub(raw, "^%s+", "")))
		q = (string.gsub(q, "%s+$", ""))
		for _, tab in ipairs(tabs) do
			local btn = tab.Button
			if btn and btn.Parent then
				local name = string.lower(tostring(tab.Name or btn.Text or ""))
				local show = (q == "") or (string.find(name, q, 1, true) ~= nil)
				btn.Visible = show
			end
		end
	end
	cleanup:AddConnection(searchBox:GetPropertyChangedSignal("Text"):Connect(filterTabs))
	cleanup:AddConnection(searchBox.FocusLost:Connect(filterTabs))
	-- Mobile keyboards sometimes only fire on change + defer
	cleanup:AddConnection(searchBox:GetPropertyChangedSignal("Text"):Connect(function()
		task.defer(filterTabs)
	end))
	searchBox.ClearTextOnFocus = false
	searchBox.TextEditable = true

	local drag = MakeDraggable(titleBar, root)
	cleanup:AddCallback(function() drag:Destroy() end)

	cleanup:AddConnection(closeBtn.MouseButton1Click:Connect(function()
		window:Close()
	end))
	cleanup:AddConnection(minBtn.MouseButton1Click:Connect(function()
		window:ToggleMinimize()
	end))

	-- Resize: right edge (width), bottom edge (height), corner (both)
	local function makeResizeHandle(name, size, pos, mode)
		local btn = Instance.new("TextButton")
		btn.Name = name
		btn.BackgroundTransparency = 1
		btn.Text = ""
		btn.Size = size
		btn.Position = pos
		btn.ZIndex = 25
		btn.AutoButtonColor = false
		btn.Parent = main
		cleanup:AddConnection(btn.InputBegan:Connect(function(input)
			if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
				return
			end
			if minimized then return end
			local startInput = input.Position
			local startSize = root.AbsoluteSize
			local moveC, endC
			moveC = UserInputService.InputChanged:Connect(function(inp)
				if inp.UserInputType ~= Enum.UserInputType.MouseMovement and inp.UserInputType ~= Enum.UserInputType.Touch then
					return
				end
				local dx = inp.Position.X - startInput.X
				local dy = inp.Position.Y - startInput.Y
				local newW = startSize.X
				local newH = startSize.Y
				if mode == "right" or mode == "corner" then
					newW = math.clamp(startSize.X + dx, 360, 900)
				end
				if mode == "bottom" or mode == "corner" then
					newH = math.clamp(startSize.Y + dy, 220, 560)
				end
				root.Size = UDim2.fromOffset(newW, newH)
				window.Width = newW
				window.Height = newH
			end)
			endC = UserInputService.InputEnded:Connect(function(inp)
				if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
					if moveC then moveC:Disconnect() end
					if endC then endC:Disconnect() end
				end
			end)
		end))
		return btn
	end

	-- Mobile-friendly: ONLY bottom-right corner (no side/bottom edge grips)
	local resizeGrip = makeResizeHandle("ResizeGrip", UDim2.new(0, 22, 0, 22), UDim2.new(1, -22, 1, -22), "corner")

	local gripVisual = Instance.new("Frame")
	gripVisual.BackgroundColor3 = Theme.Border
	gripVisual.BackgroundTransparency = 0.3
	gripVisual.BorderSizePixel = 0
	gripVisual.Size = UDim2.new(0, 10, 0, 2)
	gripVisual.Position = UDim2.new(1, -12, 1, -6)
	gripVisual.Rotation = -45
	gripVisual.ZIndex = 26
	gripVisual.Parent = main
	local grip2 = gripVisual:Clone()
	grip2.Position = UDim2.new(1, -8, 1, -6)
	grip2.Parent = main

	-- Open animation (original TweenEngine)
	root.Size = UDim2.fromOffset(0, 0)
	main.BackgroundTransparency = 1
	TweenEngine.Play(root, {
		Size = UDim2.fromOffset(width, height),
	}, { Duration = 0.4, Easing = "BackOut" })
	TweenEngine.Play(main, { BackgroundTransparency = 0.02 }, { Duration = 0.32, Easing = "QuadOut" })

	cleanup:AddInstance(gui)

	-- Re-fit when phone rotates or resolution changes
	local function refitToViewport(forceSize)
		if minimized or cleanup:IsDestroyed() then return end
		local cam = workspace.CurrentCamera
		if not cam then return end
		local vp = cam.ViewportSize
		if forceSize then
			local nw, nh = ComputeResponsiveSize(config)
			width, height = nw, nh
			window.Width, window.Height = nw, nh
			root.Size = UDim2.fromOffset(nw, nh)
		else
			-- Clamp current size into new viewport
			local nw = math.clamp(root.AbsoluteSize.X, 280, math.max(280, vp.X - 12))
			local nh = math.clamp(root.AbsoluteSize.Y, 180, math.max(180, vp.Y - 12))
			root.Size = UDim2.fromOffset(nw, nh)
			window.Width, window.Height = nw, nh
		end
		-- Keep centered
		local aw = root.AbsoluteSize.X
		local ah = root.AbsoluteSize.Y
		root.Position = UDim2.new(0.5, -aw / 2, 0.5, -ah / 2)
		if sizeConstraint then
			sizeConstraint.MinSize = Vector2.new(math.min(300, vp.X - 8), math.min(180, vp.Y - 8))
			sizeConstraint.MaxSize = Vector2.new(math.min(900, vp.X - 8), math.min(560, vp.Y - 8))
		end
	end

	if workspace.CurrentCamera then
		cleanup:AddConnection(workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			task.defer(function()
				refitToViewport(true)
			end)
		end))
	end
	cleanup:AddConnection(workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		local cam = workspace.CurrentCamera
		if cam then
			cleanup:AddConnection(cam:GetPropertyChangedSignal("ViewportSize"):Connect(function()
				task.defer(function()
					refitToViewport(true)
				end)
			end))
			task.defer(function() refitToViewport(true) end)
		end
	end))

	local function refreshWindowTheme()
		if cleanup:IsDestroyed() then return end
		main.BackgroundColor3 = Theme.Background
		mainStroke.Color = Theme.Border
		titleBar.BackgroundColor3 = Theme.Secondary
		titleFix.BackgroundColor3 = Theme.Secondary
		titleLabel.TextColor3 = Theme.Text
		titleLabel.Font = Theme.FontBold
		subtitle.TextColor3 = Theme.SecondaryText
		subtitle.Font = Theme.Font
		closeBtn.TextColor3 = Theme.SecondaryText
		minBtn.TextColor3 = Theme.SecondaryText
		sidebar.BackgroundColor3 = Theme.Secondary
		searchBox.BackgroundColor3 = Theme.Tertiary
		searchBox.TextColor3 = Theme.Text
		searchBox.PlaceholderColor3 = Theme.MutedText
		searchBox.Font = Theme.Font
		outline.BackgroundColor3 = Theme.OutlineAccent or Color3.fromRGB(255, 255, 255)
		for _, tab in ipairs(tabs) do
			if tab.RefreshTheme then tab:RefreshTheme() end
		end
	end
	cleanup:AddCallback(OnThemeChange(refreshWindowTheme))

	function window:AddAction(actionConfig)
		actionConfig = actionConfig or {}
		local name = actionConfig.Name or "Action"
		local icon = actionConfig.Icon
		local callback = actionConfig.Callback
		if not window._ActionBar then
			window._ActionBar = Instance.new("Frame")
			window._ActionBar.Name = "ActionBar"
			window._ActionBar.BackgroundTransparency = 1
			window._ActionBar.Size = UDim2.new(0, 0, 0, 26)
			window._ActionBar.Position = UDim2.new(1, -64, 0.5, -13)
			window._ActionBar.AnchorPoint = Vector2.new(1, 0)
			window._ActionBar.ZIndex = 4
			window._ActionBar.Parent = titleBar
			local al = Instance.new("UIListLayout")
			al.FillDirection = Enum.FillDirection.Horizontal
			al.HorizontalAlignment = Enum.HorizontalAlignment.Right
			al.Padding = UDim.new(0, 4)
			al.Parent = window._ActionBar
		end
		local actionBar = window._ActionBar
		local btn = Instance.new("TextButton")
		btn.BackgroundColor3 = Theme.Tertiary
		btn.BackgroundTransparency = 0.3
		btn.BorderSizePixel = 0
		btn.Size = UDim2.new(0, 24, 0, 24)
		btn.AutoButtonColor = false
		btn.Text = ""
		btn.ZIndex = 5
		btn.Parent = actionBar
		-- sharp action buttons
		if icon and tostring(icon) ~= "" then
			local img = Instance.new("ImageLabel")
			img.BackgroundTransparency = 1
			img.Size = UDim2.new(0, 14, 0, 14)
			img.Position = UDim2.new(0.5, -7, 0.5, -7)
			img.Image = tostring(icon)
			img.Parent = btn
		else
			local lbl = Instance.new("TextLabel")
			lbl.BackgroundTransparency = 1
			lbl.Size = UDim2.new(1, 0, 1, 0)
			lbl.Font = Theme.FontBold
			lbl.TextSize = 10
			lbl.TextColor3 = Theme.Text
			lbl.Text = string.sub(name, 1, 1)
			lbl.Parent = btn
		end
		btn.MouseEnter:Connect(function()
			TweenEngine.Play(btn, { BackgroundTransparency = 0.1 }, { Duration = 0.1 })
		end)
		btn.MouseLeave:Connect(function()
			TweenEngine.Play(btn, { BackgroundTransparency = 0.3 }, { Duration = 0.1 })
		end)
		btn.MouseButton1Click:Connect(function()
			if callback then task.spawn(callback) end
		end)
		task.defer(function()
			local total = 0
			for _, ch in ipairs(actionBar:GetChildren()) do
				if ch:IsA("GuiObject") then total += ch.AbsoluteSize.X + 4 end
			end
			actionBar.Size = UDim2.new(0, math.max(total, 0), 0, 26)
		end)
		local act = { Button = btn, Name = name }
		table.insert(window.Actions, act)
		return act
	end

	function window:CreateTab(c)
		local tab = CreateTab(window, c)
		table.insert(tabs, tab)
		if not activeTab then
			window:SelectTab(tab)
		end
		return tab
	end

	function window:SelectTab(tab)
		if activeTab == tab then return end
		if activeTab then activeTab:SetActive(false) end
		activeTab = tab
		tab:SetActive(true)
	end

	function window:RefreshTheme()
		refreshWindowTheme()
	end

	-- Exact original TweenEngine minimize / close
	function window:ToggleMinimize()
		minimized = not minimized
		local grip = main:FindFirstChild("ResizeGrip")
		local gripR = main:FindFirstChild("ResizeRight")
		local gripB = main:FindFirstChild("ResizeBottom")
		if minimized then
			-- Use Size offsets (NOT AbsoluteSize) so UIScale does not shrink width
			local w = root.Size.X.Offset
			if w < 100 then
				w = window.Width or 540
			end
			local h = root.Size.Y.Offset
			if h < 40 then
				h = window.Height or 300
			end
			window.Width = w
			window.Height = h
			if sizeConstraint then sizeConstraint.Parent = nil end
			body.Visible = false
			sidebar.Visible = false
			contentContainer.Visible = false
			if grip then grip.Visible = false end
			if gripR then gripR.Visible = false end
			if gripB then gripB.Visible = false end
			TweenEngine.CancelOnObject(root)
			TweenEngine.CancelOnObject(main)
			-- Width stays EXACTLY the same — only height collapses to title bar
			TweenEngine.Play(root, {
				Size = UDim2.new(0, w, 0, TITLE_H),
			}, { Duration = 0.3, Easing = "QuadOut" })
		else
			local w = window.Width
			local h = window.Height
			TweenEngine.CancelOnObject(root)
			TweenEngine.CancelOnObject(main)
			TweenEngine.Play(root, {
				Size = UDim2.new(0, w, 0, h),
			}, {
				Duration = 0.35,
				Easing = "BackOut",
				OnComplete = function()
					body.Visible = true
					sidebar.Visible = true
					contentContainer.Visible = true
					if grip then grip.Visible = true end
					if gripR then gripR.Visible = true end
					if gripB then gripB.Visible = true end
					if sizeConstraint and not sizeConstraint.Parent then sizeConstraint.Parent = root end
				end,
			})
		end
	end

	function window:Close()
		TweenEngine.CancelOnObject(root)
		TweenEngine.CancelOnObject(main)
		TweenEngine.Play(root, {
			Size = UDim2.new(0, 0, 0, 0),
		}, {
			Duration = 0.3,
			Easing = "QuadIn",
			OnComplete = function()
				window:Destroy()
			end,
		})
		TweenEngine.Play(main, {
			Size = UDim2.new(0, 0, 0, 0),
			BackgroundTransparency = 1,
		}, { Duration = 0.3, Easing = "QuadIn" })
	end

	function window:Destroy()
		-- cancel tweens on this window tree
		pcall(function() TweenEngine.CancelOnObject(root) end)
		pcall(function() TweenEngine.CancelOnObject(main) end)
		for _, tab in ipairs(tabs) do
			pcall(function()
				if tab.Destroy then tab:Destroy() end
			end)
		end
		table.clear(tabs)
		pcall(function() cleanup:Destroy() end)
		-- destroy gui root
		pcall(function()
			if gui then gui:Destroy() end
		end)
		-- drop from global Windows list
		pcall(function()
			local idx = table.find(Windows, window)
			if idx then table.remove(Windows, idx) end
		end)
		-- if no windows left, wipe notifications to prevent leaks
		pcall(function()
			if #Windows == 0 and NotifManager then
				NotifManager:Clear()
			end
		end)
	end

	-- Auto Settings tab (theme, toggle-UI keybind, profile)
	pcall(function()
		SetupSettingsTab(window)
	end)

	return window
end



----------------------------------------------------------------
-- INTRO (optional)
----------------------------------------------------------------
local function PlayIntro(config)
	config = config or {}
	local duration = config.Duration or 1.5
	local titleText = config.Title or "Veyra"
	local subtitleText = config.Subtitle or ""
	local logoId = config.Logo
	local cleanup = CreateCleanup()
	local gui = Instance.new("ScreenGui")
	gui.Name = "VeyraIntro"
	gui.DisplayOrder = 2147483647
	gui.IgnoreGuiInset = true
	ProtectAndParent(gui)
	cleanup:AddInstance(gui)
	local overlay = Instance.new("Frame")
	overlay.BackgroundColor3 = Color3.fromRGB(8, 8, 12)
	overlay.BorderSizePixel = 0
	overlay.Size = UDim2.new(1, 0, 1, 0)
	overlay.Parent = gui
	local center = Instance.new("Frame")
	center.BackgroundTransparency = 1
	center.Size = UDim2.new(0, 220, 0, 120)
	center.Position = UDim2.new(0.5, -110, 0.5, -60)
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
		TweenEngine.Play(logo, { ImageTransparency = 0 }, { Duration = 0.4, Easing = "QuadOut" })
	end
	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, 0, 0, 28)
	title.Position = UDim2.new(0, 0, 0, logoId and 56 or 20)
	title.Font = Theme.FontBold
	title.TextSize = 22
	title.TextColor3 = Theme.Text
	title.Text = titleText
	title.TextTransparency = 1
	title.Parent = center
	local subtitle = Instance.new("TextLabel")
	subtitle.BackgroundTransparency = 1
	subtitle.Size = UDim2.new(1, 0, 0, 18)
	subtitle.Position = UDim2.new(0, 0, 0, logoId and 86 or 50)
	subtitle.Font = Theme.Font
	subtitle.TextSize = 13
	subtitle.TextColor3 = Theme.SecondaryText
	subtitle.Text = subtitleText
	subtitle.TextTransparency = 1
	subtitle.Parent = center
	TweenEngine.Play(title, { TextTransparency = 0 }, { Duration = 0.45, Delay = 0.1, Easing = "QuadOut" })
	TweenEngine.Play(subtitle, { TextTransparency = 0 }, { Duration = 0.4, Delay = 0.2, Easing = "QuadOut" })
	local finished = false
	local function finish()
		if finished then return end
		finished = true
		TweenEngine.Play(overlay, { BackgroundTransparency = 1 }, {
			Duration = 0.35, Easing = "QuadIn",
			OnComplete = function() cleanup:Destroy() end,
		})
		TweenEngine.Play(title, { TextTransparency = 1 }, { Duration = 0.25, Easing = "QuadIn" })
		TweenEngine.Play(subtitle, { TextTransparency = 1 }, { Duration = 0.25, Easing = "QuadIn" })
	end
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
-- LIBRARY
----------------------------------------------------------------
local Library = {}
Library.__index = Library

local NotifManager = NotificationManager.new()
-- Set Library.NotifDraggable = false to disable dragging notifications
local Windows = {}

function Library:CreateWindow(config)
	local win = CreateWindow(Library, config)
	table.insert(Windows, win)
	-- ensure list entry is dropped when this window dies
	local oldDestroy = win.Destroy
	function win:Destroy()
		local idx = table.find(Windows, self)
		if idx then table.remove(Windows, idx) end
		if oldDestroy then oldDestroy(self) end
	end
	return win
end

function Library:Notify(config)
	return NotifManager:Notify(config)
end

-- Toggle notification dragging (default true)
function Library:SetNotifDraggable(enabled)
	NotifManager.Draggable = enabled and true or false
end
Library.NotifDraggable = true


-- Alurt-style alias
function Library:CreateNode(config)
	config = config or {}
	-- Map Alurt names → Veyra
	if config.Content and not config.Description then
		config.Description = config.Content
	end
	if config.Length ~= nil and config.Duration == nil then
		config.Duration = config.Length
	end
	return NotifManager:Notify(config)
end

function Library:SetTheme(t)
	SetTheme(t)
end

function Library:ApplyTheme(name)
	return ApplyThemePreset(name)
end

function Library:GetTheme()
	return GetTheme()
end

function Library:GetSettings()
	return Settings
end

function Library:SaveSettings()
	return ConfigSave()
end

function Library:LoadSettings()
	return ConfigLoad()
end

Library.ThemePresets = ThemePresets
Library.Settings = Settings

local InitDone = false

-- Full restart: kill every previous Veyra UI + notifs (re-exec / second script)
local function KillPrevious()
	pcall(function()
		-- destroy tracked windows
		local snap = table.clone(Windows)
		table.clear(Windows)
		for _, win in ipairs(snap) do
			pcall(function()
				if win.Destroy then win:Destroy() end
			end)
		end
		-- clear notifications
		if NotifManager then
			pcall(function() NotifManager:Clear() end)
			pcall(function()
				if NotifManager.Gui then NotifManager.Gui:Destroy() end
			end)
			NotifManager = NotificationManager.new()
		end
		-- cancel leftover tweens
		pcall(function() TweenEngine.CancelAll() end)
		-- wipe any leftover ScreenGuis named Veyra*
		local parents = {}
		pcall(function() table.insert(parents, game:GetService("CoreGui")) end)
		pcall(function()
			if type(gethui) == "function" then table.insert(parents, gethui()) end
		end)
		pcall(function()
			local lp = game:GetService("Players").LocalPlayer
			if lp then table.insert(parents, lp:FindFirstChildOfClass("PlayerGui")) end
		end)
		for _, parent in ipairs(parents) do
			if parent then
				for _, child in ipairs(parent:GetChildren()) do
					if child:IsA("ScreenGui") then
						local n = child.Name
						if string.find(n, "Veyra") or string.find(n, "veyra") then
							pcall(function() child:Destroy() end)
						end
					end
				end
			end
		end
	end)
end

--[[
	UI:Init() or UI:Init({ Theme = "Dark", Intro = true })

	Call once at the top of your script.
	Safe to call every time the script runs — cleans old UI first.
]]
function Library:Init(options)
	options = options or {}
	-- Always clean previous run so loadstring twice doesn't stack UIs
	KillPrevious()
	pcall(function()
		self:Destroy()
	end)
	InitDone = true

	if type(options.Theme) == "string" then
		ApplyThemePreset(options.Theme)
	elseif type(options.Theme) == "table" then
		SetTheme(options.Theme)
	end

	if options.NotifDraggable ~= nil then
		NotifManager.Draggable = options.NotifDraggable and true or false
	end

	if options.Intro == true then
		task.spawn(function()
			PlayIntro(options.IntroConfig or {
				Title = options.Title or "Veyra",
				Subtitle = options.Subtitle or "",
			})
		end)
	end

	return Library
end

function Library:PlayIntro(config)
	return PlayIntro(config)
end

function Library:IsInit()
	return InitDone
end

function Library:Destroy()
	local snap = table.clone(Windows)
	table.clear(Windows)
	for _, win in ipairs(snap) do
		pcall(function() win:Destroy() end)
	end
	pcall(function() NotifManager:Destroy() end)
	-- Rebuild notif manager so next Init/New still works
	pcall(function()
		NotifManager = NotificationManager.new()
	end)
	TweenEngine.CancelAll()
	table.clear(ThemeListeners)
	InitDone = false
end

-- Expose animation engine
Library.Animation = TweenEngine

----------------------------------------------------------------
-- SIMPLE API (same GUI, way less boilerplate)
--
--   local UI = loadstring(...)()
--   local Win = UI:New("My Hub", "v1")
--   local Tab = Win:Tab("Main")
--   Tab:Toggle("Speed", false, function(on) end)
--   Tab:Slider("WalkSpeed", 16, 200, 16, function(v) end)
--   Tab:Button("Click", function() end)
--   Tab:Drop("Theme", {"Dark","Light"}, "Dark", function(v) end)
--   UI:Notify("Hi", "Loaded", 3)
----------------------------------------------------------------

local function wrapTab(tab)
	local t = tab
	function t:Section(name, desc)
		return self:CreateSection({ Name = name, Description = desc })
	end
	function t:Toggle(name, default, callback)
		if type(default) == "function" then
			callback = default
			default = false
		end
		return self:CreateToggle({ Name = name, Default = default == true, Callback = callback })
	end
	function t:Slider(name, min, max, default, callback)
		if type(min) == "function" then
			callback = min
			min, max, default = 0, 100, 0
		elseif type(default) == "function" then
			callback = default
			default = min
		end
		return self:CreateSlider({
			Name = name,
			Min = min or 0,
			Max = max or 100,
			Default = default or min or 0,
			Callback = callback,
		})
	end
	function t:Button(name, callback)
		return self:CreateButton({ Name = name, Callback = callback })
	end
	function t:Drop(name, options, default, callback)
		if type(options) == "function" then
			callback = options
			options, default = {}, nil
		elseif type(default) == "function" then
			callback = default
			default = options and options[1]
		end
		return self:CreateDropdown({
			Name = name,
			Options = options or {},
			Default = default or (options and options[1]) or "",
			Callback = callback,
		})
	end
	function t:Key(name, key, callback)
		if type(key) == "function" then
			callback = key
			key = Enum.KeyCode.Unknown
		end
		return self:CreateKeybind({ Name = name, Default = key or Enum.KeyCode.Unknown, Callback = callback })
	end
	function t:Input(name, placeholder, callback)
		if type(placeholder) == "function" then
			callback = placeholder
			placeholder = ""
		end
		return self:CreateTextbox({ Name = name, Placeholder = placeholder or "", Callback = callback })
	end
	function t:Label(name, desc)
		return self:CreateLabel({ Name = name, Description = desc })
	end
	function t:Line()
		return self:CreateDivider()
	end
	return t
end

local function wrapWindow(win)
	local w = win
	function w:Tab(name)
		return wrapTab(self:CreateTab({ Name = name or "Tab" }))
	end
	function w:Action(name, callback)
		return self:AddAction({ Name = name, Callback = callback })
	end
	return w
end

-- UI:New("Title") or UI:New("Title", "Subtitle") or UI:New({ Title = "...", Width = 500 })
function Library:New(title, subtitle)
	if not InitDone then
		self:Init()
	end
	local config
	if type(title) == "table" then
		config = title
	else
		config = {
			Title = title or "Veyra",
			Subtitle = subtitle or "",
		}
	end
	return wrapWindow(self:CreateWindow(config))
end

-- Keep CreateWindow returning simple-wrapped window too
local _CreateWindow = Library.CreateWindow
function Library:CreateWindow(config)
	return wrapWindow(_CreateWindow(self, config))
end

-- UI:Notify("Title", "Desc", 3) or UI:Notify({ Title = "...", ... })
local _Notify = Library.Notify
function Library:Notify(a, b, c)
	if type(a) == "table" then
		return _Notify(self, a)
	end
	return _Notify(self, {
		Title = tostring(a or "Notice"),
		Description = tostring(b or ""),
		Duration = tonumber(c) or 3,
		Type = "Info",
	})
end

return Library
