<p align="center">
  <a href="https://mewmori.com/en/">
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset="docs/images/logo-dark.svg">
      <img src="docs/images/logo.svg" alt="Mewmori" width="360">
    </picture>
  </a>
</p>

<h1 align="center">Mewmori Cat Starter</h1>

<p align="center"><b>English</b> · <a href="README.ru.md">Русский</a><br>
<a href="https://mewmori.com/en/">mewmori.com</a></p>

<p align="center"><img src="docs/images/cats.png" alt="Mewmori cats from the shop sets" width="600"></p>

A small, buildable starting point for putting a local 2B language model and a living character into your own Apple app. It accompanies two talks by Maksim Grishutin about [Mewmori](https://mewmori.com/en/), a pixel cat that lives on the macOS desktop and talks through an on-device model:

- **"A Cat with 2 Billion Parameters"** (Mobius): how to embed a small LLM in an app, make it keep a role, and prove it with a benchmark instead of by eye;
- **"Building a smart cat that sees your screen"** (Podlodka iOS Crew): Vision OCR, layout from coordinates, and a short digest for a small model.

This is not a copy of Mewmori. Each part is the smallest version of one mechanism from the talks that you can read in an evening and build on.

## The real app

Everything here is cut out of [Mewmori](https://mewmori.com/en/), a desktop cat for macOS. It watches the cursor, reads the active window, remembers what you told it, and talks through the same 2B model, fully offline.

<p align="center">
  <img src="docs/images/hello.gif" alt="The cat greets the user on the desktop" width="32%">
  <img src="docs/images/remembers.gif" alt="The cat remembers what the user said" width="32%">
  <img src="docs/images/skins.gif" alt="The cat changes skins" width="32%">
</p>

Download the app and see the full version at **[mewmori.com](https://mewmori.com/en/)**.

## What's inside

| Target | Platform | What it shows |
| --- | --- | --- |
| `CatPocketCore` | iOS, macOS | A chat on the raw llama.cpp C API: chat template, sampler chain, stop on finished sentences, a cat persona, and a 10-case "who is who" benchmark |
| `CatPocket` | iOS | The same cat in your pocket: one-time model download, chat, and a **Bench** tab with pass rate, tokens/s, prompt time and physical footprint |
| `CatBench` | macOS CLI | The same benchmark from the terminal |
| `CatStarter` | macOS app | A layered SpriteKit rig: animation as deltas from the rest pose, eyes following the cursor, a validator, and automatic screen OCR behind a cheap 32×32 change detector |
| `CatInferenceDemo` | macOS CLI | Vision OCR → geometric digest → one local reply from the model |

## Measured

Qwen 3.5 2B (`UD-Q4_K_XL`, 1.3 GB), the bundled benchmark, 50 generations:

| | iPhone 16 Pro Max | MacBook Pro M3 Max |
| --- | --- | --- |
| pass rate | 86% | 86% |
| generation | 19 tok/s | 93 tok/s |
| prompt processing | 0.67 s | 0.11 s |
| physical footprint | 191 MB | 321 MB |
| model load | 1.4 s | |

<p align="center">
  <img src="docs/images/iphone-bench.jpg" alt="Bench tab on iPhone: pass rate, speed, footprint" width="260">
  <img src="docs/images/iphone-cases.jpg" alt="Bench cases on iPhone" width="260">
</p>

With the same seeds the model answers the same on both devices, failures included. Debug your prompt on the Mac and confirm it on the phone with one tap.

## Quick start

Requirements: macOS 14+, Xcode 16+, [XcodeGen](https://github.com/yonaskolb/XcodeGen) if you change `project.yml`. Model weights are not in the repository. Download the GGUF once:

```sh
curl -L -o Qwen3.5-2B-UD-Q4_K_XL.gguf \
  https://huggingface.co/unsloth/Qwen3.5-2B-GGUF/resolve/main/Qwen3.5-2B-UD-Q4_K_XL.gguf
```

### A 2B model in your own code

```swift
import CatPocketCore

let chat = try LlamaChat(modelPath: "/path/to/Qwen3.5-2B-UD-Q4_K_XL.gguf")
let persona = CatPersona(catName: "Tom", userName: "Max")
let reply = try chat.generate(persona.messages(history: [.user("How are you?")]))
print(reply.text, reply.tokensPerSecond)
```

The persona writes in Russian by default; change the language line in `CatPersona.system`.

### Benchmark on the Mac

```sh
swift run -c release CatBench /path/to/Qwen3.5-2B-UD-Q4_K_XL.gguf 5
```

### The cat on your iPhone

1. Set your Apple team in `project.yml` (`DEVELOPMENT_TEAM`) and run `xcodegen generate`.
2. Open `CatStarter.xcodeproj`, pick the `CatPocket` scheme and a real device. The simulator does not work: the llama.cpp xcframework has no simulator slice.
3. Run. The app downloads the model once, then opens the chat and the **Bench** tab.

To measure without tapping, launch with `-autoBench 5`; the report lands in `Documents/bench.json` inside the app container:

```sh
xcrun devicectl device process launch --device <id> com.barredewe.CatPocket -- -autoBench 5
xcrun devicectl device copy from --device <id> --domain-type appDataContainer \
  --domain-identifier com.barredewe.CatPocket --source Documents/bench.json --destination bench.json
```

You can also copy the model from the Mac instead of downloading it on the phone:

```sh
xcrun devicectl device copy to --device <id> --domain-type appDataContainer \
  --domain-identifier com.barredewe.CatPocket --source Qwen3.5-2B-UD-Q4_K_XL.gguf \
  --destination "Library/Application Support/Models/Qwen3.5-2B-UD-Q4_K_XL.gguf"
```

### The desktop cat

Open `CatStarter.xcodeproj`, pick the `CatStarter` scheme and `My Mac`, press `⌘R`, or run `swift run CatStarter`. The pupils follow the cursor and the cat walks now and then. On the first launch macOS asks for Screen Recording permission for the OCR part.

### OCR + model from the terminal

```sh
swift run CatInferenceDemo /path/to/model.gguf /path/to/screenshot.png
swift run CatInferenceDemo --ocr-only /path/to/screenshot.png
```

Without an image path the command captures the main display.

## Small-model tricks, with the code

- **Roles beat text.** A 2B model mixes up who is speaking: the cat, the user, the screen, memory. The user's name lives as a field next to the cat's in `<state>`, not in a paragraph (`CatPersona.swift`).
- **Rule and example work only together.** In the talk's measurements a rule alone made "What's my name?" → "I'm Max" worse; a rule plus one example turn fixed it. The example goes as a user/assistant pair before the history, not as text inside the instructions.
- **Length is a generation setting, not a request.** Generation stops right after the N-th finished sentence (`Sentences.completedCount` in `LlamaChat.swift`); the token limit is only a safety net.
- **Untrusted input is escaped, not asked nicely.** Screen text goes into an escaped `<screen_context>` (`CatOCR`, `CatInferenceDemo`).
- **A cheap check guards an expensive one.** OCR runs only after a 32×32 grayscale thumbnail changes noticeably (`ScreenThumbnail` and `ScreenChangeDetector` in `CatOCR/ScreenOCR.swift`).
- **The benchmark grows from bugs.** Every case in `PocketBench.swift` is a past failure, checked by code, not by a reference answer.

## Tests

```sh
swift test
xcodebuild -project CatStarter.xcodeproj -scheme CatStarter -destination 'platform=macOS' test
```

The UI tests launch the real window. macOS asks once to allow XCTest to control the computer.

## Layout

```text
Sources/CatPocketCore     llama.cpp chat, persona, on-device benchmark
Sources/CatPocket         iOS app
Sources/CatBench          benchmark CLI
Sources/CatStarter        SpriteKit rig, animation, validator, macOS window
Sources/CatOCR            Vision OCR and the screen digest
Sources/CatInferenceDemo  OCR + model CLI
Tests, UITests            unit and UI tests
project.yml               XcodeGen description of CatStarter.xcodeproj
```

[`PRESENTATION_EVIDENCE.md`](PRESENTATION_EVIDENCE.md) (in Russian) maps every claim from the talks to the code and test that backs it, and lists what the starter deliberately leaves out compared to the real app.

## License

Code: [Apache License 2.0](LICENSE). The cat sprites in `Sources/CatStarter/Resources/Art` and the images in `docs/images` are Mewmori artwork and are not covered by that license (see [NOTICE](NOTICE)); they are here so the demo runs and the README shows what it builds. Please do not ship them in your own product.

---

<p align="center">Made with a cat · <a href="https://mewmori.com/en/">mewmori.com</a> · <a href="https://t.me/prefire_ios">@prefire_ios</a></p>
