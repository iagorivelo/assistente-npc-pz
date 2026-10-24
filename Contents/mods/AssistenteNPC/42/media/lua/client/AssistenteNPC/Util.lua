-- AssistenteNPC - funcoes utilitarias (mundo, distancia, busca de objetos).

require "AssistenteNPC/Config"

AssistenteNPC.Util = {}
local Util = AssistenteNPC.Util
local Config = AssistenteNPC.Config

function Util.log(...)
    if not Config.debug then return end
    local parts = {}
    for i = 1, select("#", ...) do
        parts[#parts + 1] = tostring(select(i, ...))
    end
    print("[AssistenteNPC] " .. table.concat(parts, " "))
end

function Util.now()
    return getTimestampMs()
end

--- Texto traduzido com fallback (evita mostrar a chave crua se faltar traducao).
function Util.text(key, ...)
    local result = getText(key, ...)
    if result == nil or result == key then
        return key
    end
    return result
end

function Util.dist(x1, y1, x2, y2)
    local dx, dy = x1 - x2, y1 - y2
    return math.sqrt(dx * dx + dy * dy)
end

function Util.distObj(a, b)
    return Util.dist(a:getX(), a:getY(), b:getX(), b:getY())
end

function Util.distToSquare(obj, square)
    return Util.dist(obj:getX(), obj:getY(), square:getX() + 0.5, square:getY() + 0.5)
end

function Util.getSquare(x, y, z)
    return getCell():getGridSquare(math.floor(x), math.floor(y), math.floor(z or 0))
end

--- Percorre todos os squares carregados num raio quadrado; callback(square) pode
--- retornar true para interromper a busca.
function Util.forEachSquare(cx, cy, cz, radius, callback)
    local cell = getCell()
    cx, cy, cz = math.floor(cx), math.floor(cy), math.floor(cz or 0)
    for x = cx - radius, cx + radius do
        for y = cy - radius, cy + radius do
            local sq = cell:getGridSquare(x, y, cz)
            if sq and callback(sq) then return end
        end
    end
end

--- Square livre (sem parede/solido) mais proximo de um ponto, ate um raio.
function Util.findFreeSquareNear(x, y, z, maxRadius)
    maxRadius = maxRadius or 3
    local best, bestDist = nil, math.huge
    Util.forEachSquare(x, y, z, maxRadius, function(sq)
        if sq:isFree(false) then
            local d = Util.dist(x, y, sq:getX() + 0.5, sq:getY() + 0.5)
            if d < bestDist then
                best, bestDist = sq, d
            end
        end
    end)
    return best
end

-- ---------------------------------------------------------------------------
-- Zumbis
-- ---------------------------------------------------------------------------

--- Inimigo vivo: zumbi comum ou bandido hostil (NPCs do Bandits tambem sao IsoZombie).
function Util.isLiveZombie(obj)
    if obj == nil or not instanceof(obj, "IsoZombie") or obj:isDead() then return false end
    if obj:getVariableBoolean("Bandit") then
        local brain = obj:getModData().brain
        -- O proprio assistente nunca e inimigo (mesmo no instante em que o
        -- Bandits o marca como hostil por fogo amigo, antes de corrigirmos).
        if brain and brain.assistente then return false end
        return Bandit ~= nil and Bandit.IsHostile(obj) == true
    end
    return true
end

--- Lista de zumbis vivos dentro de um raio de (x, y).
function Util.zombiesNear(x, y, z, radius)
    local result = {}
    local list = getCell():getZombieList()
    for i = 0, list:size() - 1 do
        local zed = list:get(i)
        if Util.isLiveZombie(zed) and math.abs(zed:getZ() - (z or 0)) < 1 then
            local d = Util.dist(x, y, zed:getX(), zed:getY())
            if d <= radius then
                table.insert(result, { zombie = zed, dist = d })
            end
        end
    end
    table.sort(result, function(a, b) return a.dist < b.dist end)
    return result
end

function Util.nearestZombie(x, y, z, radius)
    local list = Util.zombiesNear(x, y, z, radius)
    if list[1] then return list[1].zombie, list[1].dist end
    return nil, nil
end

-- ---------------------------------------------------------------------------
-- Corpos
-- ---------------------------------------------------------------------------

function Util.deadBodiesOnSquare(square)
    local result = {}
    local bodies = square:getDeadBodys()
    if bodies then
        for i = 0, bodies:size() - 1 do
            table.insert(result, bodies:get(i))
        end
    end
    return result
end

-- ---------------------------------------------------------------------------
-- Arvores e toras
-- ---------------------------------------------------------------------------

function Util.treeOnSquare(square)
    local tree = square:getTree()
    if tree and instanceof(tree, "IsoTree") then return tree end
    return nil
end

function Util.isLogItem(item)
    return item ~= nil and item:getFullType() == "Base.Log"
end

--- Retorna a lista de IsoWorldInventoryObject com toras num square.
function Util.logsOnSquare(square)
    local result = {}
    local objects = square:getWorldObjects()
    if objects then
        for i = 0, objects:size() - 1 do
            local wo = objects:get(i)
            if wo and Util.isLogItem(wo:getItem()) then
                table.insert(result, wo)
            end
        end
    end
    return result
end

function Util.isAxe(item)
    if not item or not instanceof(item, "HandWeapon") then return false end
    if item:isBroken() then return false end
    -- B42.20+: tags sao um enum (ItemTag.CHOP_TREE). Versoes anteriores usavam string.
    if ItemTag and ItemTag.CHOP_TREE then
        local ok, hasTag = pcall(function() return item:hasTag(ItemTag.CHOP_TREE) end)
        if ok and hasTag then return true end
    end
    local ok, hasTag = pcall(function() return item:hasTag("ChopTree") end)
    if ok and hasTag then return true end
    local okCat, cats = pcall(function() return item:getCategories() end)
    if okCat and cats and cats:contains("Axe") then return true end
    return string.find(string.lower(item:getType()), "axe", 1, true) ~= nil
        and not string.find(string.lower(item:getType()), "pickaxe", 1, true)
end

function Util.findAxe(inventory)
    if not inventory then return nil end
    local items = inventory:getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if Util.isAxe(item) then return item end
    end
    return nil
end

-- Cache "fullType -> e machado?" para armas do brain do Bandits (que sao so nomes).
local axeTypeCache = {}

function Util.isAxeType(fullType)
    if not fullType then return false end
    if axeTypeCache[fullType] == nil then
        local ok, item = pcall(instanceItem, fullType)
        axeTypeCache[fullType] = ok and item ~= nil and Util.isAxe(item) or false
    end
    return axeTypeCache[fullType]
end

-- ---------------------------------------------------------------------------
-- Inventario
-- ---------------------------------------------------------------------------

function Util.countType(inventory, fullType)
    local count = 0
    local items = inventory:getItems()
    for i = 0, items:size() - 1 do
        if items:get(i):getFullType() == fullType then count = count + 1 end
    end
    return count
end

function Util.inventoryWeight(inventory)
    local ok, weight = pcall(function() return inventory:getCapacityWeight() end)
    if ok and weight then return weight end
    local total = 0
    local items = inventory:getItems()
    for i = 0, items:size() - 1 do
        total = total + items:get(i):getActualWeight()
    end
    return total
end

--- Inventario -> lista de registros simples (salvavel em ModData).
--- Guarda tipo, condicao e idade (frescor de comida) de cada item.
function Util.serializeInventory(inventory)
    local list = {}
    local items = inventory:getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        local record = { t = item:getFullType() }
        pcall(function() record.c = item:getCondition() end)
        if instanceof(item, "Food") then
            pcall(function() record.a = item:getAge() end)
        end
        table.insert(list, record)
    end
    return list
end

--- Recria no inventario os itens de Util.serializeInventory.
function Util.restoreInventory(inventory, list)
    for _, record in ipairs(list) do
        -- Aceita tambem o formato antigo (so a string do tipo).
        local fullType = type(record) == "table" and record.t or record
        local ok, item = pcall(instanceItem, fullType)
        if ok and item then
            if type(record) == "table" then
                if record.c then pcall(function() item:setCondition(record.c) end) end
                if record.a then pcall(function() item:setAge(record.a) end) end
            end
            inventory:AddItem(item)
        end
    end
    inventory:setDrawDirty(true)
end

--- Itens que o assistente entrega ao jogador (tudo menos o machado, que ele usa).
function Util.deliverableItems(inventory)
    local result = {}
    local keptAxe = false
    local items = inventory:getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if not keptAxe and Util.isAxe(item) then
            keptAxe = true
        else
            table.insert(result, item)
        end
    end
    return result
end

-- ---------------------------------------------------------------------------
-- Direcao (para a dica "voce ouve alguem gritando ao norte")
-- ---------------------------------------------------------------------------

local TAN_22_5 = 0.41421356

--- Direcao cardinal de (fromX, fromY) ate (toX, toY). No PZ, +x = leste e +y = sul.
function Util.directionKey(fromX, fromY, toX, toY)
    local dx, dy = toX - fromX, toY - fromY
    local ns = dy < 0 and "N" or "S"
    local ew = dx > 0 and "E" or "W"
    local adx, ady = math.abs(dx), math.abs(dy)
    local dir
    if ady <= adx * TAN_22_5 then
        dir = ew
    elseif adx <= ady * TAN_22_5 then
        dir = ns
    else
        dir = ns .. ew
    end
    return "IGUI_AssistenteNPC_Dir_" .. dir
end

-- ---------------------------------------------------------------------------
-- Texto flutuante sobre o jogador
-- ---------------------------------------------------------------------------

--- kind: "good" (verde), "bad" (vermelho) ou nil (cor r, g, b; padrao cinza claro).
function Util.halo(player, text, kind, r, g, b)
    if not player or not text then return end
    if kind == "bad" then
        HaloTextHelper.addBadText(player, text)
        return
    elseif kind == "good" then
        HaloTextHelper.addGoodText(player, text)
        return
    end
    r, g, b = r or 220, g or 220, b or 220
    -- A assinatura de addText mudou entre versoes; tenta as conhecidas.
    if pcall(HaloTextHelper.addText, player, text, "", r, g, b) then return end
    if pcall(HaloTextHelper.addText, player, text, r, g, b) then return end
    HaloTextHelper.addGoodText(player, text)
end

return Util
