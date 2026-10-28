-- AssistenteNPC - gerenciador do assistente (lado do jogador).
--
-- Responsabilidades:
--  * criar o assistente inicial quando o jogo comeca;
--  * manter o inventario do NPC salvo (o jogo nao salva o inventario de zumbis)
--    e devolve-lo quando o corpo e recriado;
--  * trazer o assistente de volta se ele ficar para tras (ex.: viagem de carro);
--  * detectar a morte (e iniciar o ciclo de recrutamento, ver Recruit.lua);
--  * receber as ordens do menu radial.
--
-- Dados globais (ModData "AssistenteNPC", alem do que o Registry guarda):
--   initialized   assistente inicial ja foi criado
--   assistantRid  registro do assistente atual (nil se morto)
--   deadAtHours   hora (idade do mundo) em que o assistente morreu
--   stray         sobrevivente recrutavel pendente (ver Recruit.lua)

require "AssistenteNPC/Config"
require "AssistenteNPC/Util"
require "AssistenteNPC/Bridge"
require "AssistenteNPC/Tasks/Common"
require "AssistenteNPC/Engine/Registry"
require "AssistenteNPC/Engine/Body"
require "AssistenteNPC/Engine/Executor"
require "AssistenteNPC/Engine/Fight"
require "AssistenteNPC/Engine/Runtime"
require "AssistenteNPC/Actions"
require "AssistenteNPC/Program"

AssistenteNPC.Brain = {}
local Brain = AssistenteNPC.Brain
local Config = AssistenteNPC.Config
local Util = AssistenteNPC.Util
local Bridge = AssistenteNPC.Bridge
local Tasks = AssistenteNPC.Tasks
local Registry = AssistenteNPC.Registry
local Body = AssistenteNPC.Body
local Runtime = AssistenteNPC.Runtime

local gameStartMs = nil
local lastScanMs = 0
local sessionReady = false
local missingSince = nil -- quando o assistente sumiu (ms, so nesta sessao)

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
    return Registry.data()
end

function Brain.assistantRecord()
    return Registry.get(Brain.getData().assistantRid)
end

--- Corpo do assistente, se estiver carregado perto do jogador.
function Brain.getNPC()
    return Runtime.bodyOf(Brain.getData().assistantRid)
end

--- Corpo do sobrevivente recrutavel, se estiver carregado.
function Brain.getStray()
    local stray = Brain.getData().stray
    local record = stray and Registry.get(stray.rid)
    if not record or record.role ~= "stray" then return nil end
    return Runtime.bodyOf(stray.rid)
end

--- Tem um assistente vivo e perto o bastante para receber ordens.
function Brain.isActive()
    return Brain.getNPC() ~= nil
end

--- Tem um assistente vivo (mesmo que longe/descarregado).
function Brain.isAlive()
    return Brain.getData().assistantRid ~= nil
end

function Brain.recordOf(npc)
    return Registry.get(Body.ridOf(npc))
end

-- ---------------------------------------------------------------------------
-- Inventario
-- ---------------------------------------------------------------------------

--- Itens que ele entrega ao jogador: tudo, menos a arma em uso e um machado.
function Brain.deliverableItems(npc)
    local keep = {}
    local weapon = npc:getPrimaryHandItem()
    if weapon then keep[weapon] = true end
    local best = Bridge.bestWeapon(npc)
    if best then keep[best] = true end
    local axe = Util.findAxe(npc:getInventory())
    if axe then keep[axe] = true end

    local result = {}
    local items = npc:getInventory():getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if not keep[item] then table.insert(result, item) end
    end
    return result
end

