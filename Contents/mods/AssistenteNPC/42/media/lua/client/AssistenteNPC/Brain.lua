-- AssistenteNPC - gerenciador do assistente (lado do jogador).
--
-- Responsabilidades:
--  * criar o assistente inicial quando o jogo comeca;
--  * reconhecer, na lista de zumbis, os NPCs que pedimos ao Bandits
--    (pela brain.key) e marcar brain.assistente;
--  * detectar a morte do assistente (e iniciar o ciclo de recrutamento);
--  * trazer o assistente de volta se ele ficar para tras (ex.: viagem de carro);
--  * receber as ordens do menu radial.
--
-- Dados globais (salvos com o mundo): ModData "AssistenteNPC"
--   initialized      assistente inicial ja foi criado
--   assistantId      id (Bandits) do assistente atual, nil se morto
--   pendingSpawn     {key, at, tries} pedido de spawn aguardando aparecer
--   order            espelho da ordem atual (para quando o NPC esta descarregado)
--   cid, name        cla (= visual) e nome do assistente (para recria-lo igual)
--   inventory        espelho do inventario (ver Util.serializeInventory)
--   restoreInventory itens a devolver ao assistente recriado
--   deadAtHours      hora (idade do mundo) em que o assistente morreu
--   stray            sobrevivente recrutavel pendente (ver Recruit.lua)

require "AssistenteNPC/Config"
require "AssistenteNPC/Util"
require "AssistenteNPC/Bridge"
require "AssistenteNPC/Tasks/Common"
require "AssistenteNPC/Actions"
require "AssistenteNPC/Program"

AssistenteNPC.Brain = {}
local Brain = AssistenteNPC.Brain
local Config = AssistenteNPC.Config
local Util = AssistenteNPC.Util
local Bridge = AssistenteNPC.Bridge
local Tasks = AssistenteNPC.Tasks

local npcRef = nil        -- IsoZombie do assistente (se carregado)
local strayRef = nil      -- IsoZombie do sobrevivente recrutavel (se carregado)
local gameStartMs = nil
local lastScanMs = 0
local warnedMissingBandits = false
local sessionReady = false -- dados de tempo real (ms) do save anterior ja foram limpos?

-- Falas ao receber cada ordem.
local ORDER_SPEECH = {
    follow = "IGUI_AssistenteNPC_SayFollow",
    stay = "IGUI_AssistenteNPC_SayStay",
    loot = "IGUI_AssistenteNPC_SayLootStart",
    wood = "IGUI_AssistenteNPC_SayWoodStart",
    guard = "IGUI_AssistenteNPC_SayGuardStart",
    analyze = "IGUI_AssistenteNPC_SayAnalyzeStart",
}

-- Ordens em que ele deve ficar onde esta, mesmo longe do jogador.
local STATIONARY_ORDERS = { stay = true, guard = true }

function Brain.getData()
    return ModData.getOrCreate("AssistenteNPC")
end

local function isValidRef(zombie)
    return zombie ~= nil and not zombie:isDead() and zombie:getCurrentSquare() ~= nil
        and Bridge.getBrain(zombie) ~= nil
end

function Brain.getNPC()
    if isValidRef(npcRef) then return npcRef end
    npcRef = nil
    return nil
end

function Brain.getStray()
    if isValidRef(strayRef) then
        local st = Bridge.getBrain(strayRef).assistente
        if st and st.role == "stray" then return strayRef end
    end
    strayRef = nil
    return nil
end

--- Tem um assistente vivo e perto o bastante para receber ordens.
function Brain.isActive()
    return Brain.getNPC() ~= nil
end

--- Tem um assistente vivo (mesmo que longe/descarregado).
function Brain.isAlive()
    return Brain.getData().assistantId ~= nil
end

-- ---------------------------------------------------------------------------
-- Ordens (chamadas pelo menu radial)
-- ---------------------------------------------------------------------------

