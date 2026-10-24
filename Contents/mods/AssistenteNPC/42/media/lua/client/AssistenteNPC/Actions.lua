-- AssistenteNPC - acoes (ZombieActions) proprias do assistente.
-- Seguem o contrato do Bandits: onStart / onWorking / onComplete, cada um
-- devolvendo true quando aquela fase terminou. task.anim e aplicado pelo
-- Bandits (setBumpType) antes do onStart; task.time conta para baixo (~60/s).

require "AssistenteNPC/Config"
require "AssistenteNPC/Util"
require "AssistenteNPC/LootFilter"
require "AssistenteNPC/Bridge"

ZombieActions = ZombieActions or {}

local Config = AssistenteNPC.Config
local Util = AssistenteNPC.Util
local LootFilter = AssistenteNPC.LootFilter
local Bridge = AssistenteNPC.Bridge

local function animStillPlaying(zombie, task)
    return zombie:getBumpType() == task.anim
end

local function state(zombie)
    local brain = Bridge.getBrain(zombie)
    return brain and brain.assistente or nil
end

-- ---------------------------------------------------------------------------
-- Lootear: pega os itens uteis de todos os corpos do square alvo.
-- ---------------------------------------------------------------------------
ZombieActions.AssistenteLoot = {}

ZombieActions.AssistenteLoot.onStart = function(zombie, task)
    zombie:faceLocationF(task.x + 0.5, task.y + 0.5)
    return true
end

ZombieActions.AssistenteLoot.onWorking = function(zombie, task)
    zombie:faceLocationF(task.x + 0.5, task.y + 0.5)
    -- A animacao de lootear nao e em loop: quando termina, a tarefa termina.
    return not animStillPlaying(zombie, task)
end

ZombieActions.AssistenteLoot.onComplete = function(zombie, task)
    local square = Util.getSquare(task.x, task.y, task.z)
    if not square then return true end

    local inventory = zombie:getInventory()
    local taken = 0
    for _, body in ipairs(Util.deadBodiesOnSquare(square)) do
        local container = body:getContainer()
        for _, item in ipairs(LootFilter.collectUseful(container)) do
            container:Remove(item)
            inventory:AddItem(item)
            taken = taken + 1
        end
        if container then container:setDrawDirty(true) end
    end
    inventory:setDrawDirty(true)
    Bridge.updateDeathItems(zombie)

    local st = state(zombie)
    if st then
        st.state = st.state or {}
        st.state.looted = (st.state.looted or 0) + taken
    end
    return true
end

-- ---------------------------------------------------------------------------
-- Cortar arvore: uma sequencia de machadadas. Derruba quando a vida acaba.
-- ---------------------------------------------------------------------------
ZombieActions.AssistenteChop = {}

--- Derruba a arvore. toppleTree (vanilla) cuida da queda e de soltar as toras;
--- se falhar, remove a arvore e cria as toras manualmente.
local function fellTree(zombie, square, tree)
    -- Cada tentativa so roda se a arvore ainda estiver de pe, para nunca
    -- derrubar duas vezes nem duplicar toras.
    if pcall(function() tree:toppleTree(zombie) end) or not Util.treeOnSquare(square) then return end
    if pcall(function() tree:toppleTree() end) or not Util.treeOnSquare(square) then return end

    local logs = 2
    pcall(function() logs = math.max(1, tree:getLogYield()) end)
    pcall(function()
        square:transmitRemoveItemFromSquare(tree)
    end)
    pcall(function()
        tree:removeFromWorld()
        tree:removeFromSquare()
    end)
    for _ = 1, logs do
        local log = instanceItem("Base.Log")
        if log then
            square:AddWorldInventoryItem(log, ZombRandFloat(0.1, 0.9), ZombRandFloat(0.1, 0.9), 0)
        end
    end
end

ZombieActions.AssistenteChop.onStart = function(zombie, task)
    local axe = Util.findAxe(zombie:getInventory())
    if axe then
        Bridge.setHands(zombie, axe:getFullType())
    end
    zombie:faceLocationF(task.x + 0.5, task.y + 0.5)
    return true
end

ZombieActions.AssistenteChop.onWorking = function(zombie, task)
    zombie:faceLocationF(task.x + 0.5, task.y + 0.5)
    -- A animacao de corte e em loop; a tarefa acaba pelo tempo.
    return false
