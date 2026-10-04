-- ============================================================
-- CHLISE HUB
-- Games/RideAPet.lua
-- ============================================================

return function(Context)

    -- ========================================================
    -- CORE
    -- ========================================================

    local Window =
        Context.Window

    local Runtime =
        Context.Runtime

    local Utils =
        Context.Utils


    if not Window then
        warn("[CHLISE HUB] Window not initialized.")
        return
    end


    -- ========================================================
    -- SERVICES
    -- ========================================================

    local Players =
        game:GetService("Players")

    local ReplicatedStorage =
        game:GetService("ReplicatedStorage")

    local RunService =
        game:GetService("RunService")

    local Lighting =
        game:GetService("Lighting")

    local VirtualInputManager =
        game:GetService("VirtualInputManager")

    local TeleportService =
        game:GetService("TeleportService")

    local TweenService =
        game:GetService("TweenService")

    local HttpService =
        game:GetService("HttpService")

    local LocalPlayer =
        Players.LocalPlayer


    -- ========================================================
    -- GAME MODULES
    -- ========================================================

    local GameServices =
        ReplicatedStorage:
        WaitForChild("GameServices")

    local GameData =
        ReplicatedStorage:
        WaitForChild("GameData")

    local Remotes =
        ReplicatedStorage:
        WaitForChild("Remotes")


    local General =
        require(
            GameServices:
            WaitForChild("General")
        )


    local DayNight =
        require(
            GameServices:
            WaitForChild("DayNight")
        )


    local PetAging =
        require(
            GameServices:
            WaitForChild("PetAging")
        )


    local EggDeliveryRules =
        require(
            GameServices:
            WaitForChild("EggDeliveryRules")
        )


    local EggsData =
        require(
            GameData:
            WaitForChild("Eggs")
        )


    local GeneralData =
        require(
            GameData:
            WaitForChild("General")
        )


    local PetData =
        require(
            GameData:
            WaitForChild("Pets")
        )


    local RebirthsData =
        require(
            GameData:
            WaitForChild("Rebirths")
        )


    local Mutations =
        require(
            GameData:
            WaitForChild("Mutations")
        )


    -- ========================================================
    -- REMOTES
    -- ========================================================

    local GameRemotes =
        Remotes:
        WaitForChild("Game")


    local HatchRemote =
        GameRemotes:
        WaitForChild("Hatch")


    local RequestPlotEggs =
        GameRemotes:
        WaitForChild("RequestPlotEggs")


    local FavoritePetRemote =
        GameRemotes:
        WaitForChild("FavoritePet")


    local UpgradesRemote =
        GameRemotes:
        WaitForChild("Plot"):
        WaitForChild("Upgrades")

    local BasketDrop =
        GameRemotes:
        WaitForChild("BasketDrop")


    local RebirthRemote =
        GameRemotes:
        WaitForChild("Rebirth")


    local EggPickupRemote =
        GameRemotes:
        WaitForChild("EggPickup")


    local EggArrivalClaimRemote =
        GameRemotes:
        WaitForChild("EggArrivalClaim")


    local EggTimerPauseRemote =
        GameRemotes:
        WaitForChild("EggTimerPause")


    local VolcanoData =
        require(
            GameData:
            WaitForChild("Volcano")
        )


    local Basket =
        LocalPlayer:
        WaitForChild("Basket")


    local SavedData =
        LocalPlayer:
        WaitForChild("SavedData")


    local CashValue =
        SavedData:
        WaitForChild("Cash")


    local RebirthsValue =
        SavedData:
        WaitForChild("Rebirths")


    local VolcanoDipRemote =
        ReplicatedStorage:
        WaitForChild("packages"):
        WaitForChild("Net"):
        WaitForChild("RE/VolcanoDip")


    -- ========================================================
    -- STATES
    -- ========================================================

    local selectedEggsFarm = {}
    local selectedRaritiesFarm = {}
    local minimumEggWeight = 0

    local selectedEggsPlace = {}
    local selectedRaritiesPlace = {}

    local selectedFoods = {}

    local selectedSellRarities = {}
    local selectedSellPetNames = {}

    local selectedFavoriteRarities = {}


    local currentPickupBasketIds = {}


    local autoFarmActive = false
    local placeEggActive = false
    local autoHatchActive = false

    local autoPlaceBestPetActive = false
    local autoRideBestPetActive = false

    -- UI/state only.
    -- Belum ada logic Feed Pet.
    local autoFeedPetActive = false

    local autoUpdateHatchLuckActive = false
    local autoMaxHatchLuckActive = false
    local autoRebirthActive = false

    local autoSellByRarityActive = false
    local autoSellByNameActive = false

    local autoFavoriteByRarityActive = false
    local autoUnfavoriteByRarityActive = false

    local espEggsEnabled = false
    local espInventoryEnabled = false

    local disable3DActive = false
    local lowGraphicActive = false
    local fpsBoostActive = false

    local selectedGiftPlayer = nil
    local giftEggActive = false
    local goVolcanoDipActive = false

    local autoServerHopActive = false
    local serverHopDelay = 30
    local noTargetSince = nil


    -- ========================================================
    -- WEBHOOK STATE
    -- ========================================================

    local webhookUrl = ""

    local webhookWorldEggActive = false
    local webhookEggPickedUpActive = false
    local webhookVolcanoDipActive = false
    local webhookGiftEggActive = false
    local webhookRebirthActive = false
    local webhookServerHopActive = false
    local webhookErrorsActive = false

    local selectedWebhookWorldEggs = {}

    local WebhookState = {
        SentWorldEggs = {}
    }


    -- ========================================================
    -- WEBHOOK HELPERS
    -- ========================================================

    local function TrimWebhookText(
        value
    )

        return tostring(
            value or ""
        ):
        match(
            "^%s*(.-)%s*$"
        )
        or ""

    end


    local function GetWebhookRequest()

        local globalEnv =
            (
                getgenv
                and getgenv()
            )
            or _G


        if type(request)
            == "function"
        then
            return request
        end


        if type(http_request)
            == "function"
        then
            return http_request
        end


        if type(globalEnv.request)
            == "function"
        then
            return globalEnv.request
        end


        if type(globalEnv.http_request)
            == "function"
        then
            return globalEnv.http_request
        end


        if type(syn)
                == "table"
            and type(syn.request)
                == "function"
        then
            return syn.request
        end


        return nil
    end


    local function IsWebhookConfigured()

        return
            type(webhookUrl)
                == "string"
            and webhookUrl
                ~= ""

    end


    local function SendWebhook(
        title,
        fields,
        description
    )

        if not IsWebhookConfigured() then
            return false
        end


        local requestFunction =
            GetWebhookRequest()


        if not requestFunction then

            warn(
                "[CHLISE HUB] Webhook request function not supported by executor."
            )

            return false
        end


        local embedFields = {}


        if type(fields)
            == "table"
        then

            for _, field
                in ipairs(fields)
            do

                table.insert(
                    embedFields,
                    {
                        name =
                            tostring(
                                field.name
                                or "Info"
                            ),

                        value =
                            tostring(
                                field.value
                                or "-"
                            ),

                        inline =
                            field.inline
                            ~= false
                    }
                )

            end

        end


        local payload = {
            username =
                "Chlise Hub",

            embeds = {
                {
                    title =
                        tostring(
                            title
                            or "Chlise Hub"
                        ),

                    description =
                        description
                        and tostring(
                            description
                        )
                        or nil,

                    fields =
                        embedFields,

                    footer = {
                        text =
                            "Ride A Pet"
                    },

                    timestamp =
                        DateTime.now():
                        ToIsoDate()
                }
            }
        }


        local ok,
            response =
            pcall(function()

                return requestFunction(
                    {
                        Url =
                            webhookUrl,

                        Method =
                            "POST",

                        Headers = {
                            ["Content-Type"] =
                                "application/json"
                        },

                        Body =
                            HttpService:
                            JSONEncode(
                                payload
                            )
                    }
                )

            end)


        if not ok then

            warn(
                "[CHLISE HUB] Webhook request failed:",
                response
            )

            return false
        end


        local statusCode =
            type(response)
                == "table"
            and (
                response.StatusCode
                or response.Status
                or response.status_code
            )
            or nil


        if statusCode
            and (
                statusCode < 200
                or statusCode >= 300
            )
        then

            warn(
                "[CHLISE HUB] Webhook HTTP status:",
                statusCode
            )

            return false
        end


        return true
    end


    local function IsWebhookEggSelected(
        eggName
    )

        if not eggName then
            return false
        end


        if type(selectedWebhookWorldEggs)
            ~= "table"
        then
            return false
        end


        for key,
            value
            in pairs(
                selectedWebhookWorldEggs
            )
        do

            if key
                    == eggName
                and value
                    == true
            then

                return true

            end


            if value
                == eggName
            then

                return true

            end

        end


        return false
    end


    local function NotifyWebhookError(
        message
    )

        if not webhookErrorsActive then
            return
        end


        task.spawn(function()

            SendWebhook(
                "Chlise Hub — Error",
                {
                    {
                        name =
                            "Message",

                        value =
                            tostring(
                                message
                            ),

                        inline =
                            false
                    }
                }
            )

        end)

    end


    -- ========================================================
    -- SERVER HOP RUNTIME STATE
    --
    -- Tidak masuk named config. Hanya dipakai selama runtime
    -- executor untuk menghindari server yang baru dikunjungi.
    -- ========================================================

    local RuntimeState =
        Runtime:GetState()

    RuntimeState.ServerHop =
        type(RuntimeState.ServerHop) == "table"
        and RuntimeState.ServerHop
        or {}

    local ServerHopState =
        RuntimeState.ServerHop

    ServerHopState.Visited =
        type(ServerHopState.Visited) == "table"
        and ServerHopState.Visited
        or {}

    -- Jangan sampai state "hopping" lama mengunci script
    -- ketika module direload di server yang sama.
    ServerHopState.Hopping = false

    if game.JobId
        and game.JobId ~= ""
    then
        ServerHopState.Visited[
            game.JobId
        ] = true
    end


    -- ========================================================
    -- MASTER DATA
    -- ========================================================

    local MASTER_EGGS = {
        "White Egg",
        "Brown Egg",
        "Cracked Egg",
        "Easter Egg",
        "Stone Egg",
        "Leaf Egg",
        "Mushroom Egg",
        "Flower Egg",
        "Slime Egg",
        "Ice Egg",
        "Glass Egg",
        "Golden Egg",
        "Diamond Egg",
        "Crystal Egg",
        "Skull Egg",
        "Asteroid Egg",
        "Dominus Egg",
        "Flaming Egg",
        "Sinister Egg",
        "Soul Egg",
        "Tidal Egg",
        "Aurora Egg",
        "Galaxy Egg",
        "Bloom Egg",
        "Blackhole Egg",
        "Solaris Egg",
        "Cherub Egg",
        "Volcanic Egg",
        "Dragon Egg",
        "Giant Egg"
    }


    local MASTER_RARITIES = {
        "Common",
        "Rare",
        "Epic",
        "Legendary",
        "Mythic",
        "Divine",
        "Ethereal",
        "Secret"
    }


    local MASTER_FOODS = {
        "Apple",
        "Banana",
        "Carrot",
        "Meat",
        "Golden Apple",
        "Energy Fruit"
    }


    local SELL_PET_NAMES = {}


    do

        for petName
            in pairs(PetData)
        do

            if type(petName)
                == "string"
            then

                table.insert(
                    SELL_PET_NAMES,
                    petName
                )

            end

        end


        table.sort(
            SELL_PET_NAMES
        )

    end


    local EGG_RARITIES = {

        ["White Egg"] = "Common",
        ["Brown Egg"] = "Common",

        ["Cracked Egg"] = "Rare",
        ["Easter Egg"] = "Rare",
        ["Stone Egg"] = "Rare",
        ["Leaf Egg"] = "Rare",

        ["Mushroom Egg"] = "Epic",
        ["Flower Egg"] = "Epic",
        ["Slime Egg"] = "Epic",
        ["Ice Egg"] = "Epic",

        ["Glass Egg"] = "Legendary",
        ["Golden Egg"] = "Legendary",

        ["Diamond Egg"] = "Mythic",
        ["Crystal Egg"] = "Mythic",
        ["Skull Egg"] = "Mythic",
        ["Asteroid Egg"] = "Mythic",
        ["Dominus Egg"] = "Mythic",
        ["Flaming Egg"] = "Mythic",
        ["Sinister Egg"] = "Mythic",
        ["Soul Egg"] = "Mythic",
        ["Tidal Egg"] = "Mythic",

        ["Aurora Egg"] = "Divine",
        ["Galaxy Egg"] = "Divine",
        ["Bloom Egg"] = "Divine",

        ["Blackhole Egg"] = "Ethereal",
        ["Solaris Egg"] = "Ethereal",
        ["Cherub Egg"] = "Ethereal",
        ["Volcanic Egg"] = "Ethereal",
        ["Dragon Egg"] = "Ethereal",
        ["Giant Egg"] = "Ethereal"

    }


    local RARITY_PRIORITY = {
        Common = 1,
        Rare = 2,
        Epic = 3,
        Legendary = 4,
        Mythic = 5,
        Divine = 6,
        Ethereal = 7,
        Secret = 8
    }


    -- ========================================================
    -- GAME MESSAGE BYPASS
    -- ========================================================

    pcall(function()

        if not getgc
            or not getfenv
            or not getupvalues
        then
            return
        end


        local playerGui =
            LocalPlayer:
            FindFirstChild(
                "PlayerGui"
            )


        local reusable =
            playerGui
            and playerGui:
                FindFirstChild(
                    "Reusable"
                )


        local gameMessages =
            reusable
            and reusable:
                FindFirstChild(
                    "GameMessages"
                )


        local handler =
            gameMessages
            and gameMessages:
                FindFirstChild(
                    "GameMessageHandler"
                )


        if not handler then
            return
        end


        for _, func
            in ipairs(getgc())
        do

            if type(func)
                == "function"
                and getfenv(func).script
                    == handler
            then

                local upvalues =
                    getupvalues(func)


                for _, value
                    in pairs(upvalues)
                do

                    if type(value)
                        == "table"
                    then

                        if value.PROMPTEVENTONRETURNEGG
                            ~= nil
                        then

                            value.PROMPTEVENTONRETURNEGG =
                                false

                        end


                        if value.STRIKEPICKEDUPEGGALWAYSONSTUDIO
                            ~= nil
                        then

                            value.STRIKEPICKEDUPEGGALWAYSONSTUDIO =
                                true

                        end
                    end
                end
            end
        end

    end)


    -- ========================================================
    -- HELPERS
    -- ========================================================

    local function GetCleanPetName(name)

        return tostring(name or "")
            :gsub(
                "%[.-%]%s*",
                ""
            )
            :match(
                "^%s*(.-)%s*$"
            )

    end


    local function GetEggRarity(
        eggName
    )

        return
            EGG_RARITIES[
                eggName
            ]
            or "Common"

    end


    local function HasSelection(
        tbl
    )

        return
            type(tbl) == "table"
            and next(tbl) ~= nil

    end


    local function MatchesFilter(
        name,
        rarity,
        nameSelection,
        raritySelection
    )

        local nameMatches =
            not HasSelection(
                nameSelection
            )
            or nameSelection[name]
                == true


        local rarityMatches =
            not HasSelection(
                raritySelection
            )
            or raritySelection[rarity]
                == true


        return
            nameMatches
            and rarityMatches

    end


    local function PositionToVector3(
        value
    )

        if typeof(value)
            == "Vector3"
        then
            return value
        end


        if typeof(value)
            == "CFrame"
        then
            return value.Position
        end


        if type(value)
            == "string"
        then

            local values = {}


            for text
                in string.gmatch(
                    value,
                    "[%-?%d%.]+"
                )
            do

                local number =
                    tonumber(text)


                if number then

                    table.insert(
                        values,
                        number
                    )

                end
            end


            if #values >= 3 then

                return
                    Vector3.new(
                        values[1],
                        values[2],
                        values[3]
                    )

            end
        end


        return nil
    end


    local function GetPlot()

        local ok, result =
            pcall(function()

                return
                    General:
                    GetPlot(
                        LocalPlayer
                    )

            end)


        if ok then
            return result
        end


        return nil
    end


    local function GetPlotCenter()

        local plot =
            GetPlot()


        if not plot then
            return nil
        end


        if plot:IsA("Model") then

            local base =
                plot:
                FindFirstChild(
                    "Baseplate"
                )
                or plot:
                FindFirstChild(
                    "Floor"
                )


            if base
                and base:IsA(
                    "BasePart"
                )
            then

                return
                    base.CFrame
            end


            return
                plot:GetPivot()

        end


        if plot:IsA(
            "BasePart"
        )
        then

            return
                plot.CFrame

        end


        return nil
    end


    local function TweenRootToPosition(
        root,
        position,
        duration
    )

        if not root
            or not root.Parent
            or typeof(position)
                ~= "Vector3"
        then

            return false

        end


        duration =
            tonumber(duration)
            or 3


        local tween =
            TweenService:
            Create(
                root,

                TweenInfo.new(
                    duration,
                    Enum.EasingStyle.Linear,
                    Enum.EasingDirection.Out
                ),

                {
                    CFrame =
                        CFrame.new(
                            position
                        )
                }
            )


        local completed =
            false

        local connection =
            tween.Completed:
            Connect(function()

                completed =
                    true

            end)


        tween:Play()


        local started =
            os.clock()


        while Runtime:IsCurrent()
            and root.Parent
            and not completed
            and os.clock()
                - started
                < duration + 0.5
        do

            task.wait(0.03)

        end


        if connection then

            connection:
            Disconnect()

        end


        if not Runtime:IsCurrent()
            or not root.Parent
        then

            pcall(function()

                tween:
                Cancel()

            end)

            return false

        end


        if not completed then

            pcall(function()

                tween:
                Cancel()

            end)

            return false

        end


        return true
    end


    local function SmoothMoveCharacter(
        character,
        root,
        targetPosition,
        duration
    )

        if not character
            or not character.Parent
            or not root
            or not root.Parent
            or typeof(targetPosition)
                ~= "Vector3"
        then

            return false

        end


        duration =
            tonumber(duration)
            or 5


        local startCFrame =
            character:
            GetPivot()


        local startPosition =
            startCFrame.Position


        local lookVector =
            startCFrame.LookVector


        local humanoid =
            character:
            FindFirstChildOfClass(
                "Humanoid"
            )


        local oldAutoRotate =
            humanoid
            and humanoid.AutoRotate


        if humanoid then

            humanoid.AutoRotate =
                false

        end


        root.AssemblyLinearVelocity =
            Vector3.zero

        root.AssemblyAngularVelocity =
            Vector3.zero


        local started =
            os.clock()


        while Runtime:IsCurrent()
            and character.Parent
            and root.Parent
        do

            local alpha =
                math.clamp(
                    (
                        os.clock()
                        - started
                    )
                    / duration,
                    0,
                    1
                )


            local position =
                startPosition:
                Lerp(
                    targetPosition,
                    alpha
                )


            character:
            PivotTo(
                CFrame.lookAt(
                    position,
                    position
                    + lookVector
                )
            )


            root.AssemblyLinearVelocity =
                Vector3.zero

            root.AssemblyAngularVelocity =
                Vector3.zero


            if alpha >= 1 then
                break
            end


            RunService.RenderStepped:
            Wait()

        end


        if humanoid
            and humanoid.Parent
        then

            humanoid.AutoRotate =
                oldAutoRotate

        end


        return
            Runtime:IsCurrent()
            and character.Parent
            and root.Parent

    end


    local function GetVolcanoEntranceCFrame()

        local volcano =
            workspace:
            FindFirstChild(
                "Volcano"
            )


        if not volcano then
            return nil
        end


        local entrance =
            volcano:
            FindFirstChild(
                "VolcanoEntrance",
                true
            )


        if not entrance then
            return nil
        end


        if entrance:IsA(
            "BasePart"
        )
        then

            return
                entrance.CFrame

        elseif entrance:IsA(
            "Model"
        )
        then

            return
                entrance:
                GetPivot()

        end


        return nil
    end


    local function GetLairDoorCFrame()

        local volcano =
            workspace:
            FindFirstChild(
                "Volcano"
            )


        if not volcano then
            return nil
        end


        -- VolcanoValidate adalah trigger utama yang kita pakai
        -- untuk masuk / keluar area Volcanic Egg.
        local validate =
            volcano:
            FindFirstChild(
                "VolcanoValidate",
                true
            )


        if validate then

            if validate:IsA(
                "BasePart"
            )
            then

                return
                    validate.CFrame

            elseif validate:IsA(
                "Model"
            )
            then

                return
                    validate:
                    GetPivot()

            end

        end


        -- Fallback kalau struktur map berubah.
        local entrance =
            volcano:
            FindFirstChild(
                "VolcanoEntrance",
                true
            )


        if entrance then

            if entrance:IsA(
                "BasePart"
            )
            then

                return
                    entrance.CFrame

            elseif entrance:IsA(
                "Model"
            )
            then

                return
                    entrance:
                    GetPivot()

            end

        end


        return nil
    end


    local function GetLairDoorPosition()

        local cf =
            GetLairDoorCFrame()


        return
            cf
            and cf.Position
            or nil

    end


    -- ========================================================
    -- EGG ARRIVAL CLAIM
    -- ========================================================

    local function SnapshotBasketNames()

        local snapshot = {}


        for _, egg
            in ipairs(
                Basket:
                GetChildren()
            )
        do

            snapshot[
                egg.Name
            ] = true

        end


        return snapshot
    end


    local function ResolveNewBasketEggIds(
        beforeSnapshot,
        timeout
    )

        timeout =
            tonumber(timeout)
            or 2


        local started =
            os.clock()


        while Runtime:IsCurrent()
            and os.clock()
                - started
                < timeout
        do

            local result = {}


            for _, egg
                in ipairs(
                    Basket:
                    GetChildren()
                )
            do

                if not beforeSnapshot[
                    egg.Name
                ]
                then

                    table.insert(
                        result,
                        egg.Name
                    )

                end

            end


            if #result > 0 then

                local allReady =
                    true


                for _, id
                    in ipairs(
                        result
                    )
                do

                    local egg =
                        Basket:
                        FindFirstChild(
                            id
                        )


                    if egg
                        and egg:
                            GetAttribute(
                                "BreakAt"
                            )
                            == nil
                    then

                        allReady =
                            false

                        break
                    end

                end


                if allReady then
                    return result
                end

            end


            task.wait(0.05)

        end


        return {}
    end


    local function FilterTrackedArrivalEggIds(
        ids
    )

        local now =
            workspace:
            GetServerTimeNow()


        local result = {}


        for _, id
            in ipairs(
                ids
                or {}
            )
        do

            local egg =
                Basket:
                FindFirstChild(
                    id
                )


            if egg then

                local breakAt =
                    tonumber(
                        egg:
                        GetAttribute(
                            "BreakAt"
                        )
                    )


                local delivering =
                    egg:
                    GetAttribute(
                        "Delivering"
                    )
                    == true


                if breakAt
                    and breakAt == breakAt
                    and math.abs(breakAt)
                        < math.huge
                    and now
                        <= breakAt + 0.5
                    and not delivering
                then

                    table.insert(
                        result,
                        id
                    )

                end

            end

        end


        return result
    end


    local function ScanEligibleArrivalEggIds()

        local ids = {}


        for _, egg
            in ipairs(
                Basket:
                GetChildren()
            )
        do

            table.insert(
                ids,
                egg.Name
            )

        end


        return
            FilterTrackedArrivalEggIds(
                ids
            )
    end


    local function GetPlotBaseplate()

        local plot =
            GetPlot()


        if not plot then
            return nil
        end


        local baseplate =
            plot:
            FindFirstChild(
                "Baseplate"
            )
            or plot:
                FindFirstChild(
                    "Floor"
                )


        if baseplate
            and baseplate:IsA(
                "BasePart"
            )
        then

            return baseplate
        end


        return nil
    end


    local function IsInsideEggDeliveryArea(
        baseplate,
        position
    )

        if not baseplate
            or typeof(position)
                ~= "Vector3"
        then

            return false
        end


        local ok,
            result =
            pcall(function()

                return
                    EggDeliveryRules.Contains(
                        baseplate,
                        position
                    )

            end)


        return
            ok
            and result
            == true
    end


    local function MoveIntoEggDeliveryArea(
        character,
        root,
        baseplate
    )

        if not character
            or not character.Parent
            or not root
            or not root.Parent
            or not baseplate
        then

            return false
        end


        -- Mulai dari titik tengah permukaan baseplate.
        local surfacePosition =
            baseplate.CFrame:
            PointToWorldSpace(
                Vector3.new(
                    0,
                    baseplate.Size.Y
                        * 0.5
                        + 2.5,
                    0
                )
            )


        character:
        PivotTo(
            CFrame.new(
                surfacePosition
            )
        )


        root.AssemblyLinearVelocity =
            Vector3.zero

        root.AssemblyAngularVelocity =
            Vector3.zero


        -- Tunggu replikasi lalu cek dengan RULE YANG SAMA seperti client game.
        local started =
            os.clock()


        while Runtime:IsCurrent()
            and root.Parent
            and os.clock()
                - started
                < 1.5
        do

            if IsInsideEggDeliveryArea(
                baseplate,
                root.Position
            )
            then

                return true
            end


            -- Kalau titik tengah belum dianggap valid, coba sedikit lebih rendah.
            local elapsed =
                os.clock()
                - started


            if elapsed > 0.45 then

                local adjusted =
                    baseplate.CFrame:
                    PointToWorldSpace(
                        Vector3.new(
                            0,
                            baseplate.Size.Y
                                * 0.5
                                + 1.0,
                            0
                        )
                    )


                character:
                PivotTo(
                    CFrame.new(
                        adjusted
                    )
                )

            end


            task.wait(0.05)

        end


        return
            IsInsideEggDeliveryArea(
                baseplate,
                root.Position
            )
    end


    local function ClaimTrackedEggArrival(
        root,
        trackedIds
    )

        if not root
            or not root.Parent
        then
            return false
        end


        local character =
            LocalPlayer.Character


        local baseplate =
            GetPlotBaseplate()


        if not character
            or not character.Parent
            or not baseplate
        then

            return false
        end


        -- ====================================================
        -- X/Z ARRIVAL BYPASS
        --
        -- EggDeliveryRules.Contains() hanya memeriksa local X/Z:
        --   abs(X) <= Size.X/2 + 2
        --   abs(Z) <= Size.Z/2 + 2
        --
        -- Y sama sekali tidak diperiksa.
        --
        -- Jadi kita tidak perlu turun ke permukaan plot. Cukup
        -- pindahkan karakter ke X/Z tengah Baseplate sambil menjaga
        -- local-Y relatif terhadap Baseplate, tunggu BreakTimer asli
        -- mendeteksi "home", lalu restore posisi lama.
        -- ====================================================

        local oldPivot =
            character:
            GetPivot()


        local oldRootCFrame =
            root.CFrame


        local localPosition =
            baseplate.CFrame:
            PointToObjectSpace(
                root.Position
            )


        local bypassWorldPosition =
            baseplate.CFrame:
            PointToWorldSpace(
                Vector3.new(
                    0,
                    localPosition.Y,
                    0
                )
            )


        local oldRotation =
            oldRootCFrame
            - oldRootCFrame.Position


        character:
        PivotTo(
            CFrame.new(
                bypassWorldPosition
            )
            * oldRotation
        )


        root.AssemblyLinearVelocity =
            Vector3.zero

        root.AssemblyAngularVelocity =
            Vector3.zero


        -- Pastikan rule client sendiri menganggap kita berada di home.
        if not IsInsideEggDeliveryArea(
            baseplate,
            root.Position
        )
        then

            -- Fallback paling aman: pusat X/Z dengan local-Y 3 studs
            -- di atas origin Baseplate. Y tidak memengaruhi Contains.
            bypassWorldPosition =
                baseplate.CFrame:
                PointToWorldSpace(
                    Vector3.new(
                        0,
                        3,
                        0
                    )
                )


            character:
            PivotTo(
                CFrame.new(
                    bypassWorldPosition
                )
                * oldRotation
            )


            root.AssemblyLinearVelocity =
                Vector3.zero

            root.AssemblyAngularVelocity =
                Vector3.zero

        end


        -- Biarkan BreakTimer bawaan game berjalan lebih dulu.
        -- Heartbeat-nya mengecek sekitar tiap 0.1 detik.
        local started =
            os.clock()


        while Runtime:IsCurrent()
            and autoFarmActive
            and root.Parent
            and os.clock()
                - started
                < 0.65
        do

            root.AssemblyLinearVelocity =
                Vector3.zero

            root.AssemblyAngularVelocity =
                Vector3.zero


            local pending =
                FilterTrackedArrivalEggIds(
                    trackedIds
                )


            if #pending == 0 then

                pending =
                    ScanEligibleArrivalEggIds()

            end


            if #pending == 0 then

                if character.Parent then

                    character:
                    PivotTo(
                        oldPivot
                    )

                end


                return true
            end


            task.wait(0.05)

        end


        -- Kalau BreakTimer asli belum claim, kirim remote dengan:
        -- current server time + HRP.Position aktual + GUID yang masih pending.
        local ids =
            FilterTrackedArrivalEggIds(
                trackedIds
            )


        if #ids == 0 then

            ids =
                ScanEligibleArrivalEggIds()

        end


        if #ids > 0
            and root.Parent
            and IsInsideEggDeliveryArea(
                baseplate,
                root.Position
            )
        then

            local ok,
                err =
                pcall(function()

                    EggArrivalClaimRemote:
                    FireServer(
                        workspace:
                        GetServerTimeNow(),
                        root.Position,
                        ids
                    )

                end)


            if not ok then

                warn(
                    "[CHLISE HUB] EggArrivalClaim X/Z bypass failed:",
                    err
                )


                NotifyWebhookError(
                    "EggArrivalClaim X/Z bypass failed: "
                    .. tostring(
                        err
                    )
                )

            end


            task.wait(0.45)

        end


        local remaining =
            FilterTrackedArrivalEggIds(
                ids
            )


        local success =
            #remaining == 0


        -- Restore posisi sebelum bypass setelah server diberi waktu
        -- menerima arrival. Tidak mengubah logic Volcano Dip.
        if character.Parent then

            character:
            PivotTo(
                oldPivot
            )

        end


        return success
    end


    -- ========================================================
    -- RENDERED EGG MATCHING
    -- ========================================================

    local RENDERED_EGG_MAX_DISTANCE =
        15


    local function GetRenderedEggsFolder()

        return
            workspace:
            FindFirstChild(
                "RenderedEggs"
            )

    end


    local function GetEggPickupPrompt(
        eggModel
    )

        if not eggModel
            or not eggModel.Parent
        then
            return nil
        end


        local pickup =
            eggModel:
            FindFirstChild(
                "Pickup",
                true
            )


        if pickup
            and pickup:IsA(
                "ProximityPrompt"
            )
            and pickup.Enabled
        then

            return pickup

        end


        return nil
    end


    local function FindRenderedEgg(
        eggName,
        targetPosition,
        maxDistance
    )

        if type(eggName)
                ~= "string"
            or eggName == ""
            or typeof(targetPosition)
                ~= "Vector3"
        then

            return nil, nil, math.huge

        end


        local renderedEggs =
            GetRenderedEggsFolder()


        if not renderedEggs then
            return nil, nil, math.huge
        end


        maxDistance =
            tonumber(maxDistance)
            or RENDERED_EGG_MAX_DISTANCE


        local bestModel =
            nil

        local bestPrompt =
            nil

        local bestDistance =
            math.huge


        for _, eggModel
            in ipairs(
                renderedEggs:
                GetChildren()
            )
        do

            if eggModel:IsA(
                    "Model"
                )
                and eggModel.Name
                    == eggName
            then

                local ok,
                    modelPosition =
                    pcall(function()

                        return
                            eggModel:
                            GetPivot()
                            .Position

                    end)


                if ok
                    and typeof(modelPosition)
                        == "Vector3"
                then

                    local distance =
                        (
                            modelPosition
                            - targetPosition
                        ).Magnitude


                    if distance
                        < bestDistance
                    then

                        local pickup =
                            GetEggPickupPrompt(
                                eggModel
                            )


                        if pickup then

                            bestDistance =
                                distance

                            bestModel =
                                eggModel

                            bestPrompt =
                                pickup

                        end

                    end

                end

            end

        end


        if not bestModel
            or bestDistance
                > maxDistance
        then

            return nil, nil, bestDistance

        end


        return
            bestModel,
            bestPrompt,
            bestDistance
    end


    local function WaitForRenderedEgg(
        eggName,
        targetPosition,
        timeout,
        maxDistance
    )

        timeout =
            tonumber(timeout)
            or 2


        local started =
            os.clock()


        repeat

            local eggModel,
                pickup =
                FindRenderedEgg(
                    eggName,
                    targetPosition,
                    maxDistance
                )


            if eggModel
                and pickup
            then

                return
                    eggModel,
                    pickup

            end


            task.wait(0.1)

        until os.clock()
            - started
            >= timeout


        return nil, nil
    end


    local function GetCharacterData()

        local character =
            LocalPlayer.Character


        if not character then
            return nil
        end


        return
            character,

            character:
            FindFirstChildOfClass(
                "Humanoid"
            ),

            character:
            FindFirstChild(
                "HumanoidRootPart"
            )

    end


    -- ========================================================
    -- REBIRTH HELPERS
    -- Mengikuti syarat client game:
    -- - belum mencapai cap
    -- - Cash >= cost rebirth berikutnya
    -- - punya pet requirement untuk tier berikutnya
    -- ========================================================

    local function OwnsRequiredRebirthPet(
        requiredPet
    )

        if type(requiredPet)
            ~= "string"
            or requiredPet == ""
        then

            return false

        end


        local function ScanTools(
            container
        )

            if not container then
                return false
            end


            for _, child
                in ipairs(
                    container:
                    GetChildren()
                )
            do

                if child:IsA("Tool")
                    and child:
                        GetAttribute(
                            "PetKey"
                        )
                then

                    local cleanName =
                        GetCleanPetName(
                            child.Name
                        )


                    local petName =
                        child:
                        GetAttribute(
                            "PetName"
                        )


                    if cleanName
                            == requiredPet
                        or GetCleanPetName(
                            petName
                        )
                            == requiredPet
                    then

                        return true

                    end

                end

            end


            return false
        end


        if ScanTools(
            LocalPlayer:
            FindFirstChild(
                "Backpack"
            )
        )
        then

            return true

        end


        local character =
            LocalPlayer.Character


        if ScanTools(
            character
        )
        then

            return true

        end


        -- Pet yang sedang dinaiki bisa tidak berada di Backpack.
        local root =
            character
            and character:
                FindFirstChild(
                    "HumanoidRootPart"
                )


        local mountJoint =
            root
            and root:
                FindFirstChild(
                    "PetMountJoint"
                )


        local mountedPet =
            mountJoint
            and mountJoint.Part1
            and mountJoint.Part1.Parent


        if mountedPet then

            local mountedName =
                mountedPet:
                GetAttribute(
                    "PetName"
                )
                or mountedPet.Name


            if GetCleanPetName(
                mountedName
            )
                == requiredPet
            then

                return true

            end

        end


        return false
    end


    local function GetRebirthEligibility()

        local currentRebirths =
            tonumber(
                RebirthsValue.Value
            )
            or 0


        local cap =
            tonumber(
                RebirthsData.Cap
            )


        if cap
            and currentRebirths
                >= cap
        then

            return
                false,
                "CapReached",
                currentRebirths

        end


        local cost =
            tonumber(
                RebirthsData:
                GetCost(
                    currentRebirths
                )
            )


        if not cost then

            return
                false,
                "NoCost",
                currentRebirths

        end


        if (
            tonumber(
                CashValue.Value
            )
            or 0
        )
            < cost
        then

            return
                false,
                "NotEnoughCash",
                currentRebirths

        end


        local requirements =
            GeneralData.RebirthRequirements


        if type(requirements)
            ~= "table"
            or #requirements
                == 0
        then

            return
                false,
                "NoRequirements",
                currentRebirths

        end


        local requirementIndex =
            math.clamp(
                currentRebirths + 1,
                1,
                #requirements
            )


        local requiredPet =
            requirements[
                requirementIndex
            ]


        if not OwnsRequiredRebirthPet(
            requiredPet
        )
        then

            return
                false,
                "MissingPet",
                currentRebirths

        end


        return
            true,
            nil,
            currentRebirths

    end


    local function GetRarityColor(
        rarity
    )

        rarity =
            string.lower(
                tostring(
                    rarity or ""
                )
            )


        if rarity:find(
            "legendary"
        )
        then

            return
                Color3.fromRGB(
                    255,
                    215,
                    0
                )

        elseif rarity:find(
            "epic"
        )
        then

            return
                Color3.fromRGB(
                    163,
                    53,
                    238
                )

        elseif rarity:find(
            "rare"
        )
        then

            return
                Color3.fromRGB(
                    0,
                    112,
                    221
                )

        elseif rarity:find(
            "mythic"
        )
        then

            return
                Color3.fromRGB(
                    255,
                    0,
                    0
                )

        elseif rarity:find(
            "divine"
        )
        then

            return
                Color3.fromRGB(
                    0,
                    255,
                    255
                )

        elseif rarity:find(
            "ethereal"
        )
        then

            return
                Color3.fromRGB(
                    255,
                    0,
                    255
                )

        end


        return
            Color3.fromRGB(
                255,
                255,
                255
            )
    end

    local function GetServerPlayerNames()

    local names = {}

        for _, player in ipairs(
            Players:GetPlayers()
        ) do

            if player ~= LocalPlayer then

                table.insert(
                    names,
                    player.Name
                )

            end
        end

        table.sort(names)

        return names
    end


    local function GetPlayerByName(
        name
    )

        if not name then
            return nil
        end

        for _, player in ipairs(
            Players:GetPlayers()
        ) do

            if player.Name == name then
                return player
            end

        end

        return nil
    end

    local function GetPlayerPlot(
        player
    )

        if not player then
            return nil
        end

        local plots =
            workspace:
            FindFirstChild("Plots")

        if not plots then
            return nil
        end

        for _, plot in ipairs(
            plots:GetChildren()
        ) do

            local data =
                plot:
                FindFirstChild("Data")

            local owner =
                data
                and data:
                    FindFirstChild("Owner")

            if owner then

                local value =
                    owner.Value

                if value == player
                    or value == player.Name
                    or value == player.UserId
                    or tostring(value)
                        == tostring(player.UserId)
                then

                    return plot
                end
            end
        end

        return nil
    end

    local function GetPlotFrontCFrame(
        plot
    )

        if not plot then
            return nil
        end

        local base =
            plot:
            FindFirstChild("Baseplate")
            or plot:
            FindFirstChild("Floor")

        if not base
            or not base:IsA("BasePart")
        then
            return nil
        end

        local frontPosition =
            base.Position
            + base.CFrame.LookVector
                * (
                    base.Size.Z / 2
                    + 6
                )
            + Vector3.new(
                0,
                3,
                0
            )

        return CFrame.new(
            frontPosition,
            frontPosition
                + base.CFrame.LookVector
        )
    end

    -- ========================================================
    -- GO VOLCANO DIP
    -- ========================================================

    local VOLCANO_DIP_POSITION =
        Vector3.new(
            -5102.8427734375,
            41411.62890625,
            -3489.114013671875
        )


    local function HasVolcanoFlight()

        local now =
            workspace:
            GetServerTimeNow()


        for _, child
            in ipairs(
                Basket:
                GetChildren()
            )
        do

            local volcanoUntil =
                child:
                GetAttribute(
                    "VolcanoUntil"
                )


            if type(volcanoUntil)
                    == "number"
                and now
                    < volcanoUntil
            then

                return true

            end

        end


        return false
    end


    local function HasEligibleVolcanoEgg()

        local now =
            workspace:
            GetServerTimeNow()


        for _, child
            in ipairs(
                Basket:
                GetChildren()
            )
        do

            if child:
                    GetAttribute(
                        "VolcanoDipped"
                    )
                    ~= true
                and child:
                    GetAttribute(
                        "Delivering"
                    )
                    ~= true
            then

                local volcanoUntil =
                    child:
                    GetAttribute(
                        "VolcanoUntil"
                    )


                if type(volcanoUntil)
                        ~= "number"
                    or not (
                        now
                        < volcanoUntil
                    )
                then

                    return true

                end

            end

        end


        return false
    end


    local function WaitForVolcanoDipButton(
        timeout
    )

        timeout =
            tonumber(timeout)
            or 2


        local playerGui =
            LocalPlayer:
            FindFirstChild(
                "PlayerGui"
            )


        local main =
            playerGui
            and playerGui:
                FindFirstChild(
                    "Main"
                )


        local actionsHolder =
            main
            and main:
                FindFirstChild(
                    "ActionsHolder"
                )


        local button =
            actionsHolder
            and actionsHolder:
                FindFirstChild(
                    "DropEggVolcanoButton"
                )


        if not button then

            return false

        end


        local started =
            os.clock()


        repeat

            if button.Visible then

                return true

            end


            task.wait(0.05)

        until os.clock()
            - started
            >= timeout


        return false
    end


    local function WaitForBasketEgg(
        timeout
    )

        timeout =
            tonumber(timeout)
            or 1.5


        local started =
            os.clock()


        repeat

            if #Basket:GetChildren()
                > 0
            then

                return true

            end


            task.wait(0.05)

        until os.clock()
            - started
            >= timeout


        return false
    end


    local function GoVolcanoDipCurrentEgg()

        local character,
            root =
            GetCharacterData()


        if not character
            or not root
        then

            warn(
                "[CHLISE HUB] Volcano Dip: character/root missing."
            )

            return false

        end


        -- Force teleport seluruh character ke koordinat Volcano Dip.
        -- PivotTo lebih tegas daripada hanya mengubah HRP.CFrame.
        character:
        PivotTo(
            CFrame.new(
                VOLCANO_DIP_POSITION
            )
        )


        -- Beri waktu posisi tereplikasi dan tombol game muncul.
        task.wait(0.5)


        local buttonReady =
            WaitForVolcanoDipButton(
                3
            )


        if not buttonReady then

            warn(
                "[CHLISE HUB] Volcano Dip: button did not appear."
            )

            -- Tetap stay sebentar di titik volcano saat testing.
            task.wait(1)

            return false

        end


        local ok,
            err =
            pcall(function()

                VolcanoDipRemote:
                FireServer()

            end)


        if not ok then

            warn(
                "[CHLISE HUB] VolcanoDip remote failed:",
                err
            )

            return false

        end


        -- Tetap di atas Volcano Dip selama 4 detik.
        task.wait(4)


        return true
    end


    local function GiftCurrentEgg()

        if not giftEggActive then
            return false
        end

        if not selectedGiftPlayer then
            return false
        end

        local targetPlayer =
            GetPlayerByName(
                selectedGiftPlayer
            )

        if not targetPlayer then
            return false
        end

        local targetPlot =
            GetPlayerPlot(
                targetPlayer
            )

        if not targetPlot then
            return false
        end

        local targetCF =
            GetPlotFrontCFrame(
                targetPlot
            )

        if not targetCF then
            return false
        end

        local character,
            humanoid,
            root =
            GetCharacterData()

        if not root then
            return false
        end

        local basket =
            LocalPlayer:
            FindFirstChild("Basket")

        if not basket
            or #basket:GetChildren() == 0
        then
            return false
        end

        local oldCF =
            root.CFrame

        root.CFrame =
            targetCF

        task.wait(0.35)

        BasketDrop:
        FireServer()

        local started =
            os.clock()

        while os.clock() - started < 2 do

            if #basket:GetChildren() == 0 then
                break
            end

            task.wait(0.05)
        end

        if root.Parent then
            root.CFrame =
                oldCF
        end

        return true
    end

    -- ========================================================
    -- SERVER HOP HELPERS
    -- ========================================================

    local SERVER_HOP_DELAYS = {
        "10 Seconds",
        "20 Seconds",
        "30 Seconds",
        "45 Seconds",
        "60 Seconds",
        "90 Seconds",
        "120 Seconds"
    }


    local function ParseServerHopDelay(
        value
    )

        local number =
            tonumber(
                tostring(
                    value or ""
                ):
                match("%d+")
            )


        if not number then
            return 30
        end


        return
            math.clamp(
                number,
                10,
                300
            )
    end


    local function GetPublicServers(
        cursor
    )

        local url =
            "https://games.roblox.com/v1/games/"
            .. tostring(game.PlaceId)
            .. "/servers/Public?sortOrder=Asc&limit=100"


        if cursor
            and cursor ~= ""
        then

            url =
                url
                .. "&cursor="
                .. HttpService:
                    UrlEncode(
                        cursor
                    )
        end


        local requestOk,
            response =
            pcall(
                game.HttpGet,
                game,
                url
            )


        if not requestOk
            or type(response) ~= "string"
        then

            warn(
                "[CHLISE HUB] Server list request failed:",
                response
            )

            return nil
        end


        local decodeOk,
            data =
            pcall(
                HttpService.JSONDecode,
                HttpService,
                response
            )


        if not decodeOk
            or type(data) ~= "table"
        then

            warn(
                "[CHLISE HUB] Invalid server list response."
            )

            return nil
        end


        return data
    end


    local function FindServerHopTarget()

        local currentJobId =
            game.JobId

        local cursor =
            nil

        local pagesChecked =
            0

        local candidates =
            {}


        repeat

            pagesChecked += 1


            local data =
                GetPublicServers(
                    cursor
                )


            if not data
                or type(data.data) ~= "table"
            then
                break
            end


            for _, server
                in ipairs(
                    data.data
                )
            do

                local serverId =
                    server.id

                local playing =
                    tonumber(
                        server.playing
                    )
                    or 0

                local maxPlayers =
                    tonumber(
                        server.maxPlayers
                    )
                    or 0


                if serverId
                    and serverId ~= ""
                    and serverId ~= currentJobId
                    and playing < maxPlayers
                    and not ServerHopState.Visited[
                        serverId
                    ]
                then

                    table.insert(
                        candidates,
                        server
                    )
                end
            end


            -- Begitu ada beberapa pilihan, tidak perlu
            -- membanjiri API dengan page berikutnya.
            if #candidates >= 8 then
                break
            end


            cursor =
                data.nextPageCursor

        until not cursor
            or cursor == ""
            or pagesChecked >= 8


        if #candidates == 0 then
            return nil
        end


        return
            candidates[
                math.random(
                    1,
                    #candidates
                )
            ]
    end


    local function ResetVisitedServers()

        Utils.ClearTable(
            ServerHopState.Visited
        )


        if game.JobId
            and game.JobId ~= ""
        then

            ServerHopState.Visited[
                game.JobId
            ] = true
        end
    end


    local function ServerHop(
        reason
    )

        if ServerHopState.Hopping then
            return false
        end


        ServerHopState.Hopping =
            true


        if game.JobId
            and game.JobId ~= ""
        then

            ServerHopState.Visited[
                game.JobId
            ] = true
        end


        local target =
            FindServerHopTarget()


        -- Semua server yang ketemu sudah pernah dikunjungi.
        -- Mulai pool baru, tapi tetap jangan pilih server saat ini.
        if not target then

            ResetVisitedServers()

            target =
                FindServerHopTarget()
        end


        if not target
            or not target.id
        then

            ServerHopState.Hopping =
                false

            warn(
                "[CHLISE HUB] No available server found."
            )


            NotifyWebhookError(
                "Server Hop failed: no available server found."
            )

            return false
        end


        local targetId =
            target.id


        ServerHopState.Visited[
            targetId
        ] = true


        print(
            "[CHLISE HUB] Server Hop:",
            reason or "Manual",
            "->",
            targetId
        )


        if webhookServerHopActive then

            task.spawn(function()

                SendWebhook(
                    "Chlise Hub — Server Hop",
                    {
                        {
                            name =
                                "Reason",

                            value =
                                tostring(
                                    reason
                                    or "Manual"
                                )
                        },

                        {
                            name =
                                "Current Server",

                            value =
                                tostring(
                                    game.JobId
                                ),

                            inline =
                                false
                        },

                        {
                            name =
                                "Target Server",

                            value =
                                tostring(
                                    targetId
                                ),

                            inline =
                                false
                        }
                    }
                )

            end)

        end


        local teleportOk,
            teleportError =
            pcall(function()

                TeleportService:
                TeleportToPlaceInstance(
                    game.PlaceId,
                    targetId,
                    LocalPlayer
                )

            end)


        if not teleportOk then

            ServerHopState.Hopping =
                false

            warn(
                "[CHLISE HUB] Server Hop failed:",
                teleportError
            )


            NotifyWebhookError(
                "Server Hop failed: "
                .. tostring(
                    teleportError
                )
            )

            return false
        end


        -- Jika TeleportService tidak benar-benar memindahkan
        -- player, izinkan percobaan berikutnya setelah cooldown.
        local sourceJobId =
            game.JobId


        task.delay(
            10,

            function()

                if Runtime:IsCurrent()
                    and game.JobId
                        == sourceJobId
                then

                    ServerHopState.Hopping =
                        false
                end

            end
        )


        return true
    end


    Runtime:TrackConnection(

        TeleportService.TeleportInitFailed:
        Connect(function(
            player
        )

            if player
                == LocalPlayer
            then

                ServerHopState.Hopping =
                    false

            end

        end)

    )


    -- ========================================================
    -- TABS
    -- ========================================================

    local FarmTab =
        Window:AddTab(
            "FARM",
            "◆"
        )


    local ProgressTab =
        Window:AddTab(
            "PROGRESS",
            "▲"
        )


    local ESPTab =
        Window:AddTab(
            "ESP",
            "◎"
        )


    local WebhookTab =
        Window:AddTab(
            "WEBHOOK",
            "✦"
        )


    local ServerTab =
        Window:AddTab(
            "SERVER",
            "◇"
        )


    -- Paksa urutan sidebar:
    -- FARM -> PROGRESS -> ESP -> WEBHOOK -> SERVER -> SETTINGS
    if FarmTab
        and FarmTab.Button
    then
        FarmTab.Button.LayoutOrder = 1
    end


    if ProgressTab
        and ProgressTab.Button
    then
        ProgressTab.Button.LayoutOrder = 2
    end


    if ESPTab
        and ESPTab.Button
    then
        ESPTab.Button.LayoutOrder = 3
    end


    if WebhookTab
        and WebhookTab.Button
    then
        WebhookTab.Button.LayoutOrder = 4
    end


    if ServerTab
        and ServerTab.Button
    then
        ServerTab.Button.LayoutOrder = 5
    end


    local ExistingSettingsTab =
        Window.Tabs
        and Window.Tabs[
            "SETTINGS"
        ]


    if ExistingSettingsTab
        and ExistingSettingsTab.Button
    then
        ExistingSettingsTab.Button.LayoutOrder = 6
    end


    -- ========================================================
    -- FARM UI
    -- ========================================================

    local FarmSection =
        Window:AddSection(
            FarmTab,
            "Eggs Farm"
        )


    FarmSection:AddDropdown(
        "EggsFarm",
        "Eggs Farm",
        MASTER_EGGS,
        true,
        selectedEggsFarm,

        function(value)
            selectedEggsFarm = value
        end
    )


    FarmSection:AddDropdown(
        "RaritiesFarm",
        "Rarities Farm",
        MASTER_RARITIES,
        true,
        selectedRaritiesFarm,

        function(value)
            selectedRaritiesFarm = value
        end
    )


    FarmSection:AddTextbox(
        "MinimumEggWeight",
        "Minimum Weight",
        "Example: 5",

        function(value)

            local normalized =
                tostring(
                    value or ""
                ):
                gsub(
                    ",",
                    "."
                )


            local parsed =
                tonumber(
                    normalized
                )


            if parsed
                and parsed > 0
            then

                minimumEggWeight =
                    parsed

            else

                -- Blank / invalid / 0 / negative = filter off.
                minimumEggWeight =
                    0

            end

        end
    )


    local GiftPlayerDropdown =
        FarmSection:AddDropdown(
            "GiftPlayer",
            "Player Selection",
            GetServerPlayerNames(),
            false,
            nil,

            function(value)

                selectedGiftPlayer =
                    value

            end,

            false
        )


    local function RefreshGiftPlayers()

        if GiftPlayerDropdown
            and GiftPlayerDropdown.SetOptions
        then

            GiftPlayerDropdown.SetOptions(
                GetServerPlayerNames(),
                true
            )

        end
    end


    Runtime:TrackConnection(

        Players.PlayerAdded:
        Connect(function()

            task.wait(0.5)

            RefreshGiftPlayers()

        end)

    )


    Runtime:TrackConnection(

        Players.PlayerRemoving:
        Connect(function(player)

            if selectedGiftPlayer
                == player.Name
            then

                selectedGiftPlayer =
                    nil
            end

            task.wait(0.1)

            RefreshGiftPlayers()

        end)

    )


    FarmSection:AddToggle(
        "GiftEgg",
        "Gift Egg",
        false,

        function(state)

            giftEggActive =
                state

        end
    )


    FarmSection:AddToggle(
        "GoVolcanoDip",
        "Go Volcano Dip",
        false,

        function(state)

            goVolcanoDipActive =
                state

        end
    )


    -- ========================================================
    -- WEBHOOK - WORLD EGG
    -- Event-based, tidak polling.
    -- ========================================================

    local function HandleWorldEggWebhook(
        eggObject
    )

        if not webhookWorldEggActive
            or not eggObject
        then
            return
        end


        local eggName =
            eggObject:
            GetAttribute(
                "Egg"
            )


        if not IsWebhookEggSelected(
            eggName
        )
        then
            return
        end


        local eggId =
            eggObject.Name


        if WebhookState.SentWorldEggs[
            eggId
        ]
        then
            return
        end


        WebhookState.SentWorldEggs[
            eggId
        ] = true


        local rarity =
            GetEggRarity(
                eggName
            )


        local area =
            eggObject:
            GetAttribute(
                "Area"
            )


        task.spawn(function()

            SendWebhook(
                "Chlise Hub — World Egg Spawned",
                {
                    {
                        name =
                            "Egg",

                        value =
                            tostring(
                                eggName
                            )
                    },

                    {
                        name =
                            "Rarity",

                        value =
                            tostring(
                                rarity
                                or "Unknown"
                            )
                    },

                    {
                        name =
                            "Area",

                        value =
                            tostring(
                                area
                                or "Unknown"
                            )
                    }
                }
            )

        end)

    end


    do

        local serverData =
            ReplicatedStorage:
            FindFirstChild(
                "ServerData"
            )


        local activeEggs =
            serverData
            and serverData:
                FindFirstChild(
                    "ActiveEggs"
                )


        if activeEggs then

            Runtime:TrackConnection(

                activeEggs.ChildAdded:
                Connect(function(
                    eggObject
                )

                    task.wait(0.05)

                    HandleWorldEggWebhook(
                        eggObject
                    )

                end)

            )


            Runtime:TrackConnection(

                activeEggs.ChildRemoved:
                Connect(function(
                    eggObject
                )

                    if eggObject then

                        WebhookState.SentWorldEggs[
                            eggObject.Name
                        ] = nil

                    end

                end)

            )

        end

    end


    -- ========================================================
    -- AUTO FARM
    -- ========================================================

    FarmSection:AddToggle(
        "AutoFarm",
        "Auto Farm",
        false,

        function(state)

            autoFarmActive =
                state


            if not state then

                noTargetSince =
                    nil

            end

        end
    )


    -- ========================================================
    -- SERVER HOP UI
    -- ========================================================

    -- ========================================================
    -- WEBHOOK UI
    -- ========================================================

    local WebhookSection =
        Window:AddSection(
            WebhookTab,
            "Webhook"
        )


    WebhookSection:AddTextbox(
        "WebhookURL",
        "Webhook URL",
        "https://discord.com/api/webhooks/...",

        function(value)

            webhookUrl =
                TrimWebhookText(
                    value
                )

        end
    )


    WebhookSection:AddButton(
        "Test Webhook",

        function()

            task.spawn(function()

                local sent =
                    SendWebhook(
                        "Chlise Hub — Test Webhook",
                        {
                            {
                                name =
                                    "Status",

                                value =
                                    "Webhook connected successfully.",

                                inline =
                                    false
                            },

                            {
                                name =
                                    "Player",

                                value =
                                    LocalPlayer.Name
                            }
                        }
                    )


                if not sent then

                    warn(
                        "[CHLISE HUB] Test Webhook failed."
                    )

                end

            end)

        end
    )


    WebhookSection:AddCheckbox(
        "WebhookWorldEgg",
        "World Egg",
        false,

        function(state)

            webhookWorldEggActive =
                state

        end
    )


    WebhookSection:AddDropdown(
        "WebhookWorldEggSelection",
        "World Egg Selection",
        MASTER_EGGS,
        true,
        selectedWebhookWorldEggs,

        function(value)

            selectedWebhookWorldEggs =
                value

        end
    )


    WebhookSection:AddCheckbox(
        "WebhookEggPickedUp",
        "Egg Picked Up",
        false,

        function(state)

            webhookEggPickedUpActive =
                state

        end
    )


    WebhookSection:AddCheckbox(
        "WebhookVolcanoDip",
        "Volcano Dip",
        false,

        function(state)

            webhookVolcanoDipActive =
                state

        end
    )


    WebhookSection:AddCheckbox(
        "WebhookGiftEgg",
        "Gift Egg",
        false,

        function(state)

            webhookGiftEggActive =
                state

        end
    )


    WebhookSection:AddCheckbox(
        "WebhookRebirth",
        "Rebirth",
        false,

        function(state)

            webhookRebirthActive =
                state

        end
    )


    WebhookSection:AddCheckbox(
        "WebhookServerHop",
        "Server Hop",
        false,

        function(state)

            webhookServerHopActive =
                state

        end
    )


    WebhookSection:AddCheckbox(
        "WebhookErrors",
        "Errors",
        false,

        function(state)

            webhookErrorsActive =
                state

        end
    )


    local ServerSection =
        Window:AddSection(
            ServerTab,
            "Server Hop"
        )


    ServerSection:AddButton(
        "Server Hop",

        function()

            task.spawn(function()

                ServerHop(
                    "Manual"
                )

            end)

        end
    )


    ServerSection:AddToggle(
        "AutoServerHop",
        "Auto Server Hop",
        false,

        function(state)

            autoServerHopActive =
                state

            noTargetSince =
                nil

        end
    )


    ServerSection:AddDropdown(
        "ServerHopDelay",
        "Hop Delay",
        SERVER_HOP_DELAYS,
        false,
        "30 Seconds",

        function(value)

            serverHopDelay =
                ParseServerHopDelay(
                    value
                )

            noTargetSince =
                nil

        end
    )


    -- ========================================================
    -- PLACE EGG UI
    -- ========================================================

    local PlaceSection =
        Window:AddSection(
            FarmTab,
            "Place Egg"
        )


    PlaceSection:AddDropdown(
        "EggsPlace",
        "Eggs Place",
        MASTER_EGGS,
        true,
        selectedEggsPlace,

        function(value)

            selectedEggsPlace =
                value

        end
    )


    PlaceSection:AddDropdown(
        "RaritiesPlace",
        "Rarities Place",
        MASTER_RARITIES,
        true,
        selectedRaritiesPlace,

        function(value)

            selectedRaritiesPlace =
                value

        end
    )


    PlaceSection:AddToggle(
        "PlaceEgg",
        "Place Egg",
        false,

        function(state)

            placeEggActive =
                state

        end
    )


    -- ========================================================
    -- HATCH UI
    -- ========================================================

    local HatchSection =
        Window:AddSection(
            FarmTab,
            "Hatch Egg"
        )


    HatchSection:AddToggle(
        "AutoHatch",
        "Auto Hatch",
        false,

        function(state)

            autoHatchActive =
                state

        end
    )


    -- ========================================================
    -- PROGRESS / PET SETTINGS
    -- ========================================================

    local PetSection =
        Window:AddSection(
            ProgressTab,
            "Pet Setting"
        )


    PetSection:AddToggle(
        "AutoPlaceBestPet",
        "Auto Place Best Pet",
        false,

        function(state)

            autoPlaceBestPetActive =
                state

        end
    )


    PetSection:AddToggle(
        "AutoRideBestPet",
        "Auto Ride Best Pet",
        false,

        function(state)

            autoRideBestPetActive =
                state

        end
    )


    -- ========================================================
    -- FEED PET
    -- PLACEHOLDER ONLY
    -- ========================================================

    local FeedSection =
        Window:AddSection(
            ProgressTab,
            "Feed Pet"
        )


    FeedSection:AddDropdown(
        "Foods",
        "Food Selection",
        MASTER_FOODS,
        true,
        selectedFoods,

        function(value)

            selectedFoods =
                value

        end
    )


    FeedSection:AddToggle(
        "AutoFeedPet",
        "Auto Feed Pet",
        false,

        function(state)

            autoFeedPetActive =
                state

            -- Belum ada logic Feed Pet.

        end
    )


    -- ========================================================
    -- UPDATE
    -- ========================================================

    local UpdateSection =
        Window:AddSection(
            ProgressTab,
            "Update"
        )


    UpdateSection:AddToggle(
        "AutoUpdateHatchLuck",
        "Auto Update Hatch Luck",
        false,

        function(state)

            autoUpdateHatchLuckActive =
                state

        end
    )


    UpdateSection:AddToggle(
        "AutoMaxHatchLuck",
        "Auto Max Hatch Luck",
        false,

        function(state)

            autoMaxHatchLuckActive =
                state

        end
    )


    UpdateSection:AddToggle(
        "AutoRebirth",
        "Auto Rebirth",
        false,

        function(state)

            autoRebirthActive =
                state

        end
    )


    -- ========================================================
    -- SELL
    -- ========================================================

    local SellSection =
        Window:AddSection(
            ProgressTab,
            "Sell"
        )


    SellSection:AddDropdown(
        "SellRarities",
        "Rarity Selection",
        MASTER_RARITIES,
        true,
        selectedSellRarities,

        function(value)

            selectedSellRarities =
                value

        end
    )


    SellSection:AddToggle(
        "AutoSellByRarity",
        "Auto Sell By Rarity",
        false,

        function(state)

            autoSellByRarityActive =
                state

        end
    )


    SellSection:AddDropdown(
        "SellPetNames",
        "Pet Selection",
        SELL_PET_NAMES,
        true,
        selectedSellPetNames,

        function(value)

            selectedSellPetNames =
                value

        end
    )


    SellSection:AddToggle(
        "AutoSellByName",
        "Auto Sell By Name",
        false,

        function(state)

            autoSellByNameActive =
                state

        end
    )


    -- ========================================================
    -- FAVORITE
    -- ========================================================

    local FavoriteSection =
        Window:AddSection(
            ProgressTab,
            "Favorite"
        )


    FavoriteSection:AddDropdown(
        "FavoriteRarities",
        "Rarity Selection",
        MASTER_RARITIES,
        true,
        selectedFavoriteRarities,

        function(value)

            selectedFavoriteRarities =
                value

        end
    )


    FavoriteSection:AddToggle(
        "AutoFavoriteByRarity",
        "Auto Favorite By Rarity",
        false,

        function(state)

            autoFavoriteByRarityActive =
                state

        end
    )


    FavoriteSection:AddToggle(
        "AutoUnfavoriteByRarity",
        "Auto Unfavorite By Rarity",
        false,

        function(state)

            autoUnfavoriteByRarityActive =
                state

        end
    )


    -- ========================================================
    -- ESP
    -- ========================================================

    local ESPSection =
        Window:AddSection(
            ESPTab,
            "ESP Settings"
        )


    ESPSection:AddToggle(
        "ESPWorldEggs",
        "ESP World Eggs",
        false,

        function(state)

            espEggsEnabled =
                state

        end
    )


    ESPSection:AddToggle(
        "ESPInventoryPet",
        "ESP Inventory Pet",
        false,

        function(state)

            espInventoryEnabled =
                state

        end
    )


    -- ========================================================
    -- PERFORMANCE BACKUPS
    -- ========================================================

    local lowGraphicBackup =
        nil


    local fpsBackups =
        {}


    local function EnableLowGraphic()

        if not lowGraphicBackup then

            lowGraphicBackup = {
                GlobalShadows =
                    Lighting.GlobalShadows,

                FogEnd =
                    Lighting.FogEnd
            }

        end


        Lighting.GlobalShadows =
            false

        Lighting.FogEnd =
            9e9

    end


    local function DisableLowGraphic()

        if not lowGraphicBackup then
            return
        end


        Lighting.GlobalShadows =
            lowGraphicBackup.GlobalShadows


        Lighting.FogEnd =
            lowGraphicBackup.FogEnd


        lowGraphicBackup =
            nil

    end


    local function EnableFPSBoost()

        for _, object
            in ipairs(
                workspace:
                GetDescendants()
            )
        do

            if object:IsA(
                "BasePart"
            )
            then

                if not fpsBackups[
                    object
                ]
                then

                    fpsBackups[object] = {
                        Type = "Material",
                        Value = object.Material
                    }

                end


                object.Material =
                    Enum.Material.SmoothPlastic


            elseif object:IsA(
                "ParticleEmitter"
            )
                or object:IsA(
                    "Fire"
                )
                or object:IsA(
                    "Smoke"
                )
            then

                if not fpsBackups[
                    object
                ]
                then

                    fpsBackups[object] = {
                        Type = "Enabled",
                        Value = object.Enabled
                    }

                end


                object.Enabled =
                    false

            end
        end

    end


    local function DisableFPSBoost()

        for object, data
            in pairs(
                fpsBackups
            )
        do

            if object
                and object.Parent
            then

                pcall(function()

                    if data.Type
                        == "Material"
                    then

                        object.Material =
                            data.Value

                    elseif data.Type
                        == "Enabled"
                    then

                        object.Enabled =
                            data.Value

                    end

                end)

            end
        end


        table.clear(
            fpsBackups
        )

    end


    -- ========================================================
    -- PERFORMANCE UI
    -- ========================================================

    local PerformanceSection =
        Window:AddSection(
            ESPTab,
            "Performance Settings"
        )


    PerformanceSection:AddToggle(
        "Disable3D",
        "Disable 3D Rendering",
        false,

        function(state)

            disable3DActive =
                state


            RunService:
            Set3dRenderingEnabled(
                not state
            )

        end
    )


    PerformanceSection:AddToggle(
        "LowGraphic",
        "Low Graphic",
        false,

        function(state)

            lowGraphicActive =
                state


            if state then

                EnableLowGraphic()

            else

                DisableLowGraphic()

            end

        end
    )


    PerformanceSection:AddToggle(
        "FPSBoost",
        "FPS Boost",
        false,

        function(state)

            fpsBoostActive =
                state


            if state then

                EnableFPSBoost()

            else

                DisableFPSBoost()

            end

        end
    )


    -- ========================================================
    -- AUTO FARM
    -- ========================================================

    task.spawn(function()

        while Runtime:IsCurrent() do

            if not autoFarmActive then
                task.wait(0.5)
                continue
            end


            local serverData =
                ReplicatedStorage:
                FindFirstChild(
                    "ServerData"
                )


            local activeEggs =
                serverData
                and serverData:
                    FindFirstChild(
                        "ActiveEggs"
                    )


            local character,
                humanoid,
                root =
                GetCharacterData()


            if not activeEggs
                or not root
            then

                -- Jangan menghitung waktu no-target ketika
                -- data game / character belum siap.
                noTargetSince =
                    nil

                task.wait(0.5)
                continue
            end


            local targetObject =
                nil

            local targetName =
                nil

            local targetPosition =
                nil

            local targetModel =
                nil

            -- Prompt fisik milik egg di RenderedEggs.
            -- Dipakai langsung untuk pickup tanpa scan Workspace.
            local targetPrompt =
                nil

            local bestRarity =
                -1

            local bestDistance =
                math.huge


            for _, configObject
                in ipairs(
                    activeEggs:
                    GetChildren()
                )
            do

                pcall(function()

                    local eggName =
                        configObject:
                        GetAttribute(
                            "Egg"
                        )


                    local position =
                        PositionToVector3(
                            configObject:
                            GetAttribute(
                                "Position"
                            )
                        )


                    if not eggName
                        or not position
                    then
                        return
                    end


                    local renderedModel =
                        nil

                    local renderedPrompt =
                        nil


                    if eggName
                        ~= "Volcanic Egg"
                    then

                        renderedModel,
                            renderedPrompt =
                            FindRenderedEgg(
                                eggName,
                                position,
                                RENDERED_EGG_MAX_DISTANCE
                            )


                        if not renderedModel
                            or not renderedPrompt
                        then
                            return
                        end

                    end


                    local rarity =
                        GetEggRarity(
                            eggName
                        )


                    if not MatchesFilter(
                        eggName,
                        rarity,
                        selectedEggsFarm,
                        selectedRaritiesFarm
                    )
                    then
                        return
                    end


                    local eggWeight =
                        tonumber(
                            configObject:
                            GetAttribute(
                                "Weight"
                            )
                        )
                        or 0


                    if minimumEggWeight
                            > 0
                        and eggWeight
                            < minimumEggWeight
                    then

                        return

                    end


                    local rarityScore =
                        RARITY_PRIORITY[
                            rarity
                        ]
                        or 0


                    local distance =
                        (
                            position
                            - root.Position
                        ).Magnitude


                    if rarityScore
                        > bestRarity

                        or (
                            rarityScore
                                == bestRarity

                            and distance
                                < bestDistance
                        )
                    then

                        bestRarity =
                            rarityScore

                        bestDistance =
                            distance

                        targetObject =
                            configObject

                        targetName =
                            eggName

                        targetPosition =
                            position

                        targetModel =
                            renderedModel

                        targetPrompt =
                            renderedPrompt

                    end

                end)

            end


            if not targetObject
                or not targetPosition
            then

                if autoServerHopActive
                    and autoFarmActive
                then

                    if not noTargetSince then

                        noTargetSince =
                            os.clock()

                    end


                    local elapsed =
                        os.clock()
                        - noTargetSince


                    if elapsed
                        >= serverHopDelay
                    then

                        noTargetSince =
                            nil


                        task.spawn(function()

                            ServerHop(
                                "No matching egg for "
                                .. tostring(
                                    serverHopDelay
                                )
                                .. "s"
                            )

                        end)


                        -- Hindari loop spam sambil teleport diproses.
                        task.wait(1)
                        continue
                    end

                else

                    noTargetSince =
                        nil

                end


                task.wait(0.5)
                continue
            end


            local plotCenter =
                GetPlotCenter()


            -- ================================================
            -- VALIDATE TARGET + VOLCANIC ENTRY
            -- ================================================

            if targetName
                == "Volcanic Egg"
            then

                pcall(function()

                    if not firesignal then
                        return
                    end


                    local reusable =
                        Remotes:
                        FindFirstChild(
                            "Reusable"
                        )


                    local event =
                        reusable
                        and reusable:
                            FindFirstChild(
                                "GameMessage"
                            )


                    if event then

                        firesignal(
                            event.OnClientEvent,
                            "Enter The Lair Through Its Door"
                        )

                    end

                end)


                local entranceCFrame =
                    GetVolcanoEntranceCFrame()


                local validateCFrame =
                    GetLairDoorCFrame()


                local validatePosition =
                    validateCFrame
                    and validateCFrame.Position
                    or nil


                if not entranceCFrame
                    or not validatePosition
                then

                    if autoServerHopActive
                        and not noTargetSince
                    then

                        noTargetSince =
                            os.clock()

                    end


                    task.wait(0.35)
                    continue
                end


                local character =
                    LocalPlayer.Character


                if not character
                    or not root
                    or not root.Parent
                then

                    task.wait(0.2)
                    continue

                end


                -- 1) Teleport dulu ke VolcanoEntrance.
                character:
                PivotTo(
                    entranceCFrame
                )


                task.wait(0.1)


                -- 2) Bergerak HALUS dari VolcanoEntrance, melewati
                -- VolcanoValidate, lalu masuk lebih dalam.
                -- Arah dihitung dari Entrance -> Validate supaya
                -- tidak bergantung pada LookVector part yang bisa terbalik.
                local entrancePosition =
                    entranceCFrame.Position


                local travelVector =
                    validatePosition
                    - entrancePosition


                local travelDirection =
                    travelVector.Magnitude
                        > 0.01
                    and travelVector.Unit
                    or validateCFrame.LookVector


                local deepTargetPosition =
                    validatePosition
                    + travelDirection
                    * 12


                local validateReached =
                    SmoothMoveCharacter(
                        character,
                        root,
                        deepTargetPosition,
                        5
                    )


                if not validateReached then

                    task.wait(0.2)
                    continue

                end


                -- 3) Setelah benar-benar masuk lebih dalam, baru tunggu
                -- Volcanic Egg dirender. Setelah terdeteksi, langsung
                -- teleport ke egg lalu trigger pickup.
                targetModel,
                    targetPrompt =
                    WaitForRenderedEgg(
                        targetName,
                        targetPosition,
                        2,
                        RENDERED_EGG_MAX_DISTANCE
                    )


                if not targetObject.Parent
                    or not targetModel
                    or not targetPrompt
                then

                    if autoServerHopActive
                        and not noTargetSince
                    then

                        noTargetSince =
                            os.clock()

                    end


                    if plotCenter
                        and root.Parent
                    then

                        root.CFrame =
                            CFrame.new(
                                plotCenter.Position
                                + Vector3.new(
                                    0,
                                    5,
                                    0
                                )
                            )

                    end


                    task.wait(0.35)
                    continue
                end

            else

                targetModel,
                    targetPrompt =
                    FindRenderedEgg(
                        targetName,
                        targetPosition,
                        RENDERED_EGG_MAX_DISTANCE
                    )


                if not targetObject.Parent
                    or not targetModel
                    or not targetPrompt
                then

                    if autoServerHopActive
                        and not noTargetSince
                    then

                        noTargetSince =
                            os.clock()

                    end


                    task.wait(0.25)
                    continue
                end

            end


            -- Sampai sini target memang valid secara fisik.
            noTargetSince =
                nil


            -- ================================================
            -- TELEPORT TO EGG
            -- ================================================

            -- Gunakan posisi egg yang benar-benar dirender.
            -- Ini mengikuti EggSpawning.Client terbaru yang membedakan
            -- posisi spawn (ActiveEgg.Position) dan posisi model yang digambar.
            local pickupPosition =
                targetPosition


            if targetPrompt
                and targetPrompt.Parent
                and targetPrompt.Parent:IsA(
                    "BasePart"
                )
            then

                pickupPosition =
                    targetPrompt.Parent.Position

            elseif targetModel
                and targetModel.Parent
            then

                local pivotOk,
                    pivot =
                    pcall(function()

                        return
                            targetModel:
                            GetPivot()

                    end)


                if pivotOk
                    and typeof(pivot)
                        == "CFrame"
                then

                    pickupPosition =
                        pivot.Position

                end

            end


            root.CFrame =
                CFrame.new(
                    pickupPosition
                    + Vector3.new(
                        0,
                        2,
                        0
                    )
                )


            root.AssemblyLinearVelocity =
                Vector3.zero

            root.AssemblyAngularVelocity =
                Vector3.zero


            -- Egg normal menunggu prompt siap sebentar.
            -- Volcanic Egg langsung trigger pickup setelah teleport.
            if targetName
                ~= "Volcanic Egg"
            then

                local promptReadyStarted =
                    os.clock()


                while Runtime:IsCurrent()
                    and autoFarmActive
                    and os.clock()
                        - promptReadyStarted
                        < 0.6
                do

                    if targetPrompt
                        and targetPrompt.Parent
                        and targetPrompt.Enabled
                    then

                        break

                    end


                    task.wait(0.03)

                end

            end


            -- ================================================
            -- PICKUP EGG
            -- ================================================

            local basketSnapshotBefore =
                SnapshotBasketNames()


            local basketCountBefore =
                #Basket:GetChildren()

            local pickedUp =
                false


            local function TriggerPickupPrompt(
                prompt
            )

                if not prompt
                    or not prompt.Parent
                    or not prompt.Enabled
                    or not fireproximityprompt
                then

                    return false

                end


                local ok =
                    pcall(function()

                        local oldHold =
                            prompt.HoldDuration


                        prompt.HoldDuration =
                            0


                        fireproximityprompt(
                            prompt
                        )


                        task.delay(
                            0.05,

                            function()

                                if prompt
                                    and prompt.Parent
                                then

                                    prompt.HoldDuration =
                                        oldHold

                                end

                            end
                        )

                    end)


                return ok
            end


            -- ====================================================
            -- DIRECT EGG PICKUP
            -- Update game terbaru memanggil:
            -- EggPickup:FireServer(<ActiveEgg GUID>)
            --
            -- targetObject adalah child di ServerData.ActiveEggs,
            -- jadi targetObject.Name adalah GUID yang dibutuhkan remote.
            -- Coba maksimal 3x seperti capture Cobalt, tetapi berhenti
            -- segera begitu Basket bertambah.
            -- ====================================================

            if targetObject
                and targetObject.Parent
            then

                for attempt = 1, 3 do

                    local directOk,
                        directErr =
                        pcall(function()

                            EggPickupRemote:
                            FireServer(
                                targetObject.Name
                            )

                        end)


                    if not directOk then

                        warn(
                            "[CHLISE HUB] EggPickup remote failed:",
                            directErr
                        )

                    end


                    local directStarted =
                        os.clock()


                    while Runtime:IsCurrent()
                        and autoFarmActive
                        and os.clock()
                            - directStarted
                            < 0.35
                    do

                        if #Basket:GetChildren()
                            > basketCountBefore
                        then

                            pickedUp =
                                true

                            break

                        end


                        task.wait(0.03)

                    end


                    if pickedUp then
                        break
                    end


                    if not targetObject.Parent then
                        break
                    end

                end

            end


            -- Fallback ke proximity prompt kalau direct remote belum diterima.
            if not pickedUp then

                TriggerPickupPrompt(
                    targetPrompt
                )


                local pickupStarted =
                    os.clock()


                while Runtime:IsCurrent()
                    and autoFarmActive
                    and os.clock()
                        - pickupStarted
                        < 1.0
                do

                    if #Basket:GetChildren()
                        > basketCountBefore
                    then

                        pickedUp =
                            true

                        break

                    end


                    task.wait(0.05)

                end

            end


            -- Retry prompt satu kali kalau direct remote + prompt pertama miss.
            if not pickedUp
                and targetModel
                and targetModel.Parent
            then

                targetPrompt =
                    GetEggPickupPrompt(
                        targetModel
                    )


                if targetPrompt
                    and targetPrompt.Parent
                then

                    TriggerPickupPrompt(
                        targetPrompt
                    )


                    local retryStarted =
                        os.clock()


                    while Runtime:IsCurrent()
                        and autoFarmActive
                        and os.clock()
                            - retryStarted
                            < 1.0
                    do

                        if #Basket:GetChildren()
                            > basketCountBefore
                        then

                            pickedUp =
                                true

                            break

                        end


                        task.wait(0.05)

                    end

                end

            end


            -- Kalau egg benar-benar belum keambil, jangan lanjut Volcano / plot.
            -- Biarkan loop Auto Farm mencoba target lagi.
            if not pickedUp then

                task.wait(0.2)
                continue

            end


            currentPickupBasketIds =
                ResolveNewBasketEggIds(
                    basketSnapshotBefore,
                    2
                )


            -- ====================================================
            -- EGG TIMER PAUSE BYPASS
            --
            -- BreakTimer bawaan game sendiri memakai EggTimerPause
            -- saat camera menjadi Scriptable. Kita manfaatkan remote
            -- yang sama untuk menahan timer selama perjalanan pulang.
            --
            -- Sengaja TIDAK dipakai untuk:
            -- - Go Volcano Dip
            -- - Volcanic Egg
            -- - Gift Egg
            -- supaya flow-flow itu tidak disentuh.
            -- ====================================================

            local timerPauseBypassActive =
                false


            if not goVolcanoDipActive
                and targetName
                    ~= "Volcanic Egg"
                and not giftEggActive
                and #currentPickupBasketIds
                    > 0
            then

                local pauseOk,
                    pauseErr =
                    pcall(function()

                        EggTimerPauseRemote:
                        FireServer(
                            true
                        )

                    end)


                if pauseOk then

                    timerPauseBypassActive =
                        true


                    -- Beri server waktu mengubah state pause basket.
                    task.wait(0.15)

                else

                    warn(
                        "[CHLISE HUB] EggTimerPause(true) failed:",
                        pauseErr
                    )

                end

            end


            if webhookEggPickedUpActive then

                local pickedWeight =
                    tonumber(
                        targetObject:
                        GetAttribute(
                            "Weight"
                        )
                    )
                    or 0


                local pickedRarity =
                    GetEggRarity(
                        targetName
                    )


                task.spawn(function()

                    SendWebhook(
                        "Chlise Hub — Egg Picked Up",
                        {
                            {
                                name =
                                    "Egg",

                                value =
                                    tostring(
                                        targetName
                                    )
                            },

                            {
                                name =
                                    "Rarity",

                                value =
                                    tostring(
                                        pickedRarity
                                        or "Unknown"
                                    )
                            },

                            {
                                name =
                                    "Weight",

                                value =
                                    string.format(
                                        "%.2f",
                                        pickedWeight
                                    )
                            }
                        }
                    )

                end)

            end


            -- ================================================
            -- GO VOLCANO DIP
            -- Setelah pickup sukses, langsung teleport ke Volcano Dip
            -- tanpa delay tambahan.
            -- Urutan:
            -- 1. Teleport ke Volcano Dip
            -- 2. Tunggu tombol / client recognize area
            -- 3. Fire VolcanoDip remote
            -- 4. Stay 10 detik DI VOLCANO
            -- ================================================

            if goVolcanoDipActive
                and targetName
                    ~= "Volcanic Egg"
            then

                -- Delay tambahan sebelum menuju Volcano Dip.
                task.wait(2)


                local currentCharacter,
                    currentHumanoid,
                    currentRoot =
                    GetCharacterData()


                if currentCharacter
                    and currentRoot
                    and currentRoot.Parent
                then

                    -- TELEPORT DULU ke titik Volcano Dip.
                    currentRoot.CFrame =
                        CFrame.new(
                            VOLCANO_DIP_POSITION
                        )


                    task.wait(0.5)


                    -- Kunci lagi posisi setelah teleport supaya karakter
                    -- benar-benar settle di titik Volcano Dip.
                    if currentRoot.Parent then

                        currentRoot.CFrame =
                            CFrame.new(
                                VOLCANO_DIP_POSITION
                            )

                    end


                    local buttonReady =
                        WaitForVolcanoDipButton(
                            3
                        )


                    local dipOk,
                        dipError =
                        pcall(function()

                            VolcanoDipRemote:
                            FireServer()

                        end)


                    if not dipOk then

                        warn(
                            "[CHLISE HUB] VolcanoDip remote failed:",
                            dipError
                        )


                        NotifyWebhookError(
                            "VolcanoDip remote failed: "
                            .. tostring(
                                dipError
                            )
                        )

                    elseif not buttonReady then

                        warn(
                            "[CHLISE HUB] Volcano Dip button not detected; remote was still attempted."
                        )

                    end


                    -- BARU setelah teleport + remote, stay 10 detik di Volcano.
                    local volcanoStayStarted =
                        os.clock()


                    while Runtime:IsCurrent()
                        and autoFarmActive
                        and os.clock()
                            - volcanoStayStarted
                            < 10
                    do

                        if currentRoot.Parent then

                            currentRoot.CFrame =
                                CFrame.new(
                                    VOLCANO_DIP_POSITION
                                )

                        end


                        task.wait(0.1)

                    end


                    if webhookVolcanoDipActive
                        and dipOk
                    then

                        task.spawn(function()

                            SendWebhook(
                                "Chlise Hub — Volcano Dip",
                                {
                                    {
                                        name =
                                            "Egg",

                                        value =
                                            tostring(
                                                targetName
                                            )
                                    },

                                    {
                                        name =
                                            "Status",

                                        value =
                                            "Dip process finished"
                                    }
                                }
                            )

                        end)

                    end

                else

                    warn(
                        "[CHLISE HUB] Volcano Dip skipped: HumanoidRootPart missing."
                    )


                    NotifyWebhookError(
                        "Volcano Dip skipped: HumanoidRootPart missing."
                    )

                end

            end


            -- ================================================
            -- VOLCANIC EGG - EXIT
            -- ================================================

            if targetName
                == "Volcanic Egg"
            then

                local validatePosition =
                    GetLairDoorPosition()


                if validatePosition
                    and root.Parent
                then

                    -- Kembali menyentuh VolcanoValidate untuk keluar.
                    root.CFrame =
                        CFrame.new(
                            validatePosition
                        )


                    task.wait(0.4)
                end

            end


            -- ================================================
            -- GIFT EGG
            -- Jalankan setelah keluar dari volcano.
            -- ================================================

            local giftSucceeded =
                false


            if giftEggActive then

                local giftCallOk,
                    giftResult =
                    pcall(function()

                        return GiftCurrentEgg()

                    end)


                if giftCallOk
                    and giftResult
                then

                    giftSucceeded =
                        true


                    if webhookGiftEggActive then

                        task.spawn(function()

                        SendWebhook(
                            "Chlise Hub — Gift Egg",
                            {
                                {
                                    name =
                                        "Egg",

                                    value =
                                        tostring(
                                            targetName
                                        )
                                },

                                {
                                    name =
                                        "Player",

                                    value =
                                        tostring(
                                            selectedGiftPlayer
                                            or "Unknown"
                                        )
                                }
                            }
                        )

                        end)

                    end

                elseif not giftCallOk then

                    NotifyWebhookError(
                        "Gift Egg failed: "
                        .. tostring(
                            giftResult
                        )
                    )

                end

            end


            if not giftSucceeded
                and root.Parent
            then

                if timerPauseBypassActive then

                    local resumeOk,
                        resumeErr =
                        pcall(function()

                            EggTimerPauseRemote:
                            FireServer(
                                false
                            )

                        end)


                    timerPauseBypassActive =
                        false


                    if not resumeOk then

                        warn(
                            "[CHLISE HUB] EggTimerPause(false) failed:",
                            resumeErr
                        )

                    end


                    -- Pada resume server dapat menyesuaikan BreakAt /
                    -- BreakPausedAt. Tunggu sinkronisasi sebentar sebelum claim.
                    task.wait(0.3)

                end


                ClaimTrackedEggArrival(
                    root,
                    currentPickupBasketIds
                )

            elseif plotCenter
                and root.Parent
            then

                root.CFrame =
                    CFrame.new(
                        plotCenter.Position
                    )

            end


            if timerPauseBypassActive then

                pcall(function()

                    EggTimerPauseRemote:
                    FireServer(
                        false
                    )

                end)


                timerPauseBypassActive =
                    false

            end


            currentPickupBasketIds = {}


            task.wait(0.5)

        end

    end)


    -- ========================================================
    -- AUTO FARM NO COLLISION
    -- ========================================================

    Runtime:TrackConnection(

        RunService.Stepped:
        Connect(function()

            if not autoFarmActive then
                return
            end


            local character =
                LocalPlayer.Character


            if not character then
                return
            end


            for _, part
                in ipairs(
                    character:
                    GetDescendants()
                )
            do

                if part:IsA(
                    "BasePart"
                )
                then

                    part.CanCollide =
                        false

                end
            end

        end)

    )


    -- ========================================================
    -- AUTO HATCH
    -- ========================================================

    task.spawn(function()

        while Runtime:IsCurrent() do

            if not autoHatchActive then
                task.wait(0.5)
                continue
            end


            pcall(function()

                local plot =
                    GetPlot()


                local eggsFolder =
                    plot
                    and plot:
                        FindFirstChild(
                            "Eggs"
                        )


                if not eggsFolder then
                    return
                end


                for _, egg
                    in ipairs(
                        eggsFolder:
                        GetChildren()
                    )
                do

                    if not autoHatchActive then
                        break
                    end


                    local eggData =
                        egg:
                        FindFirstChild(
                            "EggData"
                        )


                    local placeTime =
                        eggData
                        and eggData:
                            FindFirstChild(
                                "PlaceTime"
                            )


                    local eggKey =
                        egg:
                        GetAttribute(
                            "EggKey"
                        )


                    if eggKey
                        and placeTime
                        and placeTime.Value > 0
                    then

                        local eggConfig =
                            EggsData[
                                egg.Name
                            ]


                        if eggConfig then

                            local weightObject =
                                eggData:
                                FindFirstChild(
                                    "Weight"
                                )


                            local weight =
                                weightObject
                                and tonumber(
                                    weightObject.Value
                                )
                                or 1


                            local totalGrowth =
                                GeneralData:
                                GrowthTimeFor(
                                    eggConfig.GrowthTime,
                                    weight
                                )


                            local elapsed


                            if egg:
                                GetAttribute(
                                    "FlatGrow"
                                )
                                == true
                            then

                                elapsed =
                                    workspace:
                                    GetServerTimeNow()
                                    - placeTime.Value

                            else

                                elapsed =
                                    DayNight:
                                    GrowthElapsed(
                                        placeTime.Value
                                    )

                            end


                            if totalGrowth
                                - elapsed
                                <= 0
                            then

                                pcall(function()

                                    if not egg:
                                        HasTag(
                                            "Hatching"
                                        )
                                    then

                                        egg:
                                        AddTag(
                                            "Hatching"
                                        )

                                    end

                                end)


                                HatchRemote:
                                FireServer({
                                    EggKey =
                                        eggKey
                                })


                                task.wait(0.5)
                            end
                        end
                    end
                end

            end)


            task.wait(1)

        end

    end)


    -- ========================================================
    -- PLACE EGG
    -- ========================================================

    task.spawn(function()

        while Runtime:IsCurrent() do

            if not placeEggActive then
                task.wait(0.5)
                continue
            end


            pcall(function()

                local plot =
                    GetPlot()


                if not plot then
                    return
                end


                local eggsFolder =
                    plot:
                    FindFirstChild(
                        "Eggs"
                    )


                if eggsFolder
                    and #eggsFolder:
                        GetChildren()
                        >= 10
                then

                    return
                end


                local character,
                    humanoid,
                    root =
                    GetCharacterData()


                if not character
                    or not humanoid
                    or not root
                then

                    return
                end


                local baseplate =
                    plot:
                    FindFirstChild(
                        "Baseplate"
                    )
                    or plot:
                    FindFirstChild(
                        "Floor"
                    )


                if not baseplate
                    or not baseplate:
                        IsA(
                            "BasePart"
                        )
                then

                    return
                end


                for x = 0, 3 do

                    for z = 0, 3 do

                        if not placeEggActive then
                            return
                        end


                        if eggsFolder
                            and #eggsFolder:
                                GetChildren()
                                >= 10
                        then
                            return
                        end


                        local backpack =
                            LocalPlayer:
                            FindFirstChild(
                                "Backpack"
                            )


                        if not backpack then
                            return
                        end


                        local eggTool =
                            nil


                        for _, tool
                            in ipairs(
                                backpack:
                                GetChildren()
                            )
                        do

                            if tool:IsA(
                                "Tool"
                            )
                            then

                                local rarity =
                                    GetEggRarity(
                                        tool.Name
                                    )


                                if EGG_RARITIES[
                                    tool.Name
                                ]
                                    and MatchesFilter(
                                        tool.Name,
                                        rarity,
                                        selectedEggsPlace,
                                        selectedRaritiesPlace
                                    )
                                then

                                    eggTool =
                                        tool

                                    break
                                end
                            end
                        end


                        if not eggTool then
                            return
                        end


                        humanoid:
                        EquipTool(
                            eggTool
                        )


                        task.wait(0.15)


                        local spawnPosition =
                            baseplate.CFrame
                            * CFrame.new(
                                x * 3.5 - 5.2,
                                4,
                                z * 3.5 - 5.2
                            )


                        root.CFrame =
                            spawnPosition


                        task.wait(0.1)


                        local camera =
                            workspace.CurrentCamera


                        if camera then

                            local screenPosition,
                                onScreen =
                                camera:
                                WorldToScreenPoint(
                                    spawnPosition.Position
                                )


                            if onScreen then

                                VirtualInputManager:
                                SendMouseButtonEvent(
                                    screenPosition.X,
                                    screenPosition.Y,
                                    0,
                                    true,
                                    game,
                                    0
                                )


                                task.wait(0.05)


                                VirtualInputManager:
                                SendMouseButtonEvent(
                                    screenPosition.X,
                                    screenPosition.Y,
                                    0,
                                    false,
                                    game,
                                    0
                                )

                            end
                        end


                        RequestPlotEggs:
                        FireServer({

                            CFrame =
                                spawnPosition,

                            Position =
                                spawnPosition.Position,

                            Hit =
                                spawnPosition,

                            Tool =
                                eggTool,

                            Name =
                                eggTool.Name,

                            Action =
                                "Place"

                        })


                        if eggTool.Parent
                            == character
                        then

                            pcall(function()

                                eggTool:
                                Activate()

                            end)

                        end


                        task.wait(0.4)

                    end
                end

            end)


            task.wait(1)

        end

    end)


    -- ========================================================
    -- AUTO REBIRTH
    --
    -- Tidak spam remote:
    -- - hanya fire saat syarat berubah menjadi terpenuhi
    -- - maksimal 1 kali untuk Rebirths.Value yang sama
    -- - baru bisa fire lagi setelah rebirth level berubah
    --   atau syarat sempat menjadi tidak terpenuhi
    -- ========================================================

    task.spawn(function()

        local wasEligible =
            false

        local lastAttemptRebirthValue =
            nil


        while Runtime:IsCurrent() do

            if not autoRebirthActive then

                wasEligible =
                    false

                lastAttemptRebirthValue =
                    nil

                task.wait(0.5)
                continue

            end


            local eligible,
                reason,
                currentRebirths =
                GetRebirthEligibility()


            if eligible then

                local shouldAttempt =
                    (
                        not wasEligible
                    )
                    or (
                        lastAttemptRebirthValue
                            ~= currentRebirths
                    )


                if shouldAttempt then

                    lastAttemptRebirthValue =
                        currentRebirths


                    local rebirthBefore =
                        currentRebirths


                    local ok,
                        err =
                        pcall(function()

                            RebirthRemote:
                            FireServer()

                        end)


                    if not ok then

                        warn(
                            "[CHLISE HUB] Auto Rebirth failed:",
                            err
                        )


                        NotifyWebhookError(
                            "Auto Rebirth failed: "
                            .. tostring(
                                err
                            )
                        )

                    elseif webhookRebirthActive then

                        task.spawn(function()

                            local started =
                                os.clock()


                            while Runtime:IsCurrent()
                                and os.clock()
                                    - started
                                    < 3
                            do

                                local rebirthAfter =
                                    tonumber(
                                        RebirthsValue.Value
                                    )
                                    or rebirthBefore


                                if rebirthAfter
                                    > rebirthBefore
                                then

                                    SendWebhook(
                                        "Chlise Hub — Rebirth",
                                        {
                                            {
                                                name =
                                                    "Rebirth",

                                                value =
                                                    tostring(
                                                        rebirthBefore
                                                    )
                                                    .. " → "
                                                    .. tostring(
                                                        rebirthAfter
                                                    )
                                            }
                                        }
                                    )

                                    break

                                end


                                task.wait(0.1)

                            end

                        end)

                    end

                end

            else

                -- Bila syarat menjadi false lagi, izinkan satu
                -- percobaan baru saat nanti kembali eligible.
                if wasEligible then

                    lastAttemptRebirthValue =
                        nil

                end

            end


            wasEligible =
                eligible


            task.wait(0.35)

        end

    end)


    -- ========================================================
    -- PET INCOME
    -- ========================================================

    local function GetPetIncomeData(
        pet
    )

        if not pet then
            return nil
        end


        local petName =
            pet:
            GetAttribute(
                "PetName"
            )
            or pet.Name


        local cleanName =
            GetCleanPetName(
                petName
            )


        local petConfig =
            PetData[petName]
            or PetData[cleanName]


        if not petConfig then
            return nil
        end


        local baseIncome =
            tonumber(
                petConfig.Income
            )
            or 0


        if baseIncome <= 0 then
            return nil
        end


        local weight =
            tonumber(
                pet:
                GetAttribute(
                    "Weight"
                )
            )
            or 10


        local mutation =
            pet:
            GetAttribute(
                "Mutation"
            )


        local spawnMutation =
            pet:
            GetAttribute(
                "SpawnMutation"
            )


        local mutationMultiplier =
            tonumber(
                Mutations:
                CombinedFactor(
                    mutation,
                    spawnMutation
                )
            )
            or 1


        local finalIncome =
            baseIncome
            * math.max(
                weight / 10,
                0
            )
            * mutationMultiplier


        return {

            Pet =
                pet,

            Name =
                cleanName,

            FinalIncome =
                finalIncome,

            PetKey =
                pet:
                GetAttribute(
                    "PetKey"
                )
                or pet.Name

        }

    end


    -- ========================================================
    -- AUTO PLACE BEST PET
    -- ========================================================

    task.spawn(function()

        while Runtime:IsCurrent() do

            if not autoPlaceBestPetActive then
                task.wait(1)
                continue
            end


            pcall(function()

                local PlacePet =
                    GameRemotes:
                    FindFirstChild(
                        "PlacePet"
                    )


                if not PlacePet then
                    return
                end


                local plots =
                    workspace:
                    FindFirstChild(
                        "Plots"
                    )


                if not plots then
                    return
                end


                local myPlot =
                    nil


                for _, plot
                    in ipairs(
                        plots:
                        GetChildren()
                    )
                do

                    local data =
                        plot:
                        FindFirstChild(
                            "Data"
                        )


                    local owner =
                        data
                        and data:
                            FindFirstChild(
                                "Owner"
                            )


                    if owner then

                        local value =
                            owner.Value


                        if value == LocalPlayer
                            or value == LocalPlayer.Name
                            or value == LocalPlayer.UserId
                            or tostring(value)
                                == tostring(
                                    LocalPlayer.UserId
                                )
                        then

                            myPlot =
                                plot

                            break
                        end
                    end
                end


                if not myPlot then
                    return
                end


                local maxPetsAllowed =
                    5


                local savedData =
                    LocalPlayer:
                    FindFirstChild(
                        "SavedData"
                    )


                local maxPets =
                    savedData
                    and savedData:
                        FindFirstChild(
                            "MaxPets"
                        )


                if maxPets then

                    maxPetsAllowed =
                        tonumber(
                            maxPets.Value
                        )
                        or maxPetsAllowed

                end


                local placedPets =
                    myPlot:
                    FindFirstChild(
                        "Pets"
                    )


                local currentCount =
                    placedPets
                    and #placedPets:
                        GetChildren()
                    or 0


                if currentCount
                    >= maxPetsAllowed
                then
                    return
                end


                local baseplate =
                    myPlot:
                    FindFirstChild(
                        "Baseplate"
                    )
                    or myPlot:
                    FindFirstChild(
                        "Floor"
                    )


                if not baseplate
                    or not baseplate:
                        IsA(
                            "BasePart"
                        )
                then
                    return
                end


                local playerFolder =
                    LocalPlayer:
                    FindFirstChild(
                        "PlayerFolder"
                    )


                local inventory =
                    playerFolder
                    and playerFolder:
                        FindFirstChild(
                            "Pets"
                        )


                if not inventory then

                    inventory =
                        LocalPlayer:
                        FindFirstChild(
                            "Backpack"
                        )

                end


                if not inventory then
                    return
                end


                local bestPet =
                    nil


                for _, pet
                    in ipairs(
                        inventory:
                        GetDescendants()
                    )
                do

                    local data =
                        GetPetIncomeData(
                            pet
                        )


                    if data
                        and (
                            not bestPet

                            or data.FinalIncome
                                > bestPet.FinalIncome
                        )
                    then

                        bestPet =
                            data

                    end
                end


                if not bestPet then
                    return
                end


                local position =
                    baseplate.CFrame
                    * CFrame.new(
                        math.random(
                            -4,
                            4
                        ),
                        3,
                        math.random(
                            -4,
                            4
                        )
                    )


                local vectorValue


                if vector
                    and vector.create
                then

                    vectorValue =
                        vector.create(
                            position.Position.X,
                            position.Position.Y,
                            position.Position.Z
                        )

                else

                    vectorValue =
                        position.Position

                end


                PlacePet:
                FireServer(
                    bestPet.PetKey,
                    vectorValue
                )

            end)


            task.wait(1.25)

        end

    end)


    -- ========================================================
    -- PET SPEED
    -- ========================================================

    local function GetPetBaseSpeed(
        petConfig
    )

        return
            tonumber(
                petConfig
                and (
                    petConfig.WalkSpeed
                    or petConfig.Speed
                    or petConfig.MovementSpeed
                )
            )
            or 0

    end


    local function GetPetSpeed(
        tool
    )

        if not tool
            or not tool:IsA(
                "Tool"
            )
        then
            return nil
        end


        local cleanName =
            GetCleanPetName(
                tool.Name
            )


        local petConfig =
            PetData[tool.Name]
            or PetData[cleanName]


        if not petConfig then
            return nil
        end


        local baseSpeed =
            GetPetBaseSpeed(
                petConfig
            )


        if baseSpeed <= 0 then
            return nil
        end


        local weight =
            tonumber(
                tool:
                GetAttribute(
                    "Weight"
                )
            )
            or 10


        local mutation =
            tool:
            GetAttribute(
                "Mutation"
            )


        local spawnMutation =
            tool:
            GetAttribute(
                "SpawnMutation"
            )


        local multiplier =
            tonumber(
                Mutations:
                CombinedFactor(
                    mutation,
                    spawnMutation
                )
            )
            or 1


        return {

            Tool =
                tool,

            Name =
                cleanName,

            Weight =
                weight,

            Mutation =
                mutation,

            SpawnMutation =
                spawnMutation,

            MutationMultiplier =
                multiplier,

            DisplaySpeed =
                PetAging:
                DisplaySpeedFor(
                    baseSpeed,
                    weight,
                    multiplier
                ),

            RealSpeed =
                PetAging:
                RealSpeedFor(
                    baseSpeed,
                    weight,
                    multiplier
                )

        }

    end


    -- ========================================================
    -- AUTO RIDE BEST PET
    -- ========================================================

    local mountedPetScore =
        nil


    task.spawn(function()

        while Runtime:IsCurrent() do

            if not autoRideBestPetActive then

                mountedPetScore =
                    nil


                task.wait(1)
                continue
            end


            pcall(function()

                local character =
                    LocalPlayer.Character


                local backpack =
                    LocalPlayer:
                    FindFirstChild(
                        "Backpack"
                    )


                if not character
                    or not backpack
                then
                    return
                end


                local humanoid =
                    character:
                    FindFirstChildOfClass(
                        "Humanoid"
                    )


                if not humanoid then
                    return
                end


                local items =
                    backpack:
                    GetChildren()


                local equipped =
                    character:
                    FindFirstChildOfClass(
                        "Tool"
                    )


                if equipped then

                    table.insert(
                        items,
                        equipped
                    )

                end


                local bestPet =
                    nil


                for _, tool
                    in ipairs(items)
                do

                    local data =
                        GetPetSpeed(
                            tool
                        )


                    if data
                        and (
                            not bestPet

                            or data.DisplaySpeed
                                > bestPet.DisplaySpeed
                        )
                    then

                        bestPet =
                            data

                    end
                end


                if not bestPet then
                    return
                end


                local isRiding =
                    LocalPlayer:
                    GetAttribute(
                        "IsRiding"
                    )
                    == true


                if isRiding
                    and mountedPetScore
                    and bestPet.DisplaySpeed
                        <= mountedPetScore
                            * 1.000000001
                then

                    return
                end


                local Mounting =
                    GameRemotes:
                    FindFirstChild(
                        "Mounting"
                    )


                if not Mounting then
                    return
                end


                if isRiding then

                    Mounting:
                    FireServer()


                    task.wait(0.5)
                end


                if bestPet.Tool.Parent
                    ~= character
                then

                    humanoid:
                    EquipTool(
                        bestPet.Tool
                    )


                    task.wait(0.45)
                end


                if LocalPlayer:
                    GetAttribute(
                        "IsRiding"
                    )
                    ~= true
                then

                    Mounting:
                    FireServer()


                    task.wait(0.6)
                end


                mountedPetScore =
                    bestPet.DisplaySpeed

            end)


            task.wait(5)

        end

    end)


    -- ========================================================
    -- AUTO UPDATE HATCH LUCK
    -- ========================================================

    task.spawn(function()

        while Runtime:IsCurrent() do

            if not autoUpdateHatchLuckActive then
                task.wait(0.5)
                continue
            end


            pcall(function()

                if LocalPlayer:
                    GetAttribute(
                        "Setting_LuckMultiplier"
                    )
                    == false
                then
                    return
                end


                UpgradesRemote:
                FireServer()

            end)


            task.wait(0.35)

        end

    end)


    -- ========================================================
    -- AUTO MAX HATCH LUCK
    -- ========================================================

    task.spawn(function()

        while Runtime:IsCurrent() do

            if not autoMaxHatchLuckActive then
                task.wait(0.5)
                continue
            end


            pcall(function()

                if LocalPlayer:
                    GetAttribute(
                        "Setting_LuckMultiplier"
                    )
                    == false
                then
                    return
                end


                local savedData =
                    LocalPlayer:
                    FindFirstChild(
                        "SavedData"
                    )


                if not savedData then
                    return
                end


                local free =
                    savedData:
                    FindFirstChild(
                        "FreeHatchUpgrades"
                    )


                if free
                    and tonumber(
                        free.Value
                    )
                    and free.Value > 0
                then

                    UpgradesRemote:
                    FireServer(
                        "MaxFree"
                    )

                else

                    UpgradesRemote:
                    FireServer(
                        "Max"
                    )

                end

            end)


            task.wait(0.75)

        end

    end)


    -- ========================================================
    -- PET INFO
    -- ========================================================

    local function GetPetInfo(
        tool
    )

        if not tool
            or not tool:IsA(
                "Tool"
            )
        then
            return nil
        end


        local petName =
            tool:
            GetAttribute(
                "PetName"
            )
            or tool.Name


        local cleanName =
            GetCleanPetName(
                petName
            )


        local config =
            PetData[petName]
            or PetData[cleanName]


        if not config
            or type(
                config.Rarity
            )
                ~= "string"
        then
            return nil
        end


        return {

            Tool =
                tool,

            Name =
                cleanName,

            Rarity =
                config.Rarity,

            PetKey =
                tool:
                GetAttribute(
                    "PetKey"
                ),

            Favorited =
                tool:
                GetAttribute(
                    "Favorited"
                )
                == true

        }

    end


    local function GetAllPetTools()

        local result = {}


        local backpack =
            LocalPlayer:
            FindFirstChild(
                "Backpack"
            )


        local character =
            LocalPlayer.Character


        if backpack then

            for _, tool
                in ipairs(
                    backpack:
                    GetChildren()
                )
            do

                local info =
                    GetPetInfo(
                        tool
                    )


                if info then

                    table.insert(
                        result,
                        info
                    )

                end
            end
        end


        if character then

            for _, tool
                in ipairs(
                    character:
                    GetChildren()
                )
            do

                local info =
                    GetPetInfo(
                        tool
                    )


                if info then

                    table.insert(
                        result,
                        info
                    )

                end
            end
        end


        return result
    end


    -- ========================================================
    -- AUTO SELL
    -- ========================================================

    local Dialogue =
        ReplicatedStorage:
        WaitForChild(
            "Dialogue"
        )


    local DialogueSelect =
        Dialogue:
        WaitForChild(
            "Remotes"
        ):
        WaitForChild(
            "DialogueSelect"
        )


    local stalls =
        workspace:
        WaitForChild(
            "Stalls"
        )


    local Richie =
        stalls:
        WaitForChild(
            "Sell"
        ):
        WaitForChild(
            "Richie"
        )


    local function ShouldSell(
        info
    )

        if not info
            or info.Favorited
        then
            return false
        end


        local rarityMatch =
            autoSellByRarityActive
            and HasSelection(
                selectedSellRarities
            )
            and selectedSellRarities[
                info.Rarity
            ]
                == true


        local nameMatch =
            autoSellByNameActive
            and HasSelection(
                selectedSellPetNames
            )
            and selectedSellPetNames[
                info.Name
            ]
                == true


        return
            rarityMatch
            or nameMatch
    end


    local function FindPetToSell()

        for _, info
            in ipairs(
                GetAllPetTools()
            )
        do

            if ShouldSell(
                info
            )
            then
                return info
            end
        end


        return nil
    end


    local function SellPet(
        tool
    )

        if not tool
            or not tool.Parent
        then
            return false
        end


        local character,
            humanoid,
            root =
            GetCharacterData()


        if not character
            or not humanoid
            or not root
        then
            return false
        end


        humanoid:
        UnequipTools()


        task.wait(0.15)


        humanoid:
        EquipTool(
            tool
        )


        local start =
            os.clock()


        while os.clock()
            - start
            < 1.5
        do

            if tool.Parent
                == character
            then
                break
            end


            task.wait(0.05)
        end


        if tool.Parent
            ~= character
        then
            return false
        end


        local richiePart =
            Richie.PrimaryPart
            or Richie:
                FindFirstChildWhichIsA(
                    "BasePart",
                    true
                )


        if not richiePart then
            return false
        end


        local oldCFrame =
            root.CFrame


        root.CFrame =
            richiePart.CFrame
            * CFrame.new(
                0,
                0,
                5
            )


        task.wait(0.35)


        local prompt =
            Richie:
            FindFirstChildWhichIsA(
                "ProximityPrompt",
                true
            )


        if prompt
            and fireproximityprompt
        then

            pcall(
                fireproximityprompt,
                prompt
            )


            task.wait(0.45)
        end


        if not tool.Parent
            or tool.Parent
                ~= character
        then

            root.CFrame =
                oldCFrame

            return false
        end


        DialogueSelect:
        FireServer(
            Richie,
            "I would like to sell this"
        )


        local sellStart =
            os.clock()


        while os.clock()
            - sellStart
            < 3
        do

            if not tool.Parent then

                if root.Parent then
                    root.CFrame =
                        oldCFrame
                end


                return true
            end


            task.wait(0.08)
        end


        if root.Parent then
            root.CFrame =
                oldCFrame
        end


        return false
    end


    task.spawn(function()

        while Runtime:IsCurrent() do

            if not autoSellByRarityActive
                and not autoSellByNameActive
            then

                task.wait(0.5)
                continue
            end


            pcall(function()

                local info =
                    FindPetToSell()


                if info then

                    SellPet(
                        info.Tool
                    )

                end

            end)


            task.wait(0.6)

        end

    end)


    -- ========================================================
    -- FAVORITE / UNFAVORITE
    --
    -- FavoritePet remote adalah TOGGLE.
    -- ========================================================

    local function ShouldFavorite(
        info
    )

        return
            autoFavoriteByRarityActive
            and info
            and not info.Favorited
            and HasSelection(
                selectedFavoriteRarities
            )
            and selectedFavoriteRarities[
                info.Rarity
            ]
                == true

    end


    local function ShouldUnfavorite(
        info
    )

        return
            autoUnfavoriteByRarityActive
            and info
            and info.Favorited
            and HasSelection(
                selectedFavoriteRarities
            )
            and selectedFavoriteRarities[
                info.Rarity
            ]
                == true

    end


    local function ToggleFavorite(
        info,
        targetState
    )

        if not info
            or not info.Tool
            or not info.Tool.Parent
            or not info.PetKey
        then
            return false
        end


        if (
            info.Tool:
            GetAttribute(
                "Favorited"
            )
            == true
        )
            == targetState
        then
            return true
        end


        FavoritePetRemote:
        FireServer(
            info.PetKey
        )


        local started =
            os.clock()


        while os.clock()
            - started
            < 2
        do

            if not info.Tool.Parent then
                return false
            end


            if (
                info.Tool:
                GetAttribute(
                    "Favorited"
                )
                == true
            )
                == targetState
            then
                return true
            end


            task.wait(0.08)
        end


        return false
    end


    task.spawn(function()

        while Runtime:IsCurrent() do

            if not autoFavoriteByRarityActive then
                task.wait(0.5)
                continue
            end


            -- Jangan jalankan dua mode
            -- secara bersamaan.
            if autoUnfavoriteByRarityActive then
                task.wait(0.5)
                continue
            end


            for _, info
                in ipairs(
                    GetAllPetTools()
                )
            do

                if ShouldFavorite(
                    info
                )
                then

                    ToggleFavorite(
                        info,
                        true
                    )

                    break
                end
            end


            task.wait(0.3)

        end

    end)


    task.spawn(function()

        while Runtime:IsCurrent() do

            if not autoUnfavoriteByRarityActive then
                task.wait(0.5)
                continue
            end


            if autoFavoriteByRarityActive then
                task.wait(0.5)
                continue
            end


            for _, info
                in ipairs(
                    GetAllPetTools()
                )
            do

                if ShouldUnfavorite(
                    info
                )
                then

                    ToggleFavorite(
                        info,
                        false
                    )

                    break
                end
            end


            task.wait(0.3)

        end

    end)


    -- ========================================================
    -- ESP WORLD EGGS
    -- ========================================================

    local espFolder =
        workspace:
        FindFirstChild(
            "ChliseESPFolder"
        )


    if not espFolder then

        espFolder =
            Instance.new(
                "Folder"
            )


        espFolder.Name =
            "ChliseESPFolder"


        espFolder.Parent =
            workspace

    end


    task.spawn(function()

        while Runtime:IsCurrent() do

            task.wait(0.5)


            if not espEggsEnabled then

                espFolder:
                ClearAllChildren()

                continue
            end


            local serverData =
                ReplicatedStorage:
                FindFirstChild(
                    "ServerData"
                )


            local activeEggs =
                serverData
                and serverData:
                    FindFirstChild(
                        "ActiveEggs"
                    )


            if not activeEggs then
                continue
            end


            local valid = {}


            for _, configObject
                in ipairs(
                    activeEggs:
                    GetChildren()
                )
            do

                pcall(function()

                    local eggName =
                        configObject:
                        GetAttribute(
                            "Egg"
                        )


                    local position =
                        PositionToVector3(
                            configObject:
                            GetAttribute(
                                "Position"
                            )
                        )


                    if not eggName
                        or not position
                    then
                        return
                    end


                    local key =
                        tostring(
                            configObject.Name
                        )


                    valid[key] =
                        true


                    local part =
                        espFolder:
                        FindFirstChild(
                            "ESP_"
                            .. key
                        )


                    if not part then

                        part =
                            Instance.new(
                                "Part"
                            )


                        part.Name =
                            "ESP_"
                            .. key


                        part.Size =
                            Vector3.new(
                                1,
                                1,
                                1
                            )


                        part.Transparency =
                            1


                        part.Anchored =
                            true


                        part.CanCollide =
                            false


                        part.Parent =
                            espFolder


                        local billboard =
                            Instance.new(
                                "BillboardGui"
                            )


                        billboard.Size =
                            UDim2.new(
                                0,
                                160,
                                0,
                                75
                            )


                        billboard.AlwaysOnTop =
                            true


                        billboard.StudsOffset =
                            Vector3.new(
                                0,
                                3,
                                0
                            )


                        billboard.Parent =
                            part


                        local label =
                            Instance.new(
                                "TextLabel"
                            )


                        label.Name =
                            "Label"


                        label.Size =
                            UDim2.fromScale(
                                1,
                                1
                            )


                        label.BackgroundTransparency =
                            1


                        label.TextSize =
                            12


                        label.Font =
                            Enum.Font.GothamBold


                        label.TextStrokeTransparency =
                            0


                        label.Parent =
                            billboard

                    end


                    part.Position =
                        position


                    local label =
                        part:
                        FindFirstChild(
                            "BillboardGui"
                        )
                        and part.BillboardGui:
                            FindFirstChild(
                                "Label"
                            )


                    if label then

                        local rarity =
                            GetEggRarity(
                                eggName
                            )


                        label.TextColor3 =
                            GetRarityColor(
                                rarity
                            )


                        label.Text =
                            eggName
                            .. "\nRarity: "
                            .. rarity

                    end

                end)

            end


            for _, object
                in ipairs(
                    espFolder:
                    GetChildren()
                )
            do

                local key =
                    object.Name:
                    gsub(
                        "^ESP_",
                        ""
                    )


                if not valid[key] then

                    object:
                    Destroy()

                end
            end

        end

    end)


    -- ========================================================
    -- ESP INVENTORY
    -- ========================================================

    local function ClearInventoryESP()

        local playerGui =
            LocalPlayer:
            FindFirstChild(
                "PlayerGui"
            )


        if not playerGui then
            return
        end


        for _, object
            in ipairs(
                playerGui:
                GetDescendants()
            )
        do

            if object.Name
                == "PetESPText"
            then

                object:
                Destroy()

            end
        end

    end


    task.spawn(function()

        while Runtime:IsCurrent() do

            task.wait(1.5)


            if not espInventoryEnabled then

                ClearInventoryESP()

                continue
            end


            local playerGui =
                LocalPlayer:
                FindFirstChild(
                    "PlayerGui"
                )


            local main =
                playerGui
                and playerGui:
                    FindFirstChild(
                        "MainUI"
                    )


            local inventory =
                main
                and main:
                    FindFirstChild(
                        "Inventory"
                    )


            if not inventory then
                continue
            end


            for _, slot
                in ipairs(
                    inventory:
                    GetDescendants()
                )
            do

                if slot:IsA(
                    "GuiObject"
                )
                    and slot.Name:
                        find(
                            "PetSlot"
                        )
                    and not slot:
                        FindFirstChild(
                            "PetESPText"
                        )
                then

                    local label =
                        Instance.new(
                            "TextLabel"
                        )


                    label.Name =
                        "PetESPText"


                    label.Size =
                        UDim2.fromScale(
                            1,
                            1
                        )


                    label.BackgroundTransparency =
                        0.4


                    label.BackgroundColor3 =
                        Color3.fromRGB(
                            0,
                            0,
                            0
                        )


                    label.TextColor3 =
                        Color3.fromRGB(
                            255,
                            255,
                            255
                        )


                    label.TextSize =
                        10


                    label.Font =
                        Enum.Font.GothamBold


                    label.TextWrapped =
                        true


                    local petName =
                        slot:
                        GetAttribute(
                            "PetName"
                        )
                        or "Pet"


                    local price =
                        slot:
                        GetAttribute(
                            "Price"
                        )
                        or "0"


                    local mutation =
                        slot:
                        GetAttribute(
                            "Mutation"
                        )
                        or "Normal"


                    label.Text =
                        tostring(
                            petName
                        )
                        .. "\nHarga: "
                        .. tostring(
                            price
                        )
                        .. "\nMutasi: "
                        .. tostring(
                            mutation
                        )


                    label.Parent =
                        slot

                end
            end

        end

    end)


    -- ========================================================
    -- CLEANUP WHEN SCRIPT GENERATION CHANGES
    -- ========================================================

    task.spawn(function()

        while Runtime:IsCurrent() do
            task.wait(1)
        end


        pcall(function()

            RunService:
            Set3dRenderingEnabled(
                true
            )

        end)


        pcall(
            DisableLowGraphic
        )


        pcall(
            DisableFPSBoost
        )


        pcall(
            ClearInventoryESP
        )

    end)


    print(
        "[CHLISE HUB] Ride A Pet loaded."
    )

end