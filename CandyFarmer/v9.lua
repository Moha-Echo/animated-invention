local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")

if not game:IsLoaded() then game.Loaded:Wait() end

local players = game:GetService("Players")
local localPlayer = players.LocalPlayer
while not localPlayer do
    task.wait()
    localPlayer = players.LocalPlayer
end
localPlayer:WaitForChild("PlayerGui", 30)

local lastKnownPosition = nil
task.spawn(function()
    local char = localPlayer.Character or localPlayer.CharacterAdded:Wait()
    local hrp = char:WaitForChild("HumanoidRootPart", 10)
    if hrp then lastKnownPosition = hrp.Position end
end)
localPlayer.CharacterAdded:Connect(function(char)
    local hrp = char:WaitForChild("HumanoidRootPart", 10)
    if hrp then lastKnownPosition = hrp.Position end
end)


local Lib = "1bzableLib"
local CTX = {}
local UILib
local UIREG = {}   -- clé CFG -> contrôle UI (pour "Restaurer les valeurs par défaut")
local function pushLog(tag, msg) print("[" .. tag .. "] " .. msg) end

local CFG = {
    AntiFling = true,            -- Anti-Fling intelligent hors-manche
    ForceRejoinOnLoading = true, -- Rejoint si l'écran "Loading" reste bloqué + de 20 s

    Enabled = true,
    Spin = true, SpinSpeed = 540,
    Flick360Interval = 1.2,     -- Toutes les 1.2s, le corps fait un tour brutal
    Speed = 25,        -- vitesse constante (studs/s)
    SpeedVar = 1,      -- alterne Speed / Speed - SpeedVar entre chaque bonbon
    Turn = 320,        -- virage max (°/s)
    TouchR = 15,       -- rayon de touch en continu
    MissDist = 6,      -- distance de dépassement avant demi-tour sec
    SafeDepth = 150, FullAt = 50,
    Cluster = false, ClusterR = 100, ClusterW = 3, AheadW = 8,
    Boost = true, BoostMult = 1.8, BoostN = 3, BoostR = 20, BoostMax = 2.5, BoostCool = 10,
    TPFar = true, TPDist = 150,
    Killer = true, KillerR = 20,
    KillerHunt = true,          -- menace seulement si elle tient un Tool
    NoClipMode = "Stepped",     -- Off / Stepped / Touched
    NoClip = true, NoClipTouched = false,
    Ghost = true, GhostR = 20,
    AutoRejoin = true,
    RejoinOnAnyError = true,    -- rejoint aussi sur un autre message d'erreur (sans pénalité)
    KickKeywords = "Invalid, Position", -- mots-clés = vrai kick du jeu (compteur + pénalités)
    Hitbox = true,
    Debug = true,
    -- Autos
    AutoPlay = true, AutoGun = true, Notify = true,
    Friends = "nahhhhhhhh2adqsd, Mohale_san, Noob_LeTricheur",
    IgnoreFriends = true,       -- épargner / ne pas éviter les amis
    KA = true, KARange = "Toute la map", KARadius = 20, KASheriff = "Sac plein",
    KAInterval = 0.25, KAEquip = false, KAStab = false,
    KAAssassin = true, KABurst = 1,   -- Assassin : spam dès que Target3 est visible, sans délai
    SA = true, SAWhen = "Sac plein", SAPart = "Torse", SAOrder = "Cible, Origine", SAInterval = 0.3,
    PreventEarlyKill = true,    -- Ne pas tuer la dernière cible si le sac n'est pas plein
    FinalKill = true,
    FlingEnd = true, FlingTargets = "Murder + Sheriff", FlingTime = 2,
    TouchFling = false, TouchFlingR = 15,
    HL = true, HLInnocent = true, HLFriends = true, HLFill = 0.65, HLOutline = 0.1,
    RoundMinutes = 3,
    -- Manche / zone secrète
    UseAlive = true,            -- attribut Player "Alive" = en manche
    PreZone = true, PreHide = "Zone secrète", PreMax = 25, -- Zone secrète / Sous la map / Aucun
    HideMode = "Sous la map",   -- planque quand le sac est plein : Sous la map / Zone secrète
    ZoneMode = "Relatif au Lobby", ZoneText = "0, 700, 0", ZoneRadius = 60,
    AutoFriends = true, HandshakeMin = 2.5,
    AvoidFriendRadius = 45, AvoidFriendWeight = 150,    -- Pénalité de score pour forcer le bot à aller ailleurs  -- Évite les bonbons proches de l'ami dans ce rayon
}

local COL = {
    Murder = Color3.fromRGB(255, 0, 0),
    Sheriff = Color3.fromRGB(0, 0, 255),
    Innocent = Color3.fromRGB(255, 255, 255),
    Friend = Color3.fromRGB(0, 255, 120),
    Target = Color3.fromRGB(255, 150, 0),   -- ta cible en mode Assassin
}

-- Valeurs par défaut (copie avant chargement des réglages sauvegardés)
local DEFAULTS, COL_DEFAULT = {}, {}
for k, v in pairs(CFG) do DEFAULTS[k] = v end
for k, v in pairs(COL) do COL_DEFAULT[k] = v end

-- ===== État persistant (kicks + stats) : getgenv + fichier =====
local STATE_FILE = "CandyFarm_state.json"
local S = getgenv().CandyState
if not S then
    S = {boostPen = 0, speedPen = 0, tpPen = 0, kicks = 0}
    pcall(function()
        if isfile and isfile(STATE_FILE) then
            for k, v in pairs(HttpService:JSONDecode(readfile(STATE_FILE))) do S[k] = v end
        end
    end)
    getgenv().CandyState = S
end
S.life = S.life or {}
local function saveState()
    pcall(function() if writefile then writefile(STATE_FILE, HttpService:JSONEncode(S)) end end)
end

-- ===== Réglages persistants (JSON) =====
local SETTINGS_FILE = "CandyFarm_settings.json"
local uiReady, cfgDirty, cfgDirtyT = false, false, 0

local function markDirty()
    if uiReady then cfgDirty, cfgDirtyT = true, os.clock() end
end

local function saveSettings()
    local data = {cfg = {}, col = {}}
    for k, v in pairs(CFG) do
        local tv = type(v)
        if tv == "number" or tv == "string" or tv == "boolean" then data.cfg[k] = v end
    end
    for k, c in pairs(COL) do data.col[k] = {c.R, c.G, c.B} end
    getgenv().CandyCFGSave = data
    pcall(function()
        if writefile then writefile(SETTINGS_FILE, HttpService:JSONEncode(data)) end
    end)
end

local function loadSettings()
    local data
    pcall(function()
        if isfile and isfile(SETTINGS_FILE) then data = HttpService:JSONDecode(readfile(SETTINGS_FILE)) end
    end)
    data = data or getgenv().CandyCFGSave
    if type(data) ~= "table" then return false end
    if type(data.cfg) == "table" then
        for k, v in pairs(data.cfg) do
            if DEFAULTS[k] ~= nil and type(v) == type(DEFAULTS[k]) then CFG[k] = v end
        end
    end
    if type(data.col) == "table" then
        for k, v in pairs(data.col) do
            if COL[k] and type(v) == "table" and #v == 3 then COL[k] = Color3.new(v[1], v[2], v[3]) end
        end
    end
    return true
end

local settingsLoaded = loadSettings()
CFG.NoClip = CFG.NoClipMode ~= "Off"
CFG.NoClipTouched = CFG.NoClipMode == "Touched"

-- Valeurs effectives (réglage - pénalités de kick)
local function effSpeed() return math.max(math.min(CFG.Speed, 15), CFG.Speed - S.speedPen) end
local function effBoost() return math.max(math.min(CFG.BoostMult, 1.1), CFG.BoostMult - S.boostPen) end
local function effTP() return CFG.TPDist + S.tpPen end

local lastAct, lastActT, lastTick = "move", 0, os.clock()

-- ===== Stats =====
local sessionStart = os.clock()
local ST = {candies = 0, kills = 0, rounds = 0, guns = 0, asMurder = 0, asSheriff = 0, asInnocent = 0}
local statDirty = false
local function stat(k, n)
    n = n or 1
    ST[k] = ST[k] + n
    S.life[k] = (S.life[k] or 0) + n
    statDirty = true
end

-- ===== Amis / notifications =====
local friendSet, autoFriends = {}, {}
local function parseFriends(txt)
    friendSet = {}
    for name in tostring(txt):gmatch("[^,%s]+") do friendSet[name:lower()] = true end
end
parseFriends(CFG.Friends)
local function isFriend(p)
    local n = typeof(p) == "Instance" and p.Name or tostring(p)
    n = n:lower()
    return friendSet[n] == true or autoFriends[n] == true
end

local function notify(title, content, t)
    print("[NOTIF] " .. title .. " : " .. content)
    if CFG.Notify and UILib then
        pcall(function() UILib:MakeNotification({Name = title, Content = content, Time = t or 6}) end)
    end
end

local BIG = Vector3.new(9e9, 9e9, 9e9)
local targetModel = workspace:FindFirstChild("CoinContainer", true)
local banned = {}
local nc = false           -- noclip actif (vol / planque)
local hiding = false       -- planque (sac plein)
local zoneActive = false   -- pré-manche : zone secrète / sous la map

getgenv().FPDH = workspace.FallenPartsDestroyHeight
workspace.FallenPartsDestroyHeight = 0/0

-- ===== Anti-kick : rejoin automatique (filtré sur le message du prompt) =====
task.spawn(function()
    local ok, overlay = pcall(function()
        return game:GetService("CoreGui"):WaitForChild("RobloxPromptGui", 30):WaitForChild("promptOverlay", 30)
    end)
    if not ok or not overlay then return end
    overlay.ChildAdded:Connect(function(child)
        if child.Name ~= "ErrorPrompt" then return end
        task.spawn(function()
            local okm, msg = pcall(function()
                return child:WaitForChild("MessageArea", 3):WaitForChild("ErrorFrame", 3):WaitForChild("ErrorMessage", 3).Text
            end)
            msg = okm and tostring(msg) or ""
            local low, isKick = msg:lower(), false
            for kw in tostring(CFG.KickKeywords):gmatch("[^,]+") do
                kw = kw:match("^%s*(.-)%s*$")
                if kw ~= "" and low:find(kw:lower(), 1, true) then isKick = true break end
            end
            pushLog("ANTI-KICK", "Message : " .. (msg ~= "" and msg or "(vide)") .. " | kick = " .. tostring(isKick))
            if isKick then
                S.kicks += 1
                if lastAct == "boost" then S.boostPen += 0.1
                elseif lastAct == "tp" then S.tpPen += 200
                else S.speedPen += 1 end
                saveState()
                pushLog("ANTI-KICK", "Kick pendant : " .. lastAct .. " (total " .. S.kicks .. ")")
            end
            if CFG.AutoRejoin and (isKick or CFG.RejoinOnAnyError) then
                task.wait(3)
                pcall(function() TeleportService:Teleport(game.PlaceId, localPlayer) end)
            end
        end)
    end)
end)

