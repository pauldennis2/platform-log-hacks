local Gui = require("scripts.gui")

local PILOT_NAME     = "plh-platform-pilot"
local PRD_NAME       = "plh-platform-request-driver"
local SECTION_PREFIX = "plh-driver-"   -- legacy: old sections had unit_number suffix
local SECTION_GROUP  = "plh-driver"    -- legacy: used for cleanup only
local SECTION_PRD_PREFIX = "plh-prd-"  -- per-PRD sections keyed by unit_number

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

local function build_upstep_clamp_filters(signals, steps)
    steps = steps or 1
    local totals = {}
    for _, sig in ipairs(signals) do
        if sig.signal.type == nil then
            local idx     = QUALITY_INDEX[sig.signal.quality or "normal"] or 1
            local new_idx = math.max(1, math.min(5, idx + steps))
            local bumped  = QUALITY_ORDER[new_idx]
            local key     = sig.signal.name .. "\0" .. bumped
            if totals[key] then
                totals[key].count = totals[key].count + sig.count
            else
                totals[key] = {name = sig.signal.name, quality = bumped, count = sig.count}
            end
        end
    end
    local filters = {}
    for _, entry in pairs(totals) do
        filters[#filters + 1] = {
            value = {type = "item", name = entry.name, quality = entry.quality},
            min   = entry.count,
        }
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

local function build_set_quality_filters(signals, quality)
    local totals = {}
    for _, sig in ipairs(signals) do
        local t   = sig.signal.type or "item"
        local key = t .. "\0" .. sig.signal.name
        if totals[key] then
            totals[key].count = totals[key].count + sig.count
        else
            totals[key] = {type = t, name = sig.signal.name, count = sig.count}
        end
    end
    local filters = {}
    for _, entry in pairs(totals) do
        filters[#filters + 1] = {
            value = {type = entry.type, name = entry.name, quality = quality},
            min   = entry.count,
        }
    end
    return filters
end

local function build_multiplex_filters(signals)
    local totals = {}
    for _, sig in ipairs(signals) do
        local t   = sig.signal.type or "item"
        local key = t .. "\0" .. sig.signal.name
        if totals[key] then
            totals[key].count = totals[key].count + sig.count
        else
            totals[key] = {type = t, name = sig.signal.name, count = sig.count}
        end
    end
    local filters = {}
    for _, entry in pairs(totals) do
        for _, quality in ipairs(QUALITY_ORDER) do
            filters[#filters + 1] = {
                value = {type = entry.type, name = entry.name, quality = quality},
                min   = entry.count,
            }
        end
    end
    return filters
end

local function build_read_quality_filters(signals)
    local totals = {}
    for _, sig in ipairs(signals) do
        local q = sig.signal.quality or "normal"
        totals[q] = (totals[q] or 0) + sig.count
    end
    local filters = {}
    for quality, count in pairs(totals) do
        filters[#filters + 1] = {
            value = {type = "quality", name = quality, quality = "normal"},
            min   = count,
        }
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

local SIGNAL_CATEGORY = {}
for cat, sig_name in pairs(CATEGORY_SIGNAL) do
    SIGNAL_CATEGORY[sig_name] = cat
end

local item_cat_cache      = {}
local item_subgroup_cache = {}

local function get_item_subgroup(name)
    local cached = item_subgroup_cache[name]
    if cached ~= nil then return cached end
    local proto = prototypes.item[name]
    local sg = proto and proto.subgroup and proto.subgroup.name or ""
    item_subgroup_cache[name] = sg
    return sg
end

-- Returns subgroup name for item/asteroid-chunk/virtual/fluid signals; nil for others.
local function get_material_subgroup(sig_type, sig_name)
    if sig_type == nil then
        return get_item_subgroup(sig_name)
    elseif sig_type == "asteroid-chunk" then
        local key = "ac\0" .. sig_name
        local cached = item_subgroup_cache[key]
        if cached ~= nil then return cached end
        local ok, ac_protos = pcall(function() return prototypes["asteroid-chunk"] end)
        local proto = ok and ac_protos and ac_protos[sig_name]
        local sg = proto and proto.subgroup and proto.subgroup.name or ""
        item_subgroup_cache[key] = sg
        return sg
    elseif sig_type == "virtual" then
        local key = "vs\0" .. sig_name
        local cached = item_subgroup_cache[key]
        if cached ~= nil then return cached end
        local proto = prototypes.virtual_signal[sig_name]
        local sg = proto and proto.subgroup and proto.subgroup.name or ""
        item_subgroup_cache[key] = sg
        return sg
    elseif sig_type == "fluid" then
        local key = "fl\0" .. sig_name
        local cached = item_subgroup_cache[key]
        if cached ~= nil then return cached end
        local proto = prototypes.fluid[sig_name]
        local sg = proto and proto.subgroup and proto.subgroup.name or ""
        item_subgroup_cache[key] = sg
        return sg
    end
    return nil  -- space-location, quality, research-progress — pass through unconditionally
end

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

-- ── Quality Modulator ─────────────────────────────────────────────────────────

local MODULATOR_NAME   = "plh-quality-modulator"
local MODULATOR_OUTPUT = "plh-quality-modulator-output"

