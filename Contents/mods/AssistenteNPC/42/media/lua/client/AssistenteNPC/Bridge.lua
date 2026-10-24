-- AssistenteNPC - ponte com o mod Bandits (id: Bandits2).
-- Todo acesso a API do Bandits passa por aqui, para que mudancas futuras
-- no Bandits precisem ser corrigidas em um so lugar.
--
-- Como o Bandits funciona (resumo):
--  * O NPC e um IsoZombie "banditizado": o estado dele (brain) fica em
--    zombie:getModData().brain e e salvo nos clusters de ModData do Bandits.
--  * A cada update, se o NPC nao tem tarefas, o Bandits chama
--    ZombiePrograms[brain.program.name][brain.program.stage](bandit), que
--    devolve uma lista de tarefas ({action="Move", ...}).
--  * Cada tarefa e executada por ZombieActions[action] (onStart/onWorking/onComplete).
--  * O combate corpo a corpo e automatico (ManageCombat) quando um inimigo
--    esta ao alcance; o programa so precisa levar o NPC ate perto do inimigo.

require "AssistenteNPC/Config"
require "AssistenteNPC/Util"

AssistenteNPC.Bridge = {}
local Bridge = AssistenteNPC.Bridge
local Config = AssistenteNPC.Config

-- Cor do texto sobre a cabeca do assistente (verde, como os aliados do Bandits).
local SPEECH_R, SPEECH_G, SPEECH_B = 0.1, 0.8, 0.1

function Bridge.isAvailable()
    return Bandit ~= nil and BanditBrain ~= nil and BanditUtils ~= nil and ZombieActions ~= nil
end

function Bridge.getBrain(zombie)
    if not zombie then return nil end
    return BanditBrain.Get(zombie)
end

function Bridge.isBandit(zombie)
    return zombie ~= nil and zombie:getVariableBoolean("Bandit")
end

--- Id estavel do NPC (o mesmo que o Bandits usa como chave do brain).
function Bridge.getId(zombie)
    return BanditUtils.GetCharacterID(zombie)
end

--- Pede ao Bandits para criar um NPC de um dos nossos clas em (x, y, z).
--- Usa "Spawner.Clan" com tamanho 1: o "Spawner.Individual" do Bandits 42.20
--- procura o cla em bandit.cid (que o loader nunca preenche) e nao cria nada.
function Bridge.spawn(player, x, y, z, key, cid, fullname)
    local args = {
        cid = cid or Config.clans[ZombRand(#Config.clans) + 1],
        size = 1,
        x = math.floor(x),
        y = math.floor(y),
        z = math.floor(z or 0),
        program = Config.programName,
        hostile = false,
        hostileP = false,
        permanent = true,
        key = key,
        fullname = fullname,
    }
    sendClientCommand(player, "Spawner", "Clan", args)
    AssistenteNPC.Util.log("spawn pedido", key, args.cid, args.x, args.y, args.z)
end

--- Atualiza a lista de itens que o NPC deixa ao morrer e marca os itens do
--- inventario como "preserve" (sem isso o Bandits apaga tudo na morte).
function Bridge.updateDeathItems(zombie)
    local brain = Bridge.getBrain(zombie)
    if brain then
        pcall(Bandit.UpdateItemsToSpawnAtDeath, zombie, brain)
    end
end

--- Se o jogador acertar um NPC amigavel, o Bandits o torna hostil e troca o
--- programa dele para "Bandit". Desfaz isso no nosso assistente.
--- Retorna true se precisou corrigir.
function Bridge.ensureFriendly(zombie)
    local brain = Bridge.getBrain(zombie)
    if not brain then return false end
    local programName = brain.program and brain.program.name
    if not brain.hostile and not brain.hostileP and programName == Config.programName then
        return false
    end
    brain.hostile = false
    brain.hostileP = false
    brain.program = { name = Config.programName, stage = "Prepare" }
    Bandit.ClearTasks(zombie)
    return true
end

--- Remove o NPC do mundo e apaga o brain dele dos dados do Bandits.
function Bridge.despawn(zombie)
    local brain = Bridge.getBrain(zombie)
    local id = brain and brain.id or Bridge.getId(zombie)
    if GetBanditClusterData then
        local gmd = GetBanditClusterData(id)
        if gmd then gmd[id] = nil end
        if TransmitBanditCluster then pcall(TransmitBanditCluster, id) end
    end
    BanditBrain.Remove(zombie)
    zombie:removeFromWorld()
    zombie:removeFromSquare()
end

function Bridge.say(zombie, text)
    if zombie and text then
        zombie:addLineChatElement(text, SPEECH_R, SPEECH_G, SPEECH_B)
    end
end

function Bridge.clearTasks(zombie)
    Bandit.ClearTasks(zombie)
end

function Bridge.forceStationary(zombie, stationary)
    Bandit.ForceStationary(zombie, stationary)
end

-- ---------------------------------------------------------------------------
-- Construtores de tarefas
-- ---------------------------------------------------------------------------

function Bridge.moveTask(zombie, x, y, z, walkType)
    local dist = AssistenteNPC.Util.dist(zombie:getX(), zombie:getY(), x, y)
    return BanditUtils.GetMoveTask(0, x, y, z, walkType or "Walk", dist, false)
end

--- Move ate um jogador, atualizando o destino enquanto ele anda.
function Bridge.moveToPlayerTask(zombie, player, walkType)
    local dist = AssistenteNPC.Util.distObj(zombie, player)
    local pid = BanditUtils.GetCharacterID(player)
    return BanditUtils.GetMoveTaskTarget(0, player:getX(), player:getY(), player:getZ(), pid, true, walkType or "Walk", dist)
end

function Bridge.faceTask(x, y)
    return { action = "FaceLocation", x = x, y = y, time = 100 }
end

function Bridge.waitTask(anim, time)
    return { action = "Time", anim = anim or "ShiftWeight", time = time or 200 }
end

function Bridge.idleTasks(zombie)
    if BanditPrograms and BanditPrograms.Idle then
        return BanditPrograms.Idle(zombie)
    end
    return { Bridge.waitTask("ShiftWeight", 200) }
end

--- Pega uma tora (ou outro item) do chao usando a acao PickUp do Bandits.
function Bridge.pickUpTask(x, y, z, itemType, count)
    return { action = "PickUp", anim = "LootLow", time = 100, x = x, y = y, z = z, itemType = itemType, cnt = count or 1 }
end

--- Mostra a arma na mao do NPC (ex.: machado durante o corte).
function Bridge.setHands(zombie, fullType)
    if not fullType then return end
    pcall(Bandit.SetHands, zombie, fullType)
end

function Bridge.getMeleeWeapon(zombie)
    local brain = Bridge.getBrain(zombie)
    return brain and brain.weapons and brain.weapons.melee or nil
end

return Bridge
