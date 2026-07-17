local M = {}
M.VERSION = "1.0_Glass"

-- ۱. پالت رنگی بازطراحی شده بر اساس سبک Premium Glassmorphism & Purple RGB
local T = {
    x = 360, y = 200, w = 600, h = 440,

    -- بنفش نئونی خیره‌کننده به عنوان رنگ اکستنت اصلی
    accent    = { 150, 110, 255, 255 },
    accent_bg = { 50, 40, 90, 180 },  -- بنفش نیمه‌شفاف برای المان‌های فعال
    
    -- رنگ‌های شیشه‌ای تیره (با آلفای پایین برای ایجاد شفافیت شیشه‌ای)
    bg        = { 13, 13, 18, 160 },   -- شیشه دودی تیره پس‌زمینه
    bg2       = { 8, 8, 12, 180 },     -- شیشه تیره‌تر داخلی
    section   = { 20, 18, 28, 110 },   -- بخش‌ها (نیمه شفاف شیشه‌ای)
    
    -- حاشیه‌های ظریف نوری بجای خطوط خشن
    border    = { 150, 110, 255, 45 },  -- مرز شیشه نئونی بنفش با آلفای بسیار ملایم
    divider   = { 150, 110, 255, 30 },  -- جداکننده ظریف نوری
    
    -- رنگ متون ارتقا یافته با کنتراست نئونی
    text      = { 200, 195, 220, 255 },
    textdim   = { 130, 125, 150, 255 },
    texthi    = { 255, 255, 255, 255 },
    
    -- ویجت‌های شیشه‌ای
    widget    = { 25, 22, 38, 120 },
    widgethi  = { 40, 35, 60, 160 },

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
    notif_info    = { 150, 110, 255 },
    notif_success = { 80, 220, 150 },
    notif_error   = { 255, 90, 110 },
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

local function setcol(c) draw.Color(c[1], c[2], c[3], rnd((c[4] or 255) * ALPHA)) end

local function rect(x, y, w, h, c)
    setcol(c); draw.FilledRect(rnd(x), rnd(y), rnd(x + w), rnd(y + h))
end

-- ۲. رندرکردن گوشه‌های شیک و گرد به سبک متریال دیزاین (Soft Glass)
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

-- ۳. ایجاد افکت درخشش نور مخفی (Glow Effect) بنفش در حاشیه‌ها
local function rglow(x, y, w, h, r, intensity, glow_col)
    local gc = { glow_col[1], glow_col[2], glow_col[3] }
    for i = 1, intensity do
        local alpha = rnd(15 * (1 - (i / intensity)))
        rfill(x - i, y - i, w + (i * 2), h + (i * 2), r + i, { gc[1], gc[2], gc[3], alpha })
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

local function textw(s) local w = draw.GetTextSize(s); return w or 0 end

local function text(x, y, c, s, font, align)
    if font then draw.SetFont(font) end
    if align == "center" then x = x - textw(s) / 2
    elseif align == "right" then x = x - textw(s) end
    setcol(c); draw.Text(rnd(x), rnd(y), s)
end

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
local function now() if _clock then local ok, v = pcall(_clock); if ok then return v end end return 0 end

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
local function readWheel() if _getWheel then local ok, v = pcall(_getWheel); if ok and type(v) == "number" then return v end end return 0 end

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
    screen = function() local w, h = 0, 0; pcall(function() w, h = draw.GetScreenSize() end); return w, h end,
}

