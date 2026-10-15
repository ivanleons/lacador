// Capturas para mostrar ao usuário + teste de recarregar a janela (F5).
const { chromium } = require('playwright');
const [url, dir] = process.argv.slice(2);
(async () => {
  const b = await chromium.launch({ args: ['--no-sandbox'] });
  const ctx = await b.newContext({ viewport: { width: 1280, height: 860 }, deviceScaleFactor: 1.5 });
  const p = await ctx.newPage();
  const erros = [];
  p.on('pageerror', e => erros.push(e.message));
  await p.goto(url);
  await p.waitForTimeout(900);
  await p.screenshot({ path: dir + '/1-inicializacao.png' });
  await p.waitForSelector('#app:not([hidden])', { timeout: 20000 });
  await p.waitForTimeout(1300);
  await p.mouse.move(640, 470); await p.waitForTimeout(700);
  await p.screenshot({ path: dir + '/2-sistemas.png' });
  await p.click('#nav [data-pagina="tokens"]'); await p.mouse.move(980, 300); await p.waitForTimeout(800);
  await p.screenshot({ path: dir + '/3-tokens.png' });
  await p.click('#nav [data-pagina="tutoriais"]'); await p.waitForTimeout(400);
  await p.locator('.tuto-item', { hasText: 'SIGADAER' }).click(); await p.waitForTimeout(600);
  await p.screenshot({ path: dir + '/4-tutoriais.png' });
  // F5: a chave some da barra de endereço, mas a tela tem de continuar funcionando
  await p.reload();
  await p.waitForSelector('#app:not([hidden])', { timeout: 20000 });
  await p.waitForTimeout(1500);
  const titulo = await p.locator('#titulo').innerText();
  const cartoes = await p.locator('#conteudo .cartao').count();
  console.log('depois do F5:', titulo, cartoes, 'cartões', 'url=' + p.url());
  console.log('ERROS', erros.length, erros.join(' | '));
  await b.close();
})();
