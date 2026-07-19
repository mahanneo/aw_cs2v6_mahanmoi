local BASE        = rawget(_G, "MAHANMOI_BASE") or "https://raw.githubusercontent.com/mahanneo/aw_cs2v6_mahanmoi/main/"
local GUILIB_URL  = BASE .. "mahanmoi_guilib.lua"
local CHANGER_URL = BASE .. "mahanmoi_changer.lua"

local ffi = rawget(_G, "ffi")
local function r_ptr(a) return tonumber(ffi.cast("uint64_t*", a)[0]) end
local function valid(p) return p ~= nil and p > 0x10000 and p < 0x7FFFFFFFFFFF end

local function fetch(url, cacheFile)
    local src
    local bust = url .. "?nocache=" .. tostring({}):gsub("%W", "")
    pcall(function() src = http.Get(bust) end)
    if type(src) ~= "string" or #src <= 500 then pcall(function() src = http.Get(url) end) end
    if type(src) == "string" and #src > 500 then
        pcall(function() local f = file.Open(cacheFile, "w"); if f then f:Write(src); f:Close() end end)
        return src, "server"
    end
    pcall(function() local f = file.Open(cacheFile, "r"); if f then src = f:Read(); f:Close() end end)
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
local weaponLb, skinLb, skinWd
local sWear, sSeed, cbAuto
local cbVm, vmX, vmY, vmZ
local hsOn, hsCmb, hsCmbWd, hsVol
local ksOn, ksCmb, ksCmbWd, ksVol
local hlOn, hlMiss, hlHit, hlHurt, hlKill
local wmOn, wmElems, wmPos
local rgOn, rgCmb, rgCmbWd, rgPen, rgMin

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
        for i = 2, #paints do if paints[i] == c.paint then skinWd.value = i; break end end
    end
    lastSig = sig()
end

local function persistOpts()
    local v = cbAuto:Get()
    if v ~= lastAuto then lastAuto = v; C.setOpt("autoFollow", v) end
end

-- ======================= SOUNDS & HITLOGS CORE =======================
local HS = {}
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

    local function resolve(cmb) return tostring(SND_PATHS[cmb:Get()] or "") end
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
    local HG = { [0] = "body", [1] = "head", [2] = "chest", [3] = "stomach", [4] = "l.arm", [5] = "r.arm", [6] = "l.leg", [7] = "r.leg", [10] = "gear" }

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
                if hlOn:Get() and hlKill:Get() then M:Hitlog("kill", dmg, "killed " .. who .. " in " .. hg .. " for " .. dmg .. "hp") end
            else
                if hsOn:Get() then HS.playHit() end
                if hlOn:Get() and hlHit:Get() then M:Hitlog("hit", dmg, "hit " .. who .. " in " .. hg .. " for " .. dmg .. "hp") end
            end
        elseif iHurt then
            local who = nameOf(elist, d.attacker) or "player"
            if hlOn:Get() and hlHurt:Get() then M:Hitlog("hurt", dmg, "hurt by " .. who .. " in " .. hg .. " for " .. dmg .. "hp") end
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
            pcall(function() d.attacker = ev:GetInt("attacker"); d.userid = ev:GetInt("userid"); d.health = ev:GetInt("health"); d.dmg_health = ev:GetInt("dmg_health"); d.hitgroup = ev:GetInt("hitgroup") end)
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
        local s = table.concat({ hsOn:Get() and 1 or 0, hsCmb:Get(), hsVol:Get(), ksOn:Get() and 1 or 0, ksCmb:Get(), ksVol:Get() }, ":")
        if s == lastHs then return end
        lastHs = s
        C.setOpt("hs_on2", hsOn:Get()); C.setOpt("hs_snd2", hsCmb:Get()); C.setOpt("hs_vol2", hsVol:Get())
        C.setOpt("ks_on2", ksOn:Get()); C.setOpt("ks_snd2", ksCmb:Get()); C.setOpt("ks_vol2", ksVol:Get())
    end
end

