-- AssistenteNPC - aparencia humana do NPC.
--
-- O corpo do NPC e um IsoZombie (unico tipo de NPC que o jogo deixa um mod
-- Lua controlar de forma estavel na Build 42). Aqui trocamos a pele de zumbi
-- por pele humana, limpamos sangue/sujeira/ferimentos e vestimos roupas.
-- A aparencia e um registro simples (salvo no ModData) para que o NPC possa
-- ser reconstruido igual ao recarregar o jogo.

require "AssistenteNPC/Util"

AssistenteNPC.Look = {}
local Look = AssistenteNPC.Look
local Util = AssistenteNPC.Util

-- Conjuntos de roupa, de dentro para fora (a ordem importa nas camadas).
local OUTFITS = {
    male = {
        { "Base.Briefs_White", "Base.Socks_Heavy", "Base.Trousers_Denim", "Base.Vest_DefaultTEXTURE",
          "Base.Shirt_Lumberjack", "Base.Gloves_LeatherGlovesBrown", "Base.Shoes_HikingBoots" },
        { "Base.Briefs_White", "Base.Socks_Long_Black", "Base.Trousers_Black", "Base.Tshirt_BluesCountry",
          "Base.Jacket_Black", "Base.Gloves_LeatherGlovesBlack", "Base.Shoes_BlackBoots" },
        { "Base.Briefs_White", "Base.Socks_Ankle_White", "Base.Shorts_LongDenim", "Base.Tshirt_HipHop",
          "Base.Shoes_Brown" },
    },
    female = {
        { "Base.Socks_Ankle", "Base.Trousers_JeanBaggy", "Base.Tshirt_DefaultDECAL_TINT",
          "Base.Gloves_FingerlessLeatherGloves_Brown", "Base.Shoes_RedTrainers" },
        { "Base.Socks_Long_Black", "Base.Trousers_Black", "Base.Tshirt_BluesCountry",
          "Base.Jacket_Black", "Base.Shoes_BlackBoots" },
        { "Base.Socks_Ankle_White", "Base.Trousers_Denim", "Base.Shirt_Lumberjack", "Base.Shoes_Brown" },
    },
}

local FALLBACK_NAMES = {
    male = { "Joe", "Mike", "Frank", "Dave", "Tom", "Bill" },
    female = { "Kate", "Anna", "Mary", "Lucy", "Sarah", "Jane" },
}

local function pick(list)
    return list[ZombRand(#list) + 1]
end

local function randomHair(female)
    local ok, style = pcall(function()
        local all = getAllHairStyles(female)
        local instance = getHairStylesInstance()
        local choices = {}
        for i = 0, all:size() - 1 do
            local id = all:get(i)
            local def = female and instance:FindFemaleStyle(id) or instance:FindMaleStyle(id)
            if def and not def:isNoChoose() then table.insert(choices, id) end
        end
        return #choices > 0 and pick(choices) or nil
    end)
    return ok and style or nil
end

local function randomBeard()
    local ok, style = pcall(function()
        local all = getAllBeardStyles()
        if all:size() == 0 then return nil end
        return all:get(ZombRand(all:size()))
    end)
    return ok and style or nil
end

local function randomHairColor(female)
    local ok, color = pcall(function()
        local desc = SurvivorFactory.CreateSurvivor(SurvivorType.Neutral, female)
        local colors = desc:getCommonHairColor()
        local c = colors:get(ZombRand(colors:size()))
        return { r = c:getRedFloat(), g = c:getGreenFloat(), b = c:getBlueFloat() }
    end)
    return ok and color or { r = 0.25, g = 0.17, b = 0.1 }
end

--- Nome aleatorio usando os nomes do proprio jogo.
function Look.randomName(female)
    local ok, name = pcall(function()
        local desc = SurvivorFactory.CreateSurvivor(SurvivorType.Neutral, female)
        return desc:getForename()
    end)
    if ok and name and name ~= "" then return name end
    return pick(female and FALLBACK_NAMES.female or FALLBACK_NAMES.male)
end

--- Aparencia aleatoria (registro salvavel).
function Look.random()
    local female = ZombRand(2) == 0
    return {
        female = female,
        skin = ZombRand(5) + 1,
        hair = randomHair(female),
        beard = (not female and ZombRand(2) == 0) and randomBeard() or nil,
        hairColor = randomHairColor(female),
        clothes = pick(female and OUTFITS.female or OUTFITS.male),
    }
end

local function skinTexture(look)
    if look.female then
        return "FemaleBody0" .. tostring(look.skin)
    end
    return "MaleBody0" .. tostring(look.skin) .. "a"
end

--- O corpo ja esta com a aparencia humana? (o jogo recria a de zumbi ao recarregar)
function Look.isApplied(zombie)
    local visual = zombie:getHumanVisual()
    local skin = visual and visual:getSkinTexture()
    return skin ~= nil and (skin:find("^MaleBody") ~= nil or skin:find("^FemaleBody") ~= nil)
end

local function cleanBody(zombie)
    local visual = zombie:getHumanVisual()
    pcall(function() visual:removeBlood() end)
    pcall(function() visual:removeDirt() end)
    pcall(function()
        local maxIndex = BloodBodyPartType.MAX:index()
        for i = 0, maxIndex - 1 do
            local part = BloodBodyPartType.FromIndex(i)
            visual:setBlood(part, 0)
            visual:setDirt(part, 0)
        end
    end)
    -- Remove ferimentos/mordidas de zumbi desenhados no corpo.
    pcall(function() visual:getBodyVisuals():clear() end)
end

local function applyBody(zombie, look)
    local visual = zombie:getHumanVisual()
    visual:setSkinTextureName(skinTexture(look))
    if look.hair then pcall(function() visual:setHairModel(look.hair) end) end
    if look.beard then
        pcall(function() visual:setBeardModel(look.beard) end)
    elseif not look.female then
        pcall(function() visual:setBeardModel("") end)
    end
    if look.hairColor then
        pcall(function()
            local color = ImmutableColor.new(look.hairColor.r, look.hairColor.g, look.hairColor.b, 1)
            visual:setHairColor(color)
            visual:setBeardColor(color)
        end)
    end
end

local function applyClothes(zombie, look)
    pcall(function() zombie:getWornItems():clear() end)
    local itemVisuals = zombie:getItemVisuals()
    itemVisuals:clear()
    for _, fullType in ipairs(look.clothes or {}) do
        local ok, item = pcall(instanceItem, fullType)
        if ok and item then
            local itemVisual = ItemVisual.new()
            itemVisual:setItemType(fullType)
            itemVisual:setClothingItemName(fullType)
            itemVisuals:add(itemVisual)
        else
            Util.log("roupa nao encontrada:", fullType)
        end
    end
end

--- Aplica a aparencia completa ao corpo.
function Look.apply(zombie, look)
    zombie:setFemaleEtc(look.female)
    cleanBody(zombie)
    applyBody(zombie, look)
    applyClothes(zombie, look)
    zombie:resetModel()
end

return Look
