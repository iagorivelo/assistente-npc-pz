-- AssistenteNPC - escolha de alvo em combate.
-- O golpe em si e automatico (ManageCombat do Bandits ataca quem estiver ao
-- alcance). Aqui decidimos PARA ONDE o assistente vai quando ha perigo.

require "AssistenteNPC/Config"
require "AssistenteNPC/Util"
require "AssistenteNPC/Bridge"

AssistenteNPC.Tasks = AssistenteNPC.Tasks or {}
AssistenteNPC.Combat = {}
local Combat = AssistenteNPC.Combat
local Config = AssistenteNPC.Config
local Util = AssistenteNPC.Util
local Bridge = AssistenteNPC.Bridge

-- Ultimo zumbi que o jogador acertou (nao persiste: e so memoria de curto prazo).
local lastPlayerTarget = nil

local function onHitZombie(zombie, attacker, bodyPartType, handWeapon)
    if attacker and attacker == getSpecificPlayer(0) and Util.isLiveZombie(zombie) then
        lastPlayerTarget = { zombie = zombie, time = Util.now() }
    end
end
Events.OnHitZombie.Add(onHitZombie)

--- Zumbi que o jogador esta atacando agora (se ainda valido).
function Combat.playerTarget(bandit)
    if not lastPlayerTarget then return nil end
    local zed = lastPlayerTarget.zombie
    if Util.now() - lastPlayerTarget.time > Config.assistMemoryMs or not Util.isLiveZombie(zed) then
        lastPlayerTarget = nil
        return nil
    end
    if Util.distObj(bandit, zed) > Config.assistMaxChase then return nil end
    return zed
end

--- Inimigo mais urgente para defender o jogador:
--- 1) o zumbi que o jogador esta atacando; 2) zumbis mirando o jogador;
--- 3) o zumbi mais proximo do jogador dentro do raio de assistencia.
function Combat.findThreatToPlayer(bandit, player)
    local target = Combat.playerTarget(bandit)
    if target then return target end

    local list = Util.zombiesNear(player:getX(), player:getY(), player:getZ(), Config.assistRadius)
    for _, entry in ipairs(list) do
        if entry.zombie:getTarget() == player then return entry.zombie end
    end
    if list[1] then return list[1].zombie end
    return nil
end

--- Inimigo mais proximo de um ponto, num raio.
function Combat.findThreatNear(x, y, z, radius)
    return (Util.nearestZombie(x, y, z, radius))
end

--- Tarefa de aproximacao (andando em posicao de ataque) ate o inimigo.
function Combat.engage(bandit, enemy)
    local walkType = "WalkAim"
    if Util.distObj(bandit, enemy) > Config.followRunDist then walkType = "Run" end
    return { Bridge.moveTask(bandit, enemy:getX(), enemy:getY(), enemy:getZ(), walkType) }
end

--- Autodefesa usada durante tarefas (lootear, madeira...).
function Combat.selfDefense(bandit)
    local enemy = Combat.findThreatNear(bandit:getX(), bandit:getY(), bandit:getZ(), Config.selfDefenseRadius)
    if enemy then return Combat.engage(bandit, enemy) end
    return nil
end

return Combat
