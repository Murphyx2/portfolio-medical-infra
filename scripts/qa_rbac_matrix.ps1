$ErrorActionPreference = "Stop"
$base = "http://localhost:8000/api"
# Unique suffix per run: centers use unique `code`, medicines use
# unique_together(generic, commercial, concentration) - avoids 400 on reruns.
$runId = Get-Random -Minimum 100000 -Maximum 999999

function Call($method, $url, $body, $token, $session) {
    $headers = @{ "Content-Type" = "application/json" }
    if ($token) { $headers["Authorization"] = "Bearer $token" }
    $params = @{ Uri = $url; Method = $method; Headers = $headers }
    if ($body) { $params["Body"] = $body }
    if ($session) { $params["WebSession"] = $session }
    try {
        $r = Invoke-RestMethod @params
        return @{ ok = $true; status = 200; data = $r }
    } catch {
        $sc = [int]$_.Exception.Response.StatusCode
        return @{ ok = $false; status = $sc; data = $null }
    }
}

function Login($u, $p) {
    # httpOnly refresh cookie (H-03): capture the Set-Cookie session so
    # /auth/token/refresh/ and /auth/logout/ can be exercised cookie-first.
    $b = @{ username = $u; password = $p } | ConvertTo-Json
    # login is throttled at 10/min per IP: retry with a backoff so this script
    # stays green even when run right after another QA script.
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        try {
            $r = Invoke-RestMethod -Uri "$base/auth/login/" -Method Post -Headers @{ "Content-Type" = "application/json" } -Body $b -SessionVariable s
            return @{ ok = $true; status = 200; data = $r; session = $s }
        } catch {
            $sc = 0
            try { $sc = [int]$_.Exception.Response.StatusCode } catch {}
            if ($sc -eq 429 -and $attempt -lt 3) {
                $wait = 30
                try {
                    $m = [regex]::Match($_.ErrorDetails.Message, "en (\d+) segundos")
                    if ($m.Success) { $wait = [int]$m.Groups[1].Value + 3 }
                } catch {}
                Start-Sleep -Seconds $wait
                continue
            }
            return @{ ok = $false; status = $sc; data = $null; session = $null }
        }
    }
}

function Body($obj) { return ($obj | ConvertTo-Json -Depth 5) }

# login each role ONCE, reuse tokens (stay under 10/min login throttle)
$tokens = @{}
$tokens["ADMIN"] = (Login "admin" "AdminPass123!").data.access
Write-Output "admin login ok: $([bool]$tokens['ADMIN'])"

# ensure role users exist (ignore duplicate errors)
$roleUsers = @{ DOCTOR="doctor"; RECEPTIONIST="receptionist"; NURSE="nurse"; IT="it"; CENTER_MANAGER="cm" }
foreach ($r in $roleUsers.GetEnumerator()) {
    $b = Body @{ username = $r.Value; email = "$($r.Value)@example.com"; password = "Pass123!x"; role = $r.Key; first_name = $r.Value }
    $c = Call "Post" "$base/auth/users/" $b $tokens["ADMIN"]
    Write-Output ("ensure user {0,-6} ({1,-15}) -> {2}" -f $r.Key, $r.Value, $c.status)
}
foreach ($r in $roleUsers.GetEnumerator()) {
    $tokens[$r.Key] = (Login $r.Value "Pass123!x").data.access
    Write-Output ("login {0,-6} ok: {1}" -f $r.Key, [bool]$tokens[$r.Key])
}

# create a patient as receptionist
$patBody = Body @{ first_name="Ana"; last_name="Perez"; birth_date="1990-05-14"; gender="FEMALE"; phone="8095550100"; address="123 Main St, Springfield"; email="ana.perez@example.com" }
$pat = Call "Post" "$base/patients/" $patBody $tokens["RECEPTIONIST"]
Write-Output ("create patient -> {0}" -f $pat.status)
$patId = $pat.data.id

# ensure a center + medicine + doctor profile exist (admin) for appointment/record payloads
$center = Call "Post" "$base/centers/" (Body @{ name="Central Clinic $runId"; code="CC$runId"; address="Av. Principal 100"; phone="8095552000" }) $tokens["ADMIN"]
$med = Call "Post" "$base/medicines/" (Body @{ generic_name="Paracetamol"; commercial_name="Tylenol $runId"; concentration="500 mg" }) $tokens["ADMIN"]
Write-Output ("ensure center -> {0}, medicine -> {1}" -f $center.status, $med.status)

# doctor profile for the `doctor` user (fetch existing or create)
$users = (Call "Get" "$base/auth/users/?search=doctor" $null $tokens["ADMIN"]).data.results
$docUser = $users | Where-Object { $_.username -eq "doctor" } | Select-Object -First 1
$profiles = (Call "Get" "$base/doctors/profiles/?user=$($docUser.id)" $null $tokens["ADMIN"]).data.results
$docProfile = $profiles | Select-Object -First 1
if (-not $docProfile) {
    $dp = Call "Post" "$base/doctors/profiles/" (Body @{ user=$docUser.id; specialty="Cardiology"; license_number="LIC-RBAC-1"; contact_phone="8095553000" }) $tokens["ADMIN"]
    $docProfile = $dp.data
}
$docProfileId = $docProfile.id
Write-Output ("doctor profile id -> {0}" -f $docProfileId)

