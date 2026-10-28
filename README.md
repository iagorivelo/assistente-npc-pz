# Assistente NPC — mod para Project Zomboid (Build 42)

Um sobrevivente assistente que te segue, obedece comandos por um menu radial e te
ajuda a lutar contra zumbis. **Não depende de nenhum outro mod.**

> Versão em teste (branch `standalone`). O modo de depuração está **ligado**:
> o assistente mostra ordem, tarefa e vida acima da cabeça. Desligue em
> `Config.lua` (`debug = false`) quando não precisar mais.

## Instalação (para testar)

1. Copie a pasta `Contents/mods/AssistenteNPC` deste projeto para
   `%UserProfile%\Zomboid\mods\` (fica `...\Zomboid\mods\AssistenteNPC\42\mod.info`).
2. No menu **Mods** do jogo, ative **Assistente NPC**.
3. Comece um **jogo novo** (single-player). O assistente aparece ao seu lado
   depois de alguns segundos, com um taco de beisebol.

Requer Build **42.15 ou mais nova** (as traduções usam o formato JSON da 42.15+).

## Comandos

Aperte **G** para abrir o menu radial (a tecla pode ser trocada em
*Opções → Mods → Assistente NPC*).

| Comando | O que ele faz |
|---|---|
| **Seguir-me** | Segue você e imita seu passo (corre quando você corre, agacha quando você agacha). |
| **Esperar aqui** | Fica parado onde você está. Só luta se algo chegar muito perto. |
| **Lootear corpos** | Revista os corpos num raio de 15 tiles e pega **só itens úteis**: armas, comida boa, remédios, munição, ferramentas e chaves. No fim, traz tudo para você. |
| **Pegar madeira** | Derruba até 3 árvores perto de onde você está e empilha as toras ali. Sem machado, a opção aparece como *"Pegar madeira (necessita de um machado para concluir)"*. |
| **Dar machado** | Aparece quando ele não tem machado e você tem um: passa o seu machado para ele. |
| **Vigiar local** | Você clica no mapa. Ele vai até lá, ataca zumbis num raio de 10 tiles e avisa você. |
| **Analisar área** | Você clica no mapa. Ele vai até lá e relata: zumbis, corpos (e quantos têm itens úteis), móveis com itens, itens no chão, árvores e os achados mais valiosos. |
| **Entregar itens** | Traz para você o que está carregando. Ele fica com a arma que usa e com o machado. Se você estiver sem espaço, deixa no chão. |

**Combate:** ele ataca com a melhor arma corpo a corpo que tiver (troca sozinho
se ganhar uma melhor ou se a atual quebrar). Defende você, principalmente contra
o zumbi que **você** está atacando e os que vêm na sua direção. Zumbis que estão
mais perto dele do que de você vão atrás dele e mordem.

**Vida:** ele tem 100 de vida, perde vida com mordidas (mais rápido se estiver
cercado), avisa quando está ferido e se recupera devagar quando não há zumbis
por perto.

**Morte:** se ele morrer, morre de vez; o corpo fica com o inventário dele.
Depois de **24 horas de jogo** você recebe a dica *"Você ouve alguém gritando por
ajuda, ao norte..."*. Encontre o sobrevivente e use **Recrutar sobrevivente**
no menu radial (a até 3 tiles dele): ele vira seu novo assistente.

**Se você for longe de carro**, o assistente reaparece perto de você uns 15
segundos depois que você sair do carro, com o mesmo nome, visual e itens. Isso
não acontece se ele estiver em *Esperar aqui* ou *Vigiar local*.

## Como funciona por dentro

O jogo não oferece hoje um NPC humano controlável só por Lua na Build 42. Como
outros mods de NPC, o corpo do assistente é um **zumbi disfarçado de humano**:

- **Aparência:** pele humana, cabelo, roupas, sem sangue nem ferimentos (`Engine/Look.lua`).
- **Animações:** 23 nós em `media/AnimSets/zombie/` que reaproveitam animações
  humanas do próprio jogo. Elas só valem para o assistente (variável `ANPC` e
  tipos de passo `ANPCWalk`/`ANPCRun`/`ANPCSneak`), então zumbis normais não
  são afetados.
- **Comportamento de zumbi desligado** a cada atualização: sem alvo, sem
  mordida, sem gemido (`Engine/Body.lua`).
- **Tarefas e combate próprios** (`Engine/Executor.lua`, `Engine/Fight.lua`).
- **Persistência:** o jogo recria os zumbis ao carregar. O mod reconhece o
  corpo pelo `persistentOutfitID` e guarda no ModData a ordem, a vida, a
  aparência e uma cópia do inventário (`Engine/Registry.lua`). O corpo nasce
  com uma roupa-base exclusiva do mod (`media/clothing/clothing.xml`), então
  esse ID nunca coincide com o de um zumbi comum.

## Estrutura

```
Contents/mods/AssistenteNPC/
├── common/                    exigida pela Build 42 (vazia)
└── 42/
    ├── mod.info
    └── media/
        ├── AnimSets/zombie/   animações humanas do assistente
        ├── clothing/          roupas-base exclusivas (identidade do corpo)
        └── lua/
            ├── shared/Translate/  EN e PTBR (JSON)
            └── client/AssistenteNPC/
                ├── Config.lua         balanceamento (e o modo debug)
                ├── Engine/            motor do NPC: corpo, aparência, registro,
                │                      tarefas, combate e laço por corpo
                ├── Brain.lua          gerenciador: assistente inicial, inventário,
                │                      recriação, morte e ordens
                ├── Program.lua        decide a próxima tarefa a partir da ordem
                ├── Tasks/             uma tarefa por comando (+ escolha de alvo)
                ├── Actions.lua        ações: lootear, cortar, largar toras, entregar
                ├── Recruit.lua        novo sobrevivente após a morte
                ├── RadialMenu.lua     menu radial e tecla
                ├── TargetCursor.lua   seleção de local no mapa
                ├── Scanner.lua        varredura da área
                ├── LootFilter.lua     o que conta como "item útil"
                ├── Bridge.lua         fachada do motor para as tarefas
                └── Util.lua
