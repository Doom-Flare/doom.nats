# What This Is

中文: `src/README.md`

**The source of this pack**: JavaScript generators (which generate rules into datapack functions) + the rule layer (`rules/`) + generation inputs (`_work/generated/`).

- Just want to play: **do not use this directory**; go download the zip in `dist/` (unzip it and drop it into `saves/<存档>/datapacks/`).
- Want to modify the pack / see the implementation: start here and follow the "three-step build" below.
- Want the more complete development environment (test bench, acceptance reports, CI): that is the author's local setup and is not distributed with this repository.

---

# src/ — The Source of This Repository (Generators + Rule Layer + Generation Inputs)

> **In one line**: this is the **source** — the set of generators that produce the datapack (`tools/`), the author rule layer (`rules/`), and the generators' input data (`_work/generated/`).
> **To modify the pack** (change numbers, change rules, add entries), follow the "three-step build" below; **to take part in development** (a real-machine acceptance bench, round-by-round reports, CI) you need the author's local test environment (not distributed with this repository).

First keep two things apart — this is also the thing most people ask about:

| Location | What it is | For whom |
|---|---|---|
| [`dist/`](../dist) | **Finished product**: `doom.nats-v4.30.1.zip` (default variant) + `doom.nats-v4x-experimental-v4.30.1.zip` (experimental variant); checksums in `dist/SHA256SUMS.txt` | Players who only want to install it into a world — **this is probably all you need** |
| `src/` (this directory) | **Source**: generators + rule layer + generation inputs. **It cannot be dropped into a world directly**; you have to run the generators first to turn it into `pack/` | People who want to modify the pack, and people who want to know "how it actually computes things" |

## Three-Step Build

Prerequisite: **Node.js 18+** (no network needed, no Minecraft needed, no dependencies to install).

```
# ① Generate the datapack (artifacts land in pack/ at the repo root; pack/ is not committed, overwritten on every run)
cd <仓库根>

node src/tools/gen_pack.mjs
node src/tools/gen_pos.mjs
node src/tools/gen_check.mjs
node src/tools/gen_mobs.mjs
node src/tools/gen_spawn.mjs
node src/tools/gen_despawn.mjs
node src/tools/gen_effects.mjs
node src/tools/gen_debug.mjs
node src/tools/gen_group.mjs
node src/tools/gen_author.mjs
#   Experimental variant (one extra exp/* layer) = the 10 above plus gen_exp / gen_exp_aj, all rerun with DOOM_EXP=1;
#   or, to take the lazy route: just run ②, and check_static will build the experimental variant itself.

# ② Static gate (generator drift + lint + reference closure) — this step is the answer to "I didn't break what I changed"
node src/tools/check_static.mjs          # default + experimental variants; experimental only: add --exp
#   Expected output: default variant 0 error / 2 warning · experimental variant 0 error / 2 warning

# ③ Install / package
#   Install into a world: copy pack/doom.nats as a whole into <world>/datapacks/ (server world/datapacks/) → in-game /reload
#   Package for distribution: zip up pack/doom.nats; **the top level inside the zip must be doom.nats/** (same shape as the artifacts in dist/)
```

How paths are resolved: every generator goes through [`tools/lib/packdir.mjs`](tools/lib/packdir.mjs);
the parent of `src/` is the repo root, and artifacts land in `<repo root>/pack/doom.nats` (`DOOM_EXP=1` ⇒ `pack/doom.nats-experimental`);
to write elsewhere, set `DOOM_OUTDIR=<directory>` (this is how the acceptance scripts isolate their builds).

## What Is in the Directory

> Scope: this directory carries the **complete source of the v4 line (this datapack)** — 12 generators + the shared `lib/` + three static gates + a real-machine test bench + the rule layer + generation inputs.
> The tools of the historical lines (v1–v3 / port / optimize) are not in it, for the reason given in the "what runs as-is" table below.

| Path | Contents |
|---|---|
| `tools/gen_*.mjs` | **Generators**: one generator per layer (pack skeleton / point selection / checks / species / spawn chain / despawn / effects / debug / group data / author layer). **Modifying the pack = modify a generator and rerun**; do not hand-edit the artifacts in `pack/` (`--check` compares byte by byte, hand edits are always caught) |
| `tools/lib/` | Libraries shared by the generators: path resolution, vanilla rule tables, author-layer parsing, SNBT, AABB interpolation, experimental rig validation… |
| `tools/check_static.mjs` | **Static master gate**: `--check` for both variants' generators + `lint_pack` + `check_closure` |
| `tools/lint_pack.mjs` · `check_closure.mjs` · `check_leak.mjs` | Individual gates: artifact lint (L1–L14) · function/storage/scoreboard reference closure · leaks and repo top-level structure |
| `rules/` | **Author rule layer** (build-time input): `entity-rules.json` / `entries.json` / `counts.json` / `rigs.json`, **all empty by default = vanilla behavior**. Field manual and four use cases: [`rules/README.md`](rules/README.md) and `rules/examples/` |
| `_work/generated/*.json` | **The generators' input data** (biome spawn tables, biome tags, hitboxes, per-entity rules, category tables… exported from the vanilla 1.21.6 jar). They **are part of the source, do not delete them** — without them the generators cannot run |
| `tools/_root.mjs`, `install.mjs`, `mcauto.mjs`, `mcrcon.mjs`, `collect.mjs`, `regress.mjs`… | The real-machine test bench: the code is here and can be read and changed, but **putting it to use needs a running server / a world** (the bench itself is not distributed with this repository) |

