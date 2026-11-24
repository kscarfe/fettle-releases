-- Fettle: shipped default reference list.
--
-- Everything here can be changed in-game (Reference tab). Your edits are stored
-- separately in SavedVariables and applied on top of these defaults, so updating
-- the addon never wipes them.
--
-- Matching is by item NAME (English client), so it keeps working even where
-- WoW Forever uses different item IDs from Classic. A category counts any item
-- whose name is one of its ranks, or matches one of its Lua patterns.
--
--   ranks:    { n = item name, lvl = required level (nil = unknown, counted but
--               never suggested), src = where it comes from, skill = {prof, lvl} }
--   patterns: Lua patterns, matched case-insensitively against item names.
--
-- Level numbers marked "~" in notes are best guesses from Classic data.
local _, ns = ...

local function R(n, lvl, src, skill) return { n = n, lvl = lvl, src = src, skill = skill } end

local C = {}

---------------------------------------------------------------------------
-- Recovery
---------------------------------------------------------------------------
C.HEALTH_POTION = {
  name = "Healing potion",
  note = "In Forever, healing potions are made with First Aid. Alchemy makes the Discolored line.",
  ranks = {
    R("Minor Healing Potion", 1, "First Aid"),
    R("Lesser Healing Potion", 3, "First Aid"),
    R("Healing Potion", 12, "First Aid"),
    R("Greater Healing Potion", 21, "First Aid"),
    R("Superior Healing Potion", 35, "First Aid"),
    R("Major Healing Potion", 45, "First Aid"),
  },
  patterns = { "healing potion$", "healthstone$" },
}

C.MANA_POTION = {
  name = "Mana potion",
  ranks = {
    R("Minor Mana Potion", 5, "Alchemy"),
    R("Lesser Mana Potion", 14, "Alchemy"),
    R("Mana Potion", 22, "Alchemy"),
    R("Greater Mana Potion", 31, "Alchemy"),
    R("Superior Mana Potion", 41, "Alchemy"),
    R("Major Mana Potion", 49, "Alchemy"),
  },
  patterns = { "mana potion$" },
}

C.BANDAGE = {
  name = "Bandage",
  note = "Rank suggestion uses your First Aid skill.",
  ranks = {
    R("Linen Bandage", 1, "First Aid", { "First Aid", 1 }),
    R("Heavy Linen Bandage", 1, "First Aid", { "First Aid", 40 }),
    R("Wool Bandage", 1, "First Aid", { "First Aid", 80 }),
    R("Heavy Wool Bandage", 1, "First Aid", { "First Aid", 115 }),
    R("Silk Bandage", 1, "First Aid", { "First Aid", 150 }),
    R("Heavy Silk Bandage", 1, "First Aid", { "First Aid", 180 }),
    R("Mageweave Bandage", 1, "First Aid", { "First Aid", 210 }),
    R("Heavy Mageweave Bandage", 1, "First Aid", { "First Aid", 240 }),
    R("Runecloth Bandage", 1, "First Aid", { "First Aid", 260 }),
    R("Heavy Runecloth Bandage", 1, "First Aid", { "First Aid", 290 }),
  },
  patterns = { "bandage$" },
}

C.ANTIVENOM = {
  name = "Anti-venom",
  ranks = {
    R("Anti-Venom", 1, "First Aid", { "First Aid", 80 }),
    R("Strong Anti-Venom", 1, "First Aid", { "First Aid", 130 }),
    R("Powerful Anti-Venom", 1, "First Aid", { "First Aid", 300 }),
  },
  patterns = { "anti%-venom$" },
}

C.DRINK = {
  name = "Drink (water)",
  ranks = {
    R("Refreshing Spring Water", 1, "Vendor"),
    R("Conjured Water", 1, "Mage"),
    R("Ice Cold Milk", 5, "Vendor"),
    R("Conjured Fresh Water", 5, "Mage"),
    R("Melon Juice", 15, "Vendor"),
    R("Conjured Purified Water", 15, "Mage"),
    R("Sweet Nectar", 25, "Vendor"),
    R("Conjured Spring Water", 25, "Mage"),
    R("Moonberry Juice", 35, "Vendor"),
    R("Conjured Mineral Water", 35, "Mage"),
    R("Morning Glory Dew", 45, "Vendor"),
    R("Conjured Sparkling Water", 45, "Mage"),
    R("Conjured Crystal Water", 55, "Mage"),
  },
  patterns = {},
}

