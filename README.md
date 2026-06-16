# Smart Links Opener

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)
[![CI](https://github.com/korchasa/open-link-in/actions/workflows/ci.yml/badge.svg)](.github/workflows/ci.yml)

> Релизы в Mac App Store автоматизированы через GitHub Actions: пуш тега `vX.Y.Z`
> собирает песочничную сборку, подписывает и загружает её в App Store Connect.
> Первоначальная настройка (сертификаты, ключи, секреты) — см.
> [`documents/tasks/2026/06/appstore-cicd-setup.md`](documents/tasks/2026/06/appstore-cicd-setup.md).

Минималистичное macOS-приложение, которое работает как браузер по умолчанию и
открывает каждую ссылку в нужном браузере в зависимости от домена. Если правило
для домена не найдено — показывает выбор среди установленных браузеров с
возможностью сразу создать правило.

Написано на SwiftUI/AppKit (стандартный нативный стек macOS), без сторонних
зависимостей.

## Открытый код и сборка в App Store

Проект **с открытым исходным кодом под GPL-3.0-or-later** — код можно изучать,
менять и распространять (с сохранением открытости форков).

- **Собрать бесплатно из исходников:** `./build.sh` (см. ниже). Полностью
  функциональная версия.
- **Купить в Mac App Store (~$3 / €3):** официальная подписанная и нотаризованная
  сборка с автообновлением и в песочнице. Это удобство и способ поддержать
  разработку — функциональность та же.

Так как GPL несовместима с условиями Mac App Store, сторонние форки, как правило,
не могут попасть в App Store; официальную платную сборку публикует автор как
правообладатель (стандартное исключение для правообладателя — ваши права на код
по GPL это не ограничивает). Подробности — в `CONTRIBUTING.md`.

Две конфигурации сборки:
- `./build.sh prod` — открытая сборка, подпись Developer ID, Hardened Runtime, без
  песочницы (распространение вне App Store: DMG/zip).
- `./build.sh appstore` — сборка для Mac App Store с включённым App Sandbox.
  Playbook публикации: `documents/tasks/2026/06/open-source-and-appstore.md`.

## Возможности

- Регистрируется в системе как веб-браузер (схемы `http`/`https`).
- **Работает в фоне как агент** (`LSUIElement`): без иконки в Dock, управление
  через иконку в строке меню. Совпавшие по правилу ссылки открываются мгновенно
  и без окон, не перехватывая фокус.
- Маршрутизация по доменам: правило `домен → браузер`, выигрывает самое длинное
  совпадение (`bbc.co.uk` важнее `co.uk`).
- **Поддержка субдоменов**: правило хранит домен второго уровня (`mail.google.com`
  → `google.com`), и все его субдомены открываются в выбранном браузере.
  Составные публичные суффиксы учитываются (`news.bbc.co.uk` → `bbc.co.uk`,
  `user.github.io` → `user.github.io`). Префикс `www.` игнорируется.
- При отсутствии правила — окно выбора браузера с галочкой «Запомнить выбор».
- Окно управления правилами: добавление, смена браузера, удаление.
- Кнопка «Сделать браузером по умолчанию» (системный API с диалогом согласия).
- **Автозапуск при входе** через `SMAppService` (современный API Apple).
- **Автоматическая интернационализация**: язык интерфейса выбирается системой
  (10 языков: en, ru, uk, de, fr, es, it, pt-BR, ja, zh-Hans).
- Список браузеров берётся из LaunchServices (реально установленные приложения).

## Фоновый режим и иконка в строке меню

После запуска приложение не показывает иконку в Dock — оно живёт в строке меню
(значок «🔗»). Через меню доступны: «Правила…», переключатель браузера по
умолчанию, «Запускать при входе» и «Выйти». Окно правил можно открыть в любой
момент из этого меню; закрытие окна не выгружает агента.

## Соответствие требованиям Apple

- Только публичные API: `NSWorkspace`, LaunchServices (через `NSWorkspace`),
  `ServiceManagement`, Apple Events (`kAEGetURL`). Приватные/устаревшие вызовы
  убраны.
- Агент-приложение объявлено через `LSUIElement` и `NSApplication`
  `.accessory` activation policy.
- Сборка подписывается с **Hardened Runtime** (`--options runtime`).
- App Sandbox намеренно не включается: маршрутизатор браузеров по своей сути
  перечисляет и запускает произвольные приложения, что песочница запрещает.
  Штатный путь распространения такой утилиты — подпись **Developer ID** и
  **нотаризация** (вне Mac App Store).

## Сборка

```bash
./build.sh
```

Скрипт компилирует релизную сборку, собирает `SmartLinksOpener.app`, подписывает
ad-hoc подписью и регистрирует бандл в LaunchServices.

## Установка как браузера по умолчанию

1. `open SmartLinksOpener.app` (или перенесите в `/Applications` и запустите).
2. В окне приложения нажмите **«Сделать браузером по умолчанию»**.
   macOS покажет системный запрос на подтверждение — подтвердите.
   Либо вручную: *Системные настройки → Рабочий стол и Dock → Веб-браузер по
   умолчанию → Smart Links Opener*.

После этого любой клик по ссылке вне браузера попадёт в Smart Links Opener,
который мгновенно перенаправит её в нужный браузер либо предложит выбрать.

## Как это устроено

- `App.swift` — точка входа (`SwiftUI.App`), ловит входящие ссылки через
  `.onOpenURL`.
- `AppStore.swift` — состояние: список браузеров, правила (хранятся в
  `UserDefaults`), сопоставление домена с браузером, открытие ссылки в
  конкретном приложении через `NSWorkspace`.
- `Domain.swift` — чистая логика доменов: сворачивание хоста до домена второго
  уровня (registrable domain, eTLD+1) и проверка поддоменного совпадения.
  Покрыта юнит-тестами (`Tests/SmartLinksOpenerTests/DomainTests.swift`).
- `PickerView.swift` — окно выбора браузера для нового домена.
- `RulesView.swift` — окно управления правилами и статусом браузера по умолчанию.
- `Resources/Info.plist` — объявляет `CFBundleURLTypes` со схемами `http`/`https`,
  благодаря чему система видит приложение как браузер.

## Интернационализация

Строки интерфейса заданы английскими ключами (`LocalizedStringKey` /
`String(localized:)`), а переводы лежат в `Resources/<язык>.lproj/Localizable.strings`.
macOS автоматически подбирает язык по настройкам системы; при отсутствии перевода
используется английская база (`CFBundleDevelopmentRegion = en`).

Добавить язык: создайте `Resources/<код>.lproj/Localizable.strings` (скопируйте
ключи из `en.lproj`), добавьте код в `CFBundleLocalizations` в `Resources/Info.plist`
и пересоберите. Тексты-данные (домены, имена браузеров) не локализуются —
в коде они выводятся через `Text(verbatim:)`.

## Распространение

Для локального запуска достаточно ad-hoc подписи (`./build.sh`).

**Вне App Store (Developer ID + нотаризация):**

```bash
./build.sh prod
codesign --force --options runtime \
    --entitlements Resources/SmartLinksOpener.entitlements \
    --sign "Developer ID Application: ВАШЕ ИМЯ (TEAMID)" SmartLinksOpener.app
xcrun notarytool submit SmartLinksOpener.app --keychain-profile "AC" --wait
xcrun stapler staple SmartLinksOpener.app
```

**Mac App Store (платная сборка, App Sandbox):** полный playbook — в
`documents/tasks/2026/06/open-source-and-appstore.md`. Кратко:

```bash
MAS_APP_IDENTITY="Apple Distribution: ВАШЕ ИМЯ (TEAMID)" \
MAS_PROVISION_PROFILE=./SmartLinksOpener_MAS.provisionprofile \
  ./build.sh appstore
productbuild --component SmartLinksOpener-AppStore.app /Applications \
    --sign "3rd Party Mac Developer Installer: ВАШЕ ИМЯ (TEAMID)" SmartLinksOpener.pkg
xcrun altool --upload-app -f SmartLinksOpener.pkg -t macos \
    --apiKey <KEY_ID> --apiIssuer <ISSUER_ID>   # или Transporter.app
```

Автозапуск (`SMAppService`) надёжно работает только для подписанного приложения,
лежащего в `/Applications`.

## Замечания

- Идентификатор бандла: `dev.korchasa.SmartLinksOpener` (меняется в
  `Resources/Info.plist`).
- App Store-сборка в песочнице хранит правила в контейнере приложения
  (`~/Library/Containers/dev.korchasa.SmartLinksOpener/…`), отдельно от открытой
  Developer ID-сборки — это ожидаемо.

## Лицензия

Copyright © 2026 korchasa.

Licensed under the GNU General Public License v3.0 or later (GPL-3.0-or-later) —
see [LICENSE](LICENSE). Вклад в проект — см. [CONTRIBUTING.md](CONTRIBUTING.md).
Конфиденциальность — [PRIVACY.md](PRIVACY.md) (данные не собираются).
