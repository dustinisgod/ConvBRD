local mq = require('mq')
local ImGui = require('ImGui')


local charName = mq.TLO.Me.Name()
local configPath = mq.configDir .. '/' .. 'ConvBRD_'.. charName .. '_config.lua'
local config = {}

local gui = {}
local previouscampSize = gui.campSize
local previouspullDistanceXY = gui.pullDistanceXY

gui.isOpen = true

local function setDefaultConfig()
    gui.botOn = false
    gui.mainAssist = ""
    gui.assistRange = 40
    gui.assistPercent = 95
    gui.assistMelee = true
    gui.stickFront = false
    gui.stickBehind = true
    gui.stickDistance = 15
    gui.switchWithMA = true
    gui.returnToCamp = false
    gui.campDistance = 10
    gui.chaseOn = false
    gui.chaseTarget = ""
    gui.chaseDistance = 20
    gui.singSongs = true
    gui.meleeGroup = true
    gui.casterGroup = false
    gui.singRunSpeed = true
    gui.singMagicResist = true
    gui.singFireColdResist = false
    gui.singDiseasePoisonResist = false
    gui.singMez = false
    gui.mezAmount = 3
    gui.mezRadius = 50
    gui.mezStopPercent = 95
    gui.singSlow = false
    gui.singAggroReduction = false
    gui.pullOn = false
    gui.campSize = 60
    gui.pullDistanceXY = 800
    gui.pullDistanceZ = 50
    gui.pullLevelMin = 1
    gui.pullLevelMax = 70
    gui.pullPause = true
    gui.pullPauseTimer = 30
    gui.pullPauseDuration = 4
    gui.keepMobsInCamp = false
    gui.keepMobsInCampAmount = 1
    gui.groupWatch = false
    gui.groupWatchCLR = false
    gui.groupWatchCLRMana = 10
    gui.groupWatchDRU = false
    gui.groupWatchDRUMana = 10
    gui.groupWatchSHM = false
    gui.groupWatchSHMMana = 10
    gui.groupWatchENC = false
    gui.groupWatchENCMana = 10
    gui.corpseDrag = false
end

function gui.getPullDistanceXY()
    return gui.pullDistanceXY
end

function gui.getPullDistanceZ()
    return gui.pullDistanceZ
end

function gui.saveConfig()
    for key, value in pairs(gui) do
        config[key] = value
    end
    mq.pickle(configPath, config)
    print("Configuration saved to " .. configPath)
end

local function loadConfig()
    local configData, err = loadfile(configPath)
    if configData then
        config = configData() or {}
        for key, value in pairs(config) do
            gui[key] = value
        end
    else
        print("Config file not found. Initializing with defaults.")
        setDefaultConfig()
        gui.saveConfig()
    end
end

loadConfig()

function ColoredText(text, color)
    ImGui.TextColored(color[1], color[2], color[3], color[4], text)
end

local previousPullOn = gui.pullOn
local function checkPullOnToggle()
    if gui.botOn and not previousPullOn and gui.pullOn then
        local nav = require('nav')
        gui.chaseOn = false
        gui.returnToCamp = true
        nav.setCamp()
    end

    previousPullOn = gui.pullOn
end

local previousbotOn = gui.botOn
local function checkBotOnToggle()
    if not gui.botOn and previousbotOn and gui.pullOn then
        gui.pullOn = false
    end

    previousbotOn = gui.botOn
end


