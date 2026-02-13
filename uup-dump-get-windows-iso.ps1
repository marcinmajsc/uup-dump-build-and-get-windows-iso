#!/usr/bin/pwsh

# Annotated and documented copy of `uup-dump-get-windows-iso.ps1`
# Purpose: This file is a line-level, in-place annotated version intended
# to help readers understand what each major block and function does,
# why specific decisions were made, and what inputs/outputs/side-effects
# to expect. It is safe to read and not intended to be executed in place
# (it contains explanatory comments) — but it remains valid PowerShell.

<#
USAGE SUMMARY
- The original script automates downloading Windows images from uupdump
  and optionally customizing the install.wim/install.esd (remove apps,
  disable features, add autounattend.xml, recompress WIM, rebuild ISO).
- High-level flow:
  1) Parse parameters
  2) Define logging and DISM progress helpers
  3) Query uup-dump API for the desired build and edition
  4) Run the downloaded `uup_download_windows.cmd` to assemble an ISO
  5) Optionally customize images in the ISO
  6) Produce checksum + metadata and move resulting ISO

This annotated file documents the main data flows, each helper, and the
key places where errors or platform differences occur.
#>

param(
  # `windowsTargetName` - example values: windows-10, windows-11, windows-11beta
  [string]$windowsTargetName,
  # Output folder for the final ISO (default `output`)
  [string]$destinationDirectory = 'output',
  # Architecture to download; this script supports x64 and arm64 only
  [ValidateSet("x64", "arm64")] [string]$architecture = "x64",
  # Edition shorthand used by this script (maps to friendly names later)
  [ValidateSet("pro", "core", "multi", "home")] [string]$edition = "pro",
  # Language code to request from uup-dump (many values enumerated in original)
  [ValidateSet("nb-no", "fr-ca", "fi-fi", "lv-lv", "es-es", "en-gb", "zh-tw", "th-th", "sv-se", "en-us", "es-mx", "bg-bg", "hr-hr", "pt-br", "el-gr", "cs-cz", "it-it", "sk-sk", "pl-pl", "sl-si", "neutral", "ja-jp", "et-ee", "ro-ro", "fr-fr", "pt-pt", "ar-sa", "lt-lt", "hu-hu", "da-dk", "zh-cn", "uk-ua", "tr-tr", "ru-ru", "nl-nl", "he-il", "ko-kr", "sr-latn-rs", "de-de")]
  [string]$lang = "en-us",

  # Flags that follow the original script behavior
  [switch]$esd,             # work with .esd files instead of .wim when present
  [switch]$drivers,         # include drivers into the converted package
  [switch]$netfx3,

  # NEW PARAMETERS (added to support customization flows described below)
  [string]$answerFile,           # Path to autounattend.xml to inject into ISO
  [switch]$removeBloatware,      # Remove a list of common preinstalled apps
  [switch]$disableDefender,      # Remove/disable Windows Defender feature
  [switch]$disableIE,            # Remove Internet Explorer feature
  [string[]]$removeApps,         # Custom glob list of apps to remove
  [string[]]$disableFeatures,    # Custom list of optional features to disable
  [switch]$compressImage         # Re-compress WIM with maximum compression
)

# Strict mode and behaviour settings to help surface bugs early
Set-StrictMode -Version Latest
$ProgressPreference = 'SilentlyContinue'  # reduce noise from progress
$ErrorActionPreference = 'Stop'           # fail fast on errors

# Preview/ring detection helpers used when selecting builds
$preview  = $false
$ringLower = $null

# Basic trap to print helpful debugging information on any error
trap {
  # Print the error and a script stack trace, then exit non-zero
  Write-Host "ERROR: $_"
  @(($_.ScriptStackTrace -split '\r?\n') -replace '^(.*)$','ERROR: $1') | Write-Host
  @(($_.Exception.ToString() -split '\r?\n') -replace '^(.*)$','ERROR EXCEPTION: $1') | Write-Host
  Exit 1
}

# ------------------------------
# Logging helpers + DISM-style progress parsing
# ------------------------------

# ANSI escape code stripper -- used to show clean progress messages
$script:reAnsi = [regex]'\x1B\[[0-9;]*[A-Za-z]'
$script:LastPrintedLine = $null
function Write-CleanLine([string]$text) {
  # Removes control characters, prevents printing the same line repeatedly
  $clean = $script:reAnsi.Replace(($text ?? ''), '')
  if ($clean -eq $script:LastPrintedLine) { return }
  $script:LastPrintedLine = $clean
  Write-Host $clean
}

