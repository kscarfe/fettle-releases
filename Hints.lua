-- Fettle: side panel at the bank, mailbox and vendors, plus the
-- dungeon-entry reminder.
local _, ns = ...
local UI = ns.UI

local T = ns.T
local PW, PH = 400, 470
local Hints = {}
ns.Hints = Hints

local C = T.Color
local LW = PW - 64

local KINDS = {
  group = { height = 46, create = function(r)
    r.name = T.Text(r, "Name", "parch"); r.name:SetPoint("TOPLEFT", 4, -6)
    r.sub = T.Text(r, "SCSmall", "blue"); r.sub:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -2)
    r.btn = T.Button(r, "Attach", 90, nil, 26); r.btn:SetPoint("RIGHT", -2, 0)
    r.line = T.Line(r, 0.7); r.line:SetPoint("BOTTOMLEFT"); r.line:SetPoint("BOTTOMRIGHT")
  end, fill = function(r, e)
    r.name:SetText(e.title)
    r.sub:SetText(e.sub or ""); r.sub:SetTextColor(T.rgb(T.HEX[e.subHex or "blue"]))
    if e.button then r.btn:Show(); r.btn:SetLabel(e.button[1]); r.btn:SetScript("OnClick", e.button[2]) else r.btn:Hide() end
  end },
  item = { height = 28, create = function(r)
    r.qty = T.Text(r, "Big", "brass"); r.qty:SetPoint("RIGHT", r, "LEFT", 40, 0); r.qty:SetJustifyH("RIGHT")
    r.name = T.Text(r, "Bold", "text"); r.name:SetPoint("LEFT", 48, 0); r.name:SetWidth(LW - 170)
    r.tag = T.Tag(r); r.tag:SetPoint("RIGHT", -4, 0)
    r.btn = T.Button(r, "Buy", 50, nil, 22); r.btn:SetPoint("RIGHT", -4, 0)
    r.line = T.Line(r, 0.45); r.line:SetPoint("BOTTOMLEFT"); r.line:SetPoint("BOTTOMRIGHT")
  end, fill = function(r, e)
    r.qty:SetText(tostring(e.item.give))
    r.name:SetText(e.item.n)
    r.tip = e.item.full and { e.item.n, e.item.full } or nil
    if e.button then
      r.tag:Hide(); r.btn:Show(); r.btn:SetLabel(e.button[1]); r.btn:SetScript("OnClick", e.button[2])
      r.name:SetText(e.item.n .. C("dim", "  " .. (e.item.reason or "")))
    else
      r.btn:Hide(); r.tag:Set(e.item.reason or "", e.tagHex or "dim")
    end
  end },
}

local TAG_HEX = { ["wish list"] = "blue", ["can learn this recipe"] = "parch", suggested = "dim" }
local function tagHex(reason)
  if not reason then return "dim" end
  if TAG_HEX[reason] then return TAG_HEX[reason] end
  if reason:find("^checklist") then return "craft" end
  if reason:find("^main ") then return "brass" end
  return "dim"
end
local function shortReason(reason)
  if not reason then return "" end
  if reason:find("^checklist") then return "kit gap" end
  if reason == "can learn this recipe" then return "can learn" end
  if reason == "no alt can learn it yet" then return "nobody can learn" end
  if reason == "no alt needs it" then return "unneeded" end
  if reason == "above every alt's level" then return "too high level" end
  if reason == "tagged for the bank" then return "tagged" end
  if reason:find("^surplus") then return "surplus" end
  if reason:find("^not in ") then return "not in kit" end
  if reason:find("^bigger bag") then return "bigger bag" end
  if reason:find("^levelling ") then return "levelling" end
  if #reason > 18 then return reason:sub(1, 16) .. "..." end
  return reason
end

