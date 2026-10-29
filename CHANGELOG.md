# Changelog

## v0.2.1

### Added
- **Automatic update** (like InputDood): when a newer release exists, *Yes* now downloads and installs it by itself. SyncDood closes for a moment, a small helper swaps the files, SyncDood opens again and shows "SyncDood was updated to version X". With the single `SyncDood.exe` it downloads the release's `.exe`; with the loose script (`Install.bat`) it downloads the release's `.zip` (or GitHub's source zip if there is none), unpacks it and copies it over the program folder, keeping `rclone.exe` and the portable AutoHotkey. Settings, history and backups are never touched. It waits if a sync is running, and falls back to opening the download page if the release has nothing installable.
- **Simple mode in the folder dialog**: a new folder now syncs **everything inside it** by default. The dialog says so in plain words, with the exact path and the number of items, and the tree only appears if you tick *I only want to sync PART of this folder*. A tip suggests picking the subfolder directly when that is all you need. Editing a folder that already has exclusions opens it in the "part of the folder" mode; switching to simple mode removes its exclusions.
- **Only sync what is checked** (whitelist) in the folder dialog: inside *I only want to sync PART of this folder*, a new switch makes the **checked items the only ones that sync**; anything new that appears later in that folder is *not* synced. Ideal for a few files or folders out of a big directory. The Folders list shows *Only checked* in the Exclusions column, and the mode is kept when you export/import settings. In this mode the extra rules box is not used, and folders too big to list in the tree (over 4,000 items) must use a subfolder or the normal mode.
- **Wrong-level check when adding from the cloud**: the dialog shows what the cloud folder contains and that those items go directly *inside* the chosen folder. If the cloud folder already has a folder named like the one you picked (for example picking `...\FIFA 17\settings` when the cloud holds `settings`), it warns in amber and, on *Add folder*, offers to use the folder above instead of ending up with `settings\settings`.
- **Warning for very general folders** (your user folder, Documents, Desktop, Downloads, AppData or a whole drive): asks for confirmation before adding.
- **Conflicts tab**: when two PCs changed the same file, SyncDood still keeps the newest one and saves the other, but now you can review it whenever you like. A ⚠ with the number of pending conflicts appears next to the tab (no pop-ups). Pick one to compare both versions side by side (size, date, who saved it and, for states, the screenshot with a big *Compare screenshots* view) and choose **Keep the one in use** or **Use the other one** (the one in use is backed up first; the chosen one syncs to your other PCs and, if the emulator is open, it warns you first). *Mark all as reviewed* clears them at once. Notices survive restarts (`data\\conflicts.tsv`); a notice disappears by itself if the cleanup removes its saved copy (states are never removed), and a state with its screenshot counts as one notice.
- **Pause**: tray menu (1 h / 4 h / until resumed) and a Pause/Resume button on the Status page. While paused, automatic syncs stop; manual *Sync now* still works.
- **Friendly cloud-limit notice**: when the cloud refuses because of a daily cap or quota (e.g. Backblaze B2), SyncDood stops insisting, shows when it will retry on its own (B2 resets at 12:00 AM GMT) and resumes automatically. A manual sync during the block asks before trying.
- **Cloud in use** is shown on the Status page and in the Cloud tab, also for cloud-app folders (MEGA, Google Drive, OneDrive, Dropbox...). It is detected from the folder path.
- **Check space** (Cloud tab): how much SyncDood uses in the cloud and, when the cloud reports it, the account's used / total / free space.
- **Space by folder** (Cloud tab): size on this PC, in the cloud, in cloud backups and in local backups for every folder, with a total. It fills in folder by folder.
- **Preview before the first sync**: shows files and size on this PC and in the cloud, and which version wins when a file exists on both sides, and asks before merging. If both sides are empty it doesn't ask.
- **Export / import settings** (Options): folders (portable paths), exclusions and options in one `.ini` file. Cloud passwords and tokens are never included. Importing replaces folders with the same name (marked in the list), restarts the app and each folder runs its first sync with a preview.
- **Safety notice when adding a folder**: with more than 4,000 items it asks for confirmation first (usually the parent folder was picked by mistake, e.g. Documents instead of the game's folder).

### Changed
- **Clearer "What to sync" tree** (when choosing part of a folder): *Check all* and *Uncheck all* buttons, a plain explanation that **checked items are uploaded to your cloud and copied to your other PCs**, and a live count ("N items will be synced to the cloud · M will NOT"). If nothing is checked it warns in amber and won't accept the dialog, since nothing would sync.
- Automatic syncs no longer start a first sync on their own: the folder stays as *first sync pending* until you press *Sync now*.
- The tray icon no longer blinks on a conflict: it stays amber (steady) while there are conflicts to review, and the Status header button becomes *Review*.
- Tab numbers changed (Conflicts is the 3rd tab); this only affects a window reopened right after a restart.
- README (EN/ES) updated: first sync with preview, pause, cloud limit, space tools, export/import and the Conflicts tab.

## v0.2

### Added
- **Portable paths**: a folder's location can use `%DOCUMENTS%`, `%SAVEDGAMES%`, `%DESKTOP%`, `%APPDATA%`, `%LOCALAPPDATA%` or `%USERPROFILE%`, so it works on PCs with a different Windows user name. SyncDood offers it automatically when you pick a folder inside your user profile.
- **Add from cloud…** (Folders tab): lists the folders that already exist in your cloud and only asks where each one goes on this PC.
- **New folder dialog**: name, location, a **tree with check boxes** to choose what NOT to sync (files or whole folders), extra rules, and a per-folder switch to **also sync empty folders** (keeps the folder structure). The same panel opens from *Options and exclusions…*.
- **Many folders**: search box, per-folder status column and counter in *Folders*; the Status page shows the folders that need attention first plus a summary line; the History filter moves extra folders to a "More" menu.
- **Clean install**: `Install.bat` detects earlier SyncDood / RSY / SaveSync settings and offers to wipe them (same as *Uninstall SyncDood…*, never touches the cloud or your saves).

### Fixed
- *Uninstall SyncDood…* crashed with "OldLink / OldAppDir has not been assigned".
- Layout with different DPI / monitors (laptop screen vs external 4K): banner, folder cards and the sidebar selection bar are now positioned from the real control scale; the window rebuilds itself when moved to a monitor with another scale.
- Exclusion rules now handle file names with brackets, such as `Game [USA].sav`.

### Removed
- The "Clean old SaveSync" button: *Uninstall SyncDood…* and the clean install in `Install.bat` already remove RSY / SaveSync leftovers.

### Docs
- README (EN/ES): portable paths, empty folders option, tree exclusions, clean install, MEGA step by step, Backblaze B2 daily-cap tip.

### Changed
- Lists (History, Games, Folders) no longer draw an inner box and use the full window width and height.
- Folder name no longer asked in a separate prompt; it is part of the new folder dialog.
