return function(context)
    local Fixture, test, equal, slot = context.Fixture, context.test, context.equal, context.slot

    local function loadStash(fixture, id, slots, records)
        fixture.env.db.saveStash(false, id, fixture.env.json.encode(records))
        return fixture.Inventory.Create(id, id, 'stash', slots, 0, 30000, false)
    end

    test('non-stack saved multiplicity stays intact in weighted invalid-record recovery', function()
        local fixture = Fixture.new(context.root)
        local player = fixture:player(1)
        local record = { name = 'rifle', count = 2, slot = 1, metadata = { serial = 'legacy' }, custom = 'retain' }
        local inventory = loadStash(fixture, 'legacy-multiple', 10, { record })
        equal({ fixture.exports.GetItemCount(inventory.id, 'rifle'), inventory.weight, inventory.unknownWeight, inventory.recovery[1].reason, inventory.recovery[1].record }, { 0, 8000, false, 'invalid_record', record })
        player:openInventory(inventory)
        equal(fixture:call('ox_inventory:recoverItem', 1, { fromType = 'stash', recoveryId = inventory.recovery[1].id }), false)
        equal({ inventory.weight, #inventory.recovery }, { 8000, 1 })
    end)

    for _, saveMethod in ipairs({ 'Remove', 'SaveInventories' }) do
        test(saveMethod .. ' persists untouched load-time recovery before a missing definition returns', function()
            local fixture = Fixture.new(context.root)
            local inventory = loadStash(fixture, 'new-recovery', 10, { { name = 'missing', count = 1, slot = 1 } })
            if saveMethod == 'Remove' then fixture.Inventory.Remove(inventory)
            else fixture.Inventory.SaveInventories(false, false) fixture.Inventory.Remove(inventory) end
            fixture.definitions.missing = { name = 'missing', label = 'Restored', stack = true, weight = 50 }
            local loaded = fixture.Inventory.Create('new-recovery', 'new-recovery', 'stash', 10, 0, 30000, false)
            equal({ fixture.exports.GetItemCount(loaded.id, 'missing'), #loaded.recovery, loaded.recovery[1] and loaded.recovery[1].reason, loaded.weight }, { 0, 1, 'unknown_item', 50 })
            equal(fixture:decode(fixture.persisted.stash[':new-recovery'])[1]._gridRecovery.record, { name = 'missing', count = 1, slot = 1 })
        end)
    end

    test('load-time relocation persists without a later inventory mutation', function()
        local fixture = Fixture.new(context.root)
        local inventory = loadStash(fixture, 'relocation-save', 30, { { name = 'rifle', count = 1, slot = 3 } })
        fixture.Inventory.Remove(inventory)
        equal(fixture:decode(fixture.persisted.stash[':relocation-save']), { { name = 'rifle', count = 1, slot = 1 } })
    end)

    test('existing recovery does not dirty an otherwise unchanged loaded inventory', function()
        local fixture = Fixture.new(context.root)
        local record = { _gridRecovery = { id = 'old-owned', reason = 'unknown_item', record = { name = 'missing', count = 1, slot = 1 } } }
        local inventory = loadStash(fixture, 'unchanged-recovery', 10, { record })
        equal({ inventory.changed, #inventory.recovery }, { false, 1 })
        fixture.Inventory.Remove(inventory)
        equal(#fixture.writes, 1)
        equal(fixture:decode(fixture.persisted.stash[':unchanged-recovery']), { record })
    end)

    test('reconciliation reserves later valid anchors before relocating displaced items', function()
        local fixture = Fixture.new(context.root)
        local inventory = loadStash(fixture, 'two-pass', 30, {
            { name = 'rifle', count = 1, slot = 3, metadata = {} },
            { name = 'phone', count = 1, slot = 8, metadata = {} },
        })
        equal({ slot(inventory.items[8]), slot(inventory.items[11]), inventory.weight, #inventory.recovery }, {
            { name = 'phone', slot = 8, count = 1, weight = 100, metadata = {} },
            { name = 'rifle', slot = 11, count = 1, weight = 4000, metadata = {} }, 4100, 0,
        })
    end)

    test('overflow remains owned recovery weight and is excluded from ordinary searches', function()
        local fixture = Fixture.new(context.root)
        local inventory = loadStash(fixture, 'overflow', 10, {
            { name = 'rifle', count = 1, slot = 1, metadata = { serial = 'first' } },
            { name = 'rifle', count = 1, slot = 2, metadata = { serial = 'second' }, custom = 'preserved' },
        })
        equal({ slot(inventory.items[1]), inventory.weight, fixture.exports.GetItemCount(inventory.id, 'rifle'), #inventory.recovery }, {
            { name = 'rifle', slot = 1, count = 1, weight = 4000, metadata = { serial = 'first' } }, 8000, 1, 1,
        })
        equal({ reason = inventory.recovery[1].reason, record = inventory.recovery[1].record }, {
            reason = 'no_space', record = { name = 'rifle', count = 1, slot = 2, metadata = { serial = 'second' }, custom = 'preserved' },
        })
    end)

    test('reclaim charges no second weight for an owned recovery record', function()
        local fixture = Fixture.new(context.root)
        local player = fixture:player(1)
        local inventory = loadStash(fixture, 'reclaim', 10, {
            { name = 'rifle', count = 1, slot = 1, metadata = { serial = 'first' } },
            { name = 'rifle', count = 1, slot = 2, metadata = { serial = 'second' } },
        })
        player:openInventory(inventory)
        local id = inventory.recovery[1].id
        equal(fixture:call('ox_inventory:recoverItem', 1, { fromType = 'stash', recoveryId = id, toSlot = 1 }), false)
        equal({ inventory.weight, #inventory.recovery, fixture.exports.GetItemCount(inventory.id, 'rifle') }, { 8000, 1, 1 })
        equal(fixture.exports.RemoveItem(inventory.id, 'rifle', 1, nil, 1), true)
        equal(inventory.weight, 4000)
        equal(fixture:call('ox_inventory:recoverItem', 1, { fromType = 'stash', recoveryId = id, toSlot = 1 }), true)
        equal({ slot(inventory.items[1]), inventory.weight, #inventory.recovery }, {
            { name = 'rifle', slot = 1, count = 1, weight = 4000, metadata = { serial = 'second' } }, 4000, 0,
        })
    end)

    test('unknown saved records survive tagged save/load and block acquisition', function()
        local fixture = Fixture.new(context.root)
        local original = { name = 'missing', count = 2, slot = 4, metadata = { tag = 'keep' }, custom = 'preserved' }
        local inventory = loadStash(fixture, 'unknown', 30, {
            { name = 'water', count = 1, slot = 1, metadata = {} }, original,
        })
        equal({ slot(inventory.items[1]), inventory.weight, #inventory.recovery, inventory.recovery[1].reason, inventory.recovery[1].record }, {
            { name = 'water', slot = 1, count = 1, weight = 250, metadata = {} }, 250, 1, 'unknown_item', original,
        })
        equal(fixture.exports.AddItem(inventory.id, 'phone', 1, nil, 2), false)
        equal(fixture.exports.CanCarryItem(inventory.id, 'phone', 1), false)
        local stableId = inventory.recovery[1].id
        equal(fixture.Inventory.Save(inventory), true)
        local saved = fixture:decode(fixture.writes[#fixture.writes].payload)
        local envelope
        for _, record in ipairs(saved) do if record._gridRecovery then envelope = record._gridRecovery end end
        equal({ id = envelope.id, reason = envelope.reason, record = envelope.record }, { id = stableId, reason = 'unknown_item', record = original })
        local loaded = fixture.Inventory.Create('unknown', 'Unknown', 'stash', 30, 0, 30000, false)
        equal({ loaded.recovery[1].id, loaded.recovery[1].record, loaded.weight }, { stableId, original, 250 })
        equal(fixture.exports.RemoveItem(loaded.id, 'water', 1, nil, 1), true)
        equal({ slot(loaded.items[1]), #loaded.recovery, loaded.weight }, { false, 1, 0 })
    end)

    test('unknown recovery permits withdrawal into an existing compatible target stack', function()
        local fixture = Fixture.new(context.root)
        local player = fixture:player(1)
        equal(fixture.exports.AddItem(1, 'water', 3, nil, 1), true)
        local inventory = loadStash(fixture, 'unknown-withdrawal', 30, {
            { name = 'water', count = 2, slot = 1 }, { name = 'missing', count = 1, slot = 7, custom = 'keep' },
        })
        player:openInventory(inventory)
        equal(fixture:call('ox_inventory:swapItems', 1, { fromType = 'stash', toType = 'player', fromSlot = 1, toSlot = 1, count = 2 }), true)
        equal({ slot(player.items[1]), slot(inventory.items[1]), inventory.weight, #inventory.recovery, inventory.recovery[1].record, player.weight }, {
            { name = 'water', slot = 1, count = 5, weight = 1250, metadata = {} }, false, 0, 1,
            { name = 'missing', count = 1, slot = 7, custom = 'keep' }, 1250,
        })
    end)

    test('invalid saved records are preserved verbatim in recovery', function()
        local fixture = Fixture.new(context.root)
        local original = { name = 'water', count = 0, slot = 2, metadata = { tag = 'keep' }, custom = 17 }
        local inventory = loadStash(fixture, 'invalid', 30, {
            { name = 'phone', count = 1, slot = 1, metadata = {} }, original,
        })
        equal({ slot(inventory.items[1]), #inventory.recovery, inventory.recovery[1].reason, inventory.recovery[1].record, inventory.weight }, {
            { name = 'phone', slot = 1, count = 1, weight = 100, metadata = {} }, 1, 'invalid_record', original, 100,
        })
    end)

    test('existing recovery envelopes stay inactive even when there is free space', function()
        local fixture = Fixture.new(context.root)
        local record = { name = 'phone', count = 1, slot = 1, metadata = { tag = 'keep' } }
        local inventory = loadStash(fixture, 'envelope', 30, {
            { _gridRecovery = { id = 'stable-record', reason = 'no_space', record = record } },
            { name = 'water', count = 1, slot = 7, metadata = {} },
        })
        equal({ slot(inventory.items[7]), slot(inventory.items[1]), inventory.weight, inventory.recovery }, {
            { name = 'water', slot = 7, count = 1, weight = 250, metadata = {} }, false, 350,
            { { id = 'stable-record', reason = 'no_space', record = record } },
        })
    end)

    test('resize moves excess items into recovery while retaining their weight', function()
        local fixture = Fixture.new(context.root)
        local inventory = fixture:inventory('resize', 'stash', 30)
        equal(fixture.exports.AddItem(inventory.id, 'rifle', 1, nil, 1), true)
        equal(fixture.exports.AddItem(inventory.id, 'rifle', 1, nil, 11, nil, true), true)
        equal(fixture.exports.SetSlotCount(inventory.id, 10), true)
        local recovered = inventory.recovery[1]
        equal({ slot(inventory.items[1]), slot(inventory.items[11]), inventory.grid, inventory.weight, #inventory.recovery, recovered.reason, recovered.record.name, recovered.record.slot, recovered.record.rotated }, {
            { name = 'rifle', slot = 1, count = 1, weight = 4000, metadata = {} }, false,
            { columns = 5, cells = 10 }, 8000, 1, 'no_space', 'rifle', 11, true,
        })
        equal(fixture.exports.SetSlotCount(inventory.id, 30), true)
        equal({ inventory.grid, inventory.weight, #inventory.recovery, fixture.exports.GetItemCount(inventory.id, 'rifle') }, { { columns = 5, cells = 30 }, 8000, 1, 1 })
    end)

    test('malformed JSON fails closed before an empty inventory can be saved', function()
        local fixture = Fixture.new(context.root)
        fixture.persisted.stash[':broken'] = 'not-a-json-token'
        local success = pcall(fixture.Inventory.Create, 'broken', 'Broken', 'stash', 30, 0, 30000, false)
        equal(success, false)
        equal(#fixture.writes, 0)
        equal(fixture.persisted.stash[':broken'], 'not-a-json-token')
    end)

    for _, invType in ipairs({ 'trunk', 'glovebox' }) do
        test(invType .. ' save/load preserves rotation and recovery', function()
            local fixture = Fixture.new(context.root)
            local inventory = fixture:inventory(invType .. '-fixture', invType, 30)
            equal(fixture.exports.AddItem(inventory.id, 'rifle', 1, nil, 1), true)
            equal(fixture.exports.AddItem(inventory.id, 'rifle', 1, nil, 11, nil, true), true)
            equal(fixture.exports.SetSlotCount(inventory.id, 10), true)
            equal(fixture.Inventory.Save(inventory), true)
            local loaded = fixture.Inventory.Create(inventory.id, invType, invType, 10, 0, 30000, false, nil, nil, inventory.dbId)
            equal({ slot(loaded.items[1]), loaded.weight, #loaded.recovery, loaded.recovery[1].record.name }, {
                { name = 'rifle', slot = 1, count = 1, weight = 4000, metadata = {} }, 8000, 1, 'rifle',
            })
            equal(loaded.recovery[1].record.rotated, true)
        end)
    end

    test('death-drop export transfers active and recovery ownership together', function()
        local fixture = Fixture.new(context.root)
        local player = fixture:player(1)
        equal(fixture.exports.AddItem(1, 'rifle', 1, nil, 1), true)
        equal(fixture.exports.AddItem(1, 'rifle', 1, nil, 11), true)
        equal(fixture.exports.SetSlotCount(1, 10), true)
        local dropId = fixture.exports.CreateDropFromPlayer(1)
        local drop = fixture.exports.GetInventory(dropId)
        equal({ slot(drop.items[1]), drop.weight, #drop.recovery, drop.recovery[1].record.name, player.weight, #player.recovery, slot(player.items[1]) }, {
            { name = 'rifle', slot = 1, count = 1, weight = 4000, metadata = {} }, 8000, 1, 'rifle', 0, 0, false,
        })
    end)

    test('confiscation source survives a failed durable restoration write', function()
        local fixture = Fixture.new(context.root)
        local player = fixture:player(1)
        equal(fixture.exports.AddItem(1, 'rifle', 1, nil, 1, nil, true), true)
        fixture.exports.ConfiscateInventory(1)
        fixture.env.db.savePlayer = function() return false end
        equal(fixture.exports.ReturnInventory(1), false)
        equal(#fixture.deletes, 0)
        local retained = fixture:decode(fixture.persisted.stash['player-1:player-1'])
        equal(retained, { { name = 'rifle', count = 1, slot = 1, rotated = true } })
        equal(player.owner, 'player-1')
    end)

    test('retrying failed durable restoration cannot duplicate confiscated items', function()
        local fixture = Fixture.new(context.root)
        local player = fixture:player(1)
        equal(fixture.exports.AddItem(1, 'rifle', 1, nil, 1), true)
        fixture.exports.ConfiscateInventory(1)
        local savePlayer = fixture.env.db.savePlayer
        fixture.env.db.savePlayer = function() return false end
        equal(fixture.exports.ReturnInventory(1), false)
        fixture.env.db.savePlayer = savePlayer
        equal(fixture.exports.ReturnInventory(1), true)
        equal({ fixture.exports.GetItemCount(1, 'rifle'), player.weight, #player.recovery, #fixture.deletes }, { 1, 4000, 0, 1 })
        equal(fixture:decode(fixture.persisted.player['player-1']), { { name = 'rifle', count = 1, slot = 1 } })
    end)

    test('duplicate recovery IDs preserve independently reclaimable records', function()
        local fixture = Fixture.new(context.root)
        local duplicate = { _gridRecovery = { id = 'duplicate', reason = 'no_space', record = { name = 'phone', count = 1, slot = 2 } } }
        local inventory = loadStash(fixture, 'duplicates', 30, {
            { _gridRecovery = { id = 'duplicate', reason = 'no_space', record = { name = 'phone', count = 1, slot = 1 } } },
            duplicate,
            { name = 'water', count = 1, slot = 7 },
        })
        equal({ #inventory.recovery, inventory.recovery[1].reason, inventory.recovery[2].reason, inventory.recovery[2].record, inventory.weight, slot(inventory.items[7]) }, {
            2, 'no_space', 'no_space', duplicate._gridRecovery.record, 450,
            { name = 'water', slot = 7, count = 1, weight = 250, metadata = {} },
        })
        equal(inventory.recovery[1].id == inventory.recovery[2].id, false)
    end)

    test('malformed recovery envelopes remain raw invalid records', function()
        local fixture = Fixture.new(context.root)
        local malformed = { _gridRecovery = { id = '', reason = 'invented', record = { name = 'phone', count = 1, slot = 1 } }, custom = 'keep' }
        local inventory = loadStash(fixture, 'bad-envelope', 30, { malformed, { name = 'water', count = 1, slot = 7 } })
        equal({ #inventory.recovery, inventory.recovery[1].reason, inventory.recovery[1].record, slot(inventory.items[7]), inventory.weight }, {
            1, 'invalid_record', malformed,
            { name = 'water', slot = 7, count = 1, weight = 250, metadata = {} }, 250,
        })
    end)

    test('automatic reclaim tries rotation while explicit placement stays strict', function()
        local fixture = Fixture.new(context.root, { items = {
            pole = { name = 'pole', label = 'Pole', weight = 100, stack = false, size = { width = 6, height = 1 } },
        } })
        local player = fixture:player(1)
        local inventory = loadStash(fixture, 'rotate-reclaim', 30, {
            { _gridRecovery = { id = 'pole-owned', reason = 'no_space', record = { name = 'pole', count = 1, slot = 1 } } },
        })
        player:openInventory(inventory)
        equal(fixture:call('ox_inventory:recoverItem', 1, { fromType = 'stash', recoveryId = 'pole-owned', toSlot = 1 }), false)
        equal(fixture:call('ox_inventory:recoverItem', 1, { fromType = 'stash', recoveryId = 'pole-owned', rotated = false }), false)
        equal(fixture:call('ox_inventory:recoverItem', 1, { fromType = 'stash', recoveryId = 'pole-owned' }), true)
        equal({ slot(inventory.items[1]), inventory.items[1].rotated, #inventory.recovery, inventory.weight }, {
            { name = 'pole', slot = 1, count = 1, weight = 100, metadata = {} }, true, 0, 100,
        })
    end)

    test('confiscation persistence cannot create a second death-drop owner', function()
        local fixture = Fixture.new(context.root)
        local player = fixture:player(1)
        equal(fixture.exports.AddItem(1, 'rifle', 1, nil, 1), true)
        local transaction = fixture.env.db.confiscatePlayer
        fixture.env.db.confiscatePlayer = function(owner, payload)
            equal(fixture.exports.CreateDropFromPlayer(1), nil)
            return transaction(owner, payload)
        end
        equal(fixture.exports.ConfiscateInventory(1), true)
        equal({ #fixture.exports.GetInventories('drop'), player.weight, slot(player.items[1]) }, { 0, 0, false })
        equal(fixture:decode(fixture.persisted.stash['player-1:player-1']), { { name = 'rifle', count = 1, slot = 1 } })
    end)

    for _, operation in ipairs({ 'restorePlayer', 'confiscatePlayer' }) do
        for _, succeeds in ipairs({ true, false }) do
            test(operation .. ' releases a disconnected inventory after database result ' .. tostring(succeeds), function()
                local fixture = Fixture.new(context.root)
                fixture:player(1)
                equal(fixture.exports.AddItem(1, 'rifle', 1, nil, 1), true)
                if operation == 'restorePlayer' then equal(fixture.exports.ConfiscateInventory(1), true) end
                local transaction = fixture.env.db[operation]
                fixture.env.db[operation] = function(owner, payload)
                    fixture.Inventory.Remove(1)
                    if not succeeds then return false end
                    return transaction(owner, payload)
                end
                local result = operation == 'restorePlayer' and fixture.exports.ReturnInventory(1) or fixture.exports.ConfiscateInventory(1)
                equal(result, succeeds)
                equal(#fixture.exports.GetInventories('player'), 0)
                local rejoined = fixture:player(1)
                equal({ rejoined.id, rejoined.owner, rejoined.weight }, { 1, 'player-1', 0 })
                if operation == 'restorePlayer' and succeeds or operation == 'confiscatePlayer' and not succeeds then
                    equal(fixture:decode(fixture.persisted.player['player-1']), { { name = 'rifle', count = 1, slot = 1 } })
                else
                    equal(fixture:decode(fixture.persisted.stash['player-1:player-1']), { { name = 'rifle', count = 1, slot = 1 } })
                end
            end)
        end
    end
end
