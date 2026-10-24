-- AssistenteNPC - ordem "Entregar itens".
-- Anda ate o jogador e passa para ele tudo o que carrega (menos o machado).
-- A transferencia acontece na acao AssistenteGive, que tambem volta a ordem
-- para "seguir".

require "AssistenteNPC/Config"
require "AssistenteNPC/Util"
require "AssistenteNPC/Bridge"
require "AssistenteNPC/Tasks/Common"
require "AssistenteNPC/Tasks/Combat"

local Tasks = AssistenteNPC.Tasks
local Config = AssistenteNPC.Config
local Util = AssistenteNPC.Util
local Bridge = AssistenteNPC.Bridge
local Combat = AssistenteNPC.Combat

function Tasks.deliver(bandit, st, player)
    if #Util.deliverableItems(bandit:getInventory()) == 0 then
        Bridge.say(bandit, Util.text("IGUI_AssistenteNPC_SayNothingToDeliver"))
        Tasks.setOrder(st, "follow")
        return { Bridge.waitTask("Shrug", 60) }
    end

    local defense = Combat.selfDefense(bandit)
    if defense then return defense end

    local dist = Util.distObj(bandit, player)
    if dist > 1.8 or math.abs(bandit:getZ() - player:getZ()) >= 1 then
        if not Tasks.tryTarget(st, "player", dist) then
            -- Nao consegue chegar ate voce: desiste e continua carregando os itens.
            Tasks.setOrder(st, "follow")
            return { Bridge.waitTask("Shrug", 60) }
        end
        local walkType = dist > Config.followRunDist and "Run" or "Walk"
        return { Bridge.moveToPlayerTask(bandit, player, walkType) }
    end

    return { { action = "AssistenteGive", anim = "Loot", time = 90 } }
end
