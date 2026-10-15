<#
===============================================================================
  LAÇADOR - Sistema de Gerenciamento de Tokens
  Lacador.Motor.psm1 - motor: catálogo, verificação, instalação e reparo
  Compatível com o Windows PowerShell 5.1 (o que já vem no Windows 10/11).
  Criado por 3S Leon, S2 Dalssasso - ATIC - Base Aérea de Canoas
===============================================================================
#>
Set-StrictMode -Off

# No Windows PowerShell 5.1, o ConvertTo-Json às vezes grava uma lista como { "value": [...], "Count": n }.
# Tirar o dado de tipo extra de System.Array evita isso (a propriedade .Count continua funcionando).
if ($PSVersionTable.PSVersion.Major -lt 6) {
    try { Remove-TypeData -TypeName System.Array -ErrorAction Stop } catch { }
}

$script:VersaoLacador    = '1.2.0'
$script:PastaPrograma    = $PSScriptRoot
$script:MarcadorWmic     = 'CORRECAO-WMIC'
$script:NomeTarefaAgente = 'Lacador-Agente'
$script:ChaveLacador     = 'SOFTWARE\Lacador'
$script:NomeXpiLocal     = 'assinador_digital_comaer.xpi'
$script:CreditoLacador   = 'Criado por 3S Leon, S2 Dalssasso'
$script:ChaveAssinador   = '{6CC54A28-5953-482E-9A6B-0A570FCAD6E8}_is1'

# Bloco que substitui as duas linhas do WMIC nos .bat do assinador (linguagem de .bat).
# Em string PowerShell com aspas simples, '' vira uma aspa simples.
$script:BlocoWmic = @(
    'rem CORRECAO-WMIC (25/09/2026): o Windows 11 removeu o WMIC. A memoria livre agora vem do PowerShell;',
    'rem se o PowerShell falhar, usa um valor padrao. O arquivo original foi salvo como .bat.original',
    'set FREEMEMORY=',
    'for /f "delims=" %%a in (''%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -NonInteractive -Command "(Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory" 2^>nul'') do set FREEMEMORY=%%a',
    'if not defined FREEMEMORY set FREEMEMORY=1048577'
)

#region Infraestrutura ---------------------------------------------------------

function Get-LacadorVersao { return $script:VersaoLacador }
function Get-LacadorNomeTarefa { return $script:NomeTarefaAgente }
function Test-LacadorWindows { return ($env:OS -eq 'Windows_NT') }

function Read-LacadorJson {
    param([string]$Caminho)
    $txt = [IO.File]::ReadAllText($Caminho, [Text.Encoding]::UTF8)
    return ($txt | ConvertFrom-Json)
}

function Write-LacadorJson {
    # Grava de forma atômica (arquivo temporário + troca), para ninguém ler um arquivo pela metade.
    param([string]$Caminho, $Objeto)
    $json = ConvertTo-Json -InputObject $Objeto -Depth 12
    $tmp = '{0}.{1}.tmp' -f $Caminho, ([guid]::NewGuid().ToString('N').Substring(0, 6))
    [IO.File]::WriteAllText($tmp, $json, (New-Object System.Text.UTF8Encoding($false)))
    try {
        if (Test-Path -LiteralPath $Caminho) { [IO.File]::Delete($Caminho) }
        [IO.File]::Move($tmp, $Caminho)
    } catch {
        Start-Sleep -Milliseconds 120
        try {
            if (Test-Path -LiteralPath $Caminho) { [IO.File]::Delete($Caminho) }
            [IO.File]::Move($tmp, $Caminho)
        } catch {
            Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
            throw
        }
    }
}

function Get-LacadorProp {
    # Lê uma propriedade pelo nome, tanto de hashtable quanto de objeto vindo de JSON.
    param($Objeto, [string]$Nome)
    if ($null -eq $Objeto) { return $null }
    if ($Objeto -is [System.Collections.IDictionary]) { return $Objeto[$Nome] }
    $p = $Objeto.PSObject.Properties[$Nome]
    if ($p) { return $p.Value }
    return $null
}

function Merge-LacadorObjeto {
    param($Base, $Extra)
    if ($null -eq $Extra) { return }
    foreach ($p in $Extra.PSObject.Properties) {
        $atual = $Base.PSObject.Properties[$p.Name]
        if ($atual -and ($atual.Value -is [pscustomobject]) -and ($p.Value -is [pscustomobject])) {
            Merge-LacadorObjeto $atual.Value $p.Value
        } elseif ($atual) {
            $atual.Value = $p.Value
        } else {
            $Base | Add-Member -NotePropertyName $p.Name -NotePropertyValue $p.Value
        }
    }
}

function Get-LacadorConfig {
    $padrao = @'
{
  "organizacao": "Base Aérea de Canoas",
  "suporte": { "nome": "ATIC", "contato": "" },
  "pastaPacotes": "",
  "proxy": { "servidor": "proxy.exemplo.intranet", "porta": 0, "excecoes": "<local>" },
  "sites": {
    "sigadaer": "http://sigadaer.exemplo.intranet/",
    "siafi": "https://siafi.tesouro.gov.br/senha/public/pages/security/login.jsf",
    "compras": "https://www.gov.br/compras/pt-br"
  },
  "firefox": { "modoInstalacaoExtensao": "force_installed", "aplicarPreferenciasProcedimentoAtic": false },
  "certificados": { "avisarDiasAntes": 30 },
  "interface": { "navegador": "auto" }
}
'@ | ConvertFrom-Json
    $arq = Join-Path $script:PastaPrograma 'config.json'
    if (Test-Path -LiteralPath $arq) {
        try { Merge-LacadorObjeto $padrao (Read-LacadorJson $arq) } catch { }
    }
    # Ajustes da base sem mexer no executável: um arquivo "Lacador.config.json" ao lado do Lacador.exe.
    try {
        $exe = Get-LacadorRecipiente
        if ($exe) {
            $extra = Join-Path (Split-Path -Parent $exe) 'Lacador.config.json'
            if (Test-Path -LiteralPath $extra) { Merge-LacadorObjeto $padrao (Read-LacadorJson $extra) }
        }
    } catch { }
    return $padrao
}

function Get-LacadorCatalogo {
    return (Read-LacadorJson (Join-Path $script:PastaPrograma 'catalogo.json'))
}

function Get-LacadorRaiz { return (Split-Path -Parent $script:PastaPrograma) }

function Get-LacadorPastaPacotes {
    param($Config)
    if (-not $Config) { $Config = Get-LacadorConfig }
    if ($Config.pastaPacotes) { return [Environment]::ExpandEnvironmentVariables([string]$Config.pastaPacotes) }
    # Uma pasta "pacotes" ao lado do Lacador.exe vale antes dos instaladores guardados dentro dele.
    $exe = [string]$env:LACADOR_EXE
    if ($exe -and (Test-Path -LiteralPath $exe -PathType Leaf)) { return (Join-Path (Split-Path -Parent $exe) 'pacotes') }
    return (Join-Path (Get-LacadorRaiz) 'pacotes')
}

function Get-LacadorRecipiente {
    # O Lacador.exe, que traz o programa e os instaladores dentro (um .zip no fim do arquivo). '' se não houver.
    $c = [string]$env:LACADOR_EXE
    if ($c -and (Test-Path -LiteralPath $c -PathType Leaf)) { return $c }
    $c = Join-Path (Get-LacadorRaiz) 'Lacador.exe'
    if (Test-Path -LiteralPath $c -PathType Leaf) { return $c }
    return ''
}

$script:IndiceRecipiente = @{ caminho = ''; marca = ''; itens = @{} }
function Get-LacadorIndiceRecipiente {
    # Nome (minúsculo) -> tamanho de cada instalador guardado dentro do Lacador.exe (pasta pacotes/ do .zip embutido).
    $r = @{}
    $exe = Get-LacadorRecipiente
    if (-not $exe) { return $r }
    try {
        $it = Get-Item -LiteralPath $exe
        $marca = '{0}|{1}' -f $it.Length, $it.LastWriteTimeUtc.Ticks
        if ($script:IndiceRecipiente.caminho -eq $exe -and $script:IndiceRecipiente.marca -eq $marca) { return $script:IndiceRecipiente.itens }
        try { Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop } catch { }
        $zip = [IO.Compression.ZipFile]::OpenRead($exe)
        try {
            foreach ($e in $zip.Entries) {
                if ($e.FullName -like 'pacotes/*' -and $e.Name) { $r[$e.Name.ToLowerInvariant()] = [long]$e.Length }
            }
        } finally { $zip.Dispose() }
        $script:IndiceRecipiente = @{ caminho = $exe; marca = $marca; itens = $r }
    } catch { }
    return $r
}

function Get-LacadorOrigemPacote {
    # Onde está um instalador: na pasta de pacotes (se existir lá) ou dentro do Lacador.exe.
    param([string]$Nome, $Config)
    $nomeArq = [IO.Path]::GetFileName($Nome)
    $r = [ordered]@{ existe = $false; tamanho = 0; origem = ''; caminho = '' }
    $arq = Join-Path (Get-LacadorPastaPacotes $Config) $nomeArq
    if (Test-Path -LiteralPath $arq -PathType Leaf) {
        $r.existe = $true; $r.origem = 'pasta'; $r.caminho = $arq
        try { $r.tamanho = [long](Get-Item -LiteralPath $arq).Length } catch { }
        return $r
    }
    $ind = Get-LacadorIndiceRecipiente
    $k = $nomeArq.ToLowerInvariant()
    if ($ind.ContainsKey($k)) { $r.existe = $true; $r.origem = 'executavel'; $r.caminho = (Get-LacadorRecipiente); $r.tamanho = [long]$ind[$k] }
    return $r
}

function Copy-LacadorPacote {
    # Copia um instalador (da pasta de pacotes ou de dentro do Lacador.exe) para $Destino.
    param([string]$Nome, [string]$Destino, $Config)
    $nomeArq = [IO.Path]::GetFileName($Nome)
    $o = Get-LacadorOrigemPacote $nomeArq $Config
    if (-not $o.existe) { throw ('Instalador não encontrado: {0}' -f $nomeArq) }
    if ($o.origem -eq 'pasta') { Copy-Item -LiteralPath $o.caminho -Destination $Destino -Force; return }
    $zip = [IO.Compression.ZipFile]::OpenRead([string]$o.caminho)
    try {
        $alvo = 'pacotes/' + $nomeArq
        $ent = $null
        foreach ($e in $zip.Entries) { if ($e.FullName -ieq $alvo) { $ent = $e; break } }
        if (-not $ent) { throw ('Instalador não encontrado dentro do Lacador.exe: {0}' -f $nomeArq) }
        $entrada = $ent.Open()
        try {
            $saida = [IO.File]::Create($Destino)
            try { $entrada.CopyTo($saida) } finally { $saida.Dispose() }
        } finally { $entrada.Dispose() }
    } finally { $zip.Dispose() }
}

function Get-LacadorPastaDados {
    # Dados da máquina (fila do agente, respostas, registros). Criada pelo Instalar-Lacador.ps1.
    $base = $env:ProgramData
    if (-not $base) { $base = [IO.Path]::GetTempPath() }
    return (Join-Path $base 'Lacador')
}

