# Adjust Implement Speed

> [!IMPORTANT]
> This is a proof of concept experiment. There is no knowing if or when this will become a "proper" mod.

Adjust the working speed limits of your implements on the fly while driving. Push past default limits or fine-tune for precision work.

Tired of implements capping your vehicle at crawling speeds? AdjustImplementSpeed lets you increase or decrease the working speed limit of any attached implement in real time - no shop visits, no restarts. Includes an antigravity mode that bypasses physics-based speed penalties like PowerConsumer drag force.

> **Note:** This is a proof of concept experiment. Features and keybindings may change. Singleplayer only. Speed adjustments are not saved - they reset when you reload the map.

## Features

- Increase or decrease implement working speed in 1 km/h steps (RightShift+1 / RightShift+2)
- Toggle antigravity mode to bypass physics-based speed penalties (RightShift+0)
- Status line in F1 help panel shows current working speed and antigravity state
- Keybindings appear automatically when your vehicle has speed-limited implements attached
- Works while AI worker is driving
- Adjusts all attached implements simultaneously

## Installation

### From GitHub Releases
1. Download the latest release from [Releases](https://github.com/rittermod/FS25_AdjustImplementSpeed/releases)
2. Place the `.zip` file in your mods folder:
   - **Windows**: `%USERPROFILE%\Documents\My Games\FarmingSimulator2025\mods\`
   - **macOS**: `~/Library/Application Support/FarmingSimulator2025/mods/`
3. Enable the mod in-game

### Manual Installation
1. Clone or download this repository
2. Copy the `AdjustImplementSpeed` folder to your mods folder
3. Enable the mod in-game

## Usage

Enter a vehicle with implements attached. The keybindings appear in the F1 help menu.

### Keyboard Shortcuts
| Key | Action |
|-----|--------|
| RightShift + 1 | Increase working speed |
| RightShift + 2 | Decrease working speed |
| RightShift + 0 | Toggle antigravity mode |

Speed adjustments are applied in 1 km/h increments. Antigravity mode bypasses power-based speed reductions and implement drag force.

## Limitations

- Only works on towed/attached implements, not self-propelled work vehicles
- Speed adjustments reset on map reload
- Other mods (e.g. Courseplay) may set their own speed limits that override adjustments
- Singleplayer only

## Compatibility

- **Game Version**: Farming Simulator 25
- **Multiplayer**: Not Supported
- **Platform**: PC (Windows/macOS)

## Changelog

See [CHANGELOG.md](CHANGELOG.md).

## License

This mod is provided as-is for personal use with Farming Simulator 25.

## Credits

- **Author**: [Ritter](https://github.com/rittermod)

## Support

Found a bug or have a feature request? [Open an issue](https://github.com/rittermod/FS25_AdjustImplementSpeed/issues)
