-- AssistenteNPC - ordem "Pegar madeira".
-- Precisa de um machado no inventario do assistente. Derruba ate
-- Config.woodTreesPerOrder arvores perto da pilha (onde voce estava ao dar a
-- ordem), junta as toras e leva para a pilha.
--
-- Ciclo de decisao (refeito a cada chamada do programa):
--   1) inimigo perto?            -> defende
--   2) carregando toras demais?  -> leva para a pilha
--   3) toras no chao perto da ultima arvore? -> pega
--   4) ainda falta arvore?       -> anda ate a arvore e corta
--   5) sobrou tora no inventario -> leva para a pilha
--   6) fim                       -> avisa e volta a seguir

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

local LOG = "Base.Log"

local function goToPileAndDrop(bandit, st)
    local p = st.params
    local dist = Util.dist(bandit:getX(), bandit:getY(), p.x, p.y)
    -- Se nao conseguir chegar na pilha, larga as toras onde estiver.
    if dist > 1.5 and not Tasks.isSkipped(st, "pile") and Tasks.tryTarget(st, "pile", dist) then
        local walkType = dist > Config.followRunDist and "Run" or "Walk"
        return { Bridge.moveTask(bandit, p.x, p.y, p.z, walkType) }
    end
    if dist > 1.5 then
        -- Pilha inalcancavel: larga aqui e encerra a ordem (senao ele
        -- recolheria essas mesmas toras de novo, para sempre).
        st.state.pileUnreachable = true
    end
    return { { action = "AssistenteDrop", anim = "LootLow", time = 80, itemType = LOG } }
end

local function findLogsAround(st, center)
    local p = st.params
    local found = nil
    Util.forEachSquare(center.x, center.y, center.z, Config.logSearchRadius, function(sq)
        -- Ignora a propria pilha, senao ele recolheria as toras que acabou de largar.
        local nearPile = Util.dist(sq:getX() + 0.5, sq:getY() + 0.5, p.x, p.y) < 2.5
        local skipped = Tasks.isSkipped(st, "log:" .. Tasks.squareKey(sq:getX(), sq:getY(), sq:getZ()))
        if not nearPile and not skipped and #Util.logsOnSquare(sq) > 0 then
            found = sq
            return true
        end
    end)
    return found
end

--- Procura toras em volta de todas as arvores derrubadas nesta ordem
--- (a queda pode ser animada, entao as toras podem aparecer com atraso).
local function findLogsNearFelledTrees(st)
    local trees = st.state.felledTrees
    if not trees then return nil end
    for _, tree in ipairs(trees) do
        local found = findLogsAround(st, tree)
        if found then return found end
    end
    return nil
end

local function findTree(bandit, st)
    local p = st.params
    local best, bestDist = nil, math.huge
    Util.forEachSquare(p.x, p.y, p.z, Config.woodRadius, function(sq)
        if Util.treeOnSquare(sq) and not Tasks.isSkipped(st, Tasks.squareKey(sq:getX(), sq:getY(), sq:getZ())) then
            local d = Util.distToSquare(bandit, sq)
            if d < bestDist then
                best, bestDist = sq, d
            end
        end
    end)
    return best, bestDist
end

--- Square livre ao lado da arvore, de onde ele pode cortar.
local function standingSquare(bandit, treeSquare)
    local ok, adjacent = pcall(AdjacentFreeTileFinder.Find, treeSquare, bandit)
    if ok and adjacent then return adjacent end
    local best, bestDist = nil, math.huge
    Util.forEachSquare(treeSquare:getX(), treeSquare:getY(), treeSquare:getZ(), 1, function(sq)
        if sq ~= treeSquare and sq:isFree(false) and not Util.treeOnSquare(sq) then
            local d = Util.distToSquare(bandit, sq)
            if d < bestDist then best, bestDist = sq, d end
        end
    end)
    return best
end

local function finish(bandit, st, text)
    Bridge.say(bandit, text)
    Tasks.setOrder(st, "follow")
    return { Bridge.waitTask("WipeBrow", 120) }
end

function Tasks.wood(bandit, st, player)
    local p = st.params
    if not p.x then
        p.x, p.y, p.z = player:getX(), player:getY(), player:getZ()
    end

    local inventory = bandit:getInventory()
    if not Util.findAxe(inventory) then
        return finish(bandit, st, Util.text("IGUI_AssistenteNPC_SayWoodNoAxe"))
    end

    local defense = Combat.selfDefense(bandit)
    if defense then return defense end

    local carrying = Util.countType(inventory, LOG)
    if st.state.pileUnreachable and carrying == 0 then
        return finish(bandit, st, Util.text("IGUI_AssistenteNPC_SayWoodDone", tostring(st.state.dropped or 0)))
    end
    if carrying >= Config.logsPerTrip then
        return goToPileAndDrop(bandit, st)
    end

    -- Recolhe as toras das arvores ja derrubadas.
    local logSquare = findLogsNearFelledTrees(st)
    if logSquare then
        local dist = Util.distToSquare(bandit, logSquare)
        if dist > 1.3 then
            local key = "log:" .. Tasks.squareKey(logSquare:getX(), logSquare:getY(), logSquare:getZ())
            if not Tasks.tryTarget(st, key, dist) then
                return { Bridge.waitTask("Shrug", 60) }
            end
            return { Bridge.moveTask(bandit, logSquare:getX() + 0.5, logSquare:getY() + 0.5, logSquare:getZ(), "Walk") }
        end
        return { Bridge.pickUpTask(logSquare:getX(), logSquare:getY(), logSquare:getZ(), LOG, 1) }
    end

    local felled = st.state.felled or 0
    if felled < Config.woodTreesPerOrder then
        local treeSquare, treeDist = findTree(bandit, st)
        if treeSquare then
            local tx, ty, tz = treeSquare:getX(), treeSquare:getY(), treeSquare:getZ()
            if treeDist > 2.0 then
                local standOn = standingSquare(bandit, treeSquare)
                if not standOn or not Tasks.tryTarget(st, Tasks.squareKey(tx, ty, tz), treeDist) then
                    st.state.skip = st.state.skip or {}
                    st.state.skip[Tasks.squareKey(tx, ty, tz)] = true
                    return { Bridge.waitTask("Shrug", 60) }
                end
                local walkType = treeDist > Config.followRunDist and "Run" or "Walk"
                return { Bridge.moveTask(bandit, standOn:getX() + 0.5, standOn:getY() + 0.5, standOn:getZ(), walkType) }
            end
            return { { action = "AssistenteChop", anim = "ChopTree", time = Config.chopTime, x = tx, y = ty, z = tz } }
        elseif felled == 0 and carrying == 0 then
            return finish(bandit, st, Util.text("IGUI_AssistenteNPC_SayWoodNoTree"))
        end
    end

    if carrying > 0 then
        return goToPileAndDrop(bandit, st)
    end

    return finish(bandit, st, Util.text("IGUI_AssistenteNPC_SayWoodDone", tostring(st.state.dropped or 0)))
end
