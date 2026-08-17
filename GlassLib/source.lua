local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local TextService = game:GetService("TextService")
local CoreGui = game:GetService("CoreGui")


local oldGlassRuntime = rawget(_G, "_GlassLibRuntime")
if oldGlassRuntime and type(oldGlassRuntime.Destroy) == "function" then
    pcall(function()
        oldGlassRuntime:Destroy()
    end)
end

local GlassLib = {}
GlassLib.__index = GlassLib
GlassLib.Flags = {}
GlassLib.Windows = {}
GlassLib.Connections = {}
_G._GlassLibRuntime = GlassLib
GlassLib.UIProfiles = {
    Default = {
        Background = Color3.fromRGB(13, 15, 20),
        Secondary = Color3.fromRGB(24, 28, 36),
        Accent = Color3.fromRGB(126, 174, 255),
        Border = Color3.fromRGB(225, 238, 255),
        Text = Color3.fromRGB(248, 249, 252),
        TextDim = Color3.fromRGB(164, 172, 186),
        Transparency = 0.16,
    },
    Midnight = {
        Background = Color3.fromRGB(19, 17, 28),
        Secondary = Color3.fromRGB(31, 27, 43),
        Accent = Color3.fromRGB(154, 124, 255),
        Border = Color3.fromRGB(236, 228, 255),
        Text = Color3.fromRGB(248, 246, 255),
        TextDim = Color3.fromRGB(175, 166, 196),
        Transparency = 0.14,
    },
    Ocean = {
        Background = Color3.fromRGB(10, 22, 32),
        Secondary = Color3.fromRGB(18, 39, 54),
        Accent = Color3.fromRGB(80, 184, 255),
        Border = Color3.fromRGB(218, 242, 255),
        Text = Color3.fromRGB(243, 249, 255),
        TextDim = Color3.fromRGB(164, 187, 204),
        Transparency = 0.15,
    },
    Emerald = {
        Background = Color3.fromRGB(11, 24, 20),
        Secondary = Color3.fromRGB(19, 40, 31),
        Accent = Color3.fromRGB(89, 225, 156),
        Border = Color3.fromRGB(224, 255, 240),
        Text = Color3.fromRGB(244, 255, 250),
        TextDim = Color3.fromRGB(161, 193, 178),
        Transparency = 0.15,
    },
    Rose = {
        Background = Color3.fromRGB(27, 15, 22),
        Secondary = Color3.fromRGB(45, 24, 35),
        Accent = Color3.fromRGB(255, 116, 161),
        Border = Color3.fromRGB(255, 233, 242),
        Text = Color3.fromRGB(255, 247, 250),
        TextDim = Color3.fromRGB(197, 166, 181),
        Transparency = 0.15,
    },
}

GlassLib.Theme = {
    Background = GlassLib.UIProfiles.Default.Background,
    Secondary = GlassLib.UIProfiles.Default.Secondary,
    Accent = GlassLib.UIProfiles.Default.Accent,
    Border = GlassLib.UIProfiles.Default.Border,
    Text = GlassLib.UIProfiles.Default.Text,
    TextDim = GlassLib.UIProfiles.Default.TextDim,
    Transparency = GlassLib.UIProfiles.Default.Transparency,
}

GlassLib.Settings = {
    AnimationTime = 0.28,
    BackgroundTransparency = GlassLib.Theme.Transparency,
    BlurEnabled = false,
    BlurSize = 0,
    ProfileMode = "Default",
    MinimizeMode = "Default",
    LiquidHeight = 34,
}

-- Configuration miroir conservée pour les anciens composants.
local THEME = {
    Background = GlassLib.Theme.Background,
    BackgroundTrans = GlassLib.Theme.Transparency,
    GlassBorder = GlassLib.Theme.Border,
    BorderTrans = 0.88,
    Accent = GlassLib.Theme.Accent,
    Text = GlassLib.Theme.Text,
    TextDim = GlassLib.Theme.TextDim,
    Font = Enum.Font.GothamMedium,
}

-- Helpers d'animation (Smooth, Élastique, Fade)
local function tween(object, info, properties)
    local t = TweenService:Create(object, info, properties)
    t:Play()
    return t
end

local function safeDestroy(obj)
    if obj then
        pcall(function()
            obj:Destroy()
        end)
    end
end

local function safeConnect(signal, callback, bucket)
    local connection = signal:Connect(callback)
    if bucket then
        table.insert(bucket, connection)
    else
        table.insert(GlassLib.Connections, connection)
    end
    return connection
end

local function getGuiParent()
    local hidden
    pcall(function()
        if type(gethui) == "function" then
            hidden = gethui()
        end
    end)

    if hidden and hidden.Parent ~= nil then
        return hidden
    end

    local ok, core = pcall(function()
        return CoreGui
    end)

    if ok and core then
        return core
    end

    return PlayerGui
end

local function getGuiParents()
    local parents = {}

    local function add(parent)
        if parent and not table.find(parents, parent) then
            table.insert(parents, parent)
        end
    end

    pcall(function()
        if type(gethui) == "function" then
            add(gethui())
        end
    end)

    add(CoreGui)
    add(PlayerGui)

    return parents
end

local function cleanupExistingGlassGui()
    for _, parent in ipairs(getGuiParents()) do
        for _, name in ipairs({
            "GlassLib_UI",
            "GlassLib_Notifs",
            "GlassLibBlur",
        }) do
            local old = parent:FindFirstChild(name)
            if old then
                safeDestroy(old)
            end
        end
    end
end

local function isColorEqual(a, b)
    return typeof(a) == "Color3"
        and typeof(b) == "Color3"
        and a == b
end

local function setBlur(enabled, size)
    local existing = Lighting:FindFirstChild("GlassLibBlur")

    if not enabled then
        if existing then
            existing.Enabled = false
        end
        return
    end

    if not existing then
        existing = Instance.new("BlurEffect")
        existing.Name = "GlassLibBlur"
        existing.Parent = Lighting
    end

    existing.Size = math.clamp(tonumber(size) or 0, 0, 24)
    existing.Enabled = existing.Size > 0
end

local function themeWalk(root, oldTheme, newTheme)
    if not root then
        return
    end

    local function remapObject(obj)
        if obj:IsA("GuiObject") then
            if isColorEqual(obj.BackgroundColor3, oldTheme.Background) then
                obj.BackgroundColor3 = newTheme.Background
            elseif isColorEqual(obj.BackgroundColor3, oldTheme.Secondary) then
                obj.BackgroundColor3 = newTheme.Secondary
            elseif isColorEqual(obj.BackgroundColor3, oldTheme.Accent) then
                obj.BackgroundColor3 = newTheme.Accent
            end
        end

        if obj:IsA("TextLabel")
            or obj:IsA("TextButton")
            or obj:IsA("TextBox")
        then
            if isColorEqual(obj.TextColor3, oldTheme.Text) then
                obj.TextColor3 = newTheme.Text
            elseif isColorEqual(obj.TextColor3, oldTheme.TextDim) then
                obj.TextColor3 = newTheme.TextDim
            elseif isColorEqual(obj.TextColor3, oldTheme.Accent) then
                obj.TextColor3 = newTheme.Accent
            end
        end

        if obj:IsA("UIStroke")
            and isColorEqual(obj.Color, oldTheme.Border)
        then
            obj.Color = newTheme.Border
        end
    end

    remapObject(root)

    for _, obj in ipairs(root:GetDescendants()) do
        remapObject(obj)
    end
end

local function updateThemeRefs(window)
    if not window or not window.MainFrame then
        return
    end

    local oldTheme = window._AppliedTheme or GlassLib.Theme
    themeWalk(window.MainFrame, oldTheme, GlassLib.Theme)

    window.MainFrame.BackgroundColor3 = GlassLib.Theme.Background
    window.MainFrame.BackgroundTransparency = GlassLib.Theme.Transparency

    window.TabBar.BackgroundColor3 = GlassLib.Theme.Secondary
    window.TopBar.BackgroundColor3 = GlassLib.Theme.Background

    if window.LiquidIndicator then
        window.LiquidIndicator.BackgroundColor3 = GlassLib.Theme.Accent
        local stroke = window.LiquidIndicator:FindFirstChildOfClass("UIStroke")
        if stroke then
            stroke.Color = GlassLib.Theme.Border
        end
    end

    window._AppliedTheme = {
        Background = GlassLib.Theme.Background,
        Secondary = GlassLib.Theme.Secondary,
        Accent = GlassLib.Theme.Accent,
        Border = GlassLib.Theme.Border,
        Text = GlassLib.Theme.Text,
        TextDim = GlassLib.Theme.TextDim,
    }
end

local function getTopLeftFromAbsolute(guiObject)
    if not guiObject then
        return Vector2.zero
    end
    return guiObject.AbsolutePosition
end

local function animate(obj, duration, properties, direction)
    if not obj or not obj.Parent then
        return nil
    end

    local info = TweenInfo.new(
        duration or GlassLib.Settings.AnimationTime,
        Enum.EasingStyle.Quint,
        direction or Enum.EasingDirection.InOut
    )

    local ok, result = pcall(function()
        local tw = TweenService:Create(obj, info, properties)
        tw:Play()
        return tw
    end)

    return ok and result or nil
end

-- Création de la Fenêtre Principale

local function createBaseElement(parent, sizeY)
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(1, -6, 0, sizeY)
    frame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    frame.BackgroundTransparency = 0.94
    frame.Parent = parent

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = frame

    local stroke = Instance.new("UIStroke")
    stroke.Color = THEME.GlassBorder
    stroke.Transparency = 0.85
    stroke.Thickness = 1
    stroke.Parent = frame

    return frame
end

-- Implémentation des composants requis

-- =============================================================================
-- GLASSLIB INTEGRATION (SUPPORT MÉTHODES AVANCÉES ET CORRECTIF DES ERREURS DE TEXTLABEL)
-- =============================================================================

function GlassLib:AddSection(tab, config)
    config = config or {}

    local frame = Instance.new("Frame")
    frame.BackgroundTransparency = 1
    frame.BorderSizePixel = 0
    frame.Size = UDim2.new(1, 0, 0, 27)
    frame.Parent = tab.Page

    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = 1
    label.Position = UDim2.new(0, 3, 0, 2)
    label.Size = UDim2.new(1, -6, 1, -4)
    label.Text = config.Name or "Section"
    label.TextColor3 = THEME.Text
    label.Font = Enum.Font.GothamBold
    label.TextSize = 13
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = frame

    -- Retourne l'objet onglet pour permettre le chaînage direct sans erreur
    return tab
end

function GlassLib:AddLabel(tab, text)
    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, 0, 0, 20)
    label.Text = text or "Label"
    label.Font = THEME.Font
    label.TextSize = 14
    label.TextColor3 = THEME.Text
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.BackgroundTransparency = 1
    label.Parent = tab.Page

    -- Système d'API moderne retourné sans casser l'arborescence UI
    return {
        Set = function(_, value)
            label.Text = tostring(value or "")
        end,
        Destroy = function()
            label:Destroy()
        end,
        Instance = label
    }
end

