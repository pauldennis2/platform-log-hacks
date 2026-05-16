local DRIVER_NAME = "plh-platform-request-driver"
local SECTION_PREFIX = "plh-driver-"

-- ── Shared helpers ────────────────────────────────────────────────────────────

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

-- Called once when a companion is first created: enables it and creates its section.
local function init_output(output)
    local behavior = output.get_or_create_control_behavior()
    behavior.enabled = true
    local section = get_circuit_section(behavior)
    section.active = true
end

-- Called each tick: returns the writable section (behavior already initialized).
local function get_output_section(output)
    local behavior = output.get_or_create_control_behavior()
    return get_circuit_section(behavior)
end

-- Returns signals from the combinator's input network (nil if nothing connected).
local function read_input(entity)
    return entity.get_signals(
        defines.wire_connector_id.combinator_input_red,
        defines.wire_connector_id.combinator_input_green
    )
end

-- Builds a stable string key from input signals (+ optional mode string) for
-- change detection. Sorting makes it order-independent across ticks.
local function signals_key(signals, extra)
    local parts = {}
    if signals then
        for _, sig in ipairs(signals) do
            parts[#parts + 1] = (sig.signal.type or "i") .. sig.count
                             .. (sig.signal.name    or "") .. (sig.signal.quality or "n")
        end
        table.sort(parts)
    end
    if extra then parts[#parts + 1] = extra end
    return table.concat(parts, "|")
end

-- ── Quality filter builders ───────────────────────────────────────────────────

local QUALITY_ORDER = {"normal", "uncommon", "rare", "epic", "legendary"}
local QUALITY_INDEX = {}
for i, q in ipairs(QUALITY_ORDER) do QUALITY_INDEX[q] = i end

local function build_upstep_filters(signals, steps)
    steps = steps or 1
    local filters = {}
    for _, sig in ipairs(signals) do
        if sig.signal.type == nil then
            local idx    = QUALITY_INDEX[sig.signal.quality or "normal"] or 1
            local bumped = QUALITY_ORDER[((idx - 1 + steps) % 5) + 1]
            filters[#filters + 1] = {
                value = {type = "item", name = sig.signal.name, quality = bumped},
                min   = sig.count,
            }
        end
    end
    return filters
end

local function build_remove_filters(signals)
    local filters = {}
    for _, sig in ipairs(signals) do
        if sig.signal.type == nil then
            filters[#filters + 1] = {
                value = {type = "item", name = sig.signal.name, quality = "normal"},
                min   = sig.count,
            }
        end
    end
    return filters
end

-- ── Type Detector ─────────────────────────────────────────────────────────────

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

local item_cat_cache = {}
local function categorize(name)
    local cached = item_cat_cache[name]
    if cached then return cached end
    local proto = prototypes.item[name]
    local cat
    if not proto then
        cat = "other"
    else
        local t = proto.type
        local g = proto.group and proto.group.name or ""
        if t == "module"                             then cat = "module"
        elseif t == "ammo" or t == "gun"
            or t == "armor" or t == "capsule"        then cat = "combat"
        elseif g == "combat"                         then cat = "combat"
        elseif g == "intermediate-products"          then cat = "intermediate"
        elseif g == "logistics"                      then cat = "logistics"
        elseif g == "production"                     then cat = "production"
        else                                              cat = "other"
        end
    end
    item_cat_cache[name] = cat
    return cat
end

local function update_detector(entity)
    local id     = entity.unit_number
    local output = storage.detector_outputs[id]
    if not (output and output.valid) then return end

    local signals = read_input(entity)
    local key     = signals_key(signals)
    if key == storage.entity_keys[id] then return end
    storage.entity_keys[id] = key

    local section = get_output_section(output)
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
            value = {type = "virtual", name = CATEGORY_SIGNAL[cat], quality = "normal"},
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
    init_output(output)
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
    storage.entity_keys[entity.unit_number]      = nil
end

-- ── Quality Up-stepper ────────────────────────────────────────────────────────

local UPSTEPPER_NAME   = "plh-quality-upstepper"
local UPSTEPPER_OUTPUT = "plh-quality-upstepper-output"

local function update_upstepper(entity)
    local id     = entity.unit_number
    local output = storage.upstepper_outputs[id]
    if not (output and output.valid) then return end

    local signals = read_input(entity)
    local key     = signals_key(signals)
    if key == storage.entity_keys[id] then return end
    storage.entity_keys[id] = key

    local section = get_output_section(output)
    if not signals then section.filters = {} return end
    section.filters = build_upstep_filters(signals)
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
    init_output(output)
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
    storage.entity_keys[entity.unit_number]       = nil
end

-- ── Quality Remover ───────────────────────────────────────────────────────────

local REMOVER_NAME   = "plh-quality-remover"
local REMOVER_OUTPUT = "plh-quality-remover-output"

local function update_remover(entity)
    local id     = entity.unit_number
    local output = storage.remover_outputs[id]
    if not (output and output.valid) then return end

    local signals = read_input(entity)
    local key     = signals_key(signals)
    if key == storage.entity_keys[id] then return end
    storage.entity_keys[id] = key

    local section = get_output_section(output)
    if not signals then section.filters = {} return end
    section.filters = build_remove_filters(signals)
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
    init_output(output)
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
    storage.entity_keys[entity.unit_number]     = nil
end

-- ── Quality Reader ────────────────────────────────────────────────────────────

local QUALITY_READER_NAME   = "plh-quality-reader"
local QUALITY_READER_OUTPUT = "plh-quality-reader-output"

local function update_quality_reader(entity)
    local id     = entity.unit_number
    local output = storage.quality_reader_outputs[id]
    if not (output and output.valid) then return end

    local signals = read_input(entity)
    local key     = signals_key(signals)
    if key == storage.entity_keys[id] then return end
    storage.entity_keys[id] = key

    local section = get_output_section(output)
    if not signals then section.filters = {} return end

    local totals = {}
    for _, sig in ipairs(signals) do
        if sig.signal.type == nil then
            local q = sig.signal.quality or "normal"
            totals[q] = (totals[q] or 0) + sig.count
        end
    end

    -- TODO: quality signals (type="quality") are accepted by section.filters and read back
    -- correctly, but do not appear on the circuit network output. Cause unknown — may be a
    -- Factorio API limitation. Needs further investigation or a virtual-signal workaround.
    local filters = {}
    for quality, count in pairs(totals) do
        filters[#filters + 1] = {
            value = {type = "quality", name = quality},
            min   = count,
        }
    end
    section.filters = filters
end

local function on_quality_reader_built(event)
    local entity = event.entity or event.created_entity
    if not (entity and entity.valid and entity.name == QUALITY_READER_NAME) then return end

    local output = entity.surface.create_entity({
        name        = QUALITY_READER_OUTPUT,
        position    = entity.position,
        force       = entity.force,
        raise_built = false,
    })
    if not output then return end

    wire_companion(entity, output)
    init_output(output)
    storage.quality_readers[entity.unit_number]        = entity
    storage.quality_reader_outputs[entity.unit_number] = output
end

local function on_quality_reader_removed(event)
    local entity = event.entity
    if not (entity and entity.name == QUALITY_READER_NAME) then return end

    local output = storage.quality_reader_outputs[entity.unit_number]
    if output and output.valid then output.destroy() end
    storage.quality_readers[entity.unit_number]        = nil
    storage.quality_reader_outputs[entity.unit_number] = nil
    storage.entity_keys[entity.unit_number]            = nil
end

-- ── Quality Multiplexer ───────────────────────────────────────────────────────

local MULTIPLEXER_NAME   = "plh-quality-multiplexer"
local MULTIPLEXER_OUTPUT = "plh-quality-multiplexer-output"

local function update_multiplexer(entity)
    local id     = entity.unit_number
    local output = storage.multiplexer_outputs[id]
    if not (output and output.valid) then return end

    local signals = read_input(entity)
    local key     = signals_key(signals)
    if key == storage.entity_keys[id] then return end
    storage.entity_keys[id] = key

    local section = get_output_section(output)
    if not signals then section.filters = {} return end

    local totals = {}
    for _, sig in ipairs(signals) do
        if sig.signal.type == nil then
            local name = sig.signal.name
            totals[name] = (totals[name] or 0) + sig.count
        end
    end

    local filters = {}
    for name, total in pairs(totals) do
        for _, quality in ipairs(QUALITY_ORDER) do
            filters[#filters + 1] = {
                value = {type = "item", name = name, quality = quality},
                min   = total,
            }
        end
    end
    section.filters = filters
end

local function on_multiplexer_built(event)
    local entity = event.entity or event.created_entity
    if not (entity and entity.valid and entity.name == MULTIPLEXER_NAME) then return end

    local output = entity.surface.create_entity({
        name        = MULTIPLEXER_OUTPUT,
        position    = entity.position,
        force       = entity.force,
        raise_built = false,
    })
    if not output then return end

    wire_companion(entity, output)
    init_output(output)
    storage.multiplexers[entity.unit_number]        = entity
    storage.multiplexer_outputs[entity.unit_number] = output
end

local function on_multiplexer_removed(event)
    local entity = event.entity
    if not (entity and entity.name == MULTIPLEXER_NAME) then return end

    local output = storage.multiplexer_outputs[entity.unit_number]
    if output and output.valid then output.destroy() end
    storage.multiplexers[entity.unit_number]        = nil
    storage.multiplexer_outputs[entity.unit_number] = nil
    storage.entity_keys[entity.unit_number]         = nil
end

-- ── Quality Modulator ─────────────────────────────────────────────────────────

local MODULATOR_NAME           = "plh-quality-modulator"
local MODULATOR_OUTPUT         = "plh-quality-modulator-output"
local MODULATOR_FRAME          = "plh-modulator-frame"
local MODULATOR_CLOSE_BTN      = "plh-modulator-close"
local MODULATOR_DROPDOWN       = "plh-modulator-mode-dropdown"
local MODULATOR_STEPS_DROPDOWN = "plh-modulator-steps-dropdown"
local MODULATOR_STEPS_ROW      = "plh-modulator-steps-row"

local function update_modulator(entity)
    local id     = entity.unit_number
    local output = storage.modulator_outputs[id]
    if not (output and output.valid) then return end

    local signals = read_input(entity)
    local mode    = storage.modulator_mode[id]  or "upstep"
    local steps   = storage.modulator_steps[id] or 1
    local key     = signals_key(signals, mode .. steps)
    if key == storage.entity_keys[id] then return end
    storage.entity_keys[id] = key

    local section = get_output_section(output)
    if not signals then section.filters = {} return end
    section.filters = mode == "upstep"
        and build_upstep_filters(signals, steps)
        or  build_remove_filters(signals)
end

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

local function create_modulator_gui(player, entity)
    local existing = player.gui.screen[MODULATOR_FRAME]
    if existing then existing.destroy() end

    local frame = player.gui.screen.add{type = "frame", name = MODULATOR_FRAME, direction = "vertical"}
    frame.auto_center = true
    make_titlebar(frame, {"entity-name.plh-quality-modulator"}, MODULATOR_CLOSE_BTN)

    local mode  = storage.modulator_mode[entity.unit_number]  or "upstep"
    local steps = storage.modulator_steps[entity.unit_number] or 1

    local row = frame.add{type = "flow", direction = "horizontal"}
    row.style.vertical_align = "center"
    row.add{type = "label", caption = {"plh-gui.mode"}}
    row.add{
        type           = "drop-down",
        name           = MODULATOR_DROPDOWN,
        items          = {{"plh-gui.upstep"}, {"plh-gui.remove"}},
        selected_index = mode == "upstep" and 1 or 2,
    }

    local steps_row = frame.add{type = "flow", name = MODULATOR_STEPS_ROW, direction = "horizontal"}
    steps_row.style.vertical_align = "center"
    steps_row.add{type = "label", caption = {"plh-gui.steps"}}
    steps_row.add{
        type           = "drop-down",
        name           = MODULATOR_STEPS_DROPDOWN,
        items          = {"1", "2", "3", "4"},
        selected_index = steps,
        enabled        = mode == "upstep",
    }

    player.opened = frame
    storage.modulator_player_entity[player.index] = entity.unit_number
end

local function on_modulator_built(event)
    local entity = event.entity or event.created_entity
    if not (entity and entity.valid and entity.name == MODULATOR_NAME) then return end

    local output = entity.surface.create_entity({
        name        = MODULATOR_OUTPUT,
        position    = entity.position,
        force       = entity.force,
        raise_built = false,
    })
    if not output then return end

    wire_companion(entity, output)
    init_output(output)
    storage.modulators[entity.unit_number]        = entity
    storage.modulator_outputs[entity.unit_number] = output
end

local function on_modulator_removed(event)
    local entity = event.entity
    if not (entity and entity.name == MODULATOR_NAME) then return end

    local output = storage.modulator_outputs[entity.unit_number]
    if output and output.valid then output.destroy() end
    storage.modulators[entity.unit_number]        = nil
    storage.modulator_outputs[entity.unit_number] = nil
    storage.modulator_mode[entity.unit_number]    = nil
    storage.modulator_steps[entity.unit_number]   = nil
    storage.entity_keys[entity.unit_number]       = nil

    -- Close the GUI for any player who has this modulator open
    for _, player in pairs(game.players) do
        if storage.modulator_player_entity[player.index] == entity.unit_number then
            local frame = player.gui.screen[MODULATOR_FRAME]
            if frame then frame.destroy() end
            storage.modulator_player_entity[player.index] = nil
        end
    end
end

local function close_modulator_gui(player)
    local frame = player.gui.screen[MODULATOR_FRAME]
    if frame and frame.valid then frame.destroy() end
    player.opened = nil
    storage.modulator_player_entity[player.index] = nil
end

local function close_gate_gui(player)
    local frame = player.gui.screen[GATE_FRAME]
    if frame and frame.valid then frame.destroy() end
    player.opened = nil
    storage.gate_player_entity[player.index] = nil
end

script.on_event(defines.events.on_gui_opened, function(event)
    if not event.entity then return end
    local player = game.players[event.player_index]
    if event.entity.name == MODULATOR_NAME then
        player.opened = nil
        create_modulator_gui(player, event.entity)
    elseif event.entity.name == GATE_NAME then
        player.opened = nil
        create_gate_gui(player, event.entity)
    end
end)

script.on_event(defines.events.on_gui_closed, function(event)
    local player = game.players[event.player_index]
    -- Entity close path: Escape/E closes the underlying combinator entity GUI
    if event.entity then
        if event.entity.name == MODULATOR_NAME then close_modulator_gui(player) end
        if event.entity.name == GATE_NAME       then close_gate_gui(player)     end
        return
    end
    -- Custom frame close path: player.opened = frame, then closed
    if not event.element then return end
    if event.element.name == MODULATOR_FRAME then
        if event.element.valid then event.element.destroy() end
        storage.modulator_player_entity[player.index] = nil
    elseif event.element.name == GATE_FRAME then
        if event.element.valid then event.element.destroy() end
        storage.gate_player_entity[player.index] = nil
    end
end)

script.on_event(defines.events.on_gui_click, function(event)
    if not event.element then return end
    local player = game.players[event.player_index]
    if event.element.name == MODULATOR_CLOSE_BTN then
        close_modulator_gui(player)
    elseif event.element.name == GATE_CLOSE_BTN then
        close_gate_gui(player)
    end
end)

-- Close open GUIs when the player walks out of reach (~10 tiles).
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

    check_proximity(storage.modulator_player_entity[player.index], storage.modulators, close_modulator_gui)
    check_proximity(storage.gate_player_entity[player.index],      storage.gates,      close_gate_gui)
end)

script.on_event(defines.events.on_gui_selection_state_changed, function(event)
    if not event.element then return end
    local player = game.players[event.player_index]

    if event.element.name == MODULATOR_DROPDOWN or event.element.name == MODULATOR_STEPS_DROPDOWN then
        local unit_number = storage.modulator_player_entity[player.index]
        if not unit_number then return end
        if event.element.name == MODULATOR_DROPDOWN then
            local new_mode = event.element.selected_index == 1 and "upstep" or "remove"
            storage.modulator_mode[unit_number] = new_mode
            local frame = player.gui.screen[MODULATOR_FRAME]
            if frame and frame.valid then
                local steps_row = frame[MODULATOR_STEPS_ROW]
                if steps_row and steps_row.valid then
                    local steps_dd = steps_row[MODULATOR_STEPS_DROPDOWN]
                    if steps_dd and steps_dd.valid then
                        steps_dd.enabled = new_mode == "upstep"
                    end
                end
            end
        elseif event.element.name == MODULATOR_STEPS_DROPDOWN then
            storage.modulator_steps[unit_number] = event.element.selected_index
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
    end
end)

-- ── Storage Reader ────────────────────────────────────────────────────────────
-- Outputs signal-A (0-100) = average % available (space remaining) across all directly-wired
-- storage entities (item chests or fluid tanks).
-- Limitation: only sees entities with a direct wire segment to this entity,
-- not transitive network members. Wire the reader directly to the storage.

local STORAGE_READER_NAME   = "plh-storage-reader"
local STORAGE_READER_OUTPUT = "plh-storage-reader-output"

local function get_fullness(entity)
    local inv = entity.get_inventory(defines.inventory.chest)
    if inv then
        local total_slots = #inv
        if total_slots == 0 then return nil end
        local used_slots = 0
        for _, entry in pairs(inv.get_contents()) do
            local proto = prototypes.item[entry.name]
            local stack_size = proto and proto.stack_size or 1
            used_slots = used_slots + math.ceil(entry.count / stack_size)
        end
        return math.min(100, math.floor(used_slots / total_slots * 100))
    end
    local fb = entity.fluidbox
    if fb and #fb > 0 then
        local total_amount   = 0
        local total_capacity = 0
        for i = 1, #fb do
            local fluid = fb[i]
            if fluid then total_amount = total_amount + fluid.amount end
            local proto = fb.get_prototype(i)
            if proto then total_capacity = total_capacity + proto.volume end
        end
        if total_capacity > 0 then
            return math.min(100, math.floor(total_amount / total_capacity * 100))
        end
    end
    return nil
end

local function update_storage_reader(entity)
    local id     = entity.unit_number
    local output = storage.storage_reader_outputs[id]
    if not (output and output.valid) then return end

    local seen      = {}
    local connected = {}
    for _, connector_id in ipairs({
        defines.wire_connector_id.combinator_input_red,
        defines.wire_connector_id.combinator_input_green,
    }) do
        local connector = entity.get_wire_connector(connector_id, false)
        if connector then
            for _, conn in pairs(connector.connections) do
                local other = conn.target.owner
                if other and other.valid and not seen[other.unit_number] then
                    seen[other.unit_number] = true
                    connected[#connected + 1] = other
                end
            end
        end
    end

    -- Compute the single output value; -1 is the sentinel for "no output".
    local new_val = -1
    if #connected > 0 then
        local total_pct = 0
        local count     = 0
        for _, ent in ipairs(connected) do
            local pct = get_fullness(ent)
            if pct then
                total_pct = total_pct + pct
                count     = count + 1
            end
        end
        if count > 0 then
            new_val = 100 - math.floor(total_pct / count)
        end
    end

    if storage.entity_keys[id] == new_val then return end
    storage.entity_keys[id] = new_val

    local section = get_output_section(output)
    if new_val == -1 then
        section.filters = {}
    else
        section.filters = {{
            value = {type = "virtual", name = "signal-A"},
            min   = new_val,
        }}
    end
end

local function on_storage_reader_built(event)
    local entity = event.entity or event.created_entity
    if not (entity and entity.valid and entity.name == STORAGE_READER_NAME) then return end

    local output = entity.surface.create_entity({
        name        = STORAGE_READER_OUTPUT,
        position    = entity.position,
        force       = entity.force,
        raise_built = false,
    })
    if not output then return end

    wire_companion(entity, output)
    init_output(output)
    storage.storage_readers[entity.unit_number]        = entity
    storage.storage_reader_outputs[entity.unit_number] = output
end

local function on_storage_reader_removed(event)
    local entity = event.entity
    if not (entity and entity.name == STORAGE_READER_NAME) then return end

    local output = storage.storage_reader_outputs[entity.unit_number]
    if output and output.valid then output.destroy() end
    storage.storage_readers[entity.unit_number]        = nil
    storage.storage_reader_outputs[entity.unit_number] = nil
    storage.entity_keys[entity.unit_number]            = nil
end

-- ── Recipe Reader (mode: producer) ───────────────────────────────────────────
-- Outputs item signals for the building that produces each input item.
-- Future option 1: output ingredient signals for each input item's recipe.
-- Future option 2: output item signals for what can be crafted using each input item.

local READER_NAME   = "plh-recipe-reader"
local READER_OUTPUT = "plh-recipe-reader-output"

-- Module-level cache: item_name → producer entity_name.
-- Rebuilt lazily from prototypes; reset on each game load automatically.
local producer_cache = nil

local function get_producer_cache()
    if producer_cache then return producer_cache end

    -- Step 1: crafting category → first player-buildable machine that handles it.
    -- Guard with prototypes.item check to exclude internal non-placeable entities
    -- (e.g. crash-site-assembling-machine) whose names have no matching item — using
    -- those would produce an invalid signal ID that Factorio silently drops.
    local category_machine = {}
    for _, entity in pairs(prototypes.entity) do
        local etype = entity.type
        if etype == "assembling-machine" or etype == "furnace" or etype == "rocket-silo" then
            if prototypes.item[entity.name] then
                for cat in pairs(entity.crafting_categories or {}) do
                    if not category_machine[cat] then
                        category_machine[cat] = entity.name
                    end
                end
            end
        end
    end

    -- Step 2: for each recipe product, map item → machine.
    -- Skip "recycling" category: recycling recipes list the original item as a
    -- product (you recover a fraction), which would make iron-plate → recycler.
    producer_cache = {}
    for _, recipe in pairs(prototypes.recipe) do
        local cat = recipe.category or "crafting"
        if cat ~= "recycling" then
            local machine = category_machine[cat]
            if machine then
                for _, product in pairs(recipe.products or {}) do
                    if product.type == "item" and not producer_cache[product.name] then
                        producer_cache[product.name] = machine
                    end
                end
            end
        end
    end

    return producer_cache
end

local function update_recipe_reader(entity)
    local id     = entity.unit_number
    local output = storage.reader_outputs[id]
    if not (output and output.valid) then return end

    local signals = read_input(entity)
    local key     = signals_key(signals)
    if key == storage.entity_keys[id] then return end
    storage.entity_keys[id] = key

    local section = get_output_section(output)
    if not signals then section.filters = {} return end

    local cache = get_producer_cache()
    local machine_counts = {}
    for _, sig in ipairs(signals) do
        if sig.signal.type == nil then
            local machine = cache[sig.signal.name]
            if machine then
                machine_counts[machine] = (machine_counts[machine] or 0) + sig.count
            end
        end
    end

    local filters = {}
    for machine_name, count in pairs(machine_counts) do
        filters[#filters + 1] = {
            value = {type = "item", name = machine_name, quality = "normal"},
            min   = count,
        }
    end
    section.filters = filters
end

local function on_reader_built(event)
    local entity = event.entity or event.created_entity
    if not (entity and entity.valid and entity.name == READER_NAME) then return end

    local output = entity.surface.create_entity({
        name        = READER_OUTPUT,
        position    = entity.position,
        force       = entity.force,
        raise_built = false,
    })
    if not output then return end

    wire_companion(entity, output)
    init_output(output)
    storage.readers[entity.unit_number]        = entity
    storage.reader_outputs[entity.unit_number] = output
end

local function on_reader_removed(event)
    local entity = event.entity
    if not (entity and entity.name == READER_NAME) then return end

    local output = storage.reader_outputs[entity.unit_number]
    if output and output.valid then output.destroy() end
    storage.readers[entity.unit_number]        = nil
    storage.reader_outputs[entity.unit_number] = nil
    storage.entity_keys[entity.unit_number]    = nil
end

-- ── Quality Gate ──────────────────────────────────────────────────────────────

local GATE_NAME          = "plh-quality-gate"
local GATE_OUTPUT        = "plh-quality-gate-output"
local GATE_FRAME         = "plh-gate-frame"
local GATE_CLOSE_BTN     = "plh-gate-close"
local GATE_MODE_DROPDOWN = "plh-gate-mode-dropdown"
local GATE_MODE_ROW      = "plh-gate-mode-row"
local GATE_DROPDOWN      = "plh-gate-quality-dropdown"
local GATE_QUALITY_ROW   = "plh-gate-quality-row"

local GATE_MODES = {"allow", "exclude", "signal"}

local QUALITY_NAMES = {"normal", "uncommon", "rare", "epic", "legendary"}

local function update_gate(entity)
    local id     = entity.unit_number
    local output = storage.gate_outputs[id]
    if not (output and output.valid) then return end

    local signals = read_input(entity)
    local quality = storage.gate_quality[id] or "normal"
    local mode    = storage.gate_mode[id]    or "allow"
    local key     = signals_key(signals, mode .. quality)
    if key == storage.entity_keys[id] then return end
    storage.entity_keys[id] = key

    local section = get_output_section(output)
    if not signals then section.filters = {} return end

    local filters = {}

    if mode == "signal" then
        local allowed = {}
        for _, sig in ipairs(signals) do
            if sig.signal.type == "quality" and sig.count > 0 then
                allowed[sig.signal.name] = true
            end
        end
        for _, sig in ipairs(signals) do
            if sig.signal.type == nil and allowed[sig.signal.quality or "normal"] then
                filters[#filters + 1] = {
                    value = {type = "item", name = sig.signal.name, quality = sig.signal.quality or "normal"},
                    min   = sig.count,
                }
            end
        end
    else
        for _, sig in ipairs(signals) do
            if sig.signal.type == nil then
                local matches = (sig.signal.quality or "normal") == quality
                if (mode == "allow") == matches then
                    filters[#filters + 1] = {
                        value = {type = "item", name = sig.signal.name, quality = sig.signal.quality or "normal"},
                        min   = sig.count,
                    }
                end
            end
        end
    end
    section.filters = filters
end

local function create_gate_gui(player, entity)
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
    for i, q in ipairs(QUALITY_NAMES) do
        if q == quality then selected = i break end
    end
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

local function on_gate_built(event)
    local entity = event.entity or event.created_entity
    if not (entity and entity.valid and entity.name == GATE_NAME) then return end

    local output = entity.surface.create_entity({
        name        = GATE_OUTPUT,
        position    = entity.position,
        force       = entity.force,
        raise_built = false,
    })
    if not output then return end

    wire_companion(entity, output)
    init_output(output)
    storage.gates[entity.unit_number]        = entity
    storage.gate_outputs[entity.unit_number] = output
end

local function on_gate_removed(event)
    local entity = event.entity
    if not (entity and entity.name == GATE_NAME) then return end

    local output = storage.gate_outputs[entity.unit_number]
    if output and output.valid then output.destroy() end
    storage.gates[entity.unit_number]        = nil
    storage.gate_outputs[entity.unit_number] = nil
    storage.gate_quality[entity.unit_number] = nil
    storage.gate_mode[entity.unit_number]    = nil
    storage.entity_keys[entity.unit_number]  = nil

    for _, player in pairs(game.players) do
        if storage.gate_player_entity[player.index] == entity.unit_number then
            local frame = player.gui.screen[GATE_FRAME]
            if frame then frame.destroy() end
            storage.gate_player_entity[player.index] = nil
        end
    end
end

-- ── Platform Request Driver ───────────────────────────────────────────────────

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

-- ── Surface rescan ───────────────────────────────────────────────────────────
-- Finds every tracked entity on all surfaces and ensures it is registered and
-- has a valid output companion. Called on_configuration_changed so entities
-- placed in previous sessions are never silently lost.

local function rescan_surfaces()
    local specs = {
        {UPSTEPPER_NAME,      UPSTEPPER_OUTPUT,      storage.upsteppers,      storage.upstepper_outputs},
        {REMOVER_NAME,        REMOVER_OUTPUT,        storage.removers,        storage.remover_outputs},
        {DETECTOR_NAME,       DETECTOR_OUTPUT,       storage.detectors,       storage.detector_outputs},
        {QUALITY_READER_NAME, QUALITY_READER_OUTPUT, storage.quality_readers, storage.quality_reader_outputs},
        {MULTIPLEXER_NAME,    MULTIPLEXER_OUTPUT,    storage.multiplexers,    storage.multiplexer_outputs},
        {MODULATOR_NAME,      MODULATOR_OUTPUT,      storage.modulators,      storage.modulator_outputs},
        {STORAGE_READER_NAME, STORAGE_READER_OUTPUT, storage.storage_readers, storage.storage_reader_outputs},
        {READER_NAME,         READER_OUTPUT,         storage.readers,         storage.reader_outputs},
        {GATE_NAME,           GATE_OUTPUT,           storage.gates,           storage.gate_outputs},
    }
    for _, surface in pairs(game.surfaces) do
        for _, spec in ipairs(specs) do
            local ename, oname, ent_tbl, out_tbl = spec[1], spec[2], spec[3], spec[4]
            for _, entity in ipairs(surface.find_entities_filtered({name = ename})) do
                local id     = entity.unit_number
                local output = out_tbl[id]
                if not (output and output.valid) then
                    local pos = entity.position
                    local found = surface.find_entities_filtered({
                        name = oname,
                        area = {{pos.x - 0.2, pos.y - 0.2}, {pos.x + 0.2, pos.y + 0.2}},
                    })
                    output = found[1]
                    if not (output and output.valid) then
                        output = surface.create_entity({
                            name        = oname,
                            position    = entity.position,
                            force       = entity.force,
                            raise_built = false,
                        })
                        if output then wire_companion(entity, output) end
                    end
                    if output and output.valid then init_output(output) end
                end
                if output and output.valid then
                    ent_tbl[id] = entity
                    out_tbl[id] = output
                end
            end
        end
    end
end

-- ── Lifecycle ─────────────────────────────────────────────────────────────────

script.on_init(function()
    storage.consoles                = {}
    storage.plh_active_planet       = {}
    storage.upsteppers              = {}
    storage.upstepper_outputs       = {}
    storage.removers                = {}
    storage.remover_outputs         = {}
    storage.detectors               = {}
    storage.detector_outputs        = {}
    storage.quality_readers         = {}
    storage.quality_reader_outputs  = {}
    storage.multiplexers            = {}
    storage.multiplexer_outputs     = {}
    storage.modulators              = {}
    storage.modulator_outputs       = {}
    storage.modulator_mode          = {}
    storage.modulator_steps         = {}
    storage.modulator_player_entity = {}
    storage.storage_readers         = {}
    storage.storage_reader_outputs  = {}
    storage.readers                 = {}
    storage.reader_outputs          = {}
    storage.gates                   = {}
    storage.gate_outputs            = {}
    storage.gate_quality            = {}
    storage.gate_mode               = {}
    storage.gate_player_entity      = {}
    storage.entity_keys             = {}
end)

script.on_configuration_changed(function()
    storage.consoles                = storage.consoles                or {}
    storage.plh_active_planet       = storage.plh_active_planet       or {}
    storage.upsteppers              = storage.upsteppers              or {}
    storage.upstepper_outputs       = storage.upstepper_outputs       or {}
    storage.removers                = storage.removers                or {}
    storage.remover_outputs         = storage.remover_outputs         or {}
    storage.detectors               = storage.detectors               or {}
    storage.detector_outputs        = storage.detector_outputs        or {}
    storage.quality_readers         = storage.quality_readers         or {}
    storage.quality_reader_outputs  = storage.quality_reader_outputs  or {}
    storage.multiplexers            = storage.multiplexers            or {}
    storage.multiplexer_outputs     = storage.multiplexer_outputs     or {}
    storage.modulators              = storage.modulators              or {}
    storage.modulator_outputs       = storage.modulator_outputs       or {}
    storage.modulator_mode          = storage.modulator_mode          or {}
    storage.modulator_steps         = storage.modulator_steps         or {}
    storage.modulator_player_entity = storage.modulator_player_entity or {}
    storage.storage_readers         = storage.storage_readers         or {}
    storage.storage_reader_outputs  = storage.storage_reader_outputs  or {}
    storage.readers                 = storage.readers                 or {}
    storage.reader_outputs          = storage.reader_outputs          or {}
    storage.gates                   = storage.gates                   or {}
    storage.gate_outputs            = storage.gate_outputs            or {}
    storage.gate_quality            = storage.gate_quality            or {}
    storage.gate_mode               = storage.gate_mode               or {}
    storage.gate_player_entity      = storage.gate_player_entity      or {}
    storage.entity_keys             = {}   -- clear change-detection cache; rescan re-writes all filters
    producer_cache                  = nil  -- rebuild from updated prototypes
    rescan_surfaces()
end)


local function on_built(event)
    on_console_built(event)
    on_detector_built(event)
    on_upstepper_built(event)
    on_remover_built(event)
    on_quality_reader_built(event)
    on_multiplexer_built(event)
    on_modulator_built(event)
    on_storage_reader_built(event)
    on_reader_built(event)
    on_gate_built(event)
end

local function on_removed(event)
    on_console_removed(event)
    on_detector_removed(event)
    on_upstepper_removed(event)
    on_remover_removed(event)
    on_quality_reader_removed(event)
    on_multiplexer_removed(event)
    on_modulator_removed(event)
    on_storage_reader_removed(event)
    on_reader_removed(event)
    on_gate_removed(event)
end

-- Engine-level name filters: Factorio skips the Lua callback entirely for
-- entities not in this list, eliminating the biggest UPS leak in busy games.
local PLH_ENTITY_FILTERS = {}
for _, n in ipairs({
    DRIVER_NAME, DETECTOR_NAME, UPSTEPPER_NAME, REMOVER_NAME,
    QUALITY_READER_NAME, MULTIPLEXER_NAME, MODULATOR_NAME,
    STORAGE_READER_NAME, READER_NAME, GATE_NAME,
}) do
    PLH_ENTITY_FILTERS[#PLH_ENTITY_FILTERS + 1] = {filter = "name", name = n}
end

-- script_raised_* events do not support entity-name filters; keep manual check.
script.on_event(defines.events.on_built_entity,                on_built,   PLH_ENTITY_FILTERS)
script.on_event(defines.events.on_robot_built_entity,          on_built,   PLH_ENTITY_FILTERS)
script.on_event(defines.events.on_space_platform_built_entity, on_built,   PLH_ENTITY_FILTERS)
script.on_event(defines.events.script_raised_built,            on_built)
script.on_event(defines.events.script_raised_revive,           on_built)

script.on_event(defines.events.on_player_mined_entity,  on_removed, PLH_ENTITY_FILTERS)
script.on_event(defines.events.on_robot_mined_entity,   on_removed, PLH_ENTITY_FILTERS)
script.on_event(defines.events.on_entity_died,          on_removed, PLH_ENTITY_FILTERS)
script.on_event(defines.events.script_raised_destroy,   on_removed)

script.on_nth_tick(60, function()
    for id, entity in pairs(storage.consoles) do
        if entity and entity.valid then
            update_console(entity)
        else
            storage.consoles[id] = nil
        end
    end
end)

script.on_nth_tick(6, function()
    -- Guard: entity_keys may be absent in saves from before this table was added.
    if not storage.entity_keys then storage.entity_keys = {} end
    for id, entity in pairs(storage.upsteppers) do
        if entity and entity.valid then update_upstepper(entity)
        else storage.upsteppers[id] = nil; storage.upstepper_outputs[id] = nil end
    end
    for id, entity in pairs(storage.removers) do
        if entity and entity.valid then update_remover(entity)
        else storage.removers[id] = nil; storage.remover_outputs[id] = nil end
    end
    for id, entity in pairs(storage.detectors) do
        if entity and entity.valid then update_detector(entity)
        else storage.detectors[id] = nil; storage.detector_outputs[id] = nil end
    end
    for id, entity in pairs(storage.quality_readers) do
        if entity and entity.valid then update_quality_reader(entity)
        else storage.quality_readers[id] = nil; storage.quality_reader_outputs[id] = nil end
    end
    for id, entity in pairs(storage.multiplexers) do
        if entity and entity.valid then update_multiplexer(entity)
        else storage.multiplexers[id] = nil; storage.multiplexer_outputs[id] = nil end
    end
    for id, entity in pairs(storage.modulators) do
        if entity and entity.valid then update_modulator(entity)
        else storage.modulators[id] = nil; storage.modulator_outputs[id] = nil end
    end
    for id, entity in pairs(storage.storage_readers) do
        if entity and entity.valid then update_storage_reader(entity)
        else storage.storage_readers[id] = nil; storage.storage_reader_outputs[id] = nil end
    end
    for id, entity in pairs(storage.readers) do
        if entity and entity.valid then update_recipe_reader(entity)
        else storage.readers[id] = nil; storage.reader_outputs[id] = nil end
    end
    for id, entity in pairs(storage.gates) do
        if entity and entity.valid then update_gate(entity)
        else storage.gates[id] = nil; storage.gate_outputs[id] = nil end
    end
end)
