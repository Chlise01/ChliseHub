-- Chlise Hub - Games/BreakAndStealAnEgg.lua
-- GameId: 10765288803
-- PlaceId: 114326934417838
-- Added: Auto Treadmill + alternating Farm/Treadmill timers
-- Added: Titanic Egg event detection/prioritization via Workspace attributes
-- Pipeline: unlimited pending hatch queue (A -> B -> C -> D ... without waiting)
-- Titanic: absolute priority over treadmill, timers, filters, normal eggs, and normal pending hatches
-- Titanic detection: standalone priority + event-driven physical index; no repeated full Workspace scan
-- Titanic movement: target is locked until that exact egg is invalid/broken, preventing back-and-forth retargeting
-- Titanic lock fix: current locked Titanic is never excluded/replaced while still valid
-- Pickup: qualifying hatch teleports directly to the pet before pickup
-- Auto Steal: optional Bat-based normal melee automation for players carrying pets; dropped pet still passes filters
-- Auto Steal precheck: identify and validate carried pet before selecting/chasing a player
-- Auto Steal final: carried pet data comes directly from Player Carrying/CarryingZone/CarryingKg/CarryingSizeMult attributes
-- Recovery teleport: if the carried pet drops during chase/return, teleport directly to that exact pet before pickup
-- Farm Teleport mode: teleport only when changing zones; move locally by walking inside the same zone
-- Auto Sell V4: uses EggRewards.PlacedCashPerSecond(AnimalName, WeightKg, SizeMult) for exact pet income before selling
-- World pet pickup: scans every hatched AnimalPickup already in the world and evaluates exact income with PlacedCashPerSecond
-- Titanic timeout: ignore locked target after 20s if still unbroken
-- Upgrades: event-driven Auto Upgrade Pen/Treadmill; only requests when Cash is sufficient
-- Shop: event-driven Auto Buy Pickaxe/Trail with confirmation + anti-spam
-- Utility: Equip Best Pet + Auto Claim Index, event-driven with debounce
-- Sell: Auto Sell resolves BackpackSellController config from GC table/upvalues and uses ToolValue / PetIncomeSeconds
-- Sell safety: GC candidate probing uses rawget to avoid proxy __index errors (GoodSignal/Connection tables)
-- Progression: Auto Next Zone checks speed, 15-hit break test, then waits for next PickaxeTier and rechecks requirement
-- Farm fallback: when current safe-zone eggs are empty, temporarily try the next eligible zone while waiting for respawn
-- Next-zone safety: detect actual current zone by zone bounds and only ever advance exactly +1 zone
-- Priority: Titanic Egg > Farm first > Treadmill; both ON alternate by timer
-- Farm filter: Minimum Pet Income/s now reads live hatch/UI income and rejects unresolved live income
-- Recovery: robust dropped-pet reacquire using HatchId + name/zone/weight fallback
-- Global pickup: collect qualifying hatched pets from any player's broken egg, not only our pending hatches
-- Global pickup safety: only collect when the pickup zone speed requirement is met
-- Global pickup range: only current safe zone and exactly one next zone; never Zone +2 or farther
-- Farm state: self-recovers if activity says Farm but worker stopped
-- Return home: dynamically targets Workspace.Build.ZoneHitboxes.SafeZone; uses current WalkSpeed

