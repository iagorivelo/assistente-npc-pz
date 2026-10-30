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
require "AssistenteNPC/Engine/Obstacles"

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

local OBSTACLE_CHECK_MS = 150
local STUCK_MOVE_DIST = 0.75     -- andar menos que isso ...
local STUCK_UNSEEN_MS = 3000     -- ... por esse tempo, longe da vista do jogador = travado
local STUCK_SEEN_MS = 8000       -- ... por esse tempo, mesmo a vista = travado
local STUCK_MIN_PLAYER_DIST = 4  -- perto do jogador nao precisa reaparecer

--- Acompanha se o NPC esta saindo do lugar. Devolve ha quantos ms ele esta
--- parado (enquanto tenta andar).
local function stuckTime(zombie, now)
    local md = zombie:getModData()
    local anchor = md.anpcMoveAnchor
    -- Um Move novo logo depois de outro continua a mesma medicao.
    if not anchor or now - (md.anpcMoveLastAt or 0) > 1000
        or Util.dist(zombie:getX(), zombie:getY(), anchor.x, anchor.y) > STUCK_MOVE_DIST then
        anchor = { x = zombie:getX(), y = zombie:getY(), at = now }
        md.anpcMoveAnchor = anchor
    end
    md.anpcMoveLastAt = now
    return now - anchor.at
end

local function isSeenByPlayer(zombie)
    local square = zombie:getCurrentSquare()
    if not square then return false end
    local ok, seen = pcall(function() return square:isCanSee(0) end)
    return ok and seen == true
end

--- Andar ate (x, y, z). Com followPlayer = true, o destino acompanha o jogador.
--- Abre portas e janelas e pula cercas no caminho (Engine/Obstacles.lua).
Actions.Move = {
    onStart = function(zombie, task)
        Body.setWalkType(zombie, Body.walkTypeFor(task.walkType))
        local pf = zombie:getPathFindBehavior2()
        pf:pathToLocationF(task.x, task.y, task.z or 0)
        task.repathAt = Util.now()
        return true
    end,
    onWorking = function(zombie, task)
        local Obstacles = AssistenteNPC.Obstacles
        local now = Util.now()
        local player = getSpecificPlayer(0)
        if task.followPlayer then
            if not player then return true end
            if Util.distObj(zombie, player) <= (task.stopDist or 2.0) then return true end
            local moved = Util.dist(player:getX(), player:getY(), task.x, task.y) > 1.5
            if moved and now - task.repathAt > 500 and not Obstacles.isClimbing(zombie) then
                task.x, task.y, task.z = player:getX(), player:getY(), player:getZ()
                zombie:getPathFindBehavior2():pathToLocationF(task.x, task.y, task.z)
                task.repathAt = now
            end
        elseif Util.dist(zombie:getX(), zombie:getY(), task.x, task.y) <= (task.stopDist or 0.6) then
            return true
        end

        if Obstacles.isClimbing(zombie) then
            zombie:getModData().anpcMoveLastAt = now
            return false
        end

        -- Medido antes dos obstaculos: um caminho bloqueado tambem conta como travado.
        local stuckMs = stuckTime(zombie, now)
        if stuckMs > STUCK_UNSEEN_MS then
            if task.followPlayer and Util.distObj(zombie, player) > STUCK_MIN_PLAYER_DIST
                and (stuckMs > STUCK_SEEN_MS or not isSeenByPlayer(zombie)) then
                Obstacles.unstick(zombie, player)
                zombie:getModData().anpcMoveAnchor = nil
                return true
            end
            if not task.followPlayer and stuckMs > STUCK_SEEN_MS then
                -- Alvo de tarefa inalcancavel: desiste (a tarefa conta a tentativa).
                task.blocked = true
                zombie:getModData().anpcMoveAnchor = nil
                return true
            end
        end

        if not task.obstacleAt or now - task.obstacleAt >= OBSTACLE_CHECK_MS then
            task.obstacleAt = now
            local ok, status = pcall(Obstacles.check, zombie)
            if ok and status == Obstacles.BLOCKED then
                task.blocked = true
                return true
            end
            if ok and status == Obstacles.BUSY then return false end
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
