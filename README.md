# DEADBLOCK: Zombie Defense Tycoon

Публичный репозиторий разрабатываемого Roblox-тайкуна.

Текущий прототип: личные локации игроков, общий конвейер, покупка до шести дропперов, три уровня каждого дроппера и два расширения участка. Покупки выполняются через площадки, улучшения — через панель выбранного дроппера. Деньги и правила проверяются сервером.

Это рабочая версия в разработке. Сохранение прогресса между входами и боевые системы пока не реализованы.

## Содержимое

- `src/server` — экономика, производство, владение базами и обработка покупок.
- `src/client/HUD.client.luau` — интерфейс и панель улучшений.
- `src/shared/Config.luau` — баланс, цены и уровни.
- `tests` — 16 проверок производства и экономики, выполненных в Studio.
- `tools/BuildTycoonWorld.luau` — сборка текущей локации в Studio.
- `tools/prepare-deployment.mjs` — подготовка скрипта установки из исходников.

## Roblox Studio

`Config` размещается в `ReplicatedStorage/DeadblockShared` как ModuleScript. Серверные модули — в `ServerScriptService/Deadblock`, `Main.server.luau` — как Script с именем Main. HUD — LocalScript в `StarterPlayer/StarterPlayerScripts`.

Для сборки используйте отдельную тестовую сцену. Сначала выполните сгенерированный скрипт установки в Edit-режиме, затем `BuildTycoonWorld.luau`. На существующем старом DeadblockWorld сборка требует резервную копию; неизвестные миры автоматически не заменяются.

Для проверки в Edit-режиме:

```luau
local root = game.ServerScriptService.Deadblock
local config = require(game.ReplicatedStorage.DeadblockShared.Config)
print(require(game.ServerStorage.DeadblockTests.Stage1Spec)(root))
print(require(game.ServerStorage.DeadblockTests.Stage2Spec)(root, config))
```

Техническая геометрия может быть заменена готовыми ассетами отдельно от экономики. Публичный выпуск игры в Roblox ещё не выполнялся.