function GlassLib:AddParagraph(tab, title, content)
    local base = createBaseElement(tab.Page, 55)
    
    local titleL = Instance.new("TextLabel")
    titleL.Size = UDim2.new(1, -20, 0, 25)
    titleL.Position = UDim2.new(0, 10, 0, 4)
    titleL.Text = title or "Title"
    titleL.Font = THEME.Font
    titleL.TextSize = 14
    titleL.TextColor3 = THEME.Text
    titleL.TextXAlignment = Enum.TextXAlignment.Left
    titleL.BackgroundTransparency = 1
    titleL.Parent = base

    local contentL = Instance.new("TextLabel")
    contentL.Size = UDim2.new(1, -20, 0, 20)
    contentL.Position = UDim2.new(0, 10, 0, 26)
    contentL.Text = content or "Content body goes here..."
    contentL.Font = THEME.Font
    contentL.TextSize = 12
    contentL.TextColor3 = THEME.TextDim
    contentL.TextXAlignment = Enum.TextXAlignment.Left
    contentL.BackgroundTransparency = 1
    contentL.Parent = base

    return {
        Set = function(_, value)
            contentL.Text = tostring(value or "")
        end,
        Instance = base
    }
end

function GlassLib:AddButton(tab, config)
    config = config or {}
    local base = createBaseElement(tab.Page, 35)
    
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, 0, 1, 0)
    btn.BackgroundTransparency = 1
    btn.Text = config.Name or "Button"
    btn.Font = THEME.Font
    btn.TextColor3 = THEME.Text
    btn.TextSize = 14
    btn.Parent = base

    btn.MouseEnter:Connect(function()
        tween(btn, TweenInfo.new(0.10), {TextColor3 = THEME.Accent})
    end)

    btn.MouseLeave:Connect(function()
        tween(btn, TweenInfo.new(0.10), {TextColor3 = THEME.Text})
    end)

    btn.MouseButton1Click:Connect(function()
        base.Size = UDim2.new(1, -12, 0, 33)
        tween(base, TweenInfo.new(0.2, Enum.EasingStyle.Elastic), {Size = UDim2.new(1, -6, 0, 35)})
        if config.Callback then config.Callback() end
    end)

    return {
        Set = function(_, value)
            btn.Text = tostring(value or "")
        end,
        Instance = base
    }
end

-- =============================================================================
-- GLASSLIB EXTENSION : COMPOSANTS INTERACTIFS AVANCÉS (TOGGLE & SLIDER AVEC FLAGS)
-- =============================================================================

function GlassLib:AddToggle(tab, config)
    config = config or {}
    local base = createBaseElement(tab.Page, 35)
    local value = config.Default == true

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -70, 1, 0)
    label.Position = UDim2.new(0, 10, 0, 0)
    label.Text = config.Name or "Toggle"
    label.Font = THEME.Font
    label.TextColor3 = THEME.Text
    label.TextSize = 13
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.BackgroundTransparency = 1
    label.Parent = base

    local switch = Instance.new("Frame")
    switch.Size = UDim2.new(0, 38, 0, 22)
    switch.Position = UDim2.new(1, -50, 0.5, -11)
    switch.BackgroundColor3 = value and (config.Color or THEME.Accent) or Color3.fromRGB(80, 80, 80)
    switch.BorderSizePixel = 0
    switch.Parent = base
    Instance.new("UICorner", switch).CornerRadius = UDim.new(0, 11)

    local knob = Instance.new("Frame")
    knob.Size = UDim2.new(0, 18, 0, 18)
    knob.Position = value and UDim2.new(1, -20, 0.5, -9) or UDim2.new(0, 2, 0.5, -9)
    knob.BackgroundColor3 = Color3.fromRGB(246, 246, 248)
    knob.BorderSizePixel = 0
    knob.Parent = switch
    Instance.new("UICorner", knob).CornerRadius = UDim.new(0, 9)

    local click = Instance.new("TextButton")
    click.Size = UDim2.new(1, 0, 1, 0)
    click.BackgroundTransparency = 1
    click.Text = ""
    click.Parent = base

    local api = {
        Value = value,
        Type = "Toggle",
        Instance = base
    }

    local function render(instant)
        local targetColor = value and (config.Color or THEME.Accent) or Color3.fromRGB(80, 80, 80)
        local targetPosition = value and UDim2.new(1, -20, 0.5, -9) or UDim2.new(0, 2, 0.5, -9)

        if instant then
            switch.BackgroundColor3 = targetColor
            knob.Position = targetPosition
        else
            tween(switch, TweenInfo.new(0.12), {BackgroundColor3 = targetColor})
            tween(knob, TweenInfo.new(0.12, Enum.EasingStyle.Quad), {Position = targetPosition})
        end
    end

    function api:Set(newValue)
        value = newValue == true
        api.Value = value
        render(false)
        if config.Callback then config.Callback(value) end
    end

    click.MouseButton1Click:Connect(function()
        api:Set(not value)
    end)

    if config.Flag and GlassLib.Flags then
        GlassLib.Flags[config.Flag] = api
    end

    render(true)
    if config.Callback then config.Callback(value) end

    return api
end

function GlassLib:AddSlider(tab, config)
    config = config or {}
    local base = createBaseElement(tab.Page, 72)

    local minValue = tonumber(config.Min) or 0
    local maxValue = tonumber(config.Max) or 100
    local increment = tonumber(config.Increment) or 1

    if minValue > maxValue then
        minValue, maxValue = maxValue, minValue
    end

    -- Fonction interne d'arrondi mathématique (snap) conforme à votre code source
    local function snapValue(val, min, max, inc)
        local snapped = math.floor((val - min) / inc + 0.5) * inc + min
        return math.clamp(snapped, min, max)
    end

    local value = snapValue(tonumber(config.Default) or minValue, minValue, maxValue, increment)

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(0.55, 0, 0, 20)
    label.Position = UDim2.new(0, 12, 0, 7)
    label.Text = config.Name or "Slider"
    label.Font = THEME.Font
    label.TextColor3 = THEME.Text
    label.TextSize = 13
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.BackgroundTransparency = 1
    label.Parent = base

    local valueBox = Instance.new("TextBox")
    valueBox.Size = UDim2.new(0, 98, 0, 24)
    valueBox.Position = UDim2.new(1, -112, 0, 6)
    valueBox.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    valueBox.BorderSizePixel = 0
    valueBox.TextColor3 = THEME.Text
    valueBox.Font = THEME.Font
    valueBox.TextSize = 11
    valueBox.TextXAlignment = Enum.TextXAlignment.Right
    valueBox.ClearTextOnFocus = false
    valueBox.Parent = base
    Instance.new("UICorner", valueBox).CornerRadius = UDim.new(0, 5)

    local hintLabel = Instance.new("TextLabel")
    hintLabel.Size = UDim2.new(0, 98, 0, 12)
    hintLabel.Position = UDim2.new(1, -112, 0, 29)
    hintLabel.Text = "Double-clic pour saisir"
    hintLabel.Font = THEME.Font
    hintLabel.TextColor3 = THEME.TextDim
    hintLabel.TextSize = 8
    hintLabel.TextXAlignment = Enum.TextXAlignment.Right
    hintLabel.BackgroundTransparency = 1
    hintLabel.Parent = base

    local bar = Instance.new("Frame")
    bar.Size = UDim2.new(1, -24, 0, 9)
    bar.Position = UDim2.new(0, 12, 0, 48)
    bar.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
    bar.BorderSizePixel = 0
    bar.Parent = base
    Instance.new("UICorner", bar).CornerRadius = UDim.new(0, 5)

    local fill = Instance.new("Frame")
    fill.Size = UDim2.new(0, 0, 1, 0)
    fill.BackgroundColor3 = config.Color or THEME.Accent
    fill.BorderSizePixel = 0
    fill.Parent = bar
    Instance.new("UICorner", fill).CornerRadius = UDim.new(0, 5)

    local knob = Instance.new("Frame")
    knob.Size = UDim2.new(0, 14, 0, 14)
    knob.AnchorPoint = Vector2.new(0.5, 0.5)
    knob.BackgroundColor3 = Color3.fromRGB(245, 245, 248)
    knob.BorderSizePixel = 0
    knob.Parent = bar
    Instance.new("UICorner", knob).CornerRadius = UDim.new(0, 7)

    local hit = Instance.new("TextButton")
    hit.Size = UDim2.new(1, 0, 1, 0)
    hit.BackgroundTransparency = 1
    hit.Text = ""
    hit.Parent = bar

    local api = {
        Value = value,
        Type = "Slider",
        Instance = base
    }

    local dragging = false
    local lastClick = 0

    local function render(instant)
        local alpha = maxValue == minValue and 0 or math.clamp((value - minValue) / (maxValue - minValue), 0, 1)
        local fillTarget = UDim2.new(alpha, 0, 1, 0)
        local knobTarget = UDim2.new(alpha, 0, 0.5, 0)

        if instant then
            fill.Size = fillTarget
            knob.Position = knobTarget
        else
            tween(fill, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Size = fillTarget})
            tween(knob, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Position = knobTarget})
        end

        valueBox.Text = tostring(value)
    end

    local function setValue(newValue, fire)
        value = snapValue(newValue, minValue, maxValue, increment)
        api.Value = value
        render(false)

        if fire and config.Callback then
            config.Callback(value)
        end
    end

    local function setFromMouse(x)
        local alpha = math.clamp((x - bar.AbsolutePosition.X) / math.max(bar.AbsoluteSize.X, 1), 0, 1)
        setValue(minValue + (maxValue - minValue) * alpha, true)
    end

    function api:Set(newValue)
        setValue(tonumber(newValue) or minValue, true)
    end

    hit.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            setFromMouse(input.Position.X)
        end
    end)

    safeConnect(UserInputService.InputChanged, function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            setFromMouse(input.Position.X)
        end
    end)

    safeConnect(UserInputService.InputEnded, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = false
        end
    end)

    valueBox.InputBegan:Connect(function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end

        local now = os.clock()
        if now - lastClick <= 0.30 then
            valueBox:CaptureFocus()
            valueBox.CursorPosition = #valueBox.Text + 1
        end
        lastClick = now
    end)

    valueBox.FocusLost:Connect(function()
        local numeric = tonumber(valueBox.Text)
        if numeric then
            setValue(numeric, true)
        else
            render(true)
        end
    end)

    if config.Flag and GlassLib.Flags then
        GlassLib.Flags[config.Flag] = api
    end

    render(true)
    if config.Callback then config.Callback(value) end

    return api
end


-- =============================================================================
-- GLASSLIB EXTENSION : DROPDOWN & TEXTBOX AVEC LOGIQUE DE POPUP ET AUTO-CLOSE
-- =============================================================================

