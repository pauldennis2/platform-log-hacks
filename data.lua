-- Category virtual signals for the type detector
for _, def in ipairs({
    {name="plh-sig-intermediate", icon="__base__/graphics/icons/iron-plate.png",          order="z-plh-a"},
    {name="plh-sig-logistics",    icon="__base__/graphics/icons/transport-belt.png",       order="z-plh-b"},
    {name="plh-sig-production",   icon="__base__/graphics/icons/assembling-machine-1.png", order="z-plh-c"},
    {name="plh-sig-combat",       icon="__base__/graphics/icons/firearm-magazine.png",     order="z-plh-d"},
    {name="plh-sig-module",       icon="__base__/graphics/icons/speed-module.png",         order="z-plh-e"},
    {name="plh-sig-other",        icon="__base__/graphics/icons/arithmetic-combinator.png",order="z-plh-f"},
}) do
    data:extend({{
        type     = "virtual-signal",
        name     = def.name,
        icon     = def.icon,
        icon_size = 64,
        subgroup = "virtual-signal-special",
        order    = def.order,
    }})
end

-- Strips all visible sprites from a hidden companion constant combinator so it
-- doesn't render on top of the main entity.
local function hide_companion(e)
    local empty = {filename = "__core__/graphics/empty.png", width = 1, height = 1, frame_count = 1}
    e.sprites              = {north = empty, south = empty, east = empty, west = empty}
    e.activity_led_sprites = nil
end

-- Entity tint profiles (applied to layer[1] of each directional sprite)
local PLH_TINT_STANDARD  = {r = 0.9,  g = 0.8,  b = 0.6,  a = 1.0}  -- warm amber, distinct from vanilla blue
local PLH_TINT_GATE      = {r = 0.35, g = 0.35, b = 0.35, a = 1.0}  -- dark grey for gate devices
local PLH_TINT_SPREADER  = {r = 0.55, g = 0.30, b = 0.75, a = 1.0}  -- dark purple for spreader
local PLH_TINT_SILVER    = {r = 0.55, g = 0.70, b = 0.90, a = 1.0}  -- cool blue-grey, distinct from red/orange base

local function apply_tint(entity, tint)
    for _, dir in pairs({"north", "east", "south", "west"}) do
        entity.sprites[dir].layers[1].tint = tint
    end
end

local function apply_tint_all_layers(entity, tint)
    for _, dir in pairs({"north", "east", "south", "west"}) do
        for _, layer in ipairs(entity.sprites[dir].layers) do
            layer.tint = tint
        end
    end
end

-- Type Detector entity (arithmetic combinator base + hidden output)
local detector = util.table.deepcopy(data.raw["arithmetic-combinator"]["arithmetic-combinator"])
detector.name = "plh-type-detector"
detector.minable = {mining_time = 0.1, result = "plh-type-detector"}
detector.icon = "__platform-log-hacks__/graphics/icons/type-reader.png"
detector.icon_size = 64
detector.icon_mipmaps = 0
apply_tint(detector, PLH_TINT_STANDARD)

local detector_out = util.table.deepcopy(data.raw["constant-combinator"]["constant-combinator"])
detector_out.name = "plh-type-detector-output"
detector_out.minable = nil
detector_out.flags = {"not-blueprintable", "not-deconstructable", "not-selectable-in-game"}
detector_out.collision_box = {{-0.1, -0.1}, {0.1, 0.1}}
detector_out.collision_mask = {layers = {}}
detector_out.selection_box = {{0, 0}, {0, 0}}
hide_companion(detector_out)


local console = util.table.deepcopy(data.raw["power-switch"]["power-switch"])
console.name = "plh-platform-pilot"
console.minable = {mining_time = 0.1, result = "plh-platform-pilot"}
-- Zero out the copper wire distance so the entity can't actually switch power networks
console.maximum_wire_distance = 0
console.surface_conditions = { { property = "pressure", min = 0, max = 0 } }

