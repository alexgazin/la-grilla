# Оригинальные экраны22 · контакт и звук

Пять неизменённых PNG работающего iPhone16ProMax Simulator. Ночная тема. Каждый кадр принадлежит фактически прошедшему методу; оригинальные имена вложений, bytes и SHA-256 сохранены в отдельных манифестах.

| Экран | Файл | Источник |
| --- | --- | --- |
| Пэды/видимая кнопка звука | [pads.png](pads.png) |60c24ce,PadTouch contact/hold PASS |
| Прослушивание Warm kit | [sound-warm-preview.png](sound-warm-preview.png) |60c24ce,actualPCM/Cancel PASS |
| Bright kit после fresh reopen | [sound-bright-reopened.png](sound-bright-reopened.png) |60c24ce,Apply/Undo/store PASS |
| Пэды и транспорт в landscape | [landscape-jam.png](landscape-jam.png) |60c24ce,reachability PASS |
| Растянутая нота/рукоятка после release | [piano-resized-note.png](piano-resized-note.png) |aded2ff,resize/count/обаUndo PASS |

[Source60c24ce manifest](source-60c24ce-manifest.json):run44033597734 завершился9PASS/1locale-format assertionFAIL. [Sourceaded2ff manifest](source-aded2ff-manifest.json):run44036545312 исполнил ровно один исходный resize-case,1PASS,81.274s. Product-файлы этих исходников и исходного main22 совпадают; **это не свежий весь10/73 и не аппаратная приёмка**.

Кадр ноты снят после commit1440ticks и доUndo. Сам прошедший метод затем проверилUndo480 и следующийUndo count0. Непрерывный preview отдельно просмотрен на оригинальном видео60c24ce с тем же product-кодом; его весь метод завершился ошибкой тестового ожидания форматирования. Это видео не переименовывается в PASS/promo.

PNG не обрезались, не перекрашивались и не масштабировались. Встроенная orientation metadata landscape сохранена. Реальные датчики Tilt, палец→динамик, голос, маршруты и Store-готовность этими кадрами не измерялись.