function GlassLib:AddDropdown(tab, config)
    config = config or {}
    local base = createBaseElement(tab.Page, 35)
    
    local options = type(config.Options) == "table" and config.Options or {}
    local value = config.Default or options[1] or "None"

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -40, 1, 0)
    label.Position = UDim2.new(0, 10, 0, 0)
    label.Text = (config.Name or "Dropdown") .. " : " .. tostring(value)
    label.Font = THEME.Font
    label.TextColor3 = THEME.Text
    label.TextSize = 14
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.BackgroundTransparency = 1
    label.Parent = base

    local arrow = Instance.new("TextLabel")
    arrow.Size = UDim2.new(0, 30, 1, 0)
    arrow.Position = UDim2.new(1, -35, 0, 0)
    arrow.Text = "▼"
    arrow.Font = THEME.Font
    arrow.TextColor3 = THEME.TextDim
    arrow.TextSize = 12
    arrow.BackgroundTransparency = 1
    arrow.Parent = base

    local optContainer = Instance.new("Frame")
    optContainer.Size = UDim2.new(1, 0, 0, 0)
    optContainer.Position = UDim2.new(0, 0, 0, 35)
    optContainer.BackgroundTransparency = 1
    optContainer.ClipsDescendants = true
    optContainer.Parent = base
    Instance.new("UIListLayout", optContainer)

    local api = {
        Value = value,
        Options = options,
        Type = "Dropdown",
        Instance = base
    }

    local open = false

    local function rebuild()
        for _, child in ipairs(optContainer:GetChildren()) do
            if child:IsA("TextButton") then
                child:Destroy()
            end
        end

        for _, option in ipairs(api.Options) do
            local selected = option == api.Value

            local optionButton = Instance.new("TextButton")
            optionButton.Size = UDim2.new(1, 0, 0, 25)
            optionButton.BackgroundColor3 = selected and THEME.Accent or Color3.fromRGB(30, 45, 65)
            optionButton.BackgroundTransparency = selected and 0.4 or 0.2
            optionButton.Text = tostring(option)
            optionButton.Font = selected and Enum.Font.GothamBold or THEME.Font
            optionButton.TextColor3 = THEME.Text
            optionButton.TextSize = 13
            optionButton.Parent = optContainer

            optionButton.MouseEnter:Connect(function()
                optionButton.BackgroundTransparency = 0.1
            end)

            optionButton.MouseLeave:Connect(function()
                optionButton.BackgroundTransparency = option == api.Value and 0.4 or 0.2
            end)

            optionButton.MouseButton1Click:Connect(function()
                api:Set(option)
                
                -- L'option reste ouverte d'après votre logique source
                task.defer(function()
                    if open then
                        local containerSize = (#api.Options * 25)
                        base.Size = UDim2.new(1, -6, 0, 35 + containerSize)
                        optContainer.Size = UDim2.new(1, 0, 0, containerSize)
                    end
                end)
            end)
        end

        if open then
            local containerSize = (#api.Options * 25)
            base.Size = UDim2.new(1, -6, 0, 35 + containerSize)
            optContainer.Size = UDim2.new(1, 0, 0, containerSize)
        end
    end

    function api:Set(newValue)
        api.Value = newValue
        label.Text = (config.Name or "Dropdown") .. " : " .. tostring(api.Value or "")
        rebuild()
        if config.Callback then config.Callback(api.Value) end
    end

    function api:Refresh(newOptions, keepValue)
        api.Options = type(newOptions) == "table" and newOptions or {}
        if not keepValue or not table.find(api.Options, api.Value) then
            api.Value = api.Options[1] or "None"
        end
        label.Text = (config.Name or "Dropdown") .. " : " .. tostring(api.Value or "")
        rebuild()
    end

    local click = Instance.new("TextButton")
    click.Size = UDim2.new(1, 0, 0, 35)
    click.BackgroundTransparency = 1
    click.Text = ""
    click.Parent = base

    click.MouseButton1Click:Connect(function()
        open = not open
        local targetSize = open and (35 + (#api.Options * 25)) or 35
        local containerSize = open and (#api.Options * 25) or 0
        arrow.Text = open and "▲" or "▼"
        
        tween(base, TweenInfo.new(0.25, Enum.EasingStyle.Quart), {Size = UDim2.new(1, -6, 0, targetSize)})
        tween(optContainer, TweenInfo.new(0.25, Enum.EasingStyle.Quart), {Size = UDim2.new(1, 0, 0, containerSize)})
        
        if open then
            rebuild()
        end
    end)

    -- Détection de clic extérieur pour fermer automatiquement le menu déroulant
    safeConnect(UserInputService.InputEnded, function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
        if not open then return end

        task.defer(function()
            if not open then return end

            local mouse = game:GetService("UserInputService"):GetMouseLocation()
            local basePos = base.AbsolutePosition
            local baseSize = base.AbsoluteSize

            local inside = mouse.X >= basePos.X 
                       and mouse.X <= basePos.X + baseSize.X 
                       and mouse.Y >= basePos.Y 
                       and mouse.Y <= basePos.Y + baseSize.Y

            if not inside then
                open = false
                arrow.Text = "▼"
                tween(base, TweenInfo.new(0.2), {Size = UDim2.new(1, -6, 0, 35)})
                tween(optContainer, TweenInfo.new(0.2), {Size = UDim2.new(1, 0, 0, 0)})
            end
        end)
    end)

    rebuild()

    if config.Flag and GlassLib.Flags then
        GlassLib.Flags[config.Flag] = api
    end

    return api
end

function GlassLib:AddTextbox(tab, config)
    config = config or {}
    local base = createBaseElement(tab.Page, 35)

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(0, 150, 1, 0)
    label.Position = UDim2.new(0, 10, 0, 0)
    label.Text = config.Name or "Textbox"
    label.Font = THEME.Font
    label.TextColor3 = THEME.Text
    label.TextSize = 14
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.BackgroundTransparency = 1
    label.Parent = base

    local box = Instance.new("TextBox")
    box.Size = UDim2.new(1, -170, 0, 24)
    box.Position = UDim2.new(0, 160, 0.5, -12)
    box.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    box.BackgroundTransparency = 0.6
    box.Text = tostring(config.Default or "")
    box.PlaceholderText = tostring(config.PlaceholderText or config.Placeholder or "Type...")
    box.Font = THEME.Font
    box.TextColor3 = THEME.Text
    box.PlaceholderColor3 = THEME.TextDim
    box.TextSize = 13
    box.ClearTextOnFocus = config.TextDisappear == true or config.Clear == true
    box.Parent = base
    Instance.new("UICorner", box).CornerRadius = UDim.new(0, 6)

    local api = {
        Value = box.Text,
        Type = "Textbox",
        Instance = base
    }

    function api:Set(value)
        box.Text = tostring(value or "")
        api.Value = box.Text
    end

    box.FocusLost:Connect(function(enterPressed)
        api.Value = box.Text
        if config.Callback then config.Callback(box.Text, enterPressed) end
    end)

    if config.Flag and GlassLib.Flags then
        GlassLib.Flags[config.Flag] = api
    end

    return api
end


-- =============================================================================
-- GLASSLIB EXTENSION : COLORPICKER COMPLET (MODÈLE RENDU HSV AVEC POPUP)
-- =============================================================================

function GlassLib:AddColorpicker(tab, config)
    config = config or {}
    local base = createBaseElement(tab.Page, 35)

    local value = typeof(config.Default) == "Color3" and config.Default or THEME.Accent

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -75, 1, 0)
    label.Position = UDim2.new(0, 10, 0, 0)
    label.Text = config.Name or "Colorpicker"
    label.Font = THEME.Font
    label.TextColor3 = THEME.Text
    label.TextSize = 14
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.BackgroundTransparency = 1
    label.Parent = base

    local swatch = Instance.new("TextButton")
    swatch.AutoButtonColor = false
    swatch.BackgroundColor3 = value
    swatch.Position = UDim2.new(1, -54, 0.5, -14)
    swatch.Size = UDim2.new(0, 40, 0, 28)
    swatch.Text = ""
    swatch.Parent = base
    Instance.new("UICorner", swatch).CornerRadius = UDim.new(0, 6)

    local strokeSwatch = Instance.new("UIStroke")
    strokeSwatch.Color = Color3.new(1, 1, 1)
    strokeSwatch.Transparency = 0.65
    strokeSwatch.Parent = swatch

    ----------------------------------------------------------------
    -- POPUP FLOTTANT (CONSTRUIT À L'INTÉRIEUR DU COMPOSANT)
    ----------------------------------------------------------------
    local popup = Instance.new("Frame")
    popup.Name = "ColorpickerPopup"
    popup.BackgroundColor3 = Color3.fromRGB(35, 35, 45)
    popup.Visible = false
    popup.Size = UDim2.fromOffset(245, 285)
    popup.Position = UDim2.new(0, 0, 0, 35)
    popup.ClipsDescendants = true
    popup.Parent = base
    Instance.new("UICorner", popup).CornerRadius = UDim.new(0, 9)

    local pTitle = Instance.new("TextLabel")
    pTitle.BackgroundTransparency = 1
    pTitle.Position = UDim2.fromOffset(12, 8)
    pTitle.Size = UDim2.new(1, -24, 0, 20)
    pTitle.Text = config.Name or "Choisir une couleur"
    pTitle.TextColor3 = THEME.Text
    pTitle.Font = THEME.Font
    pTitle.TextSize = 13
    pTitle.TextXAlignment = Enum.TextXAlignment.Left
    pTitle.Parent = popup

    ----------------------------------------------------------------
    -- SATURATION / VALEUR (CADRE DU GRADIENT RENDU)
    ----------------------------------------------------------------
    local sv = Instance.new("Frame")
    sv.BackgroundColor3 = Color3.fromHSV(0, 1, 1)
    sv.Position = UDim2.fromOffset(12, 34)
    sv.Size = UDim2.fromOffset(185, 185)
    sv.Parent = popup
    Instance.new("UICorner", sv).CornerRadius = UDim.new(0, 7)

    -- Blanc -> Couleur
    local whiteGradient = Instance.new("UIGradient")
    whiteGradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
        ColorSequenceKeypoint.new(1, Color3.new(1, 1, 1)),
    })
    whiteGradient.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0),
        NumberSequenceKeypoint.new(1, 1),
    })
    whiteGradient.Parent = sv

    -- Noir -> Transparent Overlay
    local blackOverlay = Instance.new("Frame")
    blackOverlay.BackgroundColor3 = Color3.new(0, 0, 0)
    blackOverlay.BackgroundTransparency = 1
    blackOverlay.Size = UDim2.fromScale(1, 1)
    blackOverlay.Parent = sv
    Instance.new("UICorner", blackOverlay).CornerRadius = UDim.new(0, 7)

    local blackGradient = Instance.new("UIGradient")
    blackGradient.Rotation = 90
    blackGradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.new(0, 0, 0)),
        ColorSequenceKeypoint.new(1, Color3.new(0, 0, 0)),
    })
    blackGradient.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0),
        NumberSequenceKeypoint.new(1, 1),
    })
    blackGradient.Parent = blackOverlay

    ----------------------------------------------------------------
    -- CURSEUR SATURATION / VALEUR
    ----------------------------------------------------------------
    local svCursor = Instance.new("Frame")
    svCursor.BackgroundColor3 = Color3.new(1, 1, 1)
    svCursor.Size = UDim2.fromOffset(12, 12)
    svCursor.AnchorPoint = Vector2.new(0.5, 0.5)
    svCursor.Parent = sv
    Instance.new("UICorner", svCursor).CornerRadius = UDim.new(0, 6)
    local strokeSVC = Instance.new("UIStroke")
    strokeSVC.Color = Color3.new(0, 0, 0)
    strokeSVC.Transparency = 0.15
    strokeSVC.Parent = svCursor

    ----------------------------------------------------------------
    -- BARRE HUE (TEINTE)
    ----------------------------------------------------------------
    local hueBar = Instance.new("Frame")
    hueBar.BackgroundColor3 = Color3.new(1, 1, 1)
    hueBar.Position = UDim2.fromOffset(208, 34)
    hueBar.Size = UDim2.fromOffset(22, 185)
    hueBar.Parent = popup
    Instance.new("UICorner", hueBar).CornerRadius = UDim.new(0, 7)

    local hueGradient = Instance.new("UIGradient")
    hueGradient.Rotation = 90
    hueGradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0.00, Color3.fromRGB(255, 0, 0)),
        ColorSequenceKeypoint.new(0.16, Color3.fromRGB(255, 255, 0)),
        ColorSequenceKeypoint.new(0.33, Color3.fromRGB(0, 255, 0)),
        ColorSequenceKeypoint.new(0.50, Color3.fromRGB(0, 255, 255)),
        ColorSequenceKeypoint.new(0.66, Color3.fromRGB(0, 0, 255)),
        ColorSequenceKeypoint.new(0.83, Color3.fromRGB(255, 0, 255)),
        ColorSequenceKeypoint.new(1.00, Color3.fromRGB(255, 0, 0)),
    })
    hueGradient.Parent = hueBar

    local hueCursor = Instance.new("Frame")
    hueCursor.BackgroundColor3 = Color3.new(1, 1, 1)
    hueCursor.Size = UDim2.new(1, 4, 0, 8)
    hueCursor.Position = UDim2.new(-0.5, 0, 0, 0)
    hueCursor.AnchorPoint = Vector2.new(0.5, 0.5)
    hueCursor.Parent = hueBar
    Instance.new("UICorner", hueCursor).CornerRadius = UDim.new(0, 4)
    local strokeHueC = Instance.new("UIStroke")
    strokeHueC.Color = Color3.new(0, 0, 0)
    strokeHueC.Transparency = 0.15
    strokeHueC.Parent = hueCursor

    ----------------------------------------------------------------
    -- COULEUR APERÇU BASSE
    ----------------------------------------------------------------
    local preview = Instance.new("Frame")
    preview.BackgroundColor3 = value
    preview.Position = UDim2.fromOffset(12, 231)
    preview.Size = UDim2.fromOffset(218, 32)
    preview.Parent = popup
    Instance.new("UICorner", preview).CornerRadius = UDim.new(0, 6)

    ----------------------------------------------------------------
    -- ETAT INITIAL HSV & LOGIQUE API
    ----------------------------------------------------------------
    local h, s, v = Color3.toHSV(value)

    local api = {
        Value = value,
        Type = "Colorpicker",
        Instance = base
    }

    local function render()
        local hueColor = Color3.fromHSV(h, 1, 1)
        sv.BackgroundColor3 = hueColor
        preview.BackgroundColor3 = Color3.fromHSV(h, s, v)
        swatch.BackgroundColor3 = Color3.fromHSV(h, s, v)

        svCursor.Position = UDim2.new(s, 0, 1 - v, 0)
        hueCursor.Position = UDim2.new(0.5, 0, h, 0)
    end

    local function emit()
        local color = Color3.fromHSV(h, s, v)
        api.Value = color
        if config.Callback then config.Callback(color) end
    end

    function api:Set(color)
        if typeof(color) ~= "Color3" then return end
        h, s, v = Color3.toHSV(color)
        api.Value = color
        render()
        if config.Callback then config.Callback(color) end
    end

    ----------------------------------------------------------------
    -- INTERACTIONS DE DRAGGING DE SOURIS
    ----------------------------------------------------------------
    local draggingSV = false
    local draggingHue = false

    local function updateSV(mouseX, mouseY)
        local size = sv.AbsoluteSize
        if size.X <= 0 or size.Y <= 0 then return end

        local px = math.clamp((mouseX - sv.AbsolutePosition.X) / size.X, 0, 1)
        local py = math.clamp((mouseY - sv.AbsolutePosition.Y) / size.Y, 0, 1)

        s = px
        v = 1 - py

        render()
        emit()
    end

    local function updateHue(mouseY)
        local size = hueBar.AbsoluteSize
        if size.Y <= 0 then return end

        h = math.clamp((mouseY - hueBar.AbsolutePosition.Y) / size.Y, 0, 1)

        render()
        emit()
    end

    sv.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            draggingSV = true
            updateSV(input.Position.X, input.Position.Y)
        end
    end)

    hueBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            draggingHue = true
            updateHue(input.Position.Y)
        end
    end)

    safeConnect(UserInputService.InputChanged, function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement then
            local mouse = game:GetService("UserInputService"):GetMouseLocation()
            if draggingSV then
                updateSV(mouse.X, mouse.Y - 36) -- Compensation topbar Roblox standard
            elseif draggingHue then
                updateHue(mouse.Y - 36)
            end
        end
    end)

    safeConnect(UserInputService.InputEnded, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            draggingSV = false
            draggingHue = false
        end
    end)

    ----------------------------------------------------------------
    -- GESTION OUVERTURE ET FERMETURE DU MODAL CONTENEUR
    ----------------------------------------------------------------
    local open = false
    swatch.MouseButton1Click:Connect(function()
        open = not open
        popup.Visible = open
        local targetSize = open and 330 or 35
            tween(base, TweenInfo.new(0.25, Enum.EasingStyle.Quart), {Size = UDim2.new(1, -6, 0, targetSize)})
            if open then render() end
        end)
        render()
    
        if config.Flag and GlassLib.Flags then
            GlassLib.Flags[config.Flag] = api
        end
    return api
