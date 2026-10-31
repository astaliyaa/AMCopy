# Encore

A private iPhone music player in the style of Apple Music, for your own audio files. It also edits tags like mp3tag and supports animated covers.

## Features

**Apple Music-style UI (SwiftUI, iOS 18+, Liquid Glass on iOS 26)**
- Tabs: Home, New, Radio, Library, Search.
- Mini player. On iOS 26 it sits in the tab bar accessory. On iOS 18 it floats above the tab bar.
- Full-screen Now Playing:
  - zoom transition from the mini player
  - animated mesh-gradient background built from the artwork's colors
  - artwork that shrinks when paused
  - Apple-style "elastic" scrubber and volume slider
  - AirPlay button and favorite (star) button
- Time-synced lyrics (LRC). The current line is highlighted and auto-scrolls; tap a line to seek.
- Queue ("Playing Next"): shuffle, repeat, drag to reorder, swipe to remove.
- Library: Playlists, Artists, Albums, Songs, Favorite Songs, Genres, plus a "Recently Added" grid.
- Album pages: full-bleed motion artwork header, Play/Shuffle buttons, disc grouping, Lossless badge.
- Playlists: create and edit them, set a custom cover, add songs, reorder, delete.
- Search across songs, albums, artists, playlists and lyrics, with Browse Categories.
- Long-press menus everywhere: Play Next, Play Last, Add to Playlist, Favorite, Edit Info, Go to Album/Artist, Share File, Delete.
- Gapless playback. Background audio, lock-screen and Control Center controls, headphone-unplug pause. The queue is restored on relaunch.

**Importing your music**
- Use **Library › + › Import Songs / Import Folder** to pick files or whole folders from the Files app.
- Anything you put in **Files › On My iPhone › Encore** is imported automatically when you open the app. From Windows you can also drag files into Encore with the **Apple Devices** app (iPhone › Files › Encore).
- "Open in… Encore" works from other apps.
- Supported formats: MP3, M4A/AAC, ALAC, FLAC, WAV, AIFF, CAF.
- Lyrics from a matching `Song.lrc` and covers from a `cover.jpg` / `folder.jpg` next to the files are picked up automatically.

