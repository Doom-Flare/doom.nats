# Changelog · doom.nats (v4 · Vanilla Natural Spawning Replica)

中文: `CHANGELOG.md`

> Scope: this table records only the v4 line (datapack-driven replication of vanilla natural spawning + the Circumstance engine + the despawn layer).
> v3 (the replica map pack `早期作品线`) and `ported/` `optimized/` belong to another line.
> Target environment: Minecraft 1.21.6 · Fabric (`pack_format` 80).
> Each entry = what changed · why · checkable numbers.
> Engineering discipline, the real-hardware test bench, and the per-round evidence reports live on the author's machine (not distributed with this repo);
> Note: the author rule layer `rules/` was once moved out of this repo (it is a build-time input and only takes effect after regeneration); since 2026-09-29 it has returned to this repo alongside the source under `src/rules/`; for the field tables and examples see [`src/rules/README.md`](src/rules/README.md).
> Note: the timestamps of v4.19–v4.22 are all 2026-09-29 (continuous iteration on the same day); `v4.21b` is only referenced inside v4.22d (the forceload unit problem),
> and has no version section of its own.

---

## v4.31.0 · Two missing checks in air spawning, and a gate that could never hit zero — 2026-10-25

> All three changes sit on the geometry and the cadence of the spawn chain: the distance gate ignored categories, the anchor followed the player's height, and the passive-mob 400-tick gate could never reach zero.
> After the fix, with the player hovering at y=200 and everything else unchanged, the same 90-second window goes from 0 to **5259** successful spawns (with `creatureGate` set to 1 to exercise the creature channel alone).
> Also fixed: `mode/off` claimed to retire the pack, but the pack kept summoning.
> And the experimental variant had been stuck on a stale build (776 files, 5 functions missing and 8 files regressed); it is rebuilt to 781 here.

### 1 · What was wrong

None of these are in the rule layer; all three are preconditions for "should this spawn at this point at all".

| # | Location | Old behavior | Vanilla semantics | Consequence |
|---|---|---|---|---|
| ① | `check/distance` | one flat 128-block cap for every category | `despawnDistance` is **per category** (`WATER_AMBIENT` = 64, the other six = 128), and `canSpawnFarFromPlayer()` (= `CREATURE` \|\| `MISC`) skips the check entirely | passive mobs got an invented 128-block ceiling; `water_ambient` was allowed out to 128 where vanilla says 64 |
| ② | `pos/band` mode 0 | y anchored on **the player's height**, scanning dy = +2 .. −16 | `NaturalSpawner.getRandomPosWithin`: `y = random(level.getMinY(), chunk.getHeight(WORLD_SURFACE, x, z) + 1)` — completely independent of the player's height | with the player high up the whole window is air; probes measured a 100% fallback rate and a 1–3% placement hit rate |
| ③ | `core/creature_tick` | `gametime % 400` sampled once per 20 ticks, inside `circ/snapshot` | `getGameTime() % 400 == 0` checked every tick | `gametime` advances by 1, sampling advances by 20 ⇒ the phase is frozen and `$gt` ranges over exactly `{17, 37, 57, …, 397}`, **never 0** ⇒ not a single passive mob ever spawns |

### 2 · Why all three had to be fixed together

They mask each other; fixing one alone shows no measurable effect:

- Fix ③ only: `$gt` reaches 0, but candidate points still hang off the player's height — spawning works on the ground and is still zero in the air.
- Fix ② only: the anchor moves to the surface, but the passive channel is still stuck behind a gate that never opens — placement is right, the category roll never picks it.
- Fix ① only: `water_ambient` distances align, passive mobs still do not spawn.

On-hardware comparison (superflat, vanilla spawning disabled with `doMobSpawning=false`, noon, `creatureGate=1`):

| Player y | Before: Δ`$spawned.total` in 90 s | After |
|---|---|---|
| 200 (hovering) | 0 | **+5259** |
| 64 | 0 | +76 |
| −60 (on the ground) | 0 | +61 |

After the fix the cliff edge at y=200 is gone too: the old build dropped to 0 from y=68 up, the new one spawns anywhere from 64 to 200.

### 3 · What changed

| File | Change |
|---|---|
| `check/distance` | Rewritten to 14 lines: the 24-block gate is unchanged → default `$chk.dist = 128` → `check/dist_pick` reads `$cfg.dist_<cat>` per category → **`creature` is exempt** and only the rest go through `check/dist_gate` |
| `check/dist_pick` | **New** (macro, `with storage doom.nats:sel`): reads the bound for `$(cat)` out of `$cfg.dist_<cat>` |
| `check/dist_gate` | **New** (macro, `with storage doom.nats:dg`): `unless entity @a[gamemode=!spectator,distance=..$(dist)]` ⇒ `check/fail {reason:2}` |
| `pos/band_surface` | **New**: when mode 0's first pass finds nothing, `positioned over motion_blocking_no_leaves` moves the anchor to that column's surface |
| `pos/band_surface_at` | **New**: reads the surface y back through a temporary marker (no command writes the execution position into a scoreboard), taking over only when `$band.sy < $py` |
| `pos/band_surface_scan` | **New**: the 19-layer scan anchored on the surface; on a hit it converts the offset to an absolute y and writes it to `$py` |
| `pos/band` | 231 → 280 lines (generator-side): the 19 scan lines became reusable `anchorLines`, and mode 0 now calls `pos/band_surface` |
| `core/creature_tick` | Called every tick now; the gate became a window `$eff.period` wide — `$gt.now = gametime % $cfg.creature_gate` → `$gt = $gt.now - $eff.period` → negative means open, `0..` means closed |
| `core/tick` | `function doom.nats:core/creature_tick` added right after `add $t` (it used to live in `circ/snapshot`) |
| `circ/snapshot` | Lost the `creature_tick` call and the `$creature_gate` copy (that variable is read nowhere in the pack) |
| `src/tools/gen_{check,pack,pos,spawn}.mjs` | Synced with all five artifacts above |

The gate is a window rather than an equality check on purpose: the spawn tick at `$spawn_t % $eff.period == 0` need not land on the exact tick where `gametime % 400 == 0`, and an equality gate would drop the whole cycle. The window is `period` wide (default 5), so 5 consecutive ticks are open every 400.

> ★ The order of the two gate lines must not be swapped: inside the window `$gt` comes out negative, and clamping it to 0 first means the `0..` check immediately closes the gate (measured on hardware: `$gt` stuck at 1 forever). Close first (`0..` → 1), then open (`..-1` → 0).

### 4 · `mode/off` now really retires the pack

`mode/off` used to only clear mobs and hand `doMobSpawning` back to vanilla, **with no stop flag at all**, while `spawn/batch` inside `core/tick` had no mode gate — so the pack kept summoning after `mode/off`. The docs (16 / 21 / 24 / 25 and the wiki install page) all describe it as retiring the pack; the code did not.

| Item | Change |
|---|---|
| New stop flag | `$mode.off` (scoreboard `doom.nats`) |
| `core/tick` | Returns from the whole function right after `add $t`; `$t` keeps counting (the minute settlement in `ctrl/settle` depends on it), and nothing else runs: no spawning, no snapshot, no capacity scan, no despawn |
| `mode/off` | Sets `$mode.off = 1` |
| `mode/survival` | Sets `$mode.off = 0` (`mode/auto` reuses survival and therefore unlocks too) |
| `core/setup` | Auto-takeover on load now requires `unless $mode.manual` **and** `unless $mode.off` — otherwise `/reload` flips `doMobSpawning` back to false while `core/tick` is still returning, leaving neither vanilla nor the pack spawning |

On hardware (1.21.10): after `mode/off`, `$mode.off=1`, `doMobSpawning=true`, `$spawn_t` reads a constant 2 across samples (frozen), and `$t` still climbs; after `/reload` it is still frozen and `doMobSpawning` is still true; both `mode/survival` and `mode/auto` unlock it and restore the cadence.

### 5 · Along the way: the experimental variant had drifted

`pack/doom.nats-experimental` had **been sitting on a previous generation**: 776 files, and of the 704 files it shares with the default variant **251 differ** — `core/creature_tick` was 4 lines (the old build), `mode/off` 5 lines, `core/tick` 32 lines, none of them carrying this version's three fixes or the stop flag. Under `DOOM_EXP=1` four generators reported drift outright.

After the rebuild it is **781 files** (+5, −0, 8 modified), the `exp/*` layer is still the same 77 files, and all 12 generators report a clean `--check`.

### 6 · The Four Gates

| Gate | Result |
|---|---|
| Generators agree | `gen_pack` / `gen_pos` / `gen_check` / `gen_spawn` plus the other 8: `--check` clean for both the default and the experimental build |
| Static gate | **0 error / 2 warning** on both (the pre-existing "macro line without a with call" warnings in `check/fail` and `debug/light_fail`) |
| Leak gate | 0 hits |
| 12-version matrix | **12/12 `pass=14 fail=0 total=14`**: 1.21.5 / 1.21.6 / 1.21.7 / 1.21.8 / 1.21.9 / 1.21.10 / 1.21.11 / 26.1 / 26.1.1 / 26.1.2 / 26.2 / 26.3, zero load errors each, 28–32 s per version |
| On-hardware spawning | Default settings agree across `$cnt.creature` and `@e[type=#doom.nats:creature]`; with `cap.creature` raised to 200 the pack spawned 96 in 120 s and the field held 106 (sheep 20 / cow 12 / pig 28 / chicken 26 / horse 17 / donkey 3), and the entity NBT carries `doom.nats.cat.creature` `doom.nats.near128` `doom.nats.spawned` |

> Measuring note: `$spawned.total` feeds the minute settlement in `ctrl/settle`, so a short-window delta may not match what actually spawned. Read `$cnt.creature` or count entities instead.

### 7 · Deliverables

| File | Applicable versions | Entries |
|---|---|---|
| `doom.nats-v4.31.0.zip` | 1.21.6 (baseline) | 705 |
| `doom.nats-v4.31.0-mc1.21.5.zip` | 1.21.5 | 705 |
| `doom.nats-v4.31.0-mc1.21.6-1.21.8.zip` | 1.21.6 to 1.21.8 | 705 |
| `doom.nats-v4.31.0-mc1.21.9-1.21.10.zip` | 1.21.9 to 1.21.10 | 705 |
| `doom.nats-v4.31.0-mc1.21.11-26.2.zip` | 1.21.11 to 26.2 | 705 |
| `doom.nats-v4.31.0-mc26.3.zip` | 26.3 | 705 |
| `doom.nats-v4x-experimental-v4.31.0.zip` | Experimental variant | 781 |

