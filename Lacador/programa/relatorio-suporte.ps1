<#
===============================================================================
  LAÇADOR - relatório para o suporte (somente leitura)
===============================================================================
  Junta num arquivo só, na Área de Trabalho (lacador-relatorio.txt):
   - o resumo do que o Laçador viu no computador;
   - programas, arquivos dos tokens, Firefox (edições, política, perfis,
     extensão e botão na barra);
   - os registros do Laçador e das últimas instalações;
   - os fatos brutos que a tela usa (para o suporte reproduzir o caso).
  Não instala, não remove e não altera nada. CPF e CNPJ saem ocultos.
  Criado por 3S Leon, S2 Dalssasso
===============================================================================
#>
param([string]$Saida)

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
Import-Module (Join-Path $PSScriptRoot 'Lacador.Motor.psm1') -Force

$s = New-Object System.Text.StringBuilder
function L($t) { [void]$s.AppendLine([string]$t) }
function Secao($t) { L ''; L ('=' * 78); L (' ' + $t); L ('=' * 78) }

$cat = Get-LacadorCatalogo
$cfg = Get-LacadorConfig
$fatos = $null; $estado = $null
try { $fatos = Get-LacadorFatos -Catalogo $cat -Config $cfg } catch { L ('Falha ao ler o computador: ' + $_.Exception.Message) }
try { if ($fatos) { $estado = ConvertTo-LacadorEstado $fatos $cat $cfg } } catch { L ('Falha ao montar o estado: ' + $_.Exception.Message) }

L ('LAÇADOR {0} - relatório para o suporte' -f (Get-LacadorVersao))
L ('Gerado em {0} no computador {1}, usuário {2}' -f (Get-Date -Format 'dd/MM/yyyy HH:mm'), $env:COMPUTERNAME, $env:USERNAME)
L 'Somente leitura: nada foi alterado. CPF/CNPJ ocultos.'

if ($estado) {
    Secao 'RESUMO'
    L ('Usuário: {0} ({1})' -f $estado.nomeUsuario, $(if ($estado.acesso.administrador) { 'administrador' } else { 'usuário comum' }))
    L ('Windows: {0} {1}, build {2}' -f $estado.windows.nome, $estado.windows.versao, $estado.windows.build)
    L ('Liberado para instalar sem administrador: {0}' -f $(if ($estado.acesso.liberado) { 'sim' } else { 'não' }))
    L ''
    foreach ($x in $estado.sistemas) { L ('[{0,-10}] {1}: {2}' -f $x.estado, $x.nome, $x.resumo) }
    L ''
    foreach ($k in $estado.itens.Keys) {
        $i = $estado.itens[$k]
        L ('[{0,-8}] {1}: {2}' -f $i.estado, $i.nome, $i.detalhe)
        foreach ($v in @($i.verificacoes)) { L ('             - {0}: {1} ({2})' -f $v.nome, $v.detalhe, $(if ($v.ok) { 'ok' } else { 'pendente' })) }
    }
    L ''
    foreach ($t in $estado.tokens) { L ('Token {0}: {1} - {2}' -f $t.nome, $t.estado, $t.resumo) }
    foreach ($c in @($estado.certificados | Where-Object { $_.pessoal })) { L ('Certificado {0}: {1}, até {2}' -f $c.titular, $c.situacao, $c.validade) }
    foreach ($a in @($estado.avisos)) { L ('Aviso: {0} - {1}' -f $a.titulo, $a.texto) }
    foreach ($e in @($estado.erros)) { L ('Falha ao ler: ' + $e) }
}

Secao 'PROGRAMAS NO REGISTRO'
$k = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
Get-ItemProperty $k -ErrorAction SilentlyContinue | Where-Object { "$($_.DisplayName) $($_.Publisher)" -match 'safesign|starsign|giesecke|dxsafe|dexon|assinador|firefox|java|adobe|a\.e\.t' } |
    ForEach-Object { L ('{0} | {1} | {2} | {3} | {4} | {5}' -f $_.DisplayName, $_.DisplayVersion, $_.Publisher, $_.PSChildName, $_.InstallLocation, $_.UninstallString) }

