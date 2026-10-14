# Life Sim Roadmap

## Goal

Cataclysm-SIM turns Cataclysm: Bright Nights into an in-depth life simulation in the spirit of The
Sims: bodies that need care, looks that change over time, relationships that grow into romance and
families, and NPCs that live the same life as the player.

## Principles

- **Ship as the `life_sim` mod first.** Features live in `data/mods/life_sim` as Lua + JSON so they
  can be iterated on quickly and toggled per world. Move logic into C++ only when Lua bindings are
  missing or performance demands it, and add the binding rather than working around it.
- **Time-stamped state, not tick counters.** Store "when did this last happen" on the character so
  state catches up correctly for NPCs outside the reality bubble and across save/load.
- **Player and NPC parity.** Every need and life event should apply to NPCs too, even if NPC behavior
  starts out abstracted (e.g. NPCs auto-resolve needs off-screen).
- **Reuse what exists.** BN already has hunger, thirst, fatigue, hygiene washing, cosmetic traits,
  NPC opinion and follower systems; build on them instead of duplicating them.
- **Pure logic is testable logic.** Keep the math in pure Lua functions and test them, plus real
  bound objects for anything that touches game state.

## Milestones

### M1: Body needs and grooming (in progress)

- [x] Bladder need with urgency stages, accidents, toilets and relieving yourself outdoors.
- [x] Hair growth through hair styles; haircuts reset it.
- [x] Facial hair traits (matching existing tileset overlays) and beard growth; shaving resets it.
- [ ] Bowel need alongside bladder (longer cycle, driven by food eaten).
- [ ] Hygiene need: dirtiness builds from time, sweat, blood and filth; washing clears it; NPCs
      notice.
- [ ] Nail growth and clipping (minor, flavor).
- [ ] NPC needs: abstracted relief off-screen; visible NPCs path to toilets.
- [ ] Sidebar widget for needs instead of the action-menu status screen.

### M2: Relationships

- [ ] Relationship values per NPC pair (friendship, attraction, respect, rivalry) built on NPC
      opinion.
- [ ] Social interactions from dialogue: chat, compliment, joke, flirt, hug, kiss, argue, insult.
- [ ] Personality traits that bias interaction outcomes (outgoing, shy, romantic, hot-headed).
- [ ] Relationship states: acquaintance → friend → best friend; crush → dating → partners.
- [ ] Jealousy, breakups, grudges.

### M3: Family

- [ ] Moving in together, shared beds and homes at a faction camp.
- [ ] Marriage / commitment ceremony.
- [ ] Pregnancy (with trimester effects) and birth.
- [ ] Children as NPCs that age: infant → child → teen → adult, inheriting appearance traits.
- [ ] Family tree tracking and family relationships.

### M4: Aging and life stages

- [ ] Characters age with the calendar; age affects stats gradually.
- [ ] Graying hair, balding, wrinkles as cosmetic trait progression.
- [ ] Old age and natural death; inheritance for followers and family.

### M5: Daily life

- [ ] Wants and moods driven by needs and relationships.
- [ ] Hobbies and fun activities that satisfy a fun need (music, games, reading together).
- [ ] Jobs/routines for settlement NPCs.

## Open questions

- Should needs be balanced to stay out of the way of survival gameplay by default, with a "hardcore"
  option for Sims-like frequency? Current bladder rates aim for roughly 4–6 trips a day.
- How much NPC needs simulation can run outside the reality bubble without hurting performance?
- Which pieces should eventually move into core C++ (e.g. a generic "need" type defined in JSON)?
