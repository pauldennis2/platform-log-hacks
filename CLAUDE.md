# platform-log-hacks — Factorio Space Age Mod

Mod ID: `platform-log-hacks` | Current version: **0.2.0** | Author: erronius

Circuit network combinators that address space platform logistics limitations.

## Architecture: Hidden Companion Pattern

Every entity is an **arithmetic-combinator** (visible) + **hidden constant-combinator** (companion) wired to the output port. Script reads the main entity's input network, writes results to `companion.section.filters`.

Key functions in control.lua:
- `wire_companion(entity, output)` — connects output port to companion
- `init_output(output)` — called ONCE at placement; sets enabled/active
- `get_output_section(output)` — called each tick; returns the writable section
- `rescan_surfaces()` — called in on_configuration_changed; rescues orphaned entities

## Entity List

| Entity | plh- name | What it does |
|---|---|---|
| Quality Up-stepper | quality-upstepper | Bumps items N quality tiers (wraps legendary→normal) |
| Quality Remover | quality-remover | Strips quality → normal |
| Quality Modulator | quality-modulator | GUI: Upstep (Steps 1-4) or Remove |
| Quality Gate | quality-gate | GUI: Allow-only / Allow-all-but / Signal mode |

| Quality Multiplexer | quality-multiplexer | Outputs each item's total at every quality tier |
| Storage Reader | storage-reader | signal-A = % available space in directly-wired storage |
| Recipe Reader | recipe-reader | Outputs producer building for each input item |
| Signal Type Detector | type-detector | Categorises items by group → virtual signals |
| Platform Request Driver | platform-request-driver | Sets hub logistic requests from circuit signals |
| Mini Signal Receiver | mini-signal-receiver | 2×2 AAI receiver (GUI not integrated) |

## Critical Rules

1. **NEVER deepcopy `decider-combinator`** — causes GPU crash / "failed to create texture" in Factorio 2.0. Always use `arithmetic-combinator` as base.
2. **Always use entity name filters** on built/removed events (`PLH_ENTITY_FILTERS` table). Without them, callbacks fire for every entity in the game.
3. **Item signal type is `nil`** (not `"item"`) when returned from `get_signals()` in Factorio 2.0.
4. **Storage reader** only sees entities with a direct wire to its input port — not full network members.
5. **NEVER modify `storage` in `on_load`** — Factorio enforces a CRC check; any storage write crashes with a save/load stability error. Use `on_configuration_changed` or `on_init` instead.
6. **Quality-type signals** require an explicit `quality = "normal"` on the filter value or they silently fail to propagate: `{type="quality", name="legendary", quality="normal"}`.
7. **Stale `entity_keys` cache**: when filter-building logic changes, bump the version in `info.json` so `on_configuration_changed` fires and clears `entity_keys`. Without a version bump, existing entities won't re-run their logic.

## Signal Conventions

- Item quality: `{type=nil, name="iron-plate", quality="rare"}`
- Quality signal: `{type="quality", name="uncommon"}`
- Storage output: `signal-A` = `100 - fullness_pct` (available space, not fullness)

## Planned

- **Quality Setter**: outputs any input item at a fixed quality regardless of input quality

## Reload Requirements — Always flag this after each change

After every code change, tell the user which reload level is needed to test it:

| Changed files | Reload needed |
|---|---|
| `control.lua`, `scripts/*.lua`, `locale/*.cfg` | **Main menu reload** — return to title screen and re-enter the save |
| `data.lua`, `data-updates.lua`, `data-final-fixes.lua`, `info.json` | **Full quit** — exit the game entirely, relaunch, then load the save |

If a single session touches both data-stage and control-stage files, the whole change requires a full quit.

## Session Tips

- Use `/clear` between distinct tasks — memory files + this CLAUDE.md restore context cheaply
- Read files with `offset`/`limit` or `Grep` first rather than loading full files
- changelog.txt and info.json track version; bump both when shipping changes
