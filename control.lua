local DRIVER_NAME = "plh-platform-request-driver"
local SECTION_PREFIX = "plh-driver-"

local function wire_companion(entity, output)
    local src_r = entity.get_wire_connector(defines.wire_connector_id.combinator_output_red,   true)
    local src_g = entity.get_wire_connector(defines.wire_connector_id.combinator_output_green, true)
    local dst_r = output.get_wire_connector(defines.wire_connector_id.circuit_red,   true)
    local dst_g = output.get_wire_connector(defines.wire_connector_id.circuit_green, true)
    src_r.connect_to(dst_r)
    src_g.connect_to(dst_g)
end

local function get_circuit_section(behavior)
    for i = 1, behavior.sections_count do
        local s = behavior.get_section(i)
        if s and s.group == "" then return s end
    end
    return behavior.add_section("")
end

-- ── Type Detector ────────────────────────────────────────────────────────────

local DETECTOR_NAME   = "plh-type-detector"
local DETECTOR_OUTPUT = "plh-type-detector-output"

local CATEGORY_SIGNAL = {
    intermediate = "plh-sig-intermediate",
    logistics    = "plh-sig-logistics",
    production   = "plh-sig-production",
    combat       = "plh-sig-combat",
    module       = "plh-sig-module",
    other        = "plh-sig-other",
}

local function categorize(name)
    local proto = prototypes.item[name]
    if not proto then return "other" end
    local t = proto.type
    local g = proto.group and proto.group.name or ""
    if t == "module"                                 then return "module" end
    if t == "ammo" or t == "gun" or t == "armor"
    or t == "capsule"                                then return "combat" end
    if g == "combat"                                 then return "combat" end
    if g == "intermediate-products"                  then return "intermediate" end
    if g == "logistics"                              then return "logistics" end
    if g == "production"                             then return "production" end
    return "other"
end

local function update_detector(entity)
    local output = storage.detector_outputs[entity.unit_number]
    if not (output and output.valid) then return end

    local signals = entity.get_signals(
        defines.wire_connector_id.combinator_input_red,
        defines.wire_connector_id.combinator_input_green
    )

    local behavior = output.get_or_create_control_behavior()
    local section  = get_circuit_section(behavior)
    section.active  = true
    behavior.enabled = true

    if not signals then section.filters = {} return end

    local totals = {}
    for _, sig in ipairs(signals) do
        if sig.signal.type == nil then
            local cat = categorize(sig.signal.name)
            totals[cat] = (totals[cat] or 0) + sig.count
        end
    end

    local filters = {}
    for cat, count in pairs(totals) do
        filters[#filters + 1] = {
            value = {type = "virtual", name = CATEGORY_SIGNAL[cat]},
            min   = count,
        }
    end
    section.filters = filters
end

local function on_detector_built(event)
    local entity = event.entity or event.created_entity
    if not (entity and entity.valid and entity.name == DETECTOR_NAME) then return end

    local output = entity.surface.create_entity({
        name        = DETECTOR_OUTPUT,
        position    = entity.position,
        force       = entity.force,
        raise_built = false,
    })
    if not output then return end

    wire_companion(entity, output)
    storage.detectors[entity.unit_number]        = entity
    storage.detector_outputs[entity.unit_number] = output
end

local function on_detector_removed(event)
    local entity = event.entity
    if not (entity and entity.name == DETECTOR_NAME) then return end

    local output = storage.detector_outputs[entity.unit_number]
    if output and output.valid then output.destroy() end
    storage.detectors[entity.unit_number]        = nil
    storage.detector_outputs[entity.unit_number] = nil
end

-- ── Quality Up-stepper ───────────────────────────────────────────────────────

local UPSTEPPER_NAME   = "plh-quality-upstepper"
local UPSTEPPER_OUTPUT = "plh-quality-upstepper-output"

local QUALITY_NEXT = {
    normal    = "uncommon",
    uncommon  = "rare",
    rare      = "epic",
    epic      = "legendary",
    legendary = "legendary",
}

local function update_upstepper(entity)
    local output = storage.upstepper_outputs[entity.unit_number]
    if not (output and output.valid) then return end

    local signals = entity.get_signals(
        defines.wire_connector_id.combinator_input_red,
        defines.wire_connector_id.combinator_input_green
    )

    local behavior = output.get_or_create_control_behavior()
    local section  = get_circuit_section(behavior)
    section.active  = true
    behavior.enabled = true

    if not signals then section.filters = {} return end

    local filters = {}
    for _, sig in ipairs(signals) do
        if sig.signal.type == nil then
            local bumped = QUALITY_NEXT[sig.signal.quality or "normal"] or "legendary"
            filters[#filters + 1] = {
                value = {type = "item", name = sig.signal.name, quality = bumped},
                min   = sig.count,
            }
        end
    end
    section.filters = filters
