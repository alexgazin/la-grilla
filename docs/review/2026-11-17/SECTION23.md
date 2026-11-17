# Сборка23 — наблюдение playback-state после перестановки

## Фактический полный результат main82

Исходник `82e4dfb02d2016dcbe31e7b34af6cd09b0f0457a`, [run44120318741, native attempt2](https://github.com/alexgazin/la-grilla/actions/runs/44120318741/attempts/2), job134181279988: все73 обязательных исходных method identifiers наблюдались; **71PASS / 2FAIL / 0allowance**, child/supervisor65, timedOut=false,3227.618s. Один opt-in diagnostic SKIP находится вне функциональных73. Приёмка полного набора корректно отклонена. SDK4 прошли на исходной attempt1; свежая IPA main82 статически проверена, но остаётся ручной альфой.

Исходная native attempt1 не получила hosted runner и не исполнила ни одного шага/теста. Повторено только это не начавшееся native-задание. Успешные SDK/archive не повторялись; их перенесённые metadata IDs не считаются новыми исполнениями.

[Оригинальный итоговый bundle14350664249](https://github.com/alexgazin/la-grilla/actions/runs/44120318741/artifacts/14350664249):322167599bytes,SHA-256 `327058874feaae9f3ee4a74c98bd831e4d4bdcc0e1b82e1a8a23868cb1738a50`,CRC2061PASS. Tiny scope14351587723:2997bytes,SHA-256 `2801cea78467c5414f9c752dd9c58d06b4a27480b5a2132acb31a53fcaa3c32b`. Оригиналы скачаны и проверены; прежние failed исходы сохраняются.

## Перестановка: условие уже видно во время неуспешного ожидания

`LiveEditingTests/testDuplicateMoveAndDeleteSectionDuringPlayback`,63.875s: duplicate и первое PLAYING прошли; реальный Move earlier на40.55s, правильный новый порядок подтверждён на42.82s. Следующий KVC predicate `label == PLAYING` не завершился в прежнем окне45.66–49.69s.

Оригинальная диагностическая запись `7FD840CB-3C1C-4612-8B48-00D63866B26B.mp4`,SHA-256 `cfa5de9bfaaa250cedd06f6895a1c2024575b92db2346bfdc7de60a6b0a2a5fa`, начинается на0.057s позже testcase. Неизменённые кадры видео47.0s и49.2s соответствуют case47.057s/49.257s, оба внутри неуспешного окна: видны Chorus1–4,Verse5–8 и PLAYING. Подлинный AX attachment `F9359F34-201D-41CD-A83A-711BF996E70C.txt` на60.91s также содержит actual `section.playback-state=PLAYING`,frame(20,431.3,400,52), нижний `perform.transport=08:3,PLAYING` и настоящий Stop. AX-файл17947bytes,SHA-256 `2b42ddafb6b14290c7e64d5534b13348afbbd2e3d379045b2bd2fabc872edac0`.

Это подтверждает дефект чтения состояния тестом, а не остановку аудио при Move earlier. Production-путь move→Session.edit/sync→audio.submit не содержит stop/seek; UUID выбранного Verse сохраняется, диапазон лупа становится4..<8bars, kernel adopt/resetCursor сохраняет active. Акустическая непрерывность не измеряется по надписи или кадрам и здесь не заявляется.

## Следующий Pad-сценарий не дошёл до пэдов

`PadTouchUITests/testContactEnqueuesBeforeReleaseAndHoldDoesNotRetrigger`,70.958s: уже на0.50s app.launch пытался завершить предыдущий LiveEditing PID49770. Примерно через60s XCTest сообщил `Failed to terminate …49770`. Ни Pad UI, ни контакт, ни счётчик enqueue/hold не выполнялись. Следующий Sliding-case запустил новый PID50880 и прошёл реальные контакты.

Причина termination IPC/жизненного цикла не установлена. Исходный native-device.log начинается16:56:32, позже обоих сбоев; CrashReports не собраны. Fresh DragUI-preflight ready=true,15.097s,PID8452/listening16:22:35.727;17 supervisor controls PASS10.151s. Нет основания подменять этот failure неполадкой Druid, пэдов или доказанным падением приложения.

## Точечная правка и следующий обязательный результат

Изменён только UITests playing-helper: существующее ожидание existence5s сохранено; следующее прежнее5s окно читает свежий native snapshot в каждом poll и требует настоящие staticText,тот же непустой identifier и точный PLAYING. Отсутствующий/неверный/недоступный узел остаётся ошибкой; diagnostics содержат фактически наблюдённые ID/type/label/value и hierarchy. Все исходные тела, действия, reorder/count/delete, успешный завершающий Stop, остальные helpers и180s лимит сохранены. Независимый обзор, Swift parse и проверка неизменности остальных байтов прошли. App/DSP/Pad/teardown не менялись.

Следующая проверка — один свежий coherent **full73** на новом exact main-source, включая этот LiveEditing и следующий PadContact подряд в исходном контексте полного набора. Нет дополнительного дублирующего focused-прогона, новых фильтров, повышения лимитов или удаления утверждений. Runtime-успех ещё Pending. Main82 сохраняет свой71/73 FAIL; hardware и Store остаются отдельными Pending. Новое промовидео не создаётся.
