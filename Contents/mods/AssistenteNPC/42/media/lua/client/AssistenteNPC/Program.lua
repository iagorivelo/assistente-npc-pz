-- AssistenteNPC - ZombieProgram registrado no Bandits.
-- O Bandits chama ZombiePrograms.AssistenteNPC[stage](bandit) sempre que o NPC
-- fica sem tarefas (e nao esta em combate corpo a corpo). Devolvemos as proximas
-- tarefas de acordo com a ordem atual (brain.assistente.order).

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

ZombiePrograms = ZombiePrograms or {}

local Config = AssistenteNPC.Config
local Util = AssistenteNPC.Util
local Bridge = AssistenteNPC.Bridge
local Tasks = AssistenteNPC.Tasks
local Combat = AssistenteNPC.Combat

local Program = {}
ZombiePrograms[Config.programName] = Program

local function result(stage, tasks)
    return { status = true, next = stage, tasks = tasks or {} }
end

--- Sobrevivente perdido esperando ser recrutado: fica parado pedindo ajuda.
local function strayTasks(bandit, st, player)
    Bridge.forceStationary(bandit, true)

    local now = Util.now()
    if player and Util.distObj(bandit, player) < 25
        and (not st.state.lastHelp or now - st.state.lastHelp > Config.strayHelpCooldownMs) then
        st.state.lastHelp = now
        Bridge.say(bandit, Util.text("IGUI_AssistenteNPC_SayHelp"))
    end

    local enemy = Combat.findThreatNear(bandit:getX(), bandit:getY(), bandit:getZ(), 3)
    if enemy then
        return { Bridge.faceTask(enemy:getX(), enemy:getY()) }
    end
    if player and Util.distObj(bandit, player) < 10 then
        return { Bridge.faceTask(player:getX(), player:getY()) }
    end
    return Bridge.idleTasks(bandit)
end

Program.Prepare = function(bandit)
    Bridge.forceStationary(bandit, false)
    return result("Main")
end

Program.Main = function(bandit)
    local brain = Bridge.getBrain(bandit)
    local st = brain and brain.assistente
    local player = getSpecificPlayer(0)

    -- Ainda nao foi reconhecido pelo gerenciador (Brain.lua) ou jogador morto.
    if not st or not player or player:isDead() then
        return result("Main", Bridge.idleTasks(bandit))
    end

    st.params = st.params or {}
    st.state = st.state or {}

    if st.role == "stray" then
        return result("Main", strayTasks(bandit, st, player))
    end

    Bridge.forceStationary(bandit, false)

    -- Se um corte foi interrompido (combate, nova ordem), o machado ficou na
    -- mao: volta a arma de combate.
    local melee = Bridge.getMeleeWeapon(bandit)
    local inHand = bandit:getPrimaryHandItem()
    if inHand and Util.isAxe(inHand) and not Util.isAxeType(melee) then
        Bridge.setHands(bandit, melee)
    end

    local handler = Tasks[st.order] or Tasks.follow
    local ok, tasks = pcall(handler, bandit, st, player)
    if not ok then
        print("[AssistenteNPC] erro na tarefa '" .. tostring(st.order) .. "': " .. tostring(tasks))
        Tasks.setOrder(st, "follow")
        tasks = { Bridge.waitTask("Shrug", 100) }
    end
    return result("Main", tasks)
end

return Program
