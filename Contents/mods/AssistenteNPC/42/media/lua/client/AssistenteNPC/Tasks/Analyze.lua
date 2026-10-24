-- AssistenteNPC - ordem "Analisar area".
-- Vai ate o ponto escolhido, observa por um instante e relata: zumbis,
-- corpos (e quantos tem itens uteis), moveis com itens, itens no chao,
-- arvores e os achados mais interessantes (armas de fogo, municao, remedios).

require "AssistenteNPC/Config"
require "AssistenteNPC/Util"
require "AssistenteNPC/Bridge"
require "AssistenteNPC/Scanner"
require "AssistenteNPC/Tasks/Common"
require "AssistenteNPC/Tasks/Combat"

local Tasks = AssistenteNPC.Tasks
local Config = AssistenteNPC.Config
local Util = AssistenteNPC.Util
local Bridge = AssistenteNPC.Bridge
local Scanner = AssistenteNPC.Scanner
local Combat = AssistenteNPC.Combat

local function report(bandit, st, player)
    local p = st.params
    local result = Scanner.scanArea(p.x, p.y, p.z, Config.analyzeRadius)
    local lines = Scanner.reportLines(result)

    -- Resumo sobre a cabeca do assistente; relatorio completo sobre o jogador.
    Bridge.say(bandit, lines[1])
    for _, line in ipairs(lines) do
        Util.halo(player, line, result.dangerous and "bad" or nil)
    end
end

function Tasks.analyze(bandit, st, player)
    local p = st.params
    if not p.x then
        p.x, p.y, p.z = bandit:getX(), bandit:getY(), bandit:getZ()
    end

    local defense = Combat.selfDefense(bandit)
    if defense then return defense end

    local phase = st.state.phase or "go"

    if phase == "go" then
        local dist = Util.dist(bandit:getX(), bandit:getY(), p.x + 0.5, p.y + 0.5)
        if dist > Config.analyzeArriveDist then
            if Tasks.tryTarget(st, Tasks.squareKey(p.x, p.y, p.z), dist) then
                local walkType = dist > Config.followRunDist and "Run" or "Walk"
                return { Bridge.moveTask(bandit, p.x + 0.5, p.y + 0.5, p.z, walkType) }
            end
            -- Nao conseguiu chegar: analisa de onde esta mesmo.
        end
        st.state.phase = "look"
        return {
            Bridge.faceTask(p.x + 0.5, p.y + 0.5),
            Bridge.waitTask("ShiftWeight", Config.analyzeLookTime),
        }
    end

    report(bandit, st, player)
    Tasks.setOrder(st, "follow")
    return { Bridge.waitTask("WipeBrow", 60) }
end
