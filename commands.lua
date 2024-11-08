local mq = require 'mq'
local gui = require 'gui'
local nav = require 'nav'
local utils = require 'utils'

local commands = {}

-- Existing functions

local function setExit()
    print("Closing..")
    gui.isOpen = false
end

local function setBotOnOff(value)
    if value == "" then
        print("Usage: /convbard Bot on/off")
    elseif value == 'on' then
        gui.botOn = true
        print("Bot is now enabled")
    elseif value == 'off' then
        gui.botOn = false
        print("Bot is now disabled")
    end
end

local function setSave()
    gui.saveConfig()
end

-- Combined function for setting main assist, range, and percent
local function setAssist(name, range, percent)
    if name then
        utils.setMainAssist(name)
        print("Main Assist set to", name)
    else
        print("Error: Main Assist name is required.")
        return
    end

    -- Set the assist range if provided
    if range and string.match(range, "^%d+$") then
        gui.assistRange = tonumber(range)
        print("Assist Range set to", gui.assistRange)
    else
        print("Assist Range not provided or invalid. Current range:", gui.assistRange)
    end

    -- Set the assist percent if provided
    if percent and string.match(percent, "^%d+$") then
        gui.assistPercent = tonumber(percent)
        print("Assist Percent set to", gui.assistPercent)
    else
        print("Assist Percent not provided or invalid. Current percent:", gui.assistPercent)
    end
end

local function toggleGroupType()
    if gui.meleeGroup then
        gui.meleeGroup = true
        gui.casterGroup = false
        print("Melee Group is now enabled.")
    elseif gui.casterGroup then
        gui.casterGroup = true
        gui.meleeGroup = false
        print("Caster Group is now enabled.")
    end
end

local function setChaseOnOff(value)
    if value == "" then
        print("Usage: /convbard Chase <targetName> <distance> or /convbard Chase off/on")
    elseif value == 'on' then
        gui.chaseOn = true
        gui.returnToCamp = false
        gui.pullOn = false
        print("Chase enabled.")
    elseif value == 'off' then
        gui.chaseOn = false
        print("Chase disabled.")
    else
        -- Split value into targetName and distance
        local targetName, distanceStr = value:match("^(%S+)%s*(%S*)$")
        
        if not targetName then
            print("Invalid input. Usage: /convbard Chase <targetName> <distance>")
            return
        end
        
        -- Convert distance to a number, if it's provided
        local distance = tonumber(distanceStr)
        
        -- Check if distance is valid
        if not distance then
            print("Invalid distance provided. Usage: /ConvBard Chase <targetName> <distance> or /ConvBard Chase off")
            return
        end
        
        -- Pass targetName and valid distance to setChaseTargetAndDistance
        nav.setChaseTargetAndDistance(targetName, distance)
    end
end

-- Combined function for setting camp, return to camp, and chase
local function setCampHere(value1)
    if value1 == "on" then
        gui.chaseOn = false
        gui.campLocation = nav.setCamp()
        gui.returnToCamp = true
        gui.campDistance = gui.campDistance or 10
        print("Camp location set to current spot. Return to Camp enabled with default distance:", gui.campDistance)
    elseif value1 == "off" then
        -- Disable return to camp
        gui.returnToCamp = false
        print("Return To Camp disabled.")
    elseif tonumber(value1) then
        gui.chaseOn = false
        gui.campLocation = nav.setCamp()
        gui.returnToCamp = true
        gui.campDistance = tonumber(value1)
        print("Camp location set with distance:", gui.campDistance)
    else
        print("Error: Invalid command. Usage: /convbard camphere <distance>, /convbard camphere on, /convbard camphere off")
    end
end

local function setMezRadius(value)
    if value == "" then
        print("Usage: /convbard MezRadius <Radius>")
        return
    end
    if not string.match(value, "^%d+$") then
        print("Error: Mesmerize Radius must be a number with no letters or symbols.")
        return
    end
    gui.mezRadius = tonumber(value) or gui.mezRadius
    print("Mesmerize Radius set to ", gui.mezRadius)
end

