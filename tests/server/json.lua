local Json = { null = {} }

function Json.decode(input)
    local cursor = 1
    local parse

    local function skip()
        cursor = input:find('%S', cursor) or (#input + 1)
    end

    local function take(character)
        skip()
        assert(input:sub(cursor, cursor) == character, 'expected JSON ' .. character .. ' at ' .. cursor)
        cursor += 1
    end

    local function stringValue()
        take('"')
        local start = cursor
        while cursor <= #input do
            local character = input:sub(cursor, cursor)
            if character == '"' then
                local value = input:sub(start, cursor - 1)
                cursor += 1
                return value
            end
            assert(character ~= '\\' and character:byte() >= 32, 'fixture JSON strings must be unescaped text')
            cursor += 1
        end
        error('unterminated fixture JSON string')
    end

    parse = function()
        skip()
        local character = input:sub(cursor, cursor)
        if character == '"' then return stringValue() end

        if character == '[' or character == '{' then
            local array = character == '['
            local closing = array and ']' or '}'
            cursor += 1
            local result = {}
            skip()
            while input:sub(cursor, cursor) ~= closing do
                if array then
                    result[#result + 1] = parse()
                else
                    local key = stringValue()
                    take(':')
                    result[key] = parse()
                end
                skip()
                if input:sub(cursor, cursor) ~= ',' then break end
                cursor += 1
            end
            take(closing)
            return result
        end

        for token, value in pairs({ ['true'] = true, ['false'] = false, ['null'] = Json.null }) do
            if input:sub(cursor, cursor + #token - 1) == token then
                cursor += #token
                return value
            end
        end

        local number = input:match('^-?%d+%.?%d*', cursor)
        assert(number and tonumber(number), 'invalid fixture JSON at ' .. cursor)
        cursor += #number
        return tonumber(number)
    end

    local value = parse()
    skip()
    assert(cursor > #input, 'trailing fixture JSON data at ' .. cursor)
    return value
end

return Json
