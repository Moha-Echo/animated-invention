local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local UserInputService = game:GetService("UserInputService")


local GlassLib = {}
GlassLib.__index = GlassLib

-- Configuration du style "Apple Liquid Glass"
local THEME = {
    Background = Color3.fromRGB(20, 35, 55), -- Fond bleu sombre translucide
    BackgroundTrans = 0.55,
    GlassBorder = Color3.fromRGB(255, 255, 255), -- Contour brillant
    BorderTrans = 0.7,
    Accent = Color3.fromRGB(0, 122, 255), -- Bleu Apple
    Text = Color3.fromRGB(255, 255, 255),
    TextDim = Color3.fromRGB(200, 210, 220),
    Font = Enum.Font.GothamMedium,
}

-- Helpers d'animation (Smooth, Élastique, Fade)
local function tween(object, info, properties)
    local t = TweenService:Create(object, info, properties)
    t:Play()
    return t
end

-- Création de la Fenêtre Principale
function GlassLib:MakeWindow(config)
    local window = {
        Title = config.Title or "GlassLib UI",
        Tabs = {},
        CurrentTab = nil,
        Minimized = false
    }
    
    -- ScreenGui Principal
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "GlassLib_UI"
    screenGui.ResetOnSpawn = false
    screenGui.Parent = PlayerGui
    window.ScreenGui = screenGui

    -- Ombre / Flou arrière plan artificiel
    local mainFrame = Instance.new("Frame")
    mainFrame.Name = "MainFrame"
    mainFrame.Size = UDim2.new(0, 600, 0, 400)
    mainFrame.Position = UDim2.new(0.5, -300, 0.5, -200)
    mainFrame.BackgroundColor3 = THEME.Background
    mainFrame.BackgroundTransparency = 1 -- Commencer invisible pour le fade in
    mainFrame.ClipsDescendants = true
    mainFrame.Parent = screenGui
    window.MainFrame = mainFrame

    -- Arrondi Apple
    local uiCorner = Instance.new("UICorner")
    uiCorner.CornerRadius = UDim.new(0, 16)
    uiCorner.Parent = mainFrame

    -- Effet de bordure brillante (Effet verre)
    local uiStroke = Instance.new("UIStroke")
    uiStroke.Color = THEME.GlassBorder
    uiStroke.Transparency = 1
    uiStroke.Thickness = 1.2
    uiStroke.Parent = mainFrame

    -- Barre supérieure (Top Bar)
    local topBar = Instance.new("Frame")
    topBar.Name = "TopBar"
    topBar.Size = UDim2.new(1, 0, 0, 45)
    topBar.BackgroundTransparency = 1
    topBar.Parent = mainFrame

    local titleLabel = Instance.new("TextLabel")
    titleLabel.Text = window.Title
    titleLabel.Size = UDim2.new(1, -60, 1, 0)
    titleLabel.Position = UDim2.new(0, 20, 0, 0)
    titleLabel.Font = THEME.Font
    titleLabel.TextSize = 18
    titleLabel.TextColor3 = THEME.Text
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel.BackgroundTransparency = 1
    titleLabel.TextTransparency = 1
    titleLabel.Parent = topBar

    -- Conteneur des Onglets (Barre Horizontale supérieure, style Apple)
    local tabBar = Instance.new("Frame")
    tabBar.Name = "TabBar"
    tabBar.Size = UDim2.new(1, -40, 0, 35)
    tabBar.Position = UDim2.new(0, 20, 0, 45)
    tabBar.BackgroundTransparency = 1
    tabBar.Parent = mainFrame

    local tabLayout = Instance.new("UIListLayout")
    tabLayout.FillDirection = Enum.FillDirection.Horizontal
    tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
    tabLayout.Padding = UDim.new(0, 15)
    tabLayout.Parent = tabBar

    -- Conteneur des Pages (Contenu des Onglets)
    local container = Instance.new("Frame")
    container.Name = "Container"
    container.Size = UDim2.new(1, -40, 1, -100)
    container.Position = UDim2.new(0, 20, 0, 90)
    container.BackgroundTransparency = 1
    container.ClipsDescendants = true
    container.Parent = mainFrame
    window.Container = container

    -- Sauvegarde de la structure pour les méthodes de fenêtres
    self.Window = window
    
    -- Système de Drag (Glisser la fenêtre) intégré
    local dragging, dragInput, dragStart, startPos
    topBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            dragStart = input.Position
            startPos = mainFrame.Position
        end
    end)
    topBar.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = false
        end
    end)
    game:GetService("UserInputService").InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement and dragging then
            local delta = input.Position - dragStart
            mainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)

    -- Permet le chaînage d'onglets : `local Tab = Window:MakeTab(...)`
    local windowMeta = {
        MakeTab = function(_, tabConfig) return GlassLib:MakeTab(tabConfig) end
    }
    setmetatable(window, {__index = windowMeta})

    return window
end

