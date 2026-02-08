-- circuit-network.lua
-- Monitors circuit network signals from constant combinators
-- Uses incremental updates to track combinators without expensive full rescans
-- Exports signal values to Prometheus metrics

local data = {
	inited = false,
	combinators = {},
}

local function rescan()
	data.combinators = {}
	for _, player in pairs(game.players) do
		for _, surface in pairs(game.surfaces) do
			for _, combinator in
				pairs(surface.find_entities_filtered({
					force = player.force,
					type = "constant-combinator",
				}))
			do
				data.combinators[combinator.unit_number] = combinator
			end
		end
	end
	data.inited = true
end

function on_circuit_network_build(event)
	local entity = event.entity or event.created_entity
	if entity and entity.name == "constant-combinator" then
		if data.inited then
			-- Incremental update: add single combinator instead of full rescan
			data.combinators[entity.unit_number] = entity
		else
			-- Not yet initialized, flag for rescan
			data.inited = false
		end
	end
end

function on_circuit_network_destroy(event)
	local entity = event.entity
	if entity and entity.name == "constant-combinator" then
		-- Incremental update: remove single combinator instead of full rescan
		data.combinators[entity.unit_number] = nil
	end
end

function on_circuit_network_init()
	data.inited = false
end

function on_circuit_network_load()
	data.inited = false
end

function on_circuit_network_tick(event)
	if event.tick then
		if not data.inited then
			rescan()
		end

		gauge_circuit_network_monitored:reset()
		gauge_circuit_network_signal:reset()
		local seen = {}
		for unit_number, combinator in pairs(data.combinators) do
			-- Validate entity and clean up invalid references
			if not combinator.valid then
				data.combinators[unit_number] = nil
				goto continue
			end

			-- Deduplicate networks at combinator level to avoid checking both wire types for same network
			local networks_checked = {}
			for _, wire_type in pairs({ defines.wire_connector_id.circuit_red, defines.wire_connector_id.circuit_green }) do
				local network = combinator.get_circuit_network(wire_type)
				if network ~= nil and not seen[network.network_id] and not networks_checked[network.network_id] and network.signals ~= nil then
					-- Mark as checked for both seen (global) and this combinator
					networks_checked[network.network_id] = true
					seen[network.network_id] = true
					local network_id = tostring(network.network_id)
					gauge_circuit_network_monitored:set(
						1,
						{ combinator.force.name, combinator.surface.name, network_id }
					)
					for _, signal in ipairs(network.signals) do
						local quality_name = signal.signal.quality and signal.signal.quality.name or "normal"
						gauge_circuit_network_signal:set(signal.count, {
							combinator.force.name,
							combinator.surface.name,
							network_id,
							signal.signal.name,
							quality_name,
						})
					end
				end
			end
			::continue::
		end
	end
end
