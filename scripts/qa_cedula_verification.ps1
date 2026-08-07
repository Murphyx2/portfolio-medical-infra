# Live cedula verification (new change: digits-only storage + 11-digit validation)
# - POST with hyphenated cedula -> 201, stored digits-only
# - POST with 10-digit cedula -> 400
# - POST with 12-digit cedula -> 400
# - PATCH with hyphenated cedula -> digits-only stored
# - IT/CENTER_MANAGER see masked cedula; ADMIN/DOCTOR see full digits
$ErrorActionPreference = "Stop"
$base = "http://localhost:8000/api"
$runId = Get-Random -Minimum 100000 -Maximum 999999

function Call($method, $url, $body, $token) {
    $headers = @{ "Content-Type" = "application/json" }
    if ($token) { $headers["Authorization"] = "Bearer $token" }
    try {
        $r = Invoke-WebRequest -Uri $url -Method $method -Headers $headers -Body $body -UseBasicParsing
        # PS 5.1 decodes application/json (no charset) as ISO-8859-1; re-read the raw
        # stream as UTF-8 so bullet-masked PII (U+2022) survives for exact checks.
        $raw = $null
        try {
            $stream = $r.RawContentStream
            $stream.Position = 0
            $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::UTF8)
            $raw = $reader.ReadToEnd()
        } catch {
            $raw = $r.Content
        }
        $data = $null
        try { $data = $raw | ConvertFrom-Json } catch { $data = $raw }
        return @{ ok = $true; status = [int]$r.StatusCode; data = $data; detail = $null }
    } catch {
        $sc = [int]$_.Exception.Response.StatusCode
        $detail = $null
        try { $detail = $_.ErrorDetails.Message } catch {}
        return @{ ok = $false; status = $sc; data = $null; detail = $detail }
    }
}
function Body($o) { return ($o | ConvertTo-Json -Depth 5) }
function Login($u, $p) {
    # Login is throttled to 10/min per IP; retry once after a short wait on 429.
    for ($try = 1; $try -le 3; $try++) {
        $r = Call "Post" "$base/auth/login/" (Body @{ username=$u; password=$p }) $null
        if ($r.status -ne 429) { return $r }
        Write-Output "  (login throttled; waiting 20s before retry #$try)"
        Start-Sleep -Seconds 20
    }
    return $r
}

$pass = 0; $fail = 0
function Check($name, $ok, $evidence) {
    $script:pass += $(if ($ok) { 1 } else { 0 })
    $script:fail += $(if ($ok) { 0 } else { 1 })
    Write-Output ("[{0}] {1} | {2}" -f $(if ($ok) { "PASS" } else { "FAIL" }), $name, $evidence)
}

$admin = Login "admin" "AdminPass123!"
$adminTok = $admin.data.access
Check "admin login" ($admin.status -eq 200) "status=$($admin.status)"

# 1. POST with hyphenated cedula -> 201 digits-only
$p1 = Call "Post" "$base/patients/" (Body @{ first_name="Ced"; last_name="Live$runId"; birth_date="1990-05-14"; gender="FEMALE"; phone="8095550100"; email="ced$runId@example.com"; cedula="010-0108492-0"; nss="123456789" }) $adminTok
Check "POST hyphenated cedula -> 201" ($p1.status -eq 201) "status=$($p1.status) cedula='$($p1.data.cedula)'"
Check "POST stored digits-only" ($p1.data.cedula -eq "01001084920") "got '$($p1.data.cedula)'"
$p1Id = $p1.data.id

# 2. GET round-trip stays digits-only
$g1 = Call "Get" "$base/patients/$p1Id/" $null $adminTok
Check "GET returns digits-only cedula" ($g1.data.cedula -eq "01001084920") "got '$($g1.data.cedula)'"

# 3. POST with 10-digit cedula -> 400
$p2 = Call "Post" "$base/patients/" (Body @{ first_name="Ced"; last_name="Bad10$runId"; gender="MALE"; cedula="010-0108492" }) $adminTok
Check "POST 10-digit cedula -> 400" ($p2.status -eq 400) "status=$($p2.status) detail=$($p2.detail)"

# 4. POST with 12-digit cedula -> 400
$p3 = Call "Post" "$base/patients/" (Body @{ first_name="Ced"; last_name="Bad12$runId"; gender="MALE"; cedula="010010849201" }) $adminTok
Check "POST 12-digit cedula -> 400" ($p3.status -eq 400) "status=$($p3.status) detail=$($p3.detail)"

# 5. PATCH with hyphenated cedula -> digits-only stored
$pat = Call "Post" "$base/patients/" (Body @{ first_name="Ced"; last_name="Patch$runId"; gender="MALE" }) $adminTok
$p4 = Call "Patch" "$base/patients/$($pat.data.id)/" (Body @{ cedula="000-1111111-1" }) $adminTok
Check "PATCH hyphenated cedula -> 200 digits-only" (($p4.status -eq 200) -and ($p4.data.cedula -eq "00011111111")) "status=$($p4.status) cedula='$($p4.data.cedula)'"

# 6. PATCH with 10-digit cedula -> 400
$p5 = Call "Patch" "$base/patients/$($pat.data.id)/" (Body @{ cedula="000-1111111" }) $adminTok
Check "PATCH 10-digit cedula -> 400" ($p5.status -eq 400) "status=$($p5.status) detail=$($p5.detail)"

# 7. Masking: IT/CENTER_MANAGER see masked cedula, ADMIN/DOCTOR see full digits
$it = (Login "it" "Pass123!x").data.access
$cm = (Login "cm" "Pass123!x").data.access
$doc = (Login "doctor" "Pass123!x").data.access
$itCed = (Call "Get" "$base/patients/$p1Id/" $null $it).data.cedula
$cmCed = (Call "Get" "$base/patients/$p1Id/" $null $cm).data.cedula
$docCed = (Call "Get" "$base/patients/$p1Id/" $null $doc).data.cedula
$admCed = $g1.data.cedula
# Masked value is "01••••20" (8 chars, first 2 + last 2 digits, bullet-masked middle).
function IsMasked($v) { return ($v -ne "01001084920") -and ($v.Length -eq 8) -and ($v.StartsWith("01")) -and ($v.EndsWith("20")) }
Check "IT sees masked cedula" (IsMasked $itCed) "got '$itCed'"
Check "CM sees masked cedula" (IsMasked $cmCed) "got '$cmCed'"
Check "DOCTOR sees full digits-only cedula" ($docCed -eq "01001084920") "got '$docCed'"
Check "ADMIN sees full digits-only cedula" ($admCed -eq "01001084920") "got '$admCed'"

Write-Output ""
Write-Output ("Cedula verification: {0} passed, {1} failed" -f $pass, $fail)
exit $(if ($fail -gt 0) { 1 } else { 0 })