**Tag editor (Edit Info)**
- Edits title, artist, album, album artist, composer, genre, year, track and disc numbers, comments, explicit flag, artwork and lyrics.
- **Batch edit:** select several songs, or use "Edit Album Info". Fields that differ show *Mixed*, and only the fields you change are written.
- **File Name → Tag** works mp3tag-style with `%artist% - %title%` patterns. In batch mode, **Auto-Number Tracks** numbers the selected songs.
- Writes real tags into the files, so they stay with the file when you share or export it:

  | Format | Tags written |
  |---|---|
  | MP3 | ID3v2.3 / v2.4 (keeps frames it doesn't manage) |
  | FLAC | Vorbis comments + PICTURE block |
  | M4A / M4B | iTunes atoms (passthrough export, no re-encode) |
  | WAV / AIFF / CAF | kept in the library only |

**Animated covers**
- In Edit Info › Artwork › Animated Cover, pick a video or GIF from Photos or Files.
- It loops silently on the album page, in New, in Now Playing and in long-press previews.
- If the song has no cover, the first frame becomes its static artwork.
- You can turn animated covers off in Settings.

## Building and installing (TestFlight)

This repo is meant to be **public**. GitHub Actions is free for public repos, including the macOS build machines. The workflow ([.github/workflows/build.yml](.github/workflows/build.yml)) does the following:

| Trigger | What happens |
|---|---|
| Pull request | Compile check only. No signing, and no secrets are used. |
| Push to `main`, or **Actions › TestFlight › Run workflow** | Signed App Store build, uploaded to TestFlight. |

Signing is done by [fastlane match](https://docs.fastlane.tools/actions/match/) ([fastlane/Fastfile](fastlane/Fastfile)), so you don't create any certificates or profiles yourself. On the first signed run, match uses your API key to create an Apple Distribution certificate and an App Store provisioning profile. It encrypts both with `MATCH_PASSWORD` and stores them on a `certificates` branch of this repo. Later runs reuse them and renew the profile when it expires.

### One-time setup

You can do all of this in a browser, without a Mac.

1. **Register an App ID.** Go to [developer.apple.com › Identifiers](https://developer.apple.com/account/resources/identifiers/list) › **+** › App IDs › App.
   - Use an explicit Bundle ID that nobody else uses, e.g. `com.yourname.encore`.
   - You don't need any extra capabilities.
2. **Put that bundle ID in [project.yml](project.yml)** as `PRODUCT_BUNDLE_IDENTIFIER`, replacing `com.personal.encore`. You can edit the file right on github.com.
3. **Create the app record.** Go to [App Store Connect › Apps](https://appstoreconnect.apple.com/apps) › **+** › New App › iOS.
   - Choose the bundle ID from step 1 and any SKU.
   - The name has to be unique across the whole App Store, e.g. "Encore Player (yourname)". It doesn't affect the home-screen name.
4. **Create an API key.** Go to App Store Connect › Users and Access › Integrations › **App Store Connect API** › Team Keys › **+**.
   - Give it the **Admin** role. The first run creates your distribution certificate, and only Admin keys are allowed to do that.
   - Download the `.p8`. You can only download it once.
   - Note the **Key ID** and the **Issuer ID** shown above the key list.
5. **Find your Team ID** on [developer.apple.com › Account › Membership details](https://developer.apple.com/account#MembershipDetailsCard). It's 10 characters, like `A1B2C3D4E5`.
6. **Pick a `MATCH_PASSWORD`.** It protects your certificate on the public `certificates` branch, so make it long and random. You can generate one in Git Bash:
   ```bash
   openssl rand -base64 32
   ```
   Keep a copy somewhere private. Changing it later means starting the certificate over (see below).
7. **Add the secrets** in your GitHub repo › Settings › Secrets and variables › Actions › **New repository secret**. They're listed in the table below.

### Secrets to add

| Secret name | Value |
|---|---|
| `APPLE_TEAM_ID` | your **Team ID** from step 5 |
| `ASC_KEY_ID` | the API key's **Key ID**, e.g. `2X9R4HXF34` |
| `ASC_ISSUER_ID` | the **Issuer ID**, a UUID |
| `ASC_KEY_P8` | the whole text of `AuthKey_XXXXXXXXXX.p8` (open it in Notepad), including the `BEGIN`/`END` lines. The file base64-encoded works too. |
| `MATCH_PASSWORD` | the password from step 6 |

The bundle ID comes from `project.yml`. The build number is the workflow run number, so every push gets a new one.

### Getting builds on your iPhone

- Push to `main`. The build takes about 10–15 minutes, then Apple processes it for another 5–30 minutes before it shows up in TestFlight.
- The first time: in App Store Connect › your app › TestFlight › **Internal Testing**, create a group and add yourself. Then install the **TestFlight** app on your iPhone. Later builds show up there automatically.
- Export compliance is already answered in the app's Info.plist (`ITSAppUsesNonExemptEncryption = NO`), so you won't be asked about it for each build.
- Each TestFlight build expires after 90 days. Push or re-run the workflow to get a fresh one.
- If a build fails, open the failed run and read the **Sign, build and upload** step, or download the **build-log** artifact. Common first-run errors:
  - *forbidden* or *permission* errors: the API key isn't Admin.
  - *Couldn't find bundle identifier*: the bundle ID in `project.yml` doesn't match the App ID you registered.
  - *maximum number of certificates*: your account already has as many Apple Distribution certificates as Apple allows. Revoke one you don't use under [Certificates](https://developer.apple.com/account/resources/certificates/list).

### Keeping the public repo safe

- Pull requests from forks never get your secrets. They only run the unsigned compile check.
- Anyone can see the `certificates` branch, but its files are encrypted with `MATCH_PASSWORD`. With a long random password nobody can read them. Even if someone did, an App Store certificate and profile can't install apps on devices; they're only good for uploading to your own App Store Connect account.
- If you'd rather keep the certificate private, create a private repo for it and add two more secrets:
  - `MATCH_GIT_URL`: its `https://github.com/...git` URL.
  - `MATCH_GIT_BASIC_AUTHORIZATION`: base64 of `your-username:token`, using a fine-grained token with Contents read/write access to that repo.
  Then delete the `certificates` branch here.
- To change `MATCH_PASSWORD` later: delete the `certificates` branch and revoke the Apple Distribution certificate it made. The next run creates new ones.
- The logs show your Team ID and bundle ID. Neither is secret.
- Your music is never in the repo. It only lives on your phone.

### Building on a Mac instead

```bash
brew install xcodegen
```

```bash
xcodegen generate && open Encore.xcodeproj
```

In Xcode, select your Team under Signing & Capabilities, then press Run with your iPhone plugged in. Use Xcode 26 to get the iOS 26 tab-bar mini player.

## Project layout

```
Encore/
  App/          entry point, tab bar + mini player, global sheets/navigation state
  Models/       Song, Playlist, derived Album/Artist/Genre, Library store (JSON on disk)
  Playback/     AVQueuePlayer engine, lock screen, LRC parser, system volume
  Import/       file/folder import, metadata reading, file-name parsing
  Tags/         ID3 (MP3), FLAC, MP4 tag readers/writers
  Artwork/      artwork store/cache, animated cover views, color extraction
  Views/        Home, New, Radio, Library, Search, Now Playing, tag editor, Settings
fastlane/       Fastfile: signing (match), build, TestFlight upload
project.yml     XcodeGen spec; set your bundle ID here
```

## Notes and limitations

- It plays only your own files. There's no Apple Music catalog, streaming or iCloud Music Library, because those need Apple's private services.
- Other apps can't put animated artwork on the iOS lock screen, so the lock screen shows the static cover.
- The tab names and the screen layouts match Apple Music. The name and icon are Encore's own; change `CFBundleDisplayName` in `project.yml` to rename it on your home screen.
