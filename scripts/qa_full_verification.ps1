# QA Full Verification - MedicalConsultations
# Independent verification per standard QA checklist.
# This script does NOT modify application code - it reports PASS/FAIL evidence.
$ErrorActionPreference = "Stop"
$base = "http://localhost:8000/api"
$results = @()

function Call($method, $url, $body, $token, $contentType = "application/json") {
    $headers = @{}
    if ($contentType) { $headers["Content-Type"] = $contentType }
    if ($token) { $headers["Authorization"] = "Bearer $token" }
    try {
        $params = @{
            Uri = $url
            Method = $method
            Headers = $headers
            UseBasicParsing = $true
        }
        if ($body) { $params["Body"] = $body }
        $resp = Invoke-WebRequest @params
        $data = $null
        try { $data = $resp.Content | ConvertFrom-Json } catch { $data = $resp.Content }
        return @{ ok = $true; status = [int]$resp.StatusCode; data = $data; detail = $null }
    } catch {
        $sc = 0
        try { $sc = [int]$_.Exception.Response.StatusCode } catch {}
        $detail = $null
        try { $detail = $_.ErrorDetails.Message } catch {}
        return @{ ok = $false; status = $sc; data = $null; detail = $detail }
    }
}
function Body($o) { return ($o | ConvertTo-Json -Depth 6) }
function Login($u, $p) {
    return Call "Post" "$base/auth/login/" (Body @{ username=$u; password=$p }) $null
}
function Report($name, $ok, $evidence) {
    $tag = if ($ok) { "PASS" } else { "FAIL" }
    $script:results += @{ name=$name; ok=$ok }
    Write-Output ("[{0}] {1} | {2}" -f $tag, $name, $evidence)
}

# ---------------------------------------------------------------
# PHASE A: RBAC matrix
# Login each role ONCE, reuse tokens.
# ---------------------------------------------------------------
Write-Output "=== PHASE A: RBAC matrix ==="
$tokens = @{}
$refreshTokens = @{}
$adminLogin = Login "admin" "AdminPass123!"
$tokens["ADMIN"] = $adminLogin.data.access
$refreshTokens["ADMIN"] = $adminLogin.data.refresh
Report "login:admin" ($adminLogin.status -eq 200) "status=$($adminLogin.status)"

$roleUsers = @{ DOCTOR="doctor"; RECEPTIONIST="receptionist"; NURSE="nurse"; IT="it"; CENTER_MANAGER="cm" }
foreach ($r in $roleUsers.GetEnumerator()) {
    # Ensure the user exists (ignore errors if already exists)
    $b = Body @{ username=$r.Value; email="$($r.Value)@example.com"; password="Pass123!x"; role=$r.Key; first_name=$r.Value }
    $c = Call "Post" "$base/auth/users/" $b $tokens["ADMIN"]
    Write-Output ("  ensure user {0} -> {1}" -f $r.Value, $c.status)
}
foreach ($r in $roleUsers.GetEnumerator()) {
    $lg = Login $r.Value "Pass123!x"
    $tokens[$r.Key] = $lg.data.access
    $refreshTokens[$r.Key] = $lg.data.refresh
    Report ("login:" + $r.Value) ($lg.status -eq 200) "status=$($lg.status)"
}

# Create a patient as receptionist (for payloads + PII checks)
$patBody = Body @{ first_name="Ana"; last_name="Perez"; birth_date="1990-05-14"; gender="FEMALE"; phone="+1-555-0100"; address="123 Main St, Springfield"; email="ana.perez@example.com" }
$pat = Call "Post" "$base/patients/" $patBody $tokens["RECEPTIONIST"]
Report "patient create (receptionist)" ($pat.status -eq 201) "status=$($pat.status)"
$patId = $pat.data.id

# Ensure center + medicine (admin) for appointment/record payloads - use unique names to avoid collisions
$stamp = Get-Date -Format "HHmmss"
$center = Call "Post" "$base/centers/" (Body @{ name="Central Clinic $stamp"; code="CC$stamp"; address="Av. Principal 100"; phone="+1-555-2000" }) $tokens["ADMIN"]
$med = Call "Post" "$base/medicines/" (Body @{ generic_name="Paracetamol$stamp"; commercial_name="Tylenol$stamp"; concentration="500 mg" }) $tokens["ADMIN"]
Report "center create (admin)" ($center.status -eq 201) "status=$($center.status)"
Report "medicine create (admin)" ($med.status -eq 201) "status=$($med.status)"
$centerId = $center.data.id
$medId = $med.data.id