$matrix = @(
    @{ role="ADMIN"; url="$base/patients/"; method="GET";    expected="200" },
    @{ role="ADMIN"; url="$base/patients/"; method="POST";   expected="201" },
    @{ role="ADMIN"; url="$base/auth/users/"; method="GET";  expected="200" },
    @{ role="ADMIN"; url="$base/centers/"; method="POST";    expected="201" },
    @{ role="ADMIN"; url="$base/medicines/"; method="POST";  expected="201" },
    @{ role="DOCTOR"; url="$base/medical-records/"; method="POST"; expected="201" },
    @{ role="DOCTOR"; url="$base/patients/"; method="POST";  expected="201" },
    @{ role="DOCTOR"; url="$base/auth/users/"; method="GET"; expected="403" },
    @{ role="DOCTOR"; url="$base/centers/"; method="POST";   expected="403" },
    @{ role="DOCTOR"; url="$base/medicines/"; method="POST"; expected="403" },
    @{ role="RECEPTIONIST"; url="$base/patients/"; method="POST"; expected="201" },
    @{ role="RECEPTIONIST"; url="$base/appointments/"; method="POST"; expected="201" },
    @{ role="RECEPTIONIST"; url="$base/medical-records/"; method="POST"; expected="403" },
    @{ role="RECEPTIONIST"; url="$base/auth/users/"; method="GET"; expected="403" },
    @{ role="NURSE"; url="$base/medical-records/"; method="POST"; expected="201" },
    @{ role="NURSE"; url="$base/patients/"; method="POST"; expected="403" },
    @{ role="NURSE"; url="$base/patients/"; method="GET"; expected="200" },
    @{ role="IT"; url="$base/auth/users/"; method="GET"; expected="200" },
    @{ role="IT"; url="$base/centers/"; method="POST"; expected="201" },
    @{ role="IT"; url="$base/medicines/"; method="POST"; expected="201" },
    @{ role="IT"; url="$base/patients/"; method="POST"; expected="403" },
    @{ role="CENTER_MANAGER"; url="$base/centers/"; method="GET"; expected="200" },
    @{ role="CENTER_MANAGER"; url="$base/patients/"; method="POST"; expected="403" }
)

$payloads = @{
    "patients/" = @{ first_name="Test"; last_name="Case"; birth_date="1980-01-01"; gender="MALE"; phone="8095550199"; email="tc@example.com" }
    "medical-records/" = @{ patient=$patId; title="QA record"; diagnosis="QA test"; treatment="none" }
    "appointments/" = @{ patient=$patId; doctor=$docProfileId; date_time="2026-09-01T10:00:00Z"; reason="QA appointment" }
    "centers/" = @{ name="QA Center $runId"; code="QAC$runId"; address="1 QA Rd"; phone="8095556000" }
    "medicines/" = @{ generic_name="ParaQA-$runId"; commercial_name="QAcol"; concentration="500 mg" }
}

Write-Output "=== RBAC matrix ==="
$pass = 0; $fail = 0
foreach ($m in $matrix) {
    $tok = $tokens[$m.role]
    if (-not $tok) { Write-Output ("{0,-15} {1,-4} {2} -> NO TOKEN" -f $m.role, $m.method, $m.url); $fail++; continue }
    if ($m.method -eq "GET") {
        $r = Call "Get" $m.url $null $tok
    } else {
        $seg = ($m.url.TrimEnd("/") -split "/")[-1] + "/"
        $body = if ($payloads[$seg]) { Body $payloads[$seg] } else { "{}" }
        # Distinct values per role so an earlier ADMIN POST (unique code /
        # medicine) does not make the identical IT POST fail with 400.
        if ($m.role -eq "IT") {
            $p = @{}
            foreach ($k in $payloads[$seg].Keys) { $p[$k] = $payloads[$seg][$k] }
            if ($seg -eq "centers/") { $p.code = "QAC-IT-$runId"; $p.name = "QA Center IT $runId" }
            if ($seg -eq "medicines/") { $p.generic_name = "ParaQA-IT-$runId" }
            $body = Body $p
        }
        $r = Call "Post" $m.url $body $tok
    }
    $match = ($r.status.ToString() -eq $m.expected) -or (($m.expected -eq "201") -and ($r.status -eq 200) -and $r.ok)
    if ($match) { $pass++ } else { $fail++ }
    Write-Output ("{0,-15} {1,-4} {2,-30} got {3} (exp {4}) {5}" -f $m.role, $m.method, $m.url, $r.status, $m.expected, $(if ($match) { "PASS" } else { "FAIL" }))
}
Write-Output ("RBAC matrix: {0} passed, {1} failed" -f $pass, $fail)

