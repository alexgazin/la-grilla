# Host measurements: catalogue metadata and full-project edits

Эти результаты получены **на Linux x86_64, Swift 6.1.2, release build**. Они подтверждают стоимость конкретных операций MusicDomain/ProjectStore на этом host. Это не измерения iPhone, SwiftUI, температуры, памяти/RSS, задержки касания или отсутствия audio dropouts.

## Измеренный результат

Все значения ниже — медианы в миллисекундах. Сравнение `AFTER list()` → `listSummaries()` использует одни и те же сохраненные проекты в одном AFTER запуске.

| Fixture / проектов | BEFORE list() | AFTER list() | AFTER listSummaries() | AFTER summary(id) |
| --- | ---: | ---: | ---: | ---: |
| P1 / 10 | 81.403 | 61.091 | 3.349 | 0.343 |
| P1 / 50 | 441.584 | 298.244 | 14.043 | 0.349 |
| P3 / 10 | 2269.579 | 1668.632 | 28.841 | 2.774 |
| P3 / 50 | 10177.557 | 8159.464 | 142.218 | 2.903 |

Для P3/50 новый metadata API занимает **142.218 мс против 8159.464 мс**, то есть в **57.37 раза меньше** времени legacy list в этом AFTER workload. Контекстный BEFORE результат — 10.18 секунды; он относится к более раннему исходнику и отдельному запуску. Это не обещание такой же кратности на телефоне.

Прежний `History.apply` mix-edit путь по-прежнему выполнял полную валидацию: P3 median 37.009 мс, p95 37.696 мс. В этом benchmark новый специализированный mix API **не измерялся**. Его отдельные результаты находятся в [MIX_HISTORY.md](MIX_HISTORY.md) и `mix-history-*`.

## Протокол

- Использованы неизмененные committed fixtures P1/P3: 768 / 16,384 compiled notes, 64 такта. Baseline архивы имеют 51,321 / 1,353,845 bytes.
- Для `Project.validate`, `Compiler.notes`, `History.apply` mix и изменения velocity существующей drum note — один warmup и 15 измеряемых повторов. Каждый History sample начинается со свежего значения fixture и History.
- Для каждого набора 10/50 проектов setup/save и первый warmup записаны отдельно. Legacy list и metadata list имеют по 5 измеряемых повторов. `summary(selectedID)` — один warmup и 15 измеряемых вызовов.
- Все записи обязаны успешно загрузиться; counts, id/name/bpm/key/revision/modified/schema/bars/trackCount и отсутствие ошибок metadata сверены с каноническими сохраненными значениями.
- `retainedSummaryCount=10/50` описывает возвращаемые metadata значения. Полного Project/patterns/events в ProjectSummary нет; это проверка формы API, **не** замер RSS.
- Receipt содержит все raw samples, min/median/nearest-rank p95/max. При 15 samples p95 совпадает с максимумом. ОС-кэш не очищался, host использовался совместно с другими задачами; измерения последовательные, без выделенного CPU.

## Идентичность исходников и файлов

BEFORE — точный commit `29adf6c398173faf830de8f6249702628b8a3f76`; source digest `f322737eca5390e3a8b56512e2cb376755706abdac8b0df1cbe86308f03fd649`.

Исторический AFTER — стабильный snapshot **незакоммиченного** MusicDomain поверх того же base, снятый 16 ноября 2026 в 13:16:07 UTC. Его digest: `79fe7fbe619adc6f21bbc7ff2b669d27bf1760e9471de83cf1549b9328ac40dd`. Это не финальный source SHA. Snapshot включает не только metadata/rename fix, но и находившиеся тогда в worktree изменения музыкального домена; отдельные недоказанные ускорения им не приписываются.

Raw receipt SHA-256:

- BEFORE: `7fc42d3d5585179c0c28e69d4e21d9d48ef70310158542e6ab6d229d10ef039f`.
- AFTER: `7ca335e64ee11f7f5bc994773972448e7e6d16774f7e7526d1bce4853e54dda1`.

