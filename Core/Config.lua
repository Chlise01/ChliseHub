-- ============================================================
-- CHLISE HUB
-- Core/Config.lua
-- ============================================================

local HttpService =
    game:GetService("HttpService")


local Config = {}

Config.__index = Config


-- ============================================================
-- DEFAULT STORAGE PATH
-- ============================================================

local ROOT_FOLDER =
    "ChliseHub"

local CONFIG_FOLDER =
    ROOT_FOLDER .. "/Configs"

local SETTINGS_FILE =
    ROOT_FOLDER .. "/settings.json"


-- ============================================================
-- EXECUTOR FILESYSTEM SUPPORT
-- ============================================================

local HAS_READFILE =
    type(readfile) == "function"

local HAS_WRITEFILE =
    type(writefile) == "function"

local HAS_ISFILE =
    type(isfile) == "function"

local HAS_LISTFILES =
    type(listfiles) == "function"

local HAS_DELFILE =
    type(delfile) == "function"

local HAS_MAKEFOLDER =
    type(makefolder) == "function"

local HAS_ISFOLDER =
    type(isfolder) == "function"


-- ============================================================
-- HELPERS
-- ============================================================

local function SafeEncode(data)

    local ok, result =
        pcall(function()
            return HttpService:JSONEncode(data)
        end)

    if not ok then
        return nil
    end

    return result
end


local function SafeDecode(raw)

    if type(raw) ~= "string"
        or raw == ""
    then
        return nil
    end

    local ok, result =
        pcall(function()
            return HttpService:JSONDecode(raw)
        end)

    if not ok then
        return nil
    end

    return result
end


local function SanitizeName(name)

    name =
        tostring(name or "")

    name =
        name:gsub(
            "[^%w%s%-%_]",
            ""
        )

    name =
        name:match(
            "^%s*(.-)%s*$"
        )

    return name
end


local function ConfigPath(name)

    return
        CONFIG_FOLDER
        .. "/"
        .. SanitizeName(name)
        .. ".json"
end


local function EnsureFolders()

    if not HAS_MAKEFOLDER then
        return
    end

    pcall(function()

        if HAS_ISFOLDER then

            if not isfolder(ROOT_FOLDER) then
                makefolder(ROOT_FOLDER)
            end

            if not isfolder(CONFIG_FOLDER) then
                makefolder(CONFIG_FOLDER)
            end

        else

            pcall(function()
                makefolder(ROOT_FOLDER)
            end)

            pcall(function()
                makefolder(CONFIG_FOLDER)
            end)

        end

    end)
end


-- ============================================================
-- CONSTRUCTOR
-- ============================================================

function Config.new(
    window,
    runtime
)

    local self =
        setmetatable(
            {},
            Config
        )


    self.Window =
        window


    self.Runtime =
        runtime


    self.State =
        runtime
        and runtime:GetState()
        or {}


    if type(
        self.State.Configs
    ) ~= "table"
    then

        self.State.Configs = {}
    end


    if type(
        self.State.ScriptSettings
    ) ~= "table"
    then

        self.State.ScriptSettings = {}
    end


    EnsureFolders()


    self:LoadSettings()


    return self
end


-- ============================================================
-- SNAPSHOT
-- ============================================================

function Config:CreateSnapshot()

    local snapshot = {
        Version = 2,
        Controls = {}
    }

    local controls =
        self.Window:GetControls()

    for id, control
        in pairs(controls)
    do

        if type(control)
            == "table"

            and control.Save
                ~= false

            and type(control.Get)
                == "function"
        then

            local ok, value =
                pcall(
                    control.Get
                )

            if ok then

                snapshot.Controls[id] =
                    value

            end

        end

    end

    return snapshot
end


-- ============================================================
-- APPLY SNAPSHOT
-- ============================================================

function Config:ApplySnapshot(
    snapshot,
    invokeCallbacks
)

    if type(snapshot)
        ~= "table"
    then
        return false
    end


    local data =
        snapshot.Controls


    if type(data)
        ~= "table"
    then
        return false
    end


    local controls =
        self.Window:GetControls()


    for id, value
        in pairs(data)
    do

        local control =
            controls[id]


        if control
            and type(control.Set)
                == "function"
        then

            pcall(
                control.Set,
                value,
                invokeCallbacks ~= false
            )

        end

    end


    return true
end


-- ============================================================
-- SAVE CONFIG
-- ============================================================

function Config:Save(
    name
)

    name =
        SanitizeName(name)


    if name == "" then
        return false,
            "Config name is empty"
    end


    local data =
        self:CreateSnapshot()


    self.State.Configs[name] =
        data


    if HAS_WRITEFILE then

        local raw =
            SafeEncode(data)


        if raw then

            local ok =
                pcall(function()

                    writefile(
                        ConfigPath(name),
                        raw
                    )

                end)


            if not ok then

                return false,
                    "Failed to write config file"

            end

        end

    end


    return true
end


-- ============================================================
-- READ CONFIG
-- ============================================================

