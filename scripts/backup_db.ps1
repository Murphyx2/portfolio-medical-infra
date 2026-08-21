<#
.SYNOPSIS
    Backs up the Postgres database (pgdata volume) and the clinical-image
    media volume into timestamped archives under infra/backups/, and prunes
    backups older than -RetentionDays.

.DESCRIPTION
    - Postgres: `pg_dump -Fc` (custom format) run inside the running `db`
      container, using the POSTGRES_USER/POSTGRES_DB env vars already present
      in that container (set from .env at `docker compose up` time) -- this
      script does not need to read .env itself.
    - Media: tars the `medicalconsultations_media_volume` named volume via a
      throwaway alpine container.
    - Output is self-contained: pg_dump -Fc embeds the full schema, so a
      backup is never invalidated by later migrations. Restoring an OLD
      backup rolls the schema back to that point, though -- see
      restore_db.ps1 and architecture.md Sec 5 "Backup & Restore" for the
      migration/PII_FIELD_KEY caveats that apply after a restore.

.PARAMETER RetentionDays
    Delete backup files older than this many days. Default 14.

.PARAMETER BackupDir
    Directory to write backups into. Default infra/backups (gitignored --
    these are decrypted-at-rest PHI and must never be committed).
#>
param(
    [int]$RetentionDays = 14,
    [string]$BackupDir = (Join-Path $PSScriptRoot "..\backups")
)

$infraDir = Join-Path $PSScriptRoot ".."
$mediaVolume = "medicalconsultations_media_volume"

Push-Location $infraDir
try {
    if (-not (Test-Path $BackupDir)) {
        New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
    }
    $BackupDir = (Resolve-Path $BackupDir).Path

    $timestamp = Get-Date -Format "yyyy-MM-ddTHHmmss"
    $dumpFile = Join-Path $BackupDir "pgdata_$timestamp.dump"
    $mediaFile = Join-Path $BackupDir "media_$timestamp.tar.gz"

    Write-Host "Backing up Postgres database to $dumpFile ..."
    $dbId = (docker compose ps -q db)
    if (-not $dbId) {
        throw "The 'db' service is not running -- start the stack first (docker compose up -d db)."
    }
    # Dump to a file INSIDE the container, then `compose cp` it out -- this is
    # binary-safe (avoids PowerShell's text pipeline mangling pg_dump's custom
    # -Fc binary output, which a plain stdout redirect would risk on Windows).
    docker compose exec -T db sh -c 'rm -f /tmp/backup.dump; pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Fc -f /tmp/backup.dump'
    if ($LASTEXITCODE -ne 0) {
        throw "pg_dump failed with exit code $LASTEXITCODE"
    }
    docker compose cp "db:/tmp/backup.dump" $dumpFile
    if ($LASTEXITCODE -ne 0) {
        throw "docker compose cp failed with exit code $LASTEXITCODE"
    }
    docker compose exec -T db rm -f /tmp/backup.dump
    if ((Get-Item $dumpFile).Length -eq 0) {
        throw "pg_dump produced an empty file -- aborting (check container logs)."
    }

    Write-Host "Backing up media volume ($mediaVolume) to $mediaFile ..."
    $volumeExists = docker volume ls -q --filter "name=^$mediaVolume$"
    if (-not $volumeExists) {
        Write-Warning "Volume '$mediaVolume' not found -- skipping media backup (nothing uploaded yet?)."
    } else {
        docker run --rm `
            -v "${mediaVolume}:/data:ro" `
            -v "${BackupDir}:/backup" `
            alpine sh -c "tar czf /backup/media_$timestamp.tar.gz -C /data ."
        if ($LASTEXITCODE -ne 0) {
            throw "media volume tar failed with exit code $LASTEXITCODE"
        }
    }

    Write-Host "Pruning backups older than $RetentionDays day(s) in $BackupDir ..."
    $cutoff = (Get-Date).AddDays(-$RetentionDays)
    Get-ChildItem -Path $BackupDir -File | Where-Object {
        $_.Name -match '^(pgdata|media)_' -and $_.LastWriteTime -lt $cutoff
    } | ForEach-Object {
        Write-Host "  removing old backup: $($_.Name)"
        Remove-Item $_.FullName -Force
    }

    Write-Host "Backup complete: $dumpFile"
} finally {
    Pop-Location
}
