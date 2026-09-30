local Runtime = {}

local GLOBAL_ENV =
    (getgenv and getgenv())
    or _G

if type(GLOBAL_ENV.ChliseRuntime) ~= "table" then
    GLOBAL_ENV.ChliseRuntime = {}
end

local State =
    GLOBAL_ENV.ChliseRuntime

State.Generation =
    tonumber(State.Generation)
    or 0

if type(State.Connections) ~= "table" then
    State.Connections = {}
end

if type(State.ESP) ~= "table" then
    State.ESP = {}
end

if type(State.Configs) ~= "table" then
    State.Configs = {}
end

if type(State.ScriptSettings) ~= "table" then
    State.ScriptSettings = {}
end


for _, connection in ipairs(State.Connections) do
    pcall(function()
        connection:Disconnect()
    end)
end

State.Connections = {}

State.Generation += 1

local CurrentGeneration =
    State.Generation


function Runtime:IsCurrent()
    return
        State.Generation
        == CurrentGeneration
end


function Runtime:TrackConnection(connection)

    if not connection then
        return nil
    end

    table.insert(
        State.Connections,
        connection
    )

    return connection
end


function Runtime:GetState()
    return State
end


function Runtime:GetESPState()
    return State.ESP
end


function Runtime:GetConfigs()
    return State.Configs
end


function Runtime:GetScriptSettings()
    return State.ScriptSettings
end


function Runtime:SetScriptSettings(settings)

    if type(settings) ~= "table" then
        return
    end

    State.ScriptSettings =
        settings
end


return Runtime