C.FOOD = {
  name = "Food (health regen)",
  ranks = {
    R("Tough Hunk of Bread", 1, "Vendor"), R("Tough Jerky", 1, "Vendor"), R("Darnassian Bleu", 1, "Vendor"),
    R("Shiny Red Apple", 1, "Vendor"), R("Forest Mushroom Cap", 1, "Vendor"), R("Slitherskin Mackerel", 1, "Vendor"),
    R("Conjured Muffin", 1, "Mage"),
    R("Freshly Baked Bread", 5, "Vendor"), R("Haunch of Meat", 5, "Vendor"), R("Dalaran Sharp", 5, "Vendor"),
    R("Tel'Abim Banana", 5, "Vendor"), R("Red-speckled Mushroom", 5, "Vendor"), R("Longjaw Mud Snapper", 5, "Vendor"),
    R("Conjured Bread", 5, "Mage"),
    R("Moist Cornbread", 15, "Vendor"), R("Mutton Chop", 15, "Vendor"), R("Dwarven Mild", 15, "Vendor"),
    R("Snapvine Watermelon", 15, "Vendor"), R("Spongy Morel", 15, "Vendor"), R("Bristle Whisker Catfish", 15, "Vendor"),
    R("Conjured Rye", 15, "Mage"),
    R("Mulgore Spice Bread", 25, "Vendor"), R("Wild Hog Shank", 25, "Vendor"), R("Stormwind Brie", 25, "Vendor"),
    R("Goldenbark Apple", 25, "Vendor"), R("Delicious Cave Mold", 25, "Vendor"), R("Rockscale Cod", 25, "Vendor"),
    R("Conjured Pumpernickel", 25, "Mage"),
    R("Soft Banana Bread", 35, "Vendor"), R("Cured Ham Steak", 35, "Vendor"), R("Fine Aged Cheddar", 35, "Vendor"),
    R("Moon Harvest Pumpkin", 35, "Vendor"), R("Raw Black Truffle", 35, "Vendor"), R("Striped Yellowtail", 35, "Vendor"),
    R("Conjured Sourdough", 35, "Mage"),
    R("Homemade Cherry Pie", 45, "Vendor"), R("Roasted Quail", 45, "Vendor"), R("Alterac Swiss", 45, "Vendor"),
    R("Deep Fried Plantains", 45, "Vendor"), R("Dried King Bolete", 45, "Vendor"), R("Spinefin Halibut", 45, "Vendor"),
    R("Conjured Sweet Roll", 45, "Mage"), R("Conjured Cinnamon Roll", 55, "Mage"),
  },
  patterns = {},
}

C.STAT_FOOD = {
  name = "Stat food (Well Fed)",
  note = "Forever reworked crafted food; levels ~Classic. Add new Forever foods in-game.",
  ranks = {
    R("Herb Baked Egg", 1, "Cooking"), R("Spiced Wolf Meat", 1, "Cooking"),
    R("Beer Basted Boar Ribs", 5, "Cooking"), R("Goretusk Liver Pie", 5, "Cooking"),
    R("Crocolisk Steak", 15, "Cooking"), R("Seasoned Wolf Kabob", 15, "Cooking"),
    R("Hot Lion Chops", 25, "Cooking"), R("Roast Raptor", 25, "Cooking"), R("Spider Sausage", 25, "Cooking"),
    R("Cookie's Feast", nil, "Cooking (camp, Forever)"),
    R("Monster Omelet", 35, "Cooking"), R("Tender Wolf Steak", 35, "Cooking"),
    R("Runn Tum Tuber Surprise", 45, "Cooking"), R("Grilled Squid", 45, "Cooking"),
    R("Nightfin Soup", 45, "Cooking"), R("Smoked Desert Dumplings", 45, "Cooking"),
    R("Dirge's Kickin' Chimaerok Chops", 55, "Cooking"),
  },
  patterns = {},
}

---------------------------------------------------------------------------
-- Elixirs (Forever names without known levels are counted, never suggested)
---------------------------------------------------------------------------
C.TANK_ELIXIR = {
  name = "Elixir: armor / stamina",
  ranks = {
    R("Elixir of Minor Defense", 1, "Alchemy"), R("Elixir of Minor Fortitude", 2, "Alchemy"),
    R("Elixir of Defense", 16, "Alchemy"), R("Elixir of Fortitude", 25, "Alchemy"),
    R("Elixir of Greater Defense", 29, "Alchemy"), R("Elixir of Superior Defense", 43, "Alchemy"),
    R("Elixir of Greater Fortitude", nil, "Alchemy (Forever)"), R("Elixir of the Phalanx", nil, "Alchemy (Forever)"),
    R("Elixir of the Whale", nil, "Alchemy (Forever)"), R("Elixir of the Grizzly", nil, "Alchemy (Forever)"),
  },
  patterns = {},
}

