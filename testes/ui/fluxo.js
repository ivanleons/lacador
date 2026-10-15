// Percorre os fluxos principais na demonstração: preparar, reparar, escolher token, busca, tutoriais.
const { chromium } = require('playwright');
const [url, dir, modo] = process.argv.slice(2);
const erros = [];
const ok = (c, m) => { console.log((c ? 'OK   ' : 'FALHA') + ' ' + m); if (!c) erros.push(m); };
(async () => {
  const b = await chromium.launch({ args: ['--no-sandbox'] });
  const ctx = await b.newContext({ viewport: { width: 1180, height: 760 } });
  const p = await ctx.newPage();
  p.on('console', m => { if (m.type() === 'error') erros.push('[console] ' + m.text()); });
  p.on('pageerror', e => erros.push('[pageerror] ' + e.message));
  p.on('response', r => { if (r.status() >= 400) erros.push('[http ' + r.status() + '] ' + r.url()); });
  await p.goto(url);
  await p.waitForSelector('#app:not([hidden])', { timeout: 20000 });
  await p.locator('.nav-item', { hasText: 'Sistemas' }).click();   // a tela abre no Início
  await p.waitForTimeout(400);
  await p.waitForTimeout(900);
  const cartao = nome => p.locator('.cartao', { has: p.locator('h2', { hasText: new RegExp('^' + nome) }) }).first();
  const selo = async nome => (await cartao(nome).locator('.selo').first().innerText()).trim();

  if (modo === 'novo') {
    ok((await selo('SIGADAER')) === 'Falta instalar', 'PC novo: SIGADAER aparece como Falta instalar (' + await selo('SIGADAER') + ')');
    await cartao('SIGADAER').locator('button', { hasText: 'Preparar' }).click();
    await p.waitForSelector('#folha .escolha');
    ok((await p.locator('#folha .escolha').count()) === 3, 'folha de escolha do token mostra 3 opções');
    await p.screenshot({ path: dir + '/10-escolher-token.png' });
    await p.locator('#folha .escolha', { hasText: 'GD Burti' }).click();
    await p.waitForSelector('#folha .folha-lista');
    const nomes = await p.locator('#folha .folha-item strong').allInnerTexts();
    console.log('     itens previstos:', nomes.join(' | '));
    ok(nomes.includes('SafeSign') && nomes.includes('Driver StarSign CUT') && nomes.includes('Assinador do COMAER') && nomes.includes('Firefox') && nomes.includes('Extensão do assinador'), 'confirmação lista driver, assinador, Firefox e extensão');
    ok(!nomes.includes('DXSafe Middleware'), 'não inclui o driver do outro token');
    await p.screenshot({ path: dir + '/11-confirmar.png' });
    await p.locator('#folha button', { hasText: 'Continuar' }).click();
    await p.waitForTimeout(1500);
    await p.screenshot({ path: dir + '/12-andamento.png' });
    await p.waitForSelector('#folha button:has-text("Fechar")', { timeout: 60000 });
    ok((await p.locator('#folha h2').innerText()) === 'Pronto', 'instalação simulada termina em Pronto');
    await p.screenshot({ path: dir + '/13-concluido.png' });
    await p.locator('#folha button', { hasText: 'Fechar' }).click();
    await p.waitForTimeout(2500);
    const s2 = await selo('SIGADAER');
    ok(s2 === 'Conecte o token' || s2 === 'Pronto', 'depois de preparar, SIGADAER fica ' + s2);
    await p.screenshot({ path: dir + '/14-depois.png' });
  } else {
    ok((await selo('SIAFI')) === 'Falta instalar', 'SIAFI aparece como Falta instalar');
    ok((await selo('SIGADAER')) === 'Precisa de reparo', 'SIGADAER aparece como Precisa de reparo');
    // Reparar o SIGADAER
    await cartao('SIGADAER').locator('button', { hasText: 'Reparar' }).click();
    await p.waitForSelector('#folha .folha-lista');
    await p.screenshot({ path: dir + '/20-confirmar-reparo.png' });
    await p.locator('#folha button', { hasText: 'Continuar' }).click();
    await p.waitForSelector('#folha button:has-text("Fechar")', { timeout: 60000 });
    ok((await p.locator('#folha h2').innerText()) === 'Pronto', 'reparo simulado termina em Pronto');
    await p.locator('#folha button', { hasText: 'Fechar' }).click();
    await p.waitForTimeout(2500);
    ok((await selo('SIGADAER')) === 'Pronto', 'SIGADAER fica Pronto depois do reparo (' + await selo('SIGADAER') + ')');
    ok((await selo('Assinar PDF')) === 'Pronto', 'Assinar PDF fica Pronto depois do reparo');
    // Preparar o SIAFI
    await cartao('SIAFI').locator('button', { hasText: 'Preparar' }).click();
    await p.waitForSelector('#folha .folha-lista');
    const n2 = await p.locator('#folha .folha-item strong').allInnerTexts();
    ok(n2.length === 1 && n2[0] === 'Java 8 Update 91', 'SIAFI pede só o Java 8 (' + n2.join(',') + ')');
    await p.locator('#folha button', { hasText: 'Continuar' }).click();
    await p.waitForSelector('#folha button:has-text("Fechar")', { timeout: 60000 });
    await p.locator('#folha button', { hasText: 'Fechar' }).click();
    await p.waitForTimeout(2500);
    ok((await selo('SIAFI')) === 'Pronto', 'SIAFI fica Pronto (' + await selo('SIAFI') + ')');
    await p.mouse.move(520, 420); await p.waitForTimeout(700);
    await p.screenshot({ path: dir + '/21-sistemas-prontos.png' });
    // Abrir site (na demonstração só responde)
    await cartao('SIAFI').locator('button', { hasText: 'Abrir' }).click();
    await p.waitForSelector('#brinde:not([hidden])');
    console.log('     brinde:', await p.locator('#brinde').innerText());
    // Busca
    await p.fill('#busca', 'siafi');
    await p.waitForTimeout(300);
    const vis = await p.locator('#conteudo .grade > .cartao:visible h2').allInnerTexts();
    ok(vis.length === 1 && vis[0].startsWith('SIAFI'), 'busca por "siafi" deixa só o cartão do SIAFI (' + vis.join(',') + ')');
    await p.fill('#busca', '');
    // Tutoriais
    await cartao('SIGADAER').locator('button', { hasText: 'Tutorial' }).click();
    await p.waitForTimeout(400);
    ok((await p.locator('.tuto h2').innerText()) === 'Assinar documento no SIGADAER', 'botão Tutorial abre o tutorial do SIGADAER');
    await p.screenshot({ path: dir + '/22-tutorial-sigadaer.png' });
    await p.locator('.tuto-item', { hasText: 'SIAFI' }).click();
    await p.waitForTimeout(300);
    ok((await p.locator('.tuto .passo').count()) === 5, 'tutorial do SIAFI tem 5 passos');
    await p.fill('#busca', 'proxy');
    await p.waitForTimeout(300);
    const tl = await p.locator('.tuto-item strong').allInnerTexts();
    ok(tl.length === 1 && /SIAFI/.test(tl[0]), 'busca "proxy" nos tutoriais acha o do SIAFI (' + tl.join(',') + ')');
    await p.fill('#busca', '');
    // Tokens: instalar o DXSafe
    await p.click('#nav [data-pagina="tokens"]');
    await p.waitForTimeout(400);
    await cartao('DXToken').locator('button', { hasText: 'Instalar' }).click();
    await p.waitForSelector('#folha .folha-lista');
    await p.locator('#folha button', { hasText: 'Continuar' }).click();
    await p.waitForSelector('#folha button:has-text("Fechar")', { timeout: 60000 });
    await p.locator('#folha button', { hasText: 'Fechar' }).click();
    await p.waitForTimeout(2500);
    console.log('     DXToken depois:', await selo('DXToken'));
    await p.screenshot({ path: dir + '/23-tokens-depois.png' });
    // Diagnóstico com histórico
    await p.click('#nav [data-pagina="diagnostico"]');
    await p.waitForTimeout(900);
    await p.locator('#conteudo').evaluate(el => el.scrollTo(0, 400));
    await p.waitForTimeout(300);
    await p.screenshot({ path: dir + '/24-diagnostico-baixo.png' });
    // Janela pequena
    await p.setViewportSize({ width: 920, height: 620 });
    await p.click('#nav [data-pagina="sistemas"]');
    await p.waitForTimeout(500);
    await p.screenshot({ path: dir + '/25-janela-pequena.png' });
    const larg = await p.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
    ok(larg <= 0, 'sem rolagem horizontal na janela pequena');
  }
  console.log('ERROS ' + erros.length); erros.forEach(e => console.log('  ' + e));
  await b.close();
  process.exit(erros.length ? 1 : 0);
})().catch(e => { console.error('FALHA GERAL', e.message); process.exit(1); });