function Hints.Create()
  if Hints.frame then return Hints.frame end
  local f = T.Frame(UIParent, "FettleHints")
  T.Window(f)
  f:SetSize(PW, PH)
  T.Iron(f)
  f:SetFrameStrata("HIGH")
  f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  -- remember where the player drags it, so it stays put
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, relPoint, x, y = self:GetPoint(1)
    if point then ns.db.hintsPos = { point, relPoint, x, y } end
  end)
  local head = T.Frame(f)
  head:SetPoint("TOPLEFT", 14, -14); head:SetPoint("TOPRIGHT", -14, -14); head:SetHeight(42)
  T.Stone(head)
  f.title = T.Text(head, "Title", "title")
  f.title:SetPoint("LEFT", 12, 0)
  local close = T.IconButton(head, "icon-close.tga", 24, "Close", function() f:Hide() end)
  close:SetPoint("RIGHT", -8, 0)
  f.info = T.Text(f, "Italic", "faint")
  f.info:SetPoint("BOTTOMLEFT", 16, 14)
  f.info:SetWidth(PW - 32)
  local body = T.Frame(f)
  body:SetPoint("TOPLEFT", 14, -62)
  body:SetPoint("BOTTOMRIGHT", -14, 34)
  T.Slot(body)
  f.list = T.List(body, KINDS, LW)
  f:Hide()
  -- Escape closes the panel
  if UISpecialFrames then table.insert(UISpecialFrames, "FettleHints") end
  -- ...and so does closing the mailbox, bank or vendor it belongs to
  for _, name in ipairs({ "MailFrame", "BankFrame", "MerchantFrame" }) do
    local target = _G[name]
    if target and target.HookScript then
      target:HookScript("OnHide", function() if Hints.owner == target then Hints.Close() end end)
    end
  end
  -- Closed by the player (Escape or the X): stay closed until the next visit
  f:HookScript("OnHide", function() if not Hints.internalHide then Hints.dismissed = true end end)
  Hints.frame = f
  return f
end

local function Anchor(f, target)
  if f:IsShown() and Hints.anchoredFor == target then return end -- already placed for this visit
  Hints.anchoredFor = target
  f:ClearAllPoints()
  local pos = ns.db and ns.db.hintsPos
  if pos then
    f:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
  elseif target and target.IsShown and target:IsShown() then
    f:SetPoint("TOPLEFT", target, "TOPRIGHT", 8, 0)
  else
    f:SetPoint("RIGHT", UIParent, "RIGHT", -40, 60)
  end
end

