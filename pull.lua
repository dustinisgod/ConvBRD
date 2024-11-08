local mq = require('mq')
local gui = require('gui')
local utils = require('utils')
local nav = require('nav')

local pullQueue = {}
gui.campQueue = {}
local aggroQueue = {}  -- New queue to track mobs on their way to camp

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

local function updatePullQueue()
    -- Initialize pullQueue and reference campQueue location
    pullQueue = {}
    gui.campQueue = utils.referenceLocation(gui.campSize) or {}

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
            elseif mq.TLO.Target.PctAggro() == 0 then
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
    -- Check if the pullQueue is empty
    if #pullQueue == 0 then
        return
    end

    -- Initialize target
    local target = pullQueue[1]
    mq.cmd("/attack off")
    mq.delay(200)

    -- Target the mob
    mq.cmdf("/target id %d", target.ID())
    mq.delay(1000, function() return mq.TLO.Target.ID() == target.ID() end)

    -- Check if targeting was successful
    if mq.TLO.Target and mq.TLO.Target.ID() ~= target.ID() then
        return
    end

    -- Handle mezzed mob
    if mq.TLO.Target and mq.TLO.Target.Mezzed() and mq.TLO.Target.Distance() <= (gui.campSize + 20) then
        table.insert(gui.campQueue, target)
        table.remove(pullQueue, 1)
        return
    end

    -- Check if target already has aggro
    if mq.TLO.Target and mq.TLO.Target.PctAggro() > 0 then
        local targetID = target.ID()
        if type(targetID) == "number" then
            table.insert(aggroQueue, targetID)
        end
        table.remove(pullQueue, 1)
        returnToCampIfNeeded()
        return
    end

    -- Begin navigation towards the target
    mq.cmdf("/nav id %d", target.ID())
    mq.delay(100, function() return mq.TLO.Navigation.Active() end)

    -- Pull or melee depending on distance
    while mq.TLO.Target and mq.TLO.Navigation.Active() do
        local distance = target.Distance()
        local pullRange = 160

        -- Use pull ability if within range but further than 40 units
        if mq.TLO.Target and distance <= pullRange and distance > 40 and mq.TLO.Target.LineOfSight() then
            mq.cmd("/nav stop")
            mq.delay(100)

            -- Attempt to use pull ability up to 3 times
            local attempts = 0
            while attempts < 3 do
                if mq.TLO.Target() and not mq.TLO.Navigation.Active() and mq.TLO.Target.LineOfSight() then
                    mq.cmd("/alt act 220")  -- Replace with actual ability ID if needed
                    mq.delay(200)

                    -- Check if aggro was gained
                    if mq.TLO.Target and mq.TLO.Target.PctAggro() > 0 then
                        local targetID = target.ID()
                        if type(targetID) == "number" then
                            table.insert(aggroQueue, targetID)
                        end
                        returnToCampIfNeeded()
                        return  -- Exit after successful pull
                    end
                else
                    break  -- Exit if conditions aren't met
                end
                attempts = attempts + 1
                mq.delay(500)  -- Delay before retrying
            end

        -- Switch to melee pull if within 40 units
        elseif distance <= 40 then
            mq.cmd("/nav stop")
            mq.delay(200)

            -- Navigate closer if more than 15 units away
            if distance > 15 then
                mq.cmd("/nav target")
                mq.delay(100, function() return mq.TLO.Navigation.Active() end)

                -- Wait until within 15 units or navigation stops
                while mq.TLO.Target and mq.TLO.Navigation.Active() and target.Distance() > 15 do
                    mq.delay(10)
                    if mq.TLO.Target and mq.TLO.Target.PctAggro() > 0 then
                        mq.cmd("/nav stop")
                        mq.delay(200)

                        local targetID = target.ID()
                        if type(targetID) == "number" then
                            table.insert(aggroQueue, targetID)
                        end
                        returnToCampIfNeeded()
                        return
                    end
                end
                mq.cmd("/nav stop")
                mq.delay(200)
            end

            -- Engage with melee attack
            mq.cmd("/attack on")
            local timeout = os.time() + 2

            -- Poll for aggro status
            while mq.TLO.Target() and mq.TLO.Target.PctAggro() == 0 do
                mq.delay(1)
                if os.time() > timeout then
                    mq.cmd("/attack off")
                    return
                end
            end

            -- Confirm target has aggro
            local aggro = mq.TLO.Target.PctAggro()
            if mq.TLO.Target() and aggro > 0 then
                mq.cmd("/attack off")

                local targetID = mq.TLO.Target.ID()
                if type(targetID) == "number" then
                    table.insert(aggroQueue, targetID)
                end
                returnToCampIfNeeded()
                return -- Exit after successful melee pull
            end
        end
        mq.delay(10)  -- Small delay to prevent loop overuse
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

local function pullRoutine()
    -- Check if player has buff ID 13087 or health is below 70%
    local hasRezSickness = mq.TLO.Me.Buff(13087)()
    local healthPct = mq.TLO.Me.PctHPs()

    if hasRezSickness or healthPct < 70 then
        print("Cannot pull: Either rez sickness is present or health is below 70%.")
        return
    end

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

        -- Continue pulling until campQueue has the desired number of mobs
        while #gui.campQueue < targetCampAmount and #aggroQueue == 0 do

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
    campQueue = gui.campQueue,
    aggroQueue = aggroQueue,  -- Export aggroQueue for external monitoring if needed
}