# DISM progress bucketing -- translate noisy incremental percentages into
# coarse buckets (e.g., every 10%) to keep logs readable and consistent.
$script:DismLastBucket = -1
$script:DismEveryPercent = if ($env:DISM_PROGRESS_STEP) { [int]$env:DISM_PROGRESS_STEP } else { 10 }
# If DISM_PROGRESS_RAW=1 we skip adding the [DISM] prefix to normalize output
$script:DismNormalizeOutput = if ($env:DISM_PROGRESS_RAW -eq '1') { $false } else { $true }

# Regex patterns used to extract percentages from various tool outputs
$script:reArchiving = [regex]'Archiving file data:\s+.*?\((\d+)%\)\s+done'
$script:reBracket   = [regex]'\[\s*[= \-]*\s*(\d+(?:[.,]\d+)?)%\s*[= \-]*\s*\]'
$script:reLoosePct  = [regex]'(^|\s)(\d{1,3})(?:[.,]\d+)?%(\s|$)'

function Get-PercentFromText([string]$text) {
  # Extract an integer 0-100 percentage from a line of text using multiple
  # heuristics. Returns $null when no percent is found.
  if ([string]::IsNullOrEmpty($text)) { return $null }
  $t = $script:reAnsi.Replace($text, '')

  $m = $script:reArchiving.Match($t)
  if ($m.Success) { return [int]$m.Groups[1].Value }

  $m = $script:reBracket.Match($t)
  if ($m.Success) {
    # e.g. "[ ==== 45.6% ==== ]" -> 45
    $pct = $m.Groups[1].Value -replace ',', '.'
    return [int][math]::Floor([double]$pct)
  }

  $m = $script:reLoosePct.Match($t)
  if ($m.Success) {
    $n = [int]$m.Groups[2].Value
    if ($n -ge 0 -and $n -le 100) { return $n }
  }
  return $null
}

function Reset-ProgressSession { $script:DismLastBucket = -1 }

function Emit-ProgressBucket([int]$pct) {
  # Round down to the bucket (e.g., to nearest 10%) and print only when the
  # bucket increases. Returns $true when an output was emitted.
  $bucket = [int]([math]::Floor($pct / $script:DismEveryPercent) * $script:DismEveryPercent)
  if ($bucket -le $script:DismLastBucket) { return $false }
  $script:DismLastBucket = $bucket

  if ($script:DismNormalizeOutput) { Write-CleanLine ("[DISM] Progress: {0}%" -f $bucket) }
  else { Write-CleanLine ("Progress: {0}%" -f $bucket) }

  if ($bucket -ge 100) {
    Write-CleanLine "[DISM] Progress: 100% (done)"
    Reset-ProgressSession
  }
  return $true
}

function Process-ProgressLine([string]$line) {
  # Parse a single line of raw output and, if it contains percent info,
  # emit a bucketed progress update. Returns $true if the line was
  # consumed as progress metadata (so callers can avoid echoing it again).
  $pct = Get-PercentFromText $line
  if ($pct -eq $null) { return $false }
  if ($script:DismLastBucket -ge 0 -and $pct -lt $script:DismLastBucket) { Reset-ProgressSession }
  [void](Emit-ProgressBucket $pct)
  return $true
}

# ------------------------------
# Basic target/metadata helpers
# ------------------------------

# map the simple `x64` to the search term used by uup-dump
$arch = if ($architecture -eq "x64") { "amd64" } else { "arm64" }

# If the requested target name contains preview indicators, track them
if ($windowsTargetName -match 'beta|dev|wif|canary') {
  $preview = $true
  $ringLower = @('beta','dev','wif','canary').Where({$windowsTargetName -match $_})[0]
}

function Get-EditionName($e) {
  # Normalize the provided edition names into the friendly names expected by
  # targets and uup-dump search strings.
  switch ($e.ToLower()) {
    "core"  { "Core" }
    "home"  { "Core" }
    "multi" { "Multi" }
    default { "Professional" }
  }
}

