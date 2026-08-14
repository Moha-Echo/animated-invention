--========================================================--
-- 1bzableLib / source.lua
-- Orion-style UI API, self-contained, client-side UI only.
--
-- Compatible API:
--   MakeWindow / MakeTab
--   AddSection / AddParagraph / AddLabel
--   AddButton / AddToggle / AddSlider
--   AddDropdown / AddTextbox / AddColorpicker
--   MakeNotification / Init / ToggleMinimize / Restore
--========================================================--

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer

local Library = {
    Windows = {},
    Flags = {},
    Connections = {},
    ThemeObjects = {},
    Themes = {
        Default = {
            Main = Color3.fromRGB(22, 22, 25),
            Second = Color3.fromRGB(30, 30, 35),
            Stroke = Color3.fromRGB(65, 65, 75),
            Divider = Color3.fromRGB(55, 55, 65),
            Text = Color3.fromRGB(240, 240, 245),
            TextDark = Color3.fromRGB(150, 150, 160),
            Accent = Color3.fromRGB(80, 135, 255),
            AccentDark = Color3.fromRGB(50, 85, 180),
        },
    },
    SelectedTheme = "Default",
}

local WindowMethods = {}
WindowMethods.__index = WindowMethods

local TabMethods = {}
TabMethods.__index = TabMethods

local function connect(signal, callback)
    local connection = signal:Connect(callback)
    table.insert(Library.Connections, connection)
    return connection
end

local function create(className, properties)
    local object = Instance.new(className)
    for property, value in pairs(properties or {}) do
        pcall(function()
            object[property] = value
        end)
    end
    return object
end

local function addCorner(parent, radius)
    return create("UICorner", {
        CornerRadius = UDim.new(0, radius or 6),
        Parent = parent,
    })
end

local function addStroke(parent, color, thickness, transparency)
    return create("UIStroke", {
        Color = color or Library.Themes.Default.Stroke,
        Thickness = thickness or 1,
        Transparency = transparency or 0,
        Parent = parent,
    })
end

local function findOption(options, value)
    for index, option in ipairs(options or {}) do
        if option == value then
            return index
        end
    end
    return nil
end

local function resolveDefault(options, default)
    if type(options) ~= "table" or #options == 0 then
        return default
    end
    if findOption(options, default) then
        return default
    end
    return options[1]
end

local function makeScroll(parent)
    local scroll = create("ScrollingFrame", {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 1, 0),
        CanvasSize = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollBarThickness = 4,
        ScrollBarImageColor3 = Library.Themes.Default.Divider,
        Parent = parent,
    })

    create("UIListLayout", {
        Padding = UDim.new(0, 7),
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = scroll,
    })

    create("UIPadding", {
        PaddingTop = UDim.new(0, 10),
        PaddingBottom = UDim.new(0, 10),
        PaddingLeft = UDim.new(0, 10),
        PaddingRight = UDim.new(0, 10),
        Parent = scroll,
    })

    return scroll
end

local function refreshTheme()
    local theme = Library.Themes[Library.SelectedTheme]
    for key, objects in pairs(Library.ThemeObjects) do
        local color = theme[key]
        if color then
            for _, item in ipairs(objects) do
                if item.Object and item.Object.Parent then
                    pcall(function()
                        item.Object[item.Property] = color
                    end)
                end
            end
        end
    end
end

local function themeObject(object, property, themeKey)
    Library.ThemeObjects[themeKey] = Library.ThemeObjects[themeKey] or {}
    table.insert(Library.ThemeObjects[themeKey], {
        Object = object,
        Property = property,
    })
    pcall(function()
        object[property] = Library.Themes[Library.SelectedTheme][themeKey]
    end)
    return object
end

