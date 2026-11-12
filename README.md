# Arena Pixel

Combate 1x1 local em plataformas, 2D, pixel art, feito em **Godot 4.5** para rodar no **navegador**.

## Como jogar

**Modos:** 1 jogador (contra a máquina: Fácil, Normal ou Difícil) ou 2 jogadores no mesmo teclado.

| | Jogador 1 | Jogador 2 |
|---|---|---|
| Andar | `A` / `D` | `←` / `→` |
| Pular | `W` ou `Espaço` | `↑` ou `0` |
| Descer da plataforma | `S` | `↓` |
| Escolher melhoria | `Q` / `E` | `1` / `2` do teclado numérico (ou `K` / `L`) |

**Pausa:** botão ⏸ ao lado do cronômetro (ou `Esc`/`P`): continuar, tela cheia, som, iluminação e voltar ao menu. As mesmas opções ficam em **OPÇÕES** no menu inicial (atalhos: `F` tela cheia, `M` som, `I` iluminação). As escolhas ficam salvas. No celular: encoste o dedo em qualquer ponto da metade esquerda e aparece um joystick (para os lados anda, puxando para baixo desce da plataforma); o botão de pular fica na direita, e as melhorias são escolhidas tocando na opção.
Controles (gamepad) também funcionam.

### Regras
- **Todos começam como Recruta:** fraco, ataca corpo a corpo e causa pouco dano em jogadores. Os monstros de nível 1 só revidam, e matar um monstro cura 8% da vida. A classe chega em ~1 minuto.
- **No nível 2**, o Recruta vira uma **classe sorteada**, sem repetir a do oponente. Dos níveis 3 em diante, cada nível oferece 2 melhorias (cartas grandes na lateral; toque, clique ou `Q`/`E`). No modo solo o jogo pausa enquanto você escolhe e volta com contagem de 3 s.
- **O ataque é automático:** sai sozinho quando um inimigo entra no alcance.
- **Monstros** dão XP e ficam mais fortes, rápidos e agressivos conforme o maior nível entre os jogadores. A cor indica a força: roxo, depois verde, laranja e vermelho.
- **Dano entre jogadores** é reduzido:
  - o Recruta causa pouco dano em jogadores;
  - um jogador com classe causa 1/3 do dano em um Recruta;
  - com os dois já com classe, vale o dano normal de PvP.
- **Portas** são todas iguais: só descobre para onde cada uma leva quem entra. Há sempre pelo menos 2 pares.
- **Ambiente:** masmorra escura com tochas, esqueletos acorrentados e pingos d'água; música própria para o menu e para a partida (que acelera na Morte Súbita).
- **Cada partida dura 3 minutos.** Se ninguém vencer até lá, começa a **Morte Súbita**:
  - as portas fecham e param de nascer monstros;
  - uma fumaça tóxica sobe do chão;
  - o dano entre jogadores aumenta a cada 15 s.
- **Vence quem sobrar vivo.**

## Classes

| Classe | Estilo |
|---|---|
| Recruta | Classe inicial de todos. Fraco, só serve para caçar monstros |
| Arqueiro | Rápido, atira flechas sem parar, dano baixo |
| Orc | Corpo a corpo, muito dano e vida, lento |
| Mago | Orbe lento que causa mais dano quanto menos distância percorre. Frágil e lento |
| Rei | Não ataca: convoca lacaios de tempos em tempos, e eles caçam sozinhos |

Os atributos ficam em `resources/classes/*.tres` e podem ser editados no Inspector do Godot.

## Estrutura

```
scripts/
  gerador_arena.gd     arena procedural por peças (escadaria, torre, ponte, ilha...) e portas
  navegacao.gd         grafo de navegação: valida mapas e guia o bot e os lacaios
  partida.gd           regras: PvP, sorteio de classe, cronômetro, Morte Súbita, monstros
  lutador.gd           personagem (movimento + ataque automático + XP)
  controle*.gd         quem comanda o lutador: humano (teclado/controle) ou bot
  seguidor_caminho.gd  segue caminhos da navegação
  minion.gd            lacaios do Rei e monstros neutros
  controles_toque.gd   joystick e botões na tela para celular, ícones de opções
  masmorra.gd          tochas, iluminação e pingos
  projetil.gd, melhorias.gd, classe_dados.gd, hud.gd, menu.gd, nevoa.gd, main.gd, jogo.gd
resources/classes/     atributos das classes
assets/                arte e sons PROVISÓRIOS (gerados por tools/gerar_arte.py; músicas em tools/gerar_musica.py)
tools/teste.gd         teste automático (mapas + partidas bot x bot + equilíbrio)
```

## Versões no ar

| Versão | Ramo | Link |
|---|---|---|
| **Ativa** (para os amigos) | `main` | https://pabllogomez.github.io/arena-pixel/ |
| **Teste** | `dev` | https://pabllogomez.github.io/arena-pixel/teste/ |

O desenvolvimento acontece no ramo `dev`. A cada push, o GitHub Actions
(`.github/workflows/web.yml`) roda o teste automático, exporta os dois ramos e publica.
Se algum teste falhar, nada é publicado. Quando a versão de teste estiver aprovada,
junte `dev` em `main` para atualizar a versão ativa.

## Exportar manualmente para o navegador

1. No Godot: **Editor → Gerenciar Modelos de Exportação → Baixar e instalar**.
2. **Projeto → Exportar → Web → Exportar Projeto**. O arquivo vai para `build/web/index.html`.
3. Para testar localmente, no próprio diálogo de exportação clique no ícone de
   **Executar no navegador** (ou rode `python3 -m http.server` dentro de `build/web`).
4. Para publicar, envie a pasta `build/web` para o itch.io, o GitHub Pages, o Netlify etc.
   O preset está **sem threads**, então funciona em qualquer hospedagem sem configurar cabeçalhos especiais.

## Teste automático

```
godot --headless --fixed-fps 60 --path . -s tools/teste.gd
godot --headless --fixed-fps 60 --path . -s tools/teste.gd -- --equilibrio 30
```

O segundo comando simula 30 partidas de bot difícil contra bot difícil e mostra a taxa de vitória de cada classe.