-- Platform Request Driver: reads item signals + source planet, sets hub logistic requests
local prd_entity = util.table.deepcopy(data.raw["constant-combinator"]["constant-combinator"])
prd_entity.name = "plh-platform-request-driver"
prd_entity.minable = {mining_time = 0.1, result = "plh-platform-request-driver"}
prd_entity.icon = "__platform-log-hacks__/graphics/icons/platform-request-driver.png"
prd_entity.icon_size = 64
prd_entity.icon_mipmaps = 0
prd_entity.surface_conditions = { { property = "pressure", min = 0, max = 0 } }
-- Swap sprite filenames to the pre-brightened custom graphic; keep all other metadata from deepcopy
local prd_sprite_path = "__platform-log-hacks__/graphics/entity/platform-request-driver.png"
for _, dir in pairs({"north", "east", "south", "west"}) do
    for _, layer in ipairs(prd_entity.sprites[dir].layers) do
        if layer.filename then layer.filename = prd_sprite_path end
        if layer.hr_version and layer.hr_version.filename then
            layer.hr_version.filename = prd_sprite_path
        end
    end
end


-- Quality Modulator: mode-selectable upstep or remove via custom GUI
local modulator = util.table.deepcopy(data.raw["arithmetic-combinator"]["arithmetic-combinator"])
modulator.name = "plh-quality-modulator"
modulator.minable = {mining_time = 0.1, result = "plh-quality-modulator"}
modulator.icon = "__platform-log-hacks__/graphics/icons/quality-modulator.png"
modulator.icon_size = 64
modulator.icon_mipmaps = 0
apply_tint(modulator, PLH_TINT_STANDARD)

local modulator_out = util.table.deepcopy(data.raw["constant-combinator"]["constant-combinator"])
modulator_out.name = "plh-quality-modulator-output"
modulator_out.minable = nil
modulator_out.flags = {"not-blueprintable", "not-deconstructable", "not-selectable-in-game"}
modulator_out.collision_box = {{-0.1, -0.1}, {0.1, 0.1}}
modulator_out.collision_mask = {layers = {}}
modulator_out.selection_box = {{0, 0}, {0, 0}}
hide_companion(modulator_out)

-- Storage Reader: reads % fullness of directly-wired storage entities
local storage_reader = util.table.deepcopy(data.raw["arithmetic-combinator"]["arithmetic-combinator"])
storage_reader.name = "plh-storage-reader"
storage_reader.minable = {mining_time = 0.1, result = "plh-storage-reader"}
storage_reader.icon = "__platform-log-hacks__/graphics/icons/storage-reader.png"
storage_reader.icon_size = 64
storage_reader.icon_mipmaps = 0
apply_tint(storage_reader, PLH_TINT_STANDARD)

local storage_reader_out = util.table.deepcopy(data.raw["constant-combinator"]["constant-combinator"])
storage_reader_out.name = "plh-storage-reader-output"
storage_reader_out.minable = nil
storage_reader_out.flags = {"not-blueprintable", "not-deconstructable", "not-selectable-in-game"}
storage_reader_out.collision_box = {{-0.1, -0.1}, {0.1, 0.1}}
storage_reader_out.collision_mask = {layers = {}}
storage_reader_out.selection_box = {{0, 0}, {0, 0}}
hide_companion(storage_reader_out)

-- Spoilage Reader: outputs signal-S = % spoiled of the most-spoiled item in directly-wired storage
local PLH_TINT_SPOILAGE = {r = 0.30, g = 0.75, b = 0.35, a = 1.0}  -- organic green
local spoilage_reader = util.table.deepcopy(data.raw["arithmetic-combinator"]["arithmetic-combinator"])
spoilage_reader.name = "plh-spoilage-reader"
spoilage_reader.minable = {mining_time = 0.1, result = "plh-spoilage-reader"}
spoilage_reader.icon = "__base__/graphics/icons/arithmetic-combinator.png"
spoilage_reader.icon_size = 64
spoilage_reader.icon_mipmaps = 4
apply_tint(spoilage_reader, PLH_TINT_SPOILAGE)

local spoilage_reader_out = util.table.deepcopy(data.raw["constant-combinator"]["constant-combinator"])
spoilage_reader_out.name = "plh-spoilage-reader-output"
spoilage_reader_out.minable = nil
spoilage_reader_out.flags = {"not-blueprintable", "not-deconstructable", "not-selectable-in-game"}
spoilage_reader_out.collision_box = {{-0.1, -0.1}, {0.1, 0.1}}
spoilage_reader_out.collision_mask = {layers = {}}
spoilage_reader_out.selection_box = {{0, 0}, {0, 0}}
hide_companion(spoilage_reader_out)