Fixture SHA-256:

- P1: `94303b07b16af882edf3d064e4f9de7dac7ce72b28c53b135173804488169ac0`.
- P3: `43582e688266c8b2c5ab2189b819255f17020daef77c27a4033b1448a1d8bffa`.

`baseline-*` и `metadata-*` receipt/provenance/harness/Package/run/provenance-script/original-readme файлы — переименованные **побайтовые копии** исходных внешних артефактов. `metadata-delivery.json` связывает прежний путь, новый filename, размер и hash. Исторические scripts сохраняют старую структуру `/tmp`; для запуска из checkout используйте переносимый runner ниже.

Полный пакет, fixtures и caches сюда не копируются. Для точного восстановления AFTER сохранены только tracked diff и семь новых файлов в lossless gzip. Delivery manifest содержит hashes и сжатых bytes, и исходных bytes; `metadata-source-snapshot.json` фиксирует каждый из 60 файлов. Runner восстанавливает их из base commit **в памяти** и сверяет весь digest до создания внешнего build directory. Поэтому исторический AFTER воспроизводим без подмены его финальным commit.

## Повторить проверку

Из корня репозитория, без записи файлов и компиляции:

```bash
python3 docs/review/2026-11-16/performance/metadata-reprofile.py --mode baseline --plan
python3 docs/review/2026-11-16/performance/metadata-reprofile.py --mode metadata --plan
```

Планы проверены: BEFORE восстанавливает 53 source files, AFTER — 60, оба полных digest совпадают. Проверены Python syntax и shell syntax исторических scripts. Переносимый runner после доставки еще не выполнял повторную полную компиляцию; исходные внешние harnesses реально собраны и замерены, их receipts приведены выше.

Для нового запуска нужна Swift 6 toolchain и новая пустая папка **вне checkout**:

```bash
python3 docs/review/2026-11-16/performance/metadata-reprofile.py --mode baseline --output /tmp/grilla-baseline-repeat --swift-bin swift
python3 docs/review/2026-11-16/performance/metadata-reprofile.py --mode metadata --output /tmp/grilla-metadata-repeat --swift-bin swift
```

Чтобы измерить опубликованный финальный commit вместо исторического AFTER, передайте `--source-ref <полный-SHA>` в metadata mode. Runner прочитает только committed source; незакоммиченные правки текущего checkout не попадут в этот результат. Требуются API `listSummaries()`/`summary(id)`; старый commit без них будет отклонен.

Новые receipt/log/provenance записываются только во внешний output. Receipt-only constants адаптируются под фактические Swift/architecture/source status; отдельный hash фиксирует скомпилированную копию harness. Операции, число samples и assertions сохраняются. Исторические receipts и исходные `/tmp` артефакты runner не изменяет.

## Измеренный Stop в Simulator, source fefa036

[Оригинальное наблюдение с lossless-payload provenance](native-stop-sample.json) восстановлено из full run [43879719282](https://github.com/alexgazin/la-grilla/actions/runs/43879719282), artifact `ios-verification`14236480842 (102125974bytes). Весь run **CANCELLED** при переходе к исправленной версии; owning method `AuthorizedMicrophoneTests/testGrantedSpeechCallbackAndOutputOnlyAssistantRemainUsable` успел завершиться **PASS,118.491s**. Связь payloadRef с исходным activity/test summary и SHA записана в JSON.

Один настоящий sample: Stop synchronous376.058ms; cleanup375.913ms, из них tap removal1.333ms, serial worker drain0.0378ms, output restoration374.511ms. Это elapsed wall-clock, не CPU time. В этом sample многосекундная блокировка workerDrain не наблюдалась; основная цена — восстановление I/O. По нему нельзя обещать phone latency или переносить AVAudioEngine на произвольную очередь.

Speech получил919426реальных PCM frames, оба разрешения предоставлены; результат NoSpeech1110. Успешная человеческая транскрипция, hardware gap/indicator и полный software gate не заявляются.
