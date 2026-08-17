local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

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

function GlassLib:AddSection(tab, config)
    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, 0, 0, 25)
    label.Text = string.upper(config.Name or "Section")
    label.Font = THEME.Font
    label.TextSize = 11
    label.TextColor3 = THEME.Accent
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.BackgroundTransparency = 1
    label.Parent = tab.Page
    return label
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
    return label
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
    return base
end

function GlassLib:AddButton(tab, config)
    local base = createBaseElement(tab.Page, 35)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, 0, 1, 0)
    btn.BackgroundTransparency = 1
    btn.Text = config.Name or "Click Me"
    btn.Font = THEME.Font
    btn.TextColor3 = THEME.Text
    btn.TextSize = 14
    btn.Parent = base

    btn.MouseButton1Click:Connect(function()
        -- Effet de rebond discret au clic
        base.Size = UDim2.new(1, -12, 0, 33)
        tween(base, TweenInfo.new(0.2, Enum.EasingStyle.Elastic), {Size = UDim2.new(1, -6, 0, 35)})
        if config.Callback then config.Callback() end
    end)
    return btn
end

function GlassLib:AddToggle(tab, config)
    local base = createBaseElement(tab.Page, 35)
    local state = config.Default or false
    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -60, 1, 0)
    label.Position = UDim2.new(0, 10, 0, 0)
    label.Text = config.Name or "Toggle"
    label.Font = THEME.Font
    label.TextColor3 = THEME.Text
    label.TextSize = 14
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.BackgroundTransparency = 1
    label.Parent = base

    -- Structure Switch Apple
    local switch = Instance.new("Frame")
    switch.Size = UDim2.new(0, 40, 0, 20)
    switch.Position = UDim2.new(1, -50, 0.5, -10)
    switch.BackgroundColor3 = state and THEME.Accent or Color3.fromRGB(80, 80, 80)
    switch.Parent = base
    Instance.new("UICorner", switch).CornerRadius = UDim.new(1, 0)

    local circle = Instance.new("Frame")
    circle.Size = UDim2.new(0, 16, 0, 16)
    circle.Position = state and UDim2.new(1, -18, 0.5, -8) or UDim2.new(0, 2, 0.5, -8)
    circle.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    circle.Parent = switch
    Instance.new("UICorner", circle).CornerRadius = UDim.new(1, 0)

    local click = Instance.new("TextButton")
    click.Size = UDim2.new(1, 0, 1, 0)
    click.BackgroundTransparency = 1
    click.Text = ""
    click.Parent = base

    click.MouseButton1Click:Connect(function()
        state = not state
        local targetPos = state and UDim2.new(1, -18, 0.5, -8) or UDim2.new(0, 2, 0.5, -8)
        local targetColor = state and THEME.Accent or Color3.fromRGB(80, 80, 80)
        tween(circle, TweenInfo.new(0.25, Enum.EasingStyle.Back), {Position = targetPos})
        tween(switch, TweenInfo.new(0.2), {BackgroundColor3 = targetColor})
        if config.Callback then config.Callback(state) end
    end)
    return base
end

function GlassLib:AddSlider(tab, config)
    local base = createBaseElement(tab.Page, 45)
    local min = config.Min or 0
    local max = config.Max or 100
    local def = config.Default or min
    local currentVal = def
    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -100, 0, 20)
    label.Position = UDim2.new(0, 10, 0, 4)
    label.Text = config.Name or "Slider"
    label.Font = THEME.Font
    label.TextColor3 = THEME.Text
    label.TextSize = 14
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.BackgroundTransparency = 1
    label.Parent = base

    local valLabel = Instance.new("TextLabel")
    valLabel.Size = UDim2.new(0, 80, 0, 20)
    valLabel.Position = UDim2.new(1, -90, 0, 4)
    valLabel.Text = tostring(def)
    valLabel.Font = THEME.Font
    valLabel.TextColor3 = THEME.Accent
    valLabel.TextSize = 14
    valLabel.TextXAlignment = Enum.TextXAlignment.Right
    valLabel.BackgroundTransparency = 1
    valLabel.Parent = base

    local slideBar = Instance.new("Frame")
    slideBar.Size = UDim2.new(1, -20, 0, 6)
    slideBar.Position = UDim2.new(0, 10, 0, 30)
    slideBar.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
    slideBar.Parent = base
    Instance.new("UICorner", slideBar)

    local fill = Instance.new("Frame")
    local pct = (def - min) / (max - min)
    fill.Size = UDim2.new(pct, 0, 1, 0)
    fill.BackgroundColor3 = THEME.Accent
    fill.Parent = slideBar
    Instance.new("UICorner", fill)

    -- Logique du drag du curseur
    local active = false
    local function update(input)
        local xOffset = math.clamp(input.Position.X - slideBar.AbsolutePosition.X, 0, slideBar.AbsoluteSize.X)
        local ratio = xOffset / slideBar.AbsoluteSize.X
        local rawVal = min + (max - min) * ratio
        currentVal = math.floor(rawVal)
        valLabel.Text = tostring(currentVal)
        fill.Size = UDim2.new(ratio, 0, 1, 0)
        if config.Callback then config.Callback(currentVal) end
    end

    base.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then active = true update(input) end
    end)

    base.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then active = false end
    end)

    game:GetService("UserInputService").InputChanged:Connect(function(input)
        if active and input.UserInputType == Enum.UserInputType.MouseMovement then update(input) end
    end)
    return base
