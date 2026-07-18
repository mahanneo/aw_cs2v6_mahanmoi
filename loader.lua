لودر


-- ============================================================
-- mahanmoi Loader
-- Fetches main script from GitHub, caches locally, falls back
-- ============================================================
local USER    = "mahanneo"
local REPO    = "aw_cs2v6_mahanmoi"
local VERSION = "latest"
local CACHE_DIR = ".\\mahanmoi_lua"

local function ref()
    if VERSION == nil or VERSION == "" or VERSION == "latest" then
        return "main"
    end
    return VERSION
end

local BASE = "https://raw.githubusercontent.com/" .. USER .. "/" .. REPO .. "/" .. ref() .. "/"

-- ============================================================
-- ENSURE CACHE DIRECTORY EXISTS
-- ============================================================
local function ensureDir(path)
    -- Simple recursive directory creation via shell
    -- Works on Windows where CS2 runs
    pcall(function()
        local f = file.Open(path .. "\\.keep", "w")
        if f then
            f:Write("")
            f:Close()
            return true
        end
    end)
    -- Fallback: try to create via os.execute (Windows)
    pcall(function()
        os.execute('mkdir "' .. path:gsub("/", "\\") .. '" 2>nul')
    end)
    return true
end

ensureDir(CACHE_DIR)

-- ============================================================
-- HTTP FETCH WITH CACHE
-- ============================================================
local function fetch(url, cacheFile)
    local src

    -- Attempt 1: cache-bust URL (bypass any proxy/CDN cache)
    local bust = url .. "?nocache=" .. tostring({}):gsub("%W", "")
    pcall(function() src = http.Get(bust) end)

    -- Attempt 2: direct URL (if bust failed or returned garbage)
    if type(src) ~= "string" or #src <= 500 then
        src = nil
        pcall(function() src = http.Get(url) end)
    end

    -- If we got valid source, cache it and return
    if type(src) == "string" and #src > 500 then
        pcall(function()
            local f = file.Open(cacheFile, "w")
            if f then f:Write(src); f:Close() end
        end)
        return src, "server"
    end

    -- Attempt 3: read from cache
    src = nil
    pcall(function()
        local f = file.Open(cacheFile, "r")
        if f then src = f:Read(); f:Close() end
    end)
    if type(src) == "string" and #src > 500 then
        return src, "cache"
    end

    return nil
end

-- ============================================================
-- LOCAL FILE FALLBACK
-- ============================================================
local function loadLocal(path)
    local src
    pcall(function()
        local f = file.Open(path, "r")
        if f then src = f:Read(); f:Close() end
    end)
    if type(src) == "string" and #src > 500 then
        return src, "local"
    end
    return nil
end

-- ============================================================
-- EXECUTE SOURCE
-- ============================================================
local function run(src, label)
    if type(src) ~= "string" or #src <= 500 then
        print("[loader] source empty or too short")
        return false
    end

    local chunk, err = loadstring(src, "=" .. label)
    if not chunk then
        print("[loader] COMPILE ERROR in " .. label .. ":")
        print("[loader] " .. tostring(err))
        return false
    end

    -- Set base URL before execution so sub-modules can find it
    _G.MAHANMOI_BASE = BASE

    local ok, e = pcall(chunk)
    if not ok then
        print("[loader] RUN ERROR in " .. label .. ":")
        print("[loader] " .. tostring(e))
        return false
    end

    return true
end

-- ============================================================
-- MAIN
-- ============================================================
local mainFile    = "mahanmoi.lua"
local cachePath   = CACHE_DIR .. "\\" .. mainFile
local localPath   = ".\\" .. mainFile  -- same dir as loader

print(string.format("[loader] mahanmoi %s | repo: %s/%s", ref(), USER, REPO))
print("[loader] base: " .. BASE)

-- Try: server -> cache -> local file
local src, where = fetch(BASE .. mainFile, cachePath)

if not src then
    print("[loader] server & cache failed, trying local file...")
    src, where = loadLocal(localPath)
end

if not src then
    print("[loader] ============================================")
    print("[loader] FATAL: Cannot load mahanmoi!")
    print("[loader] ============================================")
    print("[loader] Possible causes:")
    print("[loader]   1. No internet connection")
    print("[loader]   2. GitHub is blocked in your region")
    print("[loader]   3. http.Get() is not available")
    print("[loader] ")
    print("[loader] Fix: Place " .. mainFile .. " next to this loader")
    print("[loader]      or in " .. CACHE_DIR .. "\\")
    print("[loader] ============================================")
    return
end

print("[loader] loaded " .. mainFile .. " from " .. tostring(where))

if run(src, mainFile) then
    print("[loader] mahanmoi started successfully")
else
    print("[loader] mahanmoi failed to start (see errors above)")
end
