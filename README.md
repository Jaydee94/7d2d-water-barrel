# Automated Water Barrel

Automated Water Barrel is a server-side mod for 7 Days to Die.

It moves water from nearby Dew Collectors into an Automated Water Barrel, so you do not need to empty each collector by hand.

## What It Does

- Adds a craftable **Automated Water Barrel** block
- Automatically transfers water produced by Dew Collectors into a nearby barrel
- Scans a 5-block radius around each Dew Collector every 10 seconds
- Works on the server only — players do not need to install the mod locally

## Crafting

The Automated Water Barrel is crafted at a **Workbench** (60 seconds).

| Ingredient | Amount |
|---|---|
| Scrap Polymers | 10 |
| Forged Iron | 5 |
| Electrical Parts | 3 |
| Spring | 2 |
| Nails | 10 |

## Installation

1. Download the latest release.
2. Extract it.
3. Copy the `AutomatedWaterBarrel` folder into your server's `Mods` folder.
4. Restart the server.

## Basic Use

1. Craft an Automated Water Barrel at a Workbench.
2. Place a Dew Collector.
3. Place the Automated Water Barrel within 5 blocks of the collector.
4. Wait for the collector to produce water.
5. The water is transferred into the barrel automatically.

## For Development

If you want to build and deploy the mod locally, use the included deploy script:

```powershell
.\Deploy-Mod.ps1
```

For a quick local playtest:

```powershell
.\Deploy-Mod.ps1 -Playtest
```

From WSL:

```bash
./Deploy-Mod.sh -Playtest
```

## Releases and CI

This repository includes GitHub Actions for:

- building the mod on pull requests
- creating a release package on pushes to `main`

If you only want the mod, you can ignore the build setup and just download a release zip.

## Files Included in the Release

```text
AutomatedWaterBarrel/
├── ModInfo.xml
├── AutomatedWaterBarrel.dll
└── Config/
    ├── blocks.xml
    ├── recipes.xml
    └── Localization.txt
```

## License

[MIT](LICENSE)
