# Maré de Vidro — design da versão completa (Godot 4.3)

Este documento expande o GDD (`../docs/Mare_de_Vidro_GDD.pdf`) para a
campanha inteira. O que o GDD já define foi mantido; o que faltava foi criado
aqui e está marcado com **(novo)**.

## Estrutura da campanha

| Região | Papel | Habilidade nova | Puzzles principais | Opcionais | Ecos |
| --- | --- | --- | --- | --- | --- |
| Farol Nulo (hub) | Prólogo, tutorial, oficina, portais | Maré (nó de ressonância) | Bacia do Farol (tutorial) | — | 3 |
| Jardim Mineral | Ensina maré e planar | **Planar** (Asa de Vidro) | 4 | 2 | 5 |
| Cidade Invertida | Combina sistemas | **Relé remoto** (Lume) | 4 | 2 | 5 |
| Coração Abissal | Maré em vários setores e final | **Ressonância dupla** | 4 (o 4º é o final) | 2 | 5 |

Totais: 12 puzzles principais, 6 opcionais, 3 encontros de guardião,
3 santuários, 1 puzzle final, 18 ecos opcionais, 2 epílogos (GDD 11).

## Regras comuns

- **Maré** binária por setor; alternar só perto de um nó, após 1 s de
  confirmação; transição de 2,5 s; cooldown de 5 s; o nó recusa subir a maré
  com Íris em volume inseguro (GDD 05).
- **Nó duplo (novo):** com a Ressonância dupla, alterna dois setores vizinhos
  ao mesmo tempo.
- **Relé remoto:** escanear (R) um pilão de relé dentro de 24 m com linha de
  visão o marca; E envia Lume, que liga o circuito à distância.
- **Integridade** de 3 segmentos (4 com o Núcleo reforçado); queda/água
  devolvem ao último piso seguro; contato com guardião tira 1; zerada,
  reinicia no checkpoint. Santuários restauram e salvam. Ecos nunca se perdem.
- **Guardiões** não têm combate: patrulha, alerta audiovisual, perseguição
  limitada, repouso; resolução por circuito.

## Farol Nulo — hub (prólogo, ~10–20 min)

Íris acorda na ilhota sul. Lume aparece e a guia.

1. **Primeiros passos:** pedras para saltar até a ilhota do nó.
2. **Bacia do Farol (tutorial de maré):** a bacia entre a ilhota e a ilha
   do farol está alagada. Escanear o nó e baixar a maré expõe o caminho de
   pedra no fundo. Ao atravessar, Lume: "controlar a maré é possível" (Ato I).
3. **Ilha do Farol:** farol com cristal-lanterna, **oficina** (melhorias e
   visores), três **portais**: Jardim (aberto), Cidade (abre após o santuário
   do Jardim), Coração (abre após o santuário da Cidade).
4. **Ecos do hub (3):** um na ilhota do nó; um no alto do farol (planar a partir
   do mirante, exige Planar); um atrás da porta do arquivo, ligada por um pilão
   de relé (exige Relé remoto). Incentivam o retorno.

### Oficina (novo)

| Melhoria | Requisito | Efeito |
| --- | --- | --- |
| Lente ampla | 3 ecos | raio do escaneamento ×2 e ecos aparecem no scan |
| Núcleo reforçado | 7 ecos | +1 segmento de integridade |
| Bússola de eco | 12 ecos | Lume aponta o eco mais próximo não coletado |
| Visor Cobre / Sal / Cerâmica | 5 / 10 / 15 ecos | cosméticos do visor da Íris |

## Jardim Mineral (~15–25 min nesta build)

Setor único. Começa em maré alta.

- **P1 Cisterna:** escanear o nó, baixar a maré, descer a escada de cristal,
  girar o condutor, subir de volta, subir a maré: a ponte líquida se forma.
- **Asa de Vidro:** no fim da ponte, Lume instala o módulo de planar.
- **P2 Comporta (novo):** a escada da praça está fechada por uma comporta. A
  alavanca fica na ilhota oeste: subir pela pedra flutuante (só na maré alta)
  até a torre e planar até a ilhota; planar de volta.
- **P3 Praça do guardião (encontro 1):** na maré baixa, três placas (▲ ● ■).
  O pilar de leitura na entrada, escaneado, mostra a ordem. Pisar na ordem
  certa fecha o circuito: o núcleo do guardião se acalma e o portão norte abre.
  Ordem errada reinicia o circuito.
- **P4 Anel do santuário (novo):** dois condutos alimentam o anel — um na
  trincheira (exposto na maré baixa) e outro numa plataforma de flutuação
  (erguida na maré alta). Acender os dois ativa o anel: memória, descanso,
  save e abertura do portal da Cidade.
- **Opcionais:** O1 plataformas de flutuação (maré alta + saltos);
  O2 mirante da chegada (planar até a rocha distante).
- **Ecos (5):** plataformas, cisterna (maré baixa), ilhota, praça, mirante.

## Cidade Invertida (~15–25 min nesta build) (novo layout)

Bairros inteiros pendem de cabeça para baixo sob grandes placas flutuantes;
Íris caminha sobre as placas e vê as torres invertidas abaixo e acima.
Setor único ("canais da cidade").

