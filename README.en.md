# doom.nats

中文: `README.md`

Replicating Minecraft's vanilla natural spawning with a datapack. Mob caps, chunk counts, light and per-entity rules, structure overrides, and the despawn layer are all here — and the rules are editable.

[![Latest release](https://img.shields.io/github/v/release/Doom-Flare/doom.nats?include_prereleases&label=%E6%9C%80%E6%96%B0%E7%89%88%E6%9C%AC)](https://github.com/Doom-Flare/doom.nats/releases)
[![Minecraft](https://img.shields.io/badge/Minecraft-1.21.5%20%E2%80%93%2026.3-3C8527)](docs/25-兼容与版本.md)
[![License](https://img.shields.io/badge/%E8%AE%B8%E5%8F%AF-All%20Rights%20Reserved%20%C2%B7%20Beta-c0392b)](docs/26-致谢与许可.md)

Works on Minecraft 1.21.5 through 26.3, split into five packages by version range.

## Which One to Download

Check your MC version first.

| Your version | Download this |
|---|---|
| 1.21.5 | `dist/doom.nats-v4.30.1-mc1.21.5.zip` |
| 1.21.6 / 1.21.7 / 1.21.8 | `dist/doom.nats-v4.30.1-mc1.21.6-1.21.8.zip` |
| 1.21.9 / 1.21.10 | `dist/doom.nats-v4.30.1-mc1.21.9-1.21.10.zip` |
| 1.21.11 to 26.2 | `dist/doom.nats-v4.30.1-mc1.21.11-26.2.zip` |
| 26.3 | `dist/doom.nats-v4.30.1-mc26.3.zip` |

The companion files are worth installing alongside; they don't vary by version:

| File | What it does |
|---|---|
| `dist/doom.log-multi.zip` | Log channel. Without it, you can't see why the pack failed |
| `dist/doom.nats-selftest.zip` | Self-assertion suite. One command tells you whether the pack is working |

There's also an experimental variant, `dist/doom.nats-v4x-experimental-v4.30.1.zip`, which adds `near` (only spawn when certain things are nearby), `on_spawn` (spawn effects), and a few presets. To install it you must enable the matching experimental gameplay when creating the world, otherwise the pack is refused at load. See [Experimental Variant](docs/wiki/实验性变体-v4x.md).

Install only one of the packages. They share the same namespace, and two copies overwrite each other.

## Installation

1. Download the zip for your version and unzip it into a `doom.nats/` folder
2. Drop the whole folder into `<save>/datapacks/`. On a server, into `world/datapacks/`
3. Get into the game and run `/reload`

Once installed you'll see a ready message in chat. If you don't, look for load errors in `logs/latest.log`.

To confirm it's really running, run `/function doom.nats:debug/all` and watch two numbers: `$spawned.total` keeps climbing, and `$cnt.monster` sits near the cap (70 by default). Within 30 seconds of installing it should climb from 48 to 70.

To uninstall, delete `datapacks/doom.nats/`, `/reload`, then run `/function doom.nats:mode/auto` to hand natural spawning back to vanilla.

## Adjusting Spawn Counts

Want more or fewer mobs? You don't need to change any rules — run one of these five:

| Command | Effect |
|---|---|
| `/function doom.nats:scale/sparse` | Cap halved |
| `/function doom.nats:scale/normal` | Back to vanilla |
| `/function doom.nats:scale/dense` | 1.5× |
| `/function doom.nats:scale/horde` | 2.5×, and a faster spawn cadence |
| `/function doom.nats:scale/extreme` | 4× |

After switching, chat tells you the current tier, and it survives `/reload`.

To set your own number:

```
/data modify storage doom.nats:config qty set value 150
/function doom.nats:cfg/apply
```

`qty` is a percentage; `100` means unchanged, and the range is `1` to `1000`. It only changes the capacity cap — that is, "how many at most". To change "how fast they spawn", use `density`, `batch`, and `period`; see [What Players Can Change](docs/21-玩家可改清单.md).

After lowering the tier, mobs already on the field don't vanish instantly; they drain down to the new cap at the despawn layer's pace.

## Changing Rules

Three routes — pick by when you want it to take effect.

| How | When it takes effect | Entry point |
|---|---|---|
| Edit in game (recommended) | Next tick | `/data modify storage doom.nats:author ...`. `/function doom.nats:author/show` to see the current state, `author/reset` for one-command vanilla |
| Edit runtime knobs | Immediately | Scoreboard switches. List in [What Players Can Change](docs/21-玩家可改清单.md) |
| Edit build-time rules | Requires regenerating the pack | `src/rules/*.json`. Field table in [src/rules/README.md](src/rules/README.md) |

Two examples you can copy directly:

```
# Let zombies spawn on leaves too
/data modify storage doom.nats:author entityRules."minecraft:zombie".belowAny set value ["#minecraft:leaves"]

# During thunderstorms, deep oceans spawn an extra kind of zombie
/data modify storage doom.nats:author entries append value {id:"storm",biome:"#minecraft:is_deep_ocean",category:"monster",mob:"minecraft:zombie",weight:100000,when:{thundering:true}}
```

All examples are in the [Example Library](docs/wiki/示例库.md).

Two things are easy to get wrong.

First, field names come in two layers. For entries you edit in game, the biome field is `biome`, singular — give one biome id or `#tag`; for several biomes, write several entries. Group size uses `min` and `max`. But `biomes` (an array), `group`, `place`, `light`, `tag`, `cluster`, `coins`, and `ySea` are build-time `rules/*.json` spellings; writing them into storage won't error, but it also won't take effect.

Second, `weight` is not a proportional share of a pool alongside the existing species. Measured hit rate is roughly `weight / 1000000`. For an entry to actually spawn, use hundred-thousand-scale numbers: `100000` is about 10%, `900000` about 90% (measured: blazes went from 22 to 32 over 180 seconds). A small number like `40` means it never spawns. Comparison table in [Rule Field Reference](docs/wiki/规则字段参考.md).

## The Knobs You Can Turn

This section lists the knobs people use most. For complete field provenance and vanilla comparisons see the [Configuration Manual](docs/18-配置手册.md); for how-to details see [What Players Can Change](docs/21-玩家可改清单.md).

### Counts and Cadence

These are the most used, and you can tune them without touching any rules.

| Key | Default | What changing it does |
|---|---|---|
| `qty` | `100` | Master count switch, a percentage. Scales the capacity cap only. Usage above in "Adjusting Spawn Counts" |
| `period` | `5` | How many ticks between spawn-attempt batches. Lower means more frequent |
| `batch` | `6` | How many origin points per batch. Higher means more tries per batch |
| `maxBatch` | `40` | Upper bound when `batch` is auto-adjusted |
| `density` | `0` | Target spawns per minute. Above 0 it auto-adjusts `batch`, so you don't fill it in by hand |

### Per-Category Caps

Seven categories sit under `cap`, measured in "max per chunk". The vanilla values are below; raising one means more mobs of that category.

| Category | Default | What it is |
|---|---|---|
| `cap.monster` | `70` | Monsters (zombies, skeletons, creepers, etc.) |
| `cap.creature` | `10` | Animals (cows, sheep, pigs, chickens, etc.) |
| `cap.ambient` | `15` | Bats |
| `cap.water_creature` | `5` | Squid, dolphins |
| `cap.water_ambient` | `20` | Tropical fish, etc. |
| `cap.underground_water_creature` | `5` | Glow squid |
| `cap.axolotls` | `5` | Axolotls |

How to change:

```
/data merge storage doom.nats:config {cap:{monster:140,creature:20}}
/function doom.nats:cfg/apply
```

### Despawn and Persistence

| Key | Default | What changing it does |
|---|---|---|
| `distance.<category>` | `128` | How far from a player before it despawns. The `water_ambient` category is `64` |
| `noDespawnDistance` | `32` | Within this distance the "no-action timer" is zeroed, so mobs aren't culled for standing still too long |
| `dice` | `0` | Above 0 turns on the probabilistic despawn layer. An optional extra on top of vanilla `checkDespawn` |
| `persist` | `0` | Set to `1` and every mob this pack spawns never despawns |

### Rule Checks

| Key | Default | What changing it does |
|---|---|---|
| `light.<dimension>` | `7` | How dark it must be for monsters to spawn. Values 0 to 15; lower makes spawning harder |
| `seaLevel.<dimension>` | Overworld `63`, Nether `32`, End `0` | The water-surface window. Affects the spawn height of aquatic mobs |
| `playerExclusion` | `24` | No spawning within this many blocks of a player |
| `creatureGate` | `400` | How many ticks between passes where animals become candidates. Lower means animals spawn more often |
| `difficulty` | `2` | 0 peaceful / 1 easy / 2 normal / 3 hard. A datapack can't read the real difficulty, so declare it yourself |
| `special` | `-1` | Regional difficulty factor. `-1` means derive it automatically from `difficulty` |
| `peaceful` | `0` | Set to `1` and the whole monster category stops spawning |

### Spawn-Point Exclusion

Vanilla forbids spawning within 24 blocks of the world spawn, but a datapack can't read the spawn coordinates, so you fill them in yourself. Off by default.

```
/data merge storage doom.nats:config {spawn24:1,spawnX:0,spawnY:64,spawnZ:0}
/function doom.nats:cfg/apply
```

It only takes effect once all three coordinates are filled in.

### Placement Height Band

Controls the height at which mobs spawn.

| Key | Default | Notes |
|---|---|---|
| `band.mode` | `0` | `0` finds the ground automatically. `1` random within a fixed band. `2` floats up and down with the player. `3` uniform random band, closest to vanilla |
| `band.yMin` `band.yMax` | `60` `70` | The height range for modes 1 and 3 |
| `band.jitter` | `3` | The float radius for mode 2 |

### Block Checks

Decides "what counts as standable" and "where a free spawn space exists". You can change these two tags by overriding same-named tags in your map pack.

| Tag | Purpose |
|---|---|
| `#doom.nats:standable` | Standable below. Approximates vanilla's "full top surface and own light emission below 14" |
| `#doom.nats:spawnable_at` | A usable free space. Approximates vanilla's "not a full collision box, not a redstone source, not a fluid" |

Once your map has taken shape, run `node src/tools/propose_tags.mjs` to read the region files; it will suggest which blocks to add.

### Author Layer (edit in game, takes effect immediately)

The settings above need `/reload` or a re-run of `cfg/apply`. The author layer doesn't — changes take effect on the next tick.

| Function | Purpose |
|---|---|
| `/function doom.nats:author/show` | See the current rules |
| `/function doom.nats:author/reset` | One command back to vanilla |
| `/function doom.nats:mode/auto` | Take over vanilla spawning automatically on load |
| `/function doom.nats:mode/manual` | Stop auto-changing the gamerule; leave it to the map |
| `/function doom.nats:mode/off` | Silently clear the field and hand natural spawning back to vanilla |
| `/function doom.nats:debug/all` | Full diagnostics |
| `/function doom.nats:debug/env` | Environment snapshot |
| `/function doom.nats:debug/clear` | Clear mobs spawned by this pack |
| `/function doom.nats:spawn/try` | Manually run one complete spawn attempt |

## Verifying Your Download

`dist/SHA256SUMS.txt` holds the sha256 of every current release artifact. From the repo root, run:

```
sha256sum -c dist/SHA256SUMS.txt
```

Windows PowerShell:

```powershell
Get-Content dist/SHA256SUMS.txt | ForEach-Object {
  $h, $f = $_ -split '\s+'
  "$f => " + $(if ((Get-FileHash "dist/$f" -Algorithm SHA256).Hash.ToLower() -eq $h) {'OK'} else {'MISMATCH'})
}
```

All `OK` means the download is intact; a `MISMATCH` means download again.

## Version Matrix

| MC version | data pack version | Package | `min_format` / `max_format` |
|---|---|---|---|
| 1.21.5 | 71 | `doom.nats-v4.30.1-mc1.21.5.zip` | `[71,0]` to `[71,0]` |
| 1.21.6 | 80 | `doom.nats-v4.30.1-mc1.21.6-1.21.8.zip` | `[80,0]` to `81` |
| 1.21.7 / 1.21.8 | 81 | Same as above | `[80,0]` to `81` |
| 1.21.9 / 1.21.10 | 88.0 | `doom.nats-v4.30.1-mc1.21.9-1.21.10.zip` | `[88,0]` to `[88,0]` |
| 1.21.11 to 26.2 | 94.1 to 107.0 | `doom.nats-v4.30.1-mc1.21.11-26.2.zip` | `[94,1]` to `[107,0]` |
| 26.3 | 121.0 | `doom.nats-v4.30.1-mc26.3.zip` | `[121,0]` to `[121,0]` |

All five packages share the same function logic; the only differences are `pack.mcmeta` and a few version-related rewrites (`chain` renamed to `iron_chain`, the gamerule `doMobSpawning` renamed to `spawn_mobs`, and the predicate `condition` changed to `type`). `ports/` holds the source tree of each package for file-by-file comparison.

These ranges are measured boundaries — don't install outside them. Installing the wrong one fails to load because a vanilla ID or gamerule has been renamed.

> 2026-10-05 correction: this table once listed 1.21.11 through 26.3 as a single range, which was wrong. A predicate registry schema change sits between 1.21.11–26.2 and 26.3, so they can't be merged. The old `-mc1.21.11-26.3.zip` has been withdrawn; it labeled its applicable range incorrectly.

## What It Can't Do

Brand-new models, textures, AI, and pathfinding (a datapack can't touch client assets or entity behavior); adding mobs to biomes that never had that category (that requires changing world generation); making mobs affect each other causally, such as "spiders eat bugs" (that's the behavior layer's job).

## Where the Source Is

| Directory | What's inside |
|---|---|
| [`doom.nats/`](doom.nats/data/doom.nats/function) | The datapack itself; open it to browse every function file |
| [`src/`](src/) | JavaScript generators, the rules layer, generation inputs |
| [`dist/`](dist/) | Finished zips |

If you just want to play, grab a zip from `dist/`. To modify the pack yourself, follow the three steps in [src/README.md](src/README.md): run the generators, `check_static`, then install/package.

The real-hardware test bench, round-by-round acceptance reports, and CI live on the author's machine and aren't distributed with the repo. The acceptance criteria and per-version real-hardware numbers live there.

## Documentation

| What you want | Where to go |
|---|---|
| Install, upgrade, uninstall | [docs/wiki/安装与升级.md](docs/wiki/安装与升级.md), [docs/16-生存直用手册.md](docs/16-生存直用手册.md) |
| Change rules in game | [docs/wiki/示例库.md](docs/wiki/示例库.md), [docs/wiki/规则字段参考.md](docs/wiki/规则字段参考.md) |
| Everything you can change | [docs/24-玩家能改动的一切.md](docs/24-玩家能改动的一切.md) |
| Per-entity differences from vanilla | [docs/17-逐实体刷怪规则核对.md](docs/17-逐实体刷怪规则核对.md) |
| Versions and compatibility | [docs/25-兼容与版本.md](docs/25-兼容与版本.md), [CHANGELOG](CHANGELOG.md) |
| License and credits | [docs/26-致谢与许可.md](docs/26-致谢与许可.md) |
| All documentation | [docs/README.md](docs/README.md) |

The illustrated Wiki is at <https://github.com/Doom-Flare/doom.nats/wiki>. If it won't open, `docs/wiki/` holds the Markdown source of those 9 pages.

## Repository Layout

```
README.md  LICENSE  CHANGELOG.md   docs / license / changelog
dist/                              The only downloads: the zips and SHA256SUMS.txt
ports/                             Source tree of the pack for each MC version range
doom.nats/                         A copy of the datapack itself, directly browsable
src/                               Source: generators tools/ + rules layer rules/ + generation inputs
docs/                              Player-facing docs; docs/wiki/ is the Wiki's Markdown source
.github/ISSUE_TEMPLATE/            Forms for filing bugs and requesting features
```

`.gitignore` filters out local artifacts; `.gitattributes` makes artifacts compare byte-for-byte with no line-ending conversion.

## Reporting Issues

Use the [Issues](https://github.com/Doom-Flare/doom.nats/issues/new/choose) forms. They'll ask for your version, variant, a `logs/latest.log` snippet, and screenshots. Filling out the form properly speeds things up a lot.

## License

All Rights Reserved · Beta. Personal use, playing, and passing it on unchanged are fine; to republish a modified version or use it commercially, get permission first.

This pack contains no Minecraft or Mojang assets and no decompiled output; only the datapack itself ships with it. Full text in [docs/26-致谢与许可.md](docs/26-致谢与许可.md).
