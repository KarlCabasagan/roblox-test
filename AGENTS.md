# roblox-test — Roblox + Rojo + Git workflow

Development workspace for a Roblox place driven by **Rojo**: scripts and UI live
as files here, and Rojo syncs them into the open Roblox Studio session.

## Layout

```
src/server   -> ServerScriptService.Server        (server-only code)
src/client   -> StarterPlayer.StarterPlayerScripts.Client  (client-only code)
src/shared   -> ReplicatedStorage.Shared          (pure modules usable by both)
```

Suffixes matter to Rojo: `*.server.luau` becomes a `Script`, `*.client.luau` a
`LocalScript`, and plain `*.luau` a `ModuleScript`. A folder `init.luau` becomes
the module for that folder.

## Session start — read this first

A fresh agent session has no memory of previous conversations. These are the
facts and traps that are expensive to rediscover.

### The MCP connection and its false negative

Roblox Studio is connected to this agent through the `Roblox_Studio` MCP server,
which DSH spawns as `cmd.exe /c <LOCALAPPDATA>\Roblox\mcp.bat` (see
`~/.dsh/profiles/desktop/cordis.patch.yml`).

**Studio's MCP panel often says "No client connected" while the connection is
fully working.** Studio reports on its own client registry, but traffic actually
flows through a local `StudioMCP.exe` proxy that Studio dials out to. The panel
counter never reflects that path. Do not try to "fix" this; do not kill
`StudioMCP.exe`. Killing the proxy risks breaking a working connection because
Studio has no way to rediscover a respawned proxy on a new port.

Verify the connection with calls that cannot lie:

1. `list_roblox_studios` — returns the live studio id and place name.
2. `get_console_output` — returns the current Studio Output log.
3. `execute_luau` printing a line — the human sees it in Studio Output.

**The studio id changes on every Studio restart.** Never cache it. Always call
`list_roblox_studios` at the start of a session and before any place-mutating
call.

### Start the sync server

`rojo serve` does not survive a harness restart. Start it as a background job
before touching `src/`, then have the human click **Connect** in the Studio Rojo
plugin (one time per Studio session):

```powershell
rojo serve default.project.json
```

The port is chosen dynamically and printed on startup; the plugin defaults to
the same one.

### Snapshot the place

Scripts are covered by Git. Geometry, lighting, and hand-placed instances are
not — those live only in the data model. Capture a restore point from Studio's
own auto-recovery file:

```
%LOCALAPPDATA%\Roblox\RobloxStudio\AutoSaves\Template_<id>_AutoRecovery_0.rbxl
```

Copy the newest one matching the open place into `backups/place-<ISO timestamp>.rbxl`
and commit it. See `backups/README.md` for provenance and restore steps.

There is **no scripting API to export a place**: `StudioService` reports
`can_save: false`, and `AssetService:SavePlaceAsync` fails with
`placeID is not valid` on unpublished places. The autosave copy is the only
automated route.

### Tool scope guardrails

These tools have effects **outside** the place and are not undoable. Do not call
them unless the human names the specific action or asset:

| Tool | Why it needs consent |
|---|---|
| `upload_image` | Uploads assets to their Roblox account; consumes quota |
| `insert_asset` | Pulls Creator Store / inventory content into the place |
| `generate_mesh` / `generate_material` / `generate_texture` / `generate_procedural_model` / `generate_scene` | Billed generation against their account |

Read-only tools (`script_read`, `script_grep`, `search_game_tree`,
`inspect_instance`, `get_console_output`, `get_studio_state`, `screen_capture`)
need no gate. Prefer them for exploration.

### Working with the data model

- Check `get_studio_state` before calling anything that needs a datamodel type.
  `Edit` operations are rejected while play mode is running; stop play first.
- `search_game_tree` output is large. Always pass `path`, `max_depth`, and
  `head_limit`. A bare full-tree traversal pulls in the `Stats` service and
  floods context with thousands of useless nodes.
- After a playtest, stop play mode before making further `Edit` changes.

## Environment

- Rojo 7.7.1 (installed globally via npm, `rojo.cmd` on PATH)
- Roblox Studio with the Rojo plugin (`Rojo.rbxm` in `%LOCALAPPDATA%\Roblox\Plugins`)
- Git remote: `https://github.com/KarlCabasagan/roblox-test.git`
- Place: **Test**, placeId `124568098578723` (published). The id changes per session; resolve it via `list_roblox_studios`.

## Agent workflow (the rules for this repo)

### 1. Branch per feature

Never commit directly to `main`. Start each feature on a branch:

```
feat/<short-name>      new feature
fix/<short-name>       bug fix
chore/<short-name>     tooling, refactor, docs
```

### 2. Commit granularity: one commit per completed step

Commit as each step completes — not one giant commit at the end of a feature.
A "step" is an independently meaningful unit: a module written, a UI wired up, a
bug fixed. Use conventional-commit messages:

```
feat(shop): add purchase button UI
feat(shop): validate purchase on server
fix(ui): correct button size on mobile
```

### 3. Completion gate before calling a feature done

A feature is only complete when it has been **verified in play mode**, not when
the code merely looks right:

1. Sync to Studio.
2. Start play mode and confirm `get_console_output` shows no errors.
3. Exercise the actual behaviour.
4. Only then commit the final step and push.

### 4. Push, never auto-merge

Push the feature branch and stop. Do not merge to `main` and do not open a PR
unless explicitly asked. The human reviews the diff on GitHub and merges.

```
git push -u origin feat/<short-name>
```

### 5. Report a test checklist

When a feature is finished, output a numbered list of **concrete things the human
can test** in Studio — what to click, what should happen, and what would indicate
a failure. Be specific; "verify the shop works" is not a test.

## Sync direction (important)

Rojo `serve` pushes **disk -> Studio**. Edits made by hand inside Studio are not
captured automatically and can be overwritten on the next sync.

The human does not hand-edit scripts; Studio is used to observe and test. If
Studio-side changes ever do need to be captured, run `rojo syncback` on a branch
first so the drift shows up in the diff instead of being silently lost.
