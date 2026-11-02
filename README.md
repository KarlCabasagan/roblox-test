# roblox-test

Roblox place built with [Rojo](https://rojo.space/) and version-controlled in Git.

## Requirements

- [Rojo](https://rojo.space/docs/) (tested with 7.7.1) — `npm install -g rojo`
- [Roblox Studio](https://create.roblox.com/) with the Rojo plugin

## Getting started

```powershell
rojo serve default.project.json
```

Open Studio, open the Rojo plugin, click **Connect**. Files under `src/` now sync
into your place live.

## Project structure

| Path | Syncs to |
| --- | --- |
| `src/server` | `ServerScriptService.Server` |
| `src/client` | `StarterPlayer.StarterPlayerScripts.Client` |
| `src/shared` | `ReplicatedStorage.Shared` |

## Contributing workflow

See [AGENTS.md](AGENTS.md) for the branch, commit, and verification rules.
