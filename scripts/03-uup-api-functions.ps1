#!/usr/bin/pwsh
# Script 3: UUP Dump API Functions
# This script handles all interactions with the UUP Dump API

param(
  [string]$configPath = ".\windows-iso-config.json"
)

Set-StrictMode -Version Latest
$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Stop'

# Import helper functions
Import-Module "$PSScriptRoot\HelperFunctions.psm1" -Force

# Load configuration
if (-not (Test-Path $configPath)) {
  throw "Configuration file not found: $configPath. Please run 01-config-and-parameters.ps1 first."
}
$config = Get-Content $configPath | ConvertFrom-Json

# ------------------------------
# API Helper Functions
# ------------------------------
function New-QueryString([hashtable]$parameters) {
  @($parameters.GetEnumerator() | ForEach-Object { 
    "$($_.Key)=$([System.Net.WebUtility]::UrlEncode([string]$_.Value))" 
  }) -join '&'
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

  $selectedBuild = $result.response.builds.PSObject.Properties `
  | ForEach-Object {
      $id = $_.Value.uuid
      $uupDumpUrl = 'https://uupdump.net/selectlang.php?' + (New-QueryString @{ id = $id })
      Write-CleanLine "Processing $name $id ($uupDumpUrl)"
      $_
    } `
  | Where-Object {
      if (!$config.preview) {
        $ok = ($target.search -like '*preview*') -or ($_.Value.title -notlike '*preview*')
        if (-not $ok) {
          Write-CleanLine "Skipping.`nL1: Expected preview=false.`nL2: Got preview=true."
        }
        return $ok
      }
      $true
    } `
  | ForEach-Object {
      $id = $_.Value.uuid
      Write-CleanLine "Getting the $name $id langs metadata"
      $result = Invoke-UupDumpApi listlangs @{ id = $id }
      if ($result.response.updateInfo.build -ne $_.Value.build) {
        throw 'for some reason listlangs returned an unexpected build'
      }
      $_.Value | Add-Member -NotePropertyMembers @{ 
        langs = $result.response.langFancyNames
        info = $result.response.updateInfo 
      }

      $langs = $_.Value.langs.PSObject.Properties.Name
      $eds = if ($langs -contains $config.lang) {
        Write-CleanLine "Getting the $name $id editions metadata"
        $result = Invoke-UupDumpApi listeditions @{ id = $id; lang = $config.lang }
        $result.response.editionFancyNames
      } else {
        Write-CleanLine "Skipping.`nL3: Expected langs=$($config.lang).`nL4: Got langs=$($langs -join ',')."
        [PSCustomObject]@{}
      }
      $_.Value | Add-Member -NotePropertyMembers @{ editions = $eds }
      $_
    } `
  | Where-Object {
      $langs = $_.Value.langs.PSObject.Properties.Name
      $editions = $_.Value.editions.PSObject.Properties.Name
      $res = $true

      if ($langs -notcontains $config.lang) {
        Write-CleanLine "Skipping.`nL5: Expected langs=$($config.lang).`nL6: Got langs=$($langs -join ',')."
        $res = $false
      }

      if ($res -and ($target.edition -ne 'Multi') -and $editions -notcontains $target.edition) {
        Write-CleanLine "Skipping.`nL7: Expected editions=$($target.edition).`nL8: Got editions=$($editions -join ',')."
        $res = $false
      }

      if ($res -and $target.PSObject.Properties.Name -contains 'ring' -and $target.ring) {
        if ($_.Value.info.ring -and ($_.Value.info.ring -ne $target.ring)) {
          Write-CleanLine "Skipping.`nL9: Expected ring=$($target.ring).`nL10: Got ring=$($_.Value.info.ring)."
          $res = $false
        }
      }

      $res
    } `
  | Select-Object -First 1

  if (-not $selectedBuild) {
    return $null
  }

  $id = $selectedBuild.Value.uuid
  [PSCustomObject]@{
    id                 = $id
    build              = $selectedBuild.Value.build
    title              = $selectedBuild.Value.title
    edition            = $target['edition']
    virtualEdition     = $target['virtualEdition']
    apiUrl             = 'https://api.uupdump.net/get.php?' + (New-QueryString @{ 
      id = $id
      lang = $config.lang
      edition = if ($config.edition -eq "multi") { "core;professional" } else { $target.edition } 
    })
    downloadUrl        = 'https://uupdump.net/download.php?' + (New-QueryString @{ 
      id = $id
      pack = $config.lang
      edition = if ($config.edition -eq "multi") { "core;professional" } else { $target.edition } 
    })
    downloadPackageUrl = 'https://uupdump.net/get.php?' + (New-QueryString @{ 
      id = $id
      pack = $config.lang
      edition = if ($config.edition -eq "multi") { "core;professional" } else { $target.edition } 
    })
  }
}

# Main execution
Write-Host "Querying UUP Dump API for: $($config.windowsTargetName)"

# Convert targets PSObject to hashtable for easier access
$targetsHash = @{}
$config.targets.PSObject.Properties | ForEach-Object {
  $targetsHash[$_.Name] = $_.Value
}

$targetConfig = $targetsHash[$config.windowsTargetName]
if (-not $targetConfig) {
  throw "Unknown Windows target: $($config.windowsTargetName)"
}

# Convert targetConfig PSObject to hashtable
$targetConfigHash = @{}
$targetConfig.PSObject.Properties | ForEach-Object {
  $targetConfigHash[$_.Name] = $_.Value
}

$iso = Get-UupDumpIso $config.windowsTargetName $targetConfigHash

if (-not $iso) {
  throw "Can't find UUP for $($config.windowsTargetName) ($($targetConfigHash.search)), lang=$($config.lang)."
}

# Save ISO metadata
$isoMetadataPath = ".\uup-dump-metadata.json"
$iso | ConvertTo-Json -Depth 10 | Set-Content $isoMetadataPath

Write-Host "ISO metadata saved to $isoMetadataPath"
Write-Host "Build: $($iso.build)"
Write-Host "Title: $($iso.title)"
Write-Host "Download URL: $($iso.downloadUrl)"