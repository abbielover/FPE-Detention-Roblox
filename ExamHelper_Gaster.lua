--[[
ExamHelper v5 - W.D. GASTER edition
Undertale-style UI: black boxes, white borders, pixel font, red SOUL cursor, glitching title.

Features
  - list exam (VOID EXAM)  -> shows the answer to every equation
  - pick exam (MATH EXAM)  -> finds the equation equal to the middle number,
                              marks it green and outlines it in the game
  - AUTO ANSWER            -> types answers / clicks the right button (clicking needs firesignal)
  - ROLE ESP               -> Teacher = red, Student = green, Guard = blue, MathChoice objects = yellow
  - INF STAMINA            -> keeps ReplicatedStorage.Player.UI.Round.Stats.Stamina maxed

Install: StarterPlayer > StarterPlayerScripts > LocalScript.
Hotkeys: RightShift = minimize / restore | Alt + RightShift = close / reopen the whole UI.

SETTINGS
  FONT_ID -> optional custom font family (e.g. Determination Mono imported through
             Studio Asset Manager > Fonts). Empty = built-in pixel font "Arcade".
  ICON_ID -> optional "rbxassetid://..." image for the minimize bubble.
]]

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RS = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

---------------------------------------------------------------- settings
local FONT_ID = ""
local ICON_ID = ""
local STAMINA_MAX = 100

local FONT = FONT_ID ~= "" and Font.new(FONT_ID) or Font.fromEnum(Enum.Font.Arcade)
local HEART_FONT = Font.fromEnum(Enum.Font.SourceSansBold)

local HL_NAME = "ExamHelperHL"
local ESP_TAG = "ExamHelperESP"
local AUTO = false
local AUTOANSWER = false
local ESP = false
local INFSTAMINA = false
local SCAN_INTERVAL = 0.25 -- seconds between screen reads while AUTO / AUTO ANSWER is on (higher = less lag)
local IDLE_INTERVAL = 0.5  -- used once the current screen is already answered
local ANSWER_DELAY = 0.08 -- short settle time before answering (lower = faster, 0 = instant)
local lastSig = nil
local lastStamScan = 0
local lastGcScan = 0
local SPRINT_SPEED = nil -- optional: your running WalkSpeed (auto-learned if nil)
local SPRINT_MULT = 1.5  -- fallback run speed = walk speed x this, if the real one was never seen
local actionNote = ""

-- intro settings
local SKIP_INTRO = false  -- true = no intro, UI opens right away (use this if flashing bothers you)
local SOUND_ID = ""       -- "rbxassetid://123456" of your uploaded Gaster phone sound (see notes)
local introDone = true    -- UI hotkeys wait until the intro has finished

local BLACK = Color3.fromRGB(0, 0, 0)
local WHITE = Color3.fromRGB(255, 255, 255)
local GRAY = Color3.fromRGB(120, 120, 120)
local DARK = Color3.fromRGB(14, 14, 14)
local RED = Color3.fromRGB(255, 0, 0)       -- SOUL
local YELLOW = Color3.fromRGB(255, 255, 0)  -- selected text
local GREEN = Color3.fromRGB(0, 255, 0)

local ROLES = {
	{ name = "Teacher", color = Color3.fromRGB(255, 0, 0) },
	{ name = "Student", color = Color3.fromRGB(0, 255, 0) },   -- green
	{ name = "Guard",   color = Color3.fromRGB(0, 120, 255) }, -- blue
}

-- ESP target: workspace.Map.Game.Model.MathChoice (only this one)
-- label renames: any object whose name contains the left word is shown as the right text
local LABEL_RENAMES = {
	{ "prompt", "PAPER" },
	{ "promt", "PAPER" }, -- (common misspelling)
}
local MIN_OBJECTS = 10 -- expected number of objects; the Output window warns if fewer are found
local MATHCHOICE_COLOR = Color3.fromRGB(255, 255, 0) -- yellow

---------------------------------------------------------------- helpers
local function make(class, props, parent)
	local o = Instance.new(class)
	if o:IsA("TextLabel") or o:IsA("TextButton") then
		o.FontFace = FONT
	end
	for k, v in pairs(props) do o[k] = v end
	o.Parent = parent
	return o
end

local function stroke(o, color, thick)
	return make("UIStroke", {
		Color = color, Thickness = thick,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		LineJoinMode = Enum.LineJoinMode.Miter,
	}, o)
end

-- drag by `handle`, moves `target`; onTap fires if it was a click, not a drag
local function draggable(handle, target, onTap)
	local dragging, moved, dragStart, startPos = false, false, nil, nil
	handle.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging, moved = true, false
			dragStart, startPos = input.Position, target.Position
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dragging = false
					if not moved and onTap then onTap() end
				end
			end)
		end
	end)
	UIS.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch) then
			local d = input.Position - dragStart
			if d.Magnitude > 5 then moved = true end
			if moved then
				target.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X,
					startPos.Y.Scale, startPos.Y.Offset + d.Y)
			end
		end
	end)
end

---------------------------------------------------------------- UI
local gui = make("ScreenGui", {
	Name = "ExamHelper", ResetOnSpawn = false, DisplayOrder = 999, IgnoreGuiInset = true,
}, playerGui)

local frame = make("Frame", {
	Size = UDim2.fromOffset(240, 350), Position = UDim2.fromOffset(20, 80),
	BackgroundColor3 = BLACK, BorderSizePixel = 0,
}, gui)
stroke(frame, WHITE, 3)

-- header: ghost + title (glitching), subtitle, divider
local header = make("Frame", {
	Size = UDim2.new(1, 0, 0, 36), BackgroundTransparency = 1,
}, frame)

local ghost = make("TextLabel", {
	Size = UDim2.new(1, -40, 0, 20), Position = UDim2.fromOffset(13, 3),
	BackgroundTransparency = 1, Text = "W.D. GASTER", TextColor3 = GRAY,
	TextSize = 16, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 1,
}, header)

local title = make("TextLabel", {
	Size = UDim2.new(1, -40, 0, 20), Position = UDim2.fromOffset(11, 1),
	BackgroundTransparency = 1, Text = "W.D. GASTER", TextColor3 = WHITE,
	TextSize = 16, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 2,
}, header)

make("TextLabel", {
	Size = UDim2.new(1, -40, 0, 10), Position = UDim2.fromOffset(11, 22),
	BackgroundTransparency = 1, Text = "* EXAM HELPER", TextColor3 = GRAY,
	TextSize = 8, TextXAlignment = Enum.TextXAlignment.Left,
}, header)

make("Frame", {
	Size = UDim2.new(1, -12, 0, 2), Position = UDim2.fromOffset(6, 36),
	BackgroundColor3 = WHITE, BorderSizePixel = 0,
}, frame)

