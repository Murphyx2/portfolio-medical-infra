<#
.SYNOPSIS
    Rebuilds and force-recreates the backend and frontend Docker containers
    (mc_backend / mc_frontend) so locally edited source is reflected live.
    Leaves db/cache untouched.
#>

$infraDir = Join-Path $PSScriptRoot ".."

Push-Location $infraDir
try {
    docker compose up -d --force-recreate --build backend frontend
    if ($LASTEXITCODE -ne 0) {
        throw "docker compose up failed with exit code $LASTEXITCODE"
    }
    docker compose ps
} finally {
    Pop-Location
}
