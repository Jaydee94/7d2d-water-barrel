# Automated Water Barrel

Automated Water Barrel is a server-side mod for 7 Days to Die.

It moves water from nearby Dew Collectors into an Automated Water Barrel, so you do not need to empty each collector by hand.

## What It Does

- Moves produced water into a nearby barrel automatically
- Works on the server only
- Does not require players to install the mod locally
- Supports the included Automated Water Barrel block

## Installation

1. Download the latest release.
2. Extract it.
3. Copy the `AutomatedWaterBarrel` folder into your server's `Mods` folder.
4. Restart the server.

## Basic Use

1. Place a Dew Collector.
2. Place an Automated Water Barrel nearby.
3. Wait for the collector to produce water.
4. The water should move into the barrel automatically.

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
```

## License

[MIT](LICENSE)
