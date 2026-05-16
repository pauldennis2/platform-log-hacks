-- GUI management for Quality Modulator and Quality Gate.
-- Required by control.lua; returns {close_modulator, close_gate} for use in
-- on_modulator_removed / on_gate_removed.

local READER_NAME          = "plh-recipe-reader"
local READER_FRAME         = "plh-reader-frame"
local READER_CLOSE_BTN     = "plh-reader-close"
local READER_MODE_DROPDOWN = "plh-reader-mode-dropdown"

local MODULATOR_NAME           = "plh-quality-modulator"
local MODULATOR_FRAME          = "plh-modulator-frame"
local MODULATOR_CLOSE_BTN      = "plh-modulator-close"
local MODULATOR_DROPDOWN       = "plh-modulator-mode-dropdown"
local MODULATOR_STEPS_DROPDOWN = "plh-modulator-steps-dropdown"
local MODULATOR_STEPS_ROW      = "plh-modulator-steps-row"

local GATE_NAME          = "plh-quality-gate"
local GATE_FRAME         = "plh-gate-frame"
local GATE_CLOSE_BTN     = "plh-gate-close"
local GATE_MODE_DROPDOWN = "plh-gate-mode-dropdown"
local GATE_MODE_ROW      = "plh-gate-mode-row"
local GATE_DROPDOWN      = "plh-gate-quality-dropdown"
local GATE_QUALITY_ROW   = "plh-gate-quality-row"

local TYPE_GATE_NAME          = "plh-type-gate"
local TYPE_GATE_FRAME         = "plh-type-gate-frame"
local TYPE_GATE_CLOSE_BTN     = "plh-type-gate-close"
local TYPE_GATE_MODE_DROPDOWN = "plh-type-gate-mode-dropdown"
local TYPE_GATE_MODE_ROW      = "plh-type-gate-mode-row"
local TYPE_GATE_DROPDOWN      = "plh-type-gate-type-dropdown"
local TYPE_GATE_TYPE_ROW      = "plh-type-gate-type-row"

