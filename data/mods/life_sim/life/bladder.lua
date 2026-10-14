-- Bladder need: fills from a slow base rate plus what you drink, nags you in stages,
-- and must be emptied at a toilet or outdoors before it empties itself.

local store = require("./store")

local bladder = {}

---@class LifeSimBladderState
---@field ml number Urine currently in the bladder.
---@field pending number Fluid drunk but not yet processed by the kidneys.

---@class LifeSimBladderStepOptions
---@field state LifeSimBladderState
---@field elapsed_hours number
---@field thirst_drop number How much thirst was quenched since the last step.
---@field sleeping boolean

bladder.BASE_ML_PER_HOUR = 30
bladder.ML_PER_THIRST = 3
bladder.KIDNEY_ML_PER_HOUR = 150
bladder.SLEEP_RATE_FACTOR = 0.5
bladder.ACCIDENT_ML = 600
--- Minimum fill (ml) at which an intensity is shown, indexed by intensity.
bladder.STAGE_ML = { 250, 400, 500 }
--- Morale penalty for a full bladder, indexed by intensity.
bladder.STAGE_MORALE = { -2, -8, -20 }
--- Longest stretch simulated in one step, so loading an old save doesn't flood the bladder.
bladder.MAX_STEP_HOURS = 12

bladder.PLACE_TOILET = "toilet"
bladder.PLACE_OUTDOORS = "outdoors"
bladder.PLACE_INDOORS = "indoors"

local effect_bladder = EffectTypeId.new("life_sim_bladder")
local effect_soiled = EffectTypeId.new("life_sim_soiled")
local effect_sleep = EffectTypeId.new("sleep")
local morale_bladder = MoraleTypeDataId.new("life_sim_morale_bladder")
local morale_relief = MoraleTypeDataId.new("life_sim_morale_relief")
local morale_accident = MoraleTypeDataId.new("life_sim_morale_accident")
local morale_embarrassed = MoraleTypeDataId.new("life_sim_morale_embarrassed")
local wash_morales = {
  MoraleTypeDataId.new("morale_shower"),
  MoraleTypeDataId.new("morale_bath"),
  MoraleTypeDataId.new("morale_cleansed_self"),
}
local act_relief = ActivityTypeId.new("ACT_LIFE_SIM_RELIEF")

bladder.FINISH_CALLBACK = "LIFE_SIM_FINISH_RELIEF"

--- Intensity (0 = fine, 1..3 = increasingly urgent) for a given fill.
---@param ml number
---@return integer
bladder.stage_for = function(ml)
  local stage = 0
  for i, threshold in ipairs(bladder.STAGE_ML) do
    if ml >= threshold then stage = i end
  end
  return stage
end

--- Advances the bladder by `elapsed_hours`. Pure: does not touch the game.
---@param opts LifeSimBladderStepOptions
---@return LifeSimBladderState
bladder.step = function(opts)
  local hours = math.max(0, math.min(opts.elapsed_hours, bladder.MAX_STEP_HOURS))
  local rate = opts.sleeping and bladder.SLEEP_RATE_FACTOR or 1
  local pending = opts.state.pending + math.max(0, opts.thirst_drop) * bladder.ML_PER_THIRST
  local processed = math.min(pending, bladder.KIDNEY_ML_PER_HOUR * hours * rate)
  return {
    ml = opts.state.ml + bladder.BASE_ML_PER_HOUR * hours * rate + processed,
    pending = pending - processed,
  }
end

---@param who Character
---@return LifeSimBladderState
bladder.get_state = function(who)
  return { ml = store.get_num(who, "bladder_ml", 0), pending = store.get_num(who, "bladder_pending", 0) }
end

---@param who Character
---@param state LifeSimBladderState
bladder.set_state = function(who, state)
  store.set_num(who, "bladder_ml", math.floor(state.ml))
  store.set_num(who, "bladder_pending", math.floor(state.pending))
end

