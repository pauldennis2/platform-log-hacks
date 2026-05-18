-- GUI management for Quality Modulator and Quality Gate.
-- Required by control.lua; returns {close_modulator, close_gate} for use in
-- on_modulator_removed / on_gate_removed.

local READER_NAME          = "plh-recipe-reader"
local READER_FRAME         = "plh-reader-frame"
local READER_CLOSE_BTN     = "plh-reader-close"
local READER_MODE_DROPDOWN = "plh-reader-mode-dropdown"

local MODULATOR_NAME             = "plh-quality-modulator"
local MODULATOR_FRAME            = "plh-modulator-frame"
local MODULATOR_CLOSE_BTN        = "plh-modulator-close"
local MODULATOR_DROPDOWN         = "plh-modulator-mode-dropdown"
local MODULATOR_STEPS_DROPDOWN   = "plh-modulator-steps-dropdown"
local MODULATOR_STEPS_ROW        = "plh-modulator-steps-row"
local MODULATOR_QUALITY_DROPDOWN = "plh-modulator-quality-dropdown"
local MODULATOR_QUALITY_ROW      = "plh-modulator-quality-row"

local QUALITY_NAMES = {"normal", "uncommon", "rare", "epic", "legendary"}

local TYPE_GATE_NAME          = "plh-type-gate"
local TYPE_GATE_FRAME         = "plh-type-gate-frame"
local TYPE_GATE_CLOSE_BTN     = "plh-type-gate-close"
local TYPE_GATE_MODE_DROPDOWN = "plh-type-gate-mode-dropdown"
local TYPE_GATE_MODE_ROW      = "plh-type-gate-mode-row"
local TYPE_GATE_DROPDOWN      = "plh-type-gate-type-dropdown"
local TYPE_GATE_TYPE_ROW      = "plh-type-gate-type-row"

local SUBTYPE_SPREADER_NAME         = "plh-subtype-spreader"
local SUBTYPE_SPREADER_FRAME        = "plh-subtype-spreader-frame"
local SUBTYPE_SPREADER_CLOSE_BTN    = "plh-subtype-spreader-close"
local SPREADER_SEL_ROW              = "plh-subtype-spreader-sel-row"
local SPREADER_SELECTED_LABEL       = "plh-subtype-spreader-selected"
local SPREADER_SEARCH_ROW           = "plh-subtype-spreader-search-row"
local SPREADER_SEARCH_FIELD         = "plh-subtype-spreader-search"
local SPREADER_LIST                 = "plh-subtype-spreader-list"

local PRD_NAME      = "plh-platform-request-driver"
local PRD_FRAME     = "plh-prd-frame"
local PRD_CLOSE     = "plh-prd-close"
local PRD_TOGGLE    = "plh-prd-toggle"

local SUBTYPE_GATE_NAME           = "plh-subtype-gate"
local SUBTYPE_GATE_FRAME          = "plh-subtype-gate-frame"
local SUBTYPE_GATE_CLOSE_BTN      = "plh-subtype-gate-close"
local SUBTYPE_GATE_MODE_DROPDOWN  = "plh-subtype-gate-mode-dropdown"
local SUBTYPE_GATE_MODE_ROW       = "plh-subtype-gate-mode-row"
local SUBTYPE_SEL_ROW             = "plh-subtype-gate-sel-row"
local SUBTYPE_SELECTED_LABEL      = "plh-subtype-gate-selected"
local SUBTYPE_SEARCH_ROW          = "plh-subtype-gate-search-row"
local SUBTYPE_SEARCH_FIELD        = "plh-subtype-gate-search"
local SUBTYPE_LIST                = "plh-subtype-gate-list"

local GATE_MODES = {"allow", "exclude", "signal"}
local TYPE_NAMES = {"intermediate", "logistics", "production", "combat", "module", "other"}

local populated_subgroups = nil