-- Création d'un Onglet (Tab)
function GlassLib:MakeTab(config)
    local window = self.Window
    local tab = {
        Name = config.Name or "Tab",
        Order = #window.Tabs + 1,
        Elements = {}
    }

    -- Bouton de l'onglet dans la barre supérieure
    local tabButton = Instance.new("TextButton")
    tabButton.Size = UDim2.new(0, 100, 1, 0)
    tabButton.BackgroundTransparency = 1
    tabButton.Text = tab.Name
    tabButton.Font = THEME.Font
    tabButton.TextSize = 14
    tabButton.TextColor3 = THEME.TextDim
    tabButton.Parent = window.MainFrame.TabBar

    -- Ligne indicatrice sous l'onglet actif
    local line = Instance.new("Frame")
    line.Size = UDim2.new(1, 0, 0, 2)
    line.Position = UDim2.new(0, 0, 1, -2)
    line.BackgroundColor3 = THEME.Accent
    line.BackgroundTransparency = 1
    line.Parent = tabButton

    -- Conteneur défilant pour les éléments de cet onglet (La Page)
    local page = Instance.new("ScrollingFrame")
    page.Size = UDim2.new(1, 0, 1, 0)
    page.Position = UDim2.new(1.5, 0, 0, 0) -- Position initiale hors-champ à droite
    page.BackgroundTransparency = 1
    page.ScrollBarThickness = 2
    page.ScrollBarImageColor3 = THEME.Accent
    page.Visible = false
    page.Parent = window.Container

    local pageLayout = Instance.new("UIListLayout")
    pageLayout.SortOrder = Enum.SortOrder.LayoutOrder
    pageLayout.Padding = UDim.new(0, 10)
    pageLayout.Parent = page

    tab.Page = page

    -- Logique de transition fluide et directionnelle des onglets
    tabButton.MouseButton1Click:Connect(function()
        if window.CurrentTab == tab then return end

        local oldTab = window.CurrentTab
        window.CurrentTab = tab

        -- Déterminer la direction du mouvement (gauche ou droite)
        local comingFromRight = true
        if oldTab and tab.Order < oldTab.Order then
            comingFromRight = false
        end

        -- Désactiver l'ancien onglet avec effet de balayage
        if oldTab then
            tween(oldTab.Button, TweenInfo.new(0.3), {TextColor3 = THEME.TextDim})
            tween(oldTab.Line, TweenInfo.new(0.3), {BackgroundTransparency = 1})
            
            local targetPos = comingFromRight and UDim2.new(-1.5, 0, 0, 0) or UDim2.new(1.5, 0, 0, 0)
            local t = tween(oldTab.Page, TweenInfo.new(0.4, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out), {Position = targetPos})
            t.Completed:Connect(function() oldTab.Page.Visible = false end)
        end

        -- Activer le nouvel onglet
        tab.Page.Visible = true
        tab.Page.Position = comingFromRight and UDim2.new(1.5, 0, 0, 0) or UDim2.new(-1.5, 0, 0, 0)
        
        tween(tabButton, TweenInfo.new(0.3), {TextColor3 = THEME.Text})
        tween(line, TweenInfo.new(0.3), {BackgroundTransparency = 0})
        tween(page, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Position = UDim2.new(0, 0, 0, 0)})
    end)

    tab.Button = tabButton
    tab.Line = line
    table.insert(window.Tabs, tab)

    -- Définir automatiquement le premier onglet créé comme actif
    if #window.Tabs == 1 then
        window.CurrentTab = tab
        tabButton.TextColor3 = THEME.Text
        line.BackgroundTransparency = 0
        page.Position = UDim2.new(0, 0, 0, 0)
        page.Visible = true
    end

    -- Injection des méthodes d'éléments requis dans l'onglet
    local tabMeta = {
        AddSection = function(_, c) return GlassLib:AddSection(tab, c) end,
        AddLabel = function(_, t) return GlassLib:AddLabel(tab, t) end,
        AddParagraph = function(_, tit, con) return GlassLib:AddParagraph(tab, tit, con) end,
        AddButton = function(_, c) return GlassLib:AddButton(tab, c) end,
        AddToggle = function(_, c) return GlassLib:AddToggle(tab, c) end,
        AddSlider = function(_, c) return GlassLib:AddSlider(tab, c) end,
        AddDropdown = function(_, c) return GlassLib:AddDropdown(tab, c) end,
        AddTextbox = function(_, c) return GlassLib:AddTextbox(tab, c) end,
        AddColorpicker = function(_, c) return GlassLib:AddColorpicker(tab, c) end,
    }
    setmetatable(tab, {__index = tabMeta})

    return tab
end

