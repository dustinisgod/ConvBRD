local mq = require('mq')
local utils = require('utils')
local commands = require('commands')
local gui = require('gui')
local nav = require('nav')
local spells = require('spells')
local pull = require('pull')
local mez = require('mez')

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

local toggleboton = gui.botOn or false

local function returnChaseToggle()
    if gui.botOn and gui.returnToCamp and not toggleboton then
        if nav.campLocation == nil then
            nav.setCamp()
            toggleboton = true
        end
    elseif not gui.botOn and toggleboton then
        nav.clearCamp()
        toggleboton = false
    end
end

utils.loadPullConfig()
utils.loadMezConfig()

while gui.controlGUI do

    returnChaseToggle()

    if gui.botOn then

        utils.twistSongMonitor()

        utils.monitorNav()

        pull.pullRoutine()

        mez.mezRoutine()

        utils.assistMonitor()

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