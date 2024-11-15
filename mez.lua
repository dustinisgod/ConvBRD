local mq = require('mq')
local spells = require('spells')
local gui = require('gui')
local utils = require('utils')

local mez = {}

-- Persistent queues for mezzing control
local notMezzableQueue = {}   -- Tracks unmezzable mobs due to level, repeated failure, etc.
local mezzedQueue = {}        -- Tracks mobs currently mezzed with sufficient duration and expiration

local charLevel = mq.TLO.Me.Level()

-- Constants
local NOT_MEZZABLE_EXPIRATION = 30  -- Expiration duration in seconds for `notMezzableQueue` entries
local MEZ_RECHECK_THRESHOLD = 5     -- Recheck only when mez duration is < 5 seconds

local DEBUG_MODE = true
-- Debug print helper function
local function debugPrint(...)
    if DEBUG_MODE then
        print(...)
    end
end

-- Remove expired entries from `notMezzableQueue`
local function cleanupNotMezzableQueue()
    local currentTime = os.time()
    for mobID, timestamp in pairs(notMezzableQueue) do
        if currentTime - timestamp > NOT_MEZZABLE_EXPIRATION then
            notMezzableQueue[mobID] = nil
        end
    end
end

-- Update the expiration time for a mezzed mob
local function updateMezStatus(mobID, duration)
    mezzedQueue[mobID] = os.time() + duration
end

-- Check if a mob needs to be remezzed based on its remaining mez duration
local function shouldRemez(mobID)
    local expireTime = mezzedQueue[mobID]
    return expireTime and (expireTime - os.time() <= MEZ_RECHECK_THRESHOLD)
end

