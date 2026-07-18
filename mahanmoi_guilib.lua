local M = {}
M.VERSION = "1.1"

local T = {
    x = 360, y = 200, w = 600, h = 440,

    -- Premium purple glassmorphism dashboard palette
    accent    = { 168, 96, 255 },
    accent_bg = { 58, 28, 92, 220 },
    bg        = { 12, 12, 18, 255 },
    bg2       = { 8, 8, 14, 255 },
    section   = { 24, 18, 38, 230 },
    border    = { 112, 72, 170, 180 },
    divider   = { 52, 34, 78, 220 },
    text      = { 210, 205, 225, 255 },
    textdim   = { 125, 115, 150, 255 },
    texthi    = { 250, 245, 255, 255 },
    widget    = { 30, 22, 48, 235 },
    widgethi  = { 52, 35, 82, 240 },

    title     = "mahanmoi",
    title_tld = ".vip",
    titlebar  = 44,
    pad       = 14,
    sec_gap   = 12,

    font      = { "Oxanium", "Space Grotesk", "Varela Round", "Tahoma", "Verdana" },
    font_logo = { "Space Grotesk", "Oxanium", "Tahoma" },
    font_size = 14,

    notif_pos    = "bottom-right",
    notif_w      = 290,
    notif_margin = 18,
    notif_life   = 3.5,
    notif_info    = { 139, 124, 246 },
    notif_success = { 80, 200, 120 },
    notif_error   = { 235, 90, 90 },
}

local WH = { check = 28, button = 36, slider = 36, combo = 52, multicombo = 52, input = 52, color = 28 }
local function wheight(wd)
    if wd.kind == "listbox" then
        return ((wd.label and wd.label ~= "") and 18 or 0) + wd.h + 6
    end
    if wd.kind == "custom" then return wd._measured or wd.h end
    return WH[wd.kind] or 28
end

local ANIM = { open = 13, tab = 17 }

local floor, sqrt, mmin, mmax, mabs = math.floor, math.sqrt, math.min, math.max, math.abs
local function rnd(n) return floor(n + 0.5) end
local function clamp(v, lo, hi) if v < lo then return lo elseif v > hi then return hi else return v end end
local function smooth(t) t = clamp(t, 0, 1); return t * t * (3 - 2 * t) end

local function decimalsOf(step)
    if not step or step >= 1 then return 0 end
    local d, s = 0, step
    while s < 1 and d < 6 do
        s = s * 10; d = d + 1
        if mabs(s - floor(s + 0.5)) < 1e-7 then break end
    end
    return d
end

local ALPHA = 1
local DT = 0
local clipTop, clipBottom

local function approach(cur, target, speed)
    return cur + (target - cur) * clamp(DT * speed, 0, 1)
end

local function lerpc(a, b, t)
    t = clamp(t, 0, 1)
    return {
        a[1] + (b[1] - a[1]) * t,
        a[2] + (b[2] - a[2]) * t,
        a[3] + (b[3] - a[3]) * t,
        (a[4] or 255) + ((b[4] or 255) - (a[4] or 255)) * t,
    }
end

local ffi = ffi

-- ============================================================
-- FONT DOWNLOAD & INIT
-- ============================================================
local FONT_URLS = {
    { file = "mahanmoi_Oxanium.ttf",      url = "https://cdn.jsdelivr.net/gh/google/fonts@main/ofl/oxanium/Oxanium%5Bwght%5D.ttf" },
    { file = "mahanmoi_Orbitron.ttf",     url = "https://cdn.jsdelivr.net/gh/google/fonts@main/ofl/orbitron/Orbitron%5Bwght%5D.ttf" },
    { file = "mahanmoi_SpaceGrotesk.ttf", url = "https://cdn.jsdelivr.net/gh/google/fonts@main/ofl/spacegrotesk/SpaceGrotesk%5Bwght%5D.ttf" },
}

local FONT, FONT_B, FONT_LOGO

local function initFonts()
    local mk = function(list, size, weight)
        for _, name in ipairs(list) do
            local f
            pcall(function() f = draw.CreateFont(name, size, weight) end)
            if not f then pcall(function() f = draw.AddFont(name, size, weight) end) end
            if f then return f, name end
        end
    end
    local picked
    FONT,      picked = mk(T.font, T.font_size, 400)
    FONT_B            = mk(T.font, T.font_size, 600)
    FONT_LOGO         = mk(T.font_logo, T.font_size + 2, 700) or FONT_B
    print("[mahanmoi] font: " .. tostring(picked))
end

local function fontInitCoro()
    coroutine.yield()

    pcall(function()
        ffi.cdef[[
            unsigned long GetCurrentDirectoryA(unsigned long, char*);
            unsigned long GetFileAttributesA(const char*);
            int CreateDirectoryA(const char*, void*);
            int AddFontResourceExA(const char*, unsigned long, void*);
            long URLDownloadToFileA(void*, const char*, const char*, unsigned long, void*);
        ]]
    end)

    local gdi32, urlmon
    pcall(function() gdi32  = ffi.load("gdi32") end)
    pcall(function() urlmon = ffi.load("urlmon") end)

    local dir = "."
    pcall(function()
        local buf = ffi.new("char[600]")
        local n = ffi.C.GetCurrentDirectoryA(600, buf)
        if n and n > 0 then dir = ffi.string(buf, n) end
    end)
    dir = dir .. "\\mahanmoi_lua"
    pcall(function() ffi.C.CreateDirectoryA(dir, nil) end)
    M._dir = dir
    coroutine.yield()

    if gdi32 then
        for _, f in ipairs(FONT_URLS) do
            local path = dir .. "\\" .. f.file
            local exists = false
            pcall(function() exists = ffi.C.GetFileAttributesA(path) ~= 0xFFFFFFFF end)
            if not exists and urlmon then
                pcall(function() urlmon.URLDownloadToFileA(nil, f.url, path, 0, nil) end)
            end
            pcall(function() gdi32.AddFontResourceExA(path, 0x10, nil) end)
            coroutine.yield()
        end
    else
        print("[mahanmoi] ffi/gdi32 unavailable, using system fonts")
    end

    initFonts()
end

-- ============================================================
-- DRAWING PRIMITIVES
-- ============================================================
local function setcol(c) draw.Color(c[1], c[2], c[3], rnd((c[4] or 255) * ALPHA)) end

local function rect(x, y, w, h, c)
    setcol(c); draw.FilledRect(rnd(x), rnd(y), rnd(x + w), rnd(y + h))
end

local function rfill(x, y, w, h, r, c, tl, tr, br, bl)
    x, y, w, h = rnd(x), rnd(y), rnd(w), rnd(h)
    r = mmin(r, floor(w / 2), floor(h / 2))
    if r <= 0 then rect(x, y, w, h, c); return end
    if tl == nil then tl, tr, br, bl = true, true, true, true end
    rect(x, y + r, w, h - 2 * r, c)
    for dy = 0, r - 1 do
        local dx = r - floor(sqrt(r * r - (r - dy - 0.5) ^ 2) + 0.5)
        local lt, rt = tl and dx or 0, tr and dx or 0
        local lb, rb = bl and dx or 0, br and dx or 0
        rect(x + lt, y + dy, w - lt - rt, 1, c)
        rect(x + lb, y + h - 1 - dy, w - lb - rb, 1, c)
    end
end

local function rbox(x, y, w, h, r, fill, brd)
    rfill(x, y, w, h, r, brd)
    rfill(x + 1, y + 1, w - 2, h - 2, r - 1, fill)
end

local function frame(x, y, w, h, c)
    rect(x, y, w, 1, c); rect(x, y + h - 1, w, 1, c)
    rect(x, y, 1, h, c); rect(x + w - 1, y, 1, h, c)
end

-- ============================================================
-- COLOR CONVERSION
-- ============================================================
local function rgb2hsv(r, g, b)
    r, g, b = r / 255, g / 255, b / 255
    local mx, mn = mmax(r, g, b), mmin(r, g, b)
    local v, d = mx, mx - mn
    local s = mx == 0 and 0 or d / mx
    local h = 0
    if d ~= 0 then
        if mx == r then h = ((g - b) / d) % 6
        elseif mx == g then h = (b - r) / d + 2
        else h = (r - g) / d + 4 end
        h = h / 6; if h < 0 then h = h + 1 end
    end
    return h, s, v
end

local function hsv2rgb(h, s, v)
    local i = floor(h * 6) % 6
    local f = h * 6 - floor(h * 6)
    local p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
    local r, g, b
    if i == 0 then r, g, b = v, t, p
    elseif i == 1 then r, g, b = q, v, p
    elseif i == 2 then r, g, b = p, v, t
    elseif i == 3 then r, g, b = p, q, v
    elseif i == 4 then r, g, b = t, p, v
    else r, g, b = v, p, q end
    return rnd(r * 255), rnd(g * 255), rnd(b * 255)