C.STR_ELIXIR = {
  name = "Elixir: strength",
  ranks = {
    R("Elixir of Lion's Strength", 1, "Alchemy"), R("Elixir of Ogre's Strength", 20, "Alchemy"),
    R("Elixir of Giants", 38, "Alchemy"), R("Elixir of Ferocity", nil, "Alchemy (Forever)"),
  },
  patterns = {},
}

C.AGI_ELIXIR = {
  name = "Elixir: agility",
  ranks = {
    R("Elixir of Minor Agility", 2, "Alchemy"), R("Elixir of Lesser Agility", 18, "Alchemy"),
    R("Elixir of Agility", 27, "Alchemy"), R("Elixir of Greater Agility", 38, "Alchemy"),
    R("Elixir of the Mongoose", 46, "Alchemy"), R("Elixir of Cunning", nil, "Alchemy (Forever)"),
  },
  patterns = {},
}

C.CASTER_ELIXIR = {
  name = "Elixir: spell power / intellect",
  ranks = {
    R("Minor Arcane Elixir", 1, "Alchemy (Forever)"), R("Lesser Arcane Elixir", nil, "Alchemy (Forever)"),
    R("Elixir of Wisdom", 15, "Alchemy"), R("Elixir of Lesser Intellect", nil, "Alchemy (Forever)"),
    R("Arcane Elixir", 37, "Alchemy"), R("Elixir of Greater Intellect", 37, "Alchemy"),
    R("Greater Arcane Elixir", 47, "Alchemy"), R("Elixir of Sages", nil, "Alchemy (Forever)"),
    R("Elixir of the Owl", nil, "Alchemy (Forever)"), R("Elixir of Nature Power", nil, "Alchemy (Forever)"),
  },
  patterns = {},
}

C.HEALER_ELIXIR = {
  name = "Elixir: healing / mana regen",
  ranks = {
    R("Elixir of Wisdom", 15, "Alchemy"), R("Lesser Cleric's Elixir", nil, "Alchemy (Forever)"),
    R("Lesser Mageblood Elixir", nil, "Alchemy (Forever)"), R("Elixir of Lesser Spirit", nil, "Alchemy (Forever)"),
    R("Mageblood Elixir", 40, "Alchemy"), R("Greater Cleric's Elixir", nil, "Alchemy (Forever)"),
    R("Greater Mageblood Elixir", nil, "Alchemy (Forever)"), R("Elixir of Greater Spirit", nil, "Alchemy (Forever)"),
  },
  patterns = {},
}

---------------------------------------------------------------------------
-- Weapon and armor enhancements
---------------------------------------------------------------------------
C.WEAPON_STONE = {
  name = "Sharpening stone / weightstone",
  note = "Sharpening stones for blades, weightstones for blunt weapons.",
  ranks = {
    R("Rough Sharpening Stone", 1, "Blacksmithing"), R("Rough Weightstone", 1, "Blacksmithing"),
    R("Coarse Sharpening Stone", 5, "Blacksmithing"), R("Coarse Weightstone", 5, "Blacksmithing"),
    R("Heavy Sharpening Stone", 15, "Blacksmithing"), R("Heavy Weightstone", 15, "Blacksmithing"),
    R("Solid Sharpening Stone", 25, "Blacksmithing"), R("Solid Weightstone", 25, "Blacksmithing"),
    R("Dense Sharpening Stone", 35, "Blacksmithing"), R("Dense Weightstone", 35, "Blacksmithing"),
    R("Elemental Sharpening Stone", 50, "Blacksmithing"),
  },
  patterns = { "sharpening stone$", "weightstone$" },
}

C.WIZARD_OIL = {
  name = "Wizard oil",
  note = "Levels ~Classic.",
  ranks = {
    R("Minor Wizard Oil", 5, "Enchanting"), R("Lesser Wizard Oil", 15, "Enchanting"),
    R("Wizard Oil", 30, "Enchanting"), R("Brilliant Wizard Oil", 45, "Enchanting"),
  },
  patterns = { "wizard oil$" },
}