-- Recipe Reader: outputs the building that produces each input item signal
-- (Future: option 1 = output ingredients, option 2 = output what can be made)
local reader = util.table.deepcopy(data.raw["arithmetic-combinator"]["arithmetic-combinator"])
reader.name = "plh-recipe-reader"
reader.minable = {mining_time = 0.1, result = "plh-recipe-reader"}
reader.icon = "__platform-log-hacks__/graphics/icons/recipe-reader.png"
apply_tint(reader, PLH_TINT_STANDARD)
reader.icon_size = 64
reader.icon_mipmaps = 0

local reader_out = util.table.deepcopy(data.raw["constant-combinator"]["constant-combinator"])
reader_out.name = "plh-recipe-reader-output"
reader_out.minable = nil
reader_out.flags = {"not-blueprintable", "not-deconstructable", "not-selectable-in-game"}
reader_out.collision_box = {{-0.1, -0.1}, {0.1, 0.1}}
reader_out.collision_mask = {layers = {}}
reader_out.selection_box = {{0, 0}, {0, 0}}
hide_companion(reader_out)

-- Type Gate: passes only item signals of the selected type category
local type_gate = util.table.deepcopy(data.raw["arithmetic-combinator"]["arithmetic-combinator"])
type_gate.name = "plh-type-gate"
type_gate.minable = {mining_time = 0.1, result = "plh-type-gate"}
type_gate.icon = "__platform-log-hacks__/graphics/icons/type-gate.png"
type_gate.icon_size = 64
type_gate.icon_mipmaps = 0
apply_tint(type_gate, PLH_TINT_GATE)

local type_gate_out = util.table.deepcopy(data.raw["constant-combinator"]["constant-combinator"])
type_gate_out.name = "plh-type-gate-output"
type_gate_out.minable = nil
type_gate_out.flags = {"not-blueprintable", "not-deconstructable", "not-selectable-in-game"}
type_gate_out.collision_box = {{-0.1, -0.1}, {0.1, 0.1}}
type_gate_out.collision_mask = {layers = {}}
type_gate_out.selection_box = {{0, 0}, {0, 0}}
hide_companion(type_gate_out)

-- Subtype Gate: passes only item signals of the selected item subgroup (e.g. belt, ammo, module)
local subtype_gate = util.table.deepcopy(data.raw["arithmetic-combinator"]["arithmetic-combinator"])
subtype_gate.name = "plh-subtype-gate"
subtype_gate.minable = {mining_time = 0.1, result = "plh-subtype-gate"}
subtype_gate.icon = "__platform-log-hacks__/graphics/icons/subtype-gate.png"
subtype_gate.icon_size = 64
subtype_gate.icon_mipmaps = 0
apply_tint(subtype_gate, PLH_TINT_GATE)

local subtype_gate_out = util.table.deepcopy(data.raw["constant-combinator"]["constant-combinator"])
subtype_gate_out.name = "plh-subtype-gate-output"
subtype_gate_out.minable = nil
subtype_gate_out.flags = {"not-blueprintable", "not-deconstructable", "not-selectable-in-game"}
subtype_gate_out.collision_box = {{-0.1, -0.1}, {0.1, 0.1}}
subtype_gate_out.collision_mask = {layers = {}}
subtype_gate_out.selection_box = {{0, 0}, {0, 0}}
hide_companion(subtype_gate_out)

-- Subtype Spreader: outputs all items of the selected subgroup with count 1.
-- Uses a constant combinator directly — no hidden companion needed.
local subtype_spreader = util.table.deepcopy(data.raw["constant-combinator"]["constant-combinator"])
subtype_spreader.name = "plh-subtype-spreader"
subtype_spreader.minable = {mining_time = 0.1, result = "plh-subtype-spreader"}
subtype_spreader.icon = "__platform-log-hacks__/graphics/icons/subtype-spreader.png"
subtype_spreader.icon_size = 64
subtype_spreader.icon_mipmaps = 0
apply_tint(subtype_spreader, PLH_TINT_SPREADER)

