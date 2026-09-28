# SkyNet: белый пролог (фаза 0)

Кинематографичная белая вставка, которая проигрывается **перед** основным шоу.
Сначала идут SSH/remote-boot и захват PowerShell, затем символьная сборка
логотипа, удержание готового кадра, финальный Sixel-кадр и ONLINE-надпись.

| Файл | Что делает |
|---|---|
| `Modules/SkyNet.Prologue.psm1` | все сцены пролога (белая палитра, ANSI-логика) |
| `Core/launch_skynet.ps1` | фаза 0: резолв `Charset`, вызов `Show-SkynetPrologue`, флаг `-NoPrologue` |

## Порядок сцен

1. `Show-SkynetSshIntro` — в самом начале: `[ HOST SCAN INITIATED ]`,
   `[ SSH SESSION ESTABLISHED ]`, `[ REMOTE TERMINAL DETECTED ]`, затем
   `SYSTEM/HOST/USER` и `scanning local system...` с реальными локальными
   CPU/MEMORY/GPU/TERMINAL/DISPLAY; и мигающая `░▒▓ SYSTEM ONLINE ▓▒░`
   (6 циклов, 220/140 мс). Данные собираются один раз через безопасные
   read-only Win32_* запросы, при ошибке выводится `UNKNOWN`.
2. `Show-SkynetTerminalHijack` — перед логотипом: обычные `PS C:\Users\<локальный пользователь>`
   переходят в такой же промпт с курсором `_`, затем `CONNECTION OVERRIDE` и статусы.
3. `Show-SkynetLogoNoiseReveal` — логотип 3,2 с собирается построчно из мусора,
   куски кадра несколько раз сильно смещаются полосами; готовый символьный кадр
   удерживается 1,6 с и центрируется по видимой ширине.
4. `Show-SkynetSixelLogo` — после видимого символьного кадра напрямую выводится
   финальный Sixel-логотип; вместе с мигающей ONLINE-надписью он отображается 2 с.
5. `Show-SkynetOnlineBlink` — мигающее `SKYNET SYSTEM ONLINE` прямо под финальным
   Sixel-кадром.
6. `Show-SkynetRadarBoot` — тёмный экран → `GLOBAL DEFENSE NETWORK` / `INITIALIZATION` /
   время / `TARGET ACQUISITION SYSTEM` / `ONLINE` (скорость 1,5×, на 50% быстрее) →
   `> SEARCHING FOR UNIT...`, `> UNIT TYPE: T-800`, `> STATUS: DEPLOYMENT READY`.
7. `Show-SkynetUnitScan` — справа выводятся все 215 исходных PNG
   (`1.png…215.png`) как настоящие Sixel-кадры через прямой вызов Chafa,
   а слева закреплена шапка (`UNIT: T-800 … TARGETING: ONLINE`). Под шапкой
   семь красных строк сканирования накапливаются по мере прохода: нейропроцессор,
   память, оптика, энергоблок, каркас, сервоприводы и полное тело. После них
   оставлены три пустые строки-разделителя. Поток ТТХ запускается только после
   последнего Sixel-кадра и закрепления `FULL-BODY SCAN DONE`, идёт ниже всех
   аннотаций и не затирает их.
   Заголовок `CYBERDYNE SYSTEMS :: UNIT IDENTIFICATION SCAN` статичен и непрерывно
   мигает на протяжении одного прохода. Символьный кэш кадров в этом режиме не
   используется. На кадрах `97…106` мигает `NEURAL PROCESSOR SCAN ---->`, через
   1 с строка закрепляется как `NEURAL PROCESSOR SCAN DONE ---->`. Затем по очереди
   добавляются `LEARNING COMPUTER SCAN ---->`,
   `OPTICAL/ACOUSTIC SENSOR SCAN ---->`, `POWER CORE SCAN ---->`,
   `HYPER-ALLOY COMBAT CHASSIS SCAN ---->` и `HYDRAULIC SERVO SCAN ---->`.
   Кадры `197…215` дают финальную строку `FULL-BODY SCAN ---->`, которая после
   последнего кадра закрепляется как `FULL-BODY SCAN DONE ---->`. Только текущая
   строка мигает; все предыдущие остаются на своих местах постоянными красными.

   После закрепления `FULL-BODY SCAN DONE` панель зон заменяется итоговым
   отчётом Cyberdyne (`Get-SkynetCyberdyneScanBlock`): заголовок с моделью,
   семь зон со статусом `--> COMPLETE`, затем `STATUS: ALL SYSTEMS NOMINAL`
   и `MISSION READY.`. Отчёт печатается построчно, а поток ТТХ переносится
   ниже него — блок выше прежней панели зон.