# RBAC matrix rows: role, url, method, expected status
$matrix = @(
    @{ role="ADMIN";    url="$base/patients/";            method="GET";  expected="200" },
    @{ role="ADMIN";    url="$base/patients/";            method="POST"; expected="201" },
    @{ role="ADMIN";    url="$base/auth/users/";          method="GET";  expected="200" },
    @{ role="ADMIN";    url="$base/auth/users/";          method="POST"; expected="201" },
    @{ role="ADMIN";    url="$base/centers/";             method="POST"; expected="201" },
    @{ role="ADMIN";    url="$base/medicines/";           method="POST"; expected="201" },
    @{ role="ADMIN";    url="$base/doctors/profiles/";    method="POST"; expected="201" },
    @{ role="ADMIN";    url="$base/medical-records/";     method="POST"; expected="201" },
    @{ role="ADMIN";    url="$base/appointments/";        method="POST"; expected="201" },
    @{ role="ADMIN";    url="$base/consultation-logs/";   method="POST"; expected="201" },
    @{ role="ADMIN";    url="$base/doctors/schedules/";   method="POST"; expected="403" },
    @{ role="ADMIN";    url="$base/bindings/";            method="POST"; expected="201" },
    @{ role="DOCTOR";   url="$base/patients/";            method="GET";  expected="200" },
    @{ role="DOCTOR";   url="$base/patients/";            method="POST"; expected="201" },
    @{ role="DOCTOR";   url="$base/medical-records/";     method="POST"; expected="201" },
    @{ role="DOCTOR";   url="$base/consultation-logs/";   method="POST"; expected="201" },
    @{ role="DOCTOR";   url="$base/appointments/";        method="POST"; expected="201" },
    @{ role="DOCTOR";   url="$base/doctors/schedules/";   method="POST"; expected="201" },
    @{ role="DOCTOR";   url="$base/images/";              method="POST"; expected="400" },  # needs multipart w/ record - expect 400
    @{ role="DOCTOR";   url="$base/auth/users/";          method="GET";  expected="403" },
    @{ role="DOCTOR";   url="$base/centers/";             method="POST"; expected="403" },
    @{ role="DOCTOR";   url="$base/medicines/";           method="POST"; expected="403" },
    @{ role="DOCTOR";   url="$base/bindings/";            method="POST"; expected="403" },
    @{ role="RECEPTIONIST"; url="$base/patients/";        method="POST"; expected="201" },
    @{ role="RECEPTIONIST"; url="$base/appointments/";    method="POST"; expected="201" },
    @{ role="RECEPTIONIST"; url="$base/medical-records/"; method="POST"; expected="403" },
    @{ role="RECEPTIONIST"; url="$base/consultation-logs/"; method="POST"; expected="403" },
    @{ role="RECEPTIONIST"; url="$base/auth/users/";      method="GET";  expected="403" },
    @{ role="RECEPTIONIST"; url="$base/centers/";         method="POST"; expected="403" },
    @{ role="RECEPTIONIST"; url="$base/medicines/";       method="POST"; expected="403" },
    @{ role="RECEPTIONIST"; url="$base/doctors/profiles/"; method="POST"; expected="403" },
    @{ role="RECEPTIONIST"; url="$base/doctors/schedules/"; method="POST"; expected="403" },
    @{ role="RECEPTIONIST"; url="$base/bindings/";        method="POST"; expected="403" },
    @{ role="NURSE";     url="$base/medical-records/";    method="POST"; expected="201" },
    @{ role="NURSE";     url="$base/consultation-logs/";  method="POST"; expected="201" },
    @{ role="NURSE";     url="$base/images/";             method="POST"; expected="400" },
    @{ role="NURSE";     url="$base/patients/";           method="POST"; expected="403" },
    @{ role="NURSE";     url="$base/patients/";           method="GET";  expected="200" },
    @{ role="NURSE";     url="$base/auth/users/";         method="GET";  expected="403" },
    @{ role="NURSE";     url="$base/centers/";            method="POST"; expected="403" },
    @{ role="NURSE";     url="$base/appointments/";       method="POST"; expected="403" },
    @{ role="NURSE";     url="$base/doctors/schedules/";  method="POST"; expected="403" },
    @{ role="IT";        url="$base/auth/users/";         method="GET";  expected="200" },
    @{ role="IT";        url="$base/auth/users/";         method="POST"; expected="201" },
    @{ role="IT";        url="$base/centers/";            method="POST"; expected="201" },
    @{ role="IT";        url="$base/medicines/";          method="POST"; expected="201" },
    @{ role="IT";        url="$base/doctors/profiles/";   method="POST"; expected="201" },
    @{ role="IT";        url="$base/patients/";           method="POST"; expected="403" },
    @{ role="IT";        url="$base/medical-records/";    method="POST"; expected="403" },
    @{ role="IT";        url="$base/appointments/";       method="POST"; expected="403" },
    @{ role="IT";        url="$base/bindings/";           method="POST"; expected="403" },
    @{ role="CENTER_MANAGER"; url="$base/centers/";       method="GET";  expected="200" },
    @{ role="CENTER_MANAGER"; url="$base/patients/";      method="GET";  expected="200" },
    @{ role="CENTER_MANAGER"; url="$base/patients/";      method="POST"; expected="403" },
    @{ role="CENTER_MANAGER"; url="$base/medical-records/"; method="POST"; expected="403" },
    @{ role="CENTER_MANAGER"; url="$base/appointments/";  method="POST"; expected="403" },
    @{ role="CENTER_MANAGER"; url="$base/auth/users/";    method="GET";  expected="403" },
    @{ role="CENTER_MANAGER"; url="$base/medicines/";     method="POST"; expected="403" }
)