Every package is byte-identical to its `ports/` directory (the baseline package to `pack/doom.nats` plus `mcdoc/`).
## v4.30.1 · the 26.3 package's `pack.mcmeta` is back to its true values — 2026-10-24

> Metadata only, no behavior change: `data/` is untouched byte for byte, and all five range packages' mcfunction / JSON are identical to v4.30.0.
> What changed is the `pack.mcmeta` inside `doom.nats-v4.30.0-mc26.3.zip`: it claimed `pack_format 94` / `min_format [94,1]` / `max_format 121`,
> while 26.3's real `pack_format` is **121**, and 26.3 is hard-incompatible with ≤26.2 (see below). This ships as a PATCH because the artifacts changed.

### 1 · What was wrong

The 2026-10-05 erratum (after v4.29-multiversion) split `-mc1.21.11-26.3` into `-mc1.21.11-26.2` and `-mc26.3`,
but only the zip **contents** were rebuilt; the `pack.mcmeta` in the `ports/` tree and the `VARIANTS` table that generates it stayed in the pre-split shape:

| Item | v4.30.0's `-mc26.3` | Corrected in v4.30.1 |
|---|---|---|
| `pack_format` | 94 | **121** |
| `min_format` | `[94, 1]` | `[121, 0]` |
| `max_format` | `121` | `[121, 0]` |
| Version string in `description` | `[v4 · 1.21.11–26.3 · …]` | `[v4 · 26.3 · …]` |
| `ports/` directory | `ports/doom.nats-1.21.11-26.3/` | `ports/doom.nats-26.3/` |

For reference: v4.29's `-mc26.3` package was already `121 / [121,0] / [121,0]` — the mislabel came in with the v4.30.0 rebuild.

### 2 · Why this had to be fixed

26.3 and ≤26.2 have a renamed `predicate` registry key (`condition` → `type`), and the two are **hard-incompatible in both directions**, asymmetrically:

| Wrong-way install | Result |
|---|---|
| ≤26.2 package → 26.3 server | Won't even start: `IllegalStateException: No key type in MapLike[{"condition":…}]` → `Registry Loading` fails |
| 26.3 package → ≤26.2 server | Starts and plays, but **all 68 predicates silently break** (`Failed to parse either. First: No key condition in MapLike[{"type":…}]`), and the self-test drops from 14 to 13 — miss `total` and you'd call it a pass |

So declaring 94 on the 26.3 package tells 1.21.11–26.2 players "this fits you too".
It won't be refused — it will quietly break a large slice of the rules. That direction **does more damage than a hard refusal**, so the lower bound has to be 121.

### 3 · What changed

| File | Change |
|---|---|
| `ports/doom.nats-26.3/` | Added (700 files), produced by the rebuild script, including the hand-written `mcdoc/doom.nats/config.mcdoc` |
| `ports/doom.nats-1.21.11-26.3/` | Removed (700 files); that directory only existed in the v4.29 / v4.30.0 generations |
| `dist/doom.nats-v4.30.1-mc26.3.zip` | Rebuilt, 576944 B; unzipped against v4.30.0's same-named package: 700 vs 700 files, the only difference is `doom.nats/pack.mcmeta` |
| The other 6 zips | Renamed only (`v4.30.0` → `v4.30.1`), sha256 identical bit for bit |
| `dist/SHA256SUMS.txt` | 26 lines; seven new `v4.30.1` entries, and 2 retired packages are left out of the list (their files stay in `dist/`, same as the v4.29 erratum) |

### 4 · Documentation fixed along the way

