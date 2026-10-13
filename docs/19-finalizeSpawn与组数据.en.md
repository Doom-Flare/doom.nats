> This document is an author-facing verification record (not required reading for players); the paths and numbers in it come from the local development environment.

# 19 · finalizeSpawn, Group Data, and Seven Spawning Questions

中文: `docs/19-finalizeSpawn与组数据.md`

> Answering the 2026-09 round of questions in one pass, and recording the group data layer newly added in v4.15 (a SpawnGroupData replica).
> All conclusions come from the local decompiled source (`doom.nats/_work/decomp/out15/`, 1.21.6 named); the line numbers can be checked yourself.

---

## 1. The Seven Questions

### Q1 Why must the author declare coordinates for "no spawning within 24 blocks of the world spawn"?

Vanilla `NaturalSpawner.isRightDistanceToPlayerAndSpawnPoint` checks three things:

```java
player distSq > 576                              // 24 blocks
&& !level.getSharedSpawnPos().closerToCenterThan(pos, 24.0)
&& (chunk == current chunk || level.canSpawnEntitiesInChunk(chunk))
```

`getSharedSpawnPos()` comes from the `spawn` field of `level.dat` (ServerLevelData). A datapack cannot read it:

- The full field list of the predicate `LocationPredicate` is only `position / biomes / structures / dimension / smokey / light / block / fluid / can_see_sky`; there is no spawn point;
- There is no condition such as `execute if spawnpoint`;
- The `SpawnX/SpawnY/SpawnZ` in player NBT is the bed/respawn anchor respawn point, which is a different thing from the world spawn (once you sleep, it diverges).

So it can only be declared by the author. This pack's implementation: this one is listed separately from `$cfg.player24`; the author just writes the world spawn coordinates in `doom.nats:config` (not writing them = the exclusion is not enabled, which is a "known deviation" rather than a bug). This is a gap caused by unobservable information, not laziness.

### Q2 What does `getMobsAt` manage?

```java
// ChunkGenerator.getMobsAt(Holder<Biome>, StructureManager, MobCategory, BlockPos)
for (StructureStart s : structureManager.getAllStructuresAt(pos)) {
   var overrides = s.getStructure().spawnOverrides();
   if (overrides has an entry for this category && pos falls inside the corresponding bounding_box (piece | full))
      return the species table given by that entry;          // ← structure override
}
return biome.getMobSettings().getMobs(category);   // ← the normal biome table
```

That is: the final arbiter of "which species should spawn at this position". By default it goes through the biome `spawners`; as long as there is a structure with `spawn_overrides` underfoot, the whole table is replaced by the one the structure gives. In vanilla only a few structures have a non-empty `spawn_overrides` (`pillager_outpost`, `swamp_hut` (cat, piece), `ancient_city` (ambient empty table); `nether_fortress` uses hardcoding rather than an override, and so on). This pack has already replicated `nether_fortress` (`mob/fortress`); the other structure overrides are still a gap (see §4).

### Q3 "finalizeSpawn can be done now": it is indeed done now, but not the way you think

Key fact (source-verified): `/summon` and `execute summon` already call `finalizeSpawn` themselves.

```java
// SummonCommand.createEntity(CommandSourceStack, Reference<EntityType<?>>, Vec3, CompoundTag, boolean)
Entity e = EntityType.loadEntityRecursive(tag, level, EntitySpawnReason.COMMAND, x -> { x.snapTo(pos…); return x; });
if ($$4 && e instanceof Mob m)                                   // ← /summon passes true here
   m.finalizeSpawn(level, level.getCurrentDifficultyAt(e.blockPosition()), EntitySpawnReason.COMMAND, null);
level.tryAddFreshEntityWithPassengers(e);                        // ← the order matches NaturalSpawner
```

`execute summon <type> run <cmd>` goes through this path too (`ExecuteCommand.spawnEntityAndRedirect` → `SummonCommand.createEntity(..., true)`), and hands the new entity to the `run` command as `@s`.

So "rewriting finalizeSpawn per entity" is not only unnecessary, it would apply things twice:
equipment/weapons (zombie iron sword and shovel, skeleton bow, drowned trident and fishing rod, piglin golden sword and crossbow + golden armor, vindicator iron axe, pillager crossbow, wither skeleton stone sword + attack damage 4),
variants (cow/sheep/pig/chicken cold/warm/temperate, cat 11 kinds, wolf 9 kinds + 7 sounds, fox red/snow, rabbit 7 kinds, axolotl 5 kinds, horse 7×markings, llama 4 kinds, parrot 5 kinds, panda genes, salmon large/medium/small, tropical fish patterns, zombie villager profession/biome),
babies (zombie 5%, piglin 20%, hoglin 20%), chicken jockeys (zombie→chicken), spider jockeys, zombie leaders (5% reinforcement), goat screaming 2%/broken horn 10%, phantom size, turtle home_pos, bat/slime size, `LeftHanded` 5%, `follow_range` triangular-distribution bonus —
all of the above is done by vanilla itself at creation time.

The two things v4.15 changed:

1. `spawn/emit` changed from `summon <type> ~ ~ ~ <nbt>` to
   ```
   $execute summon $(type) run function doom.nats:post/$(slug) with storage doom.nats:sel
   ```
   so that "give the just-spawned one this pack's NBT + apply group data" has an unambiguous `@s`.
   The old form `@e[distance=..1,sort=nearest]` would pick the wrong entity when several spawn consecutively at the same point (the same cluster, random walking into each other). That was a latent bug in the original design, fixed along the way.
2. A new group data layer (§2 of this file): replaying with scoreboards the `SpawnGroupData` that `NaturalSpawner` passes to `finalizeSpawn`.

Along the way, the random facing vanilla gives in `snapTo` (`random*360`) was also added: `execute summon` only aligns the position, leaving rotation at 0.

### Q4 What is "per-position biome", and where does it differ?

Vanilla picks the species using the biome of the candidate point: `NaturalSpawner.getRandomSpawnMobAt(level, structureManager, chunkGenerator, category, random, pos)` → `chunkGenerator.getMobsAt(level.getBiome(pos), …)`.