-- Base pour générer un composant UI standardisé (Look Glass)
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

    game:GetService("UserInputService").InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            setFromMouse(input.Position.X)
        end
    end)

    game:GetService("UserInputService").InputEnded:Connect(function(input)
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
    game:GetService("UserInputService").InputEnded:Connect(function(input)
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

    game:GetService("UserInputService").InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement then
            local mouse = game:GetService("UserInputService"):GetMouseLocation()
            if draggingSV then
                updateSV(mouse.X, mouse.Y - 36) -- Compensation topbar Roblox standard
            elseif draggingHue then
                updateHue(mouse.Y - 36)
            end
        end
    end)

    game:GetService("UserInputService").InputEnded:Connect(function(input)
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


-- Notification System
function GlassLib:MakeNotification(config)
    local title = config.Title or "Notification"
    local content = config.Content or "Message body."
    local duration = config.Duration or 5

    -- Vérifier ou créer le conteneur de notifications
    local notifContainer = PlayerGui:FindFirstChild("GlassLib_Notifs")
    if not notifContainer then
        notifContainer = Instance.new("ScreenGui")
        notifContainer.Name = "GlassLib_Notifs"
        notifContainer.Parent = PlayerGui

        local layout = Instance.new("UIListLayout")
        layout.FillDirection = Enum.FillDirection.Vertical
        layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
        layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
        layout.SortOrder = Enum.SortOrder.LayoutOrder
        layout.Padding = UDim.new(0, 10)
        layout.Parent = notifContainer

        local padding = Instance.new("UIPadding")
        padding.PaddingBottom = UDim.new(0, 20)
        padding.PaddingRight = UDim.new(0, 20)
        padding.Parent = notifContainer
    end

    local card = Instance.new("Frame")
    card.Size = UDim2.new(0, 260, 0, 65)
    card.BackgroundColor3 = THEME.Background
    card.BackgroundTransparency = THEME.BackgroundTrans
    card.Position = UDim2.new(1, 300, 0, 0) -- Spawn hors écran à droite
    card.Parent = notifContainer
    Instance.new("UICorner", card).CornerRadius = UDim.new(0, 12)

    local stroke = Instance.new("UIStroke")
    stroke.Color = THEME.GlassBorder
    stroke.Transparency = THEME.BorderTrans
    stroke.Parent = card

    local tLabel = Instance.new("TextLabel")
    tLabel.Size = UDim2.new(1, -20, 0, 22)
    tLabel.Position = UDim2.new(0, 12, 0, 6)
    tLabel.Text = title
    tLabel.Font = THEME.Font
    tLabel.TextSize = 13
    tLabel.TextColor3 = THEME.Accent
    tLabel.TextXAlignment = Enum.TextXAlignment.Left
    tLabel.BackgroundTransparency = 1
    tLabel.Parent = card

    local cLabel = Instance.new("TextLabel")
    cLabel.Size = UDim2.new(1, -20, 0, 30)
    cLabel.Position = UDim2.new(0, 12, 0, 26)
    cLabel.Text = content
    cLabel.Font = THEME.Font
    cLabel.TextSize = 12
    cLabel.TextColor3 = THEME.Text
    cLabel.TextXAlignment = Enum.TextXAlignment.Left
    cLabel.TextYAlignment = Enum.TextYAlignment.Top
    cLabel.TextWrapped = true
    cLabel.BackgroundTransparency = 1
    cLabel.Parent = card

    -- Animation Slide-In
    tween(card, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Position = UDim2.new(0, 0, 0, 0)})

    task.delay(duration, function()
        local t = tween(card, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {BackgroundTransparency = 1, Size = UDim2.new(0,0,0,0)})
        t.Completed:Connect(function() card:Destroy() end)
    end)
end

-- Toggle Minimize/Maximize (Ouvre / Ferme le menu de manière élastique)
function GlassLib:ToggleMinimize()
    if not self.Window then return end
    local window = self.Window
    window.Minimized = not window.Minimized

    if window.Minimized then
        -- Animation fermeture : réduit vers le haut
        tween(window.MainFrame, TweenInfo.new(0.4, Enum.EasingStyle.Quart, Enum.EasingDirection.In), {Size = UDim2.new(0, 600, 0, 45)})
        window.Container.Visible = false
        window.MainFrame.TabBar.Visible = false
    else
        -- Animation ouverture élastique
        window.Container.Visible = true
        window.MainFrame.TabBar.Visible = true
        tween(window.MainFrame, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Size = UDim2.new(0, 600, 0, 400)})
    end
end

-- Initialisation de la librairie avec effets Fade-in de démarrage
function GlassLib:Init()
    if not self.Window then return end
    local mf = self.Window.MainFrame

    -- Rendre visible doucement au démarrage
    local stroke = mf:FindFirstChildOfClass("UIStroke")
    local title = mf.TopBar:FindFirstChildOfClass("TextLabel")
    tween(mf, TweenInfo.new(0.6, Enum.EasingStyle.Quad), {BackgroundTransparency = THEME.BackgroundTrans})

    if stroke then tween(stroke, TweenInfo.new(0.6), {Transparency = THEME.BorderTrans}) end
    if title then tween(title, TweenInfo.new(0.6), {TextTransparency = 0}) end

    -- Petit effet de rebond d'échelle à l'apparition globale
    mf.Size = UDim2.new(0, 550, 0, 370)
    tween(mf, TweenInfo.new(0.5, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out), {Size = UDim2.new(0, 600, 0, 400)})