end

local function on_upstepper_built(event)
    local entity = event.entity or event.created_entity
    if not (entity and entity.valid and entity.name == UPSTEPPER_NAME) then return end

    local output = entity.surface.create_entity({
        name        = UPSTEPPER_OUTPUT,
        position    = entity.position,
        force       = entity.force,
        raise_built = false,
    })
    if not output then return end

    wire_companion(entity, output)
    storage.upsteppers[entity.unit_number]        = entity
    storage.upstepper_outputs[entity.unit_number] = output
end

local function on_upstepper_removed(event)
    local entity = event.entity
    if not (entity and entity.name == UPSTEPPER_NAME) then return end

    local output = storage.upstepper_outputs[entity.unit_number]
    if output and output.valid then output.destroy() end
    storage.upsteppers[entity.unit_number]        = nil
    storage.upstepper_outputs[entity.unit_number] = nil
end

-- ── Quality Remover ──────────────────────────────────────────────────────────

local REMOVER_NAME   = "plh-quality-remover"
local REMOVER_OUTPUT = "plh-quality-remover-output"

local function update_remover(entity)
    local output = storage.remover_outputs[entity.unit_number]
    if not (output and output.valid) then return end

    local signals = entity.get_signals(
        defines.wire_connector_id.combinator_input_red,
        defines.wire_connector_id.combinator_input_green
    )

    local behavior = output.get_or_create_control_behavior()
    local section  = get_circuit_section(behavior)
    section.active  = true
    behavior.enabled = true

    if not signals then section.filters = {} return end

    local filters = {}
    for _, sig in ipairs(signals) do
        if sig.signal.type == nil then
            filters[#filters + 1] = {
                value = {type = "item", name = sig.signal.name, quality = "normal"},
                min   = sig.count,
            }
        end
    end
    section.filters = filters
end

local function on_remover_built(event)
    local entity = event.entity or event.created_entity
    if not (entity and entity.valid and entity.name == REMOVER_NAME) then return end

    local output = entity.surface.create_entity({
        name        = REMOVER_OUTPUT,
        position    = entity.position,
        force       = entity.force,
        raise_built = false,
    })
    if not output then return end

    wire_companion(entity, output)
    storage.removers[entity.unit_number]        = entity
    storage.remover_outputs[entity.unit_number] = output
end

local function on_remover_removed(event)
    local entity = event.entity
    if not (entity and entity.name == REMOVER_NAME) then return end

    local output = storage.remover_outputs[entity.unit_number]
    if output and output.valid then output.destroy() end
    storage.removers[entity.unit_number]        = nil
    storage.remover_outputs[entity.unit_number] = nil
end

-- ── Platform Request Driver ──────────────────────────────────────────────────

local function get_or_create_section(lp, unit_number)
    local group = SECTION_PREFIX .. unit_number
    local i = 1
    while true do
        local s = lp.get_section(i)
        if not s then break end
        if s.group == group then return s end
        i = i + 1
    end
    return lp.add_section(group)
end

local function remove_section(lp, unit_number)
    local group = SECTION_PREFIX .. unit_number
    local i = 1
    while true do
        local s = lp.get_section(i)
        if not s then break end
        if s.group == group then
            lp.remove_section(i)
            return
        end
        i = i + 1
    end
end

local function set_platform_interrupt(platform, old_planet, new_planet)
    local schedule = platform.schedule
    if not schedule then return end
    local records = schedule.records

    if old_planet then
        for i = #records, 1, -1 do
            if records[i].interrupt and records[i].station == old_planet then
                table.remove(records, i)
                break
            end
        end
    end

    if new_planet then
        table.insert(records, 1, {
            station         = new_planet,
            temporary       = true,
            wait_conditions = {{type = "time", compare_type = "and", ticks = 3600}},
        })
    end

    platform.schedule = schedule
end