-- ===== Sécurité Anti-Loading Screen Bug =====
task.spawn(function()
    if not game:IsLoaded() then game.Loaded:Wait() end
    task.wait(20)
    local pg = localPlayer:WaitForChild("PlayerGui", 10)
    if pg and pg:FindFirstChild("Loading") and CFG.ForceRejoinOnLoading then
        pushLog("SECURITY", "Écran 'Loading' détecté après 20s. Rejoin forcé...")
        pcall(function() TeleportService:Teleport(game.PlaceId, localPlayer) end)
    end
end)

-- ===== Frame Candy / sac =====
local function candyFrame()
    local g = localPlayer:FindFirstChild("PlayerGui")
    g = g and g:FindFirstChild("MainGUI")
    g = g and g:FindFirstChild("Game")
    g = g and g:FindFirstChild("CoinBags")
    g = g and g:FindFirstChild("Container")
    return g and g:FindFirstChild("Candy")
end

local function bagCount()
    local f = candyFrame()
    local icon = f and f:FindFirstChild("CurrencyFrame") and f.CurrencyFrame:FindFirstChild("Icon")
    local coins = icon and icon:FindFirstChild("Coins")
    return coins and tonumber(coins.Text)
end

-- Pas prêt : frame Candy invisible (manche déjà commencée / pas de manche) ou icône cachée (fin / mort)
local function isRoundOver()
    local f = candyFrame()
    if not f or not f.Visible then return true end
    local icon = f:FindFirstChild("CurrencyFrame") and f.CurrencyFrame:FindFirstChild("Icon")
    if icon then return not icon.Visible end
    return true
end

local function isBagFull()
    local f = candyFrame()
    if not f then return false end
    local n = bagCount()
    if f:FindFirstChild("Full") and f.Full.Visible == true and (not n or n > 0) then return true end
    return n ~= nil and n >= CFG.FullAt
end

local bagT, bagV = 0, false
local function bagFullCached()
    local now = os.clock()
    if now - bagT > 0.1 then bagT, bagV = now, isBagFull() end
    return bagV
end

-- ===== Mode Assassin =====
local function assassinTargetName()
    local pg = localPlayer:FindFirstChild("PlayerGui")
    local g = pg and pg:FindFirstChild("MainGUI")
    g = g and g:FindFirstChild("Game")
    local t3 = g and g:FindFirstChild("Target3")
    if t3 and t3.Visible then
        local lbl = t3:FindFirstChild("TargetName")
        if lbl and lbl.Text ~= "" then return lbl.Text end
    end
    return nil
end

local function obtenirModeActuel()
    local playerGui = localPlayer:FindFirstChild("PlayerGui")
    if not playerGui then return "Inconnu" end
    local modesFrame = playerGui:FindFirstChild("CrossPlatform")
        and playerGui.CrossPlatform:FindFirstChild("GameModes")
        and playerGui.CrossPlatform.GameModes:FindFirstChild("Container")
        and playerGui.CrossPlatform.GameModes.Container:FindFirstChild("Modes")
    if not modesFrame then return "Inconnu" end
    local assassinServer = modesFrame:FindFirstChild("Assassin")
        and modesFrame.Assassin:FindFirstChild("Info")
        and modesFrame.Assassin.Info:FindFirstChild("ModeIcon")
        and modesFrame.Assassin.Info.ModeIcon:FindFirstChild("CurrentServer")
    if assassinServer and assassinServer.Visible then return "Assassin" end
    return "Standard"
end

local function isAssassin()
    return assassinTargetName() ~= nil or obtenirModeActuel() == "Assassin"
end

-- ===== Rôles / manche / carte =====
local roles, killedSet = {}, {}
local myRoleCached = nil
local flagSheriffDead, flagGunDrop, flagFinal, flagAssassin = false, false, false, false
local noRoleSince = nil

local function hasTool(p, name)
    local ch = p.Character
    local t = ch and ch:FindFirstChild(name)
    if t and t:IsA("Tool") then return true end
    local bp = p:FindFirstChild("Backpack")
    return bp ~= nil and bp:FindFirstChild(name) ~= nil
end

local function roleNow(p)
    if hasTool(p, "Knife") then return "murder" end
    if hasTool(p, "Gun") then return "sheriff" end
    return nil
end

local function isAlive(p)
    local ch = p.Character
    local h = ch and ch:FindFirstChildOfClass("Humanoid")
    return h ~= nil and h.Health > 0 and ch:FindFirstChild("HumanoidRootPart") ~= nil
end

-- Heuristique de secours "en manche" : proche de la zone des bonbons
local mapCenter, mapRadius, mapFloorY = nil, nil, nil
local function updateMap(list)
    if #list < 3 then return end
    local miny = math.huge
    for _, c in ipairs(list) do
        if c.Position.Y < miny then miny = c.Position.Y end
    end
    mapFloorY = mapFloorY and math.min(mapFloorY, miny) or miny
    if not mapCenter and #list >= 8 then
        local sum = Vector3.zero
        for _, c in ipairs(list) do sum += c.Position end
        mapCenter = sum / #list
        local mr = 0
        for _, c in ipairs(list) do mr = math.max(mr, (c.Position - mapCenter).Magnitude) end
        mapRadius = mr + CFG.SafeDepth + 100
    end
end

-- En manche = attribut Player "Alive" == true (attribut absent = pas / plus en manche)
local aliveAttrSeen = false
local function inRound(p)
    if CFG.UseAlive then
        local a = p:GetAttribute("Alive")
        if a ~= nil then aliveAttrSeen = true end
        if aliveAttrSeen then return a == true end
    end
    local r = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
    if not r then return false end
    if not mapCenter then return true end
    return (r.Position - mapCenter).Magnitude <= mapRadius
end

local function isUnderground(p)
    local r = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
    return r ~= nil and mapFloorY ~= nil and r.Position.Y < mapFloorY - CFG.SafeDepth * 0.5
end

-- Lobby (boîte englobante du model workspace.Lobby)
local lobbyBox, lobbyBoxT = nil, 0
local function getLobbyBox()
    local now = os.clock()
    if now - lobbyBoxT > 1 then
        lobbyBoxT = now
        lobbyBox = nil
        local lob = workspace:FindFirstChild("Lobby")
        if lob and lob:IsA("Model") then
            local ok, cf, size = pcall(lob.GetBoundingBox, lob)
            if ok then lobbyBox = {cf = cf, size = size} end
        end
    end
    return lobbyBox
end

local function inLobbyPos(pos)
    local b = getLobbyBox()
    if not b then return false end
    local rel = b.cf:PointToObjectSpace(pos)
    local h = b.size / 2 + Vector3.new(30, 60, 30)
    return math.abs(rel.X) <= h.X and math.abs(rel.Y) <= h.Y and math.abs(rel.Z) <= h.Z
end

-- Zone secrète (relative au Lobby ou coordonnées fixes)
local function parseVec3(txt)
    local x, y, z = tostring(txt):match("(-?[%d%.]+)%s*,%s*(-?[%d%.]+)%s*,%s*(-?[%d%.]+)")
    if x then return Vector3.new(tonumber(x) or 0, tonumber(y) or 0, tonumber(z) or 0) end
    return nil
end

local zcT, zcV = 0, nil
local function zoneCenter()
    local now = os.clock()
    if zcV and now - zcT < 0.5 then return zcV end
    local v = parseVec3(CFG.ZoneText) or Vector3.new(0, 700, 0)
    if CFG.ZoneMode == "Relatif au Lobby" then
        local lob = workspace:FindFirstChild("Lobby")
        if lob then
            local ok, piv = pcall(lob.GetPivot, lob)
            if ok then v = piv.Position + v end
        end
    end
    zcT, zcV = now, v
    return v
end

