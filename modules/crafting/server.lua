if not lib then return end

local CraftingBenches = {}
local Items = require 'modules.items.server'
local Inventory = require 'modules.inventory.server'
local Grid = require 'modules.inventory.grid'

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
	return (shared.target and bench.zones) and bench.zones[index]?.groups or bench.groups
end

---@param source number
---@param bench table
---@param index number
---@return vector3
local function getCraftingCoords(source, bench, index)
	if not bench.zones and not bench.points then
		return GetEntityCoords(GetPlayerPed(source))
	else
		return shared.target and bench.zones[index]?.coords or bench.points[index]
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

	return Inventory.Snapshot(left)
end)

local TriggerEventHooks = require 'modules.hooks.server'

local function craftingAccess(source, inv, bench, index)
    if not bench then return false end

    local groups = getCraftingGroups(bench, index)
    local coords = getCraftingCoords(source, bench, index)

    return coords and (not groups or server.hasGroup(inv, groups)) and #(GetEntityCoords(GetPlayerPed(source)) - coords) <= 10
end

local function craftCommands(inv, recipe, credits)
    local commands, durability = {}, {}

    for name, needs in pairs(recipe.ingredients) do
        if type(needs) ~= 'number' or needs ~= needs or needs < 0 or needs == math.huge then return end

        local remaining, found = needs, false

        for slot = 1, inv.slots do
            local record = inv.items[slot]
            if record and record.name == name then
                local value = record.metadata.durability
                if needs == 0 then
                    if not value or value > 100 and value > os.time() or value > 0 and value <= 100 then
                        found = true
                        break
                    end
                elseif needs < 1 then
                    local item = Items(name)
                    local available = value and (value > 100 and ((value - os.time()) / ((record.metadata.degrade or item.degrade or 1) * 60)) or value / 100)
                    if available and available >= needs then
                        durability[#durability + 1] = { kind = 'durability', inventory = inv, slot = slot, amount = needs }
                        found = true
                        break
                    end
                else
                    if not Grid.Integer(needs) then return end
                    local count = math.min(remaining, record.count)
                    commands[#commands + 1] = { kind = 'remove', inventory = inv, name = name, count = count, slot = slot }
                    remaining -= count
                    if remaining == 0 then
                        found = true
                        break
                    end
                end
            end
        end
        if not found then return end
    end

    for _, command in ipairs(durability) do commands[#commands + 1] = command end

    for _, command in ipairs(credits) do
        command = table.clone(command)
        command.revision = inv.revision
        commands[#commands + 1] = command
    end

    return commands
end

lib.callback.register('ox_inventory:craftItem', function(source, id, index, recipeId, toSlot, rotated)
    if (type(id) ~= 'string' and not Grid.Integer(id)) or not Grid.Integer(index) or not Grid.Integer(recipeId)
        or (toSlot ~= nil and not Grid.Integer(toSlot)) or (rotated ~= nil and type(rotated) ~= 'boolean') then return false end
    local inv, bench = Inventory(source), CraftingBenches[id]
    if not inv or not craftingAccess(source, inv, bench, index) then return false end
    local recipe = bench.items[recipeId]
    if not recipe then return false end
    local expectedRecipe = table.deepclone(recipe)
    local item = Items(recipe.name)
    if not item then return false end
    local count = type(recipe.count) == 'number' and recipe.count or type(recipe.count) == 'table' and math.random(recipe.count[1], recipe.count[2]) or 1
    if not Grid.Integer(count) then return false end
    local credits, err = Inventory.PrepareItems(inv, item, count, recipe.metadata or {}, toSlot, rotated)
    if not credits then return false, err end
    local commands = craftCommands(inv, recipe, credits)
    if not commands then return false end
    local plan
    plan, err = Inventory.Assess(commands)
    if not plan then return false, err end
    if not lib.callback.await('ox_inventory:startCrafting', source, id, recipeId) then return false end
    if Inventory(source) ~= inv or CraftingBenches[id] ~= bench or not craftingAccess(source, inv, bench, index)
        or not table.matches(bench.items[recipeId], expectedRecipe) then return false end
    commands = craftCommands(inv, recipe, credits)
    if not commands then return false end
    plan, err = Inventory.Assess(commands)
    if not plan then return false, err end
    local hooks <close> = TriggerEventHooks('craftItem', {
        source = source, benchId = id, benchIndex = index, recipe = recipe, toInventory = inv.id, toSlot = toSlot,
    })
    if not hooks.success then return false end
    local success, response = Inventory.Apply(plan)
    if not success then hooks.success = false end
    return success, response
end)
