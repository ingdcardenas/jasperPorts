# lib/JasperApi.psm1
#
# Libreria comun (PowerShell 5.1 y 7) equivalente de lib/jasper-api.sh.
# Uso en los scripts:
#   Import-Module (Join-Path (Join-Path $PSScriptRoot 'lib') 'JasperApi.psm1') -Force
#   Initialize-Jasper
#
# Notas:
#   - Sin proxy (equivale a curl --noproxy '*').
#   - Sesion: cookie JSESSIONID en el MISMO archivo y formato Netscape que la
#     version bash (.jasper-session), por lo que la sesion se comparte.
#   - La contrasena nunca se escribe en disco ni se imprime.
#   - Solo ASCII en este archivo (Windows PowerShell 5.1 lee sin BOM como ANSI).

$script:RootDir = Split-Path -Parent $PSScriptRoot
$script:DefaultUrl = 'http://10.6.206.57:8080/jasperserver'
$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

# Estado compartido (tabla por referencia, visible para los scripts).
$Jasper = @{ Root = $script:RootDir; Url = ''; CookieJar = ''; HostsFile = ''; ReportesDir = ''; BackupsDir = '' }

# Codigos de salida (mismos que la version bash).
$JasperErr = @{ Usage = 2; Http = 10; Login = 11; NotFound = 12; SessionExpired = 13; Backup = 14; Xml = 15; Unexpected = 20 }

try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }

function Write-JasperLog { param([string]$Msg) [Console]::Error.WriteLine("[jasper] $Msg") }
function Write-JasperOk  { param([string]$Msg) [Console]::Error.WriteLine("[OK]     $Msg") }
function Write-JasperErr { param([string]$Msg) [Console]::Error.WriteLine("[ERROR]  $Msg") }

function Import-JasperEnv {
    # Equivale a "source .env": lineas VAR=valor (opcional "export "), comillas simples/dobles.
    $f = Join-Path $script:RootDir '.env'
    if (-not (Test-Path -LiteralPath $f)) { return }
    foreach ($line in [IO.File]::ReadAllLines($f)) {
        $m = [regex]::Match($line, '^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)=(.*)$')
        if (-not $m.Success) { continue }
        $v = $m.Groups[2].Value.Trim()
        if ($v.Length -ge 2 -and (($v[0] -eq '"' -and $v[$v.Length - 1] -eq '"') -or ($v[0] -eq "'" -and $v[$v.Length - 1] -eq "'"))) {
            $v = $v.Substring(1, $v.Length - 2)
        } else {
            $i = $v.IndexOf(' #'); if ($i -ge 0) { $v = $v.Substring(0, $i).TrimEnd() }
        }
        [Environment]::SetEnvironmentVariable($m.Groups[1].Value, $v, 'Process')
    }
}

function Get-JasperHosts {
    if (Test-Path -LiteralPath $Jasper.HostsFile) {
        return @([IO.File]::ReadAllLines($Jasper.HostsFile) | Where-Object { $_ -ne '' })
    }
    return @()
}
function Get-JasperLastHost { $h = @(Get-JasperHosts); if ($h.Count -gt 0) { return $h[0] }; return '' }

function Set-JasperOwnerOnly {
    # Equivale a chmod 600 (mejor esfuerzo).
    param([string]$Path)
    try {
        if ($env:OS -eq 'Windows_NT') {
            & icacls.exe $Path /inheritance:r /grant:r "$($env:USERNAME):(R,W)" 2>&1 | Out-Null
        } else {
            & chmod 600 $Path 2>&1 | Out-Null
        }
    } catch { }
}

function Add-JasperHost {
    param([string]$Url)
    if (-not $Url) { return }
    $lines = @($Url) + @(Get-JasperHosts | Where-Object { $_ -cne $Url })
    [IO.File]::WriteAllText($Jasper.HostsFile, (($lines -join "`n") + "`n"), $script:Utf8NoBom)
    Set-JasperOwnerOnly $Jasper.HostsFile
}

