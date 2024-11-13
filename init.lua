local mq = require('mq')
local utils = require('utils')
local commands = require('commands')
local gui = require('gui')
local nav = require('nav')
local spells = require('spells')
local pull = require('pull')
local mez = require('mez')

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

spells.startup(currentLevel)

local startupRun = false

local function checkBotOn(currentLevel)
    if gui.botOn and not startupRun then
        spells.startup(currentLevel)
        startupRun = true
    elseif not gui.botOn and startupRun then
        startupRun = false
    end
end

local toggleboton = false
local lastPullOnState = false

local function returnChaseToggle()
    -- Check if bot is on and return-to-camp is enabled, and only set camp if toggleboton is false
    if gui.botOn and gui.returnToCamp and not toggleboton then
        nav.setCamp()
        toggleboton = true
    elseif not gui.botOn and toggleboton then
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

        utils.monitorNav()

        if gui.singSongs then
            utils.twistSongMonitor()
        end

        if gui.pullOn then
            pull.pullRoutine()
        end

        if gui.singSongs and gui.singMez then
            mez.mezRoutine()
        end

        if gui.assistMelee then
            utils.assistMonitor()
        end

        checkBotOn(currentLevel)

        local newLevel = mq.TLO.Me.Level()
        if newLevel ~= currentLevel then
            printf(string.format("Level has changed from %d to %d. Updating spells.", currentLevel, newLevel))
            spells.startup(newLevel)
            currentLevel = newLevel
        end
    end

    mq.doevents()
    mq.delay(100)
end