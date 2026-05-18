# Shield Generators — Visibility & Connectivity Options

(By Claude)

Evaluation of three approaches to expose shield HP data from the `shield-generators_0.6.0` mod.

## Mod Background

- Entities are `electric-energy-interface` type (not turrets, not combinators)
- Shield HP is tracked in `storage.shield_generators[unit_number]` (provider shields) and `storage.shields[unit_number]` (turret self-shields)
- No circuit network integration exists today
- Uses the `migratus-orchestrus` migration system for storage upgrades

---

## Feature 1: Shield HP on Entity Tooltip

**How:** Factorio 2.0 exposes `entity.custom_description` — a runtime-settable string shown in the entity tooltip. Update it whenever shield HP changes (tie into existing dirty-tracking).

**Example output:** `Shield: 847 / 1000 HP (84.7%)`

| | |
|---|---|
| Complexity | Low |
| Prototype changes | None |
| Reload required | Main menu reload (control.lua only) |
| Patching foreign mod | Yes — edit shields_provider.lua and shields_self.lua |

**Verdict:** Highest visible payoff for least work. Best starting point.

---

## Feature 2: Circuit Network Output (Companion Combinator)

**How:** `electric-energy-interface` cannot connect to circuit networks. Add a hidden `constant-combinator` companion per generator (same pattern as platform-log-hacks), wire it on placement, and write shield HP as signals each tick.

Signals to expose: current HP, max HP, optionally energy buffer %.

| | |
|---|---|
| Complexity | Moderate–High |
| Prototype changes | Yes — new hidden combinator in data.lua |
| Reload required | Full quit (data-stage change) |
| Patching foreign mod | Yes — data.lua + shields_provider.lua + migration entry |
| New storage keys | Yes — companion unit numbers per generator |

**Verdict:** Most useful for in-game automation, but requires forking and maintaining shield-generators. Prefer Feature 3 + a wrapper in platform-log-hacks instead.

---

## Feature 3: Remote API

**How:** `remote.add_interface("shield-generators", {...})` exposes Lua functions other mods can call. Read-only, no new entities.

Suggested interface:
```lua
remote.call("shield-generators", "get_shield_hp", unit_number)
remote.call("shield-generators", "get_provider_data", unit_number)
remote.call("shield-generators", "list_generators", surface)
```

| | |
|---|---|
| Complexity | Very Low |
| Prototype changes | None |
| Reload required | Main menu reload (control.lua only) |
| Patching foreign mod | Yes — add api.lua, register in control.lua |

**Verdict:** Minimal risk. Useful as the data seam if platform-log-hacks reads shield state and exposes it to the circuit network through its own combinator.

---

## Recommended Approach

1. **Feature 1** — tooltip display, low effort, immediate player value
2. **Feature 3** — remote API, enables platform-log-hacks integration without deeply patching shield-generators
3. **Avoid Feature 2 directly** — achieves the same circuit network result via the Feature 3 API + a platform-log-hacks wrapper entity, without owning a fork of shield-generators