end

--========================================================--
-- GlassLib V2 : visual shell override
-- Public Add* API remains unchanged.
--========================================================--

THEME.Background = Color3.fromRGB(16, 18, 23)
THEME.BackgroundTrans = 0.18
THEME.GlassBorder = Color3.fromRGB(255, 255, 255)
THEME.BorderTrans = 0.84
THEME.Accent = Color3.fromRGB(112, 168, 255)
THEME.Text = Color3.fromRGB(248, 249, 252)
THEME.TextDim = Color3.fromRGB(170, 178, 191)

local function _v2Destroy(obj)
    if obj then pcall(function() obj:Destroy() end) end
end

local function _v2Tween(obj, info, props)
    if not obj or not obj.Parent then return nil end
    local ok, tw = pcall(function()
        local t = TweenService:Create(obj, info, props)
        t:Play()
        return t
    end)
    return ok and tw or nil
end

local function _v2Corner(parent, radius)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, radius)
    c.Parent = parent
    return c
end

-- Base card update: affects existing Button/Toggle/Slider/Dropdown/Textbox visuals.
createBaseElement = function(parent, sizeY)
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(1, -8, 0, sizeY)
    frame.BackgroundColor3 = THEME.GlassBorder
    frame.BackgroundTransparency = 0.945
    frame.BorderSizePixel = 0
    frame.Parent = parent
    _v2Corner(frame, 12)

    local stroke = Instance.new("UIStroke")
    stroke.Color = THEME.GlassBorder
    stroke.Transparency = 0.92
    stroke.Thickness = 1
    stroke.Parent = frame

    local sheen = Instance.new("Frame")
    sheen.Size = UDim2.new(1, -2, 0, math.min(20, math.max(8, sizeY * 0.30)))
    sheen.Position = UDim2.fromOffset(1, 1)
    sheen.BackgroundColor3 = Color3.new(1, 1, 1)
    sheen.BackgroundTransparency = 0.985
    sheen.BorderSizePixel = 0
    sheen.Parent = frame
    _v2Corner(sheen, 10)

    return frame
end

