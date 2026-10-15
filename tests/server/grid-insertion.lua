return function(context)
    local Fixture, test, equal, slot = context.Fixture, context.test, context.equal, context.slot

    test('item-table exports resolve canonical stack size and weight policy', function()
        local fixture = Fixture.new(context.root, { realItems = true })
        local inventory = fixture:player(1, 10)
        local forged = { name = 'rifle', label = 'Fake', weight = 0, stack = true }

        equal(fixture.exports.CanCarryItem(1, forged, 2), false)
        equal(fixture.exports.CanCarryAmount(1, forged), 1)
        equal(fixture.exports.AddItem(1, forged, 2, nil, 1), false)
        equal({ fixture.exports.GetItemCount(1, 'rifle'), inventory.weight }, { 0, 0 })
        equal(fixture.exports.AddItem(1, forged, 1, nil, 1), true)
        equal(
            { inventory.items[1].count, inventory.items[1].label, inventory.items[1].stack, inventory.weight },
            { 1, 'Rifle', false, 4000 }
        )
    end)

    test('planner rejects a multiple-count non-stack record without changing ownership', function()
        local fixture = Fixture.new(context.root)
        local inventory = fixture:player(1, 10)

        equal(
            fixture.Inventory.Assess({ {
                kind = 'add',
                inventory = inventory,
                record = { name = 'rifle', count = 2, metadata = {} }
            } }),
            nil
        )
        equal({ fixture.exports.GetItemCount(1, 'rifle'), inventory.weight }, { 0, 0 })
    end)

    test('item-table exports reject missing or invalid definition names', function()
        local fixture = Fixture.new(context.root, { realItems = true })
        local inventory = fixture:player(1)

        for _, item in ipairs({ {}, { name = false }, { name = 1 }, { name = {} }, { name = 'unknown' } }) do
            equal(fixture.exports.AddItem(1, item, 1), false)
            equal(fixture.exports.CanCarryItem(1, item, 1), false)
            equal(fixture.exports.CanCarryAmount(1, item), 0)
        end

        equal(fixture.exports.AddItem(1, nil, 1), false)
        equal({ inventory.weight, next(inventory.items) or false }, { 0, false })
    end)

    for _, destination in ipairs({ 2, 4, 30, 0, -1, 1.5, '2' }) do
        test('explicit AddItem rejects invalid or covered destination ' .. tostring(destination), function()
            local fixture = Fixture.new(context.root)
            local inventory = fixture:inventory('strict', 'stash', 30)

            equal(fixture.exports.AddItem(inventory.id, 'rifle', 1, nil, 1), true)
            equal(fixture.exports.AddItem(inventory.id, 'rifle', 1, nil, destination), false)
            equal({ slot(inventory.items[1]), inventory.weight, fixture.exports.GetItemCount(inventory.id, 'rifle') }, {
                { name = 'rifle', slot = 1, count = 1, weight = 4000, metadata = {} }, 4000, 1,
            })
        end)
    end

    test('AddItem rejects footprints crossing a partial final row', function()
        local fixture = Fixture.new(context.root)
        local inventory = fixture:inventory('partial', 'stash', 13)

        equal(fixture.exports.AddItem(inventory.id, 'phone', 1, nil, 5), true)
        equal(fixture.exports.AddItem(inventory.id, 'rifle', 1, nil, 6), false)
        equal({ slot(inventory.items[5]), inventory.weight }, {
            { name = 'phone', slot = 5, count = 1, weight = 100, metadata = {} }, 100,
        })
    end)

    test('non-stack batch addition fails without publishing a partial result', function()
        local fixture = Fixture.new(context.root)
        local inventory = fixture:inventory('batch', 'stash', 10)

        equal(fixture.exports.AddItem(inventory.id, 'phone', 1, nil, 10), true)
        equal(fixture.exports.AddItem(inventory.id, 'rifle', 2), false)
        equal({ slot(inventory.items[10]), inventory.weight, fixture.exports.GetItemCount(inventory.id, 'rifle') }, {
            { name = 'phone', slot = 10, count = 1, weight = 100, metadata = {} }, 100, 0,
        })
    end)

    test('non-stack batch addition allocates complete non-overlapping rectangles', function()
        local fixture = Fixture.new(context.root)
        local inventory = fixture:inventory('batch-fit', 'stash', 30)

        equal(fixture.exports.AddItem(inventory.id, 'rifle', 3), true)
        equal({ slot(inventory.items[1]), slot(inventory.items[11]), slot(inventory.items[21]), inventory.weight }, {
            { name = 'rifle', slot = 1, count = 1, weight = 4000, metadata = {} },
            { name = 'rifle', slot = 11, count = 1, weight = 4000, metadata = {} },
            { name = 'rifle', slot = 21, count = 1, weight = 4000, metadata = {} }, 12000,
        })
    end)

    test('AddItem includes metadata weight in its own cap check', function()
        local fixture = Fixture.new(context.root)
        local inventory = fixture:inventory('metadata-weight', 'stash', 30, 4100)

        equal(fixture.exports.AddItem(inventory.id, 'scrap', 1, nil, 5), true)
        equal(fixture.exports.AddItem(inventory.id, 'rifle', 1, { weight = 100 }, 1), false)
        equal({ slot(inventory.items[5]), inventory.weight }, {
            { name = 'scrap', slot = 5, count = 1, weight = 50, metadata = {} }, 50,
        })
    end)

    test('AddItem rejects an overweight batch without modifying existing records', function()
        local fixture = Fixture.new(context.root)
        local inventory = fixture:inventory('weight-batch', 'stash', 30, 5000)

        equal(fixture.exports.AddItem(inventory.id, 'phone', 1, nil, 5), true)
        equal(fixture.exports.AddItem(inventory.id, 'rifle', 2), false)
        equal({ slot(inventory.items[5]), inventory.weight, fixture.exports.GetItemCount(inventory.id, 'rifle') }, {
            { name = 'phone', slot = 5, count = 1, weight = 100, metadata = {} }, 100, 0,
        })
    end)

    test('carry and allocation exports derive their answer from covered cells', function()
        local fixture = Fixture.new(context.root)
        local inventory = fixture:inventory('capacity', 'stash', 10)

        equal(fixture.exports.AddItem(inventory.id, 'rifle', 1, nil, 1), true)
        equal(fixture.exports.CanCarryItem(inventory.id, 'rifle', 1), false)
        equal(fixture.exports.CanCarryItem(inventory.id, 'phone', 2), true)
        equal(fixture.exports.CanCarryItem(inventory.id, 'phone', 3), false)
        equal(fixture.exports.CanCarryAmount(inventory.id, 'phone'), 2)
        equal(fixture.exports.GetEmptySlot(inventory.id), 5)
        equal(fixture.exports.GetSlotForItem(inventory.id, 'phone'), 5)
        equal(inventory.weight, 4000)
    end)

    test('zero-weight non-stack carry amount is limited by geometry', function()
        local fixture = Fixture.new(context.root)

        fixture.definitions.card = { name = 'card', label = 'Card', weight = 0, stack = false }

        local inventory = fixture:inventory('zero-weight', 'stash', 10)

        equal(fixture.exports.AddItem(inventory.id, 'rifle', 1, nil, 1), true)
        equal(fixture.exports.CanCarryAmount(inventory.id, 'card'), 2)
        equal(fixture.exports.CanCarryItem(inventory.id, 'card', 3), false)
        equal(fixture.exports.AddItem(inventory.id, 'card', 2), true)
        equal({ slot(inventory.items[5]), slot(inventory.items[10]), inventory.weight }, {
            { name = 'card', slot = 5, count = 1, weight = 0, metadata = {} },
            { name = 'card', slot = 10, count = 1, weight = 0, metadata = {} }, 4000,
        })
    end)

    test('wide definitions fit when explicitly rotated', function()
        local fixture = Fixture.new(context.root)

        fixture.definitions.pole = {
            name = 'pole',
            label = 'Pole',
            weight = 100,
            stack = false,
            size = { width = 6, height = 1 }
        }

        local inventory = fixture:inventory('wide', 'stash', 30)

        equal(fixture.exports.AddItem(inventory.id, 'pole', 1, nil, 1), false)
        equal(fixture.exports.AddItem(inventory.id, 'pole', 1, nil, 5, nil, true), true)
        equal({ slot(inventory.items[5]), inventory.items[5].rotated, inventory.weight }, {
            { name = 'pole', slot = 5, count = 1, weight = 100, metadata = {} }, true, 100,
        })
    end)

    test('SetSlot cannot create a covered anchor', function()
        local fixture = Fixture.new(context.root)
        local inventory = fixture:inventory('set-slot', 'stash', 30)

        equal(fixture.Inventory.SetSlot(inventory, 'rifle', 1, {}, 1), true)
        equal(fixture.Inventory.SetSlot(inventory, 'phone', 1, {}, 2), false)
        equal({ slot(inventory.items[1]), inventory.weight }, {
            { name = 'rifle', slot = 1, count = 1, weight = 4000, metadata = {} }, 4000,
        })
    end)
end
