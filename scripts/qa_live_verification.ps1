# QA Live Verification - MedicalConsultations (pagination, NSS, RBAC, masking, JWT, throttle)
# Independent verification against the LIVE stack. Does NOT modify application code.
$ErrorActionPreference = "Stop"
$base = "http://localhost:8000/api"
$results = @()

# ensure the login-throttle window (10/min) is fully reset before role logins
Write-Output "  waiting 65s for login-throttle window reset before role logins..."
Start-Sleep -Seconds 65

function Call($method, $url, $body, $token, $session) {
    $headers = @{ "Content-Type" = "application/json" }
    if ($token) { $headers["Authorization"] = "Bearer $token" }
    try {
        $params = @{ Uri = $url; Method = $method; Headers = $headers; UseBasicParsing = $true }
        if ($body) { $params["Body"] = $body }
        if ($session) { $params["WebSession"] = $session }
        $resp = Invoke-WebRequest @params
        $data = $null
        try { $data = $resp.Content | ConvertFrom-Json } catch { $data = $resp.Content }
        return @{ ok = $true; status = [int]$resp.StatusCode; data = $data; detail = $null }
    } catch {
        $sc = 0; $detail = $null
        try { $sc = [int]$_.Exception.Response.StatusCode } catch {}
        try { $detail = $_.ErrorDetails.Message } catch {}
        return @{ ok = $false; status = $sc; data = $null; detail = $detail }
    }
}
function Body($o) { return ($o | ConvertTo-Json -Depth 6) }
function Login($u, $p) {
    # httpOnly refresh cookie (H-03): capture the Set-Cookie session so
    # /auth/token/refresh/ and /auth/logout/ can be exercised cookie-first.
    $headers = @{ "Content-Type" = "application/json" }
    try {
        $resp = Invoke-WebRequest -Uri "$base/auth/login/" -Method Post -Headers $headers -Body (Body @{ username=$u; password=$p }) -UseBasicParsing -SessionVariable s
        $data = $null
        try { $data = $resp.Content | ConvertFrom-Json } catch { $data = $resp.Content }
        return @{ ok = $true; status = [int]$resp.StatusCode; data = $data; session = $s; detail = $null }
    } catch {
        $sc = 0; $detail = $null
        try { $sc = [int]$_.Exception.Response.StatusCode } catch {}
        try { $detail = $_.ErrorDetails.Message } catch {}
        return @{ ok = $false; status = $sc; data = $null; session = $null; detail = $detail }
    }
}
function Report($name, $ok, $evidence) {
    $tag = if ($ok) { "PASS" } else { "FAIL" }
    $script:results += @{ name=$name; ok=$ok }
    Write-Output ("[{0}] {1} | {2}" -f $tag, $name, $evidence)
}

# ---------------------------------------------------------------
# PHASE 1: logins (ONCE per role, reuse tokens - stay under 10/min throttle)
# ---------------------------------------------------------------
Write-Output "=== PHASE 1: Login ==="
$tokens = @{}
$lg = Login "admin" "AdminPass123!"
$tokens["ADMIN"] = $lg.data.access
Report "login admin" ($lg.status -eq 200) "status=$($lg.status)"
$roleUsers = @{ DOCTOR="doctor"; RECEPTIONIST="receptionist"; NURSE="nurse"; IT="it"; CENTER_MANAGER="cm" }
foreach ($r in $roleUsers.GetEnumerator()) {
    $l = Login $r.Value "Pass123!x"
    $tokens[$r.Key] = $l.data.access
    Report ("login " + $r.Value) ($l.status -eq 200) "status=$($l.status) hasAccess=$([bool]$l.data.access) hasRefreshInBody=$([bool]$l.data.refresh)"
}

# ---------------------------------------------------------------
# PHASE 2: Pagination LIVE (admin)
# ---------------------------------------------------------------
Write-Output "=== PHASE 2: Pagination ==="
$adm = $tokens["ADMIN"]
$p0 = Call "Get" "$base/patients/" $null $adm
$default20 = ($p0.status -eq 200) -and ($p0.data.results.Count -eq 20) -and ($p0.data.count -ge 20)
Report "patients default page_size=20" $default20 "results=$($p0.data.results.Count) count=$($p0.data.count)"

