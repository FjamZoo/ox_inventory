return function(context)
    local Fixture, test, equal, slot = context.Fixture, context.test, context.equal, context.slot

    test('baseline accepts a phone inside a 4x2 rifle footprint', function()
        local fixture = Fixture.new(context.root)
        local inventory = fixture:inventory('overlap', 'stash', 30)

        equal(fixture.exports.AddItem(inventory.id, 'rifle', 1, nil, 1), true)
        equal(fixture.exports.AddItem(inventory.id, 'phone', 1, nil, 2), true)
        equal({ slot(inventory.items[1]), slot(inventory.items[2]), inventory.weight }, {
            { name = 'rifle', slot = 1, count = 1, weight = 4000, metadata = {} },
            { name = 'phone', slot = 2, count = 1, weight = 100, metadata = {} }, 4100,
        })
        print('BASELINE covered-cell AddItem returned true; rifle@1 and phone@2; weight=4100')
    end)

    test('baseline accepts a 4x2 rifle at the last cell', function()
        local fixture = Fixture.new(context.root)
        local inventory = fixture:inventory('off-edge', 'stash', 30)
        local success, item = fixture.exports.AddItem(inventory.id, 'rifle', 1, nil, 30)

        equal(success, true)
        equal(slot(item), { name = 'rifle', slot = 30, count = 1, weight = 4000, metadata = {} })
        equal(inventory.weight, 4000)
        print('BASELINE off-edge AddItem returned true; rifle@30 in 30 slots; weight=4000')
    end)

    test('baseline carry weight check rejects a second rifle', function()
        local fixture = Fixture.new(context.root)
        local inventory = fixture:inventory('weight', 'stash', 30, 5000)

        equal(fixture.exports.AddItem(inventory.id, 'rifle', 1, nil, 1), true)
        equal(fixture.exports.CanCarryItem(inventory.id, 'rifle', 1), false)
        equal(inventory.weight, 4000)
        print('BASELINE CanCarryItem returned false for 8000 total weight against maxWeight=5000')
    end)

    test('baseline AddItem itself does not enforce the weight cap', function()
        local fixture = Fixture.new(context.root)
        local inventory = fixture:inventory('raw-weight', 'stash', 30, 5000)

        equal(fixture.exports.AddItem(inventory.id, 'rifle', 1, nil, 1), true)
        equal(fixture.exports.AddItem(inventory.id, 'rifle', 1, nil, 2), true)
        equal(inventory.weight, 8000)
        print('BASELINE direct AddItem returned true at 8000 total weight against maxWeight=5000')
    end)
end
