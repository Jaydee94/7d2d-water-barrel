# 7d2d-water-barrel – Automated Water Barrel

A **server-side-only** Harmony mod for **7 Days to Die (v2.5 / Alpha 21+)** that
automatically transfers water produced by **Dew Collectors** into a nearby
**Automated Water Barrel** storage container.

---

## Features

| Feature | Detail |
|---|---|
| **Automatic transfer** | Water items (e.g. `drinkJarDirty`) produced by Dew Collectors are moved into the nearest valid barrel. |
| **5-block search radius** | The patch scans a cube of 11³ blocks around each Dew Collector. |
| **Two discovery methods** | Finds containers by block name (`automatedWaterBarrel`) **or** by the `WaterStorage` tag — so any modded container can opt-in via XML. |
| **Stacking-aware** | Items are first stacked onto matching existing stacks, then placed in the next empty slot. |
| **Output-slot clearing** | The Dew Collector's output slot is cleared on successful transfer so the next production cycle begins immediately. |
| **CPU-friendly timer** | Each Dew Collector is checked at most once every **10 seconds**. |
| **Server-side only** | No custom network packages; safe to run on a dedicated server without a matching client mod. |

---

## File Structure

```
AutomatedWaterBarrel/          ← drop this folder into <GameDir>/Mods/
├── ModInfo.xml
├── WaterBarrelMod.csproj      ← build project (not required at runtime)
├── AutomatedWaterBarrel.dll   ← compiled output (built from src/)
├── Config/
│   └── blocks.xml             ← block definition for automatedWaterBarrel
└── src/
    ├── WaterBarrelMod.cs      ← IModApi entry point / Harmony init
    └── DewCollectorPatch.cs   ← Harmony postfix on TileEntityDewCollector.HandleUpdate
```

---

## Building from Source

### Prerequisites

* .NET SDK 6+ (the MSBuild SDK targets `net472` which ships with all recent .NET SDKs)
* 7 Days to Die installed locally

### Steps

1. Open `WaterBarrelMod.csproj` and set the `<GamePath>` property to your game
   installation directory (defaults to the Steam default path on Windows):

   ```xml
   <GamePath>C:\Program Files (x86)\Steam\steamapps\common\7 Days To Die</GamePath>
   ```

2. Build the project:

   ```bash
   dotnet build WaterBarrelMod.csproj -c Release
   ```

   The compiled `AutomatedWaterBarrel.dll` is written directly to the repository
   root (next to `ModInfo.xml`) so the mod folder is immediately deployable.

3. Copy the entire folder to `<GameDir>/Mods/AutomatedWaterBarrel/`.

---

## Installation (pre-built)

1. Download the latest release and extract it.
2. Copy the `AutomatedWaterBarrel` folder into:
   - **Windows dedicated server:** `<GameDir>\Mods\`
   - **Linux dedicated server:** `<GameDir>/Mods/`
3. Start the server — no client-side installation required.

---

## Configuration

### Search Radius

Edit `src/DewCollectorPatch.cs` and change the constant:

```csharp
private const int SearchRadius = 5; // blocks (cube half-side)
```

### Timer Interval

```csharp
private const double CheckIntervalSeconds = 10.0; // seconds
```

### Adding Your Own Water-Storage Container

Add `WaterStorage` to the block's `Tags` property in your XML:

```xml
<block name="myCustomTank">
    <property name="Tags" value="WaterStorage,storage" />
    <!-- … rest of your block definition … -->
</block>
```

The patch will then automatically discover and fill that container too.

---

## How It Works

```
TileEntityDewCollector.HandleUpdate (game calls every tick)
  └─► [Postfix] DewCollectorToWaterBarrelPatch.Postfix
        ├── Server-side guard
        ├── Rate-limit: skip if < 10 s since last check
        ├── Read output slot (items[0])
        ├── Return early if slot is empty
        ├── FindNearbyStorage(radius=5)
        │     └── scans positions for block name OR "WaterStorage" tag
        └── TryTransferItem → clear output slot → SetModified on both TEs
```

---

## License

[MIT](LICENSE)
