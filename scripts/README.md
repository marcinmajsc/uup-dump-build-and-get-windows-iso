# Windows ISO Download Scripts - Separated Components

This directory contains the original UUP Dump Windows ISO download script separated into modular components for easier maintenance, debugging, and customization.

## Overview

The original monolithic script has been broken down into 8 separate scripts, each handling a specific part of the Windows ISO creation process.

## Scripts

### 00-run-all.ps1 (Master Orchestrator)
**Purpose:** Runs all steps in sequence with proper error handling.

**Usage:**
```powershell
.\00-run-all.ps1 -windowsTargetName "windows-11" -architecture "x64" -edition "pro" -lang "en-us"
```

**Options:**
- `-windowsTargetName`: Target Windows version (e.g., "windows-11", "windows-10", "windows-11beta")
- `-destinationDirectory`: Output directory (default: "output")
- `-architecture`: x64 or arm64 (default: "x64")
- `-edition`: pro, core, multi, or home (default: "pro")
- `-lang`: Language code (default: "en-us")
- `-esd`: Create ESD format instead of WIM
- `-drivers`: Include Dell drivers (x64 only)
- `-netfx3`: Include .NET Framework 3.5
- `-keepBuildDirectory`: Don't delete temporary build files

---

### 01-config-and-parameters.ps1
**Purpose:** Initialize configuration and validate parameters.

**What it does:**
- Validates all input parameters
- Determines architecture (x64/arm64)
- Checks for preview builds (beta/dev/canary)
- Creates Windows target definitions
- Exports configuration to `windows-iso-config.json`

**Output Files:**
- `windows-iso-config.json` - Configuration for subsequent scripts

---

### 02-helper-functions.ps1
**Purpose:** Utility functions for logging and progress tracking.

**What it provides:**
- `Write-CleanLine()` - Clean ANSI-stripped console output
- `Get-PercentFromText()` - Extract percentage from DISM output
- `Reset-ProgressSession()` - Reset progress tracking
- `Emit-ProgressBucket()` - Emit progress updates in 10% buckets
- `Process-ProgressLine()` - Parse and display DISM progress

**Note:** This script is dot-sourced by other scripts, not run standalone.

---

### 03-uup-api-functions.ps1
**Purpose:** Interact with the UUP Dump API to find and select the appropriate Windows build.

**What it does:**
- Queries UUP Dump API for available builds
- Filters by architecture, edition, language
- Handles preview/insider builds
- Validates build rings (Beta/Dev/Canary)
- Generates download URLs

**Input Files:**
- `windows-iso-config.json`

**Output Files:**
- `uup-dump-metadata.json` - Build information and download URLs

---

### 04-download-package.ps1
**Purpose:** Download the UUP conversion package from UUP Dump.

**What it does:**
- Downloads the UUP dump ZIP package
- Extracts conversion scripts and tools
- Creates build directory structure
- Determines virtual editions if applicable

**Input Files:**
- `windows-iso-config.json`
- `uup-dump-metadata.json`

**Output Files:**
- `build-info.json` - Build directory and title information
- Extracted UUP package in `output/<target-name>/` directory

---

### 05-configure-conversion.ps1
**Purpose:** Configure the conversion settings and patch aria2 flags.

**What it does:**
- Modifies `ConvertConfig.ini` for desired options:
  - ESD format conversion
  - Driver inclusion
  - .NET Framework 3.5
  - Virtual edition settings
- Patches aria2 download manager for quiet operation
- Copies driver files if needed

**Input Files:**
- `windows-iso-config.json`
- `build-info.json`
- `uup-dump-metadata.json`
- `ConvertConfig.ini` (in build directory)

**Output Files:**
- Modified `ConvertConfig.ini`
- Modified `uup_download_windows.cmd`
- Updated `build-info.json` (with tags)

---

### 06-create-iso.ps1
**Purpose:** Execute the UUP conversion process to create the Windows ISO.

**What it does:**
- Installs aria2 download manager
- Runs `uup_download_windows.cmd`
- Monitors DISM progress with bucketed output
- Downloads Windows update files
- Applies updates and creates bootable ISO
- Logs all output to file

