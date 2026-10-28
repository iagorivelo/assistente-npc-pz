-- AssistenteNPC - estado de ordens compartilhado pelas tarefas.
--
-- As tarefas recebem o registro do NPC (Engine/Registry.lua, salvo no
-- ModData). Campos usados aqui:
--   role   = "assistant" | "stray"
--   order  = "follow" | "stay" | "loot" | "wood" | "guard" | "analyze" | "deliver"
--   params = parametros da ordem (ex.: posicao do posto de vigia)
--   state  = progresso interno da tarefa (zerado a cada nova ordem)

require "AssistenteNPC/Config"

AssistenteNPC.Tasks = AssistenteNPC.Tasks or {}
local Tasks = AssistenteNPC.Tasks
local Config = AssistenteNPC.Config

function Tasks.setOrder(st, order, params)
    st.order = order
    st.params = params or {}
    st.state = {}
end

--- Registra mais uma tentativa de andar ate um alvo, a distancia `dist`.
--- So conta como tentativa falha quando ele nao chegou mais perto. Devolve
--- false se falhou vezes demais (alvo inalcancavel); nesse caso o alvo vai
--- para a lista de ignorados.
function Tasks.tryTarget(st, key, dist)
    st.state.skip = st.state.skip or {}
    if st.state.target ~= key then
        st.state.target = key
        st.state.attempts = 0
        st.state.bestDist = math.huge
    end
    if dist < st.state.bestDist - 0.5 then
        st.state.bestDist = dist
    else
        st.state.attempts = st.state.attempts + 1
    end
    if st.state.attempts > Config.maxAttempts then
        st.state.skip[key] = true
        st.state.target = nil
        return false
    end
    return true
end

function Tasks.isSkipped(st, key)
    return st.state.skip ~= nil and st.state.skip[key] == true
end

function Tasks.squareKey(x, y, z)
    return tostring(math.floor(x)) .. ":" .. tostring(math.floor(y)) .. ":" .. tostring(math.floor(z or 0))
end

return Tasks
