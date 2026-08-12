-- Nexus V6 Launcher
if not game:IsLoaded() then
    game.Loaded:Wait()
end

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local LocalPlayer = Players.LocalPlayer

local info
local ok = pcall(function()
    info = MarketplaceService:GetProductInfo(game.PlaceId)
end)

if not ok or not info or type(info.Name) ~= "string" then
    warn("[Nexus Launcher] Impossible de lire le nom de l'expérience.")
    return
end

local experienceName = info.Name
print("[Nexus Launcher] Experience : " .. experienceName)

if not experienceName:find(":", 1, true) then
    print("[Nexus Launcher] ':' absent → Nexus non chargé.")
    return
end

print("[Nexus Launcher] ':' détecté → chargement de Nexus V7 CTX.")

local okLoad, loadError = pcall(function()
    loadstring(game:HttpGet(
        "https://raw.githubusercontent.com/Moha-Echo/animated-invention/refs/heads/main/Nexus/v7-CTX.lua"
    ))()
end)

if not okLoad then
    warn("[Nexus Launcher] Erreur de chargement : " .. tostring(loadError))
    return
end

local function clickWhenVisible()
    -- 1. Attente de l'existence des éléments dans l'arborescence
    local winscreen = PlayerGui:WaitForChild("Winscreen", 5)
    if not winscreen then return end
    
    local buttons = winscreen:WaitForChild("Buttons", 5)
    if not buttons then return end
    
    local queueAgain = buttons:WaitForChild("QueueAgain", 5)
    if not queueAgain then return end
    
    local button = queueAgain:WaitForChild("Button", 5)
    if not button then return end
    
    -- 2. Boucle d'attente jusqu'à ce que le bouton devienne visible à l'écran
    -- (On vérifie aussi que ses parents sont visibles pour être sûr)
    while not (button.Visible and queueAgain.Visible and buttons.Visible and winscreen.Enabled) do
        task.wait(0.1) -- Pause de 100ms pour ne pas faire ramer le jeu
    end
    
    -- Petite sécurité de 0.1s après l'apparition avant de cliquer
    task.wait(0.1)
    
    -- 3. Simulation du clic universel (ImageButton compatible)
    if button then
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
end

-- Lance la détection et le clic automatique
clickWhenVisible()

--[[
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

task.spawn(function()
    while true do
        local winscreen = PlayerGui:FindFirstChild("Winscreen")
        local buttons = winscreen and winscreen:FindFirstChild("Buttons")
        local queueAgain = buttons and buttons:FindFirstChild("QueueAgain")
        local button = queueAgain and queueAgain:FindFirstChild("Button")

        if winscreen
            and winscreen:IsA("ScreenGui")
            and winscreen.Enabled
            and queueAgain
            and queueAgain.Visible
            and button
            and button:IsA("GuiButton")
            and button.Visible
        then
            task.wait(0.1)

            pcall(function()
                for _, connection in ipairs(getconnections(button.Activated)) do
                    connection:Fire()
                end
            end)

            task.wait(0.75)
        end

        task.wait(0.15)
    end
end)
]]--
