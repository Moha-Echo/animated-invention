local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")


local GlassLib = {}
GlassLib.__index = GlassLib
GlassLib.Flags = {}

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

--========================================================--
-- GlassLib V3 : Liquid Glass shell
-- API Add* conservée.
--========================================================--

THEME.Background = Color3.fromRGB(13, 15, 20)
THEME.BackgroundTrans = 0.18
THEME.GlassBorder = Color3.fromRGB(255, 255, 255)
THEME.BorderTrans = 0.88
THEME.Accent = Color3.fromRGB(126, 174, 255)
THEME.Text = Color3.fromRGB(248, 249, 252)
THEME.TextDim = Color3.fromRGB(164, 172, 186)

local V3 = {
    NormalSize = UDim2.fromOffset(600, 440),
    MinimizedSize = UDim2.fromOffset(365, 108),
    NormalShadow = UDim2.fromOffset(628, 468),
    MinimizedShadow = UDim2.fromOffset(393, 136),
    NormalTopHeight = 58,
    MinimizedTopHeight = 102,
    Ease = Enum.EasingStyle.Quint,
}

local function v3Destroy(obj)
    if obj then
        pcall(function() obj:Destroy() end)
    end
end

local function v3Tween(obj, duration, direction, props)
    if not obj or not obj.Parent then
        return nil
    end

    local ok, tw = pcall(function()
        local info = TweenInfo.new(
            duration,
            V3.Ease,
            direction or Enum.EasingDirection.InOut
        )

        local t = TweenService:Create(obj, info, props)
        t:Play()
        return t
    end)

    return ok and tw or nil
end

local function v3Corner(parent, radius)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, radius)
    c.Parent = parent
    return c
end

local function v3Stroke(parent, color, transparency, thickness)
    local stroke = Instance.new("UIStroke")
    stroke.Color = color
    stroke.Transparency = transparency
    stroke.Thickness = thickness or 1
    stroke.Parent = parent
    return stroke
end

-- Les cartes des composants utilisent désormais le même langage visuel.
createBaseElement = function(parent, sizeY)
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(1, -8, 0, sizeY)
    frame.BackgroundColor3 = Color3.new(1, 1, 1)
    frame.BackgroundTransparency = 0.948
    frame.BorderSizePixel = 0
    frame.Active = true
    frame.Parent = parent

    v3Corner(frame, 12)
    v3Stroke(frame, Color3.new(1, 1, 1), 0.925, 1)

    local gloss = Instance.new("Frame")
    gloss.Name = "GlassHighlight"
    gloss.Size = UDim2.new(1, -2, 0, math.min(22, math.max(10, sizeY * 0.32)))
    gloss.Position = UDim2.fromOffset(1, 1)
    gloss.BackgroundColor3 = Color3.new(1, 1, 1)
    gloss.BackgroundTransparency = 0.985
    gloss.BorderSizePixel = 0
    gloss.Parent = frame
    gloss.ZIndex = frame.ZIndex
    v3Corner(gloss, 11)

    return frame
end

local function v3GuiParent()
    local ok, coreGui = pcall(function()
        return game:GetService("CoreGui")
    end)

    if ok and coreGui then
        return coreGui
    end

    return PlayerGui
end

local function v3ProfileCard(window, parent)
    local profile = Instance.new("Frame")
    profile.Name = "ProfileCard"
    profile.Size = UDim2.fromOffset(166, 42)
    profile.AnchorPoint = Vector2.new(0.5, 0)
    profile.Position = UDim2.new(0.5, 0, 0, 7)
    profile.BackgroundColor3 = Color3.new(1, 1, 1)
    profile.BackgroundTransparency = 0.973
    profile.BorderSizePixel = 0
    profile.ZIndex = 11
    profile.Parent = parent

    v3Corner(profile, 13)
    v3Stroke(profile, Color3.new(1, 1, 1), 0.93, 1)

    local avatar = Instance.new("ImageLabel")
    avatar.Name = "Avatar"
    avatar.Size = UDim2.fromOffset(32, 32)
    avatar.Position = UDim2.fromOffset(5, 5)
    avatar.BackgroundTransparency = 1
    avatar.ZIndex = 12
    avatar.Parent = profile
    v3Corner(avatar, 10)

    local avatarStroke = v3Stroke(
        avatar,
        Color3.new(1, 1, 1),
        0.80,
        1
    )

    local displayName = Instance.new("TextLabel")
    displayName.Name = "DisplayName"
    displayName.Size = UDim2.new(1, -48, 0, 16)
    displayName.Position = UDim2.fromOffset(43, 5)
    displayName.BackgroundTransparency = 1
    displayName.Text = LocalPlayer.DisplayName
    displayName.Font = Enum.Font.GothamBold
    displayName.TextSize = 10
    displayName.TextColor3 = THEME.Text
    displayName.TextXAlignment = Enum.TextXAlignment.Left
    displayName.TextTruncate = Enum.TextTruncate.AtEnd
    displayName.ZIndex = 12
    displayName.Parent = profile

    local username = Instance.new("TextLabel")
    username.Name = "Username"
    username.Size = UDim2.new(1, -48, 0, 14)
    username.Position = UDim2.fromOffset(43, 21)
    username.BackgroundTransparency = 1
    username.Text = "@" .. LocalPlayer.Name
    username.Font = THEME.Font
    username.TextSize = 9
    username.TextColor3 = THEME.TextDim
    username.TextXAlignment = Enum.TextXAlignment.Left
    username.TextTruncate = Enum.TextTruncate.AtEnd
    username.ZIndex = 12
    username.Parent = profile

    task.spawn(function()
        local ok, image = pcall(function()
            return Players:GetUserThumbnailAsync(
                LocalPlayer.UserId,
                Enum.ThumbnailType.HeadShot,
                Enum.ThumbnailSize.Size100x100
            )
        end)

        if ok and image and avatar.Parent then
            avatar.Image = image
        end
    end)

    window.Profile = profile
    return profile
