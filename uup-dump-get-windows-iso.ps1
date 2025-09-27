#!/usr/bin/pwsh

[CmdletBinding()]
param(
  [Parameter(Mandatory)]
  [ValidateSet(
    "windows-10",
    "windows-11old",
    "windows-11",
    "windows-11new",
    "windows-11beta",
    "windows-11dev",
    "windows-11canary"
  )]
  [string]$windowsTargetName,

  [ValidateNotNullOrEmpty()]
  [string]$destinationDirectory = 'output',

  [ValidateSet("x64", "arm64")]
  [string]$architecture = "x64",

  [ValidateSet("pro", "core", "multi", "home")]
  [string]$edition = "pro",

  [ValidateSet("nb-no", "fr-ca", "fi-fi", "lv-lv", "es-es", "en-gb", "zh-tw", "th-th", "sv-se", "en-us", "es-mx", "bg-bg", "hr-hr", "pt-br", "el-gr", "cs-cz", "it-it", "sk-sk", "pl-pl", "sl-si", "neutral", "ja-jp", "et-ee", "ro-ro", "fr-fr", "pt-pt", "ar-sa", "lt-lt", "hu-hu", "da-dk", "zh-cn", "uk-ua", "tr-tr", "ru-ru", "nl-nl", "he-il", "ko-kr", "sr-latn-rs", "de-de")]
  [string]$lang = "en-us",

  [switch]$esd,
  [switch]$drivers,
  [switch]$netfx3
)

Set-StrictMode -Version Latest
$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Stop'

$preview  = $false
$ringLower = $null

trap {
  Write-Host "ERROR: $_"
  @(($_.ScriptStackTrace -split '\r?\n') -replace '^(.*)$','ERROR: $1') | Write-Host
  @(($_.Exception.ToString() -split '\r?\n') -replace '^(.*)$','ERROR EXCEPTION: $1') | Write-Host
  Exit 1
}

# ------------------------------
# Log helpers + DISM bucketed progress (no aria2 parsing)
# ------------------------------
$script:reAnsi = [regex]'\x1B\[[0-9;]*[A-Za-z]'
$script:LastPrintedLine = $null
function Write-CleanLine([string]$text) {
  $clean = $script:reAnsi.Replace(($text ?? ''), '')
  if ($clean -eq $script:LastPrintedLine) { return }
  $script:LastPrintedLine = $clean
  Write-Host $clean
}

function Write-SkipReason {
  param(
    [Parameter(Mandatory)][string]$Reason
  )

  Write-CleanLine ("Skipping. {0}" -f $Reason)
}

# DISM buckets (0/10/.../100)
$script:DismLastBucket = -1
$script:DismEveryPercent = if ($env:DISM_PROGRESS_STEP) { [int]$env:DISM_PROGRESS_STEP } else { 10 }
$script:DismNormalizeOutput = if ($env:DISM_PROGRESS_RAW -eq '1') { $false } else { $true }

$script:reArchiving = [regex]'Archiving file data:\s+.*?\((\d+)%\)\s+done'
$script:reBracket   = [regex]'\[\s*[= \-]*\s*(\d+(?:[.,]\d+)?)%\s*[= \-]*\s*\]'
$script:reLoosePct  = [regex]'(^|\s)(\d{1,3})(?:[.,]\d+)?%(\s|$)'

