-- AssistenteNPC - combate.
--
--  * Golpe do NPC: quando um inimigo esta ao alcance da arma e ele esta de
--    frente, entra uma tarefa "Smack" (animacao de golpe + dano no momento
--    certo via zumbi:Hit).
--  * Zumbis contra o NPC: zumbis normais nao atacam outros "zumbis", entao
--    simulamos: os que estao mais perto do NPC do que do jogador vao ate ele e
--    mordem (animacao ANPCZombieBite + perda de vida).
--  * Vida: o corpo e invulneravel para o motor do jogo; a vida fica no
--    registro (record.hp). Ao zerar, o corpo morre de verdade e vira cadaver.

require "AssistenteNPC/Config"
require "AssistenteNPC/Util"
require "AssistenteNPC/Engine/Body"
require "AssistenteNPC/Engine/Executor"

AssistenteNPC.Fight = {}
local Fight = AssistenteNPC.Fight
local Config = AssistenteNPC.Config
local Util = AssistenteNPC.Util
local Executor = AssistenteNPC.Executor
local Actions = AssistenteNPC.Actions

local MELEE_CHECK_MS = 150
local ZOMBIE_CHECK_MS = 300
local CHASE_REPATH_MS = 2000

local bareHands = nil

--- Arma atual (ou maos nuas).
function Fight.weaponOf(npc)
    local item = npc:getPrimaryHandItem()
    if item and instanceof(item, "HandWeapon") and not item:isBroken() and not item:isRanged() then
        return item
    end
    if not bareHands then bareHands = instanceItem("Base.BareHands") end
    return bareHands
end

local function reachOf(item)
    local ok, range = pcall(function() return item:getMaxRange() end)
    if not ok or not range or range <= 0 then range = 1.0 end
    return range + Config.reachBonus
end

local ANIMS = {
    bare = { "ANPCAttackBare1", "ANPCAttackBare2" },
    oneHanded = { "ANPCAttack1H1", "ANPCAttack1H2" },
    twoHanded = { "ANPCAttack2H1", "ANPCAttack2H2" },
    knife = { "ANPCAttackKnife" },
    spear = { "ANPCAttackSpear" },
}