local function controlGUI()
    gui.isOpen, _ = ImGui.Begin("Convergence Bard", gui.isOpen, 2)

    if not gui.isOpen then
        mq.exit()
    end

    ImGui.SetWindowSize(440, 600)

    -- Track the previous state of `gui.botOn` within the UI rendering function
    local previousBotOnState = gui.botOn or false

    -- Render the checkbox and detect if `gui.botOn` has changed
    gui.botOn = ImGui.Checkbox("Bot On", gui.botOn or false)

    -- Only call `checkBotOnToggle()` if `gui.botOn` has changed
    if gui.botOn ~= previousBotOnState then
        checkBotOnToggle()
    end


    ImGui.SameLine()

    if ImGui.Button("Save Config") then
        gui.saveConfig()
    end

    ImGui.Spacing()
    if ImGui.CollapsingHeader("Assist Settings") then
    ImGui.Spacing()
        ImGui.SetNextItemWidth(100)
        gui.mainAssist = ImGui.InputText("Assist", gui.mainAssist)


        if ImGui.IsItemDeactivatedAfterEdit() then

            if gui.mainAssist ~= "" then
                gui.mainAssist = gui.mainAssist:sub(1, 1):upper() .. gui.mainAssist:sub(2):lower()
            end
        end
        
        -- Validate the spawn if the input is non-empty
        if gui.mainAssist ~= "" then
            local spawn = mq.TLO.Spawn(gui.mainAssist)
            if not (spawn and spawn.Type() == "PC") or gui.mainAssist == charName then
                ImGui.TextColored(1, 0, 0, 1, "Invalid Target")
            end
        end
        
        ImGui.Spacing()
        if gui.mainAssist ~= "" then
            ImGui.Spacing()
            ImGui.SetNextItemWidth(100)
            gui.assistRange = ImGui.SliderInt("Assist Range", gui.assistRange, 5, 200)
            ImGui.Spacing()
            ImGui.SetNextItemWidth(100)
            gui.assistPercent= ImGui.SliderInt("Assist %", gui.assistPercent, 5, 100)

            ImGui.Spacing()
            ImGui.Separator()
            ImGui.Spacing()

            gui.assistMelee = ImGui.Checkbox("Melee", gui.assistMelee or false)
            if gui.assistMelee then
                ImGui.Spacing()
                gui.stickFront = ImGui.Checkbox("Front", gui.stickFront or false)
                if gui.stickFront then
                    gui.stickBehind = false
                end

                gui.stickBehind = ImGui.Checkbox("Behind", gui.stickBehind or false)
                if gui.stickBehind then
                    gui.stickFront = false
                end

                ImGui.Spacing()
                ImGui.Separator()
                ImGui.Spacing()

                ImGui.SetNextItemWidth(100)
                gui.stickDistance = ImGui.SliderInt("Stick Distance", gui.stickDistance, 5, 50)
                ImGui.Spacing()
                gui.switchWithMA = ImGui.Checkbox("Switch with MA", gui.switchWithMA or false)
            end
        end
    end

    ImGui.Spacing()
    if ImGui.CollapsingHeader("Nav Settings") then
    ImGui.Spacing()
    
        local previousReturnToCamp = gui.returnToCamp or false
        local previousChaseOn = gui.chaseOn or false

        local currentReturnToCamp = ImGui.Checkbox("Return To Camp", gui.returnToCamp or false)
        if currentReturnToCamp ~= previousReturnToCamp then
            gui.returnToCamp = currentReturnToCamp
                if gui.returnToCamp then
                    gui.chaseOn = false
                else
                    local nav = require('nav')
                    nav.campLocation = nil
                end
            previousReturnToCamp = currentReturnToCamp
        end

        if gui.returnToCamp then
            ImGui.SameLine()
            ImGui.SetNextItemWidth(100)
            gui.campDistance = ImGui.SliderInt("Camp Distance", gui.campDistance, 5, 200)
            ImGui.SameLine()
            ImGui.SetNextItemWidth(100)
            if ImGui.Button("Camp Here") then
                local nav = require('nav')
                nav.setCamp()
            end
        end

        local currentChaseOn = ImGui.Checkbox("Chase", gui.chaseOn or false)
        if currentChaseOn ~= previousChaseOn then
            gui.chaseOn = currentChaseOn
                if gui.chaseOn then
                    local nav = require('nav')
                    gui.returnToCamp = false
                    nav.campLocation = nil
                    gui.pullOn = false
                end
            previousChaseOn = currentChaseOn
        end

        if gui.chaseOn then
            ImGui.SameLine()
            ImGui.SetNextItemWidth(100)
            gui.chaseTarget = ImGui.InputText("Name", gui.chaseTarget)
            ImGui.SameLine()
            ImGui.SetNextItemWidth(100)
            gui.chaseDistance = ImGui.SliderInt("Chase Distance", gui.chaseDistance, 5, 200)
        end
    end

    ImGui.Spacing()
    if ImGui.CollapsingHeader("Song Settings:") then
    ImGui.Spacing()

    gui.singSongs = ImGui.Checkbox("Sing Songs", gui.singSongs or false)

        ImGui.Spacing()
        ImGui.Separator()
        ImGui.Spacing()

        if gui.singSongs then

            gui.singRunSpeed = ImGui.Checkbox("Run Speed", gui.singRunSpeed or false)

            ImGui.Spacing()
            ImGui.Separator()
            ImGui.Spacing()

            gui.meleeGroup = ImGui.Checkbox("Melee Group", gui.meleeGroup or false)
            if gui.meleeGroup then
                gui.casterGroup = false
            end

            gui.casterGroup = ImGui.Checkbox("Caster Group", gui.casterGroup or false)
            if gui.casterGroup then
                gui.meleeGroup = false
            end

            ImGui.Spacing()
            ImGui.Separator()
            ImGui.Spacing()

            gui.singMagicResist = ImGui.Checkbox("MR/AC/Absorb", gui.singMagicResist or false)
            if gui.singMagicResist then
                gui.singFireColdResist = false
                gui.singDiseasePoisonResist = false
            end

            gui.singFireColdResist = ImGui.Checkbox("Fire/Cold Resist", gui.singFireColdResist or false)
            if gui.singFireColdResist then
                gui.singMagicResist = false
                gui.singDiseasePoisonResist = false
            end

            gui.singDiseasePoisonResist = ImGui.Checkbox("Disease/Poison Resist", gui.singDiseasePoisonResist or false)
            if gui.singDiseasePoisonResist then
                gui.singMagicResist = false
                gui.singFireColdResist = false
            end

            ImGui.Spacing()
            ImGui.Separator()


            ImGui.Spacing()
            if ImGui.CollapsingHeader("Mez Settings:") then
            ImGui.Spacing()

                gui.singMez = ImGui.Checkbox("Mez", gui.singMez or false)
                if gui.singMez then

                -- Add Mob to Zone Ignore List Button
                if ImGui.Button("+ Mez Zone Ignore") then
                    local utils = require("utils")
                    local targetName = mq.TLO.Target.CleanName()
                    if targetName then
                        utils.addMobToMezIgnoreList(targetName)  -- Add to the zone-specific ignore list
                        print(string.format("'%s' has been added to the mez ignore list for the current zone.", targetName))
                    else
                        print("Error: No target selected. Please target a mob to add it to the mez ignore list.")
                    end
                end

                -- Remove Mob from Zone Ignore List Button
                if ImGui.Button("- Mez Zone Ignore") then
                    local utils = require("utils")
                    local targetName = mq.TLO.Target.CleanName()
                    if targetName then
                        utils.removeMobFromMezIgnoreList(targetName)  -- Remove from the zone-specific ignore list
                        print(string.format("'%s' has been removed from the mez ignore list for the current zone.", targetName))
                    else
                        print("Error: No target selected. Please target a mob to remove it from the mez ignore list.")
                    end
                end

                -- Add Mob to Global QuestNPC Ignore List Button
                if ImGui.Button("+ Mez Global Ignore") then
                    local utils = require("utils")
                    local targetName = mq.TLO.Target.CleanName()
                    if targetName then
                        utils.addMobToMezIgnoreList(targetName, true)  -- Add to the global ignore list
                        print(string.format("'%s' has been added to the global quest NPC ignore list.", targetName))
                    else
                        print("Error: No target selected. Please target a mob to add it to the global quest NPC ignore list.")
                    end
                end

                -- Remove Mob from Global QuestNPC Ignore List Button
                if ImGui.Button("- Mez Global Ignore") then
                    local utils = require("utils")
                    local targetName = mq.TLO.Target.CleanName()
                    if targetName then
                        utils.removeMobFromMezIgnoreList(targetName, true)  -- Remove from the global ignore list
                        print(string.format("'%s' has been removed from the global quest NPC ignore list.", targetName))
                    else
                        print("Error: No target selected. Please target a mob to remove it from the global quest NPC ignore list.")
                    end
                end

                    ImGui.SetNextItemWidth(100)
                    gui.mezAmount = ImGui.SliderInt("Amount In Camp", gui.mezAmount, 1, 20)
                    ImGui.SetNextItemWidth(100)
                    gui.mezRadius = ImGui.SliderInt("Radius", gui.mezRadius, 5, 100)
                    ImGui.SetNextItemWidth(100)
                    gui.mezStopPercent = ImGui.SliderInt("Stop %", gui.mezStopPercent, 1, 100)
                end
            end
            ImGui.Spacing()
            ImGui.Separator()
            ImGui.Spacing()

            gui.singSlow = ImGui.Checkbox("Slow", gui.singSlow or false)

            ImGui.Spacing()
            ImGui.Separator()
            ImGui.Spacing()

            gui.singAggroReduction = ImGui.Checkbox("Aggro Reduction", gui.singAggroReduction or false)

        end
    end

    ImGui.Spacing()
    if ImGui.CollapsingHeader("Pull Settings") then
        ImGui.Spacing()
    
        -- Track the previous state of `gui.pullOn` within the UI rendering function
        local previousPullOnState = gui.pullOn or false

        -- Render the checkbox and detect if `gui.pullOn` has changed
        gui.pullOn = ImGui.Checkbox("Pull", gui.pullOn or false)

        -- Only call `checkPullOnToggle()` if `gui.pullOn` has changed
        if gui.pullOn ~= previousPullOnState then
            checkPullOnToggle()
        end

        ImGui.Spacing()

        if gui.pullOn then
            gui.chase = false
            gui.returnToCamp = true

            ImGui.Spacing()

            -- Add Mob to Zone Pull Ignore List Button
            if ImGui.Button("+ Pull Zone Ignore") then
                local utils = require("utils")
                local targetName = mq.TLO.Target.CleanName()
                if targetName then
                    utils.addMobToPullIgnoreList(targetName)  -- Add to the zone-specific pull ignore list
                    print(string.format("'%s' has been added to the pull ignore list for the current zone.", targetName))
                else
                    print("Error: No target selected. Please target a mob to add it to the pull ignore list.")
                end
            end

            -- Remove Mob from Zone Pull Ignore List Button
            if ImGui.Button("- Pull Zone Ignore") then
                local utils = require("utils")
                local targetName = mq.TLO.Target.CleanName()
                if targetName then
                    utils.removeMobFromPullIgnoreList(targetName)  -- Remove from the zone-specific pull ignore list
                    print(string.format("'%s' has been removed from the pull ignore list for the current zone.", targetName))
                else
                    print("Error: No target selected. Please target a mob to remove it from the pull ignore list.")
                end
            end

            -- Add Mob to Global Pull Ignore List Button
            if ImGui.Button("+ Pull Global Ignore") then
                local utils = require("utils")
                local targetName = mq.TLO.Target.CleanName()
                if targetName then
                    utils.addMobToPullIgnoreList(targetName, true)  -- Add to the global pull ignore list
                    print(string.format("'%s' has been added to the global pull ignore list.", targetName))
                else
                    print("Error: No target selected. Please target a mob to add it to the global pull ignore list.")
                end
            end

            -- Remove Mob from Global Pull Ignore List Button
            if ImGui.Button("- Pull Global Ignore") then
                local utils = require("utils")
                local targetName = mq.TLO.Target.CleanName()
                if targetName then
                    utils.removeMobFromPullIgnoreList(targetName, true)  -- Remove from the global pull ignore list
                    print(string.format("'%s' has been removed from the global pull ignore list.", targetName))
                else
                    print("Error: No target selected. Please target a mob to remove it from the global pull ignore list.")
                end
            end

            ImGui.Spacing()
            ImGui.SetNextItemWidth(100)
            gui.campSize = ImGui.SliderInt("Camp Size", gui.campSize, 20, 100)
        -- Check if the tank range has changed
        if gui.campSize ~= previouscampSize then
            mq.cmdf('/squelch /mapfilter spellradius %s', gui.campSize)
            previouscampSize = gui.campSize
        end
            ImGui.Spacing()
            ImGui.SetNextItemWidth(100)
            gui.pullDistanceXY = ImGui.SliderInt("Pull Distance", gui.pullDistanceXY, 5, 4000)
        -- Check if the tank range has changed
        if gui.pullDistanceXY ~= previouspullDistanceXY then
            mq.cmdf('/squelch /mapfilter castradius %s', gui.pullDistanceXY)
            previouspullDistanceXY = gui.pullDistanceXY
        end
            ImGui.Spacing()
            ImGui.SetNextItemWidth(100)
            gui.pullDistanceZ = ImGui.SliderInt("Max Z", gui.pullDistanceZ, 5, 1000)

            ImGui.Spacing()
            ImGui.Separator()
            ImGui.Spacing()

            ImGui.SetNextItemWidth(100)
            gui.pullLevelMin = ImGui.SliderInt("Min Level", gui.pullLevelMin, 1, 70)
            ImGui.SetNextItemWidth(100)
            gui.pullLevelMax = ImGui.SliderInt("Max Level", gui.pullLevelMax, 1, 70)
            if gui.pullLevelMax < gui.pullLevelMin then
                gui.pullLevelMax = gui.pullLevelMin
            end

            ImGui.Spacing()
            ImGui.Separator()
            ImGui.Spacing()

            gui.keepMobsInCamp = ImGui.Checkbox("Keep Mobs In Camp", gui.keepMobsInCamp or false)
                if gui.keepMobsInCamp then
                    ImGui.SetNextItemWidth(100)
                    gui.keepMobsInCampAmount = ImGui.SliderInt("Camp Mobs", gui.keepMobsInCampAmount, 1, 40)
                end

            ImGui.Spacing()
            ImGui.Separator()
            ImGui.Spacing()

            gui.pullPause = ImGui.Checkbox("Pull Pause", gui.pullPause or false)
            if gui.pullPause then
                ImGui.SetNextItemWidth(100)
                gui.pullPauseTimer = ImGui.SliderInt("Pause Timer", gui.pullPauseTimer, 1, 120)
                ImGui.SetNextItemWidth(100)
                gui.pullPauseDuration = ImGui.SliderInt("Pause Length", gui.pullPauseDuration, 1, 15)
            end

            ImGui.Spacing()
            ImGui.Separator()
            ImGui.Spacing()
            if ImGui.CollapsingHeader("Group Watch Settings") then
            ImGui.SetNextItemWidth(100)
            gui.groupWatch = ImGui.Checkbox("Watch Group", gui.groupWatch or false)
                if gui.groupWatch then
                    gui.groupWatchCLR = ImGui.Checkbox("Clerics", gui.groupWatchCLR or false)
                    if gui.groupWatchCLR then
                        ImGui.SetNextItemWidth(100)
                        gui.groupWatchCLRMana = ImGui.SliderInt("Cleric Mana", gui.groupWatchCLRMana, 1, 100)
                    end
                    gui.groupWatchDRU = ImGui.Checkbox("Druid", gui.groupWatchDRU or false)
                    if gui.groupWatchDRU then
                        ImGui.SetNextItemWidth(100)
                        gui.groupWatchDRUMana = ImGui.SliderInt("Druid Mana", gui.groupWatchDRUMana, 1, 100)
                    end
                    gui.groupWatchSHM = ImGui.Checkbox("Shaman", gui.groupWatchSHM or false)
                    if gui.groupWatchSHM then
                        ImGui.SetNextItemWidth(100)
                        gui.groupWatchSHMMana = ImGui.SliderInt("Shaman Mana", gui.groupWatchSHMMana, 1, 100)
                    end
                    gui.groupWatchENC = ImGui.Checkbox("Enchanter", gui.groupWatchENC or false)
                    if gui.groupWatchENC then
                        ImGui.SetNextItemWidth(100)
                        gui.groupWatchENCMana = ImGui.SliderInt("Enchanter Mana", gui.groupWatchENCMana, 1, 100)
                    end
                end
            end
        end
    end

    ImGui.Spacing()
        if ImGui.CollapsingHeader("Misc Settings") then

            ImGui.Spacing()
        
            gui.corpseDrag = ImGui.Checkbox("Corpse Drag", gui.corpseDrag or false)

            ImGui.Spacing()
    end

    ImGui.End()
end

gui.controlGUI = controlGUI

return gui