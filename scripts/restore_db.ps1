<#
.SYNOPSIS
    Restores a Postgres dump (from backup_db.ps1) and its matching media
    archive into the running stack. DESTRUCTIVE -- overwrites the current
    database and media volume contents. Requires -Confirm.

.DESCRIPTION
    Restore-time caveats (see architecture.md Sec 5 "Backup & Restore"):
    - Schema drift: restoring an OLD dump rolls the schema back to that
      point. Migrations that ran after the backup (including data-backfill
      migrations) are lost and must be re-applied with
      `python manage.py migrate` after this script finishes.
    - PII_FIELD_KEY: if the encryption key was rotated (reencrypt_pii)
      between backup and restore, the restored encrypted PII columns are
      undecryptable under the CURRENT key (decrypt_token fails closed).
      Use the key that was active at backup time, or re-run
      `manage.py reencrypt_pii` after restore.

.PARAMETER DumpFile
    Path to a pgdata_*.dump file produced by backup_db.ps1.

.PARAMETER MediaArchive
    Path to the matching media_*.tar.gz file. Optional -- omit to restore
    the database only.

.PARAMETER Confirm
    Required. Without this switch the script refuses to run.
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$DumpFile,
    [string]$MediaArchive,
    [switch]$Confirm
)

if (-not $Confirm) {
    Write-Error "This restore OVERWRITES the current database and media volume. Re-run with -Confirm to proceed."
    exit 1
}

if (-not (Test-Path $DumpFile)) {
    throw "Dump file not found: $DumpFile"
}
if ($MediaArchive -and -not (Test-Path $MediaArchive)) {
    throw "Media archive not found: $MediaArchive"
}

$infraDir = Join-Path $PSScriptRoot ".."
$mediaVolume = "medicalconsultations_media_volume"

Push-Location $infraDir
try {
    $dbId = (docker compose ps -q db)
    if (-not $dbId) {
        throw "The 'db' service is not running -- start the stack first (docker compose up -d db)."
    }

    Write-Host "Restoring Postgres database from $DumpFile ..."
    docker compose cp $DumpFile "db:/tmp/restore.dump"
    if ($LASTEXITCODE -ne 0) {
        throw "docker compose cp (dump) failed with exit code $LASTEXITCODE"
    }
    docker compose exec -T db sh -c 'pg_restore -U "$POSTGRES_USER" -d "$POSTGRES_DB" --clean --if-exists /tmp/restore.dump'
    if ($LASTEXITCODE -ne 0) {
        throw "pg_restore failed with exit code $LASTEXITCODE"
    }
    docker compose exec -T db rm -f /tmp/restore.dump

    if ($MediaArchive) {
        Write-Host "Restoring media volume ($mediaVolume) from $MediaArchive ..."
        $mediaArchiveFull = (Resolve-Path $MediaArchive).Path
        $mediaArchiveDir = Split-Path $mediaArchiveFull -Parent
        $mediaArchiveName = Split-Path $mediaArchiveFull -Leaf
        docker run --rm `
            -v "${mediaVolume}:/data" `
            -v "${mediaArchiveDir}:/backup:ro" `
            alpine sh -c "rm -rf /data/* /data/.[!.]* 2>/dev/null; tar xzf /backup/$mediaArchiveName -C /data"
        if ($LASTEXITCODE -ne 0) {
            throw "media volume restore failed with exit code $LASTEXITCODE"
        }
    } else {
        Write-Warning "No -MediaArchive given -- media volume was NOT restored."
    }

    Write-Host ""
    Write-Host "Restore complete. Remember to:"
    Write-Host "  1. Run 'python manage.py migrate' from backend/ to reapply any migrations newer than this backup."
    Write-Host "  2. If PII_FIELD_KEY was rotated since this backup, run 'manage.py reencrypt_pii' with the backup-era key."
} finally {
    Pop-Location
}
