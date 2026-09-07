*Read this in other languages: [English](README.md), [한국어](README.ko.md)*

# ⚡ SwiftDeck: FinOps & Office Workflow Automation Suite
A portable productivity command center for office professionals and business teams, built with AutoHotkey v2.

<p align="center">
  <img src="./assets/demo.gif" width="900" alt="SwiftDeck Demo">
</p>

---

## What SwiftDeck Does

**SwiftDeck** helps office professionals eliminate repetitive work by combining folder shortcuts, text automation, prompt execution, hotstrings, key remapping, and a quick prompt popup menu into one lightweight Windows tray application.

It is designed especially for finance, sales administration, accounting, credit control, and other back-office teams that repeatedly work with ERP systems, monthly closing folders, shared drives, standard emails, and routine operational text.

> **Accelerate Team Month-End Closings · Prevent Human Errors · Reduce Repetitive Tasks · Standardize Workflows**

---

## Core Features

- **📂 1-Click Folder Navigation**: Open frequently used folders, ERP download paths, monthly evidence folders, and shared network drives from a hotkey menu. Supports subfolder browsing up to 2 levels deep with an intelligent cache.
- **⌨️ Prompt & SQL Text Automation**: Run long text blocks, SQL queries, AI prompts, or control-key sequences such as `{Enter}`, `{Tab}`, `{Wait:500}`, and `Ctrl+S`.
- **📋 Quick Prompt Popup Menu**: Press `Shift + Win + Space` to instantly display all registered prompts in a popup menu at your mouse cursor position — no need to remember individual slot numbers.
- **✏️ Hotstrings**: Expand short abbreviations into full email templates, reporting phrases, symbols, or standard messages instantly after a space or Enter key.
- **🔀 Key Remapping**: Remap rarely used keys such as CapsLock into practical shortcuts, mouse clicks, or workflow-specific actions.
- **⚙️ Portable Team Deployment**: Share local `.ini` settings files to standardize folder paths, prompts, and templates across a team with zero installation.

---

## 🚀 Download & Quick Start

**SwiftDeck** is a **portable application**. It runs by double-clicking the executable and does not require installation.

### 📥 For General Users (1-Click Portable Download)

