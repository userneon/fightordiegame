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
│   ├── Data/            gameplay DATA, separate from logic (factions, ranks,
│   │                    roles, body parts, materials, ammo, weapons, items)
│   ├── Remotes/         single source of truth for every RemoteEvent/Function
│   ├── Types/           shared Luau type definitions
│   └── Modules/         Logger, Registry (service locator), HoldTracker
├── server/          -> ServerScriptService/Server (authoritative)
│   ├── init.server.luau     ServerBootstrap: remotes, registry, Init/Start
│   └── Services/
│       ├── GameService/         PLAY -> deploy flow (no auto-spawn)
│       ├── PlayerService/       lifecycle + Alive/Wounded/Critical/Dead
│       ├── FactionService/      Army/Terrorist assignment + switch rules
│       ├── RankService/         XP, promotion, permission gate (authority)
│       ├── DataService/         DataStore profiles, autosave, migration
│       ├── SpawnService/        tagged spawn zones, role-scaled respawn
│       ├── MovementService/     Heavy Walk + weight -> speed
│       ├── InventoryService/    slots, weight, equip, death loot
│       ├── BallisticsService/   simulated rounds (no Part per bullet)
│       ├── WeaponService/       data-driven weapons, shot validation
│       ├── DamageService/       single damage authority (zones, armour)
│       ├── ArmorService/        helmet/plate, durability, first-impact rule
│       ├── MedicalService/      medic-only hold-to-treat / revive
│       ├── CarryService/        server-welded casualty carrying
│       ├── CorpseService/       persistent corpses + faction loot rules
│       ├── InteractionService/  doors, containers, mission objects (by tag)
│       ├── ObjectiveService/    hold-E objectives (by tag)
│       ├── MissionService/      mission definitions over objectives
│       ├── EagleEyeService/     Army recon, detection-gated (no wallhack)
│       ├── VehicleService/      ownership, seats, damage, crash injury
│       ├── HelicopterService/   flight/radar/lock state
│       ├── DroneService/        deploy, battery, range/signal
│       ├── VisionService/       NVG/flashlight authority + blackout
│       ├── AudioService/        audio EVENT routing (no assets)
│       └── AntiCheatService/    validation, strikes, lock/ban with evidence
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

## Connecting your world

No service creates map geometry. They find the world you build in Studio by
**CollectionService tag** and **attributes**, so the world stays entirely your
work. Tag things and they come alive:

| Tag | Read by | Notes |
|---|---|---|
| `ArmySpawn` / `TerroristSpawn` | SpawnService | any BasePart works as a spawn pad |
| `Interactable` | InteractionService | attrs: `InteractKind`, `InteractHold`, `RequiredPerm`, `RequiredItem`, `RequiredFaction` |
| `Objective` | ObjectiveService | attrs: `ObjectiveId`, `ObjectiveKind`, `HoldTime`, `Faction`, `Radius` |
| `Vehicle` | VehicleService | attrs: `VehicleType`, `MaxHealth`, `RequiredPerm`; Seats/VehicleSeats inside |
| `Helicopter` | HelicopterService | attrs: `MaxHealth`, `Faction`, `RequiredPerm` |
| `PowerSource` | VisionService | toggling it drives blackout |
| `Tire` | VehicleService | per-tire damage pools |

## Status

Server-side gameplay foundation implemented: player/character state, factions,
ranks & permissions, combat (ballistics, weapons, damage, armour), survival
(corpses, medical, carry), persistence, anti-cheat, and the world-facing
frameworks (interaction, objectives/missions, vehicles, helicopters, recon).

Client is feel-only: Start Menu, first-person camera, HUD/compass, input.
