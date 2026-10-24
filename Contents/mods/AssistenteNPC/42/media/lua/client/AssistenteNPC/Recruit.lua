-- AssistenteNPC - recrutamento de um novo assistente apos a morte do anterior.
--
-- Fluxo:
--  1) o assistente morre (Brain.lua grava data.deadAtHours);
--  2) depois de Config.recruitCooldownHours horas de jogo, escolhemos um ponto
--     aleatorio longe do jogador e avisamos a direcao ("ao norte...");
--  3) quando aquela area carrega (jogador chegou perto), pedimos ao Bandits
--     um sobrevivente "perdido" ali (brain.key = keyStray);
--  4) ele fica parado pedindo socorro; perto dele, o menu radial mostra
--     "Recrutar sobrevivente" e ele vira o novo assistente.
--
-- data.stray = { x, y, z, id, requestedAt, hintedAt }

require "AssistenteNPC/Config"
require "AssistenteNPC/Util"
require "AssistenteNPC/Bridge"
require "AssistenteNPC/Tasks/Common"

AssistenteNPC.Recruit = {}
local Recruit = AssistenteNPC.Recruit
local Config = AssistenteNPC.Config
local Util = AssistenteNPC.Util
local Bridge = AssistenteNPC.Bridge
local Tasks = AssistenteNPC.Tasks

local HINT_INTERVAL_HOURS = 3
local hintedThisSession = false

local function hint(player, stray)
    local dirKey = Util.directionKey(player:getX(), player:getY(), stray.x, stray.y)
    Util.halo(player, Util.text("IGUI_AssistenteNPC_RecruitHint", Util.text(dirKey)), nil, 255, 220, 120)
    stray.hintedAt = getGameTime():getWorldAgeHours()
end

local function chooseLocation(player)
    local angle = ZombRandFloat(0, 2 * math.pi)
    local dist = ZombRand(Config.recruitSpawnMinDist, Config.recruitSpawnMaxDist + 1)
    return {
        x = math.floor(player:getX() + math.cos(angle) * dist),
        y = math.floor(player:getY() + math.sin(angle) * dist),
        z = 0,
    }
end

local function isGoodSquare(sq)
    if not sq:isFree(false) then return false end
    if BanditUtils and BanditUtils.IsWater and BanditUtils.IsWater(sq) then return false end
    return true
end

local function findSpawnSquare(stray)
    local best = nil
    Util.forEachSquare(stray.x, stray.y, stray.z, 4, function(sq)
        if isGoodSquare(sq) then
            best = sq
            return true
        end
    end)
    return best
end

--- Chamado pelo Brain a cada varredura (~1s).
function Recruit.update(player, data)
    if data.assistantId or data.pendingSpawn or not data.deadAtHours then return end

    local hours = getGameTime():getWorldAgeHours()

    if not data.stray then
        if hours - data.deadAtHours >= Config.recruitCooldownHours then
            data.stray = chooseLocation(player)
            hint(player, data.stray)
            hintedThisSession = true
        end
        return
    end

    local stray = data.stray
    if stray.id then
        -- Ja existe no mundo. Se o jogador esta perto do local e mesmo assim
        -- nao o encontramos por um tempo, ele se perdeu: cria outro ali.
        if AssistenteNPC.Brain.getStray() then
            stray.lostSince = nil
        elseif Util.dist(player:getX(), player:getY(), stray.x, stray.y) < 40 then
            stray.lostSince = stray.lostSince or Util.now()
            if Util.now() - stray.lostSince > Config.strayLostMs then
                stray.id = nil
                stray.requestedAt = nil
                stray.lostSince = nil
            end
        end
        return
    end

    if not hintedThisSession or hours - (stray.hintedAt or 0) >= HINT_INTERVAL_HOURS then
        hintedThisSession = true
        hint(player, stray)
    end

    if stray.requestedAt and Util.now() - stray.requestedAt < Config.spawnTimeoutMs then return end

    -- So da para criar o NPC quando a area estiver carregada.
    if not Util.getSquare(stray.x, stray.y, stray.z) then return end

    local square = findSpawnSquare(stray)
    if not square then
        -- Lugar ruim (agua, parede...): sorteia outro e avisa de novo.
        data.stray = chooseLocation(player)
        hint(player, data.stray)
        return
    end

    stray.requestedAt = Util.now()
    Bridge.spawn(player, square:getX(), square:getY(), square:getZ(), Config.keyStray)
end

--- Sobrevivente recrutavel ao alcance do jogador (ou nil).
function Recruit.findStrayNear(player)
    local stray = AssistenteNPC.Brain.getStray()
    if stray and Util.distObj(stray, player) <= Config.recruitInteractDist then
        return stray
    end
    return nil
end

function Recruit.recruit(player)
    local stray = Recruit.findStrayNear(player)
    if not stray then return end
    local brain = Bridge.getBrain(stray)
    local st = brain and brain.assistente
    if not st then return end

    local data = AssistenteNPC.Brain.getData()
    st.role = "assistant"
    Tasks.setOrder(st, "follow")
    Bridge.forceStationary(stray, false)
    Bridge.clearTasks(stray)

    data.assistantId = brain.id
    data.cid = brain.cid
    data.name = brain.fullname
    data.stray = nil
    data.deadAtHours = nil
    data.missingSince = nil

    Bridge.say(stray, Util.text("IGUI_AssistenteNPC_SayRecruited"))
end

return Recruit
