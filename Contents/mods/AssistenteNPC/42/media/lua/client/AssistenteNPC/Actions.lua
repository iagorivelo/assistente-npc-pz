-- AssistenteNPC - acoes proprias do assistente (lootear, cortar, largar, entregar).
-- Mesmo contrato das acoes basicas (ver Engine/Executor.lua): onStart /
-- onWorking / onComplete, cada um devolvendo true quando aquela fase terminou.

require "AssistenteNPC/Config"
require "AssistenteNPC/Util"
require "AssistenteNPC/LootFilter"
require "AssistenteNPC/Bridge"
require "AssistenteNPC/Engine/Registry"
require "AssistenteNPC/Engine/Body"
require "AssistenteNPC/Engine/Executor"

local Actions = AssistenteNPC.Actions
local Config = AssistenteNPC.Config
local Util = AssistenteNPC.Util
local LootFilter = AssistenteNPC.LootFilter
local Bridge = AssistenteNPC.Bridge
local Registry = AssistenteNPC.Registry
local Body = AssistenteNPC.Body

local function animStillPlaying(npc, task)
    return npc:getBumpType() == task.anim
end

--- Progresso da ordem atual (record.state).
local function progress(npc)
    local record = Registry.get(Body.ridOf(npc))
    if not record then return nil end
    record.state = record.state or {}
    return record.state, record
end

-- ---------------------------------------------------------------------------
-- Lootear: pega os itens uteis de todos os corpos do square alvo.
-- ---------------------------------------------------------------------------
Actions.AssistenteLoot = {
    onStart = function(npc, task)
        npc:faceLocationF(task.x + 0.5, task.y + 0.5)
        return true
    end,
    onWorking = function(npc, task)
        npc:faceLocationF(task.x + 0.5, task.y + 0.5)
        -- A animacao de lootear nao e em loop: quando termina, a tarefa termina.
        return not animStillPlaying(npc, task)
    end,
    onComplete = function(npc, task)
        local square = Util.getSquare(task.x, task.y, task.z)
        if not square then return true end

        local inventory = npc:getInventory()
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

        local state = progress(npc)
        if state then state.looted = (state.looted or 0) + taken end
        return true
    end,
}

-- ---------------------------------------------------------------------------
-- Cortar arvore: uma sequencia de machadadas. Derruba quando a vida acaba.
-- ---------------------------------------------------------------------------

--- Derruba a arvore. toppleTree (vanilla) cuida da queda e de soltar as toras;
--- se falhar, remove a arvore e cria as toras manualmente.
local function fellTree(npc, square, tree)
    -- Cada tentativa so roda se a arvore ainda estiver de pe, para nunca
    -- derrubar duas vezes nem duplicar toras.
    if pcall(function() tree:toppleTree(npc) end) or not Util.treeOnSquare(square) then return end
    if pcall(function() tree:toppleTree() end) or not Util.treeOnSquare(square) then return end

    local logs = 2
    pcall(function() logs = math.max(1, tree:getLogYield()) end)
    pcall(function() square:transmitRemoveItemFromSquare(tree) end)
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

Actions.AssistenteChop = {
    onStart = function(npc, task)
        local axe = Util.findAxe(npc:getInventory())
        if not axe then return true end -- onComplete nao faz nada sem arvore/machado
        Bridge.equip(npc, axe)
        npc:faceLocationF(task.x + 0.5, task.y + 0.5)
        -- Se a tarefa for interrompida (combate, nova ordem), volta a arma de combate.
        task.onInterrupt = function(n) Bridge.equipBestWeapon(n) end
        return true
    end,
    onWorking = function(npc, task)
        npc:faceLocationF(task.x + 0.5, task.y + 0.5)
        -- A animacao de corte e em loop; a tarefa acaba pelo tempo.
        return false
    end,
    onComplete = function(npc, task)
        local square = Util.getSquare(task.x, task.y, task.z)
        local tree = square and Util.treeOnSquare(square)

        if tree and Util.findAxe(npc:getInventory()) then
            local maxHealth = tree:getMaxHealth()
            if not maxHealth or maxHealth <= 0 then maxHealth = tree:getHealth() end
            local damage = math.max(1, math.ceil(maxHealth / Config.chopHitsPerTree))
            tree:setHealth(math.max(0, tree:getHealth() - damage))
            pcall(function() npc:getEmitter():playSound("ChopTree") end)

            if tree:getHealth() <= 0 and Util.treeOnSquare(square) then
                fellTree(npc, square, tree)
                local state = progress(npc)
                if state then
                    state.felled = (state.felled or 0) + 1
                    state.felledTrees = state.felledTrees or {}
                    table.insert(state.felledTrees, { x = task.x, y = task.y, z = task.z })
                    state.target = nil
                end
            end
        end

        Bridge.equipBestWeapon(npc)
        return true
    end,
}

-- ---------------------------------------------------------------------------
-- Largar no chao todos os itens de um tipo (ex.: toras na pilha).
-- ---------------------------------------------------------------------------
Actions.AssistenteDrop = {
    onStart = function(npc, task) return true end,
    onWorking = function(npc, task)
        return not animStillPlaying(npc, task)
    end,
    onComplete = function(npc, task)
        local square = npc:getSquare()
        if not square then return true end

        local inventory = npc:getInventory()
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

        local state = progress(npc)
        if state then state.dropped = (state.dropped or 0) + #toDrop end
        return true
    end,
}

-- ---------------------------------------------------------------------------
-- Entregar ao jogador tudo que ele carrega (menos a arma em uso e o machado).
-- Se o jogador nao tiver espaco, larga o resto no chao ao lado dele.
-- ---------------------------------------------------------------------------
local function playerHasRoom(player, item)
    local ok, result = pcall(function()
        return player:getInventory():hasRoomFor(player, item)
    end)
    if ok then return result end
    return true
end

Actions.AssistenteGive = {
    onStart = function(npc, task)
        local player = getSpecificPlayer(0)
        if player then npc:faceThisObject(player) end
        return true
    end,
    onWorking = function(npc, task)
        return not animStillPlaying(npc, task)
    end,
    onComplete = function(npc, task)
        local player = getSpecificPlayer(0)
        if not player then return true end

        local inventory = npc:getInventory()
        local playerInventory = player:getInventory()
        local dropped = 0

        for _, item in ipairs(AssistenteNPC.Brain.deliverableItems(npc)) do
            inventory:Remove(item)
            if playerHasRoom(player, item) then
                playerInventory:AddItem(item)
            else
                local square = player:getSquare() or npc:getSquare()
                square:AddWorldInventoryItem(item, ZombRandFloat(0.2, 0.8), ZombRandFloat(0.2, 0.8), 0)
                dropped = dropped + 1
            end
        end
        inventory:setDrawDirty(true)
        playerInventory:setDrawDirty(true)

        Bridge.say(npc, Util.text(dropped > 0 and "IGUI_AssistenteNPC_SayDeliverDropped" or "IGUI_AssistenteNPC_SayDeliver"))

        local _, record = progress(npc)
        if record then AssistenteNPC.Tasks.setOrder(record, "follow") end
        return true
    end,
}