function Initialize-Jasper {
    Import-JasperEnv
    $e = { param($n, $d) $v = [Environment]::GetEnvironmentVariable($n); if ($v) { $v } else { $d } }
    $Jasper.CookieJar   = & $e 'JASPER_COOKIE_JAR'  (Join-Path $script:RootDir '.jasper-session')
    $Jasper.HostsFile   = & $e 'JASPER_HOSTS_FILE'  (Join-Path $script:RootDir '.jasper-hosts')
    $Jasper.ReportesDir = & $e 'JASPER_REPORTES_DIR' (Join-Path $script:RootDir 'reportes')
    $Jasper.BackupsDir  = & $e 'JASPER_BACKUPS_DIR'  (Join-Path $script:RootDir 'backups')
    $u = & $e 'JASPER_URL' ''
    if (-not $u) { $u = Get-JasperLastHost }
    if (-not $u) { $u = $script:DefaultUrl }
    $Jasper.Url = $u.TrimEnd('/')
}

# ---------------------------------------------------------------------------
# Cookie jar (formato Netscape, compatible con curl)
# ---------------------------------------------------------------------------
function Read-JasperCookie {
    if (-not (Test-Path -LiteralPath $Jasper.CookieJar)) { return $null }
    foreach ($line in [IO.File]::ReadAllLines($Jasper.CookieJar)) {
        $l = $line.TrimEnd("`r", "`n")
        if (-not $l.Trim()) { continue }
        if ($l.StartsWith('#HttpOnly_')) { $l = $l.Substring(10) } elseif ($l.StartsWith('#')) { continue }
        $f = $l -split "`t"
        if ($f.Count -ge 7 -and $f[5] -eq 'JSESSIONID') {
            return [pscustomobject]@{ Domain = $f[0]; Path = $f[2]; Value = $f[6] }
        }
    }
    return $null
}

function Save-JasperCookie {
    param([string]$Domain, [string]$Path, [string]$Value)
    if (-not (Test-Path -LiteralPath $Jasper.CookieJar)) { [IO.File]::WriteAllText($Jasper.CookieJar, '', $script:Utf8NoBom) }
    Set-JasperOwnerOnly $Jasper.CookieJar
    $txt = "# Netscape HTTP Cookie File`n#HttpOnly_$Domain`tFALSE`t$Path`tFALSE`t0`tJSESSIONID`t$Value`n"
    [IO.File]::WriteAllText($Jasper.CookieJar, $txt, $script:Utf8NoBom)
}

function Clear-JasperCookieJar {
    [IO.File]::WriteAllText($Jasper.CookieJar, '', $script:Utf8NoBom)
    Set-JasperOwnerOnly $Jasper.CookieJar
}

