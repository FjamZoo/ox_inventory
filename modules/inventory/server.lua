if not lib then return end

local Inventory = {}
local Grid = require 'modules.inventory.grid'

---@type table<any, OxInventory>
local Inventories = {}

---@class OxInventory
---@field grid {columns: integer, cells: integer}
---@field recovery {id: string, reason: 'unknown_item'|'invalid_record'|'no_space', record: any}[]
---@field revision integer
---@field storageBusy? boolean
---@field removeAfterStorage? boolean
---@field unknownWeight boolean
local OxInventory = {}
OxInventory.__index = OxInventory

---Open a player's inventory, optionally with a secondary inventory.
---@param inv? inventory
function OxInventory:openInventory(inv)
	if not self?.player then return end

	inv = inv and inv ~= self and Inventory(inv) or nil --[[@as OxInventory? ]]
	self.open = inv?.id or self.id

    if inv then
        inv:set('open', true)
        inv.openedBy[self.id] = true
    end

    TriggerEvent('ox_inventory:openedInventory', self.id, inv?.id)
end

---Close a player's inventory.
---@param noEvent? boolean
function OxInventory:closeInventory(noEvent)
	if not self.player or not self.open then return end

	local inv = self.open ~= self.id and Inventory(self.open)

    if inv then
        inv.openedBy[self.id] = nil
        inv:set('open', false)
    end

    self.open = false
    self.currentShop = nil
    self.containerSlot = nil

	if not noEvent then
		TriggerClientEvent('ox_inventory:closeInventory', self.id, true)
	end

	TriggerEvent('ox_inventory:closedInventory', self.id, inv?.id)
end

---@alias updateSlot { item: SlotWithItem | { slot: number }, inventory: string|number }

---Sync a player's inventory state.
---@param slots updateSlot[]
---@param weight { left?: number, right?: number } | number
function OxInventory:syncSlotsWithPlayer(slots, weight)
	TriggerClientEvent('ox_inventory:updateSlots', self.id, slots, weight)
end

---Sync an inventory's state with all player's accessing it.
---@param slots updateSlot[]
---@param syncOwner? boolean
---@param weaponSlot? number | false
function OxInventory:syncSlotsWithClients(slots, syncOwner, weaponSlot)
	for playerId in pairs(self.openedBy) do
		if self.id ~= playerId then
            local target = Inventories[playerId]

            if target then
			    TriggerClientEvent('ox_inventory:updateSlots', playerId, slots, target.weight)
            end
		end
	end

	if syncOwner and self.player then
		TriggerClientEvent('ox_inventory:updateSlots', self.id, slots, self.weight, weaponSlot)
	end
end

local Vehicles = lib.load('data.vehicles')
local RegisteredStashes = {}

for _, stash in pairs(lib.load('data.stashes') or {}) do
	RegisteredStashes[stash.name] = {
		name = stash.name,
		label = stash.label,
		owner = stash.owner,
		slots = stash.slots,
		maxWeight = stash.weight,
		groups = stash.groups or stash.jobs,
		coords = shared.target and stash.target?.loc or stash.coords,
        distance = stash.distance or 10
	}
end

local GetVehicleNumberPlateText = GetVehicleNumberPlateText

---@class OpenInventoryData
---@field id string | number
---@field owner? string | number | boolean
---@field type? string
---@field entityId? number
---@field [string] unknown

---Atempts to lazily load inventory data from the database or create a new player-owned instance for "personal" stashes
---@param data OpenInventoryData
---@param player OxInventory
---@param ignoreSecurityChecks boolean
---@return OxInventory | false | nil
local function loadInventoryData(data, player, ignoreSecurityChecks)
	local source = source
	local inventory

	if not data.type and type(data.id) == 'string' then
		if data.id:find('^glove') then
			data.type = 'glovebox'
		elseif data.id:find('^trunk') then
			data.type = 'trunk'
		elseif data.id:find('^evidence-') then
			data.type = 'policeevidence'
		end
	end

	if data.type == 'trunk' or data.type == 'glovebox' then
		local plate = data.id:sub(6)

		if server.trimplate then
			plate = string.strtrim(plate)
			data.id = ('%s%s'):format(data.id:sub(1, 5), plate)
		end

		inventory = Inventories[data.id]

		if not inventory then
			local entity

			if data.netid then
				entity = NetworkGetEntityFromNetworkId(data.netid)

				if not entity then
					return shared.info('Failed to load vehicle inventory data (no entity exists with given netid).')
				end

                data.entityId = entity
			else
				local vehicles = GetAllVehicles()

				for i = 1, #vehicles do
					local vehicle = vehicles[i]
					local _plate = GetVehicleNumberPlateText(vehicle)

					if _plate:find(plate) then
						entity = vehicle
                        data.entityId = entity
						data.netid = NetworkGetNetworkIdFromEntity(entity)
						break
					end
				end

				if not entity then
					return shared.info('Failed to load vehicle inventory data (no entity exists with given plate).')
				end
			end

			if not source then
				source = NetworkGetEntityOwner(entity)

				if not source then
					return shared.info('Failed to load vehicle inventory data (entity is unowned).')
				end
			end

			local model, class = lib.callback.await('ox_inventory:getVehicleData', source, data.netid)
			local storage = Vehicles[data.type].models[model] or Vehicles[data.type][class]
            local dbId

            if server.getOwnedVehicleId then
                dbId = server.getOwnedVehicleId(entity)
            else
                dbId = data.id:sub(6)
            end

            inventory = Inventory.Create(data.id, plate, data.type, storage[1], 0, storage[2], false, nil, nil, dbId)
		end
	elseif data.type == 'policeevidence' then
		inventory = Inventory.Create(data.id, locale('police_evidence'), data.type, 100, 0, 100000, false)
	else
		local stash = RegisteredStashes[data.id]

		if stash then
			if stash.jobs then stash.groups = stash.jobs end
			if not ignoreSecurityChecks and player and stash.groups and not server.hasGroup(player, stash.groups) then return end

			local owner

			if stash.owner then
				if stash.owner == true then
					owner = data.owner or player?.owner
				else
					owner = stash.owner
				end
			end

			inventory = Inventories[owner and ('%s:%s'):format(stash.name, owner) or stash.name]

			if not inventory then
				inventory = Inventory.Create(stash.name, stash.label or stash.name, 'stash', stash.slots, 0, stash.maxWeight, owner, nil, stash.groups)
                inventory.coords = stash.coords
                inventory.distance = stash.distance
                inventory.instance = stash.instance
			end
		end
	end

	if data.netid then
        inventory.entityId = data.entityId or NetworkGetEntityFromNetworkId(data.netid)
		inventory.netid = data.netid
	end

	return inventory or false
end

setmetatable(Inventory, {
	__call = function(self, inv, player, ignoreSecurityChecks)
        if Inventory.Lock then return false end

		if not inv then
			return self
		elseif type(inv) == 'table' then
			if inv.__index then return inv end

			return not inv.owner and Inventories[inv.id] or loadInventoryData(inv, player, ignoreSecurityChecks)
		end

		return Inventories[inv] or loadInventoryData({ id = inv }, player, ignoreSecurityChecks)
	end
})

---@cast Inventory +fun(inv: inventory, player?: inventory, ignoreSecurityChecks?: boolean): OxInventory|false|nil

---@param inv inventory
---@param owner? string | number
local function getInventory(inv, owner)
	if not inv then return Inventory end

	local type = type(inv)

	if type == 'table' or type == 'number' then
		return Inventory(inv)
	else
		return Inventory({ id = inv, owner = owner })
	end
end

exports('Inventory', getInventory)
exports('GetInventory', getInventory)

