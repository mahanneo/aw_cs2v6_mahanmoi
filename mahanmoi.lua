local BASE        = rawget(_G, "MAHANMOI_BASE") or "https://raw.githubusercontent.com/mahanneo/aw_cs2v6_mahanmoi/main/"
local GUILIB_URL  = BASE .. "mahanmoi_guilib.lua"
local CHANGER_URL = BASE .. "mahanmoi_changer.lua"

-- اگر میخوای از کد آفلاین استفاده کنی، آدرس رو عوض کن:
-- local CHANGER_URL = "file:///./mahanmoi_changer.lua"

local ffi = rawget(_G, "ffi")

local function r_ptr(a) return tonumber(ffi.cast("uint64_t*", a)[0]) end
local function valid(p) return p ~= nil and p > 0x10000 and p < 0x7FFFFFFFFFFF end

local SIG = {
    vm = "E8 ?? ?? ?? ?? 48 8B CB E8 ?? ?? ?? ?? 84 C0 74 11 F3 0F 10 45 B0",
}

-- ============================================================
-- HTTP FETCH + CACHE
-- ============================================================
local function fetch(url, cacheFile)
    local src
    local bust = url .. "?nocache=" .. tostring({}):gsub("%W", "")
    pcall(function() src = http.Get(bust) end)
    if type(src) ~= "string" or #src <= 500 then
        pcall(function() src = http.Get(url) end)
    end
    if type(src) == "string" and #src > 500 then
        pcall(function()
            local f = file.Open(cacheFile, "w")
            if f then f:Write(src); f:Close() end
        end)
        return src, "server"
    end
    -- Cache fallback
    pcall(function()
        local f = file.Open(cacheFile, "r")
        if f then src = f:Read(); f:Close() end
    end)
    if type(src) == "string" and #src > 500 then return src, "cache" end
    return nil
end

local function load_mod(url, cacheFile, name)
    local src, where = fetch(url, cacheFile)
    if not src then
        print("[mahanmoi] FATAL: cannot load " .. name)
        return nil
    end
    local chunk, err = loadstring(src, "=" .. cacheFile)
    if not chunk then
        print("[mahanmoi] " .. name .. " compile error: " .. tostring(err))
        return nil
    end
    local ok, mod = pcall(chunk)
    if not ok then
        print("[mahanmoi] " .. name .. " run error: " .. tostring(mod))
        return nil
    end
    print("[mahanmoi] " .. name .. " loaded from " .. tostring(where))
    return mod
end

-- ============================================================
-- LOAD MODULES
-- ============================================================
local M = load_mod(GUILIB_URL, ".\\mahanmoi_lua\\mahanmoi_guilib.lua", "guilib")
if type(M) ~= "table" then
    print("[mahanmoi] CRITICAL: guilib failed to load, aborting")
    return
end

local C = load_mod(CHANGER_URL, ".\\mahanmoi_lua\\mahanmoi_changer.lua", "changer")
if type(C) ~= "table" then
    print("[mahanmoi] CRITICAL: changer failed to load, aborting")
    return
end