# resolve a real doctor profile id for appointment/schedule/binding payloads
$usersList = (Invoke-RestMethod -Uri "$base/auth/users/" -Headers @{Authorization="Bearer $($tokens['ADMIN'])"}).results
$docUser = $usersList | Where-Object { $_.username -eq "doctor" } | Select-Object -First 1
$docProfile = (Invoke-RestMethod -Uri "$base/doctors/profiles/" -Headers @{Authorization="Bearer $($tokens['ADMIN'])"}).results |
    Where-Object { $_.user_id -eq $docUser.id } | Select-Object -First 1
$matrixDoctorProfileId = if ($docProfile) { $docProfile.id } else { 1 }

$rowN = 0
$payloads = @{
    "patients/" = @{ first_name="RBAC"; last_name="Patient"; birth_date="1980-01-01"; gender="MALE"; phone="+1-555-0199"; email="rbac@example.com" }
    "medical-records/" = @{ patient=$patId; title="QA record $stamp"; diagnosis="QA test"; treatment="none" }
    "appointments/" = @{ patient=$patId; doctor=$matrixDoctorProfileId; date_time="2026-09-01T10:00:00Z"; notes="QA appointment" }
    "consultation-logs/" = @{ patient=$patId; subjective="S"; objective="O"; assessment="A"; plan="P" }
    "doctors/schedules/" = @{ doctor=$matrixDoctorProfileId; center=$centerId; weekday=0; start_time="09:00"; end_time="17:00" }
    "bindings/" = @{ doctor=$matrixDoctorProfileId; center=$centerId }
}

$pass = 0; $fail = 0
foreach ($m in $matrix) {
    $rowN++
    $tok = $tokens[$m.role]
    if (-not $tok) { Report ("RBAC " + $m.role + " " + $m.method + " " + $m.url) $false "NO TOKEN"; $fail++; continue }
    if ($m.method -eq "GET") {
        $r = Call "Get" $m.url $null $tok
    } else {
        $seg = ($m.url.TrimEnd("/") -split "/")[-1] + "/"
        if ($m.url -match "schedules") { $seg = "doctors/schedules/" }
        if ($m.url -match "bindings") { $seg = "bindings/" }
        if ($m.url -match "profiles") { $seg = "doctors/profiles/" }
        if ($m.url -match "users") { $seg = "users/" }
        if ($seg -eq "users/") {
            # unique user per row (ADMIN and IT both POST users)
            $u = "qa_row_${stamp}_$rowN"
            $body = Body @{ username=$u; email="$u@example.com"; password="Pass123!x"; role="NURSE" }
        } elseif ($seg -eq "doctors/profiles/") {
            # fresh user + license per row so ADMIN and IT rows never collide
            # (a second profile for the same user now correctly returns 400)
            $profileUser = Call "Post" "$base/auth/users/" (Body @{ username="prow_${stamp}_$rowN"; password="Pass123!x"; role="DOCTOR"; first_name="Prof" }) $tok
            $body = Body @{ user=$profileUser.data.id; specialty="Cardiology"; license_number="LIC-${stamp}-$rowN"; contact_phone="+1-555-8888" }
        } elseif ($m.url -match "/centers/") {
            # unique code per row (ADMIN and IT both POST centers)
            $body = Body @{ name="QA Center ${stamp}_$rowN"; code="QAC${stamp}_$rowN"; address="1 QA Rd"; phone="+1-555-7777" }
        } elseif ($m.url -match "/medicines/") {
            # unique medicine per row (ADMIN and IT both POST medicines)
            $body = Body @{ generic_name="ParaQA${stamp}_$rowN"; commercial_name="QAcol${stamp}_$rowN"; concentration="500 mg" }
        } else {
            $body = if ($payloads[$seg]) { Body $payloads[$seg] } else { "{}" }
        }
        $r = Call "Post" $m.url $body $tok
        if ($seg -eq "users/" -and $r.ok) { $lastCreatedUserId = $r.data.id }
    }
    $match = ($r.status.ToString() -eq $m.expected) -or (($m.expected -eq "201") -and ($r.status -eq 200) -and $r.ok) -or (($m.expected -eq "400") -and ($r.status -eq 400))
    if ($match) { $pass++ } else { $fail++ }
    Report ("RBAC " + $m.role + " " + $m.method + " " + $m.url) $match ("got {0} exp {1}" -f $r.status, $m.expected)
}
Report "RBAC matrix total" ($fail -eq 0) ("{0} passed, {1} failed" -f $pass, $fail)