8. `Show-SkynetOpticalCheck` — чёрный экран → `OPTICAL SYSTEM` +
   `VISIBLE SPECTRUM / IR SPECTRUM / TARGETING / MOTION TRACKING … OK`.

## Глитчи строк (сцена 1)

`Write-SkynetGlitchLine` печатает строку в три фазы: побитая версия → «перескок»
(та же побитая строка со сдвигом вбок) → верная строка поверх. Вероятности:

```powershell
Write-SkynetGlitchLine -Text '> scanning local system...' -GlitchChance 0.25 -JumpChance 0.5
```

## Прокрутка ТТХ (сцена 7)

Строки берутся из `tactical and technical specifications.MD` (корень проекта):

* `Resolve-SkynetSpecFile` — автопоиск: явный путь → файл с «tactical+spec» →
  любой `*specification*.md`; ничего не нашлось → пусто;
* `Get-SkynetSpecScanLines` — читает файл последовательно:
  `LABEL: value` → `> LABEL ....... VALUE`, остальной текст — абзацами;
  длинные строки переносятся через `Format-SkynetWrappedText`;
* если файла нет, используется запасной набор `Get-SkynetT800ScanLines`
  (те же ТТХ из `Get-SkynetT800Specs`, но короче).

Свой файл можно указать разово:

```powershell
.\Core\launch_skynet.ps1 -SpecFile 'D:\specs\t800.md'
```

Шапка (`UNIT: T-800`, `MODEL: 101`, `ENDOSKELETON: HYPER-ALLOY`, `POWER CELL: ACTIVE`,
`CPU: NEURAL-NET PROCESSOR`, `VISION: INFRARED`, `TARGETING: ONLINE`) висит на месте
всё сканирование. Семь строк зон (processor/memory/optics/power/chassis/hydraulic/body)
занимают постоянный блок под шапкой, а прокрутка ТТХ идёт только ниже него
и только после `FULL-BODY SCAN DONE`.

## Параметры запуска

```powershell
.\Core\launch_skynet.ps1                              # пролог + шоу
.\Core\launch_skynet.ps1 -NoPrologue                  # сразу основное шоу
.\Core\launch_skynet.ps1 -TorsoFramesFolder .\assets\torso_frames
.\Core\launch_skynet.ps1 -SpecFile '.\tactical and technical specifications.MD'
.\Core\launch_skynet.ps1 -NoGlitch                    # спокойный прогон, без глитчей логотипа
```

Пролог целиком пропускается при `-Instant` (быстрые smoke-прогоны) и при
`-SkipLogo`. Если `ANSI` недоступен или логотип не найден — пролог тихо
пропускается с `WARN` в `logs\skynet_boot.log`.

## Кадры вращения

В Sixel-режиме используются 215 исходных PNG в натуральном порядке.
Путь: `-T800FramesFolder` → `assets\t800_frames` → `assets` (если там ≥2
числовых файлов). Для T-800 Chafa вызывается напрямую с `--format=sixel` и
`--dither=none`; символьный кэш `cache\t800seq_*.spin` в этом режиме не строится.
В прологе и в основной сцене выполняется один полный проход: 215 кадров,
интервал между запусками Chafa — 8 мс (фактическая частота ограничена
обработкой самого Chafa). Перед кадром область не очищается пробелами, поэтому
изображение не мигает; финальная очистка выполняется только после сцены.
Кадр `106` удерживается ровно один раз — на первом кадре после зоны
процессора, чтобы `NEURAL PROCESSOR SCAN DONE` успел появиться и повисеть; флаг
`$processorHoldPending` гарантирует, что удержание не повторяется на каждом
следующем кадре (иначе активный этап сбрасывался бы назад на `processor`,
а строки `MEMORY/OPTICS/POWER` никогда бы не мигали).

## Тайминги (примерно)

* сканирование юнита — один полный проход по 215 исходным PNG как Sixel;
  `97…106` — мигающий `NEURAL PROCESSOR SCAN ---->` (через 1 с закрепляется
  `NEURAL PROCESSOR SCAN DONE ---->`), `107…116` — `LEARNING COMPUTER SCAN ---->`,
  `117…126` — `OPTICAL/ACOUSTIC SENSOR SCAN ---->`,
  `127…136` — `POWER CORE SCAN ---->`,
  `137…166` — `HYPER-ALLOY COMBAT CHASSIS SCAN ---->`,
  `167…196` — `HYDRAULIC SERVO SCAN ---->`;
  `197…215` — `FULL-BODY SCAN ---->`, после последнего кадра — `FULL-BODY SCAN DONE ---->`;
  активная красная строка мигает, а все предыдущие остаются на экране
  постоянными красными и не сдвигаются потоком ТТХ; ТТХ стартует после
  финального `FULL-BODY SCAN DONE` и выводится под тремя пустыми строками;
  текст ТТХ выводится ровно вдвое быстрее: 2 мс на знак и 22 мс между строками;
  символы выводятся в отдельные ячейки без полной перерисовки строки;
  финальный Sixel-кадр удерживается, пока не закреплена строка полного тела;
