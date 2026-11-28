-- Fettle: "Forgeplate" theme. Dark iron, carved stone, brass, stamped tags.
local _, ns = ...

local T = {}
ns.T = T

local MEDIA = "Interface\\AddOns\\Fettle\\Media\\"
T.MEDIA = MEDIA

local function rgb(hex)
  return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255
end
T.rgb = rgb

-- palette (hex, used for both textures and |c codes)
T.HEX = {
  text = "ece3d1", dim = "a39b8d", faint = "8d877c", brass = "f0c27a", title = "e2b867",
  blue = "8cc4ec", orange = "ff9a4a", craft = "f0a35a", parch = "e9ddc6", soft = "d6cdbb",
  slot = "1c1b1d", btn = "2b2a2d", edge = "6e6a63", dark = "111111", active = "3a3836",
}
function T.Color(name, s) return "|cff" .. (T.HEX[name] or name) .. s .. "|r" end
T.CLASS_HEX = {
  WARRIOR = "c79c6e", PALADIN = "f58cba", HUNTER = "abd473", ROGUE = "fff569", PRIEST = "ffffff",
  SHAMAN = "2f8fe0", MAGE = "69ccf0", WARLOCK = "9482c9", DRUID = "ff7d0a",
}

---------------------------------------------------------------------------
-- Fonts (shipped under the SIL Open Font License; see Media/Fonts)
---------------------------------------------------------------------------
local FONTS = {
  Title = { "CinzelDecorative-Bold.ttf", 26 },
  Name = { "Cinzel-SemiBold.ttf", 17 },
  NameSmall = { "Cinzel-SemiBold.ttf", 14 },
  Body = { "AlegreyaSans-Regular.ttf", 14 },
  Bold = { "AlegreyaSans-Bold.ttf", 14 },
  Big = { "AlegreyaSans-Bold.ttf", 17 },
  Huge = { "AlegreyaSans-Bold.ttf", 21 },
  Small = { "AlegreyaSans-Regular.ttf", 12 },
  Italic = { "AlegreyaSans-Italic.ttf", 12.5 },
  SC = { "AlegreyaSansSC-Bold.ttf", 13 },
  SCSmall = { "AlegreyaSansSC-Bold.ttf", 11 },
  Tag = { "AlegreyaSans-Bold.ttf", 10 },
}
T.Font = {}
for key, def in pairs(FONTS) do
  local f = CreateFont("FettleFont" .. key)
  local ok = f.SetFont and f:SetFont(MEDIA .. "Fonts\\" .. def[1], def[2], "")
  if not ok and f.SetFont then f:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", def[2] - 1, "") end
  if f.SetShadowOffset then f:SetShadowOffset(1, -1); f:SetShadowColor(0, 0, 0, 0.9) end
  T.Font[key] = f
end

function T.Text(parent, font, hex, layer)
  local fs = parent:CreateFontString(nil, layer or "OVERLAY")
  fs:SetFontObject(T.Font[font or "Body"])
  if hex then fs:SetTextColor(rgb(T.HEX[hex] or hex)) end
  fs:SetJustifyH("LEFT")
  fs:SetWordWrap(false)
  return fs
end

function T.Width(fs, fallback)
  local w = fs.GetStringWidth and fs:GetStringWidth()
  if type(w) ~= "number" or w <= 0 then w = fallback or 40 end
  return w
end

---------------------------------------------------------------------------
-- Surfaces
---------------------------------------------------------------------------
local BACKDROP = { bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 }

function T.Frame(parent, name, kind)
  local f = CreateFrame(kind or "Frame", name, parent, "BackdropTemplate")
  return f
end

