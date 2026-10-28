-- AssistenteNPC - fila de tarefas do NPC.
--
-- Cada tarefa e uma tabela { action = "Nome", time = N, anim = "...", ... }.
-- A acao correspondente (AssistenteNPC.Actions[Nome]) tem tres fases, cada uma
-- devolvendo true quando terminou:
--   onStart(npc, task)    -> comeca (true = passa para onWorking)
--   onWorking(npc, task)  -> roda a cada atualizacao (true = terminou)
--   onComplete(npc, task) -> efeito final (true = remove da fila)
-- task.time conta para baixo (~60 por segundo); ao zerar, a tarefa termina.
-- task.anim, se houver, e tocado com setBumpType (prefixo "ANPC" automatico).
--
-- A fila vive so na memoria: ao recarregar, o programa (Program.lua) decide
-- de novo o que fazer a partir da ordem salva no registro.

require "AssistenteNPC/Util"
require "AssistenteNPC/Engine/Body"

AssistenteNPC.Actions = AssistenteNPC.Actions or {}
AssistenteNPC.Executor = {}
local Executor = AssistenteNPC.Executor
local Actions = AssistenteNPC.Actions
local Util = AssistenteNPC.Util
local Body = AssistenteNPC.Body

local queues = {} -- rid -> lista de tarefas

local function queueOf(zombie)
    local rid = Body.ridOf(zombie)
    if not rid then return nil end
    local q = queues[rid]
    if not q then
        q = {}
        queues[rid] = q
    end
    return q
end

local function animName(anim)
    if not anim or anim == "" then return nil end
    if anim:sub(1, 4) == "ANPC" then return anim end
    return "ANPC" .. anim
end

function Executor.add(zombie, task)
    local q = queueOf(zombie)
    if q then table.insert(q, task) end
end

function Executor.addAll(zombie, tasks)
    for _, task in ipairs(tasks or {}) do
        Executor.add(zombie, task)
    end
end

--- Interrompe a tarefa atual e esvazia a fila.
function Executor.clear(zombie)
    local q = queueOf(zombie)
    if not q then return end
    local current = q[1]
    if current and current.state == "WORKING" and current.action == "Move" then
        pcall(Actions.Move.onComplete, zombie, current)
    end
    if current and current.onInterrupt then
        pcall(current.onInterrupt, zombie, current)
    end
    queues[Body.ridOf(zombie)] = {}
end

function Executor.current(zombie)
    local q = queueOf(zombie)
    return q and q[1] or nil
end

function Executor.isBusyWith(zombie, action)
    local task = Executor.current(zombie)
    return task ~= nil and task.action == action
end

--- Sem tarefa, ou so a reacao a golpe (que pode coexistir com o corpo caido).
function Executor.isEmptyOrHitReact(zombie)
    local task = Executor.current(zombie)
    return task == nil or (task.action == "Time" and task.anim == "ANPCHitReact")
end

function Executor.forget(rid)
    queues[rid] = nil
end

local function frameStep()
    local fps = getAverageFPS and getAverageFPS() or 60
    if not fps or fps < 1 then fps = 60 end
    return 60 / (fps + 0.5)
end

--- Roda a tarefa atual. Devolve true se havia tarefa.
function Executor.tick(zombie)
    local q = queueOf(zombie)
    local task = q and q[1]
    if not task then return false end

    local action = Actions[task.action]
    if not action then
        print("[AssistenteNPC] acao desconhecida: " .. tostring(task.action))
        table.remove(q, 1)
        return true
    end

    if not task.state then
        task.state = "NEW"
        task.time = task.time or 1000
        task.anim = animName(task.anim)
    end

    local ok, err = pcall(function()
        if task.state == "NEW" then
            if task.anim then zombie:setBumpType(task.anim) end
            if action.onStart(zombie, task) then task.state = "WORKING" end
        elseif task.state == "WORKING" then
            task.time = task.time - frameStep()
            if action.onWorking(zombie, task) or task.time <= 0 then
                task.state = "COMPLETED"
            end
        elseif task.state == "COMPLETED" then
            if action.onComplete(zombie, task) and q[1] == task then
                table.remove(q, 1)
            end
        end
    end)
    if not ok then
        print("[AssistenteNPC] erro na acao '" .. tostring(task.action) .. "': " .. tostring(err))
        if q[1] == task then table.remove(q, 1) end
    end
    return true
