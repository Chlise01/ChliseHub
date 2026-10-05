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

    local AnimalRenders
    pcall(function()
        AnimalRenders = require(Shared:WaitForChild("AnimalRenders"))
    end)

    -- Game objects
    local EggHitRequest = ReplicatedStorage:WaitForChild("EggHitRequest")
    local AnimalBankedRemote = ReplicatedStorage:WaitForChild("AnimalBankedRemote")

    local Build = Workspace:WaitForChild(ZonesConfig.BuildFolderName or "Build")
    local ZoneBuilds = Build:WaitForChild(ZonesConfig.ZoneBuildsName or "ZoneBuilds")
    local Pickups = Workspace:WaitForChild("AnimalPickups")
    local PromptAnchor = Workspace:WaitForChild("PromptAnchor")
    local GlobalPrompt = PromptAnchor:WaitForChild("StealPrompt")

    -- Tunables
    local HIT_DISTANCE = 7
    local EGG_APPROACH_DISTANCE = 4
    local HIT_DELAY = 0.52

    local PICKUP_SPAWN_TIMEOUT = 8
    local MAX_PICKUP_SPAWN_DISTANCE = 15

    local PET_APPROACH_DISTANCE = 3
    local PROMPT_TIMEOUT = 7
    local CARRY_TIMEOUT = 3
    local BANK_TIMEOUT = 8

    local MOVE_REFRESH = 0.08
    local MOVE_COMMAND_REFRESH = 0.75
    local MOVE_STUCK_SECONDS = 2
    local MOVE_STUCK_STUDS = 0.75

    -- Movement speed is synced 1:1 to the Humanoid's current WalkSpeed.
    -- The script never overwrites WalkSpeed.
    local HOME_STAGING_DISTANCE = 12
    local HOME_INSIDE_DISTANCE = 4
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

    local function buildPetList()
        local found = {}
        local result = {}

        if type(AnimalRenders) == "table"
            and type(AnimalRenders.Normal) == "table"
        then
            for name in pairs(AnimalRenders.Normal) do
                if type(name) == "string" and name ~= "" then
                    found[name] = true
                end
            end
        end

        for _, animal in ipairs(Pickups:GetChildren()) do
            local name =
                animal:GetAttribute("AnimalName")
                or animal.Name

            if type(name) == "string" and name ~= "" then
                found[name] = true
            end
        end

        for name in pairs(found) do
            table.insert(result, name)
        end

        table.sort(result, function(a, b)
            return a:lower() < b:lower()
        end)

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
        local _, humanoid, hrp = getCharacter()
        humanoid:MoveTo(hrp.Position)
    end

    local function walkTo(targetPosition, stopDistance, timeout, extraCheck)
        stopDistance = tonumber(stopDistance) or 3
        timeout = tonumber(timeout) or 30

        local _, humanoid, hrp = getCharacter()
        local deadline = os.clock() + timeout

        log(
            "Walk speed sync",
            "| WalkSpeed:",
            tonumber(humanoid.WalkSpeed) or 16
        )

        local lastProgressPosition = hrp.Position
        local lastProgressTime = os.clock()
        local lastMoveCommand = 0

        -- Important: jangan spam Humanoid:MoveTo terus-menerus.
        -- Saat membawa pet, spam MoveTo + physics carry/guard bisa bikin stutter.
        local function issueMove()
            humanoid:MoveTo(targetPosition)
            lastMoveCommand = os.clock()
        end

        issueMove()

        while autoFarmActive
            and hrp.Parent
            and humanoid.Health > 0
            and os.clock() < deadline
        do
            if type(extraCheck) == "function" and extraCheck() then
                stopMoving()
                return true
            end

            local distance = (hrp.Position - targetPosition).Magnitude

            if distance <= stopDistance then
                stopMoving()
                return true
            end

            -- Refresh MoveTo hanya sesekali, bukan tiap loop.
            if os.clock() - lastMoveCommand >= MOVE_COMMAND_REFRESH then
                issueMove()
            end

            local moved = (hrp.Position - lastProgressPosition).Magnitude

            if moved >= MOVE_STUCK_STUDS then
                lastProgressPosition = hrp.Position
                lastProgressTime = os.clock()
            elseif os.clock() - lastProgressTime >= MOVE_STUCK_SECONDS then
                humanoid.Jump = true
                issueMove()

                lastProgressPosition = hrp.Position
                lastProgressTime = os.clock()
            end

            task.wait(MOVE_REFRESH)
        end

        stopMoving()

        if type(extraCheck) == "function" and extraCheck() then
            return true
        end

        return (hrp.Position - targetPosition).Magnitude <= stopDistance
    end

    local function teleportTo(targetPosition, stopDistance, extraCheck)
        stopDistance = tonumber(stopDistance) or 3

        local _, humanoid, hrp = getCharacter()

        humanoid:MoveTo(hrp.Position)

        local lastTime =
            os.clock()

        while autoFarmActive
            and hrp.Parent
            and humanoid.Health > 0
        do
            if type(extraCheck) == "function"
                and extraCheck()
            then
                return true
            end

            local delta =
                targetPosition
                - hrp.Position

            local distance =
                delta.Magnitude

            if distance <= stopDistance then
                hrp.AssemblyLinearVelocity = Vector3.zero
                hrp.AssemblyAngularVelocity = Vector3.zero
                return true
            end

            local now =
                os.clock()

            local dt =
                math.clamp(
                    now - lastTime,
                    1 / 120,
                    0.12
                )

            lastTime =
                now

            local allowedSpeed =
                getCurrentMoveSpeed()

            local stepDistance =
                math.min(
                    distance,
                    allowedSpeed * dt
                )

            local nextPosition =
                hrp.Position
                + delta.Unit
                    * stepDistance

            local flatLook =
                Vector3.new(
                    delta.X,
                    0,
                    delta.Z
                )

            if flatLook.Magnitude < 0.01 then
                flatLook =
                    Vector3.new(
                        hrp.CFrame.LookVector.X,
                        0,
                        hrp.CFrame.LookVector.Z
                    )
            end

            if flatLook.Magnitude < 0.01 then
                flatLook =
                    Vector3.new(0, 0, -1)
            else
                flatLook =
                    flatLook.Unit
            end

            -- Keep Y exactly on the travel line; do not pitch upward.
            local finalPosition =
                Vector3.new(
                    nextPosition.X,
                    hrp.Position.Y,
                    nextPosition.Z
                )

            hrp.AssemblyLinearVelocity =
                Vector3.zero

            hrp.AssemblyAngularVelocity =
                Vector3.zero

            hrp.CFrame =
                CFrame.lookAt(
                    finalPosition,
                    finalPosition + flatLook
                )

            task.wait()
        end

        return false
    end

    local function tweenTo(targetPosition, stopDistance, timeout, extraCheck)
        stopDistance = tonumber(stopDistance) or 3
        timeout = tonumber(timeout) or 30

        local _, humanoid, hrp = getCharacter()

        humanoid:MoveTo(hrp.Position)

        local distance = (hrp.Position - targetPosition).Magnitude

        if distance <= stopDistance then
            return true
        end

        local syncedSpeed =
            getCurrentMoveSpeed()

        local duration =
            math.max(
                0.05,
                distance / syncedSpeed
            )

        duration =
            math.min(
                duration,
                timeout
            )

        log(
            "Tween speed sync",
            "| WalkSpeed:", syncedSpeed,
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
                extraCheck
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
            return
                type(isBanked) == "function"
                and isBanked() == true
        end

        local function interrupted()
            if bankedNow() then
                return true
            end

            return
                type(isCarrying) == "function"
                and not isCarrying()
        end

        local _, _, hrp = getCharacter()

        local stagingPosition,
            insidePosition =
            getHomeEntryPoints(
                hitbox,
                hrp.Position
            )

        log(
            "Returning home",
            "| Mode:", movementMode,
            "| WalkSpeed:", getCurrentMoveSpeed(),
            "| Inside:", HOME_INSIDE_DISTANCE
        )

        -- Tween/Teleport only handles the long part.
        -- Safe-zone crossing still uses the real Humanoid walk.
        if movementMode == "Tween" then
            tweenTo(
                stagingPosition,
                2.25,
                60,
                interrupted
            )
        elseif movementMode == "Teleport" then
            teleportTo(
                stagingPosition,
                2.5,
                interrupted
            )
        end

        if bankedNow() then
            return "banked"
        end

        if not isCarrying() then
            return "dropped"
        end

        -- Cross only a few studs into the owned safe zone.
        walkTo(
            insidePosition,
            1.25,
            30,
            interrupted
        )

        if bankedNow() then
            return "banked"
        end

        if not isCarrying() then
            return "dropped"
        end

        -- Once the pet is in the safe zone, do not start a new egg
        -- while the guardian chase state is still active.
        -- Keep retrying the shallow safe position until chase is gone.
        while autoFarmActive
            and isCarrying()
            and isBeingChased()
            and not bankedNow()
        do
            local _, _, currentHRP =
                getCharacter()

            if not isBankablePosition(currentHRP.Position) then
                walkTo(
                    insidePosition,
                    1.0,
                    8,
                    interrupted
                )
            else
                -- Re-issue a normal walk target without going deep into base.
                local _, humanoid =
                    getCharacter()

                humanoid:MoveTo(insidePosition)
            end

            task.wait(HOME_RETRY_WAIT)
        end

        if bankedNow() then
            return "banked"
        end

        if not isCarrying() then
            return "dropped"
        end

        local _, _, currentHRP =
            getCharacter()

        local bankable =
            isBankablePosition(
                currentHRP.Position
            )

        log(
            "Safe-zone state",
            "| Bankable:", bankable,
            "| Chased:", isBeingChased(),
            "| Carrying:", isCarrying()
        )

        if bankable and not isBeingChased() then
            return "safe"
        end

        return "failed"
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
        local found = {}
        local result = {}

        for _, zoneName in ipairs(MASTER_ZONES) do
            local zone = ZoneBuilds:FindFirstChild(zoneName)
            local eggs = zone and zone:FindFirstChild("Eggs")

            if eggs then
                for _, container in ipairs(eggs:GetChildren()) do
                    local egg = resolveEgg(container)

                    if egg then
                        local name = getEggName(egg)

                        if not found[name] then
                            found[name] = true
                            table.insert(result, name)
                        end
                    end
                end
            end
        end

        table.sort(result)

        return result
    end

    local MASTER_EGGS = buildEggList()

    local function findBestEgg()
        local _, _, hrp = getCharacter()

        local bestEgg
        local bestZone
        local bestDistance = math.huge

        for _, zoneName in ipairs(MASTER_ZONES) do
            if isSelected(selectedZones, zoneName) then
                local zone = ZoneBuilds:FindFirstChild(zoneName)
                local eggs = zone and zone:FindFirstChild("Eggs")

                if eggs then
                    for _, container in ipairs(eggs:GetChildren()) do
                        local egg = resolveEgg(container)

                        if validEgg(egg) then
                            local eggName = getEggName(egg)

                            if isSelected(selectedEggs, eggName) then
                                local distance = (hrp.Position - egg.Position).Magnitude

                                if distance < bestDistance then
                                    bestEgg = egg
                                    bestZone = zoneName
                                    bestDistance = distance
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

    local function waitResultPet(before, zoneName, eggPosition)
        local deadline = os.clock() + PICKUP_SPAWN_TIMEOUT

        while autoFarmActive and os.clock() < deadline do
            local best
            local bestDistance = math.huge

            for _, animal in ipairs(Pickups:GetChildren()) do
                if not before[animal] and animal:IsA("Model") then
                    local hatched = animal:GetAttribute("Hatched")
                    local animalZone = normalizeZone(animal:GetAttribute("ZoneId"))

                    if hatched == true
                        and (not animalZone or animalZone == zoneName)
                    then
                        local position = animal:GetPivot().Position
                        local distance = (position - eggPosition).Magnitude

                        if distance <= MAX_PICKUP_SPAWN_DISTANCE
                            and distance < bestDistance
                        then
                            best = animal
                            bestDistance = distance
                        end
                    end
                end
            end

            if best then
                log(
                    "Result pet:",
                    best:GetAttribute("AnimalName") or best.Name,
                    "| SpawnDist:",
                    string.format("%.2f", bestDistance)
                )

                task.wait(0.15)

                return best
            end

            task.wait(0.04)
        end

        return nil
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
            eggPosition
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

        if distance <= 1.5 then
            return true
        end

        if distance <= 6 then
            local weight = animal:GetAttribute("WeightKg")
            local shownWeight = promptKg(prompt)

            if typeof(weight) == "number"
                and typeof(shownWeight) == "number"
                and math.abs(weight - shownWeight) <= 1.1
            then
                return true
            end

            local animalName = animal:GetAttribute("AnimalName") or animal.Name
            local objectText = normalizeText(prompt.ObjectText)
            local targetText = normalizeText(animalName)

            if targetText ~= ""
                and objectText:find(targetText, 1, true)
            then
                return true
            end
        end

        return false
    end

    local function findCurrentPrompt(animal)
        for _, object in ipairs(animal:GetDescendants()) do
            if object:IsA("ProximityPrompt")
                and object.Enabled
                and promptMatchesAnimal(object, animal)
            then
                return object
            end
        end

        if GlobalPrompt.Enabled
            and promptMatchesAnimal(GlobalPrompt, animal)
        then
            return GlobalPrompt
        end

        return nil
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
        local ok, active = pcall(function()
            return ChaseState.IsActive(LocalPlayer)
        end)

        return ok and active == true
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

        if signature.HatchId ~= nil
            and hatchId ~= nil
        then
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
        if not animal or not animal.Parent then
            return false
        end

        local petPosition =
            animal:GetPivot().Position

        if not walkNear(
            petPosition,
            PET_APPROACH_DISTANCE,
            35
        ) then
            log(
                "Failed to reach pet:",
                animalName
            )

            return false
        end

        local prompt =
            waitStealPrompt(animal)

        if not prompt then
            warn(
                "[CHLISE HUB] StealPrompt not found:",
                animalName
            )

            return false
        end

        local promptPosition =
            getPromptPosition(prompt)

        if promptPosition then
            local _, _, hrp =
                getCharacter()

            if (
                hrp.Position
                - promptPosition
            ).Magnitude > 7 then
                if not walkNear(
                    promptPosition,
                    2.5,
                    15
                ) then
                    return false
                end
            end
        end

        log(
            "Fire steal:",
            animalName
        )

        fireproximityprompt(prompt)

        if not waitUntilCarrying(
            CARRY_TIMEOUT
        ) then
            warn(
                "[CHLISE HUB] Carry state not detected:",
                animalName
            )

            return false
        end

        return true
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

        if minimumPetWeight > 0
            and weight < minimumPetWeight
        then
            log(
                "Discard hatch result:",
                animalName,
                "| Weight:",
                weight,
                "| Minimum:",
                minimumPetWeight
            )

            return false
        end

        if not isSelected(
            selectedPets,
            animalName
        ) then
            log(
                "Discard hatch result:",
                animalName,
                "| Pet filter mismatch"
            )

            -- The pet has not been picked up yet, so "discard"
            -- means leave/ignore this hatch result.
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

        if not pickUpAnimal(
            animal,
            animalName
        ) then
            return false
        end

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

        -- If the guardian knocks the pet out of our hands,
        -- locate the same HatchId and pick it up again.
        while autoFarmActive
            and not banked
        do
            if not isCarrying() then
                local dropped =
                    waitForDroppedAnimal(
                        signature
                    )

                if not dropped then
                    bankConnection:Disconnect()

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

        bankConnection:Disconnect()

        if banked then
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
                        log("Result pet not found.")
                    end

                    task.wait(0.15)
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
        MASTER_ZONES,
        true,
        selectedZones,

        function(value)
            selectedZones = value
        end
    )

    FarmSection:AddDropdown(
        "BSAEEggs",
        "Egg Selection",
        MASTER_EGGS,
        true,
        selectedEggs,

        function(value)
            selectedEggs = value
        end
    )

    FarmSection:AddDropdown(
        "BSAEPetFilter",
        "Pet Filter",
        MASTER_PETS,
        true,
        selectedPets,

        function(value)
            selectedPets = value
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
