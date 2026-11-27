-- Fettle: per-alt kits, checklist, stock lookup, wish lists, bank pool
-- and hint planning.
local _, ns = ...

local function lower(s) return s and string.lower(s) or "" end
local function contains(list, v)
  for _, x in ipairs(list or {}) do if x == v then return true end end
  return false
end

function ns.IsBank(c) return ns.RoleOf(c) == "BANK" end

function ns.FindChar(text)
  if not text or text == "" then return nil end
  local l = lower(ns.Trim(text))
  if ns.db.chars[text] then return ns.db.chars[text] end
  local me = ns.Me()
  local hit
  for _, c in pairs(ns.db.chars) do
    if lower(c.name) == l then
      if c.realm == me.realm then return c end
      hit = hit or c
    end
  end
  return hit
end

---------------------------------------------------------------------------
-- "Wants": either a category ({cat=key}) or a specific item ({n=name, id=id})
---------------------------------------------------------------------------
function ns.WantMatches(want, itemName, itemId, forChar)
  if want.cat then
    return ns.MatchCategory(want.cat, itemName) and ns.ItemUsable(want.cat, itemName, forChar)
  end
  if want.id and itemId and want.id == itemId then return true end
  return want.n and lower(want.n) == lower(itemName)
end

-- Stock of `want` held by `holder`, judged usable for `forChar`.
-- Returns bag, bank, mail totals and the individual items.
function ns.Stock(holder, want, forChar)
  forChar = forChar or holder
  local b, k, m, items = 0, 0, 0, {}
  for key, rec in pairs(holder.inv or {}) do
    local id = type(key) == "number" and key or nil
    if rec.n and ns.WantMatches(want, rec.n, id, forChar) then
      b = b + (rec.b or 0); k = k + (rec.k or 0); m = m + (rec.m or 0)
      items[#items + 1] = { id = id, key = key, n = rec.n, b = rec.b or 0, k = rec.k or 0, m = rec.m or 0, bound = rec.bound }
    end
  end
  return b, k, m, items
end

-- Alts (same realm and faction) that can craft something matching `want` usable by forChar.
function ns.Crafters(want, forChar)
  local out = {}
  local pool = ns.Siblings(forChar)
  pool[#pool + 1] = forChar
  for _, o in ipairs(pool) do
    for prof, list in pairs(o.recipes or {}) do
      for outName, rec in pairs(list) do
        if ns.WantMatches(want, outName, rec.id, forChar) then
          out[#out + 1] = { char = o, prof = prof, item = outName, rec = rec }
          break
        end
      end
    end
  end
  return out
end

---------------------------------------------------------------------------
-- Kits: each alt's own list of { cat, qty, minLevel, prof, optional }
---------------------------------------------------------------------------
function ns.Starter(c, role)
  role = role or ns.RoleOf(c)
  local lines = {}
  if role == "BANK" then return lines end
  for _, r in ipairs(ns.Defaults.starters) do
    local fits = (not r.roles or contains(r.roles, role))
      and (not r.classes or contains(r.classes, c.class))
      and (not r.mana or ns.MANA_CLASSES[c.class or ""])
    local q = r.qty and (r.qty[role] or r.qty.ALL) or 1
    if fits and q and q > 0 then
      lines[#lines + 1] = { cat = r.cat, qty = q, minLevel = r.minLevel, prof = r.prof, optional = r.optional, from = r.id }
    end
  end
  return lines
end

function ns.SeedKit(c, role)
  c.kit = ns.Starter(c, role)
  c.kitRole = role or ns.RoleOf(c)
  ns.Changed("kit")
end

-- First sight of an alt: build its kit (carrying over v0.1 per-alt overrides).
function ns.EnsureKit(c)
  if c.kit then return c.kit end
  c.kit = ns.Starter(c)
  c.kitRole = ns.RoleOf(c)
  local keep = {}
  for _, line in ipairs(c.kit) do
    if not (c.needOff and c.needOff[line.from]) then
      if c.needQty and c.needQty[line.from] then line.qty = c.needQty[line.from] end
      keep[#keep + 1] = line
    end
  end
  c.kit = keep
  c.needQty, c.needOff = {}, {}
  return c.kit
end

-- nil when active, otherwise the reason it is waiting
function ns.LineLocked(line, c)
  if not ns.ref.categories[line.cat] then return "category removed" end
  if line.minLevel and (c.level or 1) < line.minLevel then return "from level " .. line.minLevel end
  if line.prof and not (c.profs and c.profs[line.prof]) then return "needs " .. line.prof end
  return nil
end

function ns.SetLineQty(c, idx, q) local l = c.kit[idx]; if l and q then l.qty = q end; ns.Changed("kit") end
function ns.RemoveLine(c, idx) table.remove(c.kit, idx); ns.Changed("kit") end
function ns.ToggleLineOptional(c, idx) local l = c.kit[idx]; if l then l.optional = not l.optional or nil end; ns.Changed("kit") end

function ns.AddLine(c, cat, qty)
  ns.EnsureKit(c)
  for _, l in ipairs(c.kit) do
    if l.cat == cat then l.qty = qty or l.qty; l.minLevel = nil; l.prof = nil; ns.Changed("kit"); return end
  end
  table.insert(c.kit, { cat = cat, qty = qty or 1 })
  ns.Changed("kit")
end

function ns.CopyKit(from, to)
  ns.EnsureKit(from)
  to.kit = ns.DeepCopy(from.kit)
  to.extras = to.extras or { items = {}, tasks = {} }
  to.extras.items = ns.DeepCopy(from.extras and from.extras.items or {})
  ns.Changed("kit")
end

function ns.FindCategoryExact(text)
  if not text then return nil end
  text = ns.Trim(text)
  if ns.ref.categories[text] then return text end
  local l = lower(text)
  for k, cat in pairs(ns.ref.categories) do if lower(cat.name) == l then return k end end
  return nil
end

-- "/fettle add" and the Add box: a category name adds a kit line, anything else an item.
function ns.AddToKit(c, text, qty)
  if not text or text == "" then return nil end
  local cat = not text:find("|H") and ns.FindCategoryExact(text)
  if cat then ns.AddLine(c, cat, qty or 1); return ns.ref.categories[cat].name end
  local id, name = ns.ParseItem(text)
  if not name then return nil end
  ns.AddExtraItem(c, id, name, qty or 1)
  return name
end

---------------------------------------------------------------------------
-- Checklist
---------------------------------------------------------------------------
local function statusFor(have, qty, optional)
  if have >= qty then return "ready" end
  if optional then return "optional" end
  if have > 0 then return "low" end
  return "missing"
end

local function sourcesFor(c, want, qty, have, bank, mail)
  local src = { bank = bank, mail = mail, alts = {}, crafters = {} }
  if have >= qty then return src end
  for _, o in ipairs(ns.Siblings(c)) do
    local b, k, m = ns.Stock(o, want, c)
    local n = b + k + m
    if n > 0 then src.alts[#src.alts + 1] = { name = ns.DisplayName(o), n = n, char = o } end
  end
  for _, cr in ipairs(ns.Crafters(want, c)) do
    src.crafters[#src.crafters + 1] = { name = ns.DisplayName(cr.char), prof = cr.prof, item = cr.item, char = cr.char, rec = cr.rec }
  end
  return src
end

function ns.Checklist(c)
  local rows = {}
  if ns.IsBank(c) then return rows end
  ns.EnsureKit(c)
  for idx, line in ipairs(c.kit) do
    local cat = ns.ref.categories[line.cat]
    local locked = ns.LineLocked(line, c)
    if locked then
      rows[#rows + 1] = { kind = "line", idx = idx, line = line, label = cat and cat.name or line.cat,
                          qty = line.qty, have = 0, status = "locked", locked = locked, optional = true }
    else
      local want = { cat = line.cat }
      local have, bank, mail = ns.Stock(c, want, c)
      local best = ns.BestRank(line.cat, c)
      local row = { kind = "line", idx = idx, line = line, want = want, qty = line.qty, have = have,
                    label = cat.name, optional = line.optional, status = statusFor(have, line.qty, line.optional), best = best }
      row.sources = sourcesFor(c, want, line.qty, have, bank, mail)
      row.sources.vendor = best and best.src == "Vendor"
      rows[#rows + 1] = row
    end
  end
  for key, x in pairs(c.extras.items) do
    local want = { n = x.n, id = x.id }
    local have, bank, mail = ns.Stock(c, want, c)
    local row = { kind = "extra", key = key, want = want, qty = x.q or 1, have = have, label = x.n,
                  status = statusFor(have, x.q or 1, false) }
    row.sources = sourcesFor(c, want, row.qty, have, bank, mail)
    rows[#rows + 1] = row
  end
  local s = ns.db.settings
  local function taskRow(t, extraIdx)
    local done, detail
    if t.auto == "durability" then
      done = (c.durability or 100) >= s.minDurability
      detail = (c.durability and (c.durability .. "%") or "?") .. " (min " .. s.minDurability .. "%)"
    elseif t.auto == "campbuff" then
      local left = ns.CampMinutesLeft(c)
      done = left >= (s.minCampMinutes or 45)
      detail = left > 0 and (left .. " min left (want " .. (s.minCampMinutes or 45) .. "+)") or "not active: sit at a campfire for 1 minute"
    elseif t.auto == "freeslots" then
      done = (c.freeSlots or 0) >= s.minFreeSlots
      detail = tostring(c.freeSlots or "?") .. " free (min " .. s.minFreeSlots .. ")"
    else
      done = c.ticks[t.id] and true or false
      if t.id == "quests" and ns.DJ() then
        local dungeon = ns.TargetDungeon(c)
        if dungeon then
          local have, missing, total = ns.DungeonQuestSummary(c, dungeon)
          done = missing == 0 or done
          detail = dungeon .. ": " .. have .. " of " .. total .. " in your log" .. (missing > 0 and (" · " .. missing .. " to pick up") or "")
        else
          detail = "choose a dungeon (... menu)"
        end
      elseif t.id == "quests" then
        local parts = {}
        for zone, list in pairs(c.dungeonQuests or {}) do parts[#parts + 1] = zone .. " " .. #list end
        table.sort(parts)
        detail = #parts > 0 and ("in your log: " .. table.concat(parts, " · ")) or "no dungeon quests in your log"
      end
    end
    local st = done and "done" or (t.optional and "optional" or "todo")
    rows[#rows + 1] = { kind = "task", task = t, id = t.id, label = t.text, detail = detail, auto = t.auto,
                        status = st, optional = t.optional, extraIdx = extraIdx }
  end
  for _, t in ipairs(ns.ref.tasks) do if not t.off then taskRow(t) end end
  for i, text in ipairs(c.extras.tasks) do taskRow({ id = "x" .. i, text = text }, i) end

  local order = { missing = 1, todo = 1, low = 2, optional = 3, ready = 4, done = 4, locked = 5 }
  for i, r in ipairs(rows) do r._i = i end
  table.sort(rows, function(a, b)
    local oa, ob = order[a.status] or 5, order[b.status] or 5
    if oa ~= ob then return oa < ob end
    return a._i < b._i
  end)
  return rows
end

function ns.Summary(c)
  local missing, low, ready, total = 0, 0, 0, 0
  for _, r in ipairs(ns.Checklist(c)) do
    if r.status == "missing" or r.status == "todo" then missing = missing + 1
    elseif r.status == "low" then low = low + 1
    elseif r.status == "ready" or r.status == "done" then ready = ready + 1 end
    if not r.optional then total = total + 1 end
  end
  return missing, low, ready, total
end

function ns.NewRun(c)
  c.ticks = {}
  ns.Changed("ticks")
end

function ns.ToggleTick(c, id)
  c.ticks[id] = not c.ticks[id] or nil
  ns.Changed("ticks")
end

---------------------------------------------------------------------------
-- Per-alt extras (specific items and tasks)
---------------------------------------------------------------------------
function ns.AddExtraItem(c, id, name, q)
  c.extras.items[lower(name)] = { id = id, n = name, q = q or 1 }
  ns.Changed("char")
end
function ns.RemoveExtraItem(c, key) c.extras.items[key] = nil; ns.Changed("char") end
function ns.SetExtraQty(c, key, q) if c.extras.items[key] then c.extras.items[key].q = q end; ns.Changed("char") end
function ns.AddExtraTask(c, text) table.insert(c.extras.tasks, text); ns.Changed("char") end
function ns.RemoveExtraTask(c, i) table.remove(c.extras.tasks, i); ns.Changed("char") end

---------------------------------------------------------------------------
-- Wish list
---------------------------------------------------------------------------
function ns.AddWish(c, id, name, q)
  c.wish[lower(name)] = { id = id, n = name, q = q or 20 }
  c.ignore[lower(name)] = nil
  ns.Changed("wish")
end
function ns.RemoveWish(c, name) c.wish[lower(name)] = nil; ns.Changed("wish") end
function ns.SetWishQty(c, name, q) local w = c.wish[lower(name)]; if w then w.q = q end; ns.Changed("wish") end
function ns.IgnoreSuggestion(c, name) c.ignore[lower(name)] = true; ns.Changed("wish") end

local function addReagents(acc, rec, times, reason)
  for _, r in ipairs(rec.reagents or {}) do
    local name = r.n or ns.ItemNameByID(r.id)
    if name then
      local k = lower(name)
      acc[k] = acc[k] or { n = name, id = r.id, q = 0, reasons = {} }
      acc[k].q = acc[k].q + (r.c or 1) * times
      acc[k].reasons[reason] = true
    end
  end
end

local function isGap(row)
  return (row.kind == "line" or row.kind == "extra") and row.status ~= "locked" and row.have < row.qty
end

-- Profession-based suggestions (only when enabled in Options).
function ns.Suggestions(c)
  local s = ns.db.settings
  if not s.autoSuggest or c.suggest == false or ns.IsBank(c) then return {} end
  local acc = {}
  for prof, list in pairs(c.recipes or {}) do
    local main = ns.MainFor(c, prof)
    if main and main.key ~= c.key then list = {} end
    local cands = {}
    for outName, rec in pairs(list) do
      if rec.diff == "optimal" or rec.diff == "medium" then cands[#cands + 1] = { n = outName, rec = rec } end
    end
    table.sort(cands, function(a, b)
      if a.rec.diff ~= b.rec.diff then return a.rec.diff == "optimal" end
      return #a.rec.reagents < #b.rec.reagents
    end)
    for i = 1, math.min(#cands, s.suggestMaxRecipes) do
      addReagents(acc, cands[i].rec, s.suggestCrafts, prof .. " skill-up: " .. cands[i].n)
    end
  end
  local pool = ns.Siblings(c)
  pool[#pool + 1] = c
  for _, o in ipairs(pool) do
    for _, row in ipairs(ns.Checklist(o)) do
      if isGap(row) and not row.optional then
        for _, cr in ipairs(row.sources.crafters or {}) do
          if cr.char == c then
            addReagents(acc, cr.rec, row.qty - row.have, "craft " .. cr.item .. " for " .. ns.DisplayName(o))
          end
        end
      end
    end
  end
  local out = {}
  for k, x in pairs(acc) do
    if not c.wish[k] and not c.ignore[k] then
      local b, kk, m = ns.Stock(c, { n = x.n, id = x.id })
      x.have = b + kk + m
      if x.have < x.q then
        local rs = {}
        for r in pairs(x.reasons) do rs[#rs + 1] = r end
        table.sort(rs)
        x.reason = table.concat(rs, "; ")
        out[#out + 1] = x
      end
    end
  end
  table.sort(out, function(a, b) return a.n < b.n end)
  return out
end

-- Everything alt `c` still needs: wish list, suggestions, checklist gaps.
-- Suggestion switches (Options -> What to suggest); missing means on.
function ns.Suggests(key) return ns.db.settings[key] ~= false end

function ns.OpenWants(c)
  local out = {}
  for _, w in pairs(ns.Suggests("hintWish") and c.wish or {}) do
    local want = { n = w.n, id = w.id }
    local b, k, m = ns.Stock(c, want)
    local rem = (w.q or 0) - (b + k + m)
    if rem > 0 then out[#out + 1] = { want = want, remaining = rem, reason = "wish list" } end
  end
  for _, s in ipairs(ns.Suggestions(c)) do
    out[#out + 1] = { want = { n = s.n, id = s.id }, remaining = s.q - s.have, reason = "suggested" }
  end
  for _, row in ipairs(ns.Suggests("hintKits") and ns.Checklist(c) or {}) do
    if isGap(row) then
      local b, k, m = ns.Stock(c, row.want, c)
      local rem = row.qty - (b + k + m)
      if rem > 0 then out[#out + 1] = { want = row.want, remaining = rem, reason = "checklist: " .. row.label } end
    end
  end
  if ns.db.settings.planWants and not ns.IsBank(c) and ns.LevelPlan then
    for _, prof in ipairs(ns.CraftingProfs(c)) do
      -- when another alt is the main for this profession, the mats are theirs:
      -- don't pull them back out to level this alt
      local main = ns.MainFor(c, prof)
      local plan = not (main and main.key ~= c.key) and ns.LevelPlan(c, prof)
      for _, x in ipairs((plan and plan.shop) or {}) do
        if x.need > x.have then
          out[#out + 1] = { want = { n = x.n, id = x.id }, remaining = x.need - x.have, reason = "levelling " .. prof }
        end
      end
    end
  end
  return out
end

---------------------------------------------------------------------------
-- Bank pool
---------------------------------------------------------------------------
function ns.BankAlt(c)
  for _, o in ipairs(ns.Siblings(c)) do if ns.IsBank(o) then return o end end
  return nil
end

function ns.TagForBank(text, on)
  if not text or ns.Trim(text) == "" then return nil end
  local tags = ns.db.bankTags
  local cat = not text:find("|H") and ns.FindCategoryExact(text)
  if cat then
    tags.cats[cat] = on or nil
    ns.Changed("bank")
    return ns.ref.categories[cat].name
  end
  local id, name = ns.ParseItem(text)
  if not name then return nil end
  tags.items[lower(name)] = on and { id = id, n = name } or nil
  ns.Changed("bank")
  return name
end

local function isTagged(name)
  local tags = ns.db.bankTags
  if tags.items[lower(name)] then return true end
  for cat in pairs(tags.cats) do
    if ns.ref.categories[cat] and ns.MatchCategory(cat, name) then return true end
  end
  return false
end

local function recipeOutput(name) return (name:gsub("^%a+: ", "")) end

local function knowsRecipe(o, prof, name)
  local list = o.recipes and o.recipes[prof]
  return list and list[recipeOutput(name)] ~= nil
end

local function canLearn(o, rec)
  local req = rec.req
  if not req then return false end
  local skill = o.profs and o.profs[req[1]]
  return skill and skill >= (req[2] or 1) and not knowsRecipe(o, req[1], rec.n)
end

-- How many of an item `c` itself should keep (its kit lines + wish list).
local function ownNeed(c, name, id)
  local need = 0
  if not ns.IsBank(c) then
    for _, line in ipairs(ns.EnsureKit(c)) do
      if not ns.LineLocked(line, c) and ns.WantMatches({ cat = line.cat }, name, id, c) then need = need + line.qty end
    end
  end
  for _, x in pairs(c.extras.items) do
    if ns.WantMatches({ n = x.n, id = x.id }, name, id, c) then need = need + (x.q or 1) end
  end
  for _, w in pairs(c.wish) do
    if ns.WantMatches({ n = w.n, id = w.id }, name, id, c) then need = need + (w.q or 0) end
  end
  return need
end

ns.OwnNeed = function(c, name, id) return ownNeed(c, name, id) end

local function usesAsReagent(c, name)
  local l = lower(name)
  for _, list in pairs(c.recipes or {}) do
    for _, rec in pairs(list) do
      for _, r in ipairs(rec.reagents or {}) do if r.n and lower(r.n) == l then return true end end
    end
  end
  return false
end

-- Wanted by any (non-bank) alt at all, satisfied or not?
local function wantedByAnyone(alts, name, id)
  for _, o in ipairs(alts) do
    if ownNeed(o, name, id) > 0 then return true end
  end
  return false
end

local function anyCategory(name)
  for key in pairs(ns.ref.categories) do
    if ns.MatchCategory(key, name) then return key end
  end
  return nil
end

-- What `me` should send to the bank alt from `field` ("b" bags, "k" bank).
function ns.BankPool(me, field, used)
  local out = {}
  used = used or {}
  if ns.IsBank(me) or not ns.BankAlt(me) then return out end
  local s = ns.db.settings
  local alts = {}
  for _, o in ipairs(ns.Siblings(me)) do if not ns.IsBank(o) then alts[#alts + 1] = o end end
  alts[#alts + 1] = me
  local maxLevel = 0
  for _, o in ipairs(alts) do maxLevel = math.max(maxLevel, o.level or 0) end

  for key, rec in pairs(me.inv) do
    local id = type(key) == "number" and key or nil
    local avail = (rec[field] or 0) - (used[key] or 0)
    if avail > 0 and rec.n and not (field == "b" and rec.bound) then
      local give, reason = 0, nil
      local keep = ownNeed(me, rec.n, id) + ns.FirstAidKeep(me, rec.n)
      if ns.FunnelTarget(me, rec) then
        give = 0 -- a profession main collects this (or I am that main)
      elseif s.bankTagged and isTagged(rec.n) then
        give, reason = avail - keep, "tagged for the bank"
      elseif s.bankRecipes and rec.cls == ns.CLASS_RECIPE and rec.req then
        local learner = false
        for _, o in ipairs(alts) do if canLearn(o, rec) then learner = true end end
        if not learner then give, reason = avail, "no alt can learn it yet" end
      elseif s.bankGear and (rec.cls == ns.CLASS_WEAPON or rec.cls == ns.CLASS_ARMOR) and rec.minLvl and rec.minLvl > maxLevel then
        give, reason = avail, "above every alt's level"
      elseif s.bankSurplus and anyCategory(rec.n) and (rec.cls == nil or rec.cls == ns.CLASS_CONSUMABLE) then
        if keep > 0 then
          local cap = keep * (s.surplusCap or 2)
          give, reason = avail - cap, "surplus (keeping " .. cap .. ")"
        else
          give, reason = avail, "not in " .. (me.name or "this alt") .. "'s kit"
        end
      elseif s.bankMats and rec.cls == ns.CLASS_TRADEGOODS then
        if not wantedByAnyone(alts, rec.n, id) and not usesAsReagent(me, rec.n) then
          give, reason = avail, "no alt needs it"
        end
      end
      if give > 0 then
        used[key] = (used[key] or 0) + give
        out[#out + 1] = { id = id, n = rec.n, give = give, reason = reason }
      end
    end
  end
  table.sort(out, function(a, b) return a.n < b.n end)
  return out
end


---------------------------------------------------------------------------
-- Profession mains: one alt per profession collects its materials and
-- crafts for everyone.
---------------------------------------------------------------------------
local MAIN_NOUN = {
  Cooking = "main cook", Alchemy = "main alchemist", Tailoring = "main tailor", Leatherworking = "main leatherworker",
  Blacksmithing = "main smith", Engineering = "main engineer", Enchanting = "main enchanter", ["First Aid"] = "main medic",
  Mining = "main miner", Fishing = "main fisher", Herbalism = "main herbalist", Skinning = "main skinner",
}
function ns.MainNoun(prof) return MAIN_NOUN[prof] or ("main " .. string.lower(prof or "?")) end

function ns.MainScope(c) return (c.realm or "?") .. "|" .. (c.faction or "?") end

local function scopeTable(c, create)
  ns.db.mains = ns.db.mains or {}
  local k = ns.MainScope(c)
  if create and not ns.db.mains[k] then ns.db.mains[k] = {} end
  return ns.db.mains[k]
end

-- Main alt for a profession (in c's realm and faction), or nil.
function ns.MainFor(c, prof)
  local t = scopeTable(c)
  local key = t and t[prof]
  local m = key and ns.db.chars[key]
  if key and not m then t[prof] = nil end -- forgotten alt
  return m
end

-- prof -> main char, for c's realm and faction.
function ns.Mains(c)
  local out = {}
  for prof in pairs(scopeTable(c) or {}) do
    local m = ns.MainFor(c, prof)
    if m then out[prof] = m end
  end
  return out
end

function ns.MainProfs(c)
  local list = {}
  for prof, m in pairs(ns.Mains(c)) do if m.key == c.key then list[#list + 1] = prof end end
  table.sort(list)
  return list
end

function ns.IsMain(c, prof)
  local m = ns.MainFor(c, prof)
  return m and m.key == c.key
end

function ns.SetMain(c, prof, on)
  local t = scopeTable(c, true)
  if on then t[prof] = c.key elseif t[prof] == c.key then t[prof] = nil end
  ns.Changed("mains")
end

-- Find a profession name from text ("cooking", "first aid", "alch").
function ns.FindProfession(text)
  if not text or text == "" then return nil end
  local l = lower(ns.Trim(text))
  local all = {}
  for prof in pairs(MAIN_NOUN) do all[#all + 1] = prof end
  for _, c in pairs(ns.db.chars) do for prof in pairs(c.profs or {}) do all[#all + 1] = prof end end
  for _, p in ipairs(all) do if lower(p) == l then return p end end
  for _, p in ipairs(all) do if lower(p):sub(1, #l) == l then return p end end
  return nil
end

local function recipeUses(list, name)
  local l = lower(name)
  for _, rec in pairs(list or {}) do
    for _, r in ipairs(rec.reagents or {}) do if r.n and lower(r.n) == l then return true end end
  end
  return false
end

-- Which main collects this item (may be the holder itself), and why.
-- Spare green/blue gear for the main enchanter to disenchant. Gear above
-- every alt's level stays for the bank alt when that option is on.
local NO_DE = { INVTYPE_BODY = true, INVTYPE_TABARD = true, INVTYPE_NON_EQUIP_IGNORE = true }
function ns.Disenchantable(holder, rec)
  if not (rec.cls == ns.CLASS_WEAPON or rec.cls == ns.CLASS_ARMOR) then return false end
  if rec.quality ~= 2 and rec.quality ~= 3 then return false end
  if rec.equip and NO_DE[rec.equip] then return false end
  local s = ns.db.settings
  if s.bankGear and rec.minLvl and ns.BankAlt(holder) then
    local maxLevel = holder.level or 0
    for _, o in ipairs(ns.Siblings(holder)) do if not ns.IsBank(o) then maxLevel = math.max(maxLevel, o.level or 0) end end
    if rec.minLvl > maxLevel then return false end
  end
  return true
end

function ns.FunnelTarget(holder, rec)
  if not rec or not rec.n then return nil end
  local mains = ns.Mains(holder)
  local profs = {}
  for prof in pairs(mains) do profs[#profs + 1] = prof end
  table.sort(profs)
  local matsOn = ns.Suggests("hintMains")
  -- 1. a main whose learned recipes use it
  for _, prof in ipairs(matsOn and profs or {}) do
    local m = mains[prof]
    if recipeUses(m.recipes and m.recipes[prof], rec.n) then return m, prof end
  end
  -- 2. the material family (trade goods subclass)
  if matsOn and rec.cls == ns.CLASS_TRADEGOODS and rec.subcls then
    for _, prof in ipairs(ns.Defaults.families[rec.subcls] or {}) do
      if mains[prof] then return mains[prof], prof end
    end
  end
  -- 3. gear to disenchant
  if mains.Enchanting and ns.db.settings.deGear ~= false and ns.Disenchantable(holder, rec) then
    return mains.Enchanting, "Enchanting", "to disenchant"
  end
  return nil
end

-- Cloth an alt keeps to level its own First Aid to its level's bandage tier.
function ns.FirstAidKeep(c, name)
  local skill = c.profs and c.profs["First Aid"]
  if not skill or ns.IsMain(c, "Tailoring") then return 0 end
  local target = math.min(300, (c.level or 1) * 5)
  if skill >= target then return 0 end
  for _, b in ipairs(ns.Defaults.firstAidCloth) do
    if skill < b.upTo then
      if lower(name) ~= lower(b.cloth) then return 0 end
      return 2 * (math.min(target, b.upTo) - skill)
    end
  end
  return 0
end

-- What `me` should send to each profession main from `field`.
local function funnelPlan(me, field, used)
  local byMain = {}
  for key, rec in pairs(me.inv) do
    local avail = (rec[field] or 0) - (used[key] or 0)
    if avail > 0 and rec.n and not (field == "b" and rec.bound) then
      local main, prof, why = ns.FunnelTarget(me, rec)
      if main and main.key ~= me.key then
        local id = type(key) == "number" and key or nil
        local keep = why and 0 or (ns.OwnNeed(me, rec.n, id) + ns.FirstAidKeep(me, rec.n))
        local give = avail - keep
        if give > 0 then
          used[key] = (used[key] or 0) + give
          local g = byMain[main.key]
          if not g then g = { to = main, items = {}, main = prof }; byMain[main.key] = g end
          g.items[#g.items + 1] = { id = id, n = rec.n, give = give, reason = why or ns.MainNoun(prof) }
        end
      end
    end
  end
  local out = {}
  for _, g in pairs(byMain) do
    table.sort(g.items, function(a, b) return a.n < b.n end)
    out[#out + 1] = g
  end
  table.sort(out, function(a, b) return ns.DisplayName(a.to) < ns.DisplayName(b.to) end)
  return out
end

-- The main's to-make list: kit gaps it can craft for alts, then skill-ups.
function ns.ToMake(c)
  local out = {}
  local s = ns.db.settings
  for _, prof in ipairs(ns.MainProfs(c)) do
    local list = c.recipes and c.recipes[prof]
    if list then
      local acc, order = {}, {}
      local pool = ns.Siblings(c)
      pool[#pool + 1] = c
      for _, o in ipairs(pool) do
        if not ns.IsBank(o) then
          for _, row in ipairs(ns.Checklist(o)) do
            if (row.kind == "line" or row.kind == "extra") and row.status ~= "locked" and not row.optional and row.have < row.qty then
              local b, k, m = ns.Stock(o, row.want, o)
              local rem = row.qty - (b + k + m)
              if rem > 0 then
                -- best recipe of this profession for that alt
                local pick, pickLvl
                for outName, rec in pairs(list) do
                  if ns.WantMatches(row.want, outName, rec.id, o) then
                    local lvl = 0
                    if row.want.cat then
                      local r = ns.ref.categories[row.want.cat]._names[lower(outName)]
                      lvl = (r and r.lvl) or 0
                    end
                    if not pick or lvl > pickLvl then pick, pickLvl = outName, lvl end
                  end
                end
                if pick then
                  local e = acc[pick]
                  if not e then e = { name = pick, rec = list[pick], prof = prof, qty = 0, kind = "gap", forList = {} }; acc[pick] = e; order[#order + 1] = pick end
                  e.qty = e.qty + rem
                  e.forList[#e.forList + 1] = { name = ns.DisplayName(o), n = rem }
                end
              end
            end
          end
        end
      end
      for _, name in ipairs(order) do out[#out + 1] = acc[name] end
      -- skill-ups
      local cands = {}
      for outName, rec in pairs(list) do
        if (rec.diff == "optimal" or rec.diff == "medium") and not acc[outName] then cands[#cands + 1] = { n = outName, rec = rec } end
      end
      table.sort(cands, function(a, b)
        if a.rec.diff ~= b.rec.diff then return a.rec.diff == "optimal" end
        return a.n < b.n
      end)
      for i = 1, math.min(#cands, s.suggestMaxRecipes or 3) do
        out[#out + 1] = { name = cands[i].n, rec = cands[i].rec, prof = prof, qty = s.suggestCrafts or 3,
                          kind = "skillup", diff = cands[i].rec.diff, forList = {} }
      end
    end
  end
  -- materials on hand
  for _, e in ipairs(out) do
    local now, all = math.huge, math.huge
    e.mats = {}
    for _, r in ipairs(e.rec.reagents or {}) do
      local b, k, m = ns.Stock(c, { n = r.n, id = r.id })
      local per = r.c or 1
      e.mats[#e.mats + 1] = { n = r.n or "?", need = per * e.qty, have = b + k, mail = m }
      now = math.min(now, math.floor((b + k) / per))
      all = math.min(all, math.floor((b + k + m) / per))
    end
    if now == math.huge then now, all = e.qty, e.qty end
    e.canNow, e.canAll = math.min(now, e.qty), math.min(all, e.qty)
  end
  return out
end

---------------------------------------------------------------------------
-- Levelling plan: from the recipes a crafter knows, the cheapest way through
-- the next few skill points, and what to buy or collect for it.
---------------------------------------------------------------------------
local CAPS = { 75, 150, 225, 300 }
local CAP_NAMES = { [75] = "Apprentice", [150] = "Journeyman", [225] = "Expert", [300] = "Artisan" }
ns.PLAN_WINDOW = 10   -- plan this many points at a time: recipe colours change as you level

function ns.LevelPlan(c, prof)
  local skill = c.profs and c.profs[prof]
  if not skill then return nil end
  local plan = { prof = prof, skill = skill, max = c.profMax and c.profMax[prof] }
  local nextCap = 300
  for _, cap in ipairs(CAPS) do if cap > skill then nextCap = cap; break end end
  plan.nextCap, plan.capName = nextCap, CAP_NAMES[nextCap]
  if skill >= 300 then plan.done = true; return plan end
  if plan.max and skill >= plan.max then plan.train = true; return plan end
  local list = c.recipes and c.recipes[prof]
  if not list then plan.noRecipes = true; return plan end
  local limit = math.min(nextCap, plan.max or nextCap)
  local window = math.min(ns.PLAN_WINDOW, limit - skill)
  plan.window = window
  -- score each skill-up recipe: how much of its mats you already hold (all alts), then fewest reagents
  local pool = ns.Siblings(c)
  local best
  for outName, rec in pairs(list) do
    if rec.diff == "optimal" or rec.diff == "medium" then
      local crafts = rec.diff == "optimal" and window or math.ceil(window * 1.5)
      local held, need = 0, 0
      for _, r in ipairs(rec.reagents or {}) do
        local want = { n = r.n, id = r.id }
        local b, k, m = ns.Stock(c, want)
        local total = b + k + m
        for _, o in ipairs(pool) do local ob, ok, om = ns.Stock(o, want); total = total + ob + ok + om end
        local n = (r.c or 1) * crafts
        need = need + n
        held = held + math.min(total, n)
      end
      local score = (need > 0 and held / need or 1) + (rec.diff == "optimal" and 1 or 0) - #(rec.reagents or {}) * 0.01
      if not best or score > best.score then best = { name = outName, rec = rec, crafts = crafts, score = score } end
    end
  end
  if not best then plan.stuck = true; return plan end
  plan.recipe, plan.rec, plan.crafts, plan.diff = best.name, best.rec, best.crafts, best.rec.diff
  plan.shop = {}
  for _, r in ipairs(best.rec.reagents or {}) do
    local want = { n = r.n, id = r.id }
    local b, k, m = ns.Stock(c, want)
    local need = (r.c or 1) * best.crafts
    local others = {}
    for _, o in ipairs(pool) do
      local ob, ok, om = ns.Stock(o, want)
      if ob + ok + om > 0 then others[#others + 1] = { name = ns.DisplayName(o), n = ob + ok + om } end
    end
    plan.shop[#plan.shop + 1] = { n = r.n or "?", id = r.id, need = need, bags = b, bank = k, mail = m, have = b + k + m,
                                  others = others, vendor = ns.db.vendorItems and r.n and ns.db.vendorItems[lower(r.n)] }
  end
  return plan
end

function ns.CraftingProfs(c)
  local out = {}
  local gather = { Herbalism = true, Mining = true, Skinning = true, Fishing = true }
  for prof in pairs(c.profs or {}) do if not gather[prof] or (c.recipes and c.recipes[prof]) then out[#out + 1] = prof end end
  table.sort(out, function(a, b)
    local am, bm = ns.IsMain(c, a), ns.IsMain(c, b)
    if am ~= bm then return am end
    return a < b
  end)
  return out
end

---------------------------------------------------------------------------
-- Dungeon quests from the DungeonJournal addon (ForeverDungeonJournal), when
-- it is installed. Fettle only reads its public data table; nothing is copied.
---------------------------------------------------------------------------
function ns.DJ()
  local fdj = _G.ForeverDungeonJournal_NS
  return fdj and type(fdj.DB) == "table" and fdj.DB or nil
end

-- Find a DungeonJournal page by instance name (exact, then without "The ", then aliases).
function ns.DJFind(name)
  local db = ns.DJ()
  if not db or not name then return nil end
  if db[name] then return name end
  local low = name:lower():gsub("^the ", "")
  for key in pairs(db) do if key:lower():gsub("^the ", "") == low then return key end end
  local al = _G.ForeverDungeonJournal_NS.DUNGEON_SEARCH_ALIASES
  if type(al) == "table" then
    for key, list in pairs(al) do
      for _, a in ipairs(type(list) == "table" and list or {}) do if a == low and db[key] then return key end end
    end
  end
end

local function levelRange(s)
  local a, b = tostring(s or ""):match("(%d+)%s*%-%s*(%d+)")
  return tonumber(a), tonumber(b)
end

-- Every dungeon with quests, sorted by level; fits = the alt's level is in range.
function ns.DungeonList(c)
  local db = ns.DJ()
  local out = {}
  if not db then return out end
  for name, d in pairs(db) do
    if type(d) == "table" and type(d.quests) == "table" and #d.quests > 0 then
      local lo, hi = levelRange(d.level)
      out[#out + 1] = { name = name, lo = lo or 0, hi = hi or 0, level = d.level, location = d.location,
                        fits = lo and hi and (c.level or 1) >= lo - 2 and (c.level or 1) <= hi }
    end
  end
  table.sort(out, function(a, b) if a.lo ~= b.lo then return a.lo < b.lo end return a.name < b.name end)
  return out
end

-- The dungeon this alt is getting ready for: chosen by you, or the best fit for its level.
function ns.TargetDungeon(c)
  local db = ns.DJ()
  if not db then return nil end
  if c.nextDungeon and db[c.nextDungeon] then return c.nextDungeon end
  local best, bestN
  for _, d in ipairs(ns.DungeonList(c)) do
    if d.fits then
      local n = 0
      for _, q in ipairs(ns.DungeonQuests(c, d.name)) do if q.state ~= "done" and q.state ~= "other" then n = n + 1 end end
      if n > 0 and (not best or n > bestN) then best, bestN = d.name, n end
    end
  end
  return best
end

local function questState(c, q)
  if q.faction and q.faction ~= "Both" and c.faction and q.faction ~= c.faction then return "other" end
  local st = c.djStatus and q.id and c.djStatus[q.id]
  if st then return st end
  if q.requires and (c.level or 1) < q.requires then return "later" end
  return "missing"
end

-- Quests of one dungeon for an alt: state = done | log | missing | later | other (wrong faction).
function ns.DungeonQuests(c, dungeon)
  local db = ns.DJ()
  local d = db and db[dungeon]
  local out = {}
  if not d then return out end
  for _, q in ipairs(d.quests or {}) do
    if type(q) == "table" and q.name then
      out[#out + 1] = { q = q, name = q.name, state = questState(c, q), pickup = q.pickup, turnin = q.turnin,
                        requires = q.requires, note = q.note, objective = q.objective, faction = q.faction }
    end
  end
  return out
end

function ns.DungeonQuestSummary(c, dungeon)
  local have, missing, total = 0, 0, 0
  for _, q in ipairs(ns.DungeonQuests(c, dungeon)) do
    if q.state ~= "other" and q.state ~= "done" and q.state ~= "later" then
      total = total + 1
      if q.state == "log" then have = have + 1 else missing = missing + 1 end
    end
  end
  return have, missing, total
end

---------------------------------------------------------------------------
-- Hints (bank / mailbox / vendor)
---------------------------------------------------------------------------
-- Items in my bags (field "b") or bank ("k") that fill target's open wants.
local function giveList(me, field, target, used)
  local items = {}
  for _, w in ipairs(ns.OpenWants(target)) do
    local left = w.remaining
    local _, _, _, mine = ns.Stock(me, w.want, target)
    for _, it in ipairs(mine) do
      local avail = (it[field] or 0) - (used[it.key] or 0)
      if field == "b" and it.bound then avail = 0 end
      if left > 0 and avail > 0 then
        local give = math.min(left, avail)
        used[it.key] = (used[it.key] or 0) + give
        left = left - give
        items[#items + 1] = { id = it.id, n = it.n, give = give, reason = w.reason }
      end
    end
  end
  return items
end

-- Recipes I hold that target can learn now (and I can't).
local function learnables(me, field, target, used)
  local items = {}
  for key, rec in pairs(me.inv) do
    local avail = (rec[field] or 0) - (used[key] or 0)
    if avail > 0 and rec.cls == ns.CLASS_RECIPE and not (field == "b" and rec.bound)
       and canLearn(target, rec) and not canLearn(me, rec) then
      used[key] = (used[key] or 0) + 1
      items[#items + 1] = { id = type(key) == "number" and key or nil, n = rec.n, give = 1, reason = "can learn this recipe" }
    end
  end
  return items
end

-- Spare ordinary bags I hold that are bigger than another alt's smallest
-- equipped bag (or fill an empty bag slot). Biggest bag goes to the alt with
-- the smallest bag first. Returns { [alt] = { items } }.
function ns.BagUpgrades(me, field, used)
  used = used or {}
  local spares = {}
  for key, rec in pairs(me.inv or {}) do
    local slots = rec.slots or (type(key) == "number" and ns.db.bagSlots and ns.db.bagSlots[key])
    if rec.cls == ns.CLASS_CONTAINER and (rec.subcls or 0) == 0 and slots and slots > 0
       and not (field == "b" and rec.bound) then
      for _ = 1, (rec[field] or 0) - (used[key] or 0) do spares[#spares + 1] = { key = key, n = rec.n, slots = slots } end
    end
  end
  table.sort(spares, function(a, b) return a.slots > b.slots end)
  local res = {}
  if #spares == 0 then return res end
  -- each alt's equipped bags, smallest first, as they would be after earlier upgrades.
  -- I'm in the pool too, so a bag I should equip myself isn't mailed away.
  local alts = {}
  local pool = ns.Siblings(me)
  table.insert(pool, 1, me)
  for _, o in ipairs(pool) do
    if o.bagSizes and #o.bagSizes > 0 then
      local sz = {}
      for i, n in ipairs(o.bagSizes) do sz[i] = n end
      alts[#alts + 1] = { c = o, sizes = sz }
    end
  end
  for _, b in ipairs(spares) do
    local best, bestIdx
    for _, a in ipairs(alts) do
      table.sort(a.sizes)
      if a.sizes[1] < b.slots and (not best or a.sizes[1] < best.sizes[1]) then best, bestIdx = a, 1 end
    end
    if best then
      best.oldSize = best.sizes[bestIdx]
      best.sizes[bestIdx] = b.slots
      used[b.key] = (used[b.key] or 0) + 1
    end
    if best and best.c ~= me then
      local old = best.oldSize
      res[best.c] = res[best.c] or {}
      local list = res[best.c]
      local merged
      for _, it in ipairs(list) do if it.n == b.n then it.give = it.give + 1; merged = true end end
      if not merged then
        list[#list + 1] = { id = type(b.key) == "number" and b.key or nil, n = b.n, give = 1,
                            reason = "bigger bag: " .. b.slots .. " slots (" .. (old == 0 and "empty bag slot" or ("replaces a " .. old)) .. ")" }
      end
    end
  end
  return res
end

local function planFrom(me, field)
  local used, out = {}, {}
  for _, o in ipairs(ns.Siblings(me)) do
    if not ns.IsBank(o) then
      local items = giveList(me, field, o, used)
      if ns.Suggests("hintLearn") then
        for _, it in ipairs(learnables(me, field, o, used)) do items[#items + 1] = it end
      end
      if #items > 0 then out[#out + 1] = { to = o, items = items } end
    end
  end
  if ns.db.settings.hintsBags ~= false then
    for o, items in pairs(ns.BagUpgrades(me, field, used)) do
      local group
      for _, g in ipairs(out) do if g.to == o and not g.pool then group = g end end
      if not group then group = { to = o, items = {} }; out[#out + 1] = group end
      for _, it in ipairs(items) do group.items[#group.items + 1] = it end
    end
  end
  for _, g in ipairs(funnelPlan(me, field, used)) do out[#out + 1] = g end
  local bank = ns.BankAlt(me)
  if bank then
    local items = ns.BankPool(me, field, used)
    if #items > 0 then out[#out + 1] = { to = bank, items = items, pool = true } end
  end
  return out, used
end

function ns.MailHints(me)
  return (planFrom(me, "b"))
end

function ns.BankHints(me)
  local res = { self = {}, alts = {} }
  for _, row in ipairs(ns.Checklist(me)) do
    if isGap(row) then
      local left = row.qty - row.have
      local _, _, _, mine = ns.Stock(me, row.want, me)
      for _, it in ipairs(mine) do
        if left > 0 and it.k > 0 then
          local take = math.min(left, it.k)
          left = left - take
          res.self[#res.self + 1] = { id = it.id, n = it.n, give = take, reason = row.label }
        end
      end
    end
  end
  res.alts = (planFrom(me, "k"))
  return res
end

local function MerchantItems()
  local list = {}
  local n = (GetMerchantNumItems and GetMerchantNumItems()) or 0
  for i = 1, n do
    local name, stack, avail
    if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
      local ok, info = pcall(C_MerchantFrame.GetItemInfo, i)
      if ok and info then name, stack, avail = info.name, info.stackCount, info.numAvailable end
    end
    if not name and GetMerchantItemInfo then
      local ok, a, _, _, q, na = pcall(GetMerchantItemInfo, i)
      if ok then name, stack, avail = a, q, na end
    end
    local link = GetMerchantItemLink and GetMerchantItemLink(i)
    local id = link and tonumber(link:match("item:(%d+)"))
    if name then
      list[#list + 1] = { index = i, n = name, id = id, stack = stack or 1, avail = avail }
      ns.db.vendorItems = ns.db.vendorItems or {}
      ns.db.vendorItems[lower(name)] = true
      local m = id and ns.ItemMeta and ns.ItemMeta(id)
      if m and ns.LearnItem then ns.LearnItem(name, m.minLvl) end
    end
  end
  return list
end
ns.MerchantItems = MerchantItems

-- Recipe scrolls a category pattern could catch by accident ("Recipe: Elixir of ...").
local SCROLL = { "^recipe:", "^pattern:", "^plans:", "^schematic:", "^formula:", "^manual:", "^design:", "^technique:" }
local function isScroll(name)
  local l = lower(name or "")
  for _, p in ipairs(SCROLL) do if l:find(p) then return true end end
  return false
end

-- What `me` should buy from a vendor:
--   direct:   my wish list and my checklist gaps (the item itself)
--   reagents: only for recipes I know that either give me a skill-up now,
--             or make something my kit/wish list or another alt's still needs.
function ns.VendorWants(me)
  local direct, mats = {}, {}
  if ns.IsBank(me) then
    for _, w in pairs(me.wish) do
      local want = { n = w.n, id = w.id }
      local b, k, m = ns.Stock(me, want)
      if (w.q or 0) > b + k + m then direct[#direct + 1] = { want = want, remaining = w.q - (b + k + m), reason = "wish list" } end
    end
    return direct, mats
  end
  local wishOn, kitsOn = ns.Suggests("hintWish"), ns.Suggests("hintKits")
  for _, w in pairs(wishOn and me.wish or {}) do
    local want = { n = w.n, id = w.id }
    local b, k, m = ns.Stock(me, want)
    if (w.q or 0) > b + k + m then direct[#direct + 1] = { want = want, remaining = w.q - (b + k + m), reason = "wish list" } end
  end
  for _, row in ipairs(kitsOn and ns.Checklist(me) or {}) do
    if isGap(row) then
      local b, k, m = ns.Stock(me, row.want, me)
      local rem = row.qty - (b + k + m)
      if rem > 0 then direct[#direct + 1] = { want = row.want, remaining = rem, reason = "checklist: " .. row.label } end
    end
  end

  local acc = {}
  -- skill-ups: the levelling plan only ever uses orange/yellow recipes I know
  for _, prof in ipairs(ns.db.settings.planWants and ns.CraftingProfs(me) or {}) do
    local plan = ns.LevelPlan(me, prof)
    if plan and plan.rec then addReagents(acc, plan.rec, plan.crafts, prof .. " skill-up: " .. plan.recipe) end
  end
  -- crafts for anything I or my alts still need, from recipes I know
  local function craftFor(o, want, n, what)
    if n <= 0 then return end
    for _, list in pairs(me.recipes or {}) do
      for outName, rec in pairs(list) do
        if ns.WantMatches(want, outName, rec.id, o) then
          addReagents(acc, rec, n, "craft " .. outName .. (o == me and "" or (" for " .. ns.DisplayName(o))))
          return
        end
      end
    end
  end
  local pool = ns.Siblings(me)
  pool[#pool + 1] = me
  for _, o in ipairs(pool) do
    if not ns.IsBank(o) and kitsOn then
      for _, row in ipairs(ns.Checklist(o)) do
        if isGap(row) then craftFor(o, row.want, row.qty - row.have, row.label) end
      end
    end
    for _, w in pairs(wishOn and o.wish or {}) do
      local want = { n = w.n, id = w.id }
      local b, k, m = ns.Stock(o, want)
      craftFor(o, want, (w.q or 0) - (b + k + m), w.n)
    end
  end
  for _, x in pairs(acc) do
    local b, k, m = ns.Stock(me, { n = x.n, id = x.id })
    if x.q > b + k + m then
      local rs = {}
      for r in pairs(x.reasons) do rs[#rs + 1] = r end
      table.sort(rs)
      mats[#mats + 1] = { want = { n = x.n, id = x.id }, remaining = x.q - (b + k + m), reason = table.concat(rs, "; ") }
    end
  end
  return direct, mats
end

function ns.VendorHints(me)
  local out = {}
  local merch = MerchantItems()
  if #merch == 0 then return out end
  local byIndex = {}
  local function add(it, buy, reason)
    local have = byIndex[it.index]
    if have then
      if buy > have.buy then have.buy = buy end
      if not have.reason:find(reason, 1, true) then have.reason = have.reason .. "; " .. reason end
      return
    end
    local v = { index = it.index, n = it.n, id = it.id, buy = buy, reason = reason }
    byIndex[it.index] = v
    out[#out + 1] = v
  end
  local direct, mats = ns.VendorWants(me)
  for _, w in ipairs(direct) do
    local pick, pickLvl
    for _, it in ipairs(merch) do
      if ns.WantMatches(w.want, it.n, it.id, me) and not (w.want.cat and isScroll(it.n)) then
        local lvl = 0
        if w.want.cat then
          local r = ns.ref.categories[w.want.cat]._names[lower(it.n)]
          lvl = (r and r.lvl) or 0
        end
        if not pick or lvl > pickLvl then pick, pickLvl = it, lvl end
      end
    end
    if pick then add(pick, w.remaining, w.reason) end
  end
  for _, w in ipairs(mats) do
    for _, it in ipairs(merch) do
      if (w.want.id and it.id == w.want.id) or lower(w.want.n or "") == lower(it.n) then add(it, w.remaining, w.reason); break end
    end
  end
  return out
end

---------------------------------------------------------------------------
-- Actions (run from button clicks)
---------------------------------------------------------------------------
local function UseSlot(bag, slot)
  if C_Container and C_Container.UseContainerItem then C_Container.UseContainerItem(bag, slot)
  elseif UseContainerItem then UseContainerItem(bag, slot) end
end

-- Move whole stacks of `items` (list of {id,n,give}) out of `bags`.
local function MoveStacks(bags, items, limit, skipBound)
  local moved, stacks = {}, 0
  for _, it in ipairs(items) do
    local left = it.give
    ns.ForEachSlot(bags, function(bag, slot, id, name, count, bound)
      if left > 0 and (not limit or stacks < limit) and not (skipBound and bound) and
         ((it.id and id == it.id) or lower(name) == lower(it.n)) then
        UseSlot(bag, slot)
        left = left - count
        stacks = stacks + 1
        moved[#moved + 1] = name .. " x" .. count
      end
    end)
  end
  return moved
end

-- Empty the Send Mail attachment slots (items go back to the bags).
local function ClearAttachments()
  local n = 0
  if not (GetSendMailItem and ClickSendMailItemButton) then return 0 end
  for i = (ATTACHMENTS_MAX_SEND or 12), 1, -1 do
    local ok, name = pcall(GetSendMailItem, i)
    if ok and name then pcall(ClickSendMailItemButton, i, true); n = n + 1 end
  end
  return n
end

-- Switch the mailbox to its Send Mail tab (as clicking the tab would).
local function ShowSendTab()
  if SendMailFrame and SendMailFrame:IsShown() then return true end
  if not (MailFrame and MailFrame:IsShown()) then return false end
  local tab = _G.MailFrameTab2
  if tab and tab.Click then pcall(tab.Click, tab)
  elseif MailFrameTab_OnClick then pcall(MailFrameTab_OnClick, tab, 2) end
  return SendMailFrame and SendMailFrame:IsShown()
end
ns.ShowSendTab = ShowSendTab

function ns.AttachMail(to, items)
  if not ShowSendTab() then
    -- never use bag items with the inbox showing: that would equip or use them
    ns.Print("Couldn't switch to the Send Mail tab. Click it, then click Attach.")
    return
  end
  -- start clean: whatever was attached for someone else goes back to the bags
  local cleared = ClearAttachments()
  if SendMailNameEditBox then
    local name = ns.ResolveMailName(to)
    SendMailNameEditBox:SetText(name or "")
    if name and not name:find(" ", 1, true) then
      ns.Print("Fettle doesn't know " .. name .. "'s last name yet. Log in on " .. name ..
        " once, or type the full name in the To box (Fettle remembers it after the mail sends).")
    end
  end
  if SendMailSubjectEditBox and SendMailSubjectEditBox.GetText and SendMailSubjectEditBox:GetText() == "" then
    SendMailSubjectEditBox:SetText("Fettle")
  end
  local function attach()
    local moved = MoveStacks(ns.BagIDs(), items, ATTACHMENTS_MAX_SEND or 12, true)
    if #moved > 0 then ns.Print("Attached for " .. ns.DisplayName(to) .. ":", table.concat(moved, ", "), "(whole stacks)") end
  end
  -- give the cleared items a moment to land back in the bags
  if cleared > 0 and C_Timer and C_Timer.After then C_Timer.After(0.4, attach) else attach() end
end

function ns.Withdraw(items)
  if not ns.IsBankOpen() then ns.Print("Bank is not open.") return end
  local moved = MoveStacks(ns.BankBagIDs(), items)
  if #moved > 0 then ns.Print("Withdrew:", table.concat(moved, ", ")) end
end

function ns.Buy(index, qty)
  if not BuyMerchantItem then return end
  local maxStack = (GetMerchantItemMaxStack and GetMerchantItemMaxStack(index)) or qty
  if not maxStack or maxStack < 1 then maxStack = qty end
  local left = qty
  while left > 0 do
    local n = math.min(left, maxStack)
    BuyMerchantItem(index, n)
    left = left - n
  end
end
