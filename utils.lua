local mq = require('mq')
local gui = require('gui')
local nav = require('nav')
local spells = require('spells')
local corpsedrag = require('corpsedrag')

local DEBUG_MODE = false
-- Debug print helper function
local function debugPrint(...)
    if DEBUG_MODE then
        print(...)
    end
end

local utils = {}

utils.IsUsingDanNet = true
utils.IsUsingTwist = true
utils.IsUsingCast = true
utils.IsUsingMelee = false
utils.IsUsingExchange = true

utils.mezConfig = {}
local mezConfigPath = mq.configDir .. '/' .. 'Conv_mez_ignore_list.lua'

utils.pullConfig = {}
local pullConfigPath = mq.configDir .. '/' .. 'Conv_pull_ignore_list.lua'

local charLevel = mq.TLO.Me.Level()

function utils.PluginCheck()
    if utils.IsUsingDanNet then
        if not mq.TLO.Plugin('mq2dannet').IsLoaded() then
            printf("Plugin \ayMQ2DanNet\ax is required. Loading it now.")
            mq.cmd('/plugin mq2dannet noauto')
        end
        -- turn off fullname mode in DanNet
        if mq.TLO.DanNet.FullNames() then
            mq.cmd('/dnet fullnames off')
        end
        if utils.IsUsingTwist then
            if not mq.TLO.Plugin('mq2twist').IsLoaded() then
                printf("Plugin \ayMQ2Twist\ax is required. Loading it now.")
                mq.cmd('/plugin mq2twist noauto')
            end
        end
        if utils.IsUsingCast then
            if not mq.TLO.Plugin('mq2cast').IsLoaded() then
                printf("Plugin \ayMQ2Cast\ax is required. Loading it now.")
                mq.cmd('/plugin mq2cast noauto')
            end
        end
        if not utils.IsUsingMelee then
            if mq.TLO.Plugin('mq2melee').IsLoaded() then
                printf("Plugin \ayMQ2Melee\ax is not recommended. Unloading it now.")
                mq.cmd('/plugin mq2melee unload')
            end
        end
        if not utils.IsUsingExchange then
            if mq.TLO.Plugin('mq2exchange').IsLoaded() then
                printf("Plugin \ayMQ2Exchange\ax is required. Loading it now.")
                mq.cmd('/plugin mq2exchange noauto')
            end
        end
    end
end

function utils.isInGroup()
    local inGroup = mq.TLO.Group() and mq.TLO.Group.Members() > 0
    return inGroup
end

-- Utility: Check if the player is in a group or raid
function utils.isInRaid()
    local inRaid = mq.TLO.Raid.Members() > 0
    return inRaid
end

-- Helper function to check if the target is in campQueue
function utils.isTargetInCampQueue(targetID)
    local pull = require('pull')
    for _, mob in ipairs(pull.campQueue) do
        if mob.ID() == targetID then
            return true
        end
    end
    return false
end

-- Function to find and equip the best percussion instrument
local function equipBestPercussionInstrument()
    local bestInstrument = nil
    local highestModifier = 0

    -- Iterate through all inventory slots (0-31 for main inventory and bags)
    for slot = 0, 31 do
        local item = mq.TLO.Me.Inventory(slot)
        if item() then
            -- Check if the item is a percussion instrument
            if item.Type() == "Percussion Instrument" then
                local modifier = item.InstrumentMod() or 0
                if modifier > highestModifier then
                    bestInstrument = item
                    highestModifier = modifier
                end
            end
        end
    end

    if not bestInstrument then
        print("No percussion instrument found.")
        return nil
    end

    debugPrint("Best percussion instrument:", bestInstrument.Name())
    return bestInstrument.Name()
end

-- Function to use Selo's Sonata with the best percussion instrument
function utils.useSeloWithPercussion()
    local sonata = "Selo's Sonata"
    if gui.singRunSpeed and (not mq.TLO.Me.Buff(sonata)() or mq.TLO.Me.Buff(sonata).Duration() < 5) then
        local bestInstrument = equipBestPercussionInstrument()
        if bestInstrument then
            -- Swap the item into the offhand slot
            mq.cmdf('/exchange "%s" offhand', bestInstrument)
            mq.delay(200)
            
            -- Activate Selo's Sonata
            mq.cmd("/alt act 3704")
        else
            print("Failed to equip a percussion instrument.")
        end
    else
        return
    end