# ---------------------------------------------------------------
# PHASE B: PII masking (IT + CENTER_MANAGER masked; DOCTOR, NURSE, ADMIN, RECEPTIONIST full)
# ---------------------------------------------------------------
Write-Output "=== PHASE B: PII masking ==="
$itPat = Call "Get" "$base/patients/$patId/" $null $tokens["IT"]
$docPat = Call "Get" "$base/patients/$patId/" $null $tokens["DOCTOR"]
$cmPat = Call "Get" "$base/patients/$patId/" $null $tokens["CENTER_MANAGER"]
$recPat = Call "Get" "$base/patients/$patId/" $null $tokens["RECEPTIONIST"]
$itMasked = ($itPat.data.phone -notmatch "\+1-555-0100") -and ($itPat.data.phone -ne "+1-555-0100") -and ($itPat.data.email -ne "ana.perez@example.com")
$docFull = ($docPat.data.phone -eq "+1-555-0100") -and ($docPat.data.email -eq "ana.perez@example.com")
$cmMasked = ($cmPat.data.phone -ne "+1-555-0100") -and ($cmPat.data.email -ne "ana.perez@example.com")
$recFull = ($recPat.data.phone -eq "+1-555-0100") -and ($recPat.data.email -eq "ana.perez@example.com")
Report "PII: IT masked" $itMasked ("IT phone={0} email={1}" -f $itPat.data.phone, $itPat.data.email)
Report "PII: doctor full" $docFull ("DOC phone={0} email={1}" -f $docPat.data.phone, $docPat.data.email)
Report "PII: center_manager masked" $cmMasked ("CM phone={0} email={1}" -f $cmPat.data.phone, $cmPat.data.email)
Report "PII: receptionist full" $recFull ("REC phone={0} email={1}" -f $recPat.data.phone, $recPat.data.email)

# ---------------------------------------------------------------
# PHASE C: E2E smoke flow
# center -> medicine -> doctor profile -> patient -> appointment cancel
# -> medical record + log + image upload -> record detail
# ---------------------------------------------------------------
Write-Output "=== PHASE C: E2E smoke ==="
$adminTok = $tokens["ADMIN"]; $recepTok = $tokens["RECEPTIONIST"]; $docTok = $tokens["DOCTOR"]

# doctor user id (for profile creation)
$users = (Call "Get" "$base/auth/users/" $null $adminTok).data.results
$docUser = $users | Where-Object { $_.username -eq "doctor" } | Select-Object -First 1
$dp = $null
# reuse an existing profile for the doctor if present, else create
$existingProfiles = (Call "Get" "$base/doctors/profiles/" $null $adminTok).data.results
$existing = $existingProfiles | Where-Object { $_.user_id -eq $docUser.id } | Select-Object -First 1
if ($existing) {
    $doctorProfileId = $existing.id
    Report "doctor profile reuse" $true "id=$doctorProfileId"
} else {
    $dp = Call "Post" "$base/doctors/profiles/" (Body @{ user=$docUser.id; specialty="Cardiology"; license_number="LIC-E2E-$stamp"; contact_phone="+1-555-3000" }) $adminTok
    $doctorProfileId = $dp.data.id
    Report "doctor profile create" ($dp.status -eq 201) "status=$($dp.status) id=$doctorProfileId"
}

