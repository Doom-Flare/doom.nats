# rules/ — Author Rule Layer (v4.23)

中文: `src/rules/README.md`

> **Default = vanilla.** When all three files are empty (`{}` / `[]` / `{}`), the generators take the original path, and the
> artifacts are **byte-for-byte identical** to those "without this layer" (guarded by the `--check` of 9 generators in `tools/check_static.mjs`).
> Each entry you fill in affects only the one behavior it names.

This layer is a **build-time** input: after changing it you must regenerate + reinstall (see "How to Use" at the end).
The simple runtime switches are still in `doom.nats:config` → `$cfg.*` (`docs/18-配置手册.md`).

---

## 1. The Three Files

| File | Purpose | Empty value |
|---|---|---|
| `entity-rules.json` | **Per-entity rule patch**: change the landing face / light / Y window / biome / weather | `{}` |
| `entries.json` | **Add conditional spawn entries**: only join the candidate pool when the condition holds; may carry custom NBT | `[]` |
| `counts.json` | **Define counts by Y axis**: `groupByY` (how many spawn per attempt) / `capByY` (capacity of that category) | `{}` |

`DOOM_RULES=<directory>` can point this layer elsewhere (that is how the acceptance use cases run; see `examples/full/`).

---

## 2. `entity-rules.json` — Per-Entity Rule Patch

Key = entity id, value = the fields to override (**shallow merge** onto the vanilla rules; `null` = delete that field).

```json
{
  "minecraft:zombie":     { "belowAny": ["minecraft:leaves"] },
  "minecraft:glow_squid": { "place": "ground", "light": "dark", "ySea": null }
}
```

### 2.1 Vanilla Vocabulary (the ones in `lib/entity-rules.mjs`, directly overridable/deletable)

| Field | Values | Meaning |
|---|---|---|
| `place` | `ground` / `any` / `water` / `water_surface` / `below_tag` / `lava` | landing type (ON_GROUND / NO_RESTRICTIONS / IN_WATER / water-surface window / tag below / IN_LAVA) |
| `light` | `none` / `dark` / `bright` / `bat` / `slime` / `glow` / `bl8` | light tier (see the item-by-item comments at the top of `lib/entity-rules.mjs`) |
| `tag` | block tag id | the "must be below" tag used by `below_tag` |
| `coins` | `half` / `moon` / `2of3` / `1of15` / `1of20` / `1of40` | coin-flip rejection |
| `cluster` | integer | `getMaxSpawnClusterSize` |
| `persist` | `true` | spawns already carrying `PersistenceRequired:1b` (vanilla semantics: never despawns) |
| `biome` | `slime` / `polar_bear` | the two special biome branches |
| others | `sky` `notWart` `deep` `moreDrowned` `river98` `d64` `noPlayer5` `ySea` `yTurtle` `lavaToAir` `grp1` `water` `noSky` `belowSurface` | switches corresponding item by item to the vanilla source (as above) |

To delete a field, write `null`: e.g. `"ySea": null` removes the glowing squid's `y ≤ seaLevel-33` window,
and `"deep": null` removes the drowned's deep-water gate (**note**: this makes all drowned common).

### 2.2 Fields Added by This Layer

| Field | Values | Meaning |
|---|---|---|
| `belowAny` | `["#tag" or "tag"]` | **extra allowed "landing faces below"** (unioned with `#doom.nats:standable ∪ #doom.nats:full_collision`). Use it to let land mobs stand on leaves/logs/warped wart blocks — vanilla does not count these blocks as standable. |
| `yMin` / `yMax` | integers (closed interval) | the candidate point's y window (checked against `$py`, same convention as the vanilla seaLevel window) |
| `lightMax` / `lightMin` | 0..15 | overall brightness upper/lower bound (`location_check.light.light.max/min`); finer than the `light` tier |
| `biomeIn` / `biomeNot` | `["#tag"]` or `["id", …]` | spawn only in these / not in these biomes (a tag must be used **on its own**: the vanilla `biomes` predicate accepts only a single tag or a list of ids) |
| `weather` | `thunder` / `rain` / `clear` | weather gate (`weather_check` predicate) |

The reason recorded on rejection matches vanilla: landing face ⇒ `3`, light ⇒ `3`, all other rules ⇒ `9`.

---

## 3. `entries.json` — Conditional Spawn Entries

An array; each entry = a species entry that is "in the candidate pool only when its condition holds".

