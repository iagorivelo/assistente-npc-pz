-- AssistenteNPC - ordem "Esperar aqui".
-- Fica parado no ponto onde voce estava; so luta se algo chegar bem perto.

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

function Tasks.stay(bandit, st, player)
    local p = st.params
    if not p.x then
        p.x, p.y, p.z = bandit:getX(), bandit:getY(), bandit:getZ()
    end

    local enemy = Combat.findThreatNear(p.x, p.y, p.z, Config.selfDefenseRadius)
    if enemy then return Combat.engage(bandit, enemy) end

    if Util.dist(bandit:getX(), bandit:getY(), p.x, p.y) > 1.5 then
        return { Bridge.moveTask(bandit, p.x, p.y, p.z, "Walk") }
    end

    return Bridge.idleTasks(bandit)
end