# ---------------------------------------------------------------------------
# Invoke-JasperRequest: devuelve @{Status; Bytes; Text; Error}. Status 0 = fallo de red.
# ---------------------------------------------------------------------------
function Invoke-JasperRequest {
    param(
        [Parameter(Mandatory)][string]$Path,
        [string]$Method = 'GET',
        [string]$Accept = '',
        [string]$ContentType = '',
        $Body = $null,
        [int]$TimeoutSec = 60,
        [switch]$NoCookie
    )
    $url = $Path
    if ($Path -notmatch '^https?://') { $url = $Jasper.Url + $Path }
    $uri = [Uri]$url

    $sess = New-Object Microsoft.PowerShell.Commands.WebRequestSession
    $sent = $null
    if (-not $NoCookie) {
        $c = Read-JasperCookie
        if ($c) {
            $sent = $c.Value
            if ($c.Domain.TrimStart('.') -ieq $uri.Host) {
                $ck = New-Object System.Net.Cookie('JSESSIONID', $c.Value, $c.Path, $uri.Host)
                $sess.Cookies.Add($uri, $ck)
            }
        }
    }

    $p = @{ Uri = $url; Method = $Method; UseBasicParsing = $true; TimeoutSec = $TimeoutSec; MaximumRedirection = 0; ErrorAction = 'Stop'; WebSession = $sess }
    if ($Accept) { $p.Headers = @{ Accept = $Accept } }
    if ($ContentType) { $p.ContentType = $ContentType }
    if ($null -ne $Body) { $p.Body = $Body }
    if ((Get-Command Invoke-WebRequest).Parameters.ContainsKey('NoProxy')) { $p.NoProxy = $true }
    else { [System.Net.WebRequest]::DefaultWebProxy = $null }

    $status = 0; $bytes = [byte[]]@(); $err = ''
    try {
        $r = Invoke-WebRequest @p
        $status = [int]$r.StatusCode
        $ms = $r.RawContentStream
        if ($ms) { $bytes = $ms.ToArray() }
    } catch {
        $ex = $_.Exception
        $resp = $null
        if ($ex.PSObject.Properties['Response']) { $resp = $ex.Response }
        if ($resp) {
            $status = [int]$resp.StatusCode
            $body = ''
            if ($_.ErrorDetails -and $_.ErrorDetails.Message) { $body = $_.ErrorDetails.Message }
            else {
                try { $sr = New-Object IO.StreamReader($resp.GetResponseStream()); $body = $sr.ReadToEnd(); $sr.Close() } catch { }
            }
            $bytes = $script:Utf8NoBom.GetBytes($body)
        } elseif ($ex.Message -match 'maximum redirection') {
            $status = 302
        } else {
            $err = $ex.Message
        }
    }

    if (-not $NoCookie -and $status -ne 0) {
        $now = $sess.Cookies.GetCookies($uri) | Where-Object { $_.Name -eq 'JSESSIONID' } | Select-Object -First 1
        if ($now -and $now.Value -ne $sent) {
            $pth = $now.Path; if (-not $pth) { $pth = '/' }
            Save-JasperCookie -Domain $uri.Host -Path $pth -Value $now.Value
        }
    }
    return [pscustomobject]@{ Status = $status; Bytes = $bytes; Text = $script:Utf8NoBom.GetString($bytes); Error = $err }
}

function ConvertTo-JasperEncodedUri {
    param([string]$Uri)
    return (($Uri -split '/' | ForEach-Object { [Uri]::EscapeDataString($_) }) -join '/')
}

function ConvertTo-JasperUri {
    param([string]$Uri)
    $u = $Uri
    if (-not $u.StartsWith('/')) { $u = "/$u" }
    if ($u -ne '/') { $u = $u.TrimEnd('/') }
    return $u
}

function ConvertTo-JasperSafePath {
    # Igual que jasper_sanitize_path: segmentos a [A-Za-z0-9._-], sin acentos, bloquea "..".
    param([string]$Uri)
    $out = @()
    foreach ($seg in ($Uri -split '/')) {
        if (-not $seg -or $seg -eq '.' -or $seg -eq '..') { continue }
        $s = $seg.Replace([string][char]0x00F1, 'n').Replace([string][char]0x00D1, 'N')
        $s = $s.Normalize([Text.NormalizationForm]::FormKD)
        $sb = New-Object System.Text.StringBuilder
        foreach ($ch in $s.ToCharArray()) {
            if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch) -ne [Globalization.UnicodeCategory]::NonSpacingMark) { [void]$sb.Append($ch) }
        }
        $s = ([regex]::Replace($sb.ToString(), '[^A-Za-z0-9._-]', '_')).Trim('_')
        if ($s) { $out += $s }
    }
    return ($out -join '/')
}

# ---------------------------------------------------------------------------
# Alcance y sesion
# ---------------------------------------------------------------------------
function Test-JasperReachable {
    # Devuelve @{Code; Info}. Sin cookie: no altera la sesion.
    $r = Invoke-JasperRequest -Path '/rest_v2/serverInfo' -Accept 'application/json' -TimeoutSec 15 -NoCookie
    if ($r.Status -eq 0) {
        Write-JasperErr "No se pudo contactar a $($Jasper.Url) ($($r.Error))."
        return [pscustomobject]@{ Code = $JasperErr.Http; Info = '' }
    }
    if ($r.Status -ne 200) {
        Write-JasperErr "serverInfo respondio HTTP $($r.Status)."
        return [pscustomobject]@{ Code = $JasperErr.Http; Info = '' }
    }
    return [pscustomobject]@{ Code = 0; Info = $r.Text }
}