function WindowMethods:MakeTab(config)
    config = config or {}

    local tabButton = create("TextButton", {
        AutoButtonColor = false,
        BackgroundColor3 = Library.Themes.Default.Second,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 35),
        Text = config.Name or "Tab",
        TextColor3 = Library.Themes.Default.TextDark,
        Font = Enum.Font.GothamSemibold,
        TextSize = 13,
        Parent = self.TabList,
    })
    addCorner(tabButton, 5)

    local page = create("Frame", {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 1, 0),
        Visible = false,
        Parent = self.ContentHolder,
    })

    local container = makeScroll(page)

    local tab = setmetatable({
        Window = self,
        Button = tabButton,
        Page = page,
        Container = container,
        Elements = {},
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

function WindowMethods:SelectTab(tab)
    for _, current in ipairs(self.Tabs) do
        local selected = current == tab
        current.Page.Visible = selected
        current.Button.BackgroundColor3 =
            selected and Library.Themes.Default.AccentDark
            or Library.Themes.Default.Second
        current.Button.TextColor3 =
            selected and Library.Themes.Default.Text
            or Library.Themes.Default.TextDark
        current.Button.Font =
            selected and Enum.Font.GothamBold
            or Enum.Font.GothamSemibold
    end
    self.ActiveTab = tab
end

function WindowMethods:ToggleMinimize()
    if self.Minimized then
        self:Restore()
        return
    end

    self.Minimized = true
    self.Sidebar.Visible = false
    self.ContentHolder.Visible = false
    TweenService:Create(
        self.Main,
        TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
        {Size = UDim2.new(0, 230, 0, 48)}
    ):Play()
end

function WindowMethods:Minimize()
    if not self.Minimized then
        self:ToggleMinimize()
    end
end

function WindowMethods:Restore()
    self.Minimized = false
    self.Sidebar.Visible = true
    self.ContentHolder.Visible = true
    TweenService:Create(
        self.Main,
        TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
        {Size = UDim2.new(0, 680, 0, 410)}
    ):Play()
end

function WindowMethods:Destroy()
    if self.Destroyed then
        return
    end
    self.Destroyed = true
    pcall(function()
        self.Gui:Destroy()
    end)
end

function TabMethods:_frame(height)
    local frame = create("Frame", {
        BackgroundColor3 = Library.Themes.Default.Second,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, height or 38),
        Parent = self.Container,
    })
    addCorner(frame, 6)
    addStroke(frame, Library.Themes.Default.Stroke, 1, 0.2)
    return frame
end

function TabMethods:AddSection(config)
    config = config or {}

    return create("TextLabel", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 23),
        Text = config.Name or "Section",
        TextColor3 = Library.Themes.Default.Text,
        Font = Enum.Font.GothamBold,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = self.Container,
    })
end

function TabMethods:AddLabel(text)
    local frame = self:_frame(32)

    local label = create("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 12, 0, 0),
        Size = UDim2.new(1, -24, 1, 0),
        Text = tostring(text or ""),
        TextColor3 = Library.Themes.Default.Text,
        Font = Enum.Font.Gotham,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = frame,
    })

    return {
        Set = function(_, value)
            label.Text = tostring(value or "")
        end,
    }
end