-- rows: { header=, sub=, subHex=, button={text, fn} } or { item=it, button=... }
local function Show(title, info, rows, anchorTo)
  local f = Hints.Create()
  if Hints.dismissed then return end
  if #rows == 0 then Hints.Hide() return end
  f.title:SetText(title)
  f.info:SetText(info or "")
  Hints.owner = anchorTo
  Anchor(f, anchorTo)
  local entries = {}
  for _, x in ipairs(rows) do
    if x.header then
      entries[#entries + 1] = { kind = "group", title = x.header, sub = x.sub, subHex = x.subHex, button = x.button }
    else
      local it = { n = x.item.n, give = x.item.give, reason = x.button and x.item.reason or shortReason(x.item.reason), full = x.item.reason }
      entries[#entries + 1] = { kind = "item", item = it, button = x.button, tagHex = tagHex(x.item.reason) }
    end
  end
  f.list:Render(entries)
  f:Show()
end

function Hints.Hide()
  if Hints.frame and Hints.frame:IsShown() then
    Hints.internalHide = true
    Hints.frame:Hide()
    Hints.internalHide = false
  end
end

---------------------------------------------------------------------------
-- Mailbox
---------------------------------------------------------------------------
function Hints.Mail()
  if not ns.db.settings.hintsMail then return Hints.Hide() end
  local me = ns.Me()
  local rows = {}
  for _, g in ipairs(ns.MailHints(me)) do
    local to, items = g.to, g.items
    local sub, hex = (to.className or "") .. " " .. (to.level or ""), "blue"
    if g.pool then sub, hex = "BANK ALT · THE POOL", "brass" elseif g.main then sub, hex = string.upper(ns.MainNoun(g.main)), "brass" end
    rows[#rows + 1] = { header = ns.DisplayName(to), sub = sub, subHex = hex,
                        button = { "Attach " .. #items, function() ns.AttachMail(to, items) end } }
    for _, it in ipairs(items) do rows[#rows + 1] = { item = it } end
  end
  Show("DISPATCH", "Whole stacks · bound items never offered", rows, MailFrame)
end

---------------------------------------------------------------------------
-- Bank
---------------------------------------------------------------------------
function Hints.Bank()
  if not ns.db.settings.hintsBank then return Hints.Hide() end
  local me = ns.Me()
  local res = ns.BankHints(me)
  local rows = {}
  if #res.self > 0 then
    local items = res.self
    rows[#rows + 1] = { header = "For " .. ns.DisplayName(me), sub = "KIT GAPS", subHex = "craft", button = { "Withdraw", function() ns.Withdraw(items) end } }
    for _, it in ipairs(items) do rows[#rows + 1] = { item = it, verb = "Take" } end
  end
  for _, g in ipairs(res.alts) do
    local items = g.items
    local sub = g.pool and "TO MAIL · BANK POOL" or (g.main and ("TO MAIL · " .. string.upper(ns.MainNoun(g.main))) or "TO MAIL")
    rows[#rows + 1] = { header = ns.DisplayName(g.to), sub = sub, subHex = "brass", button = { "Withdraw", function() ns.Withdraw(items) end } }
    for _, it in ipairs(items) do rows[#rows + 1] = { item = it, verb = "Take" } end
  end
  Show("BANK", "Whole stacks are withdrawn", rows, BankFrame)
end

---------------------------------------------------------------------------
-- Vendor
---------------------------------------------------------------------------
function Hints.Vendor()
  if not ns.db.settings.hintsVendor then return Hints.Hide() end
  local me = ns.Me()
  local list = ns.VendorHints(me)
  local rows = {}
  if #list > 0 then
    rows[#rows + 1] = { header = "This vendor sells", sub = "THINGS " .. string.upper(ns.DisplayName(me)) .. " NEEDS", subHex = "craft", button = { "Buy all", function()
      for _, v in ipairs(list) do ns.Buy(v.index, v.buy) end
    end } }
  end
  for _, v in ipairs(list) do
    rows[#rows + 1] = { item = { n = v.n, give = v.buy, reason = v.reason },
                        button = { "Buy", function() ns.Buy(v.index, v.buy) end } }
  end
  Show("VENDOR", "Check the price before buying", rows, MerchantFrame)
end

---------------------------------------------------------------------------
-- Wiring
---------------------------------------------------------------------------
local where = nil -- "mail" | "bank" | "vendor"

-- The mailbox / bank / vendor closed: stop hinting until the next visit.
function Hints.Close()
  Hints.anchoredFor = nil
  where = nil
  Hints.owner = nil
  Hints.Hide()
end

local function Visit(kind)
  where = kind
  Hints.dismissed = false
end
local function refresh()
  if where == "mail" then Hints.Mail()
  elseif where == "bank" then Hints.Bank()
  elseif where == "vendor" then Hints.Vendor() end
end

local queued = false
ns.OnChange(function(what)
  if what == "mail_open" then Visit("mail")
  elseif what == "bank_open" then Visit("bank")
  elseif what == "mail_close" or what == "bank_close" then Hints.Close(); return end
  if not where or queued then return end
  queued = true
  local function go() queued = false; local ok, err = pcall(refresh); if not ok then ns.Print("hint error:", err) end end
  if C_Timer and C_Timer.After then C_Timer.After(0.2, go) else go() end
end)

ns.On("MERCHANT_SHOW", function()
  Visit("vendor")
  if C_Timer and C_Timer.After then C_Timer.After(0.3, function() pcall(Hints.Vendor) end) else Hints.Vendor() end
end)
ns.On("MERCHANT_CLOSED", function() if where == "vendor" then Hints.Close() end end)

---------------------------------------------------------------------------
-- Dungeon entry / exit
---------------------------------------------------------------------------
local inDungeon = false
local function CheckInstance()
  if not IsInInstance then return end
  local inInst, kind = IsInInstance()
  local nowDungeon = inInst and kind == "party"
  if nowDungeon and not inDungeon then
    inDungeon = true
    local me = ns.Me()
    if ns.ScanDungeonQuests then ns.ScanDungeonQuests() end
    local zone = GetInstanceInfo and GetInstanceInfo()
    local djKey = ns.DJFind and ns.DJFind(zone)
    if djKey then
      zone = djKey
      ns.ScanDJStatus()
      local missing = {}
      for _, q in ipairs(ns.DungeonQuests(me, zone)) do if q.state == "missing" then missing[#missing + 1] = q.name end end
      local have, _, total = ns.DungeonQuestSummary(me, zone)
      ns.Print(zone .. ": " .. have .. " of " .. total .. " quests in your log" .. (#missing > 0 and (". Missing: " .. table.concat(missing, ", ")) or "."))
      if #missing == 0 then me.ticks.quests = true end
      zone = nil -- handled
    end
    local qs = zone and me.dungeonQuests and me.dungeonQuests[zone]
    if qs and #qs > 0 then
      ns.Print(#qs .. " quest" .. (#qs > 1 and "s" or "") .. " for " .. zone .. " in your log: " .. table.concat(qs, ", "))
      me.ticks.quests = true
    elseif zone then
      ns.Print("no quests for " .. zone .. " in your log.")
    end
    local missing, low = ns.Summary(me)
    if missing + low > 0 then
      ns.Print(C("orange", missing .. " missing") .. ", " .. low .. " low on your checklist. /fettle to view.")
      if ns.db.settings.popupOnDungeon then
        UI.selectedKey = me.key
        UI.Show(1)
      end
    end
  elseif not nowDungeon and inDungeon then
    inDungeon = false
    if ns.db.settings.resetTicksOnLeave then ns.NewRun(ns.Me()) end
  end
end
ns.On("PLAYER_ENTERING_WORLD", function() if C_Timer and C_Timer.After then C_Timer.After(2, CheckInstance) else CheckInstance() end end)
ns.On("ZONE_CHANGED_NEW_AREA", CheckInstance)
