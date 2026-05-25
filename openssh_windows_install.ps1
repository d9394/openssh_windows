# =========================================================
# Enterprise OpenSSH Installer (PASSWORD AUTHENTICATION)
#
# Compatible:
#    Windows Server 2008 R2
#    Windows Server 2012 R2
#    Windows Server 2016
#    Windows Server 2019
#
# Package Required:
#    OpenSSH-Win64.zip
# =========================================================

$ErrorActionPreference = "SilentlyContinue"

# =========================
# CONFIG
# =========================

$ZipFile = Join-Path $PSScriptRoot "OpenSSH-Win64.zip"

$InstallPath = "C:\Program Files\OpenSSH"

$ProgramDataSSH = "C:\ProgramData\ssh"

$SshUser = $env:USERNAME

# =========================
# ADMIN CHECK
# =========================

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)

if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "ERROR: Run as Administrator" -ForegroundColor Red
    exit 1
}

# =========================
# CHECK FILE
# =========================

if (-not (Test-Path $ZipFile)) {
    Write-Host "ERROR: OpenSSH-Win64.zip not found"
    exit 1
}

# =========================
# STOP & REMOVE OLD SERVICE
# =========================

sc.exe stop sshd | Out-Null
sc.exe delete sshd | Out-Null

sc.exe stop ssh-agent | Out-Null
sc.exe delete ssh-agent | Out-Null

Start-Sleep 2

# =========================
# REMOVE OLD INSTALL
# =========================

if (Test-Path $InstallPath) {
    cmd /c "rmdir /s /q `"$InstallPath`""
}

mkdir $InstallPath | Out-Null

# =========================
# EXTRACT ZIP (Win2008 compatible COM method)
# =========================

$shell = New-Object -ComObject Shell.Application
$zip = $shell.NameSpace($ZipFile)
$dest = $shell.NameSpace($InstallPath)

$dest.CopyHere($zip.Items(), 16)

# ?? 已修复：此处变量已从 $InstallRoot 改为 $InstallPath
Move-Item "$InstallPath\OpenSSH-Win64\*" "$InstallPath" -Force
Remove-Item "$InstallPath\OpenSSH-Win64" -Recurse -Force

Start-Sleep 8

if (-not (Test-Path "$InstallPath\sshd.exe")) {
    Write-Host "ERROR: extraction failed"
    exit 1
}

# =========================
# SET PATH
# =========================

$oldPath = [Environment]::GetEnvironmentVariable("Path","Machine")

if ($oldPath -notlike "*OpenSSH*") {
    [Environment]::SetEnvironmentVariable(
        "Path",
        $oldPath + ";" + $InstallPath,
        "Machine"
    )
}

$env:PATH += ";" + $InstallPath

# =========================
# CREATE SERVICE (manual, Win2008 safe)
# =========================

sc.exe create sshd binPath= "`"$InstallPath\sshd.exe`"" start= auto DisplayName= "OpenSSH SSH Server"
sc.exe create ssh-agent binPath= "`"$InstallPath\ssh-agent.exe`"" start= demand DisplayName= "OpenSSH Auth Agent"

# =========================
# PROGRAMDATA SSH
# =========================

if (-not (Test-Path $ProgramDataSSH)) {
    mkdir $ProgramDataSSH | Out-Null
}

# =========================
# sshd_config (密码认证配置)
# =========================

$configFile = "$ProgramDataSSH\sshd_config"

$config = @()

$config += "Port 22"
$config += "Protocol 2"
$config += "ListenAddress 0.0.0.0"

# 自动生成并使用主机密钥（如果是第一次运行，sshd 启动时会自动生成这些 key）
$config += "HostKey C:/ProgramData/ssh/ssh_host_rsa_key"

# ?? 核心修改：允许密码登录，禁用密钥登录
$config += "PubkeyAuthentication no"
$config += "PasswordAuthentication yes"
$config += "PermitEmptyPasswords no"

# Win2008 compatibility crypto
$config += "HostKeyAlgorithms ssh-rsa"
$config += "KexAlgorithms diffie-hellman-group14-sha1"
$config += "Ciphers aes128-ctr,aes192-ctr,aes256-ctr"

$config += "Subsystem sftp sftp-server.exe"

Set-Content -Path $configFile -Value $config -Encoding ASCII

# =========================
# FIREWALL (Win2008 compatible)
# =========================

netsh advfirewall firewall add rule `
    name="OpenSSH-22" `
    dir=in `
    action=allow `
    protocol=TCP `
    localport=22 | Out-Null

# =========================
# START SERVICE
# =========================

sc.exe start ssh-agent | Out-Null
sc.exe start sshd | Out-Null

Start-Sleep 3

# =========================
# STATUS
# =========================

Write-Host ""
Write-Host "===================================="
Write-Host "OPENSSH PASSWORD-AUTH DEPLOY COMPLETE"
Write-Host "===================================="
Write-Host ""

sc.exe query sshd

Write-Host ""
netstat -ano | findstr ":22"

Write-Host ""
Write-Host "USER:"
Write-Host $SshUser

Write-Host ""
Write-Host "LOGIN:"
Write-Host "ssh $SshUser@IP (Then enter your Windows Password)"
Write-Host ""

# =========================
# SET DEFAULT SHELL TO POWERSHELL
# =========================
$RegistryPath = "HKLM:\SOFTWARE\OpenSSH"

# 如果注册表项不存在则创建
if (-not (Test-Path $RegistryPath)) {
    New-Item -Path $RegistryPath -Force | Out-Null
}

# 设置默认 Shell 为 PowerShell
New-ItemProperty -Path $RegistryPath -Name "DefaultShell" -Value "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -PropertyType String -Force | Out-Null
