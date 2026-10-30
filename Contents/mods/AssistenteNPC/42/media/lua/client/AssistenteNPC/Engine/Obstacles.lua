-- AssistenteNPC - portas, janelas e cercas no caminho, e NPC travado.
--
-- O jogo calcula o caminho do corpo (um IsoZombie) como o de um zumbi: ele
-- passa por portas fechadas, janelas e cercas baixas, porque zumbis quebram
-- ou pulam essas coisas. Sozinho, o NPC so andaria contra a parede. Durante
-- uma tarefa Move, quando ele chega na borda do tile e o proximo tile esta
-- atras de uma dessas coisas:
--   * porta fechada: abre (trancada ou com barricada: bloqueado);
--   * janela fechada: abre (trancada ou com barricada: bloqueado);
--   * janela aberta ou quebrada, ou so a moldura: pula pela janela;
--   * cerca baixa: pula a cerca.
--
-- Se mesmo assim ele nao sai do lugar por alguns segundos enquanto segue o
-- jogador, reaparece perto dele (Obstacles.unstick).

require "AssistenteNPC/Util"

AssistenteNPC.Obstacles = {}
local Obstacles = AssistenteNPC.Obstacles
local Util = AssistenteNPC.Util

local EDGE_DIST = 0.45 -- a partir de quanto perto da borda do tile olhamos o vizinho

Obstacles.OK = "ok"           -- nada no caminho
Obstacles.BUSY = "busy"       -- abrindo ou pulando algo; espere
Obstacles.BLOCKED = "blocked" -- nao da para passar por aqui

local CLIMB_STATES = { climbfence = true, climbwindow = true }

function Obstacles.isClimbing(zombie)
    return CLIMB_STATES[zombie:getActionStateName()] == true
end

--- Proximo square na direcao em que o NPC anda, se ele esta na borda do atual.
--- Devolve (square atual, proximo square, direcao) ou nil.
local function nextSquare(zombie)
    local current = zombie:getCurrentSquare()
    if not current then return nil end
    local forward = zombie:getForwardDirection()
    local dx, dy = forward:getX(), forward:getY()
    local x, y = zombie:getX(), zombie:getY()
    local cx, cy = current:getX(), current:getY()

    local nx, ny, dir = cx, cy, nil
    if math.abs(dx) >= math.abs(dy) then
        if dx > 0 and cx + 1 - x <= EDGE_DIST then nx, dir = cx + 1, IsoDirections.E
        elseif dx < 0 and x - cx <= EDGE_DIST then nx, dir = cx - 1, IsoDirections.W end
    else
        if dy > 0 and cy + 1 - y <= EDGE_DIST then ny, dir = cy + 1, IsoDirections.S
        elseif dy < 0 and y - cy <= EDGE_DIST then ny, dir = cy - 1, IsoDirections.N end
    end
    if not dir then return nil end
    local next = getCell():getGridSquare(nx, ny, current:getZ())
    if not next then return nil end
    return current, next, dir
end

local function isLocked(obj)
    local ok, locked = pcall(function() return obj:isLocked() or obj:isLockedByKey() end)
    return ok and locked == true
end

local function isBarricaded(obj)
    local ok, barricaded = pcall(function() return obj:isBarricaded() end)
    return ok and barricaded == true
end

local function openDoor(zombie, door)
    local ok = pcall(function() door:ToggleDoor(zombie) end)
    if not ok or not door:IsOpen() then
        pcall(function()
            door:ToggleDoorSilent()
            door:getSquare():RecalcProperties()
            door:getSquare():RecalcAllWithNeighbours(true)
        end)
    end
    return door:IsOpen()
end

local function handleDoor(zombie, door)
    if door:IsOpen() then return Obstacles.OK end
    if isBarricaded(door) or isLocked(door) then return Obstacles.BLOCKED end
    zombie:faceThisObject(door)
    if openDoor(zombie, door) then return Obstacles.BUSY end
    return Obstacles.BLOCKED
end

local function handleWindow(zombie, window)
    if isBarricaded(window) then return Obstacles.BLOCKED end
    local passable = window:IsOpen() or window:isSmashed() or window:isDestroyed()
    if not passable then
        if isLocked(window) or window:isPermaLocked() then return Obstacles.BLOCKED end
        zombie:faceThisObject(window)
        pcall(function() window:ToggleWindow(zombie) end)
        if not window:IsOpen() then return Obstacles.BLOCKED end
        return Obstacles.BUSY
    end
    if not window:canClimbThrough(zombie) then return Obstacles.BLOCKED end
    zombie:climbThroughWindow(window)
    return Obstacles.BUSY
end

--- Olha o que ha entre o tile atual e o proximo e reage.
function Obstacles.check(zombie)
    if Obstacles.isClimbing(zombie) then return Obstacles.BUSY end
    local current, next, dir = nextSquare(zombie)
    if not current then return Obstacles.OK end

    local door = current:getDoorTo(next)
    if door then return handleDoor(zombie, door) end

    -- Janelas e cercas: so quando ele de fato esbarrou (o caminho passa por
    -- ali), para nao abrir/pular algo so por andar rente a parede.
    local collided = zombie:isCollidedThisFrame() or zombie:isCollided()
    if not collided then return Obstacles.OK end

    local window = current:getWindowTo(next)
    if window then return handleWindow(zombie, window) end

    local frame = current:getWindowFrameTo(next)
    if frame then
        zombie:climbThroughWindowFrame(frame)
        return Obstacles.BUSY
    end

    if current:isHoppableTo(next) then
        zombie:climbOverFence(dir)
        return Obstacles.BUSY
    end

    return Obstacles.OK
end

-- ---------------------------------------------------------------------------
-- NPC travado
-- ---------------------------------------------------------------------------

--- Square livre perto do jogador, no mesmo comodo (ou ao ar livre, se ele
--- estiver ao ar livre), para nao reaparecer do outro lado de uma parede.
local function squareNearPlayer(player)
    local playerSq = player:getCurrentSquare()
    if not playerSq then return nil end
    local room = playerSq:getRoom()
    local best, bestDist = nil, math.huge
    Util.forEachSquare(player:getX(), player:getY(), player:getZ(), 3, function(sq)
        if sq ~= playerSq and sq:isFree(false) and sq:getRoom() == room then
            local d = Util.distToSquare(player, sq)
            -- Prefere ~2 tiles de distancia: nem colado, nem longe.
            local score = math.abs(d - 2)
            if score < bestDist then best, bestDist = sq, score end
        end
    end)
    return best
end

--- Coloca o NPC num square (cancelando o caminho atual).
function Obstacles.teleport(zombie, square)
    local pf = zombie:getPathFindBehavior2()
    pcall(function()
        pf:cancel()
        pf:reset()
    end)
    zombie:setPath2(nil)
    local x, y, z = square:getX() + 0.5, square:getY() + 0.5, square:getZ()
    zombie:setForceX(x)
    zombie:setForceY(y)
    zombie:setZ(z)
    zombie:setLastZ(z)
    zombie:ensureOnTile()
end

--- Tira o NPC de onde ele travou, levando-o para perto do jogador.
function Obstacles.unstick(zombie, player)
    local square = squareNearPlayer(player)
    if not square then return false end
    Util.log("travado; reaparecendo perto do jogador")
    Obstacles.teleport(zombie, square)
    zombie:faceThisObject(player)
    return true
end

return Obstacles
