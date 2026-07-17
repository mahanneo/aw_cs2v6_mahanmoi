mhanmoi.lua


local BASE        = rawget(_G, "MAHANMOI_BASE") or "https://raw.githubusercontent.com/mahanneo/aw_cs2v6_mahanmoi/main/"
local GUILIB_URL  = BASE .. "mahanmoi_guilib.lua"
local CHANGER_URL = BASE .. "mahanmoi_changer.lua"

local ffi = rawget(_G, "ffi")

local function r_ptr(a) return tonumber(ffi.cast("uint64_t*", a)[0]) end
local function valid(p) return p ~= nil and p > 0x10000 and p < 0x7FFFFFFFFFFF end

local SIG = {
    vm = "E8 ?? ?? ?? ?? 48 8B CB E8 ?? ?? ?? ?? 84 C0 74 11 F3 0F 10 45 B0",
}

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

local function load(url, cacheFile, name)
    local src, where = fetch(url, cacheFile)
    if not src then print("[mahanmoi] FATAL: cannot load " .. name) return nil end
    local chunk, err = loadstring(src, "=" .. cacheFile)
    if not chunk then print("[mahanmoi] " .. name .. " compile error: " .. tostring(err)) return nil end
    local ok, mod = pcall(chunk)
    if not ok then print("[mahanmoi] " .. name .. " run error: " .. tostring(mod)) return nil end
    print("[mahanmoi] " .. name .. " loaded from " .. tostring(where))
    return mod
end

local M = load(GUILIB_URL, ".\\mahanmoi_lua\\mahanmoi_guilib.lua", "guilib")
if type(M) ~= "table" then return end

local C = load(CHANGER_URL, ".\\mahanmoi_lua\\mahanmoi_changer.lua", "changer")
if type(C) ~= "table" then return end

local floor = math.floor

local VM = {}
local HS = {}

local weaponLb, skinLb, skinWd
local sWear, sSeed, cbAuto
local modelLb, modelWd, modelPaths
local cbVm, vmX, vmY, vmZ
local hsOn, hsCmb, hsCmbWd, hsVol
local ksOn, ksCmb, ksCmbWd, ksVol
local hlOn, hlMiss, hlHit, hlHurt, hlKill
local wmOn, wmElems, wmPos
local rgOn, rgCmb, rgCmbWd, rgPen, rgMin
local ncOn, ncMode, ncSrc, ncText, ncSpeed
local vrOn, vrMode
local SND_NAMES, SND_PATHS

local lastModelSel = -1
local curPaints    = { 0 }
local lastSel      = -1
local lastSig      = nil
local lastAutoDef  = nil
local lastAuto     = false

local function item()     return C.items[weaponLb:Get()] end
local function paint()    return curPaints[skinLb:Get()] or 0 end
local function settings() return sWear:Get(), floor(sSeed:Get() + 0.5) end

local function applySelected()
    local it = item(); if not it then return end
    local w, s = settings()
    C.apply(it, paint(), w, s)
end

local function sig()
    local it = item(); if not it then return "none" end
    local w, s = settings()
    return it.def.."|"..paint().."|"..floor(w * 100000).."|"..s
end

local function autoFollow()
    if not cbAuto:Get() then lastAutoDef = nil; return end
    local def = C.activeDef(); if not def then return end
    if not C.defToItem[def] and C.isKnife(def) and C.knifeDef() then def = C.knifeDef() end
    if def == lastAutoDef then return end
    local idx = C.defToItem[def]; if not idx then return end
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
    local it = C.items[sel]; if not it then return end
    local names, paints = C.skinList(it.def)
    curPaints     = paints
    skinWd.items  = names
    skinWd.value  = 1
    skinWd.scroll = 0
    local c = C.getCfg(it.def)
    if c then
        sWear:Set(c.wear); sSeed:Set(c.seed)
        for i = 2, #paints do
            if paints[i] == c.paint then skinWd.value = i; break end
        end
    end
    lastSig = sig()
end

local function persistOpts()
    local v = cbAuto:Get()
    if v ~= lastAuto then lastAuto = v; C.setOpt("autoFollow", v) end
end

local function syncModel()
    if not modelLb then return end
    local sel = modelLb:Get()
    if sel == lastModelSel then return end
    lastModelSel = sel
    C.setLocalModel(modelPaths and modelPaths[sel] or nil)
end

