#!/usr/bin/pwsh
# Script 7: Validate and Generate ISO Metadata
# This script validates the ISO, extracts Windows images info, and generates metadata

param(
  [string]$configPath = ".\windows-iso-config.json",
  [string]$buildInfoPath = ".\build-info.json",
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

# Load build info
if (-not (Test-Path $buildInfoPath)) {
  throw "Build info file not found: $buildInfoPath"
}
$buildInfo = Get-Content $buildInfoPath | ConvertFrom-Json

# Load ISO metadata
if (-not (Test-Path $metadataPath)) {
  throw "ISO metadata file not found: $metadataPath"
}
$iso = Get-Content $metadataPath | ConvertFrom-Json

# Get source ISO path
$sourceIsoPath = $buildInfo.sourceIsoPath
if (-not (Test-Path $sourceIsoPath)) {
  throw "ISO file not found: $sourceIsoPath"
}

Write-CleanLine "Validating ISO: $sourceIsoPath"

# Function to get Windows images from ISO
function Get-IsoWindowsImages($isoPath) {
  $isoPath = Resolve-Path $isoPath
  Write-CleanLine "Mounting $isoPath"
  
  $isoImage = Mount-DiskImage $isoPath -PassThru
  try {
    $isoVolume = $isoImage | Get-Volume
    $installPath = if ($config.esd) { 
      "$($isoVolume.DriveLetter):\sources\install.esd" 
    } else { 
      "$($isoVolume.DriveLetter):\sources\install.wim" 
    }
    
    Write-CleanLine "Getting Windows images from $installPath"
    
    Get-WindowsImage -ImagePath $installPath | ForEach-Object {
      $image = Get-WindowsImage -ImagePath $installPath -Index $_.ImageIndex
      [PSCustomObject]@{ 
        index = $image.ImageIndex
        name = $image.ImageName
        version = $image.Version 
      }
    }
  }
  finally {
    Write-CleanLine "Dismounting $isoPath"
    Dismount-DiskImage $isoPath | Out-Null
  }
}

# Get Windows images information
Write-CleanLine "Extracting Windows images information..."
$windowsImages = Get-IsoWindowsImages $sourceIsoPath

Write-CleanLine "Found $($windowsImages.Count) Windows image(s):"
foreach ($img in $windowsImages) {
  Write-CleanLine "  [$($img.index)] $($img.name) - Version $($img.version)"
}

# Calculate checksum
Write-CleanLine "Calculating SHA256 checksum..."
$isoChecksum = (Get-FileHash -Algorithm SHA256 $sourceIsoPath).Hash.ToLowerInvariant()
Write-CleanLine "Checksum: $isoChecksum"

# Determine version/build string
if (!$config.preview) {
  if (-not ($iso.title -match 'version')) { 
    throw "Unexpected title format: missing 'version'" 
  }
  $parts = $iso.title -split 'version\s*'
  if ($parts.Count -lt 2) { 
    throw "Unexpected title format, split resulted in less than 2 parts: $($parts -join '|')" 
  }
  $verbuild = $parts[1] -split '[\s\(]' | Select-Object -First 1
} else {
  $verbuild = $config.ringLower.ToUpper()
}

# Create comprehensive metadata
$metadata = [PSCustomObject]@{
  name     = $config.windowsTargetName
  title    = $iso.title
  build    = $iso.build
  version  = $verbuild
  tags     = $buildInfo.tags
  checksum = $isoChecksum
  images   = @($windowsImages)
  uupDump  = @{
    id                 = $iso.id
    apiUrl             = $iso.apiUrl
    downloadUrl        = $iso.downloadUrl
    downloadPackageUrl = $iso.downloadPackageUrl
  }
}

# Save metadata to JSON file
$metadataJsonPath = "$sourceIsoPath.json"
$metadata | ConvertTo-Json -Depth 99 | ForEach-Object { $_ -replace '\\u0026','&' } | Set-Content $metadataJsonPath
Write-CleanLine "Metadata saved to: $metadataJsonPath"

# Save checksum to separate file
$checksumPath = "$sourceIsoPath.sha256.txt"
Set-Content -Encoding ascii -NoNewline -Path $checksumPath -Value $isoChecksum
Write-CleanLine "Checksum saved to: $checksumPath"

# Update build info with final details
$buildInfo | Add-Member -NotePropertyMembers @{ 
  checksum = $isoChecksum
  metadataPath = $metadataJsonPath
  checksumPath = $checksumPath
} -Force
$buildInfo | ConvertTo-Json | Set-Content $buildInfoPath

Write-Host "`nValidation complete!"
Write-Host "ISO: $sourceIsoPath"
Write-Host "Checksum: $isoChecksum"
Write-Host "Images: $($windowsImages.Count)"
Write-Host "Metadata: $metadataJsonPath"
