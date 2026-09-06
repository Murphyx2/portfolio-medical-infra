$ErrorActionPreference = "Stop"
$base = "http://localhost:8000/api"
$runId = Get-Random -Minimum 100000 -Maximum 999999

function Call($method, $url, $body, $token) {
    $headers = @{ "Content-Type" = "application/json" }
    if ($token) { $headers["Authorization"] = "Bearer $token" }
    try {
        $r = Invoke-RestMethod -Uri $url -Method $method -Headers $headers -Body $body
        return @{ ok = $true; status = 200; data = $r }
    } catch {
        $sc = [int]$_.Exception.Response.StatusCode
        $detail = $null
        try { $detail = $_.ErrorDetails.Message } catch {}
        return @{ ok = $false; status = $sc; data = $null; detail = $detail }
    }
}
function Body($o) { return ($o | ConvertTo-Json -Depth 5) }

$admin = (Call "Post" "$base/auth/login/" (Body @{ username="admin"; password="AdminPass123!" }) $null)
$adminTok = $admin.data.access
Write-Output "admin login: $($admin.status)"

# 0. Schema / docs gating (M-01): anonymous 401, admin/IT 200
$schemaAnon = (Call "Get" "$base/schema/" $null $null).status
$docsAnon = (Call "Get" "$base/docs/" $null $null).status
$schemaAdm = (Call "Get" "$base/schema/" $null $adminTok).status
$docsAdm = (Call "Get" "$base/docs/" $null $adminTok).status
Write-Output "schema gating: anon=$schemaAnon (exp 401), docs anon=$docsAnon (exp 401), schema admin=$schemaAdm (exp 200), docs admin=$docsAdm (exp 200)"

# 1. Center with required phone
$c = Call "Post" "$base/centers/" (Body @{ name="Central Clinic $runId"; code="CC$runId"; address="Av. Principal 100"; phone="8095552000" }) $adminTok
Write-Output "center create -> $($c.status) $(if (-not $c.ok) { $c.detail })"
$centerId = $c.data.id

# 2. Medicine with concentration field
$m = Call "Post" "$base/medicines/" (Body @{ generic_name="Paracetamol"; commercial_name="Tylenol $runId"; concentration="500 mg" }) $adminTok
Write-Output "medicine create -> $($m.status) $(if (-not $m.ok) { $m.detail })"
$medId = $m.data.id

# 3. Doctor profile for the doctor user (fetch existing or create)
$users = (Call "Get" "$base/auth/users/?search=doctor" $null $adminTok).data.results
$docUser = $users | Where-Object { $_.username -eq "doctor" } | Select-Object -First 1
Write-Output "doctor user id: $($docUser.id)"
$profiles = (Call "Get" "$base/doctors/profiles/?user=$($docUser.id)" $null $adminTok).data.results
$docProfile = $profiles | Select-Object -First 1
if (-not $docProfile) {
    $dp = Call "Post" "$base/doctors/profiles/" (Body @{ user=$docUser.id; specialty="Cardiology"; license_number="LIC-QA-001"; contact_phone="8095553000" }) $adminTok
    $docProfile = $dp.data
}
$doctorProfileId = $docProfile.id
Write-Output "doctor profile id: $($doctorProfileId)"

# 3b. Approved binding doctor <-> center (required by H-03 before center-scoped writes)
$bnd = Call "Post" "$base/bindings/" (Body @{ doctor=$doctorProfileId; center=$centerId }) $adminTok
Write-Output "binding create -> $($bnd.status) $(if (-not $bnd.ok) { $bnd.detail })"

# 4. Patient (receptionist)
$recep = (Call "Post" "$base/auth/login/" (Body @{ username="receptionist"; password="Pass123!x" }) $null)
$recepTok = $recep.data.access
Write-Output "receptionist login: $($recep.status)"
$pat = Call "Post" "$base/patients/" (Body @{ first_name="Ana"; last_name="Perez"; birth_date="1990-05-14"; gender="FEMALE"; phone="8095550100"; address="123 Main St"; email="ana.perez@example.com" }) $recepTok
Write-Output "patient create -> $($pat.status)"
$patientId = $pat.data.id

# 5. Appointment (receptionist) - needs doctor + patient
$ap = Call "Post" "$base/appointments/" (Body @{ patient=$patientId; doctor=$doctorProfileId; center=$centerId; date_time="2026-09-01T10:00:00Z"; notes="QA appointment" }) $recepTok
Write-Output "appointment create -> $($ap.status) $(if (-not $ap.ok) { $ap.detail })"
$apptId = $ap.data.id

# 6. Verify lists return data
$pats = (Call "Get" "$base/patients/" $null $recepTok).data
Write-Output "patients list count: $($pats.count)"
$appts = (Call "Get" "$base/appointments/" $null $recepTok).data
Write-Output "appointments list count: $($appts.count)"
$meds = (Call "Get" "$base/medicines/" $null $adminTok).data
Write-Output "medicines list count: $($meds.count)"
$cents = (Call "Get" "$base/centers/" $null $adminTok).data
Write-Output "centers list count: $($cents.count)"
$docs = (Call "Get" "$base/doctors/profiles/" $null $adminTok).data
Write-Output "doctor profiles list count: $($docs.count)"

# 7. Appointment lifecycle: cancel (receptionist), then doctor can see it
$cancel = Call "Post" "$base/appointments/$apptId/cancel/" "{}" $recepTok
Write-Output "appointment cancel -> $($cancel.status) (status now: $($cancel.data.status))"

# 8. Medical record + log + image upload end-to-end (doctor)
$docTok = (Call "Post" "$base/auth/login/" (Body @{ username="doctor"; password="Pass123!x" }) $null).data.access
Write-Output "doctor login: $([bool]$docTok)"
$rec = Call "Post" "$base/medical-records/" (Body @{ patient=$patientId; title="Initial consult"; diagnosis="Hypertension"; treatment="Lifestyle + meds"; center=$centerId }) $docTok
Write-Output "medical record create -> $($rec.status) $(if (-not $rec.ok) { $rec.detail })"
$recId = $rec.data.id
$log = Call "Post" "$base/consultation-logs/" (Body @{ patient=$patientId; center=$centerId; subjective="Headaches"; objective="BP 150/95"; assessment="Stage 1 HTN"; plan="Follow up in 4 weeks" }) $docTok
Write-Output "consultation log create -> $($log.status) $(if (-not $log.ok) { $log.detail })"

# 8b. Image upload (multipart via curl.exe, PS5.1 has no -Form)
$pngPath = Join-Path $env:TEMP "qa_upload.png"
[System.IO.File]::WriteAllBytes($pngPath, [System.Convert]::FromBase64String("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="))
$up = & curl.exe -s -o - -w "`n%{http_code}" -X POST -H "Authorization: Bearer $docTok" -F "record=$recId" -F "image=@$pngPath;type=image/png" -F "caption=x-ray" "$base/images/"
$upStatus = ($up | Select-Object -Last 1).Trim()
Write-Output "image upload -> $upStatus"

# 9. GET record detail includes images + logs
$recDetail = Call "Get" "$base/medical-records/$recId/" $null $docTok
Write-Output "record detail ok -> $($recDetail.status) (images: $(@($recDetail.data.images).Count))"

Write-Output "DONE. created ids -> center=$centerId medicine=$medId doctorProfile=$doctorProfileId patient=$patientId appointment=$apptId record=$recId"
