# =========================================================
# Enterprise OpenSSH Installer / Configurator (Final Stable)
#
# Compatible:
#    Windows Server 2008 R2 (PowerShell 2.0 严格兼容)
#    Windows Server 2012 R2 / 2016 / 2019
# =========================================================

$ErrorActionPreference = "SilentlyContinue"

# =========================
# CONFIG
# =========================

$ZipFile = Join-Path $PSScriptRoot "OpenSSH-Win64.zip"
$InstallPath = "C:\Program Files\OpenSSH"
$ProgramDataSSH = "C:\ProgramData\ssh"

# 证书变量（请确保此处替换为你真实的 id_rsa.pub 内容）
$IdRsaPub = 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQC4C38rbhkJvW0cbkYAnJdxSULA+dBp7kC/vDgunHnvcc6IaMu635SxRGjyG9ZjlDIn9iouFuLrw9OROUsiZh7WU0cAwijrgyehk9oAGgtBlKU19jCyCmNBBJJ2EIDKWvK+z9zwx6vayF79K+4tcqiYFqa9Okl7CrYnJfcXBE++MTbmUGgBh8aDBOvEbQXK77SvXB54lNESFI50v9VKswv2zXJwvRF+Iwrq0yKzNoLEswcmjwIVZQeyxaFR54PPxQBsbjtXosyCk6T6/Vokm/QzBqKHoLSq7g2yxtYTF1h4hmoBEPfeptkkYulQGnVtWhfAFjOgzsfWwxaBoEpSeCe60VASXO5G5u5haaIKHDk/g9s5SOXRxWC3dDpwPVnYFvQq1ga605kHWRZQNcnh7rkRHiIk2gTxdk26Z8H5loy92Ke70gCb+MyEV27YVjqb76FZQC+kQuo0vFuMU0ECuqQ8bV6Nj/EBbNzncaC95y/5M58b5HqASzGanPN9mD+hSdv47c/eqaAR7yscyeL5t4wIZ0jb7JP+T/njf2RSQ/lWUiBOUNPVqwDSVlIZqT7qAErlMBFkke0mTgmInhA75039EwsOgUgbY/KV9EzdNlT30gz+ycNzCIHyuzU37gncEXn2XfG4UkaVKm/gFL616n+WEqAAVZxSWVJDB7HKYD+isQ== root@TEST-INETGATE'

# =========================
# ADMIN CHECK & USER DETERMINE
# =========================

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)

if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "ERROR: Run as Administrator" -ForegroundColor Red
    exit 1
}

$SshUser = "Administrator"
$UserProfiles = Get-WmiObject Win32_UserProfile | Where-Object { $_.LocalPath -like "*\$SshUser" }
$UserHome = if ($UserProfiles) { $UserProfiles.LocalPath } else { "C:\Users\Administrator" }

# =========================
# 系统服务状态严格检查
# =========================

$NeedInstallService = $true
$ServiceCheck = sc.exe query sshd

# 优化：只有当系统服务真实存在且注册成功时，才跳过注册流程
if ($ServiceCheck -match "SERVICE_NAME: sshd") {
    $NeedInstallService = $false
    Write-Host ">>> OpenSSH System Service detected. Updating configuration and certificates only..." -ForegroundColor Cyan
}