--- Muda quando entra/sai item ou quando a condicao de algum item muda.
local function inventorySignature(inventory)
    local parts = {}
    local items = inventory:getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        parts[#parts + 1] = item:getFullType() .. ":" .. tostring(item:getCondition())
    end
    return table.concat(parts, ",")
end

--- Guarda uma copia do inventario no registro quando ele muda.
local function syncInventory(npc, record)
    local md = npc:getModData()
    local signature = inventorySignature(npc:getInventory())
    if signature ~= md.anpcSig then
        md.anpcSig = signature
        record.items = Util.serializeInventory(npc:getInventory())
    end
end

local function giveStarterItems(npc)
    local inventory = npc:getInventory()
    for _, fullType in ipairs(Config.starterItems) do
        local ok, item = pcall(instanceItem, fullType)
        if ok and item then inventory:AddItem(item) end
    end
end

--- Chamado quando um corpo de NPC aparece (spawn novo ou jogo recarregado).
function Brain.onBodyLoaded(npc, record)
    local inventory = npc:getInventory()
    if inventory:getItems():size() == 0 and record.items and #record.items > 0 then
        Util.restoreInventory(inventory, record.items)
    end
    npc:getModData().anpcSig = inventorySignature(inventory)
    Bridge.equipBestWeapon(npc)
end

-- ---------------------------------------------------------------------------
-- Spawn
-- ---------------------------------------------------------------------------

--- Cria o corpo de um registro perto de (x, y, z). Devolve o corpo ou nil.
function Brain.spawnRecord(record, x, y, z, fresh)
    local square = Util.findFreeSquareNear(x, y, z, 2)
    if not square then return nil end
    local npc = Body.spawn(record, square:getX(), square:getY(), square:getZ())
    if not npc then return nil end
    Runtime.bind(record.rid, npc)
    if fresh then giveStarterItems(npc) end
    Brain.onBodyLoaded(npc, record)
    record.x, record.y, record.z = npc:getX(), npc:getY(), npc:getZ()
    return npc
end

local function spawnInitialAssistant(player, data)
    local record = Registry.create("assistant")
    local npc = Brain.spawnRecord(record, player:getX() + 1, player:getY() + 1, player:getZ(), true)
    if not npc then
        Registry.remove(record.rid)
        return false
    end
    data.assistantRid = record.rid
    Util.log("assistente inicial criado:", record.name, "em", npc:getX(), npc:getY(), npc:getZ())
    Bridge.say(npc, Util.text("IGUI_AssistenteNPC_SayHello"))
    return true
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
    local record = npc and Brain.recordOf(npc)
    if not record then return end

    if name == "wood" and not Brain.hasAxe() then
        Bridge.say(npc, Util.text("IGUI_AssistenteNPC_SayWoodNoAxe"))
        return
    end

    Bridge.clearTasks(npc)
    Tasks.setOrder(record, name, params)
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
-- Laco principal
-- ---------------------------------------------------------------------------

--- O assistente nao esta carregado: decide se deve recria-lo.
local function handleMissing(player, record, now)
    if player:getVehicle() then
        missingSince = nil
        return
    end
    missingSince = missingSince or now
    if now - missingSince < Config.relocateAfterMs then return end
    missingSince = nil

    local x, y, z
    if STATIONARY_ORDERS[record.order] then
        -- Esperando/vigiando: so recria no proprio posto, e so se voce estiver perto.
        if not record.x or Util.dist(player:getX(), player:getY(), record.x, record.y) > 40 then return end
        x, y, z = record.x, record.y, record.z
    else
        -- Ficou para tras: reaparece perto de voce com o mesmo nome, visual e itens.
        x, y, z = player:getX() + 1, player:getY() + 1, player:getZ()
    end
    if not Util.getSquare(x, y, z) then return end

    Util.log("assistente sumido, recriando em", x, y, z, "ordem", record.order)
    Registry.retireOutfit(record)
    Brain.spawnRecord(record, x, y, z, false)
end

local function update(player, data)
    local now = Util.now()

    if not sessionReady then
        sessionReady = true
        missingSince = nil
        if data.stray then
            data.stray.requestedAt = nil
            data.stray.lostSince = nil
        end
    end

    -- Assistente inicial (jogo novo ou mod adicionado a um save existente).
    if not data.initialized then
        if spawnInitialAssistant(player, data) then
            data.initialized = true
        end
        return
    end

    local record = Brain.assistantRecord()
    if record then
        local npc = Brain.getNPC()
        if npc then
            missingSince = nil
            record.x, record.y, record.z = npc:getX(), npc:getY(), npc:getZ()
            syncInventory(npc, record)
        elseif not record.dying then
            handleMissing(player, record, now)
        end
    end

    local stray = Brain.getStray()
    if stray then
        local strayRecord = Brain.recordOf(stray)
        if strayRecord then
            strayRecord.x, strayRecord.y, strayRecord.z = stray:getX(), stray:getY(), stray:getZ()
            syncInventory(stray, strayRecord)
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

    local ok, err = pcall(update, player, Brain.getData())
    if not ok then print("[AssistenteNPC] erro no gerenciador: " .. tostring(err)) end
end

local function onGameStart()
    gameStartMs = Util.now()
    lastScanMs = 0
    sessionReady = false
end

--- Recupera vida aos poucos quando nao ha zumbis por perto.
local function onEveryOneMinute()
    Registry.each(function(rid, record)
        if record.dying or (record.hp or Config.maxHp) >= Config.maxHp then return end
        local npc = Runtime.bodyOf(rid)
        if npc and not Util.nearestZombie(npc:getX(), npc:getY(), npc:getZ(), 8) then
            record.hp = math.min(Config.maxHp, record.hp + Config.hpRegenPerMinute)
        end
    end)
end

--- Registra a morte de um NPC (assistente ou sobrevivente).
function Brain.handleDeath(rid)
    local record = rid and Registry.get(rid)
    if not record then return end

    local data = Brain.getData()
    local hours = getGameTime():getWorldAgeHours()
    Runtime.unbind(rid)
    Registry.remove(rid)

    Util.log("NPC morreu:", record.role, record.name)
    if rid == data.assistantRid then
        data.assistantRid = nil
        data.deadAtHours = hours
        missingSince = nil
        Util.halo(getSpecificPlayer(0), Util.text("IGUI_AssistenteNPC_Died"), "bad")
    elseif data.stray and data.stray.rid == rid then
        -- O sobrevivente morreu antes de ser recrutado: outro aparecera mais tarde.
        data.stray = nil
        data.deadAtHours = hours
    end
end

local function onZombieDead(zombie)
    Brain.handleDeath(zombie:getModData().anpcRid)
end

Events.OnGameStart.Add(onGameStart)
Events.OnTick.Add(onTick)
Events.EveryOneMinute.Add(onEveryOneMinute)
Events.OnZombieDead.Add(onZombieDead)

return Brain
