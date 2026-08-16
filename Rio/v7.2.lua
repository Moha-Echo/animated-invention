--[[
    rio V7 — 5 TAB VERIFIED BUILD
    Base : VFX / Alliés / Spin / Auto Case
    Added : Combat
    One Orion window only. This build contains only the requested tab UI
    plus the dependency kernel required for those modules.
]]

--[[
    rio IA v7.2
    [🚢 CARGO] DUELS DE COUTEAUX
    V7 — architecture unifiée : tracking cible, visibilité, mouvement persistant, anti-stuck, Copy robuste, IA Lointain, ESP/PiP.
    CORRECTIF : détection des équipes via attributs (GetAttribute) au lieu d'instances.
]]

------------------------------------------------------------
-- SERVICES & NETTOYAGE
------------------------------------------------------------
local Lib = "1bzableLib"
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local PathfindingService = game:GetService("PathfindingService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local Workspace = game:GetService("Workspace")
local Camera = workspace.CurrentCamera
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local playerGui = LocalPlayer:WaitForChild("PlayerGui")

--========================================================--
-- CTX : état partagé compact pour réduire les local registers
--========================================================--
local CTX = {}

-- Runtime singleton : nettoie l'ancienne instance de rio V7 avant re-exécution.
if _G.rioV7Runtime and _G.rioV7Runtime.Shutdown then
    pcall(function() _G.rioV7Runtime.Shutdown() end)
end

local Runtime = { Connections = {}, Drawings = {}, Shutdown = nil }

local function trackConnection(connection)
    if connection then table.insert(Runtime.Connections, connection) end
    return connection
end

local function trackDrawing(drawing)
    if drawing then table.insert(Runtime.Drawings, drawing) end
    return drawing
end

Runtime.Shutdown = function()
    for _, connection in ipairs(Runtime.Connections) do
        pcall(function() connection:Disconnect() end)
    end
    for _, drawing in ipairs(Runtime.Drawings) do
        pcall(function()
            drawing.Visible = false
            drawing:Remove()
        end)
    end
    table.clear(Runtime.Connections)
    table.clear(Runtime.Drawings)
end

_G.rioV7Runtime = Runtime

for _, guiName in ipairs({"rio v2.0", "rio v3.0", "rio v4.0",  "rio v5.0", "rio v7.0", "rio v7.2"}) do
    local old = game:GetService("CoreGui"):FindFirstChild(guiName)
    if old then old:Destroy() end
end

------------------------------------------------------------
-- CONFIG GLOBALE
------------------------------------------------------------
_G.AimbotMode = "Full Lock"
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
CTX.ALLY_COLOR = Color3.fromRGB(0, 255, 90)

-- Jeu de référence : HP = attribut Character, tir à distance = clic droit.
CTX.KNIFE_DUEL_GAME_ID = 9641502068
CTX.USE_GAME_HP = (game.GameId == CTX.KNIFE_DUEL_GAME_ID)

-- Forward declarations : certaines connexions sont installées avant les fonctions.
local stopMovement
local logStateOnce
local waitAndScanGameTeams
local registerAIDeath
local OrionLib
local pressInput
local scheduleRelease
local fireM2
local getAimPart
local resetAimPart
local isEntityActuallyVisible
local isEntityDangerous
local canAimAtEntity
local function updateFOVCircleVisibility()
    if not CTX.fovCircle then
        return
    end

    CTX.fovCircle.Visible =
        CTX.aimbotActive
        and _G.AimbotMode == "FOV Circle"
end
CTX.GAME_TEAMMATE_HIGHLIGHT = "MatchTeammateHighlight"
CTX.GAME_ENEMY_HIGHLIGHT = "MatchEnemyHighlight"
CTX.aimbotActive = false
CTX.currentTarget = nil
CTX.trackedTarget = nil
CTX.AutoShootEnabled = false
CTX.CombatConfig = {
    AttackCooldownM2 = 0.1,
}
CTX.AutoShootLastM2 = 0
CTX.NoEnemyFinishCooldown = 2.5
CTX.LastNoEnemyFinish = 0
CTX.MatchState = {
    MatchDetectionRunning = true,
    Ended = false,
    PlayersProtected = false,
    LastEndTime = 0
}

-- Cible persistante de l'IA : tracking séparé du verrouillage caméra.
CTX.AITarget = nil
CTX.AITargetSince = 0
CTX.AITargetLastValid = 0
CTX.AITargetLastVisible = false
CTX.AILastAcquire = 0
CTX.AIState = {
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
    RecoveryStartPosition = nil,

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
CTX.fovRadius = 130
CTX.whitelistedAllies = {}
CTX.detectedRoundEnemies = {}
CTX.TeamScanState = {
    Locked = false,
    Scanning = false,
    StartedAt = 0,
    ExpectedAllies = 0,
    ExpectedEnemies = 0,
}
CTX.RoundEntities = {}
CTX.TargetMode = "Les deux"
CTX.targetAimParts = {}
CTX.BotCharactersCached = {}
CTX.LastBotScanTime = 0
CTX.BotScanInterval = 0.35

-- Ragdolls : indice supplémentaire de mort et éléments à exclure du scanner de bots.
CTX.RagdollFolderName = "RagdollVisualProxies"
CTX.RagdollProxySuffix = "_RagdollVisualProxy"

-- Origine des tracers.
CTX.TracerOrigin = "Bas milieu"

CTX.lastTargetTime = 0
CTX.tpBehindOffset = 4


-- ==========================================
-- CONFIGURATION ET TABLE DES OFFSETS PAR COUTEAU
-- ==========================================
CTX.OffsetsConfig = {
    -- Vos valeurs de réglages parfaites pour le SkeletonV2
    ["SkeletonV2"] = {
        Position = Vector3.new(0.3, -1.7, 0),
        Rotation = CFrame.Angles(math.rad(350), math.rad(0), math.rad(200))
    },
    -- Exemple pour une Bayonet si elle flotte (à ajuster au besoin)
    ["Bayonet"] = {
        Position = Vector3.new(0.2, -1.5, -0.2),
        Rotation = CFrame.Angles(math.rad(0), math.rad(90), math.rad(0))
    },
    -- Configuration par défaut générique si le couteau n'est pas dans la liste
    ["Default"] = {
        Position = Vector3.new(0, -1.7, 0),
        Rotation = CFrame.Angles(math.rad(0), math.rad(0), math.rad(0))
    }
}


CTX.Skin = {
    EnabledModel = false,
    EnabledSkin = false,
    EnabledVFX = false,
    EnabledTrail = false,

    Intensity = 1,
    Knife = "SkeletonV2",
    Skin = "HologramSkeleton",
    Texture = "HologramSkeleton",
    VFX = "Divine",

    OriginalViewModelName = nil,
    OriginalBackup = nil,
    BackupDone = false,
}


-- Services Roblox
local Debris = game:GetService("Debris")
local SoundService = game:GetService("SoundService")

-- Récupération des dossiers d'Assets
local assets = ReplicatedStorage:WaitForChild("Assets")
local knifeTextures = assets:WaitForChild("KnifeTextures")
local knifeVFX = assets:WaitForChild("KnifeVFX")          
local throwFX = assets:WaitForChild("Sounds"):WaitForChild("ThrowFX")
local viewmodelsFolder = assets:WaitForChild("Viewmodels")
local knifeThrowModels = assets:WaitForChild("KnifeThrowModels")
 

 
-- ==========================================
-- FONCTION : TROUVER LE VIEWMODEL DYNAMIQUEMENT
-- ==========================================
local function trouverViewModelActuel()
    Camera = workspace.CurrentCamera or Camera

    if not Camera then
        return nil
    end

    for _, child in ipairs(Camera:GetChildren()) do
        if child:IsA("Model")
            and child:FindFirstChild("Knife")
        then
            return child
        end
    end

    return nil
end
-- ==========================================
-- FONCTION : RECONSTRUIRE ET APPLIQUER LES VFX & TRAILS
-- ==========================================
local function appliquerEffetsEtTrails(mainMesh, sourceVFX, conteneurParent, estUnCouteauLance)
    -- Nettoyage des anciens composants
    for _, obj in pairs(mainMesh:GetChildren()) do
        if obj:IsA("ParticleEmitter") or obj:IsA("Attachment") or obj:IsA("Trail") then
            obj:Destroy()
        end
    end
    for _, obj in pairs(conteneurParent:GetChildren()) do
        if obj:IsA("Part") and obj.Name == "vfx" then
            obj:Destroy()
        end
    end

    if not CTX.Skin.EnabledVFX or not sourceVFX then return end

    local attachmentsClones = {}

    for _, vfxObj in pairs(sourceVFX:GetChildren()) do
        -- 1. Particules standards
        if vfxObj:IsA("ParticleEmitter") then
            local clone = vfxObj:Clone()
            -- Ajustement de l'intensité via le curseur (Rate d'origine modifié)
            clone.Rate = clone.Rate * CTX.Skin.Intensity
            clone.Parent = mainMesh
            
        -- 2. Attachments & Traînées
        elseif vfxObj:IsA("Attachment") then
            local cloneAttach = vfxObj:Clone()
            cloneAttach.Parent = mainMesh
            attachmentsClones[cloneAttach.Name] = cloneAttach
            
            -- Gestion des taux de particules internes aux attachments si présents
            for _, subParticule in pairs(cloneAttach:GetChildren()) do
                if subParticule:IsA("ParticleEmitter") then
                    subParticule.Rate = subParticule.Rate * CTX.Skin.Intensity
                end
            end
            
            if CTX.Skin.EnabledTrail or estUnCouteauLance then
                local foundTrail = cloneAttach:FindFirstChildOfClass("Trail")
                if foundTrail then
                    local att0 = cloneAttach:FindFirstChild("0") or attachmentsClones["0"]
                    local att1 = cloneAttach:FindFirstChild("1") or attachmentsClones["1"]
                    if att0 and att1 then
                        foundTrail.Attachment0 = att0
                        foundTrail.Attachment1 = att1
                    else
                        local fallback0 = mainMesh:FindFirstChild("TrailAtt0") or Instance.new("Attachment", mainMesh)
                        fallback0.Name = "TrailAtt0"
                        fallback0.Position = Vector3.new(0, 0, -0.8)
                        
                        local fallback1 = mainMesh:FindFirstChild("TrailAtt1") or Instance.new("Attachment", mainMesh)
                        fallback1.Name = "TrailAtt1"
                        fallback1.Position = Vector3.new(0, 0, 0.8)
                        
                        foundTrail.Attachment0 = fallback0
                        foundTrail.Attachment1 = fallback1
                    end
                end
            else
                local trailObj = cloneAttach:FindFirstChildOfClass("Trail")
                if trailObj then trailObj:Destroy() end
            end
            
        -- 3. Sous-parties physiques complexes (ex: Void, Glacier...)
        elseif vfxObj:IsA("Part") and vfxObj.Name == "vfx" then
            local clonePartVfx = vfxObj:Clone()
            clonePartVfx.Parent = conteneurParent
            clonePartVfx.CFrame = mainMesh.CFrame
            
            -- Ajustement de l'intensité sur la visibilité de la pièce d'effet
            if CTX.Skin.Intensity <= 0.05 then
                clonePartVfx.Transparency = 1
            else
                clonePartVfx.Transparency = 1 - CTX.Skin.Intensity
            end
            
            for _, subObj in pairs(clonePartVfx:GetDescendants()) do
                if subObj:IsA("ParticleEmitter") then
                    subObj.Rate = subObj.Rate * CTX.Skin.Intensity
                elseif subObj:IsA("Trail") and not CTX.Skin.EnabledTrail and not estUnCouteauLance then
                    subObj:Destroy()
                end
            end
            
            local motor = Instance.new("Motor6D")
            motor.Name = "VFX_Motor"
            motor.Part0 = mainMesh
            motor.Part1 = clonePartVfx
            motor.Parent = clonePartVfx
        end
    end
end


local function getSelectedSkinTexture()
    return CTX.Skin.Texture
        or CTX.Skin.Skin
        or "HologramSkeleton"
end
-- ==========================================
-- FONCTION REVISÉE : TOTALEMENT INDÉPENDANTE POUR LES TOGGLES
-- ==========================================
local function actualiserViewmodel()
    local targetViewModel = trouverViewModelActuel()
    if not targetViewModel then return end
    
    -- 1. Sauvegarde unique du couteau serveur d'origine dès sa première détection
    if not CTX.Skin.BackupDone then
        local baseKnife = targetViewModel:FindFirstChild("Knife")
        if baseKnife then
            originalViewModelName = targetViewModel.Name
            CTX.Skin.OriginalBackup = baseKnife:Clone() -- Sauvegarde complète (Skin + Modèle d'origine)
            CTX.Skin.BackupDone = true
        end
    end

    local currentKnife = targetViewModel:FindFirstChild("Knife")

    -- ==========================================
    -- ÉTAPE A : GESTION DE LA STRUCTURE DU MODÈLE (TOGGLE 1)
    -- ==========================================
    if CTX.Skin.EnabledModel then
        -- On ne recrée le modèle custom que s'il n'est pas déjà présent ou s'il a changé
        if not currentKnife or currentKnife:GetAttribute("CustomModelName") ~= CTX.Skin.Knife then
            if currentKnife then currentKnife:Destroy() end
            
            local sourcePrefab = viewmodelsFolder:FindFirstChild(CTX.Skin.Knife)
            if sourcePrefab then
                local newKnife = sourcePrefab:WaitForChild("Knife"):Clone()
                newKnife:SetAttribute("CustomModel", true)
                newKnife:SetAttribute("CustomModelName", CTX.Skin.Knife)
                newKnife.Parent = targetViewModel
                currentKnife = newKnife
                
                local jointPart = targetViewModel:FindFirstChild("Right Arm")
                local handle = newKnife:FindFirstChild("Handle") or newKnife:FindFirstChild("Main")
                if jointPart and handle then
                    local motor = Instance.new("Motor6D")
                    motor.Name = "KnifeMotor"
                    motor.Part0 = jointPart
                    motor.Part1 = handle
                    
                    -- Lecture de vos offsets personnalisés
                    local cfg = CTX.OffsetsConfig[CTX.Skin.Knife] or CTX.OffsetsConfig["Default"]
                    motor.C0 = CFrame.new(cfg.Position) * cfg.Rotation
                    motor.Parent = handle
                end
            end
        end
    else
        -- Si le changer est FALSE mais qu'un modèle custom tourne encore, on le vire pour restaurer l'origine
        if currentKnife and currentKnife:GetAttribute("CustomModel") == true then
            currentKnife:Destroy()
            currentKnife = nil
        end
        
        -- Restauration physique de la copie conforme de l'arme serveur d'origine
        if not currentKnife and CTX.Skin.OriginalBackup then
            local restoredKnife = CTX.Skin.OriginalBackup:Clone()
            restoredKnife.Parent = targetViewModel
            currentKnife = restoredKnife
            
            local jointPart = targetViewModel:FindFirstChild("Right Arm")
            local handle = restoredKnife:FindFirstChild("Handle") or restoredKnife:FindFirstChild("Main")
            if jointPart and handle then
                local motor = Instance.new("Motor6D")
                motor.Name = "KnifeMotor"
                motor.Part0 = jointPart
                motor.Part1 = handle
                motor.Parent = handle
            end
        end
    end

    -- Si on n'a trouvé aucun couteau à ce stade, on stoppe pour éviter les erreurs
    if not currentKnife then return end

    -- ==========================================
    -- ÉTAPE B : APPLICATION DES SKINS ET EFFECTS (INDÉPENDANTS)
    -- ==========================================
    local mainMesh = currentKnife:FindFirstChild("Main") or currentKnife:FindFirstChild("Handle")
    if not mainMesh and currentKnife:FindFirstChild("Knife") then
        mainMesh = currentKnife.Knife:FindFirstChild("Main") or currentKnife.Knife:FindFirstChild("Handle")
    end
    
    if mainMesh then
        -- Gestion indépendante du SKIN
        if CTX.Skin.EnabledSkin then
            local sourceTexture =
                knifeTextures:FindFirstChild(
                    getSelectedSkinTexture()
                )
            if sourceTexture then
                for _, obj in pairs(mainMesh:GetChildren()) do
                    if obj:IsA("SurfaceAppearance") or obj:IsA("Texture") then obj:Destroy() end
                end
                sourceTexture:Clone().Parent = mainMesh
            end
        else
            -- Si désactivé, on nettoie
            for _, obj in pairs(mainMesh:GetChildren()) do
                if obj:IsA("SurfaceAppearance") or obj:IsA("Texture") then obj:Destroy() end
            end
            -- Si on est sur l'arme d'origine, on lui remet sa vraie texture de sauvegarde
            if not CTX.Skin.EnabledModel and CTX.Skin.OriginalBackup then
                local originalMain = CTX.Skin.OriginalBackup:FindFirstChild("Main") or CTX.Skin.OriginalBackup:FindFirstChild("Handle")
                if originalMain then
                    for _, origObj in pairs(originalMain:GetChildren()) do
                        if origObj:IsA("SurfaceAppearance") or origObj:IsA("Texture") then
                            origObj:Clone().Parent = mainMesh
                        end
                    end
                end
            end
        end
        
        -- Gestion indépendante des VFX (Marche sur l'arme de base comme sur l'arme custom !)
        local sourceVFX = knifeVFX:FindFirstChild(CTX.Skin.VFX)
        appliquerEffetsEtTrails(mainMesh, sourceVFX, currentKnife, false)
    end
end


-- ==========================================
-- FONCTION : INJECTER SUR LES COUTEAUX LANCÉS
-- ==========================================
local function makeKnifeVisualPartSafe(part)
    if not part or not part:IsA("BasePart") then
        return
    end

    part.CanCollide = false
    part.CanTouch = false
    part.CanQuery = false
    part.Massless = true
end


local function injecterCouteauLance(thrownKnife)
    if not thrownKnife
        or not thrownKnife.Parent
    then
        return
    end

    -- Son uniquement : aucun changement physique du projectile.
    if throwFX then
        local soundTrack =
            throwFX:FindFirstChild(CTX.Skin.VFX)

        if soundTrack
            and soundTrack:IsA("Sound")
        then
            local localSound = soundTrack:Clone()
            localSound.Parent = SoundService
            localSound:Play()

            Debris:AddItem(
                localSound,
                localSound.TimeLength + 0.2
            )
        end
    end

    local centerPart =
        thrownKnife:FindFirstChild("Center")
        or thrownKnife:FindFirstChildOfClass("BasePart")

    if not centerPart
        or not centerPart:IsA("BasePart")
    then
        return
    end

    -- Le projectile original reste intact.
    -- On ajoute uniquement une représentation visuelle non physique.
    local visualModel = nil
    local mainMesh = centerPart

    if CTX.Skin.EnabledModel then
        local modelAlternatif =
            knifeThrowModels:FindFirstChild(
                CTX.Skin.Knife
            )

        if modelAlternatif then
            visualModel = Instance.new("Model")
            visualModel.Name = "rioKnifeVisual"
            visualModel.Parent = thrownKnife

            for _, item in ipairs(
                modelAlternatif:GetChildren()
            ) do
                if item.Name ~= "Center" then
                    local cloneItem = item:Clone()
                    cloneItem.Parent = visualModel

                    if cloneItem:IsA("BasePart") then
                        makeKnifeVisualPartSafe(cloneItem)
                        cloneItem.CFrame = centerPart.CFrame

                        local weld =
                            Instance.new("WeldConstraint")

                        weld.Part0 = centerPart
                        weld.Part1 = cloneItem
                        weld.Parent = cloneItem
                    else
                        for _, descendant in ipairs(
                            cloneItem:GetDescendants()
                        ) do
                            if descendant:IsA("BasePart") then
                                makeKnifeVisualPartSafe(
                                    descendant
                                )
                            end
                        end

                        local visualRoot =
                            cloneItem.PrimaryPart
                            or cloneItem:FindFirstChildWhichIsA(
                                "BasePart",
                                true
                            )

                        if visualRoot then
                            cloneItem:PivotTo(
                                centerPart.CFrame
                            )

                            local weld =
                                Instance.new(
                                    "WeldConstraint"
                                )

                            weld.Part0 = centerPart
                            weld.Part1 = visualRoot
                            weld.Parent = visualRoot
                        end
                    end
                end
            end

            local visualMain =
                visualModel:FindFirstChild(
                    "Main",
                    true
                )

            if visualMain
                and visualMain:IsA("BasePart")
            then
                mainMesh = visualMain
            end
        end
    end

    if not mainMesh then
        return
    end

    if CTX.Skin.EnabledSkin then
        local sourceTexture =
            knifeTextures:FindFirstChild(
                getSelectedSkinTexture()
            )

        if sourceTexture then
            for _, obj in ipairs(
                mainMesh:GetDescendants()
            ) do
                if obj:IsA("SurfaceAppearance")
                    or obj:IsA("Texture")
                then
                    obj:Destroy()
                end
            end

            sourceTexture:Clone().Parent = mainMesh
        end
    end

    local sourceVFX =
        knifeVFX:FindFirstChild(
            CTX.Skin.VFX
        )

    appliquerEffetsEtTrails(
        mainMesh,
        sourceVFX,
        visualModel or thrownKnife,
        true
    )
end


-- Écouteur pour les lancers
workspace.ChildAdded:Connect(function(child)
    if child.Name == "ThrownKnife" then
        task.wait(0.02)
        injecterCouteauLance(child)
    end
end)

--========================================================--
-- AIMBOT : SYSTÈME DE PRIORITÉS
--========================================================--
CTX.AimbotPriorityConfig = {
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
CTX.logLines, CTX.maxLogLines = {}, 14

local function refreshLogText()
    if CTX.logText then CTX.logText.Text = #CTX.logLines > 0 and table.concat(CTX.logLines, "\n") or "En attente..." end
end

local function setLogVisible(v) if CTX.logGui then CTX.logGui.Enabled = v end end

local function pushLog(tag, message)
    local line = ("[%s] %s"):format(tostring(tag), tostring(message))
    print("[rio V7] " .. line)
    table.insert(CTX.logLines, 1, line)
    while #CTX.logLines > CTX.maxLogLines do table.remove(CTX.logLines) end
    refreshLogText()
end

------------------------------------------------------------
-- ENTITY SYSTEM : JOUEURS + BOTS
------------------------------------------------------------

local function getEntityCharacter(entity)
    if not entity then
        return nil
    end

    if entity:IsA("Player") then
        return entity.Character
    end

    if entity:IsA("Model") then
        return entity
    end

    return nil
end

local function getEntityName(entity)
    local character = getEntityCharacter(entity)

    if entity and entity:IsA("Player") then
        return entity.Name
    end

    if character then
        local hum = character:FindFirstChildOfClass("Humanoid")
        local displayName = hum and hum.DisplayName
        if type(displayName) == "string" and displayName ~= "" then
            return character.Name .. " (" .. displayName .. ")"
        end
        return character.Name
    end

    return "Unknown"
end

local function isBotEntity(entity)
    return entity
        and entity:IsA("Model")
        and entity ~= LocalPlayer.Character
end

local function isTargetTypeAllowed(entity)
    if not entity then
        return false
    end

    if entity:IsA("Player") then
        return CTX.TargetMode == "Joueurs"
            or CTX.TargetMode == "Les deux"
    end

    if entity:IsA("Model") then
        return CTX.TargetMode == "Bots"
            or CTX.TargetMode == "Les deux"
    end

    return false
end

local function isCharacterOwnedByPlayer(character)
    if not character then
        return false
    end

    for _, player in ipairs(Players:GetPlayers()) do
        if player.Character == character then
            return true
        end
    end

    return false
end

local function getRagdollProxy(entity)
    local folder =
        workspace:FindFirstChild(
            CTX.RagdollFolderName
        )

    if not folder or not entity then
        return nil
    end

    local name

    if entity:IsA("Player") or entity:IsA("Model") then
        name =
            entity.Name
            .. CTX.RagdollProxySuffix
    else
        return nil
    end

    return folder:FindFirstChild(name)
end

local function isEntityRagdolled(entity)
    return getRagdollProxy(entity) ~= nil
end

local function isRagdollModel(model)
    if not model or not model:IsA("Model") then
        return false
    end

    local folder =
        workspace:FindFirstChild(
            CTX.RagdollFolderName
        )

    if folder and model:IsDescendantOf(folder) then
        return true
    end

    return model.Name:sub(
        -#CTX.RagdollProxySuffix
    ) == CTX.RagdollProxySuffix
end

local function getTracerOrigin(camera)
    if CTX.TracerOrigin == "Centre" then
        return Vector2.new(
            camera.ViewportSize.X / 2,
            camera.ViewportSize.Y / 2
        )
    end

    return Vector2.new(
        camera.ViewportSize.X / 2,
        camera.ViewportSize.Y
    )
end

local function refreshBotCharactersIfNeeded(force)
    if CTX.TargetMode == "Joueurs" and not force then
        return
    end

    local now = os.clock()

    if not force
        and now - CTX.LastBotScanTime < CTX.BotScanInterval
    then
        return
    end

    CTX.LastBotScanTime = now
    CTX.BotCharactersCached = {}

    local localCharacter = LocalPlayer.Character
    local seen = {}

    for _, model in ipairs(workspace:GetDescendants()) do
        if model:IsA("Model")
            and model ~= localCharacter
            and not isCharacterOwnedByPlayer(model)
            and not isRagdollModel(model)
        then
            local hum = model:FindFirstChildOfClass("Humanoid")
            local head = model:FindFirstChild("Head")
            local root = model:FindFirstChild("HumanoidRootPart")

            if hum and head and root then
                local hasDuelMarker =
                    model:GetAttribute("HP") ~= nil
                    or model:GetAttribute("DuelEliminated") ~= nil
                    or model:FindFirstChild(CTX.GAME_TEAMMATE_HIGHLIGHT, true) ~= nil
                    or model:FindFirstChild(CTX.GAME_ENEMY_HIGHLIGHT, true) ~= nil

                if not CTX.USE_GAME_HP or hasDuelMarker then
                    if not seen[model] then
                        seen[model] = true
                        table.insert(
                            CTX.BotCharactersCached,
                            model
                        )
                    end
                end
            end
        end
    end
end

local function collectAllCombatEntities()
    local entities = {}

    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer
            and player.Character
            and player.Character:FindFirstChild("HumanoidRootPart")
        then
            table.insert(entities, player)
        end
    end

    refreshBotCharactersIfNeeded(true)

    for _, model in ipairs(CTX.BotCharactersCached) do
        if model.Parent
            and model:FindFirstChild("HumanoidRootPart")
        then
            table.insert(entities, model)
        end
    end

    return entities
end

local function collectTargetEntities()
    refreshBotCharactersIfNeeded(false)

    local entities = {}
    local seen = {}

    if CTX.TargetMode == "Joueurs"
        or CTX.TargetMode == "Les deux"
    then
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer
                and player.Character
                and player.Character:FindFirstChild("HumanoidRootPart")
            then
                if not seen[player] then
                    seen[player] = true
                    table.insert(entities, player)
                end
            end
        end
    end

    if CTX.TargetMode == "Bots"
        or CTX.TargetMode == "Les deux"
    then
        for _, model in ipairs(CTX.BotCharactersCached) do
            if model.Parent
                and model:FindFirstChild("HumanoidRootPart")
            then
                if not seen[model] then
                    seen[model] = true
                    table.insert(entities, model)
                end
            end
        end
    end

    return entities
end

------------------------------------------------------------
-- DUEL : VALIDATION CIBLE (HP / DuelEliminated)
------------------------------------------------------------
local function getDuelHP(entity)
    local char = getEntityCharacter(entity)

    if not char then
        return nil
    end

    if CTX.USE_GAME_HP then
        return char:GetAttribute("HP")
    end

    local hum = char:FindFirstChildOfClass("Humanoid")
    return hum and hum.Health or nil
end

local function isEntityAlive(entity)
    if not entity then
        return false
    end

    if entity:IsA("Player")
        and entity == LocalPlayer
    then
        return false
    end

    local char =
        getEntityCharacter(entity)

    if not char then
        return false
    end

    if not char:FindFirstChild("HumanoidRootPart") then
        return false
    end

    -- Un proxy ragdoll confirme une mort, mais son absence
    -- ne suffit jamais à déclarer l'entité vivante.
    if isEntityRagdolled(entity) then
        return false
    end

    if char:GetAttribute("DuelEliminated") == true then
        return false
    end

    -- Dans le jeu de duel, HP est la seule source de vérité.
    -- S'il manque, l'entité est considérée comme invalide.
    local hp = getDuelHP(entity)

    return hp ~= nil and hp > 0
end

local function isDuelTargetActive(entity)
    if not entity then
        return false
    end

    if entity:IsA("Player") and entity == LocalPlayer then
        return false
    end

    if not isTargetTypeAllowed(entity) then
        return false
    end

    if CTX.whitelistedAllies[entity] then
        return false
    end

    return isEntityAlive(entity)
end


local function getEntityESPFolder(entity)
    if not entity or not CTX.ESP.folder then
        return nil
    end

    local folderName =
        entity.Name .. "_Skeleton_ESP"

    local folder =
        CTX.ESP.folder:FindFirstChild(folderName)

    if not folder then
        folder = Instance.new("Folder")
        folder.Name = folderName
        folder.Parent = CTX.ESP.folder
    end

    return folder
end


local function applyAllyHighlight(entity)
    local char = getEntityCharacter(entity)

    if not char then
        return
    end

    local folder =
        getEntityESPFolder(entity)

    if not folder then
        return
    end

    local hl =
        folder:FindFirstChild("rioAllyHighlight")

    if not hl then
        hl = Instance.new("Highlight")
        hl.Name = "rioAllyHighlight"
        hl.Adornee = char
        hl.Parent = folder
    end

    hl.FillColor = CTX.ALLY_COLOR
    hl.OutlineColor = CTX.ALLY_COLOR
    hl.FillTransparency = 0.45
    hl.OutlineTransparency = 0
    hl.DepthMode =
        Enum.HighlightDepthMode.AlwaysOnTop
    hl.Adornee = char
    hl.Enabled = true
end


local function clearAllyHighlight(entity)
    if not entity or not CTX.ESP.folder then
        return
    end

    local folderName =
        entity.Name .. "_Skeleton_ESP"

    local folder =
        CTX.ESP.folder:FindFirstChild(folderName)

    if not folder then
        return
    end

    local ally =
        folder:FindFirstChild("rioAllyHighlight")

    if ally then
        ally:Destroy()
    end
end

local function protectAllPlayersAfterMatch()
    CTX.MatchState.Ended = true
    CTX.MatchState.PlayersProtected = true
    CTX.MatchState.LastEndTime = os.clock()

    -- L'IA ne doit plus avoir de cible.
    CTX.AITarget = nil
    CTX.trackedTarget = nil
    CTX.currentTarget = nil

    -- Tous les joueurs deviennent temporairement alliés.
    for _, entity in ipairs(collectAllCombatEntities()) do
        CTX.whitelistedAllies[entity] = true
        applyAllyHighlight(entity)
    end

    pushLog(
        "MATCH",
        "Fin du duel détectée : tous les joueurs sont temporairement protégés."
    )

    pcall(function()
        OrionLib:SendTelemetryEvent(
            "match_end",
            "Winscreen détecté",
            "None"
        )
    end)
end

local function clearMatchProtection()
    if not CTX.MatchState.Ended then
        return
    end

    for player in pairs(CTX.whitelistedAllies) do
        clearAllyHighlight(player)
    end

    table.clear(CTX.whitelistedAllies)

    CTX.MatchState.Ended = false
    CTX.MatchState.PlayersProtected = false
    CTX.LastNoEnemyFinish = 0

    CTX.AITarget = nil
    CTX.trackedTarget = nil
    CTX.currentTarget = nil
    CTX.AutoShootLastM2 = 0
    CTX.StrafeSlideActive = false
    CTX.StrafeSlideEndTime = 0
    CTX.LastStrafeSlide = -math.huge
    table.clear(CTX.targetAimParts)

    _G.ThroughWall = false
    _G.AimSmooth = 1

    CTX.AIState.StuckMemory = {}

    CTX.AIState.CurrentStuckKey = nil
    CTX.AIState.CurrentStuckAttempt = nil
    CTX.AIState.RecoveryStartPosition = nil

    CTX.AIState.StuckSince = nil
    CTX.AIState.StuckStage = 0

    CTX.AIState.TemporaryRecoveryStyle = nil
    CTX.AIState.RecoveryOriginalStyle = nil
    CTX.AIState.RecoveryStartedAt = 0

    table.clear(CTX.detectedRoundEnemies)
    CTX.RoundEntities = {}
    CTX.BotCharactersCached = {}
    CTX.TeamScanState.Locked = false
    CTX.TeamScanState.Scanning = false
    CTX.TeamScanState.StartedAt = 0
    CTX.TeamScanState.ExpectedAllies = 0
    CTX.TeamScanState.ExpectedEnemies = 0

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
OrionLib = loadstring(game:HttpGet("https://raw.githubusercontent.com/Moha-Echo/animated-invention/refs/heads/main/".. Lib .."/source.lua"))()
CTX.Window = OrionLib:MakeWindow({
    Name = "rio v7.2",
    HidePremium = true,
    SaveConfig = false,
})

print(
    "[rio DEBUG] Window =",
    typeof(CTX.Window),
    "ToggleMinimize =",
    CTX.Window and typeof(CTX.Window.ToggleMinimize) or "nil"
)
------------------------------------------------------------
-- ONGLET VFX
-- ==========================================
local ChangerTab = CTX.Window:MakeTab({
    Name = "VFX",
    Icon = "rbxassetid://4483345998",
    PremiumOnly = false
})

local couteauxDisponibles = {}
for _, child in pairs(knifeThrowModels:GetChildren()) do table.insert(couteauxDisponibles, child.Name) end

local skinsDisponibles = {}
for _, child in pairs(knifeTextures:GetChildren()) do table.insert(skinsDisponibles, child.Name) end

local vfxDisponibles = {}
for _, child in pairs(knifeVFX:GetChildren()) do table.insert(vfxDisponibles, child.Name) end

-- MODEL CHANGER
ChangerTab:AddToggle({
    Name = "Activer Knife Changer",
    Default = true,
    Callback = function(Value)
        CTX.Skin.EnabledModel = Value
        actualiserViewmodel()
    end
})

ChangerTab:AddDropdown({
    Name = "Choisir Knife Model",
    Default = "SkeletonV2",
    Options = couteauxDisponibles,
    Callback = function(Value)
        CTX.Skin.Knife = Value
        if CTX.Skin.EnabledModel then actualiserViewmodel() end
    end    
})

-- SKINS
ChangerTab:AddToggle({
    Name = "Activer le Skin",
    Default = true,
    Callback = function(Value)
        CTX.Skin.EnabledSkin = Value
        actualiserViewmodel()
    end
})

ChangerTab:AddDropdown({
    Name = "Choisir le Skin",
    Default = "HologramSkeleton",
    Options = skinsDisponibles,
    Callback = function(Value)
        CTX.Skin.Texture = Value
        if CTX.Skin.EnabledSkin then actualiserViewmodel() end
    end    
})

-- EFFETS (VFX)
ChangerTab:AddToggle({
    Name = "Activer VFX",
    Default = true,
    Callback = function(Value)
        CTX.Skin.EnabledVFX = Value
        actualiserViewmodel()
    end
})

ChangerTab:AddDropdown({
    Name = "Choisir VFX",
    Default = "Divine",
    Options = vfxDisponibles,
    Callback = function(Value)
        CTX.Skin.VFX = Value
        if CTX.Skin.EnabledVFX then actualiserViewmodel() end
    end    
})

-- CURSEUR D'INTENSITÉ VFX
ChangerTab:AddSlider({
    Name = "Intensité VFX",
    Min = 0,
    Max = 100,
    Default = 75,
    Color = Color3.fromRGB(0, 170, 255),
    Increment = 5,
    ValueName = "%",
    Callback = function(Value)
        CTX.Skin.Intensity = Value / 100
        actualiserViewmodel()
    end    
})

-- TRAÎNÉE
ChangerTab:AddToggle({
    Name = "Activer la Trail",
    Default = true,
    Callback = function(Value)
        CTX.Skin.EnabledTrail = Value
        actualiserViewmodel()
    end
})

-- ONGLET ALLIÉS
------------------------------------------------------------

CTX.AlliesTab = CTX.Window:MakeTab({ Name = "Alliés", Icon = "rbxassetid://4483345998", PremiumOnly = false })
CTX.totalJoueurs = #Players:GetPlayers()
CTX.defaultMatchFormat = "2v2"
if CTX.totalJoueurs == 2 then CTX.defaultMatchFormat = "1v1"
elseif CTX.totalJoueurs == 4 then CTX.defaultMatchFormat = "2v2"
elseif CTX.totalJoueurs == 6 then CTX.defaultMatchFormat = "3v3"
elseif CTX.totalJoueurs == 8 then CTX.defaultMatchFormat = "4v4"
end

CTX.AlliesTab:AddDropdown({
    Name = "Format du Match",
    Default = CTX.defaultMatchFormat,
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
            if not CTX.whitelistedAllies[p] then
                CTX.whitelistedAllies[p] = true
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

CTX.AlliesTab:AddButton({ Name = "Scanner les Alliés (Touche V)", Callback = triggerAutomaticFetch })
CTX.AlliesTab:AddButton({
    Name = "Vider la Liste",
    Callback = function()
        for p in pairs(CTX.whitelistedAllies) do clearAllyHighlight(p) end
        table.clear(CTX.whitelistedAllies)
        sendNotification("Whitelist", "Tous les alliés ont été retirés.")
    end,
})
CTX.AlliesTab:AddButton({ Name = "White List ALL", Callback = function()
        -- Tous les joueurs deviennent temporairement alliés.
        for _, entity in ipairs(collectAllCombatEntities()) do
            CTX.whitelistedAllies[entity] = true
            applyAllyHighlight(entity)
        end 
    end,
})

------------------------------------------------------------
-- ONGLET SPIN
------------------------------------------------------------
CTX.SpinTab = CTX.Window:MakeTab({ Name = "Spin", Icon = "rbxassetid://4483345998", PremiumOnly = false })

CTX.SpinTab:AddToggle({
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

CTX.SpinTab:AddDropdown({ Name = "Type de Rendu", Default = "Serveur", Options = {"Client", "Serveur"}, Callback = function(v) _G.SpinBotMode = v end })
CTX.SpinTab:AddSlider({ Name = "Vitesse", Min = 10, Max = 350, Default = 100, Increment = 10, ValueName = "vitesse", Callback = function(v) _G.SpinSpeed = v end })

------------------------------------------------------------

trackConnection(RunService.RenderStepped:Connect(function() 
    Camera = workspace.CurrentCamera or Camera 
    local center = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2) 
    if CTX.fovCircle then 
        CTX.fovCircle.Position = center 
        CTX.fovCircle.Color = _G.FOVColor or CTX.fovCircle.Color 
    end 
    local char = LocalPlayer.Character 
    local hrp = char and char:FindFirstChild("HumanoidRootPart") 
    local hum = char and char:FindFirstChildOfClass("Humanoid") 
    if _G.SpinBotEnabled and hrp and hum and hum.Health > 0 then 
        CTX.currentAngle = (CTX.currentAngle + _G.SpinSpeed) % 360 
        local radAngle = math.rad(CTX.currentAngle) 
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
end))
local shopFrame = playerGui:WaitForChild("Shop"):WaitForChild("Frame")
local container = shopFrame:WaitForChild("Container")
local cratesFolder = container:WaitForChild("ScrollingFrame"):WaitForChild("Crates")
local cashTextLabel = shopFrame:WaitForChild("Topbar"):WaitForChild("Cash"):WaitForChild("TextLabel")

-- Références des boutons de la boutique
local detailsButtons = container:WaitForChild("Details"):WaitForChild("Buttons")
local globalOpenButton = detailsButtons:WaitForChild("Open"):WaitForChild("Button")
local globalBuyButton = detailsButtons:WaitForChild("Buy"):WaitForChild("Button")

-- Nouvelles références pour skip et fermer l'aperçu
local crateOpeningGui = playerGui:WaitForChild("CrateOpening")
local skipButton = crateOpeningGui:WaitForChild("Frame"):WaitForChild("Skip"):WaitForChild("Button")

local inspectGui = playerGui:WaitForChild("Inspect")
local leaveButton = inspectGui:WaitForChild("Frame"):WaitForChild("Leave"):WaitForChild("Button")

-- Variables d'état
local autoCaseEnabled = false
local selectedCrate = nil
local casesToOpen = 0 -- 0 = infini

-- Convertisseur de texte d'argent
local function parseCash(text)
    if not text then return 0 end
    text = string.upper(text:gsub("%s+", ""))
    local multiplier = 1
    if string.find(text, "K") then
        multiplier = 1000
        text = text:gsub("K", "")
    elseif string.find(text, "M") then
        multiplier = 1000000
        text = text:gsub("M", "")
    elseif string.find(text, "B") then
        multiplier = 1000000000
        text = text:gsub("B", "")
    end
    local num = tonumber(text)
    return num and (num * multiplier) or 0
end

-- Récupération de la liste des caisses
local function getCrateList()
    local list = {}
    for _, crate in pairs(cratesFolder:GetChildren()) do
        if crate:IsA("Frame") and crate.Name ~= "template" then
            table.insert(list, crate.Name)
        end
    end
    return list
end

-- Fonction pour forcer l'affichage de tout le chemin jusqu'au bouton
local function forceVisibility(object)
    local current = object
    while current and current ~= game and current ~= playerGui do
        if current:IsA("ScreenGui") then
            current.Enabled = true
        elseif current:IsA("GuiObject") then
            current.Visible = true
        end
        current = current.Parent
    end
end

-- Méthode de clic ultra-robuste universel
local function secureClick(button)
    if not button then return end
    
    forceVisibility(button)
    task.wait(0.05)
    
    for _, connection in ipairs(getconnections(button.MouseButton1Click)) do
        connection:Fire()
    end
    for _, connection in ipairs(getconnections(button.MouseButton1Down)) do
        connection:Fire()
    end
    for _, connection in ipairs(getconnections(button.Activated)) do
        connection:Fire()
    end
end

-- Logique dédiée à la gestion de la cinématique et de l'aperçu du couteau reçu
local function handleSkipAndLeave()
    task.spawn(function()
        -- 1. Attente courte et clic sur Skip pour passer l'animation de la caisse
        task.wait(0.1)
        secureClick(skipButton)
        
        -- 2. Attente de 0.5 seconde demandée puis clic sur Leave pour quitter la frame de l'arme obtenue
        task.wait(0.5)
        secureClick(leaveButton)
    end)
end

--=====================================================
-- Fenêtre Orion
--=====================================================

local CaseTab = CTX.Window:MakeTab({Name = "Auto Case", Icon = "rbxassetid://4483345998", PremiumOnly = false})
local Section = CaseTab:AddSection({Name = "Configuration"})

-- 1. Dropdown
local CrateDropdown = CaseTab:AddDropdown({
    Name = "Select Case",
    Default = "None",
    Options = getCrateList(),
    Callback = function(Value)
        selectedCrate = Value
        OrionLib:MakeNotification({
            Name = "Caisse Sélectionnée",
            Content = "Tu as choisi : " .. Value,
            Time = 3
        })
        
        local crateFrame = cratesFolder:FindFirstChild(selectedCrate)
        if crateFrame and crateFrame:FindFirstChild("Button") then
            secureClick(crateFrame.Button)
        end
    end
})

-- 2. Textbox
CaseTab:AddTextbox({
    Name = "Select Number (0 = Inf)",
    Default = "0",
    TextDisappear = false,
    Callback = function(Value)
        local num = tonumber(Value)
        casesToOpen = (num and num >= 0) and num or 0
    end
})

-- Boutons Manuels
CaseTab:AddButton({
    Name = "Buy Once",
    Callback = function()
        secureClick(globalBuyButton)
    end
})

CaseTab:AddButton({
    Name = "Open Once",
    Callback = function()
        secureClick(globalOpenButton)
        handleSkipAndLeave() -- Applique aussi le skip/leave en mode manuel
    end
})

-- 3. Boucle Auto Case
CaseTab:AddToggle({
    Name = "Auto Case",
    Default = false,
    Callback = function(Value)
        autoCaseEnabled = Value
        
        if autoCaseEnabled then
            task.spawn(function()
                local openedCount = 0
                
                while autoCaseEnabled do
                    task.wait(0.3) -- Délai de stabilité entre les cycles d'UI
                    
                    if not selectedCrate then continue end
                    
                    local crateFrame = cratesFolder:FindFirstChild(selectedCrate)
                    if not crateFrame then continue end
                    
                    -- Lecture du stock possédé
                    local ownedLabel = crateFrame.Button:FindFirstChild("Owned")
                    local ownedAmount = ownedLabel and parseCash(ownedLabel.Text) or 0
                    
                    if ownedAmount > 0 then
                        -- Action d'ouverture
                        secureClick(globalOpenButton)
                        handleSkipAndLeave() -- Déclenche la fermeture ultra rapide de l'animation
                        
                        openedCount = openedCount + 1
                        if casesToOpen > 0 and openedCount >= casesToOpen then
                            autoCaseEnabled = false
                            break
                        end
                        
                        -- On ajoute une pause supplémentaire pour laisser le script fermer l'aperçu avant la prochaine boucle
                        task.wait(0.6)
                    else
                        -- Action d'achat
                        local priceLabel = crateFrame:FindFirstChild("Cash") and crateFrame.Cash:FindFirstChild("TextLabel")
                        if not priceLabel then continue end
                        
                        local price = parseCash(priceLabel.Text)
                        local currentMoney = parseCash(cashTextLabel.Text)
                        
                        if currentMoney < price then
                            autoCaseEnabled = false
                            OrionLib:MakeNotification({
                                Name = "Fonds insuffisants",
                                Content = "Plus assez d'argent !",
                                Time = 5
                            })
                            break
                        end
                        
                        secureClick(globalBuyButton)
                    end
                end
            end)
        end
    end
})

------------------------------------------------------------
-- ONGLET COMBAT
------------------------------------------------------------
CTX.CombatTab = CTX.Window:MakeTab({ Name = "Combat", Icon = "rbxassetid://4483345998", PremiumOnly = false })

CTX.CombatTab:AddDropdown({
    Name = "Mode visée",
    Default = "Full Lock",
    Options = {"FOV Circle", "Champ de Vision", "Full Lock"},
    Callback = function(v) _G.AimbotMode = v updateFOVCircleVisibility() end,
})

CTX.CombatTab:AddDropdown({
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

CTX.CombatTab:AddDropdown({
    Name = "Type de cibles",
    Default = "Les deux",
    Options = {"Joueurs", "Bots", "Les deux"},
    Callback = function(v)
        CTX.TargetMode = v
        CTX.trackedTarget = nil
        CTX.currentTarget = nil
        CTX.AITarget = nil
        CTX.RoundEntities = {}
        table.clear(CTX.detectedRoundEnemies)
        CTX.TeamScanState.Locked = false
        CTX.TeamScanState.Scanning = false
    end,
})

CTX.CombatTab:AddSlider({
    Name = "Taille FOV",
    Min = 0,
    Max = 600,
    Default = CTX.fovRadius,
    Increment = 10,
    ValueName = "px",
    Callback = function(v)
        CTX.fovRadius = math.max(0, v)
        if CTX.fovCircle then
            CTX.fovCircle.Radius = CTX.fovRadius
        end
        updateFOVCircleVisibility()
    end,
})

CTX.CombatTab:AddToggle({
    Name = "Auto Shoot",
    Default = true,
    Callback = function(v)
        CTX.AutoShootEnabled = v
    end
})

CTX.CombatTab:AddSlider({
    Name = "Cooldown Auto Shoot",
    Min = 0.1,
    Max = 1,
    Default = 0.1,
    Increment = 0.05,
    ValueName = "s",
    Callback = function(v)
        CTX.CombatConfig.AttackCooldownM2 = v
    end,
})

CTX.CombatTab:AddToggle({ Name = "Wallbang", Default = false, Callback = function(v) _G.ThroughWall = v end })

--========================================================--
-- PRIORITÉS DE SÉLECTION
--========================================================--
CTX.PriorityOptions = {
    "Visibilité",
    "Dangereux",
    "Plus proche",
    "Plus proche du viseur"
}

CTX.CombatTab:AddDropdown({
    Name = "Priorité 1",
    Default = CTX.AimbotPriorityConfig.Primary,
    Options = CTX.PriorityOptions,

    Callback = function(value)
        CTX.AimbotPriorityConfig.Primary = value
        CTX.trackedTarget = nil
        CTX.currentTarget = nil
        CTX.AITarget = nil
    end
})

CTX.CombatTab:AddDropdown({
    Name = "Priorité 2",
    Default = CTX.AimbotPriorityConfig.Secondary,
    Options = CTX.PriorityOptions,

    Callback = function(value)
        CTX.AimbotPriorityConfig.Secondary = value
        CTX.trackedTarget = nil
        CTX.currentTarget = nil
        CTX.AITarget = nil
    end
})

CTX.CombatTab:AddDropdown({
    Name = "Priorité 3",
    Default = CTX.AimbotPriorityConfig.Tertiary,
    Options = CTX.PriorityOptions,

    Callback = function(value)
        CTX.AimbotPriorityConfig.Tertiary = value
        CTX.trackedTarget = nil
        CTX.currentTarget = nil
        CTX.AITarget = nil
    end
})

CTX.CombatTab:AddColorpicker({
    Name = "Couleur FOV",
    Default = Color3.fromRGB(255, 0, 0),
    Callback = function(v)
        _G.FOVColor = v
        if CTX.fovCircle then CTX.fovCircle.Color = v end
    end,
})

CTX.CombatTab:AddSlider({
    Name = "Lissage (IA + Aimbot)",
    Min = 1, Max = 10, Default = 3,
    Color = Color3.fromRGB(255, 100, 0), Increment = 1, ValueName = "/10",
    Callback = function(v) _G.AimSmooth = v / 10 end,
})

CTX.CombatTab:AddSlider({
    Name = "Cooldown cible",
    Min = 0, Max = 100, Default = 10,
    Color = Color3.fromRGB(0, 100, 255), Increment = 5, ValueName = "ms",
    Callback = function(v) _G.LockCooldown = v / 100 end,
})

CTX.CombatTab:AddSlider({
    Name = "Réévaluation cible",
    Min = 1,
    Max = 30,
    Default = 1,
    Increment = 1,
    ValueName = "x10 ms",

    Callback = function(v)
        CTX.AimbotPriorityConfig.RecheckInterval = v / 100
    end
})

CTX.CombatTab:AddParagraph("Raccourcis", "J = Aimbot | V = Alliés | L = REC | P = Copy")

-- MOTEUR AIMBOT (visée seulement si cible visible + vivante)
------------------------------------------------------------
CTX.fovCircle = trackDrawing(Drawing.new("Circle"))
CTX.fovCircle.Color = _G.FOVColor
CTX.fovCircle.Thickness = 1.5
CTX.fovCircle.Radius = CTX.fovRadius
CTX.fovCircle.Transparency = 0.8
CTX.fovCircle.Visible = CTX.aimbotActive
CTX.fovCircle.Filled = false
updateFOVCircleVisibility()

UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.KeyCode == Enum.KeyCode.J then
        CTX.aimbotActive = not CTX.aimbotActive
        CTX.currentTarget = nil
        CTX.trackedTarget = nil
        updateFOVCircleVisibility()
        sendNotification("Aimbot", CTX.aimbotActive and "ACTIVÉ" or "DÉSACTIVÉ")
    end
end)


--========================================================--
-- TARGET VALIDATION + PRIORITY ENGINE
--========================================================--

local function hasGameHighlight(entity, highlightName)
    if not entity or not highlightName then
        return false
    end

    local char = getEntityCharacter(entity)
    if not char then
        return false
    end

    if char:GetAttribute(highlightName) ~= nil then
        return true
    end

    return char:FindFirstChild(highlightName, true) ~= nil
end

local function isEnemyValidForTracking(entity)
    if not entity then
        return false
    end

    if entity:IsA("Player")
        and entity == LocalPlayer
    then
        return false
    end

    if not isTargetTypeAllowed(entity) then
        return false
    end

    if CTX.whitelistedAllies[entity] then
        return false
    end

    if not isEntityAlive(entity) then
        return false
    end

    if CTX.TeamScanState.Locked then
        return CTX.detectedRoundEnemies[entity] == true
    end

    if hasGameHighlight(
        entity,
        CTX.GAME_ENEMY_HIGHLIGHT
    ) then
        return true
    end

    if hasGameHighlight(
        entity,
        CTX.GAME_TEAMMATE_HIGHLIGHT
    ) then
        CTX.whitelistedAllies[entity] = true
        return false
    end

    return true
end

local function getTargetPriorityValue(entity, priority)
    local char = getEntityCharacter(entity)
    if not char then
        return nil
    end

    local root = char:FindFirstChild("HumanoidRootPart")
    local part = getAimPart(entity)

    if priority == "Visibilité" then
        return isEntityActuallyVisible(entity) and 1 or 0
    end

    if priority == "Dangereux" then
        return isEntityDangerous(entity) and 1 or 0
    end

    if priority == "Plus proche" then
        local localChar = LocalPlayer.Character
        local localRoot =
            localChar and localChar:FindFirstChild("HumanoidRootPart")

        if not localRoot or not root then
            return nil
        end

        return -(root.Position - localRoot.Position).Magnitude
    end

    if priority == "Plus proche du viseur" then
        if not part then
            return nil
        end

        local screenPos =
            Camera:WorldToViewportPoint(part.Position)

        local center =
            Vector2.new(
                Camera.ViewportSize.X / 2,
                Camera.ViewportSize.Y / 2
            )

        return -(
            Vector2.new(screenPos.X, screenPos.Y) - center
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
        CTX.AimbotPriorityConfig.Primary,
        CTX.AimbotPriorityConfig.Secondary,
        CTX.AimbotPriorityConfig.Tertiary,
    }

    for _, priority in ipairs(priorities) do
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

    local localChar = LocalPlayer.Character
    local localRoot =
        localChar
        and localChar:FindFirstChild("HumanoidRootPart")

    local candidateChar = getEntityCharacter(candidate)
    local currentChar = getEntityCharacter(current)

    local candidateRoot =
        candidateChar
        and candidateChar:FindFirstChild("HumanoidRootPart")

    local currentRoot =
        currentChar
        and currentChar:FindFirstChild("HumanoidRootPart")

    if localRoot and candidateRoot and currentRoot then
        local candidateDistance =
            (candidateRoot.Position - localRoot.Position).Magnitude

        local currentDistance =
            (currentRoot.Position - localRoot.Position).Magnitude

        return candidateDistance < currentDistance
    end

    return false
end

local function searchBestTarget()
    local candidates = {}

    for _, entity in ipairs(collectTargetEntities()) do
        if isEnemyValidForTracking(entity) then
            local part = getAimPart(entity)

            if part then
                local screenPos, onScreen =
                    Camera:WorldToViewportPoint(
                        part.Position
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

                if _G.AimbotMode == "FOV Circle" then
                    validForMode =
                        onScreen
                        and screenDistance <= CTX.fovRadius

                elseif _G.AimbotMode == "Champ de Vision" then
                    validForMode = onScreen

                elseif _G.AimbotMode == "Full Lock" then
                    validForMode = true
                end

                if validForMode then
                    table.insert(
                        candidates,
                        entity
                    )
                end
            end
        end
    end

    if #candidates == 0 then
        return nil
    end

    -- Visibilité obligatoire lorsque Wallbang est désactivé.
    if not _G.ThroughWall then
        local visibleCandidates = {}

        for _, entity in ipairs(candidates) do
            if isEntityActuallyVisible(entity) then
                table.insert(
                    visibleCandidates,
                    entity
                )
            end
        end

        if #visibleCandidates == 0 then
            return nil
        end

        candidates = visibleCandidates
    end

    local bestTarget = nil

    for _, entity in ipairs(candidates) do
        if isBetterTarget(entity, bestTarget) then
            bestTarget = entity
        end
    end

    return bestTarget
end

local function getBodyAimPart(character)
    if not character then
        return nil
    end

    local upperTorso = character:FindFirstChild("UpperTorso")
    if upperTorso then return upperTorso end

    local torso = character:FindFirstChild("Torso")
    if torso then return torso end

    return character:FindFirstChild("HumanoidRootPart")
end

getAimPart = function(entity)
    if not entity then return nil end
    local character = getEntityCharacter(entity)

    if not character then
        return nil
    end

    if _G.AimPartMode == "Head" then
        return character:FindFirstChild("Head")
    end

    if _G.AimPartMode == "Body" then
        return getBodyAimPart(character)
    end

    local cached =
        CTX.targetAimParts[entity]

    if cached
        and cached.Parent
        and cached:IsDescendantOf(character)
    then
        return cached
    end

    CTX.targetAimParts[entity] = nil

    local head = character:FindFirstChild("Head")
    local body = getBodyAimPart(character)

    if not head and not body then
        return nil
    end

    if not body then
        CTX.targetAimParts[entity] = head
        return head
    end

    if not head then
        CTX.targetAimParts[entity] = body
        return body
    end

    if math.random() <= 0.30 then
        CTX.targetAimParts[entity] = head
    else
        CTX.targetAimParts[entity] = body
    end

    return CTX.targetAimParts[entity]
end

resetAimPart = function(entity)
    if entity then
        CTX.targetAimParts[entity] = nil
    end
end

isEntityActuallyVisible = function(entity)
    if not isDuelTargetActive(entity) then
        return false
    end

    local targetChar =
        getEntityCharacter(entity)

    local localChar =
        LocalPlayer.Character

    if not targetChar or not localChar then
        return false
    end

    local localHead =
        localChar:FindFirstChild("Head")

    local targetPart =
        getAimPart(entity)

    if not localHead
        or not targetPart
        or not targetPart:IsDescendantOf(targetChar)
    then
        resetAimPart(entity)
        return false
    end

    local params = RaycastParams.new()
    params.FilterType =
        Enum.RaycastFilterType.Blacklist

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

local function isTargetVisible(entity)
    if _G.ThroughWall then
        return true
    end

    return isEntityActuallyVisible(entity)
end

isEntityDangerous = function(entity)
    if not isDuelTargetActive(entity) then
        return false
    end

    local localChar =
        LocalPlayer.Character

    local targetChar =
        getEntityCharacter(entity)

    if not localChar or not targetChar then
        return false
    end

    local localHead =
        localChar:FindFirstChild("Head")

    local targetHead =
        targetChar:FindFirstChild("Head")

    if not localHead or not targetHead then
        return false
    end

    local directionToUs =
        localHead.Position
        - targetHead.Position

    if directionToUs.Magnitude <= 0.01 then
        return true
    end

    local dot =
        targetHead.CFrame.LookVector.Unit:Dot(
            directionToUs.Unit
        )

    return dot >=
        CTX.AimbotPriorityConfig.DangerThreshold
end

canAimAtEntity = function(entity)
    if not isDuelTargetActive(entity) then
        return false
    end

    if CTX.whitelistedAllies[entity] then
        return false
    end

    local char =
        getEntityCharacter(entity)

    if not char then
        return false
    end

    local aimPart =
        getAimPart(entity)

    if not aimPart then
        return false
    end

    local screenPos, onScreen =
        Camera:WorldToViewportPoint(
            aimPart.Position
        )

    local center =
        Vector2.new(
            Camera.ViewportSize.X / 2,
            Camera.ViewportSize.Y / 2
        )

    if _G.AimbotMode == "FOV Circle" then
        if not onScreen then
            return false
        end

        return (
            Vector2.new(
                screenPos.X,
                screenPos.Y
            ) - center
        ).Magnitude <= CTX.fovRadius

    elseif _G.AimbotMode == "Champ de Vision" then
        return onScreen

    end

    return true
end
 
local function aimAtTarget(entity)
    if not Camera
        or not entity
    then
        return
    end

    if not isDuelTargetActive(entity) then
        resetAimPart(entity)
        return
    end

    local character =
        getEntityCharacter(entity)

    if not character then
        resetAimPart(entity)
        return
    end

    local aimPart =
        getAimPart(entity)

    if not aimPart
        or not aimPart:IsDescendantOf(character)
    then
        resetAimPart(entity)
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

CTX.currentAngle = 0

trackConnection(RunService.RenderStepped:Connect(function() 
    Camera = workspace.CurrentCamera or Camera 
    local center = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2) 
    if CTX.fovCircle then 
        CTX.fovCircle.Position = center 
        CTX.fovCircle.Color = _G.FOVColor or CTX.fovCircle.Color 
    end 
    local char = LocalPlayer.Character 
    local hrp = char and char:FindFirstChild("HumanoidRootPart") 
    local hum = char and char:FindFirstChildOfClass("Humanoid") 
    if _G.SpinBotEnabled and hrp and hum and hum.Health > 0 then 
        CTX.currentAngle = (CTX.currentAngle + _G.SpinSpeed) % 360 
        local radAngle = math.rad(CTX.currentAngle) 
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
    -- ==========================================================
    -- PRIORITÉ CAMÉRA : AIMBOT NATIF > AUTO-PLAY IA
    -- ==========================================================

    if CTX.aimbotActive then

        -- Une cible native morte/invalide est immédiatement retirée.
        if CTX.trackedTarget
            and not isDuelTargetActive(CTX.trackedTarget)
        then
            resetAimPart(CTX.trackedTarget)
            CTX.trackedTarget = nil
            CTX.currentTarget = nil
        end

        -- Réévaluation native.
        if tick() - CTX.lastTargetTime
            >= CTX.AimbotPriorityConfig.RecheckInterval
        then
            local newTarget = searchBestTarget()

            if newTarget ~= CTX.trackedTarget then
                resetAimPart(CTX.trackedTarget)
                resetAimPart(newTarget)

                CTX.trackedTarget = newTarget
                CTX.currentTarget = newTarget
            end

            CTX.lastTargetTime = tick()
        end

        -- Si le lock natif existe, il possède EXCLUSIVEMENT la caméra.
        if CTX.trackedTarget
            and isDuelTargetActive(CTX.trackedTarget)
            and canAimAtEntity(CTX.trackedTarget)
        then
            aimAtTarget(CTX.trackedTarget)
        end

        -- Auto Shoot reste indépendant, mais uniquement sur
        -- une cible native réellement visible.
        if CTX.AutoShootEnabled
            and CTX.trackedTarget
            and isDuelTargetActive(CTX.trackedTarget)
            and canAimAtEntity(CTX.trackedTarget)
            and isEntityActuallyVisible(CTX.trackedTarget)
        then
            local now = os.clock()

            if now - CTX.AutoShootLastM2
                >= CTX.CombatConfig.AttackCooldownM2
            then
                CTX.AutoShootLastM2 = now
                fireM2()
            end
        end

        updateFOVCircleVisibility()

    else
        CTX.trackedTarget = nil
        CTX.currentTarget = nil
        updateFOVCircleVisibility()
    end
end))





-- Standalone fire primitive for Combat-only build.
fireM2 = function()
    local pos = UserInputService:GetMouseLocation()

    -- Clic droit pour le lancer à distance dans le jeu de duel ciblé.
    local button = 1

    VirtualInputManager:SendMouseButtonEvent(
        pos.X,
        pos.Y,
        button,
        true,
        game,
        0
    )

    task.delay(0.08, function()
        local currentPos =
            UserInputService:GetMouseLocation()

        VirtualInputManager:SendMouseButtonEvent(
            currentPos.X,
            currentPos.Y,
            button,
            false,
            game,
            0
        )
    end)
end

-- AUTO-PLAY CONFIG & UI
------------------------------------------------------------
CTX.AutoPlayTab = CTX.Window:MakeTab({ Name = "Auto-Play", Icon = "rbxassetid://4483345998", PremiumOnly = false })
CTX.AiSection = CTX.AutoPlayTab:AddSection({ Name = "IA" })
CTX.CombatSection = CTX.AutoPlayTab:AddSection({ Name = "Combat Couteaux" })
CTX.MoveSection = CTX.AutoPlayTab:AddSection({ Name = "Déplacement" })
CTX.CopySection = CTX.AutoPlayTab:AddSection({ Name = "Mode Copy" })
CTX.RecordSection = CTX.AutoPlayTab:AddSection({ Name = "Enregistreur" })
CTX.DebugSection = CTX.AutoPlayTab:AddSection({ Name = "Debug" })
CTX.emergencyStop = nil

CTX.AutoPlayConfig = {
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
    LowHealthThreshold = 30,

    WalkSpeed = 24,
    DetectionRange = 200,
    TargetRecheckInterval = 0.01,

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

    -- Slide spécial pendant le strafe IA :
    -- 0.7 s maintenu, puis nouvelle impulsion au plus tôt 2 s après.
    StrafeSlideEnabled = true,
    StrafeSlideHoldDuration = 0.7,
    StrafeSlideInterval = 2.0,

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
CTX.storedLogText = ""
CTX.PlaybackEvents = {}
CTX.playbackActive = false
CTX.playbackStartTime = 0
CTX.playbackIndex = 1
CTX.recording = false
CTX.recordStartTime = 0
CTX.recordEvents = {}
CTX.lastCamRecordTime = 0
CTX.copyCameraTarget = nil
CTX.shiftHeldByScript = false
CTX.slideActive, CTX.slideEndTime = false, 0


local function getEffectiveIAStyle()
    if CTX.AutoPlayConfig.IAStyle ~= "AUTO" then
        return CTX.AutoPlayConfig.IAStyle
    end

    local deaths = CTX.AutoPlayConfig.AutoDeaths or 0

    -- Après 3 morts :
    -- on passe temporairement en Lointain.
    if deaths >= 3 then
        return "Lointain"
    end

    -- Sinon on garde le style de départ.
    return CTX.AutoPlayConfig.AutoBaseStyle
        or "Aggressive"
end

registerAIDeath = function()
    CTX.AutoPlayConfig.AutoDeaths =
        CTX.AutoPlayConfig.AutoDeaths + 1

    if CTX.AutoPlayConfig.IAStyle == "AUTO" then
        local effective = getEffectiveIAStyle()

        pushLog(
            "IA",
            "AUTO → stratégie actuelle : " .. effective
        )
    end

    local deaths =
        CTX.AutoPlayConfig.AutoDeaths

    pushLog(
        "IA",
        "Mort détectée #" .. deaths
    )

    -- 3e mort : Lointain
    if CTX.AutoPlayConfig.IAStyle == "AUTO"
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
            "local_death",
            "Joueur local | Mort #" .. deaths,
            LocalPlayer.Name
        )
    end)
end
CTX.MOVEMENT_KEYS = { W = true, A = true, S = true, D = true, Z = true }

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
            if type(normalized) == "string" and CTX.MOVEMENT_KEYS[normalized] then
                held[normalized] = true
            end

            table.insert(repaired, {
                time = ev.time,
                type = "KEY_DOWN",
                data = normalized,
            })

        elseif ev.type == "KEY_UP" then
            if type(normalized) == "string" and CTX.MOVEMENT_KEYS[normalized] then
                if not held[normalized] then
                    table.insert(repaired, {
                        time = math.max(0, ev.time - CTX.AutoPlayConfig.CopyKeyUpSimulate),
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
    CTX.storedLogText = raw or ""
    local events, stats = parseLogText(CTX.storedLogText)
    CTX.PlaybackEvents = events
    local msg = string.format("%d evt (%d keys, %d cam, %d unk, +%d réparés)",
        stats.total, stats.keys, stats.camera, stats.unknown, stats.repaired)
    pushLog(sourceTag or "COPY", msg)
    sendNotification("Copy", msg)
    return stats
end

--========================================================--
-- DÉTECTION DES ÉQUIPES DU DUEL
--========================================================--
CTX.MATCH_TEAM_SIZE = {
    ["1v1"] = 1,
    ["2v2"] = 2,
    ["3v3"] = 3,
    ["4v4"] = 4,
}

local function getExpectedTeamCounts(roster)
    local totalEntities = #roster

    local configuredTeamSize =
        CTX.MATCH_TEAM_SIZE[_G.GameModeSetup]

    if configuredTeamSize
        and totalEntities >= configuredTeamSize * 2
    then
        return math.max(0, configuredTeamSize - 1), configuredTeamSize

    end

    if totalEntities >= 2
        and totalEntities % 2 == 0
    then
        local teamSize =
            totalEntities / 2

            return math.max(0, teamSize - 1), teamSize
    end

    if configuredTeamSize then
        local opponents =
            math.max(0, totalEntities - 1)

        local allies =
            math.min(
                math.max(0, configuredTeamSize - 1),
                opponents
            )

        return allies, opponents - allies
    end

    return 0, math.max(0, totalEntities - 1)
end

local function lockRoundTeams(roster)
    roster = roster or collectAllCombatEntities()

    local expectedAllies =
        CTX.TeamScanState.ExpectedAllies

    local expectedEnemies =
        CTX.TeamScanState.ExpectedEnemies

    if #roster < expectedAllies + expectedEnemies then
        return false
    end

    local allyCount = 0
    local enemyCount = 0

    for _, entity in ipairs(roster) do
        if CTX.whitelistedAllies[entity] then
            allyCount += 1
        elseif CTX.detectedRoundEnemies[entity] then
            enemyCount += 1
        end
    end

    if allyCount < expectedAllies then
        return false
    end

    -- Dès que les alliés attendus sont connus,
    -- tous les autres membres du roster deviennent ennemis.
    for _, entity in ipairs(roster) do
        if not CTX.whitelistedAllies[entity] then
            CTX.detectedRoundEnemies[entity] = true
        end
    end

    enemyCount = 0
    for _, entity in ipairs(roster) do
        if CTX.detectedRoundEnemies[entity] then
            enemyCount += 1
        end
    end

    if enemyCount < expectedEnemies then
        return false
    end

    CTX.TeamScanState.Locked = true
    CTX.TeamScanState.Scanning = false

    CTX.RoundEntities = {}
    for _, entity in ipairs(roster) do
        CTX.RoundEntities[entity] = true
    end

    CTX.Skin.EnabledModel = false
    actualiserViewmodel()

    pushLog(
        "MATCH",
        string.format(
            "Équipes verrouillées | alliés=%d ennemis=%d | roster=%d",
            allyCount,
            enemyCount,
            #roster
        )
    )

    pcall(function()
        OrionLib:SendTelemetryEvent(
            "team_scan_locked",
            string.format(
                "Alliés %d | Ennemis %d",
                allyCount,
                enemyCount
            ),
            tostring(_G.GameModeSetup)
        )
    end)

    return true
end

local function scanGameTeams()
    if CTX.MatchState.Ended then
        return true
    end

    if CTX.TeamScanState.Locked then
        return true
    end

    refreshBotCharactersIfNeeded(true)

    local roster =
        collectAllCombatEntities()

    local expectedAllies, expectedEnemies =
        getExpectedTeamCounts(roster)

    CTX.TeamScanState.ExpectedAllies =
        expectedAllies

    CTX.TeamScanState.ExpectedEnemies =
        expectedEnemies

    for _, entity in ipairs(roster) do
        if hasGameHighlight(
            entity,
            CTX.GAME_TEAMMATE_HIGHLIGHT
        )
        then
            local wasAlreadyKnown =
                CTX.whitelistedAllies[entity] == true

            CTX.whitelistedAllies[entity] = true
            CTX.detectedRoundEnemies[entity] = nil

            applyAllyHighlight(entity)

            if not wasAlreadyKnown then
                pcall(function()
                    OrionLib:SendTelemetryEvent(
                        "ally_found",
                        string.format(
                            "Allié trouvé | format %s",
                            tostring(_G.GameModeSetup)
                        ),
                        getEntityName(entity)
                    )
                end)
            end

        elseif hasGameHighlight(
            entity,
            CTX.GAME_ENEMY_HIGHLIGHT
        ) then
            if not CTX.whitelistedAllies[entity] then
                CTX.detectedRoundEnemies[entity] = true
                clearAllyHighlight(entity)
            end
        end
    end

    return lockRoundTeams(roster)
end

waitAndScanGameTeams = function()
    if CTX.MatchState.Ended
        or CTX.TeamScanState.Locked
        or CTX.TeamScanState.Scanning
    then
        return false
    end

    CTX.TeamScanState.Scanning = true
    CTX.TeamScanState.StartedAt = os.clock()

    local success = false

    while not CTX.MatchState.Ended
        and not CTX.TeamScanState.Locked
        and os.clock() - CTX.TeamScanState.StartedAt < 3
    do
        if scanGameTeams() then
            success = true
            break
        end

        task.wait(0.1)
    end

    if not CTX.MatchState.Ended
        and not CTX.TeamScanState.Locked
    then
        success = scanGameTeams()
            or lockRoundTeams()
            or success
    end

    CTX.TeamScanState.Scanning = false

    return success
end

CTX.AiSection:AddToggle({
    Name = "Activer Auto-Play",
    Default = false,
    Callback = function(v)
        CTX.AutoPlayConfig.Enabled = v
        if v then CTX.aimbotActive = true if CTX.fovCircle then CTX.fovCircle.Visible = true end end
        pushLog("SYSTEM", v and "Auto-Play ON" or "Auto-Play OFF")
    end,
})

CTX.AiSection:AddDropdown({
    Name = "Type de cibles",
    Default = "Les deux",
    Options = {"Joueurs", "Bots", "Les deux"},
    Callback = function(v)
        CTX.TargetMode = v
        CTX.trackedTarget = nil
        CTX.currentTarget = nil
        CTX.AITarget = nil
        CTX.RoundEntities = {}
        table.clear(CTX.detectedRoundEnemies)
        CTX.TeamScanState.Locked = false
        CTX.TeamScanState.Scanning = false
    end,
})

CTX.AiSection:AddDropdown({
    Name = "Style IA",
    Default = "Lointain",

    Options = {
        "Aggressive",
        "Defensive",
        "Mixed",
        "Lointain",
        "AUTO"
    },

    Callback = function(v)
        CTX.AutoPlayConfig.IAStyle = v

        if v ~= "AUTO" then
            CTX.AutoPlayConfig.AutoBaseStyle = v
        end

        pushLog(
            "IA",
            "Style sélectionné : " .. v
        )
    end,
})
CTX.AiSection:AddToggle({ Name = "Overlay logs", Default = true, Callback = function(v) CTX.AutoPlayConfig.ShowLogs = v setLogVisible(v) end })

CTX.CombatSection:AddToggle({ Name = "M1 = clic gauche (sinon Q)", Default = true, Callback = function(v) CTX.AutoPlayConfig.M1UseMouse = v end })
CTX.CombatSection:AddToggle({ Name = "M2 = clic droit (sinon Q/A)", Default = true, Callback = function(v) CTX.AutoPlayConfig.M2UseMouse = v end })
CTX.CombatSection:AddSlider({ Name = "Portée M1", Min = 3, Max = 15, Default = 8, Increment = 1, Callback = function(v) CTX.AutoPlayConfig.MeleeRange = v end })
CTX.CombatSection:AddSlider({ Name = "Portée lancer", Min = 15, Max = 1000, Default = 1000, Increment = 1, Callback = function(v) CTX.AutoPlayConfig.KnifeRange = v end })
CTX.CombatSection:AddSlider({ Name = "Cooldown M2", Min = 0.1, Max = 1, Default = 0.25, Increment = 0.05, Callback = function(v) CTX.AutoPlayConfig.AttackCooldownM2 = v end })

CTX.MoveSection:AddSlider({ Name = "Vitesse IA", Min = 8, Max = 32, Default = 32, Increment = 1, Callback = function(v) CTX.AutoPlayConfig.WalkSpeed = v end })
CTX.MoveSection:AddSlider({ Name = "Détection ennemi", Min = 20, Max = 1000, Default = 1000, Increment = 5, Callback = function(v) CTX.AutoPlayConfig.DetectionRange = v end })
CTX.MoveSection:AddSlider({ Name = "Distance murs", Min = 3, Max = 15, Default = 10, Increment = 1, Callback = function(v) CTX.AutoPlayConfig.WallRange = v end })
CTX.MoveSection:AddSlider({ Name = "Temps blocage", Min = 0.3, Max = 2, Default = 1.5, Increment = 0.05, Callback = function(v) CTX.AutoPlayConfig.StuckTime = v end })
CTX.MoveSection:AddSlider({ Name = "Durée slide (C maintenu)", Min = 1, Max = 3, Default = 2, Increment = 0.1, Callback = function(v) CTX.AutoPlayConfig.SlideHoldDuration = v end })

CTX.MoveSection:AddToggle({
    Name = "Slide pendant le strafe",
    Default = true,
    Callback = function(v)
        CTX.AutoPlayConfig.StrafeSlideEnabled = v
    end,
})

CTX.MoveSection:AddSlider({
    Name = "Durée slide strafe",
    Min = 0.1,
    Max = 1.5,
    Default = 0.7,
    Increment = 0.1,
    ValueName = "s",
    Callback = function(v)
        CTX.AutoPlayConfig.StrafeSlideHoldDuration = v
    end,
})

CTX.MoveSection:AddSlider({
    Name = "Intervalle slide strafe",
    Min = 1,
    Max = 5,
    Default = 2,
    Increment = 0.1,
    ValueName = "s",
    Callback = function(v)
        CTX.AutoPlayConfig.StrafeSlideInterval = v
    end,
})


CTX.CopySection:AddButton({ Name = "📋 Importer presse-papier", Callback = function()
    local ok, clip = pcall(function() return getclipboard() end)
    if ok and clip and clip ~= "" then loadLogsFromText(clip, "IMPORT") else sendNotification("Copy", "Presse-papier vide.") end
end })

CTX.CopySection:AddButton({ Name = "📄 Parser logs", Callback = function()
    local ok, clip = pcall(function() return getclipboard() end)
    if ok and clip and clip ~= "" then loadLogsFromText(clip, "PARSE")
    elseif CTX.storedLogText ~= "" then loadLogsFromText(CTX.storedLogText, "PARSE")
    else sendNotification("Copy", "Aucun log.") end
end })

CTX.CopySection:AddToggle({ Name = "Boucle Copy", Default = false, Callback = function(v) CTX.AutoPlayConfig.CopyLoop = v end })
CTX.CopySection:AddToggle({ Name = "Caméra relative", Default = false, Callback = function(v) CTX.AutoPlayConfig.CopyRelativeCamera = v end })
CTX.CopySection:AddSlider({ Name = "Lissage cam Copy", Min = 0.05, Max = 0.5, Default = 0.18, Increment = 0.01, Callback = function(v) CTX.AutoPlayConfig.CopyCameraSmooth = v end })

CTX.CopySection:AddButton({ Name = "▶ Lecture (P)", Callback = function()
    if #CTX.PlaybackEvents == 0 then
        sendNotification("Copy", "Aucun événement parsé.")
        return
    end
    CTX.playbackActive = true
    CTX.playbackStartTime = os.clock()
    CTX.playbackIndex = 1
    CTX.copyCameraTarget = nil
    CTX.firstCameraLook = nil
    table.clear(CTX.pendingReleases)
    pushLog("COPY", "Lecture " .. #CTX.PlaybackEvents .. " evt")
end })

CTX.RecordSection:AddButton({ Name = "⏺ REC (L)", Callback = function()
    if not CTX.recording then
        CTX.recording = true
        CTX.recordStartTime = os.clock()
        CTX.recordEvents = {}
        CTX.lastCamRecordTime = 0
        sendNotification("REC", "REC ON (L stop)")
    end
end })

CTX.RecordSection:AddButton({ Name = "⏹ Stop & copier", Callback = function()
    if not CTX.recording then return end
    CTX.recording = false
    CTX.storedLogText = eventsToText(CTX.recordEvents)
    CTX.PlaybackEvents = select(1, parseLogText(CTX.storedLogText))
    pcall(function() setclipboard(CTX.storedLogText) end)
    sendNotification("REC", #CTX.recordEvents .. " events copiés")
end })

CTX.DebugSection:AddButton({
    Name = "⛔ STOP IA / INPUTS",
    Callback = CTX.emergencyStop,
})

CTX.DebugSection:AddParagraph("Info", "L=REC | P=Copy | J=Aimbot | V=Alliés | C=Slide | Shift=Sprint")

OrionLib:MakeNotification({ Name = "rio V7", Content = "Duels de Couteaux — V6 chargée.", Time = 5 })

------------------------------------------------------------
-- INPUT SIMULATION
------------------------------------------------------------
CTX.keysDown = {}
CTX.copyKeysDown = {}
CTX.currentMoveKeys = {}
CTX.pendingReleases = {}
CTX.firstCameraLook = nil
CTX.KEY_ALIASES = {
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
CTX.KEYCODE_MAP = {
    W = Enum.KeyCode.W, A = Enum.KeyCode.A, S = Enum.KeyCode.S, D = Enum.KeyCode.D,
    Space = Enum.KeyCode.Space, LeftShift = Enum.KeyCode.LeftShift,
    C = Enum.KeyCode.C, Q = Enum.KeyCode.Q, E = Enum.KeyCode.E,
}

local function getMousePos() return UserInputService:GetMouseLocation() end

local function resolveInputName(name)
    name = normalizeKeyName(name)
    local resolved = CTX.KEY_ALIASES[name] or name
    if resolved == "MouseLeft" or resolved == "MouseRight" then return "mouse", resolved end
    local kc = CTX.KEYCODE_MAP[resolved]
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
    if kind == "key" then return CTX.keysDown[code] == true end
    if kind == "mouse" then return CTX.copyKeysDown[code] == true end
    return false
end

pressInput = function(name, isCopy)
    name = normalizeKeyName(name)
    local kind, code = resolveInputName(name)
    if not kind then return end
    if kind == "mouse" then
        local pos = getMousePos()
        local btn = (code == "MouseLeft") and 0 or 1
        VirtualInputManager:SendMouseButtonEvent(pos.X, pos.Y, btn, true, game, 0)
        CTX.copyKeysDown[code] = true
    else
        if not CTX.keysDown[code] then
            VirtualInputManager:SendKeyEvent(true, code, false, game)
            CTX.keysDown[code] = true
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
        CTX.copyKeysDown[code] = nil
    else
        if CTX.keysDown[code] then
            VirtualInputManager:SendKeyEvent(false, code, false, game)
            CTX.keysDown[code] = nil
        end
    end
end

scheduleRelease = function(name, delay)
    table.insert(CTX.pendingReleases, { time = os.clock() + delay, name = name })
end

local function releaseShift()
    if CTX.shiftHeldByScript then
        releaseInput("LeftShift")
        CTX.shiftHeldByScript = false
    end
end

local function releaseAllInputs()
    for key in pairs(CTX.keysDown) do
        VirtualInputManager:SendKeyEvent(false, key, false, game)
        CTX.keysDown[key] = nil
    end

    for key in pairs(CTX.currentMoveKeys or {}) do
        CTX.currentMoveKeys[key] = nil
    end

    table.clear(CTX.copyKeysDown)
    table.clear(CTX.pendingReleases)

    if CTX.currentMoveKeys then table.clear(CTX.currentMoveKeys) end

    local pos = getMousePos()
    VirtualInputManager:SendMouseButtonEvent(pos.X, pos.Y, 0, false, game, 0)
    VirtualInputManager:SendMouseButtonEvent(pos.X, pos.Y, 1, false, game, 0)

    CTX.slideActive = false
    CTX.shiftHeldByScript = false
    CTX.AIState.ShiftApplied = false
end

local function ensureShiftHeld(force)
    --[[
    if force then
        if CTX.keysDown[Enum.KeyCode.LeftShift] then
            VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.LeftShift, false, game)
            CTX.keysDown[Enum.KeyCode.LeftShift] = nil
        end
        CTX.shiftHeldByScript = false
    end

    if not CTX.keysDown[Enum.KeyCode.LeftShift] then
        VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.LeftShift, false, game)
        CTX.keysDown[Enum.KeyCode.LeftShift] = true
        CTX.shiftHeldByScript = true
        CTX.AIState.ShiftApplied = true
    end
    ]]--
end

local function fireM1()
    if CTX.AutoPlayConfig.M1UseMouse then
        pressInput("MouseLeft")
        scheduleRelease("MouseLeft", 0.05)
    else
        pressInput("Q")
        scheduleRelease("Q", 0.05)
    end
end

fireM2 = function()
    -- Dans le jeu de duels, le lancer à distance utilise le clic droit.
    if CTX.USE_GAME_HP then
        if CTX.AutoPlayConfig.M2UseMouse then
            pressInput("MouseRight")
            scheduleRelease("MouseRight", 0.08)
        else
            pressInput("Q")
            scheduleRelease("Q", 0.08)
        end
        return
    end

    -- Dans les autres jeux : tir au clic gauche, sans touche A.
    pressInput("MouseLeft")
    scheduleRelease("MouseLeft", 0.05)
end

------------------------------------------------------------
-- ENREGISTREUR
------------------------------------------------------------
local function recordEvent(type_, data)
    table.insert(CTX.recordEvents, { time = os.clock() - CTX.recordStartTime, type = type_, data = data })
end

local function captureBegan(input)
    if not CTX.recording then return end
    if input.UserInputType == Enum.UserInputType.MouseButton1 then recordEvent("KEY_DOWN", "MouseLeft")
    elseif input.UserInputType == Enum.UserInputType.MouseButton2 then recordEvent("KEY_DOWN", "MouseRight")
    elseif input.KeyCode ~= Enum.KeyCode.Unknown then recordEvent("KEY_DOWN", input.KeyCode.Name)
    else recordEvent("KEY_DOWN", "Unknown") end
end

local function captureEnded(input)
    if not CTX.recording then return end
    if input.UserInputType == Enum.UserInputType.MouseButton1 then recordEvent("KEY_UP", "MouseLeft")
    elseif input.UserInputType == Enum.UserInputType.MouseButton2 then recordEvent("KEY_UP", "MouseRight")
    elseif input.KeyCode ~= Enum.KeyCode.Unknown then recordEvent("KEY_UP", input.KeyCode.Name)
    else recordEvent("KEY_UP", "Unknown") end
end

UserInputService.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    if input.KeyCode == Enum.KeyCode.L then
        CTX.recording = not CTX.recording
        if CTX.recording then
            CTX.recordStartTime = os.clock()
            CTX.recordEvents = {}
            CTX.lastCamRecordTime = 0
            pushLog("REC", "REC ON")
        else
            CTX.storedLogText = eventsToText(CTX.recordEvents)
            CTX.PlaybackEvents = select(1, parseLogText(CTX.storedLogText))
            pcall(function() setclipboard(CTX.storedLogText) end)
            pushLog("REC", #CTX.recordEvents .. " copiés")
        end
        return
    end
    if input.KeyCode == Enum.KeyCode.P then
        if #CTX.PlaybackEvents == 0 then sendNotification("Copy", "Parser d'abord.") return end
        CTX.playbackActive = not CTX.playbackActive
        if CTX.playbackActive then
            CTX.playbackStartTime = os.clock()
            CTX.playbackIndex = 1
            CTX.copyCameraTarget = nil
            CTX.firstCameraLook = nil
            table.clear(CTX.pendingReleases)
            if CTX.AutoPlayConfig.Mode == "IA" then CTX.AutoPlayConfig.Mode = "Copy" end
            pushLog("COPY", "Lecture ON")
        else releaseAllInputs() pushLog("COPY", "Lecture OFF") end
        return
    end
    captureBegan(input)
end)

UserInputService.InputEnded:Connect(captureEnded)

RunService.RenderStepped:Connect(function()
    if CTX.recording then
        local now = os.clock()
        if now - CTX.lastCamRecordTime >= 0.1 then
            CTX.lastCamRecordTime = now
            local cf = Camera.CFrame
            recordEvent("CAMERA", { cf.Position, cf.LookVector })
        end
    end
    if CTX.copyCameraTarget and CTX.playbackActive then
        Camera.CFrame = Camera.CFrame:Lerp(CTX.copyCameraTarget, CTX.AutoPlayConfig.CopyCameraSmooth)
    end
end)

-- Shift au spawn / nouveau round
local function onCharacterSpawn(char)
    task.defer(function()
        task.wait(0.5)

        if CTX.MatchState.Ended then
            clearMatchProtection()
        end

        local hum = char:FindFirstChildOfClass("Humanoid")

        if CTX.USE_GAME_HP then
            local deathRegistered = false
            local previousHP = char:GetAttribute("HP")

            char:GetAttributeChangedSignal("HP"):Connect(function()
                if deathRegistered then
                    return
                end

                local newHP = char:GetAttribute("HP")

                if previousHP ~= nil
                    and previousHP > 0
                    and newHP ~= nil
                    and newHP <= 0
                then
                    deathRegistered = true
                    registerAIDeath()
                end

                previousHP = newHP
            end)
        elseif hum then
            hum.Died:Connect(function()
                registerAIDeath()
            end)
        end

        task.spawn(waitAndScanGameTeams)
        ensureShiftHeld(true)
        pushLog("SYSTEM", "Shift maintenu (nouveau round)")
    end)
end

if LocalPlayer.Character then
    onCharacterSpawn(LocalPlayer.Character)
end

LocalPlayer.CharacterAdded:Connect(onCharacterSpawn)

LocalPlayer.CharacterRemoving:Connect(function()
    if stopMovement then
        stopMovement()
    end

    releaseAllInputs()
    CTX.AITarget = nil
    CTX.trackedTarget = nil
    CTX.currentTarget = nil
    CTX.AIState.LastPosition = nil
    CTX.AIState.StuckSince = nil
end)

------------------------------------------------------------
-- OUTILS IA
------------------------------------------------------------
local function getCharacter()
    local char = LocalPlayer.Character
    if not char then return nil end

    local hrp = char:FindFirstChild("HumanoidRootPart")
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hrp or not hum then return nil end

    if CTX.USE_GAME_HP then
        local hp = char:GetAttribute("HP")
        if hp ~= nil and hp > 0 then
            return char, hrp, hum
        end
        return nil
    end

    if hum.Health > 0 then
        return char, hrp, hum
    end
end

--========================================================--
-- AUTO PLAY : SELECTEUR DE CIBLE
--========================================================--

local function acquireAITarget(fromPosition)
    local allCandidates = {}
    local visibleCandidates = {}

    local source = {}

    if CTX.TeamScanState.Locked then
        for entity in pairs(CTX.detectedRoundEnemies) do
            table.insert(source, entity)
        end
    else
        source = collectTargetEntities()
    end

    for _, entity in ipairs(source) do
        if isEnemyValidForTracking(entity) then
            local char = getEntityCharacter(entity)
            local hrp = char and char:FindFirstChild("HumanoidRootPart")

            if hrp then
                local distance =
                    (hrp.Position - fromPosition).Magnitude

                if distance <= CTX.AutoPlayConfig.DetectionRange then
                    local actuallyVisible =
                        isEntityActuallyVisible(entity)

                    local dangerous =
                        isEntityDangerous(entity)

                    local candidate = {
                        Entity = entity,
                        Distance = distance,
                        Visible = actuallyVisible,
                        Dangerous = dangerous,
                    }

                    table.insert(
                        allCandidates,
                        candidate
                    )

                    if actuallyVisible then
                        table.insert(
                            visibleCandidates,
                            candidate
                        )
                    end
                end
            end
        end
    end

    -- Une ou plusieurs cibles réellement visibles :
    -- Visible > Dangerous > Distance.
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
                and candidate.Distance
                    < best.Distance
            then
                best = candidate
            end
        end

        return best.Entity
    end

    -- Personne visible :
    -- l'IA continue à chasser le plus proche.
    if #allCandidates > 0 then
        local closest = allCandidates[1]

        for i = 2, #allCandidates do
            local candidate = allCandidates[i]

            if candidate.Distance < closest.Distance then
                closest = candidate
            end
        end

        return closest.Entity
    end

    return nil
end

local function updateAITarget(hrp)
    local now = os.clock()

    -- La cible actuelle est immédiatement invalidée si elle meurt.
    if CTX.AITarget
        and not isDuelTargetActive(CTX.AITarget)
    then
        resetAimPart(CTX.AITarget)
        CTX.AITarget = nil
        CTX.AITargetLastVisible = false
    end

    -- Pas encore le moment du prochain scan.
    if now - CTX.AILastAcquire
        < CTX.AutoPlayConfig.TargetRecheckInterval
    then
        return CTX.AITarget
    end

    CTX.AILastAcquire = now

    local newTarget = acquireAITarget(hrp.Position)

    if newTarget ~= CTX.AITarget then
        resetAimPart(CTX.AITarget)
        resetAimPart(newTarget)

        CTX.AITarget = newTarget
        CTX.AITargetSince = newTarget and now or 0
        CTX.AITargetLastVisible =
            newTarget
            and isEntityActuallyVisible(newTarget)
            or false
    end

    return CTX.AITarget
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
            local blocked = castWall(hrp.Position, direction, CTX.AutoPlayConfig.WallRange + 3)
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
    for i = 1, CTX.AutoPlayConfig.CoverSamples do
        local angle = (i / CTX.AutoPlayConfig.CoverSamples) * math.pi * 2
        local offset = Vector3.new(math.cos(angle), 0, math.sin(angle)) * CTX.AutoPlayConfig.CoverSearchRadius
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
CTX.lastPathTime, CTX.lastState = 0, ""

logStateOnce = function(state, extra)
    local msg = extra and (state .. " | " .. extra) or state
    if CTX.lastState ~= msg then CTX.lastState = msg pushLog("IA", msg) end
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
        CTX.AIState.StuckMemory[zoneKey]

    if not zone then
        zone = {}
        CTX.AIState.StuckMemory[zoneKey] = zone
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
    local zone = CTX.AIState.StuckMemory[zoneKey]
    if not zone then return nil end

    local bestChoice = nil
    local bestScore = -math.huge

    for choice, data in pairs(zone) do
        local score = data.Success * 3 - data.Fail
        if score > bestScore then
            bestScore = score
            bestChoice = choice
        end
    end

    return bestChoice
end

local function getFrontObstacleInfo(hrp, preferredDirection)
    local direction = preferredDirection
    if not direction or direction.Magnitude <= 0.01 then
        direction = hrp.CFrame.LookVector
    end

    direction = Vector3.new(direction.X, 0, direction.Z)
    if direction.Magnitude <= 0.01 then
        return nil, nil
    end
    direction = direction.Unit

    local params = makeRayParams({ LocalPlayer.Character })
    local result = Workspace:Raycast(
        hrp.Position + Vector3.new(0, 1.5, 0),
        direction * (CTX.AutoPlayConfig.WallRange + 3),
        params
    )

    if not result or not result.Instance
        or not result.Instance:IsA("BasePart")
        or not result.Instance.CanCollide
    then
        return nil, nil
    end

    return result.Instance, result.Instance.Size.Y
end

local function getCharacterHeight()
    local char = LocalPlayer.Character
    if not char then return 5 end

    local ok, size = pcall(function()
        return char:GetExtentsSize()
    end)

    if ok and size and size.Y > 0 then
        return size.Y
    end

    return 5
end

local function canUseJumpRecovery(hrp, preferredDirection)
    local _, obstacleHeight = getFrontObstacleInfo(hrp, preferredDirection)
    if not obstacleHeight then
        return true
    end

    return obstacleHeight <= getCharacterHeight() * 1.25
end

local function getRecoveryActionDirection(hrp, targetHRP, zoneKey)
    local known = getBestKnownStuckChoice(zoneKey)

    local away = hrp.Position - targetHRP.Position
    if away.Magnitude <= 0.01 then
        away = -hrp.CFrame.LookVector
    else
        away = away.Unit
    end

    local function exploreNext()
        CTX.AIState.StuckStage = (CTX.AIState.StuckStage % 4) + 1

        if CTX.AIState.StuckStage == 1 then
            return "Recul", away, false
        elseif CTX.AIState.StuckStage == 2 then
            return "Droite", hrp.CFrame.RightVector, false
        elseif CTX.AIState.StuckStage == 3 then
            return "Gauche", -hrp.CFrame.RightVector, false
        end

        if canUseJumpRecovery(hrp, hrp.CFrame.LookVector) then
            return "Saut", hrp.CFrame.LookVector, true
        end

        return "Recul", away, false
    end

    if known == "Recul" then
        return "Recul", away, false
    elseif known == "Droite" then
        return "Droite", hrp.CFrame.RightVector, false
    elseif known == "Gauche" then
        return "Gauche", -hrp.CFrame.RightVector, false
    elseif known == "Saut" and canUseJumpRecovery(hrp, hrp.CFrame.LookVector) then
        return "Saut", hrp.CFrame.LookVector, true
    end

    return exploreNext()
end


local function updateStuckState(hrp)
    local now = os.clock()

    if now < CTX.AIState.StuckCooldownUntil then
        return false
    end

    if not CTX.AIState.LastPosition then
        CTX.AIState.LastPosition = hrp.Position
        CTX.AIState.LastPositionTime = now
        return false
    end

    if now - CTX.AIState.LastPositionTime < 0.20 then
        return false
    end

    local moved = (hrp.Position - CTX.AIState.LastPosition).Magnitude
    CTX.AIState.LastPosition = hrp.Position
    CTX.AIState.LastPositionTime = now

    if moved >= 3 then
        if CTX.AIState.CurrentStuckKey and CTX.AIState.CurrentStuckAttempt then
            rememberStuckResult(
                CTX.AIState.CurrentStuckKey,
                CTX.AIState.CurrentStuckAttempt,
                true
            )
        end

        CTX.AIState.CurrentStuckKey = nil
        CTX.AIState.CurrentStuckAttempt = nil
        CTX.AIState.RecoveryStartPosition = nil
        CTX.AIState.StuckSince = nil
        CTX.AIState.StuckStage = 0

        if CTX.AIState.TemporaryRecoveryStyle then
            pushLog(
                "IA",
                "STUCK RÉSOLU → retour à "
                    .. tostring(
                        CTX.AIState.RecoveryOriginalStyle
                    )
            )

            CTX.AIState.TemporaryRecoveryStyle = nil
            CTX.AIState.RecoveryOriginalStyle = nil
            CTX.AIState.RecoveryStartedAt = 0
        end
        return false
    end

    if not CTX.AIState.StuckSince then
        CTX.AIState.StuckSince = now
        return false
    end

    return now - CTX.AIState.StuckSince >= CTX.AutoPlayConfig.StuckTime
end

local function startStuckFallback()
    if CTX.AIState.TemporaryRecoveryStyle then
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

    CTX.AIState.RecoveryOriginalStyle =
        original

    CTX.AIState.TemporaryRecoveryStyle =
        temporary

    CTX.AIState.RecoveryStartedAt =
        os.clock()

    pushLog(
        "IA",
        "STUCK LONG → "
            .. temporary
            .. " temporaire."
    )
end

local function getMovementIAStyle()
    if CTX.AIState.TemporaryRecoveryStyle then
        return CTX.AIState.TemporaryRecoveryStyle
    end

    return getEffectiveIAStyle()
end

local function getStrafeDirection(hrp)
    local now = os.clock()

    if now >= CTX.AIState.NextStrafeSwitch then
        CTX.AIState.StrafeSide = -CTX.AIState.StrafeSide
        CTX.AIState.NextStrafeSwitch = now + math.random(70, 130) / 100
    end

    return hrp.CFrame.RightVector * CTX.AIState.StrafeSide
end

local function canFireM1(now)
    return now - CTX.AIState.LastM1 >= CTX.AutoPlayConfig.AttackCooldownM1
end

local function canFireM2(now)
    return now - CTX.AIState.LastM2 >= CTX.AutoPlayConfig.AttackCooldownM2
end

local function updateStrafeSlide(state, targetVisible, now)
    if not CTX.AutoPlayConfig.StrafeSlideEnabled then
        return
    end

    local isStrafeState =
        state == "Strafe"
        or state == "Lointain-Strafe"

    -- Dès que la cible n'est plus réellement visible ou qu'on ne strafe plus,
    -- on relâche immédiatement le slide spécial.
    if not targetVisible or not isStrafeState then
        if CTX.StrafeSlideActive then
            CTX.StrafeSlideActive = false
            CTX.StrafeSlideEndTime = 0
            releaseInput("C")
        end
        return
    end

    -- Fin d'une impulsion de 0.7 s.
    if CTX.StrafeSlideActive
        and now >= CTX.StrafeSlideEndTime
    then
        CTX.StrafeSlideActive = false
        releaseInput("C")
    end

    -- Nouvelle impulsion au maximum toutes les 2 s.
    if not CTX.StrafeSlideActive
        and now - (CTX.LastStrafeSlide or -math.huge)
            >= CTX.AutoPlayConfig.StrafeSlideInterval
    then
        CTX.LastStrafeSlide = now
        CTX.StrafeSlideActive = true
        CTX.StrafeSlideEndTime =
            now + CTX.AutoPlayConfig.StrafeSlideHoldDuration

        pressInput("C")
    end
end

local function buildDesiredDirection(style, hrp, hum, targetHRP, targetChar, dist)
    local toTarget = targetHRP.Position - hrp.Position
    local awayFromTarget = hrp.Position - targetHRP.Position
    local desired = Vector3.zero
    local state = "Idle"
    local canSee = hasLineOfSight(hrp.Position + Vector3.new(0, 2, 0), targetChar, targetHRP)

    if style == "Lointain" then
        ensureShiftHeld()

        if dist < CTX.AutoPlayConfig.LointainMinDist and awayFromTarget.Magnitude > 0.01 then
            desired = awayFromTarget.Unit
            state = "Lointain-Recul"
        elseif dist <= CTX.AutoPlayConfig.LointainMaxDist then
            if canSee and CTX.AutoPlayConfig.StrafeEnabled then
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
        local localHP = getDuelHP(LocalPlayer)
        local healthValue = localHP ~= nil and localHP or hum.Health

        if healthValue <= CTX.AutoPlayConfig.LowHealthThreshold then
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

        if CTX.AutoPlayConfig.StrafeEnabled and canSee and dist <= CTX.AutoPlayConfig.MeleeRange + 6 then
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
    local wallFront = castWall(hrp.Position, forward, CTX.AutoPlayConfig.WallRange)
    local corrected = desiredDirection
    if wallFront or castWall(hrp.Position, forward - right, CTX.AutoPlayConfig.WallRange) or castWall(hrp.Position, forward + right, CTX.AutoPlayConfig.WallRange) then
        corrected = findBestOpenDirection(hrp, desiredDirection)
    end
    local shouldJump = wallFront
    return corrected, shouldJump
end

local function setMoveKey(name, enabled)
    if enabled then
        if not CTX.currentMoveKeys[name] then
            pressInput(name)
            CTX.currentMoveKeys[name] = true
        end
    elseif CTX.currentMoveKeys[name] then
        releaseInput(name)
        CTX.currentMoveKeys[name] = nil
    end
end

stopMovement = function()
    for key in pairs(CTX.currentMoveKeys) do
        releaseInput(key)
        CTX.currentMoveKeys[key] = nil
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

    CTX.AIState.LastDirection = flatDirection
    CTX.AIState.LastMoveCommand = os.clock()
end

CTX.emergencyStop = function()
    CTX.AutoPlayConfig.Enabled = false
    CTX.playbackActive = false

    stopMovement()
    releaseAllInputs()

    CTX.AITarget = nil
    CTX.trackedTarget = nil
    CTX.currentTarget = nil
    CTX.copyCameraTarget = nil
    CTX.firstCameraLook = nil

    CTX.slideActive = false
    CTX.shiftHeldByScript = false

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

    if CTX.AutoPlayConfig.CopyRelativeCamera then
        if not CTX.firstCameraLook then
            CTX.firstCameraLook = look.Unit
            return
        end

        local baseRotation = CFrame.lookAt(Vector3.zero, CTX.firstCameraLook)
        local currentRotation = CFrame.lookAt(Vector3.zero, look.Unit)
        local deltaRotation = baseRotation:ToObjectSpace(currentRotation)

        CTX.copyCameraTarget = CFrame.new(Camera.CFrame.Position) * Camera.CFrame.Rotation * deltaRotation
    else
        local pos = ev.data[1]
        CTX.copyCameraTarget = CFrame.new(pos, pos + look)
    end
end

local function runCopyPlayback(skipCamera)
    if not CTX.playbackActive or #CTX.PlaybackEvents == 0 then return end
    local elapsed = os.clock() - CTX.playbackStartTime
    while CTX.playbackIndex <= #CTX.PlaybackEvents and CTX.PlaybackEvents[CTX.playbackIndex].time <= elapsed do
        processPlaybackEvent(CTX.PlaybackEvents[CTX.playbackIndex], skipCamera)
        CTX.playbackIndex = CTX.playbackIndex + 1
    end
    if CTX.playbackIndex > #CTX.PlaybackEvents then
        if CTX.AutoPlayConfig.CopyLoop then
            CTX.playbackStartTime = os.clock()
            CTX.playbackIndex = 1
            CTX.copyCameraTarget = nil
            CTX.firstCameraLook = nil
        else
            CTX.playbackActive = false
            releaseAllInputs()
            CTX.copyCameraTarget = nil
            pushLog("COPY", "Fin lecture")
        end
    end
end

local function startSlide(now)
    if CTX.slideActive then return false end
    if now - CTX.AIState.LastSlide < CTX.AutoPlayConfig.SlideCooldown then return false end

    CTX.AIState.LastSlide = now
    CTX.slideActive = true
    CTX.slideEndTime = now + CTX.AutoPlayConfig.SlideHoldDuration
    pressInput("C")
    return true
end

--========================================================--
-- AUTO STRATEGY
--========================================================--

-- ==========================================================
-- GESTION ANTI-STUCK
-- ==========================================================
local function handleStuck(hrp, targetHRP, now, targetPlayer)
    if not updateStuckState(hrp) then
        return nil, nil, nil
    end

    local stuckDuration = CTX.AIState.StuckSince and (os.clock() - CTX.AIState.StuckSince) or 0
    if stuckDuration >= CTX.AutoPlayConfig.StuckModeSwitchTime then
        startStuckFallback()
    end

    local zoneKey = getStuckZoneKey(hrp.Position)
    if CTX.AIState.CurrentStuckKey and CTX.AIState.CurrentStuckAttempt then
        rememberStuckResult(CTX.AIState.CurrentStuckKey, CTX.AIState.CurrentStuckAttempt, false)
    end

    local actionName, recovery, recoveryJump = getRecoveryActionDirection(hrp, targetHRP, zoneKey)
    CTX.AIState.CurrentStuckKey = zoneKey
    CTX.AIState.CurrentStuckAttempt = actionName
    CTX.AIState.RecoveryStartPosition = hrp.Position

    CTX.AIState.StuckCooldownUntil = now + CTX.AutoPlayConfig.StuckRecoveryDuration

    logStateOnce("Stuck", "zone=" .. zoneKey .. " | choix=" .. actionName .. (recoveryJump and " | jump" or ""))

    pcall(function()
        OrionLib:SendTelemetryEvent("ai_stuck", "Recovery | " .. tostring(CTX.AIState.TemporaryRecoveryStyle or getMovementIAStyle()), targetPlayer and getEntityName(targetPlayer) or "None")
    end)

    return recovery, recoveryJump, true
end

-- ==========================================================
-- PATHFINDING
-- ==========================================================
local function computePathIfNeeded(hrp, targetHRP, now)
    if (hrp.Position - targetHRP.Position).Magnitude < 0.08 then
        return nil
    end

    if now - CTX.lastPathTime < CTX.AutoPlayConfig.PathRecomputeDelay then
        return nil
    end

    CTX.lastPathTime = now
    local waypoint = computePathDirection(hrp.Position, targetHRP.Position)
    if not waypoint then
        return nil
    end

    local dir = waypoint.Position - hrp.Position
    if dir.Magnitude <= 0.01 then
        return nil
    end

    local result = {
        direction = dir.Unit,
        jump = (waypoint.Action == Enum.PathWaypointAction.Jump)
    }
    return result
end

-- ==========================================================
-- MOUVEMENT + SAUT
-- ==========================================================
local function executeMovement(corrected, shouldJump, now)
    applyMovementKeys(corrected)

    if corrected.Magnitude > 0.15 then
        startSlide(now)
    end

    if shouldJump and now - CTX.AIState.LastJump >= CTX.AutoPlayConfig.JumpCooldown then
        CTX.AIState.LastJump = now
        pressInput("Space")
        scheduleRelease("Space", 0.06)
    end
end

local function processStuckAndMovement(hrp, targetHRP, desired, now, targetPlayer)
    local corrected, shouldJump = applyObstacleAvoidance(hrp, desired)

    -- Gestion du stuck
    local recovery, recoveryJump, isStuck = handleStuck(hrp, targetHRP, now, targetPlayer)
    if isStuck then
        corrected = findBestOpenDirection(hrp, recovery)
        shouldJump = recoveryJump
    end

    -- Pathfinding si on ne bouge presque pas
    if corrected.Magnitude < 0.08 then
        local path = computePathIfNeeded(hrp, targetHRP, now)
        if path then
            corrected = path.direction
            shouldJump = path.jump
        end
    end

    -- Application du mouvement
    executeMovement(corrected, shouldJump, now)
end

local function getKnownEnemyCount()
    local count = 0

    for entity in pairs(CTX.detectedRoundEnemies) do
        if entity then
            count += 1
        end
    end

    return count
end

local function areAllKnownEnemiesDefeated()
    if not CTX.TeamScanState.Locked then
        return false
    end

    if getKnownEnemyCount() <= 0 then
        return false
    end

    for entity in pairs(CTX.detectedRoundEnemies) do
        if isEntityAlive(entity) then
            return false
        end
    end

    return true
end

local function Tbag()
    pressInput("N")
    task.wait(0.05) -- Temps où il reste accroupi
    releaseInput("N")
    task.wait(0.05) -- Temps où il reste debout avant le prochain coup
end


local function pressFinishKeyOnce()
    local now = os.clock()

    if now - CTX.LastNoEnemyFinish
        < CTX.NoEnemyFinishCooldown
    then
        return false
    end

    local char =
        LocalPlayer.Character

    if not char
        or char:GetAttribute("DuelEliminated") == true
    then
        return false
    end

    local hp =
        getDuelHP(LocalPlayer)

    if hp == nil or hp <= 0 then
        return false
    end

    CTX.LastNoEnemyFinish = now

    pressInput("F")
    scheduleRelease("F", 0.06)

    pushLog(
        "MATCH",
        "Aucun ennemi actif → F envoyé."
    )

    for i = 1, 10 do
        Tbag()
    end

    pushLog(
        "MATCH",
        "Aucun ennemi actif → TBAG envoyé."
    )

    return true
end

local function resetEnemyScanAndRescan()
    CTX.AITarget = nil
    CTX.trackedTarget = nil
    CTX.currentTarget = nil

    table.clear(CTX.detectedRoundEnemies)
    CTX.RoundEntities = {}

    CTX.TeamScanState.Locked = false
    CTX.TeamScanState.Scanning = false
    CTX.TeamScanState.StartedAt = 0
    CTX.TeamScanState.ExpectedAllies = 0
    CTX.TeamScanState.ExpectedEnemies = 0

    refreshBotCharactersIfNeeded(true)

    task.spawn(function()
        waitAndScanGameTeams()
    end)

    return true
end

local function handleNoActiveEnemy()
    stopMovement()

    if areAllKnownEnemiesDefeated() then
        pressFinishKeyOnce()
        return
    end

    pushLog(
        "MATCH",
        "Aucune cible active alors que des ennemis peuvent encore exister → rescan."
    )

    resetEnemyScanAndRescan()
end

local function processCombat(visible, targetDistance, effectiveStyle, now)
    if not visible then
        return
    end

    if canFireM2(now) then
        CTX.AIState.LastM2 = now
        fireM2()
    end

    if targetDistance <= CTX.AutoPlayConfig.MeleeRange
        and canFireM1(now)
    then
        CTX.AIState.LastM1 = now
        fireM1()
    end
end

local function processCamera(targetEntity)
    -- L'Aimbot manuel conserve toujours la priorité caméra.
    local nativeAimHasPriority =
        CTX.aimbotActive
        and CTX.trackedTarget
        and canAimAtEntity(CTX.trackedTarget)

    if nativeAimHasPriority then
        return
    end

    if not targetEntity then
        return
    end

    -- L'IA ne LOCK sa caméra que lorsqu'elle voit réellement sa cible.
    if not isEntityActuallyVisible(targetEntity) then
        return
    end

    if canAimAtEntity(targetEntity) then
        aimAtTarget(targetEntity)
    end
end


-- ==========================================================
-- AUTO STRATEGY (VERSION REFACTORISÉE)
-- ==========================================================

local function runIALogic(hybridMode)
    if CTX.MatchState.Ended then
        CTX.AITarget = nil
        if not hybridMode then
            stopMovement()
        end
        return
    end

    if not CTX.TeamScanState.Locked then
        task.spawn(waitAndScanGameTeams)

        if not CTX.TeamScanState.Locked then
            if not hybridMode then
                stopMovement()
            end
            return
        end
    end

    local char, hrp, hum =
        getCharacter()

    if not char then
        return
    end

    ensureShiftHeld()

    local targetEntity =
        updateAITarget(hrp)

    if not targetEntity then
        handleNoActiveEnemy()
        return
    end

    local targetChar =
        getEntityCharacter(targetEntity)

    if not isEntityAlive(targetEntity) then
        resetAimPart(targetEntity)
        CTX.AITarget = nil
        CTX.AITargetLastVisible = false
        return
    end

    local targetHRP =
        targetChar
        and targetChar:FindFirstChild("HumanoidRootPart")

    if not targetHRP then
        CTX.AITarget = nil
        return
    end

    local targetDistance =
        (targetHRP.Position - hrp.Position).Magnitude

    local visible =
        isEntityActuallyVisible(targetEntity)

    CTX.AITargetLastVisible = visible
    CTX.AITargetLastValid = os.clock()

    hum.WalkSpeed =
        CTX.AutoPlayConfig.WalkSpeed

    local effectiveStyle =
        getMovementIAStyle()

    local desired, state =
        buildDesiredDirection(
            effectiveStyle,
            hrp,
            hum,
            targetHRP,
            targetChar,
            targetDistance
        )

    updateStrafeSlide(state, visible, os.clock())

    if not hybridMode then
        local now = os.clock()

        processStuckAndMovement(
            hrp,
            targetHRP,
            desired,
            now,
            targetEntity
        )
    end

    local now = os.clock()

    processCombat(
        visible,
        targetDistance,
        effectiveStyle,
        now
    )

    processCamera(targetEntity)

    CTX.AITarget = targetEntity

    logStateOnce(
        state,
        getEntityName(targetEntity)
            .. " "
            .. string.format(
                "%.0f",
                targetDistance
            )
            .. (
                visible
                and " VISIBLE"
                or " CACHE"
            )
    )
end


------------------------------------------------------------
-- BOUCLE AUTO-PLAY
------------------------------------------------------------
RunService.Heartbeat:Connect(function()
    Camera = workspace.CurrentCamera or Camera
    local now = os.clock()

    -- ⚠️ VÉRIFICATION ULTRA-STRICTE POUR LES MORTS
    if CTX.AITarget and not isEntityAlive(CTX.AITarget) then
        CTX.AITarget = nil
        CTX.AITargetLastVisible = false
        resetAimPart(CTX.AITarget)
    end

    if CTX.trackedTarget and not isEntityAlive(CTX.trackedTarget) then
        CTX.trackedTarget = nil
        CTX.currentTarget = nil
        resetAimPart(CTX.trackedTarget)
    end

    -- Sanitation globale : une cible morte/éliminée ne peut jamais rester la cible active.
    if CTX.AITarget and not isDuelTargetActive(CTX.AITarget) then
        CTX.AITarget = nil
        CTX.AITargetLastVisible = false
    end
    if CTX.currentTarget and not isDuelTargetActive(CTX.currentTarget) then
        CTX.currentTarget = nil
    end
    for i = #CTX.pendingReleases, 1, -1 do
        if now >= CTX.pendingReleases[i].time then
            releaseInput(CTX.pendingReleases[i].name)
            table.remove(CTX.pendingReleases, i)
        end
    end

    if CTX.slideActive and now >= CTX.slideEndTime then
        CTX.slideActive = false
        releaseInput("C")
    end

    if CTX.StrafeSlideActive
        and now >= CTX.StrafeSlideEndTime
    then
        CTX.StrafeSlideActive = false
        releaseInput("C")
    end

    local mode = CTX.AutoPlayConfig.Mode

    if CTX.playbackActive and (mode == "Copy" or mode == "Hybride") then
        runCopyPlayback(mode == "Hybride")
        if mode == "Hybride" and CTX.AutoPlayConfig.Enabled then runIALogic(true) end
        return
    end

    if CTX.AutoPlayConfig.Enabled and mode == "IA" then
        runIALogic(false)
        return
    end

    if not CTX.playbackActive and not CTX.AutoPlayConfig.Enabled then
        stopMovement()
        releaseShift()
        if CTX.slideActive then
            CTX.slideActive = false
            releaseInput("C")
        end

        if CTX.StrafeSlideActive then
            CTX.StrafeSlideActive = false
            CTX.StrafeSlideEndTime = 0
            releaseInput("C")
        end
    end
end)



------------------------------------------------------------
-- ESP V2 — MODULE MODULABLE
-- Remplace l'ancien moteur ESP/Tracers.
------------------------------------------------------------

CTX.ESP = {
    folder = nil,

    EspActive = true,
    EspHighlight = true,
    EspSkeleton = true,
    EspNameHp = true,
    EspTracers = true,

    TracerOrigin = "Centre",
    TracerTarget = "Head",

    Color = Color3.fromRGB(255, 0, 0),
    SkeletonThickness = 3,
    TracerThickness = 1,
    TextSize = 14,

    activeTracers = {},
    playerConnections = {},
}

do
    local CoreGui = game:GetService("CoreGui")

    local oldFolder = CoreGui:FindFirstChild("rioESP")
    if oldFolder then
        oldFolder:Destroy()
    end

    CTX.ESP.folder = Instance.new("Folder")
    CTX.ESP.folder.Name = "rioESP"
    CTX.ESP.folder.Parent = CoreGui
end

local function getESPColor()
    return CTX.ESP.Color or Color3.fromRGB(255, 0, 0)
end

local function obterOrigineTracerESP(camera)
    local size = camera.ViewportSize

    if CTX.ESP.TracerOrigin == "Centre" then
        return Vector2.new(size.X / 2, size.Y / 2)
    end

    return Vector2.new(size.X / 2, size.Y)
end

local function removeTracerESP(player)
    local line = CTX.ESP.activeTracers[player]

    if line then
        pcall(function()
            line.Visible = false
            line:Remove()
        end)

        CTX.ESP.activeTracers[player] = nil
    end
end

local function clearPlayerESP(player)
    if not player then
        return
    end

    local folderName =
        player.Name .. "_Skeleton_ESP"

    local playerFolder =
        CTX.ESP.folder
        and CTX.ESP.folder:FindFirstChild(folderName)

    if playerFolder then
        playerFolder:Destroy()
    end

    removeTracerESP(player)

    if CTX.ESP.playerConnections[player] then
        for _, connection in ipairs(
            CTX.ESP.playerConnections[player]
        ) do
            pcall(function()
                connection:Disconnect()
            end)
        end

        CTX.ESP.playerConnections[player] = nil
    end
end

local function clearAllESP()
    for _, playerFolder in ipairs(
        CTX.ESP.folder
        and CTX.ESP.folder:GetChildren()
        or {}
    ) do
        playerFolder:Destroy()
    end

    for player in pairs(CTX.ESP.activeTracers) do
        removeTracerESP(player)
    end
end

local function creerHighlightSecurise(character, dossierParent)
    if not CTX.ESP.EspActive
        or not CTX.ESP.EspHighlight
        or not character
    then
        return
    end

    local hl = Instance.new("Highlight")

    hl.Name =
        character.Name
        .. "_HighlightESP"

    hl.FillColor = getESPColor()
    hl.FillTransparency = 0.75
    hl.OutlineColor = getESPColor()
    hl.OutlineTransparency = 0
    hl.DepthMode =
        Enum.HighlightDepthMode.AlwaysOnTop
    hl.Adornee = character
    hl.Parent = dossierParent
end

local function creerLigneSquelette(
    partieA,
    partieB,
    dossierParent
)
    if not CTX.ESP.EspActive
        or not CTX.ESP.EspSkeleton
        or not partieA
        or not partieB
    then
        return
    end

    local ligne =
        Instance.new("LineHandleAdornment")

    ligne.Name =
        partieA.Name
        .. "_to_"
        .. partieB.Name

    ligne.Thickness =
        CTX.ESP.SkeletonThickness

    ligne.Color3 = getESPColor()
    ligne.ZIndex = 10
    ligne.AlwaysOnTop = true
    ligne.Adornee = partieA
    ligne.Length = 0
    ligne.Parent = dossierParent

    task.spawn(function()
        while ligne
            and ligne.Parent
            and partieA
            and partieB
            and partieA.Parent
            and partieB.Parent
        do
            if not CTX.ESP.EspActive
                or not CTX.ESP.EspSkeleton
            then
                ligne.Transparency = 1
            else
                ligne.Transparency = 0
                ligne.Color3 = getESPColor()
                ligne.Thickness =
                    CTX.ESP.SkeletonThickness

                local posA = partieA.Position
                local posB = partieB.Position

                ligne.Length =
                    (posA - posB).Magnitude

                ligne.CFrame =
                    CFrame.lookAt(
                        Vector3.zero,
                        partieA.CFrame:Inverse()
                            * posB
                    )
            end

            task.wait()
        end

        if ligne then
            ligne:Destroy()
        end
    end)
end

local function createTextESP(
    autreJoueur,
    conteneur,
    char,
    head
)
    if not CTX.ESP.EspNameHp then
        return
    end

    local monChar = LocalPlayer.Character
    local monRoot =
        monChar
        and monChar:FindFirstChild(
            "HumanoidRootPart"
        )

    local autreRoot =
        char:FindFirstChild(
            "HumanoidRootPart"
        )

    local humanoid =
        char:FindFirstChildOfClass("Humanoid")

    local billboard =
        Instance.new("BillboardGui")

    billboard.Name = "TextESP"
    billboard.Size =
        UDim2.new(0, 200, 0, 50)

    billboard.StudsOffset =
        Vector3.new(0, 2.5, 0)

    billboard.AlwaysOnTop = true
    billboard.Adornee = head
    billboard.Parent = conteneur

    local textLabel =
        Instance.new("TextLabel")

    textLabel.Size =
        UDim2.new(1, 0, 1, 0)

    textLabel.BackgroundTransparency = 1
    textLabel.TextColor3 =
        Color3.fromRGB(255, 255, 255)

    textLabel.TextStrokeTransparency = 0
    textLabel.TextSize =
        CTX.ESP.TextSize

    textLabel.Font =
        Enum.Font.SourceSansBold

    textLabel.Parent = billboard

    local connexion

    connexion =
        RunService.RenderStepped:Connect(
            function()
                if not billboard
                    or not billboard.Parent
                    or not char.Parent
                    or not head.Parent
                then
                    if connexion then
                        connexion:Disconnect()
                    end

                    return
                end

                if not CTX.ESP.EspActive
                    or not CTX.ESP.EspNameHp
                then
                    textLabel.Visible = false
                    return
                end

                textLabel.Visible = true
                textLabel.TextSize =
                    CTX.ESP.TextSize

                local distanceText =
                    "?? studs"

                if monRoot and autreRoot then
                    local distance =
                        (
                            monRoot.Position
                            - autreRoot.Position
                        ).Magnitude

                    distanceText =
                        math.round(distance)
                        .. " studs"
                end

                local hpActuel = 0

                if CTX.USE_GAME_HP then
                    hpActuel =
                        char:GetAttribute("HP")
                        or (
                            humanoid
                            and humanoid.Health
                        )
                        or 0
                else
                    hpActuel =
                        humanoid
                        and humanoid.Health
                        or 0
                end

                hpActuel =
                    math.round(hpActuel)

                textLabel.Text =
                    string.format(
                        "%s\nHP: %s | %s",
                        autreJoueur.Name,
                        tostring(hpActuel),
                        distanceText
                    )
            end
        )

    table.insert(
        CTX.ESP.playerConnections[autreJoueur],
        connexion
    )
end

local function appliquerSqueletteR15(autreJoueur)
    if autreJoueur == LocalPlayer then
        return
    end

    clearPlayerESP(autreJoueur)

    if not CTX.ESP.folder then
        return
    end

    local nomDossier =
        autreJoueur.Name
        .. "_Skeleton_ESP"

    local conteneur =
        Instance.new("Folder")

    conteneur.Name = nomDossier
    conteneur.Parent = CTX.ESP.folder

    CTX.ESP.playerConnections[autreJoueur] = {}

    local function nettoyerESP()
        local ancienDossier =
            CTX.ESP.folder
            and CTX.ESP.folder:FindFirstChild(
                nomDossier
            )

        if ancienDossier then
            ancienDossier:Destroy()
        end

        removeTracerESP(autreJoueur)
    end

    local char = autreJoueur.Character
    if not char then
        return
    end

    local humanoid =
        char:FindFirstChildOfClass("Humanoid")

    if humanoid then
        local deathConnection =
            humanoid.Died:Connect(
                nettoyerESP
            )

        table.insert(
            CTX.ESP.playerConnections[autreJoueur],
            deathConnection
        )
    end

    local destroyingConnection =
        char.Destroying:Connect(
            nettoyerESP
        )

    table.insert(
        CTX.ESP.playerConnections[autreJoueur],
        destroyingConnection
    )

    local upperTorso =
        char:WaitForChild(
            "UpperTorso",
            5
        )

    local lowerTorso =
        char:WaitForChild(
            "LowerTorso",
            5
        )

    local head =
        char:WaitForChild(
            "Head",
            5
        )

    if not (
        upperTorso
        and lowerTorso
        and head
    ) then
        return
    end

    createTextESP(
        autreJoueur,
        conteneur,
        char,
        head
    )

    creerHighlightSecurise(
        char,
        conteneur
    )

    creerLigneSquelette(
        upperTorso,
        head,
        conteneur
    )

    creerLigneSquelette(
        lowerTorso,
        upperTorso,
        conteneur
    )

    if char:FindFirstChild(
        "LeftUpperArm"
    )
        and char:FindFirstChild(
            "LeftLowerArm"
        )
        and char:FindFirstChild(
            "LeftHand"
        )
    then
        creerLigneSquelette(
            upperTorso,
            char.LeftUpperArm,
            conteneur
        )

        creerLigneSquelette(
            char.LeftUpperArm,
            char.LeftLowerArm,
            conteneur
        )

        creerLigneSquelette(
            char.LeftLowerArm,
            char.LeftHand,
            conteneur
        )
    end

    if char:FindFirstChild(
        "RightUpperArm"
    )
        and char:FindFirstChild(
            "RightLowerArm"
        )
        and char:FindFirstChild(
            "RightHand"
        )
    then
        creerLigneSquelette(
            upperTorso,
            char.RightUpperArm,
            conteneur
        )

        creerLigneSquelette(
            char.RightUpperArm,
            char.RightLowerArm,
            conteneur
        )

        creerLigneSquelette(
            char.RightLowerArm,
            char.RightHand,
            conteneur
        )
    end

    if char:FindFirstChild(
        "LeftUpperLeg"
    )
        and char:FindFirstChild(
            "LeftLowerLeg"
        )
        and char:FindFirstChild(
            "LeftFoot"
        )
    then
        creerLigneSquelette(
            lowerTorso,
            char.LeftUpperLeg,
            conteneur
        )

        creerLigneSquelette(
            char.LeftUpperLeg,
            char.LeftLowerLeg,
            conteneur
        )

        creerLigneSquelette(
            char.LeftLowerLeg,
            char.LeftFoot,
            conteneur
        )
    end

    if char:FindFirstChild(
        "RightUpperLeg"
    )
        and char:FindFirstChild(
            "RightLowerLeg"
        )
        and char:FindFirstChild(
            "RightFoot"
        )
    then
        creerLigneSquelette(
            lowerTorso,
            char.RightUpperLeg,
            conteneur
        )

        creerLigneSquelette(
            char.RightUpperLeg,
            char.RightLowerLeg,
            conteneur
        )

        creerLigneSquelette(
            char.RightLowerLeg,
            char.RightFoot,
            conteneur
        )
    end
end

-- Onglet ESP dans la même Window Orion.
CTX.ESPTab =
    CTX.Window:MakeTab({
        Name = "ESP",
        Icon = "rbxassetid://4483345998",
        PremiumOnly = false
    })

CTX.ESPTab:AddToggle({
    Name = "ESP global",
    Default = true,
    Callback = function(value)
        CTX.ESP.EspActive = value

        if not value then
            clearAllESP()
        else
            for _, player in ipairs(
                Players:GetPlayers()
            ) do
                if player ~= LocalPlayer then
                    task.spawn(
                        appliquerSqueletteR15,
                        player
                    )
                end
            end
        end
    end
})

CTX.ESPTab:AddToggle({
    Name = "Highlight",
    Default = true,
    Callback = function(value)
        CTX.ESP.EspHighlight = value
        for _, player in ipairs(
            Players:GetPlayers()
        ) do
            if player ~= LocalPlayer
                and player.Character
            then
                task.spawn(
                    appliquerSqueletteR15,
                    player
                )
            end
        end
    end
})

CTX.ESPTab:AddToggle({
    Name = "Squelette",
    Default = true,
    Callback = function(value)
        CTX.ESP.EspSkeleton = value
    end
})

CTX.ESPTab:AddToggle({
    Name = "Nom + HP + Distance",
    Default = true,
    Callback = function(value)
        CTX.ESP.EspNameHp = value
    end
})

CTX.ESPTab:AddToggle({
    Name = "Tracers",
    Default = true,
    Callback = function(value)
        CTX.ESP.EspTracers = value
    end
})

CTX.ESPTab:AddColorpicker({
    Name = "Couleur ESP",
    Default = CTX.ESP.Color,
    Callback = function(value)
        CTX.ESP.Color = value
    end
})

CTX.ESPTab:AddDropdown({
    Name = "Origine Tracer",
    Default = CTX.ESP.TracerOrigin,
    Options = {
        "Centre",
        "Bas milieu"
    },
    Callback = function(value)
        CTX.ESP.TracerOrigin = value
    end
})

CTX.ESPTab:AddDropdown({
    Name = "Cible Tracer",
    Default = CTX.ESP.TracerTarget,
    Options = {
        "Head",
        "UpperTorso",
        "HumanoidRootPart"
    },
    Callback = function(value)
        CTX.ESP.TracerTarget = value
    end
})

CTX.ESPTab:AddSlider({
    Name = "Épaisseur Skeleton",
    Min = 1,
    Max = 6,
    Default = 3,
    Increment = 1,
    ValueName = "px",
    Callback = function(value)
        CTX.ESP.SkeletonThickness = value
    end
})

CTX.ESPTab:AddSlider({
    Name = "Épaisseur Tracer",
    Min = 1,
    Max = 4,
    Default = 1,
    Increment = 1,
    ValueName = "px",
    Callback = function(value)
        CTX.ESP.TracerThickness = value
    end
})

CTX.ESPTab:AddSlider({
    Name = "Taille du texte",
    Min = 10,
    Max = 22,
    Default = 14,
    Increment = 1,
    ValueName = "px",
    Callback = function(value)
        CTX.ESP.TextSize = value
    end
})

trackConnection(
    Players.PlayerAdded:Connect(
        function(player)
            if player == LocalPlayer then
                return
            end

            local characterConnection =
                player.CharacterAdded:Connect(
                    function()
                        task.spawn(
                            appliquerSqueletteR15,
                            player
                        )
                    end
                )

            CTX.ESP.playerConnections[player] =
                CTX.ESP.playerConnections[player]
                or {}

            table.insert(
                CTX.ESP.playerConnections[player],
                characterConnection
            )

            if player.Character then
                task.spawn(
                    appliquerSqueletteR15,
                    player
                )
            end
        end
    )
)

trackConnection(
    Players.PlayerRemoving:Connect(
        function(player)
            clearPlayerESP(player)
        end
    )
)

trackConnection(
    RunService.RenderStepped:Connect(
        function()
            Camera =
                workspace.CurrentCamera
                or Camera

            local origineTracer =
                obterOrigineTracerESP(
                    Camera
                )

            for _, player in ipairs(
                Players:GetPlayers()
            ) do
                if player ~= LocalPlayer then
                    local char =
                        player.Character

                    local ciblePart =
                        char
                        and char:FindFirstChild(
                            CTX.ESP.TracerTarget
                        )

                    local humanoid =
                        char
                        and char:FindFirstChildOfClass(
                            "Humanoid"
                        )

                    local estVivant =
                        humanoid
                        and humanoid.Health > 0

                    if char
                        and ciblePart
                        and estVivant
                        and CTX.ESP.EspActive
                        and CTX.ESP.EspTracers
                    then
                        local screenPos, onScreen =
                            Camera:WorldToViewportPoint(
                                ciblePart.Position
                            )

                        if onScreen then
                            if not CTX.ESP.activeTracers[player] then
                                local maLigne =
                                    Drawing.new("Line")

                                maLigne.Thickness =
                                    CTX.ESP.TracerThickness

                                maLigne.Transparency = 1
                                maLigne.Color =
                                    getESPColor()

                                CTX.ESP.activeTracers[player] =
                                    trackDrawing(
                                        maLigne
                                    )
                            end

                            local ligneVectorielle =
                                CTX.ESP.activeTracers[player]

                            ligneVectorielle.From =
                                origineTracer

                            ligneVectorielle.To =
                                Vector2.new(
                                    screenPos.X,
                                    screenPos.Y
                                )

                            ligneVectorielle.Color =
                                getESPColor()

                            ligneVectorielle.Thickness =
                                CTX.ESP.TracerThickness

                            ligneVectorielle.Visible =
                                true
                        elseif CTX.ESP.activeTracers[player] then
                            CTX.ESP.activeTracers[player].Visible =
                                false
                        end
                    elseif CTX.ESP.activeTracers[player] then
                        CTX.ESP.activeTracers[player].Visible =
                            false
                    end
                end
            end
        end
    )
)

for _, player in ipairs(
    Players:GetPlayers()
) do
    if player ~= LocalPlayer then
        task.spawn(
            appliquerSqueletteR15,
            player
        )
    end
end

OrionLib:Init()

pcall(function()
    OrionLib:SendTelemetryEvent(
        "script_loaded",
        "rio V7 + UI chargés",
        tostring(game.PlaceId)
    )
end)

--========================================================--
-- DÉTECTION FIN DE MATCH
--========================================================--


task.spawn(function()
    while CTX.MatchState.MatchDetectionRunning do
        local winscreen =
            PlayerGui:FindFirstChild("Winscreen")

        if winscreen
            and winscreen:IsA("ScreenGui")
            and winscreen.Enabled
        then
            if not CTX.MatchState.Ended then
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

                    
                end
            end
        end

        task.wait(0.15)
    end
end)

pushLog("SYSTEM", "rio v7.2 prêt")

if Lib == "1bzableLib" then
    if CTX.Window
        and typeof(CTX.Window.ToggleMinimize) == "function"
    then
        CTX.Window:ToggleMinimize()
    else
        warn("[rio DEBUG] 1bzableLib: ToggleMinimize absent")
    end
else
    if OrionLib
        and typeof(OrionLib.ToggleMinimize) == "function"
    then
        OrionLib:ToggleMinimize()
    end
end
