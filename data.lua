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

data:extend({
    receiver,
    console,
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
