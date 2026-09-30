-- ============================================================
-- CHLISE HUB
-- Loader.lua
-- ============================================================

local BASE_URL =
    "https://raw.githubusercontent.com/Chlise01/ChliseHub/main/"


-- ============================================================
-- LOAD FILE FROM GITHUB
-- ============================================================

local function LoadFile(
    path
)

    local ok, source =
        pcall(function()

            return
                game:HttpGet(
                    BASE_URL
                    .. path
                )

        end)


    if not ok
        or type(source)
            ~= "string"
        or source == ""
    then

        warn(
            "[CHLISE HUB] Failed to fetch:",
            path
        )

        return nil
    end


    local chunk,
        compileError =
        loadstring(
            source
        )


    if not chunk then

        warn(
            "[CHLISE HUB] Compile error:",
            path,
            compileError
        )

        return nil
    end


    local success,
        result =
        pcall(
            chunk
        )


    if not success then

        warn(
            "[CHLISE HUB] Runtime error:",
            path,
            result
        )

        return nil
    end


    return result
end


-- ============================================================
-- WAIT GAME
-- ============================================================

if not game:IsLoaded() then

    game.Loaded:
    Wait()

end


-- ============================================================
-- LOAD CORE
-- ============================================================

local UI =
    LoadFile(
        "Core/UI.lua"
    )


local Runtime =
    LoadFile(
        "Core/Runtime.lua"
    )


local Utils =
    LoadFile(
        "Core/Utils.lua"
    )


local Config =
    LoadFile(
        "Core/Config.lua"
    )


if not UI
    or not Runtime
    or not Utils
    or not Config
then

    warn(
        "[CHLISE HUB] Failed to load core modules."
    )

    return
end


-- ============================================================
-- CONTEXT
-- ============================================================

local Context = {

    UI =
        UI,

    Config =
        Config,

    Runtime =
        Runtime,

    Utils =
        Utils

}


-- ============================================================
-- UNIVERSAL
--
-- Creates:
-- Window
-- Settings
-- ConfigManager
-- Anti AFK
-- ============================================================

local Universal =
    LoadFile(
        "Universal.lua"
    )


if type(Universal)
    ~= "function"
then

    warn(
        "[CHLISE HUB] Invalid Universal module."
    )

    return
end


local universalOK,
    universalError =
    pcall(
        Universal,
        Context
    )


if not universalOK then

    warn(
        "[CHLISE HUB] Universal error:",
        universalError
    )

    return
end


if not Context.Window then

    warn(
        "[CHLISE HUB] Window was not created."
    )

    return
end


-- ============================================================
-- GAME REGISTRY
-- ============================================================

local Games =
    LoadFile(
        "Games/Games.lua"
    )


if type(Games)
    ~= "table"
then

    warn(
        "[CHLISE HUB] Games registry failed."
    )

    return
end


-- ============================================================
-- FIND GAME MODULE
-- ============================================================

local gameFile =
    Games[
        game.GameId
    ]


if not gameFile then

    warn(
        "[CHLISE HUB] Unsupported game:",
        game.GameId
    )

    return
end


-- ============================================================
-- LOAD GAME MODULE
-- ============================================================

local GameModule =
    LoadFile(
        gameFile
    )


if type(GameModule)
    ~= "function"
then

    warn(
        "[CHLISE HUB] Invalid game module:",
        gameFile
    )

    return
end


-- ============================================================
-- START GAME MODULE
-- ============================================================

local gameOK,
    gameError =
    pcall(
        GameModule,
        Context
    )


if not gameOK then

    warn(
        "[CHLISE HUB] Game module error:",
        gameError
    )

    return
end


-- ============================================================
-- DEFAULT TAB
-- ============================================================

pcall(function()

    Context.Window:
    SelectTab(
        "FARM"
    )

end)


-- ============================================================
-- AUTOLOAD
--
-- PENTING:
-- Jalankan SETELAH semua control game dibuat.
-- ============================================================

if Context.ConfigManager then

    local ok,
        result =
        pcall(function()

            return
                Context.ConfigManager:
                RunAutoload()

        end)


    if not ok then

        warn(
            "[CHLISE HUB] Autoload error:",
            result
        )

    elseif result then

        print(
            "[CHLISE HUB] Autoload applied."
        )

    end

end


-- ============================================================
-- READY
-- ============================================================

print(
    "[CHLISE HUB] Ready.",
    "| GameId:",
    game.GameId,
    "| Module:",
    gameFile
)