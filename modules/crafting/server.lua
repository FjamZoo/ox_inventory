if not lib then return end

local CraftingBenches = {}
local Items = require 'modules.items.server'
local Inventory = require 'modules.inventory.server'

---@param id number | string
---@param data table
local function createCraftingBench(id, data)
	CraftingBenches[id] = {}
	local recipes = data.items

	if recipes then
		for i = 1, #recipes do
			local recipe = recipes[i]
			local item = Items(recipe.name)

			if item then
				recipe.weight = item.weight
                recipe.size = item.size
				recipe.slot = i
			else
				warn(('failed to setup crafting recipe (bench: %s, slot: %s) - item "%s" does not exist'):format(id, i, recipe.name))
			end

			for ingredient, needs in pairs(recipe.ingredients) do
				if needs < 1 then
					item = Items(ingredient)

					if item and not item.durability then
						item.durability = true
					end
				end
			end
		end

		if shared.target then
			data.points = nil
		else
			data.zones = nil
		end

		CraftingBenches[id] = data
	end
end

for id, data in pairs(lib.load('data.crafting') or {}) do createCraftingBench(data.name or id, data) end

---@param bench table
---@param index number
---@return table?
local function getCraftingGroups(bench, index)
	return (shared.target and bench.zones) and bench.zones[index].groups or bench.groups
end

---falls back to player coords if zones and points are both nil
---@param source number
---@param bench table
---@param index number
---@return vector3
local function getCraftingCoords(source, bench, index)
	if not bench.zones and not bench.points then
		return GetEntityCoords(GetPlayerPed(source))
	else
		return shared.target and bench.zones[index].coords or bench.points[index]
	end
end

lib.callback.register('ox_inventory:openCraftingBench', function(source, id, index)
	local left, bench = Inventory(source), CraftingBenches[id]

	if not left then return end

	if bench then
		local groups = getCraftingGroups(bench, index)
		local coords = getCraftingCoords(source, bench, index)

		if not coords then return end

		if groups and not server.hasGroup(left, groups) then return end
		if #(GetEntityCoords(GetPlayerPed(source)) - coords) > 10 then return end

		if left.open and left.open ~= source then
			local inv = Inventory(left.open) --[[@as OxInventory]]

			-- Why would the player inventory open with an invalid target? Can't repro but whatever.
			if inv?.player then
				inv:closeInventory()
			end
		end

		left:openInventory()
	end

	return { label = left.label, type = left.type, slots = left.slots, weight = left.weight, maxWeight = left.maxWeight }
end)

local TriggerEventHooks = require 'modules.hooks.server'
local GetLocks = require 'modules.locks'

