local DRIVER_NAME = "plh-platform-request-driver"
local SECTION_PREFIX = "plh-driver-"

-- Finds our managed logistic section on the hub, or creates it.
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

-- Removes our managed section from the hub on entity removal.
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

local function update_console(entity)
    local platform = entity.surface.platform
    if not platform then return end
    local hub = platform.hub
    if not (hub and hub.valid) then return end

    local lp = hub.get_logistic_point(defines.logistic_member_index.space_platform_hub_requester)
    if not lp then return end

    local signals = entity.get_signals(
        defines.wire_connector_id.circuit_red,
        defines.wire_connector_id.circuit_green
    )

    local section = get_or_create_section(lp, entity.unit_number)
    if not section then return end

    if not signals then
        section.filters = {}
        return
    end

    local planet_name = nil
    local new_filters = {}

    for _, sig in pairs(signals) do
        if sig.signal.type == "space-location" then
            -- First planet signal found wins
            if not planet_name then
                planet_name = sig.signal.name
            end
        elseif sig.signal.type == "item" and sig.count > 0 then
            table.insert(new_filters, sig)
        end
    end

    if not planet_name or not next(new_filters) then
        section.filters = {}
        return
    end

    local filters = {}
    for i, sig in ipairs(new_filters) do
        filters[i] = {
            value = {
                type  = "item",
                name  = sig.signal.name,
                quality = sig.signal.quality or "normal",
            },
            min = sig.count,
            import_from = planet_name,
        }
    end
    section.filters = filters
end

-- Placement: reject if not on a space platform.
local function on_console_built(event)
    local entity = event.entity or event.created_entity
    if not (entity and entity.valid and entity.name == DRIVER_NAME) then return end

    if not entity.surface.platform then
        local player = event.player_index and game.players[event.player_index]
        if player then
            player.give_item_stack({name = DRIVER_NAME, count = 1})
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
    storage.consoles[entity.unit_number] = nil

    local platform = entity.surface.platform
    if not platform then return end
    local hub = platform.hub
    if not (hub and hub.valid) then return end
    local lp = hub.get_logistic_point(defines.logistic_member_index.space_platform_hub_requester)
    if lp then remove_section(lp, entity.unit_number) end
end

script.on_init(function()
    storage.consoles = {}
end)

script.on_configuration_changed(function()
    storage.consoles = storage.consoles or {}
end)

script.on_event(defines.events.on_built_entity, on_console_built)
script.on_event(defines.events.on_robot_built_entity, on_console_built)
script.on_event(defines.events.on_space_platform_built_entity, on_console_built)
script.on_event(defines.events.script_raised_built, on_console_built)
script.on_event(defines.events.script_raised_revive, on_console_built)

script.on_event(defines.events.on_player_mined_entity, on_console_removed)
script.on_event(defines.events.on_robot_mined_entity, on_console_removed)
script.on_event(defines.events.on_entity_died, on_console_removed)
script.on_event(defines.events.script_raised_destroy, on_console_removed)

-- Suppress the default roboport GUI until proper AAI channel integration is implemented
script.on_event(defines.events.on_gui_opened, function(event)
    if event.entity and event.entity.valid and event.entity.name == "plh-mini-signal-receiver" then
        game.players[event.player_index].opened = nil
    end
end)

script.on_nth_tick(60, function()
    for id, entity in pairs(storage.consoles) do
        if entity and entity.valid then
            update_console(entity)
        else
            storage.consoles[id] = nil
        end
    end
end)
