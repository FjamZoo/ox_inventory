return function(context)
    local Fixture, test, equal = context.Fixture, context.test, context.equal
    local Client = assert(loadfile(context.root .. '/tests/server/client-update-fixture.lua'))()
    local function setup()
        local fixture = Fixture.new(context.root)
        local inventory = fixture:player(1)
        equal(fixture.exports.AddItem(1, 'rifle', 1, { serial = 'equipped' }, 1), true)
        inventory.weapon = 1
        return fixture, inventory, Client.new(context.root, fixture, 1, 1)
    end

    for _, operation in ipairs({ 'move', 'swap', 'rotate', 'raw swap' }) do
        test('authoritative ' .. operation .. ' preserves the equipped weapon before old-anchor deletion', function()
            local fixture, inventory, client = setup()
            if operation == 'swap' or operation == 'raw swap' then equal(fixture.exports.AddItem(1, 'phone', 1, nil, 11), true) end
            local destination = operation == 'rotate' and 1 or 11
            local send = fixture.env.TriggerClientEvent
            fixture.env.TriggerClientEvent = function(name, target, ...)
                if name == 'ox_inventory:updateSlots' and target == 1 then equal(inventory.weapon, destination) end
                send(name, target, ...)
            end
            if operation == 'raw swap' then
                fixture.exports.SwapSlots(1, 1, 1, destination)
            else
                equal(fixture:call('ox_inventory:swapItems', 1, { fromType = 'player', toType = 'player', fromSlot = 1, toSlot = destination, count = 1, rotated = operation == 'rotate' or nil }), true)
            end
            equal({ client.disarms, client.env.currentWeapon and client.env.currentWeapon.slot, inventory.weapon, client.env.currentWeapon and client.env.currentWeapon.metadata.serial }, { 0, destination, destination, 'equipped' })
        end)
    end

    for _, operation in ipairs({ 'give', 'remove', 'exchange' }) do
        test('authoritative ' .. operation .. ' disarms a departing equipped weapon', function()
            local fixture, inventory, client = setup()
            local other = fixture:player(2)
            if operation == 'give' then fixture:call('ox_inventory:giveItem', 1, 1, 2, 1)
            elseif operation == 'remove' then equal(fixture.exports.RemoveItem(1, 'rifle', 1, nil, 1), true)
            else
                equal(fixture.exports.AddItem(2, 'phone', 1, nil, 1), true)
                inventory:openInventory(other)
                equal(fixture:call('ox_inventory:swapItems', 1, { fromType = 'player', toType = 'otherplayer', fromSlot = 1, toSlot = 1, count = 1 }), true)
            end
            equal({ client.disarms, client.env.currentWeapon or false, inventory.weapon or false }, { 1, false, false })
        end)
    end

    test('swapping another item into the equipped anchor follows the displaced weapon', function()
        local fixture, inventory, client = setup()
        equal(fixture.exports.AddItem(1, 'phone', 1, nil, 11), true)
        equal(fixture:call('ox_inventory:swapItems', 1, { fromType = 'player', toType = 'player', fromSlot = 11, toSlot = 1, count = 1 }), true)
        equal({ inventory.weapon, client.env.currentWeapon.slot, client.env.currentWeapon.metadata.serial, client.disarms }, { 11, 11, 'equipped', 0 })
    end)

    test('rejected cross-inventory movement retains the equipped weapon', function()
        local fixture, inventory, client = setup()
        local target = fixture:inventory('weapon-reject', 'stash', 1)
        inventory:openInventory(target)
        local accepted
        client.callbacks.swapItems({ fromType = 'player', toType = 'stash', fromSlot = 1, toSlot = 1, count = 1 }, function(value) accepted = value end)
        equal({ accepted, inventory.weapon, client.env.currentWeapon.slot, client.disarms }, { false, 1, 1, 0 })
    end)

    test('equipped anchor mapping is private to the inventory owner', function()
        local fixture, inventory, client = setup()
        local viewer = fixture:player(2)
        viewer:openInventory(inventory)
        equal(fixture:call('ox_inventory:swapItems', 1, { fromType = 'player', toType = 'player', fromSlot = 1, toSlot = 11, count = 1 }), true)
        local messages = {}
        for _, event in ipairs(fixture.clientEvents) do
            if event.name == 'ox_inventory:updateSlots' and event.target == 2 then messages[#messages + 1] = { event.target, event.args[3] or 'absent' } end
        end
        equal(messages, { { 2, 'absent' } })
        equal({ client.env.currentWeapon.slot, client.disarms }, { 11, 0 })
    end)

    test('a late swap callback cannot restore an older equipped anchor', function()
        local fixture, inventory, client = setup()
        client.env.lib.callback.await = function(name, _, data)
            equal(fixture:call(name, 1, data), true)
            equal(fixture:call(name, 1, { fromType = 'player', toType = 'player', fromSlot = 11, toSlot = 16, count = 1 }), true)
            return true, nil, 11
        end
        local accepted
        client.callbacks.swapItems({ fromType = 'player', toType = 'player', fromSlot = 1, toSlot = 11, count = 1 }, function(value) accepted = value end)
        equal({ accepted, inventory.weapon, client.env.currentWeapon and client.env.currentWeapon.slot, client.disarms }, { true, 16, 16, 0 })
    end)

    test('legacy updateSlots without weapon mapping retains equipped metadata updates', function()
        local fixture, _, client = setup()
        local record = fixture.env.table.deepclone(fixture.Inventory(1).items[1])
        record.metadata.ammo = 7
        client.handlers['ox_inventory:updateSlots']({ { item = record, inventory = 1 } }, 4000)
        equal({ client.env.currentWeapon.slot, client.env.currentWeapon.metadata.ammo, client.disarms }, { 1, 7, 0 })
    end)
end