data:extend({
    console,
    detector,
    detector_out,
    modulator,
    modulator_out,

    storage_reader,
    storage_reader_out,
    spoilage_reader,
    spoilage_reader_out,
    reader,
    reader_out,
    type_gate,
    type_gate_out,
    subtype_gate,
    subtype_gate_out,
    subtype_spreader,
    prd_entity,
    {
        type = "item",
        name = "plh-type-detector",
        icon = "__platform-log-hacks__/graphics/icons/type-reader.png",
        icon_size = 64,
        subgroup = "circuit-network",
        order = "c[combinators]-z[plh-type-detector]",
        stack_size = 10,
        place_result = "plh-type-detector",
    },
    {
        type = "recipe",
        name = "plh-type-detector",
        ingredients = {{type = "item", name = "arithmetic-combinator", amount = 1}},
        results = {{type = "item", name = "plh-type-detector", amount = 1}},
        enabled = false,
        energy_required = 1,
    },
    {
        type = "item",
        name = "plh-platform-pilot",
        icon = "__platform-log-hacks__/graphics/icons/platform-pilot.png",
        icon_size = 64,
        subgroup = "circuit-network",
        order = "c[combinators]-z[plh-platform-pilot]",
        stack_size = 10,
        place_result = "plh-platform-pilot",
    },
    {
        type = "recipe",
        name = "plh-platform-pilot",
        ingredients = {
            {type = "item", name = "processing-unit",   amount = 20},
            {type = "item", name = "advanced-circuit",  amount = 5},
            {type = "item", name = "steel-plate",       amount = 5},
        },
        results = {{type = "item", name = "plh-platform-pilot", amount = 1}},
        enabled = false,
        energy_required = 10,
    },
    {
        type = "item",
        name = "plh-platform-request-driver",
        icon = "__platform-log-hacks__/graphics/icons/platform-request-driver.png",
        icon_size = 64,
        subgroup = "circuit-network",
        order = "c[combinators]-z[plh-platform-request-driver]",
        stack_size = 10,
        place_result = "plh-platform-request-driver",
    },
    {
        type = "recipe",
        name = "plh-platform-request-driver",
        ingredients = {
            {type = "item", name = "processing-unit",   amount = 10},
            {type = "item", name = "advanced-circuit",  amount = 5},
            {type = "item", name = "steel-plate",       amount = 3},
        },
        results = {{type = "item", name = "plh-platform-request-driver", amount = 1}},
        enabled = false,
        energy_required = 10,
    },
    {
        type = "item",
        name = "plh-quality-modulator",
        icon = "__platform-log-hacks__/graphics/icons/quality-modulator.png",
        icon_size = 64,
        icon_mipmaps = 0,
        icon_mipmaps = 1,
        subgroup = "circuit-network",
        order = "c[combinators]-z[plh-quality-modulator]",
        stack_size = 10,
        place_result = "plh-quality-modulator",
    },
    {
        type = "recipe",
        name = "plh-quality-modulator",
        ingredients = {{type = "item", name = "arithmetic-combinator", amount = 1}},
        results = {{type = "item", name = "plh-quality-modulator", amount = 1}},
        enabled = false,
        energy_required = 1,
    },
    {
        type = "item",
        name = "plh-storage-reader",
        icon = "__platform-log-hacks__/graphics/icons/storage-reader.png",
        icon_size = 64,
        subgroup = "circuit-network",
        order = "c[combinators]-z[plh-storage-reader]",
        stack_size = 10,
        place_result = "plh-storage-reader",
    },
    {
        type = "recipe",
        name = "plh-storage-reader",
        ingredients = {{type = "item", name = "arithmetic-combinator", amount = 1}},
        results = {{type = "item", name = "plh-storage-reader", amount = 1}},
        enabled = false,
        energy_required = 1,
    },
    {
        type = "item",
        name = "plh-spoilage-reader",
        icon = "__base__/graphics/icons/arithmetic-combinator.png",
        icon_size = 64,
        icon_mipmaps = 4,
        subgroup = "circuit-network",
        order = "c[combinators]-z[plh-spoilage-reader]",
        stack_size = 10,
        place_result = "plh-spoilage-reader",
    },
    {
        type = "recipe",
        name = "plh-spoilage-reader",
        ingredients = {{type = "item", name = "arithmetic-combinator", amount = 1}},
        results = {{type = "item", name = "plh-spoilage-reader", amount = 1}},
        enabled = false,
        energy_required = 1,
    },
    {
        type = "item",
        name = "plh-recipe-reader",
        icon = "__platform-log-hacks__/graphics/icons/recipe-reader.png",
        icon_size = 64,
        icon_mipmaps = 0,
        subgroup = "circuit-network",
        order = "c[combinators]-z[plh-recipe-reader]",
        stack_size = 10,
        place_result = "plh-recipe-reader",
    },
    {
        type = "recipe",
        name = "plh-recipe-reader",
        ingredients = {{type = "item", name = "arithmetic-combinator", amount = 1}},
        results = {{type = "item", name = "plh-recipe-reader", amount = 1}},
        enabled = false,
        energy_required = 1,
    },
    {
        type = "item",
        name = "plh-type-gate",
        icon = "__platform-log-hacks__/graphics/icons/type-gate.png",
        icon_size = 64,
        subgroup = "circuit-network",
        order = "c[combinators]-z[plh-type-gate]",
        stack_size = 10,
        place_result = "plh-type-gate",
    },
    {
        type = "recipe",
        name = "plh-type-gate",
        ingredients = {{type = "item", name = "arithmetic-combinator", amount = 1}},
        results = {{type = "item", name = "plh-type-gate", amount = 1}},
        enabled = false,
        energy_required = 1,
    },
    {
        type = "item",
        name = "plh-subtype-spreader",
        icon = "__platform-log-hacks__/graphics/icons/subtype-spreader.png",
        icon_size = 64,
        subgroup = "circuit-network",
        order = "c[combinators]-z[plh-subtype-spreader]",
        stack_size = 10,
        place_result = "plh-subtype-spreader",
    },
    {
        type = "recipe",
        name = "plh-subtype-spreader",
        ingredients = {{type = "item", name = "constant-combinator", amount = 1}},
        results = {{type = "item", name = "plh-subtype-spreader", amount = 1}},
        enabled = false,
        energy_required = 1,
    },
    {
        type = "item",
        name = "plh-subtype-gate",
        icon = "__platform-log-hacks__/graphics/icons/subtype-gate.png",
        icon_size = 64,
        subgroup = "circuit-network",
        order = "c[combinators]-z[plh-subtype-gate]",
        stack_size = 10,
        place_result = "plh-subtype-gate",
    },
    {
        type = "recipe",
        name = "plh-subtype-gate",
        ingredients = {{type = "item", name = "arithmetic-combinator", amount = 1}},
        results = {{type = "item", name = "plh-subtype-gate", amount = 1}},
        enabled = false,
        energy_required = 1,
    },
})