end

-- Habillage V4 du Colorpicker : la logique HSV originale reste inchangée.
local GlassLib_AddColorpickerBase = GlassLib.AddColorpicker

function GlassLib:AddColorpicker(tab, config)
    local api = GlassLib_AddColorpickerBase(self, tab, config)
    local base = api and api.Instance

    if base then
        v3Stroke(base, Color3.new(1, 1, 1), 0.92, 1)

        local popup = base:FindFirstChild("ColorpickerPopup")
        if popup then
            popup.BackgroundColor3 = Color3.fromRGB(21, 24, 31)
            popup.BackgroundTransparency = 0.08
            v3Corner(popup, 12)

            local existingStroke = popup:FindFirstChildOfClass("UIStroke")
            if existingStroke then
                existingStroke.Color = Color3.new(1, 1, 1)
                existingStroke.Transparency = 0.89
            else
                v3Stroke(
                    popup,
                    Color3.new(1, 1, 1),
                    0.89,
                    1
                )
            end
        end
    end

    return api
end

--========================================================--
-- GlassLib V4 : shell interaction / tabs / minimize fixes
-- API des composants conservée.
--========================================================--

local V4 = {
    NormalSize = UDim2.fromOffset(600, 440),
    NormalShadow = UDim2.fromOffset(628, 468),

    MinimizedSize = UDim2.fromOffset(318, 94),
    MinimizedShadow = UDim2.fromOffset(344, 120),

    NormalTopHeight = 58,
    MinimizedTopHeight = 86,

    TopLeftMargin = 12,

    Ease = Enum.EasingStyle.Quint,
}

local function v4Tween(obj, duration, direction, props)
    if not obj or not obj.Parent then
        return nil
    end

    local ok, tw = pcall(function()
        local info = TweenInfo.new(
            duration,
            V4.Ease,
            direction or Enum.EasingDirection.InOut
        )

        local t = TweenService:Create(obj, info, props)
        t:Play()
        return t
    end)

    return ok and tw or nil
end

local function v4GuiParent()
    local ok, coreGui = pcall(function()
        return game:GetService("CoreGui")
    end)

    if ok and coreGui then
        local usable = pcall(function()
            local probe = Instance.new("Folder")
            probe.Name = "__GlassLibProbe"
            probe.Parent = coreGui
            probe:Destroy()
        end)

        if usable then
            return coreGui
        end
    end

    return PlayerGui
end

local function v4PointInside(guiObject, point)
    if not guiObject or not guiObject.Parent then
        return false
    end

    local pos = guiObject.AbsolutePosition
    local size = guiObject.AbsoluteSize

    return point.X >= pos.X
        and point.X <= pos.X + size.X
        and point.Y >= pos.Y
        and point.Y <= pos.Y + size.Y
end

local function v4ActivateControls(gui)
    if not gui then
        return
    end

    -- GlassLib ne verrouille jamais le pointeur Roblox via GuiButton.Modal.
    -- On conserve uniquement Active pour les contrôles UI.
    for _, obj in ipairs(gui:GetDescendants()) do
        if obj:IsA("GuiButton") or obj:IsA("TextBox") then
            pcall(function()
                obj.Active = true
            end)
        end
    end
end

