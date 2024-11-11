local mq = require('mq')
local gui = require('gui')
local utils = require('utils')
local pull = require('pull')

local assist = {}

local charLevel = mq.TLO.Me.Level()

function assist.assistRoutine()

    if not gui.botOn or not gui.assistMelee then
        return
    end

    if gui.pullOn and pull.campQueueCount < 0 then
        return
    elseif gui.pullOn and gui.keepMobsInCamp and gui.keepMobsInCampAmount < pull.campQueueCount then
        return
    end

    -- Use reference location to find mobs within assist range
    local mobsInRange = utils.referenceLocation(gui.assistRange) or {}
    if #mobsInRange == 0 then
        return
    end

    -- Check if the main assist is a valid PC, is alive, and is in the same zone
    local mainAssistSpawn = mq.TLO.Spawn(gui.mainAssist)
    if mainAssistSpawn and mainAssistSpawn.Type() == "PC" and not mainAssistSpawn.Dead() then
        mq.cmdf("/assist %s", gui.mainAssist)
        mq.delay(200)  -- Short delay to allow the assist command to take effect
    else
        return
    end

    -- Re-check the target after assisting to confirm it's an NPC within range
    if not mq.TLO.Target() or mq.TLO.Target.Type() ~= "NPC" then
        return
    end

    if mq.TLO.Target() and mq.TLO.Target.PctHPs() <= gui.assistPercent and mq.TLO.Target.Distance() <= gui.assistRange and mq.TLO.Stick() == "OFF" and not mq.TLO.Target.Mezzed() then
        if gui.stickFront then
            mq.cmdf("/stick front %d uw", gui.stickDistance)
            mq.delay(100)
            mq.cmd("/face")
        elseif gui.stickBehind then
            mq.cmdf("/stick behind %d uw", gui.stickDistance)
            mq.delay(100)
            mq.cmd("/face")
            
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

    if mq.TLO.Me.CombatState() == "COMBAT" and mq.TLO.Target() and mq.TLO.Target.PctHPs() > 0 then

        if mq.TLO.Target() and not mq.TLO.Target.Mezzed() and mq.TLO.Target.PctHPs() <= gui.assistPercent and mq.TLO.Target.Distance() <= gui.assistRange then
            mq.cmd("/squelch /attack on")
        elseif mq.TLO.Target() and (mq.TLO.Target.Mezzed() or mq.TLO.Target.PctHPs() > gui.assistPercent or mq.TLO.Target.Distance() > (gui.assistRange + 30)) then
            mq.cmd("/squelch /attack off")
        end

        if mq.TLO.Target() and gui.singSongs and gui.singAgroReduction and charLevel >= 53 and mq.TLO.Me.PctAggro() >= 80 and mq.TLO.Target.Distance() <= gui.assistRange then
            mq.cmd("/twist off")
            mq.delay(200)
            mq.cmd("/cast 7")
            while mq.TLO.Target() and mq.TLO.Me.PctAggro() > 80 and mq.TLO.Target.AggroHolder() do
                mq.delay(10)
            end
        end

        if mq.TLO.Target() and mq.TLO.Target.Distance() > gui.stickDistance then
            if gui.stickFront then
                mq.cmdf("/stick front %d uw", gui.stickDistance)
                mq.delay(100)
                mq.cmd("/face")
            elseif gui.stickBehind then
                mq.cmdf("/stick behind %d uw", gui.stickDistance)
                mq.delay(100)
                mq.cmd("/face")
            end
        elseif mq.TLO.Target() and mq.TLO.Target.Distance() < (gui.stickDistance / 2) then
            if gui.stickFront then
                mq.cmdf("/stick front %d uw", gui.stickDistance)
                mq.delay(100)
                mq.cmd("/face")
            elseif gui.stickBehind then
                mq.cmdf("/stick behind %d uw", gui.stickDistance)
                mq.delay(100)
                mq.cmd("/face")
            end
        end
        mq.delay(50)
    end
end

return assist