do
    local page, match, origRel, ok = nil, nil, nil, false

    local function r_i32(a) return ffi.cast("int32_t*",  a)[0] end
    local function w_u8 (a, v) ffi.cast("uint8_t*", a)[0] = v end
    local function w_i32(a, v) ffi.cast("int32_t*", a)[0] = v end
    local function w_f32(a, v) ffi.cast("float*",   a)[0] = v end

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

        local b = { 0x53, 0x56, 0x48,0x83,0xEC,0x28, 0x48,0x89,0xD6, 0x48,0xB8 }
        for _, v in ipairs(le64(orig)) do b[#b + 1] = v end
        for _, v in ipairs({ 0xFF,0xD0, 0x48,0xBB }) do b[#b + 1] = v end
        for _, v in ipairs(le64(page)) do b[#b + 1] = v end
        for _, v in ipairs({
            0x8B,0x0B, 0x85,0xC9, 0x74,0x2B,
            0xF3,0x0F,0x10,0x4B,0x04, 0xF3,0x0F,0x58,0x0E, 0xF3,0x0F,0x11,0x0E,
            0xF3,0x0F,0x10,0x4B,0x08, 0xF3,0x0F,0x58,0x4E,0x04, 0xF3,0x0F,0x11,0x4E,0x04,
            0xF3,0x0F,0x10,0x4B,0x0C, 0xF3,0x0F,0x58,0x4E,0x08, 0xF3,0x0F,0x11,0x4E,0x08,
            0x48,0x83,0xC4,0x28, 0x5E, 0x5B, 0xC3,
        }) do b[#b + 1] = v end
        for i = 0, #b - 1 do w_u8(code + i, b[i + 1]) end
        w_i32(page, 0); w_f32(page + 4, 0); w_f32(page + 8, 0); w_f32(page + 12, 0)

        local rel = code - (match + 5)
        if rel < -2147483648 or rel > 2147483647 then print("[mahanmoi] VM: rel32 overflow"); return false end
        origRel = r_i32(match + 1)
        local old = ffi.new("uint32_t[1]")
        ffi.C.VirtualProtect(ffi.cast("void*", match), 5, 0x40, old)
        w_i32(match + 1, rel)
        ffi.C.VirtualProtect(ffi.cast("void*", match), 5, old[0], old)
        pcall(function() ffi.C.FlushInstructionCache(ffi.C.GetCurrentProcess(), ffi.cast("void*", match), 5) end)
        print("[mahanmoi] VM: installed")
        return true
    end

    -- Disabled on load: code patch crashes after CS2 update (execute AV on unmapped RIP)
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

local lastVm = nil
local function syncVm()
    local on = cbVm:Get()
    local x, y, z = vmX:Get(), vmY:Get(), vmZ:Get()
    VM.set(on, x, y, z)
    local s = (on and "1" or "0") .. ":" .. x .. ":" .. y .. ":" .. z
    if s ~= lastVm then
        lastVm = s
        C.setOpt("vm_on", on)
        C.setOpt("vm_x", x); C.setOpt("vm_y", y); C.setOpt("vm_z", z)
    end
end

do
    local f = ffi
    local FFF, FNF, FCL, GCD, WINEXEC
    local soundDir = ".\\csgo\\sounds"
    if type(f) == "table" then
        pcall(function() f.cdef [[ void* GetModuleHandleA(const char*); void* GetProcAddress(void*, const char*); ]] end)
        pcall(function() f.cdef [[ typedef struct { uint32_t attr; uint8_t pad[40]; char nm[260]; char alt[14]; } AWSNDFD; ]] end)
        local function P(nm, t)
            local h = f.C.GetModuleHandleA("kernel32.dll"); if h == nil then return nil end
            local p = f.C.GetProcAddress(h, nm); return (p ~= nil) and f.cast(t, p) or nil
        end
        FFF = P("FindFirstFileA",       "void*(*)(const char*, void*)")
        FNF = P("FindNextFileA",        "int(*)(void*, void*)")
        FCL = P("FindClose",            "int(*)(void*)")
        GCD = P("GetCurrentDirectoryA", "uint32_t(*)(uint32_t, char*)")
        WINEXEC = P("WinExec",          "uint32_t(*)(const char*, uint32_t)")
        pcall(function()
            if GCD then
                local eb = f.new("char[?]", 1024)
                local cwd = f.string(eb, GCD(1024, eb))
                soundDir = cwd:gsub("[\\/]bin[\\/]win64.*$", "\\csgo\\sounds")
            end
        end)
    end
    HS.openSoundDir = function()
        if WINEXEC then pcall(function() WINEXEC('explorer.exe "' .. soundDir .. '"', 5) end) end
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
                    if nm:sub(-7):lower() == ".vsnd_c" then names[#names + 1] = nm:sub(1, #nm - 7) end
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
    SND_NAMES, SND_PATHS = scanSounds()

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

    function HS.playHit()  play(resolve(hsCmb), hsVol:Get()) end
    function HS.playKill() play(resolve(ksCmb), ksVol:Get()) end

    local bit_ = rawget(_G, "bit")
    local DLL  = "client.dll"
    local off  = {}
    off.dwEntityList            = C.offsets and C.offsets.dwEntityList
    off.dwLocalPlayerController = C.offsets and C.offsets.dwLocalPlayerController
    pcall(function()
        local j = http.Get("https://raw.githubusercontent.com/a2x/cs2-dumper/main/output/client_dll.json")
        off.m_iszPlayerName = j and tonumber(j:match('"m_iszPlayerName"%s*:%s*(%d+)')) or nil
        off.m_iPing         = j and tonumber(j:match('"m_iPing"%s*:%s*(%d+)')) or nil
    end) 

    local band, rshift = (bit_ or {}).band, (bit_ or {}).rshift
    local function slot(elist, idx)
        if not valid(elist) then return nil end
        local chunk = r_ptr(elist + 8 * rshift(idx, 9) + 16); if not valid(chunk) then return nil end
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
        if not (type(ffi) == "table" and band and off.dwLocalPlayerController and off.dwEntityList) then return nil, nil end
        local base = mem.GetModuleBase(DLL); if not base then return nil, nil end
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

    local MISS_DELAY = 16
    local frameId = 0
    local pend = {}

    local HG = { [0] = "body", [1] = "head", [2] = "chest", [3] = "stomach",
                 [4] = "l.arm", [5] = "r.arm", [6] = "l.leg", [7] = "r.leg", [10] = "gear" }

    local function evHurt(d)
        local dmg = d.dmg_health or 0
        if dmg <= 0 then return end
        local lctrl, elist = localCtrlList()
        local iAttack, iHurt = true, false
        if lctrl then
            iAttack = slot(elist, (d.attacker or -1) + 1) == lctrl
            iHurt   = slot(elist, (d.userid   or -1) + 1) == lctrl
        end
        if d.userid == d.attacker then iAttack = false end

        local hg = HG[d.hitgroup or 0] or "body"
        if iAttack then
            for i = 1, #pend do if not pend[i].hit then pend[i].hit = true; break end end
            local dead = (d.health or 1) <= 0
            local who  = nameOf(elist, d.userid) or "player"
            if dead then
                if ksOn:Get() then HS.playKill() end
                if hlOn:Get() and hlKill:Get() then
                    M:Hitlog("kill", dmg, "killed " .. who .. " in " .. hg .. " for " .. dmg .. "hp")
                end
            else
                if hsOn:Get() then HS.playHit() end
                if hlOn:Get() and hlHit:Get() then
                    M:Hitlog("hit", dmg, "hit " .. who .. " in " .. hg .. " for " .. dmg .. "hp")
                end
            end
        elseif iHurt then
            local who = nameOf(elist, d.attacker) or "player"
            if hlOn:Get() and hlHurt:Get() then
                M:Hitlog("hurt", dmg, "hurt by " .. who .. " in " .. hg .. " for " .. dmg .. "hp")
            end
        end
    end

    local function evFire(d)
        if not (hlOn:Get() and hlMiss:Get()) then return end
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
                d.attacker   = ev:GetInt("attacker")
                d.userid     = ev:GetInt("userid")
                d.health     = ev:GetInt("health")
                d.dmg_health = ev:GetInt("dmg_health")
                d.hitgroup   = ev:GetInt("hitgroup")
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
                if not s.hit and hlOn:Get() and hlMiss:Get() then M:Hitlog("miss", nil, "missed shot") end
            else
                keep[#keep + 1] = s
            end
        end
        pend = keep
    end

    local lastHs = nil
    function HS.sync()
        local s = table.concat({ hsOn:Get() and 1 or 0, hsCmb:Get(), hsVol:Get(),
                                 ksOn:Get() and 1 or 0, ksCmb:Get(), ksVol:Get() }, ":")
        if s == lastHs then return end
        lastHs = s
        C.setOpt("hs_on2", hsOn:Get()); C.setOpt("hs_snd2", hsCmb:Get()); C.setOpt("hs_vol2", hsVol:Get())
        C.setOpt("ks_on2", ksOn:Get()); C.setOpt("ks_snd2", ksCmb:Get()); C.setOpt("ks_vol2", ksVol:Get())
    end
end

local RG = { ok = false, ids = {}, names = {}, allow = {}, add = 200, enabled = false, installed = false }
do
    local f = ffi
    local CITY = {
        ams = "Amsterdam", atl = "Atlanta", bom = "Mumbai", maa = "Chennai",
        can = "Guangzhou", sha = "Shanghai", tyo = "Tokyo", hkg = "Hong Kong",
        seo = "Seoul", sgp = "Singapore", syd = "Sydney", dxb = "Dubai",
        fra = "Frankfurt", lhr = "London", lux = "Luxembourg", par = "Paris",
        mad = "Madrid", sto = "Stockholm", vie = "Vienna", waw = "Warsaw",
        hel = "Helsinki", iad = "Washington", ord = "Chicago", lax = "Los Angeles",
        sea = "Seattle", dfw = "Dallas", okc = "Oklahoma", gru = "Sao Paulo",
        sao = "Sao Paulo", scl = "Santiago", lim = "Lima", bog = "Bogota",
        eat = "Moscow", sto2 = "Stockholm", jhb = "Johannesburg", pwj = "Tianjin",
        pwg = "Guangzhou", pwz = "Chengdu", tsn = "Tianjin", cpt = "Cape Town",
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

    if type(f) == "table" then
        local IDX_COUNT, IDX_LIST = 10, 11
        local TARGETS = {
            { rva = 0x13F050, steal = 17 },             -- GetPingToDataCenter (vtable idx 8)
            { rva = 0x13EBB0, steal = 15, call = 10 },  -- GetDirectPingToPOP  (vtable idx 9)
        }

        local DLL  = "steamnetworkingsockets.dll"
        local ACCS = { "SteamNetworkingUtils_LibV4", "SteamNetworkingUtils_LibV3", "SteamNetworkingUtils_LibV2" }

        local hmod = f.C.GetModuleHandleA(DLL)
        local base = hmod ~= nil and tonumber(f.cast("uintptr_t", hmod)) or nil
        local modSize = 0
        if base then
            -- PE SizeOfImage at OptionalHeader+0x38 (PE32+), e_lfanew at 0x3C
            pcall(function()
                local e_lfanew = f.cast("uint32_t*", base + 0x3C)[0]
                modSize = tonumber(f.cast("uint32_t*", base + e_lfanew + 0x50)[0]) or 0
            end)
        end

        local utils, vtbl, getCount, getList
        if hmod ~= nil then
            local acc
            for _, nm in ipairs(ACCS) do
                local p = f.C.GetProcAddress(hmod, nm)
                if p ~= nil then acc = p; break end
            end
            if acc ~= nil then
                local ok2, u = pcall(function() return f.cast("void*(*)(void)", acc)() end)
                if ok2 and u ~= nil then utils = u end
            end
            if utils ~= nil then
                vtbl = f.cast("void***", utils)[0]
                if vtbl ~= nil then
                    getCount = f.cast("int(*)(void*)", vtbl[IDX_COUNT])
                    getList  = f.cast("int(*)(void*, uint32_t*, int)", vtbl[IDX_LIST])
                end
            end
        end

        local w_u8  = function(a, v) f.cast("uint8_t*",  a)[0] = v end
        local w_i32 = function(a, v) f.cast("int32_t*",  a)[0] = v end
        local le64  = function(a, v) f.cast("uint64_t*", a)[0] = f.cast("uint64_t", v) end

        local function alloc_near(target)
            local gran = 0x10000
            local b = target - (target % gran)
            for i = 1, 0x8000 do
                local lo = b - i * gran
                if lo > 0x10000 then
                    local p = f.C.VirtualAlloc(f.cast("void*", lo), 64, 0x3000, 0x40)
                    if p ~= nil then return p end
                end
                local p2 = f.C.VirtualAlloc(f.cast("void*", b + i * gran), 64, 0x3000, 0x40)
                if p2 ~= nil then return p2 end
            end
            return nil
        end

        local hooks, keeps = {}, {}

        local function hookFunc(rva, steal, callOff)
            if not base or modSize <= 0 or rva <= 0 or (rva + steal + 16) > modSize then
                return nil
            end
            local T  = base + rva
            local b0 = f.cast("uint8_t*", T)
            -- skip if target looks like padding / empty (outdated RVA after update)
            if b0[0] == 0x00 or b0[0] == 0xCC then return nil end
            local p  = alloc_near(T); if p == nil then return nil end
            local TR = tonumber(f.cast("uintptr_t", p))

            local saved = {}
            for i = 0, steal - 1 do saved[i] = b0[i]; w_u8(TR + i, b0[i]) end

            if callOff then
                local relOrig    = f.cast("int32_t*", T + callOff + 1)[0]
                local callTarget = (T + callOff + 5) + relOrig
                local newRel     = callTarget - (TR + callOff + 5)
                if newRel < -2147483648 or newRel > 2147483647 then return nil end
                w_i32(TR + callOff + 1, newRel)
            end

            w_u8(TR + steal, 0xFF); w_u8(TR + steal + 1, 0x25); w_i32(TR + steal + 2, 0)
            le64(TR + steal + 6, T + steal)

            local orig = f.cast("int(*)(void*, uint32_t, uint32_t*)", f.cast("void*", TR))
            local cb = f.cast("int(*)(void*, uint32_t, uint32_t*)", function(self, popid, via)
                local r = orig(self, popid, via)
                if RG.enabled and r >= 0 and next(RG.allow) ~= nil then
                    if RG.allow[tonumber(popid)] then
                        if RG.minimize then return 1 end
                    else
                        return r + RG.add
                    end
                end
                return r
            end)
            keeps[#keeps + 1] = cb

            local old = f.new("uint32_t[1]")
            if f.C.VirtualProtect(f.cast("void*", T), steal, 0x40, old) == 0 then return nil end
            w_u8(T, 0xFF); w_u8(T + 1, 0x25); w_i32(T + 2, 0); le64(T + 6, tonumber(f.cast("uintptr_t", cb)))
            for i = 14, steal - 1 do w_u8(T + i, 0x90) end
            f.C.VirtualProtect(f.cast("void*", T), steal, old[0], old)
            pcall(function() f.C.FlushInstructionCache(f.C.GetCurrentProcess(), f.cast("void*", T), steal) end)

            hooks[#hooks + 1] = { T = T, saved = saved, steal = steal }
            return orig
        end

        local function install()
            if not base then return false end
            local any = false
            for _, t in ipairs(TARGETS) do
                local o = nil
                pcall(function() o = hookFunc(t.rva, t.steal, t.call) end)
                if o then
                    any = true
                    if not RG.ping then RG.ping = o end
                end
            end
            RG.installed = any
            return any
        end

        function RG.uninstall()
            for _, h in ipairs(hooks) do
                pcall(function()
                    local old = f.new("uint32_t[1]")
                    f.C.VirtualProtect(f.cast("void*", h.T), h.steal, 0x40, old)
                    for i = 0, h.steal - 1 do w_u8(h.T + i, h.saved[i]) end
                    f.C.VirtualProtect(f.cast("void*", h.T), h.steal, old[0], old)
                    f.C.FlushInstructionCache(f.C.GetCurrentProcess(), f.cast("void*", h.T), h.steal)
                end)
            end
            RG.installed = false
        end

        local function pingOf(id)
            if not RG.ping then return nil end
            local r
            pcall(function()
                local via = f.new("uint32_t[1]")
                r = RG.ping(nil, id, via)
            end)
            if r and r >= 0 and r < 100000 then return r end
            return nil
        end

        local function enumerate()
            if utils == nil or not getCount or not getList then return end
            local n = getCount(utils)
            if n <= 0 then return end
            if n > 256 then n = 256 end
            local buf = f.new("uint32_t[?]", n)
            local got = getList(utils, buf, n)
            if got < 0 then return end
            if got > n then got = n end
            local all, hasPing = {}, {}
            for i = 0, got - 1 do
                local id    = tonumber(buf[i])
                local known = CITY[decode(id):lower()] ~= nil
                local ping  = pingOf(id)
                local nm    = RG.label(id) .. (ping and ("  " .. ping .. "ms") or "")
                local e = { id = id, name = nm, known = known, ping = ping }
                all[#all + 1] = e
                if ping ~= nil and ping <= 250 then hasPing[#hasPing + 1] = e end
            end
            local use = (#hasPing > 0) and hasPing or all
            table.sort(use, function(a, b)
                if (a.ping ~= nil) ~= (b.ping ~= nil) then return a.ping ~= nil end
                if a.ping and b.ping and a.ping ~= b.ping then return a.ping < b.ping end
                if a.known ~= b.known then return a.known end
                return a.name < b.name
            end)
            local ids, names = {}, {}
            for _, e in ipairs(use) do ids[#ids + 1] = e.id; names[#names + 1] = e.name end
            if #ids > 0 then RG.ids = ids; RG.names = names end
        end
        RG.enumerate = enumerate

        local okI = false
        -- Disabled: hardcoded steamnetworkingsockets RVAs cause execute AV on inject after update
        -- pcall(function() okI = install() end)
        -- if utils ~= nil and vtbl ~= nil then pcall(enumerate) end
        if utils ~= nil and vtbl ~= nil then pcall(enumerate) end
        RG.ok = okI
        if okI then print("[mahanmoi] region: hooked " .. #hooks .. " fns (" .. #RG.ids .. " pops)")
        else            print("[mahanmoi] region: auto-install disabled (safe mode)") end
    end

    if #RG.names == 0 then RG.names = { "[ join a server, then Refresh ]" } end
end
pcall(function() callbacks.Register("Unload", function() pcall(RG.uninstall) end) end)

---------------------------------------------------------
-- MAHANMOI Name Changer (Advanced Engine Based)
---------------------------------------------------------
ffi.cdef[[
    void* GetModuleHandleA(const char* lpModuleName);
]]
local NULL = 0x0
local ENGINE2_DLL_NAME = "engine2.dll"
local cVTable_Address_VEngineCvar007_offset = NULL
local cResolveConVar_offset = NULL
local cVTable_FindConVar_offset = 0xB
local cConVarFlags = 0x30
local FCVAR_DEVELOPMENTONLY = 0x2
local FCVAR_USERINFO = 0x200
local function getOffsetFromPattern(cDllName, cPattern, cPatternOffset, cInstrSize)
    local cPatternLocation = mem.FindPattern(cDllName, cPattern)
    local cRelativeAddress = ffi.cast("int32_t*", cPatternLocation + cPatternOffset)[0x0]
    return tonumber(cPatternLocation + cRelativeAddress + cInstrSize) - tonumber(ffi.cast("uintptr_t", ffi.C.GetModuleHandleA(cDllName)))
end
cVTable_Address_VEngineCvar007_offset = getOffsetFromPattern(ENGINE2_DLL_NAME, "48 8B 0D ?? ?? ?? ?? 48 8B 16 48 89 7C 24 ?? 4C 89 4C 24 ??", 3, 7)
cResolveConVar_offset = getOffsetFromPattern(ENGINE2_DLL_NAME, "48 8B D3 E8 ?? ?? ?? ?? 48 8B 44 24", 4, 8)
local function patchConVar(cConVarName)
    local engine2_base_address = tonumber(ffi.cast("uintptr_t", ffi.C.GetModuleHandleA(ENGINE2_DLL_NAME)))
    if engine2_base_address == nil or engine2_base_address == NULL then return end
    local vTable_engine_address = tonumber(ffi.cast("uintptr_t*", engine2_base_address + cVTable_Address_VEngineCvar007_offset)[0x0])
    local vTable_engine_table = tonumber(ffi.cast("uintptr_t*", vTable_engine_address)[0x0])
    local pFindConVarFunction_address = ffi.cast("uintptr_t*", vTable_engine_table)[cVTable_FindConVar_offset]
    local pFindConVarFunction = ffi.cast("void* (*)(void*, void*, const char*, int)", pFindConVarFunction_address)
    local pFindConVarOutput = ffi.new("void*[1]")
    local pFindConVarName = ffi.new("char[?]", cConVarName:len() + 0x1, cConVarName)
    local pFindConVarHandle_address = pFindConVarFunction(ffi.cast("void*", vTable_engine_address), pFindConVarOutput, pFindConVarName, 0x0)
    local pFindConVarHandle = ffi.cast("void*", pFindConVarHandle_address)
    local pResolveConVarFunction = ffi.cast("void* (*)(int64_t*, int32_t, int16_t)", tonumber(ffi.cast("uintptr_t", engine2_base_address + cResolveConVar_offset)))
    local pResolveConVarOutput = ffi.new("int64_t[0x2]")
    local pResolveConVarResult = pResolveConVarFunction(pResolveConVarOutput, ffi.cast("int32_t", pFindConVarOutput[0x0]), 0x0)
    local pCurrentConVarStruct_address = tonumber(pResolveConVarOutput[0x1])
    local pCurrentConVarFlags = ffi.cast("uintptr_t*", pCurrentConVarStruct_address + cConVarFlags)
    pCurrentConVarFlags[0x0] = bit.band(pCurrentConVarFlags[0x0], bit.bnot(FCVAR_DEVELOPMENTONLY))
    pCurrentConVarFlags[0x0] = bit.bor(pCurrentConVarFlags[0x0], FCVAR_USERINFO)
end
local Aimware_Misc_Features_ref = gui.Reference("Miscellaneous", "Features")
local NameChanger_Combobox_ref = gui.Combobox(Aimware_Misc_Features_ref, "mahanmoi_nc_listbox", "Mahanmoi Name-Changer", "Disabled", "Fake name", "Animated", "Static", "Static | Radar", "Minecraft enchantment | Radar", "Radar Exploit")
local NameChanger_Clantag_Editbox_ref = gui.Editbox(Aimware_Misc_Features_ref, "mahanmoi_nc_clantag", "")
local NameChanger_Clantag_Speed_Slider_ref = gui.Slider(Aimware_Misc_Features_ref, "mahanmoi_nc_speed", "Animation speed", 0.3, 0, 1, 0.1)
local function GetMagicSymbols(iCount) local magicSymbols = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz" local result = "" for i = 1, iCount do local magicIndex = math.random(1, magicSymbols:len()) result = result .. magicSymbols:sub(magicIndex, magicIndex) end return result end
local cOldRealName = " "
local function SaveRealPlayerName(cRealPlayerName) cOldRealName = cRealPlayerName end
local function GetRealPlayerName() return cOldRealName end
local function SetUserNameAndClantag(cClantagWithName) client.Command('name ' .. '"' .. cClantagWithName .. '"', true) client.Command('setinfo name ' .. '"' .. cClantagWithName .. '"', true) end
local function DisabledClantagHandler() SetUserNameAndClantag(cOldRealName) end
local function StaticClantagHandler() SetUserNameAndClantag(NameChanger_Clantag_Editbox_ref:GetString() .. " " .. cOldRealName) end
local function FakeNameHandler() SetUserNameAndClantag(NameChanger_Clantag_Editbox_ref:GetString()) end
local cAnimatedName = " " local iAnimatedNameCurrentIndex = -1 local bReversed = false local cLastTimeChanged_AnimTag = -1
local function AnimatedNameHandler() if globals.CurTime() < cLastTimeChanged_AnimTag then cLastTimeChanged_AnimTag = globals.CurTime() end if (globals.CurTime() - cLastTimeChanged_AnimTag) < NameChanger_Clantag_Speed_Slider_ref:GetValue() then return end cLastTimeChanged_AnimTag = globals.CurTime() local ExitBoxStr_len = NameChanger_Clantag_Editbox_ref:GetString():len() if bReversed then iAnimatedNameCurrentIndex = iAnimatedNameCurrentIndex + 1 if iAnimatedNameCurrentIndex > ExitBoxStr_len then bReversed = false; iAnimatedNameCurrentIndex = ExitBoxStr_len end else iAnimatedNameCurrentIndex = iAnimatedNameCurrentIndex - 1 if iAnimatedNameCurrentIndex < 0 then bReversed = true; iAnimatedNameCurrentIndex = 0 end end local cCurrentAnimatedNameTag = cAnimatedName:sub(1, iAnimatedNameCurrentIndex) local cAdditionalSpaces = ("\xC2\xA0\xC2\xA0"):rep(ExitBoxStr_len - iAnimatedNameCurrentIndex) SetUserNameAndClantag(cCurrentAnimatedNameTag .. cAdditionalSpaces .. " " .. cOldRealName) end
local fakeChanged = false
local function StaticRadarClantagHandler() if fakeChanged then SetUserNameAndClantag(NameChanger_Clantag_Editbox_ref:GetString() .. " " .. cOldRealName) fakeChanged = false else SetUserNameAndClantag(NameChanger_Clantag_Editbox_ref:GetString() .. " " .. cOldRealName.. "\xC2\xA0") fakeChanged = true end end
local function MinecraftEnchantmentClantagHandler() SetUserNameAndClantag(GetMagicSymbols(math.random(10, 16))) end
local function RadarExploitClantagHandler() if fakeChanged then SetUserNameAndClantag(cOldRealName) fakeChanged = false else SetUserNameAndClantag(cOldRealName .. "\xC2\xA0") fakeChanged = true end end
local cInitTime = globals.CurTime() local bForceExit = false local bNameWasSaved = false local bNameWasChanged = false local cLastTimeChanged_logic = -1
local function NameChangerLogicHandler() if bForceExit then return end if globals.CurTime() < cLastTimeChanged_logic then cLastTimeChanged_logic = globals.CurTime() end if globals.CurTime() < cInitTime then cInitTime = globals.CurTime() end if engine.GetServerIP() == nil then cInitTime = globals.CurTime(); bNameWasSaved = false; return end if engine.GetMapName() == nil or engine.GetMapName() == "" then cInitTime = globals.CurTime(); bNameWasSaved = false; return end local pLocalPLayerEnt = entities.GetLocalPlayer() if pLocalPLayerEnt == nil then cInitTime = globals.CurTime(); bNameWasSaved = false; return end if (globals.CurTime() - cInitTime) < 1.0 then bNameWasSaved = false; return end if bNameWasSaved == false then if pLocalPLayerEnt:IsPlayer() == false then return end print("[mahanmoi] Name changer activated successfully") SaveRealPlayerName(pLocalPLayerEnt:GetName()) bNameWasSaved = true patchConVar("name") end if (globals.CurTime() - cLastTimeChanged_logic) > 0.03 then cLastTimeChanged_logic = globals.CurTime() local ComboboxValue = NameChanger_Combobox_ref:GetValue() if ComboboxValue == 0 and bNameWasChanged == true then DisabledClantagHandler(); bNameWasChanged = false end if ComboboxValue == 1 then FakeNameHandler(); bNameWasChanged = true end if ComboboxValue == 2 then if NameChanger_Clantag_Editbox_ref:GetString() ~= cAnimatedName then cAnimatedName = NameChanger_Clantag_Editbox_ref:GetString() iAnimatedNameCurrentIndex = NameChanger_Clantag_Editbox_ref:GetString():len() bReversed = false end AnimatedNameHandler(); bNameWasChanged = true end if ComboboxValue == 3 then StaticClantagHandler(); bNameWasChanged = true end if ComboboxValue == 4 then StaticRadarClantagHandler(); bNameWasChanged = true end if ComboboxValue == 5 then MinecraftEnchantmentClantagHandler(); bNameWasChanged = true end if ComboboxValue == 6 then RadarExploitClantagHandler(); bNameWasChanged = true end end end
local cLastTimeChanged_menu = -1
local function NameChangerMenuHandler() if bForceExit then return end if globals.CurTime() < cLastTimeChanged_menu then cLastTimeChanged_menu = globals.CurTime() end if (globals.CurTime() - cLastTimeChanged_menu) > 0.03 then cLastTimeChanged_menu = globals.CurTime() local ComboboxValue = NameChanger_Combobox_ref:GetValue() if ComboboxValue == 0 then NameChanger_Clantag_Editbox_ref:SetInvisible(true); NameChanger_Clantag_Speed_Slider_ref:SetInvisible(true) end if ComboboxValue == 1 then NameChanger_Clantag_Editbox_ref:SetInvisible(false); NameChanger_Clantag_Speed_Slider_ref:SetInvisible(true) end if ComboboxValue == 2 then NameChanger_Clantag_Editbox_ref:SetInvisible(false); NameChanger_Clantag_Speed_Slider_ref:SetInvisible(false) end if ComboboxValue == 3 then NameChanger_Clantag_Editbox_ref:SetInvisible(false); NameChanger_Clantag_Speed_Slider_ref:SetInvisible(true) end if ComboboxValue == 4 then NameChanger_Clantag_Editbox_ref:SetInvisible(false); NameChanger_Clantag_Speed_Slider_ref:SetInvisible(true) end if ComboboxValue == 5 then NameChanger_Clantag_Editbox_ref:SetInvisible(true); NameChanger_Clantag_Speed_Slider_ref:SetInvisible(true) end if ComboboxValue == 6 then NameChanger_Clantag_Editbox_ref:SetInvisible(true); NameChanger_Clantag_Speed_Slider_ref:SetInvisible(true) end end end
callbacks.Register("Draw", NameChangerLogicHandler)
callbacks.Register("Draw", NameChangerMenuHandler)
callbacks.Register("Unload", function() bForceExit = true if bNameWasSaved and NameChanger_Combobox_ref:GetValue() ~= 0 then if entities.GetLocalPlayer() == nil then return end DisabledClantagHandler() end end)

---------------------------------------------------------
-- MAHANMOI Reconnect Bypass (Firewall Method)
---------------------------------------------------------
local mahanmoi_rb_DEBUG = false
ffi.cdef[[ int RegOpenKeyExA(void* hKey, const char* lpSubKey, unsigned long ulOptions, unsigned long samDesired, void** phkResult); int RegQueryValueExA(void* hKey, const char* lpValueName, unsigned long* lpReserved, unsigned long* lpType, unsigned char* lpData, unsigned long* lpcbData); int RegCloseKey(void* hKey); void* ShellExecuteA(void* hwnd, const char* lpOperation, const char* lpFile, const char* lpParameters, const char* lpDirectory, int nShowCmd); void* CreateFileA(const char* lpFileName, unsigned long dwDesiredAccess, unsigned long dwShareMode, void* lpSecurityAttributes, unsigned long dwCreationDisposition, unsigned long dwFlagsAndAttributes, void* hTemplateFile); int CloseHandle(void* hObject); ]]
local SW_HIDE = 0x0 local SW_SHOW = 0x5 local SW_POWERSHELL = mahanmoi_rb_DEBUG and SW_SHOW or SW_HIDE local ERROR_SUCCESS = 0x0 local HKEY_CURRENT_USER = ffi.cast("void*", 0x80000001) local HKEY_STEAM_SUB_PATH = "Software\\Valve\\Steam" local KEY_QUERY_VALUE = 0x0001 local GENERIC_ALL = 0x10000000 local CREATE_ALWAYS = 0x2 local FILE_ATTRIBUTE_NORMAL = 0x80 local INVALID_HANDLE_VALUE = ffi.cast("void*", -0x1)
local mahanmoi_rb_Advapi32 = ffi.load("Advapi32") local mahanmoi_rb_Shell32 = ffi.load("Shell32") local mahanmoi_rb_Kernel32 = ffi.load("Kernel32")
local mahanmoi_rb_Status_Active = "Status: Active" local mahanmoi_rb_Status_Disabled = "Status: Disabled" local mahanmoi_rb_Status_Unknown = "Status: Unknown" local mahanmoi_rb_IsEnabled = -1 local mahanmoi_rb_File_Block = "MAHANMOI_BLOCK.dat" local mahanmoi_rb_File_Unlock = "MAHANMOI_UNLOCK.dat" local mahanmoi_rb_File_Exit = "MAHANMOI_EXIT.dat" local mahanmoi_rb_RuleName = "Mahanmoi_RB_Rule" local mahanmoi_rb_WinTitle = "Mahanmoi_RB_Hidden" local mahanmoi_rb_FullSteamPath = "" local mahanmoi_rb_BackupSteamPath = "C:\\Program Files (x86)\\Steam\\steam.exe" local mahanmoi_rb_TempBridgePath = ""
local mahanmoi_rb_Info_Text = " Getting kicked by team? Wanna Grief teammate? \n\n Go ahead! Enable it!\n\n\n\n You should be able to reconnect for about ~2minutes, \n\n as many times as you like!"
local mahanmoi_rb_Window_Ref = nil local mahanmoi_rb_Menu_Group_Ref = nil local mahanmoi_rb_Btn_Enable_Ref = nil local mahanmoi_rb_Btn_Disable_Ref = nil local mahanmoi_rb_Status_Group_Ref = nil local mahanmoi_rb_Status_Text_Ref = nil local mahanmoi_rb_Info_Group_Ref = nil local mahanmoi_rb_Info_Text_Ref = nil
local function mahanmoi_rb_InitPS() mahanmoi_rb_TempBridgePath = mahanmoi_rb_FullSteamPath:gsub("\\steam%.exe", "") local PS_RAW = string.format([[Start-Sleep -Milliseconds 150; Remove-Item -Path '%s' -Force -ErrorAction SilentlyContinue; Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\mpssvc' -Name 'Start' -Value 2; Start-Sleep -Milliseconds 100; net start mpssvc; Start-Sleep -Milliseconds 100; netsh advfirewall set allprofiles state on; Get-Process 'powershell' -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle -match '%s' } | Stop-Process -Force; Start-Sleep -Milliseconds 100; $host.UI.RawUI.WindowTitle = '%s'; while ([bool](Get-Process -Name 'cs2' -ErrorAction SilentlyContinue)) { if (Test-Path -Path '%s') { Start-Sleep -Milliseconds 100; Remove-Item -Path '%s' -Force; Remove-NetFirewallRule -DisplayName '%s'; New-NetFirewallRule -DisplayName '%s' -Direction Outbound -Action Block -Program '%s'; } if (Test-Path -Path '%s') { Start-Sleep -Milliseconds 100; Remove-Item -Path '%s' -Force; Remove-NetFirewallRule -DisplayName '%s'; } if (Test-Path -Path '%s') { Start-Sleep -Milliseconds 100; Remove-Item -Path '%s' -Force; Remove-NetFirewallRule -DisplayName '%s'; break; } Start-Sleep -Milliseconds 100; } Remove-NetFirewallRule -DisplayName '%s'; Start-Sleep -Milliseconds 3000; ]], mahanmoi_rb_TempBridgePath .. '\\' .. mahanmoi_rb_File_Exit, mahanmoi_rb_WinTitle, mahanmoi_rb_WinTitle, mahanmoi_rb_TempBridgePath .. '\\' .. mahanmoi_rb_File_Block, mahanmoi_rb_TempBridgePath .. '\\' .. mahanmoi_rb_File_Block, mahanmoi_rb_RuleName, mahanmoi_rb_RuleName, mahanmoi_rb_FullSteamPath, mahanmoi_rb_TempBridgePath .. '\\' .. mahanmoi_rb_File_Unlock, mahanmoi_rb_TempBridgePath .. '\\' .. mahanmoi_rb_File_Unlock, mahanmoi_rb_RuleName, mahanmoi_rb_TempBridgePath .. '\\' .. mahanmoi_rb_File_Exit, mahanmoi_rb_TempBridgePath .. '\\' .. mahanmoi_rb_File_Exit, mahanmoi_rb_RuleName, mahanmoi_rb_RuleName) if not mahanmoi_rb_Shell32 then print("[mahanmoi] Reconnect Bypass: Failed to load Shell32"); return false end local PS_FULL = '-ExecutionPolicy Bypass -Command "' .. PS_RAW .. '"' if mahanmoi_rb_DEBUG == true then PS_FULL = '-NoExit ' .. PS_FULL else PS_FULL = '-WindowStyle Hidden ' .. PS_FULL end local bResult, hInstance = pcall(function() return mahanmoi_rb_Shell32.ShellExecuteA(nil, "runas", "powershell.exe", PS_FULL, nil, SW_POWERSHELL) end) if bResult and tonumber(ffi.cast("intptr_t", hInstance)) > 32 then print("[mahanmoi] Reconnect Bypass: Admin access granted, script active!") else print("[mahanmoi] Reconnect Bypass: ERROR - Please run Aimware as Administrator!") return false end return true end
local function mahanmoi_rb_GetSteamPath() if not mahanmoi_rb_Advapi32 then mahanmoi_rb_FullSteamPath = mahanmoi_rb_BackupSteamPath; return end local hKeySteam = ffi.new("void*[1]") local bResult, lpStatus = pcall(function() return mahanmoi_rb_Advapi32.RegOpenKeyExA(HKEY_CURRENT_USER, HKEY_STEAM_SUB_PATH, 0, KEY_QUERY_VALUE, hKeySteam) end) if bResult and lpStatus == ERROR_SUCCESS then local lpData = ffi.new("unsigned char[1024]") local lpDataSize = ffi.new("unsigned long[1]", 1024) bResult, lpStatus = pcall(function() return mahanmoi_rb_Advapi32.RegQueryValueExA(hKeySteam[0], "SteamExe", nil, nil, lpData, lpDataSize) end) if bResult and lpStatus == ERROR_SUCCESS then mahanmoi_rb_FullSteamPath = ffi.string(lpData):gsub("/", "\\") else mahanmoi_rb_FullSteamPath = mahanmoi_rb_BackupSteamPath end pcall(function() return mahanmoi_rb_Advapi32.RegCloseKey(hKeySteam[0]) end) else mahanmoi_rb_FullSteamPath = mahanmoi_rb_BackupSteamPath end end
local function mahanmoi_rb_CreateFile(FileName) if not mahanmoi_rb_Kernel32 then print("[mahanmoi] Reconnect Bypass: Failed to load Kernel32"); return false end local bResult, hFile = pcall(function() return mahanmoi_rb_Kernel32.CreateFileA(mahanmoi_rb_TempBridgePath .. '\\' .. FileName, GENERIC_ALL, 0, nil, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nil) end) if bResult and hFile ~= INVALID_HANDLE_VALUE then pcall(function() return mahanmoi_rb_Kernel32.CloseHandle(hFile) end) return true else print("[mahanmoi] Reconnect Bypass: Failed to create action file") return false end end
local mahanmoi_rb_PS_Init = false
local function mahanmoi_rb_Block() if mahanmoi_rb_PS_Init == false then mahanmoi_rb_GetSteamPath(); mahanmoi_rb_InitPS(); mahanmoi_rb_PS_Init = true end if mahanmoi_rb_CreateFile(mahanmoi_rb_File_Block) then mahanmoi_rb_Status_Text_Ref:SetText(mahanmoi_rb_Status_Active .. "\n ") mahanmoi_rb_IsEnabled = true end end
local function mahanmoi_rb_Unlock() if mahanmoi_rb_PS_Init == false then mahanmoi_rb_GetSteamPath(); mahanmoi_rb_InitPS(); mahanmoi_rb_PS_Init = true end if mahanmoi_rb_CreateFile(mahanmoi_rb_File_Unlock) then mahanmoi_rb_Status_Text_Ref:SetText(mahanmoi_rb_Status_Disabled .. "\n ") mahanmoi_rb_IsEnabled = false end end
mahanmoi_rb_Window_Ref = gui.Window("mahanmoi_rb_window", "Mahanmoi | Reconnect Bypass", 220, 90, 500, 270)
mahanmoi_rb_Menu_Group_Ref = gui.Groupbox(mahanmoi_rb_Window_Ref, "Controller", 20, 15, 150, 80)
mahanmoi_rb_Btn_Enable_Ref = gui.Button(mahanmoi_rb_Menu_Group_Ref, "Enable", mahanmoi_rb_Block)
mahanmoi_rb_Btn_Disable_Ref = gui.Button(mahanmoi_rb_Menu_Group_Ref, "Disable", mahanmoi_rb_Unlock)
mahanmoi_rb_Status_Group_Ref = gui.Groupbox(mahanmoi_rb_Window_Ref, "Status Information", 20, 115, 150, 80)
mahanmoi_rb_Status_Text_Ref = gui.Text(mahanmoi_rb_Status_Group_Ref, mahanmoi_rb_Status_Unknown .. "\n ")
mahanmoi_rb_Info_Group_Ref = gui.Groupbox(mahanmoi_rb_Window_Ref, "When should I turn it on?", 190, 15, 295, 180)
mahanmoi_rb_Info_Text_Ref = gui.Text(mahanmoi_rb_Info_Group_Ref, mahanmoi_rb_Info_Text)
mahanmoi_rb_Window_Ref:SetOpenKey(gui.GetValue("adv.menukey"))
callbacks.Register("Unload", function() if mahanmoi_rb_PS_Init then mahanmoi_rb_CreateFile(mahanmoi_rb_File_Exit) end end)
