--[[
    Nexus IA V6.0
    [🚢 CARGO] DUELS DE COUTEAUX
    V6 — architecture unifiée : tracking cible, visibilité, mouvement persistant, anti-stuck, Copy robuste, IA Lointain, ESP/PiP.
]]

------------------------------------------------------------
-- SERVICES & NETTOYAGE
------------------------------------------------------------
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local PathfindingService = game:GetService("PathfindingService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local Workspace = game:GetService("Workspace")
local Camera = workspace.CurrentCamera
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

for _, guiName in ipairs({"Nexus v2.0", "Nexus v3.0", "Nexus v4.0",  "Nexus v5.0", "Nexus v6.0"}) do
    local old = game:GetService("CoreGui"):FindFirstChild(guiName)
    if old then old:Destroy() end
end

------------------------------------------------------------
-- CONFIG GLOBALE
------------------------------------------------------------
_G.AimbotMode = "FOV Circle"
_G.ThroughWall = false
_G.AimSmooth = 1
_G.AimPartMode = "Human"
_G.LockCooldown = 0.1
_G.FOVColor = Color3.fromRGB(255, 0, 0)
_G.SpinBotEnabled = false
_G.SpinBotMode = "Serveur"
_G.SpinSpeed = 100
_G.GameModeSetup = "1v1"
_G.ESPMode = "Highlight"
_G.ESPColor = Color3.fromRGB(255, 0, 0)
_G.TracersEnabled = false
_G.TPBehindActive = false
_G.CameraCorner = "Haut-Droite"

local ALLY_COLOR = Color3.fromRGB(0, 255, 90)
local AutoPlayConfig
local fovCircle

local aimbotActive = true
local currentTarget = nil
local trackedTarget = nil

local MatchState = {
    Ended = false,
    PlayersProtected = false,
    LastEndTime = 0
}

-- Cible persistante de l'IA : tracking séparé du verrouillage caméra.
local AITarget = nil
local AITargetSince = 0
local AITargetLastValid = 0
local AITargetLastVisible = false
local AILastAcquire = 0

local AIState = {
    Name = "Idle",
    LastStateChange = 0,

    LastPosition = nil,
    LastPositionTime = 0,
    StuckSince = nil,
    StuckStage = 0,
    StuckCooldownUntil = 0,

    LastDirection = Vector3.zero,
    LastMoveCommand = 0,

    StuckMemory = {},

    CurrentStuckKey = nil,
    CurrentStuckAttempt = nil,

    TemporaryRecoveryStyle = nil,
    RecoveryOriginalStyle = nil,
    RecoveryStartedAt = 0,

    LastM1 = 0,
    LastM2 = 0,
    LastJump = 0,
    LastSlide = 0,

    StrafeSide = 1,
    NextStrafeSwitch = 0,

    RoundId = 0,
    ShiftApplied = false,
}
local fovRadius = 130
local whitelistedAllies = {}
local lastTargetTime = 0
local tpBehindOffset = 4

--========================================================--
-- AIMBOT : SYSTÈME DE PRIORITÉS
--========================================================--

local AimbotPriorityConfig = {
    Primary = "Visibilité",
    Secondary = "Dangereux",
    Tertiary = "Plus proche",

    -- Intervalle entre deux réévaluations de cible.
    -- Plus bas = changement de cible plus réactif.
    RecheckInterval = 0.08,

    -- Un joueur est considéré comme "dangereux"
    -- s'il regarde suffisamment dans notre direction.
    DangerThreshold = 0.55,

    -- Garde une petite stabilité lorsqu'il y a de minuscules
    -- différences entre deux candidats.
    DistanceTieTolerance = 1.5,
}

local function sendNotification(title, text, icon)
    StarterGui:SetCore("SendNotification", {
        Title = title,
        Text = text,
        Duration = 3,
        Icon = icon or "rbxassetid://111201744721013",
    })
end

local logLines, maxLogLines = {}, 14
local logGui, logText

local function refreshLogText()
    if logText then logText.Text = #logLines > 0 and table.concat(logLines, "\n") or "En attente..." end
end

local function setLogVisible(v) if logGui then logGui.Enabled = v end end

local function pushLog(tag, message)
    local line = ("[%s] %s"):format(tostring(tag), tostring(message))
    print("[Nexus V6] " .. line)
    table.insert(logLines, 1, line)
    while #logLines > maxLogLines do table.remove(logLines) end
    refreshLogText()
end

------------------------------------------------------------
-- DUEL : VALIDATION CIBLE (HP / DuelEliminated)
------------------------------------------------------------
local function getDuelHP(player)
    local char = player and player.Character
    if not char then return nil end
    local hp = char:GetAttribute("HP")
    if hp == nil then
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum then hp = hum.Health end
    end
    return hp
end

local function isDuelTargetActive(player)
    if not player or player == LocalPlayer then return false end
    local char = player.Character
    if not char or not char:FindFirstChild("HumanoidRootPart") then return false end
    if char:GetAttribute("DuelEliminated") == true then return false end
    local hp = getDuelHP(player)
    if hp ~= nil and hp <= 0 then return false end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum and hum.Health <= 0 then return false end
    return true
end

local function applyAllyHighlight(player)
    local char = player and player.Character

    if not char then
        return
    end

    local hl =
        char:FindFirstChild("NexusAllyHighlight")

    if not hl then
        hl = Instance.new("Highlight")
        hl.Name = "NexusAllyHighlight"
        hl.Parent = char
    end

    hl.FillColor = ALLY_COLOR
    hl.OutlineColor = ALLY_COLOR
    hl.FillTransparency = 0.45
    hl.OutlineTransparency = 0
    hl.Adornee = char
    hl.Enabled = true
end

local function clearAllyHighlight(player)
    local char = player and player.Character

    if char then
        local ally =
            char:FindFirstChild("NexusAllyHighlight")

        if ally then
            ally:Destroy()
        end
    end
end

local function protectAllPlayersAfterMatch()
    MatchState.Ended = true
    MatchState.PlayersProtected = true
    MatchState.LastEndTime = os.clock()

    -- L'IA ne doit plus avoir de cible.
    AITarget = nil
    trackedTarget = nil
    currentTarget = nil

    -- Tous les joueurs deviennent temporairement alliés.
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            whitelistedAllies[player] = true
            applyAllyHighlight(player)
        end
    end

    pushLog(
        "MATCH",
        "Fin du duel détectée : tous les joueurs sont temporairement protégés."
    )
end

local function clearMatchProtection()
    if not MatchState.Ended then
        return
    end

    for player in pairs(whitelistedAllies) do
        clearAllyHighlight(player)
    end

    table.clear(whitelistedAllies)

    MatchState.Ended = false
    MatchState.PlayersProtected = false

    AITarget = nil
    trackedTarget = nil
    currentTarget = nil

    AutoPlayConfig.AutoDeaths = 0

    if AutoPlayConfig.IAStyle == "AUTO" then
        AutoPlayConfig.AutoBaseStyle = "Aggressive"
    end

    _G.ThroughWall = false
    _G.AimSmooth = 1

    AIState.StuckMemory = {}

    AIState.CurrentStuckKey = nil
    AIState.CurrentStuckAttempt = nil

    AIState.StuckSince = nil
    AIState.StuckStage = 0

    AIState.TemporaryRecoveryStyle = nil
    AIState.RecoveryOriginalStyle = nil
    AIState.RecoveryStartedAt = 0

    pushLog(
        "IA",
        "Mémoire anti-stuck réinitialisée pour la nouvelle partie."
    )
    pushLog(
        "MATCH",
        "Nouvelle manche détectée : protection retirée."
    )
end
------------------------------------------------------------
-- ORION UI
------------------------------------------------------------
local OrionLib = loadstring(game:HttpGet("https://raw.githubusercontent.com/Moha-Echo/animated-invention/refs/heads/main/OrionLib/source"))()
local Window = OrionLib:MakeWindow({
    Name = "Nexus v6.0",
    HidePremium = true,
    SaveConfig = false,
})

------------------------------------------------------------
-- ONGLET COMBAT
------------------------------------------------------------
local CombatTab = Window:MakeTab({ Name = "Combat", Icon = "rbxassetid://4483345998", PremiumOnly = false })

CombatTab:AddDropdown({
    Name = "Mode visée",
    Default = "FOV Circle",
    Options = {"FOV Circle", "Champ de Vision", "Full Lock"},
    Callback = function(v) _G.AimbotMode = v end,
})

CombatTab:AddDropdown({
    Name = "Partie visée",
    Default = "Human",
    Options = {
        "Head",
        "Body",
        "Human"
    },

    Callback = function(v)
        _G.AimPartMode = v
    end,
})

CombatTab:AddToggle({ Name = "Wallbang", Default = false, Callback = function(v) _G.ThroughWall = v end })

--========================================================--
-- PRIORITÉS DE SÉLECTION
--========================================================--

local PriorityOptions = {
    "Visibilité",
    "Dangereux",
    "Plus proche",
    "Plus proche du viseur"
}

CombatTab:AddDropdown({
    Name = "Priorité 1",
    Default = AimbotPriorityConfig.Primary,
    Options = PriorityOptions,

    Callback = function(value)
        AimbotPriorityConfig.Primary = value
        trackedTarget = nil
        currentTarget = nil
        AITarget = nil
    end
})

CombatTab:AddDropdown({
    Name = "Priorité 2",
    Default = AimbotPriorityConfig.Secondary,
    Options = PriorityOptions,

    Callback = function(value)
        AimbotPriorityConfig.Secondary = value
        trackedTarget = nil
        currentTarget = nil
        AITarget = nil
    end
})

CombatTab:AddDropdown({
    Name = "Priorité 3",
    Default = AimbotPriorityConfig.Tertiary,
    Options = PriorityOptions,

    Callback = function(value)
        AimbotPriorityConfig.Tertiary = value
        trackedTarget = nil
        currentTarget = nil
        AITarget = nil
    end
})

CombatTab:AddColorpicker({
    Name = "Couleur FOV",
    Default = Color3.fromRGB(255, 0, 0),
    Callback = function(v)
        _G.FOVColor = v
        if fovCircle then fovCircle.Color = v end
    end,
})

CombatTab:AddSlider({
    Name = "Lissage (IA + Aimbot)",
    Min = 1, Max = 10, Default = 10,
    Color = Color3.fromRGB(255, 100, 0), Increment = 1, ValueName = "/10",
    Callback = function(v) _G.AimSmooth = v / 10 end,
})

CombatTab:AddSlider({
    Name = "Cooldown cible",
    Min = 0, Max = 100, Default = 10,
    Color = Color3.fromRGB(0, 100, 255), Increment = 5, ValueName = "ms",
    Callback = function(v) _G.LockCooldown = v / 100 end,
})

CombatTab:AddSlider({
    Name = "Réévaluation cible",
    Min = 1,
    Max = 30,
    Default = 8,
    Increment = 1,
    ValueName = "x10 ms",

    Callback = function(v)
        AimbotPriorityConfig.RecheckInterval = v / 100
    end
})

CombatTab:AddParagraph("Raccourcis", "J = Aimbot | V = Alliés | L = REC | P = Copy")

------------------------------------------------------------
-- ONGLET ALLIÉS
------------------------------------------------------------
local AlliesTab = Window:MakeTab({ Name = "Alliés", Icon = "rbxassetid://4483345998", PremiumOnly = false })

local totalJoueurs = #Players:GetPlayers()
local defaultMatchFormat = "2v2"
if totalJoueurs == 2 then defaultMatchFormat = "1v1"
elseif totalJoueurs == 4 then defaultMatchFormat = "2v2"
elseif totalJoueurs == 6 then defaultMatchFormat = "3v3"
elseif totalJoueurs == 8 then defaultMatchFormat = "4v4"
end

AlliesTab:AddDropdown({
    Name = "Format du Match",
    Default = defaultMatchFormat,
    Options = {"1v1", "2v2", "3v3", "4v4"},
    Callback = function(v) _G.GameModeSetup = v end,
})

local function getPlayerAvatarUrl(player)
    if not player then return "rbxassetid://0" end
    return "https://roblox.com/HeadshotThumbnail/image?userId=" .. player.UserId .. "&width=150&height=150&format=png"
end

local function getSortedPlayersByDistance()
    local list = {}
    local char = LocalPlayer.Character
    if not char or not char:FindFirstChild("HumanoidRootPart") then return list end
    local localPos = char.HumanoidRootPart.Position
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            if LocalPlayer.Team and player.Team == LocalPlayer.Team then continue end
            local pChar = player.Character
            if pChar and pChar:FindFirstChild("HumanoidRootPart") then
                table.insert(list, { Player = player, Distance = (pChar.HumanoidRootPart.Position - localPos).Magnitude })
            end
        end
    end
    table.sort(list, function(a, b) return a.Distance < b.Distance end)
    return list
end

local function triggerAutomaticFetch()
    local slotsToFill = ({ ["2v2"] = 1, ["3v3"] = 2, ["4v4"] = 3 })[_G.GameModeSetup] or 0
    if slotsToFill == 0 then
        sendNotification("Whitelist", "Mode 1v1 : Aucun allié requis.")
        return
    end
    local sortedList = getSortedPlayersByDistance()
    local addedCount = 0
    for i = 1, #sortedList do
        if addedCount >= slotsToFill then break end
        local targetData = sortedList[i]
        if targetData.Distance <= 50 then
            local p = targetData.Player
            if not whitelistedAllies[p] then
                whitelistedAllies[p] = true
                addedCount = addedCount + 1
                applyAllyHighlight(p)
                sendNotification("Allié Protégé", p.Name .. " (Highlight vert)", getPlayerAvatarUrl(p))
            end
        else break end
    end
end

UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.KeyCode == Enum.KeyCode.V then triggerAutomaticFetch() end
end)

AlliesTab:AddButton({ Name = "Scanner les Alliés (Touche V)", Callback = triggerAutomaticFetch })
AlliesTab:AddButton({
    Name = "Vider la Liste",
    Callback = function()
        for p in pairs(whitelistedAllies) do clearAllyHighlight(p) end
        table.clear(whitelistedAllies)
        sendNotification("Whitelist", "Tous les alliés ont été retirés.")
    end,
})

------------------------------------------------------------
-- ONGLET SPIN
------------------------------------------------------------
local SpinTab = Window:MakeTab({ Name = "Spin", Icon = "rbxassetid://4483345998", PremiumOnly = false })

SpinTab:AddToggle({
    Name = "Activer le Spin Bot",
    Default = false,
    Callback = function(v)
        _G.SpinBotEnabled = v
        if not v then
            local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
            if hum then hum.AutoRotate = true end
        end
    end,
})

SpinTab:AddDropdown({ Name = "Type de Rendu", Default = "Serveur", Options = {"Client", "Serveur"}, Callback = function(v) _G.SpinBotMode = v end })
SpinTab:AddSlider({ Name = "Vitesse", Min = 10, Max = 350, Default = 100, Increment = 10, ValueName = "vitesse", Callback = function(v) _G.SpinSpeed = v end })

------------------------------------------------------------
-- MOTEUR AIMBOT (visée seulement si cible visible + vivante)
------------------------------------------------------------
fovCircle = Drawing.new("Circle")
fovCircle.Color = _G.FOVColor
fovCircle.Thickness = 1.5
fovCircle.Radius = fovRadius
fovCircle.Transparency = 0.8
fovCircle.Visible = aimbotActive
fovCircle.Filled = false

UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.KeyCode == Enum.KeyCode.J then
        aimbotActive = not aimbotActive
        currentTarget = nil
        trackedTarget = nil
        if fovCircle then fovCircle.Visible = aimbotActive end
        sendNotification("Aimbot", aimbotActive and "ACTIVÉ" or "DÉSACTIVÉ")
    end
end)

local getAimPart
local resetAimPart

local function checkTargetVisibility(targetHead)
    if _G.ThroughWall then return true end
    local char = LocalPlayer.Character
    if not char or not char:FindFirstChild("Head") or not targetHead then return false end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Blacklist
    params.FilterDescendantsInstances = { char }
    local result = Workspace:Raycast(char.Head.Position, targetHead.Position - char.Head.Position, params)
    return result and result.Instance and result.Instance:IsDescendantOf(targetHead.Parent)