local function update_modulator(entity)
    local id     = entity.unit_number
    local output = storage.modulator_outputs[id]
    if not (output and output.valid) then return end

    local signals = read_input(entity)
    local mode    = storage.modulator_mode[id]    or "upstep"
    local steps   = storage.modulator_steps[id]   or 1
    local quality = storage.modulator_quality[id] or "normal"
    local key     = signals_key(signals, mode .. steps .. quality)
    if key == storage.entity_keys[id] then return end
    storage.entity_keys[id] = key

    local section = get_output_section(output)
    if not signals then section.filters = {} return end
    if mode == "upstep" then
        section.filters = build_upstep_filters(signals, steps)
    elseif mode == "upstep-clamp" then
        section.filters = build_upstep_clamp_filters(signals, steps)
    elseif mode == "multiplex" then
        section.filters = build_multiplex_filters(signals)
    elseif mode == "set" then
        section.filters = build_set_quality_filters(signals, quality)
    elseif mode == "read-quality" then
        section.filters = build_read_quality_filters(signals)
    else
        section.filters = build_remove_filters(signals)
    end
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
    storage.modulator_quality[entity.unit_number] = nil
    storage.entity_keys[entity.unit_number]       = nil

    for _, player in pairs(game.players) do
        if storage.modulator_player_entity[player.index] == entity.unit_number then
            Gui.close_modulator(player)
        end
    end
end

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
            value = {type = "virtual", name = "signal-A", quality = "normal"},
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

-- ── Recipe Reader (modes: producer / ingredients) ────────────────────────────
-- producer:    outputs the building that produces each input item.
-- ingredients: outputs the ingredient items needed to craft each input item,
--              scaled by the input signal count.

local READER_NAME   = "plh-recipe-reader"
local READER_OUTPUT = "plh-recipe-reader-output"

-- Module-level caches; rebuilt lazily from prototypes, reset on config change.
local producer_cache       = nil
local all_producers_cache  = nil
local best_producer_cache  = nil
local ingredient_cache     = nil

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

local function get_all_producers_cache()
    if all_producers_cache then return all_producers_cache end

    -- category → set of all player-buildable machines that handle it
    local category_machines = {}
    for _, entity in pairs(prototypes.entity) do
        local etype = entity.type
        if etype == "assembling-machine" or etype == "furnace" or etype == "rocket-silo" then
            if prototypes.item[entity.name] then
                for cat in pairs(entity.crafting_categories or {}) do
                    if not category_machines[cat] then category_machines[cat] = {} end
                    category_machines[cat][entity.name] = true
                end
            end
        end
    end

    -- item → set of all machines that can produce it (across all recipes)
    all_producers_cache = {}
    for _, recipe in pairs(prototypes.recipe) do
        local cat = recipe.category or "crafting"
        if cat ~= "recycling" then
            local machines = category_machines[cat]
            if machines then
                for _, product in pairs(recipe.products or {}) do
                    if product.type == "item" then
                        if not all_producers_cache[product.name] then
                            all_producers_cache[product.name] = {}
                        end
                        for machine_name in pairs(machines) do
                            all_producers_cache[product.name][machine_name] = true
                        end
                    end
                end
            end
        end
    end

    return all_producers_cache
end

local function build_all_producers_filters(signals)
    local cache         = get_all_producers_cache()
    local machine_counts = {}
    for _, sig in ipairs(signals) do
        if sig.signal.type == nil then
            local machines = cache[sig.signal.name]
            if machines then
                for machine_name in pairs(machines) do
                    machine_counts[machine_name] = (machine_counts[machine_name] or 0) + sig.count
                end
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
    return filters
end

local function get_best_producer_cache()
    if best_producer_cache then return best_producer_cache end

    -- category → fastest player-buildable machine (by crafting_speed)
    local category_best = {}
    for _, entity in pairs(prototypes.entity) do
        local etype = entity.type
        if etype == "assembling-machine" or etype == "furnace" or etype == "rocket-silo" then
            if prototypes.item[entity.name] then
                local ok, speed = pcall(function() return entity.get_crafting_speed() end)
                if ok and type(speed) == "number" then
                    for cat in pairs(entity.crafting_categories or {}) do
                        local cur = category_best[cat]
                        if not cur or speed > cur.speed then
                            category_best[cat] = {name = entity.name, speed = speed}
                        end
                    end
                end
            end
        end
    end

    -- item → single fastest machine across all non-recycling recipes that produce it
    local item_best = {}
    for _, recipe in pairs(prototypes.recipe) do
        local cat = recipe.category or "crafting"
        if cat ~= "recycling" then
            local best = category_best[cat]
            if best then
                for _, product in pairs(recipe.products or {}) do
                    if product.type == "item" then
                        local cur = item_best[product.name]
                        if not cur or best.speed > cur.speed then
                            item_best[product.name] = best
                        end
                    end
                end
            end
        end
    end

    best_producer_cache = {}
    for item_name, best in pairs(item_best) do
        best_producer_cache[item_name] = best.name
    end

    return best_producer_cache
end

local function build_best_producer_filters(signals)
    local cache = get_best_producer_cache()
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
    return filters
end