end


--========================================================--
-- GlassLib V6 : FINAL LIQUID GLASS SHELL
--========================================================--
-- No button modal property is used intentionally. The UI remains
-- interactive without forcing first-person mouse/camera behavior.
local V6 = {
    NormalSize = UDim2.fromOffset(600, 440),
    ShadowSize = UDim2.fromOffset(630, 470),
    NormalTopHeight = 56,

    Minimize = {
        Default = {
            Size = UDim2.fromOffset(390, 108),
            Shadow = UDim2.fromOffset(418, 136),
            TopHeight = 102,
        },
        Compacte = {
            Size = UDim2.fromOffset(300, 68),
            Shadow = UDim2.fromOffset(326, 94),
            TopHeight = 68,
        },
        ["Ultra compacte"] = {
            Size = UDim2.fromOffset(58, 58),
            Shadow = UDim2.fromOffset(74, 74),
            TopHeight = 58,
        },
    },
}

local function applyLegacyTheme()
    THEME.Background = GlassLib.Theme.Background
    THEME.BackgroundTrans = GlassLib.Theme.Transparency
    THEME.GlassBorder = GlassLib.Theme.Border
    THEME.Accent = GlassLib.Theme.Accent
    THEME.Text = GlassLib.Theme.Text
    THEME.TextDim = GlassLib.Theme.TextDim
end

-- ====================================================================
-- 1. LA FONCTION REFRESH CORRIGÉE
-- ====================================================================
local function refreshLiquidIndicator(window, instant)
    if not window or not window.CurrentTab or not window.LiquidIndicator or not window.TabScroll then
        return
    end

    local button = window.CurrentTab.Button
    if not button or not button.Parent then
        return
    end

    -- Position relative par rapport à la barre principale (sans recalculer le CanvasPosition manuellement)
    local targetX = button.AbsolutePosition.X - window.TabBar.AbsolutePosition.X

    local targetPosition = UDim2.fromOffset(targetX, 3)
    local targetSize = UDim2.fromOffset(button.AbsoluteSize.X, GlassLib.Settings.LiquidHeight)

    if instant then
        window.LiquidIndicator.Position = targetPosition
        window.LiquidIndicator.Size = targetSize
    else
        -- Correction de la direction en Enum.EasingDirection.Out pour l'effet fluide "Apple"
        animate(
            window.LiquidIndicator,
            GlassLib.Settings.AnimationTime,
            {
                Position = targetPosition,
                Size = targetSize,
            },
            Enum.EasingDirection.Out -- Ajouté ici pour écraser le InOut trop lourd
        )
    end
end

local function keepTabVisible(window, tab)
    if not window
        or not window.TabScroll
        or not tab
        or not tab.Button
    then
        return
    end

    local scroll = window.TabScroll
    local button = tab.Button

    task.defer(function()
        if not button.Parent then
            return
        end

        local left =
            button.AbsolutePosition.X
            - scroll.AbsolutePosition.X

        local right =
            left + button.AbsoluteSize.X

        local visibleLeft = 0
        local visibleRight = scroll.AbsoluteSize.X

        local target = scroll.CanvasPosition.X

        if left < visibleLeft then
            target = scroll.CanvasPosition.X + left - 8
        elseif right > visibleRight then
            target =
                scroll.CanvasPosition.X
                + (right - visibleRight)
                + 8
        end

        target = math.max(0, target)

        animate(
            scroll,
            GlassLib.Settings.AnimationTime,
            {
                CanvasPosition =
                    Vector2.new(target, 0),
            }
        )
    end)
end

local function updateProfileMode(window)
    if not window or not window.Profile then
        return
    end

    local profile = window.Profile
    local avatar = profile:FindFirstChild("Avatar")
    local display = profile:FindFirstChild("DisplayName")
    local username = profile:FindFirstChild("Username")

    if window.Minimized
        and window.MinimizeMode == "Ultra compacte"
    then
        -- Ultra mini : handled by the mini-square state.
        profile.Visible = false
        return
    end

    profile.Visible =
        not (
            window.Minimized
            and window.MinimizeMode == "Compacte"
        )

    local mode = window.ProfileMode

    if mode == "Default" then
        profile.Size = UDim2.fromOffset(166, 42)

        if avatar then
            avatar.Size = UDim2.fromOffset(32, 32)
            avatar.Position = UDim2.fromOffset(5, 5)
        end

        if display then
            display.Visible = true
            display.Position = UDim2.fromOffset(43, 5)
            display.Size = UDim2.new(1, -48, 0, 16)
        end

        if username then
            username.Visible = true
            username.Position = UDim2.fromOffset(43, 21)
            username.Size = UDim2.new(1, -48, 0, 14)
        end

    elseif mode == "Compacte" then
        profile.Size = UDim2.fromOffset(150, 38)

        if avatar then
            avatar.Size = UDim2.fromOffset(30, 30)
            avatar.Position = UDim2.fromOffset(4, 4)
        end

        if display then
            display.Visible = true
            display.Position = UDim2.fromOffset(40, 6)
            display.Size = UDim2.new(1, -46, 0, 18)
        end

        if username then
            username.Visible = false
        end

    else
        profile.Size = UDim2.fromOffset(46, 46)

        if avatar then
            avatar.Size = UDim2.fromOffset(38, 38)
            avatar.Position = UDim2.fromOffset(4, 4)
        end

        if display then
            display.Visible = false
        end

        if username then
            username.Visible = false
        end
    end

    profile.Position = UDim2.new(0.5, 0, 0, 6)
    profile.AnchorPoint = Vector2.new(0.5, 0)
end


local function uiCorner(parent, radius)
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, radius or 8)
    corner.Parent = parent
    return corner
end

local function uiStroke(parent, color, transparency, thickness)
    local stroke = Instance.new("UIStroke")
    stroke.Color = color or GlassLib.Theme.Border
    stroke.Transparency = transparency == nil and 0.88 or transparency
    stroke.Thickness = thickness or 1
    stroke.Parent = parent
    return stroke
end

