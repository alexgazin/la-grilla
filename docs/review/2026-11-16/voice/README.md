# Voice-to-MIDI: исправление границ и отклонённые гипотезы

Это продолжение W4 из [плана аудита](../PLAN.md). Исправлена конкретная ошибка переноса голоса на сетку. Изменение точности распознавания человеческих нот **не заявляется**: detector, segmentation и их временные пороги сохранены.

## Что исправлено в приложении

`VoiceAnalyzer.notes` раньше ограничивал начало через `length-grid`. При take короче выбранной сетки это давало отрицательный tick. При незавершённой последней клетке создавался off-grid onset: для length 1000/grid 480 получалось 520 вместо 960.

Теперь начало ограничено последней настоящей линией сетки внутри take; конец обрезается по реальной границе. Короткий take 128 ticks с grid 480 получает допустимую ноту `[0,128)`, без выхода за секцию и без выдуманного смещения. Quantization off, исходный CAF, pitch/confidence, ручная коррекция и placement offset не меняются.

**Проверено:** targeted **21 Swift tests PASS**, включая четыре новых `VoiceNoteProjectionTests` (один параметризован девятью границами): short take, partial tail, offset loop, настоящий deterministic synthetic CAF → анализ → Apply → store/reopen → одна Undo/Redo с неизменными source bytes. Это synthetic/domain evidence, не захват на телефоне. Первый build тестов остановился до исполнения из-за синтаксиса параллельно добавлявшегося SketchComposerTests; после исправления владельцем набор собран и завершён.

## Фактический контроль на записанном голосе

Обычный production `Tools/VoiceBenchmark` дважды запущен offline в release Swift 6.1.2/Linux на фиксированных development IDs **1–8** Vocadito. Все 34 исходных corpus members проверены pinned SHA/размером. Анализ: первые `min(30 s, duration)`, mono PCM16 44.1 kHz → Float32, 120 BPM/PPQ 960, quantization off, без scale projection.

До и после совпали **все track reports**, включая **18 329 F0 frames, segments и 587 unquantized notes**. Per-track canonical hashes и exact comparisons записаны в [production-equivalence.json](production-equivalence.json). Raw `.analysis.json` остаются вне Git; их пути, размеры и SHA сохранены. Единственная различающаяся глобальная величина вне reports — время вычисления.

| Показатель | До | После projection fix |
| --- | ---: | ---: |
| Confidence-qualified F0 accuracy | 95.88% | 95.88% |
| Note onset+pitch F1, A1 / A2 | 60.28% / 54.95% | 60.28% / 54.95% |
| Note onset+pitch+offset F1, A1 / A2 | 42.76% / 38.36% | 42.76% / 38.36% |
| Predicted notes | 587 | 587 |

Source identity: рабочий music-completion checkout поверх `fefa036ace0e10713689a8d22c3c0b69abfc0fbf`, с параллельными незакоммиченными музыкальными изменениями. Это **не exact-final-commit claim**. Оба протокола зафиксировали одинаковый Model hash `deafda1d…`; Voice hash изменился с `40d37169…` на `db35f836…`. Core source/harness/manifest hashes проверены до/после каждого запуска. Сжатые побайтовые копии двух VoiceAnalyzer сохранены для проверки диффа; полного immutable package snapshot эти эксперименты не объявляют.

## Почему segmentation не изменена

Диагностика development-данных выявила два противоположных вида ошибок: 106/A1 и 131/A2 unmatched начал попадали внутрь референсной ноты того же pitch; 46/A1 и 29/A2 реартикуляций оказывались внутри одной предсказанной ноты. Это признаки fragmentation/merging относительно двух разных человеческих аннотаторов, а не абсолютная классификация всех ошибок.

Проверены **две заранее описанные гипотезы** на неизменных production frames. До scoring каждой сохранены её protocol/guards. Минимум: mean A1/A2 onset+pitch F1 +1 процентный пункт; регрессия каждого annotator/strict F1 не более 0.1 п.п.; далее per-track и synthetic проверки. После провала раннего guard поздние проверки не использовались для оправдания кандидата.

| Offline-гипотеза | Onset+pitch F1 A1 / A2 | Strict F1 A1 / A2 | Решение |
| --- | ---: | ---: | --- |
| Production control | 60.28% / 54.95% | 42.76% / 38.36% | Сохранён |
| Объединить только короткий discarded semitone island между стабильными одинаковыми pitch | 60.66% / 54.84% | 43.57% / 39.35% | Отклонена: mean +0.139 п.п.; A2 ухудшился более чем на 0.1 п.п. |
| Разделить стабильный pitch по глубокой RMS-впадине с новым attack | 60.73% / 55.47% | 43.49% / 38.77% | Отклонена: mean +0.490 п.п., ниже +1 п.п. |

Ни одна из гипотез не включена в production source. Позднего изменения порога успеха не было. Небольшой development gain не объявляется generalization. Reserved holdout IDs **9–16: audio/annotations не открывались и не оценивались**.

## Артефакты и воспроизведение

`baseline-report.json.gz`, `projection-report.json.gz` — полные byte-preserving production metric reports; два candidate reports — полные raw development counts/F1 по tracks/A1/A2. Рядом лежат исходные протоколы, [решения](decisions.json), диагностический отчёт и [manifest SHA/размеров](manifest.json). Gzip lossless; corpus audio, reference annotations и processed PCM здесь отсутствуют.

Исходные материалы: Rachel M. Bittner et al. (2021), *vocadito*, v3, [DOI 10.5281/zenodo.5578807](https://zenodo.org/records/5578807), [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). Изменения — анализ первых 30 секунд, frame/note projection и offline hypotheses; raw источники не менялись. Полный протокол и исторический baseline: [VOICE_HUMAN_BASELINE.md](../../../VOICE_HUMAN_BASELINE.md).

Для нового production run из корня checkout, используя уже проверенный внешний corpus cache и Swift toolchain:

```bash
GRILLA_SWIFT_BIN=/path/to/swift python3 scripts/benchmark_human_voice.py --cache-dir /external/vocadito-cache --output /tmp/voice-new-run/report.json --scratch-dir /tmp/voice-new-run/swift
```

Если cache отсутствует, существующий benchmark требует явного `--download`; этот пакет ничего не скачивает автоматически. Новый run получает свои source/input/tool hashes и не наследует исторические числа.

Для replay двух **отклонённых** гипотез на настоящем production output:

```bash
python3 docs/review/2026-11-16/voice/reproduce_candidates.py --analysis /tmp/voice-new-run/report.analysis.json --cache-dir /external/vocadito-cache --output /tmp/voice-new-run/rejected-candidates.json
```

Runner принимает только IDs 1–8, проверяет cached members offline, сначала требует exact control reconstruction всех note ticks/durations/pitches и пишет только во внешний output. Параметры гипотез фиксированы, выбора holdout нет. Нужны зависимости из `Tools/VoiceBenchmark/requirements.txt`.

Остаются Pending: улучшение note segmentation, live human voice на установленном iPhone, акустический bleed, задержки/маршруты и заранее объявленная аппаратная/пользовательская приёмка. Полезный quantization fix не закрывает эти задачи.