---@param who Character
---@param msg_type MsgType
---@param text string
local function tell(who, msg_type, text)
  if who:is_avatar() then gapi.add_msg(msg_type, text) end
end

---@param who Character
---@return boolean
local function has_witnesses(who)
  for _, creature in ipairs(who:get_visible_creatures(12)) do
    if creature:is_npc() then return true end
  end
  return false
end

---@param who Character
---@return integer
local function wash_morale_total(who)
  local total = 0
  for _, morale in ipairs(wash_morales) do
    total = total + who:get_morale(morale)
  end
  return total
end

--- Shows the bladder's stage as a status effect and morale penalty.
---@param who Character
---@param stage integer
local function apply_stage(who, stage)
  local previous = who:has_effect(effect_bladder) and who:get_effect_int(effect_bladder) or 0
  if stage == previous then return end

  who:rem_morale(morale_bladder)
  if stage == 0 then
    who:remove_effect(effect_bladder)
    return
  end

  who:add_effect(effect_bladder, TimeDuration.from_hours(1), nil, stage)
  local penalty = bladder.STAGE_MORALE[stage]
  who:add_morale(morale_bladder, penalty, penalty, TimeDuration.from_hours(24), TimeDuration.from_hours(24), false)

  if stage > previous then
    local messages = {
      locale.gettext("You feel the need to pee."),
      locale.gettext("You really need to pee!"),
      locale.gettext("Your bladder is about to burst!"),
    }
    tell(who, stage == 3 and MsgType.bad or MsgType.warning, messages[stage])
  end
end

---@param who Character
local function have_accident(who)
  bladder.set_state(who, { ml = 0, pending = bladder.get_state(who).pending })
  apply_stage(who, 0)
  who:add_effect(effect_soiled, TimeDuration.from_hours(12))
  store.set_num(who, "soiled_wash_morale", wash_morale_total(who))
  who:add_morale(morale_accident, -20, -20, TimeDuration.from_hours(4), TimeDuration.from_hours(2), false)
  if has_witnesses(who) then
    who:add_morale(morale_embarrassed, -10, -10, TimeDuration.from_hours(6), TimeDuration.from_hours(3), false)
  end
  tell(who, MsgType.bad, locale.gettext("You couldn't hold it any longer.  You wet yourself."))
end

--- Washing (shower, bath, washing up) refreshes its morale, which clears the soiled state.
---@param who Character
local function check_washed(who)
  if not who:has_effect(effect_soiled) then return end
  if wash_morale_total(who) > store.get_num(who, "soiled_wash_morale", 0) then
    who:remove_effect(effect_soiled)
    tell(who, MsgType.good, locale.gettext("You feel clean again."))
  end
end

--- Advances the bladder of `who` to the current turn.
---@param who Character
bladder.update = function(who)
  local now = store.now()
  local last_turn = store.get_num(who, "bladder_turn", now)
  local thirst = who:get_thirst()
  local last_thirst = store.get_num(who, "bladder_thirst", thirst)
  local sleeping = who:has_effect(effect_sleep)

  local state = bladder.step({
    state = bladder.get_state(who),
    elapsed_hours = (now - last_turn) / 3600,
    thirst_drop = last_thirst - thirst,
    sleeping = sleeping,
  })
  store.set_num(who, "bladder_turn", now)
  store.set_num(who, "bladder_thirst", thirst)

  check_washed(who)

  if state.ml >= bladder.ACCIDENT_ML then
    bladder.set_state(who, state)
    have_accident(who)
    return
  end

  bladder.set_state(who, state)
  local stage = bladder.stage_for(state.ml)
  apply_stage(who, stage)
  if sleeping and stage == 3 then
    who:wake_up()
    tell(who, MsgType.warning, locale.gettext("Your bursting bladder wakes you up."))
  end
end

---@param map Map
---@param pos TripointBubMs
---@return TripointBubMs?
local function find_adjacent_toilet(map, pos)
  for _, p in ipairs(map:points_in_radius(pos, 1)) do
    local furn = map:get_furn_at(p)
    if furn and furn:is_valid() and furn:str_id():str() == "f_toilet" then return p end
  end
  return nil