end

local lastNavTime = 0

function utils.monitorNav()

    if gui.botOn and (gui.chaseon or gui.returntocamp) and not gui.pullOn then
        if not gui then
            printf("Error: gui is nil")
            return
        end

        local currentTime = os.time()

        if gui.returntocamp and (currentTime - lastNavTime >= 5) then
            nav.checkCampDistance()
            lastNavTime = currentTime
        elseif gui.chaseon and (currentTime - lastNavTime >= 2) then
            nav.chase()
            lastNavTime = currentTime
        end
    else
        return
    end
end

local lastCorpseDragTime = 0

function utils.monitorCorpseDrag()

    if gui.botOn and gui.corpsedrag then
        if not gui then
            printf("Error: gui is nil")
            return
        end

        local currentTime = os.time()

        if gui.corpsedrag and (currentTime - lastCorpseDragTime >= 10) then
            corpsedrag.corpsedragRoutine()
            lastCorpseDragTime = currentTime
        end
    else
        return
    end
end

function utils.assistMonitor()
local assist = require('assist')
debugPrint("assistMonitor")
    if gui.botOn then
        if not gui.assistMelee then
            debugPrint("not gui.assistMelee")
            return
        end

        if gui.pullOn then
            debugPrint("gui.pullOn")
            gui.campQueue = gui.campQueue or {}
            local campQueueSize = #gui.campQueue

            if gui.keepMobsInCamp then
                debugPrint("gui.keepMobsInCamp")
                if campQueueSize >= gui.keepMobsInCampAmount then
                    debugPrint("campQueueSize >= gui.keepMobsInCampAmount")
                    assist.assistRoutine()
                end
            else
                if campQueueSize >= 1 then
                    debugPrint("campQueueSize >= 1")
                    assist.assistRoutine()
                end
            end
        else
            debugPrint("not gui.pullOn")
            assist.assistRoutine()
        end
    else
        debugPrint("not gui.botOn")
        return
    end
end

function utils.setMainAssist(charName)
    if charName and charName ~= "" then
        -- Remove spaces, numbers, and symbols
        charName = charName:gsub("[^%a]", "")
        
        -- Capitalize the first letter and make the rest lowercase
        charName = charName:sub(1, 1):upper() .. charName:sub(2):lower()

        gui.mainAssist = charName
    end
end

-- Utility function to check if a table contains a given value
function utils.tableContains(table, value)
    for _, v in ipairs(table) do
        if v == value then
            return true
        end
    end
    return false
end

local hasLoggedError = false