- `docs/25-兼容与版本.md` / `.en.md`: the 26.3 row's `pack_format` in the matrix, 94 → **121** (the only wrong cell in that matrix; the README version table was always right)
- `docs/18-配置手册.md` / `.en.md`: the experimental artifact's entry count, 771 → **777** (measured)
- Every "current version" reference across the repo: `v4.30.0` → `v4.30.1` (README download and version tables, docs index, the tag segment of the wiki download links, each manual's `dist/` reference, the `src/README` file-count table, the credits footer)
- Historical prose is untouched: the v4.30.0 CHANGELOG section, the `v4.25/v4.28/v4.29/v4.30.0` enumerations, and the version history table in `docs/wiki/版本与验收`

### 5 · The Four Gates

| Gate | Result |
|---|---|
| Static gate (default + experimental) | 0 error / 2 warning |
| Zero load-time failures | 26.3 on a real server: `load errors = 0` |
| Real-hardware assertions | 26.3 on a real server: `pass=14 fail=0 total=14` |
| zip byte-identical to the pack tree | The new 26.3 zip matches `ports/doom.nats-26.3` file by file |
| sha256 alignment | Local, `SHA256SUMS.txt`, and the Release attachment agree |

> The other 4 range packages and the baseline package were **not** re-run through the matrix: `data/` is unchanged, their contents are byte-identical to v4.30.0, and v4.30.0's all-green 12-version result still holds.

### 6 · Deliverables

| File | Applicable versions |
|---|---|
| `doom.nats-v4.30.1.zip` | 1.21.6 (baseline) |
| `doom.nats-v4.30.1-mc1.21.5.zip` | 1.21.5 |
| `doom.nats-v4.30.1-mc1.21.6-1.21.8.zip` | 1.21.6 to 1.21.8 |
| `doom.nats-v4.30.1-mc1.21.9-1.21.10.zip` | 1.21.9 to 1.21.10 |
| `doom.nats-v4.30.1-mc1.21.11-26.2.zip` | 1.21.11 to 26.2 |
| `doom.nats-v4.30.1-mc26.3.zip` | 26.3 |
| `doom.nats-v4x-experimental-v4.30.1.zip` | Experimental variant |

## v4.30.0 · Quantity Tiers (scale) — 2026-10-07

> This version adds a set of quantity knobs: no rule changes, no species changes, only "how many can spawn at most".
> One command switches the spawning scale to half, one and a half times, two and a half times, or four times, and it survives `/reload`.

### 1 · New: Quantity Master Switch `qty`

| Item | Value |
|---|---|
| Config key | `qty` (written into `doom.nats:config`) |
| Meaning | A percentage. `100` = as-is, `50` = halve every category's cap, `200` = double it |
| Valid range | `1` to `1000` |
| Affects | Only scales the **capacity caps** (each category's `maxInstancesPerChunk`) |
| Does not affect | Spawning cadence. Speed has its own three knobs: `density` / `batch` / `period` |

Written the same way as any other config key:

```
/data modify storage doom.nats:config qty set value 150
/function doom.nats:cfg/apply
```

### 2 · New: Five One-Key Tiers

If you don't want to compute percentages, use these five functions. They write the value into the config layer, and it is still there after `/reload`.

| Command | `qty` | Effect |
|---|---|---|
| `/function doom.nats:scale/sparse` | 50 | Caps halved |
| `/function doom.nats:scale/normal` | 100 | Back to vanilla |
| `/function doom.nats:scale/dense` | 150 | One and a half times |
| `/function doom.nats:scale/horde` | 250 | Two and a half times, and also speeds up the spawn cadence |
| `/function doom.nats:scale/extreme` | 400 | Four times |

After switching, a chat message says which tier is active. To go back to vanilla, run `scale/normal`.

### 3 · Filled In: Capacity Counting (the v4.28 performance rework)

The previous version's `ports/` used a generator snapshot missing the capacity counting, so the artifacts were short 5 function files and didn't match the pack already shipped in `dist/`. This version fills them in:

- `check/caps_formula`, the capacity formula (`maxInstancesPerChunk × spawnableChunkCount / 289`)
- `check/caps_scan`, capacity counting, one whole-map box query per dimension per tick
- `check/cnt_overworld` / `cnt_the_nether` / `cnt_the_end`, per-entity dispatch by category

Performance numbers: box queries dropped from 21 per second to 3. On real hardware a single box selection measures about 71 to 75 ms; before the rework that amplified to about 1.47 s/s, after it about 0.21 s/s.

### 4 · Documentation Fix: `mcdoc` Gains `qty`

`mcdoc/doom.nats/config.mcdoc` is the config type declaration meant for editors. The previous version added `qty` but missed it; this version adds it.
The experimental variant's pack also carries this file for the first time (previously only the default variant had it).

### 5 · Rule-Layer Documentation Fix: the Measure of `weight`

The description of `weight` in `src/rules/README.md` was wrong. It used to say
"competes in the same pool as vanilla entries" — measured, that isn't so.

The actual measure: the hit rate is approximately `weight / 1000000`. For your own entries to really spawn,
you have to write hundred-thousand-scale numbers. Writing a small number like `40` is the same as not spawning.

The examples were updated to match: the weight in `src/rules/examples/full/entries.json` changed from `120` to `100000`.

### 6 · Real-Hardware Acceptance

All conclusions come from real hardware: Fabric server + `/reload` + the in-pack self-assertion suite.
The verdict standard is `pass/fail` plus `total == 14`, plus zero across all 8 classes of load errors.

| MC version | Load errors | Self-test |
|---|---|---|
| 1.21.5 | 0 | `pass=14 fail=0 total=14` |
| 1.21.6 | 0 | `pass=14 fail=0 total=14` |
| 1.21.7 | 0 | `pass=14 fail=0 total=14` |
| 1.21.8 | 0 | `pass=14 fail=0 total=14` |
| 1.21.9 | 0 | `pass=14 fail=0 total=14` |
| 1.21.10 | 0 | `pass=14 fail=0 total=14` |
| 1.21.11 | 0 | `pass=14 fail=0 total=14` |
| 26.1 | 0 | `pass=14 fail=0 total=14` |
| 26.1.1 | 0 | `pass=14 fail=0 total=14` |
| 26.1.2 | 0 | `pass=14 fail=0 total=14` |
| 26.2 | 0 | `pass=14 fail=0 total=14` |
| 26.3 | 0 | `pass=14 fail=0 total=14` |

### 7 · The Four Gates

| Gate | Result |
|---|---|
| Static gate (default + experimental) | 0 error / 2 warning |
| Zero load-time failures | 0 across all 12 versions |
| Real-hardware assertions | `pass=14 fail=0 total=14` across all 12 versions |
| zip byte-identical to the pack tree | All 7 zips pass |
| sha256 alignment | Local, `SHA256SUMS.txt`, and the Release attachment agree |

### 8 · Deliverables

| File | Applicable versions |
|---|---|
| `doom.nats-v4.30.0.zip` | 1.21.6 (baseline) |
| `doom.nats-v4.30.0-mc1.21.5.zip` | 1.21.5 |
| `doom.nats-v4.30.0-mc1.21.6-1.21.8.zip` | 1.21.6 to 1.21.8 |
| `doom.nats-v4.30.0-mc1.21.9-1.21.10.zip` | 1.21.9 to 1.21.10 |
| `doom.nats-v4.30.0-mc1.21.11-26.2.zip` | 1.21.11 to 26.2 |
| `doom.nats-v4.30.0-mc26.3.zip` | 26.3 |
| `doom.nats-v4x-experimental-v4.30.0.zip` | Experimental variant |

## v4.29-multiversion · Multi-Version Support (1.21.5 → 26.3) — 2026-10-05

> This version is a pure port: not one line of function logic was touched; it only makes the same pack load and run correctly on 12 versions from 1.21.5 to 26.3,
> and delivers it as 4 packages with truthful ranges. The cross-version differences concentrate in 4 hard breaks (see "Porting Matrix" below).
> All conclusions come from real-hardware acceptance (Fabric server + `/reload` + the in-pack self-assertion suite), not from static inference.

### 1 · Multi-Version Support Table

| MC version | data pack version | Delivered pack (`dist/`) | `min_format` / `max_format` | Real-hardware acceptance |
|---|---|---|---|---|
| **1.21.5** | 71 | `doom.nats-v4.29-mc1.21.5.zip` | `[71,0]` – `[71,0]` | ✅ `pass=14 fail=0 total=14` |
| **1.21.6** | 80 | `doom.nats-v4.29-mc1.21.6-1.21.8.zip` | `[80,0]` – `81` | 🟡 Inferred (same range) |
| **1.21.7 / 1.21.8** | 81 | `doom.nats-v4.29-mc1.21.6-1.21.8.zip` | `[80,0]` – `81` | ✅ `pass=14 fail=0 total=14` (1.21.8 measured) |
| **1.21.9 / 1.21.10** | 88.0 | `doom.nats-v4.29-mc1.21.9-1.21.10.zip` | `[88,0]` – `[88,0]` | ✅ `pass=14 fail=0 total=14` |
| **1.21.11 – 26.2** | 94.1 – 107.0 | `doom.nats-v4.29-mc1.21.11-26.2.zip` | `[94,1]` – `[107,0]` | ✅ `pass=14 fail=0 total=14` (5 versions measured) |
| **26.3** | 121.0 | `doom.nats-v4.29-mc26.3.zip` | `[121,0]` – `[121,0]` | ✅ `pass=14 fail=0 total=14` |

> The baseline is unchanged: `dist/doom.nats-v4.29.zip` (the original v4.29 default variant, aimed at 1.21.6) is preserved byte for byte,
> and its sha256 is identical to the previous commit (`883ff3eb…bc38`), so existing players are unaffected by upgrading.
> Companions: `dist/doom.log-multi.zip` (the logging channel, all ranges) and `dist/doom.nats-selftest.zip` (the self-assertion suite, all ranges).

### 2 · Hard-Break Fixes (4 classes hit across 12 versions)

| # | Break | Affected versions | What changed |
|---|---|---|---|
| 1 | Vanilla ID rename: `minecraft:chain` → `minecraft:iron_chain` | 1.21.9 onwards | Switched to the new ID in the narrow-judgment tags (the 1.21.5–1.21.8 variants still use `chain`) |
| 2 | Entity ID addition: `minecraft:happy_ghast` | Present from 1.21.6 | `legacy` (for 1.21.5 only) **removed** this entry; the 1.21.6+ variants keep it |
| 3 | **gamerule rename** (snake_case): `doMobSpawning` → `spawn_mobs` | **1.21.11** onwards | `mode/survival` and `mode/off` switched to the new name (the old name gives `Incorrect argument for command` on that version, and the whole function fails to load) |
| 4 | predicate schema change: `condition` → `type`; the inner layer of `light` flattened; `time` value `daytime` → `day` | 26.3 | 68 predicates rewritten field by field |
| 5 | **New `pack.mcmeta` rules** | 1.21.9 onwards | The new variants declare `min_format`/`max_format` explicitly, and **tighten them to the measured boundary** (see §3) |

### 3.1 · ★ Erratum: `1.21.11 – 26.3` Is Not a Single Range (the old asset has been pulled)

- The defect: §1's original table merged 1.21.11 – 26.3 into one `doom.nats-v4.29-mc1.21.11-26.3.zip` ✗
  It straddled two different break boundaries (gamerule rename = 1.21.11 · predicate schema = 26.3),
  ⇒ the middle stretch 1.21.11 / 26.1 / 26.1.1 / 26.1.2 / 26.2 was in fact covered by nobody ✗.
- Real-hardware evidence (installing that asset as-is into these 5 versions): after `/reload`, 8 classes of load errors totaled 732
  (`Failed to load function` 244 · `Whilst parsing` 488), suite `pass=13 fail=0 total=13`
  — ★ note that `fail=0` looks all-green ✗: in fact the whole batch of functions containing assertions never loaded, and only "`total` == expected 14" revealed the failure ✓.
- Root cause (located line by line): inside that variant, 68 predicates used the new form `{"type":"minecraft:location_check", …}`,
  while 1.21.11–26.2 accepts only the old form `{"condition": …}` ⇒ all 68 predicates failed to register ⇒ 244 functions referencing them failed along with them.
- The fix: split into two packages with truthful ranges:
  - `doom.nats-v4.29-mc1.21.11-26.2.zip` (new variant: old-style `condition` + new-style `spawn_mobs` + `iron_chain`, `[94,1]`–`[107,0]`)
  - `doom.nats-v4.29-mc26.3.zip` (the former `-mc1.21.11` variant, now meaning exactly 26.3, new-style `type`, `[121,0]`–`[121,0]`)
- Boundary experiment (the hardest evidence): installing the 26.3 variant on 1.21.10 really does fail (742 errors, 13/13)
  ⇒ proving the two boundaries neither overlap nor leave a gap — it is not "either side can muddle through" ✓.
- Re-verification: the new variant was measured on 1.21.11 / 26.1 / 26.1.1 / 26.1.2 / 26.2, all `pass=14 fail=0 total=14`,
  all 8 classes of errors 0, and the five artifacts' sha256 identical bit for bit ✓.
- Release-surface handling: the old asset on the GitHub Release `doom.nats-v4.29-mc1.21.11-26.3.zip` (downloaded once)
  was mislabeled and leaving it up would make people install a broken pack ⇒ it has been pulled and replaced by the two packages above ✓.

### 3 · Fix: Two `pack.mcmeta` Files That "Claim a Wider Range Than They Can Actually Do"

- The defect (original values):
  - `doom.nats-multi-1.21.9`: `min_format [88,0]` / `max_format 94`, while that variant only covers 1.21.9–1.21.10 (data 88.0).
  - `doom.nats-multi-legacy`: `min_format [48,0]` / `max_format 81` / `supported_formats{48,81}`, while it only covers 1.21.5 (data 71).
- Real-hardware evidence (1.21.11, `pack_data = 94.1`): installing the unmodified `1.21.9` variant as-is ⇒ the pack is accepted, then
  `Failed to load function doom.nats:mode/survival` and `mode/off`, two `Incorrect argument for command … gamerule` errors
  ⇒ the self-declared range "touched" a version it actually can't run on.
- `max_format` granularity semantics (double-checked on real hardware + bytecode): the integer form equals `PackFormat(v, 0)` (minor defaults to 0),
  and comparison goes major first, then minor ⇒ `(94,0) < (94,1)`. Also note: measured, on a dedicated server that range is not a load gate
  (`max_format` of 87/88/93/94 all get force-enabled) ⇒ the real point of tightening is "honest metadata + the client-side datapack selection UI doesn't mislead".
- The fix: `1.21.9` → `[88,0]`–`[88,0]`; `legacy` → `[71,0]`–`[71,0]` and delete `supported_formats` (a narrow range doesn't need it, and it must match min/max value for value).
- Re-verification after the fix: 1.21.5 `pass=14 fail=0 total=14` (0 load errors) · 1.21.10 `pass=14 fail=0 total=14` (0 load errors).

### 4 · Real-Hardware Acceptance Evidence

- The three-part verdict (all required): `pass/fail` + `total == expected(14)` + zero across all 8 classes of load errors
  (`Failed to load function` / `Whilst parsing` / `Macro without` / `No variables in macro` / `Invalid NBT path` /
  `Incorrect argument for command` / `Failed to load datapacks, can't proceed` / `Registry loading errors`).
- The verdict follows the summary line: `[SELFTEST] RESULT pass=14 fail=0 total=14` (not "no ERROR in the log" — measured, real failure lines don't contain the ERROR keyword).
- Four machines measured: 1.21.5 ✅ · 1.21.8 ✅ · 1.21.10 ✅ · 26.3 ✅ (all 14/14, 0 errors).
  After this round's mcmeta tightening, 1.21.5 and 1.21.10 were each re-run once, still 14/14.

### 5 · Artifact Fingerprints (sha256)

```
158628810082f9d97c3afd29ddec8ae2f87f8519a342368bfa3bb8b1303bbb60  doom.nats-v4.29-mc1.21.5.zip
7d90b832a6bbd8aa2fbddb6bf04faeb747acc3c33625a5ba4d67e6df14eff038  doom.nats-v4.29-mc1.21.6-1.21.8.zip
511410de0c45bf9d6496ab8f60a4bff2907fe06d17f60b35a0c12c5ce6f896bd  doom.nats-v4.29-mc1.21.9-1.21.10.zip
0e4f03b4ededc93ad8797e72c3806c1cace1b4309a9476c0dc4ca1166b00bc2e  doom.nats-v4.29-mc1.21.11-26.2.zip
9fea4c81e1236fe2c9c939a7571976da7788702750949838f7abfbb5b61e1b44  doom.nats-v4.29-mc26.3.zip
a65873bf49bb1b135b67fe533a883cf8b0fafeca0289be9455eaf32a2c15bd71  doom.log-multi.zip
4ab6836a8dfd19372b4a2d6f7f716f73b76489bb85a504728fe27f0fea42f1bb  doom.nats-selftest.zip
```

> ~~`ebc2d807…7273  doom.nats-v4.29-mc1.21.11-26.3.zip`~~ → pulled (mislabeled range, see §3.1).

The full list is in `dist/SHA256SUMS.txt`.

### 6 · Repository Structure Changes

- Added `ports/`: the pack's own source tree for each version range (`ports/doom.nats-<range>/`, `ports/doom.log/`, `ports/doom.nats-selftest/`),
  for file-by-file comparison; the zips in `dist/` are packed from these trees (the top-level layout inside the zip matches the existing artifacts).
- The top-level `doom.nats/` stays as the default variant (1.21.6 baseline), byte-for-byte corresponding to `dist/doom.nats-v4.29.zip`.

> Not measured / open question: `1.21.6`, `1.21.7`, `1.21.9`, `1.21.11`, `26.1`, `26.1.1`, `26.1.2`, `26.2` were not started as separate servers;
> they sit in the same variant range as measured versions and share all version-related changes ⇒ inferred usable (🟡).

---

## v4.29 · Official Release (Latest) — 2026-10-04

> This version has two faces of the same thing: fixing, together, the examples and presets that the true `weight` measure had misled — ① the `weight:40` in the in-game help and usage comments (written that way, it never spawns) and ② the three custom mobs in the experimental presets `blood_moon` / `storm_season` / `deep_dark` that, by the same measure, almost never appear. Also, two "the docs tell you to run something that doesn't exist" items corrected against the facts. Not one line of generator logic was touched; only values and wording.

### 1 · Fix: the `weight` Example in the In-Game Help (written that way, it never spawns)

- The defect: in the author layer's runtime help and usage comments, the example entry read `weight:40` — in `/function doom.nats:author/help`'s `[2] entry`, in `author/add_entry`'s usage comment, and in `author/demo_run`'s demo entry (`weight:20`). By `weight`'s true measure — "the chance of being selected per attempt when the condition holds ≈ `weight / 1000000`" — `40` ⇒ 0.004%, `20` ⇒ 0.002%: an entry copied straight from this example almost never spawns.
- The fix (only values and wording inside the generator, no logic changes; file `src/tools/lib/author-runtime.mjs`):
  - `add_entry` usage comment: `weight:40` → `weight:100000`, plus two plain-language lines (≈ `weight/1000000`; to really spawn, write hundred-thousand-scale)
  - `help`'s `[2] entry` example: `weight:40` → `weight:100000`
  - `demo_run` demo entry: `weight:20` → `weight:100000`
  - `help` gains a gold hint line: `⚠ weight：条件成立时每次尝试被选中概率 ≈ weight/1000000，要真刷出来就填 10 万级（40 ⇒ 0.004%，等于永远不刷；100000 ⇒ 10%）。多条目同时成立按声明顺序吃区间。`
- The mechanism (why `40` doesn't spawn): the hit interval `#off..#hi` is computed at the small magnitude of "vanilla weight sum + weight", but what gets compared is the not-yet-moduloed `$rng` (`random value 0..999999`); `$rng %= #wsum` happens after this comparison ⇒ only the stretch of dice values of length = `weight` out of 0..999999 can hit. Real-hardware comparison: `40` ⇒ 0.004% (≈ never spawns) · `90` ⇒ 0.009% (0 in 90 seconds) · `100000` ⇒ 10% · `900000` ⇒ ≈90% (blazes 22 → 32 in 180 seconds).
- Documentation side: the **repo-wide correction** of the `weight` measure was done in `c3238d8` (the "⚠ the true measure of `weight`" section of `docs/wiki/规则字段参考.md`, `docs/wiki/示例库.md`, `docs/wiki/FAQ.md`, `docs/wiki/已知限制.md`, `src/rules/README.md`); this section fills in **the help text inside the generator that was missed** — the generator writes it into the artifact, so changing the docs can't reach it.

Real-hardware A/B evidence (isolated instance game 25598 / RCON 25608, real client mineflayer 1.21.6 as `@s`; `/reload` 0 load errors, `Failed to load function` 0):

| Artifact | The reply from `/function doom.nats:author/help` |
|---|---|
| Before (`doom.nats-v4.28.zip`) | `[2] 条目：…weight:40,when:{thundering:1b}}…`, and **no** weight-measure hint line |
| After (`doom.nats-v4.29.zip`) | `[2] 条目：…weight:100000,when:{thundering:1b}}…` + the gold line `⚠ weight：条件成立时…≈ weight/1000000…（40 ⇒ 0.004%，等于永远不刷；100000 ⇒ 10%）` |

### 2 · Fix: the Same Wrong `weight` in the Experimental Presets (three of them: `30/25/30` ⇒ `120000/100000/120000`)

- The same class of defect, with a more direct consequence: in the entries of the three built-in presets in `src/tools/gen_exp.mjs`, `blood_moon`'s "blood moon walker", `storm_season`'s "storm hunter", and `deep_dark`'s "deep dark stalker" read `weight: 30 / 25 / 30`. By the same measure (≈ `weight/1000000`) the hit rates are only 0.003% / 0.0025% / 0.003% ⇒ after a player runs `/function doom.nats:exp/preset` to apply a preset, those three custom mobs almost never appear. Presets are meant for one-key application, so they deserved the fix more than the documentation example.
- Why these values: raise the originals by ×4000 into hundred-thousand range, preserving the author's original strength ratio (blood_moon 30 : storm_season 25 = 120000 : 100000) ⇒ **`blood_moon` 120000 (12% per attempt) · `storm_season` 100000 (10%) · `deep_dark` 120000 (12%)**. No new ratio was invented: the author's three entries originally differed by only 5 (≈ no differentiation); raising them just turns "invisible" into "visible" without changing the relative strength between presets.
  Real-hardware A/B evidence (isolated instance game 25602 / RCON 25612, reusing a world with the `minecart_improvements` flag; `/reload` 0 load errors, and `datapack list` shows both `[minecart_improvements (feature)]` and `[file/doom.nats (world)]`):

| Artifact | `data merge storage doom.nats:exp_in {name:"blood_moon"}` → `function doom.nats:exp/preset` → `data get storage doom.nats:exp entries[0]` |
|---|---|
| Before (`doom.nats-v4x-experimental-v4.28.zip`) | `entries[0].id` = `"blood_moon_walker"` · **`entries[0].weight` = `30`** |
| After (`doom.nats-v4x-experimental-v4.29.zip`) | `entries[0].id` = `"blood_moon_walker"` · **`entries[0].weight` = `120000`** |

### 3 · Artifacts and Repository in Sync

- All 12 generators (10 default + 2 experimental) exit 0; `node src/tools/check_static.mjs` ⇒ exit 0 / 0 error / 2 warning (the two warnings are the pre-existing `check/fail` and `debug/light_fail` "contains a macro line but has no `with` call at all").
- Artifact differences checked item by item (unpacking the two versions' zips and comparing sha256 file by file): default variant 694 → 694 items, 0 added, 0 removed, exactly 3 files with different content (`data/doom.nats/function/author/{add_entry,help,demo_run}.mcfunction`); experimental variant 771 → 771 items, 0 added, 0 removed, exactly 9 files with different content (the 3 above + `exp/{add_entry,help,demo_run}.mcfunction` + `exp/preset/{blood_moon,storm_season,deep_dark}.mcfunction`). The generator artifacts are still 693 files default / 770 experimental, plus one hand-written `mcdoc/` ⇒ 694 items in the default zip / 771 in the experimental one.
- `dist/` repacked and checksums recomputed (the four zips from v4.25 and v4.28 are all kept, not deleted):
  - `doom.nats-v4.29.zip` · sha256 `883ff3eb2761079f67f14b7fc33bdf378564bb8e52149257e85c9c72d598bc38` · 569804 B · 694 items; packed once more after the preset change, sha256 unchanged bit for bit (`exp/*` doesn't enter the default variant, so std is entirely unaffected)
  - `doom.nats-v4x-experimental-v4.29.zip` · sha256 `29ec530c2dfdeed7c79c6719ba60bd2f2081f4c16fe2462f49802b6428096af6` · 654270 B · 771 items
  - `dist/SHA256SUMS.txt` lists only these two (2 lines, `<sha256>` + two spaces + filename + LF; independently re-checked with `Get-FileHash`, agreeing).
- The top-level `doom.nats/` in the repo (the pack tree you can click straight into) is synced to v4.29: item-for-item identical to `dist/doom.nats-v4.29.zip` (694/694, 0 missing, 0 extra, 0 with different content); the experimental zip is likewise 771/771 byte-identical to `pack/doom.nats-experimental/` + the hand-written `mcdoc/`.

### 4 · Documentation: Four Places "Telling You to Run a File That Doesn't Exist" Corrected Against the Facts

`dist/` contains only `dist/SHA256SUMS.txt` (each line `<sha256>` + two spaces + filename, recomputed on every release); there is no per-zip checksum file named `doom.nats-*.zip.sha256`. The same issue was corrected earlier in the README; this round swept up the remaining stragglers:

| File | Before (✗ that file doesn't exist) | After (✓ pointing at a checksum that really exists) |
|---|---|---|
| `docs/wiki/安装与升级.md` | `sha256sum -c doom.nats-v4.29.zip.sha256` | `sha256sum -c dist/SHA256SUMS.txt` + a one-line Windows command |
| `docs/25-兼容与版本.md` | `sha256sum -c doom.nats-v4.29.zip.sha256` (Windows: just `Get-FileHash .\doom.nats-v4.29.zip`) | Same two commands as above |
| `docs/wiki/版本与验收.md` | "the two variants' zips…**each with a `.sha256` checksum file**" | "checksums are collected in `dist/SHA256SUMS.txt` (recomputed on every release, listing only the current release's two)" |
| `.github/ISSUE_TEMPLATE/bug_report.yml` | `sha256sum -c doom.nats-v4.25.zip.sha256` (the Issue form still asked for the old v4.25 command) | `sha256sum -c dist/SHA256SUMS.txt` (on Windows, check line by line with `Get-FileHash`) |

- Repo-wide `git grep '\.sha256'` re-check: apart from this section (which describes the "before") and historical sections, nothing remains. Historical entries are left alone.

## v4.28 · Official Release — 2026-10-04

> This version: four things: capacity counting cut to ≈ 7× less total (P0 performance) · the ready message restored (a macro missing an argument had silently dropped the whole function) · **4 more missing-argument cases of the same kind in `debug/*` filled in · the `mcdoc/` missed by the packaging re-added** (present in the v4.25 zip, missed in v4.26–v4.28).
> Local measurement convention: isolated instance 25574 / RCON 25584 · view-distance 10 · Mem Reduct resident (the performance numbers below were taken with it resident).

### 1 · Performance: Capacity Counting Cut to ≈ 7× Less Total, Window tps 13.92 → 20.0x

- The change: capacity scanning went from "7 categories × 3 dimensions = 21 whole-map box selectors / second" to "1 whole-map box per dimension (3 / second), plus new `check/cnt_overworld` / `cnt_the_nether` / `cnt_the_end` dispatching per entity by category tag" — a selected entity judges itself with `@s[type=#doom.nats:<category>]` and adds +1 to each category it matches. The three dimensions each own a phase (1 / 8 / 14), still one round of 20 ticks = 1 Hz. The old selector's `limit=500` saturation semantics are implemented equivalently by capping per entity (510 bats ⇒ `$cnt.ambient` exactly 500, matching the old implementation's `check/caps` reading).
- Reference implementation: `check/caps` (the 21-selector full version) is kept as a debug / verification entry point and does not run on any cadence; its non-comment lines are byte-identical to before the fix, so the equivalence regression uses it as the reference.
- Before → after (same instance, same protocol, back to back): `/reload` → idle 60 s → `tick query` ×3 (15 s apart) → `debug start` → 20 s → `debug stop`
  - Before (the v4.27 split-tick version): `avg 60.1 ms · P50 56.8 · P95 106.9 · P99 139.3 · tps 17.41` (3/3 samples "can't keep up with the target")
  - After: `avg 13.8 ms · P50 3.2 · P95 74.5 · P99 99.4 · tps 20.02` (3/3 "keeps up"); corroborating v4.26 (all 21 selectors crammed into the 1 Hz tick) tps 13.92
  - Total model: `R + 21q/20 = 60.1`, `R + 3q/20 = 13.8` ⇒ one whole-map box ≈ 51 ms, non-capacity overhead ≈ 6 ms/tick ⇒ capacity counting 54.0 → 7.7 ms/tick = 7.0× reduction (avg drops only 4.4× because that ≈6 ms/tick doesn't shrink)
- This round's re-measurement (v4.28 artifact · same recipe · fewer entities on field): `tick query` **P50 0.3 ms · P95 52.2–52.9 ms · P99 57.1–61.5 ms · avg 6.2–6.3 ms (budget 50 ms/tick); `debug stop` window 400 tick / 19.97 s = 20.03 tps (target 20); same-period 10 s profile window (202 tick ⇒ 20.17 ticks/s): `core/tick` accounts for 12.43% of the total**, of which the 3 whole-map boxes are `5.55 + 3.33 + 3.32 = 12.20%`.
  - Don't compare percentages directly across rounds: the previous round's archived figure for the same item was `core/tick 15.26%` / 3 boxes `9.43%`; the box share varies with how many entities are on field. The comparable hard numbers are "box selectors 21/second → 3/second" and "the window tps stays near 20".
- The tail spike still exists: `P95 ≥ 50 ms`, sourced from the capacity scan every 20 ticks + the 3 whole-map boxes; per procedure it is **only marked ⚠, not judged FAIL**; both hard criteria (`avg < 50 ms/tick`, window `tps ≥ 19.0`) pass.

### 2 · Fix: the Ready Message (a macro missing an argument ⇒ the whole function body silently dropped)

- The `function doom.log:info {…}` line at the end of `core/setup` wrote only `message` and omitted `code`. `doom.log:info` is a macro entry point, and the convention is "both the `code` and `message` keys must be written; miss one and the whole function body is silently dropped" (engine behavior) ⇒ the "you'll see a ready message in chat after installing" that the README promises did not in fact appear. After adding `code:"E101"` (configuration / load time), real hardware shows it ✓.

### 3 · Fix: 4 More Missing Macro Arguments in `debug/*` (the same class of defect, found one by one)

All 4 wrote only `message`, so several lines of the `/function doom.nats:debug/all` the README tells people to run were dead:

| Function | code added | Segment |
|---|---|---|
| `debug/dryrun` (first line) | `E911` | E9xx Other (manually triggered diagnostic output) |
| `debug/despawn_report` | `E912` | Same as above |
| `debug/mobs` | `E913` | Same as above |
| `debug/reject_report` | `E914` | Same as above |

The numbering follows `doom.log`'s coding convention: **E1xx configuration/load time · E2xx concurrency/state pollution · E3xx persistence layer/cache · E4xx item/NBT contract · E5xx scheduling/timing · E9xx other/compatibility paths**. Already taken: `E101` (this pack ready), `E201` (`doom.consumable`), `E995–E999` (`doom.test` self-test) ⇒ these four manually triggered diagnostic outputs land in the E91x sub-segment.

A/B real-hardware evidence (same world, same command `debug/all`, only the artifact swapped; both artifacts have 0 load errors on `/reload`):

| Artifact | `doom.log:clear` → `debug/all` → read back `doom.log:data` |
|---|---|
| Before (the previous v4.28 zip) | `{history: []}`, by_code all empty, history all empty (not one of the 4 was recorded) |
| After | `by_code` = **`{E911, E912, E913, E914}`** (each `n:1`) · `history` all 4 present · `last` = `E912` |

Two independent read-backs agree. Archived at `_work/gates/2026-10-04-v429-debugcode-ab.txt` (author's machine, not distributed with the repo).

### 4 · Artifacts and Repository in Sync

- Both variants regenerated: only these 4 files × 2 variants changed (`check_static`'s `--check` byte comparison passes; the generator artifacts are 693 default / 770 experimental, matching the pre-change file set. zip item counts below).
- `dist/` repacked and checksums recomputed:
  - `doom.nats-v4.28.zip` · sha256 `77c2c2e0701cd694bc30ab43c553e605a55e6d11a0c1b592d3f3c36d923f287c` · 569438 B · 694 items
  - `doom.nats-v4x-experimental-v4.28.zip` · sha256 `fdcae6046712cdde539f4ef8184a99ccf800fac9e690413d210571d0b0697a43` · 653542 B · 771 items
  - `dist/SHA256SUMS.txt` lists only these two (2 lines; recomputed once per release).
- The top-level `doom.nats/` in the repo (the pack tree you can click straight into) is synced to v4.28: item-for-item identical to `dist/doom.nats-v4.28.zip` (694/694, 0 missing, 0 extra, 0 with different content). Previously it had stalled at v4.25 (689 files) and carried the ready-message bug above.
  - Packaging-omission fix: the hand-written editor hint `mcdoc/doom.nats/config.mcdoc` (3.5 KB · sha256 `411fe4cb36…`, no generator owns it — the repo maintains it by hand) was in the v4.25 zip but was missed when repacking v4.26–v4.28 ⇒ this round it is back in the packaging flow, and both zips carry it again (default variant 693 → 694 items, experimental 770 → 771 items), and [docs/21](docs/21-玩家可改清单.md)'s wording is restored to "the zip contains `mcdoc/`".
- Gates: `check_static.mjs` default and `--exp` both 0 error / 2 warning (the two warnings are the pre-existing `check/fail` and `debug/light_fail` "contains a macro line but has no `with` call at all").

## v4.25 · Official Release — 2026-09-29

- Status change: `v4.25` moved from pre-release to official and was set as the repo's Latest Release.
- Positioning: this version is the stable version for Minecraft 1.21.6; the non-vanilla experimental capabilities (`near` / `on_spawn` / preset packs) exist only in the `v4x` experimental variant, and installing it requires enabling the matching experimental gameplay when creating the world. Custom appearances (the AJ bridge) are counted separately: the source is in `src/tools/gen_exp_aj.mjs`, but it was not released with this version's artifacts — this repo's `src/rules/rigs.json` is `{}`, and the shipped zip has 0 `exp/aj` entries; to use it you need your own non-empty `rules/rigs.json` (sample `src/rules/examples/aj/rigs.json`) and re-run the generator with `DOOM_EXP=1`.
- Source visible: the generators `src/tools/`, the author rule layer `src/rules/`, and the generation inputs `src/_work/generated/` ship with this repo; to modify the pack yourself, follow the "three-step build" in [`src/README.md`](src/README.md) (run the generators → `check_static` → install/package). The generator's `--check` + lint + reference closure pass in a real clone.
- Artifacts unchanged: the two zips in `dist/` and their sha256 are byte-identical to the previous commit (this version only changed the release conventions and the repo shape).
- Gates: `src/tools/check_static.mjs` default and `--exp` both 0 error / 2 warning; `check_leak.mjs` (including the top-level structure) 0 hits.

## v4.23 – v4.26 · Player-Visible Summary

- v4.23 author rule layer: added three files under `rules/` (per-entity rules / conditional entries / count curves). All empty by default = vanilla behavior; they only take effect once changed.
- v4.24 runtime author layer: rules moved into in-game storage, so a change takes effect the next tick — no restart, no reinstalling the pack (`/function doom.nats:author/show|reset|help`). Non-vanilla capabilities (nearby mobs, spawn effects, preset packs) are made into a separate experimental variant, guarded by the engine gate: if the world hasn't enabled the matching experimental gameplay, it refuses to load.
- v4.25 custom-appearance bridge (experimental): a real entity as the kernel + a skeleton as the appearance (mounted with `ride`); the kernel moves/despawns as usual and the appearance follows block by block (position error 0.0000 blocks), and capacity counts only the kernel. (Source in `src/tools/gen_exp_aj.mjs`, but not released with this version's artifacts: this repo's `src/rules/rigs.json` is `{}` and the shipped zip has 0 `exp/aj` entries; the numbers come from an experimental build with non-empty rigs.)
- v4.26 repository shape cleanup: this repo = player-facing (`dist/` downloads + `docs/` + `rules/`); the generators, test bench, acceptance reports, and CI are the author's machine's business (not distributed with this repo).
- Fixes in the same batch: in the Overworld, the four categories `water_creature / water_ambient / underground_water_creature / axolotls` always read 0 in the global capacity judgment (the capacity gate effectively didn't exist); the orphan file `water_fluid` caused the experimental variant's whole function to fail loading; `data merge` recursively stuck the previous entry's NBT onto the next mob; on 1.21.5+ equipment NBT should be `equipment:{}`.

> Incidentally "fixed" a bug nobody reported and nobody thought was a bug: glow squid can't spawn on grass. 😄 (It's of course not a vanilla bug; it's just that you're now allowed to change it to "can".)

The complete per-version entries and numbers are archived on the author's machine (not distributed with this repo).

> Documentation fix (after v4.25 · 2026-09-29): the "gameplay A (runtime)" examples in the README / docs / Wiki once mixed in build-time field names.
> They have now been aligned with the implementation item by item: the biome in an entry is `biome` (singular) · group size is `min` / `max` · `belowAny` must write the block tag `#minecraft:leaves` ·
> `on_spawn` is a hook switch (`1b`) plus a function file of the same name · source-level switches such as `cluster` / `coins` / `ySea` / `tag` can only be changed at build time. The datapack artifacts themselves were not modified.

## Documentation Upgrade — 2026-09-29 · Hero Section / Compatibility Table / Issue Entry Point / Credits Page / Checksum Line

- Motivation: comparing against 24 similar and generally excellent repositories (the report is on the author's machine at `reports/参考-优秀仓库案例-20260929.md`, not distributed with this repo), three things were filled in: "the first screen is still a wall of text, version compatibility has to be pieced together, reporting a problem has no fixed fields". Only docs and templates changed; the datapack artifacts did not.
- README reorganized: the first screen gains a badge row (latest version / MC version / license) + a hero image slot (placeholder — the image has to be shot in game) + a 30-second three-step table; long-form content such as "more examples" moved to [`docs/wiki/示例库.md`](docs/wiki/示例库.md) and [`docs/24`](docs/24-玩家能改动的一切.md), leaving the README with only "answers" content + a link table.
- Added [`docs/25-兼容与版本.md`](docs/25-兼容与版本.md): a one-page comparison of version × variant × whether experimental gameplay is needed × `pack_format`, covering upgrade/downgrade/variant switch/uninstall, and "why the experimental variant borrows a native flag, and what it costs".
- Added [`docs/26-致谢与许可.md`](docs/26-致谢与许可.md): a license summary (what you can/can't do), third-party boundaries (no Mojang assets included; the custom-appearance bridge only demonstrates the mechanism, and third-party packs such as rigs are not distributed with the pack), credits, and the credit format.
- Added issue forms: `.github/ISSUE_TEMPLATE/` (bug report / feature request / guided configuration). The bug form always collects pack version · variant · MC version and singleplayer-or-server · checksum result · reproduction steps · log excerpt · screenshots.
- Added how to verify the checksum: a one-line two-method answer in the README (`sha256sum -c` / PowerShell `Get-FileHash`) + the current two zips' sha256 values (`cd347370…` / `ddf72ddb…`).
- Added [`docs/图-首屏效果位.md`](docs/图-首屏效果位.md): where the hero image goes, how big, what to shoot, what not to include (including "no screenshots of third-party appearance packs").
- Wiki: `docs/wiki/` is still 9 source pages; the online Wiki repo has not been created yet (GitHub requires clicking "Create first page" on the web once), and the README now has a fallback: "if it won't open, read `docs/wiki/`".

## Wording Cleanup — 2026-09-29 · Making It Player-Readable (removing old abbreviations, repacking)

- Why: internal abbreviations should not appear in the README / docs / Wiki / in-pack descriptions. They were uniformly changed to player-comprehensible phrasings such as "natural spawning replica (datapack-driven)" and "replicating vanilla spawning", without introducing new terminology abbreviations.
- What changed: a full-text cleanup of this repo's `README.md` / `CHANGELOG.md` / `docs/` (including `docs/wiki/`); the datapack-internal `pack.mcmeta` description and the in-game ready message were changed in step (regenerated by the generators under `src/tools/`, artifacts not hand-edited).
- Repacked: the two zips in `dist/` were rebuilt from the new artifacts (the zip top level is still `doom.nats/`; every file in both zips is byte-identical to the artifact regenerated from `src/`):
  - `doom.nats-v4.25.zip` · sha256 `cd3473703bdcb51186ba10c26767f7385dfe5bf3c1c625602bfd260e63ea065e`
  - `doom.nats-v4x-experimental-v4.25.zip` · sha256 `ddf72ddb393c432adc55066af9074b2bc8bb3f68312fe2980cce68746a1786a9`
  - The four Release `v4.25` attachments (the two zips + their sha256) were replaced in step.
- Nothing about gameplay or rules changed: this pass only touched "the words meant for people" — the `pack.mcmeta` description, the chat ready message from `core/setup`, the artifact file header comments, and one explanatory line in a block tag.
  Byte comparison confirms: functions, tags, and judgment logic are all unchanged (697 files in the default variant / 765 in the experimental variant, with an identical file-name list).
- Acceptance: `src/tools/check_static.mjs` default 0 error / 2 warning, `--exp` 0 error / 2 warning; `check_leak.mjs` 0 hits; full-text search for the old abbreviation across both repos' body text: 0 hits.

## v4.26 — 2026-09-29 · Repository Split: the Public Repo Keeps Only What Players Need (+ name cleanup)

- The public repo (this one) is left with only 6 items: `README.md` `LICENSE` `CHANGELOG.md` `dist/` `docs/` `rules/`.
  The datapack = the two zips in `dist/` (each with sha256); no more source / generators / test bench / reports / CI.
- Development material moved to the author's local development workspace: the generators and static gate (`doom.nats/tools/*`),
  the generator data tables (`doom.nats/_work/generated/*`), the real-hardware test bench (`tests/`), the per-round evidence reports (`doom.nats/reports/`), CI (`.github/workflows`), VS Code tasks.
- Artifact directory renames: `v4/doom.nats` → `pack/doom.nats`, `v4x/doom.nats` → `pack/doom.nats-experimental` (both variants now live under `pack/`).
  The public repo no longer includes these two directories; players just download the zips from `dist/`. The artifacts are byte-identical (all 1462 file sha256s equal · generator `--check` passes).
- "Why are there two": the default variant = item-by-item vanilla replication (recommended, for the vast majority); the experimental variant = the default variant + non-vanilla capabilities
  (`near` / `on_spawn` / preset packs), and its `pack.mcmeta` carries the `features` engine gate ⇒ the world must have the matching experimental gameplay enabled at creation, otherwise it won't install.
- Name cleanup: a round of wording replacement was done at the user's request (177 files), and the old project name was added to the leak-gate blacklist (0 hits in the public repo).
- Acceptance: `tools/check_static.mjs` default variant 0 error / 2 warning, `--exp` experimental variant 0 error / 2 warning;
  `check_leak` 0 hits (including local absolute paths); the top-level structure gate (whitelist) 0 violations;
  the files inside the zip are byte-identical to the artifact regenerated from `src/`.

---

## v4.22d — 2026-09-29 · `in_fortress` Flapping Closed (conclusion: a test-bench problem, not a pack defect)

- Engine semantics (`LocationPredicate.java:49-53`): both `structures` and `biomes` of `location_check` are
  short-circuited by `level.isLoaded(pos)` ⇒ the predicate is always false when the chunk the position is in isn't loaded. Vanilla only
  attempts spawning in loaded and ticking chunks ⇒ the production path never hits this; what this pack calls is the engine predicate ⇒ same semantics as vanilla.
- Test-bench bug: `forceload add <x1> <z1> [<x2> <z2>]` takes block coordinates (≤256 chunks at a time). The old script passed
  "chunk coordinates" (`Math.floor(X/16)±4`) ⇒ the command echoed success but actually marked other chunks (passing `-45,-44` actually loaded `chunk[-3,-3]`).
- Numbers (isolated instance 25581, 200 evaluations at the same stronghold point): not loaded 0/200 = 0.0% · force-loaded 200/200 = 100.0% ·
  only 1 of 5 candidate points loaded 80/200 = 40.0% (per point either 0% or 100%, zero flapping). End to end (25565, same stronghold):
  both gates were off-table 0/24 = 0.0%, 3 PASS / 0 FAIL. The "~17% flapping" was a record from an earlier round before the criteria converged.
- New discipline: any case relying on `forceload` must read back `data get block` to judge `loaded`, `exit 1` if unmet, and never degrade silently;
  tests that poke structure/biome predicates at an arbitrary coordinate must first force-load that coordinate.
  `_work/verify_fortress_e2e.mjs` has been changed to ±64 blocks = 9×9 chunks.

## v4.22 — 2026-09-29 · Despawn Layer "Nearest Player" Quantifier Bug (P0) + Gate Anchors/Test Preconditions Failing En Masse

- P0: the despawn layer wrote "nearest player" as "any player". v4.17's `execute as @a at @s as @e[tag=…,distance=129..]`
  = "∃ a player >128 ⇒ kill"; vanilla `Mob.checkDespawn()` is "only discard when the nearest player is >128" = "∀ players >128 ⇒ kill".
  Consequence: when two players are more than 256 blocks apart, each one's spawned mobs get judged away by the other (real hardware, 3 players 460 blocks apart: in 75 seconds
  `$spawned.total` +692 while only 0–9 remained on field).
- The fix: mark-and-sweep in two passes (first clear `near64/near128`, then "within 64/128 blocks of any player ⇒ mark", and finally only what has "no mark at all"
  gets `void_kill`), plus an online-player guard (with no players, vanilla's `getNearestPlayer=null` ⇒ no judgment). The probabilistic despawn segment (`near32`) got the same family of fix.
- Numbers: `verify_multibot` 1 PASS / 3 FAIL → 4 PASS / 0 FAIL; both A/B spots within 128 blocks 0/0 → 67/24.
- Three tool fixes: `tools/check_closure.mjs`'s `RE_TAG_ADD` character class was missing `@` (the actual form is always `tag @s add <tag>`)
  ⇒ that regex had never matched once, and it reported dynamically added tags as "reads a tag that was never added" (C4 false red 6 → 0);
  `debug/dryrun_check` now refreshes `$att.dim` first (otherwise a cross-dimension dryrun falsely gives r5); `install.mjs`'s fixture gains
  `general:fortress_rounds` (one RCON = 40 rounds, speeding up structure-type e2e, not entering the artifacts).
- Gate anchors: the anchor was hardcoded to `y=64` while the test world's surface is at y=70 ⇒ the bot was buried ⇒ sky light 0 ⇒ failures en masse. The gate now scans top-down for
  "`#doom.nats:standable` + two spawnable blocks above + the standing point sees sky", and before scanning it lifts the bot to y=200 so chunks load.
  Numbers: `rules 12/4 → 16/0`, `animals 4/2 → 6/0`, `persist 9/1 → 10/0`.
- Safety regression: added `_work/verify_dim_att.mjs` (`$att.dim` attribution / `$snap.dim` isolation / End at full cap ⇒ r5 required /
  no cross-contamination in reverse / both directions of the production chain) 6 PASS / 0 FAIL; automation commands always carry a guard (only touching anchored bots).

## v4.20 — 2026-09-29 · Two Cross-Dimension P0s Dug Up by Extreme Scenarios E1–E7

- P0-1 the production path never refreshed "the dimension of this attempt" ⇒ Nether/End attempts were judged with the Overworld's counts/capacity/sea-level window,
  and the global capacity gate effectively didn't exist in non-Overworld dimensions (measured: the End stacked up to 500 endermen, `$rej.5` always 0).
  Root cause: `pos/ctx` was only called by the debug path. Fix: add `function doom.nats:pos/ctx` as the first line of `spawn/try_at` (once per attempt).
  Regression assertion: clean world + a player in the End + `cap.monster` lowered ⇒ `$rej.5` must grow.
- P0-2 `$snap.dim` was a shared scoreboard (the snapshot layer writes it every 20t, and the attempt layer writes it too ⇒ overwritten when busy) ⇒ split out a dedicated `$att.dim`
  (written by `circ/detect_dim_att`; read by `check/cap`, `check/sealevel`).
- `check/border` (reason=11): added vanilla's `worldborder.isWithinBounds`, checked at all three placement outcomes, with config
  `border.centerX/centerZ/size` (`size=0` disables it by default), half-open interval matching vanilla.
- `water_fluid` tag: aquatic placement moved to fluid semantics (water / seagrass / tall_seagrass / kelp / kelp_plant / bubble_column),
  13 judgment sites (`check/block` 12 + `check/entity` 1). E5 measured: before the fix, seagrass/kelp/bubble-column blocks were all wrongly rejected.
- Discipline: gates must be single-instance (running two gates at once ⇒ all numbers are cross-written); a single script must have a timeout (`spawnSync` waits for the stdio pipe to close);
  the anchored bot's dimension/distance/time is backstopped by the gate; a probe must call the function under test itself and read `$chk.*`, never "equivalent inference".

## v4.19 — 2026-09-29 · "No Drowned Visible in Water" → Four Fixes (three real bugs)

- P0-4 the production chain never rolled `$rng` (only the test script rolled it ⇒ always 0) ⇒ every category forever spawned only "the first row in the table" (oceans forever spiders,
  strongholds forever blazes, forest/desert/snowy plains all spiders), and drowned (5/520) could never be selected.
  Fix: the biome distribution table header in `gen_mobs.mjs` rolls `random 0..999999` itself.
- P0-5 the y for taking a position only scanned "player layer +2..-16" ⇒ over deep water it couldn't find the ground and candidate points were pinned to the player layer ⇒ zero spawning in deep water.
  Fix: when the scan finds nothing, fall back to a vanilla-style uniform whole-column `pos/band_fallback` (config `band.fallback` / `floorY.<dimension>`).
- P1-10 `#reduce_water_ambient_spawns` had the polarity backwards (`unless` should be `if`) ⇒ ocean fish were docked 98%, while rivers instead got 50× the excess.
- P1-11 missing `Drowned.checkDrownedSpawnRules`'s first item "the block below must be water" ⇒ drowned could spawn even in a shallow puddle.
- New regression gate `_work/verify_species_mix.mjs` (goes through the production dispatch, does not pre-roll `$rng`; bucket alignment + count of `$rng` values drawn +
  first-row share + category share + liveness) 9/0.
- Three conventions fixed: ① freezing must freeze `$snap_period` (setting only `$eff.period` gets restored by the snapshot a second later);
  ② a probe must not roll `$rng` itself (the old form happened to mask P0-4: tests all green, production all degraded); ③ long-lived bots and long tasks must live outside the
  DSH process tree (`_work/start_bot.ps1` / `run_bg.ps1`), otherwise reclaiming the process tree drops them.

## v4.18 — 2026-09-28/29 · Q7 Closed Out (map worldgen override end to end · single-category biome fatal bug · ghost files)

- worldgen override end to end (four-phase A/B/A in the same world with only the roster swapped, isolated instances 25567/25577):
  P1 vanilla `+91` spawned / 70 on field → P2a empty-table override (= RC4 map semantics) `+0` → P2b husk override `+59` (husk=70, everything else 0)
  → P3 restored `+51` / 68. Evidence: after the fix `mob/biome/plains/monster.mcfunction` goes from 97 lines/8 species → 20 lines/["husk"].
- Fatal bug (present in the vanilla build too, 7 biomes affected): the single-category branch of `mob/biome/<biome>.mcfunction` doesn't set `$catid`
  ⇒ it inherits the previous biome's value ⇒ `if score $catid matches 0` randomly fails ⇒ the whole biome stops spawning.
  Victims: `the_end / end_barrens / end_highlands / end_midlands / small_end_islands / deep_dark / the_void`
  and any biome overridden by a map to a single category. Fix: the single-category branch explicitly sets `scoreboard players set $catid doom.nats 0`;
  new lint L14. Red→green: before the fix the generation gave `+0`/reason=8 `+1891`, after it `+59` husk only.
- Ghost files: the generator only wrote, never deleted ⇒ after a roster change the old tables lingered (the user's save had 2 `mob/biome/wgtest/**`),
  and `--check` couldn't see it. Fix: after writing, clean up files under `mob/biome/**` that aren't in this run's output set, and `--check` counts "stale files" as drift.
  The vanilla build went 586 → 584 files.
- Regression hook `tools/regress.mjs --worldgen <dir>`: merge override → `export_rosters` → regenerate → the whole static/offline/real-hardware set →
  automatic `--reset` restore and read-back verification against `biomes.json`'s sha1 (a mismatch turns the whole round red).
- Trap: don't use `execFileSync('powershell', …Start-Process -PassThru)` to start a detached server (`execFileSync` waits for stdout EOF,
  and the Java child inherits the handle ⇒ the parent blocks forever). The right way is `spawn(JAVA, …, {detached:true, stdio:['ignore', fd, fd]})` + `unref()`.

## v4.17 — 2026-09-28 · Fidelity Backlog (P0-3 variant dice timing · despawn-layer reference-point bug · multi-instance isolation)

- P0-3 variant dice timing: vanilla `NaturalSpawner:186`'s `finalizeSpawn(...)` happens after `isValidPositionForMob` (:254)
  ⇒ `SpawnGroupData` is created by the first individual that actually spawns successfully, and the position is its `blockPosition()`.
  Now `grp/init/<slug>` writes only fallback values + `$grp.vneed=1`; `post/<slug>` runs `grp/var/<slug>` then `grp/mem/<slug>`.
  Red→green: `verify_group` 22 PASS / 0 FAIL (`/fillbiome` creates two mutually exclusive biome zones, forest/plains; the first individual in forest ⇒ 4/4 woods;
  reversed ⇒ 2/2 pale; the counter-proof of putting the dice roll back in init ⇒ pale).
- Despawn-layer real-hardware bug (severe): `despawn/tick` used a bare `distance=129..`, and its reference point is the function's execution position = `core/tick`'s
  context = the world spawn point ⇒ when players are more than 128 blocks from spawn, all of this pack's non-persistent mobs got `void_kill`ed within one despawn tick
  (symptom: "mobs vanish as soon as they spawn"). Changed to per-player judgment. Red→green: `verify_persist 10 PASS / 0 FAIL`, `verify_animals 6/0`.
- Multi-instance isolation: `mcauto.mjs` / `regress.mjs` support `MC_SRV` / `MC_PORT` / `RCON_PORT`, with defaults exactly as before;
  `bot.mjs` gets `--port` passed from them. Parallel workflows each use their own `mcserver-<name>` + separate ports.
- Trap: a bare `@e[,…,distance=N..]` in a datapack, and any position-dependent predicate, refers to the function's execution position;
  macro function arguments must be written into storage before the call; values that differ per member need separate macro functions (horse `Variant`).

## v4.16 — 2026-09-28 · Toolchain: VS Code Integration + headless Spyglass

- Added `.vscode/tasks.json`: the default build runs `tools/check_static.mjs --vscode` (9 generators' `--check` + lint + closure),
  emitting `file:line:col: error: msg` with the `$gcc` problemMatcher ⇒ straight into the editor's "Problems" panel; there is also a one-key regression / group-data special task.
- Added `tools/check_static.mjs` (the unified static gate, <2s) and `tools/lint_spyglass.mjs` (headless launch of an installed Spyglass LSP).
  The latter was not made to work: the probe pack comes back with "(no diagnostics)" ⇒ unusable as evidence (see `docs/20`).
- The hard gate is still the game's own loader (`/reload` + looking only at this round's `Failed to load function`), built into mcauto/regress.

## v4.15 — 2026-09-28 · finalizeSpawn Group-Data Layer (SpawnGroupData replica)

- First, correcting an old belief: `/summon` and `execute summon` already call finalizeSpawn
  (`SummonCommand.createEntity(..., true)`, reason=COMMAND, groupData=null) ⇒ rewriting equipment/variant/baby per entity was redundant;
  what was really missing was the `SpawnGroupData` that vanilla `NaturalSpawner` passes.
- New generator `gen_group.mjs` (140 files): `grp/init/<slug>` (once per group), `grp/mem/<slug>` (applied per individual),
  `post/<slug>` (add this pack's NBT + global persistence + random facing), `predicate/grp/biome/*` (cold/warm livestock, white/gold rabbit, snow fox, wolf — 8 biomes).
- `spawn/emit` changed to `$execute summon $(type) run function doom.nats:post/$(slug) with storage doom.nats:sel`
  ⇒ the new entity is `@s`, eliminating the old form's `@e[distance=..1,sort=nearest]` risk of picking the wrong one.
- Engine trap: a macro line without `$(name)` makes the whole function fail to load (`No variables in macro`) ⇒ lint gains L12.
- Animals being babies uses `Age:-24000` (the `AgeableMob` save key), zombie-type mobs use `IsBaby`; new cfg `difficulty`, `special`.
  Real hardware: all 14 assertions green, full regression 16 PASS / 0 FAIL.

## v4.14 — 2026-09-28 · Animals / Dimensions / Persistence / Configuration

- The passive-mob cadence must use `time query gametime` (vanilla `gameTime % 400`), not `daytime`; a creature only enters the candidate set on the tick that hits the cadence.
- Dimension detection happens at the first non-spectator player's position (`circ/detect_dim`), because the tick function's execution context is always the Overworld.
- Sea level / light tier enter the config layer per dimension: Overworld 63 / uniform 0..7; Nether 32 / constant 7 (no sky light); End 0.
- Persistence in three states: default (vanilla manages despawn) / the `doom.nats.persistent` tag (only affects this pack's cleanup layer) /
  `PersistenceRequired:1b` (vanilla won't despawn it either); per-rule `persist:true` + global `$cfg.persist=1`.
- Config layer: `doom.nats:cfg_defaults` → `doom.nats:config` (author overrides) → `$cfg.*`; the key list is in `docs/18-配置手册.md`.
- Real-hardware verification `_work/verify_{rules,persist,animals,dims,mode}.mjs`, all folded into `regress.mjs --reuse`.

## v4.13 — 2026-09-28 · Per-Entity Rules + Per-Entity Light (corrections after source comparison)

- Rule table `tools/lib/entity-rules.mjs` (47 entities → 27 rule signatures) → `_work/generated/entity-rules.json`;
  `gen_mobs.mjs` writes `$sel.rule/place/light/tag/grp1/cluster`, `gen_check.mjs` generates `check/block` and `check/entity`.
- Light per entity (`$sel.light`: none/dark/bright/bat/slime/glow/bl8) ⇒ fixes the mutually exclusive bug where "an animal is required to be both bright and dark".
- Placement per type (`$sel.place`: ground/any/water/water_surface/below_tag/lava) ⇒ fixes the mutually exclusive bug where "an aquatic mob requires a standable block below".
- The block below now uses 14 vanilla tags; new biome predicates (slime / river / more_drowned / polar_alt) and `can_see_sky`.
- Cluster caps filled in: ghast/pillager/happy_ghast=1, camel/llama/trader_llama=6; water_ambient distance 64; rivers 98% no spawn;
  slime gains a 50% coin flip. The despawn layer is off by default (vanilla `Mob.checkDespawn` already applies to ordinary mobs).
- lint gains L11 (no two consecutive spaces in a command: Brigadier rejects the whole command outright — hit on real hardware).

## v4.12 — 2026-09-28 · Survival-Ready Mode (`mode/*`)

- Problem: this pack creates mobs with `summon`, which `doMobSpawning` doesn't constrain ⇒ if vanilla natural spawning is still on, spawning happens twice.
- `core/setup` (the load tag) runs `mode/survival` by default: `gamerule doMobSpawning false` + emit one snapshot + `say` to the log.
- The switches `mode/{survival,manual,auto,off}`, with state stored on a scoreboard, surviving `/reload` and re-entering the world.
  Real hardware: `verify_mode` 9 PASS / 0 FAIL (including the counter-proof that "after manual, a reload still gives true").
- Survival manual `docs/16-生存直用手册.md` (three-step assembly + command table + measured numbers + an honest list of the gaps from vanilla).

## v4.11 — 2026-09-28 · Removing the Indiscriminate void_kill

- Vanilla despawning / out-of-range removal = `discard()` (silent, no drops, no experience); `kill` drops loot and gives experience ⇒ wrong semantics.
- `util/void_kill` = `tp @s ~ ~-500 ~`; the despawn layer and cleanup both go through it. `debug/clear` silently clears this pack's mobs
  (keeping `doom.nats.persistent`) and reports the count to chat and the log.
- Don't use `kill @e[tag=doom.nats.spawned]` to clear the field anymore (measured: it leaves 476 dropped items on the ground).

## v4.10 — 2026-09-28 · Cluster Model

- One spawn attempt = at most 3 groups; each group's starting point is modeled as a reset, and within-group displacement accumulates `nextInt(6)-nextInt(6)`.
- `groupSize = minCount + rand(1+max-min)` (recomputed once after a species is picked); the species is picked only once per group.
- `spawned >= getMaxSpawnClusterSize()` ⇒ ends the whole attempt (default 4; only 8 entity classes override it).
- For debugging look at `$grp.sel / $grp.sized / $grp.stop / $dbg.clusterMax`.

## v4.9 — 2026-09-28 · One-Key Regression `regress.mjs`

```bash
node tools/regress.mjs --reuse          # static + comparison + offline + one real-hardware round (no server stop, no kicking)
node tools/regress.mjs --quick          # skip the comparison variant
node tools/regress.mjs --reuse --stress # also run the batch step stress test
```

- One failing step doesn't abort (it summarizes at the end), producing `reports/回归-<timestamp>.md`: each step's PASS/FAIL, duration, key output + the latest trend-chart path;
  exit code 0/1 plugs straight into CI. Measured all green 9 PASS / 0 FAIL.

## v4.8 — 2026-09-27 · Two Ways to Run `mcauto.mjs` (important)

| Command | Behavior | Does it kick players |
|---|---|---|
| `node tools/mcauto.mjs --reuse --minutes N` | Reuse the already-running server: only hot-load the new pack (`/reload`), run the scenario, don't stop the server | **No** (measured: PID unchanged, players on field stay connected) |
| `node tools/mcauto.mjs --minutes N` | Clean world → start a new server → stop the server when done | **Yes** (client Connection reset) |

By default it carries `--curve 1.5` (a trend chart + stats line per round); `--stress` also runs the batch step stress test.

## v4.7 — 2026-09-27 · Two New Tools

- `_work/timeseries.mjs`: time-series sampling (per-category counts / cumulative spawns / batch / caps / mspt), producing json+csv+svg+png.
  Measured steady state: monsters 71.7 (cap 70), mspt 5.29ms (budget 50), refilled within 6 seconds after clearing the field.
- `tools/propose_tags.mjs --save <save>`: reads the Anvil region to tally the real terrain's "block below/above" distribution → gives coverage and suggested ids to add.
  On its first run it found that `standable` was missing `ice`/`packed_ice` (40% of placement faces in snowy plains), coverage 3.7% → 43.9%.

## v4.5 / v4.4 — 2026-09-27 · Automatic Ground Finding + Per-Entity Rules

- v4.4: `pos/band` defaults to `$band.mode 0` = scanning down from "player layer +2" to -16 at the candidate point, taking the first place where "below is standable + the mob itself/above is spawnable"
  ⇒ the author no longer has to declare a height band (mode 1 fixed band, mode 2 ±jitter).
- v4.5: `check/entity` (reason=9), with the rule id written in the roster row's `$sel.rule`: land mobs can't be in water / surface aquatics need a seaLevel window +
  water above and below / deep-water mobs need real water / bats below the surface + dark + 50% / slime 50<y<70 + moon-phase gate. New snapshot values `$snap.py`, `$snap.moon`.
- New lint L9 (trailing comment on a line), L10 (illegal `~+N` coordinate), both bought by real-hardware load failures that day.

## v4.3 — 2026-09-27 · Real-Hardware Automation

- No more typing commands by hand: `node tools/mcauto.mjs --minutes 3` runs the whole chain in one command: kill the old server → clean world → install the pack → start a local Fabric server →
  start a real client bot → set the scenario → wait for chunks to settle → `debug/all` → collect the report.
- Components: `tools/mcrcon.mjs`, `_work/mcserver/setup.mjs`, `_work/mcserver/bot.mjs` (mineflayer), `_work/mcprobe.mjs`.
- The driver must assert 0 load-time errors at the start of every run: a function failing to load makes a whole chain silently vanish (hit that day in `check/distance`).
  On a dedicated server, `tellraw` doesn't reach the log ⇒ collection uses `say`.
- Measured steady state: `$cnt.monster = 70` (= cap), `$cnt.ambient = 13` ⇒ the capacity chain really is in control.

## v4.1 — 2026-09-27 · Collection Chain

- `collect.mjs` really can collect v4 markers: `[nats.env]` / `[nats.reject] rej:` / `[nats.light] tier:` / `[dryrun]`.
- `debug/reject_report` prints the values before zeroing them ⇒ every `/function doom.nats:debug/all` is its own measurement window.
- New saves: automatic installation + automatic collection: `node _work/watch_new_save.mjs --minutes 45`, `node _work/watch_collect.mjs --minutes 60`.

---

## Appendix: Current Acceptance Convention (Four Gates)

| Gate | Command | Requires | Latest result |
|---|---|---|---|
| ① Static | `node tools/check_static.mjs` (generator `--check` + lint L1–L14 + reference closure) | node | **0 error / 2 warning** (<2s; wired into CI) |
| ② Load time | Install + `/reload`, looking only at this round's `Failed to load function` | Fabric server | 0 (built into mcauto/regress) |
| ③ Real-hardware assertions | `_work/verify_*.mjs` (`RCON_PORT=<port>` can point at an isolated instance) | Server + bot | `rules 16/0` · `animals 6/0` · `persist 10/0` · `dims 13/0` · `multibot 4/0` · `species_mix 9/0` · `dim_att 6/0` · `fortress_e2e 3/0` (off-table 0/24 = 0.0%) · `e6_generic 7/0` |
| ④ One-key regression | `node tools/regress.mjs --reuse --minutes 1 --curve 1` | Server (`--reuse` doesn't kick players) | **16 PASS / 0 FAIL** |

Capacity (E6 / stress-test convention): a single dimension's cap is decided by `maxInstancesPerChunk × spawnableChunkCount / 289`, growing naturally with the chunk count;
multiple dimensions count independently (fixed in v4.20); nothing spawns under `/tick freeze`, and redstone-type scenarios are evidenced with a 10 Hz observation clock.
