-- AssistenteNPC - laco por corpo (Events.OnZombieUpdate).
--
-- Para cada zumbi atualizado pelo jogo:
--  1) se ainda nao sabemos quem ele e, olhamos o persistentOutfitID no
--     registro: pode ser um NPC nosso recarregado (vira NPC de novo), um corpo
--     antigo ja substituido (e removido) ou um zumbi comum (ignorado);
--  2) se e um NPC: desliga o comportamento de zumbi, cuida do combate, roda a
--     tarefa atual e, sem tarefa, pergunta ao programa o que fazer.

require "AssistenteNPC/Config"
require "AssistenteNPC/Util"
require "AssistenteNPC/Engine/Registry"
require "AssistenteNPC/Engine/Body"
require "AssistenteNPC/Engine/Executor"
require "AssistenteNPC/Engine/Fight"

AssistenteNPC.Runtime = {}
local Runtime = AssistenteNPC.Runtime
local Config = AssistenteNPC.Config
local Util = AssistenteNPC.Util
local Registry = AssistenteNPC.Registry
local Body = AssistenteNPC.Body
local Executor = AssistenteNPC.Executor
local Fight = AssistenteNPC.Fight

local bodies = {} -- rid -> IsoZombie (so nesta sessao)

local function isValidBody(zombie, rid)
    return zombie ~= nil and not zombie:isDead() and zombie:getCurrentSquare() ~= nil
        and zombie:getModData().anpcRid == rid
end

--- Corpo carregado de um NPC (ou nil se morto/longe/descarregado).
function Runtime.bodyOf(rid)
    local zombie = bodies[rid]
    if isValidBody(zombie, rid) then return zombie end
    bodies[rid] = nil
    return nil
end

function Runtime.bind(rid, zombie)
    bodies[rid] = zombie
end

function Runtime.unbind(rid)
    bodies[rid] = nil
    Executor.forget(rid)
end

--- Reconhece um zumbi que ainda nao foi classificado. Devolve o rid se for NPC.
local function recognize(zombie, md)
    local id = Body.id(zombie)
    if md.anpcSeenId == id then return nil end
    md.anpcSeenId = id

    local rid = Registry.ridForOutfit(id)
    local record = rid and Registry.get(rid)
    if not record then
        if Registry.isRetired(id) then Body.despawn(zombie) end
        return nil
    end
    if record.dying then return nil end

    -- Segunda checagem de identidade: mesmo sexo e perto da ultima posicao conhecida.
    if zombie:isFemale() ~= (record.look.female == true) then return nil end
    if record.x and Util.dist(zombie:getX(), zombie:getY(), record.x, record.y) > 100 then return nil end

    -- Ja existe outro corpo vivo para este NPC: este e uma copia sobrando.
    local current = Runtime.bodyOf(rid)
    if current and current ~= zombie then
        Body.despawn(zombie)
        return nil
    end

    Body.adopt(zombie, record)
    Runtime.bind(rid, zombie)
    Util.log("corpo reconhecido:", record.role, record.name, "outfit", id)
    if AssistenteNPC.Brain then AssistenteNPC.Brain.onBodyLoaded(zombie, record) end
    return rid
end

local function think(zombie, record)
    local program = AssistenteNPC.Program
    if not program then return end
    local ok, tasks = pcall(program.think, zombie, record)
    if not ok then
        print("[AssistenteNPC] erro no programa: " .. tostring(tasks))
        return
    end
    Executor.addAll(zombie, tasks)
end

--- Modo debug: mostra ordem, tarefa e vida acima da cabeca.
local function debugLabel(zombie, record)
    local md = zombie:getModData()
    local now = Util.now()
    if md.anpcDebugAt and now - md.anpcDebugAt < 2000 then return end
    md.anpcDebugAt = now
    local task = Executor.current(zombie)
    local text = string.format("[%s] %s | %s | hp %d | %s",
        tostring(record.role), tostring(record.order), task and task.action or "-",
        math.floor(record.hp or 0), zombie:getActionStateName())
    zombie:addLineChatElement(text, 0.6, 0.6, 1.0)
end

local function onZombieUpdate(zombie)
    local md = zombie:getModData()
    local rid = md.anpcRid
    if not rid then
        rid = recognize(zombie, md)
        if not rid then return end
    end

    local record = Registry.get(rid)
    if not record then
        -- NPC apagado do registro (ex.: morreu e o corpo antigo reapareceu).
        Body.despawn(zombie)
        return
    end
    if record.outfitId ~= Body.id(zombie) then
        -- O jogo reaproveita objetos de zumbi: este objeto ja nao e o nosso NPC.
        md.anpcRid = nil
        md.anpcSeenId = nil
        return
    end
    if bodies[rid] ~= zombie then
        if Runtime.bodyOf(rid) then
            Body.despawn(zombie)
            return
        end
        Runtime.bind(rid, zombie)
    end
    if record.dying then return end

    Body.suppress(zombie, record)
    if Body.isDown(zombie) then
        -- Caido ou cambaleando: descarta as tarefas e espera levantar.
        if not Executor.isEmptyOrHitReact(zombie) then Executor.clear(zombie) end
        return
    end
    Fight.update(zombie, record)
    if record.dying then return end

    if not Executor.tick(zombie) then
        think(zombie, record)
    end
    if Config.debug then debugLabel(zombie, record) end
end

Events.OnZombieUpdate.Add(onZombieUpdate)

return Runtime
