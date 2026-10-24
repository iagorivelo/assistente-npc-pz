# Assistente NPC — mod para Project Zomboid (Build 42)

Um sobrevivente assistente que te segue, obedece comandos por um menu radial e te
ajuda a lutar contra zumbis.

> **Requer o mod [Bandits](https://steamcommunity.com/sharedfiles/filedetails/?id=3268487204)**
> (id `Bandits2`, Build 42.20 ou mais nova). O Bandits fornece o "corpo" do NPC:
> animações, movimento e combate. Este mod adiciona o comportamento de assistente.

## Instalação (para testar)

1. Assine o **Bandits** na Steam Workshop.
2. Copie a pasta `Contents/mods/AssistenteNPC` deste projeto para
   `%UserProfile%\Zomboid\mods\` (fica `...\Zomboid\mods\AssistenteNPC\42\mod.info`).
3. No menu **Mods** do jogo, ative **Bandits** e **Assistente NPC**.
4. Comece um **jogo novo** (single-player). O assistente aparece ao seu lado
   depois de alguns segundos.

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
| **Entregar itens** | Traz para você tudo o que está carregando (menos o machado). Se você estiver sem espaço, deixa no chão. |

**Combate:** em qualquer modo de seguir, ele ataca os zumbis que estão perto de
você, principalmente o que **você** está atacando e os que estão vindo na sua
direção. Durante as outras tarefas, ele se defende quando algo chega perto.

**Morte:** se ele morrer, morre de vez (o corpo fica com o inventário dele).
Depois de **24 horas de jogo**, você recebe a dica *"Você ouve alguém gritando por
ajuda, ao norte..."*. Encontre o sobrevivente e use **Recrutar sobrevivente**
no menu radial, a até 3 tiles dele. Ele vira seu novo assistente.

**Se você for longe de carro**, o assistente reaparece perto de você uns 15
segundos depois que você sair do carro, com o mesmo nome, visual e itens. Isso
não acontece se ele estiver nas ordens *Esperar aqui* ou *Vigiar local*.

**Fogo amigo:** no Bandits, acertar um NPC amigável o torna hostil. O mod
desfaz isso automaticamente no assistente, então um golpe sem querer durante uma
briga não o transforma em inimigo.

## Ajustes

Os valores de balanceamento (raios, tempos, quantidade de árvores, cooldown de
recrutamento etc.) ficam em
`42/media/lua/client/AssistenteNPC/Config.lua`.

## Estrutura

```
Contents/mods/AssistenteNPC/
├── common/bandits/            3 clãs amigáveis (1 visual cada) lidos pelo Bandits
└── 42/
    ├── mod.info               require=\Bandits2
    └── media/lua/
        ├── shared/Translate/  EN e PTBR (JSON, formato da B42.15+)
        └── client/AssistenteNPC/
            ├── Config.lua         balanceamento
            ├── Brain.lua          gerenciador: spawn inicial, morte, recriação, ordens
            ├── Program.lua        ZombieProgram que o Bandits executa
            ├── Actions.lua        ações próprias (lootear, cortar, largar, entregar)
            ├── Tasks/             uma tarefa por comando (+ combate)
            ├── Recruit.lua        novo sobrevivente após a morte
            ├── RadialMenu.lua     menu radial e tecla
            ├── TargetCursor.lua   seleção de local no mapa
            ├── Scanner.lua        varredura da área
            ├── LootFilter.lua     o que conta como "item útil"
            ├── Bridge.lua         todo acesso à API do Bandits
            └── Util.lua
```

## Checklist de teste

O mod foi escrito sem poder rodar o jogo, então estes são os pontos a confirmar
primeiro. Os erros aparecem em `%UserProfile%\Zomboid\console.txt`; procure por
`AssistenteNPC` e `BANDITS`. Para ver mais detalhes, ative `debug = true` no
`Config.lua`.

1. O assistente aparece num jogo novo e diz *"Vamos nessa. Estou com você."*
2. **G** abre o menu radial com os comandos.
3. Ele segue, corre junto e ataca o zumbi que você acerta.
4. **Lootear corpos**: pega só itens úteis e depois entrega para você.
5. **Dar machado** e depois **Pegar madeira**: ele corta, a árvore cai e as toras vão para a pilha.
   *Ponto mais incerto:* a queda da árvore usa `toppleTree()` da API do jogo, e o código tem um plano B caso ela falhe.
6. **Vigiar local** e **Analisar área**: o cursor aparece, você clica e ele vai até o local.
7. Salvar, sair e carregar: ele continua lá, com a mesma ordem e os mesmos itens.
8. Deixe ele morrer, avance 24h e confira a dica e o recrutamento.

## Limitações conhecidas

- Só single-player.
- Depende da API interna do Bandits; uma atualização grande dele pode exigir
  ajustes, concentrados em `Bridge.lua`.
- O Bandits não salva o inventário dos NPCs, então o mod guarda uma cópia
  (tipo, condição e frescor de cada item) e a devolve ao recarregar o jogo ou
  ao recriar o assistente. Outros estados se perdem nesse processo, como usos
  restantes de itens consumíveis e o conteúdo de mochilas que ele carregue.
- Se você desativar este mod num save em que o assistente existe, o Bandits
  vai gerar erros para esse NPC, porque o programa dele deixa de existir.
  Mate ou remova o assistente antes de desativar o mod.
- A tecla padrão **G** também é a tecla padrão de "postos" do Bandits. Hoje esse
  atalho do Bandits está desativado no código dele, então não há conflito real,
  mas a tela de opções pode mostrar a duplicata.
- Falta `poster.png` (a imagem do mod no menu), que é opcional.
