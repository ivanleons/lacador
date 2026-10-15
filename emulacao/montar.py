#!/usr/bin/env python3
"""Monta a página única da emulação: a interface real do Laçador + o simulador do serviço local."""
import base64, json, re, sys
prog, emu = sys.argv[1], sys.argv[2]
iface = prog + '/interface'

def uri(caminho, tipo):
    return 'data:%s;base64,%s' % (tipo, base64.b64encode(open(caminho, 'rb').read()).decode('ascii'))

css = open(iface + '/app.css', encoding='utf-8').read()
assert 'url(img/splash.jpg)' in css
css = css.replace('url(img/splash.jpg)', 'url(%s)' % uri(iface + '/img/splash.jpg', 'image/jpeg'))
css += open(emu + '/emulacao.css', encoding='utf-8').read()

html = open(iface + '/index.html', encoding='utf-8').read()
corpo = re.search(r'<body>(.*)</body>', html, re.S).group(1)
corpo = corpo.replace('<script src="app.js"></script>', '')
for nome, tipo in (('icone.png', 'image/png'), ('nome.png', 'image/png')):
    alvo = 'src="img/%s"' % nome
    assert alvo in corpo, alvo
    corpo = corpo.replace(alvo, 'src="%s"' % uri(iface + '/img/' + nome, tipo))
assert 'img/' not in corpo and 'src="app' not in corpo

dados = {
    'versao': '1.2.0',
    'estados': json.load(open(emu + '/estados.json', encoding='utf-8')),
    'tutoriais': json.load(open(prog + '/tutoriais.json', encoding='utf-8')),
}
dados_js = 'window.EMU = ' + json.dumps(dados, ensure_ascii=False, separators=(',', ':')).replace('</', '<\\/') + ';'
sim = open(emu + '/simulador.js', encoding='utf-8').read()
app = open(iface + '/app.js', encoding='utf-8').read()
assert '</script' not in sim and '</script' not in app

pagina = '<title>Emulação do Laçador</title>\n<style>\n' + css + '\n</style>\n' + corpo.strip() + \
         '\n<script>\n' + dados_js + '\n</script>\n<script>\n' + sim + '\n</script>\n<script>\n' + app + '\n</script>\n'
open(emu + '/emulacao-lacador.html', 'w', encoding='utf-8').write(pagina)

# Cópia só para olhar aqui: imita o esqueleto que a publicação coloca em volta da página.
esqueleto = ('<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">'
             '<style>:root{color-scheme:light}body{margin:0;font:14px system-ui}img{max-width:100%}[hidden]{display:none!important}</style></head><body>')
open(emu + '/previa.html', 'w', encoding='utf-8').write(esqueleto + pagina + '</body></html>')
print(len(pagina.encode('utf-8')), 'bytes')
