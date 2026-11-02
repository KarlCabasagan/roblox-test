# robox-test — Roblox + Rojo + Git workflow

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

## Environment

- Rojo 7.7.1 (installed globally via npm, `rojo.cmd` on PATH)
- Roblox Studio with the Rojo plugin installed
- Git remote: `https://github.com/KarlCabasagan/roblox-test.git`

Start the live sync before working in Studio:

```powershell
rojo serve default.project.json
```

Then in Studio open the Rojo plugin and click **Connect**.

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
