local mq = require('mq')
local spells = require('spells')
local gui = require('gui')
local utils = require('utils')

local mez = {}

local charLevel = mq.TLO.Me.Level()

function mez.mezRoutine()
    if not gui.botOn or (not gui.singSongs or not gui.singMez) or charLevel < 15 then
        return
    end

    print("Mez routine started.")
    -- Find the best mez spell for the character's level
    local bestMezSpell = spells.findBestSpell("Mez", charLevel)
    if not bestMezSpell then
        return
    end

    ---@diagnostic disable-next-line: undefined-field
    local maxMezLevel = mq.TLO.Spell(bestMezSpell) and mq.TLO.Spell(bestMezSpell).MaxLevel() or 0

    -- Get mobs in range for potential mez
    local mobsInRange = utils.referenceLocation(gui.mezRadius) or {}
    local mezCount = gui.mezCount or 0  -- Ensure mezCount has a default value

    -- Check if any mobs are within assist range for mez
    if #mobsInRange == 0 then
        return
    end

    -- Check if there are enough mobs to initiate mez
    if #mobsInRange < mezCount then
        return
    end

    -- Create queues for mob management
    local mobQueue = {}
    local notMezzableQueue = {}
    local mezzedQueue = {}

    -- Get the current zone name
    local zoneName = mq.TLO.Zone.ShortName() or "UnknownZone"

    -- Populate mobQueue with mobs that meet level requirements or add ignored mobs to notMezzableQueue
    for _, mob in ipairs(mobsInRange) do
        local mobName = mob.CleanName()
        
        -- Check if the mob is in the ignore list for the current zone
        if utils.mezConfig[zoneName] and utils.mezConfig[zoneName][mobName] then
            table.insert(notMezzableQueue, mob.ID())
            print(string.format("Mob '%s' is in the ignore list for zone '%s'. Adding to notMezzableQueue.", mobName, zoneName))
        elseif maxMezLevel > 0 and mob.Level() <= maxMezLevel then
            table.insert(mobQueue, mob.ID())
        else
            table.insert(notMezzableQueue, mob.ID())
        end
    end

    -- Filter mobQueue against mobs in notMezzableQueue and mezzedQueue
    for i = #mobQueue, 1, -1 do
        local mobID = mobQueue[i]
        if utils.tableContains(notMezzableQueue, mobID) or (mezzedQueue[mobID] and mezzedQueue[mobID] > os.time() + 10) then
            table.remove(mobQueue, i)
        end
    end

    -- Cycle through mobQueue to attempt mez on each mob
    for _, mobID in ipairs(mobQueue) do
        local attempts = 0  -- Initialize attempts counter for each mob
        local mezSuccessful = false  -- Track if mez was successful

        while attempts < 2 do
            attempts = attempts + 1  -- Increment attempt counter

            mq.cmd("/attack off")
            mq.delay(100)
            mq.cmdf("/target id %d", mobID)
            mq.delay(200)

            -- Check if the target is still the intended mobID
            if not mq.TLO.Target() or mq.TLO.Target.ID() ~= mobID then
                print(string.format("Target ID changed from %d. Exiting mez attempt.", mobID))
                break
            end

            -- Check the target's distance from the player to ensure it's within mez range
            if mq.TLO.Target.Distance() <= gui.mezRadius then
                -- Check if the aggro holder is in the group or raid
                local aggroHolder = mq.TLO.Target.AggroHolder()
                local inGroupOrRaid = aggroHolder and (mq.TLO.Group.Member(aggroHolder)() or mq.TLO.Raid.Member(aggroHolder)())

                if aggroHolder and inGroupOrRaid then
                    -- Ensure the target meets the mez requirements
                    if mq.TLO.Target.PctHPs() and mq.TLO.Target.PctHPs() > gui.mezStopPercent 
                        and mq.TLO.Target.Mezzed() and mq.TLO.Target.Mezzed.Duration() < 5000 
                        and mq.TLO.Target.Level() and mq.TLO.Target.Level() <= maxMezLevel then
                    
                        mq.cmd("/twist off")
                        mq.delay(200)

                        mq.cmd("/cast 8")  -- Begin casting mez
                        mq.delay(100)

                        -- Wait for the cast to finish
                        while mq.TLO.Me.Casting() do
                            -- Re-check if the target is still the intended mobID during casting
                            if mq.TLO.Target.ID() ~= mobID then
                                print("Target ID changed during casting. Stopping mez attempt.")
                                mq.cmd("/stopcast")
                                break
                            end

                            local mezDuration = mq.TLO.Target.Mezzed.Duration()
                            if mezDuration and mezDuration > 10000 then
                                mq.cmd("/stopcast")
                                mezSuccessful = true
                                break
                            end
                            mq.delay(50)
                        end

                        -- Check if mez was successful
                        local mezDuration = mq.TLO.Target.Mezzed.Duration() or 0
                        if mezDuration > 10000 then
                            mezzedQueue[mobID] = os.time() + mezDuration / 1000
                            mezSuccessful = true
                            break
                        end
                    end
                else
                    print(string.format("Skipping mez on mob ID %d. Aggro holder is not in our group or raid.", mobID))
                    break
                end
            else
                print(string.format("Skipping mob ID %d as it is out of mez range.", mobID))
                break
            end

            -- If the mez was successful, exit the retry loop for this mob
            if mezSuccessful then
                break
            else
                print(string.format("Mez attempt %d on mob ID %d failed. Retrying...", attempts, mobID))
                mq.delay(500)  -- Short delay before retrying the mez attempt
            end
        end

        -- If both attempts failed, add the mob to notMezzableQueue
        if not mezSuccessful then
            table.insert(notMezzableQueue, mobID)
            print(string.format("Failed to mez mob ID %d after 2 attempts. Adding to notMezzableQueue.", mobID))
        end
    end
end

return mez