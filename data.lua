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

-- Type Detector entity (arithmetic combinator base + hidden output)
local detector = util.table.deepcopy(data.raw["arithmetic-combinator"]["arithmetic-combinator"])
detector.name = "plh-type-detector"
detector.minable = {mining_time = 0.1, result = "plh-type-detector"}

local detector_out = util.table.deepcopy(data.raw["constant-combinator"]["constant-combinator"])
detector_out.name = "plh-type-detector-output"
detector_out.minable = nil
detector_out.flags = {"not-blueprintable", "not-deconstructable", "not-selectable-in-game"}
detector_out.collision_box = {{-0.1, -0.1}, {0.1, 0.1}}
detector_out.collision_mask = {layers = {}}
detector_out.selection_box = {{0, 0}, {0, 0}}

local receiver = util.table.deepcopy(data.raw["roboport"]["aai-signal-receiver"])

receiver.name = "plh-mini-signal-receiver"
receiver.minable = {mining_time = 0.2, result = "plh-mini-signal-receiver"}
receiver.max_health = 200
receiver.collision_box = {{-0.9, -0.9}, {0.9, 0.9}}
receiver.selection_box = {{-1.0, -1.0}, {1.0, 1.0}}

-- Single still frame extracted from the AAI sprite sheet — no animation, minimal memory
local sprite_scale = 0.5 * (2 / 9)
receiver.base_animation = {
    layers = {
        {
            filename = "__platform-log-hacks__/graphics/entity/mini-signal-receiver.png",
            priority = "high",
            width = 586,
            height = 680,
            frame_count = 1,
            shift = util.by_pixel(0, -6),
            scale = sprite_scale,
        },
        {
            draw_as_shadow = true,
            filename = "__platform-log-hacks__/graphics/entity/mini-signal-receiver-shadow.png",
            priority = "high",
            width = 680,
            height = 600,
            frame_count = 1,
            shift = util.by_pixel(6, 4),
            scale = sprite_scale,
        },
    },
}

-- Wire connection points scaled proportionally from 9x9 to 2x2
receiver.circuit_connector = {
    points = {
        shadow = {
            green = {-0.56, 0.93},
            red =   {-0.60, 0.89},
        },
        wire = {
            green = {-0.78, 0.71},
            red =   {-0.82, 0.67},
        }
    }
}
receiver.circuit_wire_max_distance = 9

local console = util.table.deepcopy(data.raw["power-switch"]["power-switch"])
console.name = "plh-platform-request-driver"
console.minable = {mining_time = 0.1, result = "plh-platform-request-driver"}
-- Zero out the copper wire distance so the entity can't actually switch power networks
console.maximum_wire_distance = 0
console.surface_conditions = { { property = "pressure", min = 0, max = 0 } }

-- Quality Upstepper: arithmetic combinator shell with separate input/output ports
local upstepper = util.table.deepcopy(data.raw["arithmetic-combinator"]["arithmetic-combinator"])
upstepper.name = "plh-quality-upstepper"
upstepper.minable = {mining_time = 0.1, result = "plh-quality-upstepper"}

-- Hidden constant combinator wired to the output port by script — provides the actual output signals
local upstepper_out = util.table.deepcopy(data.raw["constant-combinator"]["constant-combinator"])
upstepper_out.name = "plh-quality-upstepper-output"
upstepper_out.minable = nil
upstepper_out.flags = {"not-blueprintable", "not-deconstructable", "not-selectable-in-game"}
upstepper_out.collision_box = {{-0.1, -0.1}, {0.1, 0.1}}
upstepper_out.collision_mask = {layers = {}}
upstepper_out.selection_box = {{0, 0}, {0, 0}}

-- Quality Remover: strips quality from all item signals
local remover = util.table.deepcopy(data.raw["arithmetic-combinator"]["arithmetic-combinator"])
remover.name = "plh-quality-remover"
remover.minable = {mining_time = 0.1, result = "plh-quality-remover"}

