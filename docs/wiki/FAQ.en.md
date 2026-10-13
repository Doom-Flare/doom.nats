# FAQ

中文: `docs/wiki/FAQ.md`

## After installing, will vanilla still spawn mobs on its own?

No. On load it automatically sets `gamerule doMobSpawning` to `false`, and this pack takes over; otherwise that would be spawning twice over.

Only natural spawning is turned off. Spawners, structure generation, breeding, command summoning, and spawn eggs are all unaffected. To coexist with vanilla:

```
/function doom.nats:mode/manual
```

## Do I need to enable experimental gameplay?

The default variant does not (`doom.nats-v4.30.0.zip`).
Only the experimental variant does (`doom.nats-v4x-experimental-v4.30.0.zip`), and it must be enabled when creating the world, otherwise the pack is refused at load. See [[实验性变体-v4x]].

## In singleplayer, standing still, why does nothing spawn?

Three possibilities, ordered by likelihood:

1. The pause menu is open / the window lost focus: singleplayer stops the tick, and spawning stops with it. Close the menu and keep the window focused.
2. A player is right next to it: nothing spawns within a 24-block sphere (vanilla semantics, normal behavior).
3. The spot is wrong: the surface is too bright in daytime, the cap is full, or the block below is not on the "standable" list. Run `/function doom.nats:debug/reject_report` to see the rejection histogram.

## How do I read the rejection histogram?

```
[nats.reject] rej: 0=<抽不到区块> 1=<24格有人> 2=<出128格> 3=<光照档> 4=<落位方块> 5=<全局容量> 6=<本地容量> 7=<spawn cost> 8=<选不到物种> 9=<该生物自身规则不满足> spawned=<成功数>
```

- `4` largest ⇒ the landing block is not recognized; extend `#doom.nats:standable` / `#doom.nats:spawnable_at` (most common on custom maps)
- `5`/`6` largest ⇒ the cap is full; adjust `cap` or the cadence
- `3` largest ⇒ the light tier is not satisfied; adjust `light` or `$eff.light`
- `0` largest ⇒ not enough of the surrounding 17×17 chunks is loaded