local GATE_MODES    = {"allow", "exclude", "signal"}
local TYPE_NAMES    = {"intermediate", "logistics", "production", "combat", "module", "other"}
local QUALITY_NAMES = {"normal", "uncommon", "rare", "epic", "legendary"}
local STEPS_VALUES  = {-4, -3, -2, -1, 1, 2, 3, 4}

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
    local mode_index = mode == "all-producers" and 2 or mode == "ingredients" and 3 or 1
    local row = frame.add{type = "flow", direction = "horizontal"}
    row.style.vertical_align = "center"
    row.add{type = "label", caption = {"plh-gui.mode"}}
    row.add{
        type           = "drop-down",
        name           = READER_MODE_DROPDOWN,
        items          = {{"plh-gui.reader-producer"}, {"plh-gui.reader-all-producers"}, {"plh-gui.reader-ingredients"}},
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

function Gui.close_gate(player)
    local frame = player.gui.screen[GATE_FRAME]
    if frame and frame.valid then frame.destroy() end
    player.opened = nil
    storage.gate_player_entity[player.index] = nil
end

function Gui.create_modulator(player, entity)
    local existing = player.gui.screen[MODULATOR_FRAME]
    if existing then existing.destroy() end

    local frame = player.gui.screen.add{type = "frame", name = MODULATOR_FRAME, direction = "vertical"}
    frame.auto_center = true
    make_titlebar(frame, {"entity-name.plh-quality-modulator"}, MODULATOR_CLOSE_BTN)

    local mode  = storage.modulator_mode[entity.unit_number]  or "upstep"
    local steps = storage.modulator_steps[entity.unit_number] or 1
    local mode_index = mode == "upstep" and 1 or mode == "upstep-clamp" and 2
                    or mode == "remove" and 3 or 4
    local steps_idx = 5  -- default: steps=1 is at index 5
    for i, v in ipairs(STEPS_VALUES) do if v == steps then steps_idx = i break end end

    local row = frame.add{type = "flow", direction = "horizontal"}
    row.style.vertical_align = "center"
    row.add{type = "label", caption = {"plh-gui.mode"}}
    row.add{
        type           = "drop-down",
        name           = MODULATOR_DROPDOWN,
        items          = {{"plh-gui.upstep"}, {"plh-gui.upstep-clamp"}, {"plh-gui.remove"}, {"plh-gui.multiplex"}},
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

    player.opened = frame
    storage.modulator_player_entity[player.index] = entity.unit_number
end

function Gui.create_gate(player, entity)
    local existing = player.gui.screen[GATE_FRAME]
    if existing then existing.destroy() end

    local frame = player.gui.screen.add{type = "frame", name = GATE_FRAME, direction = "vertical"}
    frame.auto_center = true
    make_titlebar(frame, {"entity-name.plh-quality-gate"}, GATE_CLOSE_BTN)

    local mode = storage.gate_mode[entity.unit_number] or "allow"
    local mode_index = 1
    for i, m in ipairs(GATE_MODES) do if m == mode then mode_index = i break end end
    local mode_row = frame.add{type = "flow", name = GATE_MODE_ROW, direction = "horizontal"}
    mode_row.style.vertical_align = "center"
    mode_row.add{type = "label", caption = {"plh-gui.gate-mode"}}
    mode_row.add{
        type           = "drop-down",
        name           = GATE_MODE_DROPDOWN,
        items          = {{"plh-gui.gate-allow"}, {"plh-gui.gate-exclude"}, {"plh-gui.gate-signal"}},
        selected_index = mode_index,
    }

    local quality_row = frame.add{type = "flow", name = GATE_QUALITY_ROW, direction = "horizontal"}
    quality_row.style.vertical_align = "center"
    quality_row.add{type = "label", caption = {"plh-gui.quality"}}

    local quality  = storage.gate_quality[entity.unit_number] or "normal"
    local selected = 1
    for i, q in ipairs(QUALITY_NAMES) do if q == quality then selected = i break end end
    quality_row.add{
        type           = "drop-down",
        name           = GATE_DROPDOWN,
        items          = {
            {"quality-name.normal"},
            {"quality-name.uncommon"},
            {"quality-name.rare"},
            {"quality-name.epic"},
            {"quality-name.legendary"},
        },
        selected_index = selected,
        enabled        = mode ~= "signal",
    }

    player.opened = frame
    storage.gate_player_entity[player.index] = entity.unit_number
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

script.on_event(defines.events.on_gui_opened, function(event)
    if not event.entity then return end
    local player = game.players[event.player_index]
    if event.entity.name == READER_NAME then
        player.opened = nil
        Gui.create_reader(player, event.entity)
    elseif event.entity.name == MODULATOR_NAME then
        player.opened = nil
        Gui.create_modulator(player, event.entity)
    elseif event.entity.name == GATE_NAME then
        player.opened = nil
        Gui.create_gate(player, event.entity)
    elseif event.entity.name == TYPE_GATE_NAME then
        player.opened = nil
        Gui.create_type_gate(player, event.entity)
    end
end)

script.on_event(defines.events.on_gui_closed, function(event)
    local player = game.players[event.player_index]
    if event.entity then
        if event.entity.name == READER_NAME    then Gui.close_reader(player)    end
        if event.entity.name == MODULATOR_NAME then Gui.close_modulator(player) end
        if event.entity.name == GATE_NAME      then Gui.close_gate(player)      end
        if event.entity.name == TYPE_GATE_NAME then Gui.close_type_gate(player) end
        return
    end
    if not event.element then return end
    if event.element.name == READER_FRAME then
        if event.element.valid then event.element.destroy() end
        storage.reader_player_entity[player.index] = nil
    elseif event.element.name == MODULATOR_FRAME then
        if event.element.valid then event.element.destroy() end
        storage.modulator_player_entity[player.index] = nil
    elseif event.element.name == GATE_FRAME then
        if event.element.valid then event.element.destroy() end
        storage.gate_player_entity[player.index] = nil
    elseif event.element.name == TYPE_GATE_FRAME then
        if event.element.valid then event.element.destroy() end
        storage.type_gate_player_entity[player.index] = nil
    end
end)

script.on_event(defines.events.on_gui_click, function(event)
    if not event.element then return end
    local player = game.players[event.player_index]
    if event.element.name == READER_CLOSE_BTN then
        Gui.close_reader(player)
    elseif event.element.name == MODULATOR_CLOSE_BTN then
        Gui.close_modulator(player)
    elseif event.element.name == GATE_CLOSE_BTN then
        Gui.close_gate(player)
    elseif event.element.name == TYPE_GATE_CLOSE_BTN then
        Gui.close_type_gate(player)
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

    check_proximity(storage.reader_player_entity[player.index],    storage.readers,    Gui.close_reader)
    check_proximity(storage.modulator_player_entity[player.index], storage.modulators, Gui.close_modulator)
    check_proximity(storage.gate_player_entity[player.index],      storage.gates,      Gui.close_gate)
    check_proximity(storage.type_gate_player_entity[player.index], storage.type_gates, Gui.close_type_gate)
end)

script.on_event(defines.events.on_gui_selection_state_changed, function(event)
    if not event.element then return end
    local player = game.players[event.player_index]

    if event.element.name == READER_MODE_DROPDOWN then
        local unit_number = storage.reader_player_entity[player.index]
        if not unit_number then return end
        local idx = event.element.selected_index
        storage.reader_mode[unit_number] = idx == 2 and "all-producers" or idx == 3 and "ingredients" or "producer"
    elseif event.element.name == MODULATOR_DROPDOWN or event.element.name == MODULATOR_STEPS_DROPDOWN then
        local unit_number = storage.modulator_player_entity[player.index]
        if not unit_number then return end
        if event.element.name == MODULATOR_DROPDOWN then
            local idx = event.element.selected_index
            local new_mode = idx == 1 and "upstep" or idx == 2 and "upstep-clamp"
                          or idx == 3 and "remove" or "multiplex"
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
            end
        elseif event.element.name == MODULATOR_STEPS_DROPDOWN then
            storage.modulator_steps[unit_number] = STEPS_VALUES[event.element.selected_index]
        end
    elseif event.element.name == GATE_DROPDOWN or event.element.name == GATE_MODE_DROPDOWN then
        local unit_number = storage.gate_player_entity[player.index]
        if not unit_number then return end
        if event.element.name == GATE_DROPDOWN then
            storage.gate_quality[unit_number] = QUALITY_NAMES[event.element.selected_index]
        else
            local new_mode = GATE_MODES[event.element.selected_index]
            storage.gate_mode[unit_number] = new_mode
            local frame = player.gui.screen[GATE_FRAME]
            if frame and frame.valid then
                local qrow = frame[GATE_QUALITY_ROW]
                if qrow and qrow.valid then
                    local qdd = qrow[GATE_DROPDOWN]
                    if qdd and qdd.valid then qdd.enabled = new_mode ~= "signal" end
                end
            end
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
    end
end)

return Gui