local Section = {}
Section.__index = Section
function Section.new(title) return setmetatable({ title = title, ws = {} }, Section) end
function Section:_add(w) self.ws[#self.ws + 1] = w; return handle(w) end

function Section:Checkbox(label, def) return self:_add({ kind = "check", label = label, value = def and true or false }) end
function Section:Button(label, cb) return self:_add({ kind = "button", label = label, cb = cb }) end
function Section:Slider(label, def, mn, mx, step, fmt)
    step = step or 1
    return self:_add({ kind = "slider", label = label, value = def, min = mn, max = mx, step = step, dec = decimalsOf(step), fmt = fmt })
end
function Section:SliderFloat(label, def, mn, mx, fmt, step) return self:Slider(label, def, mn, mx, step or 0.01, fmt) end
function Section:Combo(label, options, def) return self:_add({ kind = "combo", label = label, options = options, value = def or 1 }) end
function Section:MultiCombo(label, options, defaults)
    local sel = {}
    if defaults then for _, i in ipairs(defaults) do sel[i] = true end end
    return self:_add({ kind = "multicombo", label = label, options = options, value = sel })
end
function Section:Input(label, def, placeholder) return self:_add({ kind = "input", label = label, value = def or "", placeholder = placeholder }) end
function Section:ColorPicker(label, col)
    col = col or { 255, 255, 255, 255 }
    return self:_add({ kind = "color", label = label, value = { col[1], col[2], col[3], col[4] or 255 } })
end
function Section:Listbox(label, items, height, def)
    local fill = (height == "fill")
    if fill then self._hasFill = true end
    return self:_add({ kind = "listbox", label = label, items = items or {}, value = def or 1, h = fill and 120 or (height or 200), fill = fill, scroll = 0 })
end
function Section:Custom(height, fn) return self:_add({ kind = "custom", h = height or 60, fn = fn }) end
function Section:height()
    local h = 42 + 10
    for _, wd in ipairs(self.ws) do h = h + wheight(wd) end
    return h
end

-- ۴. بازطراحی رندرینگ سکشن‌ها به صورت شیشه‌ای با لبه‌های بسیار نرم
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
            rbox(x, drawY, w, drawH, 10, T.section, T.border)
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
        if visible then
            self:_widget(wd, ix, iy, iw)
        end
        iy = iy + wh
        if clipBottom and iy >= clipBottom then break end
    end
    return h
end

-- ۵. رندرینگ ویجت‌ها با توجه به تم نئونی و هاور‌های نرم
function Section:_widget(wd, x, y, w)
    if wd.kind == "check" then
        local box = 15
        local by  = y + 1
        local hov = hovering(x, by, w, box)
        wd._h  = approach(wd._h or 0, hov and 1 or 0, 16)
        wd._on = approach(wd._on or 0, wd.value and 1 or 0, 16)
        local fill = lerpc(lerpc(T.widget, T.widgethi, wd._h), T.accent_bg, wd._on)
        rbox(x, by, box, box, 5, fill, lerpc(T.border, T.accent, wd._on))
        text(x + box + 9, y + 2, lerpc(T.text, T.texthi, mmax(wd._h, wd._on)), wd.label, FONT)
        if clicked(x, by, w, box) then wd.value = not wd.value end

    elseif wd.kind == "button" then
        local bh  = 22
        local hov = hovering(x, y + 1, w, bh)
        wd._h = approach(wd._h or 0, hov and 1 or 0, 16)
        rbox(x, y + 1, w, bh, 8, lerpc(T.widget, T.widgethi, wd._h), lerpc(T.border, T.accent, wd._h))
        text(x + w / 2, y + 6, lerpc(T.text, T.texthi, wd._h), wd.label, FONT, "center")
        if clicked(x, y + 1, w, bh) then
            local ok, err = pcall(wd.cb); if not ok then print("[mahanmoi] button error: " .. tostring(err)) end
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
        rbox(x, ty, w, th, 4, lerpc(T.widget, T.widgethi, wd._h), T.border)
        if frac > 0 then rfill(x, ty, mmax(th, w * frac), th, 4, T.accent, true, false, false, true) end
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
        rbox(x, by, w, bh, 8, lerpc(T.widget, T.widgethi, wd._h), open and T.accent or T.border)
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
        rbox(x, by, w, bh, 8, lerpc(T.widget, T.widgethi, wd._h), open and T.accent or T.border)
        local parts, count = {}, 0
        for i, o in ipairs(wd.options) do if wd.value[i] then count = count + 1; parts[#parts + 1] = o end end
        local shown = count == 0 and "None" or (count > 2 and (count .. " selected") or table.concat(parts, ", "))
        text(x + 9, by + 5, open and T.texthi or lerpc(T.text, T.texthi, wd._h), shown, FONT)
        text(x + w - 16, by + 5, open and T.accent or T.textdim, open and "-" or "v", FONT)
        if clicked(x, by, w, bh) then M._combo = open and nil or wd end
        if M._combo == wd then M._dd = { wd = wd, x = x, y = by + bh, w = w, bh = bh } end

    elseif wd.kind == "listbox" then
        local ly = y
        if wd.label and wd.label ~= "" then text(x, y, T.text, wd.label, FONT); ly = y + 18 end
        local lh, itemH = (wd._fillH or wd.h), 20
        rbox(x, ly, w, lh, 8, T.bg2, T.border)
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
                    rfill(x + 3, iy + 1, listW - 6, itemH - 2, 4, T.accent_bg)
                    rfill(x + 3, iy + 1, 2, itemH - 2, 1, T.accent)
                elseif hov then
                    rfill(x + 3, iy + 1, listW - 6, itemH - 2, 4, T.widget)
                end
                text(x + 11, iy + 3, (sel or hov) and T.texthi or T.text, tostring(wd.items[idx]), FONT)
                if clicked(x + 2, iy, listW - 4, itemH) then wd.value = idx end
            end
        end
    end
end

-- ۶. رندرکردن پنل کلی منو به صورت کاملاً شیشه‌ای و نئونی مدرن
function M:_frame()
    -- درخشش هاله نوری بنفش (Ambient Backlight Glow)
    rglow(T.x, T.y, T.w, T.h, 14, 15, T.accent)

    -- بدنه اصلی منوی شیشه‌ای نیمه شفاف
    rbox(T.x, T.y, T.w, T.h, 14, T.bg, T.border)

    -- تایتل بار بالایی منو همراه با لوگوی سفارشی
    local title_w = textw(T.title)
    text(T.x + 16, T.y + 13, T.texthi, T.title, FONT_LOGO)
    text(T.x + 16 + title_w, T.y + 13, T.accent, T.title_tld, FONT_LOGO)

    -- جداکننده ظریف و درخشان زیر هدر
    rect(T.x + 16, T.y + T.titlebar - 1, T.w - 32, 1, T.divider)

    -- تب‌های بالایی منو با انیمیشن‌های هاور شیک
    local tabX = T.x + 16 + title_w + 50
    for i, tab in ipairs(self._tabs) do
        local tw = textw(tab.name)
        local hov = hovering(tabX, T.y + 10, tw + 20, 24)
        local active = (self._activeTab == i)
        
        if active then
            rfill(tabX, T.y + 8, tw + 20, 26, 6, T.accent_bg)
            text(tabX + 10, T.y + 13, T.texthi, tab.name, FONT_B)
        else
            if hov then
                rfill(tabX, T.y + 8, tw + 20, 26, 6, T.widget)
            end
            text(tabX + 10, T.y + 13, hov and T.texthi or T.textdim, tab.name, FONT)
        end
        if clicked(tabX, T.y + 8, tw + 20, 26) then self._activeTab = i end
        tabX = tabX + tw + 30
    end

    -- رندر سکشن‌ها به صورت ستون‌های قرینه و داینامیک
    local activeTab = self._tabs[self._activeTab]
    if activeTab then
        local colW = (T.w - (T.pad * 2) - T.sec_gap) / 2
        local leftY = T.y + T.titlebar + T.pad
        local rightY = T.y + T.titlebar + T.pad
        
        for _, sec in ipairs(activeTab.sections) do
            if sec.col == 1 then
                leftY = leftY + sec:render(T.x + T.pad, leftY, colW) + T.sec_gap
            else
                rightY = rightY + sec:render(T.x + T.pad + colW + T.sec_gap, rightY, colW) + T.sec_gap
            end
        end
    end
end

-- ۷. توابع مدیریت چرخه حیات (Framework Lifecycle & Callbacks)
function M:Init()
    _getMouse = resolveMouse()
    _clock    = resolveClock()
    _getWheel = resolveWheel()

    self._open      = true
    self._activeTab = 1
    self._tabs      = {}
    self._onframe   = {}
    self._toasts    = {}
    self._t         = 0

    initFonts()
    self._initco = coroutine.create(fontInitCoro)

    -- ثبت هوک فریمورک اصلی در موتور بازی/اجراکننده
    pcall(function() callbacks.Register("Draw", function() self:_draw() end) end)
    pcall(function() callbacks.Register("CreateMove", function(cmd)
        if not (self._open and self._focus) or not cmd then return end
        pcall(function() cmd.forwardmove = 0 end)
        pcall(function() cmd.sidemove = 0 end)
        pcall(function() cmd.upmove = 0 end)
        pcall(function() cmd.buttons = 0 end)
        pcall(function() cmd:SetForwardMove(0) end)
        pcall(function() cmd:SetSideMove(0) end)
        pcall(function() cmd:SetUpMove(0) end)
    end) end)
end

function M:_draw()
    DT = 0.015 -- مقدار فرضی برای زمان مابین فریم‌ها
    local open = self._open
    self._t = approach(self._t, open and 1 or 0, 12)
    ALPHA = smooth(self._t)

    if self._initco then
        pcall(function()
            if coroutine.status(self._initco) ~= "dead" then coroutine.resume(self._initco) end
        end)
        if coroutine.status(self._initco) == "dead" then self._initco = nil end
        return
    end

    updateMouse()

    if not open and self._t < 0.005 then self._t = 0; return end

    local ok, err = pcall(function() self:_frame() end)
    if not ok then print("[mahanmoi] frame error: " .. tostring(err)) end
end

function M:Tab(name)
    local t = { name = name, sections = {} }
    self._tabs[#self._tabs + 1] = t
    return {
        Section = function(_, title, col)
            local s = Section.new(title)
            s.col = col or 1
            t.sections[#t.sections + 1] = s
            return s
        end
    }
end

return M
