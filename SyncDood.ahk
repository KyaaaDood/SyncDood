; ============================================================================
; SyncDood.ahk  -  Keeps your save / state folders in sync through your cloud
;             Sincroniza tus carpetas de partidas (saves / states) con la nube
; Requires / Requiere: AutoHotkey v2 + rclone (>= 1.66; Filen needs >= 1.73).  Install.bat downloads both.
;
; Made by KyaaaDood with Claude AI.   https://github.com/kyaaadood/SyncDood
;
; Language: follows Windows (English / Español; anything else falls back to English).
; Everything (folders, cloud, options) is editable from the app window; no need to
; touch config.ini.
;
; Icons:  icons\syncing.ico (blue) | icons\ok.ico (green) | icons\error.ico (red) | icons\conflict.ico (amber: conflicts to review)
; Config and data: %LOCALAPPDATA%\SyncDood\  (config.ini, sync.log, data\)
; ============================================================================
#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent
SetWorkingDir(A_ScriptDir)

;@Ahk2Exe-SetName SyncDood
;@Ahk2Exe-SetDescription SyncDood - Save sync
;@Ahk2Exe-SetCopyright KyaaaDood
;@Ahk2Exe-SetVersion 0.2.1.0

; ---------------------------------------------------------------- Paths -----
AppDir      := EnvGet("LOCALAPPDATA") "\SyncDood"
IniFile     := AppDir "\config.ini"
LogFile     := AppDir "\sync.log"
DataDir     := AppDir "\data"
HistFile    := DataDir "\history.tsv"
ConfFile    := DataDir "\conflicts.tsv"
IconDir     := A_ScriptDir "\icons"
StartupLink := A_Startup "\SyncDood.lnk"
RemoteName  := "syncdood"     ; name of the rclone remote created by the wizard

; ---- Project info (shown in the About tab) ----------------------------------
; >>> THE VERSION LIVES HERE. Keep it equal to your GitHub release tag (v0.2.1). <<<
AppVersion  := "0.2.1"
AppAuthor   := "KyaaaDood"
GithubRepo  := "kyaaadood/SyncDood"     ; "user/repo" (also used by the update checker)
GithubUrl   := "https://github.com/kyaaadood"       ; author page (About tab and tray menu)
PatreonUrl  := "https://www.patreon.com/cw/KyaaaDood"

; ---- Migration from the old names (RSY, SaveSync) ---------------------------------
; Moves settings, history and backups. The rclone remote and the cloud folder are
; kept as they were (they are stored in config.ini).
; (RSY was the name in between; SyncDood takes whichever of the two it finds, RSY first.)
for OldAppDir in [EnvGet("LOCALAPPDATA") "\RSY", EnvGet("LOCALAPPDATA") "\SaveSync"] {
    if (DirExist(OldAppDir) && !DirExist(AppDir)) {
        try {
            DirMove(OldAppDir, AppDir)
        }
    }
}
for OldLink in [A_Startup "\RSY.lnk", A_Startup "\SaveSync.lnk"] {
    if FileExist(OldLink) {
        try {
            FileDelete(OldLink)
        }
        try {
            EnableStartup()
        }
    }
}
DirCreate(DataDir)

; -------------------------------------------------------------- Language -----
L10n := BuildStrings()
Lang := DetectLang()
Dpi  := A_ScreenDPI / 96      ; provisional: BuildMain measures the scale the controls really get
BaseW := 0, BaseH := 0        ; client size (raw pixels) of the main window right after it was built

; ------------------------------------------------------------------ rclone ---
Rclone := A_ScriptDir "\rclone.exe"
if A_IsCompiled
    Rclone := ExtractBundle()          ; single .exe: rclone and icons are inside
else if !FileExist(Rclone)
    Rclone := "rclone.exe"
try {
    RunWait(Format('"{1}" version', Rclone), , "Hide")
} catch {
    MsgBox(T("err_no_rclone"), "SyncDood", "Iconx")
    ExitApp()
}

; ------------------------------------------------ Wizard (first launch) ------
if (IniRead(IniFile, "general", "configured", "0") != "1")
    RunWizard()

; ---------------------------------------------------------------- Config ----
Remote      := RTrim(IniRead(IniFile, "general", "remote", RemoteName ":SyncDood"), "/\")
FirstWins   := StrLower(Trim(IniRead(IniFile, "general", "firstSyncWins", "newer")))
IntervalMin := Integer(IniRead(IniFile, "general", "intervalMin", "5"))
WatchProc   := Trim(IniRead(IniFile, "general", "watchProcess", "retroarch.exe"))
ResumeDelay := Integer(IniRead(IniFile, "general", "resumeDelaySec", "20"))
BackupDir   := RTrim(IniRead(IniFile, "general", "backupDir", AppDir "\backups"), "\")
KeepDays    := Integer(IniRead(IniFile, "general", "backupKeepDays", "30"))
ParallelOverride := IniRead(IniFile, "general", "parallelOverride", "0")     ; 0 = automatic (see ParallelNow)
ParallelOverride := (IsInteger(ParallelOverride) && ParallelOverride >= 1 && ParallelOverride <= 32) ? Integer(ParallelOverride) : 0
CloudPrune  := (IniRead(IniFile, "general", "pruneCloudBackups", "0") = "1")    ; also clean old backups in the cloud
MaxDelPct   := IniRead(IniFile, "general", "maxDeletePct", "25")           ; stop a sync that would delete more than this % (0 = off)
MaxDelPct   := (IsInteger(MaxDelPct) && MaxDelPct >= 0 && MaxDelPct <= 100) ? Integer(MaxDelPct) : 25
Blocked     := Map()      ; folders stopped by the delete protection: name -> Map(n, total, toLocal, toCloud, names)
LastBlock   := ""
DryRun      := (IniRead(IniFile, "general", "dryRun", "0") = "1")
CheckUpd    := (IniRead(IniFile, "general", "checkUpdates", "1") = "1")
PauseRun    := (IniRead(IniFile, "general", "pauseWhileRunning", "1") = "1")
ThemePref   := StrLower(Trim(IniRead(IniFile, "general", "theme", "auto")))      ; auto | light | dark
SettleSec   := Integer(IniRead(IniFile, "general", "settleSec", "10"))          ; wait for files still being written
LastTrimTick := 0
PauseUntil  := IniRead(IniFile, "state", "pauseUntil", "")     ; "" | "forever" | yyyyMMddHHmmss (user pause)
CapUntil    := IniRead(IniFile, "state", "capUntil", "")       ; "" | yyyyMMddHHmmss (the cloud refused: limit reached)
LastCapWait := ""         ; set by SyncFolder when a sync stopped because of a cloud limit
CapName     := ""         ; folder that hit the limit
PauseMenu   := ""
PcName := RegExReplace(Trim(IniRead(IniFile, "general", "pcName", "")), '[\\/:*?"<>|]', "_")
if (PcName = "")
    PcName := RegExReplace(A_ComputerName, '[\\/:*?"<>|]', "_")     ; shown as the origin of your saves
PcLogs := Map()          ; cache: folder -> upload records of every PC (see LoadPcLogs)

; The rclone connection named in Remote must exist. If it doesn't but the old SaveSync
; connection does, keep using that one (migration); otherwise warn and open the Cloud tab.
RemoteMissing := ""
if RegExMatch(Remote, "^([^:\\/]{2,}):", &rm) {
    names := RemoteNames()
    if (names != "" && !InStr("`n" names, "`n" rm[1] ":")) {
        if InStr("`n" names, "`nsavesync:") {
            Remote := "savesync:SaveSync"
            IniWrite(Remote, IniFile, "general", "remote")
        } else {
            RemoteMissing := rm[1]
        }
    }
}

; [folders]  name=local_path   (the name is also the subfolder in the cloud)
; The path may use tokens (%DOCUMENTS%\MyGame, %USERPROFILE%\...) so the same line works on PCs with a
; different user name. FolderRaw keeps what is written in config.ini; Folders has the real path on THIS PC.
Folders := Map()
Folders.CaseSense := "Off"      ; "Saves" and "saves" are the same folder (some clouds ignore capitals)
FolderRaw := Map()
FolderRaw.CaseSense := "Off"
foldersRaw := ""
try {
    foldersRaw := IniRead(IniFile, "folders")
}
for line in StrSplit(foldersRaw, "`n", "`r") {
    p := InStr(line, "=")
    if (p > 1) {
        fname := Trim(SubStr(line, 1, p - 1))
        raw := RTrim(Trim(SubStr(line, p + 1)), "\")
        FolderRaw[fname] := raw
        Folders[fname] := RTrim(ExpandPath(raw), "\")
    }
}
if (Folders.Count = 0) {
    MsgBox(T("no_folders"), "SyncDood", "Iconi")
    IniWrite("0", IniFile, "general", "configured")
    Reload()
}

if (RemoteMissing != "") {
    MsgBox(T("remote_missing", RemoteMissing), "SyncDood", "Iconx")
    SetTimer(() => ShowMain(PG_CLOUD), -1500)
}

; the backups folder must not be inside (or contain) a synced folder
overlapFolder := BackupOverlap(BackupDir)
if (overlapFolder != "")
    SetTimer(() => MsgBox(T("o_backup_inside", BackupDir, overlapFolder), "SyncDood", "Iconx"), -2500)

; Upgrade from the old single "needFirstSync" flag to per-folder flags
oldNF := IniRead(IniFile, "general", "needFirstSync", "")
if (oldNF != "") {
    if (oldNF = "0") {
        for name in Folders
            MarkFirstDone(name)
    }
    try {
        IniDelete(IniFile, "general", "needFirstSync")
    }
}

; ---------------------------------------------------------------- State ------
Syncing         := false
Retries         := 0
Conflicts       := []     ; conflict notices: Map(ts, folder, rel, status = pending|kept|swapped, loser, dir, done)
ConfRows        := []     ; the ones shown in the Conflicts list
ConfLV          := ""
LastState       := "syncing"
LastTip         := ""
TipKind         := ""
ReopenTab       := 0
MainGui         := ""
HistLV          := ""
GamesLV         := ""
GTW := 156, GTH := 117      ; games grid: thumbnail size (design units)
GDW := 210, GDH := 158      ; inside a game: slot thumbnail size
TILE_BG := "10151F"         ; background of the thumbnails
VPW := 320, VPH := 240      ; versions window: preview box
GamesList       := []     ; each state: Map(folder, rel, game, gname, gkey, emu, slotTxt, slotKey, time, size, png, origin)
GamesGroups     := []     ; one per game: Map(key, name, emu, folder, items, shot, latest, img)
GamesView       := []     ; the groups currently shown in the grid (after search / sort)
FolderLV        := ""
History         := []     ; each item: Map(ts, folder, ev, rel, size)
WasRA           := (WatchProc != "" && ProcessExist(WatchProc) != 0)

EvMap := Map("up", T("ev_up"), "down", T("ev_down")
    , "del_here", T("ev_del_here"), "del_cloud", T("ev_del_cloud")
    , "conflict", T("ev_conflict"), "fail", T("ev_fail"), "info", T("ev_info"), "restore", T("ev_restore"))

; ---- window / theme state (the window itself is built in BuildMain)
SW := 200, CX := 228, CW0 := 724, W0 := 980, H0 := 680          ; sidebar width, content x / width, design size
PG_STATUS := 1, PG_HIST := 2, PG_CONF := 3, PG_GAMES := 4, PG_FOLDERS := 5, PG_CLOUD := 6, PG_OPT := 7, PG_ABOUT := 8
TH := Map(), UI := Map(), Hov := Map(), FS := Map(), OptC := Map()
Nav := [], PgCtrls := [], HistKeys := []
HovCur := 0, HoverHooked := false, MainBuilt := false, CurPage := 1
DarkNow := false, BannerCol := "2154A3", IconFont := "", HistFilterName := ""
SyncTotal := 0, SyncIdx := 0, SyncName := ""
NextCheck := 0, SyncWaiting := false
FState := Map()       ; per folder: Map(st = wait|pending|syncing|ok|conflict|error, when, msg)
for name in Folders
    FState[name] := Map("st", IsFirstDone(name) ? "wait" : "pending", "when", "", "msg", "")

LoadHistory()
LoadConflicts()

FirstPath := ""
for name, path in Folders {
    FirstPath := path
    break
}

; ------------------------------------------------------------ Menu / tray ---
A_TrayMenu.Delete()
A_TrayMenu.Add(T("menu_open"), MenuOpen)
A_TrayMenu.Default := T("menu_open")
A_TrayMenu.Add(T("menu_sync"), MenuSyncNow)
PauseMenu := Menu()
PauseMenu.Add(T("pause_1h"), (*) => PauseFor(60))
PauseMenu.Add(T("pause_4h"), (*) => PauseFor(240))
PauseMenu.Add(T("pause_forever"), (*) => SetPause("forever"))
A_TrayMenu.Add(T("menu_pause"), PauseMenu)
A_TrayMenu.Add(T("menu_resume"), ResumeNow)
A_TrayMenu.Add()
A_TrayMenu.Add(T("menu_open_saves"), MenuOpenFolder)
A_TrayMenu.Add(T("menu_open_backups"), MenuOpenBackup)
A_TrayMenu.Add(T("menu_open_log"), MenuOpenLog)
A_TrayMenu.Add()
A_TrayMenu.Add(T("menu_updates"), MenuUpdates)
A_TrayMenu.Add(T("menu_about"), MenuAbout)
A_TrayMenu.Add(T("menu_patreon"), MenuPatreon)
A_TrayMenu.Add(T("menu_github"), MenuGithub)
A_TrayMenu.Add()
A_TrayMenu.Add(T("menu_startup"), MenuStartup)
A_TrayMenu.Add(T("menu_exit"), MenuExit)
if FileExist(StartupLink)
    A_TrayMenu.Check(T("menu_startup"))

SetState("syncing", T("tip_starting"))
if IsPaused() {
    if (PauseUntil != "forever")
        SetTimer(PauseExpired, -Max(1000, DateDiff(PauseUntil, A_Now, "Seconds") * 1000))
}
if CapActive()
    SetTimer(CapExpired, -Max(1000, DateDiff(CapUntil, A_Now, "Seconds") * 1000))
UpdatePauseMenu()

; ------------------------------------------------------------- Triggers -----
SetTimer(StartupSync, AnyPending() ? -3000 : -15000)   ; after launch (network should be up)
SetTimer(PeriodicSync, IntervalMin * 60000)            ; every N minutes
NextCheck := DateAdd(A_Now, IntervalMin, "Minutes")
OnMessage(0x1A, OnSettingChange)                       ; WM_SETTINGCHANGE (Windows light/dark switch)
OnMessage(0x2E0, OnDpiChanged)                         ; WM_DPICHANGED (window moved to a monitor with another scale)
if (WatchProc != "")
    SetTimer(WatchRA, 30000)                           ; detects when you close the emulator
if CheckUpd
    SetTimer(AutoUpdateCheck, -25000)                  ; silent, at most once a day
OnMessage(0x218, OnPower)                              ; WM_POWERBROADCAST (sleep/resume)

; Re-open the window after a restart caused by a settings change
reopen := Integer(IniRead(IniFile, "general", "reopenUI", "0"))
if (reopen > 0) {
    try {
        IniDelete(IniFile, "general", "reopenUI")
    }
    ReopenTab := reopen
    SetTimer(ReopenUI, -400)
}

ReopenUI() {
    ShowMain(ReopenTab)
}

; ============================================================================
;  Language
; ============================================================================
; Windows language -> "es" for Spanish, "en" for everything else.
; Can be forced from Options (language=auto|en|es in config.ini).
DetectLang() {
    pref := StrLower(Trim(IniRead(IniFile, "general", "language", "auto")))
    if (pref = "es" || pref = "en")
        return pref
    primary := Integer("0x" SubStr(A_Language, -2))   ; low byte = primary language id
    return (primary = 0x0A) ? "es" : "en"
}

; T("key", args...)  ->  text in the current language ({1}, {2}... are the args)
T(key, args*) {
    txt := key
    if (L10n[Lang].Has(key))
        txt := L10n[Lang][key]
    else if (L10n["en"].Has(key))
        txt := L10n["en"][key]
    return args.Length ? Format(txt, args*) : txt
}

; ============================================================================
;  Texts  (English / Español)
; ============================================================================
BuildStrings() {
    en := Map(
        "err_no_rclone", "rclone was not found.`n`nRun Install.bat (it downloads it for you) or put rclone.exe next to this script."
        , "no_folders", "No folders are configured. The setup wizard will open."
        , "bundle_fail", "Could not prepare SyncDood's internal files:`n{1}"
        , "menu_open", "Open SyncDood"
        , "menu_sync", "Sync now"
        , "menu_open_saves", "Open saves folder"
        , "menu_open_backups", "Open backups folder"
        , "menu_open_log", "Open log"
        , "menu_updates", "Check for updates"
        , "menu_about", "About / Credits"
        , "menu_patreon", "Support on Patreon ☕"
        , "menu_github", "Project on GitHub"
        , "menu_startup", "Run at startup"
        , "menu_exit", "Exit"
        , "tip_starting", "Starting…"
        , "tip_syncing", "Syncing ({1})…"
        , "tip_fail_retry", "Failed: {1}- retrying in 45 s"
        , "tip_fail", "Failed: {1}- check sync.log"
        , "tip_conflict", "{1} conflict(s) to review. Nothing is lost: the other copy was saved"
        , "tip_conflict_seen", "Conflicts reviewed"
        , "tip_ok", "Synced {1}  (↑{2} ↓{3})"
        , "reason_start", "startup"
        , "reason_periodic", "periodic"
        , "reason_retry", "retry"
        , "reason_resume", "resumed from sleep"
        , "reason_emu", "emulator closed"
        , "reason_manual", "manual"
        , "reason_first", "first sync"
        , "fail_exec", "could not run rclone"
        , "fail_repair", "needs 'First sync / repair'"
        , "fail_code", "code {1}"
        , "ev_up", "↑ Uploaded"
        , "ev_down", "↓ Downloaded"
        , "ev_del_here", "✕ Deleted here (propagated)"
        , "ev_del_cloud", "✕ Deleted from the cloud"
        , "ev_conflict", "⚠ Conflict (loser backed up)"
        , "ev_fail", "✖ Failed"
        , "ev_info", "● Info"
        , "hist_first_done", "First sync completed"
        , "hist_fail_log", "{1} - see sync.log"
        , "wiz_title", "SyncDood - Initial setup"
        , "wiz_welcome", "Welcome to SyncDood.`n`nI'll ask you for:`n   1. Your SAVES folder`n   2. Your STATES folder`n   3. Your cloud`n`nWhen picking folders you can type or paste the path in the address bar.`n`nDo the same on every PC you want to keep in sync."
        , "wiz_same", "The saves folder and the states folder can't be the same."
        , "wiz_more", "Do you want to add another folder to sync?`n(for example, another emulator's)"
        , "wiz_done", "Done. SyncDood is in the system tray (next to the clock) and will start syncing.`n`nDouble-click the icon to open it."
        , "pick_saves", "Select your SAVES folder (game saves)"
        , "pick_states", "Select your STATES folder (save states)"
        , "pick_add", "Select the folder you want to add"
        , "pick_change", "Select the new folder for '{1}'"
        , "pick_required", "That folder is required to continue.`nOpen SyncDood again whenever you want to set it up."
        , "f_nameprompt", "Name of this folder in the cloud.`nIt must be the SAME on all your PCs."
        , "cd_title", "SyncDood - Choose your cloud"
        , "cd_intro", "Where do you want to keep your saves? Use the SAME cloud on all your PCs.`n★ = the easiest ones."
        , "cd_continue", "Continue"
        , "cd_cancel", "Cancel"
        , "cd_missing", "Missing: {1}"
        , "cd_browse", "Browse…"
        , "cd_browse_title", "Choose a folder inside your cloud app"
        , "cloud_fail", "Could not connect to the cloud.`n`n{1}`n`nTry again?"
        , "cloud_connect_msg", "Your browser will open so you can authorize access to your cloud.`nAccept and come back here."
        , "cloud_other_msg", "The rclone wizard will open.`n`nCreate a remote named:  {1}`n(pick the cloud type you want and leave the rest as default)."
        , "oauth_info", "You don't need to copy anything: your browser opens, you sign in, done."
        , "pr_onedrive_tag", "5 GB free"
        , "pr_onedrive_info", "You don't need to copy anything: your browser opens, you sign in, done.`n`nIt comes with Windows, so you probably already have an account. With work or school accounts you may see 'admin approval required': your organization blocks outside apps, so use another cloud."
        , "pr_dropbox_tag", "2 GB free"
        , "pr_pcloud_tag", "5 GB free, up to 10 with tasks"
        , "pr_pcloud_info", "You don't need to copy anything: your browser opens, you sign in, done.`n`nYou start with about 5 GB; the rest is unlocked by completing tasks or inviting people."
        , "pr_box_tag", "10 GB free"
        , "pr_box_info", "You don't need to copy anything: your browser opens, you sign in, done.`n`nOn the free plan each file can be up to 250 MB (plenty for saves and states)."
        , "pr_folder_name", "Your cloud app's folder"
        , "pr_folder_tag", "MEGA 20 GB, Google Drive 15 GB…"
        , "pr_folder_info", "If you already have your cloud's desktop app installed (MEGA, Google Drive for desktop, iCloud, Filen, OneDrive, Dropbox…), pick a folder inside it. SyncDood keeps that folder up to date and the app uploads it to the internet.`n`nNo accounts or credentials. The folder must be available offline (not 'online only')."
        , "pr_folder_field", "Folder inside your cloud app (you can paste the path)"
        , "pr_filen_name", "Filen"
        , "pr_filen_tag", "10 GB free, encrypted (advanced)"
        , "pr_filen_info", "Direct connection to Filen, no app needed. Requires rclone 1.73 or newer.`n`nBesides your email and password, rclone needs an API key. You get it once with the Filen CLI (a small download): log in and run the export-api-key command. After that the CLI is no longer needed.`n`nIf you change your Filen password, repeat this."
        , "pr_filen_link", '<a href="https://docs.cli.filen.io/">Filen CLI (to get your API key)</a>'
        , "pr_filen_email", "Filen account email"
        , "pr_filen_pass", "Filen password"
        , "pr_filen_key", "API key (from the Filen CLI: export-api-key)"
        , "hint_filen", "Filen: check the email, the password and the API key (re-export it if you changed your password), and that rclone is version 1.73 or newer."
        , "pr_nas_name", "Network folder, NAS or your own server"
        , "pr_nas_tag", "no space limit"
        , "pr_nas_info", "Syncs with a folder on your network: a NAS, another PC or a server (a network path like \\MyNAS\saves or a drive like Z:\saves).`n`nNo accounts or keys: you only need to be able to open that folder in Windows. If the NAS is off, SyncDood retries on the next sync. Use the same shared folder on all your PCs."
        , "pr_nas_field", "Folder on your NAS or server (you can paste the path, e.g. \\MyNAS\saves)"
        , "pr_drive_name", "Google Drive direct (advanced)"
        , "pr_drive_tag", "15 GB free"
        , "pr_drive_info", "Google removed the simple access for apps like this, so connecting directly needs your own credentials.`n`nIt's much easier to install 'Google Drive for desktop' and use the 'Your cloud app's folder' option. Use this only if you already have your client ID and secret."
        , "pr_drive_link", '<a href="https://rclone.org/drive/#making-your-own-client-id">Guide to creating the Google credentials</a>'
        , "pr_drive_cid", "Client ID"
        , "pr_drive_cs", "Client secret"
        , "pr_b2_name", "Backblaze B2 (advanced)"
        , "pr_b2_tag", "10 GB free"
        , "pr_b2_info", "Storage for technical users. In your Backblaze account create a 'bucket' (the root folder) and an 'Application Key' with access to it; you get two codes to paste here.`n`nIf you don't know what this is, pick another cloud from the list."
        , "pr_b2_link", '<a href="https://secure.backblaze.com/app_keys.htm">Where to get these values (Backblaze)</a>'
        , "pr_b2_kid", "Key ID (keyID)"
        , "pr_b2_key", "Application key (applicationKey)"
        , "pr_b2_bucket", "Bucket name"
        , "pr_nextcloud_name", "Nextcloud / ownCloud (advanced)"
        , "pr_nextcloud_tag", "your own server"
        , "pr_nextcloud_info", "For people with their own Nextcloud server (or a compatible NAS). Use an app password: in Nextcloud, Settings → Security → 'Create new app password'."
        , "pr_nextcloud_url", "Server address (e.g. https://cloud.mydomain.com)"
        , "pr_nextcloud_user", "Username"
        , "pr_nextcloud_pass", "App password"
        , "pr_other_name", "Other (rclone manual wizard)"
        , "pr_other_tag", "dozens of clouds"
        , "pr_other_info", "rclone's text wizard will open; it supports dozens of services. You must create a remote named 'syncdood'. Remember the cloud must keep the files' modification date."
        , "hint_onedrive", "OneDrive: if the browser said admin approval is required, your organization blocks outside apps. Try another cloud."
        , "hint_drive", "Google Drive: check the client ID and secret, and that your Google app is published 'In production'. Easier: use 'Your cloud app's folder' with Google Drive for desktop."
        , "hint_b2", "Backblaze B2: check the keyID, the applicationKey and the exact bucket name."
        , "hint_nextcloud", "Nextcloud: check the server address, the username and the app password."
        , "hint_folder", "Check that the folder exists and that you can write to it."
        , "hint_nas", "Check that the NAS or server is on and connected to your network, that you can open the folder in Explorer and that you can write to it."
        , "hint_default", "Check your internet connection and authorize again in the browser."
        , "btn_sync_now", "Sync now"
        , "btn_details", "Details"
        , "btn_close", "Close"
        , "o_clean_old", "Clean old SaveSync"
        , "o_uninstall", "Uninstall SyncDood..."
        , "cl_none", "No SaveSync leftovers were found on this PC."
        , "cl_intro", "SaveSync leftovers found on this PC:`n`n{1}`nDelete them? Your cloud and your saves are not touched."
        , "cl_dir", "- Old settings folder: {1}"
        , "cl_link", "- Old run-at-startup shortcut"
        , "cl_remote", "- Old rclone connection 'savesync'"
        , "cl_inuse", "- (The 'savesync' connection is still used by SyncDood, so it is kept.)"
        , "cl_cache", "- Old sync records ({1} files)"
        , "cl_done", "SaveSync leftovers deleted. If you still have the old SaveSync.exe, delete it by hand."
        , "un_confirm", "SyncDood will be removed from this PC:`n`n- Run-at-startup shortcut`n- Settings, history and log (%LOCALAPPDATA%\SyncDood)`n- The rclone connection to your cloud (the credentials saved on this PC)`n- rclone's sync records for SyncDood`n- Any SaveSync leftovers`n`nNOT touched: your cloud (files and its SyncDood folder) and your saves and states folders.`n`nContinue?"
        , "un_backups", "Delete the local backups too?`n`n{1}`n`nThey hold files that were overwritten or lost a conflict.`nYes = delete them. No = keep them."
        , "un_program", "Also delete the program itself?`n`n{1}"
        , "un_done", "SyncDood was removed from this PC. Your cloud was not touched."
        , "det_title", "SyncDood - Details"
        , "det_none", "(No error lines found in the log.)"
        , "remote_missing", "The cloud connection '{1}' does not exist on this PC (it may have been lost when migrating from SaveSync, or rclone's settings were removed).`n`nIn the Cloud tab choose 'Change cloud' to set it up again."
        , "hist_relist", "Sync records were missing: running a first sync (merges, nothing is deleted)"
        , "g_purge", "Purge versions…"
        , "pv_ask", "Delete saved-state versions older than how many days?`n`nOnly old copies kept in the backups are removed (on this PC and in the cloud); your current states are not touched."
        , "pv_none", "There are no state versions older than {1} days."
        , "pv_confirm", "Delete {1} old state file(s) ({2}) from the local backups and {4} from the cloud, older than {3} days?`n`nThis can't be undone."
        , "pv_cloud_fail", "Could not read the cloud backups, so only this PC's old versions can be deleted.`n`nDelete only the local ones?"
        , "pv_done", "Deleted {1} old state file(s) on this PC and {2} in the cloud."
        , "g_rename", "Rename game…"
        , "g_lookup", "Find names"
        , "ln_none", "Nothing to look up: every game already has a name, or none comes from an emulator SyncDood can search (DuckStation, Dolphin). You can still use Rename game…."
        , "ln_done", "Found {1} of {2} names."
        , "ln_fail", "`n`nSome source could not be reached. Check your connection and try again."
        , "g_rename_ask", "Name to show for this game (ID: {1}).`n`nLeave it empty to go back to the ID."
        , "hist_filters", "Exclusion rules changed: re-listing this folder (merges, nothing is deleted)"
        , "o_pcname", "Name of this PC (shown as the origin of your saves)"
        , "o_backup_inside", "The backups folder can't be inside a synced folder (or contain one): its files would be synced too and the sync would fail.`n`nBackups: {1}`nSynced folder: {2}`n`nChoose another backups folder in Options."
        , "f_inside_backup", "That folder overlaps the backups folder ({1}). Pick another one, or change the backups folder in Options."
        , "f_reserved", "That name is used by SyncDood inside the cloud. Pick another one."
        , "g_sel_none", "Nothing selected: click a state in the list"
        , "g_sel", "Selected:  {1}  (slot {2})"
        , "g_this_pc", "This PC ({1})"
        , "v_col_origin", "Origin"
        , "un_program_dir", "Also delete SyncDood's program files?`n`n{1}`n`nOnly SyncDood's own files are removed (the program, icons, rclone.exe and the readme files). Anything else in that folder is left alone."
        , "tab_history", "History"
        , "tab_conflicts", "Conflicts"
        , "cf_help", "When the same file changes on two PCs before they sync, SyncDood keeps the newest one and saves the other copy. Nothing is lost: come here only when you want to compare them and choose."
        , "cf_none", "✓ No conflicts to review."
        , "cf_col_state", "Status"
        , "cf_pending", "⚠ To review"
        , "cf_kept", "Kept the one in use"
        , "cf_swapped", "Used the other one"
        , "cf_all", "Mark all as reviewed"
        , "cf_cur", "In use (your folder)"
        , "cf_oth", "Other version (saved copy)"
        , "cf_size", "Size: {1}"
        , "cf_date", "Date: {1}"
        , "cf_origin", "From: {1}"
        , "cf_newer", "● Newer"
        , "cf_older", "● Older"
        , "cf_missing", "The file is not there"
        , "cf_nofile", "Plain file: no preview"
        , "cf_keep", "Keep the one in use"
        , "cf_use", "Use the other one"
        , "cf_compare", "Compare screenshots"
        , "cf_pick", "Pick a conflict from the list to see both versions."
        , "cf_foot", "The other copy stays in your backups (days set in Options). Save-state copies are never deleted automatically."
        , "cf_confirm_use", "Use the other version of this file?`n`n{1}`n`nThe one in use now is saved in the backups first, and the other one will sync to your other PCs on the next sync."
        , "cf_confirm_all", "Mark {1} conflict(s) as reviewed and keep the versions in use?`n`nThe other copies stay in the backups."
        , "btn_cf_review", "Review"
        , "tab_folders", "Folders"
        , "tab_cloud", "Cloud"
        , "tab_options", "Options"
        , "tab_about", "About"
        , "tab_games", "Games"
        , "g_intro", "Your games with save states. Double-click a game to see its slots, older versions and restore one."
        , "g_refresh", "Refresh"
        , "g_versions", "Older versions / Restore…"
        , "g_col_game", "Game"
        , "g_col_slot", "Slot"
        , "g_col_date", "Saved"
        , "g_col_origin", "Origin"
        , "g_here", "This PC"
        , "g_other", "Another PC"
        , "g_unknown", "—"
        , "g_restored_origin", "Restored here"
        , "g_empty", "No states found in your folders."
        , "g_nomatch", "No games match your search."
        , "g_open", "Open"
        , "g_search", "Search game…"
        , "g_sort_az", "A–Z"
        , "g_sort_new", "Recent"
        , "gd_title", "States - {1}"
        , "gd_sub", "{1}  ·  folder “{2}”  ·  {3} state(s)"
        , "gd_slot", "Slot {1}"
        , "gd_info", "{1}  ·  {2}  ·  {3}  ·  Origin: {4}"
        , "g_nosel", "Select a game or state first."
        , "g_loading", "Loading…"
        , "slot_auto", "Auto"
        , "ev_restore", "Restored"
        , "v_title", "Versions - {1} (slot {2})"
        , "v_help", "These are copies SyncDood already keeps in its backups; nothing extra is stored. Pick one to see its screenshot and restore it. The current state is copied to the backups first, so you can undo."
        , "v_current", "Current"
        , "v_kind_day", "Overwritten by a sync ({1})"
        , "v_kind_conf", "Replaced / lost a conflict ({1})"
        , "v_kind_cloud", "Cloud backup ({1})"
        , "v_col_date", "Saved"
        , "v_col_kind", "Copy"
        , "v_col_size", "Size"
        , "v_restore", "Restore this version"
        , "v_cloud", "Include cloud backups"
        , "v_close", "Close"
        , "v_pick", "Select an older version (not the current one)."
        , "v_confirm", "Restore {1} (slot {2}) to the version saved on {3}?`n`nThe current state is copied to the backups first, and the restored one will sync to your other PCs."
        , "v_confirm_emu", "The emulator is open. Close it first, or it may overwrite the restored state."
        , "v_done", "Restored. It will sync to your other PCs on the next sync."
        , "v_fail", "Could not restore: {1}"
        , "v_cloud_fail", "Could not read the cloud backups. Check your connection."
        , "v_cloud_none", "There are no additional versions in the cloud."
        , "v_nopreview", "No screenshot for this version"
        , "v_compare", "Enlarge / Compare…"
        , "v_cmp_title", "Compare - {1} (slot {2})"
        , "v_cmp_cur", "Current  ·  {1}"
        , "v_cmp_ver", "Selected version  ·  {1}"
        , "v_cmp_only", "{1}"
        , "tab_status", "Status"
        , "f_excl", "Options and exclusions…"
        , "f_col_excl", "Exclusions"
        , "ex_rules", "{1} rules"
        , "ex_title", "Exclusions - {1}"
        , "ex_help", "Files and folders that match these rules are NOT synced: they are ignored on this PC and in the cloud, and nothing is deleted. One rule per line:`n   *.log  = files by name      shaders/  = a folder, wherever it is      /logs/  = a folder only at the top`nCapitals don't matter. What was already uploaded stays in the cloud (SyncDood just stops touching it)."
        , "ex_none", "No rules: everything is synced."
        , "ex_preview", "These rules exclude {1} file(s) on this PC ({2})."
        , "ex_add_file", "+ File…"
        , "ex_add_folder", "+ Folder…"
        , "ex_pick_file", "Choose the file to exclude"
        , "ex_pick_folder", "Choose the folder to exclude"
        , "ex_outside", "That item is not inside the synced folder."
        , "ex_save", "Save"
        , "st_waiting", "Waiting for files in {1} to finish being written…"
        , "st_title_ok", "Everything is up to date"
        , "st_title_syncing", "Syncing…"
        , "st_title_conflict", "Conflicts to review"
        , "st_title_error", "Could not sync"
        , "st_side_ok", "Up to date"
        , "st_side_syncing", "Syncing…"
        , "st_side_conflict", "Conflict"
        , "st_side_error", "Error"
        , "st_recent", "Recent activity"
        , "st_all_history", "See full history →"
        , "st_none", "No activity yet."
        , "st_folder_wait", "Waiting for the first check"
        , "st_folder_ok", "Up to date · {1}"
        , "st_folder_syncing", "Syncing…"
        , "st_folder_error", "Error: {1}"
        , "st_folder_conflict", "Conflict · {1}"
        , "st_folder_pending", "First sync pending"
        , "st_more_folders", "+{1} more folders (see Folders)"
        , "st_progress", "Syncing {1} ({2} of {3})…"
        , "st_next", "Next automatic check: {1}"
        , "st_paused", "Automatic sync is paused while {1} is open (it syncs when you close it)."
        , "pv_title", "First sync"
        , "pv_wait", "Checking {1}…"
        , "pv_body", "First sync of '{1}'.`n`nThis PC ({2}): {3} files, {4}`nCloud: {5} files, {6}`n`nWhat will happen: {7}`n`nContinue?"
        , "o_export", "Export settings…"
        , "o_import", "Import settings…"
        , "cfg_export_title", "Save SyncDood settings"
        , "cfg_import_title", "Choose the SyncDood settings file"
        , "cfg_exported", "Settings saved to:`n{1}`n`nIt has your folders (with portable paths), exclusions and options. It does not include cloud passwords or tokens: connect the cloud on the other PC from the Cloud tab."
        , "cfg_fail", "Could not save the file: {1}"
        , "cfg_bad", "That file is not a SyncDood settings file."
        , "cfg_replace", "replaces the one here"
        , "cfg_import_ask", "Import {1} folders?{2}`n`nSyncDood restarts and each folder does a first sync (with preview) before syncing normally."
        , "sp_btn", "Space by folder…"
        , "sp_title", "Space by folder"
        , "sp_help", "How much each folder takes on this PC, in the cloud and in the backups."
        , "sp_pc", "This PC"
        , "sp_cloud", "Cloud"
        , "sp_bk_cloud", "Cloud backups"
        , "sp_bk_pc", "Local backups"
        , "sp_total", "Total"
        , "sp_close", "Close"
        , "menu_pause", "Pause sync"
        , "menu_resume", "Resume sync"
        , "pause_1h", "For 1 hour"
        , "pause_4h", "For 4 hours"
        , "pause_forever", "Until I resume it"
        , "btn_pause", "Pause"
        , "btn_resume", "Resume"
        , "st_paused_manual", "Sync is paused. Press Resume when you want it to continue."
        , "st_paused_until", "Sync is paused until {1}."
        , "tip_paused", "Sync paused"
        , "reason_resume_pause", "resuming after pause"
        , "reason_resume_cap", "cloud limit lifted"
        , "fail_cap", "The cloud daily limit was reached"
        , "tip_cap", "Cloud limit reached. SyncDood will retry on its own at {1}."
        , "hist_cap", "Cloud limit reached; retrying at {1}"
        , "st_cap", "The cloud reached its daily limit. SyncDood will retry on its own at {1}."
        , "cap_still", "The cloud's daily limit was reached and it should be lifted at {1}.`n`nSync now anyway?"
        , "st_cloud", "Cloud: {1}"
        , "c_app_of", "Folder of {1}"
        , "c_space_btn", "Check space"
        , "c_space_wait", "Checking space…"
        , "c_space_used", "SyncDood uses {1} in the cloud ({2} files)."
        , "c_space_acct", "Account: {1} used of {2} ({3} free)."
        , "c_space_none", "This cloud does not report the free space of the account."
        , "c_space_fail", "Could not read the cloud size. Check the connection."
        , "st_sync_folder", "Sync"
        , "f_sync_one", "Sync selected folder"
        , "seg_auto", "Auto"
        , "o_theme", "Appearance"
        , "th_light", "Light"
        , "th_dark", "Dark"
        , "o_settle", "Wait for files being written (seconds, 0 = off)"
        , "o_parallel", "Parallel uploads/downloads (Auto = best for your cloud)"
        , "o_maxdel", "Stop if a sync would delete more than this % (0 = no limit)"
        , "o_cloudprune", "Also clean old backups and conflicts in the cloud (same days; states stay)"
        , "fail_blocked", "stopped: it would delete too many files"
        , "tip_blocked", "Sync stopped in {1}: it would delete too many files. Use Sync now to review it"
        , "hist_blocked", "Stopped by the delete protection (nothing was deleted)"
        , "blk_head", "The sync of the folder «{1}» was stopped because it would delete more than {2}% of its files."
        , "blk_count", "Deletions: {1} of {2} items."
        , "blk_local", "Would be deleted ON THIS PC: {1}"
        , "blk_cloud", "Would be deleted IN THE CLOUD: {1}"
        , "blk_sample", "Examples:"
        , "blk_question", "Continue anyway? (Deleted files still go to the backups folder.)"
        , "seg_manual", "Manual"
        , "hist_folder", "Folder:"
        , "hist_all", "All folders"
        , "col_date", "Date"
        , "col_folder", "Folder"
        , "col_event", "Event"
        , "col_file", "File"
        , "col_size", "Size"
        , "fmt_date", "MM/dd HH:mm"
        , "f_intro", "Folders SyncDood keeps in sync. The name is the subfolder used in the cloud and must be the same on all your PCs; the location can be different on each PC (and can use %DOCUMENTS% or %USERPROFILE% so it works with any user name)."
        , "f_add", "Add folder…"
        , "f_change", "Change path…"
        , "f_remove", "Remove"
        , "f_open", "Open"
        , "f_repair", "First sync / repair…"
        , "f_col_name", "Name (in the cloud)"
        , "f_col_path", "Folder on this PC"
        , "f_dup_name", "There is already a folder with that name."
        , "f_dup_path", "That folder is already being synced."
        , "f_nosel", "Select a folder in the list first."
        , "f_remove_confirm", "Stop syncing '{1}'?`n`nNothing is deleted: the files stay on this PC and in the cloud."
        , "f_remove_last", "You need to keep at least one folder."
        , "f_change_confirm", "Change the folder of '{1}' to:`n{2}`n`nSyncDood will do a first sync for it (merging this folder with the cloud). Nothing is lost: anything overwritten is backed up.`n`nContinue?"
        , "f_busy", "A sync is in progress. Try again when it finishes."
        , "f_portable_ask", "This folder is inside your Windows user folder.`n`nSave it as:`n{1}`n`nso it also works on PCs with a different user name?"
        , "f_cloud_add", "Add from cloud…"
        , "f_portable_tag", "portable"
        , "f_search", "Search:"
        , "f_count", "{1} folders"
        , "f_count_f", "{1} of {2} folders"
        , "f_col_status", "Status"
        , "st_summary", "{1} folders · {2} up to date · {3} with problems  —  see all"
        , "hist_more", "More ({1}) ▾"
        , "cf_looking", "Checking the cloud…"
        , "cf_fail", "Could not read the cloud. Check the connection in the Cloud tab and try again."
        , "cf_none", "There are no folders in the cloud that are missing on this PC."
        , "cf_title", "Add from the cloud"
        , "cf_help", "These folders already exist in your cloud but are not set up on this PC. Pick one and then choose where it goes on this PC."
        , "cf_next", "Continue…"
        , "pick_cloud", "Where should '{1}' go on this PC?"
        , "fd_title_add", "Add folder"
        , "fd_title_cloud", "Add folder from the cloud"
        , "fd_title_edit", "Folder options - {1}"
        , "fd_name", "Name in the cloud"
        , "fd_path", "Folder on this PC"
        , "fd_browse", "Browse…"
        , "fd_portable", "Save the path as {1} (it also works on PCs with another user name)"
        , "fd_tree", "What to sync"
        , "fd_tree_help", "Only what is CHECKED will be synced: it is uploaded to your cloud and copied to your other PCs. Uncheck what you don't want to sync (nothing is deleted)."
        , "fd_choose", "I only want to sync PART of this folder (choose files or folders)"
        , "fd_simple", "Everything inside this folder ({2} items) will be synced to your cloud and your other PCs:`n{1}"
        , "fd_simple_empty", "This folder is empty or doesn't exist yet. Whatever is inside will be synced to your cloud and your other PCs:`n{1}"
        , "fd_tip_sub", "Tip: if you only need one subfolder, cancel and pick that subfolder directly."
        , "fd_cloud_info", "In the cloud, '{1}' contains: {2}`nThese items will be placed directly INSIDE the folder chosen above."
        , "fd_cloud_empty", "The cloud folder '{1}' looks empty (or it couldn't be read)."
        , "fd_cloud_warn", "⚠ The cloud folder '{1}' already has a folder called '{2}' inside. With this path you would end up with '{2}\{2}'. Did you mean the folder above: {3}?"
        , "fd_cloud_fix", "{1}`n`nThe cloud folder '{2}' already contains a folder called '{3}', so you would end up with:`n{1}\{3}`n`nYes = use the folder above ({4})`nNo = keep this path anyway`nCancel = go back"
        , "fd_root_confirm", "That is a very general folder:`n{1}`n`nSyncDood would sync everything inside it unless you uncheck it. Usually you want the game's own folder. Continue anyway?"
        , "fd_only", "Only sync what is checked (anything NEW that appears later is not synced)"
        , "fd_only_help", "Use it when you want just a few files or folders out of a big folder. Without it, new files and folders are synced automatically."
        , "fd_count_only", "ONLY the {1} checked item(s) will be synced. Anything new that appears later will NOT be synced."
        , "fd_adv_off", "Extra rules (not used in this mode)"
        , "fd_only_trunc", "This folder has too many items to list them all, and 'only sync what is checked' needs the full list.`n`nPick a subfolder instead, or turn that option off."
        , "ex_only", "Only checked"
        , "fd_checkall", "Check all"
        , "fd_uncheckall", "Uncheck all"
        , "fd_count", "{1} item(s) will be synced to the cloud  ·  {2} will NOT"
        , "fd_none", "Nothing is checked, so nothing would be synced. Check what you want to sync."
        , "fd_err_none", "Nothing is checked, so SyncDood would not sync anything.`n`nCheck at least the files or folders you want to sync."
        , "fd_tree_empty", "Nothing to show yet: the folder is empty or doesn't exist. You can still add rules below."
        , "fd_tree_trunc", "only the first {1} items are shown; use the rules below for the rest"
        , "fd_excluded", "{1} item(s) will NOT be synced"
        , "fd_all_synced", "Everything ({1} items) will be synced to the cloud"
        , "fd_adv", "Extra rules (optional)"
        , "fd_empty", "Also sync empty folders (keep the folder structure)"
        , "fd_empty_help", "Turn it on if the game or emulator needs its folders to exist even when they are empty. They are created on your other PCs too."
        , "fd_empty_b2", "Your cloud (Backblaze B2) can't store empty folders."
        , "fd_add", "Add folder"
        , "fd_err_name", "Type a name for the folder."
        , "fd_big_confirm", "This folder has thousands of files:`n{1}`n`nIs it really the one you want to sync? (For example, pick the game's own folder, not 'Documents'.)"
        , "fd_err_abs", "Choose a full folder path on this PC, like C:\Games\Saves."
        , "fd_create_ask", "That folder doesn't exist yet:`n{1}`n`nCreate it?"
        , "re_local", "If a file exists here and in the cloud, THIS PC's version wins."
        , "re_cloud", "If a file exists here and in the cloud, the CLOUD's version wins."
        , "re_newer", "If a file exists here and in the cloud, the NEWEST one wins."
        , "re_body", "This runs an initial sync that merges this PC with the cloud.`n`n{1}`n`nWhatever is missing on one side is copied to the other, and whatever loses is saved in the backups folder.`n`nContinue?"
        , "re_title", "SyncDood - First sync"
        , "c_current", "Current cloud"
        , "c_unknown", "Unknown"
        , "c_local", "Folder (cloud app, network or NAS)"
        , "c_target", "Destination: {1}"
        , "c_change", "Change cloud…"
        , "c_test", "Test connection"
        , "c_note", "Use the same cloud on all your PCs. When you change it, every folder does a first sync against the new one (they merge; nothing is deleted, anything overwritten is backed up)."
        , "c_confirm", "Change the cloud?`n`nEvery folder will do a first sync against the new cloud and merge with what is there. Nothing is deleted: anything overwritten is backed up.`n`nContinue?"
        , "c_test_ok", "Connection OK."
        , "c_test_fail", "Could not reach the cloud.`n`n{1}"
        , "o_language", "Language"
        , "lang_auto", "Automatic (Windows)"
        , "o_interval", "Check every (minutes)"
        , "o_watch", "Emulator process (sync when it closes; empty = off)"
        , "o_resume", "Wait after waking from sleep (seconds)"
        , "o_firstwins", "First sync: who wins when a file is on both sides"
        , "fw_newer", "The newest"
        , "fw_local", "This PC"
        , "fw_cloud", "The cloud"
        , "o_backupdir", "Backups folder"
        , "o_keepdays", "Keep backups and conflicts (days, 0 = forever)"
        , "o_startup", "Run at startup"
        , "o_checkupd", "Check for updates on startup"
        , "o_pause", "Don't sync automatically while the emulator is open (avoids conflicts)"
        , "o_dryrun", "Test mode (only writes to the log what it would do)"
        , "o_save", "Save and apply"
        , "o_open_ini", "Open config.ini"
        , "o_open_log", "Open log"
        , "o_open_backups", "Open backups"
        , "o_invalid", "Check the numbers: whole numbers only, the interval must be at least 1 and parallel transfers between 1 and 32, and the delete limit between 0 and 100."
        , "ab_version", "Version {1}"
        , "ab_desc", "Keeps your saves and states identical on all your PCs through your cloud, with a tray icon.`n`nBlue icon = syncing, green = up to date, red = error, amber blinking = conflict."
        , "ab_made", "Made by {1} with Claude AI. 🤖✨"
        , "ab_patreon", "☕ Support me on Patreon"
        , "ab_github", "🐙 Source code and downloads on GitHub"
        , "ab_libs", "Uses <a href=`"https://rclone.org`">rclone</a> (MIT) and <a href=`"https://www.autohotkey.com`">AutoHotkey v2</a> (GPLv2)."
        , "ab_check", "Check for updates"
        , "ab_libs_plain", "Uses rclone (MIT) and AutoHotkey v2 (GPLv2)."
        , "upd_new", "A new version is available: {1} (you have {2}).`n`nOpen the download page?"
        , "upd_none", "You are up to date (version {1})."
        , "upd_noreleases", "No published releases found yet."
        , "upd_error", "Could not check for updates. Check your internet connection."
    )

    es := Map(
        "err_no_rclone", "No se encontró rclone.`n`nEjecuta Install.bat (lo descarga solo) o pon rclone.exe junto a este script."
        , "no_folders", "No hay carpetas configuradas. Se abrirá el asistente."
        , "bundle_fail", "No pude preparar los archivos internos de SyncDood:`n{1}"
        , "menu_open", "Abrir SyncDood"
        , "menu_sync", "Sincronizar ahora"
        , "menu_open_saves", "Abrir carpeta de saves"
        , "menu_open_backups", "Abrir carpeta de respaldos"
        , "menu_open_log", "Abrir log"
        , "menu_updates", "Buscar actualizaciones"
        , "menu_about", "Acerca de / Créditos"
        , "menu_patreon", "Apoyar en Patreon ☕"
        , "menu_github", "Proyecto en GitHub"
        , "menu_startup", "Iniciar con Windows"
        , "menu_exit", "Salir"
        , "tip_starting", "Iniciando…"
        , "tip_syncing", "Sincronizando ({1})…"
        , "tip_fail_retry", "Falló: {1}- reintentando en 45 s"
        , "tip_fail", "Falló: {1}- revisa sync.log"
        , "tip_conflict", "{1} conflicto(s) por revisar. No se pierde nada: la otra copia quedó guardada"
        , "tip_conflict_seen", "Conflictos revisados"
        , "tip_ok", "Sincronizado {1}  (↑{2} ↓{3})"
        , "reason_start", "inicio"
        , "reason_periodic", "periódico"
        , "reason_retry", "reintento"
        , "reason_resume", "reanudó de suspensión"
        , "reason_emu", "el emulador cerró"
        , "reason_manual", "manual"
        , "reason_first", "primera sincronización"
        , "fail_exec", "no se pudo ejecutar rclone"
        , "fail_repair", "requiere 'Primera sincronización / reparar'"
        , "fail_code", "código {1}"
        , "ev_up", "↑ Subido"
        , "ev_down", "↓ Descargado"
        , "ev_del_here", "✕ Borrado aquí (propagado)"
        , "ev_del_cloud", "✕ Borrado desde la nube"
        , "ev_conflict", "⚠ Conflicto (perdedor respaldado)"
        , "ev_fail", "✖ Falló"
        , "ev_info", "● Info"
        , "hist_first_done", "Primera sincronización completada"
        , "hist_fail_log", "{1} - ver sync.log"
        , "wiz_title", "SyncDood - Configuración inicial"
        , "wiz_welcome", "Bienvenido a SyncDood.`n`nVoy a pedirte:`n   1. La carpeta de SAVES`n   2. La carpeta de STATES`n   3. Tu nube`n`nAl elegir carpetas puedes escribir o pegar la ruta en la barra de direcciones.`n`nHaz lo mismo en cada PC que quieras mantener sincronizada."
        , "wiz_same", "La carpeta de saves y la de states no pueden ser la misma."
        , "wiz_more", "¿Quieres agregar otra carpeta a sincronizar?`n(por ejemplo, la de otro emulador)"
        , "wiz_done", "Listo. SyncDood quedó en la bandeja del sistema (junto al reloj) y empezará a sincronizar.`n`nDoble clic al ícono para abrirlo."
        , "pick_saves", "Selecciona la carpeta de SAVES (partidas guardadas)"
        , "pick_states", "Selecciona la carpeta de STATES (estados guardados)"
        , "pick_add", "Selecciona la carpeta que quieres agregar"
        , "pick_change", "Selecciona la nueva carpeta para '{1}'"
        , "pick_required", "Se necesita esa carpeta para continuar.`nVuelve a abrir SyncDood cuando quieras configurarlo."
        , "f_nameprompt", "Nombre de esta carpeta en la nube.`nDebe ser el MISMO en todas tus PCs."
        , "cd_title", "SyncDood - Elige tu nube"
        , "cd_intro", "¿Dónde quieres guardar tus partidas? Usa la MISMA nube en todas tus PCs.`n★ = las más fáciles."
        , "cd_continue", "Continuar"
        , "cd_cancel", "Cancelar"
        , "cd_missing", "Falta este dato: {1}"
        , "cd_browse", "Examinar…"
        , "cd_browse_title", "Elige una carpeta dentro de la app de tu nube"
        , "cloud_fail", "No pude conectar con la nube.`n`n{1}`n`n¿Intentar de nuevo?"
        , "cloud_connect_msg", "Se abrirá el navegador para que autorices el acceso a tu nube.`nAcepta y regresa aquí."
        , "cloud_other_msg", "Se abrirá el asistente de rclone.`n`nCrea un remote llamado:  {1}`n(elige el tipo de nube que quieras y deja lo demás por defecto)."
        , "oauth_info", "No necesitas copiar ningún dato: se abre el navegador, inicias sesión y listo."
        , "pr_onedrive_tag", "5 GB gratis"
        , "pr_onedrive_info", "No necesitas copiar ningún dato: se abre el navegador, inicias sesión y listo.`n`nViene con Windows, así que probablemente ya tienes cuenta. Con cuentas de trabajo o escuela puede salir «se necesita aprobación del administrador»: tu organización lo bloquea, usa otra nube."
        , "pr_dropbox_tag", "2 GB gratis"
        , "pr_pcloud_tag", "5 GB gratis, hasta 10 con tareas"
        , "pr_pcloud_info", "No necesitas copiar ningún dato: se abre el navegador, inicias sesión y listo.`n`nEmpiezas con unos 5 GB; el resto se desbloquea completando tareas o invitando gente."
        , "pr_box_tag", "10 GB gratis"
        , "pr_box_info", "No necesitas copiar ningún dato: se abre el navegador, inicias sesión y listo.`n`nEn el plan gratis cada archivo puede pesar hasta 250 MB (de sobra para saves y states)."
        , "pr_folder_name", "Carpeta de tu app de nube"
        , "pr_folder_tag", "MEGA 20 GB, Google Drive 15 GB…"
        , "pr_folder_info", "Si ya tienes la app de escritorio de tu nube instalada (MEGA, Google Drive para escritorio, iCloud, Filen, OneDrive, Dropbox…), elige una carpeta dentro de ella. SyncDood mantiene esa carpeta al día y la app la sube a internet.`n`nSin cuentas ni credenciales. La carpeta debe estar disponible sin conexión (no «solo en línea»)."
        , "pr_folder_field", "Carpeta dentro de tu app de nube (puedes pegar la ruta)"
        , "pr_filen_name", "Filen"
        , "pr_filen_tag", "10 GB gratis, cifrado (avanzado)"
        , "pr_filen_info", "Conexión directa a Filen, sin apps. Requiere rclone 1.73 o más nuevo.`n`nAdemás de tu correo y contraseña, rclone necesita una API key. La obtienes una sola vez con la CLI de Filen (una descarga pequeña): inicia sesión y ejecuta el comando export-api-key. Después ya no necesitas la CLI.`n`nSi cambias tu contraseña de Filen, repite este paso."
        , "pr_filen_link", '<a href="https://docs.cli.filen.io/">CLI de Filen (para obtener tu API key)</a>'
        , "pr_filen_email", "Correo de tu cuenta de Filen"
        , "pr_filen_pass", "Contraseña de Filen"
        , "pr_filen_key", "API key (de la CLI de Filen: export-api-key)"
        , "hint_filen", "Filen: revisa el correo, la contraseña y la API key (expórtala de nuevo si cambiaste la contraseña), y que rclone sea versión 1.73 o más nueva."
        , "pr_nas_name", "Carpeta de red, NAS o servidor propio"
        , "pr_nas_tag", "sin límite de espacio"
        , "pr_nas_info", "Sincroniza con una carpeta de tu red: un NAS, otro PC o un servidor (una ruta de red como \\MiNAS\saves o una unidad como Z:\saves).`n`nSin cuentas ni claves: solo necesitas poder abrir esa carpeta en Windows. Si el NAS está apagado, SyncDood reintenta en la siguiente sincronización. Usa la misma carpeta compartida en todas tus PCs."
        , "pr_nas_field", "Carpeta en tu NAS o servidor (puedes pegar la ruta, ej. \\MiNAS\saves)"
        , "pr_drive_name", "Google Drive directo (avanzado)"
        , "pr_drive_tag", "15 GB gratis"
        , "pr_drive_info", "Google retiró el acceso simple para apps como esta, así que conectar directo exige crear tus propias credenciales.`n`nEs mucho más fácil instalar «Google Drive para escritorio» y usar la opción «Carpeta de tu app de nube». Usa esta solo si ya tienes tu ID y secreto de cliente."
        , "pr_drive_link", '<a href="https://rclone.org/drive/#making-your-own-client-id">Guía para crear las credenciales de Google</a>'
        , "pr_drive_cid", "ID de cliente"
        , "pr_drive_cs", "Secreto de cliente"
        , "pr_b2_name", "Backblaze B2 (avanzado)"
        , "pr_b2_tag", "10 GB gratis"
        , "pr_b2_info", "Almacenamiento para usuarios técnicos. En tu cuenta de Backblaze crea un «bucket» (la carpeta raíz) y una «Application Key» con acceso a él; te da dos códigos que se copian aquí.`n`nSi no sabes qué es esto, elige otra nube de la lista."
        , "pr_b2_link", '<a href="https://secure.backblaze.com/app_keys.htm">Dónde obtener estos datos (Backblaze)</a>'
        , "pr_b2_kid", "ID de la clave (keyID)"
        , "pr_b2_key", "Clave de aplicación (applicationKey)"
        , "pr_b2_bucket", "Nombre del bucket"
        , "pr_nextcloud_name", "Nextcloud / ownCloud (avanzado)"
        , "pr_nextcloud_tag", "tu propio servidor"
        , "pr_nextcloud_info", "Para quien tiene su propio servidor Nextcloud (o un NAS compatible). Usa una contraseña de aplicación: en Nextcloud, Ajustes → Seguridad → «Crear nueva contraseña de aplicación»."
        , "pr_nextcloud_url", "Dirección del servidor (ej. https://nube.midominio.com)"
        , "pr_nextcloud_user", "Usuario"
        , "pr_nextcloud_pass", "Contraseña de aplicación"
        , "pr_other_name", "Otra (asistente manual de rclone)"
        , "pr_other_tag", "decenas de nubes"
        , "pr_other_info", "Se abrirá el asistente de texto de rclone, que soporta decenas de servicios. Debes crear un remote llamado «syncdood». Recuerda que la nube debe guardar la fecha de modificación de los archivos."
        , "hint_onedrive", "OneDrive: si el navegador dijo que se necesita aprobación del administrador, tu organización bloquea apps externas. Prueba otra nube."
        , "hint_drive", "Google Drive: revisa el ID y el secreto de cliente, y que tu app de Google esté publicada «En producción». Más fácil: usa «Carpeta de tu app de nube» con Google Drive para escritorio."
        , "hint_b2", "Backblaze B2: revisa el keyID, la applicationKey y el nombre exacto del bucket."
        , "hint_nextcloud", "Nextcloud: revisa la dirección del servidor, el usuario y la contraseña de aplicación."
        , "hint_folder", "Revisa que la carpeta exista y que tengas permiso para escribir en ella."
        , "hint_nas", "Revisa que el NAS o servidor esté encendido y conectado a tu red, que puedas abrir la carpeta desde el Explorador y que tengas permiso para escribir en ella."
        , "hint_default", "Revisa tu conexión a internet y vuelve a autorizar en el navegador."
        , "btn_sync_now", "Sincronizar ahora"
        , "btn_details", "Detalles"
        , "btn_close", "Cerrar"
        , "o_clean_old", "Limpiar SaveSync viejo"
        , "o_uninstall", "Desinstalar SyncDood..."
        , "cl_none", "No se encontraron restos de SaveSync en este PC."
        , "cl_intro", "Restos de SaveSync encontrados en este PC:`n`n{1}`n¿Borrarlos? Tu nube y tus partidas no se tocan."
        , "cl_dir", "- Carpeta de ajustes vieja: {1}"
        , "cl_link", "- Acceso directo viejo de inicio con Windows"
        , "cl_remote", "- Conexión vieja de rclone 'savesync'"
        , "cl_inuse", "- (La conexión 'savesync' aún la usa SyncDood, así que se conserva.)"
        , "cl_cache", "- Registros viejos de sincronización ({1} archivos)"
        , "cl_done", "Restos de SaveSync borrados. Si aún tienes el SaveSync.exe viejo, bórralo a mano."
        , "un_confirm", "Se quitará SyncDood de este PC:`n`n- Acceso directo de inicio con Windows`n- Ajustes, historial y log (%LOCALAPPDATA%\SyncDood)`n- La conexión de rclone a tu nube (las credenciales guardadas en este PC)`n- Los registros de sincronización de rclone para SyncDood`n- Cualquier resto de SaveSync`n`nNO se toca: tu nube (archivos y su carpeta SyncDood) ni tus carpetas de saves y states.`n`n¿Continuar?"
        , "un_backups", "¿Borrar también los respaldos locales?`n`n{1}`n`nGuardan archivos que se sobrescribieron o perdieron un conflicto.`nSí = borrarlos. No = conservarlos."
        , "un_program", "¿Borrar también el programa?`n`n{1}"
        , "un_done", "SyncDood se quitó de este PC. Tu nube no se tocó."
        , "det_title", "SyncDood - Detalles"
        , "det_none", "(No hay líneas de error en el log.)"
        , "remote_missing", "La conexión de nube '{1}' no existe en este PC (puede haberse perdido al migrar desde SaveSync, o se borró la configuración de rclone).`n`nEn la pestaña Nube elige 'Cambiar nube' para configurarla de nuevo."
        , "hist_relist", "Faltaban los registros de sincronización: se hace una primera sincronización (combina, no se borra nada)"
        , "g_purge", "Depurar versiones…"
        , "pv_ask", "¿Borrar las versiones de partidas con más de cuántos días?`n`nSolo se quitan copias viejas de los respaldos (en esta PC y en la nube); tus states actuales no se tocan."
        , "pv_none", "No hay versiones de partidas con más de {1} días."
        , "pv_confirm", "¿Borrar {1} archivo(s) de states viejos ({2}) de los respaldos locales y {4} de la nube, con más de {3} días?`n`nNo se puede deshacer."
        , "pv_cloud_fail", "No se pudieron leer los respaldos de la nube, así que solo se pueden borrar las versiones viejas de esta PC.`n`n¿Borrar solo las locales?"
        , "pv_done", "Se borraron {1} archivo(s) de states viejos en esta PC y {2} en la nube."
        , "g_rename", "Renombrar juego…"
        , "g_lookup", "Buscar nombres"
        , "ln_none", "Nada que buscar: todos los juegos ya tienen nombre, o ninguno viene de un emulador que SyncDood pueda buscar (DuckStation, Dolphin). Aún puedes usar Renombrar juego…."
        , "ln_done", "Se encontraron {1} de {2} nombres."
        , "ln_fail", "`n`nNo se pudo llegar a alguna fuente. Revisa tu conexión e inténtalo de nuevo."
        , "g_rename_ask", "Nombre que se mostrará para este juego (ID: {1}).`n`nDéjalo vacío para volver al ID."
        , "hist_filters", "Cambiaron las reglas de exclusión: se vuelve a listar esta carpeta (combina, no se borra nada)"
        , "o_pcname", "Nombre de esta PC (se muestra como origen de tus partidas)"
        , "o_backup_inside", "La carpeta de respaldos no puede estar dentro de una carpeta sincronizada (ni contener una): sus archivos también se sincronizarían y la sincronización fallaría.`n`nRespaldos: {1}`nCarpeta sincronizada: {2}`n`nElige otra carpeta de respaldos en Opciones."
        , "f_inside_backup", "Esa carpeta se cruza con la carpeta de respaldos ({1}). Elige otra, o cambia la carpeta de respaldos en Opciones."
        , "f_reserved", "SyncDood usa ese nombre dentro de la nube. Elige otro."
        , "g_sel_none", "Nada elegido: haz clic en un state de la lista"
        , "g_sel", "Elegido:  {1}  (slot {2})"
        , "g_this_pc", "Esta PC ({1})"
        , "v_col_origin", "Origen"
        , "un_program_dir", "¿Borrar también los archivos del programa SyncDood?`n`n{1}`n`nSolo se borran los archivos propios de SyncDood (el programa, los iconos, rclone.exe y los README). Todo lo demás que haya en esa carpeta no se toca."
        , "tab_history", "Historial"
        , "tab_conflicts", "Conflictos"
        , "cf_help", "Cuando el mismo archivo cambia en dos PCs antes de sincronizar, SyncDood se queda con el más nuevo y guarda la otra copia. No se pierde nada: entra aquí solo cuando quieras comparar y elegir."
        , "cf_none", "✓ No hay conflictos por revisar."
        , "cf_col_state", "Estado"
        , "cf_pending", "⚠ Por revisar"
        , "cf_kept", "Se conservó la que estaba"
        , "cf_swapped", "Se usó la otra"
        , "cf_all", "Marcar todos como revisados"
        , "cf_cur", "En uso (tu carpeta)"
        , "cf_oth", "Otra versión (copia guardada)"
        , "cf_size", "Tamaño: {1}"
        , "cf_date", "Fecha: {1}"
        , "cf_origin", "De: {1}"
        , "cf_newer", "● Más nueva"
        , "cf_older", "● Más vieja"
        , "cf_missing", "El archivo no está"
        , "cf_nofile", "Archivo normal: sin vista previa"
        , "cf_keep", "Conservar la que está"
        , "cf_use", "Usar la otra"
        , "cf_compare", "Comparar capturas"
        , "cf_pick", "Elige un conflicto de la lista para ver las dos versiones."
        , "cf_foot", "La otra copia queda en tus respaldos (los días se definen en Opciones). Las copias de states nunca se borran solas."
        , "cf_confirm_use", "¿Usar la otra versión de este archivo?`n`n{1}`n`nLa que está en uso ahora se guarda primero en los respaldos, y la otra se sincronizará a tus demás PCs en la próxima sincronización."
        , "cf_confirm_all", "¿Marcar {1} conflicto(s) como revisados y conservar las versiones en uso?`n`nLas otras copias se quedan en los respaldos."
        , "btn_cf_review", "Revisar"
        , "tab_folders", "Carpetas"
        , "tab_cloud", "Nube"
        , "tab_options", "Opciones"
        , "tab_about", "Acerca de"
        , "tab_games", "Partidas"
        , "g_intro", "Tus juegos con states. Haz doble clic en uno para ver sus slots, versiones anteriores y restaurar una."
        , "g_refresh", "Actualizar"
        , "g_versions", "Versiones anteriores / Restaurar…"
        , "g_col_game", "Juego"
        , "g_col_slot", "Slot"
        , "g_col_date", "Guardado"
        , "g_col_origin", "Origen"
        , "g_here", "Esta PC"
        , "g_other", "Otra PC"
        , "g_unknown", "—"
        , "g_restored_origin", "Restaurada aquí"
        , "g_empty", "No se encontraron states en tus carpetas."
        , "g_nomatch", "Ningún juego coincide con tu búsqueda."
        , "g_open", "Abrir"
        , "g_search", "Buscar juego…"
        , "g_sort_az", "A–Z"
        , "g_sort_new", "Recientes"
        , "gd_title", "States - {1}"
        , "gd_sub", "{1}  ·  carpeta «{2}»  ·  {3} state(s)"
        , "gd_slot", "Slot {1}"
        , "gd_info", "{1}  ·  {2}  ·  {3}  ·  Origen: {4}"
        , "g_nosel", "Primero elige un juego o state."
        , "g_loading", "Cargando…"
        , "slot_auto", "Auto"
        , "ev_restore", "Restaurado"
        , "v_title", "Versiones - {1} (slot {2})"
        , "v_help", "Son copias que SyncDood ya guarda en sus respaldos; no se guarda nada extra. Elige una para ver su captura y restaurarla. El state actual se copia antes a los respaldos, así que puedes deshacer."
        , "v_current", "Actual"
        , "v_kind_day", "Sobrescrita por una sync ({1})"
        , "v_kind_conf", "Reemplazada / perdió un conflicto ({1})"
        , "v_kind_cloud", "Respaldo en la nube ({1})"
        , "v_col_date", "Guardado"
        , "v_col_kind", "Copia"
        , "v_col_size", "Tamaño"
        , "v_restore", "Restaurar esta versión"
        , "v_cloud", "Incluir respaldos de la nube"
        , "v_close", "Cerrar"
        , "v_pick", "Elige una versión anterior (no la actual)."
        , "v_confirm", "¿Restaurar {1} (slot {2}) a la versión guardada el {3}?`n`nEl state actual se copia antes a los respaldos, y el restaurado se sincronizará a tus otras PCs."
        , "v_confirm_emu", "El emulador está abierto. Ciérralo primero o podría sobrescribir el state restaurado."
        , "v_done", "Restaurado. Se sincronizará a tus otras PCs en la próxima sync."
        , "v_fail", "No se pudo restaurar: {1}"
        , "v_cloud_fail", "No se pudieron leer los respaldos de la nube. Revisa tu conexión."
        , "v_cloud_none", "No hay más versiones en la nube."
        , "v_nopreview", "Esta versión no tiene captura"
        , "v_compare", "Ampliar / Comparar…"
        , "v_cmp_title", "Comparar - {1} (slot {2})"
        , "v_cmp_cur", "Actual  ·  {1}"
        , "v_cmp_ver", "Versión elegida  ·  {1}"
        , "v_cmp_only", "{1}"
        , "tab_status", "Estado"
        , "f_excl", "Opciones y exclusiones…"
        , "f_col_excl", "Exclusiones"
        , "ex_rules", "{1} reglas"
        , "ex_title", "Exclusiones - {1}"
        , "ex_help", "Los archivos y carpetas que cumplan estas reglas NO se sincronizan: se ignoran en esta PC y en la nube, y no se borra nada. Una regla por línea:`n   *.log  = archivos por nombre      shaders/  = una carpeta, esté donde esté      /logs/  = una carpeta solo en la raíz`nNo importan las mayúsculas. Lo que ya se subió se queda en la nube (SyncDood simplemente deja de tocarlo)."
        , "ex_none", "Sin reglas: se sincroniza todo."
        , "ex_preview", "Estas reglas excluyen {1} archivo(s) en esta PC ({2})."
        , "ex_add_file", "+ Archivo…"
        , "ex_add_folder", "+ Carpeta…"
        , "ex_pick_file", "Elige el archivo a excluir"
        , "ex_pick_folder", "Elige la carpeta a excluir"
        , "ex_outside", "Eso no está dentro de la carpeta sincronizada."
        , "ex_save", "Guardar"
        , "st_waiting", "Esperando a que terminen de escribirse los archivos de {1}…"
        , "st_title_ok", "Todo al día"
        , "st_title_syncing", "Sincronizando…"
        , "st_title_conflict", "Conflictos por revisar"
        , "st_title_error", "No se pudo sincronizar"
        , "st_side_ok", "Al día"
        , "st_side_syncing", "Sincronizando…"
        , "st_side_conflict", "Conflicto"
        , "st_side_error", "Error"
        , "st_recent", "Actividad reciente"
        , "st_all_history", "Ver todo el historial →"
        , "st_none", "Todavía no hay actividad."
        , "st_folder_wait", "Esperando la primera revisión"
        , "st_folder_ok", "Al día · {1}"
        , "st_folder_syncing", "Sincronizando…"
        , "st_folder_error", "Error: {1}"
        , "st_folder_conflict", "Conflicto · {1}"
        , "st_folder_pending", "Primera sincronización pendiente"
        , "st_more_folders", "+{1} carpetas más (ver Carpetas)"
        , "st_progress", "Sincronizando {1} ({2} de {3})…"
        , "st_next", "Próxima revisión automática: {1}"
        , "st_paused", "Sincronización automática en pausa mientras {1} está abierto (se sincroniza al cerrarlo)."
        , "pv_title", "Primera sincronización"
        , "pv_wait", "Revisando {1}…"
        , "pv_body", "Primera sincronización de '{1}'.`n`nEsta PC ({2}): {3} archivos, {4}`nNube: {5} archivos, {6}`n`nQué va a pasar: {7}`n`n¿Continuar?"
        , "o_export", "Exportar ajustes…"
        , "o_import", "Importar ajustes…"
        , "cfg_export_title", "Guardar ajustes de SyncDood"
        , "cfg_import_title", "Elige el archivo de ajustes de SyncDood"
        , "cfg_exported", "Ajustes guardados en:`n{1}`n`nIncluye tus carpetas (con rutas portátiles), exclusiones y opciones. No incluye contraseñas ni tokens de la nube: conecta la nube en la otra PC desde la pestaña Nube."
        , "cfg_fail", "No se pudo guardar el archivo: {1}"
        , "cfg_bad", "Ese archivo no es de ajustes de SyncDood."
        , "cfg_replace", "reemplaza la que hay aquí"
        , "cfg_import_ask", "¿Importar {1} carpetas?{2}`n`nSyncDood se reinicia y cada carpeta hace una primera sincronización (con vista previa) antes de sincronizar normal."
        , "sp_btn", "Espacio por carpeta…"
        , "sp_title", "Espacio por carpeta"
        , "sp_help", "Cuánto ocupa cada carpeta en esta PC, en la nube y en los respaldos."
        , "sp_pc", "Esta PC"
        , "sp_cloud", "Nube"
        , "sp_bk_cloud", "Respaldos nube"
        , "sp_bk_pc", "Respaldos locales"
        , "sp_total", "Total"
        , "sp_close", "Cerrar"
        , "menu_pause", "Pausar sincronización"
        , "menu_resume", "Reanudar sincronización"
        , "pause_1h", "Por 1 hora"
        , "pause_4h", "Por 4 horas"
        , "pause_forever", "Hasta que la reanude"
        , "btn_pause", "Pausar"
        , "btn_resume", "Reanudar"
        , "st_paused_manual", "La sincronización está en pausa. Pulsa Reanudar cuando quieras que continúe."
        , "st_paused_until", "La sincronización está en pausa hasta {1}."
        , "tip_paused", "Sincronización en pausa"
        , "reason_resume_pause", "reanudando tras la pausa"
        , "reason_resume_cap", "límite de la nube liberado"
        , "fail_cap", "Se alcanzó el límite diario de la nube"
        , "tip_cap", "Límite de la nube alcanzado. SyncDood reintentará solo a las {1}."
        , "hist_cap", "Límite de la nube alcanzado; se reintenta a las {1}"
        , "st_cap", "La nube alcanzó su límite diario. SyncDood reintentará solo a las {1}."
        , "cap_still", "Se alcanzó el límite diario de la nube y debería liberarse a las {1}.`n`n¿Sincronizar ahora de todos modos?"
        , "st_cloud", "Nube: {1}"
        , "c_app_of", "Carpeta de {1}"
        , "c_space_btn", "Ver espacio"
        , "c_space_wait", "Consultando espacio…"
        , "c_space_used", "SyncDood usa {1} en la nube ({2} archivos)."
        , "c_space_acct", "Cuenta: {1} usados de {2} ({3} libres)."
        , "c_space_none", "Esta nube no informa el espacio libre de la cuenta."
        , "c_space_fail", "No se pudo leer el tamaño de la nube. Revisa la conexión."
        , "st_sync_folder", "Sincronizar"
        , "f_sync_one", "Sincronizar carpeta seleccionada"
        , "seg_auto", "Auto"
        , "o_theme", "Apariencia"
        , "th_light", "Claro"
        , "th_dark", "Oscuro"
        , "o_settle", "Espera de archivos en escritura (segundos, 0 = no esperar)"
        , "o_parallel", "Subidas/bajadas en paralelo (Auto = lo mejor para tu nube)"
        , "o_maxdel", "Detener si una sync borraría más de este % (0 = sin límite)"
        , "o_cloudprune", "Limpiar también respaldos y conflictos viejos de la nube (mismos días; los states se quedan)"
        , "fail_blocked", "detenida: borraría demasiados archivos"
        , "tip_blocked", "Sincronización detenida en {1}: borraría demasiados archivos. Usa Sincronizar ahora para revisarla"
        , "hist_blocked", "Detenida por la protección contra borrados (no se borró nada)"
        , "blk_head", "Se detuvo la sincronización de la carpeta «{1}» porque borraría más del {2}% de sus archivos."
        , "blk_count", "Borrados: {1} de {2} elementos."
        , "blk_local", "Se borrarían EN ESTA PC: {1}"
        , "blk_cloud", "Se borrarían EN LA NUBE: {1}"
        , "blk_sample", "Ejemplos:"
        , "blk_question", "¿Continuar de todos modos? (Lo borrado sigue yendo a la carpeta de respaldos.)"
        , "seg_manual", "Manual"
        , "hist_folder", "Carpeta:"
        , "hist_all", "Todas las carpetas"
        , "col_date", "Fecha"
        , "col_folder", "Carpeta"
        , "col_event", "Evento"
        , "col_file", "Archivo"
        , "col_size", "Tamaño"
        , "fmt_date", "dd/MM HH:mm"
        , "f_intro", "Carpetas que SyncDood mantiene sincronizadas. El nombre es la subcarpeta en la nube y debe ser el mismo en todas tus PCs; la ubicación puede ser distinta en cada PC (y puede usar %DOCUMENTS% o %USERPROFILE% para que funcione con cualquier nombre de usuario)."
        , "f_add", "Agregar carpeta…"
        , "f_change", "Cambiar ruta…"
        , "f_remove", "Quitar"
        , "f_open", "Abrir"
        , "f_repair", "Primera sincronización / reparar…"
        , "f_col_name", "Nombre (en la nube)"
        , "f_col_path", "Carpeta en esta PC"
        , "f_dup_name", "Ya hay una carpeta con ese nombre."
        , "f_dup_path", "Esa carpeta ya se está sincronizando."
        , "f_nosel", "Primero selecciona una carpeta de la lista."
        , "f_remove_confirm", "¿Dejar de sincronizar '{1}'?`n`nNo se borra nada: los archivos se quedan en esta PC y en la nube."
        , "f_remove_last", "Debes conservar al menos una carpeta."
        , "f_change_confirm", "Cambiar la carpeta de '{1}' a:`n{2}`n`nSyncDood hará una primera sincronización de ella (fusiona esta carpeta con la nube). No se pierde nada: lo que se sobrescriba queda en respaldos.`n`n¿Continuar?"
        , "f_busy", "Hay una sincronización en curso. Inténtalo cuando termine."
        , "f_portable_ask", "Esta carpeta está dentro de la carpeta de tu usuario de Windows.`n`n¿Guardarla como:`n{1}`n`npara que también funcione en PCs con otro nombre de usuario?"
        , "f_cloud_add", "Agregar desde la nube…"
        , "f_portable_tag", "portátil"
        , "f_search", "Buscar:"
        , "f_count", "{1} carpetas"
        , "f_count_f", "{1} de {2} carpetas"
        , "f_col_status", "Estado"
        , "st_summary", "{1} carpetas · {2} al día · {3} con problemas  —  ver todas"
        , "hist_more", "Más ({1}) ▾"
        , "cf_looking", "Consultando la nube…"
        , "cf_fail", "No pude leer la nube. Revisa la conexión en la pestaña Nube e inténtalo de nuevo."
        , "cf_none", "No hay carpetas en la nube que falten en esta PC."
        , "cf_title", "Agregar desde la nube"
        , "cf_help", "Estas carpetas ya existen en tu nube pero no están configuradas en esta PC. Elige una y luego indica en qué lugar de esta PC va."
        , "cf_next", "Continuar…"
        , "pick_cloud", "¿Dónde va '{1}' en esta PC?"
        , "fd_title_add", "Agregar carpeta"
        , "fd_title_cloud", "Agregar carpeta desde la nube"
        , "fd_title_edit", "Opciones de la carpeta - {1}"
        , "fd_name", "Nombre en la nube"
        , "fd_path", "Carpeta en esta PC"
        , "fd_browse", "Examinar…"
        , "fd_portable", "Guardar la ruta como {1} (también sirve en PCs con otro nombre de usuario)"
        , "fd_tree", "Qué sincronizar"
        , "fd_tree_help", "Solo lo que esté MARCADO se sincroniza: se sube a tu nube y se copia a tus otras PCs. Quita la marca a lo que no quieras sincronizar (no se borra nada)."
        , "fd_choose", "Solo quiero sincronizar UNA PARTE de esta carpeta (elegir archivos o carpetas)"
        , "fd_simple", "Todo lo que hay dentro de esta carpeta ({2} elementos) se sincronizará con tu nube y tus otras PCs:`n{1}"
        , "fd_simple_empty", "Esta carpeta está vacía o aún no existe. Lo que haya dentro se sincronizará con tu nube y tus otras PCs:`n{1}"
        , "fd_tip_sub", "Consejo: si solo necesitas una subcarpeta, cancela y elige directamente esa subcarpeta."
        , "fd_cloud_info", "En la nube, '{1}' contiene: {2}`nEstos elementos se colocarán directamente DENTRO de la carpeta elegida arriba."
        , "fd_cloud_empty", "La carpeta de la nube '{1}' parece vacía (o no se pudo leer)."
        , "fd_cloud_warn", "⚠ La carpeta de la nube '{1}' ya tiene una carpeta llamada '{2}' dentro. Con esta ruta terminarías con '{2}\{2}'. ¿Quisiste elegir la carpeta de arriba: {3}?"
        , "fd_cloud_fix", "{1}`n`nLa carpeta de la nube '{2}' ya contiene una carpeta llamada '{3}', así que terminarías con:`n{1}\{3}`n`nSí = usar la carpeta de arriba ({4})`nNo = dejar esta ruta de todos modos`nCancelar = volver"
        , "fd_root_confirm", "Esa es una carpeta muy general:`n{1}`n`nSyncDood sincronizaría todo lo que contiene, salvo lo que desmarques. Normalmente quieres la carpeta propia del juego. ¿Continuar de todos modos?"
        , "fd_only", "Sincronizar solo lo marcado (lo NUEVO que aparezca después no se sincroniza)"
        , "fd_only_help", "Úsalo cuando quieres solo unos pocos archivos o carpetas de una carpeta grande. Sin esto, los archivos y carpetas nuevos se sincronizan solos."
        , "fd_count_only", "SOLO los {1} elemento(s) marcados se sincronizarán. Lo nuevo que aparezca después NO se sincronizará."
        , "fd_adv_off", "Reglas extra (no se usan en este modo)"
        , "fd_only_trunc", "Esta carpeta tiene demasiados elementos para listarlos todos, y «sincronizar solo lo marcado» necesita la lista completa.`n`nElige una subcarpeta, o desactiva esa opción."
        , "ex_only", "Solo lo marcado"
        , "fd_checkall", "Marcar todo"
        , "fd_uncheckall", "Desmarcar todo"
        , "fd_count", "{1} elemento(s) se sincronizarán con la nube  ·  {2} NO"
        , "fd_none", "No hay nada marcado, así que no se sincronizaría nada. Marca lo que quieras sincronizar."
        , "fd_err_none", "No hay nada marcado, así que SyncDood no sincronizaría nada.`n`nMarca al menos los archivos o carpetas que quieras sincronizar."
        , "fd_tree_empty", "Aún no hay nada que mostrar: la carpeta está vacía o no existe. Aun así puedes agregar reglas abajo."
        , "fd_tree_trunc", "solo se muestran los primeros {1} elementos; usa las reglas de abajo para el resto"
        , "fd_excluded", "{1} elemento(s) NO se sincronizarán"
        , "fd_all_synced", "Todo ({1} elementos) se sincronizará con la nube"
        , "fd_adv", "Reglas extra (opcional)"
        , "fd_empty", "Sincronizar también las carpetas vacías (conservar la estructura)"
        , "fd_empty_help", "Actívalo si el juego o emulador necesita que sus carpetas existan aunque estén vacías. También se crean en tus otras PCs."
        , "fd_empty_b2", "Tu nube (Backblaze B2) no puede guardar carpetas vacías."
        , "fd_add", "Agregar carpeta"
        , "fd_err_name", "Escribe un nombre para la carpeta."
        , "fd_big_confirm", "Esta carpeta tiene miles de archivos:`n{1}`n`n¿De verdad es la que quieres sincronizar? (Por ejemplo, elige la carpeta del propio juego, no «Documentos».)"
        , "fd_err_abs", "Elige una ruta completa en esta PC, por ejemplo C:\Juegos\Saves."
        , "fd_create_ask", "Esa carpeta aún no existe:`n{1}`n`n¿Quieres crearla?"
        , "re_local", "Si un archivo existe aquí y en la nube, gana la versión de ESTA PC."
        , "re_cloud", "Si un archivo existe aquí y en la nube, gana la versión de la NUBE."
        , "re_newer", "Si un archivo existe aquí y en la nube, gana el MÁS RECIENTE."
        , "re_body", "Esto hace una sincronización inicial que fusiona esta PC con la nube.`n`n{1}`n`nLo que no esté de un lado se copia al otro, y lo que pierda se guarda en la carpeta de respaldos.`n`n¿Continuar?"
        , "re_title", "SyncDood - Primera sincronización"
        , "c_current", "Nube actual"
        , "c_unknown", "Desconocida"
        , "c_local", "Carpeta (app de nube, red o NAS)"
        , "c_target", "Destino: {1}"
        , "c_change", "Cambiar nube…"
        , "c_test", "Probar conexión"
        , "c_note", "Usa la misma nube en todas tus PCs. Al cambiarla, cada carpeta hace una primera sincronización contra la nueva (se fusionan; no se borra nada, lo que se sobrescriba queda en respaldos)."
        , "c_confirm", "¿Cambiar la nube?`n`nCada carpeta hará una primera sincronización contra la nueva nube y se fusionará con lo que haya ahí. No se borra nada: lo que se sobrescriba queda en respaldos.`n`n¿Continuar?"
        , "c_test_ok", "Conexión correcta."
        , "c_test_fail", "No se pudo conectar con la nube.`n`n{1}"
        , "o_language", "Idioma"
        , "lang_auto", "Automático (Windows)"
        , "o_interval", "Revisar cada (minutos)"
        , "o_watch", "Proceso del emulador (sincroniza al cerrarse; vacío = desactivado)"
        , "o_resume", "Espera tras reanudar de suspensión (segundos)"
        , "o_firstwins", "Primera sincronización: quién gana si el archivo está en ambos lados"
        , "fw_newer", "El más reciente"
        , "fw_local", "Esta PC"
        , "fw_cloud", "La nube"
        , "o_backupdir", "Carpeta de respaldos"
        , "o_keepdays", "Conservar respaldos y conflictos (días, 0 = siempre)"
        , "o_startup", "Iniciar con Windows"
        , "o_checkupd", "Buscar actualizaciones al iniciar"
        , "o_pause", "No sincronizar automáticamente mientras el emulador está abierto (evita conflictos)"
        , "o_dryrun", "Modo prueba (solo escribe en el log lo que haría)"
        , "o_save", "Guardar y aplicar"
        , "o_open_ini", "Abrir config.ini"
        , "o_open_log", "Abrir log"
        , "o_open_backups", "Abrir respaldos"
        , "o_invalid", "Revisa los números: solo enteros, el intervalo debe ser al menos 1 y las transferencias en paralelo de 1 a 32, y el límite de borrados de 0 a 100."
        , "ab_version", "Versión {1}"
        , "ab_desc", "Mantiene tus saves y states iguales en todas tus PCs usando tu nube, con un ícono en la bandeja del sistema.`n`nÍcono azul = sincronizando, verde = todo al día, rojo = error, ámbar parpadeante = conflicto."
        , "ab_made", "Hecho por {1} con Claude AI. 🤖✨"
        , "ab_patreon", "☕ Apóyame en Patreon"
        , "ab_github", "🐙 Código fuente y descargas en GitHub"
        , "ab_libs", "Usa <a href=`"https://rclone.org`">rclone</a> (MIT) y <a href=`"https://www.autohotkey.com`">AutoHotkey v2</a> (GPLv2)."
        , "ab_check", "Buscar actualizaciones"
        , "ab_libs_plain", "Usa rclone (MIT) y AutoHotkey v2 (GPLv2)."
        , "upd_new", "Hay una versión nueva: {1} (tienes la {2}).`n`n¿Abrir la página de descarga?"
        , "upd_none", "Estás al día (versión {1})."
        , "upd_noreleases", "Todavía no hay versiones publicadas."
        , "upd_error", "No se pudo buscar actualizaciones. Revisa tu conexión a internet."
    )
    return Map("en", en, "es", es)
}

; ============================================================================
;  Single .exe
;  When compiled with Build.bat, rclone.exe and the icons live INSIDE SyncDood.exe.
;  They are unpacked into %LOCALAPPDATA%\SyncDood\bin (only when the .exe changes
;  version). Returns the path to rclone.exe.
; ============================================================================
ExtractBundle() {
    global IconDir
    binDir := AppDir "\bin"
    IconDir := binDir "\icons"
    rc := binDir "\rclone.exe"
    stampFile := binDir "\.stamp"
    stamp := FileGetTime(A_ScriptFullPath, "M") "|" FileGetSize(A_ScriptFullPath)
    old := ""
    try {
        old := FileRead(stampFile)
    }
    if (old = stamp && FileExist(rc) && FileExist(IconDir "\ok.ico"))
        return rc
    try {
        DirCreate(IconDir)
        FileInstall("rclone.exe", rc, 1)
        FileInstall("icons\ok.ico", IconDir "\ok.ico", 1)
        FileInstall("icons\syncing.ico", IconDir "\syncing.ico", 1)
        FileInstall("icons\error.ico", IconDir "\error.ico", 1)
        FileInstall("icons\conflict.ico", IconDir "\conflict.ico", 1)
        FileInstall("icons\conflict.png", IconDir "\conflict.png", 1)
        FileInstall("icons\ok.png", IconDir "\ok.png", 1)
        FileInstall("icons\syncing.png", IconDir "\syncing.png", 1)
        FileInstall("icons\error.png", IconDir "\error.png", 1)
        try {
            FileDelete(stampFile)
        }
        FileAppend(stamp, stampFile)
    } catch as e {
        if !FileExist(rc) {
            MsgBox(T("bundle_fail", e.Message), "SyncDood", "Iconx")
            ExitApp()
        }
    }
    return rc
}

; ============================================================================
;  Setup wizard (first launch only; later everything is edited in the window)
; ============================================================================
RunWizard() {
    MsgBox(T("wiz_welcome"), T("wiz_title"), "Iconi")

    folders := Map()
    folders.CaseSense := "Off"
    saves := PickFolder(T("pick_saves"))
    states := PickFolder(T("pick_states"))
    if (StrLower(saves) = StrLower(states)) {
        MsgBox(T("wiz_same"), "SyncDood", "Iconx")
        ExitApp()
    }
    folders["saves"] := saves
    folders["states"] := states

    while (MsgBox(T("wiz_more"), "SyncDood", "YesNo Icon?") = "Yes") {
        extra := PickFolder(T("pick_add"))
        SplitPath(extra, &nm)
        nm := RegExReplace(nm, "[^\w\-]", "_")
        ib := InputBox(T("f_nameprompt"), "SyncDood", "w380 h170", nm)
        if (ib.Result != "OK" || Trim(ib.Value) = "")
            continue
        nm := RegExReplace(Trim(ib.Value), "[^\w\-]", "_")
        if (folders.Has(nm) || ReservedName(nm)) {
            MsgBox(T(ReservedName(nm) ? "f_reserved" : "f_dup_name"), "SyncDood", "Iconx")
            continue
        }
        folders[nm] := extra
    }

    info := ChooseCloud(RemoteName, false)

    ; --- save configuration
    try {
        IniDelete(IniFile, "folders")
    }
    try {
        IniDelete(IniFile, "firstsync")
    }
    for nm, p in folders
        IniWrite(p, IniFile, "folders", nm)
    IniWrite(info["remote"], IniFile, "general", "remote")
    IniWrite(info["name"], IniFile, "general", "cloudName")
    IniWrite(info["id"], IniFile, "general", "cloudId")
    IniWrite("0", IniFile, "general", "parallelOverride")      ; new cloud: back to its recommended parallel value
    DefIni("firstSyncWins", "newer")     ; newer | local | cloud
    DefIni("intervalMin", "5")
    DefIni("watchProcess", "retroarch.exe")
    DefIni("resumeDelaySec", "20")
    DefIni("backupDir", AppDir "\backups")
    DefIni("backupKeepDays", "30")
    DefIni("dryRun", "0")
    DefIni("checkUpdates", "1")
    DefIni("pauseWhileRunning", "1")
    DefIni("language", "auto")
    IniWrite("1", IniFile, "general", "configured")
    try {
        FileDelete(DataDir "\*.snap")
    }
    EnableStartup()
    MsgBox(T("wiz_done"), "SyncDood", "Iconi")
}

DefIni(key, val) {
    if (IniRead(IniFile, "general", key, "") = "")
        IniWrite(val, IniFile, "general", key)
}

; ---- first-sync flags: one per folder (section [firstsync] in config.ini) -----
IsFirstDone(name) {
    return (IniRead(IniFile, "firstsync", name, "0") = "1")
}

MarkFirstDone(name) {
    IniWrite("1", IniFile, "firstsync", name)
}

AnyPending() {
    for name in Folders {
        if !IsFirstDone(name)
            return true
    }
    return false
}

; Forget everything about a folder's sync state (used when its path changes or it is removed)
ForgetFolder(name) {
    try {
        IniDelete(IniFile, "firstsync", name)
    }
    try {
        FileDelete(DataDir "\" name ".snap")
    }
    try {
        FileDelete(DataDir "\excl_" name ".txt")
    }
}

; ============================================================================
;  Portable paths.  A folder's path can start with a token so it is valid on every PC, whatever the
;  Windows user name is:   %DOCUMENTS%\My Game   ->   C:\Users\<whoever>\Documents\My Game
;  Tokens: %DOCUMENTS% %SAVEDGAMES% %DESKTOP% %LOCALAPPDATA% %APPDATA% %USERPROFILE%
;  (any other Windows variable such as %PROGRAMDATA% also works). config.ini keeps the token form.
; ============================================================================
KnownDirs() {
    prof := EnvGet("USERPROFILE")
    return [["%DOCUMENTS%", A_MyDocuments]
          , ["%SAVEDGAMES%", prof "\Saved Games"]
          , ["%DESKTOP%", A_Desktop]
          , ["%LOCALAPPDATA%", EnvGet("LOCALAPPDATA")]
          , ["%APPDATA%", A_AppData]
          , ["%USERPROFILE%", prof]]
}

; Real path on this PC of a path that may contain tokens
ExpandPath(p) {
    p := Trim(p)
    if !InStr(p, "%")
        return p
    for d in KnownDirs() {
        if (d[2] != "")
            p := StrReplace(p, d[1], d[2])
    }
    n := DllCall("ExpandEnvironmentStringsW", "WStr", p, "Ptr", 0, "UInt", 0, "UInt")
    if (n <= 1)
        return p
    buf := Buffer(n * 2)
    DllCall("ExpandEnvironmentStringsW", "WStr", p, "Ptr", buf, "UInt", n, "UInt")
    return StrGet(buf, "UTF-16")
}

; The portable form of a real path ("" if it is not inside any known folder of this user)
PortablePath(p) {
    p := RTrim(p, "\")
    best := "", bestLen := 0
    for d in KnownDirs() {
        base := RTrim(d[2], "\")
        if (base != "" && PathInside(p, base) && StrLen(base) > bestLen) {
            best := d[1]
            bestLen := StrLen(base)
        }
    }
    return (best = "") ? "" : best SubStr(p, bestLen + 1)
}

; ============================================================================
;  Folder picker
;  Uses the modern Windows dialog (the same as "Open"): it has an address bar
;  where you can TYPE or PASTE the path. Returns the chosen path, or "" if cancelled.
; ============================================================================
SelectFolder(title := "Select a folder", startDir := "", owner := 0) {
    path := ""
    try {
        ; IFileOpenDialog
        dlg := ComObject("{DC1C5A9C-E88A-4dde-A5A1-60F82A20AEF7}", "{D57C7288-D4AD-4768-BE02-9D969532D960}")
        ComCall(10, dlg, "UInt*", &opts := 0)                   ; GetOptions
        ComCall(9, dlg, "UInt", opts | 0x20 | 0x40)             ; SetOptions: PICKFOLDERS + FORCEFILESYSTEM
        ComCall(17, dlg, "WStr", title)                         ; SetTitle
        if (startDir != "" && DirExist(startDir)) {
            iid := Buffer(16)
            DllCall("ole32\CLSIDFromString", "WStr", "{43826D1E-E718-42EE-BC55-A1E261C37BFE}", "Ptr", iid)   ; IShellItem
            if (DllCall("shell32\SHCreateItemFromParsingName", "WStr", startDir, "Ptr", 0, "Ptr", iid, "Ptr*", &si := 0) = 0) {
                ComCall(12, dlg, "Ptr", si)                     ; SetFolder (initial folder)
                ObjRelease(si)
            }
        }
        ComCall(3, dlg, "Ptr", owner)                           ; Show (throws if the user cancels)
        ComCall(20, dlg, "Ptr*", &item := 0)                    ; GetResult
        ComCall(5, item, "UInt", 0x80058000, "Ptr*", &pName := 0)   ; GetDisplayName (SIGDN_FILESYSPATH)
        path := StrGet(pName, "UTF-16")
        DllCall("ole32\CoTaskMemFree", "Ptr", pName)
        ObjRelease(item)
    } catch {
        return ""
    }
    return path
}

; Like SelectFolder, but closes the app if you cancel (used by the first-run wizard).
; Remembers the previous folder so the next pick opens nearby.
PickFolder(prompt) {
    static last := ""
    p := SelectFolder(prompt, last)
    if (p = "") {
        MsgBox(T("pick_required"), "SyncDood", "Iconx")
        ExitApp()
    }
    p := RTrim(p, "\")
    SplitPath(p, , &parent)
    last := (parent != "") ? parent : p
    return p
}

; ============================================================================
;  Available clouds
;  Each one declares only the data it really needs; the dialog shows only those fields.
;    star = recommended        oauth = authorized in the browser
;    fields = data it asks for (kind: text | secret | folder)
; ============================================================================
CloudProviders() {
    return [
        Map("id", "onedrive", "name", "OneDrive", "tag", T("pr_onedrive_tag"), "star", true, "oauth", true, "type", "onedrive"
            , "info", T("pr_onedrive_info"), "link", "", "fields", []),

        Map("id", "dropbox", "name", "Dropbox", "tag", T("pr_dropbox_tag"), "star", false, "oauth", true, "type", "dropbox"
            , "info", T("oauth_info"), "link", "", "fields", []),

        Map("id", "folder", "name", T("pr_folder_name"), "tag", T("pr_folder_tag"), "star", true, "oauth", false, "type", ""
            , "info", T("pr_folder_info"), "link", ""
            , "fields", [Map("id", "folder", "label", T("pr_folder_field"), "kind", "folder")]),

        Map("id", "filen", "name", T("pr_filen_name"), "tag", T("pr_filen_tag"), "star", false, "oauth", false, "type", "filen"
            , "info", T("pr_filen_info"), "link", T("pr_filen_link")
            , "fields", [Map("id", "email", "label", T("pr_filen_email"), "kind", "text")
                       , Map("id", "pass", "label", T("pr_filen_pass"), "kind", "secret")
                       , Map("id", "key", "label", T("pr_filen_key"), "kind", "secret")]),

        Map("id", "nas", "name", T("pr_nas_name"), "tag", T("pr_nas_tag"), "star", false, "oauth", false, "type", ""
            , "info", T("pr_nas_info"), "link", ""
            , "fields", [Map("id", "folder", "label", T("pr_nas_field"), "kind", "folder")]),

        Map("id", "pcloud", "name", "pCloud", "tag", T("pr_pcloud_tag"), "star", false, "oauth", true, "type", "pcloud"
            , "info", T("pr_pcloud_info"), "link", "", "fields", []),

        Map("id", "box", "name", "Box", "tag", T("pr_box_tag"), "star", false, "oauth", true, "type", "box"
            , "info", T("pr_box_info"), "link", "", "fields", []),

        Map("id", "drive", "name", T("pr_drive_name"), "tag", T("pr_drive_tag"), "star", false, "oauth", true, "type", "drive"
            , "info", T("pr_drive_info"), "link", T("pr_drive_link")
            , "fields", [Map("id", "cid", "label", T("pr_drive_cid"), "kind", "text")
                       , Map("id", "cs", "label", T("pr_drive_cs"), "kind", "secret")]),

        Map("id", "b2", "name", T("pr_b2_name"), "tag", T("pr_b2_tag"), "star", false, "oauth", false, "type", "b2"
            , "info", T("pr_b2_info"), "link", T("pr_b2_link")
            , "fields", [Map("id", "kid", "label", T("pr_b2_kid"), "kind", "text")
                       , Map("id", "key", "label", T("pr_b2_key"), "kind", "secret")
                       , Map("id", "bucket", "label", T("pr_b2_bucket"), "kind", "text")]),

        Map("id", "nextcloud", "name", T("pr_nextcloud_name"), "tag", T("pr_nextcloud_tag"), "star", false, "oauth", false, "type", "webdav"
            , "info", T("pr_nextcloud_info"), "link", ""
            , "fields", [Map("id", "url", "label", T("pr_nextcloud_url"), "kind", "text")
                       , Map("id", "user", "label", T("pr_nextcloud_user"), "kind", "text")
                       , Map("id", "pass", "label", T("pr_nextcloud_pass"), "kind", "secret")]),

        Map("id", "other", "name", T("pr_other_name"), "tag", T("pr_other_tag"), "star", false, "oauth", false, "type", ""
            , "info", T("pr_other_info"), "link", "", "fields", [])
    ]
}

; Shows the cloud dialog and creates the remote. Returns Map(remote, name, id),
; or "" if cancelable and the user gave up.
ChooseCloud(rname, cancelable := false) {
    Loop {
        v := CloudDialog(cancelable)
        if !IsObject(v)
            return ""
        remote := CreateRemote(v, rname)
        if (remote != "")
            return Map("remote", remote, "name", v["prov"]["name"], "id", v["prov"]["id"])
        msg := T("cloud_fail", CloudHint(v["prov"]["id"]))
        if (MsgBox(msg, "SyncDood", "YesNo Iconx") != "Yes") {
            if cancelable
                return ""
            ExitApp()
        }
    }
}

CloudHint(id) {
    switch id {
        case "onedrive":
            return T("hint_onedrive")
        case "drive":
            return T("hint_drive")
        case "b2":
            return T("hint_b2")
        case "nextcloud":
            return T("hint_nextcloud")
        case "folder":
            return T("hint_folder")
        case "nas":
            return T("hint_nas")
        case "filen":
            return T("hint_filen")
    }
    return T("hint_default")
}

; "Browse…" button of a folder field
BrowseInto(edit, owner, *) {
    p := SelectFolder(T("cd_browse_title"), Trim(edit.Value), owner.Hwnd)
    if (p != "")
        edit.Value := RTrim(p, "\")
}

; Shows the cloud list and ONLY the fields the chosen cloud needs.
; Returns Map("prov", <cloud>, "vals", Map(field -> value)), or "" if cancelled.
CloudDialog(cancelable := false) {
    provs := CloudProviders()
    st := Map("done", false, "cancel", false)
    g := Gui("+AlwaysOnTop", T("cd_title"))
    g.SetFont("s9", "Segoe UI")
    g.Add("Text", "w450", T("cd_intro"))

    labels := []
    for p in provs
        labels.Push((p["star"] ? "★ " : "") . p["name"] . "  ·  " . p["tag"])
    dd := g.Add("DropDownList", "w450 Choose1", labels)

    info := g.Add("Text", "w450 h140 y+12", "")
    info.GetPos(&ix, &iy, &iw, &ih)
    link := g.Add("Link", "xm w450 h18 y" . (iy + ih + 2), "")
    yBase := iy + ih + 30

    ; Controls of every cloud share the same area; only the chosen one is visible.
    ctrls := []
    edits := []
    for i, p in provs {
        ctrls.Push([])
        em := Map()
        y := yBase
        for f in p["fields"] {
            ctrls[i].Push(g.Add("Text", "xm w450 y" . y, f["label"]))
            if (f["kind"] = "folder") {
                e := g.Add("Edit", "xm w360 y" . (y + 20))
                b := g.Add("Button", "x+8 w82 yp-1", T("cd_browse"))
                b.OnEvent("Click", BrowseInto.Bind(e, g))
                ctrls[i].Push(e, b)
            } else {
                opt := "xm w450 y" . (y + 20) . (f["kind"] = "secret" ? " Password" : "")
                e := g.Add("Edit", opt)
                ctrls[i].Push(e)
            }
            em[f["id"]] := e
            y += 54
        }
        edits.Push(em)
    }

    btn := g.Add("Button", "Default xm w140 y" . yBase, T("cd_continue"))
    btnCancel := ""
    if cancelable
        btnCancel := g.Add("Button", "x+10 w110 yp", T("cd_cancel"))

    UpdateView(*) {
        sel := dd.Value
        for i, arr in ctrls {
            for c in arr
                c.Visible := (i = sel)
        }
        info.Text := provs[sel]["info"]
        link.Text := provs[sel]["link"]
        link.Visible := (provs[sel]["link"] != "")
        newY := yBase + provs[sel]["fields"].Length * 54 + 4
        btn.Move(, newY)
        if cancelable
            btnCancel.Move(, newY)
        g.Show("AutoSize")
    }

    Submit(*) {
        sel := dd.Value
        for f in provs[sel]["fields"] {
            if (Trim(edits[sel][f["id"]].Value) = "") {
                MsgBox(T("cd_missing", f["label"]), "SyncDood", "Iconx")
                return
            }
        }
        st["done"] := true
    }

    DlgClose(*) {
        if cancelable
            st["cancel"] := true
        else
            ExitApp()
    }

    dd.OnEvent("Change", UpdateView)
    btn.OnEvent("Click", Submit)
    if cancelable
        btnCancel.OnEvent("Click", DlgClose)
    g.OnEvent("Close", DlgClose)
    UpdateView()

    while (!st["done"] && !st["cancel"])
        Sleep(100)

    if st["cancel"] {
        g.Destroy()
        return ""
    }
    sel := dd.Value
    vals := Map()
    for id, e in edits[sel]
        vals[id] := Trim(e.Value)
    out := Map("prov", provs[sel], "vals", vals)
    g.Destroy()
    return out
}

; Creates the rclone remote and checks it works. Returns "remote:path" or "" on failure.
CreateRemote(v, rname) {
    prov := v["prov"]
    vals := v["vals"]
    id := prov["id"]
    remote := rname ":SyncDood"

    try {
        RunWait(Format('"{1}" config delete {2}', Rclone, rname), , "Hide")
    }

    if (id = "other") {
        MsgBox(T("cloud_other_msg", rname), "SyncDood", "Iconi")
        RunWait(Format('"{1}" config', Rclone))
    } else if (id = "folder" || id = "nas") {
        ; no rclone remote: sync against a folder of the cloud app / network
        remote := RTrim(vals["folder"], "\") . "\SyncDood"
    } else {
        args := Format("config create {1} {2}", rname, prov["type"])
        switch id {
            case "drive":
                args .= " scope=drive " CmdArg("client_id=" vals["cid"]) " " CmdArg("client_secret=" vals["cs"])
            case "b2":
                args .= " " CmdArg("account=" vals["kid"]) " " CmdArg("key=" vals["key"])
                remote := rname ":" vals["bucket"] "/SyncDood"
            case "filen":
                args .= " " CmdArg("email=" vals["email"]) SecretArgs(["password", "api_key"], [vals["pass"], vals["key"]])
            case "nextcloud":
                url := RTrim(vals["url"], "/")
                if !RegExMatch(url, "i)^https?://")
                    url := "https://" url
                args .= " vendor=nextcloud " CmdArg("url=" url "/remote.php/dav/files/" vals["user"] "/")
                    . " " CmdArg("user=" vals["user"]) SecretArgs(["pass"], [vals["pass"]])
        }
        if prov["oauth"]
            MsgBox(T("cloud_connect_msg"), "SyncDood", "Iconi")
        try {
            RunWait('"' Rclone '" ' args)
        }
    }

    ; verify: create the working folder in the cloud (also validates access)
    code := -1
    try {
        code := RunWait(Format('"{1}" mkdir "{2}"', Rclone, remote), , "Hide")
    }
    return (code = 0) ? remote : ""
}

; One command-line argument, quoted the way Windows expects (a " or a trailing \ inside it can't break the command)
CmdArg(s) {
    s := RegExReplace(s, '(\\*)"', '$1$1\"')
    s := RegExReplace(s, '(\\+)$', '$1$1')
    return '"' s '"'
}

; rclone's obscured form of a password, read through its standard input so the real password never
; shows up in a command line. "" if it couldn't be done.
Obscure(pw) {
    out := ""
    try {
        ex := ComObject("WScript.Shell").Exec(Format('"{1}" obscure -', Rclone))
        ex.StdIn.Write(pw)
        ex.StdIn.Close()
        out := Trim(ex.StdOut.ReadAll(), " `r`n`t")
    }
    return (out != "" && !InStr(out, " ")) ? out : ""
}

; Arguments "key=value" for secret settings: obscured first (so no plain password on the command line);
; if that fails, plain values + --obscure, still quoted safely.
SecretArgs(keys, values) {
    obs := []
    for v in values {
        o := Obscure(v)
        if (o = "")
            break
        obs.Push(o)
    }
    out := ""
    if (obs.Length = keys.Length) {
        for i, k in keys
            out .= " " CmdArg(k "=" obs[i])
        return out
    }
    for i, k in keys
        out .= " " CmdArg(k "=" values[i])
    return out " --obscure"
}

EnableStartup() {
    target := A_IsCompiled ? A_ScriptFullPath : A_AhkPath
    args   := A_IsCompiled ? "" : '"' A_ScriptFullPath '"'
    FileCreateShortcut(target, StartupLink, A_ScriptDir, args, "SyncDood")
}

; ============================================================================
;  Triggers
; ============================================================================
StartupSync() {
    PruneBackups()
    if AutoBlocked() {
        ShowHeldState()
        return
    }
    RunSync(T("reason_start"))
}

; ---- pause (chosen by the user) and cloud-limit hold (decided by SyncDood) --------------------
IsPaused() {
    global PauseUntil
    if (PauseUntil = "")
        return false
    if (PauseUntil = "forever")
        return true
    if (A_Now >= PauseUntil) {
        PauseUntil := ""
        try {
            IniDelete(IniFile, "state", "pauseUntil")
        }
        return false
    }
    return true
}

CapActive() {
    global CapUntil
    if (CapUntil = "")
        return false
    if (A_Now >= CapUntil) {
        CapUntil := ""
        try {
            IniDelete(IniFile, "state", "capUntil")
        }
        return false
    }
    return true
}

; automatic syncs (timer, resume from sleep, emulator closed...) stay quiet while either is active
AutoBlocked() {
    return (IsPaused() || CapActive())
}

; Shows the held state in the tray / banner (used when nothing else is running)
ShowHeldState() {
    if IsPaused()
        SetState("ok", T("tip_paused"))
    else if CapActive()
        SetState("error", T("tip_cap", FormatTime(CapUntil, T("fmt_date"))))
    UpdatePauseMenu()
}

SetPause(untilT) {
    global PauseUntil
    PauseUntil := untilT
    IniWrite(untilT, IniFile, "state", "pauseUntil")
    SetTimer(PauseExpired, 0)
    if (untilT != "forever")
        SetTimer(PauseExpired, -Max(1000, DateDiff(untilT, A_Now, "Seconds") * 1000))
    ShowHeldState()
}

PauseFor(minutes) {
    SetPause(DateAdd(A_Now, minutes, "Minutes"))
}

ClearPause() {
    global PauseUntil
    PauseUntil := ""
    try {
        IniDelete(IniFile, "state", "pauseUntil")
    }
    SetTimer(PauseExpired, 0)
    UpdatePauseMenu()
}

PauseExpired() {
    if IsPaused()
        return
    UpdatePauseMenu()
    if !AutoBlocked()
        RunSync(T("reason_resume_pause"))
}

ResumeNow(*) {
    ClearPause()
    if (!Syncing && !CapActive())
        RunSync(T("reason_resume_pause"))
    else
        UpdateHeader()
}

; Enables / disables the "Resume" item of the tray menu
UpdatePauseMenu() {
    try {
        if IsPaused()
            A_TrayMenu.Enable(T("menu_resume"))
        else
            A_TrayMenu.Disable(T("menu_resume"))
    }
    UpdateHeader()
}

; Pause button of the Status page: opens the choices, or resumes
PauseButton(*) {
    if IsPaused()
        ResumeNow()
    else
        PauseMenu.Show()
}

SetCap(untilT) {
    global CapUntil
    CapUntil := untilT
    IniWrite(untilT, IniFile, "state", "capUntil")
    SetTimer(CapExpired, 0)
    SetTimer(CapExpired, -Max(1000, DateDiff(untilT, A_Now, "Seconds") * 1000))
}

CapExpired() {
    if CapActive()
        return
    UpdateHeader()
    if !AutoBlocked()
        RunSync(T("reason_resume_cap"))
}

; If the log shows the cloud refused because of a limit, returns when it is worth trying again
; (local time, yyyyMMddHHmmss); otherwise "".
CapWait(txt) {
    if RegExMatch(txt, "i)cap[_ ]exceeded") {
        ; Backblaze: the daily caps reset at 12:00 AM GMT
        nextMidnight := DateAdd(SubStr(A_NowUTC, 1, 8) "000000", 1, "Days")
        return DateAdd(DateAdd(nextMidnight, UtcOffset(), "Seconds"), 3, "Minutes")
    }
    if RegExMatch(txt, "i)over ?quota|quota ?(is )?exceeded|exceeded.{0,20}quota|transfer quota|bandwidth limit|EOVERQUOTA|storageQuotaExceeded")
        return DateAdd(A_Now, 60, "Minutes")
    if RegExMatch(txt, "i)too many requests|rate ?limit|status code 429|error 429|HTTP 429")
        return DateAdd(A_Now, 15, "Minutes")
    return ""
}
; Saves/states are rewritten while you play: syncing then makes conflicts. When the emulator closes, AfterRA syncs.
EmuBusy() {
    return (PauseRun && WatchProc != "" && ProcessExist(WatchProc) != 0)
}
PeriodicSync() {
    global NextCheck
    NextCheck := DateAdd(A_Now, IntervalMin, "Minutes")
    if (EmuBusy() || AutoBlocked())
        return
    RunSync(T("reason_periodic"))
}
RetrySync() {
    if (EmuBusy() || AutoBlocked())
        return
    RunSync(T("reason_retry"))
}
ResumeSync() {
    if (EmuBusy() || AutoBlocked())
        return
    RunSync(T("reason_resume"))
}
AfterRA() {
    if AutoBlocked()
        return
    RunSync(T("reason_emu"))
}

OnPower(wParam, lParam, msg, hwnd) {
    ; 7 = PBT_APMRESUMESUSPEND, 18 = PBT_APMRESUMEAUTOMATIC
    ; A single reusable timer: if both notices arrive, it only runs once.
    if (wParam = 7 || wParam = 18)
        SetTimer(ResumeSync, -ResumeDelay * 1000)
}

WatchRA() {
    global WasRA
    running := (ProcessExist(WatchProc) != 0)
    if (WasRA && !running)
        SetTimer(AfterRA, -3000)
    WasRA := running
}

; ============================================================================
;  Synchronization
; ============================================================================
; tip = text for the tooltip and the window header; kind = "conflict" when it is a conflict notice
SetState(state, tip, kind := "") {
    global LastState, LastTip, TipKind
    LastState := state
    LastTip := tip
    TipKind := kind
    ; conflicts to review: steady amber icon (no blinking, no pop-ups) until they are reviewed in the Conflicts tab
    icon := IconDir "\" (kind = "conflict" ? "conflict" : state) ".ico"
    if FileExist(icon)
        TraySetIcon(icon)
    A_IconTip := SubStr("SyncDood - " tip, 1, 127)
    UpdateHeader()
}

; Keeps only the last 2 days of sync.log (checked at most once an hour).
RotateLog() {
    global LastTrimTick
    if (LastTrimTick != 0 && A_TickCount - LastTrimTick < 3600000)
        return
    LastTrimTick := A_TickCount
    TrimLog(2)
    PruneBackups()            ; hourly at most (before, it only ran at startup)
    PruneCloudBackups()       ; opt-in, at most once a day
}

TrimLog(days) {
    try {
        FileDelete(LogFile ".old")
    }
    if !FileExist(LogFile)
        return
    txt := ""
    try {
        txt := FileRead(LogFile, "UTF-8")
    } catch {
        return
    }
    cutoff := DateAdd(A_Now, -days, "Days")
    pat := "m)^(\d{4})/(\d\d)/(\d\d) (\d\d):(\d\d):(\d\d)"
    ; the log is chronological: binary search near the cut, then a short linear scan
    lo := 1, hi := StrLen(txt)
    while (hi - lo > 8192) {
        mid := (lo + hi) // 2
        if !RegExMatch(txt, pat, &mm, mid) {
            hi := mid
            continue
        }
        if (mm[1] mm[2] mm[3] mm[4] mm[5] mm[6] >= cutoff)
            hi := mid
        else
            lo := mid
    }
    pos := lo
    cut := 0
    while RegExMatch(txt, pat, &m, pos) {
        if (m[1] m[2] m[3] m[4] m[5] m[6] >= cutoff) {
            cut := m.Pos
            break
        }
        pos := m.Pos + m.Len
    }
    if (cut = 1)
        return                        ; everything is recent
    try {
        f := FileOpen(LogFile, "w", "UTF-8-RAW")
        if (cut > 1)
            f.Write(SubStr(txt, cut))
        f.Close()
    }
}

RunSync(reason := "manual", resyncAll := false, only := "") {
    global Syncing, Retries, SyncTotal, SyncIdx, SyncName, CapName

    if Syncing
        return
    if (reason = T("reason_manual") && CapActive()
        && MsgBox(T("cap_still", FormatTime(CapUntil, T("fmt_date"))), "SyncDood", "YesNo Icon? Default2") != "Yes")
        return

    Syncing := true
    capHit := false
    SyncTotal := (only != "") ? 1 : Folders.Count
    SyncIdx := 0
    SyncName := ""
    SetState("syncing", T("tip_syncing", reason))
    RotateLog()

    failed := []          ; "name|code"
    stillBlocked := []    ; stopped by the delete protection and not confirmed
    totUp := 0, totDown := 0, totConf := 0

    for name, path in Folders {
        if (only != "" && name != only)
            continue
        SyncIdx += 1
        SyncName := name
        FState[name]["st"] := "syncing"
        UpdateHeader()
        ; a folder does its "first sync" if asked, or if it never completed one
        pending := resyncAll || !IsFirstDone(name)
        isManual := (reason = T("reason_manual"))
        allow := false
        if Blocked.Has(name) {
            ; stopped earlier: only a manual sync asks again, automatic ones leave it alone
            if (!isManual || !AskBlocked(name)) {
                stillBlocked.Push(name)
                FState[name]["st"] := "error"
                FState[name]["msg"] := T("fail_blocked")
                continue
            }
            allow := true
        }
        ; first sync: show what is on each side and ask (automatic runs leave it waiting for the user)
        if (pending && !DryRun && !IsFirstDone(name) || (pending && resyncAll && !DryRun)) {
            if (!isManual && reason != T("reason_first")) {
                FState[name]["st"] := "pending"
                FState[name]["msg"] := T("st_folder_pending")
                continue
            }
            if !FirstPreview(name, path) {
                FState[name]["st"] := "pending"
                FState[name]["msg"] := T("st_folder_pending")
                continue
            }
        }
        code := SyncFolder(name, path, pending, &nu, &nd, &nc, "", allow)
        if (code = 91) {
            capHit := true
            CapName := name
            FState[name]["st"] := "error"
            FState[name]["msg"] := FailText(91)
            break
        }
        if (code = 90) {
            Blocked[name] := LastBlock
            AddHistory(name, "info", T("hist_blocked"), "")
            if (isManual && AskBlocked(name)) {
                code := SyncFolder(name, path, pending, &nu, &nd, &nc, "", true)
            } else {
                stillBlocked.Push(name)
                FState[name]["st"] := "error"
                FState[name]["msg"] := T("fail_blocked")
                continue
            }
        }
        if (code = 0 && Blocked.Has(name))
            Blocked.Delete(name)
        if (code != 0) {
            failed.Push(name "|" code)
            FState[name]["st"] := "error"
            FState[name]["msg"] := FailText(code)
        } else {
            totUp += nu, totDown += nd, totConf += nc
            FState[name]["st"] := (nc > 0 || FolderPendingConf(name)) ? "conflict" : "ok"
            FState[name]["when"] := FormatTime(, "HH:mm")
            FState[name]["msg"] := ""
            if (pending && !DryRun) {
                MarkFirstDone(name)
                AddHistory(name, "info", T("hist_first_done"), "")
            }
        }
    }

    Syncing := false

    ; the cloud refused because of a limit: stop here, no retries, resume by itself when it resets
    if capHit {
        SetCap(LastCapWait)
        Retries := 0
        when := FormatTime(CapUntil, T("fmt_date"))
        AddHistory(CapName, "fail", T("hist_cap", when), "")
        SetState("error", T("tip_cap", when))
        UpdatePauseMenu()
        SaveHistory()
        RefreshHistory()
        RefreshConflicts()
        return
    }

    ; folders that failed earlier and were not part of this run keep the error state
    others := ""
    for name, fs in FState {
        if (fs["st"] = "error" && !HasItem(failed, name))
            others .= name " (" fs["msg"] ") "
    }

    if (failed.Length > 0) {
        txt := ""
        for item in failed {
            parts := StrSplit(item, "|")
            txt .= parts[1] " (" FailText(parts[2]) ") "
        }
        if (Retries < 2) {
            Retries += 1
            SetState("error", T("tip_fail_retry", txt))
            SetTimer(RetrySync, -45000)
        } else {
            for item in failed {
                parts := StrSplit(item, "|")
                AddHistory(parts[1], "fail", T("hist_fail_log", FailText(parts[2])), "")
            }
            SetState("error", T("tip_fail", txt))
        }
    } else if (stillBlocked.Length > 0) {
        names := ""
        for nm in stillBlocked
            names .= nm " "
        SetState("error", T("tip_blocked", RTrim(names)))
    } else if (others != "") {
        SetState("error", T("tip_fail", others))
    } else if (PendingConflicts() > 0) {
        Retries := 0
        SetState("error", T("tip_conflict", PendingConflicts()), "conflict")
    } else {
        Retries := 0
        SetState("ok", T("tip_ok", FormatTime(, T("fmt_date")), totUp, totDown))
    }

    if (failed.Length = 0)
        FetchPcLogs()
    SaveHistory()
    RefreshHistory()
    RefreshConflicts()
}

; true if the "name|code" list has an entry for that folder
HasItem(list, name) {
    for item in list {
        if (StrSplit(item, "|")[1] = name)
            return true
    }
    return false
}

; Reads rclone's "Safety abort: too many deletes" from the log. true (and fills LastBlock) if that is what happened.
ParseBlock(txt) {
    global LastBlock
    if !InStr(txt, "too many deletes")
        return false
    n := 0, total := 0
    if RegExMatch(txt, "too many deletes[^\r\n]*?(\d+) of (\d+)", &m)
        n := Integer(m[1]), total := Integer(m[2])
    toLocal := 0, toCloud := 0, names := []
    for line in StrSplit(txt, "`n", "`r") {
        if RegExMatch(line, "Path([12])\s+File was deleted\s+- (.+)$", &d) {
            if (d[1] = "2")
                toLocal += 1          ; gone from the cloud -> would be deleted here
            else
                toCloud += 1
            if (names.Length < 6)
                names.Push(d[2])
        }
    }
    LastBlock := Map("n", n, "total", total, "toLocal", toLocal, "toCloud", toCloud, "names", names)
    return true
}

; Asks whether to run a stopped folder anyway. true = continue.
AskBlocked(name) {
    b := Blocked[name]
    msg := T("blk_head", name, MaxDelPct)
    if (b["n"] > 0)
        msg .= "`n`n" T("blk_count", b["n"], b["total"])
    if (b["toLocal"] > 0)
        msg .= "`n" T("blk_local", b["toLocal"])
    if (b["toCloud"] > 0)
        msg .= "`n" T("blk_cloud", b["toCloud"])
    if (b["names"].Length > 0) {
        msg .= "`n`n" T("blk_sample")
        for item in b["names"]
            msg .= "`n  • " item
    }
    msg .= "`n`n" T("blk_question")
    return (MsgBox(msg, "SyncDood", "YesNo Icon! Default2") = "Yes")
}

FailText(code) {
    if (code = "-1")
        return T("fail_exec")
    if (code = "7")
        return T("fail_repair")
    if (code = "90")
        return T("fail_blocked")
    if (code = "91")
        return T("fail_cap")
    return T("fail_code", code)
}

; Syncs ONE folder. Returns rclone's exit code (0 = ok).
; "count|bytes" of a folder (local or cloud), "0|0" if it does not exist or cannot be read
SideSize(target, name := "") {
    args := Format('size --json "{1}"', target)
    if (name != "")
        args .= FilterArgs(name)
    txt := RcloneText(args)
    c := 0, b := 0
    if RegExMatch(txt, '"count"\s*:\s*(\d+)', &mc)
        c := mc[1]
    if RegExMatch(txt, '"bytes"\s*:\s*(\d+)', &mb)
        b := mb[1]
    return c "|" b
}

; Before a folder's first sync: what is here, what is in the cloud and what will happen. true = go on.
FirstPreview(name, path) {
    ToolTip(T("pv_wait", name))
    loc := StrSplit(SideSize(path, name), "|")
    rem := StrSplit(SideSize(Remote "/" name, name), "|")
    ToolTip()
    if (loc[1] = 0 && rem[1] = 0)
        return true
    if (FirstWins = "local")
        how := T("re_local")
    else if (FirstWins = "cloud")
        how := T("re_cloud")
    else
        how := T("re_newer")
    return MsgBox(T("pv_body", name, path, loc[1], BigSize(loc[2]), rem[1], BigSize(rem[2]), how)
        , T("pv_title"), "YesNo Icon?") = "Yes"
}

SyncFolder(name, path, resync, &nUp, &nDown, &nConf, forceMode := "", allowDel := false) {
    global LastCapWait
    nUp := 0, nDown := 0, nConf := 0
    ; rclone bisync refuses to run when the exclusion rules changed since the last sync (it wants --resync).
    ; Do that re-listing ourselves, always in "newer wins" mode so it can't overwrite the wrong side.
    if (!resync && FilterChanged(name)) {
        if !DryRun
            AddHistory(name, "info", T("hist_filters"), "")
        return SyncFolder(name, path, true, &nUp, &nDown, &nConf, "newer")
    }
    if !DirExist(path)
        DirCreate(path)
    remotePath := Remote "/" name
    day := FormatTime(, "yyyy-MM-dd")

    ; --- "before" snapshot: what changed here since the last sync = what will be uploaded
    WaitSettled(name, path)
    rxs  := ExcludeRegexes(name)
    pre  := Scan(path, rxs)
    last := LoadSnap(name)
    upList := [], delHere := []
    if IsObject(last)
        Diff(last, pre, &upList, &delHere)

    if resync {
        try {
            RunWait(Format('"{1}" mkdir "{2}"', Rclone, remotePath), , "Hide")
        }
    }

    cmd := Format('"{1}" bisync "{2}" "{3}"'
        . ' --conflict-resolve newer --conflict-suffix syncconflict'
        . '{7} --resilient --recover'
        . ' --backup-dir1 "{4}" --backup-dir2 "{5}"'
        . ' -v --stats 0 --log-file "{6}"'
        , Rclone, path, remotePath
        , BackupDir "\" name "\" day
        , Remote "/_backup/" name "/" day
        , LogFile
        , EmptyDirsFor(name) ? " --create-empty-src-dirs" : "")
    par := ParallelNow()
    cmd .= Format(" --transfers {1} --checkers {2}", par, par * 2)
    cmd .= FilterArgs(name)
    if resync {
        ; path1 = this PC, path2 = cloud
        mode := (forceMode != "") ? forceMode : FirstWins
        if (mode = "local")
            cmd .= " --resync-mode path1"
        else if (mode = "cloud")
            cmd .= " --resync-mode path2"
        else
            cmd .= " --resync-mode newer"
    }
    if (MaxDelPct > 0 && !resync)
        cmd .= " --max-delete " MaxDelPct
    if allowDel
        cmd .= " --force"                ; the user confirmed this big deletion
    if DryRun
        cmd .= " --dry-run"

    code := -1
    logPos := LogSize()
    try {
        code := RunWait(cmd, , "Hide")
    }
    if (code != 0) {
        ; the cloud refused because of a limit (daily cap, quota, rate limit): stop and wait for it to reset
        capTxt := LogSince(logPos)
        capAt := CapWait(capTxt)
        if (capAt != "") {
            LastCapWait := capAt
            return 91
        }
        ; delete protection: rclone stopped before touching anything because too much would be deleted
        if (!resync && !allowDel && ParseBlock(LogSince(logPos)))
            return 90
        ; rclone has no record of a previous sync for this folder/cloud pair (new cloud name,
        ; moved folder, cleaned cache...): do a first sync, which merges and deletes nothing.
        if (!resync && InStr(LogSince(logPos), "cannot find prior Path1 or Path2 listings")) {
            AddHistory(name, "info", T("hist_relist"), "")
            rc := SyncFolder(name, path, true, &nUp, &nDown, &nConf)
            if (rc = 0)
                MarkFirstDone(name)
            return rc
        }
        ; rclone asks for --resync (for example, exclusions edited in a way SyncDood didn't notice): do it safely once
        if (!resync && code = 7 && InStr(LogSince(logPos), "--resync")) {
            if !DryRun
                AddHistory(name, "info", T("hist_filters"), "")
            return SyncFolder(name, path, true, &nUp, &nDown, &nConf, "newer")
        }
        return code
    }
    if DryRun            ; test mode: nothing was touched, nothing to record
        return 0

    ; --- "after" snapshot: what changed here because of the sync = what was downloaded
    post := Scan(path, rxs)
    downList := [], delCloud := []
    Diff(pre, post, &downList, &delCloud)

    ; what rclone itself decided (more exact than comparing folder snapshots); only for normal runs
    if (!resync && ParseBisyncLog(LogSince(logPos), rxs, &lUp, &lDown, &lDelHere, &lDelCloud)) {
        upList := lUp, downList := lDown, delHere := lDelHere, delCloud := lDelCloud
        fromLog := true
    } else {
        fromLog := false
    }

    ; --- conflicts: move the losing copy to the backups folder
    confl := []
    for rel, v in post {
        if InStr(rel, "syncconflict")
            confl.Push(rel)
    }
    ts := FormatTime(, "yyyy-MM-dd_HHmmss")
    ; the screenshot of a state that also conflicted travels with the state: it gets no notice of its own
    shotOf := Map()
    for rel in confl {
        sr := ShotRel(RegExReplace(rel, "\.+syncconflict\d*$"))
        if (sr != "")
            shotOf[StrLower(sr)] := true
    }
    for rel in confl {
        dest := BackupDir "\" name "\conflicts\" ts "\" rel
        SplitPath(dest, , &destDir)
        DirCreate(destDir)
        try {
            FileMove(path "\" rel, dest, true)
            orig := RegExReplace(rel, "\.+syncconflict\d*$")
            AddHistory(name, "conflict", orig, SizeOf(post[rel]))
            if !shotOf.Has(StrLower(orig))
                AddConflict(name, orig, dest, BackupDir "\" name "\conflicts\" ts)
            nConf += 1
        }
        post.Delete(rel)
    }

    ; --- history
    for rel in upList {
        if !InStr(rel, "syncconflict") {
            AddHistory(name, "up", rel, SizeOf(post.Get(rel, pre.Get(rel, ""))))
            nUp += 1
        }
    }
    for rel in delHere
        AddHistory(name, "del_here", rel, "")
    for rel in downList {
        if !InStr(rel, "syncconflict") {
            AddHistory(name, "down", rel, SizeOf(post.Get(rel, "")))
            nDown += 1
        }
    }
    for rel in delCloud
        AddHistory(name, "del_cloud", rel, "")

    ; --- who uploaded which state (shown as "Origin" in the Games tab)
    LogUploads(name, post, upList, downList, !IsObject(last))
    StoreFilter(name)
    SaveSnap(name, post)
    return 0
}

; Clouds that store real folders keep empty ones too. Object storage (Backblaze B2) has no real folders, so an empty
; one disappears from the cloud and bisync would then delete it on this PC: there empty folders are left alone.
KeepsEmptyDirs() {
    return (StrLower(IniRead(IniFile, "general", "cloudId", "")) != "b2")
}

; Files transferred at the same time (rclone --transfers; checks run at twice that).
; Automatic: 8 for clouds that handle parallel requests well (Backblaze B2, your own Nextcloud, a folder or NAS),
; 4 (rclone's default, the safe value) for the rest, which tend to rate-limit when pushed.
ParallelNow() {
    return (ParallelOverride > 0) ? ParallelOverride : ParallelAuto()
}

; Recommended value for the current cloud (ignores the manual value)
ParallelAuto() {
    id := StrLower(IniRead(IniFile, "general", "cloudId", ""))
    if (id = "b2" || id = "nextcloud" || id = "folder" || id = "nas")
        return 8
    if (id = "" && !RegExMatch(Remote, "^[^:\\/]{2,}:"))       ; a plain path (D:\...) is a folder
        return 8
    return 4
}

; ---- exclusion rules: remember what the last good sync used -----------------
FilterKey(name) {
    k := OnlyMode(name) ? "#only-checked`n" : ""
    for pat in ExcludePatterns(name)
        k .= pat "`n"
    ; a folder that treats empty folders differently from the cloud's default also needs the safe re-listing
    if (EmptyDirsFor(name) != KeepsEmptyDirs())
        k .= "#emptydirs=" (EmptyDirsFor(name) ? "1" : "0") "`n"
    return k
}

; true if the rules changed since the last good sync (no record = older install: don't force anything)
FilterChanged(name) {
    f := DataDir "\excl_" name ".txt"
    if !FileExist(f)
        return false
    old := ""
    try {
        old := FileRead(f, "UTF-8")
    }
    return (old != FilterKey(name))
}

StoreFilter(name) {
    f := DataDir "\excl_" name ".txt"
    try {
        FileDelete(f)
    }
    try {
        FileAppend(FilterKey(name), f, "UTF-8-RAW")
    }
}

; ============================================================================
;  Origin of a state: which PC uploaded it.
;  Each PC keeps a small list of the states IT uploaded (file name, date, size) and copies it to the cloud
;  as _pcs/<PC name>/<folder>.tsv (outside the synced folders). After each sync the other PCs' lists are
;  copied back here, so the name can be looked up offline by matching name + date + size.
;  Dates are stored in UTC so PCs in different time zones agree.
; ============================================================================
UploadLogFile(folder) {
    return DataDir "\uploads\" folder ".tsv"
}

UtcOffset() {            ; seconds: local time minus UTC (rounded to a quarter hour)
    return Round(DateDiff(A_Now, A_NowUTC, "Seconds") / 900) * 900
}

ToUtc(t) {
    return DateAdd(t, -UtcOffset(), "Seconds")
}

; Records the states this PC just uploaded. upList = files rclone uploaded; on a first sync (no earlier
; snapshot) every state that was not downloaded counts as this PC's.
LogUploads(name, post, upList, downList, firstRun) {
    global PcLogs
    if DryRun
        return
    cand := []
    if firstRun {
        downs := Map()
        downs.CaseSense := "Off"
        for rel in downList
            downs[rel] := true
        for rel, v in post {
            if (!downs.Has(rel) && IsStateFile(rel))
                cand.Push(rel)
        }
    } else {
        for rel in upList {
            if (IsStateFile(rel) && post.Has(rel))
                cand.Push(rel)
        }
    }
    lines := ""
    for rel in cand {
        pv := StrSplit(post[rel], "|")
        lines .= ToUtc(pv[1]) "`t" pv[2] "`t" rel "`t" A_NowUTC "`n"
    }
    if (lines = "")
        return
    f := UploadLogFile(name)
    old := ""
    try {
        old := FileRead(f, "UTF-8")
    }
    arr := StrSplit(RTrim(old lines, "`n"), "`n", "`r")
    if (arr.Length > 1500) {                 ; keep it small: drop the oldest
        arr.RemoveAt(1, arr.Length - 1000)
    }
    out := ""
    for ln in arr
        out .= ln "`n"
    try {
        DirCreate(DataDir "\uploads")
        FileDelete(f)
    }
    try {
        FileAppend(out, f, "UTF-8-RAW")
    }
    PcLogs := Map()
    try {
        RunWait(Format('"{1}" copyto "{2}" "{3}/_pcs/{4}/{5}.tsv"', Rclone, f, Remote, PcName, name), , "Hide")
    }
}

IsStateFile(rel) {
    SplitPath(rel, &leaf, &dir)
    return IsObject(ParseState(leaf, dir))
}

; Copies the other PCs' lists from the cloud (small files; nothing is ever deleted)
FetchPcLogs() {
    global PcLogs
    if DryRun
        return
    try {
        RunWait(Format('"{1}" copy "{2}/_pcs" "{3}\pcs" --include "*.tsv"', Rclone, Remote, DataDir), , "Hide")
    }
    PcLogs := Map()
}

; All upload records of a folder: array of Map(pc, mt, size, rel, ts)
LoadPcLogs(folder) {
    global PcLogs
    if PcLogs.Has(folder)
        return PcLogs[folder]
    out := []
    ReadPcLog(out, UploadLogFile(folder), PcName)
    Loop Files DataDir "\pcs\*", "D" {
        if (StrLower(A_LoopFileName) != StrLower(PcName))
            ReadPcLog(out, A_LoopFilePath "\" folder ".tsv", A_LoopFileName)
    }
    PcLogs[folder] := out
    return out
}

ReadPcLog(out, file, pc) {
    if !FileExist(file)
        return
    txt := ""
    try {
        txt := FileRead(file, "UTF-8")
    }
    for line in StrSplit(txt, "`n", "`r") {
        f := StrSplit(line, "`t")
        if (f.Length >= 4 && f[1] ~= "^\d{14}$")
            out.Push(Map("pc", pc, "mt", f[1], "size", f[2], "rel", f[3], "ts", f[4]))
    }
}

; Name of the PC that uploaded this exact file (same name, size and date), or "" if unknown.
; The date may differ by 2 s (clouds round it) or by exactly 1 h (daylight saving).
OriginOf(folder, rel, localTime, size) {
    if !(localTime ~= "^\d{14}$" && IsInteger(size))
        return ""
    tUtc := ToUtc(localTime)      ; not "t": variables are case-insensitive and would hide the function T()
    best := "", bestTs := -1
    for e in LoadPcLogs(folder) {
        if (!IsInteger(e["size"]) || Integer(e["size"]) != Integer(size) || StrLower(e["rel"]) != StrLower(rel))
            continue
        d := Abs(DateDiff(tUtc, e["mt"], "Seconds"))
        ts := IsInteger(e["ts"]) ? Integer(e["ts"]) : 0
        if ((d <= 2 || Abs(d - 3600) <= 2) && ts >= bestTs) {
            best := e["pc"]
            bestTs := ts
        }
    }
    if (best = "")
        return ""
    return (StrLower(best) = StrLower(PcName)) ? T("g_this_pc", best) : best
}

; ============================================================================
;  Folder snapshots (to know what was uploaded / downloaded)
; ============================================================================
Scan(path, rxs := "") {
    m := Map()
    if !DirExist(path)
        return m
    base := StrLen(path) + 2
    hasEx := IsObject(rxs) && rxs.Length > 0
    Loop Files path "\*", "FR" {
        rel := SubStr(A_LoopFilePath, base)
        if (hasEx && IsExcluded(rel, rxs))
            continue
        m[rel] := A_LoopFileTimeModified "|" A_LoopFileSize
    }
    return m
}

; ============================================================================
;  Exclusions (per folder).  One pattern per line in %LOCALAPPDATA%\SyncDood\exclude\<folder>.txt,
;  rclone syntax:  *.log   shaders/   /only-at-root.txt   dir/**
;  Matching is case-insensitive. Excluded files are ignored on BOTH sides (never deleted).
; ============================================================================
ExcludeFile(name) {
    return AppDir "\exclude\" name ".txt"
}

; Pattern lines of a folder (comments and empty lines removed)
ExcludePatterns(name) {
    out := []
    f := ExcludeFile(name)
    if !FileExist(f)
        return out
    txt := ""
    try {
        txt := FileRead(f, "UTF-8")
    }
    for line in StrSplit(txt, "`n", "`r") {
        line := Trim(line)
        if (line = "" || SubStr(line, 1, 1) = "#" || SubStr(line, 1, 1) = ";")
            continue
        out.Push(line)
    }
    return out
}

; "Only sync what is checked": the file starts with the marker line #only-checked and its rules are then
; the items that ARE synced (everything else is ignored, including anything new).
OnlyMode(name) {
    f := ExcludeFile(name)
    if !FileExist(f)
        return false
    txt := ""
    try {
        txt := FileRead(f, "UTF-8")
    }
    for line in StrSplit(txt, "`n", "`r") {
        if (Trim(line) = "#only-checked")
            return true
    }
    return false
}

FilterFile(name) {
    return AppDir "\exclude\" name ".filter"
}

; Extra rclone arguments that apply the folder's rules ("" if it has none)
FilterArgs(name) {
    if (ExcludeRegexes(name).Length = 0)
        return ""
    if !OnlyMode(name)
        return Format(' --ignore-case --exclude-from "{1}"', ExcludeFile(name))
    ; whitelist: "+ item" for each checked item, then "- *" for everything else (first match wins)
    out := ""
    for pat in ExcludePatterns(name)
        out .= "+ " (SubStr(pat, -1) = "/" ? pat "**" : pat) "`n"
    out .= "- *`n"
    try {
        DirCreate(AppDir "\exclude")
        FileDelete(FilterFile(name))
    }
    try {
        FileAppend(out, FilterFile(name), "UTF-8-RAW")
    }
    return Format(' --ignore-case --filter-from "{1}"', FilterFile(name))
}

ExcludeRegexes(name) {
    out := []
    if OnlyMode(name) {
        ; allow-list regexes are marked with a leading "!" (see IsExcluded); no rules = nothing is synced
        for pat in ExcludePatterns(name) {
            rx := PatToRegex(pat)
            if (rx != "")
                out.Push("!" rx)
        }
        if (out.Length = 0)
            out.Push("!i)(?!)")
        return out
    }
    for pat in ExcludePatterns(name) {
        rx := PatToRegex(pat)
        if (rx != "")
            out.Push(rx)
    }
    return out
}

; rclone-style glob -> PCRE (to preview and to ignore excluded files in the settle check)
PatToRegex(pat) {
    ; a backslash before a special character (\[ \* ...) escapes it; any other backslash is a Windows path separator
    pat := Trim(RegExReplace(pat, "\\(?![*?\[\]{}!\\])", "/"))
    if (pat = "")
        return ""
    anch := (SubStr(pat, 1, 1) = "/")
    if anch
        pat := SubStr(pat, 2)
    isDir := (SubStr(pat, -1) = "/")
    if isDir
        pat := SubStr(pat, 1, -1)
    if (pat = "")
        return ""
    rx := ""
    depth := 0
    i := 1
    n := StrLen(pat)
    while (i <= n) {
        ch := SubStr(pat, i, 1)
        if (ch = "\") {
            rx .= RegExReplace(SubStr(pat, i + 1, 1), "[\\.+()|\[\]{}^$,*?]", "\$0")
            i += 2
            continue
        }
        if (ch = "*") {
            if (SubStr(pat, i + 1, 1) = "*") {
                rx .= ".*"
                i += 2
                continue
            }
            rx .= "[^/]*"
        } else if (ch = "?") {
            rx .= "[^/]"
        } else if (ch = "[") {
            j := InStr(pat, "]", , i + 1)
            if (j > 0) {
                cls := SubStr(pat, i + 1, j - i - 1)
                if (SubStr(cls, 1, 1) = "!")
                    cls := "^" SubStr(cls, 2)
                rx .= "[" cls "]"
                i := j + 1
                continue
            }
            rx .= "\["
        } else if (ch = "{") {
            depth += 1
            rx .= "(?:"
        } else if (ch = "}" && depth > 0) {
            depth -= 1
            rx .= ")"
        } else if (ch = "," && depth > 0) {
            rx .= "|"
        } else {
            rx .= RegExReplace(ch, "[\\.+()|\[\]{}^$,]", "\$0")
        }
        i += 1
    }
    return "i)" . (anch ? "^" : "(?:^|/)") . rx . (isDir ? "/.*$" : "$")
}

IsExcluded(rel, rxs) {
    rel := StrReplace(rel, "\", "/")
    allowRules := false, allowed := false
    for rx in rxs {
        if (SubStr(rx, 1, 1) = "!") {            ; allow-list rule ("only sync what is checked")
            allowRules := true
            if RegExMatch(rel, SubStr(rx, 2))
                allowed := true
        } else if RegExMatch(rel, rx) {
            return true
        }
    }
    return (allowRules && !allowed)
}

; Waits (up to ~45 s) until no non-excluded file was modified in the last SettleSec seconds,
; so a state/save that the emulator is still writing is not uploaded half-written.
WaitSettled(name, path) {
    global SyncWaiting
    if (SettleSec <= 0 || !DirExist(path))
        return
    rxs := ExcludeRegexes(name)
    deadline := A_TickCount + 45000
    base := StrLen(path) + 2
    while true {
        youngest := -1
        Loop Files path "\*", "FR" {
            age := DateDiff(A_Now, A_LoopFileTimeModified, "Seconds")
            if (age < 0 || age >= SettleSec)
                continue
            if (rxs.Length > 0 && IsExcluded(SubStr(A_LoopFilePath, base), rxs))
                continue
            if (youngest < 0 || age < youngest)
                youngest := age
        }
        if (youngest < 0 || A_TickCount > deadline)
            break
        SyncWaiting := true
        UpdateHeader()
        Sleep(Max(1, SettleSec - youngest) * 1000 + 500)
    }
    if SyncWaiting {
        SyncWaiting := false
        UpdateHeader()
    }
}

; Reads rclone bisync's own log: which files changed on this PC (to upload), on the cloud (to download)
; and which were deleted. Returns false if the log has no such lines (so the caller falls back).
ParseBisyncLog(txt, rxs, &ups, &downs, &delHere, &delCloud) {
    ups := [], downs := [], delHere := [], delCloud := []
    if !InStr(txt, "checking for diffs")
        return false
    p1 := Map(), p2 := Map()          ; rel -> "chg" | "del"
    for line in StrSplit(txt, "`n", "`r") {
        if !RegExMatch(line, "^\S+ \S+ (?:INFO|NOTICE)\s*: - (Path[12])\s+(File .*?)\s{2,}- (.+)$", &m)
            continue
        rel := StrReplace(m[3], "/", "\")
        if InStr(rel, "syncconflict")
            continue
        if (rxs.Length > 0 && IsExcluded(rel, rxs))
            continue
        kind := InStr(m[2], "deleted") ? "del" : "chg"
        if (m[1] = "Path1")
            p1[rel] := kind
        else
            p2[rel] := kind
    }
    for rel, k in p1 {
        if (k = "del") {
            if !p2.Has(rel)
                delHere.Push(rel)
        } else if !(p2.Has(rel) && p2[rel] = "chg") {      ; changed on both sides = conflict
            ups.Push(rel)
        }
    }
    for rel, k in p2 {
        if (k = "del") {
            if !p1.Has(rel)
                delCloud.Push(rel)
        } else if !(p1.Has(rel) && p1[rel] = "chg") {
            downs.Push(rel)
        }
    }
    return true
}

Diff(oldM, newM, &changed, &removed) {
    changed := []
    removed := []
    for k, v in newM {
        if (!oldM.Has(k) || oldM[k] != v)
            changed.Push(k)
    }
    for k, v in oldM {
        if !newM.Has(k)
            removed.Push(k)
    }
}

SizeOf(v) {
    parts := StrSplit(v, "|")
    return parts.Length >= 2 ? parts[2] : ""
}

LoadSnap(name) {
    f := DataDir "\" name ".snap"
    if !FileExist(f)
        return ""
    m := Map()
    for line in StrSplit(FileRead(f, "UTF-8"), "`n", "`r") {
        p := InStr(line, "`t")
        if (p > 1)
            m[SubStr(line, 1, p - 1)] := SubStr(line, p + 1)
    }
    return m
}

SaveSnap(name, m) {
    f := DataDir "\" name ".snap"
    out := ""
    for k, v in m
        out .= k "`t" v "`n"
    try {
        FileDelete(f)
    }
    FileAppend(out, f, "UTF-8")
}

; ============================================================================
;  History (data)
; ============================================================================
LoadHistory() {
    if !FileExist(HistFile)
        return
    for line in StrSplit(FileRead(HistFile, "UTF-8"), "`n", "`r") {
        f := StrSplit(line, "`t")
        if (f.Length >= 5)
            History.Push(Map("ts", f[1], "folder", f[2], "ev", f[3], "rel", f[4], "size", f[5]))
    }
}

AddHistory(folder, ev, rel, size) {
    History.Push(Map("ts", A_Now, "folder", folder, "ev", ev, "rel", rel, "size", size))
}

SaveHistory() {
    global History
    ; keep the 200 most recent per folder
    counts := Map()
    kept := []
    Loop History.Length {
        h := History[History.Length - A_Index + 1]
        c := counts.Get(h["folder"], 0) + 1
        counts[h["folder"]] := c
        if (c <= 200)
            kept.InsertAt(1, h)
    }
    History := kept
    out := ""
    for h in History
        out .= h["ts"] "`t" h["folder"] "`t" h["ev"] "`t" h["rel"] "`t" h["size"] "`n"
    try {
        FileDelete(HistFile)
    }
    FileAppend(out, HistFile, "UTF-8")
}

FormatSize(b) {
    if (b = "")
        return ""
    b := Integer(b)
    if (b < 1024)
        return b " B"
    if (b < 1048576)
        return Round(b / 1024, 1) " KB"
    return Round(b / 1048576, 1) " MB"
}

; ============================================================================
;  Backups
; ============================================================================
; Automatic cleanup: after backupKeepDays, old backups and conflict copies are deleted, EXCEPT save-state
; versions (.state, .state1, .state.auto and their .png), which are only removed by hand (Games > Purge versions).
; Local folder only; the cloud one is cleaned by PruneCloudBackups (opt-in) or by hand.
PruneBackups() {
    if (KeepDays <= 0 || !DirExist(BackupDir))
        return
    cutoff := FormatTime(DateAdd(A_Now, -KeepDays, "Days"), "yyyyMMdd")
    for d in OldBackupDirs(cutoff)
        PruneDir(d, true)
}

; Opt-in (Options): the same cleanup, but on _backup/ in the cloud, with the same days and the same exception
; (save-state versions stay). Never touches the synced folders themselves. At most once a day.
; Backup folders are named by date, so the age comes from the folder name (file dates are the originals').
PruneCloudBackups() {
    global CloudListFail
    if (!CloudPrune || KeepDays <= 0 || DryRun)
        return
    stamp := DataDir "\cloudprune.txt"
    today := FormatTime(, "yyyyMMdd")
    try {
        if (FileRead(stamp) = today)
            return
    }
    CloudListFail := false
    cutoff := FormatTime(DateAdd(A_Now, -KeepDays, "Days"), "yyyyMMdd")
    root := Remote "/_backup"
    olds := []
    for nm in CloudLs(root, true) {
        for sub in CloudLs(root "/" nm, true) {
            if (sub = "conflicts" || sub = "conflictos") {
                for c in CloudLs(root "/" nm "/" sub, true)
                    AddIfOld(olds, root "/" nm "/" sub "/" c, c, cutoff)
            } else {
                AddIfOld(olds, root "/" nm "/" sub, sub, cutoff)
            }
        }
    }
    hard := (StrLower(IniRead(IniFile, "general", "cloudId", "")) = "b2") ? " --b2-hard-delete" : ""
    list := A_Temp "\syncdood_cloudprune.txt"
    for d in olds {
        del := ""
        for f in CloudLs(d, false) {
            SplitPath(f, &leaf)
            if !IsStateBackup(leaf)
                del .= f "`n"
        }
        if (del != "") {
            try {
                FileDelete(list)
            }
            try {
                FileAppend(del, list, "UTF-8-RAW")
                RunWait(Format('"{1}" delete "{2}" --files-from "{3}"{4}', Rclone, d, list, hard), , "Hide")
            }
        }
        try {
            RunWait(Format('"{1}" rmdirs "{2}"', Rclone, d), , "Hide")        ; only removes it if it ended up empty
        }
    }
    try {
        FileDelete(list)
    }
    if !CloudListFail {
        try {
            FileDelete(stamp)
        }
        try {
            FileAppend(today, stamp, "UTF-8-RAW")
        }
    }
}

; Names inside a cloud folder: its subfolders (dirsOnly) or all its files with their relative path. [] if none.
CloudLs(path, dirsOnly) {
    global CloudListFail
    tmp := A_Temp "\syncdood_cloudls.txt"
    try {
        FileDelete(tmp)
    }
    code := -1
    try {
        code := RunWait(Format('{1} /c ""{2}" lsf {3} "{4}" > "{5}""', A_ComSpec, Rclone, dirsOnly ? "--dirs-only" : "-R --files-only", path, tmp), , "Hide")
    }
    txt := ""
    try {
        txt := FileRead(tmp, "UTF-8")
    }
    try {
        FileDelete(tmp)
    }
    out := []
    if (code != 0) {
        if (code != 3)                   ; 3 = that folder doesn't exist: nothing to clean, not an error
            CloudListFail := true
        return out
    }
    for line in StrSplit(txt, "`n", "`r") {
        if (line != "")
            out.Push(dirsOnly ? RTrim(line, "/") : line)
    }
    return out
}

; Dated backup folders (day folders and conflicts\<date_time>) older than the cutoff (yyyyMMdd)
OldBackupDirs(cutoff) {
    out := []
    if !DirExist(BackupDir)
        return out
    Loop Files BackupDir "\*", "D" {
        nameDir := A_LoopFilePath
        Loop Files nameDir "\*", "D" {
            if (A_LoopFileName = "conflicts" || A_LoopFileName = "conflictos") {
                cDir := A_LoopFilePath
                Loop Files cDir "\*", "D"
                    AddIfOld(out, A_LoopFilePath, A_LoopFileName, cutoff)
            } else {
                AddIfOld(out, A_LoopFilePath, A_LoopFileName, cutoff)
            }
        }
    }
    return out
}

AddIfOld(out, dirPath, dirName, cutoff) {
    d := StrReplace(SubStr(dirName, 1, 10), "-")
    if (d ~= "^\d{8}$" && d < cutoff)
        out.Push(dirPath)
}

; Save-state copies (RetroArch .state, DuckStation .sav, PCSX2 .p2s, Dolphin .s01, Azahar .cst, PPSSPP .ppst), their screenshot, and rclone's .syncconflict variants
IsStateBackup(fileName) {
    n := RegExReplace(fileName, "i)\.+syncconflict\d*$")
    if IsObject(ParseState(n))
        return true
    if RegExMatch(n, "i)\.(png|jpg)$") {                     ; screenshot of a state
        base := RegExReplace(n, "i)\.(png|jpg)$")
        return IsObject(ParseState(base)) || IsObject(ParseState(base ".ppst"))
    }
    return false
}

; Deletes the files of a dated backup folder (keepStates = leave the save-state copies) and the folder if it ends up empty
PruneDir(dirPath, keepStates) {
    Loop Files dirPath "\*", "FR" {
        if (keepStates && IsStateBackup(A_LoopFileName))
            continue
        try {
            FileDelete(A_LoopFilePath)
        }
    }
    subs := []
    Loop Files dirPath "\*", "DR"
        subs.Push(A_LoopFilePath)
    Loop subs.Length {
        try {
            DirDelete(subs[subs.Length - A_Index + 1])        ; deepest first; only works if empty
        }
    }
    try {
        DirDelete(dirPath)
    }
}

; ============================================================================
;  Updates (GitHub releases)
; ============================================================================
; Returns Map("tag", "v0.2.1"), Map("none", true) if there are no releases, or "" on error.
FetchLatest() {
    try {
        whr := ComObject("WinHttp.WinHttpRequest.5.1")
        whr.SetTimeouts(5000, 5000, 8000, 8000)
        whr.Open("GET", "https://api.github.com/repos/" GithubRepo "/releases/latest", false)
        whr.SetRequestHeader("User-Agent", "SyncDood-updater")
        whr.SetRequestHeader("Accept", "application/vnd.github+json")
        whr.Send()
        if (whr.Status = 404)
            return Map("none", true)
        if (whr.Status = 200 && RegExMatch(whr.ResponseText, '"tag_name"\s*:\s*"([^"]+)"', &m))
            return Map("tag", m[1])
    }
    return ""
}

; true if version "a" is newer than "b" (accepts a leading "v": v0.2 > 0.1)
VerNewer(a, b) {
    pa := StrSplit(RegExReplace(a, "i)^v"), ".")
    pb := StrSplit(RegExReplace(b, "i)^v"), ".")
    Loop Max(pa.Length, pb.Length) {
        x := VerPart(pa, A_Index)
        y := VerPart(pb, A_Index)
        if (x != y)
            return (x > y)
    }
    return false
}

VerPart(arr, i) {
    if (i > arr.Length)
        return 0
    n := RegExReplace(arr[i], "\D.*$")
    return (n = "") ? 0 : Integer(n)
}

; manual = true shows a message in every case; false (startup) only speaks if there IS an update
CheckUpdates(manual := false) {
    r := FetchLatest()
    if !IsObject(r) {
        if manual
            MsgBox(T("upd_error"), "SyncDood", "Iconx")
        return
    }
    if r.Has("none") {
        if manual
            MsgBox(T("upd_noreleases"), "SyncDood", "Iconi")
        return
    }
    tag := r["tag"]
    if VerNewer(tag, AppVersion) {
        if (MsgBox(T("upd_new", tag, AppVersion), "SyncDood", "YesNo Iconi") = "Yes")
            Run("https://github.com/" GithubRepo "/releases/latest")
    } else if manual {
        MsgBox(T("upd_none", AppVersion), "SyncDood", "Iconi")
    }
}

AutoUpdateCheck() {
    today := FormatTime(, "yyyyMMdd")
    if (IniRead(IniFile, "general", "lastUpdateCheck", "") = today)
        return
    IniWrite(today, IniFile, "general", "lastUpdateCheck")
    CheckUpdates(false)
}

; ============================================================================
;  Main window  (sidebar: Status | History | Folders | Cloud | Options | About)
; ============================================================================
; Scale a design-unit number to real pixels (Move() and the Size event use raw pixels)
Px(n) {
    return Round(n * Dpi)
}

; ---------------------------------------------------------------- Colors -----
; Mixes two RRGGBB colors: t = 0 gives a, t = 1 gives b
Mix(a, b, t) {
    out := ""
    for i in [1, 3, 5] {
        x := Integer("0x" SubStr(a, i, 2))
        y := Integer("0x" SubStr(b, i, 2))
        out .= Format("{:02X}", Round(x + (y - x) * t))
    }
    return out
}

; RRGGBB -> COLORREF (0x00BBGGRR)
BGR(hex) {
    r := Integer("0x" SubStr(hex, 1, 2))
    g := Integer("0x" SubStr(hex, 3, 2))
    b := Integer("0x" SubStr(hex, 5, 2))
    return (b << 16) | (g << 8) | r
}

WindowsDark() {
    try {
        return (RegRead("HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize", "AppsUseLightTheme") = 0)
    }
    return false
}

IsDark() {
    if (ThemePref = "dark")
        return true
    if (ThemePref = "light")
        return false
    return WindowsDark()
}

; Fills TH with the light or dark palette (decided by the "theme" option / Windows)
LoadTheme() {
    global DarkNow
    DarkNow := IsDark()
    if DarkNow {
        c := Map("bg", "141923", "card", "1C2330", "border", "2B3445", "text", "E7EBF3", "sub", "93A0B8"
            , "side", "0D111A", "sideText", "9FB0CC", "sideHov", "171F2E", "sideSel", "1F2B44"
            , "accent", "4F8CFF", "accentHov", "6FA1FF", "btn", "2A3447", "btnHov", "36435C"
            , "ok", "3DD68C", "warn", "F5B83D", "err", "FF6B6B", "info", "8794AB", "down", "35C7D6"
            , "lvBg", "141923", "editBg", "0F141D", "track", "2B3445"
            , "bn_ok", "17603E", "bn_sync", "1B4B8F", "bn_warn", "8F5E0C", "bn_err", "8A2233")
    } else {
        c := Map("bg", "F2F4F8", "card", "FFFFFF", "border", "DCE1EA", "text", "1B2433", "sub", "667085"
            , "side", "14213D", "sideText", "AEBBD3", "sideHov", "1C2D55", "sideSel", "27407A"
            , "accent", "2F6BEB", "accentHov", "2557C2", "btn", "E3E8F1", "btnHov", "D3DAE8"
            , "ok", "1C9B57", "warn", "C27803", "err", "D13B3B", "info", "7D8799", "down", "0E8FA0"
            , "lvBg", "F2F4F8", "editBg", "FFFFFF", "track", "DCE1EA"
            , "bn_ok", "1E7B4F", "bn_sync", "2154A3", "bn_warn", "B4690E", "bn_err", "A32638")
    }
    TH.Clear()
    for k, v in c
        TH[k] := v
}

HasFont(name) {
    for hive in ["HKLM", "HKCU"] {
        try {
            RegRead(hive "\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts", name " (TrueType)")
            return true
        }
    }
    return false
}

; ------------------------------------------------------- Control helpers -----
; Text with its own font / color / background (all given explicitly so it can be recolored later)
AddTxt(g, arr, opts, text, spec, color, bg) {
    g.SetFont(spec " c" color, "Segoe UI")
    c := g.Add("Text", opts " Background" bg, text)
    FS[c.Hwnd] := [spec, "Segoe UI"]
    if IsObject(arr)
        arr.Push(c)
    return c
}

; Changes the text color of a control created with AddTxt / AddBtn
Recolor(c, color) {
    f := FS.Get(c.Hwnd, ["s9 norm", "Segoe UI"])
    c.SetFont(f[1] " c" color, f[2])
}

; [background, hover background, text color] of each button kind
BtnColors(kind) {
    switch kind {
        case "prim", "segon":
            return [TH["accent"], TH["accentHov"], "FFFFFF"]
        case "ban":
            return ["FFFFFF", "E6ECF7", "1B2433"]
        case "ban2":
            return [Mix(BannerCol, "FFFFFF", 0.20), Mix(BannerCol, "FFFFFF", 0.32), "FFFFFF"]
        case "danger":
            return [TH["btn"], TH["btnHov"], TH["err"]]
    }
    return [TH["btn"], TH["btnHov"], TH["text"]]
}

; Flat button made from a Text control: it looks identical in light and dark mode.
AddBtn(g, arr, x, y, w, h, label, fn, kind := "norm", spec := "s9 norm") {
    col := BtnColors(kind)
    g.SetFont(spec " c" col[3], "Segoe UI")
    c := g.Add("Text", Format("x{1} y{2} w{3} h{4} +0x100 +0x200 Center Background{5}", x, y, w, h, col[1]), label)
    FS[c.Hwnd] := [spec, "Segoe UI"]
    c.OnEvent("Click", fn)
    Hov[c.Hwnd] := Map("ctrls", [c], "bg", col[1], "hv", col[2], "kind", kind)
    if IsObject(arr)
        arr.Push(c)
    return c
}

; Re-styles a button (e.g. selected / not selected)
SetBtnKind(c, kind) {
    col := BtnColors(kind)
    info := Hov[c.Hwnd]
    info["bg"] := col[1]
    info["hv"] := col[2]
    info["kind"] := kind
    c.Opt("Background" col[1])
    Recolor(c, col[3])
    c.Redraw()
}

; Single-line text box with the current theme
AddEdit(g, arr, x, y, w, text, extra := "") {
    g.SetFont("s9 norm c" TH["text"], "Segoe UI")
    opt := Format("x{1} y{2} w{3} c{4} Background{5} {6}", x, y, w, TH["text"], TH["editBg"], extra)
    if !RegExMatch(extra, "i)\br\d")
        opt .= " r1"
    if DarkNow
        opt .= " -E0x200 +Border"
    c := g.Add("Edit", opt, text)
    if IsObject(arr)
        arr.Push(c)
    return c
}

; Row of exclusive options. Returns Map("sel", n, "btns", [...])
AddSeg(g, arr, x, y, labels, sel, bw := 92) {
    seg := Map("sel", sel, "btns", [])
    for i, lb in labels {
        c := AddBtn(g, arr, x + (i - 1) * (bw + 4), y, bw, 28, lb, SegClick.Bind(seg, i), (i = sel) ? "segon" : "norm")
        seg["btns"].Push(c)
    }
    return seg
}

SegClick(seg, i, *) {
    seg["sel"] := i
    for n, c in seg["btns"]
        SetBtnKind(c, (n = i) ? "segon" : "norm")
}

; On/off switch with a label. Returns Map("on", bool, ...)
AddToggle(g, arr, x, y, w, label, on) {
    t := Map("on", on ? true : false)
    g.SetFont("s10 norm cFFFFFF", "Wingdings")
    t["box"] := g.Add("Text", Format("x{1} y{2} w22 h22 +0x100 +0x200 Center Background{3}", x, y, on ? TH["accent"] : TH["btn"]), on ? Chr(0xFC) : "")
    t["lbl"] := AddTxt(g, arr, Format("x{1} y{2} w{3} h22 +0x100 +0x200", x + 32, y, w - 32), label, "s9 norm", TH["text"], TH["bg"])
    if IsObject(arr)
        arr.Push(t["box"])
    t["box"].OnEvent("Click", ToggleClick.Bind(t))
    t["lbl"].OnEvent("Click", ToggleClick.Bind(t))
    return t
}

ToggleClick(t, *) {
    t["on"] := !t["on"]
    t["box"].Opt("Background" (t["on"] ? TH["accent"] : TH["btn"]))
    t["box"].Text := t["on"] ? Chr(0xFC) : ""
    t["box"].Redraw()
}

SetToggle(t, on) {
    t["on"] := on ? true : false
    t["box"].Opt("Background" (t["on"] ? TH["accent"] : TH["btn"]))
    t["box"].Text := t["on"] ? Chr(0xFC) : ""
}

; ---------------------------------------------------------------- Hover -----
OnMouseMove(wParam, lParam, msg, hwnd) {
    global HovCur
    ctl := 0
    try {
        MouseGetPos(, , , &ctl, 2)
    }
    if (ctl = HovCur)
        return
    HoverOut()
    if (ctl != 0 && Hov.Has(ctl)) {
        HovCur := ctl
        for c in Hov[ctl]["ctrls"] {
            c.Opt("Background" Hov[ctl]["hv"])
            c.Redraw()
        }
        SetTimer(HoverPoll, 100)
    }
}

HoverOut() {
    global HovCur
    if (HovCur = 0)
        return
    if Hov.Has(HovCur) {
        info := Hov[HovCur]
        try {
            for c in info["ctrls"] {
                c.Opt("Background" info["bg"])
                c.Redraw()
            }
        }
    }
    HovCur := 0
}

HoverPoll() {
    ctl := 0
    try {
        MouseGetPos(, , , &ctl, 2)
    }
    if (ctl != HovCur) {
        HoverOut()
        SetTimer(HoverPoll, 0)
    }
}

; ---------------------------------------------------------------- Window -----
ShowMain(page := 0) {
    if !IsObject(MainGui)
        BuildMain()
    ShowPage(page > 0 ? page : CurPage)
    RefreshHistory()
    UpdateHeader()
    MainGui.Show()
}

BuildMain() {
    global MainGui, MainBuilt, HistLV, FolderLV, GamesLV, ConfLV, IconFont, BannerCol, HoverHooked, Dpi, BaseW, BaseH
    MainBuilt := false
    LoadTheme()
    UI.Clear()
    Hov.Clear()
    FS.Clear()
    OptC.Clear()
    Nav.Length := 0
    PgCtrls.Length := 0
    BannerCol := TH["bn_sync"]
    IconFont := HasFont("Segoe MDL2 Assets") ? "Segoe MDL2 Assets" : ""

    g := Gui("+Resize +MinSize" Px(900) "x" Px(620), "SyncDood")
    g.BackColor := TH["bg"]
    g.MarginX := 0
    g.MarginY := 0
    g.SetFont("s9 norm c" TH["text"], "Segoe UI")
    MainGui := g

    ; ---- sidebar
    UI["side"] := g.Add("Text", Format("x0 y0 w{1} h{2} Background{3}", SW, H0, TH["side"]), "")
    ; Real scale of this window: the sidebar was asked to be SW design units wide. Everything that is moved later
    ; (Px) uses this, not A_ScreenDPI, which can differ (laptop screen vs external 4K monitor).
    try {
        UI["side"].GetPos(, , &sideRaw)
        if (sideRaw > 0)
            Dpi := sideRaw / SW
    }
    g.Opt("+MinSize" Px(900) "x" Px(620))
    logo := PicPath("ok")
    if (logo != "") {
        try {
            g.Add("Picture", "x18 y20 w36 h36 BackgroundTrans", logo)
        }
    }
    AddTxt(g, "", "x64 y20 w130 h36 +0x200", "SyncDood", "s14 bold", "FFFFFF", TH["side"])
    labels := [T("tab_status"), T("tab_history"), T("tab_conflicts"), T("tab_games"), T("tab_folders"), T("tab_cloud"), T("tab_options"), T("tab_about")]
    icons := [Chr(0xE80F), Chr(0xE81C), Chr(0xE7BA), Chr(0xE7FC), Chr(0xE8B7), Chr(0xE753), Chr(0xE713), Chr(0xE946)]
    for i, lb in labels
        AddNav(g, i, 88 + (i - 1) * 46, (IconFont != "") ? icons[i] : "", lb)
    UI["navBar"] := g.Add("Text", Format("x0 y95 w4 h26 Background{1}", TH["accent"]), "")
    UI["sideDot"] := AddTxt(g, "", Format("x20 y{1} w18 h24 +0x200", H0 - 62), "●", "s10 norm", TH["info"], TH["side"])
    UI["sideTxt"] := AddTxt(g, "", Format("x40 y{1} w{2} h24 +0x200", H0 - 62, SW - 50), "", "s9 norm", TH["sideText"], TH["side"])
    UI["sideVer"] := AddTxt(g, "", Format("x20 y{1} w{2} h20 +0x200", H0 - 36, SW - 30), T("ab_version", AppVersion), "s8 norm", Mix(TH["sideText"], TH["side"], 0.45), TH["side"])

    ; ---- pages
    Loop 8
        PgCtrls.Push([])
    BuildStatusPage(g, PgCtrls[1])
    BuildHistoryPage(g, PgCtrls[2])
    BuildConflictsPage(g, PgCtrls[PG_CONF])
    BuildGamesPage(g, PgCtrls[PG_GAMES])
    BuildFoldersPage(g, PgCtrls[PG_FOLDERS])
    BuildCloudPage(g, PgCtrls[PG_CLOUD])
    BuildOptionsPage(g, PgCtrls[PG_OPT])
    BuildAboutPage(g, PgCtrls[PG_ABOUT])

    LoadOptionsIntoUI()
    FillFolders()
    FillCloud()

    ; modern look for the lists (dark scrollbars in dark mode)
    for lv in [HistLV, FolderLV, GamesLV, ConfLV]
        DllCall("uxtheme\SetWindowTheme", "Ptr", lv.Hwnd, "Str", DarkNow ? "DarkMode_Explorer" : "Explorer", "Ptr", 0)
    HistLV.OnNotify(-12, HistDraw)
    ConfLV.OnNotify(-12, ConfDraw)

    try {
        DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", g.Hwnd, "Int", 20, "Int*", DarkNow ? 1 : 0, "Int", 4)   ; dark title bar
        DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", g.Hwnd, "Int", 35, "Int*", BGR(TH["side"]), "Int", 4)   ; title bar color
        DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", g.Hwnd, "Int", 36, "Int*", 0xFFFFFF, "Int", 4)          ; title text
    }

    if !HoverHooked {
        OnMessage(0x200, OnMouseMove)      ; WM_MOUSEMOVE: hover colors for the flat buttons
        HoverHooked := true
    }
    g.OnEvent("Size", OnMainSize)
    g.OnEvent("Close", (gobj) => gobj.Hide())
    g.Show("w" W0 " h" H0 " Hide")
    BaseW := Px(W0), BaseH := Px(H0)
    try {
        g.GetClientPos(, , &BaseW, &BaseH)
    }
    MainBuilt := true
}

; Rebuilds the window with the current theme (Windows switched between light and dark)
RebuildMain() {
    global MainGui, MainBuilt
    if !IsObject(MainGui)
        return
    wasVisible := DllCall("IsWindowVisible", "Ptr", MainGui.Hwnd)
    page := CurPage
    MainBuilt := false
    try {
        MainGui.Destroy()
    }
    MainGui := ""
    BuildMain()
    ShowPage(page)
    RefreshHistory()
    UpdateHeader()
    if wasVisible
        MainGui.Show()
}

OnDpiChanged(wParam, lParam, msg, hwnd) {
    if (IsObject(MainGui) && MainBuilt && hwnd = MainGui.Hwnd)
        SetTimer(RebuildMain, -400)
}

OnSettingChange(wParam, lParam, msg, hwnd) {
    ; Windows changed its theme: if we follow it, rebuild the window
    if (ThemePref = "auto" && IsObject(MainGui) && MainBuilt && (IsDark() != DarkNow))
        SetTimer(RebuildMain, -300)
}

AddNav(g, i, y, icon, label) {
    bg := TH["side"]
    fnt := (IconFont != "") ? IconFont : "Segoe UI"
    strip := g.Add("Text", Format("x8 y{1} w{2} h40 +0x100 Background{3}", y, SW - 16, bg), "")
    g.SetFont("s12 norm c" TH["sideText"], fnt)
    ico := g.Add("Text", Format("x20 y{1} w32 h40 +0x100 +0x200 Center Background{2}", y, bg), icon)
    FS[ico.Hwnd] := ["s12 norm", fnt]
    lbl := AddTxt(g, "", Format("x58 y{1} w{2} h40 +0x100 +0x200", y, SW - 70), label, "s10 norm", TH["sideText"], bg)
    ctrls := [strip, ico, lbl]
    if (i = PG_CONF) {
        ; "⚠ 2": number of conflicts to review (empty when there are none)
        badge := AddTxt(g, "", Format("x{1} y{2} w58 h40 +0x100 +0x200 Right", SW - 74, y), "", "s9 bold", TH["warn"], bg)
        ctrls.Push(badge)
        UI["navBadge"] := badge
    }
    info := Map("ctrls", ctrls, "bg", bg, "hv", TH["sideHov"], "kind", "nav")
    for c in info["ctrls"] {
        Hov[c.Hwnd] := info
        c.OnEvent("Click", NavClick.Bind(i))
    }
    Nav.Push(Map("ico", ico, "lbl", lbl, "info", info))
}

NavClick(i, *) {
    ShowPage(i)
}

SetNav(sel) {
    for i, n in Nav {
        on := (i = sel)
        bg := on ? TH["sideSel"] : TH["side"]
        n["info"]["bg"] := bg
        n["info"]["hv"] := on ? TH["sideSel"] : TH["sideHov"]
        for c in n["info"]["ctrls"]
            c.Opt("Background" bg)
        Recolor(n["ico"], on ? TH["accentHov"] : TH["sideText"])
        Recolor(n["lbl"], on ? "FFFFFF" : TH["sideText"])
        for c in n["info"]["ctrls"]
            c.Redraw()
    }
    try {
        Nav[sel]["info"]["ctrls"][1].GetPos(, &sy, , &sh)
        UI["navBar"].GetPos(, , , &bh)
        UI["navBar"].Move(, sy + (sh - bh) // 2)
    }
}

ShowPage(i) {
    global CurPage
    CurPage := i
    for idx, arr in PgCtrls {
        for c in arr
            c.Visible := (idx = i)
    }
    SetNav(i)
    UpdateHeader()
    if (i = PG_HIST)
        RefreshHistory()
    if (i = PG_CONF)
        RefreshConflicts()
    if (i = PG_GAMES)
        RefreshGames()
    else
        UI["gEmpty"].Visible := false
}

; ---------------------------------------------------------- Page: Status -----
BuildStatusPage(g, arr) {
    x := CX
    w := CW0
    ; banner: its color follows the state (blue syncing, green ok, amber conflict, red error)
    UI["banner"] := g.Add("Text", Format("x{1} y24 w{2} h120 Background{3}", x, w, BannerCol), "")
    arr.Push(UI["banner"])
    UI["bIco"] := g.Add("Picture", Format("x{1} y44 w80 h80 BackgroundTrans", x + 20), "")
    arr.Push(UI["bIco"])
    UI["bTitle"] := AddTxt(g, arr, Format("x{1} y40 w{2} h36 +0x200", x + 118, w - 118 - 204), "", "s18 bold", "FFFFFF", BannerCol)
    UI["bSub"] := AddTxt(g, arr, Format("x{1} y80 w{2} h40", x + 120, w - 120 - 204), "", "s10 norm", "FFFFFF", BannerCol)
    UI["bBtn1"] := AddBtn(g, arr, x + w - 188, 38, 172, 38, T("btn_sync_now"), MenuSyncNow, "ban", "s10 bold")
    UI["bBtn2"] := AddBtn(g, arr, x + w - 188, 86, 172, 32, T("btn_details"), ShowDetails, "ban2")

    ; one line under the banner: progress / pause notice / next check
    UI["infoTxt"] := AddTxt(g, arr, Format("x{1} y158 w{2} h22 +0x200", x, w - 200), "", "s9 norm", TH["sub"], TH["bg"])
    UI["bPause"] := AddBtn(g, arr, x + w - 190, 152, 190, 28, T("btn_pause"), PauseButton)
    UI["pauseKind"] := "norm"
    UI["barTrack"] := g.Add("Text", Format("x{1} y184 w{2} h4 Background{3}", x, w, TH["track"]), "")
    UI["barFill"] := g.Add("Text", Format("x{1} y184 w120 h4 Background{2}", x, TH["accent"]), "")
    arr.Push(UI["barTrack"], UI["barFill"])

    ; folders
    AddTxt(g, arr, Format("x{1} y206 w300 h24 +0x200", x), T("tab_folders"), "s11 bold", TH["text"], TH["bg"])
    UI["stCloud"] := AddTxt(g, arr, Format("x{1} y206 w{2} h24 +0x200 +0x2", x + w - 440, 440), "", "s9 norm", TH["sub"], TH["bg"])
    UI["rows"] := []
    y := 236
    n := 0
    for name, path in Folders {
        n += 1
        if (n > 4)
            break
        r := Map("name", name, "key", "")
        r["card"] := g.Add("Text", Format("x{1} y{2} w{3} h54 Background{4}", x, y, w, TH["card"]), "")
        arr.Push(r["card"])
        r["dot"] := AddTxt(g, arr, Format("x{1} y{2} w22 h54 +0x200 Center", x + 12, y), "●", "s14 norm", TH["info"], TH["card"])
        r["lbl"] := AddTxt(g, arr, Format("x{1} y{2} w240 h22 +0x200", x + 44, y + 7), name, "s10 bold", TH["text"], TH["card"])
        r["path"] := AddTxt(g, arr, Format("x{1} y{2} w{3} h18 +0x4000", x + 44, y + 29, w - 44 - 452), path, "s8 norm", TH["sub"], TH["card"])
        r["stat"] := AddTxt(g, arr, Format("x{1} y{2} w300 h54 +0x200 +0x4000 Right", x + w - 432, y), "", "s9 norm", TH["sub"], TH["card"])
        r["btn"] := AddBtn(g, arr, x + w - 124, y + 12, 112, 30, T("st_sync_folder"), RowSync.Bind(r))
        UI["rows"].Push(r)
        y += 60
    }
    UI["fSum"] := ""
    if (Folders.Count > 4) {
        ; many folders: the 4 that need attention first, and a one-line summary that opens the full list
        UI["fSum"] := AddTxt(g, arr, Format("x{1} y{2} w{3} h22 +0x100 +0x200", x, y - 4, w), "", "s9 bold", TH["accent"], TH["bg"])
        UI["fSum"].OnEvent("Click", (*) => ShowPage(PG_FOLDERS))
        y += 24
    }

    ; recent activity
    y += 8
    AddTxt(g, arr, Format("x{1} y{2} w300 h24 +0x200", x, y), T("st_recent"), "s11 bold", TH["text"], TH["bg"])
    y += 34
    UI["act"] := []
    Loop 4 {
        a := Map()
        a["ts"] := AddTxt(g, arr, Format("x{1} y{2} w100 h24 +0x200", x + 4, y), "", "s9 norm", TH["sub"], TH["bg"])
        a["ev"] := AddTxt(g, arr, Format("x{1} y{2} w210 h24 +0x200", x + 108, y), "", "s9 norm", TH["text"], TH["bg"])
        a["file"] := AddTxt(g, arr, Format("x{1} y{2} w{3} h24 +0x200 +0x4000", x + 326, y, w - 326), "", "s9 norm", TH["text"], TH["bg"])
        UI["act"].Push(a)
        y += 26
    }
    UI["actEmpty"] := AddTxt(g, arr, Format("x{1} y{2} w{3} h24 +0x200", x + 4, y - 26 * 4, w - 8), T("st_none"), "s9 norm", TH["sub"], TH["bg"])
    link := AddTxt(g, arr, Format("x{1} y{2} w300 h24 +0x100 +0x200", x + 4, y + 4), T("st_all_history"), "s9 bold", TH["accent"], TH["bg"])
    link.OnEvent("Click", (*) => ShowPage(PG_HIST))
}

SyncOne(name, *) {
    if Syncing
        return
    RunSync(T("reason_manual"), false, name)
}

; "Sync" button of a row on the Status page (the row shows whichever folder is in it right now)
RowSync(r, *) {
    SyncOne(r["name"])
}

; 0 = needs attention most ... 4 = nothing special
FolderPriority(nm) {
    fs := FState.Get(nm, "")
    if !IsObject(fs)
        return 4
    switch fs["st"] {
        case "error":
            return 0
        case "conflict":
            return 1
        case "syncing":
            return 2
        case "pending":
            return 3
    }
    return 4
}

; --------------------------------------------------------- Page: History -----
BuildHistoryPage(g, arr) {
    global HistLV
    AddTxt(g, arr, Format("x{1} y22 w{2} h40 +0x200", CX, CW0), T("tab_history"), "s18 bold", TH["text"], TH["bg"])
    UI["chips"] := []
    xp := CX
    limit := CX + CW0 - 160          ; keep room for the "More" button
    over := []                       ; folders that do not fit: they go in the "More" menu
    names := [""]
    for name in Folders
        names.Push(name)
    for nm in names {
        lbl := (nm = "") ? T("hist_all") : nm
        bw := Min(170, Max(72, 32 + StrLen(lbl) * 8))
        if (nm != "" && (over.Length > 0 || xp + bw > limit)) {
            over.Push(nm)
            continue
        }
        c := AddBtn(g, arr, xp, 74, bw, 28, lbl, ChipClick.Bind(nm), (nm = HistFilterName) ? "segon" : "norm")
        UI["chips"].Push(Map("ctrl", c, "name", nm))
        xp += bw + 8
    }
    UI["moreNames"] := over
    if (over.Length > 0)
        UI["moreBtn"] := AddBtn(g, arr, xp, 74, 150, 28, MoreLabel(), ShowMoreMenu, HasItem(over, HistFilterName) ? "segon" : "norm")
    ; column titles (positions are set in LayoutHist)
    UI["hCols"] := []
    for lb in [T("col_date"), T("col_folder"), T("col_event"), T("col_file"), T("col_size")]
        UI["hCols"].Push(AddTxt(g, arr, Format("x{1} y118 w100 h20 +0x200", CX), lb, "s9 bold", TH["sub"], TH["bg"]))
    UI["hCols"][5].Opt("+0x2")
    UI["hLine"] := g.Add("Text", Format("x{1} y140 w{2} h1 Background{3}", CX, CW0 + 28, TH["border"]), "")
    arr.Push(UI["hLine"])
    g.SetFont("s9 norm c" TH["text"], "Segoe UI")
    HistLV := g.Add("ListView", Format("x{1} y144 w{2} h{3} -Hdr -Multi +LV0x10000 -E0x200 c{4} Background{5}"
        , CX, CW0 + 28, H0 - 144, TH["text"], TH["lvBg"])
        , [T("col_date"), T("col_folder"), T("col_event"), T("col_file"), T("col_size")])
    arr.Push(HistLV)
    UI["histEmpty"] := AddTxt(g, arr, Format("x{1} y{2} w{3} h28 +0x200 Center", CX, 170, CW0), T("st_none"), "s10 norm", TH["sub"], TH["lvBg"])
    LayoutHist(Px(CW0 + 28))
}

; Column widths (design units) of the history list; the file column takes what is left
LayoutHist(wRaw) {
    wd := wRaw / Dpi
    cols := [112, 100, 200, 0, 84]
    cols[4] := Max(120, wd - 112 - 100 - 200 - 84 - 24)
    x := 0
    for i, cw in cols {
        HistLV.ModifyCol(i, Px(cw) (i = 5 ? " Right" : ""))
        lab := UI["hCols"][i]
        if (i = 5)
            lab.Move(Px(CX) + Px(x), , Px(cw) - Px(6))
        else
            lab.Move(Px(CX) + Px(x) + Px(6), , Px(cw) - Px(8))
        x += cw
    }
}

ChipClick(nm, *) {
    global HistFilterName
    HistFilterName := nm
    for ch in UI["chips"]
        SetBtnKind(ch["ctrl"], (ch["name"] = nm) ? "segon" : "norm")
    if UI.Has("moreBtn") {
        SetBtnKind(UI["moreBtn"], HasItem(UI["moreNames"], nm) ? "segon" : "norm")
        UI["moreBtn"].Text := MoreLabel()
    }
    RefreshHistory()
}

; Label of the "More" button: the chosen folder if it is one of the hidden ones, else how many there are
MoreLabel() {
    if (HistFilterName != "" && HasItem(UI["moreNames"], HistFilterName))
        return HistFilterName
    return T("hist_more", UI["moreNames"].Length)
}

; Menu with the folders that did not fit as buttons
ShowMoreMenu(*) {
    m := Menu()
    for nm in UI["moreNames"]
        m.Add(StrReplace(nm, "&", "&&"), ChipClick.Bind(nm))
    m.Show()
}

; Colors the "event" column of the history list by type
HistDraw(ctrl, lParam) {
    static CDDS_PREPAINT := 0x1, CDDS_ITEMPREPAINT := 0x10001, CDDS_SUBITEM := 0x30001
    p := A_PtrSize
    stage := NumGet(lParam, 3 * p, "UInt")
    if (stage = CDDS_PREPAINT || stage = CDDS_ITEMPREPAINT)
        return 0x20                                   ; CDRF_NOTIFYITEMDRAW / CDRF_NOTIFYSUBITEMDRAW
    if (stage = CDDS_SUBITEM) {
        offSpec := (p = 8) ? 56 : 36
        offClr := (p = 8) ? 80 : 48
        row := NumGet(lParam, offSpec, "Ptr") + 1
        sub := NumGet(lParam, offClr + 8, "Int")      ; 0-based column
        col := TH["text"]
        if (sub = 2 && row <= HistKeys.Length)
            col := EvColor(HistKeys[row])
        else if (sub = 0 || sub = 4 || sub = 1)
            col := (sub = 0 || sub = 4) ? TH["sub"] : TH["text"]
        NumPut("UInt", BGR(col), lParam, offClr)
        return 0x2                                    ; CDRF_NEWFONT
    }
    return 0
}

EvColor(ev) {
    switch ev {
        case "up":
            return TH["ok"]
        case "down":
            return TH["down"]
        case "conflict":
            return TH["warn"]
        case "fail":
            return TH["err"]
        case "del_here", "del_cloud":
            return TH["sub"]
    }
    return TH["info"]
}

; ========================================================= Page: Conflicts ===
; When the same file changes on two PCs, the sync keeps the newest copy and saves the other one in the backups.
; This page lists those cases so you can compare both versions and, only if you want to, bring the other one back.
; Nothing here interrupts you: a ⚠ with a number next to the tab and an amber tray icon are the only notice.
BuildConflictsPage(g, arr) {
    global ConfLV
    x := CX
    cw := 356                                   ; width of each version card
    AddTxt(g, arr, Format("x{1} y22 w{2} h40 +0x200", x, CW0 - 220), T("tab_conflicts"), "s18 bold", TH["text"], TH["bg"])
    UI["cfAll"] := AddBtn(g, arr, x + CW0 - 200, 28, 200, 30, T("cf_all"), ConfMarkAll)
    AddTxt(g, arr, Format("x{1} y66 w{2} h40", x, CW0), T("cf_help"), "s9 norm", TH["sub"], TH["bg"])

    g.SetFont("s9 norm c" TH["text"], "Segoe UI")
    ConfLV := g.Add("ListView", Format("x{1} y114 w{2} h170 -Multi +LV0x10000 -E0x200 c{3} Background{4}"
        , x, CW0 + 28, TH["text"], TH["lvBg"])
        , [T("col_date"), T("col_folder"), T("col_file"), T("cf_col_state")])
    arr.Push(ConfLV)
    ConfLV.OnEvent("ItemSelect", ConfSelect)
    UI["cfEmpty"] := AddTxt(g, arr, Format("x{1} y{2} w{3} h28 +0x200 Center", x, 190, CW0), T("cf_none"), "s10 norm", TH["sub"], TH["lvBg"])
    LayoutConf(Px(CW0 + 28))

    ; the file being looked at, and the two versions side by side
    UI["cfFile"] := AddTxt(g, arr, Format("x{1} y294 w{2} h26 +0x200 +0x4000", x, CW0), "", "s10 bold", TH["text"], TH["bg"])
    UI["cfDetail"] := [UI["cfFile"]]
    UI["cfSides"] := []
    Loop 2 {
        n := A_Index
        x0 := x + (n - 1) * (cw + 12)
        d := Map("x0", x0)
        d["card"] := g.Add("Text", Format("x{1} y326 w{2} h166 Background{3}", x0, cw, TH["card"]), "")
        arr.Push(d["card"])
        d["title"] := AddTxt(g, arr, Format("x{1} y334 w{2} h26 +0x200", x0 + 12, cw - 24), T(n = 1 ? "cf_cur" : "cf_oth"), "s10 bold", TH["text"], TH["card"])
        d["box"] := g.Add("Text", Format("x{1} y368 w152 h114 Background{2}", x0 + 12, TH["lvBg"]), "")
        arr.Push(d["box"])
        d["pic"] := g.Add("Picture", Format("x{1} y368 w10 h10 BackgroundTrans", x0 + 12), "")
        arr.Push(d["pic"])
        d["noPic"] := AddTxt(g, arr, Format("x{1} y404 w152 h44 Center", x0 + 12), T("v_nopreview"), "s8 norm", TH["sub"], TH["lvBg"])
        d["size"] := AddTxt(g, arr, Format("x{1} y368 w{2} h22 +0x200", x0 + 176, cw - 188), "", "s9 norm", TH["text"], TH["card"])
        d["date"] := AddTxt(g, arr, Format("x{1} y392 w{2} h22 +0x200", x0 + 176, cw - 188), "", "s9 norm", TH["text"], TH["card"])
        d["from"] := AddTxt(g, arr, Format("x{1} y416 w{2} h22 +0x200 +0x4000", x0 + 176, cw - 188), "", "s9 norm", TH["sub"], TH["card"])
        d["tag"] := AddTxt(g, arr, Format("x{1} y446 w{2} h22 +0x200", x0 + 176, cw - 188), "", "s9 bold", TH["sub"], TH["card"])
        UI["cfSides"].Push(d)
        UI["cfDetail"].Push(d["card"], d["title"], d["box"], d["size"], d["date"], d["from"], d["tag"])
    }
    UI["cfHint"] := AddTxt(g, arr, Format("x{1} y380 w{2} h40 +0x200 Center", x, CW0), T("cf_pick"), "s10 norm", TH["sub"], TH["bg"])
    UI["cfShotCur"] := ""
    UI["cfShotOth"] := ""

    UI["cfKeep"] := AddBtn(g, arr, x, 506, 220, 36, T("cf_keep"), ConfKeep, "prim")
    UI["cfUse"] := AddBtn(g, arr, x + 228, 506, 220, 36, T("cf_use"), ConfUse)
    UI["cfCmp"] := AddBtn(g, arr, x + 456, 506, 240, 36, T("cf_compare"), ConfCompare)
    AddTxt(g, arr, Format("x{1} y556 w{2} h40", x, CW0), T("cf_foot"), "s8 norm", TH["sub"], TH["bg"])
}

; Column widths (design units); the file column takes what is left
LayoutConf(wRaw) {
    wd := wRaw / Dpi
    ConfLV.ModifyCol(1, Px(112))
    ConfLV.ModifyCol(2, Px(130))
    ConfLV.ModifyCol(4, Px(190))
    ConfLV.ModifyCol(3, Px(Max(120, wd - 112 - 130 - 190 - 24)))
}

; Colors of the list: the "to review" status in amber, dates dimmed
ConfDraw(ctrl, lParam) {
    static CDDS_PREPAINT := 0x1, CDDS_ITEMPREPAINT := 0x10001, CDDS_SUBITEM := 0x30001
    p := A_PtrSize
    stage := NumGet(lParam, 3 * p, "UInt")
    if (stage = CDDS_PREPAINT || stage = CDDS_ITEMPREPAINT)
        return 0x20
    if (stage = CDDS_SUBITEM) {
        offSpec := (p = 8) ? 56 : 36
        offClr := (p = 8) ? 80 : 48
        row := NumGet(lParam, offSpec, "Ptr") + 1
        sub := NumGet(lParam, offClr + 8, "Int")
        col := TH["text"]
        if (row <= ConfRows.Length) {
            if (sub = 0)
                col := TH["sub"]
            else if (sub = 3)
                col := (ConfRows[row]["status"] = "pending") ? TH["warn"] : TH["sub"]
        }
        NumPut("UInt", BGR(col), lParam, offClr)
        return 0x2
    }
    return 0
}

ConfSelect(*) {
    ConfShowSel()
}

; The notice the list has selected ("" if none)
ConfSel() {
    if !IsObject(ConfLV)
        return ""
    r := ConfLV.GetNext(0)
    return (r >= 1 && r <= ConfRows.Length) ? ConfRows[r] : ""
}

ConfStatusText(c) {
    switch c["status"] {
        case "pending":
            return T("cf_pending")
        case "swapped":
            return T("cf_swapped")
    }
    return T("cf_kept")
}

; Rebuilds the list (to review first, then the ones already resolved) and the ⚠ number next to the tab
RefreshConflicts() {
    global ConfRows
    CleanConflicts()
    ConfRows := []
    Loop Conflicts.Length {
        c := Conflicts[Conflicts.Length - A_Index + 1]
        if (c["status"] = "pending")
            ConfRows.Push(c)
    }
    Loop Conflicts.Length {
        c := Conflicts[Conflicts.Length - A_Index + 1]
        if (c["status"] != "pending")
            ConfRows.Push(c)
    }
    UpdateConfBadge()
    if (!MainBuilt || !IsObject(MainGui) || CurPage != PG_CONF)
        return
    prev := ConfSel()
    ConfLV.Opt("-Redraw")
    ConfLV.Delete()
    for c in ConfRows
        ConfLV.Add(, FormatTime(c["ts"], T("fmt_date")), c["folder"], c["rel"], ConfStatusText(c))
    ConfLV.Opt("+Redraw")
    UI["cfEmpty"].Visible := (ConfRows.Length = 0)
    if (ConfRows.Length > 0) {
        idx := 1
        if IsObject(prev) {
            for i, c in ConfRows {
                if (ObjPtr(c) = ObjPtr(prev))
                    idx := i
            }
        }
        ConfLV.Modify(idx, "Select Focus Vis")
    }
    ConfShowSel()
}

; "⚠ 2" at the right of the Conflicts tab; empty when there is nothing to review
UpdateConfBadge() {
    if (!IsObject(MainGui) || !UI.Has("navBadge"))
        return
    n := PendingConflicts()
    txt := (n > 0) ? "⚠ " n : ""
    if (UI["navBadge"].Text != txt)
        UI["navBadge"].Text := txt
}

; Shows both versions of the selected notice
ConfShowSel() {
    if (!MainBuilt || CurPage != PG_CONF)
        return
    c := ConfSel()
    on := IsObject(c)
    for ctl in UI["cfDetail"]
        ctl.Visible := on
    UI["cfHint"].Visible := !on
    pend := (on && c["status"] = "pending")
    UI["cfKeep"].Visible := pend
    UI["cfUse"].Visible := pend
    UI["cfAll"].Visible := (PendingConflicts() > 1)
    sides := UI["cfSides"]
    if !on {
        for d in sides {
            d["pic"].Visible := false
            d["noPic"].Visible := false
        }
        UI["cfCmp"].Visible := false
        return
    }
    folder := c["folder"], rel := c["rel"]
    fdir := Folders.Get(folder, "")
    curP := (fdir != "") ? fdir "\" rel : ""
    othP := c["loser"]
    sr := ShotRel(rel)
    curShot := (sr != "" && fdir != "" && FileExist(fdir "\" sr)) ? fdir "\" sr : ""
    othShot := (sr != "") ? FindVariant(c["dir"], sr) : ""
    UI["cfFile"].Text := rel "   ·   " folder

    ; which one is newer
    tag1 := "", tag2 := ""
    if (curP != "" && FileExist(curP) && FileExist(othP)) {
        diff := DateDiff(FileGetTime(curP, "M"), FileGetTime(othP, "M"), "Seconds")
        if (diff > 1) {
            tag1 := "cf_newer"
            tag2 := "cf_older"
        } else if (diff < -1) {
            tag1 := "cf_older"
            tag2 := "cf_newer"
        }
    }
    isState := IsStateFile(rel)
    ConfFillSide(sides[1], curP, folder, rel, curShot, tag1, isState)
    ConfFillSide(sides[2], othP, folder, rel, othShot, tag2, isState)
    UI["cfShotCur"] := curShot
    UI["cfShotOth"] := othShot
    UI["cfCmp"].Visible := (curShot != "" && othShot != "")
}

; Size, date, who saved it and screenshot of one side
ConfFillSide(d, path, folder, rel, shot, tag, isState) {
    if (path != "" && FileExist(path)) {
        tm := FileGetTime(path, "M")
        sz := FileGetSize(path)
        d["size"].Text := T("cf_size", FormatSize(sz))
        d["date"].Text := T("cf_date", FormatTime(tm, T("fmt_date")))
        who := OriginOf(folder, rel, tm, sz)
        d["from"].Text := (who != "") ? T("cf_origin", who) : ""
    } else {
        d["size"].Text := T("cf_missing")
        d["date"].Text := ""
        d["from"].Text := ""
    }
    d["tag"].Text := (tag != "") ? T(tag) : ""
    if (tag != "")
        Recolor(d["tag"], (tag = "cf_newer") ? TH["ok"] : TH["sub"])
    shown := SetPic(d["pic"], shot, Px(d["x0"] + 12), Px(368), Px(152), Px(114))
    d["noPic"].Text := isState ? T("v_nopreview") : T("cf_nofile")
    d["noPic"].Visible := !shown
}

; Big view of the two screenshots
ConfCompare(*) {
    c := ConfSel()
    if (!IsObject(c) || UI["cfShotCur"] = "" || UI["cfShotOth"] = "")
        return
    curP := Folders.Get(c["folder"], "") "\" c["rel"]
    capA := T("cf_cur")
    if FileExist(curP)
        capA .= "  ·  " FormatTime(FileGetTime(curP, "M"), T("fmt_date"))
    capB := T("cf_oth")
    if FileExist(c["loser"])
        capB .= "  ·  " FormatTime(FileGetTime(c["loser"], "M"), T("fmt_date"))
    CompareShots(MainGui, c["rel"], UI["cfShotCur"], capA, UI["cfShotOth"], capB)
}

; ---- actions

; "Keep the current one": nothing changes in your files, the notice is just marked as reviewed
ConfKeep(*) {
    c := ConfSel()
    if (!IsObject(c) || c["status"] != "pending")
        return
    c["status"] := "kept"
    c["done"] := A_Now
    ConfChanged()
}

ConfMarkAll(*) {
    n := PendingConflicts()
    if (n = 0)
        return
    if (MsgBox(T("cf_confirm_all", n), "SyncDood", "YesNo Icon?") != "Yes")
        return
    for c in Conflicts {
        if (c["status"] = "pending") {
            c["status"] := "kept"
            c["done"] := A_Now
        }
    }
    ConfChanged()
}

; "Use the other one": the version in use goes to the backups first, then the other one takes its place.
; It gets today's date so the next sync spreads it to the other PCs instead of undoing it.
ConfUse(*) {
    c := ConfSel()
    if (!IsObject(c) || c["status"] != "pending")
        return
    if CheckBusy()
        return
    folder := c["folder"], rel := c["rel"]
    if (!Folders.Has(folder) || !FileExist(c["loser"])) {
        RefreshConflicts()
        return
    }
    msg := T("cf_confirm_use", rel)
    if (WatchProc != "" && ProcessExist(WatchProc))
        msg .= "`n`n" T("v_confirm_emu")
    if (MsgBox(msg, "SyncDood", "YesNo Icon?") != "Yes")
        return

    dest := Folders[folder] "\" rel
    sr := ShotRel(rel)
    shotDest := (sr != "") ? Folders[folder] "\" sr : ""
    shotSrc := (sr != "") ? FindVariant(c["dir"], sr) : ""
    stamp := BackupDir "\" folder "\conflicts\" FormatTime(, "yyyy-MM-dd_HHmmss")
    newLoser := ""
    try {
        ; 1) what is in use now is kept in the backups
        if FileExist(dest) {
            newLoser := stamp "\" rel
            SplitPath(newLoser, , &bkDir)
            DirCreate(bkDir)
            FileCopy(dest, newLoser, true)
            if (shotDest != "" && FileExist(shotDest)) {
                SplitPath(stamp "\" sr, , &bkDir)
                DirCreate(bkDir)
                FileCopy(shotDest, stamp "\" sr, true)
            }
        }
        ; 2) the other version takes its place
        SplitPath(dest, , &destDir)
        DirCreate(destDir)
        FileCopy(c["loser"], dest, true)
        if (shotDest != "" && shotSrc != "")
            FileCopy(shotSrc, shotDest, true)
        FileSetTime(A_Now, dest, "M")
        if (shotDest != "" && FileExist(shotDest))
            FileSetTime(A_Now, shotDest, "M")
    } catch as err {
        MsgBox(T("v_fail", err.Message), "SyncDood", "Iconx")
        return
    }

    ; the list now shows the former one as "the other version", so nothing is lost track of
    if (newLoser != "") {
        c["loser"] := newLoser
        c["dir"] := stamp
    }
    c["status"] := "swapped"
    c["done"] := A_Now
    AddHistory(folder, "restore", rel, FileGetSize(dest))
    SaveHistory()
    RefreshHistory()
    ConfChanged()
}

; After any change of the notices: save, refresh the list, and settle the tray icon / folder status
ConfChanged() {
    SaveConflicts()
    for nm, fs in FState {
        if (fs["st"] = "conflict" && !FolderPendingConf(nm))
            fs["st"] := "ok"
    }
    n := PendingConflicts()
    if (!Syncing && TipKind = "conflict") {
        if (n > 0)
            SetState("error", T("tip_conflict", n), "conflict")
        else
            SetState("ok", T("tip_conflict_seen"))
    }
    RefreshConflicts()
    UpdateHeader()
}

; ---- data (data\conflicts.tsv: one notice per line, they survive restarts)
LoadConflicts() {
    global Conflicts
    Conflicts := []
    if !FileExist(ConfFile)
        return
    for line in StrSplit(FileRead(ConfFile, "UTF-8"), "`n", "`r") {
        f := StrSplit(line, "`t")
        if (f.Length >= 7)
            Conflicts.Push(Map("ts", f[1], "folder", f[2], "rel", f[3], "status", f[4], "loser", f[5], "dir", f[6], "done", f[7]))
    }
    CleanConflicts()
}

SaveConflicts() {
    global Conflicts
    ; every pending one is kept; of the resolved ones only the 40 most recent
    keep := []
    nRes := 0
    Loop Conflicts.Length {
        c := Conflicts[Conflicts.Length - A_Index + 1]
        if (c["status"] != "pending") {
            nRes += 1
            if (nRes > 40)
                continue
        }
        keep.InsertAt(1, c)
    }
    Conflicts := keep
    out := ""
    for c in Conflicts
        out .= c["ts"] "`t" c["folder"] "`t" c["rel"] "`t" c["status"] "`t" c["loser"] "`t" c["dir"] "`t" c["done"] "`n"
    try {
        FileDelete(ConfFile)
    }
    try {
        FileAppend(out, ConfFile, "UTF-8")
    }
}

; Called by the sync when it saves the losing copy of a file. A newer notice for the same file replaces the older one.
AddConflict(folder, rel, loser, dir) {
    Loop Conflicts.Length {
        i := Conflicts.Length - A_Index + 1
        c := Conflicts[i]
        if (c["status"] = "pending" && c["folder"] = folder && StrLower(c["rel"]) = StrLower(rel))
            Conflicts.RemoveAt(i)
    }
    Conflicts.Push(Map("ts", A_Now, "folder", folder, "rel", rel, "status", "pending", "loser", loser, "dir", dir, "done", ""))
    SaveConflicts()
}

; Forgets the pending ones that can no longer be compared: the saved copy is gone (automatic cleanup) or the folder was removed
CleanConflicts() {
    changed := false
    Loop Conflicts.Length {
        i := Conflicts.Length - A_Index + 1
        c := Conflicts[i]
        if (c["status"] = "pending" && (!Folders.Has(c["folder"]) || !FileExist(c["loser"]))) {
            Conflicts.RemoveAt(i)
            changed := true
        }
    }
    if changed
        SaveConflicts()
}

PendingConflicts() {
    n := 0
    for c in Conflicts {
        if (c["status"] = "pending")
            n += 1
    }
    return n
}

FolderPendingConf(name) {
    for c in Conflicts {
        if (c["status"] = "pending" && c["folder"] = name)
            return true
    }
    return false
}

; --------------------------------------------------------- Page: Folders -----
BuildFoldersPage(g, arr) {
    global FolderLV
    AddTxt(g, arr, Format("x{1} y22 w{2} h40 +0x200", CX, CW0), T("tab_folders"), "s18 bold", TH["text"], TH["bg"])
    AddTxt(g, arr, Format("x{1} y68 w{2} h40", CX, CW0), T("f_intro"), "s9 norm", TH["sub"], TH["bg"])
    bx := CX
    for it in [[T("f_add"), AddFolderUI, 130], [T("f_cloud_add"), AddFromCloudUI, 176], [T("f_change"), ChangeFolderUI, 130], [T("f_remove"), RemoveFolderUI, 90], [T("f_open"), OpenFolderUI, 80]] {
        AddBtn(g, arr, bx, 114, it[3], 32, it[1], it[2])
        bx += it[3] + 8
    }
    bx := CX
    for it in [[T("f_sync_one"), SyncSelectedUI, 200, "prim"], [T("f_excl"), ExcludeUI, 220, "norm"], [T("f_repair"), MenuResync, 250, "norm"]] {
        AddBtn(g, arr, bx, 154, it[3], 32, it[1], it[2], it[4])
        bx += it[3] + 8
    }
    ; search (useful when there are many folders) + how many are shown
    AddTxt(g, arr, Format("x{1} y198 w64 h26 +0x200", CX), T("f_search"), "s9 norm", TH["sub"], TH["bg"])
    UI["fSearch"] := AddEdit(g, arr, CX + 66, 198, 240, "")
    UI["fSearch"].OnEvent("Change", (*) => FillFolders())
    UI["fCount"] := AddTxt(g, arr, Format("x{1} y198 w300 h26 +0x200", CX + 322), "", "s9 norm", TH["sub"], TH["bg"])
    UI["fCols"] := []
    for lb in [T("f_col_name"), T("f_col_path"), T("f_col_status"), T("f_col_excl")]
        UI["fCols"].Push(AddTxt(g, arr, Format("x{1} y232 w100 h20 +0x200", CX), lb, "s9 bold", TH["sub"], TH["bg"]))
    UI["fLine"] := g.Add("Text", Format("x{1} y254 w{2} h1 Background{3}", CX, CW0 + 28, TH["border"]), "")
    arr.Push(UI["fLine"])
    g.SetFont("s9 norm c" TH["text"], "Segoe UI")
    FolderLV := g.Add("ListView", Format("x{1} y258 w{2} h{3} -Hdr -Multi +LV0x10000 -E0x200 c{4} Background{5}"
        , CX, CW0 + 28, H0 - 258, TH["text"], TH["lvBg"])
        , [T("f_col_name"), T("f_col_path"), T("f_col_status"), T("f_col_excl")])
    arr.Push(FolderLV)
    LayoutFolders(Px(CW0 + 28))
}

LayoutFolders(wRaw) {
    wd := wRaw / Dpi
    cols := [170, 0, 190, 90]
    cols[2] := Max(140, wd - 170 - 190 - 90 - 24)
    x := 0
    for i, cw in cols {
        FolderLV.ModifyCol(i, Px(cw))
        UI["fCols"][i].Move(Px(CX) + Px(x) + Px(6), , Px(cw) - Px(8))
        x += cw
    }
}

; ----------------------------------------------------------- Page: Cloud -----
BuildCloudPage(g, arr) {
    AddTxt(g, arr, Format("x{1} y22 w{2} h40 +0x200", CX, CW0), T("tab_cloud"), "s18 bold", TH["text"], TH["bg"])
    UI["cloudCard"] := g.Add("Text", Format("x{1} y76 w{2} h132 Background{3}", CX, CW0, TH["card"]), "")
    arr.Push(UI["cloudCard"])
    AddTxt(g, arr, Format("x{1} y92 w600 h20 +0x200", CX + 22), T("c_current"), "s9 bold", TH["sub"], TH["card"])
    UI["cloudCur"] := AddTxt(g, arr, Format("x{1} y114 w{2} h38 +0x200", CX + 22, CW0 - 44), "", "s17 bold", TH["accent"], TH["card"])
    UI["cloudTgt"] := AddTxt(g, arr, Format("x{1} y156 w{2} h40", CX + 22, CW0 - 44), "", "s9 norm", TH["sub"], TH["card"])
    AddBtn(g, arr, CX, 226, 190, 34, T("c_change"), ChangeCloudUI, "prim")
    AddBtn(g, arr, CX + 198, 226, 190, 34, T("c_test"), TestCloudUI)
    AddBtn(g, arr, CX + 396, 226, 150, 34, T("c_space_btn"), CloudSpaceUI)
    AddBtn(g, arr, CX + 554, 226, 170, 34, T("sp_btn"), SpacePanelUI)
    UI["cloudSpace"] := AddTxt(g, arr, Format("x{1} y276 w{2} h44", CX, CW0), "", "s10 norm", TH["text"], TH["bg"])
    AddTxt(g, arr, Format("x{1} y332 w{2} h60", CX, CW0), T("c_note"), "s9 norm", TH["sub"], TH["bg"])
}

; --------------------------------------------------------- Page: Options -----
BuildOptionsPage(g, arr) {
    AddTxt(g, arr, Format("x{1} y22 w{2} h40 +0x200", CX, CW0), T("tab_options"), "s18 bold", TH["text"], TH["bg"])
    lx := CX
    vx := CX + 410
    y := 76
    ; each row: label on the left, control on the right
    Lbl := (txt) => AddTxt(g, arr, Format("x{1} y{2} w396 h28 +0x200", lx, y), txt, "s9 norm", TH["text"], TH["bg"])

    Lbl(T("o_language"))
    OptC["lang"] := AddSeg(g, arr, vx, y, [T("seg_auto"), "English", "Español"], 1, 96)
    y += 29
    Lbl(T("o_theme"))
    OptC["theme"] := AddSeg(g, arr, vx, y, [T("seg_auto"), T("th_light"), T("th_dark")], 1, 96)
    y += 29
    Lbl(T("o_interval"))
    OptC["interval"] := AddEdit(g, arr, vx, y + 2, 80, IntervalMin, "Number")
    y += 29
    Lbl(T("o_watch"))
    OptC["watch"] := AddEdit(g, arr, vx, y + 2, 200, WatchProc)
    y += 29
    Lbl(T("o_resume"))
    OptC["resume"] := AddEdit(g, arr, vx, y + 2, 80, ResumeDelay, "Number")
    y += 29
    Lbl(T("o_settle"))
    OptC["settle"] := AddEdit(g, arr, vx, y + 2, 80, SettleSec, "Number")
    y += 29
    Lbl(T("o_firstwins"))
    OptC["firstwins"] := AddSeg(g, arr, vx, y, [T("fw_newer"), T("fw_local"), T("fw_cloud")], 1, 96)
    y += 29
    Lbl(T("o_parallel"))
    OptC["parmode"] := AddSeg(g, arr, vx, y, [T("seg_auto"), T("seg_manual")], 1, 96)
    OptC["par"] := AddEdit(g, arr, vx + 208, y + 2, 60, ParallelNow(), "Number")
    y += 29
    Lbl(T("o_maxdel"))
    OptC["maxdel"] := AddEdit(g, arr, vx, y + 2, 80, MaxDelPct, "Number")
    y += 29
    Lbl(T("o_pcname"))
    OptC["pcname"] := AddEdit(g, arr, vx, y + 2, 200, PcName)
    y += 29
    Lbl(T("o_backupdir"))
    OptC["backup"] := AddEdit(g, arr, vx, y + 2, 210, BackupDir)
    AddBtn(g, arr, vx + 218, y, 90, 28, T("cd_browse"), BrowseBackup)
    y += 29
    Lbl(T("o_keepdays"))
    OptC["keep"] := AddEdit(g, arr, vx, y + 2, 80, KeepDays, "Number")
    y += 34

    OptC["startup"] := AddToggle(g, arr, lx, y, 620, T("o_startup"), false)
    y += 28
    OptC["checkupd"] := AddToggle(g, arr, lx, y, 620, T("o_checkupd"), false)
    y += 28
    OptC["pause"] := AddToggle(g, arr, lx, y, 700, T("o_pause"), false)
    y += 28
    OptC["cloudprune"] := AddToggle(g, arr, lx, y, 700, T("o_cloudprune"), false)
    y += 28
    OptC["dryrun"] := AddToggle(g, arr, lx, y, 620, T("o_dryrun"), false)
    y += 34

    AddBtn(g, arr, lx, y, 190, 36, T("o_save"), SaveOptions, "prim", "s9 bold")
    AddBtn(g, arr, lx + 198, y, 130, 36, T("o_open_ini"), MenuOpenIni)
    AddBtn(g, arr, lx + 336, y, 110, 36, T("o_open_log"), MenuOpenLog)
    AddBtn(g, arr, lx + 454, y, 130, 36, T("o_open_backups"), MenuOpenBackup)
    y += 46
    AddBtn(g, arr, lx, y, 190, 30, T("o_export"), ExportConfigUI)
    AddBtn(g, arr, lx + 198, y, 190, 30, T("o_import"), ImportConfigUI)
    y += 40
    AddBtn(g, arr, lx, y, 190, 30, T("o_uninstall"), UninstallUI, "danger")
}

; ----------------------------------------------------------- Page: About -----
BuildAboutPage(g, arr) {
    ico := PicPath("ok")
    if (ico != "") {
        try {
            arr.Push(g.Add("Picture", Format("x{1} y40 w80 h80 BackgroundTrans", CX), ico))
        }
    }
    AddTxt(g, arr, Format("x{1} y34 w400 h48 +0x200", CX + 100), "SyncDood", "s26 bold", TH["text"], TH["bg"])
    AddTxt(g, arr, Format("x{1} y86 w400 h26 +0x200", CX + 102), T("ab_version", AppVersion), "s10 norm", TH["sub"], TH["bg"])
    AddTxt(g, arr, Format("x{1} y146 w{2} h80", CX, CW0 - 40), T("ab_desc"), "s10 norm", TH["text"], TH["bg"])
    AddTxt(g, arr, Format("x{1} y234 w{2} h26 +0x200", CX, CW0), T("ab_made", AppAuthor), "s10 norm", TH["text"], TH["bg"])
    AddBtn(g, arr, CX, 276, 300, 36, T("ab_patreon"), MenuPatreon, "prim", "s10 norm")
    AddBtn(g, arr, CX + 310, 276, 360, 36, T("ab_github"), MenuGithub, "norm", "s10 norm")
    AddTxt(g, arr, Format("x{1} y334 w{2} h24 +0x200", CX, CW0), T("ab_libs_plain"), "s9 norm", TH["sub"], TH["bg"])
    AddBtn(g, arr, CX, 366, 120, 28, "rclone.org", (*) => Run("https://rclone.org"))
    AddBtn(g, arr, CX + 128, 366, 160, 28, "autohotkey.com", (*) => Run("https://www.autohotkey.com"))
    AddBtn(g, arr, CX, 416, 220, 34, T("ab_check"), MenuUpdates)
}

; ============================================================================
;  Games: one card per game (a grid of screenshots); opening a game shows its slots / states.
;  Older versions are the copies the sync already keeps in the backups; the PC name of each one comes from small upload lists (see "Origin of a state")
;  (local: <backupDir>\<folder>\<day>\ and \conflicts\, cloud: _backup/<folder>/<day>/).
;
;  Save-state formats it recognises (any synced folder is scanned):
;    RetroArch    Game.state / .state1 / .state.auto      + Game.state.png (screenshot)
;    DuckStation  SLUS-00594_1.sav / _resume.sav          (inside a "savestates" folder, or named like a disc serial)
;    PCSX2        SLUS-20312 (E3C4F6B8).01.p2s / .resume.p2s
;    Dolphin      GALE01.s01 ... .s10
;    Azahar       00040000001B5000.01.cst
;    PPSSPP       ULUS10041_1.01_0.ppst                   + the .jpg next to it
;  Standalone emulators that store the game as an ID (serials) can be given readable names in
;  %LOCALAPPDATA%\SyncDood\gamenames.ini  (one "ID=Name" per line).
; ============================================================================
BuildGamesPage(g, arr) {
    global GamesLV
    AddTxt(g, arr, Format("x{1} y22 w{2} h40 +0x200", CX, CW0), T("tab_games"), "s18 bold", TH["text"], TH["bg"])
    AddTxt(g, arr, Format("x{1} y68 w{2} h40", CX, CW0), T("g_intro"), "s9 norm", TH["sub"], TH["bg"])
    AddBtn(g, arr, CX, 114, 112, 32, T("g_refresh"), (*) => RefreshGames())
    AddBtn(g, arr, CX + 120, 114, 150, 32, T("g_purge"), PurgeVersionsUI)
    UI["gBtn"] := AddBtn(g, arr, CX + 278, 114, 96, 32, T("g_open"), OpenGameSel, "norm")
    UI["gFind"] := AddEdit(g, arr, CX + 382, 118, 170, "")
    UI["gFind"].OnEvent("Change", (*) => FillGamesGrid())
    try {
        SendMessage(0x1501, 1, StrPtr(T("g_search")), UI["gFind"].Hwnd)        ; EM_SETCUEBANNER
    }
    UI["gSort"] := AddSeg(g, arr, CX + 560, 116, [T("g_sort_az"), T("g_sort_new")], 1, 80)
    for c in UI["gSort"]["btns"]
        c.OnEvent("Click", (*) => FillGamesGrid())
    g.SetFont("s9 norm c" TH["text"], "Segoe UI")
    GamesLV := g.Add("ListView", Format("x{1} y158 w{2} h{3} Icon -Multi +0x8 +0x100 +LV0x400 +LV0x10000 -E0x200 c{4} Background{5}"
        , CX, CW0 + 28, H0 - 158, TH["text"], TH["lvBg"])
        , [T("g_col_game")])
    arr.Push(GamesLV)
    GamesLV.OnEvent("DoubleClick", OpenGameDbl)
    GamesLV.OnEvent("ItemSelect", UpdateGamesSel)
    UI["gEmpty"] := AddTxt(g, arr, Format("x{1} y{2} w{3} h28 +0x200 Center", CX, 240, CW0), T("g_empty"), "s10 norm", TH["sub"], TH["lvBg"])
}

; The Open button turns blue when a game is selected
UpdateGamesSel(*) {
    if (!MainBuilt || !UI.Has("gBtn") || !IsObject(GamesLV))
        return
    row := GamesLV.GetNext(0)
    SetBtnKind(UI["gBtn"], (row > 0 && row <= GamesView.Length) ? "prim" : "norm")
}

; Spacing between cards = thumbnail + room for the (two-line) name. Must be set after the image list.
SetIconSpacing(lv, tw, thh) {
    sx := Px(tw + 18), sy := Px(thh + 56)
    try {
        SendMessage(0x1035, 0, (sy << 16) | (sx & 0xFFFF), lv.Hwnd)         ; LVM_SETICONSPACING
    }
}

OpenGameSel(*) {
    row := GamesLV.GetNext(0)
    if (row = 0 || row > GamesView.Length) {
        MsgBox(T("g_nosel"), "SyncDood", "Iconi")
        return
    }
    GameUI(GamesView[row]["key"])
}

OpenGameDbl(lv, row, *) {
    if (row > 0 && row <= GamesView.Length)
        GameUI(GamesView[row]["key"])
}

; Rescans the folders and rebuilds the grid with its thumbnails
RefreshGames() {
    global GamesList, GamesGroups
    if (!MainBuilt || !IsObject(MainGui))
        return
    ToolTip(T("g_loading"))
    GamesList := ScanStates()
    GamesGroups := GroupStates(GamesList)
    il := DllCall("comctl32\ImageList_Create", "Int", Px(GTW), "Int", Px(GTH), "UInt", 0x20, "Int", 16, "Int", 16, "Ptr")
    for gr in GamesGroups {
        badge := (gr["items"].Length > 1) ? "×" gr["items"].Length : ""
        hb := MakeThumb(gr["shot"], Px(GTW), Px(GTH), TILE_BG, gr["emu"], badge, Initials(gr["name"]))
        gr["img"] := DllCall("comctl32\ImageList_Add", "Ptr", il, "Ptr", hb, "Ptr", 0, "Int") + 1
        DllCall("DeleteObject", "Ptr", hb)
    }
    GamesLV.Opt("-Redraw")
    GamesLV.Delete()
    old := GamesLV.SetImageList(il, 0)
    if old {
        try {
            DllCall("comctl32\ImageList_Destroy", "Ptr", old)
        }
    }
    SetIconSpacing(GamesLV, GTW, GTH)
    GamesLV.Opt("+Redraw")
    FillGamesGrid()
    ToolTip()
}

; Fills the grid from GamesGroups using the search box and the sort buttons (no rescan)
FillGamesGrid() {
    global GamesView
    if (!MainBuilt || !IsObject(GamesLV) || !UI.Has("gFind"))
        return
    prev := ""
    row := GamesLV.GetNext(0)
    if (row > 0 && row <= GamesView.Length)
        prev := GamesView[row]["key"]
    q := Trim(UI["gFind"].Value)
    view := []
    for gr in GamesGroups {
        if (q = "" || InStr(gr["name"] " " gr["emu"], q))
            view.Push(gr)
    }
    if (UI["gSort"]["sel"] = 2 && view.Length > 1) {
        keys := ""
        for i, gr in view
            keys .= gr["latest"] "`t" i "`n"
        keys := Sort(RTrim(keys, "`n"), "R")
        sorted := []
        for line in StrSplit(keys, "`n")
            sorted.Push(view[Integer(SubStr(line, InStr(line, "`t") + 1))])
        view := sorted
    }
    GamesView := view
    GamesLV.Opt("-Redraw")
    GamesLV.Delete()
    for gr in view
        GamesLV.Add("Icon" gr["img"], gr["name"])
    if (view.Length > 0) {
        pick := 1
        for i, gr in view {
            if (gr["key"] = prev) {
                pick := i
                break
            }
        }
        GamesLV.Modify(pick, "Select Focus Vis")
    }
    GamesLV.Opt("+Redraw")
    UI["gEmpty"].Text := (GamesGroups.Length = 0) ? T("g_empty") : T("g_nomatch")
    UI["gEmpty"].Visible := (view.Length = 0 && CurPage = PG_GAMES)
    UpdateGamesSel()
}

FindGroup(key) {
    for gr in GamesGroups {
        if (gr["key"] = key)
            return gr
    }
    return ""
}

; One entry per game: Map(key, name, emu, folder, items (sorted by slot), shot (screenshot of the newest state), latest (date))
GroupStates(list) {
    byKey := Map()
    arr := []
    for e in list {
        k := e["gkey"]
        if !byKey.Has(k) {
            gr := Map("key", k, "name", e["gname"], "emu", e["emu"], "folder", e["folder"], "items", [], "shot", "", "latest", "", "img", 1)
            byKey[k] := gr
            arr.Push(gr)
        }
        byKey[k]["items"].Push(e)
    }
    for gr in arr {
        shotTime := ""
        for e in gr["items"] {
            if (gr["latest"] = "" || e["time"] > gr["latest"])
                gr["latest"] := e["time"]
            if (e["png"] != "" && (shotTime = "" || e["time"] > shotTime)) {
                gr["shot"] := e["png"]
                shotTime := e["time"]
            }
        }
    }
    return arr
}

; "Chrono Trigger - Edicion..." -> "CT";  one word or an ID ("SLUS-00594") -> its first two characters
Initials(name) {
    if !InStr(Trim(name), " ")
        return StrUpper(SubStr(Trim(name), 1, 2))
    out := ""
    pos := 1
    while (StrLen(out) < 2 && RegExMatch(name, "[\p{L}\p{N}]+", &m, pos)) {
        out .= SubStr(m[0], 1, 1)
        pos := m.Pos + m.Len
    }
    return StrUpper(out)
}

; Window of one game: its slots as a grid of screenshots, with the older versions of the selected one
GameUI(key) {
    if !IsObject(FindGroup(key))
        return
    LVW := 740
    LVH := Min(Ceil(FindGroup(key)["items"].Length / 3) * (GDH + 54) + 16, 420)       ; 3 per row, as many rows as needed
    d := Gui("+Owner" MainGui.Hwnd, T("gd_title", FindGroup(key)["name"]))
    d.BackColor := TH["bg"]
    d.MarginX := 16
    d.MarginY := 14
    d.SetFont("s9 norm c" TH["text"], "Segoe UI")
    AddTxt(d, "", Format("x16 y14 w{1} h34 +0x200", LVW), FindGroup(key)["name"], "s15 bold", TH["text"], TH["bg"])
    subTxt := AddTxt(d, "", Format("x16 y50 w{1} h22 +0x200", LVW), "", "s9 norm", TH["sub"], TH["bg"])
    d.SetFont("s9 norm c" TH["text"], "Segoe UI")
    lv := d.Add("ListView", Format("x16 y82 w{1} h{2} Icon -Multi +0x8 +0x100 +LV0x400 +LV0x10000 -E0x200 c{3} Background{4}", LVW, LVH, TH["text"], TH["lvBg"])
        , [T("g_col_slot")])
    DllCall("uxtheme\SetWindowTheme", "Ptr", lv.Hwnd, "Str", DarkNow ? "DarkMode_Explorer" : "Explorer", "Ptr", 0)
    yb := 82 + LVH + 10
    infoTxt := AddTxt(d, "", Format("x16 y{1} w{2} h24 +0x200", yb, LVW), "", "s9 bold", TH["accent"], TH["bg"])
    yb += 32
    AddBtn(d, "", 16, yb, 300, 34, T("g_versions"), (*) => OpenSlot(), "prim")
    AddBtn(d, "", 324, yb, 170, 34, T("g_rename"), (*) => RenameGame())
    AddBtn(d, "", 502, yb, 138, 34, T("g_lookup"), (*) => FindNames())
    AddBtn(d, "", 16 + LVW - 110, yb, 110, 34, T("v_close"), (*) => d.Destroy())
    d.OnEvent("Close", (*) => d.Destroy())
    lv.OnEvent("ItemSelect", (*) => ShowInfo())
    lv.OnEvent("DoubleClick", (*) => OpenSlot())
    FillSlots()
    d.Show("w" . (LVW + 32) . " h" . (yb + 34 + 16))

    FillSlots() {
        gr := FindGroup(key)
        if !IsObject(gr) {
            d.Destroy()
            return
        }
        prevRow := lv.GetNext(0)
        subTxt.Text := T("gd_sub", gr["emu"], gr["folder"], gr["items"].Length)
        il := DllCall("comctl32\ImageList_Create", "Int", Px(GDW), "Int", Px(GDH), "UInt", 0x20, "Int", 16, "Int", 16, "Ptr")
        for e in gr["items"] {
            hb := MakeThumb(e["png"], Px(GDW), Px(GDH), TILE_BG, "", "", SlotShort(e))
            idx := DllCall("comctl32\ImageList_Add", "Ptr", il, "Ptr", hb, "Ptr", 0, "Int")
            DllCall("DeleteObject", "Ptr", hb)
        }
        lv.Opt("-Redraw")
        lv.Delete()
        old := lv.SetImageList(il, 0)
        if old {
            try {
                DllCall("comctl32\ImageList_Destroy", "Ptr", old)
            }
        }
        SetIconSpacing(lv, GDW + 10, GDH - 2)
        for i, e in gr["items"]
            lv.Add("Icon" i, SlotLabel(e) "  ·  " FormatTime(e["time"], T("fmt_date")))
        lv.Opt("+Redraw")
        if (gr["items"].Length > 0)
            lv.Modify((prevRow > 0 && prevRow <= gr["items"].Length) ? prevRow : 1, "Select Focus Vis")
        ShowInfo()
    }

    ShowInfo() {
        gr := FindGroup(key)
        r := lv.GetNext(0)
        if (!IsObject(gr) || r = 0 || r > gr["items"].Length) {
            infoTxt.Text := ""
            return
        }
        e := gr["items"][r]
        infoTxt.Text := T("gd_info", SlotLabel(e), FormatTime(e["time"], T("fmt_date")), FormatSize(e["size"]), e["origin"])
    }

    ; Gives the game a readable name (saved in gamenames.ini) and reopens this window with it
    RenameGame() {
        gr := FindGroup(key)
        if (!IsObject(gr) || gr["items"].Length = 0)
            return
        id := gr["items"][1]["gid"]
        names := LoadGameNames()
        ib := InputBox(T("g_rename_ask", id), "SyncDood", "w420 h200", names.Has(id) ? names[id] : "")
        if (ib.Result != "OK")
            return
        SetGameName(id, Trim(ib.Value))
        d.Destroy()
        RefreshGames()
        GameUI(key)
    }

    ; Searches the names of all the games that still show an ID, then reopens this window
    FindNames() {
        if !LookupNames()
            return
        d.Destroy()
        RefreshGames()
        GameUI(key)
    }

    OpenSlot(*) {
        gr := FindGroup(key)
        r := lv.GetNext(0)
        if (!IsObject(gr) || r = 0 || r > gr["items"].Length) {
            MsgBox(T("g_nosel"), "SyncDood", "Iconi")
            return
        }
        VersionsUI(gr["items"][r], d.Hwnd, () => (RefreshGames(), FillSlots()))
    }
}

; "Slot 3" for numbered slots, "Auto" / "undo" for the special ones
SlotLabel(e) {
    return (Integer(e["slotKey"]) >= 998) ? e["slotTxt"] : T("gd_slot", e["slotTxt"])
}

; Short text drawn on a tile that has no screenshot
SlotShort(e) {
    return (Integer(e["slotKey"]) >= 998) ? e["slotTxt"] : "#" e["slotTxt"]
}

; All the states in the synced folders: array of Map(folder, rel, game, gname, gkey, emu, slotTxt, slotKey, time, size, png, origin)
ScanStates() {
    out := []
    keys := ""
    names := LoadGameNames()
    for name, path in Folders {
        if !DirExist(path)
            continue
        base := StrLen(path) + 2
        Loop Files path "\*", "FR" {
            ps := ParseState(A_LoopFileName, A_LoopFileDir)
            if !IsObject(ps)
                continue
            full := A_LoopFilePath
            rel := SubStr(full, base)
            SplitPath(rel, , &sub)
            id := ps["game"]
            gname := names.Has(id) ? names[id] : id
            isRA := (ps["emu"] = "RetroArch")
            if (isRA && sub != "")
                gname .= "  (" sub ")"           ; RetroArch keeps one folder per core
            shot := (ps["shot"] != "") ? A_LoopFileDir "\" ps["shot"] : ""
            if (shot != "" && !FileExist(shot))
                shot := ""
            out.Push(Map("folder", name, "rel", rel, "game", gname, "gname", gname, "gid", id, "emu", ps["emu"]
                , "gkey", ps["emu"] "|" name "|" (isRA ? StrLower(sub) : "") "|" StrLower(id)
                , "slotTxt", ps["slotTxt"], "slotKey", ps["slotKey"]
                , "time", A_LoopFileTimeModified, "size", A_LoopFileSize
                , "png", shot, "origin", StateOrigin(name, rel, A_LoopFileTimeModified, A_LoopFileSize)))
            keys .= StrLower(gname) "|" ps["emu"] "|" ps["slotKey"] "`t" out.Length "`n"
        }
    }
    if (out.Length = 0)
        return out
    keys := RTrim(keys, "`n")
    keys := Sort(keys)
    sorted := []
    for line in StrSplit(keys, "`n") {
        p := InStr(line, "`t")
        sorted.Push(out[Integer(SubStr(line, p + 1))])
    }
    return sorted
}

; ---- which files are save states -------------------------------------------
; Map(emu, game, slotTxt, slotKey, shot) for the NAME of a state file, or "" if it isn't one.
; shot = name of its screenshot next to it ("" if the emulator keeps none). dir = folder that contains it.
ParseState(leaf, dir := "") {
    if RegExMatch(leaf, "i)^(.+)\.state(\d*|\.auto)$", &m)              ; RetroArch
        return StateInfo("RetroArch", m[1], (m[2] = "") ? 0 : m[2], leaf ".png")
    if RegExMatch(leaf, "i)\.sav$") {                                   ; DuckStation
        if (RegExMatch(leaf, "i)^(.+)_(\d+|resume)\.sav$", &m)
            && (RegExMatch(m[1], "i)^[A-Z]{4}-\d{5}$") || RegExMatch(dir, "i)(^|[\\/])savestates$")))
            return StateInfo("DuckStation", m[1], m[2])
        return ""
    }
    if RegExMatch(leaf, "i)^(.+?) \([0-9A-F]{8}\)\.(\d+|resume)\.p2s$", &m)      ; PCSX2
        return StateInfo("PCSX2", m[1], m[2])
    if RegExMatch(leaf, "i)^([A-Z0-9]{4,6})\.s(0[1-9]|10)$", &m)                ; Dolphin
        return StateInfo("Dolphin", m[1], m[2])
    if RegExMatch(leaf, "i)^([0-9A-F]{16})\.(\d+)\.cst$", &m)                    ; Azahar / Citra
        return StateInfo("Azahar", m[1], m[2])
    if RegExMatch(leaf, "i)^(.+)_(\d+(?:\.\d+)+)_(\d+|undo)\.ppst$", &m)         ; PPSSPP
        return StateInfo("PPSSPP", m[1], m[3], RegExReplace(leaf, "i)\.ppst$", ".jpg"))
    return ""
}

StateInfo(emu, game, slot, shot := "") {
    if (slot = ".auto" || slot = "resume") {
        txt := T("slot_auto"), key := "999"
    } else if (slot = "undo") {
        txt := "undo", key := "998"
    } else {
        txt := Integer(slot), key := Format("{1:03d}", Integer(slot))
    }
    return Map("emu", emu, "game", game, "slotTxt", txt, "slotKey", key, "shot", shot)
}

; Screenshot of a state, as a path relative to its folder ("" if there is none). rel = path of the state inside the synced folder
ShotRel(rel) {
    SplitPath(rel, &leaf, &dir)
    ps := ParseState(leaf, dir)
    if (!IsObject(ps) || ps["shot"] = "")
        return ""
    return (dir != "" ? dir "\" : "") ps["shot"]
}

; Optional readable names for games that the emulator saves as an ID:  %LOCALAPPDATA%\SyncDood\gamenames.ini  ->  SLUS-00594=Final Fantasy VII
LoadGameNames() {
    out := Map()
    out.CaseSense := "Off"
    ReadNamesInto(out, AppDir "\gamenames_auto.ini")      ; found on the internet (Find names)
    ReadNamesInto(out, AppDir "\\gamenames.ini")           ; yours: they win
    return out
}

ReadNamesInto(out, f) {
    if !FileExist(f)
        return
    txt := ""
    try {
        txt := FileRead(f, "UTF-8")
    }
    for line in StrSplit(txt, "`n", "`r") {
        line := Trim(line)
        if (line = "" || InStr(";[#", SubStr(line, 1, 1)))
            continue
        p := InStr(line, "=")
        if (p > 1)
            out[Trim(SubStr(line, 1, p - 1))] := Trim(SubStr(line, p + 1))
    }
}

; Looks up the readable name of every game that still shows an ID. Sources (downloaded when you press the button):
;   DuckStation (PlayStation serials)  -> libretro-database, Redump list  (serial -> title)
;   Dolphin (GameCube / Wii IDs)       -> GameTDB  (ID = title)
; What is found goes to gamenames_auto.ini; your own names in gamenames.ini always win. Returns true if anything was searched.
LookupNames() {
    names := LoadGameNames()
    wantPs := Map(), wantDol := Map()
    wantPs.CaseSense := "Off", wantDol.CaseSense := "Off"
    for e in GamesList {
        id := e["gid"]
        if (names.Has(id) || id = "")
            continue
        if (e["emu"] = "DuckStation")
            wantPs[id] := true
        else if (e["emu"] = "Dolphin")
            wantDol[id] := true
    }
    total := wantPs.Count + wantDol.Count
    if (total = 0) {
        MsgBox(T("ln_none"), "SyncDood", "Iconi")
        return false
    }
    found := Map()
    failed := false
    ToolTip(T("g_loading"))
    if (wantPs.Count > 0) {
        txt := HttpText("https://raw.githubusercontent.com/libretro/libretro-database/master/dat/Sony%20-%20PlayStation.dat")
        if (txt = "")
            failed := true
        else
            ParseRedumpDat(txt, wantPs, found)
    }
    if (wantDol.Count > 0) {
        txt := HttpText("https://www.gametdb.com/wiitdb.txt")
        if (txt = "")
            failed := true
        else
            ParseGameTdb(txt, wantDol, found)
    }
    ToolTip()
    if (found.Count > 0) {
        out := ""
        for id, nm in found
            out .= id "=" nm "`n"
        DirCreate(AppDir)
        try {
            FileAppend(out, AppDir "\gamenames_auto.ini", "UTF-8")
        }
    }
    MsgBox(T("ln_done", found.Count, total) (failed ? T("ln_fail") : ""), "SyncDood", failed ? "Icon!" : "Iconi")
    return true
}

; Downloads a text file (UTF-8). "" if it could not be read.
HttpText(url) {
    try {
        whr := ComObject("WinHttp.WinHttpRequest.5.1")
        whr.SetTimeouts(8000, 8000, 20000, 90000)
        whr.Open("GET", url, false)
        whr.SetRequestHeader("User-Agent", "SyncDood-names")
        whr.Send()
        if (whr.Status != 200)
            return ""
        stm := ComObject("ADODB.Stream")
        stm.Type := 1
        stm.Open()
        stm.Write(whr.ResponseBody)
        stm.Position := 0
        stm.Type := 2
        stm.Charset := "utf-8"
        txt := stm.ReadText()
        stm.Close()
        return txt
    }
    return ""
}

; clrmamepro DAT (libretro / Redump):  game ( name "Title (USA) (Disc 1)" ... rom ( ... serial "SLUS-00594" ) )
ParseRedumpDat(txt, want, found) {
    for chunk in StrSplit(txt, "`ngame (") {
        if !InStr(chunk, "serial ")
            continue
        if !RegExMatch(chunk, 'name "([^"]*)"', &nm)
            continue
        pos := 1
        while RegExMatch(chunk, 'serial "([^"]*)"', &sm, pos) {
            pos := sm.Pos + sm.Len
            for sr in StrSplit(sm[1], [",", ";", " "], " `t") {
                if (sr != "" && want.Has(sr) && !found.Has(sr))
                    found[sr] := CleanTitle(nm[1])
            }
        }
    }
}

; Drops the region / revision / language tags, keeps the disc number:  "Final Fantasy VII (USA) (Disc 1)" -> "Final Fantasy VII (Disc 1)"
CleanTitle(n) {
    out := Trim(RegExReplace(n, "\s*\((?!Disc\b)[^)]*\)", ""))
    return (out = "") ? n : out
}

; GameTDB list: one "ID = Title" per line
ParseGameTdb(txt, want, found) {
    for line in StrSplit(txt, "`n", "`r") {
        if RegExMatch(line, "^([A-Za-z0-9]{4,6})\s*=\s*(.+)$", &m) {
            if (want.Has(m[1]) && !found.Has(m[1]))
                found[m[1]] := Trim(m[2])
        }
    }
}

; Saves (or, with an empty name, removes) the readable name of a game ID in gamenames.ini, keeping every other line as it is
SetGameName(id, name) {
    f := AppDir "\gamenames.ini"
    txt := ""
    try {
        txt := FileRead(f, "UTF-8")
    }
    out := "", found := false
    for line in StrSplit(txt, "`n", "`r") {
        t := Trim(line)
        p := InStr(t, "=")
        if (t != "" && !InStr(";[#", SubStr(t, 1, 1)) && p > 1 && StrLower(Trim(SubStr(t, 1, p - 1))) = StrLower(id)) {
            if (!found && name != "")
                out .= id "=" name "`n"
            found := true
            continue
        }
        out .= line "`n"
    }
    if (!found && name != "")
        out := RTrim(out, "`n") (out = "" ? "" : "`n") id "=" name "`n"
    DirCreate(AppDir)
    try {
        FileDelete(f)
    }
    FileAppend(RTrim(out, "`n") "`n", f, "UTF-8")
}

; Where the current copy came from, according to SyncDood's history on this PC
StateOrigin(folder, rel, time, size) {
    o := OriginOf(folder, rel, time, size)
    if (o != "")
        return o
    Loop History.Length {
        h := History[History.Length - A_Index + 1]
        if (h["folder"] != folder || h["rel"] != rel)
            continue
        if (h["ev"] = "restore")
            return T("g_restored_origin")
        if (h["ev"] = "up")
            return T("g_this_pc", PcName)
        if (h["ev"] = "down")
            return T("g_other")
    }
    return T("g_unknown")
}

; Width and height of an image file ([0, 0] if it can't be read)
ImgSize(path) {
    try {
        hb := LoadPicture(path, "GDI+")
        bm := Buffer(A_PtrSize = 8 ? 32 : 24, 0)
        DllCall("GetObject", "Ptr", hb, "Int", bm.Size, "Ptr", bm)
        w := NumGet(bm, 4, "Int"), h := NumGet(bm, 8, "Int")
        DllCall("DeleteObject", "Ptr", hb)
        return [w, h]
    }
    return [0, 0]
}

; HBITMAP of exactly tw x th, a card-like tile: the screenshot scaled to fit and centered on a dark background
; (caller deletes it). tag = small label top-left (emulator), badge = small label bottom-right (number of states),
; ph = big text shown when there is no screenshot.
MakeThumb(path, tileW, tileH, bgHex, tag := "", badge := "", ph := "") {
    hb := 0, w := 0, h := 0
    if (path != "" && FileExist(path)) {
        d := ImgSize(path)
        if (d[1] > 0 && d[2] > 0) {
            s := Min(tileW / d[1], tileH / d[2])
            w := Max(1, Round(d[1] * s)), h := Max(1, Round(d[2] * s))
            try {
                hb := LoadPicture(path, "GDI+ w" w " h" h)
            } catch {
                hb := 0
            }
        }
    }
    scr := DllCall("GetDC", "Ptr", 0, "Ptr")
    mdc := DllCall("CreateCompatibleDC", "Ptr", scr, "Ptr")
    ; 24-bit DIB on purpose: GDI leaves alpha = 0 on a 32-bit bitmap, and the image list would then draw
    ; everything GDI painted (background, labels, text) as transparent
    bmi := Buffer(40, 0)
    NumPut("UInt", 40, "Int", tileW, "Int", -tileH, "UShort", 1, "UShort", 24, bmi)
    canvas := DllCall("CreateDIBSection", "Ptr", scr, "Ptr", bmi, "UInt", 0, "Ptr*", &bits := 0, "Ptr", 0, "UInt", 0, "Ptr")
    oldBmp := DllCall("SelectObject", "Ptr", mdc, "Ptr", canvas, "Ptr")
    brush := DllCall("CreateSolidBrush", "UInt", BGR(bgHex), "Ptr")
    rc := Buffer(16, 0)
    NumPut("Int", 0, "Int", 0, "Int", tileW, "Int", tileH, rc)
    DllCall("FillRect", "Ptr", mdc, "Ptr", rc, "Ptr", brush)
    DllCall("DeleteObject", "Ptr", brush)
    if hb {
        sdc := DllCall("CreateCompatibleDC", "Ptr", scr, "Ptr")
        oldSrc := DllCall("SelectObject", "Ptr", sdc, "Ptr", hb, "Ptr")
        DllCall("BitBlt", "Ptr", mdc, "Int", (tileW - w) // 2, "Int", (tileH - h) // 2, "Int", w, "Int", h
            , "Ptr", sdc, "Int", 0, "Int", 0, "UInt", 0x00CC0020)
        DllCall("SelectObject", "Ptr", sdc, "Ptr", oldSrc)
        DllCall("DeleteDC", "Ptr", sdc)
        DllCall("DeleteObject", "Ptr", hb)
    } else if (ph != "") {
        hf := MakeFont(Round(tileH * 0.36), 700)
        oldF := DllCall("SelectObject", "Ptr", mdc, "Ptr", hf, "Ptr")
        DllCall("SetBkMode", "Ptr", mdc, "Int", 1)
        DllCall("SetTextColor", "Ptr", mdc, "UInt", BGR(Mix(bgHex, "FFFFFF", 0.30)))
        DllCall("DrawTextW", "Ptr", mdc, "Str", ph, "Int", -1, "Ptr", rc, "UInt", 0x25)     ; centered, one line
        DllCall("SelectObject", "Ptr", mdc, "Ptr", oldF)
        DllCall("DeleteObject", "Ptr", hf)
    }
    fpx := Max(10, Round(tileH / 9))
    gap := Max(4, Round(tileH / 20))
    if (tag != "")
        DrawPill(mdc, tag, gap, gap, "0A0D13", "FFFFFF", fpx, false)
    if (badge != "")
        DrawPill(mdc, badge, tileW - gap, tileH - gap, TH["accent"], "FFFFFF", fpx, true)
    fb := DllCall("CreateSolidBrush", "UInt", BGR(Mix(bgHex, "FFFFFF", 0.14)), "Ptr")        ; thin frame
    NumPut("Int", 0, "Int", 0, "Int", tileW, "Int", tileH, rc)
    DllCall("FrameRect", "Ptr", mdc, "Ptr", rc, "Ptr", fb)
    DllCall("DeleteObject", "Ptr", fb)
    DllCall("SelectObject", "Ptr", mdc, "Ptr", oldBmp)
    DllCall("DeleteDC", "Ptr", mdc)
    DllCall("ReleaseDC", "Ptr", 0, "Ptr", scr)
    return canvas
}

; Segoe UI font of a given pixel height (caller deletes it)
MakeFont(pxH, weight := 400) {
    return DllCall("CreateFont", "Int", -pxH, "Int", 0, "Int", 0, "Int", 0, "Int", weight
        , "UInt", 0, "UInt", 0, "UInt", 0, "UInt", 1, "UInt", 0, "UInt", 0, "UInt", 5, "UInt", 0, "Str", "Segoe UI", "Ptr")
}

; Small rounded label drawn on a thumbnail; (x, y) is its top-left corner, or its bottom-right one when fromEnd is true
DrawPill(hdc, text, x, y, bgHex, fgHex, fpx, fromEnd := false) {
    hf := MakeFont(fpx, 700)
    oldF := DllCall("SelectObject", "Ptr", hdc, "Ptr", hf, "Ptr")
    rc := Buffer(16, 0)
    DllCall("DrawTextW", "Ptr", hdc, "Str", text, "Int", -1, "Ptr", rc, "UInt", 0x420)      ; DT_CALCRECT: measure only
    textW := NumGet(rc, 8, "Int"), textH := NumGet(rc, 12, "Int")
    padX := Round(fpx * 0.55), padY := Round(fpx * 0.2)
    pw := textW + 2 * padX, ph := textH + 2 * padY
    if fromEnd
        x -= pw, y -= ph
    brush := DllCall("CreateSolidBrush", "UInt", BGR(bgHex), "Ptr")
    oldB := DllCall("SelectObject", "Ptr", hdc, "Ptr", brush, "Ptr")
    oldP := DllCall("SelectObject", "Ptr", hdc, "Ptr", DllCall("GetStockObject", "Int", 8, "Ptr"), "Ptr")   ; no outline
    DllCall("RoundRect", "Ptr", hdc, "Int", x, "Int", y, "Int", x + pw + 1, "Int", y + ph + 1, "Int", padY * 2, "Int", padY * 2)
    DllCall("SelectObject", "Ptr", hdc, "Ptr", oldB)
    DllCall("SelectObject", "Ptr", hdc, "Ptr", oldP)
    DllCall("DeleteObject", "Ptr", brush)
    DllCall("SetBkMode", "Ptr", hdc, "Int", 1)
    DllCall("SetTextColor", "Ptr", hdc, "UInt", BGR(fgHex))
    NumPut("Int", x + padX, "Int", y + padY, "Int", x + pw, "Int", y + ph, rc)
    DllCall("DrawTextW", "Ptr", hdc, "Str", text, "Int", -1, "Ptr", rc, "UInt", 0x20)       ; one line
    DllCall("SelectObject", "Ptr", hdc, "Ptr", oldF)
    DllCall("DeleteObject", "Ptr", hf)
}

; Shows an image inside a box (raw pixels), keeping its proportions. false if there is no image.
SetPic(pic, path, x, y, bw, bh) {
    if (path = "" || !FileExist(path)) {
        pic.Visible := false
        return false
    }
    d := ImgSize(path)
    if (d[1] <= 0 || d[2] <= 0) {
        pic.Visible := false
        return false
    }
    s := Min(bw / d[1], bh / d[2])
    fw := Max(1, Round(d[1] * s)), fh := Max(1, Round(d[2] * s))
    pic.Move(x + (bw - fw) // 2, y + (bh - fh) // 2, fw, fh)
    pic.Value := "*w" fw " *h" fh " " path
    pic.Visible := true
    return true
}

; ---- older versions ---------------------------------------------------------
; Local backups of one state: day backups and conflicts/replaced. Newest first.
LocalVersions(e) {
    vers := []
    folder := e["folder"], rel := e["rel"]
    sr := ShotRel(rel)
    root := BackupDir "\" folder
    if !DirExist(root)
        return vers
    Loop Files root "\*", "D" {
        dn := A_LoopFileName
        dpath := A_LoopFilePath
        if RegExMatch(dn, "^\d{4}-\d\d-\d\d$") {
            f := dpath "\" rel
            if FileExist(f)
                AddVersion(vers, e, "day", T("v_kind_day", dn), f, (sr != "") ? FindVariant(dpath, sr) : "")
        } else if (dn = "conflicts" || dn = "conflictos") {
            Loop Files dpath "\*", "D" {
                tsn := A_LoopFileName
                tpath := A_LoopFilePath
                f := FindVariant(tpath, rel)
                if (f != "")
                    AddVersion(vers, e, "conf", T("v_kind_conf", SubStr(tsn, 1, 10)), f, (sr != "") ? FindVariant(tpath, sr) : "")
            }
        }
    }
    return SortVersions(vers)
}

; Exact file, or the same file with rclone's ".syncconflictN" suffix, inside dir. "" if neither exists.
FindVariant(dir, relx) {
    exact := dir "\" relx
    if (FileExist(exact) && !InStr(FileExist(exact), "D"))
        return exact
    SplitPath(relx, &leaf, &sub)
    where := dir . (sub != "" ? "\" sub : "")
    if !DirExist(where)
        return ""
    Loop Files where "\" leaf "*syncconflict*", "F" {
        rest := SubStr(A_LoopFileName, StrLen(leaf) + 1)
        if (SubStr(A_LoopFileName, 1, StrLen(leaf)) = leaf && RegExMatch(rest, "^\.+syncconflict\d*$"))
            return A_LoopFilePath
    }
    return ""
}

; Adds a version unless it is the same as the current file or one already in the list (same date and size)
AddVersion(vers, e, kind, kindTxt, src, png, cloudSrc := "", cloudPng := "", time := "", size := "") {
    if (src != "") {
        time := FileGetTime(src, "M")
        size := FileGetSize(src)
    }
    key := time "|" size
    if (key = e["time"] "|" e["size"])
        return false
    for v in vers {
        if (v["time"] "|" v["size"] = key)
            return false
    }
    vers.Push(Map("kind", kind, "kindTxt", kindTxt, "time", time, "size", size
        , "src", src, "png", png, "cloudSrc", cloudSrc, "cloudPng", cloudPng
        , "origin", OriginOf(e["folder"], e["rel"], time, size)))
    return true
}

SortVersions(vers) {
    if (vers.Length < 2)
        return vers
    keys := ""
    for i, v in vers
        keys .= v["time"] "`t" i "`n"
    keys := Sort(RTrim(keys, "`n"), "R")
    out := []
    for line in StrSplit(keys, "`n")
        out.Push(vers[Integer(SubStr(line, InStr(line, "`t") + 1))])
    return out
}

; Cloud backups of one state (needs the network). Returns an array, or "" if the cloud couldn't be read.
CloudVersions(e, vers) {
    src := Remote "/_backup/" e["folder"]
    tmp := A_Temp "\syncdood_cloudver.txt"
    try {
        FileDelete(tmp)
    }
    code := -1
    try {
        code := RunWait(Format('{1} /c ""{2}" lsf -R --files-only --format "tsp" --separator "|" --include "*.state*" --include "*.sav" --include "*.p2s" --include "*.s[0-9][0-9]" --include "*.cst" --include "*.ppst" --include "*.jpg" "{3}" > "{4}""'
            , A_ComSpec, Rclone, src, tmp), , "Hide")
    }
    txt := ""
    try {
        txt := FileRead(tmp, "UTF-8")
    }
    try {
        FileDelete(tmp)
    }
    if (code != 0 && code != 3)          ; 3 = that backup folder doesn't exist (nothing to list)
        return ""
    relS := StrReplace(e["rel"], "\", "/")
    shotS := StrReplace(ShotRel(e["rel"]), "\", "/")
    states := Map(), pngs := Map()       ; day -> [time, size]  /  day -> true
    for line in StrSplit(txt, "`n", "`r") {
        if !RegExMatch(line, "^(\d{4})-(\d\d)-(\d\d) (\d\d):(\d\d):(\d\d)\|(\d+)\|(.+)$", &m)
            continue
        p := m[8]
        s := InStr(p, "/")
        if (s < 2)
            continue
        day := SubStr(p, 1, s - 1)
        r := SubStr(p, s + 1)
        if (r = relS)
            states[day] := [m[1] m[2] m[3] m[4] m[5] m[6], m[7]]
        else if (shotS != "" && r = shotS)
            pngs[day] := true
    }
    added := []
    for day, info in states {
        base := src "/" day "/" relS
        if AddVersion(vers, e, "cloud", T("v_kind_cloud", day), "", "", base, pngs.Has(day) ? src "/" day "/" shotS : "", info[1], info[2])
            added.Push(day)
    }
    return added
}

; Manual cleanup of old save-state versions in the local backups (nothing else is touched, and never the current states)
PurgeVersionsUI(*) {
    if CheckBusy()
        return
    ib := InputBox(T("pv_ask"), "SyncDood", "w420 h210", "90")
    if (ib.Result != "OK")
        return
    days := Trim(ib.Value)
    if !(IsInteger(days) && days >= 0) {
        MsgBox(T("o_invalid"), "SyncDood", "Iconx")
        return
    }
    cutoff := FormatTime(DateAdd(A_Now, -Integer(days), "Days"), "yyyyMMdd")
    dirs := OldBackupDirs(cutoff)
    n := 0, bytes := 0
    for d in dirs {
        Loop Files d "\*", "FR" {
            if IsStateBackup(A_LoopFileName) {
                n += 1
                bytes += A_LoopFileSize
            }
        }
    }
    ; the same in the cloud (the cloud mirrors this PC: its old state versions go too)
    cloudRes := [], cloudN := 0
    if !DryRun {
        ToolTip(T("g_loading"))
        cr := CloudOldStates(cutoff)
        ToolTip()
        if IsObject(cr) {
            cloudRes := cr
            for it in cr
                cloudN += it[2].Length
        } else if (MsgBox(T("pv_cloud_fail"), "SyncDood", "YesNo Icon!") != "Yes") {
            return
        }
    }
    if (n = 0 && cloudN = 0) {
        MsgBox(T("pv_none", days), "SyncDood", "Iconi")
        return
    }
    if (MsgBox(T("pv_confirm", n, FormatSize(bytes) != "" ? FormatSize(bytes) : "0 B", days, cloudN), "SyncDood", "YesNo Icon!") != "Yes")
        return
    ToolTip(T("g_loading"))
    for d in dirs
        PruneDir(d, false)
    for it in cloudRes
        CloudDeleteFiles(it[1], it[2])
    ToolTip()
    MsgBox(T("pv_done", n, cloudN), "SyncDood", "Iconi")
}

; Save-state files inside the dated cloud backup folders older than the cutoff (yyyyMMdd).
; Returns an array of [cloud folder, [files relative to it]], or "" if the cloud could not be read.
CloudOldStates(cutoff) {
    global CloudListFail
    CloudListFail := false
    root := Remote "/_backup"
    olds := []
    for nm in CloudLs(root, true) {
        for sub in CloudLs(root "/" nm, true) {
            if (sub = "conflicts" || sub = "conflictos") {
                for c in CloudLs(root "/" nm "/" sub, true)
                    AddIfOld(olds, root "/" nm "/" sub "/" c, c, cutoff)
            } else {
                AddIfOld(olds, root "/" nm "/" sub, sub, cutoff)
            }
        }
    }
    res := []
    for d in olds {
        fl := []
        for f in CloudLs(d, false) {
            SplitPath(f, &leaf)
            if IsStateBackup(leaf)
                fl.Push(f)
        }
        if (fl.Length > 0)
            res.Push([d, fl])
    }
    return CloudListFail ? "" : res
}

; Deletes those files (relative to the cloud folder dir) and the folder if it ends up empty
CloudDeleteFiles(dir, files) {
    hard := (StrLower(IniRead(IniFile, "general", "cloudId", "")) = "b2") ? " --b2-hard-delete" : ""
    list := A_Temp "\syncdood_cloudpurge.txt"
    txt := ""
    for f in files
        txt .= f "`n"
    try {
        FileDelete(list)
    }
    try {
        FileAppend(txt, list, "UTF-8-RAW")
        RunWait(Format('"{1}" delete "{2}" --files-from "{3}"{4}', Rclone, dir, list, hard), , "Hide")
    }
    try {
        FileDelete(list)
    }
    try {
        RunWait(Format('"{1}" rmdirs "{2}"', Rclone, dir), , "Hide")        ; only removes it if it ended up empty
    }
}

; Window with the older versions of the selected state
VersionsUI(e, owner := 0, onDone := "") {
    st := Map("vers", LocalVersions(e), "cloud", false, "tmps", [])
    pvx := Px(502), pvy := Px(60)

    d := Gui("+Owner" (owner ? owner : MainGui.Hwnd), T("v_title", e["game"], e["slotTxt"]))
    d.BackColor := TH["bg"]
    d.MarginX := 16
    d.MarginY := 14
    d.SetFont("s9 norm c" TH["text"], "Segoe UI")
    AddTxt(d, "", "x16 y14 w800 h40", T("v_help"), "s9 norm", TH["sub"], TH["bg"])
    d.SetFont("s9 norm c" TH["text"], "Segoe UI")
    lv := d.Add("ListView", Format("x16 y60 w470 h{1} -Multi +0x8 +LV0x10000 c{2} Background{3}", VPH, TH["text"], TH["lvBg"])
        , [T("v_col_date"), T("v_col_kind"), T("v_col_size"), T("v_col_origin")])
    DllCall("uxtheme\SetWindowTheme", "Ptr", lv.Hwnd, "Str", DarkNow ? "DarkMode_Explorer" : "Explorer", "Ptr", 0)
    d.Add("Text", Format("x502 y60 w{1} h{2} Background{3}", VPW, VPH, TH["lvBg"]), "")
    pic := d.Add("Picture", "x502 y60 w10 h10 BackgroundTrans", "")
    cap := AddTxt(d, "", Format("x502 y{1} w{2} h24 +0x200", 60 + VPH + 6, VPW), "", "s9 norm", TH["sub"], TH["bg"])
    AddBtn(d, "", 16, 60 + VPH + 16, 200, 34, T("v_restore"), RestoreSel, "prim")
    cloudBtn := AddBtn(d, "", 224, 60 + VPH + 16, 200, 34, T("v_cloud"), LoadCloud)
    AddBtn(d, "", 502, 60 + VPH + 16, 210, 34, T("v_compare"), CompareSel)
    AddBtn(d, "", 502 + VPW - 100, 60 + VPH + 16, 100, 34, T("v_close"), (*) => CloseV())
    d.OnEvent("Close", (*) => CloseV())
    lv.OnEvent("ItemSelect", (*) => ShowSel())
    Fill()
    d.Show("w" . (502 + VPW + 16) . " h" . (60 + VPH + 70))

    Fill() {
        lv.Delete()
        lv.Add(, FormatTime(e["time"], T("fmt_date")), T("v_current"), FormatSize(e["size"]), e["origin"])
        for v in st["vers"]
            lv.Add(, FormatTime(v["time"], T("fmt_date")), v["kindTxt"], FormatSize(v["size"]), v["origin"] != "" ? v["origin"] : "—")
        lv.ModifyCol(1, Px(112))
        lv.ModifyCol(2, Px(156))
        lv.ModifyCol(3, Px(64))
        lv.ModifyCol(4, Px(114))
        lv.Modify(1, "Select Focus")
        ShowSel()
    }

    ; Screenshot file of a row (row 1 = current). A cloud screenshot is downloaded once and reused.
    PathOf(r) {
        if (r = 1)
            return e["png"]
        if (r < 2 || r - 1 > st["vers"].Length)
            return ""
        v := st["vers"][r - 1]
        path := v["png"]
        if (path = "" && v["cloudPng"] != "") {
            tmp := A_Temp "\syncdood_prev_" A_TickCount ".png"
            ToolTip(T("g_loading"))
            try {
                RunWait(Format('"{1}" copyto "{2}" "{3}"', Rclone, v["cloudPng"], tmp), , "Hide")
            }
            ToolTip()
            if FileExist(tmp) {
                v["png"] := tmp
                st["tmps"].Push(tmp)
                path := tmp
            }
        }
        return path
    }

    ShowSel() {
        cap.Text := SetPic(pic, PathOf(lv.GetNext(0)), pvx, pvy, Px(VPW), Px(VPH)) ? "" : T("v_nopreview")
    }

    ; Big view: the current screenshot and the selected version side by side (just the current one if it is the one selected)
    CompareSel(*) {
        r := lv.GetNext(0)
        if (r < 1)
            r := 1
        curLbl := T("v_cmp_cur", FormatTime(e["time"], T("fmt_date")))
        if (r = 1) {
            CompareShots(d, T("v_cmp_title", e["game"], e["slotTxt"]), e["png"], T("v_cmp_only", curLbl), "", "")
            return
        }
        v := st["vers"][r - 1]
        CompareShots(d, T("v_cmp_title", e["game"], e["slotTxt"]), e["png"], curLbl, PathOf(r), T("v_cmp_ver", FormatTime(v["time"], T("fmt_date")) "  ·  " v["kindTxt"]))
    }

    LoadCloud(*) {
        if st["cloud"]
            return
        ToolTip(T("g_loading"))
        added := CloudVersions(e, st["vers"])
        ToolTip()
        if !IsObject(added) {
            MsgBox(T("v_cloud_fail"), "SyncDood", "Iconx")
            return
        }
        st["cloud"] := true
        st["vers"] := SortVersions(st["vers"])
        Fill()
        if (added.Length = 0)
            MsgBox(T("v_cloud_none"), "SyncDood", "Iconi")
    }

    RestoreSel(*) {
        r := lv.GetNext(0)
        if (r < 2) {
            MsgBox(T("v_pick"), "SyncDood", "Iconi")
            return
        }
        if RestoreVersion(e, st["vers"][r - 1]) {
            CloseV()
            if IsObject(onDone)
                onDone()
            else
                RefreshGames()
        }
    }

    CloseV() {
        for f in st["tmps"] {
            try {
                FileDelete(f)
            }
        }
        d.Destroy()
    }
}

; Window that shows one or two screenshots as large as the screen allows (two = side by side, to compare).
; pathB = "" shows only the first. Sizes are worked out in real pixels and converted for the window options.
CompareShots(owner, title, pathA, capA, pathB, capB) {
    two := (pathB != "")
    MonitorGetWorkArea(, &wl, &wt, &wr, &wb)
    availW := (wr - wl) / Dpi - 64                  ; design units
    availH := (wb - wt) / Dpi - 150
    gap := 16
    boxW := two ? Floor((availW - gap) / 2) : availW
    boxW := Min(boxW, 960)
    ; box height from the tallest aspect ratio of the images (default 4:3), limited by the screen
    ratio := 0.75
    for pth in [pathA, pathB] {
        if (pth = "" || !FileExist(pth))
            continue
        sz := ImgSize(pth)
        if (sz[1] > 0 && sz[2] > 0)
            ratio := Max(ratio, sz[2] / sz[1])
    }
    boxH := Min(Floor(boxW * ratio), availH)
    boxH := Max(boxH, 240)
    boxW := Max(boxW, 320)

    g := Gui("+Owner" owner.Hwnd, title)
    g.BackColor := TH["bg"]
    g.SetFont("s9 norm c" TH["text"], "Segoe UI")
    n := two ? 2 : 1
    winW := 16 + n * boxW + (n - 1) * gap + 16
    Loop n {
        x := 16 + (A_Index - 1) * (boxW + gap)
        AddTxt(g, "", Format("x{1} y14 w{2} h24 +0x200", x, boxW), (A_Index = 1) ? capA : capB, "s9 bold", TH["text"], TH["bg"])
        g.Add("Text", Format("x{1} y44 w{2} h{3} Background{4}", x, boxW, boxH, TH["lvBg"]), "")
        pc := g.Add("Picture", Format("x{1} y44 w10 h10 BackgroundTrans", x), "")
        p := (A_Index = 1) ? pathA : pathB
        if !SetPic(pc, p, Px(x), Px(44), Px(boxW), Px(boxH))
            AddTxt(g, "", Format("x{1} y{2} w{3} h24 +0x200 Center", x, 44 + boxH // 2 - 12, boxW), T("v_nopreview"), "s9 norm", TH["sub"], TH["lvBg"])
    }
    yb := 44 + boxH + 14
    AddBtn(g, "", winW - 16 - 110, yb, 110, 34, T("v_close"), (*) => g.Destroy())
    g.OnEvent("Close", (*) => g.Destroy())
    g.OnEvent("Escape", (*) => g.Destroy())
    g.Show("w" winW " h" (yb + 34 + 16))
}

; Puts an older version back in place of the current one. The current one is copied to the backups first.
RestoreVersion(e, v) {
    if CheckBusy()
        return false
    folder := e["folder"], rel := e["rel"]
    dest := Folders[folder] "\" rel
    shotR := ShotRel(rel)
    shotDest := (shotR != "") ? Folders[folder] "\" shotR : ""
    msg := T("v_confirm", e["game"], e["slotTxt"], FormatTime(v["time"], T("fmt_date")))
    if (WatchProc != "" && ProcessExist(WatchProc))
        msg .= "`n`n" T("v_confirm_emu")
    if (MsgBox(msg, "SyncDood", "YesNo Icon?") != "Yes")
        return false

    ; 1) keep what is there now (conflicts\ folder; the automatic cleanup never removes state copies)
    if FileExist(dest) {
        stamp := BackupDir "\" folder "\conflicts\" FormatTime(, "yyyy-MM-dd_HHmmss")
        bk := stamp "\" rel
        SplitPath(bk, , &bkDir)
        try {
            DirCreate(bkDir)
            FileCopy(dest, bk, true)
            if (shotDest != "" && FileExist(shotDest))
                FileCopy(shotDest, stamp "\" shotR, true)
        } catch as err {
            MsgBox(T("v_fail", err.Message), "SyncDood", "Iconx")
            return false
        }
    }

    ; 2) bring the old one back
    SplitPath(dest, , &destDir)
    try {
        DirCreate(destDir)
        if (v["src"] != "") {
            FileCopy(v["src"], dest, true)
            if (shotDest != "" && v["png"] != "" && FileExist(v["png"]))
                FileCopy(v["png"], shotDest, true)
        } else {
            rc := RunWait(Format('"{1}" copyto "{2}" "{3}"', Rclone, v["cloudSrc"], dest), , "Hide")
            if (rc != 0)
                throw Error("rclone " rc)
            if (shotDest != "" && v["cloudPng"] != "") {
                try {
                    RunWait(Format('"{1}" copyto "{2}" "{3}"', Rclone, v["cloudPng"], shotDest), , "Hide")
                }
            }
        }
        ; the copy keeps its old date: make it the newest, or the next sync would undo the restore
        FileSetTime(A_Now, dest, "M")
        if (shotDest != "" && FileExist(shotDest))
            FileSetTime(A_Now, shotDest, "M")
    } catch as err {
        MsgBox(T("v_fail", err.Message), "SyncDood", "Iconx")
        return false
    }

    AddHistory(folder, "restore", rel, FileGetSize(dest))
    SaveHistory()
    RefreshHistory()
    MsgBox(T("v_done"), "SyncDood", "Iconi")
    return true
}

; ----------------------------------------------------------------- Resize -----
OnMainSize(g, minMax, w, h) {
    if (minMax = -1 || !MainBuilt)
        return
    dw := w - BaseW            ; how much bigger than when it was built (raw pixels)
    dh := h - BaseH
    UI["side"].Move(, , , h)
    UI["sideDot"].Move(, Px(H0 - 62) + dh)
    UI["sideTxt"].Move(, Px(H0 - 62) + dh)
    UI["sideVer"].Move(, Px(H0 - 36) + dh)
    ; status
    UI["banner"].Move(, , Px(CW0) + dw)
    UI["bBtn1"].Move(Px(CX + CW0 - 188) + dw)
    UI["bBtn2"].Move(Px(CX + CW0 - 188) + dw)
    UI["bTitle"].Move(, , Px(CW0 - 118 - 204) + dw)
    UI["bSub"].Move(, , Px(CW0 - 120 - 204) + dw)
    UI["infoTxt"].Move(, , Px(CW0 - 200) + dw)
    UI["bPause"].Move(Px(CX + CW0 - 190) + dw)
    UI["stCloud"].Move(Px(CX + CW0 - 440) + dw)
    UI["barTrack"].Move(, , Px(CW0) + dw)
    for r in UI["rows"] {
        r["card"].Move(, , Px(CW0) + dw)
        r["stat"].Move(Px(CX + CW0 - 432) + dw)
        r["btn"].Move(Px(CX + CW0 - 124) + dw)
        r["path"].Move(, , Px(CW0 - 44 - 452) + dw)
    }
    for a in UI["act"]
        a["file"].Move(, , Px(CW0 - 326) + dw)
    ; history
    HistLV.Move(, , Px(CW0 + 28) + dw, Px(H0 - 144) + dh)
    UI["hLine"].Move(, , Px(CW0 + 28) + dw)
    UI["histEmpty"].Move(, , Px(CW0) + dw)
    LayoutHist(Px(CW0 + 28) + dw)
    ; conflicts
    ConfLV.Move(, , Px(CW0 + 28) + dw)
    LayoutConf(Px(CW0 + 28) + dw)
    UI["cfEmpty"].Move(, , Px(CW0) + dw)
    UI["cfAll"].Move(Px(CX + CW0 - 200) + dw)
    UI["cfFile"].Move(, , Px(CW0) + dw)
    UI["cfHint"].Move(, , Px(CW0) + dw)
    ; games
    for i, c in UI["gSort"]["btns"]
        c.Move(Px(CX + 560 + (i - 1) * 84) + dw)
    GamesLV.Move(, , Px(CW0 + 28) + dw, Px(H0 - 158) + dh)
    try {
        SendMessage(0x1016, 0, 0, GamesLV.Hwnd)         ; LVM_ARRANGE: reflow the cards to the new width now
    }
    UI["gEmpty"].Move(, , Px(CW0) + dw)
    ; folders
    FolderLV.Move(, , Px(CW0 + 28) + dw, Px(H0 - 258) + dh)
    UI["fLine"].Move(, , Px(CW0 + 28) + dw)
    LayoutFolders(Px(CW0 + 28) + dw)
    ; cloud
    UI["cloudCard"].Move(, , Px(CW0) + dw)
    UI["cloudSpace"].Move(, , Px(CW0) + dw)
    UI["cloudCur"].Move(, , Px(CW0 - 44) + dw)
    UI["cloudTgt"].Move(, , Px(CW0 - 44) + dw)
}

; Image for the Picture controls: the PNG (always loads); falls back to the .ico. "" if none.
PicPath(name) {
    for ext in ["png", "ico"] {
        f := IconDir "\" name "." ext
        if FileExist(f)
            return f
    }
    return ""
}

; ------------------------------------------------------- Status refresh -----
; Updates everything that shows the sync state: banner, sidebar footer, folder rows,
; progress line and recent activity. Cheap; called on every state change.
UpdateHeader() {
    global BannerCol
    if (!MainBuilt || !IsObject(MainGui))
        return
    kind := LastState
    if (LastState = "error" && TipKind = "conflict")
        kind := "conflict"
    switch kind {
        case "ok":
            col := TH["bn_ok"], title := T("st_title_ok"), dotc := TH["ok"], side := T("st_side_ok")
        case "conflict":
            col := TH["bn_warn"], title := T("st_title_conflict"), dotc := TH["warn"], side := T("st_side_conflict")
        case "error":
            col := TH["bn_err"], title := T("st_title_error"), dotc := TH["err"], side := T("st_side_error")
        default:
            col := TH["bn_sync"], title := T("st_title_syncing"), dotc := TH["accent"], side := T("st_side_syncing")
    }
    if (col != BannerCol) {
        BannerCol := col
        for k in ["banner", "bTitle", "bSub"] {
            UI[k].Opt("Background" col)
            UI[k].Redraw()
        }
        SetBtnKind(UI["bBtn2"], "ban2")
    }
    icon := PicPath(kind = "conflict" ? "conflict" : LastState)
    if (icon != "" && UI.Get("bIcoPath", "") != icon) {
        UI["bIcoPath"] := icon
        try {
            UI["bIco"].Value := "*w80 *h80 " icon
        }
    }
    if (UI["bTitle"].Text != title)
        UI["bTitle"].Text := title
    if (UI["bSub"].Text != LastTip)
        UI["bSub"].Text := LastTip
    bt := (kind = "conflict") ? T("btn_cf_review") : T("btn_details")
    if (UI["bBtn2"].Text != bt)
        UI["bBtn2"].Text := bt
    Recolor(UI["sideDot"], dotc)
    UI["sideTxt"].Text := side

    ; line under the banner
    if (Syncing && SyncWaiting) {
        info := T("st_waiting", SyncName)
    } else if Syncing {
        info := T("st_progress", SyncName, SyncIdx, SyncTotal)
    } else if IsPaused() {
        info := (PauseUntil = "forever") ? T("st_paused_manual") : T("st_paused_until", FormatTime(PauseUntil, T("fmt_date")))
    } else if CapActive() {
        info := T("st_cap", FormatTime(CapUntil, T("fmt_date")))
    } else if EmuBusy() {
        info := T("st_paused", WatchProc)
    } else if (NextCheck != 0) {
        info := T("st_next", FormatTime(NextCheck, "HH:mm"))
    } else {
        info := ""
    }
    if (UI["infoTxt"].Text != info)
        UI["infoTxt"].Text := info
    ; pause button and cloud name
    paused := IsPaused()
    pk := paused ? "prim" : "norm"
    if (UI["pauseKind"] != pk) {
        UI["pauseKind"] := pk
        SetBtnKind(UI["bPause"], pk)
    }
    pt := paused ? T("btn_resume") : T("btn_pause")
    if (UI["bPause"].Text != pt)
        UI["bPause"].Text := pt
    ct := T("st_cloud", CloudDisplayName())
    if (UI["stCloud"].Text != ct)
        UI["stCloud"].Text := ct
    barOn := (Syncing && CurPage = PG_STATUS)
    UI["barFill"].Visible := barOn
    if barOn
        BarTick()
    SetTimer(BarTick, barOn ? 60 : 0)

    ; folder rows: with many folders the ones that need attention come first
    order := []
    for pr in [0, 1, 2, 3, 4] {
        for nm in Folders {
            if (FolderPriority(nm) = pr)
                order.Push(nm)
        }
    }
    for i, r in UI["rows"] {
        nm := order[i]
        if (r["name"] != nm) {
            r["name"] := nm
            r["lbl"].Text := nm
            r["path"].Text := Folders[nm]
            r["key"] := ""
        }
        fs := FState[nm]
        key := fs["st"] "|" fs["when"] "|" fs["msg"]
        if (key = r["key"])
            continue
        r["key"] := key
        txt := FolderStatus(fs, &c)
        Recolor(r["dot"], c)
        r["stat"].Text := txt
    }
    if IsObject(UI["fSum"]) {
        nOk := 0, nBad := 0
        for nm in Folders {
            st := FState[nm]["st"]
            if (st = "ok")
                nOk += 1
            else if (st = "error" || st = "conflict")
                nBad += 1
        }
        sumTxt := T("st_summary", Folders.Count, nOk, nBad)
        if (UI["fSum"].Text != sumTxt)
            UI["fSum"].Text := sumTxt
    }
    RefreshFolderStatus()
    RefreshActivity()
    UpdateConfBadge()
}

; Indeterminate progress bar: a segment that slides along the track
BarTick() {
    if (!MainBuilt || !Syncing)
        return
    UI["barTrack"].GetPos(&tx, &ty, &tw, &th)
    seg := Round(tw * 0.25)
    pos := Mod(A_TickCount // 6, tw + seg) - seg
    l := Max(0, pos)
    r := Min(tw, pos + seg)
    if (r <= l) {
        UI["barFill"].Visible := false
        return
    }
    UI["barFill"].Visible := true
    UI["barFill"].Move(tx + l, ty, r - l, th)
}

; Last events on the Status page
RefreshActivity() {
    n := 0
    for a in UI["act"] {
        idx := History.Length - n
        if (idx >= 1) {
            h := History[idx]
            a["ts"].Text := FormatTime(h["ts"], T("fmt_date"))
            a["ev"].Text := EvMap.Get(h["ev"], h["ev"])
            Recolor(a["ev"], EvColor(h["ev"]))
            a["file"].Text := h["rel"]
        } else {
            a["ts"].Text := "", a["ev"].Text := "", a["file"].Text := ""
        }
        n += 1
    }
    UI["actEmpty"].Visible := (History.Length = 0 && CurPage = PG_STATUS)
}

; ---- error details (the banner only has room for two lines) ----
LogSize() {
    return FileExist(LogFile) ? FileGetSize(LogFile) : 0
}

LogSince(pos) {
    txt := ""
    try {
        f := FileOpen(LogFile, "r", "UTF-8")
        if (pos > f.Length)
            pos := 0
        f.Pos := pos
        txt := f.Read()
        f.Close()
    }
    return txt
}

LastErrors(n := 20) {
    txt := ""
    try {
        txt := FileRead(LogFile, "UTF-8")
    }
    if (StrLen(txt) > 60000)
        txt := SubStr(txt, -60000)
    lines := []
    for line in StrSplit(txt, "`n", "`r") {
        if RegExMatch(line, "(ERROR|NOTICE|CRITICAL)\s*:|^Tip:|^Path[12]:|^rclone ")
            lines.Push(RegExReplace(line, "^\d{4}/\d\d/\d\d "))
    }
    out := ""
    start := Max(1, lines.Length - n + 1)
    Loop lines.Length - start + 1
        out .= lines[start + A_Index - 1] "`n"
    return Trim(out, "`n")
}

ShowDetails(*) {
    if (TipKind = "conflict" && PendingConflicts() > 0 && IsObject(MainGui)) {
        ShowPage(PG_CONF)
        return
    }
    body := LastTip
    errs := LastErrors(24)
    body .= "`n`n" . (errs != "" ? errs : T("det_none"))
    d := Gui(IsObject(MainGui) ? ("+Owner" MainGui.Hwnd) : "", T("det_title"))
    d.BackColor := TH.Has("bg") ? TH["bg"] : "F2F4F8"
    d.MarginX := 14
    d.MarginY := 14
    d.SetFont("s9 norm", "Segoe UI")
    e := AddEdit(d, "", 14, 14, 680, body, "r16 ReadOnly -Wrap +HScroll +VScroll")
    AddBtn(d, "", 14, 14 + 16 * 19 + 24, 150, 32, T("o_open_log"), MenuOpenLog)
    AddBtn(d, "", 172, 14 + 16 * 19 + 24, 110, 32, T("btn_close"), (*) => d.Destroy(), "prim")
    d.OnEvent("Close", (*) => d.Destroy())
    d.OnEvent("Escape", (*) => d.Destroy())
    d.Show("w708")
}

; Names of the rclone connections ("name:" per line); "" if it could not be read.
RemoteNames() {
    tmp := A_Temp "\syncdood_remotes.txt"
    try {
        FileDelete(tmp)
    }
    try {
        RunWait(Format('{1} /c ""{2}" listremotes > "{3}""', A_ComSpec, Rclone, tmp), , "Hide")
    }
    txt := ""
    try {
        txt := FileRead(tmp)
    }
    try {
        FileDelete(tmp)
    }
    return StrReplace(txt, "`r", "")
}

; ---------------------------------------------------------------- History ----
RefreshHistory() {
    global HistKeys
    if (!MainBuilt || !IsObject(MainGui))
        return
    HistKeys := []
    HistLV.Opt("-Redraw")
    HistLV.Delete()
    Loop History.Length {
        h := History[History.Length - A_Index + 1]
        if (HistFilterName != "" && h["folder"] != HistFilterName)
            continue
        HistLV.Add(, FormatTime(h["ts"], T("fmt_date")), h["folder"], EvMap.Get(h["ev"], h["ev"]), h["rel"], FormatSize(h["size"]))
        HistKeys.Push(h["ev"])
    }
    HistLV.Opt("+Redraw")
    UI["histEmpty"].Visible := (HistKeys.Length = 0 && CurPage = PG_HIST)
    RefreshActivity()
}

; ---------------------------------------------------------------- Folders ----
FillFolders() {
    selName := ""
    row := FolderLV.GetNext(0)
    if (row > 0)
        selName := FolderLV.GetText(row, 1)
    flt := UI.Has("fSearch") ? Trim(UI["fSearch"].Value) : ""
    FolderLV.Opt("-Redraw")
    FolderLV.Delete()
    shown := 0
    selRow := 0
    for name, path in Folders {
        if (flt != "" && !InStr(name, flt) && !InStr(path, flt))
            continue
        n := ExcludePatterns(name).Length
        shown += 1
        shownPath := path
        if (FolderRaw.Get(name, path) != path)
            shownPath .= "   [" T("f_portable_tag") "]"
        FolderLV.Add(, name, shownPath, FolderStatus(FState.Get(name, ""), &c), (n > 0) ? (OnlyMode(name) ? T("ex_only") : T("ex_rules", n)) : "—")
        if (name = selName)
            selRow := shown
    }
    if (selRow > 0)
        FolderLV.Modify(selRow, "Select Focus")
    FolderLV.Opt("+Redraw")
    if UI.Has("fCount")
        UI["fCount"].Text := (flt = "") ? T("f_count", Folders.Count) : T("f_count_f", shown, Folders.Count)
}

; Text (and color) that describes the sync state of one folder
FolderStatus(fs, &c) {
    c := TH["info"]
    if !IsObject(fs)
        return T("st_folder_wait")
    switch fs["st"] {
        case "syncing":
            c := TH["accent"]
            return T("st_folder_syncing")
        case "ok":
            c := TH["ok"]
            return T("st_folder_ok", fs["when"])
        case "conflict":
            c := TH["warn"]
            return T("st_folder_conflict", fs["when"])
        case "error":
            c := TH["err"]
            return T("st_folder_error", fs["msg"])
        case "pending":
            return T("st_folder_pending")
    }
    return T("st_folder_wait")
}

; Lighter than FillFolders: only the "Status" column of the rows already shown
RefreshFolderStatus() {
    if !IsObject(FolderLV)
        return
    Loop FolderLV.GetCount() {
        txt := FolderStatus(FState.Get(FolderLV.GetText(A_Index, 1), ""), &c)
        if (FolderLV.GetText(A_Index, 3) != txt)
            FolderLV.Modify(A_Index, "Col3", txt)
    }
}

; ============================================================================
;  Folder dialog: add a folder, add one that already exists in the cloud, or edit a folder's options.
;    mode "add"   : new folder (the path is picked first)
;    mode "cloud" : a folder that already exists in the cloud (the name is fixed, you choose where it goes on this PC)
;    mode "edit"  : options of an existing folder (exclusions, empty folders)
;  Everything is decided in this one window: name, location (portable if possible), what to sync (tree with
;  check boxes), extra rules and whether empty folders are synced too.
; ============================================================================
FolderDialog(mode, name := "", preset := "") {
    isEdit := (mode = "edit")
    isCloud := (mode = "cloud")
    W := 668
    st := Map("trunc", false, "port", "", "auto", "", "advInit", false, "shown", false, "dy", 0, "h", 0, "onlyInit", (mode = "edit" && OnlyMode(name)))
    nodes := Map()                                  ; tree item id -> [relative path, is folder, checked]
    cur := isEdit ? ExcludePatterns(name) : []
    managed := Map()                                ; rules the tree can show (a plain path): key -> rule
    advLines := []                                  ; rules the tree cannot show (wildcards...)
    for ln0 in cur {
        mk := ManagedRuleKey(ln0)
        if (mk != "")
            managed[mk] := ln0
        else
            advLines.Push(ln0)
    }
    canEmpty := KeepsEmptyDirs()
    advList := []                                   ; controls of the "choose what to sync" block (hidden in simple mode)
    lowList := []                                   ; controls below it (they move up when the block is hidden)
    lowY := []
    cloudTop := []                                  ; what the cloud folder holds (only when adding from the cloud)
    if isCloud {
        ToolTip(T("cf_looking"))
        cloudTop := CloudTopLs(Remote "/" name)
        ToolTip()
    }
    lCloud := ""

    ; ---- behavior (defined first; it uses the controls created below) ------------------------------
    AddRule(txt, *) {
        for ln in StrSplit(eAdv.Value, "`n", "`r") {
            if (StrLower(Trim(ln)) = StrLower(txt))
                return
        }
        v := RTrim(eAdv.Value, "`r`n")
        eAdv.Value := (v = "" ? "" : v "`r`n") txt "`r`n"
    }

    Recount() {
        on := 0
        for id in nodes {
            if tv.Get(id, "Check")
                on += 1
        }
        off := nodes.Count - on
        warnNone := (nodes.Count > 0 && on = 0)
        if (nodes.Count = 0)
            txt2 := T("fd_tree_empty")
        else if warnNone
            txt2 := T("fd_none")
        else if tOnly["on"]
            txt2 := T("fd_count_only", on)
        else if (off = 0)
            txt2 := T("fd_all_synced", on)
        else
            txt2 := T("fd_count", on, off)
        if (st["trunc"] && nodes.Count > 0)
            txt2 .= "  ·  " T("fd_tree_trunc", ExcTreeMax())
        lInfo.SetFont("s9 " (warnNone ? "bold c" TH["warn"] : "norm c" TH["sub"]))
        lInfo.Text := txt2
    }

    ; simple mode (sync everything) or "choose what to sync" (tree)
    ApplyMode(resize := true) {
        simple := !tChoose["on"]
        for c in advList
            c.Visible := !simple
        lSimple.Visible := simple
        if (lowY.Length = 0) {
            for c in lowList {
                c.GetPos(, &yy)
                lowY.Push(yy)
            }
        }
        dy := simple ? st["dy"] : 0
        for i, c in lowList
            c.Move(, lowY[i] - dy)
        if (resize && st["shown"])
            d.Show("w" (W + 32) " h" (st["h"] - dy))
    }

    UpdateSimple() {
        absp := RTrim(ExpandPath(ePath.Value), "\")
        txt3 := (nodes.Count = 0) ? T("fd_simple_empty", absp) : T("fd_simple", absp, st["trunc"] ? "4,000+" : nodes.Count)
        if !isCloud
            txt3 .= "`n" T("fd_tip_sub")
        lSimple.Text := txt3
    }

    ; the cloud folder already holds a folder called like the chosen one? (that would nest it: settings\settings)
    CloudDupDir(leaf) {
        for it in cloudTop {
            if (SubStr(it, -1) = "/" && leaf != "" && StrLower(RTrim(it, "/")) = StrLower(leaf))
                return RTrim(it, "/")
        }
        return ""
    }

    UpdateCloudInfo() {
        if !isCloud
            return
        absp := RTrim(ExpandPath(ePath.Value), "\")
        SplitPath(absp, &leaf, &parent)
        dup := CloudDupDir(leaf)
        if (dup != "") {
            lCloud.SetFont("s8 bold c" TH["warn"])
            lCloud.Text := T("fd_cloud_warn", name, dup, parent)
            return
        }
        lCloud.SetFont("s8 norm c" TH["sub"])
        if (cloudTop.Length = 0) {
            lCloud.Text := T("fd_cloud_empty", name)
            return
        }
        lst := ""
        for i, it in cloudTop {
            if (i > 6) {
                lst .= ", … (+" (cloudTop.Length - 6) ")"
                break
            }
            lst .= (i > 1 ? ", " : "") StrReplace(it, "/", "\")
        }
        lCloud.Text := T("fd_cloud_info", name, lst)
    }

    UpdatePortable() {
        rawp := Trim(ePath.Value)
        port := (rawp != "" && !InStr(rawp, "%")) ? PortablePath(ExpandPath(rawp)) : ""
        st["port"] := port
        show := (port != "" && !isEdit)
        tPort["box"].Visible := show
        tPort["lbl"].Visible := show
        if show
            tPort["lbl"].Text := T("fd_portable", port)
    }

    LoadTree() {
        absp := RTrim(ExpandPath(ePath.Value), "\")
        tv.Opt("-Redraw")
        tv.Delete()
        nodes.Clear()
        used := Map()
        ctx := Map("count", 0, "max", ExcTreeMax(), "trunc", false, "managed", managed, "used", used, "only", st["onlyInit"]
            , "iF", iFolder ? " Icon" iFolder : "", "iD", iFile ? " Icon" iFile : "")
        if (absp != "" && DirExist(absp))
            ExcTreeFill(tv, nodes, absp, "", 0, st["onlyInit"], ctx)
        tv.Opt("+Redraw")
        st["trunc"] := ctx["trunc"]
        if !st["advInit"] {
            ; first load: rules that matched nothing in the tree stay as text rules (they are not lost)
            st["advInit"] := true
            extra := ""
            for mk2, rule in managed {
                if !used.Has(mk2)
                    extra .= rule "`r`n"
            }
            if (extra != "")
                eAdv.Value := eAdv.Value extra
        }
        Recount()
        UpdateSimple()
        UpdateCloudInfo()
    }

    ; "Only sync what is checked": the extra rules do not apply, the count message changes
    OnlyChanged(*) {
        on := tOnly["on"]
        eAdv.Enabled := !on
        advLbl.Text := T(on ? "fd_adv_off" : "fd_adv")
        Recount()
    }

    ; "Check all" / "Uncheck all" buttons
    SetAll(on, *) {
        tv.Opt("-Redraw")
        for id, nd in nodes {
            nd[3] := on
            tv.Modify(id, on ? "Check" : "-Check")
        }
        tv.Opt("+Redraw")
        Recount()
    }

    ; a check box was clicked: a folder takes everything inside it along; checking something re-checks its parents.
    ; Done a moment later, when Windows has already updated the box, by comparing what is shown with what we know.
    OnCheck(ctrl, item, *) {
        SetTimer(Reconcile, -25)
    }

    Reconcile() {
        for id, nd in nodes {
            if ((tv.Get(id, "Check") ? true : false) != nd[3]) {
                ExcTreeApply(tv, nodes, id, !nd[3])
                break
            }
        }
        Recount()
    }

    Browse() {
        start := (Trim(ePath.Value) != "") ? RTrim(ExpandPath(ePath.Value), "\") : ""
        picked := SelectFolder(isCloud ? T("pick_cloud", name) : T("pick_add"), start, d.Hwnd)
        if (picked = "")
            return
        picked := RTrim(picked, "\")
        ePath.Value := picked
        if !isCloud {
            SplitPath(picked, &leaf)
            leaf := RegExReplace(leaf, "[^\w\-]", "_")
            if (Trim(eName.Value) = "" || eName.Value = st["auto"]) {
                eName.Value := leaf
                st["auto"] := leaf
            }
        }
        UpdatePortable()
        LoadTree()
    }

    PathChanged(*) {
        UpdatePortable()
        SetTimer(LoadTree, -700)
    }

    AddPat(pats, seen, ln) {
        ln := Trim(ln)
        ; rclone reads "\" as an escape: turn Windows paths (shaders\) into "/" (keeps \* \? etc.)
        ln := RegExReplace(ln, "\\(?![*?\[\]{}!\\])", "/")
        if (ln = "" || SubStr(ln, 1, 1) = "#" || SubStr(ln, 1, 1) = ";")
            return
        if seen.Has(StrLower(ln))
            return
        seen[StrLower(ln)] := true
        pats.Push(ln)
    }

    Accept(*) {
        if (!isEdit && CheckBusy())      ; adding restarts the app: wait for a running sync
            return
        nm := (isCloud || isEdit) ? name : RegExReplace(Trim(eName.Value), "[^\w\-]", "_")
        rawText := Trim(ePath.Value)
        absp := RTrim(ExpandPath(rawText), "\")
        if !isEdit {
            ; wrong level? the cloud folder already holds a folder with the name of the chosen one
            if isCloud {
                SplitPath(absp, &leafA, &parentA)
                dupA := CloudDupDir(leafA)
                if (dupA != "") {
                    r := MsgBox(T("fd_cloud_fix", absp, name, dupA, parentA), "SyncDood", "YesNoCancel Icon! Default1")
                    if (r = "Cancel")
                        return
                    if (r = "Yes") {
                        ePath.Value := parentA
                        UpdatePortable()
                        LoadTree()
                        return
                    }
                }
            }
            ; very general folders (Documents, Desktop, the user folder, a whole drive...)
            if (IsBroadFolder(absp) && MsgBox(T("fd_root_confirm", absp), "SyncDood", "YesNo Icon! Default2") != "Yes")
                return
            if (nm = "") {
                MsgBox(T("fd_err_name"), "SyncDood", "Iconx")
                return
            }
            for fn in Folders {
                if (StrLower(fn) = StrLower(nm)) {
                    MsgBox(T("f_dup_name"), "SyncDood", "Iconx")
                    return
                }
            }
            if ReservedName(nm) {
                MsgBox(T("f_reserved"), "SyncDood", "Iconx")
                return
            }
            if !RegExMatch(absp, "^([A-Za-z]:\\|\\\\)[^\\]") {
                MsgBox(T("fd_err_abs"), "SyncDood", "Iconx")
                return
            }
            for fn, ep in Folders {
                if (StrLower(ep) = StrLower(absp)) {
                    MsgBox(T("f_dup_path"), "SyncDood", "Iconx")
                    return
                }
            }
            if (PathInside(BackupDir, absp) || PathInside(absp, BackupDir)) {
                MsgBox(T("f_inside_backup", BackupDir), "SyncDood", "Iconx")
                return
            }
            if !DirExist(absp) {
                if (MsgBox(T("fd_create_ask", absp), "SyncDood", "YesNo Icon?") != "Yes")
                    return
                try {
                    DirCreate(absp)
                } catch {
                    MsgBox(T("fd_err_abs"), "SyncDood", "Iconx")
                    return
                }
            }
        }

        ; a huge folder is usually the wrong one (for example "Documents" instead of the game's folder)
        if (!isEdit && st["trunc"] && MsgBox(T("fd_big_confirm", absp), "SyncDood", "YesNo Icon! Default2") != "Yes")
            return

        ; everything unchecked = nothing would sync (usually a slip): ask for at least one item
        if (tChoose["on"] && tOnly["on"] && st["trunc"]) {
            MsgBox(T("fd_only_trunc"), "SyncDood", "Iconx")
            return
        }
        if (tChoose["on"] && nodes.Count > 0) {
            anyOn := false
            for id in nodes {
                if tv.Get(id, "Check") {
                    anyOn := true
                    break
                }
            }
            if !anyOn {
                MsgBox(T("fd_err_none"), "SyncDood", "Iconx")
                return
            }
        }

        ; rules: what was unchecked in the tree + the text rules
        pats := []
        seen := Map()
        onlyOn := (tChoose["on"] && tOnly["on"])
        if onlyOn {                       ; whitelist: the checked items are the rules
            for rl in ExcTreeAllow(tv, nodes, [])
                AddPat(pats, seen, rl)
        } else if tChoose["on"] {         ; simple mode = sync everything: no exclusions
            for rl in ExcTreeRules(tv, nodes, [])
                AddPat(pats, seen, rl)
            for ln in StrSplit(eAdv.Value, "`n", "`r")
                AddPat(pats, seen, ln)
        }
        SaveExclusions(nm, pats, onlyOn)
        if canEmpty
            IniWrite(tEmpty["on"] ? "1" : "0", IniFile, "emptydirs", nm)

        if isEdit {
            FillFolders()
            d.Destroy()
            return
        }
        rawOut := absp
        if InStr(rawText, "%")
            rawOut := rawText
        else if (tPort["on"] && st["port"] != "")
            rawOut := st["port"]
        Folders[nm] := absp
        FolderRaw[nm] := rawOut
        SaveFolders()
        ForgetFolder(nm)              ; a new folder: its own first sync
        d.Destroy()
        RestartApp(PG_FOLDERS)
    }

    ; ---- window ------------------------------------------------------------------------------------
    title := isEdit ? T("fd_title_edit", name) : (isCloud ? T("fd_title_cloud") : T("fd_title_add"))
    d := Gui("+Owner" MainGui.Hwnd, title)
    d.BackColor := TH["bg"]
    d.MarginX := 16
    d.MarginY := 14
    d.SetFont("s9 norm", "Segoe UI")

    y := 14
    AddTxt(d, "", Format("x16 y{1} w190 h20 +0x200", y), T("fd_name"), "s9 bold", TH["text"], TH["bg"])
    AddTxt(d, "", Format("x222 y{1} w{2} h20 +0x200", y, W - 206), T("fd_path"), "s9 bold", TH["text"], TH["bg"])
    y += 22
    eName := AddEdit(d, "", 16, y, 190, (isEdit || isCloud) ? name : "", (isEdit || isCloud) ? "ReadOnly" : "")
    startPath := isEdit ? Folders[name] : preset
    ePath := AddEdit(d, "", 222, y, isEdit ? W - 206 : W - 206 - 108, startPath, isEdit ? "ReadOnly" : "")
    bBrowse := AddBtn(d, "", 16 + W - 100, y - 2, 100, 26, T("fd_browse"), (*) => Browse())
    bBrowse.Visible := !isEdit
    y += 34
    tPort := AddToggle(d, "", 16, y, W, T("fd_portable", "%DOCUMENTS%"), true)
    y += 34

    if isCloud {
        lCloud := AddTxt(d, "", Format("x16 y{1} w{2} h54", y, W), "", "s8 norm", TH["sub"], TH["bg"])
        y += 58
    }
    tChoose := AddToggle(d, "", 16, y, W, T("fd_choose"), isEdit && cur.Length > 0)
    y += 32
    yBlock := y
    lSimple := AddTxt(d, "", Format("x16 y{1} w{2} h60", y, W), "", "s9 norm", TH["sub"], TH["bg"])

    ; ---- block "choose what to sync" (tree + extra rules); it starts at the same place as the simple text
    AddTxt(d, advList, Format("x16 y{1} w{2} h24 +0x200", y, W - 290), T("fd_tree"), "s9 bold", TH["text"], TH["bg"])
    AddBtn(d, advList, 16 + W - 282, y - 1, 136, 26, T("fd_checkall"), (*) => SetAll(true))
    AddBtn(d, advList, 16 + W - 140, y - 1, 140, 26, T("fd_uncheckall"), (*) => SetAll(false))
    y += 28
    AddTxt(d, advList, Format("x16 y{1} w{2} h34", y, W), T("fd_tree_help"), "s8 norm", TH["sub"], TH["bg"])
    y += 38
    d.SetFont("s9 norm c" TH["text"], "Segoe UI")
    tv := d.Add("TreeView", Format("x16 y{1} w{2} h130 Checked c{3} Background{4}", y, W, TH["text"], TH["card"]))
    advList.Push(tv)
    il := IL_Create(2)
    iFolder := IL_Add(il, "shell32.dll", 4)
    iFile := IL_Add(il, "shell32.dll", 1)
    try {
        tv.SetImageList(il)
    }
    try {
        DllCall("uxtheme\SetWindowTheme", "Ptr", tv.Hwnd, "Str", DarkNow ? "DarkMode_Explorer" : "Explorer", "Ptr", 0)
    }
    y += 134
    lInfo := AddTxt(d, advList, Format("x16 y{1} w{2} h20 +0x200", y, W), "", "s9 norm", TH["sub"], TH["bg"])
    y += 26
    tOnly := AddToggle(d, advList, 16, y, W, T("fd_only"), st["onlyInit"])
    y += 26
    AddTxt(d, advList, Format("x48 y{1} w{2} h30", y, W - 32), T("fd_only_help"), "s8 norm", TH["sub"], TH["bg"])
    y += 34

    advLbl := AddTxt(d, advList, Format("x16 y{1} w200 h26 +0x200", y), T("fd_adv"), "s9 bold", TH["text"], TH["bg"])
    xs := 222
    for sug in ["*.log", "*.tmp", "shaders/", "cache/", "*.qcow2"] {
        bw := 36 + StrLen(sug) * 7
        AddBtn(d, advList, xs, y, bw, 26, "+ " sug, AddRule.Bind(sug))
        xs += bw + 6
    }
    y += 30
    advTxt := ""
    for ln0 in advLines
        advTxt .= ln0 "`r`n"
    eAdv := AddEdit(d, advList, 16, y, W, advTxt, "r2 -Wrap +VScroll")
    y += 50
    st["dy"] := (y - yBlock) - 64                   ; how much the controls below move up in simple mode

    tEmpty := AddToggle(d, lowList, 16, y, W, T("fd_empty"), canEmpty && (isEdit ? EmptyDirsFor(name) : true))
    y += 26
    AddTxt(d, lowList, Format("x48 y{1} w{2} h34", y, W - 32), T(canEmpty ? "fd_empty_help" : "fd_empty_b2"), "s8 norm", TH["sub"], TH["bg"])
    if !canEmpty {
        tEmpty["box"].Enabled := false
        tEmpty["lbl"].Enabled := false
    }
    y += 44

    AddBtn(d, lowList, 16, y, 150, 34, T(isEdit ? "ex_save" : "fd_add"), (*) => Accept(), "prim", "s9 bold")
    AddBtn(d, lowList, 174, y, 110, 34, T("cd_cancel"), (*) => d.Destroy())
    y += 48
    st["h"] := y

    tv.OnEvent("ItemCheck", OnCheck)
    if !isEdit
        ePath.OnEvent("Change", PathChanged)
    d.OnEvent("Close", (*) => d.Destroy())
    d.OnEvent("Escape", (*) => d.Destroy())
    if (preset != "" && !isCloud) {
        SplitPath(preset, &leaf0)
        leaf0 := RegExReplace(leaf0, "[^\w\-]", "_")
        eName.Value := leaf0
        st["auto"] := leaf0
    }
    tOnly["box"].OnEvent("Click", OnlyChanged)
    tOnly["lbl"].OnEvent("Click", OnlyChanged)
    OnlyChanged()
    tChoose["box"].OnEvent("Click", (*) => ApplyMode())
    tChoose["lbl"].OnEvent("Click", (*) => ApplyMode())
    UpdatePortable()
    LoadTree()
    ApplyMode(false)
    st["shown"] := true
    d.Show("w" (W + 32) " h" (st["h"] - (tChoose["on"] ? 0 : st["dy"])))
}

; Direct contents of a cloud folder; folders end with "/". [] if it is empty or can't be read.
CloudTopLs(path) {
    tmp := A_Temp "\syncdood_cloudtop.txt"
    try {
        FileDelete(tmp)
    }
    code := -1
    try {
        code := RunWait(Format('{1} /c ""{2}" lsf "{3}" > "{4}""', A_ComSpec, Rclone, path, tmp), , "Hide")
    }
    txt := ""
    try {
        txt := FileRead(tmp, "UTF-8")
    }
    try {
        FileDelete(tmp)
    }
    out := []
    if (code != 0)
        return out
    for line in StrSplit(txt, "`n", "`r") {
        if (line != "")
            out.Push(line)
    }
    return out
}

; A folder that is almost never the one you want to sync as a whole (user folder, Documents, Desktop, a drive...)
IsBroadFolder(p) {
    p := StrLower(RTrim(p, "\"))
    if RegExMatch(p, "^[a-z]:$")
        return true
    up := EnvGet("USERPROFILE")
    for b in [up, A_MyDocuments, A_Desktop, up "\Downloads", EnvGet("APPDATA"), EnvGet("LOCALAPPDATA")] {
        if (b != "" && StrLower(RTrim(b, "\")) = p)
            return true
    }
    return false
}

; Writes (or deletes) the exclusion rules file of a folder
SaveExclusions(name, pats, only := false) {
    f := ExcludeFile(name)
    if (pats.Length = 0) {
        try {
            FileDelete(f)
        }
        return
    }
    DirCreate(AppDir "\exclude")
    out := "# SyncDood exclusions for '" name "' (rclone syntax, one rule per line)`n"
    if only
        out .= "#only-checked`n"
    for pt in pats
        out .= pt "`n"
    try {
        FileDelete(f)
    }
    FileAppend(out, f, "UTF-8-RAW")
}

; ---- the exclusions tree ----------------------------------------------------------------------------
ExcTreeMax() {
    return 4000
}

; A rule that is just a path (/saves/slot1/ or /saves/a.sav) -> "saves/slot1/" (lower case); "" if it has wildcards
ManagedRuleKey(line) {
    if (SubStr(line, 1, 1) != "/")
        return ""
    s := SubStr(line, 2)
    if RegExMatch(s, "(?<!\\)[*?\[\]{}]")
        return ""
    s := RegExReplace(s, "\\([*?\[\]{}!\\])", "$1")
    return (s = "") ? "" : StrLower(s)
}

; Escapes the characters rclone treats as wildcards ([USA] -> \[USA\])
EscapeGlob(s) {
    return RegExReplace(s, "([*?\[\]{}])", "\$1")
}

; Fills the TreeView with what is inside dirPath (folders first, then files).
; Items are checked (= synced) unless a rule excludes them; everything under an excluded folder is unchecked.
ExcTreeFill(tv, nodes, dirPath, rel, parentId, parentOff, ctx) {
    dirs := [], files := []
    Loop Files dirPath "\*", "D"
        dirs.Push(A_LoopFileName)
    Loop Files dirPath "\*", "F"
        files.Push(A_LoopFileName)
    for kind in [1, 2] {
        for nm in (kind = 1 ? dirs : files) {
            if (ctx["count"] >= ctx["max"]) {
                ctx["trunc"] := true
                return
            }
            ctx["count"] += 1
            r := (rel = "") ? nm : rel "/" nm
            key := StrLower(r) (kind = 1 ? "/" : "")
            off := parentOff
            chk := false
            if ctx["only"] {
                ; the rules are the items that ARE synced: checked if listed (or inside a listed folder),
                ; and a folder is also checked when something inside it is listed
                full := (!parentOff || ctx["managed"].Has(key))
                if ctx["managed"].Has(key)
                    ctx["used"][key] := true
                chk := full
                if (!chk && kind = 1) {
                    for mk3 in ctx["managed"] {
                        if (SubStr(mk3, 1, StrLen(key)) = key) {
                            chk := true
                            break
                        }
                    }
                }
                off := !full
            } else {
                if ctx["managed"].Has(key) {
                    ctx["used"][key] := true
                    off := true
                }
                chk := !off
            }
            id := tv.Add(nm, parentId, (chk ? "Check" : "") (kind = 1 ? ctx["iF"] : ctx["iD"]))
            nodes[id] := [r, kind = 1, chk]
            if (kind = 1)
                ExcTreeFill(tv, nodes, dirPath "\" nm, r, id, off, ctx)
        }
    }
}

; An item was checked / unchecked by the user: everything inside follows it, and checking also re-checks its parents
ExcTreeApply(tv, nodes, item, on) {
    nodes[item][3] := on
    ExcTreeDown(tv, nodes, item, on)
    if on {
        p := tv.GetParent(item)
        while p {
            if !nodes[p][3] {
                nodes[p][3] := true
                tv.Modify(p, "Check")
            }
            p := tv.GetParent(p)
        }
    }
}

ExcTreeDown(tv, nodes, id, on) {
    c := tv.GetChild(id)
    while c {
        if (nodes[c][3] != on) {
            nodes[c][3] := on
            tv.Modify(c, on ? "Check" : "-Check")
        }
        ExcTreeDown(tv, nodes, c, on)
        c := tv.GetNext(c)
    }
}

; Rules for the unchecked items: a whole unchecked folder is one rule; inside a checked folder each unchecked item is
ExcTreeRules(tv, nodes, out, id := 0) {
    c := id ? tv.GetChild(id) : tv.GetNext()
    while c {
        nd := nodes[c]
        if !tv.Get(c, "Check") {
            out.Push("/" EscapeGlob(nd[1]) (nd[2] ? "/" : ""))
        } else if nd[2] {
            ExcTreeRules(tv, nodes, out, c)
        }
        c := tv.GetNext(c)
    }
    return out
}

; Paths for "only sync what is checked": a fully checked folder is one rule, otherwise each checked item
ExcTreeAllow(tv, nodes, out, id := 0) {
    c := id ? tv.GetChild(id) : tv.GetNext()
    while c {
        nd := nodes[c]
        if tv.Get(c, "Check") {
            if nd[2] {
                if ExcTreeAllChecked(tv, c)
                    out.Push("/" EscapeGlob(nd[1]) "/")
                else
                    ExcTreeAllow(tv, nodes, out, c)
            } else {
                out.Push("/" EscapeGlob(nd[1]))
            }
        }
        c := tv.GetNext(c)
    }
    return out
}

ExcTreeAllChecked(tv, id) {
    c := tv.GetChild(id)
    while c {
        if (!tv.Get(c, "Check") || !ExcTreeAllChecked(tv, c))
            return false
        c := tv.GetNext(c)
    }
    return true
}

; Does this folder also sync its empty sub-folders? (the default is what the cloud supports)
EmptyDirsFor(name) {
    v := IniRead(IniFile, "emptydirs", name, "")
    if (v = "")
        return KeepsEmptyDirs()
    return (v = "1" && KeepsEmptyDirs())
}

; "Add from the cloud": folders that exist in the cloud but are not set up on this PC
AddFromCloudUI(*) {
    global CloudListFail
    if CheckBusy()
        return
    CloudListFail := false
    ToolTip(T("cf_looking"))
    names := []
    for nm in CloudLs(Remote, true) {
        if (nm != "" && !ReservedName(nm) && !Folders.Has(nm))
            names.Push(nm)
    }
    ToolTip()
    if CloudListFail {
        MsgBox(T("cf_fail"), "SyncDood", "Iconx")
        return
    }
    if (names.Length = 0) {
        MsgBox(T("cf_none"), "SyncDood", "Iconi")
        return
    }

    d := Gui("+Owner" MainGui.Hwnd, T("cf_title"))
    d.BackColor := TH["bg"]
    d.MarginX := 16
    d.MarginY := 14
    d.SetFont("s9 norm", "Segoe UI")
    AddTxt(d, "", "x16 y14 w440 h44", T("cf_help"), "s9 norm", TH["sub"], TH["bg"])
    d.SetFont("s9 norm c" TH["text"], "Segoe UI")
    lv := d.Add("ListView", Format("x16 y64 w440 h220 -Hdr -Multi -E0x200 c{1} Background{2}", TH["text"], TH["card"]), [T("f_col_name")])
    for nm in names
        lv.Add(, nm)
    lv.ModifyCol(1, 410)
    try {
        DllCall("uxtheme\SetWindowTheme", "Ptr", lv.Hwnd, "Str", DarkNow ? "DarkMode_Explorer" : "Explorer", "Ptr", 0)
    }

    Pick(*) {
        row := lv.GetNext(0)
        if (row = 0) {
            MsgBox(T("f_nosel"), "SyncDood", "Iconi")
            return
        }
        chosen := lv.GetText(row, 1)
        d.Destroy()
        loc := SelectFolder(T("pick_cloud", chosen), "", MainGui.Hwnd)
        if (loc = "")
            return
        FolderDialog("cloud", chosen, RTrim(loc, "\"))
    }
    AddBtn(d, "", 16, 300, 150, 34, T("cf_next"), Pick, "prim", "s9 bold")
    AddBtn(d, "", 174, 300, 110, 34, T("cd_cancel"), (*) => d.Destroy())
    lv.OnEvent("DoubleClick", Pick)
    d.OnEvent("Close", (*) => d.Destroy())
    d.OnEvent("Escape", (*) => d.Destroy())
    d.Show("w472 h350")
}

; Pick the folder first, then the dialog with the rest of the options
AddFolderUI(*) {
    if CheckBusy()
        return
    p := SelectFolder(T("pick_add"), "", MainGui.Hwnd)
    if (p = "")
        return
    FolderDialog("add", "", RTrim(p, "\"))
}

; Options of the selected folder (exclusions tree, empty folders)
ExcludeUI(*) {
    name := SelectedFolder()
    if (name = "")
        return
    FolderDialog("edit", name)
}

; true if path a is the same as b or inside it (case-insensitive)
PathInside(a, b) {
    a := StrLower(RTrim(a, "\")), b := StrLower(RTrim(b, "\"))
    return (a != "" && b != "" && (a = b || SubStr(a, 1, StrLen(b) + 1) = b "\"))
}

; name of the first synced folder that overlaps the backups folder "bk" (inside it or containing it), or ""
BackupOverlap(bk, skip := "") {
    for nm, fp in Folders {
        if (nm = skip)
            continue
        if (PathInside(bk, fp) || PathInside(fp, bk))
            return fp
    }
    return ""
}

; names SyncDood uses inside the cloud for its own things
ReservedName(nm) {
    return (StrLower(nm) = "_backup" || StrLower(nm) = "_pcs")
}

; Returns the selected folder's name, or "" (and tells the user) if none is selected
SelectedFolder() {
    row := FolderLV.GetNext(0)
    if (row = 0) {
        MsgBox(T("f_nosel"), "SyncDood", "Iconi")
        return ""
    }
    return FolderLV.GetText(row, 1)
}

SyncSelectedUI(*) {
    name := SelectedFolder()
    if (name = "")
        return
    if CheckBusy()
        return
    RunSync(T("reason_manual"), false, name)
}

; true (and tells the user) if a sync is running: settings that restart the app wait
CheckBusy() {
    if Syncing {
        MsgBox(T("f_busy"), "SyncDood", "Iconi")
        return true
    }
    return false
}

; Saves the current Folders map to config.ini
SaveFolders() {
    try {
        IniDelete(IniFile, "folders")
    }
    for nm, p in Folders
        IniWrite(FolderRaw.Get(nm, p), IniFile, "folders", nm)
}

; ---- export / import of the configuration (folders, exclusions, options; never passwords or tokens) ----
ConfigKeys := ["language", "theme", "intervalMin", "pauseWhileRunning", "pruneCloudBackups", "backupKeepDays"
    , "firstSyncWins", "maxDeletePct", "watchProcess", "settleSec", "resumeDelaySec"]

ExportConfigUI(*) {
    dest := FileSelect("S16", A_Desktop "\SyncDood-config.ini", T("cfg_export_title"), "SyncDood (*.ini)")
    if (dest = "")
        return
    if !RegExMatch(dest, "i)\.ini$")
        dest .= ".ini"
    try {
        FileDelete(dest)
    }
    try {
        FileAppend("", dest, "UTF-16")     ; IniWrite keeps the file's encoding: UTF-16 so accents survive
        IniWrite("SyncDood", dest, "meta", "app")
        IniWrite(AppVersion, dest, "meta", "version")
        for k in ConfigKeys {
            v := IniRead(IniFile, "general", k, "")
            if (v != "")
                IniWrite(v, dest, "general", k)
        }
        for nm, p in Folders {
            raw := FolderRaw.Get(nm, p)
            if !InStr(raw, "%") {
                port := PortablePath(ExpandPath(raw))
                if (port != "")
                    raw := port
            }
            IniWrite(raw, dest, "folders", nm)
            ed := IniRead(IniFile, "emptydirs", nm, "")
            if (ed != "")
                IniWrite(ed, dest, "emptydirs", nm)
            i := 0
            for pat in ExcludePatterns(nm) {
                i += 1
                IniWrite(pat, dest, "exclude_" nm, i)
            }
            if OnlyMode(nm)
                IniWrite("1", dest, "onlymode", nm)
        }
    } catch as e {
        MsgBox(T("cfg_fail", e.Message), "SyncDood", "Iconx")
        return
    }
    MsgBox(T("cfg_exported", dest), "SyncDood", "Iconi")
}

ImportConfigUI(*) {
    if CheckBusy()
        return
    src := FileSelect(3, A_Desktop, T("cfg_import_title"), "SyncDood (*.ini)")
    if (src = "")
        return
    if (IniRead(src, "meta", "app", "") != "SyncDood") {
        MsgBox(T("cfg_bad"), "SyncDood", "Iconx")
        return
    }
    secTxt := ""
    try {
        secTxt := IniRead(src, "folders")
    }
    names := []
    raws := Map()
    for line in StrSplit(secTxt, "`n", "`r") {
        p := InStr(line, "=")
        if (p > 1) {
            nm := Trim(SubStr(line, 1, p - 1))
            names.Push(nm)
            raws[nm] := RTrim(Trim(SubStr(line, p + 1)), "\")
        }
    }
    if (names.Length = 0) {
        MsgBox(T("cfg_bad"), "SyncDood", "Iconx")
        return
    }
    list := ""
    for nm in names
        list .= "`n - " nm (Folders.Has(nm) ? "  (" T("cfg_replace") ")" : "")
    if (MsgBox(T("cfg_import_ask", names.Length, list), "SyncDood", "YesNo Icon?") != "Yes")
        return
    DirCreate(AppDir "\exclude")
    for nm in names {
        FolderRaw[nm] := raws[nm]
        Folders[nm] := RTrim(ExpandPath(raws[nm]), "\")
        ed := IniRead(src, "emptydirs", nm, "")
        if (ed != "")
            IniWrite(ed, IniFile, "emptydirs", nm)
        pats := ""
        try {
            pats := IniRead(src, "exclude_" nm)
        }
        if (pats != "") {
            out := ""
            for line in StrSplit(pats, "`n", "`r") {
                p := InStr(line, "=")
                if (p > 1)
                    out .= SubStr(line, p + 1) "`n"
            }
            if (IniRead(src, "onlymode", nm, "") = "1")
                out := "#only-checked`n" out
            try {
                FileDelete(ExcludeFile(nm))
            }
            FileAppend(out, ExcludeFile(nm), "UTF-8")
        }
        try {
            IniDelete(IniFile, "firstsync", nm)       ; it will preview and merge on its first sync here
        }
    }
    for k in ConfigKeys {
        v := IniRead(src, "general", k, "")
        if (v != "")
            IniWrite(v, IniFile, "general", k)
    }
    SaveFolders()
    RestartApp(PG_FOLDERS)
}

; Applies a settings change: restarts SyncDood and re-opens the window on the given page
RestartApp(page := 5) {
    SaveHistory()
    IniWrite(page, IniFile, "general", "reopenUI")
    Reload()
}

ChangeFolderUI(*) {
    if CheckBusy()
        return
    name := SelectedFolder()
    if (name = "")
        return
    p := SelectFolder(T("pick_change", name), Folders[name], MainGui.Hwnd)
    if (p = "")
        return
    p := RTrim(p, "\")
    for n, ep in Folders {
        if (n != name && StrLower(ep) = StrLower(p)) {
            MsgBox(T("f_dup_path"), "SyncDood", "Iconx")
            return
        }
    }
    if (PathInside(BackupDir, p) || PathInside(p, BackupDir)) {
        MsgBox(T("f_inside_backup", BackupDir), "SyncDood", "Iconx")
        return
    }
    if (MsgBox(T("f_change_confirm", name, p), "SyncDood", "YesNo Icon?") != "Yes")
        return
    raw := p
    port := PortablePath(p)
    if (port != "" && MsgBox(T("f_portable_ask", port), "SyncDood", "YesNo Icon?") = "Yes")
        raw := port
    Folders[name] := p
    FolderRaw[name] := raw
    SaveFolders()
    ForgetFolder(name)            ; the new path needs its own first sync
    RestartApp(PG_FOLDERS)
}

RemoveFolderUI(*) {
    if CheckBusy()
        return
    name := SelectedFolder()
    if (name = "")
        return
    if (Folders.Count <= 1) {
        MsgBox(T("f_remove_last"), "SyncDood", "Iconx")
        return
    }
    if (MsgBox(T("f_remove_confirm", name), "SyncDood", "YesNo Icon?") != "Yes")
        return
    Folders.Delete(name)
    FolderRaw.Delete(name)
    SaveFolders()
    ForgetFolder(name)
    try {
        IniDelete(IniFile, "emptydirs", name)
    }
    RestartApp(PG_FOLDERS)
}

OpenFolderUI(*) {
    name := SelectedFolder()
    if (name != "")
        Run('explorer.exe "' Folders[name] '"')
}

; ------------------------------------------------------------------ Cloud ----
FillCloud() {
    UI["cloudCur"].Text := CloudDisplayName()
    UI["cloudTgt"].Text := T("c_target", Remote)
}

; Name of the cloud in use. For "your cloud app's folder" it names the app when the path gives it away (MEGA, Google Drive...)
CloudDisplayName() {
    nm := IniRead(IniFile, "general", "cloudName", "")
    id := IniRead(IniFile, "general", "cloudId", "")
    isLocal := RegExMatch(Remote, "i)^([a-z]:\\|\\\\)")
    if (isLocal && (id = "folder" || id = "")) {
        app := CloudAppName(Remote)
        if (app != "")
            return T("c_app_of", app)
    }
    if (nm = "")
        return isLocal ? T("c_local") : T("c_unknown")
    return nm
}

; Which cloud app a local folder belongs to, judging by its path ("" if unknown)
CloudAppName(path) {
    apps := [["MEGA", "mega"], ["Google Drive", "google ?drive|my drive|mi unidad|drive for desktop"], ["OneDrive", "onedrive"]
        , ["Dropbox", "dropbox"], ["iCloud Drive", "icloud"], ["pCloud", "pcloud"], ["Proton Drive", "proton ?drive"]
        , ["Box", "box|box sync"], ["Koofr", "koofr"], ["Nextcloud", "nextcloud"], ["Synology Drive", "synology"]
        , ["Sync.com", "sync\.com"], ["Yandex Disk", "yandex"]]
    for app in apps {
        if RegExMatch(path, "i)(^|[\\ _-])(" app[2] ")([\\ _-]|$)")
            return app[1]
    }
    return ""
}

; "12.4 GB" style size (FormatSize stops at MB)
BigSize(b) {
    b := Number(b)
    if (b < 1024)
        return Round(b) " B"
    if (b < 1048576)
        return Round(b / 1024, 1) " KB"
    if (b < 1073741824)
        return Round(b / 1048576, 1) " MB"
    if (b < 1099511627776)
        return Round(b / 1073741824, 2) " GB"
    return Round(b / 1099511627776, 2) " TB"
}

; Runs rclone with its output saved to a temp file; returns the text ("" if it failed)
RcloneText(args) {
    tmp := A_Temp "\syncdood_out.txt"
    try {
        FileDelete(tmp)
    }
    code := -1
    try {
        code := RunWait(Format('{1} /c ""{2}" {3} > "{4}" 2>nul"', A_ComSpec, Rclone, args, tmp), , "Hide")
    }
    txt := ""
    try {
        txt := FileRead(tmp, "UTF-8")
    }
    try {
        FileDelete(tmp)
    }
    return (code = 0) ? txt : ""
}

; Space by folder: this PC, cloud, and the backups (cloud and local) of every folder
SpacePanelUI(*) {
    d := Gui("+Owner" MainGui.Hwnd, T("sp_title"))
    d.BackColor := TH["bg"]
    d.MarginX := 16
    d.MarginY := 14
    d.SetFont("s9 norm", "Segoe UI")
    AddTxt(d, "", "x16 y14 w640 h22", T("sp_help"), "s9 norm", TH["sub"], TH["bg"])
    d.SetFont("s9 norm c" TH["text"], "Segoe UI")
    lv := d.Add("ListView", Format("x16 y44 w640 h300 -Multi -E0x200 c{1} Background{2}", TH["text"], TH["card"])
        , [T("f_col_name"), T("sp_pc"), T("sp_cloud"), T("sp_bk_cloud"), T("sp_bk_pc")])
    for nm, p in Folders
        lv.Add(, nm, "…", "…", "…", "…")
    lv.Add(, T("sp_total"), "", "", "", "")
    lv.ModifyCol(1, 190)
    loop 4
        lv.ModifyCol(A_Index + 1, "AutoHdr")
    try {
        DllCall("uxtheme\SetWindowTheme", "Ptr", lv.Hwnd, "Str", DarkNow ? "DarkMode_Explorer" : "Explorer", "Ptr", 0)
    }
    alive := true
    d.OnEvent("Close", (*) => (alive := false, d.Destroy()))
    d.OnEvent("Escape", (*) => (alive := false, d.Destroy()))
    AddBtn(d, "", 16, 356, 110, 34, T("sp_close"), (*) => (alive := false, d.Destroy()))
    d.Show("w672 h406")

    Fill() {
        tot := [0, 0, 0, 0]
        row := 0
        for nm, p in Folders {
            row += 1
            if !alive
                return
            v := [0, 0, 0, 0]
            v[1] := StrSplit(SideSize(p, nm), "|")[2]
            if !alive
                return
            v[2] := StrSplit(SideSize(Remote "/" nm, nm), "|")[2]
            if !alive
                return
            v[3] := StrSplit(SideSize(Remote "/_backup/" nm), "|")[2]
            if !alive
                return
            v[4] := StrSplit(SideSize(BackupDir "\" nm), "|")[2]
            for i, x in v
                tot[i] += x
            try {
                lv.Modify(row, , nm, BigSize(v[1]), BigSize(v[2]), BigSize(v[3]), BigSize(v[4]))
            }
        }
        try {
            lv.Modify(row + 1, , T("sp_total"), BigSize(tot[1]), BigSize(tot[2]), BigSize(tot[3]), BigSize(tot[4]))
        }
    }
    SetTimer(Fill, -80)
}

; "Check space": what SyncDood occupies in the cloud and, when the cloud reports it, the account's free space
CloudSpaceUI(*) {
    UI["cloudSpace"].Text := T("c_space_wait")
    ToolTip(T("c_space_wait"))
    id := IniRead(IniFile, "general", "cloudId", "")
    sz := RcloneText(Format('size --json "{1}"', Remote))
    ab := ""
    if (id != "folder" && id != "nas" && !RegExMatch(Remote, "i)^([a-z]:\\|\\\\)"))
        ab := RcloneText(Format('about --json "{1}"', RegExReplace(Remote, "^([^:]+:).*$", "$1")))
    ToolTip()
    out := ""
    if (RegExMatch(sz, '"count"\s*:\s*(\d+)', &mc) && RegExMatch(sz, '"bytes"\s*:\s*(\d+)', &mb))
        out := T("c_space_used", BigSize(mb[1]), mc[1])
    else
        out := T("c_space_fail")
    if (RegExMatch(ab, '"total"\s*:\s*(\d+)', &mt) && RegExMatch(ab, '"used"\s*:\s*(\d+)', &mu)) {
        free := Number(mt[1]) - Number(mu[1])
        out .= "`n" T("c_space_acct", BigSize(mu[1]), BigSize(mt[1]), BigSize(Max(0, free)))
    } else if (id != "folder" && id != "nas") {
        out .= "`n" T("c_space_none")
    }
    UI["cloudSpace"].Text := out
}

ChangeCloudUI(*) {
    if CheckBusy()
        return
    if (MsgBox(T("c_confirm"), "SyncDood", "YesNo Icon?") != "Yes")
        return
    ; use the other remote name so the working one is untouched if this fails or is cancelled
    oldName := RegExMatch(Remote, "^(syncdood2?|rsy2?):", &m) ? m[1] : ""
    newName := (oldName = RemoteName) ? RemoteName "2" : RemoteName
    info := ChooseCloud(newName, true)
    if !IsObject(info)
        return
    if (oldName != "" && oldName != newName) {
        try {
            RunWait(Format('"{1}" config delete {2}', Rclone, oldName), , "Hide")
        }
    }
    IniWrite(info["remote"], IniFile, "general", "remote")
    IniWrite(info["name"], IniFile, "general", "cloudName")
    IniWrite(info["id"], IniFile, "general", "cloudId")
    IniWrite("0", IniFile, "general", "parallelOverride")      ; new cloud: back to its recommended parallel value
    ; every folder must do a first sync against the new cloud
    try {
        IniDelete(IniFile, "firstsync")
    }
    RestartApp(PG_CLOUD)
}

TestCloudUI(*) {
    code := -1
    try {
        code := RunWait(Format('"{1}" mkdir "{2}"', Rclone, Remote), , "Hide")
    }
    if (code = 0)
        MsgBox(T("c_test_ok"), "SyncDood", "Iconi")
    else
        MsgBox(T("c_test_fail", CloudHint(IniRead(IniFile, "general", "cloudId", ""))), "SyncDood", "Iconx")
}

; ---------------------------------------------------------------- Options ----
LoadOptionsIntoUI() {
    lang := StrLower(Trim(IniRead(IniFile, "general", "language", "auto")))
    SegClick(OptC["lang"], (lang = "en") ? 2 : ((lang = "es") ? 3 : 1))
    SegClick(OptC["theme"], (ThemePref = "light") ? 2 : ((ThemePref = "dark") ? 3 : 1))
    SegClick(OptC["firstwins"], (FirstWins = "local") ? 2 : ((FirstWins = "cloud") ? 3 : 1))
    SegClick(OptC["parmode"], (ParallelOverride > 0) ? 2 : 1)
    OptC["par"].Value := ParallelNow()
    SetToggle(OptC["startup"], FileExist(StartupLink))
    SetToggle(OptC["checkupd"], CheckUpd)
    SetToggle(OptC["dryrun"], DryRun)
    SetToggle(OptC["pause"], PauseRun)
    SetToggle(OptC["cloudprune"], CloudPrune)
}

BrowseBackup(*) {
    p := SelectFolder(T("o_backupdir"), Trim(OptC["backup"].Value), MainGui.Hwnd)
    if (p != "")
        OptC["backup"].Value := RTrim(p, "\")
}

SaveOptions(*) {
    if CheckBusy()
        return
    iv := Trim(OptC["interval"].Value)
    rs := Trim(OptC["resume"].Value)
    st := Trim(OptC["settle"].Value)
    kd := Trim(OptC["keep"].Value)
    pv := Trim(OptC["par"].Value)
    md := Trim(OptC["maxdel"].Value)
    manualPar := (OptC["parmode"]["sel"] = 2)
    if (!(IsInteger(iv) && iv >= 1 && IsInteger(rs) && rs >= 0 && IsInteger(st) && st >= 0 && IsInteger(kd) && kd >= 0)
        || (manualPar && !(IsInteger(pv) && pv >= 1 && pv <= 32))
        || !(IsInteger(md) && md >= 0 && md <= 100)) {
        MsgBox(T("o_invalid"), "SyncDood", "Iconx")
        return
    }
    bk := RTrim(Trim(OptC["backup"].Value), "\")
    if (bk = "")
        bk := AppDir "\backups"
    bad := BackupOverlap(bk)
    if (bad != "") {
        MsgBox(T("o_backup_inside", bk, bad), "SyncDood", "Iconx")
        return
    }
    pc := RegExReplace(Trim(OptC["pcname"].Value), '[\\/:*?"<>|]', "_")
    IniWrite(pc, IniFile, "general", "pcName")
    IniWrite(["auto", "en", "es"][OptC["lang"]["sel"]], IniFile, "general", "language")
    IniWrite(["auto", "light", "dark"][OptC["theme"]["sel"]], IniFile, "general", "theme")
    IniWrite(iv, IniFile, "general", "intervalMin")
    IniWrite(Trim(OptC["watch"].Value), IniFile, "general", "watchProcess")
    IniWrite(rs, IniFile, "general", "resumeDelaySec")
    IniWrite(st, IniFile, "general", "settleSec")
    IniWrite(["newer", "local", "cloud"][OptC["firstwins"]["sel"]], IniFile, "general", "firstSyncWins")
    IniWrite(bk, IniFile, "general", "backupDir")
    IniWrite(kd, IniFile, "general", "backupKeepDays")
    IniWrite(Integer(md), IniFile, "general", "maxDeletePct")
    IniWrite(manualPar ? Integer(pv) : 0, IniFile, "general", "parallelOverride")     ; 0 = automatic per cloud
    IniWrite(OptC["checkupd"]["on"] ? "1" : "0", IniFile, "general", "checkUpdates")
    IniWrite(OptC["dryrun"]["on"] ? "1" : "0", IniFile, "general", "dryRun")
    IniWrite(OptC["pause"]["on"] ? "1" : "0", IniFile, "general", "pauseWhileRunning")
    IniWrite(OptC["cloudprune"]["on"] ? "1" : "0", IniFile, "general", "pruneCloudBackups")
    if (OptC["startup"]["on"] && !FileExist(StartupLink)) {
        EnableStartup()
    } else if (!OptC["startup"]["on"] && FileExist(StartupLink)) {
        try {
            FileDelete(StartupLink)
        }
    }
    RestartApp(PG_OPT)
}

; ============================================================================
;  Menu actions
; ============================================================================
MenuOpen(*) {
    ShowMain(PG_STATUS)
}

MenuAbout(*) {
    ShowMain(PG_ABOUT)
}

MenuSyncNow(*) {
    RunSync(T("reason_manual"))
}

MenuUpdates(*) {
    CheckUpdates(true)
}

MenuPatreon(*) {
    Run(PatreonUrl)
}

MenuGithub(*) {
    Run(GithubUrl)
}

; "First sync / repair": merges this PC with the cloud again, for every folder
MenuResync(*) {
    if (FirstWins = "local")
        how := T("re_local")
    else if (FirstWins = "cloud")
        how := T("re_cloud")
    else
        how := T("re_newer")
    if (MsgBox(T("re_body", how), T("re_title"), "YesNo Icon?") = "Yes")
        RunSync(T("reason_first"), true)
}

MenuOpenIni(*) {
    Run('notepad.exe "' IniFile '"')
}

MenuOpenLog(*) {
    if !FileExist(LogFile)
        FileAppend("", LogFile)
    Run('notepad.exe "' LogFile '"')
}

MenuOpenFolder(*) {
    Run('explorer.exe "' FirstPath '"')
}

MenuOpenBackup(*) {
    if !DirExist(BackupDir)
        DirCreate(BackupDir)
    Run('explorer.exe "' BackupDir '"')
}

MenuStartup(*) {
    if FileExist(StartupLink) {
        FileDelete(StartupLink)
        A_TrayMenu.Uncheck(T("menu_startup"))
    } else {
        EnableStartup()
        A_TrayMenu.Check(T("menu_startup"))
    }
}


; ============================================================================
;  Cleanup: old SaveSync leftovers and full uninstall (the cloud is never touched)
; ============================================================================
BisyncDir() {
    return EnvGet("LOCALAPPDATA") "\rclone\bisync"
}

; rclone's bisync records whose name matches any of the patterns
FindBisyncFiles(patterns) {
    out := []
    dir := BisyncDir()
    if !DirExist(dir)
        return out
    for pat in patterns {
        Loop Files dir "\" pat, "F"
            out.Push(A_LoopFilePath)
    }
    return out
}

DeleteFiles(list) {
    for f in list {
        try {
            FileDelete(f)
        }
    }
}

RcloneRemoteDelete(name) {
    try {
        RunWait(Format('"{1}" config delete {2}', Rclone, name), , "Hide")
    }
}

; ---- full uninstall ----
UninstallUI(*) {
    if CheckBusy()
        return
    if (MsgBox(T("un_confirm"), "SyncDood", "YesNo Icon!") != "Yes")
        return

    keepBackups := false
    if DirExist(BackupDir) {
        r := MsgBox(T("un_backups", BackupDir), "SyncDood", "YesNo Icon?")
        keepBackups := (r != "Yes")
    }

    ; the program itself: the .exe, or (loose scripts) SyncDood's own files in its folder - never the whole folder
    progTarget := A_IsCompiled ? A_ScriptFullPath : A_ScriptDir
    delProg := false
    if (StrLen(progTarget) > 6 && FileExist(A_IsCompiled ? progTarget : A_ScriptDir "\SyncDood.ahk"))
        delProg := (MsgBox(T(A_IsCompiled ? "un_program" : "un_program_dir", progTarget), "SyncDood", "YesNo Icon?") = "Yes")

    ; stop everything first so no file is in use
    SetTimer(PeriodicSync, 0)
    SetTimer(WatchRA, 0)

    ; startup shortcuts
    for lnk in [StartupLink, A_Startup "\RSY.lnk", A_Startup "\SaveSync.lnk"] {
        try {
            FileDelete(lnk)
        }
    }

    ; rclone connections created by SyncDood / RSY / SaveSync (only the local credentials)
    for nm in ["syncdood", "syncdood2", "rsy", "rsy2", "savesync"]
        RcloneRemoteDelete(nm)

    ; rclone's bisync records for SyncDood, RSY and SaveSync (and for folder / NAS "clouds")
    pats := ["*..syncdood_*", "*..syncdood2_*", "*..rsy_*", "*..rsy2_*", "*..savesync_*"]
    for name, p in Folders {
        pats.Push("*_SyncDood_" name ".*")
        pats.Push("*_RSY_" name ".*")
    }
    DeleteFiles(FindBisyncFiles(pats))

    ; settings, history, log, bin ...  (backups kept if asked)
    for dir in [AppDir, EnvGet("LOCALAPPDATA") "\RSY", EnvGet("LOCALAPPDATA") "\SaveSync"] {
        if !DirExist(dir)
            continue
        if (keepBackups && dir = AppDir) {
            Loop Files dir "\*", "D" {
                if (A_LoopFileName != "backups") {
                    try {
                        DirDelete(A_LoopFilePath, true)
                    }
                }
            }
            Loop Files dir "\*", "F" {
                try {
                    FileDelete(A_LoopFilePath)
                }
            }
        } else {
            try {
                DirDelete(dir, true)
            }
        }
    }

    ; a custom backups folder lives outside SyncDood's data folder: remove only SyncDood's subfolders in it
    ; (and the folder itself only if that leaves it empty); anything else in there is not ours
    if (!keepBackups && DirExist(BackupDir) && !PathInside(BackupDir, AppDir)) {
        for nm in Folders {
            try {
                DirDelete(BackupDir "\" nm, true)
            }
        }
        try {
            DirDelete(BackupDir)
        }
    }

    MsgBox(T("un_done"), "SyncDood", "Iconi")

    ; the program can't delete itself while it runs: a hidden command does it just after we exit
    if delProg {
        if A_IsCompiled {
            cmd := Format('/c ping -n 4 127.0.0.1 >nul & del /f /q "{1}"', progTarget)
        } else {
            dels := ""
            for f in ["SyncDood.ahk", "rclone.exe", "README.md", "README.es.md", "THIRD_PARTY_NOTICES.md"
                    , "Install.bat", "Setup.ps1", "Build.bat", "Build.ps1", ".gitignore"]
                dels .= Format(' & del /f /q "{1}\{2}"', progTarget, f)
            cmd := Format('/c ping -n 4 127.0.0.1 >nul{1} & rmdir /s /q "{2}\icons" & rmdir /s /q "{2}\tools" & rmdir "{2}"'
                , dels, progTarget)          ; the last rmdir only works if the folder is now empty
        }
        Run(A_ComSpec " " cmd, A_Temp, "Hide")
    }
    ExitApp()
}

MenuExit(*) {
    ExitApp()
}