## What Runs As-Is and What Doesn't (Measured)

"Runs as-is" in the table below was run item by item **in a clean clone** (Node 18+, no extra files beyond this directory):

| Runs as-is | Notes |
|---|---|
| `node src/tools/gen_*.mjs` (12 generators) | both generation and `--check` work; reads only `src/rules/` and `src/_work/generated/` |
| `node src/tools/check_static.mjs` | **actually run and passed in the clone**: default variant 0 error / 2 warning · experimental variant 0 error / 2 warning (same with `--exp`) |
| `node src/tools/lint_pack.mjs <产物目录>` | run artifact lint on its own |
| `node src/tools/check_closure.mjs` | function / storage / scoreboard reference closure |
| `node src/tools/check_leak.mjs` | leak + top-level structure gate (when local git is not on PATH: `DOOM_GIT=<full path to git> node src/tools/check_leak.mjs`; when not inside a git repository, add `DOOM_TOP=off`) |
| `node src/tools/sim_v4.mjs 400` | run the v4 core in a headless interpreter. **It runs, but the summary will have 3 FAILs**: the log sink `harness/doom.log` belongs to the test bench and is not published with this repository |

| Doesn't run as-is (needs the author's local environment or an external environment) | Why |
|---|---|
| `install.mjs` / `mcauto.mjs` / `mcrcon.mjs` / `collect.mjs` / `regress.mjs` | Real-machine kind: needs a server with RCON open, a world, and the `harness/` test bench (none of these ship with this repository; ordinary players should not touch them either) |
| `export_biomes.mjs` / `export_rosters.mjs` / `export_biome_tags.mjs` / `export_mobs.mjs` | needs the **vanilla 1.21.6 jar** to re-export the biome spawn tables (the exported results already sit in `_work/generated/`; day-to-day pack edits do not need a re-export) |
| `export_hitboxes.mjs` | needs the **decompiled artifact** `_work/decomp/named.jar`; decompiled artifacts are not published with any repository |
| the toolset of the historical lines (v1–v3 / port / optimize) | **not published with the source** (`doomify.mjs` · `port.mjs` · `optimize.mjs` · `verify.mjs` · `sim.mjs` · `viz.mjs` and their dedicated `tools/rules/`, `lib/exttag.mjs`, `lib/simrun.mjs`, `lib/snbt.mjs`): they deal with the four directories `original/` `ported/` `optimized/` `v3/`, which are **not in this repository** and which still carry the old project name (it must not appear in a player-facing repository). They are not distributed with this repository — what this directory carries is the **complete source of the v4 line** |
| `propose_tags.mjs` | needs the terrain file (`.mca`) of a real world to tally the block distribution at landing points |
| `lint_spyglass.mjs` | needs Spyglass installed locally; it is an optional tool, not a generation dependency |

## How to Modify the Pack (Three Typical Cases)

1. **Adjust numbers**: edit `src/rules/counts.json` (the count curves by Y band) or the vanilla vocabulary in `tools/lib/entity-rules.mjs` → rerun the generators → run `check_static`.
2. **Add entries**: edit `src/rules/entries.json` (conditional spawn entries, may carry NBT); the four use cases are in `src/rules/examples/full/`.
3. **Change the implementation**: edit only `tools/gen_*.mjs`, then **rerun the whole set in the order of ①** (layers depend on one another: pack → pos → check → mobs → spawn → despawn → effects → debug → group → author).

After changing `rules/`, always rerun the generators — it is a **build-time** input, and changing the files without regenerating means nothing took effect.
The layer you can change on the spot in-game (`storage doom.nats:author`) is in [`../docs/24-玩家能改动的一切.md`](../docs/24-玩家能改动的一切.md).

## Known Discrepancies (Honest List)

The editor hint file `mcdoc/doom.nats/config.mcdoc` **has no generator responsible for it**; it is a hand-written file (see
[`../docs/21-玩家可改清单.md`](../docs/21-玩家可改清单.md)). Generators write only the files they are responsible for and do not delete
anything else, so regenerating in place keeps it. If you generate into an empty directory instead, the resulting pack will lack this one file.

File counts in each place:

| Location | File count |
|---|---|
| `pack/doom.nats` (generator artifacts) | 700 |
| `pack/doom.nats-experimental` (experimental) | 777 |
| `dist/doom.nats-v4.30.1.zip` | 700 |
| `dist/doom.nats-v4x-experimental-v4.30.1.zip` | 777 |
| the repo top-level [`doom.nats/`](../doom.nats) | 700 |

The repo top-level `doom.nats/` is **identical item by item** to the zips (0 missing, 0 extra, 0 with different content), and likewise identical to `ports/doom.nats-1.21.6-1.21.8`.
- For the sha256 of both zips see [`dist/SHA256SUMS.txt`](../dist/SHA256SUMS.txt).

## Contributing

The generators are only half a table. The other half — the real-machine acceptance bench (`tests/`), the round-by-round evidence reports (`reports/`), CI, the log sink `harness/` —
keeps its acceptance criteria and each version's real-machine numbers filed on the author's machine, and is not distributed with this repository.

License: see [`../LICENSE`](../LICENSE): **All Rights Reserved · Beta** — personal use / playing / verbatim redistribution is fine; republishing a modified version or using it commercially requires permission first.