data:extend({{
    type          = "technology",
    name          = "plh-platform-logistics",
    icon          = "__platform-log-hacks__/graphics/icons/platform-pilot.png",
    icon_size     = 64,
    prerequisites = {"space-platform-thruster"},
    unit = {
        count       = 200,
        ingredients = {
            {"automation-science-pack", 1},
            {"logistic-science-pack",   1},
            {"chemical-science-pack",   1},
            {"space-science-pack",      1},
        },
        time = 60,
    },
    effects = {
        {type = "unlock-recipe", recipe = "plh-platform-pilot"},
        {type = "unlock-recipe", recipe = "plh-platform-request-driver"},
    },
}})

data:extend({{
    type          = "technology",
    name          = "plh-speciality-combinators",
    icon          = "__base__/graphics/icons/arithmetic-combinator.png",
    icon_size     = 64,
    prerequisites = {"circuit-network"},
    unit = {
        count       = 100,
        ingredients = {
            {"automation-science-pack", 1},
            {"logistic-science-pack",   1},
            {"chemical-science-pack",   1},
        },
        time = 30,
    },
    effects = {
        {type = "unlock-recipe", recipe = "plh-type-detector"},
        {type = "unlock-recipe", recipe = "plh-quality-modulator"},
        {type = "unlock-recipe", recipe = "plh-storage-reader"},
        {type = "unlock-recipe", recipe = "plh-spoilage-reader"},
        {type = "unlock-recipe", recipe = "plh-recipe-reader"},
        {type = "unlock-recipe", recipe = "plh-type-gate"},
        {type = "unlock-recipe", recipe = "plh-subtype-gate"},
        {type = "unlock-recipe", recipe = "plh-subtype-spreader"},
    },
}})
