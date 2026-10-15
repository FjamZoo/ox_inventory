return function(context)
    local Fixture, test, equal, slot = context.Fixture, context.test, context.equal, context.slot
    local bar = { name = 'bar', label = 'Bar', weight = 100, stack = false, size = { width = 2, height = 1 } }

    local function craftingFixture(output, ingredients)
        return Fixture.new(context.root, { items = { bar = bar }, data = { ['data.crafting'] = {
            workbench = { items = { { name = output, count = 1, ingredients = ingredients } } },
        } } })
    end

    test('shop rejects covered placement without charging money or stock', function()
        local fixture = Fixture.new(context.root)
        local inventory = fixture:player(1)

        fixture.exports.RegisterShop(
            'fixture',
            { name = 'Fixture shop', inventory = { { name = 'phone', price = 10, count = 3 } } }
        )
        equal(fixture.exports.AddItem(1, 'rifle', 1, nil, 1), true)
        equal(fixture.exports.AddItem(1, 'money', 50, nil, 5), true)
        fixture:call('ox_inventory:openShop', 1, { type = 'fixture' })
        equal(
            fixture:call('ox_inventory:buyItem', 1, { toType = 'player', fromSlot = 1, toSlot = 2, count = 1 }),
            false
        )
        equal({
            slot(inventory.items[1]),
            slot(inventory.items[5]),
            fixture.env.server.shops.fixture.items[1].count,
            inventory.weight
        }, {
            { name = 'rifle', slot = 1, count = 1, weight = 4000, metadata = {} },
            { name = 'money', slot = 5, count = 50, weight = 0, metadata = {} }, 3, 4000,
        })
    end)

    test('shop plans placement using cells freed by consumed currency', function()
        local fixture = Fixture.new(context.root, { items = { bar = bar } })
        local inventory = fixture:player(1, 2)

        fixture.exports.RegisterShop(
            'fixture',
            { name = 'Fixture shop', inventory = { { name = 'bar', price = 10, count = 3 } } }
        )
        equal(fixture.exports.AddItem(1, 'money', 10, nil, 1), true)
        fixture:call('ox_inventory:openShop', 1, { type = 'fixture' })
        equal(fixture:call('ox_inventory:buyItem', 1, { toType = 'player', fromSlot = 1, toSlot = 1, count = 1 }), true)
        equal({
            slot(inventory.items[1]),
            fixture.exports.GetItemCount(1, 'money'),
            fixture.env.server.shops.fixture.items[1].count,
            inventory.weight
        }, {
            { name = 'bar', slot = 1, count = 1, weight = 100, metadata = {} }, 0, 2, 100,
        })
    end)

    test('shop preserves independent hook mutation when its proposal becomes stale', function()
        local fixture = Fixture.new(context.root)
        local inventory = fixture:player(1)

        fixture.exports.RegisterShop(
            'fixture',
            { name = 'Fixture shop', inventory = { { name = 'water', price = 10, count = 3 } } }
        )
        equal(fixture.exports.AddItem(1, 'money', 50, nil, 1), true)
        fixture:call('ox_inventory:openShop', 1, { type = 'fixture' })
        fixture:addHook('buyItem', function() equal(fixture.exports.AddItem(1, 'phone', 1, nil, 6), true) end)
        equal(
            fixture:call('ox_inventory:buyItem', 1, { toType = 'player', fromSlot = 1, toSlot = 2, count = 1 }),
            false
        )
        equal({
            slot(inventory.items[1]),
            slot(inventory.items[2]),
            slot(inventory.items[6]),
            fixture.env.server.shops.fixture.items[1].count,
            inventory.weight
        }, {
            { name = 'money', slot = 1, count = 50, weight = 0, metadata = {} }, false,
            { name = 'phone', slot = 6, count = 1, weight = 100, metadata = {} }, 3, 100,
        })
    end)

    test('crafting plans placement using cells freed by consumed ingredients', function()
        local fixture = craftingFixture('bar', { scrap = 2 })
        local inventory = fixture:player(1, 2)

        equal(fixture.exports.AddItem(1, 'scrap', 2, nil, 1), true)
        equal(fixture:call('ox_inventory:craftItem', 1, 'workbench', 1, 1, 1), true)
        equal({ slot(inventory.items[1]), fixture.exports.GetItemCount(1, 'scrap'), inventory.weight }, {
            { name = 'bar', slot = 1, count = 1, weight = 100, metadata = {} }, 0, 100,
        })
    end)

    test('crafting rejects covered output before progress or ingredient consumption', function()
        local fixture = craftingFixture('phone', { scrap = 2 })
        local inventory = fixture:player(1)

        equal(fixture.exports.AddItem(1, 'rifle', 1, nil, 1), true)
        equal(fixture.exports.AddItem(1, 'scrap', 2, nil, 5), true)

        local progressCount = 0

        fixture.await['ox_inventory:startCrafting'] = function()
            progressCount += 1

            return true
        end

        equal(fixture:call('ox_inventory:craftItem', 1, 'workbench', 1, 1, 2), false)
        equal({ slot(inventory.items[1]), slot(inventory.items[5]), inventory.weight, progressCount }, {
            { name = 'rifle', slot = 1, count = 1, weight = 4000, metadata = {} },
            { name = 'scrap', slot = 5, count = 2, weight = 100, metadata = {} }, 4100, 0,
        })
    end)

    test('crafting revalidates ingredients after progress without undoing independent removal', function()
        local fixture = craftingFixture('phone', { scrap = 2 })
        local inventory = fixture:player(1)

        equal(fixture.exports.AddItem(1, 'scrap', 3, nil, 1), true)
        fixture.await['ox_inventory:startCrafting'] = function()
            equal(fixture.exports.RemoveItem(1, 'scrap', 2, nil, 1), true)

            return true
        end

        equal(fixture:call('ox_inventory:craftItem', 1, 'workbench', 1, 1, 2), false)
        equal({ slot(inventory.items[1]), slot(inventory.items[2]), inventory.weight }, {
            { name = 'scrap', slot = 1, count = 1, weight = 50, metadata = {} }, false, 50,
        })
    end)

    test('crafting preserves completion-hook mutation and rejects stale consumption', function()
        local fixture = craftingFixture('phone', { scrap = 2 })
        local inventory = fixture:player(1)

        equal(fixture.exports.AddItem(1, 'scrap', 3, nil, 1), true)

        local progressed = false

        fixture.await['ox_inventory:startCrafting'] = function()
            progressed = true

            return true
        end

        fixture:addHook('craftItem', function()
            equal(progressed, true)
            equal(fixture.exports.AddItem(1, 'water', 1, nil, 6), true)
        end)
        equal(fixture:call('ox_inventory:craftItem', 1, 'workbench', 1, 1, 2), false)
        equal({ slot(inventory.items[1]), slot(inventory.items[2]), slot(inventory.items[6]), inventory.weight }, {
            { name = 'scrap', slot = 1, count = 3, weight = 150, metadata = {} }, false,
            { name = 'water', slot = 6, count = 1, weight = 250, metadata = {} }, 400,
        })
    end)

    for _, value in ipairs({ 0, -1, 1.5, '1', math.huge, 0 / 0 }) do
        test('shop rejects invalid count ' .. tostring(value) .. ' without charging', function()
            local fixture = Fixture.new(context.root)
            local inventory = fixture:player(1)

            fixture.exports.RegisterShop(
                'fixture',
                { name = 'Fixture shop', inventory = { { name = 'water', price = 10, count = 3 } } }
            )
            equal(fixture.exports.AddItem(1, 'money', 50, nil, 1), true)
            fixture:call('ox_inventory:openShop', 1, { type = 'fixture' })
            equal(
                fixture:call('ox_inventory:buyItem', 1, { toType = 'player', fromSlot = 1, toSlot = 2, count = value }),
                false
            )
            equal({
                slot(inventory.items[1]),
                slot(inventory.items[2]),
                fixture.env.server.shops.fixture.items[1].count,
                inventory.weight
            }, {
                { name = 'money', slot = 1, count = 50, weight = 0, metadata = {} }, false, 3, 0,
            })
        end)
    end
end
