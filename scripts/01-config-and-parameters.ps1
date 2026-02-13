#!/usr/bin/pwsh
# Script 1: Configuration and Parameters
# This script defines all the parameters and configuration needed for the Windows ISO download process

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

# Set global variables
$script:preview = $false
$script:ringLower = $null

# Error handling
trap {
  Write-Host "ERROR: $_"
  @(($_.ScriptStackTrace -split '\r?\n') -replace '^(.*)$','ERROR: $1') | Write-Host
  @(($_.Exception.ToString() -split '\r?\n') -replace '^(.*)$','ERROR EXCEPTION: $1') | Write-Host
  Exit 1
}

# Determine architecture
$script:arch = if ($architecture -eq "x64") { "amd64" } else { "arm64" }

# Check if this is a preview build
if ($windowsTargetName -match 'beta|dev|wif|canary') {
  $script:preview = $true
  $script:ringLower = @('beta','dev','wif','canary').Where({$windowsTargetName -match $_})[0]
}

# Define edition name mapping
function Get-EditionName($e) {
  switch ($e.ToLower()) {
    "core"  { "Core" }
    "home"  { "Core" }
    "multi" { "Multi" }
    default { "Professional" }
  }
}

# Define Windows targets
$script:TARGETS = @{
  "windows-10"       = @{ search="windows 10 19045 $arch"; edition=(Get-EditionName $edition) }
  "windows-11old"    = @{ search="windows 11 22631 $arch"; edition=(Get-EditionName $edition) }
  "windows-11"       = @{ search="windows 11 26100 $arch"; edition=(Get-EditionName $edition) }
  "windows-11new"    = @{ search="windows 11 26200 $arch"; edition=(Get-EditionName $edition) }
  "windows-11beta"   = @{ search="windows 11 26120 $arch"; edition=(Get-EditionName $edition); ring="Beta" }
  "windows-11dev"    = @{ search="windows 11 26220 $arch"; edition=(Get-EditionName $edition); ring="Wif" }
  "windows-11canary" = @{ search="windows 11 $arch"; edition=(Get-EditionName $edition); ring="Canary" }
}

# Export configuration as a JSON file for other scripts to use
$config = @{
  windowsTargetName = $windowsTargetName
  destinationDirectory = $destinationDirectory
  architecture = $architecture
  arch = $script:arch
  edition = $edition
  lang = $lang
  esd = $esd.IsPresent
  drivers = $drivers.IsPresent
  netfx3 = $netfx3.IsPresent
  preview = $script:preview
  ringLower = $script:ringLower
  targets = $script:TARGETS
}

$configPath = ".\windows-iso-config.json"
$config | ConvertTo-Json -Depth 10 | Set-Content $configPath

Write-Host "Configuration saved to $configPath"
Write-Host "Target: $windowsTargetName"
Write-Host "Architecture: $architecture ($($script:arch))"
Write-Host "Edition: $edition"
Write-Host "Language: $lang"
Write-Host "Preview: $($script:preview)"
