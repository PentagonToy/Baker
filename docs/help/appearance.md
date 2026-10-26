# Appearance

Baker uses the charcoal and wheat colours shared by its authored banner and logo. System controls keep familiar macOS behaviour. The appearance follows the system unless you choose Light or Dark in Settings → General.

| Role | Light | Dark |
| --- | --- | --- |
| Banner background | `#ECEEF1` | `#1F2429` |
| Banner and logo accent | `#C27F2E` | `#EDBA68` |
| Banner foreground | `#262C33` | `#E8EBEE` |
| App surface | `#F8F9FB` | `#282F36` |
| App accent text and controls | `#8B581F` | `#EDBA68` |

The light app accent is a darker wheat shade for readable small text. Higher-contrast appearance uses `#704315` in Light and `#FFE9BE` in Dark. Recognition badges retain cloud or computer symbols and explicit provider names; colour alone does not identify the engine. Completed-copy feedback uses a checkmark, while errors and warnings retain their system colours and messages. Captured pixels and annotation colours are unchanged.

Banner colours come directly from the [light](../../others/assests/banner/baker_banner_light.svg) and [dark](../../others/assests/banner/baker_banner_dark.svg) SVGs. App surfaces are derived neutral shades. Colour roles follow Apple’s [Color](https://developer.apple.com/design/human-interface-guidelines/color) and [Dark Mode](https://developer.apple.com/design/human-interface-guidelines/dark-mode) guidance; normal text pairs are checked against a 4.5:1 contrast target.
