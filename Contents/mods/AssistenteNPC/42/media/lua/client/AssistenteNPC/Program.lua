-- AssistenteNPC - "cerebro" do NPC.
-- O motor (Engine/Runtime.lua) chama Program.think(npc, record) sempre que a
-- fila de tarefas do NPC esvazia. Devolvemos as proximas tarefas de acordo com
-- o papel (assistente ou sobrevivente perdido) e a ordem atual.

require "AssistenteNPC/Config"
require "AssistenteNPC/Util"
require "AssistenteNPC/Bridge"
require "AssistenteNPC/Tasks/Common"
require "AssistenteNPC/Tasks/Combat"
require "AssistenteNPC/Tasks/Follow"
require "AssistenteNPC/Tasks/Stay"
require "AssistenteNPC/Tasks/Guard"
require "AssistenteNPC/Tasks/Loot"
require "AssistenteNPC/Tasks/Wood"
require "AssistenteNPC/Tasks/Analyze"
require "AssistenteNPC/Tasks/Deliver"

AssistenteNPC.Program = {}
local Program = AssistenteNPC.Program
local Config = AssistenteNPC.Config
local Util = AssistenteNPC.Util
local Bridge = AssistenteNPC.Bridge
local Tasks = AssistenteNPC.Tasks
local Combat = AssistenteNPC.Combat

--- Sobrevivente perdido esperando ser recrutado: fica parado pedindo ajuda.
local function strayTasks(npc, record, player)
    local now = Util.now()
    if player and Util.distObj(npc, player) < 25
        and (not record.state.lastHelp or now - record.state.lastHelp > Config.strayHelpCooldownMs) then
        record.state.lastHelp = now
        Bridge.say(npc, Util.text("IGUI_AssistenteNPC_SayHelp"))
    end

    if player and Util.distObj(npc, player) < 10 then
        return { Bridge.faceTask(player:getX(), player:getY()) }
    end
    return Bridge.idleTasks(npc)
end

--- Enquanto ele esta a toa (tarefa "idle"): ha motivo para parar e
--- reavaliar agora? Na ordem "Seguir-me", sim, se voce se afastou.
function Program.shouldStopIdling(npc, record)
    if record.role ~= "assistant" or record.order ~= "follow" then return false end
    local player = getSpecificPlayer(0)
    if not player or player:isDead() then return false end
    return Util.distObj(npc, player) > Config.followMaxDist
        or math.abs(npc:getZ() - player:getZ()) >= 1
end

function Program.think(npc, record)
    local player = getSpecificPlayer(0)
    if not player or player:isDead() then
        return Bridge.idleTasks(npc)
    end

    record.params = record.params or {}
    record.state = record.state or {}

    -- Arma: sempre a melhor que ele tiver (troca se quebrou ou se ganhou outra).
    local inHand = npc:getPrimaryHandItem()
    local best = Bridge.bestWeapon(npc)
    if inHand ~= best then Bridge.equip(npc, best) end

    if record.role == "stray" then
        return strayTasks(npc, record, player)
    end

    local handler = Tasks[record.order] or Tasks.follow
    local ok, tasks = pcall(handler, npc, record, player)
    if not ok then
        print("[AssistenteNPC] erro na tarefa '" .. tostring(record.order) .. "': " .. tostring(tasks))
        Tasks.setOrder(record, "follow")
        tasks = { Bridge.waitTask("Shrug", 100) }
    end
    return tasks
end

return Program
