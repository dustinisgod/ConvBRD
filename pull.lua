local mq = require('mq')
local gui = require('gui')
local utils = require('utils')
local nav = require('nav')
local corpsedrag = require('corpsedrag')

local DEBUG_MODE = false
-- Debug print helper function
local function debugPrint(...)
    if DEBUG_MODE then
        print(...)
    end
end

local pullQueue = {}
local campQueue = {}
local aggroQueue = {}  -- New queue to track mobs on their way to camp
local campQueueCount = 0  -- Variable to track the number of mobs in campQueue

local pullability = "220"

local zone = mq.TLO.Zone.ShortName() or "Unknown"

local messagePrintedFlags = {
    CLR = false,
    DRU = false,
    SHM = false,
    ENC = false
}
local pullPauseTimer = os.time()  -- Initialize with the current time

local function getCleanName(name)
    if not name then
        return ""
    end
    return name:gsub("_%d+$", ""):gsub("_", " ")
end

local function atan2(y, x)
    if x > 0 then return math.atan(y / x) end
    if x < 0 and y >= 0 then return math.atan(y / x) + math.pi end
    if x < 0 and y < 0 then return math.atan(y / x) - math.pi end
    if x == 0 and y > 0 then return math.pi / 2 end
    if x == 0 and y < 0 then return -math.pi / 2 end
    return 0
end

local function calculateHeadingTo(targetY, targetX)
    if not targetY or not targetX then
        print("calculateHeadingTo: Invalid target coordinates", targetY, targetX)
        return nil
    end

    local playerY = mq.TLO.Me.Y()
    local playerX = mq.TLO.Me.X()

    if not playerY or not playerX then
        print("calculateHeadingTo: Invalid player coordinates")
        return nil
    end

    local deltaY = targetY - playerY
    local deltaX = targetX - playerX
    local heading = math.deg(atan2(deltaX, deltaY))

    if heading < 0 then heading = heading + 360 end
    return heading
end

