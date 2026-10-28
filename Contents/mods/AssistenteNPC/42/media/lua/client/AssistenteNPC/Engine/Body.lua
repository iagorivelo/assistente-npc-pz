-- AssistenteNPC - corpo do NPC (um IsoZombie "domesticado").
--
-- Responsabilidades:
--  * criar o corpo (addZombiesInOutfit) e aplicar a aparencia humana;
--  * identificar o corpo entre salvamentos: o jogo recria os zumbis ao
--    carregar, mas mantem o persistentOutfitID, que usamos como identidade;
--  * a cada atualizacao, desligar o comportamento de zumbi (alvo, mordida,
--    gemidos, investida) e manter o tipo de passo humano.

require "AssistenteNPC/Config"
require "AssistenteNPC/Util"
require "AssistenteNPC/Engine/Look"
require "AssistenteNPC/Engine/Registry"

AssistenteNPC.Body = {}
local Body = AssistenteNPC.Body
local Config = AssistenteNPC.Config
local Look = AssistenteNPC.Look

-- Tipos de passo das nossas animacoes (ver media/AnimSets/zombie/walktoward).
Body.WALK = "ANPCWalk"
Body.RUN = "ANPCRun"
Body.SNEAK = "ANPCSneak"

-- Tipos de passo usados pelas tarefas -> tipos das nossas animacoes.
local WALK_TYPES = {
    Walk = Body.WALK,
    WalkAim = Body.WALK,
    Limp = Body.WALK,
    Run = Body.RUN,
    SneakWalk = Body.SNEAK,
}

function Body.walkTypeFor(taskWalkType)
    return WALK_TYPES[taskWalkType] or Body.WALK
end

local ZOMBIE_VOICES = {
    "FemaleZombieVoiceA", "FemaleZombieVoiceB", "FemaleZombieVoiceC",
    "MaleZombieVoiceA", "MaleZombieVoiceB", "MaleZombieVoiceC",
    "MaleZombieCombined", "FemaleZombieCombined",
}

-- O bit de valor 32768 do persistentOutfitID muda quando o chapeu cai; zeramos
-- esse bit para a identidade nao mudar. No Kahlua o % trunca (resto negativo
-- para numeros negativos, que e o caso dos corpos femininos), entao
-- normalizamos o resto antes de testar o bit.
local HAT_BIT = 32768
local LOW_MASK = HAT_BIT * 2

--- Identidade estavel do corpo.
function Body.id(zombie)
    local raw = zombie:getPersistentOutfitID()
    local low = raw % LOW_MASK
    if low < 0 then low = low + LOW_MASK end
    if low >= HAT_BIT then
        raw = raw - HAT_BIT
    end
    return raw
end

-- Roupas-base exclusivas do mod (media/clothing/clothing.xml). Usar uma delas
-- garante que o persistentOutfitID do NPC nunca coincide com o de um zumbi comum.
local BODY_OUTFITS = 10

local function bodyOutfit()
    return "ANPCBody" .. tostring(ZombRand(BODY_OUTFITS) + 1)
end

function Body.ridOf(zombie)
    return zombie and zombie:getModData().anpcRid
end

--- Cria um corpo em (x, y, z) com a aparencia do registro. Devolve o zumbi ou nil.
function Body.spawn(record, x, y, z)
    local look = record.look
    local femaleChance = look.female and 100 or 0
    local ok, list = pcall(addZombiesInOutfit,
        math.floor(x), math.floor(y), math.floor(z or 0),
        1, bodyOutfit(), femaleChance,
        false, false, false, false, -- crawler, fallOnFront, fakeDead, knockedDown
        true, false,                -- invulnerable, sitting
        1.0)                        -- health
    if not ok or not list or list:size() == 0 then
        print("[AssistenteNPC] roupa-base do mod indisponivel, usando 'Naked': " .. tostring(list))
        ok, list = pcall(addZombiesInOutfit, math.floor(x), math.floor(y), math.floor(z or 0),
            1, "Naked", femaleChance, false, false, false, false, true, false, 1.0)
    end
    if not ok or not list or list:size() == 0 then
        print("[AssistenteNPC] nao foi possivel criar o corpo do NPC: " .. tostring(list))
        return nil
    end
    AssistenteNPC.Util.log("corpo criado para", record.role, record.name, "em", x, y, z)
    local zombie = list:get(0)
    Body.adopt(zombie, record)
    return zombie