function GlassLib:MakeWindow(config)
    config = config or {}

    _v2Destroy(PlayerGui:FindFirstChild("GlassLib_UI"))

    local window = {
        Title = config.Title or "GlassLib UI",
        Subtitle = config.Subtitle or "",
        Tabs = {},
        CurrentTab = nil,
        Minimized = false,
        Destroyed = false,
        Accent = config.AccentColor or THEME.Accent,
    }

    local gui = Instance.new("ScreenGui")
    gui.Name = "GlassLib_UI"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.Parent = PlayerGui
    window.ScreenGui = gui

    local shadow = Instance.new("Frame")
    shadow.Name = "Shadow"
    shadow.AnchorPoint = Vector2.new(0.5, 0.5)
    shadow.Size = UDim2.fromOffset(628, 468)
    shadow.Position = UDim2.fromScale(0.5, 0.5)
    shadow.BackgroundColor3 = Color3.new(0,0,0)
    shadow.BackgroundTransparency = 0.74
    shadow.BorderSizePixel = 0
    shadow.ZIndex = 0
    shadow.Parent = gui
    _v2Corner(shadow, 23)
    window.Shadow = shadow

    local main = Instance.new("Frame")
    main.Name = "MainFrame"
    main.AnchorPoint = Vector2.new(0.5,0.5)
    main.Size = UDim2.fromOffset(580,422)
    main.Position = UDim2.fromScale(0.5,0.5)
    main.BackgroundColor3 = THEME.Background
    main.BackgroundTransparency = 1
    main.BorderSizePixel = 0
    main.ClipsDescendants = true
    main.ZIndex = 1
    main.Parent = gui
    _v2Corner(main,19)
    window.MainFrame = main

    local stroke = Instance.new("UIStroke")
    stroke.Color = THEME.GlassBorder
    stroke.Transparency = 1
    stroke.Thickness = 1
    stroke.Parent = main

    local frosted = Instance.new("Frame")
    frosted.Size = UDim2.new(1,-2,1,-2)
    frosted.Position = UDim2.fromOffset(1,1)
    frosted.BackgroundColor3 = Color3.fromRGB(255,255,255)
    frosted.BackgroundTransparency = 0.976
    frosted.BorderSizePixel = 0
    frosted.ZIndex = 2
    frosted.Parent = main
    _v2Corner(frosted,18)

    local fg = Instance.new("UIGradient")
    fg.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0,Color3.fromRGB(255,255,255)),
        ColorSequenceKeypoint.new(0.5,Color3.fromRGB(255,255,255)),
        ColorSequenceKeypoint.new(1,Color3.fromRGB(190,205,230)),
    })
    fg.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0,0.93),
        NumberSequenceKeypoint.new(0.5,0.975),
        NumberSequenceKeypoint.new(1,0.93),
    })
    fg.Rotation = 90
    fg.Parent = frosted

    local shine = Instance.new("Frame")
    shine.Size = UDim2.new(1,-4,0,76)
    shine.Position = UDim2.fromOffset(2,2)
    shine.BackgroundColor3 = Color3.new(1,1,1)
    shine.BackgroundTransparency = 0.982
    shine.BorderSizePixel = 0
    shine.ZIndex = 3
    shine.Parent = main
    _v2Corner(shine,17)

    local top = Instance.new("Frame")
    top.Name = "TopBar"
    top.Size = UDim2.new(1,-20,0,58)
    top.Position = UDim2.fromOffset(10,7)
    top.BackgroundTransparency = 1
    top.ZIndex = 8
    top.Parent = main
    window.TopBar = top

    local title = Instance.new("TextLabel")
    title.Name = "Title"
    title.Size = UDim2.new(1,-220,0,24)
    title.Position = UDim2.fromOffset(14,8)
    title.BackgroundTransparency = 1
    title.Text = window.Title
    title.Font = Enum.Font.GothamBold
    title.TextSize = 17
    title.TextColor3 = THEME.Text
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.TextTransparency = 1
    title.Parent = top

    local subtitle = Instance.new("TextLabel")
    subtitle.Name = "Subtitle"
    subtitle.Size = UDim2.new(1,-220,0,16)
    subtitle.Position = UDim2.fromOffset(14,32)
    subtitle.BackgroundTransparency = 1
    subtitle.Text = window.Subtitle
    subtitle.Font = THEME.Font
    subtitle.TextSize = 10
    subtitle.TextColor3 = THEME.TextDim
    subtitle.TextXAlignment = Enum.TextXAlignment.Left
    subtitle.TextTransparency = 1
    subtitle.Parent = top

    local profile = Instance.new("Frame")
    profile.Size = UDim2.fromOffset(154,40)
    profile.AnchorPoint = Vector2.new(1,0)
    profile.Position = UDim2.new(1,-72,0,7)
    profile.BackgroundColor3 = Color3.new(1,1,1)
    profile.BackgroundTransparency = 0.975
    profile.BorderSizePixel = 0
    profile.ZIndex = 9
    profile.Parent = top
    _v2Corner(profile,12)

    local profileStroke = Instance.new("UIStroke")
    profileStroke.Color = Color3.new(1,1,1)
    profileStroke.Transparency = 0.94
    profileStroke.Parent = profile

    local avatar = Instance.new("ImageLabel")
    avatar.Size = UDim2.fromOffset(30,30)
    avatar.Position = UDim2.fromOffset(5,5)
    avatar.BackgroundTransparency = 1
    avatar.ZIndex = 10
    avatar.Parent = profile
    _v2Corner(avatar,9)

    local displayName = Instance.new("TextLabel")
    displayName.Size = UDim2.new(1,-43,0,16)
    displayName.Position = UDim2.fromOffset(40,5)
    displayName.BackgroundTransparency = 1
    displayName.Text = LocalPlayer.DisplayName
    displayName.Font = Enum.Font.GothamBold
    displayName.TextSize = 10
    displayName.TextColor3 = THEME.Text
    displayName.TextXAlignment = Enum.TextXAlignment.Left
    displayName.TextTruncate = Enum.TextTruncate.AtEnd
    displayName.Parent = profile

    local userName = Instance.new("TextLabel")
    userName.Size = UDim2.new(1,-43,0,14)
    userName.Position = UDim2.fromOffset(40,21)
    userName.BackgroundTransparency = 1
    userName.Text = "@" .. LocalPlayer.Name
    userName.Font = THEME.Font
    userName.TextSize = 9
    userName.TextColor3 = THEME.TextDim
    userName.TextXAlignment = Enum.TextXAlignment.Left
    userName.TextTruncate = Enum.TextTruncate.AtEnd
    userName.Parent = profile

    task.spawn(function()
        local ok, image = pcall(function()
            return Players:GetUserThumbnailAsync(
                LocalPlayer.UserId,
                Enum.ThumbnailType.HeadShot,
                Enum.ThumbnailSize.Size100x100
            )
        end)
        if ok and image and avatar.Parent then avatar.Image = image end
    end)

    local function makeControl(name,text,offset,color)
        local b=Instance.new("TextButton")
        b.Name=name
        b.Size=UDim2.fromOffset(27,27)
        b.AnchorPoint=Vector2.new(1,0)
        b.Position=UDim2.new(1,offset,0,13)
        b.BackgroundColor3=Color3.new(1,1,1)
        b.BackgroundTransparency=.975
        b.BorderSizePixel=0
        b.AutoButtonColor=false
        b.Text=text
        b.Font=Enum.Font.GothamBold
        b.TextSize=14
        b.TextColor3=color or THEME.TextDim
        b.ZIndex=12
        b.Parent=top
        _v2Corner(b,9)
        b.MouseEnter:Connect(function()
            _v2Tween(b,TweenInfo.new(.16,Enum.EasingStyle.Quint,Enum.EasingDirection.Out),{
                BackgroundTransparency=.90,
                TextColor3=THEME.Text
            })
        end)
        b.MouseLeave:Connect(function()
            _v2Tween(b,TweenInfo.new(.18,Enum.EasingStyle.Quint,Enum.EasingDirection.InOut),{
                BackgroundTransparency=.975,
                TextColor3=color or THEME.TextDim
            })
        end)
        return b
    end

    local minimize=makeControl("Minimize","−",-43)
    local close=makeControl("Close","×",-8,Color3.fromRGB(255,125,140))
    minimize.MouseButton1Click:Connect(function() self:ToggleMinimize() end)
    close.MouseButton1Click:Connect(function() self:Destroy() end)

    local tabBar=Instance.new("Frame")
    tabBar.Name="TabBar"
    tabBar.Size=UDim2.new(1,-24,0,40)
    tabBar.Position=UDim2.fromOffset(12,67)
    tabBar.BackgroundColor3=Color3.new(1,1,1)
    tabBar.BackgroundTransparency=.972
    tabBar.BorderSizePixel=0
    tabBar.ClipsDescendants=true
    tabBar.ZIndex=7
    tabBar.Parent=main
    _v2Corner(tabBar,13)

    local barStroke=Instance.new("UIStroke")
    barStroke.Color=Color3.new(1,1,1)
    barStroke.Transparency=.95
    barStroke.Parent=tabBar

    local pad=Instance.new("UIPadding")
    pad.PaddingLeft=UDim.new(0,4)
    pad.PaddingRight=UDim.new(0,4)
    pad.PaddingTop=UDim.new(0,3)
    pad.PaddingBottom=UDim.new(0,3)
    pad.Parent=tabBar

    local layout=Instance.new("UIListLayout")
    layout.FillDirection=Enum.FillDirection.Horizontal
    layout.VerticalAlignment=Enum.VerticalAlignment.Center
    layout.Padding=UDim.new(0,3)
    layout.Parent=tabBar

    local liquid=Instance.new("Frame")
    liquid.Name="LiquidIndicator"
    liquid.Size=UDim2.fromOffset(96,34)
    liquid.Position=UDim2.fromOffset(4,3)
    liquid.BackgroundColor3=window.Accent
    liquid.BackgroundTransparency=.84
    liquid.BorderSizePixel=0
    liquid.ZIndex=7
    liquid.Parent=tabBar
    _v2Corner(liquid,12)

    local liquidStroke=Instance.new("UIStroke")
    liquidStroke.Color=Color3.fromRGB(190,220,255)
    liquidStroke.Transparency=.60
    liquidStroke.Parent=liquid

    local content=Instance.new("Frame")
    content.Name="Container"
    content.Size=UDim2.new(1,-24,1,-116)
    content.Position=UDim2.fromOffset(12,112)
    content.BackgroundTransparency=1
    content.BorderSizePixel=0
    content.ClipsDescendants=true
    content.ZIndex=4
    content.Parent=main

    window.TabBar=tabBar
    window.Container=content
    window.LiquidIndicator=liquid
    window.Profile=profile

    local dragging=false
    local dragStart,startPos
    top.InputBegan:Connect(function(input)
        if input.UserInputType==Enum.UserInputType.MouseButton1 then
            dragging=true
            dragStart=input.Position
            startPos=main.Position
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType==Enum.UserInputType.MouseButton1 then dragging=false end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and input.UserInputType==Enum.UserInputType.MouseMovement then
            local d=input.Position-dragStart
            local pos=UDim2.new(startPos.X.Scale,startPos.X.Offset+d.X,startPos.Y.Scale,startPos.Y.Offset+d.Y)
            main.Position=pos
            shadow.Position=pos
        end
    end)

    self.Window=window
    setmetatable(window,{__index={MakeTab=function(_,tabConfig) return GlassLib:MakeTab(tabConfig) end}})
    return window