Secao 'ARQUIVOS DOS TOKENS'
foreach ($a in 'System32\aetpkss1.dll', 'SysWOW64\aetpkss1.dll', 'System32\DXSafePKCS11.dll', 'SysWOW64\DXSafePKCS11.dll') { $p = Join-Path "$env:windir" $a; L ('{0} : {1}' -f $p, (Test-Path -LiteralPath $p)) }
foreach ($d in "$env:ProgramFiles\A.E.T. Europe B.V", "${env:ProgramFiles(x86)}\A.E.T. Europe B.V") {
    if ($d -match '^[A-Za-z]:\\' -and (Test-Path -LiteralPath $d)) { Get-ChildItem -LiteralPath $d -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 40 | ForEach-Object { L $_.FullName } }
}

Secao 'FIREFOX'
foreach ($i in @(Get-LacadorFirefoxInstalacoes)) { L ('{0} | {1} | versão {2} | canal {3} | {4}' -f (Get-LacadorNomeEdicao $i.edicao), $i.pasta, $i.versao, $i.canal, $i.arquitetura) }
L ''
$pol = Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Mozilla\Firefox' -ErrorAction SilentlyContinue
if ($pol) { $pol.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' } | ForEach-Object { L ('Política {0} = {1}' -f $_.Name, (@($_.Value) -join ' ')) } } else { L 'Nenhuma política do Firefox no registro' }
L ''
$it = @($cat.itens | Where-Object { $_.id -eq 'extensao-firefox' })[0]
foreach ($pf in @(Get-LacadorPerfisFirefox ([string]$it.extensaoId))) {
    $ex = 'não está neste perfil'
    if ($pf.extensao) { $ex = ('versão {0}, ativa={1}, desativada pelo usuário={2}, bloqueada={3}' -f $pf.extensao.versao, $pf.extensao.ativa, $pf.extensao.desativada, $pf.extensao.bloqueada) }
    L ('Perfil {0} ({1}, em uso={2}, já aberto={3}): extensão {4}; botão na barra={5}' -f $pf.nome, $pf.edicao, $pf.emUso, $pf.aberto, $ex, $pf.fixada)
}

Secao 'REGISTROS DO LAÇADOR'
foreach ($f in (Join-Path (Get-LacadorPastaUsuario) 'lacador.log'), (Join-Path (Get-LacadorPastaDados) 'logs\agente.log'), (Join-Path (Get-LacadorPastaDados) 'logs\instalacao.log')) {
    L ('-- ' + $f)
    if (Test-Path -LiteralPath $f) { Get-Content -LiteralPath $f -Tail 120 -Encoding UTF8 -ErrorAction SilentlyContinue | ForEach-Object { L $_ } } else { L 'não existe' }
}
foreach ($lm in @(Get-ChildItem (Join-Path (Get-LacadorPastaDados) 'logs') -Filter 'msi-*.log' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime | Select-Object -Last 3)) {
    # Registro do Windows Installer: só as linhas que interessam (é enorme).
    L ('-- ' + $lm.FullName)
    Get-Content -LiteralPath $lm.FullName -ErrorAction SilentlyContinue | Where-Object { $_ -match 'aetpkss1|PKCS11|Return value 3|Erro|Error |Produto:|Product:|returning|Note:|ADDLOCAL|REINSTALL|Feature: |Component: x64PKCS11|Component: PKCS11_Library' } | Select-Object -First 160 | ForEach-Object { L $_ }
}
Get-ChildItem (Join-Path (Get-LacadorPastaUsuario) 'pedidos'), (Join-Path (Get-LacadorPastaDados) 'respostas') -Filter '*.json' -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime | Select-Object -Last 8 | ForEach-Object { L ('-- ' + $_.FullName); L ([IO.File]::ReadAllText($_.FullName, [Text.Encoding]::UTF8)) }

if ($fatos) {
    Secao 'FATOS BRUTOS (o que a tela usa)'
    L (ConvertTo-Json -InputObject $fatos -Depth 12)
}

if (-not $Saida) {
    $mesa = [Environment]::GetFolderPath('Desktop')
    if (-not $mesa -or -not (Test-Path -LiteralPath $mesa)) { $mesa = $env:USERPROFILE }
    $Saida = Join-Path $mesa 'lacador-relatorio.txt'
}
[IO.File]::WriteAllText($Saida, $s.ToString(), (New-Object System.Text.UTF8Encoding($true)))
if (-not $PSBoundParameters.ContainsKey('Saida')) { Start-Process -FilePath 'notepad.exe' -ArgumentList ('"{0}"' -f $Saida) }