end

local function canAimAtPlayer(player)
    if not isDuelTargetActive(player) then
        return false
    end

    if player == LocalPlayer
        or whitelistedAllies[player]
    then
        return false
    end

    if LocalPlayer.Team
        and player.Team == LocalPlayer.Team
    then
        return false
    end

    local char = player.Character

    if not char
        or not char:FindFirstChild("Head")
    then
        return false
    end

    local screenPos, onScreen =
        Camera:WorldToViewportPoint(
            char.Head.Position
        )

    local center =
        Vector2.new(
            Camera.ViewportSize.X / 2,
            Camera.ViewportSize.Y / 2
        )

    if _G.AimbotMode == "FOV Circle" then
        if fovCircle then
            fovCircle.Visible = aimbotActive
        end

        if not onScreen then
            return false
        end

        if (
            Vector2.new(
                screenPos.X,
                screenPos.Y
            ) - center
        ).Magnitude > fovRadius then
            return false
        end

    elseif _G.AimbotMode == "Champ de Vision" then
        if fovCircle then
            fovCircle.Visible = false
        end

        if not onScreen then
            return false
        end

    elseif _G.AimbotMode == "Full Lock" then
        if fovCircle then
            fovCircle.Visible = false
        end
    end

    return _G.ThroughWall
        or checkTargetVisibility(char.Head)
end

-- Tracking et visibilité sont volontairement séparés :
-- l'IA peut garder une cible à travers un mur sans forcer la caméra à la regarder.
local function isTargetVisible(player)
    if not isDuelTargetActive(player) then
        return false
    end

    if _G.ThroughWall then
        return true
    end

    local targetChar = player.Character
    local localChar = LocalPlayer.Character

    if not targetChar or not localChar then
        return false
    end

    local localHead = localChar:FindFirstChild("Head")
    local targetPart = getAimPart(player)

    if not localHead or not targetPart then
        return false
    end

    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Blacklist
    params.FilterDescendantsInstances = {
        localChar
    }
    params.IgnoreWater = true

    local direction =
        targetPart.Position
        - localHead.Position

    if direction.Magnitude <= 0.01 then
        return true
    end

    local result =
        Workspace:Raycast(
            localHead.Position,
            direction,
            params
        )

    return (
        not result
        or result.Instance:IsDescendantOf(targetChar)
    )
end

--========================================================--
-- DÉTECTION : JOUEUR QUI NOUS REGARDE
--========================================================--

local function isPlayerDangerous(player)
    if not isDuelTargetActive(player) then
        return false
    end

    local localChar = LocalPlayer.Character
    local targetChar = player.Character

    if not localChar or not targetChar then
        return false
    end

    local localHead = localChar:FindFirstChild("Head")
    local targetHead = targetChar:FindFirstChild("Head")

    if not localHead or not targetHead then
        return false
    end

    local directionToUs =
        localHead.Position - targetHead.Position

    if directionToUs.Magnitude <= 0.01 then
        return true
    end

    directionToUs = directionToUs.Unit

    local lookDirection =
        targetHead.CFrame.LookVector.Unit

    local dot =
        lookDirection:Dot(directionToUs)

    return dot >= AimbotPriorityConfig.DangerThreshold
end

--========================================================--
-- AUTO PLAY : CIBLE LA PLUS PROCHE UNIQUEMENT
--========================================================--

--========================================================--
-- AUTO PLAY : SELECTEUR DE CIBLE INTELLIGENT
--
-- Règles :
-- 1. Si aucun ennemi visible -> plus proche.
-- 2. Si au moins un ennemi visible -> ignorer les cachés.
-- 3. Si plusieurs visibles -> joueur dangereux prioritaire.
-- 4. En cas d'égalité -> plus proche.
--========================================================--

--========================================================--
-- AUTO PLAY : VALIDATION DES ENNEMIS
--========================================================--

local function isEnemyValidForTrackingOldTeamCheck(player)
    if not player
        or player == LocalPlayer
        or whitelistedAllies[player]
    then
        return false
    end

    if LocalPlayer.Team
        and player.Team == LocalPlayer.Team
    then
        return false
    end

    return isDuelTargetActive(player)
end

local function isEnemyValidForTracking(player)
    if not player
        or player == LocalPlayer
    then
        return false
    end

    if whitelistedAllies[player] then
        return false
    end

    -- Le jeu a explicitement déclaré le joueur allié.
    if hasGameHighlight(
        player,
        GAME_TEAMMATE_HIGHLIGHT
    ) then
        whitelistedAllies[player] = true
        return false
    end

    -- Le jeu a explicitement déclaré le joueur ennemi.
    if hasGameHighlight(
        player,
        GAME_ENEMY_HIGHLIGHT
    ) then
        return isDuelTargetActive(player)
    end

    -- Fallback si les highlights n'existent pas encore.
    if LocalPlayer.Team
        and player.Team == LocalPlayer.Team
    then
        return false
    end

    return isDuelTargetActive(player)
end

--========================================================--
-- AUTO PLAY : SELECTEUR DE CIBLE
--========================================================--

local function acquireAITarget(fromPosition)
    local allCandidates = {}
    local visibleCandidates = {}

    for _, player in ipairs(Players:GetPlayers()) do
        if isEnemyValidForTracking(player) then
            local char = player.Character
            local hrp =
                char
                and char:FindFirstChild("HumanoidRootPart")

            if hrp then
                local distance =
                    (hrp.Position - fromPosition).Magnitude

                if distance <= AutoPlayConfig.DetectionRange then
                    local visible =
                        isTargetVisible(player)

                    local dangerous =
                        isPlayerDangerous(player)

                    local candidate = {
                        Player = player,
                        Distance = distance,
                        Visible = visible,
                        Dangerous = dangerous
                    }

                    table.insert(
                        allCandidates,
                        candidate
                    )

                    if visible then
                        table.insert(
                            visibleCandidates,
                            candidate
                        )
                    end
                end
            end
        end
    end

    if #allCandidates == 0 then
        local totalPlayers = 0
        local validDuel = 0
        local blockedAllies = 0
        local blockedTeam = 0

        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer then
                totalPlayers += 1

                if whitelistedAllies[player] then
                    blockedAllies += 1

                elseif LocalPlayer.Team
                    and player.Team == LocalPlayer.Team
                then
                    blockedTeam += 1

                elseif isDuelTargetActive(player) then
                    validDuel += 1
                end
            end
        end

        logStateOnce(
            "Scan",
            string.format(
                "Aucun ennemi | joueurs=%d duel=%d alliés=%d équipe=%d",
                totalPlayers,
                validDuel,
                blockedAllies,
                blockedTeam
            )
        )

        return nil
    end

    --====================================================--
    -- AU MOINS UN ENNEMI VISIBLE
    --====================================================--

    if #visibleCandidates > 0 then
        local best = nil

        for _, candidate in ipairs(visibleCandidates) do
            if not best then
                best = candidate

            elseif candidate.Dangerous
                and not best.Dangerous
            then
                best = candidate

            elseif candidate.Dangerous
                == best.Dangerous
                and candidate.Distance < best.Distance
            then
                best = candidate
            end
        end

        return best.Player
    end

    --====================================================--
    -- PERSONNE VISIBLE
    -- → CIBLE LA PLUS PROCHE
    --====================================================--

    local closest = allCandidates[1]

    for i = 2, #allCandidates do
        local candidate = allCandidates[i]

        if candidate.Distance < closest.Distance then
            closest = candidate
        end
    end

    return closest.Player
end

--========================================================--
-- AIMBOT : CALCUL DES PRIORITÉS
--========================================================--

local function getTargetPriorityValue(player, priority)
    local char = player.Character

    if not char then
        return nil
    end

    local hrp = char:FindFirstChild("HumanoidRootPart")
    local head = char:FindFirstChild("Head")

    if priority == "Visibilité" then
        return isTargetVisible(player) and 1 or 0
    end

    if priority == "Dangereux" then
        return isPlayerDangerous(player) and 1 or 0
    end

    if priority == "Plus proche" then
        local localChar = LocalPlayer.Character
        local localHRP =
            localChar and localChar:FindFirstChild("HumanoidRootPart")

        if not localHRP or not hrp then
            return nil
        end

        -- Inversion pour que la valeur la plus élevée soit prioritaire.
        return -(
            hrp.Position - localHRP.Position
        ).Magnitude
    end

    if priority == "Plus proche du viseur" then
        if not head then
            return nil
        end

        local screenPos =
            Camera:WorldToViewportPoint(head.Position)

        local center =
            Vector2.new(
                Camera.ViewportSize.X / 2,
                Camera.ViewportSize.Y / 2
            )

        return -(
            Vector2.new(
                screenPos.X,
                screenPos.Y
            ) - center
        ).Magnitude
    end

    return nil
end


local function isBetterTarget(candidate, current)
    if not candidate then
        return false
    end

    if not current then
        return true
    end

    local priorities = {
        AimbotPriorityConfig.Primary,
        AimbotPriorityConfig.Secondary,
        AimbotPriorityConfig.Tertiary
    }

    for _, priority in ipairs(priorities) do
        -- Quand Wallbang est activé, la visibilité n'est
        -- plus un critère : tout est considéré visible.
        if not (
            priority == "Visibilité"
            and _G.ThroughWall
        ) then

            local candidateValue =
                getTargetPriorityValue(
                    candidate,
                    priority
                )

            local currentValue =
                getTargetPriorityValue(
                    current,
                    priority
                )

            if candidateValue ~= nil
                and currentValue ~= nil
            then

                local difference =
                    candidateValue - currentValue

                if math.abs(difference) > 0.0001 then
                    return difference > 0
                end
            end
        end
    end

    -- Dernier tie-breaker : distance réelle.
    local localChar = LocalPlayer.Character
    local localHRP =
        localChar and localChar:FindFirstChild("HumanoidRootPart")

    local candidateHRP =
        candidate.Character
        and candidate.Character:FindFirstChild("HumanoidRootPart")

    local currentHRP =
        current.Character
        and current.Character:FindFirstChild("HumanoidRootPart")

    if localHRP and candidateHRP and currentHRP then
        local candidateDistance =
            (
                candidateHRP.Position
                - localHRP.Position
            ).Magnitude

        local currentDistance =
            (
                currentHRP.Position
                - localHRP.Position
            ).Magnitude

        return candidateDistance < currentDistance
    end

    return false
end


local function searchBestTarget(requireVisible)
    local bestTarget = nil

    local localChar = LocalPlayer.Character

    if not localChar then
        return nil
    end

    --====================================================--
    -- 1. CONSTRUIRE LES CANDIDATS
    --====================================================--

    local candidates = {}

    for _, player in ipairs(Players:GetPlayers()) do
        if isEnemyValidForTracking(player) then
            local char = player.Character
            local head = char and char:FindFirstChild("Head")

            if head then
                local screenPos, onScreen =
                    Camera:WorldToViewportPoint(
                        head.Position
                    )

                local center =
                    Vector2.new(
                        Camera.ViewportSize.X / 2,
                        Camera.ViewportSize.Y / 2
                    )

                local screenDistance =
                    (
                        Vector2.new(
                            screenPos.X,
                            screenPos.Y
                        ) - center
                    ).Magnitude

                local validForMode = true

                --================================================--
                -- FOV CIRCLE
                --================================================--

                if _G.AimbotMode == "FOV Circle" then
                    validForMode =
                        onScreen
                        and screenDistance <= fovRadius

                --================================================--
                -- CHAMP DE VISION
                --================================================--

                elseif _G.AimbotMode == "Champ de Vision" then
                    validForMode = onScreen

                --================================================--
                -- FULL LOCK
                --================================================--

                elseif _G.AimbotMode == "Full Lock" then
                    validForMode = true
                end

                if validForMode then
                    table.insert(
                        candidates,
                        player
                    )
                end
            end
        end
    end

    if #candidates == 0 then
        return nil
    end

    --====================================================--
    -- 2. VISIBILITÉ = PRIORITÉ ABSOLUE SI WALLBANG OFF
    --====================================================--

    if not _G.ThroughWall then
        local visibleCandidates = {}

        for _, player in ipairs(candidates) do
            if isTargetVisible(player) then
                table.insert(
                    visibleCandidates,
                    player
                )
            end
        end

        -- S'il existe des joueurs visibles,
        -- on ne choisit JAMAIS un joueur derrière un mur.
        if #visibleCandidates > 0 then
            candidates = visibleCandidates
        else
            -- Aucun joueur visible = aucune cible.
            return nil
        end
    end

    --====================================================--
    -- 3. CLASSEMENT MULTI-PRIORITÉS
    --====================================================--

    for _, player in ipairs(candidates) do
        if isBetterTarget(player, bestTarget) then
            bestTarget = player
        end
    end

    return bestTarget
end

--========================================================--
-- AIM PART : HEAD / BODY / HUMAN
--========================================================--

--========================================================--
-- AIM PART : HEAD / BODY / HUMAN
--========================================================--

local targetAimParts = {}

local function getBodyAimPart(character)
    if not character then
        return nil
    end

    local upperTorso = character:FindFirstChild("UpperTorso")
    if upperTorso then
        return upperTorso
    end

    local torso = character:FindFirstChild("Torso")
    if torso then
        return torso
    end

    return character:FindFirstChild("HumanoidRootPart")
end


getAimPart = function(player)
    if not player or not player.Character then
        return nil
    end

    local character = player.Character

    --====================================================--
    -- HEAD
    --====================================================--

    if _G.AimPartMode == "Head" then
        return character:FindFirstChild("Head")
    end

    --====================================================--
    -- BODY
    --====================================================--

    if _G.AimPartMode == "Body" then
        return getBodyAimPart(character)
    end

    --====================================================--
    -- HUMAN
    --====================================================--

    local cached = targetAimParts[player]

    if cached and cached.Parent then
        return cached
    end

    local head = character:FindFirstChild("Head")
    local body = getBodyAimPart(character)

    if not head and not body then
        return nil
    end

    if not body then
        targetAimParts[player] = head
        return head
    end

    if not head then
        targetAimParts[player] = body
        return body
    end

    -- 30% HEAD / 70% BODY
    if math.random() <= 0.30 then
        targetAimParts[player] = head
    else
        targetAimParts[player] = body
    end

    return targetAimParts[player]
end


resetAimPart = function(player)
    if player then
        targetAimParts[player] = nil
    end
end

local function aimAtTarget(player)
    if not Camera
        or not player
        or not player.Character
    then
        return
    end

    if not isDuelTargetActive(player) then
        return
    end

    if not isTargetVisible(player) then
        return
    end

    local aimPart = getAimPart(player)

    if not aimPart then
        return
    end

    local targetCFrame =
        CFrame.new(
            Camera.CFrame.Position,
            aimPart.Position
        )

    local smoothing =
        math.clamp(
            _G.AimSmooth or 0.5,
            0.01,
            1
        )

    Camera.CFrame =
        Camera.CFrame:Lerp(
            targetCFrame,
            smoothing
        )
end

local currentAngle = 0