local function get_ingredient_cache()
    if ingredient_cache then return ingredient_cache end
    ingredient_cache = {}
    for _, recipe in pairs(prototypes.recipe) do
        local cat = recipe.category or "crafting"
        if cat ~= "recycling" then
            for _, product in pairs(recipe.products or {}) do
                if product.type == "item" and not ingredient_cache[product.name] then
                    local ings = {}
                    for _, ing in pairs(recipe.ingredients or {}) do
                        if ing.type == "item" then
                            ings[#ings + 1] = {name = ing.name, amount = ing.amount or 1}
                        end
                    end
                    if #ings > 0 then
                        ingredient_cache[product.name] = {
                            ingredients = ings,
                            yield       = product.amount or 1,
                        }
                    end
                end
            end
        end
    end
    return ingredient_cache
end

local function build_ingredients_filters(signals)
    local cache  = get_ingredient_cache()
    local totals = {}
    for _, sig in ipairs(signals) do
        if sig.signal.type == nil then
            local data = cache[sig.signal.name]
            if data then
                local crafts = math.ceil(sig.count / data.yield)
                for _, ing in ipairs(data.ingredients) do
                    totals[ing.name] = (totals[ing.name] or 0) + crafts * ing.amount
                end
            end
        end
    end
    local filters = {}
    for name, count in pairs(totals) do
        filters[#filters + 1] = {
            value = {type = "item", name = name, quality = "normal"},
            min   = count,
        }
    end
    return filters
end

local function update_recipe_reader(entity)
    local id     = entity.unit_number
    local output = storage.reader_outputs[id]
    if not (output and output.valid) then return end

    local signals = read_input(entity)
    local mode    = storage.reader_mode[id] or "producer"
    local key     = signals_key(signals, mode)
    if key == storage.entity_keys[id] then return end
    storage.entity_keys[id] = key

    local section = get_output_section(output)
    if not signals then section.filters = {} return end

    if mode == "ingredients" then
        section.filters = build_ingredients_filters(signals)
        return
    elseif mode == "all-producers" then
        section.filters = build_all_producers_filters(signals)
        return
    elseif mode == "best-producer" then
        section.filters = build_best_producer_filters(signals)
        return
    end

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
    storage.readers[entity.unit_number]             = nil
    storage.reader_outputs[entity.unit_number]      = nil
    storage.reader_mode[entity.unit_number]         = nil
    storage.entity_keys[entity.unit_number]         = nil

    for _, player in pairs(game.players) do
        if storage.reader_player_entity[player.index] == entity.unit_number then
            Gui.close_reader(player)
        end
    end
end

-- ── Type Gate ─────────────────────────────────────────────────────────────────

local TYPE_GATE_NAME   = "plh-type-gate"
local TYPE_GATE_OUTPUT = "plh-type-gate-output"

local function update_type_gate(entity)
    local id     = entity.unit_number
    local output = storage.type_gate_outputs[id]
    if not (output and output.valid) then return end

    local signals  = read_input(entity)
    local type_sel = storage.type_gate_type[id] or "intermediate"
    local mode     = storage.type_gate_mode[id] or "allow"
    local key      = signals_key(signals, mode .. type_sel)
    if key == storage.entity_keys[id] then return end
    storage.entity_keys[id] = key

    local section = get_output_section(output)
    if not signals then section.filters = {} return end

    local filters = {}

    if mode == "signal" then
        local allowed_types = {}
        for _, sig in ipairs(signals) do
            if sig.signal.type == "virtual" and sig.count > 0 then
                local cat = SIGNAL_CATEGORY[sig.signal.name]
                if cat then allowed_types[cat] = true end
            end
        end
        for _, sig in ipairs(signals) do
            if sig.signal.type == nil then
                if allowed_types[categorize(sig.signal.name)] then
                    filters[#filters + 1] = {
                        value = {type = "item", name = sig.signal.name, quality = sig.signal.quality or "normal"},
                        min   = sig.count,
                    }
                end
            else
                filters[#filters + 1] = {
                    value = {type = sig.signal.type, name = sig.signal.name, quality = sig.signal.quality or "normal"},
                    min   = sig.count,
                }
            end
        end
    else
        for _, sig in ipairs(signals) do
            if sig.signal.type == nil then
                local matches = categorize(sig.signal.name) == type_sel
                if (mode == "allow") == matches then
                    filters[#filters + 1] = {
                        value = {type = "item", name = sig.signal.name, quality = sig.signal.quality or "normal"},
                        min   = sig.count,
                    }
                end
            else
                -- non-item signals (virtual, space-location, fluid, etc.) pass through unconditionally
                filters[#filters + 1] = {
                    value = {type = sig.signal.type, name = sig.signal.name, quality = sig.signal.quality or "normal"},
                    min   = sig.count,
                }
            end
        end
    end

    section.filters = filters
end

local function on_type_gate_built(event)
    local entity = event.entity or event.created_entity
    if not (entity and entity.valid and entity.name == TYPE_GATE_NAME) then return end

    local output = entity.surface.create_entity({
        name        = TYPE_GATE_OUTPUT,
        position    = entity.position,
        force       = entity.force,
        raise_built = false,
    })
    if not output then return end

    wire_companion(entity, output)
    init_output(output)
    storage.type_gates[entity.unit_number]        = entity
    storage.type_gate_outputs[entity.unit_number] = output
end

local function on_type_gate_removed(event)
    local entity = event.entity
    if not (entity and entity.name == TYPE_GATE_NAME) then return end

    local output = storage.type_gate_outputs[entity.unit_number]
    if output and output.valid then output.destroy() end
    storage.type_gates[entity.unit_number]        = nil
    storage.type_gate_outputs[entity.unit_number] = nil
    storage.type_gate_type[entity.unit_number]    = nil
    storage.type_gate_mode[entity.unit_number]    = nil
    storage.entity_keys[entity.unit_number]       = nil

    for _, player in pairs(game.players) do
        if storage.type_gate_player_entity[player.index] == entity.unit_number then
            Gui.close_type_gate(player)
        end
    end
end

-- ── Subtype Gate ──────────────────────────────────────────────────────────────

local SUBTYPE_GATE_NAME   = "plh-subtype-gate"
local SUBTYPE_GATE_OUTPUT = "plh-subtype-gate-output"

local function update_subtype_gate(entity)
    local id     = entity.unit_number
    local output = storage.subtype_gate_outputs[id]
    if not (output and output.valid) then return end

    local signals  = read_input(entity)
    local subgroup = storage.subtype_gate_subgroup[id] or ""
    local mode     = storage.subtype_gate_mode[id] or "allow"
    local key      = signals_key(signals, mode .. subgroup)
    if key == storage.entity_keys[id] then return end
    storage.entity_keys[id] = key

    local section = get_output_section(output)
    if not signals then section.filters = {} return end

    local filters = {}
    for _, sig in ipairs(signals) do
        local sg = get_material_subgroup(sig.signal.type, sig.signal.name)
        if sg ~= nil then
            local matches = sg == subgroup
            if (mode == "allow") == matches then
                filters[#filters + 1] = {
                    value = {type = sig.signal.type or "item", name = sig.signal.name, quality = sig.signal.quality or "normal"},
                    min   = sig.count,
                }
            end
        else
            -- virtual, space-location, quality, fluid — pass through unconditionally
            filters[#filters + 1] = {
                value = {type = sig.signal.type, name = sig.signal.name, quality = sig.signal.quality or "normal"},
                min   = sig.count,
            }
        end
    end

    section.filters = filters
end

local function on_subtype_gate_built(event)
    local entity = event.entity or event.created_entity
    if not (entity and entity.valid and entity.name == SUBTYPE_GATE_NAME) then return end

    local output = entity.surface.create_entity({
        name        = SUBTYPE_GATE_OUTPUT,
        position    = entity.position,
        force       = entity.force,
        raise_built = false,
    })
    if not output then return end

    wire_companion(entity, output)
    init_output(output)
    storage.subtype_gates[entity.unit_number]        = entity
    storage.subtype_gate_outputs[entity.unit_number] = output
end

local function on_subtype_gate_removed(event)
    local entity = event.entity
    if not (entity and entity.name == SUBTYPE_GATE_NAME) then return end

    local output = storage.subtype_gate_outputs[entity.unit_number]
    if output and output.valid then output.destroy() end
    storage.subtype_gates[entity.unit_number]           = nil
    storage.subtype_gate_outputs[entity.unit_number]    = nil
    storage.subtype_gate_subgroup[entity.unit_number]   = nil
    storage.subtype_gate_mode[entity.unit_number]       = nil
    storage.entity_keys[entity.unit_number]             = nil

    for _, player in pairs(game.players) do
        if storage.subtype_gate_player_entity[player.index] == entity.unit_number then
            Gui.close_subtype_gate(player)
        end
    end
end

-- ── Subtype Spreader ──────────────────────────────────────────────────────────

local SUBTYPE_SPREADER_NAME   = "plh-subtype-spreader"
local PLH_SPREADER_GROUP      = "plh-spreader"
local subtype_spreader_cache  = {}  -- subgroup_name → list of {type, name}

local function get_subgroup_items(subgroup)
    if subtype_spreader_cache[subgroup] then return subtype_spreader_cache[subgroup] end
    local items = {}
    for name, proto in pairs(prototypes.item) do
        if proto.subgroup and proto.subgroup.name == subgroup then
            items[#items + 1] = {type = "item", name = name}
        end
    end
    local ok, ac_protos = pcall(function() return prototypes["asteroid-chunk"] end)
    if ok and ac_protos then
        for name, proto in pairs(ac_protos) do
            if proto.subgroup and proto.subgroup.name == subgroup then
                items[#items + 1] = {type = "asteroid-chunk", name = name}
            end
        end
    end
    for name, proto in pairs(prototypes.virtual_signal) do
        if proto.subgroup and proto.subgroup.name == subgroup then
            items[#items + 1] = {type = "virtual", name = name}
        end
    end
    for name, proto in pairs(prototypes.fluid) do
        if proto.subgroup and proto.subgroup.name == subgroup then
            items[#items + 1] = {type = "fluid", name = name}
        end
    end
    table.sort(items, function(a, b)
        if a.type ~= b.type then return a.type < b.type end
        return a.name < b.name
    end)
    subtype_spreader_cache[subgroup] = items
    return items
end

local function update_subtype_spreader(entity)
    local id       = entity.unit_number
    local subgroup = storage.subtype_spreader_subgroup[id] or ""
    if subgroup == storage.entity_keys[id] then return end
    storage.entity_keys[id] = subgroup

    local behavior = entity.get_or_create_control_behavior()
    behavior.enabled = true

    -- Remove all existing plh-spreader sections
    local i = 1
    while i <= behavior.sections_count do
        local s = behavior.get_section(i)
        if s and s.group == PLH_SPREADER_GROUP then
            behavior.remove_section(i)
        else
            i = i + 1
        end
    end

    if subgroup == "" then return end

    local items = get_subgroup_items(subgroup)
    if #items == 0 then return end

    -- Write items in chunks of 1000 (section filter limit)
    local CHUNK = 1000
    for offset = 0, #items - 1, CHUNK do
        local s = behavior.add_section(PLH_SPREADER_GROUP)
        s.active = true
        local filters = {}
        for j = 1, math.min(CHUNK, #items - offset) do
            local item = items[offset + j]
            filters[j] = {
                value = {type = item.type, name = item.name, quality = "normal"},
                min   = 1,
            }
        end
        s.filters = filters
    end
end

local function on_subtype_spreader_built(event)
    local entity = event.entity or event.created_entity
    if not (entity and entity.valid and entity.name == SUBTYPE_SPREADER_NAME) then return end
    storage.subtype_spreaders[entity.unit_number] = entity
    local behavior = entity.get_or_create_control_behavior()
    behavior.enabled = true
end

local function on_subtype_spreader_removed(event)
    local entity = event.entity
    if not (entity and entity.name == SUBTYPE_SPREADER_NAME) then return end
    storage.subtype_spreaders[entity.unit_number]          = nil
    storage.subtype_spreader_subgroup[entity.unit_number]  = nil
    storage.entity_keys[entity.unit_number]                = nil

    for _, player in pairs(game.players) do
        if storage.subtype_spreader_player_entity[player.index] == entity.unit_number then
            Gui.close_subtype_spreader(player)
        end
    end
end

-- ── Platform Request Driver ───────────────────────────────────────────────────

local function get_or_create_section(lp)
    local i = 1
    while true do
        local s = lp.get_section(i)
        if not s then break end
        if s.group == SECTION_GROUP then return s end
        -- Migrate legacy numbered section: remove it (filters rewritten next tick)
        if s.group:sub(1, #SECTION_PREFIX) == SECTION_PREFIX then
            lp.remove_section(i)
        else
            i = i + 1
        end
    end
    return lp.add_section(SECTION_GROUP)
end

local function remove_section(lp)
    local i = 1
    while true do
        local s = lp.get_section(i)
        if not s then break end
        if s.group == SECTION_GROUP or s.group:sub(1, #SECTION_PREFIX) == SECTION_PREFIX then
            lp.remove_section(i)
        else
            i = i + 1
        end
    end
end

local function get_or_create_prd_section(lp, unit_number)
    local group = SECTION_PRD_PREFIX .. unit_number
    local i = 1
    while true do
        local s = lp.get_section(i)
        if not s then break end
        if s.group == group then return s end
        i = i + 1
    end
    return lp.add_section(group)
end

local function remove_prd_section(lp, unit_number)
    local group = SECTION_PRD_PREFIX .. unit_number
    local i = 1
    while true do
        local s = lp.get_section(i)
        if not s then break end
        if s.group == group then lp.remove_section(i); return end
        i = i + 1
    end
end

-- old_stops / new_stops are ordered lists of planet name strings
local function set_platform_interrupt(platform, old_stops, new_stops)
    local schedule = platform.schedule
    if not schedule then
        if not new_stops then return end
        schedule = {records = {}, current = 1}
    end
    local records = schedule.records

    if old_stops then
        for _, planet in ipairs(old_stops) do
            for i = #records, 1, -1 do
                if records[i].station == planet and records[i].temporary then
                    table.remove(records, i)
                    break
                end
            end
        end
    end

    if new_stops then
        -- Insert in reverse order so final schedule order matches new_stops
        for i = #new_stops, 1, -1 do
            table.insert(records, 1, {
                station         = new_stops[i],
                temporary       = true,
                wait_conditions = {{type = "time", compare_type = "and", ticks = settings.global["plh-prd-wait-time"].value * 60}},
            })
        end
    end

    if #records == 0 then platform.schedule = nil; return end
    schedule.current = math.max(1, math.min(schedule.current or 1, #records))
    platform.schedule = schedule
end

local function routes_equal(a, b)
    if not a or not b then return a == b end
    if #a ~= #b then return false end
    for i, v in ipairs(a) do
        if v ~= b[i] then return false end
    end
    return true
end

local function update_pilot(entity)
    local platform = entity.surface.platform
    if not platform then return end

    local function clear()
        local old = storage.plh_active_planet[entity.unit_number]
        if old then
            storage.plh_active_planet[entity.unit_number] = nil
            set_platform_interrupt(platform, old, nil)
        end
    end

    if not entity.power_switch_state then clear() return end

    -- Both wires: collect space-location signals, dedup by planet (lower value wins), sort ascending
    local seen = {}
    local function collect(net)
        if not net then return end
        for _, sig in pairs(net.signals or {}) do
            if sig.signal.type == "space-location" then
                local n = sig.signal.name
                if not seen[n] or sig.count < seen[n] then seen[n] = sig.count end
            end
        end
    end
    collect(entity.get_circuit_network(defines.wire_connector_id.circuit_red))
    collect(entity.get_circuit_network(defines.wire_connector_id.circuit_green))
    local raw = {}
    for name, order in pairs(seen) do raw[#raw + 1] = {name = name, order = order} end

    if #raw == 0 then clear() return end

    table.sort(raw, function(a, b) return a.order < b.order end)
    local new_route = {}
    for _, s in ipairs(raw) do new_route[#new_route + 1] = s.name end

    local old_route = storage.plh_active_planet[entity.unit_number]
    if not routes_equal(old_route, new_route) then
        storage.plh_active_planet[entity.unit_number] = new_route
        set_platform_interrupt(platform, old_route, new_route)
    end
end

local function update_prd(entity)
    local platform = entity.surface.platform
    if not platform then return end
    local hub = platform.hub
    if not (hub and hub.valid) then return end
    local lp = hub.get_logistic_point(defines.logistic_member_index.space_platform_hub_requester)
    if not lp then return end
    local section = get_or_create_prd_section(lp, entity.unit_number)
    if not section then return end

    local source_planet = nil
    local new_filters = {}
    local red_net = entity.get_circuit_network(defines.wire_connector_id.circuit_red)
    if red_net then
        for _, sig in pairs(red_net.signals or {}) do
            if sig.signal.type == "space-location" and not source_planet then
                source_planet = sig.signal.name
            elseif sig.signal.type == nil and sig.count > 0 then
                new_filters[#new_filters + 1] = sig
            end
        end
    end

    if not source_planet or not next(new_filters) then
        section.filters = {}
        return
    end

    local filters = {}
    for i, sig in ipairs(new_filters) do
        filters[i] = {
            value = {
                type    = "item",
                name    = sig.signal.name,
                quality = sig.signal.quality or "normal",
            },
            min         = sig.count,
            import_from = source_planet,
        }
    end
    section.filters = filters
end

local function make_platform_reject(event, entity, item_name)
    return function(msg)
        local player = event.player_index and game.players[event.player_index]
        if not player then
            for _, p in pairs(game.players) do
                if p.valid and p.surface == entity.surface then player = p; break end
            end
        end
        local platform = entity.surface.platform
        if platform then
            local hub = platform.hub
            if hub and hub.valid then hub.insert({name = item_name, count = 1}) end
        elseif player then
            local cursor = player.cursor_stack
            if cursor and not cursor.valid_for_read then
                cursor.set_stack({name = item_name, count = 1})
            elseif cursor and cursor.valid_for_read and cursor.name == item_name then
                cursor.count = cursor.count + 1
            else
                player.insert({name = item_name, count = 1})
            end
        else
            entity.surface.spill_item_stack({position = entity.position, stack = {name = item_name, count = 1}, enable_looted = true})
        end
        if player and msg then player.print(msg) end
        entity.destroy()
    end
end

local function on_pilot_built(event)
    local entity = event.entity or event.created_entity
    if not (entity and entity.valid and entity.name == PILOT_NAME) then return end
    local reject = make_platform_reject(event, entity, PILOT_NAME)
    if not entity.surface.platform then reject(); return end
    local existing = entity.surface.find_entities_filtered({name = PILOT_NAME, limit = 2})
    if #existing > 1 then reject("Only one Platform Pilot is allowed per platform."); return end
    storage.pilots[entity.unit_number] = entity
end

local function on_pilot_removed(event)
    local entity = event.entity
    if not (entity and entity.name == PILOT_NAME) then return end
    local old_route = storage.plh_active_planet[entity.unit_number]
    storage.plh_active_planet[entity.unit_number] = nil
    storage.pilots[entity.unit_number] = nil
    local platform = entity.surface.platform
    if not platform then return end
    if old_route then set_platform_interrupt(platform, old_route, nil) end
end

local function on_prd_built(event)
    local entity = event.entity or event.created_entity
    if not (entity and entity.valid and entity.name == PRD_NAME) then return end
    local reject = make_platform_reject(event, entity, PRD_NAME)
    if not entity.surface.platform then reject(); return end
    storage.prd_entities[entity.unit_number] = entity
end

local function on_prd_removed(event)
    local entity = event.entity
    if not (entity and entity.name == PRD_NAME) then return end
    storage.prd_entities[entity.unit_number] = nil
    local platform = entity.surface.platform
    if not platform then return end
    local hub = platform.hub
    if not (hub and hub.valid) then return end
    local lp = hub.get_logistic_point(defines.logistic_member_index.space_platform_hub_requester)
    if lp then remove_prd_section(lp, entity.unit_number) end
end

-- ── Surface rescan ───────────────────────────────────────────────────────────
-- Finds every tracked entity on all surfaces and ensures it is registered and
-- has a valid output companion. Called on_configuration_changed so entities
-- placed in previous sessions are never silently lost.

local function rescan_surfaces()
    local specs = {
        {DETECTOR_NAME,       DETECTOR_OUTPUT,       storage.detectors,       storage.detector_outputs},

        {MODULATOR_NAME,      MODULATOR_OUTPUT,      storage.modulators,      storage.modulator_outputs},
        {STORAGE_READER_NAME, STORAGE_READER_OUTPUT, storage.storage_readers, storage.storage_reader_outputs},
        {READER_NAME,         READER_OUTPUT,         storage.readers,         storage.reader_outputs},
        {TYPE_GATE_NAME,      TYPE_GATE_OUTPUT,      storage.type_gates,      storage.type_gate_outputs},
        {SUBTYPE_GATE_NAME,   SUBTYPE_GATE_OUTPUT,   storage.subtype_gates,   storage.subtype_gate_outputs},
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

local register_compaktcircuit  -- forward declaration; defined in the CC block below

script.on_init(function()
    storage.pilots                  = {}
    storage.prd_entities            = {}
    storage.plh_active_planet       = {}
    storage.detectors               = {}
    storage.detector_outputs        = {}

    storage.modulators              = {}
    storage.modulator_outputs       = {}
    storage.modulator_mode          = {}
    storage.modulator_steps         = {}
    storage.modulator_quality       = {}
    storage.modulator_player_entity = {}
    storage.storage_readers         = {}
    storage.storage_reader_outputs  = {}
    storage.readers                 = {}
    storage.reader_outputs          = {}
    storage.reader_mode             = {}
    storage.reader_player_entity    = {}
    storage.type_gates                 = {}
    storage.type_gate_outputs          = {}
    storage.type_gate_type             = {}
    storage.type_gate_mode             = {}
    storage.type_gate_player_entity    = {}
    storage.subtype_gates                 = {}
    storage.subtype_gate_outputs          = {}
    storage.subtype_gate_subgroup         = {}
    storage.subtype_gate_mode             = {}
    storage.subtype_gate_player_entity    = {}
    storage.subtype_spreaders             = {}
    storage.subtype_spreader_subgroup     = {}
    storage.subtype_spreader_player_entity= {}
    storage.entity_keys                   = {}
    register_compaktcircuit()
end)

script.on_load(function()
    register_compaktcircuit()
end)

script.on_configuration_changed(function()
    storage.pilots                  = storage.pilots                  or {}
    storage.prd_entities            = storage.prd_entities            or {}
    storage.plh_active_planet       = {}  -- reset on upgrade
    storage.detectors               = storage.detectors               or {}
    storage.detector_outputs        = storage.detector_outputs        or {}

    storage.modulators              = storage.modulators              or {}
    storage.modulator_outputs       = storage.modulator_outputs       or {}
    storage.modulator_mode          = storage.modulator_mode          or {}
    storage.modulator_steps         = storage.modulator_steps         or {}
    storage.modulator_quality       = storage.modulator_quality       or {}
    storage.modulator_player_entity = storage.modulator_player_entity or {}
    storage.storage_readers         = storage.storage_readers         or {}
    storage.storage_reader_outputs  = storage.storage_reader_outputs  or {}
    storage.readers                 = storage.readers                 or {}
    storage.reader_outputs          = storage.reader_outputs          or {}
    storage.reader_mode             = storage.reader_mode             or {}
    storage.reader_player_entity    = storage.reader_player_entity    or {}
    storage.type_gates                 = storage.type_gates                 or {}
    storage.type_gate_outputs          = storage.type_gate_outputs          or {}
    storage.type_gate_type             = storage.type_gate_type             or {}
    storage.type_gate_mode             = storage.type_gate_mode             or {}
    storage.type_gate_player_entity    = storage.type_gate_player_entity    or {}
    storage.subtype_gates                  = storage.subtype_gates                  or {}
    storage.subtype_gate_outputs           = storage.subtype_gate_outputs           or {}
    storage.subtype_gate_subgroup          = storage.subtype_gate_subgroup          or {}
    storage.subtype_gate_mode              = storage.subtype_gate_mode              or {}
    storage.subtype_gate_player_entity     = storage.subtype_gate_player_entity     or {}
    storage.subtype_spreaders              = storage.subtype_spreaders              or {}
    storage.subtype_spreader_subgroup      = storage.subtype_spreader_subgroup      or {}
    storage.subtype_spreader_player_entity = storage.subtype_spreader_player_entity or {}
    storage.entity_keys                    = {}   -- clear change-detection cache; rescan re-writes all filters
    producer_cache                     = nil  -- rebuild from updated prototypes
    all_producers_cache                = nil
    best_producer_cache                = nil
    ingredient_cache                   = nil
    item_subgroup_cache                = {}
    subtype_spreader_cache             = {}
    rescan_surfaces()
    -- Re-register spreaders and refresh their output (no companion pattern)
    for _, surface in pairs(game.surfaces) do
        for _, entity in ipairs(surface.find_entities_filtered({name = SUBTYPE_SPREADER_NAME})) do
            storage.subtype_spreaders[entity.unit_number] = entity
            update_subtype_spreader(entity)
        end
        -- Re-register pilots and PRDs
        for _, entity in ipairs(surface.find_entities_filtered({name = PILOT_NAME})) do
            storage.pilots[entity.unit_number] = entity
        end
        for _, entity in ipairs(surface.find_entities_filtered({name = PRD_NAME})) do
            storage.prd_entities[entity.unit_number] = entity
        end
        -- Remove legacy "plh-driver" hub sections (requests now handled by Platform Request Driver)
        for _, hub in ipairs(surface.find_entities_filtered({name = "space-platform-hub"})) do
            local lp = hub.get_logistic_point(defines.logistic_member_index.space_platform_hub_requester)
            if lp then remove_section(lp) end
        end
    end
    register_compaktcircuit()
end)


-- ── Compact Circuits integration ──────────────────────────────────────────────

local function get_entity_state(entity)
    local id   = entity.unit_number
    local name = entity.name
    if name == MODULATOR_NAME then
        return {mode = storage.modulator_mode[id], steps = storage.modulator_steps[id], quality = storage.modulator_quality[id]}
    elseif name == READER_NAME then
        return {reader_mode = storage.reader_mode[id]}
    elseif name == TYPE_GATE_NAME then
        return {gate_mode = storage.type_gate_mode[id], gate_type = storage.type_gate_type[id]}
    elseif name == SUBTYPE_GATE_NAME then
        return {gate_mode = storage.subtype_gate_mode[id], subgroup = storage.subtype_gate_subgroup[id]}
    elseif name == SUBTYPE_SPREADER_NAME then
        return {subgroup = storage.subtype_spreader_subgroup[id]}
    end
    return {}
end

local function restore_entity_state(entity, info)
    local id   = entity.unit_number
    local name = entity.name
    if name == MODULATOR_NAME then
        if info.mode    then storage.modulator_mode[id]    = info.mode    end
        if info.steps   then storage.modulator_steps[id]   = info.steps   end
        if info.quality then storage.modulator_quality[id] = info.quality end
    elseif name == READER_NAME then
        if info.reader_mode then storage.reader_mode[id] = info.reader_mode end
    elseif name == TYPE_GATE_NAME then
        if info.gate_mode then storage.type_gate_mode[id] = info.gate_mode end
        if info.gate_type then storage.type_gate_type[id] = info.gate_type end
    elseif name == SUBTYPE_GATE_NAME then
        if info.gate_mode then storage.subtype_gate_mode[id]    = info.gate_mode end
        if info.subgroup  then storage.subtype_gate_subgroup[id] = info.subgroup  end
    elseif name == SUBTYPE_SPREADER_NAME then
        if info.subgroup  then storage.subtype_spreader_subgroup[id] = info.subgroup end
    end
end

local function plh_create_entity(info, surface, position, force)
    local entity = surface.create_entity({
        name      = info.name,
        position  = position or info.position,
        direction = info.direction,
        force     = force,
    })
    -- on_built fires synchronously above and sets defaults; overwrite with saved state.
    if entity and entity.valid then
        restore_entity_state(entity, info)
    end
    return entity
end

if script.active_mods["compaktcircuit"] then
    remote.add_interface("platform-log-hacks", {
        get_info             = get_entity_state,
        create_packed_entity = function(info, surface, pos, force)
            return plh_create_entity(info, surface, pos, force)
        end,
        create_entity        = function(info, surface, force)
            return plh_create_entity(info, surface, nil, force)
        end,
    })
end

register_compaktcircuit = function()
    if not script.active_mods["compaktcircuit"] then return end
    for _, name in ipairs({
        PILOT_NAME, PRD_NAME, DETECTOR_NAME, MODULATOR_NAME,
        STORAGE_READER_NAME, READER_NAME, TYPE_GATE_NAME,
        SUBTYPE_GATE_NAME, SUBTYPE_SPREADER_NAME,
    }) do
        remote.call("compaktcircuit", "add_combinator", {
            name           = name,
            interface_name = "platform-log-hacks",
        })
    end
end

local function on_built(event)
    on_pilot_built(event)
    on_prd_built(event)
    on_detector_built(event)

    on_modulator_built(event)
    on_storage_reader_built(event)
    on_reader_built(event)
    on_type_gate_built(event)
    on_subtype_gate_built(event)
    on_subtype_spreader_built(event)
    -- Blueprint placement: individual handlers set defaults above; overwrite with saved tags.
    local built_entity = event.entity or event.created_entity
    if event.tags and built_entity and built_entity.valid then
        restore_entity_state(built_entity, event.tags)
    end
end

local function on_removed(event)
    on_pilot_removed(event)
    on_prd_removed(event)
    on_detector_removed(event)

    on_modulator_removed(event)
    on_storage_reader_removed(event)
    on_reader_removed(event)
    on_type_gate_removed(event)
    on_subtype_gate_removed(event)
    on_subtype_spreader_removed(event)
end

-- Engine-level name filters: Factorio skips the Lua callback entirely for
-- entities not in this list, eliminating the biggest UPS leak in busy games.
local PLH_ENTITY_FILTERS = {}
for _, n in ipairs({
    PILOT_NAME, PRD_NAME, DETECTOR_NAME, MODULATOR_NAME,
    STORAGE_READER_NAME, READER_NAME, TYPE_GATE_NAME, SUBTYPE_GATE_NAME, SUBTYPE_SPREADER_NAME,
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

script.on_event(defines.events.on_player_setup_blueprint, function(event)
    if not event.mapping.valid then return end
    local map = event.mapping.get()   -- table<entity_number, LuaEntity>

    local player = game.players[event.player_index]
    local bp = player.blueprint_to_setup
    if not (bp and bp.valid_for_read) then
        local cs = player.cursor_stack
        if cs and cs.valid_for_read and cs.is_blueprint then bp = cs end
    end
    if not (bp and bp.valid_for_read) then return end

    local entities = bp.get_blueprint_entities()
    if not entities then return end

    for _, bp_entity in pairs(entities) do
        local id     = bp_entity.entity_number
        local entity = map[id]
        if entity and entity.valid then
            local state = get_entity_state(entity)
            if next(state) then
                bp.set_blueprint_entity_tags(id, state)
            end
        end
    end
end)

script.on_nth_tick(60, function()
    for id, entity in pairs(storage.pilots) do
        if entity and entity.valid then
            update_pilot(entity)
        else
            storage.pilots[id] = nil
        end
    end
    for id, entity in pairs(storage.prd_entities) do
        if entity and entity.valid then
            update_prd(entity)
        else
            storage.prd_entities[id] = nil
        end
    end
end)

script.on_nth_tick(6, function()
    -- Guard: tables may be absent in saves from before they were added.
    if not storage.entity_keys       then storage.entity_keys       = {} end
    if not storage.modulator_quality then storage.modulator_quality = {} end
    for id, entity in pairs(storage.detectors) do
        if entity and entity.valid then update_detector(entity)
        else storage.detectors[id] = nil; storage.detector_outputs[id] = nil end
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
    for id, entity in pairs(storage.type_gates) do
        if entity and entity.valid then update_type_gate(entity)
        else storage.type_gates[id] = nil; storage.type_gate_outputs[id] = nil end
    end
    for id, entity in pairs(storage.subtype_gates) do
        if entity and entity.valid then update_subtype_gate(entity)
        else storage.subtype_gates[id] = nil; storage.subtype_gate_outputs[id] = nil end
    end
    for id, entity in pairs(storage.subtype_spreaders) do
        if entity and entity.valid then update_subtype_spreader(entity)
        else storage.subtype_spreaders[id] = nil end
    end
end)