# Table of preconfigured target search strings. This is how the script maps a
# simple name like `windows-11` into a uup-dump search term and optionally a
# ring (Beta, Wif, Canary) to filter preview builds.
$TARGETS = @{
  "windows-10"       = @{ search="windows 10 19045 $arch"; edition=(Get-EditionName $edition) }
  "windows-11old"    = @{ search="windows 11 22631 $arch"; edition=(Get-EditionName $edition) }
  "windows-11"       = @{ search="windows 11 26100 $arch"; edition=(Get-EditionName $edition) }
  "windows-11new"    = @{ search="windows 11 26200 $arch"; edition=(Get-EditionName $edition) }
  "windows-11beta"   = @{ search="windows 11 26120 $arch"; edition=(Get-EditionName $edition); ring="Beta" }
  "windows-11dev"    = @{ search="windows 11 26220 $arch"; edition=(Get-EditionName $edition); ring="Wif" }
  "windows-11canary" = @{ search="windows 11 $arch"; edition=(Get-EditionName $edition); ring="Canary" }
}

function New-QueryString([hashtable]$parameters) {
  # Build a URL querystring from a hashtable, URL-encoding values.
  @($parameters.GetEnumerator() | ForEach-Object { "$($_.Key)=$([System.Net.WebUtility]::UrlEncode([string]$_.Value))" }) -join '&'
}

function Invoke-UupDumpApi([string]$name, [hashtable]$body) {
  # Robust wrapper around the uupdump.net API endpoints. Retries up to 15
  # times with a delay when transient network errors occur.
  for ($n = 0; $n -lt 15; ++$n) {
    if ($n) {
      Write-CleanLine "Waiting a bit before retrying the uup-dump api ${name} request #$n"
      Start-Sleep -Seconds 10
      Write-CleanLine "Retrying the uup-dump api ${name} request #$n"
    }
    try {
      $qs = if ($body) { '?' + (New-QueryString $body) } else { '' }
      return Invoke-RestMethod -Method Get -Uri ("https://api.uupdump.net/{0}.php{1}" -f $name, $qs)
    } catch {
      Write-CleanLine "WARN: failed the uup-dump api $name request: $_"
    }
  }
  throw "timeout making the uup-dump api $name request"
}

function Get-UupDumpIso($name, $target) {
  <#
  High-level: query the uup-dump API for builds matching the `target.search`
  string, filter by language and edition, and return a compact object with
  all the URLs and metadata needed to download the uup package.

  Important behaviors and filters in the function (keep these in mind when
  adapting the script):
  - If $preview is false the function will skip builds whose title contains
    "preview" (to avoid accidentally selecting insider builds).
  - It ensures that the chosen build exposes the requested language and
    edition; for the `multi` edition it expects both core and professional
    to be present.
  - Once a candidate is chosen, it constructs the `apiUrl`, `downloadUrl`,
    and `downloadPackageUrl` needed by later steps.
  #>

  Write-CleanLine "Getting the $name metadata"
  $result = Invoke-UupDumpApi listid @{ search = $target.search }

  # Iterate the returned builds and enrich them with language + edition info
  $result.response.builds.PSObject.Properties
  | ForEach-Object {
      $id = $_.Value.uuid
      $uupDumpUrl = 'https://uupdump.net/selectlang.php?' + (New-QueryString @{ id = $id })
      Write-CleanLine "Processing $name $id ($uupDumpUrl)"
      $_
    }
  | Where-Object {
      # Skip Insider/previews when we don't want them
      if (!$preview) {
        $ok = ($target.search -like '*preview*') -or ($_.Value.title -notlike '*preview*')
        if (-not $ok) {
          Write-CleanLine "Skipping.
L1: Expected preview=false.
L2: Got preview=true."
        }
        return $ok
      }
      $true
    }
  | ForEach-Object {
      # For the chosen build, fetch the language list and edition list
      $id = $_.Value.uuid
      Write-CleanLine "Getting the $name $id langs metadata"
      $result = Invoke-UupDumpApi listlangs @{ id = $id }
      if ($result.response.updateInfo.build -ne $_.Value.build) {
        throw 'for some reason listlangs returned an unexpected build'
      }
      $_.Value | Add-Member -NotePropertyMembers @{ langs = $result.response.langFancyNames; info = $result.response.updateInfo }

      # If the requested $lang exists, query editions for that language
      $langs = $_.Value.langs.PSObject.Properties.Name
      $eds = if ($langs -contains $lang) {
        Write-CleanLine "Getting the $name $id editions metadata"
        $result = Invoke-UupDumpApi listeditions @{ id = $id; lang = $lang }
        $result.response.editionFancyNames
      } else {
        Write-CleanLine "Skipping.
L3: Expected langs=$lang.
L4: Got langs=$($langs -join ',')."
        [PSCustomObject]@{}
      }
      $_.Value | Add-Member -NotePropertyMembers @{ editions = $eds }
      $_
    }
  | Where-Object {
      # Final filtering stage: confirm language, edition(s), and ring (if set)
      $langs = $_.Value.langs.PSObject.Properties.Name
      $editions = $_.Value.editions.PSObject.Properties.Name
      $res = $true

      if ($target.PSObject.Properties.Name -contains 'ring' -and $target.ring) {
        $ok = $_.Value.info.ring -eq $target.ring
        if (-not $ok) {
          Write-CleanLine "Skipping.
L5: Expected ring=$($target.ring).
L6: Got ring=$($_.Value.info.ring)."
        }
        $res = $res -and $ok
      }

      if ($langs -notcontains $lang) {
        $res = $false
      }

      if ($target.edition -eq "Multi") {
        # multi editions must expose both core and professional
        $ok = ($editions -contains "core") -and ($editions -contains "professional")
        if (-not $ok) {
          Write-CleanLine "Skipping.
L7: Expected editions=core,professional.
L8: Got editions=$($editions -join ',')."
        }
        $res = $res -and $ok
      } else {
        $ok = $editions -contains $target.edition
        if (-not $ok) {
          Write-CleanLine "Skipping.
L9: Expected editions=$($target.edition).
L10: Got editions=$($editions -join ',')."
        }
        $res = $res -and $ok
      }

      return $res
    }
  | Select-Object -First 1
  | ForEach-Object {
      # Build a compact result object for downstream steps
      $id = $_.Value.uuid
      [PSCustomObject]@{
        id                 = $id
        title              = $_.Value.title
        build              = $_.Value.build
        edition            = $target.edition
        virtualEdition     = $target['virtualEdition']
        apiUrl             = 'https://api.uupdump.net/get.php?' + (New-QueryString @{ id = $id; lang = $lang; edition = if ($edition -eq "multi") { "core;professional" } else { $target.edition } })
        downloadUrl        = 'https://uupdump.net/download.php?' + (New-QueryString @{ id = $id; pack = $lang; edition = if ($edition -eq "multi") { "core;professional" } else { $target.edition } })
        downloadPackageUrl = 'https://uupdump.net/get.php?' + (New-QueryString @{ id = $id; pack = $lang; edition = if ($edition -eq "multi") { "core;professional" } else { $target.edition } })
      }
    }
}

