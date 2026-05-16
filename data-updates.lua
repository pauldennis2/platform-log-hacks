local tech = data.raw["technology"]["aai-signal-transmission"]
if tech then
    table.insert(tech.effects, {type = "unlock-recipe", recipe = "plh-mini-signal-receiver"})
end

local circuit_tech = data.raw["technology"]["circuit-network"]
if circuit_tech then
    table.insert(circuit_tech.effects, {type = "unlock-recipe", recipe = "plh-platform-request-driver"})
    table.insert(circuit_tech.effects, {type = "unlock-recipe", recipe = "plh-quality-upstepper"})
    table.insert(circuit_tech.effects, {type = "unlock-recipe", recipe = "plh-quality-remover"})
    table.insert(circuit_tech.effects, {type = "unlock-recipe", recipe = "plh-type-detector"})
    table.insert(circuit_tech.effects, {type = "unlock-recipe", recipe = "plh-quality-modulator"})
    table.insert(circuit_tech.effects, {type = "unlock-recipe", recipe = "plh-quality-reader"})
    table.insert(circuit_tech.effects, {type = "unlock-recipe", recipe = "plh-quality-multiplexer"})
    table.insert(circuit_tech.effects, {type = "unlock-recipe", recipe = "plh-storage-reader"})
    table.insert(circuit_tech.effects, {type = "unlock-recipe", recipe = "plh-recipe-reader"})
    table.insert(circuit_tech.effects, {type = "unlock-recipe", recipe = "plh-quality-gate"})
    table.insert(circuit_tech.effects, {type = "unlock-recipe", recipe = "plh-type-gate"})
end
