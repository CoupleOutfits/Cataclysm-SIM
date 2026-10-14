# Life Sim

Turns survival into a life simulation. This is the home of Cataclysm-SIM's life-sim features; see
[`docs/en/dev/design/life_sim_roadmap.md`](../../../docs/en/dev/design/life_sim_roadmap.md) for what's planned.

## Bladder

- Your bladder fills slowly on its own (30 ml/h) and faster after you drink: quenched thirst is
  processed by your kidneys over the following hour or two. It fills at half speed while you sleep.
- Status effects warn you as it fills: **Need to Pee** (250 ml), **Need to Pee Badly** (400 ml) and
  **Bursting Bladder** (500 ml), each with a growing morale penalty. A bursting bladder wakes you up.
- At 600 ml you have an accident: a big morale hit, extra embarrassment if anyone saw, and the
  **Soiled** effect until you wash (shower, bath, or washing up) or 12 hours pass.
- To go:
  - **Toilets**: examine one and pick _Use the toilet_ (the tank can still be checked for water).
  - **Action menu → Relieve yourself**: uses an adjacent toilet if there is one, otherwise works
    outdoors. Being watched by NPCs is embarrassing. Indoors with no toilet you can only go when you
    are bursting, and you won't feel good about it.
- **Action menu → Check personal needs** shows how full you are.

## Hair

Hair styles grow out over time and haircuts (any action that gives the _Got a Haircut_ morale)
reset the clock:

| Style                         | Grows into  | After    |
| ----------------------------- | ----------- | -------- |
| crew-cut, mohawk, cropped     | short       | 30 days  |
| short, parted, swept, treated | medium      | 60 days  |
| medium                        | long        | 120 days |
| 'fro                          | overflowing | 150 days |
| long, ponytail                | overflowing | 180 days |

Bald characters stay bald.

## Facial hair

Adds facial-hair traits matching the facial-hair overlays already shipped with the tileset (pick one
at character creation). Male characters grow facial hair:

- clean-shaven → stubble (3 days) → jaw scruff (7 days) → full beard (21 days) → wizened (180 days)
- any groomed style left alone for 45 days becomes a full beard.

Shaving (the _Freshly Shaven_ morale) removes natural growth and keeps a groomed style tidy.

NPCs in the reality bubble grow hair and beards too.