function Get-IsoWindowsImages($isoPath) {
  # Mount an ISO, read the install.wim or install.esd and list contained
  # images (index, name, version). This is used later to create metadata for
  # the produced ISO.
  $isoPath = Resolve-Path $isoPath
  Write-CleanLine "Mounting $isoPath"
  $isoImage = Mount-DiskImage $isoPath -PassThru
  try {
    $isoVolume = $isoImage | Get-Volume
    $installPath = if ($esd) { "$($isoVolume.DriveLetter):\sources\install.esd" } else { "$($isoVolume.DriveLetter):\sources\install.wim" }
    Write-CleanLine "Getting Windows images from $installPath"
    Get-WindowsImage -ImagePath $installPath | ForEach-Object {
      $image = Get-WindowsImage -ImagePath $installPath -Index $_.ImageIndex
      [PSCustomObject]@{ index = $image.ImageIndex; name = $image.ImageName; version = $image.Version }
    }
  }
  finally {
    Write-CleanLine "Dismounting $isoPath"
    Dismount-DiskImage $isoPath | Out-Null
  }
}

# ------------------------------
# Image Customization: mount WIM, remove apps/features, recompress
# ------------------------------

function Invoke-ImageCustomization {
  param(
    [string]$IsoPath,
    [string]$WorkDirectory
  )
  
  # This function performs an offline customization of images inside the
  # ISO. It extracts the ISO to a working directory, converts ESD->WIM when
  # necessary, mounts each image index, makes modifications, saves and
  # optionally recompresses the WIM.
  
  Write-CleanLine "=== Starting Image Customization ==="
  
  # Create working directories used during processing
  $extractPath = Join-Path $WorkDirectory "extracted_iso"
  $mountPath = Join-Path $WorkDirectory "mount"
  $customIsoPath = Join-Path $WorkDirectory "custom.iso"
  
  New-Item -Path $extractPath -ItemType Directory -Force | Out-Null
  New-Item -Path $mountPath -ItemType Directory -Force | Out-Null
  
  try {
    # Extract ISO contents by mounting and copying the root of the ISO
    Write-CleanLine "Extracting ISO contents..."
    $isoImage = Mount-DiskImage $IsoPath -PassThru
    $isoVolume = $isoImage | Get-Volume
    Copy-Item -Path "$($isoVolume.DriveLetter):\*" -Destination $extractPath -Recurse -Force
    Dismount-DiskImage $IsoPath | Out-Null
    
    # Determine path to the install image file inside the extracted ISO
    $wimPath = if ($esd) {
      Join-Path $extractPath "sources\install.esd"
    } else {
      Join-Path $extractPath "sources\install.wim"
    }
    
    # If we have an ESD, convert to WIM so that mounting and Modify APIs work
    if ($esd) {
      Write-CleanLine "Converting ESD to WIM for customization..."
      $tempWim = Join-Path $extractPath "sources\install_temp.wim"
      # Export-WindowsImage with CompressionType max produces an intermediate WIM
      Export-WindowsImage -SourceImagePath $wimPath -SourceIndex 1 -DestinationImagePath $tempWim -CompressionType max
      $wimPath = $tempWim
    }
    
    # Enumerate images (indexes) inside the WIM so we can iterate
    $images = Get-WindowsImage -ImagePath $wimPath
    
    # For each image index: mount, apply changes, unmount (save)
    foreach ($img in $images) {
      Write-CleanLine "Customizing image $($img.ImageIndex): $($img.ImageName)"
      
      # Mount the image to a local folder so we can run offline commands
      Write-CleanLine "Mounting image $($img.ImageIndex)..."
      Mount-WindowsImage -ImagePath $wimPath -Index $img.ImageIndex -Path $mountPath
      
      try {
        # Remove bloatware apps: by default we remove a list of common
        # consumer packages. Users may override with `-removeApps ...`.
        if ($removeBloatware -or $removeApps) {
          Write-CleanLine "Removing bloatware apps..."
          
          $defaultBloatware = @(
            "*Xbox*",
            "*Zune*",
            "*Bing*",
            "*MicrosoftOfficeHub*",
            "*SkypeApp*",
            "*Solitaire*",
            "*Candy*",
            "*MarchofEmpires*",
            "*BubbleWitch*",
            "*Disney*",
            "*Facebook*",
            "*Twitter*",
            "*Spotify*",
            "*LinkedInforWindows*",
            "*MinecraftUWP*"
          )
          
          $appsToRemove = if ($removeApps) { $removeApps } else { $defaultBloatware }
          
          foreach ($app in $appsToRemove) {
            # `Get-AppxProvisionedPackage -Path $mountPath` returns packages
            # that will be installed for new users; removing them reduces
            # the installed footprint for first logon.
            Get-AppxProvisionedPackage -Path $mountPath | 
              Where-Object { $_.DisplayName -like $app } | 
              ForEach-Object {
                Write-CleanLine "  Removing: $($_.DisplayName)"
                Remove-AppxProvisionedPackage -Path $mountPath -PackageName $_.PackageName
              }
          }
        }
        
        # Optionally remove Windows Defender feature (offline) using DISM
        if ($disableDefender) {
          Write-CleanLine "Disabling Windows Defender..."
          Disable-WindowsOptionalFeature -Path $mountPath -FeatureName "Windows-Defender" -Remove -NoRestart -ErrorAction SilentlyContinue
        }
        
        # Optionally remove Internet Explorer runtime components
        if ($disableIE) {
          Write-CleanLine "Disabling Internet Explorer..."
          Disable-WindowsOptionalFeature -Path $mountPath -FeatureName "Internet-Explorer-Optional-amd64" -Remove -NoRestart -ErrorAction SilentlyContinue
        }
        
        # Disable any user-specified optional features by name
        if ($disableFeatures) {
          foreach ($feature in $disableFeatures) {
            Write-CleanLine "Disabling feature: $feature"
            Disable-WindowsOptionalFeature -Path $mountPath -FeatureName $feature -Remove -NoRestart -ErrorAction SilentlyContinue
          }
        }
        
        # Run a component cleanup to reduce size and reset superseded components
        Write-CleanLine "Running component cleanup..."
        Repair-WindowsImage -Path $mountPath -StartComponentCleanup -ResetBase
        
      } finally {
        # Always unmount and save changes to the WIM to persist modifications
        Write-CleanLine "Saving changes to image $($img.ImageIndex)..."
        Dismount-WindowsImage -Path $mountPath -Save
      }
    }
    
    # If requested, recompress the WIM to reduce size. The logic here is
    # somewhat conservative: it exports images into a new compressed file and
    # then replaces the original.
    if ($compressImage) {
      Write-CleanLine "Compressing WIM with maximum compression..."
      $compressedWim = Join-Path $extractPath "sources\install_compressed.wim"
      Export-WindowsImage -SourceImagePath $wimPath -SourceIndex 1 -DestinationImagePath $compressedWim -CompressionType max
      
      # If multiple images exist, export them too
      if ($images.Count -gt 1) {
        for ($i = 2; $i -le $images.Count; $i++) {
          Export-WindowsImage -SourceImagePath $wimPath -SourceIndex $i -DestinationImagePath $compressedWim -CompressionType max
        }
      }
      
      Remove-Item $wimPath
      Move-Item $compressedWim $wimPath
    }
    
    # Copy provided autounattend.xml into the extracted ISO root so that the
    # rebuilt ISO contains it for unattended installs
    if ($answerFile -and (Test-Path $answerFile)) {
      Write-CleanLine "Adding answer file to ISO..."
      Copy-Item $answerFile -Destination (Join-Path $extractPath "autounattend.xml")
    }
    
    # Rebuild the ISO using `oscdimg.exe` from the Windows ADK. If ADK
    # isn't available the function prints a warning and leaves the extracted
    # folder for manual processing.
    Write-CleanLine "Rebuilding ISO..."
    $oscdimg = "C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe"
    
    if (Test-Path $oscdimg) {
      $bootData = Join-Path $extractPath "boot\etfsboot.com"
      $efiSys = Join-Path $extractPath "efi\microsoft\boot\efisys.bin"
      
      & $oscdimg -m -o -u2 -udfver102 -bootdata:2#p0,e,b"$bootData"#pEF,e,b"$efiSys" $extractPath $customIsoPath
      
      if ($LASTEXITCODE -eq 0) {
        Write-CleanLine "Custom ISO created successfully at: $customIsoPath"
        return $customIsoPath
      } else {
        throw "oscdimg failed with exit code $LASTEXITCODE"
      }
    } else {
      Write-CleanLine "WARNING: oscdimg.exe not found. Install Windows ADK to rebuild ISO."
      Write-CleanLine "Modified files are in: $extractPath"
      return $null
    }
    
  } finally {
    # Remove temporary mount folder used to mount WIM images
    if (Test-Path $mountPath) {
      Remove-Item -Path $mountPath -Recurse -Force -ErrorAction SilentlyContinue
    }
  }
}