function Brain.hasAxe()
    local npc = Brain.getNPC()
    return npc ~= nil and Util.findAxe(npc:getInventory()) ~= nil
end

function Brain.order(name, params)
    local npc = Brain.getNPC()
    if not npc then return end
    local st = Bridge.getBrain(npc).assistente
    if not st then return end

    if name == "wood" and not Brain.hasAxe() then
        Bridge.say(npc, Util.text("IGUI_AssistenteNPC_SayWoodNoAxe"))
        return
    end

    Bridge.clearTasks(npc)
    Tasks.setOrder(st, name, params)
    if ORDER_SPEECH[name] then
        Bridge.say(npc, Util.text(ORDER_SPEECH[name]))
    end
end

local function isAxePredicate(item)
    return Util.isAxe(item)
end

--- Machado em qualquer lugar do inventario do jogador (inclusive mochilas).
function Brain.playerAxe(player)
    local ok, item = pcall(function()
        return player:getInventory():getFirstEvalRecurse(isAxePredicate)
    end)
    if ok and item then return item end
    return Util.findAxe(player:getInventory())
end

function Brain.giveAxeFrom(player)
    local npc = Brain.getNPC()
    if not npc then return end

    local axe = Brain.playerAxe(player)
    if not axe then
        Bridge.say(npc, Util.text("IGUI_AssistenteNPC_SayNoAxeToGive"))
        return
    end

    pcall(function()
        if player:isEquipped(axe) then player:removeFromHands(axe) end
    end)
    pcall(function() player:removeAttachedItem(axe) end)
    local container = axe:getContainer() or player:getInventory()
    container:Remove(axe)
    container:setDrawDirty(true)

    npc:getInventory():AddItem(axe)
    Bridge.say(npc, Util.text("IGUI_AssistenteNPC_SayGotAxe"))
end

-- ---------------------------------------------------------------------------
-- Spawn
-- ---------------------------------------------------------------------------

local initRetryAtMs = nil -- quando o spawn inicial falhou: hora (ms) da proxima tentativa

local function spawnNear(player, key, cid, fullname)
    local square = Util.findFreeSquareNear(player:getX() + 1, player:getY() + 1, player:getZ(), 2)
        or player:getCurrentSquare()
    Bridge.spawn(player, square:getX(), square:getY(), square:getZ(), key, cid, fullname)
end

function Brain.requestAssistantSpawn(player, restoreInventory)
    local data = Brain.getData()
    local pending = data.pendingSpawn
    data.pendingSpawn = {
        key = Config.keyAssistant,
        at = Util.now(),
        tries = (pending and pending.tries or 0) + 1,
        relocate = restoreInventory ~= nil or (pending ~= nil and pending.relocate),
    }
    if restoreInventory then data.restoreInventory = restoreInventory end
    spawnNear(player, Config.keyAssistant, data.cid, data.name)
end

-- ---------------------------------------------------------------------------
-- Inventario: o Bandits nao salva o inventario do NPC (o zumbi e recriado a
-- partir do brain ao recarregar). Guardamos uma copia em brain.assistente.items
-- (salva junto com o brain) e em data.inventory (para recriar o assistente).
-- ---------------------------------------------------------------------------