function utils.isInCamp(range)

    range = range or 10  -- Default to a 10-unit range if none is provided

    -- Determine reference location (camp location or main assist's location)
    local referenceLocation
    if gui.returntocamp then
        -- Use camp location if returntocamp is enabled
        nav.campLocation = nav.campLocation or {x = 0, y = 0, z = 0}  -- Default camp location if not set
        referenceLocation = {x = nav.campLocation.x, y = nav.campLocation.y, z = nav.campLocation.z}
    elseif gui.chaseon then
        -- Use main assist's location if chaseon is enabled
        local mainAssistSpawn = mq.TLO.Spawn(gui.mainAssist)
        if mainAssistSpawn() then
            referenceLocation = {x = mainAssistSpawn.X(), y = mainAssistSpawn.Y(), z = mainAssistSpawn.Z()}
        else
            if not hasLoggedError then
                hasLoggedError = true
            end
            return false  -- No valid main assist, so not in camp
        end
    else
        if not hasLoggedError then
            hasLoggedError = true
        end
        return false  -- Neither camp nor chase is active, so not in camp
    end

    -- Reset error flag if a valid reference location is found
    hasLoggedError = false

    -- Get the player’s current location
    local playerX, playerY, playerZ = mq.TLO.Me.X(), mq.TLO.Me.Y(), mq.TLO.Me.Z()
    if not playerX or not playerY or not playerZ then
        return false  -- Exit if player coordinates are unavailable
    end

    -- Calculate distance from the player to the reference location
    local distanceToCamp = math.sqrt((referenceLocation.x - playerX)^2 +
                                     (referenceLocation.y - playerY)^2 +
                                     (referenceLocation.z - playerZ)^2)
    
    -- Check if the player is within the specified range of the camp location
    return distanceToCamp <= range
end

function utils.referenceLocation(range)
    range = range or 50  -- Set a default range if none is provided

    -- Determine reference location based on returntocamp or chaseon settings
    local referenceLocation
    if gui.returntocamp then
        nav.campLocation = nav.campLocation or {x = 0, y = 0, z = 0}  -- Initialize campLocation with a default if needed
        referenceLocation = {x = nav.campLocation.x, y = nav.campLocation.y, z = nav.campLocation.z}
    elseif gui.chaseon then
        local mainAssistSpawn = mq.TLO.Spawn(gui.mainAssist)
        if mainAssistSpawn() then
            referenceLocation = {x = mainAssistSpawn.X(), y = mainAssistSpawn.Y(), z = mainAssistSpawn.Z()}
        else
            if not hasLoggedError then
                hasLoggedError = true
            end
            return {}  -- Return an empty table if no valid main assist found
        end
    else
        if not hasLoggedError then
            hasLoggedError = true
        end
        return {}  -- Return an empty table if neither returntocamp nor chaseon is enabled
    end

    -- Reset error flag if a valid location is found
    hasLoggedError = false

    local mobsInRange = mq.getFilteredSpawns(function(spawn)
        local mobX, mobY, mobZ = spawn.X(), spawn.Y(), spawn.Z()
        if not mobX or not mobY or not mobZ then
            return false  -- Skip this spawn if any coordinate is nil
        end

        local mobID = spawn.ID()
        local mobName = mq.TLO.Spawn(mobID).CleanName()
        local currentZone = mq.TLO.Zone.ShortName()

        -- Check if the mob is in the globalIgnoreList or zone-specific ignore list
        if utils.pullConfig.globalIgnoreList[mobName] or 
           (utils.pullConfig[currentZone] and utils.pullConfig[currentZone][mobName]) then
            debugPrint("Skipping spawn due to pullConfig exclusion:", mobName)
            return false
        end

        local distanceToReference = math.sqrt((referenceLocation.x - mobX)^2 +
                                              (referenceLocation.y - mobY)^2 +
                                              (referenceLocation.z - mobZ)^2)
        -- Add Line of Sight (LOS) check
        return spawn.Type() == 'NPC' and distanceToReference <= range and spawn.LineOfSight()
    end)

    return mobsInRange  -- Return the list of mobs in range
end

function utils.twistSongMonitor()
    local twist = mq.TLO.Twist()
    if not gui.singSongs then
        if twist and tostring(twist):lower() == "true" then
            mq.cmd("/twist stop")
            return
        else
            return
        end
    end

    -- Initialize the twist list
    local twistList = {}

    utils.useSeloWithPercussion()

    -- Spellgem 2
    if gui.meleeGroup and charLevel >= 10 then
        local bestSpell = spells.findBestSpell("Haste", charLevel)
        if mq.TLO.Me.Gem(2).Name() ~= bestSpell then
            mq.cmd("/twist stop")
            mq.delay(100)
            spells.loadAndMemorizeSpell("Haste", charLevel, 2)
        end
        table.insert(twistList, 2)

    -- Spellgem 8
    elseif gui.casterGroup and charLevel >= 44 then
        local bestSpell = spells.findBestSpell("IntWisBuff", charLevel)
        if mq.TLO.Me.Gem(8).Name() ~= bestSpell then
            mq.cmd("/twist stop")
            mq.delay(100)
            spells.loadAndMemorizeSpell("IntWisBuff", charLevel, 8)
        end
        table.insert(twistList, 8)
    end

    -- Spellgem 3
    if charLevel >= 6 then
        table.insert(twistList, 3)
    end

    -- Spellgem 4
    if charLevel >= 17 then
        table.insert(twistList, 4)
    end

    -- Spellgem 5
    if gui.singFireColdResist and charLevel >= 9 then
        local bestSpell = spells.findBestSpell("ResistanceFireCold", charLevel)
        if mq.TLO.Me.Gem(5).Name() ~= bestSpell then
            mq.cmd("/twist stop")
            mq.delay(100)
            spells.loadAndMemorizeSpell("ResistanceFireCold", charLevel, 5)
        end
        table.insert(twistList, 5)
    end
    
    if gui.singDiseasePoisonResist and charLevel >= 13 then
        local bestSpell = spells.findBestSpell("ResistancePoisonDisease", charLevel)
        if mq.TLO.Me.Gem(5).Name() ~= bestSpell then
            mq.cmd("/twist stop")
            mq.delay(100)
            spells.loadAndMemorizeSpell("ResistancePoisonDisease", charLevel, 5)
        end
        table.insert(twistList, 5)
    end

    -- Spellgem 6

    if gui.singMagicResist and charLevel >= 41 then
        local bestSpell = spells.findBestSpell("Absorb", charLevel)
        if mq.TLO.Me.Gem(6).Name() ~= bestSpell then
            mq.cmd("/twist stop")
            mq.delay(100)
            spells.loadAndMemorizeSpell("Absorb", charLevel, 6)
        end
        table.insert(twistList, 6)
    end

    -- Spellgem 7
    if gui.singSlow and charLevel >= 20 then
        local bestSpell = spells.findBestSpell("Slow", charLevel)
        if mq.TLO.Me.Gem(7).Name() ~= bestSpell then
            mq.cmd("/twist stop")
            mq.delay(100)
            spells.loadAndMemorizeSpell("Slow", charLevel, 7)
        end
        table.insert(twistList, 7)

    end

    -- Check if the character is currently twisting and if the twist list matches
    local isTwisting = tostring(mq.TLO.Twist()):lower() == "true"
    local currentTwistList = mq.TLO.Twist.List()

    -- Convert currentTwistList to a table of numbers
    local currentList = {}
    for num in string.gmatch(currentTwistList, "%d+") do
        table.insert(currentList, tonumber(num))
    end

    -- Function to compare two lists for equality
    local function listsEqual(list1, list2)
        if #list1 ~= #list2 then return false end
        for i = 1, #list1 do
            if list1[i] ~= list2[i] then return false end
        end
        return true
    end

    -- Only update twist if twisting is inactive ("false") or the twist list needs adjustment
    if not isTwisting or not listsEqual(twistList, currentList) then
        local twistCommand = "/twist " .. table.concat(twistList, " ")
        mq.cmd(twistCommand)
    end
end

-- Load the pull ignore list from the config file
function utils.loadPullConfig()
    local configData, err = loadfile(pullConfigPath)
    if configData then
        local config = configData() or {}
        
        -- Load each zone-specific list
        for zone, mobs in pairs(config) do
            utils.pullConfig[zone] = mobs
        end
        
        -- Ensure the global ignore list is always loaded and initialized
        utils.pullConfig.globalIgnoreList = utils.pullConfig.globalIgnoreList or {}
        
        print("Pull ignore list loaded from " .. pullConfigPath)
    else
        print("No pull ignore list found. Starting with an empty list.")
        utils.pullConfig = {globalIgnoreList = {}}  -- Initialize with an empty global list
    end
end

-- Function to add a mob to the pull ignore list using its clean name
function utils.addMobToPullIgnoreList(targetName, isGlobal)
    local zoneName = isGlobal and "globalIgnoreList" or mq.TLO.Zone.ShortName() or "UnknownZone"
    
    if targetName then
        -- Ensure the zone or global list has an entry in the table
        utils.pullConfig[zoneName] = utils.pullConfig[zoneName] or {}
        
        -- Add the mob's clean name to the appropriate ignore list if not already present
        if not utils.pullConfig[zoneName][targetName] then
            utils.pullConfig[zoneName][targetName] = true
            print(string.format("Added '%s' to the pull ignore list for '%s'.", targetName, zoneName))
            utils.savePullConfig() -- Save the configuration after adding
        else
            print(string.format("'%s' is already in the pull ignore list for '%s'.", targetName, zoneName))
        end
    else
        print("Error: No target selected. Please target a mob to add it to the pull ignore list.")
    end
end

-- Function to remove a mob from the pull ignore list using its clean name
function utils.removeMobFromPullIgnoreList(targetName, isGlobal)
    local zoneName = isGlobal and "globalIgnoreList" or mq.TLO.Zone.ShortName() or "UnknownZone"
    
    if targetName then
        -- Check if the zone or global entry exists in the ignore list
        if utils.pullConfig[zoneName] and utils.pullConfig[zoneName][targetName] then
            utils.pullConfig[zoneName][targetName] = nil  -- Remove the mob entry
            print(string.format("Removed '%s' from the pull ignore list for '%s'.", targetName, zoneName))
            utils.savePullConfig()  -- Save the updated ignore list
        else
            print(string.format("'%s' is not in the pull ignore list for '%s'.", targetName, zoneName))
        end
    else
        print("Error: No target selected. Please target a mob to remove it from the pull ignore list.")
    end
end

-- Save the pull ignore list to the config file
function utils.savePullConfig()
    local config = {}
    for zone, mobs in pairs(utils.pullConfig) do
        config[zone] = mobs
    end
    mq.pickle(pullConfigPath, config)
    print("Pull ignore list saved to " .. pullConfigPath)
end

-- Load the mez ignore list from the config file
function utils.loadMezConfig()
    local configData, err = loadfile(mezConfigPath)
    if configData then
        local config = configData() or {}
        
        -- Load each zone-specific list
        for zone, mobs in pairs(config) do
            utils.mezConfig[zone] = mobs
        end
        
        -- Ensure the global ignore list is always loaded and initialized
        utils.mezConfig.globalIgnoreList = utils.mezConfig.globalIgnoreList or {}
        
        print("Mez ignore list loaded from " .. mezConfigPath)
    else
        print("No mez ignore list found. Starting with an empty list.")
        utils.mezConfig = {globalIgnoreList = {}}  -- Initialize with an empty global list
    end
end

-- Function to add a mob to the ignore list using its clean name
function utils.addMobToMezIgnoreList(targetName, isGlobal)
    local zoneName = isGlobal and "globalIgnoreList" or mq.TLO.Zone.ShortName() or "UnknownZone"
    
    if targetName then
        -- Ensure the zone or global list has an entry in the table
        utils.mezConfig[zoneName] = utils.mezConfig[zoneName] or {}
        
        -- Add the mob's clean name to the appropriate ignore list if not already present
        if not utils.mezConfig[zoneName][targetName] then
            utils.mezConfig[zoneName][targetName] = true
            print(string.format("Added '%s' to the ignore list for '%s'.", targetName, zoneName))
            utils.saveMezConfig() -- Save the configuration after adding
        else
            print(string.format("'%s' is already in the ignore list for '%s'.", targetName, zoneName))
        end
    else
        print("Error: No target selected. Please target a mob to add it to the ignore list.")
    end
end

-- Function to remove a mob from the ignore list using its clean name
function utils.removeMobFromMezIgnoreList(targetName, isGlobal)
    local zoneName = isGlobal and "globalIgnoreList" or mq.TLO.Zone.ShortName() or "UnknownZone"
    
    if targetName then
        -- Check if the zone or global entry exists in the ignore list
        if utils.mezConfig[zoneName] and utils.mezConfig[zoneName][targetName] then
            utils.mezConfig[zoneName][targetName] = nil  -- Remove the mob entry
            print(string.format("Removed '%s' from the ignore list for '%s'.", targetName, zoneName))
            utils.saveMezConfig()  -- Save the updated ignore list
        else
            print(string.format("'%s' is not in the ignore list for '%s'.", targetName, zoneName))
        end
    else
        print("Error: No target selected. Please target a mob to remove it from the ignore list.")
    end
end

-- Save the mez ignore list to the config file
function utils.saveMezConfig()
    local config = {}
    for zone, mobs in pairs(utils.mezConfig) do
        config[zone] = mobs
    end
    mq.pickle(mezConfigPath, config)
    print("Mez ignore list saved to " .. mezConfigPath)
end

return utils