```

## Checklist de teste

Os erros aparecem em `%UserProfile%\Zomboid\console.txt` (procure por
`AssistenteNPC`). Com o modo debug ligado, o texto azul acima da cabeça dele
mostra `[papel] ordem | tarefa | hp | estado`.

1. **Aparência:** ele aparece num jogo novo, com cara e roupa de gente (não de zumbi), e diz *"Vamos nessa. Estou com você."*
2. **Movimento:** ele anda e corre como pessoa atrás de você, sem gemer nem tentar te morder.
3. **Combate:** ele golpeia zumbis com o taco, e zumbis perto dele o atacam e tiram vida.
4. **Menu:** G abre o menu radial.
5. **Lootear:** ele pega só itens úteis e depois entrega para você.
6. **Madeira:** use *Dar machado* e depois *Pegar madeira*. A árvore cai e as toras vão para a pilha.
7. **Vigiar e analisar:** o cursor aparece, você clica e ele vai até lá. Você não deve andar até o local.
8. **Salvar e carregar:** depois de salvar, sair e carregar, ele volta com a mesma aparência, ordem e itens.
9. **Morte e recrutamento:** deixe ele morrer, avance 24h e confira a dica e o recrutamento.

## Limitações conhecidas

- Só single-player.
- Golpes seus nele não causam dano, mas podem fazê-lo cambalear com animação de zumbi.
- A presença dele pode contar como "zumbi por perto" para a música e o pânico do personagem.
- Itens recriados (ao recarregar ou recriar o assistente) mantêm tipo, condição
  e frescor, mas perdem outros estados (usos restantes, conteúdo de mochilas).