local function update_console(entity)
    local platform = entity.surface.platform
    if not platform then return end
    local hub = platform.hub
    if not (hub and hub.valid) then return end

    local lp = hub.get_logistic_point(defines.logistic_member_index.space_platform_hub_requester)
    if not lp then return end

    local section = get_or_create_section(lp, entity.unit_number)
    if not section then return end

    local signals = entity.get_signals(
        defines.wire_connector_id.circuit_red,
        defines.wire_connector_id.circuit_green
    )

    local function clear()
        section.filters = {}
        local old = storage.plh_active_planet[entity.unit_number]
        if old then
            storage.plh_active_planet[entity.unit_number] = nil
            set_platform_interrupt(platform, old, nil)
        end
    end

    if not signals then clear() return end

    local planet_name = nil
    local new_filters = {}

    for _, sig in pairs(signals) do
        if sig.signal.type == "space-location" then
            if not planet_name then planet_name = sig.signal.name end
        elseif sig.signal.type == nil and sig.count > 0 then
            table.insert(new_filters, sig)
        end
    end

    if not planet_name or not next(new_filters) then clear() return end

    local filters = {}
    for i, sig in ipairs(new_filters) do
        filters[i] = {
            value = {
                type    = "item",
                name    = sig.signal.name,
                quality = sig.signal.quality or "normal",
            },
            min         = sig.count,
            import_from = planet_name,
        }
    end
    section.filters = filters

    local old_planet = storage.plh_active_planet[entity.unit_number]
    if old_planet ~= planet_name then
        storage.plh_active_planet[entity.unit_number] = planet_name
        set_platform_interrupt(platform, old_planet, planet_name)
    end
end

local function on_console_built(event)
    local entity = event.entity or event.created_entity
    if not (entity and entity.valid and entity.name == DRIVER_NAME) then return end

    if not entity.surface.platform then
        local player = event.player_index and game.players[event.player_index]
        if player then
            player.insert({name = DRIVER_NAME, count = 1})
        else
            entity.surface.spill_item_stack(entity.position, {name = DRIVER_NAME, count = 1}, true)
        end
        entity.destroy()
        return
    end

    storage.consoles[entity.unit_number] = entity
end

local function on_console_removed(event)
    local entity = event.entity
    if not (entity and entity.name == DRIVER_NAME) then return end

    local old_planet = storage.plh_active_planet[entity.unit_number]
    storage.plh_active_planet[entity.unit_number] = nil
    storage.consoles[entity.unit_number] = nil

    local platform = entity.surface.platform
    if not platform then return end

    if old_planet then
        set_platform_interrupt(platform, old_planet, nil)
    end

    local hub = platform.hub
    if not (hub and hub.valid) then return end
    local lp = hub.get_logistic_point(defines.logistic_member_index.space_platform_hub_requester)
    if lp then remove_section(lp, entity.unit_number) end
end

-- ── Lifecycle ────────────────────────────────────────────────────────────────

script.on_init(function()
    storage.consoles           = {}
    storage.plh_active_planet  = {}
    storage.upsteppers         = {}
    storage.upstepper_outputs  = {}
    storage.removers           = {}
    storage.remover_outputs    = {}
    storage.detectors          = {}
    storage.detector_outputs   = {}
end)

script.on_configuration_changed(function()
    storage.consoles           = storage.consoles           or {}
    storage.plh_active_planet  = storage.plh_active_planet  or {}
    storage.upsteppers         = storage.upsteppers         or {}
    storage.upstepper_outputs  = storage.upstepper_outputs  or {}
    storage.removers           = storage.removers           or {}
    storage.remover_outputs    = storage.remover_outputs    or {}
    storage.detectors          = storage.detectors          or {}
    storage.detector_outputs   = storage.detector_outputs   or {}
end)

local function on_built(event)
    on_console_built(event)
    on_detector_built(event)
    on_upstepper_built(event)
    on_remover_built(event)
end

local function on_removed(event)
    on_console_removed(event)
    on_detector_removed(event)
    on_upstepper_removed(event)
    on_remover_removed(event)
end

script.on_event(defines.events.on_built_entity,           on_built)
script.on_event(defines.events.on_robot_built_entity,     on_built)
script.on_event(defines.events.on_space_platform_built_entity, on_built)
script.on_event(defines.events.script_raised_built,       on_built)
script.on_event(defines.events.script_raised_revive,      on_built)

script.on_event(defines.events.on_player_mined_entity,    on_removed)
script.on_event(defines.events.on_robot_mined_entity,     on_removed)
script.on_event(defines.events.on_entity_died,            on_removed)
script.on_event(defines.events.script_raised_destroy,     on_removed)

script.on_nth_tick(60, function()
    for id, entity in pairs(storage.consoles) do
        if entity and entity.valid then
            update_console(entity)
        else
            storage.consoles[id] = nil
        end
    end
end)

script.on_nth_tick(2, function()
    for id, entity in pairs(storage.upsteppers) do
        if entity and entity.valid then
            update_upstepper(entity)
        else
            storage.upsteppers[id] = nil
            storage.upstepper_outputs[id] = nil
        end
    end
    for id, entity in pairs(storage.removers) do
        if entity and entity.valid then
            update_remover(entity)
        else
            storage.removers[id] = nil
            storage.remover_outputs[id] = nil
        end
    end
    for id, entity in pairs(storage.detectors) do
        if entity and entity.valid then
            update_detector(entity)
        else
            storage.detectors[id] = nil
            storage.detector_outputs[id] = nil
        end
    end
end)