local function v4ClampPosition(gui)
    if not gui or not gui.Parent then
        return
    end

    local camera = workspace.CurrentCamera
    if not camera then
        return
    end

    local viewport = camera.ViewportSize
    local size = gui.AbsoluteSize

    local x = math.clamp(
        gui.AbsolutePosition.X,
        0,
        math.max(0, viewport.X - size.X)
    )

    local y = math.clamp(
        gui.AbsolutePosition.Y,
        0,
        math.max(0, viewport.Y - size.Y)
    )

    local anchor = gui.AnchorPoint

    gui.Position = UDim2.fromOffset(
        x + size.X * anchor.X,
        y + size.Y * anchor.Y
    )
end

local function v4MinimizedPosition(main)
    local halfX = V4.MinimizedSize.X.Offset * 0.5
    local halfY = V4.MinimizedSize.Y.Offset * 0.5

    return UDim2.fromOffset(
        V4.TopLeftMargin + halfX,
        V4.TopLeftMargin + halfY
    )
end

local function v4SetTabColor(tab, active)
    if not tab or not tab.Button then
        return
    end

    v4Tween(
        tab.Button,
        0.18,
        Enum.EasingDirection.InOut,
        {
            TextColor3 = active
                and THEME.Text
                or THEME.TextDim
        }
    )
end

local function v4UpdateTabCanvas(window)
    if not window.TabScroller
        or not window.TabLayout
    then
        return
    end

    local contentWidth =
        window.TabLayout.AbsoluteContentSize.X + 10

    window.TabScroller.CanvasSize =
        UDim2.fromOffset(
            math.max(
                contentWidth,
                window.TabScroller.AbsoluteSize.X
            ),
            0
        )
end

local function v4PositionIndicator(window, instant)
    if not window
        or not window.CurrentTab
        or not window.LiquidIndicator
        or not window.TabOuter
        or not window.TabScroller
    then
        return
    end

    local button = window.CurrentTab.Button

    if not button
        or not button.Parent
    then
        return
    end

    local scrollerPos =
        window.TabScroller.AbsolutePosition

    local outerPos =
        window.TabOuter.AbsolutePosition

    local scrollX =
        window.TabScroller.CanvasPosition.X

    local x =
        button.AbsolutePosition.X
        - outerPos.X

    -- Conserver l'indicateur dans la fenêtre visible du tab bar.
    local targetWidth = math.max(
        44,
        button.AbsoluteSize.X
    )

    local position =
        UDim2.fromOffset(
            x + 4,
            3
        )

    local size =
        UDim2.fromOffset(
            targetWidth,
            34
        )

    if instant then
        window.LiquidIndicator.Position = position
        window.LiquidIndicator.Size = size
    else
        v4Tween(
            window.LiquidIndicator,
            0.50,
            Enum.EasingDirection.InOut,
            {
                Position = position,
                Size = size,
            }
        )
    end
end

local function v4ScrollTabIntoView(window, tab)
    if not window.TabScroller or not tab then
        return
    end

    local button = tab.Button
    if not button then
        return
    end

    task.defer(function()
        RunService.RenderStepped:Wait()

        local scroller = window.TabScroller
        local viewportLeft = scroller.AbsolutePosition.X
        local viewportRight =
            viewportLeft
            + scroller.AbsoluteSize.X

        local buttonLeft = button.AbsolutePosition.X
        local buttonRight =
            buttonLeft
            + button.AbsoluteSize.X

        local current = scroller.CanvasPosition.X

        if buttonLeft < viewportLeft then
            scroller.CanvasPosition = Vector2.new(
                math.max(
                    0,
                    current
                        - (viewportLeft - buttonLeft)
                        - 8
                ),
                0
            )
        elseif buttonRight > viewportRight then
            scroller.CanvasPosition = Vector2.new(
                current
                    + (buttonRight - viewportRight)
                    + 8,
                0
            )
        end

        v4PositionIndicator(window, true)
    end)
end