local function zoneSlotOffset()
    local id = localPlayer.UserId
    return Vector3.new(((id % 5) - 2) * 3, 0, (((id // 5) % 5) - 2) * 3)
end

local function inZone(p)
    local r = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
    return r ~= nil and (r.Position - zoneCenter()).Magnitude <= CFG.ZoneRadius
end

local function isHiddenSpot(p)
    return isUnderground(p) or inZone(p)
end

-- Joueurs vivants en manche (hors moi)
local function aliveOthers()
    local out = {}
    for _, pl in ipairs(players:GetPlayers()) do
        if pl ~= localPlayer and isAlive(pl) and inRound(pl) then out[#out + 1] = pl end
    end
    return out
end

-- Tuer ce joueur terminerait la manche (il est le dernier en vie à part moi)
local function wouldEndRound(target)
    local o = aliveOthers()
    return #o == 1 and o[1] == target
end

-- ===== Highlights =====
local function removeHighlight(ch)
    local h = ch and ch:FindFirstChild("RoleHighlight")
    if h then h:Destroy() end
end

local function applyHighlight(ch, color)
    local h = ch:FindFirstChild("RoleHighlight")
    if not h then
        h = Instance.new("Highlight")
        h.Name = "RoleHighlight"
        h.Adornee = ch
        h.Parent = ch
    end
    if h.FillColor ~= color then
        h.FillColor = color
        h.OutlineColor = color
    end
    h.FillTransparency = CFG.HLFill
    h.OutlineTransparency = CFG.HLOutline
end

local function clearRound()
    for _, p in ipairs(players:GetPlayers()) do removeHighlight(p.Character) end
    roles, killedSet = {}, {}
    flagSheriffDead, flagGunDrop, flagFinal, flagAssassin = false, false, false, false
end

local function watchPlayers()
    task.spawn(function()
        while true do
            local ok, err = pcall(function()
                local any, mine = false, nil
                local assassin = isAssassin()
                local atarget = assassinTargetName()
                for _, p in ipairs(players:GetPlayers()) do
                    local r = roleNow(p)
                    if r then any = true end
                    if p == localPlayer then
                        mine = r
                    elseif r and isAlive(p) and roles[p.Name] ~= r then
                        roles[p.Name] = r
                        if not assassin then
                            local tag = isFriend(p) and " (ami)" or ""
                            if r == "murder" then notify("Murder détecté", p.Name .. tag, 5)
                            else notify("Sheriff détecté", p.Name .. tag, 5) end
                        end
                    end
                end
                myRoleCached = mine or (any and "innocent" or nil)

                if assassin and any and not flagAssassin then
                    flagAssassin = true
                    notify("Mode Assassin", "Cible : " .. (atarget or "?"), 6)
                end

                -- sheriff mort (le Gun tombe au sol)
                if any and not assassin and not flagSheriffDead then
                    for name, role in pairs(roles) do
                        if role == "sheriff" then
                            local p = players:FindFirstChild(name)
                            if not p or not isAlive(p) then
                                flagSheriffDead = true
                                notify("Sheriff mort", name .. " : le Gun est au sol", 5)
                                break
                            end
                        end
                    end
                end

                -- highlights : amis / cible / murder / sheriff / innocents
                for _, p in ipairs(players:GetPlayers()) do
                    if p then -- jai retiré ~= localPlayer pr que meme nous on a le highlight c + meixu
                        local ch = p.Character
                        local col
                        if CFG.HL and any and ch and isAlive(p) then
                            local role = roles[p.Name]
                            if CFG.HLFriends and isFriend(p) then col = COL.Friend
                            elseif atarget and p.Name == atarget then col = COL.Target
                            elseif role == "murder" then col = COL.Murder
                            elseif role == "sheriff" then col = COL.Sheriff
                            elseif CFG.HLInnocent and inRound(p) then col = COL.Innocent end
                        end
                        if col then applyHighlight(ch, col) elseif ch then removeHighlight(ch) end
                    end
                end

                -- fin de manche : plus aucun rôle pendant 4 s
                if any then
                    noRoleSince = nil
                else
                    noRoleSince = noRoleSince or os.clock()
                    if os.clock() - noRoleSince > 4 and next(roles) ~= nil then clearRound() end
                end
            end)
            if not ok then warn("[ROLES] " .. tostring(err)) end
            task.wait(0.3)
        end
    end)
end

-- Menaces à éviter : murder si on n'est pas murder, sheriff si on est murder (amis ignorés)
local function getThreats()
    local out = {}
    local want = (myRoleCached == "murder") and "sheriff" or "murder"
    for name, role in pairs(roles) do
        if role == want then
            local p = players:FindFirstChild(name)
            if p and isAlive(p) and not (CFG.IgnoreFriends and isFriend(p)) then
                local ch = p.Character
                if not CFG.KillerHunt or ch:FindFirstChildOfClass("Tool") then
                    out[#out + 1] = ch.HumanoidRootPart.Position
                end
            end
        end
    end
    return out
end

-- ===== Bonbons =====
local function alive(c) return c.Parent and c:FindFirstChild("TouchInterest") end

local lastModelSearch = 0
local function scan()
    local list = {}
    if not targetModel or not targetModel:IsDescendantOf(workspace) then
        targetModel = nil
        local now = os.clock()
        if now - lastModelSearch > 1 then
            lastModelSearch = now
            targetModel = workspace:FindFirstChild("CoinContainer", true)
        end
    end
    if not targetModel then return list end
    for _, c in ipairs(targetModel:GetChildren()) do
        if c:IsA("BasePart") and c:FindFirstChild("TouchInterest") then list[#list + 1] = c end
    end
    return list
end

local function segDist(a, b, p)
    local ab = b - a
    local l2 = ab:Dot(ab)
    if l2 < 1e-6 then return (p - a).Magnitude end
    local t = math.clamp((p - a):Dot(ab) / l2, 0, 1)
    return (p - (a + ab * t)).Magnitude
end

local function neighbors(list, c)
    local n = 0
    for _, o in ipairs(list) do
        if o ~= c and (o.Position - c.Position).Magnitude <= CFG.ClusterR then n += 1 end
    end
    return n
end

-- Score = -distance + devant*AheadW + voisins*ClusterW ; exclut les trajets près des menaces
local function pickBest(list, pos, fwd, kills, exclude)
    local best, bs
    local now = os.clock()
    
    local friendPos = nil
    for name, _ in pairs(autoFriends) do
        local p = players:FindFirstChild(name)
        if p and p.Character and p.Character:FindFirstChild("HumanoidRootPart") then
            friendPos = p.Character.HumanoidRootPart.Position
            break
        end
    end

    for _, c in ipairs(list) do
        if c ~= exclude and not (banned[c] and banned[c] > now) then
            local ok = true
            for _, k in ipairs(kills) do
                if segDist(pos, c.Position, k) < CFG.KillerR then ok = false break end
            end
            if ok then
                local to = c.Position - pos
                local dist = to.Magnitude
                local s = -dist
                
                if friendPos and (c.Position - friendPos).Magnitude <= (CFG.AvoidFriendRadius or 45) then
                    s -= (CFG.AvoidFriendWeight or 150)
                end

                if fwd and dist > 0.01 then s += fwd:Dot(to / dist) * CFG.AheadW end
                if CFG.Cluster then s += neighbors(list, c) * CFG.ClusterW end
                if not bs or s > bs then best, bs = c, s end
            end
        end
    end
    return best
end

-- ===== Debug visuel =====
local DBG, lineA, lineB, zone
local marks, dbgDirty = {}, false

local function mkLine(col)
    local p = Instance.new("Part")
    p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, false, false, false
    p.Material, p.Color, p.Transparency = Enum.Material.Neon, col, 1
    p.Size = Vector3.new(0.25, 0.25, 0.25)
    p.Parent = DBG
    return p
end

local function setLine(p, a, b)
    if not a or not b then p.Transparency = 1 return end
    local d = math.max((b - a).Magnitude, 0.1)
    p.Size = Vector3.new(0.25, 0.25, d)
    p.CFrame = CFrame.lookAt(a, b) * CFrame.new(0, 0, -d / 2)
    p.Transparency = 0.2
end

local function dbgInit()
    if DBG and DBG.Parent then return end
    DBG = Instance.new("Folder")
    DBG.Name = "CandyDebug"
    DBG.Parent = workspace
    lineA = mkLine(Color3.fromRGB(0, 220, 255))
    lineB = mkLine(Color3.fromRGB(255, 230, 0))
    zone = mkLine(Color3.fromRGB(255, 0, 0))
    zone.Shape = Enum.PartType.Ball
end

local function mkMark(c)
    local g = Instance.new("BillboardGui")
    g.Size, g.AlwaysOnTop, g.Adornee, g.Parent = UDim2.fromOffset(28, 28), true, c, DBG
    local f = Instance.new("Frame")
    f.Name, f.Size, f.BackgroundTransparency, f.BorderSizePixel = "F", UDim2.fromScale(1, 1), 0.2, 0
    f.Parent = g
    Instance.new("UICorner", f).CornerRadius = UDim.new(1, 0)
    local t = Instance.new("TextLabel")
    t.Name, t.Size, t.BackgroundTransparency = "T", UDim2.fromScale(1, 1), 1
    t.TextColor3, t.Font, t.TextSize = Color3.new(0, 0, 0), Enum.Font.GothamBold, 14
    t.Parent = f
    return g
end

local function clearDebug()
    if not dbgDirty then return end
    dbgDirty = false
    for c, m in pairs(marks) do m:Destroy() marks[c] = nil end
    if lineA then lineA.Transparency, lineB.Transparency, zone.Transparency = 1, 1, 1 end
end

local function updateDebug(list, pos, target, kills)
    dbgInit()
    dbgDirty = true
    local seen = {}
    for _, c in ipairs(list) do
        seen[c] = true
        local n = neighbors(list, c)
        local m = marks[c]
        if n == 0 and c ~= target then
            if m then m:Destroy() marks[c] = nil end
        else
            if not m then m = mkMark(c) marks[c] = m end
            m.F.BackgroundColor3 = c == target and Color3.fromRGB(0, 200, 255)
                or (n >= 3 and Color3.fromRGB(0, 230, 80) or Color3.fromRGB(255, 170, 0))
            m.F.T.Text = tostring(n)
        end
    end
    for c, m in pairs(marks) do
        if not seen[c] then m:Destroy() marks[c] = nil end
    end
    local nxt = target and pickBest(list, target.Position, nil, kills, target)
    setLine(lineA, pos, target and target.Position)
    setLine(lineB, target and target.Position, nxt and nxt.Position)
    if #kills > 0 then
        zone.Position = kills[1]
        zone.Size = Vector3.one * CFG.KillerR * 2
        zone.Transparency = 0.85
    else
        zone.Transparency = 1
    end
end

-- ===== NoClip : Stepped (parties du perso) ou Touched (murs touchés) =====
local ncParts, ncChar, ncT = {}, nil, 0
RunService.Stepped:Connect(function()
    local on = zoneActive or (nc and CFG.NoClip and not CFG.NoClipTouched)
    if not on then return end
    local ch = localPlayer.Character
    if not ch then return end
    local t = os.clock()
    if ch ~= ncChar or t - ncT > 2 then
        ncChar, ncT, ncParts = ch, t, {}
        for _, p in ipairs(ch:GetDescendants()) do
            if p:IsA("BasePart") then ncParts[#ncParts + 1] = p end
        end
    end
    for _, p in ipairs(ncParts) do p.CanCollide = false end
end)

local ncOrig, tConns, tChar = {}, {}, nil
local touchNames = {"HumanoidRootPart", "Torso", "UpperTorso", "LowerTorso",
    "LeftArm", "LeftUpperArm", "LeftLowerArm", "LeftHand",
    "RightArm", "RightUpperArm", "RightLowerArm", "RightHand"}

local function onTouch(hit)
    if not (nc and CFG.NoClip and CFG.NoClipTouched) then return end
    if not hit.CanCollide or hit:IsA("Terrain") or hit.Name == "Baseplate" then return end
    local ch = localPlayer.Character
    local r = ch and ch:FindFirstChild("HumanoidRootPart")
    if not r or hit:IsDescendantOf(ch) then return end
    local m = hit:FindFirstAncestorOfClass("Model")
    if m and m:FindFirstChildOfClass("Humanoid") then return end
    if hit.Position.Y < r.Position.Y - r.Size.Y then return end -- ne pas traverser le sol
    ncOrig[hit] = true
    hit.CanCollide = false
end

local function hookTouch(ch)
    tChar = ch
    for _, cn in ipairs(tConns) do cn:Disconnect() end
    tConns = {}
    for _, n in ipairs(touchNames) do
        local p = ch:FindFirstChild(n)
        if p and p:IsA("BasePart") then tConns[#tConns + 1] = p.Touched:Connect(onTouch) end
    end
end

local function ncRestore()
    for p in pairs(ncOrig) do
        if p.Parent then p.CanCollide = true end
        ncOrig[p] = nil
    end
end

local function setNoClipMode(m)
    CFG.NoClipMode = m
    CFG.NoClip = (m ~= "Off")
    CFG.NoClipTouched = (m == "Touched")
    if m ~= "Touched" then ncRestore() end
end

-- ===== Transparence des objets autour =====
local ghosted = {}
local gp = OverlapParams.new()
gp.FilterType = Enum.RaycastFilterType.Exclude

local function ghostClear()
    for p, o in pairs(ghosted) do
        if p.Parent then p.Transparency = o end
        ghosted[p] = nil
    end
end

local function ghostUpdate(center)
    local ex = {}
    for _, pl in ipairs(players:GetPlayers()) do
        if pl.Character then ex[#ex + 1] = pl.Character end
    end
    if targetModel then ex[#ex + 1] = targetModel end
    if DBG then ex[#ex + 1] = DBG end
    gp.FilterDescendantsInstances = ex
    local seen = {}
    for _, p in ipairs(workspace:GetPartBoundsInRadius(center, CFG.GhostR, gp)) do
        if ghosted[p] or p.Transparency < 0.6 then
            seen[p] = true
            if not ghosted[p] then
                ghosted[p] = p.Transparency
                p.Transparency = 0.75
            end
        end
    end
    for p, o in pairs(ghosted) do
        if not seen[p] then
            if p.Parent then p.Transparency = o end
            ghosted[p] = nil
        end
    end
end

-- ===== Auto Play (écran Join) =====
local function clickButton(btn)
    if not getconnections then return end
    for _, ev in ipairs({btn.MouseButton1Click, btn.MouseButton1Down, btn.Activated}) do
        for _, cn in ipairs(getconnections(ev)) do pcall(function() cn:Fire() end) end
    end
end

local function startAutoPlay()
    task.spawn(function()
        local clickedAt = 0
        while true do
            task.wait(0.5)
            if CFG.AutoPlay then
                pcall(function()
                    local pg = localPlayer:FindFirstChild("PlayerGui")
                    local join = pg and pg:FindFirstChild("Join")
                    local fr = join and join:FindFirstChild("Friends")
                    local btn = fr and fr:FindFirstChild("Play")
                    if btn and btn.Visible and fr.Visible and join.Enabled and os.clock() - clickedAt > 5 then
                        task.wait(1)
                        clickButton(btn)
                        clickedAt = os.clock()
                        notify("Auto Play", "Clic sur Play", 3)
                    end
                end)
            end
        end
    end)
end

-- ===== Auto pickup du Gun (GunDrop) =====
local gunBusy = setmetatable({}, {__mode = "k"})

local function touchPartOf(drop)
    local ti = drop:FindFirstChildOfClass("TouchInterest") or drop:FindFirstChild("TouchInterest", true)
    if ti and ti.Parent and ti.Parent:IsA("BasePart") then return ti.Parent end
    if drop:IsA("BasePart") then return drop end
    return drop:FindFirstChildWhichIsA("BasePart", true)
end

local function handleGunDrop(drop)
    if gunBusy[drop] then return end
    gunBusy[drop] = true
    if not flagGunDrop then
        flagGunDrop = true
        notify("GunDrop", "Le Gun est au sol" .. ((CFG.AutoGun and myRoleCached ~= "murder") and " : ramassage auto" or ""), 5)
    end
    if not CFG.AutoGun or myRoleCached == "murder" or not firetouchinterest then return end
    local t0 = os.clock()
    while drop.Parent and CFG.AutoGun and os.clock() - t0 < 15 do
        local hrp = localPlayer.Character and localPlayer.Character:FindFirstChild("HumanoidRootPart")
        local part = touchPartOf(drop)
        if hrp and part then
            pcall(function()
                firetouchinterest(hrp, part, 0)
                task.wait(0.02)
                firetouchinterest(hrp, part, 1)
            end)
        end
        task.wait(0.3)
    end
    task.wait(0.3)
    if not drop.Parent then
        if hasTool(localPlayer, "Gun") then
            stat("guns")
            notify("Gun récupéré", "Tu es maintenant Sheriff", 7)
        else
            local who
            for _, p in ipairs(players:GetPlayers()) do
                if p ~= localPlayer and hasTool(p, "Gun") then who = p.Name break end
            end
            notify("Gun pris", (who or "Quelqu'un") .. " a ramassé le Gun", 7)
        end
    else
        notify("GunDrop", "Ramassage échoué", 3)
    end
end

local function startGunWatch()
    workspace.DescendantAdded:Connect(function(d)
        if d.Name == "GunDrop" then task.spawn(handleGunDrop, d) end
    end)
    for _, d in ipairs(workspace:GetDescendants()) do
        if d.Name == "GunDrop" then task.spawn(handleGunDrop, d) end
    end
end

-- ===== Kill Aura Murder =====
local attacked = {}

local function trackKills()
    local now = os.clock()
    for p, t in pairs(attacked) do
        if not p.Parent or not isAlive(p) then
            if now - t < 6 and not killedSet[p.Name] then
                killedSet[p.Name] = true
                stat("kills")
                notify("Kill", p.Name, 3)
            end
            attacked[p] = nil
        elseif now - t > 6 then
            attacked[p] = nil
        end
    end
end

local function knifeEvents()
    local ch = localPlayer.Character
    if not ch then return nil end
    local bp = localPlayer:FindFirstChild("Backpack")
    local knife = ch:FindFirstChild("Knife") or (bp and bp:FindFirstChild("Knife"))
    local ev = knife and knife:FindFirstChild("Events")
    return knife, ev and ev:FindFirstChild("HandleTouched"), ev
end

-- Dernière phase : il ne reste que des amis, tous cachés, et on est le murder caché
local finalT, finalV = 0, false
local function finalFriendsMode()
    local now = os.clock()
    if now - finalT < 0.15 then return finalV end
    finalT, finalV = now, false
    if not CFG.FinalKill or myRoleCached ~= "murder" then return false end
    if not hiding and not (bagFullCached() and isHiddenSpot(localPlayer)) then return false end
    local n = 0
    for _, p in ipairs(players:GetPlayers()) do
        if p ~= localPlayer and isAlive(p) and inRound(p) then
            if not isFriend(p) or not isHiddenSpot(p) then return false end
            n += 1
        end
    end
    finalV = n > 0
    return finalV
end

-- Mode Assassin : aucun délai, dès que Target3 est visible (avant même les bonbons)
local function assassinStep()
    if not (CFG.KA and CFG.KAAssassin) then return end
    local name = assassinTargetName()
    if not name then return end
    local p = players:FindFirstChild(name)
    if not p or p == localPlayer then return end
    local knife, touch = knifeEvents()
    if not touch then return end
    local pc = p.Character
    local tr = pc and pc:FindFirstChild("HumanoidRootPart")
    local th = pc and pc:FindFirstChildOfClass("Humanoid")
    if not tr or not th or th.Health <= 0 then return end
    local friend = isFriend(p)
    local final = finalFriendsMode()
    if friend and CFG.IgnoreFriends and not final then return end
    -- ne pas finir la manche avant d'avoir rempli le sac
    if not friend and not (hiding or bagFullCached()) and wouldEndRound(p) then return end
    if CFG.KAEquip and knife.Parent ~= localPlayer.Character then
        local hum = localPlayer.Character:FindFirstChildOfClass("Humanoid")
        if hum then pcall(function() hum:EquipTool(knife) end) end
    end
    for _ = 1, math.max(1, CFG.KABurst) do
        pcall(touch.FireServer, touch, tr)
    end
    attacked[p] = os.clock()
    trackKills()
end

local function runKillAura()
    if not CFG.KA then return end
    if CFG.KAAssassin and assassinTargetName() then return end   -- géré par assassinStep (sans délai)
    if myRoleCached ~= "murder" then return end
    local ch = localPlayer.Character
    local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
    local hum = ch and ch:FindFirstChildOfClass("Humanoid")
    if not hrp or not hum or hum.Health <= 0 then return end
    local knife, touch, events = knifeEvents()
    if not touch then return end
    if CFG.KAEquip and knife.Parent ~= ch then
        pcall(function() hum:EquipTool(knife) end)
        task.wait(0.05)
    end

    local bagFull = hiding or bagFullCached()
    local final = finalFriendsMode()
    local allowSheriff = CFG.KASheriff == "Toujours" or (CFG.KASheriff == "Sac plein" and bagFull)
    if final and not flagFinal then
        flagFinal = true
        notify("Fin de manche", "Il ne reste que des amis : kill final", 7)
    end

    local cands = {}
    if not final and obtenirModeActuel() == "Assassin" then
        local name = assassinTargetName()
        local p = name and players:FindFirstChild(name)
        if p then cands[1] = p end
    else
        for _, p in ipairs(players:GetPlayers()) do
            if p ~= localPlayer then cands[#cands + 1] = p end
        end
    end

    local now = os.clock()
    for _, p in ipairs(cands) do
        local pc = p.Character
        local tr = pc and pc:FindFirstChild("HumanoidRootPart")
        local th = pc and pc:FindFirstChildOfClass("Humanoid")
        if tr and th and th.Health > 0 and inRound(p) then
            local friend = isFriend(p)
            local ok
            if final then
                ok = friend
            else
                ok = not (CFG.IgnoreFriends and friend)
                if ok and roles[p.Name] == "sheriff" and not allowSheriff then ok = false end
                if ok and CFG.PreventEarlyKill and not (hiding or bagFullCached()) and wouldEndRound(p) then ok = false end
                if ok and CFG.KARange == "Rayon" and (tr.Position - hrp.Position).Magnitude > CFG.KARadius then ok = false end
                if ok and not bagFull and wouldEndRound(p) then ok = false end
            end
            if ok then
                if CFG.KAStab then
                    local stab = events:FindFirstChild("KnifeStabbed")
                    if stab then pcall(stab.FireServer, stab) end
                end
                pcall(touch.FireServer, touch, tr)
                attacked[p] = now
            end
        end
    end
    trackKills()
end

-- ===== Sheriff : tir silencieux sur le murder =====
local shotCache = setmetatable({}, {__mode = "k"})

local function findShootRemote(gun)
    if shotCache[gun] then return shotCache[gun] end
    local found
    local prefer = {Shoot = true, Gun = true, Fire = true, ShootGun = true}
    for _, d in ipairs(gun:GetDescendants()) do
        if (d:IsA("RemoteEvent") or d:IsA("RemoteFunction")) and prefer[d.Name] then found = d break end
    end
    if not found then
        for _, d in ipairs(gun:GetDescendants()) do
            if d:IsA("RemoteEvent") then found = d break end
        end
    end
    if not found and getnilinstances then
        for _, o in ipairs(getnilinstances()) do
            if o:IsA("RemoteEvent") and o.Name == "Gun" then found = o break end
        end
    end
    if found then
        shotCache[gun] = found
        pushLog("SHERIFF", "Remote de tir : " .. found.Name .. " (" .. found.ClassName .. ")")
    end
    return found
end

local function runSheriff()
    if not CFG.SA or myRoleCached ~= "sheriff" then return end
    local ch = localPlayer.Character
    local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
    local hum = ch and ch:FindFirstChildOfClass("Humanoid")
    if not hrp or not hum or hum.Health <= 0 then return end
    if CFG.SAWhen == "Sac plein" and not (hiding or bagFullCached()) then return end
    local bp = localPlayer:FindFirstChild("Backpack")
    local gun = ch:FindFirstChild("Gun") or (bp and bp:FindFirstChild("Gun"))
    if not gun or not gun:IsA("Tool") then return end

    local best, bd
    for _, p in ipairs(players:GetPlayers()) do
        if p ~= localPlayer and isAlive(p) and not (CFG.IgnoreFriends and isFriend(p))
            and (roles[p.Name] == "murder" or hasTool(p, "Knife")) then
            local d = (p.Character.HumanoidRootPart.Position - hrp.Position).Magnitude
            if not bd or d < bd then best, bd = p, d end
        end
    end
    if not best then return end

    local pc = best.Character
    local part
    if CFG.SAPart == "Tête" then part = pc:FindFirstChild("Head")
    elseif CFG.SAPart == "HumanoidRootPart" then part = pc:FindFirstChild("HumanoidRootPart")
    else part = pc:FindFirstChild("UpperTorso") or pc:FindFirstChild("Torso") end
    part = part or pc:FindFirstChild("HumanoidRootPart")
    if not part then return end

    if gun.Parent ~= ch then
        pcall(function() hum:EquipTool(gun) end)
        task.wait(0.05)
    end
    local remote = findShootRemote(gun)
    if not remote then return end

    local origin, target = hrp.CFrame, CFrame.new(part.Position)
    local a, b = target, origin
    if CFG.SAOrder == "Origine, Cible" then a, b = origin, target end
    if remote:IsA("RemoteFunction") then
        task.spawn(pcall, remote.InvokeServer, remote, a, b)
    else
        pcall(remote.FireServer, remote, a, b)
    end
end

-- ===== Fling (fin de manche) =====
local function flingTarget(tp, tmax, backCF)
    local ch = localPlayer.Character
    local hum = ch and ch:FindFirstChildOfClass("Humanoid")
    local root = hum and hum.RootPart
    local tch = tp.Character
    local thum = tch and tch:FindFirstChildOfClass("Humanoid")
    local troot = thum and thum.RootPart
    if not (root and troot) or thum.Health <= 0 or thum.Sit then return end

    local function fpos(off, rot)
        root.CFrame = CFrame.new(troot.Position) * off * rot
        root.AssemblyLinearVelocity = Vector3.new(9e7, 9e8, 9e7)
        root.AssemblyAngularVelocity = Vector3.new(9e8, 9e8, 9e8)
        lastTick = os.clock()
        task.wait()
    end

    local t0, ang = os.clock(), 0
    repeat
        if not (root.Parent and troot.Parent) or thum.Health <= 0 or not CFG.FlingEnd then break end
        local spd = troot.AssemblyLinearVelocity.Magnitude
        if spd < 50 then
            ang += 100
            local r = CFrame.Angles(math.rad(ang), 0, 0)
            local mv = thum.MoveDirection
            fpos(CFrame.new(0, 1.5, 0) + mv * spd / 1.25, r)
            fpos(CFrame.new(0, -1.5, 0) + mv * spd / 1.25, r)
            fpos(CFrame.new(0, 1.5, 0) + mv * spd / 1.25, r)
            fpos(CFrame.new(0, -1.5, 0) + mv * spd / 1.25, r)
            fpos(CFrame.new(0, 1.5, 0) + mv, r)
            fpos(CFrame.new(0, -1.5, 0) + mv, r)
        else
            local ws = thum.WalkSpeed
            fpos(CFrame.new(0, 1.5, ws), CFrame.Angles(math.rad(90), 0, 0))
            fpos(CFrame.new(0, -1.5, -ws), CFrame.Angles(0, 0, 0))
            fpos(CFrame.new(0, 1.5, ws), CFrame.Angles(math.rad(90), 0, 0))
            fpos(CFrame.new(0, -1.5, 0), CFrame.Angles(math.rad(90), 0, 0))
            fpos(CFrame.new(0, -1.5, 0), CFrame.Angles(0, 0, 0))
            fpos(CFrame.new(0, -1.5, 0), CFrame.Angles(math.rad(90), 0, 0))
            fpos(CFrame.new(0, -1.5, 0), CFrame.Angles(0, 0, 0))
        end
    until os.clock() - t0 > tmax

    local t1 = os.clock()
    repeat
        root.AssemblyLinearVelocity, root.AssemblyAngularVelocity = Vector3.zero, Vector3.zero
        root.CFrame = backCF
        lastTick = os.clock()
        task.wait()
    until (root.Position - backCF.Position).Magnitude < 25 or os.clock() - t1 > 2
    root.AssemblyLinearVelocity = Vector3.zero
end

local function flingCandidates()
    local out = {}
    for _, p in ipairs(players:GetPlayers()) do
        if p ~= localPlayer and isAlive(p) and inRound(p) and not isFriend(p) then
            local role = roles[p.Name]
            if CFG.FlingTargets == "Tous les joueurs" or role == "murder" or role == "sheriff" then
                out[#out + 1] = p
            end
        end
    end
    return out
end

-- ===== Anti-Fling Intelligent Débrayable =====
local flingLoop = nil
local function togglePhysicalAntiFling(enable)
    if not enable then
        if flingLoop then flingLoop:Disconnect() flingLoop = nil end
        return
    end
    if flingLoop then return end

    flingLoop = RunService.Heartbeat:Connect(function()
        if not CFG.AntiFling or not localPlayer.Character then return end
        for _, p in ipairs(players:GetPlayers()) do
            if p ~= localPlayer and p.Character then
                local hrp = p.Character:FindFirstChild("HumanoidRootPart")
                if hrp and hrp:IsA("BasePart") and not hrp.Anchored then
                    pcall(function()
                        hrp.CustomPhysicalProperties = PhysicalProperties.new(0, 0, 0, 0, 0)
                        hrp.AssemblyLinearVelocity = Vector3.zero
                        hrp.AssemblyAngularVelocity = Vector3.zero
                        hrp.CanCollide = false
                    end)
                end
            end
        end
    end)
end

-- ===== Manche : phases, zone secrète, poignée de main entre amis =====
local phase = "lobby"        -- lobby / pre / round
local preStartT, preArrival, zonePos = 0, nil, nil
local SECRET = 7919          -- code partagé entre tes comptes : change-le (même valeur partout)
local hs = {}                -- handshake : nom -> {hist, time, lastOk, ok}

local function codeAt(t)
    local n = math.floor(t)
    return (n * 7 + (n // 3) * 5 + SECRET) % 16
end

local function yawOf(cf)
    local l = cf.LookVector
    return math.deg(math.atan2(-l.X, -l.Z)) % 360
end

local function myHRP()
    local ch = localPlayer.Character
    return ch and ch:FindFirstChild("HumanoidRootPart"), ch and ch:FindFirstChildOfClass("Humanoid")
end

-- Dans la zone, on se fige et on "parle" : l'angle (yaw) suit un code qui change chaque seconde
RunService.Heartbeat:Connect(function()
    if not zoneActive or not zonePos then return end
    local hrp, hum = myHRP()
    if not hrp or not hum or hum.Health <= 0 then return end
    hum.AutoRotate = false
    local code = codeAt(workspace:GetServerTimeNow())
    hrp.CFrame = CFrame.new(zonePos) * CFrame.Angles(0, math.rad(code * 22.5), 0)
    hrp.AssemblyLinearVelocity = Vector3.zero
    hrp.AssemblyAngularVelocity = Vector3.zero
end)

-- On écoute les autres : leur yaw doit suivre le même code (avec une marge de latence)
task.spawn(function()
    while true do
        task.wait(0.15)
        if zoneActive and phase == "pre" and CFG.AutoFriends and CFG.PreHide == "Zone secrète" then
            pcall(function()
                local t = workspace:GetServerTimeNow()
                local want = {codeAt(t), codeAt(t - 0.25), codeAt(t - 0.5)}
                for _, p in ipairs(players:GetPlayers()) do
                    if p ~= localPlayer and inZone(p) then
                        local hrp = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
                        if hrp then
                            local y, m = yawOf(hrp.CFrame), false
                            for _, c in ipairs(want) do
                                if math.abs((y - c * 22.5 + 180) % 360 - 180) <= 10 then m = true break end
                            end
                            local h = hs[p.Name]
                            if not h then
                                h = {hist = {}, time = 0, lastOk = 0, ok = false}
                                hs[p.Name] = h
                            end
                            h.hist[#h.hist + 1] = m and 1 or 0
                            if #h.hist > 14 then table.remove(h.hist, 1) end
                            local sum = 0
                            for _, v in ipairs(h.hist) do sum += v end
                            h.ok = #h.hist >= 10 and sum / #h.hist >= 0.6
                            if h.ok then
                                h.time += 0.15
                                h.lastOk = os.clock()
                            end
                        end
                    end
                end
            end)
        end
    end
end)

local function leaveZone()
    if not zoneActive then return end
    zoneActive = false
    local _, hum = myHRP()
    if hum then hum.AutoRotate = true end
end

local function finalizeFriends()
    local now = os.clock()
    for name, h in pairs(hs) do
        local p = players:FindFirstChild(name)
        if p and h.time >= CFG.HandshakeMin and now - h.lastOk <= 3 and not autoFriends[name:lower()] then
            autoFriends[name:lower()] = true
            notify("Ami détecté", name .. " (handshake)", 10)
        end
    end
end

local function enterPre()
    local hrp = myHRP()
    if not hrp then return end
    autoFriends, hs = {}, {}
    preStartT, preArrival = os.clock(), hrp.CFrame
    notify("Manche", "Début de manche (pré-manche)", 4)
    if CFG.PreZone and CFG.PreHide ~= "Aucun" then
        if CFG.PreHide == "Zone secrète" then
            zonePos = zoneCenter() + zoneSlotOffset()
        else
            zonePos = preArrival.Position - Vector3.new(0, CFG.SafeDepth, 0)
        end
        zoneActive = true
        hrp.CFrame = CFrame.new(zonePos)
    end
end

local function enterRound(timedOut)
    local hrp = myHRP()
    finalizeFriends()
    leaveZone()
    if not hrp then return end
    local list = scan()
    local best = pickBest(list, hrp.Position, nil, CFG.Killer and getThreats() or {}, nil)
    if best then
        hrp.CFrame = CFrame.new(best.Position)
        hrp.AssemblyLinearVelocity = Vector3.zero
        pcall(function()
            firetouchinterest(hrp, best, 0)
            firetouchinterest(hrp, best, 1)
        end)
        lastAct, lastActT = "tp", os.clock()
    elseif timedOut and preArrival then
        hrp.CFrame = preArrival
    end
end

local function phaseStep()
    local hrp, hum = myHRP()
    if not hrp or not hum or hum.Health <= 0 then 
        if phase ~= "lobby" then
            phase = "lobby"
            pushLog("PHASE", "Reset -> lobby (mort / absent)")
            leaveZone()
        end
        return 
    end

    local currentPos = hrp.Position
    local suddenTeleport = false
    
    if lastKnownPosition then
        local delta = (currentPos - lastKnownPosition).Magnitude
        -- Détection immédiate du gros saut spatial du serveur
        if delta > (CFG.TPDist or 150) then
            suddenTeleport = true
        end
    end
    lastKnownPosition = currentPos

    local cnt = #scan()
    local assassinModeTrigger = (CFG.KAAssassin and assassinTargetName() ~= nil)

    if phase == "lobby" then
        if suddenTeleport or assassinModeTrigger then
            phase = "pre"
            pushLog("PHASE", "lobby -> pre (" .. (suddenTeleport and "Téléportation" or "Cible Assassin détectée") .. ")")
            enterPre()
        end
    elseif phase == "pre" then
        if cnt >= 3 then
            phase = "round"
            pushLog("PHASE", "pre -> round (bonbons : " .. cnt .. ")")
            enterRound(false)
        elseif os.clock() - preStartT > CFG.PreMax then
            phase = "round"
            pushLog("PHASE", "pre -> round (timeout)")
            enterRound(true)
        end
    elseif phase == "round" then
        local a = localPlayer:GetAttribute("Alive")
        local isMatchOver = false
        if CFG.UseAlive and a ~= nil then 
            isMatchOver = (a == false) 
        else 
            isMatchOver = isRoundOver() 
        end
        if isMatchOver or inLobbyPos(currentPos) then
            phase = "lobby"
            pushLog("PHASE", "round -> lobby (Fin de manche)")
            leaveZone()
        end
    end
end


-- ===== Boucle principale =====
local function claims()
    local bv, dir, target, safe
    local spinA, approached, tries, slow = 0, false, 0, false
    local boostOn, boostT, boostCool = false, 0, 0
    local lastEval, dbgT, gT, ghT = 0, 0, 0, 0
    local rOver, bFull = true, false
    local flying, needReset = false, true
    local prevN, roundStartT, roleLogged = nil, 0, true

    while true do
        local dt = RunService.Heartbeat:Wait()
        lastTick = os.clock()
        local now = lastTick

        -- Pré-manche : la zone secrète gère la position (rien à faire ici)
        if zoneActive then
            needReset = true
            task.wait(0.1)
            continue
        end

        if now - gT > 0.1 then
            gT = now
            rOver, bFull = isRoundOver(), isBagFull()
            local n = bagCount()
            if rOver then
                prevN = nil
            elseif n then
                if prevN and n > prevN then stat("candies", n - prevN) end
                prevN = n
            end
        end

        local c = localPlayer.Character
        local hrp = c and c:FindFirstChild("HumanoidRootPart")
        local hum = c and c:FindFirstChildOfClass("Humanoid")

        -- Attente : désactivé / mort / frame Candy invisible / round fini
        if not CFG.Enabled or not hrp or not hum or hum.Health <= 0 or rOver then
            if bv and bv.Parent then bv.MaxForce = Vector3.zero end
            flying, dir, target, needReset, nc, boostOn, safe, hiding = false, nil, nil, true, false, false, nil, false
            clearDebug()
            ghostClear()
            ncRestore()
            -- Lobby / hors manche : on active l'anti-fling
            if CFG.AntiFling then togglePhysicalAntiFling(true) end
            task.wait(0.3)
            continue
        end

        if tChar ~= c then hookTouch(c) end

        if needReset then
            needReset = false
            banned = {}
            mapCenter, mapRadius, mapFloorY = nil, nil, nil
            roundStartT, roleLogged = now, false
            stat("rounds")
            pushLog("ROUND", "Round détecté, collecte lancée")
            notify("Round", "Collecte lancée", 3)
        end

        if not roleLogged and now - roundStartT > 3 then
            roleLogged = true
            local r = myRoleCached or "innocent"
            stat(r == "murder" and "asMurder" or (r == "sheriff" and "asSheriff" or "asInnocent"))
            notify("Ton rôle", r == "murder" and "Tu es MURDER" or (r == "sheriff" and "Tu es SHERIFF" or "Tu es INNOCENT"), 6)
        end

        if not bv or bv.Parent ~= hrp then
            bv = Instance.new("BodyVelocity")
            bv.Name = "AntiFall"
            bv.MaxForce = Vector3.zero
            bv.Velocity = Vector3.zero
            bv.Parent = hrp
        end

        -- Anti-vide : dernière position au sol, retour si on tombe trop bas
        if not flying and hum.FloorMaterial ~= Enum.Material.Air then safe = hrp.CFrame end
        if safe and hrp.Position.Y < safe.Position.Y - 300 then
            hrp.CFrame = safe
            hrp.AssemblyLinearVelocity = Vector3.zero
            dir, target = nil, nil
        end

        -- Sac plein : planque (sous la map ou zone secrète) + fling de fin de manche si activé
        if bFull then
            local back = hrp.CFrame
            local hideCF
            if CFG.HideMode == "Zone secrète" then
                hideCF = CFrame.new(zoneCenter() + zoneSlotOffset())
            else
                hideCF = back - Vector3.new(0, CFG.SafeDepth, 0)
            end
            nc, hiding = true, true
            if CFG.AntiFling then togglePhysicalAntiFling(true) end
            bv.MaxForce, bv.Velocity = BIG, Vector3.zero
            hrp.CFrame = hideCF
            notify("Sac plein", "Planque : " .. CFG.HideMode, 4)
            repeat
                lastTick = os.clock()
                task.wait(0.5)
                if CFG.FlingEnd and myRoleCached == "innocent" and not isRoundOver() then
                    for _, p in ipairs(flingCandidates()) do
                        if not CFG.FlingEnd or isRoundOver() or hum.Health <= 0 then break end
                        flingTarget(p, CFG.FlingTime, hideCF)
                    end
                end
            until not isBagFull() or isRoundOver() or hum.Health <= 0 or not CFG.Enabled
            hiding = false
            if (hrp.Position - hideCF.Position).Magnitude < 100 then hrp.CFrame = back end
            hrp.AssemblyLinearVelocity = Vector3.zero
            bFull, dir, target = false, nil, nil
            continue
        end

        local pos = hrp.Position
        local list = scan()
        updateMap(list)
        local kills = CFG.Killer and getThreats() or {}

        -- Cible : morte = ramassée -> suivante ; ou devenue dangereuse (menace)
        if target then
            if not alive(target) then
                target = nil
            elseif #kills > 0 and now - lastEval > 0.1 then
                lastEval = now
                for _, k in ipairs(kills) do
                    if segDist(pos, target.Position, k) < CFG.KillerR then target = nil break end
                end
            end
        end
        if not target then
            target = pickBest(list, pos, dir, kills, nil)
            approached, tries = false, 0
            if target then slow = not slow end -- alterne la vitesse à chaque nouveau bonbon
        end

        local w, dist
        if target then
            local to = target.Position - pos
            dist = to.Magnitude
            w = dist > 0.01 and to / dist or (dir or Vector3.xAxis)
        else
            -- pas de cible sûre : fuite si une menace est trop proche, sinon on attend
            local fk
            for _, k in ipairs(kills) do
                if (pos - k).Magnitude < CFG.KillerR then fk = k break end
            end
            if fk then
                local a = Vector3.new(pos.X - fk.X, 0, pos.Z - fk.Z)
                w = a.Magnitude > 0.1 and a.Unit or Vector3.xAxis
            else
                bv.MaxForce = Vector3.zero
                flying, dir, nc, boostOn = false, nil, false, false
                ghostClear()
                if CFG.Debug and now - dbgT > 0.1 then
                    dbgT = now
                    updateDebug(list, pos, nil, kills)
                end
                continue
            end
        end

        flying, nc = true, true
        -- On vole vers une cible : on coupe l'anti-fling pour éviter le freeze
        togglePhysicalAntiFling(false)
        bv.MaxForce, bv.Velocity = BIG, Vector3.zero

        -- Bonbon exceptionnellement loin : TP direct dessus puis pause 1 s
        if CFG.TPFar and target and dist > effTP() then
            hrp.CFrame = CFrame.new(target.Position)
            hrp.AssemblyLinearVelocity = Vector3.zero
            firetouchinterest(hrp, target, 0)
            firetouchinterest(hrp, target, 1)
            lastAct, lastActT = "tp", now
            task.wait(1)
            dir, target = nil, nil
            continue
        end

        if not dir then dir = w end

        local sharp = false
        if target then
            if dist < CFG.TouchR * 2 and dir:Dot(w) > 0.5 then approached = true end
            -- bonbon dépassé sans être ramassé : demi-tour sec
            if approached and dist > CFG.MissDist and dir:Dot(w) < 0 then
                dir, sharp, approached = w, true, false
                tries += 1
                if tries >= 3 then banned[target] = now + 3 target = nil end
            end
        end
        if not sharp then
            local maxA = math.rad(CFG.Turn) * dt
            local ang = math.acos(math.clamp(dir:Dot(w), -1, 1))
            if ang <= maxA then
                dir = w
            else
                local ax = dir:Cross(w)
                if ax.Magnitude < 1e-4 then ax = Vector3.yAxis end
                dir = CFrame.fromAxisAngle(ax.Unit, maxA):VectorToWorldSpace(dir)
            end
        end

        -- Boost court : paquet de BoostN bonbons proches, puis pause BoostCool après CHAQUE boost
        local want = false
        if CFG.Boost and target and dist < CFG.BoostR * 2 and now >= boostCool then
            local n = 0
            for _, o in ipairs(list) do
                if (o.Position - target.Position).Magnitude <= CFG.BoostR then n += 1 end
            end
            want = n >= CFG.BoostN and (not boostOn or now - boostT <= CFG.BoostMax)
        end
        if want and not boostOn then
            boostOn, boostT = true, now
        elseif not want and boostOn then
            boostOn, boostCool = false, now + CFG.BoostCool
        end
        if boostOn then lastAct, lastActT = "boost", now
        elseif now - lastActT > 6 then lastAct = "move" end

        -- Déplacement (vitesse alternée / boost) + spin visible serveur
        local base = effSpeed()
        local spd = boostOn and base * effBoost() or (base - (slow and CFG.SpeedVar or 0))
        local np = pos + dir * spd * dt
        
        local rot
        spinA = (spinA + CFG.SpinSpeed * dt) % 360
        
        local flickAngle = 0
        getgenv().LastFlickT = getgenv().LastFlickT or 0
        if now - getgenv().LastFlickT > (CFG.Flick360Interval or 1.2) then
            getgenv().LastFlickT = now
            -- Injection d'un demi-tour sec (180°) + un angle aléatoire pour casser la ligne droite
            flickAngle = math.rad(180 + math.random(-45, 45))
        end

        if CFG.Spin then
            rot = CFrame.Angles(0, math.rad(spinA) + flickAngle, 0)
        else
            local h = Vector3.new(dir.X, 0, dir.Z)
            local baseRot = h.Magnitude > 1e-3 and CFrame.lookAt(Vector3.zero, h) or hrp.CFrame.Rotation
            rot = baseRot * CFrame.Angles(0, flickAngle, 0)
        end
        hrp.CFrame = CFrame.new(np) * rot


        -- Touch fling passif : seulement si un joueur non ami est à proximité
        local fl = false
        if CFG.TouchFling then
            for _, p in ipairs(players:GetPlayers()) do
                if p ~= localPlayer and not isFriend(p) and isAlive(p)
                    and (p.Character.HumanoidRootPart.Position - np).Magnitude <= CFG.TouchFlingR then
                    fl = true
                    break
                end
            end
        end
        if fl then
            hrp.AssemblyLinearVelocity = Vector3.new(0, 1e4, 0)
            local cn
            cn = RunService.RenderStepped:Connect(function()
                cn:Disconnect()
                if hrp.Parent then hrp.AssemblyLinearVelocity = Vector3.zero end
            end)
        else
            hrp.AssemblyLinearVelocity = Vector3.zero
        end

        if CFG.Hitbox and target and target.Size.X < 100 then
            target.CanCollide = false
            target.Size = Vector3.new(100, 100, 100)
        end

        -- Touch en continu sur tout bonbon à portée
        for _, cn in ipairs(list) do
            if (cn.Position - np).Magnitude <= CFG.TouchR then
                firetouchinterest(hrp, cn, 0)
                firetouchinterest(hrp, cn, 1)
            end
        end

        -- Transparence des objets autour
        if CFG.Ghost then
            if now - ghT > 0.15 then
                ghT = now
                ghostUpdate(np)
            end
        else
            ghostClear()
        end

        if CFG.Debug then
            if now - dbgT > 0.1 then
                dbgT = now
                updateDebug(list, np, target, kills)
            end
        else
            clearDebug()
        end
    end
end

-- ===== Restaurer les valeurs par défaut =====
local function restoreDefaults()
    for k, v in pairs(DEFAULTS) do CFG[k] = v end
    for k, c in pairs(COL_DEFAULT) do COL[k] = c end
    parseFriends(CFG.Friends)
    setNoClipMode(CFG.NoClipMode)
    for k, api in pairs(UIREG) do
        pcall(function()
            if k:sub(1, 4) == "col_" then api:Set(COL[k:sub(5)])
            else api:Set(CFG[k]) end
        end)
    end
    cfgDirty = false
    saveSettings()
    notify("Réglages", "Valeurs par défaut restaurées", 4)
end

-- ===== UI (un onglet par thème) =====
local statLbl = {}

pcall(function()
    UILib = loadstring(game:HttpGet("https://raw.githubusercontent.com/Moha-Echo/animated-invention/refs/heads/main/" .. Lib .. "/source.lua"))()
    CTX.Window = UILib:MakeWindow({
        Name = "CandyFarm v9",
        HidePremium = true,
        SaveConfig = false,
    })
    print("[CandyFarm DEBUG] Window =", typeof(CTX.Window),
        "ToggleMinimize =", CTX.Window and typeof(CTX.Window.ToggleMinimize) or "nil")

    local function reg(key, api)
        if type(api) == "table" then UIREG[key] = api end
    end
    local function tg(tab, n, k, cb)
        reg(k, tab:AddToggle({Name = n, Default = CFG[k], Callback = function(v)
            CFG[k] = v
            markDirty()
            if cb then cb(v) end
        end}))
    end
    local function sl(tab, n, k, mn, mx, inc)
        reg(k, tab:AddSlider({Name = n, Min = mn, Max = mx, Default = CFG[k], Increment = inc or 1, Callback = function(v)
            CFG[k] = v
            markDirty()
        end}))
    end
    local function dd(tab, n, k, opts, cb)
        reg(k, tab:AddDropdown({Name = n, Options = opts, Default = CFG[k], Callback = function(v)
            CFG[k] = v
            markDirty()
            if cb then cb(v) end
        end}))
    end
    local function cp(tab, n, key)
        reg("col_" .. key, tab:AddColorpicker({Name = n, Default = COL[key], Callback = function(c)
            COL[key] = c
            markDirty()
        end}))
    end
    local function tb(tab, n, k, cb)
        reg(k, tab:AddTextbox({Name = n, Default = CFG[k], Callback = function(txt)
            CFG[k] = txt
            markDirty()
            if cb then cb(txt) end
        end}))
    end
    local function safeTab(name, fn)
        local ok, tab = pcall(function() return CTX.Window:MakeTab({Name = name}) end)
        if not ok then warn("[UI] onglet " .. name .. " : " .. tostring(tab)) return end
        local ok2, err = pcall(fn, tab)
        if not ok2 then warn("[UI] " .. name .. " : " .. tostring(err)) end
    end

    safeTab("Autos", function(t)
        t:AddSection({Name = "Général"})
        tg(t, "Auto Play (écran Join)", "AutoPlay")
        tg(t, "Auto ramasser le Gun (GunDrop)", "AutoGun")
        tg(t, "Notifications", "Notify")
        tb(t, "Amis (séparés par des virgules)", "Friends", parseFriends)
        tg(t, "Épargner / ignorer les amis", "IgnoreFriends")

        t:AddSection({Name = "Kill Aura Murder"})
        tg(t, "Kill Aura (si tu es Murder)", "KA")
        dd(t, "Portée", "KARange", {"Toute la map", "Rayon"})
        sl(t, "Rayon (studs)", "KARadius", 5, 500)
        dd(t, "Tuer le Sheriff", "KASheriff", {"Sac plein", "Toujours", "Jamais"})
        sl(t, "Intervalle (s)", "KAInterval", 0.1, 1, 0.05)
        tg(t, "Équiper le couteau", "KAEquip")
        tg(t, "Simuler le coup (KnifeStabbed)", "KAStab")

        t:AddSection({Name = "Mode Assassin"})
        tg(t, "Spam dès que Target3 est visible", "KAAssassin")
        sl(t, "Events par frame", "KABurst", 1, 5)

        t:AddSection({Name = "Sheriff Auto Kill"})
        tg(t, "Tir auto sur le Murder (si Gun)", "SA")
        dd(t, "Quand tirer", "SAWhen", {"Sac plein", "Toujours"})
        dd(t, "Partie visée", "SAPart", {"Torse", "HumanoidRootPart", "Tête"})
        dd(t, "Ordre des CFrames du tir", "SAOrder", {"Cible, Origine", "Origine, Cible"})
        sl(t, "Intervalle tir (s)", "SAInterval", 0.05, 1, 0.05)

        t:AddSection({Name = "Fin de manche"})
        tg(t, "Kill final entre amis (cachés)", "FinalKill")
        tg(t, "Fling de fin (si Innocent)", "FlingEnd")
        dd(t, "Cibles du fling", "FlingTargets", {"Murder + Sheriff", "Tous les joueurs"})
        sl(t, "Durée fling / cible (s)", "FlingTime", 1, 6)
        tg(t, "Touch Fling passif", "TouchFling")
        sl(t, "Rayon Touch Fling", "TouchFlingR", 5, 40)
    end)

    safeTab("Manche", function(t)
        t:AddSection({Name = "Détection"})
        tg(t, "Attribut Alive = en manche", "UseAlive")
        t:AddSection({Name = "Pré-manche"})
        tg(t, "Se cacher avant le début", "PreZone")
        dd(t, "Cachette pré-manche", "PreHide", {"Zone secrète", "Sous la map", "Aucun"})
        sl(t, "Attente max (s)", "PreMax", 5, 60)
        t:AddSection({Name = "Planque sac plein"})
        dd(t, "Cachette sac plein", "HideMode", {"Sous la map", "Zone secrète"})
        t:AddSection({Name = "Zone secrète"})
        dd(t, "Repère", "ZoneMode", {"Relatif au Lobby", "Coordonnées fixes"})
        tb(t, "Zone (x, y, z)", "ZoneText", function() zcT = 0 end)
        sl(t, "Rayon de la zone", "ZoneRadius", 20, 200)
        t:AddButton({Name = "Définir la zone ici (ma position)", Callback = function()
            local hrp = myHRP()
            if not hrp then return end
            local off = hrp.Position
            if CFG.ZoneMode == "Relatif au Lobby" then
                local lob = workspace:FindFirstChild("Lobby")
                if lob then off = hrp.Position - lob:GetPivot().Position end
            end
            CFG.ZoneText = ("%.1f, %.1f, %.1f"):format(off.X, off.Y, off.Z)
            zcT = 0
            if UIREG.ZoneText then pcall(function() UIREG.ZoneText:Set(CFG.ZoneText) end) end
            markDirty()
            notify("Zone", "Zone définie : " .. CFG.ZoneText, 5)
        end})
        t:AddSection({Name = "Amis automatiques"})
        tg(t, "Détecter les amis (handshake)", "AutoFriends")
        sl(t, "Durée min du handshake (s)", "HandshakeMin", 1, 6, 0.5)
    end)

    safeTab("Farm", function(t)
        tg(t, "Auto Farm", "Enabled")
        tg(t, "Paquets (cluster)", "Cluster")
        sl(t, "Rayon paquet", "ClusterR", 5, 100)
        sl(t, "Priorité paquets", "ClusterW", 0, 40)
        sl(t, "Bonbons avant planque", "FullAt", 1, 50)
        sl(t, "Profondeur planque", "SafeDepth", 50, 400)
        tg(t, "Hitbox cible", "Hitbox")
    end)

    safeTab("Mouvement", function(t)
        sl(t, "Vitesse", "Speed", 10, 120)
        sl(t, "Variation vitesse (-N)", "SpeedVar", 0, 5)
        sl(t, "Virage (°/s)", "Turn", 90, 1080)
        sl(t, "Rayon touch", "TouchR", 3, 30)
        tg(t, "Spin", "Spin")
        sl(t, "Vitesse spin", "SpinSpeed", 60, 1080)
    end)

    safeTab("Boost & TP", function(t)
        tg(t, "Boost sur paquet", "Boost")
        sl(t, "Multiplicateur boost", "BoostMult", 1, 4, 0.1)
        sl(t, "Bonbons min pour boost", "BoostN", 2, 6)
        sl(t, "Rayon paquet boost", "BoostR", 5, 50)
        sl(t, "Durée max boost (s)", "BoostMax", 1, 6, 0.5)
        sl(t, "Pause après boost (s)", "BoostCool", 0, 60)
        tg(t, "TP si bonbon très loin", "TPFar")
        sl(t, "Distance TP", "TPDist", 150, 1500)
    end)

    safeTab("Menaces", function(t)
        tg(t, "Éviter les menaces", "Killer")
        tg(t, "Seulement si elle tient un Tool", "KillerHunt")
        sl(t, "Rayon menace", "KillerR", 10, 60)
    end)

    safeTab("Visuel", function(t)
        t:AddSection({Name = "Debug"})
        tg(t, "Debug visuel", "Debug")
        tg(t, "Transparence autour", "Ghost")
        sl(t, "Rayon transparence", "GhostR", 4, 40)
        t:AddSection({Name = "Highlights joueurs"})
        tg(t, "Highlights actifs", "HL")
        tg(t, "Highlight innocents", "HLInnocent")
        tg(t, "Highlight amis", "HLFriends")
        cp(t, "Couleur Murder", "Murder")
        cp(t, "Couleur Sheriff", "Sheriff")
        cp(t, "Couleur Innocents", "Innocent")
        cp(t, "Couleur Amis", "Friend")
        cp(t, "Couleur ta cible (Assassin)", "Target")
        sl(t, "Transparence remplissage", "HLFill", 0, 1, 0.05)
        sl(t, "Transparence contour", "HLOutline", 0, 1, 0.05)
    end)

    safeTab("Stats", function(t)
        for _, k in ipairs({"candies", "rounds", "kills", "guns", "roles", "cph", "est", "time", "kicks", "phase"}) do
            statLbl[k] = t:AddLabel("...")
        end
        sl(t, "Durée d'un round (min)", "RoundMinutes", 1, 6, 0.5)
        t:AddButton({Name = "Reset stats de session", Callback = function()
            for k in pairs(ST) do ST[k] = 0 end
            sessionStart = os.clock()
        end})
    end)

    safeTab("Sécurité", function(t)
        t:AddSection({Name = "Connexion"})
        tg(t, "Auto Rejoin (anti-kick)", "AutoRejoin")
        tg(t, "Rejoindre aussi sur autre erreur", "RejoinOnAnyError")
        tb(t, "Mots-clés d'un vrai kick", "KickKeywords")
        t:AddSection({Name = "Protection"})
        tg(t, "Anti-Fling Intelligent", "AntiFling", function(v) togglePhysicalAntiFling(v) end)
        dd(t, "NoClip", "NoClipMode", {"Off", "Stepped", "Touched"}, setNoClipMode)
        t:AddSection({Name = "Réglages"})
        t:AddButton({Name = "Reset pénalités kick", Callback = function()
            S.boostPen, S.speedPen, S.tpPen, S.kicks = 0, 0, 0, 0
            saveState()
        end})
        t:AddButton({Name = "Sauvegarder les réglages maintenant", Callback = function()
            saveSettings()
            notify("Réglages", "Sauvegardés", 3)
        end})
        t:AddButton({Name = "Restaurer les valeurs par défaut", Callback = restoreDefaults})
    end)
end)
uiReady = true

pushLog("SYSTEM", "CandyFarm v9 prêt" .. (settingsLoaded and " (réglages restaurés)" or ""))

if Lib == "1bzableLib" then
    if CTX.Window and typeof(CTX.Window.ToggleMinimize) == "function" then
        CTX.Window:ToggleMinimize()
    else
        warn("[CandyFarm DEBUG] 1bzableLib: ToggleMinimize absent")
    end
else
    if UILib and typeof(UILib.ToggleMinimize) == "function" then
        UILib:ToggleMinimize()
    end
end

-- ===== Lancement des modules =====
watchPlayers()
startAutoPlay()
startGunWatch()

-- Liaison sur le Heartbeat pour ne rater aucune frame du saut spatial du serveur
RunService.Heartbeat:Connect(function()
    pcall(phaseStep)
end)


task.spawn(function()
    while true do
        pcall(runKillAura)
        task.wait(math.max(0.05, CFG.KAInterval))
    end
end)

RunService.Heartbeat:Connect(function()
    pcall(assassinStep)
end)

task.spawn(function()
    while true do
        pcall(runSheriff)
        task.wait(math.max(0.05, CFG.SAInterval))
    end
end)

-- Stats : affichage (1 s) + sauvegarde des stats (20 s) + sauvegarde des réglages (après modification)
task.spawn(function()
    local n = 0
    while true do
        task.wait(1)
        n += 1
        if n % 20 == 0 and statDirty then
            statDirty = false
            saveState()
        end
        if cfgDirty and os.clock() - cfgDirtyT > 1.5 then
            cfgDirty = false
            saveSettings()
        end
        if statLbl.candies then
            pcall(function()
                local L = S.life
                local el = os.clock() - sessionStart
                local hours = el / 3600
                local names = {}
                for name in pairs(autoFriends) do names[#names + 1] = name end
                statLbl.candies:Set(("Bonbons : %.0f (total %.0f)"):format(ST.candies, L.candies or 0))
                statLbl.rounds:Set(("Rounds : %.0f (total %.0f)"):format(ST.rounds, L.rounds or 0))
                statLbl.kills:Set(("Kills : %.0f (total %.0f)"):format(ST.kills, L.kills or 0))
                statLbl.guns:Set(("Gun récupéré : %.0f (total %.0f)"):format(ST.guns, L.guns or 0))
                statLbl.roles:Set(("Murder %.0f | Sheriff %.0f | Innocent %.0f"):format(ST.asMurder, ST.asSheriff, ST.asInnocent))
                statLbl.cph:Set(el > 120 and ("Bonbons/h (réel) : %.0f"):format(ST.candies / hours) or "Bonbons/h (réel) : calcul en cours...")
                statLbl.est:Set(ST.rounds > 0
                    and ("Estimation (%.1f min/round) : %.0f/h"):format(CFG.RoundMinutes, (ST.candies / ST.rounds) * (60 / CFG.RoundMinutes))
                    or "Estimation : en attente d'un round")
                statLbl.time:Set(("Session : %02d:%02d:%02d"):format(el // 3600, (el % 3600) // 60, el % 60))
                statLbl.kicks:Set(("Kicks : %.0f | Pénalités : speed -%.0f, boost -%.1f, TP +%.0f"):format(S.kicks, S.speedPen, S.boostPen, S.tpPen))
                statLbl.phase:Set(("Phase : %s | Amis auto : %s"):format(phase, #names > 0 and table.concat(names, ", ") or "aucun"))
            end)
        end
    end
end)

local farmThread
local function startFarm()
    if farmThread then pcall(task.cancel, farmThread) end
    local r = localPlayer.Character and localPlayer.Character:FindFirstChild("HumanoidRootPart")
    local old = r and r:FindFirstChild("AntiFall")
    if old then old:Destroy() end
    nc, hiding = false, false
    lastTick = os.clock()
    farmThread = task.spawn(function()
        while true do
            local ok, err = pcall(claims)
            if not ok then warn("[CandyFarm] boucle relancée : " .. tostring(err)) end
            nc, hiding = false, false
            task.wait(1)
        end
    end)
end
startFarm()

-- Watchdog (1 s) : la frame Candy est visible mais la boucle est figée -> relance
local lastActive
task.spawn(function()
    while true do
        task.wait(1)
        local f = candyFrame()
        local icon = f and f:FindFirstChild("CurrencyFrame") and f.CurrencyFrame:FindFirstChild("Icon")
        local active = f ~= nil and f.Visible and icon ~= nil and icon.Visible
        if active ~= lastActive then
            lastActive = active
            pushLog("WATCHDOG", "Candy.Visible=" .. tostring(f and f.Visible) .. " Icon.Visible=" .. tostring(icon and icon.Visible))
        end
        if active and CFG.Enabled and os.clock() - lastTick > 3 then
            pushLog("WATCHDOG", "Boucle figée, relance")
            startFarm()
        end
    end
end)
