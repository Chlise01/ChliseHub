local Utils = {}


function Utils.CopyTable(source)

    local result = {}

    if type(source) ~= "table" then
        return result
    end

    for key, value in pairs(source) do

        if type(value) == "table" then
            result[key] =
                Utils.CopyTable(value)
        else
            result[key] = value
        end
    end

    return result
end


function Utils.ClearTable(tbl)

    if type(tbl) ~= "table" then
        return
    end

    for key in pairs(tbl) do
        tbl[key] = nil
    end
end


function Utils.ReplaceTable(target, source)

    if type(target) ~= "table" then
        return
    end

    Utils.ClearTable(target)

    if type(source) ~= "table" then
        return
    end

    for key, value in pairs(source) do
        target[key] = value
    end
end


function Utils.Trim(value)

    return tostring(value or "")
        :match("^%s*(.-)%s*$")
end


function Utils.SafeCall(callback, ...)

    if type(callback) ~= "function" then
        return false
    end

    return pcall(
        callback,
        ...
    )
end


return Utils