---
date: 2026-06-17
status: in progress
implements:
  - FR-FILE-OPEN
tags: [routing, apple-events, picker]
---
# Маршрутизация локальных HTML-файлов через пикер

## Goal

Двойной клик по локальному `.html`-файлу при назначенном «браузере по умолчанию» = наше приложение должен показывать пикер выбора браузера и открывать файл в выбранном, а не молча открывать окно настроек.

## Overview

### Context

Приложение — дефолтный обработчик `http`/`https`. Роль «браузер по умолчанию» неявно перепривязывает к нему и тип документа `public.html` (проверено: `LSCopyDefaultRoleHandlerForContentType(public.html, .viewer)` = `dev.korchasa.SmartLinksOpener`). Поэтому macOS отдаёт приложению и локальные HTML-файлы.

### Current State

- Файл доставляется Apple Event-ом `kAEOpenDocuments` (`odoc`), а веб-ссылка — `kAEGetURL` (`GURL`).
- `AppDelegate` (`App.swift`) регистрирует только обработчик `GURL`. `odoc` обрабатывать некому → `handledURLAtLaunch` остаётся `false` → фолбэк-таймер 0.4 с вызывает `showRules()` → открывается окно настроек, файл не открывается.
- Downstream уже корректно деградирует на `file://`: `handleIncoming` не находит домен → очередь → пикер; `choose(remember:)` не создаёт правило (`ruleDomain` = nil); `open(_:in:)` открывает файл в браузере через `NSWorkspace`.
- Пикер показывает заголовок `store.ruleDomain(for:) ?? url.host ?? url.absoluteString` → для файла это полный `file:///…` путь, а ярлык режима врёт «Open & remember» (правило для файла невозможно).

### Constraints

- Только публичные Apple API. Без сторонних зависимостей.
- Без новых ключей локализации (переиспользовать существующий «Open once — no rule created»).
- `Info.plist` оставить минимальным — НЕ объявлять `CFBundleDocumentTypes` (доставка уже работает через роль дефолтного браузера; объявление выставило бы приложение HTML-просмотрщиком во всех меню «Открыть с помощью»).
- Не трогать ручной обработчик `GURL` (он перекрывает только `GURL`; `odoc` остаётся за AppKit → `application(_:open:)`).

## Definition of Done

- [x] FR-FILE-OPEN: чистый `LinkLabel.title(for:)` даёт имя файла для `file://` и registrable-домен для веб-URL
  - Test: `Tests/SmartLinksOpenerTests/LinkLabelTests.swift::testFileURLShowsFilename` (+ `testWebURLShowsRegistrableDomain`)
  - Evidence: `./build.sh test LinkLabelTests`
- [ ] FR-FILE-OPEN: локальный `.html` доходит до пикера и открывается в выбранном браузере; правило не создаётся; окно настроек НЕ открывается
  - Test: `manual — maintainer — double-click .html → picker appears → choose browser → file opens in it; no rule stored; settings window does NOT appear`
  - Evidence: `./build.sh check`

## Solution

1. **SRS** (`documents/requirements.md`): добавить `### 3.13 FR-FILE-OPEN: Route local HTML files [ANC:fr:file-open]` со scenario + acceptance (LinkLabelTests + manual). Обновить §5 Interfaces (добавить `kAEOpenDocuments` как второй ingress).
2. **SDS** (`documents/design.md`): §3.1 — добавить `application(_:open:)` в Agent shell + `[REF:fr:file-open]`; новый §3.10 «Link label — `LinkLabel.swift`»; §5 — ветка `file://` (имя файла, режим open-once); §7 — обновить констрейнт «Apple-event handling is the sole URL ingress» → два ingress (`GURL` веб-ссылки + `odoc` файлы).
3. **RED**: `Tests/SmartLinksOpenerTests/LinkLabelTests.swift` — `file://` → `lastPathComponent`; `https://mail.google.com` → `google.com`. Запустить → падает (нет `LinkLabel`).
4. **GREEN**: `Sources/SmartLinksOpener/LinkLabel.swift` — `enum LinkLabel { static func title(for:) }` с `// [REF:fr:file-open]`. Тесты зелёные.
5. **GREEN**: `App.swift` — `func application(_:open urls:)` → `handledURLAtLaunch = true` + `store.handleIncoming` на каждый URL, маркер `// [REF:fr:file-open]`.
6. **GREEN**: `PickerView.swift` — заголовок через `LinkLabel.title(for:)`; `openOnce = shiftHeld || url.isFileURL`; ярлык режима и `choose(remember: !openOnce)`; скрыть ⇧-подсказку для файлов.
7. **CHECK**: `./build.sh check` зелёный. Ручная проверка двойным кликом по `.html`.
8. **Docs**: AGENTS Documentation Map — добавить `App.swift → FR-FILE-OPEN`, `LinkLabel.swift`, `LinkLabelTests.swift`. Обновить `documents/index.md` (новый FR).
</content>
</invoke>
