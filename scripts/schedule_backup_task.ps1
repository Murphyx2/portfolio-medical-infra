<#
.SYNOPSIS
    Registers a daily Windows Task Scheduler entry that runs backup_db.ps1
    unattended, closing the "backups are manual" gap noted in
    infra/docs/backups.md and infra/docs/manuales/manual-respaldo.md.

.DESCRIPTION
    Wraps Register-ScheduledTask so wiring up a scheduled backup on the
    actual deployment server is a single command instead of a multi-step
    manual walkthrough in Task Scheduler's GUI. Does not touch, start, or
    otherwise depend on Docker itself -- it only registers the task; the
    task's first real run (at the next scheduled time, or via -RunNow)
    exercises backup_db.ps1 exactly as a person running it by hand would.

    Idempotent: re-running with the same -TaskName replaces the existing
    task definition (Register-ScheduledTask -Force) rather than erroring
    or duplicating it.

.PARAMETER TaskName
    Name shown in Task Scheduler. Default "MedicalConsultations DB Backup".

.PARAMETER At
    Daily run time, 24h "HH:mm". Default "02:00" (low-traffic hours).

.PARAMETER RetentionDays
    Passed straight through to backup_db.ps1 -RetentionDays. Default 14.

.PARAMETER RunNow
    Also trigger one immediate run after registering, so the task's
    first real execution (and any permission/path problem) is caught
    right away instead of at 2 AM.

.EXAMPLE
    # Run as Administrator, from infra/scripts/:
    .\schedule_backup_task.ps1
    .\schedule_backup_task.ps1 -At "03:30" -RetentionDays 30 -RunNow
#>
param(
    [string]$TaskName = "MedicalConsultations DB Backup",
    [string]$At = "02:00",
    [int]$RetentionDays = 14,
    [switch]$RunNow
)

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "Registering a scheduled task requires an elevated (Administrator) PowerShell session."
}

$backupScript = Join-Path $PSScriptRoot "backup_db.ps1"
if (-not (Test-Path $backupScript)) {
    throw "backup_db.ps1 not found next to this script at $backupScript"
}

$action = New-ScheduledTaskAction `
    -Execute "pwsh.exe" `
    -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$backupScript`" -RetentionDays $RetentionDays" `
    -WorkingDirectory $PSScriptRoot

$trigger = New-ScheduledTaskTrigger -Daily -At $At

$settings = New-ScheduledTaskSettingsSet `
    -StartWhenAvailable `
    -DontStopOnIdleEnd `
    -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 10)

# Runs as SYSTEM so it works with nobody logged in -- matches the
# "runs as a service, no interactive session required" pattern already used
# for the self-hosted CI runner (see cicd-deployment-pipeline.md Sec.4).
Register-ScheduledTask `
    -TaskName $TaskName `
    -Action $action `
    -Trigger $trigger `
    -Settings $settings `
    -User "SYSTEM" `
    -RunLevel Highest `
    -Force | Out-Null

Write-Host "Registered scheduled task '$TaskName': daily at $At, retention $RetentionDays day(s)."
Write-Host "Verify with: Get-ScheduledTask -TaskName `"$TaskName`" | Get-ScheduledTaskInfo"

if ($RunNow) {
    Write-Host "Running the task now to verify it works end-to-end..."
    Start-ScheduledTask -TaskName $TaskName
    Start-Sleep -Seconds 3
    Get-ScheduledTaskInfo -TaskName $TaskName | Format-List TaskName, LastRunTime, LastTaskResult
}
