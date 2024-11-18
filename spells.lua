mq = require('mq')
local gui = require('gui')

local spells = {

    RunSpeed = {
        {level = 49, name = "Selo's Accelerating Chorus"},      --runspeed 2m
        {level = 5, name = "Selo's Accelerando"}                --runspeed 12s
    },
    Haste = {

        {level = 57, name = "McVaxius' Rousing Rondo"},         --haste/str/atk/dmgshield
        {level = 50, name = "Verses of Victory"},               --haste/str/agi/ac
        {level = 42, name = "McVaxius' Berserker Crescendo"},   --haste/str/ac
        {level = 36, name = "Vilia's Verses of Celerity"},      --haste/agi/ac
        {level = 10, name = "Anthem de Arms"}                   --haste/str
    },
    IntWisBuff = {
        {level = 44, name = "Cassindra's Elegy"}                --int/wis
    },
   Regen = {
        {level = 55, name = "Cantata of Replenishment"},        --hpregen/manaregen
        {level = 32, name = "Cassindra's Chorus of Clarity"},   --manaregen
        {level = 20, name = "Cassindra's Chant of Clarity"},    --manaregen
        {level = 6, name = "Hymn of Restoration"}               --hpregen
    },
    MrBuff = {
        {level = 17, name = "Guardian Rhythms"}                 --mr/ac
    },

    ResistanceFireCold = {
        {level = 9, name = "Elemental Rhythms"}                 --mr/cold/fire/ac
    },

    ResistancePoisonDisease = {
        {level = 13, name = "Purifying Rhythms"}                --mr/poison/disease/ac
    },
    Absorb = {
        {level = 41, name = "Psalm of Mystic Shielding"}        --mr/ac/hp/absorb
    },
    Mez = {
        {level = 53, name = "Song of Twilight"},                --mez55
        {level = 28, name = "Crission's Pixie Strike"},         --mez37
        {level = 15, name = "Kelin's Lucid Lullaby"}            --mez30

  
    },
    Slow = {
        {level = 51, name = "Largo's Assonant Binding"},        --slow/snare/-agi
        {level = 20, name = "Largo's Melodic Binding"}          --slow/-ac
    },
    ReduceHate = {
        {level = 53, name = "Song of Dawn"}                     --reducehate
    }
}

-- Function to find the best spell for a given type and level
function spells.findBestSpell(spellType, charLevel)
    local spells = spells[spellType]

    if not spells then
        return nil -- Return nil if the spell type doesn't exist
    end

    -- General spell search for other types and levels
    for _, spell in ipairs(spells) do
        if charLevel >= spell.level then
            return spell.name
        end
    end

    return nil
end

function spells.loadDefaultSpells(charLevel)
    local defaultSpells = {}

    if charLevel >= 5 then
        defaultSpells[1] = spells.findBestSpell("RunSpeed", charLevel)
    end
    if gui.meleeGroup and charLevel >= 10 then
        defaultSpells[2] = spells.findBestSpell("Haste", charLevel)
    end
    if charLevel >= 6 then
        defaultSpells[3] = spells.findBestSpell("Regen", charLevel)
    end
    if charLevel >= 17 then
        defaultSpells[4] = spells.findBestSpell("MrBuff", charLevel)
    end
    if not gui.singDiseasePoisonResist and charLevel >= 9 then
        defaultSpells[5] = spells.findBestSpell("ResistanceFireCold", charLevel)
    elseif gui.singDiseasePoisonResist and charLevel >= 13 then
        defaultSpells[5] = spells.findBestSpell("ResistancePoisonDisease", charLevel)
    end
    if gui.singMagicResist and charLevel >= 41 then
        defaultSpells[6] = spells.findBestSpell("Absorb", charLevel)
    end
    if charLevel >= 20 then
        defaultSpells[7] = spells.findBestSpell("Slow", charLevel)
    end
    if charLevel >= 44 then
        defaultSpells[8] = spells.findBestSpell("IntWisBuff", charLevel)
    end
    if charLevel >= 53 then
        defaultSpells[9] = spells.findBestSpell("ReduceHate", charLevel)
    end
    if charLevel >= 15 then
        defaultSpells[10] = spells.findBestSpell("Mez", charLevel)
    end
    return defaultSpells
end

-- Function to memorize spells in the correct slots with delay
function spells.memorizeSpells(spells)
    for slot, spellName in pairs(spells) do
        if spellName then
            -- Check if the spell is already in the correct slot
            if mq.TLO.Me.Gem(slot)() == spellName then
                printf(string.format("Spell %s is already memorized in slot %d", spellName, slot))
            else
                -- Clear the slot first to avoid conflicts
                mq.cmdf('/memorize "" %d', slot)
                mq.delay(500)  -- Short delay to allow the slot to clear

                -- Issue the /memorize command to memorize the spell in the slot
                mq.cmdf('/memorize "%s" %d', spellName, slot)
                mq.delay(1000)  -- Initial delay to allow the memorization command to take effect

                -- Loop to check if the spell is correctly memorized
                local maxAttempts = 10
                local attempt = 0
                while mq.TLO.Me.Gem(slot)() ~= spellName and attempt < maxAttempts do
                    mq.delay(500)  -- Check every 0.5 seconds
                    attempt = attempt + 1
                end

                -- Check if memorization was successful
                if mq.TLO.Me.Gem(slot)() ~= spellName then
                    printf(string.format("Failed to memorize spell: %s in slot %d", spellName, slot))
                else
                    printf(string.format("Successfully memorized %s in slot %d", spellName, slot))
                end
            end
        end
    end
end


function spells.loadAndMemorizeSpell(spellType, level, spellSlot)

    local bestSpell = spells.findBestSpell(spellType, level)

    if not bestSpell then
        printf("No spell found for type: " .. spellType .. " at level: " .. level)
        return
    end

    -- Check if the spell is already in the correct spell gem slot
    if mq.TLO.Me.Gem(spellSlot).Name() == bestSpell then
        printf("Spell " .. bestSpell .. " is already memorized in slot " .. spellSlot)
        return true
    end

    -- Memorize the spell in the correct slot
    mq.cmdf('/memorize "%s" %d', bestSpell, spellSlot)

    -- Add a delay to wait for the spell to be memorized
    local maxAttempts = 10
    local attempt = 0
    while mq.TLO.Me.Gem(spellSlot).Name() ~= bestSpell and attempt < maxAttempts do
        mq.delay(2000) -- Wait 2 seconds before checking again
        attempt = attempt + 1
    end

    -- Check if the spell is now memorized correctly
    if mq.TLO.Me.Gem(spellSlot).Name() == bestSpell then
        printf("Successfully memorized spell " .. bestSpell .. " in slot " .. spellSlot)
        return true
    else
        printf("Failed to memorize spell " .. bestSpell .. " in slot " .. spellSlot)
        return false
    end
end

function spells.startup(charLevel)

    local defaultSpells = spells.loadDefaultSpells(charLevel)

    spells.memorizeSpells(defaultSpells)
end

return spells