-- ======================= REGION LOCKER CORE =======================
local RG = { ok = false, ids = {}, names = {}, allow = {}, add = 200, enabled = false, installed = false, minimize = false }
do
    local f = ffi
    local CITY = { ams = "Amsterdam", atl = "Atlanta", bom = "Mumbai", maa = "Chennai", can = "Guangzhou", sha = "Shanghai", tyo = "Tokyo", hkg = "Hong Kong", seo = "Seoul", sgp = "Singapore", syd = "Sydney", dxb = "Dubai", fra = "Frankfurt", lhr = "London", lux = "Luxembourg", par = "Paris", mad = "Madrid", sto = "Stockholm", vie = "Vienna", waw = "Warsaw", hel = "Helsinki", iad = "Washington", ord = "Chicago", lax = "Los Angeles", sea = "Seattle", dfw = "Dallas", okc = "Oklahoma", gru = "Sao Paulo", sao = "Sao Paulo", scl = "Santiago", lim = "Lima", bog = "Bogota", eat = "Moscow", jhb = "Johannesburg", pwj = "Tianjin", pwg = "Guangzhou", pwz = "Chengdu", tsn = "Tianjin", cpt = "Cape Town" }

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
        local TARGETS = { { rva = 0x13F050, steal = 17 }, { rva = 0x13EBB0, steal = 15, call = 10 } }
        local DLL  = "steamnetworkingsockets.dll"
        local ACCS = { "SteamNetworkingUtils_LibV4", "SteamNetworkingUtils_LibV3", "SteamNetworkingUtils_LibV2" }
        local hmod = f.C.GetModuleHandleA(DLL)
        local base = hmod ~= nil and tonumber(f.cast("uintptr_t", hmod)) or nil
        local modSize = 0
        if base then pcall(function() local e_lfanew = f.cast("uint32_t*", base + 0x3C)[0]; modSize = tonumber(f.cast("uint32_t*", base + e_lfanew + 0x50)[0]) or 0 end) end

        local utils, vtbl, getCount, getList
        if hmod ~= nil then
            local acc
            for _, nm in ipairs(ACCS) do local p = f.C.GetProcAddress(hmod, nm); if p ~= nil then acc = p; break end end
            if acc ~= nil then local ok2, u = pcall(function() return f.cast("void*(*)(void)", acc)() end); if ok2 and u ~= nil then utils = u end end
            if utils ~= nil then vtbl = f.cast("void***", utils)[0]; if vtbl ~= nil then getCount = f.cast("int(*)(void*)", vtbl[IDX_COUNT]); getList  = f.cast("int(*)(void*, uint32_t*, int)", vtbl[IDX_LIST]) end end
        end

        local w_u8  = function(a, v) f.cast("uint8_t*",  a)[0] = v end
        local w_i32 = function(a, v) f.cast("int32_t*",  a)[0] = v end
        local le64  = function(a, v) f.cast("uint64_t*", a)[0] = f.cast("uint64_t", v) end

        local function alloc_near(target)
            local gran = 0x10000; local b = target - (target % gran)
            for i = 1, 0x8000 do
                local lo = b - i * gran
                if lo > 0x10000 then local p = f.C.VirtualAlloc(f.cast("void*", lo), 64, 0x3000, 0x40); if p ~= nil then return p end end
                local p2 = f.C.VirtualAlloc(f.cast("void*", b + i * gran), 64, 0x3000, 0x40); if p2 ~= nil then return p2 end
            end
            return nil
        end

        local hooks, keeps = {}, {}
        local function hookFunc(rva, steal, callOff)
            if not base or modSize <= 0 or rva <= 0 or (rva + steal + 16) > modSize then return nil end
            local T  = base + rva; local b0 = f.cast("uint8_t*", T)
            if b0[0] == 0x00 or b0[0] == 0xCC then return nil end
            local p  = alloc_near(T); if p == nil then return nil end
            local TR = tonumber(f.cast("uintptr_t", p))
            local saved = {}
            for i = 0, steal - 1 do saved[i] = b0[i]; w_u8(TR + i, b0[i]) end
            if callOff then local relOrig = f.cast("int32_t*", T + callOff + 1)[0]; local callTarget = (T + callOff + 5) + relOrig; local newRel = callTarget - (TR + callOff + 5); if newRel < -2147483648 or newRel > 2147483647 then return nil end; w_i32(TR + callOff + 1, newRel) end
            w_u8(TR + steal, 0xFF); w_u8(TR + steal + 1, 0x25); w_i32(TR + steal + 2, 0); le64(TR + steal + 6, T + steal)
            local orig = f.cast("int(*)(void*, uint32_t, uint32_t*)", f.cast("void*", TR))
            local cb = f.cast("int(*)(void*, uint32_t, uint32_t*)", function(self, popid, via)
                local r = orig(self, popid, via)
                if RG.enabled and r >= 0 and next(RG.allow) ~= nil then
                    if RG.allow[tonumber(popid)] then if RG.minimize then return 1 end else return r + RG.add end
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
            for _, t in ipairs(TARGETS) do local o = nil; pcall(function() o = hookFunc(t.rva, t.steal, t.call) end); if o then any = true; if not RG.ping then RG.ping = o end end end
            RG.installed = any; return any
        end

        function RG.uninstall()
            for _, h in ipairs(hooks) do pcall(function() local old = f.new("uint32_t[1]"); f.C.VirtualProtect(f.cast("void*", h.T), h.steal, 0x40, old); for i = 0, h.steal - 1 do w_u8(h.T + i, h.saved[i]) end; f.C.VirtualProtect(f.cast("void*", h.T), h.steal, old[0], old); f.C.FlushInstructionCache(f.C.GetCurrentProcess(), f.cast("void*", h.T), h.steal) end) end
            RG.installed = false
        end

        local function pingOf(id)
            if not RG.ping then return nil end
            local r; pcall(function() local via = f.new("uint32_t[1]"); r = RG.ping(nil, id, via) end)
            if r and r >= 0 and r < 100000 then return r end
            return nil
        end

        local function enumerate()
            if utils == nil or not getCount or not getList then return end
            local n = getCount(utils); if n <= 0 then return end; if n > 256 then n = 256 end
            local buf = f.new("uint32_t[?]", n); local got = getList(utils, buf, n); if got < 0 then return end; if got > n then got = n end
            local all, hasPing = {}, {}
            for i = 0, got - 1 do
                local id = tonumber(buf[i]); local known = CITY[decode(id):lower()] ~= nil; local ping = pingOf(id)
                local nm = RG.label(id) .. (ping and ("  " .. ping .. "ms") or "")
                local e = { id = id, name = nm, known = known, ping = ping }; all[#all + 1] = e
                if ping ~= nil and ping <= 250 then hasPing[#hasPing + 1] = e end
            end
            local use = (#hasPing > 0) and hasPing or all
            table.sort(use, function(a, b) if (a.ping ~= nil) ~= (b.ping ~= nil) then return a.ping ~= nil end; if a.ping and b.ping and a.ping ~= b.ping then return a.ping < b.ping end; if a.known ~= b.known then return a.known end; return a.name < b.name end)
            local ids, names = {}, {}
            for _, e in ipairs(use) do ids[#ids + 1] = e.id; names[#names + 1] = e.name end
            if #ids > 0 then RG.ids = ids; RG.names = names end
        end
        RG.enumerate = enumerate

        local okI = false
        pcall(function() okI = install() end)
        if utils ~= nil and vtbl ~= nil then pcall(enumerate) end
        RG.ok = okI
        if okI then print("[mahanmoi] region: hooked " .. #hooks .. " fns (" .. #RG.ids .. " pops)") else print("[mahanmoi] region: auto-install disabled (safe mode)") end
    end
    if #RG.names == 0 then RG.names = { "[ join a server, then Refresh ]" } end
end
pcall(function() callbacks.Register("Unload", function() pcall(RG.uninstall) end) end)

-- ======================= VOTE LOGGER & CHAT CORE =======================
local CHAT = { ok = false }
do
    local f = ffi
    local SIG_CHAT = "4C 89 4C 24 20 53 56 B8 38 10 00 00 E8 ?? ?? ?? ?? 48 2B E0 48 8B 0D ?? ?? ?? ?? 41 8B D8 48 8B F2"
    local fn, flags
    if type(f) == "table" then
        local a = mem.FindPattern("client.dll", SIG_CHAT)
        if a and a ~= 0 then fn = f.cast("void(*)(void*, void*, uint32_t, const char*, const char*)", f.cast("void*", a)); flags = f.new("int[1]", 0x0100); CHAT.ok = true end
    end
    function CHAT.print(text) if not (CHAT.ok and fn) then return false end; return pcall(function() fn(nil, flags, 0, "%s", tostring(text)) end) end
end

local VR = { q = {} }
do
    local G, R, W, P = string.char(4), string.char(2), string.char(1), string.char(14)
    local function pfx() return "[" .. P .. "mahanmoi" .. W .. "] " end
    local function startMsg(initiator, target) return pfx() .. initiator .. " started a vote to kick " .. target, initiator .. " wants to kick " .. target end
    local function castMsg(name, yes) local yn = yes and (G .. "yes" .. W) or (R .. "no" .. W); return pfx() .. name .. " voted " .. yn, name .. " voted " .. (yes and "yes" or "no") end
    local function push(chat, note, kind) VR.q[#VR.q + 1] = { chat = chat, note = note, kind = kind } end
    local function pname(slot) if not slot or slot < 0 then return "player" end; local n = HS.nameBySlot(slot); if type(n) == "string" and #n > 0 and #n < 64 then return n end; return "player" end

    function VR.flush()
        local total = #VR.q; if total == 0 then return end
        local q = VR.q; VR.q = {}
        local mode = (VR._mode and VR._mode()) or 3
        for i = 1, total do local it = q[i]; if mode == 1 or mode == 3 then pcall(function() CHAT.print(it.chat) end) end; if mode == 2 or mode == 3 then pcall(function() M:Notify(it.note, it.kind) end) end end
    end

    function VR.onEvent(ev)
        if not (VR._on and VR._on()) then return end
        local name; pcall(function() name = ev:GetName() end)
        if name == "vote_cast" then
            local opt; pcall(function() opt = ev:GetInt("vote_option") end); if opt == nil or opt < 0 then return end
            local voter; pcall(function() voter = ev:GetInt("userid") end); local yes = (opt == 0)
            local c, n = castMsg(pname(voter), yes); push(c, n, yes and "success" or "error")
        elseif name == "vote_started" or name == "vote_begin" then
            local initiator; pcall(function() initiator = ev:GetInt("entityid") end); if not initiator or initiator <= 0 then pcall(function() initiator = ev:GetInt("userid") end) end
            local tid; pcall(function() local disp = ev:GetString("disp_str"); if type(disp) == "string" then local m = disp:match(":(%d+):"); if m then tid = tonumber(m) end end end)
            local c, n = startMsg(pname(initiator), tid and pname(tid) or "player"); push(c, n, "info")
        end
    end
end

-- ======================= UI SECTION =======================
local tab = M:Tab("Skins")
tab:Row()
weaponLb = tab:Section("Weapons"):Listbox("", C.names, "fill", 1)
tab:Col()
local sSec = tab:Section("Skins")
skinLb = sSec:Listbox("", { "[ select a weapon ]" }, "fill", 1)
skinWd = sSec.ws[#sSec.ws]
tab:Col()
local setSec = tab:Section("Settings")
sWear  = setSec:Slider("Wear / Float", 0.0001, 0.0, 1.0, 0.001, "%.3f")
sSeed  = setSec:Slider("Seed", 0, 0, 1000, 1)
cbAuto = setSec:Checkbox("Auto select weapon", false)
local actSec = tab:Section("Actions")
actSec:Button("Remove",    function() C.remove(item()) end)
actSec:Button("Reset All", function() C.resetAll() end)
local cfgSec = tab:Section("Config")
cfgSec:Button("Reset config", function() C.clearConfig() end)

local vtab = M:Tab("Visuals")
-- Models Sub-Tab Completely Removed As Requested

local sublocal = vtab:Sub("Local")
sublocal:Row()
local localSection = sublocal:Section("Local player")
cbVm = localSection:Checkbox("Viewmodel override", false)
vmX  = localSection:Slider("Offset X", 0, -30, 30, 0.1, "%.1f")
vmY  = localSection:Slider("Offset Y", 0, -30, 30, 0.1, "%.1f")
vmZ  = localSection:Slider("Offset Z", 0, -30, 30, 0.1, "%.1f")

local subsound = vtab:Sub("Sounds")
subsound:Row()
local hsSec = subsound:Section("Hit sound")
hsOn = hsSec:Checkbox("Enabled", true); hsCmb = hsSec:Combo("Sound", SND_NAMES, 1); hsCmbWd = hsSec.ws[#hsSec.ws]; hsVol = hsSec:Slider("Volume", 100, 0, 100, 1, "%.0f")
subsound:Col()
local ksSec = subsound:Section("Kill sound")
ksOn = ksSec:Checkbox("Enabled", false); ksCmb = ksSec:Combo("Sound", SND_NAMES, 1); ksCmbWd = ksSec.ws[#ksSec.ws]; ksVol = ksSec:Slider("Volume", 100, 0, 100, 1, "%.0f")
subsound:Col()
local tSec = subsound:Section("Preview")
tSec:Button("Play hit",  function() HS.playHit() end)
tSec:Button("Play kill", function() HS.playKill() end)
tSec:Button("Rescan", function() local n, p = HS.scan(); SND_PATHS = p; hsCmbWd.options = n; hsCmbWd.value = 1; ksCmbWd.options = n; ksCmbWd.value = 1 end)
tSec:Button("Open folder", function() HS.openSoundDir() end)

local subhl = vtab:Sub("Hitlogs")
subhl:Row()
local hlSet = subhl:Section("Hitlog")
hlOn = hlSet:Checkbox("Enabled", true)
hlSet:Button("Reset position", function() M:HitlogResetPos() end)
subhl:Col()
local hlTypes = subhl:Section("Types")
hlHit = hlTypes:Checkbox("Hit", true); hlKill = hlTypes:Checkbox("Kill", true); hlHurt = hlTypes:Checkbox("Hurt", true); hlMiss = hlTypes:Checkbox("Miss", false)
hlTypes:Button("Test", function() local d = math.random(8, 60); M:Hitlog("hit", d, "hit player in head for " .. d .. "hp"); M:Hitlog("kill", d, "killed player in head for " .. d .. "hp"); M:Hitlog("miss", nil, "missed shot") end)
subhl:Col()
local hlCol = subhl:Section("Colors")
local cMiss = hlCol:ColorPicker("Miss", { 235, 90, 90 }); local cHit = hlCol:ColorPicker("Hit", { 139, 124, 246 }); local cHurt = hlCol:ColorPicker("Hurt", { 245, 170, 70 }); local cKill = hlCol:ColorPicker("Kill", { 80, 200, 120 })

local subwm = vtab:Sub("Watermark")
subwm:Row()
local wmSec = subwm:Section("Watermark")
wmOn = wmSec:Checkbox("Enabled", true)
wmElems = wmSec:MultiCombo("Elements", { "Cheat name", "Lua name", "Username", "Nickname", "fps", "ping" }, { 2, 4, 5, 6 })
wmPos = wmSec:Combo("Position", { "Top left", "Top right", "Bottom left", "Bottom right" }, 2)

-- ======================= MISC TAB & REGION UI =======================
local mtab = M:Tab("Misc")
local subrg = mtab:Sub("Region")
subrg:Row()
local rgSec = subrg:Section("Region Locker")
rgOn = rgSec:Checkbox("Enable Region Locker", false)
rgCmb = rgSec:Combo("Select Region", RG.names, 1)
rgCmbWd = rgSec.ws[#rgSec.ws]
rgPen = rgSec:Slider("Ping Penalty (ms)", 200, 0, 500, 10, "%.0f")
rgMin = rgSec:Checkbox("Minimize allowed ping", false)
rgSec:Button("Refresh Regions", function() pcall(RG.enumerate); rgCmbWd.options = RG.names; rgCmbWd.value = 1 end)

-- ======================= SYNCHRONIZATION & MAIN LOOPS =======================
local lastVm = nil
local function syncVm()
    local on = cbVm:Get()
    local x, y, z = vmX:Get(), vmY:Get(), vmZ:Get()
    if on then
        client.SetConVar("viewmodel_offset_x", x, true)
        client.SetConVar("viewmodel_offset_y", y, true)
        client.SetConVar("viewmodel_offset_z", z, true)
    else
        client.SetConVar("viewmodel_offset_x", 0, true)
        client.SetConVar("viewmodel_offset_y", 0, true)
        client.SetConVar("viewmodel_offset_z", 0, true)
    end
    local s = (on and "1" or "0") .. ":" .. x .. ":" .. y .. ":" .. z
    if s ~= lastVm then lastVm = s; C.setOpt("vm_on", on); C.setOpt("vm_x", x); C.setOpt("vm_y", y); C.setOpt("vm_z", z) end
end

local function syncRegion()
    RG.enabled = rgOn:Get(); RG.allow = {}
    if RG.enabled then local sel = rgCmb:Get(); local id = RG.ids[sel]; if id then RG.allow[id] = true; RG.add = rgPen:Get(); RG.minimize = rgMin:Get() end end
end

-- ======================= EVENT HANDLERS & SKIN FIX =======================
pcall(function()
    for _, e in ipairs({ "player_hurt", "weapon_fire", "vote_started", "vote_begin", "vote_cast", "round_start" }) do
        pcall(function() client.AllowListener(e) end)
    end
    callbacks.Register("FireGameEvent", "FemboyTap_Events", function(ev)
        local name
        pcall(function() name = ev:GetName() end)
        
        -- FIX: Force skin re-apply when a new round starts
        if name == "round_start" then
            lastSig = nil 
            lastAutoDef = nil
        end
        
        pcall(HS.onEvent, ev)
        pcall(VR.onEvent, ev)
    end)
end)

callbacks.Register("Draw", "mahanmoi_main_draw", function()
    pcall(autoFollow)
    pcall(syncSkins)
    pcall(autoApply)
    pcall(persistOpts)
    pcall(syncVm)
    pcall(HS.sync)
    pcall(syncRegion)
    pcall(HS.missTick)
    pcall(VR.flush)
end)


-- ======================= NEW NAME CHANGER SCRIPT =======================
pcall(function() ffi.cdef [[ void* GetModuleHandleA(const char* lpModuleName); ]] end)

local NULL = 0x0
local ENGINE2_DLL_NAME = "engine2.dll"
local cVTable_Address_VEngineCvar007_offset 	= NULL
local cResolveConVar_offset 					= NULL
local cVTable_FindConVar_offset 				= 0xB
local cConVarFlags 						= 0x30
local FCVAR_DEVELOPMENTONLY					= 0x2
local FCVAR_USERINFO						= 0x200

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
local NameChanger_Combobox_ref = gui.Combobox(Aimware_Misc_Features_ref, "var_NameChanger_Listbox", "Clan-tag/Name-tag", "Disabled", "Fake name", "Animated", "Static", "Static | Radar", "Minecraft enchantment | Radar", "Radar Exploit")
local NameChanger_Clantag_Editbox_ref = gui.Editbox(Aimware_Misc_Features_ref, "var_NameChanger_Clantag_Editbox", "")
local NameChanger_Clantag_Speed_Slider_ref = gui.Slider(Aimware_Misc_Features_ref, "var_NameChanger_Clantag_Speed_Slider", "Animation speed", 0.3, 0, 1, 0.1)

local function GetMagicSymbols(iCount)
    local magicSymbols = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
    local result = ""
    for i = 1, iCount do
        local magicIndex = math.random(1, magicSymbols:len())
        result = result .. magicSymbols:sub(magicIndex, magicIndex)
    end
    return result
end

local cOldRealName = " "
local function SaveRealPlayerName(cRealPlayerName) cOldRealName = cRealPlayerName end
local function GetRealPlayerName() return cOldRealName end
local function SetUserNameAndClantag(cClantagWithName)
    client.Command('name ' .. '"' .. cClantagWithName .. '"', true)
    client.Command('setinfo name ' .. '"' .. cClantagWithName .. '"', true)
end

local function DisabledClantagHandler() SetUserNameAndClantag(cOldRealName) end
local function StaticClantagHandler() SetUserNameAndClantag(NameChanger_Clantag_Editbox_ref:GetString() .. " " .. cOldRealName) end
local function FakeNameHandler() SetUserNameAndClantag(NameChanger_Clantag_Editbox_ref:GetString()) end

local cAnimatedName = " "
local iAnimatedNameCurrentIndex = -1
local bReversed = false
local cLastTimeChanged_AnimTag = -1

local function AnimatedNameHandler()
    if globals.CurTime() < cLastTimeChanged_AnimTag then cLastTimeChanged_AnimTag = globals.CurTime() end
    if (globals.CurTime() - cLastTimeChanged_AnimTag) < NameChanger_Clantag_Speed_Slider_ref:GetValue() then return end
    cLastTimeChanged_AnimTag = globals.CurTime()
    local ExitBoxStr_len = NameChanger_Clantag_Editbox_ref:GetString():len()
    if bReversed then
        iAnimatedNameCurrentIndex = iAnimatedNameCurrentIndex + 1
        if iAnimatedNameCurrentIndex > ExitBoxStr_len then bReversed = false; iAnimatedNameCurrentIndex = ExitBoxStr_len end
    else
        iAnimatedNameCurrentIndex = iAnimatedNameCurrentIndex - 1
        if iAnimatedNameCurrentIndex < 0 then bReversed = true; iAnimatedNameCurrentIndex = 0 end
    end
    local cCurrentAnimatedNameTag = cAnimatedName:sub(1, iAnimatedNameCurrentIndex)
    local cAdditionalSpaces = ("\xC2\xA0\xC2\xA0"):rep(ExitBoxStr_len - iAnimatedNameCurrentIndex)
    SetUserNameAndClantag(cCurrentAnimatedNameTag .. cAdditionalSpaces .. " " .. cOldRealName)
end

local fakeChanged = false
local function StaticRadarClantagHandler()
    if fakeChanged then SetUserNameAndClantag(NameChanger_Clantag_Editbox_ref:GetString() .. " " .. cOldRealName); fakeChanged = false
    else SetUserNameAndClantag(NameChanger_Clantag_Editbox_ref:GetString() .. " " .. cOldRealName.. "\xC2\xA0"); fakeChanged = true end
end

local function MinecraftEnchantmentClantagHandler() SetUserNameAndClantag(GetMagicSymbols(math.random(10, 16))) end

local function RadarExploitClantagHandler()
    if fakeChanged then SetUserNameAndClantag(cOldRealName); fakeChanged = false
    else SetUserNameAndClantag(cOldRealName .. "\xC2\xA0"); fakeChanged = true end
end

local cInitTime = globals.CurTime()
local bForceExit = false
local bNameWasSaved = false
local bNameWasChanged = false
local cLastTimeChanged_logic = -1

local function NameChangerLogicHandler()
    if bForceExit then return end
    if globals.CurTime() < cLastTimeChanged_logic then cLastTimeChanged_logic = globals.CurTime() end
    if globals.CurTime() < cInitTime then cInitTime = globals.CurTime() end
    if engine.GetServerIP() == nil then cInitTime = globals.CurTime(); bNameWasSaved = false; return end
    if engine.GetMapName() == nil or engine.GetMapName() == "" then cInitTime = globals.CurTime(); bNameWasSaved = false; return end
    local pLocalPLayerEnt = entities.GetLocalPlayer()
    if pLocalPLayerEnt == nil then cInitTime = globals.CurTime(); bNameWasSaved = false; return end
    if (globals.CurTime() - cInitTime) < 1.0 then bNameWasSaved = false; return end
    if bNameWasSaved == false then
        if pLocalPLayerEnt:IsPlayer() == false then return end
        SaveRealPlayerName(pLocalPLayerEnt:GetName())
        bNameWasSaved = true
        patchConVar("name")
    end
    if (globals.CurTime() - cLastTimeChanged_logic) > 0.03 then
        cLastTimeChanged_logic = globals.CurTime()
        local ComboboxValue = NameChanger_Combobox_ref:GetValue()
        if ComboboxValue == 0 and bNameWasChanged == true then DisabledClantagHandler(); bNameWasChanged = false end
        if ComboboxValue == 1 then FakeNameHandler(); bNameWasChanged = true end
        if ComboboxValue == 2 then
            if NameChanger_Clantag_Editbox_ref:GetString() ~= cAnimatedName then cAnimatedName = NameChanger_Clantag_Editbox_ref:GetString(); iAnimatedNameCurrentIndex = NameChanger_Clantag_Editbox_ref:GetString():len(); bReversed = false end
            AnimatedNameHandler(); bNameWasChanged = true
        end
        if ComboboxValue == 3 then StaticClantagHandler(); bNameWasChanged = true end
        if ComboboxValue == 4 then StaticRadarClantagHandler(); bNameWasChanged = true end
        if ComboboxValue == 5 then MinecraftEnchantmentClantagHandler(); bNameWasChanged = true end
        if ComboboxValue == 6 then RadarExploitClantagHandler(); bNameWasChanged = true end
    end
end

local cLastTimeChanged_menu = -1
local function NameChangerMenuHandler()
    if bForceExit then return end
    if globals.CurTime() < cLastTimeChanged_menu then cLastTimeChanged_menu = globals.CurTime() end
    if (globals.CurTime() - cLastTimeChanged_menu) > 0.03 then
        cLastTimeChanged_menu = globals.CurTime()
        local ComboboxValue = NameChanger_Combobox_ref:GetValue()
        if ComboboxValue == 0 then NameChanger_Clantag_Editbox_ref:SetInvisible(true); NameChanger_Clantag_Speed_Slider_ref:SetInvisible(true) end
        if ComboboxValue == 1 then NameChanger_Clantag_Editbox_ref:SetInvisible(false); NameChanger_Clantag_Speed_Slider_ref:SetInvisible(true) end
        if ComboboxValue == 2 then NameChanger_Clantag_Editbox_ref:SetInvisible(false); NameChanger_Clantag_Speed_Slider_ref:SetInvisible(false) end
        if ComboboxValue == 3 then NameChanger_Clantag_Editbox_ref:SetInvisible(false); NameChanger_Clantag_Speed_Slider_ref:SetInvisible(true) end
        if ComboboxValue == 4 then NameChanger_Clantag_Editbox_ref:SetInvisible(false); NameChanger_Clantag_Speed_Slider_ref:SetInvisible(true) end
        if ComboboxValue == 5 then NameChanger_Clantag_Editbox_ref:SetInvisible(true); NameChanger_Clantag_Speed_Slider_ref:SetInvisible(true) end
        if ComboboxValue == 6 then NameChanger_Clantag_Editbox_ref:SetInvisible(true); NameChanger_Clantag_Speed_Slider_ref:SetInvisible(true) end
    end
end

callbacks.Register("Draw", NameChangerLogicHandler)
callbacks.Register("Draw", NameChangerMenuHandler)
callbacks.Register("Unload", function()
    bForceExit = true
    if bNameWasSaved and NameChanger_Combobox_ref:GetValue() ~= 0 then
        if entities.GetLocalPlayer() == nil then return end
        DisabledClantagHandler()
    end
end)