-- minimize button
local minBtn = make("TextButton", {
	Size = UDim2.fromOffset(20, 20), Position = UDim2.new(1, -28, 0, 7),
	BackgroundColor3 = BLACK, Text = "_", TextColor3 = WHITE, TextSize = 12,
	BorderSizePixel = 0, AutoButtonColor = false,
}, header)
local minStroke = stroke(minBtn, WHITE, 2)
minBtn.MouseEnter:Connect(function() minStroke.Color = YELLOW; minBtn.TextColor3 = YELLOW end)
minBtn.MouseLeave:Connect(function() minStroke.Color = WHITE; minBtn.TextColor3 = WHITE end)

-- minimized bubble: black box with the red SOUL
local bubble
if ICON_ID ~= "" then
	bubble = make("ImageButton", {
		Size = UDim2.fromOffset(36, 36), Position = frame.Position, BackgroundColor3 = BLACK,
		Image = ICON_ID, ScaleType = Enum.ScaleType.Fit, BorderSizePixel = 0,
	}, gui)
else
	bubble = make("TextButton", {
		Size = UDim2.fromOffset(36, 36), Position = frame.Position, BackgroundColor3 = BLACK,
		Text = "♥", TextColor3 = RED, TextSize = 20, BorderSizePixel = 0, AutoButtonColor = false,
		FontFace = HEART_FONT,
	}, gui)
end
bubble.Visible = false
bubble.ZIndex = 10
stroke(bubble, WHITE, 2)

-- menu buttons: black box, white border, SOUL appears on hover
local function menuButton(text, x, w, y)
	local b = make("TextButton", {
		Size = UDim2.new(w, w == 1 and -12 or -9, 0, 22),
		Position = UDim2.new(x, x == 0 and 6 or 3, 0, y),
		BackgroundColor3 = BLACK, Text = "", BorderSizePixel = 0, AutoButtonColor = false,
	}, frame)
	local s = stroke(b, WHITE, 2)
	local lbl = make("TextLabel", {
		Size = UDim2.new(1, -22, 1, 0), Position = UDim2.fromOffset(20, 0),
		BackgroundTransparency = 1, Text = text, TextColor3 = WHITE, TextSize = 10,
		TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
	}, b)
	local heart = make("TextLabel", {
		Size = UDim2.fromOffset(14, 22), Position = UDim2.fromOffset(4, 0),
		BackgroundTransparency = 1, Text = "♥", TextColor3 = RED, TextSize = 13,
		Visible = false, FontFace = HEART_FONT,
	}, b)

	local state = { on = false, hot = false }
	local function paint()
		local lit = state.hot or state.on
		heart.Visible = lit
		lbl.TextColor3 = lit and YELLOW or WHITE
		s.Color = lit and YELLOW or WHITE
	end
	b.MouseEnter:Connect(function() state.hot = true; paint() end)
	b.MouseLeave:Connect(function() state.hot = false; paint() end)
	return b, lbl, state, paint
end

-- toggle: label shows [ON]/[OFF]; stays lit (yellow + SOUL) while ON
local function toggleButton(name, x, w, y, onChange)
	local b, lbl, state, paint = menuButton(name .. " [OFF]", x, w, y)
	b.MouseButton1Click:Connect(function()
		state.on = not state.on
		lbl.Text = name .. (state.on and " [ON]" or " [OFF]")
		paint()
		onChange(state.on)
	end)
	return b, lbl
end

local scanBtn = menuButton("SCAN", 0, 0.5, 42)

local autoBtn = toggleButton("AUTO", 0.5, 0.5, 42, function(on) AUTO = on end)

local answerBtn = toggleButton("AUTO ANSWER", 0, 1, 68, function(on)
	AUTOANSWER = on
	lastSig, actionNote = nil, ""
end)

local clearESP -- defined below
local espBtn = toggleButton("ESP", 0, 0.5, 94, function(on)
	ESP = on
	if not on then clearESP() end
end)

local stamBtn, stamLbl = toggleButton("STAMINA", 0.5, 0.5, 94, function(on)
	INFSTAMINA = on
	lastStamScan = 0 -- rescan right away
	lastGcScan = -100
end)

local status = make("TextLabel", {
	Size = UDim2.new(1, -12, 0, 16), Position = UDim2.fromOffset(6, 122),
	BackgroundTransparency = 1, Text = "* WAITING FOR EXAM...", TextColor3 = WHITE,
	TextSize = 9, TextXAlignment = Enum.TextXAlignment.Left,
	TextTruncate = Enum.TextTruncate.AtEnd,
}, frame)

make("Frame", {
	Size = UDim2.new(1, -12, 0, 2), Position = UDim2.fromOffset(6, 141),
	BackgroundColor3 = WHITE, BorderSizePixel = 0,
}, frame)

local list = make("ScrollingFrame", {
	Size = UDim2.new(1, -12, 1, -152), Position = UDim2.fromOffset(6, 148),
	BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 3,
	ScrollBarImageColor3 = WHITE, AutomaticCanvasSize = Enum.AutomaticSize.Y,
	CanvasSize = UDim2.new(),
}, frame)
make("UIListLayout", { Padding = UDim.new(0, 4) }, list)

