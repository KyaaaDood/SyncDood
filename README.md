<p align="center">
  <b>English</b> · <a href="README.es.md">Español</a>
</p>

<p align="center">
  <img src="icons/syncing.png" width="96" alt="SyncDood syncing">
  <img src="icons/ok.png" width="96" alt="SyncDood up to date">
  <img src="icons/error.png" width="96" alt="SyncDood error">
</p>

# 🎮 SyncDood — your saves and states, the same on every PC

> **Version 0.2.1** · 🌍 Follows the Windows language (English / Spanish)

SyncDood keeps your **game saves** 💾 and **save states** 📸 identical on all your PCs through **your own cloud** ☁️. It sits in the system tray, and its window lets you see the history and change folders, cloud and options — **no file editing needed**. Made with RetroArch in mind, but it works with any folder.

🪶 Light: idle it uses a few MB and almost 0% CPU. `rclone` only runs while syncing.
🧩 Built with [rclone](https://rclone.org) (two-way sync) + an [AutoHotkey v2](https://www.autohotkey.com) script.

## ✨ What it does

- 🔄 **Two-way sync** between all your PCs, automatically.
- 🚦 **Tray icon that changes color**: 🔵 syncing · 🟢 up to date · 🔴 error · 🟠 conflict.
- 🕹️ **Games tab** with a card per game, screenshots, and **restore older versions** of a save state.
- 🛟 **Backups of everything** a sync replaces or deletes, plus **conflict copies** — nothing gets lost.
- 🛡️ **Delete protection**: stops a sync that would delete too much.
- 🚫 **Exclusions** (logs, shaders, caches…) per folder, picked from a **tree with check boxes**.
- 👀 **Preview before the first sync**, **export/import settings** between PCs and **space by folder** (PC, cloud, backups).
- ⏸️ **Pause** from the tray or the Status page, a friendly notice when the cloud hits its daily limit (it retries on its own), the cloud in use shown on the Status page, and a **Check space** button in the Cloud tab.
- 🧭 **Portable paths** (`%DOCUMENTS%\…`) and **Add from cloud** for PCs with a different user name.
- 🗂️ Comfortable with **dozens of folders**: search, per-folder status, overflow menus.
- ☁️ **Many clouds**: OneDrive, Dropbox, MEGA / Google Drive (via their app), pCloud, Box, Filen, NAS / network folder, Backblaze B2, Nextcloud…

## 🚀 Install (on every PC)

No administrator rights needed.

1. 📦 Unzip the `SyncDood` folder anywhere.
2. 🖱️ Double-click **`Install.bat`**. It downloads rclone and AutoHotkey v2 (portable, in the same folder) and opens the app. If it finds earlier SyncDood / RSY / SaveSync settings on the PC, it offers a **clean install** (same as *Uninstall SyncDood…*: deletes settings, history, log, the cloud credentials stored on that PC and rclone's records; asks whether to keep the backups; never touches your cloud or your saves/states folders).
3. 🧙 The wizard asks for: your **SAVES** folder, your **STATES** folder, *(optional)* any other folders, and your **cloud** (it only shows what that cloud needs; for the easiest ones you just sign in once in the browser). In the folder dialog you can **type or paste the path** in the address bar.
4. ✅ Done: it sets up run-at-startup. The first sync of each folder starts after you confirm a **preview** (see below).

📁 Folders can live in different paths on each PC. What must match is the **cloud** and the **name** of each folder (`saves`, `states`, or whatever you named the extra ones).

🧭 **Same folder, different user name.** When you add a folder that sits inside your Windows user folder (for example `C:\Users\Ana\Documents\My Game`), SyncDood offers to store it as **`%DOCUMENTS%\My Game`**, so the same location is valid on a PC whose user is called something else. Available tokens: `%DOCUMENTS%`, `%SAVEDGAMES%`, `%DESKTOP%`, `%APPDATA%`, `%LOCALAPPDATA%`, `%USERPROFILE%` (any other Windows variable works too). You can also type them straight into the path box. On a new PC use *Folders → Add from cloud…*: it lists the folders that already exist in your cloud and only asks where each one goes on that PC. **Important:** the cloud folder's *contents* are placed directly **inside** the folder you choose. If your laptop synced `Documents\FIFA 17\settings` and the cloud folder is called `FIFA_17`, on the other PC pick `Documents\FIFA 17` (the folder that *contains* `settings`), not `settings` itself. The dialog shows what the cloud folder contains, warns in amber if you would end up with `settings\settings`, and offers to use the folder above.

**First sync:** this PC is merged with the cloud. Before it starts, SyncDood shows a **preview** (files and size on this PC and in the cloud, and which version wins when a file is on both sides) and asks you to confirm; if both sides are empty it doesn't ask. Automatic syncs never start a first sync by themselves: the folder waits as *first sync pending* until you press *Sync now*. What exists on only one side is copied to the other; if a file exists on both, the **newest wins** and the loser goes to the backups. You can install on your PCs in any order. Prefer one side to always win? *Options → First sync: who wins* (newest · this PC · the cloud).

**Coming from RSY or SaveSync?** 🔁 SyncDood is the new name. On first launch it moves your old settings (`%LOCALAPPDATA%\RSY` or `\SaveSync`) to `%LOCALAPPDATA%\SyncDood` and keeps your cloud and folders as they were. The startup shortcut is recreated. Then you can delete the old folder and the old `.exe`.

## ☁️ Which cloud should I pick?

⭐ = easiest. Free space is approximate and changes over time.

| Cloud | What it asks for | Notes |
|---|---|---|
| ⭐ **OneDrive** | Just sign in | ~5 GB free, comes with Windows. With work/school accounts, if the browser says **"admin approval required"**, use another cloud. |
| **Dropbox** | Just sign in | ~2 GB free. |
| ⭐ **Your cloud app's folder** | Pick a folder | The easy way to use **MEGA** (20 GB free, the most), **Google Drive** (15 GB), iCloud and similar through their desktop app. |
| **Network folder / NAS / your server** | Pick a folder | No accounts or keys, e.g. `\\MyNAS\saves` or `Z:\saves`. |
| **pCloud** | Just sign in | ~5 GB at the start (~10 GB with tasks/invites). |
| **Box** | Just sign in | ~10 GB free; 250 MB max per file. |
| Filen *(advanced)* | Email, password, API key | 10 GB free, end-to-end encrypted. Needs rclone 1.73+. |
| Google Drive direct *(advanced)* | Your own client ID and secret | Google is withdrawing rclone's simple access in 2026. |
| Backblaze B2 *(advanced)* | keyID, applicationKey, bucket | For technical users. |
| Nextcloud / ownCloud *(advanced)* | Server, user, app password | Your own server or compatible NAS. |
| Other *(advanced)* | rclone's manual wizard | Create a remote named `syncdood`. |

⚠️ Every cloud must keep the files' **modification date** ("newest wins" depends on it). MEGA connected directly to rclone doesn't handle it well: use MEGA through its desktop app with *Your cloud app's folder*.

<details>
<summary>📂 <b>Your cloud app's folder</b> (recommended for MEGA and Google Drive)</summary>

1. Install the app (*MEGA*, *Google Drive for desktop*…) and sign in.
2. In SyncDood choose **Your cloud app's folder** and pick a folder inside it. SyncDood creates a `SyncDood` subfolder there.
3. Repeat on every PC with the **same account**.

**MEGA, step by step:** install the MEGA desktop app and sign in · in the app, create a sync between a new local folder (for example `C:\MEGA\SyncDood-hub`) and a new folder in your MEGA · in SyncDood choose *Your cloud app's folder* and select that local folder · on the other PCs repeat with the same account and let the MEGA app finish downloading before the first sync. Mind the transfer quota of free accounts.

Keep in mind: the cloud app must be running, and the folder must be available offline (Google Drive: *Mirror files*; OneDrive: *Always keep on this device*). Changes take a bit longer to arrive because two syncs happen in a row.
</details>

<details>
<summary>🖥️ <b>Network folder, NAS or your own server</b></summary>

1. Share a folder (SMB/Samba: Windows, Synology, QNAP, TrueNAS, Linux with Samba…).
2. Check you can open it from Explorer (`\\MyNAS\saves`) or give it a drive letter.
3. In SyncDood choose **Network folder, NAS or your own server** and pick it (or paste the path). SyncDood creates a `SyncDood` subfolder inside.
4. Repeat on every PC pointing to the **same shared folder**.

If the NAS is off or you're away from home, the sync fails and retries next round; nothing is lost. To reach it from outside: use a VPN into your network, or install Nextcloud and use the *Nextcloud / ownCloud* option.
</details>

<details>
<summary>🔐 <b>Filen direct</b> (advanced)</summary>

rclone needs your email, password and an **API key**, which Filen only gives through its command-line tool (once per account):

1. Download the [Filen CLI](https://docs.cli.filen.io/) (it doesn't need to stay installed).
2. Log in and run `export-api-key`. Copy the key.
3. In SyncDood choose **Filen (advanced)** and paste email, password and key. Repeat on every PC.

Needs **rclone 1.73+** (`Install.bat` / `Build.bat` download the current one; replace an older `rclone.exe`). If you change your Filen password, export the key again and re-enter the three values in *Cloud*.
</details>

<details>
<summary>🔑 <b>Google Drive direct</b> (advanced)</summary>

Google is withdrawing rclone's shared app during 2026, so you need your own credentials:

1. In [console.cloud.google.com](https://console.cloud.google.com) create a project.
2. Enable the **Google Drive API**.
3. *OAuth consent screen*: **External**, add your email as test user and **publish ("In production")** — in "Testing" access expires after 7 days.
4. *Credentials → Create credentials → OAuth client ID* → **Desktop app**.
5. Paste the *client ID* and *secret* in the wizard.

"Unverified app" warning? It's your own app, continue. Too much work? Use *Your cloud app's folder*.
</details>

## 🪟 The window

**Double-click the tray icon** to open it. **Right-click** for the menu: *Open SyncDood*, *Sync now*, *Pause* (1 hour / 4 hours / until resumed), open folders / log, *Check for updates*, *About / Credits*, *Support on Patreon*, *Project on GitHub*, *Run at startup*, *Exit*.

Eight tabs. Changes to folders, cloud and options restart SyncDood by themselves. The theme (light / dark) follows Windows, or choose it in *Options → Appearance*.

| Tab | What it's for |
|---|---|
| 📊 **Status** | Header color sums it up (🔵🟢🟠🔴), last sync, next check, the **cloud in use**, a **Pause / Resume** button, a progress bar, each folder with its own **Sync** button, and recent activity. |
| 📜 **History** | Latest 200 events per folder, with a folder filter: ↑ Uploaded · ↓ Downloaded · ✕ Deleted · ⚠ Conflict · ✖ Failed. |
| ⚠️ **Conflicts** | Only when two PCs changed the same file: compare both versions (size, date, who saved it and the **screenshot** if it's a state) and **keep the one in use or use the other**. No pop-ups: a ⚠ with a number appears next to the tab. |
| 🕹️ **Games** | Your save states, game by game. See below. |
| 📁 **Folders** | Add folders (also **from the cloud**), change, remove and open them · search and per-folder status, comfortable with dozens of folders · **sync only the selected one** · **options and exclusions** (tree with check boxes, empty folders) · *First sync / repair*. |
| ☁️ **Cloud** | Shows the current cloud (also the app's name for cloud-app folders, e.g. *MEGA folder*), **change it** and **test the connection**. **Check space**: what SyncDood uses in the cloud and, when the cloud reports it, used / total / free. **Space by folder**: size on this PC, in the cloud and in cloud / local backups. |
| ⚙️ **Options** | Language, appearance, check interval, emulator process, waits, who wins on first sync, backups, startup, updates, test mode, PC name, **export / import settings**. |
| ℹ️ **About** | Version, credits and *Check for updates*. |

💡 The History comes from rclone's own log, so it shows what rclone really decided. A ↓ means **the cloud had a different version** (usually saved from another PC).

📌 A folder's **name** is its subfolder in the cloud and must be the same on all PCs; the local path can differ.

### 🕹️ Games tab

- 🃏 **One card per game** (screenshot, emulator, number of states). Search by name or emulator, sort A–Z or by most recent.
- 🔍 **Double-click a game** to see its slots: screenshot, date, **origin** (the name of the PC that uploaded it) and size.
- 🎛️ **Recognized states:** **RetroArch** (`.state`, `.state1`… `.state.auto` + its `.png`), **DuckStation** (`SLUS-00594_1.sav` in a `savestates` folder), **PCSX2** (`.p2s`), **Dolphin** (`.s01`–`.s10`), **Azahar** (`.cst`), **PPSSPP** (`.ppst` + `.jpg`). Add each emulator's states folder in *Folders* like any other.
- ⏪ **Older versions / Restore…**: select a slot (or double-click) to list the copies SyncDood **already keeps** in the backups (this PC's, and with *Include cloud backups* the cloud's too), each with its screenshot. **Restore** first saves the current state to the backups (so you can undo), makes the chosen one the newest, and it reaches your other PCs on the next sync.
- 🔎 **Enlarge / Compare…**: big view of the current screenshot next to the selected version, to compare before restoring.
- 🏷️ **Real names:** some emulators save the game as an ID (serial / title ID).
  - **Rename game…** gives it a readable name (saved in `%LOCALAPPDATA%\SyncDood\gamenames.ini`, one `ID=Name` per line, e.g. `SLUS-00594=Final Fantasy VII`; you can also edit the file by hand).
  - **Find names** looks up names for games still showing an ID: DuckStation via the libretro/Redump list, Dolphin via GameTDB. It downloads only when you press it, and **your own names always win**. Azahar and PPSSPP IDs can only be renamed by hand.
- 🧹 **Purge versions…** deletes old state versions **on this PC and in the cloud**, after showing how many. Choose how many days to keep.
- 🖥️ **Origin name:** set it in *Options → Name of this PC* (defaults to the Windows computer name). The only extra thing stored is a small text list per PC of which states it uploaded (in the cloud under `_pcs/`, outside your synced folders).

<details>
<summary>🚫 <b>Emulators without file-based states</b></summary>

They don't appear in Games, but their regular game saves do sync if you add their folder in *Folders*: **Ryujinx/Ryubing** and **Cemu** have no save states; **RPCS3** and **Vita3K** (game saves only); **TeknoParrot** depends on each game; **Xemu** keeps snapshots inside the `.qcow2` disk, so they can't be listed per slot.
</details>

<details>
<summary>🗂️ <b>Empty folders</b></summary>

They sync as real folders on clouds that have them (OneDrive, Dropbox, pCloud, Nextcloud, folder/NAS…). **Backblaze B2** has no real folders, so empty ones are ignored there; emulators recreate what they need.

It is a **per-folder option** (on by default): when you add a folder, or later in *Folders → Options and exclusions…*, the switch *Also sync empty folders (keep the folder structure)* decides whether the empty sub-folders are created on your other PCs too. Turn it on when a game or emulator needs its folder tree to exist even if it is empty.
</details>

### 📂 Only part of a folder?

By default a folder syncs **everything inside it**, and the dialog says so with the exact path and item count. Pick the way that fits:

1. **You need one subfolder** (for example `FIFA 17\settings`): the easiest is to add **that subfolder itself** as its own SyncDood folder. No tree, no rules, and new files elsewhere in the game folder are never touched.
2. **You need almost everything except a few things** (caches, shaders, logs): add the folder and tick *I only want to sync PART of this folder*, then uncheck what you don't want, or use the extra rules.
3. **You need a few files or folders out of a big folder**: add the folder, tick *I only want to sync PART of this folder*, press *Uncheck all*, check what you want and turn on **Only sync what is checked**. Only the checked items sync; new files or folders that appear later are **not** synced. (Without that switch the tree only *excludes* what you uncheck, so anything new **would** be synced.)

SyncDood also asks for confirmation if you pick a very general folder (your user folder, Documents, Desktop, Downloads, AppData or a whole drive) or one with thousands of items.

### 🚫 Exclusions

*Folders → Options and exclusions…* (and the same panel when you add a folder, once you tick *I only want to sync PART of this folder*) shows the folder as a **tree with check boxes**: uncheck any file or whole folder you do **not** want to sync (unchecking a folder unchecks everything inside it). Only **checked** items are synced (uploaded to your cloud and copied to your other PCs). *Check all* / *Uncheck all* buttons and a live count help you; if nothing is checked SyncDood won't accept it. Below the tree there is a box for **extra rules**, one per line (rclone syntax, case-insensitive):

| Rule | Excludes |
|---|---|
| `*.log` | files by name, in any subfolder |
| `shaders/` | any folder called `shaders` and its contents |
| `/logs/` | only the `logs` folder at the root |
| `/xbox_hdd.qcow2` | one specific file at the root |

In **Only sync what is checked** mode the extra rules box is not used (the checked items are the rules), and the Folders list shows *Only checked* for that folder. If the folder has more than 4,000 items the tree can't list them all, so pick a subfolder or use the normal mode.

There are buttons with common suggestions (`*.log`, `shaders/`, `cache/`, `*.qcow2`). What you uncheck in the tree is saved as exact-path rules (`/collections/old/`), so tree and rules always agree; trees show up to 4,000 items (use the rules for the rest).

- 🔁 After editing rules, the next sync re-lists that folder by itself (merges, **newest wins**, deletes nothing).
- 🔒 Excluded items are ignored **on both sides and never deleted**: what was already in the cloud stays (delete it by hand to free space).
- 💻 Rules live in `%LOCALAPPDATA%\SyncDood\exclude\<folder>.txt` and are per PC.

## ⏱️ When it syncs

- 🏁 15 s after SyncDood starts.
- ⏲️ Every few minutes (5 by default).
- 😴 ~20 s after **waking from sleep** (gives WiFi time to come back).
- 🕹️ ~3 s after you **close the emulator** (`retroarch.exe` by default), to upload the last save/state.
- 🖱️ Manually: tray menu or window → *Sync now* (it works even while paused).

⏸️ **Pause:** tray menu → *Pause* (1 hour, 4 hours or until you resume) or the button on the Status page. While paused no automatic syncs run; *Sync now* still works.

☁️ **Cloud limit:** if the cloud refuses because of a daily cap or quota (e.g. Backblaze B2), SyncDood stops retrying, shows when it will try again and resumes by itself. For B2 that is 12:00 AM GMT. If you sync manually during the block, it asks first.

While the watched emulator is open it **doesn't sync automatically** (the emulator rewrites the file while it uploads, which causes conflicts); it syncs right after you close it. You can still press *Sync now* any time (*Options → "Don't sync automatically while the emulator is open"* turns this on/off).

If a sync fails (e.g. no internet after waking), it retries twice 45 s apart before warning you, then keeps trying on the normal timer.

## 🛟 Conflicts and backups

A **conflict** = the same file changed on **both PCs** since the last sync.

1. 🏆 The **newest** version wins and keeps its normal name on both PCs.
2. 📦 The loser **moves to the backups**, not lost: `<backupDir>\<folder>\conflicts\<date_time>\...`
3. 🔶 The tray icon turns **amber** (steady, no blinking, no pop-ups), a ⚠ event appears in History and a **⚠ with a number** shows up next to the *Conflicts* tab. You don't have to do anything: when you feel like it, open the tab, compare both versions and press **Keep the one in use** or **Use the other one** (the one in use is saved in the backups first). *Mark all as reviewed* clears the notice in one click.

Besides that, everything a sync **deletes or overwrites** is backed up **per day**, on the PC (`<backupDir>\<folder>\<yyyy-MM-dd>\`) and in the cloud (`_backup/<folder>/<yyyy-MM-dd>/`).

- 🧽 Local backups clean themselves after `backupKeepDays` (30 by default). Cloud ones are not removed automatically unless you turn on *Also clean old backups and conflicts in the cloud* in Options (same days, at most once a day; on Backblaze B2 it deletes for good).
- 🎮 The automatic cleanup **never deletes save-state versions** (`.state`, `.state1`, `.state.auto` and their screenshots): they stay in *Older versions* until you use **Games → Purge versions…**.
- ℹ️ Backups are made when a **sync replaces or deletes** a file, not every time you save in the emulator, and are kept **per day**: if a file is replaced several times in a day, the latest copy of that day stays.
- 🩹 **To recover something:** *Options → Open backups* (or tray menu → *Open backups folder*) and copy the file back.

## 🔄 Updates

SyncDood checks the GitHub *Releases* (`kyaaadood/SyncDood`) in the background, at most once a day, and silently if nothing is new. You can also use *Check for updates* in the tray menu or *About*. If there's a newer version it offers to **install it by itself**: SyncDood closes for a moment, downloads the new version, replaces its files, opens again and tells you it was updated. Your settings, history and backups stay as they are. Turn the check off in *Options*.

- With the single **`SyncDood.exe`** it downloads the release's `.exe`. With the loose script (`Install.bat`) it downloads the release's `.zip` and copies it over the program folder (your `rclone.exe` and portable AutoHotkey are kept).
- If the release has nothing installable it just opens the download page. If the program lives in a protected folder (such as *Program Files*), Windows may refuse to replace the files; move it to a normal folder or update by hand.
- It needs Windows 10 or newer (it uses the built-in `tar` to unpack the zip).

<details>
<summary>🏷️ <b>Publishing a new version</b> (for the developer)</summary>

The version lives in **one place**: the `AppVersion` line at the top of `SyncDood.ahk` (now `"0.2.1"`).

1. Change `AppVersion` (e.g. `"0.2.1"`).
2. Create a GitHub *Release* in `kyaaadood/SyncDood` with the same number and a leading `v` (`v0.2.1`), and **attach the files the updater installs**: `SyncDood.exe` (from `dist\` after `Build.bat`) for the single-file version, and a `.zip` with the `SyncDood` folder (without `rclone.exe` or `ahk\`) for the loose-script version. Without a `.zip`, GitHub's automatic source zip is used.
3. Running copies compare that tag with their `AppVersion` and offer the download if the tag is newer.

`Build.bat` also reads `AppVersion` and writes it into `SyncDood.exe`'s properties.
</details>

<details>
<summary>📦 <b>Build a single <code>SyncDood.exe</code></b></summary>

For handing out **one file** (no Install.bat, no AutoHotkey install, no downloads on the target PC):

1. On Windows, double-click **`Build.bat`**.
2. First time it downloads rclone, AutoHotkey v2 and Ahk2Exe (cached in `build\cache`) and compiles.
3. You get **`dist\SyncDood.exe`**. Copy it to any PC and open it: the usual wizard appears.

It contains the AutoHotkey runtime, the script, `rclone.exe` and the icons. On open it unpacks rclone and the icons to `%LOCALAPPDATA%\SyncDood\bin` (only when the version changes). Settings stay in `%LOCALAPPDATA%\SyncDood\`.

Keep in mind:
- ⚖️ ~60 MB, almost all rclone.
- 📌 Leave the `.exe` in a fixed folder (e.g. `C:\Programs\SyncDood`): run-at-startup points to it. If you move it, turn *Run at startup* off and on.
- 🔁 To update rclone, delete `build\cache\rclone.exe` and run `Build.bat` again.
- 🛡️ The `.exe` isn't signed: SmartScreen may warn the first time ("More info → Run anyway"), and some antivirus programs wrongly flag AutoHotkey executables. Add an exception or build it yourself on that PC.
- 🌐 If your network blocks downloads, put `rclone.exe`, `AutoHotkey64.exe` (v2) and `Ahk2Exe.exe` in `build\cache`.
</details>

## 🎨 Icons

The logo is an **S** that changes color with the sync state:

| Icon | Meaning |
|---|---|
| 🔵 Blue | Syncing |
| 🟢 Green | All synced (the tooltip shows the time and how many files went up ↑ and down ↓) |
| 🔴 Red | The sync failed (the tooltip says why) |
| 🟠 Amber | There are conflicts to review in the *Conflicts* tab (nothing is lost; it goes back to green when you have reviewed them) |

<details>
<summary>🖌️ <b>Regenerate the icons</b></summary>

```
python tools/make_icons.py
```

Requires [Pillow](https://python-pillow.org). Generates `icons/ok.ico`, `syncing.ico`, `error.ico` and `conflict.ico` (and the `.png` files used here).
</details>

## 📤 Export / import settings

*Options → Export settings…* saves your folders (with portable paths), exclusions and options to a single `.ini` file. **Cloud passwords and tokens are not included**: on the other PC connect the cloud in the *Cloud* tab. *Import settings…* replaces folders that already exist with the same name (marked in the list), restarts SyncDood, and each folder does its first sync with a preview.

## ⚙️ Settings (`config.ini`)

You normally **don't need it**: everything is changed from the window. It lives in `%LOCALAPPDATA%\SyncDood\` with `sync.log` and the `data\` folder (*Open config.ini* in *Options*; after editing by hand, exit and reopen SyncDood).

<details>
<summary>📋 <b>All the keys</b></summary>

| Key | What it does | Default |
|---|---|---|
| `language` | `auto` (Windows language), `en` or `es` | `auto` |
| `firstSyncWins` | Who wins the first sync: `newer`, `local`, `cloud` | `newer` |
| `intervalMin` | Minutes between checks | `5` |
| `watchProcess` | Emulator process; syncs when it closes (empty = off) | `retroarch.exe` |
| `resumeDelaySec` | Seconds to wait after waking from sleep | `20` |
| `pcName` | Name of this PC, shown as the origin of your states (empty = Windows computer name) | *(empty)* |
| `parallelOverride` | Files transferred at once (1-32; checks run at twice that). `0` = automatic: 8 for Backblaze B2, Nextcloud, folder and NAS, 4 for the rest (higher can make Google Drive, OneDrive or Dropbox rate-limit you). Set in Options (Auto / Manual); changing the cloud goes back to automatic | `0` |
| `maxDeletePct` | Delete protection: a sync that would delete more than this % of a folder's files is stopped before touching anything. A manual *Sync now* shows what would be deleted (this PC / cloud) and asks to continue; automatic syncs just leave that folder stopped. `0` = off | `25` |
| `pruneCloudBackups` | `1` also cleans old backups and conflicts in the cloud (`_backup/`), same days as `backupKeepDays`, at most once a day. Save-state versions stay; your synced folders are never touched. On Backblaze B2 it deletes for good (frees space) | `0` |
| `backupDir` | Local backups folder (outside the synced folders) | `%LOCALAPPDATA%\SyncDood\backups` |
| `backupKeepDays` | Days local backups are kept (`0` = forever) | `30` |
| `checkUpdates` | `1` = check for updates on startup | `1` |
| `dryRun` | `1` = test mode: only writes to `sync.log` what it would do | `0` |
| `settleSec` | Seconds a file must stay untouched before syncing (waits up to ~45 s; `0` = don't wait) | `10` |
| `theme` | `auto` (follows Windows), `light` or `dark` | `auto` |
| `pauseWhileRunning` | `1` = no automatic syncs while the watched emulator is open (syncs when you close it) | `1` |

With *Your cloud app's folder* the path can differ on each PC; what must match is the cloud account.
</details>

## 🧹 Uninstall and cleanup

*Window → Options*:

- 🗑️ **Uninstall SyncDood…** removes the startup shortcut, `%LOCALAPPDATA%\SyncDood` (settings, history, log), the rclone connection to your cloud (credentials stored on this PC), rclone's sync records for SyncDood and any RSY / SaveSync leftovers. It asks separately about deleting the local backups and the program itself (loose scripts: only SyncDood's own files, never the whole folder). **It never touches your cloud (files or its `SyncDood` folder) nor your saves/states folders.**

The old `.exe` files (wherever you put them) and any `SaveSync` / `RSY` folder inside your cloud are not deleted automatically; remove them by hand if you don't need them.

## 🆘 Troubleshooting

<details>
<summary>Open the list</summary>

- **Install.bat closes or can't run scripts:** the PC's policy may block PowerShell. Put `rclone.exe` next to `SyncDood.ahk`, install [AutoHotkey v2](https://www.autohotkey.com/) and open `SyncDood.ahk` directly.
- **Downloads are blocked:** get `rclone.exe` from [rclone.org/downloads](https://rclone.org/downloads/), put it next to `SyncDood.ahk`, and install AutoHotkey v2 separately.
- **Backblaze B2 says you exceeded the daily limit:** those are the account's daily caps (downloads and transactions). They reset at 12:00 AM GMT. SyncDood notices the refusal, stops retrying and shows when it will try again (you can also *Pause* it). Check *Caps & Alerts* in your account if you want to raise them. A misconfigured or very large folder uses them fast.
- **Red icon asking for "First sync / repair":** a sync was interrupted at a bad moment, or something was moved/deleted by hand. *Window → Folders → First sync / repair…*
- **The header shows an error but it's cut off:** click **Details** (top right) for the full message and the latest `sync.log` error lines.
- **"cannot find prior Path1 or Path2 listings" in the log:** rclone has no sync record for that folder and cloud (e.g. after migrating or changing the cloud name). SyncDood detects it and runs a first sync by itself (merges both sides, deletes nothing).
- **`.syncconflict1` on a state/save while you play:** the emulator rewrites the file while rclone uploads it. Nothing is lost: the newer copy stays and the other goes to *backups → conflicts*. SyncDood avoids this by not syncing automatically while the emulator runs.
- **See the log:** tray menu → *Open log* (`sync.log`, keeps the last 2 days).
- **Deleting a save by hand** reaches the other PCs on the next sync (that's two-way sync), but it's backed up. If you delete more than 50% of the files at once, rclone refuses to sync as a safeguard.
</details>

## 📝 Good to know

- 🕐 Keep your PCs' clocks right ("newest wins" depends on file dates).
- 📏 States are bigger than saves: watch your cloud space (and the backups').
- 🚫 Avoid playing the same game on two PCs at once: the conflict is detected, but one session ends up only as a backup.
- 🧪 `rclone bisync` is marked *beta* by the rclone project. It works well with small folders, but keep a separate copy of your saves once in a while.
- 🌍 The texts follow the Windows language (Spanish if Windows is in Spanish, English otherwise; you can force it in *Options*).

## 💛 Credits

Made by **KyaaaDood** with Claude AI. 🤖✨

Follow my work on [GitHub](https://github.com/kyaaadood) and, if you want to support the project, you can do it on [Patreon](https://www.patreon.com/cw/KyaaaDood). ☕

SyncDood uses [rclone](https://rclone.org) (MIT license) and [AutoHotkey v2](https://www.autohotkey.com) (GPLv2); see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