```json
[
  {
    "id": "thunder_royal_zombie",
    "comment": "雷暴时的深海：带自定义 NBT 的特例",
    "biomes": ["#minecraft:is_deep_ocean"],
    "category": "monster",
    "mob": "minecraft:zombie",
    "weight": 100000,
    "group": [2, 3],
    "when": { "thundering": true, "yMax": 40 },
    "nbt": "{CustomName:'{\"text\":\"深海雷暴僵尸\",\"color\":\"aqua\"}',equipment:{mainhand:{id:\"minecraft:trident\",count:1}},Health:40f}"
  }
]
```

| Field | Required | Notes |
|---|---|---|
| `id` | ✅ | unique name. The generated entity is tagged `doom.nats.author.<id>` in the artifacts (handy for tallying/cleanup) |
| `mob` | ✅ | entity id |
| `category` | ✅ | `monster` / `creature` / `ambient` / `water_creature` / `water_ambient` / `underground_water_creature` / `axolotls` |
| `biomes` | ✅ | biome id or `#tag` (tags are expanded into concrete biomes by `node tools/export_biome_tags.mjs`) |
| `weight` | | default `1`. **Hit rate ≈ `weight / 1000000`** — **not** "competing in the same pool as the vanilla entries" (measured on a real machine in v4.28; the mechanism and comparison table are in the "⚠ the weight convention" note below). To take effect, fill in a **hundred-thousand-scale** value: `100000`≈10% · `900000`≈90%; `40` amounts to not spawning at all |
| `group` | | `[min, max]`, default `[1,1]` |
| `when` | | conditions (all ANDed): `thundering` `raining` `yMin` `yMax` `lightMax` `lightMin`; empty = unconditional |
| `nbt` | | SNBT, **merged into** this pack's tags and then `data merge entity @s`. Writing `Tags` overrides this pack's tags (not recommended). Equipment fields were renamed in 1.21.5+ (`HandItems`→`equipment`, drop rates→the entity-level `drop_chances`); the old form is **silently discarded** ⇒ see §7.5 pitfall 5 |
| `groupByY` | | override this entry's group size by Y band (same form as §4) |

**Semantics (equivalence)**: the artifacts write the condition into the `#wsum` accumulation — when the condition holds, `#wsum += weight`, the hit interval follows immediately after the vanilla interval,
and "the offset `#off` only advances when the condition holds". **This "condition filtering" step** is point-by-point equivalent to "first filter the candidate table by condition, then roll by weight" (no gaps appear).

