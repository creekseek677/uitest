--[[
	SATURN INTRO  —  dark / white  ·  delayed ring physics  ·  full drag
]]

local function PlaySaturnIntro(parent)
	parent = parent or game:GetService("CoreGui")
	local RunService          = game:GetService("RunService")
	local TweenService        = game:GetService("TweenService")
	local UserInputService    = game:GetService("UserInputService")

	--------------------------------------------------------------------
	-- FULLSCREEN BLACK
	--------------------------------------------------------------------
	local root = Instance.new("Frame")
	root.Name               = "SaturnRoot"
	root.Size               = UDim2.fromScale(1, 1)
	root.BackgroundColor3   = Color3.new(0, 0, 0)
	root.BackgroundTransparency = 0
	root.BorderSizePixel    = 0
	root.ZIndex             = 2147483647
	root.Active             = true
	root.Parent             = parent

	-- subtle vertical gradient (near-black → deep charcoal)
	local grad = Instance.new("UIGradient")
	grad.Name = "BgGrad"
	grad.Rotation = 90
	grad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0,   Color3.fromRGB(8, 8, 12)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(0, 0, 0)),
		ColorSequenceKeypoint.new(1,   Color3.fromRGB(14, 12, 18)),
	})
	grad.Parent = root

	--------------------------------------------------------------------
	-- MUSIC
	--------------------------------------------------------------------
	local music = Instance.new("Sound")
	music.Name          = "SaturnMusic"
	music.SoundId       = "rbxassetid://9044749540"
	music.Volume        = 0.85
	music.Looped        = false
	music.Parent        = root
	music:Play()

	--------------------------------------------------------------------
	-- CORE CONTAINER (the thing you drag)
	--------------------------------------------------------------------
	local core = Instance.new("Frame")
	core.Name             = "Core"
	core.AnchorPoint      = Vector2.new(0.5, 0.5)
	core.Position         = UDim2.fromScale(0.5, 0.5)
	core.Size             = UDim2.fromOffset(0, 0)
	core.BackgroundTransparency = 1
	core.BorderSizePixel  = 0
	core.ZIndex           = 10
	core.Active           = true
	core.Parent           = root

	--------------------------------------------------------------------
	-- PLANET
	--------------------------------------------------------------------
	local planet = Instance.new("Frame")
	planet.Name             = "Planet"
	planet.AnchorPoint      = Vector2.new(0.5, 0.5)
	planet.Position         = UDim2.fromScale(0.5, 0.5)
	planet.Size             = UDim2.fromScale(1, 1)
	planet.BackgroundColor3 = Color3.new(1, 1, 1)
	planet.BorderSizePixel  = 0
	planet.ZIndex           = 5
	local pc = Instance.new("UICorner")
	pc.CornerRadius = UDim.new(1, 0)
	pc.Parent = planet
	planet.Parent = core

	-- soft outer glow
	local glow = Instance.new("ImageLabel")
	glow.Name               = "Glow"
	glow.AnchorPoint        = Vector2.new(0.5, 0.5)
	glow.Position           = UDim2.fromScale(0.5, 0.5)
	glow.Size               = UDim2.fromScale(1.55, 1.55)
	glow.BackgroundTransparency = 1
	glow.Image              = "rbxassetid://5028857084"
	glow.ImageColor3        = Color3.new(1, 1, 1)
	glow.ImageTransparency  = 0.82
	glow.ZIndex             = 4
	glow.Parent             = core

	--------------------------------------------------------------------
	-- RINGS (live outside core so they can lag)
	--------------------------------------------------------------------
	local function makeRing(scaleX, scaleY, thick, z, lag)
		local ring = Instance.new("Frame")
		ring.Name             = "Ring"
		ring.AnchorPoint      = Vector2.new(0.5, 0.5)
		ring.Position         = UDim2.fromScale(0.5, 0.5)
		ring.Size             = UDim2.fromOffset(0, 0)
		ring.BackgroundTransparency = 1
		ring.BorderSizePixel  = 0
		ring.ZIndex           = z
		ring.Parent           = root

		local stroke = Instance.new("UIStroke")
		stroke.Color         = Color3.new(1, 1, 1)
		stroke.Thickness     = thick
		stroke.Transparency  = 0.12
		stroke.Parent        = ring

		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(1, 0)
		c.Parent = ring

		return {
			inst   = ring,
			scaleX = scaleX,
			scaleY = scaleY,
			lag    = lag,
			pos    = Vector2.new(0.5, 0.5),
			rot    = 0,
		}
	end

	local rings = {
		makeRing(2.55, 0.52, 6.0, 3, 0.085),
		makeRing(3.05, 0.62, 4.0, 2, 0.145),
		makeRing(3.55, 0.72, 2.5, 1, 0.210),
	}

	--------------------------------------------------------------------
	-- TITLE
	--------------------------------------------------------------------
	local title = Instance.new("TextLabel")
	title.Name               = "Title"
	title.AnchorPoint        = Vector2.new(0.5, 0.5)
	title.Position           = UDim2.fromScale(0.5, 0.82)
	title.Size               = UDim2.fromScale(0.7, 0.065)
	title.BackgroundTransparency = 1
	title.Text               = "SATURN"
	title.Font               = Enum.Font.GothamMedium
	title.TextColor3         = Color3.new(1, 1, 1)
	title.TextTransparency   = 1
	title.TextScaled         = true
	title.ZIndex             = 20
	title.Parent             = root

	local subtitle = Instance.new("TextLabel")
	subtitle.Name            = "Sub"
	subtitle.AnchorPoint     = Vector2.new(0.5, 0.5)
	subtitle.Position        = UDim2.fromScale(0.5, 0.875)
	subtitle.Size            = UDim2.fromScale(0.5, 0.03)
	subtitle.BackgroundTransparency = 1
	subtitle.Text            = "hold · drag · release"
	subtitle.Font            = Enum.Font.Code
	subtitle.TextColor3      = Color3.new(0.7, 0.7, 0.7)
	subtitle.TextTransparency = 1
	subtitle.TextScaled      = true
	subtitle.ZIndex          = 20
	subtitle.Parent          = root

	--------------------------------------------------------------------
	-- INTRO GROW
	--------------------------------------------------------------------
	local TARGET = 280

	TweenService:Create(core, TweenInfo.new(2.4, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
		Size = UDim2.fromOffset(TARGET, TARGET)
	}):Play()

	for i, r in ipairs(rings) do
		TweenService:Create(r.inst, TweenInfo.new(2.4 + i * 0.18, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
			Size = UDim2.fromOffset(TARGET * r.scaleX, TARGET * r.scaleY)
		}):Play()
	end

	TweenService:Create(title, TweenInfo.new(1.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		TextTransparency = 0
	}):Play()
	TweenService:Create(subtitle, TweenInfo.new(2.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		TextTransparency = 0.35
	}):Play()

	--------------------------------------------------------------------
	-- STATE
	--------------------------------------------------------------------
	local spinning   = true
	local baseRot    = 0
	local dragging   = false
	local dragOffset = Vector2.zero
	local corePos    = Vector2.new(0.5, 0.5)

	--------------------------------------------------------------------
	-- MAIN LOOP
	--------------------------------------------------------------------
	local gradPhase = 0
	local conn = RunService.RenderStepped:Connect(function(dt)
		-- slow drifting gradient
		gradPhase = (gradPhase + dt * 0.08) % 1
		grad.Offset = Vector2.new(0, math.sin(gradPhase * math.pi * 2) * 0.35)
		grad.Rotation = 90 + math.sin(gradPhase * math.pi * 2 * 0.5) * 12

		if spinning then
			baseRot = (baseRot + 14 * dt) % 360
		end

		for i, r in ipairs(rings) do
			-- delayed follow
			r.pos = r.pos:Lerp(corePos, 1 - math.exp(-dt / r.lag))
			r.inst.Position = UDim2.fromScale(r.pos.X, r.pos.Y)

			-- independent spin
			r.rot = (r.rot + (11 + i * 2.2) * dt) % 360
			r.inst.Rotation = baseRot * (0.9 - i * 0.07) + r.rot * 0.15
		end

		core.Position = UDim2.fromScale(corePos.X, corePos.Y)
	end)

	--------------------------------------------------------------------
	-- DRAG
	--------------------------------------------------------------------
	local function beginDrag(input)
		if dragging then return end
		dragging = true
		spinning = false
		local mouse = Vector2.new(input.Position.X, input.Position.Y)
		local abs   = core.AbsolutePosition + core.AbsoluteSize / 2
		dragOffset  = abs - mouse
		TweenService:Create(planet, TweenInfo.new(0.12), {BackgroundTransparency = 0.25}):Play()
		TweenService:Create(glow,   TweenInfo.new(0.12), {ImageTransparency = 0.55}):Play()
	end

	local function moveDrag(input)
		if not dragging then return end
		local mouse  = Vector2.new(input.Position.X, input.Position.Y) + dragOffset
		local screen = root.AbsoluteSize
		corePos = Vector2.new(
			math.clamp(mouse.X / screen.X, 0.12, 0.88),
			math.clamp(mouse.Y / screen.Y, 0.12, 0.88)
		)
	end

	local function endDrag()
		if not dragging then return end
		dragging = false
		local start = corePos
		local t0 = os.clock()
		local snapConn
		snapConn = RunService.RenderStepped:Connect(function()
			local a = math.clamp((os.clock() - t0) / 0.55, 0, 1)
			local ease = TweenService:GetValue(a, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
			corePos = start:Lerp(Vector2.new(0.5, 0.5), ease)
			if a >= 1 then
				snapConn:Disconnect()
				spinning = true
			end
		end)
		TweenService:Create(planet, TweenInfo.new(0.25), {BackgroundTransparency = 0}):Play()
		TweenService:Create(glow,   TweenInfo.new(0.25), {ImageTransparency = 0.82}):Play()
	end

	core.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			beginDrag(input)
		end
	end)

	root.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			local mouse = Vector2.new(input.Position.X, input.Position.Y)
			local center = core.AbsolutePosition + core.AbsoluteSize / 2
			if (mouse - center).Magnitude < TARGET * 1.9 then
				beginDrag(input)
			end
		end
	end)

	UserInputService.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch then
			moveDrag(input)
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			endDrag()
		end
	end)

	--------------------------------------------------------------------
	-- EXIT
	--------------------------------------------------------------------
	task.wait(9.5)

	spinning = false
	TweenService:Create(root,   TweenInfo.new(1.4), {BackgroundTransparency = 1}):Play()
	TweenService:Create(planet, TweenInfo.new(1.4), {BackgroundTransparency = 1}):Play()
	TweenService:Create(glow,   TweenInfo.new(1.4), {ImageTransparency = 1}):Play()
	TweenService:Create(title,  TweenInfo.new(1.0), {TextTransparency = 1}):Play()
	TweenService:Create(subtitle, TweenInfo.new(1.0), {TextTransparency = 1}):Play()
	for _, r in ipairs(rings) do
		local s = r.inst:FindFirstChildOfClass("UIStroke")
		if s then TweenService:Create(s, TweenInfo.new(1.4), {Transparency = 1}):Play() end
	end
	TweenService:Create(music, TweenInfo.new(1.4), {Volume = 0}):Play()

	task.wait(1.5)
	conn:Disconnect()
	music:Stop()
	root:Destroy()
end

return PlaySaturnIntro