# patient (receptionist) - unique email
$e2ePat = Call "Post" "$base/patients/" (Body @{ first_name="E2E"; last_name="Patient$stamp"; birth_date="1990-05-14"; gender="FEMALE"; phone="+1-555-0101"; address="456 Elm St"; email="e2e$stamp@example.com" }) $recepTok
Report "e2e patient create" ($e2ePat.status -eq 201) "status=$($e2ePat.status)"
$e2ePatId = $e2ePat.data.id

# approved binding doctor <-> center (required by H-03 before center-scoped
# writes) - fetch-or-create: the Phase A matrix may already have created it
$existingBindings = (Call "Get" "$base/bindings/?doctor=$doctorProfileId&center=$centerId" $null $adminTok).data.results
if ($existingBindings) {
    $bnd = @{ status = 200; ok = $true }
} else {
    $bnd = Call "Post" "$base/bindings/" (Body @{ doctor=$doctorProfileId; center=$centerId }) $adminTok
}
Report "e2e binding create (approved)" (($bnd.status -eq 200) -or ($bnd.status -eq 201)) "status=$($bnd.status)"

# appointment (receptionist) -> cancel (receptionist)
$ap = Call "Post" "$base/appointments/" (Body @{ patient=$e2ePatId; doctor=$doctorProfileId; center=$centerId; date_time="2026-09-01T10:00:00Z"; notes="E2E QA appointment" }) $recepTok
Report "e2e appointment create" ($ap.status -eq 201) "status=$($ap.status) id=$($ap.data.id)"
$apptId = $ap.data.id
$cancel = Call "Post" "$base/appointments/$apptId/cancel/" "{}" $recepTok
Report "e2e appointment cancel" ($cancel.status -eq 200 -and $cancel.data.status -eq "CANCELLED") "status=$($cancel.status) apptStatus=$($cancel.data.status)"

# medical record (doctor)
$rec = Call "Post" "$base/medical-records/" (Body @{ patient=$e2ePatId; center=$centerId; title="Initial consult $stamp"; diagnosis="Hypertension"; treatment="Lifestyle + meds"; medicine_and_doses="Amlodipine 5 mg daily"; notes="Follow up in 4 weeks" }) $docTok
Report "e2e record create" ($rec.status -eq 201) "status=$($rec.status) id=$($rec.data.id)"
$recId = $rec.data.id

# consultation log (doctor)
$log = Call "Post" "$base/consultation-logs/" (Body @{ patient=$e2ePatId; center=$centerId; subjective="Headaches"; objective="BP 150/95"; assessment="Stage 1 HTN"; plan="Follow up in 4 weeks" }) $docTok
Report "e2e log create" ($log.status -eq 201) "status=$($log.status) id=$($log.data.id)"