$p100 = Call "Get" "$base/patients/?page_size=100" $null $adm
$ps100 = ($p100.status -eq 200) -and ($p100.data.results.Count -eq 100) -and ($p100.data.count -ge 100)
Report "patients ?page_size=100 -> 100 results" $ps100 "results=$($p100.data.results.Count) count=$($p100.data.count)"

$total = $p100.data.count
$remainder = $total - 100
$p2 = Call "Get" "$base/patients/?page_size=100&page=2" $null $adm
$page2 = ($p2.status -eq 200) -and ($p2.data.results.Count -eq $remainder)
Report "patients page=2 returns remainder" $page2 "results=$($p2.data.results.Count) expected=$remainder"

# distinct rows between page1 and page2
$ids1 = @($p100.data.results | ForEach-Object { $_.id })
$ids2 = @($p2.data.results | ForEach-Object { $_.id })
$overlap = @($ids1 | Where-Object { $ids2 -contains $_ }).Count
Report "page1 vs page2 rows distinct" ($overlap -eq 0) "overlappingIds=$overlap"

$pcap = Call "Get" "$base/patients/?page_size=500" $null $adm
$capped = ($pcap.status -eq 200) -and ($pcap.data.results.Count -le 200) -and ($pcap.data.results.Count -eq $total)
Report "page_size=500 capped at 200 (no error)" $capped "results=$($pcap.data.results.Count) count=$($pcap.data.count)"

# other list endpoints honor pagination too (200 + results array <= 20 default, no error)
$otherLists = @(
    @{ name="centers";           url="centers/" },
    @{ name="medicines";         url="medicines/" },
    @{ name="appointments";      url="appointments/" },
    @{ name="medical-records";   url="medical-records/" },
    @{ name="users";             url="auth/users/" },
    @{ name="doctors/profiles";  url="doctors/profiles/" }
)
$listOk = $true
foreach ($ep in $otherLists) {
    $r = Call "Get" "$base/$($ep.url)" $null $adm
    $shape = ($r.status -eq 200) -and ($null -ne $r.data.results) -and ($null -ne $r.data.count)
    if (-not $shape) { $listOk = $false; Write-Output ("  list {0} -> {1} hasResults={2}" -f $ep.name, $r.status, $null -ne $r.data.results) }
    else { Write-Output ("  list {0} -> {1} results={2} count={3}" -f $ep.name, $r.status, $r.data.results.Count, $r.data.count) }
}
Report "pagination meta present on all 7 list endpoints" $listOk "checked: patients,centers,medicines,appointments,medical-records,users,doctors"

# ---------------------------------------------------------------
# PHASE 3: NSS validation (receptionist) + cleanup
# ---------------------------------------------------------------
Write-Output "=== PHASE 3: NSS validation ==="
$rec = $tokens["RECEPTIONIST"]
$stamp = Get-Date -Format "HHmmssfff"

$nss12 = Call "Post" "$base/patients/" (Body @{ first_name="Nss12"; last_name="Digits"; gender="MALE"; phone="8095551212"; nss="123456789012"; email="nss12$stamp@example.com" }) $rec
Report "NSS 12 digits rejected (400)" ($nss12.status -eq 400) "status=$($nss12.status) nssErrors=$((($nss12.detail | ConvertFrom-Json).nss -join ';'))"

$nssLtr = Call "Post" "$base/patients/" (Body @{ first_name="NssLtr"; last_name="Letters"; gender="MALE"; phone="8095551213"; nss="1234ABC78901"; email="nssltr$stamp@example.com" }) $rec
Report "NSS with letters rejected (400)" ($nssLtr.status -eq 400) "status=$($nssLtr.status) nssErrors=$((($nssLtr.detail | ConvertFrom-Json).nss -join ';'))"

$nss11 = Call "Post" "$base/patients/" (Body @{ first_name="NssOk"; last_name="Eleven"; gender="MALE"; phone="8095551214"; nss="12345678901"; email="nssok$stamp@example.com" }) $rec
Report "NSS 11 digits accepted (201)" ($nss11.status -eq 201) "status=$($nss11.status) id=$($nss11.data.id)"
$nssPatId = $nss11.data.id

# cleanup: delete created patient(s)
$del = Call "Delete" "$base/patients/$nssPatId/" $null $adm
Report "cleanup: delete NSS-test patient" ($del.status -eq 204) "status=$($del.status)"