function TabMethods:AddParagraph(title, content)
    local frame = self:_frame(70)

    create("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 12, 0, 8),
        Size = UDim2.new(1, -24, 0, 18),
        Text = tostring(title or ""),
        TextColor3 = Library.Themes.Default.Text,
        Font = Enum.Font.GothamBold,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = frame,
    })

    local body = create("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 12, 0, 29),
        Size = UDim2.new(1, -24, 0, 32),
        Text = tostring(content or ""),
        TextColor3 = Library.Themes.Default.TextDark,
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

    local frame = self:_frame(36)
    local button = create("TextButton", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 1, 0),
        Text = config.Name or "Button",
        TextColor3 = Library.Themes.Default.Text,
        Font = Enum.Font.GothamBold,
        TextSize = 13,
        Parent = frame,
    })

    connect(button.Activated, function()
        if type(config.Callback) == "function" then
            task.spawn(config.Callback)
        end
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
    local frame = self:_frame(38)

    create("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 12, 0, 0),
        Size = UDim2.new(1, -60, 1, 0),
        Text = config.Name or "Toggle",
        TextColor3 = Library.Themes.Default.Text,
        Font = Enum.Font.GothamBold,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = frame,
    })

    local box = create("Frame", {
        BackgroundColor3 =
            value and (config.Color or Library.Themes.Default.Accent)
            or Library.Themes.Default.Divider,
        BorderSizePixel = 0,
        Size = UDim2.new(0, 25, 0, 25),
        Position = UDim2.new(1, -37, 0.5, 0),
        AnchorPoint = Vector2.new(0.5, 0.5),
        Parent = frame,
    })
    addCorner(box, 6)

    local check = create("TextLabel", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 1, 0),
        Text = "✓",
        TextColor3 = Color3.new(1, 1, 1),
        Font = Enum.Font.GothamBold,
        TextSize = 15,
        Visible = value,
        Parent = box,
    })

    local click = create("TextButton", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 1, 0),
        Text = "",
        Parent = frame,
    })

    local api = {
        Value = value,
        Type = "Toggle",
        Save = config.Save == true,
    }

    function api:Set(newValue)
        value = newValue == true
        api.Value = value
        box.BackgroundColor3 =
            value and (config.Color or Library.Themes.Default.Accent)
            or Library.Themes.Default.Divider
        check.Visible = value

        if type(config.Callback) == "function" then
            task.spawn(config.Callback, value)
        end
    end

    connect(click.Activated, function()
        api:Set(not value)
    end)

    if config.Flag then
        Library.Flags[config.Flag] = api
    end

    api:Set(value)
    return api
end

function TabMethods:AddSlider(config)
    config = config or {}

    local min = tonumber(config.Min) or 0
    local max = tonumber(config.Max) or 100
    local increment = tonumber(config.Increment) or 1
    local value = tonumber(config.Default) or min

    if max < min then
        min, max = max, min
    end

    local frame = self:_frame(66)

    create("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 12, 0, 8),
        Size = UDim2.new(0.7, 0, 0, 18),
        Text = config.Name or "Slider",
        TextColor3 = Library.Themes.Default.Text,
        Font = Enum.Font.GothamBold,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = frame,
    })

    local valueLabel = create("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.new(0.7, 0, 0, 8),
        Size = UDim2.new(0.3, -12, 0, 18),
        TextColor3 = Library.Themes.Default.TextDark,
        Font = Enum.Font.Gotham,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Right,
        Parent = frame,
    })

    local bar = create("Frame", {
        BackgroundColor3 = Library.Themes.Default.Divider,
        BorderSizePixel = 0,
        Position = UDim2.new(0, 12, 0, 36),
        Size = UDim2.new(1, -24, 0, 10),
        Parent = frame,
    })
    addCorner(bar, 5)

    local fill = create("Frame", {
        BackgroundColor3 = config.Color or Library.Themes.Default.Accent,
        BorderSizePixel = 0,
        Size = UDim2.new(0, 0, 1, 0),
        Parent = bar,
    })
    addCorner(fill, 5)

    local drag = create("TextButton", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 1, 0),
        Text = "",
        Parent = bar,
    })

    local api = {
        Value = value,
        Type = "Slider",
        Save = config.Save == true,
    }

    local dragging = false

    local function snap(newValue)
        if increment <= 0 then
            return math.clamp(newValue, min, max)
        end

        local steps = math.floor(((newValue - min) / increment) + 0.5)
        return math.clamp(min + steps * increment, min, max)
    end

    local function setFromAlpha(alpha)
        alpha = math.clamp(alpha, 0, 1)

        local newValue
        if max == min then
            newValue = min
        else
            newValue = snap(min + (max - min) * alpha)
        end

        value = newValue
        api.Value = newValue

        local ratio = max == min and 0 or ((newValue - min) / (max - min))
        fill.Size = UDim2.new(ratio, 0, 1, 0)

        valueLabel.Text =
            tostring(newValue)
            .. tostring(config.ValueName or "")

        if type(config.Callback) == "function" then
            task.spawn(config.Callback, newValue)
        end
    end

    function api:Set(newValue)
        local numeric = tonumber(newValue) or min
        local ratio

        if max == min then
            ratio = 0
        else
            ratio =
                (math.clamp(numeric, min, max) - min)
                / (max - min)
        end

        setFromAlpha(ratio)
    end

    connect(drag.InputBegan, function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
            return
        end

        dragging = true
        setFromAlpha(
            (input.Position.X - bar.AbsolutePosition.X)
            / math.max(bar.AbsoluteSize.X, 1)
        )
    end)

    connect(UserInputService.InputChanged, function(input)
        if not dragging then
            return
        end

        if input.UserInputType == Enum.UserInputType.MouseMovement then
            setFromAlpha(
                (input.Position.X - bar.AbsolutePosition.X)
                / math.max(bar.AbsoluteSize.X, 1)
            )
        end
    end)

    connect(UserInputService.InputEnded, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = false
        end
    end)

    if config.Flag then
        Library.Flags[config.Flag] = api
    end

    api:Set(math.clamp(value, min, max))
    return api