local function createProfileCard(window, parent)
    local profile = Instance.new("Frame")
    profile.Name = "Profile"
    profile.AnchorPoint = Vector2.new(0.5, 0)
    profile.Position = UDim2.new(0.5, 0, 0, 6)
    profile.Size = UDim2.fromOffset(166, 42)
    profile.BackgroundColor3 = GlassLib.Theme.Secondary
    profile.BackgroundTransparency = 0.28
    profile.BorderSizePixel = 0
    profile.ZIndex = 11
    profile.Parent = parent

    uiCorner(profile, 12)
    uiStroke(profile, GlassLib.Theme.Border, 0.86, 1)

    local avatar = Instance.new("ImageLabel")
    avatar.Name = "Avatar"
    avatar.BackgroundTransparency = 1
    avatar.Position = UDim2.fromOffset(5, 5)
    avatar.Size = UDim2.fromOffset(32, 32)
    avatar.Image = "rbxthumb://type=AvatarHeadShot&id="
        .. tostring(LocalPlayer.UserId)
        .. "&w=150&h=150"
    avatar.ZIndex = 12
    avatar.Parent = profile
    uiCorner(avatar, 16)

    local display = Instance.new("TextLabel")
    display.Name = "DisplayName"
    display.BackgroundTransparency = 1
    display.Position = UDim2.fromOffset(43, 5)
    display.Size = UDim2.new(1, -48, 0, 16)
    display.Text = LocalPlayer.DisplayName or LocalPlayer.Name
    display.TextColor3 = GlassLib.Theme.Text
    display.Font = Enum.Font.GothamBold
    display.TextSize = 10
    display.TextXAlignment = Enum.TextXAlignment.Left
    display.TextTruncate = Enum.TextTruncate.AtEnd
    display.ZIndex = 12
    display.Parent = profile

    local username = Instance.new("TextLabel")
    username.Name = "Username"
    username.BackgroundTransparency = 1
    username.Position = UDim2.fromOffset(43, 21)
    username.Size = UDim2.new(1, -48, 0, 14)
    username.Text = "@" .. LocalPlayer.Name
    username.TextColor3 = GlassLib.Theme.TextDim
    username.Font = Enum.Font.Gotham
    username.TextSize = 8
    username.TextXAlignment = Enum.TextXAlignment.Left
    username.TextTruncate = Enum.TextTruncate.AtEnd
    username.ZIndex = 12
    username.Parent = profile

    return profile
end

local function setupUltraMiniIcon(window)
    if window.UltraMiniIcon then
        safeDestroy(window.UltraMiniIcon)
        window.UltraMiniIcon = nil
    end

    local icon = Instance.new("ImageButton")
    icon.Name = "UltraMiniIcon"
    icon.AutoButtonColor = false
    icon.BackgroundColor3 = GlassLib.Theme.Secondary
    icon.BackgroundTransparency = 0.08
    icon.BorderSizePixel = 0
    icon.Size = UDim2.fromOffset(58, 58)
    icon.Position = UDim2.fromOffset(0, 0)
    icon.Image = ""
    icon.ZIndex = 30
    icon.Visible = false
    icon.Parent = window.MainFrame

    uiCorner(icon, 18)
    uiStroke(icon, GlassLib.Theme.Border, 0.72, 1)

    local avatar = window.Profile
        and window.Profile:FindFirstChild("Avatar")

    if avatar then
        icon.Image = avatar.Image
    else
        task.spawn(function()
            local ok, image = pcall(function()
                return Players:GetUserThumbnailAsync(
                    LocalPlayer.UserId,
                    Enum.ThumbnailType.HeadShot,
                    Enum.ThumbnailSize.Size100x100
                )
            end)

            if ok and image then
                icon.Image = image
            end
        end)
    end

    window.UltraMiniIcon = icon
end

local function setNormalVisibility(window, visible)
    window.Container.Visible = visible
    window.TabBar.Visible = visible
    window.TopHighlight.Visible = visible
end

local function getMiniSize(window)
    return V6.Minimize[window.MinimizeMode]
        or V6.Minimize.Default
end

local function saveNormalState(window)
    window.NormalPosition = window.MainFrame.Position
    window.NormalAnchor = window.MainFrame.AnchorPoint

    local topLeft = getTopLeftFromAbsolute(window.MainFrame)
    window.NormalTopLeft = topLeft
end

local function getMiniTargetPosition(window, size)
    local topLeft =
        window.NormalTopLeft
        or getTopLeftFromAbsolute(window.MainFrame)

    return UDim2.fromOffset(
        topLeft.X + size.Size.X.Offset / 2,
        topLeft.Y + size.Size.Y.Offset / 2
    )
end

local function applyMinimizeModeVisual(window, instant)
    local mode = window.MinimizeMode
    local cfg = getMiniSize(window)

    if window.Minimized then
        setNormalVisibility(window, false)
        window.LiquidIndicator.Visible = false

        window.TopBar.Size = UDim2.new(
            1,
            -12,
            0,
            cfg.TopHeight
        )

        if mode == "Default" then
            window.Profile.Visible = true
            window.MinimizeButton.Visible = true
            window.CloseButton.Visible = true
            window.UltraMiniIcon.Visible = false

        elseif mode == "Compacte" then
            window.Profile.Visible = false
            window.MinimizeButton.Visible = true
            window.CloseButton.Visible = true
            window.UltraMiniIcon.Visible = false

        else
            window.Profile.Visible = false
            window.MinimizeButton.Visible = false
            window.CloseButton.Visible = false
            window.UltraMiniIcon.Visible = true
        end

        local function finish()
            window.MainFrame.Size = cfg.Size
            window.Shadow.Size = cfg.Shadow
            window.MainFrame.Position =
                window._MiniTargetPosition
        end

        if instant then
            finish()
        else
            animate(
                window.MainFrame,
                GlassLib.Settings.AnimationTime + 0.08,
                {
                    Size = cfg.Size,
                    Position = window._MiniTargetPosition,
                }
            )

            animate(
                window.Shadow,
                GlassLib.Settings.AnimationTime,
                {
                    Size = cfg.Shadow,
                    Position = window._MiniTargetPosition,
                }
            )
        end

    else
        setNormalVisibility(window, true)
        window.LiquidIndicator.Visible = true

        window.Profile.Visible = true
        window.MinimizeButton.Visible = true
        window.CloseButton.Visible = true
        window.UltraMiniIcon.Visible = false

        if instant then
            window.MainFrame.Size = V6.NormalSize
            window.Shadow.Size = V6.ShadowSize
            window.MainFrame.Position = window.NormalPosition
            window.MainFrame.AnchorPoint = window.NormalAnchor
            window.Shadow.Position = window.MainFrame.Position
        else
            animate(
                window.MainFrame,
                GlassLib.Settings.AnimationTime + 0.10,
                {
                    Size = V6.NormalSize,
                    Position = window.NormalPosition,
                }
            )

            animate(
                window.Shadow,
                GlassLib.Settings.AnimationTime + 0.08,
                {
                    Size = V6.ShadowSize,
                    Position = window.NormalPosition,
                }
            )

            task.delay(
                GlassLib.Settings.AnimationTime,
                function()
                    if window.Destroyed then
                        return
                    end

                    window.MainFrame.AnchorPoint =
                        window.NormalAnchor
                end
            )
        end

        window.TopBar.Size = UDim2.new(
            1,
            -20,
            0,
            V6.NormalTopHeight
        )

        updateProfileMode(window)

        task.defer(function()
            refreshLiquidIndicator(window, true)
        end)
    end
end