local function attackAnim(item)
    local list = ANIMS.oneHanded
    if not item or item:getFullType() == "Base.BareHands" then
        list = ANIMS.bare
    else
        local ok, weaponType = pcall(function() return WeaponType.getWeaponType(item) end)
        if ok and weaponType then
            if weaponType == WeaponType.KNIFE then list = ANIMS.knife
            elseif weaponType == WeaponType.SPEAR then list = ANIMS.spear
            elseif weaponType == WeaponType.UNARMED then list = ANIMS.bare
            elseif weaponType == WeaponType.TWO_HANDED or weaponType == WeaponType.HEAVY then list = ANIMS.twoHanded
            end
        elseif item:isTwoHandWeapon() then
            list = ANIMS.twoHanded
        end
    end
    return list[ZombRand(#list) + 1]
end

local function wearWeapon(npc, item)
    if item:getFullType() == "Base.BareHands" then return end
    local ok, chance = pcall(function() return item:getConditionLowerChance() end)
    if not ok or not chance or chance < 1 then chance = 10 end
    if ZombRand(chance * 2) == 0 then
        item:setCondition(math.max(0, item:getCondition() - 1))
        if item:isBroken() then
            npc:setPrimaryHandItem(nil)
            npc:resetEquippedHandsModels()
        end
    end
end

--- Aplica o golpe do NPC no alvo.
function Fight.applyHit(npc, item, target)
    if not Util.isLiveZombie(target) then return end
    if Util.distObj(npc, target) > reachOf(item) + 0.3 then return end
    local damage = item:getMaxDamage() * Config.damageMultiplier
    target:setHitFromBehind(npc:isBehind(target))
    target:setAttackedBy(npc)
    target:Hit(item, getCell():getFakeZombieForHit(), damage, false, 1, false)
    pcall(function() target:playSound(item:getZombieHitSound()) end)
    wearWeapon(npc, item)
end

--- Golpe corpo a corpo.
Actions.Smack = {
    onStart = function(npc, task)
        task.item = Fight.weaponOf(npc)
        task.anim = attackAnim(task.item)
        task.hitAt = task.time - 25
        npc:setBumpType(task.anim)
        npc:faceThisObject(task.target)
        pcall(function() npc:playSound(task.item:getSwingSound()) end)
        return true
    end,
    onWorking = function(npc, task)
        if Util.isLiveZombie(task.target) then npc:faceThisObject(task.target) end
        if not task.hit and task.time <= task.hitAt then
            task.hit = true
            Fight.applyHit(npc, task.item, task.target)
        end
        return task.hit and npc:getBumpType() ~= task.anim
    end,
    onComplete = function(npc, task) return true end,
}

-- ---------------------------------------------------------------------------
-- Vida e morte
-- ---------------------------------------------------------------------------

--- Ao morrer, o jogo esvazia o inventario do zumbi e so recria as roupas e os
--- itens marcados com addItemToSpawnAtDeath. Marcamos tudo que ele carrega.
local function keepItemsOnDeath(npc)
    npc:clearItemsToSpawnAtDeath()
    local items = npc:getInventory():getItems()
    for i = 0, items:size() - 1 do
        npc:addItemToSpawnAtDeath(items:get(i))
    end
end

function Fight.kill(npc, record)
    record.hp = 0
    record.dying = true
    Executor.clear(npc)
    pcall(keepItemsOnDeath, npc)
    pcall(function() npc:setInvulnerable(false) end)
    pcall(function() npc:setAvoidDamage(false) end)
    npc:setAttackedBy(getCell():getFakeZombieForHit())
    npc:setHealth(0)
    local died = pcall(function() npc:die() end)
    if not died then
        died = pcall(function() npc:Kill(getCell():getFakeZombieForHit()) end)
    end
    if not died then
        -- Nao conseguiu matar o corpo: remove e registra a morte mesmo assim,
        -- para nao travar o recrutamento.
        print("[AssistenteNPC] falha ao matar o corpo do NPC; removendo")
        local rid = AssistenteNPC.Body.ridOf(npc)
        AssistenteNPC.Body.despawn(npc)
        if AssistenteNPC.Brain then AssistenteNPC.Brain.handleDeath(rid) end
    end
end

function Fight.hurt(npc, record, amount)
    if record.dying then return end
    local before = record.hp or Config.maxHp
    record.hp = before - amount
    if record.hp <= 0 then
        Fight.kill(npc, record)
        return
    end
    if before >= Config.hurtWarningHp and record.hp < Config.hurtWarningHp then
        AssistenteNPC.Bridge.say(npc, Util.text("IGUI_AssistenteNPC_SayHurt"))
    end
    -- Reacao ao golpe (sem interromper um golpe dele em andamento).
    if not Executor.isBusyWith(npc, "Smack") then
        Executor.clear(npc)
        Executor.add(npc, { action = "Time", anim = "ANPCHitReact", time = 40 })
    end
end

-- ---------------------------------------------------------------------------
-- Atualizacao por corpo
-- ---------------------------------------------------------------------------

local function meleeUpdate(npc, md, now)
    if Executor.isBusyWith(npc, "Smack") then return end
    if md.anpcNextAttack and now < md.anpcNextAttack then return end
    local reach = reachOf(Fight.weaponOf(npc))
    local enemy = Util.nearestZombie(npc:getX(), npc:getY(), npc:getZ(), reach)
    if not enemy then return end
    if npc:isFacingObject(enemy, 0.5) then
        Executor.clear(npc)
        Executor.add(npc, { action = "Smack", target = enemy, time = 70 })
        md.anpcNextAttack = now + Config.attackCooldownMs
    else
        npc:faceThisObject(enemy)
    end
end

-- Zumbis nesses estados nao podem morder (caidos, levantando, ja mordendo...).
local ZOMBIE_BUSY_STATES = {
    bumped = true, onground = true, ["onground-ragdoll"] = true, climbfence = true,
    climbwindow = true, getup = true, ["getup-fromonback"] = true, ["getup-fromonfront"] = true,
    turnalerted = true, staggerback = true, ["staggerback-knockeddown"] = true,
    hitreaction = true, falldown = true,
}

local BITE_HIT_DELAY_MS = 450 -- momento da mordida na animacao Zombie_Bite

local pendingBites = {} -- rid -> lista de { zombie, at }

local function canBite(zombie)
    if ZOMBIE_BUSY_STATES[zombie:getActionStateName()] then return false end
    if zombie:isProne() or zombie:isCrawling() then return false end
    return true
end

--- Aplica as mordidas cujo momento de impacto ja passou (se o zumbi ainda esta perto).
local function resolveBites(npc, record, now)
    local list = pendingBites[record.rid]
    if not list or #list == 0 then return end
    local remaining, damage, hits = {}, 0, 0
    for _, bite in ipairs(list) do
        if now < bite.at then
            table.insert(remaining, bite)
        elseif Util.isLiveZombie(bite.zombie) and Util.distObj(bite.zombie, npc) <= Config.zombieBiteRange + 0.2 then
            hits = hits + 1
            damage = damage + Config.zombieBiteDamage + (bite.swarm and Config.zombieSwarmBonus or 0)
        end
    end
    pendingBites[record.rid] = remaining
    if hits > 0 then
        pcall(function() npc:playSound(ZombRand(3) == 0 and "ZombieBite" or "ZombieScratch") end)
        Fight.hurt(npc, record, damage)
    end
end

local function zombiesUpdate(npc, record, now)
    resolveBites(npc, record, now)
    if record.dying then return end

    local player = getSpecificPlayer(0)
    local list = Util.zombiesNear(npc:getX(), npc:getY(), npc:getZ(), Config.zombieAggroRadius)
    local npcSquare = npc:getSquare()
    local adjacent = 0
    local newBites = {}

    for _, entry in ipairs(list) do
        local zombie = entry.zombie
        local playerDist = player and Util.distObj(zombie, player) or math.huge
        -- So cuida dos zumbis que estao mais perto do NPC do que de voce.
        if entry.dist < playerDist then
            local zmd = zombie:getModData()
            if entry.dist > Config.zombieBiteRange then
                if (not zmd.anpcChaseAt or now - zmd.anpcChaseAt > CHASE_REPATH_MS) and zombie:CanSee(npc) then
                    zmd.anpcChaseAt = now
                    zombie:pathToCharacter(npc)
                end
            else
                adjacent = adjacent + 1
                local blocked = false
                pcall(function()
                    blocked = zombie:getSquare():isSomethingTo(npcSquare)
                end)
                if not blocked and canBite(zombie) then
                    if zombie:isFacingObject(npc, 0.4) then
                        if not zmd.anpcBiteAt or now - zmd.anpcBiteAt > Config.zombieBiteCooldownMs then
                            zmd.anpcBiteAt = now
                            zombie:setBumpType("ANPCZombieBite")
                            table.insert(newBites, { zombie = zombie, at = now + BITE_HIT_DELAY_MS })
                        end
                    else
                        zombie:faceThisObject(npc)
                    end
                end
            end
        end
    end

    if #newBites > 0 then
        local pending = pendingBites[record.rid] or {}
        for _, bite in ipairs(newBites) do
            bite.swarm = adjacent >= 3
            table.insert(pending, bite)
        end
        pendingBites[record.rid] = pending
    end
end

function Fight.update(npc, record)
    if record.dying then return end
    local md = npc:getModData()
    local now = Util.now()
    if not md.anpcMeleeAt or now - md.anpcMeleeAt >= MELEE_CHECK_MS then
        md.anpcMeleeAt = now
        meleeUpdate(npc, md, now)
    end
    if not md.anpcZombiesAt or now - md.anpcZombiesAt >= ZOMBIE_CHECK_MS then
        md.anpcZombiesAt = now
        zombiesUpdate(npc, record, now)
    end
end

return Fight
