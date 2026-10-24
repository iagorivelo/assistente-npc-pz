-- AssistenteNPC - varre uma area e monta um relatorio (usado por "Analisar area").

require "AssistenteNPC/Util"
require "AssistenteNPC/LootFilter"

AssistenteNPC.Scanner = {}
local Scanner = AssistenteNPC.Scanner
local Util = AssistenteNPC.Util
local LootFilter = AssistenteNPC.LootFilter

local DANGER_ZOMBIES = 5
local MAX_HIGHLIGHTS = 3

-- Itens que merecem destaque no relatorio (ordem = prioridade).
local function highlightScore(item)
    if instanceof(item, "HandWeapon") and item:isRanged() then return 4 end
    local cat = item:getDisplayCategory()
    if cat == "Ammo" then return 3 end
    if cat == "FirstAid" then return 2 end
    if instanceof(item, "HandWeapon") and not item:isBroken() then return 1 end
    return 0
end

local function considerItems(report, container)
    if not container then return 0 end
    local items = container:getItems()
    local count = items:size()
    for i = 0, count - 1 do
        local item = items:get(i)
        local score = highlightScore(item)
        if score > 0 then
            table.insert(report.candidates, { name = item:getDisplayName(), score = score })
        end
    end
    return count
end

--- Varre um raio em volta de (x, y, z). Retorna uma tabela com contagens.
function Scanner.scanArea(x, y, z, radius)
    local report = {
        zombies = 0,
        bodies = 0,
        bodiesWithLoot = 0,
        trees = 0,
        containersWithItems = 0,
        groundItems = 0,
        candidates = {},
        highlights = {},
    }

    report.zombies = #Util.zombiesNear(x, y, z, radius)

    Util.forEachSquare(x, y, z, radius, function(sq)
        if Util.treeOnSquare(sq) then
            report.trees = report.trees + 1
        end

        for _, body in ipairs(Util.deadBodiesOnSquare(sq)) do
            report.bodies = report.bodies + 1
            local container = body:getContainer()
            if #LootFilter.collectUseful(container) > 0 then
                report.bodiesWithLoot = report.bodiesWithLoot + 1
            end
            considerItems(report, container)
        end

        local worldObjects = sq:getWorldObjects()
        if worldObjects then
            for i = 0, worldObjects:size() - 1 do
                local item = worldObjects:get(i):getItem()
                if item then
                    report.groundItems = report.groundItems + 1
                    local score = highlightScore(item)
                    if score > 0 then
                        table.insert(report.candidates, { name = item:getDisplayName(), score = score })
                    end
                end
            end
        end

        local objects = sq:getObjects()
        for i = 0, objects:size() - 1 do
            local obj = objects:get(i)
            for c = 0, obj:getContainerCount() - 1 do
                local container = obj:getContainerByIndex(c)
                if container and considerItems(report, container) > 0 then
                    report.containersWithItems = report.containersWithItems + 1
                end
            end
        end
    end)

    table.sort(report.candidates, function(a, b) return a.score > b.score end)
    local seen = {}
    for _, cand in ipairs(report.candidates) do
        if not seen[cand.name] then
            seen[cand.name] = true
            table.insert(report.highlights, cand.name)
            if #report.highlights >= MAX_HIGHLIGHTS then break end
        end
    end
    report.candidates = nil

    report.dangerous = report.zombies >= DANGER_ZOMBIES
    return report
end

--- Converte o relatorio em linhas de texto traduzidas.
function Scanner.reportLines(report)
    local lines = {}
    table.insert(lines, Util.text(report.dangerous and "IGUI_AssistenteNPC_SayAnalyzeDanger" or "IGUI_AssistenteNPC_SayAnalyzeSafe"))
    table.insert(lines, Util.text("IGUI_AssistenteNPC_ReportZombies", tostring(report.zombies)))
    table.insert(lines, Util.text("IGUI_AssistenteNPC_ReportBodies", tostring(report.bodies), tostring(report.bodiesWithLoot)))
    table.insert(lines, Util.text("IGUI_AssistenteNPC_ReportContainers", tostring(report.containersWithItems)))
    table.insert(lines, Util.text("IGUI_AssistenteNPC_ReportItems", tostring(report.groundItems)))
    table.insert(lines, Util.text("IGUI_AssistenteNPC_ReportTrees", tostring(report.trees)))
    if #report.highlights > 0 then
        table.insert(lines, Util.text("IGUI_AssistenteNPC_ReportHighlights", table.concat(report.highlights, ", ")))
    end
    return lines
end

return Scanner
