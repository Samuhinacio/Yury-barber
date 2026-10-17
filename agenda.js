// © 2026 Samuel Inácio José. Todos os direitos reservados. Uso, cópia ou modificação somente com autorização. Ver LICENSE.
// =====================================================================
// Agenda inteligente — usada pelo site (index.html) e pelo painel (admin.html)
// Calcula os horários livres de um barbeiro para um serviço, encaixando
// atendimentos curtos nas sobras que os outros serviços deixam.
// =====================================================================
window.AgendaYP = (() => {
  const toMin = hm => { const [h, m] = String(hm).split(":").map(Number); return h * 60 + m; };
  const toHm = m => String(Math.floor(m / 60)).padStart(2, "0") + ":" + String(m % 60).padStart(2, "0");

  // Partes livres do dia: [abre, fecha] menos os compromissos (busy = [[início, fim], ...] em minutos)
  function gaps(open, close, busy) {
    const list = busy.map(([a, b]) => [Math.max(a, open), Math.min(b, close)]).filter(([a, b]) => b > a).sort((x, y) => x[0] - y[0]);
    const out = [];
    let t = open;
    for (const [a, b] of list) {
      if (a > t) out.push([t, a]);
      t = Math.max(t, b);
    }
    if (close > t) out.push([t, close]);
    return out;
  }

  // Horários em que dá para começar um serviço de `dur` minutos:
  //  - a grade normal da barbearia (abre + intervalo, intervalo, ...);
  //  - logo que termina cada atendimento ou bloqueio (encaixe na sobra);
  //  - colado no próximo compromisso, para a sobra antes dele não ficar perdida.
  function slots({ open, close, step, dur, busy, minStart = -1 }) {
    const set = new Set();
    for (const [gs, ge] of gaps(open, close, busy)) {
      if (ge - gs < dur) continue;
      for (let m = open; m + dur <= ge; m += step) if (m >= gs) set.add(m);
      if (gs > open) set.add(gs);
      if (ge < close) set.add(ge - dur);
    }
    return [...set].filter(m => m > minStart).sort((a, b) => a - b);
  }

  // Um bloqueio vale para o dia `date` (YYYY-MM-DD)? Com data: só nela. Com dia_semana: toda semana.
  function blockOn(b, date) {
    if (b.data) return b.data === date;
    const [y, m, d] = date.split("-").map(Number);
    return Number(b.dia_semana) === new Date(y, m - 1, d).getDay();
  }

  // Barbeiros cadastrados (equipe com foto). Aceita o formato antigo: só a lista de nomes.
  function team(cfg) {
    const eq = Array.isArray(cfg && cfg.equipe) && cfg.equipe.length ? cfg.equipe
      : (Array.isArray(cfg && cfg.barbeiros) ? cfg.barbeiros : []).map((n, i) => ({ id: "b" + (i + 1), nome: n, foto: /^yury/i.test(n) ? "fotos/yury.webp" : "", ativo: true }));
    return eq.filter(b => b && b.nome).map(b => ({ id: String(b.id || b.nome), nome: String(b.nome), foto: b.foto || "", ativo: b.ativo !== false }));
  }

  return { toMin, toHm, gaps, slots, blockOn, team };
})();
