# Relatório — Fase 2: Editor e organização

## Objetivo
Permitir escrever e organizar discursos de verdade: tópicos, blocos, marcações
de orador, estimativa de duração, pastas/etiquetas/favoritos, duplicação e
salvamento automático confiável.

## Entregas

### Núcleo
- `InlineMarkup` completo — `*ênfase*`, `{pausa: 3}`, `{tom: solene}`,
  `{transição}`, `{lento}`/`{rápido}`, `{olhar}`, `{nota: ...}`, com segmentos
  contíguos que cobrem o texto inteiro (a interface usa isso para realce).
- `SpeechDurationEstimator` — palavras por minuto, pausas explícitas,
  indicações, comparação com a duração planejada.
- `SpeechTextRenderer` — texto simples/Markdown/HTML a partir do discurso
  (base da exportação e do PDF).
- `AutosaveCoordinator` — salvamento com atraso/debounce, cancelável, sem
  perder a última alteração.
- Regras de modelo: progresso de preparação, contagens, `displayTitle`,
  `duplicated(newTitle:)`, ordenação (`SpeechSortOption`), resumo
  (`SpeechSummary`).

### Aplicativo
- `Views/Speeches/SpeechEditorView` + `SpeechEditorViewModel` — edição de
  título/subtítulo/ocasião/etiquetas, tópicos e blocos (parágrafo, título,
  subtítulo, lista, citação, texto bíblico, nota, indicação, separador),
  reordenação, duplicação, exclusão, prévia de duração e marcações.
- `SpeechListView` + `SpeechListViewModel` — busca, filtros (por pasta,
  favorito, situação), ordenação e criação.
- `SpeechDetailView` + `SpeechDetailViewModel` — visão geral, progresso,
  ações (duplicar, favoritar, abrir no modo de proferimento, exportar).
- Pastas, etiquetas recentes e posição de leitura persistidas nos ajustes.

## Testes
- Núcleo: `AutoScrollAndSessionTests` (autosave, posições, resumo),
  `BibleReferenceParserTests` (referências dentro do texto),
  `ExportBackupTests` (renderização do texto) — parte dos 160.
- Aplicativo: `PayloadCodingTests` garante que tudo o que o editor grava volta
  idêntico do registro.

## Limitações desta fase
- Sem edição colaborativa, sem histórico de versões e sem controle de
  alterações por data (o discurso guarda só `createdAt`/`updatedAt`).
- A estimativa é heurística (palavras e pausas), não uma medição de fala.
- Defeitos encontrados mais tarde pelo script de verificação (e já corrigidos)
  estão registrados no relatório da Fase 6.

## Como verificar
```bash
swift test
Scripts/verify_app_logic.sh
```