1. Go to the **[Releases](https://github.com/KwangBeomPark/02_SwiftDeck/releases)** tab on the right side of the GitHub repository.
2. Download the latest **`SwiftDeck.vX.Y.Z.zip`** or standalone **`SwiftDeck.vX.Y.Z.exe`** file (for example `SwiftDeck.v1.3.2.exe`).
3. Unzip the file if needed, then double-click the downloaded `.exe`.
   Each release also ships an identical `SwiftDeck.exe` under the fixed name, which the built-in updater in v1.3.1 and earlier relies on.
4. A black lightning bolt icon will appear in the Windows system tray — SwiftDeck is ready to use.

If no release file is available yet, please build or run `src/SwiftDeck.ahk` using AutoHotkey v2.

### 🛡️ What Windows Will Say

SwiftDeck releases are **not code-signed yet**, so Windows treats the download as a program it has never seen. What you get depends on which protection is active on your machine:

| Protection | What happens | What to do |
| --- | --- | --- |
| **SmartScreen** | A blue "Windows protected your PC" dialog | Click **More info**, then **Run anyway** |
| **Smart App Control** | The app is **blocked outright** — no dialog to click through | See below |
| **Antivirus or company policy** | May quarantine the file or block it silently | Ask your IT team to allow it |

**Smart App Control** is the one that stops you completely. It is on by default on clean Windows 11 installs, it enforces below the desktop rather than warning you, and it refuses any unsigned program that has no established reputation. Check it under **Windows Security → App & browser control → Smart App Control**. If it says **On**:

- **Run from source instead** — install [AutoHotkey v2](https://www.autohotkey.com/) and run `src/SwiftDeck.ahk`. The AutoHotkey interpreter is signed, so this path works with Smart App Control left on. This is the recommended option on a work machine.
- Turning Smart App Control off also works, but it is a **one-way change**: Windows cannot switch it back on without reinstalling the operating system. Do not do this on a machine you do not own.

Signing is planned once an open-source code-signing certificate is in place. Note that signing alone does not remove the SmartScreen prompt immediately — reputation builds up over downloads — so the source-run option above stays the reliable one for locked-down environments.

### 🔍 Verifying Your Download

An unsigned download is exactly the case where you cannot tell the real file from one that was swapped in transit, so every release ships a `SHA256SUMS.txt` asset listing a digest for each file. Compare it with what you downloaded:

```powershell
Get-FileHash .\SwiftDeck.v1.3.2.exe -Algorithm SHA256
```

The printed hash must match the line for that filename in `SHA256SUMS.txt`. If it does not, delete the file and download it again.

`SwiftDeck.exe` and `SwiftDeck.vX.Y.Z.exe` are byte-identical copies of the same build — the fixed name exists only so that the updater in v1.3.1 and earlier keeps working — so their digests are the same by design.

### 🔄 Automatic Updates

SwiftDeck checks the latest public GitHub Release after startup at most once every 24 hours. When a newer release is available, **App Settings** shows `New version vX available` in its header and the header's **Update to vX** button starts the verified update directly. **App Information** and the tray menu's **Check for Updates** remain available for manual checks. The updater downloads the release binary beside the currently running app, verifies its SHA-256 digest against `SwiftDeck.update.ini`, safely replaces the executable, and restarts SwiftDeck. It prefers the version-stamped asset and falls back to `SwiftDeck.exe`. The running file keeps its own name, so an executable you renamed stays renamed after an update. Saved settings in `%AppData%\SwiftDeck` are not replaced. Source mode and read-only folders remain manual-update only.

### 🛠️ For Power Users & Developers (Custom Build)

1. Install [AutoHotkey v2](https://www.autohotkey.com/).
2. Clone this repository.
3. Customize `src/SwiftDeck.ahk` as needed.
4. Run `scripts/build.ps1` to compile, package, and write the update manifest.

To produce a signed build, import your code-signing certificate into your personal
certificate store and pass its thumbprint:

```powershell
.\scripts\build.ps1 -CertificateThumbprint <thumbprint>
```

Signing runs before the SHA-256 is written into `SwiftDeck.update.ini`, so a signed
build stays verifiable by the updater. Without the parameter the build is unsigned.

Before publishing, exercise the self-update path against the previous release:

```powershell
.\tests\Test-UpdateWorker.ps1 -OldExe dist\SwiftDeck.v1.3.1.exe -NewExe release\SwiftDeck.v1.3.2.exe -WorkRoot $env:TEMP
.\tests\Test-UpdateRollback.ps1 -OldExe release\SwiftDeck.v1.3.2.exe -WorkRoot $env:TEMP
```

### Repository Layout

```text
src/      Source entry point and AutoHotkey library files
tests/    Test suites; scripts/build.ps1 runs every tests/*Tests.ahk and fails the build on any failure
scripts/  Build, packaging, signing, and optional release publishing
assets/   Public images, icons, and README media
dist/     Local build output (.exe only), excluded from Git
release/  Assets for upload: versioned .exe and .zip, SwiftDeck.exe, SwiftDeck.update.ini, SHA256SUMS.txt; excluded from Git
```

Release binaries should be uploaded to GitHub Releases, not committed to the repository body.

---

## 💼 Practical FinOps & Business Use Cases

- **Month-end closing folder access**: Press `F1` to open a menu of monthly closing folders, ERP downloads, evidence files, and shared drives — all within one click.
- **SQL / AI prompt execution**: Press a registered shortcut or open the Quick Prompt Menu (`Shift + Win + Space`) to type any stored AI prompt or SQL query automatically.
- **Standard email templates**: Type a short hotstring such as `;t1` to expand it instantly into a full report message, budget request, or daily cash update.
- **Quick Prompt Popup**: Browse and launch all prompts slot-by-slot from a popup menu at your mouse cursor — ideal for users managing multiple AI prompt libraries.
- **Fatigue reduction**: Remap repetitive keyboard or mouse operations to reduce wrist strain during long Excel, ERP, or copy-paste work sessions.
- **Team standardization**: A manager can configure common prompts, folder paths, and hotstrings once, then distribute the generated `.ini` files to bring the whole team onto the same workflow standard.

---

## 📖 User Manual

✔ **Folders**: Manage and quick-jump to frequently used folder paths. Subfolders are browsable up to 2 levels deep.  
✔ **Prompts**: Execute repetitive text strings and control-key macros such as `{Wait}`, `{Enter}`, and `{Tab}`. Supports `{Ctrl+S}`, `{Alt+Tab}`, and other shortcut combos.  
✔ **Hotstrings**: Register text abbreviations for instant auto-completion triggered by a space or Enter key.  
✔ **Key Remap**: Map physical keys to more useful shortcuts or mouse clicks.  
✔ **General**: Manage hotkeys, Windows startup, the settings folder, saved-setting backups, restore, and factory reset.<br>
✔ Changes in **Folders**, **Prompts**, **Hotstrings**, and **Key Remap** are saved and applied immediately after each confirmed action. Only **General** keeps **Save & Apply** because its hotkey values are edited as a set. Closing or exiting with pending General changes offers **Save All**, **Discard**, or **Keep Editing**.

> Open **App Settings → Manual** for the built-in guide. Its shortcut summary is generated from the settings currently active on your PC, and the last selected manual language is restored the next time you open it.

---

## ⌨️ Essential Shortcuts & Controls

| Shortcut | Function |
|---------|----------|
| `F1` (Default) | Open the Favorite Folders popup menu from anywhere |
| `Win + Numpad (0~9)` | Execute registered prompt slots directly by number |
| `Shift + Win + Space` | Open the **Quick Prompt Popup Menu** at mouse position |
| `Ctrl + Win + Space` | Open the emoji and symbol picker |
| `Ctrl + F1` (Default) | Add the current Explorer folder to Favorites. If the Favorites hotkey changes, SwiftDeck derives and displays a non-conflicting related shortcut. |
| `;abbreviation` e.g. `;t1` | Expand a hotstring into long text or an email template |
| `System Tray Menu` | Open App Settings and related management menus |

---

## ⚙️ Settings File & Team Deployment

SwiftDeck stores all configuration data in local `.ini` files — no registry entries, no hidden data.

You can open the settings folder from:

```text
System Tray Menu → Open Settings Folder
```

The same actions are available in **App Settings → General → Data, Startup & Recovery**:

- **Open Folder** opens the local settings directory.
- **Backup Saved** backs up the configuration currently stored on disk. If General shows pending changes, apply them first.
- **Restore** confirms before replacing the current configuration and then reloads SwiftDeck.
- **Factory Reset** preserves backups but replaces active settings with defaults after confirmation.

**If Restore is not enough.** SwiftDeck refreshes `Backups\<file>.bak` every time it starts, so if a problem is only noticed after a restart, that copy already reflects the problem. Before overwriting it, the previous `.bak` is kept as `Backups\<file>.bak.YYYYMMDD`, one per day and five days in total. **Restore** only uses the plain `.bak`; to go further back, open the settings folder, copy the dated file you want over the matching `.ini` with SwiftDeck closed, and start it again.

For team deployment, one manager can configure common folder paths, prompts, and hotstrings first, then share the generated `.ini` files with colleagues. Each team member simply places the files in the correct location and reloads the app — no additional setup required.

---

## 🔐 Security & Privacy

- SwiftDeck runs locally on Windows. Settings are stored on the user's machine and are not synced by the app.
- When the built-in translation feature is used, the selected text is sent to Google's public translation endpoint for that request.
- If bundled support images are missing, the app may download public UI assets such as the Buy Me a Coffee button or GitHub favicon.
- All folder paths, prompts, hotstrings, and key remap settings are stored in local `.ini` files only.
- **Folder paths are validated before they are opened**: SwiftDeck checks that the target exists and is a directory, and passes it as a quoted argument. It does not go through a command shell, so characters such as `&`, `|`, `>` and `<` in a folder name cannot chain commands — which is also why a normal folder like `Sales & Marketing` opens correctly rather than being refused.
- **Releases are not code-signed yet**, and each one publishes a `SHA256SUMS.txt` so you can verify a download. See [What Windows Will Say](#-what-windows-will-say).
- Avoid storing passwords, API keys, personal credentials, or highly confidential information in Prompt or Hotstring settings.
- Review shared `.ini` files carefully before distributing them to other users.

---

## 👨‍💼 Project Background

I am **not a professional software developer, but a business operations practitioner who wanted to reduce repetitive office workflows.**

Watching daily repetitive tasks such as complex ERP inquiries, scattered month-end folder searches, and routine email drafting consume valuable team hours, I started this project with a practical question: **How can we remove inefficient workflows and help the whole team focus on higher-value work?**

By analyzing real operational pain points and bottlenecks, **SwiftDeck** evolved from a personal macro script into a practical, enterprise-grade office automation suite for standardizing workflows and elevating team productivity.

---

## 💻 Environment & License

- **Environment**: Windows 10 / 11, AutoHotkey v2 runtime, or compiled standalone executable
- **License**: MIT License. SwiftDeck is open-source and free to modify and distribute.

---

## ☕ Support Practical Automation with a Coffee

If this tool has reduced your month-end closing hours or eased repetitive work, your support is a great motivation for developing more practical open-source finance automation tools.

<p align="center">
  <a href="https://www.buymeacoffee.com/KBPark_Bob">
    <img
      src="./assets/bmc_button.png"
      width="220"
      alt="Buy Me A Coffee">
  </a>
</p>
