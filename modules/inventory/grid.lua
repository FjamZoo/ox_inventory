-- Pure geometry; slot numbers are row-major, one-based top-left anchors.
local Grid = {}

function Grid.integer(value)
    return type(value) == 'number' and value == value and value > 0 and value < math.huge and value % 1 == 0
end

function Grid.size(item, rotated)
    local size = item and type(item.size) == 'table' and item.size or {}
    local width, height = size.width or size[1] or 1, size.height or size[2] or 1
    if not Grid.integer(width) or not Grid.integer(height) then width, height = 1, 1 end
    if rotated then return height, width end
    return width, height
end

function Grid.columns(inv)
    return math.min(5, inv.slots)
end

function Grid.cells(inv, item, slot, rotated)
    if not Grid.integer(slot) or slot > inv.slots then return end
    local columns = Grid.columns(inv)
    local width, height = Grid.size(item, rotated)
    if (slot - 1) % columns + width > columns then return end
    if slot + (height - 1) * columns + width - 1 > inv.slots then return end
    local cells = {}
    for y = 0, height - 1 do
        for x = 0, width - 1 do cells[#cells + 1] = slot + y * columns + x end
    end
    return cells
end

function Grid.fits(inv, item, slot, rotated, ignore)
    local cells = Grid.cells(inv, item, slot, rotated)
    if not cells then return false end
    local occupied = {}
    for anchor, other in pairs(inv.items) do
        if anchor <= inv.slots and not (ignore and ignore[anchor]) then
            for _, cell in ipairs(Grid.cells(inv, other, anchor, other.rotated) or {}) do occupied[cell] = true end
        end
    end
    for _, cell in ipairs(cells) do if occupied[cell] then return false end end
    return true
end

function Grid.find(inv, item, rotated)
    for slot = 1, inv.slots do
        if Grid.fits(inv, item, slot, rotated) then return slot, rotated == true end
    end
    if rotated == nil then
        for slot = 1, inv.slots do
            if Grid.fits(inv, item, slot, true) then return slot, true end
        end
    end
end

-- Recovery entries live outside the grid. They retain their item/metadata/count,
-- can be taken out, and never create usable capacity for incoming items.
function Grid.migrate(inv, definitions)
    local ordered, pending, placed = {}, {}, {}
    for _, item in pairs(inv.items) do ordered[#ordered + 1] = item end
    table.sort(ordered, function(a, b) return a.slot < b.slot end)
    local layout = { slots = inv.slots, items = placed }
    for _, item in ipairs(ordered) do
        local width, height = Grid.size(definitions(item.name))
        item.size = { width = width, height = height }
        item.rotated = item.rotated == true
        if Grid.fits(layout, item, item.slot, item.rotated) then
            placed[item.slot] = item
        else pending[#pending + 1] = item end
    end
    local overflow = inv.slots
    for _, item in ipairs(pending) do
        local slot, rotated = Grid.find(layout, item, item.rotated)
        if not slot then slot, rotated = Grid.find(layout, item, not item.rotated) end
        if not slot then overflow = overflow + 1; slot, rotated = overflow, item.rotated end
        item.slot, item.rotated = slot, rotated
        placed[slot] = item
    end
    -- Keep table identity: player startup and several bridges retain this table.
    for key in pairs(inv.items) do inv.items[key] = nil end
    for key, item in pairs(placed) do inv.items[key] = item end
end

-- Validate both resulting rectangles, including their intersection in a swap.
function Grid.move(from, to, fromSlot, toSlot, count, rotated, stack)
    local source, target = from.items[fromSlot], to.items[toSlot]
    if not source or not Grid.integer(count) or count > source.count then return false end
    if from == to and fromSlot == toSlot then
        return count == source.count and Grid.fits(to, source, toSlot, rotated, { [fromSlot] = true })
    end
    local ignore = {}
    if from == to and (count == source.count or (target and not stack)) then ignore[fromSlot] = true end
    if target then ignore[toSlot] = true end
    if stack then
        return toSlot <= to.slots and Grid.fits(to, target, toSlot, target.rotated, { [toSlot] = true })
    end
    if not Grid.fits(to, source, toSlot, rotated, ignore) then return false end
    if target then
        if count ~= source.count then return false end
        local backIgnore = { [fromSlot] = true }
        if from == to then backIgnore[toSlot] = true end
        if not Grid.fits(from, target, fromSlot, target.rotated, backIgnore) then return false end
        if from == to then
            local cells = {}
            for _, cell in ipairs(Grid.cells(to, source, toSlot, rotated)) do cells[cell] = true end
            for _, cell in ipairs(Grid.cells(from, target, fromSlot, target.rotated)) do
                if cells[cell] then return false end
            end
        end
    end
    return true
end

return Grid
