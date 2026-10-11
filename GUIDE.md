# Guide: How the uup-dump Windows ISO Script Works

## Overview

This PowerShell script (`uup-dump-get-windows-iso.ps1`) automates the process of downloading Windows ISO images using the [UUP dump](https://uupdump.net) API. It fetches metadata, downloads the appropriate build package, and creates a usable ISO file.

## Architecture

The script supports three CPU architectures:

| Architecture | Mapping | Description |
|-------------|---------|-------------|
| `x64` | `amd64` | 64-bit x86 compatible |
| `arm64` | `arm64` | 64-bit ARM |
| `x86` (new) | `x86` | 32-bit x86 (added for Windows 10 32-bit support) |

## Supported Windows Builds

The script defines target builds in a hashtable (`$TARGETS`) with search strings that the UUP dump API uses to find matching builds. Each entry includes:

- **search**: The search query sent to the API
- **edition**: The default edition name (translated via `Get-EditionName`)

### Supported builds:

- `windows-10`: Windows 10 19045 (22H2)
- `windows-10-x86`: Windows 10 32-bit (x86) 19045 (22H2) - **new**
- `windows-11old`: Windows 11 22631 (23H2)
- `windows-11`: Windows 11 26100 (24H2)
- `windows-11new`: Windows 11 26200 (25H2)
- `windows-11beta`: Windows 11 26120 (24H2 BETA)
- `windows-11dev`: Windows 11 26220 (25H2 BETA Dev channel)
- `windows-1126h1`: Windows 11 28000 (26H1 - new hardware)
- `windows-1126h2`: Windows 11 26300 (26H2)
- `windows-1126h2beta`: Windows 11 26340 (26H2 Experimental)
- `windows-dev`: Windows 11 DEV channel
- `windows-canary`: Windows 11 Canary channel

## Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `windowsTargetName` | string | The build name (e.g., `windows-11new`) |
| `destinationDirectory` | string | Output directory (default: `output`) |
| `architecture` | string | `x64`, `arm64`, or `x86` (default: `x64`) |
| `edition` | string | `pro`, `core`, `multi`, or `home` (default: `pro`) |
| `lang` | string | Language code (default: `en-us`) |
| `esd` | switch | Use ESD compression |
| `drivers` | switch | Add drivers (x64 and x86, not arm64) |
| `netfx3` | switch | Add .NET Framework 3.5 |
| `revision` | string | Specific system revision number |

## How the Script Works - Step by Step

### 1. Parameter Processing and Initialization

The script begins by declaring all parameters with validation sets for architecture and language. It then:

- Sets strict mode and error preferences
- Initializes progress tracking variables
- Determines if the build is a preview/beta/dev/canary release
- Maps the architecture parameter to the internal format (`x64` → `amd64`, `x86` → `x86`, `arm64` → `arm64`)

### 2. Targets Lookup

The script looks up the specified Windows build in the `$TARGETS` hashtable. This returns metadata including:

- The search query for the API
- The edition name
- Virtual edition information (for some builds)

### 3. API Calls to UUP dump

The script makes several API calls to [https://api.uupdump.net](https://api.uupdump.net):

1. **`listid`**: Gets a list of build IDs matching the search query
2. **`listlangs`**: Gets available languages for the selected build
3. **`listeditions`**: Gets available editions for the selected language

These calls include retry logic (up to 15 attempts with 10-second delays) and error handling.

### 4. Filtering and Selection

The script filters results based on several criteria:

- **Preview builds**: If not in preview mode, filters out preview builds
- **Ring filtering**: For beta/dev/canary builds, validates the ring setting
- **Language compatibility**: Ensures the selected language is available
- **Edition compatibility**: Validates the edition matches the requested one

### 5. Download Package

After selecting a build, the script:

- Constructs a download request body based on whether virtual editions are involved
- Posts to the download package URL
- Saves the `.zip` package to the build directory
- Extracts the package using `Expand-Archive`

### 6. Configuration

The script modifies `ConvertConfig.ini` to control the ISO creation process:

- `AutoExit=1`: Exit after ISO creation
- `ResetBase=1`: Reset the base image
- `Cleanup=1`: Clean up temporary files
- `wim2esd=1` (if `-esd` flag): Use ESD compression
- `AddDrivers=1` (if `-drivers` flag): Add Dell drivers
- `NetFx3=1` (if `-netfx3` flag): Add .NET Framework 3.5
- Virtual edition settings (for virtualized builds)

### 7. Running the Batch File

The script patches and runs `uup_download_windows.cmd`, which uses [aria2](https://aria2.net/) for downloads. The script:

- Patches aria2 flags for quiet operation and reduced logging
- Executes the batch file
- Captures raw DISM/aria2 progress output
- Parses progress buckets and displays cleaned output
- Handles errors and dumps last 1500 log lines on failure

### 8. ISO Finalization

After successful build:

- Computes SHA256 checksum of the ISO
- Extracts Windows image information using DISM (or adapted for Linux)
- Creates metadata JSON file with build details
- Moves the ISO to the destination directory
- Outputs `ISO_NAME` to the GitHub environment for release tagging

## Linux Compatibility Details

When running on PowerShell 7+ on Linux:

### What works:

- API calls to uup-dump.net (HTTP requests)
- Download and extraction of ZIP packages
- Progress parsing (adapted for different log formats)
- ISO metadata generation
- Checksum computation

### What requires adaptation:

- **ISO mounting**: On Windows, uses `Mount-DiskImage`. On Linux, the script needs 7-Zip or similar to extract the ISO contents
- **DISM progress**: The progress tracking regex patterns are adapted for Linux-style output
- **aria2**: The `Patch-Aria2-Flags` function includes a PowerShell fallback when `sed` is not available
- **Package managers**: On Linux, Chocolatey is not available; the script detects system package managers

### Required for Linux:

- PowerShell 7+ installed
- 7-Zip or equivalent for ISO extraction
- aria2c for download management
- Appropriate permissions for disk operations

## Windows 7 / PowerShell 5.1 Compatibility

### Minimum requirements:

- PowerShell 5.1 (built into Windows 7/Server 2008 R2) or PowerShell 7+ (installable)

### Adaptations made:

- `Get-FileHash` works in both PS 5.1 and PS 7+, with compatible output format
- `ConvertTo-Json -Depth 99` behaves consistently across versions
- All regex patterns are culture-invariant
- No reliance on Windows-specific DISM cmdlets for core functionality

### Known limitations on PS 5.1:

- Some advanced progress tracking features may not work
- Error message formatting may differ
- JSON depth handling may have minor differences

## Output Structure

When the script completes successfully, it produces:

1. **ISO file**: The Windows ISO at `<destination>/<ISO_NAME>.ISO`
2. **Metadata JSON**: `<ISO_NAME>.json` containing:
   - Build name, title, version
   - SHA256 checksum
   - Available Windows images/indexes
   - uup-dump API URLs
3. **Environment variable**: `ISO_NAME` set for GitHub Actions integration

## Building Custom Platform Packages

The GitHub Actions workflow also builds platform-specific packages:

- **Windows**: `.cmd` script with aria2 and 7-Zip
- **Linux**: `.sh` script with aria2 and 7-Zip
- **macOS**: Shell script with aria2 and 7-Zip

These packages contain:
- Binary files (aria2c, 7z)
- Download scripts
- Part extraction logic
- Checksum verification

## Troubleshooting

### Common issues:

1. **Build not found**: Verify the `windowsTargetName` parameter matches a supported build
2. **Language not available**: Check the language code is in the supported list
3. **Edition mismatch**: Ensure the edition exists for the selected build
4. **Drivers not installing**: Drivers are skipped for arm64 architecture
5. **Progress not showing**: May occur on Linux with different log formats
6. **ISO extraction failure**: Ensure 7-Zip is available or install it

### Debug mode:

The script includes verbose output via `Write-CleanLine` which strips ANSI escape sequences. Set `$DebugPreference = 'Continue'` for additional debugging information.

## Security Considerations

- The script downloads from external APIs (uup-dump.net)
- ARIA2 downloads are executed with `--quiet=true` to reduce output
- Checksums are computed and provided for verification
- No external scripts are executed without user confirmation