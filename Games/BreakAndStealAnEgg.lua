-- Chlise Hub - Games/BreakAndStealAnEgg.lua
-- GameId: 10765288803
-- PlaceId: 114326934417838

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

    local AnimalRenders
    pcall(function()
        AnimalRenders = require(Shared:WaitForChild("AnimalRenders", 5))
    end)

    -- Game objects
    local EggHitRequest = ReplicatedStorage:WaitForChild("EggHitRequest")
    local AnimalBankedRemote = ReplicatedStorage:WaitForChild("AnimalBankedRemote")

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
    local HOME_STAGING_DISTANCE = 12
    local HOME_INSIDE_DISTANCE = 4
    local HOME_ENTRY_SPEED = 24
    local HOME_CONFIRM_TIMEOUT = 8
    local BANK_GRACE_SECONDS = 1.5
    local HOME_RETRY_WAIT = 0.12
    local DROPPED_PET_TIMEOUT = 12

    -- State
    local autoFarmActive = false
    local farmLoopRunning = false
    local debugEnabled = false

    local selectedZones = {}
    local selectedEggs = {}
    local selectedPets = {}
    local minimumPetWeight = 0

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

    local isCarrying
    local isBeingChased

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

    local function getHomeEntryPoints(hitbox, fromPosition)
        local flatFrom =
            Vector3.new(
                fromPosition.X,
                hitbox.Position.Y,
                fromPosition.Z
            )

        local localFrom =
            hitbox.CFrame:
            PointToObjectSpace(flatFrom)

        local direction =
            Vector3.new(
                localFrom.X,
                0,
                localFrom.Z
            )

        if direction.Magnitude < 0.05 then
            direction = Vector3.new(0, 0, 1)
        else
            direction = direction.Unit
        end

        local half = hitbox.Size * 0.5
        local tx = math.huge
        local tz = math.huge

        if math.abs(direction.X) > 0.001 then
            tx = half.X / math.abs(direction.X)
        end

        if math.abs(direction.Z) > 0.001 then
            tz = half.Z / math.abs(direction.Z)
        end

        local edgeDistance =
            math.min(tx, tz)

        local stagingLocal =
            direction
            * (
                edgeDistance
                + HOME_STAGING_DISTANCE
            )

        -- Only a little bit inside the safe zone.
        local insideLocal =
            direction
            * math.max(
                edgeDistance
                    - HOME_INSIDE_DISTANCE,
                0
            )

        local stagingWorld =
            hitbox.CFrame:
            PointToWorldSpace(stagingLocal)

        local insideWorld =
            hitbox.CFrame:
            PointToWorldSpace(insideLocal)

        return
            Vector3.new(
                stagingWorld.X,
                fromPosition.Y,
                stagingWorld.Z
            ),
            Vector3.new(
                insideWorld.X,
                fromPosition.Y,
                insideWorld.Z
            )
    end

    local function walkHome(isBanked)
        local hitbox = getOwnedPlotHitbox()
        if not hitbox then
            warn("[CHLISE HUB] Owned plot hitbox not found.")
            return "failed"
        end

        local function bankedNow()
            return type(isBanked) == "function" and isBanked() == true
        end
        local function inOwnedPlot()
            local _, _, hrp = getCharacter()
            return SafeZoneQuery.IsPositionInOwnedPlot(LocalPlayer.UserId, hrp.Position)
        end
        local function interrupted()
            return bankedNow() or not isCarrying()
        end
        local _, _, hrp = getCharacter()
        local stagingPosition, insidePosition = getHomeEntryPoints(hitbox, hrp.Position)
        if not inOwnedPlot() then
            -- End CFrame travel outside the plot, then cross using normal physics.
            local reached
            if movementMode == "Tween" then
                reached = tweenTo(stagingPosition, 1, 60, interrupted)
            elseif movementMode == "Teleport" then
                reached = teleportTo(stagingPosition, 1, interrupted, 60)
            else
                reached = walkTo(stagingPosition, 1, 60, interrupted)
            end
            if not reached and isCarrying() and not bankedNow() then return "failed" end
        end

        local deadline = os.clock() + HOME_CONFIRM_TIMEOUT
        local carryMissingSince
        while autoFarmActive and os.clock() < deadline do
            if bankedNow() then
                stopMoving()
                return "banked"
            end
            local owned = inOwnedPlot()
            if not isCarrying() then
                stopMoving()
                if not owned then return "dropped" end
                carryMissingSince = carryMissingSince or os.clock()
                if os.clock() - carryMissingSince >= BANK_GRACE_SECONDS then
                    return "dropped"
                end
            else
                carryMissingSince = nil
                if not owned then
                    -- Fast WalkSpeed can skip a whole plot in one frame.
                    -- Cap just this crossing and restore the latest game speed.
                    walkTo(insidePosition, 0.75, math.min(3, deadline - os.clock()),
                        function() return interrupted() or inOwnedPlot() end,
                        HOME_ENTRY_SPEED)
                else
                    stopMoving()
                end
            end
            task.wait(HOME_RETRY_WAIT)
        end
        stopMoving()
        -- Arrival alone is not evidence that the server banked the pet.
        return bankedNow() and "banked" or "failed"
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

    local function waitResultPet(before, zoneName, eggPosition, brokenEgg, hatchId)
        local deadline = os.clock() + PICKUP_SPAWN_TIMEOUT
        local resolved, accepted = false, nil

        local function scanResult()
            if resolved then return end
            local best, bestDistance = nil, math.huge
            for _, animal in ipairs(Pickups:GetChildren()) do
                if not before[animal] and animal:IsA("Model")
                    and animal:GetAttribute("Hatched") == true then
                    local animalZone = normalizeZone(animal:GetAttribute("ZoneId"))
                    local candidateId = animal:GetAttribute("HatchId")
                    local identityMatches = hatchId == nil
                        or (candidateId ~= nil and tostring(candidateId) == tostring(hatchId))
                    if identityMatches and (not animalZone or animalZone == zoneName) then
                        local distance = (animal:GetPivot().Position - eggPosition).Magnitude
                        if distance <= MAX_PICKUP_SPAWN_DISTANCE and distance < bestDistance then
                            best, bestDistance = animal, distance
                        end
                    end
                end
            end
            if not best then return end
            -- Wait for metadata replication instead of rejecting an unknown weight.
            local rawName = best:GetAttribute("AnimalName") or best.Name
            if minimumPetWeight > 0 and isSelected(selectedPets, rawName)
                and tonumber(best:GetAttribute("WeightKg")) == nil then return end
            resolved = true
            if petMatchesFilter(best) then
                accepted = best
                log("Hatch accepted, return for pickup:", rawName)
            else
                log("Hatch rejected, continue to next egg:", rawName)
            end
        end

        local function interruptTravel()
            scanResult()
            return accepted ~= nil or os.clock() >= deadline
                or isCarrying() or isBeingChased()
        end

        scanResult()
        if autoFarmActive and not accepted and not isCarrying() and not isBeingChased() then
            local nextEgg = findBestEgg(brokenEgg)
            if nextEgg then
                log("Pre-position at next egg:", getEggName(nextEgg))
                moveTo(getApproachPosition(nextEgg.Position, EGG_APPROACH_DISTANCE),
                    2, math.max(0.05, deadline - os.clock()), interruptTravel)
            end
        end
        while autoFarmActive and not resolved and os.clock() < deadline do
            scanResult()
            if not resolved then task.wait(0.04) end
        end
        if accepted then stopMoving() end
        return accepted
    end

    local function breakEgg(egg, zoneName)
        if not validEgg(egg) then
            return nil
        end

        if not ensurePickaxe() then
            return nil
        end

        local before = snapshotPickups()
        local eggPosition = egg.Position
        local hatchId = egg:GetAttribute("HatchId")

        local _, _, hrp = getCharacter()
        local distance = (hrp.Position - eggPosition).Magnitude

        log(
            "Target:",
            getEggName(egg),
            "| HP:",
            egg:GetAttribute("Health"),
            "| Zone:",
            zoneName,
            "| Distance:",
            string.format("%.2f", distance)
        )

        if distance > HIT_DISTANCE then
            if not walkNear(eggPosition, EGG_APPROACH_DISTANCE, 45) then
                log("Failed to reach egg.")
                return nil
            end
        end

        if not usePickaxe() then
            return nil
        end

        while autoFarmActive and validEgg(egg) do
            local _, _, currentHRP = getCharacter()
            local currentDistance = (currentHRP.Position - egg.Position).Magnitude

            if currentDistance > HIT_DISTANCE then
                if not walkNear(egg.Position, EGG_APPROACH_DISTANCE, 20) then
                    return nil
                end
            end

            local tier = LocalPlayer:GetAttribute("PickaxeTier") or 1

            EggHitRequest:FireServer(
                egg,
                tier
            )

            log(
                "Hit",
                "| Tier:",
                tier,
                "| HP:",
                egg:GetAttribute("Health")
            )

            task.wait(HIT_DELAY)
        end

        if not autoFarmActive then
            return nil
        end

        log("Egg done:", getEggName(egg))

        return waitResultPet(
            before,
            zoneName,
            eggPosition,
            egg,
            hatchId or egg:GetAttribute("HatchId")
        )
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

    local function matchesAnimalSignature(animal, signature)
        if not animal
            or not animal.Parent
            or not animal:IsA("Model")
        then
            return false
        end

        local hatchId =
            animal:GetAttribute("HatchId")

        if signature.HatchId ~= nil then
            return
                tostring(hatchId)
                == tostring(signature.HatchId)
        end

        local name =
            animal:GetAttribute("AnimalName")
            or animal.Name

        if name ~= signature.AnimalName then
            return false
        end

        local zone =
            normalizeZone(
                animal:GetAttribute("ZoneId")
            )

        if signature.ZoneId
            and zone
            and zone ~= signature.ZoneId
        then
            return false
        end

        local weight =
            tonumber(
                animal:GetAttribute("WeightKg")
            )

        if signature.WeightKg
            and weight
            and math.abs(
                weight - signature.WeightKg
            ) > 1.1
        then
            return false
        end

        return true
    end

    local function waitForDroppedAnimal(signature)
        local deadline =
            os.clock()
            + DROPPED_PET_TIMEOUT

        while autoFarmActive
            and os.clock() < deadline
        do
            local _, _, hrp =
                getCharacter()

            local best
            local bestDistance =
                math.huge

            for _, candidate
                in ipairs(Pickups:GetChildren())
            do
                if matchesAnimalSignature(
                    candidate,
                    signature
                ) then
                    local position =
                        candidate:GetPivot().Position

                    local distance =
                        (
                            position
                            - hrp.Position
                        ).Magnitude

                    if distance < bestDistance then
                        best = candidate
                        bestDistance = distance
                    end
                end
            end

            if best then
                log(
                    "Dropped pet found:",
                    signature.AnimalName,
                    "| Distance:",
                    string.format(
                        "%.2f",
                        bestDistance
                    )
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
                for _, candidate in ipairs(Pickups:GetChildren()) do
                    if matchesAnimalSignature(candidate, signature) then
                        replacement = candidate
                        break
                    end
                end
                if not replacement then return false end
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
                local dropped =
                    waitForDroppedAnimal(
                        signature
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
                    task.wait(0.15)
                    continue
                end
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

    -- Farm loop
    local function startAutoFarm()
        if farmLoopRunning then
            return
        end

        farmLoopRunning = true

        task.spawn(function()
            while autoFarmActive
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

            stopMoving()
            farmLoopRunning = false
        end)
    end

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

    FarmSection:AddToggle(
        "BSAEAutoFarm",
        "Auto Break & Steal",
        false,

        function(state)
            autoFarmActive = state

            if state then
                local homeHitbox = getOwnedPlotHitbox()

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
                    warn("[CHLISE HUB] Owned plot was not detected yet.")
                end

                startAutoFarm()
            else
                stopMoving()
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