lib.callback.register('ox_inventory:craftItem', function(source, id, index, recipeId, toSlot, rotated)
    if not Inventory.Grid.integer(toSlot) or (rotated ~= nil and type(rotated) ~= 'boolean') then return false end
	local left, bench = Inventory(source), CraftingBenches[id]

	if not left then return end

	if bench then
		local groups = getCraftingGroups(bench, index)
		local coords = getCraftingCoords(source, bench, index)

		if groups and not server.hasGroup(left, groups) then return end
		if #(GetEntityCoords(GetPlayerPed(source)) - coords) > 10 then return end

		local recipe = bench.items[recipeId]

		if recipe then
			local tbl, num = {}, 0

			for name in pairs(recipe.ingredients) do
				num += 1
				tbl[num] = name
			end

			local craftedItem = Items(recipe.name)
			local craftCount = (type(recipe.count) == 'number' and recipe.count) or (table.type(recipe.count) == 'array' and math.random(recipe.count[1], recipe.count[2])) or 1

			local items = Inventory.Search(left, 'slots', tbl) or {}
			table.wipe(tbl)

            for name, needs in pairs(recipe.ingredients) do
                local slots = items[name] or items
                local remaining, found = needs, false
                for _, slot in ipairs(slots) do
                    if needs == 0 then
                        if not slot.metadata.durability or slot.metadata.durability > 0 then
                            tbl[slot.slot], found = 0, true
                            break
                        end
                    elseif needs < 1 then
                        local durability = slot.metadata.durability
                        if durability and durability > 100 then
                            local definition = Items(name)
                            durability = (durability - os.time()) * 100 / ((slot.metadata.degrade or definition.degrade) * 60)
                        end
                        if durability and durability >= needs * 100 then
                            tbl[slot.slot], found = needs, true
                            break
                        end
                    else
                        local count = math.min(remaining, slot.count)
                        tbl[slot.slot], remaining = count, remaining - count
                        if remaining == 0 then found = true break end
                    end
                end
                if not found then return false end
            end

            local lockIds = { ('inventory-%s:grid'):format(left.id) }

            for slot in pairs(tbl) do
                lockIds[#lockIds + 1] = ('inventory-%s:slot-%s'):format(left.id, slot)
            end

            local activeSlots <close> = GetLocks(lockIds)

            if not activeSlots then return end

            local ingredientsBefore = table.deepclone(left.items)
			local hooks <close> = TriggerEventHooks('craftItem', {
				source = source,
				benchId = id,
				benchIndex = index,
				recipe = recipe,
				toInventory = left.id,
				toSlot = toSlot,
			})

			if not hooks.success then return false end

			local success = lib.callback.await('ox_inventory:startCrafting', source, id, recipeId)

            if success then
                if Inventory(source) ~= left then hooks.success = false return false end
                -- Slots can change during the progress callback. Never consume a replacement item.
                for slot in pairs(tbl) do
                    if not left.items[slot] or not table.matches(left.items[slot], ingredientsBefore[slot]) then
                        hooks.success = false return false
                    end
                end
                local before = table.deepclone(left.items)
                local simulation = { id = left.id, slots = left.slots, maxWeight = left.maxWeight,
                    items = table.deepclone(left.items), weight = left.weight }
                for slot, count in pairs(tbl) do
                    local entry = simulation.items[slot]
                    local definition = Items(entry.name)
                    if count == 0 then
                        -- Required tools are retained and must remain present through progress.
                    elseif count >= 1 then
                        entry.count = entry.count - count
                        if entry.count <= 0 then simulation.items[slot] = nil end
                    else
                        local durability = entry.metadata.durability or 100
                        if durability > 100 then durability = durability - (entry.metadata.degrade or definition.degrade) * 60 * count
                        else durability = durability - count * 100 end
                        if entry.count > 1 then
                            entry.count = entry.count - 1
                            if not (definition.decay and durability <= 0) then
                                local anchor, orientation = Inventory.Grid.find(simulation, definition)
                                if not anchor then hooks.success = false return false, 'inventory_full' end
                                local split = table.deepclone(entry)
                                split.slot, split.count, split.rotated = anchor, 1, orientation
                                split.metadata.durability = math.max(0, durability)
                                simulation.items[anchor] = split
                            end
                        elseif definition.decay and durability <= 0 then simulation.items[slot] = nil
                        else entry.metadata.durability = math.max(0, durability) end
                    end
                end
                simulation.weight = Inventory.CalculateWeight(simulation.items)
                for _, entry in pairs(simulation.items) do entry.weight = Inventory.SlotWeight(Items(entry.name), entry) end
                local plan, reason = Inventory.PlanAdd(simulation, craftedItem, craftCount, recipe.metadata or {}, toSlot, rotated, true)
                -- Metadata hooks may yield: the transaction only commits against the same state.
                if not plan or not table.matches(left.items, before) or Inventory(source) ~= left
                    or left.slots ~= simulation.slots or left.maxWeight ~= simulation.maxWeight then
                    hooks.success = false return false, reason or 'inventory_full'
                end
                for _, addition in ipairs(plan) do
                    local target = simulation.items[addition.slot]
                    local entry = { name = craftedItem.name, label = craftedItem.label, description = craftedItem.description,
                        stack = craftedItem.stack, close = craftedItem.close, size = craftedItem.size,
                        slot = addition.slot, rotated = addition.rotated, metadata = addition.metadata,
                        count = addition.count + (target and target.count or 0) }
                    entry.weight = Inventory.SlotWeight(craftedItem, entry)
                    simulation.items[addition.slot] = entry
                end
                left.items, left.weight, left.changed = simulation.items, Inventory.CalculateWeight(simulation.items), true
                local updates, seen = {}, {}
                for slot, entry in pairs(left.items) do
                    updates[#updates + 1] = { item = entry, inventory = left.id }; seen[slot] = true
                end
                for slot in pairs(before) do
                    if not seen[slot] then updates[#updates + 1] = { item = { slot = slot }, inventory = left.id } end
                end
                left:syncSlotsWithClients(updates, true)
                if server.syncInventory then server.syncInventory(left) end
            end

			return success
		end
	end
end)
