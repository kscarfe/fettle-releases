-- Fettle: reference list = shipped defaults + your in-game edits.
local _, ns = ...

local function lower(s) return s and string.lower(s) or "" end

---------------------------------------------------------------------------
-- Build the merged reference
---------------------------------------------------------------------------
function ns.RebuildReference()
  local D = ns.Defaults
  local custom = ns.db.custom
  local ref = { categories = {}, tasks = {}, taskById = {} }

  -- categories
  for key, def in pairs(D.categories) do ref.categories[key] = ns.DeepCopy(def) end
  for key, patch in pairs(custom.categories) do
    if patch.deleted then
      ref.categories[key] = nil
    elseif patch.full then
      ref.categories[key] = ns.DeepCopy(patch.full)
      ref.categories[key].custom = true
    else
      local cat = ref.categories[key]
      if cat then
        if patch.name then cat.name = patch.name end
        local kept = {}
        for _, r in ipairs(cat.ranks or {}) do
          if not (patch.removed and patch.removed[lower(r.n)]) then kept[#kept + 1] = r end
        end
        cat.ranks = kept
        for _, r in ipairs(patch.add or {}) do cat.ranks[#cat.ranks + 1] = ns.DeepCopy(r) end
        for _, r in ipairs(cat.ranks) do
          local l = patch.rankLvl and patch.rankLvl[lower(r.n)]
          if l ~= nil then r.lvl = (l ~= false) and l or nil end
        end
        local pats = {}
        for _, p in ipairs(cat.patterns or {}) do
          if not (patch.removedPatterns and patch.removedPatterns[p]) then pats[#pats + 1] = p end
        end
        for _, p in ipairs(patch.addPatterns or {}) do pats[#pats + 1] = p end
        cat.patterns = pats
        cat.edited = true
      end
    end
  end

  -- tasks
  for _, def in ipairs(D.tasks) do
    local patch = custom.tasks[def.id]
    if not (patch and patch.deleted) then
      local t = ns.DeepCopy(def)
      if patch then
        if patch.off ~= nil then t.off = patch.off end
        if patch.optional ~= nil then t.optional = patch.optional end
        if patch.text then t.text = patch.text end
      end
      ref.tasks[#ref.tasks + 1] = t; ref.taskById[t.id] = t
    end
  end
  for id, patch in pairs(custom.tasks) do
    if patch.full and not patch.deleted then
      local t = ns.DeepCopy(patch.full); t.id = id; t.custom = true
      if patch.off ~= nil then t.off = patch.off end
      ref.tasks[#ref.tasks + 1] = t; ref.taskById[id] = t
    end
  end

  -- levels and items Fettle has seen in the game (your own edits win)
  local learnedLvl = ns.db.learnedLvl or {}
  local learnedRanks = ns.db.learnedRanks or {}
  for key, cat in pairs(ref.categories) do
    local patch = custom.categories[key] or {}
    local have = {}
    for _, r in ipairs(cat.ranks or {}) do
      local l = lower(r.n)
      have[l] = true
      if not (patch.rankLvl and patch.rankLvl[l] ~= nil) and learnedLvl[l] then r.lvl = learnedLvl[l]; r.seen = true end
    end
    for l, name in pairs(learnedRanks[key] or {}) do
      if not have[l] and not (patch.removed and patch.removed[l]) then
        cat.ranks = cat.ranks or {}
        table.insert(cat.ranks, { n = name, lvl = learnedLvl[l], src = "Seen in game", seen = true })
      end
    end
  end

  -- matchers
  for key, cat in pairs(ref.categories) do
    local names = {}
    for _, r in ipairs(cat.ranks or {}) do names[lower(r.n)] = r end
    local pats = {}
    for _, p in ipairs(cat.patterns or {}) do pats[#pats + 1] = lower(p) end
    cat._names, cat._pats, cat.key = names, pats, key
  end

  ns.ref = ref
  ns.matchCache = {}
  if ns.Changed then ns.Changed("ref") end
  return ref
end

---------------------------------------------------------------------------
-- Matching
---------------------------------------------------------------------------
function ns.MatchCategory(key, itemName)
  local cat = ns.ref.categories[key]
  if not cat or not itemName then return false end
  local cache = ns.matchCache[key]
  if not cache then cache = {}; ns.matchCache[key] = cache end
  local hit = cache[itemName]
  if hit ~= nil then return hit end
  local l = lower(itemName)
  hit = cat._names[l] ~= nil
  if not hit then
    for _, p in ipairs(cat._pats) do
      local ok, found = pcall(string.find, l, p)
      if ok and found then hit = true; break end
    end
  end
  cache[itemName] = hit
  return hit
end

-- Whether a rank is usable by character c (level and profession skill).
function ns.RankUsable(r, c)
  if not r.lvl then return false end
  if c and c.level and r.lvl > c.level then return false end
  if r.skill and c then
    local prof, need = r.skill[1], r.skill[2] or 1
    local have = c.profs and c.profs[prof]
    if not have or have < need then return false end
  end
  return true
end

-- Item usable by c? Unknown items (not a listed rank) are assumed usable.
function ns.ItemUsable(key, itemName, c)
  local cat = ns.ref.categories[key]
  local r = cat and cat._names[lower(itemName)]
  if not r then return true end
  if not r.lvl then return true end
  return ns.RankUsable(r, c)
end

-- Highest-level usable rank of a category for character c.
function ns.BestRank(key, c)
  local cat = ns.ref.categories[key]
  if not cat then return nil end
  local best
  for _, r in ipairs(cat.ranks or {}) do
    if ns.RankUsable(r, c) then
      local score = r.lvl + ((r.skill and r.skill[2] or 0) / 1000)
      if not best or score > best._score then best = r; best._score = score end
    end
  end
  return best
end

---------------------------------------------------------------------------
-- Editing API (all edits go to db.custom, then the reference is rebuilt)
---------------------------------------------------------------------------
local function catPatch(key)
  local c = ns.db.custom.categories
  c[key] = c[key] or {}
  return c[key]
end

local function isCustomCat(key)
  local p = ns.db.custom.categories[key]
  return p and p.full
end

function ns.Ref_AddRank(key, name, lvl, src)
  if not name or name == "" then return end
  if isCustomCat(key) then
    table.insert(isCustomCat(key).ranks, { n = name, lvl = lvl, src = src })
  else
    local p = catPatch(key)
    if p.removed then p.removed[lower(name)] = nil end
    p.add = p.add or {}
    table.insert(p.add, { n = name, lvl = lvl, src = src })
  end
  ns.RebuildReference()
end

function ns.Ref_RemoveRank(key, name)
  local full = isCustomCat(key)
  if full then
    for i = #full.ranks, 1, -1 do if lower(full.ranks[i].n) == lower(name) then table.remove(full.ranks, i) end end
  else
    local p = catPatch(key)
    if p.add then
      for i = #p.add, 1, -1 do if lower(p.add[i].n) == lower(name) then table.remove(p.add, i) end end
    end
    p.removed = p.removed or {}
    p.removed[lower(name)] = true
  end
  ns.RebuildReference()
end

function ns.Ref_SetRankLevel(key, name, lvl)
  local full = isCustomCat(key)
  if full then
    for _, r in ipairs(full.ranks) do if lower(r.n) == lower(name) then r.lvl = lvl end end
  else
    local p = catPatch(key)
    p.rankLvl = p.rankLvl or {}
    p.rankLvl[lower(name)] = lvl or false
  end
  ns.RebuildReference()
end

function ns.Ref_AddPattern(key, pat)
  if not pat or pat == "" then return end
  local ok = pcall(string.find, "", pat)
  if not ok then ns.Print("Invalid pattern:", pat) return end
  local full = isCustomCat(key)
  if full then table.insert(full.patterns, pat)
  else
    local p = catPatch(key)
    if p.removedPatterns then p.removedPatterns[pat] = nil end
    p.addPatterns = p.addPatterns or {}
    table.insert(p.addPatterns, pat)
  end
  ns.RebuildReference()
end

function ns.Ref_RemovePattern(key, pat)
  local full = isCustomCat(key)
  if full then
    for i = #full.patterns, 1, -1 do if full.patterns[i] == pat then table.remove(full.patterns, i) end end
  else
    local p = catPatch(key)
    if p.addPatterns then
      for i = #p.addPatterns, 1, -1 do if p.addPatterns[i] == pat then table.remove(p.addPatterns, i) end end
    end
    p.removedPatterns = p.removedPatterns or {}
    p.removedPatterns[pat] = true
  end
  ns.RebuildReference()
end

function ns.Ref_RenameCategory(key, name)
  local full = isCustomCat(key)
  if full then full.name = name else catPatch(key).name = name end
  ns.RebuildReference()
end

function ns.Ref_NewCategory(name)
  local base = "U_" .. string.upper((name or "NEW"):gsub("[^%w]", "_"))
  local key, i = base, 1
  while ns.ref.categories[key] do i = i + 1; key = base .. i end
  ns.db.custom.categories[key] = { full = { name = name, ranks = {}, patterns = {} } }
  ns.RebuildReference()
  return key
end

function ns.Ref_ResetCategory(key)
  if ns.Defaults.categories[key] then ns.db.custom.categories[key] = nil
  else ns.db.custom.categories[key] = { deleted = true } end
  ns.RebuildReference()
end

function ns.Ref_AddTask(text, optional)
  local id, i = "u_task", 1
  while ns.ref.taskById[id .. i] do i = i + 1 end
  ns.db.custom.tasks[id .. i] = { full = { text = text, optional = optional } }
  ns.RebuildReference()
end

function ns.Ref_SetTaskOff(id, off)
  ns.db.custom.tasks[id] = ns.db.custom.tasks[id] or {}
  ns.db.custom.tasks[id].off = off and true or false
  ns.RebuildReference()
end

function ns.Ref_DeleteTask(id)
  local isDefault = false
  for _, d in ipairs(ns.Defaults.tasks) do if d.id == id then isDefault = true end end
  if isDefault then ns.db.custom.tasks[id] = { deleted = true } else ns.db.custom.tasks[id] = nil end
  ns.RebuildReference()
end

---------------------------------------------------------------------------
-- Learning from the game: required levels of items you hold, see at vendors
-- or can craft. Items that a category's name pattern catches become ranks.
---------------------------------------------------------------------------
local learnQueued = false
function ns.LearnItem(name, minLvl)
  if not name or not ns.ref or not ns.db then return end
  if type(minLvl) ~= "number" then return end
  local db = ns.db
  db.learnedLvl = db.learnedLvl or {}
  db.learnedRanks = db.learnedRanks or {}
  local l = lower(name)
  local lvl = math.max(1, minLvl)
  local changed = db.learnedLvl[l] ~= lvl
  db.learnedLvl[l] = lvl
  for key, cat in pairs(ns.ref.categories) do
    if not cat._names[l] and ns.MatchCategory(key, name) then
      db.learnedRanks[key] = db.learnedRanks[key] or {}
      if not db.learnedRanks[key][l] then db.learnedRanks[key][l] = name; changed = true end
    end
  end
  if changed and not learnQueued then
    learnQueued = true
    local function go() learnQueued = false; ns.RebuildReference() end
    if C_Timer and C_Timer.After then C_Timer.After(1, go) else go() end
  end
end

-- Categories an item already counts toward.
function ns.CategoriesFor(name)
  local out = {}
  for key in pairs(ns.ref.categories) do if ns.MatchCategory(key, name) then out[#out + 1] = key end end
  table.sort(out, function(a, b) return lower(ns.ref.categories[a].name) < lower(ns.ref.categories[b].name) end)
  return out
end

-- Sorted list of category keys (by display name).
function ns.CategoryKeys()
  local keys = {}
  for k in pairs(ns.ref.categories) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return lower(ns.ref.categories[a].name) < lower(ns.ref.categories[b].name) end)
  return keys
end

-- Find a category by (partial) display name or key.
function ns.FindCategory(text)
  if not text then return nil end
  if ns.ref.categories[text] then return text end
  local l = lower(text)
  for k, c in pairs(ns.ref.categories) do if lower(c.name) == l then return k end end
  for k, c in pairs(ns.ref.categories) do if lower(c.name):find(l, 1, true) then return k end end
  return nil
end
