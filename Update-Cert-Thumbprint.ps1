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

# =========================
# VALIDATE ENVIRONMENT
# =========================

# Verify NPWS registry value exists and read current value (do not create it — NPWS must be installed)
try {
    $currentValue = Get-ItemPropertyValue -Path $RegistryPath -Name $RegistryValueName -ErrorAction Stop
} catch {
    throw "Registry value '$RegistryValueName' not found at '$RegistryPath'. Is NPWS Application Server installed on this machine?"
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

Write-Output "Current thumbprint : $currentValue"
Write-Output "New thumbprint     : $Thumbprint"

if ($currentValue -ne $Thumbprint) {
    Set-ItemProperty `
        -Path $RegistryPath `
        -Name $RegistryValueName `
        -Value $Thumbprint `
        -Force

    Write-Output "Registry value '$RegistryValueName' updated."
} else {
    Write-Output "Registry value already matches — no update needed."
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