# --- 如果服务未注册，执行安装或补齐服务流程 ---
if ($NeedInstallService) {

    # 如果连二进制文件都不就位，则尝试解压
    if (-not (Test-Path "$InstallPath\sshd.exe")) {
        
        if (-not (Test-Path $ZipFile)) {
            Write-Host "ERROR: OpenSSH-Win64.zip not found!" -ForegroundColor Red
            exit 1
        }

        # 清理可能存在的旧残留
        sc.exe stop sshd | Out-Null
        sc.exe delete sshd | Out-Null
        sc.exe stop ssh-agent | Out-Null
        sc.exe delete ssh-agent | Out-Null
        Start-Sleep 2

        if (Test-Path $InstallPath) { cmd /c "rmdir /s /q `"$InstallPath`"" }
        mkdir $InstallPath | Out-Null

        # 尝试自动解压
        Write-Host "Trying to extract package automatically..." -ForegroundColor Yellow
        $shell = New-Object -ComObject Shell.Application
        $zip = $shell.NameSpace($ZipFile)
        $dest = $shell.NameSpace($InstallPath)
        $dest.CopyHere($zip.Items(), 20)

        # 异步等待流释放
        $retry = 0
        while (-not (Test-Path "$InstallPath\OpenSSH-Win64\sshd.exe") -and $retry -lt 15) {
            Start-Sleep 1
            $retry++
        }

        # 目录结构平铺
        if (Test-Path "$InstallPath\OpenSSH-Win64") {
            Move-Item "$InstallPath\OpenSSH-Win64\*" "$InstallPath" -Force
            Remove-Item "$InstallPath\OpenSSH-Win64" -Recurse -Force
        }
    }

    # 人工介入死循环检测：直到物理文件真实在磁盘就位
    while (-not (Test-Path "$InstallPath\sshd.exe")) {
        Write-Host ""
        Write-Host "=====================================================================" -ForegroundColor Red
        Write-Host "?? 警告: 自动解压失败 (Win2008 常见 COM 错误)" -ForegroundColor Yellow
        Write-Host "请保持当前窗口不要关闭，手动将 OpenSSH-Win64.zip 中的所有文件解压到:" -ForegroundColor White
        Write-Host "?? $InstallPath" -ForegroundColor Green
        Write-Host "确保 $InstallPath 目录下直接包含 sshd.exe，不要多嵌套一层文件夹！" -ForegroundColor White
        Write-Host "=====================================================================" -ForegroundColor Red
        Write-Host "请在手动解压完成后，按 [任意键] 继续后续安装..." -ForegroundColor Cyan
        
        # 暂停并等待键盘输入
        $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") | Out-Null
        
        if (-not (Test-Path "$InstallPath\sshd.exe")) {
            Write-Host "? 依然没有在 $InstallPath 中检测到 sshd.exe，请检查路径后再试。" -ForegroundColor Red
        }
    }

    Write-Host "?? 文件已就位，正在向系统注册 OpenSSH 服务..." -ForegroundColor Green

    # 设置系统环境变量 PATH
    $oldPath = [Environment]::GetEnvironmentVariable("Path","Machine")
    if ($oldPath -notlike "*OpenSSH*") {
        [Environment]::SetEnvironmentVariable("Path", $oldPath + ";" + $InstallPath, "Machine")
    }
    $env:PATH += ";" + $InstallPath

    # ?? 修复方案：此处修改为 Windows Server 2008 R2 严格兼容的纯单/双引号及等号留空语法
    sc.exe create sshd binPath= "C:\Program Files\OpenSSH\sshd.exe" start= auto DisplayName= "OpenSSH SSH Server"
    sc.exe create ssh-agent binPath= "C:\Program Files\OpenSSH\ssh-agent.exe" start= demand DisplayName= "OpenSSH Auth Agent"
}

# =========================================================
# CONFIGURATION & CERTIFICATES AREA (配置收尾区)
# =========================================================

if (-not (Test-Path $ProgramDataSSH)) { mkdir $ProgramDataSSH | Out-Null }

# 1. 写入/更新 Administrator 证书
$sshDir = Join-Path $UserHome ".ssh"
$authKeys = Join-Path $sshDir "authorized_keys"

if (-not (Test-Path $sshDir)) { mkdir $sshDir | Out-Null }
if (-not (Test-Path $authKeys)) { New-Item -Path $authKeys -ItemType File | Out-Null }

$content = Get-Content $authKeys
$exists = $false
foreach ($line in $content) {
    if ($line.Trim() -eq $IdRsaPub.Trim()) { $exists = $true }
}
if (-not $exists) {
    Add-Content -Path $authKeys -Value $IdRsaPub
    Write-Host ">>> Public key appended to $authKeys" -ForegroundColor Green
} else {
    Write-Host ">>> Public key already exists. Checked." -ForegroundColor Yellow
}

# 严格精简权限 (Windows 2008 安全兼容写法)
cmd /c "icacls `"$sshDir`" /inheritance:r" | Out-Null
cmd /c "icacls `"$sshDir`" /grant:r `"$SshUser`":F" | Out-Null
cmd /c "icacls `"$sshDir`" /grant:r SYSTEM:F" | Out-Null

cmd /c "icacls `"$authKeys`" /inheritance:r" | Out-Null
cmd /c "icacls `"$authKeys`" /grant:r `"$SshUser`":F" | Out-Null
cmd /c "icacls `"$authKeys`" /grant:r SYSTEM:F" | Out-Null

# 2. 覆盖写入 sshd_config（密码+证书双模登录）
$configFile = "$ProgramDataSSH\sshd_config"
$config = @()
$config += "Port 22"
$config += "Protocol 2"
$config += "ListenAddress 0.0.0.0"
$config += "HostKey C:/ProgramData/ssh/ssh_host_rsa_key"
$config += "PubkeyAuthentication yes"
$config += "PasswordAuthentication yes"
$config += "PermitEmptyPasswords no"
$config += "AuthorizedKeysFile .ssh/authorized_keys"
$config += "HostKeyAlgorithms ssh-rsa"
$config += "PubkeyAcceptedAlgorithms +ssh-rsa"
$config += "KexAlgorithms diffie-hellman-group14-sha1"
$config += "Ciphers aes128-ctr,aes192-ctr,aes256-ctr"
$config += "Subsystem sftp sftp-server.exe"

Set-Content -Path $configFile -Value $config -Encoding ASCII
Write-Host ">>> sshd_config updated." -ForegroundColor Green

# 3. 设置默认 Shell 为 PowerShell
$RegistryPath = "HKLM:\SOFTWARE\OpenSSH"
if (-not (Test-Path $RegistryPath)) { New-Item -Path $RegistryPath -Force | Out-Null }
New-ItemProperty -Path $RegistryPath -Name "DefaultShell" -Value "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -PropertyType String -Force | Out-Null

# 4. 放行防火墙
netsh advfirewall firewall add rule name="OpenSSH-22" dir=in action=allow protocol=TCP localport=22 | Out-Null

# =========================
# RESTART SERVICES
# =========================

Write-Host "Restarting OpenSSH services..."
sc.exe stop sshd | Out-Null
Start-Sleep 1
sc.exe start ssh-agent | Out-Null
sc.exe start sshd | Out-Null
Start-Sleep 2

Write-Host "`n===================================="
Write-Host "PROCESS COMPLETE!"
Write-Host "===================================="
sc.exe query sshd