⚠ `0` and `8` increased in strict lockstep in the measurements (5-second granularity, 6/6 intervals equal point by point, and the whole window lines up too). So you cannot use the relative sizes of `0` and `8` to decide whether it is "cannot draw a qualified chunk" or "cannot pick a species": this histogram cannot tell those two causes apart. The mechanism has not been determined; this is recorded as an observation only.
(Source comments record that `$rej.8` / `$rej.9` only `add` and never `set`, so they are never zeroed. In a snapshot they are "cumulative over the world's lifetime" (recorded in v4.17, unchanged), and `8`'s absolute value could not be compared directly with `0` in the first place.)

The histogram prints the numbers first and then zeroes them (except `8` / `9`), so every call is an independent measurement window.

## After installing, why do animals not spawn?

Animals have spawned since v4.14 (before that the light tiers contradicted each other and they never spawned). If you still do not see sheep/cows/pigs/chickens:

- Animals require enough light (≥ 9): in the open during the day, or near a light source at night;
- In biomes like `snowy_beach` that vanilla originally had no creature list for, vanilla does not spawn them either (consistent);
- Passive mobs entering the candidate set have a cadence gate (`creatureGate`, by default once every 400 ticks), so you need to wait patiently.

## Why do mobs disappear right after they spawn?

Vanilla's own despawn logic is still in control (the 128-block hard despawn + probabilistic despawn), and what this pack spawns are ordinary mobs. To keep one:

```
/tag @e[type=zombie,limit=1] add doom.nats.persistent     # only immune to this pack's cleanup and despawn layer
```

To make vanilla not despawn it either, use `PersistenceRequired:1b`, or set the config's `persist` to 1 (so even newly spawned ones carry it).

## Why do mobs still spawn within 24 blocks of the world spawn point?

This is off by default: the datapack cannot read the world's spawn point coordinates. You need to declare them:

```
data merge storage doom.nats:config {spawn24:1, spawnX:0, spawnY:64, spawnZ:0}
function doom.nats:cfg/apply
```

All three coordinates must be given; if one is missing it automatically reverts to off. When it is not in effect, `reason=10` appears in the rejection reasons.

## The spawning height band is strange / I want to pin the height

The datapack cannot read the heightmap, so the default policy is "follow the player ± jitter". For a custom map, declare it explicitly:

```
data merge storage doom.nats:config {band:{mode:1, yMin:40, yMax:120}}
function doom.nats:cfg/apply
```

`band.mode`: `0` find the ground automatically / `1` fixed band / `2` follow the player ± jitter / `3` uniform random band (closest to vanilla).

## Will it cause frame drops?

Measured (on the author's machine, budget 50 mspt): steady-state mob count 71.7, mspt mean 5.29 (peak 5.70).

The real bottleneck on throughput is not performance, but vanilla's `maxCommandChainLength` (default 65536 ≈ 10 attempts/tick). For higher density: raise that gamerule first, then raise `batch`.

Recommendation: to keep mspt within 30 ms ⇒ `$eff.batch` at no more than 200.

## How does it behave on a multiplayer server?

- Cap counting and the per-player limits are computed individually per player, and counted independently per dimension.
- The chunk union is exact in singleplayer, while in multiplayer it is a square approximation (Euclidean distance cannot be expressed in a datapack).
- The more people, the larger the total cap and the more active the spawning; this is by design.

## Can I cleanly uninstall it afterwards?

Yes:

```
/function doom.nats:mode/off     # silent clear (no drops, no experience) + give natural spawning back to vanilla
```

Then delete `datapacks/doom.nats` and `/reload`. The mobs that have already spawned will be cleared along with it by `mode/off`; if you just deleted the folder beforehand, they will stay in the world as ordinary mobs.

## What do I do about a `Failed to load function` error?

Usually three things: ① the pack was not unzipped correctly (`pack.mcmeta` must be at the `doom.nats/` level); ② two variants were installed at once (default + experimental), delete one; ③ the experimental variant was installed into a world that did not enable experimental gameplay. Read the full error in `logs/latest.log` before doing anything.

## Why can the glow squid spawn on grass?

v4.25 incidentally "fixed" a bug that nobody had reported and nobody considered a bug: in vanilla, the glow squid cannot spawn on grass.
At runtime you can change its landing face and light (see the landing face section of [[示例库]]). But vanilla has one more depth gate (y ≤ sea level-33) that is a rule-level switch and cannot be removed at runtime. To really make it spawn on land, you must write `"ySea": null` into entity-rules.json at build time and regenerate.
Vanilla is of course not a bug; it is just that these "not allowed" things are now all rules you can change. 😄

## Nothing spawns at all? Check `$snap_period` and `$cap.*` first

This pack ships with a frozen-snapshot test recipe (`$snap_period=20000`, which the acceptance scripts use). If the world was left in a frozen state by a previous session:

```
$snap.chunks = 0   ⇒   $cap.monster = 0   ⇒   every attempt gets reason=5 (global cap full)
```

The symptom is that nothing spawns at all, while the tick loop and the load log are all normal. This is the easiest thing to misdiagnose as "the pack is broken / mobs cannot pass the gate". To thaw (= restore the default value):

```
/scoreboard players get $snap_period doom.nats     # if it is not 20, it was frozen
/scoreboard players set $snap_period doom.nats 20
/function doom.nats:circ/snapshot
```

After thawing you should see `$snap.chunks=289`, `$cap.monster=70`. Then run `/function doom.nats:debug/reject_report`: if `5` (global cap) accounts for the overwhelming majority, this is the cause.

## I added an entry and it still does not spawn / what spawns is not the species I wanted?

The two most common traps:

1. `weight`'s real measure is `weight / 1000000`; writing `40` equals not spawning, you must fill in hundred-thousand-scale values (see the "⚠ `weight`'s real measure" section of [[规则字段参考]]).
2. The "leftovers" of the entry path: at runtime an entry does not load the selected species' vanilla `place`/`light`/`rule`/`tall`, and these `$sel.*` values carry over the values left by the last vanilla draw:

```
/data get storage doom.nats:sel        # check whether rule / tall / place / light are what you expect
```

`entityRules` can only pin the two items `place`/`light`. `rule`/`tall` have no corresponding author field and cannot be changed at runtime (only at build time by changing `rules/`).
The leftovers are usually inert: in the measured "ghost window" (no override) they are `rule=12` / `tall=1` (enderman leftovers), and `rule 12` has no match at all among all 38 lines of `check/entity` ⇒ harmless.
The two specific values to watch are `11` and `28`: if the landing vanilla table leaves `$sel.rule` as `11` (drowned, requiring water underfoot) or `28` (slime), it will silently reject your target mob. All you see in the rejection reasons is `reason=9` ("the mob's own rules are not satisfied"), which looks like "the pack is broken". This is most easily hit after changing biome / changing dimension.

## What can I change and what can I not change?

- What you can change: see [[规则字段参考]] and [[示例库]]
- What you cannot change: see [[已知限制]]
