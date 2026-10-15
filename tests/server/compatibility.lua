return function(context)
    local Fixture, test, equal, slot = context.Fixture, context.test, context.equal, context.slot

    test('AddItem export stacks 1x1 items and preserves metadata', function()
        local fixture = Fixture.new(context.root)
        local inventory = fixture:inventory('stack')
        local success, item = fixture.exports.AddItem(inventory.id, 'water', 2, { type = 'spring' }, 7)
        equal(success, true)
        equal(slot(item), { name = 'water', slot = 7, count = 2, weight = 500, metadata = { type = 'spring' } })
        equal(fixture.exports.AddItem(inventory.id, 'water', 1, { type = 'spring' }), true)
        equal(slot(inventory.items[7]), { name = 'water', slot = 7, count = 3, weight = 750, metadata = { type = 'spring' } })
        equal(inventory.weight, 750)
        equal(fixture.exports.GetItemCount(inventory.id, 'water'), 3)
    end)

    test('AddItem export allocates separate non-stack items', function()
        local fixture = Fixture.new(context.root)
        local inventory = fixture:inventory('phones', 'stash', 3)
        local success, items = fixture.exports.AddItem(inventory.id, 'phone', 2)
        equal(success, true)
        equal({ slot(items[1]), slot(items[2]) }, {
            { name = 'phone', slot = 1, count = 1, weight = 100, metadata = {} },
            { name = 'phone', slot = 2, count = 1, weight = 100, metadata = {} },
        })
        equal(inventory.weight, 200)
        equal(fixture.exports.GetEmptySlot(inventory.id), 3)
    end)

    test('RemoveItem export releases the anchor and subtracts weight', function()
        local fixture = Fixture.new(context.root)
        local inventory = fixture:inventory('remove')
        equal(fixture.exports.AddItem(inventory.id, 'water', 3, nil, 4), true)
        equal(fixture.exports.RemoveItem(inventory.id, 'water', 2, nil, 4), true)
        equal(slot(inventory.items[4]), { name = 'water', slot = 4, count = 1, weight = 250, metadata = {} })
        equal(fixture.exports.RemoveItem(inventory.id, 'water', 1, nil, 4), true)
        equal({ remaining = slot(inventory.items[4]), weight = inventory.weight }, { remaining = false, weight = 0 })
    end)

    test('CanCarryItem export enforces weight separately from empty anchors', function()
        local fixture = Fixture.new(context.root)
        local inventory = fixture:inventory('weight', 'stash', 30, 500)
        equal(fixture.exports.AddItem(inventory.id, 'water', 1), true)
        equal(fixture.exports.CanCarryItem(inventory.id, 'water', 1), true)
        equal(fixture.exports.CanCarryItem(inventory.id, 'water', 2), false)
        local canCarry, available = fixture.exports.CanCarryWeight(inventory.id, 251)
        equal({ canCarry, available }, { false, 250 })
        equal(inventory.weight, 250)
    end)

    test('swapItems callback splits and stacks 1x1 items', function()
        local fixture = Fixture.new(context.root)
        local inventory = fixture:player(1)
        equal(fixture.exports.AddItem(1, 'water', 4, nil, 1), true)
        equal(fixture:call('ox_inventory:swapItems', 1, { fromType = 'player', toType = 'player', fromSlot = 1, toSlot = 4, count = 2 }), true)
        equal({ slot(inventory.items[1]), slot(inventory.items[4]), inventory.weight }, {
            { name = 'water', slot = 1, count = 2, weight = 500, metadata = {} },
            { name = 'water', slot = 4, count = 2, weight = 500, metadata = {} },
            1000,
        })
        equal(fixture:call('ox_inventory:swapItems', 1, { fromType = 'player', toType = 'player', fromSlot = 4, toSlot = 1, count = 2 }), true)
        equal({ slot(inventory.items[1]), slot(inventory.items[4]), inventory.weight }, {
            { name = 'water', slot = 1, count = 4, weight = 1000, metadata = {} }, false, 1000,
        })
    end)

    test('swapItems callback rejects overweight cross-inventory movement', function()
        local fixture = Fixture.new(context.root)
        local player = fixture:player(1)
        local stash = fixture:inventory('small', 'stash', 30, 100)
        player:openInventory(stash)
        equal(fixture.exports.AddItem(1, 'water', 1, nil, 1), true)
        local success, reason = fixture:call('ox_inventory:swapItems', 1, { fromType = 'player', toType = 'stash', fromSlot = 1, toSlot = 1, count = 1 })
        equal({ success, reason }, { false, 'cannot_carry_other' })
        equal({ slot(player.items[1]), slot(stash.items[1]), player.weight, stash.weight }, {
            { name = 'water', slot = 1, count = 1, weight = 250, metadata = {} }, false, 250, 0,
        })
    end)

    test('swapItems callback swaps distinct 1x1 anchors', function()
        local fixture = Fixture.new(context.root)
        local inventory = fixture:player(1)
        equal(fixture.exports.AddItem(1, 'phone', 1, nil, 1), true)
        equal(fixture.exports.AddItem(1, 'water', 2, nil, 2), true)
        equal(fixture:call('ox_inventory:swapItems', 1, { fromType = 'player', toType = 'player', fromSlot = 1, toSlot = 2, count = 1 }), true)
        equal({ slot(inventory.items[1]), slot(inventory.items[2]), inventory.weight }, {
            { name = 'water', slot = 1, count = 2, weight = 500, metadata = {} },
            { name = 'phone', slot = 2, count = 1, weight = 100, metadata = {} }, 600,
        })
    end)

    test('real save/load methods round-trip sparse records through persistence', function()
        local fixture = Fixture.new(context.root)
        local inventory = fixture:inventory('saved')
        equal(fixture.exports.AddItem(inventory.id, 'water', 2, { type = 'spring' }, 7), true)
        equal(fixture.Inventory.Save(inventory.id), true)
        equal(fixture:decode(fixture.writes[1].payload), {
            { name = 'water', count = 2, slot = 7, metadata = { type = 'spring' } },
        })
        local loaded = fixture.Inventory.Create('saved', 'Saved', 'stash', 30, 0, 30000, false)
        equal(slot(loaded.items[7]), { name = 'water', slot = 7, count = 2, weight = 500, metadata = { type = 'spring' } })
        equal(loaded.weight, 500)
    end)

    test('shop callback pays currency and decrements stock', function()
        local fixture = Fixture.new(context.root)
        local inventory = fixture:player(1)
        fixture.exports.RegisterShop('fixture', { name = 'Fixture shop', inventory = { { name = 'water', price = 10, count = 3 } } })
        equal(fixture.exports.AddItem(1, 'money', 50, nil, 1), true)
        fixture:call('ox_inventory:openShop', 1, { type = 'fixture' })
        local success, response = fixture:call('ox_inventory:buyItem', 1, { toType = 'player', fromSlot = 1, toSlot = 2, count = 2 })
        equal(success, true)
        equal(slot(response[2]), { name = 'water', slot = 2, count = 2, weight = 500, metadata = {} })
        equal({ money = inventory.items[1].count, stock = fixture.env.server.shops.fixture.items[1].count, weight = inventory.weight }, { money = 30, stock = 1, weight = 500 })
    end)

    test('craft callback consumes ingredients and adds output', function()
        local fixture = Fixture.new(context.root, { data = { ['data.crafting'] = {
            workbench = { items = { { name = 'phone', count = 1, ingredients = { scrap = 2 } } } },
        } } })
        local inventory = fixture:player(1)
        equal(fixture.exports.AddItem(1, 'scrap', 3, nil, 1), true)
        equal(fixture:call('ox_inventory:craftItem', 1, 'workbench', 1, 1, 2), true)
        equal({ slot(inventory.items[1]), slot(inventory.items[2]), inventory.weight }, {
            { name = 'scrap', slot = 1, count = 1, weight = 50, metadata = {} },
            { name = 'phone', slot = 2, count = 1, weight = 100, metadata = {} }, 150,
        })
    end)

    test('swapItems hook rejection preserves both inventories', function()
        local fixture = Fixture.new(context.root)
        local player = fixture:player(1)
        local stash = fixture:inventory('veto')
        player:openInventory(stash)
        equal(fixture.exports.AddItem(1, 'water', 2, nil, 1), true)
        local payload
        fixture:addHook('swapItems', function(value)
            payload = { action = value.action, fromInventory = value.fromInventory, toInventory = value.toInventory, count = value.count }
            return false
        end)
        fixture:call('ox_inventory:swapItems', 1, { fromType = 'player', toType = 'stash', fromSlot = 1, toSlot = 3, count = 1 })
        equal(payload, { action = 'move', fromInventory = 1, toInventory = 'veto', count = 1 })
        equal({ slot(player.items[1]), slot(stash.items[3]), player.weight, stash.weight }, {
            { name = 'water', slot = 1, count = 2, weight = 500, metadata = {} }, false, 500, 0,
        })
    end)

    test('confiscate and return exports restore sparse records', function()
        local fixture = Fixture.new(context.root)
        local inventory = fixture:player(1)
        equal(fixture.exports.AddItem(1, 'water', 2, { type = 'spring' }, 7), true)
        fixture.exports.ConfiscateInventory(1)
        equal({ slot(inventory.items[7]), inventory.weight }, { false, 0 })
        equal(fixture:decode(fixture.writes[1].payload), {
            { name = 'water', count = 2, slot = 7, metadata = { type = 'spring' } },
        })
        fixture.exports.ReturnInventory(1)
        equal({ slot(inventory.items[7]), inventory.weight }, {
            { name = 'water', slot = 7, count = 2, weight = 500, metadata = { type = 'spring' } }, 500,
        })
    end)

    test('root server export reconstructs a saved player inventory', function()
        local fixture = Fixture.new(context.root, { loadServer = true })
        fixture.env.db.savePlayer('loaded-player', fixture.env.json.encode({
            { name = 'water', slot = 7, count = 2, metadata = { type = 'spring' } },
        }))
        fixture.exports.setPlayerInventory({ source = '1', identifier = 'loaded-player', name = 'Saved player' })
        local inventory = fixture.exports.GetInventory(1)
        equal({ slot(inventory.items[7]), inventory.weight, inventory.owner, inventory.player.ped }, {
            { name = 'water', slot = 7, count = 2, weight = 500, metadata = { type = 'spring' } }, 500, 'loaded-player', 1,
        })
    end)
end