local function setMezStopPercent(value)
    if value == "" then
        print("Usage: /convbard MezStopPct <Percent>")
        return
    end
    if not string.match(value, "^%d+$") then
        print("Error: Mesmerize Stop Percent must be a number with no letters or symbols.")
        return
    end
    gui.mezStopPercent = tonumber(value) or gui.mezStopPercent
    print("Mesmerize Stop Percent set to", gui.mezStopPercent)
end

local function setMezAmount(value)
    if value == "" then
        print("Usage: /convbard mezAmount <amount>")
        return
    end
    if not string.match(value, "^%d+$") then
        print("Error: Mez amount must be a number with no letters or symbols.")
        return
    end
    gui.mezAmount = tonumber(value) or gui.mezAmount
    print("Mez Amount set to", gui.mezAmount)
end

local function setPullAmount(value)
    if value == "" then
        print("Usage: /convbard pullamount <amount>")
        return
    end
    if not string.match(value, "^%d+$") then
        print("Error: Pull amount must be a number with no letters or symbols.")
        return
    end
    gui.pullAmount = tonumber(value) or gui.pullAmount
        print("Pull Amount set to", gui.pullAmount)
end

local function setPullDistance(value)
    if value == "" then
        print("Usage: /convbard PullDistance <distance>")
        return
    end
    if not string.match(value, "^%d+$") then
        print("Error: Camp distance must be a number with no letters or symbols.")
        return
    end
    gui.pullDistance = tonumber(value) or gui.pullDistance
    print("Pull Distance set to", gui.pullDistance)
end

local function setPullLevelMin(value)
    if value == "" then
        print("Usage: /convbard pullLevelMin <level>")
        return
    end
    if not string.match(value, "^%d+$") then
        print("Error: Pull level min must be a number with no letters or symbols.")
        return
    end
    gui.pullLevelMin = tonumber(value) or gui.pullLevelMin
    print("Pull Level Min set to", gui.pullLevelMin)
end

local function setPullLevelMax(value)
    if value == "" then
        print("Usage: /convbard pullLevelMax <level>")
        return
    end
    if not string.match(value, "^%d+$") then
        print("Error: Pull level max must be a number with no letters or symbols.")
        return
    end
    gui.pullLevelMax = tonumber(value) or gui.pullLevelMax
    print("Pull Level Max set to", gui.pullLevelMax)
end

local function setPullPauseTimer(value)
    if value == "" then
        print("Usage: /convbard pullPauseTimer <timer>")
        return
    end
    if not string.match(value, "^%d+$") then
        print("Error: Pull Pause Timer must be a number with no letters or symbols.")
        return
    end
    gui.pullPauseTimer = tonumber(value) or gui.pullPauseTimer
    print("Pull Pause Timer set to", gui.pullPauseTimer)
end

local function setPullPauseDuration(value)
    if value == "" then
        print("Usage: /convbard pullPauseDuration <duration>")
        return
    end
    if not string.match(value, "^%d+$") then
        print("Error: Pull Pause Duration must be a number with no letters or symbols.")
        return
    end
    gui.pullPauseDuration = tonumber(value) or gui.pullPauseDuration
    print("Pull Pause Duration set to", gui.pullPauseDuration)
end

local function setKeepMobsInCampAmount(value)
    if value == "" then
        print("Usage: /convbard KeepMobsInCampAmount <amount>")
        return
    end
    if not string.match(value, "^%d+$") then
        print("Error: Keep Mobs In Camp Amount must be a number with no letters or symbols.")
        return
    end
    gui.keepMobsInCampAmount = tonumber(value) or gui.keepMobsInCampAmount
    print("Keep Mobs In Camp Amount set to", gui.keepMobsInCampAmount)
end

local function setKeepMobsInCamp(value)
    if value == "" then
        print("Usage: /convbard KeepMobsInCamp on/off")
    elseif value == 'on' then
        gui.keepMobsInCamp = true
        print("Keep Mobs In Camp is now enabled")
    elseif value == 'off' then
        gui.keepMobsInCamp = false
        print("Keep Mobs In Camp is now disabled")
    end
end