end

-- ============================================================
-- TEXT
-- ============================================================
local function textw(s) local w = draw.GetTextSize(s); return w or 0 end

local function text(x, y, c, s, font, align)
    if font then draw.SetFont(font) end
    if align == "center" then x = x - textw(s) / 2
    elseif align == "right" then x = x - textw(s) end
    setcol(c); draw.Text(rnd(x), rnd(y), s)
end

-- ============================================================
-- INPUT RESOLUTION
-- ============================================================
local _getMouse
local function resolveMouse()
    local cands = {
        function() local p = input.GetMousePos();    return p.x or p[1], p.y or p[2] end,
        function() local p = input.GetCursorPos();    return p.x or p[1], p.y or p[2] end,
        function() local x, y = input.GetMousePos();  return x, y end,
        function() local x, y = input.GetCursorPos(); return x, y end,
    }
    for _, f in ipairs(cands) do
        local ok, x, y = pcall(f)
        if ok and type(x) == "number" and type(y) == "number" then return f end
    end
end

local _clock
local function resolveClock()
    local cands = {
        function() return globals.RealTime() end,
        function() return globals.CurTime() end,
        function() return os.clock() end,
    }
    for _, f in ipairs(cands) do
        local ok, v = pcall(f)
        if ok and type(v) == "number" then return f end
    end
end
local function now()
    if _clock then local ok, v = pcall(_clock); if ok then return v end end
    return 0
end

local _getWheel
local function resolveWheel()
    local cands = {
        function() return input.GetMouseWheel() end,
        function() return input.GetMouseWheelDelta() end,
        function() return input.GetScrollDelta() end,
        function() return input.GetScroll() end,
    }
    for _, f in ipairs(cands) do
        local ok, v = pcall(f)
        if ok and type(v) == "number" then return f end
    end
end
local function readWheel()
    if _getWheel then local ok, v = pcall(_getWheel); if ok and type(v) == "number" then return v end end
    return 0
end

-- ============================================================
-- KEYBOARD INPUT
-- ============================================================
local SHIFT_DIGITS = {
    [0x30] = ")", [0x31] = "!", [0x32] = "@", [0x33] = "#", [0x34] = "$",
    [0x35] = "%", [0x36] = "^", [0x37] = "&", [0x38] = "*", [0x39] = "("
}
local OEM = {
    [0xBA] = { ";", ":" }, [0xBB] = { "=", "+" }, [0xBC] = { ",", "<" },
    [0xBD] = { "-", "_" }, [0xBE] = { ".", ">" }, [0xBF] = { "/", "?" },
    [0xC0] = { "`", "~" }, [0xDB] = { "[", "{" }, [0xDC] = { "\\", "|" },
    [0xDD] = { "]", "}" }, [0xDE] = { "'", '"' },
}

local function keyPressed(k) local v = false; pcall(function() v = input.IsButtonPressed(k) end); return v end
local function keyDown(k)    local v = false; pcall(function() v = input.IsButtonDown(k)  end); return v end

-- ============================================================
-- CLIPBOARD
-- ============================================================
pcall(function() ffi.cdef[[
    int    OpenClipboard(void*);
    int    CloseClipboard(void);
    int    EmptyClipboard(void);
    void*  GetClipboardData(unsigned int);
    void*  SetClipboardData(unsigned int, void*);
    void*  GlobalAlloc(unsigned int, size_t);
    void*  GlobalLock(void*);
    int    GlobalUnlock(void*);
]] end)

local function clipGet()
    local out
    pcall(function()
        if ffi.C.OpenClipboard(nil) == 0 then return end
        local h = ffi.C.GetClipboardData(1)
        if h ~= nil then
            local p = ffi.C.GlobalLock(h)
            if p ~= nil then out = ffi.string(ffi.cast("char*", p)); ffi.C.GlobalUnlock(h) end
        end
        ffi.C.CloseClipboard()
    end)
    if out then out = out:gsub("[\r\n\t]", "") end
    return out
end

