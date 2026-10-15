import json, copy, os, datetime
cat = json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'Lacador', 'programa', 'catalogo.json'), encoding='utf-8'))
pac = {p['arquivo']: {'existe': True, 'tamanho': p['tamanho']} for it in cat['itens'] for p in it['pacotes']}
hoje = datetime.datetime(2026, 10, 6, 12, 0, 0)
def cert(nome, emissor, dias, chave=True, auto=False, anos=3):
    fim = hoje + datetime.timedelta(days=dias)
    return {'titular': nome, 'emissor': emissor, 'inicio': (fim - datetime.timedelta(days=365 * anos)).strftime('%Y-%m-%dT%H:%M:%S'), 'fim': fim.strftime('%Y-%m-%dT%H:%M:%S'), 'chavePrivada': chave, 'autoassinado': auto, 'id': 'A1B2C3D4'}
base = {
  'coletadoEm': '2026-10-06T12:00:00', 'computador': 'PC-TESTE', 'usuario': 'usuario', 'dominio': 'PC-TESTE', 'admin': False,
  'windows': {'nome': 'Windows 11 Home Single Language', 'versao': '25H2', 'build': '26200.9457', 'arquitetura': 'x64'},
  'programas': [], 'arquivos': {'%SystemRoot%\\System32\\aetpkss1.dll': False, '%SystemRoot%\\System32\\DXSafePKCS11.dll': False},
  'servicos': {'SCardSvr': {'estado': 'Stopped', 'inicio': 'Manual'}, 'CertPropSvc': {'estado': 'Running', 'inicio': 'Automatic'}},
  'dispositivos': [], 'certificados': [],
  'assinador': {'pasta': '', 'jar': False, 'bats': [], 'ligacao64': '', 'ligacao32': '', 'manifesto': False, 'atalho': False, 'configUsuario': {'existe': False, 'tokens': []}},
  'firefox': {'instalacoes': [], 'politica': {'origem': '', 'modo': '', 'url': '', 'assinaturaFraca': False, 'arquivoExiste': False, 'prefsAtic': False}, 'perfis': []},
  'java': {'jres': [], 'jnlpComando': '', 'jnlpEscolhaUsuario': '', 'atualizacaoDesativada': False},
  'proxy': {'ativo': False, 'servidor': '', 'pac': '', 'excecoes': ''}, 'wmic': {'x64': False, 'x86': False},
  'pastaPacotes': 'E:\\Lacador\\pacotes', 'pacotes': pac, 'navegadores': {'edge': 'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe', 'chrome': ''},
  'agente': {'tarefa': False, 'instalado': False, 'pasta': '', 'versao': ''}, 'erros': []
}
P = lambda n, v, f, pasta='', chave='x': {'nome': n, 'versao': v, 'fabricante': f, 'pasta': pasta, 'chave': chave}
safesign = P('SafeSign 64-bits', '3.0.97', 'A.E.T. Europe B.V.')
starsign = P('Giesecke & Devrient GmbH StarSign CUT', '1.7.17.0', 'Giesecke & Devrient GmbH', 'C:\\Program Files (x86)\\G&D\\')
ff_esr86 = {'pasta': 'C:\\Program Files (x86)\\Mozilla Firefox', 'exe': 'C:\\Program Files (x86)\\Mozilla Firefox\\firefox.exe', 'versao': '153.3.0', 'canal': 'esr', 'arquitetura': 'x86'}
ass_dir = 'C:\\Program Files (x86)\\Assinador Digital do COMAER'
leitor_gd = [
  {'nome': 'Giesecke & Devrient GmbH StarSign CUT 0', 'id': 'SWD\\SCDEVICEENUM\\1_GIESECKE_&_DEVRIENT_GMBH_STARSIGN_CUT_0', 'classe': 'SoftwareDevice', 'status': 'OK'},
  {'nome': 'G&D StarSign CUT', 'id': 'USB\\VID_1059&PID_0017\\01140712030920', 'classe': 'SmartCardReader', 'status': 'OK'}]