C.MANA_OIL = {
  name = "Mana oil",
  note = "Levels ~Classic.",
  ranks = {
    R("Minor Mana Oil", 20, "Enchanting"), R("Lesser Mana Oil", 30, "Enchanting"), R("Brilliant Mana Oil", 45, "Enchanting"),
  },
  patterns = { "mana oil$" },
}

C.ARMOR_KIT = {
  name = "Armor kit",
  note = "Levels ~Classic.",
  ranks = {
    R("Light Armor Kit", 1, "Leatherworking"), R("Medium Armor Kit", 5, "Leatherworking"),
    R("Heavy Armor Kit", 15, "Leatherworking"), R("Thick Armor Kit", 25, "Leatherworking"),
    R("Rugged Armor Kit", 35, "Leatherworking"),
  },
  patterns = { "armor kit$" },
}

C.EXPLOSIVE = {
  name = "Bombs / grenades",
  ranks = {
    R("Rough Copper Bomb", 1, "Engineering"), R("Rough Dynamite", 1, "Engineering"),
    R("Coarse Dynamite", 1, "Engineering"), R("Small Bronze Bomb", 1, "Engineering"),
    R("Big Bronze Bomb", 1, "Engineering"), R("Iron Grenade", 1, "Engineering"),
    R("Big Iron Bomb", 1, "Engineering"), R("Solid Dynamite", 1, "Engineering"),
    R("Thorium Grenade", 1, "Engineering"), R("Dense Dynamite", 1, "Engineering"),
  },
  patterns = { "bomb$", "grenade$", "dynamite$" },
}

---------------------------------------------------------------------------
-- Camping (Forever). Assumes the crafted item has the same name as the camp
-- object. If an item turns out to be named differently, fix it in-game.
---------------------------------------------------------------------------
local function Camp(prof, t1, t2, t3)
  return { name = "Camp feature: " .. prof, note = "One per player per camp. Shares a 1 hour cooldown.",
           ranks = { R(t1, 1, prof .. " 20"), R(t2, 1, prof .. " 140"), R(t3, 1, prof .. " 300") }, patterns = {} }
end
C.CAMP_ALCHEMY = Camp("Alchemy", "Mana Well", "Fermenter", "Alchemy Laboratory")
C.CAMP_BLACKSMITHING = Camp("Blacksmithing", "Sharpening Wheel", "Anvil", "Master Forge")
C.CAMP_ENCHANTING = Camp("Enchanting", "Enchanted Lute", "Arcane Salvager", "Arcane Forge")
C.CAMP_ENGINEERING = Camp("Engineering", "Reagent Bot", "Repair Bot", "Anarchist's Workbench")
C.CAMP_FIRSTAID = Camp("First Aid", "First Aid Kit", "Toxin Study", "Plague Doctor's Laboratory")
C.CAMP_FISHING = Camp("Fishing", "Fish Bowl", "Fishing Rack", "Fishing Hut")
C.CAMP_HERBALISM = Camp("Herbalism", "Incense Candle", "Greenhouse", "Seed Hybridizer")
C.CAMP_LEATHERWORKING = Camp("Leatherworking", "Camp Tent", "Tanning Rack", "Sewing Machine")
C.CAMP_MINING = Camp("Mining", "Lodestone", "Rock Garden", "Molten Foundry")
C.CAMP_SKINNING = Camp("Skinning", "Camp Chair", "Field Guide", "Trapper's Workbench")
C.CAMP_TAILORING = Camp("Tailoring", "Faction Banner", "Spinning Wheel", "Loom")
C.CAMPFIRE = {
  name = "Campfire kit / wood",
  note = "Basic Campfire uses Simple Wood; Journeyman uses Star Wood; Expert uses Thick Logs.",
  ranks = { R("Basic Campfire Kit", 1, "Cooking 1"), R("Journeyman Campfire Kit", 1, "Cooking 90"),
            R("Expert Campfire Kit", 1, "Cooking 220"), R("Simple Wood", 1, "Vendor"),
            R("Star Wood", 1, "Vendor"), R("Thick Logs", 1, "Vendor") },
  patterns = {},
}
C.FLINT = { name = "Flint and Tinder", ranks = { R("Flint and Tinder", 1, "Trade supplies vendor") }, patterns = {} }

