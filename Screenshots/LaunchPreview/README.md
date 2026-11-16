# Сплеш La Grilla · нативное QA-превью

Три оригинальных PNG **1.0.0 (17), schema 8**, source `29adf6c398173faf830de8f6249702628b8a3f76`, iPhone 16 Pro Max Simulator, 1320 × 2868. Байты сохранены без ресайза, ретуши и генерации.

| Тёмная тема · EN | Светлая тема · EN | Крупный текст · RU / Reduce Motion |
| --- | --- | --- |
| [![Dark](dark-en.png)](dark-en.png) | [![Light](light-en.png)](light-en.png) | [![Русский](dark-ru-large-reduced-motion.png)](dark-ru-large-reduced-motion.png) |

Это тот же SwiftUI `AppStartView`, удержанный параметром `--uitesting --splash-preview` после настоящего bootstrap. Кадры показывают компонент загрузки, **не** системный статический launch screen и **не** длительность холодного запуска. В обычном приложении искусственного минимального ожидания нет. У RU-кадра Reduce Motion задан явным QA override; системное значение записано отдельно.

[Нативный запуск 43870504379](https://github.com/alexgazin/la-grilla/actions/runs/43870504379): метод `SplashScreenTests/testBrandedLoadingPreviewAndRealStartupPreserveOnboarding()` — **PASS, 41.777 s**; он также прошёл настоящий обычный запуск, Welcome → Skip и повторный запуск. Весь workflow завершился ошибкой: 5 PASS, два других UI-метода превысили allowance. Эти кадры не означают приёмку всех семи сценариев, физического iPhone или производительности запуска.

Каждый кадр просмотрен: композиция помещается, текст не перекрывается; крупный русский статус переносится на две строки, слоган скрыт для размещения. [Манифест с SHA-256, исходными именами и связью с методом](manifest.json) и [неизменённый нативный receipt](native-observations.txt) сохраняют происхождение.