local function compute_populated_subgroups()
    local seen = {}
    for _, proto in pairs(prototypes.item) do
        if proto.subgroup then seen[proto.subgroup.name] = true end
    end
    local ok, ac_protos = pcall(function() return prototypes["asteroid-chunk"] end)
    if ok and ac_protos then
        for _, proto in pairs(ac_protos) do
            if proto.subgroup then seen[proto.subgroup.name] = true end
        end
    end
    for _, proto in pairs(prototypes.virtual_signal) do
        if proto.subgroup then seen[proto.subgroup.name] = true end
    end
    for _, proto in pairs(prototypes.fluid) do
        if proto.subgroup then seen[proto.subgroup.name] = true end
    end
    local result = {}
    for name in pairs(seen) do result[#result + 1] = name end
    table.sort(result)
    populated_subgroups = result
end

local function filter_subgroups(query)
    if not populated_subgroups then compute_populated_subgroups() end
    if query == "" then return populated_subgroups end
    local q = query:lower()
    local result = {}
    for _, name in ipairs(populated_subgroups) do
        if name:lower():find(q, 1, true) then
            result[#result + 1] = name
        end
    end
    return result
end
local STEPS_VALUES = {-4, -3, -2, -1, 1, 2, 3, 4}

local function make_titlebar(frame, caption, close_btn_name)
    local titlebar = frame.add{type = "flow", direction = "horizontal"}
    titlebar.drag_target = frame
    local lbl = titlebar.add{type = "label", style = "frame_title", caption = caption}
    lbl.ignored_by_interaction = true
    local filler = titlebar.add{type = "empty-widget"}
    filler.style.horizontally_stretchable = true
    filler.ignored_by_interaction = true
    titlebar.add{
        type    = "sprite-button",
        name    = close_btn_name,
        style   = "frame_action_button",
        sprite  = "utility/close",
        tooltip = {"gui.close"},
    }
end

local Gui = {}

function Gui.close_reader(player)
    local frame = player.gui.screen[READER_FRAME]
    if frame and frame.valid then frame.destroy() end
    player.opened = nil
    storage.reader_player_entity[player.index] = nil
end

function Gui.create_reader(player, entity)
    local existing = player.gui.screen[READER_FRAME]
    if existing then existing.destroy() end

    local frame = player.gui.screen.add{type = "frame", name = READER_FRAME, direction = "vertical"}
    frame.auto_center = true
    make_titlebar(frame, {"entity-name.plh-recipe-reader"}, READER_CLOSE_BTN)

    local mode = storage.reader_mode[entity.unit_number] or "producer"
    local mode_index = mode == "all-producers" and 2 or mode == "best-producer" and 3
                    or mode == "ingredients" and 4 or 1
    local row = frame.add{type = "flow", direction = "horizontal"}
    row.style.vertical_align = "center"
    row.add{type = "label", caption = {"plh-gui.mode"}}
    row.add{
        type           = "drop-down",
        name           = READER_MODE_DROPDOWN,
        items          = {
            {"plh-gui.reader-producer"},
            {"plh-gui.reader-all-producers"},
            {"plh-gui.reader-best-producer"},
            {"plh-gui.reader-ingredients"},
        },
        selected_index = mode_index,
    }

    player.opened = frame
    storage.reader_player_entity[player.index] = entity.unit_number
end

function Gui.close_modulator(player)
    local frame = player.gui.screen[MODULATOR_FRAME]
    if frame and frame.valid then frame.destroy() end
    player.opened = nil
    storage.modulator_player_entity[player.index] = nil
end

function Gui.create_modulator(player, entity)
    local existing = player.gui.screen[MODULATOR_FRAME]
    if existing then existing.destroy() end

    local frame = player.gui.screen.add{type = "frame", name = MODULATOR_FRAME, direction = "vertical"}
    frame.auto_center = true
    make_titlebar(frame, {"entity-name.plh-quality-modulator"}, MODULATOR_CLOSE_BTN)

    local mode    = storage.modulator_mode[entity.unit_number]    or "upstep"
    local steps   = storage.modulator_steps[entity.unit_number]   or 1
    local quality = storage.modulator_quality[entity.unit_number] or "normal"
    local mode_index = mode == "upstep-clamp" and 2 or mode == "remove" and 3
                    or mode == "multiplex" and 4 or mode == "set" and 5
                    or mode == "read-quality" and 6 or 1
    local steps_idx = 5  -- default: steps=1 is at index 5
    for i, v in ipairs(STEPS_VALUES) do if v == steps then steps_idx = i break end end
    local quality_idx = 1
    for i, q in ipairs(QUALITY_NAMES) do if q == quality then quality_idx = i break end end

    local row = frame.add{type = "flow", direction = "horizontal"}
    row.style.vertical_align = "center"
    row.add{type = "label", caption = {"plh-gui.mode"}}
    row.add{
        type           = "drop-down",
        name           = MODULATOR_DROPDOWN,
        items          = {{"plh-gui.upstep"}, {"plh-gui.upstep-clamp"}, {"plh-gui.remove"}, {"plh-gui.multiplex"}, {"plh-gui.set-quality"}, {"plh-gui.read-quality"}},
        selected_index = mode_index,
    }

    local steps_row = frame.add{type = "flow", name = MODULATOR_STEPS_ROW, direction = "horizontal"}
    steps_row.style.vertical_align = "center"
    steps_row.add{type = "label", caption = {"plh-gui.steps"}}
    steps_row.add{
        type           = "drop-down",
        name           = MODULATOR_STEPS_DROPDOWN,
        items          = {"-4", "-3", "-2", "-1", "1", "2", "3", "4"},
        selected_index = steps_idx,
        enabled        = mode == "upstep" or mode == "upstep-clamp",
    }

    local quality_row = frame.add{type = "flow", name = MODULATOR_QUALITY_ROW, direction = "horizontal"}
    quality_row.style.vertical_align = "center"
    quality_row.add{type = "label", caption = {"plh-gui.quality"}}
    quality_row.add{
        type           = "drop-down",
        name           = MODULATOR_QUALITY_DROPDOWN,
        items          = {
            {"quality-name.normal"},
            {"quality-name.uncommon"},
            {"quality-name.rare"},
            {"quality-name.epic"},
            {"quality-name.legendary"},
        },
        selected_index = quality_idx,
        enabled        = mode == "set",
    }

    player.opened = frame
    storage.modulator_player_entity[player.index] = entity.unit_number
end

function Gui.close_type_gate(player)
    local frame = player.gui.screen[TYPE_GATE_FRAME]
    if frame and frame.valid then frame.destroy() end
    player.opened = nil
    storage.type_gate_player_entity[player.index] = nil
end

function Gui.create_type_gate(player, entity)
    local existing = player.gui.screen[TYPE_GATE_FRAME]
    if existing then existing.destroy() end

    local frame = player.gui.screen.add{type = "frame", name = TYPE_GATE_FRAME, direction = "vertical"}
    frame.auto_center = true
    make_titlebar(frame, {"entity-name.plh-type-gate"}, TYPE_GATE_CLOSE_BTN)

    local mode = storage.type_gate_mode[entity.unit_number] or "allow"
    local mode_index = 1
    for i, m in ipairs(GATE_MODES) do if m == mode then mode_index = i break end end
    local mode_row = frame.add{type = "flow", name = TYPE_GATE_MODE_ROW, direction = "horizontal"}
    mode_row.style.vertical_align = "center"
    mode_row.add{type = "label", caption = {"plh-gui.gate-mode"}}
    mode_row.add{
        type           = "drop-down",
        name           = TYPE_GATE_MODE_DROPDOWN,
        items          = {{"plh-gui.gate-allow"}, {"plh-gui.gate-exclude"}, {"plh-gui.gate-signal"}},
        selected_index = mode_index,
    }

    local type_row = frame.add{type = "flow", name = TYPE_GATE_TYPE_ROW, direction = "horizontal"}
    type_row.style.vertical_align = "center"
    type_row.add{type = "label", caption = {"plh-gui.type"}}

    local type_sel = storage.type_gate_type[entity.unit_number] or "intermediate"
    local selected = 1
    for i, t in ipairs(TYPE_NAMES) do if t == type_sel then selected = i break end end
    type_row.add{
        type           = "drop-down",
        name           = TYPE_GATE_DROPDOWN,
        items          = {
            {"plh-gui.type-gate-intermediate"},
            {"plh-gui.type-gate-logistics"},
            {"plh-gui.type-gate-production"},
            {"plh-gui.type-gate-combat"},
            {"plh-gui.type-gate-module"},
            {"plh-gui.type-gate-other"},
        },
        selected_index = selected,
        enabled        = mode ~= "signal",
    }

    player.opened = frame
    storage.type_gate_player_entity[player.index] = entity.unit_number
end

function Gui.close_subtype_spreader(player)
    local frame = player.gui.screen[SUBTYPE_SPREADER_FRAME]
    if frame and frame.valid then frame.destroy() end
    player.opened = nil
    storage.subtype_spreader_player_entity[player.index] = nil
end

function Gui.create_subtype_spreader(player, entity)
    local existing = player.gui.screen[SUBTYPE_SPREADER_FRAME]
    if existing then existing.destroy() end

    local frame = player.gui.screen.add{type = "frame", name = SUBTYPE_SPREADER_FRAME, direction = "vertical"}
    frame.auto_center = true
    make_titlebar(frame, {"entity-name.plh-subtype-spreader"}, SUBTYPE_SPREADER_CLOSE_BTN)

    local subgroup = storage.subtype_spreader_subgroup[entity.unit_number] or ""
    local sel_row = frame.add{type = "flow", name = SPREADER_SEL_ROW, direction = "horizontal"}
    sel_row.style.vertical_align = "center"
    sel_row.add{type = "label", caption = {"plh-gui.subtype-selected"}}
    local sel_lbl = sel_row.add{type = "label", name = SPREADER_SELECTED_LABEL, caption = subgroup}
    sel_lbl.style.font = "default-bold"

    local search_row = frame.add{type = "flow", name = SPREADER_SEARCH_ROW, direction = "horizontal"}
    search_row.style.vertical_align = "center"
    search_row.add{type = "label", caption = {"plh-gui.subtype-search"}}
    local tf = search_row.add{type = "textfield", name = SPREADER_SEARCH_FIELD, text = ""}
    tf.style.width = 180

    local list = frame.add{type = "list-box", name = SPREADER_LIST, items = filter_subgroups("")}
    list.style.height = 200
    list.style.width  = 260

    player.opened = frame
    storage.subtype_spreader_player_entity[player.index] = entity.unit_number
end

function Gui.close_subtype_gate(player)
    local frame = player.gui.screen[SUBTYPE_GATE_FRAME]
    if frame and frame.valid then frame.destroy() end
    player.opened = nil
    storage.subtype_gate_player_entity[player.index] = nil
end

function Gui.create_subtype_gate(player, entity)
    local existing = player.gui.screen[SUBTYPE_GATE_FRAME]
    if existing then existing.destroy() end

    local frame = player.gui.screen.add{type = "frame", name = SUBTYPE_GATE_FRAME, direction = "vertical"}
    frame.auto_center = true
    make_titlebar(frame, {"entity-name.plh-subtype-gate"}, SUBTYPE_GATE_CLOSE_BTN)

    local mode = storage.subtype_gate_mode[entity.unit_number] or "allow"
    local mode_index = mode == "exclude" and 2 or 1
    local mode_row = frame.add{type = "flow", name = SUBTYPE_GATE_MODE_ROW, direction = "horizontal"}
    mode_row.style.vertical_align = "center"
    mode_row.add{type = "label", caption = {"plh-gui.gate-mode"}}
    mode_row.add{
        type           = "drop-down",
        name           = SUBTYPE_GATE_MODE_DROPDOWN,
        items          = {{"plh-gui.gate-allow"}, {"plh-gui.gate-exclude"}},
        selected_index = mode_index,
    }

    local subgroup = storage.subtype_gate_subgroup[entity.unit_number] or ""
    local sel_row = frame.add{type = "flow", name = SUBTYPE_SEL_ROW, direction = "horizontal"}
    sel_row.style.vertical_align = "center"
    sel_row.add{type = "label", caption = {"plh-gui.subtype-selected"}}
    local sel_lbl = sel_row.add{type = "label", name = SUBTYPE_SELECTED_LABEL, caption = subgroup}
    sel_lbl.style.font = "default-bold"

    local search_row = frame.add{type = "flow", name = SUBTYPE_SEARCH_ROW, direction = "horizontal"}
    search_row.style.vertical_align = "center"
    search_row.add{type = "label", caption = {"plh-gui.subtype-search"}}
    local tf = search_row.add{type = "textfield", name = SUBTYPE_SEARCH_FIELD, text = ""}
    tf.style.width = 180

    local list = frame.add{type = "list-box", name = SUBTYPE_LIST, items = filter_subgroups("")}
    list.style.height = 200
    list.style.width  = 260

    player.opened = frame
    storage.subtype_gate_player_entity[player.index] = entity.unit_number
end

function Gui.close_prd(player)
    local frame = player.gui.screen[PRD_FRAME]
    if frame and frame.valid then frame.destroy() end
    player.opened = nil
    storage.prd_player_entity[player.index] = nil
end

function Gui.create_prd(player, entity)
    local existing = player.gui.screen[PRD_FRAME]
    if existing then existing.destroy() end

    local frame = player.gui.screen.add{type = "frame", name = PRD_FRAME, direction = "vertical"}
    frame.auto_center = true
    make_titlebar(frame, {"entity-name.plh-platform-request-driver"}, PRD_CLOSE)

    -- On/off toggle
    local toggle_row = frame.add{type = "flow", direction = "horizontal"}
    toggle_row.style.vertical_align = "center"
    toggle_row.add{type = "label", caption = {"plh-gui.prd-enabled"}}
    local enabled = storage.prd_enabled[entity.unit_number]
    if enabled == nil then enabled = true end
    toggle_row.add{type = "checkbox", name = PRD_TOGGLE, state = enabled}

    frame.add{type = "line", direction = "horizontal"}

    -- Read red-wire signals (same logic as update_prd)
    local source_planet = nil
    local item_signals  = {}
    local red_net = entity.get_circuit_network(defines.wire_connector_id.circuit_red)
    if red_net then
        for _, sig in pairs(red_net.signals or {}) do
            if sig.signal.type == "space-location" and not source_planet then
                source_planet = sig.signal.name
            elseif sig.signal.type == nil and sig.count > 0 then
                item_signals[#item_signals + 1] = sig
            end
        end
    end

    -- Planet row
    local planet_row = frame.add{type = "flow", direction = "horizontal"}
    planet_row.style.vertical_align = "center"
    planet_row.add{type = "label", caption = {"plh-gui.prd-planet"}}
    local planet_caption
    if source_planet then
        local proto = prototypes.space_location and prototypes.space_location[source_planet]
        planet_caption = proto and proto.localised_name or source_planet
    else
        planet_caption = {"plh-gui.prd-no-planet"}
    end
    local planet_lbl = planet_row.add{type = "label", caption = planet_caption}
    planet_lbl.style.font = "default-bold"

    frame.add{type = "line", direction = "horizontal"}

    -- Requests header
    local req_row = frame.add{type = "flow", direction = "horizontal"}
    req_row.add{type = "label", caption = {"plh-gui.prd-requests"}}
    local count_lbl = req_row.add{type = "label", caption = " (" .. #item_signals .. ")"}
    count_lbl.style.font_color = {r = 0.7, g = 0.7, b = 0.7}

    if #item_signals == 0 then
        local none_lbl = frame.add{type = "label", caption = {"plh-gui.prd-no-requests"}}
        none_lbl.style.font_color = {r = 0.7, g = 0.7, b = 0.7}
    else
        local scroll = frame.add{type = "scroll-pane", direction = "vertical"}
        scroll.style.maximal_height = 220
        scroll.style.minimal_width  = 200
        local tbl = scroll.add{type = "table", column_count = 1}
        for _, sig in ipairs(item_signals) do
            local quality = sig.signal.quality or "normal"
            local icon = quality ~= "normal"
                and "[item=" .. sig.signal.name .. ",quality=" .. quality .. "]"
                or  "[item=" .. sig.signal.name .. "]"
            tbl.add{type = "label", caption = icon .. " " .. sig.count}
        end
    end

    player.opened = frame
    storage.prd_player_entity[player.index] = entity.unit_number
end

script.on_event(defines.events.on_gui_opened, function(event)
    if not event.entity then return end
    local player = game.players[event.player_index]
    if event.entity.name == READER_NAME then
        player.opened = nil
        Gui.create_reader(player, event.entity)
    elseif event.entity.name == MODULATOR_NAME then
        player.opened = nil
        Gui.create_modulator(player, event.entity)
    elseif event.entity.name == TYPE_GATE_NAME then
        player.opened = nil
        Gui.create_type_gate(player, event.entity)
    elseif event.entity.name == SUBTYPE_GATE_NAME then
        player.opened = nil
        Gui.create_subtype_gate(player, event.entity)
    elseif event.entity.name == SUBTYPE_SPREADER_NAME then
        player.opened = nil
        Gui.create_subtype_spreader(player, event.entity)
    elseif event.entity.name == PRD_NAME then
        player.opened = nil
        Gui.create_prd(player, event.entity)
    end
end)

script.on_event(defines.events.on_gui_closed, function(event)
    local player = game.players[event.player_index]
    if event.entity then
        if event.entity.name == READER_NAME    then Gui.close_reader(player)    end
        if event.entity.name == MODULATOR_NAME then Gui.close_modulator(player) end
        if event.entity.name == TYPE_GATE_NAME    then Gui.close_type_gate(player)    end
        if event.entity.name == SUBTYPE_GATE_NAME     then Gui.close_subtype_gate(player)     end
        if event.entity.name == SUBTYPE_SPREADER_NAME  then Gui.close_subtype_spreader(player)  end
        if event.entity.name == PRD_NAME               then Gui.close_prd(player)               end
        return
    end
    if not event.element then return end
    if event.element.name == READER_FRAME then
        if event.element.valid then event.element.destroy() end
        storage.reader_player_entity[player.index] = nil
    elseif event.element.name == MODULATOR_FRAME then
        if event.element.valid then event.element.destroy() end
        storage.modulator_player_entity[player.index] = nil
    elseif event.element.name == TYPE_GATE_FRAME then
        if event.element.valid then event.element.destroy() end
        storage.type_gate_player_entity[player.index] = nil
    elseif event.element.name == SUBTYPE_GATE_FRAME then
        if event.element.valid then event.element.destroy() end
        storage.subtype_gate_player_entity[player.index] = nil
    elseif event.element.name == SUBTYPE_SPREADER_FRAME then
        if event.element.valid then event.element.destroy() end
        storage.subtype_spreader_player_entity[player.index] = nil
    elseif event.element.name == PRD_FRAME then
        if event.element.valid then event.element.destroy() end
        storage.prd_player_entity[player.index] = nil
    end
end)

script.on_event(defines.events.on_gui_click, function(event)
    if not event.element then return end
    local player = game.players[event.player_index]
    if event.element.name == READER_CLOSE_BTN then
        Gui.close_reader(player)
    elseif event.element.name == MODULATOR_CLOSE_BTN then
        Gui.close_modulator(player)
    elseif event.element.name == TYPE_GATE_CLOSE_BTN then
        Gui.close_type_gate(player)
    elseif event.element.name == SUBTYPE_GATE_CLOSE_BTN then
        Gui.close_subtype_gate(player)
    elseif event.element.name == SUBTYPE_SPREADER_CLOSE_BTN then
        Gui.close_subtype_spreader(player)
    elseif event.element.name == PRD_CLOSE then
        Gui.close_prd(player)
    end
end)

script.on_event(defines.events.on_player_changed_position, function(event)
    local player = game.players[event.player_index]

    local function check_proximity(unit_number, entity_table, close_fn)
        if not unit_number then return end
        local entity = entity_table[unit_number]
        if not (entity and entity.valid) then close_fn(player) return end
        local dx = player.position.x - entity.position.x
        local dy = player.position.y - entity.position.y
        if dx * dx + dy * dy > 100 then close_fn(player) end
    end

    check_proximity(storage.reader_player_entity[player.index],      storage.readers,      Gui.close_reader)
    check_proximity(storage.modulator_player_entity[player.index],   storage.modulators,   Gui.close_modulator)
    check_proximity(storage.type_gate_player_entity[player.index],   storage.type_gates,   Gui.close_type_gate)
    check_proximity(storage.subtype_gate_player_entity[player.index],   storage.subtype_gates,    Gui.close_subtype_gate)
    check_proximity(storage.subtype_spreader_player_entity[player.index],storage.subtype_spreaders,Gui.close_subtype_spreader)
    check_proximity(storage.prd_player_entity and storage.prd_player_entity[player.index], storage.prd_entities, Gui.close_prd)
end)

script.on_event(defines.events.on_gui_selection_state_changed, function(event)
    if not event.element then return end
    local player = game.players[event.player_index]

    if event.element.name == READER_MODE_DROPDOWN then
        local unit_number = storage.reader_player_entity[player.index]
        if not unit_number then return end
        local idx = event.element.selected_index
        storage.reader_mode[unit_number] = idx == 2 and "all-producers" or idx == 3 and "best-producer"
                                        or idx == 4 and "ingredients" or "producer"
    elseif event.element.name == MODULATOR_DROPDOWN
        or event.element.name == MODULATOR_STEPS_DROPDOWN
        or event.element.name == MODULATOR_QUALITY_DROPDOWN then
        local unit_number = storage.modulator_player_entity[player.index]
        if not unit_number then return end
        if event.element.name == MODULATOR_DROPDOWN then
            local idx = event.element.selected_index
            local new_mode = idx == 2 and "upstep-clamp" or idx == 3 and "remove"
                          or idx == 4 and "multiplex"    or idx == 5 and "set"
                          or idx == 6 and "read-quality" or "upstep"
            storage.modulator_mode[unit_number] = new_mode
            local frame = player.gui.screen[MODULATOR_FRAME]
            if frame and frame.valid then
                local steps_row = frame[MODULATOR_STEPS_ROW]
                if steps_row and steps_row.valid then
                    local steps_dd = steps_row[MODULATOR_STEPS_DROPDOWN]
                    if steps_dd and steps_dd.valid then
                        steps_dd.enabled = new_mode == "upstep" or new_mode == "upstep-clamp"
                    end
                end
                local quality_row = frame[MODULATOR_QUALITY_ROW]
                if quality_row and quality_row.valid then
                    local quality_dd = quality_row[MODULATOR_QUALITY_DROPDOWN]
                    if quality_dd and quality_dd.valid then
                        quality_dd.enabled = new_mode == "set"
                    end
                end
            end
        elseif event.element.name == MODULATOR_STEPS_DROPDOWN then
            storage.modulator_steps[unit_number] = STEPS_VALUES[event.element.selected_index]
        elseif event.element.name == MODULATOR_QUALITY_DROPDOWN then
            storage.modulator_quality[unit_number] = QUALITY_NAMES[event.element.selected_index]
        end
    elseif event.element.name == TYPE_GATE_DROPDOWN or event.element.name == TYPE_GATE_MODE_DROPDOWN then
        local unit_number = storage.type_gate_player_entity[player.index]
        if not unit_number then return end
        if event.element.name == TYPE_GATE_DROPDOWN then
            storage.type_gate_type[unit_number] = TYPE_NAMES[event.element.selected_index]
        else
            local new_mode = GATE_MODES[event.element.selected_index]
            storage.type_gate_mode[unit_number] = new_mode
            local frame = player.gui.screen[TYPE_GATE_FRAME]
            if frame and frame.valid then
                local trow = frame[TYPE_GATE_TYPE_ROW]
                if trow and trow.valid then
                    local tdd = trow[TYPE_GATE_DROPDOWN]
                    if tdd and tdd.valid then tdd.enabled = new_mode ~= "signal" end
                end
            end
        end
    elseif event.element.name == SUBTYPE_GATE_MODE_DROPDOWN then
        local unit_number = storage.subtype_gate_player_entity[player.index]
        if not unit_number then return end
        local new_mode = event.element.selected_index == 2 and "exclude" or "allow"
        storage.subtype_gate_mode[unit_number] = new_mode
    elseif event.element.name == SUBTYPE_LIST then
        local unit_number = storage.subtype_gate_player_entity[player.index]
        if not unit_number then return end
        local idx = event.element.selected_index
        local items = event.element.items
        if idx > 0 and items[idx] then
            local selected = items[idx]
            storage.subtype_gate_subgroup[unit_number] = selected
            local frame = player.gui.screen[SUBTYPE_GATE_FRAME]
            if frame and frame.valid then
                local sel_row = frame[SUBTYPE_SEL_ROW]
                if sel_row and sel_row.valid then
                    local lbl = sel_row[SUBTYPE_SELECTED_LABEL]
                    if lbl and lbl.valid then lbl.caption = selected end
                end
            end
        end
    elseif event.element.name == SPREADER_LIST then
        local unit_number = storage.subtype_spreader_player_entity[player.index]
        if not unit_number then return end
        local idx = event.element.selected_index
        local items = event.element.items
        if idx > 0 and items[idx] then
            local selected = items[idx]
            storage.subtype_spreader_subgroup[unit_number] = selected
            local frame = player.gui.screen[SUBTYPE_SPREADER_FRAME]
            if frame and frame.valid then
                local sel_row = frame[SPREADER_SEL_ROW]
                if sel_row and sel_row.valid then
                    local lbl = sel_row[SPREADER_SELECTED_LABEL]
                    if lbl and lbl.valid then lbl.caption = selected end
                end
            end
        end
    end
end)

script.on_event(defines.events.on_gui_text_changed, function(event)
    if not event.element then return end
    local player = game.players[event.player_index]
    if event.element.name == SUBTYPE_SEARCH_FIELD then
        local frame = player.gui.screen[SUBTYPE_GATE_FRAME]
        if not (frame and frame.valid) then return end
        local list = frame[SUBTYPE_LIST]
        if list and list.valid then
            list.items = filter_subgroups(event.element.text)
            list.selected_index = 0
        end
    elseif event.element.name == SPREADER_SEARCH_FIELD then
        local frame = player.gui.screen[SUBTYPE_SPREADER_FRAME]
        if not (frame and frame.valid) then return end
        local list = frame[SPREADER_LIST]
        if list and list.valid then
            list.items = filter_subgroups(event.element.text)
            list.selected_index = 0
        end
    end
end)

script.on_event(defines.events.on_gui_checked_state_changed, function(event)
    if not event.element or event.element.name ~= PRD_TOGGLE then return end
    local player = game.players[event.player_index]
    local unit_number = storage.prd_player_entity[player.index]
    if not unit_number then return end
    local entity = storage.prd_entities[unit_number]
    if not (entity and entity.valid) then return end
    storage.prd_enabled[entity.unit_number] = event.element.state
end)

return Gui