---------------------------------------------------------------------------
-- Class reagents and supplies (levels ~Classic)
---------------------------------------------------------------------------
C.AMMO = {
  name = "Ammunition",
  ranks = {
    R("Rough Arrow", 1, "Vendor"), R("Light Shot", 1, "Vendor"),
    R("Sharp Arrow", 10, "Vendor"), R("Heavy Shot", 10, "Vendor"),
    R("Razor Arrow", 25, "Vendor"), R("Solid Shot", 25, "Vendor"),
    R("Jagged Arrow", 40, "Vendor"), R("Accurate Slugs", 40, "Vendor"),
  },
  patterns = { "arrow$", " shot$", "slugs$" },
}
C.INSTANT_POISON = { name = "Instant Poison", ranks = { R("Instant Poison", 20, "Rogue (Poisons)") }, patterns = { "^instant poison" } }
C.DEADLY_POISON = { name = "Deadly Poison", ranks = { R("Deadly Poison", 30, "Rogue (Poisons)") }, patterns = { "^deadly poison" } }
C.CRIPPLING_POISON = { name = "Crippling Poison", ranks = { R("Crippling Poison", 20, "Rogue (Poisons)") }, patterns = { "^crippling poison" } }
C.FLASH_POWDER = { name = "Flash Powder", ranks = { R("Flash Powder", 22, "Reagent vendor") }, patterns = {} }
C.BLINDING_POWDER = { name = "Blinding Powder", ranks = { R("Blinding Powder", 34, "Rogue (Poisons)") }, patterns = {} }
C.SYMBOL_DIVINITY = { name = "Symbol of Divinity", ranks = { R("Symbol of Divinity", 30, "Reagent vendor") }, patterns = {} }
C.SYMBOL_KINGS = { name = "Symbol of Kings", ranks = { R("Symbol of Kings", 52, "Reagent vendor") }, patterns = {} }
C.LIGHT_FEATHER = { name = "Light Feather", ranks = { R("Light Feather", 12, "Reagent vendor") }, patterns = {} }
C.CANDLE = { name = "Prayer candle", ranks = { R("Holy Candle", 48, "Reagent vendor"), R("Sacred Candle", 56, "Reagent vendor") }, patterns = {} }
C.ANKH = { name = "Ankh", ranks = { R("Ankh", 30, "Reagent vendor") }, patterns = {} }
C.RUNE_TELEPORT = { name = "Rune of Teleportation", ranks = { R("Rune of Teleportation", 20, "Reagent vendor") }, patterns = {} }
C.RUNE_PORTALS = { name = "Rune of Portals", ranks = { R("Rune of Portals", 40, "Reagent vendor") }, patterns = {} }
C.ARCANE_POWDER = { name = "Arcane Powder", ranks = { R("Arcane Powder", 56, "Reagent vendor") }, patterns = {} }
C.SOUL_SHARD = { name = "Soul Shard", ranks = { R("Soul Shard", 10, "Drain Soul") }, patterns = {} }
C.REBIRTH_SEED = {
  name = "Rebirth seed",
  ranks = { R("Maple Seed", 20, "Reagent vendor"), R("Stranglethorn Seed", 30, "Reagent vendor"),
            R("Ashwood Seed", 40, "Reagent vendor"), R("Hornbeam Seed", 50, "Reagent vendor"),
            R("Ironwood Seed", 60, "Reagent vendor") },
  patterns = {},
}
C.WILD_BERRIES = { name = "Gift of the Wild reagent", ranks = { R("Wild Berries", 50, "Reagent vendor"), R("Wild Thornroot", 60, "Reagent vendor") }, patterns = {} }

