#Requires -Version 5.0
# param (
#     [Parameter(Mandatory = $true)]
#     [String]
#     [ValidateNotNullOrEmpty()]
#     $Version
# )
$ErrorActionPreference = 'Stop'

Import-Module -WarningAction Ignore -Name "$PSScriptRoot\utils.psm1"


function Build {
    # [CmdletBinding()]
    param (
        # [Parameter()]
        # [String]
        # $Version,
        [parameter()]
        [string]
        $BuildPath,
        [parameter()]
        [string]
        $Commit,
        [parameter()]
        [string]
        $Output        
    )
    $Env:GO_LDFLAGS = '-s -w -gcflags=all=-dwarf=false -extldflags "-static"'

    if ($env:DEBUG) {
        $Env:GO_LDFLAGS = '-v -gcflags=all=-N -l'
        Write-LogInfo ('Debug flag passed, changing ldflags to {0}' -f $linkFlags)
        # go install github.com/go-delve/delve/cmd/dlv@latest
    }

    $GO_LDFLAGS = ("'{0} -X {1}/{2}/api/v3/version.GitSHA={3}'" -f $Env:GO_LDFLAGS, $env:GIT_ORG, $env:GIT_REPO, $Commit)
    if ($env:DEBUG){
        Write-LogInfo "[DEBUG] Running command: go build -o $Output -ldflags $linkerFlags"
    }

    Push-Location $BuildPath
    go build -o $Output -ldflags $GO_LDFLAGS .
    Pop-Location
    if (-Not $?) {
        Write-LogFatal "go build for $BuildPath failed!"
    }
}

trap {
    Write-Host -NoNewline -ForegroundColor Red "[ERROR]: "
    Write-Host -ForegroundColor Red "$_"

    Pop-Location
    exit 1
}

Invoke-Script -File "$PSScriptRoot\version.ps1"

$SRC_PATH = (Resolve-Path "$PSScriptRoot\..\..").Path
Push-Location $SRC_PATH
if ($env:DEBUG) {
    Write-LogInfo "[DEBUG] Build Path: $SRC_PATH"
}

Remove-Item -Path "$SRC_PATH/bin/*.exe" -Force -ErrorAction Ignore
$null = New-Item -Type Directory -Path bin -ErrorAction Ignore
$env:GOARCH = $env:ARCH
$env:GOOS = 'windows'
$env:CGO_ENABLED = 0

Write-LogInfo "Starting Builds for etcd and etcdctl"
Build -BuildPath "$SRC_PATH/server" -Commit $env:COMMIT -Output "..\bin\etcd.exe" # -Version $env:VERSION
Build -BuildPath "$SRC_PATH/etcdctl" -Commit $env:COMMIT -Output "..\bin\etcdctl.exe" # -Version $env:VERSION
Write-LogInfo "Builds Complete"

Pop-Location
