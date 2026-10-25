-- CandyFarmer v9 Launcher
if not game:IsLoaded() then
    game.Loaded:Wait()
end

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local LocalPlayer = Players.LocalPlayer

local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local v = getgenv().v or getgenv().version or "v9"

local info
local ok = pcall(function()
    info = MarketplaceService:GetProductInfo(game.PlaceId)
end)

if not ok or not info or type(info.Name) ~= "string" then
    warn("[CandyFarmer Launcher] Impossible de lire le nom de l'expérience.")
    return
end

local experienceName = info.Name
print("[CandyFarmer Launcher] Experience : " .. experienceName)

if not experienceName:find("2", 1, true) then
    print("[CandyFarmer Launcher] '2' absent → CandyFarmer "..v.." non chargé.")
    return
end

print("[CandyFarmer Launcher] '2' détecté → chargement de CandyFarmer "..v..".")

local okLoad, loadError = pcall(function()
    loadstring(game:HttpGet(
        "https://raw.githubusercontent.com/Moha-Echo/animated-invention/refs/heads/main/CandyFarmer/"..v..".lua" --"https://raw.githubusercontent.com/Moha-Echo/animated-invention/refs/heads/main/Nexus/v7-CTX.lua"
    ))()
end)

if not okLoad then
    warn("[CandyFarmer Launcher] Erreur de chargement : " .. tostring(loadError))
    return
end

