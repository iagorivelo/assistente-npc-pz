-- AssistenteNPC - decide quais itens valem a pena pegar de um corpo.
-- Regra: armas, comida, remedio, municao e ferramentas. Roupa e lixo ficam.

require "AssistenteNPC/Config"

AssistenteNPC.LootFilter = {}
local LootFilter = AssistenteNPC.LootFilter

-- DisplayCategory (campo dos scripts de item) considerados uteis.
local USEFUL_DISPLAY_CATEGORIES = {
    Ammo = true,
    FirstAid = true,
    Food = true,
    Tool = true,
    ToolWeapon = true,
    Weapon = true,
    WeaponPart = true,
    Gardening = false,
    Cooking = false,
}

-- Itens especificos que sempre valem a pena, mesmo fora das categorias.
local ALWAYS_TAKE = {
    ["Base.Pills"] = true,
    ["Base.PillsAntiDep"] = true,
    ["Base.PillsBeta"] = true,
    ["Base.PillsSleepingTablets"] = true,
    ["Base.Antibiotics"] = true,
    ["Base.Bandage"] = true,
    ["Base.Bandaid"] = true,
    ["Base.AlcoholWipes"] = true,
    ["Base.Disinfectant"] = true,
    ["Base.Lighter"] = true,
    ["Base.Matches"] = true,
}

local function safeCall(obj, method)
    if not obj or not obj[method] then return nil end
    local ok, result = pcall(obj[method], obj)
    if ok then return result end
    return nil
end

--- Retorna true se o item deve ser pego pelo assistente.
function LootFilter.isUseful(item)
    if not item then return false end

    local fullType = safeCall(item, "getFullType")
    if fullType and ALWAYS_TAKE[fullType] then return true end

    -- Chaves (de carro ou casa) que zumbis carregam sao muito uteis.
    if instanceof(item, "Key") then return true end

    if instanceof(item, "HandWeapon") then
        if safeCall(item, "isBroken") then return false end
        return true
    end

    if instanceof(item, "Food") then
        -- Comida podre ou queimada nao vale o peso.
        if safeCall(item, "isRotten") then return false end
        if safeCall(item, "isBurnt") then return false end
        return true
    end

    if instanceof(item, "Clothing") then return false end

    local displayCategory = safeCall(item, "getDisplayCategory")
    if displayCategory and USEFUL_DISPLAY_CATEGORIES[displayCategory] then
        return true
    end

    return false
end

--- Lista os itens uteis de um container (ex.: inventario de um corpo).
function LootFilter.collectUseful(container)
    local result = {}
    if not container then return result end
    local items = container:getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if LootFilter.isUseful(item) then
            table.insert(result, item)
        end
    end
    return result
end

return LootFilter