local function updatePullQueue()
    -- Initialize pullQueue and reference campQueue location
    pullQueue = {}
    campQueue = utils.referenceLocation(gui.campSize) or {}

    -- Predefined heading ranges
    local headingRanges = {}
    if gui.pullNorth then table.insert(headingRanges, {min = 315, max = 45}) end
    if gui.pullWest then table.insert(headingRanges, {min = 45, max = 135}) end
    if gui.pullSouth then table.insert(headingRanges, {min = 135, max = 225}) end
    if gui.pullEast then table.insert(headingRanges, {min = 225, max = 315}) end

    -- Combine heading ranges into a single list
    local function isHeadingValid(heading)
        for _, range in ipairs(headingRanges) do
            if range.min <= range.max then
                if heading >= range.min and heading <= range.max then
                    return true
                end
            else -- Wrap-around case
                if heading >= range.min or heading <= range.max then
                    return true
                end
            end
        end
        return false
    end

    -- Retrieve pulling parameters
    local pullDistanceXY = gui.pullDistanceXY
    local pullDistanceZ = gui.pullDistanceZ
    local pullLevelMin = gui.pullLevelMin
    local pullLevelMax = gui.pullLevelMax

    -- Retrieve all spawns and initialize best target variables
    local allSpawns = mq.getAllSpawns()
    local shortestPathLength = math.huge
    local bestTarget = nil

    for _, spawn in ipairs(allSpawns) do
        -- Attempt to retrieve coordinates from spawn object or fallback to TLO
        local targetY = spawn.Y() or mq.TLO.Spawn("id " .. spawn.ID()).Y()
        local targetX = spawn.X() or mq.TLO.Spawn("id " .. spawn.ID()).X()
    
        -- Skip spawns with invalid coordinates
        if not targetY or not targetX then
            print("Skipping spawn due to invalid coordinates:", spawn.Name() or "Unnamed")
            goto continue
        end
    
        -- Calculate heading to the spawn
        local headingToSpawn = calculateHeadingTo(targetY, targetX)
        if not headingToSpawn then
            print("Skipping spawn due to heading calculation failure:", spawn.Name() or "Unnamed")
            goto continue
        end
    
        -- Validate other conditions (distance, level, type, etc.)
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
    
        -- Validate heading range
        if not isHeadingValid(headingToSpawn) then
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
        debugPrint("Added target to pullQueue:", bestTarget.Name())
    end

    -- Sort pullQueue by distance
    table.sort(pullQueue, function(a, b) return a.Distance() < b.Distance() end)
    debugPrint("Updated pullQueue:", #pullQueue)
end

local function isGroupOrRaidMember(memberName)
    local aggroHolderName = mq.TLO.Target.AggroHolder.Name()  -- Get the name of the aggro holder

    -- Check raid members if not already found in group
    if mq.TLO.Raid.Members() > 0 then
        local raidSize = mq.TLO.Raid.Members() or 0
        for i = 1, raidSize do
            if mq.TLO.Raid.Member(i).Name() == aggroHolderName then
            return true
            else
                return false
            end
        end
    elseif mq.TLO.Me.Grouped() then  -- Verify the player is in a group
        local groupSize = mq.TLO.Group.Members() or 0
        for i = 1, groupSize do
            if mq.TLO.Group.Member(i).Name() == aggroHolderName then
                return true
            else
                return false
            end
        end
    end
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
            mq.cmdf("/squelch /nav loc %f %f %f", campY, campX, campZ)
            while mq.TLO.Navigation.Active() do
                utils.useSeloWithPercussion()
                mq.delay(50)
            end
            mq.cmd("/face fast")  -- Face camp direction after reaching camp
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
            mq.cmdf("/squelch /target id %d", mobID)
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
    mq.cmd("/squelch /attack off")
    mq.delay(100)

    mq.cmdf("/squelch /target id %d", target.ID())
    mq.delay(200, function() return mq.TLO.Target.ID() == target.ID() end)

    if mq.TLO.Target() and mq.TLO.Target.ID() ~= target.ID() then
        return
    end

    if mq.TLO.Target() and mq.TLO.Target.Mezzed() and mq.TLO.Target.Distance() <= (gui.campSize + 20) then
        table.insert(gui.campQueue, target)
        table.remove(pullQueue, 1)
        return
    end

    if mq.TLO.Target() and mq.TLO.Target.PctAggro() > 0 or isGroupOrRaidMember() then
        local targetID = target.ID()
        if type(targetID) == "number" then
            table.insert(aggroQueue, targetID)
        end
        table.remove(pullQueue, 1)
        returnToCampIfNeeded()
        return
    end

    mq.cmdf("/squelch /nav id %d", target.ID())
    debugPrint("Navigating to target:", target.Name())
    mq.delay(50, function() return mq.TLO.Navigation.Active() end)

    while mq.TLO.Target() and mq.TLO.Target.PctAggro() <= 0 do
        if gui.botOn and gui.pullOn then
            if not mq.TLO.Target() then
                print("Error: No target selected. Exiting pull routine.")
                return
            end

            utils.useSeloWithPercussion()

            if mq.TLO.Target() and mq.TLO.Target.LineOfSight() and mq.TLO.Target.PctAggro() <= 0 and mq.TLO.Target.Distance() < 160 then
                debugPrint("Target is in line of sight and within range.", mq.TLO.Target.LineOfSight())

                if not pullability then
                    print("Error: pullability is nil. Check if the ability ID is correctly set.")
                    return
                end
                debugPrint("Pulling target:", target.Name())
                if mq.TLO.Me.AltAbilityReady(pullability) then
                    mq.cmdf("/squelch /alt act %s", pullability)
                end
            end

            if mq.TLO.Target() and not mq.TLO.Navigation.Active() and mq.TLO.Target.PctAggro() <= 0 then
                debugPrint("Navigating to target:", target.Name())
                mq.cmdf("/squelch /nav id %d", target.ID())
            end
        else
            debugPrint("Bot is off. Exiting pull routine.")
            return
        end
        mq.delay(200)
    end

    if mq.TLO.Target() and mq.TLO.Target.PctAggro() > 0 then
        debugPrint("Target has aggro. Stopping pull routine.")
        mq.cmd("/squelch /nav stop")
        mq.delay(100)
        local targetID = mq.TLO.Target.ID()
        if type(targetID) == "number" then
            debugPrint("Adding target to aggroQueue:", targetID)
            table.insert(aggroQueue, targetID)
        end
        debugPrint("Removing target from pullQueue:", target.Name())
        returnToCampIfNeeded()
        return
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
    local hasRezSickness = mq.TLO.Me.Buff("Revival Sickness")()
    local healthPct = mq.TLO.Me.PctHPs()
    local rooted = mq.TLO.Me.Rooted()

    if not shownMessage and healthPct < 70  then
        print("Cannot pull: Health is below 70%.")
        shownMessage = true
    elseif shownMessage and hasRezSickness == "Revival Sickness" then
        print("Cannot pull: Revival Sickness is active.")
        shownMessage = true
    elseif shownMessage and rooted then
        print("Cannot pull: Rooted.")
        shownMessage = true
    else
        shownMessage = false
        return true
    end
end

local function pullRoutine()
    if not gui.botOn and gui.pullOn then
        debugPrint("Bot is off. Exiting pull routine.")
        return
    end
    checkHealthAndBuff()
    if gui.pullPause and os.difftime(os.time(), pullPauseTimer) >= (gui.pullPauseTimer * 60) then
        if utils.isInCamp() then
            debugPrint("Pull routine paused for " .. gui.pullPauseDuration .. " minutes.")
            print("Pull routine paused for " .. gui.pullPauseDuration .. " minutes.")
            mq.delay(gui.pullPauseDuration * 60 * 1000)  -- Pause timer

            aggroQueue = {}
            updateAggroQueue()
            debugPrint("AggroQueue count:", #aggroQueue)

            pullPauseTimer = os.time()  -- Reset the timer
        end
    end

    -- Check if nav.campLocation exists and has a valid zone
    if not nav.campLocation or not nav.campLocation.zone or nav.campLocation.zone == "nil" then
        print("Camp location is not set. Aborting pull routine.")
        return
    end

    -- Check if the current zone does not match camp zone
    if zone ~= nav.campLocation.zone then
        print("Current zone does not match camp zone. Aborting pull routine.")
        return
    end

    gui.campQueue = utils.referenceLocation(gui.campSize) or {}
    campQueueCount = #gui.campQueue  -- Update campQueueCount to track mob count
    debugPrint("CampQueue count:", campQueueCount)

    aggroQueue = aggroQueue or {}
    updateAggroQueue()
    debugPrint("AggroQueue count:", #aggroQueue)

    local targetCampAmount = gui.keepMobsInCampAmount or 1

    local pullCondition
    if gui.keepMobsInCamp then
        pullCondition = function() return campQueueCount < targetCampAmount and #aggroQueue == 0 end
    else
        pullCondition = function() return campQueueCount == 0 and #aggroQueue == 0 end
    end

    while pullCondition() do
        -- Check if pullOn was unchecked during the routine
        if not gui.pullOn then
            debugPrint("Pull routine stopped.")
            return
        elseif mq.TLO.Navigation.Active() then
            debugPrint("Navigation is active. Stopping pull routine.")
            mq.cmd("/squelch /nav stop")  -- Stop any active navigation
            return
        end

        local groupStatusOk = checkGroupMemberStatus()
        if not groupStatusOk then
            debugPrint("Group status is not OK. Pausing pull routine.")
            break
        end

        updatePullQueue()
        debugPrint("PullQueue count:", #pullQueue)  
        if #pullQueue > 0 then
            pullTarget()

            gui.campQueue = utils.referenceLocation(gui.campSize) or {}
            campQueueCount = #gui.campQueue  -- Refresh campQueueCount after updating campQueue

            updateAggroQueue()
            debugPrint("AggroQueue count:", #aggroQueue)
        else
            break
        end
    end
end

return {
    updatePullQueue = updatePullQueue,
    pullRoutine = pullRoutine,
    pullQueue = pullQueue,
    campQueue = campQueue,
    aggroQueue = aggroQueue,
    campQueueCount = campQueueCount
}