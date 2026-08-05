$ErrorActionPreference = "Stop"
$base = "http://localhost:8000/api"

function Call($method, $url, $body, $token) {
    $headers = @{ "Content-Type" = "application/json" }
    if ($token) { $headers["Authorization"] = "Bearer $token" }
    try {
        $r = Invoke-RestMethod -Uri $url -Method $method -Headers $headers -Body $body
        return @{ ok = $true; status = 200; data = $r }
    } catch {
        $sc = [int]$_.Exception.Response.StatusCode
        return @{ ok = $false; status = $sc; data = $null }
    }
}

function Login($u, $p) {
    $b = @{ username = $u; password = $p } | ConvertTo-Json
    $r = Call "Post" "$base/auth/login/" $b $null
    return $r
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
$patBody = Body @{ first_name="Ana"; last_name="Perez"; birth_date="1990-05-14"; gender="FEMALE"; phone="+1-555-0100"; address="123 Main St, Springfield"; email="ana.perez@example.com" }
$pat = Call "Post" "$base/patients/" $patBody $tokens["RECEPTIONIST"]
Write-Output ("create patient -> {0}" -f $pat.status)
$patId = $pat.data.id

# ensure a center + medicine exist (admin) for appointment/record payloads
$center = Call "Post" "$base/centers/" (Body @{ name="Central Clinic"; code="CC01"; address="Av. Principal 100" }) $tokens["ADMIN"]
$med = Call "Post" "$base/medicines/" (Body @{ generic_name="Paracetamol"; commercial_name="Tylenol"; dosage="500mg"; unit="tablet" }) $tokens["ADMIN"]
Write-Output ("ensure center -> {0}, medicine -> {1}" -f $center.status, $med.status)

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
    "patients/" = @{ first_name="Test"; last_name="Case"; birth_date="1980-01-01"; gender="MALE"; phone="+1-555-0199"; email="tc@example.com" }
    "medical-records/" = @{ patient=$patId; title="QA record"; diagnosis="QA test"; treatment="none" }
    "appointments/" = @{ patient=$patId; date_time="2026-09-01T10:00:00Z"; reason="QA appointment" }
    "centers/" = @{ name="QA Center"; code="QAC02"; address="1 QA Rd" }
    "medicines/" = @{ generic_name="ParaQA"; commercial_name="QAcol"; dosage="500mg"; unit="tablet" }
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
        $r = Call "Post" $m.url $body $tok
    }
    $match = ($r.status.ToString() -eq $m.expected) -or (($m.expected -eq "201") -and ($r.status -eq 200) -and $r.ok)
    if ($match) { $pass++ } else { $fail++ }
    Write-Output ("{0,-15} {1,-4} {2,-30} got {3} (exp {4}) {5}" -f $m.role, $m.method, $m.url, $r.status, $m.expected, $(if ($match) { "PASS" } else { "FAIL" }))
}
Write-Output ("RBAC matrix: {0} passed, {1} failed" -f $pass, $fail)

Write-Output "=== PII redaction (IT vs DOCTOR) ==="
$itPat = Call "Get" "$base/patients/$patId/" $null $tokens["IT"]
$docPat = Call "Get" "$base/patients/$patId/" $null $tokens["DOCTOR"]
Write-Output ("IT  phone={0} email={1}" -f $itPat.data.phone, $itPat.data.email)
Write-Output ("DOC phone={0} email={1}" -f $docPat.data.phone, $docPat.data.email)
Write-Output ("IT masked={0} DOCTOR full={1}" -f ($itPat.data.phone -match "•"), ($docPat.data.phone -eq "+1-555-0100"))

Write-Output "=== JWT refresh rotation + blacklist ==="
$lr = Login "admin" "AdminPass123!"
$r2 = Call "Post" "$base/auth/token/refresh/" (Body @{ refresh = $lr.data.refresh }) $null
Write-Output ("rotate refresh -> {0}, new refresh issued: {1}" -f $r2.status, [bool]$r2.data.refresh)
$r3 = Call "Post" "$base/auth/token/refresh/" (Body @{ refresh = $lr.data.refresh }) $null
Write-Output ("reuse old refresh -> {0} (expect 401 blacklist)" -f $r3.status)

Write-Output "=== Security basics ==="
$anon = Call "Get" "$base/patients/" $null $null
Write-Output ("anon GET patients -> {0} (expect 401)" -f $anon.status)
$bad = Login "admin" "wrongpass"
Write-Output ("bad login -> {0} (expect 401)" -f $bad.status)

Write-Output "=== Login throttle (expect 429) ==="
$throttled = $false
for ($i = 0; $i -lt 12; $i++) {
    $r = Login "throttleuser$i" "wrongpass"
    if ($r.status -eq 429) { $throttled = $true; Write-Output "got 429 after $($i + 1) rapid attempts"; break }
}
Write-Output ("throttle enforced: {0}" -f $throttled)
