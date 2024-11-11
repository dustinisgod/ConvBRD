local mq = require('mq')
local gui = require('gui')
local utils = require('utils')
local nav = require('nav')
local corpsedrag = require('corpsedrag')

local pullQueue = {}
local campQueue = {}
local aggroQueue = {}  -- New queue to track mobs on their way to camp
local campQueueCount = 0  -- Variable to track the number of mobs in campQueue

local messagePrintedFlags = {
    CLR = false,
    DRU = false,
    SHM = false,
    ENC = false
}
local pullPauseTimer = os.time()  -- Initialize with the current time

-- Function to add a mob to the campQueue
local function addToCampQueue(mob)
    table.insert(campQueue, mob)
    campQueueCount = campQueueCount + 1
end

-- Function to remove a mob from the campQueue
local function removeFromCampQueue(index)
    table.remove(campQueue, index)
    campQueueCount = campQueueCount - 1
end

local function getCleanName(name)
    if not name then
        return ""
    end
    return name:gsub("_%d+$", ""):gsub("_", " ")
end

local function updatePullQueue()
    -- Initialize pullQueue and reference campQueue location
    pullQueue = {}
    campQueue = utils.referenceLocation(gui.campSize) or {}

    -- Set pulling parameters
    local pullDistanceXY = gui.pullDistanceXY
    local pullDistanceZ = gui.pullDistanceZ
    local pullLevelMin = gui.pullLevelMin
    local pullLevelMax = gui.pullLevelMax

    -- Retrieve all spawns and initialize best target variables
    local allSpawns = mq.getAllSpawns()
    local shortestPathLength = math.huge
    local bestTarget = nil

    -- Iterate over all spawns to find the best pull target
    for _, spawn in ipairs(allSpawns) do
        local distanceXY = spawn.Distance()
        local distanceZ = spawn.DistanceZ()
        local level = spawn.Level()
        local cleanName = getCleanName(spawn.Name())

        -- Check if the spawn is already in campQueue
        local inPullQueue = false
        for _, pullMob in ipairs(gui.campQueue) do
            if pullMob.ID() == spawn.ID() then
                inPullQueue = true
                break
            end
        end

        if inPullQueue then
            goto continue
        end

        -- Check if spawn's name is in the pull ignore list
        if utils.pullConfig[cleanName] then
            goto continue
        end

        -- Evaluate spawn against pull conditions
        if spawn.Type() == "NPC" and level >= pullLevelMin and level <= pullLevelMax and distanceXY <= pullDistanceXY and distanceZ <= pullDistanceZ then
            local pathLength = mq.TLO.Navigation.PathLength("id " .. spawn.ID())()
            if pathLength and pathLength > -1 and pathLength < shortestPathLength then
                bestTarget = spawn
                shortestPathLength = pathLength
            end
        end

        ::continue::
    end

    -- Add the best target to the pullQueue if one is found
    if bestTarget then
        table.insert(pullQueue, bestTarget)
    end

    -- Sort pullQueue by distance
    table.sort(pullQueue, function(a, b) return a.Distance() < b.Distance() end)
end

local function returnToCampIfNeeded()
    -- Check if camp location is set
    if nav.campLocation then
        -- Retrieve player and camp coordinates
        local playerX, playerY = mq.TLO.Me.X(), mq.TLO.Me.Y()
        local campX = tonumber(nav.campLocation.x) or 0
        local campY = tonumber(nav.campLocation.y) or 0
        local campZ = tonumber(nav.campLocation.z) or 0

        -- Calculate distance to camp
        local distanceToCamp = math.sqrt((playerX - campX)^2 + (playerY - campY)^2)

        -- Navigate back to camp if beyond threshold
        if distanceToCamp > 50 then
            mq.cmdf("/nav loc %f %f %f", campY, campX, campZ)
            while mq.TLO.Navigation.Active() do
                mq.delay(50)
            end
            mq.cmd("/face")  -- Face camp direction after reaching camp
        end
    end
end