function Get-PercentFromText([string]$text) {
  if ([string]::IsNullOrEmpty($text)) { return $null }
  $t = $script:reAnsi.Replace($text, '')

  $m = $script:reArchiving.Match($t)
  if ($m.Success) { return [int]$m.Groups[1].Value }

  $m = $script:reBracket.Match($t)
  if ($m.Success) {
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
  $pct = Get-PercentFromText $line
  if ($pct -eq $null) { return $false }
  if ($script:DismLastBucket -ge 0 -and $pct -lt $script:DismLastBucket) { Reset-ProgressSession }
  [void](Emit-ProgressBucket $pct)
  return $true
}

# ------------------------------
# Basic metadata helpers
# ------------------------------
$arch = if ($architecture -eq "x64") { "amd64" } else { "arm64" }

if ($windowsTargetName -match 'beta|dev|canary') {
  $preview = $true
  $ringLower = @('beta','dev','canary').Where({$windowsTargetName -match $_})[0]
}

function Get-EditionName($e) {
  switch ($e.ToLower()) {
    "core"  { "Core" }
    "home"  { "Core" }
    "multi" { "Multi" }
    default { "Professional" }
  }
}

$editionName = Get-EditionName $edition

$TARGETS = @{
  "windows-10"       = @{ search="windows 10 19045 $arch"; edition=$editionName }
  "windows-11old"    = @{ search="windows 11 22631 $arch"; edition=$editionName }
  "windows-11"       = @{ search="windows 11 26100 $arch"; edition=$editionName }
  "windows-11new"    = @{ search="windows 11 26200 $arch"; edition=$editionName }
  "windows-11beta"   = @{ search="windows 11 26120 $arch"; edition=$editionName; ring="Beta" }
  "windows-11dev"    = @{ search="windows 11 26200 $arch"; edition=$editionName; ring="Dev" }
  "windows-11canary" = @{ search="windows 11 preview $arch"; edition=$editionName; ring="Canary" }
}

function New-QueryString([hashtable]$parameters) {
  @($parameters.GetEnumerator() | ForEach-Object { "$($_.Key)=$([System.Net.WebUtility]::UrlEncode([string]$_.Value))" }) -join '&'
}

function Invoke-UupDumpApi([string]$name, [hashtable]$body) {
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
  Write-CleanLine "Getting the $name metadata"
  $result = Invoke-UupDumpApi listid @{ search = $target.search }

  $result.response.builds.PSObject.Properties
  | ForEach-Object {
      $id = $_.Value.uuid
      $uupDumpUrl = 'https://uupdump.net/selectlang.php?' + (New-QueryString @{ id = $id })
      Write-CleanLine "Processing $name $id ($uupDumpUrl)"
      $_
    }
  | Where-Object {
      if (!$preview) {
        $ok = ($target.search -like '*preview*') -or ($_.Value.title -notlike '*preview*')
        if (-not $ok) {
          Write-SkipReason 'Expected preview=false. Got preview=true.'
        }
        return $ok
      }
      $true
    }
  | ForEach-Object {
      $id = $_.Value.uuid
      Write-CleanLine "Getting the $name $id langs metadata"
      $result = Invoke-UupDumpApi listlangs @{ id = $id }
      if ($result.response.updateInfo.build -ne $_.Value.build) {
        throw 'for some reason listlangs returned an unexpected build'
      }
      $_.Value | Add-Member -NotePropertyMembers @{ langs = $result.response.langFancyNames; info = $result.response.updateInfo }

      $langs = $_.Value.langs.PSObject.Properties.Name
      $eds = if ($langs -contains $lang) {
        Write-CleanLine "Getting the $name $id editions metadata"
        $result = Invoke-UupDumpApi listeditions @{ id = $id; lang = $lang }
        $result.response.editionFancyNames
      } else {
        $langsJoined = $langs -join ', '
        Write-SkipReason ("Expected langs={0}. Got langs={1}." -f $lang, $langsJoined)
        [PSCustomObject]@{}
      }
      $_.Value | Add-Member -NotePropertyMembers @{ editions = $eds }
      $_
    }
  | Where-Object {
      $langs = $_.Value.langs.PSObject.Properties.Name
      $editions = $_.Value.editions.PSObject.Properties.Name
      $res = $true

      $expectedRing = if ($ringLower) { $ringLower.ToUpper() } else { 'RETAIL' }
      if ($ringLower) {
        $actual = ($_.Value.info.ring).ToUpper()
        if ($ringLower -in @('dev','beta')) {
          if ($actual -notin @($expectedRing, 'WIF', 'WIS')) {
            Write-SkipReason ("Expected ring match for {0}, WIS or WIF. Got ring={1}." -f $expectedRing, $actual)
            $res = $false
          }
        } elseif ($actual -ne $expectedRing) {
          Write-SkipReason ("Expected ring match for {0}. Got ring={1}." -f $expectedRing, $actual)
          $res = $false
        }
      }

      if ($langs -notcontains $lang) {
        $langsJoined = $langs -join ', '
        Write-SkipReason ("Expected langs={0}. Got langs={1}." -f $lang, $langsJoined)
        $res = $false
      }

      $requestedEditionName = $editionName
      $editionsJoined = $editions -join ', '
      if ($requestedEditionName -eq 'Multi') {
        if (($editions -notcontains 'Professional') -and ($editions -notcontains 'Core')) {
          Write-SkipReason ("Expected editions=Multi (Professional/Core). Got editions={0}." -f $editionsJoined)
          $res = $false
        }
      } elseif ($editions -notcontains $requestedEditionName) {
        Write-SkipReason ("Expected editions={0}. Got editions={1}." -f $requestedEditionName, $editionsJoined)
        $res = $false
      }

      $res
    }
  | Select-Object -First 1
  | ForEach-Object {
      $id = $_.Value.uuid
      [PSCustomObject]@{
        name               = $name
        title              = $_.Value.title
        build              = $_.Value.build
        id                 = $id
        edition            = $target.edition
        virtualEdition     = $target['virtualEdition']
        apiUrl             = 'https://api.uupdump.net/get.php?' + (New-QueryString @{ id = $id; lang = $lang; edition = if ($editionName -eq 'Multi') { 'core;professional' } else { $target.edition } })
        downloadUrl        = 'https://uupdump.net/download.php?' + (New-QueryString @{ id = $id; pack = $lang; edition = if ($editionName -eq 'Multi') { 'core;professional' } else { $target.edition } })
        downloadPackageUrl = 'https://uupdump.net/get.php?' + (New-QueryString @{ id = $id; pack = $lang; edition = if ($editionName -eq 'Multi') { 'core;professional' } else { $target.edition } })
      }
    }
}

function Get-IsoWindowsImages($isoPath) {
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
# Patch uup_download_windows.cmd with sed (variant A) — quiet aria2 flags
# ------------------------------
function Patch-Aria2-Flags {
  param([string]$CmdPath)
  if (-not (Test-Path $CmdPath)) { return }

  $sed = Get-Command sed -ErrorAction SilentlyContinue
  if ($sed) {
    Write-CleanLine "Patching aria2 flags in $CmdPath using sed (variant A)."
    # Remove conflicting flags first
    & $sed.Path -ri 's/\s--console-log-level=\w+\b//g; s/\s--summary-interval=\d+\b//g; s/\s--download-result=\w+\b//g; s/\s--enable-color=\w+\b//g; s/\s-(q|quiet(=\w+)?)\b//g' $CmdPath
    # Inject quiet set right after "%aria2%"
    & $sed.Path -ri 's@("%aria2%"\s+)@\1--quiet=true --console-log-level=error --summary-interval=0 --download-result=hide --enable-color=false @g' $CmdPath
    return
  }

  # Fallback: PowerShell regex (preserves UTF-16LE)
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
  $iso = Get-UupDumpIso $name $TARGETS.$name
  if (-not $iso) { throw "Can't find UUP for $name ($($TARGETS.$name.search)), lang=$lang." }

  $isoHasEdition    = $iso.PSObject.Properties.Name -contains 'edition' -and $iso.edition
  $hasVirtualMember = $iso.PSObject.Properties.Name -contains 'virtualEdition' -and $iso.virtualEdition
  $effectiveEdition = if ($isoHasEdition) { $iso.edition } else { $TARGETS.$name.edition }

  if (!$preview) {
    if (-not ($iso.title -match 'version')) { throw "Unexpected title format: missing 'version'" }
    $parts = $iso.title -split 'version\s*'
    if ($parts.Count -lt 2) { throw "Unexpected title format, split resulted in less than 2 parts: $($parts -join '|')" }
    $verbuild = $parts[1] -split '[\s\(]' | Select-Object -First 1
  } else {
    $verbuild = $ringLower.ToUpper()
  }

  $buildDirectory             = Join-Path -Path $destinationDirectory -ChildPath $name
  $destinationIsoPath         = Join-Path -Path $destinationDirectory -ChildPath ("$name.iso")
  $destinationIsoMetadataPath = '{0}.json' -f $destinationIsoPath
  $destinationIsoChecksumPath = '{0}.sha256.txt' -f $destinationIsoPath

  if (-not (Test-Path $destinationDirectory)) {
    New-Item -ItemType Directory -Force $destinationDirectory | Out-Null
  }

  if (Test-Path $buildDirectory) { Remove-Item -Force -Recurse $buildDirectory | Out-Null }
  New-Item -ItemType Directory -Force $buildDirectory | Out-Null

  $edn = if ($hasVirtualMember) { $iso.virtualEdition } else { $effectiveEdition }
  Write-CleanLine $edn
  $title = "$name $edn $($iso.build)"

  Write-CleanLine "Downloading the UUP dump download package for $title from $($iso.downloadPackageUrl)"
  $downloadPackageBody = if ($hasVirtualMember) { @{ autodl=3; updates=1; cleanup=1; 'virtualEditions[]'=$iso.virtualEdition } } else { @{ autodl=2; updates=1; cleanup=1 } }
  $packageArchivePath = Join-Path -Path $destinationDirectory -ChildPath ("$name.zip")
  Invoke-WebRequest -Method Post -Uri $iso.downloadPackageUrl -Body $downloadPackageBody -OutFile $packageArchivePath | Out-Null
  try {
    Expand-Archive -Path $packageArchivePath -DestinationPath $buildDirectory -Force
  }
  finally {
    if (Test-Path $packageArchivePath) {
      Remove-Item -Force $packageArchivePath
    }
  }

  $convertConfigPath = Join-Path -Path $buildDirectory -ChildPath 'ConvertConfig.ini'
  $convertConfig = (Get-Content $convertConfigPath) `
    -replace '^(AutoExit\s*)=.*','$1=1' `
    -replace '^(ResetBase\s*)=.*','$1=1' `
    -replace '^(Cleanup\s*)=.*','$1=1'

  $tag = ""
  if ($esd) { $convertConfig = $convertConfig -replace '^(wim2esd\s*)=.*', '$1=1'; $tag += ".E" }
  if ($drivers -and $arch -ne "arm64") {
    $convertConfig = $convertConfig -replace '^(AddDrivers\s*)=.*', '$1=1'
    $tag += ".D"
    $driverSource = Join-Path -Path $PSScriptRoot -ChildPath 'Drivers'
    if (-not (Test-Path -Path $driverSource -PathType Container)) {
      throw "Dell drivers directory not found at $driverSource"
    }

    Write-CleanLine "Copy Dell drivers from $driverSource to $buildDirectory directory"
    $driversDestination = Join-Path -Path $buildDirectory -ChildPath 'Drivers'
    Copy-Item -Path $driverSource -Destination $driversDestination -Recurse -Force
  }
  if ($netfx3) { $convertConfig = $convertConfig -replace '^(NetFx3\s*)=.*', '$1=1'; $tag += ".N" }
  if ($hasVirtualMember) {
    $convertConfig = $convertConfig `
      -replace '^(StartVirtual\s*)=.*','$1=1' `
      -replace '^(vDeleteSource\s*)=.*','$1=1' `
      -replace '^(vAutoEditions\s*)=.*',"`$1=$($iso.virtualEdition)"
  }
  Set-Content -Encoding ascii -Path $convertConfigPath -Value $convertConfig

  Write-CleanLine "Creating the $title iso file inside the $buildDirectory directory"
  Push-Location $buildDirectory
  try {
    # Patch aria2 flags in the batch before running it (sed variant A, with PS fallback)
    $downloadScriptPath = Join-Path -Path $buildDirectory -ChildPath 'uup_download_windows.cmd'
    Patch-Aria2-Flags -CmdPath $downloadScriptPath

    # Raw log path
    $runnerTemp = if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { [System.IO.Path]::GetTempPath() }
    $rawLog = Join-Path $runnerTemp "uup_dism_aria2_raw.log"

    & {
      powershell cmd /c uup_download_windows.cmd 2>&1 |
        Tee-Object -FilePath $rawLog |
        ForEach-Object {
          $raw = [string]$_
          if ([string]::IsNullOrEmpty($raw)) { return }
          foreach ($crChunk in ($raw -split "`r")) {
            foreach ($line in ($crChunk -split "`n")) {
              if ($line -eq $null) { continue }
              # DISM progress buckets; aria2 is not parsed here
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
  }
  finally {
    Pop-Location
  }

  $sourceIsoPath = Get-ChildItem -Path $buildDirectory -Filter *.iso -ErrorAction Stop | Sort-Object -Property LastWriteTime -Descending | Select-Object -First 1 | Select-Object -ExpandProperty FullName
  $IsoName = Split-Path $sourceIsoPath -Leaf

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
      uupDump = @{
        id                 = $iso.id
        apiUrl             = $iso.apiUrl
        downloadUrl        = $iso.downloadUrl
        downloadPackageUrl = $iso.downloadPackageUrl
      }
    } | ConvertTo-Json -Depth 99) -replace '\\u0026','&'
  )

  Write-CleanLine "Moving the created $sourceIsoPath to $destinationDirectory/$IsoName"
  $finalIsoPath = Join-Path -Path $destinationDirectory -ChildPath $IsoName
  Move-Item -Force $sourceIsoPath $finalIsoPath

  if ($env:GITHUB_ENV) {
    Write-Output "ISO_NAME=$IsoName" | Out-File -FilePath $env:GITHUB_ENV -Encoding utf8 -Append
  }
  Write-CleanLine 'All Done.'
}

Get-WindowsIso $windowsTargetName $destinationDirectory
