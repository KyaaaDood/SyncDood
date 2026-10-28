# Changelog

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
