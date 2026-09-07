--[[
	ModernUI Library (Luau)
	Cool, modern, no-square UI lib with expandable selected tabs, light hover tilt,
	hover/click/mechanical sounds, multi-theme, minimize/close (lucide), 
	toggles/sliders/colorpickers/dropdowns, hold-to-show tooltips, and a 5s knife disassemble close.

	API is kept dead simple.
]]

local ModernUI = {}
ModernUI.__index = ModernUI

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer
local Mouse = LocalPlayer:GetMouse()

-- // SOUNDS (common free assets, replace if you want)
local SOUNDS = {
	Hover = "rbxassetid://6895079853",
	Click = "rbxassetid://6895079853",
	Mechanical = "rbxassetid://9113822144", -- mechanical-ish slider tick
	Open = "rbxassetid://6895079853",
	Close = "rbxassetid://6895079853",
}

local function playSound(id, volume, pitch)
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume or 0.35
	s.PlaybackSpeed = pitch or 1
	s.Parent = SoundService
	s:Play()
	game:GetService("Debris"):AddItem(s, 3)
end

-- // THEMES
local Themes = {
	Coffee = {
		Background = Color3.fromRGB(32, 24, 18),
		Secondary = Color3.fromRGB(48, 36, 28),
		Accent = Color3.fromRGB(180, 120, 70),
		Text = Color3.fromRGB(245, 230, 210),
		TextDim = Color3.fromRGB(180, 160, 140),
		Stroke = Color3.fromRGB(70, 50, 35),
		Selected = Color3.fromRGB(160, 100, 55),
		Hover = Color3.fromRGB(60, 45, 35),
		Success = Color3.fromRGB(120, 180, 90),
		Danger = Color3.fromRGB(200, 80, 70),
	},
	Dark = {
		Background = Color3.fromRGB(18, 18, 22),
		Secondary = Color3.fromRGB(28, 28, 34),
		Accent = Color3.fromRGB(100, 140, 255),
		Text = Color3.fromRGB(240, 240, 245),
		TextDim = Color3.fromRGB(150, 150, 160),
		Stroke = Color3.fromRGB(50, 50, 60),
		Selected = Color3.fromRGB(80, 110, 220),
		Hover = Color3.fromRGB(40, 40, 50),
		Success = Color3.fromRGB(90, 200, 130),
		Danger = Color3.fromRGB(220, 80, 80),
	},
	Light = {
		Background = Color3.fromRGB(245, 245, 250),
		Secondary = Color3.fromRGB(230, 230, 240),
		Accent = Color3.fromRGB(70, 110, 220),
		Text = Color3.fromRGB(25, 25, 30),
		TextDim = Color3.fromRGB(100, 100, 120),
		Stroke = Color3.fromRGB(200, 200, 210),
		Selected = Color3.fromRGB(90, 130, 240),
		Hover = Color3.fromRGB(220, 220, 235),
		Success = Color3.fromRGB(60, 170, 100),
		Danger = Color3.fromRGB(210, 70, 70),
	},
	Crimson = {
		Background = Color3.fromRGB(28, 12, 16),
		Secondary = Color3.fromRGB(42, 18, 24),
		Accent = Color3.fromRGB(220, 50, 70),
		Text = Color3.fromRGB(255, 230, 235),
		TextDim = Color3.fromRGB(180, 130, 140),
		Stroke = Color3.fromRGB(80, 30, 40),
		Selected = Color3.fromRGB(190, 40, 60),
		Hover = Color3.fromRGB(55, 25, 32),
		Success = Color3.fromRGB(100, 190, 110),
		Danger = Color3.fromRGB(255, 70, 90),
	},
	Moonshine = {
		Background = Color3.fromRGB(12, 14, 22),
		Secondary = Color3.fromRGB(20, 24, 36),
		Accent = Color3.fromRGB(160, 190, 255),
		Text = Color3.fromRGB(230, 240, 255),
		TextDim = Color3.fromRGB(140, 155, 180),
		Stroke = Color3.fromRGB(40, 50, 70),
		Selected = Color3.fromRGB(120, 160, 240),
		Hover = Color3.fromRGB(30, 35, 50),
		Success = Color3.fromRGB(100, 210, 180),
		Danger = Color3.fromRGB(230, 90, 110),
	},
}

-- // UTILS
local function create(class, props, children)
	local inst = Instance.new(class)
	for k, v in pairs(props or {}) do
		if k ~= "Parent" then
			inst[k] = v
		end
	end
	if props and props.Parent then
		inst.Parent = props.Parent
	end
	if children then
		for _, c in ipairs(children) do
			c.Parent = inst
		end
	end
	return inst
end

local function round(frame, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 8)
	c.Parent = frame
	return c
end

local function stroke(frame, color, thickness, transparency)
	local s = Instance.new("UIStroke")
	s.Color = color or Color3.new(1,1,1)
	s.Thickness = thickness or 1
	s.Transparency = transparency or 0
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = frame
	return s
end

