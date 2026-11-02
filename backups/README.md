# Place snapshots

Binary `.rbxl` copies of the Roblox place, kept as restore points.

## Why these exist

Git tracks `src/` — every script and UI module Rojo manages. It cannot track
what lives *only* in the data model: parts, terrain, lighting settings, and
`StarterGui` instances placed by hand.

A `.rbxl` here closes that gap. A file here is **not** a source of truth and
must never be edited by hand — it exists so the place can be recovered if
something goes badly wrong.

## How they are produced

Roblox Studio has no scripting API to export a place (its save methods are
`PluginSecurity` and require an already-published place). Snapshots are
therefore captured from Studio's own auto-recovery files:

```
%LOCALAPPDATA%\Roblox\RobloxStudio\AutoSaves\Template_<id>_AutoRecovery_0.rbxl
```

The newest autosave matching the open place is copied here, renamed with its
capture timestamp.

## Provenance and limits

- An autosave reflects the **last autosave interval**, not this second. A
  snapshot can lag recent edits.
- It is derived from the baseplate template the place was created from, so it
  carries that template's identity, not a published place ID.
- Script content is compressed in this binary format, so the file cannot be
  audited with a text search. Trust `src/` for code, this file for geometry.

## Restore

Open the file directly in Studio (`File → Open from File`). Rename the target
if you want to keep the current working place intact alongside it.

## Naming

`place-<ISO-8601 timestamp>.rbxl`, e.g. `place-2026-11-02T1043.rbxl`.
Use `placeId-<id>-<timestamp>.rbxl` once the place is published.
