# Relatório — Fase 3: Modo de proferimento

## Objetivo
A prioridade declarada do produto: proferir o discurso com texto grande,
legível e controlável, sem sustos (rolagem que não dispara sozinha), com
navegação por tópicos, temas, perfis de leitura e retomada do ponto.

## Entregas

### Núcleo
- `AutoScrollEngine` — rolagem por tempo decorrido (pontos/segundo), limites
  sãos, `pausedUntil` para “pausar e retomar”, nunca avança sem instrução.
- `PresentationSession` — estado do proferimento: seção atual, progresso,
  posição de retomada, tempo decorrido.
- `PresentationPreferences` — tipografia (fonte, altura de linha, espaçamento,
  coluna, margens), aparência (tema), rolagem (velocidade, política de
  interação, tempo de retomada), comportamento (tela acesa, orientação,
  notas, progresso, referências, interface do sistema, confirmação de saída) e
  `sanitized()` para nunca aceitar valores fora de faixa.
- `ReadingProfile` — perfis prontos (“Leitura normal”, “Fonte grande”,
  “Ambiente escuro”, “Rolagem automática”, “Púlpito (alto contraste)”).

### Aplicativo
- `Views/Presentation/PresentationView` + `PresentationViewModel` — tela do
  proferimento, toques de controle, navegação de tópicos, indicadores e
  integração com orientação/tela acesa.
- `PresentationTextView` — `UIViewRepresentable` com `UITextView` não editável
  em TextKit 1 para medição exata das seções e da rolagem.
- `PresentationTextBuilder` — monta o texto atribuído (fontes, cores por tema,
  destaques, notas do apresentador opcionais, ligações de referências).
- `PresentationSettingsSheet` — controles de tipografia/tema/rolagem em tempo
  real, carregar/salvar perfis, restaurar padrões.
- Retomada: `lastReadPosition` no discurso e no material; ao reabrir, o texto
  volta ao tópico/fração.
- `SystemSupport` — manter a tela acesa durante a apresentação, bloquear a
  orientação (opcional) e háptica leve.

## Testes
- Núcleo: `AutoScrollAndSessionTests` (17 testes) — motor, políticas de
  interação, sessão, retomada, autosave, sanidade das preferências.
- Aplicativo (Apple/Xcode): `PresentationTextBuilderTests` (12 testes) — faixas
  das seções, marcações resolvidas, notas sob demanda, ligações
  `discursoref://` presentes/ausentes conforme a preferência, fundo de
  destaque, estilos de parágrafo e tema claro × escuro.

## Defeito encontrado e corrigido
- O texto apresentado mostrava as marcações em linha cruas (`*palavra*`,
  `{pausa: 2}`). A montagem agora resolve as marcações com `InlineMarkup`,
  mantendo as indicações de bloco (`[Pausa: 2 segundos]`) como orientações
  discretas.

## Limitações desta fase
- A precisão da medição/rolagem **não foi verificada em aparelho** (exige Mac);
  é o item de maior risco restante — ver o checklist do `App/README.md`.
- Sem espelho/segundo dispositivo nem controle remoto do proferimento.
- Voz sintetizada (fase 6) lê o texto, mas não sincroniza realce palavra a
  palavra com a rolagem.

## Como verificar
```bash
swift test                        # motor e sessão
# macOS:
xcodebuild test -scheme DiscursoBiblico -destination 'platform=iOS Simulator,name=iPhone 16'
```