---------------------------------------------------------------- title glitch
task.spawn(function()
	local base = "W.D. GASTER"
	local glyphs = { "#", "%", "@", "&", "?", "0", "1", "/", "*" }
	while gui.Parent do
		task.wait(math.random(15, 40) / 10)
		for _ = 1, math.random(3, 7) do
			local t = base:split("")
			for _ = 1, math.random(1, 3) do
				local k = math.random(#t)
				if t[k] ~= " " and t[k] ~= "." then t[k] = glyphs[math.random(#glyphs)] end
			end
			local s = table.concat(t)
			title.Text, ghost.Text = s, s
			title.Position = UDim2.fromOffset(11 + math.random(-3, 3), 1 + math.random(-2, 2))
			ghost.Position = UDim2.fromOffset(13 + math.random(-3, 3), 3 + math.random(-2, 2))
			task.wait(0.05)
		end
		title.Text, ghost.Text = base, base
		title.Position = UDim2.fromOffset(11, 1)
		ghost.Position = UDim2.fromOffset(13, 3)
	end
end)

---------------------------------------------------------------- minimize / restore
local function minimize()
	bubble.Position = frame.Position
	frame.Visible = false
	bubble.Visible = true
end

local function restore()
	frame.Position = bubble.Position
	bubble.Visible = false
	frame.Visible = true
end

minBtn.MouseButton1Click:Connect(minimize)
draggable(header, frame)
draggable(bubble, bubble, restore)

local function altDown()
	return UIS:IsKeyDown(Enum.KeyCode.LeftAlt) or UIS:IsKeyDown(Enum.KeyCode.RightAlt)
end

UIS.InputBegan:Connect(function(input, processed)
	if processed or not introDone then return end
	local k = input.KeyCode
	if k == Enum.KeyCode.RightShift then
		if altDown() then
			gui.Enabled = not gui.Enabled      -- Alt + RightShift: close / reopen the whole UI
		elseif gui.Enabled then
			if frame.Visible then minimize() else restore() end
		end
	elseif (k == Enum.KeyCode.LeftAlt or k == Enum.KeyCode.RightAlt)
		and UIS:IsKeyDown(Enum.KeyCode.RightShift) then
		gui.Enabled = not gui.Enabled          -- same combo, Alt pressed second
	end
end)

---------------------------------------------------------------- reading the game's GUI
local function clean(s)
	s = s:gsub("<[^>]+>", "")
	s = s:gsub("\u{2212}", "-"):gsub("\u{2013}", "-"):gsub("\u{2014}", "-")
	s = s:gsub("\u{00D7}", "*"):gsub("\u{00F7}", "/"):gsub("%s+", "")
	return s
end

local function isShown(obj)
	local cur = obj
	while cur and cur ~= playerGui do
		if cur:IsA("GuiObject") and not cur.Visible then return false end
		if cur:IsA("ScreenGui") and not cur.Enabled then return false end
		cur = cur.Parent
	end
	return true
end

-- the clickable button that holds / contains this object (nil if none)
local function buttonOf(g)
	local b = g
	while b and b:IsA("GuiObject") do
		if b:IsA("GuiButton") then return b end
		b = b.Parent
	end
	return nil
end

local function evalEq(a, op, b)
	if op == "+" then return a + b end
	if op == "-" then return a - b end
	if op == "/" then
		if b == 0 then return nil end
		return a / b
	end
	return a * b
end

-- visits only what is actually on screen: hidden frames / disabled ScreenGuis are skipped with
-- their whole subtree (much cheaper than GetDescendants + walking up the parents of every object)
local function walkShown(fn)
	local function visit(node)
		for _, c in ipairs(node:GetChildren()) do
			if c:IsA("GuiObject") then
				if c.Visible then
					fn(c)
					visit(c)
				end
			else
				fn(c)
				visit(c)
			end
		end
	end
	for _, sg in ipairs(playerGui:GetChildren()) do
		if sg ~= gui and not (sg:IsA("LayerCollector") and not sg.Enabled) then
			fn(sg)
			visit(sg)
		end
	end
end

local function collect()
	local eqs, nums, consumed = {}, {}, {}
	local texts, groups = {}, {}
	local hint = false

	walkShown(function(d)
		if (d:IsA("TextLabel") or d:IsA("TextButton")) and d.Text ~= "" then
			table.insert(texts, d)
			if d.Text:lower():find("middle", 1, true) then hint = true end
			local p = d.Parent
			groups[p] = groups[p] or {}
			table.insert(groups[p], d)
		end
	end)

	local function midY(o) return o.AbsolutePosition.Y + o.AbsoluteSize.Y / 2 end

	local function addEq(s, holder)
		local a, op, b = s:match("^(%d+)([%+%-%*xX/])(%d+)$")
		if not a then return false end
		local v = evalEq(tonumber(a), op, tonumber(b))
		if v == nil then return false end
		table.insert(eqs, { text = a .. " " .. op .. " " .. b, value = v, gui = holder })
		return true
	end

	-- 1) whole equation in ONE label/button
	for _, d in ipairs(texts) do
		if addEq(clean(d.Text), d) then consumed[d] = true end
	end

	-- 2) equations split into pieces: number, operator, number (same row, side by side)
	for parent, items in pairs(groups) do
		local rest = {}
		for _, t in ipairs(items) do
			if not consumed[t] then table.insert(rest, t) end
		end
		table.sort(rest, function(x, y) return x.AbsolutePosition.X < y.AbsolutePosition.X end)
		for i, t in ipairs(rest) do
			local op = clean(t.Text)
			local l, r = rest[i - 1], rest[i + 1]
			if op:match("^[%+%-%*xX/]$") and not consumed[t] and l and r
				and not consumed[l] and not consumed[r] then
				local ls, rs = clean(l.Text), clean(r.Text)
				local tol = math.max(t.AbsoluteSize.Y, 20)
				if ls:match("^%d+$") and rs:match("^%d+$")
					and math.abs(midY(l) - midY(t)) < tol and math.abs(midY(r) - midY(t)) < tol then
					local holder = buttonOf(t)
					if not holder and #rest == 3 and parent:IsA("GuiObject") then holder = parent end
					if addEq(ls .. op .. rs, holder or t) then
						consumed[l], consumed[t], consumed[r] = true, true, true
					end
				end
			end
		end
	end

	-- 3) standalone numbers (candidates for the "middle number")
	for _, d in ipairs(texts) do
		if not consumed[d] then
			local s = clean(d.Text)
			if s:match("^%-?%d+$") then
				table.insert(nums, { value = tonumber(s), gui = d })
			end
		end
	end

	table.sort(eqs, function(x, y) return x.gui.AbsolutePosition.Y < y.gui.AbsolutePosition.Y end)
	return eqs, nums, hint
end