function Test-JasperSession {
    if (-not (Test-Path -LiteralPath $Jasper.CookieJar)) { return $false }
    if ((Get-Item -LiteralPath $Jasper.CookieJar).Length -eq 0) { return $false }
    $r = Invoke-JasperRequest -Path '/rest_v2/resources?limit=1' -Accept 'application/json' -TimeoutSec 15
    return ($r.Status -eq 200 -or $r.Status -eq 204)
}

function Assert-JasperSession {
    # Devuelve 0 si hay sesion valida; si no, imprime el error y devuelve 11.
    if (Test-JasperSession) { return 0 }
    Write-JasperErr "No hay sesion valida en $($Jasper.CookieJar) (servidor $($Jasper.Url))."
    Write-JasperErr "Ejecuta '.\login.ps1' primero y reintenta."
    return $JasperErr.Login
}

function Test-JasperSessionExpired {
    # $true (con mensaje) si el estado HTTP es 401.
    param([int]$Status)
    if ($Status -eq 401) {
        Write-JasperErr 'Sesion expirada o invalida (HTTP 401). Ejecuta .\login.ps1 para renovarla.'
        return $true
    }
    return $false
}

function ConvertFrom-JasperSecure {
    param([System.Security.SecureString]$Secure)
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}

function Invoke-JasperLogin {
    param([string]$User = '')
    if (-not $User) { $User = $env:JASPER_USER }
    $redirected = [Console]::IsInputRedirected
    if (-not $User) { $User = Read-Host 'Usuario de Jasper' }
    if (-not $User) { Write-JasperErr 'No se indico usuario.'; return $JasperErr.Login }

    $plain = $env:JASPER_PASSWORD
    if (-not $plain) {
        if ($redirected) { $plain = Read-Host "Password de $User" }
        else { $plain = ConvertFrom-JasperSecure (Read-Host "Password de $User" -AsSecureString) }
    }
    if (-not $plain) { Write-JasperErr 'No se indico contrasena.'; return $JasperErr.Login }

    $dir = Split-Path -Parent $Jasper.CookieJar
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    Clear-JasperCookieJar

    $body = 'j_username=' + [Uri]::EscapeDataString($User) + '&j_password=' + [Uri]::EscapeDataString($plain)
    $plain = $null; $body2 = $body; $body = $null
    Remove-Item Env:JASPER_PASSWORD -ErrorAction SilentlyContinue

    # Se hace la peticion sin cookie previa y se captura JSESSIONID de la respuesta.
    $uri = [Uri]($Jasper.Url + '/rest_v2/login')
    $sess = New-Object Microsoft.PowerShell.Commands.WebRequestSession
    $p = @{ Uri = $uri; Method = 'POST'; Body = $body2; ContentType = 'application/x-www-form-urlencoded'; UseBasicParsing = $true; TimeoutSec = 60; MaximumRedirection = 0; ErrorAction = 'Stop'; WebSession = $sess }
    if ((Get-Command Invoke-WebRequest).Parameters.ContainsKey('NoProxy')) { $p.NoProxy = $true }
    else { [System.Net.WebRequest]::DefaultWebProxy = $null }
    $status = 0
    try { $r = Invoke-WebRequest @p; $status = [int]$r.StatusCode }
    catch {
        $ex = $_.Exception
        if ($ex.PSObject.Properties['Response'] -and $ex.Response) { $status = [int]$ex.Response.StatusCode }
        elseif ($ex.Message -match 'maximum redirection') { $status = 302 }
    }
    $body2 = $null

    $ck = $sess.Cookies.GetCookies($uri) | Where-Object { $_.Name -eq 'JSESSIONID' } | Select-Object -First 1
    if ($status -ne 200 -or -not $ck) {
        Write-JasperErr "Login fallido (HTTP $status). Revisar usuario/contrasena."
        Clear-JasperCookieJar
        return $JasperErr.Login
    }
    $pth = $ck.Path; if (-not $pth) { $pth = '/' }
    Save-JasperCookie -Domain $uri.Host -Path $pth -Value $ck.Value
    Write-JasperOk "Login exitoso como '$User'."
    return 0
}

