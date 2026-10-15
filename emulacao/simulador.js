/* Emulação do Laçador: faz o papel do serviço local (Lacador.ps1). A tela é a mesma do programa;
   os estados foram calculados pelo motor de verdade, com os dados de exemplo. Nada é instalado. */
(function () {
  'use strict';
  var E = window.EMU;
  var ORDEM = ['assinador', 'java8', 'dxsafe', 'java7', 'adobe-xi', 'ajuste-dexon', 'acesso'];
  var feitos = {}, rodada = 0, fase = 'verificando', percentual = 2, etapa = 'Carregando o sistema...';
  var estado = null, acao = null, acesso = null, historico = [], sequencia = 0, verificando = false;

  function chave() { return ORDEM.filter(function (k) { return feitos[k]; }).join(','); }
  function dois(n) { return (n < 10 ? '0' : '') + n; }
  function agora() {
    var d = new Date();
    return d.getFullYear() + '-' + dois(d.getMonth() + 1) + '-' + dois(d.getDate()) + 'T' + dois(d.getHours()) + ':' + dois(d.getMinutes()) + ':' + dois(d.getSeconds());
  }
  function copia(o) { return JSON.parse(JSON.stringify(o)); }

  function verificar() {
    if (verificando) return;
    verificando = true; fase = 'verificando'; percentual = 2; etapa = 'Carregando o sistema...';
    var passos = [[12, 'Lendo o Windows...'], [30, 'Procurando tokens conectados...'], [52, 'Lendo os certificados...'], [72, 'Verificando o Firefox e a extensão...'], [90, 'Verificando o Java...']];
    passos.forEach(function (p, i) { setTimeout(function () { percentual = p[0]; etapa = p[1]; }, 230 * i); });
    setTimeout(function () {
      estado = copia(E.estados[chave()]);
      estado.coletadoEm = agora();
      percentual = 100; rodada++; fase = 'pronto'; verificando = false;
    }, 230 * passos.length);
  }

  function iniciarAcao(c) {
    if (acao && acao.estado === 'executando') return { ok: false, mensagem: 'Já existe uma instalação em andamento.' };
    if (!estado) return { ok: false, mensagem: 'Aguarde a verificação terminar.' };
    if (c.acao !== 'instalar' && c.acao !== 'reparar') return { ok: false, mensagem: 'Ação inválida.' };
    var pedidos = {};
    (c.sistemas || []).forEach(function (sid) {
      var s = estado.sistemas.filter(function (x) { return x.id === sid; })[0];
      if (s) s.faltando.concat(s.reparar).forEach(function (id) { pedidos[id] = true; });
    });
    (c.itens || []).forEach(function (id) { if (estado.itens[id]) pedidos[id] = true; });
    var ids = Object.keys(estado.itens).filter(function (id) { return pedidos[id]; });   // ordem do catálogo
    if (!ids.length) return { ok: false, mensagem: 'Nada a fazer: já está tudo em ordem.' };
    var nova = {
      id: 'emu' + (++sequencia), acao: c.acao, via: 'demonstracao', estado: 'executando', mensagem: '', reiniciar: false,
      passos: ids.map(function (id) { return { item: id, nome: estado.itens[id].nome, estado: 'pendente', mensagens: [] }; })
    };
    acao = nova;
    function passo(i) {
      if (i >= nova.passos.length) {
        nova.estado = 'concluido';
        ids.forEach(function (id) { if (ORDEM.indexOf(id) >= 0) feitos[id] = true; });
        historico.unshift({ quando: agora(), acao: c.acao, itens: ids, resultado: 'concluido', via: 'demonstracao', demonstracao: true });
        verificar();
        return;
      }
      nova.passos[i].estado = 'executando';
      setTimeout(function () {
        nova.passos[i].estado = 'ok';
        nova.passos[i].mensagens = ['Simulação: nada foi instalado.'];
        passo(i + 1);
      }, 1100);
    }
    passo(0);
    return { ok: true, id: nova.id, via: nova.via };
  }

  function iniciarAcesso(c) {
    if (c.acao !== 'liberar' && c.acao !== 'remover') return { ok: false, mensagem: 'Ação inválida.' };
    if (acesso && acesso.estado === 'executando') return { ok: false, mensagem: 'Já existe uma operação em andamento.' };
    if (acao && acao.estado === 'executando') return { ok: false, mensagem: 'Espere a instalação em andamento terminar.' };
    var novo = { tipo: c.acao, estado: 'executando', mensagem: '' };
    acesso = novo;
    setTimeout(function () {
      if (c.acao === 'liberar') feitos.acesso = true; else delete feitos.acesso;
      novo.estado = 'concluido';
      novo.mensagem = 'Simulação: nada foi alterado neste computador.';
      verificar();
    }, 2400);
    return { ok: true };
  }

  function rota(caminho, metodo, corpo) {
    if (caminho === '/api/estado') return { fase: fase, percentual: percentual, etapa: etapa, rodada: rodada, erro: null, versao: E.versao, estado: estado, acao: acao, acesso: acesso };
    if (caminho === '/api/acesso') return iniciarAcesso(corpo || {});
    if (caminho === '/api/acesso/fechar') { if (acesso && acesso.estado !== 'executando') acesso = null; return { ok: true }; }
    if (caminho === '/api/verificar') { verificar(); return { ok: true }; }
    if (caminho === '/api/acao') return iniciarAcao(corpo || {});
    if (caminho === '/api/acao/fechar') { if (acao && acao.estado !== 'executando') acao = null; return { ok: true }; }
    if (caminho === '/api/usuario') {
      if (corpo && corpo.operacao === 'assinador-token') { feitos['ajuste-dexon'] = true; verificar(); }
      return { ok: true, mensagem: 'Demonstração: no uso real, esta ação seria executada agora.' };
    }
    if (caminho === '/api/tutoriais') return E.tutoriais;
    if (caminho === '/api/historico') return { itens: historico };
    return { ok: false, mensagem: 'não encontrado' };
  }

  var original = window.fetch;
  window.fetch = function (url, opcoes) {
    var u = String(url);
    if (u.indexOf('/api/') !== 0) return original.apply(this, arguments);
    var corpo;
    try { corpo = opcoes && opcoes.body ? JSON.parse(opcoes.body) : undefined; } catch (e) { corpo = undefined; }
    var resposta = copia(rota(u.split('?')[0], (opcoes && opcoes.method) || 'GET', corpo));
    return Promise.resolve({ ok: true, status: 200, json: function () { return Promise.resolve(resposta); }, text: function () { return Promise.resolve(JSON.stringify(resposta)); } });
  };
  try { navigator.sendBeacon = function () { return true; }; } catch (e) { /* sem problema */ }

  verificar();
})();
