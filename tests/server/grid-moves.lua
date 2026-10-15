return function(context)
    local Fixture, test, equal, slot = context.Fixture, context.test, context.equal, context.slot

    test('same-anchor rotation publishes the new orientation', function()
        local fixture = Fixture.new(context.root)
        local inventory = fixture:player(1)
        equal(fixture.exports.AddItem(1, 'rifle', 1, nil, 1), true)
        equal(fixture:call('ox_inventory:swapItems', 1, { fromType = 'player', toType = 'player', fromSlot = 1, toSlot = 1, count = 1, rotated = true }), true)
        equal({ slot(inventory.items[1]), inventory.items[1].rotated, inventory.weight }, {
            { name = 'rifle', slot = 1, count = 1, weight = 4000, metadata = {} }, true, 4000,
        })
    end)

    test('rotation rejection keeps the original rectangle and blocker', function()
        local fixture = Fixture.new(context.root)
        local inventory = fixture:player(1)
        equal(fixture.exports.AddItem(1, 'rifle', 1, nil, 1), true)
        equal(fixture.exports.AddItem(1, 'phone', 1, nil, 11), true)
        equal(fixture:call('ox_inventory:swapItems', 1, { fromType = 'player', toType = 'player', fromSlot = 1, toSlot = 1, count = 1, rotated = true }), false)
        equal({ slot(inventory.items[1]), inventory.items[1].rotated or false, slot(inventory.items[11]), inventory.weight }, {
            { name = 'rifle', slot = 1, count = 1, weight = 4000, metadata = {} }, false,
            { name = 'phone', slot = 11, count = 1, weight = 100, metadata = {} }, 4100,
        })
    end)

    test('full movement preserves an omitted rotated orientation', function()
        local fixture = Fixture.new(context.root)
        local inventory = fixture:player(1)
        equal(fixture.exports.AddItem(1, 'rifle', 1, nil, 1, nil, true), true)
        equal(fixture:call('ox_inventory:swapItems', 1, { fromType = 'player', toType = 'player', fromSlot = 1, toSlot = 2, count = 1 }), true)
        equal({ slot(inventory.items[1]), slot(inventory.items[2]), inventory.items[2].rotated, inventory.weight }, {
            false, { name = 'rifle', slot = 2, count = 1, weight = 4000, metadata = {} }, true, 4000,
        })
    end)

    test('full movement can occupy released source cells', function()
        local fixture = Fixture.new(context.root)
        local inventory = fixture:player(1)
        equal(fixture.exports.AddItem(1, 'rifle', 1, nil, 1), true)
        equal(fixture:call('ox_inventory:swapItems', 1, { fromType = 'player', toType = 'player', fromSlot = 1, toSlot = 2, count = 1 }), true)
        equal({ slot(inventory.items[1]), slot(inventory.items[2]), inventory.weight }, {
            false, { name = 'rifle', slot = 2, count = 1, weight = 4000, metadata = {} }, 4000,
        })
    end)

    test('splitting a multi-cell stack retains source occupancy', function()
        local fixture = Fixture.new(context.root)
        fixture.definitions.crate = { name = 'crate', label = 'Crate', weight = 100, stack = true, size = { width = 2, height = 2 } }
        local inventory = fixture:player(1)
        equal(fixture.exports.AddItem(1, 'crate', 4, nil, 1), true)
        equal(fixture:call('ox_inventory:swapItems', 1, { fromType = 'player', toType = 'player', fromSlot = 1, toSlot = 2, count = 2 }), false)
        equal(slot(inventory.items[1]), { name = 'crate', slot = 1, count = 4, weight = 400, metadata = {} })
        equal(fixture:call('ox_inventory:swapItems', 1, { fromType = 'player', toType = 'player', fromSlot = 1, toSlot = 3, count = 2 }), true)
        equal({ slot(inventory.items[1]), slot(inventory.items[3]), inventory.weight }, {
            { name = 'crate', slot = 1, count = 2, weight = 200, metadata = {} },
            { name = 'crate', slot = 3, count = 2, weight = 200, metadata = {} }, 400,
        })
    end)

    test('stacking retains the target orientation', function()
        local fixture = Fixture.new(context.root)
        fixture.definitions.bar = { name = 'bar', label = 'Bar', weight = 100, stack = true, size = { width = 2, height = 1 } }
        local inventory = fixture:player(1)
        equal(fixture.exports.AddItem(1, 'bar', 2, nil, 1), true)
        equal(fixture.exports.AddItem(1, 'bar', 3, nil, 3, nil, true), true)
        equal(fixture:call('ox_inventory:swapItems', 1, { fromType = 'player', toType = 'player', fromSlot = 1, toSlot = 3, count = 2, rotated = false }), true)
        equal({ slot(inventory.items[1]), slot(inventory.items[3]), inventory.items[3].rotated, inventory.weight }, {
            false, { name = 'bar', slot = 3, count = 5, weight = 500, metadata = {} }, true, 500,
        })
    end)

    test('swapping validates the two final rectangles together', function()
        local fixture = Fixture.new(context.root)
        local inventory = fixture:player(1)
        equal(fixture.exports.AddItem(1, 'rifle', 1, nil, 2), true)
        equal(fixture.exports.AddItem(1, 'phone', 1, nil, 1), true)
        equal(fixture:call('ox_inventory:swapItems', 1, { fromType = 'player', toType = 'player', fromSlot = 2, toSlot = 1, count = 1 }), false)
        equal({ slot(inventory.items[1]), slot(inventory.items[2]), inventory.weight }, {
            { name = 'phone', slot = 1, count = 1, weight = 100, metadata = {} },
            { name = 'rifle', slot = 2, count = 1, weight = 4000, metadata = {} }, 4100,
        })
    end)

    test('raw SwapSlots export rejects overweight final inventories', function()
        local fixture = Fixture.new(context.root)
        local from = fixture:inventory('from')
        local target = fixture:inventory('target', 'stash', 30, 1000)
        equal(fixture.exports.AddItem(from.id, 'rifle', 1, nil, 1), true)
        equal(fixture.exports.AddItem(target.id, 'phone', 1, nil, 1), true)
        equal(fixture.exports.SwapSlots(from, target, 1, 1), false)
        equal({ slot(from.items[1]), slot(target.items[1]), from.weight, target.weight }, {
            { name = 'rifle', slot = 1, count = 1, weight = 4000, metadata = {} },
            { name = 'phone', slot = 1, count = 1, weight = 100, metadata = {} }, 4000, 100,
        })
    end)

    test('raw SwapSlots export owns accepted cross-inventory weights', function()
        local fixture = Fixture.new(context.root)
        local from = fixture:inventory('raw-from')
        local target = fixture:inventory('raw-target')
        equal(fixture.exports.AddItem(from.id, 'rifle', 1, nil, 1), true)
        equal(fixture.exports.AddItem(target.id, 'phone', 1, nil, 11), true)
        fixture.exports.SwapSlots(from, target, 1, 11)
        equal({ slot(from.items[1]), slot(target.items[11]), from.weight, target.weight }, {
            { name = 'phone', slot = 1, count = 1, weight = 100, metadata = {} },
            { name = 'rifle', slot = 11, count = 1, weight = 4000, metadata = {} }, 100, 4000,
        })
    end)

    test('a supported hook mutation survives stale outer move rejection', function()
        local fixture = Fixture.new(context.root)
        local player = fixture:player(1)
        local target = fixture:inventory('hook-target')
        player:openInventory(target)
        equal(fixture.exports.AddItem(1, 'water', 2, nil, 1), true)
        fixture:addHook('swapItems', function()
            equal(fixture.exports.RemoveItem(1, 'water', 1, nil, 1), true)
        end)
        equal(fixture:call('ox_inventory:swapItems', 1, { fromType = 'player', toType = 'stash', fromSlot = 1, toSlot = 1, count = 1 }), false)
        equal({ slot(player.items[1]), slot(target.items[1]), player.weight, target.weight }, {
            { name = 'water', slot = 1, count = 1, weight = 250, metadata = {} }, false, 250, 0,
        })
    end)

    test('give preserves the rotated source footprint', function()
        local fixture = Fixture.new(context.root)
        local from = fixture:player(1)
        local target = fixture:player(2)
        equal(fixture.exports.AddItem(1, 'rifle', 1, nil, 1, nil, true), true)
        fixture:call('ox_inventory:giveItem', 1, 1, 2, 1)
        equal({ slot(from.items[1]), slot(target.items[1]), target.items[1].rotated, from.weight, target.weight }, {
            false, { name = 'rifle', slot = 1, count = 1, weight = 4000, metadata = {} }, true, 0, 4000,
        })
    end)

    for _, case in ipairs({ { name = 'omitted' }, { name = 'zero', count = 0 } }) do
        test('give keeps the established one-item default for ' .. case.name .. ' count', function()
            local fixture = Fixture.new(context.root)
            local from, target = fixture:player(1), fixture:player(2)
            equal(fixture.exports.AddItem(1, 'water', 2, nil, 1), true)
            fixture:call('ox_inventory:giveItem', 1, 1, 2, case.count)
            equal({ slot(from.items[1]), slot(target.items[1]), from.weight, target.weight }, {
                { name = 'water', slot = 1, count = 1, weight = 250, metadata = {} },
                { name = 'water', slot = 1, count = 1, weight = 250, metadata = {} }, 250, 250,
            })
        end)
    end

    test('drop preserves the rotated source footprint', function()
        local fixture = Fixture.new(context.root)
        local player = fixture:player(1)
        equal(fixture.exports.AddItem(1, 'rifle', 1, nil, 1, nil, true), true)
        equal(fixture:call('ox_inventory:swapItems', 1, { fromType = 'player', toType = 'newdrop', fromSlot = 1, toSlot = 1, count = 1, coords = vector3(0, 0, 0) }), true)
        local drops = fixture.exports.GetInventories('drop', true)
        equal(#drops, 1)
        equal({ slot(player.items[1]), slot(drops[1].items[1]), drops[1].items[1].rotated, player.weight, drops[1].weight }, {
            false, { name = 'rifle', slot = 1, count = 1, weight = 4000, metadata = {} }, true, 0, 4000,
        })
    end)

    test('container moves account for carried contents once', function()
        local fixture = Fixture.new(context.root)
        fixture.definitions.bag = { name = 'bag', label = 'Bag', weight = 100, stack = false }
        fixture.Items.containers.bag = {}
        local player = fixture:player(1)
        local container = fixture:inventory('bag-1', 'container', 10, 2000)
        equal(fixture.exports.AddItem(1, 'bag', 1, { container = 'bag-1', size = { 10, 2000 } }, 1), true)
        equal(fixture.exports.AddItem(1, 'water', 2, nil, 2), true)
        player:openInventory(container)
        player.containerSlot = 1
        equal(fixture:call('ox_inventory:swapItems', 1, { fromType = 'player', toType = 'container', fromSlot = 2, toSlot = 1, count = 1 }), 350)
        equal({ player.items[1].metadata.weight, player.items[1].weight, player.weight, container.weight, slot(player.items[2]), slot(container.items[1]) }, {
            250, 350, 600, 250,
            { name = 'water', slot = 2, count = 1, weight = 250, metadata = {} },
            { name = 'water', slot = 1, count = 1, weight = 250, metadata = {} },
        })
    end)

    local invalid = {
        { field = 'count', value = 0, name = 'zero count' },
        { field = 'count', value = -1, name = 'negative count' },
        { field = 'count', value = 1.5, name = 'fraction count' },
        { field = 'count', value = '1', name = 'string count' },
        { field = 'count', value = 0 / 0, name = 'NaN count' },
        { field = 'count', value = math.huge, name = 'infinite count' },
        { field = 'fromSlot', value = '1', name = 'string source' },
        { field = 'fromSlot', value = 0, name = 'zero source' },
        { field = 'fromSlot', value = 1.5, name = 'fraction source' },
        { field = 'toSlot', value = 0, name = 'zero destination' },
        { field = 'toSlot', value = '2', name = 'string destination' },
        { field = 'toSlot', value = 1.5, name = 'fraction destination' },
        { field = 'toSlot', value = 0 / 0, name = 'NaN destination' },
        { field = 'toSlot', value = math.huge, name = 'infinite destination' },
        { field = 'rotated', value = 'true', name = 'string rotation' },
        { field = 'rotated', value = 1, name = 'numeric rotation' },
        { field = 'fromType', value = {}, name = 'table source type' },
        { field = 'toType', value = 'inspect', name = 'inspect target' },
    }

    for _, case in ipairs(invalid) do
        test('swapItems rejects ' .. case.name .. ' without mutation', function()
            local fixture = Fixture.new(context.root)
            local inventory = fixture:player(1)
            equal(fixture.exports.AddItem(1, 'water', 2, nil, 1), true)
            local data = { fromType = 'player', toType = 'player', fromSlot = 1, toSlot = 2, count = 1 }
            data[case.field] = case.value
            equal(fixture:call('ox_inventory:swapItems', 1, data), false)
            equal({ slot(inventory.items[1]), slot(inventory.items[2]), inventory.weight }, {
                { name = 'water', slot = 1, count = 2, weight = 500, metadata = {} }, false, 500,
            })
        end)
    end
end