function Get-LacadorPastaUsuario {
    $base = $env:LOCALAPPDATA
    if (-not $base) { $base = Join-Path ([IO.Path]::GetTempPath()) 'lacador-usuario' }
    $p = Join-Path $base 'Lacador'
    if (-not (Test-Path -LiteralPath $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null }
    return $p
}

function Expand-LacadorCaminho {
    param([string]$Caminho)
    return [Environment]::ExpandEnvironmentVariables($Caminho)
}

function Get-LacadorPlural {
    # "1 dia", "17 dias"
    param([int]$Numero, [string]$Singular, [string]$Plural)
    if ($Numero -eq 1) { return ('1 {0}' -f $Singular) }
    return ('{0} {1}' -f $Numero, $Plural)
}

function Compare-LacadorVersao {
    # -1 se A < B, 0 se iguais, 1 se A > B. Aceita "3.0.97", "1.7.17.0", "8.0.910.15"...
    param([string]$A, [string]$B)
    $pa = @([regex]::Matches([string]$A, '\d+') | ForEach-Object { [long]$_.Value })
    $pb = @([regex]::Matches([string]$B, '\d+') | ForEach-Object { [long]$_.Value })
    $n = [Math]::Max($pa.Count, $pb.Count)
    for ($i = 0; $i -lt $n; $i++) {
        $x = 0; $y = 0
        if ($i -lt $pa.Count) { $x = $pa[$i] }
        if ($i -lt $pb.Count) { $y = $pb[$i] }
        if ($x -lt $y) { return -1 }
        if ($x -gt $y) { return 1 }
    }
    return 0
}

function Open-LacadorChave {
    # Abre uma chave do registro numa "vista" específica (32 ou 64 bits). Retorna $null se não existir.
    param([string]$Raiz, [int]$Vista, [string]$Caminho, [bool]$Escrita = $false, [bool]$Criar = $false)
    $hive = [Microsoft.Win32.RegistryHive]::LocalMachine
    if ($Raiz -eq 'HKCU') { $hive = [Microsoft.Win32.RegistryHive]::CurrentUser }
    $view = [Microsoft.Win32.RegistryView]::Registry64
    if ($Vista -eq 32) { $view = [Microsoft.Win32.RegistryView]::Registry32 }
    $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey($hive, $view)
    if ($Criar) { return $base.CreateSubKey($Caminho) }
    return $base.OpenSubKey($Caminho, $Escrita)
}

function Get-LacadorValorRegistro {
    param([string]$Raiz, [int]$Vista, [string]$Caminho, [string]$Nome)
    $k = $null
    try {
        $k = Open-LacadorChave $Raiz $Vista $Caminho
        if (-not $k) { return $null }
        return $k.GetValue($Nome)
    } catch { return $null } finally { if ($k) { $k.Close() } }
}

function Get-LacadorArquiteturaPE {
    # Lê o cabeçalho de um .exe e diz se é x86 ou x64.
    param([string]$Arquivo)
    try {
        $fs = [IO.File]::Open($Arquivo, 'Open', 'Read', 'ReadWrite')
        try {
            $br = New-Object IO.BinaryReader($fs)
            $fs.Position = 0x3C
            $pe = $br.ReadInt32()
            $fs.Position = $pe + 4
            $m = $br.ReadUInt16()
            if ($m -eq 0x8664) { return 'x64' }
            if ($m -eq 0x14c) { return 'x86' }
            return ''
        } finally { $fs.Close() }
    } catch { return '' }
}

function Hide-LacadorCpf {
    param([string]$Texto)
    if (-not $Texto) { return $Texto }
    $t = $Texto -replace ':\d{6,}$', ''
    $t = $t -replace '\d{3}\.\d{3}\.\d{3}-\d{2}', '[oculto]'
    return ($t -replace '\d{11,14}', '[oculto]')
}

#endregion

#region Coleta de fatos (somente leitura) -------------------------------------

function Get-LacadorProgramas {
    $lista = New-Object System.Collections.Generic.List[object]
    $sub = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
    $relevante = 'assinador|comaer|safesign|starsign|giesecke|dxsafe|dexon|java|firefox|adobe|acrobat|epass|feitian|token|smart ?card|certisign|safenet'
    $vistos = @{}
    foreach ($f in @(@('HKLM', 64), @('HKLM', 32), @('HKCU', 64))) {
        $k = $null
        try { $k = Open-LacadorChave $f[0] $f[1] $sub } catch { }
        $origem = '{0}{1}' -f $f[0], $f[1]
        if (-not $k) { continue }
        foreach ($nome in $k.GetSubKeyNames()) {
            $s = $null
            try {
                $s = $k.OpenSubKey($nome)
                $dn = [string]$s.GetValue('DisplayName')
                if ($dn -and (('{0} {1}' -f $dn, [string]$s.GetValue('Publisher')) -match $relevante)) {
                    $id = '{0}|{1}' -f $nome, $dn
                    if (-not $vistos.ContainsKey($id)) {
                        $vistos[$id] = $true
                        $lista.Add([ordered]@{
                            nome         = $dn
                            versao       = [string]$s.GetValue('DisplayVersion')
                            fabricante   = [string]$s.GetValue('Publisher')
                            pasta        = [string]$s.GetValue('InstallLocation')
                            chave        = $nome
                            origem       = $origem
                            msi          = ([string]$s.GetValue('WindowsInstaller') -eq '1')
                            desinstalar  = [string]$s.GetValue('UninstallString')
                            silencioso   = [string]$s.GetValue('QuietUninstallString')
                        })
                    }
                }
            } catch { } finally { if ($s) { $s.Close() } }
        }
        $k.Close()
    }
    return $lista.ToArray()
}

function Get-LacadorDispositivos {
    param($Catalogo)
    $res = New-Object System.Collections.Generic.List[object]
    $vids = @($Catalogo.tokens | ForEach-Object { $_.hardware } | Where-Object { $_ })
    $padraoVid = $null
    if ($vids.Count) { $padraoVid = ($vids -join '|') }
    $devs = @()
    try {
        $devs = @(Get-PnpDevice -PresentOnly -ErrorAction Stop)
    } catch {
        try {
            $devs = @(Get-CimInstance Win32_PnPEntity -ErrorAction Stop | ForEach-Object {
                [pscustomobject]@{ FriendlyName = $_.Name; InstanceId = $_.PNPDeviceID; Class = $_.PNPClass; Status = $_.Status }
            })
        } catch { }
    }
    foreach ($d in $devs) {
        $classe = [string]$d.Class
        $id = [string]$d.InstanceId
        # Leitores, os cartões que o Windows enxerga dentro deles e os aparelhos USB dos fabricantes do catálogo
        $ehLeitor = ($classe -eq 'SmartCardReader' -or $classe -eq 'SmartCard' -or $id -like 'SWD\SCDEVICEENUM\*')
        $ehConhecido = ($padraoVid -and ($id -match $padraoVid))
        if ($id -like 'SWD\SCDEVICEENUMBUS*') { continue }
        if ($ehLeitor -or $ehConhecido) {
            $res.Add([ordered]@{ nome = [string]$d.FriendlyName; id = $id; classe = $classe; status = [string]$d.Status })
        }
    }
    return $res.ToArray()
}

function Get-LacadorCertificados {
    $res = New-Object System.Collections.Generic.List[object]
    $itens = @()
    try { $itens = @(Get-ChildItem -Path Cert:\CurrentUser\My -ErrorAction Stop) } catch { }
    foreach ($c in $itens) {
        $cn = [string]$c.Subject
        if ($cn -match 'CN=([^,]+)') { $cn = $matches[1] }
        $em = [string]$c.Issuer
        if ($em -match 'CN=([^,]+)') { $em = $matches[1] }
        $imp = [string]$c.Thumbprint
        if ($imp.Length -gt 8) { $imp = $imp.Substring($imp.Length - 8) }
        $res.Add([ordered]@{
            titular      = (Hide-LacadorCpf $cn)
            emissor      = $em
            inicio       = $c.NotBefore.ToString('s')
            fim          = $c.NotAfter.ToString('s')
            chavePrivada = [bool]$c.HasPrivateKey
            autoassinado = ($c.Subject -eq $c.Issuer)
            id           = $imp
        })
    }
    return $res.ToArray()
}

function Get-LacadorPastasAssinador {
    param($Programas)
    $cands = New-Object System.Collections.Generic.List[string]
    foreach ($p in @($Programas)) {
        if ((Get-LacadorProp $p 'chave') -eq $script:ChaveAssinador -or ([string](Get-LacadorProp $p 'nome')) -like 'Assinador Digital do COMAER*') {
            $pasta = [string](Get-LacadorProp $p 'pasta')
            if ($pasta) { $cands.Add($pasta) }
        }
    }
    foreach ($pf in @(${env:ProgramFiles(x86)}, $env:ProgramFiles, $env:ProgramW6432)) {
        if ($pf) { $cands.Add((Join-Path $pf 'Assinador Digital do COMAER')) }
    }
    if ($env:LOCALAPPDATA) {
        $cands.Add((Join-Path $env:LOCALAPPDATA 'Programs\Assinador Digital do COMAER'))
        $cands.Add((Join-Path $env:LOCALAPPDATA 'Assinador Digital do COMAER'))
    }
    $achadas = New-Object System.Collections.Generic.List[string]
    foreach ($c in $cands) {
        if ($c -and (Test-Path -LiteralPath (Join-Path $c 'assinador-ccasj.jar'))) {
            $r = $c.TrimEnd('\')
            if (-not $achadas.Contains($r)) { $achadas.Add($r) }
        }
    }
    return $achadas.ToArray()
}

function Test-LacadorUsaWmic {
    # Verdadeiro se alguma linha que NÃO é comentário chama o WMIC.
    param([string[]]$Linhas)
    return (@($Linhas | Where-Object { $_ -notmatch '^\s*(rem\b|::)' -and $_ -match 'wmic' }).Count -gt 0)
}

function Get-LacadorAssinadorFatos {
    param($Programas)
    $r = [ordered]@{ pasta = ''; jar = $false; bats = @(); ligacao64 = ''; ligacao32 = ''; manifesto = $false; atalho = $false; configUsuario = [ordered]@{ existe = $false; tokens = @() } }
    $pastas = @(Get-LacadorPastasAssinador $Programas)
    if ($pastas.Count) {
        $r.pasta = $pastas[0]
        $r.jar = $true
        $bats = New-Object System.Collections.Generic.List[object]
        foreach ($nome in 'assinador_comaer.bat', 'assinador_standalone.bat') {
            $arq = Join-Path $r.pasta $nome
            $b = [ordered]@{ nome = $nome; existe = $false; usaWmic = $false; corrigido = $false }
            if (Test-Path -LiteralPath $arq) {
                $b.existe = $true
                try {
                    $linhas = [IO.File]::ReadAllLines($arq, [Text.Encoding]::Default)
                    $b.usaWmic = (Test-LacadorUsaWmic $linhas)
                    $b.corrigido = (($linhas -join "`n") -match $script:MarcadorWmic)
                } catch { }
            }
            $bats.Add($b)
        }
        $r.bats = $bats.ToArray()
        $r.manifesto = (Test-Path -LiteralPath (Join-Path $r.pasta 'assinador_comaer.json'))
    }
    $chaveNm = 'SOFTWARE\Mozilla\NativeMessagingHosts\assinador_comaer'
    $r.ligacao64 = [string](Get-LacadorValorRegistro 'HKLM' 64 $chaveNm '')
    $r.ligacao32 = [string](Get-LacadorValorRegistro 'HKLM' 32 $chaveNm '')
    if (-not $r.ligacao64 -and -not $r.ligacao32) {
        $r.ligacao64 = [string](Get-LacadorValorRegistro 'HKCU' 64 $chaveNm '')
    }
    if ($env:PUBLIC) { $r.atalho = (Test-Path -LiteralPath (Join-Path $env:PUBLIC 'Desktop\Assinador Digital do COMAER.lnk')) }
    $cfg = Get-LacadorCaminhoConfigAssinador
    if ($cfg -and (Test-Path -LiteralPath $cfg)) {
        $r.configUsuario.existe = $true
        $toks = New-Object System.Collections.Generic.List[object]
        try {
            foreach ($l in [IO.File]::ReadAllLines($cfg, [Text.Encoding]::GetEncoding(28591))) {
                if ($l -match '^\s*token\.([^=\s]+)\s*=\s*(.+?)\s*$') { $toks.Add([ordered]@{ nome = $matches[1]; caminho = $matches[2] }) }
            }
        } catch { }
        $r.configUsuario.tokens = $toks.ToArray()
    }
    return $r
}

function Get-LacadorCaminhoConfigAssinador {
    if (-not $env:USERPROFILE) { return $null }
    return (Join-Path $env:USERPROFILE 'Assinador Digital COMAER\config.properties')
}

function Get-LacadorFirefoxInstalacoes {
    $dirs = New-Object System.Collections.Generic.List[string]
    foreach ($produto in 'Mozilla Firefox ESR', 'Mozilla Firefox', 'Firefox Developer Edition') {
        foreach ($v in 64, 32) {
            $k = $null
            try {
                $k = Open-LacadorChave 'HKLM' $v ('SOFTWARE\Mozilla\{0}' -f $produto)
                if ($k) {
                    foreach ($sub in $k.GetSubKeyNames()) {
                        $m = $k.OpenSubKey(('{0}\Main' -f $sub))
                        if ($m) { $d = [string]$m.GetValue('Install Directory'); if ($d) { $dirs.Add($d) }; $m.Close() }
                    }
                }
            } catch { } finally { if ($k) { $k.Close() } }
        }
    }
    foreach ($pf in @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramW6432)) {
        if ($pf) {
            foreach ($n in 'Mozilla Firefox', 'Mozilla Firefox ESR', 'Firefox Developer Edition') { $dirs.Add((Join-Path $pf $n)) }
        }
    }
    if ($env:LOCALAPPDATA) { $dirs.Add((Join-Path $env:LOCALAPPDATA 'Mozilla Firefox')) }
    $res = New-Object System.Collections.Generic.List[object]
    $vistos = @{}
    foreach ($d in $dirs) {
        if (-not $d) { continue }
        $chave = $d.TrimEnd('\').ToLowerInvariant()
        if ($vistos.ContainsKey($chave)) { continue }
        $vistos[$chave] = $true
        $exe = Join-Path $d 'firefox.exe'
        if (-not (Test-Path -LiteralPath $exe)) { continue }
        $canal = ''
        try {
            $cp = Join-Path $d 'defaults\pref\channel-prefs.js'
            if (Test-Path -LiteralPath $cp) {
                $t = [IO.File]::ReadAllText($cp)
                if ($t -match '"app\.update\.channel"\s*,\s*"([^"]+)"') { $canal = $matches[1] }
            }
            if (-not $canal) {
                # Reserva: o canal também aparece nas configurações de atualização da instalação.
                $us = Join-Path $d 'update-settings.ini'
                if ((Test-Path -LiteralPath $us) -and ([IO.File]::ReadAllText($us) -match 'firefox-mozilla-([a-z]+)')) { $canal = $matches[1] }
            }
        } catch { }
        $ver = ''
        try { $ver = [string](Get-Item -LiteralPath $exe).VersionInfo.ProductVersion } catch { }
        $res.Add([ordered]@{ pasta = $d.TrimEnd('\'); exe = $exe; versao = $ver; canal = $canal; edicao = (Get-LacadorEdicaoFirefox $canal $d); arquitetura = (Get-LacadorArquiteturaPE $exe) })
    }
    return $res.ToArray()
}

function Get-LacadorEdicaoFirefox {
    # developer (Developer Edition, padrão da base), esr (reserva), comum, beta, nightly
    param([string]$Canal, [string]$Pasta)
    switch ($Canal) {
        'esr' { return 'esr' }
        'aurora' { return 'developer' }
        'release' { return 'comum' }
        'beta' { return 'beta' }
        'nightly' { return 'nightly' }
    }
    if ($Pasta -match 'Developer') { return 'developer' }
    if ($Pasta -match 'ESR') { return 'esr' }
    if ($Pasta -match 'Nightly') { return 'nightly' }
    return 'comum'
}

function Get-LacadorEdicaoDe {
    # A edição de uma instalação de Firefox (os fatos antigos não tinham o campo "edicao").
    param($Instalacao)
    $e = [string](Get-LacadorProp $Instalacao 'edicao')
    if ($e) { return $e }
    return (Get-LacadorEdicaoFirefox ([string]$Instalacao.canal) ([string]$Instalacao.pasta))
}

function Get-LacadorNomeEdicao {
    param([string]$Edicao)
    switch ($Edicao) {
        'developer' { return 'Firefox Developer Edition' }
        'esr' { return 'Firefox ESR' }
        'beta' { return 'Firefox Beta' }
        'nightly' { return 'Firefox Nightly' }
    }
    return 'Firefox'
}

function Get-LacadorIdBotaoExtensao {
    # Nome do botão da extensão na barra do Firefox (regra do próprio Firefox: minúsculas, o resto vira "_").
    param([string]$ExtensaoId)
    return ((($ExtensaoId.ToLowerInvariant()) -replace '[^a-z0-9_-]', '_') + '-browser-action')
}

function Get-LacadorBarraFirefox {
    # Lê, do prefs.js de um perfil, onde ficam os botões da barra do Firefox. $null se o Firefox nunca salvou.
    param([string]$PastaPerfil)
    $prefs = Join-Path $PastaPerfil 'prefs.js'
    if (-not (Test-Path -LiteralPath $prefs)) { return $null }
    $txt = [IO.File]::ReadAllText($prefs, [Text.Encoding]::UTF8)
    $m = [regex]::Match($txt, 'user_pref\("browser\.uiCustomization\.state",\s*"((?:[^"\\]|\\.)*)"\);')
    if (-not $m.Success) { return $null }
    $json = $m.Groups[1].Value -replace '\\(.)', '$1'
    return ($json | ConvertFrom-Json)
}

function Test-LacadorExtensaoFixada {
    # Verdadeiro: o botão está numa barra visível. Falso: está escondido no menu de extensões. $null: não dá para saber.
    param($Barra, [string]$IdBotao)
    if (-not $Barra -or -not $Barra.placements) { return $null }
    foreach ($p in $Barra.placements.PSObject.Properties) {
        if ($p.Name -in 'unified-extensions-area', 'widget-overflow-fixed-list') { continue }
        if (@($p.Value) -contains $IdBotao) { return $true }
    }
    return $false
}

function Get-LacadorPoliticaFirefox {
    # Lê a política ExtensionSettings do Firefox (registro e policies.json) para a extensão do assinador.
    param([string]$ExtensaoId, $Instalacoes)
    $r = [ordered]@{ origem = ''; modo = ''; url = ''; assinaturaFraca = $false; arquivoExiste = $false; prefsAtic = $false; gravadaEm = '' }
    try { $r.gravadaEm = [string](Get-LacadorValorRegistro 'HKLM' 64 $script:ChaveLacador 'ExtensaoPoliticaEm') } catch { }
    $bruto = $null
    try {
        $v = Get-LacadorValorRegistro 'HKLM' 64 'SOFTWARE\Policies\Mozilla\Firefox' 'ExtensionSettings'
        if ($v) { $bruto = (@($v) -join "`n"); $r.origem = 'registro' }
    } catch { }
    $entrada = $null
    if ($bruto) {
        try { $entrada = Get-LacadorProp ($bruto | ConvertFrom-Json) $ExtensaoId } catch { }
    }
    if (-not $entrada) {
        foreach ($i in @($Instalacoes)) {
            $pj = Join-Path ([string](Get-LacadorProp $i 'pasta')) 'distribution\policies.json'
            if (Test-Path -LiteralPath $pj) {
                try {
                    $pol = Read-LacadorJson $pj
                    $entrada = Get-LacadorProp (Get-LacadorProp $pol.policies 'ExtensionSettings') $ExtensaoId
                    if ($entrada) { $r.origem = 'policies.json'; break }
                } catch { }
            }
        }
    }
    if ($entrada) {
        $r.modo = [string]$entrada.installation_mode
        $r.url = [string]$entrada.install_url
        $r.assinaturaFraca = [bool]$entrada.temporarily_allow_weak_signatures
        if ($r.url -match '^file:///(.+)$') {
            $local = [Uri]::UnescapeDataString($matches[1]) -replace '/', '\'
            $r.arquivoExiste = (Test-Path -LiteralPath $local)
            # Versões antigas do Laçador não guardavam a data: a cópia local da extensão é gravada junto com a política.
            if (-not $r.gravadaEm -and $r.arquivoExiste) { try { $r.gravadaEm = (Get-Item -LiteralPath $local).LastWriteTime.ToString('s') } catch { } }
        } elseif ($r.url) { $r.arquivoExiste = $true }
    } else { $r.origem = '' }
    try {
        $pv = Get-LacadorValorRegistro 'HKLM' 64 'SOFTWARE\Policies\Mozilla\Firefox' 'Preferences'
        if ($pv) {
            $po = (@($pv) -join "`n") | ConvertFrom-Json
            $sig = Get-LacadorProp $po 'xpinstall.signatures.required'
            if ($sig -and ($sig.Value -eq $false)) { $r.prefsAtic = $true }
        }
    } catch { }
    return $r
}

function Get-LacadorPastasPerfis {
    # Pastas dos perfis do Firefox deste usuário: as da pasta Profiles e as de outro lugar citadas no profiles.ini.
    $res = New-Object System.Collections.Generic.List[string]
    if (-not $env:APPDATA) { return $res.ToArray() }
    $raiz = Join-Path $env:APPDATA 'Mozilla\Firefox'
    $pastaPerfis = Join-Path $raiz 'Profiles'
    if (Test-Path -LiteralPath $pastaPerfis) {
        foreach ($pf in @(Get-ChildItem -LiteralPath $pastaPerfis -Directory -ErrorAction SilentlyContinue)) { $res.Add($pf.FullName) }
    }
    $ini = Join-Path $raiz 'profiles.ini'
    if (Test-Path -LiteralPath $ini) {
        try {
            $relativo = $true
            foreach ($l in [IO.File]::ReadAllLines($ini)) {
                if ($l -match '^\[') { $relativo = $true }
                elseif ($l -match '^IsRelative=0') { $relativo = $false }
                elseif ($l -match '^Path=(.+)$' -and -not $relativo) {
                    $p = $matches[1].Trim() -replace '/', '\'
                    if ((Test-Path -LiteralPath $p) -and -not $res.Contains($p)) { $res.Add($p) }
                }
            }
        } catch { }
    }
    return $res.ToArray()
}

function Get-LacadorPerfisFirefox {
    param([string]$ExtensaoId)
    $res = New-Object System.Collections.Generic.List[object]
    if (-not $env:APPDATA) { return $res.ToArray() }
    $raiz = Join-Path $env:APPDATA 'Mozilla\Firefox'
    $emUso = @()
    $ini = Join-Path $raiz 'installs.ini'
    if (Test-Path -LiteralPath $ini) {
        try {
            $emUso = @([IO.File]::ReadAllLines($ini) | Where-Object { $_ -match '^Default=(.+)$' } | ForEach-Object { (Split-Path -Leaf (($_ -replace '^Default=', '').Trim() -replace '/', '\')) })
        } catch { }
    }
    $idBotao = Get-LacadorIdBotaoExtensao $ExtensaoId
    foreach ($pasta in @(Get-LacadorPastasPerfis)) {
        $nome = Split-Path -Leaf $pasta
        $edicao = 'comum'
        if ($nome -match 'dev-edition') { $edicao = 'developer' } elseif ($nome -match 'esr') { $edicao = 'esr' }
        $p = [ordered]@{ nome = $nome; pasta = $pasta; edicao = $edicao; emUso = ($emUso -contains $nome); aberto = $false; atualizadoEm = ''; extensao = $null; fixada = $null }
        $ext = Join-Path $pasta 'extensions.json'
        if (Test-Path -LiteralPath $ext) {
            $p.aberto = $true
            try { $p.atualizadoEm = (Get-Item -LiteralPath $ext).LastWriteTime.ToString('s') } catch { }
            try {
                $j = [IO.File]::ReadAllText($ext, [Text.Encoding]::UTF8) | ConvertFrom-Json
                $a = @($j.addons | Where-Object { $_.id -eq $ExtensaoId }) | Select-Object -First 1
                if ($a) { $p.extensao = [ordered]@{ versao = [string]$a.version; ativa = [bool]$a.active; bloqueada = [bool]$a.appDisabled; desativada = [bool]$a.userDisabled } }
            } catch { }
        }
        try { $p.fixada = Test-LacadorExtensaoFixada (Get-LacadorBarraFirefox $pasta) $idBotao } catch { $p.fixada = $null }
        $res.Add($p)
    }
    return $res.ToArray()
}

function Get-LacadorJavaFatos {
    $r = [ordered]@{ jres = @(); jnlpComando = ''; jnlpEscolhaUsuario = ''; atualizacaoDesativada = $false }
    $jres = New-Object System.Collections.Generic.List[object]
    foreach ($v in 32, 64) {
        $k = $null
        try {
            $k = Open-LacadorChave 'HKLM' $v 'SOFTWARE\JavaSoft\Java Runtime Environment'
            if ($k) {
                foreach ($sub in $k.GetSubKeyNames()) {
                    if ($sub -notmatch '^\d+\.\d+\.\d+') { continue }
                    $s = $k.OpenSubKey($sub)
                    $home2 = [string]$s.GetValue('JavaHome')
                    $s.Close()
                    $arqBits = 'x64'
                    if ($v -eq 32 -and [Environment]::Is64BitOperatingSystem) { $arqBits = 'x86' }
                    if (-not [Environment]::Is64BitOperatingSystem) { $arqBits = 'x86' }
                    $ja = $false
                    if ($home2) { $ja = (Test-Path -LiteralPath (Join-Path $home2 'bin\javaws.exe')) }
                    $chaveU = '{0}|{1}' -f $sub, $home2
                    if (-not @($jres | Where-Object { ('{0}|{1}' -f $_.versao, $_.pasta) -eq $chaveU }).Count) {
                        $jres.Add([ordered]@{ versao = $sub; pasta = $home2; arquitetura = $arqBits; javaws = $ja })
                    }
                }
            }
        } catch { } finally { if ($k) { $k.Close() } }
    }
    $r.jres = $jres.ToArray()
    $r.jnlpComando = [string](Get-LacadorValorRegistro 'HKLM' 64 'SOFTWARE\Classes\JNLPFile\shell\open\command' '')
    $r.jnlpEscolhaUsuario = [string](Get-LacadorValorRegistro 'HKCU' 64 'Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.jnlp\UserChoice' 'ProgId')
    $pol = Get-LacadorValorRegistro 'HKLM' 32 'SOFTWARE\JavaSoft\Java Update\Policy' 'EnableJavaUpdate'
    $r.atualizacaoDesativada = ($null -ne $pol -and [int]$pol -eq 0)
    return $r
}

function Get-LacadorProxyFatos {
    $r = [ordered]@{ ativo = $false; servidor = ''; pac = ''; excecoes = '' }
    $c = 'Software\Microsoft\Windows\CurrentVersion\Internet Settings'
    $en = Get-LacadorValorRegistro 'HKCU' 64 $c 'ProxyEnable'
    $r.ativo = ($null -ne $en -and [int]$en -eq 1)
    $r.servidor = [string](Get-LacadorValorRegistro 'HKCU' 64 $c 'ProxyServer')
    $r.pac = [string](Get-LacadorValorRegistro 'HKCU' 64 $c 'AutoConfigURL')
    $r.excecoes = [string](Get-LacadorValorRegistro 'HKCU' 64 $c 'ProxyOverride')
    return $r
}

function Get-LacadorNavegadores {
    $r = [ordered]@{ edge = ''; chrome = '' }
    foreach ($pf in @(${env:ProgramFiles(x86)}, $env:ProgramFiles, $env:ProgramW6432)) {
        if (-not $pf) { continue }
        $e = Join-Path $pf 'Microsoft\Edge\Application\msedge.exe'
        if (-not $r.edge -and (Test-Path -LiteralPath $e)) { $r.edge = $e }
        $c = Join-Path $pf 'Google\Chrome\Application\chrome.exe'
        if (-not $r.chrome -and (Test-Path -LiteralPath $c)) { $r.chrome = $c }
    }
    if (-not $r.chrome -and $env:LOCALAPPDATA) {
        $c = Join-Path $env:LOCALAPPDATA 'Google\Chrome\Application\chrome.exe'
        if (Test-Path -LiteralPath $c) { $r.chrome = $c }
    }
    return $r
}

function Get-LacadorAgenteFatos {
    $r = [ordered]@{ tarefa = $false; instalado = $false; pasta = ''; versao = '' }
    try {
        $null = & schtasks.exe /Query /TN ('\{0}' -f $script:NomeTarefaAgente) 2>$null
        $r.tarefa = ($LASTEXITCODE -eq 0)
    } catch { }
    $p = [string](Get-LacadorValorRegistro 'HKLM' 64 $script:ChaveLacador 'Pasta')
    if ($p) { $r.pasta = $p; $r.instalado = (Test-Path -LiteralPath (Join-Path $p 'programa\Lacador-Agente.ps1')); $r.versao = [string](Get-LacadorValorRegistro 'HKLM' 64 $script:ChaveLacador 'Versao') }
    return $r
}

function Format-LacadorNome {
    # "IVAN LOPES DA SILVA" -> "Ivan Lopes da Silva"; postos e siglas curtas ("3S", "BMB") ficam como estão.
    param([string]$Nome)
    if (-not $Nome) { return '' }
    $Nome = ($Nome -replace '[._]', ' ' -replace '\s+', ' ').Trim()
    $cultura = [Globalization.CultureInfo]::GetCultureInfo('pt-BR')
    $palavras = foreach ($w in ($Nome -split ' ')) {
        if ($w -cmatch '^(DA|DE|DO|DAS|DOS|E)$') { $w.ToLowerInvariant() }
        elseif ($w -cmatch '^[A-ZÀ-Ý]{4,}$' -or $w -cmatch '^[a-zà-ý]{2,}$') { $cultura.TextInfo.ToTitleCase($w.ToLowerInvariant()) }
        else { $w }
    }
    return ($palavras -join ' ')
}

function Get-LacadorNomeUsuario {
    # Nome de exibição de quem está usando o Windows (o mesmo da tela de entrada). Sem rede: não consulta o domínio.
    $sam = [string]$env:USERNAME
    $nome = ''
    try {
        $base = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\LogonUI'
        $k = Open-LacadorChave 'HKLM' 64 ($base + '\SessionData')
        if ($k) {
            try {
                foreach ($s in $k.GetSubKeyNames()) {
                    $x = $k.OpenSubKey($s)
                    if (-not $x) { continue }
                    $u = [string]$x.GetValue('LoggedOnSAMUser'); $d = [string]$x.GetValue('LoggedOnDisplayName'); $x.Close()
                    if ($d -and $u -and ($u -split '\\')[-1] -eq $sam) { $nome = $d; break }
                }
            } finally { $k.Close() }
        }
        if (-not $nome) {
            $u = [string](Get-LacadorValorRegistro 'HKLM' 64 $base 'LastLoggedOnSAMUser')
            if ($u -and ($u -split '\\')[-1] -eq $sam) { $nome = [string](Get-LacadorValorRegistro 'HKLM' 64 $base 'LastLoggedOnDisplayName') }
        }
    } catch { }
    if (-not $nome -and $env:USERDOMAIN -and $env:USERDOMAIN -eq $env:COMPUTERNAME) {
        # Conta local deste computador: o "nome completo" dela.
        try { $nome = [string]([adsi]('WinNT://{0}/{1},user' -f $env:COMPUTERNAME, $sam)).FullName } catch { }
    }
    if (-not $nome) { $nome = $sam }
    return (Format-LacadorNome $nome)
}

function Test-LacadorGrupoAdmin {
    # O usuário pertence ao grupo Administradores, mesmo que este processo não esteja elevado?
    # (Com o UAC ligado, o administrador roda os programas sem o privilégio até clicar em "Sim".)
    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        foreach ($c in @($id.Claims)) { if ([string]$c.Value -eq 'S-1-5-32-544') { return $true } }
    } catch { }
    try {
        $ErrorActionPreference = 'Continue'
        $saida = (& (Join-Path $env:windir 'System32\whoami.exe') '/groups' '/fo' 'csv' '/nh' 2>$null) -join "`n"
        if ($saida -match 'S-1-5-32-544') { return $true }
    } catch { }
    return $false
}

function Get-LacadorFatos {
    <#
      Coleta, somente leitura, tudo o que o Laçador precisa saber do computador.
      -Rapido pula o que é lento ou só interessa à tela (dispositivos, certificados, perfis do Firefox).
      -Progresso recebe uma hashtable sincronizada para a tela de inicialização acompanhar.
    #>
    param($Catalogo, $Config, [switch]$Rapido, $Progresso)
    if (-not $Catalogo) { $Catalogo = Get-LacadorCatalogo }
    if (-not $Config) { $Config = Get-LacadorConfig }
    $erros = New-Object System.Collections.Generic.List[string]
    $passo = {
        param($pct, $txt)
        if ($Progresso) { $Progresso['percentual'] = $pct; $Progresso['etapa'] = $txt }
    }
    $f = [ordered]@{}
    $f.coletadoEm = (Get-Date).ToString('s')
    $f.computador = [string]$env:COMPUTERNAME
    $f.usuario = [string]$env:USERNAME
    $f.nomeUsuario = ''
    try { $f.nomeUsuario = Get-LacadorNomeUsuario } catch { $f.nomeUsuario = [string]$env:USERNAME }
    $f.dominio = [string]$env:USERDOMAIN
    $f.admin = $false
    $f.grupoAdmin = $false
    $f.windows = [ordered]@{ nome = ''; versao = ''; build = ''; arquitetura = 'x64' }

    & $passo 5 'Lendo o Windows...'
    try {
        $f.admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        $f.grupoAdmin = [bool]$f.admin
        if (-not $f.grupoAdmin) { $f.grupoAdmin = Test-LacadorGrupoAdmin }
        if (-not [Environment]::Is64BitOperatingSystem) { $f.windows.arquitetura = 'x86' }
        $cv = 'SOFTWARE\Microsoft\Windows NT\CurrentVersion'
        $f.windows.nome = [string](Get-LacadorValorRegistro 'HKLM' 64 $cv 'ProductName')
        $f.windows.versao = [string](Get-LacadorValorRegistro 'HKLM' 64 $cv 'DisplayVersion')
        $build = [string](Get-LacadorValorRegistro 'HKLM' 64 $cv 'CurrentBuild')
        $f.windows.build = '{0}.{1}' -f $build, (Get-LacadorValorRegistro 'HKLM' 64 $cv 'UBR')
        # O registro ainda diz "Windows 10" no Windows 11; o número do build resolve.
        if ($build -match '^\d+$' -and [int]$build -ge 22000) { $f.windows.nome = $f.windows.nome -replace 'Windows 10', 'Windows 11' }
    } catch { $erros.Add('windows: ' + $_.Exception.Message) }

    & $passo 15 'Verificando os programas...'
    $f.programas = @()
    try { $f.programas = @(Get-LacadorProgramas) } catch { $erros.Add('programas: ' + $_.Exception.Message) }

    $f.arquivos = [ordered]@{}
    try {
        foreach ($it in $Catalogo.itens) {
            foreach ($a in @($it.detectar.arquivos)) {
                if ($a) { $f.arquivos[[string]$a] = (Test-Path -LiteralPath (Expand-LacadorCaminho $a)) }
            }
        }
    } catch { $erros.Add('arquivos: ' + $_.Exception.Message) }

    $f.servicos = [ordered]@{}
    try {
        foreach ($s in 'SCardSvr', 'CertPropSvc') {
            $x = Get-Service -Name $s -ErrorAction SilentlyContinue
            if ($x) { $f.servicos[$s] = [ordered]@{ estado = [string]$x.Status; inicio = [string]$x.StartType } }
        }
    } catch { $erros.Add('servicos: ' + $_.Exception.Message) }

    & $passo 30 'Procurando tokens conectados...'
    $f.dispositivos = @()
    if (-not $Rapido) {
        try { $f.dispositivos = @(Get-LacadorDispositivos $Catalogo) } catch { $erros.Add('dispositivos: ' + $_.Exception.Message) }
    }

    & $passo 50 'Lendo os certificados...'
    $f.certificados = @()
    if (-not $Rapido) {
        try { $f.certificados = @(Get-LacadorCertificados) } catch { $erros.Add('certificados: ' + $_.Exception.Message) }
    }

    & $passo 62 'Verificando o Assinador do COMAER...'
    $f.assinador = [ordered]@{ pasta = ''; jar = $false; bats = @(); ligacao64 = ''; ligacao32 = ''; manifesto = $false; atalho = $false; configUsuario = [ordered]@{ existe = $false; tokens = @() } }
    try { $f.assinador = Get-LacadorAssinadorFatos $f.programas } catch { $erros.Add('assinador: ' + $_.Exception.Message) }

    & $passo 74 'Verificando o Firefox e a extensão...'
    $f.firefox = [ordered]@{ instalacoes = @(); politica = $null; perfis = @(); aberto = $false }
    try {
        $extId = [string](@($Catalogo.itens | Where-Object { $_.id -eq 'extensao-firefox' })[0].extensaoId)
        $f.firefox.instalacoes = @(Get-LacadorFirefoxInstalacoes)
        $f.firefox.politica = Get-LacadorPoliticaFirefox $extId $f.firefox.instalacoes
        if (-not $Rapido) { $f.firefox.perfis = @(Get-LacadorPerfisFirefox $extId) }
        $f.firefox.aberto = (@(Get-Process -Name 'firefox' -ErrorAction SilentlyContinue).Count -gt 0)
    } catch { $erros.Add('firefox: ' + $_.Exception.Message) }

    & $passo 84 'Verificando o Java...'
    $f.java = [ordered]@{ jres = @(); jnlpComando = ''; jnlpEscolhaUsuario = ''; atualizacaoDesativada = $false }
    try { $f.java = Get-LacadorJavaFatos } catch { $erros.Add('java: ' + $_.Exception.Message) }

    & $passo 90 'Verificando a rede e os instaladores...'
    $f.proxy = [ordered]@{ ativo = $false; servidor = ''; pac = ''; excecoes = '' }
    try { $f.proxy = Get-LacadorProxyFatos } catch { $erros.Add('proxy: ' + $_.Exception.Message) }

    $f.wmic = [ordered]@{ x64 = $false; x86 = $false }
    try {
        if ($env:windir) {
            $f.wmic.x64 = (Test-Path -LiteralPath (Join-Path $env:windir 'System32\wbem\WMIC.exe'))
            $f.wmic.x86 = (Test-Path -LiteralPath (Join-Path $env:windir 'SysWOW64\wbem\WMIC.exe'))
        }
    } catch { }

    $f.pastaPacotes = Get-LacadorPastaPacotes $Config
    $f.recipiente = ''
    try { $f.recipiente = [string](Get-LacadorRecipiente) } catch { }
    $f.pacotes = [ordered]@{}
    try {
        foreach ($it in $Catalogo.itens) {
            foreach ($p in @($it.pacotes)) {
                if (-not $p) { continue }
                $o = Get-LacadorOrigemPacote ([string]$p.arquivo) $Config
                $f.pacotes[[string]$p.arquivo] = [ordered]@{ existe = [bool]$o.existe; tamanho = [long]$o.tamanho; origem = [string]$o.origem }
            }
        }
    } catch { $erros.Add('pacotes: ' + $_.Exception.Message) }

    $f.navegadores = [ordered]@{ edge = ''; chrome = '' }
    try { $f.navegadores = Get-LacadorNavegadores } catch { }
    $f.agente = [ordered]@{ tarefa = $false; instalado = $false; pasta = ''; versao = '' }
    try { $f.agente = Get-LacadorAgenteFatos } catch { $erros.Add('agente: ' + $_.Exception.Message) }

    $f.erros = $erros.ToArray()
    & $passo 96 'Montando o resultado...'
    # Ida e volta por JSON: garante um formato único (o mesmo dos arquivos de simulação).
    return ((ConvertTo-Json -InputObject $f -Depth 12) | ConvertFrom-Json)
}

#endregion

#region Estado (cálculo puro a partir dos fatos) ------------------------------

function Get-LacadorPacotesDoItem {
    param($Item, [string]$Arquitetura)
    return @(@($Item.pacotes) | Where-Object { $_ -and ((-not $_.arquitetura) -or ($_.arquitetura -eq $Arquitetura)) })
}

function Find-LacadorPrograma {
    # Devolve o programa instalado que casa com a regra (o de maior versão), ou $null.
    param($Fatos, [string]$PadraoNome, [string]$PadraoFabricante, [string]$Chave)
    $achados = @(@($Fatos.programas) | Where-Object {
        $_ -and (
            ($Chave -and $_.chave -eq $Chave) -or
            ($PadraoNome -and ([string]$_.nome -match $PadraoNome) -and ((-not $PadraoFabricante) -or ([string]$_.fabricante -match $PadraoFabricante)))
        )
    })
    if (-not $achados.Count) { return $null }
    $melhor = $achados[0]
    foreach ($a in $achados) { if ((Compare-LacadorVersao $a.versao $melhor.versao) -gt 0) { $melhor = $a } }
    return $melhor
}

function New-LacadorVerificacao {
    param([string]$Nome, [bool]$Ok, [string]$Detalhe = '', [bool]$Informativa = $false)
    return [ordered]@{ nome = $Nome; ok = $Ok; detalhe = $Detalhe; informativa = $Informativa }
}

function Get-LacadorEstadoItem {
    param($Item, $Fatos, $Catalogo, $Config)
    $arq = [string]$Fatos.windows.arquitetura
    $r = [ordered]@{
        id = [string]$Item.id; nome = [string]$Item.nome; descricao = [string]$Item.descricao
        categoria = [string]$Item.categoria; icone = [string]$Item.icone; versao = [string]$Item.versao
        opcional = [bool]$Item.opcional; legado = [bool]$Item.legado
        estado = 'ausente'; versaoInstalada = ''; detalhe = ''; acao = 'instalar'
        verificacoes = @(); avisos = @($Item.avisos | Where-Object { $_ })
        pacotesFaltando = @(); temPacotes = $false
        reinstalar = $false; podeDesinstalar = $false; podeReparar = $false; abrir = [string]$Item.abrir
        passo = ''; edicoes = @(); recusada = $false
    }
    $ver = New-Object System.Collections.Generic.List[object]

    # Instaladores disponíveis?
    $pacs = @(Get-LacadorPacotesDoItem $Item $arq)
    $r.temPacotes = ($pacs.Count -gt 0)
    $falt = New-Object System.Collections.Generic.List[string]
    foreach ($p in $pacs) {
        $info = Get-LacadorProp $Fatos.pacotes ([string]$p.arquivo)
        if (-not $info -or -not $info.existe) { $falt.Add([string]$p.arquivo) }
        elseif ($p.tamanho -and $info.tamanho -and ([long]$info.tamanho -ne [long]$p.tamanho)) { $falt.Add(('{0} (tamanho diferente do esperado)' -f $p.arquivo)) }
    }
    $r.pacotesFaltando = $falt.ToArray()

    # Modo demonstração: itens "instalados" pela simulação.
    $sim = $Fatos.simulacao
    if ($sim -and (@($sim.ok) -contains ('removido:' + $Item.id))) {
        $r.estado = 'ausente'; $r.acao = 'instalar'; $r.detalhe = 'Não instalado'
        return $r
    }
    if ($sim -and (@($sim.ok) -contains $Item.id)) {
        $r.estado = 'ok'; $r.acao = $null; $r.versaoInstalada = [string]$Item.versao; $r.detalhe = 'Instalado'
        return $r
    }

    # Regra genérica do catálogo
    $det = $Item.detectar
    $instalado = $false
    $prog = $null
    if ($det -and ($det.programa -or $det.chave)) {
        $prog = Find-LacadorPrograma $Fatos ([string]$det.programa) ([string]$det.fabricante) ([string]$det.chave)
        if ($prog) { $instalado = $true; $r.versaoInstalada = [string]$prog.versao }
    }
    $arquivosOk = $true
    foreach ($a in @($det.arquivos)) {
        if ($a -and -not (Get-LacadorProp $Fatos.arquivos ([string]$a))) { $arquivosOk = $false }
    }

    switch ([string]$Item.id) {
        'assinador' {
            $as = $Fatos.assinador
            $instalado = [bool]$as.jar
            if ($instalado) {
                $bats = @($as.bats | Where-Object { $_.existe })
                $comWmic = @($bats | Where-Object { $_.usaWmic })
                $ver.Add((New-LacadorVerificacao 'Programa instalado' $true ([string]$as.pasta)))
                $detW = 'Os inicializadores não dependem do WMIC'
                if ($comWmic.Count) { $detW = 'Os inicializadores ainda chamam o WMIC, que o Windows 11 removeu' }
                $ver.Add((New-LacadorVerificacao 'Correção do WMIC' ($comWmic.Count -eq 0 -and $bats.Count -gt 0) $detW))
                $lig = ([bool]$as.ligacao64 -or [bool]$as.ligacao32) -and [bool]$as.manifesto
                $detL = 'Registrada'
                if (-not $lig) { $detL = 'O Firefox não sabe onde está o assinador' }
                $ver.Add((New-LacadorVerificacao 'Ligação com o Firefox' $lig $detL))
            }
        }
        'firefox-esr' {
            # O padrão da base é o Firefox Developer Edition; o ESR é a reserva quando o SIGADAER não funciona no Developer.
            $inst = @($Fatos.firefox.instalacoes | Where-Object { $_ })
            $dev = @($inst | Where-Object { (Get-LacadorEdicaoDe $_) -eq 'developer' }) | Select-Object -First 1
            $esr = @($inst | Where-Object { (Get-LacadorEdicaoDe $_) -eq 'esr' }) | Select-Object -First 1
            $instalado = [bool]($dev -or $esr)
            $eds = New-Object System.Collections.Generic.List[object]
            foreach ($x in @($dev, $esr)) {
                if (-not $x) { continue }
                $bits = '64 bits'
                if ($x.arquitetura -eq 'x86') { $bits = '32 bits' }
                $eds.Add([ordered]@{ edicao = (Get-LacadorEdicaoDe $x); nome = (Get-LacadorNomeEdicao (Get-LacadorEdicaoDe $x)); versao = [string]$x.versao; bits = $bits })
            }
            $r.edicoes = $eds.ToArray()
            $detD = 'Não instalado'
            if ($dev) { $detD = ('Instalado, versão {0} (padrão da base)' -f $dev.versao) }
            $ver.Add((New-LacadorVerificacao 'Firefox Developer Edition' ([bool]$dev) $detD $true))
            $detE = 'Não instalado. É a reserva para quando o SIGADAER não funciona no Developer.'
            if ($esr) { $detE = ('Instalado, versão {0} (reserva)' -f $esr.versao) }
            $ver.Add((New-LacadorVerificacao 'Firefox ESR' ([bool]$esr) $detE $true))
            if ($dev -and $esr) { $r.detalhe = 'Developer Edition e ESR instalados'; $r.versaoInstalada = [string]$dev.versao }
            elseif ($dev) { $r.detalhe = ('Developer Edition {0}' -f $dev.versao); $r.versaoInstalada = [string]$dev.versao }
            elseif ($esr) { $r.detalhe = ('ESR {0}' -f $esr.versao); $r.versaoInstalada = [string]$esr.versao }
            elseif ($inst.Count) { $r.detalhe = 'Só o Firefox comum está instalado. O SIGADAER pede o Developer Edition ou o ESR.' }
            else { $r.detalhe = 'Nenhum Firefox instalado' }
            $r.temDeveloper = [bool]$dev
            $r.temEsr = [bool]$esr
            if ($esr) { $r.podeDesinstalar = $true; $r.podeReparar = $true }
        }
        'extensao-firefox' {
            # Obrigatório: a extensão precisa estar no Firefox deste usuário E com o botão fixado na barra.
            $pol = $Fatos.firefox.politica
            $polOk = ($pol -and [bool]$pol.url -and [bool]$pol.arquivoExiste -and ([string]$pol.modo -ne 'blocked'))
            $perfis = @($Fatos.firefox.perfis | Where-Object { $_ })
            $doSig = @($perfis | Where-Object { (Get-LacadorProp $_ 'edicao') -in 'developer', 'esr' })
            if (-not $doSig.Count) { $doSig = $perfis }
            $usados = @($doSig | Where-Object { $_.emUso })
            if (-not $usados.Count) { $usados = @($doSig | Where-Object { (Get-LacadorProp $_ 'aberto') -or $_.extensao }) }
            $com = @($usados | Where-Object { $_.extensao -and $_.extensao.ativa })
            $desligada = @($usados | Where-Object { $_.extensao -and -not $_.extensao.ativa })
            $semFixar = @($com | Where-Object { (Get-LacadorProp $_ 'fixada') -ne $true })
            if ($Fatos.simulacao -and (@($Fatos.simulacao.ok) -contains 'fixar-extensao')) { $semFixar = @() }
            $temFirefox = (@($Fatos.firefox.instalacoes | Where-Object { $_ -and (Get-LacadorEdicaoDe $_) -in 'developer', 'esr' }).Count -gt 0)
            $instalado = ($polOk -or $com.Count -gt 0)
            if ($instalado) {
                $r.podeReparar = $true
                if ($polOk) { $r.podeDesinstalar = $true }
                $detP = 'O Firefox instala a extensão sozinho, para todos os usuários'
                if (-not $polOk) { $detP = 'Instalada à mão só neste usuário: o Laçador refaz pela política' }
                $ver.Add((New-LacadorVerificacao 'Instalação automática' $polOk $detP $true))
                if ($pol -and $pol.url -and -not $pol.arquivoExiste) { $ver.Add((New-LacadorVerificacao 'Arquivo da extensão' $false 'A política aponta para um arquivo que não existe mais')) }
                $ondeTxt = @($com | ForEach-Object { Get-LacadorNomeEdicao ([string](Get-LacadorProp $_ 'edicao')) } | Select-Object -Unique) -join ' e '
                if ($com.Count) {
                    $r.versaoInstalada = [string]$com[0].extensao.versao
                    $ver.Add((New-LacadorVerificacao 'No Firefox deste usuário' $true ('Ativa no {0}' -f $ondeTxt)))
                    $detF = 'O botão do assinador está na barra do Firefox'
                    if ($semFixar.Count) { $detF = 'O botão do assinador está escondido no menu de extensões (a peça de quebra-cabeça)' }
                    $ver.Add((New-LacadorVerificacao 'Fixada na barra' ($semFixar.Count -eq 0) $detF))
                    if ($semFixar.Count) { $r.passo = 'fixar' }
                } elseif ($desligada.Count) {
                    $ver.Add((New-LacadorVerificacao 'No Firefox deste usuário' $false 'Está no Firefox, mas desativada'))
                } elseif ($temFirefox) {
                    $quando = [string](Get-LacadorProp $pol 'gravadaEm')
                    $depois = @($usados | Where-Object { $quando -and [string](Get-LacadorProp $_ 'atualizadoEm') -and ([string](Get-LacadorProp $_ 'atualizadoEm')) -gt $quando })
                    $aberto = [bool](Get-LacadorProp $Fatos.firefox 'aberto')
                    if ($polOk -and $depois.Count -and -not $aberto) {
                        # O Firefox abriu depois da política e não instalou: Reparar aplica o procedimento da ATIC.
                        $ver.Add((New-LacadorVerificacao 'No Firefox deste usuário' $false 'O Firefox abriu, mas não aceitou a extensão. Reparar aplica o procedimento da ATIC.'))
                        $r.recusada = $true
                    } elseif ($aberto) {
                        $ver.Add((New-LacadorVerificacao 'No Firefox deste usuário' $false 'Ainda não apareceu: feche e abra o Firefox para ela entrar'))
                        if ($polOk) { $r.passo = 'abrir-firefox' }
                    } else {
                        $ver.Add((New-LacadorVerificacao 'No Firefox deste usuário' $false 'Ainda não apareceu: o Firefox precisa ser aberto uma vez'))
                        if ($polOk) { $r.passo = 'abrir-firefox' }
                    }
                }
            } elseif (-not $temFirefox) {
                $r.detalhe = 'Instale o Firefox primeiro'
            }
        }
        'java8' {
            $jre = @(@($Fatos.java.jres) | Where-Object { $_.versao -eq '1.8.0_91' -and $_.arquitetura -eq 'x86' }) | Select-Object -First 1
            if (-not $jre -and $arq -eq 'x86') { $jre = @(@($Fatos.java.jres) | Where-Object { $_.versao -eq '1.8.0_91' }) | Select-Object -First 1 }
            $instalado = ($null -ne $jre) -or $instalado
            if ($instalado) {
                $r.versaoInstalada = '8u91'
                $cmd = [string]$Fatos.java.jnlpComando
                $okJ = ($cmd -match 'jre1\.8\.0_91\\bin\\javaws\.exe')
                $detJ = 'Arquivos .jnlp abrem com o Java 8u91'
                if (-not $okJ) { $detJ = 'Arquivos .jnlp não estão ligados ao Java 8u91' }
                $ver.Add((New-LacadorVerificacao 'Abertura do SIAFI (.jnlp)' $okJ $detJ))
                $detA = 'Desligada (o Java não troca de versão sozinho)'
                if (-not $Fatos.java.atualizacaoDesativada) { $detA = 'Ligada: o Java pode pedir para atualizar' }
                $ver.Add((New-LacadorVerificacao 'Atualização automática' ([bool]$Fatos.java.atualizacaoDesativada) $detA))
            }
        }
        'java7' {
            $jre = @(@($Fatos.java.jres) | Where-Object { $_.versao -eq '1.7.0_51' }) | Select-Object -First 1
            $instalado = ($null -ne $jre) -or $instalado
            if ($instalado) { $r.versaoInstalada = '7u51' }
        }
        'adobe-xi' {
            if ($instalado -and $det.versaoMinima -and (Compare-LacadorVersao $r.versaoInstalada ([string]$det.versaoMinima)) -lt 0) {
                $ver.Add((New-LacadorVerificacao 'Atualização 11.0.23' $false ('Instalada a versão {0}; falta aplicar a atualização' -f $r.versaoInstalada)))
            }
        }
        'servico-smartcard' {
            $s = Get-LacadorProp $Fatos.servicos 'SCardSvr'
            $instalado = ($null -ne $s)
            $r.acao = 'reparar'
            if ($s) {
                $desativado = ([string]$s.inicio -eq 'Disabled')
                $leitores = @(@($Fatos.dispositivos) | Where-Object { $_.classe -eq 'SmartCardReader' })
                $parado = ($leitores.Count -gt 0 -and [string]$s.estado -ne 'Running')
                $detS = 'Funcionando'
                if ($desativado) { $detS = 'O serviço está desativado' }
                elseif ($parado) { $detS = 'Há um token conectado, mas o serviço está parado' }
                elseif ([string]$s.estado -ne 'Running') { $detS = 'Pronto (inicia quando um token é conectado)' }
                $ver.Add((New-LacadorVerificacao 'Serviço "Cartão inteligente"' (-not $desativado -and -not $parado) $detS))
            } else {
                $r.detalhe = 'Serviço "Cartão inteligente" não encontrado no Windows'
            }
        }
        default {
            if ($det -and -not ($det.programa -or $det.chave) -and @($det.arquivos).Count) { $instalado = $arquivosOk }
            if ($instalado -and -not $arquivosOk) {
                $ver.Add((New-LacadorVerificacao 'Arquivos do driver' $false 'O programa consta como instalado, mas falta um arquivo no Windows. O Laçador reinstala por cima.'))
                $r.reinstalar = $true
            }
        }
    }

    # Conflito declarado no catálogo (ex.: outro Adobe instalado)
    $conf = $Item.conflito
    if (-not $instalado -and $conf -and $conf.programa) {
        $outro = @(@($Fatos.programas) | Where-Object { [string]$_.nome -match [string]$conf.programa }) | Select-Object -First 1
        if ($outro) {
            $r.estado = 'conflito'; $r.acao = $null
            $r.detalhe = ('{0} Instalado: {1} {2}.' -f $conf.mensagem, $outro.nome, $outro.versao)
            $r.verificacoes = $ver.ToArray()
            return $r
        }
    }

    $r.verificacoes = $ver.ToArray()
    if (-not $instalado) {
        $r.estado = 'ausente'
        if ($r.acao -ne 'reparar') { $r.acao = 'instalar' }
        if (-not $r.detalhe) { $r.detalhe = 'Não instalado' }
        $r.podeDesinstalar = $false
        return $r
    }
    if ($Item.id -notin 'firefox-esr', 'extensao-firefox') {
        if ($Item.categoria -ne 'ambiente') { $r.podeReparar = $true }
        if ($Item.desinstalar) { $r.podeDesinstalar = $true }
    }
    $falhas = @($ver | Where-Object { -not $_.ok -and -not $_.informativa })
    $versaoAntiga = ($det -and $det.versaoMinima -and $r.versaoInstalada -and ((Compare-LacadorVersao $r.versaoInstalada ([string]$det.versaoMinima)) -lt 0))
    if ($versaoAntiga) {
        $r.estado = 'atencao'; $r.acao = 'instalar'
        $r.detalhe = ('Versão {0} instalada; a do catálogo é {1}' -f $r.versaoInstalada, $Item.versao)
    } elseif ($falhas.Count) {
        $r.estado = 'atencao'; $r.acao = 'reparar'
        if ($r.passo) { $r.acao = $r.passo }    # algo que o próprio usuário faz (abrir o Firefox, fixar o botão)
        $r.detalhe = [string]$falhas[0].detalhe
    } else {
        $r.estado = 'ok'; $r.acao = $null
        if (-not $r.detalhe) {
            $r.detalhe = 'Instalado'
            if ($r.versaoInstalada) { $r.detalhe = ('Instalado ({0})' -f $r.versaoInstalada) }
        }
    }
    return $r
}

function Get-LacadorEstadoCertificado {
    param($Cert, [int]$AvisarDias, [datetime]$Agora)
    $ini = [datetime]::Parse([string]$Cert.inicio, [Globalization.CultureInfo]::InvariantCulture)
    $fim = [datetime]::Parse([string]$Cert.fim, [Globalization.CultureInfo]::InvariantCulture)
    $dias = [int][Math]::Floor(($fim - $Agora).TotalDays)
    $sit = 'valido'
    if ($fim -lt $Agora) { $sit = 'vencido' }
    elseif ($ini -gt $Agora) { $sit = 'futuro' }
    elseif ($dias -le $AvisarDias) { $sit = 'vencendo' }
    $total = ($fim - $ini).TotalDays
    $pct = 0
    if ($total -gt 0) { $pct = [int][Math]::Max(0, [Math]::Min(100, (($fim - $Agora).TotalDays / $total) * 100)) }
    $titular = [string]$Cert.titular
    $pessoal = ([bool]$Cert.chavePrivada -and -not [bool]$Cert.autoassinado -and ($titular -notmatch '^(trust_)?[0-9a-f]{8}-[0-9a-f]{4}-'))
    return [ordered]@{
        titular = $titular; emissor = [string]$Cert.emissor; id = [string]$Cert.id
        validade = $fim.ToString('dd/MM/yyyy'); dias = $dias; situacao = $sit; restante = $pct
        pessoal = $pessoal; chavePrivada = [bool]$Cert.chavePrivada
    }
}

function ConvertTo-LacadorEstado {
    <# Transforma os fatos brutos no estado que a tela mostra. Função pura: não toca no computador. #>
    param($Fatos, $Catalogo, $Config, [datetime]$Agora = (Get-Date))
    if (-not $Catalogo) { $Catalogo = Get-LacadorCatalogo }
    if (-not $Config) { $Config = Get-LacadorConfig }
    $e = [ordered]@{}
    $e.versao = $script:VersaoLacador
    if ($Fatos.coletadoEm -is [datetime]) { $e.coletadoEm = $Fatos.coletadoEm.ToString('s') } else { $e.coletadoEm = [string]$Fatos.coletadoEm }
    $e.computador = [string]$Fatos.computador
    $e.usuario = [string]$Fatos.usuario
    $e.nomeUsuario = [string](Get-LacadorProp $Fatos 'nomeUsuario')
    if (-not $e.nomeUsuario) { $e.nomeUsuario = Format-LacadorNome ([string]$Fatos.usuario) }
    $e.credito = $script:CreditoLacador
    $e.firefoxAberto = [bool](Get-LacadorProp $Fatos.firefox 'aberto')
    $e.admin = [bool]$Fatos.admin
    $e.windows = $Fatos.windows
    $e.organizacao = [string]$Config.organizacao
    $e.suporte = $Config.suporte
    $e.demonstracao = [bool]$Fatos.simulacao

    # Itens
    $itens = [ordered]@{}
    foreach ($it in $Catalogo.itens) { $itens[[string]$it.id] = Get-LacadorEstadoItem $it $Fatos $Catalogo $Config }
    $e.itens = $itens

    # Tokens
    $devs = @($Fatos.dispositivos | Where-Object { $_ })
    $usados = New-Object System.Collections.Generic.List[string]
    $tokens = New-Object System.Collections.Generic.List[object]
    foreach ($t in $Catalogo.tokens) {
        $meus = @($devs | Where-Object {
            (($t.leitor) -and ([string]$_.nome -match [string]$t.leitor)) -or (($t.hardware) -and ([string]$_.id -match [string]$t.hardware))
        })
        foreach ($d in $meus) { $usados.Add([string]$d.id) }
        $conectado = ($meus.Count -gt 0)
        $leitorOk = (@($meus | Where-Object { $_.classe -ne '' -and $_.classe -ne 'Unknown' -and $_.status -eq 'OK' }).Count -gt 0)
        $estItens = @($t.itens | ForEach-Object { $itens[[string]$_] })
        $faltando = @($estItens | Where-Object { $_.estado -eq 'ausente' -or ($_.estado -eq 'atencao' -and $_.acao -eq 'instalar') } | ForEach-Object { $_.id })
        $reparar = @($estItens | Where-Object { $_.estado -eq 'atencao' -and $_.acao -eq 'reparar' } | ForEach-Object { $_.id })
        $driverOk = ($faltando.Count -eq 0 -and $reparar.Count -eq 0)
        $estado = 'desconectado'
        $resumo = 'Driver instalado. Conecte o token para usar.'
        if ($conectado -and $driverOk -and $leitorOk) { $estado = 'pronto'; $resumo = 'Tudo certo' }
        elseif ($conectado -and $driverOk) { $estado = 'atencao'; $resumo = 'O token está conectado, mas o Windows não o reconheceu. Tente outra porta USB ou clique em Reparar.' }
        elseif ($conectado) { $estado = 'sem-driver'; $resumo = 'Token conectado, falta instalar o driver' }
        elseif (-not $driverOk) { $estado = 'sem-driver'; $resumo = 'Driver não instalado' }
        $noAssinador = $false
        if ($t.assinadorToken) {
            $noAssinador = (@(@($Fatos.assinador.configUsuario.tokens) | Where-Object { $_ -and ([string]$_.caminho -replace '\\', '/').ToLowerInvariant() -eq ([string]$t.pkcs11).ToLowerInvariant() }).Count -gt 0)
        }
        # Demonstração: o botão "Ajustar" marca o ajuste como feito.
        if ($t.assinadorToken -and $Fatos.simulacao -and (@($Fatos.simulacao.ok) -contains ('ajuste-{0}' -f [string]$t.assinadorToken))) { $noAssinador = $true }
        $adm = ''
        if ($Fatos.simulacao) { $adm = 'simulado' }
        $nomeLeitor = ''
        if ($meus.Count) { $nomeLeitor = [string]$meus[0].nome }
        $tokens.Add([ordered]@{
            id = [string]$t.id; nome = [string]$t.nome; fabricante = [string]$t.fabricante; descricao = [string]$t.descricao
            conectado = $conectado; leitor = $nomeLeitor
            estado = $estado; resumo = $resumo
            itens = @($t.itens); faltando = $faltando; reparar = $reparar
            metodoAssinador = [string]$t.metodoAssinador
            administrador = [string]$t.administrador.nome
            ajusteAssinador = [bool]$t.assinadorToken; ajusteAssinadorFeito = $noAssinador
        })
    }
    $e.tokens = $tokens.ToArray()
    $e.leitoresDesconhecidos = @($devs | Where-Object {
        $_.classe -eq 'SmartCardReader' -and -not $usados.Contains([string]$_.id) -and ([string]$_.nome -notmatch 'Windows Hello|Virtual|UICC|TPM|NFC|Bluetooth|Microsoft IFD')
    } | ForEach-Object { [ordered]@{ nome = [string]$_.nome; id = [string]$_.id } })

    # Certificados
    $avisar = 30
    if ($Config.certificados.avisarDiasAntes) { $avisar = [int]$Config.certificados.avisarDiasAntes }
    $certs = @($Fatos.certificados | Where-Object { $_ } | ForEach-Object { Get-LacadorEstadoCertificado $_ $avisar $Agora })
    $e.certificados = @($certs | Sort-Object @{ Expression = { -not $_.pessoal } }, @{ Expression = { $_.dias } })

    # Proxy
    $px = $Fatos.proxy
    $alvo = [string]$Config.proxy.servidor
    $porta = 0
    if ($Config.proxy.porta) { $porta = [int]$Config.proxy.porta }
    $pxOk = ($alvo -and (([bool]$px.ativo -and [string]$px.servidor -match [regex]::Escape($alvo)) -or ([string]$px.pac -ne '')))
    $pxTexto = 'Sem proxy configurado neste usuário'
    if ($px.pac) { $pxTexto = ('Configuração automática: {0}' -f $px.pac) }
    elseif ($px.ativo -and $px.servidor) { $pxTexto = [string]$px.servidor }
    $e.proxy = [ordered]@{ esperado = $alvo; porta = $porta; atual = $pxTexto; ok = [bool]$pxOk; automatico = [bool]$px.pac; podeAplicar = ($porta -gt 0 -and -not $px.pac) }

    # Sistemas
    $prontos = @($e.tokens | Where-Object { $_.estado -eq 'pronto' })
    $comDriver = @($e.tokens | Where-Object { $_.faltando.Count -eq 0 -and $_.reparar.Count -eq 0 })
    $conectadosSemDriver = @($e.tokens | Where-Object { $_.conectado -and ($_.faltando.Count -gt 0 -or $_.reparar.Count -gt 0) })
    $sistemas = New-Object System.Collections.Generic.List[object]
    foreach ($s in $Catalogo.sistemas) {
        $linhas = New-Object System.Collections.Generic.List[object]
        $faltando = New-Object System.Collections.Generic.List[string]
        $reparar = New-Object System.Collections.Generic.List[string]
        $escolherToken = $false
        $bloqueio = ''
        $passo = $null
        foreach ($req in @($s.requer)) {
            if ($req -eq '@token') {
                if ($prontos.Count) {
                    $linhas.Add([ordered]@{ id = '@token'; nome = 'Token'; estado = 'ok'; detalhe = ('{0} conectado' -f $prontos[0].nome) })
                } elseif ($conectadosSemDriver.Count) {
                    $t = $conectadosSemDriver[0]
                    foreach ($x in $t.faltando) { if (-not $faltando.Contains($x)) { $faltando.Add($x) } }
                    foreach ($x in $t.reparar) { if (-not $reparar.Contains($x)) { $reparar.Add($x) } }
                    $linhas.Add([ordered]@{ id = '@token'; nome = 'Token'; estado = 'ausente'; detalhe = ('{0} conectado, falta o driver' -f $t.nome) })
                } elseif ($comDriver.Count) {
                    $linhas.Add([ordered]@{ id = '@token'; nome = 'Token'; estado = 'aguardando'; detalhe = ('Driver instalado ({0}). Conecte o token.' -f (@($comDriver | ForEach-Object { $_.nome }) -join ', ')) })
                } else {
                    $escolherToken = $true
                    $linhas.Add([ordered]@{ id = '@token'; nome = 'Token'; estado = 'ausente'; detalhe = 'Nenhum driver de token instalado' })
                }
                continue
            }
            $it = $itens[[string]$req]
            if (-not $it) { continue }
            $linhas.Add([ordered]@{ id = $it.id; nome = $it.nome; estado = $it.estado; detalhe = $it.detalhe })
            if ($it.estado -eq 'ausente' -or ($it.estado -eq 'atencao' -and $it.acao -eq 'instalar')) { $faltando.Add($it.id) }
            elseif ($it.estado -eq 'atencao' -and $it.acao -in 'abrir-firefox', 'fixar') { if (-not $passo) { $passo = [ordered]@{ item = $it.id; acao = $it.acao; texto = $it.detalhe } } }
            elseif ($it.estado -eq 'atencao') { $reparar.Add($it.id) }
            elseif ($it.estado -eq 'conflito') { $bloqueio = $it.detalhe }
        }
        $avisos = New-Object System.Collections.Generic.List[string]
        if ($s.verificarProxy -and -not $e.proxy.ok) {
            $avisos.Add(('Na rede da FAB, o SIAFI tela preta pede o proxy {0}. Atual: {1}.' -f $e.proxy.esperado, $e.proxy.atual))
        }
        $opc = @($s.opcionais | Where-Object { $_ } | ForEach-Object { $itens[[string]$_] } | Where-Object { $_ } | ForEach-Object { [ordered]@{ id = $_.id; nome = $_.nome; estado = $_.estado; detalhe = $_.detalhe } })
        $semPacote = @(@($faltando) | ForEach-Object { $itens[$_] } | Where-Object { $_.pacotesFaltando.Count -gt 0 } | ForEach-Object { $_.nome })
        $estado = 'pronto'
        $resumo = 'Pronto para usar'
        if ($bloqueio) { $estado = 'bloqueado'; $resumo = $bloqueio }
        elseif ($faltando.Count -or $escolherToken) { $estado = 'falta'; $n = $faltando.Count; if ($escolherToken) { $n++ }; if ($n -eq 1) { $resumo = 'Falta instalar 1 item' } else { $resumo = ('Faltam instalar {0} itens' -f $n) } }
        elseif ($reparar.Count) { $estado = 'atencao'; $resumo = 'Precisa de reparo' }
        elseif ($passo) {
            $estado = 'atencao'
            if ($passo.acao -eq 'fixar') { $resumo = 'Falta fixar o botão do assinador na barra do Firefox' } else { $resumo = 'Falta abrir o Firefox uma vez para a extensão entrar' }
        }
        elseif (@($linhas | Where-Object { $_.estado -eq 'aguardando' }).Count) { $estado = 'aguardando'; $resumo = 'Instalado. Conecte o token para usar.' }
        $sistemas.Add([ordered]@{
            id = [string]$s.id; nome = [string]$s.nome; descricao = [string]$s.descricao; icone = [string]$s.icone
            opcional = [bool]$s.opcional; estado = $estado; resumo = $resumo
            requisitos = $linhas.ToArray(); opcionais = $opc
            faltando = $faltando.ToArray(); reparar = $reparar.ToArray(); escolherToken = $escolherToken
            semPacote = $semPacote; avisos = $avisos.ToArray(); passo = $passo
            temSite = [bool]$s.site; temPrograma = [bool]$s.programa; tutorial = [string]$s.tutorial
        })
    }
    $e.sistemas = $sistemas.ToArray()

    # Avisos do topo, do mais grave para o menos grave
    $av = New-Object System.Collections.Generic.List[object]
    foreach ($c in @($e.certificados | Where-Object { $_.pessoal })) {
        if ($c.situacao -eq 'vencido') { $av.Add([ordered]@{ nivel = 'alerta'; titulo = 'Certificado vencido'; texto = ('O certificado de {0} venceu em {1}. Procure o setor responsável para renovar.' -f $c.titular, $c.validade); pagina = 'certificados' }) }
        elseif ($c.situacao -eq 'vencendo') { $av.Add([ordered]@{ nivel = 'alerta'; titulo = 'Certificado perto de vencer'; texto = ('O certificado de {0} vence em {1}, em {2}.' -f $c.titular, (Get-LacadorPlural $c.dias 'dia' 'dias'), $c.validade); pagina = 'certificados' }) }
    }
    foreach ($t in @($e.tokens | Where-Object { $_.conectado -and $_.estado -ne 'pronto' })) {
        $av.Add([ordered]@{ nivel = 'alerta'; titulo = ('{0} precisa de atenção' -f $t.nome); texto = $t.resumo; pagina = 'tokens' })
    }
    $as = $itens['assinador']
    if ($as -and $as.estado -eq 'atencao') {
        $av.Add([ordered]@{ nivel = 'alerta'; titulo = 'O Assinador do COMAER precisa de reparo'; texto = $as.detalhe; pagina = 'programas' })
    }
    foreach ($l in @($e.leitoresDesconhecidos)) {
        $av.Add([ordered]@{ nivel = 'info'; titulo = 'Token ou leitor não identificado'; texto = ('Conectado: {0}. Se for o DXToken (Dexon), instale o DXSafe na página Tokens.' -f $l.nome); pagina = 'tokens' })
    }
    $e.avisos = $av.ToArray()

    # Acesso: quem é o usuário e se este computador já foi liberado para instalar sem administrador
    $liberado = [bool](Get-LacadorProp $Fatos.agente 'tarefa')
    $versaoInst = [string](Get-LacadorProp $Fatos.agente 'versao')
    if ($Fatos.simulacao -and (@($Fatos.simulacao.ok) -contains 'acesso')) { $liberado = $true; $versaoInst = $script:VersaoLacador }
    $ehAdmin = ([bool]$Fatos.admin -or [bool](Get-LacadorProp $Fatos 'grupoAdmin'))
    $e.acesso = [ordered]@{
        usuario = [string]$Fatos.usuario
        administrador = $ehAdmin
        elevado = [bool]$Fatos.admin
        liberado = $liberado
        pasta = [string](Get-LacadorProp $Fatos.agente 'pasta')
        versaoInstalada = $versaoInst
        atualizar = [bool]($liberado -and $versaoInst -and ((Compare-LacadorVersao $versaoInst $script:VersaoLacador) -lt 0))
        executavel = [bool](Get-LacadorProp $Fatos 'recipiente')
    }
    if ($e.acesso.atualizar) {
        # O agente que instala sem senha é a cópia instalada: enquanto ela for antiga, as correções novas não valem.
        $av.Insert(0, [ordered]@{ nivel = 'alerta'; titulo = ('O Laçador instalado neste computador é o {0}' -f $versaoInst); texto = ('Atualize para o {0} na página Acesso (botão Atualizar). Até lá, as instalações sem senha usam a versão antiga.' -f $script:VersaoLacador); pagina = 'acesso' })
        $e.avisos = $av.ToArray()
    }
    if (-not $liberado -and -not $ehAdmin) {
        $av.Add([ordered]@{ nivel = 'info'; titulo = 'Este usuário não é administrador'; texto = 'Para instalar, o Windows vai pedir a senha de um administrador. O suporte pode liberar este computador uma vez, na página Acesso.'; pagina = 'acesso' })
        $e.avisos = $av.ToArray()
    }

    # Diagnóstico
    $e.agente = [ordered]@{ tarefa = $liberado; instalado = [bool](Get-LacadorProp $Fatos.agente 'instalado'); pasta = [string](Get-LacadorProp $Fatos.agente 'pasta'); versao = $versaoInst }
    $e.wmic = $Fatos.wmic
    $noExe = $false
    $valsPac = @()
    if ($Fatos.pacotes -is [System.Collections.IDictionary]) { $valsPac = @($Fatos.pacotes.Values) }
    elseif ($Fatos.pacotes) { $valsPac = @($Fatos.pacotes.PSObject.Properties | ForEach-Object { $_.Value }) }
    foreach ($v in $valsPac) { if ([string](Get-LacadorProp $v 'origem') -eq 'executavel') { $noExe = $true } }
    $e.pacotesNoExecutavel = $noExe
    if ($noExe) { $e.pastaPacotes = 'Dentro do Lacador.exe' } else { $e.pastaPacotes = [string]$Fatos.pastaPacotes }
    $listaPac = New-Object System.Collections.Generic.List[object]
    foreach ($it in $Catalogo.itens) {
        foreach ($p in @(Get-LacadorPacotesDoItem $it ([string]$Fatos.windows.arquitetura))) {
            $info = Get-LacadorProp $Fatos.pacotes ([string]$p.arquivo)
            $ok = ($info -and $info.existe -and ((-not $p.tamanho) -or ([long]$info.tamanho -eq [long]$p.tamanho)))
            $listaPac.Add([ordered]@{ item = [string]$it.nome; arquivo = [string]$p.arquivo; presente = [bool]($info -and $info.existe); ok = [bool]$ok })
        }
    }
    $e.pacotes = $listaPac.ToArray()
    $faltamPac = @($listaPac | Where-Object { -not $_.ok }).Count
    if ($e.acesso.executavel -and $listaPac.Count -and $faltamPac -eq $listaPac.Count) { $e.pastaPacotes = 'Este Lacador.exe veio sem os instaladores' }
    if ($faltamPac -gt 0) {
        $comoResolver = 'Veja a lista na página Diagnóstico.'
        if ($e.acesso.executavel) { $comoResolver = 'Na página Diagnóstico, clique em “Montar o Laçador completo” e escolha o arquivo TOKENS.rar.' }
        if ($faltamPac -eq 1) { $tituloPac = 'Falta 1 instalador' } else { $tituloPac = ('Faltam {0} instaladores' -f $faltamPac) }
        if ($faltamPac -eq $listaPac.Count) { $tituloPac = 'Este Laçador está sem os instaladores' }
        $av.Insert(0, [ordered]@{ nivel = 'alerta'; titulo = $tituloPac; texto = ('Ele verifica e repara, mas não consegue instalar o que depende deles. {0}' -f $comoResolver); pagina = 'diagnostico' })
        $e.avisos = $av.ToArray()
    }
    $e.navegadores = $Fatos.navegadores
    $e.erros = @($Fatos.erros | Where-Object { $_ })
    return $e
}

function Get-LacadorEstado {
    param($Progresso, [switch]$Rapido)
    $cat = Get-LacadorCatalogo
    $cfg = Get-LacadorConfig
    $fatos = Get-LacadorFatos -Catalogo $cat -Config $cfg -Progresso $Progresso -Rapido:$Rapido
    return (ConvertTo-LacadorEstado $fatos $cat $cfg)
}

function Resolve-LacadorPlano {
    <#
      Recebe o que o usuário pediu (itens, e opcionalmente sistemas e um modelo de token)
      e devolve a lista de itens na ordem certa de instalação (a ordem do catálogo),
      já com as dependências.
    #>
    param($Catalogo, [string[]]$Itens, [string[]]$Sistemas, [string]$Token, $Estado)
    $quero = New-Object System.Collections.Generic.List[string]
    foreach ($i in @($Itens)) { if ($i) { $quero.Add($i) } }
    foreach ($sid in @($Sistemas)) {
        $s = @($Catalogo.sistemas | Where-Object { $_.id -eq $sid })[0]
        if (-not $s) { continue }
        foreach ($req in @($s.requer)) {
            if ($req -eq '@token') {
                $modelos = @()
                if ($Token -eq 'todos') { $modelos = @($Catalogo.tokens) }
                elseif ($Token) { $modelos = @($Catalogo.tokens | Where-Object { $_.id -eq $Token }) }
                elseif ($Estado) {
                    $con = @($Estado.tokens | Where-Object { $_.conectado } | ForEach-Object { $_.id })
                    $modelos = @($Catalogo.tokens | Where-Object { $con -contains $_.id })
                }
                foreach ($m in $modelos) { foreach ($x in @($m.itens)) { $quero.Add([string]$x) } }
            } else { $quero.Add([string]$req) }
        }
    }
    # dependências
    $mudou = $true
    while ($mudou) {
        $mudou = $false
        foreach ($id in @($quero.ToArray())) {
            $it = @($Catalogo.itens | Where-Object { $_.id -eq $id })[0]
            foreach ($d in @($it.depende)) { if ($d -and -not $quero.Contains([string]$d)) { $quero.Add([string]$d); $mudou = $true } }
        }
    }
    return @($Catalogo.itens | Where-Object { $quero.Contains([string]$_.id) } | ForEach-Object { [string]$_.id })
}

#endregion

#region Ações com privilégio (rodam no agente) ---------------------------------

function Protect-LacadorPasta {
    <# Deixa a pasta com dono Administradores e acesso total só para SYSTEM e Administradores.
       -UsuariosLeem: os usuários podem ler.  -UsuariosCriam: os usuários podem criar arquivos (fila de pedidos). #>
    param([string]$Pasta, [switch]$UsuariosLeem, [switch]$UsuariosCriam)
    if (-not (Test-Path -LiteralPath $Pasta)) { New-Item -ItemType Directory -Path $Pasta -Force | Out-Null }
    $it = Get-Item -LiteralPath $Pasta -Force
    if ($it.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw ('A pasta {0} é um atalho ou junção e não pode ser usada.' -f $Pasta) }
    $icacls = Join-Path $env:windir 'System32\icacls.exe'
    $null = & $icacls $Pasta '/setowner' '*S-1-5-32-544' '/C' '/Q' 2>&1
    $lista = @($Pasta, '/inheritance:r', '/grant:r', '*S-1-5-18:(OI)(CI)F', '/grant:r', '*S-1-5-32-544:(OI)(CI)F')
    if ($UsuariosCriam) { $lista += @('/grant:r', '*S-1-5-32-545:(RX,WD)', '/grant', '*S-1-5-32-545:(OI)(IO)M') }
    elseif ($UsuariosLeem) { $lista += @('/grant:r', '*S-1-5-32-545:(OI)(CI)RX') }
    else { $lista += @('/remove:g', '*S-1-5-32-545', '/remove:g', '*S-1-5-11', '/remove:g', '*S-1-1-0') }
    $saida = & $icacls @lista '/C' '/Q' 2>&1
    if ($LASTEXITCODE -ne 0) { throw ('Não foi possível proteger a pasta {0}: {1}' -f $Pasta, (@($saida) -join ' ')) }
}

function Initialize-LacadorPastaDados {
    <# Cria e protege C:\ProgramData\Lacador. Precisa de administrador.
       -ComFila cria também a fila de pedidos usada pela tarefa agendada (modo instalado). #>
    param([switch]$ComFila)
    $dados = Get-LacadorPastaDados
    Protect-LacadorPasta $dados -UsuariosLeem
    foreach ($n in 'logs', 'firefox') { Protect-LacadorPasta (Join-Path $dados $n) -UsuariosLeem }
    if ($ComFila) {
        Protect-LacadorPasta (Join-Path $dados 'respostas') -UsuariosLeem
        Protect-LacadorPasta (Join-Path $dados 'pedidos') -UsuariosCriam
    }
    return $dados
}

function New-LacadorPastaPreparo {
    # Pasta temporária só do SYSTEM e dos Administradores. Os instaladores são copiados para cá,
    # conferidos e executados daqui: assim ninguém troca o arquivo entre a conferência e a execução.
    $p = Join-Path ([IO.Path]::GetTempPath()) ('lacador-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $p -ErrorAction Stop | Out-Null
    Protect-LacadorPasta $p
    if (@(Get-ChildItem -LiteralPath $p -Force).Count) { throw 'A pasta de preparo não está vazia.' }
    return $p
}

function Start-LacadorProcesso {
    param([string]$Arquivo, [string]$Argumentos, [int]$TempoMaxSeg = 900, [string]$PastaTrabalho)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Arquivo
    $psi.Arguments = $Argumentos
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    if ($PastaTrabalho) { $psi.WorkingDirectory = $PastaTrabalho }
    $p = [System.Diagnostics.Process]::Start($psi)
    if (-not $p.WaitForExit($TempoMaxSeg * 1000)) {
        try { $p.Kill() } catch { }
        return [ordered]@{ codigo = -1; tempoEsgotado = $true }
    }
    return [ordered]@{ codigo = [int]$p.ExitCode; tempoEsgotado = $false }
}

function Test-LacadorHash {
    param([string]$Arquivo, [string]$Sha256)
    $h = (Get-FileHash -LiteralPath $Arquivo -Algorithm SHA256).Hash
    return ($h -eq $Sha256.ToUpperInvariant())
}

function Test-LacadorBlocoWmic {
    # Roda o bloco novo num .bat temporário, em 64 e em 32 bits, antes de alterar qualquer arquivo.
    param([scriptblock]$Registrar)
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ('lacador-teste-memoria-{0}.bat' -f ([guid]::NewGuid().ToString('N').Substring(0, 8)))
    $linhas = @('@echo off') + $script:BlocoWmic + @(
        'echo FREEMEMORY=[%FREEMEMORY%]',
        'IF %FREEMEMORY% LSS 262144 (echo RESULTADO=POUCA) else (echo RESULTADO=OK)'
    )
    [IO.File]::WriteAllText($tmp, (($linhas -join "`r`n") + "`r`n"), [Text.Encoding]::ASCII)
    $cmd64 = Join-Path $env:windir 'Sysnative\cmd.exe'
    if (-not (Test-Path -LiteralPath $cmd64)) { $cmd64 = Join-Path $env:windir 'System32\cmd.exe' }
    $ok = $true
    $testados = 0
    foreach ($par in @(@('64 bits', $cmd64), @('32 bits', (Join-Path $env:windir 'SysWOW64\cmd.exe')))) {
        if (-not (Test-Path -LiteralPath $par[1])) { continue }
        $testados++
        $saida = ''
        try { $saida = (& $par[1] /d /c $tmp 2>&1 | Out-String) } catch { $saida = $_.Exception.Message }
        if ($saida -match 'RESULTADO=(OK|POUCA)') {
            if ($Registrar) { & $Registrar ('Teste do novo método em {0}: OK' -f $par[0]) }
        } else {
            $ok = $false
            if ($Registrar) { & $Registrar ('Teste do novo método em {0}: FALHOU - {1}' -f $par[0], (($saida -replace '\s+', ' ').Trim())) }
        }
    }
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    return ($ok -and $testados -gt 0)
}

function Update-LacadorBat {
    # Troca as 2 linhas do WMIC pelo bloco novo. Retorna: CORRIGIDO | JA_CORRIGIDO | SEM_WMIC | FORMATO_DIFERENTE | ERRO_VERIFICACAO
    param([string]$Arquivo, [Text.Encoding]$Codificacao = [Text.Encoding]::Default)
    $linhas = [IO.File]::ReadAllLines($Arquivo, $Codificacao)
    if (($linhas -join "`n") -match $script:MarcadorWmic) { return 'JA_CORRIGIDO' }
    $iSet = -1
    for ($i = 0; $i -lt $linhas.Count; $i++) {
        if ($linhas[$i] -match '^\s*set\s+torun\s*=.*wmic') { $iSet = $i; break }
    }
    if ($iSet -lt 0 -or ($iSet + 1) -ge $linhas.Count -or $linhas[$iSet + 1] -notmatch '^\s*for\s+/f.*%torun%') {
        if (Test-LacadorUsaWmic $linhas) { return 'FORMATO_DIFERENTE' }
        return 'SEM_WMIC'
    }
    $orig = "$Arquivo.original"
    if (-not (Test-Path -LiteralPath $orig)) { Copy-Item -LiteralPath $Arquivo -Destination $orig }
    $antes = @()
    if ($iSet -gt 0) { $antes = $linhas[0..($iSet - 1)] }
    $depois = @()
    if (($iSet + 2) -lt $linhas.Count) { $depois = $linhas[($iSet + 2)..($linhas.Count - 1)] }
    $novas = @($antes) + $script:BlocoWmic + @($depois)
    [IO.File]::WriteAllText($Arquivo, (($novas -join "`r`n") + "`r`n"), $Codificacao)
    $conf = [IO.File]::ReadAllLines($Arquivo, $Codificacao)
    if ((($conf -join "`n") -match $script:MarcadorWmic) -and -not (Test-LacadorUsaWmic $conf)) { return 'CORRIGIDO' }
    Copy-Item -LiteralPath $orig -Destination $Arquivo -Force
    return 'ERRO_VERIFICACAO'
}

function Repair-LacadorWmicAssinador {
    param([scriptblock]$Registrar)
    $pastas = @(Get-LacadorPastasAssinador (Get-LacadorProgramas))
    if (-not $pastas.Count) { throw 'O Assinador do COMAER não está instalado.' }
    $bats = @(foreach ($p in $pastas) { Get-ChildItem -LiteralPath $p -Filter '*.bat' -File -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName } })
    $precisam = @($bats | Where-Object {
        $l = [IO.File]::ReadAllLines($_, [Text.Encoding]::Default)
        (($l -join "`n") -notmatch $script:MarcadorWmic) -and (Test-LacadorUsaWmic $l)
    })
    if (-not $precisam.Count) { return 'Correção do WMIC: já estava aplicada.' }
    if (-not (Test-LacadorBlocoWmic $Registrar)) { throw 'O teste do novo método de leitura de memória falhou; nenhum arquivo foi alterado.' }
    $problemas = 0
    foreach ($b in $precisam) {
        $s = Update-LacadorBat $b
        if ($Registrar) { & $Registrar ('{0}: {1}' -f $b, $s) }
        if ($s -in 'FORMATO_DIFERENTE', 'ERRO_VERIFICACAO') { $problemas++ }
    }
    if ($problemas) { throw 'Um dos inicializadores do assinador estava num formato diferente do esperado e não foi alterado.' }
    return ('Correção do WMIC aplicada em {0}.' -f (Get-LacadorPlural $precisam.Count 'arquivo' 'arquivos'))
}

function Repair-LacadorLigacaoFirefox {
    $pastas = @(Get-LacadorPastasAssinador (Get-LacadorProgramas))
    if (-not $pastas.Count) { throw 'O Assinador do COMAER não está instalado.' }
    $manifesto = Join-Path $pastas[0] 'assinador_comaer.json'
    if (-not (Test-Path -LiteralPath $manifesto)) { throw ('Não encontrei o arquivo {0}. Reinstale o assinador.' -f $manifesto) }
    $vistas = @(64)
    if ([Environment]::Is64BitOperatingSystem) { $vistas = @(64, 32) }
    foreach ($v in $vistas) {
        $k = Open-LacadorChave 'HKLM' $v 'SOFTWARE\Mozilla\NativeMessagingHosts\assinador_comaer' $true $true
        $k.SetValue('', $manifesto)
        $k.Close()
    }
    return 'Ligação do assinador com o Firefox registrada.'
}

function Set-LacadorPoliticaFirefox {
    # -Reforcar: além da política da extensão, aplica o procedimento da ATIC (o Firefox aceita a assinatura antiga
    # da extensão). Usado no Reparar, quando o Firefox abriu e mesmo assim não instalou a extensão.
    param($Item, $Config, [string]$PastaPacotes, [switch]$Reforcar)
    $pac = @($Item.pacotes)[0]
    $origem = Join-Path $PastaPacotes ([IO.Path]::GetFileName([string]$pac.arquivo))
    $dir = Join-Path (Initialize-LacadorPastaDados) 'firefox'
    $destino = Join-Path $dir $script:NomeXpiLocal
    if (Test-Path -LiteralPath $destino) { Remove-Item -LiteralPath $destino -Force }
    Copy-Item -LiteralPath $origem -Destination $destino -Force
    if ($pac.sha256 -and -not (Test-LacadorHash $destino ([string]$pac.sha256))) {
        Remove-Item -LiteralPath $destino -Force -ErrorAction SilentlyContinue
        throw 'A extensão copiada não confere com o catálogo (SHA-256 diferente).'
    }
    $url = 'file:///' + (($destino -replace '\\', '/') -replace ' ', '%20')
    $chave = 'SOFTWARE\Policies\Mozilla\Firefox'
    $k = Open-LacadorChave 'HKLM' 64 $chave $true $true
    try {
        $obj = $null
        $atual = $k.GetValue('ExtensionSettings')
        if ($atual) { try { $obj = (@($atual) -join "`n") | ConvertFrom-Json } catch { $obj = $null } }
        if (-not $obj) { $obj = New-Object psobject }
        $modo = [string]$Config.firefox.modoInstalacaoExtensao
        if ($modo -notin 'force_installed', 'normal_installed') { $modo = 'force_installed' }
        # default_area = navbar: o botão do assinador já entra fixado na barra do Firefox (Firefox 113 ou mais novo).
        $entrada = [pscustomobject][ordered]@{ installation_mode = $modo; install_url = $url; temporarily_allow_weak_signatures = $true; default_area = 'navbar' }
        $obj | Add-Member -NotePropertyName ([string]$Item.extensaoId) -NotePropertyValue $entrada -Force
        $linhas = [string[]]((ConvertTo-Json -InputObject $obj -Depth 10) -split "`r?`n")
        $k.SetValue('ExtensionSettings', $linhas, [Microsoft.Win32.RegistryValueKind]::MultiString)

        if ($Config.firefox.aplicarPreferenciasProcedimentoAtic -or $Reforcar) {
            $prefs = $null
            $pAtual = $k.GetValue('Preferences')
            if ($pAtual) { try { $prefs = (@($pAtual) -join "`n") | ConvertFrom-Json } catch { $prefs = $null } }
            if (-not $prefs) { $prefs = New-Object psobject }
            foreach ($nome in 'xpinstall.signatures.required', 'extensions.blocklist.enabled') {
                $prefs | Add-Member -NotePropertyName $nome -NotePropertyValue ([pscustomobject][ordered]@{ Value = $false; Status = 'locked' }) -Force
            }
            $k.SetValue('Preferences', [string[]]((ConvertTo-Json -InputObject $prefs -Depth 10) -split "`r?`n"), [Microsoft.Win32.RegistryValueKind]::MultiString)
        }
    } finally { $k.Close() }
    try {
        $kl = Open-LacadorChave 'HKLM' 64 $script:ChaveLacador $true $true
        $kl.SetValue('ExtensaoPoliticaEm', (Get-Date).ToString('s'))
        $kl.Close()
    } catch { }
    if ($Reforcar) { return 'Política do Firefox gravada com o procedimento da ATIC: feche e abra o Firefox para a extensão entrar, já fixada na barra.' }
    return 'Política do Firefox gravada: a extensão entra sozinha, já fixada na barra, na próxima abertura do Firefox.'
}

function Remove-LacadorPoliticaFirefox {
    # Desinstalar a extensão: a política passa a bloquear o assinador, e o Firefox a remove na próxima abertura.
    param($Item)
    $chave = 'SOFTWARE\Policies\Mozilla\Firefox'
    $k = Open-LacadorChave 'HKLM' 64 $chave $true $true
    try {
        $obj = $null
        $atual = $k.GetValue('ExtensionSettings')
        if ($atual) { try { $obj = (@($atual) -join "`n") | ConvertFrom-Json } catch { $obj = $null } }
        if (-not $obj) { $obj = New-Object psobject }
        $obj | Add-Member -NotePropertyName ([string]$Item.extensaoId) -NotePropertyValue ([pscustomobject][ordered]@{ installation_mode = 'blocked' }) -Force
        $k.SetValue('ExtensionSettings', [string[]]((ConvertTo-Json -InputObject $obj -Depth 10) -split "`r?`n"), [Microsoft.Win32.RegistryValueKind]::MultiString)
    } finally { $k.Close() }
    try { Remove-Item -LiteralPath (Join-Path (Join-Path (Get-LacadorPastaDados) 'firefox') $script:NomeXpiLocal) -Force -ErrorAction SilentlyContinue } catch { }
    return 'Extensão removida da política: o Firefox tira o assinador na próxima vez que for aberto.'
}

function Get-LacadorComandoDesinstalar {
    # Monta o comando de desinstalação a partir do registro (HKLM, que só o administrador altera).
    param($Programa, [string]$Tipo)
    $us = [string]$Programa.desinstalar
    $guid = ''
    if ([string]$Programa.chave -match '^\{[0-9A-Fa-f-]{36}\}$') { $guid = [string]$Programa.chave }
    elseif ($us -match '(\{[0-9A-Fa-f-]{36}\})') { $guid = $matches[1] }
    if ($Tipo -eq 'msi' -or [bool]$Programa.msi -or $us -match '(?i)msiexec') {
        if (-not $guid) { throw ('Não achei o código de instalação de {0}.' -f $Programa.nome) }
        return [ordered]@{ arquivo = ('{0}\System32\msiexec.exe' -f $env:windir); argumentos = ('/x {0} /qn /norestart' -f $guid) }
    }
    $exe = ''
    if ($us -match '^\s*"([^"]+)"') { $exe = $matches[1] }
    elseif ($us -match '^\s*(.+?\.exe)') { $exe = $matches[1] }
    if (-not $exe -or -not [IO.Path]::IsPathRooted($exe) -or -not (Test-Path -LiteralPath $exe)) { throw ('O desinstalador de {0} não foi encontrado.' -f $Programa.nome) }
    $arg = '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART'
    if ($Tipo -eq 'nsis') { $arg = '/S' }
    return [ordered]@{ arquivo = $exe; argumentos = $arg }
}

function Invoke-LacadorDesinstalacao {
    param($Item, $Catalogo, $Config, [scriptblock]$Log)
    $tipo = [string]$Item.desinstalar.tipo
    if (-not $tipo) { throw 'Este item não pode ser desinstalado pelo Laçador.' }
    if ($tipo -eq 'politica') { & $Log (Remove-LacadorPoliticaFirefox $Item); return }
    $f = Get-LacadorFatos -Catalogo $Catalogo -Config $Config -Rapido
    $det = $Item.detectar
    $padrao = [string]$Item.desinstalar.programa
    $alvos = @(@($f.programas) | Where-Object {
        $_ -and ([string](Get-LacadorProp $_ 'origem')) -like 'HKLM*' -and (
            ($padrao -and [string]$_.nome -match $padrao) -or
            (-not $padrao -and $det.chave -and $_.chave -eq $det.chave) -or
            (-not $padrao -and $det.programa -and ([string]$_.nome -match [string]$det.programa) -and ((-not $det.fabricante) -or ([string]$_.fabricante -match [string]$det.fabricante)))
        )
    })
    if (-not $alvos.Count) { throw 'Não está instalado (nada a desinstalar).' }
    foreach ($a in $alvos) {
        $c = Get-LacadorComandoDesinstalar $a $tipo
        & $Log ('Desinstalando {0} {1}' -f $a.nome, $a.versao)
        $r = Start-LacadorProcesso $c.arquivo $c.argumentos 900 $null
        if ($r.tempoEsgotado) { throw ('O desinstalador de {0} não terminou no tempo previsto.' -f $a.nome) }
        if ($r.codigo -notin 0, 3010, 1641, 1605) { throw ('O desinstalador de {0} terminou com o código {1}.' -f $a.nome, $r.codigo) }
    }
    # Alguns desinstaladores devolvem o controle e continuam trabalhando: espera o programa sumir.
    $limite = (Get-Date).AddSeconds(180)
    do {
        Start-Sleep -Seconds 3
        $f2 = Get-LacadorFatos -Catalogo $Catalogo -Config $Config -Rapido
        $ainda = @(@($f2.programas) | Where-Object { $p = $_; @($alvos | Where-Object { $_.chave -eq $p.chave -and $_.nome -eq $p.nome }).Count })
    } while ($ainda.Count -and (Get-Date) -lt $limite)
    if ($ainda.Count) { throw 'O desinstalador terminou, mas o programa continua aparecendo como instalado.' }
    & $Log 'Desinstalado.'
}

function Disable-LacadorAtualizacaoJava {
    $vistas = @(64)
    if ([Environment]::Is64BitOperatingSystem) { $vistas = @(32, 64) }
    foreach ($v in $vistas) {
        $tem = Open-LacadorChave 'HKLM' $v 'SOFTWARE\JavaSoft'
        if (-not $tem) { continue }
        $tem.Close()
        $k = Open-LacadorChave 'HKLM' $v 'SOFTWARE\JavaSoft\Java Update\Policy' $true $true
        foreach ($n in 'EnableJavaUpdate', 'EnableAutoUpdateCheck', 'NotifyDownload', 'NotifyInstall') { $k.SetValue($n, 0, [Microsoft.Win32.RegistryValueKind]::DWord) }
        $k.Close()
        $run = Open-LacadorChave 'HKLM' $v 'SOFTWARE\Microsoft\Windows\CurrentVersion\Run' $true
        if ($run) {
            if ($null -ne $run.GetValue('SunJavaUpdateSched')) { $run.DeleteValue('SunJavaUpdateSched', $false) }
            $run.Close()
        }
    }
    return 'Atualização automática do Java desligada.'
}

function Set-LacadorAssociacaoJnlp {
    $java = Get-LacadorJavaFatos
    $jre = @(@($java.jres) | Where-Object { $_.versao -eq '1.8.0_91' -and $_.javaws }) | Select-Object -First 1
    if (-not $jre) { return 'Java 8u91 não instalado: a ligação dos arquivos .jnlp não foi alterada.' }
    $javaws = Join-Path ([string]$jre.pasta) 'bin\javaws.exe'
    $k = Open-LacadorChave 'HKLM' 64 'SOFTWARE\Classes\.jnlp' $true $true
    $k.SetValue('', 'JNLPFile'); $k.SetValue('Content Type', 'application/x-java-jnlp-file'); $k.Close()
    $k = Open-LacadorChave 'HKLM' 64 'SOFTWARE\Classes\JNLPFile' $true $true
    if (-not $k.GetValue('')) { $k.SetValue('', 'JNLP File') }
    $k.Close()
    $k = Open-LacadorChave 'HKLM' 64 'SOFTWARE\Classes\JNLPFile\shell\open\command' $true $true
    $k.SetValue('', ('"{0}" "%1"' -f $javaws)); $k.Close()
    return 'Arquivos .jnlp ligados ao Java 8u91.'
}

function Repair-LacadorServicoSmartCard {
    $s = Get-Service -Name 'SCardSvr' -ErrorAction SilentlyContinue
    if (-not $s) { return 'Serviço "Cartão inteligente" não existe neste Windows.' }
    if ([string]$s.StartType -eq 'Disabled') { Set-Service -Name 'SCardSvr' -StartupType Manual }
    try { Start-Service -Name 'SCardSvr' -ErrorAction Stop } catch { }
    return 'Serviço "Cartão inteligente" conferido.'
}

function Invoke-LacadorPosPasso {
    param([string]$Passo, $Item, $Config, [string]$PastaPacotes, [scriptblock]$Registrar)
    switch ($Passo) {
        'corrigir-wmic'        { return (Repair-LacadorWmicAssinador $Registrar) }
        'ligacao-firefox'      { return (Repair-LacadorLigacaoFirefox) }
        'politica-firefox'     { return (Set-LacadorPoliticaFirefox $Item $Config $PastaPacotes -Reforcar:([bool]$script:LacadorReforcar)) }
        'java-sem-atualizacao' { return (Disable-LacadorAtualizacaoJava) }
        'associar-jnlp'        { return (Set-LacadorAssociacaoJnlp) }
        'servico-smartcard'    { return (Repair-LacadorServicoSmartCard) }
        default                { return ('Passo desconhecido ignorado: {0}' -f $Passo) }
    }
}

function Invoke-LacadorItem {
    <# Instala ou repara UM item do catálogo. Roda com privilégio (agente). Devolve { ok, mensagens, reiniciar }. #>
    param($Item, [string]$Acao, $Catalogo, $Config, [switch]$Simular, [scriptblock]$Registrar)
    $msgs = New-Object System.Collections.Generic.List[string]
    $reiniciar = $false
    $preparo = $null
    $log = {
        param($t)
        $msgs.Add([string]$t)
        if ($Registrar) { & $Registrar ('[{0}] {1}' -f $Item.id, $t) }
    }
    try {
        if ($Simular) {
            Start-Sleep -Milliseconds 1100
            & $log 'Simulação: nada foi instalado.'
            return [ordered]@{ ok = $true; mensagens = $msgs.ToArray(); reiniciar = $false }
        }
        if ($Acao -eq 'desinstalar') {
            Invoke-LacadorDesinstalacao $Item $Catalogo $Config $log
            return [ordered]@{ ok = $true; mensagens = $msgs.ToArray(); reiniciar = $false }
        }
        $pasta = Get-LacadorPastaPacotes $Config
        $estadoDe = {
            $f = Get-LacadorFatos -Catalogo $Catalogo -Config $Config -Rapido
            return (Get-LacadorEstadoItem $Item $f $Catalogo $Config)
        }
        $est = & $estadoDe
        if ($est.estado -eq 'conflito') { throw $est.detalhe }
        $arq = 'x64'
        if (-not [Environment]::Is64BitOperatingSystem) { $arq = 'x86' }
        $pacs = @(Get-LacadorPacotesDoItem $Item $arq)
        # instalar: não está (ou versão antiga). reinstalar: está, mas quebrado (falta arquivo) ou o usuário pediu Reparar.
        $modo = ''
        if ($est.estado -eq 'ausente' -or $est.acao -eq 'instalar') { $modo = 'instalar' }
        elseif ($Item.reinstalar -and $pacs.Count -and ($est.reinstalar -or $Acao -eq 'reparar')) { $modo = 'reinstalar' }
        if ($Item.id -eq 'firefox-esr') {
            # O Developer Edition é o padrão; pedir para instalar com ele presente instala o ESR, a reserva.
            if ($Acao -eq 'instalar' -and -not $est.temEsr) { $modo = 'instalar' }
            elseif ($modo -eq 'reinstalar' -and -not $est.temEsr) { $modo = '' }
        }
        $precisaInstalar = [bool]$modo
        # Reparar a extensão = gravar de novo a política, agora com o procedimento da ATIC.
        $script:LacadorReforcar = ($Item.id -eq 'extensao-firefox' -and $Acao -eq 'reparar')

        # Copia os arquivos para uma pasta protegida e confere a cópia (SHA-256 do catálogo) antes de qualquer coisa.
        if (($precisaInstalar -or $Item.id -eq 'extensao-firefox') -and $pacs.Count) {
            $preparo = New-LacadorPastaPreparo
            foreach ($p in $pacs) {
                $nomeArq = [IO.Path]::GetFileName([string]$p.arquivo)
                if (-not $p.sha256) { throw ('O catálogo não tem o SHA-256 de {0}. Não foi executado.' -f $nomeArq) }
                $copia = Join-Path $preparo $nomeArq
                Copy-LacadorPacote $nomeArq $copia $Config
                if (-not (Test-LacadorHash $copia ([string]$p.sha256))) {
                    throw ('O arquivo {0} não confere com o catálogo (SHA-256 diferente). Não foi executado.' -f $nomeArq)
                }
            }
            $pasta = $preparo
        }

        $rodarPacotes = {
            param([string]$Como)
            foreach ($p in $pacs) {
                $arquivo = Join-Path $pasta ([IO.Path]::GetFileName([string]$p.arquivo))
                $args2 = [string]$p.argumentos
                if ($Como -eq 'reinstalar' -and $p.argumentosReinstalar) { $args2 = [string]$p.argumentosReinstalar }
                if ($p.registroMsi -and $args2 -match '/v"') {
                    # Registro detalhado do Windows Installer, para o relatório do suporte (caminho sem espaços).
                    try {
                        $pl = Join-Path (Get-LacadorPastaDados) 'logs'
                        if (-not (Test-Path -LiteralPath $pl)) { New-Item -ItemType Directory -Path $pl -Force | Out-Null }
                        $lm = Join-Path $pl ('msi-{0}-{1}.log' -f $Item.id, $Como)
                        if ($lm -notmatch '\s') { $args2 = $args2 -replace '/v"', ('/v"/l*v ' + $lm + ' ') }
                    } catch { }
                }
                $r = $null
                if ($p.tipo -eq 'exe') {
                    if ($Item.id -eq 'adobe-xi' -and $est.versaoInstalada) { & $log 'Adobe Reader XI já instalado: aplicando só a atualização.'; continue }
                    if ($Item.id -eq 'firefox-esr') {
                        $f0 = Get-LacadorFatos -Catalogo $Catalogo -Config $Config -Rapido
                        $outro = @(@($f0.firefox.instalacoes) | Where-Object { (Get-LacadorEdicaoDe $_) -ne 'esr' -and ([string]$_.pasta -match '\\Mozilla Firefox$') })
                        if ($outro.Count) { $args2 = $args2 + ' /InstallDirectoryName="Mozilla Firefox ESR"'; & $log 'Já existe outro Firefox na pasta padrão: o ESR vai para uma pasta separada.' }
                    }
                    if ($Como -eq 'reinstalar') { & $log ('Reinstalando por cima: {0}' -f $p.arquivo) } else { & $log ('Executando {0}' -f $p.arquivo) }
                    $r = Start-LacadorProcesso $arquivo $args2 ([int]$Item.tempoMaxSeg) (Split-Path -Parent $arquivo)
                } elseif ($p.tipo -eq 'msp') {
                    & $log ('Aplicando a atualização {0}' -f $p.arquivo)
                    $msi = Join-Path $env:windir 'System32\msiexec.exe'
                    $r = Start-LacadorProcesso $msi ('/p "{0}" /qn /norestart' -f $arquivo) ([int]$Item.tempoMaxSeg) $null
                } else { continue }
                if ($r.tempoEsgotado) { throw ('O instalador {0} não terminou no tempo previsto e foi encerrado.' -f $p.arquivo) }
                if ($r.codigo -eq 3010 -or $r.codigo -eq 1641) { $script:LacadorReiniciar = $true }
                elseif ($r.codigo -ne 0) { throw ('O instalador {0} terminou com o código {1}.' -f $p.arquivo, $r.codigo) }
            }
        }
        $script:LacadorReiniciar = $false
        if ($Item.categoria -ne 'ambiente' -and $modo -eq 'instalar') {
            & $rodarPacotes 'instalar'
            # Espera o programa aparecer como instalado (alguns instaladores devolvem o controle antes do fim)
            if ($Item.id -ne 'extensao-firefox') {
                $limite = (Get-Date).AddSeconds(120)
                do {
                    $est = & $estadoDe
                    if ($est.estado -ne 'ausente' -and -not ($Item.id -eq 'firefox-esr' -and -not $est.temEsr)) { break }
                    Start-Sleep -Seconds 4
                } while ((Get-Date) -lt $limite)
                if ($est.estado -eq 'ausente') { throw 'O instalador terminou, mas o programa não apareceu como instalado.' }
                & $log 'Instalação concluída.'
            }
        } elseif ($Item.categoria -ne 'ambiente' -and $modo -eq 'reinstalar') {
            # Reinstalação forçada (por exemplo: o SafeSign consta como instalado, mas a biblioteca do token sumiu).
            $falhou = ''
            try { & $rodarPacotes 'reinstalar' } catch { $falhou = $_.Exception.Message }
            if (-not $falhou) { Start-Sleep -Seconds 3; $est = & $estadoDe }
            if ($falhou -or $est.reinstalar) {
                if ($falhou) { & $log ('A reinstalação por cima não deu certo ({0}).' -f $falhou) } else { & $log 'Depois da reinstalação por cima ainda faltam arquivos.' }
                if (-not $Item.desinstalar) { throw 'Não foi possível reinstalar.' }
                & $log 'Removendo a instalação quebrada para instalar do zero...'
                Invoke-LacadorDesinstalacao $Item $Catalogo $Config $log
                & $rodarPacotes 'instalar'
                $limite = (Get-Date).AddSeconds(120)
                do { $est = & $estadoDe; if ($est.estado -ne 'ausente' -and -not $est.reinstalar) { break }; Start-Sleep -Seconds 4 } while ((Get-Date) -lt $limite)
            }
            & $log 'Reinstalação concluída.'
        }
        if ($script:LacadorReiniciar) { $reiniciar = $true }

        foreach ($d in @($Item.depois)) {
            if (-not $d) { continue }
            & $log (Invoke-LacadorPosPasso ([string]$d) $Item $Config $pasta $Registrar)
        }

        $est = & $estadoDe
        if ($est.estado -eq 'ok') { return [ordered]@{ ok = $true; mensagens = $msgs.ToArray(); reiniciar = $reiniciar } }
        $pend = @($est.verificacoes | Where-Object { -not $_.ok -and -not $_.informativa } | ForEach-Object { $_.detalhe })
        if (-not $pend.Count) { $pend = @($est.detalhe) }
        & $log ('Ainda pendente: {0}' -f ($pend -join '; '))
        return [ordered]@{ ok = $false; mensagens = $msgs.ToArray(); reiniciar = $reiniciar }
    } catch {
        & $log ('ERRO: {0}' -f $_.Exception.Message)
        return [ordered]@{ ok = $false; mensagens = $msgs.ToArray(); reiniciar = $reiniciar }
    } finally {
        if ($preparo) { Remove-Item -LiteralPath $preparo -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

function Test-LacadorPedido {
    # Valida um pedido vindo do usuário. Devolve $null se estiver bom, ou o motivo da recusa.
    param($Pedido, $Catalogo)
    if (-not $Pedido) { return 'pedido vazio' }
    if ([string]$Pedido.id -notmatch '^[0-9a-f]{32}$') { return 'identificador inválido' }
    if ([string]$Pedido.acao -notin 'instalar', 'reparar', 'desinstalar') { return 'ação inválida' }
    $itens = @($Pedido.itens)
    if ($itens.Count -lt 1 -or $itens.Count -gt 20) { return 'lista de itens inválida' }
    $validos = @($Catalogo.itens | ForEach-Object { [string]$_.id })
    foreach ($i in $itens) {
        if ([string]$i -notmatch '^[a-z0-9-]{1,40}$') { return 'item com nome inválido' }
        if ($validos -notcontains [string]$i) { return ('item fora do catálogo: {0}' -f $i) }
        if ([string]$Pedido.acao -eq 'desinstalar' -and -not (@($Catalogo.itens | Where-Object { $_.id -eq [string]$i })[0].desinstalar)) { return ('o Laçador não desinstala: {0}' -f $i) }
    }
    return $null
}

function Invoke-LacadorPedido {
    <# Executa um pedido já validado e vai gravando o andamento no arquivo de resposta. #>
    param($Pedido, [string]$ArquivoResposta, [switch]$Simular, [scriptblock]$Registrar)
    $cat = Get-LacadorCatalogo
    $cfg = Get-LacadorConfig
    if ([string]$Pedido.acao -eq 'desinstalar') {
        # Desinstalar: só o que foi pedido, sem dependências, do último para o primeiro do catálogo.
        $pedidos = @($Pedido.itens | ForEach-Object { [string]$_ })
        $ordem = @($cat.itens | Where-Object { $pedidos -contains [string]$_.id } | ForEach-Object { [string]$_.id })
        [array]::Reverse($ordem)
    } else {
        $ordem = @(Resolve-LacadorPlano -Catalogo $cat -Itens @($Pedido.itens | ForEach-Object { [string]$_ }))
    }
    $resp = [ordered]@{
        id = [string]$Pedido.id; acao = [string]$Pedido.acao; estado = 'executando'
        inicio = (Get-Date).ToString('s'); fim = $null; reiniciar = $false; simulado = [bool]$Simular
        passos = @($ordem | ForEach-Object {
            $id = $_
            [ordered]@{ item = $id; nome = [string](@($cat.itens | Where-Object { $_.id -eq $id })[0].nome); estado = 'pendente'; mensagens = @() }
        })
    }
    $gravar = { if ($ArquivoResposta) { try { Write-LacadorJson $ArquivoResposta $resp } catch { } } }
    & $gravar
    $falhas = 0
    foreach ($passo in $resp.passos) {
        $passo.estado = 'executando'
        & $gravar
        $it = @($cat.itens | Where-Object { $_.id -eq $passo.item })[0]
        $r = Invoke-LacadorItem -Item $it -Acao ([string]$Pedido.acao) -Catalogo $cat -Config $cfg -Simular:$Simular -Registrar $Registrar
        $passo.mensagens = @($r.mensagens)
        if ($r.ok) { $passo.estado = 'ok' } else { $passo.estado = 'erro'; $falhas++ }
        if ($r.reiniciar) { $resp.reiniciar = $true }
        & $gravar
    }
    $resp.fim = (Get-Date).ToString('s')
    if ($falhas) { $resp.estado = 'erro' } else { $resp.estado = 'concluido' }
    & $gravar
    return $resp
}

#endregion

#region Operações do usuário (sem privilégio) ----------------------------------

function Get-LacadorFirefoxPreferido {
    # O padrão da base é o Developer Edition; o ESR é a reserva. -Edicao escolhe um dos dois.
    param([string]$Edicao)
    $inst = @(Get-LacadorFirefoxInstalacoes)
    $ordem = @('developer', 'esr')
    if ($Edicao) { $ordem = @($Edicao) }
    foreach ($ed in $ordem) {
        $b = @($inst | Where-Object { $_.edicao -eq $ed }) | Select-Object -First 1
        if ($b) { return [string]$b.exe }
    }
    if ($Edicao) { return '' }
    $b = $inst | Select-Object -First 1
    if ($b) { return [string]$b.exe }
    return ''
}

function Set-LacadorBotaoNaBarra {
    # Põe o botão do assinador na barra do Firefox, num perfil. O Firefox precisa estar fechado.
    # Devolve: 'fixado', 'ja-estava' ou 'sem-estado' (o Firefox ainda não gravou a barra deste perfil).
    param([string]$PastaPerfil, [string]$IdBotao)
    $prefs = Join-Path $PastaPerfil 'prefs.js'
    if (-not (Test-Path -LiteralPath $prefs)) { return 'sem-estado' }
    $txt = [IO.File]::ReadAllText($prefs, [Text.Encoding]::UTF8)
    $re = 'user_pref\("browser\.uiCustomization\.state",\s*"((?:[^"\\]|\\.)*)"\);'
    $m = [regex]::Match($txt, $re)
    if (-not $m.Success) { return 'sem-estado' }
    $estado = ($m.Groups[1].Value -replace '\\(.)', '$1') | ConvertFrom-Json
    if (-not $estado.placements) { return 'sem-estado' }
    if ((Test-LacadorExtensaoFixada $estado $IdBotao) -eq $true) { return 'ja-estava' }
    foreach ($area in @($estado.placements.PSObject.Properties)) {
        $area.Value = @(@($area.Value) | Where-Object { $_ -ne $IdBotao })
    }
    $nav = @()
    $prop = $estado.placements.PSObject.Properties['nav-bar']
    if ($prop) { $nav = @($prop.Value) }
    $pos = [array]::IndexOf([object[]]$nav, 'unified-extensions-button')
    if ($pos -lt 0) { $nav = @($nav) + $IdBotao }
    elseif ($pos -eq 0) { $nav = @($IdBotao) + $nav }
    else { $nav = @($nav[0..($pos - 1)]) + $IdBotao + @($nav[$pos..($nav.Count - 1)]) }
    if ($prop) { $prop.Value = $nav } else { $estado.placements | Add-Member -NotePropertyName 'nav-bar' -NotePropertyValue $nav }
    $visto = $estado.PSObject.Properties['seen']
    if ($visto -and (@($visto.Value) -notcontains $IdBotao)) { $visto.Value = @(@($visto.Value) + $IdBotao) }
    $json = ConvertTo-Json -InputObject $estado -Depth 12 -Compress
    $linha = 'user_pref("browser.uiCustomization.state", "' + ($json -replace '\\', '\\' -replace '"', '\"') + '");'
    $copia = $prefs + '.lacador'
    if (-not (Test-Path -LiteralPath $copia)) { Copy-Item -LiteralPath $prefs -Destination $copia }
    $novo = $txt.Substring(0, $m.Index) + $linha + $txt.Substring($m.Index + $m.Length)
    [IO.File]::WriteAllText($prefs, $novo, (New-Object System.Text.UTF8Encoding($false)))
    return 'fixado'
}

function Close-LacadorFirefox {
    # Fecha o Firefox do jeito normal (como clicar no X); ele reabre as abas depois. Devolve $true se fechou.
    $ps = @(Get-Process -Name 'firefox' -ErrorAction SilentlyContinue)
    if (-not $ps.Count) { return $true }
    foreach ($p in $ps) { try { [void]$p.CloseMainWindow() } catch { } }
    $limite = (Get-Date).AddSeconds(12)
    while ((Get-Date) -lt $limite) {
        Start-Sleep -Milliseconds 400
        if (-not @(Get-Process -Name 'firefox' -ErrorAction SilentlyContinue).Count) { return $true }
    }
    return $false
}

function Add-LacadorTokenAoAssinador {
    # Acrescenta a linha token.<nome>=<biblioteca PKCS#11> no config.properties do Assinador do COMAER (do usuário).
    param([string]$Nome, [string]$Biblioteca)
    $arq = Get-LacadorCaminhoConfigAssinador
    if (-not $arq) { throw 'Não encontrei a pasta do usuário.' }
    $dll = (Expand-LacadorCaminho $Biblioteca) -replace '/', '\'
    if (-not (Test-Path -LiteralPath $dll)) { throw ('A biblioteca do token não está instalada: {0}. Instale o driver primeiro.' -f $dll) }
    $enc = [Text.Encoding]::GetEncoding(28591)
    $dir = Split-Path -Parent $arq
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $linhas = @()
    if (Test-Path -LiteralPath $arq) {
        $linhas = @([IO.File]::ReadAllLines($arq, $enc))
        if (-not (Test-Path -LiteralPath "$arq.original")) { Copy-Item -LiteralPath $arq -Destination "$arq.original" }
    }
    $nova = ('token.{0}={1}' -f $Nome, ($Biblioteca -replace '\\', '/'))
    $linhas = @($linhas | Where-Object { $_ -notmatch ('^\s*token\.{0}\s*=' -f [regex]::Escape($Nome)) })
    $linhas += $nova
    [IO.File]::WriteAllText($arq, (($linhas -join "`r`n") + "`r`n"), $enc)
    return ('Assinador do COMAER configurado para o token ({0}).' -f $nova)
}

function Invoke-LacadorOperacaoUsuario {
    <# Operações que não precisam de administrador. Devolve { ok, mensagem }. #>
    param([string]$Operacao, $Parametros)
    $cat = Get-LacadorCatalogo
    $cfg = Get-LacadorConfig
    try {
        switch ($Operacao) {
            'abrir-site' {
                $s = @($cat.sistemas | Where-Object { $_.id -eq [string]$Parametros.sistema })[0]
                if (-not $s -or -not $s.site) { throw 'Sistema sem site cadastrado.' }
                $url = [string](Get-LacadorProp $cfg.sites ([string]$s.site))
                if ($url -notmatch '^https?://') { throw 'Endereço do site não configurado em config.json.' }
                $nav = Get-LacadorNavegadores
                if ($s.navegador -eq 'firefox') {
                    $ff = Get-LacadorFirefoxPreferido
                    if ($ff) { Start-Process -FilePath $ff -ArgumentList ('"{0}"' -f $url); return [ordered]@{ ok = $true; mensagem = 'Abrindo no Firefox.' } }
                } elseif ($s.navegador -eq 'moderno') {
                    $exe = [string]$nav.chrome
                    if (-not $exe) { $exe = [string]$nav.edge }
                    if ($exe) { Start-Process -FilePath $exe -ArgumentList ('"{0}"' -f $url); return [ordered]@{ ok = $true; mensagem = 'Abrindo no navegador.' } }
                }
                Start-Process $url
                return [ordered]@{ ok = $true; mensagem = 'Abrindo no navegador padrão.' }
            }
            'abrir-programa' {
                $alvo = [string]$Parametros.alvo
                if ($alvo -eq 'assinador') {
                    $pastas = @(Get-LacadorPastasAssinador (Get-LacadorProgramas))
                    if (-not $pastas.Count) { throw 'O Assinador do COMAER não está instalado.' }
                    Start-Process -FilePath (Join-Path $pastas[0] 'assinador_standalone.bat') -WorkingDirectory $pastas[0]
                    return [ordered]@{ ok = $true; mensagem = 'Abrindo o Assinador do COMAER.' }
                }
                if ($alvo -eq 'adobe-xi') {
                    foreach ($pf in @(${env:ProgramFiles(x86)}, $env:ProgramFiles)) {
                        if ($pf) { $exe = Join-Path $pf 'Adobe\Reader 11.0\Reader\AcroRd32.exe'; if (Test-Path -LiteralPath $exe) { Start-Process -FilePath $exe; return [ordered]@{ ok = $true; mensagem = 'Abrindo o Adobe Reader.' } } }
                    }
                    throw 'O Adobe Reader XI não está instalado.'
                }
                if ($alvo -eq 'certificados') { Start-Process -FilePath 'certmgr.msc'; return [ordered]@{ ok = $true; mensagem = 'Abrindo os certificados do Windows.' } }
                if ($alvo -eq 'proxy-windows') { Start-Process 'ms-settings:network-proxy'; return [ordered]@{ ok = $true; mensagem = 'Abrindo as configurações de proxy.' } }
                if ($alvo -eq 'pasta-pacotes') {
                    $pastaPac = Get-LacadorPastaPacotes $cfg
                    $exePac = Get-LacadorRecipiente
                    if (-not (Test-Path -LiteralPath $pastaPac) -and $exePac) {
                        Start-Process -FilePath 'explorer.exe' -ArgumentList ('/select,"{0}"' -f $exePac)
                        return [ordered]@{ ok = $true; mensagem = 'Os instaladores ficam dentro do Lacador.exe.' }
                    }
                    if (-not (Test-Path -LiteralPath $pastaPac)) { throw 'A pasta de instaladores não existe.' }
                    Start-Process -FilePath 'explorer.exe' -ArgumentList ('"{0}"' -f $pastaPac)
                    return [ordered]@{ ok = $true; mensagem = 'Abrindo a pasta dos instaladores.' }
                }
                if ($alvo -eq 'carregar-pacotes') {
                    # Reserva para um Lacador.exe sem os instaladores dentro: junta os arquivos do TOKENS.rar numa pasta "pacotes".
                    $prep = Join-Path (Join-Path (Get-LacadorRaiz) 'ferramentas') 'Preparar-Pacotes.ps1'
                    if (-not (Test-Path -LiteralPath $prep)) { throw 'A ferramenta de instaladores não foi encontrada.' }
                    $exeBase = Get-LacadorRecipiente
                    if ($exeBase) {
                        # Monta um Lacador-completo.exe ao lado deste, com os instaladores dentro.
                        Start-Process -FilePath 'powershell.exe' -ArgumentList ('-NoProfile -STA -ExecutionPolicy Bypass -File "{0}" -Montar -Recipiente "{1}" -Pausar' -f $prep, $exeBase)
                        return [ordered]@{ ok = $true; mensagem = 'Escolha o arquivo TOKENS.rar na janela que abriu. No fim aparece o Lacador-completo.exe, ao lado deste.' }
                    }
                    Start-Process -FilePath 'powershell.exe' -ArgumentList ('-NoProfile -STA -ExecutionPolicy Bypass -File "{0}" -Destino "{1}" -Pausar' -f $prep, (Get-LacadorPastaPacotes $cfg))
                    return [ordered]@{ ok = $true; mensagem = 'Escolha o arquivo TOKENS.rar na janela que abriu. Depois clique em Verificar tudo.' }
                }
                if ($alvo -eq 'manual') {
                    $man = Join-Path (Get-LacadorRaiz) 'LEIA-ME.txt'
                    if (-not (Test-Path -LiteralPath $man)) { throw 'O manual não foi encontrado.' }
                    Start-Process -FilePath 'notepad.exe' -ArgumentList ('"{0}"' -f $man)
                    return [ordered]@{ ok = $true; mensagem = 'Abrindo o manual.' }
                }
                if ($alvo -eq 'pasta-registros') { Start-Process -FilePath 'explorer.exe' -ArgumentList ('"{0}"' -f (Get-LacadorPastaUsuario)); return [ordered]@{ ok = $true; mensagem = 'Abrindo a pasta de registros.' } }
                if ($alvo -like 'token:*') {
                    $t = @($cat.tokens | Where-Object { $_.id -eq $alvo.Substring(6) })[0]
                    if (-not $t) { throw 'Token fora do catálogo.' }
                    foreach ($c in @($t.administrador.caminhos)) {
                        $exe = Expand-LacadorCaminho ([string]$c)
                        if (Test-Path -LiteralPath $exe) { Start-Process -FilePath $exe; return [ordered]@{ ok = $true; mensagem = ('Abrindo: {0}' -f $t.administrador.nome) } }
                    }
                    throw ('{0} não está instalado.' -f $t.administrador.nome)
                }
                throw 'Programa desconhecido.'
            }
            'abrir-firefox' {
                if ($Parametros.reabrir -and @(Get-Process -Name 'firefox' -ErrorAction SilentlyContinue).Count) {
                    if (-not (Close-LacadorFirefox)) { throw 'O Firefox não fechou. Feche todas as janelas dele e tente de novo.' }
                    Start-Sleep -Milliseconds 800
                }
                $ed = [string]$Parametros.edicao
                if ($ed -and $ed -notin 'developer', 'esr') { throw 'Edição do Firefox inválida.' }
                $ff = Get-LacadorFirefoxPreferido $ed
                if (-not $ff) { throw 'Nenhum Firefox Developer Edition ou ESR instalado.' }
                $args3 = @()
                if ($Parametros.sistema) {
                    $s = @($cat.sistemas | Where-Object { $_.id -eq [string]$Parametros.sistema })[0]
                    if ($s -and $s.site) { $u = [string](Get-LacadorProp $cfg.sites ([string]$s.site)); if ($u -match '^https?://') { $args3 = @('"{0}"' -f $u) } }
                }
                if ($args3.Count) { Start-Process -FilePath $ff -ArgumentList $args3 } else { Start-Process -FilePath $ff }
                $nomeEd = 'o Firefox'
                foreach ($i in @(Get-LacadorFirefoxInstalacoes)) { if ($i.exe -eq $ff) { $nomeEd = 'o ' + (Get-LacadorNomeEdicao $i.edicao) } }
                return [ordered]@{ ok = $true; mensagem = ('Abrindo {0}.' -f $nomeEd) }
            }
            'fixar-extensao' {
                $it = @($cat.itens | Where-Object { $_.id -eq 'extensao-firefox' })[0]
                $idBotao = Get-LacadorIdBotaoExtensao ([string]$it.extensaoId)
                if (@(Get-Process -Name 'firefox' -ErrorAction SilentlyContinue).Count) {
                    if (-not $Parametros.fechar) { return [ordered]@{ ok = $false; precisaFechar = $true; mensagem = 'O Firefox está aberto. Para fixar o botão ele precisa ser fechado (as abas voltam quando ele abrir de novo).' } }
                    if (-not (Close-LacadorFirefox)) { throw 'O Firefox não fechou. Feche todas as janelas dele e tente de novo.' }
                    Start-Sleep -Milliseconds 800
                }
                $feitos = 0; $sem = 0
                foreach ($pf in @(Get-LacadorPerfisFirefox ([string]$it.extensaoId))) {
                    if (-not $pf.extensao -or -not $pf.extensao.ativa -or $pf.fixada -eq $true) { continue }
                    $r = Set-LacadorBotaoNaBarra ([string]$pf.pasta) $idBotao
                    if ($r -eq 'fixado') { $feitos++ } elseif ($r -eq 'sem-estado') { $sem++ }
                }
                if ($feitos) { return [ordered]@{ ok = $true; mensagem = 'Pronto: o botão do assinador está na barra do Firefox. Abra o Firefox para conferir.' } }
                if ($sem) { throw 'O Firefox ainda não gravou a barra deste usuário. Abra o Firefox, clique na peça de quebra-cabeça (Extensões) e, no Assinador Digital COMAER, escolha "Fixar na barra".' }
                return [ordered]@{ ok = $true; mensagem = 'O botão do assinador já estava na barra do Firefox.' }
            }
            'proxy-aplicar' {
                $porta = 0
                if ($cfg.proxy.porta) { $porta = [int]$cfg.proxy.porta }
                if ($porta -le 0) { throw 'A porta do proxy não está definida em config.json.' }
                $k = Open-LacadorChave 'HKCU' 64 'Software\Microsoft\Windows\CurrentVersion\Internet Settings' $true $true
                try {
                    if ($k.GetValue('AutoConfigURL')) { throw 'Este usuário usa configuração automática de proxy (definida pela rede). Nada foi alterado.' }
                    $k.SetValue('ProxyServer', ('{0}:{1}' -f $cfg.proxy.servidor, $porta))
                    $k.SetValue('ProxyEnable', 1, [Microsoft.Win32.RegistryValueKind]::DWord)
                    if (-not $k.GetValue('ProxyOverride') -and $cfg.proxy.excecoes) { $k.SetValue('ProxyOverride', [string]$cfg.proxy.excecoes) }
                } finally { $k.Close() }
                return [ordered]@{ ok = $true; mensagem = ('Proxy definido como {0}:{1}. Feche e abra o navegador.' -f $cfg.proxy.servidor, $porta) }
            }
            'assinador-token' {
                $t = @($cat.tokens | Where-Object { $_.id -eq [string]$Parametros.token })[0]
                if (-not $t -or -not $t.assinadorToken) { throw 'Este token não precisa de ajuste no assinador.' }
                return [ordered]@{ ok = $true; mensagem = (Add-LacadorTokenAoAssinador ([string]$t.assinadorToken) ([string]$t.pkcs11)) }
            }
            'importar-certificado' {
                Add-Type -AssemblyName System.Windows.Forms
                $dlg = New-Object System.Windows.Forms.OpenFileDialog
                $dlg.Title = 'Escolha o arquivo do certificado (.pfx ou .p12)'
                $dlg.Filter = 'Certificado digital (*.pfx;*.p12)|*.pfx;*.p12'
                $dono = New-Object System.Windows.Forms.Form
                $dono.TopMost = $true; $dono.ShowInTaskbar = $false; $dono.Opacity = 0
                $dono.StartPosition = 'CenterScreen'; $dono.Width = 1; $dono.Height = 1
                $dono.Show()
                $res = $dlg.ShowDialog($dono)
                $dono.Close()
                if ($res -ne [System.Windows.Forms.DialogResult]::OK) { return [ordered]@{ ok = $true; mensagem = 'Importação cancelada.' } }
                Start-Process -FilePath $dlg.FileName
                return [ordered]@{ ok = $true; mensagem = 'O assistente do Windows foi aberto. A senha do certificado é digitada nele, não no Laçador.' }
            }
            'relatorio' {
                $script2 = Join-Path $script:PastaPrograma 'relatorio-suporte.ps1'
                if (-not (Test-Path -LiteralPath $script2)) { throw 'Arquivo do relatório não encontrado.' }
                Start-Process -FilePath 'powershell.exe' -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}"' -f $script2)
                return [ordered]@{ ok = $true; mensagem = 'Gerando o relatório. Ele abre no Bloco de Notas em alguns segundos e fica salvo na Área de Trabalho como lacador-relatorio.txt.' }
            }
            'relatorio-assinador' {
                $script2 = Join-Path $script:PastaPrograma 'diagnostico-assinador.ps1'
                if (-not (Test-Path -LiteralPath $script2)) { throw 'Arquivo de diagnóstico não encontrado.' }
                Start-Process -FilePath 'powershell.exe' -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}"' -f $script2)
                return [ordered]@{ ok = $true; mensagem = 'Gerando o diagnóstico do assinador. Ele abre no Bloco de Notas e fica salvo na Área de Trabalho.' }
            }
            default { throw 'Operação desconhecida.' }
        }
    } catch {
        return [ordered]@{ ok = $false; mensagem = [string]$_.Exception.Message }
    }
}

#endregion

Export-ModuleMember -Function *-Lacador*
