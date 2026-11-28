-- Fettle: core namespace, saved variables, events and slash commands.
local ADDON, ns = ...
ns = ns or {}
_G.Fettle = ns

ns.VERSION = "0.9.0"
ns.ICON = "Interface\\AddOns\\Fettle\\Media\\icon"
ns.ROLES = { "TANK", "HEALER", "MELEE", "RANGED", "CASTER", "BANK" }
ns.ROLE_NAMES = { TANK = "Tank", HEALER = "Healer", MELEE = "Melee DPS", RANGED = "Ranged DPS", CASTER = "Caster DPS", BANK = "Bank alt" }

-- Classes that use mana (Forever keeps Classic resource rules).
ns.MANA_CLASSES = { PALADIN = true, HUNTER = true, PRIEST = true, SHAMAN = true, MAGE = true, WARLOCK = true, DRUID = true }

local unpack = unpack or table.unpack
ns.unpack = unpack

---------------------------------------------------------------------------
-- Utilities
---------------------------------------------------------------------------
function ns.Print(...)
  local parts = {}
  for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
  local msg = "|cff66ccffFettle|r: " .. table.concat(parts, " ")
  if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(msg) else print(msg) end
end

function ns.DeepCopy(v)
  if type(v) ~= "table" then return v end
  local t = {}
  for k, x in pairs(v) do t[k] = ns.DeepCopy(x) end
  return t
end

function ns.Lower(s) return s and string.lower(s) or nil end

function ns.Trim(s) return (s and s:gsub("^%s+", ""):gsub("%s+$", "")) or s end

-- Parse an item link or plain name. Returns id (number or nil), name (string or nil).
function ns.ParseItem(text)
  if not text or text == "" then return nil, nil end
  local id = text:match("item:(%d+)")
  local name = text:match("%[(.-)%]")
  if id then id = tonumber(id) end
  if not name then
    name = ns.Trim(text)
    if name:match("^%d+$") then id = tonumber(name); name = nil end
  end
  if id and not name then name = ns.ItemNameByID(id) end
  if name and not id and C_Item and C_Item.GetItemInfoInstant then
    local ok, iid = pcall(C_Item.GetItemInfoInstant, name)
    if ok and type(iid) == "number" then id = iid end
  end
  return id, name
end

function ns.ItemNameByID(id)
  if not id then return nil end
  if C_Item and C_Item.GetItemNameByID then
    local ok, n = pcall(C_Item.GetItemNameByID, id)
    if ok and n then return n end
  end
  if C_Item and C_Item.GetItemInfo then
    local ok, n = pcall(C_Item.GetItemInfo, id)
    if ok and n then return n end
  end
  if GetItemInfo then
    local ok, n = pcall(GetItemInfo, id)
    if ok and n then return n end
  end
  return nil
end

function ns.Now() return (time and time()) or os.time() end

function ns.Ago(t)
  if not t then return "never" end
  local d = ns.Now() - t
  if d < 120 then return "just now" end
  if d < 7200 then return math.floor(d / 60) .. "m ago" end
  if d < 172800 then return math.floor(d / 3600) .. "h ago" end
  return math.floor(d / 86400) .. "d ago"
end

---------------------------------------------------------------------------
-- Saved variables
---------------------------------------------------------------------------
ns.DEFAULT_SETTINGS = {
  popupOnDungeon = true,     -- open the checklist when zoning into a dungeon with gaps
  hintsBank = true,
  hintsMail = true,
  hintsVendor = true,
  hintsBags = false,
  deGear = false,
  hintKits = true,
  hintWish = true,
  hintLearn = false,
  hintMains = false,
  receiveBugs = false,
  resetTicksOnLeave = true,  -- clear manual ticks when leaving a dungeon
  autoSuggest = false,       -- profession-based wish list suggestions (off: wishlist only)
  -- bank pool: what other alts are prompted to mail to the bank alt
  bankRecipes = true,        -- recipes none of your alts can learn yet
  bankMats = true,           -- trade goods no alt needs
  bankSurplus = true,        -- consumables above surplusCap x the alt's kit amount
  bankTagged = true,         -- items / categories you tagged "bank it"
  bankGear = true,           -- tradeable gear above every alt's level
  surplusCap = 2,
  suggestCrafts = 3,         -- crafts' worth of reagents per suggested recipe
  suggestMaxRecipes = 3,
  minDurability = 80,
  minCampMinutes = 45,
  planWants = true,          -- levelling plan materials show up in mail and vendor hints       -- Camp Benefits counts as done with at least this long left
  minFreeSlots = 4,
}