RunService.RenderStepped:Connect(function() 
    Camera = workspace.CurrentCamera or Camera 
    local center = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2) 
    if fovCircle then 
        fovCircle.Position = center 
        fovCircle.Color = _G.FOVColor or fovCircle.Color 
    end 
    local char = LocalPlayer.Character 
    local hrp = char and char:FindFirstChild("HumanoidRootPart") 
    local hum = char and char:FindFirstChildOfClass("Humanoid") 
    if _G.SpinBotEnabled and hrp and hum and hum.Health > 0 then 
        currentAngle = (currentAngle + _G.SpinSpeed) % 360 
        local radAngle = math.rad(currentAngle) 
        if _G.SpinBotMode == "Serveur" then 
            hum.AutoRotate = false 
            hrp.CFrame = CFrame.new(hrp.Position) * CFrame.Angles(0, radAngle, 0) 
            if Camera.CameraType == Enum.CameraType.Custom then 
                Camera.CFrame = CFrame.new(Camera.CFrame.Position) * Camera.CFrame.Rotation 
            end 
        else 
            hum.AutoRotate = true 
            Camera.CFrame = Camera.CFrame * CFrame.Angles(0, radAngle, 0) 
        end 
    end 
    if aimbotActive then
        -- Réévaluation régulière de la meilleure cible.
        if tick() - lastTargetTime >= AimbotPriorityConfig.RecheckInterval then
            local newTarget =
                searchBestTarget(false)

            if newTarget ~= trackedTarget then
                resetAimPart(trackedTarget)
                resetAimPart(newTarget)

                trackedTarget = newTarget
                currentTarget = newTarget
            end

            lastTargetTime = tick()
        end

        -- Nettoyage si la cible devient invalide.
        if trackedTarget
            and not isEnemyValidForTracking(trackedTarget)
        then
            trackedTarget = nil
            currentTarget = nil
        end

        -- La visée reste soumise à la visibilité,
        -- sauf si Wallbang est actif.
        if trackedTarget
            and canAimAtPlayer(trackedTarget)
        then
            aimAtTarget(trackedTarget)
        end
    else
        trackedTarget = nil
        currentTarget = nil
    end
end)


------------------------------------------------------------
-- ONGLET HUMANOID
------------------------------------------------------------
local HumanoidTab = Window:MakeTab({ Name = "Humanoid", Icon = "rbxassetid://4483345998", PremiumOnly = false })

local initChar = LocalPlayer.Character
local initHum = initChar and initChar:FindFirstChildOfClass("Humanoid")
_G.CustomSpeed = (initHum and initHum.WalkSpeed) or 16
_G.CustomJump = (initHum and initHum.JumpPower) or 50
_G.CustomHipHeight = (initHum and initHum.HipHeight) or 2.08
_G.CustomFOV = Camera.FieldOfView or 70
_G.UseJumpPowerToggle = (initHum and initHum.UseJumpPower ~= false)

HumanoidTab:AddSlider({ Name = "Vitesse", Min = 16, Max = 150, Default = _G.CustomSpeed, Increment = 2, ValueName = "studs", Callback = function(v) _G.CustomSpeed = v end })
HumanoidTab:AddSlider({ Name = "Saut", Min = 50, Max = 250, Default = _G.CustomJump, Increment = 5, ValueName = "power", Callback = function(v) _G.CustomJump = v end })
HumanoidTab:AddToggle({ Name = "UseJumpPower", Default = _G.UseJumpPowerToggle, Callback = function(v) _G.UseJumpPowerToggle = v end })
HumanoidTab:AddSlider({ Name = "HipHeight", Min = 0, Max = 20, Default = _G.CustomHipHeight, Increment = 0.5, ValueName = "studs", Callback = function(v) _G.CustomHipHeight = v end })
HumanoidTab:AddSlider({ Name = "FOV Caméra", Min = 70, Max = 120, Default = _G.CustomFOV, Increment = 2, ValueName = "deg", Callback = function(v) _G.CustomFOV = v end })

RunService.Heartbeat:Connect(function()
    Camera.FieldOfView = _G.CustomFOV
    local c = LocalPlayer.Character
    local hum = c and c:FindFirstChildOfClass("Humanoid")
    if hum and hum.Health > 0 then
        hum.UseJumpPower = _G.UseJumpPowerToggle
        if not _G.SpinBotEnabled then
            hum.WalkSpeed = _G.CustomSpeed
            if _G.UseJumpPowerToggle then hum.JumpPower = _G.CustomJump else hum.JumpHeight = _G.CustomJump / 7 end
        end
        hum.HipHeight = _G.CustomHipHeight
    end
end)

------------------------------------------------------------
-- ONGLET CAMÉRA + PiP ViewportFrame
------------------------------------------------------------
--========================================================--
--                  ONGLET CAMÉRA - PiP
--              Version restructurée / optimisée
--========================================================--

local CameraTab = Window:MakeTab({
    Name = "Caméra",
    Icon = "rbxassetid://4483345998",
    PremiumOnly = false
})

--========================================================--
-- SERVICES
--========================================================--

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")

local LocalPlayer = Players.LocalPlayer

--========================================================--
-- CONFIGURATION
--========================================================--

local CameraSystem = {
    Enabled = false,
    Target = nil,

    RenderMode = "Proche",
    Corner = "Haut-Droite",

    Gui = nil,
    Frame = nil,
    Viewport = nil,
    Camera = nil,
    WorldModel = nil,
    Title = nil,

    RenderConnection = nil,
    LightingConnection = nil,

    TargetClone = nil,
    TargetCharacter = nil,

    PlayerClones = {},
    EnvironmentClones = {},

    LastEnvironmentPosition = Vector3.zero,

    CustomPosition = UDim2.new(0, 10, 0, 10),

    RenderDistance = 120,

    Dragging = false,
    Resizing = false,
    DragInput = nil,
    DragStart = nil,
    StartPosition = nil,
    ResizeStart = nil,
    StartSize = nil
}

--========================================================--
-- CONSTANTES UI
--========================================================--

local CORNER_CONFIG = {
    ["Haut-Droite"] = {
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -10, 0, 10)
    },

    ["Haut-Gauche"] = {
        AnchorPoint = Vector2.new(0, 0),
        Position = UDim2.new(0, 10, 0, 10)
    },

    ["Bas-Droite"] = {
        AnchorPoint = Vector2.new(1, 1),
        Position = UDim2.new(1, -10, 1, -10)
    },

    ["Bas-Gauche"] = {
        AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.new(0, 10, 1, -10)
    },

    ["Custom"] = {
        AnchorPoint = Vector2.new(0, 0)
    }
}

--========================================================--
-- UTILITAIRES
--========================================================--

local function safeDestroy(instance)
    if instance then
        pcall(function()
            instance:Destroy()
        end)
    end
end

local function disconnect(connection)
    if connection then
        pcall(function()
            connection:Disconnect()
        end)
    end
end

local function setTransparencyRecursive(instance, transparency)
    if not instance then
        return
    end

    for _, descendant in ipairs(instance:GetDescendants()) do
        pcall(function()
            if descendant:IsA("BasePart") then
                descendant.Transparency = transparency

            elseif descendant:IsA("Decal") or descendant:IsA("Texture") then
                descendant.Transparency = transparency
            end
        end)
    end
end

--========================================================--
-- NETTOYAGE DES CLONES
--========================================================--

function CameraSystem:CleanClone(clone)
    if not clone then
        return nil
    end

    for _, descendant in ipairs(clone:GetDescendants()) do
        if descendant:IsA("LuaSourceContainer")
            or descendant:IsA("Sound")
            or descendant:IsA("TouchTransmitter")
        then
            pcall(function()
                descendant:Destroy()
            end)
        end
    end

    return clone
end

--========================================================--
-- POSITION DU PiP
--========================================================--

function CameraSystem:SetPosition(corner)
    if not self.Frame then
        return
    end

    self.Corner = corner

    local config = CORNER_CONFIG[corner]

    if not config then
        config = CORNER_CONFIG["Haut-Droite"]
        self.Corner = "Haut-Droite"
    end

    self.Frame.AnchorPoint = config.AnchorPoint

    if corner == "Custom" then
        self.Frame.Position = self.CustomPosition
    else
        self.Frame.Position = config.Position
    end
end

function CameraSystem:SaveCustomPosition()
    if self.Frame and self.Corner == "Custom" then
        self.CustomPosition = self.Frame.Position
    end
end

--========================================================--
-- DÉPLACEMENT / REDIMENSIONNEMENT
--========================================================--

function CameraSystem:SetupInteraction()
    if not self.Frame or not self.Title then
        return
    end

    local resizeTrigger = Instance.new("Frame")
    resizeTrigger.Name = "ResizeHandle"
    resizeTrigger.Size = UDim2.new(0, 15, 0, 15)
    resizeTrigger.Position = UDim2.new(1, -15, 1, -15)
    resizeTrigger.BackgroundColor3 = Color3.fromRGB(150, 150, 150)
    resizeTrigger.BackgroundTransparency = 0.35
    resizeTrigger.BorderSizePixel = 0
    resizeTrigger.ZIndex = 10
    resizeTrigger.Parent = self.Frame

    local resizeCorner = Instance.new("UICorner")
    resizeCorner.CornerRadius = UDim.new(1, 0)
    resizeCorner.Parent = resizeTrigger

    --====================================================--
    -- DRAG
    --====================================================--

    self.Title.InputBegan:Connect(function(input)
        if self.Corner ~= "Custom" then
            return
        end

        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            self.Dragging = true
            self.DragStart = input.Position
            self.StartPosition = self.Frame.Position
        end
    end)

    self.Title.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement then
            self.DragInput = input
        end
    end)

    --====================================================--
    -- RESIZE
    --====================================================--

    resizeTrigger.InputBegan:Connect(function(input)
        if self.Corner ~= "Custom" then
            return
        end

        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            self.Resizing = true
            self.ResizeStart = input.Position
            self.StartSize = self.Frame.Size
        end
    end)

    --====================================================--
    -- FIN DE L'INTERACTION
    --====================================================--

    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            self.Dragging = false
            self.Resizing = false
        end
    end)

    --====================================================--
    -- MOUVEMENT / RESIZE
    --====================================================--

    UserInputService.InputChanged:Connect(function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseMovement then
            return
        end

        -- Déplacement
        if self.Dragging and self.DragStart and self.StartPosition then
            local delta = input.Position - self.DragStart

            self.Frame.Position = UDim2.new(
                self.StartPosition.X.Scale,
                self.StartPosition.X.Offset + delta.X,
                self.StartPosition.Y.Scale,
                self.StartPosition.Y.Offset + delta.Y
            )

            self:SaveCustomPosition()
        end

        -- Redimensionnement
        if self.Resizing and self.ResizeStart and self.StartSize then
            local delta = input.Position - self.ResizeStart

            local width = math.max(
                160,
                self.StartSize.X.Offset + delta.X
            )

            local height = math.max(
                120,
                self.StartSize.Y.Offset + delta.Y
            )

            self.Frame.Size = UDim2.new(
                0,
                width,
                0,
                height
            )
        end
    end)
end

--========================================================--
-- NETTOYAGE DE L'ENVIRONNEMENT
--========================================================--

function CameraSystem:ClearEnvironment()
    if not self.WorldModel then
        return
    end

    for _, clone in ipairs(self.EnvironmentClones) do
        safeDestroy(clone)
    end

    table.clear(self.EnvironmentClones)
end

--========================================================--
-- RENDU DE L'ENVIRONNEMENT
--========================================================--

function CameraSystem:RefreshEnvironment(centerPosition)
    if not self.WorldModel then
        return
    end

    self:ClearEnvironment()

    for _, instance in ipairs(workspace:GetDescendants()) do
        if instance:IsA("BasePart")
            and not instance:IsDescendantOf(Players)
            and not instance:IsDescendantOf(self.WorldModel)
        then
            local shouldClone = false

            if self.RenderMode == "Tout" then
                shouldClone = true
            else
                local distance = (
                    instance.Position - centerPosition
                ).Magnitude

                shouldClone = distance <= self.RenderDistance
            end

            if shouldClone then
                local oldArchivable = instance.Archivable

                pcall(function()
                    instance.Archivable = true

                    local clone = instance:Clone()

                    if clone then
                        clone.Name = "EnvironmentPart"
                        clone.Parent = self.WorldModel

                        table.insert(
                            self.EnvironmentClones,
                            clone
                        )
                    end
                end)

                instance.Archivable = oldArchivable
            end
        end
    end

    self.LastEnvironmentPosition = centerPosition
end

--========================================================--
-- CRÉATION DU CLONE D'UN JOUEUR
--========================================================--

function CameraSystem:CreatePlayerClone(player)
    if not player or not player.Character or not self.WorldModel then
        return nil
    end

    local character = player.Character
    local userId = player.UserId

    -- Déjà présent
    if self.PlayerClones[userId] then
        return self.PlayerClones[userId]
    end

    local oldArchivable = character.Archivable
    local clone

    pcall(function()
        character.Archivable = true
        clone = character:Clone()
    end)

    character.Archivable = oldArchivable

    if not clone then
        return nil
    end

    clone.Name = "Player_" .. tostring(userId)

    self:CleanClone(clone)

    --====================================================--
    -- Cacher tête / accessoires de la cible
    --====================================================--

    if player == self.Target then
        for _, descendant in ipairs(clone:GetDescendants()) do
            pcall(function()
                if descendant:IsA("BasePart")
                    and (
                        descendant.Name == "Head"
                        or descendant:IsDescendantOf(
                            descendant.Parent
                        )
                    )
                then
                    -- Rien ici volontairement :
                    -- traitement détaillé juste après.
                end
            end)
        end

        local head = clone:FindFirstChild("Head", true)

        if head then
            pcall(function()
                if head:IsA("BasePart") then
                    head.Transparency = 1
                end
            end)
        end

        for _, descendant in ipairs(clone:GetDescendants()) do
            if descendant:IsA("Accessory") then
                setTransparencyRecursive(descendant, 1)
            end
        end
    end

    --====================================================--
    -- Highlight du joueur local
    --====================================================--

    if player == LocalPlayer then
        local highlight = Instance.new("Highlight")

        highlight.Name = "LocalPlayerHighlight"
        highlight.FillColor = Color3.new(1, 1, 1)
        highlight.FillTransparency = 0.2
        highlight.OutlineColor = Color3.new(1, 1, 1)
        highlight.OutlineTransparency = 0
        highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        highlight.Parent = clone
    end

    clone.Parent = self.WorldModel

    self.PlayerClones[userId] = clone

    return clone
end

--========================================================--
-- SUPPRESSION D'UN CLONE JOUEUR
--========================================================--

function CameraSystem:RemovePlayerClone(player)
    if not player then
        return
    end

    local clone = self.PlayerClones[player.UserId]

    if clone then
        safeDestroy(clone)
        self.PlayerClones[player.UserId] = nil
    end
end

--========================================================--
-- NETTOYAGE DES CLONES JOUEURS
--========================================================--

function CameraSystem:ClearPlayerClones()
    for userId, clone in pairs(self.PlayerClones) do
        safeDestroy(clone)
        self.PlayerClones[userId] = nil
    end
end

--========================================================--
-- GESTION DU JOUEUR CIBLE
--========================================================--

function CameraSystem:SetTarget(player)
    -- Suppression ancienne cible
    if self.Target and self.Target ~= player then
        self:RemovePlayerClone(self.Target)
    end

    self.Target = player
    self.TargetClone = nil
    self.TargetCharacter = nil

    if not player then
        if self.Title then
            self.Title.Text = "POV : Aucun joueur"
        end

        return
    end

    if not player.Character then
        if self.Title then
            self.Title.Text = "POV : " .. player.Name
        end

        return
    end

    self:CreateTargetClone()

    if self.Title then
        self.Title.Text = "POV : " .. player.Name
    end
end

--========================================================--
-- CRÉATION DU CLONE DE LA CIBLE
--========================================================--

function CameraSystem:CreateTargetClone()
    if not self.Target or not self.Target.Character then
        return nil
    end

    local target = self.Target
    local character = target.Character

    -- Supprime ancien clone
    self:RemovePlayerClone(target)

    local clone = self:CreatePlayerClone(target)

    if not clone then
        return nil
    end

    self.TargetClone = clone
    self.TargetCharacter = character

    local root = character:FindFirstChild("HumanoidRootPart")

    if root then
        self.LastEnvironmentPosition = root.Position
        self:RefreshEnvironment(root.Position)
    end

    return clone
end

--========================================================--
-- MISE À JOUR DES JOUEURS
--========================================================--

