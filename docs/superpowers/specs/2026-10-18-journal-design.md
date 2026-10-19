# Cipherbook Journal — design

## Intent
A Journal section in Cipherbook. You type entries on parchment pages; finishing an entry
zooms out to a wall where stacks of pages can be moved freely or snapped to a grid.
Pages look unique and physical. Entries sync to a private server on the Pi and are
ingested on the desktop into `~/knowledge/` + Qdrant for AI recall. Single user, private.

## Decisions (agreed)
- Input: typed (system or cipher keyboard). Handwriting is out of scope.
- Pages: fixed size, text auto-flows to a new page at the bottom; "Done" ends the sitting
  early. One **entry** = one sitting = one **stack** of pages on the wall.
- Rendering: layered 2.5D first, behind a `WallRenderer` protocol so a 3D (SceneKit/RealityKit)
  renderer can be added without touching model, sync or editor.
- Uniqueness: each page stores only seeds; shape, wear, stains, tears, creases and fastener
  placement are generated deterministically from them. No rendered images are stored or synced.
- Physical shuffling: pages have a real height order. Pulling a page from mid-stack slides it
  out beneath the pages above, travels around, and drops on top; shadow follows height.
- Text: journal toggle for dual-font (sub font under each word) using native CoreText ruby
  annotations; editor is a plain text view. Synced text is plain English either way.
- Theming: reuses existing font slots and ink color; parchment presets (aged, vellum, linen,
  dark slate) set base color/wear level, seeds vary within a preset.
- Sync: standalone `journal-api` on the Pi (Flask + waitress + SQLite — the pi-infra convention — bearer
  token, Cloudflare tunnel route, in the style of word-api/dexcom-api). Plaintext at rest, HTTPS in transit
  (same model as CarbBook). Isolated from CarbBook.
- Backups: Pi nightly, keep 30 daily + one per month indefinitely; desktop pulls a copy daily
  with the same retention. Live data is never trimmed.
- Desktop ingest: `journal-pull` systemd timer pulls new/changed entries, writes
  `~/knowledge/journal/YYYY-MM-DD-<slug>.md` (domain: personal, tags: [journal]) and runs
  `kb-ingest`. Desktop notes are never deleted by a server tombstone.
- Edit/delete: finished pages stay editable. Deleting an entry writes a tombstone that syncs.

- Word art: every page carries a unique doodle at a seeded random spot, built from the page's words
  with the **legacy mode** of `sbruschke/VectorCompression` (layer-words on, individual vectors only,
  no resultant): each word restarts at the origin, each character adds its fixed 3D vector tip-to-tail,
  the 3D picture is projected with a seeded camera and redrawn as hand-inked quadratic strokes
  (bend, taper, tick arrowheads; early words toward paper edge-ink, later words toward the writing
  ink and denser). Derived from (text, page seed), never stored or synced. Drawn *under* the text at
  low opacity so it may overlap writing (marginalia-style) without hurting legibility; toggle and
  strength in settings. A second toggle (default off) makes the text **wrap around** the doodle's
  frame like an inline image: the frame is the rotated doodle square, which depends on the page seed
  only, so pagination and layout never depend on the typed words. Layout is row-by-row CoreText
  (`CTTypesetter`) filling the free segments on both sides of the frame in reading order. Unmappable characters are skipped; capped at 120 words x 30 characters.

## Components
iOS (`App/Journal/`, `Core/Journal/`):
- `Model` — pure Swift: `Entry` (id, created, title?, wall x/y/rot, deleted), `Page` (id,
  entryId, order, text, appearanceSeed, fastenerSeed), `WallLayout` (snap grid, free vs
  snapped positions both retained), `StackOps` (pull-out / travel / drop paths, z-order).
- `WordArt` — legacy vector table + seeded projection to hand-drawn strokes (pure Swift, same package).
- `Appearance` — seed + preset -> plain numbers and paths (outline, wear, stains, tears,
  creases, fastener kinds/positions). Renderer-independent.
- `Render25D` — implements `WallRenderer`; draws wall, stacks, shadows, animations.
- `Editor` — UITextView on parchment, auto-flow pagination, Done -> zoom-out transition.
- `Sync` — per-record last-write-wins (`updated_at`, `updated_by`), offline queue, pull cursor.
  Single narrow module so E2E encryption could be added later.

Server (`journal-api`, in ~/Projects/pi-infra, Python): tables `entry`, `page` (tombstones via `deleted`),
`POST /sync/push`, `GET /sync/pull?since=`, bearer auth, nightly backup unit.

Desktop: `journal-pull` script + systemd user timer; runs `kb-ingest` per written note.

## Amendments from planning
- Page splits are **content, not layout**: they are fixed when text is written/edited on a device
  and synced as page text. Changing fonts or sizes never re-splits. A page whose text overflows
  on another device/font is drawn shrink-to-fit (down to 70%) and then clipped with a fade;
  no text is ever lost. Editing a page re-flows that page and the ones after it.
- Seeds are 64-bit and travel as decimal strings (JSON/JS numbers lose precision above 2^53).
- Server backups run inside `journal-api` (nightly SQLite online backup, retention 30 daily +
  monthly forever); the desktop downloads `/backup/latest` daily with the same retention.
- Page reorder in v1: drag a page sideways out of the fanned stack to bring it to the front, plus
  menu actions (send to back, up, down) that all play the physical shuffle path.

## Wall interaction
- Pannable/pinchable canvas; stacks at free x/y with slight rotation.
- "Snap to grid": snaps on drop; enabling animates stacks into cells; free positions are
  remembered so disabling restores them.
- Tap stack to fan out; drag a page to reorder (physical path above).
- Long-press stack: add/remove pin, staple, tape (positions from fastenerSeed).

## Testing
- Linux (Docker Swift): Model, StackOps, Appearance determinism (same seed -> same output),
  z-order invariants, shuffle paths, sync merge via shared JSON vectors.
- Server: vitest/node tests against the same vectors; migration + backup/restore check.
- Desktop: ingest script tested against a fixture server response.
- Renderer/editor compile only on macOS CI; not claimed working until CI builds and the user
  confirms on device.

## Out of scope (v1)
Handwriting/OCR, E2E encryption, 3D renderer, multi-user, images in entries.
