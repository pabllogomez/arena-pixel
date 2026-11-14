# Arena Pixel: instruções para o Claude

Jogo Godot 4.5 (2D, pixel art) para navegador. Textos do jogo e da conversa em português do Brasil.

## Fluxo de trabalho (combinado com o dono do projeto)
1. **Planejamento primeiro:** apresentar o plano (o que muda, como funciona, decisões em aberto) e esperar aprovação antes de implementar.
2. **Build de teste:** implementar no ramo `dev`, rodar os testes e enviar (`git push origin dev`).
   O GitHub Actions publica em https://pabllogomez.github.io/arena-pixel/teste/
3. **Publicar:** só juntar `dev` em `main` quando o dono disser explicitamente para publicar.
   Antes, subir `config/version` no `project.godot` e escrever a seção da versão em `NOVIDADES.md`;
   o GitHub Actions cria a tag e o Release ao publicar a `main`.
   A `main` é a versão que os amigos jogam: https://pabllogomez.github.io/arena-pixel/

## Testes
```
godot --headless --path . --import
godot --headless --fixed-fps 60 --path . -s tools/teste.gd
godot --headless --fixed-fps 60 --path . -s tools/teste.gd -- --equilibrio 30   # vitórias por classe (bot x bot)
```
Equilíbrio entre classes (6 confrontos em paralelo, bot difícil x bot difícil, sem itens):
```
GODOT=/caminho/do/godot tools/confrontos.sh 60   # partidas por par
```
Referência atual (60 por par, Orc com investida/fúria/pouso): Orc 52%, Mago 52%, Arqueiro 50%, Rei 43%.

Rede (duas instâncias, ENet em localhost):
```
PAPEL=anfitriao godot --headless --path . -s tools/teste_rede.gd &
PAPEL=convidado godot --headless --path . -s tools/teste_rede.gd
```
Os testes rodam no CI antes de cada publicação; se falharem, nada é publicado.

## Arquitetura
- `scripts/gerador_arena.gd`: arena procedural por peças + portas (mínimo 2 pares).
- `scripts/navegacao.gd`: grafo de navegação (validação de mapas, bot e lacaios).
- `scripts/lutador.gd`: personagem; recebe comandos de um `Controle` (`controle_humano.gd` ou `controle_bot.gd`).
- `scripts/partida.gd`: regras (PvP, Recruta, sorteio de classe, cronômetro, Morte Súbita, monstros).
- `scripts/torre.gd` (+ `torre_fim.gd`): modo single player Torre da Tormenta (9 andares: subida de 5 + etapa final de 4). O `Torre` (criado pelo `main.gd`) guarda personagem, dificuldade, ordem dos adversários, estado do jogador entre lutas (`Lutador.exportar_estado`/`importar_estado`) e estatísticas; cada andar é uma `Partida` nova via `config` (`monstros`, `itens`, `morte_subita`, `regen`, `xp`, `lutadores`, `torre`; padrões = partida normal). MUITO DIFÍCIL (`ControleBot.Dificuldade.MUITO_DIFICIL`) só existe na torre e é desbloqueado por personagem em `user://opcoes.cfg`.
- `scripts/mapa_controle.gd`: índices de botão do controle por plataforma (no navegador o Godot entrega os índices crus W3C; os atalhos do InputMap em `Jogo._criar_controles` usam `MapaControle.botao()`; gatilhos não são ligados). O `Jogo` também trata a pausa (`pausa_pedida`: Start/Back/Esc/P) e o analógico nos menus (pulsos de `menu_cima`/`menu_baixo`).
- `scripts/controles_toque.gd`: botões na tela para celular.
- `resources/classes/*.tres`: atributos das classes (balanceamento).
- `scripts/rede.gd` (autoload Rede) + `scripts/lobby.gd`: jogo em rede 1x1 por WebRTC com códigos de copiar e colar; o anfitrião simula, o convidado só desenha (`partida.rede`).
- `scripts/masmorra.gd`: tochas, iluminação (opcional) e pingos.
- `scripts/particulas.gd`: partículas em pixel art (um nó desenha todas). Efeitos nomeados em `fx()`; a partida chama `partida.fx(nome, pos, a, b)`, que também repassa ao convidado em rede.
- `scripts/ui.gd`: peças de interface (fonte pixel Tiny5 em `assets/fontes/`, texto com contorno, molduras, botões, barras, ícones). A fonte só fica nítida em múltiplos de 8 px (`UI.P`, `UI.M`, `UI.G`).
- `scripts/hud.gd`, `scripts/menu.gd`, `scripts/fundo_menu.gd`, `scripts/cortina.gd`: HUD, menu na masmorra e transição entre telas.
- Efeitos visuais não podem mudar regras: confirmar com os testes e com `tools/confrontos.sh`.
- Arte/sons provisórios gerados por `tools/gerar_arte.py`; músicas por `tools/gerar_musica.py` (numpy + ffmpeg).