end

function GlassLib:MakeTab(config)
    config=config or {}
    local window=self.Window
    assert(window,"GlassLib:MakeWindow must be called before MakeTab")

    local tab={Name=config.Name or "Tab",Order=#window.Tabs+1,Elements={}}

    local button=Instance.new("TextButton")
    button.Name="TabButton"
    button.Size=UDim2.fromOffset(96,34)
    button.BackgroundTransparency=1
    button.BorderSizePixel=0
    button.AutoButtonColor=false
    button.Text=tab.Name
    button.Font=THEME.Font
    button.TextSize=10
    button.TextColor3=THEME.TextDim
    button.LayoutOrder=tab.Order
    button.ZIndex=10
    button.Parent=window.TabBar

    local page=Instance.new("ScrollingFrame")
    page.Name="Page"
    page.Size=UDim2.fromScale(1,1)
    page.Position=UDim2.fromScale(1.06,0)
    page.BackgroundTransparency=1
    page.BorderSizePixel=0
    page.ScrollBarThickness=3
    page.ScrollBarImageColor3=window.Accent
    page.ScrollBarImageTransparency=.5
    page.AutomaticCanvasSize=Enum.AutomaticSize.Y
    page.Visible=false
    page.ZIndex=5
    page.Parent=window.Container

    local pp=Instance.new("UIPadding")
    pp.PaddingTop=UDim.new(0,3)
    pp.PaddingBottom=UDim.new(0,12)
    pp.PaddingLeft=UDim.new(0,2)
    pp.PaddingRight=UDim.new(0,8)
    pp.Parent=page

    local pl=Instance.new("UIListLayout")
    pl.SortOrder=Enum.SortOrder.LayoutOrder
    pl.Padding=UDim.new(0,8)
    pl.Parent=page

    tab.Button=button
    tab.Page=page
    table.insert(window.Tabs,tab)

    local function moveIndicator(instant)
        local x=button.AbsolutePosition.X-window.TabBar.AbsolutePosition.X
        local props={Position=UDim2.fromOffset(x,3),Size=UDim2.fromOffset(button.AbsoluteSize.X,34)}
        if instant then
            window.LiquidIndicator.Position=props.Position
            window.LiquidIndicator.Size=props.Size
        else
            _v2Tween(window.LiquidIndicator,TweenInfo.new(.48,Enum.EasingStyle.Quint,Enum.EasingDirection.InOut),props)
        end
    end

    local function select()
        if window.CurrentTab==tab then return end
        local old=window.CurrentTab
        local dir=(old and tab.Order<old.Order) and -1 or 1
        window.CurrentTab=tab

        if old then
            _v2Tween(old.Button,TweenInfo.new(.2,Enum.EasingStyle.Quad,Enum.EasingDirection.InOut),{TextColor3=THEME.TextDim})
            _v2Tween(old.Page,TweenInfo.new(.30,Enum.EasingStyle.Quint,Enum.EasingDirection.InOut),{Position=UDim2.new(-dir*1.06,0,0,0)})
        end

        page.Visible=true
        page.Position=UDim2.new(dir*1.06,0,0,0)
        _v2Tween(button,TweenInfo.new(.2,Enum.EasingStyle.Quad,Enum.EasingDirection.InOut),{TextColor3=THEME.Text})
        moveIndicator(false)

        -- Quint InOut: acceleration at start, deceleration at end.
        _v2Tween(page,TweenInfo.new(.44,Enum.EasingStyle.Quint,Enum.EasingDirection.InOut),{Position=UDim2.fromScale(0,0)})

        local original=button.Size
        button.Size=UDim2.new(original.X.Scale,original.X.Offset+4,original.Y.Scale,original.Y.Offset)
        _v2Tween(button,TweenInfo.new(.34,Enum.EasingStyle.Quint,Enum.EasingDirection.Out),{Size=original})

        if old then
            task.delay(.31,function()
                if old~=window.CurrentTab then old.Page.Visible=false end
            end)
        end
    end

    button.MouseButton1Click:Connect(select)
    button.MouseEnter:Connect(function()
        if window.CurrentTab~=tab then
            _v2Tween(button,TweenInfo.new(.14,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{TextColor3=THEME.Text})
        end
    end)
    button.MouseLeave:Connect(function()
        if window.CurrentTab~=tab then
            _v2Tween(button,TweenInfo.new(.16,Enum.EasingStyle.Quint,Enum.EasingDirection.InOut),{TextColor3=THEME.TextDim})
        end
    end)

    if #window.Tabs==1 then
        window.CurrentTab=tab
        page.Visible=true
        page.Position=UDim2.fromScale(0,0)
        button.TextColor3=THEME.Text
        task.defer(function() moveIndicator(true) end)
    end

    setmetatable(tab,{__index={
        AddSection=function(_,c) return GlassLib:AddSection(tab,c) end,
        AddLabel=function(_,t) return GlassLib:AddLabel(tab,t) end,
        AddParagraph=function(_,a,b) return GlassLib:AddParagraph(tab,a,b) end,
        AddButton=function(_,c) return GlassLib:AddButton(tab,c) end,
        AddToggle=function(_,c) return GlassLib:AddToggle(tab,c) end,
        AddSlider=function(_,c) return GlassLib:AddSlider(tab,c) end,
        AddDropdown=function(_,c) return GlassLib:AddDropdown(tab,c) end,
        AddTextbox=function(_,c) return GlassLib:AddTextbox(tab,c) end,
        AddColorpicker=function(_,c) return GlassLib:AddColorpicker(tab,c) end,
    }})
    return tab
end

-- Colorpicker stays functionally identical; only its shell is refreshed.
local _oldAddColorpicker = GlassLib.AddColorpicker
function GlassLib:AddColorpicker(tab, config)
    local api=_oldAddColorpicker(self,tab,config)
    local base=api and api.Instance
    if base then
        local popup=base:FindFirstChild("ColorpickerPopup")
        if popup then
            popup.BackgroundColor3=Color3.fromRGB(25,29,37)
            popup.BackgroundTransparency=.08
            local stroke=popup:FindFirstChildOfClass("UIStroke")
            if stroke then
                stroke.Color=THEME.GlassBorder
                stroke.Transparency=.88
                stroke.Thickness=1
            end
            for _,obj in ipairs(popup:GetDescendants()) do
                if obj:IsA("UICorner") then
                    obj.CornerRadius=UDim.new(0,10)
                end
            end
        end
    end
    return api
end

local _oldMakeNotification = GlassLib.MakeNotification
function GlassLib:MakeNotification(config)
    -- Keep existing notification API, but soften the theme.
    return _oldMakeNotification(self,config)
end

function GlassLib:ToggleMinimize()
    if not self.Window then return end
    local w=self.Window
    w.Minimized=not w.Minimized

    if w.Minimized then
        w.Container.Visible=false
        w.TabBar.Visible=false
        w.LiquidIndicator.Visible=false
        _v2Tween(w.MainFrame,TweenInfo.new(.34,Enum.EasingStyle.Quint,Enum.EasingDirection.InOut),{Size=UDim2.fromOffset(600,76)})
        _v2Tween(w.Shadow,TweenInfo.new(.30,Enum.EasingStyle.Quint,Enum.EasingDirection.InOut),{Size=UDim2.fromOffset(618,92)})
    else
        w.Container.Visible=true
        w.TabBar.Visible=true
        w.LiquidIndicator.Visible=true
        _v2Tween(w.MainFrame,TweenInfo.new(.42,Enum.EasingStyle.Quint,Enum.EasingDirection.InOut),{Size=UDim2.fromOffset(600,440)})
        _v2Tween(w.Shadow,TweenInfo.new(.42,Enum.EasingStyle.Quint,Enum.EasingDirection.InOut),{Size=UDim2.fromOffset(628,468)})
    end
end

function GlassLib:Destroy()
    if not self.Window or self.Window.Destroyed then return end
    local w=self.Window
    w.Destroyed=true
    local t=_v2Tween(w.MainFrame,TweenInfo.new(.28,Enum.EasingStyle.Quint,Enum.EasingDirection.InOut),{
        Size=UDim2.fromOffset(555,405),
        BackgroundTransparency=1
    })
    _v2Tween(w.Shadow,TweenInfo.new(.24,Enum.EasingStyle.Quint,Enum.EasingDirection.InOut),{
        Size=UDim2.fromOffset(580,420),
        BackgroundTransparency=1
    })
    if t then
        t.Completed:Connect(function()
            _v2Destroy(w.ScreenGui)
            _v2Destroy(w.Shadow)
        end)
    else
        _v2Destroy(w.ScreenGui)
        _v2Destroy(w.Shadow)
    end
end

function GlassLib:Init()
    if not self.Window then return end
    local w=self.Window
    local main=w.MainFrame
    local shadow=w.Shadow

    main.BackgroundTransparency=1
    shadow.BackgroundTransparency=1

    local title=w.TopBar:FindFirstChild("Title")
    local subtitle=w.TopBar:FindFirstChild("Subtitle")
    local profile=w.Profile

    if title then title.TextTransparency=1 end
    if subtitle then subtitle.TextTransparency=1 end
    if profile then profile.BackgroundTransparency=1 end

    _v2Tween(shadow,TweenInfo.new(.56,Enum.EasingStyle.Quint,Enum.EasingDirection.Out),{BackgroundTransparency=.74})
    _v2Tween(main,TweenInfo.new(.65,Enum.EasingStyle.Quint,Enum.EasingDirection.InOut),{
        Size=UDim2.fromOffset(600,440),
        BackgroundTransparency=.18
    })

    if title then
        _v2Tween(title,TweenInfo.new(.42,Enum.EasingStyle.Quint,Enum.EasingDirection.Out),{TextTransparency=0})
    end
    if subtitle then
        _v2Tween(subtitle,TweenInfo.new(.50,Enum.EasingStyle.Quint,Enum.EasingDirection.Out),{TextTransparency=0})
    end
    if profile then
        _v2Tween(profile,TweenInfo.new(.50,Enum.EasingStyle.Quint,Enum.EasingDirection.Out),{BackgroundTransparency=.975})
    end

    task.defer(function()
        if w.CurrentTab and w.LiquidIndicator then
            local b=w.CurrentTab.Button
            local x=b.AbsolutePosition.X-w.TabBar.AbsolutePosition.X
            w.LiquidIndicator.Position=UDim2.fromOffset(x,3)
            w.LiquidIndicator.Size=UDim2.fromOffset(b.AbsoluteSize.X,34)
        end
    end)
end

return GlassLib
