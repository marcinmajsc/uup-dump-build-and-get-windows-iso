#!/usr/bin/pwsh
# Master Script: Run All Steps
# This script orchestrates the entire Windows ISO download and creation process

param(
  [string]$windowsTargetName,
  [string]$destinationDirectory = 'output',
  [ValidateSet("x64", "arm64")] [string]$architecture = "x64",
  [ValidateSet("pro", "core", "multi", "home")] [string]$edition = "pro",
  [ValidateSet("nb-no", "fr-ca", "fi-fi", "lv-lv", "es-es", "en-gb", "zh-tw", "th-th", "sv-se", "en-us", "es-mx", "bg-bg", "hr-hr", "pt-br", "el-gr", "cs-cz", "it-it", "sk-sk", "pl-pl", "sl-si", "neutral", "ja-jp", "et-ee", "ro-ro", "fr-fr", "pt-pt", "ar-sa", "lt-lt", "hu-hu", "da-dk", "zh-cn", "uk-ua", "tr-tr", "ru-ru", "nl-nl", "he-il", "ko-kr", "sr-latn-rs", "de-de")]
  [string]$lang = "en-us",
  [switch]$esd,
  [switch]$drivers,
  [switch]$netfx3,
  [switch]$keepBuildDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptDir = $PSScriptRoot
if (-not $scriptDir) { $scriptDir = Get-Location }

Write-Host "========================================="
Write-Host "Windows ISO Creation - Full Process"
Write-Host "========================================="
Write-Host "Target: $windowsTargetName"
Write-Host "Architecture: $architecture"
Write-Host "Edition: $edition"
Write-Host "Language: $lang"
Write-Host "========================================="
Write-Host ""

# Step 1: Configuration and Parameters
Write-Host "[1/8] Setting up configuration..."
& "$scriptDir\01-config-and-parameters.ps1" `
  -windowsTargetName $windowsTargetName `
  -destinationDirectory $destinationDirectory `
  -architecture $architecture `
  -edition $edition `
  -lang $lang `
  -esd:$esd `
  -drivers:$drivers `
  -netfx3:$netfx3

if ($LASTEXITCODE) { throw "Step 1 failed with exit code $LASTEXITCODE" }
Write-Host ""

# Step 2: Helper functions are loaded via dot-sourcing in other scripts
Write-Host "[2/8] Helper functions ready"
Write-Host ""

# Step 3: Query UUP Dump API
Write-Host "[3/8] Querying UUP Dump API..."
& "$scriptDir\03-uup-api-functions.ps1"
if ($LASTEXITCODE) { throw "Step 3 failed with exit code $LASTEXITCODE" }
Write-Host ""

# Step 4: Download UUP Package
Write-Host "[4/8] Downloading UUP dump package..."
& "$scriptDir\04-download-package.ps1"
if ($LASTEXITCODE) { throw "Step 4 failed with exit code $LASTEXITCODE" }
Write-Host ""

# Step 5: Configure Conversion
Write-Host "[5/8] Configuring conversion settings..."
& "$scriptDir\05-configure-conversion.ps1"
if ($LASTEXITCODE) { throw "Step 5 failed with exit code $LASTEXITCODE" }
Write-Host ""

# Step 6: Create ISO
Write-Host "[6/8] Creating Windows ISO (this may take a while)..."
& "$scriptDir\06-create-iso.ps1"
if ($LASTEXITCODE) { throw "Step 6 failed with exit code $LASTEXITCODE" }
Write-Host ""

# Step 7: Validate and Generate Metadata
Write-Host "[7/8] Validating ISO and generating metadata..."
& "$scriptDir\07-validate-and-metadata.ps1"
if ($LASTEXITCODE) { throw "Step 7 failed with exit code $LASTEXITCODE" }
Write-Host ""

# Step 8: Cleanup and Organize
Write-Host "[8/8] Organizing output and cleaning up..."
$cleanupArgs = @{}
if ($keepBuildDirectory) { $cleanupArgs['keepBuildDirectory'] = $true }
& "$scriptDir\08-cleanup-and-organize.ps1" @cleanupArgs
if ($LASTEXITCODE) { throw "Step 8 failed with exit code $LASTEXITCODE" }
Write-Host ""

Write-Host "========================================="
Write-Host "Process completed successfully!"
Write-Host "========================================="
