
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

local LocalPlayer = Players.LocalPlayer

local Library = {
    Windows = {},
    Connections = {},
    Flags = {},

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
        BlurEnabled = true,
        BlurSize = 8,
        BackgroundTransparency = 0.5,
        FadeTime = 0.20,
        SliderTweenTime = 0.08,
        DropdownMaxHeight = 230,
        DropdownRowHeight = 34,
    },
}

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

        valueBox.Text = tostring(value) .. tostring(config.ValueName or "")
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

    connect(valueBox.Activated, function()
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
                popup.Visible = false
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

    connect(UserInputService.InputBegan, function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
            return
        end

        if not popup.Visible then
            return
        end

        local mouse = UserInputService:GetMouseLocation()

        local popupPos = popup.AbsolutePosition
        local popupSize = popup.AbsoluteSize
        local insidePopup =
            mouse.X >= popupPos.X and
            mouse.X <= popupPos.X + popupSize.X and
            mouse.Y >= popupPos.Y and
            mouse.Y <= popupPos.Y + popupSize.Y

        local buttonPos = button.AbsolutePosition
        local buttonSize = button.AbsoluteSize
        local insideButton =
            mouse.X >= buttonPos.X and
            mouse.X <= buttonPos.X + buttonSize.X and
            mouse.Y >= buttonPos.Y and
            mouse.Y <= buttonPos.Y + buttonSize.Y

        if not insidePopup and not insideButton then
            popup.Visible = false
        end
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
        Parent = frame,
    })
    addCorner(swatch, 6)
    addStroke(swatch, Color3.new(1, 1, 1), 1, 0.65)

    local popup = new("Frame", {
        BackgroundColor3 = Library.Theme.Main,
        BorderSizePixel = 0,
        Position = UDim2.new(1, -190, 1, 4),
        Size = UDim2.new(0, 180, 0, 132),
        Visible = false,
        ZIndex = 120,
        Parent = frame,
    })
    addCorner(popup, 7)
    addStroke(popup, Library.Theme.Stroke, 1, 0)

    local channels = {}
    for index, channel in ipairs({"R", "G", "B"}) do
        channels[channel] = new("TextBox", {
            BackgroundColor3 = Library.Theme.Second,
            BorderSizePixel = 0,
            Position = UDim2.new(0, 8, 0, 8 + (index - 1) * 37),
            Size = UDim2.new(1, -16, 0, 30),
            PlaceholderText = channel .. " (0-255)",
            TextColor3 = Library.Theme.Text,
            Font = Enum.Font.Gotham,
            TextSize = 12,
            ClearTextOnFocus = false,
            ZIndex = 121,
            Parent = popup,
        })
        addCorner(channels[channel], 5)
    end

    local api = {
        Value = value,
        Type = "Colorpicker",
    }

    local function updateInputs(color)
        channels.R.Text = tostring(math.floor(color.R * 255 + 0.5))
        channels.G.Text = tostring(math.floor(color.G * 255 + 0.5))
        channels.B.Text = tostring(math.floor(color.B * 255 + 0.5))
    end

    local function apply()
        local r = math.clamp(tonumber(channels.R.Text) or 0, 0, 255)
        local g = math.clamp(tonumber(channels.G.Text) or 0, 0, 255)
        local b = math.clamp(tonumber(channels.B.Text) or 0, 0, 255)

        api:Set(Color3.fromRGB(r, g, b))
    end

    function api:Set(color)
        if typeof(color) ~= "Color3" then
            return
        end

        api.Value = color
        swatch.BackgroundColor3 = color
        updateInputs(color)
        safeCallback(config.Callback, color)
    end

    connect(swatch.Activated, function()
        popup.Visible = not popup.Visible
    end)

    for _, input in pairs(channels) do
        connect(input.FocusLost, apply)
    end

    if config.Flag then
        Library.Flags[config.Flag] = api
    end

    api:Set(value)
    return api
end

--========================================================--
-- Window
--========================================================--

function Library:MakeWindow(config)
    config = config or {}

    local old = CoreGui:FindFirstChild("1bzableLib")
    if old then
        pcall(function()
            old:Destroy()
        end)
    end

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
        BackgroundTransparency = 0.06,
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
        BackgroundTransparency = 0.08,
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
        BackgroundTransparency = 0.15,
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
        Tabs = {},
        Dropdowns = {},
        PopupHost = nil,
        Minimized = false,
        Destroyed = false,
    }, WindowMethods)

    table.insert(self.Windows, window)

    makePopupHost(window)

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

function Library:Init()
    applyBlur()
end

function Library:Destroy()
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
