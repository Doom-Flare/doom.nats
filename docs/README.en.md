# Documentation Index (player-facing)

中文: `docs/README.md`

> The datapack itself is in [`../dist/`](../dist): unzip the archive to get a `doom.nats/` folder, drop the whole thing into `saves/<save>/datapacks/` (on a server, `world/datapacks/`), then `/reload` in game.
> Finished builds live in [`../dist/`](../dist), source in [`../src/`](../src/README.md): to modify the pack, follow the three-step build in `src/README.md`.
> Where documents in this directory mention paths like `tools/*` and `_work/*`, they mostly refer to this repo's [`../src/`](../src/README.md) (both the generators and the generation inputs live there);
> Only the real-hardware test bench (`tests/`, `harness/`) and the round-by-round reports (`reports/`) are things on the author's machine, not distributed with this repo.

| Document | Corresponding version | What it covers |
|---|---|---|
| [13-v4使用手册](13-v4使用手册.md) | v4.1 (historical snapshot) | Overview + complete usage for map authors |
| [16-生存直用手册](16-生存直用手册.md) | v4.12 (historical snapshot) | Install in three steps, use it straight in survival |
| [17-逐实体刷怪规则核对](17-逐实体刷怪规则核对.md) | v4.13 | Per-entity comparison against vanilla rules (checklist) |
| [18-配置手册](18-配置手册.md) | v4.14 | Switches, tag interface, the engine gate of the experimental variant |
| [19-finalizeSpawn与组数据](19-finalizeSpawn与组数据.md) | v4.15 | The layer for baby rates / shared variants / group effects |
| [21-玩家可改清单](21-玩家可改清单.md) | Save snapshot (v4.17–v4.18) | Tags and files you can change (quick reference) |
| [24-玩家能改动的一切](24-玩家能改动的一切.md) | Save snapshot | Full list: runtime storage / build-time rules / runtime knobs / tag interface |
| [rules/README.md](../src/rules/README.md) | v4.23 (v4.25 added a rigs section) | The author rules layer: field table + four complete use cases (source in [`src/rules/`](../src/rules/README.md)) |
| [25-兼容与版本](25-兼容与版本.md) | v4.30.0 (current) | Version × variant × whether experimental gameplay is needed (see at a glance which to download) |
| [26-致谢与许可](26-致谢与许可.md) | v4.30.0 | License summary, third-party boundaries, credits |
| [图-首屏效果位](图-首屏效果位.md) | Documentation convention (not version-bound) | How the README hero image is shot and wired in (placeholder notes) |
| [wiki/](wiki/) | Save snapshot (around v4.30.0) | The Wiki's 9 pages of Markdown source: Home / 安装与升级 / 快速上手 / 规则字段参考 / 示例库 / 实验性变体 / FAQ / 版本与验收 / 已知限制. Target: <https://github.com/Doom-Flare/doom.nats/wiki> |

> "Corresponding version" = the version at the time this document was written. The two marked "historical snapshot" haven't been updated along the way; their body text is kept as written then, and a note has been added at the top.
> For the current state, see the [CHANGELOG](../CHANGELOG.md) and [24-玩家能改动的一切](24-玩家能改动的一切.md).
