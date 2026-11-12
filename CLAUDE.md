# Arena Pixel: instruções para o Claude

Jogo Godot 4.5 (2D, pixel art) para navegador. Textos do jogo e da conversa em português do Brasil.

## Fluxo de trabalho (combinado com o dono do projeto)
1. **Planejamento primeiro:** apresentar o plano (o que muda, como funciona, decisões em aberto) e esperar aprovação antes de implementar.
2. **Build de teste:** implementar no ramo `dev`, rodar os testes e enviar (`git push origin dev`).
   O GitHub Actions publica em https://pabllogomez.github.io/arena-pixel/teste/
3. **Publicar:** só juntar `dev` em `main` quando o dono disser explicitamente para publicar.
   A `main` é a versão que os amigos jogam: https://pabllogomez.github.io/arena-pixel/

## Testes
```
godot --headless --path . --import
godot --headless --fixed-fps 60 --path . -s tools/teste.gd
godot --headless --fixed-fps 60 --path . -s tools/teste.gd -- --equilibrio 30   # vitórias por classe (bot x bot)
```
O teste roda no CI antes de cada publicação; se falhar, nada é publicado.

## Arquitetura
- `scripts/gerador_arena.gd`: arena procedural por peças + portas (mínimo 2 pares).
- `scripts/navegacao.gd`: grafo de navegação (validação de mapas, bot e lacaios).
- `scripts/lutador.gd`: personagem; recebe comandos de um `Controle` (`controle_humano.gd` ou `controle_bot.gd`).
- `scripts/partida.gd`: regras (PvP, Recruta, sorteio de classe, cronômetro, Morte Súbita, monstros).
- `scripts/controles_toque.gd`: botões na tela para celular.
- `resources/classes/*.tres`: atributos das classes (balanceamento).
- `scripts/masmorra.gd`: tochas, iluminação (opcional) e pingos.
- Arte/sons provisórios gerados por `tools/gerar_arte.py`; músicas por `tools/gerar_musica.py` (numpy + ffmpeg).
