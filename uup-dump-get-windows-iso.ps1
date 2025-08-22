#!/usr/bin/pwsh

param(
  [string]$windowsTargetName,
  [string]$destinationDirectory = 'output',
  [ValidateSet("x64", "arm64")] [string]$architecture = "x64",
  [ValidateSet("pro", "core", "multi", "home")] [string]$edition = "pro",
  [ValidateSet("nb-no", "fr-ca", "fi-fi", "lv-lv", "es-es", "en-gb", "zh-tw", "th-th", "sv-se", "en-us", "es-mx", "bg-bg", "hr-hr", "pt-br", "el-gr", "cs-cz", "it-it", "sk-sk", "pl-pl", "sl-si", "neutral", "ja-jp", "et-ee", "ro-ro", "fr-fr", "pt-pt", "ar-sa", "lt-lt", "hu-hu", "da-dk", "zh-cn", "uk-ua", "tr-tr", "ru-ru", "nl-nl", "he-il", "ko-kr", "sr-latn-rs", "de-de")]
  [string]$lang = "en-us",
  [switch]$esd,
  [switch]$drivers,
  [switch]$netfx3
)

Set-StrictMode -Version Latest
$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Stop'

$preview = $false
$ringLower = $null

trap {
  Write-Host "ERROR: $_"
  @(($_.ScriptStackTrace -split '\r?\n') -replace '^(.*)$','ERROR: $1') | Write-Host
  @(($_.Exception.ToString() -split '\r?\n') -replace '^(.*)$','ERROR EXCEPTION: $1') | Write-Host
  Exit 1
}

# --- BEGIN: DISM/cmd + aria2 log filter (inline) ---
# DISM/cmd: show progress buckets only (0,10,20,...,100), handle CR-based progress from .bat/cmd, strip ANSI.
# aria2: hide live progress lines, print full "Download Progress Summary", and condense "Download Results"
#        (one-liner if all OK; otherwise only non-OK rows). Emit a heartbeat every 10s while live is suppressed.

# ---- Common helpers / regex ----
$script:reAnsi = [regex]'\x1B\[[0-9;]*[A-Za-z]'
$script:LastPrintedLine = $null
function Write-CleanLine([string]$text) {
  $clean = $script:reAnsi.Replace(($text ?? ''), '')
  # de-duplicate identical consecutive messages
  if ($clean -eq $script:LastPrintedLine) { return }
  $script:LastPrintedLine = $clean
  Write-Host $clean
}

# ---- DISM progress ----
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

  # Fallback: any "NN%" in the text (common in console tools)
  $m = $script:reLoosePct.Match($t)
  if ($m.Success) {
    $n = [int]$m.Groups[2].Value
    if ($n -ge 0 -and $n -le 100) { return $n }
  }
  return $null
}

function Reset-ProgressSession {
  $script:DismLastBucket = -1
}

function Emit-ProgressBucket([int]$pct) {
  $bucket = [int]([math]::Floor($pct / $script:DismEveryPercent) * $script:DismEveryPercent)
  if ($bucket -le $script:DismLastBucket) { return $false }
  $script:DismLastBucket = $bucket

  if ($script:DismNormalizeOutput) {
    Write-CleanLine ("[DISM] Progress: {0}%" -f $bucket)
  } else {
    Write-CleanLine ("Progress: {0}%" -f $bucket)
  }

  if ($bucket -ge 100) {
    Write-CleanLine "[DISM] Progress: 100% (done)"
    # Prepare for next DISM phase (e.g., Mounting image)
    Reset-ProgressSession
  }
  return $true
}

function Process-ProgressLine([string]$line) {
  $pct = Get-PercentFromText $line
  if ($pct -eq $null) { return $false }

  # If percent goes backwards, assume a NEW DISM phase started
  if ($script:DismLastBucket -ge 0 -and $pct -lt $script:DismLastBucket) {
    Reset-ProgressSession
  }

  [void](Emit-ProgressBucket $pct)
  return $true
}

# ---- aria2 filtering & heartbeat ----
# Live progress lines look like: [DL:48MiB][#498b74 10MiB/10MiB(100%)]...
# Summary header: "*** Download Progress Summary as of ..."
# Results block: "Download Results:" ... table lines "gid|STAT|...|path"
$script:reAria2Live    = [regex]'^\[DL:[^\]]+\](?:\[[^\]]*\])+'   # multi [..][..]
$script:reAria2Live2   = [regex]'^\s*\[#?[0-9a-f]{6,}\s+[0-9A-Za-z./()%,:\s-]+\]\s*$' # e.g. "[#526375 0B/0B CN:1 DL:0B]"
$script:reAria2Summary = [regex]'\*\*\*\s+Download Progress Summary as of '
$script:reAria2Results = [regex]'^\s*Download Results:\s*$'
$script:reAria2Header  = [regex]'^\s*gid\s+\|stat\|avg speed\s+\|path/URI\s*$'
$script:reAria2Sep     = [regex]'^\s*=+\+==+\+.*$'
$script:reAria2Row     = [regex]'^\s*([0-9a-f]{6,})\|([A-Z]+)\|'