---------------------------------------------------------------------------
-- Starter kits. When an alt is first seen (or you press "Reset to starter"),
-- every rule below that fits its class and role is copied into that alt's own
-- kit. After that the kit belongs to the alt: edit it on its Checklist tab.
-- prof and minLevel stay attached to the copied line, so it switches on by
-- itself when the alt learns the profession or reaches the level.
--   qty:      per role (TANK/HEALER/MELEE/RANGED/CASTER) or ALL
--   roles:    only these roles (nil = all)
--   classes:  only these classes (class file tokens, nil = all)
--   mana:     true = only mana users
--   prof:     only alts with this profession (any skill)
--   minLevel: only from this level
--   optional: shown, but never counts as "missing"
---------------------------------------------------------------------------
local N = {
  { id = "hp", cat = "HEALTH_POTION", qty = { TANK = 5, HEALER = 3, MELEE = 5, RANGED = 3, CASTER = 3 } },
  { id = "mp", cat = "MANA_POTION", mana = true, minLevel = 5, qty = { TANK = 4, HEALER = 10, MELEE = 3, RANGED = 3, CASTER = 6 } },
  { id = "bandage", cat = "BANDAGE", prof = "First Aid", qty = { ALL = 10, HEALER = 5 } },
  { id = "antivenom", cat = "ANTIVENOM", prof = "First Aid", optional = true, qty = { ALL = 3 } },
  { id = "drink", cat = "DRINK", mana = true, qty = { TANK = 20, HEALER = 40, MELEE = 20, RANGED = 20, CASTER = 30 } },
  { id = "food", cat = "FOOD", qty = { ALL = 20 } },
  { id = "statfood", cat = "STAT_FOOD", qty = { ALL = 5 } },

  { id = "el_tank", cat = "TANK_ELIXIR", roles = { "TANK" }, qty = { ALL = 2 } },
  { id = "el_str", cat = "STR_ELIXIR", roles = { "TANK", "MELEE" }, classes = { "WARRIOR", "PALADIN", "SHAMAN" }, qty = { ALL = 2 } },
  { id = "el_agi", cat = "AGI_ELIXIR", roles = { "TANK", "MELEE", "RANGED" }, classes = { "ROGUE", "HUNTER", "DRUID" }, qty = { ALL = 2 } },
  { id = "el_caster", cat = "CASTER_ELIXIR", roles = { "CASTER" }, qty = { ALL = 2 } },
  { id = "el_healer", cat = "HEALER_ELIXIR", roles = { "HEALER" }, qty = { ALL = 2 } },

  { id = "stone", cat = "WEAPON_STONE", roles = { "TANK", "MELEE" }, classes = { "WARRIOR", "PALADIN", "ROGUE" }, qty = { ALL = 3 } },
  { id = "wizoil", cat = "WIZARD_OIL", roles = { "CASTER" }, minLevel = 5, qty = { ALL = 1 } },
  { id = "manaoil", cat = "MANA_OIL", roles = { "HEALER" }, minLevel = 20, qty = { ALL = 1 } },
  { id = "armorkit", cat = "ARMOR_KIT", optional = true, qty = { ALL = 1, TANK = 2 } },
  { id = "explosive", cat = "EXPLOSIVE", prof = "Engineering", optional = true, qty = { ALL = 5 } },

  { id = "camp_alch", cat = "CAMP_ALCHEMY", prof = "Alchemy", optional = true, qty = { ALL = 1 } },
  { id = "camp_bs", cat = "CAMP_BLACKSMITHING", prof = "Blacksmithing", optional = true, qty = { ALL = 1 } },
  { id = "camp_ench", cat = "CAMP_ENCHANTING", prof = "Enchanting", optional = true, qty = { ALL = 1 } },
  { id = "camp_eng", cat = "CAMP_ENGINEERING", prof = "Engineering", optional = true, qty = { ALL = 1 } },
  { id = "camp_fa", cat = "CAMP_FIRSTAID", prof = "First Aid", optional = true, qty = { ALL = 1 } },
  { id = "camp_fish", cat = "CAMP_FISHING", prof = "Fishing", optional = true, qty = { ALL = 1 } },
  { id = "camp_herb", cat = "CAMP_HERBALISM", prof = "Herbalism", optional = true, qty = { ALL = 1 } },
  { id = "camp_lw", cat = "CAMP_LEATHERWORKING", prof = "Leatherworking", optional = true, qty = { ALL = 1 } },
  { id = "camp_mine", cat = "CAMP_MINING", prof = "Mining", optional = true, qty = { ALL = 1 } },
  { id = "camp_skin", cat = "CAMP_SKINNING", prof = "Skinning", optional = true, qty = { ALL = 1 } },
  { id = "camp_tail", cat = "CAMP_TAILORING", prof = "Tailoring", optional = true, qty = { ALL = 1 } },
  { id = "campfire", cat = "CAMPFIRE", prof = "Cooking", qty = { ALL = 1 } },
  { id = "flint", cat = "FLINT", prof = "Cooking", qty = { ALL = 1 } },

  { id = "ammo", cat = "AMMO", classes = { "HUNTER" }, qty = { ALL = 1000 } },
  { id = "instant", cat = "INSTANT_POISON", classes = { "ROGUE" }, minLevel = 20, qty = { ALL = 10 } },
  { id = "deadly", cat = "DEADLY_POISON", classes = { "ROGUE" }, minLevel = 30, optional = true, qty = { ALL = 10 } },
  { id = "crippling", cat = "CRIPPLING_POISON", classes = { "ROGUE" }, minLevel = 20, optional = true, qty = { ALL = 5 } },
  { id = "flash", cat = "FLASH_POWDER", classes = { "ROGUE" }, minLevel = 22, qty = { ALL = 5 } },
  { id = "blinding", cat = "BLINDING_POWDER", classes = { "ROGUE" }, minLevel = 34, optional = true, qty = { ALL = 5 } },
  { id = "divinity", cat = "SYMBOL_DIVINITY", classes = { "PALADIN" }, minLevel = 30, optional = true, qty = { ALL = 2 } },
  { id = "kings", cat = "SYMBOL_KINGS", classes = { "PALADIN" }, minLevel = 52, qty = { ALL = 40 } },
  { id = "feather_p", cat = "LIGHT_FEATHER", classes = { "PRIEST" }, minLevel = 34, optional = true, qty = { ALL = 10 } },
  { id = "feather_m", cat = "LIGHT_FEATHER", classes = { "MAGE" }, minLevel = 12, optional = true, qty = { ALL = 10 } },
  { id = "candle", cat = "CANDLE", classes = { "PRIEST" }, minLevel = 48, qty = { ALL = 20 } },
  { id = "ankh", cat = "ANKH", classes = { "SHAMAN" }, minLevel = 30, qty = { ALL = 3 } },
  { id = "rune_tp", cat = "RUNE_TELEPORT", classes = { "MAGE" }, minLevel = 20, optional = true, qty = { ALL = 2 } },
  { id = "rune_portal", cat = "RUNE_PORTALS", classes = { "MAGE" }, minLevel = 40, optional = true, qty = { ALL = 2 } },
  { id = "arcpowder", cat = "ARCANE_POWDER", classes = { "MAGE" }, minLevel = 56, qty = { ALL = 20 } },
  { id = "shard", cat = "SOUL_SHARD", classes = { "WARLOCK" }, minLevel = 10, qty = { ALL = 5 } },
  { id = "seed", cat = "REBIRTH_SEED", classes = { "DRUID" }, minLevel = 20, qty = { ALL = 2 } },
  { id = "berries", cat = "WILD_BERRIES", classes = { "DRUID" }, minLevel = 50, qty = { ALL = 20 } },
}

