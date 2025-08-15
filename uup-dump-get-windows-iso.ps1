#!/usr/bin/pwsh
param(
    [string]$windowsTargetName,
    [string]$destinationDirectory='output',
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
$preview   = $false
$ringLower = $null
trap {
    Write-Host "ERROR: $_"
    @(($_.ScriptStackTrace -split '\r?\n') -replace '^(.*)$','ERROR: $1') | Write-Host
    @(($_.Exception.ToString() -split '\r?\n') -replace '^(.*)$','ERROR EXCEPTION: $1') | Write-Host
    Exit 1
}

$arch = if ($architecture -eq "x64") { "amd64" } else { "arm64" }

$ringLower = $null
if ($windowsTargetName -match 'beta|dev|canary') {
    $preview = $true
    $ringLower = @('beta','dev','canary').Where({$windowsTargetName -match $_})[0]
}

if ($ringLower -eq 'dev') {
    $ringLower = 'dev|wif'
}

if ($ringLower -eq 'beta') {
    $ringLower = 'beta|wif'
}

function Get-EditionName($e) {
    switch ($e.ToLower()) {
        "core" { "Core" }
        "home" { "Core" }
        "multi" { "Multi" }
        default { "Professional" }
    }
}

$TARGETS = @{
    "windows-10"       = @{ search="windows 10 19045 $arch";       edition=(Get-EditionName $edition) }
    "windows-11old"    = @{ search="windows 11 22631 $arch";       edition=(Get-EditionName $edition) }
    "windows-11"       = @{ search="windows 11 26100 $arch";       edition=(Get-EditionName $edition) }
    "windows-11beta"   = @{ search="windows 11 26120 $arch";       edition=(Get-EditionName $edition); ring="Beta" }
    "windows-11dev"    = @{ search="windows 11 26200 $arch";       edition=(Get-EditionName $edition); ring="Dev" }
    "windows-11canary" = @{ search="windows 11 preview $arch";     edition=(Get-EditionName $edition); ring="Canary" }
}

function New-QueryString([hashtable]$parameters) {
    @($parameters.GetEnumerator() | ForEach-Object { "$($_.Key)=$([System.Net.WebUtility]::UrlEncode([string]$_.Value))" }) -join '&'
}

function Invoke-UupDumpApi([string]$name, [hashtable]$body) {
    for ($n = 0; $n -lt 15; ++$n) {
        if ($n) {
            Write-Host "Waiting a bit before retrying the uup-dump api ${name} request #$n"
            Start-Sleep -Seconds 10
            Write-Host "Retrying the uup-dump api ${name} request #$n"
        }
        try {
            $qs = if ($body) { '?' + (New-QueryString $body) } else { '' }
            return Invoke-RestMethod -Method Get -Uri ("https://api.uupdump.net/{0}.php{1}" -f $name, $qs)
        } catch {
            Write-Host "WARN: failed the uup-dump api $name request: $_"
        }
    }
    throw "timeout making the uup-dump api $name request"
}

function Get-UupDumpIso($name, $target) {
    Write-Host "Getting the $name metadata"
    $result = Invoke-UupDumpApi listid @{ search = $target.search }
    $result.response.builds.PSObject.Properties |
        ForEach-Object {
            $id = $_.Value.uuid
            $uupDumpUrl = 'https://uupdump.net/selectlang.php?' + (New-QueryString @{ id = $id })
            Write-Host "Processing $name $id ($uupDumpUrl)"
            $_
        } |
        Where-Object {
            if (!$preview) {
                $ok = ($target.search -like '*preview*') -or ($_.Value.title -notlike '*preview*')
                if (-not $ok) { Write-Host "Skipping. Expected preview=false. Got preview=true." }
                return $ok
            }
            $true
        } |
        ForEach-Object {
            $id = $_.Value.uuid
            Write-Host "Getting the $name $id langs metadata"
            $result = Invoke-UupDumpApi listlangs @{ id = $id }
            if ($result.response.updateInfo.build -ne $_.Value.build) { throw 'for some reason listlangs returned an unexpected build' }
            $_.Value | Add-Member -NotePropertyMembers @{ langs = $result.response.langFancyNames; info = $result.response.updateInfo }
            $langs = $_.Value.langs.PSObject.Properties.Name
            $eds = if ($langs -contains $lang) {
                Write-Host "Getting the $name $id editions metadata"
                $result = Invoke-UupDumpApi listeditions @{ id = $id; lang = $lang }
                $result.response.editionFancyNames
            } else {
                Write-Host "Skipping. Expected langs=$lang. Got langs=$($langs -join ',')."
                [PSCustomObject]@{}
            }
            $_.Value | Add-Member -NotePropertyMembers @{ editions = $eds }
            $_
        } |
        Where-Object {
            $langs = $_.Value.langs.PSObject.Properties.Name
            $editions = $_.Value.editions.PSObject.Properties.Name
            $res = $true
            $expectedRing = if ($ringLower) { $ringLower.ToUpper() } else { 'RETAIL' }
            if ($ringLower -and ($_.Value.info.ring -notmatch $ringLower)) {
                Write-Host "Skipping. Expected ring match for $ringLower. Got ring=$($_.Value.info.ring)."
                $res = $false
            }
            if ($langs -notcontains $lang) {
                Write-Host "Skipping. Expected langs=$lang. Got langs=$($langs -join ',')."
                $res = $false
            }
            if ((Get-EditionName $edition) -eq "Multi") {
                if (($editions -notcontains "Professional") -and ($editions -notcontains "Core")) {
                    Write-Host "Skipping. Expected editions=Multi (Professional/Core). Got editions=$($editions -join ',')."
                    $res = $false
                }
            } elseif ($editions -notcontains (Get-EditionName $edition)) {
                Write-Host "Skipping. Expected editions=$(Get-EditionName $edition). Got editions=$($editions -join ',')."
                $res = $false
            }
            $res
        } |
        Select-Object -First 1 |
        ForEach-Object {
            $id = $_.Value.uuid
            [PSCustomObject]@{
                name = $name
                title = $_.Value.title
                build = $_.Value.build
                id = $id
                edition = $target.edition
                virtualEdition = $target['virtualEdition']
                apiUrl = 'https://api.uupdump.net/get.php?' + (New-QueryString @{ id = $id; lang = $lang; edition = if ($edition -eq "multi") { "core;professional" } else { $target.edition } })
                downloadUrl = 'https://uupdump.net/download.php?' + (New-QueryString @{ id = $id; pack = $lang; edition = if ($edition -eq "multi") { "core;professional" } else { $target.edition } })
                downloadPackageUrl = 'https://uupdump.net/get.php?' + (New-QueryString @{ id = $id; pack = $lang; edition = if ($edition -eq "multi") { "core;professional" } else { $target.edition } })
            }
        }
}

function Get-IsoWindowsImages($isoPath) {
    $isoPath = Resolve-Path $isoPath
    Write-Host "Mounting $isoPath"
    $isoImage = Mount-DiskImage $isoPath -PassThru
    try {
        $isoVolume = $isoImage | Get-Volume
        $installPath = if ($esd) { "$($isoVolume.DriveLetter):\sources\install.esd" } else { "$($isoVolume.DriveLetter):\sources\install.wim" }
        Write-Host "Getting Windows images from $installPath"
        Get-WindowsImage -ImagePath $installPath | ForEach-Object {
            $image = Get-WindowsImage -ImagePath $installPath -Index $_.ImageIndex
            [PSCustomObject]@{ index = $image.ImageIndex; name = $image.ImageName; version = $image.Version }
        }
    } finally {
        Write-Host "Dismounting $isoPath"
        Dismount-DiskImage $isoPath | Out-Null
    }
}

function Get-WindowsIso($name, $destinationDirectory) {
    $iso = Get-UupDumpIso $name $TARGETS.$name
    if (-not $iso) { throw "Brak dopasowania UUP dla $name ($($TARGETS.$name.search)), lang=$lang." }
    $isoHasEdition  = $iso.PSObject.Properties.Name -contains 'edition' -and $iso.edition
    $hasVirtual     = $iso.PSObject.Properties.Name -contains 'virtualEdition' -and $iso.virtualEdition
    $effectiveEdition = if ($isoHasEdition) { $iso.edition } else { $TARGETS.$name.edition }
    $hasVirtual = $iso -and ($iso.PSObject.Properties.Name -contains 'virtualEdition') -and $iso.virtualEdition
    if (!$preview) {
        if (-not ($iso.title -match 'version')) { throw "Unexpected title format: missing 'version'" }
        $parts = $iso.title -split 'version\s*'
        if ($parts.Count -lt 2) { throw "Unexpected title format, split resulted in less than 2 parts: $($parts -join '|')" }
        $verbuild = $parts[1] -split '[\s\(]' | Select-Object -First 1
    } else {
        $verbuild = $ringLower
    }

    $buildDirectory = "$destinationDirectory/$name"
    $destinationIsoPath = "$buildDirectory.iso"
    $destinationIsoMetadataPath = "$destinationIsoPath.json"
    $destinationIsoChecksumPath = "$destinationIsoPath.sha256.txt"

    if (Test-Path $buildDirectory) { Remove-Item -Force -Recurse $buildDirectory | Out-Null }
    New-Item -ItemType Directory -Force $buildDirectory | Out-Null

    $edn = if ($hasVirtual) { $iso.virtualEdition } else { $effectiveEdition }
    Write-Host $edn
    $title = "$name $edn $($iso.build)"

    Write-Host "Downloading the UUP dump download package for $title from $($iso.downloadPackageUrl)"
    $downloadPackageBody = if ($hasVirtual) { @{ autodl=3; updates=1; cleanup=1; 'virtualEditions[]'=$iso.virtualEdition } } else { @{ autodl=2; updates=1; cleanup=1 } }
    Invoke-WebRequest -Method Post -Uri $iso.downloadPackageUrl -Body $downloadPackageBody -OutFile "$buildDirectory.zip" | Out-Null
    Expand-Archive "$buildDirectory.zip" $buildDirectory

    $convertConfig = (Get-Content $buildDirectory/ConvertConfig.ini) `
        -replace '^(AutoExit\s*)=.*','$1=1' `
        -replace '^(ResetBase\s*)=.*','$1=1' `
        -replace '^(Cleanup\s*)=.*','$1=1'
    $tag = ""
    if ($esd) { $convertConfig = $convertConfig -replace '^(wim2esd\s*)=.*', '$1=1'; $tag += ".E" }
    if ($drivers -and $arch -ne "arm64") { $convertConfig = $convertConfig -replace '^(AddDrivers\s*)=.*', '$1=1'; $tag += ".D"; Write-Host "Copy Dell drivers to $buildDirectory directory"; Copy-Item -Path Drivers -Destination $buildDirectory/Drivers -Recurse }
    if ($netfx3) { $convertConfig = $convertConfig -replace '^(NetFx3\s*)=.*', '$1=1'; $tag += ".N" }
    if ($hasVirtual) {
    $convertConfig = $convertConfig `
        -replace '^(StartVirtual\s*)=.*','$1=1' `
        -replace '^(vDeleteSource\s*)=.*','$1=1' `
        -replace '^(vAutoEditions\s*)=.*',"`$1=$($iso.virtualEdition)"
    }
    Set-Content -Encoding ascii -Path $buildDirectory/ConvertConfig.ini -Value $convertConfig

    Write-Host "Creating the $title iso file inside the $buildDirectory directory"
    Push-Location $buildDirectory
    powershell cmd /c uup_download_windows.cmd | Out-String -Stream
    if ($LASTEXITCODE) { throw "uup_download_windows.cmd failed with exit code $LASTEXITCODE" }
    Pop-Location

    $sourceIsoPath = Resolve-Path $buildDirectory/*.iso
    $IsoName = Split-Path $sourceIsoPath -leaf

    Write-Host "Getting the $sourceIsoPath checksum"
    $isoChecksum = (Get-FileHash -Algorithm SHA256 $sourceIsoPath).Hash.ToLowerInvariant()
    Set-Content -Encoding ascii -NoNewline -Path $destinationIsoChecksumPath -Value $isoChecksum

    $windowsImages = Get-IsoWindowsImages $sourceIsoPath

    Set-Content -Path $destinationIsoMetadataPath -Value (
        ([PSCustomObject]@{
            name = $name
            title = $iso.title
            build = $iso.build
            version = $verbuild
            tags = $tag
            checksum = $isoChecksum
            images = @($windowsImages)
            uupDump = @{
                id = $iso.id
                apiUrl = $iso.apiUrl
                downloadUrl = $iso.downloadUrl
                downloadPackageUrl = $iso.downloadPackageUrl
            }
        } | ConvertTo-Json -Depth 99) -replace '\\u0026','&'
    )

    Write-Host "Moving the created $sourceIsoPath to $destinationDirectory/$IsoName"
    Move-Item -Force $sourceIsoPath "$destinationDirectory/$IsoName"
    Write-Output "ISO_NAME=$IsoName" | Out-File -FilePath $env:GITHUB_ENV -Encoding utf8 -Append
    Write-Host 'All Done.'
}

Get-WindowsIso $windowsTargetName $destinationDirectory