$script:Aria2InSummary       = $false
$script:Aria2InResults       = $false
$script:Aria2ResultsBuffer   = New-Object System.Collections.Generic.List[string]
$script:Aria2ResultsHasError = $false
$script:Aria2ErrorCount      = 0
$script:Aria2RowCount        = 0

# Heartbeat state
$script:Aria2Active          = $false
$script:Aria2LastSeen        = [datetime]::MinValue
$script:Aria2LastHeartbeat   = [datetime]::MinValue
$script:Aria2HeartbeatEveryS = if ($env:ARIA2_HEARTBEAT_SEC) { [int]$env:ARIA2_HEARTBEAT_SEC } else { 10 }
$script:Aria2IdleCutoffS     = 15  # consider aria2 inactive if nothing seen for this long

function Aria2-MaybeHeartbeat {
  if (-not $script:Aria2Active) { return }
  $now = Get-Date
  if (($now - $script:Aria2LastSeen).TotalSeconds -gt $script:Aria2IdleCutoffS) {
    # aria2 became idle
    $script:Aria2Active = $false
    return
  }
  if (($now - $script:Aria2LastHeartbeat).TotalSeconds -ge $script:Aria2HeartbeatEveryS) {
    Write-CleanLine "aria2: downloading…"
    $script:Aria2LastHeartbeat = $now
  }
}

function Flush-Aria2ResultsBuffer {
  if ($script:Aria2ResultsBuffer.Count -eq 0) { return }

  if (-not $script:Aria2ResultsHasError) {
    Write-CleanLine "All downloads completed without any errors."
  } else {
    Write-CleanLine ("Download Results (errors only): {0}/{1} items failed" -f $script:Aria2ErrorCount, $script:Aria2RowCount)
    # Print compact table header
    Write-CleanLine 'gid     |stat|avg speed |path/URI'
    Write-CleanLine '========+====+==========+========================================================'
    foreach ($l in $script:Aria2ResultsBuffer) {
      $m = $script:reAria2Row.Match($l)
      if ($m.Success) {
        $stat = $m.Groups[2].Value
        if ($stat -ne 'OK') { Write-CleanLine $l }
      }
    }
  }

  # Reset results state (but keep aria2 activity for a moment; heartbeat will stop itself on idle)
  $script:Aria2ResultsBuffer.Clear() | Out-Null
  $script:Aria2InResults       = $false
  $script:Aria2ResultsHasError = $false
  $script:Aria2ErrorCount      = 0
  $script:Aria2RowCount        = 0
}

function Process-Aria2Line([string]$line) {
  if ($null -eq $line) { return $false }
  $txt = $line

  # track activity for heartbeat
  if ($script:reAria2Live.IsMatch($txt) -or $script:reAria2Live2.IsMatch($txt) -or
      $script:reAria2Summary.IsMatch($txt) -or $script:reAria2Results.IsMatch($txt)) {
    $script:Aria2Active = $true
    $script:Aria2LastSeen = Get-Date
  }

  # Inside Summary block → print verbatim until a new section begins
  if ($script:Aria2InSummary) {
    if ($script:reAria2Results.IsMatch($txt) -or $script:reAria2Live.IsMatch($txt) -or $script:reAria2Live2.IsMatch($txt)) {
      $script:Aria2InSummary = $false
      # fallthrough
    } else {
      Write-CleanLine $txt
      return $true
    }
  }

  # Hide live progress lines and whitespace-only spacer lines from CR updates
  if ($script:reAria2Live.IsMatch($txt) -or $script:reAria2Live2.IsMatch($txt)) {
    Aria2-MaybeHeartbeat
    return $true
  }
  if ($txt -match '^\s+$' -and -not $script:Aria2InResults) {
    Aria2-MaybeHeartbeat
    return $true
  }

  # Summary start → print verbatim until it ends
  if ($script:reAria2Summary.IsMatch($txt)) {
    $script:Aria2InSummary = $true
    Write-CleanLine $txt
    return $true
  }

  # Results block start → buffer until end
  if ($script:reAria2Results.IsMatch($txt)) {
    Flush-Aria2ResultsBuffer
    $script:Aria2InResults = $true
    $null = $script:Aria2ResultsBuffer.Add($txt)
    return $true
  }

  if ($script:Aria2InResults) {
    $null = $script:Aria2ResultsBuffer.Add($txt)

    # Count rows & detect non-OK
    $m = $script:reAria2Row.Match($txt)
    if ($m.Success) {
      $script:Aria2RowCount++
      $stat = $m.Groups[2].Value
      if ($stat -ne 'OK') {
        $script:Aria2ResultsHasError = $true
        $script:Aria2ErrorCount++
      }
    }

    # End of results block: blank line OR start of another section (summary header) OR next live line
    if ($txt -match '^\s*$' -or $script:reAria2Summary.IsMatch($txt) -or $script:reAria2Live.IsMatch($txt) -or $script:reAria2Live2.IsMatch($txt)) {
      Flush-Aria2ResultsBuffer
    }
    return $true
  }

  return $false
}