function CameraSystem:UpdatePlayers(headPosition)
    if not self.WorldModel or not self.Target then
        return
    end

    for _, player in ipairs(Players:GetPlayers()) do
        if player.Character
            and player.Character:FindFirstChild("HumanoidRootPart")
        then
            local root = player.Character.HumanoidRootPart

            local distance = (
                root.Position - headPosition
            ).Magnitude

            local shouldDisplay =
                player == self.Target
                or self.RenderMode == "Tout"
                or distance <= self.RenderDistance

            local clone = self.PlayerClones[player.UserId]

            if shouldDisplay then
                if not clone then
                    clone = self:CreatePlayerClone(player)
                end

                if clone then
                    pcall(function()
                        clone:PivotTo(
                            player.Character:GetPivot()
                        )
                    end)
                end
            elseif clone then
                self:RemovePlayerClone(player)
            end
        elseif self.PlayerClones[player.UserId] then
            self:RemovePlayerClone(player)
        end
    end
end

--========================================================--
-- MISE À JOUR DE LA CAMÉRA
--========================================================--

function CameraSystem:UpdateCamera()
    if not self.Camera then
        return
    end

    if not self.Target
        or not self.Target.Character
    then
        return
    end

    local head = self.Target.Character:FindFirstChild("Head")

    if not head then
        return
    end

    -- Caméra légèrement devant les yeux
    pcall(function()
        self.Camera.CFrame =
            head.CFrame
            * CFrame.new(0, 0, -0.75)
    end)
end

--========================================================--
-- MISE À JOUR DU CLONE CIBLE
--========================================================--

function CameraSystem:UpdateTarget()
    if not self.Target then
        return
    end

    if not self.Target.Character then
        return
    end

    local character = self.Target.Character

    -- Respawn / nouveau Character
    if self.TargetCharacter ~= character
        or not self.TargetClone
        or not self.TargetClone.Parent
    then
        self:CreateTargetClone()
        return
    end

    pcall(function()
        self.TargetClone:PivotTo(
            character:GetPivot()
        )
    end)
end

--========================================================--
-- ENVIRONNEMENT
--========================================================--

function CameraSystem:UpdateEnvironment()
    if not self.Target
        or not self.Target.Character
    then
        return
    end

    local root =
        self.Target.Character:FindFirstChild(
            "HumanoidRootPart"
        )

    if not root then
        return
    end

    local currentPosition = root.Position

    if (
        currentPosition
        - self.LastEnvironmentPosition
    ).Magnitude > 15
    then
        self:RefreshEnvironment(currentPosition)
    end
end

--========================================================--
-- LABEL
--========================================================--

function CameraSystem:UpdateTitle()
    if not self.Title then
        return
    end

    if self.Target then
        self.Title.Text =
            "POV : " .. self.Target.Name
    else
        self.Title.Text =
            "POV : Aucun joueur"
    end
end

--========================================================--
-- BOUCLE PRINCIPALE
--========================================================--

function CameraSystem:StartUpdateLoop()
    disconnect(self.RenderConnection)

    self.RenderConnection =
        RunService.RenderStepped:Connect(function()
            if not self.Enabled then
                return
            end

            if not self.Target
                or not self.Target.Character
                or not self.Camera
                or not self.WorldModel
            then
                return
            end

            local head =
                self.Target.Character:FindFirstChild("Head")

            if not head then
                return
            end

            self:UpdateCamera()
            self:UpdateTarget()
            self:UpdatePlayers(head.Position)
            self:UpdateEnvironment()
            self:UpdateTitle()
        end)
end

--========================================================--
-- CRÉATION DU PiP
--========================================================--

function CameraSystem:Create()
    self:Destroy()

local playerGui =
    LocalPlayer:WaitForChild("PlayerGui")

    --====================================================--
    -- SCREEN GUI
    --====================================================--

    self.Gui = Instance.new("ScreenGui")
    self.Gui.Name = "NexusPiP"
    self.Gui.ResetOnSpawn = false
    self.Gui.IgnoreGuiInset = true
    self.Gui.ZIndexBehavior =
        Enum.ZIndexBehavior.Sibling
    self.Gui.Parent = playerGui

    --====================================================--
    -- FRAME PRINCIPAL
    --====================================================--

    self.Frame = Instance.new("Frame")
    self.Frame.Name = "PiPFrame"
    self.Frame.Size =
        UDim2.new(0, 240, 0, 180)
    self.Frame.BackgroundColor3 =
        Color3.fromRGB(10, 10, 12)
    self.Frame.BorderSizePixel = 0
    self.Frame.Parent = self.Gui

    local frameCorner =
        Instance.new("UICorner")

    frameCorner.CornerRadius =
        UDim.new(0, 8)

    frameCorner.Parent = self.Frame

    local stroke =
        Instance.new("UIStroke")

    stroke.Color =
        Color3.fromRGB(80, 80, 100)

    stroke.Thickness = 1
    stroke.Parent = self.Frame

    --====================================================--
    -- TITRE
    --====================================================--

    self.Title = Instance.new("TextLabel")
    self.Title.Name = "Title"
    self.Title.Size =
        UDim2.new(1, 0, 0, 22)
    self.Title.BackgroundTransparency = 1
    self.Title.Font = Enum.Font.GothamBold
    self.Title.TextSize = 11
    self.Title.TextColor3 =
        Color3.new(1, 1, 1)
    self.Title.Text =
        "POV : Aucun joueur"
    self.Title.ZIndex = 5
    self.Title.Parent = self.Frame

    --====================================================--
    -- VIEWPORT
    --====================================================--

    self.Viewport = Instance.new("ViewportFrame")
    self.Viewport.Name = "Viewport"
    self.Viewport.Size =
        UDim2.new(1, -8, 1, -28)
    self.Viewport.Position =
        UDim2.new(0, 4, 0, 24)

    self.Viewport.BackgroundColor3 =
        Color3.fromRGB(25, 25, 30)

    self.Viewport.BorderSizePixel = 0

    self.Viewport.Ambient = Lighting.Ambient
    self.Viewport.LightColor =
        Lighting.OutdoorAmbient

    self.Viewport.Parent = self.Frame

    local viewportCorner =
        Instance.new("UICorner")

    viewportCorner.CornerRadius =
        UDim.new(0, 6)

    viewportCorner.Parent = self.Viewport

    --====================================================--
    -- CAMERA
    --====================================================--

    self.Camera = Instance.new("Camera")
    self.Camera.Name = "PiPCamera"
    self.Camera.FieldOfView = 75
    self.Camera.Parent = self.Viewport

    self.Viewport.CurrentCamera = self.Camera

    --====================================================--
    -- WORLD MODEL
    --====================================================--

    self.WorldModel =
        Instance.new("WorldModel")

    self.WorldModel.Name = "PiPWorld"
    self.WorldModel.Parent = self.Viewport

    --====================================================--
    -- POSITION
    --====================================================--

    self:SetPosition(self.Corner)

    --====================================================--
    -- INTERACTION
    --====================================================--

    self:SetupInteraction()

    --====================================================--
    -- LIGHTING SYNC
    --====================================================--

    disconnect(self.LightingConnection)

    self.LightingConnection =
        Lighting:GetPropertyChangedSignal(
            "Ambient"
        ):Connect(function()
            if self.Viewport then
                self.Viewport.Ambient =
                    Lighting.Ambient
            end

            if self.Viewport then
                self.Viewport.LightColor =
                    Lighting.OutdoorAmbient
            end
        end)

    --====================================================--
    -- UPDATE
    --====================================================--

    self:StartUpdateLoop()

    --====================================================--
    -- TARGET INITIAL
    --====================================================--

    if self.Target then
        self:CreateTargetClone()
    end
end

--========================================================--
-- DESTRUCTION DU PiP
--========================================================--

function CameraSystem:Destroy()
    disconnect(self.RenderConnection)
    disconnect(self.LightingConnection)

    self.RenderConnection = nil
    self.LightingConnection = nil

    self:ClearPlayerClones()
    self:ClearEnvironment()

    safeDestroy(self.Gui)

    self.Gui = nil
    self.Frame = nil
    self.Viewport = nil
    self.Camera = nil
    self.WorldModel = nil
    self.Title = nil

    self.TargetClone = nil
    self.TargetCharacter = nil

    self.Dragging = false
    self.Resizing = false
    self.DragInput = nil
    self.DragStart = nil
    self.StartPosition = nil
    self.ResizeStart = nil
    self.StartSize = nil
end

--========================================================--
-- ACTIVATION / DÉSACTIVATION
--========================================================--

function CameraSystem:SetEnabled(value)
    self.Enabled = value

    if value then
        self:Create()
    else
        self:Destroy()
    end
end

--========================================================--
-- MODE DE RENDU
--========================================================--

function CameraSystem:SetRenderMode(mode)
    if mode == "Tout le Workspace" then
        self.RenderMode = "Tout"
    else
        self.RenderMode = "Proche"
    end

    if not self.Enabled
        or not self.Target
        or not self.Target.Character
    then
        return
    end

    local root =
        self.Target.Character:FindFirstChild(
            "HumanoidRootPart"
        )

    if root then
        self:RefreshEnvironment(root.Position)
    end
end

--========================================================--
-- RESET CAMÉRA RÉELLE
--========================================================--

local function ResetRealCamera()
    local currentCamera =
        workspace.CurrentCamera

    if not currentCamera then
        return
    end

    currentCamera.CameraType =
        Enum.CameraType.Custom

    local character =
        LocalPlayer.Character

    if not character then
        return
    end

    local humanoid =
        character:FindFirstChildOfClass(
            "Humanoid"
        )

    if humanoid then
        currentCamera.CameraSubject =
            humanoid
    end
end

--========================================================--
-- LISTE DES JOUEURS
--========================================================--

local PlayerDropdown

local function RefreshPlayerList()
    local options = {
        "Aucun"
    }

    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            table.insert(
                options,
                player.Name
            )
        end
    end

    if PlayerDropdown then
        PlayerDropdown:Refresh(
            options,
            true
        )
    end
end

--========================================================--
-- UI - POSITION
--========================================================--

CameraTab:AddDropdown({
    Name = "Position PiP",

    Default = "Haut-Droite",

    Options = {
        "Haut-Droite",
        "Haut-Gauche",
        "Bas-Droite",
        "Bas-Gauche",
        "Custom"
    },

    Callback = function(value)
        CameraSystem:SetPosition(value)
    end
})

--========================================================--
-- UI - MODE RENDU
--========================================================--

CameraTab:AddDropdown({
    Name = "Mode Rendu Décor",

    Default = "Proche uniquement",

    Options = {
        "Proche uniquement",
        "Tout le Workspace"
    },

    Callback = function(value)
        CameraSystem:SetRenderMode(value)
    end
})

--========================================================--
-- UI - ACTIVATION
--========================================================--

CameraTab:AddToggle({
    Name = "Mini caméra POV (ViewportFrame)",

    Default = false,

    Callback = function(value)
        CameraSystem:SetEnabled(value)
    end
})

--========================================================--
-- UI - RESET CAMÉRA
--========================================================--

CameraTab:AddButton({
    Name = "↩ Réinitialiser ma caméra",

    Callback = function()
        ResetRealCamera()
    end
})

--========================================================--
-- UI - SÉLECTION JOUEUR
--========================================================--

PlayerDropdown = CameraTab:AddDropdown({
    Name = "Sélectionner Joueur (PiP)",

    Default = "Aucun",

    Options = {
        "Aucun"
    },

    Callback = function(value)
        -- IMPORTANT :
        -- "Aucun" désélectionne réellement la cible.
        if value == "Aucun" then
            CameraSystem:SetTarget(nil)
            return
        end

        local player =
            Players:FindFirstChild(value)

        if not player
            or player == LocalPlayer
        then
            return
        end

        CameraSystem:SetTarget(player)
    end
})

--========================================================--
-- EVENTS JOUEURS
--========================================================--


Players.PlayerAdded:Connect(function(player)
    RefreshPlayerList()

    player.CharacterAdded:Connect(function()
        task.delay(0.2, function()
            if MatchState.Ended then
                return
            end

            task.spawn(waitAndScanGameTeams)
        end)
    end)
end)

for _, player in ipairs(Players:GetPlayers()) do
    if player ~= LocalPlayer then
        player.CharacterAdded:Connect(function()
            task.delay(0.2, function()
                if not MatchState.Ended then
                    task.spawn(waitAndScanGameTeams)
                end
            end)
        end)
    end
end

Players.PlayerRemoving:Connect(function(player)
    if CameraSystem.Target == player then
        CameraSystem:SetTarget(nil)
    end

    CameraSystem:RemovePlayerClone(player)

    RefreshPlayerList()
end)

--========================================================--
-- INITIALISATION
--========================================================--

RefreshPlayerList()

------------------------------------------------------------
-- ONGLET GIVE
------------------------------------------------------------
local GiveTab = Window:MakeTab({ Name = "Give", Icon = "rbxassetid://4483345998", PremiumOnly = false })

GiveTab:AddButton({
    Name = "🔍 Scanner objets givables",
    Callback = function()
        sendNotification("Scanner", "Recherche en cours...")
        local count = 0
        for _, location in ipairs({ game:GetService("ReplicatedStorage"), Workspace }) do
            for _, object in ipairs(location:GetDescendants()) do
                if object:IsA("Tool") then
                    count = count + 1
                    GiveTab:AddButton({
                        Name = "Give: " .. object.Name,
                        Callback = function()
                            local backpack = LocalPlayer:FindFirstChild("Backpack")
                            if backpack then
                                object:Clone().Parent = backpack
                                sendNotification("Give", "Objet ajouté : " .. object.Name)
                            end
                        end,
                    })
                end
            end
        end
        sendNotification("Scanner", count > 0 and (count .. " objets trouvés.") or "Aucun objet trouvé.")
    end,
})


------------------------------------------------------------
-- ONGLET ESP (nettoyage tracers + alliés verts)
------------------------------------------------------------
local ESPTab = Window:MakeTab({ Name = "ESP", Icon = "rbxassetid://4483345998", PremiumOnly = false })
local activeTracers = {}

local function cleanupTracer(player)
    if activeTracers[player] then
        pcall(function() activeTracers[player]:Remove() end)
        activeTracers[player] = nil
    end
end

Players.PlayerRemoving:Connect(function(player)
    cleanupTracer(player)
    whitelistedAllies[player] = nil
    if AITarget == player then
        AITarget = nil
        AITargetLastVisible = false
    end
end)

ESPTab:AddDropdown({ Name = "Type ESP", Default = "Highlight", Options = {"Highlight", "Désactivé"}, Callback = function(v) _G.ESPMode = v end })
ESPTab:AddToggle({ Name = "Tracers", Default = false, Callback = function(v) _G.TracersEnabled = v end })
ESPTab:AddColorpicker({ Name = "Couleur ennemis", Default = Color3.fromRGB(255, 0, 0), Callback = function(v) _G.ESPColor = v end })

RunService.RenderStepped:Connect(function()
    Camera = workspace.CurrentCamera or Camera

    local seen = {}
    local centerBottom = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y)
    for _, player in ipairs(Players:GetPlayers()) do
        seen[player] = true
        if player ~= LocalPlayer and player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
            local char = player.Character
            local hrp = char.HumanoidRootPart
            local isAlly = whitelistedAllies[player] == true
            local espColor = isAlly and ALLY_COLOR or _G.ESPColor
            local screenPos, onScreen = Camera:WorldToViewportPoint(hrp.Position)

            if _G.TracersEnabled and onScreen and _G.ESPMode ~= "Désactivé" then
                if not activeTracers[player] then
                    activeTracers[player] = Drawing.new("Line")
                    activeTracers[player].Thickness = 1
                    activeTracers[player].Transparency = 1
                end

                local line = activeTracers[player]

                line.From = centerBottom
                line.To = Vector2.new(
                    screenPos.X,
                    screenPos.Y
                )

                line.Color = espColor
                line.Visible = true
            else
                --cleanupTracer(player) 
                if activeTracers[player] then
                    activeTracers[player].Visible = false
                end
            end

            if _G.ESPMode == "Highlight" then
                if isAlly then
                    local enemyHl = char:FindFirstChild("NexusESPHighlight")
                    if enemyHl then enemyHl:Destroy() end

                    local allyHl = char:FindFirstChild("NexusAllyHighlight")
                    if not allyHl then
                        allyHl = Instance.new("Highlight")
                        allyHl.Name = "NexusAllyHighlight"
                        allyHl.Parent = char
                    end
                    allyHl.Adornee = char
                    allyHl.FillColor = ALLY_COLOR
                    allyHl.OutlineColor = ALLY_COLOR
                    allyHl.FillTransparency = 0.45
                    allyHl.Enabled = true
                else
                    local allyHl = char:FindFirstChild("NexusAllyHighlight")
                    if allyHl then allyHl:Destroy() end

                    local enemyHl = char:FindFirstChild("NexusESPHighlight")
                    if not enemyHl then
                        enemyHl = Instance.new("Highlight")
                        enemyHl.Name = "NexusESPHighlight"
                        enemyHl.Parent = char
                    end
                    enemyHl.Adornee = char
                    enemyHl.FillColor = _G.ESPColor
                    enemyHl.OutlineColor = _G.ESPColor
                    enemyHl.FillTransparency = 0.5
                    enemyHl.Enabled = true
                end
            else
                local allyHl = char:FindFirstChild("NexusAllyHighlight")
                local enemyHl = char:FindFirstChild("NexusESPHighlight")
                if allyHl and not isAlly then allyHl:Destroy() end
                if enemyHl then enemyHl:Destroy() end
            end
        else cleanupTracer(player) end
    end
    for player in pairs(activeTracers) do
        if not seen[player] then cleanupTracer(player) end
    end
