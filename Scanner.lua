-- Fettle: reads the current character (bags, bank, mail, professions,
-- spec, recipes). Every API call is guarded because Forever's client may differ.
local _, ns = ...

-- pcall wrapper that keeps every return value (including nils in the middle,
-- e.g. GetProfessions() returns nil for an empty primary profession slot).
local function strip(ok, ...)
  if ok then return ... end
  return nil
end
local function safe(fn, ...)
  if not fn then return nil end
  return strip(pcall(fn, ...))
end

local function linkId(link) return link and tonumber(link:match("item:(%d+)")) end
local function linkName(link) return link and link:match("%[(.-)%]") end

---------------------------------------------------------------------------
-- Containers
---------------------------------------------------------------------------
local function NumSlots(bag)
  if C_Container and C_Container.GetContainerNumSlots then return safe(C_Container.GetContainerNumSlots, bag) or 0 end
  if GetContainerNumSlots then return safe(GetContainerNumSlots, bag) or 0 end
  return 0
end

local function SlotInfo(bag, slot)
  if C_Container and C_Container.GetContainerItemInfo then
    local info = safe(C_Container.GetContainerItemInfo, bag, slot)
    if info then return info.itemID or linkId(info.hyperlink), info.hyperlink, info.stackCount or 1, info.isBound end
    return nil
  end
  if GetContainerItemInfo then
    local _, count, _, _, _, _, link, _, _, id = safe(GetContainerItemInfo, bag, slot)
    if link then return id or linkId(link), link, count or 1 end
  end
  return nil
end
ns.SlotInfo = SlotInfo

