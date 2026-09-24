# Wine Vault App Store assets

English (US) description: `description.txt`. Three genuine 1242 × 2688 RGB PNGs without alpha in `Screenshots/6.5-inch/`: collection, bottle details, dashboard. Captured from main revision 5a362070d96785791eef44e01121b2ab4473025a, iPhone 11 Pro Max, iOS 26.5, Xcode 27.0, September 23, 2026.

To reproduce, generate the project with `xcodegen generate`, build the WineVault scheme and install it on a dedicated simulator. Launch once, then terminate. Run `seed-screenshot-data.py` against its empty `Library/Application Support/com.infinityball.winevault/vault.sqlite`. It creates fictional wines and manual prices and refuses a populated collection. Relaunch, capture the collection, open Cabernet Sauvignon and capture the bottle details, then return and open the bar-chart dashboard. Use `xcrun simctl io <device-id> screenshot <file.png>` and export as RGB without changing dimensions.

The existing local custom icon has been preserved and assigned through project.yml. Only the icon, its assignment and App Store assets are included; unrelated working-copy changes remain untouched. No App Store upload or submission has been performed.
