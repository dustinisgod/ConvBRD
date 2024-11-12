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

    -- Find the best mez spell for the character's level
    local bestMezSpell = spells.findBestSpell("Mez", charLevel)
    if not bestMezSpell then
        print("Error: No suitable mez spell found for level", charLevel)
        return
    end
    
    ---@diagnostic disable-next-line: undefined-field
    local maxMezLevel = mq.TLO.Spell(bestMezSpell) and mq.TLO.Spell(bestMezSpell).MaxLevel() or 0

    -- Clear expired entries from `notMezzableQueue`
    cleanupNotMezzableQueue()

    -- Get mobs within the defined mez radius
    local mobsInRange = utils.referenceLocation(gui.mezRadius) or {}
    
    -- Check if enough mobs are present to initiate mezzing
    if #mobsInRange < (gui.mezAmount or 1) then
        return
    end

    -- Process mobs in range
    local mobQueue = {}

    -- Populate mobQueue based on conditions
    for _, mob in ipairs(mobsInRange) do
        local mobID = mob.ID()
        local mobName = mob.CleanName()

        if not mobID or not mobName then
            goto continue
        end

        -- Skip if mob is a pet or in `notMezzableQueue`
        if mob.Type() == "Pet" or notMezzableQueue[mobID] then
            -- Skip this mob
        elseif mob.Level() and mob.Level() > maxMezLevel then
            notMezzableQueue[mobID] = os.time()  -- Mark as unmezzable due to level
        elseif utils.mezConfig[mq.TLO.Zone.ShortName()] and utils.mezConfig[mq.TLO.Zone.ShortName()][mobName] then
            notMezzableQueue[mobID] = os.time()  -- Mark as configured unmezzable
        elseif shouldRemez(mobID) or not mezzedQueue[mobID] then
            -- Eligible for mezzing or remezzing
            mobQueue[mobID] = true
        end
        ::continue::
    end

    -- Attempt to mez each mob in `mobQueue`
    for mobID, _ in pairs(mobQueue) do
        local attempts, mezSuccessful = 0, false

        while attempts < 2 and not mezSuccessful do
            attempts = attempts + 1
            mq.cmd("/squelch /attack off")
            mq.delay(100)

            if mq.TLO.Target.ID() ~= mobID then
                mq.cmdf("/squelch /target id %d", mobID)
                mq.delay(500)
            end

            -- Validate target distance and health before mezzing
            if not mq.TLO.Target() or mq.TLO.Target.Distance() > gui.mezRadius or mq.TLO.Target.PctHPs() < gui.mezStopPercent then
                break
            end

            -- Attempt to cast mez
            if not mq.TLO.Target.Mezzed() or mq.TLO.Target.Mezzed.Duration() < MEZ_RECHECK_THRESHOLD then
                if mq.TLO.Twist() == "TRUE" then
                    mq.cmd("/squelch /twist off")
                    mq.delay(200)
                end

                mq.cmd("/squelch /cast 8")
                mq.delay(300)

                -- Monitor casting completion and apply mez
                while mq.TLO.Me.Casting() do
                    if mq.TLO.Target.ID() ~= mobID or mq.TLO.Target.Distance() > gui.mezRadius or mq.TLO.Target.PctHPs() < gui.mezStopPercent then
                        mq.cmd("/squelch /stopcast")
                        break
                    elseif mq.TLO.Target.Mezzed() and mq.TLO.Target.Mezzed.Duration() > MEZ_RECHECK_THRESHOLD then
                        updateMezStatus(mobID, mq.TLO.Target.Mezzed.Duration() / 1000)
                        mezSuccessful = true
                        break
                    end
                    mq.delay(50)
                end
            elseif mq.TLO.Target.Mezzed() and mq.TLO.Target.Mezzed.Duration() > MEZ_RECHECK_THRESHOLD then
                updateMezStatus(mobID, mq.TLO.Target.Mezzed.Duration() / 1000)
                mezSuccessful = true
            end
        end

        -- Add to `notMezzableQueue` if mezzing attempts failed
        if not mezSuccessful then
            print(string.format("Warning: Failed to mez mob ID %d after 2 attempts.", mobID))
            notMezzableQueue[mobID] = os.time()
        else
            mobQueue[mobID] = nil
        end
    end
end

return mez
