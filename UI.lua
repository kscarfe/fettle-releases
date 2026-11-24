-- Fettle: main window (Checklist, Wish list, Alts, Options) in the Forgeplate theme.
local _, ns = ...
local T = ns.T

local UI = {}
ns.UI = UI

local W, H = 880, 580
local NAV = 92
local CW = W - NAV - 20          -- content width
local LISTW = CW - 40            -- list row width

local C = T.Color
local function lower(s) return s and string.lower(s) or "" end

function UI.CharName(c)
  return C(T.CLASS_HEX[c.class or ""] or "ffffff", ns.DisplayName(c))
end

---------------------------------------------------------------------------
-- Selection and role helpers
---------------------------------------------------------------------------
function UI.Selected()
  local key = UI.selectedKey
  local c = key and ns.db.chars[key]
  if not c then c = ns.Me(); UI.selectedKey = c.key end
  return ns.GetChar(c.key)
end

function UI.CycleAlt(dir)
  local keys = {}
  for k in pairs(ns.db.chars) do keys[#keys + 1] = k end
  table.sort(keys)
  local cur = UI.Selected().key
  local idx = 1
  for i, k in ipairs(keys) do if k == cur then idx = i end end
  idx = ((idx - 1 + dir) % #keys) + 1
  UI.selectedKey = keys[idx]
  UI.Refresh()
end

local ROLE_ORDER = { false, "TANK", "HEALER", "MELEE", "RANGED", "CASTER", "BANK" }
function UI.CycleRole(c)
  local cur = c.roleOverride or false
  local idx = 1
  for i = 2, #ROLE_ORDER do if ROLE_ORDER[i] == cur then idx = i end end
  idx = idx % #ROLE_ORDER + 1
  c.roleOverride = ROLE_ORDER[idx] or nil
  ns.Changed("char")
end

local function SpecText(c)
  return (c.spec and c.spec ~= c.className) and c.spec or nil
end

---------------------------------------------------------------------------
-- Sources as stamped tags
---------------------------------------------------------------------------
function UI.SourceTags(row)
  local s = row.sources or {}
  local tags = {}
  if row.status == "ready" then return { { "Packed", "faint" } } end
  if (s.bank or 0) > 0 then tags[#tags + 1] = { "Bank " .. s.bank, "blue" } end
  if (s.mail or 0) > 0 then tags[#tags + 1] = { "Mail " .. s.mail, "blue" } end
  for _, a in ipairs(s.alts or {}) do tags[#tags + 1] = { a.name .. " " .. a.n, "parch" } end
  for _, cr in ipairs(s.crafters or {}) do
    local star = ns.IsMain(cr.char, cr.prof) and " *" or ""
    tags[#tags + 1] = { "Craft · " .. cr.name .. star, "craft" }
  end
  if s.vendor then tags[#tags + 1] = { "Vendor", "dim" } end
  if #tags > 4 then
    local extra = #tags - 3
    tags = { tags[1], tags[2], tags[3], { "+" .. extra .. " more", "faint" } }
  end
  return tags
end

-- Plain text version (tooltips, tests).
function UI.SourceText(row)
  local parts = {}
  local s = row.sources or {}
  if (s.bank or 0) > 0 then parts[#parts + 1] = "Bank " .. s.bank end
  if (s.mail or 0) > 0 then parts[#parts + 1] = "Mail " .. s.mail end
  for _, a in ipairs(s.alts or {}) do parts[#parts + 1] = a.name .. " " .. a.n end
  for _, cr in ipairs(s.crafters or {}) do parts[#parts + 1] = "Craft: " .. cr.name .. " (" .. cr.prof .. ")" end
  if s.vendor then parts[#parts + 1] = "Vendor" end
  return table.concat(parts, " | ")
end

local function LineTip(row, c)
  local tip = { row.label }
  local cat = row.line and ns.ref.categories[row.line.cat]
  if cat then
    if cat.note then tip[#tip + 1] = cat.note end
    local usable, other = {}, {}
    for _, r in ipairs(cat.ranks or {}) do
      local txt = r.n .. (r.lvl and (" (" .. r.lvl .. ")") or " (level ?)")
      if r.skill then txt = txt .. " [" .. r.skill[1] .. " " .. r.skill[2] .. "]" end
      if ns.RankUsable(r, c) then usable[#usable + 1] = txt else other[#other + 1] = txt end
    end
    if #usable > 0 then tip[#tip + 1] = "Usable now: " .. table.concat(usable, ", ") end
    if #other > 0 then tip[#tip + 1] = "Later: " .. table.concat(other, ", ") end
  end
  local src = UI.SourceText(row)
  if src ~= "" then tip[#tip + 1] = "Get it from: " .. src end
  for _, cr in ipairs((row.sources and row.sources.crafters) or {}) do
    local mats = {}
    for _, r in ipairs(cr.rec.reagents or {}) do mats[#mats + 1] = (r.c or 1) .. "x " .. (r.n or "?") end
    if #mats > 0 then tip[#tip + 1] = cr.name .. " makes " .. cr.item .. " from " .. table.concat(mats, ", ") end
  end
  return tip
end

local function StarterQty(c, cat)
  for _, l in ipairs(ns.Starter(c)) do if l.cat == cat then return l.qty end end
  return nil
end

---------------------------------------------------------------------------
-- Pickers (copy kit from, add a category)
---------------------------------------------------------------------------
function UI.Pick(title, entries, onPick, onCreate)
  local f = UI.picker
  if not f then
    f = T.Frame(UIParent, "FettlePicker")
    f:SetSize(300, 420)
    T.Iron(f)
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f.title = T.Text(f, "Name", "title")
    f.title:SetPoint("TOPLEFT", 16, -14)
    local close = T.IconButton(f, "icon-close.tga", 22, "Close", function() f:Hide() end)
    close:SetPoint("TOPRIGHT", -12, -10)
    local box = T.Frame(f)
    box:SetPoint("TOPLEFT", 12, -42)
    box:SetPoint("BOTTOMRIGHT", -12, 12)
    T.Slot(box)
    f.list = T.List(box, {
      pick = { height = 30, create = function(r)
        r.fs = T.Text(r, "Bold", "text"); r.fs:SetPoint("LEFT", 8, 4)
        r.sub = T.Text(r, "Small", "dim"); r.sub:SetPoint("LEFT", 8, -8)
        r.line = T.Line(r); r.line:SetPoint("BOTTOMLEFT"); r.line:SetPoint("BOTTOMRIGHT")
        local hl = r:CreateTexture(nil, "HIGHLIGHT"); hl:SetColorTexture(1, 0.85, 0.6, 0.08); hl:SetAllPoints()
      end, fill = function(r, e)
        r.fs:SetText(e.text); r.sub:SetText(e.detail or "")
        if e.detail then r.fs:SetPoint("LEFT", 8, 5) else r.fs:SetPoint("LEFT", 8, 0) end
        r:SetScript("OnClick", function() f:Hide(); if f.onPick then f.onPick(e.value) end end)
      end },
    }, 236)
    f.box = box
    f.newName = T.Edit(f, 180); f.newName:SetPoint("BOTTOMLEFT", 12, 12); f.newName:SetPlaceholder("New category name")
    f.newBtn = T.Button(f, "Create", 84, function()
      local n = ns.Trim(f.newName:GetText())
      if n ~= "" and f.onCreate then f.newName:SetText(""); f:Hide(); f.onCreate(n) end
    end)
    f.newBtn:SetPoint("LEFT", f.newName, "RIGHT", 6, 0)
    if UISpecialFrames then table.insert(UISpecialFrames, "FettlePicker") end
    UI.picker = f
  end
  f.onCreate = onCreate
  f.onPick = onPick
  f.box:ClearAllPoints()
  f.box:SetPoint("TOPLEFT", 12, -42)
  if onCreate then
    f.newName:Show(); f.newBtn:Show()
    f.box:SetPoint("BOTTOMRIGHT", -12, 44)
  else
    f.newName:Hide(); f.newBtn:Hide()
    f.box:SetPoint("BOTTOMRIGHT", -12, 12)
  end
  f.title:SetText(title)
  local list = {}
  for _, e in ipairs(entries) do list[#list + 1] = { kind = "pick", text = e.text, detail = e.detail, value = e.value } end
  f.list:Render(list)
  f:ClearAllPoints()
  if UI.frame and UI.frame:IsShown() then f:SetPoint("TOPLEFT", UI.frame, "TOPRIGHT", 6, 0) else f:SetPoint("CENTER") end
  f:Show()
  return f
end

local function CategoryEntries()
  local out = {}
  for _, key in ipairs(ns.CategoryKeys()) do out[#out + 1] = { text = ns.ref.categories[key].name, value = key } end
  return out
end

---------------------------------------------------------------------------
-- Window, nav tabs, header
---------------------------------------------------------------------------
UI.tabs, UI.panels = {}, {}
local TABS = {
  { "Checklist", "tab-checklist.tga" }, { "Wish list", "tab-wish.tga" }, { "Crafting", "icon-fire.tga" },
  { "Alts", "tab-alts.tga" }, { "Options", "tab-options.tga" },
}

local function Header(f)
  local h = T.Frame(f)
  h:SetPoint("TOPLEFT", NAV, -14)
  h:SetPoint("TOPRIGHT", -20, -14)
  h:SetHeight(54)
  T.Stone(h)
  local title = T.Text(h, "Title", "title")
  title:SetPoint("LEFT", 16, 0)
  title:SetText("FETTLE")
  if title.SetShadowColor then title:SetShadowOffset(0, -1); title:SetShadowColor(0, 0, 0, 0.9) end
  local div = h:CreateTexture(nil, "ARTWORK")
  div:SetColorTexture(0, 0, 0, 0.5)
  div:SetSize(1, 30)
  div:SetPoint("LEFT", title, "RIGHT", 14, 0)
  h.prev = T.IconButton(h, "icon-left.tga", 26, "Previous alt", function() UI.CycleAlt(-1) end)
  h.prev:SetPoint("LEFT", div, "RIGHT", 12, 0)
  h.name = T.Text(h, "Name", "parch")
  h.name:SetPoint("TOPLEFT", h.prev, "TOPRIGHT", 10, 4)
  h.info = T.Text(h, "Small", "soft")
  h.info:SetPoint("TOPLEFT", h.name, "BOTTOMLEFT", 0, -2)
  h.badge = T.Tag(h)
  h.badge:SetPoint("LEFT", h.name, "RIGHT", 8, 0)
  h.badge:Hide()
  h.next = T.IconButton(h, "icon-right.tga", 26, "Next alt", function() UI.CycleAlt(1) end)
  -- right-side action slots
  h.actions = {}
  return h
end

local function SetHeader(c, showSelector)
  local h = UI.header
  if showSelector then
    h.prev:Show(); h.next:Show()
    h.name:SetText(UI.CharName(c))
    local spec = SpecText(c)
    h.info:SetText((c.level or "?") .. " " .. (c.className or "?") .. (spec and (" · " .. spec) or "") ..
      " · " .. C("brass", ns.ROLE_NAMES[ns.RoleOf(c)]) .. (c.roleOverride and "" or C("faint", " (auto)")))
    local mains = ns.MainProfs(c)
    if #mains > 0 then
      h.badge:Set("* " .. ns.MainNoun(mains[1]) .. (#mains > 1 and (" +" .. (#mains - 1)) or ""), "brass")
    elseif ns.IsBank(c) then h.badge:Set("bank alt", "brass")
    else h.badge:Hide() end
    h.next:ClearAllPoints()
    local w = math.max(T.Width(h.name, 80) + (h.badge:IsShown() and (T.Width(h.badge.fs, 60) + 18) or 0), T.Width(h.info, 120))
    h.next:SetPoint("LEFT", h.prev, "RIGHT", 18 + w, 0)
  else
    h.prev:Hide(); h.next:Hide(); h.badge:Hide()
  end
end

local function SetActions(list)
  local h = UI.header
  for _, b in ipairs(h.actions) do b:Hide() end
  local x = -12
  for i = #list, 1, -1 do
    local a = list[i]
    local b = a.button
    b:SetParent(h)
    b:ClearAllPoints()
    b:SetPoint("RIGHT", h, "RIGHT", x, 0)
    b:Show()
    x = x - (b:GetWidth() or 80) - 6
    h.actions[#h.actions + 1] = b
  end
end

function UI.Create()
  if UI.frame then return UI.frame end
  local f = T.Frame(UIParent, "FettleFrame")
  f:SetSize(W, H)
  f:SetPoint("CENTER")
  T.Iron(f)
  f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f:SetFrameStrata("HIGH")
  f:SetClampedToScreen(true)
  if UISpecialFrames then table.insert(UISpecialFrames, "FettleFrame") end
  f:Hide()
  UI.frame = f

  local close = T.IconButton(f, "icon-close.tga", 20, "Close", function() f:Hide() end)
  close:SetPoint("TOPRIGHT", -22, -2)
  close:SetFrameLevel((f:GetFrameLevel() or 1) + 10)

  UI.header = Header(f)

  local y = -84
  for i, t in ipairs(TABS) do
    local b = T.Frame(f, nil, "Button")
    b:SetSize(NAV - 16, 58)
    b:SetPoint("TOPLEFT", 12, y)
    y = y - 64
    local ic = T.Icon(b, t[2], 22, "faint")
    ic:SetPoint("TOP", 0, -9)
    local fs = T.Text(b, "SCSmall", "faint")
    fs:SetPoint("BOTTOM", 0, 9)
    fs:SetJustifyH("CENTER")
    fs:SetText(t[1])
    b.icon, b.fs = ic, fs
    local hl = b:CreateTexture(nil, "HIGHLIGHT"); hl:SetColorTexture(1, 0.85, 0.6, 0.06); hl:SetAllPoints()
    b:SetScript("OnClick", function() UI.Show(i) end)
    UI.tabs[i] = b
    local p = CreateFrame("Frame", nil, f)
    p:SetPoint("TOPLEFT", NAV, -74)
    p:SetPoint("BOTTOMRIGHT", -20, 14)
    p:Hide()
    UI.panels[i] = p
  end
  UI.BuildChecklist(UI.panels[1])
  UI.BuildWishlist(UI.panels[2])
  UI.BuildCrafting(UI.panels[3])
  UI.BuildAlts(UI.panels[4])
  UI.BuildOptions(UI.panels[5])
  UI.current = 1
  return f
end

local function StyleTabs()
  for i, b in ipairs(UI.tabs) do
    local on = i == UI.current
    if on then T.Box(b, "active", "edge") elseif b.SetBackdrop then b:SetBackdrop(nil) end
    local hex = on and T.HEX.brass or T.HEX.faint
    b.icon:SetVertexColor(T.rgb(hex))
    b.fs:SetTextColor(T.rgb(hex))
  end
end

function UI.Show(i)
  UI.Create()
  UI.current = i or UI.current or 1
  for n, p in ipairs(UI.panels) do if n == UI.current then p:Show() else p:Hide() end end
  StyleTabs()
  UI.frame:Show()
  UI.Refresh()
end

function ns.ToggleUI(tab)
  UI.Create()
  if UI.frame:IsShown() and not tab then UI.frame:Hide() else UI.Show(tab) end
end

function UI.Refresh()
  if not UI.frame or not UI.frame:IsShown() then return end
  local p = UI.panels[UI.current]
  if p and p.Refresh then
    local ok, err = pcall(p.Refresh, p)
    if not ok then ns.Print("UI error:", err) end
  end
end

local pending = false
ns.OnChange(function()
  if not UI.frame or not UI.frame:IsShown() or pending then return end
  pending = true
  local function go() pending = false; UI.Refresh() end
  if C_Timer and C_Timer.After then C_Timer.After(0.15, go) else go() end
end)

---------------------------------------------------------------------------
-- Shared row kinds
---------------------------------------------------------------------------
local function SectionKind()
  return { height = 28, create = function(r)
    r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(14, 14); r.icon:SetPoint("LEFT", 2, -2)
    r.fs = T.Text(r, "SC", "soft"); r.fs:SetPoint("LEFT", r.icon, "RIGHT", 8, 0)
    r.note = T.Text(r, "Italic", "faint"); r.note:SetPoint("LEFT", r.fs, "RIGHT", 10, 0)
    r.c1 = T.Text(r, "SCSmall", "faint"); r.c1:SetPoint("RIGHT", -112, -2)
    r.c2 = T.Text(r, "SCSmall", "faint"); r.c2:SetPoint("RIGHT", -38, -2)
    r.line = T.Line(r, 0.6); r.line:SetPoint("BOTTOMLEFT"); r.line:SetPoint("BOTTOMRIGHT")
    r.menu = T.IconButton(r, "icon-dots.tga", 26, "More", nil); r.menu:SetPoint("RIGHT", -4, -1)
  end, fill = function(r, e)
    if e.menu then r.menu:Show(); r.menu:SetScript("OnClick", function(b) T.ShowMenu(b, e.menu()) end) else r.menu:Hide() end
    r.icon:SetTexture(T.MEDIA .. (e.icon or "icon-shield.tga"))
    r.icon:SetVertexColor(T.rgb(T.HEX[e.hex or "soft"]))
    r.fs:SetText(e.text); r.fs:SetTextColor(T.rgb(T.HEX[e.hex or "soft"]))
    r.note:SetText(e.note or "")
    r.c1:SetText(e.c1 or ""); r.c2:SetText(e.c2 or "")
  end }
end

local function InfoKind()
  return { height = 30, create = function(r)
    r.fs = T.Text(r, "Italic", "dim"); r.fs:SetPoint("LEFT", 26, 0); r.fs:SetWidth(LISTW - 40); r.fs:SetWordWrap(true)
    r:EnableMouse(false)
  end, fill = function(r, e) r.fs:SetText(e.text) end }
end

-- A kit / wish line: gem, name + hint, tags, have/need, amount box, ⋯ menu.
local function LineKind(width)
  width = width or LISTW
  return { height = 38, create = function(r)
    r.gem = r:CreateTexture(nil, "ARTWORK"); r.gem:SetSize(20, 20); r.gem:SetPoint("LEFT", 2, 0)
    r.name = T.Text(r, "Bold", "text"); r.name:SetPoint("TOPLEFT", 30, -4); r.name:SetWidth(width - 180)
    r.tags = T.TagRow(r, 4, width - 30 - 170); r.tags:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 30, 4)
    r.have = T.Text(r, "Big", "text"); r.have:SetPoint("RIGHT", -96, 0); r.have:SetJustifyH("RIGHT")
    r.edit = T.Edit(r, 44, true, 22); r.edit:SetPoint("RIGHT", -36, 0)
    r.edit:SetScript("OnEnterPressed", function(self) self:ClearFocus(); if r.onEdit then r.onEdit(tonumber(self:GetText())) end end)
    r.menu = T.IconButton(r, "icon-dots.tga", 26, "More", nil); r.menu:SetPoint("RIGHT", -4, 0)
    r.check = T.Check(r); r.check:SetPoint("LEFT", 3, 0)
    r.line = T.Line(r); r.line:SetPoint("BOTTOMLEFT"); r.line:SetPoint("BOTTOMRIGHT")
  end, fill = function(r, e)
    r.gem:Show(); r.check:Hide(); r.edit:Show(); r.menu:Show(); r.have:Show()
    if e.check ~= nil then
      r.gem:Hide(); r.check:Show(); r.check:SetChecked(e.check); r.check.onToggle = e.onCheck
      if e.checkDisabled then r.check:EnableMouse(false) else r.check:EnableMouse(true) end
    else
      T.SetGem(r.gem, e.status)
    end
    r.name:SetText(e.title)
    if e.tags and #e.tags > 0 then
      r.tags:Set(e.tags); r.name:SetPoint("TOPLEFT", 30, -4)
    else
      r.tags:Set(nil); r.name:SetPoint("TOPLEFT", 30, -11)
    end
    if e.haveText then r.have:SetText(e.haveText) else r.have:Hide() end
    if e.qty then r.edit:SetText(tostring(e.qty)); r.onEdit = e.onEdit else r.edit:Hide() end
    if e.menu then r.menu:SetScript("OnClick", function(b) T.ShowMenu(b, e.menu()) end) else r.menu:Hide() end
    r:SetAlpha(e.dim and 0.75 or 1)
    r.tip = e.tip
  end }
end

local function HaveText(have, need, status)
  local hex = ({ ready = "blue", low = "brass", missing = "orange" })[status] or "dim"
  return C(hex, tostring(have)) .. C("faint", " / " .. tostring(need))
end

-- Add bar used at the bottom of the checklist and wish list.
local function AddBar(p, label)
  local bar = CreateFrame("Frame", nil, p)
  bar:SetPoint("BOTTOMLEFT", 0, 0)
  bar:SetPoint("BOTTOMRIGHT", 0, 0)
  bar:SetHeight(30)
  bar.label = T.Text(bar, "SC", "dim"); bar.label:SetPoint("LEFT", 2, 0); bar.label:SetText(label)
  bar.item = T.ItemEdit(bar, 250); bar.item:SetPoint("LEFT", bar.label, "RIGHT", 10, 0)
  bar.qty = T.Edit(bar, 44, true); bar.qty:SetPoint("LEFT", bar.item, "RIGHT", 6, 0)
  return bar
end

---------------------------------------------------------------------------
-- Tab 1: Checklist
---------------------------------------------------------------------------
local function ReadyCountsText(c)
  local m, l, r = ns.Summary(c)
  return C("orange", m .. " missing") .. "    " .. C("brass", l .. " low") .. "    " .. C("blue", r .. " ready")
end

local function MakeKind()
  return { height = 60, create = function(r)
    r.qty = T.Text(r, "Huge", "brass"); r.qty:SetPoint("RIGHT", r, "LEFT", 52, 0); r.qty:SetJustifyH("RIGHT")
    r.name = T.Text(r, "Bold", "text"); r.name:SetPoint("TOPLEFT", 62, -6)
    r.tag = T.Tag(r); r.tag:SetPoint("LEFT", r.name, "RIGHT", 8, 0)
    r.forfs = T.Text(r, "Small", "soft"); r.forfs:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -3); r.forfs:SetWidth(LISTW - 200)
    r.mats = T.Text(r, "Small", "dim"); r.mats:SetPoint("TOPLEFT", r.forfs, "BOTTOMLEFT", 0, -2); r.mats:SetWidth(LISTW - 200)
    r.now = T.Text(r, "Big", "blue"); r.now:SetPoint("TOPRIGHT", -10, -10); r.now:SetJustifyH("RIGHT")
    r.note = T.Text(r, "Small", "faint"); r.note:SetPoint("TOPRIGHT", r.now, "BOTTOMRIGHT", 0, -2); r.note:SetJustifyH("RIGHT")
    r.line = T.Line(r); r.line:SetPoint("BOTTOMLEFT"); r.line:SetPoint("BOTTOMRIGHT")
  end, fill = function(r, e)
    local m = e.make
    r.qty:SetText("x" .. m.qty)
    r.name:SetText(m.name)
    if m.kind == "gap" then r.tag:Set("kit gap", "craft")
    else r.tag:Set("skill-up · " .. (m.diff == "optimal" and "orange" or "yellow"), m.diff == "optimal" and "orange" or "brass") end
    if m.kind == "gap" then
      local parts = {}
      for _, f in ipairs(m.forList) do parts[#parts + 1] = f.name .. " " .. f.n end
      r.forfs:SetText("For " .. table.concat(parts, " · "))
    else
      r.forfs:SetText("Levels " .. m.prof .. (m.diff == "optimal" and ": a guaranteed skill point" or ": usually a skill point"))
    end
    local mats = {}
    for _, x in ipairs(m.mats) do
      local hex = (x.have >= x.need) and "soft" or "orange"
      mats[#mats + 1] = C(hex, x.n .. " " .. x.have .. "/" .. x.need) .. ((x.mail or 0) > 0 and C("faint", " (+" .. x.mail .. " mail)") or "")
    end
    r.mats:SetText("Mats: " .. (#mats > 0 and table.concat(mats, "  ·  ") or "unknown"))
    local hex = (m.canNow >= m.qty) and "blue" or (m.canNow > 0 and "brass" or "orange")
    r.now:SetText(C(hex, tostring(m.canNow)))
    r.now:SetText(C(hex, tostring(m.canNow)) .. C("faint", " can make"))
    r.note:SetText(m.canAll > m.canNow and (m.canAll .. " once mail is collected") or "")
  end }
end

local function TaskKind()
  return { height = 30, create = function(r)
    r.check = T.Check(r); r.check:SetPoint("LEFT", 3, 0)
    r.gem = r:CreateTexture(nil, "ARTWORK"); r.gem:SetSize(18, 18); r.gem:SetPoint("LEFT", 3, 0)
    r.fs = T.Text(r, "Body", "text"); r.fs:SetPoint("LEFT", 30, 0)
    r.detail = T.Text(r, "Italic", "dim"); r.detail:SetPoint("LEFT", r.fs, "RIGHT", 10, 0)
    r.menu = T.IconButton(r, "icon-dots.tga", 26, "More", nil); r.menu:SetPoint("RIGHT", -4, 0)
    r.line = T.Line(r, 0.4); r.line:SetPoint("BOTTOMLEFT"); r.line:SetPoint("BOTTOMRIGHT")
  end, fill = function(r, e)
    local x = e.row
    if x.auto then
      r.check:Hide(); r.gem:Show(); T.SetGem(r.gem, x.status)
    else
      r.gem:Hide(); r.check:Show(); r.check:SetChecked(x.status == "done"); r.check.onToggle = e.onToggle
    end
    r.fs:SetText(x.label)
    r:SetScript("OnClick", e.click)
    r.tip = e.tip
    r.fs:SetTextColor(T.rgb(T.HEX[(x.status == "done") and "blue" or (x.optional and "dim" or "text")]))
    r.detail:SetText(x.detail or (x.optional and "optional" or ""))
    if e.menu then r.menu:Show(); r.menu:SetScript("OnClick", function(b) T.ShowMenu(b, e.menu()) end) else r.menu:Hide() end
  end }
end

function UI.BuildChecklist(p)
  p.summary = T.Text(p, "SC", "text"); p.summary:SetPoint("TOPLEFT", 4, -8)
  p.note = T.Text(p, "Italic", "faint"); p.note:SetPoint("TOPRIGHT", -4, -8); p.note:SetJustifyH("RIGHT")
  local box = T.Frame(p)
  box:SetPoint("TOPLEFT", 0, -28)
  box:SetPoint("BOTTOMRIGHT", 0, 38)
  T.Slot(box)
  p.list = T.List(box, { section = SectionKind(), line = LineKind(), make = MakeKind(), task = TaskKind(), info = InfoKind() }, LISTW)

  local bar = AddBar(p, "Add")
  bar.item:SetPlaceholder("Category or item (shift-click an item)")
  bar.qty:SetText("1")
  local add
  add = T.Button(bar, "Add", 54, function() UI.AddFromBar(UI.Selected(), bar, add) end)
  add:SetPoint("LEFT", bar.qty, "RIGHT", 6, 0)
  local cats = T.Button(bar, "Categories...", 106, function()
    local c = UI.Selected()
    UI.Pick("Add to " .. ns.DisplayName(c), CategoryEntries(),
      function(key) ns.AddLine(c, key, tonumber(bar.qty:GetText()) or 1) end,
      function(name)
        local key = ns.Ref_NewCategory(name)
        ns.AddLine(c, key, tonumber(bar.qty:GetText()) or 1)
        UI.EditCategory(key)
      end)
  end)
  cats:SetPoint("LEFT", add, "RIGHT", 6, 0)
  local task = T.Edit(bar, 130); task:SetPoint("LEFT", cats, "RIGHT", 14, 0); task:SetPlaceholder("New task")
  local addT
  addT = T.Button(bar, "Add task", 78, function()
    local t = ns.Trim(task:GetText())
    if t == "" then return end
    local c = UI.Selected()
    T.ShowMenu(addT, {
      { text = "Just for " .. ns.DisplayName(c), func = function() ns.AddExtraTask(c, t); task:SetText("") end },
      { text = "For every alt", func = function() ns.Ref_AddTask(t); task:SetText("") end },
    })
  end)
  addT:SetPoint("LEFT", task, "RIGHT", 6, 0)
  p.bar = bar

  p.copy = T.Button(UIParent, "Copy from...", 104, function()
    local c = UI.Selected()
    local entries = {}
    for _, o in ipairs(ns.Siblings(c)) do
      if not ns.IsBank(o) then
        entries[#entries + 1] = { text = UI.CharName(o), detail = (o.className or "") .. " · " .. ns.ROLE_NAMES[ns.RoleOf(o)], value = o }
      end
    end
    UI.Pick("Copy kit from", entries, function(o) ns.CopyKit(o, c); ns.Print("Copied kit from", ns.DisplayName(o)) end)
  end)
  p.starter = T.Button(UIParent, "Starter", 72, function()
    local c = UI.Selected()
    if IsShiftKeyDown and IsShiftKeyDown() then ns.SeedKit(c); ns.Print("Kit reset to the", ns.ROLE_NAMES[ns.RoleOf(c)], "starter.")
    else ns.Print("Shift-click Starter to replace this alt's kit with the starter for its class and role.") end
  end)
  p.starter.tip = { "Starter kit", "Shift-click to replace this alt's kit with the starter for its class and role." }
  p.run = T.Button(UIParent, "New run", 78, function() ns.NewRun(UI.Selected()) end)
  p.run.tip = { "New run", "Clears the ticked tasks." }
  p.copy:Hide(); p.starter:Hide(); p.run:Hide()

  p:SetScript("OnShow", function() SetActions({ { button = p.copy }, { button = p.starter }, { button = p.run } }) end)

  function p:Refresh()
    local c = UI.Selected()
    SetHeader(c, true)
    SetActions({ { button = self.copy }, { button = self.starter }, { button = self.run } })
    local entries = {}
    if ns.IsBank(c) then
      self.summary:SetText(C("brass", "Bank alt") .. C("dim", ": no checklist"))
      self.note:SetText("")
      entries[#entries + 1] = { kind = "info", text = "Its stock shows up as a source for your other alts. At the mailbox they're prompted to send it recipes nobody can learn yet, spare materials, surplus and anything tagged for the bank (Wish list tab)." }
      self.list:Render(entries)
      return
    end
    local rows = ns.Checklist(c)
    self.summary:SetText(ReadyCountsText(c))
    self.note:SetText(c.key == ns.Me().key and "" or ("stock as of " .. ns.Ago(c.lastSeen) .. ", bank " .. ns.Ago(c.bankSeen)))

    local must, nice, waiting, tasks = {}, {}, {}, {}
    for _, x in ipairs(rows) do
      if x.kind == "task" then tasks[#tasks + 1] = x
      elseif x.status == "locked" then waiting[#waiting + 1] = x
      elseif x.optional then nice[#nice + 1] = x
      else must[#must + 1] = x end
    end

    local function lineEntry(x)
      local e = { kind = "line", status = x.status, qty = x.qty, tags = UI.SourceTags(x), tip = LineTip(x, c) }
      local best = x.best and C("dim", "  " .. x.best.n) or ""
      e.title = x.label .. best
      e.haveText = HaveText(x.have, x.qty, x.optional and "optional" or x.status)
      if x.kind == "line" then
        e.onEdit = function(v) if v then ns.SetLineQty(c, x.idx, v) end end
        e.menu = function()
          local items = {}
          if x.optional then items[#items + 1] = { text = "Move to Must bring", func = function() ns.ToggleLineOptional(c, x.idx) end }
          else items[#items + 1] = { text = "Move to Nice to have", func = function() ns.ToggleLineOptional(c, x.idx) end } end
          local catName = ns.ref.categories[x.line.cat] and ns.ref.categories[x.line.cat].name or "this"
          items[#items + 1] = { text = "Edit what counts as " .. catName .. "...", func = function() UI.EditCategory(x.line.cat) end }
          local sq = StarterQty(c, x.line.cat)
          if sq and sq ~= x.qty then items[#items + 1] = { text = "Reset amount to starter (" .. sq .. ")", func = function() ns.SetLineQty(c, x.idx, sq) end } end
          items[#items + 1] = { sep = true }
          items[#items + 1] = { text = "Remove from " .. ns.DisplayName(c) .. "'s kit", hex = "orange", func = function() ns.RemoveLine(c, x.idx) end }
          return items
        end
      else
        e.onEdit = function(v) if v then ns.SetExtraQty(c, x.key, v) end end
        e.menu = function()
          return { { text = "Remove from " .. ns.DisplayName(c) .. "'s kit", hex = "orange", func = function() ns.RemoveExtraItem(c, x.key) end } }
        end
      end
      if x.status == "locked" then
        e.title = C("dim", x.label); e.tags = { { "Waiting · " .. x.locked, "faint" } }; e.haveText = C("faint", "x" .. x.qty); e.dim = true
      end
      return e
    end

    entries[#entries + 1] = { kind = "section", text = "MUST BRING", icon = "icon-shield.tga", hex = "soft", c1 = "HAVE", c2 = "CARRY" }
    for _, x in ipairs(must) do entries[#entries + 1] = lineEntry(x) end
    if #must == 0 then entries[#entries + 1] = { kind = "info", text = "Nothing yet. Add a category or item below, or shift-click Starter." } end
    if #nice > 0 then
      entries[#entries + 1] = { kind = "section", text = "NICE TO HAVE", note = "never counts as missing", icon = "icon-star.tga", hex = "faint" }
      for _, x in ipairs(nice) do local e = lineEntry(x); e.dim = true; entries[#entries + 1] = e end
    end
    entries[#entries + 1] = { kind = "section", text = "BEFORE YOU GO", icon = "icon-checklist.tga", hex = "soft", menu = function()
      local items = { { header = true, text = "Tasks for every alt" } }
      for _, t in ipairs(ns.ref.tasks) do
        items[#items + 1] = { text = t.text, checked = not t.off, func = function() ns.Ref_SetTaskOff(t.id, not t.off) end }
      end
      items[#items + 1] = { sep = true }
      for _, t in ipairs(ns.ref.tasks) do
        if t.custom then items[#items + 1] = { text = "Delete \"" .. t.text .. "\"", hex = "orange", func = function() ns.Ref_DeleteTask(t.id) end } end
      end
      items[#items + 1] = { text = "Add a task: type it in the box below", hex = "faint" }
      return items
    end }
    for _, x in ipairs(tasks) do
      local e = { kind = "task", row = x, onToggle = function() ns.ToggleTick(c, x.id) end }
      if x.id == "quests" and ns.DJ() then
        local dungeon = ns.TargetDungeon(c)
        e.click = function() UI.DungeonQuestsWindow(c) end
        e.tip = { "Dungeon quests", "Click to see " .. (dungeon or "a dungeon") .. "'s quests and where to pick them up.", "Quest data from the DungeonJournal addon." }
        e.menu = function()
          local items = {}
          if dungeon then items[#items + 1] = { text = "Show " .. dungeon .. " quests", func = function() UI.DungeonQuestsWindow(c) end } end
          items[#items + 1] = { header = true, text = "Getting ready for" }
          items[#items + 1] = { text = "Best fit for my level", checked = c.nextDungeon == nil, func = function() c.nextDungeon = nil; ns.Changed("quests") end }
          for _, d in ipairs(ns.DungeonList(c)) do
            if d.fits then
              items[#items + 1] = { text = d.name .. C("faint", "  " .. (d.level or "")), checked = c.nextDungeon == d.name,
                func = function() c.nextDungeon = d.name; ns.Changed("quests") end }
            end
          end
          items[#items + 1] = { text = "Other dungeon...", func = function()
            local list = {}
            for _, d in ipairs(ns.DungeonList(c)) do list[#list + 1] = { text = d.name, detail = "level " .. (d.level or "?"), value = d.name } end
            UI.Pick("Getting ready for", list, function(name) c.nextDungeon = name; ns.Changed("quests") end)
          end }
          return items
        end
      end
      if x.extraIdx then e.menu = function() return { { text = "Remove task", hex = "orange", func = function() ns.RemoveExtraTask(c, x.extraIdx) end } } end end
      entries[#entries + 1] = e
    end
    self.list:Render(entries)
  end
end

---------------------------------------------------------------------------
-- Tab 2: Wish list (bank alt: bank pool tags)
---------------------------------------------------------------------------
function UI.BuildWishlist(p)
  p.summary = T.Text(p, "SC", "text"); p.summary:SetPoint("TOPLEFT", 4, -8)
  p.note = T.Text(p, "Italic", "faint"); p.note:SetPoint("TOPRIGHT", -4, -8); p.note:SetJustifyH("RIGHT")
  local box = T.Frame(p)
  box:SetPoint("TOPLEFT", 0, -28)
  box:SetPoint("BOTTOMRIGHT", 0, 38)
  T.Slot(box)
  p.list = T.List(box, { section = SectionKind(), line = LineKind(), info = InfoKind() }, LISTW)
  local bar = AddBar(p, "Add")
  bar.qty:SetText("20")
  p.add = T.Button(bar, "Add to wish list", 130, function()
    local c = UI.Selected()
    if ns.IsBank(c) then
      if ns.TagForBank(bar.item:GetText(), true) then bar.item:SetText("") end
      return
    end
    local id, name = ns.ParseItem(bar.item:GetText())
    if name then ns.AddWish(c, id, name, tonumber(bar.qty:GetText()) or 20); bar.item:SetText("") end
  end)
  p.add:SetPoint("LEFT", bar.qty, "RIGHT", 6, 0)
  p.sugg = T.Check(bar, "Suggestions for this alt", function(on) UI.Selected().suggest = on; ns.Changed("wish") end)
  p.sugg:SetPoint("LEFT", p.add, "RIGHT", 16, 0)
  p.bar = bar

  function p:Refresh()
    local c = UI.Selected()
    SetHeader(c, true)
    SetActions({})
    local entries = {}
    if ns.IsBank(c) then
      bar.qty:Hide(); self.add:SetLabel("Tag for bank"); self.sugg:Hide(); self.sugg.label:Hide()
      bar.item:SetPlaceholder("Item or category name")
      self.summary:SetText(C("brass", "Bank pool tags"))
      self.note:SetText("Other alts always send these to " .. ns.DisplayName(c))
      entries[#entries + 1] = { kind = "section", text = "ALWAYS SEND TO THE BANK", icon = "icon-star.tga", hex = "brass" }
      local list = {}
      for _, x in pairs(ns.db.bankTags.items) do list[#list + 1] = { text = x.n, kind = "item", value = x.n } end
      for key in pairs(ns.db.bankTags.cats) do
        if ns.ref.categories[key] then list[#list + 1] = { text = ns.ref.categories[key].name, kind = "category", value = key } end
      end
      table.sort(list, function(a, b) return a.text < b.text end)
      for _, x in ipairs(list) do
        entries[#entries + 1] = { kind = "line", status = "optional", title = x.text, tags = { { x.kind, "dim" } },
          menu = function() return { { text = "Stop sending this to the bank", hex = "orange", func = function() ns.TagForBank(x.value, false) end } } end }
      end
      if #list == 0 then entries[#entries + 1] = { kind = "info", text = "Nothing tagged. Each alt still keeps what its own kit needs." } end
      self.list:Render(entries)
      return
    end
    bar.qty:Show(); self.add:SetLabel("Add to wish list")
    bar.item:SetPlaceholder("Item (type, shift-click or drop)")
    local auto = ns.db.settings.autoSuggest
    if auto then self.sugg:Show(); self.sugg.label:Show(); self.sugg:SetChecked(c.suggest ~= false) else self.sugg:Hide(); self.sugg.label:Hide() end
    self.summary:SetText(C("text", "Collecting"))
    self.note:SetText("Other alts see these at the mailbox and bank")
    entries[#entries + 1] = { kind = "section", text = "WISH LIST", icon = "tab-wish.tga", hex = "soft", c1 = "HAVE", c2 = "WANT" }
    local keys = {}
    for k in pairs(c.wish) do keys[#keys + 1] = k end
    table.sort(keys)
    for _, k in ipairs(keys) do
      local w = c.wish[k]
      local want = { n = w.n, id = w.id }
      local b, kk, m = ns.Stock(c, want)
      local have = b + kk + m
      local st = have >= (w.q or 0) and "ready" or (have > 0 and "low" or "missing")
      local tags = {}
      if b > 0 then tags[#tags + 1] = { "Bags " .. b, "soft" } end
      if kk > 0 then tags[#tags + 1] = { "Bank " .. kk, "blue" } end
      if m > 0 then tags[#tags + 1] = { "Mail " .. m, "blue" } end
      for _, o in ipairs(ns.Siblings(c)) do
        local ob, ok, om = ns.Stock(o, want)
        if ob + ok + om > 0 and #tags < 4 then tags[#tags + 1] = { ns.DisplayName(o) .. " " .. (ob + ok + om), "parch" } end
      end
      entries[#entries + 1] = { kind = "line", status = st, title = w.n, tags = tags, haveText = HaveText(have, w.q or 0, st),
        qty = w.q or 0, onEdit = function(v) if v then ns.SetWishQty(c, w.n, v) end end,
        menu = function() return { { text = "Remove from wish list", hex = "orange", func = function() ns.RemoveWish(c, w.n) end } } end }
    end
    if #keys == 0 then entries[#entries + 1] = { kind = "info", text = "Nothing on the wish list. Add materials this alt is collecting below." } end
    local sugg = ns.Suggestions(c)
    if #sugg > 0 then
      entries[#entries + 1] = { kind = "section", text = "SUGGESTED", note = "from professions", icon = "icon-star.tga", hex = "faint" }
      for _, s in ipairs(sugg) do
        entries[#entries + 1] = { kind = "line", status = "optional", title = s.n, tags = { { "suggested", "dim" } }, dim = true,
          haveText = HaveText(s.have, s.q, "optional"), tip = { s.n, s.reason or "" },
          menu = function() return {
            { text = "Add to wish list (" .. s.q .. ")", func = function() ns.AddWish(c, s.id, s.n, s.q) end },
            { text = "Ignore", hex = "dim", func = function() ns.IgnoreSuggestion(c, s.n) end } } end }
      end
    end
    self.list:Render(entries)
  end
end

---------------------------------------------------------------------------
-- Tab 3: Crafting (what mains should make, and a levelling plan)
---------------------------------------------------------------------------
local function PlanKind()
  return { height = 48, create = function(r)
    r.qty = T.Text(r, "Huge", "brass"); r.qty:SetPoint("RIGHT", r, "LEFT", 52, 0); r.qty:SetJustifyH("RIGHT")
    r.name = T.Text(r, "Bold", "text"); r.name:SetPoint("TOPLEFT", 62, -7)
    r.tag = T.Tag(r); r.tag:SetPoint("LEFT", r.name, "RIGHT", 8, 0)
    r.sub = T.Text(r, "Small", "soft"); r.sub:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -4); r.sub:SetWidth(LISTW - 90)
    r.line = T.Line(r); r.line:SetPoint("BOTTOMLEFT"); r.line:SetPoint("BOTTOMRIGHT")
  end, fill = function(r, e)
    local p = e.plan
    r.qty:SetText("x" .. p.crafts)
    r.name:SetText(p.recipe)
    if p.diff == "optimal" then r.tag:Set("orange · a point each", "orange") else r.tag:Set("yellow · most give a point", "brass") end
    r.sub:SetText("Next " .. p.window .. " points: " .. p.skill .. " to " .. (p.skill + p.window) ..
      "   ·   " .. p.capName .. " cap " .. p.nextCap .. "   ·   the plan updates as recipe colours change")
  end }
end

function UI.BuildCrafting(p)
  p.summary = T.Text(p, "SC", "text"); p.summary:SetPoint("TOPLEFT", 4, -8)
  p.note = T.Text(p, "Italic", "faint"); p.note:SetPoint("TOPRIGHT", -4, -8); p.note:SetJustifyH("RIGHT")
  local box = T.Frame(p)
  box:SetPoint("TOPLEFT", 0, -28)
  box:SetPoint("BOTTOMRIGHT", 0, 0)
  T.Slot(box)
  p.list = T.List(box, { section = SectionKind(), line = LineKind(), make = MakeKind(), plan = PlanKind(), info = InfoKind() }, LISTW)

  function p:Refresh()
    local c = UI.Selected()
    SetHeader(c, true)
    SetActions({})
    self.summary:SetText(C("text", "Crafting"))
    self.note:SetText("open a profession window to refresh its recipes")
    local entries = {}
    local profs = ns.CraftingProfs(c)
    local make = ns.ToMake(c)
    for _, prof in ipairs(profs) do
      local main = ns.IsMain(c, prof)
      local plan = ns.LevelPlan(c, prof)
      local skill = c.profs[prof] or 0
      local max = c.profMax and c.profMax[prof]
      local shopping = plan and plan.shop
      entries[#entries + 1] = { kind = "section", text = string.upper(prof) .. "  " .. skill .. (max and (" / " .. max) or ""),
        note = main and ("* " .. ns.MainNoun(prof)) or nil, icon = "icon-fire.tga", hex = main and "brass" or "soft",
        menu = function()
          local items = {}
          if shopping and #shopping > 0 then
            items[#items + 1] = { text = "Put the shopping list on the wish list", func = function()
              for _, x in ipairs(shopping) do if x.need > x.have then ns.AddWish(c, x.id, x.n, x.need) end end
            end }
          end
          items[#items + 1] = { text = main and ("Stop being the " .. ns.MainNoun(prof)) or ("Make " .. ns.DisplayName(c) .. " the " .. ns.MainNoun(prof)),
            func = function() ns.SetMain(c, prof, not main) end }
          return items
        end }
      -- what to make for other alts (mains only)
      if main then
        local any = false
        for _, m in ipairs(make) do
          if m.prof == prof and m.kind == "gap" then entries[#entries + 1] = { kind = "make", make = m }; any = true end
        end
        if not any then entries[#entries + 1] = { kind = "info", text = "Nobody's kit is short of anything you make." } end
      end
      -- levelling
      if not plan then
      elseif plan.done then entries[#entries + 1] = { kind = "info", text = "Maxed out at 300." }
      elseif plan.train then entries[#entries + 1] = { kind = "info", text = "At the " .. skill .. " cap. Train the next rank (" .. (plan.capName or "next") .. ") at a trainer." }
      elseif plan.noRecipes then entries[#entries + 1] = { kind = "info", text = "Open your " .. prof .. " window once so Fettle can read your recipes and plan your levelling." }
      elseif plan.stuck then entries[#entries + 1] = { kind = "info", text = "None of your recipes give skill any more. Learn new ones from a trainer or vendor." }
      else
        entries[#entries + 1] = { kind = "plan", plan = plan }
        for _, x in ipairs(plan.shop) do
          local st = x.have >= x.need and "ready" or (x.have > 0 and "low" or "missing")
          local tags = {}
          if x.bags > 0 then tags[#tags + 1] = { "Bags " .. x.bags, "soft" } end
          if x.bank > 0 then tags[#tags + 1] = { "Bank " .. x.bank, "blue" } end
          if x.mail > 0 then tags[#tags + 1] = { "Mail " .. x.mail, "blue" } end
          for _, o in ipairs(x.others) do tags[#tags + 1] = { o.name .. " " .. o.n, "parch" } end
          if x.vendor then tags[#tags + 1] = { "Vendor", "dim" } end
          entries[#entries + 1] = { kind = "line", status = st, title = x.n, tags = tags, haveText = HaveText(x.have, x.need, st),
            tip = { x.n, "Needed for the next " .. plan.window .. " points of " .. prof .. "." } }
        end
      end
    end
    if #profs == 0 then entries[#entries + 1] = { kind = "info", text = ns.DisplayName(c) .. " has no crafting professions." } end
    self.list:Render(entries)
  end
end

---------------------------------------------------------------------------
-- Tab 4: Alts (with profession mains)
---------------------------------------------------------------------------
local ALL_PROFS = { "Alchemy", "Blacksmithing", "Cooking", "Enchanting", "Engineering", "First Aid", "Fishing",
                    "Herbalism", "Leatherworking", "Mining", "Skinning", "Tailoring" }

local function AltKind()
  return { height = 46, create = function(r)
    r.name = T.Text(r, "NameSmall", "text"); r.name:SetPoint("TOPLEFT", 6, -6)
    r.info = T.Text(r, "Small", "dim"); r.info:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -3)
    r.role = T.Text(r, "Bold", "brass"); r.role:SetPoint("LEFT", 200, 0); r.role:SetWidth(90)
    r.tags = T.TagRow(r, 4, LISTW - 300 - 150); r.tags:SetPoint("LEFT", r, "LEFT", 300, 0)
    r.kit = T.Text(r, "Small", "dim"); r.kit:SetPoint("RIGHT", -40, 0); r.kit:SetJustifyH("RIGHT")
    r.menu = T.IconButton(r, "icon-dots.tga", 26, "More", nil); r.menu:SetPoint("RIGHT", -4, 0)
    r.line = T.Line(r); r.line:SetPoint("BOTTOMLEFT"); r.line:SetPoint("BOTTOMRIGHT")
  end, fill = function(r, e)
    local c = e.char
    r.name:SetText(UI.CharName(c))
    local spec = SpecText(c)
    r.info:SetText((c.level or "?") .. " " .. (c.className or "?") .. (spec and (" · " .. spec) or "") .. "   seen " .. ns.Ago(c.lastSeen))
    r.role:SetText(ns.ROLE_NAMES[ns.RoleOf(c)])
    local tags = {}
    local profs = {}
    for prof, rank in pairs(c.profs or {}) do profs[#profs + 1] = { prof, rank } end
    table.sort(profs, function(a, b)
      local am, bm = ns.IsMain(c, a[1]), ns.IsMain(c, b[1])
      if am ~= bm then return am end
      return a[1] < b[1]
    end)
    for _, x in ipairs(profs) do
      local main = ns.IsMain(c, x[1])
      tags[#tags + 1] = { (main and "* " or "") .. x[1] .. " " .. tostring(x[2]), main and "brass" or "dim" }
    end
    r.tags:Set(tags)
    if ns.IsBank(c) then
      local n = 0
      for _ in pairs(c.inv or {}) do n = n + 1 end
      r.kit:SetText(C("brass", n .. " kinds of item"))
    else
      local m, l = ns.Summary(c)
      r.kit:SetText((m > 0 and C("orange", m .. " missing") or C("blue", "ready")) .. (l > 0 and C("brass", ", " .. l .. " low") or ""))
    end
    r.tip = { ns.DisplayName(c), "Role: " .. ns.ROLE_NAMES[ns.RoleOf(c)] .. (c.roleOverride and " (set by you)" or " (from spec)"),
              "Use ... to set mains, change the role or open this alt's checklist." }
    r.menu:SetScript("OnClick", function(b) T.ShowMenu(b, e.menu()) end)
  end }
end

function UI.BuildAlts(p)
  p.mainsLabel = T.Text(p, "SC", "soft"); p.mainsLabel:SetPoint("TOPLEFT", 4, -8); p.mainsLabel:SetText("PROFESSION MAINS")
  p.mains = T.TagRow(p, 8, CW - 170); p.mains:SetPoint("LEFT", p.mainsLabel, "RIGHT", 12, 0)
  local box = T.Frame(p)
  box:SetPoint("TOPLEFT", 0, -28)
  box:SetPoint("BOTTOMRIGHT", 0, 26)
  T.Slot(box)
  p.list = T.List(box, { alt = AltKind(), info = InfoKind() }, LISTW)
  p.foot = T.Text(p, "Italic", "faint"); p.foot:SetPoint("BOTTOMLEFT", 4, 6)
  p.foot:SetText("* Mains get every material for their profession from your other alts, and make consumables for everyone.")

  function p:Refresh()
    SetHeader(ns.Me(), false)
    UI.header.name:SetText(C("parch", "Your alts"))
    UI.header.info:SetText(C("soft", (ns.Me().realm or "") .. " · " .. (ns.Me().faction or "")))
    SetActions({})
    local me = ns.Me()
    local mains = ns.Mains(me)
    local tags = {}
    local profs = {}
    for prof in pairs(mains) do profs[#profs + 1] = prof end
    table.sort(profs)
    for _, prof in ipairs(profs) do tags[#tags + 1] = { "* " .. prof .. " " .. ns.DisplayName(mains[prof]), "brass" } end
    if #tags == 0 then tags[1] = { "none yet: use an alt's ... menu", "faint" } end
    self.mains:Set(tags)
    local chars = {}
    for _, c in pairs(ns.db.chars) do chars[#chars + 1] = ns.GetChar(c.key) end
    table.sort(chars, function(a, b) return ns.DisplayName(a) < ns.DisplayName(b) end)
    local entries = {}
    for _, c in ipairs(chars) do
      entries[#entries + 1] = { kind = "alt", char = c, menu = function()
        local items = { { header = true, text = "Make " .. ns.DisplayName(c) .. " the main for" } }
        items[#items + 1] = { text = "Open " .. ns.DisplayName(c) .. "'s crafting", func = function() UI.selectedKey = c.key; UI.Show(3) end }
        local list = {}
        for prof in pairs(c.profs or {}) do list[#list + 1] = prof end
        if #list == 0 then list = ALL_PROFS end
        table.sort(list)
        for _, prof in ipairs(list) do
          local cur = ns.MainFor(c, prof)
          local isMe = cur and cur.key == c.key
          local note = isMe and "" or (cur and C("faint", "  (now " .. (cur.name or "?") .. ")") or C("faint", "  (no main yet)"))
          items[#items + 1] = { text = prof .. note, checked = isMe, func = function() ns.SetMain(c, prof, not isMe) end }
        end
        items[#items + 1] = { sep = true }
        items[#items + 1] = { header = true, text = "Role" }
        for i = 1, #ROLE_ORDER do
          local r = ROLE_ORDER[i]
          local label = r and ns.ROLE_NAMES[r] or ("Auto (" .. ns.ROLE_NAMES[c.autoRole or "MELEE"] .. ")")
          items[#items + 1] = { text = label, checked = (c.roleOverride or false) == r, func = function() c.roleOverride = r or nil; ns.Changed("char") end }
        end
        items[#items + 1] = { sep = true }
        items[#items + 1] = { text = "Open " .. ns.DisplayName(c) .. "'s checklist", func = function() UI.selectedKey = c.key; UI.Show(1) end }
        items[#items + 1] = { text = "Forget " .. ns.DisplayName(c) .. " (shift-click)", hex = "orange", func = function()
          if IsShiftKeyDown and IsShiftKeyDown() then ns.db.chars[c.key] = nil; ns.Changed("chars")
          else ns.Print("Hold Shift and choose Forget again to delete " .. ns.DisplayName(c) .. ".") end
        end }
        return items
      end }
    end
    self.list:Render(entries)
  end
end

---------------------------------------------------------------------------
-- Adding from the bar: categories, exact items, or "count it as..."
---------------------------------------------------------------------------
function UI.AddFromBar(c, bar, anchor)
  local text = bar.item:GetText()
  local qty = tonumber(bar.qty:GetText()) or 1
  if not text or ns.Trim(text) == "" then return end
  local cat = not text:find("|H") and ns.FindCategoryExact(text)
  if cat then ns.AddLine(c, cat, qty); bar.item:SetText(""); return end
  local id, name = ns.ParseItem(text)
  if not name then return end
  local items = {}
  local cats = ns.CategoriesFor(name)
  for _, key in ipairs(cats) do
    local cn = ns.ref.categories[key].name
    items[#items + 1] = { text = "Add " .. cn .. C("faint", "  (any rank)"), func = function() ns.AddLine(c, key, qty); bar.item:SetText("") end }
  end
  items[#items + 1] = { text = "Add exactly " .. name, func = function() ns.AddExtraItem(c, id, name, qty); bar.item:SetText("") end }
  if #cats == 0 then
    items[#items + 1] = { sep = true }
    items[#items + 1] = { text = "Count " .. name .. " as...", func = function()
      UI.Pick("Count " .. name .. " as", CategoryEntries(), function(key)
        local m = id and ns.ItemMeta and ns.ItemMeta(id)
        ns.Ref_AddRank(key, name, m and m.minLvl and math.max(1, m.minLvl) or nil, "Added by you")
        ns.AddLine(c, key, qty)
        bar.item:SetText("")
      end, function(newName)
        local key = ns.Ref_NewCategory(newName)
        local m = id and ns.ItemMeta and ns.ItemMeta(id)
        ns.Ref_AddRank(key, name, m and m.minLvl and math.max(1, m.minLvl) or nil, "Added by you")
        ns.AddLine(c, key, qty)
        bar.item:SetText("")
      end)
    end }
  end
  T.ShowMenu(anchor, items)
end

---------------------------------------------------------------------------
-- Dungeon quests window (data from the DungeonJournal addon)
---------------------------------------------------------------------------
local QSTATE = {
  done = { gem = "ready", tag = { "done", "faint" } },
  log = { gem = "ready", tag = { "in your log", "blue" } },
  missing = { gem = "missing", tag = { "pick it up", "orange" } },
  later = { gem = "optional", tag = { "later", "dim" } },
}

local function QuestKind()
  return { height = 46, create = function(r)
    r.gem = r:CreateTexture(nil, "ARTWORK"); r.gem:SetSize(20, 20); r.gem:SetPoint("LEFT", 2, 0)
    r.name = T.Text(r, "Bold", "text"); r.name:SetPoint("TOPLEFT", 30, -6); r.name:SetWidth(300)
    r.tag = T.Tag(r); r.tag:SetPoint("TOPRIGHT", -4, -6)
    r.where = T.Text(r, "Small", "soft"); r.where:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -4); r.where:SetWidth(390)
    r.line = T.Line(r); r.line:SetPoint("BOTTOMLEFT"); r.line:SetPoint("BOTTOMRIGHT")
  end, fill = function(r, e)
    local q = e.quest
    local look = QSTATE[q.state] or QSTATE.missing
    T.SetGem(r.gem, look.gem)
    r.name:SetText(q.name .. (q.faction and q.faction ~= "Both" and C("faint", "  " .. q.faction) or ""))
    r.name:SetTextColor(T.rgb(T.HEX[q.state == "done" and "dim" or "text"]))
    local tag = look.tag
    if q.state == "later" then tag = { "from level " .. (q.requires or "?"), "dim" } end
    r.tag:Set(tag[1], tag[2])
    local where
    if q.state == "log" then where = "Turn in: " .. (q.turnin or "?")
    elseif q.state == "done" then where = "Completed"
    else where = "Pick up: " .. (q.pickup or "?") end
    r.where:SetText(where)
    local tip = { q.name }
    if q.objective then tip[#tip + 1] = q.objective end
    if q.pickup then tip[#tip + 1] = "Pick up: " .. q.pickup end
    if q.turnin then tip[#tip + 1] = "Turn in: " .. q.turnin end
    if q.note then tip[#tip + 1] = q.note end
    tip[#tip + 1] = "From the DungeonJournal addon."
    r.tip = tip
  end }
end

function UI.DungeonQuestsWindow(c)
  local f = UI.questWin
  if not f then
    f = T.Frame(UIParent, "FettleQuests")
    f:SetSize(460, 480)
    T.Iron(f)
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f.title = T.Text(f, "Name", "title"); f.title:SetPoint("TOPLEFT", 18, -14)
    f.sub = T.Text(f, "Small", "dim"); f.sub:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -3)
    local close = T.IconButton(f, "icon-close.tga", 22, "Close", function() f:Hide() end)
    close:SetPoint("TOPRIGHT", -14, -12)
    local box = T.Frame(f)
    box:SetPoint("TOPLEFT", 12, -56)
    box:SetPoint("BOTTOMRIGHT", -12, 30)
    T.Slot(box)
    f.list = T.List(box, { quest = QuestKind(), info = InfoKind() }, 396)
    f.foot = T.Text(f, "Italic", "faint"); f.foot:SetPoint("BOTTOMLEFT", 16, 10)
    f.foot:SetText("Quest data from the DungeonJournal addon")
    if UISpecialFrames then table.insert(UISpecialFrames, "FettleQuests") end
    function f:Refresh()
      local ch = self.char
      local dungeon = ns.TargetDungeon(ch)
      local db = ns.DJ()
      local d = dungeon and db and db[dungeon]
      self.title:SetText(dungeon or "No dungeon chosen")
      self.sub:SetText(d and ((d.level and ("Level " .. d.level) or "") .. (d.location and ("  ·  " .. d.location) or "")) or "")
      local entries = {}
      local order = { missing = 1, log = 2, later = 3, done = 4 }
      local qs = dungeon and ns.DungeonQuests(ch, dungeon) or {}
      local shown = {}
      for _, q in ipairs(qs) do if q.state ~= "other" then shown[#shown + 1] = q end end
      table.sort(shown, function(a, b) return (order[a.state] or 5) < (order[b.state] or 5) end)
      for _, q in ipairs(shown) do entries[#entries + 1] = { kind = "quest", quest = q } end
      if #entries == 0 then entries[1] = { kind = "info", text = dungeon and "No quests for your faction here." or "Choose a dungeon from the task's ... menu." } end
      self.list:Render(entries)
    end
    ns.OnChange(function() if f:IsShown() then f:Refresh() end end)
    UI.questWin = f
  end
  f.char = c
  f:ClearAllPoints()
  if UI.frame and UI.frame:IsShown() then f:SetPoint("TOPLEFT", UI.frame, "TOPRIGHT", 6, 0) else f:SetPoint("CENTER") end
  f:Show()
  f:Refresh()
  return f
end

---------------------------------------------------------------------------
-- Bug reports: write one (sent to the developer), or read what's come in
---------------------------------------------------------------------------
local function BugText()
  local lines = {}
  for i, r in ipairs(ns.db.bugInbox or {}) do
    lines[#lines + 1] = "#" .. i .. " from " .. tostring(r.from) .. (date and r.at and ("  (" .. date("%Y-%m-%d %H:%M", r.at) .. ")") or "")
    lines[#lines + 1] = r.text
    lines[#lines + 1] = ""
  end
  return table.concat(lines, "\n")
end

function UI.BugWindow(mode, prefill)
  local f = UI.bugWin
  if not f then
    f = T.Frame(UIParent, "FettleBugs")
    f:SetSize(440, 360)
    T.Iron(f)
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f.title = T.Text(f, "Name", "title"); f.title:SetPoint("TOPLEFT", 18, -14)
    f.sub = T.Text(f, "Small", "dim"); f.sub:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -3); f.sub:SetWidth(400)
    local close = T.IconButton(f, "icon-close.tga", 22, "Close", function() f:Hide() end)
    close:SetPoint("TOPRIGHT", -14, -12)
    local box = T.Frame(f)
    box:SetPoint("TOPLEFT", 14, -60)
    box:SetPoint("BOTTOMRIGHT", -14, 46)
    T.Slot(box)
    local sf = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 8, -6)
    sf:SetPoint("BOTTOMRIGHT", -28, 6)
    local eb = CreateFrame("EditBox", nil, sf)
    eb:SetMultiLine(true)
    eb:SetAutoFocus(false)
    eb:SetFontObject(T.Font.Body)
    eb:SetWidth(370)
    eb:SetMaxLetters(1500)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    sf:SetScrollChild(eb)
    box:EnableMouse(true)
    box:SetScript("OnMouseDown", function() eb:SetFocus() end)
    f.edit = eb
    f.status = T.Text(f, "Italic", "faint"); f.status:SetPoint("BOTTOMLEFT", 18, 18); f.status:SetWidth(220)
    f.primary = T.Button(f, "Send", 90, function() f:Primary() end, 24)
    f.primary:SetPoint("BOTTOMRIGHT", -16, 12)
    f.secondary = T.Button(f, "Clear all", 90, function() f:Secondary() end, 24)
    f.secondary:SetPoint("RIGHT", f.primary, "LEFT", -8, 0)
    if UISpecialFrames then table.insert(UISpecialFrames, "FettleBugs") end
    function f:Primary()
      if self.mode == "report" then
        local res = ns.SubmitBug(self.edit:GetText())
        if not res then self.status:SetText("Type what went wrong first."); return end
        self.edit:SetText("")
        if res == "saved" then self.status:SetText("Saved to your bug reports.")
        else self.status:SetText("Sent. It reaches the developer next time you're both online.") end
        ns.Print("bug report queued. You'll get a message when the developer has it.")
      else
        self.edit:HighlightText()
        self.edit:SetFocus()
        self.status:SetText("Press Ctrl+C to copy.")
      end
    end
    function f:Secondary()
      if self.mode == "inbox" then
        if IsShiftKeyDown and IsShiftKeyDown() then
          ns.db.bugInbox = {}
          ns.Changed("bugs")
          self:Refresh()
        else
          self.status:SetText("Shift-click to delete every report.")
        end
      end
    end
    function f:Refresh()
      if self.mode == "report" then
        self.title:SetText("Report a bug")
        local q = #(ns.db.bugOutbox or {})
        self.sub:SetText("Say what you did, what happened, and what you expected. Your version and character are added for you.")
        self.status:SetText(q > 0 and (q .. " report" .. (q > 1 and "s" or "") .. " waiting for the developer to log in") or "")
        self.primary:SetLabel("Send")
        self.secondary:Hide()
      else
        local n = #(ns.db.bugInbox or {})
        self.title:SetText("Bug reports (" .. n .. ")")
        self.sub:SetText("Reports from your guildies. Select all and copy them to paste wherever you track bugs.")
        self.edit:SetText(n > 0 and BugText() or "No reports yet.")
        self.status:SetText("")
        self.primary:SetLabel("Select all")
        self.secondary:Show()
      end
    end
    ns.OnChange(function(what) if what == "bugs" and f:IsShown() and f.mode == "inbox" then f:Refresh() end end)
    UI.bugWin = f
  end
  f.mode = mode or "report"
  if f.mode == "report" then f.edit:SetText(prefill or "") end
  f:ClearAllPoints()
  f:SetPoint("CENTER")
  f:Show()
  f:Refresh()
  if f.mode == "report" then f.edit:SetFocus() end
  return f
end

---------------------------------------------------------------------------
-- Category editor (opened from a line's ... menu): which items count
---------------------------------------------------------------------------
function UI.EditCategory(key)
  local f = UI.catEditor
  if not f then
    f = T.Frame(UIParent, "FettleCategory")
    f:SetSize(460, 500)
    T.Iron(f)
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f.kicker = T.Text(f, "SCSmall", "faint"); f.kicker:SetPoint("TOPLEFT", 18, -14); f.kicker:SetText("WHAT COUNTS AS")
    f.rename = T.Edit(f, 260, false, 26); f.rename:SetPoint("TOPLEFT", 16, -30)
    f.rename:SetScript("OnEnterPressed", function(self) self:ClearFocus(); ns.Ref_RenameCategory(f.key, self:GetText()) end)
    local close = T.IconButton(f, "icon-close.tga", 22, "Close", function() f:Hide() end)
    close:SetPoint("TOPRIGHT", -14, -12)
    f.reset = T.Button(f, "Reset", 64, function()
      if IsShiftKeyDown and IsShiftKeyDown() then ns.Ref_ResetCategory(f.key); if not ns.ref.categories[f.key] then f:Hide() end
      else ns.Print("Shift-click Reset to restore the default items (or delete the category if you made it).") end
    end)
    f.reset:SetPoint("LEFT", f.rename, "RIGHT", 8, 0)
    f.reset.tip = { "Reset", "Shift-click to restore this category's default items, or delete it if you made it." }
    f.note = T.Text(f, "Italic", "faint"); f.note:SetPoint("TOPLEFT", 18, -62); f.note:SetWidth(420)
    local box = T.Frame(f)
    box:SetPoint("TOPLEFT", 12, -80)
    box:SetPoint("BOTTOMRIGHT", -12, 76)
    T.Slot(box)
    f.list = T.List(box, { line = LineKind(396), info = InfoKind() }, 396)
    f.item = T.ItemEdit(f, 220); f.item:SetPoint("BOTTOMLEFT", 14, 44); f.item:SetPlaceholder("Item (type, shift-click or drop)")
    f.lvl = T.Edit(f, 44, true); f.lvl:SetPoint("LEFT", f.item, "RIGHT", 6, 0); f.lvl:SetPlaceholder("lvl")
    local addItem = T.Button(f, "Add item", 90, function()
      local id, name = ns.ParseItem(f.item:GetText()); if not name then return end
      local lvl = tonumber(f.lvl:GetText())
      if not lvl and id and ns.ItemMeta then local m = ns.ItemMeta(id); lvl = m and m.minLvl and math.max(1, m.minLvl) or nil end
      ns.Ref_AddRank(f.key, name, lvl, "Added by you")
      f.item:SetText(""); f.lvl:SetText("")
    end)
    addItem:SetPoint("LEFT", f.lvl, "RIGHT", 6, 0)
    f.pat = T.Edit(f, 220); f.pat:SetPoint("BOTTOMLEFT", 14, 14); f.pat:SetPlaceholder("or a name pattern, e.g. healing potion$")
    local addPat = T.Button(f, "Add pattern", 110, function()
      local t = ns.Trim(f.pat:GetText()); if t ~= "" then ns.Ref_AddPattern(f.key, t:lower()); f.pat:SetText("") end
    end)
    addPat:SetPoint("LEFT", f.pat, "RIGHT", 6, 0)
    addPat.tip = { "Name pattern", "Counts every item whose name matches, e.g. 'healing potion$' = names ending in healing potion." }
    if UISpecialFrames then table.insert(UISpecialFrames, "FettleCategory") end
    function f:Refresh()
      local cat = ns.ref.categories[self.key]
      if not cat then self:Hide() return end
      if not self.rename:HasFocus() then self.rename:SetText(cat.name) end
      self.note:SetText(cat.note or "Levels come from the game once you've seen an item. Type a level to override it.")
      local entries = {}
      for _, r in ipairs(cat.ranks or {}) do
        local tags = {}
        if r.src then tags[#tags + 1] = { r.src, r.seen and "blue" or "craft" } end
        if r.skill then tags[#tags + 1] = { r.skill[1] .. " " .. r.skill[2], "dim" } end
        if not r.lvl then tags[#tags + 1] = { "level unknown", "faint" } end
        local k = self.key
        entries[#entries + 1] = { kind = "line", status = r.lvl and "ready" or "optional", title = r.n, tags = tags,
          haveText = r.lvl and C("dim", "lvl") or "", qty = r.lvl or "", onEdit = function(v) ns.Ref_SetRankLevel(k, r.n, v) end,
          tip = { r.n, "Required level. Clear it and press Enter if unknown (counted, never suggested)." },
          menu = function() return { { text = "Stop counting " .. r.n, hex = "orange", func = function() ns.Ref_RemoveRank(k, r.n) end } } end }
      end
      for _, pat in ipairs(cat.patterns or {}) do
        local k = self.key
        entries[#entries + 1] = { kind = "line", status = "optional", title = C("blue", "pattern  ") .. pat, tags = { { "any matching name", "dim" } },
          menu = function() return { { text = "Remove pattern", hex = "orange", func = function() ns.Ref_RemovePattern(k, pat) end } } end }
      end
      if #entries == 0 then entries[1] = { kind = "info", text = "Nothing counts yet. Add an item or a name pattern below." } end
      self.list:Render(entries)
    end
    ns.OnChange(function() if f:IsShown() then f:Refresh() end end)
    UI.catEditor = f
  end
  f.key = key
  f:ClearAllPoints()
  if UI.frame and UI.frame:IsShown() then f:SetPoint("TOPLEFT", UI.frame, "TOPRIGHT", 6, 0) else f:SetPoint("CENTER") end
  f:Show()
  f:Refresh()
  return f
end

---------------------------------------------------------------------------
-- Tab 5: Options
---------------------------------------------------------------------------
function UI.BuildOptions(p)
  local s = function() return ns.db.settings end
  local box = T.Frame(p)
  box:SetPoint("TOPLEFT", 0, -4)
  box:SetPoint("BOTTOMRIGHT", 0, 38)
  T.Slot(box)
  p.checks, p.nums = {}, {}
  local col = { x = 16, y = -12 }
  local function at(x) col.x = x; col.y = -12 end
  local function head(text)
    local fs = T.Text(box, "SC", "brass"); fs:SetPoint("TOPLEFT", col.x, col.y); fs:SetText(text)
    col.y = col.y - 26
  end
  local function check(key, label, onToggle)
    local c = T.Check(box, label, onToggle or function(on) s()[key] = on; ns.Changed("settings") end)
    c:SetPoint("TOPLEFT", col.x + 2, col.y)
    c.key = key
    p.checks[#p.checks + 1] = c
    col.y = col.y - 25
    return c
  end
  local function num(key, label)
    local e = T.Edit(box, 44, true, 22)
    e:SetPoint("TOPLEFT", col.x + 2, col.y)
    e:SetScript("OnEnterPressed", function(self) self:ClearFocus(); local v = tonumber(self:GetText()); if v then s()[key] = v; ns.Changed("settings") end end)
    local fs = T.Text(box, "Body", "text"); fs:SetPoint("LEFT", e, "RIGHT", 10, 0); fs:SetText(label)
    e.key = key
    p.nums[#p.nums + 1] = e
    col.y = col.y - 27
  end
  at(16)
  head("WHEN TO SHOW FETTLE")
  check("popupOnDungeon", "Open the checklist in dungeons if anything's missing")
  check("resetTicksOnLeave", "Clear ticked tasks after a dungeon")
  check("hintsBank", "Hints at the bank")
  check("hintsMail", "Hints at the mailbox")
  check("hintsVendor", "Hints at vendors")
  check("hintsBags", "Suggest mailing bigger bags to alts")
  check("autoSuggest", "Suggest wish list mats from professions")
  check("planWants", "Levelling plan mats show in mail and vendor hints")
  col.y = col.y - 8
  head("NUMBERS")
  num("surplusCap", "Surplus cap (times the kit amount)")
  num("minDurability", "Durability % for 'Gear repaired'")
  num("minFreeSlots", "Free bag slots wanted")
  num("suggestCrafts", "Skill-up crafts per recipe")
  num("suggestMaxRecipes", "Skill-up recipes per profession")
  at(math.floor(CW / 2) + 10)
  head("SEND TO THE BANK ALT")
  check("bankRecipes", "Recipes no alt can learn yet")
  check("bankMats", "Trade goods nobody needs or collects")
  check("bankSurplus", "Consumables over the surplus cap")
  check("bankTagged", "Items and categories tagged for the bank")
  check("bankGear", "Tradeable gear above every alt's level")
  col.y = col.y - 8
  head("PROFESSION MAINS")
  check("deGear", "Spare green and blue gear to the main enchanter")
  col.y = col.y - 8
  head("MINIMAP")
  p.mm = T.Check(box, "Show minimap button", function(on) ns.db.minimap.hide = not on; if ns.UpdateMinimap then ns.UpdateMinimap() end end)
  p.mm:SetPoint("TOPLEFT", col.x + 2, col.y)
  col.y = col.y - 33
  head("BUG REPORTS")
  local report = T.Button(box, "Report a bug", 120, function() UI.BugWindow("report") end, 24)
  report:SetPoint("TOPLEFT", col.x + 2, col.y)
  report.tip = { "Report a bug", "Sends a report to the Fettle developer in game (when you're both online)." }
  p.inboxBtn = T.Button(box, "Bug reports", 120, function() UI.BugWindow("inbox") end, 24)
  p.inboxBtn:SetPoint("LEFT", report, "RIGHT", 8, 0)
  col.y = col.y - 32
  check("receiveBugs", "Receive bug reports (I make Fettle)")

  local reset = T.Button(p, "Reset category edits", 170, function()
    if IsShiftKeyDown and IsShiftKeyDown() then ns.Slash("resetref") else ns.Print("Shift-click to discard all your category and task edits.") end
  end)
  reset:SetPoint("BOTTOMLEFT", 0, 4)
  reset.tip = { "Reset category edits", "Shift-click to discard all your changes to categories and shared tasks." }
  local ver = T.Text(p, "Small", "faint"); ver:SetPoint("BOTTOMRIGHT", -2, 10); ver:SetText("Fettle " .. ns.VERSION .. "   /fettle help")

  function p:Refresh()
    SetHeader(ns.Me(), false)
    UI.header.name:SetText(C("parch", "Options"))
    UI.header.info:SetText(C("soft", "Shared by all your alts"))
    SetActions({})
    for _, c in ipairs(self.checks) do c:SetChecked(s()[c.key] and true or false) end
    for _, e in ipairs(self.nums) do if not e:HasFocus() then e:SetText(tostring(s()[e.key] or "")) end end
    self.mm:SetChecked(not ns.db.minimap.hide)
    local n = #(ns.db.bugInbox or {})
    if ns.IsDev() or n > 0 then self.inboxBtn:Show(); self.inboxBtn:SetLabel("Bug reports (" .. n .. ")") else self.inboxBtn:Hide() end
  end
end
