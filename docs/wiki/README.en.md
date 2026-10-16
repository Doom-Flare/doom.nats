# Wiki Source Files (9 pages + sidebar/footer)

中文: `docs/wiki/README.md`

These 9 `.md` files are the page sources of this datapack's GitHub Wiki; a page's title = the file name (minus `.md`);
`_Sidebar.md` and `_Footer.md` are the GitHub Wiki's global sidebar and footer (they do not take a page title), and the push script brings them along.

| File | Page |
|---|---|
| `Home.md` | Home (one-screen quick start) |
| `安装与升级.md` | Installation and Upgrade |
| `快速上手-在游戏里改规则.md` | Quick Start |
| `规则字段参考.md` | Rule Field Reference |
| `示例库.md` | Example Library |
| `实验性变体-v4x.md` | Experimental Variant |
| `FAQ.md` | FAQ |
| `版本与验收.md` | Versions and Acceptance |
| `已知限制.md` | Known Limitations |
| `_Sidebar.md` | Global sidebar (shown on every page) |
| `_Footer.md` | Global footer (field-table authority + license) |

Target address: <https://github.com/Doom-Flare/doom.nats/wiki>

## Why the Content Lives Here

GitHub's Wiki has a platform limitation: the repository must already have one Wiki page before `<repo>.wiki.git` exists and can be cloned / pushed; before then `git ls-remote` reports `Repository not found`, and the REST API has no endpoint for creating a Wiki page either (`/wiki/pages` returns 404).

So the content ships with the repository as Markdown sources first, and you pick either route:

### Route A: Paste in the web UI (zero dependencies, 9 times)

Go to <https://github.com/Doom-Flare/doom.nats/wiki>, click Create the first page (create the home page, set the title to `Home`, the body can just be saved for now), then for each further page use New Page to create a page with the same name and paste the corresponding `.md` content in whole and save.

### Route B: Push with a script (do the first step of Route A once first)

1. Click Create the first page once in the web UI (even if the content is just "placeholder"), and save
2. Back on your machine, clone this repository and run:

```bash
bash docs/wiki/push-wiki.sh
```

The script pushes all 9 pages up in one go (overwriting pages with the same name), then deletes the temporary clone directory.

## Maintenance Conventions

- Cross-page links inside a page use the Wiki-native syntax `[[page name]]`; remember to keep them in sync when renaming.
- If the field table conflicts with this repository's `src/rules/README.md`, `src/rules/README.md` prevails.
- Every page follows the same pattern: conclusion first, then the command, then the caveats; commands go in code blocks; do not write repository-internal details.
