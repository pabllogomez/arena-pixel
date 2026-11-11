# Arena Pixel

Combate 1x1 local em plataformas, 2D, pixel art, feito em **Godot 4.5** para rodar no **navegador**.

## Como jogar

| | Jogador 1 | Jogador 2 |
|---|---|---|
| Andar | `A` / `D` | `←` / `→` |
| Pular | `W` ou `Espaço` | `↑` ou `0` |
| Descer da plataforma | `S` | `↓` |
| Escolher melhoria | `Q` / `E` | `1` / `2` do teclado numérico (ou `K` / `L`) |

Controles (gamepad) também funcionam: o 1º controle é o P1 e o 2º é o P2.

- **O ataque é automático:** sai sozinho quando um inimigo entra no alcance.
- **Portas:** portas de mesma cor são ligadas. Entrou por uma, sai pela outra.
- **Monstros roxos** são neutros e atacam qualquer um. Matá-los dá XP. Cada nível oferece 2 melhorias para escolher.
- **Vence quem sobrar vivo.** Depois, `Pular` = revanche com mapa novo e `Esc` = trocar classes.

## Classes

| Classe | Estilo |
|---|---|
| Arqueiro | Rápido, atira flechas sem parar, dano baixo |
| Orc | Corpo a corpo, muito dano e vida, lento |
| Mago | Orbe lento que causa mais dano quanto menos distância percorre. Frágil e lento |
| Rei | Não ataca: convoca lacaios de tempos em tempos, e eles caçam sozinhos |

Os atributos ficam em `resources/classes/*.tres` e podem ser editados no Inspector do Godot.

## Estrutura

```
scripts/
  gerador_arena.gd   geração procedural do mapa e das portas
  partida.gd         partida: portas, monstros, vitória
  lutador.gd         personagem do jogador (movimento + ataque automático)
  minion.gd          IA dos lacaios do Rei e dos monstros neutros
  projetil.gd        flechas e orbes
  melhorias.gd       melhorias de nível
  classe_dados.gd    recurso com os atributos de cada classe
  hud.gd, selecao.gd, main.gd, jogo.gd (autoload)
resources/classes/   atributos das 4 classes
assets/              arte e sons PROVISÓRIOS
tools/gerar_arte.py  gera a arte/sons provisórios (python3 + Pillow)
tools/teste.gd       teste automático (2000 mapas + partidas simuladas)
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
```