**Input Files:**
- `build-info.json`

**Output Files:**
- Windows ISO file (e.g., `26100.1.amd64fre.ge_release.*.iso`)
- Raw log file in temp directory
- Updated `build-info.json` (with ISO path)

**Note:** This is the longest-running step (can take 30+ minutes).

---

### 07-validate-and-metadata.ps1
**Purpose:** Validate the created ISO and generate comprehensive metadata.

**What it does:**
- Mounts the ISO file
- Extracts Windows image information (editions, versions)
- Calculates SHA256 checksum
- Generates detailed metadata JSON
- Creates separate checksum file

**Input Files:**
- `windows-iso-config.json`
- `build-info.json`
- `uup-dump-metadata.json`
- Created ISO file

**Output Files:**
- `<iso-file>.json` - Comprehensive ISO metadata
- `<iso-file>.sha256.txt` - SHA256 checksum
- Updated `build-info.json` (with checksum and metadata paths)

---

### 08-cleanup-and-organize.ps1
**Purpose:** Move ISO to final location and clean up temporary files.

**What it does:**
- Moves ISO to destination directory
- Moves metadata and checksum files
- Removes build directory (unless `-keepBuildDirectory` specified)
- Removes downloaded ZIP package
- Sets GitHub Actions environment variables if applicable
- Displays final summary

**Input Files:**
- `windows-iso-config.json`
- `build-info.json`

**Options:**
- `-keepBuildDirectory`: Preserve temporary build files for debugging

---

## Workflow Diagram

```
01-config-and-parameters.ps1
    ↓ (creates windows-iso-config.json)
02-helper-functions.ps1 (loaded by other scripts)
    ↓
03-uup-api-functions.ps1
    ↓ (creates uup-dump-metadata.json)
04-download-package.ps1
    ↓ (creates build-info.json + extracts UUP package)
05-configure-conversion.ps1
    ↓ (modifies ConvertConfig.ini)
06-create-iso.ps1
    ↓ (creates ISO file)
07-validate-and-metadata.ps1
    ↓ (creates .json and .sha256.txt)
08-cleanup-and-organize.ps1
    ↓ (final ISO in output directory)
```

## Running Individual Steps

You can run scripts individually for debugging or customization:

```powershell
# Step 1: Setup configuration
.\01-config-and-parameters.ps1 -windowsTargetName "windows-11" -edition "pro"

# Step 3: Query API (uses config from step 1)
.\03-uup-api-functions.ps1

# Step 4: Download package
.\04-download-package.ps1

# And so on...
```

## Intermediate Files

The scripts create several JSON files for inter-script communication:

- **windows-iso-config.json** - User configuration and parameters
- **uup-dump-metadata.json** - UUP Dump build information
- **build-info.json** - Build directory, title, and progress tracking

These files allow you to:
- Inspect intermediate state
- Resume from a specific step
- Modify configuration between steps

## Advantages of Separation

1. **Debugging**: Run individual steps to isolate issues
2. **Customization**: Modify one step without affecting others
3. **Resumability**: Skip completed steps if they succeeded
4. **Maintenance**: Update specific functionality independently
5. **Understanding**: Clearer separation of concerns
6. **Testing**: Test individual components in isolation

## Dependencies

- **PowerShell 5.1+** or **PowerShell Core 7+**
- **Chocolatey** (for aria2 installation)
- **Windows** (for DISM operations)
- **Administrator privileges** (for DISM and disk image operations)

## Common Issues

### "Configuration file not found"
Run the scripts in order, starting with `01-config-and-parameters.ps1` or use `00-run-all.ps1`.

### "Build directory not found"
Ensure previous steps completed successfully. Check for error messages.

### aria2 download failures
Network issues or UUP Dump server availability. The script retries automatically.

### DISM errors
Requires Windows and administrator privileges. Some operations need Windows 10/11.

## Tips

- Use `-keepBuildDirectory` for debugging ISO creation issues
- Check intermediate JSON files to understand script state
- Review the raw log file if step 6 fails
- Monitor disk space - the process requires ~15-20 GB temporarily

## License

Same as the original script. These separated scripts maintain the functionality and license of the original UUP Dump Windows ISO script.
