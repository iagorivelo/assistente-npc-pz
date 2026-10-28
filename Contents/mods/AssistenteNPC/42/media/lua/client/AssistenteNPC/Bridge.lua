-- AssistenteNPC - fachada do motor de NPC para as tarefas.
-- As tarefas (Tasks/*.lua) so falam com o motor por aqui: montam tarefas,
-- fazem o NPC falar e trocam a arma da mao.

require "AssistenteNPC/Config"
require "AssistenteNPC/Util"
require "AssistenteNPC/Engine/Executor"

AssistenteNPC.Bridge = {}
local Bridge = AssistenteNPC.Bridge
local Util = AssistenteNPC.Util
local Executor = AssistenteNPC.Executor

-- Cor do texto sobre a cabeca do assistente (verde).
local SPEECH_R, SPEECH_G, SPEECH_B = 0.1, 0.8, 0.1

function Bridge.say(npc, text)
    if npc and text then
        npc:addLineChatElement(text, SPEECH_R, SPEECH_G, SPEECH_B)
    end
end

function Bridge.clearTasks(npc)
    Executor.clear(npc)
end

-- ---------------------------------------------------------------------------
-- Construtores de tarefas
-- ---------------------------------------------------------------------------

--- Andar ate um ponto. A tarefa dura no maximo ~10s; depois o programa
--- reavalia (e manda andar de novo se for o caso).
function Bridge.moveTask(npc, x, y, z, walkType)
    return { action = "Move", x = x, y = y, z = z or 0, walkType = walkType or "Walk", time = 600 }
end

--- Andar ate o jogador, acompanhando enquanto ele se move.
function Bridge.moveToPlayerTask(npc, player, walkType)
    return {
        action = "Move", followPlayer = true,
        x = player:getX(), y = player:getY(), z = player:getZ(),
        walkType = walkType or "Walk", stopDist = 2.0, time = 300,
    }
end

function Bridge.faceTask(x, y)
    return { action = "FaceLocation", x = x, y = y, time = 60 }
end

function Bridge.waitTask(anim, time)
    return { action = "Time", anim = anim, time = time or 120 }
end

local IDLE_ANIMS = { "ShiftWeight", "WipeBrow" }

--- Ficar a toa: na maioria das vezes so espera; as vezes faz um gesto.
function Bridge.idleTasks(npc)
    if ZombRand(6) == 0 then
        return { Bridge.waitTask(IDLE_ANIMS[ZombRand(#IDLE_ANIMS) + 1], 200) }
    end
    return { Bridge.waitTask(nil, 90) }
end

--- Pegar item(ns) do chao.
function Bridge.pickUpTask(x, y, z, itemType, count)
    return { action = "PickUp", anim = "LootLow", time = 100, x = x, y = y, z = z, itemType = itemType, cnt = count or 1 }
end

-- ---------------------------------------------------------------------------
-- Arma na mao
-- ---------------------------------------------------------------------------

--- Melhor arma corpo a corpo do inventario (maior dano, nao quebrada).
function Bridge.bestWeapon(npc)
    local best, bestDamage = nil, -1
    local items = npc:getInventory():getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if instanceof(item, "HandWeapon") and not item:isBroken() and not item:isRanged() then
            local damage = item:getMaxDamage()
            if damage > bestDamage then best, bestDamage = item, damage end
        end
    end
    return best
end

--- Coloca um item (do inventario dele) na mao; nil = maos vazias.
function Bridge.equip(npc, item)
    if npc:getPrimaryHandItem() == item then return end
    npc:setPrimaryHandItem(item)
    npc:resetEquippedHandsModels()
end

--- Garante que ele esta segurando a melhor arma (ou nada, se nao tiver).
function Bridge.equipBestWeapon(npc)
    Bridge.equip(npc, Bridge.bestWeapon(npc))
end

return Bridge
