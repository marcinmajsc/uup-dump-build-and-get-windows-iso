#!/usr/bin/pwsh
# Script 6: Create Windows ISO
# This script executes the UUP conversion process to create the Windows ISO file

param(
  [string]$buildInfoPath = ".\build-info.json"
)

Set-StrictMode -Version Latest
$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Stop'

# Import helper functions
. .\02-helper-functions.ps1

# Load build info
if (-not (Test-Path $buildInfoPath)) {
  throw "Build info file not found: $buildInfoPath. Please run previous scripts first."
}
$buildInfo = Get-Content $buildInfoPath | ConvertFrom-Json

$buildDirectory = $buildInfo.buildDirectory

if (-not (Test-Path $buildDirectory)) {
  throw "Build directory not found: $buildDirectory"
}

Write-CleanLine "Creating the $($buildInfo.title) ISO file"
Write-CleanLine "Build directory: $buildDirectory"

# Install aria2 (download manager)
Write-CleanLine "Installing aria2..."
choco install aria2 /y *> $null

# Change to build directory
Push-Location $buildDirectory

try {
  # Setup raw log path
  $rawLog = if ($env:RUNNER_TEMP) { 
    Join-Path $env:RUNNER_TEMP "uup_dism_aria2_raw.log" 
  } else { 
    Join-Path $env:TEMP "uup_dism_aria2_raw.log" 
  }

  Write-CleanLine "Starting ISO creation process..."
  Write-CleanLine "Raw log will be saved to: $rawLog"

  # Execute the UUP download script with progress monitoring
  & {
    powershell cmd /c uup_download_windows.cmd 2>&1 |
      Tee-Object -FilePath $rawLog |
      ForEach-Object {
        $raw = [string]$_
        if ([string]::IsNullOrEmpty($raw)) { return }
        
        foreach ($crChunk in ($raw -split "`r")) {
          foreach ($line in ($crChunk -split "`n")) {
            if ($line -eq $null) { continue }
            
            # Process DISM progress buckets
            if (-not (Process-ProgressLine $line)) {
              # Reset progress on key DISM operations
              if ($line -match '^\s*(Mounting image|Saving image|Applying image|Exporting image|Unmounting image|Deployment Image Servicing and Management tool|^=== )') {
                Reset-ProgressSession
              }
              Write-CleanLine $line
            }
          }
        }
      }
  }

  # Check exit code
  if ($LASTEXITCODE) {
    Write-Host "::warning title=Build failed::Dumping last 1500 raw log lines"
    if (Test-Path $rawLog) {
      Get-Content $rawLog -Tail 1500 | Write-Host
    }
    throw "uup_download_windows.cmd failed with exit code $LASTEXITCODE"
  }

  Write-CleanLine "ISO creation completed successfully"

} finally {
  Pop-Location
}

# Find the created ISO file
$isoFiles = Get-ChildItem -Path $buildDirectory -Filter "*.iso"
if ($isoFiles.Count -eq 0) {
  throw "No ISO file found in $buildDirectory"
}

$sourceIsoPath = $isoFiles[0].FullName
Write-CleanLine "Created ISO: $sourceIsoPath"

# Update build info with ISO path
$buildInfo | Add-Member -NotePropertyMembers @{ sourceIsoPath = $sourceIsoPath } -Force
$buildInfo | ConvertTo-Json | Set-Content $buildInfoPath

Write-Host "ISO creation complete!"
Write-Host "ISO file: $sourceIsoPath"