function GlassLib:MakeWindow(config)
    config = config or {}

    cleanupExistingGlassGui()

    local window = {
        Title = config.Name or config.Title or "GlassLib UI",
        Subtitle = config.Subtitle or "",
        Tabs = {},
        CurrentTab = nil,
        Minimized = false,
        Destroyed = false,
        ProfileMode = GlassLib.Settings.ProfileMode,
        MinimizeMode = GlassLib.Settings.MinimizeMode,
        Connections = {},
    }

    local gui = Instance.new("ScreenGui")
    gui.Name = "GlassLib_UI"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Global
    gui.DisplayOrder = 2147483647

    local parent = getGuiParent()
    local parented = pcall(function()
        gui.Parent = parent
    end)

    if not parented or not gui.Parent then
        pcall(function()
            gui.Parent = CoreGui
        end)
    end

    if not gui.Parent then
        gui.Parent = PlayerGui
    end

    window.ScreenGui = gui
    window.Gui = gui

    --[[
    local shadow = Instance.new("Frame")
    shadow.Name = "GlassShadow"
    shadow.AnchorPoint = Vector2.new(0.5, 0.5)
    shadow.Size = V6.ShadowSize
    shadow.Position = UDim2.fromScale(0.5, 0.5)
    shadow.BackgroundColor3 = Color3.new(0, 0, 0)
    shadow.BackgroundTransparency = 0.77
    shadow.BorderSizePixel = 0
    shadow.ZIndex = 0
    shadow.Parent = gui
    uiCorner(shadow, 24)
    window.Shadow = shadow

    local shadow = Instance.new("ImageLabel") -- Changé en ImageLabel
    shadow.Name = "GlassShadow"
    shadow.AnchorPoint = Vector2.new(0.5, 0.5)
    shadow.Size = V6.ShadowSize
    shadow.Position = UDim2.fromScale(0.5, 0.5)
    shadow.BackgroundTransparency = 1 -- Fond invisible pour ne voir que l'image
    
    -- Propriétés de la texture de l'ombre
    shadow.Image = "rbxassetid://1316045217" -- ID d'une ombre douce standard
    shadow.ImageColor3 = Color3.new(0, 0, 0)
    shadow.ImageTransparency = 0.5 -- Ajuste l'opacité ici (0 = opaque, 1 = invisible)
    shadow.ScaleType = Enum.ScaleType.Slice -- Permet d'étirer l'ombre sans la déformer
    shadow.SliceCenter = Rect.new(10, 10, 118, 118) -- Zone centrale à ne pas déformer
    
    shadow.ZIndex = 0
    shadow.Parent = gui
    window.Shadow = shadow
]]--

    local shadow = Instance.new("ImageLabel")
    shadow.Name = "GlassShadow"
    shadow.AnchorPoint = Vector2.new(0.5, 0.5)
    
    -- CORRECTION : On agrandit un peu l'ombre pour que le flou dépasse proprement tout autour
    -- Si V6.ShadowSize est déjà plus grand que ta fenêtre, tu peux laisser : shadow.Size = V6.ShadowSize
    shadow.Size = V6.ShadowSize + UDim2.fromOffset(40, 40) 
    
    shadow.Position = UDim2.fromScale(0.5, 0.5)
    shadow.BackgroundTransparency = 1
    
    -- NOUVEL ID : Ombre moderne, douce et sans glitchs visuels
    shadow.Image = "rbxassetid://5554236805" 
    shadow.ImageColor3 = Color3.new(0, 0, 0)
    shadow.ImageTransparency = 0.55 -- Augmente (ex: 0.7) si tu la trouves encore trop sombre
    
    -- SliceCenter calibré au pixel près pour cette texture spécifique
    shadow.ScaleType = Enum.ScaleType.Slice
    shadow.SliceCenter = Rect.new(15, 15, 285, 285)
    
    shadow.ZIndex = 0
    shadow.Parent = gui
    window.Shadow = shadow


    local main = Instance.new("Frame")
    main.Name = "MainFrame"
    main.AnchorPoint = Vector2.new(0.5, 0.5)
    main.Size = V6.NormalSize
    main.Position = UDim2.fromScale(0.5, 0.5)
    main.BackgroundColor3 = GlassLib.Theme.Background
    main.BackgroundTransparency = GlassLib.Theme.Transparency
    main.BorderSizePixel = 0
    main.ClipsDescendants = true
    main.Active = true
    main.ZIndex = 1
    main.Parent = gui
    uiCorner(main, 20)
    uiStroke(main, GlassLib.Theme.Border, 0.86, 1)
    window.MainFrame = main

    local glassLayer = Instance.new("Frame")
    glassLayer.Name = "GlassLayer"
    glassLayer.Size = UDim2.new(1, -2, 1, -2)
    glassLayer.Position = UDim2.fromOffset(1, 1)
    glassLayer.BackgroundColor3 = Color3.new(1, 1, 1)
    glassLayer.BackgroundTransparency = 0.975
    glassLayer.BorderSizePixel = 0
    glassLayer.ZIndex = 2
    glassLayer.Parent = main
    uiCorner(glassLayer, 19)

    local gradient = Instance.new("UIGradient")
    gradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
        ColorSequenceKeypoint.new(0.48, Color3.fromRGB(228, 239, 255)),
        ColorSequenceKeypoint.new(1, Color3.new(1, 1, 1)),
    })
    gradient.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.987),
        NumberSequenceKeypoint.new(0.48, 0.975),
        NumberSequenceKeypoint.new(1, 0.991),
    })
    gradient.Rotation = 90
    gradient.Parent = glassLayer

    local topHighlight = Instance.new("Frame")
    topHighlight.Name = "TopHighlight"
    topHighlight.Size = UDim2.new(1, -4, 0, 78)
    topHighlight.Position = UDim2.fromOffset(2, 2)
    topHighlight.BackgroundColor3 = Color3.new(1, 1, 1)
    topHighlight.BackgroundTransparency = 0.989
    topHighlight.BorderSizePixel = 0
    topHighlight.ZIndex = 3
    topHighlight.Parent = main
    uiCorner(topHighlight, 18)
    window.TopHighlight = topHighlight

    local top = Instance.new("Frame")
    top.Name = "TopBar"
    top.Size = UDim2.new(1, -20, 0, V6.NormalTopHeight)
    top.Position = UDim2.fromOffset(10, 7)
    top.BackgroundTransparency = 1
    top.Active = true
    top.ZIndex = 8
    top.Parent = main
    window.TopBar = top

    local dragHandle = Instance.new("TextButton")
    dragHandle.Name = "DragHandle"
    dragHandle.AutoButtonColor = false
    dragHandle.BackgroundTransparency = 1
    dragHandle.BorderSizePixel = 0
    dragHandle.Size = UDim2.new(1, 0, 1, 0)
    dragHandle.Text = ""
    dragHandle.ZIndex = 8
    dragHandle.Parent = top
    window.DragHandle = dragHandle

    local title = Instance.new("TextLabel")
    title.Name = "Title"
    title.Size = UDim2.new(0, 185, 0, 25)
    title.Position = UDim2.fromOffset(14, 8)
    title.BackgroundTransparency = 1
    title.Text = window.Title
    title.Font = Enum.Font.GothamBold
    title.TextSize = 17
    title.TextColor3 = GlassLib.Theme.Text
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.ZIndex = 12
    title.Parent = top
    window.TitleLabel = title

    local subtitle = Instance.new("TextLabel")
    subtitle.Name = "Subtitle"
    subtitle.Size = UDim2.new(0, 185, 0, 15)
    subtitle.Position = UDim2.fromOffset(14, 32)
    subtitle.BackgroundTransparency = 1
    subtitle.Text = window.Subtitle
    subtitle.Font = THEME.Font
    subtitle.TextSize = 10
    subtitle.TextColor3 = GlassLib.Theme.TextDim
    subtitle.TextXAlignment = Enum.TextXAlignment.Left
    subtitle.ZIndex = 12
    subtitle.Parent = top
    window.SubtitleLabel = subtitle

    local profile = createProfileCard(window, top)
    window.Profile = profile
    updateProfileMode(window)

    local function makeControl(name, text, xOffset, tint)
        local b = Instance.new("TextButton")
        b.Name = name
        b.Size = UDim2.fromOffset(28, 28)
        b.AnchorPoint = Vector2.new(1, 0)
        b.Position = UDim2.new(1, xOffset, 0, 13)
        b.BackgroundColor3 = GlassLib.Theme.Secondary
        b.BackgroundTransparency = 0.56
        b.BorderSizePixel = 0
        b.AutoButtonColor = false
        b.Text = text
        b.Font = Enum.Font.GothamBold
        b.TextSize = 15
        b.TextColor3 = tint or GlassLib.Theme.TextDim
        b.ZIndex = 14
        b.Active = true
        b.Parent = top
        uiCorner(b, 9)
        uiStroke(b, GlassLib.Theme.Border, 0.82, 1)

        b.MouseEnter:Connect(function()
            animate(b, 0.12, {
                BackgroundTransparency = 0.30,
                TextColor3 = GlassLib.Theme.Text,
            }, Enum.EasingDirection.Out)
        end)

        b.MouseLeave:Connect(function()
            animate(b, 0.16, {
                BackgroundTransparency = 0.56,
                TextColor3 = tint or GlassLib.Theme.TextDim,
            })
        end)

        return b
    end

    local minimize = makeControl("Minimize", "−", -43)
    local close = makeControl(
        "Close",
        "×",
        -8,
        Color3.fromRGB(255, 132, 148)
    )

    window.MinimizeButton = minimize
    window.CloseButton = close

    local tabBar = Instance.new("Frame")
    tabBar.Name = "TabBar"
    tabBar.Size = UDim2.new(1, -24, 0, 40)
    tabBar.Position = UDim2.fromOffset(12, 67)
    tabBar.BackgroundColor3 = GlassLib.Theme.Secondary
    tabBar.BackgroundTransparency = 0.54
    tabBar.BorderSizePixel = 0
    tabBar.ClipsDescendants = true
    tabBar.Active = true
    tabBar.ZIndex = 7
    tabBar.Parent = main
    uiCorner(tabBar, 13)
    uiStroke(tabBar, GlassLib.Theme.Border, 0.90, 1)
    window.TabBar = tabBar

    local tabScroll = Instance.new("ScrollingFrame")
    tabScroll.Name = "TabScroll"
    tabScroll.Size = UDim2.new(1, 0, 1, 0)
    tabScroll.BackgroundTransparency = 1
    tabScroll.BorderSizePixel = 0
    tabScroll.ScrollBarThickness = 0
    tabScroll.ScrollingDirection = Enum.ScrollingDirection.X
    tabScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    tabScroll.AutomaticCanvasSize = Enum.AutomaticSize.X
    tabScroll.ScrollingEnabled = true
    tabScroll.ZIndex = 7
    tabScroll.Parent = tabBar
    window.TabScroll = tabScroll

    local padding = Instance.new("UIPadding")
    padding.PaddingLeft = UDim.new(0, 4)
    padding.PaddingRight = UDim.new(0, 4)
    padding.PaddingTop = UDim.new(0, 3)
    padding.PaddingBottom = UDim.new(0, 3)
    padding.Parent = tabScroll

    local layout = Instance.new("UIListLayout")
    layout.FillDirection = Enum.FillDirection.Horizontal
    layout.VerticalAlignment = Enum.VerticalAlignment.Center
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Padding = UDim.new(0, 4)
    layout.Parent = tabScroll
    window.TabLayout = layout
-- ====================================================================
-- 2. TON EXTRAIT DE MAKEWINDOW (Avec la connexion ajoutée en bas)
-- ====================================================================
-- [Vos lignes de création de tabBar, tabScroll, padding, layout restent identiques...]

    -- Indicator is OUTSIDE the scrolling list, so it is never a fake tab.
    local liquid = Instance.new("Frame")
    liquid.Name = "LiquidIndicator"
    liquid.Size = UDim2.fromOffset(96, GlassLib.Settings.LiquidHeight)
    liquid.Position = UDim2.fromOffset(4, 3)
    liquid.BackgroundColor3 = GlassLib.Theme.Accent
    liquid.BackgroundTransparency = 0.72
    liquid.BorderSizePixel = 0
    liquid.ZIndex = 8
    liquid.Parent = tabBar
    uiCorner(liquid, 14)
    uiStroke(liquid, GlassLib.Theme.Border, 0.78, 1)
    window.LiquidIndicator = liquid

    -- <<< AJOUT ICI : CONNEXION POUR METTRE À JOUR LA BULLE PENDANT LE SCROLL >>>
    tabScroll:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
        -- On passe "true" pour forcer une mise à jour instantanée sans Tween,
        -- sinon la bulle aurait du retard sur le mouvement du doigt/de la souris.
        refreshLiquidIndicator(window, true)
    end)

    local content = Instance.new("Frame")
    content.Name = "Container"
    content.Size = UDim2.new(1, -24, 1, -116)
    content.Position = UDim2.fromOffset(12, 112)
    content.BackgroundTransparency = 1
    content.BorderSizePixel = 0
    content.ClipsDescendants = true
    content.ZIndex = 4
    content.Parent = main
    window.Container = content
    window.Layout = layout

    setupUltraMiniIcon(window)

    -- Track existing position before any minimize.
    saveNormalState(window)
    window._AppliedTheme = {
        Background = GlassLib.Theme.Background,
        Secondary = GlassLib.Theme.Secondary,
        Accent = GlassLib.Theme.Accent,
        Border = GlassLib.Theme.Border,
        Text = GlassLib.Theme.Text,
        TextDim = GlassLib.Theme.TextDim,
    }

    -- True drag surface: the empty space is draggable, while profile/buttons
    -- sit above it.
    do
        local dragging = false
        local dragStart
        local startPos
        local clickStart
        local moved = false

        safeConnect(dragHandle.InputBegan, function(input)
            if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
                return
            end

            dragging = true
            moved = false
            dragStart = input.Position
            clickStart = input.Position
            startPos = main.Position
        end, window.Connections)

        safeConnect(UserInputService.InputChanged, function(input)
            if not dragging
                or input.UserInputType ~= Enum.UserInputType.MouseMovement
            then
                return
            end

            local delta = input.Position - dragStart

            if delta.Magnitude > 4 then
                moved = true
            end

            main.Position = UDim2.new(
                startPos.X.Scale,
                startPos.X.Offset + delta.X,
                startPos.Y.Scale,
                startPos.Y.Offset + delta.Y
            )

            shadow.Position = main.Position

            if not window.Minimized then
                window.NormalPosition = main.Position
                task.defer(function()
                    if not window.Minimized and main.Parent then
                        window.NormalTopLeft = main.AbsolutePosition
                    end
                end)
            end
        end, window.Connections)

        safeConnect(UserInputService.InputEnded, function(input)
            if input.UserInputType ~= Enum.UserInputType.MouseButton1
            then
                return
            end

            if dragging
                and window.Minimized
                and window.MinimizeMode == "Ultra compacte"
                and not moved
            then
                window:Restore()
            end

            dragging = false
        end, window.Connections)
    end

    -- Ultra-compact mini square: click restores; dragging moves it.
    do
        local ultraDragging = false
        local ultraDragStart
        local ultraStartPos
        local ultraMoved = false

        safeConnect(window.UltraMiniIcon.InputBegan, function(input)
            if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
                return
            end

            if not window.Minimized
                or window.MinimizeMode ~= "Ultra compacte"
            then
                return
            end

            ultraDragging = true
            ultraMoved = false
            ultraDragStart = input.Position
            ultraStartPos = main.Position
        end, window.Connections)

        safeConnect(UserInputService.InputChanged, function(input)
            if not ultraDragging
                or input.UserInputType ~= Enum.UserInputType.MouseMovement
            then
                return
            end

            local delta = input.Position - ultraDragStart

            if delta.Magnitude > 4 then
                ultraMoved = true
            end

            main.Position = UDim2.new(
                ultraStartPos.X.Scale,
                ultraStartPos.X.Offset + delta.X,
                ultraStartPos.Y.Scale,
                ultraStartPos.Y.Offset + delta.Y
            )

            shadow.Position = main.Position
        end, window.Connections)

        safeConnect(UserInputService.InputEnded, function(input)
            if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
                return
            end

            if ultraDragging
                and not ultraMoved
                and window.Minimized
                and window.MinimizeMode == "Ultra compacte"
            then
                window:Restore()
            end

            ultraDragging = false
        end, window.Connections)
    end

    safeConnect(minimize.Activated, function()
        window:ToggleMinimize()
    end, window.Connections)

    safeConnect(close.Activated, function()
        window:Destroy()
    end, window.Connections)

    safeConnect(UserInputService.InputBegan, function(input, processed)
        if processed then
            return
        end

        if input.KeyCode == Enum.KeyCode.RightControl then
            window:ToggleMinimize()
        end
    end, window.Connections)

    safeConnect(tabScroll:GetPropertyChangedSignal("CanvasPosition"), function()
        if window.CurrentTab then
            refreshLiquidIndicator(window, true)
        end
    end, window.Connections)

    safeConnect(layout:GetPropertyChangedSignal("AbsoluteContentSize"), function()
        if window.CurrentTab then
            task.defer(function()
                refreshLiquidIndicator(window, true)
            end)
        end
    end, window.Connections)

    -- Expose Window methods. The functions resolve at call time,
    -- so their GlassLib implementations may be declared later in the file.
    setmetatable(window, {
        __index = {
            MakeTab = function(_, tabConfig)
                return GlassLib:MakeTab(tabConfig)
            end,
            ToggleMinimize = function(_)
                return GlassLib:ToggleMinimize()
            end,
            Minimize = function(_)
                return GlassLib:Minimize()
            end,
            Restore = function(_)
                return GlassLib:Restore()
            end,
            Destroy = function(_)
                return GlassLib:Destroy()
            end,
        },
    })

    table.insert(GlassLib.Windows, window)
    self.Window = window

    -- Fade / entrance.
    main.BackgroundTransparency = 1
    shadow.BackgroundTransparency = 1

    task.defer(function()
        animate(
            shadow,
            0.42,
            {
                BackgroundTransparency = 0.77,
                Size = V6.ShadowSize,
            }
        )

        animate(
            main,
            0.52,
            {
                BackgroundTransparency = GlassLib.Theme.Transparency,
                Size = V6.NormalSize,
            },
            Enum.EasingDirection.Out
        )
    end)

    setBlur(
        GlassLib.Settings.BlurEnabled,
        GlassLib.Settings.BlurSize
    )

    return window