# ---------------------------------------------------------------
# PHASE 4: Patient-create RBAC (admin/doctor/receptionist=201; nurse/it/cm=403)
# ---------------------------------------------------------------
Write-Output "=== PHASE 4: Patient create RBAC ==="
$pBody = @{ first_name="Rbac"; last_name="Patient$stamp"; birth_date="1980-01-01"; gender="MALE"; phone="8095550199"; email="rbac$stamp@example.com" }
$rw = @(
    @{ role="ADMIN";       exp=201 },
    @{ role="DOCTOR";      exp=201 },
    @{ role="RECEPTIONIST";exp=201 },
    @{ role="NURSE";       exp=403 },
    @{ role="IT";          exp=403 },
    @{ role="CENTER_MANAGER"; exp=403 }
)
$createdIds = @()
foreach ($t in $rw) {
    $b = Body @{ first_name=$t.role; last_name="Patient$stamp"; birth_date="1980-01-01"; gender="MALE"; phone="8095550199"; email="rbac$stamp@example.com" }
    $r = Call "Post" "$base/patients/" $b $tokens[$t.role]
    $ok = ($r.status -eq $t.exp)
    if ($r.status -eq 201) { $createdIds += $r.data.id }
    Report ("patient create as " + $t.role) $ok "got=$($r.status) exp=$($t.exp)"
}
# cleanup created patients
$cleanAll = $true
foreach ($id in $createdIds) {
    $d = Call "Delete" "$base/patients/$id/" $null $adm
    if ($d.status -ne 204) { $cleanAll = $false }
}
Report "cleanup: delete RBAC-test patients" $cleanAll "deleted=$($createdIds.Count)"

# ---------------------------------------------------------------
# PHASE 5: PII masking (IT/CM masked; admin/doctor/receptionist/nurse full)
# ---------------------------------------------------------------
Write-Output "=== PHASE 5: PII masking ==="
$maskPat = Call "Post" "$base/patients/" (Body @{ first_name="Pii"; last_name="Check$stamp"; birth_date="1990-05-14"; gender="FEMALE"; phone="8095553131"; email="pii$stamp@example.com"; cedula="00101655332"; nss="98765432101"; address="42 Mask Rd" }) $rec
$maskPatId = $maskPat.data.id
$fullExpect = @{ phone="8095553131"; email="pii$stamp@example.com"; first_name="Pii"; last_name="Check$stamp"; cedula="00101655332"; nss="98765432101" }

$maskRows = @(
    @{ role="IT"; full=$false }, @{ role="CENTER_MANAGER"; full=$false },
    @{ role="ADMIN"; full=$true }, @{ role="DOCTOR"; full=$true },
    @{ role="RECEPTIONIST"; full=$true }, @{ role="NURSE"; full=$true }
)
$bullet = [string][char]0x2022
foreach ($t in $maskRows) {
    $d = (Call "Get" "$base/patients/$maskPatId/" $null $tokens[$t.role]).data
    if ($t.full) {
        $ok = ($d.phone -eq $fullExpect.phone) -and ($d.email -eq $fullExpect.email) -and ($d.first_name -eq $fullExpect.first_name) -and ($d.last_name -eq $fullExpect.last_name) -and ($d.cedula -eq $fullExpect.cedula) -and ($d.nss -eq $fullExpect.nss)
    } else {
        # _mask() keeps first2+last2, replaces middle with U+2022 bullets.
        # Invoke-WebRequest may mangle the bullet (codepage), so assert via
        # "2 chars + non-digits + 2 chars" pattern which survives mojibake.
        $phoneM = $d.phone -match '^.{2}\D+.{2}$'
        $emailM = $d.email -match '^.{2}\D+.{2}$'
        $cedM   = $d.cedula -match '^.{2}\D+.{2}$'
        $nssM   = $d.nss -match '^.{2}\D+.{2}$'
        $nameM  = ($d.first_name -ne $fullExpect.first_name) -and ($d.last_name -ne $fullExpect.last_name) -and ($d.first_name -match '\D+') -and ($d.last_name -match '\D+')
        $ok = $phoneM -and $emailM -and $cedM -and $nssM -and $nameM
    }
    Report ("PII " + $t.role + " " + $(if ($t.full) { "FULL" } else { "MASKED" })) $ok "phone=$($d.phone) email=$($d.email) name=$($d.first_name) cedula=$($d.cedula) nss=$($d.nss)"
}
$del2 = Call "Delete" "$base/patients/$maskPatId/" $null $adm
Report "cleanup: delete PII-test patient" ($del2.status -eq 204) "status=$($del2.status)"