# 1) notebook de um usuário ANTES (relatorio de 25/09 08:54): drivers ok, assinador ausente, Java 7, token nao detectado
c1 = copy.deepcopy(base)
c1['admin'] = True
c1['programas'] = [starsign, P('Java 7 Update 51', '7.0.510', 'Oracle', 'C:\\Program Files (x86)\\Java\\jre7\\'), P('Java Auto Updater', '2.8.503.1', 'Oracle Corporation'), P('Mozilla Firefox ESR (x86 pt-BR)', '153.3.0', 'Mozilla', 'C:\\Program Files (x86)\\Mozilla Firefox'), safesign]
c1['arquivos']['%SystemRoot%\\System32\\aetpkss1.dll'] = True
c1['servicos']['SCardSvr'] = {'estado': 'Stopped', 'inicio': 'Automatic'}
c1['certificados'] = [cert('trust_b09a715e-aa3f-40b9-ab00-7b33b1554cb1', 'trust_b09a715e-aa3f-40b9-ab00-7b33b1554cb1', 249, auto=True), cert('d9699006-b223-40b3-a639-4c8565af84f6', 'd9699006-b223-40b3-a639-4c8565af84f6', -175, auto=True), cert('FULANO DE TAL', 'Autoridade Certificadora de Defesa', 877)]
c1['firefox']['instalacoes'] = [ff_esr86]
c1['firefox']['perfis'] = [{'nome': '9t18me82.default', 'pasta': 'C:\\Users\\usuario\\AppData\\Roaming\\Mozilla\\Firefox\\Profiles\\9t18me82.default', 'edicao': 'comum', 'emUso': False, 'aberto': True, 'extensao': None, 'fixada': None}, {'nome': 'ttdw9ti7.default-esr', 'pasta': 'C:\\Users\\usuario\\AppData\\Roaming\\Mozilla\\Firefox\\Profiles\\ttdw9ti7.default-esr', 'edicao': 'esr', 'emUso': True, 'aberto': True, 'extensao': {'versao': '2.0.9', 'ativa': True, 'bloqueada': False, 'desativada': False}, 'fixada': True}]
c1['java'] = {'jres': [{'versao': '1.7.0_51', 'pasta': 'C:\\Program Files (x86)\\Java\\jre7', 'arquitetura': 'x86', 'javaws': True}], 'jnlpComando': '"C:\\Program Files (x86)\\Java\\jre7\\bin\\javaws.exe" "%1"', 'jnlpEscolhaUsuario': '', 'atualizacaoDesativada': False}

# 2) notebook de um usuário DEPOIS: assinador instalado e corrigido, token conectado
c2 = copy.deepcopy(c1)
c2['programas'] = [P('Assinador Digital do COMAER versão 2.0.12', '2.0.12', 'CCA-SJ', ass_dir + '\\', '{6CC54A28-5953-482E-9A6B-0A570FCAD6E8}_is1'), starsign, P('Mozilla Firefox ESR (x86 pt-BR)', '153.3.0', 'Mozilla', 'C:\\Program Files (x86)\\Mozilla Firefox'), safesign]
c2['servicos']['SCardSvr'] = {'estado': 'Running', 'inicio': 'Automatic'}
c2['dispositivos'] = leitor_gd
c2['assinador'] = {'pasta': ass_dir, 'jar': True, 'bats': [{'nome': 'assinador_comaer.bat', 'existe': True, 'usaWmic': False, 'corrigido': True}, {'nome': 'assinador_standalone.bat', 'existe': True, 'usaWmic': False, 'corrigido': True}], 'ligacao64': ass_dir + '\\assinador_comaer.json', 'ligacao32': ass_dir + '\\assinador_comaer.json', 'manifesto': True, 'atalho': True, 'configUsuario': {'existe': True, 'tokens': []}}
c2['java'] = {'jres': [], 'jnlpComando': '', 'jnlpEscolhaUsuario': '', 'atualizacaoDesativada': False}
c2['wmic'] = {'x64': True, 'x86': False}

# 3) computador novo, Firefox comum, leitor generico (possivel Dexon), nada instalado
c3 = copy.deepcopy(base)
c3['firefox']['instalacoes'] = [{'pasta': 'C:\\Program Files\\Mozilla Firefox', 'exe': 'C:\\Program Files\\Mozilla Firefox\\firefox.exe', 'versao': '143.0', 'canal': 'release', 'arquitetura': 'x64'}]
c3['dispositivos'] = [{'nome': 'Microsoft Usbccid Smartcard Reader (WUDF)', 'id': 'USB\\VID_0000&PID_0000\\5&1A2B', 'classe': 'SmartCardReader', 'status': 'OK'}]
c3['navegadores']['chrome'] = 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe'

# 4) assinador quebrado pelo WMIC, certificado vencendo, outro Adobe instalado, falta um instalador
c4 = copy.deepcopy(c2)
for b in c4['assinador']['bats']: b['usaWmic'] = True; b['corrigido'] = False
c4['certificados'] = [cert('FULANO DE TAL', 'Autoridade Certificadora de Defesa', 12), cert('BELTRANO DA SILVA', 'Autoridade Certificadora de Defesa', -3)]
c4['programas'].append(P('Adobe Acrobat (64-bit)', '25.001.20997', 'Adobe'))
c4['pacotes'] = copy.deepcopy(pac); c4['pacotes']['jre-8u91-windows-i586.exe'] = {'existe': False, 'tamanho': 0}
c4['agente'] = {'tarefa': True, 'instalado': True, 'pasta': 'C:\\Program Files\\Lacador', 'versao': '1.0.0'}

