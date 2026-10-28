-- AssistenteNPC - configuracao central
-- Todos os valores de balanceamento ficam aqui para facilitar ajustes.
-- Tempos de tarefa ("time") usam ~60 unidades = 1 segundo.

AssistenteNPC = AssistenteNPC or {}

AssistenteNPC.Config = {
    -- Gerenciador (Brain)
    scanIntervalMs = 1000,       -- frequencia do laco de gerenciamento
    startDelayMs = 3000,         -- espera apos carregar o jogo antes de criar o assistente
    relocateAfterMs = 15000,     -- sumido (ex.: voce foi de carro) por esse tempo => reaparece perto de voce

    -- Corpo
    walkSpeed = 1.0,             -- multiplicador da animacao de andar
    runSpeed = 0.75,             -- multiplicador da animacao de correr
    starterItems = { "Base.BaseballBat" },

    -- Vida (o corpo e invulneravel para o jogo; a vida e controlada pelo mod)
    maxHp = 100,
    hpRegenPerMinute = 1,        -- por minuto de jogo, sem inimigos por perto
    hurtWarningHp = 35,          -- abaixo disso ele avisa que esta ferido

    -- Seguir
    followMaxDist = 3.0,         -- acima disso ele anda ate voce
    followRunDist = 10.0,        -- acima disso ele corre

    -- Combate do assistente
    assistRadius = 8,            -- raio (em volta de voce) em que ele te defende
    assistMemoryMs = 8000,       -- quanto tempo ele lembra do zumbi que voce atacou
    assistMaxChase = 15,         -- distancia maxima que ele persegue o zumbi que voce atacou
    selfDefenseRadius = 5,       -- durante tarefas, reage a zumbis a essa distancia dele
    attackCooldownMs = 900,      -- intervalo minimo entre golpes
    damageMultiplier = 2.0,      -- multiplica o dano maximo da arma contra zumbis
    reachBonus = 0.3,            -- somado ao alcance da arma

    -- Zumbis contra o assistente
    zombieAggroRadius = 10,      -- zumbis a essa distancia (e mais perto dele que de voce) vao atras dele
    zombieBiteRange = 0.9,
    zombieBiteDamage = 8,        -- vida perdida por mordida
    zombieBiteCooldownMs = 1600, -- por zumbi
    zombieSwarmBonus = 6,        -- dano extra por mordida quando 3+ zumbis o cercam

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

    debug = true,                -- TESTES: mostra ordem/tarefa/vida sobre a cabeca e registra eventos no console.txt
}

return AssistenteNPC.Config
