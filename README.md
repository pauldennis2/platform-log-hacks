# Platform Logistics Hacks

That name might change. This is a Factorio mod. It's evolved a bit, but essentially aims to make the circuit network more powerful/usable in a wide range of scenarios.

(Had Claude create a quick summary of features. TODO: re-write and improve)

### Features

#### \*\*\*\*\* Platform Request Driver \*\*\*\*\*

This device allows you to drive your spaceship via the circuit network. Place it on a space platform and wire it to your circuit network. Every signal on the network is interpreted as a logistics request to the platform hub — signal name is the item, signal value is the quantity. This lets you build fully automated supply logic without touching the hub UI at all.

#### Quality Modulator

A swiss-army knife for quality manipulation. Open it to select a mode:

- **Upstep (wrap)** — bumps every input item up N quality tiers. Wraps legendary back to normal. Steps adjustable from ±1 to ±4.
- **Upstep (clamp)** — same as above but legendary stays legendary instead of wrapping.
- **Remove** — strips quality from all input signals, outputting everything at normal quality.
- **Multiplex** — outputs each input item's total count once at every quality tier. Useful for feeding a quality-aware requester that needs to see all tiers.
- **Set Quality** — outputs all input signals at a fixed quality tier of your choice, regardless of input quality.
- **Read Quality** — strips item identity entirely and outputs one quality-type signal per tier, summed across all input items. Tells you "how much quality is in this network" without caring what the items are.

#### Quality Gate

Filters signals by quality. Open to select a mode:

- **Allow only** — passes only signals at or above the selected quality tier.
- **Allow all but** — passes everything except the selected quality tier.
- **Signal mode** — uses an incoming virtual signal to set the quality threshold dynamically.

#### Quality Reader

Strips item identity from input signals and outputs one quality-type signal per tier present, with the count summed across all items. If you have 50 rare iron plates and 30 rare copper plates, you get `rare = 80`. (Also available as a mode in the Quality Modulator.)

#### Quality Multiplexer

For each input item signal, outputs that item's total count at every quality tier simultaneously. Useful when downstream logic needs to see all quality tiers of an item at once rather than the specific quality coming in.

#### Quality Up-stepper / Quality Remover

Single-purpose fixed versions of the Modulator's upstep and remove modes. Useful when you want a dedicated device wired into a specific spot without a GUI to accidentally reconfigure.

#### Recipe Reader

A multimodal device. For each input item signal it reads your available recipes and outputs something useful:

- **Producer** — outputs the building that produces each input item (e.g. iron plate → stone furnace).
- **All Producers** — outputs every building that can produce each item.
- **Best Producer** — outputs the fastest available machine for each item based on crafting speed.
- **Ingredients** — outputs the crafting ingredients needed to produce each input item.

#### Storage Reader

Wire a chest or tank directly to this device's input side and it outputs `signal-A` = percentage of available space remaining (0 = full, 100 = empty). Useful for triggering logistics requests or halting production when storage is nearly full. Can also read available space on platform.

**Notes**
1. Only sees entities with a direct wire to its input port, not other members of the same circuit network.
2. For containers the availability calculation is purely slot based - a slot with 1 iron bar is considered "full". 

#### Signal Type Detector

Categorises all input item signals by their item group and outputs one virtual signal per category with the total item count. Categories: Intermediate Products, Logistics, Production, Combat, Modules, Other. Useful for building dashboards or routing logic that needs to distinguish between item classes.

---

### Known Issues

1. Output is not displayed on the specialized circuits, but it is there. Attach their "out" side to a pole if you need.
2. Quality Reader (and the Quality Modulator's "Read Quality" mode) only reliably reads item signals. Other signal types (fluids, space-locations, asteroid chunks) may not be counted even if they carry a quality tier.

---

### Mod Integrations

**Compakt Circuits** — All PLH devices can be packed into Compakt Circuits processor blocks. State (mode, steps, quality selection, etc.) is preserved through pack/unpack and blueprints. Additionally, Compakt Circuits' iconnector entity supports named cross-surface channels — place one iconnector on Nauvis and another on your space platform with the same channel name, wire each to your local circuit network, and signals flow freely between surfaces. This is the recommended approach for platform-to-ground circuit communication.