function ns.BagIDs()
  local last = (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4)
  local t = {}
  for b = 0, last do t[#t + 1] = b end
  return t
end

function ns.BankBagIDs()
  local t, seen = {}, {}
  local function add(b) if b and not seen[b] then seen[b] = true; t[#t + 1] = b end end
  local E = Enum and Enum.BagIndex
  add(E and E.Bank or -1)
  if E then
    add(E.Reagentbank)
    for i = 1, 8 do add(E["CharacterBankTab_" .. i]); add(E["BankBag_" .. i]) end
  end
  local first = (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4) + 1
  for b = first, first + (NUM_BANKBAGSLOTS or 7) - 1 do add(b) end
  return t
end

-- Iterate over occupied slots: fn(bag, slot, id, name, count, isBound)
function ns.ForEachSlot(bags, fn)
  for _, bag in ipairs(bags) do
    local n = NumSlots(bag)
    for slot = 1, n do
      local id, link, count, bound = SlotInfo(bag, slot)
      if id or link then
        local name = linkName(link) or ns.ItemNameByID(id)
        if name then fn(bag, slot, id, name, count, bound) end
      end
    end
  end
end

---------------------------------------------------------------------------
-- Item facts used by the bank pool: class (7 trade goods, 9 recipe, 2/4 gear,
-- 0 consumable), required level, and for recipes "Requires <Prof> (<skill>)".
---------------------------------------------------------------------------
ns.CLASS_CONSUMABLE, ns.CLASS_WEAPON, ns.CLASS_ARMOR, ns.CLASS_TRADEGOODS, ns.CLASS_RECIPE = 0, 2, 4, 7, 9

ns.CLASS_CONTAINER = 1
local metaCache = {}

-- Slot count of a bag item: learned from equipped bags, else its tooltip ("8 Slot Bag").
local function BagSlotsFromTooltip(bag, slot)
  if not (C_TooltipInfo and C_TooltipInfo.GetBagItem) then return nil end
  local data = safe(C_TooltipInfo.GetBagItem, bag, slot)
  for _, line in ipairs((data and data.lines) or {}) do
    local n = type(line.leftText) == "string" and tonumber(line.leftText:match("^(%d+) Slot"))
    if n then return n end
  end
end
local function RecipeRequirement(bag, slot)
  if not (C_TooltipInfo and C_TooltipInfo.GetBagItem) then return nil end
  local data = safe(C_TooltipInfo.GetBagItem, bag, slot)
  for _, line in ipairs((data and data.lines) or {}) do
    local t = line.leftText
    if type(t) == "string" then
      local prof, skill = t:match("^Requires ([%a ]+) %((%d+)%)")
      if prof then return { prof, tonumber(skill) } end
    end
  end
  return nil
end

function ns.ClearItemMeta() metaCache = {} end

function ns.ItemMeta(id, bag, slot)
  if not id then return nil end
  local m = metaCache[id]
  if m and m.minLvl == nil and m.cls ~= nil then m = nil end -- item info wasn't cached yet: retry
  if not m then
    m = {}
    if C_Item and C_Item.GetItemInfoInstant then
      local _, _, sub, equipLoc, _, cls, subcls = safe(C_Item.GetItemInfoInstant, id)
      m.cls, m.sub, m.equip, m.subcls = cls, sub, equipLoc, subcls
    end
    local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if getInfo then
      local _, _, _, _, minLvl = safe(getInfo, id)
      m.minLvl = minLvl
    end
    metaCache[id] = m
  end
  if m.cls == ns.CLASS_CONTAINER and bag then
    ns.db.bagSlots = ns.db.bagSlots or {}
    if not ns.db.bagSlots[id] then ns.db.bagSlots[id] = BagSlotsFromTooltip(bag, slot) end
    m.slots = ns.db.bagSlots[id]
  end
  if m.cls == ns.CLASS_RECIPE and not m.req and bag then
    m.req = RecipeRequirement(bag, slot)
    if not m.req and m.sub then m.req = { m.sub, 1 } end
  end
  return m
end

local function setField(c, field, counts)
  for _, rec in pairs(c.inv) do
    rec[field] = nil
    if field == "b" then rec.bound = nil end
  end
  for id, x in pairs(counts) do
    local rec = c.inv[id]
    if not rec then rec = { n = x.n }; c.inv[id] = rec end
    rec.n = x.n
    rec[field] = x.c
    if x.meta then rec.cls, rec.subcls, rec.minLvl, rec.req, rec.slots = x.meta.cls, x.meta.subcls, x.meta.minLvl, x.meta.req, x.meta.slots end
    if field == "b" and x.bound then rec.bound = true end
  end
  for id, rec in pairs(c.inv) do
    if not rec.b and not rec.k and not rec.m then c.inv[id] = nil end
  end
end

local function collect(bags)
  local counts = {}
  ns.ForEachSlot(bags, function(bag, slot, id, name, count, bound)
    local key = id or name
    if not counts[key] then
      local meta = ns.ItemMeta(id, bag, slot)
      counts[key] = { n = name, c = 0, meta = meta }
      if meta and ns.LearnItem then ns.LearnItem(name, meta.minLvl) end
    end
    counts[key].c = counts[key].c + count
    if bound then counts[key].bound = true end
  end)
  return counts
end

function ns.ScanBags()
  if not ns.ready then return end
  local c = ns.Me()
  setField(c, "b", collect(ns.BagIDs()))
  -- free slots in ordinary bags
  local free = 0
  for _, bag in ipairs(ns.BagIDs()) do
    local f, bagType
    if C_Container and C_Container.GetContainerNumFreeSlots then f, bagType = safe(C_Container.GetContainerNumFreeSlots, bag)
    elseif GetContainerNumFreeSlots then f, bagType = safe(GetContainerNumFreeSlots, bag) end
    if f and (bagType == nil or bagType == 0) then free = free + f end
  end
  c.freeSlots = free
  -- sizes of the four ordinary bag slots (0 = confirmed empty). Special bags
  -- (quiver, ammo, soul, herb...) and the keyring/reagent bag are left out, and
  -- if a slot can't be read yet the old record is kept.
  local sizes, unsure = {}, false
  ns.db.bagSlots = ns.db.bagSlots or {}
  for bag = 1, 4 do
    local n = NumSlots(bag) or 0
    local inv = (C_Container and C_Container.ContainerIDToInventoryID and safe(C_Container.ContainerIDToInventoryID, bag))
             or (ContainerIDToInventoryID and safe(ContainerIDToInventoryID, bag))
    local id = inv and GetInventoryItemID and safe(GetInventoryItemID, "player", inv)
    local _, bagType
    if C_Container and C_Container.GetContainerNumFreeSlots then _, bagType = safe(C_Container.GetContainerNumFreeSlots, bag)
    elseif GetContainerNumFreeSlots then _, bagType = safe(GetContainerNumFreeSlots, bag) end
    if id then
      if n == 0 then unsure = true                           -- bag info not loaded yet
      elseif bagType and bagType ~= 0 then                    -- special bag: not a candidate
      else sizes[#sizes + 1] = n; ns.db.bagSlots[id] = n end
    elseif n > 0 then
      if not (bagType and bagType ~= 0) then sizes[#sizes + 1] = n end
    elseif inv and GetInventoryItemID then
      sizes[#sizes + 1] = 0                                   -- really empty
    else
      unsure = true
    end
  end
  if not unsure then c.bagSizes = sizes end
  c.bagsSeen = ns.Now()
end

function ns.ScanBank()
  if not ns.ready then return end
  local c = ns.Me()
  setField(c, "k", collect(ns.BankBagIDs()))
  c.bankSeen = ns.Now()
end

function ns.ScanMail()
  if not ns.ready then return end
  local c = ns.Me()
  local counts = {}
  local num = safe(GetInboxNumItems) or 0
  for i = 1, num do
    for a = 1, (ATTACHMENTS_MAX_RECEIVE or 16) do
      local name, id, _, count = safe(GetInboxItem, i, a)
      if name then
        local key = id or name
        counts[key] = counts[key] or { n = name, c = 0 }
        counts[key].c = counts[key].c + (count or 1)
      end
    end
  end
  setField(c, "m", counts)
  c.mailPending = {}   -- the inbox is now the truth
  -- mail from your own alts shows their full names
  local senders = {}
  for i = 1, num do
    local _, _, sender = safe(GetInboxHeaderInfo, i)
    if type(sender) == "string" then senders[#senders + 1] = sender end
  end
  if #senders > 0 then ns.LearnFullNames(senders) end
  c.mailSeen = ns.Now()
end

---------------------------------------------------------------------------
-- Outgoing mail to your own alts: credit the recipient immediately.
---------------------------------------------------------------------------
local pendingSend
local function SnapshotAttachments()
  local items = {}
  for i = 1, (ATTACHMENTS_MAX_SEND or 12) do
    local name, id, _, count = safe(GetSendMailItem, i)
    if name then items[#items + 1] = { id = id, n = name, c = count or 1 } end
  end
  return items
end

function ns.HookMail()
  if ns.mailHooked or not hooksecurefunc or not SendMail then return end
  ns.mailHooked = true
  hooksecurefunc("SendMail", function(recipient)
    pendingSend = { to = recipient, items = SnapshotAttachments() }
  end)
end

-- Find one of your alts from what was typed in the To field.
function ns.FindAltByMailName(to, me)
  if not to or to == "" then return nil end
  local l = to:lower():gsub("^%s+", ""):gsub("%s+$", "")
  local first = l:match("^(%S+)")
  local exact, byFirst, nFirst = nil, nil, 0
  for _, o in pairs(ns.db.chars) do
    if o.key ~= me.key and (o.faction == me.faction or not o.faction) then
      local mn = ns.MailName(o)
      if mn and mn:lower() == l then exact = o end
      if o.name and o.name:lower() == first then byFirst = o; nFirst = nFirst + 1 end
    end
  end
  if exact then return exact, false end
  if nFirst == 1 then return byFirst, true end
  return nil
end

ns.On("MAIL_SEND_SUCCESS", function()
  if not pendingSend or not pendingSend.to then return end
  local to = pendingSend.to
  local me = ns.Me()
  local target, guessed = ns.FindAltByMailName(to, me)
  if target then
    -- learn the full name from a mail that went through
    if guessed and to:find(" ", 1, true) and not target.mailName then target.mailName = ns.Trim(to) end
    for _, it in ipairs(pendingSend.items) do
      local key = it.id or it.n
      local rec = target.inv[key] or { n = it.n }
      rec.m = (rec.m or 0) + it.c
      target.inv[key] = rec
    end
    ns.Changed("inv")
  end
  pendingSend = nil
  ns.ScanBags()
end)

---------------------------------------------------------------------------
-- Camp Benefits (the one-hour buff from sitting at a Forever campfire)
---------------------------------------------------------------------------
local CAMP_BUFF = "Camp Benefits"
function ns.ScanCampBuff()
  if not ns.ready then return end
  local c = ns.Me()
  local ok, remaining = pcall(function()
    local aura
    if C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName then
      aura = C_UnitAuras.GetAuraDataBySpellName("player", CAMP_BUFF, "HELPFUL")
    end
    if not aura and C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
      for i = 1, 40 do
        local a = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
        if not a then break end
        if a.name == CAMP_BUFF then aura = a; break end
      end
    end
    if not aura then return 0 end
    if not aura.expirationTime or aura.expirationTime == 0 then return 3600 end
    return aura.expirationTime - GetTime()
  end)
  if not ok then return end -- aura data hidden right now (combat); keep the last reading
  local before = c.campExpires
  c.campExpires = (remaining and remaining > 0) and (ns.Now() + remaining) or nil
  if (before == nil) ~= (c.campExpires == nil) then ns.Changed("char") end
end

function ns.CampMinutesLeft(c)
  if not c.campExpires then return 0 end
  return math.max(0, math.floor((c.campExpires - ns.Now()) / 60))
end

local auraQueued = false
ns.On("UNIT_AURA", function(_, unit)
  if unit ~= "player" or auraQueued then return end
  auraQueued = true
  local function go() auraQueued = false; ns.ScanCampBuff() end
  if C_Timer and C_Timer.After then C_Timer.After(1, go) else go() end
end)

---------------------------------------------------------------------------
-- Dungeon quests in the quest log, grouped by dungeon (the log's header)
---------------------------------------------------------------------------
local function isDungeonQuest(questID)
  local fn = (C_QuestLog and C_QuestLog.GetQuestTagInfo) or GetQuestTagInfo
  if not (fn and questID) then return false end
  local ok, a, b = pcall(fn, questID)
  if not ok then return false end
  local name = type(a) == "table" and (a.tagName or "") or (b or "")
  local id = type(a) == "table" and a.tagID or a
  return name == "Dungeon" or id == 81
end

function ns.ScanDungeonQuests()
  if not ns.ready then return end
  local c = ns.Me()
  local out, header = {}, nil
  local n = (C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetNumQuestLogEntries()) or
            (GetNumQuestLogEntries and GetNumQuestLogEntries()) or 0
  for i = 1, n do
    local title, isHeader, questID
    if C_QuestLog and C_QuestLog.GetInfo then
      local info = safe(C_QuestLog.GetInfo, i)
      if info then title, isHeader, questID = info.title, info.isHeader, info.questID end
    elseif GetQuestLogTitle then
      local t, _, _, hdr, _, _, _, qid = safe(GetQuestLogTitle, i)
      title, isHeader, questID = t, hdr, qid
    end
    if isHeader then header = title
    elseif title and header and isDungeonQuest(questID) then
      out[header] = out[header] or {}
      table.insert(out[header], title)
    end
  end
  c.dungeonQuests = out
end

-- Done / in-log state of every DungeonJournal quest, saved per alt so other
-- alts' status can be shown too.
function ns.ScanDJStatus()
  if not ns.ready or not ns.DJ then return end
  local db = ns.DJ()
  if not db then return end
  local c = ns.Me()
  local st = {}
  local done = (C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted) or IsQuestFlaggedCompleted
  local onQuest = (C_QuestLog and (C_QuestLog.IsOnQuest or C_QuestLog.GetLogIndexForQuestID))
  for _, d in pairs(db) do
    for _, q in ipairs((type(d) == "table" and d.quests) or {}) do
      if type(q) == "table" and q.id then
        local ok, isDone = pcall(done, q.id)
        if ok and isDone then st[q.id] = "done"
        elseif onQuest then
          local ok2, v = pcall(onQuest, q.id)
          if ok2 and v and v ~= 0 then st[q.id] = "log" end
        end
      end
    end
  end
  c.djStatus = st
end

local qQueued = false
ns.On("QUEST_LOG_UPDATE", function()
  if qQueued then return end
  qQueued = true
  local function go() qQueued = false; ns.ScanDungeonQuests(); ns.ScanDJStatus(); ns.Changed("quests") end
  if C_Timer and C_Timer.After then C_Timer.After(1, go) else go() end
end)

---------------------------------------------------------------------------
-- Equipment durability
---------------------------------------------------------------------------
function ns.ScanDurability()
  if not ns.ready then return end
  local c = ns.Me()
  local cur, max = 0, 0
  for slot = 1, 19 do
    local a, b = safe(GetInventoryItemDurability, slot)
    if a and b and b > 0 then cur = cur + a; max = max + b end
  end
  c.durability = max > 0 and math.floor(cur / max * 100 + 0.5) or 100
end

---------------------------------------------------------------------------
-- Professions
---------------------------------------------------------------------------
function ns.ScanProfessions()
  if not ns.ready then return end
  local c = ns.Me()
  local profs, maxes = {}, {}
  if GetProfessions then
    local list = { safe(GetProfessions) }
    for i = 1, 8 do
      local idx = list[i]
      if idx then
        local name, _, rank, maxRank = safe(GetProfessionInfo, idx)
        if name then profs[name] = rank or 1; maxes[name] = maxRank end
      end
    end
  end
  -- Classic-style skill lines (catches First Aid if GetProfessions omits it)
  if GetNumSkillLines and GetSkillLineInfo then
    local known = {
      ["Alchemy"] = 1, ["Blacksmithing"] = 1, ["Enchanting"] = 1, ["Engineering"] = 1, ["Herbalism"] = 1,
      ["Leatherworking"] = 1, ["Mining"] = 1, ["Skinning"] = 1, ["Tailoring"] = 1, ["Cooking"] = 1,
      ["First Aid"] = 1, ["Fishing"] = 1, ["Jewelcrafting"] = 1, ["Inscription"] = 1,
    }
    for i = 1, (safe(GetNumSkillLines) or 0) do
      local name, isHeader, _, rank, _, _, maxRank = safe(GetSkillLineInfo, i)
      if name and not isHeader and known[name] then profs[name] = rank or profs[name] or 1; maxes[name] = maxRank or maxes[name] end
    end
  end
  -- keep anything learned from the trade skill window that the APIs above missed
  for name, rank in pairs(c.profs or {}) do if profs[name] == nil and c.recipes[name] then profs[name] = rank end end
  c.profs = profs
  c.profMax = maxes
end

---------------------------------------------------------------------------
-- Recipes (learned when you open a profession window)
---------------------------------------------------------------------------
local DIFF = { [0] = "optimal", [1] = "medium", [2] = "easy", [3] = "trivial" }

local function ScanRecipesModern()
  if not (C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs) then return nil end
  local profName, rank
  local base = safe(C_TradeSkillUI.GetBaseProfessionInfo) or safe(C_TradeSkillUI.GetChildProfessionInfo)
  if base then profName, rank = base.professionName, base.skillLevel; ns.lastProfMax = base.maxSkillLevel end
  if not profName then return nil end
  local ids = safe(C_TradeSkillUI.GetAllRecipeIDs) or {}
  local out = {}
  for _, rid in ipairs(ids) do
    local info = safe(C_TradeSkillUI.GetRecipeInfo, rid)
    if info and info.learned then
      local schem = safe(C_TradeSkillUI.GetRecipeSchematic, rid, false)
      local outId = schem and schem.outputItemID
      local outName = (outId and ns.ItemNameByID(outId)) or info.name
      local reagents = {}
      for _, slot in ipairs((schem and schem.reagentSlotSchematics) or {}) do
        local r = slot.reagents and slot.reagents[1]
        if r and r.itemID then
          reagents[#reagents + 1] = { id = r.itemID, n = ns.ItemNameByID(r.itemID), c = slot.quantityRequired or 1 }
        end
      end
      out[outName or info.name] = { id = outId, diff = DIFF[info.relativeDifficulty] or info.difficulty, reagents = reagents, recipe = info.name }
    end
  end
  return profName, rank, out
end

local function ScanRecipesClassic()
  if not (GetNumTradeSkills and GetTradeSkillInfo) then return nil end
  local profName, rank, maxRank = safe(GetTradeSkillLine)
  ns.lastProfMax = maxRank
  if not profName or profName == "UNKNOWN" then return nil end
  local out = {}
  for i = 1, (safe(GetNumTradeSkills) or 0) do
    local name, kind = safe(GetTradeSkillInfo, i)
    if name and kind ~= "header" and kind ~= "subheader" then
      local link = safe(GetTradeSkillItemLink, i)
      local reagents = {}
      for r = 1, (safe(GetTradeSkillNumReagents, i) or 0) do
        local rn, _, rc = safe(GetTradeSkillReagentInfo, i, r)
        local rl = safe(GetTradeSkillReagentItemLink, i, r)
        if rn then reagents[#reagents + 1] = { id = linkId(rl), n = rn, c = rc or 1 } end
      end
      out[linkName(link) or name] = { id = linkId(link), diff = kind, reagents = reagents, recipe = name }
    end
  end
  return profName, rank, out
end

-- A guildie's or a linked profession window shows their recipes, not ours.
local function ForeignWindow()
  local t = C_TradeSkillUI
  for _, fn in ipairs({ t and t.IsTradeSkillLinked, t and t.IsTradeSkillGuild, t and t.IsNPCCrafting,
                        _G.IsTradeSkillLinked, _G.IsTradeSkillGuild }) do
    if fn then
      local ok, v = pcall(fn)
      if ok and v then return true end
    end
  end
  return false
end

function ns.ScanRecipes()
  if not ns.ready then return end
  if ForeignWindow() then return end
  local c = ns.Me()
  local prof, rank, list = ScanRecipesModern()
  if not prof then prof, rank, list = ScanRecipesClassic() end
  if not prof or not list then return end
  if next(list) == nil then return end
  c.recipes[prof] = list
  if rank then c.profs[prof] = rank end
  if ns.lastProfMax then c.profMax = c.profMax or {}; c.profMax[prof] = ns.lastProfMax end
  for outName, rec in pairs(list) do
    local m = rec.id and ns.ItemMeta(rec.id)
    if m and ns.LearnItem then ns.LearnItem(outName, m.minLvl) end
  end
  ns.Changed("recipes")
end

---------------------------------------------------------------------------
-- Spec and role
---------------------------------------------------------------------------
local SPEC_ROLE = {
  Protection = "TANK", Guardian = "TANK",
  Holy = "HEALER", Discipline = "HEALER", Restoration = "HEALER",
  Arms = "MELEE", Fury = "MELEE", Retribution = "MELEE", Assassination = "MELEE", Combat = "MELEE",
  Outlaw = "MELEE", Subtlety = "MELEE", Enhancement = "MELEE", Feral = "MELEE",
  ["Beast Mastery"] = "RANGED", Marksmanship = "RANGED", Survival = "RANGED",
  Shadow = "CASTER", Elemental = "CASTER", Balance = "CASTER", Arcane = "CASTER", Fire = "CASTER",
  Frost = "CASTER", Affliction = "CASTER", Demonology = "CASTER", Destruction = "CASTER",
}
local CLASS_DEFAULT = {
  WARRIOR = "MELEE", PALADIN = "MELEE", HUNTER = "RANGED", ROGUE = "MELEE", PRIEST = "HEALER",
  SHAMAN = "CASTER", MAGE = "CASTER", WARLOCK = "CASTER", DRUID = "CASTER",
}
ns.SPEC_ROLE, ns.CLASS_DEFAULT = SPEC_ROLE, CLASS_DEFAULT

local function ReadSpec()
  local idx
  if C_SpecializationInfo and C_SpecializationInfo.GetSpecialization then idx = safe(C_SpecializationInfo.GetSpecialization) end
  if not idx and GetSpecialization then idx = safe(GetSpecialization) end
  if idx and idx > 0 then
    local fn = (C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo) or GetSpecializationInfo
    local _, name, _, _, role = safe(fn, idx)
    if name then return name, role end
  end
  -- Classic talent tabs: pick the tree with the most points
  if GetNumTalentTabs and GetTalentTabInfo then
    local bestName, bestPts = nil, 0
    for i = 1, (safe(GetNumTalentTabs) or 0) do
      local a, b, c3, d, e = safe(GetTalentTabInfo, i)
      local name, pts
      if type(a) == "string" then name, pts = a, c3 else name, pts = b, e end
      if type(pts) == "number" and pts > bestPts then bestName, bestPts = name, pts end
    end
    if bestName then return bestName, nil end
  end
  return nil, nil
end

-- Work out the role from class + spec name + the API's role.
function ns.AutoRole(class, specName, apiRole)
  if apiRole == "TANK" or apiRole == "HEALER" then return apiRole end
  local r = specName and SPEC_ROLE[specName]
  if r == "TANK" and apiRole == "DAMAGER" then r = nil end
  if class == "DRUID" and specName == "Feral" then return apiRole == "TANK" and "TANK" or "MELEE" end
  if r then return r end
  return CLASS_DEFAULT[class] or "MELEE"
end

function ns.RoleOf(c)
  return c.roleOverride or c.autoRole or CLASS_DEFAULT[c.class or ""] or "MELEE"
end

-- Before v0.3.3 alts were saved under their first name only. When the full
-- name becomes known, fold the old record into the new one.
local function isStarterKit(c)
  local a, b = c.kit or {}, ns.Starter(c)
  if #a ~= #b then return false end
  for i = 1, #a do if a[i].cat ~= b[i].cat or a[i].qty ~= b[i].qty or (a[i].optional or false) ~= (b[i].optional or false) then return false end end
  return true
end

function ns.MergeOldRecord(oldKey, newKey)
  local db = ns.db
  local old, new = db.chars[oldKey], db.chars[newKey]
  if not old or oldKey == newKey then return end
  if not new then
    old.key = newKey
    db.chars[newKey] = old
  else
    -- keep the newer scan (inventory, level), take the player's settings from
    -- whichever record has them
    if (not new.kit or isStarterKit(new)) and old.kit then new.kit = old.kit end
    for _, f in ipairs({ "roleOverride", "mailName", "suggest" }) do if new[f] == nil then new[f] = old[f] end end
    for k, v in pairs(old.extras and old.extras.items or {}) do new.extras.items[k] = new.extras.items[k] or v end
    for _, t in ipairs(old.extras and old.extras.tasks or {}) do table.insert(new.extras.tasks, t) end
    for k, v in pairs(old.wish or {}) do new.wish[k] = new.wish[k] or v end
    for k, v in pairs(old.ignore or {}) do new.ignore[k] = new.ignore[k] or v end
    for prof, list in pairs(old.recipes or {}) do new.recipes[prof] = new.recipes[prof] or list end
    if (old.bankSeen or 0) > (new.bankSeen or 0) then
      for id, rec in pairs(old.inv or {}) do
        if rec.k then new.inv[id] = new.inv[id] or { n = rec.n }; new.inv[id].k = rec.k end
      end
      new.bankSeen = old.bankSeen
    end
  end
  db.chars[oldKey] = nil
  for _, scope in pairs(db.mains or {}) do
    for prof, k in pairs(scope) do if k == oldKey then scope[prof] = newKey end end
  end
end

function ns.ScanIdentity()
  local key, name, realm, full = ns.CurrentKey()
  local _, class = safe(UnitClass, "player")
  local faction = safe(UnitFactionGroup, "player")
  -- fold in any other record of this same character: saved under its first
  -- name only, under another realm label, or before the full name was known
  for oldKey, o in pairs(ns.db.chars) do
    if oldKey ~= key and o.name == name and (o.class == nil or o.class == class)
       and (o.faction == nil or o.faction == faction)
       and (o.fullName == nil or o.fullName == full) then
      ns.MergeOldRecord(oldKey, key)
    end
  end
  ns.myKey = key
  local c = ns.GetChar(key, true)
  c.name, c.realm = name, realm
  if full then c.fullName = full end
  local className, class = safe(UnitClass, "player")
  c.className, c.class = className, class
  c.level = safe(UnitLevel, "player") or c.level
  c.faction = safe(UnitFactionGroup, "player") or c.faction
  local spec, apiRole = ReadSpec()
  c.spec, c.apiRole = spec, apiRole
  c.autoRole = ns.AutoRole(class, spec, apiRole)
  c.lastSeen = ns.Now()
end

---------------------------------------------------------------------------
-- Glue
---------------------------------------------------------------------------
function ns.ScanAll()
  ns.ScanIdentity()
  ns.ScanCampBuff()
  ns.ScanDJStatus()
  ns.ScanBags()
  ns.ScanDurability()
  ns.ScanProfessions()
  ns.Changed("char")
end

local bankOpen, mailOpen = false, false
ns.IsBankOpen = function() return bankOpen end
ns.IsMailOpen = function() return mailOpen end

local pendingBagScan = false
local function QueueBagScan()
  if pendingBagScan then return end
  pendingBagScan = true
  local function run()
    pendingBagScan = false
    ns.ScanBags()
    if bankOpen then ns.ScanBank() end
    ns.Changed("inv")
  end
  if C_Timer and C_Timer.After then C_Timer.After(0.3, run) else run() end
end

ns.On("PLAYER_LOGIN", function()
  ns.ready = true
  ns.ScanAll()
  ns.HookMail()
end)
ns.On("PLAYER_LEVEL_UP", function(_, lvl) local c = ns.Me(); c.level = lvl or c.level; ns.Changed("char") end)
ns.On("BAG_UPDATE_DELAYED", QueueBagScan)
ns.On("BAG_UPDATE", QueueBagScan)
ns.On("PLAYERBANKSLOTS_CHANGED", QueueBagScan)
ns.On("PLAYERREAGENTBANKSLOTS_CHANGED", QueueBagScan)
ns.On("UPDATE_INVENTORY_DURABILITY", function() ns.ScanDurability(); ns.Changed("char") end)
ns.On("SKILL_LINES_CHANGED", function() ns.ScanProfessions(); ns.Changed("char") end)
ns.On("PLAYER_SPECIALIZATION_CHANGED", function() ns.ScanIdentity(); ns.Changed("char") end)
ns.On("ACTIVE_TALENT_GROUP_CHANGED", function() ns.ScanIdentity(); ns.Changed("char") end)
ns.On("CHARACTER_POINTS_CHANGED", function() ns.ScanIdentity(); ns.Changed("char") end)
ns.On("TRADE_SKILL_SHOW", function() if C_Timer then C_Timer.After(0.5, ns.ScanRecipes) else ns.ScanRecipes() end end)
ns.On("TRADE_SKILL_LIST_UPDATE", function() ns.ScanRecipes() end)
ns.On("TRADE_SKILL_UPDATE", function() ns.ScanRecipes() end)
ns.On("BANKFRAME_OPENED", function() bankOpen = true; ns.ScanBank(); ns.Changed("bank_open") end)
ns.On("BANKFRAME_CLOSED", function() bankOpen = false; ns.Changed("bank_close") end)
ns.On("MAIL_SHOW", function() mailOpen = true; ns.HookMail(); ns.Changed("mail_open") end)
ns.On("MAIL_INBOX_UPDATE", function() if mailOpen then ns.ScanMail(); ns.Changed("inv") end end)
ns.On("MAIL_CLOSED", function() mailOpen = false; ns.Changed("mail_close") end)
ns.On("QUEST_TURNED_IN", function() if C_Timer and C_Timer.After then C_Timer.After(1, function() ns.ScanDJStatus(); ns.Changed("quests") end) end end)
ns.On("GUILD_ROSTER_UPDATE", function() if ns.ready then ns.LearnFullNames() end end)
ns.On("MAIL_SHOW", function() if ns.ready then ns.LearnFullNames() end end)

-- The full name can arrive a moment after login: re-check once the world is up.
ns.On("PLAYER_ENTERING_WORLD", function()
  if not ns.ready then return end
  local key = ns.CurrentKey()
  if key ~= ns.myKey then ns.ScanIdentity(); ns.Changed("chars") end
end)
ns.On("PLAYER_LOGOUT", function() pcall(ns.ScanBags); pcall(ns.ScanDurability) end)

function ns.Debug()
  local c = ns.Me()
  ns.Print("Character:", c.key, "level", c.level, c.className or "?", "(" .. tostring(c.class) .. ")", c.faction or "?")
  ns.Print("Mail name:", ns.MailName(c), c.mailName and "(set by hand or learned)" or (c.fullName and "(detected)" or "(first name only: use /fettle fullname)"))
  ns.Print("Name APIs:", ns.nameProbe or "?")
  ns.Print("Spec:", tostring(c.spec), "API role:", tostring(c.apiRole), "-> role:", ns.RoleOf(c), c.roleOverride and "(manual)" or "(auto)")
  local p = {}
  for k, v in pairs(c.profs) do p[#p + 1] = k .. " " .. tostring(v) end
  ns.Print("Professions:", #p > 0 and table.concat(p, ", ") or "none detected")
  local nr = {}
  for k, v in pairs(c.recipes) do local n = 0; for _ in pairs(v) do n = n + 1 end; nr[#nr + 1] = k .. " " .. n end
  ns.Print("Recipes known:", #nr > 0 and table.concat(nr, ", ") or "open a profession window to record them")
  local items = 0
  for _ in pairs(c.inv) do items = items + 1 end
  ns.Print("Distinct items stored:", items, "free slots:", tostring(c.freeSlots), "durability:", tostring(c.durability) .. "%")
  ns.Print("Bank seen:", ns.Ago(c.bankSeen), " Mail seen:", ns.Ago(c.mailSeen))
  local n = 0
  for _ in pairs(ns.db.chars) do n = n + 1 end
  local iface = "?"
  if GetBuildInfo then iface = tostring((select(4, GetBuildInfo()))) end
  ns.Print("Characters stored:", n, " Interface:", iface)
  local inInst, kind = false, nil
  if IsInInstance then inInst, kind = IsInInstance() end
  ns.Print("Instance:", tostring(inInst), tostring(kind))
end
