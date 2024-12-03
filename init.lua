local mq = require('mq')
local utils = require('utils')
local commands = require('commands')
local gui = require('gui')
local nav = require('nav')
local spells = require('spells')
local pull = require('pull')
local mez = require('mez')

local DEBUG_MODE = false
-- Debug print helper function
local function debugPrint(...)
    if DEBUG_MODE then
        print(...)
    end
end

local class = mq.TLO.Me.Class()
if class ~= "Bard" then
    print("This script is only for Bards.")
    mq.exit()
end

local currentLevel = mq.TLO.Me.Level()

utils.PluginCheck()

mq.cmd('/assist off')

mq.imgui.init('controlGUI', gui.controlGUI)

commands.init()
commands.initALL()

local startupRun = false

-- Function to check the botOn status and run startup once
local function checkBotOn(currentLevel)
    if gui.botOn and not startupRun then
        nav.setCamp()
        spells.startup(currentLevel)
        startupRun = true  -- Set flag to prevent re-running
        printf("Bot has been turned on. Running startup.")

    elseif not gui.botOn and startupRun then
        -- Optional: Reset the flag if bot is turned off
        startupRun = false
    end
end

local toggleboton = false
local function returnChaseToggle()
    -- Check if bot is on and return-to-camp is enabled, and only set camp if toggleboton is false
    if gui.botOn and gui.returntocamp and not toggleboton then
        debugPrint("Setting camp")
        nav.setCamp()
        toggleboton = true
    elseif not gui.botOn and toggleboton then
        debugPrint("Clearing camp")
        -- Clear camp if bot is turned off after being on
        nav.clearCamp()
        toggleboton = false
    end
end

utils.loadPullConfig()
utils.loadMezConfig()

while gui.controlGUI do

    returnChaseToggle()

    if gui.botOn then

        checkBotOn(currentLevel)

        debugPrint("Navigating")
        utils.monitorNav()

        if gui.singSongs then
            debugPrint("Singing songs")
            utils.twistSongMonitor()
        end

        if gui.corpsedrag then
            debugPrint("Dragging corpses")
            utils.monitorCorpseDrag()
        end

        if gui.pullOn then
            debugPrint("Pulling")
            pull.pullRoutine()
        end

        if gui.singSongs and gui.singMez then
            debugPrint("Mezzing")
            mez.mezRoutine()
        end

        if gui.assistMelee then
            debugPrint("Assisting melee")
            utils.assistMonitor()
        end

        local newLevel = mq.TLO.Me.Level()
        if newLevel ~= currentLevel then
            debugPrint("Level has changed from " .. currentLevel .. " to " .. newLevel .. ". Updating spells.")
            printf(string.format("Level has changed from %d to %d. Updating spells.", currentLevel, newLevel))
            spells.startup(newLevel)
            currentLevel = newLevel
        end
    end

    mq.doevents()
    mq.delay(100)
end