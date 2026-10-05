-- Chlise Hub - Games/BreakAndStealAnEgg.lua
-- GameId: 10765288803
-- PlaceId: 114326934417838
-- Added: Auto Treadmill + alternating Farm/Treadmill timers
-- Added: Titanic Egg event detection/prioritization via Workspace attributes
-- Pipeline: unlimited pending hatch queue (A -> B -> C -> D ... without waiting)
-- Titanic: absolute priority over treadmill, timers, filters, normal eggs, and normal pending hatches
-- Titanic detection: physical spawned egg fallback works even when Workspace event attributes are stale/missing
-- Upgrades: event-driven Auto Upgrade Pen/Treadmill; only requests when Cash is sufficient
-- Shop: event-driven Auto Buy Pickaxe/Trail with confirmation + anti-spam
-- Recovery: robust dropped-pet reacquire using HatchId + name/zone/weight fallback
-- Farm state: self-recovers if activity says Farm but worker stopped
-- Return home: dynamically targets Workspace.Build.ZoneHitboxes.SafeZone; uses current WalkSpeed

return function(Context)
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

    local Build = Workspace:WaitForChild(ZonesConfig.BuildFolderName or "Build")
    local ZoneBuilds = Build:WaitForChild(ZonesConfig.ZoneBuildsName or "ZoneBuilds")
    local Pickups = Workspace:WaitForChild("AnimalPickups")
    local CollectionService = game:GetService("CollectionService")

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

    local autoBuyPickaxe = false
    local autoBuyTrail = false

    local pickaxeBuyWorkerRunning = false
    local trailBuyWorkerRunning = false

    local pickaxeBuyRetryAt = 0
    local trailBuyRetryAt = 0

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
    local minimumPetWeight = 0

    local prioritizeTitanicEgg = true

    local movementMode = "Walk"

    local function log(...)
        if debugEnabled then
            print("[CHLISE HUB][BREAK & STEAL]", ...)
        end
    end

    local function getCharacter()
        local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
        local humanoid = character:WaitForChild("Humanoid")
        local hrp = character:WaitForChild("HumanoidRootPart")
        return character, humanoid, hrp
    end

    local function getCurrentMoveSpeed()
        local _, humanoid = getCharacter()

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
    local function selectionEmpty(selection)
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

    local function isSelected(selection, wanted)
        if selectionEmpty(selection) then
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

    local function normalizeZone(value)
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
    local function displayName(raw)
        local name = (EggRewards.DisplayNames or {})[raw] or tostring(raw)
        name = name:gsub("_", " "):gsub("(%l)(%u)", "%1 %2")
            :gsub("(%u)(%u%l)", "%1 %2")
        return (name:gsub("%S+", function(word)
            if word == "T-Rex" then return word end
            return word:sub(1, 1):upper() .. word:sub(2):lower()
        end))
    end

    local function decodeSelection(value, labels)
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

    local function buildPetList()
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
                raw = raw, name = displayName(raw),
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

    local MASTER_PETS = buildPetList()

    -- Owned plot / home
    local function getOwnedPlotHitbox()
        local hitbox = SafeZoneQuery.GetOwnedPlotHitbox(LocalPlayer.UserId)

        if hitbox and hitbox.Parent and hitbox:IsA("BasePart") then
            return hitbox
        end

        return nil
    end

    local function isBankablePosition(position)
        local ok, result = pcall(function()
            return SafeZoneQuery.IsBankable(LocalPlayer.UserId, position)
        end)

        return ok and result == true
    end

    local function durationToSeconds(value, unit)
        local amount = tonumber(value)

        if not amount or amount <= 0 then
            return nil
        end

        if unit == "Hours" then
            return amount * 3600
        end

        return amount * 60
    end

    local function getActivityDuration(activity)
        if activity == "Farm" then
            return durationToSeconds(
                farmTimerValue,
                farmTimerUnit
            )
        end

        if activity == "Treadmill" then
            return durationToSeconds(
                treadmillTimerValue,
                treadmillTimerUnit
            )
        end

        return nil
    end

    local function otherActivityEnabled(activity)
        if activity == "Farm" then
            return autoTreadmillEnabled
        end

        if activity == "Treadmill" then
            return autoFarmEnabled
        end

        return false
    end

    local function refreshActivityDeadline()
        if not currentActivity
            or not otherActivityEnabled(currentActivity)
        then
            activityDeadline = nil
            return
        end

        local duration =
            getActivityDuration(currentActivity)

        if duration then
            activityDeadline =
                os.clock() + duration
        else
            activityDeadline = nil
        end
    end

    local function getOwnedPlot()
        local hitbox =
            getOwnedPlotHitbox()

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
    local function getOwnedPlotExact()
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

    local function getCash()
        return
            tonumber(
                LocalPlayer:GetAttribute(
                    "Cash"
                )
            )
            or 0
    end

    local function getNextPenUpgradeCost(
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

    local function getNextTreadmillUpgradeCost(
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

    local function waitForUpgradeLevel(
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

    local function runAutoUpgradePen()
        if penUpgradeWorkerRunning then
            return
        end

        penUpgradeWorkerRunning = true

        task.spawn(function()
            while autoUpgradePen
                and not Window.Destroyed
            do
                local plot =
                    getOwnedPlotExact()

                if not plot then
                    break
                end

                local cost, level =
                    getNextPenUpgradeCost(
                        plot
                    )

                if not cost then
                    log(
                        "Auto Upgrade Pen:",
                        "MAX LEVEL",
                        "| Level:",
                        level
                    )

                    break
                end

                local cash =
                    getCash()

                if cash < cost then
                    log(
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

                log(
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
                    waitForUpgradeLevel(
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

                    log(
                        "Auto Upgrade Pen:",
                        "no level confirmation; cooldown 10s"
                    )

                    break
                end

                penUpgradeRetryAt = 0

                log(
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

    local function runAutoUpgradeTreadmill()
        if treadmillUpgradeWorkerRunning then
            return
        end

        treadmillUpgradeWorkerRunning = true

        task.spawn(function()
            while autoUpgradeTreadmill
                and not Window.Destroyed
            do
                local plot =
                    getOwnedPlotExact()

                if not plot then
                    break
                end

                if plot:GetAttribute(
                    "TreadmillUnlocked"
                ) ~= true
                then
                    log(
                        "Auto Upgrade Treadmill:",
                        "treadmill is locked"
                    )

                    break
                end

                local cost, level =
                    getNextTreadmillUpgradeCost(
                        plot
                    )

                if not cost then
                    log(
                        "Auto Upgrade Treadmill:",
                        "MAX LEVEL",
                        "| Level:",
                        level
                    )

                    break
                end

                local cash =
                    getCash()

                if cash < cost then
                    log(
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

                log(
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
                    waitForUpgradeLevel(
                        plot,
                        "TreadmillLevel",
                        level,
                        5
                    )

                if not confirmed then
                    treadmillUpgradeRetryAt =
                        os.clock() + 10

                    log(
                        "Auto Upgrade Treadmill:",
                        "no level confirmation; cooldown 10s"
                    )

                    break
                end

                treadmillUpgradeRetryAt = 0

                log(
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

    local function parseOwnedTrails()
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

    local function getNextPickaxePurchase()
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

    local function getNextTrailPurchase()
        local owned =
            parseOwnedTrails()

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

    local function waitForPickaxeTier(
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

    local function waitForTrailOwned(
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
                parseOwnedTrails()

            if owned[
                trailId
            ] then
                return true
            end

            task.wait(0.05)
        end

        return false
    end

    local function waitForTrailEquipped(
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

    local function runAutoBuyPickaxe()
        if pickaxeBuyWorkerRunning then
            return
        end

        pickaxeBuyWorkerRunning = true

        task.spawn(function()
            while autoBuyPickaxe
                and not Window.Destroyed
            do
                local nextPurchase,
                    currentTier =
                    getNextPickaxePurchase()

                if not nextPurchase then
                    log(
                        "Auto Buy Pickaxe:",
                        "MAX TIER",
                        "| Tier:",
                        currentTier
                    )

                    break
                end

                local cash =
                    getCash()

                if cash
                    < nextPurchase.Price
                then
                    log(
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
                    < pickaxeBuyRetryAt
                then
                    break
                end

                log(
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
                    waitForPickaxeTier(
                        currentTier,
                        5
                    )

                if not confirmed then
                    pickaxeBuyRetryAt =
                        os.clock() + 10

                    log(
                        "Auto Buy Pickaxe:",
                        "no tier confirmation; cooldown 10s"
                    )

                    break
                end

                pickaxeBuyRetryAt = 0

                log(
                    "Auto Buy Pickaxe confirmed",
                    "| Tier:",
                    newTier
                )

                task.wait(0.05)
            end

            pickaxeBuyWorkerRunning =
                false
        end)
    end

    local function runAutoBuyTrail()
        if trailBuyWorkerRunning then
            return
        end

        trailBuyWorkerRunning = true

        task.spawn(function()
            while autoBuyTrail
                and not Window.Destroyed
            do
                local nextPurchase =
                    getNextTrailPurchase()

                if not nextPurchase then
                    log(
                        "Auto Buy Trail:",
                        "ALL OWNED"
                    )

                    break
                end

                local cash =
                    getCash()

                if cash
                    < nextPurchase.Price
                then
                    log(
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
                    < trailBuyRetryAt
                then
                    break
                end

                log(
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
                    waitForTrailOwned(
                        nextPurchase.Id,
                        5
                    )

                if not confirmed then
                    trailBuyRetryAt =
                        os.clock() + 10

                    log(
                        "Auto Buy Trail:",
                        "no ownership confirmation; cooldown 10s"
                    )

                    break
                end

                trailBuyRetryAt = 0

                log(
                    "Auto Buy Trail confirmed",
                    "| ID:",
                    nextPurchase.Id
                )

                -- Equip the newly bought/best trail after ownership is confirmed.
                TrailShopRequest:
                    FireServer(
                        "Equip",
                        nextPurchase.Id
                    )

                waitForTrailEquipped(
                    nextPurchase.Id,
                    3
                )

                task.wait(0.05)
            end

            trailBuyWorkerRunning =
                false
        end)
    end

    local function triggerAutoPurchases()
        if autoBuyPickaxe then
            runAutoBuyPickaxe()
        end

        if autoBuyTrail then
            runAutoBuyTrail()
        end
    end

    local function triggerAutoUpgrades()
        if autoUpgradePen then
            runAutoUpgradePen()
        end

        if autoUpgradeTreadmill then
            runAutoUpgradeTreadmill()
        end
    end

    -- Event-driven: no upgrade polling loop.
    LocalPlayer:
    GetAttributeChangedSignal(
        "Cash"
    ):
    Connect(function()
        triggerAutoUpgrades()
        triggerAutoPurchases()
    end)

    local function treadmillMultiplier(object)
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

    local function findTreadmillPart(container)
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

    local function getPlotTreadmill()
        local plot =
            getOwnedPlot()

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
                    findTreadmillPart(child)

                if part then
                    local multiplier =
                        treadmillMultiplier(child)

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
                        findTreadmillPart(object)

                    if part then
                        local multiplier =
                            treadmillMultiplier(
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

    local function getTreadmillStandCFrame(part)
        local _, humanoid, hrp =
            getCharacter()

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

    local function teleportToTreadmill()
        local plot,
            model,
            part,
            multiplier =
            getPlotTreadmill()

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
            getCharacter()

        humanoid:Move(
            Vector3.zero,
            false
        )

        local standCF =
            getTreadmillStandCFrame(
                part
            )

        hrp.AssemblyLinearVelocity =
            Vector3.zero

        hrp.AssemblyAngularVelocity =
            Vector3.zero

        hrp.CFrame =
            standCF

        log(
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

    local function isOnTreadmill(part)
        if not part
            or not part.Parent
        then
            return false
        end

        local _, _, hrp =
            getCharacter()

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

    local isCarrying
    local isBeingChased

    local startAutoFarm
    local startAutoTreadmill
    local setActivity

    -- Normal character movement.
    -- This intentionally does NOT raw-CFrame teleport long distances.
    local function stopMoving()
        local character = LocalPlayer.Character
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        if humanoid then humanoid:Move(Vector3.zero, false) end
    end

    local function walkTo(targetPosition, stopDistance, timeout, extraCheck, speedLimit)
        stopDistance = tonumber(stopDistance) or 3
        local character, humanoid, hrp = getCharacter()
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

    local function teleportTo(targetPosition, stopDistance, extraCheck, timeout)
        stopDistance = tonumber(stopDistance) or 3
        if not autoFarmActive then return false end
        local _, humanoid, hrp = getCharacter()
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

    local function tweenTo(targetPosition, stopDistance, timeout, extraCheck)
        stopDistance = tonumber(stopDistance) or 3
        timeout = tonumber(timeout) or 30

        local _, humanoid, hrp = getCharacter()

        humanoid:Move(Vector3.zero, false)

        local distance = (hrp.Position - targetPosition).Magnitude

        if distance <= stopDistance then
            return true
        end

        local syncedSpeed = getCurrentMoveSpeed()
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

        log(
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

    local function moveTo(targetPosition, stopDistance, timeout, extraCheck)
        log("Movement:", movementMode)

        if movementMode == "Teleport" then
            return teleportTo(
                targetPosition,
                stopDistance,
                extraCheck,
                timeout
            )
        end

        if movementMode == "Tween" then
            return tweenTo(
                targetPosition,
                stopDistance,
                timeout,
                extraCheck
            )
        end

        return walkTo(
            targetPosition,
            stopDistance,
            timeout,
            extraCheck
        )
    end

    local function getApproachPosition(targetPosition, desiredDistance)
        local _, _, hrp = getCharacter()

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

    local function walkNear(targetPosition, desiredDistance, timeout)
        local approachPosition = getApproachPosition(targetPosition, desiredDistance)
        return moveTo(approachPosition, 2, timeout)
    end

    local function getMapSafeZonePart()
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

    local function getHomeTargetPosition(
        fromPosition
    )
        local safeZone =
            getMapSafeZonePart()

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

    local function walkHome(isBanked)
        local hitbox =
            getOwnedPlotHitbox()

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
                getCharacter()

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
                or not isCarrying()
        end

        local _, _, hrp =
            getCharacter()

        local centerPosition =
            getHomeTargetPosition(
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
            stopMoving()
        else
            local reached = false

            if movementMode == "Tween" then
                reached =
                    tweenTo(
                        centerPosition,
                        2,
                        60,
                        interrupted
                    )

            elseif movementMode == "Teleport" then
                reached =
                    teleportTo(
                        centerPosition,
                        2,
                        interrupted,
                        60
                    )

            else
                -- Walk in one straight direction toward the fixed safe-zone target.
                -- No speed cap: keep the player's current/boosted WalkSpeed.
                reached =
                    walkTo(
                        centerPosition,
                        2,
                        60,
                        interrupted
                    )
            end

            if not reached
                and isCarrying()
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
                stopMoving()
                return "banked"
            end

            local owned =
                inOwnedPlot()

            if not isCarrying() then
                stopMoving()

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
                    stopMoving()
                else
                    -- If knocked back out, simply head straight to the
                    -- safe-zone center again.
                    local _, _, currentHRP =
                        getCharacter()

                    local retryCenter =
                        getHomeTargetPosition(
                            currentHRP.Position
                        )

                    if not retryCenter then
                        return "failed"
                    end

                    walkTo(
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

        stopMoving()

        return
            bankedNow()
            and "banked"
            or "failed"
    end

    -- Pickaxe
    local function ensurePickaxe()
        local character, humanoid = getCharacter()

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
                log(
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

    local function usePickaxe()
        local pickaxe = ensurePickaxe()

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
    local function resolveEgg(container)
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

    local function getEggName(egg)
        local eggType = egg:GetAttribute("EggType")

        if typeof(eggType) == "string" and eggType ~= "" then
            return eggType
        end

        if egg.Parent then
            return egg.Parent.Name:gsub("^%d+:%s*", "")
        end

        return egg.Name
    end

    local function validEgg(egg)
        if not egg or not egg.Parent then
            return false
        end

        local health = egg:GetAttribute("Health")

        return typeof(health) == "number"
            and health > 0
            and egg:GetAttribute("Hatching") ~= true
            and egg:GetAttribute("Broken") ~= true
    end

    local function buildEggList()
        local result, found = {}, {}
        local function add(zoneName, raw)
            if type(raw) ~= "string" or found[raw] then return end
            found[raw] = true
            local label = "Zone " .. (zoneName:match("%d+") or zoneName)
                .. " • " .. displayName(raw)
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
                    local egg = resolveEgg(container)
                    if egg then add(zoneName, getEggName(egg)) end
                end
            end
        end
        return result
    end

    local MASTER_EGGS = buildEggList()

    -- Titanic event state is replicated directly on Workspace.
    local function normalizeEggKey(value)
        return tostring(value or "")
            :gsub("^%d+:%s*", "")
            :lower()
            :gsub("[^%w]", "")
    end

    local function getTitanicState()
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

    local function isTitanicPriorityActive()
        if not prioritizeTitanicEgg then
            return false
        end

        local state =
            getTitanicState()

        return state.Active == true
    end

    local function pendingIsFromTitanic(
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
            normalizeEggKey(
                pending.EggName
            )
            == normalizeEggKey(
                state.EggName
            )
    end

    local function objectLooksTitanic(
        object
    )
        local current = object

        for _ = 1, 5 do
            if not current then
                break
            end

            local normalized =
                normalizeEggKey(
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

    local function isTitanicEggObject(
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
            if normalizeEggKey(
                getEggName(egg)
            ) == normalizeEggKey(
                state.EggName
            )
            then
                return true
            end
        end

        -- Fallback for game updates where Titanic workspace attributes are
        -- late/missing but the event egg is already physically spawned.
        if objectLooksTitanic(
            egg
        ) then
            return true
        end

        local eggName =
            normalizeEggKey(
                getEggName(egg)
            )

        return
            eggName:
            find(
                "titanic",
                1,
                true
            ) ~= nil
    end

    local lastTitanicScanAt = 0
    local cachedTitanicEgg = nil
    local cachedTitanicZone = nil
    local cachedTitanicDistance = nil
    local cachedTitanicState = nil

    local function findTitanicEgg(
        excludedEgg
    )
        if not prioritizeTitanicEgg then
            return nil
        end

        local nowClock =
            os.clock()

        -- Avoid doing a Workspace:GetDescendants() scan every frame.
        if nowClock
                - lastTitanicScanAt
            < 0.25
            and cachedTitanicEgg
            and cachedTitanicEgg.Parent
            and cachedTitanicEgg
                ~= excludedEgg
            and validEgg(
                cachedTitanicEgg
            )
        then
            return
                cachedTitanicEgg,
                cachedTitanicZone,
                cachedTitanicDistance,
                cachedTitanicState
        end

        lastTitanicScanAt =
            nowClock

        local state =
            getTitanicState()

        local _, _, hrp =
            getCharacter()

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
                or not validEgg(
                    egg
                )
                or not isTitanicEggObject(
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
                        resolveEgg(
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
                            resolveEgg(
                                container
                            )
                        )
                    end
                end
            end
        end

        -- 3) Event-only fallback outside ZoneBuilds. Do not require state.Active:
        -- the physical Titanic egg itself is enough proof that the event exists.
        if not best then
            for _, object
                in ipairs(
                    Workspace:
                    GetDescendants()
                )
            do
                if object:IsA(
                        "BasePart"
                    )
                    and (
                        typeof(
                            object:
                            GetAttribute(
                                "Health"
                            )
                        ) == "number"
                        or objectLooksTitanic(
                            object
                        )
                    )
                then
                    consider(
                        object
                    )
                end
            end
        end

        cachedTitanicEgg =
            best

        cachedTitanicZone =
            bestZone

        cachedTitanicDistance =
            bestDistance

        cachedTitanicState =
            state

        if best then
            return
                best,
                bestZone,
                bestDistance,
                state
        end

        return nil
    end

    local function getEggPriority(egg, zoneName)
        local eggName = getEggName(egg)
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

    local function findBestEgg(excludedEgg)
        local titanicEgg,
            titanicZone,
            titanicDistance =
            findTitanicEgg(
                excludedEgg
            )

        if titanicEgg then
            log(
                "Titanic priority target:",
                getEggName(titanicEgg),
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

        local _, _, hrp = getCharacter()

        local bestEgg
        local bestZone
        local bestDistance = math.huge
        local bestRarity, bestTier = -1, -1

        for _, zoneName in ipairs(MASTER_ZONES) do
            if isSelected(selectedZones, zoneName) then
                local zone = ZoneBuilds:FindFirstChild(zoneName)
                local eggs = zone and zone:FindFirstChild("Eggs")

                if eggs then
                    for _, container in ipairs(eggs:GetChildren()) do
                        local egg = resolveEgg(container)

                        if egg ~= excludedEgg and validEgg(egg) then
                            local eggName = getEggName(egg)

                            if isSelected(selectedEggs, eggName) then
                                local distance = (hrp.Position - egg.Position).Magnitude

                                local rarity, tier = getEggPriority(egg, zoneName)
                                if rarity > bestRarity
                                    or (rarity == bestRarity and tier > bestTier)
                                    or (rarity == bestRarity and tier == bestTier
                                        and distance < bestDistance) then
                                    bestEgg = egg
                                    bestZone = zoneName
                                    bestDistance = distance
                                    bestRarity, bestTier = rarity, tier
                                end
                            end
                        end
                    end
                end
            end
        end

        return bestEgg, bestZone, bestDistance
    end

    -- Result pet
    local function snapshotPickups()
        local snapshot = {}

        for _, animal in ipairs(Pickups:GetChildren()) do
            snapshot[animal] = true
        end

        return snapshot
    end

    local function petMatchesFilter(animal)
        local rawName = animal:GetAttribute("AnimalName") or animal.Name
        local weight = tonumber(animal:GetAttribute("WeightKg"))
        if not isSelected(selectedPets, rawName) then return false end
        return minimumPetWeight <= 0 or (weight ~= nil and weight >= minimumPetWeight)
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

    local function makePendingHatch(
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

    local function scanPendingHatches()
        local index = 1

        local titanicState =
            getTitanicState()

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
                        normalizeZone(
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

                -- Give replicated weight metadata a moment to arrive when
                -- the user has an active minimum-weight filter.
                if minimumPetWeight > 0
                    and isSelected(
                        selectedPets,
                        rawName
                    )
                    and tonumber(
                        best:GetAttribute(
                            "WeightKg"
                        )
                    ) == nil
                then
                    index += 1
                else
                    table.remove(
                        pendingHatches,
                        index
                    )

                    if petMatchesFilter(best) then
                        if suppressNormalAccepted
                            and not pendingIsFromTitanic(
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

                            log(
                                "Pending hatch deferred for Titanic:",
                                rawName,
                                "| From:",
                                pending.EggName
                            )
                        else
                            log(
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
                        log(
                            "Pending hatch rejected:",
                            rawName,
                            "| From:",
                            pending.EggName,
                            "| Continue breaking eggs"
                        )
                    end
                end

            elseif os.clock()
                    >= pending.Deadline
            then
                log(
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

    local function waitHitDelayWatchingPending(
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
                scanPendingHatches()

            if accepted then
                return accepted
            end

            task.wait(0.03)
        end

        return nil
    end

    local function attackEggWhileWatchingPending(
        egg,
        zoneName
    )
        if not validEgg(egg) then
            return nil, false
        end

        local before =
            snapshotPickups()

        local eggPosition =
            egg.Position

        local hatchId =
            egg:GetAttribute(
                "HatchId"
            )

        local eggName =
            getEggName(egg)

        local acceptedDuringMove
        local titanicSwitchRequested = false

        local function checkTitanicSwitch()
            if not prioritizeTitanicEgg then
                return false
            end

            local titanic =
                findTitanicEgg(
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
                scanPendingHatches()

            return acceptedDuringMove ~= nil
                or checkTitanicSwitch()
                or isCarrying()
                or isBeingChased()
                or not autoFarmActive
                or currentActivity
                    ~= "Farm"
        end

        local _, _, hrp =
            getCharacter()

        local distance =
            (
                hrp.Position
                - eggPosition
            ).Magnitude

        log(
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
            moveTo(
                getApproachPosition(
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
                log(
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
            scanPendingHatches()

        if acceptedBeforeEquip then
            return
                acceptedBeforeEquip,
                false
        end

        if not ensurePickaxe() then
            return nil, false
        end

        if not usePickaxe() then
            return nil, false
        end

        while autoFarmActive
            and currentActivity == "Farm"
            and validEgg(egg)
        do
            local titanicNow =
                findTitanicEgg(
                    egg
                )

            if titanicNow then
                log(
                    "Titanic spawned; interrupting normal egg:",
                    eggName
                )

                stopMoving()
                return nil, false
            end

            local accepted =
                scanPendingHatches()

            if accepted then
                stopMoving()

                return
                    accepted,
                    false
            end

            local _, _, currentHRP =
                getCharacter()

            local currentDistance =
                (
                    currentHRP.Position
                    - egg.Position
                ).Magnitude

            if currentDistance
                > HIT_DISTANCE
            then
                acceptedDuringMove = nil

                moveTo(
                    getApproachPosition(
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
                    log(
                        "Titanic spawned during re-approach; switching target."
                    )

                    return nil, false
                end

                if not validEgg(egg) then
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

            log(
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
                waitHitDelayWatchingPending(
                    HIT_DELAY
                )

            if acceptedDuringDelay then
                stopMoving()

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

        if validEgg(egg) then
            return nil, false
        end

        log(
            "Egg done:",
            eggName,
            "| Queue hatch result",
            "| Pending:",
            #pendingHatches + 1
        )

        local titanicStateAtBreak =
            getTitanicState()

        if titanicStateAtBreak.Active
            and titanicStateAtBreak.EggName
            and normalizeEggKey(eggName)
                == normalizeEggKey(
                    titanicStateAtBreak.EggName
                )
        then
            titanicOverrideSpawnId =
                titanicStateAtBreak.SpawnId

            log(
                "Titanic egg broken:",
                eggName,
                "| SpawnId:",
                titanicOverrideSpawnId
            )
        end

        table.insert(
            pendingHatches,
            makePendingHatch(
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

    local function breakEgg(
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
                findTitanicEgg()

            if titanicEgg then
                if targetEgg ~= titanicEgg then
                    stopMoving()

                    targetEgg =
                        titanicEgg

                    targetZone =
                        titanicZone

                    log(
                        "ABSOLUTE TITANIC PRIORITY ->",
                        getEggName(
                            titanicEgg
                        ),
                        "| Zone:",
                        titanicZone
                    )
                end
            else
                local accepted =
                    scanPendingHatches()

                if accepted then
                    stopMoving()
                    return accepted
                end
            end

            if not targetEgg
                or not validEgg(targetEgg)
            then
                targetEgg,
                targetZone =
                    findBestEgg()
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
                attackEggWhileWatchingPending(
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
    local function getPromptPosition(prompt)
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

    local function modelDistanceToPoint(model, point)
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

    local function normalizeText(text)
        return tostring(text or "")
            :gsub("<.->", "")
            :lower()
            :gsub("[^%w]", "")
    end

    local function promptKg(prompt)
        local text = tostring(prompt.ObjectText or ""):gsub("<.->", "")
        return tonumber(text:match("%[([%d%.]+)%s*[Kk][Gg]%]"))
    end

    local function promptMatchesAnimal(prompt, animal)
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

        local position = getPromptPosition(prompt)

        if not position then
            return false
        end

        local distance = modelDistanceToPoint(animal, position)

        if distance > 6 then return false end
        local name = animal:GetAttribute("AnimalName") or animal.Name
        local objectText = normalizeText(prompt.ObjectText)
        local targetText = normalizeText(displayName(name))
        local rawText = normalizeText(name)
        local nameMatches = objectText:find(targetText, 1, true)
            or objectText:find(rawText, 1, true)
        local weight = tonumber(animal:GetAttribute("WeightKg"))
        local shownWeight = promptKg(prompt)
        if nameMatches then
            return not weight or not shownWeight or math.abs(weight - shownWeight) <= 1.1
        end
        -- Only use geometry when a prompt has no identifying text.
        return objectText == "" and distance <= 1.5
    end

    local function findCurrentPrompt(animal)
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
        local _, _, hrp = getCharacter()
        local best, bestDistance = nil, math.huge
        for prompt in pairs(candidates) do
            if prompt.Enabled and promptMatchesAnimal(prompt, animal) then
                local position = getPromptPosition(prompt)
                local distance = position and (position - hrp.Position).Magnitude or math.huge
                if distance < bestDistance then best, bestDistance = prompt, distance end
            end
        end
        return best
    end

    local function waitStealPrompt(animal)
        local foundPrompt

        local shownConnection =
            ProximityPromptService.PromptShown:
            Connect(function(prompt)
                if not foundPrompt
                    and promptMatchesAnimal(prompt, animal)
                then
                    foundPrompt = prompt
                    log("Prompt shown:", prompt:GetFullName())
                end
            end)

        local deadline = os.clock() + PROMPT_TIMEOUT

        while autoFarmActive
            and animal.Parent
            and os.clock() < deadline
            and not foundPrompt
        do
            foundPrompt = findCurrentPrompt(animal)

            if foundPrompt then
                break
            end

            task.wait(0.08)
        end

        shownConnection:Disconnect()

        return foundPrompt
    end

    -- Carry state from the game's own ChaseState module.
    isCarrying = function()
        local ok, carrying = pcall(function()
            return ChaseState.IsCarrying(LocalPlayer)
        end)

        return ok and carrying == true
    end

    isBeingChased = function()
        -- IsActive also includes Carrying; only this attribute identifies chase.
        local attribute = ChaseState.ChasedAttribute or "BeingChased"
        return LocalPlayer:GetAttribute(attribute) ~= nil
    end

    local function waitUntilCarrying(timeout)
        local deadline = os.clock() + (timeout or CARRY_TIMEOUT)

        while autoFarmActive and os.clock() < deadline do
            if isCarrying() then
                return true
            end

            task.wait(0.01)
        end

        return false
    end

    local function getAnimalSignature(animal)
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
                normalizeZone(
                    animal:GetAttribute("ZoneId")
                )
        }
    end

    local function matchesAnimalSignature(
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
            normalizeZone(
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

    local function waitForDroppedAnimal(
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
                getCharacter()

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
                if matchesAnimalSignature(
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
                log(
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

    local function pickUpAnimal(animal, animalName)
        if not animal or not animal.Parent then return false end
        local signature = getAnimalSignature(animal)
        local deadline = os.clock() + 35
        while autoFarmActive and os.clock() < deadline do
            if isCarrying() then return true end
            if not animal:IsDescendantOf(Pickups) then
                local replacement
                local replacementDistance =
                    math.huge

                local _, _, replacementHRP =
                    getCharacter()

                for _, candidate
                    in ipairs(
                        Pickups:GetChildren()
                    )
                do
                    if matchesAnimalSignature(
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

                log(
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
            local prompt = findCurrentPrompt(animal)
            local promptPosition = prompt and getPromptPosition(prompt)
            local _, _, hrp = getCharacter()
            local range = prompt and prompt.MaxActivationDistance or PET_APPROACH_DISTANCE
            local distance = promptPosition and (hrp.Position - promptPosition).Magnitude
                or modelDistanceToPoint(animal, hrp.Position)
            if distance > math.max(1, range - 0.5) then
                -- Short approaches refresh position when the ragdoll rolls or slides.
                local approach = getApproachPosition(promptPosition or targetPosition, 2)
                moveTo(approach, 1, math.min(2, deadline - os.clock()), function()
                    return isCarrying() or not animal:IsDescendantOf(Pickups)
                        or (animal:GetPivot().Position - targetPosition).Magnitude > 2
                end)
            elseif prompt and prompt.Parent and prompt.Enabled
                and promptMatchesAnimal(prompt, animal) then
                if type(fireproximityprompt) ~= "function" then
                    warn("[CHLISE HUB] Prompt activation is unavailable.")
                    return false
                end
                local ok, err = pcall(fireproximityprompt, prompt)
                if not ok then log("Pickup retry:", err) end
                if waitUntilCarrying(math.min(0.6, math.max(0, deadline - os.clock()))) then
                    return true
                end
            end
            task.wait(0.1)
        end
        log("Pickup timed out:", animalName)
        return false
    end

    local function stealAndBank(animal)
        if not animal or not animal.Parent then
            return false
        end

        local signature =
            getAnimalSignature(animal)

        local animalName =
            signature.AnimalName

        local weight =
            signature.WeightKg
            or 0

        if not petMatchesFilter(animal) then
            log("Discard hatch result:", animalName, "| Filter mismatch")
            return false
        end

        log(
            "Pet accepted:",
            animalName,
            "| Weight:",
            weight,
            "| HatchId:",
            signature.HatchId
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

                        log(
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
            if not pickUpAnimal(animal, animalName) then return false end
        -- If the guardian knocks the pet out of our hands,
        -- locate the same HatchId and pick it up again.
        while autoFarmActive
            and not banked
        do
            if not isCarrying() then
                local _, _, currentHRP = getCharacter()
                if isBankablePosition(currentHRP.Position) then
                    local graceDeadline = os.clock() + BANK_GRACE_SECONDS
                    while autoFarmActive and not banked and os.clock() < graceDeadline do
                        task.wait(0.03)
                    end
                    if banked then break end
                end
                local dropPosition =
                    currentHRP.Position

                local dropped =
                    waitForDroppedAnimal(
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

                log(
                    "Retry pickup:",
                    animalName
                )

                if not pickUpAnimal(
                    dropped,
                    animalName
                ) then
                    log(
                        "Dropped pet pickup failed, retrying:",
                        animalName
                    )

                    task.wait(0.15)
                    continue
                end

                log(
                    "Dropped pet recovered, returning home:",
                    animalName
                )
            end

            local homeState =
                walkHome(
                    bankedNow
                )

            if banked then
                break
            end

            if homeState == "dropped" then
                log(
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
                    and isCarrying()
                    and not isBeingChased()
                    and os.clock() < deadline
                do
                    task.wait(0.03)
                end

                if not isCarrying()
                    and not banked
                then
                    log(
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
            stopMoving()
            while autoFarmActive and isBeingChased() do
                task.wait(HOME_RETRY_WAIT)
            end
            log(
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

            log(
                "Treadmill session detected",
                "| Speed:",
                speed,
                "| Position:",
                sessionCF.Position
            )
        end)
    end

    -- Farm loop
    startAutoFarm = function()
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
                    startAutoFarm()
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
                    if isBeingChased() or isCarrying() then
                        stopMoving()
                        task.wait(HOME_RETRY_WAIT)
                        return
                    end
                    local egg, zoneName, distance = findBestEgg()

                    if not egg then
                        task.wait(0.25)
                        return
                    end

                    log(
                        "Selected egg:",
                        getEggName(egg),
                        "| Zone:",
                        zoneName,
                        "| Distance:",
                        string.format("%.2f", distance)
                    )

                    local animal = breakEgg(egg, zoneName)

                    if not autoFarmActive then
                        return
                    end

                    if animal and animal.Parent then
                        log(
                            "Hatched:",
                            animal:GetAttribute("AnimalName") or animal.Name
                        )

                        stealAndBank(animal)
                    else
                        log("No matching hatch; continue farming.")
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
                stopMoving()
            end

            farmLoopRunning = false
        end)
    end

    startAutoTreadmill = function()
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
                            getPlotTreadmill()

                        if not part then
                            teleportToTreadmill()
                            task.wait(0.5)
                            return
                        end

                        if not isOnTreadmill(
                            part
                        ) then
                            teleportToTreadmill()
                            task.wait(0.25)
                            return
                        end

                        local _,
                            humanoid =
                            getCharacter()

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

    setActivity = function(activity)
        local sameActivity =
            activity == currentActivity

        currentActivity =
            activity

        autoFarmActive =
            activity == "Farm"

        autoTreadmillActive =
            activity == "Treadmill"

        if not sameActivity then
            stopMoving()
        end

        if activity == "Farm" then
            log(
                "Activity -> Auto Farm Egg"
            )

            if titanicOverrideActive then
                activityDeadline = nil
            else
                refreshActivityDeadline()
            end

            startAutoFarm()

        elseif activity == "Treadmill" then
            log(
                "Activity -> Auto Treadmill"
            )

            refreshActivityDeadline()

            teleportToTreadmill()
            startAutoTreadmill()

        else
            activityDeadline = nil
            log("Activity -> Idle")
        end
    end

    local function beginTitanicOverride()
        if titanicOverrideActive then
            return
        end

        -- Do not throw away a pet already in our hands.
        -- Finish banking/recovery first, then Titanic takes over.
        if isCarrying()
            or isBeingChased()
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
            getTitanicState()

        titanicOverrideSpawnId =
            state.SpawnId

        log(
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
            setActivity("Farm")
        else
            autoFarmActive = true
            activityDeadline = nil
            startAutoFarm()
        end

        activityDeadline = nil
    end

    local function restoreAfterTitanic()
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

        local desired

        if resumeActivity == "Treadmill"
            and autoTreadmillEnabled
        then
            desired = "Treadmill"

        elseif resumeActivity == "Farm"
            and autoFarmEnabled
        then
            desired = "Farm"

        elseif autoFarmEnabled then
            desired = "Farm"

        elseif autoTreadmillEnabled then
            desired = "Treadmill"

        else
            desired = nil
        end

        log(
            "TITANIC OVERRIDE END",
            "| Resume:",
            desired
        )

        setActivity(desired)

        if desired
            and resumeActivity == desired
            and resumeRemaining
            and resumeRemaining > 0
            and otherActivityEnabled(
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
    -- Priority order:
    -- 1. Already-carried pet recovery/banking (safety)
    -- 2. Titanic Egg
    -- 3. Active Farm/Treadmill timer
    -- 4. Normal egg pipeline / pending normal pets
    task.spawn(function()
        while not Window.Destroyed do
            local state =
                getTitanicState()

            local automationEnabled =
                autoFarmEnabled
                or autoTreadmillEnabled
                or currentActivity ~= nil

            local titanicTargetExists =
                false

            if prioritizeTitanicEgg
                and automationEnabled
            then
                local target =
                    findTitanicEgg()

                titanicTargetExists =
                    target ~= nil
            end

            if titanicTargetExists then
                if not titanicOverrideActive then
                    beginTitanicOverride()
                end

            elseif titanicOverrideActive then
                -- The Titanic egg is gone/broken. Return to the exact activity
                -- that was interrupted and restore its remaining timer.
                restoreAfterTitanic()

            elseif titanicOverrideRequested
                and not isCarrying()
                and not isBeingChased()
            then
                -- We were waiting for a carried pet to finish banking.
                local target =
                    prioritizeTitanicEgg
                    and state.Active
                    and findTitanicEgg()
                    or nil

                if target then
                    beginTitanicOverride()
                else
                    titanicOverrideRequested =
                        false
                end
            end

            -- Normal alternating timers are suspended during Titanic override.
            if not titanicOverrideActive
                and not titanicOverrideRequested
                and currentActivity
                and activityDeadline
                and os.clock()
                    >= activityDeadline
            then
                if currentActivity
                    == "Treadmill"
                then
                    if autoFarmEnabled then
                        setActivity("Farm")
                    else
                        activityDeadline = nil
                    end

                elseif currentActivity
                    == "Farm"
                then
                    if autoTreadmillEnabled then
                        if not isCarrying()
                            and not isBeingChased()
                        then
                            setActivity(
                                "Treadmill"
                            )
                        end
                    else
                        activityDeadline = nil
                    end
                end
            end

            task.wait(0.1)
        end
    end)

    local function logTitanicEventState()
        local state =
            getTitanicState()

        local physicalTarget =
            prioritizeTitanicEgg
            and findTitanicEgg()
            or nil

        if state.Active
            or physicalTarget
        then
            log(
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
            log(
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
            logTitanicEventState()
        end)
    end

    task.spawn(function()
        while not Window.Destroyed do
            if currentActivity == "Farm"
                and autoFarmEnabled
                and autoFarmActive
                and not farmLoopRunning
            then
                startAutoFarm()
            end

            if currentActivity == "Treadmill"
                and autoTreadmillEnabled
                and autoTreadmillActive
                and not treadmillLoopRunning
            then
                startAutoTreadmill()
            end

            task.wait(0.5)
        end
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
            selectedZones = decodeSelection(value, zoneLabels)
        end
    )

    FarmSection:AddDropdown(
        "BSAEEggs",
        "Egg Selection",
        MASTER_EGGS,
        true,
        selectedEggs,

        function(value)
            selectedEggs = decodeSelection(value, eggLabels)
        end
    )

    FarmSection:AddToggle(
        "BSAEPrioritizeTitanic",
        "Prioritize Titanic Egg",
        true,

        function(state)
            prioritizeTitanicEgg =
                state == true

            if not prioritizeTitanicEgg
                and titanicOverrideActive
            then
                restoreAfterTitanic()
            end

            local titanicState =
                getTitanicState()

            log(
                "Prioritize Titanic:",
                prioritizeTitanicEgg,
                "| Active:",
                titanicState.Active,
                "| NextAt:",
                titanicState.NextAt
            )
        end
    )

    FarmSection:AddDropdown(
        "BSAEPetFilter",
        "Pet Filter",
        MASTER_PETS,
        true,
        selectedPets,

        function(value)
            selectedPets = decodeSelection(value, petLabels)
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
                log("Movement mode changed:", movementMode)
            end
        end
    )

    FarmSection:AddTextbox(
        "BSAEMinimumPetWeight",
        "Minimum Pet Weight",
        "0 = Off",

        function(value)
            local normalized =
                tostring(value or ""):
                gsub(",", ".")

            local parsed =
                tonumber(normalized)

            if parsed and parsed > 0 then
                minimumPetWeight = parsed
            else
                minimumPetWeight = 0
            end
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
                    refreshActivityDeadline()
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
                    refreshActivityDeadline()
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
                    getOwnedPlotHitbox()

                if homeHitbox then
                    log(
                        "Owned plot:",
                        homeHitbox:GetFullName(),
                        "| WalkSpeed:",
                        getCurrentMoveSpeed(),
                        "| PetFilters:",
                        #MASTER_PETS
                    )
                else
                    warn(
                        "[CHLISE HUB] Owned plot was not detected yet."
                    )
                end

                if currentActivity == nil then
                    setActivity("Farm")
                elseif currentActivity
                    == "Treadmill"
                then
                    -- Keep treadmill phase running.
                    -- Farm starts when treadmill timer expires.
                    refreshActivityDeadline()
                else
                    setActivity("Farm")
                end
            else
                if currentActivity == "Farm" then
                    if autoTreadmillEnabled then
                        setActivity(
                            "Treadmill"
                        )
                    else
                        setActivity(nil)
                    end
                else
                    refreshActivityDeadline()
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
                    refreshActivityDeadline()
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
                    refreshActivityDeadline()
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
                -- Auto Treadmill ON always enters
                -- the treadmill immediately.
                setActivity(
                    "Treadmill"
                )
            else
                if currentActivity
                    == "Treadmill"
                then
                    if autoFarmEnabled then
                        setActivity("Farm")
                    else
                        setActivity(nil)
                    end
                else
                    refreshActivityDeadline()
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
                runAutoUpgradePen()
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
                runAutoUpgradeTreadmill()
            end
        end
    )

    UpgradeSection:AddToggle(
        "BSAEAutoBuyPickaxe",
        "Auto Buy Pickaxe",
        false,

        function(state)
            autoBuyPickaxe =
                state == true

            if autoBuyPickaxe then
                pickaxeBuyRetryAt = 0
                runAutoBuyPickaxe()
            end
        end
    )

    UpgradeSection:AddToggle(
        "BSAEAutoBuyTrail",
        "Auto Buy Trail",
        false,

        function(state)
            autoBuyTrail =
                state == true

            if autoBuyTrail then
                trailBuyRetryAt = 0
                runAutoBuyTrail()
            end
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
