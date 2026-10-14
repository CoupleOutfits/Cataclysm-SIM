#include "avatar.h"
#include "calendar.h"
#include "catalua.h"
#include "catalua_impl.h"
#include "catalua_sol.h"
#include "catch/catch.hpp"
#include "effect.h"
#include "init.h"
#include "map/mapdata.h"
#include "morale_types.h"
#include "mutation.h"
#include "state_helpers.h"
#include "type_id.h"

#include <algorithm>
#include <string>
#include <vector>

namespace {

auto hair_style_of(const Character& who) -> std::string {
    const auto mutations = who.get_mutations();
    const auto found = std::ranges::find_if(mutations, [](const trait_id& id) {
        return id->types.contains("hair_style");
    });
    return found == mutations.end() ? std::string{} : found->str();
}

auto set_hair_style(Character& who, const trait_id& style) -> void {
    std::ranges::for_each(who.get_mutations(), [&who](const trait_id& id) {
        if (id->types.contains("hair_style")) { who.unset_mutation(id); }
    });
    who.set_mutation(style);
}

auto facial_hair_of(const Character& who) -> std::string {
    const auto mutations = who.get_mutations();
    const auto found = std::ranges::find_if(mutations, [](const trait_id& id) {
        return id->types.contains("facial_hair");
    });
    return found == mutations.end() ? std::string{} : found->str();
}

auto set_bladder(Character& who, int ml) -> void {
    who.set_value("life_sim_bladder_ml", std::to_string(ml));
    who.set_value("life_sim_bladder_pending", "0");
    who.set_value("life_sim_bladder_turn", std::to_string(to_turn<int>(calendar::turn)));
    who.set_value("life_sim_bladder_thirst", std::to_string(who.get_thirst()));
}

auto load_life_sim_test(sol::state& lua) -> sol::table {
    auto test_data = lua.create_table();
    lua.globals()["test_data"] = test_data;
    run_lua_script(lua, "tests/lua/life_sim_test.lua");
    return test_data;
}

} // namespace

TEST_CASE("life_sim_bladder_math", "[lua][life_sim]") {
    clear_all_state();
    auto lua = make_lua_state();
    const auto data = load_life_sim_test(lua);

    const auto stages = data.get<std::vector<int>>("stage_values");
    CHECK(stages == std::vector<int>{0, 0, 1, 2, 3});

    // 1 hour: 30 ml base plus 150 ml of the 300 ml drunk; the rest is still pending.
    CHECK(data.get<double>("step_ml") == Approx(180));
    CHECK(data.get<double>("step_pending") == Approx(150));
    // Long gaps are clamped to 12 hours.
    CHECK(data.get<double>("clamped_ml") == Approx(360));
    // Sleep halves the rate.
    CHECK(data.get<double>("sleeping_ml") == Approx(30));

    // State round-trips through character values on a real avatar.
    CHECK(data.get<double>("stored_ml") == Approx(321));
    CHECK(data.get<double>("stored_pending") == Approx(12));
    CHECK(get_avatar().get_value("life_sim_bladder_ml") == "321");
}

TEST_CASE("life_sim_growth_chains", "[lua][life_sim]") {
    clear_all_state();
    auto lua = make_lua_state();
    const auto data = load_life_sim_test(lua);

    CHECK_FALSE(data.get<sol::optional<std::string>>("beard_none_early").has_value());
    CHECK(data.get<std::string>("beard_none_due") == "FACIAL_HAIR_3DAYSTUBBLE");
    CHECK(data.get<std::string>("beard_styled_due") == "FACIAL_HAIR_BEARD");
    CHECK_FALSE(data.get<sol::optional<std::string>>("bald_growth").has_value());
}

