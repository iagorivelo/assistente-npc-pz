-- AssistenteNPC - ordem "Seguir-me" (tambem e o comportamento padrao).
-- Segue o jogador, imita o passo dele (correr/agachar) e o defende de zumbis.

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

local function walkTypeFor(bandit, player, dist)
    if bandit:getHealth() < 0.4 then return "Limp" end
    if player:isSprinting() or player:isRunning() or dist > Config.followRunDist then return "Run" end
    if player:isSneaking() then return "SneakWalk" end
    return "Walk"
end

function Tasks.follow(bandit, st, player)
    local enemy = Combat.findThreatToPlayer(bandit, player)
    if enemy then
        if not st.state.saidCombat then
            st.state.saidCombat = true
            Bridge.say(bandit, Util.text("IGUI_AssistenteNPC_SayCombat"))
        end
        return Combat.engage(bandit, enemy)
    end
    st.state.saidCombat = false

    local dist = Util.distObj(bandit, player)
    if dist > Config.followMaxDist or math.abs(bandit:getZ() - player:getZ()) >= 1 then
        return { Bridge.moveToPlayerTask(bandit, player, walkTypeFor(bandit, player, dist)) }
    end

    return Bridge.idleTasks(bandit)
end