end)

------------------------------------------------------------
-- ONGLET TÉLÉPORT
------------------------------------------------------------
local TPTab = Window:MakeTab({ Name = "Téléport", Icon = "rbxassetid://4483345998", PremiumOnly = false })
TPTab:AddToggle({ Name = "TP Behind continu", Default = false, Callback = function(v) _G.TPBehindActive = v end })
TPTab:AddButton({
    Name = "🔄 Charger liste TP",
    Callback = function()
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LocalPlayer then
                TPTab:AddButton({
                    Name = "⚡ TP : " .. p.Name,
                    Callback = function()
                        local myHRP = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
                        local tHRP = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
                        if myHRP and tHRP then myHRP.CFrame = tHRP.CFrame * CFrame.new(0, 2, 0) end
                    end,
                })
            end
        end
    end,
})

RunService.RenderStepped:Connect(function()
    if not _G.TPBehindActive or not currentTarget or not isDuelTargetActive(currentTarget) then return end
    local targetHRP = currentTarget.Character and currentTarget.Character:FindFirstChild("HumanoidRootPart")
    local myHRP = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if myHRP and targetHRP then
        myHRP.CFrame = CFrame.new(targetHRP.Position - targetHRP.CFrame.LookVector * tpBehindOffset, targetHRP.Position)
    end
end)

------------------------------------------------------------
-- INITIALISATION DES SERVICES & LOGIQUE (À garder)
------------------------------------------------------------


-- Variables de configuration globales (si pas déjà définies plus haut)
local config = config or {
    FlyEnabled = false,
    FlySpeed = 50,
    FlyVerticalSpeed = 20,
    NoClip = false,
    NoClipType = "Classic",
    NoClipForce = 1,
    ClickTP = false -- Nouvelle option demandée
}

local flyBodyVelocity = nil
local flyBodyGyro = nil
local flyConnections = {}
local tpConnection = nil

------------------------------------------------------------
-- INITIALISATION DES TABLES ET VARIABLES (Obligatoire)
------------------------------------------------------------
local ghostParts = {}
local originalCollisions = {}
local noClipConnection = nil

------------------------------------------------------------
-- FONCTION NOCLIP OPTIMISÉE
------------------------------------------------------------
local function setupNoClip()
    -- 1. Nettoyage propre de l'ancienne connexion pour éviter les fuites de mémoire
    if noClipConnection then
        noClipConnection:Disconnect()
        noClipConnection = nil
    end

    if config.NoClip then
        ----------------------------------------------------
        -- MODE GHOST (Rend transparents les murs touchés)
        ----------------------------------------------------
        if config.NoClipType == "Ghost" then
            noClipConnection = RunService.Stepped:Connect(function()
                local character = LocalPlayer.Character
                if not character then return end
                
                -- Table temporaire pour suivre ce qui touche le joueur à CETTE frame
                local currentFrameParts = {}
                
                for _, part in ipairs(character:GetDescendants()) do
                    if part:IsA("BasePart") then
                        local overlapping = workspace:GetPartsInPart(part)
                        for _, otherPart in ipairs(overlapping) do
                            if otherPart:IsA("BasePart") and otherPart.CanCollide and otherPart.Transparency < 0.5 and not otherPart:IsDescendantOf(character) then
                                currentFrameParts[otherPart] = true
                                if not ghostParts[otherPart] then
                                    -- Sauvegarde de l'état initial
                                    ghostParts[otherPart] = {
                                        transparency = otherPart.Transparency,
                                        canCollide = otherPart.CanCollide
                                    }
                                    otherPart.Transparency = 0.8
                                    otherPart.CanCollide = false
                                end
                            end
                        end
                    end
                end
                
                -- Rétablit les objets qui ne touchent plus du tout le joueur
                for part, data in pairs(ghostParts) do
                    if not currentFrameParts[part] then
                        if part and part.Parent then
                            part.Transparency = data.transparency
                            part.CanCollide = data.canCollide
                        end
                        ghostParts[part] = nil
                    end
                end
            end)
            
        ----------------------------------------------------
        -- MODE CLASSIC (Désactive les collisions du corps entier)
        ----------------------------------------------------
        else
            -- Le mode Classic le plus efficace sur Roblox : forcer le CanCollide à false de TOUT le corps à chaque frame
            noClipConnection = RunService.Stepped:Connect(function()
                local character = LocalPlayer.Character
                if not character then return end
                
                for _, part in ipairs(character:GetDescendants()) do
                    if part:IsA("BasePart") and part.CanCollide then
                        -- Sauvegarde l'état d'origine si inconnu
                        if not originalCollisions[part] then
                            originalCollisions[part] = part.CanCollide
                        end
                        part.CanCollide = false
                    end
                end
            end)
        end
    else
        ----------------------------------------------------
        -- DÉSACTIVATION : RESTAURATION DE LA PHYSIQUE
        ----------------------------------------------------
        -- Restaure le mode Classic
        for part, canCollide in pairs(originalCollisions) do
            if part and part.Parent then
                part.CanCollide = canCollide
            end
        end
        originalCollisions = {}
        
        -- Restaure le mode Ghost
        for part, data in pairs(ghostParts) do
            if part and part.Parent then
                part.Transparency = data.transparency
                part.CanCollide = data.canCollide
            end
        end
        ghostParts = {}
    end
end

local function enableFly()
    if not LocalPlayer.Character then return end
    local hrp = LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    local hum = LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
    if not hrp or not hum then return end
    
    -- Empêche Roblox de forcer le mode marche au sol
    hum.PlatformStand = true
    
    -- Créer les contrôles physiques (Strictement ton code d'origine)
    flyBodyVelocity = Instance.new("BodyVelocity")
    flyBodyVelocity.Velocity = Vector3.new(0, 0, 0)
    flyBodyVelocity.MaxForce = Vector3.new(10000, 10000, 10000)
    flyBodyVelocity.P = 10000
    flyBodyVelocity.Parent = hrp
    
    flyBodyGyro = Instance.new("BodyGyro")
    flyBodyGyro.MaxTorque = Vector3.new(10000, 10000, 10000)
    flyBodyGyro.P = 10000
    flyBodyGyro.D = 100
    flyBodyGyro.CFrame = hrp.CFrame
    flyBodyGyro.Parent = hrp
    
    -- Activer le NoClip (Ton code d'origine)
    config.NoClip = true
    setupNoClip()
    
    -- Connexion des entrées (Strictement ton code d'origine)
    table.insert(flyConnections, UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then return end
        if input.KeyCode == Enum.KeyCode.Space then
            flyBodyVelocity.Velocity = Vector3.new(flyBodyVelocity.Velocity.X, config.FlyVerticalSpeed, flyBodyVelocity.Velocity.Z)
        elseif input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
            flyBodyVelocity.Velocity = Vector3.new(flyBodyVelocity.Velocity.X, -config.FlyVerticalSpeed, flyBodyVelocity.Velocity.Z)
        end
    end))
    
    table.insert(flyConnections, UserInputService.InputEnded:Connect(function(input, gameProcessed)
        if gameProcessed then return end
        if input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
            flyBodyVelocity.Velocity = Vector3.new(flyBodyVelocity.Velocity.X, 0, flyBodyVelocity.Velocity.Z)
        end
    end))
    
    -- Boucle Heartbeat (Strictement ton code d'origine pour les axes)
    table.insert(flyConnections, RunService.Heartbeat:Connect(function()
        if not flyBodyVelocity or not flyBodyGyro then return end
        
        -- On maintient la sécurité pour le sol
        if hum then hum.PlatformStand = true end
        
        -- Mise à jour de la direction
        flyBodyGyro.CFrame = Camera.CFrame
        
        -- Calcul de la vélocité
        local forward = Camera.CFrame.LookVector
        local right = Camera.CFrame.RightVector
        local velocity = Vector3.new(0, 0, 0)
        
        if UserInputService:IsKeyDown(Enum.KeyCode.W) then
            velocity = velocity + forward
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.S) then
            velocity = velocity - forward
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.D) then
            velocity = velocity + right
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.A) then
            velocity = velocity - right
        end
        
        flyBodyVelocity.Velocity = velocity * config.FlySpeed
    end))
end