# image upload (doctor) - multipart via curl.exe (PS 5.1 lacks -Form); use a valid PNG
Add-Type -AssemblyName System.Drawing
$png = Join-Path $env:TEMP "qa_pixel_$stamp.png"
$bmp = New-Object System.Drawing.Bitmap(10,10)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.Clear([System.Drawing.Color]::Red)
$bmp.Save($png, [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()
$uploadResp = & curl.exe -s -o NUL -w "%{http_code}" -X POST "$base/images/" -H "Authorization: Bearer $docTok" -F "record=$recId" -F "image=@$png" -F "caption=E2E xray $stamp"
$imgUploaded = ($uploadResp -eq "201")
Report "e2e image upload" $imgUploaded "http=$uploadResp"

# record detail includes images + logs
$recDetail = Call "Get" "$base/medical-records/$recId/" $null $docTok
$detailOk = ($recDetail.status -eq 200) -and ($recDetail.data.images.Count -ge 1) -and ($recDetail.data.diagnosis -eq "Hypertension")
Report "e2e record detail" $detailOk ("status=$($recDetail.status) images=$($recDetail.data.images.Count) diagnosis=$($recDetail.data.diagnosis)")

# lists sanity
$patsList = (Call "Get" "$base/patients/" $null $recepTok).status
$apptsList = (Call "Get" "$base/appointments/" $null $recepTok).status
$medsList = (Call "Get" "$base/medicines/" $null $adminTok).status
$centsList = (Call "Get" "$base/centers/" $null $adminTok).status
Report "e2e list endpoints 200" (($patsList -eq 200) -and ($apptsList -eq 200) -and ($medsList -eq 200) -and ($centsList -eq 200)) "patients=$patsList appts=$apptsList meds=$medsList centers=$centsList"

# ---------------------------------------------------------------
# PHASE D: JWT rotation + blacklist
# ---------------------------------------------------------------
Write-Output "=== PHASE D: JWT rotation + blacklist ==="
$lr = Login "admin" "AdminPass123!"
$r2 = Call "Post" "$base/auth/token/refresh/" (Body @{ refresh = $lr.data.refresh }) $null
$rotated = ($r2.status -eq 200) -and [bool]$r2.data.refresh -and [bool]$r2.data.access
Report "JWT refresh rotate issues new tokens" $rotated "status=$($r2.status) newRefresh=$([bool]$r2.data.refresh)"
$r3 = Call "Post" "$base/auth/token/refresh/" (Body @{ refresh = $lr.data.refresh }) $null
Report "JWT old refresh blacklisted after rotation" ($r3.status -eq 401) "status=$($r3.status) detail=$($r3.detail)"
$r4 = Call "Post" "$base/auth/token/refresh/" (Body @{ refresh = $r2.data.refresh }) $null
Report "JWT new refresh still valid" ($r4.status -eq 200) "status=$($r4.status)"

# access token usable
$me = Call "Get" "$base/auth/me/" $null $lr.data.access
Report "JWT access token valid for /auth/me/" ($me.status -eq 200) "status=$($me.status)"

# ---------------------------------------------------------------
# PHASE E2: Bug reproduction - duplicate doctor profile for same user
# Fix P1: second profile for the same user must return 400 (not 500).
# ---------------------------------------------------------------
Write-Output "=== PHASE E2: duplicate doctor-profile robustness ==="
$adminTok2 = (Login "admin" "AdminPass123!").data.access
$dupUser = Call "Post" "$base/auth/users/" (Body @{ username="dup$stamp"; password="Pass123!x"; role="DOCTOR"; first_name="Dup"; last_name="User" }) $adminTok2
$dupUserId = $dupUser.data.id
$firstProfile = Call "Post" "$base/doctors/profiles/" (Body @{ user=$dupUserId; specialty="Cardiology"; license_number="LIC-DUP1-$stamp"; contact_phone="+1-555-7776" }) $adminTok2
$dupProfile = Call "Post" "$base/doctors/profiles/" (Body @{ user=$dupUserId; specialty="Cardiology"; license_number="LIC-DUP2-$stamp"; contact_phone="+1-555-7776" }) $adminTok2
Report "duplicate doctor profile: first create -> 201" ($firstProfile.status -eq 201) "got=$($firstProfile.status)"
Report "duplicate doctor profile: second -> 400 (not 500)" ($dupProfile.status -eq 400) "got=$($dupProfile.status) detail=$($dupProfile.detail)"

# ---------------------------------------------------------------
# PHASE E: Security basics
# ---------------------------------------------------------------
Write-Output "=== PHASE E: Security basics ==="
$anon = Call "Get" "$base/patients/" $null $null
Report "anon GET patients -> 401" ($anon.status -eq 401) "status=$($anon.status)"
$anonSchema = Call "Get" "$base/schema/" $null $null
Report "anon GET schema -> 401 (gated, M-01)" ($anonSchema.status -eq 401) "status=$($anonSchema.status)"
$schemaAdm = Call "Get" "$base/schema/" $null $tokens["ADMIN"]
Report "admin GET schema -> 200" ($schemaAdm.status -eq 200) "status=$($schemaAdm.status)"
$bad = Login "admin" "wrongpass"
Report "bad login -> 401" ($bad.status -eq 401) "status=$($bad.status)"

# ---------------------------------------------------------------
# PHASE F: Login throttle - wait for window reset then 12 rapid attempts
# ---------------------------------------------------------------
Write-Output "=== PHASE F: Login throttle ==="
Write-Output "  waiting 65s for login-throttle window reset..."
Start-Sleep -Seconds 65
$throttled = $false
$first429 = $null
for ($i = 1; $i -le 12; $i++) {
    $r = Login "throttleuser$i" "wrongpass"
    if ($r.status -eq 429) { $throttled = $true; $first429 = $i; break }
}
Report "login throttle -> 429 after ~11 rapid attempts" ($throttled -and $first429 -ge 10) ("first429At={0} throttled={1}" -f $first429, $throttled)

# ---------------------------------------------------------------
# Summary
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