end

--- Transforma um zumbi no corpo do NPC do registro (spawn novo ou recarregado).
function Body.adopt(zombie, record)
    local md = zombie:getModData()
    md.anpcRid = record.rid

    zombie:setNoTeeth(true)
    zombie:setReanimate(false)
    zombie:setFakeDead(false)
    pcall(function() zombie:setInvulnerable(true) end)
    pcall(function() zombie:setAvoidDamage(true) end)
    pcall(function() zombie:setZombiesDontAttack(true) end)
    -- Faz o motor pular a reacao a golpe de zumbi que acessa "moodles" (que
    -- zumbis nao tem) e travaria o jogo.
    zombie:setVariable("ZombieHitReaction", "Chainsaw")
    zombie:setVariable("NoLungeTarget", true)
    zombie:setVariable("ANPC", true)
    zombie:setVariable("ANPCWalkSpeed", Config.walkSpeed)
    zombie:setVariable("ANPCRunSpeed", Config.runSpeed)
    zombie:setWalkType(Body.WALK)
    zombie:setTurnAlertedValues(-5, 5)
    zombie:clearAttachedItems()
    zombie:setPrimaryHandItem(nil)
    zombie:setSecondaryHandItem(nil)
    pcall(function() zombie:getDescriptor():setVoicePrefix("NotAZombie") end)
    zombie:getEmitter():stopAll()

    Look.apply(zombie, record.look)
    md.anpcWalkType = Body.WALK

    AssistenteNPC.Registry.bindOutfit(record, Body.id(zombie))
end

--- Remove o corpo do mundo (sem deixar cadaver).
function Body.despawn(zombie)
    zombie:getModData().anpcRid = nil
    pcall(function() zombie:removeFromWorld() end)
    pcall(function() zombie:removeFromSquare() end)
end

function Body.setWalkType(zombie, walkType)
    zombie:getModData().anpcWalkType = walkType
    zombie:setWalkType(walkType)
end

local IGNORED_STATES = {
    pathfind = true,
    walktoward = true,
    idle = true,
    bumped = true,
}

--- Chamado a cada atualizacao do corpo: mantem o "zumbi" agindo como gente.
function Body.suppress(zombie, record)
    local md = zombie:getModData()
    zombie:setVariable("ANPC", true)
    zombie:setNoTeeth(true)
    zombie:setTarget(nil)
    -- "useless" desliga a IA de zumbi (vagar, reagir a sons, perseguir quem
    -- avista). O caminho por PathFindBehavior2 continua funcionando.
    zombie:setUseless(true)
    zombie:setEatBodyTarget(nil, false)
    zombie:setWalkType(md.anpcWalkType or Body.WALK)
    zombie:setSpeedMod(1)

    -- Gemidos de zumbi.
    local emitter = zombie:getEmitter()
    for i = 1, #ZOMBIE_VOICES do
        if emitter:isPlaying(ZOMBIE_VOICES[i]) then
            emitter:stopSoundByName(ZOMBIE_VOICES[i])
        end
    end

    -- Estados de zumbi que nao queremos (virar ao ouvir algo, investida).
    local state = zombie:getActionStateName()
    if not IGNORED_STATES[state] then
        if state == "turnalerted" then
            zombie:clearAggroList()
            zombie:changeState(ZombieIdleState.instance())
        elseif state == "lunge" or state == "attack" then
            zombie:clearAggroList()
        end
    end

    -- Se o jogo recriou a aparencia de zumbi (ex.: roupa aplicada com atraso
    -- ao carregar), refaz. A checagem e barata (so le a textura da pele).
    if record and not Look.isApplied(zombie) then
        Look.apply(zombie, record.look)
    end
end

-- Estados em que o corpo esta caido/cambaleando: nenhuma tarefa deve rodar.
local DOWN_STATES = {
    onground = true,
    ["onground-ragdoll"] = true,
    staggerback = true,
    ["staggerback-knockeddown"] = true,
    getup = true,
    ["getup-fromonback"] = true,
    ["getup-fromonfront"] = true,
    ["getup-fromsitting"] = true,
    falldown = true,
    hitreaction = true,
}

function Body.isDown(zombie)
    return DOWN_STATES[zombie:getActionStateName()] == true
end

return Body