function GlassLib:MakeWindow(config)
    config = config or {}

    local parent = v4GuiParent()

    local existing = parent:FindFirstChild("GlassLib_UI")
    if existing then
        v3Destroy(existing)
    end

    local window = {
        Title = config.Title or "GlassLib UI",
        Subtitle = config.Subtitle or "",
        Tabs = {},
        CurrentTab = nil,
        Minimized = false,
        Destroyed = false,
        Accent = config.AccentColor or THEME.Accent,
        RestorePosition = nil,
        Connections = {},
    }

    local gui = Instance.new("ScreenGui")
    gui.Name = "GlassLib_UI"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Global

    pcall(function()
        gui.DisplayOrder = 2147483647
    end)

    gui.Parent = parent
    window.ScreenGui = gui

    local shadow = Instance.new("Frame")
    shadow.Name = "GlassShadow"
    shadow.AnchorPoint = Vector2.new(0.5, 0.5)
    shadow.Size = V4.NormalShadow
    shadow.Position = UDim2.fromScale(0.5, 0.5)
    shadow.BackgroundColor3 = Color3.new(0, 0, 0)
    shadow.BackgroundTransparency = 0.78
    shadow.BorderSizePixel = 0
    shadow.ZIndex = 0
    shadow.Parent = gui
    v3Corner(shadow, 24)
    window.Shadow = shadow

    local main = Instance.new("Frame")
    main.Name = "MainFrame"
    main.AnchorPoint = Vector2.new(0.5, 0.5)
    main.Size = V4.NormalSize
    main.Position = UDim2.fromScale(0.5, 0.5)
    main.BackgroundColor3 = THEME.Background
    main.BackgroundTransparency = 0.16
    main.BorderSizePixel = 0
    main.ClipsDescendants = true
    main.Active = true
    main.ZIndex = 1
    main.Parent = gui
    v3Corner(main, 20)
    window.MainFrame = main

    v3Stroke(
        main,
        Color3.new(1, 1, 1),
        0.89,
        1
    )

    local glassLayer = Instance.new("Frame")
    glassLayer.Name = "GlassLayer"
    glassLayer.Size = UDim2.new(1, -2, 1, -2)
    glassLayer.Position = UDim2.fromOffset(1, 1)
    glassLayer.BackgroundColor3 = Color3.new(1, 1, 1)
    glassLayer.BackgroundTransparency = 0.975
    glassLayer.BorderSizePixel = 0
    glassLayer.ZIndex = 2
    glassLayer.Parent = main
    v3Corner(glassLayer, 19)

    local topHighlight = Instance.new("Frame")
    topHighlight.Name = "TopHighlight"
    topHighlight.Size = UDim2.new(1, -4, 0, 78)
    topHighlight.Position = UDim2.fromOffset(2, 2)
    topHighlight.BackgroundColor3 = Color3.new(1, 1, 1)
    topHighlight.BackgroundTransparency = 0.989
    topHighlight.BorderSizePixel = 0
    topHighlight.ZIndex = 3
    topHighlight.Parent = main
    v3Corner(topHighlight, 18)

    -- La top bar prend maintenant toute la largeur.
    local top = Instance.new("Frame")
    top.Name = "TopBar"
    top.Size = UDim2.new(1, 0, 0, V4.NormalTopHeight)
    top.Position = UDim2.fromOffset(0, 6)
    top.BackgroundTransparency = 1
    top.Active = true
    top.ZIndex = 8
    top.Parent = main
    window.TopBar = top

    local dragSurface = Instance.new("TextButton")
    dragSurface.Name = "DragSurface"
    dragSurface.Size = UDim2.fromScale(1, 1)
    dragSurface.BackgroundTransparency = 1
    dragSurface.BorderSizePixel = 0
    dragSurface.AutoButtonColor = false
    dragSurface.Text = ""
    dragSurface.ZIndex = 8
    dragSurface.Active = true
    dragSurface.Parent = top

    window.DragSurface = dragSurface

    local title = Instance.new("TextLabel")
    title.Name = "Title"
    title.Size = UDim2.fromOffset(185, 25)
    title.Position = UDim2.fromOffset(14, 8)
    title.BackgroundTransparency = 1
    title.Text = window.Title
    title.Font = Enum.Font.GothamBold
    title.TextSize = 17
    title.TextColor3 = THEME.Text
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.ZIndex = 12
    title.Parent = top
    window.TitleLabel = title

    local subtitle = Instance.new("TextLabel")
    subtitle.Name = "Subtitle"
    subtitle.Size = UDim2.fromOffset(185, 15)
    subtitle.Position = UDim2.fromOffset(14, 32)
    subtitle.BackgroundTransparency = 1
    subtitle.Text = window.Subtitle
    subtitle.Font = THEME.Font
    subtitle.TextSize = 10
    subtitle.TextColor3 = THEME.TextDim
    subtitle.TextXAlignment = Enum.TextXAlignment.Left
    subtitle.ZIndex = 12
    subtitle.Parent = top
    window.SubtitleLabel = subtitle

    local profile = v3ProfileCard(window, top)
    profile.ZIndex = 14

    local function makeControl(name, text, xOffset, tint)
        local b = Instance.new("TextButton")
        b.Name = name
        b.Size = UDim2.fromOffset(28, 28)
        b.AnchorPoint = Vector2.new(1, 0)
        b.Position = UDim2.new(1, xOffset, 0, 13)
        b.BackgroundColor3 = Color3.new(1, 1, 1)
        b.BackgroundTransparency = 0.972
        b.BorderSizePixel = 0
        b.AutoButtonColor = false
        b.Text = text
        b.Font = Enum.Font.GothamBold
        b.TextSize = 15
        b.TextColor3 = tint or THEME.TextDim
        b.ZIndex = 15
        b.Active = true
        b.Parent = top
        v3Corner(b, 9)
        v3Stroke(
            b,
            Color3.new(1, 1, 1),
            0.94,
            1
        )

        -- Important : pas de Modal.
        b.MouseEnter:Connect(function()
            v4Tween(
                b,
                0.15,
                Enum.EasingDirection.Out,
                {
                    BackgroundTransparency = 0.91,
                    TextColor3 = THEME.Text,
                }
            )
        end)

        b.MouseLeave:Connect(function()
            v4Tween(
                b,
                0.18,
                Enum.EasingDirection.InOut,
                {
                    BackgroundTransparency = 0.972,
                    TextColor3 = tint or THEME.TextDim,
                }
            )
        end)

        b.MouseButton1Down:Connect(function()
            v4Tween(
                b,
                0.10,
                Enum.EasingDirection.Out,
                {
                    Size = UDim2.fromOffset(25, 25),
                }
            )
        end)

        b.MouseButton1Up:Connect(function()
            v4Tween(
                b,
                0.16,
                Enum.EasingDirection.Out,
                {
                    Size = UDim2.fromOffset(28, 28),
                }
            )
        end)

        return b
    end

    -- Toujours collés au coin supérieur droit.
    local minimize = makeControl(
        "Minimize",
        "−",
        -43
    )

    local close = makeControl(
        "Close",
        "×",
        -8,
        Color3.fromRGB(255, 130, 145)
    )

    window.MinimizeButton = minimize
    window.CloseButton = close

    -- Conteneur extérieur fixe.
    local tabOuter = Instance.new("Frame")
    tabOuter.Name = "TabBar"
    tabOuter.Size = UDim2.new(1, -24, 0, 40)
    tabOuter.Position = UDim2.fromOffset(12, 67)
    tabOuter.BackgroundColor3 = Color3.new(1, 1, 1)
    tabOuter.BackgroundTransparency = 0.976
    tabOuter.BorderSizePixel = 0
    tabOuter.ClipsDescendants = true
    tabOuter.Active = true
    tabOuter.ZIndex = 7
    tabOuter.Parent = main
    v3Corner(tabOuter, 13)
    v3Stroke(
        tabOuter,
        Color3.new(1, 1, 1),
        0.95,
        1
    )

    local tabScroller = Instance.new("ScrollingFrame")
    tabScroller.Name = "TabScroller"
    tabScroller.Size = UDim2.new(1, 0, 1, 0)
    tabScroller.Position = UDim2.fromOffset(0, 0)
    tabScroller.BackgroundTransparency = 1
    tabScroller.BorderSizePixel = 0
    tabScroller.ScrollingDirection =
        Enum.ScrollingDirection.X
    tabScroller.ScrollBarThickness = 0
    tabScroller.ScrollingEnabled = true
    tabScroller.CanvasSize = UDim2.fromOffset(0, 0)
    tabScroller.Active = true
    tabScroller.ZIndex = 8
    tabScroller.Parent = tabOuter

    local padding = Instance.new("UIPadding")
    padding.PaddingLeft = UDim.new(0, 4)
    padding.PaddingRight = UDim.new(0, 4)
    padding.PaddingTop = UDim.new(0, 3)
    padding.PaddingBottom = UDim.new(0, 3)
    padding.Parent = tabScroller

    local layout = Instance.new("UIListLayout")
    layout.FillDirection =
        Enum.FillDirection.Horizontal
    layout.VerticalAlignment =
        Enum.VerticalAlignment.Center
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Padding = UDim.new(0, 3)
    layout.Parent = tabScroller

    -- L'indicateur n'est PLUS enfant du layout.
    -- C'était la cause du faux "onglet vide".
    local liquid = Instance.new("Frame")
    liquid.Name = "LiquidIndicator"
    liquid.Size = UDim2.fromOffset(96, 34)
    liquid.Position = UDim2.fromOffset(4, 3)
    liquid.BackgroundColor3 = window.Accent
    liquid.BackgroundTransparency = 0.83
    liquid.BorderSizePixel = 0
    liquid.ZIndex = 7
    liquid.Parent = tabOuter
    v3Corner(liquid, 12)
    v3Stroke(
        liquid,
        Color3.fromRGB(208, 229, 255),
        0.61,
        1
    )

    local liquidGlow = Instance.new("Frame")
    liquidGlow.Size = UDim2.new(0.72, 0, 0.32, 0)
    liquidGlow.Position =
        UDim2.new(0.14, 0, 0.08, 0)
    liquidGlow.BackgroundColor3 = Color3.new(1, 1, 1)
    liquidGlow.BackgroundTransparency = 0.94
    liquidGlow.BorderSizePixel = 0
    liquidGlow.ZIndex = 8
    liquidGlow.Parent = liquid
    v3Corner(liquidGlow, 12)

    window.TabOuter = tabOuter
    window.TabScroller = tabScroller
    window.TabBar = tabScroller
    window.TabLayout = layout
    window.LiquidIndicator = liquid

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
    window.Profile = profile

    layout:GetPropertyChangedSignal(
        "AbsoluteContentSize"
    ):Connect(function()
        v4UpdateTabCanvas(window)
        v4PositionIndicator(window, true)
    end)

    tabScroller:GetPropertyChangedSignal(
        "CanvasPosition"
    ):Connect(function()
        v4PositionIndicator(window, true)
    end)

    -- Molette = scroll horizontal uniquement quand elle est
    -- au-dessus de la barre des onglets.
    tabScroller.InputChanged:Connect(function(input)
        if input.UserInputType
            ~= Enum.UserInputType.MouseWheel
        then
            return
        end

        local delta = input.Position.Z

        if delta == 0 then
            return
        end

        local current =
            tabScroller.CanvasPosition.X

        local maxX = math.max(
            0,
            tabScroller.AbsoluteCanvasSize.X
                - tabScroller.AbsoluteSize.X
        )

        tabScroller.CanvasPosition = Vector2.new(
            math.clamp(
                current - delta * 70,
                0,
                maxX
            ),
            0
        )
    end)

    -- Drag surface : toute la zone vide de la topbar.
    -- Les vrais contrôles au-dessus ne déclenchent pas le drag.
    local dragging = false
    local dragStart
    local startPos

    dragSurface.InputBegan:Connect(function(input)
        if input.UserInputType
            ~= Enum.UserInputType.MouseButton1
        then
            return
        end

        dragging = true
        dragStart = input.Position
        startPos = main.Position
    end)

    table.insert(
        window.Connections,
        UserInputService.InputEnded:Connect(function(input)
            if input.UserInputType
                == Enum.UserInputType.MouseButton1
            then
                dragging = false
            end
        end)
    )

    table.insert(
        window.Connections,
        UserInputService.InputChanged:Connect(function(input)
            if not dragging
                or input.UserInputType
                    ~= Enum.UserInputType.MouseMovement
            then
                return
            end

        local delta =
            input.Position - dragStart

        local pos = UDim2.new(
            startPos.X.Scale,
            startPos.X.Offset + delta.X,
            startPos.Y.Scale,
            startPos.Y.Offset + delta.Y
        )

            main.Position = pos
            shadow.Position = pos
        end)
    )

    minimize.MouseButton1Click:Connect(function()
        self:ToggleMinimize()
    end)

    close.MouseButton1Click:Connect(function()
        self:Destroy()
    end)

    self.Window = window

    setmetatable(window, {
        __index = {
            MakeTab = function(_, tabConfig)
                return GlassLib:MakeTab(tabConfig)
            end,
        },
    })

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

    local button = Instance.new("TextButton")
    button.Name = "TabButton"
    button.Size = UDim2.fromOffset(96, 34)
    button.BackgroundTransparency = 1
    button.BorderSizePixel = 0
    button.AutoButtonColor = false
    button.Text = tab.Name
    button.Font = THEME.Font
    button.TextSize = 10
    button.TextColor3 = THEME.TextDim
    button.LayoutOrder = tab.Order
    button.ZIndex = 10
    button.Active = true
    button.Parent = window.TabScroller

    local page = Instance.new("ScrollingFrame")
    page.Name = "Page"
    page.Size = UDim2.fromScale(1, 1)
    page.Position = UDim2.fromScale(1.08, 0)
    page.BackgroundTransparency = 1
    page.BorderSizePixel = 0
    page.ScrollBarThickness = 3
    page.ScrollBarImageColor3 = window.Accent
    page.ScrollBarImageTransparency = 0.55
    page.AutomaticCanvasSize = Enum.AutomaticSize.Y
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
        if window.CurrentTab == tab
            or window.Minimized
        then
            return
        end

        local old = window.CurrentTab
        local direction =
            (
                old
                and tab.Order < old.Order
            )
            and -1
            or 1

        window.CurrentTab = tab

        if old then
            v4SetTabColor(old, false)

            v4Tween(
                old.Page,
                0.34,
                Enum.EasingDirection.InOut,
                {
                    Position = UDim2.fromScale(
                        -direction * 1.08,
                        0
                    ),
                }
            )

            task.delay(0.36, function()
                if old ~= window.CurrentTab
                    and old.Page.Parent
                then
                    old.Page.Visible = false
                end
            end)
        end

        page.Visible = true
        page.Position = UDim2.fromScale(
            direction * 1.08,
            0
        )

        v4SetTabColor(tab, true)

        v4ScrollTabIntoView(window, tab)

        v4Tween(
            window.LiquidIndicator,
            0.52,
            Enum.EasingDirection.InOut,
            {
                Position = UDim2.fromOffset(
                    button.AbsolutePosition.X
                        - window.TabOuter.AbsolutePosition.X
                        - window.TabScroller.CanvasPosition.X,
                    3
                ),
                Size = UDim2.fromOffset(
                    button.AbsoluteSize.X,
                    34
                ),
            }
        )

        v4Tween(
            page,
            0.46,
            Enum.EasingDirection.InOut,
            {
                Position = UDim2.fromScale(0, 0),
            }
        )
    end

    button.MouseButton1Click:Connect(select)

    button.MouseEnter:Connect(function()
        if window.CurrentTab ~= tab then
            v4Tween(
                button,
                0.14,
                Enum.EasingDirection.Out,
                {
                    TextColor3 = THEME.Text,
                }
            )
        end
    end)

    button.MouseLeave:Connect(function()
        if window.CurrentTab ~= tab then
            v4Tween(
                button,
                0.17,
                Enum.EasingDirection.InOut,
                {
                    TextColor3 = THEME.TextDim,
                }
            )
        end
    end)

    if #window.Tabs == 1 then
        window.CurrentTab = tab
        page.Visible = true
        page.Position = UDim2.fromScale(0, 0)
        button.TextColor3 = THEME.Text

        task.defer(function()
            RunService.RenderStepped:Wait()
            v4UpdateTabCanvas(window)
            v4PositionIndicator(window, true)
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
                return GlassLib:AddParagraph(
                    tab,
                    a,
                    b
                )
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
                return GlassLib:AddColorpicker(
                    tab,
                    c
                )
            end,
        },
    })

    return tab