---------------------------------------------------------------- showing results
local function addRow(eqText, answer, match)
	local row = make("Frame", {
		Size = UDim2.new(1, -6, 0, 26), BorderSizePixel = 0, BackgroundColor3 = BLACK,
	}, list)
	stroke(row, match and GREEN or WHITE, 2)

	make("TextLabel", {
		Size = UDim2.new(1, -64, 1, 0), Position = UDim2.fromOffset(8, 0),
		BackgroundTransparency = 1, Text = (match and "♥ " or "* ") .. eqText,
		TextColor3 = match and GREEN or WHITE, TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, row)
	make("TextLabel", {
		Size = UDim2.fromOffset(56, 26), Position = UDim2.new(1, -60, 0, 0),
		BackgroundTransparency = 1, Text = "= " .. answer,
		TextColor3 = match and GREEN or YELLOW, TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Right,
	}, row)
end

local function highlight(g)
	local b = buttonOf(g) or g
	if b and b:IsA("GuiObject") then
		local s = stroke(b, GREEN, 4)
		s.Name = HL_NAME
	end
end

local function clearAll()
	for _, c in ipairs(list:GetChildren()) do
		if c:IsA("Frame") then c:Destroy() end
	end
	for _, h in ipairs(playerGui:GetDescendants()) do
		if h.Name == HL_NAME then h:Destroy() end
	end
end

---------------------------------------------------------------- auto answer
local function click(btn)
	if not firesignal then return false end
	if getconnections then
		for _, sig in ipairs({ btn.Activated, btn.MouseButton1Click }) do
			local ok, conns = pcall(getconnections, sig)
			if ok and #conns > 0 then return (pcall(firesignal, sig)) end
		end
	end
	return (pcall(firesignal, btn.MouseButton1Click))
end

local function shown(class)
	local out = {}
	walkShown(function(d)
		if d:IsA(class) then table.insert(out, d) end
	end)
	return out
end

local function cx(o) return o.AbsolutePosition.X + o.AbsoluteSize.X / 2 end
local function cy(o) return o.AbsolutePosition.Y + o.AbsoluteSize.Y / 2 end

local function nearestInRow(holder, cands, minX)
	if not holder:IsA("GuiObject") then return nil end
	local tol = math.max(holder.AbsoluteSize.Y, 24)
	local best, bestD
	for _, c in ipairs(cands) do
		if c ~= holder and (not minX or cx(c) > minX) then
			local d = math.abs(cy(c) - cy(holder))
			if d < tol and (not bestD or d < bestD) then best, bestD = c, d end
		end
	end
	return best
end

local function fillAndSend(eqs)
	local boxes = shown("TextBox")
	local checks, send = {}, nil
	for _, b in ipairs(shown("GuiButton")) do
		if b:IsA("TextButton") and b.Text:lower():find("send", 1, true) then
			send = b
		elseif not b:IsA("TextButton") or (b.Text:gsub("%s", "")) == "" then
			table.insert(checks, b)
		end
	end

	local filled = 0
	for _, e in ipairs(eqs) do
		local box = nearestInRow(e.gui, boxes)
		if box then
			box.Text = tostring(e.value)
			filled += 1
			local chk = nearestInRow(e.gui, checks, cx(box))
			if chk then click(chk) end
			-- (no wait between boxes: as fast as possible)
		end
	end

	local sent = false
	if send and filled > 0 then sent = click(send) end
	return filled, sent
end

-- reads the screen and decides: list exam or pick exam, which equation(s) win
local function analyze()
	local eqs, nums, hint = collect()
	if #eqs == 0 then return nil end

	-- candidates for the middle number: numbers that are NOT inside a button
	local cands = {}
	for _, n in ipairs(nums) do
		if not buttonOf(n.gui) then table.insert(cands, n) end
	end
	if #cands == 0 then cands = nums end

	-- the middle number sits in the middle of the equations: sort by distance to their center
	local minX, maxX = math.huge, -math.huge
	for _, e in ipairs(eqs) do
		minX = math.min(minX, cx(e.gui))
		maxX = math.max(maxX, cx(e.gui))
	end
	local mid = (minX + maxX) / 2
	table.sort(cands, function(x, y)
		return math.abs(cx(x.gui) - mid) < math.abs(cx(y.gui) - mid)
	end)

	local function hasEq(v)
		for _, e in ipairs(eqs) do
			if e.value == v then return true end
		end
		return false
	end

	-- first candidate (closest to center) that really has a matching equation
	local target
	for _, c in ipairs(cands) do
		if hasEq(c.value) then target = c break end
	end
	target = target or cands[1]

	local pickExam = target ~= nil
		and (hint or (#cands == 1 and hasEq(target.value) and #shown("TextBox") == 0))

	local winners = {}
	if pickExam then
		for _, e in ipairs(eqs) do
			if e.value == target.value then table.insert(winners, e) end
		end
	end

	local parts = {}
	for _, e in ipairs(eqs) do table.insert(parts, e.text) end
	return {
		pick = pickExam, eqs = eqs, winners = winners, target = target,
		sig = table.concat(parts, ",") .. "|" .. (pickExam and target.value or ""),
	}
end

local function autoAnswer(info)
	if not info or info.sig == lastSig then return end
	lastSig = info.sig
	task.wait(ANSWER_DELAY)

	-- the screen may still have been animating: read it again and make sure it is the same
	local cur = analyze()
	if not cur or cur.sig ~= info.sig then
		lastSig = nil -- changed under us; try again next tick
		return
	end

	if cur.pick then
		for _, e in ipairs(cur.winners) do
			local b = buttonOf(e.gui)
			print("[ExamHelper] middle =", cur.target.value, "| answer =", e.text, "=", e.value,
				"| button =", b and b:GetFullName() or "none")
			if b and click(b) then
				actionNote = "CLICKED " .. e.text
				return
			end
		end
		actionNote = #cur.winners == 0 and "NO MATCH"
			or (firesignal and "NO BUTTON FOUND" or "CAN'T CLICK HERE")
	else
		local filled, sent = fillAndSend(cur.eqs)
		actionNote = sent and ("FILLED " .. filled .. " + SENT")
			or ("FILLED " .. filled .. (firesignal and ", NO SEND" or ", CAN'T CLICK"))
	end
end

local function render()
	clearAll()

	local info = analyze()
	if not info then
		status.Text = "* NO EQUATIONS FOUND"
		status.TextColor3 = GRAY
		lastSig = nil
		return nil
	end

	status.TextColor3 = WHITE
	if info.pick then
		status.Text = "* PICK EXAM | MIDDLE = " .. info.target.value
	else
		status.Text = "* LIST EXAM | " .. #info.eqs .. " PROBLEMS"
	end

	local isWinner = {}
	for _, w in ipairs(info.winners) do isWinner[w] = true end

	for _, e in ipairs(info.eqs) do
		local match = isWinner[e] or false
		addRow(e.text, e.value, match)
		if match then highlight(e.gui) end
	end

	if AUTOANSWER and actionNote ~= "" then
		status.Text = status.Text .. " [" .. actionNote .. "]"
	end
	return info
end

---------------------------------------------------------------- role ESP
local lastObjScan, lastObjSummary = 0, nil
local marks = {}       -- [part] = { box = BoxHandleAdornment, tag = BillboardGui }
local wantedNow = {}   -- parts that should be marked in the scan that is running
local objDirty = true  -- set when something is added to / removed from Model

function clearESP()
	lastObjSummary, lastObjScan, objDirty = nil, 0, true
	for k in pairs(marks) do marks[k] = nil end
	for _, d in ipairs(workspace:GetDescendants()) do
		if d.Name == ESP_TAG then d:Destroy() end
	end
end

local function applyESP(obj, color)
	if not (obj:IsA("Model") or obj:IsA("BasePart")) or obj:FindFirstChild(ESP_TAG) then return end
	local h = Instance.new("Highlight")
	h.Name = ESP_TAG
	h.FillColor = color
	h.OutlineColor = color
	h.FillTransparency = 0.5
	h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	h.Parent = obj
end

-- highlight `holder` itself (Model / Part) or, if it is a Folder, every child inside it
local function espHolder(holder, color)
	if holder:IsA("Model") or holder:IsA("BasePart") then
		applyESP(holder, color)
	else
		for _, m in ipairs(holder:GetChildren()) do
			applyESP(m, color)
		end
	end
end

---- MathChoice ESP -----------------------------------------------------------
-- * ALWAYS searching: rescans twice a second, and immediately when something is added to or
--   removed from workspace.Map.Game.Model.
-- * Looks for MathChoice inside Model (any depth). If none exists, it falls back to the most
--   similar names (choice / paper / prompt, then math / answer / question / quiz / exam, then
--   any name close to "MathChoice").
-- * When a marked part is gone (deleted, moved out of Model), its mark is removed too.
-- Uses box adornments + labels instead of Highlights (Roblox only draws ~31 Highlights).
local function destroyMark(part)
	local m = marks[part]
	if m then
		if m.box then m.box:Destroy() end
		if m.tag then m.tag:Destroy() end
		marks[part] = nil
	end
end

local function boxPart(part)
	wantedNow[part] = true
	local m = marks[part]
	if m and m.box and m.box.Parent then return end
	local box = Instance.new("BoxHandleAdornment")
	box.Name = ESP_TAG
	box.Adornee = part
	box.Size = part.Size + Vector3.new(0.15, 0.15, 0.15)
	box.Color3 = MATHCHOICE_COLOR
	box.Transparency = 0.45
	box.AlwaysOnTop = true
	box.ZIndex = 5
	box.Parent = part
	marks[part] = marks[part] or {}
	marks[part].box = box
end

local function displayName(name)
	local n = name:lower()
	for _, r in ipairs(LABEL_RENAMES) do
		if n:find(r[1], 1, true) then return r[2] end
	end
	return name
end

local function labelPart(part, text)
	wantedNow[part] = true
	local m = marks[part]
	if m and m.tag and m.tag.Parent then return end
	local tag = Instance.new("BillboardGui")
	tag.Name = ESP_TAG
	tag.Adornee = part
	tag.Size = UDim2.fromOffset(90, 16)
	tag.StudsOffset = Vector3.new(0, 2, 0)
	tag.AlwaysOnTop = true
	tag.Parent = part
	local txt = Instance.new("TextLabel")
	txt.Size = UDim2.fromScale(1, 1)
	txt.BackgroundTransparency = 1
	txt.Text = displayName(text)
	txt.FontFace = FONT
	txt.TextSize = 12
	txt.TextColor3 = MATHCHOICE_COLOR
	txt.TextStrokeTransparency = 0
	txt.Parent = tag
	marks[part] = marks[part] or {}
	marks[part].tag = tag
end

-- box every part inside `mc`, label every object (any depth) inside it
local function espMathChoice(mc)
	local nParts = 0
	if mc:IsA("BasePart") then boxPart(mc); nParts += 1 end
	for _, d in ipairs(mc:GetDescendants()) do
		if d:IsA("BasePart") then
			boxPart(d)
			nParts += 1
			if nParts >= 1000 then break end
		end
	end

	local nObjs = 0
	for _, d in ipairs(mc:GetDescendants()) do
		if d.Name ~= ESP_TAG then
			if d:IsA("Model") then
				for _, c in ipairs(d:GetChildren()) do
					if c:IsA("BasePart") then
						labelPart(c, d.Name)
						nObjs += 1
						break
					end
				end
			elseif d:IsA("BasePart") then
				local m = d:FindFirstAncestorOfClass("Model")
				if not m or not m:IsDescendantOf(mc) then
					labelPart(d, d.Name)
					nObjs += 1
				end
			end
		end
	end
	if nObjs == 0 and mc:IsA("BasePart") then labelPart(mc, mc.Name); nObjs = 1 end
	return nObjs, nParts
end

-- similarity helpers -------------------------------------------------------
local TIERS = {
	{ "paper", "sheet", "prompt", "promt", "choice" },
	{ "exam", "math", "answer", "question", "quiz", "test" },
}

local function edit(a, b) -- Levenshtein distance
	local la, lb = #a, #b
	local prev, cur = {}, {}
	for j = 0, lb do prev[j] = j end
	for i = 1, la do
		cur[0] = i
		for j = 1, lb do
			local cost = a:byte(i) == b:byte(j) and 0 or 1
			cur[j] = math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
		end
		prev, cur = cur, prev
	end
	return prev[lb]
end

-- names are normalised (lowercase, no spaces / _ / -) so "Exam Paper", "ExamPaper", "exam_paper" all match
local function norm(n) return (n:lower():gsub("[%s_%-%.]", "")) end

local function matchExact(n)
	n = norm(n)
	return n:find("mathchoice", 1, true) ~= nil or n:find("mathexam", 1, true) ~= nil
		or n:find("exampaper", 1, true) ~= nil
end

local function matchTier(words)
	return function(n)
		n = norm(n)
		for _, w in ipairs(words) do
			if n:find(w, 1, true) then return true end
		end
		return false
	end
end

local function matchClose(n)
	n = norm(n)
	return #n >= 6 and #n <= 16
		and (edit(n, "exampaper") <= 3 or edit(n, "mathchoice") <= 4 or edit(n, "mathexam") <= 3)
end

-- top-most descendants of `root` whose name passes `pred`
local function findAll(root, pred)
	local out = {}
	for _, d in ipairs(root:GetDescendants()) do
		if d.Name ~= ESP_TAG and pred(d.Name)
			and (d:IsA("Model") or d:IsA("BasePart") or d:IsA("Folder")) then
			local nested, cur = false, d.Parent
			while cur and cur ~= root do
				if pred(cur.Name) then nested = true break end
				cur = cur.Parent
			end
			if not nested then table.insert(out, d) end
		end
	end
	return out
end

local hookedModel, hookConns = nil, {}
local function hookModel(model)
	if hookedModel == model then return end
	for _, c in ipairs(hookConns) do c:Disconnect() end
	hookConns, hookedModel = {}, model
	if model then
		table.insert(hookConns, model.DescendantAdded:Connect(function() objDirty = true end))
		table.insert(hookConns, model.DescendantRemoving:Connect(function() objDirty = true end))
	end
end

local function scanObjects()
	-- step 1: keep looking for workspace.Map.Game.Model until it exists
	local map = workspace:FindFirstChild("Map")
	local g = map and map:FindFirstChild("Game")
	local model = g and g:FindFirstChild("Model")
	hookModel(model)

	wantedNow = {}
	local text, found = nil, {}
	if not model then
		text = "workspace.Map.Game.Model not found (still searching)"
	else
		-- step 2: Model exists -> look ONLY inside it for MathChoice / MathExam (then similar names)
		local mode = "exact"
		found = findAll(model, matchExact)
		if #found == 0 then
			for i, words in ipairs(TIERS) do
				found = findAll(model, matchTier(words))
				if #found > 0 then mode = "similar" .. i break end
			end
		end
		if #found == 0 then
			found = findAll(model, matchClose)
			mode = "close"
		end

		local objs, parts, names = 0, 0, {}
		for _, mc in ipairs(found) do
			local o, p = espMathChoice(mc)
			objs += o
			parts += p
			if #names < 6 then table.insert(names, mc.Name) end
		end
		text = "Model found | MathChoice/MathExam " .. (#found == 0 and "NOT found (nothing similar either)" or
			(mode .. " [" .. table.concat(names, ",") .. "]")) ..
			" found=" .. #found .. " objects=" .. objs .. " parts=" .. parts
		if #found > 0 and objs < MIN_OBJECTS then
			text = text .. "  (fewer than " .. MIN_OBJECTS .. "!)"
		end
	end

	-- remove marks of parts that are gone (deleted / left Model / no longer wanted)
	for part in pairs(marks) do
		if not wantedNow[part] or not part:IsDescendantOf(workspace) then
			destroyMark(part)
		end
	end

	if text ~= lastObjSummary then
		lastObjSummary = text
		print("[ExamHelper] ESP:", text)
		if model and (#found == 0 or text:find("fewer", 1, true)) then
			local n = 0
			for _, d in ipairs(model:GetDescendants()) do
				if d.Name ~= ESP_TAG then
					print("   ", d:GetFullName(), "(" .. d.ClassName .. ")")
					n += 1
					if n >= 80 then print("    ..."); break end
				end
			end
		end
	end
end

local function refreshESP()
	local root = workspace:FindFirstChild("Players")
	if root then
		for _, role in ipairs(ROLES) do
			local holder = root:FindFirstChild(role.name)
			if holder then espHolder(holder, role.color) end
		end
	end

	if objDirty or os.clock() - lastObjScan > 0.5 then
		objDirty = false
		lastObjScan = os.clock()
		scanObjects()
	end
end

---------------------------------------------------------------- infinite stamina
-- The copy in ReplicatedStorage is usually only a template: the game clones it into
-- PlayerGui / the player / the character. So we search ALL of those for anything named
-- "Stamina" (NumberValue, IntValue or an Attribute), lock every one of them every frame,
-- and snap them back the instant the game lowers them.
local RunService = game:GetService("RunService")

local stamList = {}  -- { inst, attr, max }
local stamSeen = {}  -- [inst][attr or "Value"] = true

local function isStam(name)
	return type(name) == "string" and name:lower():find("stamina", 1, true) ~= nil
end

local function readS(t)
	if t.attr then return t.inst:GetAttribute(t.attr) end
	return t.inst.Value
end

local function writeS(t, v)
	if t.attr then t.inst:SetAttribute(t.attr, v) else t.inst.Value = v end
end

local function lockOne(t)
	if not t.inst.Parent then return end
	local cur = readS(t)
	if type(cur) ~= "number" then return end
	if cur > t.max then t.max = cur end
	if cur < t.max then writeS(t, t.max) end
end

local function addStam(inst, attr)
	local key = attr or "Value"
	stamSeen[inst] = stamSeen[inst] or {}
	if stamSeen[inst][key] then return end
	stamSeen[inst][key] = true

	local t = { inst = inst, attr = attr }
	local cur = readS(t)
	if type(cur) ~= "number" then return end
	-- guess the scale: 0..1 bars vs 0..100 values
	if cur > 1 then t.max = math.max(cur, STAMINA_MAX)
	elseif cur > 0 then t.max = 1
	else t.max = STAMINA_MAX end
	table.insert(stamList, t)

	local sig = attr and inst:GetAttributeChangedSignal(attr) or inst.Changed
	sig:Connect(function()
		if INFSTAMINA then lockOne(t) end
	end)
	print("[ExamHelper] stamina target:", inst:GetFullName(), attr and ("attribute " .. attr) or inst.ClassName,
		"= " .. tostring(cur))
end

local function scanInst(d)
	if d == gui or d:IsDescendantOf(gui) then return end
	if isStam(d.Name) and (d:IsA("NumberValue") or d:IsA("IntValue")) then
		addStam(d, nil)
	end
	for k, v in pairs(d:GetAttributes()) do
		if isStam(k) and type(v) == "number" then addStam(d, k) end
	end
end

local function scanStamina()
	for i = #stamList, 1, -1 do -- drop destroyed ones
		if not stamList[i].inst.Parent then table.remove(stamList, i) end
	end
	local roots = { RS, playerGui, player, player.Character }
	for _, r in ipairs(roots) do
		scanInst(r)
		for _, d in ipairs(r:GetDescendants()) do scanInst(d) end
	end
	if INFSTAMINA then
		stamLbl.Text = "STAMINA [" .. (#stamList > 0 and tostring(#stamList) or "NONE") .. "]"
	end
end

-- Method 2: stamina kept in a script variable / module table (not in any Instance).
-- With an executor that has getgc, find tables that have a "Stamina" number and lock them too.
local GC_KEYS = { "Stamina", "stamina", "CurrentStamina", "currentStamina", "Stam" }
local gcTargets, gcSeen = {}, setmetatable({}, { __mode = "k" })

local function scanGC()
	if not getgc then return end
	local ok, objs = pcall(getgc, true)
	if not ok or type(objs) ~= "table" then return end
	for _, o in ipairs(objs) do
		if type(o) == "table" and #gcTargets < 25 then
			for _, k in ipairs(GC_KEYS) do
				local v = rawget(o, k)
				if type(v) == "number" and not (gcSeen[o] and gcSeen[o][k]) then
					gcSeen[o] = gcSeen[o] or {}
					gcSeen[o][k] = true
					local max = (v > 1 and math.max(v, STAMINA_MAX)) or (v > 0 and 1) or STAMINA_MAX
					table.insert(gcTargets, { tbl = o, key = k, max = max })
					print("[ExamHelper] stamina table field:", k, "=", v)
				end
			end
		end
	end
end

local function lockGc()
	for i = #gcTargets, 1, -1 do
		local t = gcTargets[i]
		local ok = pcall(function()
			local cur = rawget(t.tbl, t.key)
			if type(cur) ~= "number" then error("gone") end
			if cur > t.max then t.max = cur end
			if cur < t.max then rawset(t.tbl, t.key, t.max) end
		end)
		if not ok then table.remove(gcTargets, i) end
	end
end

-- Method 3: sprint speed. Many games simply stop the run when stamina is 0 by lowering
-- WalkSpeed. While LeftShift is held we keep a running speed (learned from when the game
-- itself ran you, otherwise walk speed x SPRINT_MULT).
local baseSpeed, runSpeed, lastSet = nil, nil, nil
local function sprintAssist()
	local ch = player.Character
	local hum = ch and ch:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	local shift = UIS:IsKeyDown(Enum.KeyCode.LeftShift) and not UIS:GetFocusedTextBox()
	if not shift then
		if lastSet and hum.WalkSpeed == lastSet and baseSpeed then
			hum.WalkSpeed = baseSpeed -- give back normal speed after letting go
		end
		lastSet = nil
		baseSpeed = hum.WalkSpeed
		return
	end

	-- learn what the game's own run speed is (ignore values we wrote ourselves)
	if baseSpeed and hum.WalkSpeed > baseSpeed + 1 and hum.WalkSpeed ~= lastSet then
		runSpeed = math.max(runSpeed or 0, hum.WalkSpeed)
	end
	local want = SPRINT_SPEED or runSpeed or (baseSpeed and baseSpeed * SPRINT_MULT)
	if want and hum.WalkSpeed < want then
		lastSet = want
		hum.WalkSpeed = want
	end
end

local function staminaTick()
	if not INFSTAMINA then return end
	local now = os.clock()
	if now - lastStamScan > 10 then
		lastStamScan = now
		scanStamina()
	end
	if now - lastGcScan > 30 then
		lastGcScan = now
		scanGC()
		if #gcTargets > 0 then
			stamLbl.Text = "STAMINA [" .. (#stamList + #gcTargets) .. "]"
		end
	end
	for _, t in ipairs(stamList) do lockOne(t) end
	lockGc()
	sprintAssist()
end

-- run both early and LAST in the frame, so we have the final word over the game's own scripts
RunService.Heartbeat:Connect(staminaTick)
pcall(function()
	RunService:BindToRenderStep("ExamHelperStamina", Enum.RenderPriority.Last.Value, staminaTick)
end)

---------------------------------------------------------------- buttons + main loop
scanBtn.MouseButton1Click:Connect(render)

task.spawn(function()
	local lastRenderSig, lastNote, lastEsp = nil, "", 0
	while gui.Parent do
		if AUTO or AUTOANSWER then
			-- read the screen once per tick; only redraw the panel when something changed
			local info = analyze()
			local sigNow = info and info.sig or ""
			if sigNow ~= lastRenderSig then
				lastRenderSig = sigNow
				render()
			end
			if AUTOANSWER then
				autoAnswer(info)
				if actionNote ~= lastNote then
					lastNote = actionNote
					render()
				end
			end
		end
		if ESP and os.clock() - lastEsp > 0.4 then
			lastEsp = os.clock()
			refreshESP()
		end
		-- pace: normal while waiting for a new screen, slower once this screen is already answered
		local alreadyDone = AUTOANSWER and lastRenderSig ~= nil and lastRenderSig == lastSig
		task.wait(alreadyDone and IDLE_INTERVAL or SCAN_INTERVAL)
	end
end)

---------------------------------------------------------------- GASTER INTRO
-- 1) game music is muted, the whole screen glitches (+ Gaster phone sound), ERROR flickers in the middle
-- 2) "THIS SCRIPT MADE BY COF" appears as random glitch symbols, then resolves into the real text
-- 3) "THIS SCRIPT STILL BETA AND WON'T BE UPDATE" does the same
-- 4) the glitch fragments slowly fly together and assemble into the menu, the glitch dies down
--    and fades out, then the game music comes back
--
-- SOUND: the script downloads the sound itself (needs an executor with request + writefile +
-- getcustomasset). Without those, upload the mp3 to Roblox and set SOUND_ID at the top.
local SOUND_URL = "https://www.myinstants.com/media/sounds/tmp9_3vr01i.mp3"

if not SKIP_INTRO then
	introDone = false
	gui.Enabled = false

	local intro = make("ScreenGui", {
		Name = "ExamHelperIntro", ResetOnSpawn = false, DisplayOrder = 1000, IgnoreGuiInset = true,
	}, playerGui)
	local bg = make("Frame", {
		Size = UDim2.fromScale(1, 1), BackgroundColor3 = BLACK, BorderSizePixel = 0,
	}, intro)

	---------------- mute the game's own music until the glitch is gone
	local muted = {} -- [Sound] = original volume
	local function muteSound(s)
		if s:IsA("Sound") and not s:IsDescendantOf(intro) and muted[s] == nil then
			muted[s] = s.Volume
			s.Volume = 0
		end
	end
	for _, d in ipairs(game:GetDescendants()) do pcall(muteSound, d) end
	local muteConn = game.DescendantAdded:Connect(function(d) pcall(muteSound, d) end)
	local function unmuteAll()
		muteConn:Disconnect()
		for s, v in pairs(muted) do
			if s.Parent then s.Volume = v end
		end
		muted = {}
	end

	---------------- Gaster phone sound
	task.spawn(function()
		local id = SOUND_ID ~= "" and SOUND_ID or nil
		if not id then
			local req = (syn and syn.request) or request or http_request
			local asset = getcustomasset or getsynasset
			if req and writefile and asset then
				local ok, res = pcall(function()
					local r = req({ Url = SOUND_URL, Method = "GET" })
					if not r or type(r.Body) ~= "string" or #r.Body < 1000 then error("download failed") end
					writefile("gaster_phone.mp3", r.Body)
					return asset("gaster_phone.mp3")
				end)
				if ok then id = res else warn("[ExamHelper] sound download failed:", res) end
			else
				warn("[ExamHelper] no sound: executor has no request/writefile/getcustomasset and SOUND_ID is empty")
			end
		end
		if not id or not intro.Parent then return end
		local snd = Instance.new("Sound")
		snd.SoundId = id
		snd.Volume = 1
		snd.Parent = intro
		local t0 = os.clock()
		while not snd.IsLoaded and os.clock() - t0 < 4 do task.wait(0.05) end
		if intro.Parent then snd:Play() end
	end)

	---------------- glitch pieces
	local WING = { "✌", "☜", "☞", "☟", "✍", "✎", "✂", "✆", "✈", "✉", "☎", "☠", "☢",
		"☣", "☮", "☯", "☸", "☹", "☺", "☻", "☼", "☽", "☾", "♀", "♂", "♠" }
	local POOL = {}
	for _, s in ipairs(WING) do POOL[#POOL + 1] = s end
	for _, s in ipairs({ "#", "%", "@", "&", "?", "0", "1", "/", "*", "!", "$", "X" }) do POOL[#POOL + 1] = s end

	local GL = { "#", "%", "@", "&", "?", "0", "1", "/", "*", "ERROR", "ERR0R", "NULL",
		"0x00", "NaN", "??", "!!", "FATAL" }
	local ERRS = { "ERROR", "ERR0R", "FATAL ERROR", "???", "NULL", "0x000000" }
	local GCOL = { WHITE, WHITE, GRAY, RED, Color3.fromRGB(0, 255, 255) }
	local function randomGlitch()
		if math.random() < 0.5 then return GL[math.random(#GL)] end
		local t = {}
		for i = 1, math.random(2, 8) do t[i] = GL[math.random(9)] end
		return table.concat(t)
	end

	local vp = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
	local fx, fy = frame.Position.X.Offset, frame.Position.Y.Offset
	local fw, fh = frame.Size.X.Offset, frame.Size.Y.Offset

	local frags, bars = {}, {}
	for i = 1, 110 do
		local l = make("TextLabel", {
			Size = UDim2.fromOffset(120, 30), BackgroundTransparency = 1, Text = "",
			TextSize = 20, ZIndex = 5, Visible = false, TextColor3 = WHITE,
		}, intro)
		frags[i] = { l = l, tx = fx + math.random(0, fw), ty = fy + math.random(0, fh) } -- where it settles
	end
	for i = 1, 40 do
		bars[i] = make("Frame", {
			BorderSizePixel = 0, BackgroundColor3 = WHITE, ZIndex = 3, Visible = false,
		}, intro)
	end

	local centerErr = make("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, 0, 0, 90), BackgroundTransparency = 1, Text = "ERROR",
		TextSize = 72, TextColor3 = RED, ZIndex = 8,
	}, intro)
	local msg = make("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -40, 0, 120), BackgroundTransparency = 1, Text = "",
		TextSize = 26, TextColor3 = WHITE, TextWrapped = true, ZIndex = 20,
		TextStrokeTransparency = 0,
	}, intro)

	-- conv: 0 -> 1 while the fragments fly together | fade: 0 -> 1 while what is left disappears
	local conv, fade = 0, 0

	local function lerp(a, b, t) return a + (b - a) * t end

	task.spawn(function()
		while intro.Parent do
			-- keep the game music muted (games often set the volume again)
			for s in pairs(muted) do
				if s.Parent and s.Volume ~= 0 then s.Volume = 0 end
			end

			local chaos = 1 - conv -- how wild the glitch still is
			for _, f in ipairs(frags) do
				local l = f.l
				local show = (0.35 + 0.4 * conv) * (1 - fade)
				if math.random() < show then
					l.Visible = true
					l.Text = randomGlitch()
					local rx, ry = math.random() * vp.X, math.random() * vp.Y
					local jx, jy = (math.random() - 0.5) * 30 * chaos, (math.random() - 0.5) * 30 * chaos
					l.Position = UDim2.fromOffset(lerp(rx, f.tx, conv) + jx, lerp(ry, f.ty, conv) + jy)
					l.TextSize = math.floor(lerp(math.random(10, 44), 9, conv))
					l.TextColor3 = GCOL[math.random(#GCOL)]
					l.TextTransparency = math.clamp(lerp(math.random() * 0.5, 0.55, conv) + fade, 0, 1)
				else
					l.Visible = false
				end
			end
			for _, b in ipairs(bars) do
				if math.random() < 0.3 * chaos then
					b.Visible = true
					b.Size = UDim2.new(math.random(10, 100) / 100, 0, 0, math.random(2, 12))
					b.Position = UDim2.fromScale(math.random(), math.random())
					b.BackgroundColor3 = GCOL[math.random(#GCOL)]
					b.BackgroundTransparency = 0.6 + math.random() * 0.3
				else
					b.Visible = false
				end
			end
			if conv < 1 then
				bg.BackgroundColor3 = math.random() < 0.08 * chaos and DARK or BLACK
			end

			-- flickering error in the middle (fades out instead of vanishing)
			centerErr.Visible = math.random() < 0.55 * chaos
			centerErr.Text = ERRS[math.random(#ERRS)]
			centerErr.TextColor3 = math.random() < 0.5 and RED or WHITE
			centerErr.TextTransparency = conv * 0.8
			centerErr.Position = UDim2.new(0.5, math.random(-8, 8) * chaos, 0.5, math.random(-6, 6) * chaos)

			task.wait(0.06)
		end
	end)

	---------------- special text: random glitch symbols that resolve into the real words
	-- p = how much of the text is already real (0 = all random, 1 = clean), gc = chance that a real
	-- letter is glitching right now
	local function setMsg(text, p, gc)
		local out, sym, n = {}, false, #text
		for i = 1, n do
			local ch = text:sub(i, i)
			if ch == " " then
				out[i] = " "
			elseif (i - 1) / n < p and math.random() > gc then
				out[i] = ch
			else
				local r = POOL[math.random(#POOL)]
				out[i] = r
				if #r > 1 then sym = true end
			end
		end
		msg.FontFace = sym and HEART_FONT or FONT
		msg.Text = table.concat(out)
	end

	local function showMessage(text)
		for _ = 1, 5 do -- random noise blinking
			for _ = 1, 3 do setMsg(text, 0, 1); task.wait(0.05) end
			msg.Text = ""
			task.wait(0.09)
		end
		for k = 0, 1, 0.04 do -- letters lock in one by one
			setMsg(text, k, 0.15)
			task.wait(0.035)
		end
		local t0 = os.clock()
		while os.clock() - t0 < 1.6 do -- hold, with small random glitches
			if math.random() < 0.12 then setMsg(text, 0.6, 0.3) else setMsg(text, 1, 0.02) end
			task.wait(0.06)
		end
		for k = 1, 0, -0.05 do -- dissolve back into noise
			setMsg(text, k, 0.2)
			task.wait(0.03)
		end
		for _ = 1, 3 do
			setMsg(text, 0, 1); task.wait(0.06)
			msg.Text = ""; task.wait(0.07)
		end
		msg.Text = ""
	end

	---------------- the end: assemble into the UI, glitch dies down, music returns
	local function assemble()
		msg.Text = ""
		local DUR = 3.5
		local t0 = os.clock()
		local menuShown = false
		while true do
			conv = math.clamp((os.clock() - t0) / DUR, 0, 1)
			bg.BackgroundTransparency = conv * conv
			if conv > 0.5 and not menuShown then
				menuShown = true
				gui.Enabled = true
				task.spawn(function() -- menu flickers into existence
					for _ = 1, 8 do
						frame.Visible = not frame.Visible
						task.wait(0.06)
					end
					frame.Visible = true
				end)
			end
			if conv >= 1 then break end
			task.wait()
		end

		local t1 = os.clock()
		while fade < 1 do -- leftover fragments fade away
			fade = math.clamp((os.clock() - t1) / 1.2, 0, 1)
			task.wait()
		end
		unmuteAll()
		intro:Destroy()
		introDone = true
	end

	task.spawn(function()
		task.wait(1.2) -- pure glitch first
		showMessage("THIS SCRIPT MADE BY COF")
		task.wait(0.5)
		showMessage("THIS SCRIPT STILL BETA AND WON'T BE UPDATE")
		task.wait(0.4)
		assemble()
	end)
end
