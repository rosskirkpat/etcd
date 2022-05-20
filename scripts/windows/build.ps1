#Requires -Version 5.0
$ErrorActionPreference = 'Stop'

Import-Module -WarningAction Ignore -Name "$PSScriptRoot\utils.psm1"


function Build {
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
    $GO_BFLAGS  = ''
    $GO_GCFLAGS = '-dwarf=false' # Avoid generating DWARF symbols in the first hand  
    $env:GO_LDFLAGS = '-s -w -extldflags "-static"' # Omit debug symbols & DWARF symbol table & do not link with shared libs

    if ($env:DEBUG) {
        $GO_BFLAGS  = '-v'     # Verbose compilation mode (switch to -x for debug mode)
        $GO_GCFLAGS = '-N -l'  # Disable optimization + Disable inlining func 
        $env:GO_LDFLAGS = ''   # Override GO_LDFLAGS to keep debug symbols & dwarf symbol table
        Write-LogInfo ('Debug flag passed, changing gcflags to {0}, ldflags to {1}' -f $GO_GCFLAGS, $env:GO_LDFLAGS )
    }
    $VERSION_SYMBOL="{0}/{1}/api/v3/version.GitSHA" -f $env:ORG_PATH, $env:GIT_REPO
    $GO_LDFLAGS = ("{0} -X '{1}={2}'" -f $env:GO_LDFLAGS, $VERSION_SYMBOL, $Commit)
    if ($env:DEBUG) {
        Write-LogInfo "[DEBUG] Running command: go build $GO_BFLAGS -o $Output -gcflags=all='$GO_GCFLAGS' -ldflags='$GO_LDFLAGS'"
    }

    Push-Location $BuildPath
    go build $GO_BFLAGS -o $Output -gcflags=all="$GO_GCFLAGS" -ldflags="$GO_LDFLAGS" .
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

Build -BuildPath "$SRC_PATH/server" -Commit $env:COMMIT -Output "..\bin\etcd.exe" # -Version $env:VERSION
Build -BuildPath "$SRC_PATH/etcdctl" -Commit $env:COMMIT -Output "..\bin\etcdctl.exe" # -Version $env:VERSION
Write-LogInfo "Builds Complete"

Pop-Location