local function clipSet(s)
    s = tostring(s or "")
    pcall(function()
        if ffi.C.OpenClipboard(nil) == 0 then return end
        ffi.C.EmptyClipboard()
        local n = #s + 1
        local h = ffi.C.GlobalAlloc(2, n)
        if h ~= nil then
            local p = ffi.C.GlobalLock(h)
            if p ~= nil then
                local dst = ffi.cast("char*", p)
                for i = 0, n - 1 do dst[i] = (i < #s) and s:byte(i + 1) or 0 end
                ffi.C.GlobalUnlock(h)
                ffi.C.SetClipboardData(1, h)
            end
        end
        ffi.C.CloseClipboard()
    end)
end

-- ============================================================
-- KEY REPEAT
-- ============================================================
local _kr = {}
local REPEAT_DELAY, REPEAT_RATE = 0.40, 0.035

local function keyRepeat(k, t)
    if not keyDown(k) then _kr[k] = nil; return false end
    local s = _kr[k]
    if not s then _kr[k] = { first = t, last = t }; return true end
    if (t - s.first) >= REPEAT_DELAY and (t - s.last) >= REPEAT_RATE then
        s.last = t; return true
    end
    return false
end

-- ============================================================
-- TEXT INPUT WIDGET LOGIC
-- ============================================================
local function selBounds(wd)
    local c = wd._caret or #wd.value
    local a = wd._anchor or c
    if a > c then a, c = c, a end
    return a, c
end

local function hasSel(wd) return (wd._anchor or wd._caret or 0) ~= (wd._caret or 0) end

local function delSel(wd)
    local a, b = selBounds(wd)
    if a == b then return false end
    wd.value = wd.value:sub(1, a) .. wd.value:sub(b + 1)
    wd._caret = a; wd._anchor = a
    return true
end

local function inputView(wd, avail)
    local v, n = wd.value, #wd.value
    local caret = clamp(wd._caret or n, 0, n); wd._caret = caret
    if wd._anchor then wd._anchor = clamp(wd._anchor, 0, n) end
    local off = clamp(wd._off or 0, 0, n)
    if caret < off then off = caret end
    while off < caret and textw(v:sub(off + 1, caret)) > avail do off = off + 1 end
    local e = n
    while e > off and textw(v:sub(off + 1, e)) > avail do e = e - 1 end
    if e < caret then e = caret end
    wd._off = off
    return v:sub(off + 1, e), off, e
end

local function caretFromX(wd, relx, off)
    local v, n = wd.value, #wd.value
    if relx <= 0 then return off end
    for i = off + 1, n do
        local w = textw(v:sub(off + 1, i))
        if w >= relx then
            local wp = textw(v:sub(off + 1, i - 1))
            return ((relx - wp) < (w - relx)) and (i - 1) or i
        end
    end
    return n
end

local function pollText(wd, t)
    local ctrl  = keyDown(0x11)
    local shift = keyDown(0x10)
    local n = #wd.value
    wd._caret  = clamp(wd._caret or n, 0, n)
    wd._anchor = wd._anchor and clamp(wd._anchor, 0, n) or wd._caret

    if ctrl then
        if keyPressed(0x41) then wd._anchor = 0; wd._caret = n end
        if keyPressed(0x43) then
            local a, b = selBounds(wd)
            clipSet(a ~= b and wd.value:sub(a + 1, b) or wd.value)
        end
        if keyPressed(0x58) then
            local a, b = selBounds(wd)
            if a ~= b then clipSet(wd.value:sub(a + 1, b)); delSel(wd)
            else clipSet(wd.value); wd.value = ""; wd._caret = 0; wd._anchor = 0 end
        end
        if keyPressed(0x56) then
            local s = clipGet()
            if s then
                delSel(wd)
                local c = wd._caret
                wd.value = wd.value:sub(1, c) .. s .. wd.value:sub(c + 1)
                wd._caret = c + #s; wd._anchor = wd._caret
            end
        end
        return
    end

    local function move(to)
        wd._caret = clamp(to, 0, #wd.value)
        if not shift then wd._anchor = wd._caret end
    end
    local function ins(ch)
        delSel(wd)
        local c = wd._caret
        wd.value = wd.value:sub(1, c) .. ch .. wd.value:sub(c + 1)
        wd._caret = c + 1; wd._anchor = wd._caret
    end

    if keyRepeat(0x25, t) then
        local a, b = selBounds(wd)
        if not shift and a ~= b then wd._caret = a; wd._anchor = a
        else move(wd._caret - 1) end
    end
    if keyRepeat(0x27, t) then
        local a, b = selBounds(wd)
        if not shift and a ~= b then wd._caret = b; wd._anchor = b
        else move(wd._caret + 1) end
    end
    if keyPressed(0x24) then move(0) end
    if keyPressed(0x23) then move(#wd.value) end

    if keyRepeat(0x08, t) then
        if not delSel(wd) then
            local c = wd._caret
            if c > 0 then
                wd.value = wd.value:sub(1, c - 1) .. wd.value:sub(c + 1)
                wd._caret = c - 1; wd._anchor = c - 1
            end
        end
    end
    if keyRepeat(0x2E, t) then
        if not delSel(wd) then
            local c = wd._caret
            if c < #wd.value then wd.value = wd.value:sub(1, c) .. wd.value:sub(c + 2) end
        end
    end

    if keyRepeat(0x20, t) then ins(" ") end
    for k = 0x41, 0x5A do
        if keyRepeat(k, t) then
            local ch = string.char(k)
            ins(shift and ch or ch:lower())
        end
    end
    for k = 0x30, 0x39 do
        if keyRepeat(k, t) then ins(shift and SHIFT_DIGITS[k] or string.char(k)) end
    end
    for k, pair in pairs(OEM) do
        if keyRepeat(k, t) then ins(shift and pair[2] or pair[1]) end
    end
    if keyPressed(0x0D) or keyPressed(0x1B) then M._focus = nil end
end

-- ============================================================
-- MOUSE STATE
-- ============================================================
local ms = { x = 0, y = 0, down = false, pressed = false, released = false, consumed = false }

local function updateMouse()
    if _getMouse then
        local ok, x, y = pcall(_getMouse)
        if ok then ms.x, ms.y = x or ms.x, y or ms.y end
    end
    local down = false
    pcall(function() down = input.IsButtonDown(0x01) and true or false end)
    ms.pressed  = down and not ms.down
    ms.released = (not down) and ms.down
    ms.down     = down
    ms.consumed = false
    ms.wheel    = readWheel()
end

local function hovering(x, y, w, h)
    return ms.x >= x and ms.x <= x + w and ms.y >= y and ms.y <= y + h
end

local function clicked(x, y, w, h)
    if ms.consumed or not ms.pressed then return false end
    if hovering(x, y, w, h) then ms.consumed = true; return true end
    return false
end

local function handle(w)
    return {
        Get = function() return w.value end,
        Set = function(_, v) w.value = v end,
    }
end

-- ============================================================
-- PUBLIC UI HELPERS
-- ============================================================
local UI = {
    T = T, now = now, clamp = clamp, lerp = lerpc,
    rect  = function(x, y, w, h, c) rect(x, y, w, h, c) end,
    rfill = function(x, y, w, h, r, c) rfill(x, y, w, h, r, c) end,
    rbox  = function(x, y, w, h, r, f, b) rbox(x, y, w, h, r, f, b or T.border) end,
    text  = function(x, y, s, col, align) text(x, y, col or T.text, tostring(s), FONT, align) end,
    title = function(x, y, s, col, align) text(x, y, col or T.texthi, tostring(s), FONT_B, align) end,
    textw = function(s) return textw(tostring(s)) end,
    hover = function(x, y, w, h) return hovering(x, y, w, h) end,
    click = function(x, y, w, h) return clicked(x, y, w, h) end,
    mouse = function() return ms.x, ms.y, ms.down end,
    screen = function()
        local w, h = 0, 0
        pcall(function() w, h = draw.GetScreenSize() end)
        return w, h
    end,
}

local IM = {}
UI._x, UI._cy, UI._w = 0, 0, 200
UI.layout = function(x, y, w) UI._x = x; UI._cy = y; if w then UI._w = w end end

-- ============================================================
-- SECTION
-- ============================================================
local Section = {}
Section.__index = Section

function Section.new(title) return setmetatable({ title = title, ws = {} }, Section) end
function Section:_add(w) self.ws[#self.ws + 1] = w; return handle(w) end

function Section:Checkbox(label, def)
    return self:_add({ kind = "check", label = label, value = def and true or false })
end
function Section:Button(label, cb)
    return self:_add({ kind = "button", label = label, cb = cb })
end
function Section:Slider(label, def, mn, mx, step, fmt)
    step = step or 1
    return self:_add({
        kind = "slider", label = label, value = def, min = mn, max = mx,
        step = step, dec = decimalsOf(step), fmt = fmt
    })
end
function Section:SliderFloat(label, def, mn, mx, fmt, step)
    return self:Slider(label, def, mn, mx, step or 0.01, fmt)
end
function Section:Combo(label, options, def)
    return self:_add({ kind = "combo", label = label, options = options, value = def or 1 })
end
function Section:MultiCombo(label, options, defaults)
    local sel = {}
    if defaults then for _, i in ipairs(defaults) do sel[i] = true end end
    return self:_add({ kind = "multicombo", label = label, options = options, value = sel })
end
function Section:Input(label, def, placeholder)
    return self:_add({ kind = "input", label = label, value = def or "", placeholder = placeholder })
end
function Section:ColorPicker(label, col)
    col = col or { 255, 255, 255, 255 }
    return self:_add({ kind = "color", label = label, value = { col[1], col[2], col[3], col[4] or 255 } })
end
function Section:Listbox(label, items, height, def)
    local fill = (height == "fill")
    if fill then self._hasFill = true end
    return self:_add({
        kind = "listbox", label = label, items = items or {}, value = def or 1,
        h = fill and 120 or (height or 200), fill = fill, scroll = 0
    })
end
function Section:Custom(height, fn)
    return self:_add({ kind = "custom", h = height or 60, fn = fn })
end

function Section:height()
    local h = 42 + 10
    for _, wd in ipairs(self.ws) do h = h + wheight(wd) end
    return h
end

function Section:render(x, y, w)
    local natural = self:height()
    local h = natural
    if self._layoutH then
        h = mmax(natural, self._layoutH)
    elseif self._hasFill and clipBottom then
        local fh = (clipBottom - 12) - y
        if fh > h then h = fh end
    end

    if clipBottom and y >= clipBottom then return h end
    if clipTop and (y + h) <= clipTop then return h end

    local boxH = h
    if clipBottom and (y + boxH) > clipBottom then
        boxH = mmax(0, clipBottom - y)
    end
    if boxH > 0 and (not clipTop or y + boxH > clipTop) then
        local drawY = y
        local drawH = boxH
        if clipTop and drawY < clipTop then
            drawH = drawH - (clipTop - drawY)
            drawY = clipTop
        end
        if drawH > 0 then
            rbox(x, drawY, w, drawH, 6, T.section, T.border)
        end
        if (not clipTop or y + 26 > clipTop) and (not clipBottom or y + 12 < clipBottom) then
            rfill(x + 14, y + 12, 3, 14, 1, T.accent)
            text(x + 23, y + 12, T.texthi, self.title, FONT_B)
            if (not clipBottom or y + 33 < clipBottom) and (not clipTop or y + 34 > clipTop) then
                rect(x + 14, y + 33, w - 28, 1, T.divider)
            end
        end
    end

    local iy = y + 44
    local ix = x + 14
    local iw = w - 28
    for _, wd in ipairs(self.ws) do
        local wh
        if wd.kind == "listbox" and wd.fill then
            local labelH = (wd.label and wd.label ~= "") and 18 or 0
            local remain = (y + h - 12) - (iy + labelH)
            wd._fillH = mmax(wd.h or 120, remain)
            wh = labelH + wd._fillH + 6
        else
            wh = wheight(wd)
        end
        local visible = true
        if clipBottom and iy >= clipBottom then visible = false end
        if clipTop and (iy + wh) <= clipTop then visible = false end
        if visible then self:_widget(wd, ix, iy, iw) end
        iy = iy + wh
        if clipBottom and iy >= clipBottom then break end
    end
    return h
end

-- ============================================================
-- WIDGET RENDERING
-- ============================================================
function Section:_widget(wd, x, y, w)
    if wd.kind == "check" then
        local box = 15
        local by  = y + 1
        local hov = hovering(x, by, w, box)
        wd._h  = approach(wd._h or 0, hov and 1 or 0, 16)
        wd._on = approach(wd._on or 0, wd.value and 1 or 0, 16)
        local fill = lerpc(lerpc(T.widget, T.widgethi, wd._h), T.accent, wd._on)
        rbox(x, by, box, box, 4, fill, lerpc(T.border, T.accent, wd._on))
        text(x + box + 9, y + 2, lerpc(T.text, T.texthi, mmax(wd._h, wd._on)), wd.label, FONT)
        if clicked(x, by, w, box) then wd.value = not wd.value end

    elseif wd.kind == "button" then
        local bh  = 22
        local hov = hovering(x, y + 1, w, bh)
        wd._h = approach(wd._h or 0, hov and 1 or 0, 16)
        rbox(x, y + 1, w, bh, 5, lerpc(T.widget, T.widgethi, wd._h), T.border)
        text(x + w / 2, y + 6, lerpc(T.text, T.texthi, wd._h), wd.label, FONT, "center")
        if clicked(x, y + 1, w, bh) then
            local ok, err = pcall(wd.cb)
            if not ok then print("[mahanmoi] button error: " .. tostring(err)) end
        end

    elseif wd.kind == "slider" then
        local active = (M._slider == wd)
        wd._h = approach(wd._h or 0, (active or hovering(x, y + 18 - 6, w, 18)) and 1 or 0, 16)
        text(x, y, lerpc(T.text, T.texthi, wd._h), wd.label, FONT)
        local valstr
        if wd.fmt then valstr = string.format(wd.fmt, wd.value)
        elseif wd.dec > 0 then valstr = string.format("%." .. wd.dec .. "f", wd.value)
        else valstr = tostring(rnd(wd.value)) end
        text(x + w, y, T.texthi, valstr, FONT, "right")
        local ty, th = y + 18, 6
        local frac = clamp((wd.value - wd.min) / (wd.max - wd.min), 0, 1)
        rbox(x, ty, w, th, 3, lerpc(T.widget, T.widgethi, wd._h), T.border)
        if frac > 0 then rfill(x, ty, mmax(th, w * frac), th, 3, T.accent, true, false, false, true) end
        if ms.pressed and not ms.consumed and hovering(x, ty - 6, w, th + 12) then
            ms.consumed = true; M._slider = wd
        end
        if active then
            if ms.down and w > 0 then
                local raw = wd.min + clamp((ms.x - x) / w, 0, 1) * (wd.max - wd.min)
                if raw ~= raw then raw = wd.min end
                local v = wd.min + floor((raw - wd.min) / wd.step + 0.5) * wd.step
                v = clamp(v, wd.min, wd.max)
                if wd.dec > 0 then v = tonumber(string.format("%." .. wd.dec .. "f", v)) or v end
                wd.value = v
            elseif not ms.down then
                M._slider = nil
            end
        end

    elseif wd.kind == "combo" then
        local by, bh = y + 18, 22
        local open = (M._combo == wd)
        local hov  = hovering(x, by, w, bh)
        wd._h = approach(wd._h or 0, (hov or open) and 1 or 0, 16)
        text(x, y, lerpc(T.text, T.texthi, wd._h), wd.label, FONT)
        rbox(x, by, w, bh, 5, lerpc(T.widget, T.widgethi, wd._h), open and T.accent or T.border)
        text(x + 9, by + 5, open and T.texthi or lerpc(T.text, T.texthi, wd._h), wd.options[wd.value] or "?", FONT)
        text(x + w - 16, by + 5, open and T.accent or T.textdim, open and "-" or "v", FONT)
        if clicked(x, by, w, bh) then M._combo = open and nil or wd end
        if M._combo == wd then M._dd = { wd = wd, x = x, y = by + bh, w = w, bh = bh } end

    elseif wd.kind == "multicombo" then
        local by, bh = y + 18, 22
        local open = (M._combo == wd)
        local hov  = hovering(x, by, w, bh)
        wd._h = approach(wd._h or 0, (hov or open) and 1 or 0, 16)
        text(x, y, lerpc(T.text, T.texthi, wd._h), wd.label, FONT)
        rbox(x, by, w, bh, 5, lerpc(T.widget, T.widgethi, wd._h), open and T.accent or T.border)
        local parts, count = {}, 0
        for i, o in ipairs(wd.options) do
            if wd.value[i] then count = count + 1; parts[#parts + 1] = o end
        end
        local shown = count == 0 and "None" or (count > 2 and (count .. " selected") or table.concat(parts, ", "))
        text(x + 9, by + 5, open and T.texthi or lerpc(T.text, T.texthi, wd._h), shown, FONT)
        text(x + w - 16, by + 5, open and T.accent or T.textdim, open and "-" or "v", FONT)
        if clicked(x, by, w, bh) then M._combo = open and nil or wd end
        if M._combo == wd then M._dd = { wd = wd, x = x, y = by + bh, w = w, bh = bh } end

    elseif wd.kind == "input" then
        local by, bh = y + 18, 22
        local focused = (M._focus == wd)
        local hov = hovering(x, by, w, bh)
        wd._h = approach(wd._h or 0, (hov or focused) and 1 or 0, 16)
        text(x, y, lerpc(T.text, T.texthi, wd._h), wd.label, FONT)
        rbox(x, by, w, bh, 5, lerpc(T.widget, T.widgethi, wd._h), focused and T.accent or T.border)
        local pad, avail = 9, w - 16
        local tx, ty = x + pad, by + 5
        if wd.value ~= "" or focused then
            local vis, off = inputView(wd, avail)
            if focused then
                local a, b = selBounds(wd)
                if a ~= b then
                    local va = clamp(a, off, off + #vis)
                    local vb = clamp(b, off, off + #vis)
                    local sx = textw(wd.value:sub(off + 1, va))
                    local sw = textw(wd.value:sub(off + 1, vb)) - sx
                    if sw > 0 then
                        rfill(tx + sx - 1, by + 4, mmin(sw + 2, avail), bh - 8, 3,
                              { T.accent[1], T.accent[2], T.accent[3], 110 })
                    end
                end
            end
            text(tx, ty, focused and T.texthi or T.text, vis, FONT)
            if focused and not hasSel(wd) and (floor(now() * 1.6) % 2 == 0) then
                rfill(tx + textw(wd.value:sub(off + 1, wd._caret)), by + 4, 1, bh - 8, 0, T.accent)
            end
        else
            text(tx, ty, T.textdim, wd.placeholder or "", FONT)
        end
        if ms.pressed and not ms.consumed and hovering(x, by, w, bh) then
            ms.consumed = true; M._focus = wd
            local c = caretFromX(wd, ms.x - tx, wd._off or 0)
            wd._caret, wd._anchor, M._inputDrag = c, c, wd
        end
        if M._inputDrag == wd then
            if ms.down and M._focus == wd then
                wd._caret = caretFromX(wd, ms.x - tx, wd._off or 0)
            else
                M._inputDrag = nil
            end
        end
        if focused then pollText(wd, now()) end

    elseif wd.kind == "color" then
        local hov = hovering(x, y, w, 20)
        wd._h = approach(wd._h or 0, hov and 1 or 0, 16)
        text(x, y + 4, lerpc(T.text, T.texthi, wd._h), wd.label, FONT)
        local sw, shh = 32, 14
        local bx, by = x + w - sw, y + 3
        rbox(bx, by, sw, shh, 3,
             { wd.value[1], wd.value[2], wd.value[3], 255 },
             (M._cp == wd) and T.accent or T.border)
        if clicked(bx, by, sw, shh) then
            if M._cp == wd then M._cp = nil
            else M._cp = wd; wd._hsv = { rgb2hsv(wd.value[1], wd.value[2], wd.value[3]) } end
        end
        if M._cp == wd then
            M._cpRect = { x = x, y = y + 24, sx = bx, sy = by, sw = sw, sh = shh }
        end

    elseif wd.kind == "listbox" then
        local ly = y
        if wd.label and wd.label ~= "" then text(x, y, T.text, wd.label, FONT); ly = y + 18 end
        local lh, itemH = (wd._fillH or wd.h), 20
        rbox(x, ly, w, lh, 5, T.bg2, T.border)
        local n = #wd.items
        local visible = floor(lh / itemH)
        local maxScroll = mmax(0, n - visible)
        if (ms.wheel or 0) ~= 0 and hovering(x, ly, w, lh) then
            wd.scroll = wd.scroll - (ms.wheel > 0 and 1 or -1)
            ms.wheel = 0
        end
        wd.scroll = clamp(wd.scroll, 0, maxScroll)
        local hasBar = n > visible
        local listW = hasBar and (w - 9) or w
        for vi = 0, visible - 1 do
            local idx = vi + 1 + floor(wd.scroll)
            if idx <= n then
                local iy = ly + vi * itemH
                local sel = (idx == wd.value)
                local hov = hovering(x + 2, iy, listW - 4, itemH)
                if sel then
                    rfill(x + 3, iy + 1, listW - 6, itemH - 2, 3, T.accent_bg)
                    rfill(x + 3, iy + 1, 2, itemH - 2, 1, T.accent)
                elseif hov then
                    rfill(x + 3, iy + 1, listW - 6, itemH - 2, 3, T.widget)
                end
                text(x + 11, iy + 3, (sel or hov) and T.texthi or T.text, tostring(wd.items[idx]), FONT)
                if clicked(x + 2, iy, listW - 4, itemH) then wd.value = idx end
            end
        end
        if hasBar then
            local trackX = x + w - 6
            local thumbH = mmax(20, lh * visible / n)
            local thumbY = ly + (lh - thumbH) * (maxScroll > 0 and wd.scroll / maxScroll or 0)
            rfill(trackX, ly + 2, 4, lh - 4, 2, T.widget)
            rfill(trackX, thumbY, 4, thumbH, 2, T.widgethi)
            if ms.pressed and not ms.consumed and hovering(trackX - 2, ly, 8, lh) then
                ms.consumed = true; M._scrollbar = wd
            end
            if M._scrollbar == wd then
                if ms.down then wd.scroll = rnd(clamp((ms.y - ly) / lh, 0, 1) * maxScroll)
                else M._scrollbar = nil end
            end
        end

    elseif wd.kind == "custom" then
        if wd.fn then
            UI._x, UI._cy, UI._w = x, y, w
            local ok, err = pcall(wd.fn, UI, x, y, w)
            if not ok then print("[mahanmoi] custom widget error: " .. tostring(err)) end
            local used = UI._cy - y
            wd._measured = used > 0 and used or wd.h
        end
    end
end

-- ============================================================
-- IMMEDIATE MODE HELPERS
-- ============================================================
local function imWidget(id, factory)
    local wd = IM[id]
    if not wd then wd = factory(); IM[id] = wd end
    return wd
end

local function imEmit(wd)
    Section._widget(Section, wd, UI._x, UI._cy, UI._w)
    UI._cy = UI._cy + wheight(wd)
end

function UI.checkbox(id, def)
    local wd = imWidget(id, function()
        return { kind = "check", label = id, value = def and true or false }
    end)
    imEmit(wd); return wd.value
end

function UI.slider(id, def, mn, mx, step, fmt)
    local wd = imWidget(id, function()
        local s = step or 1
        return { kind = "slider", label = id, value = def, min = mn, max = mx, step = s, dec = decimalsOf(s), fmt = fmt }
    end)
    wd.min, wd.max = mn, mx
    imEmit(wd); return wd.value
end

function UI.combo(id, options, def)
    local wd = imWidget(id, function()
        return { kind = "combo", label = id, options = options, value = def or 1 }
    end)
    wd.options = options
    imEmit(wd); return wd.value
end

function UI.button(id)
    local wd = imWidget(id, function()
        return { kind = "button", label = id }
    end)
    wd._clicked = false
    wd.cb = function() wd._clicked = true end
    imEmit(wd); return wd._clicked
end

function UI.colorpicker(id, def)
    local wd = imWidget(id, function()
        local c = def or { 255, 255, 255, 255 }
        return { kind = "color", label = id, value = { c[1], c[2], c[3], c[4] or 255 } }
    end)
    imEmit(wd); return wd.value
end

function UI.label(s, col)
    text(UI._x, UI._cy, col or T.text, tostring(s), FONT)
    UI._cy = UI._cy + 18
end

-- ============================================================
-- LAYOUT: ROWS, COLUMNS, CONTAINERS
-- ============================================================
local function renderSectionAt(s, x, y, w)
    local h = 40
    pcall(function() h = s:height() end)
    if s._layoutH then h = mmax(h, s._layoutH) end
    if clipBottom and y >= clipBottom then return h end
    if clipTop and (y + h) <= clipTop then return h end
    local rh = h
    local ok, err = pcall(function() rh = s:render(x, y, w) or h end)
    if not ok then print("[mahanmoi] section error: " .. tostring(err)); return h end
    return rh
end

local function renderAutoPack(secs, x, y, w, cols)
    cols = cols or 2
    local colW = (w - (cols - 1) * T.pad) / cols
    local colY, colX = {}, {}
    for c = 1, cols do
        colY[c] = y
        colX[c] = x + (c - 1) * (colW + T.pad)
    end
    for _, s in ipairs(secs) do
        local best = 1
        for c = 2, cols do if colY[c] < colY[best] then best = c end end
        colY[best] = colY[best] + renderSectionAt(s, colX[best], colY[best], colW) + T.sec_gap
    end
end

local function renderRows(rows, x, y, w)
    local cy = y
    for _, row in ipairs(rows) do
        local n = #row
        if n > 0 then
            local gap = 8
            local colW = (w - (n - 1) * gap) / n
            -- Pass 1: measure heights
            local colH = {}
            local rowH = 0
            for ci, col in ipairs(row) do
                local h = 0
                for _, s in ipairs(col) do
                    s._layoutH = nil
                    local sh = 40; pcall(function() sh = s:height() end)
                    h = h + sh + T.sec_gap
                end
                colH[ci] = h
                if h > rowH then rowH = h end
            end
            -- Pass 2: stretch fill, render
            for ci, col in ipairs(row) do
                local cxx = x + (ci - 1) * (colW + gap)
                local yy = cy
                local stretch = rowH - colH[ci]
                if stretch > 0 then
                    for _, s in ipairs(col) do
                        if s._hasFill then
                            local sh = 40; pcall(function() sh = s:height() end)
                            s._layoutH = sh + stretch
                            break
                        end
                    end
                end
                for _, s in ipairs(col) do
                    yy = yy + renderSectionAt(s, cxx, yy, colW) + T.sec_gap
                    s._layoutH = nil
                end
            end
            cy = cy + rowH
        end
    end
end

local function renderContainer(cont, x, y, w)
    if cont._rows and #cont._rows > 0 then
        renderRows(cont._rows, x, y, w)
    else
        renderAutoPack(cont.secs, x, y, w, cont._cols)
    end
end

local function measureSecs(secs)
    local total = 0
    for _, s in ipairs(secs) do
        local h = 40; pcall(function() h = s:height() end)
        total = total + h + T.sec_gap
    end
    return total
end

local function containerHeight(cont)
    if cont._rows and #cont._rows > 0 then
        local total = 0
        for _, row in ipairs(cont._rows) do
            local rowH = 0
            for _, col in ipairs(row) do
                local h = measureSecs(col)
                if h > rowH then rowH = h end
            end
            total = total + rowH
        end
        return total
    end
    local cols = cont._cols or 2
    local colY = {}
    for c = 1, cols do colY[c] = 0 end
    for _, s in ipairs(cont.secs) do
        local best = 1
        for c = 2, cols do if colY[c] < colY[best] then best = c end end
        local h = 40; pcall(function() h = s:height() end)
        colY[best] = colY[best] + h + T.sec_gap
    end
    local mx = 0
    for c = 1, cols do if colY[c] > mx then mx = colY[c] end end
    return mx
end

local function tabContentHeight(tab)
    if #tab.subs == 0 then return containerHeight(tab) end
    local sub = tab.subs[tab._activeSub]
    return 28 + T.sec_gap + (sub and containerHeight(sub) or 0)
end

local function addSection(cont, title)
    local s = Section.new(title)
    if cont._rows and #cont._rows > 0 then
        local row = cont._rows[#cont._rows]
        local col = row[#row]
        col[#col + 1] = s
    else
        cont.secs[#cont.secs + 1] = s
    end
    return s
end

local function contRow(cont)
    cont._rows[#cont._rows + 1] = { {} }
    return cont
end

local function contCol(cont)
    if #cont._rows == 0 then cont._rows[#cont._rows + 1] = { {} } end
    local row = cont._rows[#cont._rows]
    row[#row + 1] = {}
    return cont
end

-- ============================================================
-- SUB TAB
-- ============================================================
local Sub = {}
Sub.__index = Sub

function Sub.new(name) return setmetatable({ name = name, secs = {}, _rows = {} }, Sub) end
function Sub:Section(title) return addSection(self, title) end
function Sub:Row() return contRow(self) end
function Sub:Col() return contCol(self) end
function Sub:Columns(n) self._cols = n; return self end

-- ============================================================
-- TAB
-- ============================================================
local Tab = {}
Tab.__index = Tab

function Tab.new(name)
    return setmetatable({
        name = name, secs = {}, subs = {}, _rows = {},
        _activeSub = 1, _subT = 1
    }, Tab)
end

function Tab:Section(title) return addSection(self, title) end
function Tab:Row() return contRow(self) end
function Tab:Col() return contCol(self) end
function Tab:Columns(n) self._cols = n; return self end

function Tab:Sub(name)
    local s = Sub.new(name)
    self.subs[#self.subs + 1] = s
    return s
end

function Tab:render(x, y, w)
    if #self.subs == 0 then
        renderContainer(self, x, y, w)
        return
    end

    local barH = 28
    local sx = x
    local pos, tgtX, tgtW = {}, x, 0
    for i, sub in ipairs(self.subs) do
        local tw = textw(sub.name) + 24
        pos[i] = { x = sx, w = tw }
        if i == self._activeSub then tgtX, tgtW = sx, tw end
        sx = sx + tw
    end

    local relX = tgtX - x
    self._subX = approach(self._subX or relX, relX, 16)
    self._subW = approach(self._subW or tgtW, tgtW, 16)
    rfill(x + self._subX + 6, y + barH - 6, self._subW - 12, 2, 1, T.accent)

    for i, sub in ipairs(self.subs) do
        local p = pos[i]
        local active = (i == self._activeSub)
        local hov = hovering(p.x, y, p.w, barH)
        sub._h = approach(sub._h or 0, (active or hov) and 1 or 0, 16)
        text(p.x + p.w / 2, y + 6, lerpc(T.textdim, T.texthi, sub._h), sub.name, FONT, "center")
        if clicked(p.x, y, p.w, barH) and self._activeSub ~= i then
            self._activeSub = i; self._subT = 0
        end
    end
    rect(x, y + barH, w, 1, T.divider)

    self._subT = self._subT + (1 - self._subT) * clamp(DT * ANIM.tab, 0, 1)
    local e = smooth(self._subT)
    local sub = self.subs[self._activeSub]
    if sub then renderContainer(sub, x + (1 - e) * 16, y + barH + T.sec_gap, w) end
end

-- ============================================================
-- MAIN STATE
-- ============================================================
M._tabs   = {}
M._active = 1
M._win    = { x = T.x, y = T.y, w = T.w, h = T.h }
M._t      = 0
M._tabT   = 1
M._last   = nil
M._toasts = {}
M._notifPos = T.notif_pos
M._onframe = {}

M._hitlog = {
    queue     = {},
    enabled   = true,
    pos       = nil,
    x_off     = 0,
    y_off     = nil,
    font_size = T.font_size,
    life      = 2.8,
    fade_in   = 0.16,
    fade_out  = 0.40,
    max       = 6,
    colors    = {
        miss = { 235, 90, 90 },
        hit  = { 139, 124, 246 },
        hurt = { 245, 170, 70 },
        kill = { 80, 200, 120 },
    },
}

M._watermark = {
    enabled    = false,
    parts      = { cheat = false, lua = true, user = false, nick = true, fps = true, ping = true },
    cheat_name = "AIMWARE.NET",
    lua_name   = "MAHANMOITAP.CC",
    user       = nil,
    nick       = nil,
    ping       = nil,
    pos        = "top-right",
    _fps       = 0,
}

-- ============================================================
-- PUBLIC API: WATERMARK
-- ============================================================
function M:Watermark(on) self._watermark.enabled = on and true or false; return self end

function M:WatermarkSet(opts)
    local wm = self._watermark
    if opts.enabled    ~= nil then wm.enabled = opts.enabled and true or false end
    if opts.cheat_name ~= nil then wm.cheat_name = opts.cheat_name end
    if opts.lua_name   ~= nil then wm.lua_name = opts.lua_name end
    if opts.user       ~= nil then wm.user = opts.user end
    if opts.nick       ~= nil then wm.nick = opts.nick end
    if opts.ping       ~= nil then wm.ping = opts.ping end
    if opts.pos        ~= nil then wm.pos = opts.pos end
    if opts.parts then
        for k, v in pairs(opts.parts) do wm.parts[k] = v and true or false end
    end
    return self
end

function M:OnFrame(fn) self._onframe[#self._onframe + 1] = fn; return self end

function M:Tab(name)
    local t = Tab.new(name)
    self._tabs[#self._tabs + 1] = t
    return t
end

-- ============================================================
-- NOTIFICATIONS
-- ============================================================
local function smoother(x) x = clamp(x, 0, 1); return x * x * x * (x * (x * 6 - 15) + 10) end

function M:Notify(text, kind)
    self._toasts[#self._toasts + 1] = {
        text = tostring(text), kind = kind or "info",
        born = now(), life = T.notif_life
    }
    while #self._toasts > 6 do table.remove(self._toasts, 1) end
end

function M:Info(t)    self:Notify(t, "info")    end
function M:Success(t) self:Notify(t, "success") end
function M:Error(t)   self:Notify(t, "error")   end

function M:SetNotifPos(p) self._notifPos = p end
function M:GetNotifPos() return self._notifPos end

function M:_drawToasts()
    local toasts = self._toasts
    if #toasts == 0 then return end

    local SLIDE_IN, SLIDE_OUT, SLIDE_DIST, GAP = 0.32, 0.45, 24, 8
    local W, M_OFF = T.notif_w, T.notif_margin
    local sw, sh = 0, 0
    pcall(function() sw, sh = draw.GetScreenSize() end)
    if sw == 0 then return end

    local pos   = self._notifPos
    local right = pos:find("right") ~= nil
    local top   = pos:find("top") ~= nil
    local x0    = right and (sw - M_OFF - W) or M_OFF

    -- Cleanup expired
    local i = 1
    while i <= #toasts do
        if (now() - toasts[i].born) >= toasts[i].life + SLIDE_OUT + 0.05 then
            table.remove(toasts, i)
        else
            i = i + 1
        end
    end

    local y = top and M_OFF or (sh - M_OFF)
    local order = {}
    if top then
        for k = 1, #toasts do order[#order + 1] = k end
    else
        for k = #toasts, 1, -1 do order[#order + 1] = k end
    end

    for _, k in ipairs(order) do
        local tw = toasts[k]
        local age = now() - tw.born
        local inE  = smoother(clamp(age / SLIDE_IN, 0, 1))
        local outE = smoother(clamp((age - tw.life) / SLIDE_OUT, 0, 1))
        local dx   = (1 - inE) * SLIDE_DIST + outE * SLIDE_DIST
        local a    = inE * (1 - outE)
        local h    = 46

        local bx = right and (x0 + dx) or (x0 - dx)
        local by = top and y or (y - h)

        ALPHA = a
        local kc = (tw.kind == "success" and T.notif_success)
                 or (tw.kind == "error" and T.notif_error)
                 or T.notif_info
        rbox(bx, by, W, h, 8, T.section, T.border)
        rfill(bx, by, 3, h, 3, kc, true, false, false, true)
        text(bx + 14, by + 9, T.texthi, tw.text, FONT)

        local prog = 1 - clamp(age / tw.life, 0, 1)
        rect(bx + 12, by + h - 9, W - 24, 3, T.widget)
        if prog > 0 then
            rfill(bx + 12, by + h - 9, (W - 24) * prog, 3, 1, kc, true, false, false, true)
        end

        y = top and (y + (h + GAP) * a) or (y - (h + GAP) * a)
    end
end

-- ============================================================
-- HITLOG
-- ============================================================
local HITLOG_TEXT = { miss = "missed", hit = "hit", hurt = "hurt", kill = "killed enemy" }

local function hitlogLabel(e)
    if e.text and e.text ~= "" then return e.text end
    local base = HITLOG_TEXT[e.kind] or e.kind
    if e.dmg then return base .. "  " .. tostring(e.dmg) end
    return base
end

function M:Hitlog(kind, dmg, txt)
    local hl = self._hitlog
    hl.queue[#hl.queue + 1] = {
        kind = tostring(kind or "hit"):lower(),
        dmg  = dmg, text = txt, born = now(),
    }
    while #hl.queue > (hl.max or 6) do table.remove(hl.queue, 1) end
    return self
end

function M:HitlogSet(opts)
    local hl = self._hitlog
    if opts.enabled   ~= nil then hl.enabled   = opts.enabled   end
    if opts.pos       ~= nil then hl.pos       = opts.pos       end
    if opts.x_off     ~= nil then hl.x_off     = opts.x_off     end
    if opts.y_off     ~= nil then hl.y_off     = opts.y_off     end
    if opts.font_size        then hl.font_size = opts.font_size end
    if opts.life             then hl.life      = opts.life      end
    if opts.colors then
        for k, v in pairs(opts.colors) do
            if v then hl.colors[tostring(k):lower()] = v end
        end
    end
    return self
end

function M:HitlogPos() return self._hitlog.x_off or 0, self._hitlog.y_off end
function M:HitlogResetPos()
    self._hitlog.x_off, self._hitlog.y_off = 0, nil
    return self
end

function M:HitlogColor(kind, col)
    if col then self._hitlog.colors[tostring(kind):lower()] = col end
    return self
end

function M:HitlogClear() self._hitlog.queue = {}; return self end

-- ============================================================
-- HITLOG RENDERING
-- ============================================================
local HITLOG_DEMO = {
    { kind = "hit",  label = "hit player in head for 90hp" },
    { kind = "hurt", label = "hurt by player in chest for 20hp" },
    { kind = "miss", label = "missed shot" },
    { kind = "kill", label = "killed player in head for 100hp" },
}

local HL_SNAP_IN, HL_SNAP_OUT, HL_DEAD = 12, 18, 28
local HL_BOTTOM = 160
local function easeOutCubic(t) t = clamp(t, 0, 1); local u = 1 - t; return 1 - u * u * u end

local function hitlogPos(hl, sw, sh)
    local px = sw / 2 + (hl.x_off or 0)
    local py = hl.y_off and (sh / 2 + hl.y_off) or (sh - HL_BOTTOM)
    return px, py
end

local function hitlogDrawEntry(entry, cx, cy, alpha, hl)
    local label = hitlogLabel(entry)
    local col = hl.colors[entry.kind] or hl.colors.hit or T.accent
    ALPHA = alpha
    text(cx, cy, col, label, FONT, "center")
    return 22
end

local function hitlogRenderEntries(entries, cx, startY, hl, sw, sh, t)
    local cy = startY
    local n = #entries
    if n == 0 then return 0 end

    -- Stack upward from startY
    for i = n, 1, -1 do
        local e = entries[i]
        local age = now() - e.born
        local fadeIn  = clamp(age / hl.fade_in, 0, 1)
        local fadeOut = clamp((age - (hl.life - hl.fade_out)) / hl.fade_out, 0, 1)
        local alpha = fadeIn * (1 - fadeOut)
        if alpha <= 0 then goto skip end

        local h = hitlogDrawEntry(e, cx, cy, alpha, hl)
        cy = cy - h
        ::skip::
    end
    return startY - cy
end

function M:_drawHitlog()
    local hl = self._hitlog
    if not hl.enabled then return end

    local sw, sh = 0, 0
    pcall(function() sw, sh = draw.GetScreenSize() end)
    if sw == 0 then return end

    -- Prune expired
    local i = 1
    while i <= #hl.queue do
        if (now() - hl.queue[i].born) >= hl.life + 0.1 then
            table.remove(hl.queue, i)
        else
            i = i + 1
        end
    end

    if #hl.queue == 0 then return end

    local cx, cy = hitlogPos(hl, sw, sh)
    hitlogRenderEntries(hl.queue, cx, cy, hl, sw, sh, now())
end

-- ============================================================
-- WATERMARK RENDERING
-- ============================================================
function M:_drawWatermark()
    local wm = self._watermark
    if not wm.enabled then return end

    local sw, sh = 0, 0
    pcall(function() sw, sh = draw.GetScreenSize() end)
    if sw == 0 then return end

    -- Update FPS
    local ft = 0
    pcall(function() ft = globals.FrameTime() end)
    if ft and ft > 0 then wm._fps = floor(1 / ft) end

    local parts = {}
    if wm.parts.cheat then parts[#parts + 1] = wm.cheat_name or "mahanmoi" end
    if wm.parts.lua   then parts[#parts + 1] = wm.lua_name   or "CS2 Lua" end
    if wm.parts.user   then
        local u = wm.user
        if not u then
            pcall(function()
                local h = ffi.C.GetModuleHandleA("steam_api64.dll")
                if h then
                    local get = ffi.C.GetProcAddress(h, "SteamAPI_ISteamFriends_GetPersonaName")
                    if get then
                        for _, v in ipairs({
                            "SteamAPI_SteamFriends_v017", "SteamAPI_SteamFriends_v018",
                            "SteamAPI_SteamFriends_v019", "SteamAPI_SteamFriends_v016",
                            "SteamAPI_SteamFriends_v020"
                        }) do
                            local acc = ffi.C.GetProcAddress(h, v)
                            if acc then
                                local ok, iface = pcall(function()
                                    return ffi.cast("void*(*)(void)", acc)()
                                end)
                                if ok and iface then
                                    local ok2, name = pcall(function()
                                        local s = ffi.cast("const char*(*)(void*)", get)(iface)
                                        return s and ffi.string(s) or nil
                                    end)
                                    if ok2 and name and #name > 0 and #name < 64 then
                                        u = name; wm.user = name; break
                                    end
                                end
                            end
                        end
                    end
                end
            end)
        end
        if u then parts[#parts + 1] = u end
    end
    if wm.parts.nick then
        local n = wm.nick
        if n then parts[#parts + 1] = n end
    end
    if wm.parts.fps  then parts[#parts + 1] = wm._fps .. "fps" end
    if wm.parts.ping then
        local p = wm.ping
        if p then parts[#parts + 1] = p .. "ms" end
    end

    if #parts == 0 then return end
    local label = table.concat(parts, "  |  ")

    local tw = textw(label) + 20
    local th = 24
    local margin = 12

    local pos = wm.pos or "top-right"
    local right = pos:find("right") ~= nil
    local top   = pos:find("top") ~= nil

    local bx = right and (sw - margin - tw) or margin
    local by = top and margin or (sh - margin - th)

    rbox(bx, by, tw, th, 6, { 12, 12, 18, 200 }, { 112, 72, 170, 140 })
    text(bx + 10, by + 5, T.texthi, label, FONT)
end

-- ============================================================
-- DROPDOWN RENDERING
-- ============================================================
local function renderDropdown()
    local dd = M._dd
    if not dd then return end
    local wd = dd.wd
    local x, y, w = dd.x, dd.y, dd.w

    local n = #wd.options
    if n == 0 then M._dd = nil; return end

    local itemH = 22
    local maxH = 220
    local visible = mmin(n, floor(maxH / itemH))
    local dh = visible * itemH

    -- Clamp to screen
    local sw, sh = 0, 0
    pcall(function() sw, sh = draw.GetScreenSize() end)
    if y + dh > sh - 10 then y = sh - 10 - dh end
    if y < 10 then y = 10 end
    if x + w > sw - 10 then x = sw - 10 - w end

    local maxScroll = mmax(0, n - visible)
    if not dd.scroll then dd.scroll = 0 end
    if (ms.wheel or 0) ~= 0 and hovering(x, y, w, dh) then
        dd.scroll = dd.scroll - (ms.wheel > 0 and 1 or -1)
        ms.wheel = 0
    end
    dd.scroll = clamp(dd.scroll, 0, maxScroll)

    rbox(x, y, w, dh, 5, T.section, T.accent)

    local isMulti = (wd.kind == "multicombo")

    for vi = 0, visible - 1 do
        local idx = vi + 1 + floor(dd.scroll)
        if idx > n then break end
        local iy = y + vi * itemH
        local label = wd.options[idx]
        local sel = isMulti and wd.value[idx] or (idx == wd.value)
        local hov = hovering(x + 2, iy, w - 4, itemH)

        if sel then
            rfill(x + 3, iy + 1, w - 6, itemH - 2, 3, T.accent_bg)
        elseif hov then
            rfill(x + 3, iy + 1, w - 6, itemH - 2, 3, T.widget)
        end

        local col = sel and T.accent or (hov and T.texthi or T.text)
        text(x + 12, iy + 4, col, tostring(label), FONT)

        if isMulti and sel then
            text(x + w - 20, iy + 4, T.accent, "+", FONT)
        end

        if clicked(x + 2, iy, w - 4, itemH) then
            if isMulti then
                wd.value[idx] = not wd.value[idx]
            else
                wd.value = idx
                M._combo = nil
                M._dd = nil
            end
        end
    end

    -- Close on click outside
    if ms.pressed and not hovering(x - 10, y - 10, w + 20, dh + 20) then
        M._combo = nil
        M._dd = nil
    end
end

-- ============================================================
-- COLOR PICKER RENDERING
-- ============================================================
local function renderColorPicker()
    local cp = M._cp
    if not cp then return end
    local r = M._cpRect
    if not r then return end

    local pw, ph = 200, 160
    local px, py = r.x, r.y

    -- Clamp to screen
    local sw, sh = 0, 0
    pcall(function() sw, sh = draw.GetScreenSize() end)
    if px + pw > sw - 10 then px = sw - 10 - pw end
    if py + ph > sh - 10 then py = sh - 10 - ph end
    if px < 10 then px = 10 end
    if py < 10 then py = 10 end

    rbox(px, py, pw, ph, 8, T.section, T.border)

    -- SV area
    local svX, svY, svW, svH = px + 10, py + 10, pw - 20, 90
    local hsv = cp._hsv or { 0, 0, 1 }

    -- Draw SV gradient (simplified: horizontal = S, vertical = V)
    for sx = 0, svW - 1, 4 do
        for sy = 0, svH - 1, 4 do
            local s = sx / svW
            local v = 1 - sy / svH
            local cr, cg, cb = hsv2rgb(hsv[1], s, v)
            rect(svX + sx, svY + sy, 4, 4, { cr, cg, cb, 255 })
        end
    end
    rbox(svX, svY, svW, svH, 4, nil, T.border)

    -- Hue bar
    local hX, hY, hW, hH = px + 10, py + svH + 20, pw - 20, 14
    for hx = 0, hW - 1, 2 do
        local h = hx / hW
        local cr, cg, cb = hsv2rgb(h, 1, 1)
        rect(hX + hx, hY, 2, hH, { cr, cg, cb, 255 })
    end
    rbox(hX, hY, hW, hH, 4, nil, T.border)

    -- Hue indicator
    local hueX = hX + hsv[1] * hW
    rect(hueX - 1, hY - 2, 3, hH + 4, { 255, 255, 255, 255 })

    -- SV indicator
    local svIx = svX + hsv[2] * svW
    local svIy = svY + (1 - hsv[3]) * svH
    rbox(svIx - 4, svIy - 4, 8, 8, 3, nil, { 255, 255, 255, 255 })

    -- Interactions
    if ms.pressed and not ms.consumed then
        if hovering(svX, svY, svW, svH) then
            ms.consumed = true
            hsv[2] = clamp((ms.x - svX) / svW, 0, 1)
            hsv[3] = clamp(1 - (ms.y - svY) / svH, 0, 1)
        elseif hovering(hX, hY, hW, hH) then
            ms.consumed = true
            hsv[1] = clamp((ms.x - hX) / hW, 0, 1) % 1
        end
    end

    -- Drag SV
    if ms.down and M._cpDrag == "sv" then
        hsv[2] = clamp((ms.x - svX) / svW, 0, 1)
        hsv[3] = clamp(1 - (ms.y - svY) / svH, 0, 1)
    end
    if ms.down and M._cpDrag == "hue" then
        hsv[1] = clamp((ms.x - hX) / hW, 0, 1) % 1
    end

    if ms.pressed and hovering(svX, svY, svW, svH) then M._cpDrag = "sv" end
    if ms.pressed and hovering(hX, hY, hW, hH) then M._cpDrag = "hue" end
    if not ms.down then M._cpDrag = nil end

    -- Update color
    local cr, cg, cb = hsv2rgb(hsv[1], hsv[2], hsv[3])
    cp.value[1] = cr
    cp.value[2] = cg
    cp.value[3] = cb
    cp.value[4] = 255
    cp._hsv = hsv

    -- Close on outside click
    if ms.pressed and not hovering(px - 5, py - 5, pw + 10, ph + 10) then
        M._cp = nil
    end
end

-- ============================================================
-- MAIN RENDER
-- ============================================================
local function renderTitlebar(x, y, w)
    rbox(x, y, w, T.titlebar, 8, T.bg, T.border)
    text(x + 14, y + 13, T.accent, T.title, FONT_LOGO)
    text(x + 14 + textw(T.title) + 2, y + 13, T.textdim, T.title_tld, FONT_LOGO)

    -- Close button
    local cbX = x + w - 34
    local cbY = y + 10
    if hovering(cbX, cbY, 22, 22) then
        rfill(cbX, cbY, 22, 22, 4, { 200, 60, 60, 180 })
    end
    text(cbX + 6, cbY + 4, { 255, 255, 255, 200 }, "X", FONT_B)
    if clicked(cbX, cbY, 22, 22) then
        M._visible = false
    end
end

local function renderTabBar(x, y, w)
    local tabs = M._tabs
    if #tabs == 0 then return T.titlebar end

    local tx = x
    local pos = {}
    for i, tab in ipairs(tabs) do
        local tw = textw(tab.name) + 28
        pos[i] = { x = tx, w = tw }
        tx = tx + tw
    end

    local barH = T.titlebar
    rbox(x, y, w, barH, 8, T.bg, T.border)

    -- Active indicator
    local active = tabs[M._active]
    if active then
        local ap = pos[M._active]
        M._tabX = approach(M._tabX or ap.x, ap.x, 16)
        M._tabW = approach(M._tabW or ap.w, ap.w, 16)
        rfill(x + M._tabX + 6, y + barH - 4, M._tabW - 12, 2, 1, T.accent)
    end

    for i, tab in ipairs(tabs) do
        local p = pos[i]
        local isAct = (i == M._active)
        local hov = hovering(p.x, y, p.w, barH)
        tab._h = approach(tab._h or 0, (isAct or hov) and 1 or 0, 16)
        text(p.x + p.w / 2, y + 13, lerpc(T.textdim, T.texthi, tab._h), tab.name, FONT, "center")
        if clicked(p.x, y, p.w, barH) and M._active ~= i then
            M._active = i; M._tabT = 0
        end
    end

    return barH
end

function M:_render()
    -- Run on-frame callbacks
    for _, fn in ipairs(self._onframe) do
        pcall(fn)
    end

    local win = self._win
    local x, y, w, h = win.x, win.y, win.w, win.h

    -- Window background
    rbox(x, y, w, h, 10, T.bg, T.border)

    -- Titlebar
    local barH = renderTabBar(x, y, w)

    -- Tab content
    self._tabT = self._tabT + (1 - self._tabT) * clamp(DT * ANIM.open, 0, 1)
    local e = smooth(self._tabT)

    clipTop = y + barH
    clipBottom = y + h

    local contentY = y + barH + 6
    local contentH = h - barH - 6

    if contentH > 0 then
        local tab = self._tabs[self._active]
        if tab then
            ALPHA = e
            tab:render(x + 10, contentY, w - 20)
            ALPHA = 1
        end
    end

    clipTop = nil
    clipBottom = nil

    -- Dropdown (on top of everything)
    renderDropdown()

    -- Color picker
    renderColorPicker()

    -- Toasts
    self:_drawToasts()

    -- Hitlog
    self:_drawHitlog()

    -- Watermark
    self:_drawWatermark()
end

-- ============================================================
-- TOGGLE & DRAG
-- ============================================================
M._visible = true
M._dragging = false
M._dragOff = { x = 0, y = 0 }

local MENU_KEY = 0x7A -- F11

function M:Toggle()
    self._visible = not self._visible
    return self
end

function M:SetKey(k) MENU_KEY = k; return self end

local function checkToggle()
    if keyPressed(MENU_KEY) then
        M._visible = not M._visible
    end
end

local function checkDrag()
    local win = M._win
    if ms.pressed and not ms.consumed and hovering(win.x, win.y, win.w, T.titlebar) then
        ms.consumed = true
        M._dragging = true
        M._dragOff.x = ms.x - win.x
        M._dragOff.y = ms.y - win.y
    end
    if M._dragging then
        if ms.down then
            win.x = ms.x - M._dragOff.x
            win.y = ms.y - M._dragOff.y
        else
            M._dragging = false
        end
    end
end

-- ============================================================
-- MAIN FRAME CALLBACK
-- ============================================================
local _lastTime = 0
local _fontCo = nil
local _fontsReady = false

local function onFrame()
    local t = now()
    DT = mmin(t - _lastTime, 0.1)
    _lastTime = t

    -- Font init coroutine
    if not _fontsReady then
        if not _fontCo then
            _fontCo = coroutine.create(fontInitCoro)
        end
        if _fontCo then
            local ok = coroutine.resume(_fontCo)
            if not ok or coroutine.status(_fontCo) == "dead" then
                _fontsReady = true
                if not FONT then initFonts() end
            end
        end
    end

    -- Resolve input methods once
    if not _getMouse then _getMouse = resolveMouse() end
    if not _clock   then _clock   = resolveClock() end
    if not _getWheel then _getWheel = resolveWheel() end

    updateMouse()
    checkToggle()
    checkDrag()

    if M._visible and FONT then
        M:_render()
    end

    -- Always render toasts/hitlog/watermark even when menu is hidden
    if not M._visible and FONT then
        M:_drawToasts()
        M:_drawHitlog()
        M:_drawWatermark()
    end
end

-- ============================================================
-- INIT
-- ============================================================
local function init()
    initFonts()

    -- Register callback
    local registered = false

    if client and client.register_callback then
        pcall(function()
            client.register_callback("paint_ui", onFrame)
            registered = true
        end)
    end

    if not registered and client_set_event_callback then
        pcall(function()
            client_set_event_callback("paint_ui", onFrame)
            registered = true
        end)
    end

    if not registered and callbacks and callbacks.Register then
        pcall(function()
            callbacks.Register("Draw", onFrame)
            registered = true
        end)
    end

    if not registered then
        pcall(function()
            client.register_callback("paint", onFrame)
            registered = true
        end)
    end

    if registered then
        print("[mahanmoi] guilib v" .. M.VERSION .. " initialized")
    else
        print("[mahanmoi] guilib WARNING: no paint callback registered")
        -- Expose for manual calling
        M._frame = onFrame
    end
end

init()

return M
