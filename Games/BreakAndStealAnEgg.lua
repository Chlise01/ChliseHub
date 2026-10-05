-- ============================================================
-- CHLISE HUB
-- Games/BreakAndStealAnEgg.lua
--
-- GameId  : 10765288803
-- PlaceId : 114326934417838
-- ============================================================

return function(Context)

    -- ========================================================
    -- CORE
    -- ========================================================

    local Window =
        Context.Window

    local Runtime =
        Context.Runtime

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

    local Workspace =
        game:GetService("Workspace")

    local ProximityPromptService =
        game:GetService("ProximityPromptService")


    local LocalPlayer =
        Players.LocalPlayer


    -- ========================================================
    -- GAME OBJECTS
    -- ========================================================

    local EggHitRequest =
        ReplicatedStorage:
        WaitForChild("EggHitRequest")


    local AnimalBankedRemote =
        ReplicatedStorage:
        WaitForChild("AnimalBankedRemote")


    local Build =
        Workspace:
        WaitForChild("Build")


    local ZoneBuilds =
        Build:
        WaitForChild("ZoneBuilds")


    local Pickups =
        Workspace:
        WaitForChild("AnimalPickups")


    local CarriedAnimals =
        Workspace:
        WaitForChild("CarriedAnimals")


    local PromptAnchor =
        Workspace:
        WaitForChild("PromptAnchor")


    local GlobalPrompt =
        PromptAnchor:
        WaitForChild("StealPrompt")


    -- ========================================================
    -- SETTINGS
    -- ========================================================

    local HIT_DISTANCE =
        7

    local EGG_TP_DISTANCE =
        4

    local HIT_DELAY =
        0.52


    local PICKUP_SPAWN_TIMEOUT =
        8

    local MAX_PICKUP_SPAWN_DISTANCE =
        15


    local PICKUP_TP_DISTANCE =
        3

    local PROMPT_TIMEOUT =
        7


    local CARRY_TIMEOUT =
        2.5

    local BANK_TIMEOUT =
        5


    -- ========================================================
    -- STATE
    -- ========================================================

    local autoFarmActive =
        false

    local farmLoopRunning =
        false

    local debugEnabled =
        false


    local selectedZones =
        {}

    local selectedEggs =
        {}

    local minimumPetWeight =
        0


    -- ========================================================
    -- RUNTIME STATE
    -- ========================================================

    local RuntimeState =
        Runtime
        and Runtime:GetState()
        or {}


    RuntimeState.BreakAndSteal =
        type(
            RuntimeState.BreakAndSteal
        ) == "table"
        and RuntimeState.BreakAndSteal
        or {}


    local FarmState =
        RuntimeState.BreakAndSteal


    -- Fallback yang sebelumnya sudah terbukti work.
    -- Bisa diganti via tombol "Set Home Position".
    local homeCFrame =
        FarmState.HomeCFrame
        or CFrame.new(
            -74.349571,
            3.498024,
            -3.833112
        )


    -- ========================================================
    -- LOG
    -- ========================================================

    local function Log(...)

        if debugEnabled then

            print(
                "[CHLISE HUB][BREAK & STEAL]",
                ...
            )

        end

    end


    -- ========================================================
    -- CHARACTER
    -- ========================================================

    local function GetCharacter()

        local character =
            LocalPlayer.Character
            or LocalPlayer.CharacterAdded:Wait()


        local hrp =
            character:
            WaitForChild(
                "HumanoidRootPart"
            )


        return
            character,
            hrp

    end


    -- ========================================================
    -- SELECTION HELPERS
    -- ========================================================

    local function SelectionEmpty(
        selection
    )

        if type(selection)
            ~= "table"
        then
            return true
        end


        for key,
            value
            in pairs(selection)
        do

            if value == true then
                return false
            end


            if type(key)
                    == "number"
                and type(value)
                    == "string"
            then

                return false

            end

        end


        return true

    end


    local function IsSelected(
        selection,
        wanted
    )

        if SelectionEmpty(
            selection
        ) then
            return true
        end


        if selection[wanted]
            == true
        then
            return true
        end


        for key,
            value
            in pairs(selection)
        do

            if value == wanted then
                return true
            end


            if key == wanted
                and value == true
            then
                return true
            end

        end


        return false

    end


    -- ========================================================
    -- ZONE
    -- ========================================================

    local function NormalizeZone(
        value
    )

        if typeof(value)
            == "number"
        then

            return
                "Zone"
                .. tostring(value)

        end


        if typeof(value)
            == "string"
        then

            local number =
                value:
                match("%d+")


            if number then

                return
                    "Zone"
                    .. number

            end

        end


        return nil

    end


    local MASTER_ZONES = {
        "Zone1",
        "Zone2",
        "Zone3",
        "Zone4",
        "Zone5",
        "Zone6",
        "Zone7",
        "Zone8",
        "Zone9"
    }


    -- ========================================================
    -- EGG HELPERS
    -- ========================================================

    local function ResolveEgg(
        container
    )

        if container:IsA(
                "BasePart"
            )
            and typeof(
                container:
                GetAttribute(
                    "Health"
                )
            ) == "number"
        then

            return container

        end


        local direct =
            container:
            FindFirstChild(
                "Egg"
            )


        if direct
            and direct:IsA(
                "BasePart"
            )
            and typeof(
                direct:
                GetAttribute(
                    "Health"
                )
            ) == "number"
        then

            return direct

        end


        for _,
            object
            in ipairs(
                container:
                GetDescendants()
            )
        do

            if object:IsA(
                    "BasePart"
                )
                and object.Name
                    == "Egg"
                and typeof(
                    object:
                    GetAttribute(
                        "Health"
                    )
                ) == "number"
            then

                return object

            end

        end


        return nil

    end


    local function GetEggName(
        egg
    )

        local eggType =
            egg:
            GetAttribute(
                "EggType"
            )


        if typeof(eggType)
                == "string"
            and eggType
                ~= ""
        then

            return eggType

        end


        local parent =
            egg.Parent


        if parent then

            return parent.Name:
                gsub(
                    "^%d+:%s*",
                    ""
                )

        end


        return egg.Name

    end


    local function ValidEgg(
        egg
    )

        if not egg
            or not egg.Parent
        then
            return false
        end


        local health =
            egg:
            GetAttribute(
                "Health"
            )


        return
            typeof(health)
                == "number"
            and health > 0
            and egg:
                GetAttribute(
                    "Hatching"
                ) ~= true
            and egg:
                GetAttribute(
                    "Broken"
                ) ~= true

    end


    -- ========================================================
    -- MASTER EGG LIST
    -- ========================================================

    local function BuildEggList()

        local found = {}
        local result = {}


        for _,
            zoneName
            in ipairs(
                MASTER_ZONES
            )
        do

            local zone =
                ZoneBuilds:
                FindFirstChild(
                    zoneName
                )


            local eggs =
                zone
                and zone:
                    FindFirstChild(
                        "Eggs"
                    )


            if eggs then

                for _,
                    container
                    in ipairs(
                        eggs:
                        GetChildren()
                    )
                do

                    local egg =
                        ResolveEgg(
                            container
                        )


                    if egg then

                        local name =
                            GetEggName(
                                egg
                            )


                        if not found[name] then

                            found[name] =
                                true


                            table.insert(
                                result,
                                name
                            )

                        end

                    end

                end

            end

        end


        table.sort(
            result
        )


        return result

    end


    local MASTER_EGGS =
        BuildEggList()


    -- ========================================================
    -- TELEPORT
    -- ========================================================

    local function TeleportNear(
        position,
        distance
    )

        local _,
            hrp =
            GetCharacter()


        local direction =
            hrp.Position
            - position


        direction =
            Vector3.new(
                direction.X,
                0,
                direction.Z
            )


        if direction.Magnitude
            < 0.1
        then

            direction =
                Vector3.new(
                    0,
                    0,
                    1
                )

        else

            direction =
                direction.Unit

        end


        local targetPosition =
            position
            + direction
                * distance
            + Vector3.new(
                0,
                2,
                0
            )


        hrp.AssemblyLinearVelocity =
            Vector3.zero


        hrp.AssemblyAngularVelocity =
            Vector3.zero


        hrp.CFrame =
            CFrame.lookAt(
                targetPosition,

                Vector3.new(
                    position.X,
                    targetPosition.Y,
                    position.Z
                )
            )


        return hrp

    end


    local function TeleportHome()

        local _,
            hrp =
            GetCharacter()


        hrp.AssemblyLinearVelocity =
            Vector3.zero


        hrp.AssemblyAngularVelocity =
            Vector3.zero


        hrp.CFrame =
            homeCFrame

    end


    -- ========================================================
    -- PICKAXE
    -- ========================================================

    local function EnsurePickaxe()

        local character =
            LocalPlayer.Character
            or LocalPlayer.CharacterAdded:Wait()


        local humanoid =
            character:
            FindFirstChildOfClass(
                "Humanoid"
            )


        if not humanoid then
            return nil
        end


        local equipped =
            character:
            FindFirstChild(
                "Pickaxe"
            )


        if equipped
            and equipped:IsA(
                "Tool"
            )
        then

            return equipped

        end


        local backpack =
            LocalPlayer:
            WaitForChild(
                "Backpack"
            )


        local pickaxe =
            backpack:
            FindFirstChild(
                "Pickaxe"
            )


        if not pickaxe
            or not pickaxe:IsA(
                "Tool"
            )
        then

            warn(
                "[CHLISE HUB] Pickaxe not found."
            )

            return nil

        end


        humanoid:
        EquipTool(
            pickaxe
        )


        local deadline =
            os.clock()
            + 2


        while autoFarmActive
            and os.clock()
                < deadline
        do

            if pickaxe.Parent
                == character
            then

                Log(
                    "Pickaxe equipped",
                    "| Tier:",
                    LocalPlayer:
                    GetAttribute(
                        "PickaxeTier"
                    )
                    or 1
                )


                return pickaxe

            end


            task.wait(
                0.02
            )

        end


        return nil

    end


    local function UsePickaxe()

        local pickaxe =
            EnsurePickaxe()


        if not pickaxe then
            return false
        end


        pcall(function()

            pickaxe:
            Activate()

        end)


        task.wait(
            0.08
        )


        return true

    end


    -- ========================================================
    -- FIND EGG
    -- ========================================================

    local function FindBestEgg()

        local _,
            hrp =
            GetCharacter()


        local bestEgg =
            nil

        local bestZone =
            nil

        local bestDistance =
            math.huge


        for _,
            zoneName
            in ipairs(
                MASTER_ZONES
            )
        do

            if IsSelected(
                selectedZones,
                zoneName
            )
            then

                local zone =
                    ZoneBuilds:
                    FindFirstChild(
                        zoneName
                    )


                local eggs =
                    zone
                    and zone:
                        FindFirstChild(
                            "Eggs"
                        )


                if eggs then

                    for _,
                        container
                        in ipairs(
                            eggs:
                            GetChildren()
                        )
                    do

                        local egg =
                            ResolveEgg(
                                container
                            )


                        if ValidEgg(
                            egg
                        )
                        then

                            local eggName =
                                GetEggName(
                                    egg
                                )


                            if IsSelected(
                                selectedEggs,
                                eggName
                            )
                            then

                                local distance =
                                    (
                                        hrp.Position
                                        - egg.Position
                                    ).Magnitude


                                if distance
                                    < bestDistance
                                then

                                    bestEgg =
                                        egg

                                    bestZone =
                                        zoneName

                                    bestDistance =
                                        distance

                                end

                            end

                        end

                    end

                end

            end

        end


        return
            bestEgg,
            bestZone,
            bestDistance

    end


    -- ========================================================
    -- PICKUP SNAPSHOT
    -- ========================================================

    local function SnapshotPickups()

        local snapshot = {}


        for _,
            animal
            in ipairs(
                Pickups:
                GetChildren()
            )
        do

            snapshot[animal] =
                true

        end


        return snapshot

    end


    -- ========================================================
    -- WAIT RESULT PET
    -- ========================================================

    local function WaitResultPet(
        before,
        zoneName,
        eggPosition
    )

        local deadline =
            os.clock()
            + PICKUP_SPAWN_TIMEOUT


        while autoFarmActive
            and os.clock()
                < deadline
        do

            local best =
                nil

            local bestDistance =
                math.huge


            for _,
                animal
                in ipairs(
                    Pickups:
                    GetChildren()
                )
            do

                if not before[animal]
                    and animal:IsA(
                        "Model"
                    )
                then

                    local hatched =
                        animal:
                        GetAttribute(
                            "Hatched"
                        )


                    local animalZone =
                        NormalizeZone(
                            animal:
                            GetAttribute(
                                "ZoneId"
                            )
                        )


                    if hatched == true
                        and (
                            not animalZone
                            or animalZone
                                == zoneName
                        )
                    then

                        local position =
                            animal:
                            GetPivot().
                            Position


                        local distance =
                            (
                                position
                                - eggPosition
                            ).Magnitude


                        if distance
                                <= MAX_PICKUP_SPAWN_DISTANCE
                            and distance
                                < bestDistance
                        then

                            best =
                                animal

                            bestDistance =
                                distance

                        end

                    end

                end

            end


            if best then

                Log(
                    "Result pet:",
                    best:
                    GetAttribute(
                        "AnimalName"
                    )
                    or best.Name,

                    "| Distance:",
                    string.format(
                        "%.2f",
                        bestDistance
                    )
                )


                task.wait(
                    0.15
                )


                return best

            end


            task.wait(
                0.04
            )

        end


        return nil

    end


    -- ========================================================
    -- BREAK EGG
    -- ========================================================

    local function BreakEgg(
        egg,
        zoneName
    )

        if not ValidEgg(
            egg
        )
        then
            return nil
        end


        if not EnsurePickaxe() then
            return nil
        end


        local before =
            SnapshotPickups()


        local eggPosition =
            egg.Position


        local _,
            hrp =
            GetCharacter()


        local distance =
            (
                hrp.Position
                - eggPosition
            ).Magnitude


        Log(
            "Target:",
            GetEggName(egg),

            "| HP:",
            egg:
            GetAttribute(
                "Health"
            ),

            "| Zone:",
            zoneName,

            "| Distance:",
            string.format(
                "%.2f",
                distance
            )
        )


        if distance
            > HIT_DISTANCE
        then

            TeleportNear(
                eggPosition,
                EGG_TP_DISTANCE
            )


            task.wait(
                0.08
            )

        end


        if not UsePickaxe() then
            return nil
        end


        while autoFarmActive
            and ValidEgg(
                egg
            )
        do

            if not EnsurePickaxe() then
                return nil
            end


            local _,
                currentHRP =
                GetCharacter()


            local currentDistance =
                (
                    currentHRP.Position
                    - egg.Position
                ).Magnitude


            if currentDistance
                > HIT_DISTANCE
            then

                TeleportNear(
                    egg.Position,
                    EGG_TP_DISTANCE
                )


                task.wait(
                    0.05
                )

            end


            local tier =
                LocalPlayer:
                GetAttribute(
                    "PickaxeTier"
                )
                or 1


            EggHitRequest:
            FireServer(
                egg,
                tier
            )


            Log(
                "Hit",
                "| Tier:",
                tier,

                "| HP:",
                egg:
                GetAttribute(
                    "Health"
                )
            )


            task.wait(
                HIT_DELAY
            )

        end


        if not autoFarmActive then
            return nil
        end


        Log(
            "Egg done:",
            GetEggName(
                egg
            )
        )


        return
            WaitResultPet(
                before,
                zoneName,
                eggPosition
            )

    end


    -- ========================================================
    -- PROMPT POSITION
    -- ========================================================

    local function GetPromptPosition(
        prompt
    )

        if not prompt
            or not prompt.Parent
        then
            return nil
        end


        local parent =
            prompt.Parent


        if parent:IsA(
            "Attachment"
        )
        then

            return parent.WorldPosition

        end


        if parent:IsA(
            "BasePart"
        )
        then

            return parent.Position

        end


        local part =
            prompt:
            FindFirstAncestorWhichIsA(
                "BasePart"
            )


        return
            part
            and part.Position
            or nil

    end


    -- ========================================================
    -- MODEL DISTANCE
    -- ========================================================

    local function ModelDistanceToPoint(
        model,
        point
    )

        local ok,
            cf,
            size =
            pcall(function()

                return
                    model:
                    GetBoundingBox()

            end)


        if not ok then
            return math.huge
        end


        local localPoint =
            cf:
            PointToObjectSpace(
                point
            )


        local half =
            size
            * 0.5


        local dx =
            math.max(
                math.abs(
                    localPoint.X
                ) - half.X,
                0
            )


        local dy =
            math.max(
                math.abs(
                    localPoint.Y
                ) - half.Y,
                0
            )


        local dz =
            math.max(
                math.abs(
                    localPoint.Z
                ) - half.Z,
                0
            )


        return
            Vector3.new(
                dx,
                dy,
                dz
            ).Magnitude

    end


    -- ========================================================
    -- PROMPT TEXT
    -- ========================================================

    local function NormalizeText(
        text
    )

        return tostring(
            text
            or ""
        ):
        gsub(
            "<.->",
            ""
        ):
        lower():
        gsub(
            "[^%w]",
            ""
        )

    end


    local function PromptKg(
        prompt
    )

        local text =
            tostring(
                prompt.ObjectText
                or ""
            ):
            gsub(
                "<.->",
                ""
            )


        return tonumber(
            text:
            match(
                "%[([%d%.]+)%s*[Kk][Gg]%]"
            )
        )

    end


    -- ========================================================
    -- PROMPT MATCHING
    -- ========================================================

    local function PromptMatchesAnimal(
        prompt,
        animal
    )

        if not prompt
            or not prompt.Parent
            or not animal
            or not animal.Parent
        then

            return false

        end


        if prompt.Name
                ~= "StealPrompt"
            and prompt.ActionText
                ~= "Steal"
        then

            return false

        end


        if prompt:
            IsDescendantOf(
                animal
            )
        then

            return true

        end


        local position =
            GetPromptPosition(
                prompt
            )


        if not position then
            return false
        end


        local distance =
            ModelDistanceToPoint(
                animal,
                position
            )


        if distance <= 1.5 then
            return true
        end


        if distance <= 6 then

            local weight =
                animal:
                GetAttribute(
                    "WeightKg"
                )


            local promptWeight =
                PromptKg(
                    prompt
                )


            if typeof(weight)
                    == "number"
                and typeof(promptWeight)
                    == "number"
                and math.abs(
                    weight
                    - promptWeight
                ) <= 1.1
            then

                return true

            end


            local animalName =
                animal:
                GetAttribute(
                    "AnimalName"
                )
                or animal.Name


            local objectText =
                NormalizeText(
                    prompt.ObjectText
                )


            local targetText =
                NormalizeText(
                    animalName
                )


            if targetText ~= ""
                and objectText:
                    find(
                        targetText,
                        1,
                        true
                    )
            then

                return true

            end

        end


        return false

    end


    -- ========================================================
    -- FIND PROMPT
    -- ========================================================

    local function FindCurrentPrompt(
        animal
    )

        for _,
            object
            in ipairs(
                animal:
                GetDescendants()
            )
        do

            if object:IsA(
                    "ProximityPrompt"
                )
                and object.Enabled
                and PromptMatchesAnimal(
                    object,
                    animal
                )
            then

                return object

            end

        end


        if GlobalPrompt.Enabled
            and PromptMatchesAnimal(
                GlobalPrompt,
                animal
            )
        then

            return GlobalPrompt

        end


        return nil

    end


    -- ========================================================
    -- WAIT STEAL PROMPT
    -- ========================================================

    local function WaitStealPrompt(
        animal
    )

        local foundPrompt =
            nil


        local shownConnection =
            ProximityPromptService.
            PromptShown:
            Connect(function(
                prompt
            )

                if not foundPrompt
                    and PromptMatchesAnimal(
                        prompt,
                        animal
                    )
                then

                    foundPrompt =
                        prompt


                    Log(
                        "Prompt shown:",
                        prompt:
                        GetFullName()
                    )

                end

            end)


        local deadline =
            os.clock()
            + PROMPT_TIMEOUT


        local _,
            hrp =
            GetCharacter()


        local basePosition =
            hrp.Position


        local toggle =
            false


        while autoFarmActive
            and animal.Parent
            and os.clock()
                < deadline
            and not foundPrompt
        do

            foundPrompt =
                FindCurrentPrompt(
                    animal
                )


            if foundPrompt then
                break
            end


            local animalPosition =
                animal:
                GetPivot().
                Position


            local _,
                currentHRP =
                GetCharacter()


            toggle =
                not toggle


            local side =
                toggle
                and 0.15
                or -0.15


            local refreshPosition =
                basePosition
                + currentHRP.CFrame.
                    RightVector
                    * side


            currentHRP.CFrame =
                CFrame.lookAt(
                    refreshPosition,

                    Vector3.new(
                        animalPosition.X,
                        refreshPosition.Y,
                        animalPosition.Z
                    )
                )


            currentHRP.AssemblyLinearVelocity =
                Vector3.zero


            task.wait(
                0.08
            )

        end


        shownConnection:
        Disconnect()


        return foundPrompt

    end


    -- ========================================================
    -- CARRY SNAPSHOT
    -- ========================================================

    local function SnapshotCarry()

        local result = {}


        for _,
            carried
            in ipairs(
                CarriedAnimals:
                GetChildren()
            )
        do

            result[carried] =
                true

        end


        return result

    end


    -- ========================================================
    -- WAIT OWN CARRY
    -- ========================================================

    local function WaitOwnCarry(
        before,
        animalName
    )

        local found =
            nil


        local function Check(
            model
        )

            if found
                or not model
                or not model.Parent
                or not model:IsA(
                    "Model"
                )
                or before[model]
            then

                return

            end


            local name =
                model:
                GetAttribute(
                    "AnimalName"
                )


            if name
                ~= animalName
            then
                return
            end


            local _,
                hrp =
                GetCharacter()


            local distance =
                (
                    model:
                    GetPivot().
                    Position
                    - hrp.Position
                ).Magnitude


            if distance <= 20 then

                found =
                    model

            end

        end


        local connection =
            CarriedAnimals.
            ChildAdded:
            Connect(function(
                model
            )

                task.defer(
                    Check,
                    model
                )

            end)


        local deadline =
            os.clock()
            + CARRY_TIMEOUT


        while autoFarmActive
            and not found
            and os.clock()
                < deadline
        do

            for _,
                model
                in ipairs(
                    CarriedAnimals:
                    GetChildren()
                )
            do

                Check(
                    model
                )


                if found then
                    break
                end

            end


            task.wait(
                0.01
            )

        end


        connection:
        Disconnect()


        return found

    end


    -- ========================================================
    -- STEAL + BANK
    -- ========================================================

    local function StealAndBank(
        animal
    )

        if not animal
            or not animal.Parent
        then

            return false

        end


        local animalName =
            animal:
            GetAttribute(
                "AnimalName"
            )
            or animal.Name


        local weight =
            tonumber(
                animal:
                GetAttribute(
                    "WeightKg"
                )
            )
            or 0


        if minimumPetWeight > 0
            and weight
                < minimumPetWeight
        then

            Log(
                "Skip pet:",
                animalName,

                "| Weight:",
                weight,

                "| Minimum:",
                minimumPetWeight
            )


            return false

        end


        Log(
            "Pet target:",
            animalName,

            "| Weight:",
            weight
        )


        TeleportNear(
            animal:
            GetPivot().
            Position,

            PICKUP_TP_DISTANCE
        )


        task.wait(
            0.12
        )


        local _,
            hrp =
            GetCharacter()


        local animalPosition =
            animal:
            GetPivot().
            Position


        hrp.CFrame =
            CFrame.lookAt(
                hrp.Position,

                Vector3.new(
                    animalPosition.X,
                    hrp.Position.Y,
                    animalPosition.Z
                )
            )


        local prompt =
            WaitStealPrompt(
                animal
            )


        if not prompt then

            warn(
                "[CHLISE HUB] StealPrompt not found:",
                animalName
            )


            return false

        end


        Log(
            "Prompt ready:",
            prompt:
            GetFullName(),

            "|",
            prompt.ObjectText
        )


        local promptPosition =
            GetPromptPosition(
                prompt
            )


        if promptPosition then

            local _,
                currentHRP =
                GetCharacter()


            local distance =
                (
                    currentHRP.Position
                    - promptPosition
                ).Magnitude


            if distance > 7 then

                TeleportNear(
                    promptPosition,
                    2.5
                )


                task.wait(
                    0.05
                )

            end

        end


        local carryBefore =
            SnapshotCarry()


        Log(
            "Fire steal:",
            animalName
        )


        fireproximityprompt(
            prompt
        )


        local carried =
            WaitOwnCarry(
                carryBefore,
                animalName
            )


        if not carried then

            warn(
                "[CHLISE HUB] Carry not detected:",
                animalName
            )


            return false

        end


        Log(
            "Own carry:",
            animalName
        )


        -- ====================================================
        -- BANK LISTENER BEFORE TELEPORT
        -- ====================================================

        local banked =
            false


        local bankConnection =
            AnimalBankedRemote.
            OnClientEvent:
            Connect(function(
                data
            )

                if type(data)
                    ~= "table"
                then

                    return

                end


                for _,
                    info
                    in ipairs(data)
                do

                    if type(info)
                            == "table"
                        and info.Name
                            == animalName
                    then

                        banked =
                            true


                        Log(
                            "Banked:",
                            info.Name,

                            "| Count:",
                            info.Count
                        )


                        break

                    end

                end

            end)


        Log(
            "TP home:",
            animalName
        )


        TeleportHome()


        local deadline =
            os.clock()
            + BANK_TIMEOUT


        while autoFarmActive
            and not banked
            and os.clock()
                < deadline
        do

            task.wait(
                0.01
            )

        end


        bankConnection:
        Disconnect()


        if banked then

            Log(
                "Cycle complete:",
                animalName
            )


            return true

        end


        warn(
            "[CHLISE HUB] Bank timeout:",
            animalName
        )


        return false

    end


    -- ========================================================
    -- FARM LOOP
    -- ========================================================

    local function StartAutoFarm()

        if farmLoopRunning then
            return
        end


        farmLoopRunning =
            true


        task.spawn(function()

            while autoFarmActive
                and not Window.Destroyed
            do

                local success,
                    errorMessage =
                    pcall(function()

                        local egg,
                            zoneName =
                            FindBestEgg()


                        if not egg then

                            task.wait(
                                0.25
                            )


                            return

                        end


                        local animal =
                            BreakEgg(
                                egg,
                                zoneName
                            )


                        if not autoFarmActive then
                            return
                        end


                        if animal
                            and animal.Parent
                        then

                            StealAndBank(
                                animal
                            )

                        end


                        task.wait(
                            0.15
                        )

                    end)


                if not success then

                    warn(
                        "[CHLISE HUB] Break & Steal error:",
                        errorMessage
                    )


                    task.wait(
                        0.5
                    )

                end

            end


            farmLoopRunning =
                false

        end)

    end


    -- ========================================================
    -- UI TABS
    -- Same template/API as Ride A Pet.
    -- ========================================================

    local FarmTab =
        Window:AddTab(
            "FARM",
            "◆"
        )


    local SettingsTab =
        Window.Tabs
        and Window.Tabs[
            "SETTINGS"
        ]


    if not SettingsTab then

        SettingsTab =
            Window:AddTab(
                "SETTINGS",
                "⚙"
            )

    end


    -- ========================================================
    -- AUTO FARM UI
    -- ========================================================

    local FarmSection =
        Window:AddSection(
            FarmTab,
            "Break & Steal"
        )


    FarmSection:AddDropdown(
        "BSAEZones",
        "Zone Selection",
        MASTER_ZONES,
        true,
        selectedZones,

        function(value)

            selectedZones =
                value

        end
    )


    FarmSection:AddDropdown(
        "BSAEEggs",
        "Egg Selection",
        MASTER_EGGS,
        true,
        selectedEggs,

        function(value)

            selectedEggs =
                value

        end
    )


    FarmSection:AddTextbox(
        "BSAEMinimumPetWeight",
        "Minimum Pet Weight",
        "0 = Off",

        function(value)

            local normalized =
                tostring(
                    value
                    or ""
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

                minimumPetWeight =
                    parsed

            else

                minimumPetWeight =
                    0

            end

        end
    )


    FarmSection:AddToggle(
        "BSAEAutoFarm",
        "Auto Break & Steal",
        false,

        function(state)

            autoFarmActive =
                state


            if state then

                StartAutoFarm()

            end

        end
    )


    -- ========================================================
    -- HOME UI
    -- ========================================================

    local HomeSection =
        Window:AddSection(
            FarmTab,
            "Home / Bank"
        )


    HomeSection:AddButton(
        "Set Home Position",

        function()

            local _,
                hrp =
                GetCharacter()


            homeCFrame =
                hrp.CFrame


            FarmState.HomeCFrame =
                homeCFrame


            Log(
                "Home position saved:",
                tostring(
                    hrp.Position
                )
            )

        end
    )


    -- ========================================================
    -- SETTINGS UI
    -- ========================================================

    local SettingsSection =
        Window:AddSection(
            SettingsTab,
            "Break & Steal"
        )


    SettingsSection:AddToggle(
        "BSAEDebug",
        "Debug",
        false,

        function(state)

            debugEnabled =
                state

        end
    )


    -- ========================================================
    -- READY
    -- ========================================================

    print(
        "[CHLISE HUB] Break and Steal an Egg loaded."
    )

end