# 5) tudo pronto com os dois tokens, politica do Firefox aplicada, Java 8 ok, Dexon ajustado no assinador
c5 = copy.deepcopy(c2)
c5['programas'] += [P('DXSafe Middleware 1.0.30', '1.0.30', 'Dexon Tecnologias Digitais LTDA', 'C:\\Program Files\\DXSafe Middleware\\', '{8135958A-27DD-4BBA-9637-DCFC7EEF5FF0}_is1'), P('Java 8 Update 91', '8.0.910.15', 'Oracle Corporation'), P('Adobe Reader XI (11.0.23) - Português', '11.0.23', 'Adobe Systems Incorporated')]
c5['arquivos']['%SystemRoot%\\System32\\DXSafePKCS11.dll'] = True
c5['dispositivos'] = leitor_gd + [{'nome': 'Dexon DXToken 0', 'id': 'SWD\\SCDEVICEENUM\\1_DEXON_DXTOKEN_0', 'classe': 'SoftwareDevice', 'status': 'OK'}]
c5['java'] = {'jres': [{'versao': '1.8.0_91', 'pasta': 'C:\\Program Files (x86)\\Java\\jre1.8.0_91', 'arquitetura': 'x86', 'javaws': True}], 'jnlpComando': '"C:\\Program Files (x86)\\Java\\jre1.8.0_91\\bin\\javaws.exe" "%1"', 'jnlpEscolhaUsuario': '', 'atualizacaoDesativada': True}
c5['firefox']['politica'] = {'origem': 'registro', 'modo': 'force_installed', 'url': 'file:///C:/ProgramData/Lacador/firefox/assinador_digital_comaer.xpi', 'assinaturaFraca': True, 'arquivoExiste': True, 'prefsAtic': False}
c5['assinador']['configUsuario']['tokens'] = [{'nome': 'dexon', 'caminho': 'c:/windows/system32/DXSafePKCS11.dll'}]
c5['proxy'] = {'ativo': True, 'servidor': 'proxy.exemplo.intranet:8080', 'pac': '', 'excecoes': '<local>'}

# 6) padrão da base: Firefox Developer Edition; extensão ativa, mas com o botão escondido no menu de extensões
c6 = copy.deepcopy(c5)
dev_dir = 'C:\\Program Files\\Firefox Developer Edition'
c6['firefox']['instalacoes'] = [{'pasta': dev_dir, 'exe': dev_dir + '\\firefox.exe', 'versao': '145.0b9', 'canal': 'aurora', 'edicao': 'developer', 'arquitetura': 'x64'}]
c6['firefox']['perfis'] = [{'nome': 'k2j4h1.dev-edition-default', 'pasta': 'C:\\Users\\leon\\AppData\\Roaming\\Mozilla\\Firefox\\Profiles\\k2j4h1.dev-edition-default', 'edicao': 'developer', 'emUso': True, 'aberto': True, 'extensao': {'versao': '2.0.12', 'ativa': True, 'bloqueada': False, 'desativada': False}, 'fixada': False}]
c6['programas'] = [x for x in c6['programas'] if 'Firefox' not in x['nome']] + [P('Firefox Developer Edition (x64 pt-BR)', '145.0', 'Mozilla', dev_dir)]
c6['nomeUsuario'] = '3S BMB Leon'

# 7) Firefox ESR e política gravados agora; o Firefox ainda não foi aberto (a extensão não entrou no perfil)
c7 = copy.deepcopy(c5)
c7['firefox']['perfis'] = [{'nome': 'ttdw9ti7.default-esr', 'pasta': 'C:\\Users\\usuario\\AppData\\Roaming\\Mozilla\\Firefox\\Profiles\\ttdw9ti7.default-esr', 'edicao': 'esr', 'emUso': True, 'aberto': True, 'extensao': None, 'fixada': None}]

# 8) SafeSign consta como instalado, mas a biblioteca do token sumiu (o caso do teste de 14/10/2026)
c8 = copy.deepcopy(c5)
c8['arquivos']['%SystemRoot%\\System32\\aetpkss1.dll'] = False
c8['firefox']['instalacoes'] = c6['firefox']['instalacoes'] + c5['firefox']['instalacoes']

for nome, c in (('notebook-antes', c1), ('notebook-depois', c2), ('pc-novo', c3), ('assinador-quebrado', c4), ('tudo-pronto', c5), ('developer-sem-fixar', c6), ('firefox-nao-aberto', c7), ('safesign-quebrado', c8)):
    json.dump(c, open('cenarios/%s.json' % nome, 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
print(sorted(os.listdir('cenarios')))
