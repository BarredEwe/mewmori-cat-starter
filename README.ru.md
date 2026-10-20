# Mewmori Cat Starter

[English](README.md) | **Русский**

Маленькая рабочая отправная точка, чтобы встроить локальную языковую модель на 2 миллиарда параметров и живого персонажа в своё приложение для Apple. Репозиторий сопровождает два доклада Максима Гришутина про [Mewmori](https://mewmori.com) - пиксельного кота, который живёт на рабочем столе macOS и разговаривает через модель на устройстве:

- **«Кот на 2 миллиарда параметров»** (Mobius): как встроить маленькую LLM в приложение, заставить её держать роль и доказать это бенчмарком, а не на глаз;
- **«Делаем умного кота, который видит экран»** (Podlodka iOS Crew): Vision OCR, разметка по координатам и короткий дайджест для маленькой модели.

Это не копия Mewmori. Каждая часть - самая маленькая версия одного механизма из докладов, которую можно прочитать за вечер и развивать дальше.

## Что внутри

| Таргет | Платформа | Что показывает |
| --- | --- | --- |
| `CatPocketCore` | iOS, macOS | Чат на голом C API llama.cpp: шаблон чата, цепочка сэмплеров, стоп по законченным предложениям, персона кота и бенчмарк «кто есть кто» на 10 кейсов |
| `CatPocket` | iOS | Тот же кот в кармане: модель скачивается один раз, дальше чат и вкладка **Бенч** с процентом прохода, ток/с, временем разбора промпта и physical footprint |
| `CatBench` | macOS CLI | Тот же бенчмарк из терминала |
| `CatStarter` | macOS-приложение | Слоёный риг на SpriteKit: анимация как дельты от позы покоя, взгляд за курсором, валидатор и автоматический OCR экрана за дешёвым сторожем 32×32 |
| `CatInferenceDemo` | macOS CLI | Vision OCR → геометрический дайджест → одна локальная реплика модели |

## Замеры

Qwen 3.5 2B (`UD-Q4_K_XL`, 1,3 ГБ), встроенный бенчмарк, 50 генераций:

| | iPhone 16 Pro Max | MacBook Pro M3 Max |
| --- | --- | --- |
| проход | 86% | 86% |
| генерация | 19 ток/с | 93 ток/с |
| разбор промпта | 0,67 с | 0,11 с |
| physical footprint | 191 МБ | 321 МБ |
| загрузка модели | 1,4 с | |

С одинаковыми сидами модель отвечает одинаково на обоих устройствах, вплоть до тех же ошибок. Промпт можно отлаживать на Mac, а проверять на телефоне одной кнопкой.

## Быстрый старт

Нужны macOS 14+, Xcode 16+ и [XcodeGen](https://github.com/yonaskolb/XcodeGen), если меняете `project.yml`. Весов модели в репозитории нет, GGUF скачивается один раз:

```sh
curl -L -o Qwen3.5-2B-UD-Q4_K_XL.gguf \
  https://huggingface.co/unsloth/Qwen3.5-2B-GGUF/resolve/main/Qwen3.5-2B-UD-Q4_K_XL.gguf
```

### Модель 2B в своём коде

```swift
import CatPocketCore

let chat = try LlamaChat(modelPath: "/path/to/Qwen3.5-2B-UD-Q4_K_XL.gguf")
let persona = CatPersona(catName: "Томас", userName: "Максим")
let reply = try chat.generate(persona.messages(history: [.user("Как дела?")]))
print(reply.text, reply.tokensPerSecond)
```

### Бенчмарк на Mac

```sh
swift run -c release CatBench /path/to/Qwen3.5-2B-UD-Q4_K_XL.gguf 5
```

### Кот на iPhone

1. Впишите свою команду в `project.yml` (`DEVELOPMENT_TEAM`) и выполните `xcodegen generate`.
2. Откройте `CatStarter.xcodeproj`, выберите схему `CatPocket` и реальное устройство. Симулятор не подходит: в xcframework llama.cpp нет слайса под него.
3. Запустите. Приложение один раз скачает модель, дальше откроются чат и вкладка **Бенч**.

Замер без нажатий: запустите приложение с аргументом `-autoBench 5`, отчёт появится в `Documents/bench.json` контейнера приложения:

```sh
xcrun devicectl device process launch --device <id> com.barredewe.CatPocket -- -autoBench 5
xcrun devicectl device copy from --device <id> --domain-type appDataContainer \
  --domain-identifier com.barredewe.CatPocket --source Documents/bench.json --destination bench.json
```

Модель можно не качать на телефоне, а скопировать с Mac:

```sh
xcrun devicectl device copy to --device <id> --domain-type appDataContainer \
  --domain-identifier com.barredewe.CatPocket --source Qwen3.5-2B-UD-Q4_K_XL.gguf \
  --destination "Library/Application Support/Models/Qwen3.5-2B-UD-Q4_K_XL.gguf"
```

### Кот на рабочем столе

Откройте `CatStarter.xcodeproj`, выберите схему `CatStarter` и `My Mac`, нажмите `⌘R` или выполните `swift run CatStarter`. Зрачки следят за курсором, а кот иногда ходит. При первом запуске macOS попросит разрешение Screen Recording для OCR.

### OCR и модель из терминала

```sh
swift run CatInferenceDemo /path/to/model.gguf /path/to/screenshot.png
swift run CatInferenceDemo --ocr-only /path/to/screenshot.png
```

Без пути к картинке команда снимет основной дисплей.

## Приёмы для маленькой модели - и где они в коде

- **Роль сообщения сильнее текста.** Модель на 2B путает, кто говорит: кот, человек, экран, память. Имя человека лежит полем рядом с именем кота в `<state>`, а не абзацем (`CatPersona.swift`).
- **Правило и пример работают только вместе.** В замерах к докладу одно правило ухудшило ответ на «Как меня зовут?» → «Я Максим», а правило и один пример исправили. Пример уходит парой сообщений user/assistant перед историей, а не текстом внутри инструкции.
- **Длина - параметр генерации, а не просьба.** Генерация останавливается сразу после N-го законченного предложения (`Sentences.completedCount` в `LlamaChat.swift`); лимит токенов - только страховка.
- **Недоверенный ввод экранируется, а не уговаривается.** Текст экрана уходит в экранированный `<screen_context>` (`CatOCR`, `CatInferenceDemo`).
- **Дешёвая проверка сторожит дорогую.** OCR запускается, только когда заметно меняется серая миниатюра 32×32 (`ScreenThumbnail` и `ScreenChangeDetector` в `CatOCR/ScreenOCR.swift`).
- **Бенчмарк растёт из багов.** Каждый кейс в `PocketBench.swift` - прошлый провал, и проверяет его код, а не эталонный ответ.

## Тесты

```sh
swift test
xcodebuild -project CatStarter.xcodeproj -scheme CatStarter -destination 'platform=macOS' test
```

UI-тесты запускают настоящее окно. При первом прогоне macOS попросит разрешить XCTest управлять компьютером.

## Структура

```text
Sources/CatPocketCore     чат на llama.cpp, персона, бенчмарк на устройстве
Sources/CatPocket         iOS-приложение
Sources/CatBench          бенчмарк из терминала
Sources/CatStarter        риг на SpriteKit, анимация, валидатор, окно macOS
Sources/CatOCR            Vision OCR и дайджест экрана
Sources/CatInferenceDemo  OCR и модель из терминала
Tests, UITests            unit- и UI-тесты
project.yml               описание CatStarter.xcodeproj для XcodeGen
```

В [`PRESENTATION_EVIDENCE.md`](PRESENTATION_EVIDENCE.md) каждый тезис докладов связан с кодом и тестом, которые его подтверждают, и перечислено, чего в стартере намеренно нет по сравнению с настоящим приложением.

## Лицензия

Код - [MIT](LICENSE). Спрайты кота в `Sources/CatStarter/Resources/Art` - арт Mewmori, они лежат здесь, чтобы демо запускалось; пожалуйста, не используйте их в своём продукте.
