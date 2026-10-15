// Abre a interface, espera a tela inicial sumir e fotografa cada página.
const { chromium } = require('playwright');
const url = process.argv[2];
const dir = process.argv[3];
(async () => {
  const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium', args: ['--no-sandbox'] }).catch(async () => chromium.launch({ args: ['--no-sandbox'] }));
  const ctx = await b.newContext({ viewport: { width: 1180, height: 760 }, deviceScaleFactor: 1 });
  const p = await ctx.newPage();
  const erros = [];
  p.on('console', m => { if (m.type() === 'error' || m.type() === 'warning') erros.push('[' + m.type() + '] ' + m.text()); });
  p.on('pageerror', e => erros.push('[pageerror] ' + e.message + '\n' + (e.stack || '')));
  p.on('requestfailed', r => erros.push('[reqfail] ' + r.url() + ' ' + (r.failure() || {}).errorText));
  p.on('response', r => { if (r.status() >= 400) erros.push('[http ' + r.status() + '] ' + r.url()); });
  await p.goto(url);
  await p.waitForTimeout(700);
  await p.screenshot({ path: dir + '/00-inicio.png' });
  await p.waitForSelector('#app:not([hidden])', { timeout: 20000 }).catch(e => erros.push('app nao apareceu: ' + e.message));
  await p.waitForTimeout(1200);
  await p.screenshot({ path: dir + '/01-sistemas.png' });
  const nav = await p.$$eval('#nav [data-pagina]', els => els.map(e => e.getAttribute('data-pagina')));
  console.log('NAV', JSON.stringify(nav));
  let i = 2;
  for (const pg of nav.slice(1)) {
    await p.click('#nav [data-pagina="' + pg + '"]');
    await p.waitForTimeout(700);
    await p.screenshot({ path: dir + '/0' + i + '-' + pg + '.png', fullPage: false });
    i++;
  }
  console.log('ERROS', erros.length); erros.forEach(e => console.log(e));
  await b.close();
})().catch(e => { console.error('FALHA', e); process.exit(1); });
