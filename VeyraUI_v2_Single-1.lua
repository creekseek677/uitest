--[[
	VeyraUI v2 - Single File (Engineering Pass)
	Dark, technical, developer-oriented Roblox UI framework.

	Engineering improvements:
	- Signal/Changed events on Toggle, Slider, Dropdown, Textbox
	- Get/Set + IsDestroyed on stateful components
	- Hardened animation scheduler + CancelOnObject
	- Notification: Audio, Image, BarColor, Duration=0, CreateNode alias
	- gethui / syn.protect_gui / CoreGui parenting
	- Dropdown outside-click + transition lock
	- Keybind Clear / Escape / destroy-while-listening
	- Visual identity preserved (sharp, ethereal, Code font)
]]

--[[
	VeyraUI - Single File (Hardened + Feature Pass)
	Dark, technical, developer-oriented Roblox UI framework.

	Usage:
		local Library = loadstring(game:HttpGet("YOUR_RAW_URL"))()

		local Window = Library:CreateWindow({
			Title = "My UI",
			Subtitle = "Developer",
			Width = 480,
			Height = 380,
		})

		local Tab = Window:CreateTab({ Name = "Main" })
		Tab:CreateSection({ Name = "Section 1" })
		Tab:CreateButton({ Name = "Test", Callback = function() end })
		-- ... Toggle, Slider, Dropdown, Keybind, Textbox, Label, Divider

		Library:Notify({
			Title = "Ready",
			Description = "Loaded.",
			Duration = 5,           -- 0 = stay until :Close()
			Type = "Success",       -- Info | Success | Warning | Error
			Typewriter = true,
			Audio = "rbxassetid://...",   -- optional sound
			Image = "rbxassetid://...",   -- optional icon
			BarColor = Color3.fromRGB(80, 200, 120),
		})

		-- Alurt-style alias:
		local n = Library:CreateNode({
			Title = "Welcome",
			Content = "You're using VeyraUI",
			Length = 8,
			Audio = "rbxassetid://...",
			Image = "rbxassetid://...",
			BarColor = Color3.fromRGB(255, 75, 75),
		})
		-- n:Close()

	Hardened:
	- Tween cancellation / CancelAll / CancelOnObject / yoyo / springs
	- Lifecycle: destroy during anim, no stale connections
	- Dropdown: outside-click, transition lock, destroy-while-open
	- Keybind: Clear, Escape cancel, destroy while listening

	Also includes:
	- gethui / syn.protect_gui / CoreGui parenting
	- Notification progress bar + audio + icon
	- Duration/Length = 0 → manual close only
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")
local SoundService = game:GetService("SoundService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

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
	Font = Enum.Font.GothamMedium,
	FontBold = Enum.Font.GothamBold,
	FontMono = Enum.Font.Code,
	CornerRadius = 6,
	ElementHeight = 36,
	AnimationSpeed = 0.35,
	HoverSpeed = 0.15,
}

local ThemeListeners = {}

local function GetTheme()
	return Theme
end

local function SetTheme(t)
	for k, v in pairs(t) do
		Theme[k] = v
	end
	for _, fn in ipairs(ThemeListeners) do
		task.spawn(fn)
	end
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
			dragging = true
			dragStart = input.Position
			startPos = target.Position
			if options.OnDragStart then options.OnDragStart() end

			local moveC, endC
			moveC = UserInputService.InputChanged:Connect(function(inp)
				if (inp.UserInputType == Enum.UserInputType.MouseMovement or inp.UserInputType == Enum.UserInputType.Touch) and dragging then
					update(inp)
				end
			end)
			endC = UserInputService.InputEnded:Connect(function(inp)
				if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
					dragging = false
					if moveC then moveC:Disconnect() end
					if endC then endC:Disconnect() end
					if options.OnDragEnd then options.OnDragEnd() end
				end
			end)
		end
	end))

	return {
		SetEnabled = function(s) enabled = s end,
		Destroy = function()
			for _, c in ipairs(conns) do c:Disconnect() end
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
-- NOTIFICATION SYSTEM
----------------------------------------------------------------
local NotificationManager = {}
NotificationManager.__index = NotificationManager

function NotificationManager.new()
	local self = setmetatable({}, NotificationManager)
	self.Notifications = {}
	self.Spacing = 10

	local gui = Instance.new("ScreenGui")
	gui.Name = "VeyraNotifications"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 2147483647
	ProtectAndParent(gui)

	local container = Instance.new("Frame")
	container.Name = "Container"
	container.BackgroundTransparency = 1
	container.Size = UDim2.new(0, 340, 1, -40)
	container.Position = UDim2.new(1, -360, 0, 20)
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

	-- Sharp rectangle, no UICorner (Veyra identity)
	local frame = Instance.new("Frame")
	frame.Name = "Notification"
	frame.BackgroundColor3 = Theme.NotificationBackground
	frame.BackgroundTransparency = 0.08
	frame.BorderSizePixel = 0
	frame.Size = UDim2.new(0, 320, 0, 0)
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.ClipsDescendants = true
	frame.Parent = self.Container

	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.NotificationBorder
	stroke.Thickness = 1
	stroke.Transparency = 0.4
	stroke.Parent = frame

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 14)
	padding.PaddingBottom = UDim.new(0, 18) -- room for progress bar
	padding.PaddingLeft = UDim.new(0, 16)
	padding.PaddingRight = UDim.new(0, 16)
	padding.Parent = frame

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 6)
	layout.Parent = frame

	-- Left accent (type color / bar color)
	local accent = Instance.new("Frame")
	accent.Name = "Accent"
	accent.BackgroundColor3 = barColor
	accent.BorderSizePixel = 0
	accent.Size = UDim2.new(0, 2, 1, 0)
	accent.Position = UDim2.new(0, 0, 0, 0)
	accent.ZIndex = 2
	accent.Parent = frame

	-- Optional icon/image (small, left of title area — not full Alurt-style panel)
	local contentOffset = 0
	if imageId and tostring(imageId) ~= "" then
		local icon = Instance.new("ImageLabel")
		icon.Name = "Icon"
		icon.BackgroundTransparency = 1
		icon.Size = UDim2.new(0, 28, 0, 28)
		icon.Position = UDim2.new(0, 8, 0, 12)
		icon.Image = tostring(imageId)
		icon.ScaleType = Enum.ScaleType.Fit
		icon.ZIndex = 3
		icon.Parent = frame
		contentOffset = 36
		cleanup:AddInstance(icon)
	end

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, -8 - contentOffset, 0, 18)
	title.Position = UDim2.new(0, contentOffset, 0, 0)
	title.Font = Theme.FontMono
	title.TextSize = 13
	title.TextColor3 = Theme.NotificationTitle
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = config.Title or config.Content and (config.Title or "Notification") or "Notification"
	title.LayoutOrder = 1
	title.Parent = frame

	local sep = CreateEtherealSeparator(frame)
	sep.Container.LayoutOrder = 2

	local descText = config.Description or config.Content or ""
	local desc = Instance.new("TextLabel")
	desc.Name = "Description"
	desc.BackgroundTransparency = 1
	desc.Size = UDim2.new(1, -8 - contentOffset, 0, 0)
	desc.AutomaticSize = Enum.AutomaticSize.Y
	desc.Font = Theme.FontMono
	desc.TextSize = 12
	desc.TextColor3 = Theme.NotificationDescription
	desc.TextXAlignment = Enum.TextXAlignment.Left
	desc.TextYAlignment = Enum.TextYAlignment.Top
	desc.TextWrapped = true
	desc.Text = descText
	desc.LayoutOrder = 3
	desc.Parent = frame

	-- Progress bar (depletes over duration; hidden if Duration = 0)
	local barBg = Instance.new("Frame")
	barBg.Name = "ProgressBG"
	barBg.BackgroundColor3 = Color3.fromRGB(30, 30, 36)
	barBg.BackgroundTransparency = 0.5
	barBg.BorderSizePixel = 0
	barBg.Size = UDim2.new(1, 0, 0, 2)
	barBg.Position = UDim2.new(0, 0, 1, -2)
	barBg.ZIndex = 4
	barBg.Parent = frame

	local bar = Instance.new("Frame")
	bar.Name = "Progress"
	bar.BackgroundColor3 = barColor
	bar.BorderSizePixel = 0
	bar.Size = UDim2.new(1, 0, 1, 0)
	bar.Parent = barBg

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
		frame.Position = UDim2.new(1, 20, 0, targetPos.Y.Offset)
		frame.BackgroundTransparency = 1
		TweenEngine.Play(frame, {
			Position = targetPos,
			BackgroundTransparency = 0.08,
		}, { Duration = 0.4, Easing = "BackOut" })

		task.delay(0.1, function()
			if not closed then sep:PlayIn(0.35) end
		end)
		task.delay(0.15, function()
			if closed then return end
			if twTitle then twTitle:Start(config.Title or "Notification") end
			if twDesc then twDesc:Start(descText) end
		end)

		-- Deplete progress bar
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
			Position = UDim2.new(1, 40, 0, frame.Position.Y.Offset),
			BackgroundTransparency = 1,
		}, {
			Duration = 0.3,
			Easing = "QuadIn",
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

	notif.Manager = self
	table.insert(self.Notifications, 1, notif)

	-- Wait one frame so AutomaticSize can resolve before measuring
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
			y += (n.Frame.AbsoluteSize.Y > 0 and n.Frame.AbsoluteSize.Y or 70) + self.Spacing
		end
	end
	return UDim2.new(0, 0, 0, y)
end

function NotificationManager:RepositionAll(animate)
	for i, notif in ipairs(self.Notifications) do
		if notif.Closed then continue end
		local target = self:GetPositionForIndex(i)
		if animate then
			TweenEngine.Play(notif.Frame, { Position = target }, { Duration = 0.35, Easing = "QuadOut" })
		else
			notif.Frame.Position = target
		end
	end
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
	-- Safe: drain from front
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

	local section = {
		Container = container,
		Content = content,
		Cleanup = cleanup,
	}

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
	stroke.Transparency = 0.5
	stroke.Parent = frame

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, -24, 0, 16)
	title.Position = UDim2.new(0, 12, 0.5, config.Description and -8 or 0)
	title.Font = Theme.Font
	title.TextSize = 13
	title.TextColor3 = Theme.Text
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = config.Name or "Button"
	title.Parent = frame

	local desc
	if config.Description then
		desc = Instance.new("TextLabel")
		desc.BackgroundTransparency = 1
		desc.Size = UDim2.new(1, -24, 0, 14)
		desc.Position = UDim2.new(0, 12, 0.5, 4)
		desc.Font = Theme.Font
		desc.TextSize = 11
		desc.TextColor3 = Theme.SecondaryText
		desc.TextXAlignment = Enum.TextXAlignment.Left
		desc.Text = config.Description
		desc.Parent = frame
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
	stroke.Transparency = 0.5
	stroke.Parent = frame

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, -60, 0, 16)
	title.Position = UDim2.new(0, 12, 0.5, config.Description and -8 or 0)
	title.Font = Theme.Font
	title.TextSize = 13
	title.TextColor3 = Theme.Text
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = config.Name or "Toggle"
	title.Parent = frame

	if config.Description then
		local d = Instance.new("TextLabel")
		d.BackgroundTransparency = 1
		d.Size = UDim2.new(1, -60, 0, 14)
		d.Position = UDim2.new(0, 12, 0.5, 4)
		d.Font = Theme.Font
		d.TextSize = 11
		d.TextColor3 = Theme.SecondaryText
		d.TextXAlignment = Enum.TextXAlignment.Left
		d.Text = config.Description
		d.Parent = frame
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
	stroke.Transparency = 0.5
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

	local function updateFromInput(pos)
		local rel = math.clamp((pos.X - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
		local raw = minv + rel * (maxv - minv)
		local newVal = snap(raw)
		if newVal ~= value then
			value = newVal
			setVisual(newVal, false)
			changed:Fire(newVal)
			if config.Callback then task.spawn(config.Callback, newVal) end
		else
			setVisual(newVal, false)
		end
	end

	local changed = CreateSignal()

	local hit = Instance.new("TextButton")
	hit.BackgroundTransparency = 1
	hit.Size = UDim2.new(1, 0, 0, 20)
	hit.Position = UDim2.new(0, 0, 1, -24)
	hit.Text = ""
	hit.Parent = frame

	cleanup:AddConnection(hit.InputBegan:Connect(function(input)
		if not enabled then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			updateFromInput(input.Position)
		end
	end))
	cleanup:AddConnection(UserInputService.InputChanged:Connect(function(input)
		if not dragging then return end
		if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
			updateFromInput(input.Position)
		end
	end))
	cleanup:AddConnection(UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end))

	cleanup:AddInstance(frame)
	setVisual(value, false)

	local slider = { Frame = frame, Cleanup = cleanup, Changed = changed }

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

	function label:SetTitle(t) title.Text = t end
	function label:SetDescription(t) if desc then desc.Text = t end end
	function label:Destroy() cleanup:Destroy() end

	table.insert(tab.Components, label)
	return label
end

-- DROPDOWN
local function CreateDropdown(tab, config)
	config = config or {}
	local cleanup = CreateCleanup()
	local options = config.Options or {}
	local value = config.Default or (options[1] or "")
	local open = false
	local transitioning = false -- lock during open/close animation
	local destroyed = false
	local parent = GetParentForComponent(tab)
	local outsideConn = nil

	local frame = Instance.new("Frame")
	frame.Name = "Dropdown_" .. (config.Name or "Untitled")
	frame.BackgroundColor3 = Theme.Secondary
	frame.BackgroundTransparency = 0.15
	frame.BorderSizePixel = 0
	frame.Size = UDim2.new(1, 0, 0, Theme.ElementHeight)
	frame.ClipsDescendants = false
	frame.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, Theme.CornerRadius)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Border
	stroke.Thickness = 1
	stroke.Transparency = 0.5
	stroke.Parent = frame

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, -40, 1, 0)
	title.Position = UDim2.new(0, 12, 0, 0)
	title.Font = Theme.Font
	title.TextSize = 13
	title.TextColor3 = Theme.Text
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = (config.Name or "Dropdown") .. ": " .. tostring(value)
	title.Parent = frame

	local arrow = Instance.new("TextLabel")
	arrow.BackgroundTransparency = 1
	arrow.Size = UDim2.new(0, 20, 1, 0)
	arrow.Position = UDim2.new(1, -28, 0, 0)
	arrow.Font = Enum.Font.GothamBold
	arrow.TextSize = 12
	arrow.TextColor3 = Theme.SecondaryText
	arrow.Text = "▼"
	arrow.Parent = frame

	local list = Instance.new("Frame")
	list.BackgroundColor3 = Theme.Tertiary
	list.BorderSizePixel = 0
	list.Size = UDim2.new(1, 0, 0, 0)
	list.Position = UDim2.new(0, 0, 1, 4)
	list.Visible = false
	list.ZIndex = 10
	list.Parent = frame

	local lc = Instance.new("UICorner")
	lc.CornerRadius = UDim.new(0, Theme.CornerRadius)
	lc.Parent = list

	local ls = Instance.new("UIStroke")
	ls.Color = Theme.Border
	ls.Thickness = 1
	ls.Transparency = 0.4
	ls.Parent = list

	local ll = Instance.new("UIListLayout")
	ll.SortOrder = Enum.SortOrder.LayoutOrder
	ll.Parent = list

	local function forceClose(instant)
		if destroyed then return end
		open = false
		transitioning = false
		if outsideConn then
			outsideConn:Disconnect()
			outsideConn = nil
		end
		TweenEngine.CancelOnObject(list)
		if instant then
			list.Size = UDim2.new(1, 0, 0, 0)
			list.Visible = false
		else
			TweenEngine.Play(list, { Size = UDim2.new(1, 0, 0, 0) }, {
				Duration = 0.15, Easing = "QuadIn",
				OnComplete = function()
					if not destroyed then list.Visible = false end
				end
			})
		end
		arrow.Text = "▼"
	end

	local function openList()
		if destroyed or transitioning or open then return end
		transitioning = true
		open = true
		local height = math.min(#options * 28, 140)
		list.Visible = true
		list.Size = UDim2.new(1, 0, 0, 0)
		TweenEngine.Play(list, { Size = UDim2.new(1, 0, 0, height) }, {
			Duration = 0.22, Easing = "QuadOut",
			OnComplete = function()
				transitioning = false
			end
		})
		arrow.Text = "▲"

		-- Outside click to close
		task.defer(function()
			if destroyed or not open then return end
			outsideConn = UserInputService.InputBegan:Connect(function(input)
				if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
					return
				end
				local pos = input.Position
				local absPos = frame.AbsolutePosition
				local absSize = frame.AbsoluteSize
				local listH = list.AbsoluteSize.Y
				-- Click outside the whole dropdown (including list)
				if pos.X < absPos.X or pos.X > absPos.X + absSize.X or
				   pos.Y < absPos.Y or pos.Y > absPos.Y + absSize.Y + listH + 8 then
					forceClose(false)
				end
			end)
			cleanup:AddConnection(outsideConn)
		end)
	end

	for i, opt in ipairs(options) do
		local btn = Instance.new("TextButton")
		btn.BackgroundColor3 = Theme.Tertiary
		btn.BorderSizePixel = 0
		btn.Size = UDim2.new(1, 0, 0, 28)
		btn.Font = Theme.Font
		btn.TextSize = 12
		btn.TextColor3 = Theme.Text
		btn.Text = tostring(opt)
		btn.TextXAlignment = Enum.TextXAlignment.Left
		btn.AutoButtonColor = false
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
			if dd and dd.Changed then dd.Changed:Fire(opt) end
			if config.Callback then task.spawn(config.Callback, opt) end
			forceClose(false)
		end)
	end

	local hit = Instance.new("TextButton")
	hit.BackgroundTransparency = 1
	hit.Size = UDim2.new(1, 0, 1, 0)
	hit.Text = ""
	hit.Parent = frame

	cleanup:AddConnection(hit.MouseButton1Click:Connect(function()
		if destroyed or transitioning then return end
		if open then
			forceClose(false)
		else
			openList()
		end
	end))

	cleanup:AddInstance(frame)

	local dd = { Frame = frame, Cleanup = cleanup }

	local changed = CreateSignal()
	dd.Changed = changed

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
	stroke.Transparency = 0.5
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
	stroke.Transparency = 0.5
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
	function div:Destroy() cleanup:Destroy() end
	table.insert(tab.Components, div)
	return div