end

ZombieActions.AssistenteChop.onComplete = function(zombie, task)
    local square = Util.getSquare(task.x, task.y, task.z)
    local tree = square and Util.treeOnSquare(square)
    local st = state(zombie)

    if tree then
        local maxHealth = tree:getMaxHealth()
        if not maxHealth or maxHealth <= 0 then maxHealth = tree:getHealth() end
        local damage = math.max(1, math.ceil(maxHealth / Config.chopHitsPerTree))
        tree:setHealth(math.max(0, tree:getHealth() - damage))
        pcall(function() zombie:getEmitter():playSound("ChopTree") end)

        if tree:getHealth() <= 0 and Util.treeOnSquare(square) then
            fellTree(zombie, square, tree)
            if st then
                st.state = st.state or {}
                st.state.felled = (st.state.felled or 0) + 1
                st.state.felledTrees = st.state.felledTrees or {}
                table.insert(st.state.felledTrees, { x = task.x, y = task.y, z = task.z })
                st.state.target = nil
            end
        end
    end

    -- Volta a mostrar a arma de combate.
    Bridge.setHands(zombie, Bridge.getMeleeWeapon(zombie))
    return true
end

-- ---------------------------------------------------------------------------
-- Largar no chao todos os itens de um tipo (ex.: toras na pilha).
-- ---------------------------------------------------------------------------
ZombieActions.AssistenteDrop = {}

ZombieActions.AssistenteDrop.onStart = function(zombie, task)
    return true
end

ZombieActions.AssistenteDrop.onWorking = function(zombie, task)
    return not animStillPlaying(zombie, task)
end

ZombieActions.AssistenteDrop.onComplete = function(zombie, task)
    local square = zombie:getSquare()
    if not square then return true end

    local inventory = zombie:getInventory()
    local toDrop = {}
    local items = inventory:getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if item:getFullType() == task.itemType then
            table.insert(toDrop, item)
        end
    end

    for _, item in ipairs(toDrop) do
        inventory:Remove(item)
        square:AddWorldInventoryItem(item, ZombRandFloat(0.2, 0.8), ZombRandFloat(0.2, 0.8), 0)
    end
    inventory:setDrawDirty(true)
    Bridge.updateDeathItems(zombie)

    local st = state(zombie)
    if st then
        st.state = st.state or {}
        st.state.dropped = (st.state.dropped or 0) + #toDrop
    end
    return true
end

-- ---------------------------------------------------------------------------
-- Entregar ao jogador tudo que ele carrega (menos o machado).
-- Se o jogador nao tiver espaco, larga o resto no chao ao lado dele.
-- ---------------------------------------------------------------------------
ZombieActions.AssistenteGive = {}

ZombieActions.AssistenteGive.onStart = function(zombie, task)
    local player = getSpecificPlayer(0)
    if player then zombie:faceThisObject(player) end
    return true
end

ZombieActions.AssistenteGive.onWorking = function(zombie, task)
    return not animStillPlaying(zombie, task)
end

local function playerHasRoom(player, item)
    local ok, result = pcall(function()
        return player:getInventory():hasRoomFor(player, item)
    end)
    if ok then return result end
    return true
end

ZombieActions.AssistenteGive.onComplete = function(zombie, task)
    local player = getSpecificPlayer(0)
    if not player then return true end

    local inventory = zombie:getInventory()
    local playerInventory = player:getInventory()
    local dropped = 0

    for _, item in ipairs(Util.deliverableItems(inventory)) do
        inventory:Remove(item)
        if playerHasRoom(player, item) then
            playerInventory:AddItem(item)
        else
            local square = player:getSquare() or zombie:getSquare()
            square:AddWorldInventoryItem(item, ZombRandFloat(0.2, 0.8), ZombRandFloat(0.2, 0.8), 0)
            dropped = dropped + 1
        end
    end
    inventory:setDrawDirty(true)
    playerInventory:setDrawDirty(true)
    Bridge.updateDeathItems(zombie)

    Bridge.say(zombie, Util.text(dropped > 0 and "IGUI_AssistenteNPC_SayDeliverDropped" or "IGUI_AssistenteNPC_SayDeliver"))

    local st = state(zombie)
    if st then
        st.order = "follow"
        st.params = {}
        st.state = {}
    end
    return true
end
