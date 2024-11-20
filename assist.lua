local mq = require('mq')
local gui = require('gui')
local utils = require('utils')
local pull = require('pull')

local DEBUG_MODE = true
-- Debug print helper function
local function debugPrint(...)
    if DEBUG_MODE then
        print(...)
    end
end

local assist = {}

local charLevel = mq.TLO.Me.Level()

function assist.assistRoutine()
debugPrint("Running assist routine.")
    if not gui.botOn or not gui.assistMelee then
        debugPrint("Bot is off or assistMelee is disabled.")
        return
    end

    if gui.pullOn and pull.campQueueCount < 0 then
            debugPrint("Pull is on and campQueueCount is less than 0.")
        return
    elseif gui.pullOn and gui.keepMobsInCamp and gui.keepMobsInCampAmount < pull.campQueueCount then
        debugPrint("Pull is on, keepMobsInCamp is enabled, and campQueueCount is greater than keepMobsInCampAmount.")
        return
    end

    -- Use reference location to find mobs within assist range
    local mobsInRange = utils.referenceLocation(gui.assistRange) or {}
    debugPrint("Mobs in range: " .. #mobsInRange)
    if #mobsInRange == 0 then
        debugPrint("No mobs in range.")
        return
    end

    -- Check if the main assist is a valid PC, is alive, and is in the same zone
    local mainAssistSpawn = mq.TLO.Spawn(gui.mainAssist)
    if mainAssistSpawn and mainAssistSpawn.Type() == "PC" and not mainAssistSpawn.Dead() then
        debugPrint("Main assist is a valid PC and is alive.")
        mq.cmdf("/squelch /assist %s", gui.mainAssist)
        mq.delay(200)  -- Short delay to allow the assist command to take effect
    else
        debugPrint("Main assist is not a valid PC or is dead.")
        return
    end

    -- Re-check the target after assisting to confirm it's an NPC within range
    if not mq.TLO.Target() or mq.TLO.Target.Type() ~= "NPC" then
        debugPrint("No target or target is not an NPC.")
        return
    end

    if mq.TLO.Target() and mq.TLO.Target.PctHPs() <= gui.assistPercent and mq.TLO.Target.Distance() <= gui.assistRange and mq.TLO.Stick() == "OFF" and not mq.TLO.Target.Mezzed() then
        if gui.stickFront then
            mq.cmd('/squelch /nav stop')
            mq.delay(100)
            mq.cmd("/stick moveback 0")
            mq.delay(100)
            mq.cmdf("/squelch /stick front %d uw", gui.stickDistance)
            mq.delay(100)
        elseif gui.stickBehind then
            mq.cmd('/squelch /nav stop')
            mq.delay(100)
            mq.cmd("/stick moveback 0")
            mq.delay(100)
            mq.cmdf("/squelch /stick behind %d uw", gui.stickDistance)
            mq.delay(100)
        end

        while mq.TLO.Target() and mq.TLO.Target.Distance() > gui.stickDistance do
            mq.delay(10)
        end

        if mq.TLO.Target() and not mq.TLO.Target.Mezzed() and mq.TLO.Target.PctHPs() <= gui.assistPercent and mq.TLO.Target.Distance() <= gui.assistRange then
            mq.cmd("/squelch /attack on")
        elseif mq.TLO.Target() and (mq.TLO.Target.Mezzed() or mq.TLO.Target.PctHPs() > gui.assistPercent or mq.TLO.Target.Distance() > (gui.assistRange + 30)) then
            mq.cmd("/squelch /attack off")
        end
    end

    if mq.TLO.Me.CombatState() == "COMBAT" and mq.TLO.Target() and mq.TLO.Target.Dead() ~= ("true" or "nil") then

        if mq.TLO.Target() and not mq.TLO.Target.Mezzed() and mq.TLO.Target.PctHPs() <= gui.assistPercent and mq.TLO.Target.Distance() <= gui.assistRange then
            mq.cmd("/squelch /attack on")
        elseif mq.TLO.Target() and (mq.TLO.Target.Mezzed() or mq.TLO.Target.PctHPs() > gui.assistPercent or mq.TLO.Target.Distance() > (gui.assistRange + 30)) then
            mq.cmd("/squelch /attack off")
        end

        if mq.TLO.Target() and gui.singSongs and gui.singAgroReduction and charLevel >= 53 and mq.TLO.Me.PctAggro() >= 80 and mq.TLO.Target.Distance() <= gui.assistRange then
            mq.cmd("/squelch /twist off")
            mq.delay(200)
            mq.cmd("/squelch /cast 9")
            while mq.TLO.Target() and mq.TLO.Me.PctAggro() > 80 and mq.TLO.Target.AggroHolder() do
                mq.delay(10)
            end
        end

        utils.useSeloWithPercussion()

        local lastStickDistance = nil

        if mq.TLO.Target() and mq.TLO.Stick() == "ON" then
            local stickDistance = gui.stickDistance -- current GUI stick distance
            local lowerBound = stickDistance * 0.9
            local upperBound = stickDistance * 1.1
            local targetDistance = mq.TLO.Target.Distance()
            
            -- Check if stickDistance has changed
            if lastStickDistance ~= stickDistance then
                lastStickDistance = stickDistance
                mq.cmdf("/squelch /stick moveback %s", stickDistance)
            end
    
            -- Check if the target distance is out of bounds and adjust as necessary
            if mq.TLO.Target.ID() then
                if targetDistance > upperBound then
                    mq.cmdf("/squelch /stick moveback %s", stickDistance)
                    mq.delay(100)
                elseif targetDistance < lowerBound then
                    mq.cmdf("/squelch /stick moveback %s", stickDistance)
                    mq.delay(100)
                end
            end
        end
        
        mq.delay(50)
    end
end

return assist