For performance, this pack makes biome detection "once per snapshot beat, probed once on each player" (`biome/detect` → `$snap.biome`), and the whole cluster reuses it. The deviations happen near biome boundaries (what was probed is the biome under the player, while the candidate point may have already crossed the boundary) and when the player and the candidate point are far apart.

Cost comparison: switching to per-candidate-point detection = 65 `execute if biome` per candidate point (see the table in `biome/dispatch`), which at the current roughly 40 attempts/second is an order-of-magnitude increase. The compromise (not done): re-probe only when the candidate point and the player are across biomes. The special rules for slime/polar bear/drowned/river are anyway per-candidate-point predicate checks, so they are unaffected.

Note: the variant layer is per-position exact. `post/<slug>` evaluates the biome predicate at `@s` (the new entity's real coordinates), so "cold/warm biome cows, sheep and pigs, snow fox, white/gold rabbit" are judged by the biome right under that creature's feet.

### Q5 What does "exact AABB" mean?

In vanilla's validity check, besides "a valid block below + standable at feet/head", there is one check that genuinely follows the collision box:

```java
// The last link of NaturalSpawner.isValidPositionForMob / isValidSpawnPostitionForType
level.noCollision(type.getSpawnAABB(x, y, z));   // the AABB is based at the block center, with width/depth from the entity size
```

`type.getSpawnAABB(x,y,z)` = a box centered on the block center `(x, y, z)` and expanded by the entity's `width/height` (scaled by `spawnDimensionsScale`), which is then intersection-tested against the block collision shapes. It can stop cases like slabs/stairs/fences/trapdoors/glass panes — things that "look standable by tag but actually have a collision box".

This pack currently uses a rule-table-driven approximation: the block below `isValidSpawn` (solid top face ∧ light emission <14) + feet/head `isValidEmptySpawnBlock` + size-derived neighbor/third-block checks (`$sel.wide/wide2/tall`). The remaining gap is exactly that class of partial blocks, plus the "light emission condition", plus per-type AABB offsets (a narrow, elongated creature's AABB is not proportional). To be exact there are only two paths: ① use block tags such as `#full_collision` to exclude slabs/stairs separately (cheap, covers most); ② hand-write the AABB box check per entity (expensive).

### Q6 Is "spawn cost" the same as spawn potential?

Yes, the same thing. The vanilla data structure is `MobSpawnSettings.MobSpawnCost { energy_budget, charge }`, together with `PotentialCalculator`:

```java
// each candidate mob applies a force charge / r to its surroundings; once the accumulation exceeds energy_budget it is rejected
calc.getPotentialEnergyChange(pos, charge).getChange() > 0  ⇒ reject
```

In 1.21.6 only two biomes fill in a non-empty `spawn_costs`: `warped_forest` (enderman) and `soul_sand_valley` (skeleton/ghast/enderman). This pack implements it: one `energy_budget` per biome, and for each candidate point it accumulates `Σ(1/r) ≤ budget/q²` bucketed by distance (6 distance tiers).

Not done: vanilla is a continuous integral (computing `charge/r` for each nearby mob at its real radius), while this pack is a bucketed discrete approximation, numerically equivalent to the tier precision.

### Q7 What is "merging the species tables covered by worldgen"?

Biome `spawners` belongs to worldgen data. If a map's own datapack overrides `data/<ns>/worldgen/biome/*.json` (or adds custom biomes), our roster (generated from vanilla `biome/*.json`) goes stale: vanilla replaces the whole registry entry wholesale (not a field-by-field merge), and new biomes are entirely absent from our table.

The correct approach (not done): add `--worldgen <directory>` to the generator, merge/override these JSON files on top of vanilla before generating the roster, and add new biome entries to `biome/detect`. Current state: every biome table and the "candidate biome" enumeration in the pack come from vanilla 1.21.6; when a map ships its own worldgen, the author must tell us manually.

---

## 2. v4.15: The Group Data Layer (a SpawnGroupData Replica)

### Why it is needed

The last parameter of `finalizeSpawn` is `SpawnGroupData`; `NaturalSpawner` binds several mobs of the same cluster into one "family": the first one creates the groupData and the rest reuse it. `/summon` passes `null`, degenerating all shared semantics into "each one randomizes independently":

| Fact | Vanilla (with groupData) | `/summon` only (groupData=null) |
| --- | --- | --- |
| Zombie baby | The whole group shares one 5% decision (`ZombieGroupData`) | Each one rolls 5% on its own (a cluster mixes ones with and without) |
| Animal babies | The first is an adult, members 2+ roll by chance (`AgeableMobGroupData`) | There are never babies (groupSize is always 0, so the condition never holds) |
| Fox/axolotl | Members 3+ are always young (`groupSize>=2`) | Always adults |
| Wolf/fox/axolotl/horse/llama variant | Same cluster, same color (decided by the first) | Each one randomizes independently |
| Spider potion effect | Same cluster, same effect (`SpiderEffectsGroupData`) | Each one 10% on its own |

### How it is implemented

Generator `tools/gen_group.mjs` (new in v4.15, 140 files):

| Artifact | Role |
| --- | --- |
| `grp/init.mcfunction` | Macro dispatch: `$function doom.nats:grp/init/$(slug) with storage doom.nats:sel` |
| `grp/init/<slug>` | Once per group (after `spawn/pick_one` first picks the species): rolls the whole group's shared items (zombie baby / spider effect / variant) and zeroes `$grp.mem` |
| `grp/mem/<slug>` | At each member's spawn (inside `post/<slug>`, in the `@s` context): applies the baby/variant/effect, and at the end `$grp.mem += 1` |
| `grp/fx_apply` | Macro function: converts the effect name in `storage doom.nats:grp fx` into `active_effects` and applies it |
| `post/<slug>` | ① `data merge entity @s $(nbt)` (this pack's tag/rule NBT) ② `$cfg.persist` global persistence ③ random facing ④ call `grp/mem/<slug>` |
| `predicate/grp/biome/*` | The biome conditions the variants need (cold/warm livestock, white/gold rabbit, snow fox, the wolf's 8 biomes) |

The probabilities and decisions all follow the source:

- Zombie: `getSpawnAsBabyOdds = nextFloat() < 0.05` → `random value 1..100 matches ..5`; non-baby groups explicitly clear `IsBaby:0b` (because `execute summon`'s single roll may just have given it the baby state).
- Animal: `AgeableMobGroupData(boolean)` has a default chance of `0.05`; the explicit overrides are `Dolphin 0.1 / Panda 0.2 / Strider 0.5 / PolarBear 1.0 / Ocelot 1.0`; `RabbitGroupData super(1.0F)`; `HorseGroupData/LlamaGroupData super(true)=0.05`; the threshold is `groupSize > 0`, i.e. the first is always an adult. Integer approximation: `random value 1..10000 <= round(chance*10000)`.
- Fox/axolotl: `groupSize >= 2 ⇒ setAge(-24000)`, and `AgeableMob`'s increment happens after the check ⇒ members 3+ (`$grp.mem matches 2..`).
- Spider: `difficulty == HARD ∧ nextFloat() < 0.1 * special`, `setRandomEffect = nextInt(5)` (0,1 speed 40% / 2 strength 20% / 3 regeneration 20% / 4 invisibility 20%). A datapack cannot read the difficulty, so `$cfg.difficulty` is added; `special` takes `$cfg.special` (-1 = automatic by difficulty: normal 75%, hard 100%).
- Shared variant: the first one's roll matches vanilla (rabbit per `SPAWNS_WHITE_RABBITS` (80/20) / `SPAWNS_GOLD_RABBITS` / otherwise 50:40:10; fox per `SPAWNS_SNOW_FOXES`; axolotl uniformly among the 4 common ones; wolf per the registry's 8 biomes + the pale fallback; horse `Variant.values()` 7 kinds; llama 4 kinds), and the rest reuse it. The horse's `Variant` is a composite value of "variant | markings<<8"; only the low 8 bits are replaced to preserve each one's own `Markings` (bit operations are done with multiplication/division by 256, since scoreboards have no bit-operation instruction).

### New configuration keys (see docs/18 for details)

| Key | Default | Note |
| --- | --- | --- |
| `difficulty` | `2` | 0 peaceful / 1 easy / 2 normal / 3 hard. A datapack cannot read the game difficulty; the spider group effect needs it |
| `special` | `-1` | Regional difficulty multiplier percent (`DifficultyInstance.getSpecialMultiplier`'s 0..1). `-1` = automatic (normal 75%, hard 100%, easy/peaceful 0). Vanilla computes it per chunk from world time / moon phase / chunk residence time, which a datapack cannot observe |

### Wiring points

- `spawn/group`: `$grp.inited = 0`
- `spawn/pick_one`: after picking the species, `grp/init` (once per group)
- `spawn/emit`: `execute summon … run function post/$(slug) with storage doom.nats:sel`
- `sel` gains `slug` (written in both places: the biome table and the nether fortress table)

---

## 3. Verification

| Assertion | Method | Result |
| --- | --- | --- |
| T1 zombie group baby rate 5% | Call `grp/init/zombie` 2000 times directly | 5.05%~5.70% (multiple runs; expected 5%±1.5%) ✅ |
| T2 the whole group shares one baby decision | Spawn one group each with `$grp.baby=1/0` | Baby group 5/5 all young; adult group 0/8 ✅ |
| T3 the first is an adult + members 2+ by chance | Cow 400 times (clearing the field each round), polar bear 4 times | First 0/1 ✅; cow members 2+ 6.5% ✅; polar bear 4/4 ✅ |
| T4 fox members 3+ are always young | 3 each with `$grp.mem=1/2` | mem=1 → 0/3; mem=2 → 3/6 (cumulative) ✅ |
| T5 wolf same group same variant | 4 wolves + explicitly setting the group variant to snowy (the test point's biome does not satisfy snowy) | 4/4 all snowy ⇒ group sharing works (instead of vanilla's independent randomization) ✅ |
| T6 spider 10% group effect + shared application | `grp/init/spider` 1000 times + 2 in the same group | 9.10%~10.20% ✅; both in the group carry invisibility (duration:-1) ✅ |
| T7 random facing | 24 zombies sampled 12 times with `sort=random` | 11 distinct yaws ✅ |
| T8 the `execute summon` macro dispatch chain + tags + the persistence switch | Call `spawn/emit` directly | Tag 1/1 ✅; `$cfg.persist=1` → 1/1 ✅ |

Script: `_work/verify_group.mjs` (real-machine RCON).

## 4. Still Not Replicated / Known Deviations (Honest List)

1. The world spawn 24-block exclusion (Q1: unobservable, needs the author's declaration).
2. Structure `spawn_overrides` other than `nether_fortress` (Q2). → Added (v4.17 / P1-6): `pillager_outpost` / `swamp_hut` /
   `monument` / `ancient_city` / `trial_chambers`, 5 in total (vanilla has 6 structures with a non-empty `spawn_overrides` in all). See §7.4.
3. Per-candidate-point biome (Q4: a performance compromise; the special rules and the variant layer are unaffected).
4. Exact AABB (Q5: partial blocks such as slabs/stairs/glass panes can still be misjudged as valid). → The cheap version is done (v4.17 / P1-7):
   ① lower support = `#standable ∪ #full_collision` (`Block.isFaceFull` semantics); ② the body/above explicitly excludes water/lava/snow
   (`#minecraft:replaceable` transitively includes them ⇒ a whitelist alone would wrongly accept them); ③ neighbor-block AABB lets through "centered narrow strips" via `#narrow_partial`
   (fence/fence gate/wall/iron bars/glass pane/chain/torch/lantern/flower pot/candle/button…): a wide-bodied mob's AABB only reaches 0.2 blocks into the neighbor block, geometrically not far enough to touch them.
   Per-entity exact AABB (intersection by width/height) is still not done. See §7.5.
5. The continuous integral of spawn cost (Q6: a bucketed approximation).
6. Roster merging for a map's own worldgen (Q7).
7. `populateDefaultEquipmentEnchantments` / `MOB_SPAWN_EQUIPMENT` (`by_cost_with_difficulty` enchanting, which requires replicating the enchantment cost model; and when `special=0` the probability is 0 anyway).
8. AI memory initialization (`PiglinAi/CamelAi/FrogAi/GoatAi.initMemories`, `Fox.setTargetGoals`, `Warden`'s BRAIN memories, `Shulker` facing, etc.) — these are runtime memories that NBT cannot express.
9. Brain memories (`PiglinAi/CamelAi/FrogAi/GoatAi.initMemories`, `Warden`'s `DIG_COOLDOWN`); real-machine testing on 2026-09-28 corrected this: `Brain` really is in entity NBT (`/data get entity <e> Brain` ⇒ `{memories:{}}`), memory items with a codec can be written and the ttl takes effect (`data merge … {Brain:{memories:{"minecraft:dig_cooldown":{value:{},ttl:200L}}}}` ⇒ reads back consistently, still present after 1.2s; script `_work/verify_brain_nbt.mjs`). "Not expressible" holds only in three places: ① these initMemories already ran inside `/summon`/`execute summon`'s finalizeSpawn, so redoing them is meaningless; ② sensor memories (such as `nearest_visible_player`) are recomputed every tick, so writing them in means they are overwritten the next tick; ③ pure Java fields/object references and the Goal list (`AbstractSchoolingFish.leader`, `Fox.setTargetGoals()`) are not data.
10. Halloween pumpkins (`LocalDate.now()` reads the real date; a datapack has no calendar). The 25% pumpkin heads of `Zombie`/`AbstractSkeleton` only take effect on 10/31 each year; this pack does not replicate it.
11. Schools (`SchoolSpawnGroupData`: salmon/cod "tagging along") and pure AI behaviors such as the `Phantom` anchor point.
12. ~~A detail deviation in the group data: this pack rolls the shared variant at the candidate point where the species is first picked, while vanilla rolls at the position of the first mob that actually spawns; within the same cluster the two usually differ by only a few blocks.~~ → Fixed (v4.17 / P0-3): the roll was deferred to `grp/var/<slug>` (called by `post/<slug>` when the first one spawns, at the position = that one's spawn point). See §7.1.

---

## 5. v4.15 Hard Lessons (All Experienced, Written Into lint / the Docs)

1. The gap is the group data passed to `finalizeSpawn`, not `finalizeSpawn` itself: `/summon` and `execute summon` both go through
   `SummonCommand.createEntity(..., EntitySpawnReason.COMMAND, true)`, and that final `true` is "call `finalizeSpawn(..., groupData = null)`
   once on the Mob". The single-mob level equipment/variant/baby/jockey/attributes already ran in vanilla; the only thing we have to add is the
   `SpawnGroupData` that `NaturalSpawner` passes in.
2. A macro line (starting with $) must contain at least one $(name): when the whole line has no placeholder, the function fails to load with
   `IllegalArgumentException: No variables in macro`, and the entire function is unusable (not just that line). Measured:
   `$execute store result storage … run random value 0..359` made the whole `spawn/emit` file fail to load; the same content without the
   `$` prefix is fine. lint L12 has been added to catch it.
3. Animal young state uses `Age` (int), not `IsBaby`: `AgeableMob.addAdditionalSaveData` writes `Age`/`ForcedAge`;
   only classes that implement `setBaby` themselves, such as zombie/piglin/zombified hoglin, use `IsBaby` (boolean). Giving a cow `data merge {IsBaby:1b}`
   is a no-op (measured: 400 cows, 0 young).
4. The macro parameter source for group data must be consistent: the $(v)/$(fx) inside `grp/mem/<slug>` come from `doom.nats:grp`, while `post/<slug>` is
   called by `spawn/emit` with `sel` ⇒ when calling `grp/mem` you must explicitly pass `with storage doom.nats:grp`, otherwise the variant line is missing its parameters and
   the whole function instance fails (the entity still spawns, but the group data is not applied; 0 foxes and wolves that "seemed to pass" were both caused by this).
5. Test infrastructure needs anchors too: mcauto's "load-time errors" check used to scan the whole run.log, so historical failures permanently polluted the conclusion (a line-count anchor has been added);
   verify scripts that need a player now exit directly when nobody is online (regress now starts a mineflayer bot itself); when the chunk containing a distant entity is not loaded,
   `kill` is a no-op, so clearing the field must come before `forceload remove`.
6. Parallel verification on the same machine must use separate ports: this doom.nats run used 25565/25575, while another workspace's doom.ui acceptance used 25566/25576.
7. Regression criteria: `regress.mjs --reuse --minutes 1 --curve 1` → 16 PASS / 0 FAIL (report
   `reports/回归-2026-09-28045848.md`, not in this repository); the group data layer's dedicated `_work/verify_group.mjs` → 14 PASS / 0 FAIL.


---

## 6. The Worldgen Risk of Q4/Q7 and Its Protection (added 2026-09-28, including one unfinished measurement)

Mechanism (which must be considered together when implementing "per-candidate-point biome"): `execute if biome ~ ~ ~ <id>` goes through `Level.getBiome(pos)`,
and when the position falls in an unloaded chunk the server must raise that chunk to the BIOME stage before it can answer ⇒ one probe may trigger chunk loading/worldgen cost.
Although the candidate points are all anchored near the player (`pos/*` starts from the player/chunk context), `band.mode 0`'s vertical scan and distant candidates can still go out of bounds.

The suggested protection (not yet implemented; higher priority than continuing to add fidelity): add an
`execute if loaded <pos>` check before the call sites of `biome/detect_at` and `biome/detect`, and skip the probe when unloaded (in that case vanilla semantics would not spawn at that point anyway ⇒ both fidelity and avoidance of chunk pulling).
```mcfunction
# Illustrative: probe only at loaded positions
execute if loaded ~ ~ ~ run function doom.nats:biome/detect_at
```

The unfinished measurement (honest record): I wrote a measurement script for "the detection cost at a distant point (900,64,900)", to determine ① whether the probe forces a chunk to load
② whether a second call is cheap (one-time generation vs steady-state cost). The script produced no result: the RCON connection in `node -e` had no `close/process.exit`,
so the process hung until the tool's wall-clock timeout (10 minutes). That was a bug in my tool script, not a datapack problem. To rerun: it must end with `process.exit(0)`,
and first record the load state before and after the probe with `execute if loaded`.

Q7 (a map's own worldgen) and "experimental worldgen": our 65 `biome-index` entries and the roster all come from vanilla worldgen;
if a map ships/overrides `worldgen/biome/*.json`, the index table goes stale (the symptom is "not included ⇒ 0 spawns", with no error).

✅ Implemented and finished on a real machine (2026-09-28 18:26–18:34, see `reports/验证-世界生成覆盖-20260928.md`; that report is not in this repository):

- `tools/apply_worldgen.mjs` (`--worldgen <directory containing data/>` repeatable / `--reset` / `--status`) merges the map's
  `data/<ns>/worldgen/biome/*.json`'s `spawners` / `spawn_costs` / `creature_spawn_probability` into
  `_work/generated/biomes.json` (the registry entry is replaced wholesale, not merged field by field), then `export_rosters` + regenerate.
- `tools/regress.mjs --worldgen <directory>` (Q7 ④): one command runs the whole regression "with overrides", and when it finishes it automatically `--reset`s back and reads the sha1 back for verification.
- The pitfall of the experimental switch (measured): when a flat world's `generator-settings.biome` points to a custom biome, the probe measures `if biome` = NO
  (that biome never entered the world registry, and `level.dat.enabled_features` only has `minecraft:vanilla`) ⇒ the test would be all 0 and the conclusion invalid.
  Using a vanilla biome as the override target sidesteps this (the override semantics are exactly the same), without touching `enabled_features`.
- Four-phase real-machine numbers (A/B/A): P1 vanilla +91 spawns (70 spiders on the field) → P2a overridden to an empty table (= RC4 map semantics) +0 and `reason=8` +1884
  → P2b overridden to husk (a species vanilla plains does not have) +59 and all 70 on the field are husk, other species 0 → P3 restored +51 (68 spiders).
  `$snap.biome`/`$sel.biome` stayed at `41` (the plains index in the table) across all three phases ⇒ the difference can only come from the roster ✓.
- Two real bugs were caught and fixed along the way (see `AGENTS.md` v4.18):
  ① A single-category biome's `mob/biome/<biome>.mcfunction` did not explicitly set `$catid` ⇒ it inherited the previous biome's value ⇒ random whole regions spawned nothing
  (7 vanilla biomes were affected: the 5 in the `the_end` family + `deep_dark` + `the_void`); a new lint L14 blocks recurrence.
  ② The generator only wrote and never deleted ⇒ after a roster change, "ghost" category files remained (2 `mob/biome/wgtest/**` were measured in a user's save); now it cleans up after writing + `--check` detects extra files.

Still to do (honest record): the measurement script for the detection cost at a distant point still produced no result (a bug in the script itself: the RCON had no `close/process.exit` ⇒ it hung until the wall-clock timeout).
To rerun: it must end with `process.exit(0)`, and first record the load state before and after the probe with `execute if loaded`.

---

## 7. v4.17: The P0-3 Group Variant Roll Point + One Real-Machine-Class Despawn Layer Bug

> This section records the first batch of changes from the 2026-09-28 "fidelity backlog". Every conclusion comes with a source line number and a red→green number; nothing is written as "looks normal".

### 7.1 P0-3: The shared variant is rolled "when the first one actually spawns" (aligned with where SpawnGroupData is created)

Source evidence (`_work/decomp/out/net/minecraft/world/level/NaturalSpawner.java`):

- `:186` `$$17 = $$26.finalizeSpawn($$1, $$1.getCurrentDifficultyAt($$26.blockPosition()), EntitySpawnReason.NATURAL, $$17);`
- This line comes after `isValidPositionForMob($$1, $$26, $$24)` at `:254` (`$$26` = the one Mob that actually spawned successfully this time),
  so the SpawnGroupData is created by "the first individual of this group to actually spawn successfully", and the biome/position its roll reads is that individual's `blockPosition()`.
- The rest of the group reuses the same groupData (the next loop iteration after `:187` passes `$$17` back) ⇒ the shared variant/baby/effect is "once per group".

The old implementation's deviation: `grp/init` (= the candidate point where this group first picked the species) rolled the shared variant. Between that candidate point and "the first individual to actually spawn"
lie: the first candidate point possibly being rejected for light/placement/capacity, plus the few blocks of intra-group random walking `nextInt(6)-nextInt(6)`. At biome boundaries
(the wolf's 8 biome conditions, the fox's snow condition, the rabbit's white/gold tags) this picks the wrong variant.

The new implementation (`tools/gen_group.mjs`):

| File | Responsibility |
| --- | --- |
| `grp/init/<slug>` | Writes only the fallback value (= the default branch when no vanilla biome condition hits) + `$grp.vneed=1`, does not roll |
| `grp/var/<slug>` | The roll itself, guarded by `$grp.vneed==1`; after rolling, `$grp.vneed=0` ⇒ strictly "once per group" |
| `post/<slug>` | First `function grp/var/<slug>`, then `function grp/mem/<slug> with storage grp` (③a/③b) |

Why the roll must sit in `post` rather than inside `grp/mem` (the macro instantiation pitfall hit this round, the same class as §5.2):
`grp/mem/<slug>` is a macro function, whose `$(v)` is read from `doom.nats:grp` at the moment of instantiation ⇒ if the roll were written in the function body,
the first member's instantiation would fail because `v` does not exist yet (`Missing argument v`: the entity still spawns, but the entire group data layer is not applied).

Red→green (`_work/verify_group.mjs`, real-machine RCON, local instance 25571/25581): 22 PASS / 0 FAIL. The new assertion T5b uses
`/fillbiome` to create two biome regions (A=forest ⇒ wolf variant `woods`; B=plains ⇒ `pale`, mutually exclusive, so the conclusion is deterministic rather than statistical):

| Assertion | Method | Result |
| --- | --- | --- |
| T5b-0/0b | The two biome regions take effect + record the original biomes (restored at the end) | Test passed ✓ |
| T5b-1 | init in region B ⇒ `grp v` does not exist, `$grp.vneed=1` (proving init no longer rolls) | `Found no elements matching v` ✓ |
| T5b-2 | init in region B, the first in region A ⇒ all 4 of the group | 4/4 `woods` ✓ (rolling independently in region B could not produce woods) |
| T5b-3 | The reverse: init in region A, the first in region B ⇒ 2 of them | 2/2 `pale` ✓ (the one in region A would be woods if each rolled independently) |
| T5b-5 | Counter-check: put the roll back at the init position (region B) ⇒ the first spawns in region A | The result is `pale` ⇒ under the old semantics T5b-2 must go red ✓ |

### 7.2 A real-machine-class bug: the despawn layer's `distance` reference point is not the player ("spawned mobs vanish immediately")

Symptom: `_work/verify_persist.mjs` ① "this pack's spawns exist, 0 alive" (red); `verify_animals`'s counts do not match.

Localization chain (reproducible):
1. Actual world spawn read from `level.dat` = `(-592, 66, -272)`; the test bot is at `(-640, 61, -688)` ⇒ about 418 blocks apart.
2. Spawning 1 non-persistent zombie at the same position with the same `sel`: it vanishes within 0.6 s; setting `$despawn_period` to `200000` (stopping `despawn/tick`)
   ⇒ the same one stays alive (it only loses health to vanilla suffocation, 20→17→…).
3. Root cause: the bare `distance` in `despawn/tick`'s `execute as @e[tag=…,distance=129..] run function util/void_kill`
   references the function's execution position; this function is called by `core/tick`, and `core/tick`'s execution context is `minecraft:tick`'s
   world spawn. ⇒ As long as the player is >128 blocks from the spawn point (which in normal play is almost always), every non-persistent mob this pack spawns is
   silently `void_kill`ed within one despawn beat (20 ticks by default).

Vanilla semantics (`Mob.checkDespawn()`): `Entity p = level.getNearestPlayer(this, -1.0); d² = p.distanceToSqr(this);`
⇒ the reference point is always the nearest player; only `d² > despawnDistance²` triggers `discard()`.

Fix (`tools/gen_despawn.mjs`, both the hard and probabilistic despawn paths changed):

```mcfunction
execute as @a[gamemode=!spectator] at @s as @e[tag=…spawned,tag=!…persistent,nbt=!{PersistenceRequired:true},distance=129..] unless data entity @s Passengers run function …:util/void_kill
```

Per-player judging ≡ vanilla's "nearest player": a mob is skipped as soon as it is within 128 blocks of any player, and only removed once it is out of range for every player.
(When no player is online no judging happens, and at that point vanilla also only judges chunks that still hold tickets.)

Red→green numbers: `verify_persist` ① "0 alive" ⇒ 10 PASS / 0 FAIL (① alive 1);
`verify_animals` "③`$cnt.creature`=10 / manual 17" ⇒ 6 PASS / 0 FAIL (`$cnt.creature=10 / manual 10`).

### 7.3 Lessons (appended to the pitfall list)

- A bare `@e[…,distance=N..]` in a datapack (and any predicate that depends on the execution position) references "the function's execution position";
  `minecraft:tick`'s context = the world spawn (on a dedicated server). To express "around a certain player" you must use `as @a at @s as @e[…]`.
  This and "an @e without position constraints crosses dimensions" are two faces of the same pitfall: the position context must be established explicitly.
- Absolute coordinates in test scripts go stale: after a player is pushed by spawns, `execute positioned <old coordinates>` lands in an unloaded chunk,
  and `execute summon` still instantiates the entity and runs `post/<slug>` (the scoreboard still increments), but `tryAddFreshEntityWithPassengers`
  discards it because the chunk is not loaded ⇒ selectors cannot find it and "total = 0". Verification scripts should always use player-relative coordinates + entity tag counting.
- A macro function's parameters must be in place before the call: roll → write storage → then call the macro function; values that differ per member (such as the horse's composite Variant)
  must be split into a separate macro function (`grp/apply/<slug>`), otherwise the first one fails the whole function due to missing arguments.

### 7.4 P1-6: The remaining structures' `spawn_overrides` (`ChunkGenerator.getMobsAt`)

Data (copied verbatim from `server-1.21.6.jar`'s `data/minecraft/worldgen/structure/*.json`): of the 34 structures only 6
carry a non-empty `spawn_overrides`: `fortress` (which already has a dedicated branch) / `pillager_outpost` / `swamp_hut` / `monument` /
`ancient_city` / `trial_chambers`.

Semantics and implementation: `getMobsAt` is the final arbiter of "which species should spawn at this position". As soon as the position hits a structure's override entry for the current category,
the biome table is replaced wholesale (an empty table ⇒ `getRandom` returns empty ⇒ `NaturalSpawner` `break`s the whole group).
This pack hangs the check at the start of every "biome × category" table (`return` early exit), rather than inside `pick_one`:
only at the table level is it known "which category was picked this time", and vanilla's override decision matches by category exactly.

| Structure | Category | Override table | This pack's artifact |
| --- | --- | --- | --- |
| pillager_outpost | monster | pillager 1..1 (full) | `mob/struct/pillager_outpost_monster` |
| swamp_hut | creature / monster | cat 1..1 / witch 1..1 (piece) | `mob/struct/swamp_hut_{creature,monster}` |
| monument | monster / axolotls / underground_water_creature | guardian 2..4 / empty / empty (full) | `mob/struct/monument_monster` + empty-table early exit |
| ancient_city | all 8 categories | empty (full) | table header `return 0` |
| trial_chambers | all 8 categories | empty (piece) | table header `return 0` |

Known approximation: `location_check.structures` is "inside the structure (the overall bounding box)", while `swamp_hut`/`trial_chambers` declare
`piece` (the specific pieces) in vanilla ⇒ this pack is slightly wider than vanilla (the gaps between pieces may also match). The decision order for overlapping structures is fixed at
outpost → swamp_hut → monument → ancient_city → trial_chambers (vanilla iterates a map, so the order is undefined).

Real-machine red→green (`_work/verify_struct_overrides.mjs`, 8 PASS / 0 FAIL):
S1 inside an outpost the monster table ⇒ `minecraft:pillager` (min/max 1/1); S5 outside the structure +400 blocks as a control ⇒ the biome table is used (spider);
S2a/S2b swamp_hut ⇒ `cat` / `witch`; S3 monument ⇒ `guardian` (2/4); S4 ancient_city (monster+ambient) and
trial_chambers (monster) ⇒ `$sel.ok` stays 0 (empty table).

The key pitfall of the red→green run (caught on a real machine): `guardian` is not in any biome roster (vanilla only gets it from the structure override) ⇒ the rule table cannot find its
rule id, and the template wrote JS's `undefined` straight into the artifact: `scoreboard players set $sel.rule doom.nats undefined`
⇒ a load-time `Expected integer at position 89`, and the whole function failed (the load gate went red). Fix: fold `guardian/pillager/cat/witch`
into `EXTRA_RULE_TYPES` and add rules for `cat`/`pillager`; also add lint L13 (ERROR): a bare `undefined`/`NaN` must not appear in an artifact,
to catch this class of "JS value leaking into the artifact".

### 7.5 P1-7: The cheap AABB version (`#full_collision` / `#narrow_partial`)

The two vanilla steps to replicate (the last link of `NaturalSpawner.isValidSpawnPostitionForType` and `isValidEmptySpawnBlock`):

```java
// ① empty-space check
if (state.isCollisionShapeFullBlock(level, pos)) return false;      // full collision ⇒ not an empty space
if (state.isSignalSource()) return false;
if (!fluid.isEmpty()) return false;                                  // fluid ⇒ not an empty space
// ② size check (what the cheap version targets)
level.noCollision(type.getSpawnAABB(x + 0.5, y, z + 0.5));           // AABB ∩ block collision shapes = ∅
```

This pack's three changes (all in `gen_check.mjs`; `LEGACY_AABB=1` generates the "before" version for comparison):

1. Lower support: `#standable` is a historical whitelist; it is now unioned with the new `#full_collision` (full collision cubes, 144 entries, with
   `standable ⊆ full_collision` guaranteed by construction) ⇒ full blocks outside the whitelist (glass/iron block/quartz/ore/stone brick variants…) are no longer wrongly rejected.
   Where the criterion comes from: `BlockBehaviour$BlockStateBase:536 isFaceSturdy(...,UP)` (the 3-arg version) = `SupportType.FULL` ⇒
   `Block.isFaceFull(shape.getFaceShape(UP))` ⇒ only a full cube (plus states whose UP face is full, such as a top slab or an upward stair) counts as standable.
2. Body/above (spawnable empty space): `#minecraft:replaceable` transitively includes `water`/`lava`/`snow` ⇒ a whitelist alone would wrongly accept them;
   now 6 exclusions are added explicitly (water/lava/snow × body/above) × place 0/1/4.
3. Neighbor-block AABB (the core of the cheap version): a new `#narrow_partial` (fence/fence gate/wall/iron bars/glass panes 17 kinds/chain/torch/lantern/end rod/
   lightning rod/button/lever/tripwire hook/flower pot/candle) as the let-through list: a wide-bodied mob (spider width 1.4) has an AABB that only reaches 0.2 blocks into the neighbor block,
   geometrically not far enough to touch these "centered narrow strips", so vanilla would not reject it, while the old whitelist-based implementation wrongly did.
   `tall` (the third block) is not let through: that block is occupied by the creature's own body, so a narrow strip intersects it anyway.

Real-machine before/after comparison (`_work/verify_aabb_cheap.mjs`, 23 scenarios; baseline = the v4.16 rules generated with `LEGACY_AABB=1`):

| Scenario | Before | After | Note |
| --- | --- | --- | --- |
| A2 below = glass | reject | pass | full collision but not in the old whitelist ⇒ wrongly rejected |
| B2 body = water | pass | reject | fluid ⇒ vanilla's `isValidEmptySpawnBlock` rejects outright |
| B3 body = snow layer | pass | reject | a snow layer has a collision box (0..2/16) ⇒ vanilla's AABB would reject |
| C1 neighbor fence | reject | pass | a centered narrow strip, cannot reach the AABB edge strip |
| C2 neighbor glass pane | reject | pass | same as above |
| C3 neighbor iron bars | reject | pass | same as above |
| C4 neighbor wall | reject | pass | same as above |
| C5 neighbor torch | reject | pass | same as above |
| C6 neighbor bottom slab / C7 neighbor stone / C8 neighbor leaves | reject | reject | fills 1×1 (or a full cube) ⇒ the edge strip hits it, must reject |
| D1/D2/D3 third block (own column) fence/stone/glass pane | reject | reject | any non-empty space in one's own column blocks the head (not let through) |
| Total | 6 pass / 17 reject | 10 pass / 13 reject | 3 wrong acceptances fixed, 6 wrong rejections fixed |

---

## 8. Correction to §7.4: The piece / full Semantics of `spawn_overrides` (2026-09-28, With Decompile Evidence)

The sentence in §7.4 that "`location_check.structures` is 'inside the structure (the overall bounding box)'… this pack is slightly wider than vanilla" had the direction backwards; corrected here:

- `StructureManager` (this time `StructureManager.class` was extracted from `named.jar` and decompiled on its own):
  - `getStructureAt(pos, structure)` (:102-110) = `StructureStart.getBoundingBox().isInside(pos)` ⇒ the overall bounding box (full)
  - `getStructureWithPieceAt(pos, …)` (:112-140) and `structureHasPieceAt` (:142-150) = iterate `start.getPieces()` and test each bounding box ⇒ piece level (piece)
- In `LocationPredicate` (:53), `structures` goes through `getStructureWithPieceAt` ⇒ a datapack's `location_check.structures` = piece level,
  synonymous with the piece branch of `ChunkGenerator.getMobsAt`'s `BoundingBoxType.PIECE ? structureHasPieceAt : start.getBoundingBox().isInside`.

The corrected, accurate conclusion:

| Structure | Vanilla `bounding_box` | This pack (piece-level predicate) | Verdict |
|---|---|---|---|
| `swamp_hut` (creature/monster) | `piece` | piece | exactly identical ✓ (the "slightly wider" claim in §7.4 does not hold) |
| `trial_chambers` (8 empty category tables) | `piece` | piece | exactly identical ✓ |
| `fortress` (monster 5 entries) | `piece` | the JSON one is not implemented (only the hardcoded one was done) | gap (see below) |
| `ancient_city` (8 empty category tables) | `full` | piece | too loose: the ring inside the overall box but outside the pieces falls back to the biome table ⇒ it spawns, while vanilla does not |
| `monument` (monster 1 entry etc.) | `full` | piece | same as above (the ring uses the biome table instead of the structure table) |
| `pillager_outpost` (monster 1 entry) | `full` | piece | same as above |

The fortress has two paths; do not implement only one (`NaturalSpawner.mobsAt` :276-290):

```java
return isInNetherFortressBounds(pos, level, cat, sm)   // hardcoded: cat==MONSTER ∧ below is NETHER_BRICKS ∧ getStructureAt(full) valid
     ? NetherFortressStructure.FORTRESS_ENEMIES
     : chunkGenerator.getMobsAt(biome, sm, cat, pos);   // otherwise the JSON override is used (fortress: monster 5 entries / piece)
```

This pack has exactly replicated the hardcoded path (`mob/fortress.mcfunction` + `pick_one`'s `if block ~ ~-1 ~ minecraft:nether_bricks`),
but has not done the fortress's JSON override. Its effective window is monster spawning "inside the fortress's overall box, with something other than nether bricks underfoot" (slightly wider than vanilla).

Correction to the backlog: the original P1-6 entry "replace the overall bounding box with piece" does not need to be done (it was already piece ✗); what should be recorded is two things:
① the 3 `full` structures (ancient_city / monument / pillager_outpost) cannot be expressed by a datapack (there is no full-level API) ⇒ an unreachable gap, which can only be declared in the documentation;
② the fortress's JSON override (piece / monster 5 entries) is not implemented ⇒ it is implementable, listed as to do.

---

## 9. P1-6b Implementation Result: Both Fortress Paths Completed + One Per-Category Bug (2026-09-28)

Background: after §8 corrected piece/full, the fortress exposed two things:

1. Missing JSON path: vanilla's `NaturalSpawner.mobsAt` has two paths, "hardcoded first, then `getMobsAt`"; this pack only did the hardcoded one
   (`nether ∧ NETHER_BRICKS underfoot ∧ in_fortress`), so a position "inside the fortress with something other than nether bricks underfoot" falls back to the biome table, whereas vanilla
   uses the fortress's JSON `spawn_overrides` there (`monster` / `piece`).
2. A per-category bug (fidelity): the old implementation put the fortress check at the `spawn/pick_one` level, which does not yet know which category was picked
   ⇒ even `creature` / `ambient` attempts inside the fortress were swapped to the monster table (more mobs spawned, and the species the biome should have were lost).
   Vanilla calls `mobsAt(cat, pos)` by category, so non-monster categories still use the biome table inside the fortress (the fortress JSON only declares `monster`).

The fix (two generators; artifacts are not hand-edited)

- `gen_mobs.mjs`: `STRUCT_OVERRIDES` gains `fortress: { monster: { ref: 'mob/fortress' } }`,
  and `structPreambleLines` supports `{ ref }` (reusing the existing table, to avoid the two tables drifting apart. In vanilla these two tables are field-by-field identical:
  `NetherFortressStructure:21-27` vs `fortress.json`).
  In the artifacts, each `mob/biome/<biome>/monster.mcfunction` gains one extra structure preamble line:
  `execute if predicate doom.nats:spawn/in_fortress run return run function doom.nats:mob/fortress`
- `gen_spawn.mjs`: remove the fortress-specific, category-blind branch from `pick_one` (4 lines → 1 line of pure `biome/dispatch`).

Real-machine red→green (`_work/verify_struct_aabb.mjs`'s section B rewritten, 12 PASS / 0 FAIL):

| Assertion | Result |
|---|---|
| B1a inside the fortress + nether brick ground ⇒ the monster channel yields the fortress table (vanilla's hardcoded path) | ✅ one of five: blaze/magma_cube/skeleton/wither_skeleton/zombified_piglin |
| B1b inside the fortress + non-nether-brick ground ⇒ still the fortress table (vanilla's JSON path, newly added this time) | ✅ same five |
| B1c inside the fortress ⇒ the creature channel falls back to the biome table (fixing the per-category bug; vanilla only overrides monster) | ✅ `strider` |
| B1d the fortress table's exclusive markers (blaze / wither_skeleton) really appear in one sample | ✅ brick=5 species / stone=5 species |
| B2 outside the fortress ⇒ the biome table, and fortress-exclusive species never appear | ✅ ghast / piglin / zombified_piglin |

Approximations still in place (restating §8): vanilla path ① uses the overall bounding box (full) and path ② uses piece, while a datapack only has the piece-level API
⇒ "inside the fortress box, outside the pieces, nether bricks underfoot" is a ring that this pack will fall back to the biome table for. It is an unreachable gap, already recorded in §8.

## 10. The `in_fortress` Jitter Closed: The `isLoaded` Gate + forceload Coordinate Units (2026-09-29 · v4.22d)

After §8 corrected the piece/full semantics, the fortress end-to-end case still left one "`in_fortress` ~17% load-state jitter at the same position (to be investigated)". This round closed it:

1. Engine semantics (source evidence): in `LocationPredicate#matches` (1.21.6 decompiled `LocationPredicate.java:49-53`),
   `boolean loaded = level.isLoaded(pos);` short-circuits both the `biomes` and the `structures` predicates, so it is always false when the chunk containing the position is not loaded.
   Vanilla only attempts spawning inside loaded and ticking chunks, so the production path never hits this; this pack calls the engine predicate directly ⇒ identical to vanilla, no pack change needed.
2. Test-bench bug: `forceload add <x> <z>` takes block coordinates; the old script passed `Math.floor(X/16) ± 4` (chunk coordinates) ⇒
   it force-loaded completely unrelated chunks (passing `-45,-44` in fact marked `chunk[-3,-3]`), so the fortress chunk was never force-loaded — that was the real reason "it was still `loaded=false` after forceload".

Numbers: controlled reproduction (isolated instance · 200 times at the same point) unloaded `0.0%` / force-loaded `100.0%` / mixed `40.0%` (per point anything non-zero counts as 100, no jitter);
end-to-end (main server 25565 · the same fortress): both this morning's acceptance gate (old script) and today's rerun (new script + a hard `loaded` assertion) gave off-table `0/24 = 0.0%`, 3 PASS / 0 FAIL; the "~17% jitter" was a record from an earlier round (before the criterion converged).
(The isolated instance's `1/24 = 4.2%` was an environment-difference reading, with 0 spawns over 4200 rounds, so it is not taken as evidence.)
The script now has a hard assertion "after force-loading, read `loaded` back, and `exit 1` if it is not satisfied" (no longer relying on the bot's view distance as a fallback).
See `reports/诊断-in_fortress抖动-20260929.md` (not in this repository).
