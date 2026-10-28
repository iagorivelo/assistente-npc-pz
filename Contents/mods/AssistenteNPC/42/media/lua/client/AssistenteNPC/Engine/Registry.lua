-- AssistenteNPC - registro persistente dos NPCs (ModData "AssistenteNPC").
--
-- O corpo (IsoZombie) e descartavel: o jogo o recria ao carregar o save ou ao
-- recarregar a area. A verdade fica aqui:
--
--   data.records[rid] = {
--     rid, role ("assistant" | "stray"), name, look, hp,
--     outfitId,          identidade do corpo atual (ver Body.id)
--     x, y, z,           ultima posicao conhecida
--     items,             inventario serializado (Util.serializeInventory)
--     order, params, state,  ordem atual e progresso da tarefa
--   }
--   data.byOutfit[tostring(outfitId)] = rid
--   data.retired[tostring(outfitId)]  = hora (idade do mundo) em que o corpo
--                                       foi substituido; expira em 72h

require "AssistenteNPC/Config"
require "AssistenteNPC/Util"
require "AssistenteNPC/Engine/Look"

AssistenteNPC.Registry = {}
local Registry = AssistenteNPC.Registry
local Config = AssistenteNPC.Config
local Util = AssistenteNPC.Util
local Look = AssistenteNPC.Look

function Registry.data()
    local data = ModData.getOrCreate("AssistenteNPC")
    data.records = data.records or {}
    data.byOutfit = data.byOutfit or {}
    data.retired = data.retired or {}
    return data
end

function Registry.get(rid)
    if not rid then return nil end
    return Registry.data().records[rid]
end

local seq = 0

--- Cria um registro novo (ainda sem corpo).
function Registry.create(role)
    seq = seq + 1
    local rid = "anpc-" .. tostring(getTimestampMs()) .. "-" .. tostring(seq) .. "-" .. tostring(ZombRand(100000))
    local look = Look.random()
    local record = {
        rid = rid,
        role = role,
        name = Look.randomName(look.female),
        look = look,
        hp = Config.maxHp,
        items = {},
        order = role == "stray" and "stay" or "follow",
        params = {},
        state = {},
    }
    Registry.data().records[rid] = record
    return record
end

function Registry.remove(rid)
    local data = Registry.data()
    local record = data.records[rid]
    if not record then return end
    if record.outfitId then
        data.byOutfit[tostring(record.outfitId)] = nil
    end
    data.records[rid] = nil
end

--- Liga o registro ao corpo atual (atualiza o indice por outfitId).
function Registry.bindOutfit(record, outfitId)
    local data = Registry.data()
    if record.outfitId and record.outfitId ~= outfitId then
        data.byOutfit[tostring(record.outfitId)] = nil
    end
    record.outfitId = outfitId
    data.byOutfit[tostring(outfitId)] = record.rid
    data.retired[tostring(outfitId)] = nil
end

--- Marca o corpo atual como antigo (sera removido se reaparecer) e desliga.
function Registry.retireOutfit(record)
    if not record.outfitId then return end
    local data = Registry.data()
    local key = tostring(record.outfitId)
    data.byOutfit[key] = nil
    data.retired[key] = getGameTime():getWorldAgeHours()
    record.outfitId = nil
end

local RETIRED_TTL_HOURS = 72

function Registry.ridForOutfit(outfitId)
    return Registry.data().byOutfit[tostring(outfitId)]
end

function Registry.isRetired(outfitId)
    local retired = Registry.data().retired
    local key = tostring(outfitId)
    local at = retired[key]
    if not at then return false end
    if type(at) ~= "number" or getGameTime():getWorldAgeHours() - at > RETIRED_TTL_HOURS then
        retired[key] = nil
        return false
    end
    return true
end

function Registry.each(callback)
    for rid, record in pairs(Registry.data().records) do
        callback(rid, record)
    end
end

return Registry
