---@class LifeSimTestData
---@field stage_values integer[]
---@field step_ml number
---@field step_pending number
---@field clamped_ml number
---@field sleeping_ml number
---@field stored_ml number
---@field stored_pending number
---@field beard_none_early string?
---@field beard_none_due string?
---@field beard_styled_due string?
---@field bald_growth string?
---@field update_hair fun()

local bladder = require("../../data/mods/life_sim/life/bladder")
local hair = require("../../data/mods/life_sim/life/hair")

---@type LifeSimTestData
local data = test_data

data.stage_values = {
  bladder.stage_for(0),
  bladder.stage_for(249),
  bladder.stage_for(250),
  bladder.stage_for(450),
  bladder.stage_for(599),
}

local stepped =
  bladder.step({ state = { ml = 0, pending = 0 }, elapsed_hours = 1, thirst_drop = 100, sleeping = false })
data.step_ml = stepped.ml
data.step_pending = stepped.pending

data.clamped_ml =
  bladder.step({ state = { ml = 0, pending = 0 }, elapsed_hours = 100, thirst_drop = 0, sleeping = false }).ml
data.sleeping_ml =
  bladder.step({ state = { ml = 0, pending = 0 }, elapsed_hours = 2, thirst_drop = 0, sleeping = true }).ml

local avatar = gapi.get_avatar()
bladder.set_state(avatar, { ml = 321.7, pending = 12 })
local stored = bladder.get_state(avatar)
data.stored_ml = stored.ml
data.stored_pending = stored.pending

data.beard_none_early =
  hair.next_growth({ current = "", elapsed_days = 2, chain = hair.NATURAL_BEARD, fallback = hair.STYLED_BEARD })
data.beard_none_due =
  hair.next_growth({ current = "", elapsed_days = 3, chain = hair.NATURAL_BEARD, fallback = hair.STYLED_BEARD })
data.beard_styled_due = hair.next_growth({
  current = "FACIAL_HAIR_GOATEE",
  elapsed_days = 45,
  chain = hair.NATURAL_BEARD,
  fallback = hair.STYLED_BEARD,
})
data.bald_growth = hair.next_growth({ current = "HAIR_BALD", elapsed_days = 1000, chain = hair.HAIR_GROWTH })

data.update_hair = function() hair.update(gapi.get_avatar()) end
