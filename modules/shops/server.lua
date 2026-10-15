if not lib then return end

local Items = require 'modules.items.server'
local Inventory = require 'modules.inventory.server'
local TriggerEventHooks = require 'modules.hooks.server'
local Shops = {}
local Grid = require 'modules.inventory.grid'
local locations = shared.target and 'targets' or 'locations'

---@class OxShopItem
---@field slot number
---@field weight number

local function setupShopItems(id, shopType, shopName, groups)
	local shop = id and Shops[shopType][id] or Shops[shopType] --[[@as OxShop]]

	for i = 1, shop.slots do
		local slot = shop.items[i]

		if slot.grade and not groups then
			print(('^1attempted to restrict slot %s (%s) to grade %s, but %s has no job restriction^0'):format(id, slot.name, json.encode(slot.grade), shopName))
			slot.grade = nil
		end

		local Item = Items(slot.name)

		if Item then
			---@type OxShopItem
			slot = {
				name = Item.name,
				slot = i,
				weight = Item.weight,
				count = slot.count,
				price = (server.randomprices and (not slot.currency or slot.currency == 'money')) and (math.ceil(slot.price * (math.random(80, 120)/100))) or slot.price or 0,
				metadata = slot.metadata,
				license = slot.license,
				currency = slot.currency,
				grade = slot.grade
			}

			if slot.metadata then
				slot.weight = Inventory.SlotWeight(Item, slot, true)
			end

			shop.items[i] = slot
		end
	end
end

---@param shopType string
---@param properties OxShop
local function registerShopType(shopType, properties)
	local shopLocations = properties[locations] or properties.locations

	if shopLocations then
		Shops[shopType] = properties
	else
		Shops[shopType] = {
			label = properties.name,
			id = shopType,
			groups = properties.groups or properties.jobs,
			items = properties.inventory,
			slots = #properties.inventory,
			type = 'shop',
		}

		setupShopItems(nil, shopType, properties.name, properties.groups or properties.jobs)
	end
end

---@param shopType string
---@param id number
local function createShop(shopType, id)
	local shop = Shops[shopType]

	if not shop then return end

	local store = (shop[locations] or shop.locations)?[id]

	if not store then return end

	local groups = shop.groups or shop.jobs
    local coords

    if shared.target then
        if store.length then
            local z = store.loc.z + math.abs(store.minZ - store.maxZ) / 2
            coords = vec3(store.loc.x, store.loc.y, z)
        else
            coords = store.coords or store.loc
        end
    else
        coords = store
    end

	shop[id] = {
		label = shop.name,
		id = shopType..' '..id,
		groups = groups,
		items = table.clone(shop.inventory),
		slots = #shop.inventory,
		type = 'shop',
		coords = coords,
		distance = shared.target and shop.targets?[id]?.distance,
	}

	setupShopItems(id, shopType, shop.name, groups)

	return shop[id]
end

for shopType, shopDetails in pairs(lib.load('data.shops') or {}) do
	registerShopType(shopType, shopDetails)
end

---@param shopType string
---@param shopDetails OxShop
exports('RegisterShop', function(shopType, shopDetails)
	registerShopType(shopType, shopDetails)
end)

lib.callback.register('ox_inventory:openShop', function(source, data)
	local playerInv, shop = Inventory(source)

	if not playerInv then return end

	if data then
		shop = Shops[data.type]

		if not shop then return end

		if not shop.items then
			shop = (data.id and shop[data.id] or createShop(data.type, data.id))

			if not shop then return end
		end

		---@cast shop OxShop

		if shop.groups then
			local group = server.hasGroup(playerInv, shop.groups)
			if not group then return end
		end

		if type(shop.coords) == 'vector3' and #(GetEntityCoords(GetPlayerPed(source)) - shop.coords) > 10 then
			return
		end

		local shopType, shopId = shop.id:match('^(.-) (%d+)$')

        local hookPayload = {
            source = source,
            shopId = shopId or shop.id,
			shopType = shopType or shop.id,
            label = shop.label,
            slots = shop.slots,
            items = shop.items,
            groups = shop.groups,
            coords = shop.coords,
            distance = shop.distance
        }

        local hooks <close> = TriggerEventHooks('openShop', hookPayload)

		if not hooks.success then return end

		---@diagnostic disable-next-line: assign-type-mismatch
		playerInv:openInventory(playerInv)
		playerInv.currentShop = shop.id
	end

	return Inventory.Snapshot(playerInv), shop
end)

