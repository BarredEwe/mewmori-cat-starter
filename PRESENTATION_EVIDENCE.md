# Что именно подтверждает Cat Starter

Этот файл связывает тезисы двух презентаций с исполняемым кодом и тестами.
Starter подтверждает выбранные механизмы, а не заявляет полную функциональную
эквивалентность Mewmori.

## «Кот на 2 миллиарда параметров» (Mobius)

| Тезис презентации | Доказательство в starter | Проверка |
| --- | --- | --- |
| Готовая Swift-обёртка над llama.cpp, локальный GGUF, контекст 2048 | `Package.swift`, `Sources/CatInferenceDemo/LocalCatModel.swift` | `swift build` подтверждает интеграцию. Весов в Git нет, поэтому реальный ответ Qwen автоматически не проверяется. |
| Кот собран из частей и суставов в design units | `Resources/rig.json`, `Rig.swift`, `CatScene.buildNodes()` | Запуск приложения строит иерархию до первого кадра. |
| Анимации - дельты от rest pose | `Resources/clips/*.json`, `Animation.swift` | `testTrackClampsToTheLastKey`, `testPoseAddsOverlayDeltas` |
| Дыхание и моргание складываются до единственной записи в SpriteKit-узлы | `composePose`, `CatScene.update()` | `testPoseAddsOverlayDeltas` проверяет сумму `0.035 + 0.02 = 0.055`. |
| Взгляд следует за курсором | `rig.json:gaze`, `CatScene.mouseMoved()` | Проверяется интерактивно после `⌘R`. |
| Ошибки данных ловит валидатор | `Validator.swift` | `testValidatorReportsUnknownParentAndCycle` |
| Персона и задача разделены; экран - недоверенные данные | `CatInferenceDemo/main.swift`, `Resources/prompt-examples.md` | Код формирует отдельные `persona`, `task` и экранированный `<screen_context>`. |
| Перед дорогим OCR стоит дешёвый сторож 32×32 с допуском 3 | `ScreenThumbnail`, `ScreenChangeDetector` | `testThumbnailIgnoresTinyChangeButNotWidespreadChange` |

## «Делаем умного кота, который видит экран» (Podlodka iOS Crew)

| Тезис презентации | Доказательство в starter | Проверка |
| --- | --- | --- |
| Vision использует `.accurate`, языковая коррекция выключена | `ScreenOCR.recognizeLines()` | `testVisionOCRReadsGeneratedText` вызывает настройки по умолчанию. |
| Vision возвращает строки и bounding boxes; координаты приводятся к началу слева сверху | `RecognizedLine`, `ScreenOCR.recognizeLines()` | `testDigestUsesGeometryFiltersChromeAndEscapesScreenText` подаёт строки с координатами. |
| Строки читаются сверху вниз, на одной высоте - слева направо | `ScreenDigest.ordered()` | Тот же unit-тест проверяет порядок через итоговый документ. |
| Очевидный chrome убирается до модели | `ScreenDigest.chromeLabels`, `ScreenDigest.isUseful()` | Тест подтверждает удаление строки «Поиск». |
| Крупная строка помечается как heading | `ScreenDigest.make()`; порог `median × 1.25` | Тест подтверждает роль `heading` для `Mewmori`. |
| Маленькая модель получает короткий документ вместо полного OCR | `ScreenDigest.maxCharacters = 600`, `maxLines = 8` | Unit-тест проверяет бюджет; CLI передаёт именно дайджест. |
| Текст экрана не становится инструкцией | `ScreenDigest.escaped()`, правило в `persona` | Unit-тест проверяет экранирование `<` и `>`. |
| OCR запускается автоматически, повторное чтение проходит через сторож | `AppDelegate.observeScreen()`, таймер 15 секунд | `testCatObservesScreenWithoutAButton`; логика сторожа покрыта unit-тестом. |

## Что намеренно не заявляется

В starter нет production-функций, показанных в Podlodka: захвата только
активного окна через ScreenCaptureKit, сигнала пользовательского ввода,
нескольких регионов экрана, отдельного chat reader, модельного классификатора
чувствительности, grammar-constrained JSON, проверки groundedness и двух
последовательных запросов к Qwen. Их источником остаётся основной репозиторий
Mewmori; этот starter показывает минимальный путь
`изменение → Vision → геометрический дайджест → одна локальная реплика`.

## Команды проверки

```sh
swift test

xcodebuild \
  -project CatStarter.xcodeproj \
  -scheme CatStarter \
  -destination 'platform=macOS' \
  test
```
