# macOS icon preflight

## Result

The selected build already includes the Sorting Hat app icon. App Store Connect obtains the Mac icon from the build; there is no separate product-page icon upload.

The shipping 1024×1024 PNG was measured and visually reviewed:

- fully opaque, with no transparent pixels or fringe;
- no likely baked rounded-rectangle mask;
- recognisable wizard-hat silhouette at 16, 32, 64, 128, 256, 512, and 1024 px;
- strong midnight-and-amber contrast consistent with the application's authored visual language;
- reference SHA-256 recorded in `evidence/app-icon-1024.json`.

## Recommendation

Use the current icon for this submission. After the first release, consider rebuilding it as a layered Icon Composer asset to adopt the newest macOS icon material and depth behavior without changing the recognisable hat silhouette.
