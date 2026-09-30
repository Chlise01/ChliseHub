-- ============================================================

-- CHLISE HUB

-- Universal.lua

-- ============================================================



return function(Context)



    -- ========================================================

    -- CORE

    -- ========================================================



    local UI =

        Context.UI



    local Config =

        Context.Config



    local Runtime =

        Context.Runtime





    -- ========================================================

    -- SERVICES

    -- ========================================================



    local Players =

        game:GetService("Players")



    local VirtualUser =

        game:GetService("VirtualUser")





    local LocalPlayer =

        Players.LocalPlayer





    -- ========================================================

    -- WINDOW

    -- ========================================================



    local Window =

        UI.new({

            Title = "CHLISE HUB",

            Width = 500,

            Height = 305

        })





    Context.Window =

        Window





    -- ========================================================

    -- CONFIG MANAGER

    -- ========================================================



    local ConfigManager =

        Config.new(

            Window,

            Runtime

        )





    Context.ConfigManager =

        ConfigManager





    -- ========================================================

    -- SETTINGS TAB

    -- ========================================================



    local SettingsTab =

        Window:AddTab(

            "SETTINGS",

            "⚙"

        )





    -- ========================================================

    -- CONFIG SECTION

    -- ========================================================


    local ConfigSection =
        Window:AddSection(
            SettingsTab,
            "Config"
        )


    -- Tidak disimpan ke config.
    local ConfigName =
        ConfigSection:AddTextbox(
            "ConfigName",
            "Save Name",
            "Example: farming",
            nil,
            false
        )


    local selectedConfig =
        nil


    -- Dideklarasikan lebih dulu karena dipakai callback
    -- Create Config / RefreshConfigList sebelum dropdown dibuat.
    local ConfigList =
        nil


    -- ========================================================

    -- REFRESH CONFIG LIST

    -- ========================================================


    local function RefreshConfigList(
        preferred
    )

        local names =
            ConfigManager:List()


        if ConfigList
            and ConfigList.SetOptions
        then

            ConfigList.SetOptions(
                names
            )

        end


        if preferred
            and preferred ~= ""
        then

            selectedConfig =
                preferred


            if ConfigList
                and ConfigList.Set
            then

                ConfigList.Set(
                    preferred,
                    false
                )

            end


            return
        end


        if not selectedConfig then
            return
        end


        local exists =
            false


        for _, name
            in ipairs(names)
        do

            if name
                == selectedConfig
            then

                exists =
                    true

                break
            end

        end


        if not exists then

            selectedConfig =
                nil


            if ConfigList
                and ConfigList.Set
            then

                ConfigList.Set(
                    nil,
                    false
                )

            end

        end

    end


    -- ========================================================

    -- CREATE CONFIG
    -- Langsung di bawah Save Name.

    -- ========================================================


    ConfigSection:AddButton(
        "Create Config",

        function()

            local name =
                ConfigName.Get()


            name =
                tostring(
                    name or ""
                )


            if name == "" then

                warn(
                    "[CHLISE HUB] Enter config name."
                )

                return
            end


            if ConfigManager:Get(
                name
            )
            then

                warn(
                    "[CHLISE HUB] Config already exists:",
                    name
                )

                return
            end


            local ok, err =
                ConfigManager:Save(
                    name
                )


            if not ok then

                warn(
                    "[CHLISE HUB] Create config failed:",
                    err
                )

                return
            end


            RefreshConfigList(
                name
            )


            print(
                "[CHLISE HUB] Config created:",
                name
            )

        end
    )


    -- ========================================================

    -- CONFIG LIST

    -- ========================================================


    ConfigList =
        ConfigSection:AddDropdown(
            "ConfigList",
            "Config List",
            ConfigManager:List(),
            false,
            nil,

            function(value)

                selectedConfig =
                    value

            end,

            false
        )


    -- ========================================================

    -- LOAD + OVERWRITE

    -- ========================================================


    ConfigSection:AddButtonRow(
        "Load Config",

        function()

            if not selectedConfig then

                warn(
                    "[CHLISE HUB] Select config first."
                )

                return
            end


            local ok, err =
                ConfigManager:Load(
                    selectedConfig
                )


            if not ok then

                warn(
                    "[CHLISE HUB] Load config failed:",
                    err
                )

                return
            end


            print(
                "[CHLISE HUB] Config loaded:",
                selectedConfig
            )

        end,


        "Overwrite Config",

        function()

            if not selectedConfig then

                warn(
                    "[CHLISE HUB] Select config first."
                )

                return
            end


            local ok, err =
                ConfigManager:Save(
                    selectedConfig
                )


            if not ok then

                warn(
                    "[CHLISE HUB] Overwrite failed:",
                    err
                )

                return
            end


            RefreshConfigList(
                selectedConfig
            )


            print(
                "[CHLISE HUB] Config overwritten:",
                selectedConfig
            )

        end
    )


    -- ========================================================

    -- DELETE + SET AUTOLOAD

    -- ========================================================


    ConfigSection:AddButtonRow(
        "Delete Config",

        function()

            if not selectedConfig then

                warn(
                    "[CHLISE HUB] Select config first."
                )

                return
            end


            local deleting =
                selectedConfig


            local ok =
                ConfigManager:Delete(
                    deleting
                )


            if not ok then

                warn(
                    "[CHLISE HUB] Failed to delete config:",
                    deleting
                )

                return
            end


            if ConfigManager:GetAutoload()
                == deleting
            then

                ConfigManager:SetAutoload(
                    ""
                )

            end


            selectedConfig =
                nil


            RefreshConfigList()


            print(
                "[CHLISE HUB] Config deleted:",
                deleting
            )

        end,


        "Set As Autoload",

        function()

            if not selectedConfig then

                warn(
                    "[CHLISE HUB] Select config first."
                )

                return
            end


            ConfigManager:SetAutoload(
                selectedConfig
            )


            print(
                "[CHLISE HUB] Autoload set:",
                selectedConfig
            )

        end
    )


    -- ========================================================

    -- CLEAR AUTOLOAD
    -- Sisa satu tombol, jadi full width.

    -- ========================================================


    ConfigSection:AddButton(
        "Clear Autoload",

        function()

            ConfigManager:SetAutoload(
                ""
            )


            print(
                "[CHLISE HUB] Autoload cleared."
            )

        end
    )


    -- ========================================================

    -- SCRIPT SETTINGS

    -- ========================================================



    local ScriptSection =

        Window:AddSection(

            SettingsTab,

            "Setting Script"

        )





    -- ========================================================

    -- AUTO EXECUTE

    --

    -- Disimpan ke settings.json.

    -- BUKAN bagian dari file config user.

    -- ========================================================



    local savedAutoExecute =

        ConfigManager:

        GetAutoExecute()





    ScriptSection:AddCheckbox(

        "AutoExecute",

        "Auto Execute",

        savedAutoExecute,



        function(state)



            ConfigManager:

            SetAutoExecute(

                state

            )



        end,



        false

    )





    -- ========================================================

    -- ANTI AFK

    --

    -- Disimpan ke settings.json.

    -- ========================================================



    local antiAFKEnabled =

        ConfigManager:

        GetSetting(

            "AntiAFK",

            false

        )

        == true





    ScriptSection:AddCheckbox(

        "AntiAFK",

        "Anti AFK",

        antiAFKEnabled,



        function(state)



            antiAFKEnabled =

                state





            ConfigManager:

            SetSetting(

                "AntiAFK",

                state

            )



        end,



        false

    )





    -- ========================================================

    -- ANTI AFK CONNECTION

    -- ========================================================



    Runtime:TrackConnection(



        LocalPlayer.Idled:

        Connect(function()



            if not antiAFKEnabled then

                return

            end





            pcall(function()



                local camera =

                    workspace.CurrentCamera





                VirtualUser:

                Button2Down(

                    Vector2.new(

                        0,

                        0

                    ),



                    camera

                    and camera.CFrame

                    or CFrame.new()

                )





                task.wait(0.5)





                VirtualUser:

                Button2Up(

                    Vector2.new(

                        0,

                        0

                    ),



                    camera

                    and camera.CFrame

                    or CFrame.new()

                )



            end)



        end)



    )





    -- ========================================================

    -- INITIAL CONFIG LIST

    -- ========================================================



    RefreshConfigList(

        ConfigManager:

        GetAutoload()

    )





    print(

        "[CHLISE HUB] Universal loaded."

    )



end