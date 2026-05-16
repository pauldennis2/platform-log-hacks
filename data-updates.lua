local tech = data.raw["technology"]["aai-signal-transmission"]
if tech then
    table.insert(tech.effects, {type = "unlock-recipe", recipe = "plh-mini-signal-receiver"})
end

local circuit_tech = data.raw["technology"]["circuit-network"]
if circuit_tech then
    table.insert(circuit_tech.effects, {type = "unlock-recipe", recipe = "plh-platform-request-driver"})
end