local function canAffordItem(inv, currency, price)
	local canAfford = price >= 0 and Inventory.GetItemCount(inv, currency) >= price

	return canAfford or {
		type = 'error',
		description = locale('cannot_afford', ('%s%s'):format((currency == 'money' and locale('$') or math.groupdigits(price)), (currency == 'money' and math.groupdigits(price) or ' '..Items(currency).label)))
	}
end

local function isRequiredGrade(grade, rank)
	if type(grade) == "table" then
		for i=1, #grade do
			if grade[i] == rank then
				return true
			end
		end
		return false
	else
		return rank >= grade
	end
end

lib.callback.register('ox_inventory:buyItem', function(source, data)
    if type(data) ~= 'table' or data.toType ~= 'player' or not Grid.Integer(data.fromSlot) or not Grid.Integer(data.toSlot)
        or not Grid.Integer(data.count) or (data.rotated ~= nil and type(data.rotated) ~= 'boolean') then return false end
    local inv = Inventory(source)
    if not inv or not inv.currentShop then return false end
    local shopType, shopId = inv.currentShop:match('^(.-) (%d+)$')
    shopType, shopId = shopType or inv.currentShop, tonumber(shopId)
    local shop = Shops[shopType]
    shop = shopId and shop and shop[shopId] or shop
    if not shop then return false end
    if shop.groups and not server.hasGroup(inv, shop.groups) then return false end
    if shop.coords and #(GetEntityCoords(GetPlayerPed(source)) - shop.coords) > 10 then return false end
    local offer = shop.items[data.fromSlot]
    if not offer then return false end
    local count = data.count
    if offer.count then
        count = math.min(count, offer.count)
        if count < 1 then return false, false, { type = 'error', description = locale('shop_nostock') } end
    end
    if offer.license and server.hasLicense and not server.hasLicense(inv, offer.license) then return false, false, { type = 'error', description = locale('item_unlicensed') } end
    if offer.grade then
        local _, rank = server.hasGroup(inv, shop.groups)
        if not rank or not isRequiredGrade(offer.grade, rank) then return false, false, { type = 'error', description = locale('stash_lowgrade') } end
    end
    local item, currency, revision = Items(offer.name), offer.currency or 'money', inv.revision
    if not item then return false end
    if item.cb and item.cb('buying', item, inv, data.fromSlot, shop) == false then return false end
    if Inventory(source) ~= inv or inv.revision ~= revision then return false end
    local credits, err = Inventory.PrepareItems(inv, item, count, offer.metadata or {}, data.toSlot, data.rotated)
    if not credits then return false, false, { type = 'error', description = locale(err) } end
    local price = count * offer.price
    if not Grid.Integer(price, 0) then return false end
    local affordable = canAffordItem(inv, currency, price)
    if affordable ~= true then return false, false, affordable end
    local commands = { { kind = 'remove', inventory = inv, name = currency, count = price } }
    if offer.count then commands[1].stock = { record = offer, expected = offer.count, count = count } end
    for _, credit in ipairs(credits) do commands[#commands + 1] = credit end
    local plan
    plan, err = Inventory.Assess(commands)
    if not plan then return false, false, { type = 'error', description = locale(err == 'cannot_carry' and err or 'inventory_full') } end
    local metadata = credits[1].record.metadata
    local hooks <close> = TriggerEventHooks('buyItem', {
        source = source, shopType = shopType, shopId = shopId or shopType, toInventory = inv.id, toSlot = data.toSlot,
        fromSlot = offer, itemName = item.name, metadata = metadata, count = count, price = offer.price, totalPrice = price, currency = currency,
    })
    if not hooks.success then return false end
    local success = Inventory.Apply(plan)
    if not success then
        hooks.success = false
        return false
    end

    TriggerClientEvent('ox_inventory:itemNotify', inv.id, { inv.items[data.toSlot], 'ui_added', count })
    local message = locale(
        'purchased_for',
        count,
        metadata.label or item.label,
        currency == 'money' and locale('$') or math.groupdigits(price),
        currency == 'money' and math.groupdigits(price) or ' ' .. Items(currency).label
    )

    if server.loglevel > 0 and (server.loglevel > 1 or offer.price >= 500) then
        lib.logger(inv.owner, 'buyItem', ('"%s" %s'):format(inv.label, message:lower()), ('shop:%s'):format(shop.label))
    end

    return true, { data.toSlot, inv.items[data.toSlot], offer.count and offer, inv.weight }, { type = 'success', description = message }
end)

server.shops = Shops
