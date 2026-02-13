#!/usr/bin/pwsh
# Script 8: Cleanup and Organize Output
# This script moves the ISO to the final destination and cleans up temporary files

param(
  [string]$configPath = ".\windows-iso-config.json",
  [string]$buildInfoPath = ".\build-info.json",
  [switch]$keepBuildDirectory
)

Set-StrictMode -Version Latest
$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Stop'

# Import helper functions
. .\02-helper-functions.ps1

# Load configuration
if (-not (Test-Path $configPath)) {
  throw "Configuration file not found: $configPath"
}
$config = Get-Content $configPath | ConvertFrom-Json

# Load build info
if (-not (Test-Path $buildInfoPath)) {
  throw "Build info file not found: $buildInfoPath"
}
$buildInfo = Get-Content $buildInfoPath | ConvertFrom-Json

# Get paths
$sourceIsoPath = $buildInfo.sourceIsoPath
$buildDirectory = $buildInfo.buildDirectory
$destinationDirectory = $config.destinationDirectory

if (-not (Test-Path $sourceIsoPath)) {
  throw "ISO file not found: $sourceIsoPath"
}

# Ensure destination directory exists
if (-not (Test-Path $destinationDirectory)) {
  New-Item -ItemType Directory -Force $destinationDirectory | Out-Null
}

# Get ISO filename
$isoFileName = Split-Path $sourceIsoPath -Leaf
$destinationIsoPath = Join-Path $destinationDirectory $isoFileName

Write-CleanLine "Moving ISO to final destination..."
Write-CleanLine "From: $sourceIsoPath"
Write-CleanLine "To: $destinationIsoPath"

# Move ISO file
Move-Item -Force $sourceIsoPath $destinationIsoPath

# Move metadata and checksum files if they exist
$metadataSource = "$sourceIsoPath.json"
$checksumSource = "$sourceIsoPath.sha256.txt"

if (Test-Path $metadataSource) {
  $metadataDestination = "$destinationIsoPath.json"
  Move-Item -Force $metadataSource $metadataDestination
  Write-CleanLine "Moved metadata to: $metadataDestination"
}

if (Test-Path $checksumSource) {
  $checksumDestination = "$destinationIsoPath.sha256.txt"
  Move-Item -Force $checksumSource $checksumDestination
  Write-CleanLine "Moved checksum to: $checksumDestination"
}

# Clean up build directory unless requested to keep it
if (-not $keepBuildDirectory) {
  if (Test-Path $buildDirectory) {
    Write-CleanLine "Removing build directory: $buildDirectory"
    Remove-Item -Force -Recurse $buildDirectory
    Write-CleanLine "Build directory removed"
  }
  
  # Remove the downloaded zip file if it exists
  $zipFile = "$buildDirectory.zip"
  if (Test-Path $zipFile) {
    Write-CleanLine "Removing download package: $zipFile"
    Remove-Item -Force $zipFile
  }
} else {
  Write-CleanLine "Keeping build directory: $buildDirectory"
}

# Set environment variable if running in GitHub Actions
if ($env:GITHUB_ENV) {
  Write-Output "ISO_NAME=$isoFileName" | Out-File -FilePath $env:GITHUB_ENV -Encoding utf8 -Append
  Write-CleanLine "Set GITHUB_ENV variable: ISO_NAME=$isoFileName"
}

# Create final summary
Write-Host "`n========================================="
Write-Host "Windows ISO Creation Complete!"
Write-Host "========================================="
Write-Host "ISO File: $destinationIsoPath"
Write-Host "Size: $([math]::Round((Get-Item $destinationIsoPath).Length / 1GB, 2)) GB"
Write-Host "Checksum: $($buildInfo.checksum)"
Write-Host "Title: $($buildInfo.title)"
Write-Host "Tags: $($buildInfo.tags)"
Write-Host "========================================="
Write-Host "`nAll done!"