local function updateAggroQueue()
    -- Retrieve mobs within the camp assist range
    local campMobs = utils.referenceLocation(gui.campSize) or {}

    -- Iterate through aggroQueue in reverse to handle removals
    for i = #aggroQueue, 1, -1 do
        local mobID = aggroQueue[i]
        local mob = mq.TLO.Spawn(mobID)  -- Retrieve mob spawn from ID

        -- Check if mob exists and is alive
        if not mob or not mob() or mob.Dead() then
            table.remove(aggroQueue, i)  -- Remove dead or nonexistent mob
        else
            -- Target the mob to check aggro
            mq.cmdf("/target id %d", mobID)
            mq.delay(10)  -- Small delay to allow targeting

            -- Verify mob is still the target and has aggro
            if mq.TLO.Target.ID() ~= mobID then
                table.remove(aggroQueue, i)  -- Remove if target doesn't match
            elseif mq.TLO.Target.PctAggro() == 0 or not mq.TLO.Target.AggroHolder() then
                table.remove(aggroQueue, i)  -- Remove if no aggro
            else
                -- Check if mob is within the camp assist range
                local inCamp = false
                for _, campMob in ipairs(campMobs) do
                    if campMob.ID() == mobID then
                        inCamp = true
                        break
                    end
                end

                -- Handle mob positioning relative to camp range
                if not inCamp and mob.Distance() and tonumber(mob.Distance()) <= 5 then
                    -- Mob is close but outside camp range (no specific action needed here)
                elseif inCamp then
                    table.insert(gui.campQueue, mob)  -- Add mob to camp queue
                    table.remove(aggroQueue, i)  -- Remove from aggroQueue
                end
            end
        end
    end
end


local function pullTarget()

    if #pullQueue == 0 then
        return
    end

    local target = pullQueue[1]
    mq.cmd("/attack off")
    mq.delay(100)

    mq.cmdf("/target id %d", target.ID())
    mq.delay(200, function() return mq.TLO.Target.ID() == target.ID() end)

    if mq.TLO.Target and mq.TLO.Target.ID() ~= target.ID() then
        return
    end

    if mq.TLO.Target and mq.TLO.Target.Mezzed() and mq.TLO.Target.Distance() <= (gui.campSize + 20) then
        table.insert(gui.campQueue, target)
        table.remove(pullQueue, 1)
        return
    end

    if mq.TLO.Target and mq.TLO.Target.PctAggro() > 0 then
        local targetID = target.ID()
        if type(targetID) == "number" then
            table.insert(aggroQueue, targetID)
        end
        table.remove(pullQueue, 1)
        returnToCampIfNeeded()
        return
    end

    mq.cmdf("/nav id %d", target.ID())
    mq.delay(50, function() return mq.TLO.Navigation.Active() end)

    while mq.TLO.Target and mq.TLO.Navigation.Active() do
        local distance = target.Distance()
        local pullRange = 160

        if gui.corpseDrag then
            corpsedrag.dragCheck()
            break
        end

        if mq.TLO.Target and distance <= pullRange and distance > 40 and mq.TLO.Target.LineOfSight() then
            mq.cmd("/nav stop")
            mq.delay(200)
        end
    end

    local attempts = 0
    while attempts < 3 do
        if mq.TLO.Target() and not mq.TLO.Navigation.Active() and mq.TLO.Target.LineOfSight() and mq.TLO.Target.PctAggro() <= 0 then
            local pullability = "220"
            mq.cmdf("/alt act %s", pullability)

            local timeout = os.time() + 2
            while mq.TLO.Target() and mq.TLO.Target.PctAggro() <= 0 do
                mq.delay(1)
                if os.time() > timeout then
                    attempts = attempts + 1
                    break
                end
            end
            if mq.TLO.Target() and mq.TLO.Target.PctAggro() > 0 then
                local targetID = mq.TLO.Target.ID()
                if type(targetID) == "number" then
                    table.insert(aggroQueue, targetID)
                end
                returnToCampIfNeeded()
                return
            end
        else
            returnToCampIfNeeded()
            return
        end
        mq.delay(200)
    end

    if mq.TLO.Target.Distance > 15 then
        mq.cmd("/nav target")
        mq.delay(50)
        
        while mq.TLO.Target and mq.TLO.Navigation.Active() and target.Distance() > 15 and mq.TLO.Target.PctAggro() < 1 do
            mq.delay(10)
        end

    else
        local timeout = os.time() + 2
        mq.cmd("/attack on")
        while mq.TLO.Target() and mq.TLO.Target.PctAggro() < 1 do
            mq.delay(1)
            if os.time() > timeout then
                mq.cmd("/squelch /attack off")
                return
            end
        end
        if mq.TLO.Target() and mq.TLO.Target.PctAggro() > 0 then
            mq.cmd("/squelch /attack off")
            local targetID = mq.TLO.Target.ID()
            if type(targetID) == "number" then
                table.insert(aggroQueue, targetID)
            end
            returnToCampIfNeeded()
            return
        end
    end
end

local function isGroupMemberAliveAndSufficientMana(classShortName, manaThreshold)
    for i = 0, 5 do
        local member = mq.TLO.Group.Member(i)
        if member() and member.Class.ShortName() == classShortName then
            local isAlive = member.PctHPs() > 0
            local sufficientMana = member.PctMana() >= manaThreshold
            
            -- Reset flag if status has improved (e.g., they are alive and have sufficient mana)
            if isAlive and sufficientMana and messagePrintedFlags[classShortName] then
                messagePrintedFlags[classShortName] = false
            end
            
            return isAlive and sufficientMana
        end
    end
    return true
