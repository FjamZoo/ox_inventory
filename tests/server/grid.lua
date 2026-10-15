return function(context)
    local Fixture, test, equal = context.Fixture, context.test, context.equal

    test('a covered cell cannot receive another anchor', function()
        local fixture = Fixture.new(context.root)
        local inventory = fixture:inventory('overlap', 'stash', 30)

        equal(fixture.exports.AddItem(inventory.id, 'rifle', 1, nil, 1), true)

        local success = fixture.exports.AddItem(inventory.id, 'phone', 1, nil, 2)

        equal(success, false)
        equal({ rifle = inventory.items[1].name, weight = inventory.weight }, { rifle = 'rifle', weight = 4000 })
    end)

    test('a 4x2 item cannot anchor at the last cell', function()
        local fixture = Fixture.new(context.root)
        local inventory = fixture:inventory('off-edge', 'stash', 30)

        equal(fixture.exports.AddItem(inventory.id, 'phone', 1, nil, 1), true)

        local success = fixture.exports.AddItem(inventory.id, 'rifle', 1, nil, 30)

        equal(success, false)
        equal({ phone = inventory.items[1].name, weight = inventory.weight }, { phone = 'phone', weight = 100 })
    end)

    for _, suite in ipairs({
        'grid-insertion',
        'grid-moves',
        'grid-economy',
        'grid-recovery',
        'grid-mutations',
        'grid-esx',
        'grid-lifecycle',
        'grid-weapons'
    }) do
        assert(loadfile(context.root .. '/tests/server/' .. suite .. '.lua'))()(context)
    end
end