return function(Context)
    print("[CHLISE HUB] BreakAndSteal module build: INCOME_UI_AUTOSELL_V5")
    local Window = Context.Window
    local Runtime = Context.Runtime

    if not Window then
        warn("[CHLISE HUB] Window not initialized.")
        return
    end

    -- Services
    local Players = game:GetService("Players")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local Workspace = game:GetService("Workspace")
    local ProximityPromptService = game:GetService("ProximityPromptService")
    local TweenService = game:GetService("TweenService")

    local LocalPlayer = Players.LocalPlayer

    -- Shared modules
    local Shared = ReplicatedStorage:WaitForChild("Shared")
    local SafeZoneQuery = require(Shared:WaitForChild("SafeZoneQuery"))
    local ZonesConfig = require(Shared:WaitForChild("ZonesConfig"))
    local ChaseState = require(Shared:WaitForChild("ChaseState"))
    local EggRewards = require(Shared:WaitForChild("EggRewards"))
    local EggRarity = require(Shared:WaitForChild("EggRarity"))
    local PlotUpgradeConfig = require(Shared:WaitForChild("PlotUpgradeConfig"))
    local TreadmillUpgradeConfig = require(Shared:WaitForChild("TreadmillUpgradeConfig"))
    local PickaxeConfig = require(Shared:WaitForChild("PickaxeConfig"))
    local TrailsConfig = require(Shared:WaitForChild("TrailsConfig"))

    local AnimalRenders
    pcall(function()
        AnimalRenders = require(Shared:WaitForChild("AnimalRenders", 5))
    end)

    -- Game objects
    local EggHitRequest = ReplicatedStorage:WaitForChild("EggHitRequest")
    local AnimalBankedRemote = ReplicatedStorage:WaitForChild("AnimalBankedRemote")
    local TreadmillSessionRemote = ReplicatedStorage:FindFirstChild("TreadmillSessionRemote")
    local UpgradePlotRequest = ReplicatedStorage:WaitForChild("UpgradePlotRequest")
    local UpgradeTreadmillRequest = ReplicatedStorage:WaitForChild("UpgradeTreadmillRequest")
    local PickaxeShopRequest = ReplicatedStorage:WaitForChild("PickaxeShopRequest")
    local TrailShopRequest = ReplicatedStorage:WaitForChild("TrailShopRequest")
    local PetsInventoryRemote = ReplicatedStorage:WaitForChild("PetsInventoryRemote")
    local IndexRemote = ReplicatedStorage:WaitForChild("IndexRemote")
    local BackpackSellRemote = ReplicatedStorage:WaitForChild("BackpackSellRemote")

    local Build = Workspace:WaitForChild(ZonesConfig.BuildFolderName or "Build")
    local ZoneBuilds = Build:WaitForChild(ZonesConfig.ZoneBuildsName or "ZoneBuilds")
    local Pickups = Workspace:WaitForChild("AnimalPickups")
    local CollectionService = game:GetService("CollectionService")

    -- Anti AFK
    -- Event + periodic input. This avoids depending only on LocalPlayer.Idled.
    pcall(function()
        local VirtualUser =
            game:GetService(
                "VirtualUser"
            )

        local VirtualInputManager
        pcall(function()
            VirtualInputManager =
                game:GetService(
                    "VirtualInputManager"
                )
        end)

        local function sendAntiAFKInput()
            local sent =
                false

            if VirtualInputManager then
                sent =
                    pcall(function()
                        VirtualInputManager:
                            SendMouseButtonEvent(
                                0,
                                0,
                                1,
                                true,
                                game,
                                0
                            )

                        task.wait(0.05)

                        VirtualInputManager:
                            SendMouseButtonEvent(
                                0,
                                0,
                                1,
                                false,
                                game,
                                0
                            )
                    end)
            end

            if not sent then
                pcall(function()
                    VirtualUser:
                        CaptureController()

                    local camera =
                        Workspace.CurrentCamera

                    local cameraCFrame =
                        camera
                        and camera.CFrame
                        or CFrame.new()

                    VirtualUser:
                        Button2Down(
                            Vector2.new(
                                0,
                                0
                            ),
                            cameraCFrame
                        )

                    task.wait(0.08)

                    VirtualUser:
                        Button2Up(
                            Vector2.new(
                                0,
                                0
                            ),
                            cameraCFrame
                        )
                end)
            end
        end

        sendAntiAFKInput()

        LocalPlayer.Idled:
            Connect(function()
                sendAntiAFKInput()
            end)

        task.spawn(function()
            while true do
                task.wait(45)
                sendAntiAFKInput()
            end
        end)

        print(
            "[CHLISE HUB] Anti AFK V3 active | periodic input: 45s"
        )
    end)

    -- Tunables
    local HIT_DISTANCE = 7
    local EGG_APPROACH_DISTANCE = 4
    local HIT_DELAY = 0.52
    local TWEEN_SPEED_MULTIPLIER = 4
    local TWEEN_MIN_SPEED = 200

    local PICKUP_SPAWN_TIMEOUT = 8
    local MAX_PICKUP_SPAWN_DISTANCE = 15

    local PET_APPROACH_DISTANCE = 3
    local PROMPT_TIMEOUT = 7
    local CARRY_TIMEOUT = 3
    local BANK_TIMEOUT = 8

    local MOVE_REFRESH = 0.08
    local MOVE_STUCK_SECONDS = 2
    local MOVE_STUCK_STUDS = 0.75

    -- Movement speed is synced 1:1 to the Humanoid's current WalkSpeed.
    -- The script never overwrites WalkSpeed.
    local HOME_CONFIRM_TIMEOUT = 8
    local BANK_GRACE_SECONDS = 1.5
    local HOME_RETRY_WAIT = 0.12
    local DROPPED_PET_TIMEOUT = 12
    local DROPPED_PET_SEARCH_RADIUS = 60

    -- State
    local autoFarmActive = false
    local autoFarmEnabled = false
    local farmLoopRunning = false

    local autoTreadmillActive = false
    local autoTreadmillEnabled = false
    local treadmillLoopRunning = false

    local currentActivity = nil
    local activityDeadline = nil

    local farmTimerValue = 10
    local farmTimerUnit = "Minutes"

    local treadmillTimerValue = 10
    local treadmillTimerUnit = "Minutes"

    local treadmillSessionSpeed = nil
    local treadmillSessionCFrame = nil
    local lastTreadmillSession = 0

    local autoUpgradePen = false
    local autoUpgradeTreadmill = false

    local penUpgradeWorkerRunning = false
    local treadmillUpgradeWorkerRunning = false

    local penUpgradeRetryAt = 0
    local treadmillUpgradeRetryAt = 0


    -- Titanic is allowed to temporarily override the normal Farm/Treadmill
    -- schedule. We preserve the previous activity + remaining timer so it can
    -- resume after the Titanic target is gone.
    local titanicOverrideActive = false
    local titanicOverrideRequested = false
    local titanicResumeActivity = nil
    local titanicResumeRemaining = nil
    local titanicOverrideSpawnId = nil

    local debugEnabled = false

    local selectedZones = {}
    local selectedEggs = {}
    local selectedPets = {}

    local prioritizeTitanicEgg = true

    local movementMode = "Walk"

    local Extra = {
        autoBuyPickaxe = false,
        autoBuyTrail = false,

        pickaxeBuyWorkerRunning = false,
        trailBuyWorkerRunning = false,

        pickaxeBuyRetryAt = 0,
        trailBuyRetryAt = 0,

        equipBestPetEnabled = false,
        autoClaimIndex = false,

        equipBestPetBusy = false,
        autoClaimIndexBusy = false,

        lastEquipBestPetAt = 0,
        lastAutoClaimIndexAt = 0,

        minimumPetIncome = 0,

        autoSellEnabled = false,
        autoSellBelowIncome = 0,
        autoSellBusy = false,
        lastAutoSellAt = 0,
        backpackSellConfig = nil,
        autoSellConfigWarned = false,
        autoSellRequestToken = nil,

        titanicCandidates = {},
        titanicDirty = true,

        titanicLockedEgg = nil,
        titanicLockedZone = nil,
        titanicLockedSpawnId = nil,
        titanicLockedAt = 0,
        titanicIgnoredSpawnId = nil,
        titanicIgnoredEgg = nil,

        autoNextZoneEnabled = false,
        autoNextZoneSafeZone = nil,
        autoNextZoneTrialZone = nil,
        autoNextZoneBlockedZone = nil,
        autoNextZoneBlockedPickaxeTier = nil,
        autoNextZoneTrialHits = 0,
        autoNextZonePromotedPickaxeTier = nil,

        autoStealEnabled = false,
        autoStealBusy = false,
        autoStealWorkerRunning = false,
        autoStealBatWarned = false,

        globalPickupScanAt = 0,
        globalPickupCached = nil
    }

    function Extra.log(...)
        if debugEnabled then
            print("[CHLISE HUB][BREAK & STEAL]", ...)
        end
    end

    function Extra.getCharacter()
        local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
        local humanoid = character:WaitForChild("Humanoid")
        local hrp = character:WaitForChild("HumanoidRootPart")
        return character, humanoid, hrp
    end

    function Extra.getCurrentMoveSpeed()
        local _, humanoid = Extra.getCharacter()

        local speed =
            tonumber(humanoid.WalkSpeed)
            or 16

        -- Never let a temporary zero/invalid value create an infinite tween.
        speed =
            math.max(
                speed,
                1
            )

        return speed
    end

    -- Selection helpers
    function Extra.selectionEmpty(selection)
        if type(selection) ~= "table" then
            return true
        end

        for key, value in pairs(selection) do
            if value == true then
                return false
            end

            if type(key) == "number" and type(value) == "string" then
                return false
            end
        end

        return true
    end

    function Extra.isSelected(selection, wanted)
        if Extra.selectionEmpty(selection) then
            return true
        end

        if selection[wanted] == true then
            return true
        end

        for key, value in pairs(selection) do
            if value == wanted or (key == wanted and value == true) then
                return true
            end
        end

        return false
    end

    function Extra.normalizeZone(value)
        if typeof(value) == "number" then
            return "Zone" .. tostring(value)
        end

        if typeof(value) == "string" then
            local number = value:match("%d+")
            if number then
                return "Zone" .. number
            end
        end

        return nil
    end

    -- Zones are taken directly from the game's config.
    local MASTER_ZONES = {}

    for _, info in ipairs(ZonesConfig.Zones or {}) do
        if type(info) == "table" and type(info.Id) == "string" then
            table.insert(MASTER_ZONES, info.Id)
        end
    end

    if #MASTER_ZONES == 0 then
        for i = 1, 9 do
            table.insert(MASTER_ZONES, "Zone" .. tostring(i))
        end
    end

    -- UI labels are separate from raw names used by the game.
    local zoneLabels, petLabels, eggLabels = {}, {}, {}
    function Extra.displayName(raw)
        local name = (EggRewards.DisplayNames or {})[raw] or tostring(raw)
        name = name:gsub("_", " "):gsub("(%l)(%u)", "%1 %2")
            :gsub("(%u)(%u%l)", "%1 %2")
        return (name:gsub("%S+", function(word)
            if word == "T-Rex" then return word end
            return word:sub(1, 1):upper() .. word:sub(2):lower()
        end))
    end

    function Extra.decodeSelection(value, labels)
        local result = {}
        if type(value) == "string" then
            result[labels[value] or value] = true
        elseif type(value) == "table" then
            for key, selected in pairs(value) do
                local label = type(key) == "number" and selected
                    or (selected == true and key)
                if type(label) == "string" then
                    result[labels[label] or label] = true
                end
            end
        end
        return result
    end

    table.sort(MASTER_ZONES, function(a, b)
        return (tonumber(a:match("%d+")) or 999) < (tonumber(b:match("%d+")) or 999)
    end)
    local ZONE_OPTIONS = {}
    for _, raw in ipairs(MASTER_ZONES) do
        local label = "Zone " .. (raw:match("%d+") or raw)
        zoneLabels[label] = raw
        table.insert(ZONE_OPTIONS, label)
    end

    function Extra.buildPetList()
        local rows, found = {}, {}
        local rarityOrder = {}
        for i, rarity in ipairs({
            "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic",
            "Divine", "Cosmic", "Secret", "Celestial", "Inferno"
        }) do rarityOrder[rarity] = i end
        local function add(raw, zone, rarity)
            if type(raw) ~= "string" or raw == "" or found[raw] then return end
            found[raw] = true
            table.insert(rows, {
                raw = raw, name = Extra.displayName(raw),
                zone = tonumber(zone), rarity = rarity or "Unknown"
            })
        end
        for _, info in ipairs(EggRewards.Pool or {}) do
            -- Extras have CashZone, which is a payout tier, not a spawn zone.
            add(info.Name, info.Zone, info.Rarity)
        end
        if type(AnimalRenders) == "table" and type(AnimalRenders.Normal) == "table" then
            for raw in pairs(AnimalRenders.Normal) do
                add(raw, EggRewards.HomeZoneOf(raw), EggRewards.RarityOf(raw))
            end
        end
        for _, animal in ipairs(Pickups:GetChildren()) do
            local raw = animal:GetAttribute("AnimalName") or animal.Name
            add(raw, EggRewards.HomeZoneOf(raw), EggRewards.RarityOf(raw))
        end
        table.sort(rows, function(a, b)
            if (a.zone or 999) ~= (b.zone or 999) then
                return (a.zone or 999) < (b.zone or 999)
            end
            local ar, br = rarityOrder[a.rarity] or 999, rarityOrder[b.rarity] or 999
            if ar ~= br then return ar < br end
            if a.name ~= b.name then return a.name:lower() < b.name:lower() end
            return a.raw < b.raw
        end)
        local result = {}
        for _, row in ipairs(rows) do
            local prefix = row.zone and ("Zone " .. row.zone) or "Special"
            local label = prefix .. " • " .. row.rarity .. " • " .. row.name
            if petLabels[label] and petLabels[label] ~= row.raw then
                label = label .. " (" .. row.raw .. ")"
            end
            petLabels[label] = row.raw
            table.insert(result, label)
        end
        return result
    end

    local MASTER_PETS = Extra.buildPetList()

    -- Owned plot / home
    function Extra.getOwnedPlotHitbox()
        local hitbox = SafeZoneQuery.GetOwnedPlotHitbox(LocalPlayer.UserId)

        if hitbox and hitbox.Parent and hitbox:IsA("BasePart") then
            return hitbox
        end

        return nil
    end

    function Extra.isBankablePosition(position)
        local ok, result = pcall(function()
            return SafeZoneQuery.IsBankable(LocalPlayer.UserId, position)
        end)

        return ok and result == true
    end

    function Extra.durationToSeconds(value, unit)
        local amount = tonumber(value)

        if not amount or amount <= 0 then
            return nil
        end

        if unit == "Hours" then
            return amount * 3600
        end

        return amount * 60
    end

    function Extra.getActivityDuration(activity)
        if activity == "Farm" then
            return Extra.durationToSeconds(
                farmTimerValue,
                farmTimerUnit
            )
        end

        if activity == "Treadmill" then
            return Extra.durationToSeconds(
                treadmillTimerValue,
                treadmillTimerUnit
            )
        end

        return nil
    end

    function Extra.otherActivityEnabled(activity)
        if activity == "Farm" then
            return autoTreadmillEnabled
        end

        if activity == "Treadmill" then
            return autoFarmEnabled
        end

        return false
    end

    function Extra.refreshActivityDeadline()
        if not currentActivity
            or not Extra.otherActivityEnabled(currentActivity)
        then
            activityDeadline = nil
            return
        end

        local duration =
            Extra.getActivityDuration(currentActivity)

        if duration then
            activityDeadline =
                os.clock() + duration
        else
            activityDeadline = nil
        end
    end

    function Extra.getOwnedPlot()
        local hitbox =
            Extra.getOwnedPlotHitbox()

        if not hitbox then
            return nil
        end

        local plots =
            Workspace:
            FindFirstChild(
                ZonesConfig.PlotsFolderName
                or "Plots"
            )

        if not plots then
            return hitbox.Parent
        end

        local current =
            hitbox

        while current
            and current.Parent
            and current.Parent ~= plots
        do
            current = current.Parent
        end

        if current
            and current.Parent == plots
        then
            return current
        end

        return hitbox.Parent
    end

    -- Exact plot ownership for upgrade systems.
    -- This does not depend on SafeZoneQuery/hitbox state.
    function Extra.getOwnedPlotExact()
        local plots =
            Workspace:
            FindFirstChild(
                ZonesConfig.PlotsFolderName
                or "Plots"
            )

        if not plots then
            return nil
        end

        for _, plot
            in ipairs(
                plots:GetChildren()
            )
        do
            if tonumber(
                plot:GetAttribute(
                    "OwnerUserId"
                )
            ) == LocalPlayer.UserId
            then
                return plot
            end
        end

        return nil
    end

    function Extra.getCash()
        return
            tonumber(
                LocalPlayer:GetAttribute(
                    "Cash"
                )
            )
            or 0
    end

    function Extra.getNextPenUpgradeCost(
        plot
    )
        if not plot then
            return nil, nil
        end

        local level =
            tonumber(
                plot:GetAttribute(
                    "PlotLevel"
                )
            )
            or tonumber(
                PlotUpgradeConfig.DefaultLevel
            )
            or 1

        local maxLevel =
            tonumber(
                PlotUpgradeConfig.MaxLevel
            )
            or 9

        if level >= maxLevel then
            return nil, level
        end

        local cost

        if type(
            PlotUpgradeConfig.UpgradeCost
        ) == "function"
        then
            local ok, value =
                pcall(
                    PlotUpgradeConfig.UpgradeCost,
                    level
                )

            if ok then
                cost =
                    tonumber(value)
            end
        end

        if not cost
            and type(
                PlotUpgradeConfig.Costs
            ) == "table"
        then
            cost =
                tonumber(
                    PlotUpgradeConfig.Costs[
                        level
                    ]
                )
        end

        return cost, level
    end

    function Extra.getNextTreadmillUpgradeCost(
        plot
    )
        if not plot then
            return nil, nil
        end

        local level =
            tonumber(
                plot:GetAttribute(
                    "TreadmillLevel"
                )
            )
            or tonumber(
                TreadmillUpgradeConfig.DefaultLevel
            )
            or 1

        local maxLevel =
            tonumber(
                TreadmillUpgradeConfig.MaxLevel
            )
            or 9

        if level >= maxLevel then
            return nil, level
        end

        local cost

        if type(
            TreadmillUpgradeConfig.UpgradeCost
        ) == "function"
        then
            local ok, value =
                pcall(
                    TreadmillUpgradeConfig.UpgradeCost,
                    level
                )

            if ok then
                cost =
                    tonumber(value)
            end
        end

        if not cost
            and type(
                TreadmillUpgradeConfig.Levels
            ) == "table"
        then
            local info =
                TreadmillUpgradeConfig.Levels[
                    level
                ]

            cost =
                info
                and tonumber(
                    info.UpgradeCost
                )
                or nil
        end

        return cost, level
    end

    function Extra.waitForUpgradeLevel(
        plot,
        attributeName,
        oldLevel,
        timeout
    )
        local deadline =
            os.clock()
            + (
                tonumber(timeout)
                or 5
            )

        while plot
            and plot.Parent
            and os.clock() < deadline
        do
            local newLevel =
                tonumber(
                    plot:GetAttribute(
                        attributeName
                    )
                )

            if newLevel
                and newLevel > oldLevel
            then
                return true, newLevel
            end

            task.wait(0.05)
        end

        return false, oldLevel
    end

    function Extra.runAutoUpgradePen()
        if penUpgradeWorkerRunning then
            return
        end

        penUpgradeWorkerRunning = true

        task.spawn(function()
            while autoUpgradePen
                and not Window.Destroyed
            do
                local plot =
                    Extra.getOwnedPlotExact()

                if not plot then
                    break
                end

                local cost, level =
                    Extra.getNextPenUpgradeCost(
                        plot
                    )

                if not cost then
                    Extra.log(
                        "Auto Upgrade Pen:",
                        "MAX LEVEL",
                        "| Level:",
                        level
                    )

                    break
                end

                local cash =
                    Extra.getCash()

                if cash < cost then
                    Extra.log(
                        "Auto Upgrade Pen waiting",
                        "| Level:",
                        level,
                        "| Cash:",
                        cash,
                        "| Need:",
                        cost
                    )

                    break
                end

                if os.clock()
                    < penUpgradeRetryAt
                then
                    break
                end

                Extra.log(
                    "Auto Upgrade Pen request",
                    "| Level:",
                    level,
                    "->",
                    level + 1,
                    "| Cost:",
                    cost,
                    "| Cash:",
                    cash
                )

                UpgradePlotRequest:
                    FireServer()

                local confirmed,
                    newLevel =
                    Extra.waitForUpgradeLevel(
                        plot,
                        "PlotLevel",
                        level,
                        5
                    )

                if not confirmed then
                    -- Conservative retry protection:
                    -- never hammer the same server request.
                    penUpgradeRetryAt =
                        os.clock() + 10

                    Extra.log(
                        "Auto Upgrade Pen:",
                        "no level confirmation; cooldown 10s"
                    )

                    break
                end

                penUpgradeRetryAt = 0

                Extra.log(
                    "Auto Upgrade Pen confirmed",
                    "| Level:",
                    newLevel
                )

                -- If Cash is still enough for the next level,
                -- continue one confirmed upgrade at a time.
                task.wait(0.05)
            end

            penUpgradeWorkerRunning =
                false
        end)
    end

    function Extra.runAutoUpgradeTreadmill()
        if treadmillUpgradeWorkerRunning then
            return
        end

        treadmillUpgradeWorkerRunning = true

        task.spawn(function()
            while autoUpgradeTreadmill
                and not Window.Destroyed
            do
                local plot =
                    Extra.getOwnedPlotExact()

                if not plot then
                    break
                end

                if plot:GetAttribute(
                    "TreadmillUnlocked"
                ) ~= true
                then
                    Extra.log(
                        "Auto Upgrade Treadmill:",
                        "treadmill is locked"
                    )

                    break
                end

                local cost, level =
                    Extra.getNextTreadmillUpgradeCost(
                        plot
                    )

                if not cost then
                    Extra.log(
                        "Auto Upgrade Treadmill:",
                        "MAX LEVEL",
                        "| Level:",
                        level
                    )

                    break
                end

                local cash =
                    Extra.getCash()

                if cash < cost then
                    Extra.log(
                        "Auto Upgrade Treadmill waiting",
                        "| Level:",
                        level,
                        "| Cash:",
                        cash,
                        "| Need:",
                        cost
                    )

                    break
                end

                if os.clock()
                    < treadmillUpgradeRetryAt
                then
                    break
                end

                Extra.log(
                    "Auto Upgrade Treadmill request",
                    "| Level:",
                    level,
                    "->",
                    level + 1,
                    "| Cost:",
                    cost,
                    "| Cash:",
                    cash
                )

                UpgradeTreadmillRequest:
                    FireServer()

                local confirmed,
                    newLevel =
                    Extra.waitForUpgradeLevel(
                        plot,
                        "TreadmillLevel",
                        level,
                        5
                    )

                if not confirmed then
                    treadmillUpgradeRetryAt =
                        os.clock() + 10

                    Extra.log(
                        "Auto Upgrade Treadmill:",
                        "no level confirmation; cooldown 10s"
                    )

                    break
                end

                treadmillUpgradeRetryAt = 0

                Extra.log(
                    "Auto Upgrade Treadmill confirmed",
                    "| Level:",
                    newLevel
                )

                task.wait(0.05)
            end

            treadmillUpgradeWorkerRunning =
                false
        end)
    end

    function Extra.parseOwnedTrails()
        local owned = {}

        local raw =
            LocalPlayer:GetAttribute(
                TrailsConfig.OwnedAttribute
                or "OwnedTrails"
            )

        if type(raw) == "string" then
            for token in raw:gmatch(
                "[^,%s]+"
            ) do
                local id =
                    tonumber(token)

                if id then
                    owned[
                        math.floor(id)
                    ] = true
                end
            end

        elseif type(raw) == "number" then
            owned[
                math.floor(raw)
            ] = true

        elseif type(raw) == "table" then
            for key, value
                in pairs(raw)
            do
                local id =
                    tonumber(key)
                    or tonumber(value)

                if id then
                    owned[
                        math.floor(id)
                    ] = true
                end
            end
        end

        return owned
    end

    function Extra.getNextPickaxePurchase()
        local currentTier =
            tonumber(
                LocalPlayer:GetAttribute(
                    "PickaxeTier"
                )
            )
            or tonumber(
                PickaxeConfig.DefaultTier
            )
            or 1

        local tiers =
            PickaxeConfig.Tiers
            or {}

        local nextTier =
            currentTier + 1

        local info =
            tiers[
                nextTier
            ]

        if not info then
            return nil,
                currentTier
        end

        return {
            Tier = nextTier,
            Info = info,
            Price =
                tonumber(
                    info.Price
                )
                or 0
        },
        currentTier
    end

    function Extra.getBestOwnedTrail()
        local owned =
            Extra.parseOwnedTrails()

        local bestId
        local bestMultiplier =
            -math.huge

        for _, info
            in ipairs(
                TrailsConfig.Trails
                or {}
            )
        do
            local id =
                tonumber(
                    info.Id
                )

            if id
                and owned[id]
            then
                local multiplier =
                    tonumber(
                        info.Multiplier
                    )

                if not multiplier
                    and type(
                        TrailsConfig.MultiplierFor
                    ) == "function"
                then
                    local ok,
                        result =
                        pcall(
                            TrailsConfig.MultiplierFor,
                            id
                        )

                    multiplier =
                        ok
                        and tonumber(result)
                        or nil
                end

                multiplier =
                    multiplier
                    or id

                if multiplier
                    > bestMultiplier
                then
                    bestMultiplier =
                        multiplier
                    bestId =
                        id
                end
            end
        end

        return
            bestId,
            bestMultiplier
    end

    function Extra.equipBestOwnedTrail()
        local bestId,
            multiplier =
            Extra.getBestOwnedTrail()

        if not bestId then
            return false
        end

        local attribute =
            TrailsConfig.EquippedAttribute
            or "EquippedTrail"

        local equipped =
            tonumber(
                LocalPlayer:
                GetAttribute(
                    attribute
                )
            )

        if equipped == bestId then
            return true
        end

        Extra.log(
            "Equip best trail",
            "| Current:",
            equipped,
            "| Best:",
            bestId,
            "| Multiplier:",
            multiplier
        )

        TrailShopRequest:
            FireServer(
                "Equip",
                bestId
            )

        return
            Extra.waitForTrailEquipped(
                bestId,
                3
            )
    end

    function Extra.getNextTrailPurchase()
        local owned =
            Extra.parseOwnedTrails()

        local trails =
            TrailsConfig.Trails
            or {}

        for _, info
            in ipairs(trails)
        do
            local id =
                tonumber(
                    info.Id
                )

            if id
                and not owned[id]
            then
                return {
                    Id = id,
                    Info = info,
                    Price =
                        tonumber(
                            info.Price
                        )
                        or 0
                }
            end
        end

        return nil
    end

    function Extra.waitForPickaxeTier(
        oldTier,
        timeout
    )
        local deadline =
            os.clock()
            + (
                tonumber(timeout)
                or 5
            )

        while os.clock()
            < deadline
        do
            local tier =
                tonumber(
                    LocalPlayer:GetAttribute(
                        "PickaxeTier"
                    )
                )
                or 0

            if tier > oldTier then
                return true, tier
            end

            task.wait(0.05)
        end

        return false, oldTier
    end

    function Extra.waitForTrailOwned(
        trailId,
        timeout
    )
        local deadline =
            os.clock()
            + (
                tonumber(timeout)
                or 5
            )

        while os.clock()
            < deadline
        do
            local owned =
                Extra.parseOwnedTrails()

            if owned[
                trailId
            ] then
                return true
            end

            task.wait(0.05)
        end

        return false
    end

    function Extra.waitForTrailEquipped(
        trailId,
        timeout
    )
        local deadline =
            os.clock()
            + (
                tonumber(timeout)
                or 3
            )

        local attribute =
            TrailsConfig.EquippedAttribute
            or "EquippedTrail"

        while os.clock()
            < deadline
        do
            local equipped =
                tonumber(
                    LocalPlayer:GetAttribute(
                        attribute
                    )
                )

            if equipped
                == trailId
            then
                return true
            end

            task.wait(0.05)
        end

        return false
    end

    function Extra.runAutoBuyPickaxe()
        if Extra.pickaxeBuyWorkerRunning then
            return
        end

        Extra.pickaxeBuyWorkerRunning = true

        task.spawn(function()
            while Extra.autoBuyPickaxe
                and not Window.Destroyed
            do
                local nextPurchase,
                    currentTier =
                    Extra.getNextPickaxePurchase()

                if not nextPurchase then
                    Extra.log(
                        "Auto Buy Pickaxe:",
                        "MAX TIER",
                        "| Tier:",
                        currentTier
                    )

                    break
                end

                local cash =
                    Extra.getCash()

                if cash
                    < nextPurchase.Price
                then
                    Extra.log(
                        "Auto Buy Pickaxe waiting",
                        "| Current:",
                        currentTier,
                        "| Next:",
                        nextPurchase.Tier,
                        "| Cash:",
                        cash,
                        "| Need:",
                        nextPurchase.Price
                    )

                    break
                end

                if os.clock()
                    < Extra.pickaxeBuyRetryAt
                then
                    break
                end

                Extra.log(
                    "Auto Buy Pickaxe request",
                    "| Tier:",
                    currentTier,
                    "->",
                    nextPurchase.Tier,
                    "| Price:",
                    nextPurchase.Price
                )

                -- Client shop callback format:
                -- PickaxeShopRequest:FireServer("Buy", tier)
                PickaxeShopRequest:
                    FireServer(
                        "Buy",
                        nextPurchase.Tier
                    )

                local confirmed,
                    newTier =
                    Extra.waitForPickaxeTier(
                        currentTier,
                        5
                    )

                if not confirmed then
                    Extra.pickaxeBuyRetryAt =
                        os.clock() + 10

                    Extra.log(
                        "Auto Buy Pickaxe:",
                        "no tier confirmation; cooldown 10s"
                    )

                    break
                end

                Extra.pickaxeBuyRetryAt = 0

                Extra.log(
                    "Auto Buy Pickaxe confirmed",
                    "| Tier:",
                    newTier
                )

                task.wait(0.05)
            end

            Extra.pickaxeBuyWorkerRunning =
                false
        end)
    end

    function Extra.runAutoBuyTrail()
        if Extra.trailBuyWorkerRunning then
            return
        end

        Extra.trailBuyWorkerRunning = true

        task.spawn(function()
            while Extra.autoBuyTrail
                and not Window.Destroyed
            do
                -- Always keep the strongest owned trail equipped, even when
                -- the next trail is not yet affordable or all trails are owned.
                Extra.equipBestOwnedTrail()

                local nextPurchase =
                    Extra.getNextTrailPurchase()

                if not nextPurchase then
                    Extra.log(
                        "Auto Buy Trail:",
                        "ALL OWNED"
                    )

                    break
                end

                local cash =
                    Extra.getCash()

                if cash
                    < nextPurchase.Price
                then
                    Extra.log(
                        "Auto Buy Trail waiting",
                        "| Next ID:",
                        nextPurchase.Id,
                        "| Name:",
                        nextPurchase.Info.Name,
                        "| Cash:",
                        cash,
                        "| Need:",
                        nextPurchase.Price
                    )

                    break
                end

                if os.clock()
                    < Extra.trailBuyRetryAt
                then
                    break
                end

                Extra.log(
                    "Auto Buy Trail request",
                    "| ID:",
                    nextPurchase.Id,
                    "| Name:",
                    nextPurchase.Info.Name,
                    "| Price:",
                    nextPurchase.Price
                )

                -- Client shop callback format:
                -- TrailShopRequest:FireServer("Buy", trailId)
                TrailShopRequest:
                    FireServer(
                        "Buy",
                        nextPurchase.Id
                    )

                local confirmed =
                    Extra.waitForTrailOwned(
                        nextPurchase.Id,
                        5
                    )

                if not confirmed then
                    Extra.trailBuyRetryAt =
                        os.clock() + 10

                    Extra.log(
                        "Auto Buy Trail:",
                        "no ownership confirmation; cooldown 10s"
                    )

                    break
                end

                Extra.trailBuyRetryAt = 0

                Extra.log(
                    "Auto Buy Trail confirmed",
                    "| ID:",
                    nextPurchase.Id
                )

                -- Re-evaluate the inventory and equip the strongest owned
                -- trail instead of assuming the just-bought ID is always best.
                Extra.equipBestOwnedTrail()

                task.wait(0.05)
            end

            Extra.trailBuyWorkerRunning =
                false
        end)
    end

    function Extra.triggerAutoPurchases()
        if Extra.autoBuyPickaxe then
            Extra.runAutoBuyPickaxe()
        end

        if Extra.autoBuyTrail then
            Extra.runAutoBuyTrail()
        end
    end

    function Extra.equipBestPet()
        if not Extra.equipBestPetEnabled
            or Extra.equipBestPetBusy
            or Window.Destroyed
        then
            return
        end

        local now =
            os.clock()

        if now
            - Extra.lastEquipBestPetAt
            < 0.75
        then
            return
        end

        Extra.equipBestPetBusy = true
        Extra.lastEquipBestPetAt = now

        task.spawn(function()
            Extra.log(
                "Equip Best Pet request"
            )

            PetsInventoryRemote:
                FireServer(
                    "EquipBest",
                    nil
                )

            task.wait(0.75)

            Extra.equipBestPetBusy =
                false
        end)
    end

    function Extra.claimAllIndex()
        if not Extra.autoClaimIndex
            or Extra.autoClaimIndexBusy
            or Window.Destroyed
        then
            return
        end

        local now =
            os.clock()

        if now
            - Extra.lastAutoClaimIndexAt
            < 1.5
        then
            return
        end

        Extra.autoClaimIndexBusy = true
        Extra.lastAutoClaimIndexAt = now

        task.spawn(function()
            Extra.log(
                "Auto Claim Index request"
            )

            IndexRemote:
                FireServer(
                    "ClaimAll",
                    nil
                )

            task.wait(1.5)

            Extra.autoClaimIndexBusy =
                false
        end)
    end

    function Extra.onPetInventoryChanged()
        if Extra.equipBestPetEnabled then
            task.delay(
                0.25,
                Extra.equipBestPet
            )
        end

        if Extra.autoClaimIndex then
            task.delay(
                0.5,
                Extra.claimAllIndex
            )
        end
    end

    function Extra.triggerAutoUpgrades()
        if autoUpgradePen then
            Extra.runAutoUpgradePen()
        end

        if autoUpgradeTreadmill then
            Extra.runAutoUpgradeTreadmill()
        end
    end

    -- Event-driven: no upgrade polling loop.
    LocalPlayer:
    GetAttributeChangedSignal(
        "Cash"
    ):
    Connect(function()
        Extra.triggerAutoUpgrades()
        Extra.triggerAutoPurchases()
    end)

    function Extra.treadmillMultiplier(object)
        local current = object

        while current do
            local value =
                tonumber(
                    current:GetAttribute(
                        "OwnMultiplier"
                    )
                )

            if value then
                return value
            end

            current = current.Parent
        end

        return 1
    end

    function Extra.findTreadmillPart(container)
        if not container then
            return nil
        end

        local preferredNames = {
            "Treadmill part",
            "Treadmill Part",
            "Hitbox"
        }

        for _, name
            in ipairs(preferredNames)
        do
            local object =
                container:
                FindFirstChild(
                    name,
                    true
                )

            if object
                and object:IsA("BasePart")
            then
                return object
            end
        end

        if container:IsA("BasePart") then
            return container
        end

        if container:IsA("Model")
            and container.PrimaryPart
        then
            return container.PrimaryPart
        end

        for _, object
            in ipairs(
                container:GetDescendants()
            )
        do
            if object:IsA("BasePart") then
                return object
            end
        end

        return nil
    end

    function Extra.getPlotTreadmill()
        local plot =
            Extra.getOwnedPlot()

        if not plot then
            return nil, nil, nil, nil
        end

        local bestModel
        local bestPart
        local bestMultiplier =
            -math.huge

        -- Prefer direct plot children such as:
        -- Wooden Treadmill / Volcanic Treadmill /
        -- Speedy Treadmill / Diamond Treadmill.
        for _, child
            in ipairs(plot:GetChildren())
        do
            local lowerName =
                child.Name:lower()

            if lowerName:find(
                    "treadmill",
                    1,
                    true
                )
                and lowerName
                    ~= "treadmillboard"
                and not lowerName:find(
                    "spawnvfx",
                    1,
                    true
                )
            then
                local part =
                    Extra.findTreadmillPart(child)

                if part then
                    local multiplier =
                        Extra.treadmillMultiplier(child)

                    if multiplier
                        > bestMultiplier
                    then
                        bestModel = child
                        bestPart = part
                        bestMultiplier =
                            multiplier
                    end
                end
            end
        end

        -- Fallback if the treadmill is nested.
        if not bestPart then
            for _, object
                in ipairs(
                    plot:GetDescendants()
                )
            do
                local lowerName =
                    object.Name:lower()

                if lowerName:find(
                        "treadmill",
                        1,
                        true
                    )
                    and lowerName
                        ~= "treadmillboard"
                    and not lowerName:find(
                        "spawnvfx",
                        1,
                        true
                    )
                then
                    local part =
                        Extra.findTreadmillPart(object)

                    if part then
                        local multiplier =
                            Extra.treadmillMultiplier(
                                object
                            )

                        if multiplier
                            > bestMultiplier
                        then
                            bestModel = object
                            bestPart = part
                            bestMultiplier =
                                multiplier
                        end
                    end
                end
            end
        end

        return
            plot,
            bestModel,
            bestPart,
            bestMultiplier
    end

    function Extra.getTreadmillStandCFrame(part)
        local _, humanoid, hrp =
            Extra.getCharacter()

        local rootHalfHeight =
            hrp.Size.Y * 0.5

        local standHeight =
            part.Size.Y * 0.5
            + humanoid.HipHeight
            + rootHalfHeight
            + 0.15

        return
            part.CFrame
            * CFrame.new(
                0,
                standHeight,
                0
            )
    end

    function Extra.teleportToTreadmill()
        local plot,
            model,
            part,
            multiplier =
            Extra.getPlotTreadmill()

        if not plot then
            warn(
                "[CHLISE HUB] Owned plot not found for Auto Treadmill."
            )

            return false
        end

        if not part then
            warn(
                "[CHLISE HUB] Treadmill not found inside owned plot:",
                plot:GetFullName()
            )

            return false
        end

        local _, humanoid, hrp =
            Extra.getCharacter()

        humanoid:Move(
            Vector3.zero,
            false
        )

        local standCF =
            Extra.getTreadmillStandCFrame(
                part
            )

        hrp.AssemblyLinearVelocity =
            Vector3.zero

        hrp.AssemblyAngularVelocity =
            Vector3.zero

        hrp.CFrame =
            standCF

        Extra.log(
            "Auto Treadmill teleport",
            "| Plot:",
            plot.Name,
            "| Treadmill:",
            model and model.Name or part.Name,
            "| Multiplier:",
            multiplier,
            "| Position:",
            standCF.Position
        )

        return true
    end

    function Extra.isOnTreadmill(part)
        if not part
            or not part.Parent
        then
            return false
        end

        local _, _, hrp =
            Extra.getCharacter()

        local localPosition =
            part.CFrame:
            PointToObjectSpace(
                hrp.Position
            )

        local horizontalPadding =
            2.5

        local insideX =
            math.abs(localPosition.X)
            <= part.Size.X * 0.5
                + horizontalPadding

        local insideZ =
            math.abs(localPosition.Z)
            <= part.Size.Z * 0.5
                + horizontalPadding

        local verticalDistance =
            math.abs(
                localPosition.Y
                - (
                    part.Size.Y * 0.5
                    + 3
                )
            )

        return
            insideX
            and insideZ
            and verticalDistance <= 8
    end






    -- Normal character movement.
    -- This intentionally does NOT raw-CFrame teleport long distances.
    function Extra.stopMoving()
        local character = LocalPlayer.Character
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        if humanoid then humanoid:Move(Vector3.zero, false) end
    end

    function Extra.walkTo(targetPosition, stopDistance, timeout, extraCheck, speedLimit)
        stopDistance = tonumber(stopDistance) or 3
        local character, humanoid, hrp = Extra.getCharacter()
        local deadline = os.clock() + (tonumber(timeout) or 30)
        local lastPosition, lastProgress = hrp.Position, os.clock()
        local arrived = false
        local restoreSpeed = humanoid.WalkSpeed
        local appliedSpeed
        local runService = game:GetService("RunService")
        local moveBinding = "ChliseBSAEWalk_" .. tostring(LocalPlayer.UserId)
        runService:BindToRenderStep(moveBinding, Enum.RenderPriority.Character.Value + 1, function()
            if autoFarmActive and hrp.Parent and humanoid.Health > 0 then
                if speedLimit then
                    -- Preserve updated boosts while limiting only the plot entry.
                    if appliedSpeed == nil or humanoid.WalkSpeed ~= appliedSpeed then
                        restoreSpeed = humanoid.WalkSpeed
                    end
                    appliedSpeed = math.min(restoreSpeed, speedLimit)
                    humanoid.WalkSpeed = appliedSpeed
                end
                local delta = targetPosition - hrp.Position
                local flat = Vector3.new(delta.X, 0, delta.Z)
                humanoid:Move(flat.Magnitude > stopDistance and flat.Unit or Vector3.zero, false)
            else
                humanoid:Move(Vector3.zero, false)
            end
        end)
        local ok, err = pcall(function()
            while autoFarmActive and LocalPlayer.Character == character
                and hrp.Parent and humanoid.Health > 0 and os.clock() < deadline do
                if type(extraCheck) == "function" and extraCheck() then
                    arrived = true
                    break
                end
                local delta = hrp.Position - targetPosition
                if Vector3.new(delta.X, 0, delta.Z).Magnitude <= stopDistance then
                    arrived = true
                    break
                end
                if (hrp.Position - lastPosition).Magnitude >= MOVE_STUCK_STUDS then
                    lastPosition, lastProgress = hrp.Position, os.clock()
                elseif os.clock() - lastProgress >= MOVE_STUCK_SECONDS then
                    humanoid.Jump = true
                    lastPosition, lastProgress = hrp.Position, os.clock()
                end
                task.wait(MOVE_REFRESH)
            end
        end)
        runService:UnbindFromRenderStep(moveBinding)
        humanoid:Move(Vector3.zero, false)
        if appliedSpeed ~= nil and humanoid.WalkSpeed == appliedSpeed then
            humanoid.WalkSpeed = restoreSpeed
        end
        if not ok then error(err, 0) end
        return arrived
    end

    function Extra.teleportTo(targetPosition, stopDistance, extraCheck, timeout)
        stopDistance = tonumber(stopDistance) or 3
        if not autoFarmActive then return false end
        local _, humanoid, hrp = Extra.getCharacter()
        if not hrp.Parent or humanoid.Health <= 0 then return false end
        if type(extraCheck) == "function" and extraCheck() then return true end

        humanoid:Move(Vector3.zero, false)
        local finalPosition = Vector3.new(targetPosition.X, hrp.Position.Y, targetPosition.Z)
        local direction = finalPosition - hrp.Position
        if direction.Magnitude > stopDistance then
            local look = direction.Magnitude > 0.01 and direction.Unit
                or Vector3.new(0, 0, -1)
            -- Teleport is one position change, with no speed-based stepping.
            hrp.CFrame = CFrame.lookAt(finalPosition, finalPosition + look)
        end
        hrp.AssemblyLinearVelocity = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero
        return (hrp.Position - finalPosition).Magnitude <= stopDistance
    end

    function Extra.tweenTo(targetPosition, stopDistance, timeout, extraCheck)
        stopDistance = tonumber(stopDistance) or 3
        timeout = tonumber(timeout) or 30

        local _, humanoid, hrp = Extra.getCharacter()

        humanoid:Move(Vector3.zero, false)

        local distance = (hrp.Position - targetPosition).Magnitude

        if distance <= stopDistance then
            return true
        end

        local syncedSpeed = Extra.getCurrentMoveSpeed()
        local travelSpeed = math.max(
            syncedSpeed * TWEEN_SPEED_MULTIPLIER,
            TWEEN_MIN_SPEED
        )

        local duration =
            math.max(
                0.05,
                distance / travelSpeed
            )

        duration =
            math.min(
                duration,
                timeout
            )

        Extra.log(
            "Tween travel speed",
            "| WalkSpeed:", syncedSpeed,
            "| TravelSpeed:", travelSpeed,
            "| Distance:", distance,
            "| Duration:", duration
        )

        local lookVector = hrp.CFrame.LookVector

        local targetCFrame = CFrame.lookAt(
            targetPosition,
            targetPosition + lookVector
        )

        hrp.AssemblyLinearVelocity = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero

        local tween = TweenService:Create(
            hrp,
            TweenInfo.new(
                duration,
                Enum.EasingStyle.Linear,
                Enum.EasingDirection.Out
            ),
            {
                CFrame = targetCFrame
            }
        )

        tween:Play()

        local deadline = os.clock() + timeout

        while autoFarmActive
            and hrp.Parent
            and humanoid.Health > 0
            and os.clock() < deadline
        do
            if type(extraCheck) == "function" and extraCheck() then
                tween:Cancel()
                return true
            end

            if (hrp.Position - targetPosition).Magnitude <= stopDistance then
                tween:Cancel()

                hrp.AssemblyLinearVelocity = Vector3.zero
                hrp.AssemblyAngularVelocity = Vector3.zero

                return true
            end

            if tween.PlaybackState == Enum.PlaybackState.Completed then
                break
            end

            task.wait(0.03)
        end

        if tween.PlaybackState == Enum.PlaybackState.Playing then
            tween:Cancel()
        end

        hrp.AssemblyLinearVelocity = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero

        if type(extraCheck) == "function" and extraCheck() then
            return true
        end

        return
            (hrp.Position - targetPosition).Magnitude
            <= stopDistance
    end

    function Extra.moveTo(targetPosition, stopDistance, timeout, extraCheck)
        Extra.log("Movement:", movementMode)

        if movementMode == "Teleport" then
            local _, _, hrp =
                Extra.getCharacter()

            local currentZone
            local targetZone

            if type(
                Extra.detectZoneAtPosition
            ) == "function"
            then
                currentZone =
                    Extra.detectZoneAtPosition(
                        hrp.Position
                    )

                targetZone =
                    Extra.detectZoneAtPosition(
                        targetPosition
                    )
            end

            -- Teleport mode is zone-based:
            -- only teleport when crossing into another zone.
            -- Once inside that zone, use normal walking between eggs/targets.
            if targetZone
                and currentZone
                and targetZone ~= currentZone
            then
                Extra.log(
                    "Zone teleport:",
                    currentZone,
                    "->",
                    targetZone
                )

                return Extra.teleportTo(
                    targetPosition,
                    stopDistance,
                    extraCheck,
                    timeout
                )
            end

            Extra.log(
                "Teleport mode local movement -> Walk",
                "| Zone:",
                targetZone
                    or currentZone
                    or "Unknown"
            )

            return Extra.walkTo(
                targetPosition,
                stopDistance,
                timeout,
                extraCheck
            )
        end

        if movementMode == "Tween" then
            return Extra.tweenTo(
                targetPosition,
                stopDistance,
                timeout,
                extraCheck
            )
        end

        return Extra.walkTo(
            targetPosition,
            stopDistance,
            timeout,
            extraCheck
        )
    end

    function Extra.getApproachPosition(targetPosition, desiredDistance)
        local _, _, hrp = Extra.getCharacter()

        local direction = hrp.Position - targetPosition
        direction = Vector3.new(direction.X, 0, direction.Z)

        if direction.Magnitude < 0.1 then
            direction = Vector3.new(0, 0, 1)
        else
            direction = direction.Unit
        end

        local result = targetPosition + direction * desiredDistance

        return Vector3.new(
            result.X,
            hrp.Position.Y,
            result.Z
        )
    end

    function Extra.walkNear(targetPosition, desiredDistance, timeout)
        local approachPosition = Extra.getApproachPosition(targetPosition, desiredDistance)
        return Extra.moveTo(approachPosition, 2, timeout)
    end

    function Extra.getMapSafeZonePart()
        local build =
            Workspace:
            FindFirstChild(
                "Build"
            )

        if not build then
            return nil
        end

        local zoneHitboxes =
            build:
            FindFirstChild(
                "ZoneHitboxes"
            )

        if not zoneHitboxes then
            return nil
        end

        local safeZone =
            zoneHitboxes:
            FindFirstChild(
                "SafeZone"
            )

        if safeZone
            and safeZone:IsA(
                "BasePart"
            )
        then
            return safeZone
        end

        return nil
    end

    function Extra.getHomeTargetPosition(
        fromPosition
    )
        local safeZone =
            Extra.getMapSafeZonePart()

        if not safeZone then
            return nil
        end

        -- Preserve current Y so movement stays horizontal and does not try to
        -- walk toward the SafeZone part's vertical center (107.5).
        return Vector3.new(
            safeZone.Position.X,
            fromPosition.Y,
            safeZone.Position.Z
        )
    end

    function Extra.walkHome(isBanked)
        local hitbox =
            Extra.getOwnedPlotHitbox()

        if not hitbox then
            warn(
                "[CHLISE HUB] Owned safe-zone hitbox not found."
            )
            return "failed"
        end

        local function bankedNow()
            return
                type(isBanked) == "function"
                and isBanked() == true
        end

        local function inOwnedPlot()
            local _, _, hrp =
                Extra.getCharacter()

            return
                SafeZoneQuery.
                IsPositionInOwnedPlot(
                    LocalPlayer.UserId,
                    hrp.Position
                )
        end

        local function interrupted()
            return
                bankedNow()
                or not Extra.isCarrying()
        end

        local _, _, hrp =
            Extra.getCharacter()

        local centerPosition =
            Extra.getHomeTargetPosition(
                hrp.Position
            )

        if not centerPosition then
            warn(
                "[CHLISE HUB] Workspace.Build.ZoneHitboxes.SafeZone not found."
            )

            return "failed"
        end

        -- If already inside the safe zone, stop immediately and let
        -- the normal bank event finish. Do not walk deeper into the plot.
        if inOwnedPlot() then
            Extra.stopMoving()
        else
            local reached = false

            if movementMode == "Tween" then
                reached =
                    Extra.tweenTo(
                        centerPosition,
                        2,
                        60,
                        interrupted
                    )

            elseif movementMode == "Teleport" then
                reached =
                    Extra.teleportTo(
                        centerPosition,
                        2,
                        interrupted,
                        60
                    )

            else
                -- Walk in one straight direction toward the fixed safe-zone target.
                -- No speed cap: keep the player's current/boosted WalkSpeed.
                reached =
                    Extra.walkTo(
                        centerPosition,
                        2,
                        60,
                        interrupted
                    )
            end

            if not reached
                and Extra.isCarrying()
                and not bankedNow()
                and not inOwnedPlot()
            then
                return "failed"
            end
        end

        local deadline =
            os.clock()
            + HOME_CONFIRM_TIMEOUT

        local carryMissingSince

        while autoFarmActive
            and os.clock() < deadline
        do
            if bankedNow() then
                Extra.stopMoving()
                return "banked"
            end

            local owned =
                inOwnedPlot()

            if not Extra.isCarrying() then
                Extra.stopMoving()

                if not owned then
                    return "dropped"
                end

                carryMissingSince =
                    carryMissingSince
                    or os.clock()

                if os.clock()
                    - carryMissingSince
                    >= BANK_GRACE_SECONDS
                then
                    return "dropped"
                end

            else
                carryMissingSince = nil

                if owned then
                    -- Already in the safe zone. Do not keep steering toward
                    -- the plot/center; stand still and wait for bank.
                    Extra.stopMoving()
                else
                    -- If knocked back out, simply head straight to the
                    -- safe-zone center again.
                    local _, _, currentHRP =
                        Extra.getCharacter()

                    local retryCenter =
                        Extra.getHomeTargetPosition(
                            currentHRP.Position
                        )

                    if not retryCenter then
                        return "failed"
                    end

                    Extra.walkTo(
                        retryCenter,
                        2,
                        math.min(
                            4,
                            math.max(
                                0.1,
                                deadline
                                    - os.clock()
                            )
                        ),
                        interrupted
                    )
                end
            end

            task.wait(
                HOME_RETRY_WAIT
            )
        end

        Extra.stopMoving()

        return
            bankedNow()
            and "banked"
            or "failed"
    end

    -- Pickaxe
    function Extra.ensurePickaxe()
        local character, humanoid = Extra.getCharacter()

        local equipped = character:FindFirstChild("Pickaxe")

        if equipped and equipped:IsA("Tool") then
            return equipped
        end

        local backpack = LocalPlayer:WaitForChild("Backpack")
        local pickaxe = backpack:FindFirstChild("Pickaxe")

        if not pickaxe or not pickaxe:IsA("Tool") then
            warn("[CHLISE HUB] Pickaxe not found.")
            return nil
        end

        humanoid:EquipTool(pickaxe)

        local deadline = os.clock() + 2

        while autoFarmActive and os.clock() < deadline do
            if pickaxe.Parent == character then
                Extra.log(
                    "Pickaxe equipped",
                    "| Tier:",
                    LocalPlayer:GetAttribute("PickaxeTier") or 1
                )
                return pickaxe
            end

            task.wait(0.02)
        end

        return nil
    end

    function Extra.usePickaxe()
        local pickaxe = Extra.ensurePickaxe()

        if not pickaxe then
            return false
        end

        pcall(function()
            pickaxe:Activate()
        end)

        task.wait(0.08)

        return true
    end

    -- Egg helpers
    function Extra.resolveEgg(container)
        if container:IsA("BasePart")
            and typeof(container:GetAttribute("Health")) == "number"
        then
            return container
        end

        local direct = container:FindFirstChild(ZonesConfig.EggName or "Egg")

        if direct
            and direct:IsA("BasePart")
            and typeof(direct:GetAttribute("Health")) == "number"
        then
            return direct
        end

        for _, object in ipairs(container:GetDescendants()) do
            if object:IsA("BasePart")
                and object.Name == (ZonesConfig.EggName or "Egg")
                and typeof(object:GetAttribute("Health")) == "number"
            then
                return object
            end
        end

        return nil
    end

    function Extra.getEggName(egg)
        local eggType = egg:GetAttribute("EggType")

        if typeof(eggType) == "string" and eggType ~= "" then
            return eggType
        end

        if egg.Parent then
            return egg.Parent.Name:gsub("^%d+:%s*", "")
        end

        return egg.Name
    end

    function Extra.validEgg(egg)
        if not egg or not egg.Parent then
            return false
        end

        local health = egg:GetAttribute("Health")

        return typeof(health) == "number"
            and health > 0
            and egg:GetAttribute("Hatching") ~= true
            and egg:GetAttribute("Broken") ~= true
    end

    function Extra.buildEggList()
        local result, found = {}, {}
        local function add(zoneName, raw)
            if type(raw) ~= "string" or found[raw] then return end
            found[raw] = true
            local label = "Zone " .. (zoneName:match("%d+") or zoneName)
                .. " • " .. Extra.displayName(raw)
            eggLabels[label] = raw
            table.insert(result, label)
        end
        for _, zoneName in ipairs(MASTER_ZONES) do
            local config = (EggRewards.ZoneEggs or {})[zoneName]
            for _, raw in ipairs(config and config.Eggs or {}) do add(zoneName, raw) end
            local zone = ZoneBuilds:FindFirstChild(zoneName)
            local eggs = zone and zone:FindFirstChild("Eggs")
            if eggs then
                for _, container in ipairs(eggs:GetChildren()) do
                    local egg = Extra.resolveEgg(container)
                    if egg then add(zoneName, Extra.getEggName(egg)) end
                end
            end
        end
        return result
    end

    local MASTER_EGGS = Extra.buildEggList()

    -- Titanic event state is replicated directly on Workspace.
    function Extra.normalizeEggKey(value)
        return tostring(value or "")
            :gsub("^%d+:%s*", "")
            :lower()
            :gsub("[^%w]", "")
    end

    function Extra.getTitanicState()
        local nextAt =
            tonumber(
                Workspace:GetAttribute(
                    "TitanicNextAt"
                )
            )

        local eggName =
            Workspace:GetAttribute(
                "TitanicEggName"
            )

        local zoneIndex =
            tonumber(
                Workspace:GetAttribute(
                    "TitanicZoneIndex"
                )
            )

        local endsAt =
            tonumber(
                Workspace:GetAttribute(
                    "TitanicEndsAt"
                )
            )

        local spawnId =
            Workspace:GetAttribute(
                "TitanicSpawnId"
            )

        local spawnByAdmin =
            Workspace:GetAttribute(
                "TitanicSpawnByAdmin"
            ) == true

        local now =
            Workspace:GetServerTimeNow()

        local active =
            type(eggName) == "string"
            and eggName ~= ""
            and zoneIndex ~= nil
            and endsAt ~= nil
            and endsAt > now

        return {
            Active = active,
            NextAt = nextAt,
            EggName = eggName,
            ZoneIndex = zoneIndex,
            EndsAt = endsAt,
            SpawnId = spawnId,
            SpawnByAdmin = spawnByAdmin,
            Now = now
        }
    end

    function Extra.isTitanicPriorityActive()
        if not prioritizeTitanicEgg then
            return false
        end

        local state =
            Extra.getTitanicState()

        return state.Active == true
    end

    function Extra.pendingIsFromTitanic(
        pending,
        state
    )
        if not pending
            or not state
            or not state.EggName
        then
            return false
        end

        return
            Extra.normalizeEggKey(
                pending.EggName
            )
            == Extra.normalizeEggKey(
                state.EggName
            )
    end

    function Extra.objectLooksTitanic(
        object
    )
        local current = object

        for _ = 1, 5 do
            if not current then
                break
            end

            local normalized =
                Extra.normalizeEggKey(
                    current.Name
                )

            if normalized:
                find(
                    "titanic",
                    1,
                    true
                )
            then
                return true
            end

            current =
                current.Parent
        end

        return false
    end

    function Extra.isTitanicEggObject(
        egg,
        state
    )
        if not egg then
            return false
        end

        -- Best signal: replicated event egg name.
        if state
            and type(state.EggName)
                == "string"
            and state.EggName ~= ""
        then
            if Extra.normalizeEggKey(
                Extra.getEggName(egg)
            ) == Extra.normalizeEggKey(
                state.EggName
            )
            then
                return true
            end
        end

        -- Fallback for game updates where Titanic workspace attributes are
        -- late/missing but the event egg is already physically spawned.
        if Extra.objectLooksTitanic(
            egg
        ) then
            return true
        end

        local eggName =
            Extra.normalizeEggKey(
                Extra.getEggName(egg)
            )

        return
            eggName:
            find(
                "titanic",
                1,
                true
            ) ~= nil
    end

    function Extra.registerTitanicCandidate(
        object
    )
        if not object
            or not object.Parent
        then
            return
        end

        local egg

        if object:IsA("BasePart")
            and typeof(
                object:GetAttribute(
                    "Health"
                )
            ) == "number"
        then
            egg = object
        elseif Extra.objectLooksTitanic(
            object
        ) then
            egg =
                Extra.resolveEgg(
                    object
                )

            if not egg
                and object.Parent
            then
                egg =
                    Extra.resolveEgg(
                        object.Parent
                    )
            end
        end

        if egg
            and egg:IsA("BasePart")
        then
            Extra.titanicCandidates[
                egg
            ] = true

            Extra.titanicDirty = true
        end
    end

    -- One initial chunked index, then only DescendantAdded updates.
    -- This catches Titanic eggs spawned outside ZoneBuilds without doing
    -- Workspace:GetDescendants() every scan.
    task.spawn(function()
        local descendants =
            Workspace:GetDescendants()

        for index, object
            in ipairs(descendants)
        do
            if object:IsA("BasePart")
                and (
                    typeof(
                        object:GetAttribute(
                            "Health"
                        )
                    ) == "number"
                    or Extra.objectLooksTitanic(
                        object
                    )
                )
            then
                Extra.registerTitanicCandidate(
                    object
                )
            end

            if index % 400 == 0 then
                task.wait()
            end
        end
    end)

    Workspace.DescendantAdded:
    Connect(function(object)
        task.defer(function()
            Extra.registerTitanicCandidate(
                object
            )
        end)

        -- Some event objects receive their attributes shortly after parenting.
        task.delay(
            0.25,
            function()
                if object
                    and object.Parent
                then
                    Extra.registerTitanicCandidate(
                        object
                    )
                end
            end
        )
    end)

    local lastTitanicScanAt = 0
    local cachedTitanicEgg = nil
    local cachedTitanicZone = nil
    local cachedTitanicDistance = nil
    local cachedTitanicState = nil

    function Extra.clearTitanicLock()
        Extra.titanicLockedEgg = nil
        Extra.titanicLockedZone = nil
        Extra.titanicLockedSpawnId = nil
        Extra.titanicLockedAt = 0
    end

    function Extra.getLockedTitanicEgg(
        excludedEgg
    )
        local egg =
            Extra.titanicLockedEgg

        if not egg
            or not egg.Parent
            or not Extra.validEgg(
                egg
            )
        then
            Extra.clearTitanicLock()
            return nil
        end

        local state =
            Extra.getTitanicState()

        if Extra.titanicIgnoredSpawnId ~= nil
            and state.SpawnId ~= nil
            and tostring(Extra.titanicIgnoredSpawnId)
                ~= tostring(state.SpawnId)
        then
            Extra.titanicIgnoredSpawnId = nil
            Extra.titanicIgnoredEgg = nil
        end

        if Extra.titanicIgnoredSpawnId ~= nil
            and state.SpawnId ~= nil
            and tostring(Extra.titanicIgnoredSpawnId)
                == tostring(state.SpawnId)
        then
            return nil
        end

        if Extra.titanicIgnoredEgg == egg
            and egg.Parent
        then
            return nil
        end

        if Extra.titanicLockedAt > 0
            and os.clock() - Extra.titanicLockedAt >= 20
        then
            Extra.log(
                "Titanic ignored: >20s without breaking",
                "| Egg:",
                Extra.getEggName(egg),
                "| SpawnId:",
                state.SpawnId
            )

            if state.SpawnId ~= nil then
                Extra.titanicIgnoredSpawnId = state.SpawnId
            else
                Extra.titanicIgnoredEgg = egg
            end

            Extra.clearTitanicLock()
            return nil
        end

        if Extra.titanicLockedSpawnId ~= nil
            and state.SpawnId ~= nil
            and tostring(
                Extra.titanicLockedSpawnId
            ) ~= tostring(
                state.SpawnId
            )
        then
            Extra.clearTitanicLock()
            return nil
        end

        if not Extra.isTitanicEggObject(
            egg,
            state
        )
        then
            Extra.clearTitanicLock()
            return nil
        end

        local _, _, hrp =
            Extra.getCharacter()

        local distance =
            (
                hrp.Position
                - egg.Position
            ).Magnitude

        return
            egg,
            Extra.titanicLockedZone
                or (
                    state.ZoneIndex
                    and (
                        "Zone"
                        .. tostring(
                            state.ZoneIndex
                        )
                    )
                )
                or "TitanicEvent",
            distance,
            state
    end

    function Extra.lockTitanicTarget(
        egg,
        zoneName,
        state
    )
        if not egg then
            return
        end

        if Extra.titanicLockedEgg ~= egg then
            Extra.titanicLockedAt = os.clock()
        end

        Extra.titanicLockedEgg =
            egg

        Extra.titanicLockedZone =
            zoneName

        Extra.titanicLockedSpawnId =
            state
            and state.SpawnId
            or nil

        Extra.log(
            "Titanic target locked:",
            Extra.getEggName(
                egg
            ),
            "| Zone:",
            zoneName,
            "| SpawnId:",
            Extra.titanicLockedSpawnId
        )
    end

    function Extra.findTitanicEgg(
        excludedEgg
    )
        if not prioritizeTitanicEgg then
            Extra.clearTitanicLock()
            return nil
        end

        local lockedEgg,
            lockedZone,
            lockedDistance,
            lockedState =
            Extra.getLockedTitanicEgg(
                excludedEgg
            )

        if lockedEgg then
            return
                lockedEgg,
                lockedZone,
                lockedDistance,
                lockedState
        end

        local stateNow =
            Extra.getTitanicState()

        if Extra.titanicIgnoredSpawnId ~= nil
            and stateNow.SpawnId ~= nil
            and tostring(Extra.titanicIgnoredSpawnId)
                == tostring(stateNow.SpawnId)
        then
            return nil
        end

        local nowClock =
            os.clock()

        -- Cache positive AND negative scans. Previously a missing target
        -- caused this function to rescan zones on every call.
        if not Extra.titanicDirty
            and nowClock
                - lastTitanicScanAt
                < 0.25
        then
            if cachedTitanicEgg
                and cachedTitanicEgg.Parent
                and cachedTitanicEgg
                    ~= excludedEgg
                and Extra.validEgg(
                    cachedTitanicEgg
                )
            then
                Extra.lockTitanicTarget(
                    cachedTitanicEgg,
                    cachedTitanicZone,
                    cachedTitanicState
                )

                return
                    cachedTitanicEgg,
                    cachedTitanicZone,
                    cachedTitanicDistance,
                    cachedTitanicState
            end

            return nil
        end

        Extra.titanicDirty = false
        lastTitanicScanAt =
            nowClock

        local state =
            Extra.getTitanicState()

        local _, _, hrp =
            Extra.getCharacter()

        local best
        local bestZone
        local bestDistance =
            math.huge

        local function inferZoneName(
            egg
        )
            local current =
                egg

            while current
                and current ~= Workspace
            do
                if current.Name:
                    match(
                        "^Zone%d+$"
                    )
                then
                    return current.Name
                end

                current =
                    current.Parent
            end

            if state.ZoneIndex then
                return
                    "Zone"
                    .. tostring(
                        state.ZoneIndex
                    )
            end

            return "TitanicEvent"
        end

        local function consider(
            egg
        )
            if not egg
                or egg == excludedEgg
                or not Extra.validEgg(
                    egg
                )
                or not Extra.isTitanicEggObject(
                    egg,
                    state
                )
            then
                return
            end

            local distance =
                (
                    hrp.Position
                    - egg.Position
                ).Magnitude

            if distance
                < bestDistance
            then
                best = egg
                bestDistance =
                    distance
                bestZone =
                    inferZoneName(
                        egg
                    )
            end
        end

        -- 1) Fast path: use the zone supplied by Titanic state when available.
        if state.ZoneIndex then
            local zoneName =
                "Zone"
                .. tostring(
                    state.ZoneIndex
                )

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
                for _, container
                    in ipairs(
                        eggs:GetChildren()
                    )
                do
                    consider(
                        Extra.resolveEgg(
                            container
                        )
                    )
                end
            end
        end

        -- 2) Scan every normal egg container. This catches a Titanic egg even
        -- when TitanicZoneIndex is stale or nil.
        if not best then
            for _, zone
                in ipairs(
                    ZoneBuilds:
                    GetChildren()
                )
            do
                local eggs =
                    zone:
                    FindFirstChild(
                        "Eggs"
                    )

                if eggs then
                    for _, container
                        in ipairs(
                            eggs:GetChildren()
                        )
                    do
                        consider(
                            Extra.resolveEgg(
                                container
                            )
                        )
                    end
                end
            end
        end

        -- 3) Event-driven physical registry. This catches event eggs placed
        -- elsewhere in Workspace while avoiding repeated full-world scans.
        if not best then
            for egg
                in pairs(
                    Extra.titanicCandidates
                )
            do
                if not egg
                    or not egg.Parent
                then
                    Extra.titanicCandidates[
                        egg
                    ] = nil
                else
                    consider(egg)
                end
            end
        end

        cachedTitanicEgg = best
        cachedTitanicZone = bestZone
        cachedTitanicDistance =
            best and bestDistance
            or nil
        cachedTitanicState = state

        if best
            and Extra.titanicIgnoredEgg ~= best
        then
            Extra.lockTitanicTarget(
                best,
                bestZone,
                state
            )

            return
                best,
                bestZone,
                bestDistance,
                state
        end

        Extra.clearTitanicLock()
        return nil
    end

    function Extra.getEggPriority(egg, zoneName)
        local eggName = Extra.getEggName(egg)
        local zoneInfo = ZonesConfig.Get(zoneName)
        local rarity = egg:GetAttribute("Rarity")
        local rank = EggRarity.IndexOf(rarity)
        if not rank then
            rarity = EggRarity.Resolve(eggName, zoneInfo)
            rank = EggRarity.IndexOf(rarity) or 0
        end
        local _, tier = EggRarity.LadderSpot(eggName)
        return rank, tonumber(tier) or 0
    end

    function Extra.zoneIndex(
        zoneName
    )
        local wanted =
            tostring(zoneName or "")

        for index, name
            in ipairs(
                MASTER_ZONES
            )
        do
            if name == wanted then
                return index
            end
        end

        return nil
    end

    function Extra.getZonePosition(
        zoneName
    )
        local zone =
            ZoneBuilds:
            FindFirstChild(
                zoneName
            )

        if not zone then
            return nil
        end

        if zone:IsA(
            "BasePart"
        ) then
            return zone.Position
        end

        if zone:IsA(
            "Model"
        ) then
            local ok,
                pivot =
                pcall(function()
                    return zone:GetPivot()
                end)

            if ok and pivot then
                return pivot.Position
            end
        end

        local part =
            zone:
            FindFirstChildWhichIsA(
                "BasePart",
                true
            )

        return
            part
            and part.Position
            or nil
    end

    function Extra.readZoneSpeedRequirement(
        zoneName
    )
        local info =
            ZonesConfig.Get(
                zoneName
            )

        local keys = {
            "RequiredSpeed",
            "SpeedRequirement",
            "MinSpeed",
            "MinimumSpeed",
            "UnlockSpeed",
            "RequiredWalkSpeed",
            "WalkSpeed"
        }

        local function inspect(
            value
        )
            if type(value)
                ~= "table"
            then
                return nil
            end

            for _, key
                in ipairs(keys)
            do
                local found =
                    tonumber(
                        value[key]
                    )

                if found then
                    return found
                end
            end

            for _, key
                in ipairs({
                    "Requirement",
                    "Requirements",
                    "Unlock",
                    "Gate"
                })
            do
                local nested =
                    value[key]

                if type(nested)
                    == "table"
                then
                    local found =
                        inspect(nested)

                    if found then
                        return found
                    end
                end
            end

            return nil
        end

        local fromConfig =
            inspect(info)

        if fromConfig then
            return fromConfig
        end

        local zone =
            ZoneBuilds:
            FindFirstChild(
                zoneName
            )

        if zone then
            for _, key
                in ipairs(keys)
            do
                local found =
                    tonumber(
                        zone:GetAttribute(
                            key
                        )
                    )

                if found then
                    return found
                end
            end
        end

        return nil
    end

    function Extra.getProgressionSpeed()
        local speed =
            Extra.getCurrentMoveSpeed()

        for _, key
            in ipairs({
                "Speed",
                "WalkSpeed",
                "MovementSpeed"
            })
        do
            speed =
                math.max(
                    speed,
                    tonumber(
                        LocalPlayer:
                        GetAttribute(
                            key
                        )
                    )
                    or 0
                )
        end

        return speed
    end

    function Extra.speedAllowsZone(
        zoneName
    )
        local requirement =
            Extra.readZoneSpeedRequirement(
                zoneName
            )

        if not requirement then
            -- Never guess an unknown gate requirement.
            return false, nil
        end

        local speed =
            Extra.getProgressionSpeed()

        return
            speed >= requirement,
            requirement
    end

    function Extra.detectZoneAtPosition(
        position
    )
        if typeof(position)
            ~= "Vector3"
        then
            return nil
        end

        local containingZone
        local containingDistance =
            math.huge

        local nearestZone
        local nearestDistance =
            math.huge

        for _, zoneName
            in ipairs(
                MASTER_ZONES
            )
        do
            local zone =
                ZoneBuilds:
                FindFirstChild(
                    zoneName
                )

            if zone then
                local center
                local size

                if zone:IsA("BasePart") then
                    center =
                        zone.CFrame
                    size =
                        zone.Size

                elseif zone:IsA("Model") then
                    local ok,
                        cf,
                        modelSize =
                        pcall(function()
                            return
                                zone:
                                GetBoundingBox()
                        end)

                    if ok then
                        center =
                            cf
                        size =
                            modelSize
                    end
                end

                if center
                    and size
                then
                    local localPoint =
                        center:
                        PointToObjectSpace(
                            position
                        )

                    local half =
                        size * 0.5

                    local inside =
                        math.abs(
                            localPoint.X
                        ) <= half.X
                        and math.abs(
                            localPoint.Z
                        ) <= half.Z

                    local distance =
                        (
                            position
                            - center.Position
                        ).Magnitude

                    if inside
                        and distance
                            < containingDistance
                    then
                        containingZone =
                            zoneName
                        containingDistance =
                            distance
                    end

                    if distance
                        < nearestDistance
                    then
                        nearestZone =
                            zoneName
                        nearestDistance =
                            distance
                    end
                else
                    local zonePosition =
                        Extra.getZonePosition(
                            zoneName
                        )

                    if zonePosition then
                        local distance =
                            (
                                position
                                - zonePosition
                            ).Magnitude

                        if distance
                            < nearestDistance
                        then
                            nearestZone =
                                zoneName
                            nearestDistance =
                                distance
                        end
                    end
                end
            end
        end

        return
            containingZone
            or nearestZone
    end

    function Extra.detectCurrentZone()
        local _, _, hrp =
            Extra.getCharacter()

        if not hrp then
            return nil
        end

        return
            Extra.detectZoneAtPosition(
                hrp.Position
            )
    end

    function Extra.getSelectedCurrentZone()
        if Extra.selectionEmpty(
            selectedZones
        ) then
            return nil
        end

        local selected =
            {}

        for _, zoneName
            in ipairs(
                MASTER_ZONES
            )
        do
            if Extra.isSelected(
                selectedZones,
                zoneName
            )
            then
                table.insert(
                    selected,
                    zoneName
                )
            end
        end

        if #selected == 1 then
            return selected[1]
        end

        if #selected > 1 then
            local _, _, hrp =
                Extra.getCharacter()

            local best
            local bestDistance =
                math.huge

            for _, zoneName
                in ipairs(
                    selected
                )
            do
                local position =
                    Extra.getZonePosition(
                        zoneName
                    )

                if position then
                    local distance =
                        (
                            hrp.Position
                            - position
                        ).Magnitude

                    if distance
                        < bestDistance
                    then
                        best =
                            zoneName
                        bestDistance =
                            distance
                    end
                end
            end

            return
                best
                or selected[1]
        end

        return nil
    end

    function Extra.initializeAutoNextZone()
        if Extra.autoNextZoneSafeZone
            and Extra.zoneIndex(
                Extra.autoNextZoneSafeZone
            )
        then
            return
        end

        local selectedZone =
            Extra.getSelectedCurrentZone()

        local detectedZone =
            Extra.detectCurrentZone()

        Extra.autoNextZoneSafeZone =
            selectedZone
            or detectedZone
            or MASTER_ZONES[1]

        Extra.autoNextZoneTrialZone =
            nil
        Extra.autoNextZoneTrialHits =
            0
        Extra.autoNextZonePromotedPickaxeTier =
            nil

        Extra.log(
            "Auto Next Zone base:",
            Extra.autoNextZoneSafeZone,
            "| Selected:",
            selectedZone
                or "None",
            "| Detected:",
            detectedZone
                or "Unknown"
        )
    end

    function Extra.getAutoNextZoneTarget()
        if not Extra.autoNextZoneEnabled then
            return nil
        end

        Extra.initializeAutoNextZone()

        local safe =
            Extra.autoNextZoneSafeZone

        local safeIndex =
            Extra.zoneIndex(
                safe
            )
            or 1

        local blocked =
            Extra.autoNextZoneBlockedZone

        local currentPickaxeTier =
            tonumber(
                LocalPlayer:
                    GetAttribute(
                        "PickaxeTier"
                    )
            )
            or 1

        local promotedTier =
            tonumber(
                Extra.autoNextZonePromotedPickaxeTier
            )

        if promotedTier
            and currentPickaxeTier
                <= promotedTier
        then
            return safe
        end

        if promotedTier
            and currentPickaxeTier
                > promotedTier
        then
            Extra.autoNextZonePromotedPickaxeTier =
                nil
        end

        local expectedNextZone =
            MASTER_ZONES[
                safeIndex + 1
            ]

        if blocked
            and blocked
                ~= expectedNextZone
        then
            Extra.log(
                "Auto Next Zone stale block cleared:",
                blocked,
                "| Expected:",
                expectedNextZone
            )

            Extra.autoNextZoneBlockedZone =
                nil
            Extra.autoNextZoneBlockedPickaxeTier =
                nil
            Extra.autoNextZoneTrialZone =
                nil
            Extra.autoNextZoneTrialHits =
                0

            blocked = nil
        end

        if blocked then
            local currentTier =
                tonumber(
                    LocalPlayer:
                    GetAttribute(
                        "PickaxeTier"
                    )
                )
                or 1

            local blockedTier =
                tonumber(
                    Extra.autoNextZoneBlockedPickaxeTier
                )
                or currentTier

            if currentTier
                > blockedTier
            then
                local allowed =
                    Extra.speedAllowsZone(
                        blocked
                    )

                if allowed then
                    Extra.log(
                        "Auto Next Zone retry after pickaxe upgrade:",
                        blocked,
                        "| Pickaxe:",
                        blockedTier,
                        "->",
                        currentTier,
                        "| Speed:",
                        Extra.getProgressionSpeed()
                    )

                    Extra.autoNextZoneBlockedZone =
                        nil
                    Extra.autoNextZoneBlockedPickaxeTier =
                        nil
                    Extra.autoNextZoneTrialZone =
                        blocked
                    Extra.autoNextZoneTrialHits =
                        0

                    return blocked
                end

                Extra.log(
                    "Auto Next Zone still locked after pickaxe upgrade:",
                    blocked,
                    "| Speed requirement not met"
                )
            end

            return safe
        end

        local nextZone =
            expectedNextZone

        if not nextZone then
            return safe
        end

        local allowed,
            requirement =
            Extra.speedAllowsZone(
                nextZone
            )

        if allowed then
            Extra.autoNextZoneTrialZone =
                nextZone

            Extra.autoNextZoneTrialHits =
                0

            Extra.log(
                "Auto Next Zone trial:",
                nextZone,
                "| Speed:",
                Extra.getProgressionSpeed(),
                "| Required:",
                requirement
                    or "Unknown"
            )

            return nextZone
        end

        Extra.autoNextZoneTrialZone =
            nil

        return safe
    end

    function Extra.markAutoNextZoneTooSlow(
        zoneName
    )
        if not Extra.autoNextZoneEnabled
            or zoneName
                ~= Extra.autoNextZoneTrialZone
        then
            return
        end

        Extra.autoNextZoneBlockedZone =
            zoneName

        Extra.autoNextZoneBlockedPickaxeTier =
            tonumber(
                LocalPlayer:
                GetAttribute(
                    "PickaxeTier"
                )
            )
            or 1

        Extra.autoNextZoneTrialZone =
            nil

        Extra.autoNextZoneTrialHits =
            0

        Extra.log(
            "Auto Next Zone fallback:",
            zoneName,
            "survived 15 hits.",
            "Back to:",
            Extra.autoNextZoneSafeZone,
            "| Waiting PickaxeTier >",
            Extra.autoNextZoneBlockedPickaxeTier
        )
    end

    function Extra.markAutoNextZoneSuccess(
        zoneName
    )
        if not Extra.autoNextZoneEnabled
            or zoneName
                ~= Extra.autoNextZoneTrialZone
        then
            return
        end

        local safeIndex =
            Extra.zoneIndex(
                Extra.autoNextZoneSafeZone
            )

        local zoneIndex =
            Extra.zoneIndex(
                zoneName
            )

        if not safeIndex
            or not zoneIndex
            or zoneIndex
                ~= safeIndex + 1
        then
            Extra.log(
                "Auto Next Zone promotion rejected:",
                zoneName,
                "| Safe:",
                Extra.autoNextZoneSafeZone
            )

            Extra.autoNextZoneTrialZone =
                nil
            Extra.autoNextZoneTrialHits =
                0

            return
        end

        Extra.autoNextZoneSafeZone =
            zoneName

        Extra.autoNextZonePromotedPickaxeTier =
            tonumber(
                LocalPlayer:
                    GetAttribute(
                        "PickaxeTier"
                    )
            )
            or 1

        Extra.autoNextZoneTrialZone =
            nil
        Extra.autoNextZoneTrialHits =
            0
        Extra.autoNextZoneBlockedZone =
            nil
        Extra.autoNextZoneBlockedPickaxeTier =
            nil

        Extra.log(
            "Auto Next Zone promoted:",
            zoneName
        )
    end

    function Extra.findBestEggInZone(
        zoneName,
        excludedEgg
    )
        if not zoneName then
            return nil
        end

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

        if not eggs then
            return nil
        end

        local _, _, hrp =
            Extra.getCharacter()

        local bestEgg
        local bestDistance =
            math.huge
        local bestRarity =
            -1
        local bestTier =
            -1

        for _, container
            in ipairs(
                eggs:GetChildren()
            )
        do
            local egg =
                Extra.resolveEgg(
                    container
                )

            if egg ~= excludedEgg
                and Extra.validEgg(
                    egg
                )
            then
                local eggName =
                    Extra.getEggName(
                        egg
                    )

                if Extra.isSelected(
                    selectedEggs,
                    eggName
                )
                then
                    local distance =
                        (
                            hrp.Position
                            - egg.Position
                        ).Magnitude

                    local rarity,
                        tier =
                        Extra.getEggPriority(
                            egg,
                            zoneName
                        )

                    if rarity
                            > bestRarity
                        or (
                            rarity
                                == bestRarity
                            and tier
                                > bestTier
                        )
                        or (
                            rarity
                                == bestRarity
                            and tier
                                == bestTier
                            and distance
                                < bestDistance
                        )
                    then
                        bestEgg =
                            egg
                        bestDistance =
                            distance
                        bestRarity =
                            rarity
                        bestTier =
                            tier
                    end
                end
            end
        end

        return
            bestEgg,
            zoneName,
            bestDistance
    end

    function Extra.findBestEgg(excludedEgg)
        local titanicEgg,
            titanicZone,
            titanicDistance =
            Extra.findTitanicEgg(
                excludedEgg
            )

        if titanicEgg then
            Extra.log(
                "Titanic priority target:",
                Extra.getEggName(
                    titanicEgg
                ),
                "| Zone:",
                titanicZone,
                "| Distance:",
                string.format(
                    "%.2f",
                    titanicDistance
                )
            )

            return
                titanicEgg,
                titanicZone,
                titanicDistance
        end

        -- Auto Next Zone behavior:
        -- 1) Prefer the current safe zone while it still has a selected egg.
        -- 2) Only when that zone is temporarily empty, try the next eligible zone.
        -- 3) The existing 15-hit trial still decides whether that next zone is
        --    actually strong enough to promote, or whether we fall back.
        if Extra.autoNextZoneEnabled then
            Extra.initializeAutoNextZone()

            local safeZone =
                Extra.autoNextZoneSafeZone

            local safeEgg,
                safeName,
                safeDistance =
                Extra.findBestEggInZone(
                    safeZone,
                    excludedEgg
                )

            if safeEgg then
                return
                    safeEgg,
                    safeName,
                    safeDistance
            end

            local fallbackZone =
                Extra.getAutoNextZoneTarget()

            if fallbackZone
                and fallbackZone
                    ~= safeZone
            then
                local nextEgg,
                    nextName,
                    nextDistance =
                    Extra.findBestEggInZone(
                        fallbackZone,
                        excludedEgg
                    )

                if nextEgg then
                    Extra.log(
                        "Current zone empty -> temporary next zone:",
                        safeZone,
                        "->",
                        fallbackZone
                    )

                    return
                        nextEgg,
                        nextName,
                        nextDistance
                end
            end

            -- If the next zone has no usable egg either, remain logically on
            -- the safe zone and wait for its eggs to respawn.
            return nil
        end

        local _, _, hrp =
            Extra.getCharacter()

        local bestEgg
        local bestZone
        local bestDistance =
            math.huge
        local bestRarity,
            bestTier =
            -1,
            -1

        for _, zoneName
            in ipairs(
                MASTER_ZONES
            )
        do
            if Extra.isSelected(
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
                    for _, container
                        in ipairs(
                            eggs:GetChildren()
                        )
                    do
                        local egg =
                            Extra.resolveEgg(
                                container
                            )

                        if egg ~= excludedEgg
                            and Extra.validEgg(
                                egg
                            )
                        then
                            local eggName =
                                Extra.getEggName(
                                    egg
                                )

                            if Extra.isSelected(
                                selectedEggs,
                                eggName
                            )
                            then
                                local distance =
                                    (
                                        hrp.Position
                                        - egg.Position
                                    ).Magnitude

                                local rarity,
                                    tier =
                                    Extra.getEggPriority(
                                        egg,
                                        zoneName
                                    )

                                if rarity
                                        > bestRarity
                                    or (
                                        rarity
                                            == bestRarity
                                        and tier
                                            > bestTier
                                    )
                                    or (
                                        rarity
                                            == bestRarity
                                        and tier
                                            == bestTier
                                        and distance
                                            < bestDistance
                                    )
                                then
                                    bestEgg =
                                        egg
                                    bestZone =
                                        zoneName
                                    bestDistance =
                                        distance
                                    bestRarity =
                                        rarity
                                    bestTier =
                                        tier
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

    -- Result pet
    function Extra.snapshotPickups()
        local snapshot = {}

        for _, animal in ipairs(Pickups:GetChildren()) do
            snapshot[animal] = true
        end

        return snapshot
    end

    local PET_INCOME_ATTRIBUTE_KEYS = {
        "IncomePerSecond",
        "CashPerSecond",
        "Income",
        "CashPerSec",
        "CPS",
        "EarningsPerSecond",
        "MoneyPerSecond"
    }

    function Extra.parseCompactNumber(value)
        local raw =
            tostring(value or "")
            :lower()
            :gsub("%s+", "")
            :gsub(",", ".")

        if raw == "" then
            return nil
        end

        local numberPart,
            suffix =
            raw:match(
                "^([%+%-]?[%d%.]+)([%a]*)$"
            )

        local number =
            tonumber(
                numberPart
                or raw
            )

        if not number then
            return nil
        end

        local multipliers = {
            k = 1e3,
            m = 1e6,
            b = 1e9,
            t = 1e12,
            qa = 1e15,
            qi = 1e18,
            sx = 1e21,
            sp = 1e24,
            oc = 1e27,
            no = 1e30,
            dc = 1e33
        }

        if suffix
            and suffix ~= ""
        then
            local multiplier =
                multipliers[
                    suffix
                ]

            if not multiplier then
                return nil
            end

            number *= multiplier
        end

        return number
    end

    function Extra.formatCompactNumber(
        value
    )
        local number =
            tonumber(value)
            or 0

        if number == 0 then
            return "0"
        end

        local absolute =
            math.abs(number)

        local suffixes = {
            {1e33, "Dc"},
            {1e30, "No"},
            {1e27, "Oc"},
            {1e24, "Sp"},
            {1e21, "Sx"},
            {1e18, "Qi"},
            {1e15, "Qa"},
            {1e12, "T"},
            {1e9, "B"},
            {1e6, "M"},
            {1e3, "K"}
        }

        for _, entry
            in ipairs(
                suffixes
            )
        do
            local divisor =
                entry[1]

            if absolute >= divisor then
                local scaled =
                    number / divisor

                local decimals

                if math.abs(scaled)
                    >= 100
                then
                    decimals = 0
                elseif math.abs(scaled)
                    >= 10
                then
                    decimals = 1
                else
                    decimals = 2
                end

                local formatted =
                    string.format(
                        "%."
                        .. tostring(decimals)
                        .. "f",
                        scaled
                    )

                formatted =
                    formatted:
                    gsub(
                        "%.?0+$",
                        ""
                    )

                return
                    formatted
                    .. entry[2]
            end
        end

        if number
            == math.floor(number)
        then
            return tostring(
                math.floor(number)
            )
        end

        local formatted =
            string.format(
                "%.2f",
                number
            )

        return formatted:
            gsub(
                "%.?0+$",
                ""
            )
    end

    function Extra.formatFullNumber(
        value
    )
        local number =
            tonumber(value)
            or 0

        if number
            == math.floor(number)
        then
            return string.format(
                "%.0f",
                number
            )
        end

        local formatted =
            string.format(
                "%.6f",
                number
            )

        return formatted:
            gsub(
                "%.?0+$",
                ""
            )
    end

    function Extra.findTextboxByLabel(
        labelText
    )
        local roots = {
            game:GetService(
                "CoreGui"
            ),
            LocalPlayer:
            FindFirstChildOfClass(
                "PlayerGui"
            )
        }

        for _, root
            in ipairs(
                roots
            )
        do
            if root then
                for _, object
                    in ipairs(
                        root:GetDescendants()
                    )
                do
                    if object:IsA(
                        "TextBox"
                    )
                    then
                        local ancestor =
                            object.Parent

                        for _ = 1, 7 do
                            if not ancestor then
                                break
                            end

                            local foundLabel =
                                false

                            for _, sibling
                                in ipairs(
                                    ancestor:
                                    GetDescendants()
                                )
                            do
                                if (
                                    sibling:IsA(
                                        "TextLabel"
                                    )
                                    or sibling:IsA(
                                        "TextButton"
                                    )
                                )
                                    and sibling.Text
                                        == labelText
                                then
                                    foundLabel =
                                        true
                                    break
                                end
                            end

                            if foundLabel then
                                return object
                            end

                            ancestor =
                                ancestor.Parent
                        end
                    end
                end
            end
        end

        return nil
    end

    function Extra.bindCompactIncomeTextbox(
        labelText,
        valueGetter
    )
        task.spawn(function()
            local textBox

            for _ = 1, 80 do
                if Window.Destroyed then
                    return
                end

                textBox =
                    Extra.findTextboxByLabel(
                        labelText
                    )

                if textBox then
                    break
                end

                task.wait(0.1)
            end

            if not textBox then
                Extra.log(
                    "Income textbox bind failed:",
                    labelText
                )
                return
            end

            pcall(function()
                textBox.ClearTextOnFocus =
                    false
            end)

            local function showCompact()
                if not textBox
                    or not textBox.Parent
                then
                    return
                end

                local value =
                    tonumber(
                        valueGetter()
                    )
                    or 0

                textBox.Text =
                    Extra.formatCompactNumber(
                        value
                    )
            end

            local function showFull()
                if not textBox
                    or not textBox.Parent
                then
                    return
                end

                local value =
                    tonumber(
                        valueGetter()
                    )
                    or 0

                textBox.Text =
                    Extra.formatFullNumber(
                        value
                    )

                pcall(function()
                    textBox.CursorPosition =
                        #textBox.Text + 1
                end)
            end

            showCompact()

            textBox.Focused:
            Connect(function()
                task.defer(
                    showFull
                )
            end)

            textBox.FocusLost:
            Connect(function()
                task.defer(
                    showCompact
                )
            end)

            Extra.log(
                "Income textbox compact display bound:",
                labelText
            )
        end)
    end

    function Extra.parseIncomeText(
        value
    )
        local raw =
            tostring(value or "")
            :lower()

        if raw == "" then
            return nil
        end

        -- Typical game text examples:
        -- "$2.5B/s", "2.5B / sec", "Income: 750M/s", "1,200,000/s"
        -- Prefer numbers close to /s or per-second wording.
        local compact =
            raw:match(
                "([%d%.,]+%s*[kmbt]%a*)%s*/%s*s"
            )
            or raw:match(
                "([%d%.,]+%s*[kmbt]%a*)%s*per%s*sec"
            )
            or raw:match(
                "([%d%.,]+%s*[kmbt]%a*)%s*per%s*second"
            )

        if compact then
            compact =
                compact:
                gsub("%s+", "")

            return
                Extra.parseCompactNumber(
                    compact
                )
        end

        local plain =
            raw:match(
                "([%d%.,]+)%s*/%s*s"
            )
            or raw:match(
                "([%d%.,]+)%s*per%s*sec"
            )
            or raw:match(
                "([%d%.,]+)%s*per%s*second"
            )

        if plain then
            -- Handle thousands separators conservatively.
            local normalized =
                plain:
                gsub("%s+", "")

            if normalized:find(",", 1, true)
                and normalized:find(".", 1, true)
            then
                normalized =
                    normalized:
                    gsub(",", "")
            elseif normalized:match(
                "^%d+,%d%d%d,"
            ) then
                normalized =
                    normalized:
                    gsub(",", "")
            elseif normalized:match(
                "^%d+,%d%d%d$"
            ) then
                normalized =
                    normalized:
                    gsub(",", "")
            else
                normalized =
                    normalized:
                    gsub(",", ".")
            end

            return
                tonumber(normalized)
        end

        return nil
    end

    function Extra.readIncomeFromTable(
        value
    )
        if type(value)
            ~= "table"
        then
            return nil
        end

        for _, key
            in ipairs(
                PET_INCOME_ATTRIBUTE_KEYS
            )
        do
            local parsed =
                tonumber(
                    value[key]
                )

            if parsed then
                return parsed
            end
        end

        return nil
    end

    function Extra.getPetIncomePerSecond(
        animal
    )
        if not animal then
            return nil
        end

        local direct =
            Extra.readIncomeFromInstance(
                animal
            )

        if direct ~= nil then
            return direct
        end

        -- For live world pickups, calculate the exact income from the same
        -- EggRewards function used by the game's value logic. This lets us
        -- evaluate pets that were already in Workspace.AnimalPickups, including
        -- pets dropped from eggs broken by OTHER players.
        if animal.Parent == Pickups
            and type(
                EggRewards.PlacedCashPerSecond
            ) == "function"
        then
            local animalName =
                animal:GetAttribute(
                    "AnimalName"
                )
                or animal.Name

            local weightKg =
                tonumber(
                    animal:GetAttribute(
                        "WeightKg"
                    )
                )

            local sizeMult =
                tonumber(
                    animal:GetAttribute(
                        "SizeMult"
                    )
                )

            if animalName
                and weightKg
                and sizeMult
            then
                local okIncome,
                    calculatedIncome =
                    pcall(
                        EggRewards.PlacedCashPerSecond,
                        animalName,
                        weightKg,
                        sizeMult
                    )

                calculatedIncome =
                    okIncome
                    and tonumber(
                        calculatedIncome
                    )
                    or nil

                if calculatedIncome then
                    Extra.log(
                        "World pet income:",
                        animalName,
                        "| Kg:",
                        weightKg,
                        "| Size:",
                        sizeMult,
                        "| Income/s:",
                        calculatedIncome,
                        "| Method: PlacedCashPerSecond"
                    )

                    return calculatedIncome
                end
            end

            -- If exact live-pickup data is incomplete while a minimum filter is
            -- active, do not fall back to base species cash and risk a false accept.
            if Extra.minimumPetIncome > 0 then
                return nil
            end
        end

        -- First prefer a replicated value on the actual hatch result.
        for _, key
            in ipairs(
                PET_INCOME_ATTRIBUTE_KEYS
            )
        do
            local value =
                tonumber(
                    animal:GetAttribute(
                        key
                    )
                )

            if value then
                return value
            end
        end

        -- Be tolerant to minor attribute naming changes.
        for key, value
            in pairs(
                animal:GetAttributes()
            )
        do
            if type(value)
                    == "number"
                and (
                    tostring(key):
                        lower():
                        find(
                            "income",
                            1,
                            true
                        )
                    or tostring(key):
                        lower():
                        find(
                            "cashper",
                            1,
                            true
                        )
                    or tostring(key):
                        lower()
                        == "cps"
                )
            then
                return value
            end
        end

        -- Fallback to EggRewards metadata/functions if this game version stores
        -- income there instead of on the pickup instance.
        local rawName =
            animal:GetAttribute(
                "AnimalName"
            )
            or animal.Name

        local function callRewardFunction(
            functionName
        )
            local fn =
                EggRewards[
                    functionName
                ]

            if type(fn)
                ~= "function"
            then
                return nil
            end

            local ok, result =
                pcall(
                    fn,
                    rawName
                )

            if ok then
                return
                    tonumber(result)
                    or Extra.readIncomeFromTable(
                        result
                    )
            end

            return nil
        end

        for _, functionName
            in ipairs({
                "IncomeOf",
                "IncomePerSecondOf",
                "CashPerSecondOf",
                "GetIncome",
                "GetIncomePerSecond",
                "GetCashPerSecond"
            })
        do
            local result =
                callRewardFunction(
                    functionName
                )

            if result then
                return result
            end
        end

        for _, tableName
            in ipairs({
                "Income",
                "Incomes",
                "IncomePerSecond",
                "CashPerSecond",
                "PetStats",
                "Animals"
            })
        do
            local source =
                EggRewards[
                    tableName
                ]

            if type(source)
                == "table"
            then
                local entry =
                    source[
                        rawName
                    ]

                local result =
                    tonumber(entry)
                    or Extra.readIncomeFromTable(
                        entry
                    )

                if result then
                    return result
                end
            end
        end

        for _, info
            in ipairs(
                EggRewards.Pool
                or {}
            )
        do
            if tostring(
                info.Name
                or ""
            ) == tostring(
                rawName
            )
            then
                local result =
                    Extra.readIncomeFromTable(
                        info
                    )

                if result then
                    return result
                end
            end
        end

        return nil
    end

    function Extra.readIncomeFromInstance(
        object
    )
        if not object then
            return nil
        end

        local function inspectAttributes(
            instance
        )
            for _, key
                in ipairs(
                    PET_INCOME_ATTRIBUTE_KEYS
                )
            do
                local raw =
                    instance:GetAttribute(
                        key
                    )

                local parsed =
                    tonumber(raw)
                    or Extra.parseCompactNumber(
                        raw
                    )

                if parsed then
                    return parsed
                end
            end

            for key, raw
                in pairs(
                    instance:GetAttributes()
                )
            do
                local lower =
                    tostring(key):
                    lower()

                if lower:find(
                        "income",
                        1,
                        true
                    )
                    or lower:find(
                        "cashper",
                        1,
                        true
                    )
                    or lower == "cps"
                    or lower:find(
                        "earning",
                        1,
                        true
                    )
                    or lower:find(
                        "moneyper",
                        1,
                        true
                    )
                then
                    local parsed =
                        tonumber(raw)
                        or Extra.parseCompactNumber(
                            raw
                        )

                    if parsed then
                        return parsed
                    end
                end
            end

            return nil
        end

        local rootIncome =
            inspectAttributes(
                object
            )

        if rootIncome ~= nil then
            return rootIncome
        end

        for _, descendant
            in ipairs(
                object:GetDescendants()
            )
        do
            local descendantIncome =
                inspectAttributes(
                    descendant
                )

            if descendantIncome ~= nil then
                return descendantIncome
            end

            if descendant:IsA(
                    "NumberValue"
                )
                or descendant:IsA(
                    "IntValue"
                )
                or descendant:IsA(
                    "StringValue"
                )
            then
                local lower =
                    descendant.Name:
                    lower()

                if lower:find(
                        "income",
                        1,
                        true
                    )
                    or lower:find(
                        "cashper",
                        1,
                        true
                    )
                    or lower == "cps"
                    or lower:find(
                        "earning",
                        1,
                        true
                    )
                    or lower:find(
                        "moneyper",
                        1,
                        true
                    )
                then
                    local parsed =
                        tonumber(
                            descendant.Value
                        )
                        or Extra.parseCompactNumber(
                            descendant.Value
                        )

                    if parsed then
                        return parsed
                    end
                end
            end

            if descendant:IsA(
                    "TextLabel"
                )
                or descendant:IsA(
                    "TextButton"
                )
                or descendant:IsA(
                    "TextBox"
                )
            then
                local parsed =
                    Extra.parseIncomeText(
                        descendant.Text
                    )

                if parsed then
                    return parsed
                end
            end
        end

        return nil
    end

    function Extra.waitForPetIncome(
        animal,
        timeout
    )
        local deadline =
            os.clock()
            + (
                tonumber(timeout)
                or 1.5
            )

        repeat
            local income =
                Extra.getPetIncomePerSecond(
                    animal
                )

            if income ~= nil then
                return income
            end

            task.wait(0.05)
        until not animal
            or not animal.Parent
            or os.clock()
                >= deadline

        return nil
    end

    function Extra.petMatchesFilter(
        animal,
        resolvedIncome
    )
        local rawName =
            animal:GetAttribute(
                "AnimalName"
            )
            or animal.Name

        if not Extra.isSelected(
            selectedPets,
            rawName
        )
        then
            return false
        end

        if Extra.minimumPetIncome <= 0 then
            return true
        end

        local income =
            resolvedIncome

        if income == nil then
            income =
                Extra.getPetIncomePerSecond(
                    animal
                )
        end

        return
            income ~= nil
            and income
                >= Extra.minimumPetIncome
    end

    function Extra.findGlobalAcceptedPickup()
        if not autoFarmActive
            or currentActivity ~= "Farm"
            or Extra.isCarrying()
            or Extra.isBeingChased()
        then
            return nil
        end

        local now =
            os.clock()

        if Extra.globalPickupCached
            and Extra.globalPickupCached.Parent
            and now
                - Extra.globalPickupScanAt
                < 0.15
        then
            return
                Extra.globalPickupCached
        end

        Extra.globalPickupScanAt =
            now
        Extra.globalPickupCached =
            nil

        local _, _, hrp =
            Extra.getCharacter()

        Extra.initializeAutoNextZone()

        local currentZone =
            Extra.autoNextZoneSafeZone
            or Extra.detectCurrentZone()

        local currentIndex =
            Extra.zoneIndex(
                currentZone
            )

        local maxPickupZone =
            currentIndex
            and MASTER_ZONES[
                currentIndex + 1
            ]
            or nil

        local maxPickupIndex =
            maxPickupZone
            and Extra.zoneIndex(
                maxPickupZone
            )
            or currentIndex

        local best
        local bestDistance =
            math.huge

        for _, animal
            in ipairs(
                Pickups:GetChildren()
            )
        do
            if animal:IsA("Model")
                and animal:GetAttribute(
                    "Hatched"
                ) == true
            then
                local position =
                    animal:GetPivot().Position

                local animalZone =
                    Extra.normalizeZone(
                        animal:GetAttribute(
                            "ZoneId"
                        )
                    )
                    or Extra.detectZoneAtPosition(
                        position
                    )

                local animalZoneIndex =
                    Extra.zoneIndex(
                        animalZone
                    )

                -- Global pickup scans ALL hatched pets currently present
                -- in Workspace.AnimalPickups, regardless of who broke the egg
                -- or when the pet spawned. Range is intentionally limited to:
                -- current safe zone + exactly one next zone.
                -- Never scan/collect from Zone +2 or farther.
                local withinPickupRange =
                    animalZoneIndex ~= nil
                    and currentIndex ~= nil
                    and animalZoneIndex
                        >= currentIndex
                    and animalZoneIndex
                        <= maxPickupIndex

                if withinPickupRange then
                    local zoneAllowed,
                        zoneRequirement =
                        Extra.speedAllowsZone(
                            animalZone
                        )

                    if zoneAllowed then
                        local rawName =
                            animal:GetAttribute(
                                "AnimalName"
                            )
                            or animal.Name

                        if Extra.isSelected(
                            selectedPets,
                            rawName
                        ) then
                            local income
                            local incomeAllowed =
                                Extra.minimumPetIncome
                                    <= 0

                            if Extra.minimumPetIncome > 0 then
                                income =
                                    Extra.getPetIncomePerSecond(
                                        animal
                                    )

                                incomeAllowed =
                                    income ~= nil
                                    and income
                                        >= Extra.minimumPetIncome
                            end

                            if incomeAllowed then
                                local distance =
                                    (
                                        position
                                        - hrp.Position
                                    ).Magnitude

                                if distance
                                    < bestDistance
                                then
                                    best =
                                        animal
                                    bestDistance =
                                        distance
                                end
                            end
                        end
                    else
                        Extra.log(
                            "Global pickup skipped by speed:",
                            animal:GetAttribute(
                                "AnimalName"
                            )
                                or animal.Name,
                            "| Zone:",
                            animalZone,
                            "| Speed:",
                            Extra.getProgressionSpeed(),
                            "| Required:",
                            zoneRequirement
                                or "Unknown"
                        )
                    end
                end
            end
        end

        Extra.globalPickupCached =
            best

        if best then
            local bestZone =
                Extra.normalizeZone(
                    best:GetAttribute(
                        "ZoneId"
                    )
                )
                or Extra.detectZoneAtPosition(
                    best:GetPivot().Position
                )

            Extra.log(
                "Global pickup candidate:",
                best:GetAttribute(
                    "AnimalName"
                )
                    or best.Name,
                "| Zone:",
                bestZone
                    or "Unknown",
                "| Allowed range:",
                currentZone
                    or "Unknown",
                "->",
                maxPickupZone
                    or currentZone
                    or "Unknown",
                "| Income/s:",
                Extra.getPetIncomePerSecond(
                    best
                )
                    or "N/A",
                "| Source: existing world pickup / any player egg"
            )
        end

        return best
    end

    -- Hatch pipeline
    --
    -- Important behavior:
    -- After Egg A breaks, the script does NOT stand still waiting for A to hatch.
    -- It immediately starts attacking Egg B while still watching A's result.
    -- If A hatches into an accepted pet, attacking B is interrupted immediately
    -- and the script returns to collect A.
    --
    -- Keep a small persistent pending queue so an Egg B that also breaks is not
    -- forgotten while Egg A is being collected/banked.
    -- No artificial pending limit:
    -- Egg A can hatch while B, C, D, ... keep getting broken.
    -- Every broken egg is tracked until its hatch result resolves or times out.
    local pendingHatches = {}

    function Extra.makePendingHatch(
        before,
        zoneName,
        eggPosition,
        brokenEgg,
        hatchId,
        eggName
    )
        return {
            Before = before,
            ZoneName = zoneName,
            EggPosition = eggPosition,
            BrokenEgg = brokenEgg,
            HatchId = hatchId,
            EggName = eggName,
            Deadline = os.clock() + PICKUP_SPAWN_TIMEOUT
        }
    end

    function Extra.scanPendingHatches()
        local index = 1

        local titanicState =
            Extra.getTitanicState()

        local suppressNormalAccepted =
            prioritizeTitanicEgg
            and titanicState.Active == true

        while index <= #pendingHatches do
            local pending =
                pendingHatches[index]

            local best
            local bestDistance =
                math.huge

            for _, animal
                in ipairs(
                    Pickups:GetChildren()
                )
            do
                if not pending.Before[animal]
                    and animal:IsA("Model")
                    and animal:GetAttribute(
                        "Hatched"
                    ) == true
                then
                    local animalZone =
                        Extra.normalizeZone(
                            animal:GetAttribute(
                                "ZoneId"
                            )
                        )

                    local candidateId =
                        animal:GetAttribute(
                            "HatchId"
                        )

                    local identityMatches =
                        pending.HatchId == nil
                        or (
                            candidateId ~= nil
                            and tostring(candidateId)
                                == tostring(
                                    pending.HatchId
                                )
                        )

                    if identityMatches
                        and (
                            not animalZone
                            or animalZone
                                == pending.ZoneName
                        )
                    then
                        local distance =
                            (
                                animal:GetPivot().Position
                                - pending.EggPosition
                            ).Magnitude

                        if distance
                                <= MAX_PICKUP_SPAWN_DISTANCE
                            and distance
                                < bestDistance
                        then
                            best = animal
                            bestDistance =
                                distance
                        end
                    end
                end
            end

            if best then
                local rawName =
                    best:GetAttribute(
                        "AnimalName"
                    )
                    or best.Name

                local resolvedIncome

                -- Give replicated income metadata a brief moment to arrive
                -- only when the user actually enabled the minimum-income filter.
                if Extra.minimumPetIncome > 0
                    and Extra.isSelected(
                        selectedPets,
                        rawName
                    )
                then
                    resolvedIncome =
                        Extra.getPetIncomePerSecond(
                            best
                        )

                    if resolvedIncome == nil
                        and os.clock()
                            < pending.Deadline
                    then
                        index += 1
                        continue
                    end

                    if resolvedIncome == nil then
                        Extra.log(
                            "Income unresolved:",
                            rawName,
                            "| Minimum:",
                            Extra.minimumPetIncome,
                            "| Rejecting hatch"
                        )
                    else
                        Extra.log(
                            "Income check:",
                            rawName,
                            "| Income/s:",
                            resolvedIncome,
                            "| Minimum:",
                            Extra.minimumPetIncome
                        )
                    end
                end

                table.remove(
                    pendingHatches,
                    index
                )

                if Extra.petMatchesFilter(
                    best,
                    resolvedIncome
                ) then
                        if suppressNormalAccepted
                            and not Extra.pendingIsFromTitanic(
                                pending,
                                titanicState
                            )
                        then
                            -- Titanic has absolute priority. Keep this accepted
                            -- normal hatch queued; it may be collected after the
                            -- Titanic target is finished.
                            table.insert(
                                pendingHatches,
                                pending
                            )

                            Extra.log(
                                "Pending hatch deferred for Titanic:",
                                rawName,
                                "| From:",
                                pending.EggName
                            )
                        else
                            Extra.log(
                                "Pending hatch accepted:",
                                rawName,
                                "| From:",
                                pending.EggName,
                                "| Remaining pending:",
                                #pendingHatches
                            )

                            return best
                        end
                    else
                        Extra.log(
                            "Pending hatch rejected:",
                            rawName,
                            "| From:",
                            pending.EggName,
                            "| Continue breaking eggs"
                        )
                    end

            elseif os.clock()
                    >= pending.Deadline
            then
                Extra.log(
                    "Pending hatch timed out:",
                    pending.EggName
                )

                table.remove(
                    pendingHatches,
                    index
                )

            else
                index += 1
            end
        end

        return nil
    end

    function Extra.waitHitDelayWatchingPending(
        duration
    )
        local deadline =
            os.clock()
            + duration

        while autoFarmActive
            and currentActivity == "Farm"
            and os.clock() < deadline
        do
            local accepted =
                Extra.scanPendingHatches()

            if accepted then
                return accepted
            end

            task.wait(0.03)
        end

        return nil
    end

    function Extra.attackEggWhileWatchingPending(
        egg,
        zoneName
    )
        if not Extra.validEgg(egg) then
            return nil, false
        end

        local before =
            Extra.snapshotPickups()

        local eggPosition =
            egg.Position

        local hatchId =
            egg:GetAttribute(
                "HatchId"
            )

        local eggName =
            Extra.getEggName(egg)

        local acceptedDuringMove
        local titanicSwitchRequested = false

        local function checkTitanicSwitch()
            if not prioritizeTitanicEgg then
                return false
            end

            if Extra.titanicLockedEgg == egg
                and egg
                and egg.Parent
                and Extra.validEgg(
                    egg
                )
            then
                return false
            end

            local titanic =
                Extra.findTitanicEgg(
                    egg
                )

            if titanic then
                titanicSwitchRequested =
                    true

                return true
            end

            return false
        end

        local function interruptForPending()
            acceptedDuringMove =
                Extra.findGlobalAcceptedPickup()

            if not acceptedDuringMove then
                acceptedDuringMove =
                    Extra.scanPendingHatches()
            end

            return acceptedDuringMove ~= nil
                or checkTitanicSwitch()
                or Extra.isCarrying()
                or Extra.isBeingChased()
                or Extra.autoStealBusy
                or not autoFarmActive
                or currentActivity
                    ~= "Farm"
        end

        local _, _, hrp =
            Extra.getCharacter()

        local distance =
            (
                hrp.Position
                - eggPosition
            ).Magnitude

        Extra.log(
            "Target:",
            eggName,
            "| HP:",
            egg:GetAttribute("Health"),
            "| Zone:",
            zoneName,
            "| Distance:",
            string.format(
                "%.2f",
                distance
            ),
            "| Pending:",
            #pendingHatches
        )

        if distance > HIT_DISTANCE then
            Extra.moveTo(
                Extra.getApproachPosition(
                    eggPosition,
                    EGG_APPROACH_DISTANCE
                ),
                2,
                45,
                interruptForPending
            )

            if acceptedDuringMove then
                return
                    acceptedDuringMove,
                    false
            end

            if titanicSwitchRequested then
                Extra.log(
                    "Titanic spawned while travelling; switching target."
                )

                return nil, false
            end

            if not autoFarmActive
                or currentActivity
                    ~= "Farm"
            then
                return nil, false
            end
        end

        local acceptedBeforeEquip =
            Extra.scanPendingHatches()

        if acceptedBeforeEquip then
            return
                acceptedBeforeEquip,
                false
        end

        if not Extra.ensurePickaxe() then
            return nil, false
        end

        if not Extra.usePickaxe() then
            return nil, false
        end

        while autoFarmActive
            and currentActivity == "Farm"
            and Extra.validEgg(egg)
        do
            local titanicNow =
                Extra.findTitanicEgg(
                    egg
                )

            if titanicNow then
                Extra.log(
                    "Titanic spawned; interrupting normal egg:",
                    eggName
                )

                Extra.stopMoving()
                return nil, false
            end

            local accepted =
                Extra.findGlobalAcceptedPickup()

            if not accepted then
                accepted =
                    Extra.scanPendingHatches()
            end

            if accepted then
                Extra.stopMoving()

                return
                    accepted,
                    false
            end

            local _, _, currentHRP =
                Extra.getCharacter()

            local currentDistance =
                (
                    currentHRP.Position
                    - egg.Position
                ).Magnitude

            if currentDistance
                > HIT_DISTANCE
            then
                acceptedDuringMove = nil

                Extra.moveTo(
                    Extra.getApproachPosition(
                        egg.Position,
                        EGG_APPROACH_DISTANCE
                    ),
                    2,
                    20,
                    interruptForPending
                )

                if acceptedDuringMove then
                    return
                        acceptedDuringMove,
                        false
                end

                if titanicSwitchRequested then
                    Extra.log(
                        "Titanic spawned during re-approach; switching target."
                    )

                    return nil, false
                end

                if not Extra.validEgg(egg) then
                    break
                end
            end

            local tier =
                LocalPlayer:GetAttribute(
                    "PickaxeTier"
                )
                or 1

            EggHitRequest:FireServer(
                egg,
                tier
            )

            if Extra.autoNextZoneEnabled
                and zoneName
                    == Extra.autoNextZoneTrialZone
            then
                Extra.autoNextZoneTrialHits += 1

                if Extra.autoNextZoneTrialHits
                    >= 15
                then
                    task.wait(0.05)

                    if Extra.validEgg(egg) then
                        Extra.markAutoNextZoneTooSlow(
                            zoneName
                        )

                        Extra.stopMoving()
                        return nil, false
                    end
                end
            end

            Extra.log(
                "Hit",
                "| Egg:",
                eggName,
                "| Tier:",
                tier,
                "| HP:",
                egg:GetAttribute(
                    "Health"
                ),
                "| Pending:",
                #pendingHatches
            )

            local acceptedDuringDelay =
                Extra.waitHitDelayWatchingPending(
                    HIT_DELAY
                )

            if acceptedDuringDelay then
                Extra.stopMoving()

                return
                    acceptedDuringDelay,
                    false
            end
        end

        if not autoFarmActive
            or currentActivity ~= "Farm"
        then
            return nil, false
        end

        if Extra.validEgg(egg) then
            return nil, false
        end

        Extra.markAutoNextZoneSuccess(
            zoneName
        )

        Extra.log(
            "Egg done:",
            eggName,
            "| Queue hatch result",
            "| Pending:",
            #pendingHatches + 1
        )

        local titanicStateAtBreak =
            Extra.getTitanicState()

        if titanicStateAtBreak.Active
            and titanicStateAtBreak.EggName
            and Extra.normalizeEggKey(eggName)
                == Extra.normalizeEggKey(
                    titanicStateAtBreak.EggName
                )
        then
            titanicOverrideSpawnId =
                titanicStateAtBreak.SpawnId

            Extra.log(
                "Titanic egg broken:",
                eggName,
                "| SpawnId:",
                titanicOverrideSpawnId
            )
        end

        table.insert(
            pendingHatches,
            Extra.makePendingHatch(
                before,
                zoneName,
                eggPosition,
                egg,
                hatchId
                    or egg:GetAttribute(
                        "HatchId"
                    ),
                eggName
            )
        )

        return nil, true
    end

    function Extra.breakEgg(
        initialEgg,
        initialZoneName
    )
        local targetEgg =
            initialEgg

        local targetZone =
            initialZoneName

        while autoFarmActive
            and currentActivity == "Farm"
        do
            -- ABSOLUTE PRIORITY:
            -- if a Titanic egg exists, it wins before pending normal pets,
            -- normal egg filters, normal rarity priority, and timers.
            local titanicEgg,
                titanicZone =
                Extra.findTitanicEgg()

            if titanicEgg then
                if targetEgg ~= titanicEgg then
                    Extra.stopMoving()

                    targetEgg =
                        titanicEgg

                    targetZone =
                        titanicZone

                    Extra.log(
                        "ABSOLUTE TITANIC PRIORITY ->",
                        Extra.getEggName(
                            titanicEgg
                        ),
                        "| Zone:",
                        titanicZone
                    )
                end
            else
                -- Any hatched pet in AnimalPickups can be collected when it
                -- passes the active pet/minimum-income filters, regardless of
                -- which player broke the egg that spawned it.
                local globalPickup =
                    Extra.findGlobalAcceptedPickup()

                if globalPickup then
                    Extra.stopMoving()

                    Extra.log(
                        "Interrupt farm for global pickup:",
                        globalPickup:GetAttribute(
                            "AnimalName"
                        )
                            or globalPickup.Name
                    )

                    return globalPickup
                end

                local accepted =
                    Extra.scanPendingHatches()

                if accepted then
                    Extra.stopMoving()
                    return accepted
                end
            end

            if not targetEgg
                or not Extra.validEgg(targetEgg)
            then
                targetEgg,
                targetZone =
                    Extra.findBestEgg()
            end

            if not targetEgg then
                -- No breakable egg right now, but a broken egg may still
                -- be hatching. Keep watching it instead of ending the cycle.
                if #pendingHatches > 0 then
                    task.wait(0.05)
                    continue
                end

                return nil
            end

            local acceptedWhileBreaking,
                brokeTarget =
                Extra.attackEggWhileWatchingPending(
                    targetEgg,
                    targetZone
                )

            if acceptedWhileBreaking then
                return
                    acceptedWhileBreaking
            end

            -- Whether it broke or became invalid, choose another target.
            -- If it broke, its hatch result is already in pendingHatches.
            targetEgg = nil
            targetZone = nil

            if not brokeTarget then
                task.wait(0.03)
            end
        end

        return nil
    end

    -- Prompt helpers
    function Extra.getPromptPosition(prompt)
        if not prompt or not prompt.Parent then
            return nil
        end

        local parent = prompt.Parent

        if parent:IsA("Attachment") then
            return parent.WorldPosition
        end

        if parent:IsA("BasePart") then
            return parent.Position
        end

        local part = prompt:FindFirstAncestorWhichIsA("BasePart")
        return part and part.Position or nil
    end

    function Extra.modelDistanceToPoint(model, point)
        local ok, cf, size = pcall(function()
            return model:GetBoundingBox()
        end)

        if not ok then
            return math.huge
        end

        local localPoint = cf:PointToObjectSpace(point)
        local half = size * 0.5

        local dx = math.max(math.abs(localPoint.X) - half.X, 0)
        local dy = math.max(math.abs(localPoint.Y) - half.Y, 0)
        local dz = math.max(math.abs(localPoint.Z) - half.Z, 0)

        return Vector3.new(dx, dy, dz).Magnitude
    end

    function Extra.normalizeText(text)
        return tostring(text or "")
            :gsub("<.->", "")
            :lower()
            :gsub("[^%w]", "")
    end

    function Extra.promptKg(prompt)
        local text = tostring(prompt.ObjectText or ""):gsub("<.->", "")
        return tonumber(text:match("%[([%d%.]+)%s*[Kk][Gg]%]"))
    end

    function Extra.promptMatchesAnimal(prompt, animal)
        if not prompt
            or not prompt.Parent
            or not animal
            or not animal.Parent
        then
            return false
        end

        if prompt.Name ~= "StealPrompt"
            and prompt.ActionText ~= "Steal"
        then
            return false
        end

        if prompt:IsDescendantOf(animal) then
            return true
        end

        local position = Extra.getPromptPosition(prompt)

        if not position then
            return false
        end

        local distance = Extra.modelDistanceToPoint(animal, position)

        if distance > 6 then return false end
        local name = animal:GetAttribute("AnimalName") or animal.Name
        local objectText = Extra.normalizeText(prompt.ObjectText)
        local targetText = Extra.normalizeText(Extra.displayName(name))
        local rawText = Extra.normalizeText(name)
        local nameMatches = objectText:find(targetText, 1, true)
            or objectText:find(rawText, 1, true)
        local weight = tonumber(animal:GetAttribute("WeightKg"))
        local shownWeight = Extra.promptKg(prompt)
        if nameMatches then
            return not weight or not shownWeight or math.abs(weight - shownWeight) <= 1.1
        end
        -- Only use geometry when a prompt has no identifying text.
        return objectText == "" and distance <= 1.5
    end

    function Extra.findCurrentPrompt(animal)
        local candidates = {}
        for _, object in ipairs(animal:GetDescendants()) do
            if object:IsA("ProximityPrompt") then candidates[object] = true end
        end
        -- SurfacePrompt.Attach reparents each prompt to its own Workspace anchor.
        for _, object in ipairs(CollectionService:GetTagged("SmartPrompt")) do
            if object:IsA("ProximityPrompt") then candidates[object] = true end
        end
        for _, anchor in ipairs(Workspace:GetChildren()) do
            if anchor.Name == "PromptAnchor" then
                for _, object in ipairs(anchor:GetDescendants()) do
                    if object:IsA("ProximityPrompt") then candidates[object] = true end
                end
            end
        end
        local _, _, hrp = Extra.getCharacter()
        local best, bestDistance = nil, math.huge
        for prompt in pairs(candidates) do
            if prompt.Enabled and Extra.promptMatchesAnimal(prompt, animal) then
                local position = Extra.getPromptPosition(prompt)
                local distance = position and (position - hrp.Position).Magnitude or math.huge
                if distance < bestDistance then best, bestDistance = prompt, distance end
            end
        end
        return best
    end

    function Extra.waitStealPrompt(animal)
        local foundPrompt

        local shownConnection =
            ProximityPromptService.PromptShown:
            Connect(function(prompt)
                if not foundPrompt
                    and Extra.promptMatchesAnimal(prompt, animal)
                then
                    foundPrompt = prompt
                    Extra.log("Prompt shown:", prompt:GetFullName())
                end
            end)

        local deadline = os.clock() + PROMPT_TIMEOUT

        while autoFarmActive
            and animal.Parent
            and os.clock() < deadline
            and not foundPrompt
        do
            foundPrompt = Extra.findCurrentPrompt(animal)

            if foundPrompt then
                break
            end

            task.wait(0.08)
        end

        shownConnection:Disconnect()

        return foundPrompt
    end

    -- Carry state from the game's own ChaseState module.
    Extra.isCarrying = function()
        local ok, carrying = pcall(function()
            return ChaseState.IsCarrying(LocalPlayer)
        end)

        return ok and carrying == true
    end

    Extra.isBeingChased = function()
        -- IsActive also includes Carrying; only this attribute identifies chase.
        local attribute = ChaseState.ChasedAttribute or "BeingChased"
        return LocalPlayer:GetAttribute(attribute) ~= nil
    end

    function Extra.waitUntilCarrying(timeout)
        local deadline = os.clock() + (timeout or CARRY_TIMEOUT)

        while autoFarmActive and os.clock() < deadline do
            if Extra.isCarrying() then
                return true
            end

            task.wait(0.01)
        end

        return false
    end

    function Extra.getAnimalSignature(animal)
        return {
            HatchId = animal:GetAttribute("HatchId"),
            AnimalName =
                animal:GetAttribute("AnimalName")
                or animal.Name,
            WeightKg =
                tonumber(
                    animal:GetAttribute("WeightKg")
                ),
            ZoneId =
                Extra.normalizeZone(
                    animal:GetAttribute("ZoneId")
                )
        }
    end

    function Extra.matchesAnimalSignature(
        animal,
        signature,
        allowMissingHatchId
    )
        if not animal
            or not animal.Parent
            or not animal:IsA("Model")
        then
            return false
        end

        local hatchId =
            animal:GetAttribute(
                "HatchId"
            )

        -- If both sides have HatchId, it is the strongest identity check.
        -- A dropped/recreated pickup can briefly have no HatchId, so recovery
        -- is allowed to fall back to the other replicated metadata.
        if signature.HatchId ~= nil
            and hatchId ~= nil
        then
            if tostring(hatchId)
                ~= tostring(
                    signature.HatchId
                )
            then
                return false
            end
        elseif signature.HatchId ~= nil
            and not allowMissingHatchId
        then
            return false
        end

        local name =
            animal:GetAttribute(
                "AnimalName"
            )
            or animal.Name

        if name ~= signature.AnimalName then
            return false
        end

        local zone =
            Extra.normalizeZone(
                animal:GetAttribute(
                    "ZoneId"
                )
            )

        if signature.ZoneId
            and zone
            and zone ~= signature.ZoneId
        then
            return false
        end

        local weight =
            tonumber(
                animal:GetAttribute(
                    "WeightKg"
                )
            )

        if signature.WeightKg
            and weight
            and math.abs(
                weight
                - signature.WeightKg
            ) > 1.1
        then
            return false
        end

        return true
    end

    function Extra.waitForDroppedAnimal(
        signature,
        expectedPosition
    )
        local deadline =
            os.clock()
            + DROPPED_PET_TIMEOUT

        expectedPosition =
            typeof(expectedPosition)
                == "Vector3"
            and expectedPosition
            or nil

        while autoFarmActive
            and os.clock() < deadline
        do
            local _, _, hrp =
                Extra.getCharacter()

            local origin =
                expectedPosition
                or hrp.Position

            local best
            local bestScore =
                math.huge

            for _, candidate
                in ipairs(
                    Pickups:GetChildren()
                )
            do
                if Extra.matchesAnimalSignature(
                    candidate,
                    signature,
                    true
                ) then
                    local position =
                        candidate:GetPivot().Position

                    local distanceToDrop =
                        (
                            position
                            - origin
                        ).Magnitude

                    local distanceToPlayer =
                        (
                            position
                            - hrp.Position
                        ).Magnitude

                    if distanceToDrop
                        <= DROPPED_PET_SEARCH_RADIUS
                    then
                        local candidateId =
                            candidate:GetAttribute(
                                "HatchId"
                            )

                        local exactId =
                            signature.HatchId ~= nil
                            and candidateId ~= nil
                            and tostring(candidateId)
                                == tostring(
                                    signature.HatchId
                                )

                        -- Exact HatchId always wins. When the recreated pickup
                        -- temporarily has no HatchId, choose the closest matching
                        -- name/zone/weight around the place where it was dropped.
                        local score =
                            distanceToDrop
                            + distanceToPlayer
                                * 0.15

                        if exactId then
                            score =
                                score - 100000
                        end

                        if score < bestScore then
                            best = candidate
                            bestScore = score
                        end
                    end
                end
            end

            if best then
                Extra.log(
                    "Dropped pet found:",
                    signature.AnimalName,
                    "| HatchId:",
                    best:GetAttribute(
                        "HatchId"
                    ),
                    "| Position:",
                    best:GetPivot().Position
                )

                return best
            end

            task.wait(0.05)
        end

        return nil
    end

    function Extra.teleportToAnimal(
        animal,
        label
    )
        if not animal
            or not animal.Parent
        then
            return false
        end

        local ok,
            result =
            pcall(function()
                local _, _, hrp =
                    Extra.getCharacter()

                local petPosition =
                    animal:GetPivot().Position

                local direction =
                    hrp.Position
                    - petPosition

                direction =
                    Vector3.new(
                        direction.X,
                        0,
                        direction.Z
                    )

                if direction.Magnitude < 0.1 then
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

                local destination =
                    petPosition
                    + direction * 2

                hrp.CFrame =
                    CFrame.lookAt(
                        Vector3.new(
                            destination.X,
                            hrp.Position.Y,
                            destination.Z
                        ),
                        Vector3.new(
                            petPosition.X,
                            hrp.Position.Y,
                            petPosition.Z
                        )
                    )

                hrp.AssemblyLinearVelocity =
                    Vector3.zero
                hrp.AssemblyAngularVelocity =
                    Vector3.zero

                Extra.log(
                    label
                        or "Teleport to pet",
                    animal:GetAttribute(
                        "AnimalName"
                    )
                        or animal.Name
                )

                return true
            end)

        return
            ok
            and result == true
    end

    function Extra.pickUpAnimal(animal, animalName)
        if not animal or not animal.Parent then return false end
        local signature = Extra.getAnimalSignature(animal)
        local deadline = os.clock() + 35
        while autoFarmActive and os.clock() < deadline do
            if Extra.isCarrying() then return true end
            if not animal:IsDescendantOf(Pickups) then
                local replacement
                local replacementDistance =
                    math.huge

                local _, _, replacementHRP =
                    Extra.getCharacter()

                for _, candidate
                    in ipairs(
                        Pickups:GetChildren()
                    )
                do
                    if Extra.matchesAnimalSignature(
                        candidate,
                        signature,
                        true
                    ) then
                        local distance =
                            (
                                candidate:GetPivot().Position
                                - replacementHRP.Position
                            ).Magnitude

                        if distance
                            < replacementDistance
                        then
                            replacement =
                                candidate

                            replacementDistance =
                                distance
                        end
                    end
                end

                if not replacement then
                    return false
                end

                Extra.log(
                    "Pickup instance replaced:",
                    animalName,
                    "| Distance:",
                    string.format(
                        "%.2f",
                        replacementDistance
                    )
                )

                animal = replacement
            end
            local targetPosition = animal:GetPivot().Position
            local prompt = Extra.findCurrentPrompt(animal)
            local promptPosition = prompt and Extra.getPromptPosition(prompt)
            local _, _, hrp = Extra.getCharacter()
            local range = prompt and prompt.MaxActivationDistance or PET_APPROACH_DISTANCE
            local distance = promptPosition and (hrp.Position - promptPosition).Magnitude
                or Extra.modelDistanceToPoint(animal, hrp.Position)
            if distance > math.max(1, range - 0.5) then
                -- Short approaches refresh position when the ragdoll rolls or slides.
                local approach = Extra.getApproachPosition(promptPosition or targetPosition, 2)
                Extra.moveTo(approach, 1, math.min(2, deadline - os.clock()), function()
                    return Extra.isCarrying() or not animal:IsDescendantOf(Pickups)
                        or (animal:GetPivot().Position - targetPosition).Magnitude > 2
                end)
            elseif prompt and prompt.Parent and prompt.Enabled
                and Extra.promptMatchesAnimal(prompt, animal) then
                if type(fireproximityprompt) ~= "function" then
                    warn("[CHLISE HUB] Prompt activation is unavailable.")
                    return false
                end
                local ok, err = pcall(fireproximityprompt, prompt)
                if not ok then Extra.log("Pickup retry:", err) end
                if Extra.waitUntilCarrying(math.min(0.6, math.max(0, deadline - os.clock()))) then
                    return true
                end
            end
            task.wait(0.1)
        end
        Extra.log("Pickup timed out:", animalName)
        return false
    end

    function Extra.findBatTool()
        local character =
            LocalPlayer.Character

        local backpack =
            LocalPlayer:
                FindFirstChildOfClass(
                    "Backpack"
                )

        local function search(
            container
        )
            if not container then
                return nil
            end

            for _, child
                in ipairs(
                    container:GetChildren()
                )
            do
                if child:IsA("Tool")
                    and child.Name:
                        lower():
                        find(
                            "bat",
                            1,
                            true
                        )
                then
                    return child
                end
            end

            return nil
        end

        return
            search(character)
            or search(backpack)
    end

    function Extra.ensureBatEquipped()
        local bat =
            Extra.findBatTool()

        if not bat then
            if not Extra.autoStealBatWarned then
                Extra.autoStealBatWarned =
                    true

                warn(
                    "[CHLISE HUB] Auto Steal: Bat tool not found in Backpack/Character."
                )
            end

            return nil
        end

        local character,
            humanoid =
            Extra.getCharacter()

        if bat.Parent ~= character then
            humanoid:
                EquipTool(
                    bat
                )

            task.wait(0.08)
        end

        if bat.Parent == character then
            Extra.autoStealBatWarned =
                false
            return bat
        end

        return nil
    end

    function Extra.playerIsCarryingPet(
        player
    )
        if not player
            or player == LocalPlayer
        then
            return false
        end

        local ok,
            carrying =
            pcall(function()
                return
                    ChaseState.IsCarrying(
                        player
                    )
            end)

        if ok
            and carrying == true
        then
            return true
        end

        local attribute =
            ChaseState.CarryingAttribute
            or "Carrying"

        return
            player:GetAttribute(
                attribute
            ) ~= nil
            and player:GetAttribute(
                attribute
            ) ~= false
    end

    function Extra.getCarriedPetInfo(
        player
    )
        if not player
            or player == LocalPlayer
            or not Extra.playerIsCarryingPet(
                player
            )
        then
            return nil
        end

        local animalName =
            player:GetAttribute(
                "Carrying"
            )

        if animalName == nil
            or animalName == false
            or tostring(animalName)
                == ""
        then
            return nil
        end

        local zoneName =
            Extra.normalizeZone(
                player:GetAttribute(
                    "CarryingZone"
                )
            )

        local weightKg =
            tonumber(
                player:GetAttribute(
                    "CarryingKg"
                )
            )

        local sizeMult =
            tonumber(
                player:GetAttribute(
                    "CarryingSizeMult"
                )
            )

        local bracket =
            player:GetAttribute(
                "CarryingBracket"
            )

        local rarity =
            player:GetAttribute(
                "CarryingRarity"
            )

        local income

        if type(
            EggRewards.PlacedCashPerSecond
        ) == "function"
            and weightKg
            and sizeMult
        then
            local okIncome,
                result =
                pcall(
                    EggRewards.PlacedCashPerSecond,
                    tostring(animalName),
                    weightKg,
                    sizeMult
                )

            if okIncome then
                income =
                    tonumber(
                        result
                    )
            end
        end

        return {
            AnimalName =
                tostring(animalName),
            ZoneName =
                zoneName,
            WeightKg =
                weightKg,
            SizeMult =
                sizeMult,
            Bracket =
                bracket,
            Rarity =
                rarity,
            Income =
                income
        }
    end

    function Extra.carriedPetPassesAutoSteal(
        player
    )
        if not Extra.playerIsCarryingPet(
            player
        ) then
            return false, nil
        end

        local info =
            Extra.getCarriedPetInfo(
                player
            )

        if not info then
            Extra.log(
                "Auto Steal skip:",
                player.Name,
                "| Carry attributes unresolved"
            )
            return false, nil
        end

        if not Extra.isSelected(
            selectedPets,
            info.AnimalName
        ) then
            Extra.log(
                "Auto Steal skip:",
                player.Name,
                "| Pet filter:",
                info.AnimalName
            )
            return false, info
        end

        if not info.ZoneName then
            Extra.log(
                "Auto Steal skip:",
                player.Name,
                "| CarryingZone unresolved"
            )
            return false, info
        end

        Extra.initializeAutoNextZone()

        local currentZone =
            Extra.autoNextZoneSafeZone
            or Extra.detectCurrentZone()

        local currentIndex =
            Extra.zoneIndex(
                currentZone
            )

        local carriedIndex =
            Extra.zoneIndex(
                info.ZoneName
            )

        if not currentIndex
            or not carriedIndex
            or carriedIndex
                < currentIndex
            or carriedIndex
                > currentIndex + 1
        then
            Extra.log(
                "Auto Steal skip:",
                player.Name,
                "| Zone:",
                info.ZoneName,
                "| Allowed:",
                currentZone,
                "->",
                currentIndex
                    and MASTER_ZONES[
                        currentIndex + 1
                    ]
                    or "?"
            )
            return false, info
        end

        local speedAllowed,
            speedRequirement =
            Extra.speedAllowsZone(
                info.ZoneName
            )

        if not speedAllowed then
            Extra.log(
                "Auto Steal skip:",
                player.Name,
                "| Speed insufficient",
                "| Zone:",
                info.ZoneName,
                "| Speed:",
                Extra.getProgressionSpeed(),
                "| Required:",
                speedRequirement
                    or "Unknown"
            )
            return false, info
        end

        if Extra.minimumPetIncome > 0 then
            if info.Income == nil then
                Extra.log(
                    "Auto Steal skip:",
                    player.Name,
                    "| Pet:",
                    info.AnimalName,
                    "| Income unresolved"
                )
                return false, info
            end

            if info.Income
                < Extra.minimumPetIncome
            then
                Extra.log(
                    "Auto Steal skip:",
                    player.Name,
                    "| Pet:",
                    info.AnimalName,
                    "| Income/s:",
                    info.Income,
                    "| Minimum:",
                    Extra.minimumPetIncome
                )
                return false, info
            end
        end

        Extra.log(
            "Auto Steal precheck PASS:",
            player.Name,
            "| Pet:",
            info.AnimalName,
            "| Zone:",
            info.ZoneName,
            "| Kg:",
            info.WeightKg
                or "N/A",
            "| Size:",
            info.SizeMult
                or "N/A",
            "| Income/s:",
            info.Income
                or "N/A"
        )

        return true, info
    end

    function Extra.findAutoStealTarget()
        local _, _, localHRP =
            Extra.getCharacter()

        local bestPlayer
        local bestHRP
        local bestInfo
        local bestDistance =
            math.huge

        for _, player
            in ipairs(
                Players:GetPlayers()
            )
        do
            if player ~= LocalPlayer
                and Extra.playerIsCarryingPet(
                    player
                )
            then
                local accepted,
                    carriedInfo =
                    Extra.carriedPetPassesAutoSteal(
                        player
                    )

                if accepted
                    and carriedInfo
                then
                    local character =
                        player.Character

                    local humanoid =
                        character
                        and character:
                            FindFirstChildOfClass(
                                "Humanoid"
                            )

                    local hrp =
                        character
                        and character:
                            FindFirstChild(
                                "HumanoidRootPart"
                            )

                    if humanoid
                        and humanoid.Health > 0
                        and hrp
                    then
                        local distance =
                            (
                                localHRP.Position
                                - hrp.Position
                            ).Magnitude

                        if distance
                            < bestDistance
                        then
                            bestPlayer =
                                player
                            bestHRP =
                                hrp
                            bestInfo =
                                carriedInfo
                            bestDistance =
                                distance
                        end
                    end
                end
            end
        end

        return
            bestPlayer,
            bestHRP,
            bestDistance,
            bestInfo
    end

    function Extra.findAcceptedPickupNear(
        origin,
        radius
    )
        if typeof(origin)
            ~= "Vector3"
        then
            return nil
        end

        radius =
            tonumber(radius)
            or 18

        Extra.initializeAutoNextZone()

        local currentZone =
            Extra.autoNextZoneSafeZone
            or Extra.detectCurrentZone()

        local currentIndex =
            Extra.zoneIndex(
                currentZone
            )

        local maxIndex =
            currentIndex
            and math.min(
                #MASTER_ZONES,
                currentIndex + 1
            )
            or nil

        local best
        local bestDistance =
            math.huge

        for _, animal
            in ipairs(
                Pickups:GetChildren()
            )
        do
            if animal:IsA("Model")
                and animal:GetAttribute(
                    "Hatched"
                ) == true
            then
                local position =
                    animal:GetPivot().Position

                local distance =
                    (
                        position
                        - origin
                    ).Magnitude

                if distance <= radius then
                    local animalZone =
                        Extra.normalizeZone(
                            animal:GetAttribute(
                                "ZoneId"
                            )
                        )
                        or Extra.detectZoneAtPosition(
                            position
                        )

                    local animalIndex =
                        Extra.zoneIndex(
                            animalZone
                        )

                    local inRange =
                        currentIndex ~= nil
                        and maxIndex ~= nil
                        and animalIndex ~= nil
                        and animalIndex
                            >= currentIndex
                        and animalIndex
                            <= maxIndex

                    if inRange then
                        local speedAllowed =
                            Extra.speedAllowsZone(
                                animalZone
                            )

                        if speedAllowed then
                            local income

                            if Extra.minimumPetIncome > 0 then
                                income =
                                    Extra.getPetIncomePerSecond(
                                        animal
                                    )
                            end

                            if Extra.petMatchesFilter(
                                animal,
                                income
                            )
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
            end
        end

        return best
    end

    function Extra.runAutoStealWorker()
        if Extra.autoStealWorkerRunning then
            return
        end

        Extra.autoStealWorkerRunning =
            true

        task.spawn(function()
            while Extra.autoStealEnabled
                and not Window.Destroyed
            do
                local ok,
                    err =
                    pcall(function()
                        if not autoFarmActive
                            or currentActivity
                                ~= "Farm"
                            or Extra.isCarrying()
                            or Extra.isBeingChased()
                        then
                            task.wait(0.15)
                            return
                        end

                        local targetPlayer,
                            targetHRP,
                            _,
                            targetInfo =
                            Extra.findAutoStealTarget()

                        if not targetPlayer
                            or not targetHRP
                            or not targetInfo
                        then
                            task.wait(0.2)
                            return
                        end

                        Extra.log(
                            "Auto Steal target accepted BEFORE chase:",
                            targetPlayer.Name,
                            "| Pet:",
                            targetInfo.AnimalName,
                            "| Zone:",
                            targetInfo.ZoneName
                                or "Unknown",
                            "| Income/s:",
                            targetInfo.Income
                                or "N/A"
                        )

                        local bat =
                            Extra.ensureBatEquipped()

                        if not bat then
                            task.wait(0.5)
                            return
                        end

                        Extra.autoStealBusy =
                            true

                        Extra.stopMoving()

                        local lastPosition =
                            targetHRP.Position

                        local deadline =
                            os.clock() + 8

                        while Extra.autoStealEnabled
                            and autoFarmActive
                            and currentActivity
                                == "Farm"
                            and os.clock()
                                < deadline
                            and targetPlayer.Parent
                            and Extra.playerIsCarryingPet(
                                targetPlayer
                            )
                        do
                            local stillAccepted =
                                Extra.carriedPetPassesAutoSteal(
                                    targetPlayer
                                )

                            if not stillAccepted then
                                Extra.log(
                                    "Auto Steal target no longer qualifies:",
                                    targetPlayer.Name
                                )
                                break
                            end
                            local _,
                                _,
                                localHRP =
                                Extra.getCharacter()

                            if not targetHRP.Parent then
                                break
                            end

                            lastPosition =
                                targetHRP.Position

                            local distance =
                                (
                                    localHRP.Position
                                    - targetHRP.Position
                                ).Magnitude

                            if distance > 7 then
                                Extra.moveTo(
                                    Extra.getApproachPosition(
                                        targetHRP.Position,
                                        4
                                    ),
                                    2,
                                    1.2,
                                    function()
                                        return
                                            not targetHRP.Parent
                                            or not Extra.playerIsCarryingPet(
                                                targetPlayer
                                            )
                                    end
                                )
                            else
                                bat =
                                    Extra.ensureBatEquipped()

                                if bat
                                    and bat.Parent
                                        == LocalPlayer.Character
                                then
                                    bat:
                                        Activate()
                                end

                                task.wait(0.25)
                            end
                        end

                        if not Extra.playerIsCarryingPet(
                            targetPlayer
                        )
                        then
                            local dropDeadline =
                                os.clock() + 3

                            local dropped

                            repeat
                                for _, candidate
                                    in ipairs(
                                        Pickups:GetChildren()
                                    )
                                do
                                    if candidate:IsA("Model")
                                        and candidate:GetAttribute(
                                            "Hatched"
                                        ) == true
                                    then
                                        local candidateName =
                                            candidate:GetAttribute(
                                                "AnimalName"
                                            )
                                            or candidate.Name

                                        local candidateZone =
                                            Extra.normalizeZone(
                                                candidate:GetAttribute(
                                                    "ZoneId"
                                                )
                                            )

                                        local position =
                                            candidate:GetPivot().Position

                                        local closeEnough =
                                            (
                                                position
                                                - lastPosition
                                            ).Magnitude
                                            <= 20

                                        if closeEnough
                                            and tostring(
                                                candidateName
                                            ) == tostring(
                                                targetInfo.AnimalName
                                            )
                                            and (
                                                not targetInfo.ZoneName
                                                or not candidateZone
                                                or candidateZone
                                                    == targetInfo.ZoneName
                                            )
                                        then
                                            local income =
                                                Extra.getPetIncomePerSecond(
                                                    candidate
                                                )

                                            if Extra.minimumPetIncome <= 0
                                                or (
                                                    income ~= nil
                                                    and income
                                                        >= Extra.minimumPetIncome
                                                )
                                            then
                                                dropped =
                                                    candidate
                                                break
                                            end
                                        end
                                    end
                                end

                                if dropped then
                                    break
                                end

                                task.wait(0.05)
                            until os.clock()
                                >= dropDeadline

                            if dropped
                                and dropped.Parent
                            then
                                Extra.log(
                                    "Auto Steal dropped pet accepted:",
                                    dropped:GetAttribute(
                                        "AnimalName"
                                    )
                                        or dropped.Name
                                )

                                Extra.teleportToAnimal(
                                    dropped,
                                    "Auto Steal drop -> instant teleport:"
                                )

                                Extra.stealAndBank(
                                    dropped
                                )
                            end
                        end

                        Extra.autoStealBusy =
                            false
                    end)

                Extra.autoStealBusy =
                    false

                if not ok then
                    warn(
                        "[CHLISE HUB] Auto Steal error:",
                        err
                    )

                    task.wait(0.5)
                end
            end

            Extra.autoStealBusy =
                false
            Extra.autoStealWorkerRunning =
                false
        end)
    end

    function Extra.stealAndBank(animal)
        if Extra.globalPickupCached == animal then
            Extra.globalPickupCached = nil
        end

        if not animal or not animal.Parent then
            return false
        end

        local signature =
            Extra.getAnimalSignature(animal)

        local animalName =
            signature.AnimalName

        local income

        if Extra.minimumPetIncome > 0 then
            income =
                Extra.waitForPetIncome(
                    animal,
                    1.5
                )
        else
            income =
                Extra.getPetIncomePerSecond(
                    animal
                )
        end

        if not Extra.petMatchesFilter(
            animal,
            income
        ) then
            Extra.log(
                "Discard hatch result:",
                animalName,
                "| Filter mismatch",
                "| Income/s:",
                income
            )
            return false
        end

        Extra.log(
            "Pet accepted:",
            animalName,
            "| Income/s:",
            income or "N/A",
            "| HatchId:",
            signature.HatchId
        )

        -- Accepted pets are time-sensitive. Teleport directly to the pickup
        -- instead of using the configured Walk/Tween/zone-teleport movement.
        Extra.teleportToAnimal(
            animal,
            "Accepted pet -> instant teleport:"
        )

        local banked = false

        local bankConnection =
            AnimalBankedRemote.OnClientEvent:
            Connect(function(data)
                if type(data) ~= "table" then
                    return
                end

                for _, info in ipairs(data) do
                    if type(info) == "table"
                        and info.Name == animalName
                    then
                        banked = true

                        Extra.log(
                            "Banked:",
                            info.Name,
                            "| Count:",
                            info.Count
                        )

                        break
                    end
                end
            end)

        local function bankedNow()
            return banked
        end

        local recoveryOK, recoveryError = pcall(function()
            if not Extra.pickUpAnimal(animal, animalName) then return false end
        -- If the guardian knocks the pet out of our hands,
        -- locate the same HatchId and pick it up again.
        while autoFarmActive
            and not banked
        do
            if not Extra.isCarrying() then
                local _, _, currentHRP = Extra.getCharacter()
                if Extra.isBankablePosition(currentHRP.Position) then
                    local graceDeadline = os.clock() + BANK_GRACE_SECONDS
                    while autoFarmActive and not banked and os.clock() < graceDeadline do
                        task.wait(0.03)
                    end
                    if banked then break end
                end
                local dropPosition =
                    currentHRP.Position

                local dropped =
                    Extra.waitForDroppedAnimal(
                        signature,
                        dropPosition
                    )

                if not dropped then

                    warn(
                        "[CHLISE HUB] Dropped pet not found:",
                        animalName
                    )

                    return false
                end

                Extra.log(
                    "Retry pickup:",
                    animalName
                )

                -- Chase/drop recovery is time-sensitive:
                -- jump straight back to the exact dropped pet first.
                Extra.teleportToAnimal(
                    dropped,
                    "Chase drop -> instant teleport:"
                )

                if not Extra.pickUpAnimal(
                    dropped,
                    animalName
                ) then
                    Extra.log(
                        "Dropped pet pickup failed, retrying:",
                        animalName
                    )

                    task.wait(0.15)
                    continue
                end

                Extra.log(
                    "Dropped pet recovered, returning home:",
                    animalName
                )
            end

            local homeState =
                Extra.walkHome(
                    bankedNow
                )

            if banked then
                break
            end

            if homeState == "dropped" then
                Extra.log(
                    "Pet dropped on return, recovering:",
                    animalName
                )

                task.wait(0.05)
                continue
            end

            if homeState == "safe" then
                -- Chase is already gone. Give the normal bank
                -- event a moment, while still watching for drops.
                local deadline =
                    os.clock()
                    + BANK_TIMEOUT

                while autoFarmActive
                    and not banked
                    and Extra.isCarrying()
                    and not Extra.isBeingChased()
                    and os.clock() < deadline
                do
                    task.wait(0.03)
                end

                if not Extra.isCarrying()
                    and not banked
                then
                    Extra.log(
                        "Pet dropped inside/near safe zone, recovering:",
                        animalName
                    )

                    continue
                end
            elseif homeState == "failed" then
                warn(
                    "[CHLISE HUB] Home retry required:",
                    animalName
                )

                task.wait(0.12)
            end
        end

        end)

        bankConnection:Disconnect()
        if not recoveryOK then error(recoveryError, 0) end

        if banked then
            Extra.stopMoving()
            while autoFarmActive and Extra.isBeingChased() do
                task.wait(HOME_RETRY_WAIT)
            end
            Extra.log(
                "Cycle complete:",
                animalName
            )

            return true
        end

        return false
    end

    if TreadmillSessionRemote then
        TreadmillSessionRemote.
        OnClientEvent:
        Connect(function(speed, sessionCF)
            if typeof(speed) ~= "number"
                or typeof(sessionCF)
                    ~= "CFrame"
            then
                return
            end

            treadmillSessionSpeed =
                speed

            treadmillSessionCFrame =
                sessionCF

            lastTreadmillSession =
                os.clock()

            Extra.log(
                "Treadmill session detected",
                "| Speed:",
                speed,
                "| Position:",
                sessionCF.Position
            )
        end)
    end

    -- Farm loop
    Extra.startAutoFarm = function()
        if farmLoopRunning then
            task.spawn(function()
                local deadline =
                    os.clock() + 2

                while farmLoopRunning
                    and os.clock() < deadline
                do
                    task.wait(0.05)
                end

                if autoFarmActive
                    and currentActivity == "Farm"
                    and not farmLoopRunning
                then
                    Extra.startAutoFarm()
                end
            end)

            return
        end

        farmLoopRunning = true

        task.spawn(function()
            while autoFarmActive
                and currentActivity == "Farm"
                and not Window.Destroyed
            do
                local ok, err = pcall(function()
                    if Extra.autoStealBusy then
                        Extra.stopMoving()
                        task.wait(0.08)
                        return
                    end

                    if Extra.isBeingChased() or Extra.isCarrying() then
                        Extra.stopMoving()
                        task.wait(HOME_RETRY_WAIT)
                        return
                    end
                    local egg, zoneName, distance = Extra.findBestEgg()

                    if not egg then
                        task.wait(0.25)
                        return
                    end

                    Extra.log(
                        "Selected egg:",
                        Extra.getEggName(egg),
                        "| Zone:",
                        zoneName,
                        "| Distance:",
                        string.format("%.2f", distance)
                    )

                    local animal = Extra.breakEgg(egg, zoneName)

                    if not autoFarmActive then
                        return
                    end

                    if animal and animal.Parent then
                        Extra.log(
                            "Hatched:",
                            animal:GetAttribute("AnimalName") or animal.Name
                        )

                        Extra.stealAndBank(animal)
                    else
                        Extra.log("No matching hatch; continue farming.")
                    end
                end)

                if not ok then
                    warn("[CHLISE HUB] Break & Steal error:", err)
                    task.wait(0.5)
                end
            end

            if currentActivity == "Farm"
                or currentActivity == nil
            then
                Extra.stopMoving()
            end

            farmLoopRunning = false
        end)
    end

    Extra.startAutoTreadmill = function()
        if treadmillLoopRunning then
            return
        end

        treadmillLoopRunning = true

        task.spawn(function()
            while autoTreadmillActive
                and currentActivity
                    == "Treadmill"
                and not Window.Destroyed
            do
                local ok, err =
                    pcall(function()
                        local _,
                            _,
                            part =
                            Extra.getPlotTreadmill()

                        if not part then
                            Extra.teleportToTreadmill()
                            task.wait(0.5)
                            return
                        end

                        if not Extra.isOnTreadmill(
                            part
                        ) then
                            Extra.teleportToTreadmill()
                            task.wait(0.25)
                            return
                        end

                        local _,
                            humanoid =
                            Extra.getCharacter()

                        -- Treadmill itself handles the session.
                        -- Do not force a running direction.
                        humanoid:Move(
                            Vector3.zero,
                            false
                        )
                    end)

                if not ok then
                    warn(
                        "[CHLISE HUB] Auto Treadmill error:",
                        err
                    )

                    task.wait(0.5)
                else
                    task.wait(0.12)
                end
            end

            treadmillLoopRunning =
                false
        end)
    end

    Extra.setActivity = function(activity)
        local sameActivity =
            activity == currentActivity

        currentActivity =
            activity

        autoFarmActive =
            activity == "Farm"

        autoTreadmillActive =
            activity == "Treadmill"

        if not sameActivity then
            Extra.stopMoving()
        end

        if activity == "Farm" then
            Extra.log(
                "Activity -> Auto Farm Egg"
            )

            if titanicOverrideActive then
                activityDeadline = nil
            else
                Extra.refreshActivityDeadline()
            end

            Extra.startAutoFarm()

        elseif activity == "Treadmill" then
            Extra.log(
                "Activity -> Auto Treadmill"
            )

            if titanicOverrideActive then
                activityDeadline = nil
            else
                Extra.refreshActivityDeadline()
            end

            Extra.teleportToTreadmill()
            Extra.startAutoTreadmill()

        else
            activityDeadline = nil
            Extra.log("Activity -> Idle")
        end
    end

    function Extra.beginTitanicOverride()
        if titanicOverrideActive then
            return
        end

        -- Do not throw away a pet already in our hands.
        -- Finish banking/recovery first, then Titanic takes over.
        if Extra.isCarrying()
            or Extra.isBeingChased()
        then
            titanicOverrideRequested =
                true

            return
        end

        titanicOverrideRequested =
            false

        titanicResumeActivity =
            currentActivity

        if activityDeadline then
            titanicResumeRemaining =
                math.max(
                    0,
                    activityDeadline
                        - os.clock()
                )
        else
            titanicResumeRemaining =
                nil
        end

        titanicOverrideActive =
            true

        local state =
            Extra.getTitanicState()

        titanicOverrideSpawnId =
            state.SpawnId

        Extra.log(
            "TITANIC OVERRIDE START",
            "| Previous:",
            titanicResumeActivity,
            "| SpawnId:",
            titanicOverrideSpawnId
        )

        -- Titanic can pull us off the treadmill even if Auto Farm itself
        -- is not enabled. This temporary Farm activity exists only to
        -- attack the Titanic event egg.
        if currentActivity ~= "Farm" then
            Extra.setActivity("Farm")
        else
            autoFarmActive = true
            activityDeadline = nil
            Extra.startAutoFarm()
        end

        activityDeadline = nil
    end

    function Extra.restoreAfterTitanic()
        if not titanicOverrideActive then
            titanicOverrideRequested =
                false

            return
        end

        titanicOverrideActive =
            false

        local resumeActivity =
            titanicResumeActivity

        local resumeRemaining =
            titanicResumeRemaining

        titanicResumeActivity = nil
        titanicResumeRemaining = nil
        titanicOverrideRequested = false

        Extra.clearTitanicLock()

        local desired

        -- Titanic always has absolute priority. When it ends, resume the
        -- exact activity that was interrupted so the Farm/Treadmill timer
        -- cycle continues naturally.
        if resumeActivity == "Farm"
            and autoFarmEnabled
        then
            desired = "Farm"

        elseif resumeActivity == "Treadmill"
            and autoTreadmillEnabled
        then
            desired = "Treadmill"

        elseif autoFarmEnabled then
            desired = "Farm"

        elseif autoTreadmillEnabled then
            desired = "Treadmill"

        else
            desired = nil
        end

        Extra.log(
            "TITANIC OVERRIDE END",
            "| Resume:",
            desired
        )

        Extra.setActivity(desired)

        if desired
            and resumeActivity == desired
            and resumeRemaining
            and resumeRemaining > 0
            and Extra.otherActivityEnabled(
                desired
            )
        then
            activityDeadline =
                os.clock()
                + resumeRemaining
        end
    end

    -- Priority coordinator.
    --
    -- Activity priority:
    -- 1. Already-carried pet recovery/banking (safety)
    -- 2. Titanic Egg
    -- 3. Current Farm/Treadmill timed activity
    --
    -- If Auto Farm + Auto Treadmill are both enabled, they alternate using
    -- the configured Farm Timer and Treadmill Timer.
    task.spawn(function()
        while not Window.Destroyed do
            local state =
                Extra.getTitanicState()

            local titanicTargetExists =
                false

            -- Titanic priority is standalone: it can temporarily start Farm
            -- even when Auto Farm and Auto Treadmill are both OFF.
            if prioritizeTitanicEgg then
                local target =
                    Extra.findTitanicEgg()

                titanicTargetExists =
                    target ~= nil
            end

            if titanicTargetExists then
                if not titanicOverrideActive then
                    Extra.beginTitanicOverride()
                end

            elseif titanicOverrideActive then
                -- The Titanic egg is gone/broken. Return to the exact activity
                -- that was interrupted and restore its remaining timer.
                Extra.restoreAfterTitanic()

            elseif titanicOverrideRequested
                and not Extra.isCarrying()
                and not Extra.isBeingChased()
            then
                -- We were waiting for a carried pet to finish banking.
                local target =
                    prioritizeTitanicEgg
                    and Extra.findTitanicEgg()
                    or nil

                if target then
                    Extra.beginTitanicOverride()
                else
                    titanicOverrideRequested =
                        false
                end
            end

            -- Normal Farm/Treadmill behavior:
            -- Titanic > active timed activity.
            --
            -- If both Auto Farm and Auto Treadmill are ON, alternate using
            -- their configured timers:
            -- Farm timer expires -> Treadmill
            -- Treadmill timer expires -> Farm
            --
            -- If only one is enabled, stay on that activity.
            if not titanicOverrideActive
                and not titanicOverrideRequested
                and not Extra.isCarrying()
                and not Extra.isBeingChased()
            then
                if currentActivity == nil then
                    if autoFarmEnabled then
                        Extra.setActivity("Farm")
                    elseif autoTreadmillEnabled then
                        Extra.setActivity("Treadmill")
                    end

                elseif currentActivity == "Farm" then
                    if not autoFarmEnabled then
                        if autoTreadmillEnabled then
                            Extra.setActivity("Treadmill")
                        else
                            Extra.setActivity(nil)
                        end
                    elseif autoTreadmillEnabled
                        and activityDeadline
                        and os.clock() >= activityDeadline
                    then
                        Extra.setActivity("Treadmill")
                    end

                elseif currentActivity == "Treadmill" then
                    if not autoTreadmillEnabled then
                        if autoFarmEnabled then
                            Extra.setActivity("Farm")
                        else
                            Extra.setActivity(nil)
                        end
                    elseif autoFarmEnabled
                        and activityDeadline
                        and os.clock() >= activityDeadline
                    then
                        Extra.setActivity("Farm")
                    end
                end
            end

            task.wait(0.1)
        end
    end)

    function Extra.logTitanicEventState()
        local state =
            Extra.getTitanicState()

        local physicalTarget =
            prioritizeTitanicEgg
            and Extra.findTitanicEgg()
            or nil

        if state.Active
            or physicalTarget
        then
            Extra.log(
                "Titanic ACTIVE",
                "| Egg:",
                state.EggName,
                "| Zone:",
                state.ZoneIndex,
                "| EndsAt:",
                state.EndsAt,
                "| SpawnId:",
                state.SpawnId,
                "| Admin:",
                state.SpawnByAdmin
            )
        else
            Extra.log(
                "Titanic waiting",
                "| NextAt:",
                state.NextAt,
                "| SpawnId:",
                state.SpawnId
            )
        end
    end

    for _, attributeName
        in ipairs({
            "TitanicNextAt",
            "TitanicEggName",
            "TitanicZoneIndex",
            "TitanicEndsAt",
            "TitanicSpawnId",
            "TitanicSpawnByAdmin"
        })
    do
        Workspace:
        GetAttributeChangedSignal(
            attributeName
        ):
        Connect(function()
            Extra.logTitanicEventState()
        end)
    end

    task.spawn(function()
        while not Window.Destroyed do
            if currentActivity == "Farm"
                and autoFarmEnabled
                and autoFarmActive
                and not farmLoopRunning
            then
                Extra.startAutoFarm()
            end

            if currentActivity == "Treadmill"
                and autoTreadmillEnabled
                and autoTreadmillActive
                and not treadmillLoopRunning
            then
                Extra.startAutoTreadmill()
            end

            task.wait(0.5)
        end
    end)

    AnimalBankedRemote.OnClientEvent:
    Connect(function()
        Extra.onPetInventoryChanged()
    end)

    task.spawn(function()
        local boundPlot
        local plotConnections = {}

        local function clearPlotConnections()
            for _, connection
                in ipairs(
                    plotConnections
                )
            do
                pcall(function()
                    connection:
                        Disconnect()
                end)
            end

            table.clear(
                plotConnections
            )
        end

        local function bindPlot(
            plot
        )
            if plot == boundPlot then
                return
            end

            clearPlotConnections()

            boundPlot =
                plot

            if not plot then
                return
            end

            for _, attributeName
                in ipairs({
                    "MaxAnimals",
                    "PlotLevel",
                    "BuildLevel"
                })
            do
                table.insert(
                    plotConnections,
                    plot:
                    GetAttributeChangedSignal(
                        attributeName
                    ):
                    Connect(function()
                        if Extra.equipBestPetEnabled then
                            task.delay(
                                0.25,
                                Extra.equipBestPet
                            )
                        end
                    end)
                )
            end
        end

        while not Window.Destroyed do
            bindPlot(
                Extra.getOwnedPlotExact()
            )

            task.wait(1)
        end

        clearPlotConnections()
    end)

    function Extra.isBackpackSellConfig(
        object
    )
        if type(object) ~= "table" then
            return false
        end

        local ok,
            remoteName,
            animalToolTag,
            toolValue,
            petValue =
            pcall(function()
                return
                    rawget(
                        object,
                        "RemoteName"
                    ),
                    rawget(
                        object,
                        "AnimalToolTag"
                    ),
                    rawget(
                        object,
                        "ToolValue"
                    ),
                    rawget(
                        object,
                        "PetValue"
                    )
            end)

        if not ok then
            return false
        end

        return
            remoteName
                == "BackpackSellRemote"
            and animalToolTag
                == "AnimalTool"
            and type(toolValue)
                == "function"
            and type(petValue)
                == "function"
    end

    function Extra.getBackpackSellConfig()
        local cached =
            Extra.backpackSellConfig

        if Extra.isBackpackSellConfig(
            cached
        ) then
            return cached
        end

        if type(getgc) ~= "function" then
            return nil
        end

        local ok,
            objects =
            pcall(
                getgc,
                true
            )

        if not ok
            or type(objects)
                ~= "table"
        then
            return nil
        end

        -- Fast path: some executors expose the config table itself.
        for _, object
            in ipairs(objects)
        do
            if Extra.isBackpackSellConfig(
                object
            ) then
                Extra.backpackSellConfig =
                    object

                local seconds

                pcall(function()
                    seconds =
                        rawget(
                            object,
                            "PetIncomeSeconds"
                        )
                end)

                Extra.log(
                    "Backpack sell config found (table)",
                    "| PetIncomeSeconds:",
                    seconds
                )

                return object
            end
        end

        -- Reliable path for this game: BackpackSellController keeps the config
        -- table as an upvalue of its controller functions.
        local getUpvaluesFn =
            rawget(
                getgenv and getgenv()
                    or _G,
                "getupvalues"
            )
            or getupvalues

        if type(getUpvaluesFn)
            ~= "function"
        then
            return nil
        end

        for _, object
            in ipairs(objects)
        do
            if type(object)
                == "function"
            then
                local okUp,
                    upvalues =
                    pcall(
                        getUpvaluesFn,
                        object
                    )

                if okUp
                    and type(upvalues)
                        == "table"
                then
                    for _,
                        upvalue
                        in pairs(
                            upvalues
                        )
                    do
                        if Extra.isBackpackSellConfig(
                            upvalue
                        ) then
                            Extra.backpackSellConfig =
                                upvalue

                            local seconds

                            pcall(function()
                                seconds =
                                    rawget(
                                        upvalue,
                                        "PetIncomeSeconds"
                                    )
                            end)

                            Extra.log(
                                "Backpack sell config found (upvalue)",
                                "| PetIncomeSeconds:",
                                seconds
                            )

                            return upvalue
                        end
                    end
                end
            end
        end

        return nil
    end

    function Extra.getSellablePetIncome(
        tool
    )
        if not tool
            or not tool:IsA("Tool")
        then
            return nil
        end

        local config =
            Extra.getBackpackSellConfig()

        if not config then
            return nil
        end

        local isSellable =
            rawget(
                config,
                "IsSellable"
            )

        if type(isSellable)
            == "function"
        then
            local okSellable,
                sellable =
                pcall(
                    isSellable,
                    tool
                )

            if not okSellable
                or sellable ~= true
            then
                return nil
            end
        elseif not CollectionService:
            HasTag(
                tool,
                "AnimalTool"
            )
        then
            return nil
        end

        local animalName =
            tool:GetAttribute(
                "AnimalName"
            )

        local weightKg =
            tonumber(
                tool:GetAttribute(
                    "WeightKg"
                )
            )

        local sizeMult =
            tonumber(
                tool:GetAttribute(
                    "SizeMult"
                )
            )

        -- The game's real pet income function was traced from
        -- ReplicatedStorage.Shared.EggRewards:
        -- PlacedCashPerSecond(name, kg, sizeMult, ...)
        -- The first three arguments are sufficient for normal pets.
        if animalName
            and weightKg
            and sizeMult
            and type(
                EggRewards.PlacedCashPerSecond
            ) == "function"
        then
            local okIncome,
                income =
                pcall(
                    EggRewards.PlacedCashPerSecond,
                    animalName,
                    weightKg,
                    sizeMult
                )

            income =
                okIncome
                and tonumber(income)
                or nil

            if income
                and income >= 0
            then
                Extra.log(
                    "Auto Sell income:",
                    animalName,
                    "| Kg:",
                    weightKg,
                    "| Size:",
                    sizeMult,
                    "| Income/s:",
                    income,
                    "| Method: PlacedCashPerSecond"
                )

                return income
            end
        end

        -- Compatibility fallback: use the game's ToolValue calculation
        -- on the real tagged Tool, then convert sell value back to income/s.
        local toolValue =
            rawget(
                config,
                "ToolValue"
            )

        if type(toolValue)
            ~= "function"
        then
            return nil
        end

        local ok,
            result =
            pcall(
                toolValue,
                tool
            )

        if not ok then
            Extra.log(
                "ToolValue failed:",
                tool.Name,
                result
            )

            return nil
        end

        local value =
            tonumber(result)

        if not value
            and type(result)
                == "table"
        then
            value =
                tonumber(
                    result.Value
                    or result.SellValue
                    or result.Cash
                    or result.Amount
                )
        end

        if not value then
            return nil
        end

        local seconds =
            tonumber(
                rawget(
                    config,
                    "PetIncomeSeconds"
                )
            )
            or 60

        if seconds <= 0 then
            return nil
        end

        local income =
            value / seconds

        Extra.log(
            "Auto Sell income:",
            animalName
                or tool.Name,
            "| Income/s:",
            income,
            "| Method: ToolValue/"
                .. tostring(seconds)
        )

        return income
    end

    function Extra.collectAutoSellTools()
        local threshold =
            tonumber(
                Extra.autoSellBelowIncome
            )
            or 0

        if threshold <= 0 then
            return {}
        end

        local config =
            Extra.getBackpackSellConfig()

        if not config then
            return {}
        end

        local maxPerRequest =
            tonumber(
                rawget(
                    config,
                    "MaxPerRequest"
                )
            )
            or 200

        maxPerRequest =
            math.max(
                1,
                math.floor(
                    maxPerRequest
                )
            )

        local selected = {}
        local seen = {}

        local function scan(
            container
        )
            if not container then
                return
            end

            for _, tool
                in ipairs(
                    container:GetChildren()
                )
            do
                if #selected
                    >= maxPerRequest
                then
                    return
                end

                if tool:IsA("Tool")
                    and not seen[tool]
                then
                    seen[tool] = true

                    local income =
                        Extra.getSellablePetIncome(
                            tool
                        )

                    if income ~= nil then
                        local animalName =
                            tool:GetAttribute(
                                "AnimalName"
                            )
                            or tool.Name

                        if income < threshold then
                            table.insert(
                                selected,
                                tool
                            )

                            Extra.log(
                                "Auto Sell candidate:",
                                animalName,
                                "| Income/s:",
                                income,
                                "| Threshold:",
                                threshold
                            )
                        else
                            Extra.log(
                                "Auto Sell keep:",
                                animalName,
                                "| Income/s:",
                                income,
                                "| Threshold:",
                                threshold
                            )
                        end
                    end
                end
            end
        end

        scan(
            LocalPlayer:
            FindFirstChildOfClass(
                "Backpack"
            )
            or LocalPlayer:
            FindFirstChild(
                "Backpack"
            )
        )

        scan(
            LocalPlayer.Character
        )

        return selected
    end

    function Extra.runAutoSell(
        force
    )
        if not Extra.autoSellEnabled
            or Window.Destroyed
        then
            return
        end

        local threshold =
            tonumber(
                Extra.autoSellBelowIncome
            )
            or 0

        if threshold <= 0 then
            return
        end

        if force then
            Extra.autoSellBusy =
                false
            Extra.lastAutoSellAt =
                0
        end

        if Extra.autoSellBusy then
            return
        end

        if not Extra.getBackpackSellConfig() then
            if not Extra.autoSellConfigWarned then
                Extra.autoSellConfigWarned =
                    true

                warn(
                    "[CHLISE HUB][AUTO SELL][V5] BackpackSellConfig not found."
                )
            end

            return
        end

        Extra.autoSellConfigWarned =
            false

        if not force
            and os.clock()
                - Extra.lastAutoSellAt
                < 1
        then
            return
        end

        local tools =
            Extra.collectAutoSellTools()

        if #tools == 0 then
            Extra.lastAutoSellAt =
                os.clock()
            return
        end

        local validTools = {}

        for _, tool
            in ipairs(
                tools
            )
        do
            if tool
                and tool.Parent
                and tool:IsA(
                    "Tool"
                )
            then
                table.insert(
                    validTools,
                    tool
                )
            end
        end

        if #validTools == 0 then
            Extra.lastAutoSellAt =
                os.clock()
            return
        end

        Extra.autoSellBusy =
            true

        Extra.lastAutoSellAt =
            os.clock()

        local requestToken =
            os.clock()

        Extra.autoSellRequestToken =
            requestToken

        Extra.log(
            "Auto Sell request:",
            #validTools,
            "tool(s)",
            "| Threshold:",
            threshold
        )

        -- Fail-safe: a RemoteFunction call should never permanently lock
        -- the Auto Sell worker if the server does not answer.
        task.delay(
            3,
            function()
                if Extra.autoSellRequestToken
                    == requestToken
                then
                    Extra.autoSellBusy =
                        false
                end
            end
        )

        task.spawn(function()
            local ok,
                result =
                pcall(function()
                    return
                        BackpackSellRemote:
                        InvokeServer(
                            validTools
                        )
                end)

            if Extra.autoSellRequestToken
                == requestToken
            then
                Extra.autoSellBusy =
                    false
                Extra.autoSellRequestToken =
                    nil
            end

            if ok then
                Extra.log(
                    "Auto Sell success:",
                    #validTools,
                    "pet(s)",
                    "| Server:",
                    result
                )

                task.delay(
                    0.2,
                    function()
                        if Extra.equipBestPetEnabled then
                            Extra.equipBestPet()
                        end

                        if Extra.autoClaimIndex then
                            Extra.claimAllIndex()
                        end

                        -- Immediately scan again because one server request
                        -- can be capped and new pets may have appeared.
                        if Extra.autoSellEnabled then
                            Extra.runAutoSell(
                                true
                            )
                        end
                    end
                )
            else
                warn(
                    "[CHLISE HUB][AUTO SELL][V5] InvokeServer failed:",
                    result
                )
            end
        end)
    end

    function Extra.queueAutoSell(
        delaySeconds
    )
        if not Extra.autoSellEnabled
            or Extra.autoSellBelowIncome
                <= 0
        then
            return
        end

        task.delay(
            delaySeconds
                or 0.1,
            function()
                if Extra.autoSellEnabled
                    and not Window.Destroyed
                then
                    Extra.runAutoSell(
                        true
                    )
                end
            end
        )
    end

    task.spawn(function()
        while not Window.Destroyed do
            if Extra.autoSellEnabled
                and Extra.autoSellBelowIncome
                    > 0
            then
                Extra.runAutoSell()
            end

            task.wait(0.75)
        end
    end)

    task.spawn(function()
        local backpack =
            LocalPlayer:
            FindFirstChildOfClass(
                "Backpack"
            )
            or LocalPlayer:
            WaitForChild(
                "Backpack"
            )

        if backpack then
            backpack.ChildAdded:
            Connect(function(child)
                if child:IsA("Tool")
                    and Extra.autoSellEnabled
                then
                    Extra.queueAutoSell(
                        0.15
                    )
                end
            end)
        end

        local function bindCharacter(
            character
        )
            character.ChildAdded:
            Connect(function(child)
                if child:IsA("Tool")
                    and Extra.autoSellEnabled
                then
                    Extra.queueAutoSell(
                        0.15
                    )
                end
            end)
        end

        if LocalPlayer.Character then
            bindCharacter(
                LocalPlayer.Character
            )
        end

        LocalPlayer.CharacterAdded:
        Connect(
            bindCharacter
        )
    end)

    -- UI - uses the same template/API as Ride A Pet.
    local FarmTab =
        Window:AddTab(
            "FARM",
            "◆"
        )

    local SettingsTab =
        Window.Tabs
        and Window.Tabs["SETTINGS"]

    if not SettingsTab then
        SettingsTab =
            Window:AddTab(
                "SETTINGS",
                "⚙"
            )
    end

    local FarmSection =
        Window:AddSection(
            FarmTab,
            "Break & Steal"
        )

    FarmSection:AddDropdown(
        "BSAEZones",
        "Zone Selection",
        ZONE_OPTIONS,
        true,
        selectedZones,

        function(value)
            selectedZones =
                Extra.decodeSelection(
                    value,
                    zoneLabels
                )

            if Extra.autoNextZoneEnabled then
                Extra.autoNextZoneSafeZone =
                    nil
                Extra.autoNextZoneTrialZone =
                    nil
                Extra.autoNextZoneBlockedZone =
                    nil
                Extra.autoNextZoneBlockedPickaxeTier =
                    nil
                Extra.autoNextZoneTrialHits =
                    0
                Extra.autoNextZonePromotedPickaxeTier =
                    nil

                Extra.initializeAutoNextZone()
            end
        end
    )

    FarmSection:AddDropdown(
        "BSAEEggs",
        "Egg Selection",
        MASTER_EGGS,
        true,
        selectedEggs,

        function(value)
            selectedEggs = Extra.decodeSelection(value, eggLabels)
        end
    )

    FarmSection:AddToggle(
        "BSAEPrioritizeTitanic",
        "Prioritize Titanic Egg",
        true,

        function(state)
            prioritizeTitanicEgg =
                state == true

            if not prioritizeTitanicEgg then
                Extra.clearTitanicLock()

                if titanicOverrideActive then
                    Extra.restoreAfterTitanic()
                end
            end

            local titanicState =
                Extra.getTitanicState()

            Extra.log(
                "Prioritize Titanic:",
                prioritizeTitanicEgg,
                "| Active:",
                titanicState.Active,
                "| NextAt:",
                titanicState.NextAt
            )
        end
    )

    FarmSection:AddToggle(
        "BSAEAutoNextZone",
        "Auto Next Zone",
        false,

        function(state)
            Extra.autoNextZoneEnabled =
                state == true

            Extra.autoNextZoneSafeZone =
                nil
            Extra.autoNextZoneTrialZone =
                nil
            Extra.autoNextZoneBlockedZone =
                nil
            Extra.autoNextZoneBlockedPickaxeTier =
                nil
            Extra.autoNextZoneTrialHits =
                0
            Extra.autoNextZonePromotedPickaxeTier =
                nil

            if Extra.autoNextZoneEnabled then
                Extra.initializeAutoNextZone()

                Extra.log(
                    "Auto Next Zone ON",
                    "| Start:",
                    Extra.autoNextZoneSafeZone
                )
            else
                Extra.log(
                    "Auto Next Zone OFF"
                )
            end
        end
    )

    FarmSection:AddToggle(
        "BSAEAutoSteal",
        "Auto Steal Carried Pet",
        false,

        function(state)
            Extra.autoStealEnabled =
                state == true

            if Extra.autoStealEnabled then
                Extra.runAutoStealWorker()

                Extra.log(
                    "Auto Steal ON"
                )
            else
                Extra.autoStealBusy =
                    false

                Extra.log(
                    "Auto Steal OFF"
                )
            end
        end
    )

    FarmSection:AddDropdown(
        "BSAEPetFilter",
        "Pet Filter",
        MASTER_PETS,
        true,
        selectedPets,

        function(value)
            selectedPets = Extra.decodeSelection(value, petLabels)
        end
    )

    FarmSection:AddDropdown(
        "BSAEMovementMode",
        "Movement Mode",
        {
            "Walk",
            "Tween",
            "Teleport"
        },
        false,
        movementMode,

        function(value)
            if value == "Walk"
                or value == "Tween"
                or value == "Teleport"
            then
                movementMode = value
                Extra.log("Movement mode changed:", movementMode)
            end
        end
    )

    FarmSection:AddTextbox(
        "BSAEMinimumPetIncome",
        "Minimum Pet Income/s",
        "Empty / 0 = Off",

        function(value)
            local parsed =
                Extra.parseCompactNumber(
                    value
                )

            if parsed
                and parsed > 0
            then
                Extra.minimumPetIncome =
                    parsed
            else
                Extra.minimumPetIncome =
                    0
            end

            Extra.log(
                "Minimum Pet Income/s:",
                Extra.minimumPetIncome > 0
                    and Extra.minimumPetIncome
                    or "OFF"
            )
        end
    )

    FarmSection:AddTextbox(
        "BSAEFarmTimer",
        "Auto Farm Timer",
        "10",

        function(value)
            local normalized =
                (
                    tostring(value or ""):
                    gsub(",", ".")
                )

            local parsed =
                tonumber(normalized)

            if parsed and parsed > 0 then
                farmTimerValue =
                    parsed

                if currentActivity
                    == "Farm"
                then
                    Extra.refreshActivityDeadline()
                end
            end
        end
    )

    FarmSection:AddDropdown(
        "BSAEFarmTimerUnit",
        "Farm Timer Unit",
        {
            "Minutes",
            "Hours"
        },
        false,
        farmTimerUnit,

        function(value)
            if value == "Minutes"
                or value == "Hours"
            then
                farmTimerUnit =
                    value

                if currentActivity
                    == "Farm"
                then
                    Extra.refreshActivityDeadline()
                end
            end
        end
    )

    FarmSection:AddToggle(
        "BSAEAutoFarm",
        "Auto Break & Steal",
        false,

        function(state)
            autoFarmEnabled =
                state

            if state then
                local homeHitbox =
                    Extra.getOwnedPlotHitbox()

                if homeHitbox then
                    Extra.log(
                        "Owned plot:",
                        homeHitbox:GetFullName(),
                        "| WalkSpeed:",
                        Extra.getCurrentMoveSpeed(),
                        "| PetFilters:",
                        #MASTER_PETS
                    )
                else
                    warn(
                        "[CHLISE HUB] Owned plot was not detected yet."
                    )
                end

                -- Farm is always the first phase whenever Auto Farm is ON.
                -- This also makes autoload order irrelevant: if Treadmill was
                -- enabled first, enabling Farm immediately switches to Farm.
                Extra.setActivity("Farm")
            else
                if currentActivity == "Farm" then
                    if autoTreadmillEnabled then
                        Extra.setActivity(
                            "Treadmill"
                        )
                    else
                        Extra.setActivity(nil)
                    end
                else
                    Extra.refreshActivityDeadline()
                end
            end
        end
    )

    local TreadmillSection =
        Window:AddSection(
            FarmTab,
            "Treadmill"
        )

    TreadmillSection:AddTextbox(
        "BSAETreadmillTimer",
        "Auto Treadmill Timer",
        "10",

        function(value)
            local normalized =
                (
                    tostring(value or ""):
                    gsub(",", ".")
                )

            local parsed =
                tonumber(normalized)

            if parsed and parsed > 0 then
                treadmillTimerValue =
                    parsed

                if currentActivity
                    == "Treadmill"
                then
                    Extra.refreshActivityDeadline()
                end
            end
        end
    )

    TreadmillSection:AddDropdown(
        "BSAETreadmillTimerUnit",
        "Treadmill Timer Unit",
        {
            "Minutes",
            "Hours"
        },
        false,
        treadmillTimerUnit,

        function(value)
            if value == "Minutes"
                or value == "Hours"
            then
                treadmillTimerUnit =
                    value

                if currentActivity
                    == "Treadmill"
                then
                    Extra.refreshActivityDeadline()
                end
            end
        end
    )

    TreadmillSection:AddToggle(
        "BSAEAutoTreadmill",
        "Auto Treadmill",
        false,

        function(state)
            autoTreadmillEnabled =
                state

            if state then
                -- If Farm is also enabled, Farm must always be the first phase.
                -- Treadmill waits until the Farm timer expires.
                if autoFarmEnabled then
                    if currentActivity ~= "Farm" then
                        Extra.setActivity("Farm")
                    else
                        Extra.refreshActivityDeadline()
                    end
                else
                    Extra.setActivity("Treadmill")
                end
            else
                if currentActivity
                    == "Treadmill"
                then
                    if autoFarmEnabled then
                        Extra.setActivity("Farm")
                    else
                        Extra.setActivity(nil)
                    end
                else
                    Extra.refreshActivityDeadline()
                end
            end
        end
    )

    local UpgradeSection =
        Window:AddSection(
            FarmTab,
            "Upgrades"
        )

    UpgradeSection:AddToggle(
        "BSAEAutoUpgradePen",
        "Auto Upgrade Pen",
        false,

        function(state)
            autoUpgradePen =
                state == true

            if autoUpgradePen then
                penUpgradeRetryAt = 0
                Extra.runAutoUpgradePen()
            end
        end
    )

    UpgradeSection:AddToggle(
        "BSAEAutoUpgradeTreadmill",
        "Auto Upgrade Treadmill",
        false,

        function(state)
            autoUpgradeTreadmill =
                state == true

            if autoUpgradeTreadmill then
                treadmillUpgradeRetryAt = 0
                Extra.runAutoUpgradeTreadmill()
            end
        end
    )

    UpgradeSection:AddToggle(
        "BSAEAutoBuyPickaxe",
        "Auto Buy Pickaxe",
        false,

        function(state)
            Extra.autoBuyPickaxe =
                state == true

            if Extra.autoBuyPickaxe then
                Extra.pickaxeBuyRetryAt = 0
                Extra.runAutoBuyPickaxe()
            end
        end
    )

    UpgradeSection:AddToggle(
        "BSAEAutoBuyTrail",
        "Auto Buy Trail",
        false,

        function(state)
            Extra.autoBuyTrail =
                state == true

            if Extra.autoBuyTrail then
                Extra.trailBuyRetryAt = 0
                Extra.runAutoBuyTrail()
            end
        end
    )

    UpgradeSection:AddToggle(
        "BSAEEquipBestPet",
        "Equip Best Pet",
        false,

        function(state)
            Extra.equipBestPetEnabled =
                state == true

            if Extra.equipBestPetEnabled then
                Extra.lastEquipBestPetAt = 0
                Extra.equipBestPet()
            end
        end
    )

    UpgradeSection:AddToggle(
        "BSAEAutoClaimIndex",
        "Auto Claim Index",
        false,

        function(state)
            Extra.autoClaimIndex =
                state == true

            if Extra.autoClaimIndex then
                Extra.lastAutoClaimIndexAt = 0
                Extra.claimAllIndex()
            end
        end
    )

    local SellSection =
        Window:AddSection(
            FarmTab,
            "Sell"
        )

    SellSection:AddTextbox(
        "BSAEAutoSellIncome",
        "Sell Below Income/s",
        "Empty / 0 = Off",

        function(value)
            local parsed = Extra.parseCompactNumber(value)

            if parsed and parsed > 0 then
                Extra.autoSellBelowIncome = parsed
            else
                Extra.autoSellBelowIncome = 0
            end

            Extra.log(
                "Auto Sell Below Income/s:",
                Extra.autoSellBelowIncome > 0
                    and Extra.autoSellBelowIncome
                    or "OFF"
            )

            if Extra.autoSellEnabled then
                Extra.autoSellBusy =
                    false
                Extra.lastAutoSellAt =
                    0
                Extra.queueAutoSell(
                    0.05
                )
            end
        end
    )

    SellSection:AddToggle(
        "BSAEAutoSell",
        "Auto Sell",
        false,

        function(state)
            Extra.autoSellEnabled =
                state == true

            Extra.autoSellBusy =
                false
            Extra.autoSellRequestToken =
                nil
            Extra.lastAutoSellAt =
                0

            if Extra.autoSellEnabled then
                Extra.queueAutoSell(
                    0.05
                )
            end
        end
    )

    Extra.bindCompactIncomeTextbox(
        "Minimum Pet Income/s",
        function()
            return
                Extra.minimumPetIncome
        end
    )

    Extra.bindCompactIncomeTextbox(
        "Sell Below Income/s",
        function()
            return
                Extra.autoSellBelowIncome
        end
    )

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
            debugEnabled = state
        end
    )

    print("[CHLISE HUB] Break and Steal an Egg loaded.")
    print(
        "[CHLISE HUB] GameId:",
        game.GameId,
        "| PlaceId:",
        game.PlaceId
    )
end
