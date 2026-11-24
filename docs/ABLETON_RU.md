# Ableton Live и Ableton Link: что нужно от владельца

Сейчас La Grilla отдаёт проект в Ableton двумя путями, и оба работают без лицензий:

- **«Для DAW: стемы, MIDI, README»**: zip со стемами от первого такта, `song.mid` с темпом, тональностью и маркерами частей и инструкцией. Подходит для Ableton Live, Logic, GarageBand, FL Studio и Reaper.
- **DAWproject** (сборка 54): открытый формат проекта. Его читают Cubase 14, Studio One, Bitwig, а на iPad Cubasis 3.7 и n-Track. Ableton Live этот формат пока не читает.

Чтобы проект открывался в Live сразу как Live Set (`.als`) и чтобы работала синхронизация темпа по Wi‑Fi (Ableton Link), нужны две лицензии Ableton и одно разрешение Apple. Получить их может только владелец приложения.

## 1. Ableton Live Set Export SDK (файлы `.als`)

1. Откройте https://www.ableton.com/en/link/sdk/license-request/ (форма запроса SDK).
2. Укажите почту своего аккаунта Ableton и имя пользователя GitHub (`alexgazin`).
3. Выберите Live Set Export SDK и примите лицензию.
4. Когда Ableton откроет доступ к репозиторию SDK, напишите мне. Я подключу экспорт `.als` к окну «Экспорт».

## 2. Ableton Link (синхронизация темпа)

1. В той же форме запросите **Link SDK для iOS (LinkKit)** и примите лицензию. Открытая версия Link распространяется по GPL и в App Store не подходит, поэтому нужна именно лицензия Ableton.
2. Для поиска других устройств в сети Apple требует разрешение `com.apple.developer.networking.multicast`. Его запрашивают в аккаунте Apple Developer: https://developer.apple.com/contact/request/networking-multicast . Нужен платный аккаунт: при бесплатной подписи через Sideloadly Link работать не будет.
3. Когда будут LinkKit и разрешение, я подключу Link к транспорту: общий темп, старт на первой доле, кнопка Link в настройках по правилам Ableton.

## Что не требует лицензий и уже есть

- MIDI Clock на выход (синхронизация с драм-машинами и DAW по MIDI).
- Стемы, MIDI и DAWproject.