end

function GlassLib:MakeTab(config)
    config = config or {}

    local window = self.Window
    assert(
        window,
        "GlassLib:MakeWindow must be called before MakeTab"
    )

    local tab = {
        Name = config.Name or "Tab",
        Order = #window.Tabs + 1,
        Elements = {},
    }

    local textSize =
        TextService:GetTextSize(
            tab.Name,
            11,
            THEME.Font,
            Vector2.new(500, 34)
        )

    local width = math.max(
        94,
        textSize.X + 30
    )

    local button = Instance.new("TextButton")
    button.Name = "TabButton"
    button.Size = UDim2.fromOffset(width, 34)
    button.BackgroundTransparency = 1
    button.BorderSizePixel = 0
    button.AutoButtonColor = false
    button.Text = tab.Name
    button.Font = THEME.Font
    button.TextSize = 11
    button.TextColor3 = GlassLib.Theme.TextDim
    button.LayoutOrder = tab.Order
    button.ZIndex = 10
    button.Active = true
    button.Parent = window.TabScroll

    local page = Instance.new("ScrollingFrame")
    page.Name = "Page"
    page.Size = UDim2.fromScale(1, 1)
    page.Position = UDim2.fromScale(1.08, 0)
    page.BackgroundTransparency = 1
    page.BorderSizePixel = 0
    page.ScrollBarThickness = 3
    page.ScrollBarImageColor3 = GlassLib.Theme.Accent
    page.ScrollBarImageTransparency = 0.55
    page.AutomaticCanvasSize = Enum.AutomaticSize.Y
    page.CanvasSize = UDim2.new(0, 0, 0, 0)
    page.ScrollingDirection = Enum.ScrollingDirection.Y
    page.Visible = false
    page.ZIndex = 5
    page.Parent = window.Container

    local pagePadding = Instance.new("UIPadding")
    pagePadding.PaddingTop = UDim.new(0, 3)
    pagePadding.PaddingBottom = UDim.new(0, 12)
    pagePadding.PaddingLeft = UDim.new(0, 2)
    pagePadding.PaddingRight = UDim.new(0, 8)
    pagePadding.Parent = page

    local pageLayout = Instance.new("UIListLayout")
    pageLayout.SortOrder = Enum.SortOrder.LayoutOrder
    pageLayout.Padding = UDim.new(0, 8)
    pageLayout.Parent = page

    tab.Button = button
    tab.Page = page

    table.insert(window.Tabs, tab)

    local function select()
        if window.CurrentTab == tab then
            keepTabVisible(window, tab)
            refreshLiquidIndicator(window, false)
            return
        end

        local old = window.CurrentTab
        local direction =
            old and tab.Order < old.Order and -1 or 1

        window.CurrentTab = tab

        if old then
            animate(
                old.Button,
                0.16,
                {TextColor3 = GlassLib.Theme.TextDim}
            )

            animate(
                old.Page,
                GlassLib.Settings.AnimationTime,
                {
                    Position = UDim2.new(
                        -direction * 1.08,
                        0,
                        0,
                        0
                    ),
                }
            )
        end

        page.Visible = true
        page.Position = UDim2.new(
            direction * 1.08,
            0,
            0,
            0
        )

        animate(
            button,
            0.18,
            {TextColor3 = GlassLib.Theme.Text}
        )

        refreshLiquidIndicator(window, false)
        keepTabVisible(window, tab)

        animate(
            page,
            GlassLib.Settings.AnimationTime + 0.10,
            {Position = UDim2.fromScale(0, 0)}
        )

        local originalSize = button.Size

        button.Size = UDim2.fromOffset(
            originalSize.X.Offset + 3,
            originalSize.Y.Offset
        )

        animate(
            button,
            0.26,
            {Size = originalSize},
            Enum.EasingDirection.Out
        )

        if old then
            task.delay(
                GlassLib.Settings.AnimationTime + 0.06,
                function()
                    if old ~= window.CurrentTab
                        and old.Page.Parent
                    then
                        old.Page.Visible = false
                    end
                end
            )
        end
    end

    button.Activated:Connect(select)

    button.MouseEnter:Connect(function()
        if window.CurrentTab ~= tab then
            animate(
                button,
                0.12,
                {
                    TextColor3 = GlassLib.Theme.Text,
                },
                Enum.EasingDirection.Out
            )
        end
    end)

    button.MouseLeave:Connect(function()
        if window.CurrentTab ~= tab then
            animate(
                button,
                0.16,
                {
                    TextColor3 = GlassLib.Theme.TextDim,
                }
            )
        end
    end)

    -- First tab is automatically selected.
    if #window.Tabs == 1 then
        window.CurrentTab = tab
        button.TextColor3 = GlassLib.Theme.Text
        page.Visible = true
        page.Position = UDim2.fromScale(0, 0)

        task.defer(function()
            refreshLiquidIndicator(window, true)
        end)
    end

    setmetatable(tab, {
        __index = {
            AddSection = function(_, c)
                return GlassLib:AddSection(tab, c)
            end,
            AddLabel = function(_, t)
                return GlassLib:AddLabel(tab, t)
            end,
            AddParagraph = function(_, a, b)
                return GlassLib:AddParagraph(tab, a, b)
            end,
            AddButton = function(_, c)
                return GlassLib:AddButton(tab, c)
            end,
            AddToggle = function(_, c)
                return GlassLib:AddToggle(tab, c)
            end,
            AddSlider = function(_, c)
                return GlassLib:AddSlider(tab, c)
            end,
            AddDropdown = function(_, c)
                return GlassLib:AddDropdown(tab, c)
            end,
            AddTextbox = function(_, c)
                return GlassLib:AddTextbox(tab, c)
            end,
            AddColorpicker = function(_, c)
                return GlassLib:AddColorpicker(tab, c)
            end,
        },
    })

    return tab
end

local oldAddColorpicker = GlassLib.AddColorpicker

function GlassLib:AddColorpicker(tab, config)
    local api = oldAddColorpicker(self, tab, config)
    local base = api and api.Instance

    if base then
        uiStroke(
            base,
            GlassLib.Theme.Border,
            0.91,
            1
        )

        local popup = base:FindFirstChild("ColorpickerPopup")
        if popup then
            popup.BackgroundColor3 = GlassLib.Theme.Background
            popup.BackgroundTransparency = 0.08
            uiCorner(popup, 12)

            local existingStroke =
                popup:FindFirstChildOfClass("UIStroke")

            if existingStroke then
                existingStroke.Color = GlassLib.Theme.Border
                existingStroke.Transparency = 0.88
                existingStroke.Thickness = 1
            else
                uiStroke(
                    popup,
                    GlassLib.Theme.Border,
                    0.88,
                    1
                )
            end
        end
    end

    return api
end

local function createNotificationGui()
    local parent = getGuiParent()
    local gui = parent:FindFirstChild("GlassLib_Notifs")

    if gui then
        return gui
    end

    gui = Instance.new("ScreenGui")
    gui.Name = "GlassLib_Notifs"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Global
    gui.DisplayOrder = 2147483647

    local ok = pcall(function()
        gui.Parent = parent
    end)

    if not ok or not gui.Parent then
        pcall(function()
            gui.Parent = CoreGui
        end)
    end

    if not gui.Parent then
        gui.Parent = PlayerGui
    end

    return gui
end

function GlassLib:MakeNotification(config)
    config = config or {}

    local title = config.Title or config.Name or "Notification"
    local content = config.Content or ""
    local duration =
        tonumber(config.Duration or config.Time or 5)
        or 5

    local gui = createNotificationGui()

    local holder = gui:FindFirstChild("Holder")

    if not holder then
        holder = Instance.new("Frame")
        holder.Name = "Holder"
        holder.AnchorPoint = Vector2.new(1, 1)
        holder.Position = UDim2.new(1, -18, 1, -18)
        holder.Size = UDim2.fromOffset(330, 360)
        holder.BackgroundTransparency = 1
        holder.Parent = gui

        local layout = Instance.new("UIListLayout")
        layout.FillDirection = Enum.FillDirection.Vertical
        layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
        layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
        layout.Padding = UDim.new(0, 7)
        layout.Parent = holder
    end

    local card = Instance.new("Frame")
    card.Size = UDim2.fromOffset(300, 68)
    card.BackgroundColor3 = GlassLib.Theme.Secondary
    card.BackgroundTransparency = 0.10
    card.BorderSizePixel = 0
    card.Parent = holder

    uiCorner(card, 13)
    uiStroke(card, GlassLib.Theme.Border, 0.82, 1)

    local titleLabel = Instance.new("TextLabel")
    titleLabel.BackgroundTransparency = 1
    titleLabel.Position = UDim2.fromOffset(13, 8)
    titleLabel.Size = UDim2.new(1, -26, 0, 18)
    titleLabel.Text = title
    titleLabel.TextColor3 = GlassLib.Theme.Accent
    titleLabel.Font = Enum.Font.GothamBold
    titleLabel.TextSize = 13
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel.Parent = card

    local contentLabel = Instance.new("TextLabel")
    contentLabel.BackgroundTransparency = 1
    contentLabel.Position = UDim2.fromOffset(13, 29)
    contentLabel.Size = UDim2.new(1, -26, 0, 31)
    contentLabel.Text = content
    contentLabel.TextColor3 = GlassLib.Theme.Text
    contentLabel.Font = Enum.Font.Gotham
    contentLabel.TextSize = 11
    contentLabel.TextWrapped = true
    contentLabel.TextXAlignment = Enum.TextXAlignment.Left
    contentLabel.TextYAlignment = Enum.TextYAlignment.Top
    contentLabel.Parent = card

    card.Position = UDim2.fromOffset(20, 0)
    card.BackgroundTransparency = 1

    animate(
        card,
        0.34,
        {
            Position = UDim2.fromOffset(0, 0),
            BackgroundTransparency = 0.10,
        },
        Enum.EasingDirection.Out
    )

    task.delay(duration, function()
        if not card.Parent then
            return
        end

        local t = animate(
            card,
            0.22,
            {
                Position = UDim2.fromOffset(25, 0),
                BackgroundTransparency = 1,
            },
            Enum.EasingDirection.In
        )

        if t then
            t.Completed:Connect(function()
                safeDestroy(card)
            end)
        else
            safeDestroy(card)
        end
    end)