* оптический тест — 3.5 с.

Уменьшить/ускорить сцену сканирования можно прямо в `Show-SkynetUnitScan`
(`-CharDelayMs`, `-LineGapMs`, `-TailHoldMs`), либо вызвать её напрямую с

## Финал: окно видеозвонка

После зелёной загрузки `Show-SkynetTerminatorFinale` открывает **отдельное
окно** — как будто терминатор звонит по видеосвязи:

1. короткий чёрный экран;
2. `Core\play_call_window.ps1` стартует в новом окне Windows Terminal
   (`wt -w new new-tab --title "Skype Video - T-800 MK-VI"`), уменьшает его до
   размера видеоокна (1152×700) и рисует шапку `SKYNET SECURE VIDEO CALL`
   с настоящими Sixel-кадрами T-800 из `assets\terminator`;
3. пока идёт звонок, в основном терминале моргает строка
   `Visual contact complited` между статичными строками
   `SKYNET :: VISUAL CHANNEL ESTABLISHED` и `REMOTE UNIT :: T-800 MK-VI`;
4. обрыв связи: микрофризы, белые полосы и сообщение о блокировке
   Malwarebytes, затем чёрный экран и `I'll be back`;
5. окно терминала возвращается из максимизированного в обычный размер.

### Ускорение анимации на 20%

Chafa тратит ~30 мс на **запуск процесса** независимо от размера кадра, поэтому
меньшее окно само по себе анимацию почти не ускоряет. Окно звонка решает это
двумя средствами:

* **кэш Sixel-кадров** — готовые кадры один раз сохраняются в
  `cache\finale_sixel\<W>x<H>\` (инвалидация по времени изменения исходника),
  и при показе просто выводятся в поток без запуска Chafa;
* **калибровка темпа** — окно замеряет реальную стоимость кадра в прежнем
  full-size рендере и держит темп `база × 137 / (1 + Speedup/100)`, то есть
  ровно на 20% быстрее прежнего.

Таймер ожидания двухступенчатый (`Start-Sleep` + `Thread::Sleep(1)`): обычный
`Start-Sleep` пере overshoots на 1–2 мс, что на 137 кадрах набегает сотни
миллисекунд. Фактическое ускорение пишется в журнал:

```text
Finale: звонок 137 кадров, 60x17, база 46.0 мс/кадр, цель 5253 мс,
факт 5220 мс (ускорение 20.8%).
```

### Ключи финала

| Ключ | Назначение |
| --- | --- |
| `-FinaleSpeedup 20` | ускорение анимации финала, % |
| `-ContactText 'Visual contact complited'` | моргающая строка во время звонка |
| `-ContactBlinkMs 200` | период моргания, мс |
| `-NoCallWindow` | не открывать окно звонка (анимация в текущем терминале) |
| `-NoRestoreWindow` / `-KeepWindowSize` | не уменьшать окно в конце шоу |
| `-CloseAfterShow` (стартер) | старое поведение: закрыть окно после `-Pause` |

### Рабочий терминал в конце

Стартер запускает шоу как

```text
pwsh -NoProfile -ExecutionPolicy Bypass -NoExit -Command "& 'launch_skynet.ps1' -KeepShell ..."
```

`-KeepShell` запрещает сценарию вызывать `exit`, а `-NoExit` оставляет
интерактивный промпт — поэтому вкладка не закрывается и после шоу можно сразу
вводить команды. Значения с пробелами (например `-ContactText`) в этой строке
берутся в одинарных кавычках; имена параметров — без кавычек, иначе
`-Command` воспринял бы их как строковые литералы.

Окно уменьшается через Win32 (`SkyCall.RestoreToNormal`): сначала `SW_RESTORE`,
затем `SetWindowPos` в центр рабочей области (62% × 72%). Окно ищется по
классу `CASCADIA_HOSTING_WINDOW_CLASS` и заголовку `SKYNET`, который сценарий
задаёт явно (`$Host.UI.RawUI.WindowTitle`) — PowerShell иначе перетирает его
текущим каталогом. Прежний режим возвращается ключом `-CloseAfterShow`.

`-ScanLines @(...)` — тогда любой свой текстовый поток уйдёт в ту же прокрутку.
