# Experimental Variant v4x

中文: `docs/wiki/实验性变体-v4x.md`

The experimental variant = the default variant + capabilities beyond vanilla (only spawn when something is nearby, spawn show, preset packs; the source for the custom appearance bridge is there, but was not released with this version's build, see the table below). It carries an engine gate: the world must have the corresponding experimental gameplay enabled at creation time, otherwise the pack is refused at load (not a warning).

## 1. Download and Installation

1. Download `dist/doom.nats-v4x-experimental-v4.31.0.zip`
2. Unzip, put `doom.nats/` into `<save>/datapacks/` (on a server `world/datapacks/`)
3. Create a new world (or edit the enabled experimental gameplay in `level.dat`), and turn on the corresponding experimental gameplay switch
4. `/reload`

> **An old save without experimental gameplay enabled ⇒ it will not install**. This is not a bug, it is the engine gate. If you want an easy time, use the default variant.

## 2. What the Engine Gate Actually Is

The pack's `pack.mcmeta` declares the required experimental flags. If the game side does not satisfy them, the whole pack is refused at load.

For 1.21.6, a datapack can borrow only three native flags:

| Flag | What you also get when it is on |
|---|---|
| `minecart_improvements` | the minecart-related vanilla changes |
| `redstone_experiments` | the redstone-related vanilla changes |
| `trade_rebalance` | the trading rebalance |

Opening this gate means your world also takes in the corresponding vanilla changes. This is "borrowing a path", not a "clean switch".

## 3. Capabilities Beyond Vanilla

| Capability | How to write it | Effect |
|---|---|---|
| `near` | add `when:{near:{type:"minecraft:wolf",radius:24,min:1}}` to an entry | only spawns when something is nearby (sheep appear only near a wolf pack) |
| `on_spawn` | add `on_spawn:1b` to an entry, then create `data/doom.nats/function/exp/on_spawn/<entry id>.mcfunction` in the datapack | spawn show: particles / sounds / announcements / extra NBT |
| Preset packs | `/data merge storage doom.nats:exp_in {name:"<name>"}` → `/function doom.nats:exp/preset` | switch worldviews in one click: `blood_moon` / `storm_season` / `deep_dark` (a measured entry point; `exp/preset` is a no-argument macro dispatch) |
| Custom appearance (AJ bridge) | build-time rule `rules/rigs.json`; the source is there in `src/tools/gen_exp_aj.mjs` and was not released with the v4.25/v4.28/v4.29/v4.30.0 builds. This repo's `rules/rigs.json` is `{}` (0 `exp/aj` entries in the release zip); to use it you must supply your own non-empty config (sample `src/rules/examples/aj/rigs.json`), then re-run the generator with `DOOM_EXP=1` | a real entity as the core + a rig as the appearance (`ride` mounting): the core moves/despawns as usual, the appearance follows block by block |
| Sampling from the mob in your hand | `/function doom.nats:author/add_entry` | turns the appearance of the mob in your hand (including NBT) directly into a rule |

The custom appearance has two key behaviors (measured on an experimental build made with a non-empty rigs config, not on any release):

- positional error 0.0000 blocks (follows block by block)
- the cap counts only the core, so mounting 10 rigs will not blow up the mobcap

## 4. Two Examples You Can Copy and Use

Sheep only spawn when a wolf is nearby

```
/data modify storage doom.nats:author entries append value {id:"wolf_sheep",biome:"#minecraft:is_forest",category:"creature",mob:"minecraft:sheep",weight:100000,when:{near:{type:"minecraft:wolf",radius:24,min:1}}}
```

In a thunderstorm over the deep ocean, the zombie's entrance fires lightning and thunder

> `on_spawn:1b` only opens the hook; the show itself must be written as a function file `data/doom.nats/function/exp/on_spawn/thunder_king.mcfunction`, containing `particle minecraft:flash ~ ~1 ~ 0 0 0 0 1` and `playsound minecraft:entity.lightning_bolt.thunder hostile @a ~ ~ ~ 1 1`.

```
/data modify storage doom.nats:author entries append value {id:"thunder_king",biome:"#minecraft:is_deep_ocean",category:"monster",mob:"minecraft:zombie",weight:50000,when:{thundering:true},on_spawn:1b}
```

## 5. Caveats

- Rules changed at runtime (including `near` / `on_spawn` / presets) are ignored in the default variant. It is not that they fail to take effect; that code is simply not in the pack at all.
- `author/export` can pack the current overrides into a one-line copyable command; but anything exported using experimental capabilities can only be restored in an experimental variant's world.
- Do not install the default variant and the experimental variant at the same time.
- The engine gate only recognizes the flags declared in `pack.mcmeta`; 1.21.6 has no clean switch for "datapack experiments only", so weigh it up before going in.

> For the per-field table (`src/rules/rigs.json`) see [src/rules/README.md](https://github.com/Doom-Flare/doom.nats/blob/main/src/rules/README.md).