end

function GlassLib:ToggleMinimize()
    if not self.Window then
        return
    end

    local w = self.Window

    if w.Minimized then
        -- Restore vers la position précédente.
        w.Minimized = false

        w.Container.Visible = true
        w.TabOuter.Visible = true
        w.LiquidIndicator.Visible = true

        v4Tween(
            w.MainFrame,
            0.46,
            Enum.EasingDirection.InOut,
            {
                Size = V4.NormalSize,
                Position =
                    w.RestorePosition
                    or UDim2.fromScale(0.5, 0.5),
            }
        )

        v4Tween(
            w.Shadow,
            0.46,
            Enum.EasingDirection.InOut,
            {
                Size = V4.NormalShadow,
                Position =
                    w.RestorePosition
                    or UDim2.fromScale(0.5, 0.5),
            }
        )

        v4Tween(
            w.TopBar,
            0.46,
            Enum.EasingDirection.InOut,
            {
                Size = UDim2.new(
                    1,
                    0,
                    0,
                    V4.NormalTopHeight
                ),
            }
        )

        v4Tween(
            w.Profile,
            0.46,
            Enum.EasingDirection.InOut,
            {
                Position =
                    UDim2.new(
                        0.5,
                        0,
                        0,
                        7
                    ),
            }
        )

        v4Tween(
            w.MinimizeButton,
            0.46,
            Enum.EasingDirection.InOut,
            {
                Position =
                    UDim2.new(
                        1,
                        -43,
                        0,
                        13
                    ),
            }
        )

        v4Tween(
            w.CloseButton,
            0.46,
            Enum.EasingDirection.InOut,
            {
                Position =
                    UDim2.new(
                        1,
                        -8,
                        0,
                        13
                    ),
            }
        )

        v4Tween(
            w.TitleLabel,
            0.42,
            Enum.EasingDirection.InOut,
            {
                Size =
                    UDim2.fromOffset(
                        185,
                        25
                    ),
            }
        )

        task.delay(0.10, function()
            v4ActivateControls(w.ScreenGui)
            v4PositionIndicator(w, true)
        end)

        return
    end

    -- Sauvegarder la position normale AVANT de partir en haut à gauche.
    w.RestorePosition = w.MainFrame.Position
    w.Minimized = true

    w.Container.Visible = false
    w.TabOuter.Visible = false
    w.LiquidIndicator.Visible = false

    local miniPos =
        v4MinimizedPosition(w.MainFrame)

    v4Tween(
        w.MainFrame,
        0.46,
        Enum.EasingDirection.InOut,
        {
            Size = V4.MinimizedSize,
            Position = miniPos,
        }
    )

    v4Tween(
        w.Shadow,
        0.42,
        Enum.EasingDirection.InOut,
        {
            Size = V4.MinimizedShadow,
            Position = miniPos,
        }
    )

    v4Tween(
        w.TopBar,
        0.46,
        Enum.EasingDirection.InOut,
        {
            Size = UDim2.new(
                1,
                0,
                0,
                V4.MinimizedTopHeight
            ),
        }
    )

    -- Le profil descend sous les contrôles.
    v4Tween(
        w.Profile,
        0.46,
        Enum.EasingDirection.InOut,
        {
            Position = UDim2.new(
                0.5,
                0,
                0,
                43
            ),
        }
    )

    -- Les boutons restent au VRAI coin supérieur droit.
    v4Tween(
        w.MinimizeButton,
        0.46,
        Enum.EasingDirection.InOut,
        {
            Position = UDim2.new(
                1,
                -43,
                0,
                10
            ),
        }
    )

    v4Tween(
        w.CloseButton,
        0.46,
        Enum.EasingDirection.InOut,
        {
            Position = UDim2.new(
                1,
                -8,
                0,
                10
            ),
        }
    )

    v4Tween(
        w.TitleLabel,
        0.42,
        Enum.EasingDirection.InOut,
        {
            Size = UDim2.new(
                1,
                -112,
                0,
                25
            ),
        }
    )