local remover_out = util.table.deepcopy(data.raw["constant-combinator"]["constant-combinator"])
remover_out.name = "plh-quality-remover-output"
remover_out.minable = nil
remover_out.flags = {"not-blueprintable", "not-deconstructable", "not-selectable-in-game"}
remover_out.collision_box = {{-0.1, -0.1}, {0.1, 0.1}}
remover_out.collision_mask = {layers = {}}
remover_out.selection_box = {{0, 0}, {0, 0}}

-- Quality Modulator: mode-selectable upstep or remove via custom GUI
local modulator = util.table.deepcopy(data.raw["arithmetic-combinator"]["arithmetic-combinator"])
modulator.name = "plh-quality-modulator"
modulator.minable = {mining_time = 0.1, result = "plh-quality-modulator"}

local modulator_out = util.table.deepcopy(data.raw["constant-combinator"]["constant-combinator"])
modulator_out.name = "plh-quality-modulator-output"
modulator_out.minable = nil
modulator_out.flags = {"not-blueprintable", "not-deconstructable", "not-selectable-in-game"}
modulator_out.collision_box = {{-0.1, -0.1}, {0.1, 0.1}}
modulator_out.collision_mask = {layers = {}}
modulator_out.selection_box = {{0, 0}, {0, 0}}

data:extend({
    receiver,
    console,
    detector,
    detector_out,
    upstepper,
    upstepper_out,
    remover,
    remover_out,
    modulator,
    modulator_out,
    {
        type = "item",
        name = "plh-type-detector",
        icon = "__base__/graphics/icons/arithmetic-combinator.png",
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
        name = "plh-quality-upstepper",
        icon = "__base__/graphics/icons/arithmetic-combinator.png",
        icon_size = 64,
        subgroup = "circuit-network",
        order = "c[combinators]-z[plh-quality-upstepper]",
        stack_size = 10,
        place_result = "plh-quality-upstepper",
    },
    {
        type = "recipe",
        name = "plh-quality-upstepper",
        ingredients = {{type = "item", name = "arithmetic-combinator", amount = 1}},
        results = {{type = "item", name = "plh-quality-upstepper", amount = 1}},
        enabled = false,
        energy_required = 1,
    },
    {
        type = "item",
        name = "plh-platform-request-driver",
        icon = "__base__/graphics/icons/power-switch.png",
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
            {type = "item", name = "electronic-circuit", amount = 1},
        },
        results = {{type = "item", name = "plh-platform-request-driver", amount = 1}},
        enabled = false,
        energy_required = 1,
    },
    {
        type = "item",
        name = "plh-quality-remover",
        icon = "__base__/graphics/icons/arithmetic-combinator.png",
        icon_size = 64,
        subgroup = "circuit-network",
        order = "c[combinators]-z[plh-quality-remover]",
        stack_size = 10,
        place_result = "plh-quality-remover",
    },
    {
        type = "recipe",
        name = "plh-quality-remover",
        ingredients = {{type = "item", name = "arithmetic-combinator", amount = 1}},
        results = {{type = "item", name = "plh-quality-remover", amount = 1}},
        enabled = false,
        energy_required = 1,
    },
    {
        type = "item",
        name = "plh-quality-modulator",
        icon = "__base__/graphics/icons/arithmetic-combinator.png",
        icon_size = 64,
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
        name = "plh-mini-signal-receiver",
        icon = "__aai-signal-transmission__/graphics/icons/signal-receiver.png",
        icon_size = 64,
        icon_mipmaps = 1,
        flags = {},
        subgroup = "circuit-network",
        order = "z-z-c",
        stack_size = 10,
        place_result = "plh-mini-signal-receiver",
        pick_sound = "__base__/sound/item/combinator-inventory-pickup.ogg",
        drop_sound = "__base__/sound/item/combinator-inventory-move.ogg",
        inventory_move_sound = "__base__/sound/item/combinator-inventory-move.ogg",
        weight = 1000000/10,
    },
    {
        type = "recipe",
        name = "plh-mini-signal-receiver",
        ingredients = {
            {type = "item", name = "steel-plate", amount = 10},
        },
        results = {
            {type = "item", name = "plh-mini-signal-receiver", amount = 1},
        },
        enabled = false,
        energy_required = 5,
    },
})
