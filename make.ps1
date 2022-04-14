<#
.SYNOPSIS 
    Native etcd binary builds for Windows
.DESCRIPTION 
    Run the script to build etcd binaries on a Windows machine
.NOTES
    Environment variables:
    - VERSION (Set the version of etcd)

    Advanced Environment Variables
    - DEBUG (Sets specific Go ldflags for debugging purposes)
    - GIT_VERSION (Local version of Git to install | default: 2.35.2)
    - GO_VERSION (Local version of Go to install | default: 1.17.8)
    - GIT_ORG (default: etcd-io}
    - GIT_REPO (default: etcd}

    
.EXAMPLE
    make.ps1 -Version dev
    make.ps1 -Version dev -Debug
    make.ps1 -Version dev -Script build
    $env:GIT_ORG="YOUR-GITHUB-ORG"; $env:GIT_REPO="YOUR-GITHUB-REPO"; make.ps1 -Version $(git tag -l --contains HEAD | Select-Object -First 1)
#>

# Make sure these params matches the CmdletBinding below
param (
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [String]
    $Version,
    [Switch]
    $GoDebug,
    [Parameter()]
    [ValidateScript({ 
        if (Test-Path $PSScriptRoot\scripts\windows\$_.ps1) {
            $true
        } else {
            throw "$_ is not a valid script name in $(echo $PSScriptRoot\scripts\windows)"
        }
    })]
    [String]
    $Script
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module -WarningAction Ignore -Name "$PSScriptRoot\scripts\windows\utils.psm1"


function Invoke-EtcdCI() {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $Version,
        [Switch]
        $GoDebug,
        [Parameter()]
        [ValidateScript({ 
            if (Test-Path $PSScriptRoot\scripts\windows\$_.ps1) {
                $true
            } else {
                throw "$_ is not a valid script name in $(echo $PSScriptRoot\scripts\windows)"
            }
        })]
        [String]
        $Script
    )
}

function Get-Args() {
    if ($Version) {
        $env:VERSION = $Version
    }

    if ($GoDebug.IsPresent) {
        $env:DEBUG = "true"
    }

    # Default invocation is full CI
    $env:SCRIPT_PATH = "ci"
    if ($Script) {
        $env:SCRIPT_PATH = ("{0}\scripts\windows\{1}.ps1" -f $PSScriptRoot, $Script)
    }
}

function Set-Environment() {
    $GIT_VERSION = $env:GIT_VERSION
    if (-not $GIT_VERSION) {        
        $env:GIT_VERSION = "2.35.2"
    }

    $GOLANG_VERSION = $env:GOLANG_VERSION
    if (-not $GOLANG_VERSION) {        
        $GOLANG_VERSION = "1.17.8"
    }

    $VERSION = $env:VERSION
    if (-not $VERSION) {
        $VERSION = $(git rev-parse --short HEAD)
    }

    $GIT_ORG = $env:GIT_ORG
    if (-not $GIT_ORG) {
        $GIT_ORG = "etcd-io"
    }

    $GIT_REPO = $env:GIT_REPO
    if (-not $GIT_REPO) {
        $GIT_REPO = "etcd"
    }
}

function Set-Path() {
    # ideally, gopath would be C:\go to match Linux a bit closer
    # but C:\go is the recommended install path for Go itself on Windows, so we use C:\gopath
    $env:PATH += ";C:\git\cmd;C:\git\mingw64\bin;C:\git\usr\bin;C:\gopath\bin;C:\go\bin"
    $environment = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
    $environment = $environment.Insert($environment.Length, ";C:\git\cmd;C:\git\mingw64\bin;C:\git\usr\bin;C:\gopath\bin;C:\go\bin")
    [System.Environment]::SetEnvironmentVariable("Path", $environment, "Machine")
}
    
function Test-Architecture() {
    if ($env:PROCESSOR_ARCHITECTURE -ne "AMD64" -or $env:PROCESSOR_ARCHITECTURE -ne "ARM64") {
        Log-Fatal "Unsupported architecture $( $env:PROCESSOR_ARCHITECTURE )"
    }
}

function Install-Git() {
    # install git
    if ((Get-Command "git" -ErrorAction SilentlyContinue) -eq $null) {
        $GIT_TAG = "v$env:GIT_VERSION.windows.1"
        $GIT_DOWNLOAD_URL = "https://github.com/git-for-windows/git/releases/download/$GIT_TAG/MinGit-$env:GIT_VERSION-64-bit.zip"
        Push-Location C:\
        Write-Host ('Downloading git ...')
        Expand-Archive -Force -Path c:\git.zip -DestinationPath c:\git\.
        Remove-Item -Force -Recurse -Path c:\git.zip
        Pop-Location
    } else {
        Write-Host ('{0} found in PATH, skipping install ...' -f $(git version))
    }
}
    
function Install-Go() {
    # install go
    if ((Get-Command "go" -ErrorAction SilentlyContinue) -eq $null) {
        Write-Host ("go not found in PATH, installing go{0}" -f $env:GOLANG_VERSION)
        Push-Location C:\
        Invoke-WebRequest -Uri ('https://golang.org/dl/go{0}.windows-amd64.zip' -f $env:GOLANG_VERSION) -OutFile 'go.zip'
        Expand-Archive go.zip -DestinationPath C:\
        Remove-Item go.zip -Force
        Pop-Location
        Write-Host ('Installed go{0}' -f $env:GOLANG_VERSION)
    } else {
        Write-Host ('{0} found in PATH, skipping install ...' -f $(go version))
    }
}

function Install-Ginkgo() {
    # install ginkgo
    if ((Get-Command "ginkgo" -ErrorAction SilentlyContinue) -eq $null) {
        Push-Location c:\
        go get -u github.com/onsi/ginkgo/ginkgo
        go get -u github.com/onsi/gomega/...
        Pop-Location
    } else {
        Write-Host ('{0} found in PATH, skipping install ...' -f $(ginkgo version))
    }
}

function Initialize-Environment() {
    Write-Host 'Preparing local etcd build environment'
    Install-Git
    Install-Go
    Install-Ginkgo
}

function Invoke-EtcdIntegrationTests() {
    Write-Host "Running Integration Tests"
    Invoke-Script -File scripts\windows\build.ps1
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }
    Invoke-Script -File scripts\windows\integration.ps1
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }
    exit 0
}

function Invoke-AllEtcd() {
    Write-Host "Running CI and Integration Tests"
    Invoke-Script -File scripts\windows\ci.ps1
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }
    exit 0
}

function Invoke-EtcdBuild() {
    Test-Architecture
    Get-Args
    Set-Environment
    Set-Path
    Initialize-Environment

    # TODO: Integration Tests
    if ($env:SCRIPT_PATH -eq "integration") {
        Invoke-EtcdIntegrationTests
    }

    # TODO: Additional Tests
    if ($env:SCRIPT_PATH -eq "all") {
        Invoke-AllEtcd
    }

    if (Test-Path $SCRIPT_PATH) {
        Import-Module -WarningAction Ignore -Name "$PSScriptRoot\scripts\windows\utils.psm1"
        Write-Host ("Running scripts\windows\{0}.ps1" -f $env:SCRIPT_PATH)
        Invoke-Script -File $SCRIPT_PATH
        if ($LASTEXITCODE -ne 0) {
            exit $LASTEXITCODE
        }
        exit 0
    }
}

Invoke-EtcdBuild

Invoke-EtcdCI