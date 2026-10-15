// Lacador.exe pequeno (sem instaladores): a tela tem de levar até "Montar o Laçador completo".
const { chromium } = require('playwright');
const [url, dir] = process.argv.slice(2);
const erros = [];
const ok = (c, m) => { console.log((c ? 'OK   ' : 'FALHA') + ' ' + m); if (!c) erros.push(m); };
(async () => {
  const b = await chromium.launch({ args: ['--no-sandbox'] });
  const p = await (await b.newContext({ viewport: { width: 1280, height: 860 } })).newPage();
  p.on('pageerror', e => erros.push('[pageerror] ' + e.message));
  await p.goto(url);
  await p.waitForSelector('#app:not([hidden])', { timeout: 20000 });
  await p.locator('.nav-item', { hasText: 'Sistemas' }).click();   // a tela abre no Início
  await p.waitForTimeout(400);
  await p.waitForTimeout(900);
  const aviso = p.locator('.aviso', { hasText: 'Este Laçador está sem os instaladores' });
  ok(await aviso.count() === 1, 'Sistemas avisa que faltam os instaladores');
  ok(await p.locator('.aviso').first().innerText().then(t => t.includes('sem os instaladores')), 'é o primeiro aviso da lista');
  const cartao = n => p.locator('.cartao', { has: p.locator('h2', { hasText: new RegExp('^' + n) }) }).first();
  ok(await cartao('SIGADAER').locator('button', { hasText: 'Preparar' }).isDisabled(), 'Preparar fica desabilitado sem os instaladores');
  await p.screenshot({ path: dir + '/40-pequeno-sistemas.png' });
  await aviso.locator('button', { hasText: 'Ver' }).click();
  await p.waitForTimeout(700);
  ok((await p.locator('#titulo').innerText()) === 'Diagnóstico', 'o aviso leva ao Diagnóstico');
  ok(await cartao('Instaladores').locator('button', { hasText: 'Montar o Laçador completo' }).count() === 1, 'Diagnóstico oferece Montar o Laçador completo');
  await cartao('Instaladores').scrollIntoViewIfNeeded();
  await p.waitForTimeout(300);
  await p.screenshot({ path: dir + '/41-pequeno-diagnostico.png' });
  console.log('ERROS ' + erros.length); erros.forEach(e => console.log('  ' + e));
  await b.close(); process.exit(erros.length ? 1 : 0);
})().catch(e => { console.error('FALHA GERAL', e.message); process.exit(1); });
