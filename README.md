# Arena Pixel

Combate 1x1 local em plataformas, 2D, pixel art, feito em **Godot 4.5** para rodar no **navegador**.

## Como jogar

**Modos:** 1 jogador (contra a máquina: Fácil, Normal ou Difícil), 2 jogadores no mesmo teclado, ou **jogar em rede** (1x1 entre dois aparelhos).

### Jogar em rede
1. Quem cria: **JOGAR EM REDE → CRIAR PARTIDA → COPIAR CONVITE** e manda o código para o amigo (WhatsApp, por exemplo).
2. O amigo: **JOGAR EM REDE → ENTRAR → COLAR CONVITE**; o jogo gera a **RESPOSTA**, que ele copia e manda de volta.
3. Quem criou: **COLAR RESPOSTA**. A partida começa sozinha para os dois.

Funciona no mesmo Wi-Fi e, na maioria das redes, pela internet. Cada um joga com os controles do P1 (teclado WASD ou toque).
Por baixo é WebRTC ponto a ponto, sem servidor: quem criou a partida "roda" o jogo e o outro recebe o estado.

| | Jogador 1 | Jogador 2 |
|---|---|---|
| Andar | `A` / `D` | `←` / `→` |
| Pular | `W` ou `Espaço` | `↑` ou `0` |
| Descer da plataforma | `S` | `↓` |
| Escolher melhoria | `Q` / `E` | `1` / `2` do teclado numérico (ou `K` / `L`) |

**Pausa:** botão ⏸ ao lado do cronômetro (ou `Esc`/`P`): continuar, tela cheia, som, iluminação, tremor e clarões, e voltar ao menu. As mesmas opções ficam em **OPÇÕES** no menu inicial (atalhos: `F` tela cheia, `M` som, `I` iluminação). As escolhas ficam salvas. No celular a tela fica limpa: arraste o dedo em qualquer ponto da metade esquerda para andar (puxando para baixo desce da plataforma) e toque em qualquer ponto da metade direita para pular; as melhorias são escolhidas tocando na carta. Um tutorial explica isso antes da primeira partida (dá para rever em **OPÇÕES → COMO JOGAR**), e **Botões na tela** em OPÇÕES traz de volta o joystick e o botão de pulo desenhados. O botão de tela cheia fica no canto do menu inicial.
Controles (gamepad) também funcionam.

### Regras
- **Todos começam como Recruta:** fraco, ataca corpo a corpo e causa pouco dano em jogadores. Os monstros de nível 1 só revidam, e matar um monstro cura 8% da vida. A classe chega depois de 6 monstros (uns 40 segundos).
- **No nível 2**, o Recruta vira uma **classe sorteada**, sem repetir a do oponente. Dos níveis 3 em diante, cada nível oferece 2 melhorias (cartas grandes na lateral; toque, clique ou `Q`/`E`).
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
  rede.gd              jogo em rede (WebRTC, códigos de copiar e colar)
  lobby.gd             tela "JOGAR EM REDE"
  controles_toque.gd   joystick e botões na tela para celular, ícones de opções
  masmorra.gd          tochas, iluminação e pingos
  particulas.gd        partículas em pixel art (faíscas, poeira, estilhaços...)
  ui.gd                peças de interface: fonte pixel, molduras, botões, barras
  fundo_menu.gd        fundo animado das telas de menu
  cortina.gd           transição em blocos entre as telas
  projetil.gd, melhorias.gd, classe_dados.gd, hud.gd, menu.gd, nevoa.gd, main.gd, jogo.gd
resources/classes/     atributos das classes
assets/fontes/         fonte pixel Tiny5 (licença SIL OFL, texto em Tiny5-OFL.txt)
assets/                arte e sons PROVISÓRIOS (gerados por tools/gerar_arte.py; músicas em tools/gerar_musica.py)
tools/teste.gd         teste automático (mapas + partidas bot x bot + equilíbrio)
tools/teste_rede.gd    teste do jogo em rede (duas instâncias conectadas)
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

Para a tabela de confrontos classe contra classe (6 pares em paralelo): `GODOT=/caminho/do/godot tools/confrontos.sh 60`.