end

function GlassLib:AddDropdown(tab, config)
    local base = createBaseElement(tab.Page, 35)
    local open = false
    local options = config.Options or {}
    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -40, 1, 0)
    label.Position = UDim2.new(0, 10, 0, 0)
    label.Text = (config.Name or "Dropdown") .. " : " .. (config.Default or "None")
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

    -- Ajouter les options
    for _, opt in ipairs(options) do
        local oBtn = Instance.new("TextButton")
        oBtn.Size = UDim2.new(1, 0, 0, 25)
        oBtn.BackgroundColor3 = Color3.fromRGB(30, 45, 65)
        oBtn.BackgroundTransparency = 0.2
        oBtn.Text = opt
        oBtn.Font = THEME.Font
        oBtn.TextColor3 = THEME.TextDim
        oBtn.TextSize = 13
        oBtn.Parent = optContainer

        oBtn.MouseButton1Click:Connect(function()
            label.Text = (config.Name or "Dropdown") .. " : " .. opt
            open = false
            tween(base, TweenInfo.new(0.2), {Size = UDim2.new(1, -6, 0, 35)})
            tween(optContainer, TweenInfo.new(0.2), {Size = UDim2.new(1, 0, 0, 0)})
            arrow.Text = "▼"
            if config.Callback then config.Callback(opt) end
        end)
    end

    local click = Instance.new("TextButton")
    click.Size = UDim2.new(1, 0, 0, 35)
    click.BackgroundTransparency = 1
    click.Text = ""
    click.Parent = base

    click.MouseButton1Click:Connect(function()
        open = not open
        local targetSize = open and (35 + (#options * 25)) or 35
        local containerSize = open and (#options * 25) or 0
        arrow.Text = open and "▲" or "▼"
        tween(base, TweenInfo.new(0.25, Enum.EasingStyle.Quart), {Size = UDim2.new(1, -6, 0, targetSize)})
        tween(optContainer, TweenInfo.new(0.25, Enum.EasingStyle.Quart), {Size = UDim2.new(1, 0, 0, containerSize)})
    end)
    return base
end

function GlassLib:AddTextbox(tab, config)
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
    box.BackgroundColor3 = Color3.fromRGB(0,0,0)
    box.BackgroundTransparency = 0.6
    box.Text = config.Placeholder or "Type..."
    box.Font = THEME.Font
    box.TextColor3 = THEME.Text
    box.TextSize = 13
    box.ClearTextOnFocus = config.Clear or false
    box.Parent = base
    Instance.new("UICorner", box).CornerRadius = UDim.new(0, 6)

    box.FocusLost:Connect(function(enterPressed)
        if config.Callback then config.Callback(box.Text, enterPressed) end
    end)
    return base
end

function GlassLib:AddColorpicker(tab, config)
    local base = createBaseElement(tab.Page, 35)
    local currentCPColor = config.Default or Color3.fromRGB(255, 0, 0)
    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -60, 1, 0)
    label.Position = UDim2.new(0, 10, 0, 0)
    label.Text = config.Name or "Colorpicker"
    label.Font = THEME.Font
    label.TextColor3 = THEME.Text
    label.TextSize = 14
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.BackgroundTransparency = 1
    label.Parent = base

    local colorPreview = Instance.new("TextButton")
    colorPreview.Size = UDim2.new(0, 30, 0, 18)
    colorPreview.Position = UDim2.new(1, -40, 0.5, -9)
    colorPreview.BackgroundColor3 = currentCPColor
    colorPreview.Text = ""
    colorPreview.Parent = base
    Instance.new("UICorner", colorPreview).CornerRadius = UDim.new(0, 4)

    colorPreview.MouseButton1Click:Connect(function()
        -- Exemple simplifié : Alterne entre 3 couleurs Apple iconiques au clic
        local colors = {Color3.fromRGB(255, 59, 48), Color3.fromRGB(52, 199, 89), Color3.fromRGB(0, 122, 255)}
        local nextColor = colors[math.random(1, #colors)]
        currentCPColor = nextColor
        colorPreview.BackgroundColor3 = nextColor
        if config.Callback then config.Callback(nextColor) end
    end)
    return base
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

return GlassLib