local function setMeleeOptions(meleeOption, stickOption, stickDistance)
    -- Set Assist Melee on or off based on the first argument
    if meleeOption == "on" then
        gui.assistMelee = true
        print("Assist Melee is now enabled")
    elseif meleeOption == "off" then
        gui.assistMelee = false
        print("Assist Melee is now disabled")
    elseif meleeOption == "front" or meleeOption == "behind" then
        -- Set Stick position based on 'front' or 'behind' and optionally set distance
        gui.assistMelee = true
        if meleeOption == "front" then
            gui.stickFront = true
            gui.stickBehind = false
            print("Stick set to front")
        elseif meleeOption == "behind" then
            gui.stickBehind = true
            gui.stickFront = false
            print("Stick set to behind")
        end

        -- Check if stickDistance is provided and is a valid number
        if stickOption and tonumber(stickOption) then
            gui.stickDistance = tonumber(stickOption)
            print("Stick distance set to", gui.stickDistance)
        elseif stickOption then
            print("Invalid stick distance. Usage: /convbard melee front/behind <distance>")
        end
    else
        print("Error: Invalid command. Usage: /convbard melee on/off or /convbard melee front/behind <distance>")
    end
end

local function setSingOptions(option, value)
    local validSongs = {
        run = "singRunSpeed",
        magic = "singMagicResist",
        fire = "singFireColdResist",
        cold = "singFireColdResist",
        disease = "singDiseasePoisonResist",
        poison = "singDiseasePoisonResist",
        mez = "singMez",
        slow = "singSlow",
        aggro = "singAggroReduction",
        melee = "meleeGroup",
        caster = "casterGroup",
    }

    if option == "on" or option == "off" then
        -- Overall singSongs on/off
        gui.singSongs = (option == "on")
        print("Twist Songs is now " .. (gui.singSongs and "enabled" or "disabled"))

    elseif validSongs[option] then
        -- Control individual songs if option is a valid song name
        local songKey = validSongs[option]
        
        if value == "on" then
            -- Enable singSongs if it is currently off
            if not gui.singSongs then
                gui.singSongs = true
                print("Twist Songs was disabled and is now enabled to allow song playback.")
            end
            
            gui[songKey] = true
            print(option:gsub("^%l", string.upper) .. " is now enabled")

            -- Ensure only one resist type is active at a time
            if songKey == 'singMagicResist' then
                gui.singFireColdResist = false
                gui.singDiseasePoisonResist = false
            elseif songKey == 'singFireColdResist' then
                gui.singMagicResist = false
                gui.singDiseasePoisonResist = false
            elseif songKey == 'singDiseasePoisonResist' then
                gui.singMagicResist = false
                gui.singFireColdResist = false
            end

        elseif value == "off" then
            gui[songKey] = false
            print(option:gsub("^%l", string.upper) .. " is now disabled")
        else
            print("Error: Value must be 'on' or 'off'. Usage: /convbard singsong <songname> on/off")
        end
    else
        print("Error: Invalid song name or command. Usage: /convbard singsong on/off or /convbard singsong <songname> on/off")
    end
end


local function setSwitchWithMA(value)
    if value == "" then
        print("Usage: /convbard switchwithma on/off")
    elseif value == 'on' then
        gui.switchWithMA = true
        print("Switch with MA is now enabled")
    elseif value == 'off' then
        gui.switchWithMA = false
        print("Switch with MA is now disabled")
    end
end

local function setPullOnOff(value)
    if value == "" then
        print("Usage: /convbard Pull on/off")
    elseif value == 'on' then
        gui.pullOn = true
        gui.chase = false
        gui.returnToCamp = true
        print("Pulling is now enabled.")
    elseif value == 'off' then
        gui.pullOn = false
        print("Pulling is now disabled.")
    end
end

local function setPullPause(value)
    if value == "" then
        print("Usage: /convbard PullPause on/off")
    elseif value == 'on' then
        gui.pullPause = true
        print("Pull Pause is now enabled")
    elseif value == 'off' then
        gui.pullPause = false
        print("Pull Pause is now disabled")
    end
end

