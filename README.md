# FIGHT OR DIE

A tactical multiplayer Roblox game by **NOMAD BROS**.

This repository holds the **code foundation** for the game. The world itself —
terrain, Army Base, Terrorist Base, Abandoned City, roads, buildings, and all 3D
architecture — is authored separately in Roblox Studio by the NOMAD BROS team and
is intentionally **not** part of this repo. The systems here operate on that world
by tag/attribute; they never generate map geometry.

## Tech stack

- **Language:** Luau
- **Sync:** [Rojo](https://rojo.space) — filesystem `.luau` files sync into Studio
- **Toolchain:** [Rokit](https://github.com/rojo-rbx/rokit) (`rokit install` pins Rojo, StyLua, Selene, Wally)

## Getting started

```bash
rokit install          # install pinned tools (Rojo, StyLua, Selene, Wally)
rojo serve             # start the sync server, then connect from the Rojo Studio plugin
```

Open your Studio place, connect the Rojo plugin, and the `src/` tree below syncs
into the correct services.

## Project structure

```
default.project.json          Rojo mapping (filesystem -> Studio services)
src/
├── shared/          -> ReplicatedStorage/Shared   (server + client)
│   ├── Config/          all tunable constants, one place
│   ├── Remotes/         single source of truth for every RemoteEvent/Function
│   ├── Types/           shared Luau type definitions
│   └── Modules/         shared utilities (Logger, future helpers)
├── server/          -> ServerScriptService/Server (authoritative)
│   ├── init.server.luau     bootstrap: builds remotes, loads + starts systems
│   └── Systems/
│       ├── GameSystem/          match/deploy flow entry (PLAY -> deploy)
│       ├── MovementSystem/      Heavy Walk + weight -> speed
│       ├── WoundedSystem/       downed / bleeding state machine
│       ├── MedicSystem/         healing + revive
│       ├── CarrySystem/         carry downed players
│       ├── InventorySystem/     inventory, weight, corpse search
│       ├── SpawnSystem/         spawn / respawn at tagged zones
│       ├── VehicleSystem/       enter/exit, ownership, damage
│       ├── DroneSystem/         deploy, range/battery/altitude
│       └── VisionSystem/        power / blackout / searchlights (authoritative)
└── client/          -> StarterPlayer/StarterPlayerScripts/Client
    ├── init.client.luau     bootstrap: loads + starts controllers
    └── Controllers/
        ├── StartMenuController/ start menu UI + menu camera (PLAY/SETTINGS/Profile)
        ├── CameraController/    first-person-only gameplay camera (modal: menu/vehicle/spectator seams)
        ├── InputController/     keybinds -> server intent
        ├── HUDController/       health, inventory, prompts, progress bars
        ├── AnimationController/ local character animation (Heavy Walk stride)
        └── NvgController/       NVG + flashlight local rendering
```

## Architecture principles

- **Server-authoritative.** Health, wounded state, inventory/weight, vehicle
  ownership, drone limits, and power/blackout are decided and validated on the
  server. Clients send *intent* over Remotes and render results.
- **Client is feel-only.** Input, HUD, NVG/flashlight visuals, and camera live
  on the client.
- **Modular lifecycle.** Every server system and client controller is a folder
  returning `{ Name, Init, Start }`. The bootstrap runs `Init()` on all, then
  `Start()` on all — so systems can safely reference each other. Add a system by
  dropping a folder in `Systems/` (or `Controllers/`); no bootstrap edits needed.
- **Networking in one place.** All remotes are declared in `shared/Remotes`,
  grouped by system, created once by the server.
- **Tuning in one place.** All constants live in `shared/Config`.

## Status

Foundation scaffolded. Each system is a wired stub awaiting its detailed spec.
Systems are implemented one at a time into this structure.