end

function TabMethods:AddDropdown(config)
    config = config or {}

    local options = type(config.Options) == "table" and config.Options or {}
    local value = resolveDefault(options, config.Default)

    local frame = self:_frame(42)

    create("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 12, 0, 0),
        Size = UDim2.new(0.44, 0, 1, 0),
        Text = config.Name or "Dropdown",
        TextColor3 = Library.Themes.Default.Text,
        Font = Enum.Font.GothamBold,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = frame,
    })

    local button = create("TextButton", {
        BackgroundColor3 = Library.Themes.Default.Main,
        BorderSizePixel = 0,
        Position = UDim2.new(0.44, 0, 0.5, 0),
        AnchorPoint = Vector2.new(0, 0.5),
        Size = UDim2.new(0.56, -12, 0, 30),
        Text = tostring(value or ""),
        TextColor3 = Library.Themes.Default.Text,
        Font = Enum.Font.Gotham,
        TextSize = 12,
        Parent = frame,
    })
    addCorner(button, 5)
    addStroke(button, Library.Themes.Default.Stroke, 1, 0.25)

    local popup = create("Frame", {
        BackgroundColor3 = Library.Themes.Default.Main,
        BorderSizePixel = 0,
        Position = UDim2.new(0, 0, 1, 5),
        Size = UDim2.new(1, 0, 0, 0),
        Visible = false,
        ZIndex = 50,
        Parent = button,
    })
    addCorner(popup, 5)
    addStroke(popup, Library.Themes.Default.Stroke, 1, 0)

    local list = create("ScrollingFrame", {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 1, 0),
        ScrollBarThickness = 3,
        ScrollBarImageColor3 = Library.Themes.Default.Divider,
        ZIndex = 51,
        Parent = popup,
    })

    create("UIListLayout", {
        Padding = UDim.new(0, 2),
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = list,
    })

    local api = {
        Value = value,
        Options = options,
        Type = "Dropdown",
        Save = config.Save == true,
    }

    local function rebuild()
        for _, child in ipairs(list:GetChildren()) do
            if child:IsA("GuiButton") then
                child:Destroy()
            end
        end

        for _, option in ipairs(api.Options) do
            local optionButton = create("TextButton", {
                BackgroundTransparency = 1,
                Size = UDim2.new(1, -6, 0, 28),
                Text = tostring(option),
                TextColor3 = Library.Themes.Default.Text,
                Font = Enum.Font.Gotham,
                TextSize = 12,
                ZIndex = 52,
                Parent = list,
            })

            connect(optionButton.Activated, function()
                api:Set(option)
                popup.Visible = false
            end)
        end

        local visibleCount = math.min(#api.Options, 5)
        popup.Size =
            UDim2.new(
                1,
                0,
                0,
                math.max(28, visibleCount * 30 + 4)
            )
    end

    function api:Set(newValue)
        local resolved = resolveDefault(api.Options, newValue)
        api.Value = resolved
        button.Text = tostring(resolved or "")

        if type(config.Callback) == "function" then
            task.spawn(config.Callback, resolved)
        end
    end

    function api:Refresh(newOptions, keepValue)
        api.Options =
            type(newOptions) == "table"
            and newOptions
            or {}

        if not keepValue
            or not findOption(api.Options, api.Value)
        then
            api.Value = resolveDefault(api.Options, nil)
        end

        button.Text = tostring(api.Value or "")
        rebuild()
    end

    connect(button.Activated, function()
        popup.Visible = not popup.Visible
    end)

    rebuild()
    api:Set(value)

    if config.Flag then
        Library.Flags[config.Flag] = api
    end

    return api
end

function TabMethods:AddTextbox(config)
    config = config or {}

    local frame = self:_frame(42)

    create("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 12, 0, 0),
        Size = UDim2.new(0.44, 0, 1, 0),
        Text = config.Name or "Textbox",
        TextColor3 = Library.Themes.Default.Text,
        Font = Enum.Font.GothamBold,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = frame,
    })

    local box = create("TextBox", {
        BackgroundColor3 = Library.Themes.Default.Main,
        BorderSizePixel = 0,
        Position = UDim2.new(0.44, 0, 0.5, 0),
        AnchorPoint = Vector2.new(0, 0.5),
        Size = UDim2.new(0.56, -12, 0, 30),
        Text = tostring(config.Default or ""),
        PlaceholderText = tostring(config.PlaceholderText or ""),
        TextColor3 = Library.Themes.Default.Text,
        PlaceholderColor3 = Library.Themes.Default.TextDark,
        Font = Enum.Font.Gotham,
        TextSize = 12,
        ClearTextOnFocus = config.TextDisappear == true,
        Parent = frame,
    })
    addCorner(box, 5)
    addStroke(box, Library.Themes.Default.Stroke, 1, 0.25)

    local api = {
        Value = box.Text,
        Type = "Textbox",
        Save = config.Save == true,
    }

    function api:Set(value)
        box.Text = tostring(value or "")
        api.Value = box.Text
    end

    connect(box.FocusLost, function()
        api.Value = box.Text

        if type(config.Callback) == "function" then
            task.spawn(config.Callback, box.Text)
        end
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
        or Library.Themes.Default.Accent

    local frame = self:_frame(44)

    create("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 12, 0, 0),
        Size = UDim2.new(0.7, 0, 1, 0),
        Text = config.Name or "Colorpicker",
        TextColor3 = Library.Themes.Default.Text,
        Font = Enum.Font.GothamBold,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = frame,
    })

    local swatch = create("TextButton", {
        BackgroundColor3 = value,
        BorderSizePixel = 0,
        Position = UDim2.new(1, -50, 0.5, 0),
        AnchorPoint = Vector2.new(0, 0.5),
        Size = UDim2.new(0, 38, 0, 26),
        Text = "",
        Parent = frame,
    })
    addCorner(swatch, 5)

    local popup = create("Frame", {
        BackgroundColor3 = Library.Themes.Default.Main,
        BorderSizePixel = 0,
        Position = UDim2.new(1, -180, 1, 3),
        Size = UDim2.new(0, 170, 0, 120),
        Visible = false,
        ZIndex = 60,
        Parent = frame,
    })
    addCorner(popup, 6)
    addStroke(popup, Library.Themes.Default.Stroke, 1, 0)

    local boxes = {}
    for index, channel in ipairs({"R", "G", "B"}) do
        boxes[channel] = create("TextBox", {
            BackgroundColor3 = Library.Themes.Default.Second,
            BorderSizePixel = 0,
            Position = UDim2.new(0, 8, 0, 8 + (index - 1) * 35),
            Size = UDim2.new(1, -16, 0, 28),
            Text = "",
            PlaceholderText = channel .. " (0-255)",
            TextColor3 = Library.Themes.Default.Text,
            Font = Enum.Font.Gotham,
            TextSize = 12,
            ZIndex = 61,
            Parent = popup,
        })
        addCorner(boxes[channel], 4)
    end

    local api = {
        Value = value,
        Type = "Colorpicker",
        Save = config.Save == true,
    }

    local function updateBoxes(color)
        boxes.R.Text = tostring(math.floor(color.R * 255 + 0.5))
        boxes.G.Text = tostring(math.floor(color.G * 255 + 0.5))
        boxes.B.Text = tostring(math.floor(color.B * 255 + 0.5))
    end

    local function apply()
        local r = math.clamp(tonumber(boxes.R.Text) or 0, 0, 255)
        local g = math.clamp(tonumber(boxes.G.Text) or 0, 0, 255)
        local b = math.clamp(tonumber(boxes.B.Text) or 0, 0, 255)

        api.Value = Color3.fromRGB(r, g, b)
        swatch.BackgroundColor3 = api.Value

        if type(config.Callback) == "function" then
            task.spawn(config.Callback, api.Value)
        end
    end

    function api:Set(color)
        if typeof(color) ~= "Color3" then
            return
        end

        api.Value = color
        swatch.BackgroundColor3 = color
        updateBoxes(color)

        if type(config.Callback) == "function" then
            task.spawn(config.Callback, color)
        end
    end

    connect(swatch.Activated, function()
        popup.Visible = not popup.Visible
    end)

    for _, box in pairs(boxes) do
        connect(box.FocusLost, apply)
    end

    if config.Flag then
        Library.Flags[config.Flag] = api
    end

    api:Set(value)
    return api