end

----------------------------------------------------------------
-- TAB
----------------------------------------------------------------
local function CreateTab(window, config)
	config = config or {}
	local cleanup = CreateCleanup()
	local name = config.Name or "Tab"

	local content = Instance.new("ScrollingFrame")
	content.Name = "TabContent_" .. name
	content.BackgroundTransparency = 1
	content.BorderSizePixel = 0
	content.Size = UDim2.new(1, 0, 1, 0)
	content.CanvasSize = UDim2.new(0, 0, 0, 0)
	content.AutomaticCanvasSize = Enum.AutomaticSize.Y
	content.ScrollBarThickness = 3
	content.ScrollBarImageColor3 = Theme.Border
	content.Visible = false
	content.Parent = window.ContentContainer

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 12)
	padding.PaddingBottom = UDim.new(0, 12)
	padding.PaddingLeft = UDim.new(0, 14)
	padding.PaddingRight = UDim.new(0, 14)
	padding.Parent = content

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 10)
	layout.Parent = content

	local tabBtn = Instance.new("TextButton")
	tabBtn.Name = "TabBtn_" .. name
	tabBtn.BackgroundColor3 = Theme.Secondary
	tabBtn.BackgroundTransparency = 1
	tabBtn.BorderSizePixel = 0
	tabBtn.Size = UDim2.new(0, 90, 0, 28)
	tabBtn.Font = Theme.Font
	tabBtn.TextSize = 12
	tabBtn.TextColor3 = Theme.SecondaryText
	tabBtn.Text = name
	tabBtn.AutoButtonColor = false
	tabBtn.Parent = window.TabBar

	local btnCorner = Instance.new("UICorner")
	btnCorner.CornerRadius = UDim.new(0, 4)
	btnCorner.Parent = tabBtn

	cleanup:AddInstance(content)
	cleanup:AddInstance(tabBtn)

	local tab = {
		Name = name,
		Content = content,
		Button = tabBtn,
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
			tabBtn.BackgroundTransparency = 0.3
			tabBtn.TextColor3 = Theme.Text
		else
			content.Visible = false
			tabBtn.BackgroundTransparency = 1
			tabBtn.TextColor3 = Theme.SecondaryText
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
	function tab:CreateDivider(c) return CreateDivider(tab) end

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
-- WINDOW
----------------------------------------------------------------
local function CreateWindow(library, config)
	config = config or {}
	local cleanup = CreateCleanup()
	local width = config.Width or 480
	local height = config.Height or 360
	local minimized = false
	local tabs = {}
	local activeTab = nil

	local gui = Instance.new("ScreenGui")
	gui.Name = "VeyraUI_" .. (config.Title or "Window")
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 50
	ProtectAndParent(gui)

	local main = Instance.new("Frame")
	main.Name = "Main"
	main.BackgroundColor3 = Theme.Background
	main.BackgroundTransparency = 0.05
	main.BorderSizePixel = 0
	main.Size = UDim2.new(0, width, 0, height)
	main.Position = UDim2.new(0.5, -width / 2, 0.5, -height / 2)
	main.Parent = gui

	local mainCorner = Instance.new("UICorner")
	mainCorner.CornerRadius = UDim.new(0, 8)
	mainCorner.Parent = main

	local mainStroke = Instance.new("UIStroke")
	mainStroke.Color = Theme.Border
	mainStroke.Thickness = 1
	mainStroke.Transparency = 0.4
	mainStroke.Parent = main

	-- Title bar
	local titleBar = Instance.new("Frame")
	titleBar.Name = "TitleBar"
	titleBar.BackgroundColor3 = Theme.Secondary
	titleBar.BackgroundTransparency = 0.2
	titleBar.BorderSizePixel = 0
	titleBar.Size = UDim2.new(1, 0, 0, 40)
	titleBar.Parent = main

	local titleCorner = Instance.new("UICorner")
	titleCorner.CornerRadius = UDim.new(0, 8)
	titleCorner.Parent = titleBar

	local titleFix = Instance.new("Frame")
	titleFix.BackgroundColor3 = Theme.Secondary
	titleFix.BackgroundTransparency = 0.2
	titleFix.BorderSizePixel = 0
	titleFix.Size = UDim2.new(1, 0, 0, 12)
	titleFix.Position = UDim2.new(0, 0, 1, -12)
	titleFix.Parent = titleBar

	local titleLabel = Instance.new("TextLabel")
	titleLabel.BackgroundTransparency = 1
	titleLabel.Size = UDim2.new(1, -80, 0, 18)
	titleLabel.Position = UDim2.new(0, 14, 0, 6)
	titleLabel.Font = Theme.FontBold
	titleLabel.TextSize = 14
	titleLabel.TextColor3 = Theme.Text
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.Text = config.Title or "Veyra"
	titleLabel.Parent = titleBar

	local subtitle = Instance.new("TextLabel")
	subtitle.BackgroundTransparency = 1
	subtitle.Size = UDim2.new(1, -80, 0, 14)
	subtitle.Position = UDim2.new(0, 14, 0, 22)
	subtitle.Font = Theme.Font
	subtitle.TextSize = 11
	subtitle.TextColor3 = Theme.SecondaryText
	subtitle.TextXAlignment = Enum.TextXAlignment.Left
	subtitle.Text = config.Subtitle or ""
	subtitle.Parent = titleBar

	local closeBtn = Instance.new("TextButton")
	closeBtn.BackgroundTransparency = 1
	closeBtn.Size = UDim2.new(0, 28, 0, 28)
	closeBtn.Position = UDim2.new(1, -34, 0.5, -14)
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.TextSize = 16
	closeBtn.TextColor3 = Theme.SecondaryText
	closeBtn.Text = "×"
	closeBtn.Parent = titleBar

	local minBtn = Instance.new("TextButton")
	minBtn.BackgroundTransparency = 1
	minBtn.Size = UDim2.new(0, 28, 0, 28)
	minBtn.Position = UDim2.new(1, -62, 0.5, -14)
	minBtn.Font = Enum.Font.GothamBold
	minBtn.TextSize = 14
	minBtn.TextColor3 = Theme.SecondaryText
	minBtn.Text = "−"
	minBtn.Parent = titleBar

	local tabBar = Instance.new("Frame")
	tabBar.Name = "TabBar"
	tabBar.BackgroundTransparency = 1
	tabBar.Size = UDim2.new(1, -20, 0, 32)
	tabBar.Position = UDim2.new(0, 10, 0, 44)
	tabBar.Parent = main

	local tabLayout = Instance.new("UIListLayout")
	tabLayout.FillDirection = Enum.FillDirection.Horizontal
	tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tabLayout.Padding = UDim.new(0, 6)
	tabLayout.Parent = tabBar

	local contentContainer = Instance.new("Frame")
	contentContainer.Name = "ContentContainer"
	contentContainer.BackgroundTransparency = 1
	contentContainer.Size = UDim2.new(1, 0, 1, -80)
	contentContainer.Position = UDim2.new(0, 0, 0, 76)
	contentContainer.ClipsDescendants = true
	contentContainer.Parent = main

	local window = {
		Gui = gui,
		Main = main,
		TitleBar = titleBar,
		TabBar = tabBar,
		ContentContainer = contentContainer,
		Tabs = tabs,
		Width = width,
		Height = height,
		Cleanup = cleanup,
	}

	-- Drag
	local drag = MakeDraggable(titleBar, main)
	cleanup:AddCallback(function() drag:Destroy() end)

	cleanup:AddConnection(closeBtn.MouseButton1Click:Connect(function()
		window:Close()
	end))

	cleanup:AddConnection(minBtn.MouseButton1Click:Connect(function()
		window:ToggleMinimize()
	end))

	-- Open animation
	main.Size = UDim2.new(0, 0, 0, 0)
	main.BackgroundTransparency = 1
	TweenEngine.Play(main, {
		Size = UDim2.new(0, width, 0, height),
		BackgroundTransparency = 0.05,
	}, { Duration = 0.45, Easing = "BackOut" })

	cleanup:AddInstance(gui)

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

	function window:ToggleMinimize()
		minimized = not minimized
		if minimized then
			TweenEngine.Play(main, {
				Size = UDim2.new(0, window.Width, 0, 40),
			}, { Duration = 0.3, Easing = "QuadOut" })
			contentContainer.Visible = false
			tabBar.Visible = false
		else
			contentContainer.Visible = true
			tabBar.Visible = true
			TweenEngine.Play(main, {
				Size = UDim2.new(0, window.Width, 0, window.Height),
			}, { Duration = 0.35, Easing = "BackOut" })
		end
	end

	function window:Close()
		TweenEngine.Play(main, {
			Size = UDim2.new(0, 0, 0, 0),
			BackgroundTransparency = 1,
		}, {
			Duration = 0.3,
			Easing = "QuadIn",
			OnComplete = function()
				window:Destroy()
			end,
		})
	end

	function window:Destroy()
		for _, tab in ipairs(tabs) do
			tab:Destroy()
		end
		cleanup:Destroy()
	end

	return window
end

----------------------------------------------------------------
-- LIBRARY
----------------------------------------------------------------
local Library = {}
Library.__index = Library

local NotifManager = NotificationManager.new()
local Windows = {}

function Library:CreateWindow(config)
	local win = CreateWindow(Library, config)
	table.insert(Windows, win)
	return win
end

function Library:Notify(config)
	return NotifManager:Notify(config)
end

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

function Library:GetTheme()
	return GetTheme()
end

function Library:Destroy()
	for _, win in ipairs(Windows) do
		win:Destroy()
	end
	NotifManager:Destroy()
	TweenEngine.CancelAll()
	table.clear(Windows)
end

-- Expose animation engine
Library.Animation = TweenEngine

-- Convenience so loadstring(...)() returns the library
return Library
