# Observation: повторное чтение History при публикации Project

Нативный resize-сценарий сборки21 на source `7e01f218` завершился настоящим Swift exclusivity abort. В `.ips` для PID11571, captureTime `2026-11-17 06:08:39.9195 +0000`, стэк показывает `Session.history.getter` из `PianoRollView.body` во время Observation `project.modify` внутри `Session.edit`. Ошибка AX была следствием завершения приложения.

[Host-отчёт](report.json) проверяет узкую причину на Linux, используя настоящий `MusicDomain.History` и `Project`. Скрипт извлекает текущий helper и методы из `App/Session.swift`; старый `edit` берётся из конкретного Git commit. Legacy child завершился **SIGABRT (-6)** с `Simultaneous accesses`; текущий child завершился **0**. Проверены edit, undo/redo, mix/music coalescing с одним Undo и rollback при ошибке валидации.

Это ручной, зависящий от workspace snapshot-repro, **не Apple SDK/typecheck, не native UI PASS и не новый обязательный CI gate**. Live performance, аудио, Voice и сохранение этим harness не проверяются. Их stub-ветки аварийно останавливают harness при неожиданном вызове.

## Повторение на Linux

Нужны полный Git object старого source, совместимые с компилятором уже построенные SPM objects `MusicDomain`/`AudioDSP` и Python. Для этого запуска использованы Swift6.1.2 и `/tmp/grilla-touch21-final-domain`.

```bash
python3 docs/review/2026-11-17/observation/reproduce.py \
  --repo /workspace/la-grilla-touch21 \
  --build /tmp/grilla-touch21-final-domain \
  --swiftc /workspace/tools/swift-6.1.2-RELEASE-ubuntu24.04/usr/bin/swiftc \
  --out /tmp/grilla-history-observation-repro
```

Укажите реальные пути своей машины. Стандартный `--legacy-source` закреплён на исходном pre-fix commit; скрипт не скачивает Git history. Внутренние поля Session и перечисленные функции должны соответствовать snapshot; последующие архитектурные изменения могут потребовать пересмотра harness.

Используется неизменённый `-static-stdlib`: packaged dynamic `libswiftObservation.so` этого Linux toolchain имел unresolved `swift::threading::fatal` при линковке. Это ограничение host toolchain, не дефект iOS-приложения. Вывод содержит большие статические бинарники и diagnostic logs; храните его вне репозитория. В этой папке намеренно лежат только скрипт, краткий отчёт и объяснение. Нативный resize/Undo-сценарий должен быть повторён отдельно на исправленном source.