end

function Library:MakeWindow(config)
    config = config or {}

    local old = CoreGui:FindFirstChild("1bzableLib")
    if old then
        old:Destroy()
    end

    local gui = create("ScreenGui", {
        Name = "1bzableLib",
        ResetOnSpawn = false,
        IgnoreGuiInset = true,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    })

    local parent
    pcall(function()
        if gethui then
            parent = gethui()
        end
    end)

    gui.Parent = parent or CoreGui

    local main = create("Frame", {
        BackgroundColor3 = Library.Themes.Default.Main,
        BorderSizePixel = 0,
        Position = UDim2.new(0.5, -340, 0.5, -205),
        Size = UDim2.new(0, 680, 0, 410),
        Parent = gui,
    })
    addCorner(main, 10)
    addStroke(main, Library.Themes.Default.Stroke, 1, 0)

    local top = create("Frame", {
        BackgroundColor3 = Library.Themes.Default.Second,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 48),
        Parent = main,
    })
    addCorner(top, 10)

    create("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 16, 0, 0),
        Size = UDim2.new(1, -120, 1, 0),
        Text = config.Name or "1bzableLib",
        TextColor3 = Library.Themes.Default.Text,
        Font = Enum.Font.GothamBlack,
        TextSize = 17,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = top,
    })

    local minimize = create("TextButton", {
        BackgroundColor3 = Library.Themes.Default.Main,
        BorderSizePixel = 0,
        Position = UDim2.new(1, -74, 0, 9),
        Size = UDim2.new(0, 28, 0, 28),
        Text = "−",
        TextColor3 = Library.Themes.Default.Text,
        Font = Enum.Font.GothamBold,
        TextSize = 18,
        Parent = top,
    })
    addCorner(minimize, 6)

    local close = create("TextButton", {
        BackgroundColor3 = Library.Themes.Default.Main,
        BorderSizePixel = 0,
        Position = UDim2.new(1, -40, 0, 9),
        Size = UDim2.new(0, 28, 0, 28),
        Text = "×",
        TextColor3 = Library.Themes.Default.Text,
        Font = Enum.Font.GothamBold,
        TextSize = 18,
        Parent = top,
    })
    addCorner(close, 6)

    local sidebar = create("Frame", {
        BackgroundColor3 = Library.Themes.Default.Second,
        BorderSizePixel = 0,
        Position = UDim2.new(0, 0, 0, 48),
        Size = UDim2.new(0, 150, 1, -48),
        Parent = main,
    })

    local tabList = makeScroll(sidebar)
    tabList.Size = UDim2.new(1, 0, 1, -10)
    tabList.Position = UDim2.new(0, 0, 0, 5)

    local contentHolder = create("Frame", {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Position = UDim2.new(0, 150, 0, 48),
        Size = UDim2.new(1, -150, 1, -48),
        Parent = main,
    })

    local window = setmetatable({
        Gui = gui,
        Main = main,
        Sidebar = sidebar,
        TabList = tabList,
        ContentHolder = contentHolder,
        Tabs = {},
        Minimized = false,
        Destroyed = false,
    }, WindowMethods)

    table.insert(Library.Windows, window)

    -- Dragging
    do
        local dragging = false
        local dragStart
        local startPosition

        connect(top.InputBegan, function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                dragging = true
                dragStart = input.Position
                startPosition = main.Position
            end
        end)

        connect(UserInputService.InputChanged, function(input)
            if not dragging or input.UserInputType ~= Enum.UserInputType.MouseMovement then
                return
            end

            local delta = input.Position - dragStart
            main.Position = UDim2.new(
                startPosition.X.Scale,
                startPosition.X.Offset + delta.X,
                startPosition.Y.Scale,
                startPosition.Y.Offset + delta.Y
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

    return window
end

function Library:MakeNotification(config)
    config = config or {}

    local gui
    for _, window in ipairs(self.Windows) do
        if window.Gui and window.Gui.Parent then
            gui = window.Gui
            break
        end
    end

    if not gui then
        return
    end

    local holder = gui:FindFirstChild("Notifications")
    if not holder then
        holder = create("Frame", {
            Name = "Notifications",
            BackgroundTransparency = 1,
            AnchorPoint = Vector2.new(1, 1),
            Position = UDim2.new(1, -15, 1, -15),
            Size = UDim2.new(0, 320, 0, 400),
            Parent = gui,
        })

        create("UIListLayout", {
            Padding = UDim.new(0, 6),
            VerticalAlignment = Enum.VerticalAlignment.Bottom,
            Parent = holder,
        })
    end

    local frame = create("Frame", {
        BackgroundColor3 = Library.Themes.Default.Second,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        Parent = holder,
    })
    addCorner(frame, 7)
    addStroke(frame, Library.Themes.Default.Stroke, 1, 0.1)

    create("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 12, 0, 7),
        Size = UDim2.new(1, -24, 0, 18),
        Text = config.Name or "Notification",
        TextColor3 = Library.Themes.Default.Text,
        Font = Enum.Font.GothamBold,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = frame,
    })

    create("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 12, 0, 27),
        Size = UDim2.new(1, -24, 0, 35),
        Text = config.Content or "",
        TextWrapped = true,
        TextColor3 = Library.Themes.Default.TextDark,
        Font = Enum.Font.Gotham,
        TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
        Parent = frame,
    })

    task.delay(tonumber(config.Time) or 3, function()
        if frame and frame.Parent then
            frame:Destroy()
        end
    end)
end

function Library:SetTheme(name, theme)
    if theme then
        self.Themes[name] = theme
    end

    if self.Themes[name] then
        self.SelectedTheme = name
        refreshTheme()
    end
end

function Library:Init()
    refreshTheme()
end

function Library:IsRunning()
    for _, window in ipairs(self.Windows) do
        if window.Gui and window.Gui.Parent then
            return true
        end
    end
    return false
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
end

return Library