end

function GlassLib:Destroy()
    if not self.Window
        or self.Window.Destroyed
    then
        return
    end

    local w = self.Window
    w.Destroyed = true

    for _, connection in ipairs(w.Connections or {}) do
        pcall(function()
            connection:Disconnect()
        end)
    end

    table.clear(w.Connections or {})

    local tweenMain = v4Tween(
        w.MainFrame,
        0.30,
        Enum.EasingDirection.InOut,
        {
            Size = UDim2.fromOffset(
                560,
                410
            ),
            BackgroundTransparency = 1,
        }
    )

    v4Tween(
        w.Shadow,
        0.28,
        Enum.EasingDirection.InOut,
        {
            Size = UDim2.fromOffset(
                580,
                420
            ),
            BackgroundTransparency = 1,
        }
    )

    if tweenMain then
        tweenMain.Completed:Connect(function()
            v3Destroy(w.ScreenGui)
        end)
    else
        v3Destroy(w.ScreenGui)
    end
end

function GlassLib:Init()
    if not self.Window then
        return
    end

    local w = self.Window

    -- Important pour le FPS / la caméra :
    -- aucun TextButton n'utilise Modal ; les contrôles restent Active.
    v4ActivateControls(w.ScreenGui)

    w.MainFrame.BackgroundTransparency = 1
    w.Shadow.BackgroundTransparency = 1

    local title =
        w.TopBar:FindFirstChild("Title")

    local subtitle =
        w.TopBar:FindFirstChild("Subtitle")

    if title then
        title.TextTransparency = 1
    end

    if subtitle then
        subtitle.TextTransparency = 1
    end

    w.Profile.BackgroundTransparency = 1

    v4Tween(
        w.Shadow,
        0.55,
        Enum.EasingDirection.Out,
        {
            BackgroundTransparency = 0.78,
        }
    )

    v4Tween(
        w.MainFrame,
        0.64,
        Enum.EasingDirection.InOut,
        {
            Size = V4.NormalSize,
            BackgroundTransparency = 0.16,
        }
    )

    if title then
        v4Tween(
            title,
            0.42,
            Enum.EasingDirection.Out,
            {
                TextTransparency = 0,
            }
        )
    end

    if subtitle then
        v4Tween(
            subtitle,
            0.50,
            Enum.EasingDirection.Out,
            {
                TextTransparency = 0,
            }
        )
    end

    v4Tween(
        w.Profile,
        0.48,
        Enum.EasingDirection.Out,
        {
            BackgroundTransparency = 0.973,
        }
    )

    task.defer(function()
        RunService.RenderStepped:Wait()
        v4UpdateTabCanvas(w)
        v4PositionIndicator(w, true)
        v4ActivateControls(w.ScreenGui)
    end)
end

return GlassLib
