-- AssistenteNPC - cursor que espera o jogador clicar num square do mapa.
-- Baseado no padrao do ISChopTreeCursor vanilla (ISBuildingObject + setDrag).
-- A classe e criada sob demanda para nao depender da ordem de carregamento
-- dos arquivos vanilla (ISBuildingObject).

require "AssistenteNPC/Util"

AssistenteNPC = AssistenteNPC or {}
AssistenteNPC.TargetCursor = {}
local TargetCursor = AssistenteNPC.TargetCursor

local CursorClass = nil

local function getCursorClass()
    if CursorClass then return CursorClass end

    CursorClass = ISBuildingObject:derive("AssistenteNPCTargetCursor")

    --- onPick(square) e chamado quando o jogador clica num square valido.
    function CursorClass:new(character, onPick)
        local o = {}
        setmetatable(o, self)
        self.__index = self
        o:init()
        o:setSprite("")
        o:setNorthSprite("")
        o.character = character
        o.player = character:getPlayerNum()
        o.noNeedHammer = true
        o.skipBuildAction = true
        o.onPick = onPick
        o.dragNilAfterPlace = true -- um clique so
        -- Sem isto o ISBuildingObject faz o JOGADOR andar ate o local antes de
        -- chamar create() (e nem chama se o local for inalcancavel).
        o.skipWalk2 = true
        return o
    end

    function CursorClass:isValid(square)
        return square ~= nil
    end

    function CursorClass:create(x, y, z, north, sprite)
        local square = getCell():getGridSquare(x, y, z)
        if square and self.onPick then
            self.onPick(square)
        end
    end

    function CursorClass:render(x, y, z, square)
        local color = self:isValid(square) and getCore():getGoodHighlitedColor() or getCore():getBadHighlitedColor()
        self:getFloorCursorSprite():RenderGhostTileColor(x, y, z, color:getR(), color:getG(), color:getB(), 0.8)
    end

    return CursorClass
end

--- Inicia a selecao de um square. Mostra a dica em texto flutuante.
function TargetCursor.start(playerObj, hintText, onPick)
    if hintText then
        AssistenteNPC.Util.halo(playerObj, hintText)
    end
    local cls = getCursorClass()
    getCell():setDrag(cls:new(playerObj, onPick), playerObj:getPlayerNum())
end

return TargetCursor
