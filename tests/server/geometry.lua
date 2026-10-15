return function(context)
    local Grid = assert(loadfile(context.root .. '/modules/inventory/grid.lua'))()
    local Json = assert(loadfile(context.root .. '/tests/server/json.lua'))()
    local file = assert(io.open(context.root .. '/tests/fixtures/grid.json', 'r'))
    local vectors = Json.decode(file:read('a'))

    file:close()

    for _, vector in ipairs(vectors.occupancy) do
        context.test('geometry occupancy ' .. vector.name, function()
            local cells = Grid.Cells(vector.grid, vector.size, vector.slot, vector.rotated)

            if vector.cells == Json.null then
                context.equal(cells, nil)
            else
                context.equal(cells, vector.cells)
            end
        end)
    end

    for _, vector in ipairs(vectors.placement) do
        context.test('geometry placement ' .. vector.name, function()
            local ignored, items = {}, {}

            for _, anchor in ipairs(vector.ignoreAnchors) do
                ignored[anchor] = true
            end

            for _, item in ipairs(vector.items) do
                if not ignored[item.slot] then
                    items[item.slot] = item
                end
            end

            local occupied = Grid.Occupancy(vector.grid, items, function(name) return vectors.definitions[name] end)
            local fits = Grid.Fits(
                vector.grid,
                occupied,
                vectors.definitions[vector.item].size,
                vector.toSlot,
                vector.rotated
            )
            context.equal(fits, vector.fits)
        end)
    end

    context.test('geometry first fit skips all covered cells', function()
        local occupied = Grid.Occupancy(
            { columns = 5, cells = 30 },
            { [1] = { name = 'rifle' } },
            function(name) return vectors.definitions[name] end
        )
        context.equal(Grid.FirstFit({ columns = 5, cells = 30 }, occupied, { width = 4, height = 2 }), 11)
        context.equal(Grid.FirstFit({ columns = 5, cells = 30 }, occupied, { width = 1, height = 1 }), 5)
    end)

    context.test('geometry size validates definitions and preserves rotatable wide items', function()
        context.equal(Grid.Size(), { width = 1, height = 1 })
        context.equal(Grid.Size({ width = 6, height = 1 }), { width = 6, height = 1 })

        local success = pcall(Grid.Size, { width = 0, height = 2 })

        context.equal(success, false)
    end)
end