# ------------------------------
# Patch helper: make aria2 less noisy in the generated batch file
# ------------------------------

function Patch-Aria2-Flags {
  param([string]$CmdPath)
  if (-not (Test-Path $CmdPath)) { return }

  # If `sed` is available (commonly present in Unix-like toolsets), use it
  # to perform in-place, fast edits. Otherwise, load the file as UTF-16LE
  # and operate via PowerShell regex (preserves BOM/encoding for .cmd files).
  $sed = Get-Command sed -ErrorAction SilentlyContinue
  if ($sed) {
    Write-CleanLine "Patching aria2 flags in $CmdPath using sed."
    # Remove conflicting flags first, then inject reduced/quiet flags
    & $sed.Path -ri 's/\s--console-log-level=\w+\b//g; s/\s--summary-interval=\d+\b//g; s/\s--download-result=\w+\b//g; s/\s--enable-color=\w+\b//g; s/\s-(q|quiet(=\w+)?)\b//g' $CmdPath
    & $sed.Path -ri 's@("%aria2%"\s+)@\1--quiet=true --console-log-level=error --summary-interval=0 --download-result=hide --enable-color=false @g' $CmdPath
    return
  }

  Write-CleanLine "sed not found. Patching aria2 flags in $CmdPath using PowerShell fallback."
  $bytes   = [System.IO.File]::ReadAllBytes($CmdPath)
  $content = [System.Text.Encoding]::Unicode.GetString($bytes)

  $patternsToRemove = @(
    '\s--console-log-level=\w+\b',
    '\s--summary-interval=\d+\b',
    '\s--download-result=\w+\b',
    '\s--enable-color=\w+\b',
    '\s-(?:q|quiet(?:=\w+)?)\b'
  )
  foreach ($re in $patternsToRemove) {
    $content = [regex]::Replace($content, $re, '', 'IgnoreCase, CultureInvariant')
  }
  $inject = '--quiet=true --console-log-level=error --summary-interval=0 --download-result=hide --enable-color=false '
  $content = [regex]::Replace($content, '("%aria2%"\s+)', ('$1' + $inject), 'IgnoreCase, CultureInvariant')

  $newBytes = [System.Text.Encoding]::Unicode.GetBytes($content)
  [System.IO.File]::WriteAllBytes($CmdPath, $newBytes)
}

