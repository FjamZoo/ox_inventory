local script = arg[0]:gsub('\\', '/')
local root = script:match('^(.*)/tests/run%.lua$') or (script == 'tests/run.lua' and '.')
assert(root, 'run the script using its tests/run.lua path')

local Fixture = assert(loadfile(root .. '/tests/server/fixture.lua'))()
local selected = arg[1] or '--compatibility'
local failures, passed = 0, 0

local function describe(value)
    if type(value) ~= 'table' then return tostring(value) end

    local keys, parts = {}, {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, function(left, right) return tostring(left) < tostring(right) end)
    for _, key in ipairs(keys) do parts[#parts + 1] = tostring(key) .. '=' .. describe(value[key]) end
    return '{' .. table.concat(parts, ', ') .. '}'
end

local function equal(actual, expected, message)
    if type(actual) ~= type(expected) then
        error((message or 'value') .. ' expected ' .. describe(expected) .. ', received ' .. describe(actual), 2)
    end

    if type(expected) == 'table' then
        for key, value in pairs(expected) do equal(actual[key], value, (message or 'value') .. '.' .. key) end
        for key in pairs(actual) do
            if expected[key] == nil then error((message or 'value') .. ' has unexpected key ' .. tostring(key), 2) end
        end
    elseif actual ~= expected then
        error((message or 'value') .. ' expected ' .. describe(expected) .. ', received ' .. describe(actual), 2)
    end
end

local function test(name, callback)
    local success, message = xpcall(callback, debug.traceback)
    if success then
        passed += 1
        print('PASS ' .. name)
    else
        failures += 1
        print('FAIL ' .. name .. '\n' .. message)
    end
end

local function slot(item)
    if not item then return false end
    return { name = item.name, slot = item.slot, count = item.count, weight = item.weight, metadata = item.metadata }
end

local context = { root = root, Fixture = Fixture, test = test, equal = equal, slot = slot }
local suites = {
    ['--compatibility'] = 'compatibility',
    ['--baseline'] = 'baseline',
    ['--grid'] = 'grid',
}
assert(suites[selected], 'expected --compatibility, --baseline, or --grid')
assert(loadfile(root .. '/tests/server/' .. suites[selected] .. '.lua'))()(context)

print(('%d passed, %d failed'):format(passed, failures))
os.exit(failures == 0 and 0 or 1)