-- Multi-select dropdown: a button showing what's on; clicking opens a menu of
-- checkboxes that stays open while you tick. opts = { { key, label, short } },
-- get(key) -> bool, set(key, bool).
function T.MultiSelect(parent, width, opts, get, set, onChange)
  local b = T.Button(parent, "", width, nil, 26)
  b.label:ClearAllPoints(); b.label:SetPoint("LEFT", 10, 0); b.label:SetPoint("RIGHT", -26, 0)
  b.label:SetJustifyH("LEFT"); b.label:SetFontObject(T.Font.Body); b.label:SetTextColor(rgb(T.HEX.text))
  b:SetScript("OnMouseDown", nil); b:SetScript("OnMouseUp", nil)
  b.arrow = b:CreateTexture(nil, "OVERLAY"); b.arrow:SetSize(14, 14); b.arrow:SetPoint("RIGHT", -8, 0)
  b.arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
  if b.arrow.SetRotation then b.arrow:SetRotation(-math.pi / 2) end
  function b:Update()
    local on, n = {}, 0
    for _, o in ipairs(opts) do if get(o[1]) then on[#on + 1] = o[3] or o[2] end; n = n + 1 end
    local text
    if #on == 0 then text = "None"
    elseif #on == n and n > 2 then text = "All " .. n
    elseif #on <= 2 then text = table.concat(on, ", ")
    else text = on[1] .. ", " .. on[2] .. " +" .. (#on - 2) end
    self:SetLabel(text)
  end
  b:SetScript("OnClick", function(self)
    T.ShowMenu(self, function()
      local items = {}
      for _, o in ipairs(opts) do
        local key = o[1]
        items[#items + 1] = { text = o[2], checkable = true, checked = get(key), keepOpen = true,
          func = function() set(key, not get(key)); b:Update(); if onChange then onChange(key) end end }
      end
      return items
    end)
  end)
  b:Update()
  return b
end

-- Fettle's own windows. Each gets its own band of frame levels (100 apart) so
-- their parts never interleave, and the one shown or clicked last comes to the front.
local windows = {}
function T.BringToFront(f)
  for i = #windows, 1, -1 do if windows[i] == f then table.remove(windows, i) end end
  windows[#windows + 1] = f
  for i, w in ipairs(windows) do
    if w.SetFrameLevel then w:SetFrameLevel(i * 100) end
  end
  if f.Raise then f:Raise() end
end

function T.Window(f)
  if f.SetToplevel then f:SetToplevel(true) end
  if f.SetClampedToScreen then f:SetClampedToScreen(true) end
  windows[#windows + 1] = f
  local hook = f.HookScript or f.SetScript
  hook(f, "OnShow", function() T.BringToFront(f) end)
  hook(f, "OnMouseDown", function() T.BringToFront(f) end)
  return f
end
T.WindowOrder = function() return windows end

function T.Box(f, bgHex, edgeHex, bgAlpha)
  if not f.SetBackdrop then return f end
  f:SetBackdrop(BACKDROP)
  local r, g, b = rgb(T.HEX[bgHex] or bgHex or "000000")
  f:SetBackdropColor(r, g, b, bgAlpha or 1)
  local er, eg, eb = rgb(T.HEX[edgeHex] or edgeHex or "000000")
  f:SetBackdropBorderColor(er, eg, eb, 1)
  return f
end

function T.Tile(f, file, layer, alpha)
  local tex = f:CreateTexture(nil, layer or "BACKGROUND")
  tex:SetTexture(MEDIA .. file, "REPEAT", "REPEAT")
  if tex.SetHorizTile then tex:SetHorizTile(true); tex:SetVertTile(true) end
  tex:SetAllPoints()
  if alpha then tex:SetAlpha(alpha) end
  return tex
end

-- Iron plate: tiled iron, dark edge, a lighter inner outline and rivets.
function T.Iron(f)
  T.Box(f, "2e2e32", "1a1a1c")
  T.Tile(f, "iron.tga", "BACKGROUND")
  local inner = T.Frame(f)
  inner:SetPoint("TOPLEFT", 4, -4)
  inner:SetPoint("BOTTOMRIGHT", -4, 4)
  if inner.SetBackdrop then
    inner:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    inner:SetBackdropBorderColor(rgb("5a5650"))
  end
  for _, p in ipairs({ { "TOPLEFT", 7, -7 }, { "TOPRIGHT", -7, -7 }, { "BOTTOMLEFT", 7, 7 }, { "BOTTOMRIGHT", -7, 7 } }) do
    local r = f:CreateTexture(nil, "ARTWORK")
    r:SetTexture(MEDIA .. "rivet.tga")
    r:SetSize(10, 10)
    r:SetPoint(p[1], p[2], p[3])
  end
  return f
end

-- Carved stone band (header).
function T.Stone(f)
  T.Box(f, "46443f", "1a1a1c")
  T.Tile(f, "stone.tga", "BACKGROUND")
  local hi = f:CreateTexture(nil, "BORDER")
  hi:SetColorTexture(1, 1, 1, 0.07)
  hi:SetPoint("TOPLEFT", 1, -1); hi:SetPoint("TOPRIGHT", -1, -1); hi:SetHeight(1)
  local lo = f:CreateTexture(nil, "BORDER")
  lo:SetColorTexture(0, 0, 0, 0.45)
  lo:SetPoint("BOTTOMLEFT", 1, 1); lo:SetPoint("BOTTOMRIGHT", -1, 1); lo:SetHeight(3)
  return f
end

-- Recessed slot: stone floor with an inner shadow.
function T.Slot(f, plain)
  T.Box(f, plain and "slot" or "3a3936", "dark")
  if not plain then T.Tile(f, "stone.tga", "BACKGROUND", 0.85) end
  local sh = f:CreateTexture(nil, "BORDER")
  sh:SetColorTexture(0, 0, 0, 0.55)
  sh:SetPoint("TOPLEFT", 1, -1); sh:SetPoint("TOPRIGHT", -1, -1); sh:SetHeight(3)
  return f
end

function T.Line(parent, alpha)
  local t = parent:CreateTexture(nil, "ARTWORK")
  t:SetColorTexture(0, 0, 0, alpha or 0.55)
  t:SetHeight(1)
  local h = parent:CreateTexture(nil, "ARTWORK")
  h:SetColorTexture(1, 1, 1, 0.05)
  h:SetHeight(1)
  h:SetPoint("TOPLEFT", t, "BOTTOMLEFT")
  h:SetPoint("TOPRIGHT", t, "BOTTOMRIGHT")
  return t
end

function T.Icon(parent, file, size, hex)
  local t = parent:CreateTexture(nil, "ARTWORK")
  t:SetTexture(MEDIA .. file)
  t:SetSize(size or 16, size or 16)
  if hex then t:SetVertexColor(rgb(T.HEX[hex] or hex)) end
  return t
end

---------------------------------------------------------------------------
-- Controls
---------------------------------------------------------------------------
local function tooltip(owner, lines)
  if not GameTooltip or not lines then return end
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  for i, l in ipairs(lines) do
    if i == 1 then GameTooltip:SetText(l, 1, 1, 1) else GameTooltip:AddLine(l, 0.85, 0.82, 0.75, true) end
  end
  GameTooltip:Show()
end
T.Tooltip = tooltip

function T.Button(parent, text, w, onClick, h)
  local b = T.Frame(parent, nil, "Button")
  b:SetSize(w or 80, h or 26)
  T.Box(b, "btn", "edge")
  local fs = T.Text(b, "SC", "brass")
  fs:SetPoint("CENTER", 0, 0)
  fs:SetJustifyH("CENTER")
  fs:SetText(text or "")
  b.label = fs
  local hl = b:CreateTexture(nil, "HIGHLIGHT")
  hl:SetColorTexture(1, 0.85, 0.6, 0.08)
  hl:SetAllPoints()
  b:SetScript("OnMouseDown", function() fs:SetPoint("CENTER", 1, -1) end)
  b:SetScript("OnMouseUp", function() fs:SetPoint("CENTER", 0, 0) end)
  b:SetScript("OnEnter", function(self) if self.tip then tooltip(self, self.tip) end end)
  b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  if onClick then b:SetScript("OnClick", onClick) end
  function b:SetLabel(t) fs:SetText(t) end
  return b
end

function T.IconButton(parent, icon, size, tip, onClick)
  local b = T.Frame(parent, nil, "Button")
  b:SetSize(size or 24, size or 22)
  T.Box(b, "btn", "edge")
  local t = T.Icon(b, icon, math.min(size or 24, 22) - 8, "brass")
  t:SetPoint("CENTER")
  b.icon = t
  local hl = b:CreateTexture(nil, "HIGHLIGHT")
  hl:SetColorTexture(1, 0.85, 0.6, 0.1)
  hl:SetAllPoints()
  b.tip = tip and { tip } or nil
  b:SetScript("OnEnter", function(self) if self.tip then tooltip(self, self.tip) end end)
  b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  if onClick then b:SetScript("OnClick", onClick) end
  return b
end

function T.Edit(parent, w, numeric, h)
  local e = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
  e:SetSize(w or 60, h or 24)
  T.Box(e, "slot", "dark")
  e:SetFontObject(T.Font.Body)
  e:SetTextColor(rgb(T.HEX.text))
  e:SetTextInsets(6, 6, 0, 0)
  e:SetAutoFocus(false)
  if numeric then e:SetNumeric(true); e:SetJustifyH("CENTER") end
  e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  local ph = T.Text(e, "Italic", "faint")
  ph:SetPoint("LEFT", 7, 0)
  e.placeholder = ph
  local function upd() if e:GetText() == "" and not e:HasFocus() then ph:Show() else ph:Hide() end end
  e:SetScript("OnEditFocusGained", function(self) ph:Hide(); if self.onFocus then self.onFocus(self) end end)
  e:SetScript("OnEditFocusLost", upd)
  e:SetScript("OnTextChanged", function(self, user) upd(); if self.onText then self.onText(self:GetText(), user) end end)
  function e:SetPlaceholder(t) ph:SetText(t or ""); upd() end
  return e
end

-- Item box: type a name, shift-click an item, or drop one onto it.
function T.ItemEdit(parent, w)
  local e = T.Edit(parent, w)
  e.onFocus = function(self) ns.activeItemBox = self end
  local function takeCursor(self)
    if GetCursorInfo then
      local kind, id, link = GetCursorInfo()
      if kind == "item" then
        self:SetText(link or tostring(id))
        if ClearCursor then ClearCursor() end
      end
    end
  end
  e:SetScript("OnReceiveDrag", takeCursor)
  e:SetScript("OnMouseDown", takeCursor)
  return e
end

local function insertLink(link)
  local box = ns.activeItemBox
  if box and box.HasFocus and box:HasFocus() and link then box:SetText(link) end
end
if hooksecurefunc then
  if ChatEdit_InsertLink then hooksecurefunc("ChatEdit_InsertLink", insertLink) end
  if ChatFrameUtil and ChatFrameUtil.InsertLink then hooksecurefunc(ChatFrameUtil, "InsertLink", insertLink) end
end

-- Small checkbox in the theme.
function T.Check(parent, label, onClick)
  local b = T.Frame(parent, nil, "Button")
  b:SetSize(18, 18)
  T.Box(b, "slot", "edge")
  local tick = b:CreateTexture(nil, "OVERLAY")
  tick:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
  tick:SetSize(22, 22)
  tick:SetPoint("CENTER", 1, 0)
  tick:Hide()
  b.tick = tick
  if label then
    local fs = T.Text(parent, "Body", "text")
    fs:SetPoint("LEFT", b, "RIGHT", 6, 0)
    fs:SetText(label)
    b.label = fs
  end
  function b:SetChecked(v) self.checked = v and true or false; if v then tick:Show() else tick:Hide() end end
  function b:GetChecked() return self.checked end
  b:SetScript("OnClick", function(self)
    self:SetChecked(not self.checked)
    if self.onToggle then self.onToggle(self.checked) end
  end)
  b.onToggle = onClick
  return b
end

---------------------------------------------------------------------------
-- Stamped tag
---------------------------------------------------------------------------
function T.Tag(parent)
  local f = T.Frame(parent)
  f:SetHeight(14)
  if f.SetBackdrop then f:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 }) end
  local fs = T.Text(f, "Tag")
  fs:SetPoint("CENTER", 0, 0)
  f.fs = fs
  function f:Set(text, hex)
    local r, g, b = rgb(T.HEX[hex] or hex or T.HEX.dim)
    fs:SetText(string.upper(text or ""))
    fs:SetTextColor(r, g, b)
    if self.SetBackdropBorderColor then self:SetBackdropBorderColor(r, g, b, 0.9) end
    self:SetWidth(T.Width(fs, #(text or "") * 6) + 10)
    self:Show()
  end
  return f
end

-- A row of up to n tags; :Set({{label, hex}, ...})
-- maxW: tags that would run past this width are folded into a "+N" tag.
function T.TagRow(parent, n, maxW)
  local row = { tags = {}, maxW = maxW }
  for i = 1, n or 4 do
    local t = T.Tag(parent)
    if i == 1 then row.first = t else t:SetPoint("LEFT", row.tags[i - 1], "RIGHT", 5, 0) end
    t:Hide()
    row.tags[i] = t
  end
  function row:SetPoint(...) self.first:SetPoint(...) end
  function row:Set(list)
    local x, shown = 0, 0
    local total = list and #list or 0
    for i, t in ipairs(self.tags) do
      local item = list and list[i]
      if item and (not self.full) then
        t:Set(item[1], item[2])
        local w = (t.GetWidth and t:GetWidth()) or 40
        if type(w) ~= "number" then w = 40 end
        if self.maxW and x + w > self.maxW then
          -- no room: turn this slot into "+N" if that fits, else hide it
          local rest = total - shown
          t:Set("+" .. rest, "faint")
          local w2 = (t.GetWidth and t:GetWidth()) or 24
          if type(w2) ~= "number" or x + w2 > self.maxW then t:Hide() end
          self.full = true
        else
          x = x + w + 5
          shown = shown + 1
        end
      else
        t:Hide()
      end
    end
    self.full = nil
  end
  return row
end

function T.SetGem(tex, status)
  local file = ({ ready = "gem-ready", done = "gem-ready", low = "gem-low", missing = "gem-missing", todo = "gem-missing",
                  optional = "gem-optional", locked = "gem-locked" })[status] or "gem-optional"
  tex:SetTexture(MEDIA .. file .. ".tga")
end

---------------------------------------------------------------------------
-- Pop-up menu (one shared). items: { text=, func=, hex=, header=true, sep=true, checked= }
---------------------------------------------------------------------------
-- items may be a table or a function returning one. An item with keepOpen
-- runs its func and redraws the menu (for multi-select lists); checkable
-- items show an empty box when unchecked.
function T.ShowMenu(anchor, items)
  local source = items
  if type(items) == "function" then items = items() end
  local m = T.menu
  if not m then
    m = T.Frame(UIParent, "FettleMenu")
    T.Box(m, "232225", "edge")
    m:SetFrameStrata("FULLSCREEN_DIALOG")
    m:EnableMouse(true)
    m:Hide()
    m.rows = {}
    -- an invisible full-screen catcher: any click outside the menu closes it
    local blocker = CreateFrame("Button", "FettleMenuBlocker", UIParent)
    blocker:SetAllPoints(UIParent)
    blocker:SetFrameStrata("FULLSCREEN")
    blocker:EnableMouse(true)
    if blocker.RegisterForClicks then blocker:RegisterForClicks("AnyUp") end
    blocker:SetScript("OnClick", function() m:Hide() end)
    blocker:Hide()
    m.blocker = blocker
    m:SetScript("OnShow", function() blocker:Show() end)
    m:SetScript("OnHide", function() blocker:Hide() end)
    -- Escape closes just the menu, not the window behind it
    if m.EnableKeyboard then m:EnableKeyboard(true) end
    m:SetScript("OnKeyDown", function(self, key)
      if key == "ESCAPE" then
        if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(false) end
        self:Hide()
      elseif self.SetPropagateKeyboardInput then
        self:SetPropagateKeyboardInput(true)
      end
    end)
    T.menu = m
  end
  local y, width = -4, 180
  for i, it in ipairs(items) do
    local r = m.rows[i]
    if not r then
      r = CreateFrame("Button", nil, m)
      r.fs = T.Text(r, "Body", "text")
      r.fs:SetPoint("LEFT", 12, 0)
      r.line = r:CreateTexture(nil, "ARTWORK")
      r.line:SetColorTexture(rgb("3a3836"))
      r.line:SetHeight(1)
      r.line:SetPoint("LEFT", 0, 0); r.line:SetPoint("RIGHT", 0, 0)
      r.hl = r:CreateTexture(nil, "HIGHLIGHT")
      r.hl:SetColorTexture(1, 0.85, 0.6, 0.1)
      r.hl:SetAllPoints()
      m.rows[i] = r
    end
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", 1, y)
    r:SetPoint("TOPRIGHT", -1, y)
    r.line:Hide(); r.fs:Show()
    r:SetScript("OnClick", nil)
    if it.sep then
      r:SetHeight(9); r.line:Show(); r.fs:Hide(); r:EnableMouse(false)
      y = y - 9
    elseif it.header then
      r:SetHeight(20); r:EnableMouse(false)
      r.fs:SetFontObject(T.Font.SCSmall); r.fs:SetTextColor(rgb(T.HEX.faint)); r.fs:SetText(string.upper(it.text))
      y = y - 20
    else
      r:SetHeight(24); r:EnableMouse(true)
      r.fs:SetFontObject(T.Font.Body)
      r.fs:SetTextColor(rgb(T.HEX[it.hex or "text"] or it.hex))
      local box = it.checked and "|TInterface\\Buttons\\UI-CheckBox-Check:14:14|t "
        or (it.checkable and "|TInterface\\Buttons\\UI-CheckBox-Up:14:14|t " or "")
      r.fs:SetText(box .. it.text)
      local fn = it.func
      if it.keepOpen then
        r:SetScript("OnClick", function() if fn then fn() end; T.ShowMenu(anchor, source) end)
      else
        r:SetScript("OnClick", function() m:Hide(); if fn then fn() end end)
      end
      y = y - 24
    end
    width = math.max(width, T.Width(r.fs, 160) + 34)
    r:Show()
  end
  for i = #items + 1, #m.rows do m.rows[i]:Hide() end
  m:SetSize(width, -y + 4)
  m:ClearAllPoints()
  m:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -2)
  m:Show()
  m.blocker:Show()
  return m
end

---------------------------------------------------------------------------
-- Scrolling list of mixed rows. kinds[k] = { height=, create=fn(row), fill=fn(row, entry) }
---------------------------------------------------------------------------
function T.List(parent, kinds, width)
  local list = { kinds = kinds, pools = {}, used = {} }
  local sf = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
  sf:SetPoint("TOPLEFT", 6, -4)
  sf:SetPoint("BOTTOMRIGHT", -26, 4)
  local child = CreateFrame("Frame", nil, sf)
  child:SetSize(width, 10)
  sf:SetScrollChild(child)
  list.scroll, list.child, list.width = sf, child, width
  function list:Render(entries)
    for _, pool in pairs(self.pools) do for _, r in ipairs(pool) do r:Hide(); r.inUse = false end end
    local y = 0
    local counters = {}
    for _, e in ipairs(entries) do
      local kind = self.kinds[e.kind]
      if kind then
        local pool = self.pools[e.kind] or {}
        self.pools[e.kind] = pool
        counters[e.kind] = (counters[e.kind] or 0) + 1
        local r = pool[counters[e.kind]]
        if not r then
          r = CreateFrame("Button", nil, self.child)
          r:SetWidth(self.width)
          kind.create(r)
          r:SetScript("OnEnter", function(row) if row.tip then tooltip(row, row.tip) end end)
          r:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
          pool[counters[e.kind]] = r
        end
        local h = (type(kind.height) == "function") and kind.height(e) or kind.height
        r:SetHeight(h)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", 0, -y)
        r.tip = nil
        kind.fill(r, e)
        r:Show()
        r.inUse = true
        y = y + h
      end
    end
    self.child:SetHeight(math.max(10, y))
  end
  return list
end