# ---------------------------------------------------------------
# PHASE 6: JWT rotation + logout blacklist
# ---------------------------------------------------------------
Write-Output "=== PHASE 6: JWT (httpOnly cookie) ==="
$authUri = "$base/auth/"
$lr = Login "admin" "AdminPass123!"
$jwtHasBoth = ($lr.status -eq 200) -and [bool]$lr.data.access -and (-not [bool]$lr.data.refresh) -and [bool]($lr.session.Cookies.GetCookies($authUri) | Where-Object { $_.Name -eq "mc_refresh" })
Report "JWT login: access in body, refresh only in httpOnly cookie" $jwtHasBoth "status=$($lr.status) access=$([bool]$lr.data.access) refreshInBody=$([bool]$lr.data.refresh)"
$oldCookie = ($lr.session.Cookies.GetCookies($authUri) | Where-Object { $_.Name -eq "mc_refresh" }).Value

$r2 = Call "Post" "$base/auth/token/refresh/" "{}" $null $lr.session
$newCookie = ($lr.session.Cookies.GetCookies($authUri) | Where-Object { $_.Name -eq "mc_refresh" }).Value
Report "JWT refresh via cookie rotates (new access + rotated cookie)" (($r2.status -eq 200) -and [bool]$r2.data.access -and ($newCookie -and $newCookie -ne $oldCookie)) "status=$($r2.status) access=$([bool]$r2.data.access) rotated=$($newCookie -ne $oldCookie)"

$lr.session.Cookies.SetCookies($authUri, "mc_refresh=$oldCookie")
$r3 = Call "Post" "$base/auth/token/refresh/" "{}" $null $lr.session
Report "JWT old cookie rejected after rotation (401)" ($r3.status -eq 401) "status=$($r3.status) detail=$($r3.detail)"

# logout: blacklist the cookie's refresh + clear it
$lr2 = Login "admin" "AdminPass123!"
$logout = Call "Post" "$base/auth/logout/" "{}" $lr2.data.access $lr2.session
$cookieAfterLogout = @($lr2.session.Cookies.GetCookies($authUri) | Where-Object { $_.Name -eq "mc_refresh" -and $_.Value })
Report "JWT logout via cookie returns 204 + clears cookie" (($logout.status -eq 204) -and ($cookieAfterLogout.Count -eq 0)) "status=$($logout.status) cookiePresentAfter=$($cookieAfterLogout.Count)"

$meAfterLogout = Call "Get" "$base/auth/me/" $null $lr2.data.access $null
Report "access token still valid after logout (refresh-only revocation)" ($meAfterLogout.status -eq 200 -and $null -ne $meAfterLogout.data) "note: access is stateless (SimpleJWT); logout revokes refresh only; /auth/me/ with access -> $($meAfterLogout.status)"

$r4 = Call "Post" "$base/auth/token/refresh/" "{}" $null $lr2.session
Report "JWT refresh after logout rejected (401)" ($r4.status -eq 401) "status=$($r4.status)"

# ---------------------------------------------------------------
# PHASE 7: Login throttle (wait for window reset, then rapid attempts)
# ---------------------------------------------------------------
Write-Output "=== PHASE 7: Login throttle ==="
Write-Output "  waiting 65s for login-throttle window reset..."
Start-Sleep -Seconds 65
$throttled = $false; $first429 = $null
for ($i = 1; $i -le 12; $i++) {
    $r = Login "throttleuser$i" "wrongpass"
    if ($r.status -eq 429) { $throttled = $true; $first429 = $i; break }
}
Report "login throttle 429 after >10 rapid attempts" ($throttled -and $first429 -ge 10) ("first429At={0} throttled={1}" -f $first429, $throttled)

# ---------------------------------------------------------------
Write-Output ""
Write-Output "=== SUMMARY ==="
$p = ($results | Where-Object { $_.ok }).Count
$f = ($results | Where-Object { -not $_.ok }).Count
Write-Output ("Total: {0} PASS, {1} FAIL" -f $p, $f)
if ($f -gt 0) {
    Write-Output "Failed checks:"
    $results | Where-Object { -not $_.ok } | ForEach-Object { Write-Output ("  - " + $_.name) }
}
exit $(if ($f -gt 0) { 1 } else { 0 })