---------------------------------------------------------------------------
-- Prep tasks shared by every alt.
--   auto = "durability", "freeslots", "campbuff" (checked automatically)
--   other tasks are ticked by hand and cleared on a new run
---------------------------------------------------------------------------
local T = {
  { id = "repair", text = "Gear repaired", auto = "durability" },
  { id = "bags", text = "Free bag space", auto = "freeslots" },
  { id = "camp", text = "Camp Benefits buff", auto = "campbuff" },
  { id = "quests", text = "Dungeon quests picked up" },
}

---------------------------------------------------------------------------
-- Material families for profession mains: trade goods subclass -> the
-- professions that collect it, in priority order (first one with a main wins).
-- A main also always gets the reagents of recipes it has learned.
---------------------------------------------------------------------------
local F = {
  [1] = { "Engineering" },                                 -- parts
  [2] = { "Engineering" },                                 -- explosives
  [3] = { "Engineering" },                                 -- devices
  [5] = { "Tailoring" },                                   -- cloth (alts keep a First Aid reserve)
  [6] = { "Leatherworking" },                              -- leather
  [7] = { "Blacksmithing", "Engineering", "Mining" },      -- metal and stone
  [8] = { "Cooking" },                                     -- meat, fish, eggs, spices
  [9] = { "Alchemy", "First Aid" },                        -- herbs
  [12] = { "Enchanting" },                                 -- dusts, essences, shards
}

-- Cloth an alt keeps to level First Aid (skill brackets, 2 cloth per point).
local FA = {
  { upTo = 80, cloth = "Linen Cloth" }, { upTo = 150, cloth = "Wool Cloth" }, { upTo = 210, cloth = "Silk Cloth" },
  { upTo = 260, cloth = "Mageweave Cloth" }, { upTo = 300, cloth = "Runecloth" },
}

ns.Defaults = { categories = C, starters = N, tasks = T, families = F, firstAidCloth = FA }