---@param invType string
---@param detailed? boolean return the full inventory instead of only the id
---@return (string|number)[] | OxInventory[]
function Inventory.GetInventories(invType, detailed)
	if type(invType) ~= 'string' then
		return error(('expected invType to be a string (received %s)'):format(type(invType)))
	end

	local returnData = {}

	for _, inv in pairs(Inventories) do
		if inv.type == invType then
			returnData[#returnData + 1] = detailed and inv or inv.id
		end
	end

	return returnData
end

exports('GetInventories', Inventory.GetInventories)

---@param inv inventory
---@param owner? string | number
---@return table?
exports('GetInventoryItems', function(inv, owner)
	return getInventory(inv, owner)?.items
end)

---@param inv inventory
---@param slotId number
---@return OxInventory?
function Inventory.GetContainerFromSlot(inv, slotId)
	local inventory = Inventory(inv)
	local slotData = inventory and inventory.items[slotId]

	if not slotData then return end

	local container = Inventory(slotData.metadata.container)

	if not container then
		container = Inventory.Create(slotData.metadata.container, slotData.label, 'container', slotData.metadata.size[1], 0, slotData.metadata.size[2], false)
	end

	return container
end

exports('GetContainerFromSlot', Inventory.GetContainerFromSlot)

---@param inv? inventory
---@param ignoreId? number|false
function Inventory.CloseAll(inv, ignoreId)
	if not inv then
		for _, data in pairs(Inventories) do
			for playerId in pairs(data.openedBy) do
				local playerInv = Inventory(playerId)

				if playerInv then playerInv:closeInventory(true) end
			end
		end

		return TriggerClientEvent('ox_inventory:closeInventory', -1, true)
	end

	local inventory = Inventory(inv) --[[@as OxInventory?]]

	if not inventory then return end

	for playerId in pairs(inv.openedBy) do
		local playerInv = Inventory(playerId)

		if playerInv and playerId ~= ignoreId then
            playerInv:closeInventory()
        end
	end
end

---@param inv inventory
---@param k string
---@param v any
function Inventory.Set(inv, k, v)
	inv = Inventory(inv) --[[@as OxInventory]]

	if inv and not inv.storageBusy then
		if type(v) == 'number' then
			v = math.floor(v + 0.5)
		end

		if k == 'open' and v == false then
			if inv.type ~= 'player' then
				if inv.player then
					inv.type = 'player'
				elseif inv.type == 'drop' and not next(inv.items) and not next(inv.recovery) and not next(inv.openedBy) then
					return Inventory.Remove(inv)
				else
					inv.time = os.time()
				end
			end

			if inv.player then
				inv.containerSlot = nil
			end
		elseif k == 'maxWeight' and v < 1000 then
			v *= 1000
		end

		if k == 'slots' then return Inventory.SetSlotCount(inv, v) end
        if k == 'maxWeight' then return Inventory.SetMaxWeight(inv, v) end
        inv[k] = v
        inv.revision = (inv.revision or 0) + 1
	end
end

---@param inv inventory
---@param key string
function Inventory.Get(inv, key)
	inv = Inventory(inv) --[[@as OxInventory]]
	if inv then
		return inv[key]
	end
end

---@class MinimalInventorySlot
---@field name string
---@field count number
---@field slot number
---@field metadata? table
---@field rotated? boolean

---@param items table<number, SlotWithItem>
---@param recovery table[]
---@return table[]
local function serialize(items, recovery)
	local inventory, count = {}, 0
	for k, v in pairs(items) do
		if v.name and v.count > 0 then
			count += 1
			inventory[count] = {
				name = v.name,
				count = v.count,
				slot = k,
				metadata = next(v.metadata) and v.metadata or nil,
                rotated = v.rotated or nil
			}
		end
	end
	for _, entry in ipairs(recovery or {}) do inventory[#inventory + 1] = { _gridRecovery = table.deepclone(entry) } end
	return inventory
end

local function minimal(inv)
    inv = Inventory(inv)
    return serialize(inv.items, inv.recovery)
end

local Items = require 'modules.items.server'

local function itemDefinition(item)
    if type(item) == 'table' then item = item.name end
    return type(item) == 'string' and Items(item) or nil
end

---@param inv inventory
---@param item table | string
---@param count number
---@param metadata any
---@param slot number
---@return boolean, string | SlotWithItem | nil
function Inventory.SetSlot(inv, item, count, metadata, slot, rotated)
    inv = Inventory(inv)
    item = itemDefinition(item)
    if not inv then return false, 'invalid_inventory' end
    if not item then return false, 'invalid_item' end
    if not Grid.Integer(count, -math.huge) or not Grid.Integer(slot) or (rotated ~= nil and type(rotated) ~= 'boolean') then return false, 'invalid_count' end
    local current = inv.items[slot]
    local newCount = (current and current.count or 0) + count
    if current and current.name ~= item.name then return false, 'occupied_slot' end
    local record = newCount > 0 and {
        name = item.name,
        count = newCount,
        metadata = metadata or {},
        slot = slot,
        rotated = rotated == nil and current and current.rotated or rotated
    } or nil

    local plan, err = Inventory.Assess({ { kind = 'set', inventory = inv, slot = slot, record = record, acquiring = count > 0 } })
    if not plan then return false, err end
    local success, response = Inventory.Apply(plan)
    if not success then return false, response end
    TriggerClientEvent('ox_inventory:itemNotify', inv.id, { inv.items[slot] or current, count < 0 and 'ui_removed' or 'ui_added', math.abs(count) })
    return true, inv.items[slot]
end

CreateThread(function()
    Inventory.accounts = server.accounts
    TriggerEvent('ox_inventory:loadInventory', Inventory)
end)

---@param inv inventory
function Inventory.GetAccountItemCounts(inv)
    local inventory = Inventory(inv)

    if not inventory then return end

    local accounts = table.clone(server.accounts)

	for _, v in pairs(inventory.items) do
		if accounts[v.name] then
			accounts[v.name] += v.count
		end
	end

    return accounts
end

---@param item table
---@param slot table
function Inventory.SlotWeight(item, slot, ignoreCount)
	local weight = ignoreCount and item.weight or item.weight * (slot.count or 1)

	if not slot.metadata then slot.metadata = {} end

	if item.ammoname and slot.metadata.ammo then
		local ammoWeight = Items(item.ammoname)?.weight

		if ammoWeight then
			weight += (ammoWeight * slot.metadata.ammo)
		end
	end

    if item.hash == `WEAPON_PETROLCAN` then
        slot.metadata.weight = 15000 * (slot.metadata.ammo / 100)
    end

	if slot.metadata.components then
		for i = #slot.metadata.components, 1, -1 do
			local componentWeight = Items(slot.metadata.components[i])?.weight

			if componentWeight then
				weight += componentWeight
			end
		end
	end

	if slot.metadata.weight then
		weight += ignoreCount and slot.metadata.weight or (slot.metadata.weight * (slot.count or 1))
	end

	return weight
end

---@param items table
function Inventory.CalculateWeight(items)
	local weight = 0
	for _, v in pairs(items) do
		local item = Items(v.name)
		if item then
			weight = weight + Inventory.SlotWeight(item, v)
		end
	end
	return weight
end

local function slotRecord(record, slot, allowNonStackCount)
    if type(record) ~= 'table' or type(record.name) ~= 'string' or not Grid.Integer(record.count) or (record.metadata ~= nil and type(record.metadata) ~= 'table') or (record.rotated ~= nil and type(record.rotated) ~= 'boolean') then return nil, 'invalid_record' end
    local item = Items(record.name)
    if not item then return nil, 'unknown_item' end
    if not allowNonStackCount and not item.stack and record.count ~= 1 then return nil, 'invalid_record' end
    local result = {
        name = item.name,
        label = item.label,
        count = record.count,
        slot = slot or record.slot,
        description = item.description,
        stack = item.stack,
        close = item.close,
        metadata = table.deepclone(record.metadata or {}),
        rotated = record.rotated or nil,
    }
    local ok, weight = pcall(Inventory.SlotWeight, item, result)
    if not ok or type(weight) ~= 'number' or weight ~= weight or weight < 0 or weight == math.huge then return nil, 'invalid_record' end
    result.weight = weight
    return result
end

local function recoveryWeight(recovery)
    local weight, unknown = 0, false
    for i = 1, #recovery do
        local record = slotRecord(recovery[i].record, nil, true)
        if record then
            weight += record.weight
        else
            unknown = true
        end
    end
    return weight, unknown
end

function Inventory.Reconcile(records, slots)
    if type(records) == 'string' then
        local ok, decoded = pcall(json.decode, records)
        if not ok or type(decoded) ~= 'table' then error('Refusing to load malformed inventory JSON', 2) end
        records = decoded
    end
    if records ~= nil and type(records) ~= 'table' then error('Refusing to load malformed inventory data', 2) end
    local grid, items, recovery, pending, ordered, usedIds, seenIds = { columns = 5, cells = slots }, {}, {}, {}, {}, {}, {}
    local migrated = false
    local function validEnvelope(value)
        return type(value) == 'table' and type(value.id) == 'string' and value.id ~= '' and value.record ~= nil
            and (value.reason == 'unknown_item' or value.reason == 'invalid_record' or value.reason == 'no_space')
    end
    for key, record in pairs(records or {}) do ordered[#ordered + 1] = { key = key, record = record } end
    table.sort(ordered, function(a, b)
        local aSlot = type(a.record) == 'table' and a.record.slot
        local bSlot = type(b.record) == 'table' and b.record.slot
        aSlot, bSlot = Grid.Integer(aSlot) and aSlot or math.huge, Grid.Integer(bSlot) and bSlot or math.huge
        if aSlot ~= bSlot then return aSlot < bSlot end
        if type(a.key) == 'number' and type(b.key) == 'number' then return a.key < b.key end
        return tostring(a.key) < tostring(b.key)
    end)
    for i = 1, #ordered do
        local envelope = type(ordered[i].record) == 'table' and ordered[i].record._gridRecovery
        if validEnvelope(envelope) then usedIds[envelope.id] = true end
    end
    local nextId = 0
    local function recoveryId()
        repeat nextId += 1 until not usedIds['recovery-' .. nextId]
        local id = 'recovery-' .. nextId
        usedIds[id] = true
        return id
    end
    local function preserve(record, reason)
        migrated = true
        recovery[#recovery + 1] = { id = recoveryId(), reason = reason, record = table.deepclone(record) }
    end
    local occupied = {}
    local function place(record, anchor)
        record.slot = anchor
        items[anchor] = record
        for _, cell in ipairs(Grid.Cells(grid, Items(record.name).size, anchor, record.rotated)) do occupied[cell] = anchor end
    end
    for i = 1, #ordered do
        local original = ordered[i].record
        local envelope = type(original) == 'table' and original._gridRecovery
        if validEnvelope(envelope) then
            local entry = table.deepclone(envelope)
            if seenIds[envelope.id] then
                entry.id = recoveryId()
                migrated = true
            end
            seenIds[envelope.id] = true
            recovery[#recovery + 1] = entry
        else
            local record, reason = slotRecord(original)
            if record and not Grid.Integer(record.slot) then record, reason = nil, 'invalid_record' end
            if record then
                local ok, metadata = pcall(Items.CheckMetadata, record.metadata, Items(record.name), record.name, os.time())
                if ok then
                    if not table.matches(record.metadata, metadata) then migrated = true end
                    record.metadata = metadata
                    record = slotRecord(record)
                else
                    record, reason = nil, 'invalid_record'
                end
            end
            if not record then
                preserve(original, reason)
            elseif Grid.Fits(grid, occupied, Items(record.name).size, record.slot, record.rotated) then
                place(record, record.slot)
            else
                migrated = true
                pending[#pending + 1] = { record = record, original = original }
            end
        end
    end
    for i = 1, #pending do
        local entry = pending[i]
        local record, size = entry.record, Items(entry.record.name).size
        local anchor = Grid.FirstFit(grid, occupied, size, record.rotated)
        if not anchor then
            anchor = Grid.FirstFit(grid, occupied, size, not record.rotated)
            if anchor then record.rotated = not record.rotated or nil end
        end
        if anchor then
            place(record, anchor)
        else
            preserve(entry.original, 'no_space')
        end
    end
    local weight, unknown = recoveryWeight(recovery)
    return items, Inventory.CalculateWeight(items) + weight, recovery, unknown, migrated
end

function Inventory.Snapshot(inv)
    return {
        id = inv.id,
        label = inv.label,
        type = inv.type,
        slots = inv.slots,
        items = inv.items,
        grid = inv.grid,
        recovery = inv.recovery,
        weight = inv.weight,
        maxWeight = inv.maxWeight
    }
end

local function syncSnapshot(inv)
    local snapshot = Inventory.Snapshot(inv)
    if inv.player then TriggerClientEvent('ox_inventory:syncInventory', inv.id, snapshot) end
    for id in pairs(inv.openedBy) do
        if id ~= inv.id then TriggerClientEvent('ox_inventory:syncInventory', id, snapshot) end
    end
end

local function addRecord(state, record, anchor, rotated)
    record = slotRecord(record)
    if not record then return nil, 'invalid_item' end
    local item = Items(record.name)
    if rotated ~= nil then record.rotated = rotated or nil end
    if anchor ~= nil and not Grid.Integer(anchor) then return nil, 'invalid_slot' end
    if not anchor and item.stack then
        for i = 1, state.slots do
            local target = state.items[i]
            if target and target.name == record.name and table.matches(target.metadata, record.metadata) then
                anchor = i
                break
            end
        end
    end
    local target = anchor and state.items[anchor]
    if target then
        if not item.stack or target.name ~= record.name or not table.matches(target.metadata, record.metadata) then return nil, 'occupied_slot' end
        target.count += record.count
        return anchor
    end
    local occupied = Grid.Occupancy(state.grid, state.items, Items)
    if not occupied then return nil, 'invalid_grid' end
    anchor = anchor or Grid.FirstFit(state.grid, occupied, item.size, record.rotated)
    if not anchor or not Grid.Fits(state.grid, occupied, item.size, anchor, record.rotated) then return nil, 'inventory_full' end
    record.slot = anchor
    state.items[anchor] = record
    return anchor
end

---@param commands table[]
---@return table? plan, string? error
function Inventory.Assess(commands)
    local plan = { states = {}, results = {}, stock = {}, containers = {}, pending = {} }
    local function stateFor(value)
        local inv = Inventory(value)
        if not inv or inv.storageBusy then return end
        if not plan.states[inv] then
            plan.states[inv] = {
                inventory = inv,
                revision = inv.revision or 0,
                weapon = inv.weapon,
                items = table.deepclone(inv.items),
                recovery = table.deepclone(inv.recovery or {}),
                slots = inv.slots,
                grid = { columns = 5, cells = inv.slots }
            }
        end
        return plan.states[inv]
    end
    for i = 1, #commands do
        local command = commands[i]
        local state = stateFor(command.inventory or command.from)
        if not state then return nil, 'invalid_inventory' end
        if command.revision and state.revision ~= command.revision then return nil, 'stale_inventory' end
        if command.kind == 'add' then
            local slot, err = addRecord(state, command.record, command.slot, command.rotated)
            if not slot then return nil, err end
            state.acquiring = true
            plan.results[#plan.results + 1] = { inventory = state.inventory, slot = slot }
        elseif command.kind == 'remove' then
            local remaining = command.count
            if not Grid.Integer(remaining, 0) then return nil, 'invalid_count' end
            for slot = 1, state.slots do
                local record = state.items[slot]
                if remaining > 0 and record and (not command.slot or slot == command.slot) and record.name == command.name and (not command.metadata or (command.strict == false and table.contains or table.matches)(record.metadata, command.metadata)) then
                    local count = math.min(remaining, record.count)
                    record.count -= count
                    remaining -= count
                    if record.count == 0 then
                        state.items[slot] = nil
                        if state.weapon == slot then state.weapon = nil end
                    end
                end
            end
            if remaining > 0 then return nil, 'not_enough_items' end
        elseif command.kind == 'set' then
            if not Grid.Integer(command.slot) then return nil, 'invalid_slot' end
            local record, err = command.record and slotRecord(command.record, command.slot)
            if command.record and not record then return nil, err end
            if state.weapon == command.slot and (not record or record.name ~= state.items[command.slot].name) then state.weapon = nil end
            state.items[command.slot] = record or nil
            state.acquiring = state.acquiring or command.acquiring
        elseif command.kind == 'transfer' then
            local target = stateFor(command.to)
            if not target then return nil, 'invalid_inventory' end
            local from = state.items[command.fromSlot]
            if not from or not Grid.Integer(command.count) or command.count > from.count then return nil, 'invalid_count' end
            if not Grid.Integer(command.toSlot) then return nil, 'invalid_slot' end
            local destination = target.items[command.toSlot]
            local exchanging = destination and (command.swap or destination.name ~= from.name or not destination.stack or not table.matches(destination.metadata, from.metadata))
            local wholeItem = command.count == from.count
            if state == target and command.fromSlot == command.toSlot then
                if command.count ~= from.count then return nil, 'invalid_count' end
                if command.rotated ~= nil then from.rotated = command.rotated or nil end
            elseif exchanging then
                if command.count ~= from.count then return nil, 'invalid_count' end
                state.items[command.fromSlot], target.items[command.toSlot] = nil, nil
                destination.slot, from.slot = command.fromSlot, command.toSlot
                if command.rotated ~= nil then from.rotated = command.rotated or nil end
                state.items[command.fromSlot], target.items[command.toSlot] = destination, from
            else
                local moving = table.deepclone(from)
                moving.count = command.count
                from.count -= command.count
                if from.count == 0 then state.items[command.fromSlot] = nil end
                local slot, err = addRecord(target, moving, command.toSlot, command.rotated)
                if not slot then return nil, err end
            end
            if state == target then
                if state.weapon == command.fromSlot and wholeItem then
                    state.weapon = command.toSlot
                elseif state.weapon == command.toSlot and exchanging then
                    state.weapon = command.fromSlot
                end
            else
                if state.weapon == command.fromSlot and wholeItem then state.weapon = nil end
                if target.weapon == command.toSlot and exchanging then target.weapon = nil end
                target.acquiring = true
                if exchanging then state.acquiring = true end
            end
        elseif command.kind == 'durability' then
            local record = state.items[command.slot]
            if not record then return nil, 'not_enough_items' end
            local item = Items(record.name)
            local value = record.metadata.durability
            if type(value) ~= 'number' or value <= 0 then return nil, 'not_enough_durability' end
            local durability = value > 100 and value - (record.metadata.degrade or item.degrade or 0) * 60 * command.amount or value - command.amount * 100
            if (value > 100 and durability < os.time()) or (value <= 100 and durability < 0) then return nil, 'not_enough_durability' end
            if record.count > 1 then
                record.count -= 1
                local split = table.deepclone(record)
                split.count = 1
                split.metadata.durability = durability
                if durability > 0 or not item.decay then plan.pending[#plan.pending + 1] = { state = state, record = split } end
            elseif durability <= 0 and item.decay then
                state.items[command.slot] = nil
                if state.weapon == command.slot then state.weapon = nil end
            else
                record.metadata.durability = durability
            end
        elseif command.kind == 'resize' or command.kind == 'replace' then
            if command.slots and not Grid.Integer(command.slots, 0) then return nil, 'invalid_slots' end
            state.slots = command.slots or state.slots
            state.grid.cells = state.slots
            local records = command.records
            if not records then
                records = {}
                for _, record in pairs(state.items) do records[#records + 1] = record end
                for _, entry in ipairs(state.recovery) do records[#records + 1] = { _gridRecovery = entry } end
            end
            state.items, state.weight, state.recovery = Inventory.Reconcile(records, state.slots)
            state.weapon = nil
            state.restore = true
        elseif command.kind == 'recover' then
            local found
            for index, entry in ipairs(state.recovery) do
                if entry.id == command.id then
                    local record = slotRecord(entry.record)
                    if not record then return nil, entry.reason end
                    local slot, err = addRecord(state, record, command.slot, command.rotated)
                    if not slot and command.slot == nil and command.rotated == nil then
                        slot, err = addRecord(state, record, nil, not record.rotated)
                    end
                    if not slot then return nil, err end
                    table.remove(state.recovery, index)
                    found = true
                    break
                end
            end
            if not found then return nil, 'invalid_recovery' end
        else
            return nil, 'invalid_operation'
        end
        if command.stock then plan.stock[#plan.stock + 1] = command.stock end
    end
    for _, pending in ipairs(plan.pending) do
        local slot, err = addRecord(pending.state, pending.record)
        if not slot then return nil, err end
    end
    local containers = {}
    for inv, state in pairs(plan.states) do
        if inv.type == 'container' then containers[#containers + 1] = state end
    end
    for _, container in ipairs(containers) do
        for _, parent in pairs(Inventories) do
            for slot, record in pairs(parent.items) do
                if record.metadata.container == container.inventory.id then
                    local state = stateFor(parent)
                    if not state then return nil, 'invalid_inventory' end
                    if state.items[slot]?.metadata.container == container.inventory.id then
                        plan.containers[#plan.containers + 1] = { parent = state, slot = slot, container = container }
                    end
                end
            end
        end
    end
    for inv, state in pairs(plan.states) do
        if not Grid.Occupancy(state.grid, state.items, Items) then return nil, 'inventory_full' end
        local weight, unknown = recoveryWeight(state.recovery)
        state.unknownWeight = unknown
        for slot, record in pairs(state.items) do
            local normalized, err = slotRecord(record, slot)
            if not normalized then return nil, err end
            state.items[slot] = normalized
            weight += normalized.weight
        end
        state.weight = weight
    end
    for _, link in ipairs(plan.containers) do
        local record = link.parent.items[link.slot]
        link.parent.weight -= record.weight
        record.metadata.weight = link.container.weight
        record.weight = Inventory.SlotWeight(Items(record.name), record)
        link.parent.weight += record.weight
    end
    for inv, state in pairs(plan.states) do
        if not state.restore and ((state.weight > inv.maxWeight and state.weight > inv.weight) or (inv.unknownWeight and state.acquiring)) then return nil, 'cannot_carry' end
    end
    return plan
end

function Inventory.Apply(plan)
    if not plan then return false, 'invalid_plan' end
    for inv, state in pairs(plan.states) do
        if Inventories[inv.id] ~= inv or (inv.revision or 0) ~= state.revision or (inv.storageBusy and not plan.storage) then return false, 'stale_inventory' end
    end
    for _, stock in ipairs(plan.stock) do
        if stock.record.count ~= stock.expected or stock.expected < stock.count then return false, 'stale_stock' end
    end
    for inv, state in pairs(plan.states) do
        state.previous = inv.items
        inv.items, inv.recovery, inv.weight, inv.unknownWeight = state.items, state.recovery, state.weight, state.unknownWeight
        inv.slots, inv.grid = state.slots, state.grid
        inv.weapon = state.weapon
        inv.revision, inv.changed = state.revision + 1, true
    end
    for _, stock in ipairs(plan.stock) do stock.record.count -= stock.count end
    for inv, state in pairs(plan.states) do
        local changes = {}
        for slot in pairs(state.previous) do
            if not inv.items[slot] then changes[#changes + 1] = { item = { slot = slot }, inventory = inv.id } end
        end
        for slot, record in pairs(inv.items) do
            if not table.matches(record, state.previous[slot]) then changes[#changes + 1] = { item = record, inventory = inv.id } end
        end
        inv:syncSlotsWithClients(changes, true, inv.weapon or false)
        syncSnapshot(inv)
        if inv.player and server.syncInventory then
            local ok, err = pcall(server.syncInventory, inv)
            if not ok then lib.print.error(('Inventory %s committed but framework synchronization failed: %s'):format(inv.id, err)) end
        end
    end
    return true
end

function Inventory.PrepareItems(inv, item, count, metadata, slot, rotated)
    local commands, revision = {}, inv.revision or 0
    while count > 0 do
        if #commands >= inv.slots then return nil, 'inventory_full' end
        local data, amount = Items.Metadata(inv, item, table.deepclone(metadata or {}), count)
        if not Grid.Integer(amount) or amount > count then return nil, 'invalid_count' end
        commands[#commands + 1] = {
            kind = 'add',
            inventory = inv,
            record = { name = item.name, count = amount, metadata = data },
            slot = #commands == 0 and slot or nil,
            rotated = rotated,
            revision = revision
        }
        count -= amount
    end
    if Inventory(inv.id) ~= inv or (inv.revision or 0) ~= revision then return nil, 'stale_inventory' end
    return commands
end

-- This should be handled by frameworks, but sometimes isn't or is exploitable in some way.
local activeIdentifiers = {}

local function hasActiveInventory(playerId, owner)
	local activePlayer = activeIdentifiers[owner]

	if activePlayer then
        if activePlayer == playerId then
            error('attempted to load active player\'s inventory a secondary time', 0)
        end

		local inventory = Inventory(activePlayer)

		if inventory then
			local endpoint = GetPlayerEndpoint(activePlayer)

			if endpoint then
				DropPlayer(playerId, ("Character identifier '%s' is already active."):format(owner))

                -- Supposedly still getting stuck? Print info and hope somebody reports back (lol)
				print(('kicked player.%s (charid is already in use)'):format(playerId), json.encode({
					oldId = activePlayer,
					newId = playerId,
					charid = owner,
					endpoint = endpoint,
					playerName = GetPlayerName(activePlayer),
					fivem = GetPlayerIdentifierByType(activePlayer, 'fivem'),
					license = GetPlayerIdentifierByType(activePlayer, 'license2') or GetPlayerIdentifierByType(activePlayer, 'license'),
				}, {
					indent = true,
                    sort_keys = true
				}))

				return true
			end

			Inventory.CloseAll(inventory)
			db.savePlayer(owner, json.encode(inventory:minimal()))
			Inventory.Remove(inventory)
			Wait(100)
		end
	end

	activeIdentifiers[owner] = playerId
end

---Manually clear an inventory state tied to the given identifier.
---Temporary workaround until somebody actually gives me info.
RegisterCommand('clearActiveIdentifier', function(source, args)
    ---Server console only.
    if source ~= 0 then return end

	local activePlayer = activeIdentifiers[args[1]] or activeIdentifiers[tonumber(args[1])]
    local inventory = activePlayer and Inventory(activePlayer)

    if not inventory then return end

    local endpoint = GetPlayerEndpoint(activePlayer)

    if endpoint then
        DropPlayer(activePlayer, 'Kicked')

        -- Supposedly still getting stuck? Print info and hope somebody reports back (lol)
        print(('kicked player.%s (clearActiveIdentifier)'):format(activePlayer), json.encode({
            oldId = activePlayer,
            charid = inventory.owner,
            endpoint = endpoint,
            playerName = GetPlayerName(activePlayer),
            fivem = GetPlayerIdentifierByType(activePlayer, 'fivem'),
            license = GetPlayerIdentifierByType(activePlayer, 'license2') or GetPlayerIdentifierByType(activePlayer, 'license'),
        }, {
            indent = true,
            sort_keys = true
        }))
    end

    Inventory.CloseAll(inventory)
    db.savePlayer(inventory.owner, json.encode(inventory:minimal()))
    Inventory.Remove(inventory)
end, true)

---@param id string|number
---@param label string|nil
---@param invType string
---@param slots number
---@param weight number
---@param maxWeight number
---@param owner? string | number | boolean
---@param items? table
---@param dbId? string | number
---@return OxInventory?
--- This should only be utilised internally!
--- To create a stash, please use `exports.ox_inventory:RegisterStash` instead.
function Inventory.Create(id, label, invType, slots, weight, maxWeight, owner, items, groups, dbId)
    if not Grid.Integer(slots, 0) then error('Inventory capacity requires a nonnegative integer') end

	local self = {
		id = id,
		label = label or id,
		type = invType,
		slots = slots,
		weight = weight,
		maxWeight = maxWeight or shared.playerweight,
		owner = owner,
		items = type(items) == 'table' and items,
		open = false,
		set = Inventory.Set,
		get = Inventory.Get,
		minimal = minimal,
		time = os.time(),
		groups = groups,
		openedBy = {},
        dbId = dbId
	}

	if invType == 'drop' or invType == 'temp' or invType == 'dumpster' then
		self.datastore = true
	else
		self.changed = false

		if invType ~= 'glovebox' and invType ~= 'trunk' then
			self.dbId = id

			if invType ~= 'player' and owner and type(owner) ~= 'boolean' then
				self.id = ('%s:%s'):format(self.id, owner)
			end
		end
	end

    if items == nil then items = Inventory.Load(self.dbId, invType, owner) end
    local migrated
    self.items, self.weight, self.recovery, self.unknownWeight, migrated = Inventory.Reconcile(items, slots)
    if migrated and not self.datastore then self.changed = true end
    self.grid = { columns = 5, cells = slots }
    self.revision = 0

    if invType == 'player' and hasActiveInventory(id, owner) then return end
	Inventories[self.id] = setmetatable(self, OxInventory)
	return Inventories[self.id]
end

---@param inv inventory
function Inventory.Remove(inv)
	inv = Inventory(inv) --[[@as OxInventory]]

	if not inv then return end
    if inv.storageBusy then
        inv.removeAfterStorage = true
        return
    end

    if inv.type == 'drop' then
        TriggerClientEvent('ox_inventory:removeDrop', -1, inv.id)
        Inventory.Drops[inv.id] = nil
    elseif inv.player or inv.type == 'player' then
        activeIdentifiers[inv.owner] = nil
    end

    for playerId in pairs(inv.openedBy) do
        if inv.id ~= playerId then
            local target = Inventories[playerId]

            if target then
                target:closeInventory()
            end
        end
    end

    if not inv.datastore and (inv.changed or inv.player) then
        Inventory.Save(inv)
    end

    Inventories[inv.id] = nil
end

exports('RemoveInventory', Inventory.Remove)

---Update the internal reference to vehicle stashes. Does not trigger a save or update the database.
---@param oldPlate string
---@param newPlate string
function Inventory.UpdateVehicle(oldPlate, newPlate)
	oldPlate = oldPlate:upper()
	newPlate = newPlate:upper()

	if server.trimplate then
		oldPlate = string.strtrim(oldPlate)
		newPlate = string.strtrim(newPlate)
	end

	local trunk = Inventory(('trunk%s'):format(oldPlate))
	local glove = Inventory(('glove%s'):format(oldPlate))

	if trunk then
		Inventory.CloseAll(trunk)

		Inventories[trunk.id] = nil
		trunk.label = newPlate
		trunk.dbId = type(trunk.id) == 'number' and trunk.dbId or newPlate
		trunk.id = ('trunk%s'):format(newPlate)
		Inventories[trunk.id] = trunk
	end

	if glove then
		Inventory.CloseAll(glove)

		Inventories[glove.id] = nil
		glove.label = newPlate
		glove.dbId = type(glove.id) == 'number' and glove.dbId or newPlate
		glove.id = ('glove%s'):format(newPlate)
		Inventories[glove.id] = glove
	end
end

exports('UpdateVehicle', Inventory.UpdateVehicle)

function Inventory.Save(inv)
	inv = Inventory(inv) --[[@as OxInventory]]

	if not inv or inv.datastore or inv.storageBusy then return end

    local buffer, n = {}, 0

    for k, v in pairs(inv.items) do
        if not Items.UpdateDurability(inv, v, Items(v.name), nil, os.time()) then
            v = inv.items[k]
            n += 1
            buffer[n] = {
                name = v.name,
                count = v.count,
                slot = k,
                metadata = next(v.metadata) and v.metadata or nil,
                rotated = v.rotated or nil
            }
        end
    end

    for _, entry in ipairs(inv.recovery or {}) do buffer[#buffer + 1] = { _gridRecovery = table.deepclone(entry) } end
    local data = next(buffer) and json.encode(buffer) or nil
    inv.changed = false

    if inv.type == 'player' then
        return db.savePlayer(inv.owner, data)
    elseif inv.type == 'trunk' then
        return db.saveTrunk(inv.dbId, data)
    elseif inv.type == 'glovebox' then
        return db.saveGlovebox(inv.dbId, data)
    end

    return db.saveStash(inv.owner, inv.dbId, data)
end

---@alias RandomLoot { [1]: string, [2]: number, [3]: number, [4]?: number }

---@param loot RandomLoot[]
---@param items RandomLoot[]
---@param size number
---@return RandomLoot
local function randomItem(loot, items, size)
    local itemIndex = math.random(1, size)
    local selectedItem = nil

    for _ = 1, size do
        selectedItem = loot[itemIndex]
        local found = false

        for i = 1, #items do
            if items[i][1] == selectedItem[1] then
                found = true
                break
            end
        end

        if not found then break end

        itemIndex = ((itemIndex - 1) % size) + 1
    end

    return selectedItem
end

---@param loot RandomLoot[]
---@return RandomLoot[]
local function randomLoot(loot)
    ---@type RandomLoot[]
    local items = {}
    local size = #loot
    local itemCount = math.random(0, 3)

    for _ = 1, itemCount do
        if #items >= size then break end

        local item = randomItem(loot, items, size)

        if item and math.random(1, 100) <= (item[4] or 80) then
            local count = math.random(item[2], item[3])

            if count > 0 then
                items[#items + 1] = { item[1], count }
            end
        end
    end

    return items
end

---@param inv inventory
---@param invType string
---@param items? table
---@return table returnData, number totalWeight
local function generateItems(inv, invType, items)
	if items == nil then
		if invType == 'dumpster' then
			items = randomLoot(server.dumpsterloot)
		elseif invType == 'vehicle' then
			items = randomLoot(server.vehicleloot)
		end
	end

	if not items then
		items = {}
	end

    local returnData, totalWeight = {}, 0
    for i = 1, #items do
        local entry = items[i]
        local item = type(entry) == 'table' and Items(entry[1])
        local remaining = type(entry) == 'table' and entry[2]
        if not item or not Grid.Integer(remaining) then
            local record = type(entry) == 'table' and table.deepclone(entry) or { original = entry }
            record.name, record.count, record.metadata, record.slot = type(entry) == 'table' and entry[1], remaining, type(entry) == 'table' and entry[3], #returnData + 1
            returnData[#returnData + 1] = record
        else
            while remaining > 0 do
                local metadata, count = Items.Metadata(inv, item, table.deepclone(entry[3] or {}), remaining)
                if not Grid.Integer(count) or count > remaining then error('Invalid generated item count') end
                local record = { name = item.name, count = count, metadata = metadata, slot = #returnData + 1 }
                totalWeight += Inventory.SlotWeight(item, record)
                returnData[#returnData + 1] = record
                remaining -= count
            end
        end
    end

	return returnData, totalWeight
end

---@param id string|number
---@param invType string
---@param owner? string | number | boolean
function Inventory.Load(id, invType, owner)
    if not invType then return end

	local result

    if invType == 'trunk' or invType == 'glovebox' then
        result = id and (invType == 'trunk' and db.loadTrunk(id) or db.loadGlovebox(id))

        if not result then
            if server.randomloot then
                return generateItems(id, 'vehicle')
            end
        else
            result = result[invType]
        end
	elseif invType == 'dumpster' then
		if server.randomloot then
			return generateItems(id, invType)
		end
	elseif id then
		result = db.loadStash(owner or '', id)
	end

    if type(result) == 'string' then
        local ok, decoded = pcall(json.decode, result)
        if not ok or type(decoded) ~= 'table' then error('Refusing to load malformed inventory JSON', 2) end
        result = decoded
    end
    return result or {}, 0
end

local function assertMetadata(metadata)
	if metadata and type(metadata) ~= 'table' then
		metadata = metadata and { type = metadata or nil }
	end

	return metadata
end

---@param inv inventory
---@param item table | string
---@param metadata? any
---@param returnsCount? boolean
---@return table | number | nil
function Inventory.GetItem(inv, item, metadata, returnsCount)
	item = itemDefinition(item)

	if item then
		item = returnsCount and item or table.clone(item)
		inv = Inventory(inv) --[[@as OxInventory]]
		local count = 0

		if inv then
			local ostime = os.time()
			metadata = assertMetadata(metadata)

			for _, v in pairs(inv.items) do
				if v.name == item.name and (not metadata or table.contains(v.metadata, metadata)) and not Items.UpdateDurability(inv, v, item, nil, ostime) then
                    count += v.count
				end
			end
		end

		if returnsCount then return count else
			item.count = count
			return item
		end
	end
end
exports('GetItem', Inventory.GetItem)

---@param fromInventory any
---@param toInventory any
---@param slot1 number
---@param slot2 number
function Inventory.SwapSlots(fromInventory, toInventory, slot1, slot2)
    fromInventory, toInventory = Inventory(fromInventory), Inventory(toInventory)
    if not fromInventory or not toInventory or not Grid.Integer(slot1) or not Grid.Integer(slot2) then return false end
    local from = fromInventory.items[slot1]
    if not from then return false end
    local plan = Inventory.Assess({
        { kind = 'transfer', from = fromInventory, to = toInventory, fromSlot = slot1, toSlot = slot2, count = from.count, swap = true },
    })
    if not plan or not Inventory.Apply(plan) then return false end
    return toInventory.items[slot2], fromInventory.items[slot1]
end

exports('SwapSlots', Inventory.SwapSlots)

function Inventory.ContainerWeight(container, metaWeight, playerInventory)
    local metadata = table.deepclone(container.metadata)
    metadata.weight = metaWeight
    return Inventory.SetMetadata(playerInventory, container.slot, metadata)
end

---@param inv inventory
---@param item table | string
---@param count number
---@param metadata? table
---@return boolean? success, string|SlotWithItem|nil response
function Inventory.SetItem(inv, item, count, metadata)
	item = itemDefinition(item)

	if not item then return false, 'invalid_item' end
	if not Grid.Integer(count, 0) then return false, 'invalid_count' end

	count = math.floor(count + 0.5)
	if count < 0 then return false, 'negative_count' end

	inv = Inventory(inv) --[[@as OxInventory]]

	if not inv then return false, 'invalid_inventory' end

	inv.changed = true
	local itemCount = Inventory.GetItem(inv, item.name, metadata, true) --[[@as number]]

	if count > itemCount then
		count -= itemCount
		return Inventory.AddItem(inv, item.name, count, metadata)
	elseif count < itemCount then
		itemCount -= count
		return Inventory.RemoveItem(inv, item.name, itemCount, metadata)
	end
end
exports('SetItem', Inventory.SetItem)

---@param inv inventory
function Inventory.GetCurrentWeapon(inv)
	inv = Inventory(inv) --[[@as OxInventory]]

	if inv?.player then
		local weapon = inv.items[inv.weapon]

		if weapon and Items(weapon.name).weapon then
			return weapon
		end

		inv.weapon = nil
	end
end
exports('GetCurrentWeapon', Inventory.GetCurrentWeapon)

---@param inv inventory
---@param slotId number
---@return table? item
function Inventory.GetSlot(inv, slotId)
	if not inv or type(slotId) ~= 'number' then return end

	inv = Inventory(inv) --[[@as OxInventory]]
	local slot = inv and inv.items?[slotId]

	if slot and not Items.UpdateDurability(inv, slot, Items(slot.name), nil, os.time()) then
        return inv.items[slotId]
	end
end
exports('GetSlot', Inventory.GetSlot)

---@param inv inventory
---@param slotId number
---@param durability number
function Inventory.SetDurability(inv, slotId, durability)
	if not inv or type(slotId) ~= 'number' or type(durability) ~= 'number' then return end

	inv = Inventory(inv) --[[@as OxInventory]]
	local slot = inv and inv.items?[slotId]

	if not slot then return end

    Items.UpdateDurability(inv, slot, Items(slot.name), durability)

    if inv.player and server.syncInventory then
        server.syncInventory(inv)
    end
end
exports('SetDurability', Inventory.SetDurability)

local Utils = require 'modules.utils.server'

---@param inv inventory
---@param slotId number
---@param metadata { [string]: any }
function Inventory.SetMetadata(inv, slotId, metadata)
    inv = Inventory(inv)
    if not inv or not Grid.Integer(slotId) or not inv.items[slotId] then return false end
    local record = table.deepclone(inv.items[slotId])
    record.metadata = type(metadata) == 'table' and table.deepclone(metadata) or { type = metadata }
    if record.metadata.imageurl and record.metadata.imageurl ~= inv.items[slotId].metadata.imageurl and Utils.IsValidImageUrl and not Utils.IsValidImageUrl(record.metadata.imageurl) then record.metadata.imageurl = nil end
    local item = Items(record.name)
    local plan, err = Inventory.Assess({ { kind = 'set', inventory = inv, slot = slotId, record = not (item.decay and record.metadata.durability == 0) and record or nil } })
    if not plan then return false, err end
    return Inventory.Apply(plan)
end

exports('SetMetadata', Inventory.SetMetadata)

---@param inv inventory
---@param slots number
function Inventory.SetSlotCount(inv, slots)
    inv = Inventory(inv)
    if not inv or not Grid.Integer(slots, 0) then return false end
    local plan = Inventory.Assess({ { kind = 'resize', inventory = inv, slots = slots } })
    if not plan then return false end
    return Inventory.Apply(plan)
end

exports('SetSlotCount', Inventory.SetSlotCount)

---@param inv inventory
---@param maxWeight number
function Inventory.SetMaxWeight(inv, maxWeight)
	inv = Inventory(inv) --[[@as OxInventory]]

	if not inv or inv.storageBusy then return end
	if not Grid.Integer(maxWeight, 0) then return end

	inv.maxWeight = maxWeight
    inv.revision = (inv.revision or 0) + 1

    if inv.player then
        TriggerClientEvent('ox_inventory:refreshMaxWeight', inv.id, {inventoryId = inv.id, maxWeight = inv.maxWeight})
    end

    for playerId in pairs(inv.openedBy) do
        if playerId ~= inv.id then
            TriggerClientEvent('ox_inventory:refreshMaxWeight', playerId, {inventoryId = inv.id, maxWeight = inv.maxWeight})
        end
	end
end

exports('SetMaxWeight', Inventory.SetMaxWeight)

---@param inv inventory
---@param item table | string
---@param count number
---@param metadata? table | string
---@param slot? number
---@param cb? fun(success?: boolean, response: string|SlotWithItem|nil)
---@return boolean? success, string|SlotWithItem|nil response
function Inventory.AddItem(inv, item, count, metadata, slot, cb, rotated)
    item = itemDefinition(item)
    inv = Inventory(inv)
    if not item then return false, 'invalid_item' end
    if not inv then return false, 'invalid_inventory' end
    if not Grid.Integer(count) then return false, 'invalid_count' end
    if slot ~= nil and not Grid.Integer(slot) then return false, 'invalid_slot' end
    if rotated ~= nil and type(rotated) ~= 'boolean' then return false, 'invalid_rotation' end
    local commands, err = Inventory.PrepareItems(inv, item, count, assertMetadata(metadata), slot, rotated)
    local plan
    if commands then plan, err = Inventory.Assess(commands) end
    if not plan then
        if cb then return cb(false, err) end

        return false, err
    end

    local success, response = Inventory.Apply(plan)
    if success then
        local records = {}
        for i, result in ipairs(plan.results) do
            records[i] = result.inventory.items[result.slot]
            TriggerClientEvent('ox_inventory:itemNotify', inv.id, { records[i], 'ui_added', commands[i].record.count })
        end
        response = #records == 1 and records[1] or records
    end
    if cb then return cb(success, response) end
    return success, response
end

exports('AddItem', Inventory.AddItem)

---@param inv inventory
---@param search string|number slots|1, count|2
---@param items table | string
---@param metadata? table | string
function Inventory.Search(inv, search, items, metadata)
	if items then
		inv = Inventory(inv) --[[@as OxInventory]]

		if inv then
			inv = inv.items

			if search == 'slots' then search = 1 elseif search == 'count' then search = 2 end
			if type(items) == 'string' then items = {items} end

			metadata = assertMetadata(metadata)
			local itemCount = #items
			local returnData = {}

			for i = 1, itemCount do
				local item = string.lower(items[i])
				if item:sub(0, 7) == 'weapon_' then item = string.upper(item) end

				if search == 1 then
					returnData[item] = {}
				elseif search == 2 then
					returnData[item] = 0
				end

				for _, v in pairs(inv) do
					if v.name == item then
						if not v.metadata then v.metadata = {} end

						if not metadata or table.contains(v.metadata, metadata) then
							if search == 1 then
								returnData[item][#returnData[item]+1] = inv[v.slot]
							elseif search == 2 then
								returnData[item] += v.count
							end
						end
					end
				end
			end

			if next(returnData) then return itemCount == 1 and returnData[items[1]] or returnData end
		end
	end

	return false
end
exports('Search', Inventory.Search)

---@param inv inventory
---@param item table | string
---@param metadata? table
---@param strict? boolean
function Inventory.GetItemSlots(inv, item, metadata, strict)
	item = itemDefinition(item)
	if not item then return end

	inv = Inventory(inv) --[[@as OxInventory]]
	if not inv?.slots then return end

	local totalCount, slots, emptySlots = 0, {}, inv.slots

	if strict == nil then strict = true end
	local tablematch = strict and table.matches or table.contains

	for k, v in pairs(inv.items) do
		local size = Items(v.name).size or { width = 1, height = 1 }
        emptySlots -= size.width * size.height
		if v.name == item.name then
			if metadata and v.metadata == nil then
				v.metadata = {}
			end
			if not metadata or tablematch(v.metadata, metadata) then
				totalCount = totalCount + v.count
				slots[k] = v.count
			end
		end
	end

	return slots, totalCount, emptySlots
end
exports('GetItemSlots', Inventory.GetItemSlots)

---@param inv inventory
---@param item table | string
---@param count integer
---@param metadata? table | string
---@param slot? number
---@param ignoreTotal? boolean
---@param strict? boolean
---@return boolean? success, string? response
function Inventory.RemoveItem(inv, item, count, metadata, slot, ignoreTotal, strict)
    item = itemDefinition(item)
    inv = Inventory(inv)
    if not item then return false, 'invalid_item' end
    if not inv then return false, 'invalid_inventory' end
    if not Grid.Integer(count) then return false, 'invalid_count' end
    if slot ~= nil and not Grid.Integer(slot) then return false, 'invalid_slot' end
    metadata = assertMetadata(metadata)
    if slot and not inv.items[slot] then return false, 'no_item_in_slot' end
    if ignoreTotal then
        local slots, total = Inventory.GetItemSlots(inv, item, metadata, strict)
        count = math.min(count, slot and (slots[slot] or 0) or total)
    end
    if count == 0 then return false, 'not_enough_items' end
    local plan, err = Inventory.Assess({ { kind = 'remove', inventory = inv, name = item.name, count = count, metadata = metadata, slot = slot, strict = strict } })
    if not plan then return false, err end
    local record = slot and inv.items[slot] or { name = item.name, label = item.label }
    local success, response = Inventory.Apply(plan)
    if success then TriggerClientEvent('ox_inventory:itemNotify', inv.id, { record, 'ui_removed', count }) end
    return success, response
end

exports('RemoveItem', Inventory.RemoveItem)

---@param inv inventory
---@param item table | string
---@param count number
---@param metadata? table | string
function Inventory.CanCarryItem(inv, item, count, metadata)
    item = itemDefinition(item)
    inv = Inventory(inv)
    count = count or 1
    if not inv or not item or not Grid.Integer(count) or (not item.stack and count > inv.slots) then return false end
    local commands = {}
    for i = 1, item.stack and 1 or count do
        commands[i] = { kind = 'add', inventory = inv, record = { name = item.name, count = item.stack and count or 1, metadata = assertMetadata(metadata) or {} } }
    end
    return Inventory.Assess(commands) ~= nil
end

exports('CanCarryItem', Inventory.CanCarryItem)

---@param inv inventory
---@param item table | string
function Inventory.CanCarryAmount(inv, item)
    item = itemDefinition(item)
    inv = Inventory(inv)
    if not inv or not item or inv.unknownWeight then return 0 end
    local limit = item.weight > 0 and math.max(0, math.floor((inv.maxWeight - inv.weight) / item.weight)) or (item.stack and 2147483647 or inv.slots)
    if item.stack then return Inventory.CanCarryItem(inv, item, math.max(1, limit)) and limit or 0 end
    local low, high = 0, math.min(inv.slots, limit)
    while low < high do
        local middle = math.ceil((low + high) / 2)
        if Inventory.CanCarryItem(inv, item, middle) then
            low = middle
        else
            high = middle - 1
        end
    end
    return low
end

exports('CanCarryAmount', Inventory.CanCarryAmount)

---@param inv inventory
---@param weight number
function Inventory.CanCarryWeight(inv, weight)
	inv = Inventory(inv) --[[@as OxInventory]]

	if not inv then return end

	local availableWeight = inv.maxWeight - inv.weight
	local canHold = not inv.unknownWeight and availableWeight >= weight
	return canHold, availableWeight
end
exports('CanCarryWeight', Inventory.CanCarryWeight)

---@param inv inventory
---@param firstItem string
---@param firstItemCount number
---@param testItem string
---@param testItemCount number
function Inventory.CanSwapItem(inv, firstItem, firstItemCount, testItem, testItemCount)
    inv = Inventory(inv)
    local item = Items(testItem)
    if not inv or not item or not Grid.Integer(firstItemCount, 0) or not Grid.Integer(testItemCount) then return false end
    local commands = { { kind = 'remove', inventory = inv, name = firstItem, count = firstItemCount } }
    for i = 1, item.stack and 1 or testItemCount do
        commands[#commands + 1] = { kind = 'add', inventory = inv, record = { name = item.name, count = item.stack and testItemCount or 1, metadata = {} } }
    end
    return Inventory.Assess(commands) ~= nil
end

exports('CanSwapItem', Inventory.CanSwapItem)

---Mostly for internal use, but deprecated.
---@param name string
---@param count number
---@param metadata { [string]: any }
---@param slot number
RegisterServerEvent('ox_inventory:removeItem', function(name, count, metadata, slot)
	Inventory.RemoveItem(source, name, count, metadata, slot)
end)

Inventory.Drops = {}

---@param prefix string?
---@return string
local function generateInvId(prefix)
	while true do
		local invId = ('%s-%s'):format(prefix or 'drop', math.random(100000, 999999))

		if not Inventories[invId] then return invId end

		Wait(0)
	end
end

local function CustomDrop(prefix, items, coords, slots, maxWeight, instance, model)
	local dropId = generateInvId()
    local records = generateItems({ id = dropId }, 'drop', items)
	local inventory = Inventory.Create(dropId, ('%s %s'):format(prefix, dropId:gsub('%D', '')), 'drop', slots or shared.dropslots, 0, maxWeight or shared.dropweight, false, records)

	if not inventory then return end

	inventory.coords = coords
	Inventory.Drops[dropId] = {
		coords = inventory.coords,
		instance = instance,
		model = model,
	}

	TriggerClientEvent('ox_inventory:createDrop', -1, dropId, Inventory.Drops[dropId])

    return dropId
end

AddEventHandler('ox_inventory:customDrop', CustomDrop)
exports('CustomDrop', CustomDrop)

exports('CreateDropFromPlayer', function(playerId)
	local playerInventory = Inventory(playerId)

	if not playerInventory or playerInventory.storageBusy or not next(playerInventory.items) and not next(playerInventory.recovery) then return end

	local dropId = generateInvId()
	local inventory = Inventory.Create(dropId, ('Drop %s'):format(dropId:gsub('%D', '')), 'drop', playerInventory.slots, playerInventory.weight, playerInventory.maxWeight, false, minimal(playerInventory))

	if not inventory then return end

	local coords = GetEntityCoords(GetPlayerPed(playerId))
	inventory.coords = vec3(coords.x, coords.y, coords.z-0.2)
	Inventory.Drops[dropId] = {
		coords = inventory.coords,
		instance = Player(playerId).state.instance
	}

    if not Inventory.Clear(playerInventory) then
        Inventory.Remove(inventory)
        return
    end
	TriggerClientEvent('ox_inventory:createDrop', -1, dropId, Inventory.Drops[dropId])

	return dropId
end)

local TriggerEventHooks = require 'modules.hooks.server'

---@class SwapSlotData
---@field count number
---@field fromSlot number
---@field toSlot number
---@field instance any
---@field fromType string
---@field toType string
---@field coords? vector3

---@param source number
---@param playerInventory OxInventory
---@param fromData SlotWithItem?
---@param data SwapSlotData
local function dropItem(source, playerInventory, fromData, data)
    if not fromData or not data.coords then return false end
    local dropId = generateInvId('drop')
    local inventory = Inventory.Create(dropId, ('Drop %s'):format(dropId:gsub('%D', '')), 'drop', shared.dropslots, 0, shared.dropweight, false, {})
    if not inventory then return false end
    local plan, err = Inventory.Assess({ {
        kind = 'transfer',
        from = playerInventory,
        to = inventory,
        fromSlot = data.fromSlot,
        toSlot = data.toSlot,
        count = data.count,
        rotated = data.rotated
    } })

    if not plan then
        Inventory.Remove(inventory)
        return false, err
    end

    local hooks <close> = TriggerEventHooks('swapItems', {
        source = source, fromInventory = playerInventory.id, fromSlot = fromData, fromType = playerInventory.type,
        toInventory = 'newdrop', toSlot = data.toSlot, toType = 'drop', count = data.count, action = 'move', dropId = dropId,
    })
    if not hooks.success or not Inventory.Apply(plan) then
        hooks.success = false
        Inventory.Remove(inventory)
        return false
    end
    inventory.coords = data.coords
    Inventory.Drops[dropId] = { coords = data.coords, instance = data.instance }
    TriggerClientEvent('ox_inventory:createDrop', -1, dropId, Inventory.Drops[dropId], playerInventory.open and source, data.fromSlot)
    return true, {
        weight = playerInventory.weight,
        items = { {
            item = playerInventory.items[data.fromSlot] or { slot = data.fromSlot },
            inventory = playerInventory.id
        } }
    }
end

lib.callback.register('ox_inventory:swapItems', function(source, data)
    if type(data) ~= 'table' or type(data.fromType) ~= 'string' or type(data.toType) ~= 'string'
        or not Grid.Integer(data.fromSlot) or not Grid.Integer(data.toSlot) or not Grid.Integer(data.count)
        or (data.rotated ~= nil and type(data.rotated) ~= 'boolean') then return false end
    if data.fromType ~= data.toType and data.toType ~= 'player' and data.fromType ~= 'player' then
        Utils.LogExploit(source, 'swapItems', 'Triggered event with invalid data', true)
        return false
    end
    if data.toType == 'inspect' or data.fromType == 'inspect' then return false end
    local player = Inventory(source)
    if not player or not player.open then return false end
    local from = data.fromType == 'player' and player or Inventory(player.open)
    local to = data.toType == 'player' and player or Inventory(player.open)
    if not from or not to then
        player:closeInventory()
        return false
    end

    if data.fromType ~= 'player' and from == player then return false end
    if data.toType ~= 'player' and data.toType ~= 'newdrop' and to == player then return false end
    local fromData, toData = from.items[data.fromSlot], to.items[data.toSlot]
    if not fromData or data.count > fromData.count then return false end
    if data.toType == 'newdrop' then
        if from ~= player or (type(data.coords) ~= 'vector3' and type(data.coords) ~= 'table') then return false end
        if #(GetEntityCoords(GetPlayerPed(source)) - data.coords) > 10 then return false end
        return dropItem(source, from, fromData, data)
    end
    if from ~= to and (from.type == 'policeevidence' or (to.type == 'policeevidence' and toData)) then
        local group, rank = server.hasGroup(player, shared.police)
        if not group or server.evidencegrade > rank then return false, 'evidence_cannot_take' end
    end
    if fromData.metadata.container and to.type == 'container' then return false end
    if toData and toData.metadata.container and from.type == 'container' then return false end
    local container = from ~= to and player.containerSlot and (from.type == 'container' and from or to.type == 'container' and to)
    local containerItem = container and player.items[player.containerSlot]
    if containerItem then
        local policy = Items.containers[containerItem.name]
        local entering = to == container and fromData or toData
        if entering and policy and ((policy.whitelist and not policy.whitelist[entering.name]) or (policy.blacklist and policy.blacklist[entering.name])) then return false end
    end
    local commands = { {
        kind = 'transfer',
        from = from,
        to = to,
        fromSlot = data.fromSlot,
        toSlot = data.toSlot,
        count = data.count,
        rotated = data.rotated
    } }
    local plan, err = Inventory.Assess(commands)
    if not plan then return false, err == 'cannot_carry' and not toData and 'cannot_carry_other' or err end
    local action = toData and (toData.name ~= fromData.name or not toData.stack or not table.matches(toData.metadata, fromData.metadata)) and 'swap' or toData and 'stack' or 'move'
    local hooks <close> = TriggerEventHooks('swapItems', {
        source = source, fromInventory = from.id, fromSlot = fromData, fromType = from.type,
        toInventory = to.id, toSlot = toData or data.toSlot, toType = to.type, count = data.count, action = action,
    })
    if not hooks.success then return false end
    local success, response = Inventory.Apply(plan)
    if not success then
        hooks.success = false
        return false, response
    end

    if from ~= to then
        if from.player and from ~= player then TriggerClientEvent('ox_inventory:itemNotify', from.id, { fromData, 'ui_removed', data.count }) end
        if to.player and to ~= player then TriggerClientEvent('ox_inventory:itemNotify', to.id, { fromData, 'ui_added', data.count }) end
    end
    if server.loglevel > 0 then lib.logger(player.owner, 'swapSlots', ('%sx %s transferred from "%s" to "%s"'):format(data.count, fromData.name, from.label, to.label)) end
    return containerItem and player.items[player.containerSlot].weight or true
end)

lib.callback.register('ox_inventory:recoverItem', function(source, data)
    if type(data) ~= 'table' or type(data.fromType) ~= 'string' or type(data.recoveryId) ~= 'string'
        or (data.toSlot ~= nil and not Grid.Integer(data.toSlot)) or (data.rotated ~= nil and type(data.rotated) ~= 'boolean') then return false end
    local player = Inventory(source)
    if not player or not player.open or data.fromType == 'inspect' then return false end
    local inv = data.fromType == 'player' and player or Inventory(player.open)
    if not inv or (data.fromType ~= 'player' and (inv == player or (inv.player and 'otherplayer' or inv.type) ~= data.fromType)) then return false end
    if inv.groups and not server.hasGroup(player, inv.groups) then return false end
    if inv.coords and type(inv.coords) == 'vector3' and #(GetEntityCoords(GetPlayerPed(source)) - inv.coords) > (inv.distance or 10) then return false end
    if inv.type == 'policeevidence' then
        local group, rank = server.hasGroup(player, shared.police)
        if not group or rank < server.evidencegrade then return false end
    end
    local plan, err = Inventory.Assess({ { kind = 'recover', inventory = inv, id = data.recoveryId, slot = data.toSlot, rotated = data.rotated } })
    if not plan then return false, err end
    return Inventory.Apply(plan)
end)

local function releaseStorage(inv)
    inv.storageBusy = nil
    if inv.removeAfterStorage then
        inv.removeAfterStorage = nil
        Inventory.Remove(inv)
    end
end

local storageGuard = { __close = function(guard) releaseStorage(guard.inventory) end }

function Inventory.PersistPlayer(inv)
    if inv.storageBusy then return false end
    inv.storageBusy = true
    local guard <close> = setmetatable({ inventory = inv }, storageGuard)
    local ok, saved = pcall(db.savePlayer, inv.owner, json.encode(minimal(inv)))
    return ok and saved ~= false and saved ~= nil
end

function Inventory.Confiscate(source)
    local inv = Inventory(source)
    if not inv or not inv.player or inv.storageBusy then return false end
    local plan = Inventory.Assess({ { kind = 'replace', inventory = inv, records = {} } })
    plan.storage = true
    inv.storageBusy = true
    local guard <close> = setmetatable({ inventory = inv }, storageGuard)
    local records = minimal(inv)
    local stored = MySQL.scalar.await('SELECT data FROM ox_inventory WHERE name = ? AND owner = ?', { inv.owner, tostring(inv.owner) })
    if stored then
        local ok, decoded = pcall(json.decode, stored)
        if not ok or type(decoded) ~= 'table' then return false end
        for _, record in pairs(decoded) do records[#records + 1] = record end
    end
    local ok, saved = pcall(db.confiscatePlayer, inv.owner, json.encode(records))
    if not ok or saved == false or saved == nil then return false end
    local success = Inventory.Apply(plan)
    if not success then return false end
    TriggerClientEvent('ox_inventory:inventoryConfiscated', inv.id)
    return true
end
exports('ConfiscateInventory', Inventory.Confiscate)

function Inventory.Return(source)
    local inv = Inventory(source)
    if not inv or not inv.player or inv.storageBusy then return false end
    local revision = inv.revision
    local records = MySQL.scalar.await('SELECT data FROM ox_inventory WHERE name = ? AND owner = ?', { inv.owner, tostring(inv.owner) })
    if not records or Inventory(source) ~= inv or inv.revision ~= revision then return false end
    local items, _, recovery = Inventory.Reconcile(records, inv.slots)
    local restored = serialize(items, recovery)
    for _, record in ipairs(minimal(inv)) do restored[#restored + 1] = record end
    local plan = Inventory.Assess({ { kind = 'replace', inventory = inv, records = restored } })
    if not plan then return false end
    local state = plan.states[inv]
    plan.storage = true
    inv.storageBusy = true
    local guard <close> = setmetatable({ inventory = inv }, storageGuard)
    local ok, saved = pcall(db.restorePlayer, inv.owner, json.encode(serialize(state.items, state.recovery)))
    if not ok or not saved then return false end
    local success = Inventory.Apply(plan)
    if not success then return false end
    TriggerClientEvent('ox_inventory:inventoryReturned', source, { inv.items, inv.weight, grid = inv.grid, recovery = inv.recovery })
    return true
end

exports('ReturnInventory', Inventory.Return)

---@param inv inventory
---@param keep? string | string[] an item or list of items to ignore while clearing items
function Inventory.Clear(inv, keep)
    inv = Inventory(inv)
    if not inv then return end
    local records, names = {}, {}
    if type(keep) == 'string' then
        names[keep] = true
    elseif type(keep) == 'table' then
        for _, name in ipairs(keep) do names[name] = true end
    end

    for _, record in pairs(inv.items) do
        if names[record.name] then records[#records + 1] = record end
    end

    if keep then
        for _, entry in ipairs(inv.recovery) do
            if type(entry.record) ~= 'table' or names[entry.record.name] then records[#records + 1] = { _gridRecovery = entry } end
        end
    end
    local plan = Inventory.Assess({ { kind = 'replace', inventory = inv, records = records } })
    if plan and Inventory.Apply(plan) then return true end
end

exports('ClearInventory', Inventory.Clear)

---@param inv inventory
---@return integer?
function Inventory.GetEmptySlot(inv)
    inv = Inventory(inv)
    if not inv then return end
    local occupied = Grid.Occupancy(inv.grid, inv.items, Items)
    return occupied and Grid.FirstFit(inv.grid, occupied, nil)
end

exports('GetEmptySlot', Inventory.GetEmptySlot)

---@param inv inventory
---@param itemName string
---@param metadata any
function Inventory.GetSlotForItem(inv, itemName, metadata)
    inv = Inventory(inv)
    local item = Items(itemName)
    if not inv or not item then return end
    metadata = assertMetadata(metadata) or {}
    if item.stack then
        for i = 1, inv.slots do
            local record = inv.items[i]
            if record and record.name == item.name and table.matches(record.metadata, metadata) then return i end
        end
    end
    local occupied = Grid.Occupancy(inv.grid, inv.items, Items)
    return occupied and Grid.FirstFit(inv.grid, occupied, item.size)
end

exports('GetSlotForItem', Inventory.GetSlotForItem)

---@param inv inventory
---@param itemName string
---@param metadata? any
---@param strict? boolean Strictly match metadata properties, otherwise use partial matching.
---@return SlotWithItem?
function Inventory.GetSlotWithItem(inv, itemName, metadata, strict)
	local inventory = Inventory(inv)
	local item = Items(itemName) --[[@as OxServerItem?]]

	if not inventory or not item then return end

	metadata = assertMetadata(metadata)
	local tablematch = strict and table.matches or table.contains

	for _, slotData in pairs(inventory.items) do
		if slotData and slotData.name == item.name and (not metadata or tablematch(slotData.metadata, metadata)) then
            if not Items.UpdateDurability(inventory, slotData, item, nil, os.time()) then
                return inventory.items[slotData.slot]
            end
		end
	end
end

exports('GetSlotWithItem', Inventory.GetSlotWithItem)

---@param inv inventory
---@param itemName string
---@param metadata? any
---@param strict? boolean Strictly match metadata properties, otherwise use partial matching.
---@return number?
function Inventory.GetSlotIdWithItem(inv, itemName, metadata, strict)
	return Inventory.GetSlotWithItem(inv, itemName, metadata, strict)?.slot
end

exports('GetSlotIdWithItem', Inventory.GetSlotIdWithItem)

---@param inv inventory
---@param itemName string
---@param metadata? any
---@param strict? boolean Strictly match metadata properties, otherwise use partial matching.
---@return SlotWithItem[]?
function Inventory.GetSlotsWithItem(inv, itemName, metadata, strict)
	local inventory = Inventory(inv)
	local item = Items(itemName) --[[@as OxServerItem?]]

	if not inventory or not item then return end

	metadata = assertMetadata(metadata)
	local response = {}
	local n = 0
	local tablematch = strict and table.matches or table.contains

	for _, slotData in pairs(inventory.items) do
		if slotData and slotData.name == item.name and (not metadata or tablematch(slotData.metadata, metadata)) then
            if not Items.UpdateDurability(inventory, slotData, item, nil, os.time()) then
                n += 1
                response[n] = inventory.items[slotData.slot]
            end
		end
	end

	return response
end

exports('GetSlotsWithItem', Inventory.GetSlotsWithItem)

---@param inv inventory
---@param itemName string
---@param metadata? any
---@param strict? boolean Strictly match metadata properties, otherwise use partial matching.
---@return number[]?
function Inventory.GetSlotIdsWithItem(inv, itemName, metadata, strict)
	local items = Inventory.GetSlotsWithItem(inv, itemName, metadata, strict)

	if items then
		---@cast items +number[]
		for i = 1, #items do
			items[i] = items[i].slot
		end

		return items
	end
end

exports('GetSlotIdsWithItem', Inventory.GetSlotIdsWithItem)

---@param inv inventory
---@param itemName string
---@param metadata? any
---@param strict? boolean Strictly match metadata properties, otherwise use partial matching.
---@return number
function Inventory.GetItemCount(inv, itemName, metadata, strict)
	local inventory = Inventory(inv)
	local item = Items(itemName) --[[@as OxServerItem?]]

	if not inventory or not item then return 0 end

	metadata = assertMetadata(metadata)
	local count = 0
	local tablematch = strict and table.matches or table.contains

	for _, slotData in pairs(inventory.items) do
		if slotData and slotData.name == item.name and (not metadata or tablematch(slotData.metadata, metadata)) then
			count += slotData.count
		end
	end

	return count
end

exports('GetItemCount', Inventory.GetItemCount)

---@alias InventorySaveData { [1]: MinimalInventorySlot, [2]: string | number, [3]: string | number | nil }

---@param inv OxInventory
---@param buffer table
---@param time integer
---@return integer?
---@return InventorySaveData?
local function prepareInventorySave(inv, buffer, time)
    if inv.storageBusy then return end
    local shouldSave = not inv.datastore and inv.changed
    local n = 0

    for k, v in pairs(inv.items) do
        if not Items.UpdateDurability(inv, v, Items(v.name), nil, time) and shouldSave then
            v = inv.items[k]
            n += 1
            buffer[n] = {
                name = v.name,
                count = v.count,
                slot = k,
                metadata = next(v.metadata) and v.metadata or nil,
                rotated = v.rotated or nil
            }
        end
	end

    if not shouldSave then return end

    for _, entry in ipairs(inv.recovery or {}) do buffer[#buffer + 1] = { _gridRecovery = table.deepclone(entry) } end
    local data = next(buffer) and json.encode(buffer) or nil
    inv.changed = false
    table.wipe(buffer)

    if inv.type == 'player' then
        return 1, { data, inv.owner }
    end

    if inv.type == 'trunk' then
        return 2, { data, inv.dbId }
    end

    if inv.type == 'glovebox' then
        return 3, { data, inv.dbId }
    end

    return 4, { data, inv.owner and tostring(inv.owner) or '', inv.dbId }
end

local isSaving = false
local inventoryClearTime = GetConvarInt('inventory:cleartime', 5) * 60

local function saveInventories(clearInventories)
	if isSaving then return end

	local time = os.time()
	local parameters = { {}, {}, {}, {} }
	local total = { 0, 0, 0, 0, 0 }
    local buffer = {}

	for _, inv in pairs(Inventories) do
        local index, data = prepareInventorySave(inv, buffer, time)

        if index and data then
            total[5] += 1

            if index == 4 and server.bulkstashsave then
                for i = 1, 3 do
					total[index] += 1
                    parameters[index][total[index]] = data[i]
                end
            else
				total[index] += 1
                parameters[index][total[index]] = data
            end
        end
	end

    if total[5] > 0 then
        isSaving = true
        local ok, err = pcall(db.saveInventories, parameters[1], parameters[2], parameters[3], parameters[4], total)
        isSaving = false

        if not ok and err then return lib.print.error(err) end
    end

    if not clearInventories then return end

    for _, inv in pairs(Inventories) do
        if not inv.open and not inv.player then
            -- clear inventory from memory if unused for x minutes, or on entity/netid mismatch
            if inv.type == 'glovebox' or inv.type == 'trunk' then
                if NetworkGetEntityFromNetworkId(inv.netid) ~= inv.entityId then
                    Inventory.Remove(inv)
                end
            elseif time - inv.time >= inventoryClearTime then
                Inventory.Remove(inv)
            end
        end
    end
end

lib.cron.new('*/5 * * * *', function()
    saveInventories(true)
end)

function Inventory.SaveInventories(lock, clearInventories)
	Inventory.Lock = lock or nil

	Inventory.CloseAll()
    saveInventories(clearInventories)
end

AddEventHandler('playerDropped', function()
	server.playerDropped(source)

	if GetNumPlayerIndices() == 0 then
		Inventory.SaveInventories(false, true)
	end
end)

AddEventHandler('txAdmin:events:serverShuttingDown', function()
	Inventory.SaveInventories(true, false)
end)

AddEventHandler('txAdmin:events:scheduledRestart', function(eventData)
    if eventData.secondsRemaining ~= 60 then return end

	Inventory.SaveInventories(true, true)
end)

AddEventHandler('onResourceStop', function(resource)
	if resource == shared.resource then
		Inventory.SaveInventories(true, false)
	end
end)

RegisterServerEvent('ox_inventory:closeInventory', function()
	local inventory = Inventories[source]

	if inventory?.open then
		local secondary = Inventories[inventory.open]

		if secondary then
			secondary:closeInventory()
		end

		inventory:closeInventory(true)
	end
end)

local function giveItem(playerId, slot, target, count)
    if count == nil or count == 0 then count = 1 end
    if not Grid.Integer(slot) or not Grid.Integer(target) or not Grid.Integer(count) then return end
    local from, to = Inventory(playerId), Inventory(target)
    if not from or not to or from == to or not to.player then return end
    local record = from.items[slot]
    if not record then return end
    local failure = { 'cannot_give', count, record.label }
    if Player(target).state.invBusy or count > record.count or #(GetEntityCoords(from.player.ped) - GetEntityCoords(to.player.ped)) > 15 then return failure end
    local occupied = Grid.Occupancy(to.grid, to.items, Items)
    local anchor
    if record.stack then
        for i = 1, to.slots do
            local item = to.items[i]
            if item and item.name == record.name and table.matches(item.metadata, record.metadata) then
                anchor = i
                break
            end
        end
    end
    anchor = anchor or (occupied and Grid.FirstFit(to.grid, occupied, Items(record.name).size, record.rotated))
    if not anchor then return failure end
    local plan = Inventory.Assess({ { kind = 'transfer', from = from, to = to, fromSlot = slot, toSlot = anchor, count = count } })
    if not plan then return failure end
    local hooks <close> = TriggerEventHooks('swapItems', {
        source = from.id, fromInventory = from.id, fromType = from.type, toInventory = to.id, toType = to.type,
        count = count, action = 'give', fromSlot = record,
    })
    if not hooks.success or not Inventory.Apply(plan) then
        hooks.success = false
        return failure
    end

    TriggerClientEvent('ox_inventory:itemNotify', from.id, { record, 'ui_removed', count })
    TriggerClientEvent('ox_inventory:itemNotify', to.id, { record, 'ui_added', count })
end

lib.callback.register('ox_inventory:giveItem', giveItem)
RegisterServerEvent('ox_inventory:giveItem', function(...) giveItem(source, ...) end)

local function updateWeapon(source, action, value, slot, specialAmmo)
    local inv = Inventory(source)
    if not inv then return false end
    if not action then
        inv.weapon = nil
        return true
    end

    if slot == false then slot = nil end
    if type(action) ~= 'string' or (slot ~= nil and not Grid.Integer(slot)) then return false end
    if type(value) == 'number' and (value ~= value or value == math.huge or value < 0) then return false end
    if action == 'component' and type(value) == 'table' then slot = value.slot end
    slot = slot or inv.weapon
    if not Grid.Integer(slot) then return false end
    local original = inv.items[slot]
    if not original then return false end
    local weapon, item = table.deepclone(original), Items(original.name)
    if not item.weapon then
        inv.weapon = nil
        return false
    end

    local commands = {}
    if action == 'load' then
        if not Grid.Integer(value, 0) or (weapon.metadata.durability or 0) <= 0 or not item.ammoname then return false end
        local count = value - (weapon.metadata.ammo or 0)
        if not Grid.Integer(count) then return false end
        commands[1] = { kind = 'remove', inventory = inv, name = item.ammoname, count = count, metadata = specialAmmo and { type = specialAmmo } or nil }
        weapon.metadata.ammo, weapon.metadata.specialAmmo = value, specialAmmo
    elseif action == 'throw' then
        local plan = Inventory.Assess({ { kind = 'remove', inventory = inv, name = weapon.name, count = 1, slot = slot } })
        return plan and Inventory.Apply(plan) or false
    elseif action == 'component' then
        local index = type(value) == 'number' and value
        if type(value) == 'table' then
            for i, name in ipairs(weapon.metadata.components or {}) do
                if name == value.component then
                    index = i
                    break
                end
            end
        end
        if index then
            local name = weapon.metadata.components and weapon.metadata.components[index]
            local component = name and Items(name)
            if not component then return false end
            local credits = Inventory.PrepareItems(inv, component, 1, {})
            if not credits then return false end
            table.remove(weapon.metadata.components, index)
            commands = credits
        elseif type(value) == 'string' then
            local anchor = tonumber(value)
            if not Grid.Integer(anchor) then return false end
            local component = inv.items[anchor]
            if not component or not Items(component.name).component then return false end
            commands[1] = { kind = 'remove', inventory = inv, name = component.name, count = 1, slot = anchor }
            weapon.metadata.components = weapon.metadata.components or {}
            table.insert(weapon.metadata.components, component.name)
        else return false end
    elseif action == 'ammo' then
        if type(value) ~= 'number' then return false end
        if item.hash == `WEAPON_FIREEXTINGUISHER` or item.hash == `WEAPON_PETROLCAN` or item.hash == `WEAPON_HAZARDCAN` or item.hash == `WEAPON_FERTILIZERCAN` then
            weapon.metadata.durability, weapon.metadata.ammo = math.min(100, math.floor(value)), math.min(100, math.floor(value))
        elseif Grid.Integer(value, 0) and value < (weapon.metadata.ammo or 0) then
            weapon.metadata.durability = (weapon.metadata.durability or 0) - (item.durability or 0) * ((weapon.metadata.ammo or 0) - value)
            weapon.metadata.ammo = value
        else return false end
    elseif action == 'melee' then
        if not Grid.Integer(value, 0) then return false end
        weapon.metadata.durability = (weapon.metadata.durability or 0) - (item.durability or 1) * value
    else return false end
    if weapon.metadata.durability then weapon.metadata.durability = math.max(0, weapon.metadata.durability) end
    commands[#commands + 1] = { kind = 'set', inventory = inv, slot = slot, record = weapon }
    local plan = Inventory.Assess(commands)
    return plan and Inventory.Apply(plan) or false
end

lib.callback.register('ox_inventory:updateWeapon', updateWeapon)

RegisterNetEvent('ox_inventory:updateWeapon', function(action, value, slot, specialAmmo)
	updateWeapon(source, action, value, slot, specialAmmo)
end)

lib.callback.register('ox_inventory:removeAmmoFromWeapon', function(source, slot)
    if not Grid.Integer(slot) then return false end
    local inv = Inventory(source)
    if not inv or inv.usingItem then return false end
    local original = inv.items[slot]
    if not original or not Grid.Integer(original.metadata.ammo) then return false end
    local item = Items(original.name)
    local ammo = item and item.ammoname and Items(item.ammoname)
    if not ammo then return false end
    local credits = Inventory.PrepareItems(inv, ammo, original.metadata.ammo, original.metadata.specialAmmo and { type = original.metadata.specialAmmo } or {})
    if not credits then return false end
    local record = table.deepclone(original)
    record.metadata.ammo = 0
    credits[#credits + 1] = { kind = 'set', inventory = inv, slot = slot, record = record }
    local plan = Inventory.Assess(credits)
    return plan and Inventory.Apply(plan) or false
end)

local function checkStashProperties(properties)
	local name = properties.name
	local slots = properties.slots
	local maxWeight = properties.maxWeight
	local coords = properties.coords

	if type(name) ~= 'string' then
		error(('received %s for stash name (expected string)'):format(type(name)))
	end

	if type(slots) ~= 'number' then
		error(('received %s for stash slots (expected number)'):format(type(slots)))
	end

	if type(maxWeight) ~= 'number' then
		error(('received %s for stash maxWeight (expected number)'):format(type(maxWeight)))
	end

	if coords then
		local typeof = type(coords)

		if typeof ~= 'vector3' then
			if typeof == 'table' and table.type(coords) ~= 'array' then
				coords = vec3(coords.x or coords[1], coords.y or coords[2], coords.z or coords[3])
			else
				if table.type(coords) == 'array' then
					for i = 1, #coords do
						coords[i] = vec3(coords[i].x, coords[i].y, coords[i].z)
					end
				else
					error(('received %s for stash coords (expected vector3 or array of vector3)'):format(typeof))
				end
			end
		end
	end

	return name, slots, maxWeight, coords
end

---@param name string stash identifier when loading from the database
---@param label string display name when inventory is open
---@param slots number
---@param maxWeight number
---@param owner? string|number|boolean
---@param groups? table<string, number>
---@param coords? vector3|table<vector3>
---@param instance? string|number
--- For simple integration with other resources that want to create valid stashes.
--- This needs to be triggered before a player can open a stash.
--- ```
--- Owner sets the stash permissions.
--- string: can only access the stash linked to the owner (usually player identifier)
--- true: each player has a unique stash, but can request other player's stashes
--- nil: always shared
---
--- groups: { ['police'] = 0 }
--- ```
local function registerStash(name, label, slots, maxWeight, owner, groups, coords, instance)
	name, slots, maxWeight, coords = checkStashProperties({
		name = name,
		slots = slots,
		maxWeight = maxWeight,
		coords = coords,
	})

	local curStash = RegisteredStashes[name]

	if curStash then
		---@todo creating proper stash classes with inheritence would simplify updating data
		---i.e. all stashes with the same type share groups, maxweight, slots, dbid, etc.
		---only label, owner, weight, coords, and items really need to vary
		for _, stash in pairs(Inventories) do
			if stash.type == 'stash' and stash.dbId == name then
				stash.label = label or stash.label
				stash.owner = (owner and owner ~= true) and stash.owner or owner
				if slots then Inventory.SetSlotCount(stash, slots) end
				if maxWeight then Inventory.SetMaxWeight(stash, maxWeight) end
				stash.groups = groups or stash.groups
				stash.coords = coords or stash.coords
				stash.instance = instance or stash.instance
			end
		end
	end

	RegisteredStashes[name] = {
		name = name,
		label = label,
		owner = owner,
		slots = slots,
		maxWeight = maxWeight,
		groups = groups,
		coords = coords,
		instance = instance
	}
end

exports('RegisterStash', registerStash)

---@param properties TemporaryStashProperties
function Inventory.CreateTemporaryStash(properties)
	properties.name = generateInvId('temp')

	local name, slots, maxWeight, coords = checkStashProperties(properties)
    local records = generateItems({ id = name }, 'drop', properties.items)
	local inventory = Inventory.Create(name, properties.label, 'temp', slots, 0, maxWeight, properties.owner, records, properties.groups)

	if not inventory then return end

	inventory.coords = coords
	inventory.instance = properties.instance

	return inventory.id
end

exports('CreateTemporaryStash', Inventory.CreateTemporaryStash)

function Inventory.InspectInventory(playerId, invId)
	local inventory = invId ~= playerId and Inventory(invId)
	local playerInventory = Inventory(playerId)

	if playerInventory and inventory then
		playerInventory:openInventory(inventory)
		TriggerClientEvent('ox_inventory:viewInventory', playerId, playerInventory, inventory)
	end
end

exports('InspectInventory', Inventory.InspectInventory)

return Inventory