local function inventorySignature(inventory)
    local parts = {}
    local items = inventory:getItems()
    for i = 0, items:size() - 1 do
        parts[#parts + 1] = items:get(i):getFullType()
    end
    return table.concat(parts, ",")
end

local function syncInventory(npc, st, data)
    local inventory = npc:getInventory()
    local objData = npc:getModData()

    -- Primeira vez que vemos este objeto: se ele voltou sem itens, devolve.
    if not objData.assistenteChecked then
        objData.assistenteChecked = true
        if inventory:getItems():size() == 0 and st.items and #st.items > 0 then
            Util.restoreInventory(inventory, st.items)
        end
    end

    local signature = inventorySignature(inventory)
    if signature ~= objData.assistenteSig then
        objData.assistenteSig = signature
        st.items = Util.serializeInventory(inventory)
        -- Marca os itens como "preserve" para nao sumirem quando ele morrer.
        Bridge.updateDeathItems(npc)
    end
    data.inventory = st.items
end

-- ---------------------------------------------------------------------------
-- Reconhecimento dos NPCs na lista de zumbis
-- ---------------------------------------------------------------------------

local function newState(role, order)
    return { role = role, order = order, params = {}, state = {}, items = {} }
end

local function claimAssistant(npc, brain, data)
    brain.assistente = newState("assistant", "follow")
    local relocated = data.restoreInventory ~= nil
    if relocated then
        Util.restoreInventory(npc:getInventory(), data.restoreInventory)
        data.restoreInventory = nil
    end
    npc:getModData().assistenteChecked = true

    data.assistantId = brain.id
    data.pendingSpawn = nil
    data.missingSince = nil
    initRetryAtMs = nil
    data.order = "follow"
    data.cid = brain.cid
    data.name = brain.fullname
    npcRef = npc

    if not relocated then
        Bridge.say(npc, Util.text("IGUI_AssistenteNPC_SayHello"))
    end
end

local function onFound(zombie, brain, data)
    local st = brain.assistente

    if not st then
        if brain.key == Config.keyAssistant then
            if data.pendingSpawn and data.pendingSpawn.key == Config.keyAssistant then
                claimAssistant(zombie, brain, data)
            else
                -- Copia sobrando (ex.: pedido de spawn repetido): remove.
                Bridge.despawn(zombie)
            end
        elseif brain.key == Config.keyStray then
            if data.stray and not data.stray.id then
                brain.assistente = newState("stray", "stay")
                data.stray.id = brain.id
                strayRef = zombie
            else
                Bridge.despawn(zombie)
            end
        end
        return
    end

    -- Fogo amigo: o Bandits torna hostil quem o jogador acerta. Desfaz.
    Bridge.ensureFriendly(zombie)

    if st.role == "assistant" then
        if brain.id == data.assistantId then
            npcRef = zombie
            -- O original voltou a carregar antes da copia aparecer: cancela a recriacao.
            if data.pendingSpawn and data.pendingSpawn.relocate then
                data.pendingSpawn = nil
                data.restoreInventory = nil
            end
        else
            -- Assistente antigo (foi recriado perto do jogador): remove o original.
            Bridge.despawn(zombie)
        end
    elseif st.role == "stray" then
        if data.stray and data.stray.id == brain.id then
            strayRef = zombie
        else
            Bridge.despawn(zombie)
        end
    end
end

local function scanZombies(data)
    npcRef, strayRef = Brain.getNPC(), Brain.getStray()
    local list = getCell():getZombieList()
    for i = list:size() - 1, 0, -1 do
        local zombie = list:get(i)
        if zombie and not zombie:isDead() and Bridge.isBandit(zombie) then
            local brain = Bridge.getBrain(zombie)
            if brain and (brain.assistente or brain.key == Config.keyAssistant or brain.key == Config.keyStray) then
                onFound(zombie, brain, data)
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Laco principal
-- ---------------------------------------------------------------------------

--- Timestamps em ms (getTimestampMs) nao valem entre sessoes: zera ao carregar.
local function resetSessionTimers(data)
    data.missingSince = nil
    if data.pendingSpawn then data.pendingSpawn.at = Util.now() end
    if data.stray then
        data.stray.requestedAt = nil
        data.stray.lostSince = nil
    end
end

local function update(player, data)
    local now = Util.now()

    if not sessionReady then
        sessionReady = true
        resetSessionTimers(data)
    end

    -- Assistente inicial (jogo novo ou mod adicionado a um save existente).
    if not data.initialized then
        if initRetryAtMs and now < initRetryAtMs then return end
        data.initialized = true
        data.order = "follow"
        Brain.requestAssistantSpawn(player)
        return
    end

    scanZombies(data)

    local npc = Brain.getNPC()
    if npc then
        data.missingSince = nil
        local st = Bridge.getBrain(npc).assistente
        data.order = st.order
        syncInventory(npc, st, data)
    elseif data.assistantId or data.pendingSpawn then
        local pending = data.pendingSpawn
        if pending then
            if now - pending.at > Config.spawnTimeoutMs then
                if pending.tries >= 3 then
                    print("[AssistenteNPC] o Bandits nao criou o assistente apos 3 tentativas; tentando de novo mais tarde.")
                    data.pendingSpawn = nil
                    if not data.assistantId then
                        -- Spawn inicial falhou: volta a tentar depois de um tempo.
                        data.initialized = false
                        initRetryAtMs = now + Config.spawnRetryMs
                    end
                else
                    Brain.requestAssistantSpawn(player)
                end
            end
        elseif not STATIONARY_ORDERS[data.order] and not player:getVehicle() then
            -- Ficou para tras: recria perto do jogador com o mesmo nome/visual/itens.
            data.missingSince = data.missingSince or now
            if now - data.missingSince > Config.relocateAfterMs then
                Util.log("assistente sumido, recriando perto do jogador")
                Brain.requestAssistantSpawn(player, data.inventory or {})
            end
        end
    end

    if AssistenteNPC.Recruit then
        AssistenteNPC.Recruit.update(player, data)
    end
end

local function onTick()
    local now = Util.now()
    if not gameStartMs or now - gameStartMs < Config.startDelayMs then return end
    if now - lastScanMs < Config.scanIntervalMs then return end
    lastScanMs = now

    local player = getSpecificPlayer(0)
    if not player or player:isDead() then return end

    if not Bridge.isAvailable() then
        if not warnedMissingBandits then
            warnedMissingBandits = true
            Util.halo(player, Util.text("IGUI_AssistenteNPC_MissingBandits"), "bad")
            print("[AssistenteNPC] mod Bandits (Bandits2) nao encontrado - assistente desativado.")
        end
        return
    end

    update(player, Brain.getData())
end

local function onGameStart()
    gameStartMs = Util.now()
    lastScanMs = 0
    sessionReady = false
    initRetryAtMs = nil
    npcRef, strayRef = nil, nil
end

--- Correcao imediata do fogo amigo (a varredura tambem corrige, ate 1s depois).
local function onHitZombie(zombie, attacker, bodyPartType, handWeapon)
    if not Bridge.isAvailable() then return end
    local brain = Bridge.getBrain(zombie)
    if brain and brain.assistente then
        Bridge.ensureFriendly(zombie)
    end
end

--- Morte. Nao depende do brain: se o handler do Bandits rodar antes, ele ja
--- removeu o brain e a variavel "Bandit". Usamos a referencia do objeto e o
--- brainId que o Bandits grava no modData do zumbi.
local function onZombieDead(zombie)
    local data = Brain.getData()
    local brain = zombie:getModData().brain
    local id = (brain and brain.id) or zombie:getModData().brainId
    local hours = getGameTime():getWorldAgeHours()

    local isAssistant = zombie == npcRef or (id ~= nil and id == data.assistantId)
    local isStray = zombie == strayRef or (id ~= nil and data.stray ~= nil and id == data.stray.id)

    if isAssistant and data.assistantId then
        data.assistantId = nil
        data.pendingSpawn = nil
        data.missingSince = nil
        data.inventory = {}
        data.deadAtHours = hours
        npcRef = nil
        Util.halo(getSpecificPlayer(0), Util.text("IGUI_AssistenteNPC_Died"), "bad")
    elseif isStray and data.stray then
        -- O sobrevivente morreu antes de ser recrutado: outro aparecera mais tarde.
        data.stray = nil
        data.deadAtHours = hours
        strayRef = nil
    end
end

Events.OnGameStart.Add(onGameStart)
Events.OnTick.Add(onTick)
Events.OnHitZombie.Add(onHitZombie)
Events.OnZombieDead.Add(onZombieDead)

return Brain
