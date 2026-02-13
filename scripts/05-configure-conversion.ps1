#!/usr/bin/pwsh
# Script 5: Configure Conversion Settings
# This script modifies the ConvertConfig.ini file and patches aria2 flags

param(
  [string]$configPath = ".\windows-iso-config.json",
  [string]$buildInfoPath = ".\build-info.json",
  [string]$metadataPath = ".\uup-dump-metadata.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Import helper functions
. "$PSScriptRoot\02-helper-functions.ps1"

# Load configuration
if (-not (Test-Path $configPath)) {
  throw "Configuration file not found: $configPath"
}
$config = Get-Content $configPath | ConvertFrom-Json

# Load build info
if (-not (Test-Path $buildInfoPath)) {
  throw "Build info file not found: $buildInfoPath. Please run 04-download-package.ps1 first."
}
$buildInfo = Get-Content $buildInfoPath | ConvertFrom-Json

# Load ISO metadata
if (-not (Test-Path $metadataPath)) {
  throw "ISO metadata file not found: $metadataPath"
}
$iso = Get-Content $metadataPath | ConvertFrom-Json

$buildDirectory = $buildInfo.buildDirectory
$hasVirtualMember = $iso.PSObject.Properties.Name -contains 'virtualEdition' -and $iso.virtualEdition

Write-CleanLine "Configuring conversion settings for $($buildInfo.title)"

# Read and modify ConvertConfig.ini
$convertConfigPath = "$buildDirectory/ConvertConfig.ini"
if (-not (Test-Path $convertConfigPath)) {
  throw "ConvertConfig.ini not found in $buildDirectory"
}

$convertConfig = (Get-Content $convertConfigPath) `
  -replace '^(AutoExit\s*)=.*','$1=1' `
  -replace '^(ResetBase\s*)=.*','$1=1' `
  -replace '^(Cleanup\s*)=.*','$1=1'

$tag = ""

# Apply ESD setting
if ($config.esd) { 
  $convertConfig = $convertConfig -replace '^(wim2esd\s*)=.*', '$1=1'
  $tag += ".E"
  Write-CleanLine "Enabled: ESD format"
}

# Apply drivers setting
if ($config.drivers -and $config.arch -ne "arm64") {
  $convertConfig = $convertConfig -replace '^(AddDrivers\s*)=.*', '$1=1'
  $tag += ".D"
  Write-CleanLine "Enabled: Drivers"
  
  # Check if Drivers folder exists
  if (Test-Path "Drivers") {
    Write-CleanLine "Copying Dell drivers to $buildDirectory directory"
    Copy-Item -Path Drivers -Destination $buildDirectory/Drivers -Recurse
  } else {
    Write-CleanLine "WARNING: Drivers folder not found. Skipping driver copy."
  }
}

# Apply .NET Framework 3.5 setting
if ($config.netfx3) { 
  $convertConfig = $convertConfig -replace '^(NetFx3\s*)=.*', '$1=1'
  $tag += ".N"
  Write-CleanLine "Enabled: .NET Framework 3.5"
}

# Apply virtual edition settings
if ($hasVirtualMember) {
  $convertConfig = $convertConfig `
    -replace '^(StartVirtual\s*)=.*','$1=1' `
    -replace '^(vDeleteSource\s*)=.*','$1=1' `
    -replace '^(vAutoEditions\s*)=.*',"`$1=$($iso.virtualEdition)"
  Write-CleanLine "Enabled: Virtual edition - $($iso.virtualEdition)"
}

# Save modified ConvertConfig.ini
Set-Content -Encoding ascii -Path $convertConfigPath -Value $convertConfig
Write-CleanLine "ConvertConfig.ini updated successfully"

# ------------------------------
# Patch aria2 flags for quieter output
# ------------------------------
function Patch-Aria2-Flags {
  param([string]$CmdPath)
  
  if (-not (Test-Path $CmdPath)) { 
    Write-CleanLine "WARNING: $CmdPath not found. Skipping aria2 patch."
    return 
  }

  $sed = Get-Command sed -ErrorAction SilentlyContinue
  if ($sed) {
    Write-CleanLine "Patching aria2 flags in $CmdPath using sed."
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

# Patch the download script
$downloadScript = Join-Path $buildDirectory 'uup_download_windows.cmd'
Patch-Aria2-Flags -CmdPath $downloadScript
Write-CleanLine "aria2 flags patched for quieter output"

# Update build info with tag
$buildInfo | Add-Member -NotePropertyMembers @{ tags = $tag } -Force
$buildInfo | ConvertTo-Json | Set-Content $buildInfoPath

Write-Host "Configuration complete"
Write-Host "Tags: $tag"
Write-Host "Ready for ISO creation"