Write-CleanLine "::notice title=Log filters::DISM in $script:DismEveryPercent% steps; aria2 live progress hidden; summary & condensed results shown; heartbeat enabled."
# --- END: DISM/cmd + aria2 log filter (inline) ---

$arch = if ($architecture -eq "x64") { "amd64" } else { "arm64" }

$ringLower = $null
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

$TARGETS = @{
  "windows-10"      = @{ search="windows 10 19045 $arch"; edition=(Get-EditionName $edition) }
  "windows-11old"   = @{ search="windows 11 22631 $arch"; edition=(Get-EditionName $edition) }
  "windows-11"      = @{ search="windows 11 26100 $arch"; edition=(Get-EditionName $edition) }
  "windows-11beta"  = @{ search="windows 11 26120 $arch"; edition=(Get-EditionName $edition); ring="Beta" }
  "windows-11dev"   = @{ search="windows 11 26200 $arch"; edition=(Get-EditionName $edition); ring="Dev" }
  "windows-11canary"= @{ search="windows 11 preview $arch"; edition=(Get-EditionName $edition); ring="Canary" }
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
          Write-CleanLine "Skipping.
L1: Expected preview=false.
L2: Got preview=true."
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
        Write-CleanLine "Skipping.
L3: Expected langs=$lang.
L4: Got langs=$($langs -join ',')."
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
            Write-CleanLine "Skipping.
L5: Expected ring match for $expectedRing, WIS or WIF. Got ring=$actual."
            $res = $false
          }
        } else {
          if ($actual -ne $expectedRing) {
            Write-CleanLine "Skipping. Expected ring match for $expectedRing. Got ring=$actual."
            $res = $false
          }
        }
      }

      if ($langs -notcontains $lang) {
        Write-CleanLine "Skipping. Expected langs=$lang. Got langs=$($langs -join ',')."
        $res = $false
      }

      if ((Get-EditionName $edition) -eq "Multi") {
        if (($editions -notcontains "Professional") -and ($editions -notcontains "Core")) {
          Write-CleanLine "Skipping.
L6: Expected editions=Multi (Professional/Core). Got editions=$($editions -join ',')."
          $res = $false
        }
      } elseif ($editions -notcontains (Get-EditionName $edition)) {
        Write-CleanLine ("Skipping. Expected editions={0}.
L7: Got editions={1}." -f (Get-EditionName $edition), ($editions -join ','))
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
        apiUrl             = 'https://api.uupdump.net/get.php?' + (New-QueryString @{ id = $id; lang = $lang; edition = if ($edition -eq "multi") { "core;professional" } else { $target.edition } })
        downloadUrl        = 'https://uupdump.net/download.php?' + (New-QueryString @{ id = $id; pack = $lang; edition = if ($edition -eq "multi") { "core;professional" } else { $target.edition } })
        downloadPackageUrl = 'https://uupdump.net/get.php?' + (New-QueryString @{ id = $id; pack = $lang; edition = if ($edition -eq "multi") { "core;professional" } else { $target.edition } })
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

function Get-WindowsIso($name, $destinationDirectory) {
  $iso = Get-UupDumpIso $name $TARGETS.$name
  if (-not $iso) {
    throw "Can't find UUP for $name ($($TARGETS.$name.search)), lang=$lang."
  }

  $isoHasEdition = $iso.PSObject.Properties.Name -contains 'edition' -and $iso.edition
  $hasVirtual    = $iso.PSObject.Properties.Name -contains 'virtualEdition' -and $iso.virtualEdition
  $effectiveEdition = if ($isoHasEdition) { $iso.edition } else { $TARGETS.$name.edition }
  $hasVirtual       = $iso -and ($iso.PSObject.Properties.Name -contains 'virtualEdition') -and $iso.virtualEdition

  if (!$preview) {
    if (-not ($iso.title -match 'version')) {
      throw "Unexpected title format: missing 'version'"
    }
    $parts = $iso.title -split 'version\s*'
    if ($parts.Count -lt 2) {
      throw "Unexpected title format, split resulted in less than 2 parts: $($parts -join '|')"
    }
    $verbuild = $parts[1] -split '[\s\(]' | Select-Object -First 1
  } else {
    $verbuild = $ringLower.ToUpper()
  }

  $buildDirectory               = "$destinationDirectory/$name"
  $destinationIsoPath           = "$buildDirectory.iso"
  $destinationIsoMetadataPath   = "$destinationIsoPath.json"
  $destinationIsoChecksumPath   = "$destinationIsoPath.sha256.txt"

  if (Test-Path $buildDirectory) {
    Remove-Item -Force -Recurse $buildDirectory | Out-Null
  }
  New-Item -ItemType Directory -Force $buildDirectory | Out-Null

  $edn = if ($hasVirtual) { $iso.virtualEdition } else { $effectiveEdition }
  Write-CleanLine $edn
  $title = "$name $edn $($iso.build)"

  Write-CleanLine "Downloading the UUP dump download package for $title from $($iso.downloadPackageUrl)"
  $downloadPackageBody = if ($hasVirtual) {
    @{ autodl=3; updates=1; cleanup=1; 'virtualEditions[]'=$iso.virtualEdition }
  } else {
    @{ autodl=2; updates=1; cleanup=1 }
  }
  Invoke-WebRequest -Method Post -Uri $iso.downloadPackageUrl -Body $downloadPackageBody -OutFile "$buildDirectory.zip" | Out-Null
  Expand-Archive "$buildDirectory.zip" $buildDirectory

  $convertConfig = (Get-Content $buildDirectory/ConvertConfig.ini) `
    -replace '^(AutoExit\s*)=.*','$1=1' `
    -replace '^(ResetBase\s*)=.*','$1=1' `
    -replace '^(Cleanup\s*)=.*','$1=1'

  $tag = ""
  if ($esd) {
    $convertConfig = $convertConfig -replace '^(wim2esd\s*)=.*', '$1=1'
    $tag += ".E"
  }
  if ($drivers -and $arch -ne "arm64") {
    $convertConfig = $convertConfig -replace '^(AddDrivers\s*)=.*', '$1=1'
    $tag += ".D"
    Write-CleanLine "Copy Dell drivers to $buildDirectory directory"
    Copy-Item -Path Drivers -Destination $buildDirectory/Drivers -Recurse
  }
  if ($netfx3) {
    $convertConfig = $convertConfig -replace '^(NetFx3\s*)=.*', '$1=1'
    $tag += ".N"
  }
  if ($hasVirtual) {
    $convertConfig = $convertConfig `
      -replace '^(StartVirtual\s*)=.*','$1=1' `
      -replace '^(vDeleteSource\s*)=.*','$1=1' `
      -replace '^(vAutoEditions\s*)=.*',"`$1=$($iso.virtualEdition)"
  }
  Set-Content -Encoding ascii -Path $buildDirectory/ConvertConfig.ini -Value $convertConfig

  Write-CleanLine "Creating the $title iso file inside the $buildDirectory directory"
  Push-Location $buildDirectory

  # --- Filtered execution: DISM progress buckets + aria2 filtering & heartbeat ---
  powershell cmd /c uup_download_windows.cmd 2>&1 |
    ForEach-Object {
      $raw = [string]$_
      if ([string]::IsNullOrEmpty($raw)) { return }
      foreach ($crChunk in ($raw -split "`r")) {
        foreach ($line in ($crChunk -split "`n")) {
          if ($line -eq $null) { continue }

          # aria2 filter first (live progress hidden, summary printed, results condensed, heartbeat)
          if (Process-Aria2Line $line) { continue }

          # DISM progress buckets
          if (-not (Process-ProgressLine $line)) {
            # Heuristics: new DISM phase markers → reset
            if ($line -match '^\s*(Mounting image|Saving image|Applying image|Exporting image|Unmounting image|Deployment Image Servicing and Management tool|^=== )') {
              Reset-ProgressSession
            }
            # Default passthrough
            if ($line -eq '') { Write-CleanLine '' } else { Write-CleanLine $line }
          }
        }
      }
    }

  # Final flush (in case a results block ended without a blank line)
  Flush-Aria2ResultsBuffer

  if ($LASTEXITCODE) {
    throw "uup_download_windows.cmd failed with exit code $LASTEXITCODE"
  }

  Pop-Location

  $sourceIsoPath = Resolve-Path $buildDirectory/*.iso
  $IsoName = Split-Path $sourceIsoPath -leaf

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
  Move-Item -Force $sourceIsoPath "$destinationDirectory/$IsoName"

  Write-Output "ISO_NAME=$IsoName" | Out-File -FilePath $env:GITHUB_ENV -Encoding utf8 -Append
  Write-CleanLine 'All Done.'
}

Get-WindowsIso $windowsTargetName $destinationDirectory