local function padding(frame, t, b, l, r)
	local p = Instance.new("UIPadding")
	p.PaddingTop = UDim.new(0, t or 0)
	p.PaddingBottom = UDim.new(0, b or 0)
	p.PaddingLeft = UDim.new(0, l or 0)
	p.PaddingRight = UDim.new(0, r or 0)
	p.Parent = frame
	return p
end

local function listLayout(frame, dir, pad)
	local l = Instance.new("UIListLayout")
	l.FillDirection = dir or Enum.FillDirection.Vertical
	l.Padding = UDim.new(0, pad or 6)
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Parent = frame
	return l
end

local function tween(obj, info, props)
	local t = TweenService:Create(obj, info, props)
	t:Play()
	return t
end

-- Light tilt on hover (perfect amount)
local function addTilt(button, amount)
	amount = amount or 3
	local original = button.Rotation
	button.MouseEnter:Connect(function()
		tween(button, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Rotation = amount})
		playSound(SOUNDS.Hover, 0.15, 1.1)
	end)
	button.MouseLeave:Connect(function()
		tween(button, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Rotation = original})
	end)
end

-- // LUCIDE FALLBACK (simple common icons, replace with full lucide module if you have it)
-- You can require a real lucide module and override this.
local Lucide = {
	Get = function(name)
		-- Common free lucide-style asset ids (approximate). Prefer loading real lucide-roblox.
		local map = {
			["x"] = "rbxassetid://6031094678",
			["minimize"] = "rbxassetid://6031094678",
			["minus"] = "rbxassetid://6031094678",
			["chevron-down"] = "rbxassetid://6031094678",
			["chevron-up"] = "rbxassetid://6031094678",
			["settings"] = "rbxassetid://6031280882",
			["palette"] = "rbxassetid://6031280882",
			["coffee"] = "rbxassetid://6031280882",
			["moon"] = "rbxassetid://6031280882",
			["sun"] = "rbxassetid://6031280882",
			["check"] = "rbxassetid://6031094667",
			["circle"] = "rbxassetid://6031094678",
		}
		return map[name:lower()] or "rbxassetid://6031094678"
	end
}

-- Try to load real lucide if available in the environment
pcall(function()
	-- Common paths people use
	local ok, mod = pcall(function()
		return require(game:GetService("ReplicatedStorage"):FindFirstChild("lucide") or game:GetService("ReplicatedStorage"):FindFirstChild("Lucide"))
	end)
	if ok and mod and (mod.GetAsset or mod.Get or mod.Icon) then
		Lucide = {
			Get = function(name)
				if mod.GetAsset then
					local a = mod.GetAsset(name, 24)
					if type(a) == "table" and a.Image then return a.Image end
					if type(a) == "string" then return a end
				end
				if mod.Get then return mod.Get(name) end
				if mod.Icon then return mod.Icon(name) end
				return "rbxassetid://6031094678"
			end
		}
	end
end)

-- // LIBRARY STATE
local Library = {
	Windows = {},
	Theme = Themes.Dark,
	Config = {},
	_flags = {},
	_connections = {},
	_initialized = false,
}

-- // INIT
function Library:Init(config)
	config = config or {}
	self.Config = config
	self.Theme = Themes[config.Theme or "Dark"] or Themes.Dark
	self._initialized = true

	-- global keybind for minimize all etc can go here
	if config.OnInit then
		pcall(config.OnInit)
	end

	return self
end

function Library:SetTheme(name)
	local t = Themes[name]
	if not t then return end
	self.Theme = t
	-- Broadcast theme change to open windows (simple version)
	for _, win in pairs(self.Windows) do
		if win.RefreshTheme then
			win:RefreshTheme()
		end
	end
end

