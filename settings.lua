data:extend({
    {
        type                = "int-setting",
        name                = "plh-prd-wait-time",
        setting_type        = "runtime-global",
        default_value       = 30,
        minimum_value       = 5,
        maximum_value       = 600,
        order               = "a",
    },
    {
        type                = "int-setting",
        name                = "plh-circuit-interval",
        setting_type        = "runtime-global",
        default_value       = 6,
        minimum_value       = 1,
        maximum_value       = 60,
        order               = "b",
    },
    {
        type                = "int-setting",
        name                = "plh-spoilage-interval",
        setting_type        = "runtime-global",
        default_value       = 60,
        minimum_value       = 30,
        maximum_value       = 600,
        order               = "c",
    },
})