local function setMezIgnore(scope, action)
    -- Check for a valid target name
    local targetName = mq.TLO.Target.CleanName()
    if not targetName then
        print("Error: No target selected. Please target a mob to modify the mez ignore list.")
        return
    end

    -- Determine if the scope is global or zone-specific
    local isGlobal = (scope == "global")

    if action == "add" then
        utils.addMobToMezIgnoreList(targetName, isGlobal)
        local scopeText = isGlobal and "global quest NPC ignore list" or "mez ignore list for the current zone"
        print(string.format("'%s' has been added to the %s.", targetName, scopeText))

    elseif action == "remove" then
        utils.removeMobFromMezIgnoreList(targetName, isGlobal)
        local scopeText = isGlobal and "global quest NPC ignore list" or "mez ignore list for the current zone"
        print(string.format("'%s' has been removed from the %s.", targetName, scopeText))

    else
        print("Error: Invalid action. Usage: /convbard mezignore zone/global add/remove")
    end
end

local function setPullIgnore(scope, action)
    -- Check for a valid target name
    local targetName = mq.TLO.Target.CleanName()
    if not targetName then
        print("Error: No target selected. Please target a mob to modify the pull ignore list.")
        return
    end

    -- Determine if the scope is global or zone-specific
    local isGlobal = (scope == "global")

    if action == "add" then
        utils.addMobToPullIgnoreList(targetName, isGlobal)
        local scopeText = isGlobal and "global quest NPC ignore list" or "pull ignore list for the current zone"
        print(string.format("'%s' has been added to the %s.", targetName, scopeText))

    elseif action == "remove" then
        utils.removeMobFromPullIgnoreList(targetName, isGlobal)
        local scopeText = isGlobal and "global quest NPC ignore list" or "pull ignore list for the current zone"
        print(string.format("'%s' has been removed from the %s.", targetName, scopeText))

    else
        print("Error: Invalid action. Usage: /convbard pullignore zone/global add/remove")
    end
end

local function commandHandler(command, ...)
    -- Convert command and arguments to lowercase for case-insensitive matching
    command = string.lower(command)
    local args = {...}
    for i, arg in ipairs(args) do
        args[i] = string.lower(arg)
    end

    if command == "exit" then
        setExit()
    elseif command == "bot" then
        setBotOnOff(args[1])
    elseif command == "save" then
        setSave()
    elseif command == "assist" then
        setAssist(args[1], args[2], args[3])
    elseif command == "melee" then
        setMeleeOptions(args[1], args[2], args[3])
    elseif command == "switchwithma" then
        setSwitchWithMA(args[1])
    elseif command == "camphere" then
        setCampHere(args[1])
    elseif command == "chase" then
        local chaseValue = args[1]
        if args[2] then
            chaseValue = chaseValue .. " " .. args[2]
        end
        setChaseOnOff(chaseValue)
    elseif command == "grouptype" then
        toggleGroupType()
    elseif command == "singsong" then
        setSingOptions(args[1], args[2])
    elseif command == "mezradius" then
        setMezRadius(args[1])
    elseif command == "mezstoppercent" then
        setMezStopPercent(args[1])
    elseif command == "mezamount" then
        setMezAmount(args[1])
    elseif command == "pull" then
        setPullOnOff(args[1])
    elseif command == "pullamount" then
        setPullAmount(args[1])
    elseif command == "pulldistance" then
        setPullDistance(args[1])
    elseif command == "pulllevelmin" then
        setPullLevelMin(args[1])
    elseif command == "pulllevelmax" then
        setPullLevelMax(args[1])
    elseif command == "pullpause" then
        setPullPause(args[1])
    elseif command == "pullpausetimer" then
        setPullPauseTimer(args[1])
    elseif command == "pullpauseduration" then
        setPullPauseDuration(args[1])
    elseif command == "keepmobsincamp" then
        setKeepMobsInCamp(args[1])
    elseif command == "keepmobsincampamount" then
        setKeepMobsInCampAmount(args[1])
    elseif command == "mezignore" then
        setMezIgnore(args[1], args[2])
    elseif command == "pullignore" then
        setPullIgnore(args[1], args[2])
    end
end

function commands.init()
    -- Single binding for the /convbard command
    mq.bind('/convbard', function(command, ...)
        commandHandler(command, ...)
    end)
end

return commands