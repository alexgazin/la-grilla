# Mix History — измеренный метод, Linux

Это микробенчмарк `History`, **не задержка интерфейса, звука или iPhone**. Профилируется неизменяемая копия промежуточного рабочего исходника поверх `29adf6c`; точные хеши всех исходных файлов и digest сохранены отдельно. Позднейшие chord-rebuild/notation-правки не выдаются за измеренный source.

| Fixture / ноты | Полный `History.apply`, median / p95 | Первый `applyMix`, median / p95 | Повторный сертифицированный `applyMix`, median / p95 | Первый после Undo, median / p95 |
| --- | --- | --- | --- | --- |
| P1 / 768 | 1,704531 / 1,901447 мс | 1,730660 / 4,791919 мс | 0,000802 / 0,000951 мс | 1,640875 / 1,867625 мс |
| P3 / 16 384 | 39,133441 / 55,854370 мс | 38,126797 / 96,316401 мс | 0,001211 / 0,001623 мс | 36,511907 / 38,063387 мс |

В каждой ячейке 15 настоящих последовательных измерений после одного warmup, `DispatchTime.uptimeNanoseconds`, optimized Swift 6.1.2, Linux x86_64. Полный путь повторяет исходный архитектурный workload: новая `History`, исходная fixture, уменьшение gain дорожки 0 на 0,01 dB.

Повторный путь хранит один полностью проверенный Project value; это не доверие к UUID/revision. Все немикшерные поля сравниваются по значению, mix проверяет конечность и допустимые диапазоны. Общие COW-буферы музыки позволяют пропустить повторный обход всех событий. Отдельные domain-тесты проверяют отказы при изменении музыки/структуры, повреждённый baseline с прежней revision, Undo/coalesce и равенство реального MIDI/WAV.

Первый вызов на непроверенном исходнике и первый после Undo по-прежнему полностью проверяют проект. Их стоимость нельзя скрывать под быстрым повторным результатом. Из этих чисел нельзя заключить, что вся операция фейдера укладывается в кадровый бюджет телефона: `Session.sync`, компиляция, SwiftUI и аудиопубликация находятся вне этого измерения.

- [Все raw samples](mix-history-receipt.json).
- [Происхождение, SHA-256 файлов/fixtures, границы измерения](mix-history-provenance.json).
- [Digest и SHA-256 всех измеренных исходников](mix-history-source-snapshot.json).
- [Точный harness](MixHistoryProfile.swift) и [Package.swift того запуска](MixHistoryPackage.swift).

Для повторения создать отдельную папку Swift package: `MixHistoryPackage.swift` положить как `Package.swift`, harness — в `Sources/GrillaMixProfile/main.swift`, точный snapshot MusicDomain — в `source/MusicDomain`. Собирать `swift run -c release GrillaMixProfile <repo-root-with-fixtures> <receipt.json>`. Проверить digest исходников и SHA fixtures до запуска. Новый исходник или машина должны получить собственный receipt; исторические raw samples не переписываются.