Write-Output "=== PII masking by role (H-04) ==="
# IT, CENTER_MANAGER -> masked; DOCTOR, NURSE, ADMIN, RECEPTIONIST -> full
function Test-Masking($roleKey, $expectFull) {
    $d = (Call "Get" "$base/patients/$patId/" $null $tokens[$roleKey]).data
    $masked = ($d.phone -ne "8095550100") -and ($d.email -ne "ana.perez@example.com") -and ($d.address -ne "123 Main St, Springfield")
    $full = ($d.phone -eq "8095550100") -and ($d.email -eq "ana.perez@example.com") -and ($d.address -eq "123 Main St, Springfield")
    if ($expectFull) { return $full }
    return $masked
}
$maskingPass = 0; $maskingFail = 0
foreach ($t in @(
    @{ role="IT"; full=$false }, @{ role="CENTER_MANAGER"; full=$false },
    @{ role="RECEPTIONIST"; full=$true }, @{ role="DOCTOR"; full=$true }, @{ role="NURSE"; full=$true }, @{ role="ADMIN"; full=$true }
)) {
    $ok = Test-Masking $t.role $t.full
    $d = (Call "Get" "$base/patients/$patId/" $null $tokens[$t.role]).data
    Write-Output ("{0,-15} phone={1} email={2} => expect {3}: {4}" -f $t.role, $d.phone, $d.email, $(if ($t.full) { "FULL" } else { "MASKED" }), $(if ($ok) { "PASS" } else { "FAIL" }))
    if ($ok) { $maskingPass++ } else { $maskingFail++ }
}
Write-Output ("PII masking: {0} passed, {1} failed" -f $maskingPass, $maskingFail)

Write-Output "=== Schema / docs gating (M-01) ==="
$schemaAnon = (Call "Get" "$base/schema/" $null $null).status
$docsAnon = (Call "Get" "$base/docs/" $null $null).status
$schemaAdm = (Call "Get" "$base/schema/" $null $tokens["ADMIN"]).status
$docsAdm = (Call "Get" "$base/docs/" $null $tokens["ADMIN"]).status
$schemaIt = (Call "Get" "$base/schema/" $null $tokens["IT"]).status
$docsIt = (Call "Get" "$base/docs/" $null $tokens["IT"]).status
Write-Output ("schema anon={0} (exp 401) docs anon={1} (exp 401) schema admin={2} (exp 200) docs admin={3} (exp 200) schema IT={4} (exp 200) docs IT={5} (exp 200)" -f $schemaAnon, $docsAnon, $schemaAdm, $docsAdm, $schemaIt, $docsIt)
$schemaOk = ($schemaAnon -eq 401) -and ($docsAnon -eq 401) -and ($schemaAdm -eq 200) -and ($docsAdm -eq 200) -and ($schemaIt -eq 200) -and ($docsIt -eq 200)
Write-Output ("schema/docs gating: {0}" -f $(if ($schemaOk) { "PASS" } else { "FAIL" }))

Write-Output "=== JWT refresh rotation + blacklist (httpOnly cookie) ==="
$lr = Login "admin" "AdminPass123!"
$authUri = "$base/auth/"
$oldCookie = ($lr.session.Cookies.GetCookies($authUri) | Where-Object { $_.Name -eq "mc_refresh" }).Value
$r2 = Call "Post" "$base/auth/token/refresh/" "{}" $null $lr.session
$newCookie = ($lr.session.Cookies.GetCookies($authUri) | Where-Object { $_.Name -eq "mc_refresh" }).Value
Write-Output ("rotate refresh via cookie -> {0}, access issued: {1}, cookie rotated: {2}" -f $r2.status, [bool]$r2.data.access, ($newCookie -ne $oldCookie))
$lr.session.Cookies.SetCookies($authUri, "mc_refresh=$oldCookie")
$r3 = Call "Post" "$base/auth/token/refresh/" "{}" $null $lr.session
Write-Output ("reuse old cookie -> {0} (expect 401 blacklist)" -f $r3.status)

Write-Output "=== Security basics ==="
$anon = Call "Get" "$base/patients/" $null $null
Write-Output ("anon GET patients -> {0} (expect 401)" -f $anon.status)
$bad = Login "admin" "wrongpass"
Write-Output ("bad login -> {0} (expect 401)" -f $bad.status)

Write-Output "=== Login throttle (expect 429) ==="
$throttled = $false
for ($i = 0; $i -lt 12; $i++) {
    # raw request, no Login retry: the helper's 429-backoff would hide the throttle
    try {
        Invoke-RestMethod -Uri "$base/auth/login/" -Method Post -Headers @{ "Content-Type" = "application/json" } -Body (Body @{ username="throttleuser$i"; password="wrongpass" }) | Out-Null
    } catch {
        $sc = 0
        try { $sc = [int]$_.Exception.Response.StatusCode } catch {}
        if ($sc -eq 429) { $throttled = $true; Write-Output "got 429 after $($i + 1) rapid attempts"; break }
    }
}
Write-Output ("throttle enforced: {0}" -f $throttled)
