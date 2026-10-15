local Grid = {}

function Grid.Integer(value, minimum)
    return type(value) == 'number' and value == value and value < math.huge and value % 1 == 0 and value >= (minimum or 1)
end

function Grid.Size(size)
    if size == nil then return { width = 1, height = 1 } end
    assert(type(size) == 'table' and Grid.Integer(size.width) and Grid.Integer(size.height), 'item size requires positive integer width and height')
    return { width = size.width, height = size.height }
end

function Grid.Cells(grid, size, anchor, rotated)
    if not Grid.Integer(anchor) or anchor > grid.cells then return end
    local width, height = (size or {}).width or 1, (size or {}).height or 1
    if rotated then width, height = height, width end
    local column = (anchor - 1) % grid.columns
    if column + width > grid.columns then return end
    if anchor + (height - 1) * grid.columns + width - 1 > grid.cells then return end
    local cells = {}
    for row = 0, height - 1 do
        for x = 0, width - 1 do cells[#cells + 1] = anchor + row * grid.columns + x end
    end
    return cells
end

function Grid.Fits(grid, occupied, size, anchor, rotated)
    local cells = Grid.Cells(grid, size, anchor, rotated)
    if not cells then return false end
    for i = 1, #cells do if occupied[cells[i]] then return false end end
    return true, cells
end

function Grid.Occupancy(grid, items, resolve)
    local occupied = {}
    for anchor, record in pairs(items) do
        local item = resolve(record.name)
        if not item then return end
        local fits, cells = Grid.Fits(grid, occupied, item.size, anchor, record.rotated)
        if not fits then return end
        for i = 1, #cells do occupied[cells[i]] = anchor end
    end
    return occupied
end

function Grid.FirstFit(grid, occupied, size, rotated)
    for anchor = 1, grid.cells do
        if Grid.Fits(grid, occupied, size, anchor, rotated) then return anchor end
    end
end

return Grid