end

-- ---------------------------------------------------------------------------
-- Acoes basicas
-- ---------------------------------------------------------------------------

--- Andar ate (x, y, z). Com followPlayer = true, o destino acompanha o jogador.
Actions.Move = {
    onStart = function(zombie, task)
        Body.setWalkType(zombie, Body.walkTypeFor(task.walkType))
        local pf = zombie:getPathFindBehavior2()
        pf:pathToLocationF(task.x, task.y, task.z or 0)
        task.repathAt = Util.now()
        return true
    end,
    onWorking = function(zombie, task)
        if task.followPlayer then
            local player = getSpecificPlayer(0)
            if not player then return true end
            if Util.distObj(zombie, player) <= (task.stopDist or 2.0) then return true end
            local moved = Util.dist(player:getX(), player:getY(), task.x, task.y) > 1.5
            if moved and Util.now() - task.repathAt > 500 then
                task.x, task.y, task.z = player:getX(), player:getY(), player:getZ()
                zombie:getPathFindBehavior2():pathToLocationF(task.x, task.y, task.z)
                task.repathAt = Util.now()
            end
        elseif Util.dist(zombie:getX(), zombie:getY(), task.x, task.y) <= (task.stopDist or 0.6) then
            return true
        end
        local result = zombie:getPathFindBehavior2():update()
        return result == BehaviorResult.Succeeded or result == BehaviorResult.Failed
    end,
    onComplete = function(zombie, task)
        local pf = zombie:getPathFindBehavior2()
        pf:cancel()
        pf:reset()
        zombie:setPath2(nil)
        return true
    end,
}

--- Esperar (opcionalmente tocando uma animacao). Termina quando a animacao
--- acaba ou o tempo zera.
Actions.Time = {
    onStart = function(zombie, task) return true end,
    onWorking = function(zombie, task)
        if task.anim and zombie:getBumpType() ~= task.anim then return true end
        return false
    end,
    onComplete = function(zombie, task) return true end,
}

--- Virar para um ponto.
Actions.FaceLocation = {
    onStart = function(zombie, task)
        zombie:faceLocationF(task.x, task.y)
        return true
    end,
    onWorking = function(zombie, task)
        zombie:faceLocationF(task.x, task.y)
        return false
    end,
    onComplete = function(zombie, task) return true end,
}

--- Pegar do chao ate `cnt` itens do tipo `itemType` no square (x, y, z).
Actions.PickUp = {
    onStart = function(zombie, task)
        zombie:faceLocationF(task.x + 0.5, task.y + 0.5)
        return true
    end,
    onWorking = function(zombie, task)
        zombie:faceLocationF(task.x + 0.5, task.y + 0.5)
        return task.anim ~= nil and zombie:getBumpType() ~= task.anim
    end,
    onComplete = function(zombie, task)
        local square = Util.getSquare(task.x, task.y, task.z)
        if not square then return true end
        local inventory = zombie:getInventory()
        local wanted = task.cnt or 1
        local taken = {}
        local objects = square:getWorldObjects()
        for i = 0, objects:size() - 1 do
            local worldItem = objects:get(i)
            local item = worldItem and worldItem:getItem()
            if item and item:getFullType() == task.itemType then
                table.insert(taken, worldItem)
                if #taken >= wanted then break end
            end
        end
        for _, worldItem in ipairs(taken) do
            local item = worldItem:getItem()
            pcall(function() square:transmitRemoveItemFromSquare(worldItem) end)
            pcall(function() worldItem:removeFromWorld() end)
            pcall(function() worldItem:removeFromSquare() end)
            pcall(function() worldItem:setSquare(nil) end)
            pcall(function() item:setWorldItem(nil) end)
            inventory:AddItem(item)
        end
        inventory:setDrawDirty(true)
        return true
    end,
}

return Executor
