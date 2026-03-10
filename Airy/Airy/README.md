# Airy iOS App

To open in Xcode:

1. In Xcode: **File → New → Project**
2. Choose **iOS → App**. Product Name: **Airy**, Interface: **SwiftUI**, Language: **Swift**, minimum deployment iOS 17.
3. Save into this `Airy` folder (so the new project sits beside the existing `Airy` source folder), or replace the generated source with this structure.
4. **Remove** the default Swift file Xcode created, then **right‑click the target’s group → Add Files to "Airy"** and add the inner `Airy` folder (with App, Core, Services). Ensure **Copy items if needed** is unchecked and **Create groups** is selected. Add **Assets.xcassets** and **Info.plist** the same way.
5. In target **Build Settings**, set **Info.plist File** to `Info.plist` (or `Airy/Info.plist` if you saved at repo root).
6. Build and run.

If you prefer to use the existing structure without creating a new project, open the repo root in Xcode and add the `Airy/Airy` folder and `Airy/Assets.xcassets` and `Airy/Info.plist` to a new app target.