end

local function checkGroupMemberStatus()
    if gui.groupWatch then
        if gui.groupWatchCLR and not isGroupMemberAliveAndSufficientMana("CLR", gui.groupWatchCLRMana) then
            if not messagePrintedFlags["CLR"] then
                print("Cleric is either dead or low on mana. Pausing pull.")
                messagePrintedFlags["CLR"] = true
            end
            return false
        end
        if gui.groupWatchDRU and not isGroupMemberAliveAndSufficientMana("DRU", gui.groupWatchDRUMana) then
            if not messagePrintedFlags["DRU"] then
                print("Druid is either dead or low on mana. Pausing pull.")
                messagePrintedFlags["DRU"] = true
            end
            return false
        end
        if gui.groupWatchSHM and not isGroupMemberAliveAndSufficientMana("SHM", gui.groupWatchSHMMana) then
            if not messagePrintedFlags["SHM"] then
                print("Shaman is either dead or low on mana. Pausing pull.")
                messagePrintedFlags["SHM"] = true
            end
            return false
        end
        if gui.groupWatchENC and not isGroupMemberAliveAndSufficientMana("ENC", gui.groupWatchENCMana) then
            if not messagePrintedFlags["ENC"] then
                print("Enchanter is either dead or low on mana. Pausing pull.")
                messagePrintedFlags["ENC"] = true
            end
            return false
        end
    end
    return true
end

local shownMessage = false  -- Flag to track if the message has been shown

-- Main check function to run periodically
local function checkHealthAndBuff()
    local hasRezSickness = mq.TLO.Me.Buff(13087)()
    local healthPct = mq.TLO.Me.PctHPs()
    local rooted = mq.TLO.Me.Rooted()

    if not shownMessage and (hasRezSickness or healthPct < 70 or rooted) then
        print("Cannot pull: Either rez sickness is present or health is below 70%.")
        shownMessage = true  -- Set the flag to avoid repeating the message
    elseif shownMessage and healthPct >= 70 then
        -- Reset the flag when health is back above 70%
        shownMessage = false
    end
end

local function pullRoutine()
    checkHealthAndBuff()

    if gui.botOn and gui.pullOn then
        -- Check if pullPause is enabled and timer has exceeded pullPauseTimer minutes
        if gui.pullPause and os.difftime(os.time(), pullPauseTimer) >= (gui.pullPauseTimer * 60) then
            -- Ensure player is in camp
            if utils.isInCamp() then
                print("Pull routine paused for " .. gui.pullPauseDuration .. " minutes.")

                -- Pause timer by waiting the pullPauseDuration
                mq.delay(gui.pullPauseDuration * 60 * 1000) -- Convert minutes to milliseconds

                -- Clear and reinitialize aggroQueue on resume to prevent stale entries
                aggroQueue = {}
                updateAggroQueue()

                -- Resume pull routine and reset pullPauseTimer
                pullPauseTimer = os.time() -- Reset the timer
            end
        end

        -- Ensure campQueue and aggroQueue are initialized
        gui.campQueue = utils.referenceLocation(gui.campSize) or {}
        aggroQueue = aggroQueue or {}

        -- Update aggroQueue and check if mobs reached camp
        updateAggroQueue()

        -- Ensure gui.keepMobsInCampAmount is set and has a sensible value
        local targetCampAmount = gui.keepMobsInCampAmount or 1

        -- Determine the pull condition based on gui.keepMobsInCamp
        local pullCondition
        if gui.keepMobsInCamp then
            pullCondition = function() return #gui.campQueue < targetCampAmount and #aggroQueue == 0 end
        else
            pullCondition = function() return #gui.campQueue == 0 and #aggroQueue == 0 end
        end

        -- Pull loop with dynamic pull condition
        while pullCondition() do
            -- Check group member health and mana status before each pull
            local groupStatusOk = checkGroupMemberStatus()
            if not groupStatusOk then
                break -- Exit the loop if a group member is dead or low on mana
            end

            updatePullQueue()
            if #pullQueue > 0 then
                -- Attempt to pull target
                pullTarget()

                -- Update campQueue and campMobs after each pull
                gui.campQueue = utils.referenceLocation(gui.campSize) or {}

                updateAggroQueue()
            else
                break
            end
        end
    end
end

return {
    updatePullQueue = updatePullQueue,
    pullRoutine = pullRoutine,
    pullQueue = pullQueue,
    campQueue = campQueue,
    aggroQueue = aggroQueue,
    campQueueCount = campQueueCount,
}