-- ============================================================
-- SANITY CHECK - Verify C module has required API
-- ============================================================
local required_C = { "items", "names", "skinList", "apply", "remove", "resetAll", "activeDef", "isKnife" }
local missing = {}
for _, fn in ipairs(required_C) do
    if C[fn] == nil then missing[#missing + 1] = fn end
end
if #missing > 0 then
    print("[mahanmoi] WARNING: changer module missing functions: " .. table.concat(missing, ", "))
    print("[mahanmoi] Some features may not work. Update mahanmoi_changer.lua")
end

local floor = math.floor

-- ============================================================
-- VIEWMODEL OVERRIDE (VM) - Disabled by default for safety
-- ============================================================
local VM = {}

do
    local page, match, origRel, ok = nil, nil, nil, false

    local function r_i32(a) return ffi.cast("int32_t*", a)[0] end
    local function w_u8(a, v) ffi.cast("uint8_t*", a)[0] = v end
    local function w_i32(a, v) ffi.cast("int32_t*", a)[0] = v end
    local function w_f32(a, v) ffi.cast("float*", a)[0] = v end

    local function le64(v)
        local t = {}
        for _ = 1, 8 do t[#t + 1] = v % 256; v = math.floor(v / 256) end
        return t
    end

    local function alloc_near(target, size)
        local gran = 0x10000
        local base = target - (target % gran)
        for i = 1, 0x8000 do
            local lo, hi = base - i * gran, base + i * gran
            if lo > 0x10000 then
                local p = ffi.C.VirtualAlloc(ffi.cast("void*", lo), size, 0x3000, 0x40)
                if p ~= nil then return p end
            end
            local p2 = ffi.C.VirtualAlloc(ffi.cast("void*", hi), size, 0x3000, 0x40)
            if p2 ~= nil then return p2 end
        end
        return nil
    end

    local function install()
        if type(ffi) ~= "table" then print("[mahanmoi] VM: no ffi"); return false end
        pcall(function() ffi.cdef [[
            void* VirtualAlloc(void*, size_t, uint32_t, uint32_t);
            int   VirtualProtect(void*, size_t, uint32_t, uint32_t*);
            void* GetCurrentProcess(void);
            int   FlushInstructionCache(void*, void*, size_t);
        ]] end)

        local a = mem.FindPattern("client.dll", SIG.vm)
        if not a or a == 0 then print("[mahanmoi] VM: sig not found"); return false end
        match = a
        local orig = a + 5 + r_i32(a + 1)

        local p = alloc_near(orig, 0x1000)
        if p == nil then print("[mahanmoi] VM: alloc failed"); return false end
        page = tonumber(ffi.cast("uintptr_t", p))
        local code = page + 16

        local b = { 0x53, 0x56, 0x48, 0x83, 0xEC, 0x28, 0x48, 0x89, 0xD6, 0x48, 0xB8 }
        for _, v in ipairs(le64(orig)) do b[#b + 1] = v end
        for _, v in ipairs({ 0xFF, 0xD0, 0x48, 0xBB }) do b[#b + 1] = v end
        for _, v in ipairs(le64(page)) do b[#b + 1] = v end
        for _, v in ipairs({
            0x8B, 0x0B, 0x85, 0xC9, 0x74, 0x2B,
            0xF3, 0x0F, 0x10, 0x4B, 0x04, 0xF3, 0x0F, 0x58, 0x0E, 0xF3, 0x0F, 0x11, 0x0E,
            0xF3, 0x0F, 0x10, 0x4B, 0x08, 0xF3, 0x0F, 0x58, 0x4E, 0x04, 0xF3, 0x0F, 0x11, 0x4E, 0x04,
            0xF3, 0x0F, 0x10, 0x4B, 0x0C, 0xF3, 0x0F, 0x58, 0x4E, 0x08, 0xF3, 0x0F, 0x11, 0x4E, 0x08,
            0x48, 0x83, 0xC4, 0x28, 0x5E, 0x5B, 0xC3,
        }) do b[#b + 1] = v end
        for i = 0, #b - 1 do w_u8(code + i, b[i + 1]) end
        w_i32(page, 0); w_f32(page + 4, 0); w_f32(page + 8, 0); w_f32(page + 12, 0)

        local rel = code - (match + 5)
        if rel < -2147483648 or rel > 2147483647 then
            print("[mahanmoi] VM: rel32 overflow"); return false
        end
        origRel = r_i32(match + 1)
        local old = ffi.new("uint32_t[1]")
        ffi.C.VirtualProtect(ffi.cast("void*", match), 5, 0x40, old)
        w_i32(match + 1, rel)
        ffi.C.VirtualProtect(ffi.cast("void*", match), 5, old[0], old)
        pcall(function() ffi.C.FlushInstructionCache(ffi.C.GetCurrentProcess(), ffi.cast("void*", match), 5) end)
        print("[mahanmoi] VM: installed")
        return true
    end

    -- Disabled: code patch crashes after CS2 updates (safe mode)
    -- pcall(function() ok = install() end)
    print("[mahanmoi] VM: auto-install disabled (safe mode)")

    function VM.set(on, x, y, z)
        if not ok or not page then return end
        w_i32(page, on and 1 or 0)
        w_f32(page + 4, x or 0)
        w_f32(page + 8, y or 0)
        w_f32(page + 12, z or 0)
    end

    function VM.uninstall()
        if not (ok and match and origRel) then return end
        pcall(function()
            local old = ffi.new("uint32_t[1]")
            ffi.C.VirtualProtect(ffi.cast("void*", match), 5, 0x40, old)
            w_i32(match + 1, origRel)
            ffi.C.VirtualProtect(ffi.cast("void*", match), 5, old[0], old)
        end)
    end
end
pcall(function() callbacks.Register("Unload", function() pcall(VM.uninstall) end) end)

-- ============================================================
-- HIT SOUNDS (HS)
-- ============================================================
local HS = {}

do
    local f = ffi
    local FFF, FNF, FCL, GCD, WINEXEC
    local soundDir = ".\\csgo\\sounds"

    if type(f) == "table" then
        pcall(function()
            f.cdef [[
                void* GetModuleHandleA(const char*);
                void* GetProcAddress(void*, const char*);
            ]]
        end)
        pcall(function()
            f.cdef [[
                typedef struct { uint32_t attr; uint8_t pad[40]; char nm[260]; char alt[14]; } AWSNDFD;
            ]]
        end)
        local function P(nm, t)
            local h = f.C.GetModuleHandleA("kernel32.dll")
            if h == nil then return nil end
            local p = f.C.GetProcAddress(h, nm)
            return (p ~= nil) and f.cast(t, p) or nil
        end
        FFF = P("FindFirstFileA", "void*(*)(const char*, void*)")
        FNF = P("FindNextFileA", "int(*)(void*, void*)")
        FCL = P("FindClose", "int(*)(void*)")
        GCD = P("GetCurrentDirectoryA", "uint32_t(*)(uint32_t, char*)")
        WINEXEC = P("WinExec", "uint32_t(*)(const char*, uint32_t)")
        pcall(function()
            if GCD then
                local eb = f.new("char[?]", 1024)
                local cwd = f.string(eb, GCD(1024, eb))
                soundDir = cwd:gsub("[\\/]bin[\\/]win64.*$", "\\csgo\\sounds")
            end
        end)
    end

    HS.openSoundDir = function()
        if WINEXEC then
            pcall(function() WINEXEC('explorer.exe "' .. soundDir .. '"', 5) end)
        end
    end

    local function scanSounds()
        local names = {}
        pcall(function()
            if not (f and FFF and FNF and FCL) then return end
            local INVALID = f.cast("void*", f.cast("intptr_t", -1))
            local fd = f.new("AWSNDFD")
            local h = FFF(soundDir .. "\\*.vsnd_c", fd)
            if h ~= INVALID then
                repeat
                    local nm = f.string(fd.nm)
                    if nm:sub(-7):lower() == ".vsnd_c" then
                        names[#names + 1] = nm:sub(1, #nm - 7)
                    end
                until FNF(h, fd) == 0
                FCL(h)
            end
        end)
        table.sort(names)
        local paths = {}
        for i = 1, #names do paths[i] = names[i] end
        if #names == 0 then names[1] = "[ put .vsnd_c in csgo\\sounds ]" end
        return names, paths
    end

    HS.scan = scanSounds
    local SND_NAMES, SND_PATHS = scanSounds()

    local function resolve(cmb)
        return tostring(SND_PATHS[cmb:Get()] or "")
    end

    local function play(path, vol)
        if path == "" then return end
        vol = (tonumber(vol) or 100) / 100
        if vol <= 0 then return end
        pcall(function() client.SetConVar("snd_toolvolume", vol, true) end)
        pcall(function() client.Command("play sounds\\" .. path, true) end)
    end

    -- These will be connected to UI later
    local hsCmbRef, ksCmbRef, hsVolRef, ksVolRef
    HS.setRefs = function(hc, kc, hv, kv)
        hsCmbRef, ksCmbRef, hsVolRef, ksVolRef = hc, kc, hv, kv
    end
    HS.refreshSounds = function(hcw, kcw)
        local n, p = scanSounds()
        SND_PATHS = p
        if hcw then hcw.options = n; hcw.value = 1 end
        if kcw then kcw.options = n; kcw.value = 1 end
    end

    function HS.playHit()
        if hsCmbRef then play(resolve(hsCmbRef), hsVolRef and hsVolRef:Get() or 100) end
    end
    function HS.playKill()
        if ksCmbRef then play(resolve(ksCmbRef), ksVolRef and ksVolRef:Get() or 100) end
    end

    -- Player name / entity helpers
    local bit_ = rawget(_G, "bit")
    local DLL = "client.dll"
    local off = {}
    off.dwEntityList = C.offsets and C.offsets.dwEntityList
    off.dwLocalPlayerController = C.offsets and C.offsets.dwLocalPlayerController
    pcall(function()
        local j = http.Get("https://raw.githubusercontent.com/a2x/cs2-dumper/main/output/client_dll.json")
        if type(j) == "string" and #j > 100 then
            off.m_iszPlayerName = tonumber(j:match('"m_iszPlayerName"%s*:%s*(%d+)')) or nil
            off.m_iPing = tonumber(j:match('"m_iPing"%s*:%s*(%d+)')) or nil
        end
    end)

    local band, rshift = (bit_ or {}).band, (bit_ or {}).rshift

    local function slot(elist, idx)
        if not valid(elist) then return nil end
        local chunk = r_ptr(elist + 8 * rshift(idx, 9) + 16)
        if not valid(chunk) then return nil end
        local e = r_ptr(chunk + 112 * band(idx, 0x1FF))
        if valid(e) and valid(r_ptr(e)) then return e end
        return nil
    end

    local function nameOf(elist, plyslot)
        if not (off.m_iszPlayerName and type(ffi) == "table") then return nil end
        local c = slot(elist, (plyslot or -1) + 1)
        if not valid(c) then return nil end
        local s
        pcall(function() s = ffi.string(ffi.cast("const char*", c + off.m_iszPlayerName)) end)
        if s and #s > 0 and #s < 64 then return s end
        return nil
    end

    local function localCtrlList()
        if not (type(ffi) == "table" and band and off.dwLocalPlayerController and off.dwEntityList) then
            return nil, nil
        end
        local base = mem.GetModuleBase(DLL)
        if not base then return nil, nil end
        local lctrl = r_ptr(base + off.dwLocalPlayerController)
        local elist = r_ptr(base + off.dwEntityList)
        if valid(lctrl) and valid(elist) then return lctrl, elist end
        return nil, nil
    end

    function HS.localInfo()
        local lctrl = localCtrlList()
        if not valid(lctrl) then return nil, nil end
        local nick, ping
        if off.m_iszPlayerName then
            pcall(function()
                local s = ffi.string(ffi.cast("const char*", lctrl + off.m_iszPlayerName))
                if s and #s > 0 and #s < 64 then nick = s end
            end)
        end
        if off.m_iPing then
            pcall(function()
                local p = ffi.cast("int32_t*", lctrl + off.m_iPing)[0]
                if p and p >= 0 and p < 10000 then ping = p end
            end)
        end
        return nick, ping
    end

    function HS.nameBySlot(s)
        local _, elist = localCtrlList()
        if not valid(elist) then return nil end
        return nameOf(elist, s)
    end

    -- Hit/Kill event handling
    local hsOnRef, ksOnRef, hlOnRef, hlHitRef, hlKillRef, hlHurtRef, hlMissRef
    HS.setEventRefs = function(h, k, hl, hh, hk, hu, hm)
        hsOnRef, ksOnRef, hlOnRef, hlHitRef, hlKillRef, hlHurtRef, hlMissRef = h, k, hl, hh, hk, hu, hm
    end

    local MISS_DELAY = 16
    local frameId = 0
    local pend = {}

    local HG = {
        [0] = "body", [1] = "head", [2] = "chest", [3] = "stomach",
        [4] = "l.arm", [5] = "r.arm", [6] = "l.leg", [7] = "r.leg", [10] = "gear"
    }

    local function evHurt(d)
        local dmg = d.dmg_health or 0
        if dmg <= 0 then return end
        local lctrl, elist = localCtrlList()
        local iAttack, iHurt = true, false
        if lctrl then
            iAttack = slot(elist, (d.attacker or -1) + 1) == lctrl
            iHurt = slot(elist, (d.userid or -1) + 1) == lctrl
        end
        if d.userid == d.attacker then iAttack = false end

        local hg = HG[d.hitgroup or 0] or "body"
        if iAttack then
            for i = 1, #pend do
                if not pend[i].hit then pend[i].hit = true; break end
            end
            local dead = (d.health or 1) <= 0
            local who = nameOf(elist, d.userid) or "player"
            if dead then
                if ksOnRef and ksOnRef:Get() then HS.playKill() end
                if hlOnRef and hlOnRef:Get() and hlKillRef and hlKillRef:Get() then
                    M:Hitlog("kill", dmg, "killed " .. who .. " in " .. hg .. " for " .. dmg .. "hp")
                end
            else
                if hsOnRef and hsOnRef:Get() then HS.playHit() end
                if hlOnRef and hlOnRef:Get() and hlHitRef and hlHitRef:Get() then
                    M:Hitlog("hit", dmg, "hit " .. who .. " in " .. hg .. " for " .. dmg .. "hp")
                end
            end
        elseif iHurt then
            local who = nameOf(elist, d.attacker) or "player"
            if hlOnRef and hlOnRef:Get() and hlHurtRef and hlHurtRef:Get() then
                M:Hitlog("hurt", dmg, "hurt by " .. who .. " in " .. hg .. " for " .. dmg .. "hp")
            end
        end
    end

    local function evFire(d)
        if not (hlOnRef and hlOnRef:Get() and hlMissRef and hlMissRef:Get()) then return end
        local adef = C.activeDef()
        if adef and C.isKnife(adef) then return end
        local lctrl, elist = localCtrlList()
        if not lctrl then return end
        if slot(elist, (d.userid or -1) + 1) ~= lctrl then return end
        pend[#pend + 1] = { f = frameId, hit = false }
    end

    function HS.onEvent(ev)
        local name
        pcall(function() name = ev:GetName() end)
        if name == "player_hurt" then
            local d = {}
            pcall(function()
                d.attacker = ev:GetInt("attacker")
                d.userid = ev:GetInt("userid")
                d.health = ev:GetInt("health")
                d.dmg_health = ev:GetInt("dmg_health")
                d.hitgroup = ev:GetInt("hitgroup")
            end)
            evHurt(d)
        elseif name == "weapon_fire" then
            local d = {}
            pcall(function() d.userid = ev:GetInt("userid") end)
            evFire(d)
        end
    end

    function HS.missTick()
        frameId = frameId + 1
        if #pend == 0 then return end
        local keep = {}
        for i = 1, #pend do
            local s = pend[i]
            if frameId - s.f >= MISS_DELAY then
                if not s.hit and hlOnRef and hlOnRef:Get() and hlMissRef and hlMissRef:Get() then
                    M:Hitlog("miss", nil, "missed shot")
                end
            else
                keep[#keep + 1] = s
            end
        end
        pend = keep
    end

    function HS.syncOpts()
        if not (hsOnRef and ksOnRef and hsCmbRef and ksCmbRef and hsVolRef and ksVolRef) then return end
        C.setOpt("hs_on2", hsOnRef:Get())
        C.setOpt("hs_snd2", hsCmbRef:Get())
        C.setOpt("hs_vol2", hsVolRef:Get())
        C.setOpt("ks_on2", ksOnRef:Get())
        C.setOpt("ks_snd2", ksCmbRef:Get())
        C.setOpt("ks_vol2", ksVolRef:Get())
    end
end

-- ============================================================
-- REGION FILTER (RG) - Disabled (safe mode)
-- ============================================================
local RG = { ok = false, ids = {}, names = {}, allow = {}, add = 200, enabled = false, installed = false }

do
    local CITY = {
        ams = "Amsterdam", atl = "Atlanta", bom = "Mumbai", maa = "Chennai",
        can = "Guangzhou", sha = "Shanghai", tyo = "Tokyo", hkg = "Hong Kong",
        seo = "Seoul", sgp = "Singapore", syd = "Sydney", dxb = "Dubai",
        fra = "Frankfurt", lhr = "London", lux = "Luxembourg", par = "Paris",
        mad = "Madrid", sto = "Stockholm", vie = "Vienna", waw = "Warsaw",
        hel = "Helsinki", iad = "Washington", ord = "Chicago", lax = "Los Angeles",
        sea = "Seattle", dfw = "Dallas", okc = "Oklahoma", gru = "Sao Paulo",
        scl = "Santiago", lim = "Lima", bog = "Bogota",
        eat = "Moscow", jhb = "Johannesburg",
    }

    local function decode(id)
        local code = ""
        for sh = 24, 0, -8 do
            local c = floor(id / 2 ^ sh) % 256
            if c >= 32 and c < 127 then code = code .. string.char(c) end
        end
        return (code:gsub("%s", ""))
    end

    function RG.label(id)
        local code = decode(id)
        local city = CITY[code:lower()]
        if city then return city .. " (" .. code .. ")" end
        return code ~= "" and code or ("#" .. id)
    end

    -- Disabled: hardcoded RVAs crash after CS2 update
    print("[mahanmoi] region: auto-install disabled (safe mode)")
    if #RG.names == 0 then RG.names = { "[ join a server, then Refresh ]" } end
end
pcall(function() callbacks.Register("Unload", function() pcall(function() if RG.uninstall then RG.uninstall() end end) end) end)

-- ============================================================
-- NAME CHANGER (NC) - Disabled (safe mode)
-- ============================================================
local NC = { ok = false, installed = false, enabled = false }

do
    local f = ffi
    local DLL = "engine2.dll"

    function NC.setName(s)
        s = tostring(s or "")
        if #s == 0 then NC._buf = nil; return end
        NC._buf = f.new("char[?]", #s + 1, s)
    end

    function NC.steamName()
        if type(f) ~= "table" then return nil end
        if NC._steam then return NC._steam end
        local h = f.C.GetModuleHandleA("steam_api64.dll")
        if h == nil then return nil end
        local getName = f.C.GetProcAddress(h, "SteamAPI_ISteamFriends_GetPersonaName")
        if getName == nil then return nil end
        local accFn
        for _, v in ipairs({
            "SteamAPI_SteamFriends_v017", "SteamAPI_SteamFriends_v018",
            "SteamAPI_SteamFriends_v019", "SteamAPI_SteamFriends_v016",
            "SteamAPI_SteamFriends_v020"
        }) do
            local p = f.C.GetProcAddress(h, v)
            if p ~= nil then accFn = p; break end
        end
        if accFn == nil then return nil end
        local res
        pcall(function()
            local iface = f.cast("void* (*)(void)", accFn)()
            if iface == nil then return end
            local s = f.cast("const char* (*)(void*)", getName)(iface)
            if s ~= nil then
                local str = f.string(s)
                if #str > 0 and #str < 64 then res = str end
            end
        end)
        if res then NC._steam = res end
        return res
    end

    function NC.origName()
        return NC.steamName() or NC._captured or "unknown"
    end

    print("[mahanmoi] namechanger: auto-install disabled (safe mode)")
end
pcall(function() callbacks.Register("Unload", function() pcall(function() if NC.uninstall then NC.uninstall() end end) end) end)

-- ============================================================
-- CHAT PRINT
-- ============================================================
local CHAT = { ok = false }

do
    local f = ffi
    local SIG_CHAT = "4C 89 4C 24 20 53 56 B8 38 10 00 00 E8 ?? ?? ?? ?? 48 2B E0 48 8B 0D ?? ?? ?? ?? 41 8B D8 48 8B F2"
    local fn, flags
    if type(f) == "table" then
        local a = mem.FindPattern("client.dll", SIG_CHAT)
        if a and a ~= 0 then
            fn = f.cast("void(*)(void*, void*, uint32_t, const char*, const char*)", f.cast("void*", a))
            flags = f.new("int[1]", 0x0100)
            CHAT.ok = true
            print("[mahanmoi] chat: hooked print @ " .. string.format("%X", a))
        else
            print("[mahanmoi] chat: print sig not found")
        end
    end
    function CHAT.print(text)
        if not (CHAT.ok and fn) then return false end
        return pcall(function() fn(nil, flags, 0, "%s", tostring(text)) end)
    end
end

-- ============================================================
-- VOTE REVEALER (VR)
-- ============================================================
local VR = { q = {} }

do
    local G, R, W, P = string.char(4), string.char(2), string.char(1), string.char(14)
    local function pfx() return "[" .. P .. "mahanmoi" .. W .. "] " end

    local function startMsg(initiator, target)
        return pfx() .. initiator .. " started a vote to kick " .. target,
               initiator .. " wants to kick " .. target
    end
    local function castMsg(name, yes)
        local yn = yes and (G .. "yes" .. W) or (R .. "no" .. W)
        return pfx() .. name .. " voted " .. yn,
               name .. " voted " .. (yes and "yes" or "no")
    end

    local function push(chat, note, kind)
        VR.q[#VR.q + 1] = { chat = chat, note = note, kind = kind }
    end

    local function pname(slot)
        if not slot or slot < 0 then return "player" end
        local n = HS.nameBySlot(slot)
        if type(n) == "string" and #n > 0 and #n < 64 then return n end
        return "player"
    end

    function VR.flush()
        local total = #VR.q
        if total == 0 then return end
        local q = VR.q; VR.q = {}
        local mode = (VR._mode and VR._mode()) or 3
        for i = 1, total do
            local it = q[i]
            if mode == 1 or mode == 3 then pcall(function() CHAT.print(it.chat) end) end
            if mode == 2 or mode == 3 then pcall(function() M:Notify(it.note, it.kind) end) end
        end
    end

    function VR.test()
        local a, b = startMsg("initiator", "target"); push(a, b, "info")
        local c, d = castMsg("player", true); push(c, d, "success")
        local e, g = castMsg("player", false); push(e, g, "error")
    end

    function VR.onEvent(ev)
        if not (VR._on and VR._on()) then return end
        local name
        pcall(function() name = ev:GetName() end)
        if name == "vote_cast" then
            local opt
            pcall(function() opt = ev:GetInt("vote_option") end)
            if opt == nil or opt < 0 then return end
            local voter
            pcall(function() voter = ev:GetInt("userid") end)
            local yes = (opt == 0)
            local c, n = castMsg(pname(voter), yes)
            push(c, n, yes and "success" or "error")
        elseif name == "vote_started" or name == "vote_begin" then
            local initiator
            pcall(function() initiator = ev:GetInt("entityid") end)
            if not initiator or initiator <= 0 then
                pcall(function() initiator = ev:GetInt("userid") end)
            end
            local tid
            pcall(function()
                local disp = ev:GetString("disp_str")
                if type(disp) == "string" then
                    local m = disp:match(":(%d+):")
                    if m then tid = tonumber(m) end
                end
            end)
            local c, n = startMsg(pname(initiator), tid and pname(tid) or "player")
            push(c, n, "info")
        end
    end
end

-- ============================================================
-- REGISTER GAME EVENTS
-- ============================================================
pcall(function()
    for _, e in ipairs({ "player_hurt", "weapon_fire", "vote_started", "vote_begin", "vote_cast" }) do
        pcall(function() client.AllowListener(e) end)
    end
    callbacks.Register("FireGameEvent", "FemboyTap_Events", function(ev)
        pcall(HS.onEvent, ev)
        pcall(VR.onEvent, ev)
    end)
end)

-- ============================================================
-- SKIN CHANGER UI STATE
-- ============================================================
local weaponLb, skinLb, skinWd
local sWear, sSeed, cbAuto
local modelLb, modelWd, modelPaths
local cbVm, vmX, vmY, vmZ
local hsOn, hsCmb, hsCmbWd, hsVol
local ksOn, ksCmb, ksCmbWd, ksVol
local hlOn, hlMiss, hlHit, hlHurt, hlKill
local wmOn, wmElems, wmPos
local ncOn, ncMode, ncText, ncSpeed
local vrOn, vrMode

local lastModelSel = -1
local curPaints = { 0 }
local lastSel = -1
local lastSig = nil
local lastAutoDef = nil
local lastAuto = false

local function item() return C.items[weaponLb:Get()] end
local function paint() return curPaints[skinLb:Get()] or 0 end
local function settings() return sWear:Get(), floor(sSeed:Get() + 0.5) end

local function applySelected()
    local it = item()
    if not it then return end
    local w, s = settings()
    C.apply(it, paint(), w, s)
end

local function sig()
    local it = item()
    if not it then return "none" end
    local w, s = settings()
    return it.def .. "|" .. paint() .. "|" .. floor(w * 100000) .. "|" .. s
end

local function autoFollow()
    if not cbAuto:Get() then lastAutoDef = nil; return end
    local def = C.activeDef()
    if not def then return end
    if not C.defToItem[def] and C.isKnife(def) and C.knifeDef() then def = C.knifeDef() end
    if def == lastAutoDef then return end
    local idx = C.defToItem[def]
    if not idx then return end
    lastAutoDef = def
    weaponLb:Set(idx)
end

local function autoApply()
    local s = sig()
    if s == lastSig then return end
    lastSig = s
    applySelected()
end

local function syncSkins()
    local sel = weaponLb:Get()
    if sel == lastSel then return end
    lastSel = sel
    local it = C.items[sel]
    if not it then return end
    local names, paints = C.skinList(it.def)
    curPaints = paints
    skinWd.items = names
    skinWd.value = 1
    skinWd.scroll = 0
    local c = C.getCfg(it.def)
    if c then
        sWear:Set(c.wear)
        sSeed:Set(c.seed)
        for i = 2, #paints do
            if paints[i] == c.paint then skinWd.value = i; break end
        end
    end
    lastSig = sig()
end

local function persistOpts()
    local v = cbAuto:Get()
    if v ~= lastAuto then
        lastAuto = v
        C.setOpt("autoFollow", v)
    end
end

local function syncModel()
    if not modelLb then return end
    local sel = modelLb:Get()
    if sel == lastModelSel then return end
    lastModelSel = sel
    C.setLocalModel(modelPaths and modelPaths[sel] or nil)
end

-- ============================================================
-- BUILD UI: SKINS TAB
-- ============================================================
local tab = M:Tab("Skins")

tab:Row()
weaponLb = tab:Section("Weapons"):Listbox("", C.names, "fill", 1)

tab:Col()
local sSec = tab:Section("Skins")
skinLb = sSec:Listbox("", { "[ select a weapon ]" }, "fill", 1)
skinWd = sSec.ws[#sSec.ws]

tab:Col()
local setSec = tab:Section("Settings")
sWear = setSec:Slider("Wear / Float", 0.0001, 0.0, 1.0, 0.001, "%.3f")
sSeed = setSec:Slider("Seed", 0, 0, 1000, 1)
cbAuto = setSec:Checkbox("Auto select weapon", C.getOpt and C.getOpt("autoFollow") or false)

local actSec = tab:Section("Actions")
actSec:Button("Apply Skin", function() applySelected(); lastSig = sig() end)
actSec:Button("Remove", function() C.remove(item()) end)
actSec:Button("Reset All", function() C.resetAll() end)

local cfgSec = tab:Section("Config")
cfgSec:Button("Reset config", function()
    if C.clearConfig then C.clearConfig() end
    pcall(function() M:Notify("config cleared", "info") end)
end)

-- ============================================================
-- BUILD UI: VISUALS TAB
-- ============================================================
local vtab = M:Tab("Visuals")

-- --- Models Sub-tab ---
local submodels = vtab:Sub("Models")
submodels:Row()
local vSec = submodels:Section("List")
local mNames
mNames, modelPaths = C.modelList and C.modelList() or { "[ loading... ]" }, {}
modelLb = vSec:Listbox("", mNames, 300, 1)
modelWd = vSec.ws[#vSec.ws]

submodels:Col()
local vSsec = submodels:Section("Scan")
local cbModelAlt = vSsec:Checkbox("Characters only", C.getModelScanAlt and C.getModelScanAlt() or false)
local inpModelSearch = vSsec:Input("Search name", C.getModelFilter and C.getModelFilter() or "", "filter...")

local function reloadModelList()
    if C.setModelScanAlt then C.setModelScanAlt(cbModelAlt:Get()) end
    if C.setModelFilter then C.setModelFilter(inpModelSearch:Get() or "") end
    local cur = C.getLocalModel and C.getLocalModel()
    if C.refreshModels then
        local n, p = C.refreshModels()
        modelPaths = p or {}
        modelWd.items = n
        modelWd.value = 1
        modelWd.scroll = 0
        if cur then
            for i = 2, #p do
                if p[i] == cur then modelWd.value = i; break end
            end
        end
        lastModelSel = modelWd.value
    end
end

vSsec:Button("Refresh models", reloadModelList)
vSsec:Button("Apply search", reloadModelList)

local vAsec = submodels:Section("Apply")
local TARGET_OPTS = { "Myself", "Teammates", "Enemies", "Selected player" }
local cmbModelTarget = vAsec:Combo("Apply target", TARGET_OPTS, 1)
local cmbModelPlayer = vAsec:Combo("Player", { "(refresh in-game)" }, 1)
local cmbModelPlayerWd = vAsec.ws[#vAsec.ws]
local cbModelPersist = vAsec:Checkbox("Persist", C.getModelPersist and C.getModelPersist() or true)
local playerListData = {}

local function refreshPlayerCombo()
    local players = {}
    pcall(function()
        if C.listPlayers then players = C.listPlayers() or {} end
    end)
    table.sort(players, function(a, b)
        if a.is_local ~= b.is_local then return a.is_local end
        return (a.name or "") < (b.name or "")
    end)
    playerListData = players
    local names = {}
    for i, info in ipairs(players) do
        local label = info.name or ("#" .. tostring(info.idx))
        if info.is_local then label = label .. " [You]" end
        names[#names + 1] = label
    end
    if #names == 0 then names[1] = "(no alive players)" end
    if cmbModelPlayerWd then
        cmbModelPlayerWd.options = names
        if (cmbModelPlayerWd.value or 1) > #names then cmbModelPlayerWd.value = 1 end
    end
end

local function selectedModelPath()
    local sel = modelLb and modelLb:Get() or 1
    if not modelPaths or sel <= 1 then return nil end
    local p = modelPaths[sel]
    if type(p) == "string" and p ~= "" then return p end
    return nil
end

local function selectedPlayerKey()
    local sel = cmbModelPlayer:Get() or 1
    local info = playerListData[sel]
    return info and info.key or nil
end

vAsec:Button("Refresh players", function()
    refreshPlayerCombo()
    pcall(function() M:Notify("players: " .. tostring(#playerListData)) end)
end)
vAsec:Button("Apply model", function()
    local path = selectedModelPath()
    if not path then pcall(function() M:Notify("select a model first") end); return end
    local mode = cmbModelTarget:Get() or 1
    pcall(function() if C.setModelPersist then C.setModelPersist(cbModelPersist:Get()) end end)
    local n = 0
    pcall(function() n = C.applyModelTarget and C.applyModelTarget(mode, selectedPlayerKey(), path) or 0 end)
    pcall(function() M:Notify(string.format("applied to %d player(s)", n)) end)
end)
vAsec:Button("Clear target", function()
    local mode = cmbModelTarget:Get() or 1
    pcall(function()
        if C.clearModelTarget then C.clearModelTarget(mode, selectedPlayerKey()) end
    end)
    pcall(function() M:Notify("cleared") end)
end)
vAsec:Button("Clear all", function()
    pcall(function() if C.clearAllModels then C.clearAllModels() end end)
    lastModelSel = 1
    if modelWd then modelWd.value = 1 end
    pcall(function() M:Notify("all cleared") end)
end)

-- --- Local Sub-tab ---
local sublocal = vtab:Sub("Local")
sublocal:Row()
local localSection = sublocal:Section("Viewmodel Override")
cbVm = localSection:Checkbox("Enabled", C.getOpt and C.getOpt("vm_on") or false)
vmX = localSection:Slider("Offset X", C.getOpt and C.getOpt("vm_x") or 0, -30, 30, 0.1, "%.1f")
vmY = localSection:Slider("Offset Y", C.getOpt and C.getOpt("vm_y") or 0, -30, 30, 0.1, "%.1f")
vmZ = localSection:Slider("Offset Z", C.getOpt and C.getOpt("vm_z") or 0, -30, 30, 0.1, "%.1f")

-- --- Sounds Sub-tab ---
local subsound = vtab:Sub("Sounds")
subsound:Row()

local SND_NAMES_INIT = { "[ scan sounds ]" }
local SND_PATHS_INIT = {}

local hsSec = subsound:Section("Hit sound")
hsOn = hsSec:Checkbox("Enabled", C.getOpt and C.getOpt("hs_on2") or true)
hsCmb = hsSec:Combo("Sound", SND_NAMES_INIT, 1)
hsCmbWd = hsSec.ws[#hsSec.ws]
hsVol = hsSec:Slider("Volume", C.getOpt and C.getOpt("hs_vol2") or 100, 0, 100, 1, "%.0f")

subsound:Col()
local ksSec = subsound:Section("Kill sound")
ksOn = ksSec:Checkbox("Enabled", C.getOpt and C.getOpt("ks_on2") or false)
ksCmb = ksSec:Combo("Sound", SND_NAMES_INIT, 1)
ksCmbWd = ksSec.ws[#ksSec.ws]
ksVol = ksSec:Slider("Volume", C.getOpt and C.getOpt("ks_vol2") or 100, 0, 100, 1, "%.0f")

subsound:Col()
local tSec = subsound:Section("Preview")
tSec:Button("Play hit", function() HS.playHit() end)
tSec:Button("Play kill", function() HS.playKill() end)
tSec:Button("Rescan", function()
    HS.refreshSounds(hsCmbWd, ksCmbWd)
end)
tSec:Button("Open folder", function() HS.openSoundDir() end)

-- Connect sound refs
HS.setRefs(hsCmb, ksCmb, hsVol, ksVol)

-- --- Hitlogs Sub-tab ---
local subhl = vtab:Sub("Hitlogs")
subhl:Row()
local hlSet = subhl:Section("Hitlog")
hlOn = hlSet:Checkbox("Enabled", true)
hlSet:Button("Reset position", function() M:HitlogResetPos() end)

subhl:Col()
local hlTypes = subhl:Section("Types")
hlHit = hlTypes:Checkbox("Hit", true)
hlKill = hlTypes:Checkbox("Kill", true)
hlHurt = hlTypes:Checkbox("Hurt", true)
hlMiss = hlTypes:Checkbox("Miss", false)
hlTypes:Button("Test", function()
    local d = math.random(8, 60)
    M:Hitlog("hit", d, "hit player in head for " .. d .. "hp")
    M:Hitlog("kill", d, "killed player in head for " .. d .. "hp")
    M:Hitlog("miss", nil, "missed shot")
end)

subhl:Col()
local hlCol = subhl:Section("Colors")
hlCol:ColorPicker("Miss", { 235, 90, 90 })
hlCol:ColorPicker("Hit", { 139, 124, 246 })
hlCol:ColorPicker("Hurt", { 245, 170, 70 })
hlCol:ColorPicker("Kill", { 80, 200, 120 })

-- Connect event refs
HS.setEventRefs(hsOn, ksOn, hlOn, hlHit, hlKill, hlHurt, hlMiss)

-- --- Watermark Sub-tab ---
local WM_PARTS = { "cheat", "lua", "user", "nick", "fps", "ping" }
local WM_POS = { "top-left", "top-right", "bottom-left", "bottom-right" }

local subwm = vtab:Sub("Watermark")
subwm:Row()
local wmSec = subwm:Section("Watermark")
wmOn = wmSec:Checkbox("Enabled", true)
wmElems = wmSec:MultiCombo("Elements",
    { "Cheat name", "Lua name", "Username", "Nickname", "FPS", "Ping" }, { 2, 4, 5, 6 })
wmPos = wmSec:Combo("Position", { "Top left", "Top right", "Bottom left", "Bottom right" }, 2)

-- ============================================================
-- BUILD UI: MISC TAB
-- ============================================================
local mtab = M:Tab("Misc")

-- --- Name Changer ---
local subnc = mtab:Sub("Name Changer")
subnc:Row()
local ncSec = subnc:Section("Name Changer")
ncOn = ncSec:Checkbox("Enabled", false)
ncMode = ncSec:Combo("Mode", { "Static", "Spam", "Rainbow" }, 1)
ncText = ncSec:Input("Name", "", "enter name...")
ncSpeed = ncSec:Slider("Spam speed", 5, 1, 30, 1)
ncSec:Button("Apply", function()
    NC.enabled = ncOn:Get()
    if NC.enabled then
        NC.setName(ncText:Get())
        if not NC.ok then
            pcall(function() M:Notify("Name changer hook not installed (safe mode)", "error") end)
        end
    end
end)
ncSec:Button("Reset", function()
    NC.enabled = false
    ncOn:Set(false)
    pcall(function() M:Notify("Name changer disabled") end)
end)

-- --- Vote Revealer ---
local subvr = mtab:Sub("Vote Revealer")
subvr:Row()
local vrSec = subvr:Section("Vote Revealer")
vrOn = vrSec:Checkbox("Enabled", false)
vrMode = vrSec:Combo("Output", { "Chat only", "Notify only", "Both" }, 3)
VR._on = function() return vrOn:Get() end
VR._mode = function() return vrMode:Get() end
vrSec:Button("Test", function()
    VR.test()
    VR.flush()
end)

-- --- Region Filter ---
local subrg = mtab:Sub("Region Filter")
subrg:Row()
local rgSec = subrg:Section("Region Filter")
local rgOn = rgSec:Checkbox("Enabled", false)
local rgCmb = rgSec:Combo("Preferred region", RG.names, 1)
local rgCmbWd = rgSec.ws[#rgSec.ws]
local rgPen = rgSec:Slider("Ping penalty", 200, 50, 500, 10, "%.0f")
local rgMin = rgSec:Checkbox("Minimize preferred ping", false)
rgSec:Button("Refresh regions", function()
    if RG.enumerate then
        pcall(RG.enumerate)
        rgCmbWd.options = RG.names
        rgCmbWd.value = 1
    end
    pcall(function() M:Notify("regions: " .. tostring(#RG.ids)) end)
end)

-- ============================================================
-- CLOCK FOR NAME CHANGER SPAM
-- ============================================================
local ncClock = (function()
    for _, fn in ipairs({
        function() return globals.RealTime() end,
        function() return globals.CurTime() end,
        function() return os.clock() end
    }) do
        local ok, v = pcall(fn)
        if ok and type(v) == "number" then return fn end
    end
    return os.clock
end)()

local ncLastSpam = 0
local ncRainbowPhase = 0

local function tickNameChanger()
    if not NC.enabled or not NC.ok then return end
    local mode = ncMode:Get()
    local now = ncClock()

    if mode == 1 then
        -- Static: already set via button
        return
    elseif mode == 2 then
        -- Spam: change name periodically
        local speed = ncSpeed:Get() or 5
        local interval = 1.0 / speed
        if now - ncLastSpam < interval then return end
        ncLastSpam = now
        local base = ncText:Get() or ""
        if #base == 0 then base = "mahanmoi" end
        -- Append random suffix to bypass spam filter
        local suffix = string.format("%04X", math.random(0, 65535))
        NC.setName(base .. " \n" .. suffix)
    elseif mode == 3 then
        -- Rainbow: slowly change name with color-like pattern
        local speed = ncSpeed:Get() or 5
        local interval = 0.5 / speed
        if now - ncLastSpam < interval then return end
        ncLastSpam = now
        ncRainbowPhase = (ncRainbowPhase + 1) % 256
        local base = ncText:Get() or ""
        if #base == 0 then base = "mahanmoi" end
        local suffix = string.char(ncRainbowPhase) .. string.format("%03X", ncRainbowPhase)
        NC.setName(base .. " " .. suffix)
    end
end

-- ============================================================
-- MAIN PAINT TICK
-- ============================================================
local optSyncTick = 0
local vmSyncTick = 0
local modelSyncTick = 0

local function onPaint()
    -- Skin changer sync
    autoFollow()
    syncSkins()
    autoApply()
    persistOpts()

    -- VM sync
    vmSyncTick = vmSyncTick + 1
    if vmSyncTick >= 5 then
        vmSyncTick = 0
        local on = cbVm:Get()
        local x, y, z = vmX:Get(), vmY:Get(), vmZ:Get()
        VM.set(on, x, y, z)
        -- Persist
        C.setOpt("vm_on", on)
        C.setOpt("vm_x", x)
        C.setOpt("vm_y", y)
        C.setOpt("vm_z", z)
    end

    -- Model sync
    modelSyncTick = modelSyncTick + 1
    if modelSyncTick >= 10 then
        modelSyncTick = 0
        syncModel()
    end

    -- Hit sound opts sync (every 120 frames)
    optSyncTick = optSyncTick + 1
    if optSyncTick >= 120 then
        optSyncTick = 0
        HS.syncOpts()
    end

    -- Miss detection tick
    HS.missTick()

    -- Vote revealer flush
    VR.flush()

    -- Name changer tick
    tickNameChanger()

    -- Player list refresh for model tab
    playerRefreshTick = (playerRefreshTick or 0) + 1
    if playerRefreshTick == 120 or playerRefreshTick % 300 == 0 then
        pcall(refreshPlayerCombo)
    end
end

-- ============================================================
-- WATERMARK RENDER
-- ============================================================
local function renderWatermark()
    if not wmOn:Get() then return end

    local selected = wmElems:Get() -- table of selected indices
    if not selected or #selected == 0 then return end

    local parts = {}
    for _, idx in ipairs(selected) do
        if idx == 1 then parts[#parts + 1] = "mahanmoi" end       -- cheat name
        if idx == 2 then parts[#parts + 1] = "CS2 Lua" end        -- lua name
        if idx == 3 then                                           -- username (steam)
            local sn = NC.steamName()
            if sn then parts[#parts + 1] = sn end
        end
        if idx == 4 then                                           -- nickname (ingame)
            local nick, _ = HS.localInfo()
            if nick then parts[#parts + 1] = nick end
        end
        if idx == 5 then                                           -- fps
            local fps = math.floor(1 / globals.FrameTime())
            parts[#parts + 1] = fps .. "fps"
        end
        if idx == 6 then                                           -- ping
            local _, ping = HS.localInfo()
            if ping then parts[#parts + 1] = ping .. "ms" end
        end
    end

    if #parts == 0 then return end
    local text = table.concat(parts, " | ")

    -- Get screen size
    local sw, sh = client.ScreenSize()
    if not sw or not sh then return end

    local pos = wmPos:Get() or 2
    local x, y
    if pos == 1 then x, y = 10, 10           -- top-left
    elseif pos == 2 then x, y = sw - 10, 10  -- top-right
    elseif pos == 3 then x, y = 10, sh - 10  -- bottom-left
    else x, y = sw - 10, sh - 10 end         -- bottom-right

    local align = (pos == 1 or pos == 3) and 0 or 2 -- 0=left, 2=right

    pcall(function()
        -- Use guilib render if available
        if M and M.DrawText then
            M:DrawText(text, x, y, { 255, 255, 255, 200 }, align)
        end
    end)
end

-- ============================================================
-- REGISTER CALLBACKS
-- ============================================================
-- Try multiple registration methods for compatibility
local registered = false

if client and client.register_callback then
    pcall(function()
        client.register_callback("paint", function()
            onPaint()
            renderWatermark()
        end)
        registered = true
    end)
end

if not registered and client_set_event_callback then
    pcall(function()
        client_set_event_callback("paint_ui", function()
            onPaint()
            renderWatermark()
        end)
        registered = true
    end)
end

if not registered and callbacks and callbacks.Register then
    pcall(function()
        callbacks.Register("Draw", function()
            onPaint()
            renderWatermark()
        end)
        registered = true
    end)
end

if not registered then
    -- Last resort: try paint_ui
    pcall(function()
        client.register_callback("paint_ui", function()
            onPaint()
            renderWatermark()
        end)
        registered = true
    end)
end

if registered then
    print("[mahanmoi] paint callback registered successfully")
else
    print("[mahanmoi] WARNING: could not register paint callback!")
end

-- ============================================================
-- INITIAL SOUND SCAN (delayed)
-- ============================================================
pcall(function()
    -- Delay sound scan to after first frame renders
    local scanDone = false
    local function delayedScan()
        if scanDone then return end
        scanDone = true
        local n, p = HS.scan()
        if hsCmbWd then hsCmbWd.options = n end
        if ksCmbWd then ksCmbWd.options = n end
        -- Restore saved selections
        local hsSnd = C.getOpt and C.getOpt("hs_snd2") or 1
        local ksSnd = C.getOpt and C.getOpt("ks_snd2") or 1
        if hsCmbWd and hsSnd <= #n then hsCmbWd.value = hsSnd end
        if ksCmbWd and ksSnd <= #n then ksCmbWd.value = ksSnd end
    end

    if client_set_event_callback then
        client_set_event_callback("paint_ui", delayedScan)
    elseif client and client.register_callback then
        client.register_callback("paint_ui", delayedScan)
    end
end)

-- ============================================================
-- STARTUP LOG
-- ============================================================
print("============================================")
print("  mahanmoi CS2 Lua - Loaded")
print("  Modules: guilib + changer")
print("  VM: " .. (VM.set and "available" or "disabled"))
print("  Chat: " .. (CHAT.ok and "hooked" or "no hook"))
print("  NC: " .. (NC.ok and "hooked" or "safe mode"))
print("  RG: " .. (RG.ok and "hooked" or "safe mode"))
print("============================================")