end

function GlassLib:SetTheme(theme)
    if type(theme) ~= "table" then
        return
    end

    local old = {
        Background = GlassLib.Theme.Background,
        Secondary = GlassLib.Theme.Secondary,
        Accent = GlassLib.Theme.Accent,
        Border = GlassLib.Theme.Border,
        Text = GlassLib.Theme.Text,
        TextDim = GlassLib.Theme.TextDim,
    }

    for key, value in pairs(theme) do
        if GlassLib.Theme[key] ~= nil then
            GlassLib.Theme[key] = value
        end
    end

    applyLegacyTheme()

    for _, window in ipairs(GlassLib.Windows) do
        if not window.Destroyed then
            window._AppliedTheme = old
            updateThemeRefs(window)
        end
    end
end

function GlassLib:ApplyUIProfile(name)
    local profile = GlassLib.UIProfiles[name]

    if type(profile) ~= "table" then
        return false
    end

    local old = {
        Background = GlassLib.Theme.Background,
        Secondary = GlassLib.Theme.Secondary,
        Accent = GlassLib.Theme.Accent,
        Border = GlassLib.Theme.Border,
        Text = GlassLib.Theme.Text,
        TextDim = GlassLib.Theme.TextDim,
    }

    for key, value in pairs(profile) do
        if GlassLib.Theme[key] ~= nil then
            GlassLib.Theme[key] = value
        end
    end

    GlassLib.Settings.BackgroundTransparency =
        math.clamp(
            profile.Transparency or GlassLib.Settings.BackgroundTransparency,
            0,
            0.92
        )

    applyLegacyTheme()

    for _, window in ipairs(GlassLib.Windows) do
        if not window.Destroyed then
            window._AppliedTheme = old
            updateThemeRefs(window)
        end
    end

    setBlur(
        GlassLib.Settings.BlurEnabled,
        GlassLib.Settings.BlurSize
    )

    return true
end

function GlassLib:SetBackgroundTransparency(value)
    GlassLib.Settings.BackgroundTransparency =
        math.clamp(
            tonumber(value) or 0.16,
            0,
            0.92
        )

    GlassLib.Theme.Transparency =
        GlassLib.Settings.BackgroundTransparency

    applyLegacyTheme()

    for _, window in ipairs(GlassLib.Windows) do
        if window.MainFrame then
            window.MainFrame.BackgroundTransparency =
                GlassLib.Settings.BackgroundTransparency
        end
    end
end

function GlassLib:SetBlur(enabled, size)
    GlassLib.Settings.BlurEnabled = enabled == true

    if size ~= nil then
        GlassLib.Settings.BlurSize =
            math.clamp(
                tonumber(size) or 0,
                0,
                24
            )
    end

    setBlur(
        GlassLib.Settings.BlurEnabled,
        GlassLib.Settings.BlurSize
    )
end

function GlassLib:SetProfileMode(mode)
    if not table.find({
        "Default",
        "Compacte",
        "Ultra compacte",
    }, mode) then
        return
    end

    GlassLib.Settings.ProfileMode = mode

    for _, window in ipairs(GlassLib.Windows) do
        if not window.Destroyed then
            window.ProfileMode = mode
            updateProfileMode(window)
        end
    end
end

function GlassLib:SetMinimizeMode(mode)
    if not V6.Minimize[mode] then
        return
    end

    GlassLib.Settings.MinimizeMode = mode

    for _, window in ipairs(GlassLib.Windows) do
        if not window.Destroyed then
            window.MinimizeMode = mode

            if window.Minimized then
                local cfg = getMiniSize(window)

                window._MiniTargetPosition =
                    getMiniTargetPosition(window, cfg)

                applyMinimizeModeVisual(window, false)
            else
                updateProfileMode(window)
            end
        end
    end
end

function GlassLib:SetLiquidHeight(value)
    GlassLib.Settings.LiquidHeight =
        math.clamp(
            tonumber(value) or 34,
            26,
            42
        )

    for _, window in ipairs(GlassLib.Windows) do
        if window.LiquidIndicator then
            refreshLiquidIndicator(window, true)
        end
    end
end

function GlassLib:ToggleMinimize()
    if not self.Window then
        return
    end

    local window = self.Window

    if window.Destroyed then
        return
    end

    if window.Minimized then
        self:Restore()
        return
    end

    saveNormalState(window)

    local cfg = getMiniSize(window)

    window._MiniTargetPosition =
        getMiniTargetPosition(window, cfg)

    window.Minimized = true

    -- Keep the window anchored at the center of itself during the resize.
    -- The destination center is calculated from the original top-left.
    applyMinimizeModeVisual(window, false)
end

function GlassLib:Minimize()
    if self.Window and not self.Window.Minimized then
        self:ToggleMinimize()
    end
end

function GlassLib:Restore()
    if not self.Window then
        return
    end

    local window = self.Window

    if not window.Minimized then
        return
    end

    window.Minimized = false

    applyMinimizeModeVisual(window, false)

    task.defer(function()
        if not window.Destroyed then
            refreshLiquidIndicator(window, true)
            keepTabVisible(window, window.CurrentTab)
        end
    end)
end

function GlassLib:BuildUISettingsTab(window)
    if not window then
        return nil
    end

    if window.UISettingsTab then
        return window.UISettingsTab
    end

    for _, existingTab in ipairs(window.Tabs) do
        if existingTab.Name == "UI" then
            window.UISettingsTab = existingTab
            return existingTab
        end
    end

    local tab = window:MakeTab({
        Name = "UI",
    })

    window.UISettingsTab = tab

    tab:AddSection({
        Name = "Apparence",
    })

    tab:AddDropdown({
        Name = "Profil de thème",
        Default = "Default",
        Options = {
            "Default",
            "Midnight",
            "Ocean",
            "Emerald",
            "Rose",
        },
        Callback = function(value)
            GlassLib:ApplyUIProfile(value)
        end,
    })

    tab:AddColorpicker({
        Name = "Couleur primaire",
        Default = GlassLib.Theme.Background,
        Callback = function(value)
            GlassLib:SetTheme({
                Background = value,
            })
        end,
    })

    tab:AddColorpicker({
        Name = "Couleur secondaire",
        Default = GlassLib.Theme.Secondary,
        Callback = function(value)
            GlassLib:SetTheme({
                Secondary = value,
            })
        end,
    })

    tab:AddColorpicker({
        Name = "Couleur accent",
        Default = GlassLib.Theme.Accent,
        Callback = function(value)
            GlassLib:SetTheme({
                Accent = value,
            })
        end,
    })

    tab:AddColorpicker({
        Name = "Couleur du contour",
        Default = GlassLib.Theme.Border,
        Callback = function(value)
            GlassLib:SetTheme({
                Border = value,
            })
        end,
    })

    tab:AddSlider({
        Name = "Transparence",
        Min = 0,
        Max = 90,
        Default = math.floor(
            GlassLib.Settings.BackgroundTransparency * 100
        ),
        Increment = 5,
        ValueName = "%",
        Callback = function(value)
            GlassLib:SetBackgroundTransparency(
                value / 100
            )
        end,
    })

    tab:AddSlider({
        Name = "Fluidité",
        Min = 10,
        Max = 60,
        Default = math.floor(
            GlassLib.Settings.AnimationTime * 100
        ),
        Increment = 5,
        ValueName = "x0.01s",
        Callback = function(value)
            GlassLib.Settings.AnimationTime =
                value / 100
        end,
    })

    tab:AddSlider({
        Name = "Épaisseur indicateur",
        Min = 26,
        Max = 42,
        Default = GlassLib.Settings.LiquidHeight,
        Increment = 2,
        ValueName = "px",
        Callback = function(value)
            GlassLib:SetLiquidHeight(value)
        end,
    })

    tab:AddSection({
        Name = "Carte joueur",
    })

    tab:AddDropdown({
        Name = "Style carte joueur",
        Default = GlassLib.Settings.ProfileMode,
        Options = {
            "Default",
            "Compacte",
            "Ultra compacte",
        },
        Callback = function(value)
            GlassLib:SetProfileMode(value)
        end,
    })

    tab:AddSection({
        Name = "Réduction",
    })

    tab:AddDropdown({
        Name = "Mode minimisation",
        Default = GlassLib.Settings.MinimizeMode,
        Options = {
            "Default",
            "Compacte",
            "Ultra compacte",
        },
        Callback = function(value)
            GlassLib:SetMinimizeMode(value)
        end,
    })

    tab:AddParagraph(
        "Raccourci",
        "Right Ctrl : minimiser / restaurer."
    )

    tab:AddSection({
        Name = "Effets",
    })

    tab:AddToggle({
        Name = "Flou arrière-plan",
        Default = GlassLib.Settings.BlurEnabled,
        Callback = function(value)
            GlassLib:SetBlur(
                value,
                GlassLib.Settings.BlurSize
            )
        end,
    })

    tab:AddSlider({
        Name = "Intensité du flou",
        Min = 0,
        Max = 100,
        Default = math.floor(
            (GlassLib.Settings.BlurSize / 24) * 100
        ),
        Increment = 5,
        ValueName = "%",
        Callback = function(value)
            GlassLib:SetBlur(
                value > 0,
                24 * (value / 100)
            )
        end,
    })

    return tab
end

function GlassLib:Destroy()
    if self.Window and not self.Window.Destroyed then
        local window = self.Window
        window.Destroyed = true

        for _, connection in ipairs(window.Connections or {}) do
            pcall(function()
                connection:Disconnect()
            end)
        end

        table.clear(window.Connections)

        local gui = window.Gui
        local main = window.MainFrame

        if main and main.Parent then
            animate(
                main,
                0.22,
                {
                    BackgroundTransparency = 1,
                    Size = UDim2.fromOffset(570, 420),
                },
                Enum.EasingDirection.In
            )
        end

        task.delay(
            0.24,
            function()
                safeDestroy(gui)
            end
        )
    end

    cleanupExistingGlassGui()
    setBlur(false)

    if rawget(_G, "_GlassLibRuntime") == self then
        _G._GlassLibRuntime = nil
    end

    for i = #GlassLib.Windows, 1, -1 do
        if GlassLib.Windows[i] == self.Window then
            table.remove(GlassLib.Windows, i)
        end
    end
end

function GlassLib:Init()
    local window = self.Window

    if not window then
        return
    end

    if window.Destroyed then
        return
    end

    -- UI is created HERE so it is guaranteed to be the LAST tab.
    self:BuildUISettingsTab(window)

    task.defer(function()
        if window.CurrentTab then
            refreshLiquidIndicator(window, true)
            keepTabVisible(window, window.CurrentTab)
        end
    end)
end

return GlassLib
