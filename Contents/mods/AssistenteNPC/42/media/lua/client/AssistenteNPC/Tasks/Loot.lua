-- AssistenteNPC - ordem "Lootear corpos".
-- Procura corpos com itens uteis perto de onde a ordem foi dada, pega so o
-- que presta (ver LootFilter) e, ao terminar, traz tudo para o jogador.

require "AssistenteNPC/Config"
require "AssistenteNPC/Util"
require "AssistenteNPC/LootFilter"
require "AssistenteNPC/Bridge"
require "AssistenteNPC/Tasks/Common"
require "AssistenteNPC/Tasks/Combat"

local Tasks = AssistenteNPC.Tasks
local Config = AssistenteNPC.Config
local Util = AssistenteNPC.Util
local LootFilter = AssistenteNPC.LootFilter
local Bridge = AssistenteNPC.Bridge
local Combat = AssistenteNPC.Combat

--- Square com corpo(s) com itens uteis mais proximo do assistente.
local function findLootSquare(bandit, st)
    local p = st.params
    local best, bestDist = nil, math.huge
    Util.forEachSquare(p.x, p.y, p.z, Config.lootRadius, function(sq)
        local key = Tasks.squareKey(sq:getX(), sq:getY(), sq:getZ())
        if Tasks.isSkipped(st, key) then return end
        for _, body in ipairs(Util.deadBodiesOnSquare(sq)) do
            if #LootFilter.collectUseful(body:getContainer()) > 0 then
                local d = Util.distToSquare(bandit, sq)
                if d < bestDist then
                    best, bestDist = sq, d
                end
                return
            end
        end
    end)
    return best, bestDist
end

local function finish(bandit, st)
    local looted = st.state.looted or 0
    if looted > 0 then
        Bridge.say(bandit, Util.text("IGUI_AssistenteNPC_SayLootDone", tostring(looted)))
        Tasks.setOrder(st, "deliver")
    else
        Bridge.say(bandit, Util.text("IGUI_AssistenteNPC_SayLootNone"))
        Tasks.setOrder(st, "follow")
    end
    return { Bridge.waitTask("ShiftWeight", 60) }
end

function Tasks.loot(bandit, st, player)
    local p = st.params
    if not p.x then
        p.x, p.y, p.z = player:getX(), player:getY(), player:getZ()
    end

    local defense = Combat.selfDefense(bandit)
    if defense then return defense end

    if Util.inventoryWeight(bandit:getInventory()) >= Config.lootMaxWeight then
        Bridge.say(bandit, Util.text("IGUI_AssistenteNPC_SayLootFull"))
        Tasks.setOrder(st, "deliver")
        return { Bridge.waitTask("ShiftWeight", 60) }
    end

    local square, dist = findLootSquare(bandit, st)
    if not square then return finish(bandit, st) end

    local x, y, z = square:getX(), square:getY(), square:getZ()
    if dist > 1.3 then
        if not Tasks.tryTarget(st, Tasks.squareKey(x, y, z), dist) then
            return { Bridge.waitTask("Shrug", 60) }
        end
        local walkType = dist > Config.followRunDist and "Run" or "Walk"
        return { Bridge.moveTask(bandit, x + 0.5, y + 0.5, z, walkType) }
    end

    return { { action = "AssistenteLoot", anim = "LootLow", time = Config.lootTime, x = x, y = y, z = z } }
end
