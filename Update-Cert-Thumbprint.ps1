param(
    $result,              # Certify The Web passes the renewal result object
    [string]$Thumbprint   # Manual mode: pass a thumbprint directly
)

# =========================
# CONFIGURATION
# =========================

$RegistryPath = "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\MATESO\Password Safe and Repository 8"
$RegistryValueName = "ServerCertificateFingerprint"

# Primary service (required, always restarted)
$PrimaryService = "PsrServer"

# Dependent service (optional, only restarted if it was running before)
$DependentService = "PsrBackupService"

# =========================
# RESOLVE THUMBPRINT
# =========================

if (-not [string]::IsNullOrWhiteSpace($Thumbprint)) {
    # Manual mode
    Write-Output "Manual mode: using provided thumbprint."
} elseif ($result) {
    # Certify The Web mode
    if (-not $result.IsSuccess) {
        throw "Certify The Web renewal failed: $($result.Message)"
    }
    $Thumbprint = $result.ManagedItem.CertificateThumbprintHash
} else {
    throw "No input provided. Pass either a Certify The Web result object or a -Thumbprint parameter."
}

if ([string]::IsNullOrWhiteSpace($Thumbprint)) {
    throw "Certificate thumbprint is empty."
}

# Validate thumbprint format (SHA-1: 40 hex characters)
if ($Thumbprint -notmatch '^[0-9a-fA-F]{40}$') {
    throw "Invalid thumbprint format: '$Thumbprint'. Expected 40 hexadecimal characters (SHA-1)."
}

Write-Output "New certificate thumbprint: $Thumbprint"

# =========================
# VALIDATE ENVIRONMENT
# =========================

# Verify NPWS registry key exists (do not create it — NPWS must be installed)
if (-not (Test-Path $RegistryPath)) {
    throw "Registry path '$RegistryPath' does not exist. Is NPWS Application Server installed on this machine?"
}

# Verify primary service exists
$primarySvc = Get-Service -Name $PrimaryService -ErrorAction SilentlyContinue
if (-not $primarySvc) {
    throw "Service '$PrimaryService' not found. Is NPWS Application Server installed on this machine?"
}

# Check if the dependent service exists and is currently running
$restartDependentService = $false
$dependentSvc = Get-Service -Name $DependentService -ErrorAction SilentlyContinue
if ($dependentSvc) {
    if ($dependentSvc.Status -eq 'Running') {
        $restartDependentService = $true
        Write-Output "Dependent service '$DependentService' is running and will be restarted."
    } else {
        Write-Output "Dependent service '$DependentService' is not running (status: $($dependentSvc.Status)). It will not be restarted."
    }
} else {
    Write-Output "Dependent service '$DependentService' is not installed. Skipping."
}

# =========================
# UPDATE REGISTRY
# =========================

$currentValue = $null
try {
    $currentValue = (Get-ItemProperty -Path $RegistryPath -ErrorAction Stop).$RegistryValueName
} catch {
    Write-Output "Registry value does not exist yet; it will be created."
}

if ($currentValue -ne $Thumbprint) {
    Set-ItemProperty `
        -Path $RegistryPath `
        -Name $RegistryValueName `
        -Value $Thumbprint `
        -Force

    Write-Output "Updated registry value '$RegistryValueName' with new thumbprint."
} else {
    Write-Output "Registry value already matches the current certificate."
}

# =========================
# RESTART SERVICES
# =========================

# Stop dependent service first (if applicable) to respect dependency order
if ($restartDependentService) {
    Write-Output "Stopping dependent service: $DependentService"
    Stop-Service -Name $DependentService -Force -ErrorAction Stop
}

Write-Output "Restarting primary service: $PrimaryService"
Restart-Service -Name $PrimaryService -Force -ErrorAction Stop

if ($restartDependentService) {
    Write-Output "Starting dependent service: $DependentService"
    Start-Service -Name $DependentService -ErrorAction Stop
}

Write-Output "Deployment task completed successfully."