- **P1 Terminal de Lume:** escanear e usar o terminal concede o Relé remoto.
  O elevador para o Mercado Caído está sem energia; o pilão fica numa rocha
  inalcançável: escanear o pilão e enviar Lume liga o elevador.
- **P2 Rede de condutores:** três junções giratórias levam energia da fonte à
  porta do Mercado. Os trilhos acendem conforme o caminho se conecta.
- **P3 Praça alagada:** na maré baixa, descer à praça e acionar a comporta;
  na maré alta, a plataforma de flutuação sobe até a varanda, de onde há linha
  de visão para o pilão do portão.
- **P4 Guardiões gêmeos (encontro 2):** dois guardiões mais rápidos patrulham
  a rua do mercado. Dois pilões precisam receber o relé sem que Íris seja vista.
  Os dois ligados reativam o núcleo da cidade e abrem o santuário.
- **Santuário 2:** memória, descanso, abre o portal do Coração.
- **Opcionais:** O3 torre pendurada (planar até a base de uma torre invertida;
  elevador por relé para voltar); O4 bonde suspenso (relé liga a gôndola).
- **Ecos (5):** torre pendurada, bonde, canto do mercado, fundo da praça
  alagada (maré baixa), varanda.

## Coração Abissal (~15–25 min nesta build) (novo layout)

Anel de ilhas em volta de um abismo; no centro, o Coração — esfera de vidro
com água suspensa. Três setores independentes: Oeste, Norte, Leste.

- **P1 Câmara da Ressonância:** pegar a Ressonância dupla. A ponte longa até a
  ilha norte precisa de Oeste **e** Norte altos; o único nó alcançável é duplo.
- **P2 Escada espiral:** três lances até o fundo: plataformas de flutuação
  (Oeste alto), ponte líquida (Norte alto) e caminho no leito (Leste baixo).
  O nó duplo da Ilha Norte (Norte+Leste) seca o leito mas derruba a ponte;
  o nó simples do patamar (Norte) a ergue de novo — a ordem é o puzzle.
- **Santuário 3:** checkpoint antes do guardião.
- **P3 Guardião abissal (encontro 3):** guardião maior, mais lento, com visão
  longa, patrulha o anel do Coração. Três pilões ao redor recebem o relé.
- **P4 O Coração (final):** pilares de leitura mostram o padrão (Oeste ▲,
  Norte ▼, Leste ▲), cada um com um tubo de vidro que mostra o nível do seu
  setor e um nó simples ao lado — todos no anel patrulhado. Com os três
  pilões ligados e o padrão certo, o nó central no píer abre o Coração.
  **Decisão:** liberar o ciclo natural ou manter o arquipélago estável.
- **Opcionais:** O5 leito do setor Leste (maré baixa); O6 agulha alta
  (planar a partir da ilha norte).
- **Ecos (5):** câmara, leito leste, agulha, espiral, mirante do Coração.

## Final e epílogos (novo)

- **Liberar o ciclo:** o oceano volta a cair em cascatas, o céu clareia, as
  ilhas descem devagar. Lume: "Vamos lembrar sem prender."
- **Manter o arquipélago:** o mar vira vidro, cristais cobrem o farol, o céu
  fica parado na noite. Lume: "Ninguém mais vai cair. Nem partir."
- Os dois preservam as memórias recuperadas; o epílogo muda paisagem e
  falas do hub. Após o final: seleção de capítulo.

## Narrativa por ecos (18)

Os ecos contam, fora de ordem, a votação que imobilizou o oceano, o medo da
perda, os guardiões construídos para impedir a reativação e a cartógrafa
anterior que deixou mapas para Íris. Textos em `scripts/autoload/i18n.gd`.

## Ajustes feitos pelo teste de jogabilidade

O teste automático (`--playtest`, ver README) joga a campanha inteira com
física real e encontrou problemas que um jogador também encontraria; todos
foram corrigidos:

- **Jardim:** depois de atravessar a ponte líquida não havia nó acessível
  para baixar a maré da praça (baixar na cisterna derrubaria a ponte com Íris
  do lado errado) → novo **nó da praça** na entrada norte do jardim.
- **Jardim / Farol:** as rochas dos ecos do mirante e do topo ficavam altas
  demais para alcançar planando → rebaixadas, e marcadas como "sem retorno"
  (cair delas devolve ao último piso seguro, não à rocha).
- **Farol:** o arquivo ficava meio fora da ilha (eco inalcançável) → movido
  para dentro.
- **Escadas:** várias terminavam 0,2–0,4 m dentro do piso de cima, criando uma
  quina que travava Íris → rampas agora terminam na borda, com patamar plano e
  6 cm de folga; extensão na base evita degrau ao subir.
- **Santuários:** a chegada caía dentro de um plinto do modelo e o portal de
  volta sobrepunha um pilar → chegada na faixa da frente, fonte na borda da
  piscina e portal numa plataforma lateral à escada.
- **Plataformas móveis:** pausas de 3 s nas pontas (antes 2 s) e simulação do
  mundo com o tempo real do quadro (não mais limitado a 0,05 s), para que
  elevadores e bonde fiquem em sincronia com Íris mesmo com FPS baixo.

