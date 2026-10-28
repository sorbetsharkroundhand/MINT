# Purlory identity and previous installations

Purlory uses `app.purlory.Purlory`, `Documents/Purlory`, and the `purlory.*` preference namespace. The executable, Swift packages, Xcode project/scheme, developer scripts, CI, and resource bundles use the Purlory name.

## Preserve existing work

The former MINT installation and its documents are never deleted or moved by Purlory. Changing the bundle identifier creates a separate sandbox identity; an old container is not automatically accessible to the new application.

Use **Import existing manuscripts** at first launch, or the project import command, and select:

- An individual `Projects/<UUID>` folder containing `project.json` for a current-format project. Import preserves the project ID, manuscript, assets, writer decisions, and recovery data in a verified copy.
- The old storage folder containing `entries.json` for legacy manuscripts. The importer prepares and verifies a new project before activation and leaves the original file unchanged.

For developer builds, the previous storage root is `~/Documents/MINT`. For sandboxed builds, locate the previous application's container in Finder; grant access using the directory picker. Do not delete the previous installation or storage before checking imported projects and their media.

Global preferences from the old `app.mint.MINT` domain are copied once when that domain is accessible. Existing Purlory values win, including explicit false/zero values. AI authorization is not transferred; select and authorize a local model in the new installation. Old recent-project/selection references are not activated before project import. If sandbox isolation makes the old preference domain unavailable, preferences remain in the previous app and can be set again in Purlory; automatic cross-container settings migration is not claimed.

## Verification and distribution

Use `swift build`, `swift test`, and `swift build --product PurloryBench`. Build the developer application with `scripts/build-purlory-app.sh`; use `scripts/archive-purlory-app.sh` for the unsigned distribution archive. Both paths validate `AppIcon.icns` and its Info.plist reference.

A new bundle ID needs its matching Apple Developer/App Store Connect configuration before Store distribution. A developer bundle does not prove signing, an upgrade of an existing Store listing, or Store acceptance. Historical benchmark reports retain the names and identities of the artifacts actually tested; they are not evidence for the renamed application.
