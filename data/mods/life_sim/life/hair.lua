-- Hair and beard growth: cosmetic traits grow into longer ones as days pass,
-- and haircuts or shaves (detected through their morale) reset the clock.

local store = require("./store")

local hair = {}

---@class LifeSimGrowthStep
---@field next string Trait id grown into ("" means no trait).
---@field days integer Days the current look lasts before growing out.

--- Hair style growth chain. Styles not listed (e.g. bald) never grow.
---@type table<string, LifeSimGrowthStep>
hair.HAIR_GROWTH = {
  hair_crewcut = { next = "hair_short", days = 30 },
  hair_mohawk = { next = "hair_short", days = 30 },
  hair_cropped = { next = "hair_short", days = 30 },
  hair_short = { next = "hair_medium", days = 60 },
  hair_parted = { next = "hair_medium", days = 60 },
  hair_swept = { next = "hair_medium", days = 60 },
  hair_treated = { next = "hair_medium", days = 60 },
  hair_medium = { next = "hair_long", days = 120 },
  hair_long = { next = "hair_overflowing", days = 180 },
  hair_ponytail = { next = "hair_overflowing", days = 180 },
  hair_fro = { next = "hair_overflowing", days = 150 },
}

--- Facial hair that grows in naturally, in order. Shaving removes these entirely.
hair.NATURAL_BEARD = {
  [""] = { next = "FACIAL_HAIR_3DAYSTUBBLE", days = 3 },
  FACIAL_HAIR_3DAYSTUBBLE = { next = "FACIAL_HAIR_JAW_SCRUFF", days = 7 },
  FACIAL_HAIR_JAW_SCRUFF = { next = "FACIAL_HAIR_BEARD", days = 21 },
  FACIAL_HAIR_BEARD = { next = "FACIAL_HAIR_WIZENED", days = 180 },
}

--- Any groomed facial hair style left untended grows into a full beard.
---@type LifeSimGrowthStep
hair.STYLED_BEARD = { next = "FACIAL_HAIR_BEARD", days = 45 }

local morale_haircut = MoraleTypeDataId.new("morale_haircut")
local morale_shave = MoraleTypeDataId.new("morale_shave")

---@class LifeSimGrowthQuery
---@field current string Current trait id ("" for none).
---@field elapsed_days number Days since the current look was established or last groomed.
---@field chain table<string, LifeSimGrowthStep>
---@field fallback LifeSimGrowthStep? Step used when `current` is not in `chain`.

--- Next trait to grow into, if it's time. Pure: does not touch the game.
---@param opts LifeSimGrowthQuery
---@return string?
hair.next_growth = function(opts)
  local step = opts.chain[opts.current] or (opts.current ~= "" and opts.fallback or nil)
  if not step or step.next == opts.current then return nil end
  if opts.elapsed_days < step.days then return nil end
  return step.next
end

--- Current trait of the given mutation type, or "".
---@param who Character
---@param type_name string
---@return string
local function current_trait(who, type_name)
  for _, mut_id in pairs(who:get_mutations(true)) do
    for _, t in pairs(mut_id:obj():mutation_types()) do
      if t == type_name then return mut_id:str() end
    end
  end
  return ""
end

---@param who Character
---@param from string
---@param to string
local function swap_trait(who, from, to)
  if from ~= "" then who:remove_mutation(MutationBranchId.new(from), true) end
  if to ~= "" then who:set_mutation(MutationBranchId.new(to)) end
end

---@param id string
---@return string
local function trait_name(id)
  if id == "" then return locale.gettext("clean-shaven") end
  -- Cosmetic trait names read "Hair style: long"; keep only the look itself.
  local name = MutationBranchId.new(id):obj():name()
  return name:match(":%s*(.+)$") or name
end

---@class LifeSimGrowthTrack
---@field key string Store key prefix.
---@field type_name string Mutation type tracked.
---@field groom_morale MoraleTypeDataId Morale that signals grooming.
---@field chain table<string, LifeSimGrowthStep>
---@field fallback LifeSimGrowthStep?
---@field on_groom (fun(who: Character, current: string): string)? Returns the look after grooming.
---@field grown_message string

--- Tracks one growing feature on `who`, returning the trait it grew into, if any.
---@param who Character
---@param track LifeSimGrowthTrack
---@return string?
local function update_track(who, track)
  local now = store.now()
  local current = current_trait(who, track.type_name)
  -- Clamp so a timestamp from the future (e.g. after the calendar was rewound) can't stall growth.
  local since = math.min(store.get_num(who, track.key .. "_since", now), now)

  -- A new look (picked in a menu, mutated, etc.) restarts growth.
  if store.get_str(who, track.key .. "_look") ~= current then since = now end

  -- Grooming morale lingers for hours; only count it once per hour of growth.
  if who:has_morale(track.groom_morale) and now - since >= 3600 then
    since = now
    if track.on_groom then
      local groomed = track.on_groom(who, current)
      if groomed ~= current then
        swap_trait(who, current, groomed)
        current = groomed
      end
    end
  end

  local grown = hair.next_growth({
    current = current,
    elapsed_days = (now - since) / 86400,
    chain = track.chain,
    fallback = track.fallback,
  })
  if grown then
    swap_trait(who, current, grown)
    current = grown
    since = now
    if who:is_avatar() then gapi.add_msg(MsgType.info, string.format(track.grown_message, trait_name(grown))) end
  end

  store.set_str(who, track.key .. "_look", current)
  store.set_num(who, track.key .. "_since", since)
  return grown
end

---@type LifeSimGrowthTrack
local hair_track = {
  key = "hair",
  type_name = "hair_style",
  groom_morale = morale_haircut,
  chain = hair.HAIR_GROWTH,
  grown_message = locale.gettext("Your hair has grown out.  It's now %s."),
}

---@type LifeSimGrowthTrack
local beard_track = {
  key = "beard",
  type_name = "facial_hair",
  groom_morale = morale_shave,
  chain = hair.NATURAL_BEARD,
  fallback = hair.STYLED_BEARD,
  on_groom = function(_who, current) return hair.NATURAL_BEARD[current] and "" or current end,
  grown_message = locale.gettext("Your facial hair has grown in: %s."),
}

--- Grows hair (and, for men, facial hair) on `who` up to the current turn.
---@param who Character
hair.update = function(who)
  update_track(who, hair_track)
  if who.male then update_track(who, beard_track) end
end

--- Short description for the status screen.
---@param who Character
---@return string[]
hair.describe = function(who)
  local now = store.now()
  local lines = {}
  local hair_days = math.floor((now - store.get_num(who, "hair_since", now)) / 86400)
  table.insert(
    lines,
    string.format(
      locale.gettext("Hair: %s (%d days since last cut)"),
      trait_name(current_trait(who, "hair_style")),
      hair_days
    )
  )
  if who.male then
    local beard_days = math.floor((now - store.get_num(who, "beard_since", now)) / 86400)
    table.insert(
      lines,
      string.format(
        locale.gettext("Facial hair: %s (%d days since last shave)"),
        trait_name(current_trait(who, "facial_hair")),
        beard_days
      )
    )
  end
  return lines
end

return hair
