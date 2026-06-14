/* ═══════════════════════════════════════════════════════
   DEBTORA CZ — Ověření nájemce (frontend modul)
   Mock režim pro vývoj UI; 'live' režim volá Supabase
   Edge Function `verify` (fáze 2, viz SPEC-overeni-najemce.md)
   ═══════════════════════════════════════════════════════ */
(function () {
  'use strict';

  var VERIFY_CONFIG = {
    mode: 'mock',                       // 'mock' | 'live'
    endpoint: '/functions/v1/verify',   // Supabase Edge Function
    ceePrice: 122                       // Kč za kontrolu CEE (5 % pod trhem)
  };

  // Definice rejstříků zobrazených ve výsledcích.
  // Pozn.: u ISIR/CEE/DPH je dobrá zpráva "nenalezen", u ARES naopak "subjekt existuje".
  var REGISTRIES = [
    { id: 'isir', name: 'Insolvenční rejstřík (ISIR)', icon: '⚖️', tier: 'free', appliesTo: ['fo', 'po'],
      clearText: 'Záznam nenalezen — osoba není v insolvenci.',
      foundText: 'Nalezeno insolvenční řízení — doporučujeme prověřit detail.' },
    { id: 'ares', name: 'Registr subjektů ARES',        icon: '🏛️', tier: 'free', appliesTo: ['po'],
      clearText: 'Subjekt v registru existuje a je aktivní, bez negativních záznamů (likvidace, zánik).',
      foundText: 'Zjištěn problém — subjekt neexistuje, zanikl nebo je v likvidaci.' },
    { id: 'dph',  name: 'Nespolehlivý plátce DPH',      icon: '🧾', tier: 'free', appliesTo: ['po'],
      clearText: 'Subjekt není veden jako nespolehlivý plátce DPH.',
      foundText: 'Subjekt je veden jako nespolehlivý plátce DPH.' },
    { id: 'cee',  name: 'Centrální evidence exekucí',   icon: '🔨', tier: 'paid', appliesTo: ['fo', 'po'],
      clearText: 'Záznam nenalezen — žádné aktivní exekuce.',
      foundText: 'Nalezeny exekuce — doporučujeme prověřit detail.' }
  ];

  var subjectType = 'fo';
  var lastSubject = null; // subjekt poslední kontroly (pro platbu CEE)
  var $ = function (id) { return document.getElementById(id); };

  function getAuthUser() {
    try { return (typeof Auth !== 'undefined' && Auth.getUser()) || null; } catch (e) { return null; }
  }

  // ── Přepínač FO / PO ──
  function setSubject(type) {
    subjectType = type;
    $('toggle-fo').classList.toggle('active', type === 'fo');
    $('toggle-po').classList.toggle('active', type === 'po');
    $('fields-fo').style.display = type === 'fo' ? '' : 'none';
    $('fields-po').style.display = type === 'po' ? '' : 'none';
  }

  // ── Validace ──
  function validate() {
    var errors = [];
    if (subjectType === 'fo') {
      if (!$('vf-firstname').value.trim()) errors.push('Vyplňte jméno.');
      if (!$('vf-lastname').value.trim()) errors.push('Vyplňte příjmení.');
      if (!$('vf-birthdate').value) errors.push('Vyplňte datum narození.');
      var rc = $('vf-rc').value.replace(/\D/g, '');
      if ($('vf-rc').value && (rc.length < 9 || rc.length > 10)) errors.push('Rodné číslo má 9–10 číslic.');
    } else {
      var ico = $('vf-ico').value.replace(/\D/g, '');
      if (ico.length !== 8 || !validateIco(ico)) errors.push('Zadejte platné osmimístné IČO.');
    }
    if (!$('vf-consent').checked) errors.push('Potvrďte účel ověření (GDPR).');
    return errors;
  }

  // Kontrolní součet IČO (mod 11)
  function validateIco(ico) {
    var sum = 0;
    for (var i = 0; i < 7; i++) sum += parseInt(ico[i], 10) * (8 - i);
    var check = (11 - (sum % 11)) % 10;
    return check === parseInt(ico[7], 10);
  }

  function getSubjectPayload() {
    if (subjectType === 'fo') {
      return {
        type: 'fo',
        firstName: $('vf-firstname').value.trim(),
        lastName: $('vf-lastname').value.trim(),
        birthDate: $('vf-birthdate').value,
        rc: $('vf-rc').value.replace(/\D/g, '') || null
      };
    }
    return { type: 'po', ico: $('vf-ico').value.replace(/\D/g, '') };
  }

  function subjectLabel(s) {
    return s.type === 'fo'
      ? s.firstName + ' ' + s.lastName + ', nar. ' + formatDate(s.birthDate)
      : 'IČO ' + s.ico;
  }

  function formatDate(iso) {
    if (!iso) return '';
    var p = iso.split('-');
    return p[2] + '. ' + parseInt(p[1], 10) + '. ' + p[0];
  }

  // ── Dotaz na rejstříky ──
  function runVerification(subject, spendCredit) {
    if (VERIFY_CONFIG.mode === 'live') {
      return window.sbClient.functions.invoke('verify', { body: { subject: subject, spendCredit: !!spendCredit } })
        .then(function (res) {
          if (res.error) throw res.error;
          return res.data.results;
        });
    }
    return mockVerification(subject);
  }

  // Mock: deterministický výsledek podle vstupu, ~1.5 s odezva
  function mockVerification(subject) {
    var seed = (subject.type === 'fo' ? subject.lastName + subject.birthDate : subject.ico)
      .split('').reduce(function (a, c) { return a + c.charCodeAt(0); }, 0);
    var results = {};
    REGISTRIES.forEach(function (reg) {
      if (reg.appliesTo.indexOf(subject.type) === -1) return;
      if (reg.tier === 'paid') { results[reg.id] = { status: 'locked' }; return; }
      var found = (seed + reg.id.length) % 5 === 0; // ~20 % "nalezeno" pro demo
      results[reg.id] = found
        ? { status: 'found', detail: mockDetail(reg.id) }
        : { status: 'clear' };
    });
    return new Promise(function (resolve) { setTimeout(function () { resolve(results); }, 1500); });
  }

  function mockDetail(regId) {
    var d = {
      isir: 'Spisová značka: KSBR 28 INS 1234/2023 · Stav: Oddlužení — plnění splátkového kalendáře',
      ares: 'Subjekt v likvidaci od 12. 3. 2024',
      dph: 'Nespolehlivý plátce od 1. 6. 2023'
    };
    return d[regId] || 'Nalezen záznam';
  }

  // ── Render výsledků ──
  function renderResults(subject, results) {
    var cards = $('result-cards');
    cards.innerHTML = '';
    var foundCount = 0, checkedCount = 0;

    REGISTRIES.forEach(function (reg) {
      if (reg.appliesTo.indexOf(subject.type) === -1) return;
      var r = results[reg.id] || { status: 'error' };
      if (r.status === 'found') foundCount++;
      if (r.status === 'clear' || r.status === 'found') checkedCount++;
      cards.appendChild(resultCard(reg, r));
    });

    var badge = $('risk-badge');
    badge.className = 'risk-badge';
    if (foundCount === 0 && checkedCount > 0) {
      badge.classList.add('risk-low'); badge.textContent = 'Nízké riziko';
    } else if (foundCount === 1) {
      badge.classList.add('risk-mid'); badge.textContent = 'Střední riziko';
    } else if (foundCount > 1) {
      badge.classList.add('risk-high'); badge.textContent = 'Vysoké riziko';
    } else {
      badge.classList.add('risk-mid'); badge.textContent = 'Neúplné ověření';
    }

    $('result-subject').textContent = subjectLabel(subject) +
      ' · ověřeno ' + checkedCount + ' z ' + Object.keys(results).length + ' rejstříků';

    $('verify-form-card').style.display = 'none';
    $('verify-loading').style.display = 'none';
    $('verify-results').style.display = 'block';
    window.scrollTo({ top: $('verify-results').offsetTop - 140, behavior: 'smooth' });
  }

  function resultCard(reg, r) {
    var card = document.createElement('div');
    var icon, title, desc, extra = '';
    switch (r.status) {
      case 'clear':
        card.className = 'result-card';
        icon = '<div class="result-status-icon rs-clear">✓</div>';
        title = reg.name;
        desc = escapeHtml(reg.clearText || 'Záznam nenalezen.');
        if (r.detail) extra = '<div class="result-detail">' + escapeHtml(r.detail) + '</div>';
        break;
      case 'found':
        card.className = 'result-card found';
        icon = '<div class="result-status-icon rs-found">!</div>';
        title = reg.name;
        desc = escapeHtml(reg.foundText || 'Nalezen záznam — doporučujeme prověřit detail.');
        extra = '<div class="result-detail">' + escapeHtml(r.detail || '') + '</div>';
        break;
      case 'locked':
        card.className = 'result-card locked';
        icon = '<div class="result-status-icon rs-locked">🔒</div>';
        title = reg.name;
        desc = 'Placená kontrola — výpis aktivních exekucí vč. spisových značek.';
        break;
      default: // 'error' | 'unavailable'
        card.className = 'result-card';
        icon = '<div class="result-status-icon rs-error">?</div>';
        title = reg.name;
        desc = escapeHtml(r.message || 'Rejstřík se nepodařilo dotázat. Zkuste to prosím později.');
    }
    card.innerHTML = icon +
      '<div class="result-body"><h4>' + escapeHtml(title) + '</h4><p>' + desc + '</p>' + extra + '</div>' +
      (r.status === 'locked'
        ? '<button type="button" class="btn-primary unlock-cee">Odemknout za ' + VERIFY_CONFIG.ceePrice + ' Kč</button>'
        : '');
    var unlock = card.querySelector('.unlock-cee');
    if (unlock) unlock.addEventListener('click', onUnlockCee);
    return card;
  }

  // ═══ PLATBA (Comgate) ═══
  function onUnlockCee() {
    if (!lastSubject) return;
    var user = getAuthUser();
    if (user && user.email) $('pay-email').value = user.email;
    $('pay-overlay').classList.add('open');
  }

  function closePayModal() { $('pay-overlay').classList.remove('open'); }

  function selectedProduct() {
    var r = document.querySelector('input[name="pay-product"]:checked');
    return r ? r.value : 'single';
  }

  function startPayment() {
    var product = selectedProduct();
    var email = $('pay-email').value.trim();
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(email)) {
      window.showToast('Zadejte platný e-mail — potřebujeme ho pro fakturu a zaslání výsledku.', 'error');
      return;
    }
    if (product !== 'single' && !getAuthUser()) {
      window.showToast('Balíček kontrol vyžaduje přihlášení k účtu.', 'error');
      sessionStorage.setItem('debtora_redirect', window.location.href);
      setTimeout(function () { window.location.href = 'prihlaseni.html'; }, 1200);
      return;
    }
    var btn = $('pay-submit');
    btn.disabled = true; btn.textContent = 'Přesměrováváme na bránu…';

    window.sbClient.functions.invoke('payment-create', {
      body: { action: 'create', product: product, email: email, subject: lastSubject }
    }).then(function (res) {
      if (res.error || !res.data || !res.data.redirect) throw (res.error || new Error('no redirect'));
      localStorage.setItem('debtora_pay_token', res.data.token);
      localStorage.setItem('debtora_pay_product', product);
      window.location.href = res.data.redirect;
    }).catch(function (e) {
      btn.disabled = false; btn.textContent = 'Zaplatit přes Comgate →';
      var msg = (e && e.context && e.context.error) || 'Platbu se nepodařilo založit. Zkuste to prosím znovu.';
      window.showToast(typeof msg === 'string' ? msg : 'Platbu se nepodařilo založit.', 'error');
    });
  }

  // Návrat z platební brány: ?status=PAID|CANCELLED (návratová URL v Comgate portálu)
  function handlePaymentReturn() {
    var qs = new URLSearchParams(window.location.search);
    var status = qs.get('status');
    if (!status) return;
    window.history.replaceState({}, '', window.location.pathname);

    if (status === 'CANCELLED') {
      window.showToast('Platba byla zrušena. Kontrolu můžete zkusit znovu.', 'error');
      localStorage.removeItem('debtora_pay_token');
      return;
    }
    var token = localStorage.getItem('debtora_pay_token');
    if (!token) return;

    $('verify-form-card').style.display = 'none';
    $('verify-loading').style.display = 'block';
    $('loading-text').textContent = 'Ověřujeme platbu a dotazujeme evidenci exekucí…';
    pollPayment(token, 0);
  }

  function pollPayment(token, attempt) {
    if (attempt > 15) {
      $('verify-loading').style.display = 'none';
      $('verify-form-card').style.display = '';
      window.showToast('Platbu stále zpracováváme. Výsledek vám přijde na e-mail.', 'info');
      return;
    }
    window.sbClient.functions.invoke('payment-create', { body: { action: 'status', token: token } })
      .then(function (res) {
        var d = res.data || {};
        if (d.status === 'paid') {
          localStorage.removeItem('debtora_pay_token');
          $('verify-loading').style.display = 'none';
          if (d.product === 'single') {
            renderPaidCee(d.cee);
          } else {
            $('verify-form-card').style.display = '';
            window.showToast('Zaplaceno — připsali jsme vám ' + (d.credits || '') + ' kreditů. Spusťte ověření, kontrola exekucí proběhne automaticky.', 'success');
          }
        } else if (d.status === 'cancelled' || d.status === 'error') {
          localStorage.removeItem('debtora_pay_token');
          $('verify-loading').style.display = 'none';
          $('verify-form-card').style.display = '';
          window.showToast('Platba neproběhla. Zkuste to prosím znovu.', 'error');
        } else {
          setTimeout(function () { pollPayment(token, attempt + 1); }, 2000);
        }
      })
      .catch(function () { setTimeout(function () { pollPayment(token, attempt + 1); }, 2000); });
  }

  function renderPaidCee(cee) {
    var reg = REGISTRIES.filter(function (r) { return r.id === 'cee'; })[0];
    var badge = $('risk-badge');
    badge.className = 'risk-badge';
    var r = cee || { status: 'error', message: 'Výsledek zpracováváme — přijde vám na e-mail.' };
    if (r.status === 'clear') { badge.classList.add('risk-low'); badge.textContent = 'Bez exekucí'; }
    else if (r.status === 'found') { badge.classList.add('risk-high'); badge.textContent = 'Nalezeny exekuce'; }
    else { badge.classList.add('risk-mid'); badge.textContent = 'Zpracovává se'; }
    $('result-subject').textContent = 'Placená kontrola — Centrální evidence exekucí';
    var cards = $('result-cards');
    cards.innerHTML = '';
    cards.appendChild(resultCard(reg, r));
    $('verify-results').style.display = 'block';
  }

  function escapeHtml(s) {
    return String(s).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }

  // ── Eventy ──
  document.addEventListener('DOMContentLoaded', function () {
    if (!$('verify-form')) return;

    $('toggle-fo').addEventListener('click', function () { setSubject('fo'); });
    $('toggle-po').addEventListener('click', function () { setSubject('po'); });

    $('verify-form').addEventListener('submit', function (e) {
      e.preventDefault();
      var errors = validate();
      if (errors.length) {
        if (typeof window.showToast === 'function') window.showToast(errors[0], 'error');
        else alert(errors.join('\n'));
        return;
      }
      var subject = getSubjectPayload();
      lastSubject = subject;
      $('verify-form-card').style.display = 'none';
      $('verify-loading').style.display = 'block';

      runVerification(subject)
        .then(function (results) { renderResults(subject, results); })
        .catch(function () {
          $('verify-loading').style.display = 'none';
          $('verify-form-card').style.display = '';
          if (typeof window.showToast === 'function') window.showToast('Ověření se nezdařilo. Zkuste to prosím znovu.', 'error');
        });
    });

    $('new-check').addEventListener('click', function () {
      $('verify-results').style.display = 'none';
      $('verify-form-card').style.display = '';
      window.scrollTo({ top: 0, behavior: 'smooth' });
    });

    // ── Platební modal ──
    $('pay-close').addEventListener('click', closePayModal);
    $('pay-overlay').addEventListener('click', function (e) {
      if (e.target === this) closePayModal();
    });
    document.querySelectorAll('input[name="pay-product"]').forEach(function (radio) {
      radio.addEventListener('change', function () {
        document.querySelectorAll('.pay-option').forEach(function (o) { o.classList.remove('selected'); });
        radio.closest('.pay-option').classList.add('selected');
      });
    });
    $('pay-submit').addEventListener('click', startPayment);

    // Použití kreditu (jen přihlášení)
    var useCredit = $('pay-use-credit');
    if (useCredit) {
      if (getAuthUser()) useCredit.style.display = '';
      useCredit.addEventListener('click', function () {
        closePayModal();
        if (!lastSubject) return;
        $('verify-results').style.display = 'none';
        $('verify-loading').style.display = 'block';
        $('loading-text').textContent = 'Čerpáme kredit a dotazujeme evidenci exekucí…';
        runVerification(lastSubject, true)
          .then(function (results) { renderResults(lastSubject, results); })
          .catch(function () {
            $('verify-loading').style.display = 'none';
            $('verify-form-card').style.display = '';
            window.showToast('Ověření se nezdařilo. Kredit nebyl čerpán.', 'error');
          });
      });
    }

    // Návrat z platební brány
    handlePaymentReturn();
  });
})();