function ns.InitDB()
  FettleDB = FettleDB or {}
  local db = FettleDB
  db.version = db.version or 1
  db.chars = db.chars or {}
  db.custom = db.custom or {}
  db.custom.categories = db.custom.categories or {}
  db.custom.needs = db.custom.needs or {}
  db.custom.tasks = db.custom.tasks or {}
  db.settings = db.settings or {}
  for k, v in pairs(ns.DEFAULT_SETTINGS) do
    if db.settings[k] == nil then db.settings[k] = v end
  end
  db.minimap = db.minimap or { angle = 200, hide = false }
  db.mains = db.mains or {}
  db.bankTags = db.bankTags or {}
  db.bankTags.items = db.bankTags.items or {}
  db.bankTags.cats = db.bankTags.cats or {}
  db.collapsed = db.collapsed or {}
  -- 0.9: four building blocks. Kits keep their Must bring lines (Nice to have
  -- goes), and the extra mail suggestions start off.
  if (db.schema or 1) < 2 then
    for _, c in pairs(db.chars) do
      if c.kit then
        local keep = {}
        for _, l in ipairs(c.kit) do if not l.optional then keep[#keep + 1] = l end end
        c.kit = keep
      end
      if c.extras and c.extras.items then
        for k, x in pairs(c.extras.items) do if x.optional then c.extras.items[k] = nil end end
      end
    end
    for _, k in ipairs({ "hintLearn", "hintMains", "deGear", "hintsBags", "autoSuggest" }) do db.settings[k] = false end
    db.schema = 2
  end
  ns.db = db
  return db
end

function ns.CharKey(name, realm)
  return (name or "?") .. "-" .. (realm or "?")
end

-- WoW Forever characters have a first and a last name ("Asha Brightvale").
-- Mail needs the full name. Try every API that might return it; a result
-- with a space in it is the full name.
local function trySpace(v)
  if type(v) == "string" and v:find(" ", 1, true) then return v end
end
function ns.DetectFullName()
  local found, tried = nil, {}
  local function try(label, fn, ...)
    if not fn then return end
    local ok, a = pcall(fn, ...)
    if ok then
      tried[#tried + 1] = label .. "=" .. tostring(a)
      found = found or trySpace(a)
    end
  end
  try("UnitName", UnitName, "player")
  try("GetUnitName", GetUnitName, "player", true)
  try("UnitFullName", UnitFullName, "player")
  try("UnitNameUnmodified", UnitNameUnmodified, "player")
  if GetPlayerInfoByGUID and UnitGUID then
    local ok, _, _, _, _, _, n = pcall(GetPlayerInfoByGUID, UnitGUID("player"))
    if ok then tried[#tried + 1] = "GetPlayerInfoByGUID=" .. tostring(n); found = found or trySpace(n) end
  end
  ns.nameProbe = table.concat(tried, ", ")
  return found
end

function ns.CurrentKey()
  local name = UnitName and UnitName("player") or "Player"
  local realm = (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName and GetRealmName()) or "Realm"
  local full = ns.DetectFullName()
  return ns.CharKey(full or name, realm), name, realm, full
end

-- The name to show: first and last name when known.
function ns.DisplayName(c)
  if not c then return "?" end
  return c.mailName or c.fullName or c.name or c.key or "?"
end

-- The name to type in the mail To field.
function ns.MailName(c)
  return c.mailName or c.fullName or c.name
end

-- Look an alt's full name up without logging in on it: the mail box's own
-- name completion (which knows your characters, friends and guild), then the
-- guild roster. Saves what it finds.
local function firstWord(s) return s and s:match("^(%S+)") end
local function uniqueMatch(list, c)
  local found
  local first = c.name and c.name:lower()
  for _, n in ipairs(list) do
    n = n:gsub("%-[^%s]*$", "") -- drop any realm suffix
    if n:find(" ", 1, true) and firstWord(n):lower() == first then
      if found and found ~= n then return nil end -- two people share that first name: don't guess
      found = n
    end
  end
  return found
end

function ns.FindFullName(c)
  if not c.name then return nil end
  local names = {}
  if GetAutoCompleteResults then
    local inc, exc = 0xffffffff, 0
    if AUTOCOMPLETE_LIST and AUTOCOMPLETE_LIST.MAIL then inc, exc = AUTOCOMPLETE_LIST.MAIL.include, AUTOCOMPLETE_LIST.MAIL.exclude end
    local ok, res = pcall(GetAutoCompleteResults, c.name, 20, #c.name, true, inc, exc)
    if ok and type(res) == "table" then
      for _, r in ipairs(res) do
        local n = type(r) == "table" and r.name or r
        if type(n) == "string" then names[#names + 1] = n end
      end
    end
  end
  local hit = uniqueMatch(names, c)
  if hit then return hit end
  if GetNumGuildMembers and GetGuildRosterInfo then
    local g = {}
    local ok, n = pcall(GetNumGuildMembers)
    for i = 1, (ok and n or 0) do
      local ok2, name, _, _, level, _, _, _, _, _, _, class = pcall(GetGuildRosterInfo, i)
      if ok2 and name and (not class or not c.class or class == c.class) then g[#g + 1] = name end
    end
    hit = uniqueMatch(g, c)
  end
  return hit
end

function ns.ResolveMailName(c)
  local n = ns.MailName(c)
  if n and n:find(" ", 1, true) then return n end
  local full = ns.FindFullName(c)
  if full then c.fullName = full; return full end
  return n
end

-- Fill in any alts' missing full names (e.g. after the guild roster loads).
function ns.LearnFullNames(extra)
  if not ns.db then return end
  for _, c in pairs(ns.db.chars) do
    if not c.fullName and not c.mailName and c.name then
      local hit = extra and uniqueMatch(extra, c) or ns.FindFullName(c)
      if hit then c.fullName = hit end
    end
  end
end

function ns.GetChar(key, create)
  local db = ns.db
  local c = db.chars[key]
  if not c and create then
    c = { key = key, inv = {}, profs = {}, recipes = {}, ticks = {}, extras = { items = {}, tasks = {} },
          needQty = {}, needOff = {}, wish = {}, ignore = {}, mailPending = {} }
    db.chars[key] = c
  end
  if c then
    -- backfill fields for records from older versions
    c.inv = c.inv or {}; c.profs = c.profs or {}; c.recipes = c.recipes or {}; c.ticks = c.ticks or {}
    c.extras = c.extras or { items = {}, tasks = {} }; c.extras.items = c.extras.items or {}; c.extras.tasks = c.extras.tasks or {}
    c.needQty = c.needQty or {}; c.needOff = c.needOff or {}; c.wish = c.wish or {}; c.ignore = c.ignore or {}
    c.mailPending = c.mailPending or {}
  end
  return c
end

function ns.Me()
  return ns.GetChar(ns.myKey or ns.CurrentKey(), true)
end

-- All alts on the same realm and faction as `c` (excluding c itself).
function ns.Siblings(c)
  local out = {}
  for k, o in pairs(ns.db.chars) do
    if k ~= c.key and o.realm == c.realm and (o.faction == c.faction or not o.faction or not c.faction) then
      out[#out + 1] = o
    end
  end
  table.sort(out, function(a, b) return (a.name or "") < (b.name or "") end)
  return out
end

---------------------------------------------------------------------------
-- Change notification (UI refresh)
---------------------------------------------------------------------------
ns.listeners = {}
function ns.OnChange(fn) ns.listeners[#ns.listeners + 1] = fn end
function ns.Changed(what)
  for _, fn in ipairs(ns.listeners) do
    local ok, err = pcall(fn, what)
    if not ok then ns.Print("UI error:", err) end
  end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local frame = CreateFrame("Frame")
ns.eventFrame = frame
ns.handlers = {}

function ns.On(event, fn)
  ns.handlers[event] = ns.handlers[event] or {}
  table.insert(ns.handlers[event], fn)
  pcall(frame.RegisterEvent, frame, event) -- unknown events in this client are ignored
end

frame:SetScript("OnEvent", function(_, event, ...)
  local list = ns.handlers[event]
  if not list then return end
  for _, fn in ipairs(list) do
    local ok, err = pcall(fn, event, ...)
    if not ok and ns.db and ns.db.settings.debug then ns.Print(event, "error:", err) end
  end
end)

ns.On("ADDON_LOADED", function(_, name)
  if name ~= ADDON then return end
  ns.InitDB()
  -- say so when a new version arrived (e.g. via the auto-updater + /reload)
  if ns.db.lastVersion and ns.db.lastVersion ~= ns.VERSION then
    ns.Print("updated from " .. ns.db.lastVersion .. " to " .. ns.VERSION .. ". See the README on GitHub for what changed.")
  end
  ns.db.lastVersion = ns.VERSION
  ns.RebuildReference()
  if ns.InitMinimap then ns.InitMinimap() end
end)

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
local function SplitQty(rest)
  -- "<item or link> <qty>" -> text, qty
  local text, qty = rest:match("^(.-)%s+(%d+)%s*$")
  if not text then text = rest end
  return ns.Trim(text), tonumber(qty)
end

local HELP = {
  "/fettle - open or close the window",
  "/fettle bug [text] - report a bug to the Fettle developer",
  "/fettle add <category or item> [qty] - add a line to this alt's kit",
  "/fettle want <item> [qty] - add an item to this alt's wish list",
  "/fettle unwant <item> - remove it from the wish list",
  "/fettle role auto|tank|healer|melee|ranged|caster|bank - set this alt's role",
  "/fettle starter - replace this alt's kit with every suggestion for its class and role",
  "/fettle copy <alt name> - copy another alt's kit onto this alt",
  "/fettle bank <item or category> - always send this to the bank alt (/fettle unbank to undo)",
  "/fettle main <profession> - make this alt the main for a profession (again to undo)",
  "/fettle mains - list profession mains",
  "/fettle fullname <First Last> - set this alt's full name for mail (if Fettle can't detect it)",
  "/fettle alts - list every stored character and its saved name",
  "/fettle dock - put the mailbox/bank/vendor panel back beside the window it belongs to",
  "/fettle run - start a new run (clears ticked tasks)",
  "/fettle scan - rescan this character now",
  "/fettle debug - print what the addon detects",
  "/fettle resetref - discard ALL your reference list edits",
  "/fettle forget <Name-Realm> - delete a stored character",
}

function ns.Slash(msg)
  msg = ns.Trim(msg or "")
  local cmd, rest = msg:match("^(%S+)%s*(.-)$")
  cmd = cmd and cmd:lower() or ""
  rest = rest or ""
  local me = ns.Me()
  if cmd == "" then
    if ns.ToggleUI then ns.ToggleUI() end
  elseif cmd == "bug" then
    if ns.UI and ns.UI.BugWindow then ns.UI.BugWindow("report", rest) end
  elseif cmd == "bugs" then
    if ns.UI and ns.UI.BugWindow then ns.UI.BugWindow("inbox") end
  elseif cmd == "help" then
    for _, l in ipairs(HELP) do ns.Print(l) end
  elseif cmd == "want" then
    local text, qty = SplitQty(rest)
    local id, name = ns.ParseItem(text)
    if not name then ns.Print("Usage: /fettle want <item link or name> [qty]") return end
    ns.AddWish(me, id, name, qty or 20)
    ns.Print("Wish list:", name, "x" .. (qty or 20))
  elseif cmd == "unwant" then
    local _, name = ns.ParseItem(rest)
    if name then ns.RemoveWish(me, name); ns.Print("Removed", name) end
  elseif cmd == "add" or cmd == "extra" then
    local text, qty = SplitQty(rest)
    local what = ns.AddToKit(me, text, qty)
    if what then ns.Print("Kit:", what, "x" .. (qty or 1)) else ns.Print("Usage: /fettle add <category or item> [qty]") end
  elseif cmd == "starter" then
    ns.SeedKit(me); ns.Print("Kit reset to the", ns.ROLE_NAMES[ns.RoleOf(me)], "starter.")
  elseif cmd == "copy" then
    local from = ns.FindChar(rest)
    if not from then ns.Print("No stored alt named", rest) return end
    ns.CopyKit(from, me); ns.Print("Copied kit from", from.name)
  elseif cmd == "main" then
    local prof = ns.FindProfession(rest)
    if not prof then ns.Print("Usage: /fettle main <profession>, e.g. /fettle main cooking") return end
    local on = not ns.IsMain(me, prof)
    ns.SetMain(me, prof, on)
    ns.Print(on and (me.name .. " is now the " .. ns.MainNoun(prof) .. ".") or (me.name .. " is no longer the " .. ns.MainNoun(prof) .. "."))
  elseif cmd == "fullname" then
    local n = ns.Trim(rest)
    if n == "" or not n:find(" ", 1, true) then ns.Print("Usage: /fettle fullname <first name> <last name>") return end
    me.mailName = n
    ns.Print("Mail will be addressed to", n)
    ns.Changed("char")
  elseif cmd == "dock" then
    ns.db.hintsPos = nil
    if ns.Hints then ns.Hints.anchoredFor = nil end
    ns.Print("The hint panel will dock beside the mailbox, bank or vendor again.")
  elseif cmd == "alts" then
    local keys = {}
    for k in pairs(ns.db.chars) do keys[#keys + 1] = k end
    table.sort(keys)
    for _, k in ipairs(keys) do
      local o = ns.db.chars[k]
      ns.Print(k, "| full name:", tostring(o.fullName), "| mail:", tostring(o.mailName), "| level", tostring(o.level), tostring(o.class), "| seen", ns.Ago(o.lastSeen))
    end
  elseif cmd == "mains" then
    local any = false
    for prof, m in pairs(ns.Mains(me)) do ns.Print(prof .. ":", m.name); any = true end
    if not any then ns.Print("No profession mains yet. On the alt, type /fettle main <profession>.") end
  elseif cmd == "bank" or cmd == "unbank" then
    local res = ns.TagForBank(rest, cmd == "bank")
    if res then ns.Print(cmd == "bank" and "Bank pool: always send" or "Bank pool: no longer sending", res)
    else ns.Print("Usage: /fettle bank <item or category>") end
  elseif cmd == "role" then
    local r = rest:upper()
    if r == "AUTO" or r == "" then me.roleOverride = nil
    elseif ns.ROLE_NAMES[r] then me.roleOverride = r
    else ns.Print("Unknown role", rest) return end
    ns.Print("Role:", ns.ROLE_NAMES[ns.RoleOf(me)], me.roleOverride and "(manual)" or "(auto)")
    ns.Changed("char")
  elseif cmd == "run" then
    ns.NewRun(me); ns.Print("New run: ticks cleared.")
  elseif cmd == "scan" then
    ns.ScanAll(); ns.Print("Rescanned.")
  elseif cmd == "debug" then
    ns.Debug()
  elseif cmd == "resetref" then
    ns.db.custom = { categories = {}, needs = {}, tasks = {} }
    for _, c in pairs(ns.db.chars) do ns.GetChar(c.key) end
    ns.RebuildReference(); ns.Print("Reference list reset to defaults.")
  elseif cmd == "forget" then
    if ns.db.chars[rest] then ns.db.chars[rest] = nil; ns.Print("Forgot", rest); ns.Changed("chars")
    else ns.Print("No stored character", rest) end
  elseif cmd == "settings" then
    for k, v in pairs(ns.db.settings) do ns.Print(k, "=", tostring(v)) end
  else
    for _, l in ipairs(HELP) do ns.Print(l) end
  end
end

SLASH_FETTLE1 = "/fettle"
SLASH_FETTLE2 = "/fet"
-- (Never assign the SlashCmdList global itself: that taints Blizzard's
-- chat command handling and breaks protected commands such as /ginvite.)
SlashCmdList["FETTLE"] = function(msg) ns.Slash(msg) end

---------------------------------------------------------------------------
-- Version check with guildies: each copy of Fettle tells the guild which
-- version it runs. If someone's is newer, you get one chat line about it.
---------------------------------------------------------------------------
local PREFIX = "Fettle"

function ns.VersionNewer(a, b) -- is a newer than b?
  local function parts(v) local t = {}; for n in tostring(v):gmatch("%d+") do t[#t + 1] = tonumber(n) end; return t end
  local pa, pb = parts(a), parts(b)
  for i = 1, math.max(#pa, #pb) do
    local x, y = pa[i] or 0, pb[i] or 0
    if x ~= y then return x > y end
  end
  return false
end

local told, answered = false, {}
local function send(msg)
  if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return end
  if not (IsInGuild and IsInGuild()) then return end
  pcall(C_ChatInfo.SendAddonMessage, PREFIX, msg, "GUILD")
end

ns.On("PLAYER_LOGIN", function()
  if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX) end
  local function hello()
    send("HELLO:" .. ns.VERSION)
    if ns.IsDev() then send("DEV:" .. ns.VERSION) end
  end
  if C_Timer and C_Timer.After then C_Timer.After(15, hello) else hello() end
end)

---------------------------------------------------------------------------
-- Bug reports: typed in game, sent over the guild addon channel to whoever
-- has "Receive bug reports" on (the developer). Queued until they're online,
-- resent until they confirm (ACK).
--   DEV:<v>                 a developer is online (sent at login and to each HELLO)
--   BUG:<id>:<i>/<n>:<text> one piece of a report
--   ACK:<id>                developer has it
---------------------------------------------------------------------------
local CHUNK = 200
local function isMe(sender)
  local me = UnitName and UnitName("player")
  return sender and me and (sender == me or sender:match("^([^%-]+)") == me)
end

function ns.IsDev() return ns.db.settings.receiveBugs and true or false end

function ns.BugHeader()
  local c = ns.Me()
  local zone = (GetRealZoneText and GetRealZoneText()) or "?"
  local build = GetBuildInfo and select(1, GetBuildInfo()) or "?"
  return string.format("Fettle %s · %s (%s %s) · %s · client %s · %s", ns.VERSION, ns.DisplayName(c),
    tostring(c.className or c.class or "?"), tostring(c.level or "?"), zone, tostring(build), date and date("%Y-%m-%d %H:%M") or "")
end

local function storeReport(id, from, text)
  ns.db.bugInbox = ns.db.bugInbox or {}
  for _, r in ipairs(ns.db.bugInbox) do if r.id == id then return false end end
  table.insert(ns.db.bugInbox, { id = id, from = from, text = text, at = time and time() or 0 })
  ns.Changed("bugs")
  return true
end

function ns.FlushBugs()
  local out = ns.db.bugOutbox
  if not out or #out == 0 then return end
  local delay = 0
  for _, r in ipairs(out) do
    local n = math.ceil(#r.text / CHUNK)
    for i = 1, n do
      local piece = "BUG:" .. r.id .. ":" .. i .. "/" .. n .. ":" .. r.text:sub((i - 1) * CHUNK + 1, i * CHUNK)
      if C_Timer and C_Timer.After and delay > 0 then C_Timer.After(delay, function() send(piece) end) else send(piece) end
      delay = delay + 0.4
    end
  end
end

-- Returns "saved" (you're the developer), "sent" or "queued".
function ns.SubmitBug(text)
  text = ns.Trim(text or "")
  if text == "" then return nil end
  local full = ns.BugHeader() .. "\n" .. text:sub(1, 1500)
  local id = tostring(time and time() or 0) .. tostring(math.random(1000, 9999))
  if ns.IsDev() then
    storeReport(id, ns.DisplayName(ns.Me()), full)
    return "saved"
  end
  ns.db.bugOutbox = ns.db.bugOutbox or {}
  table.insert(ns.db.bugOutbox, { id = id, text = full })
  send("HELLO:" .. ns.VERSION) -- an online developer answers DEV, which sends it
  return (IsInGuild and IsInGuild()) and "sent" or "queued"
end

local partial = {}
local devAnswered = {}
ns.On("CHAT_MSG_ADDON", function(_, prefix, msg, channel, sender)
  if prefix ~= PREFIX or type(msg) ~= "string" or isMe(sender) then return end
  local kind = msg:match("^(%u+):")
  if kind == "DEV" then
    if ns.db.bugOutbox and #ns.db.bugOutbox > 0 then ns.FlushBugs() end
    return
  elseif kind == "BUG" then
    if not ns.IsDev() then return end
    local id, i, n, text = msg:match("^BUG:(%d+):(%d+)/(%d+):(.*)$")
    if not id then return end
    i, n = tonumber(i), tonumber(n)
    local p = partial[id] or { parts = {}, got = 0 }
    partial[id] = p
    if not p.parts[i] then p.parts[i] = text; p.got = p.got + 1 end
    if p.got >= n then
      partial[id] = nil
      if storeReport(id, sender, table.concat(p.parts)) then
        ns.Print("new bug report from " .. tostring(sender) .. ". Options tab → Bug reports, or /fettle bugs.")
      end
      send("ACK:" .. id)
    end
    return
  elseif kind == "ACK" then
    local id = msg:match("^ACK:(%d+)$")
    local out = ns.db.bugOutbox or {}
    for k = #out, 1, -1 do
      if out[k].id == id then
        table.remove(out, k)
        ns.Print("your bug report reached " .. tostring(sender) .. ". Thanks!")
        ns.Changed("bugs")
      end
    end
    return
  elseif kind == "HELLO" and ns.IsDev() and not devAnswered[sender] then
    devAnswered[sender] = true
    send("DEV:" .. ns.VERSION)
  end
  local ver = msg:match("^%u+:(.+)$")
  if not ver then return end
  if ns.VersionNewer(ver, ns.VERSION) then
    if not told then
      told = true
      ns.Print("a guildie has a newer version (" .. ver .. "). The auto-updater installs it within a few minutes; then type /reload.")
    end
  elseif kind == "HELLO" and ns.VersionNewer(ns.VERSION, ver) and not answered[ver] then
    answered[ver] = true -- tell older copies once per version per session
    send("VER:" .. ns.VERSION)
  end
end)