function Invoke-JasperLogout {
    if (Test-Path -LiteralPath $Jasper.CookieJar) {
        # Jasper no documenta /logout REST; se invoca el de la webapp (mejor esfuerzo).
        try { Invoke-JasperRequest -Path '/logout.html' -TimeoutSec 10 | Out-Null } catch { }
        Remove-Item -LiteralPath $Jasper.CookieJar -Force
        Write-JasperLog "Sesion cerrada y cookie eliminada ($($Jasper.CookieJar))."
    } else {
        Write-JasperLog "No habia cookie de sesion en $($Jasper.CookieJar)."
    }
}

# ---------------------------------------------------------------------------
# XML / reportUnit
# ---------------------------------------------------------------------------
function Test-JasperXml {
    # Bien formado (sin resolver DTD externos). Acepta ruta de archivo.
    param([string]$Path)
    try {
        $bytes = [IO.File]::ReadAllBytes($Path)
        $ms = New-Object IO.MemoryStream(, $bytes)
        $rs = New-Object System.Xml.XmlReaderSettings
        $rs.DtdProcessing = [System.Xml.DtdProcessing]::Ignore
        $rs.XmlResolver = $null
        $rd = [System.Xml.XmlReader]::Create($ms, $rs)
        while ($rd.Read()) { }
        $rd.Close()
        return $true
    } catch {
        [Console]::Error.WriteLine($_.Exception.Message)
        return $false
    }
}

function Get-JasperReportUnit {
    # Descarga el descriptor JSON a $OutFile. Devuelve 0 o un codigo de error.
    param([string]$Uri, [string]$OutFile)
    $u = ConvertTo-JasperUri $Uri
    $enc = ConvertTo-JasperEncodedUri $u
    $r = Invoke-JasperRequest -Path "/rest_v2/resources$enc" -Accept 'application/repository.reportUnit+json' -TimeoutSec 60
    if (Test-JasperSessionExpired $r.Status) { return $JasperErr.SessionExpired }
    switch ($r.Status) {
        200 { [IO.File]::WriteAllBytes($OutFile, $r.Bytes); return 0 }
        404 { Write-JasperErr "No existe el recurso $u (HTTP 404)."; return $JasperErr.NotFound }
        default { Write-JasperErr "GET descriptor de $u respondio HTTP $($r.Status)."; return $JasperErr.Http }
    }
}

function Get-JasperJrxmlUri {
    # URI del jrxml principal (referencia o inline). Vacio si no se halla.
    param([string]$DescriptorFile)
    $d = [IO.File]::ReadAllText($DescriptorFile, $script:Utf8NoBom) | ConvertFrom-Json
    $j = $d.jrxml
    if ($j -and $j.jrxmlFileReference -and $j.jrxmlFileReference.uri) { return [string]$j.jrxmlFileReference.uri }
    if ($j -and $j.jrxmlFile -and $j.jrxmlFile.uri) { return [string]$j.jrxmlFile.uri }
    return ''
}

Export-ModuleMember -Variable Jasper, JasperErr -Function Write-JasperLog, Write-JasperOk, Write-JasperErr, Get-JasperHosts, Get-JasperLastHost, Add-JasperHost, Initialize-Jasper, Invoke-JasperRequest, ConvertTo-JasperEncodedUri, ConvertTo-JasperUri, ConvertTo-JasperSafePath, Test-JasperReachable, Test-JasperSession, Assert-JasperSession, Test-JasperSessionExpired, Invoke-JasperLogin, Invoke-JasperLogout, Test-JasperXml, Get-JasperReportUnit, Get-JasperJrxmlUri, Set-JasperOwnerOnly, Clear-JasperCookieJar
