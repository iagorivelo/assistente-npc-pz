-- AssistenteNPC - recrutamento de um novo assistente apos a morte do anterior.
--
-- Fluxo:
--  1) o assistente morre (Brain.lua grava data.deadAtHours);
--  2) depois de Config.recruitCooldownHours horas de jogo, escolhemos um ponto
--     aleatorio longe do jogador e avisamos a direcao ("ao norte...");
--  3) quando aquela area carrega (jogador chegou perto), criamos ali um
--     sobrevivente "perdido" (registro com role = "stray");
--  4) ele fica parado pedindo socorro; perto dele, o menu radial mostra
--     "Recrutar sobrevivente" e ele vira o novo assistente.
--
-- data.stray = { x, y, z, rid, hintedAt, lostSince }

require "AssistenteNPC/Config"
require "AssistenteNPC/Util"
require "AssistenteNPC/Bridge"
require "AssistenteNPC/Tasks/Common"
require "AssistenteNPC/Engine/Registry"

AssistenteNPC.Recruit = {}
local Recruit = AssistenteNPC.Recruit
local Config = AssistenteNPC.Config
local Util = AssistenteNPC.Util
local Bridge = AssistenteNPC.Bridge
local Tasks = AssistenteNPC.Tasks
local Registry = AssistenteNPC.Registry

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

local function isWater(sq)
    -- B42.20+: IsoGridSquare:has(IsoFlagType); versoes antigas usavam Is().
    local ok, water = pcall(function() return sq:has(IsoFlagType.water) end)
    if ok then return water == true end
    ok, water = pcall(function() return sq:Is(IsoFlagType.water) end)
    return ok and water == true
end

local function isGoodSquare(sq)
    return sq:isFree(false) and not isWater(sq)
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

--- Cria (ou recria) o corpo do sobrevivente no local pendente.
local function spawnStray(player, data)
    local stray = data.stray
    -- So da para criar o NPC quando a area estiver carregada.
    if not Util.getSquare(stray.x, stray.y, stray.z) then return end

    local square = findSpawnSquare(stray)
    if not square then
        -- Lugar ruim (agua, parede...): sorteia outro e avisa de novo.
        local old = stray.rid
        data.stray = chooseLocation(player)
        data.stray.rid = old
        hint(player, data.stray)
        return
    end

    local record = Registry.get(stray.rid)
    local fresh = false
    if not record then
        record = Registry.create("stray")
        stray.rid = record.rid
        fresh = true
    else
        Registry.retireOutfit(record)
    end
    AssistenteNPC.Brain.spawnRecord(record, square:getX(), square:getY(), square:getZ(), fresh)
end

--- Chamado pelo Brain a cada varredura (~1s).
function Recruit.update(player, data)
    if data.assistantRid or not data.deadAtHours then return end

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
    if AssistenteNPC.Brain.getStray() then
        stray.lostSince = nil
        return
    end

    if not hintedThisSession or hours - (stray.hintedAt or 0) >= HINT_INTERVAL_HOURS then
        hintedThisSession = true
        hint(player, stray)
    end

    if not stray.rid then
        spawnStray(player, data)
        return
    end

    -- Ja foi criado. Se o jogador esta perto do local e mesmo assim nao o
    -- encontramos por um tempo, o corpo se perdeu: cria de novo ali.
    if Util.dist(player:getX(), player:getY(), stray.x, stray.y) < 40 then
        stray.lostSince = stray.lostSince or Util.now()
        if Util.now() - stray.lostSince > Config.strayLostMs then
            stray.lostSince = nil
            spawnStray(player, data)
        end
    else
        stray.lostSince = nil
    end
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
    local record = AssistenteNPC.Brain.recordOf(stray)
    if not record then return end

    local data = AssistenteNPC.Brain.getData()
    record.role = "assistant"
    Tasks.setOrder(record, "follow")
    Bridge.clearTasks(stray)

    data.assistantRid = record.rid
    data.stray = nil
    data.deadAtHours = nil

    Bridge.say(stray, Util.text("IGUI_AssistenteNPC_SayRecruited"))
end

return Recruit