-- Main mezzing routine
function mez.mezRoutine()
        -- Check bot status and settings
    if not gui.botOn or not (gui.singSongs and gui.singMez) or charLevel < 15 then
        return
    end

    -- Get mobs within the defined mez radius
    local mobsInRange = utils.referenceLocation(gui.mezRadius) or {}
    debugPrint("Mobs in range:", #mobsInRange)
    
    -- Check if enough mobs are present to initiate mezzing
    if #mobsInRange < (gui.mezAmount or 1) then
        return
    end

    -- Find the best mez spell for the character's level
    local bestMezSpell = spells.findBestSpell("Mez", charLevel)
    if not bestMezSpell then
        print("Error: No suitable mez spell found for level", charLevel)
        return
    end
    debugPrint("Best Mez Spell:", bestMezSpell)

    ---@diagnostic disable-next-line: undefined-field
    local maxMezLevel = mq.TLO.Spell(bestMezSpell) and mq.TLO.Spell(bestMezSpell).MaxLevel() or 0
    debugPrint("Max Mez Level:", maxMezLevel)
    -- Clear expired entries from `notMezzableQueue`
    cleanupNotMezzableQueue()

    -- Process mobs in range
    local mobQueue = {}

    -- Populate mobQueue based on conditions
    for _, mob in ipairs(mobsInRange) do
        local mobID = mob.ID()
        local mobName = mob.CleanName()

        debugPrint("Mob ID: ", mobID, " Mob Name: ", mobName)

        -- Check if mobID or mobName is valid
        if mobID and mobName then
            if mob.Level() and mob.Level() > maxMezLevel then
                debugPrint("Mob is unmezzable due to level: ", mob.Level())
                -- Mark as unmezzable due to level
                notMezzableQueue[mobID] = os.time()
            elseif utils.mezConfig[mq.TLO.Zone.ShortName()] and utils.mezConfig[mq.TLO.Zone.ShortName()][mobName] then
                debugPrint("Mob is unmezzable due to configuration.")
                -- Mark as configured unmezzable
                notMezzableQueue[mobID] = os.time()
            elseif shouldRemez(mobID) or not mezzedQueue[mobID] then
                debugPrint("Mob is eligible for mezzing.")
                -- Eligible for mezzing or remezzing
                mobQueue[mobID] = true
            end
        end
    end

    -- Attempt to mez each mob in `mobQueue`
    for mobID, _ in pairs(mobQueue) do
        debugPrint("Mezzing mob ID:", mobID)
        local attempts, mezSuccessful = 0, false


        while attempts < 2 and not mezSuccessful do
            attempts = attempts + 1
            debugPrint("Mezzing attempt:", attempts)
            mq.cmd("/squelch /attack off")
            mq.delay(100)

            if mq.TLO.Target.ID() ~= mobID then
                debugPrint("Targeting mob ID:", mobID)
                mq.cmdf("/squelch /target id %d", mobID)
                mq.delay(500)
            end

            -- Validate target distance and health before mezzing
            if mq.TLO.Target() and mq.TLO.Target.Distance() > gui.mezRadius then
                debugPrint("Target out of range! Distance:", mq.TLO.Target.Distance(), " Radius: ", gui.mezRadius)
                break
            end

            -- Validate target distance and health before mezzing
            if mq.TLO.Target() and mq.TLO.Target.PctHPs() < gui.mezStopPercent then
                debugPrint("Target Hp to low!")
                break
            end

            -- Attempt to cast mez
            if mq.TLO.Target.ID() and not mq.TLO.Target.Mezzed() or (mq.TLO.Target.Mezzed() and mq.TLO.Target.Mezzed.Duration() < MEZ_RECHECK_THRESHOLD) then
                if mq.TLO.Twist() == "TRUE" then
                    debugPrint("Twist off for mezzing.")
                    mq.cmd("/squelch /twist off")
                    mq.delay(200)
                end

                mq.cmdf("/squelch /cast 10")
                debugPrint("Casting mez spell gem 10")
                mq.delay(100)

                -- Monitor casting completion and apply mez with a 4-second timeout
                local castStartTime = os.time()
                while mq.TLO.Me.Casting() do
                    if (os.time() - castStartTime) > 5 then
                        mq.cmd("/squelch /stopcast")
                        debugPrint("Casting timed out after 5 seconds.")
                        break
                    end

                    if mq.TLO.Target.ID() ~= mobID or mq.TLO.Target.Distance() > gui.mezRadius or mq.TLO.Target.PctHPs() < gui.mezStopPercent then
                        mq.cmd("/squelch /stopcast")
                        debugPrint("Casting interrupted: Range: " .. mq.TLO.Target.Distance() .. " HP%: " .. mq.TLO.Target.PctHPs())
                        break
                    elseif mq.TLO.Target.ID() and mq.TLO.Target.Mezzed() and mq.TLO.Target.Mezzed.Duration() > MEZ_RECHECK_THRESHOLD then
                        mq.cmd("/squelch /stopcast")
                        updateMezStatus(mobID, mq.TLO.Target.Mezzed.Duration() / 1000)
                        mezSuccessful = true
                        debugPrint("Mez successful.")
                        break
                    end

                    mq.delay(10)
                end

                mq.delay(100)

                if mq.TLO.Target.ID() and mq.TLO.Target.Mezzed() and mq.TLO.Target.Mezzed.Duration() > MEZ_RECHECK_THRESHOLD then
                updateMezStatus(mobID, mq.TLO.Target.Mezzed.Duration() / 1000)
                debugPrint("Mez successful on second check.")
                mezSuccessful = true
                break
                end

            elseif mq.TLO.Target.ID() and mq.TLO.Target.Mezzed() and mq.TLO.Target.Mezzed.Duration() > MEZ_RECHECK_THRESHOLD then
                updateMezStatus(mobID, mq.TLO.Target.Mezzed.Duration() / 1000)
                debugPrint("Mez successful on second check.")
                mezSuccessful = true
                break
            end
        end

        -- Add to `notMezzableQueue` if mezzing attempts failed
        if not mezSuccessful then
            print(string.format("Warning: Failed to mez mob ID %d after 2 attempts.", mobID))
            notMezzableQueue[mobID] = os.time()
            debugPrint("Adding mob ID to notMezzableQueue:", mobID)
        else
            mobQueue[mobID] = nil
            debugPrint("Removing mob ID from mobQueue:", mobID)
        end
        mq.delay(50)
    end
    debugPrint("Mezzing routine completed.")
end

return mez
