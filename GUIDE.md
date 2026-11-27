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




ATTENTION, NOTICE (October 12, 2026): microsoft will cut off starting June 19,
2027 the access to windows update for all the computers that have windows 10
without ESU and below (the previous block was up to windows vista-server 2008
without R2), this logically affects the server versions (server 2008 R2 up to
server 2019, from server 2022 onwards, the windows update closure doesn't
affect it), this is due to the expiry of the root certificates of the update
service that expire as of this date, if you want to take a look at the official
link of the microsoft news, here it is (use the browser translation, it's in
English):

https://techcommunity.microsoft.com/blog/windows-itpro-blog/prepare-for-windows-update-certificate-rotation-in-2027/4562463

remember that root certificates are part of internet browsing, one of the
characteristics of the https protocol is that now everything that is transferred
to the router is encrypted (previously it wasn't so), but for programs used to
analyze everything that is transferred on a home network like wireshark to have
no effect (no sensitive data is seen), the root certificates must work and be
up to date, if they don't work, it gives a certificate error in the browser and
the programs that connect to the internet will stop working, you have to take
this into account when using an old windows installed on the computer (by the
way, the windows update closure also affects virtual machines, i.e., the PCs
booted inside a physical machine).

when the expiry date of the root certificate arrives it's possible that the
offices installed on windows without support give errors checking updates (up
to 10 and server 2019 which are client and server respectively you can install
the 2021-365, 7 and 8, up to office 2016), this being solved by deactivating
the office updates (when the expiry date of said root certificates arrives).

in the previous window (automatic updates were imposed starting from windows
2000) it didn't give any kind of failure when booting the operating system,
only when opening the microsoft update page or starting the windows update.
(I experienced the previous update closure window).

in case it's windows 10 with ESU, windows 11 24H2, LTSC servers of 2019 and
2016 and server 2022, microsoft has put as the official method to solve the
problem, the update, i.e., you'll have to update the second Tuesday of each
month until the date of June 19, 2027 in which already...piano, piano (you'll
understand what I'm telling you).

in case you come across this type of computers, these are the paths you have:

-  buy the ESU (windows 10) (in the case of countries of the european union, it has no cost)
-  patch the update to access the ESU, the only patch (and recommended for windows 10) is the MAS (microsoft activation script)
-  install an unofficial patch to update the root certificates, which is the legacy update
-  in the case of compatible versions (it's not mandatory for now from 11 24H2, windows 10 without ESU is essential
half-way) accept the updates to major versions of windows via update or doing an update from the windows installation
media.
-  keep the windows installation and do a dual boot with linux (not advisable).
-  uninstall windows and install linux together with a windows virtual machine (there everything is allowed, from originals to modified ones)

in case you choose the sensible option (the last one), remember that you must
set up vmware or virtualbox on linux (install linux on the computer logically)
and the virtual machine with the windows of your choice (that there you can
indeed install old windows) in an official way until June 2027, afterwards it
won't work and you'll only be able to install and update this type of PCs by
unofficial methods.

in case you've lost your job or the course for having told you this
inconvenience, good luck in your job search or in the course search (which I
hope you find), with all these clues I tell you you'll see how surely in the
end you find the dreamed job or course.