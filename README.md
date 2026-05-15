# NPWS Certificate Automation

Automates TLS certificate rotation for the **Netwrix Password Secure (NPWS) Application Server** using [Certify The Web](https://certifytheweb.com/) or manual invocation.

When a certificate is renewed, a PowerShell script updates the certificate thumbprint in the Windows Registry and restarts the NPWS services — fully unattended.

## How It Works

1. A new certificate is issued (automatically via Certify The Web, or manually).
2. The script receives the new thumbprint and writes it to the registry at:
   ```
   HKLM\SOFTWARE\MATESO\Password Safe and Repository 8
   ```
   Value: `ServerCertificateFingerprint`
3. The `PsrServer` service is restarted.
4. If `PsrBackupService` was running before the update, it is restarted as well. If it was stopped or not installed, it is left untouched.

## Prerequisites

- Windows Server with **Netwrix Password Secure Application Server** installed
- The executing user/service account needs:
  - Write access to the registry path above
  - Permission to restart the `PsrServer` and `PsrBackupService` services

## Usage

### Automated with Certify The Web

#### 1. Place the Script

Copy `Update-Cert-Thumbprint.ps1` to your scripts directory:

```
C:\SCRIPTS\Update-Cert-Thumbprint.ps1
```

#### 2. Configure the Deployment Task

Add a deployment task to the managed certificate with the following settings:

| Setting                  | Value                                    |
| ------------------------ | ---------------------------------------- |
| Task Type                | Run PowerShell Script                    |
| Task Name                | Update NPWS Server Manager               |
| Trigger                  | Run On Success                           |
| Authentication           | Local (current service user)             |
| Script Path              | `C:\SCRIPTS\Update-Cert-Thumbprint.ps1`  |
| Pass Result as First Arg | Enabled                                  |
| Impersonation LogonType  | Service                                  |
| Script Timeout Mins.     | 3                                        |

#### 3. Test

Use the **Test** button on the deployment task in Certify The Web to verify the script executes correctly. Check that:

- The registry value `ServerCertificateFingerprint` is updated
- The `PsrServer` service restarts without errors
- The `PsrBackupService` restarts only if it was previously running

### Manual Usage

The script can be run directly from an elevated PowerShell prompt by passing the `-Thumbprint` parameter:

```powershell
.\Update-Cert-Thumbprint.ps1 -Thumbprint "AB12CD34EF56AB12CD34EF56AB12CD34EF56AB12"
```

To get the thumbprint of a certificate in the local machine store:

```powershell
Get-ChildItem Cert:\LocalMachine\My | Format-Table Subject, Thumbprint, NotAfter
```

Then copy the thumbprint and pass it to the script:

```powershell
.\Update-Cert-Thumbprint.ps1 -Thumbprint "PASTE_THUMBPRINT_HERE"
```

> **Note:** Manual usage requires an elevated PowerShell session (Run as Administrator) with permissions to write to the registry and restart NPWS services.

## Script Configuration

The script has a configuration section at the top. The defaults match a standard NPWS installation:

```powershell
$RegistryPath      = "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\MATESO\Password Safe and Repository 8"
$RegistryValueName = "ServerCertificateFingerprint"
$PrimaryService    = "PsrServer"
$DependentService  = "PsrBackupService"
```

Adjust these values if your installation differs.

## Service Restart Behavior

| Service            | Behavior                                                                 |
| ------------------ | ------------------------------------------------------------------------ |
| `PsrServer`        | **Required.** Restarted when the thumbprint changes. Script fails if this service is missing. |
| `PsrBackupService` | **Optional.** Restarted when the thumbprint changes, but only if it was running before the update. Skipped silently if not installed or stopped. |

Services are only restarted if the registry value was actually updated. If the thumbprint already matches, the script exits without touching any services.

The restart order ensures `PsrBackupService` (which depends on `PsrServer`) is stopped first, then `PsrServer` is restarted, then `PsrBackupService` is started again.

## Troubleshooting

- **"Certify The Web renewal failed"** — The certificate renewal itself failed. Check the Certify The Web log for details.
- **"No input provided"** — The script was called without a Certify The Web result object or `-Thumbprint` parameter.
- **"Certificate thumbprint is empty"** — Certify The Web passed a result but the thumbprint hash was empty. Ensure *Pass Result as First Arg* is enabled on the deployment task.
- **"Invalid thumbprint format"** — The provided thumbprint is not a valid 40-character SHA-1 hex string. Verify you copied the full thumbprint.
- **"Registry value 'ServerCertificateFingerprint' not found at '...'"** — NPWS Application Server is not installed on this machine (or uses a non-default registry path). The script refuses to create the value to avoid orphan registry entries.
- **"Service 'PsrServer' not found"** — The primary NPWS service is not installed. Verify NPWS Application Server is installed on this machine.
- **Service restart fails** — Verify the executing account has permission to restart NPWS services.
- **Registry update fails** — Verify write access to `HKLM\SOFTWARE\MATESO\Password Safe and Repository 8`.
