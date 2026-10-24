-- AssistenteNPC - menu radial de comandos (abre com a tecla configuravel, padrao G).

require "AssistenteNPC/Config"
require "AssistenteNPC/Util"
require "AssistenteNPC/TargetCursor"
require "AssistenteNPC/Brain"
require "AssistenteNPC/Recruit"

AssistenteNPC.RadialMenu = {}
local RadialMenu = AssistenteNPC.RadialMenu
local Util = AssistenteNPC.Util

local ICONS = {
    follow  = "media/ui/emotes/followme.png",
    stay    = "media/ui/emotes/stop.png",
    loot    = "media/ui/emotes/gears.png",
    wood    = "media/ui/emotes/moveout.png",
    guard   = "media/ui/emotes/salute.png",
    analyze = "media/ui/emotes/comehere.png",
    deliver = "media/ui/emotes/thumbsup.png",
    giveAxe = "media/ui/emotes/yes.png",
    recruit = "media/ui/Traits/trait_talkative.png",
}

local function icon(name)
    return getTexture(ICONS[name])
end

-- ---------------------------------------------------------------------------
-- Acoes das fatias. O primeiro argumento e sempre o jogador.
-- ---------------------------------------------------------------------------

local function onFollow(playerObj)
    AssistenteNPC.Brain.order("follow")
end

local function onStay(playerObj)
    AssistenteNPC.Brain.order("stay", { x = playerObj:getX(), y = playerObj:getY(), z = playerObj:getZ() })
end

local function onLoot(playerObj)
    AssistenteNPC.Brain.order("loot")
end

local function onWood(playerObj)
    AssistenteNPC.Brain.order("wood", { x = playerObj:getX(), y = playerObj:getY(), z = playerObj:getZ() })
end

local function onGuard(playerObj)
    AssistenteNPC.TargetCursor.start(playerObj, Util.text("IGUI_AssistenteNPC_PickGuard"), function(square)
        AssistenteNPC.Brain.order("guard", { x = square:getX(), y = square:getY(), z = square:getZ() })
    end)
end

local function onAnalyze(playerObj)
    AssistenteNPC.TargetCursor.start(playerObj, Util.text("IGUI_AssistenteNPC_PickAnalyze"), function(square)
        AssistenteNPC.Brain.order("analyze", { x = square:getX(), y = square:getY(), z = square:getZ() })
    end)
end

local function onDeliver(playerObj)
    AssistenteNPC.Brain.order("deliver")
end

local function onGiveAxe(playerObj)
    AssistenteNPC.Brain.giveAxeFrom(playerObj)
end

local function onRecruit(playerObj)
    AssistenteNPC.Recruit.recruit(playerObj)
end

-- ---------------------------------------------------------------------------

local function centerMenu(menu, playerNum)
    menu:setX(getPlayerScreenLeft(playerNum) + getPlayerScreenWidth(playerNum) / 2 - menu:getWidth() / 2)
    menu:setY(getPlayerScreenTop(playerNum) + getPlayerScreenHeight(playerNum) / 2 - menu:getHeight() / 2)
end

function RadialMenu.show(playerObj)
    local playerNum = playerObj:getPlayerNum()
    local menu = getPlayerRadialMenu(playerNum)

    -- A mesma tecla fecha o menu.
    if menu:isReallyVisible() then
        menu:undisplay()
        return
    end

    menu:clear()

    local Brain = AssistenteNPC.Brain
    if Brain.isActive() then
        menu:addSlice(Util.text("IGUI_AssistenteNPC_Follow"), icon("follow"), onFollow, playerObj)
        menu:addSlice(Util.text("IGUI_AssistenteNPC_Stay"), icon("stay"), onStay, playerObj)
        menu:addSlice(Util.text("IGUI_AssistenteNPC_Loot"), icon("loot"), onLoot, playerObj)

        local woodLabel = Brain.hasAxe() and "IGUI_AssistenteNPC_Wood" or "IGUI_AssistenteNPC_WoodNeedsAxe"
        menu:addSlice(Util.text(woodLabel), icon("wood"), onWood, playerObj)

        menu:addSlice(Util.text("IGUI_AssistenteNPC_Guard"), icon("guard"), onGuard, playerObj)
        menu:addSlice(Util.text("IGUI_AssistenteNPC_Analyze"), icon("analyze"), onAnalyze, playerObj)
        menu:addSlice(Util.text("IGUI_AssistenteNPC_Deliver"), icon("deliver"), onDeliver, playerObj)

        if not Brain.hasAxe() and Brain.playerAxe(playerObj) then
            menu:addSlice(Util.text("IGUI_AssistenteNPC_GiveAxe"), icon("giveAxe"), onGiveAxe, playerObj)
        end
    elseif AssistenteNPC.Recruit.findStrayNear(playerObj) then
        menu:addSlice(Util.text("IGUI_AssistenteNPC_Recruit"), icon("recruit"), onRecruit, playerObj)
    elseif Brain.isAlive() then
        Util.halo(playerObj, Util.text("IGUI_AssistenteNPC_TooFar"), "bad")
        return
    else
        Util.halo(playerObj, Util.text("IGUI_AssistenteNPC_NoAssistant"), "bad")
        return
    end

    centerMenu(menu, playerNum)
    menu:addToUIManager()

    if JoypadState.players[playerNum + 1] then
        menu:setHideWhenButtonReleased(Joypad.DPadUp)
        setJoypadFocus(playerNum, menu)
        playerObj:setJoypadIgnoreAimUntilCentered(true)
    end
end

-- ---------------------------------------------------------------------------
-- Tecla (Opcoes > Mods > Assistente NPC)
-- ---------------------------------------------------------------------------

local options = PZAPI.ModOptions:create("AssistenteNPC", getText("UI_AssistenteNPC_ModName"))
RadialMenu.keyOption = options:addKeyBind("radialKey", getText("UI_AssistenteNPC_RadialKey"), Keyboard.KEY_G)

local function onKeyPressed(key)
    if key ~= RadialMenu.keyOption:getValue() then return end
    local playerObj = getSpecificPlayer(0)
    if not playerObj or playerObj:isDead() then return end
    -- Nao abre o menu enquanto o jogador digita no chat.
    if isGamePaused() then return end
    RadialMenu.show(playerObj)
end

Events.OnKeyPressed.Add(onKeyPressed)

return RadialMenu
