-- AssistenteNPC - configuracao central
-- Todos os valores de balanceamento ficam aqui para facilitar ajustes.
-- Tempos de tarefa ("time") seguem a unidade do Bandits: ~60 unidades = 1 segundo.

AssistenteNPC = AssistenteNPC or {}

AssistenteNPC.Config = {
    -- Integracao com o Bandits
    programName = "AssistenteNPC",       -- nome do ZombieProgram registrado
    keyAssistant = "AssistenteNPC",      -- brain.key do assistente
    keyStray = "AssistenteNPC_Stray",    -- brain.key do sobrevivente recrutavel
    -- Clas definidos em common/bandits/clans.txt. Cada cla tem um unico modelo
    -- de NPC (common/bandits/bandits.txt), entao o cla define o visual.
    -- Clas com spawnChance = 0 nunca aparecem sozinhos pelo mapa.
    clans = {
        "5fc15d3b-9667-4e48-925c-24027145eeff", -- Lenhador
        "96f949b5-09c2-4f34-a043-0627d4b1110c", -- Exploradora
        "1028ff56-3d9d-43be-8982-b5df85c28aa6", -- Andarilho
    },

    -- Gerenciador (Brain)
    scanIntervalMs = 1000,       -- frequencia da busca pelo NPC na lista de zumbis
    startDelayMs = 3000,         -- espera apos carregar o jogo antes de criar o assistente
    spawnTimeoutMs = 10000,      -- se o NPC pedido nao aparecer nesse tempo, pede de novo
    relocateAfterMs = 15000,     -- sumido (ex.: voce foi de carro) por esse tempo => reaparece perto de voce
    spawnRetryMs = 60000,        -- se o Bandits nao criar o assistente, tenta de novo depois disso

    -- Seguir
    followMaxDist = 3.0,         -- acima disso ele anda ate voce
    followRunDist = 10.0,        -- acima disso ele corre

    -- Combate
    assistRadius = 8,            -- raio (em volta de voce) em que ele te defende
    assistMemoryMs = 8000,       -- quanto tempo ele lembra do zumbi que voce atacou
    assistMaxChase = 15,         -- distancia maxima que ele persegue o zumbi que voce atacou
    selfDefenseRadius = 5,       -- durante tarefas, reage a zumbis a essa distancia dele

    -- Lootear corpos
    lootRadius = 15,             -- raio de busca por corpos (a partir de onde voce deu a ordem)
    lootTime = 150,
    lootMaxWeight = 25,          -- peso carregado que faz ele voltar para entregar
    maxAttempts = 6,             -- tentativas de alcancar um alvo antes de desistir dele

    -- Madeira
    woodRadius = 20,             -- raio de busca por arvores (a partir da pilha)
    woodTreesPerOrder = 3,       -- arvores derrubadas por comando
    chopTime = 180,              -- duracao de cada sequencia de machadadas
    chopHitsPerTree = 8,         -- sequencias necessarias para derrubar uma arvore
    logsPerTrip = 2,             -- toras carregadas por viagem
    logSearchRadius = 3,         -- raio em volta da arvore derrubada para achar toras

    -- Vigiar
    guardRadius = 10,
    guardAlertCooldownMs = 15000,

    -- Analisar area
    analyzeRadius = 12,
    analyzeArriveDist = 3,
    analyzeLookTime = 200,

    -- Morte / recrutamento
    recruitCooldownHours = 24,   -- horas de jogo apos a morte ate surgir um novo sobrevivente
    recruitSpawnMinDist = 60,    -- distancia (tiles) do jogador onde o sobrevivente aparece
    recruitSpawnMaxDist = 150,
    recruitInteractDist = 3,
    strayHelpCooldownMs = 12000,
    strayLostMs = 30000,         -- perto do local e sem achar o sobrevivente por esse tempo => recria

    debug = false,
}

return AssistenteNPC.Config
