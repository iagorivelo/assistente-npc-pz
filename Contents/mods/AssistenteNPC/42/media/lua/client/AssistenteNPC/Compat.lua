-- AssistenteNPC - compatibilidade com tratadores do jogo que supoem jogador.
--
-- Trocar a arma na mao do NPC dispara OnEquipPrimary com o corpo dele (um
-- IsoZombie). O tratador de pesca do jogo chama getPlayerNum() nesse
-- personagem e da erro. Filtramos: ele so roda para jogadores.

local patched = false

local function patchFishing()
    if patched then return end
    if not (Fishing and Fishing.Handler and Fishing.Handler.onEquipPrimary) then return end
    patched = true
    local original = Fishing.Handler.onEquipPrimary
    Events.OnEquipPrimary.Remove(original)
    Fishing.Handler.onEquipPrimary = function(character, item)
        if instanceof(character, "IsoPlayer") then
            return original(character, item)
        end
    end
    Events.OnEquipPrimary.Add(Fishing.Handler.onEquipPrimary)
end

Events.OnGameStart.Add(patchFishing)