> ⚠ **The weight convention (measured on a real machine in v4.28: differs from the "same pool" intent in the sentence above)**: the hit interval `#off..#hi` is computed on a
> **small-order-of-magnitude** basis of "vanilla weight sum + weight" (each biome/category ranges from single digits to around 600), but the `$rng` compared against it is the **not-yet-moduloed** `random value 0..999999`;
> the modulo `$rng %= #wsum` happens **after** this comparison (`gen_mobs.mjs` inserts the author-layer block between `set #wsum` and `%=`) ⇒
> **the actual hit rate ≈ `weight / 1000000`**, independent of the vanilla weight sum (the vanilla half's proportion is still correct).
> Measured comparison: `weight=90` ⇒ 90 seconds, **0** mobs; `weight=900000` ⇒ 180 seconds, blazes **22 → 32** (≈90%).
> Build-time entries and runtime entries **go through the same chain**, with the same convention. **To take effect, fill in a hundred-thousand-scale value.**

**Limitation (honest list)**: an entry can only be added to a category the biome **already has** (`mob/biome/<biome>/<category>` must already exist).
To add monsters to "a biome that originally had no monster at all", you have to change the roster / worldgen override (`tools/apply_worldgen.mjs`).

---

## 4. `counts.json` — Define Counts by Y Axis

```json
{
  "groupByY": {
    "minecraft:zombie": [
      { "yMax": 0,             "min": 4, "max": 6 },
      { "yMin": 1, "yMax": 63, "min": 2, "max": 3 },
      { "yMin": 64,            "min": 1, "max": 1 }
    ]
  },
  "capByY": {
    "monster": [
      { "yMax": 0, "max": 200, "localMax": 140 },
      { "yMin": 1, "max": 70,  "localMax": 70 }
    ]
  }
}
```

- `groupByY.<entity>` = `[{yMin?, yMax?, min, max}]`: **how many to spawn per attempt** (the vanilla `minCount..maxCount`), overridden by the candidate point's Y band.
  Bands are **evaluated in order, later ones overriding earlier ones**; you may write only `yMax`, only `yMin`, or both.
- `capByY.<category>` = `[{yMin?, yMax?, max?, localMax?}]`:
  - `max` = **global capacity** (the upper bound on the total number of that category in the dimension; the vanilla formula is `maxInstancesPerChunk × spawnableChunkCount / 289`)
  - `localMax` = **per-player limit** (the vanilla `LocalMobCapCalculator`, default = `maxInstancesPerChunk`, 70 for monsters)
  Either can be given on its own; whatever you don't give keeps the snapshot the engine computes each tick.
- A failed count check uses the vanilla reason: globally full ⇒ `5`, locally full ⇒ `6`.

> A reminder about the `capByY` convention: capacity is "**a snapshot recomputed every tick**", and your Y band is evaluated only at the **attempt point**'s y —
> that is, "when the player is underground, the mob cap is computed from the underground band". This is **deliberately different** from vanilla's "the cap depends only on the chunk count"
> and is an extension of this layer (what is wanted is "fully definable").

---

## 5. How to Use

```bash
cd <仓库>/doom.nats

# ① Edit the files in rules/ directly (or copy examples/full/*.json in)
# ② Regenerate the artifacts (the 9 generators)
for g in gen_pack gen_pos gen_check gen_mobs gen_spawn gen_despawn gen_effects gen_debug gen_group; do node tools/$g.mjs; done
# ③ Static gate (no generator drift + lint + reference closure)
node tools/check_static.mjs
# ④ Install into a world / test instance
node tools/install.mjs --variant std --save <存档名>

# Variant build (without changing rules/ in the repo): just prefix with DOOM_RULES=<directory>
DOOM_RULES=$PWD/rules/examples/full node tools/gen_mobs.mjs
```

**Back to vanilla**: empty the three files (or delete `rules/`) and regenerate ⇒ the artifacts should be byte-for-byte identical to "never modified"
(`node tools/check_static.mjs` will tell you).

## 6. Acceptance Use Cases

`examples/full/` is the collection of the four use cases (the four the user raised):

| Use case | File | Effect |
|---|---|---|
| ① Zombies spawn on leaves | `entity-rules.json` | the zombie's set of standable blocks below gets `#minecraft:leaves` unioned in |
| ② Thunderstorm + deep ocean spawns a mob with NBT | `entries.json` | the deep-ocean `monster` pool gains, while thundering and y≤40, one "deep-sea thunderstorm zombie" with **weight 100000** (≈10%) (trident + custom name + 40 health) |
| ③ Glowing squids spawn on grass | `entity-rules.json` | removes the `y ≤ seaLevel-33` window, changes the landing to land, changes light to `dark` |
| ④ Spawn counts fully defined by the Y axis | `counts.json` | zombie group size y≤0 → 4~6 / 1~63 → 2~3 / ≥64 → 1; monster capacity y≤0 → global 200·per player 140, otherwise 70·70 |

How to run:

```bash
DOOM_RULES=$PWD/rules/examples/full node tools/gen_mobs.mjs
DOOM_RULES=$PWD/rules/examples/full node tools/gen_check.mjs
DOOM_RULES=$PWD/rules/examples/full node tools/gen_group.mjs
```

Real-machine acceptance script: `_work/verify_author_rules.mjs` (A/B: same world, only the rules directory swapped, comparing "vanilla / this pack / where they differ / the numbers").

---

## 7. Runtime Changes (v4.24): Change the Storage and It Takes Effect Immediately, No Regeneration Needed

> Sections 1–6 above are **build-time**: change `rules/*.json` → regenerate → reinstall.
> Since v4.24 the same capabilities also have a **runtime** path: **change the storage in-game and it takes effect immediately** (the checks read the storage on the spot),
> with no regeneration, no reinstall, and no restart. The build-time layer is kept as is (the two can be stacked).

### 7.1 Storage Shape (isomorphic to `rules/*.json`, so you can pour the JSON straight in)

```mcfunction
# Per-entity patch (= the shape of entity-rules.json, keys are still entity ids)
data modify storage doom.nats:author entityRules."minecraft:zombie".belowAny set value ["#minecraft:leaves"]
# Conditional entry (= one entry of entries.json)
data modify storage doom.nats:author_in entry set value {id:"royal",mob:"minecraft:zombie",biome:"#minecraft:is_overworld",category:"monster",weight:100000,when:{thundering:1b},nbt:"{CustomName:'{\"text\":\"皇家僵尸\",\"color\":\"gold\"}'}"}
function doom.nats:author/add_entry with storage doom.nats:author_in
# Counts by Y (= one band of counts.json)
data merge storage doom.nats:author_in {type:"minecraft:zombie",yMax:0,min:4,max:6}
function doom.nats:author/set_group_by_y with storage doom.nats:author_in
```

| Storage key | Equivalent to | Fields supported at runtime |
|---|---|---|
| `doom.nats:author.entityRules.<entity id>` | `rules/entity-rules.json` | `belowAny`(≤8) `yMin` `yMax` `lightMin` `lightMax` `weather`(thunder/rain/clear) `biomeIn`(≤4) `biomeNot`(≤4) `place` `light` `persist` |
| `doom.nats:author.entries[]` (≤8 entries) | `rules/entries.json` | `id` `mob` `biome` (a single biome or `#tag`; for several, write several entries) `category` `weight` `min` `max` `nbt` `when{thundering,raining,yMin,yMax,lightMin,lightMax}` |
| `doom.nats:author.counts.groupByY.<entity id>[]` (≤8 bands) | `groupByY` of `rules/counts.json` | each band `{yMin?,yMax?,min,max}`; **bands are evaluated in order, later ones overriding earlier ones** |
| `doom.nats:author.counts.capByY.<category>[]` (≤8 bands) | `capByY` of `counts.json` | each band `{yMin?,yMax?,max?,localMax?}`; either can be given on its own |

Command surface (`/function` has no inline arguments ⇒ everything goes through the `doom.nats:author_in` "argument storage"):

| Command | Effect |
|---|---|
| `function doom.nats:author/help` | usage and field list |
| `function doom.nats:author/show` | print the current overrides (chat summary + full `data get storage` + one log line) |
| `function doom.nats:author/export` | pack the current overrides into one copyable `data modify storage … set value {…}` |
| `function doom.nats:author/reset` | **back to vanilla** (removes the three layers of keys + clears the cache) |
| `…/add_below_tag` · `…/set_group_by_y` · `…/set_cap_y` · `…/add_entry` | append one entry (arguments as in the table above) |
| `…/load` · `…/demo` | reload/refresh the summary · command-surface demo (requires `scoreboard players set $auth.demo doom.nats 1` first) |

### 7.2 Three-Column Comparison (don't just ask "can it be changed", ask "how does the result differ from vanilla")

| Capability | What vanilla does | What this pack does (default) | What the experimental variant (v4x) does |
|---|---|---|---|
| Extra landing face `belowAny` | leaves are not `isFaceSturdy(UP)` ⇒ zombies will not stand on leaves | both the build-time `rules/` and the runtime storage can add tags; empty by default = item-by-item identical to vanilla | same as default |
| Y window / brightness window / weather gate / biome list | hard-coded in the source (`check*SpawnRules`) | write one entry in the storage and it takes effect immediately, with reason codes matching the build-time ones (light⇒3, the rest⇒9) | same as default |
| Group size / capacity by Y | group size = `minCount..maxCount` (independent of y); capacity = `maxInstancesPerChunk × chunks / 289` | overridden by the **candidate point's y** (the capacity override is an **extension of this pack**, see the convention reminder in §4) | same as default |
| Conditional entries (with custom NBT) | there is no such concept as a "conditional entry" | joins the pool only when the condition holds (point-by-point equivalent to "filter first, then roll by weight"); NBT is merged in with `$data merge entity @s $(nbt)` | same as default |
| `when.near` relational condition | **no** such coupling | unsupported (writing it into `when` is ignored) | supported: `near:{type:"#doom.nats:creature",radius:24,min:1,max:0}` counts entities once, centered on the **candidate point**. **Not a vanilla capability** |
| `on_spawn` effect hook | **none** | unsupported (the `on_spawn` field is ignored) | supported: an entry writes `on_spawn:1b`, and on a hit after spawning it calls `doom.nats:exp/on_spawn/<entry id>` (`@s` = the new entity). When the file does not exist, only that hook step is skipped and the entity spawns as usual |
| `preset` presets | **none** | unsupported | supported: `blood_moon` / `storm_season` / `deep_dark` (+ `rules/presets/*.json`). Merge semantics, stackable, `reset` restores in one command |

### 7.3 Two Tracks: Engine Gate + Runtime Switch (both in the **experimental variant**)

- **Engine gate** (whole-pack level, decides "whether it can be installed"): the `pack.mcmeta` of the experimental variant `pack/doom.nats-experimental` carries
  `"features": {"enabled": ["minecraft:minecart_improvements"]}` (the field shape is taken from vanilla's own experimental datapack;
  the three flags available in 1.21.6 are `minecart_improvements` / `redstone_experiments` / `trade_rebalance`, and there is no "custom" flag
  ⇒ you can only borrow a native flag as the gate, at the cost that a world enabling it also gets vanilla's minecart changes).
  When the world has not enabled that experimental gameplay, the engine explicitly refuses to enable it:
  `Pack 'file/doom.nats' cannot be enabled, since required flags are not enabled in this world: minecraft:minecart_improvements!`
- **Runtime switch** (`storage doom.nats:exp enabled:1b`, decides "whether the behavior rolls back"): `function doom.nats:exp/disable`
  keeps the whole layer out of the checks with one command (entries and rules are all retained), `enable` turns it back on, and `reset` clears it.

### 7.4 Numbers (real machine, isolated instance fid 25571/RCON 25581)

| Item | Number |
|---|---|
| Runtime layer acceptance (default variant) | `_work/verify_author_runtime.mjs --variant std` ⇒ **15 PASS / 0 FAIL** (3 experimental assertions SKIP by design) |
| Runtime layer acceptance (experimental variant) | `--variant exp` ⇒ **19 PASS / 0 FAIL** (including the three on_spawn / near / preset ones) |
| Build-time A/B no-regression | `verify_author_rules.mjs --expect default` **5 PASS / 0 FAIL** · `--expect author` **6 PASS / 0 FAIL** |
| Load time | both variants `/reload` with **0 Failed to load function** |
| Static gate | `node tools/check_static.mjs` ⇒ **0 error / 2 warning** (generator `--check` + lint run once per variant) |

> ⚠ The `verify_*` numbers in §7.4 all come from **fixed `$rng`** probes (hand-picked dice values that land in the author window); they only verify "routing / condition gates / NBT landing",
> and **do not cover the `weight` hit rate** — all green **does not mean** `weight` takes effect as "same-pool competition" (see the weight convention at the end of §3).

### 7.5 Pitfalls (specific to this runtime layer; all hit on a real machine)

1. **Every placeholder in a macro line must exist**: missing one ⇒ **the whole function aborts** (`Failed to instantiate … Missing argument`).
   So runtime values are always "lay down defaults first, then merge" (see `cur` in `author/row`, `e` in `entry_prep_*`).
2. **`data merge` is a recursive merge**: writing `nbt` into the same merge makes the previous entry's keys accumulate onto the next mob
   ⇒ this pack has changed to "merge the structural fields + `set` the `nbt` as a whole" (`sel.nbt`).
3. **`data remove storage <id>` must carry a path**; `execute if data storage <id>{…}` **is illegal** (both raised errors on a real machine).
4. **A string substituted into SNBT by a macro must be quoted by you**: `type:$(mob)` becomes `type:minecraft:zombie` (illegal SNBT) ⇒ write `type:"$(mob)"`.
5. **The equipment NBT in 1.21.5+ is `equipment:{mainhand:{…},head:{…}}`**: the old `HandItems`/`ArmorItems` are **silently ignored**
   (measured this round: writing `HandItems` neither errors nor takes effect). Equipment drop rates are the **entity-level** `drop_chances:{mainhand:…,head:…}` (on the same level as `equipment`;
   putting them inside `equipment` is likewise silently discarded), and the slot names are `mainhand`/`offhand`/`head`/`chest`/`legs`/`feet`/`body`. For the player-facing explanation see §8 of `docs/wiki/示例库.md`.
6. A runtime entry's `biome` check is evaluated at the **candidate point** (the same meaning as the build-time "table expanded by biome") ⇒ an entry can only be added to a category the biome **already has**.

---

## 8. Experimental AJ / thirdparty-tool rig Bridge (v4.25, `rules/rigs.json`)

> **Absent by default**: if `rules/rigs.json` is `{}` / missing ⇒ the generators **produce no `exp/aj/**` at all**, and `spawn/emit` and `core/tick`
> add not one word either (the default variant's `check_static` is still 0 error / 2 warning). This layer **only goes into the experimental variant** (`DOOM_EXP=1 ⇒ pack/doom.nats-experimental`).

**The problem being solved**: the "custom mobs" exported by Animated Java / thirdparty-tool are a **display entity skeleton + animation functions**; a display is not a `Mob`
(it has no `MobCategory`/`SpawnPlacements`/`checkDespawn`/`finalizeSpawn`) ⇒ it cannot be a species in the biome table.
This layer's approach is **plan A, "a real entity as the core, the rig as the appearance"**: the core (an ordinary mob) goes through the spawn chain as usual, and the rig is summoned at the same position and **mounted onto the core**.

### 8.1 Field Table (`rules/rigs.json`)

```json
{
  "thirdparty_rig": {
    "carrier": "minecraft:squid",
    "rig": "your_rig:summon",
    "carrier_nbt": "{Silent:1b,active_effects:[{id:\"minecraft:invisibility\",amplifier:0,duration:-1,show_particles:0b}]}",
    "rig_args": "{args:{}}",
    "rig_root_tag": "your_rig_root_tag",
    "on_spawn": "your_rig:start_animation",
    "cat": "water_creature",
    "count_with_carrier": true,
    "mount": true,
    "comment": "示例 rig（仅为演示桥接，非随包分发）（只用于验收，不进产物）"
  }
}
```

| Field | Required | Default | Notes |
|---|---|---|---|
| `carrier` | ✅ | —— | the real-entity core (**must** be a species in the mob registry; one core can be paired with only one rig) |
| `rig` | ✅ | —— | the **summon entry function** id of the third-party rig (AJ: `<ns>:<blueprint>/summon`; thirdparty-tool: `<ns>:summon`) |
| `carrier_nbt` | | none | SNBT merged into the core (invisible/silent/no AI…) |
| `rig_args` | | `{args:{}}` | macro arguments passed to the rig's summon function (the AJ/thirdparty-tool convention reads `$(args)`) |
| `rig_root_tag` | | `aj.global.root` | the tag carried by the rig's **root** display (AJ's convention; thirdparty-tool exports use a string of the author's own) |
| `on_spawn` | | none | the function called after mounting completes (@s = the core); typical use: start a third-party animation |
| `cat` | | from the registry | category (only affects tags and diagnostics; **must** match the registry, otherwise the build errors) |
| `count_with_carrier` | | `true` | whether the core counts toward mobcap; `false` ⇒ tag the core with `PersistenceRequired:1b` (vanilla semantics: persistent mobs do not count toward `SpawnState`, at the cost of also being immune to the despawn layer/`debug/clear`) |
| `mount` | | `true` | whether this bridge manages it (claim + mount + sweep); `false` ⇒ only summon, and leave the rest to the third-party pack |
| `comment` | | none | a comment for humans (keys starting with `_` are always ignored) |

### 8.2 How to Use

```bash
cd <仓库>/doom.nats
# ① Write rules/rigs.json (or copy rules/examples/aj/rigs.json in)
# ② Regenerate with the experimental variant
DOOM_EXP=1 node tools/gen_pack.mjs && DOOM_EXP=1 node tools/gen_mobs.mjs && DOOM_EXP=1 node tools/gen_exp_aj.mjs
#    The other generators run as usual; gen_exp_aj writes only data/doom.nats/function/exp/aj/** (17 files)
# ③ Install the experimental variant (pack/doom.nats-experimental) + put the third-party pack into the world's datapacks
#    If the third-party pack uses the new pack.mcmeta schema (min_format/max_format), 1.21.6 cannot recognize it ⇒ add "pack_format": 80
```

**In-game self-check**: `function doom.nats:exp/aj/help` (usage + current rig list) · `function doom.nats:exp/aj/status` (how many displays are live / how many are mounted / how many are left over).
`function doom.nats:exp/aj/placeholder/summon` is a **zero-dependency placeholder rig** (a hand-built display skeleton), used to tell "the bridge is broken" apart from "some third-party rig is broken".

### 8.3 Three Measured Conclusions (read before changing the mounting method)

1. **The direction must be "the rig rides the core"** (`ride <rig> mount <core>`). Reversed, the core becomes the passenger and gets pinned to a display that never moves.
2. **`minecraft:marker` cannot carry passengers** (`Item Display couldn't start riding Marker`) ⇒ do not build the "marker as the mounting hub" layer.
3. **One mob can carry several displays at once, and they land on the same mounting point** (with 3 passengers measured, `Pos` was exactly identical) ⇒
   the skeleton's relative layout is determined by each one's `transformation` and is not scrambled by "passenger index".
   Another related measurement: a display entity has **no `RootVehicle`** (even while being ridden) ⇒ to determine "is it mounted", use the passenger closure (this layer uses the `exp.aj.live` tag).
