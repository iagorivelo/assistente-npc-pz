-- AssistenteNPC - ordem "Vigiar local".
-- Vai ate o posto escolhido, ataca zumbis que entrarem no raio de vigia,
-- avisa o jogador e volta para o posto.

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

local function alert(bandit, st, player)
    local now = Util.now()
    if st.state.lastAlert and now - st.state.lastAlert < Config.guardAlertCooldownMs then return end
    st.state.lastAlert = now
    local text = Util.text("IGUI_AssistenteNPC_SayGuardAlert")
    Bridge.say(bandit, text)
    -- Se voce estiver longe, o aviso aparece tambem sobre o seu personagem.
    if player and Util.distObj(bandit, player) > 15 then
        Util.halo(player, text, "bad")
    end
end

function Tasks.guard(bandit, st, player)
    local p = st.params
    if not p.x then
        p.x, p.y, p.z = bandit:getX(), bandit:getY(), bandit:getZ()
    end

    local enemy = Combat.findThreatNear(p.x, p.y, p.z, Config.guardRadius)
    if enemy then
        alert(bandit, st, player)
        return Combat.engage(bandit, enemy)
    end

    local dist = Util.dist(bandit:getX(), bandit:getY(), p.x + 0.5, p.y + 0.5)
    if dist > 1.5 then
        local walkType = dist > Config.followRunDist and "Run" or "Walk"
        return { Bridge.moveTask(bandit, p.x + 0.5, p.y + 0.5, p.z, walkType) }
    end

    -- No posto: fica de olho no zumbi mais proximo, mesmo fora do raio.
    local watched = Combat.findThreatNear(p.x, p.y, p.z, 24)
    if watched then
        return { Bridge.faceTask(watched:getX(), watched:getY()) }
    end
    return Bridge.idleTasks(bandit)
end