function Config:Get(
    name
)

    name =
        SanitizeName(name)


    if name == "" then
        return nil
    end


    local cached =
        self.State.Configs[name]


    if type(cached)
        == "table"
    then
        return cached
    end


    if HAS_READFILE
        and HAS_ISFILE
    then

        local path =
            ConfigPath(name)


        local result =
            nil


        pcall(function()

            if isfile(path) then

                result =
                    SafeDecode(
                        readfile(path)
                    )

            end

        end)


        if type(result)
            == "table"
        then

            self.State.Configs[name] =
                result


            return result
        end

    end


    return nil
end


-- ============================================================
-- LOAD CONFIG
-- ============================================================

function Config:Load(
    name
)

    local data =
        self:Get(name)


    if not data then

        return false,
            "Config not found"

    end


    local ok =
        self:ApplySnapshot(
            data,
            true
        )


    if not ok then

        return false,
            "Invalid config"

    end


    return true
end


-- ============================================================
-- DELETE CONFIG
-- ============================================================

function Config:Delete(
    name
)

    name =
        SanitizeName(name)


    if name == "" then
        return false
    end


    self.State.Configs[name] =
        nil


    if HAS_DELFILE
        and HAS_ISFILE
    then

        pcall(function()

            local path =
                ConfigPath(name)


            if isfile(path) then

                delfile(path)

            end

        end)

    end


    return true
end


-- ============================================================
-- LIST CONFIGS
-- ============================================================

function Config:List()

    local seen = {}

    local names = {}


    if type(
        self.State.Configs
    ) ~= "table"
    then

        self.State.Configs = {}
    end


    for name
        in pairs(
            self.State.Configs
        )
    do

        name =
            SanitizeName(name)


        if name ~= ""
            and not seen[name]
        then

            seen[name] = true

            table.insert(
                names,
                name
            )

        end

    end


    if HAS_LISTFILES then

        pcall(function()

            local files =
                listfiles(
                    CONFIG_FOLDER
                )


            if type(files)
                ~= "table"
            then
                return
            end


            for _, path
                in ipairs(files)
            do

                local normalized =
                    tostring(path)
                    :gsub(
                        "\\",
                        "/"
                    )


                local fileName =
                    normalized:match(
                        "([^/]+)$"
                    )


                if fileName
                    and fileName
                        :lower()
                        :sub(-5)
                        == ".json"
                then

                    local clean =
                        fileName:sub(
                            1,
                            -6
                        )


                    clean =
                        SanitizeName(
                            clean
                        )


                    if clean ~= ""
                        and not seen[clean]
                    then

                        seen[clean] =
                            true

                        table.insert(
                            names,
                            clean
                        )

                    end

                end

            end

        end)

    end


    table.sort(
        names,
        function(a, b)

            return
                a:lower()
                < b:lower()

        end
    )


    return names
end


-- ============================================================
-- SETTINGS
-- ============================================================

function Config:LoadSettings()

    local settings =
        self.State.ScriptSettings


    if type(settings)
        ~= "table"
    then

        settings = {}

        self.State.ScriptSettings =
            settings
    end


    if HAS_READFILE
        and HAS_ISFILE
    then

        pcall(function()

            if isfile(
                SETTINGS_FILE
            )
            then

                local saved =
                    SafeDecode(
                        readfile(
                            SETTINGS_FILE
                        )
                    )


                if type(saved)
                    == "table"
                then

                    for key, value
                        in pairs(saved)
                    do

                        settings[key] =
                            value

                    end

                end

            end

        end)

    end


    return settings
end


function Config:SaveSettings()

    if not HAS_WRITEFILE then
        return false
    end


    local raw =
        SafeEncode(
            self.State.ScriptSettings
        )


    if not raw then
        return false
    end


    local ok =
        pcall(function()

            writefile(
                SETTINGS_FILE,
                raw
            )

        end)


    return ok
end


function Config:GetSetting(
    key,
    defaultValue
)

    local value =
        self.State.ScriptSettings[key]


    if value == nil then
        return defaultValue
    end


    return value
end


function Config:SetSetting(
    key,
    value
)

    self.State.ScriptSettings[key] =
        value


    self:SaveSettings()
end


-- ============================================================
-- AUTOLOAD
-- ============================================================

function Config:SetAutoload(
    name
)

    name =
        SanitizeName(name)


    self:SetSetting(
        "Autoload",
        name
    )
end


function Config:GetAutoload()

    return
        self:GetSetting(
            "Autoload",
            ""
        )
end


function Config:SetAutoExecute(
    enabled
)

    self:SetSetting(
        "AutoExecute",
        enabled == true
    )
end


function Config:GetAutoExecute()

    return
        self:GetSetting(
            "AutoExecute",
            false
        ) == true
end


function Config:RunAutoload()

    if not self:GetAutoExecute() then
        return false
    end


    local name =
        self:GetAutoload()


    if type(name)
        ~= "string"

        or name == ""
    then
        return false
    end


    return
        self:Load(name)
end


return Config