end

---@class LifeSimReliefActivityData
---@field place string

---@param who Character
---@param place string
local function start_relief(who, place)
  local ml = bladder.get_state(who).ml
  who:assign_lua_activity({
    type = act_relief,
    duration = TimeDuration.from_seconds(30 + math.floor(ml / 8)),
    on_finish = bladder.FINISH_CALLBACK,
    data = { place = place },
  })
  tell(who, MsgType.neutral, locale.gettext("You start relieving yourself."))
end

---@param who Character
---@return boolean
local function has_anything_to_do(who)
  if bladder.get_state(who).ml >= 50 then return true end
  tell(who, MsgType.info, locale.gettext("You don't need to go right now."))
  return false
end

--- Action menu entry: relieve yourself wherever is appropriate.
bladder.relieve_action = function()
  local who = gapi.get_avatar()
  if not has_anything_to_do(who) then return end

  local map = gapi.get_map()
  local pos = who:get_pos_ms()
  if find_adjacent_toilet(map, pos) then
    start_relief(who, bladder.PLACE_TOILET)
  elseif map:is_outside(pos) then
    start_relief(who, bladder.PLACE_OUTDOORS)
  elseif bladder.stage_for(bladder.get_state(who).ml) >= 3 then
    tell(who, MsgType.warning, locale.gettext("There's no toilet, but you can't hold it.  The corner will have to do."))
    start_relief(who, bladder.PLACE_INDOORS)
  else
    tell(who, MsgType.info, locale.gettext("You can't do that in here.  Find a toilet or go outside."))
  end
end

--- Toilet examine: use it, or fall back to drinking from the tank.
---@param params { user: Character, pos: TripointBubMs }
bladder.examine_toilet = function(params)
  local menu = UiList.new()
  menu:title(locale.gettext("Toilet"))
  menu:add(1, locale.gettext("Use the toilet"))
  menu:add(2, locale.gettext("Check the tank for water"))
  local choice = menu:query()
  if choice == 1 then
    if has_anything_to_do(params.user) then start_relief(params.user, bladder.PLACE_TOILET) end
  elseif choice == 2 then
    gapi.call_builtin_examine("toilet", gapi.get_avatar(), params.pos)
  end
end

--- Activity finish: empty the bladder and apply place-dependent morale.
---@param params { user: Character, data: LifeSimReliefActivityData? }
bladder.finish_relief = function(params)
  local who = params.user
  local place = params.data and params.data.place or bladder.PLACE_OUTDOORS
  bladder.set_state(who, { ml = 0, pending = bladder.get_state(who).pending })
  apply_stage(who, 0)

  if place == bladder.PLACE_INDOORS then
    who:add_morale(morale_embarrassed, -8, -8, TimeDuration.from_hours(4), TimeDuration.from_hours(2), false)
    tell(who, MsgType.neutral, locale.gettext("You relieve yourself.  Not your proudest moment."))
    return
  end

  local relief = place == bladder.PLACE_TOILET and 6 or 3
  who:add_morale(morale_relief, relief, relief, TimeDuration.from_hours(1), TimeDuration.from_minutes(30), false)
  if place == bladder.PLACE_OUTDOORS and has_witnesses(who) then
    who:add_morale(morale_embarrassed, -5, -5, TimeDuration.from_hours(2), TimeDuration.from_hours(1), false)
    tell(who, MsgType.neutral, locale.gettext("You relieve yourself, painfully aware that you're being watched."))
    return
  end
  tell(who, MsgType.good, locale.gettext("Ahh, sweet relief."))
end

--- Short description for the status screen.
---@param who Character
---@return string
bladder.describe = function(who)
  local ml = bladder.get_state(who).ml
  local percent = math.floor(100 * ml / bladder.ACCIDENT_ML)
  return string.format(locale.gettext("Bladder: %d%% full"), percent)
end

return bladder
