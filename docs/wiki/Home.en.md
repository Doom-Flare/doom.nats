# doom.nats · Vanilla Natural Spawning Replica (Datapack · Minecraft 1.21.5 to 26.3)

中文: `docs/wiki/Home.md`

Replicating Minecraft's vanilla natural spawning (global caps, light and per-entity rules, biome species tables, structure overrides, the despawn layer) with a pure datapack. Every rule is open to you: one command in game changes it, and it takes effect on the next tick.

By default nothing is changed, so it equals vanilla. This is a contract verified automatically on every release.

## Which One to Download

| Download this | What it is | Who it suits |
|---|---|---|
| [doom.nats-v4.30.0.zip](https://github.com/Doom-Flare/doom.nats/releases/download/v4.30.0/doom.nats-v4.30.0.zip) | Default variant: item-by-item replication of vanilla natural spawning | Most people (recommended) |
| [doom.nats-v4x-experimental-v4.30.0.zip](https://github.com/Doom-Flare/doom.nats/releases/download/v4.30.0/doom.nats-v4x-experimental-v4.30.0.zip) | Everything in the default variant + capabilities beyond vanilla (only spawn when something is nearby, spawn effects, preset packs) | People who want to play with more, and are willing to enable the matching experimental gameplay when creating the world |
| [All downloads / checksums](https://github.com/Doom-Flare/doom.nats/releases) | sha256 attachments of both zips | People who want to confirm the download is complete |

> The experimental variant carries an engine gate: if the world has not enabled the matching experimental gameplay, it will not install (not a warning). See [[实验性变体-v4x]].
>
> Custom appearance (the AJ bridge) is not in either zip: the source is there (`src/tools/gen_exp_aj.mjs`), but it was not released with the v4.25/v4.28/v4.29/v4.30.0 builds. To produce it you must supply your own non-empty `rules/rigs.json` (sample `src/rules/examples/aj/rigs.json`) and re-run `gen_exp_aj` with `DOOM_EXP=1` (together with `gen_pack` / `gen_mobs`). This repo's `src/rules/rigs.json` is `{}`, so the release zips contain 0 `exp/aj` entries.

## Install in Three Steps

1. Unzip `doom.nats-v4.30.0.zip` to get a `doom.nats/` folder
2. Drop the whole `doom.nats/` into `<save>/datapacks/` (on a server: `world/datapacks/`)
3. Go in game and run `/reload`

If this line shows up in chat, it is installed:

```
[nats] mode/survival —— 已接管自然生成（doMobSpawning=false）
```

## Where to Go Next

| What you want to do | See this page |
|---|---|
| Install, upgrade, uninstall | [[安装与升级]] |
| Change spawning rules in game | [[快速上手-在游戏里改规则]] |
| What every field is and what it accepts | [[规则字段参考]] |
| Examples you can copy and use | [[示例库]] |
| Only spawn sheep when a wolf is nearby, thunder at spawn | [[实验性变体-v4x]] |
| Common questions (nothing spawns, frame drops, multiplayer) | [[FAQ]] |
| Acceptance criteria and the latest numbers | [[版本与验收]] |
| Things it explicitly cannot do | [[已知限制]] |

## Two Sentences of Caution

- This is currently Beta (public testing): known deviations are documented one by one and are not all fixed yet. **You can install it into a save and play, but please back up the save first.**
- License: All Rights Reserved · Beta. Personal use / playing / passing it on unchanged is fine; to republish a modified version or use it commercially, get permission first.

> The source and the generators are right in this repository at [`src/`](https://github.com/Doom-Flare/doom.nats/tree/main/src); the real-hardware test bench and the round-by-round acceptance reports are not distributed with this repository. This repository holds only what players need.