TEST_CASE("life_sim_hair_grows_on_real_avatar", "[lua][life_sim]") {
    clear_all_state();
    auto& u = get_avatar();
    // Facial hair traits come from the mod itself, so only exercise scalp hair here.
    u.male = false;
    u.remove_value("life_sim_hair_look");
    u.remove_value("life_sim_hair_since");
    set_hair_style(u, trait_id("hair_short"));

    auto lua = make_lua_state();
    const auto data = load_life_sim_test(lua);
    auto update_hair = data.get<sol::protected_function>("update_hair");
    const auto update = [&update_hair]() { REQUIRE(update_hair().valid()); };

    update();
    CHECK(hair_style_of(u) == "hair_short");

    calendar::turn += 59_days;
    update();
    CHECK(hair_style_of(u) == "hair_short");

    calendar::turn += 2_days;
    update();
    CHECK(hair_style_of(u) == "hair_medium");

    SECTION("a haircut restarts the clock") {
        calendar::turn += 119_days;
        u.add_morale(MORALE_HAIRCUT, 5, 5, 6_hours, 3_hours);
        update();
        u.rem_morale(MORALE_HAIRCUT);
        calendar::turn += 2_days;
        update();
        CHECK(hair_style_of(u) == "hair_medium");
    }

    SECTION("picking a new style restarts the clock") {
        calendar::turn += 119_days;
        set_hair_style(u, trait_id("hair_crewcut"));
        update();
        CHECK(hair_style_of(u) == "hair_crewcut");
        calendar::turn += 30_days;
        update();
        CHECK(hair_style_of(u) == "hair_short");
    }

    SECTION("untouched hair keeps growing") {
        calendar::turn += 120_days;
        update();
        CHECK(hair_style_of(u) == "hair_long");
    }
}

// Needs the mod's own data: run with `cata_test --mods=life_sim "[.life_sim_mod]"`.
TEST_CASE("life_sim_mod_runtime", "[.life_sim_mod]") {
    clear_all_state();
    auto& lua = DynamicDataLoader::get_instance().lua->lua;
    auto mod = lua["game"]["mod_runtime"]["life_sim"];
    REQUIRE(mod.valid());
    const auto call = [&mod](const char* name) {
        REQUIRE(mod[name].get<sol::protected_function>()().valid());
    };

    auto& u = get_avatar();
    const auto bladder_effect = efftype_id("life_sim_bladder");
    const auto soiled_effect = efftype_id("life_sim_soiled");
    const auto morale_relief = morale_type("life_sim_morale_relief");
    const auto morale_accident = morale_type("life_sim_morale_accident");

    CHECK(furn_str_id("f_toilet")->examine_action_id == "LIFE_SIM_TOILET_EXAMINE");

    SECTION("a filling bladder shows its stage") {
        set_bladder(u, 450);
        call("on_every_5_minutes");
        REQUIRE(u.has_effect(bladder_effect));
        CHECK(u.get_effect_int(bladder_effect) == 2);

        auto params = lua.create_table();
        params["user"] = u.as_character();
        auto data = lua.create_table();
        data["place"] = "toilet";
        params["data"] = data;
        REQUIRE(mod["finish_relief"].get<sol::protected_function>()(params).valid());
        CHECK_FALSE(u.has_effect(bladder_effect));
        CHECK(u.has_morale(morale_relief));
        CHECK(u.get_value("life_sim_bladder_ml") == "0");
    }

    SECTION("an overfull bladder causes an accident") {
        set_bladder(u, 599);
        calendar::turn += 1_hours;
        call("on_every_5_minutes");
        CHECK(u.has_effect(soiled_effect));
        CHECK(u.has_morale(morale_accident));
        CHECK_FALSE(u.has_effect(bladder_effect));
    }

    SECTION("men grow stubble and shaving removes it") {
        u.male = true;
        std::ranges::for_each(u.get_mutations(), [&u](const trait_id& id) {
            if (id->types.contains("facial_hair")) { u.unset_mutation(id); }
        });
        u.remove_value("life_sim_beard_look");
        u.remove_value("life_sim_beard_since");
        call("on_every_hour");
        calendar::turn += 3_days;
        call("on_every_hour");
        CHECK(facial_hair_of(u) == "FACIAL_HAIR_3DAYSTUBBLE");

        calendar::turn += 2_hours;
        u.add_morale(MORALE_SHAVE, 5, 5, 6_hours, 3_hours);
        call("on_every_hour");
        CHECK(facial_hair_of(u).empty());
    }
}
