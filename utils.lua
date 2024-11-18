local mq = require('mq')
local gui = require('gui')
local nav = require('nav')
local spells = require('spells')

local utils = {}

utils.IsUsingDanNet = true
utils.IsUsingTwist = true
utils.IsUsingCast = true
utils.IsUsingMelee = false

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

local lastNavTime = 0

function utils.monitorNav()

    if gui.botOn and (gui.chaseOn or gui.returnToCamp) and not gui.pullOn then
        if not gui then
            printf("Error: gui is nil")
            return
        end

        local currentTime = os.time()

        if gui.returnToCamp and (currentTime - lastNavTime >= 5) then
            nav.checkCampDistance()
            lastNavTime = currentTime
        elseif gui.chaseOn and (currentTime - lastNavTime >= 2) then
            nav.chase()
            lastNavTime = currentTime
        end
    else
        return
    end
end

function utils.assistMonitor()
    local assist = require('assist')
    if gui.botOn then
        if not gui.pullOn then
            assist.assistRoutine()
            return
        end

        -- Check campQueue requirements if pulling is enabled
        local campQueueSize = #gui.campQueue

        -- If `gui.keepMobsInCamp` is checked, ensure campQueue has at least `keepMobsInCampAmount` mobs
        if gui.keepMobsInCamp then
            if campQueueSize >= gui.keepMobsInCampAmount then
                assist.assistRoutine()
            end
        else
            -- Otherwise, ensure campQueue has at least 1 mob if `gui.pullOn` is enabled
            if campQueueSize >= 1 then
                assist.assistRoutine()
            end
        end
    else
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
    if gui.returnToCamp then
        -- Use camp location if returnToCamp is enabled
        nav.campLocation = nav.campLocation or {x = 0, y = 0, z = 0}  -- Default camp location if not set
        referenceLocation = {x = nav.campLocation.x, y = nav.campLocation.y, z = nav.campLocation.z}
    elseif gui.chaseOn then
        -- Use main assist's location if chaseOn is enabled
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
    range = range or 100  -- Set a default range if none is provided

    -- Determine reference location based on returnToCamp or chaseOn settings
    local referenceLocation
    if gui.returnToCamp then
        nav.campLocation = nav.campLocation or {x = 0, y = 0, z = 0}  -- Initialize campLocation with a default if needed
        referenceLocation = {x = nav.campLocation.x, y = nav.campLocation.y, z = nav.campLocation.z}
    elseif gui.chaseOn then
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
        return {}  -- Return an empty table if neither returnToCamp nor chaseOn is enabled
    end

    -- Reset error flag if a valid location is found
    hasLoggedError = false

    local mobsInRange = mq.getFilteredSpawns(function(spawn)
        local mobX, mobY, mobZ = spawn.X(), spawn.Y(), spawn.Z()
        if not mobX or not mobY or not mobZ then
            return false  -- Skip this spawn if any coordinate is nil
        end

        local distanceToReference = math.sqrt((referenceLocation.x - mobX)^2 +
                                              (referenceLocation.y - mobY)^2 +
                                              (referenceLocation.z - mobZ)^2)
        return spawn.Type() == 'NPC' and distanceToReference <= range
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

    -- Build the twist list for slots 1-5 based on conditions
    -- Spellgem 1
    if gui.singRunSpeed and charLevel >= 5 then
        table.insert(twistList, 1)
    end

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