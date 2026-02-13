#!/usr/bin/pwsh
# Script 4: Download UUP Dump Package
# This script downloads and extracts the UUP Dump conversion package

param(
  [string]$configPath = ".\windows-iso-config.json",
  [string]$metadataPath = ".\uup-dump-metadata.json"
)

Set-StrictMode -Version Latest
$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Stop'

# Import helper functions
Import-Module "$PSScriptRoot\HelperFunctions.psm1" -Force

# Load configuration
if (-not (Test-Path $configPath)) {
  throw "Configuration file not found: $configPath"
}
$config = Get-Content $configPath | ConvertFrom-Json

# Load ISO metadata
if (-not (Test-Path $metadataPath)) {
  throw "ISO metadata file not found: $metadataPath. Please run 03-uup-api-functions.ps1 first."
}
$iso = Get-Content $metadataPath | ConvertFrom-Json

# Setup directories
$name = $config.windowsTargetName
$buildDirectory = "$($config.destinationDirectory)/$name"

if (Test-Path $buildDirectory) { 
  Remove-Item -Force -Recurse $buildDirectory | Out-Null 
}
New-Item -ItemType Directory -Force $buildDirectory | Out-Null

# Determine edition name
$isoHasEdition = $iso.PSObject.Properties.Name -contains 'edition' -and $iso.edition
$hasVirtualMember = $iso.PSObject.Properties.Name -contains 'virtualEdition' -and $iso.virtualEdition

# Convert targets to hashtable
$targetsHash = @{}
$config.targets.PSObject.Properties | ForEach-Object {
  $targetsHash[$_.Name] = $_.Value
}

$targetConfig = $targetsHash[$name]
$effectiveEdition = if ($isoHasEdition) { $iso.edition } else { $targetConfig.edition }

$edn = if ($hasVirtualMember) { $iso.virtualEdition } else { $effectiveEdition }
$title = "$name $edn $($iso.build)"

Write-CleanLine "Downloading the UUP dump download package for $title"
Write-CleanLine "From: $($iso.downloadPackageUrl)"

# Prepare download parameters
$downloadPackageBody = if ($hasVirtualMember) { 
  @{ 
    autodl = 3
    updates = 1
    cleanup = 1
    'virtualEditions[]' = $iso.virtualEdition 
  } 
} else { 
  @{ 
    autodl = 2
    updates = 1
    cleanup = 1 
  } 
}

# Download the package
$downloadPath = "$buildDirectory.zip"
Invoke-WebRequest -Method Post -Uri $iso.downloadPackageUrl -Body $downloadPackageBody -OutFile $downloadPath | Out-Null

Write-CleanLine "Package downloaded to $downloadPath"
Write-CleanLine "Extracting package to $buildDirectory"

# Extract the package
Expand-Archive $downloadPath $buildDirectory

Write-CleanLine "Package extracted successfully"

# Save build directory path for next script
$buildInfo = @{
  buildDirectory = $buildDirectory
  title = $title
  edition = $edn
}
$buildInfo | ConvertTo-Json | Set-Content ".\build-info.json"

Write-Host "Build directory: $buildDirectory"
Write-Host "Build info saved to .\build-info.json"