local function disableFly()
    -- Désactiver le NoClip (Ton code d'origine)
    config.NoClip = false
    setupNoClip()
    
    -- Remet le joueur normal
    local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
    if hum then hum.PlatformStand = false end
    
    -- Supprimer les contrôles physiques (Ton code d'origine)
    if flyBodyVelocity then
        flyBodyVelocity:Destroy()
        flyBodyVelocity = nil
    end
    
    if flyBodyGyro then
        flyBodyGyro:Destroy()
        flyBodyGyro = nil
    end
    
    -- Désactiver les connexions (Ton code d'origine)
    for _, conn in ipairs(flyConnections) do
        conn:Disconnect()
    end
    flyConnections = {}
end



-- Fonction Click TP au clic droit
local function handleClickTeleport(input, gameProcessed)
    if gameProcessed or not config.ClickTP or input.UserInputType ~= Enum.UserInputType.MouseButton2 then
        return
    end
    
    local mousePos = UserInputService:GetMouseLocation()
    local ray = Camera:ViewportPointToRay(mousePos.X, mousePos.Y)
    local raycastParams = RaycastParams.new()
    raycastParams.FilterType = Enum.RaycastFilterType.Blacklist
    raycastParams.FilterDescendantsInstances = {LocalPlayer.Character}
    
    local result = workspace:Raycast(ray.Origin, ray.Direction * 1000, raycastParams)
    if result then
        local position = result.Position
        local character = LocalPlayer.Character
        if character then
            local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
            if humanoidRootPart then
                local safePosition = position + Vector3.new(0, 3, 0)
                humanoidRootPart.CFrame = CFrame.new(safePosition)
            end
        end
    end
end

------------------------------------------------------------
-- INTERFACE GRAPHIQUE ORION LIB
------------------------------------------------------------
-- (On assume que la variable 'Window' est déjà créée plus haut dans ton script principal)

-- 1. Onglet Fly
local FlyTab = Window:MakeTab({
    Name = "Fly",
    Icon = "rbxassetid://4483345998",
    PremiumOnly = false
})

FlyTab:AddToggle({
    Name = "Activer Fly",
    Default = config.FlyEnabled,
    Callback = function(state)
        config.FlyEnabled = state
        if state then enableFly() else disableFly() end
    end
})

FlyTab:AddSlider({
    Name = "Vitesse Fly",
    Min = 1,
    Max = 200,
    Default = config.FlySpeed,
    Color = Color3.fromRGB(255,255,255),
    Increment = 1,
    ValueName = "studs/s",
    Callback = function(value)
        config.FlySpeed = value
    end
})

FlyTab:AddSlider({
    Name = "Vitesse Verticale",
    Min = 1,
    Max = 100,
    Default = config.FlyVerticalSpeed,
    Color = Color3.fromRGB(255,255,255),
    Increment = 1,
    ValueName = "studs/s",
    Callback = function(value)
        config.FlyVerticalSpeed = value
    end
})

-- Ajout de l'option Click TP demandée directement dans l'onglet Fly/Mouvement
FlyTab:AddToggle({
    Name = "Téléportation au Clic Droit (Click TP)",
    Default = config.ClickTP,
    Callback = function(state)
        config.ClickTP = state
        if state then
            if not tpConnection then
                tpConnection = UserInputService.InputBegan:Connect(handleClickTeleport)
            end
        else
            if tpConnection then
                tpConnection:Disconnect()
                tpConnection = nil
            end
        end
    end
})

-- 2. Onglet NoClip
local NoClipTab = Window:MakeTab({
    Name = "NoClip",
    Icon = "rbxassetid://4483345998",
    PremiumOnly = false
})

NoClipTab:AddToggle({
    Name = "Activer NoClip",
    Default = config.NoClip,
    Callback = function(state)
        config.NoClip = state
        setupNoClip()
    end
})

NoClipTab:AddDropdown({
    Name = "Type de NoClip",
    Default = config.NoClipType,
    Options = {"Classic", "Ghost"},
    Callback = function(value)
        config.NoClipType = value
        setupNoClip()
    end
})

NoClipTab:AddSlider({
    Name = "NoClip Force",
    Min = 0.1,
    Max = 5,
    Default = config.NoClipForce,
    Color = Color3.fromRGB(255,255,255),
    Increment = 0.1,
    ValueName = "Force",
    Callback = function(value)
        config.NoClipForce = value
    end
})

------------------------------------------------------------
-- LOGS OVERLAY
------------------------------------------------------------


local function createLogOverlay()
    local playerGui = LocalPlayer:WaitForChild("PlayerGui")
    local old = playerGui:FindFirstChild("NexusV6LogOverlay")
    if old then old:Destroy() end
    logGui = Instance.new("ScreenGui")
    logGui.Name = "NexusV6LogOverlay"
    logGui.ResetOnSpawn = false
    logGui.IgnoreGuiInset = true
    logGui.Parent = playerGui
    local f = Instance.new("Frame")
    f.AnchorPoint = Vector2.new(1, 1)
    f.Position = UDim2.new(1, -18, 1, -18)
    f.Size = UDim2.new(0, 400, 0, 210)
    f.BackgroundColor3 = Color3.fromRGB(15, 15, 18)
    f.BackgroundTransparency = 0.1
    f.BorderSizePixel = 0
    f.Parent = logGui
    Instance.new("UICorner", f).CornerRadius = UDim.new(0, 10)
    logText = Instance.new("TextLabel", f)
    logText.BackgroundTransparency = 1
    logText.Position = UDim2.new(0, 10, 0, 8)
    logText.Size = UDim2.new(1, -20, 1, -16)
    logText.Font = Enum.Font.Gotham
    logText.TextSize = 12
    logText.TextXAlignment = Enum.TextXAlignment.Left
    logText.TextYAlignment = Enum.TextYAlignment.Top
    logText.TextWrapped = true
    logText.TextColor3 = Color3.fromRGB(230, 230, 230)
    logText.Text = "Nexus V6 — Auto-Play"
end
createLogOverlay()

------------------------------------------------------------
-- AUTO-PLAY CONFIG & UI
------------------------------------------------------------
local AutoPlayTab = Window:MakeTab({ Name = "Auto-Play", Icon = "rbxassetid://4483345998", PremiumOnly = false })

local AiSection = AutoPlayTab:AddSection({ Name = "IA" })
local CombatSection = AutoPlayTab:AddSection({ Name = "Combat Couteaux" })
local MoveSection = AutoPlayTab:AddSection({ Name = "Déplacement" })
local CopySection = AutoPlayTab:AddSection({ Name = "Mode Copy" })
local RecordSection = AutoPlayTab:AddSection({ Name = "Enregistreur" })
local DebugSection = AutoPlayTab:AddSection({ Name = "Debug" })

local emergencyStop

AutoPlayConfig = {
    Enabled = false,
    ShowLogs = true,

    Mode = "IA",
    IAStyle = "Aggressive",

    AutoDeaths = 0,
    AutoBaseStyle = "Aggressive",

    AutoLongRangeDeathThreshold = 3,
    AutoAdvancedThreshold = 4,

    AutoWallbang = false,
    AutoAimSmooth = false,

    WalkSpeed = 24,
    DetectionRange = 200,

    MeleeRange = 8,
    KnifeRange = 50,

    LointainMinDist = 28,
    LointainMaxDist = 55,

    WallRange = 7,
    StuckModeSwitchTime = 5,

    StuckTime = 2,
    StuckRecoveryDuration = 0.45,
    StuckRecheckDelay = 0.15,

    JumpCooldown = 0.65,

    SlideCooldown = 1.2,
    SlideHoldDuration = 2.0,

    AttackCooldownM1 = 0.08,
    AttackCooldownM2 = 0.35,

    StrafeEnabled = true,
    StrafeSwitchMin = 0.7,
    StrafeSwitchMax = 1.3,

    M1UseMouse = true,
    M2UseMouse = true,

    CopyLoop = false,
    CopyRelativeCamera = true,
    CopyCameraSmooth = 0.18,
    CopyKeyUpSimulate = 0.14,

    CoverSearchRadius = 24,
    CoverSamples = 12,
    PathRecomputeDelay = 0.75,
}

local storedLogText = ""
local PlaybackEvents = {}
local playbackActive = false
local playbackStartTime = 0
local playbackIndex = 1
local recording = false
local recordStartTime = 0
local recordEvents = {}
local lastCamRecordTime = 0
local copyCameraTarget = nil
local shiftHeldByScript = false
local slideActive, slideEndTime = false, 0


local function getEffectiveIAStyle()
    if AutoPlayConfig.IAStyle ~= "AUTO" then
        return AutoPlayConfig.IAStyle
    end

    local deaths = AutoPlayConfig.AutoDeaths or 0

    -- Après 3 morts :
    -- on passe temporairement en Lointain.
    if deaths >= 3 then
        return "Lointain"
    end

    -- Sinon on garde le style de départ.
    return AutoPlayConfig.AutoBaseStyle
        or "Aggressive"
end

local function registerAIDeath()
    AutoPlayConfig.AutoDeaths =
        AutoPlayConfig.AutoDeaths + 1

    if AutoPlayConfig.IAStyle == "AUTO" then
        local effective = getEffectiveIAStyle()

        pushLog(
            "IA",
            "AUTO → stratégie actuelle : " .. effective
        )
    end

    local deaths =
        AutoPlayConfig.AutoDeaths

    pushLog(
        "IA",
        "Mort détectée #" .. deaths
    )

    -- 3e mort : Lointain
    if AutoPlayConfig.IAStyle == "AUTO"
        and deaths == 3
    then
        pushLog(
            "IA",
            "AUTO : 3 morts → stratégie Lointain."
        )
    end

    -- 4e mort : précision + Wallbang
    if deaths >= 4 then
        _G.AimSmooth = 1
        _G.ThroughWall = true

        pushLog(
            "IA",
            "AUTO : 4+ morts → Aim 10/10 + Wallbang."
        )
    end

    pcall(function()
        OrionLib:SendTelemetryEvent(
            "ai_death",
            "AUTO | Mort #" .. deaths,
            AITarget and AITarget.Name or "None"
        )
    end)
end

local MOVEMENT_KEYS = { W = true, A = true, S = true, D = true, Z = true }

local function eventsToText(events)
    local lines = {}
    for _, ev in ipairs(events) do
        local dataStr
        if ev.type == "CAMERA" then
            local pos, look = ev.data[1], ev.data[2]
            dataStr = string.format("%.2f,%.2f,%.2f;%.2f,%.2f,%.2f", pos.X, pos.Y, pos.Z, look.X, look.Y, look.Z)
        else dataStr = tostring(ev.data) end
        table.insert(lines, string.format("%.3f %s %s", ev.time, ev.type, dataStr))
    end
    return table.concat(lines, "\n")
end

local function normalizeKeyName(name)
    if name == "Z" then return "W" end
    return name
end

-- Répare logs KEY_UP-only : estime la durée d'appui entre deux événements
local function repairPlaybackEvents(events)
    local repaired = {}
    local held = {}
    local syntheticCount = 0

    for _, ev in ipairs(events) do
        local data = ev.data
        local normalized = type(data) == "string" and normalizeKeyName(data) or data

        if ev.type == "KEY_DOWN" then
            if type(normalized) == "string" and MOVEMENT_KEYS[normalized] then
                held[normalized] = true
            end

            table.insert(repaired, {
                time = ev.time,
                type = "KEY_DOWN",
                data = normalized,
            })

        elseif ev.type == "KEY_UP" then
            if type(normalized) == "string" and MOVEMENT_KEYS[normalized] then
                if not held[normalized] then
                    table.insert(repaired, {
                        time = math.max(0, ev.time - AutoPlayConfig.CopyKeyUpSimulate),
                        type = "KEY_DOWN",
                        data = normalized,
                        synthetic = true,
                    })
                    syntheticCount += 1
                end
                held[normalized] = nil
            end

            table.insert(repaired, {
                time = ev.time,
                type = "KEY_UP",
                data = normalized,
            })
        else
            table.insert(repaired, {
                time = ev.time,
                type = ev.type,
                data = normalized,
            })
        end
    end

    table.sort(repaired, function(a, b)
        if a.time == b.time then
            if a.type ~= b.type then
                return a.type == "KEY_DOWN"
            end
            return tostring(a.data) < tostring(b.data)
        end
        return a.time < b.time
    end)

    return repaired, syntheticCount
end

local function parseLogText(raw)
    local events = {}
    local stats = { total = 0, keys = 0, camera = 0, unknown = 0, skipped = 0, repaired = 0 }
    for line in raw:gmatch("[^\r\n]+") do
        line = line:match("^%s*(.-)%s*$")
        if line ~= "" then
            local time, type_, data = line:match("^(%S+)%s+(%S+)%s+(.+)$")
            if time and type_ and data then
                time = tonumber(time)
                if time and (type_ == "KEY_DOWN" or type_ == "KEY_UP" or type_ == "CAMERA") then
                    if type_ == "CAMERA" then
                        local px, py, pz, lx, ly, lz = data:match("^([%-%d%.]+),([%-%d%.]+),([%-%d%.]+);([%-%d%.]+),([%-%d%.]+),([%-%d%.]+)$")
                        if px then
                            table.insert(events, { time = time, type = type_, data = {
                                Vector3.new(tonumber(px), tonumber(py), tonumber(pz)),
                                Vector3.new(tonumber(lx), tonumber(ly), tonumber(lz)),
                            }})
                            stats.camera = stats.camera + 1
                        else stats.skipped = stats.skipped + 1 end
                    else
                        table.insert(events, { time = time, type = type_, data = data })
                        stats.keys = stats.keys + 1
                        if data == "Unknown" then stats.unknown = stats.unknown + 1 end
                    end
                    stats.total = stats.total + 1
                else stats.skipped = stats.skipped + 1 end
            else stats.skipped = stats.skipped + 1 end
        end
    end
    table.sort(events, function(a, b) return a.time < b.time end)
    local repairedEvents, repairedCount = repairPlaybackEvents(events)
    events = repairedEvents
    stats.repaired = repairedCount
    return events, stats
end

local function loadLogsFromText(raw, sourceTag)
    storedLogText = raw or ""
    local events, stats = parseLogText(storedLogText)
    PlaybackEvents = events
    local msg = string.format("%d evt (%d keys, %d cam, %d unk, +%d réparés)",
        stats.total, stats.keys, stats.camera, stats.unknown, stats.repaired)
    pushLog(sourceTag or "COPY", msg)
    sendNotification("Copy", msg)
    return stats
end

--========================================================--
-- DÉTECTION DES ÉQUIPES DU DUEL VIA HIGHLIGHTS DU JEU
--========================================================--

local GAME_TEAMMATE_HIGHLIGHT = "MatchTeammateHighlight"
local GAME_ENEMY_HIGHLIGHT = "MatchEnemyHighlight"

local function hasGameHighlight(player, highlightName)
    local char = player and player.Character

    if not char then
        return false
    end

    local highlight =
        char:FindFirstChild(
            highlightName,
            true
        )

    return highlight ~= nil
end


local function scanGameTeams()
    -- 1v1 : aucun allié attendu.
    if _G.GameModeSetup == "1v1" then
        return
    end

    local detectedAllies = 0
    local detectedEnemies = 0

    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then

            if hasGameHighlight(
                player,
                GAME_TEAMMATE_HIGHLIGHT
            ) then

                whitelistedAllies[player] = true

                applyAllyHighlight(player)

                detectedAllies += 1

            elseif hasGameHighlight(
                player,
                GAME_ENEMY_HIGHLIGHT
            ) then

                -- Si le joueur était anciennement
                -- protégé, on l'enlève.
                whitelistedAllies[player] = nil

                clearAllyHighlight(player)

                detectedEnemies += 1
            end
        end
    end

    pushLog(
        "MATCH",
        string.format(
            "Scan équipes | alliés=%d ennemis=%d",
            detectedAllies,
            detectedEnemies
        )
    )
end


local function waitAndScanGameTeams()
    -- Attendre que les Highlights du round apparaissent.
    for _ = 1, 40 do
        scanGameTeams()
        task.wait(0.1)
    end
end

AiSection:AddToggle({
    Name = "Activer Auto-Play",
    Default = false,
    Callback = function(v)
        AutoPlayConfig.Enabled = v
        if v then aimbotActive = true if fovCircle then fovCircle.Visible = true end end
        pushLog("SYSTEM", v and "Auto-Play ON" or "Auto-Play OFF")
    end,
})

AiSection:AddDropdown({
    Name = "Style IA",
    Default = "Aggressive",

    Options = {
        "Aggressive",
        "Defensive",
        "Mixed",
        "Lointain",
        "AUTO"
    },

    Callback = function(v)
        AutoPlayConfig.IAStyle = v

        if v ~= "AUTO" then
            AutoPlayConfig.AutoBaseStyle = v
        end

        pushLog(
            "IA",
            "Style sélectionné : " .. v
        )
    end,
})
AiSection:AddToggle({ Name = "Overlay logs", Default = true, Callback = function(v) AutoPlayConfig.ShowLogs = v setLogVisible(v) end })

CombatSection:AddToggle({ Name = "M1 = clic gauche (sinon Q)", Default = true, Callback = function(v) AutoPlayConfig.M1UseMouse = v end })
CombatSection:AddToggle({ Name = "M2 = clic droit (sinon Q/A)", Default = true, Callback = function(v) AutoPlayConfig.M2UseMouse = v end })
CombatSection:AddSlider({ Name = "Portée M1", Min = 3, Max = 15, Default = 8, Increment = 1, Callback = function(v) AutoPlayConfig.MeleeRange = v end })
CombatSection:AddSlider({ Name = "Portée lancer", Min = 15, Max = 80, Default = 50, Increment = 1, Callback = function(v) AutoPlayConfig.KnifeRange = v end })
CombatSection:AddSlider({ Name = "Cooldown M2", Min = 0.1, Max = 1, Default = 0.35, Increment = 0.05, Callback = function(v) AutoPlayConfig.AttackCooldownM2 = v end })

MoveSection:AddSlider({ Name = "Vitesse IA", Min = 8, Max = 32, Default = 24, Increment = 1, Callback = function(v) AutoPlayConfig.WalkSpeed = v end })
MoveSection:AddSlider({ Name = "Détection ennemi", Min = 20, Max = 200, Default = 200, Increment = 5, Callback = function(v) AutoPlayConfig.DetectionRange = v end })
MoveSection:AddSlider({ Name = "Distance murs", Min = 3, Max = 15, Default = 7, Increment = 1, Callback = function(v) AutoPlayConfig.WallRange = v end })
MoveSection:AddSlider({ Name = "Temps blocage", Min = 0.3, Max = 2, Default = 0.85, Increment = 0.05, Callback = function(v) AutoPlayConfig.StuckTime = v end })
MoveSection:AddSlider({ Name = "Durée slide (C maintenu)", Min = 1, Max = 3, Default = 2, Increment = 0.1, Callback = function(v) AutoPlayConfig.SlideHoldDuration = v end })

CopySection:AddButton({ Name = "📋 Importer presse-papier", Callback = function()
    local ok, clip = pcall(function() return getclipboard() end)
    if ok and clip and clip ~= "" then loadLogsFromText(clip, "IMPORT") else sendNotification("Copy", "Presse-papier vide.") end
end })

CopySection:AddButton({ Name = "📄 Parser logs", Callback = function()
    local ok, clip = pcall(function() return getclipboard() end)
    if ok and clip and clip ~= "" then loadLogsFromText(clip, "PARSE")
    elseif storedLogText ~= "" then loadLogsFromText(storedLogText, "PARSE")
    else sendNotification("Copy", "Aucun log.") end
end })

CopySection:AddToggle({ Name = "Boucle Copy", Default = false, Callback = function(v) AutoPlayConfig.CopyLoop = v end })
CopySection:AddToggle({ Name = "Caméra relative", Default = false, Callback = function(v) AutoPlayConfig.CopyRelativeCamera = v end })
CopySection:AddSlider({ Name = "Lissage cam Copy", Min = 0.05, Max = 0.5, Default = 0.18, Increment = 0.01, Callback = function(v) AutoPlayConfig.CopyCameraSmooth = v end })

CopySection:AddButton({ Name = "▶ Lecture (P)", Callback = function()
    if #PlaybackEvents == 0 then
        sendNotification("Copy", "Aucun événement parsé.")
        return
    end
    playbackActive = true
    playbackStartTime = os.clock()
    playbackIndex = 1
    copyCameraTarget = nil
    firstCameraLook = nil
    table.clear(pendingReleases)
    pushLog("COPY", "Lecture " .. #PlaybackEvents .. " evt")
end })

RecordSection:AddButton({ Name = "⏺ REC (L)", Callback = function()
    if not recording then
        recording = true
        recordStartTime = os.clock()
        recordEvents = {}
        lastCamRecordTime = 0
        sendNotification("REC", "REC ON (L stop)")
    end
end })

RecordSection:AddButton({ Name = "⏹ Stop & copier", Callback = function()
    if not recording then return end
    recording = false
    storedLogText = eventsToText(recordEvents)
    PlaybackEvents = select(1, parseLogText(storedLogText))
    pcall(function() setclipboard(storedLogText) end)
    sendNotification("REC", #recordEvents .. " events copiés")
end })

DebugSection:AddButton({
    Name = "⛔ STOP IA / INPUTS",
    Callback = emergencyStop,
})

DebugSection:AddParagraph("Info", "L=REC | P=Copy | J=Aimbot | V=Alliés | C=Slide | Shift=Sprint")

OrionLib:MakeNotification({ Name = "Nexus V6", Content = "Duels de Couteaux — V6 chargée.", Time = 5 })

------------------------------------------------------------
-- INPUT SIMULATION
------------------------------------------------------------
local keysDown = {}
local copyKeysDown = {}
local currentMoveKeys = {}
local pendingReleases = {}
local firstCameraLook = nil

local KEY_ALIASES = {
    Unknown = "Q",
    L = "MouseLeft",
    Left = "MouseLeft",
    MouseLeft = "MouseLeft",
    MouseButton1 = "MouseLeft",
    MouseRight = "MouseRight",
    MouseButton2 = "MouseRight",
    Right = "MouseRight",
    Z = "W",
}

local KEYCODE_MAP = {
    W = Enum.KeyCode.W, A = Enum.KeyCode.A, S = Enum.KeyCode.S, D = Enum.KeyCode.D,
    Space = Enum.KeyCode.Space, LeftShift = Enum.KeyCode.LeftShift,
    C = Enum.KeyCode.C, Q = Enum.KeyCode.Q, E = Enum.KeyCode.E,
}

local function getMousePos() return UserInputService:GetMouseLocation() end

local function resolveInputName(name)
    name = normalizeKeyName(name)
    local resolved = KEY_ALIASES[name] or name
    if resolved == "MouseLeft" or resolved == "MouseRight" then return "mouse", resolved end
    local kc = KEYCODE_MAP[resolved]
    if not kc then
        local ok, ek = pcall(function() return Enum.KeyCode[resolved] end)
        if ok and ek then kc = ek end
    end
    if kc then return "key", kc end
    return nil
end

local function isKeyHeld(name)
    name = normalizeKeyName(name)
    local kind, code = resolveInputName(name)
    if kind == "key" then return keysDown[code] == true end
    if kind == "mouse" then return copyKeysDown[code] == true end
    return false
end

local function pressInput(name, isCopy)
    name = normalizeKeyName(name)
    local kind, code = resolveInputName(name)
    if not kind then return end
    if kind == "mouse" then
        local pos = getMousePos()
        local btn = (code == "MouseLeft") and 0 or 1
        VirtualInputManager:SendMouseButtonEvent(pos.X, pos.Y, btn, true, game, 0)
        copyKeysDown[code] = true
    else
        if not keysDown[code] then
            VirtualInputManager:SendKeyEvent(true, code, false, game)
            keysDown[code] = true
        end
    end
end

local function releaseInput(name)
    name = normalizeKeyName(name)
    local kind, code = resolveInputName(name)
    if not kind then return end
    if kind == "mouse" then
        local pos = getMousePos()
        local btn = (code == "MouseLeft") and 0 or 1
        VirtualInputManager:SendMouseButtonEvent(pos.X, pos.Y, btn, false, game, 0)
        copyKeysDown[code] = nil
    else
        if keysDown[code] then
            VirtualInputManager:SendKeyEvent(false, code, false, game)
            keysDown[code] = nil
        end
    end
end

local function scheduleRelease(name, delay)
    table.insert(pendingReleases, { time = os.clock() + delay, name = name })
end

local function releaseShift()
    if shiftHeldByScript then
        releaseInput("LeftShift")
        shiftHeldByScript = false
    end
end

local function releaseAllInputs()
    for key in pairs(keysDown) do
        VirtualInputManager:SendKeyEvent(false, key, false, game)
        keysDown[key] = nil
    end

    for key in pairs(currentMoveKeys or {}) do
        currentMoveKeys[key] = nil
    end

    table.clear(copyKeysDown)
    table.clear(pendingReleases)

    if currentMoveKeys then table.clear(currentMoveKeys) end

    local pos = getMousePos()
    VirtualInputManager:SendMouseButtonEvent(pos.X, pos.Y, 0, false, game, 0)
    VirtualInputManager:SendMouseButtonEvent(pos.X, pos.Y, 1, false, game, 0)

    slideActive = false
    shiftHeldByScript = false
    AIState.ShiftApplied = false
end

local function ensureShiftHeld(force)
    if force then
        if keysDown[Enum.KeyCode.LeftShift] then
            VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.LeftShift, false, game)
            keysDown[Enum.KeyCode.LeftShift] = nil
        end
        shiftHeldByScript = false
    end

    if not keysDown[Enum.KeyCode.LeftShift] then
        VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.LeftShift, false, game)
        keysDown[Enum.KeyCode.LeftShift] = true
        shiftHeldByScript = true
        AIState.ShiftApplied = true
    end
end

local function fireM1()
    if AutoPlayConfig.M1UseMouse then pressInput("MouseLeft") scheduleRelease("MouseLeft", 0.05)
    else pressInput("Q") scheduleRelease("Q", 0.05) end
end

local function fireM2()
    if AutoPlayConfig.M2UseMouse then pressInput("MouseRight") scheduleRelease("MouseRight", 0.08)
    else pressInput("Q") scheduleRelease("Q", 0.08) end
end

------------------------------------------------------------
-- ENREGISTREUR
------------------------------------------------------------
local function recordEvent(type_, data)
    table.insert(recordEvents, { time = os.clock() - recordStartTime, type = type_, data = data })
end

local function captureBegan(input)
    if not recording then return end
    if input.UserInputType == Enum.UserInputType.MouseButton1 then recordEvent("KEY_DOWN", "MouseLeft")
    elseif input.UserInputType == Enum.UserInputType.MouseButton2 then recordEvent("KEY_DOWN", "MouseRight")
    elseif input.KeyCode ~= Enum.KeyCode.Unknown then recordEvent("KEY_DOWN", input.KeyCode.Name)
    else recordEvent("KEY_DOWN", "Unknown") end
end

local function captureEnded(input)
    if not recording then return end
    if input.UserInputType == Enum.UserInputType.MouseButton1 then recordEvent("KEY_UP", "MouseLeft")
    elseif input.UserInputType == Enum.UserInputType.MouseButton2 then recordEvent("KEY_UP", "MouseRight")
    elseif input.KeyCode ~= Enum.KeyCode.Unknown then recordEvent("KEY_UP", input.KeyCode.Name)
    else recordEvent("KEY_UP", "Unknown") end
end

UserInputService.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    if input.KeyCode == Enum.KeyCode.L then
        recording = not recording
        if recording then
            recordStartTime = os.clock()
            recordEvents = {}
            lastCamRecordTime = 0
            pushLog("REC", "REC ON")
        else
            storedLogText = eventsToText(recordEvents)
            PlaybackEvents = select(1, parseLogText(storedLogText))
            pcall(function() setclipboard(storedLogText) end)
            pushLog("REC", #recordEvents .. " copiés")
        end
        return
    end
    if input.KeyCode == Enum.KeyCode.P then
        if #PlaybackEvents == 0 then sendNotification("Copy", "Parser d'abord.") return end
        playbackActive = not playbackActive
        if playbackActive then
            playbackStartTime = os.clock()
            playbackIndex = 1
            copyCameraTarget = nil
            firstCameraLook = nil
            table.clear(pendingReleases)
            if AutoPlayConfig.Mode == "IA" then AutoPlayConfig.Mode = "Copy" end
            pushLog("COPY", "Lecture ON")
        else releaseAllInputs() pushLog("COPY", "Lecture OFF") end
        return
    end
    captureBegan(input)
end)

UserInputService.InputEnded:Connect(captureEnded)

RunService.RenderStepped:Connect(function()
    if recording then
        local now = os.clock()
        if now - lastCamRecordTime >= 0.1 then
            lastCamRecordTime = now
            local cf = Camera.CFrame
            recordEvent("CAMERA", { cf.Position, cf.LookVector })
        end
    end
    if copyCameraTarget and playbackActive then
        Camera.CFrame = Camera.CFrame:Lerp(copyCameraTarget, AutoPlayConfig.CopyCameraSmooth)
    end
end)

-- Shift au spawn / nouveau round
local function onCharacterSpawn(char)
    task.defer(function()
        task.wait(0.5)

        if not MatchState.Ended then
            task.spawn(waitAndScanGameTeams)
        end

        local hum =
            char:FindFirstChildOfClass("Humanoid")

        if hum then
            hum.Died:Connect(function()
                registerAIDeath()
            end)
        end

        ensureShiftHeld(true)

        pushLog(
            "SYSTEM",
            "Shift maintenu (nouveau round)"
        )
    end)
end

if LocalPlayer.Character then onCharacterSpawn(LocalPlayer.Character) end
LocalPlayer.CharacterAdded:Connect(onCharacterSpawn)
LocalPlayer.CharacterRemoving:Connect(function()
    stopMovement()
    releaseAllInputs()
    AITarget = nil
    trackedTarget = nil
    currentTarget = nil
    AIState.LastPosition = nil
    AIState.StuckSince = nil
end)

------------------------------------------------------------
-- OUTILS IA
------------------------------------------------------------
local function getCharacter()
    local char = LocalPlayer.Character
    if not char then return nil end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    local hum = char:FindFirstChildOfClass("Humanoid")
    if hrp and hum and hum.Health > 0 then return char, hrp, hum end
end

local function isEnemyPlayer(plr)
    if not plr or plr == LocalPlayer or whitelistedAllies[plr] then return false end
    if LocalPlayer.Team and plr.Team == LocalPlayer.Team then return false end
    return isDuelTargetActive(plr)
end

local function updateAITarget(hrp)
    local now = os.clock()

    if AITarget
        and isDuelTargetActive(AITarget)
    then
        AITargetLastValid = now
        return AITarget
    end

    if now - AILastAcquire
        < 0.10
    then
        return AITarget
    end

    AILastAcquire = now

    local newTarget =
        acquireAITarget(hrp.Position)

    if newTarget ~= AITarget then
        AITarget = newTarget
        AITargetSince =
            newTarget and now or 0

        AITargetLastVisible =
            newTarget
            and isTargetVisible(newTarget)
            or false
            
        pcall(function()
            OrionLib:SendTelemetryEvent(
                "target_acquired",
                "AutoPlay target",
                newTarget and newTarget.Name or "None"
            )
        end)
    end

    return AITarget
end

local function makeRayParams(extra)
    local p = RaycastParams.new()
    p.FilterType = Enum.RaycastFilterType.Blacklist
    p.FilterDescendantsInstances = extra or { LocalPlayer.Character }
    p.IgnoreWater = true
    return p
end

local function hasLineOfSight(origin, targetChar, targetHRP)
    local params = makeRayParams({ LocalPlayer.Character })
    local dir = targetHRP.Position - origin
    if dir.Magnitude <= 0.01 then return true end
    local result = Workspace:Raycast(origin, dir, params)
    return (not result) or result.Instance:IsDescendantOf(targetChar)
end

local function castWall(origin, direction, distance)
    if direction.Magnitude <= 0.001 then return false end
    local params = makeRayParams({ LocalPlayer.Character })
    local unit = direction.Unit
    for _, h in ipairs({ 1.5, 3.0, 5.0 }) do
        local r = Workspace:Raycast(origin + Vector3.new(0, h, 0), unit * distance, params)
        if r and r.Instance and r.Instance.CanCollide then return true end
    end
    return false
end

local function findBestOpenDirection(hrp, preferred)
    local forward = Vector3.new(hrp.CFrame.LookVector.X, 0, hrp.CFrame.LookVector.Z)
    local right = Vector3.new(hrp.CFrame.RightVector.X, 0, hrp.CFrame.RightVector.Z)

    if forward.Magnitude < 0.01 then forward = Vector3.new(0, 0, -1) end
    if right.Magnitude < 0.01 then right = Vector3.new(1, 0, 0) end

    forward = forward.Unit
    right = right.Unit

    local preferredFlat = Vector3.new(preferred.X, 0, preferred.Z)
    if preferredFlat.Magnitude < 0.01 then preferredFlat = forward end
    preferredFlat = preferredFlat.Unit

    local candidates = {
        preferredFlat,
        -forward,
        right,
        -right,
        (forward + right).Unit,
        (forward - right).Unit,
        (-forward + right).Unit,
        (-forward - right).Unit,
    }

    local bestDirection, bestScore = nil, -math.huge

    for _, direction in ipairs(candidates) do
        if direction and direction.Magnitude > 0.01 then
            local blocked = castWall(hrp.Position, direction, AutoPlayConfig.WallRange + 3)
            if not blocked then
                local score = direction:Dot(preferredFlat) * 3
                if score > bestScore then
                    bestScore = score
                    bestDirection = direction.Unit
                end
            end
        end
    end

    return bestDirection or -forward
end

local function chooseBestCoverPosition(char, targetChar, hrpPos, enemyPos)
    local params = makeRayParams({ char, targetChar })
    local bestPos, bestScore = nil, -math.huge
    for i = 1, AutoPlayConfig.CoverSamples do
        local angle = (i / AutoPlayConfig.CoverSamples) * math.pi * 2
        local offset = Vector3.new(math.cos(angle), 0, math.sin(angle)) * AutoPlayConfig.CoverSearchRadius
        local ground = Workspace:Raycast(hrpPos + offset + Vector3.new(0, 10, 0), Vector3.new(0, -40, 0), params)
        if ground then
            local candidate = ground.Position + Vector3.new(0, 2, 0)
            local ray = Workspace:Raycast(enemyPos + Vector3.new(0, 2, 0), candidate - enemyPos, params)
            local score = (ray and 1000 or 0) + (candidate - enemyPos).Magnitude - (candidate - hrpPos).Magnitude * 0.35
            if score > bestScore then bestPos, bestScore = candidate, score end
        end
    end
    return bestPos
end

local function computePathDirection(origin, destination)
    local path = PathfindingService:CreatePath({ AgentRadius = 2, AgentHeight = 5, AgentCanJump = true, WaypointSpacing = 3 })
    local ok = pcall(function() path:ComputeAsync(origin, destination) end)
    if ok and path.Status == Enum.PathStatus.Success then
        local wp = path:GetWaypoints()
        if wp and #wp >= 2 then return wp[2] end
    end
end

local lastPathTime, lastState = 0, ""

local function logStateOnce(state, extra)
    local msg = extra and (state .. " | " .. extra) or state
    if lastState ~= msg then lastState = msg pushLog("IA", msg) end
end

local function getStuckZoneKey(position)
    local x = math.floor(position.X / 12)
    local y = math.floor(position.Y / 8)
    local z = math.floor(position.Z / 12)

    return string.format(
        "%d:%d:%d",
        x,
        y,
        z
    )
end

local function rememberStuckResult(
    zoneKey,
    choice,
    success
)
    if not zoneKey or not choice then
        return
    end

    local zone =
        AIState.StuckMemory[zoneKey]

    if not zone then
        zone = {}
        AIState.StuckMemory[zoneKey] = zone
    end

    if not zone[choice] then
        zone[choice] = {
            Success = 0,
            Fail = 0
        }
    end

    if success then
        zone[choice].Success += 1
    else
        zone[choice].Fail += 1
    end
end

local function getBestKnownStuckChoice(zoneKey)
    local zone =
        AIState.StuckMemory[zoneKey]

    if not zone then
        return nil
    end

    local bestChoice = nil
    local bestScore = -math.huge

    for choice, data in pairs(zone) do
        local score =
            data.Success * 3
            - data.Fail

        if score > bestScore then
            bestScore = score
            bestChoice = choice
        end
    end

    return bestChoice
end

local function updateStuckState(hrp)
    local now = os.clock()

    if now < AIState.StuckCooldownUntil then
        return false
    end

    if not AIState.LastPosition then
        AIState.LastPosition = hrp.Position
        AIState.LastPositionTime = now
        return false
    end

    if now - AIState.LastPositionTime < 0.20 then
        return false
    end

    local moved = (hrp.Position - AIState.LastPosition).Magnitude
    AIState.LastPosition = hrp.Position
    AIState.LastPositionTime = now

    if moved >= 2 then
        AIState.StuckSince = nil
        AIState.StuckStage = 0

        if AIState.TemporaryRecoveryStyle then
            pushLog(
                "IA",
                "STUCK RÉSOLU → retour à "
                    .. tostring(
                        AIState.RecoveryOriginalStyle
                    )
            )

            AIState.TemporaryRecoveryStyle = nil
            AIState.RecoveryOriginalStyle = nil
            AIState.RecoveryStartedAt = 0
        end
        return false
    end

    if not AIState.StuckSince then
        AIState.StuckSince = now
        return false
    end

    return now - AIState.StuckSince >= AutoPlayConfig.StuckTime
end

local function getStuckDirection(hrp, targetHRP)
    AIState.StuckStage = (AIState.StuckStage % 3) + 1
    AIState.StuckSince = os.clock()

    local away = hrp.Position - targetHRP.Position
    if away.Magnitude <= 0.01 then
        away = -hrp.CFrame.LookVector
    else
        away = away.Unit
    end

    if AIState.StuckStage == 1 then
        return away
    elseif AIState.StuckStage == 2 then
        return hrp.CFrame.RightVector
    else
        return -hrp.CFrame.RightVector
    end
end

local function startStuckFallback()
    if AIState.TemporaryRecoveryStyle then
        return
    end

    local original =
        getEffectiveIAStyle()

    local temporary

    if original == "Lointain" then
        temporary = "Aggressive"
    else
        temporary = "Lointain"
    end

    AIState.RecoveryOriginalStyle =
        original

    AIState.TemporaryRecoveryStyle =
        temporary

    AIState.RecoveryStartedAt =
        os.clock()

    pushLog(
        "IA",
        "STUCK LONG → "
            .. temporary
            .. " temporaire."
    )
end

local function getMovementIAStyle()
    if AIState.TemporaryRecoveryStyle then
        return AIState.TemporaryRecoveryStyle
    end

    return getEffectiveIAStyle()
end

local function getStrafeDirection(hrp)
    local now = os.clock()

    if now >= AIState.NextStrafeSwitch then
        AIState.StrafeSide = -AIState.StrafeSide
        AIState.NextStrafeSwitch = now + math.random(70, 130) / 100
    end

    return hrp.CFrame.RightVector * AIState.StrafeSide
end

local function canFireM1(now)
    return now - AIState.LastM1 >= AutoPlayConfig.AttackCooldownM1
end

local function canFireM2(now)
    return now - AIState.LastM2 >= AutoPlayConfig.AttackCooldownM2
end

local function buildDesiredDirection(style, hrp, hum, targetHRP, targetChar, dist)
    local toTarget = targetHRP.Position - hrp.Position
    local awayFromTarget = hrp.Position - targetHRP.Position
    local desired = Vector3.zero
    local state = "Idle"
    local canSee = hasLineOfSight(hrp.Position + Vector3.new(0, 2, 0), targetChar, targetHRP)

    if style == "Lointain" then
        ensureShiftHeld()

        if dist < AutoPlayConfig.LointainMinDist and awayFromTarget.Magnitude > 0.01 then
            desired = awayFromTarget.Unit
            state = "Lointain-Recul"
        elseif dist <= AutoPlayConfig.LointainMaxDist then
            if canSee and AutoPlayConfig.StrafeEnabled then
                desired = getStrafeDirection(hrp)
                state = "Lointain-Strafe"
            elseif toTarget.Magnitude > 0.01 then
                desired = toTarget.Unit
                state = "Lointain-Approche"
            end
        elseif toTarget.Magnitude > 0.01 then
            desired = (toTarget.Unit * 0.45 + getStrafeDirection(hrp) * 0.55).Unit
            state = "Lointain-Approche"
        end

        if desired.Magnitude < 0.01 and toTarget.Magnitude > 0.01 then
            desired = toTarget.Unit
        end

        return desired, state, canSee
    end

    local aggressive, defensive = false, false
    if style == "Mixed" then
        if hum.Health <= AutoPlayConfig.LowHealthThreshold then
            defensive = true
        else
            aggressive = true
        end
    elseif style == "Defensive" then
        defensive = true
    else
        aggressive = true
    end

    if aggressive then
        state = "Aggressive"
        if toTarget.Magnitude > 0.01 then
            desired = toTarget.Unit
        end

        if AutoPlayConfig.StrafeEnabled and canSee and dist <= AutoPlayConfig.MeleeRange + 6 then
            desired = (desired + getStrafeDirection(hrp) * 0.55).Unit
            state = "Strafe"
        end
    elseif defensive then
        state = "Defensive"
        local coverPos = chooseBestCoverPosition(hrp.Parent, targetChar, hrp.Position, targetHRP.Position)

        if coverPos then
            local toCover = coverPos - hrp.Position
            if toCover.Magnitude > 0.01 then
                desired = toCover.Unit
                state = "Cover"
            end
        end

        if desired.Magnitude <= 0.01 and awayFromTarget.Magnitude > 0.01 then
            desired = awayFromTarget.Unit
        end
    end

    return desired, state, canSee
end

local function applyObstacleAvoidance(hrp, desiredDirection)
    local forward = hrp.CFrame.LookVector
    local right = hrp.CFrame.RightVector
    local wallFront = castWall(hrp.Position, forward, AutoPlayConfig.WallRange)
    local corrected = desiredDirection
    if wallFront or castWall(hrp.Position, forward - right, AutoPlayConfig.WallRange) or castWall(hrp.Position, forward + right, AutoPlayConfig.WallRange) then
        corrected = findBestOpenDirection(hrp, desiredDirection)
    end
    local shouldJump = wallFront
    return corrected, shouldJump
end

local function setMoveKey(name, enabled)
    if enabled then
        if not currentMoveKeys[name] then
            pressInput(name)
            currentMoveKeys[name] = true
        end
    elseif currentMoveKeys[name] then
        releaseInput(name)
        currentMoveKeys[name] = nil
    end
end

local function stopMovement()
    for key in pairs(currentMoveKeys) do
        releaseInput(key)
        currentMoveKeys[key] = nil
    end
end

local function applyMovementKeys(direction)
    if direction.Magnitude < 0.08 then
        stopMovement()
        return
    end

    local flatDirection = Vector3.new(direction.X, 0, direction.Z)
    if flatDirection.Magnitude < 0.05 then
        stopMovement()
        return
    end
    flatDirection = flatDirection.Unit

    local cameraForward = Vector3.new(Camera.CFrame.LookVector.X, 0, Camera.CFrame.LookVector.Z)
    local cameraRight = Vector3.new(Camera.CFrame.RightVector.X, 0, Camera.CFrame.RightVector.Z)
    if cameraForward.Magnitude < 0.01 or cameraRight.Magnitude < 0.01 then return end

    cameraForward = cameraForward.Unit
    cameraRight = cameraRight.Unit

    local forwardDot = flatDirection:Dot(cameraForward)
    local rightDot = flatDirection:Dot(cameraRight)

    setMoveKey("W", forwardDot > 0.30)
    setMoveKey("S", forwardDot < -0.30)
    setMoveKey("A", rightDot < -0.30)
    setMoveKey("D", rightDot > 0.30)

    AIState.LastDirection = flatDirection
    AIState.LastMoveCommand = os.clock()
end

emergencyStop = function()
    AutoPlayConfig.Enabled = false
    playbackActive = false

    stopMovement()
    releaseAllInputs()

    AITarget = nil
    trackedTarget = nil
    currentTarget = nil
    copyCameraTarget = nil
    firstCameraLook = nil

    slideActive = false
    shiftHeldByScript = false

    pushLog("SYSTEM", "Arrêt d'urgence")
end

local function processPlaybackEvent(ev, skipCamera)
    if ev.type == "KEY_DOWN" then
        pressInput(ev.data, true)
        return
    end

    if ev.type == "KEY_UP" then
        releaseInput(ev.data)
        return
    end

    if ev.type ~= "CAMERA" or skipCamera then
        return
    end

    local _, look = ev.data[1], ev.data[2]
    if not look then return end

    if AutoPlayConfig.CopyRelativeCamera then
        if not firstCameraLook then
            firstCameraLook = look.Unit
            return
        end

        local baseRotation = CFrame.lookAt(Vector3.zero, firstCameraLook)
        local currentRotation = CFrame.lookAt(Vector3.zero, look.Unit)
        local deltaRotation = baseRotation:ToObjectSpace(currentRotation)

        copyCameraTarget = CFrame.new(Camera.CFrame.Position) * Camera.CFrame.Rotation * deltaRotation
    else
        local pos = ev.data[1]
        copyCameraTarget = CFrame.new(pos, pos + look)
    end
end

local function runCopyPlayback(skipCamera)
    if not playbackActive or #PlaybackEvents == 0 then return end
    local elapsed = os.clock() - playbackStartTime
    while playbackIndex <= #PlaybackEvents and PlaybackEvents[playbackIndex].time <= elapsed do
        processPlaybackEvent(PlaybackEvents[playbackIndex], skipCamera)
        playbackIndex = playbackIndex + 1
    end
    if playbackIndex > #PlaybackEvents then
        if AutoPlayConfig.CopyLoop then
            playbackStartTime = os.clock()
            playbackIndex = 1
            copyCameraTarget = nil
            firstCameraLook = nil
        else
            playbackActive = false
            releaseAllInputs()
            copyCameraTarget = nil
            pushLog("COPY", "Fin lecture")
        end
    end
end

local function startSlide(now)
    if slideActive then return false end
    if now - AIState.LastSlide < AutoPlayConfig.SlideCooldown then return false end

    AIState.LastSlide = now
    slideActive = true
    slideEndTime = now + AutoPlayConfig.SlideHoldDuration
    pressInput("C")
    return true
end

--========================================================--
-- AUTO STRATEGY
--========================================================--


local function runIALogic(hybridMode)
    if MatchState.Ended then
        AITarget = nil

        if not hybridMode then
            stopMovement()
        end

        return
    end
    
    local char, hrp, hum = getCharacter()
    if not char then return end

    ensureShiftHeld()

    local targetPlayer = updateAITarget(hrp)
    if not targetPlayer then
        logStateOnce("Scan", "Aucun ennemi actif")
        if not hybridMode then stopMovement() end
        return
    end

    local targetChar = targetPlayer.Character
    local targetHRP = targetChar and targetChar:FindFirstChild("HumanoidRootPart")
    if not targetHRP then
        AITarget = nil
        return
    end

    local targetDistance = (targetHRP.Position - hrp.Position).Magnitude
    local visible = isTargetVisible(targetPlayer)
    AITargetLastVisible = visible
    AITargetLastValid = os.clock()

    hum.WalkSpeed = AutoPlayConfig.WalkSpeed
    local effectiveStyle = getMovementIAStyle()

    local desired, state = buildDesiredDirection(
        effectiveStyle,
        hrp,
        hum,
        targetHRP,
        targetChar,
        targetDistance
    )

    if not hybridMode then
        local now = os.clock()
        local corrected, shouldJump = applyObstacleAvoidance(hrp, desired)

        if updateStuckState(hrp) then
            local stuckDuration =
                AIState.StuckSince
                and (os.clock() - AIState.StuckSince)
                or 0

            if stuckDuration >=
                AutoPlayConfig.StuckModeSwitchTime
            then
                startStuckFallback()
            end

            local recovery = getStuckDirection(hrp, targetHRP)
            corrected = findBestOpenDirection(hrp, recovery)
            shouldJump = true
            AIState.StuckCooldownUntil = now + AutoPlayConfig.StuckRecoveryDuration
            local zoneKey = getStuckZoneKey(hrp.Position)

            local knownChoice = getBestKnownStuckChoice(zoneKey)

            logStateOnce(
                "Stuck",
                "zone=" .. zoneKey
                    .. " | choix="
                    .. tostring(
                        knownChoice
                        or "exploration"
                    )
            )

            pcall(function()
                OrionLib:SendTelemetryEvent(
                    "ai_stuck",
                    "Recovery | "
                        .. tostring(
                            AIState.TemporaryRecoveryStyle
                            or getMovementIAStyle()
                        ),
                    AITarget and AITarget.Name or "None"
                )
            end)
        end
        
        if corrected.Magnitude < 0.08 and now - lastPathTime >= AutoPlayConfig.PathRecomputeDelay then
            lastPathTime = now
            local waypoint = computePathDirection(hrp.Position, targetHRP.Position)
            if waypoint then
                local direction = waypoint.Position - hrp.Position
                if direction.Magnitude > 0.01 then
                    corrected = direction.Unit
                end
                if waypoint.Action == Enum.PathWaypointAction.Jump then
                    shouldJump = true
                end
            end
        end

        applyMovementKeys(corrected)

        if corrected.Magnitude > 0.15 then
            startSlide(now)
        end

        if shouldJump and now - AIState.LastJump >= AutoPlayConfig.JumpCooldown then
            AIState.LastJump = now
            pressInput("Space")
            scheduleRelease("Space", 0.06)
        end
    end

    local now = os.clock()

    if visible then
        if effectiveStyle == "Lointain" then
            if targetDistance >= AutoPlayConfig.LointainMinDist and canFireM2(now) then
                AIState.LastM2 = now
                fireM2()
            end
        elseif targetDistance <= AutoPlayConfig.MeleeRange and canFireM1(now) then
            AIState.LastM1 = now
            fireM1()
        elseif targetDistance <= AutoPlayConfig.KnifeRange and canFireM2(now) then
            AIState.LastM2 = now
            fireM2()
        end

        --========================================================--
        -- ARBITRAGE CAMÉRA :
        -- L'Aimbot natif possède toujours la priorité.
        -- L'IA ne prend la caméra que si le natif n'a pas de lock.
        --========================================================--

        local nativeAimHasPriority =
            aimbotActive
            and trackedTarget
            and canAimAtPlayer(trackedTarget)

        if not nativeAimHasPriority
            and canAimAtPlayer(targetPlayer)
        then
            aimAtTarget(targetPlayer)
        end
    end

    --trackedTarget = targetPlayer
    --currentTarget = targetPlayer

    AITarget = targetPlayer
    
    logStateOnce(state, targetPlayer.Name .. " " .. string.format("%.0f", targetDistance) .. (visible and " VISIBLE" or " CACHE"))
end

------------------------------------------------------------
-- BOUCLE AUTO-PLAY
------------------------------------------------------------
RunService.Heartbeat:Connect(function()
    Camera = workspace.CurrentCamera or Camera
    local now = os.clock()

    -- Sanitation globale : une cible morte/éliminée ne peut jamais rester la cible active.
    if AITarget and not isDuelTargetActive(AITarget) then
        AITarget = nil
        AITargetLastVisible = false
    end
    if currentTarget and not isDuelTargetActive(currentTarget) then
        currentTarget = nil
    end
    for i = #pendingReleases, 1, -1 do
        if now >= pendingReleases[i].time then
            releaseInput(pendingReleases[i].name)
            table.remove(pendingReleases, i)
        end
    end

    if slideActive and now >= slideEndTime then
        slideActive = false
        releaseInput("C")
    end

    local mode = AutoPlayConfig.Mode

    if playbackActive and (mode == "Copy" or mode == "Hybride") then
        runCopyPlayback(mode == "Hybride")
        if mode == "Hybride" and AutoPlayConfig.Enabled then runIALogic(true) end
        return
    end

    if AutoPlayConfig.Enabled and mode == "IA" then
        runIALogic(false)
        return
    end

    if not playbackActive and not AutoPlayConfig.Enabled then
        stopMovement()
        releaseShift()
        if slideActive then
            slideActive = false
            releaseInput("C")
        end
    end
end)

OrionLib:Init()

--========================================================--
-- DÉTECTION FIN DE MATCH
--========================================================--


local MatchDetectionRunning = true

task.spawn(function()
    while MatchDetectionRunning do
        local winscreen =
            PlayerGui:FindFirstChild("Winscreen")

        if winscreen
            and winscreen:IsA("ScreenGui")
            and winscreen.Enabled
        then
            if not MatchState.Ended then
                protectAllPlayersAfterMatch()
            end

            if _G.AutoReplay == true then
                local buttons =
                    winscreen:FindFirstChild("Buttons")

                local queueAgain =
                    buttons
                    and buttons:FindFirstChild("QueueAgain")

                local button =
                    queueAgain
                    and queueAgain:FindFirstChild("Button")

                if button
                    and button:IsA("GuiButton")
                    and button.Visible
                then
                    -- Petit délai pour laisser l'écran se stabiliser
                    task.wait(0.1)

                    pcall(function()
                        for _, connection in ipairs(
                            getconnections(button.MouseButton1Click)
                        ) do
                            connection:Fire()
                        end

                        for _, connection in ipairs(
                            getconnections(button.MouseButton1Down)
                        ) do
                            connection:Fire()
                        end

                        for _, connection in ipairs(
                            getconnections(button.Activated)
                        ) do
                            connection:Fire()
                        end
                    end)

                    pushLog(
                        "MATCH",
                        "QueueAgain détecté → tentative de rematch."
                    )

                    pcall(function()
                        OrionLib:SendTelemetryEvent(
                            "match_end",
                            "Winscreen détecté",
                            "None"
                        )
                    end)
                end
            end
        end

        task.wait(0.15)
    end
end)

pushLog("SYSTEM", "Nexus V6.0 prêt")