-- // CREATE WINDOW
function Library:CreateWindow(opts)
	opts = opts or {}
	assert(self._initialized, "Call Library:Init() first")

	local theme = self.Theme
	local title = opts.Title or "ModernUI"
	local size = opts.Size or UDim2.fromOffset(520, 380)
	local position = opts.Position or UDim2.fromScale(0.5, 0.5)

	local screenGui = create("ScreenGui", {
		Name = "ModernUI_" .. HttpService:GenerateGUID(false),
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		IgnoreGuiInset = true,
		Parent = LocalPlayer:WaitForChild("PlayerGui"),
	})

	local main = create("Frame", {
		Name = "Main",
		Size = size,
		Position = position,
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = theme.Background,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Parent = screenGui,
	})
	round(main, 14)
	stroke(main, theme.Stroke, 1.2, 0.3)

	-- Top bar
	local topBar = create("Frame", {
		Name = "TopBar",
		Size = UDim2.new(1, 0, 0, 42),
		BackgroundColor3 = theme.Secondary,
		BorderSizePixel = 0,
		Parent = main,
	})
	round(topBar, 14)
	-- fix bottom corners of topbar
	local topFix = create("Frame", {
		Size = UDim2.new(1, 0, 0, 16),
		Position = UDim2.new(0, 0, 1, -16),
		BackgroundColor3 = theme.Secondary,
		BorderSizePixel = 0,
		Parent = topBar,
	})

	local titleLabel = create("TextLabel", {
		Size = UDim2.new(1, -100, 1, 0),
		Position = UDim2.fromOffset(16, 0),
		BackgroundTransparency = 1,
		Text = title,
		Font = Enum.Font.GothamMedium,
		TextSize = 16,
		TextColor3 = theme.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = topBar,
	})

	-- Minimize & Close buttons (lucide)
	local btnContainer = create("Frame", {
		Size = UDim2.fromOffset(72, 28),
		Position = UDim2.new(1, -82, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundTransparency = 1,
		Parent = topBar,
	})
	listLayout(btnContainer, Enum.FillDirection.Horizontal, 6)

	local function makeIconBtn(iconName, color, callback)
		local b = create("ImageButton", {
			Size = UDim2.fromOffset(28, 28),
			BackgroundColor3 = theme.Hover,
			BorderSizePixel = 0,
			Image = Lucide.Get(iconName),
			ImageColor3 = color or theme.Text,
			ScaleType = Enum.ScaleType.Fit,
			AutoButtonColor = false,
			Parent = btnContainer,
		})
		round(b, 8)
		addTilt(b, 2.5)
		b.MouseButton1Click:Connect(function()
			playSound(SOUNDS.Click, 0.4)
			if callback then callback() end
		end)
		b.MouseEnter:Connect(function()
			tween(b, TweenInfo.new(0.15), {BackgroundColor3 = theme.Accent})
		end)
		b.MouseLeave:Connect(function()
			tween(b, TweenInfo.new(0.15), {BackgroundColor3 = theme.Hover})
		end)
		return b
	end

	local minimized = false
	local originalSize = size

	local minBtn = makeIconBtn("minus", theme.TextDim, function()
		minimized = not minimized
		if minimized then
			tween(main, TweenInfo.new(0.35, Enum.EasingStyle.Quint), {Size = UDim2.fromOffset(size.X.Offset, 42)})
		else
			tween(main, TweenInfo.new(0.35, Enum.EasingStyle.Quint), {Size = originalSize})
		end
	end)

	-- Close with knife disassemble
	local function knifeDisassemble()
		playSound(SOUNDS.Close, 0.5)
		-- 1. Fade entire UI to black
		local blackOverlay = create("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 1,
			ZIndex = 100,
			Parent = main,
		})
		round(blackOverlay, 14)
		tween(blackOverlay, TweenInfo.new(0.6, Enum.EasingStyle.Quad), {BackgroundTransparency = 0})

		task.wait(0.55)

		-- 2. Spawn many "knives" (thin rotated frames) and fling them
		local knives = {}
		local knifeCount = 28
		for i = 1, knifeCount do
			local knife = create("Frame", {
				Size = UDim2.fromOffset(math.random(28, 55), math.random(4, 7)),
				Position = UDim2.fromScale(0.5, 0.5),
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundColor3 = Color3.fromRGB(180 + math.random(-30, 30), 180 + math.random(-30, 30), 190),
				BorderSizePixel = 0,
				Rotation = math.random(0, 360),
				ZIndex = 101,
				Parent = screenGui,
			})
			round(knife, 2)
			stroke(knife, Color3.fromRGB(80, 80, 90), 1, 0.4)
			table.insert(knives, knife)

			local angle = math.rad((i / knifeCount) * 360 + math.random(-15, 15))
			local dist = math.random(280, 520)
			local targetPos = UDim2.fromOffset(
				main.AbsolutePosition.X + main.AbsoluteSize.X/2 + math.cos(angle) * dist,
				main.AbsolutePosition.Y + main.AbsoluteSize.Y/2 + math.sin(angle) * dist
			)

			tween(knife, TweenInfo.new(1.8 + math.random() * 1.2, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
				Position = targetPos,
				Rotation = knife.Rotation + math.random(-180, 180),
				BackgroundTransparency = 1,
			})
		end

		-- 3. Fade main away while knives fly
		tween(main, TweenInfo.new(1.2, Enum.EasingStyle.Quad), {BackgroundTransparency = 1})
		for _, child in ipairs(main:GetDescendants()) do
			if child:IsA("GuiObject") then
				pcall(function()
					tween(child, TweenInfo.new(0.9), {BackgroundTransparency = 1, TextTransparency = 1, ImageTransparency = 1})
				end)
			end
		end

		task.wait(4.2) -- total ~5s feel
		for _, k in ipairs(knives) do
			k:Destroy()
		end
		screenGui:Destroy()
	end

	local closeBtn = makeIconBtn("x", theme.Danger, function()
		knifeDisassemble()
	end)

	-- Dragging
	local dragging, dragStart, startPos
	topBar.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = input.Position
			startPos = main.Position
		end
	end)
	topBar.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			local delta = input.Position - dragStart
			main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
		end
	end)

	-- Tab bar (left side style or top? Description says selected tab longer + hovers)
	-- Using horizontal expandable tabs under topbar
	local tabBar = create("Frame", {
		Name = "TabBar",
		Size = UDim2.new(1, -20, 0, 36),
		Position = UDim2.fromOffset(10, 48),
		BackgroundTransparency = 1,
		Parent = main,
	})
	local tabLayout = listLayout(tabBar, Enum.FillDirection.Horizontal, 6)
	tabLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left

	local contentHolder = create("Frame", {
		Name = "Content",
		Size = UDim2.new(1, -20, 1, -100),
		Position = UDim2.fromOffset(10, 92),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Parent = main,
	})

	local window = {
		ScreenGui = screenGui,
		Main = main,
		Tabs = {},
		CurrentTab = nil,
		Theme = theme,
	}

	function window:RefreshTheme()
		-- basic recolor (full deep refresh left as exercise)
		main.BackgroundColor3 = Library.Theme.Background
		topBar.BackgroundColor3 = Library.Theme.Secondary
		topFix.BackgroundColor3 = Library.Theme.Secondary
		titleLabel.TextColor3 = Library.Theme.Text
	end

	function window:AddTab(tabOpts)
		tabOpts = tabOpts or {}
		local name = tabOpts.Name or "Tab"
		local icon = tabOpts.Icon

		local tabBtn = create("TextButton", {
			Name = name,
			Size = UDim2.fromOffset(90, 32), -- normal size
			BackgroundColor3 = theme.Secondary,
			BorderSizePixel = 0,
			Text = "  " .. name,
			Font = Enum.Font.GothamMedium,
			TextSize = 13,
			TextColor3 = theme.TextDim,
			AutoButtonColor = false,
			Parent = tabBar,
		})
		round(tabBtn, 10)
		stroke(tabBtn, theme.Stroke, 1, 0.5)

		if icon then
			local ic = create("ImageLabel", {
				Size = UDim2.fromOffset(16, 16),
				Position = UDim2.fromOffset(8, 8),
				BackgroundTransparency = 1,
				Image = Lucide.Get(icon),
				ImageColor3 = theme.TextDim,
				Parent = tabBtn,
			})
		end

		local page = create("ScrollingFrame", {
			Name = name .. "_Page",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ScrollBarThickness = 3,
			ScrollBarImageColor3 = theme.Accent,
			CanvasSize = UDim2.new(0, 0, 0, 0),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			Visible = false,
			Parent = contentHolder,
		})
		listLayout(page, Enum.FillDirection.Vertical, 8)
		padding(page, 4, 8, 4, 4)

		local tabData = {
			Button = tabBtn,
			Page = page,
			Name = name,
		}

		local function selectTab()
			if window.CurrentTab == tabData then return end
			-- revert previous
			if window.CurrentTab then
				local prev = window.CurrentTab
				tween(prev.Button, TweenInfo.new(0.28, Enum.EasingStyle.Quint), {
					Size = UDim2.fromOffset(90, 32),
					BackgroundColor3 = theme.Secondary,
				})
				prev.Button.TextColor3 = theme.TextDim
				prev.Page.Visible = false
			end
			-- select new (longer + color + slight "hover" lift)
			window.CurrentTab = tabData
			tween(tabBtn, TweenInfo.new(0.28, Enum.EasingStyle.Quint), {
				Size = UDim2.fromOffset(130, 34), -- longer when selected
				BackgroundColor3 = theme.Selected,
			})
			tabBtn.TextColor3 = theme.Text
			page.Visible = true
			playSound(SOUNDS.Click, 0.3, 1.05)
		end

		tabBtn.MouseButton1Click:Connect(selectTab)
		addTilt(tabBtn, 2)

		tabBtn.MouseEnter:Connect(function()
			if window.CurrentTab ~= tabData then
				tween(tabBtn, TweenInfo.new(0.15), {BackgroundColor3 = theme.Hover})
			end
		end)
		tabBtn.MouseLeave:Connect(function()
			if window.CurrentTab ~= tabData then
				tween(tabBtn, TweenInfo.new(0.15), {BackgroundColor3 = theme.Secondary})
			end
		end)

		table.insert(window.Tabs, tabData)
		if #window.Tabs == 1 then
			selectTab()
		end

		-- Tab methods
		local tabAPI = {}

		function tabAPI:AddSection(secName)
			local sec = create("Frame", {
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundColor3 = theme.Secondary,
				BorderSizePixel = 0,
				Parent = page,
			})
			round(sec, 10)
			stroke(sec, theme.Stroke, 1, 0.45)
			padding(sec, 10, 10, 12, 12)
			listLayout(sec, Enum.FillDirection.Vertical, 8)

			local header = create("TextLabel", {
				Size = UDim2.new(1, 0, 0, 20),
				BackgroundTransparency = 1,
				Text = secName or "Section",
				Font = Enum.Font.GothamBold,
				TextSize = 13,
				TextColor3 = theme.Accent,
				TextXAlignment = Enum.TextXAlignment.Left,
				Parent = sec,
			})

			local sectionAPI = {}

			-- BUTTON
			function sectionAPI:AddButton(bOpts)
				bOpts = bOpts or {}
				local btn = create("TextButton", {
					Size = UDim2.new(1, 0, 0, 34),
					BackgroundColor3 = theme.Background,
					BorderSizePixel = 0,
					Text = bOpts.Name or "Button",
					Font = Enum.Font.GothamMedium,
					TextSize = 13,
					TextColor3 = theme.Text,
					AutoButtonColor = false,
					Parent = sec,
				})
				round(btn, 9)
				stroke(btn, theme.Stroke, 1, 0.4)
				addTilt(btn, 2.2)

				btn.MouseEnter:Connect(function()
					tween(btn, TweenInfo.new(0.15), {BackgroundColor3 = theme.Hover})
				end)
				btn.MouseLeave:Connect(function()
					tween(btn, TweenInfo.new(0.15), {BackgroundColor3 = theme.Background})
				end)
				btn.MouseButton1Click:Connect(function()
					playSound(SOUNDS.Click, 0.4)
					if bOpts.Callback then
						pcall(bOpts.Callback)
					end
				end)

				-- Hold tooltip
				if bOpts.Tooltip then
					local tip
					btn.MouseButton1Down:Connect(function()
						tip = create("TextLabel", {
							Size = UDim2.fromOffset(160, 28),
							BackgroundColor3 = theme.Secondary,
							Text = bOpts.Tooltip,
							Font = Enum.Font.Gotham,
							TextSize = 12,
							TextColor3 = theme.Text,
							ZIndex = 50,
							Parent = screenGui,
						})
						round(tip, 6)
						stroke(tip, theme.Stroke, 1, 0.3)
						local function updateTip()
							if tip then
								tip.Position = UDim2.fromOffset(Mouse.X + 14, Mouse.Y + 14)
							end
						end
						local conn = RunService.RenderStepped:Connect(updateTip)
						btn.MouseButton1Up:Connect(function()
							if tip then tip:Destroy() tip = nil end
							conn:Disconnect()
						end)
						btn.MouseLeave:Connect(function()
							if tip then tip:Destroy() tip = nil end
							conn:Disconnect()
						end)
					end)
				end

				return btn
			end

			-- TOGGLE
			function sectionAPI:AddToggle(tOpts)
				tOpts = tOpts or {}
				local state = tOpts.Default or false
				local holder = create("Frame", {
					Size = UDim2.new(1, 0, 0, 32),
					BackgroundTransparency = 1,
					Parent = sec,
				})
				local label = create("TextLabel", {
					Size = UDim2.new(1, -60, 1, 0),
					BackgroundTransparency = 1,
					Text = tOpts.Name or "Toggle",
					Font = Enum.Font.Gotham,
					TextSize = 13,
					TextColor3 = theme.Text,
					TextXAlignment = Enum.TextXAlignment.Left,
					Parent = holder,
				})
				local track = create("Frame", {
					Size = UDim2.fromOffset(46, 24),
					Position = UDim2.new(1, -46, 0.5, 0),
					AnchorPoint = Vector2.new(0, 0.5),
					BackgroundColor3 = state and theme.Accent or theme.Background,
					BorderSizePixel = 0,
					Parent = holder,
				})
				round(track, 12)
				stroke(track, theme.Stroke, 1, 0.4)

				local knob = create("Frame", {
					Size = UDim2.fromOffset(18, 18),
					Position = state and UDim2.new(1, -21, 0.5, 0) or UDim2.fromOffset(3, 3),
					AnchorPoint = state and Vector2.new(0, 0.5) or Vector2.new(0, 0),
					BackgroundColor3 = theme.Text,
					BorderSizePixel = 0,
					Parent = track,
				})
				round(knob, 9)

				local function set(val)
					state = val
					tween(track, TweenInfo.new(0.22, Enum.EasingStyle.Quad), {
						BackgroundColor3 = state and theme.Accent or theme.Background
					})
					tween(knob, TweenInfo.new(0.22, Enum.EasingStyle.Quad), {
						Position = state and UDim2.new(1, -21, 0.5, 0) or UDim2.fromOffset(3, 3),
						AnchorPoint = state and Vector2.new(0, 0.5) or Vector2.new(0, 0),
					})
					playSound(SOUNDS.Click, 0.25, state and 1.15 or 0.9)
					if tOpts.Callback then pcall(tOpts.Callback, state) end
				end

				track.InputBegan:Connect(function(input)
					if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
						set(not state)
					end
				end)
				addTilt(track, 1.5)

				return {Set = set, Get = function() return state end}
			end

			-- SLIDER (mechanical sound)
			function sectionAPI:AddSlider(sOpts)
				sOpts = sOpts or {}
				local min, max = sOpts.Min or 0, sOpts.Max or 100
				local value = sOpts.Default or min
				local step = sOpts.Step or 1

				local holder = create("Frame", {
					Size = UDim2.new(1, 0, 0, 48),
					BackgroundTransparency = 1,
					Parent = sec,
				})
				local label = create("TextLabel", {
					Size = UDim2.new(1, -50, 0, 18),
					BackgroundTransparency = 1,
					Text = (sOpts.Name or "Slider") .. ": " .. tostring(value),
					Font = Enum.Font.Gotham,
					TextSize = 13,
					TextColor3 = theme.Text,
					TextXAlignment = Enum.TextXAlignment.Left,
					Parent = holder,
				})
				local barBg = create("Frame", {
					Size = UDim2.new(1, 0, 0, 10),
					Position = UDim2.fromOffset(0, 28),
					BackgroundColor3 = theme.Background,
					BorderSizePixel = 0,
					Parent = holder,
				})
				round(barBg, 5)
				stroke(barBg, theme.Stroke, 1, 0.4)

				local fill = create("Frame", {
					Size = UDim2.new((value - min) / (max - min), 0, 1, 0),
					BackgroundColor3 = theme.Accent,
					BorderSizePixel = 0,
					Parent = barBg,
				})
				round(fill, 5)

				local knob = create("Frame", {
					Size = UDim2.fromOffset(16, 16),
					Position = UDim2.new((value - min) / (max - min), 0, 0.5, 0),
					AnchorPoint = Vector2.new(0.5, 0.5),
					BackgroundColor3 = theme.Text,
					BorderSizePixel = 0,
					Parent = barBg,
				})
				round(knob, 8)

				local sliding = false
				local lastTick = 0

				local function update(val)
					val = math.clamp(math.floor(val / step + 0.5) * step, min, max)
					value = val
					local pct = (val - min) / (max - min)
					fill.Size = UDim2.new(pct, 0, 1, 0)
					knob.Position = UDim2.new(pct, 0, 0.5, 0)
					label.Text = (sOpts.Name or "Slider") .. ": " .. tostring(val)
					if tick() - lastTick > 0.045 then
						playSound(SOUNDS.Mechanical, 0.2, 0.85 + pct * 0.4)
						lastTick = tick()
					end
					if sOpts.Callback then pcall(sOpts.Callback, val) end
				end

				barBg.InputBegan:Connect(function(input)
					if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
						sliding = true
					end
				end)
				UserInputService.InputEnded:Connect(function(input)
					if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
						sliding = false
					end
				end)
				UserInputService.InputChanged:Connect(function(input)
					if sliding and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
						local rel = (input.Position.X - barBg.AbsolutePosition.X) / barBg.AbsoluteSize.X
						update(min + rel * (max - min))
					end
				end)

				return {Set = update, Get = function() return value end}
			end

			-- DROPDOWN (rounded, no squares)
			function sectionAPI:AddDropdown(dOpts)
				dOpts = dOpts or {}
				local options = dOpts.Options or {"Option 1", "Option 2"}
				local selected = dOpts.Default or options[1]
				local open = false

				local holder = create("Frame", {
					Size = UDim2.new(1, 0, 0, 34),
					BackgroundTransparency = 1,
					Parent = sec,
					ClipsDescendants = false,
				})
				local mainBtn = create("TextButton", {
					Size = UDim2.new(1, 0, 0, 34),
					BackgroundColor3 = theme.Background,
					BorderSizePixel = 0,
					Text = "  " .. tostring(selected),
					Font = Enum.Font.Gotham,
					TextSize = 13,
					TextColor3 = theme.Text,
					TextXAlignment = Enum.TextXAlignment.Left,
					AutoButtonColor = false,
					Parent = holder,
				})
				round(mainBtn, 9)
				stroke(mainBtn, theme.Stroke, 1, 0.4)
				addTilt(mainBtn, 1.8)

				local chev = create("ImageLabel", {
					Size = UDim2.fromOffset(16, 16),
					Position = UDim2.new(1, -26, 0.5, 0),
					AnchorPoint = Vector2.new(0, 0.5),
					BackgroundTransparency = 1,
					Image = Lucide.Get("chevron-down"),
					ImageColor3 = theme.TextDim,
					Parent = mainBtn,
				})

				local dropFrame = create("Frame", {
					Size = UDim2.new(1, 0, 0, 0),
					Position = UDim2.fromOffset(0, 38),
					BackgroundColor3 = theme.Secondary,
					BorderSizePixel = 0,
					ClipsDescendants = true,
					Visible = false,
					ZIndex = 20,
					Parent = holder,
				})
				round(dropFrame, 10)
				stroke(dropFrame, theme.Stroke, 1, 0.35)
				listLayout(dropFrame, Enum.FillDirection.Vertical, 2)
				padding(dropFrame, 4, 4, 4, 4)

				local function closeDrop()
					open = false
					tween(dropFrame, TweenInfo.new(0.2, Enum.EasingStyle.Quad), {Size = UDim2.new(1, 0, 0, 0)})
					task.delay(0.2, function() dropFrame.Visible = false end)
					tween(chev, TweenInfo.new(0.2), {Rotation = 0})
				end

				local function openDrop()
					open = true
					dropFrame.Visible = true
					local h = math.min(#options * 30 + 8, 160)
					tween(dropFrame, TweenInfo.new(0.25, Enum.EasingStyle.Quint), {Size = UDim2.new(1, 0, 0, h)})
					tween(chev, TweenInfo.new(0.2), {Rotation = 180})
				end

				for _, opt in ipairs(options) do
					local optBtn = create("TextButton", {
						Size = UDim2.new(1, 0, 0, 28),
						BackgroundColor3 = theme.Secondary,
						BorderSizePixel = 0,
						Text = "  " .. tostring(opt),
						Font = Enum.Font.Gotham,
						TextSize = 12,
						TextColor3 = theme.Text,
						TextXAlignment = Enum.TextXAlignment.Left,
						AutoButtonColor = false,
						ZIndex = 21,
						Parent = dropFrame,
					})
					round(optBtn, 7)
					optBtn.MouseEnter:Connect(function()
						tween(optBtn, TweenInfo.new(0.12), {BackgroundColor3 = theme.Hover})
					end)
					optBtn.MouseLeave:Connect(function()
						tween(optBtn, TweenInfo.new(0.12), {BackgroundColor3 = theme.Secondary})
					end)
					optBtn.MouseButton1Click:Connect(function()
						selected = opt
						mainBtn.Text = "  " .. tostring(opt)
						playSound(SOUNDS.Click, 0.3)
						closeDrop()
						if dOpts.Callback then pcall(dOpts.Callback, opt) end
					end)
				end

				mainBtn.MouseButton1Click:Connect(function()
					playSound(SOUNDS.Click, 0.25)
					if open then closeDrop() else openDrop() end
				end)

				return {
					Set = function(v)
						selected = v
						mainBtn.Text = "  " .. tostring(v)
					end,
					Get = function() return selected end
				}
			end

			-- COLOR PICKER (modern rounded, HSV, no pure square hell)
			function sectionAPI:AddColorPicker(cOpts)
				cOpts = cOpts or {}
				local color = cOpts.Default or Color3.fromRGB(100, 140, 255)
				local h, s, v = color:ToHSV()

				local holder = create("Frame", {
					Size = UDim2.new(1, 0, 0, 34),
					BackgroundTransparency = 1,
					Parent = sec,
				})
				local label = create("TextLabel", {
					Size = UDim2.new(1, -50, 1, 0),
					BackgroundTransparency = 1,
					Text = cOpts.Name or "Color",
					Font = Enum.Font.Gotham,
					TextSize = 13,
					TextColor3 = theme.Text,
					TextXAlignment = Enum.TextXAlignment.Left,
					Parent = holder,
				})
				local preview = create("TextButton", {
					Size = UDim2.fromOffset(34, 24),
					Position = UDim2.new(1, -34, 0.5, 0),
					AnchorPoint = Vector2.new(0, 0.5),
					BackgroundColor3 = color,
					BorderSizePixel = 0,
					Text = "",
					AutoButtonColor = false,
					Parent = holder,
				})
				round(preview, 8)
				stroke(preview, theme.Stroke, 1, 0.3)
				addTilt(preview, 2)

				local pickerOpen = false
				local pickerFrame

				local function openPicker()
					if pickerOpen then return end
					pickerOpen = true
					pickerFrame = create("Frame", {
						Size = UDim2.fromOffset(200, 180),
						Position = UDim2.fromOffset(preview.AbsolutePosition.X - 160, preview.AbsolutePosition.Y + 30),
						BackgroundColor3 = theme.Secondary,
						BorderSizePixel = 0,
						ZIndex = 40,
						Parent = screenGui,
					})
					round(pickerFrame, 12)
					stroke(pickerFrame, theme.Stroke, 1.2, 0.3)

					-- Saturation/Value area (rounded square-ish but soft)
					local sv = create("ImageButton", {
						Size = UDim2.fromOffset(150, 120),
						Position = UDim2.fromOffset(12, 12),
						BackgroundColor3 = Color3.fromHSV(h, 1, 1),
						BorderSizePixel = 0,
						Image = "",
						AutoButtonColor = false,
						ZIndex = 41,
						Parent = pickerFrame,
					})
					round(sv, 10)

					local svGradient = Instance.new("UIGradient")
					svGradient.Color = ColorSequence.new{
						ColorSequenceKeypoint.new(0, Color3.new(1,1,1)),
						ColorSequenceKeypoint.new(1, Color3.new(1,1,1)),
					}
					svGradient.Transparency = NumberSequence.new{
						NumberSequenceKeypoint.new(0, 0),
						NumberSequenceKeypoint.new(1, 1),
					}
					svGradient.Rotation = 90
					svGradient.Parent = sv

					local whiteGrad = Instance.new("UIGradient")
					-- better approach: use two frames or accept simple HSV
					-- simplified SV cursor
					local cursor = create("Frame", {
						Size = UDim2.fromOffset(12, 12),
						AnchorPoint = Vector2.new(0.5, 0.5),
						BackgroundColor3 = Color3.new(1,1,1),
						BorderSizePixel = 0,
						ZIndex = 42,
						Parent = sv,
					})
					round(cursor, 6)
					stroke(cursor, Color3.new(0,0,0), 1, 0.3)

					-- Hue bar
					local hueBar = create("Frame", {
						Size = UDim2.fromOffset(18, 120),
						Position = UDim2.fromOffset(170, 12),
						BackgroundColor3 = Color3.new(1,1,1),
						BorderSizePixel = 0,
						ZIndex = 41,
						Parent = pickerFrame,
					})
					round(hueBar, 6)
					local hueGrad = Instance.new("UIGradient")
					hueGrad.Color = ColorSequence.new{
						ColorSequenceKeypoint.new(0, Color3.fromHSV(0,1,1)),
						ColorSequenceKeypoint.new(0.16, Color3.fromHSV(0.16,1,1)),
						ColorSequenceKeypoint.new(0.33, Color3.fromHSV(0.33,1,1)),
						ColorSequenceKeypoint.new(0.5, Color3.fromHSV(0.5,1,1)),
						ColorSequenceKeypoint.new(0.66, Color3.fromHSV(0.66,1,1)),
						ColorSequenceKeypoint.new(0.83, Color3.fromHSV(0.83,1,1)),
						ColorSequenceKeypoint.new(1, Color3.fromHSV(1,1,1)),
					}
					hueGrad.Rotation = 90
					hueGrad.Parent = hueBar

					local function applyColor()
						color = Color3.fromHSV(h, s, v)
						preview.BackgroundColor3 = color
						sv.BackgroundColor3 = Color3.fromHSV(h, 1, 1)
						if cOpts.Callback then pcall(cOpts.Callback, color) end
					end

					-- simple drag logic
					local function updateSV(input)
						local relX = math.clamp((input.Position.X - sv.AbsolutePosition.X) / sv.AbsoluteSize.X, 0, 1)
						local relY = math.clamp((input.Position.Y - sv.AbsolutePosition.Y) / sv.AbsoluteSize.Y, 0, 1)
						s = relX
						v = 1 - relY
						cursor.Position = UDim2.fromScale(s, 1 - v)
						applyColor()
					end
					local function updateHue(input)
						local relY = math.clamp((input.Position.Y - hueBar.AbsolutePosition.Y) / hueBar.AbsoluteSize.Y, 0, 1)
						h = relY
						applyColor()
					end

					sv.InputBegan:Connect(function(i)
						if i.UserInputType == Enum.UserInputType.MouseButton1 then
							local conn
							conn = UserInputService.InputChanged:Connect(function(inp)
								if inp.UserInputType == Enum.UserInputType.MouseMovement then
									updateSV(inp)
								end
							end)
							local endConn
							endConn = UserInputService.InputEnded:Connect(function(inp)
								if inp.UserInputType == Enum.UserInputType.MouseButton1 then
									conn:Disconnect()
									endConn:Disconnect()
								end
							end)
							updateSV(i)
						end
					end)
					hueBar.InputBegan:Connect(function(i)
						if i.UserInputType == Enum.UserInputType.MouseButton1 then
							local conn
							conn = UserInputService.InputChanged:Connect(function(inp)
								if inp.UserInputType == Enum.UserInputType.MouseMovement then
									updateHue(inp)
								end
							end)
							local endConn
							endConn = UserInputService.InputEnded:Connect(function(inp)
								if inp.UserInputType == Enum.UserInputType.MouseButton1 then
									conn:Disconnect()
									endConn:Disconnect()
								end
							end)
							updateHue(i)
						end
					end)

					-- close on click outside (simple)
					local closeBtn2 = create("TextButton", {
						Size = UDim2.fromOffset(60, 22),
						Position = UDim2.new(1, -70, 1, -30),
						BackgroundColor3 = theme.Background,
						Text = "Done",
						Font = Enum.Font.GothamMedium,
						TextSize = 12,
						TextColor3 = theme.Text,
						AutoButtonColor = false,
						ZIndex = 42,
						Parent = pickerFrame,
					})
					round(closeBtn2, 6)
					closeBtn2.MouseButton1Click:Connect(function()
						pickerFrame:Destroy()
						pickerOpen = false
						playSound(SOUNDS.Click, 0.3)
					end)
				end

				preview.MouseButton1Click:Connect(function()
					playSound(SOUNDS.Click, 0.3)
					openPicker()
				end)

				return {
					Set = function(c)
						color = c
						h, s, v = c:ToHSV()
						preview.BackgroundColor3 = c
					end,
					Get = function() return color end
				}
			end

			return sectionAPI
		end

		return tabAPI
	end

	table.insert(Library.Windows, window)
	playSound(SOUNDS.Open, 0.3)
	return window
end

-- Convenience
function Library:Notify(text, duration)
	duration = duration or 3
	local theme = self.Theme
	local notif = create("Frame", {
		Size = UDim2.fromOffset(260, 50),
		Position = UDim2.new(1, -280, 1, -70),
		BackgroundColor3 = theme.Secondary,
		BorderSizePixel = 0,
		Parent = LocalPlayer.PlayerGui:FindFirstChildOfClass("ScreenGui") or create("ScreenGui", {Parent = LocalPlayer.PlayerGui}),
	})
	round(notif, 10)
	stroke(notif, theme.Accent, 1.5, 0.2)
	create("TextLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = text,
		Font = Enum.Font.Gotham,
		TextSize = 13,
		TextColor3 = theme.Text,
		Parent = notif,
	})
	task.delay(duration, function()
		tween(notif, TweenInfo.new(0.3), {BackgroundTransparency = 1})
		task.wait(0.3)
		notif:Destroy()
	end)
end

return setmetatable(Library, ModernUI)
