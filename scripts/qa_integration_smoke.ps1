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
        $detail = $null
        try { $detail = $_.ErrorDetails.Message } catch {}
        return @{ ok = $false; status = $sc; data = $null; detail = $detail }
    }
}
function Body($o) { return ($o | ConvertTo-Json -Depth 5) }

$admin = (Call "Post" "$base/auth/login/" (Body @{ username="admin"; password="AdminPass123!" }) $null)
$adminTok = $admin.data.access
Write-Output "admin login: $($admin.status)"

# 1. Center with required phone
$c = Call "Post" "$base/centers/" (Body @{ name="Central Clinic"; code="CC01"; address="Av. Principal 100"; phone="+1-555-2000" }) $adminTok
Write-Output "center create -> $($c.status) $(if (-not $c.ok) { $c.detail })"
$centerId = $c.data.id

# 2. Medicine with concentration field
$m = Call "Post" "$base/medicines/" (Body @{ generic_name="Paracetamol"; commercial_name="Tylenol"; concentration="500 mg" }) $adminTok
Write-Output "medicine create -> $($m.status) $(if (-not $m.ok) { $m.detail })"
$medId = $m.data.id

# 3. Doctor profile for the doctor user (find id)
$users = (Call "Get" "$base/auth/users/" $null $adminTok).data.results
$docUser = $users | Where-Object { $_.username -eq "doctor" } | Select-Object -First 1
Write-Output "doctor user id: $($docUser.id)"
$dp = Call "Post" "$base/doctors/profiles/" (Body @{ user=$docUser.id; specialty="Cardiology"; license_number="LIC-QA-001"; contact_phone="+1-555-3000" }) $adminTok
Write-Output "doctor profile create -> $($dp.status) $(if (-not $dp.ok) { $dp.detail })"
$doctorProfileId = $dp.data.id

# 4. Patient (receptionist)
$recep = (Call "Post" "$base/auth/login/" (Body @{ username="receptionist"; password="Pass123!x" }) $null)
$recepTok = $recep.data.access
Write-Output "receptionist login: $($recep.status)"
$pat = Call "Post" "$base/patients/" (Body @{ first_name="Ana"; last_name="Perez"; birth_date="1990-05-14"; gender="FEMALE"; phone="+1-555-0100"; address="123 Main St"; email="ana.perez@example.com" }) $recepTok
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
$rec = Call "Post" "$base/medical-records/" (Body @{ patient=$patientId; title="Initial consult"; diagnosis="Hypertension"; treatment="Lifestyle + meds" }) $docTok
Write-Output "medical record create -> $($rec.status)"
$recId = $rec.data.id
$log = Call "Post" "$base/consultation-logs/" (Body @{ patient=$patientId; center=$centerId; subjective="Headaches"; objective="BP 150/95"; assessment="Stage 1 HTN"; plan="Follow up in 4 weeks" }) $docTok
Write-Output "consultation log create -> $($log.status) $(if (-not $log.ok) { $log.detail })"

# 9. GET record detail includes images + logs
$recDetail = Call "Get" "$base/medical-records/$recId/" $null $docTok
Write-Output "record detail ok -> $($recDetail.status) (images: $($recDetail.data.images.Count))"

Write-Output "DONE. created ids -> center=$centerId medicine=$medId doctorProfile=$doctorProfileId patient=$patientId appointment=$apptId record=$recId"
