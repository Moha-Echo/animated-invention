
local LiveConsole = (function()
    local Players = game:GetService("Players")
    local UIS = game:GetService("UserInputService")
    local HttpService = game:GetService("HttpService")
    local player = Players.LocalPlayer
    assert(player, "LiveConsole doit être utilisée côté client")

    local Console = {
        MaxLines = 300,
        ForwardToConsole = false,
        ToggleKey = Enum.KeyCode.RightShift
    }

    local function create(className, properties, parent)
        local obj = Instance.new(className)
        for key, value in pairs(properties or {}) do
            obj[key] = value
        end
        obj.Parent = parent
        return obj
    end

    local function getParent()
        local ok, hui = pcall(function()
            return gethui()
        end)
        if ok and hui then return hui end
        return player:WaitForChild("PlayerGui")
    end

    local gui = create("ScreenGui", {
        Name = "LiveDebugConsole",
        ResetOnSpawn = false,
        IgnoreGuiInset = true,
        DisplayOrder = 10000,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    }, getParent())

    local main = create("Frame", {
        Name = "Window",
        Size = UDim2.fromOffset(560, 360),
        Position = UDim2.new(1, -580, 1, -380),
        BackgroundColor3 = Color3.fromRGB(20, 22, 29),
        BorderSizePixel = 0
    }, gui)
    create("UICorner", {CornerRadius = UDim.new(0, 9)}, main)
    create("UIStroke", {
        Color = Color3.fromRGB(65, 70, 85),
        Thickness = 1
    }, main)

    local header = create("Frame", {
        Name = "Header",
        Size = UDim2.new(1, 0, 0, 38),
        BackgroundColor3 = Color3.fromRGB(30, 33, 43),
        BorderSizePixel = 0
    }, main)
    create("UICorner", {CornerRadius = UDim.new(0, 9)}, header)

    create("TextLabel", {
        Name = "Title",
        Position = UDim2.fromOffset(12, 0),
        Size = UDim2.new(1, -115, 1, 0),
        BackgroundTransparency = 1,
        Font = Enum.Font.Code,
        Text = "LIVE CONSOLE  //  DEBUG",
        TextColor3 = Color3.fromRGB(220, 225, 240),
        TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Left
    }, header)

    local minimize = create("TextButton", {
        Size = UDim2.fromOffset(30, 28),
        Position = UDim2.new(1, -70, 0, 5),
        BackgroundColor3 = Color3.fromRGB(48, 53, 67),
        Text = "—",
        TextColor3 = Color3.new(1, 1, 1),
        TextSize = 16,
        Font = Enum.Font.Code
    }, header)
    create("UICorner", {CornerRadius = UDim.new(0, 5)}, minimize)

    local hide = create("TextButton", {
        Size = UDim2.fromOffset(30, 28),
        Position = UDim2.new(1, -36, 0, 5),
        BackgroundColor3 = Color3.fromRGB(135, 48, 57),
        Text = "X",
        TextColor3 = Color3.new(1, 1, 1),
        TextSize = 14,
        Font = Enum.Font.Code
    }, header)
    create("UICorner", {CornerRadius = UDim.new(0, 5)}, hide)

    local body = create("Frame", {
        Name = "Body",
        Position = UDim2.fromOffset(0, 38),
        Size = UDim2.new(1, 0, 1, -38),
        BackgroundTransparency = 1
    }, main)

    local scroll = create("ScrollingFrame", {
        Name = "Output",
        Position = UDim2.fromOffset(8, 8),
        Size = UDim2.new(1, -16, 1, -48),
        BackgroundColor3 = Color3.fromRGB(14, 16, 21),
        BorderSizePixel = 0,
        ScrollBarThickness = 5,
        ScrollBarImageColor3 = Color3.fromRGB(105, 115, 140),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        ScrollingDirection = Enum.ScrollingDirection.Y
    }, body)
    create("UICorner", {CornerRadius = UDim.new(0, 5)}, scroll)

    local layout = create("UIListLayout", {
        Padding = UDim.new(0, 3),
        SortOrder = Enum.SortOrder.LayoutOrder
    }, scroll)

    local clearButton = create("TextButton", {
        Name = "Clear",
        Position = UDim2.new(0, 8, 1, -34),
        Size = UDim2.fromOffset(78, 27),
        BackgroundColor3 = Color3.fromRGB(48, 53, 67),
        Text = "EFFACER",
        TextColor3 = Color3.fromRGB(230, 230, 240),
        TextSize = 11,
        Font = Enum.Font.Code
    }, body)
    create("UICorner", {CornerRadius = UDim.new(0, 5)}, clearButton)

    create("TextLabel", {
        Name = "Hint",
        Position = UDim2.new(0, 96, 1, -34),
        Size = UDim2.new(1, -105, 0, 27),
        BackgroundTransparency = 1,
        Text = "RightShift : afficher / masquer",
        TextColor3 = Color3.fromRGB(130, 140, 160),
        TextSize = 11,
        Font = Enum.Font.Code,
        TextXAlignment = Enum.TextXAlignment.Left
    }, body)

    local lines = {}
    local connections = {}
    local minimized = false

    local colors = {
        INFO = Color3.fromRGB(220, 225, 240),
        WARN = Color3.fromRGB(255, 190, 85),
        ERROR = Color3.fromRGB(255, 100, 110),
        SUCCESS = Color3.fromRGB(100, 230, 155),
        DEBUG = Color3.fromRGB(110, 195, 255)
    }

    local function track(connection)
        table.insert(connections, connection)
        return connection
    end

    local function stringify(...)
        local output = {}
        for i = 1, select("#", ...) do
            local value = select(i, ...)
            if typeof(value) == "Instance" then
                output[i] = value:GetFullName()
            elseif type(value) == "table" then
                local ok, result = pcall(function()
                    return HttpService:JSONEncode(value)
                end)
                output[i] = ok and result or tostring(value)
            else
                output[i] = tostring(value)
            end
        end
        return table.concat(output, " ")
    end

    function Console:Log(level, ...)
        level = string.upper(tostring(level or "INFO"))
        local message = stringify(...)
        local timestamp = os.date("%H:%M:%S")
        local line = string.format("[%s] [%s] %s", timestamp, level, message)

        local row = create("TextLabel", {
            Name = "LogLine",
            Size = UDim2.new(1, -10, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1,
            Font = Enum.Font.Code,
            Text = line,
            TextColor3 = colors[level] or colors.INFO,
            TextSize = 12,
            TextWrapped = true,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextYAlignment = Enum.TextYAlignment.Top,
            LayoutOrder = #lines + 1
        }, scroll)

        table.insert(lines, row)

        while #lines > self.MaxLines do
            local old = table.remove(lines, 1)
            if old then old:Destroy() end
        end

        if self.ForwardToConsole and self._originals then
            local fn = level == "WARN"
                and self._originals.warn
                or self._originals.print
            if fn then pcall(fn, line) end
        end

        task.defer(function()
            if scroll.Parent then
                scroll.CanvasPosition = Vector2.new(
                    0,
                    math.max(0, scroll.AbsoluteCanvasSize.Y - scroll.AbsoluteSize.Y)
                )
            end
        end)
    end

    function Console:Info(...) self:Log("INFO", ...) end
    function Console:Print(...) self:Log("INFO", ...) end
    function Console:Warn(...) self:Log("WARN", ...) end
    function Console:Error(...) self:Log("ERROR", ...) end
    function Console:Success(...) self:Log("SUCCESS", ...) end
    function Console:Debug(...) self:Log("DEBUG", ...) end

    function Console:Clear()
        for _, row in ipairs(lines) do
            row:Destroy()
        end
        table.clear(lines)
        scroll.CanvasPosition = Vector2.zero
    end

    function Console:Show()
        main.Visible = true
    end

    function Console:Hide()
        main.Visible = false
    end

    function Console:Toggle()
        main.Visible = not main.Visible
    end

    function Console:AttachPrint()
        if self._attached then return true end

        local ok, env = pcall(function()
            return getfenv(0)
        end)

        if not ok or type(env) ~= "table" then
            self:Warn("Impossible d'intercepter print/warn dans cet environnement.")
            return false
        end

        self._environment = env
        self._originals = {
            print = env.print or print,
            warn = env.warn or warn
        }

        local logger = self

        self._printWrapper = function(...)
            logger:Log("INFO", ...)
        end

        self._warnWrapper = function(...)
            logger:Log("WARN", ...)
        end

        local printOK = pcall(function()
            env.print = self._printWrapper
        end)

        local warnOK = pcall(function()
            env.warn = self._warnWrapper
        end)

        self._attached = printOK or warnOK

        if self._attached then
            self:Success("Interception print/warn activée.")
        else
            self:Warn("Interception impossible. Utilise Console:Info().")
        end

        return self._attached
    end

    function Console:DetachPrint()
        local env = self._environment
        if not env then return end

        pcall(function()
            if env.print == self._printWrapper then
                env.print = self._originals.print
            end
            if env.warn == self._warnWrapper then
                env.warn = self._originals.warn
            end
        end)

        self._attached = false
        self._environment = nil
    end

    function Console:Destroy()
        self:DetachPrint()
        for _, connection in ipairs(connections) do
            connection:Disconnect()
        end
        gui:Destroy()
    end

    track(clearButton.Activated:Connect(function()
        Console:Clear()
    end))

    track(minimize.Activated:Connect(function()
        minimized = not minimized
        body.Visible = not minimized
        main.Size = UDim2.fromOffset(560, minimized and 38 or 360)
        minimize.Text = minimized and "+" or "—"
    end))

    track(hide.Activated:Connect(function()
        Console:Hide()
    end))

    track(UIS.InputBegan:Connect(function(input, processed)
        if not processed and input.KeyCode == Console.ToggleKey then
            Console:Toggle()
        end
    end))

    -- Déplacement de la fenêtre avec la souris ou le tactile.
    local dragging = false
    local dragStart, startPosition, dragInput

    track(header.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPosition = main.Position

            local ended
            ended = input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                    if ended then ended:Disconnect() end
                end
            end)
        end
    end))

    track(header.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
        end
    end))

    track(UIS.InputChanged:Connect(function(input)
        if dragging and input == dragInput then
            local delta = input.Position - dragStart
            main.Position = UDim2.new(
                startPosition.X.Scale,
                startPosition.X.Offset + delta.X,
                startPosition.Y.Scale,
                startPosition.Y.Offset + delta.Y
            )
        end
    end))

    Console:Success("LiveConsole initialisée.")
    return Console
end)()

-- Active l'interception pour les print() et warn() suivants.
LiveConsole:AttachPrint()
