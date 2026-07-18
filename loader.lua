# Local-only reference loader. Prefer Multscript.lua (GitHub fetch).
local USER    = "mahanneo"
local REPO    = "aw_cs2v6_mahanmoi"
local VERSION = "latest"

local function ref()
    if VERSION == nil or VERSION == "" or VERSION == "latest" then return "main" end
    return VERSION
end

local BASE = "https://raw.githubusercontent.com/" .. USER .. "/" .. REPO .. "/" .. ref() .. "/"

local function fetch(url, cacheFile)
    local src
    local bust = url .. "?nocache=" .. tostring({}):gsub("%W", "")
    pcall(function() src = http.Get(bust) end)
    if type(src) ~= "string" or #src <= 500 then pcall(function() src = http.Get(url) end) end
    if type(src) == "string" and #src > 500 then
        pcall(function()
            local f = file.Open(cacheFile, "w")
            if f then f:Write(src); f:Close() end
        end)
        return src, "server"
    end
    pcall(function()
        local f = file.Open(cacheFile, "r")
        if f then src = f:Read(); f:Close() end
    end)
    if type(src) == "string" and #src > 500 then return src, "cache" end
    return nil
end

local src, where = fetch(BASE .. "mahanmoi.lua", ".\\mahanmoi_lua\\mahanmoi.lua")
if not src then print("[loader] FATAL: cannot fetch mahanmoi.lua") return end

local chunk, err = loadstring(src, "=mahanmoi.lua")
if not chunk then print("[loader] compile error: " .. tostring(err)) return end

_G.MAHANMOI_BASE = BASE
print(string.format("[loader] mahanmoi %s from %s", ref(), tostring(where)))

local ok, e = pcall(chunk)
if not ok then print("[loader] run error: " .. tostring(e)) end
