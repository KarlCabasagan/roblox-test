# roblox-test

A chess variant built for Roblox with [Rojo](https://rojo.space/), version-controlled in Git.

Ten files wide, eight ranks deep, and two pieces that do not exist in chess.

## Requirements

- [Rojo](https://rojo.space/docs/) (tested with 7.7.1) — `npm install -g rojo`
- [Roblox Studio](https://create.roblox.com/) with the Rojo plugin

## Getting started

```powershell
rojo serve default.project.json
```

Open Studio, open the Rojo plugin, click **Connect**. Files under `src/` now sync
into your place live. Press Play to build the table and open the panel.

## The game

The board is 10 files by 8 ranks. Both armies are the full standard set, plus a
**Hexer** and a **Rift**, so each side fields 20 pieces.

| Piece | Moves | Notes |
| --- | --- | --- |
| Pawn | one forward, two from home rank, diagonal capture | promotes into any of six pieces, including the custom ones |
| Knight | standard leap | |
| Bishop | standard diagonal slide | |
| Rook | standard orthogonal slide | |
| Queen | slides any direction | |
| King | one square any direction | castling on the a and j files |
| **Hexer** | slides diagonally like a bishop | once per game, may swap squares with any friendly piece anywhere on the board |
| **Rift** | leaps exactly two squares orthogonally or diagonally, over anything | a leaper, so blockers are irrelevant |

Standard rules apply otherwise: castling, en passant, checkmate, stalemate,
threefold repetition, the fifty-move rule, and insufficient material. Kings can
never be captured; every move is filtered through "does this leave my king
attacked".

## Playing

- **2D panel** — the play surface. Tap a piece, then a highlighted square. Works
  with mouse, touch, and gamepad because it is ordinary GUI input.
- **3D table** — the world representation, visible to anyone walking past. It
  mirrors the live game and highlights the last move. It is not clickable.
- **Lobby** — choose *Play vs Bot* (Easy, Medium, or Hard) or *Play vs Player*,
  which queues you for the next opponent. Everyone not seated spectates.
- **Resign** ends the current game. A player who leaves forfeits after 60 seconds.

The server owns the position. Clients send the squares they clicked; the server
decides whether the move is legal and whether it is that player's turn.

## Project structure

| Path | Syncs to | Contents |
| --- | --- | --- |
| `src/shared/Chess` | `ReplicatedStorage.Shared.Chess` | rules engine, bot, wire format |
| `src/server` | `ServerScriptService.Server` | match manager, 3D table, remotes |
| `src/client` | `StarterPlayer.StarterPlayerScripts.Client` | 2D panel, lobby, HUD |

The engine is pure: `Config` holds every constant (including board dimensions),
`Board` owns the grid and state, `Moves` generates pseudo-legal moves and detects
attacks, `Rules` filters for king safety and detects terminal positions, and
`Bot` searches.

## Engine self-test

The rules engine is checked headlessly, without a play session:

```lua
local report = require(game.ReplicatedStorage.Shared.Chess.SelfTest).run()
print(report.summary)
```

Fourteen checks cover the opening move count, en passant, castling in both
directions and its refusal through check, pins, checkmate, stalemate, promotion
into every piece, Hexer swap consumption, Rift leaping, bot legality per tier,
and that applying a move never mutates the source state.

## Contributing workflow

See [AGENTS.md](AGENTS.md) for the branch, commit, and verification rules.