function Get-WindowsIso($name, $destinationDirectory) {
  # Main entrypoint that drives the full flow for one target name.
  $iso = Get-UupDumpIso $name $TARGETS.$name
  if (-not $iso) { throw "Can't find UUP for $name ($($TARGETS.$name.search)), lang=$lang." }

  # Determine how the edition is represented in the metadata
  $isoHasEdition    = $iso.PSObject.Properties.Name -contains 'edition' -and $iso.edition
  $hasVirtualMember = $iso.PSObject.Properties.Name -contains 'virtualEdition' -and $iso.virtualEdition
  $effectiveEdition = if ($isoHasEdition) { $iso.edition } else { $TARGETS.$name.edition }

  # Parse the title returned by uup-dump to extract a build/version token
  if (!$preview) {
    if (-not ($iso.title -match 'version')) { throw "Unexpected title format: missing 'version'" }
    $parts = $iso.title -split 'version\s*'
    if ($parts.Count -lt 2) { throw "Unexpected title format, split resulted in less than 2 parts: $($parts -join '|')" }
    $verbuild = $parts[1] -split '[\s\(]' | Select-Object -First 1
  } else {
    $verbuild = $ringLower.ToUpper()
  }

  # Prepare paths and workspace for the build
  $buildDirectory               = "$destinationDirectory/$name"
  $destinationIsoPath           = "$buildDirectory.iso"
  $destinationIsoMetadataPath   = "$destinationIsoPath.json"
  $destinationIsoChecksumPath   = "$destinationIsoPath.sha256.txt"

  if (Test-Path $buildDirectory) { Remove-Item -Force -Recurse $buildDirectory | Out-Null }
  New-Item -ItemType Directory -Force $buildDirectory | Out-Null

  $edn = if ($hasVirtualMember) { $iso.virtualEdition } else { $effectiveEdition }
  Write-CleanLine $edn
  $title = "$name $edn $($iso.build)"

  # Download the prepared package that uup-dump provides. It yields a ZIP
  # containing `uup_download_windows.cmd` and the conversion helpers.
  Write-CleanLine "Downloading the UUP dump download package for $title from $($iso.downloadPackageUrl)"
  $downloadPackageBody = if ($hasVirtualMember) { @{ autodl=3; updates=1; cleanup=1; 'virtualEditions[]'=$iso.virtualEdition } } else { @{ autodl=2; updates=1; cleanup=1 } }
  Invoke-WebRequest -Method Post -Uri $iso.downloadPackageUrl -Body $downloadPackageBody -OutFile "$buildDirectory.zip" | Out-Null
  Expand-Archive "$buildDirectory.zip" $buildDirectory

  # `ConvertConfig.ini` controls the conversion behavior. The script modifies
  # several keys to ensure a non-interactive, cleaned output.
  $convertConfig = (Get-Content $buildDirectory/ConvertConfig.ini) `
    -replace '^(AutoExit\s*)=.*','$1=1' `
    -replace '^(ResetBase\s*)=.*','$1=1' `
    -replace '^(Cleanup\s*)=.*','$1=1'

  $tag = ""
  if ($esd) { $convertConfig = $convertConfig -replace '^(wim2esd\s*)=.*', '$1=1'; $tag += ".E" }
  if ($drivers -and $arch -ne "arm64") {
    $convertConfig = $convertConfig -replace '^(AddDrivers\s*)=.*', '$1=1'
    $tag += ".D"
    Write-CleanLine "Copy Dell drivers to $buildDirectory directory"
    Copy-Item -Path Drivers -Destination $buildDirectory/Drivers -Recurse
  }
  if ($netfx3) { $convertConfig = $convertConfig -replace '^(NetFx3\s*)=.*', '$1=1'; $tag += ".N" }
  if ($hasVirtualMember) {
    $convertConfig = $convertConfig `
      -replace '^(StartVirtual\s*)=.*','$1=1' `
      -replace '^(vDeleteSource\s*)=.*','$1=1' `
      -replace '^(vAutoEditions\s*)=.*',"`$1=$($iso.virtualEdition)"
  }
  Set-Content -Encoding ascii -Path $buildDirectory/ConvertConfig.ini -Value $convertConfig

  Write-CleanLine "Creating the $title iso file inside the $buildDirectory directory"
  Push-Location $buildDirectory

  # Before executing the batch we patch its aria2 invocation to be quiet
  Patch-Aria2-Flags -CmdPath (Join-Path $buildDirectory 'uup_download_windows.cmd')

  # Path for raw combined logs produced while running the batch
  $rawLog = Join-Path $env:RUNNER_TEMP "uup_dism_aria2_raw.log"

  # Ensure aria2 is installed (chocolatey) so the batch can call it. This
  # is a convenience and mirrors the original script's intent.
  choco install aria2 /y *> $null

  & {
    # Execute the Windows batch in a subshell; capture its stdout/stderr and
    # stream-process it so we can generate friendly/normalized progress output
    powershell cmd /c uup_download_windows.cmd 2>&1 |
      Tee-Object -FilePath $rawLog |
      ForEach-Object {
        $raw = [string]$_
        if ([string]::IsNullOrEmpty($raw)) { return }
        foreach ($crChunk in ($raw -split "`r")) {
          foreach ($line in ($crChunk -split "`n")) {
            if ($line -eq $null) { continue }
            # Process DISM progress lines into buckets; aria2 progress isn't
            # parsed here (only DISM-style output is bucketed)
            if (-not (Process-ProgressLine $line)) {
              if ($line -match '^\s*(Mounting image|Saving image|Applying image|Exporting image|Unmounting image|Deployment Image Servicing and Management tool|^=== )') {
                Reset-ProgressSession
              }
              Write-CleanLine $line
            }
          }
        }
      }
  }

  if ($LASTEXITCODE) {
    Write-Host "::warning title=Build failed::Dumping last 1500 raw log lines"
    Get-Content $rawLog -Tail 1500 | Write-Host
    throw "uup_download_windows.cmd failed with exit code $LASTEXITCODE"
  }

  Pop-Location

  $sourceIsoPath = Resolve-Path $buildDirectory/*.iso
  $IsoName = Split-Path $sourceIsoPath -leaf

  # Decide whether the user asked for customization and call the customizer
  $needsCustomization = $removeBloatware -or $disableDefender -or $disableIE -or $removeApps -or $disableFeatures -or $answerFile -or $compressImage
  
  if ($needsCustomization) {
    Write-CleanLine "=== Customization Requested ==="
    $customWorkDir = Join-Path $buildDirectory "customization_work"
    $customIsoPath = Invoke-ImageCustomization -IsoPath $sourceIsoPath -WorkDirectory $customWorkDir
    
    if ($customIsoPath -and (Test-Path $customIsoPath)) {
      # Replace original ISO with customized one
      Remove-Item $sourceIsoPath
      $sourceIsoPath = $customIsoPath
      $IsoName = "CUSTOM_" + (Split-Path $sourceIsoPath -Leaf)
    }
  }

  Write-CleanLine "Getting the $sourceIsoPath checksum"
  $isoChecksum = (Get-FileHash -Algorithm SHA256 $sourceIsoPath).Hash.ToLowerInvariant()
  Set-Content -Encoding ascii -NoNewline -Path $destinationIsoChecksumPath -Value $isoChecksum

  $windowsImages = Get-IsoWindowsImages $sourceIsoPath
  Set-Content -Path $destinationIsoMetadataPath -Value (
    ([PSCustomObject]@{
      name    = $name
      title   = $iso.title
      build   = $iso.build
      version = $verbuild
      tags    = $tag
      checksum = $isoChecksum
      images  = @($windowsImages)
      customization = @{
        removedBloatware = $removeBloatware.IsPresent
        disabledDefender = $disableDefender.IsPresent
        disabledIE = $disableIE.IsPresent
        customAppsRemoved = ($removeApps -ne $null)
        customFeaturesDisabled = ($disableFeatures -ne $null)
        hasAnswerFile = ($answerFile -ne $null -and (Test-Path $answerFile))
        compressed = $compressImage.IsPresent
      }
      uupDump = @{
        id                 = $iso.id
        apiUrl             = $iso.apiUrl
        downloadUrl        = $iso.downloadUrl
        downloadPackageUrl = $iso.downloadPackageUrl
      }
    } | ConvertTo-Json -Depth 99) -replace '\\\u0026','&'
  )

  Write-CleanLine "Moving the created $sourceIsoPath to $destinationDirectory/$IsoName"
  Move-Item -Force $sourceIsoPath "$destinationDirectory/$IsoName"

  Write-Output "ISO_NAME=$IsoName" | Out-File -FilePath $env:GITHUB_ENV -Encoding utf8 -Append
  Write-CleanLine 'All Done.'
}

# Entry point: call the main function with the parsed parameters
Get-WindowsIso $windowsTargetName $destinationDirectory
