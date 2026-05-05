/**
 * Med_Pront Enhancements — Vanilla JS para OpenEMR
 * Injetado via custom.yaml (mecanismo oficial Header.php)
 *
 * Funcionalidades:
 * 1. Sidebar toggle (collapse/expand mobile)
 * 2. Máscaras de input (CPF, CEP, telefone)
 * 3. Validação inline de formulários
 * 4. Melhorias de acessibilidade (skip-to-content, focus trapping)
 */

(function () {
  'use strict';

  /* ============================================================
   * 1. SIDEBAR TOGGLE
   * ============================================================ */
  function initSidebar() {
    var sidebar = document.querySelector('.sidebar, #mainSidebar, nav.navbar-dark');
    if (!sidebar) return;

    var toggleBtn = document.createElement('button');
    toggleBtn.className = 'medpront-sidebar-toggle';
    toggleBtn.setAttribute('aria-label', 'Alternar menu lateral');
    toggleBtn.setAttribute('aria-expanded', 'true');
    toggleBtn.innerHTML =
      '<svg width="20" height="20" viewBox="0 0 20 20" fill="none"><path d="M3 5h14M3 10h14M3 15h14" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg>';

    var topbar = document.querySelector('.navbar, .navbar-light, .sticky-top');
    if (topbar) {
      topbar.insertBefore(toggleBtn, topbar.firstChild);
    }

    var collapsed = false;
    toggleBtn.addEventListener('click', function () {
      collapsed = !collapsed;
      document.body.classList.toggle('sidebar-collapsed', collapsed);
      toggleBtn.setAttribute('aria-expanded', String(!collapsed));
      localStorage.setItem('medpront-sidebar-collapsed', String(collapsed));
    });

    if (localStorage.getItem('medpront-sidebar-collapsed') === 'true') {
      collapsed = true;
      document.body.classList.add('sidebar-collapsed');
      toggleBtn.setAttribute('aria-expanded', 'false');
    }
  }

  /* ============================================================
   * 2. INPUT MASKS
   * ============================================================ */
  var masks = {
    cpf: {
      pattern: [/\d/, /\d/, /\d/, '.', /\d/, /\d/, /\d/, '.', /\d/, /\d/, /\d/, '-', /\d/, /\d/],
      selector: 'input[data-mask="cpf"], input[id*="cpf"], input[name*="cpf"], .cpf-mask input',
      clean: function (v) { return v.replace(/\D/g, '').slice(0, 11); }
    },
    cep: {
      pattern: [/\d/, /\d/, /\d/, /\d/, /\d/, '-', /\d/, /\d/, /\d/],
      selector: 'input[data-mask="cep"], input[id*="cep"], input[name*="cep"], .cep-mask input',
      clean: function (v) { return v.replace(/\D/g, '').slice(0, 8); }
    },
    phone: {
      apply: function (input, raw) {
        var ddd = raw.slice(0, 2);
        var rest = raw.slice(2);
        if (rest.length > 8) {
          return '(' + ddd + ') ' + rest.slice(0, 5) + '-' + rest.slice(5, 9);
        }
        if (rest.length > 4) {
          return '(' + ddd + ') ' + rest.slice(0, 4) + '-' + rest.slice(4, 8);
        }
        if (ddd.length === 2) return '(' + ddd + ') ' + rest;
        if (ddd.length > 0) return '(' + ddd;
        return raw;
      },
      selector: 'input[data-mask="phone"], input[id*="phone"], input[name*="phone"], input[type="tel"], .phone-mask input',
      clean: function (v) { return v.replace(/\D/g, '').slice(0, 11); }
    }
  };

  function applyMask(input, maskDef) {
    input.addEventListener('input', function () {
      var raw = maskDef.clean(input.value);
      var formatted = '';

      if (maskDef.pattern) {
        var ri = 0;
        for (var i = 0; i < maskDef.pattern.length && ri < raw.length; i++) {
          var ch = maskDef.pattern[i];
          if (typeof ch === 'string') {
            formatted += ch;
          } else {
            formatted += raw[ri];
            ri++;
          }
        }
      } else if (maskDef.apply) {
        formatted = maskDef.apply(input, raw);
      }

      input.value = formatted;
    });

    input.addEventListener('blur', function () {
      var raw = maskDef.clean(input.value);
      if (maskDef.apply) {
        input.value = maskDef.apply(input, raw);
      }
    });
  }

  function initMasks() {
    Object.keys(masks).forEach(function (key) {
      var def = masks[key];
      document.querySelectorAll(def.selector).forEach(function (el) {
        if (el.tagName === 'INPUT' && !el.dataset.maskApplied) {
          el.dataset.maskApplied = 'true';
          applyMask(el, def);
        }
      });
    });

    // MutationObserver para inputs adicionados dinamicamente
    var observer = new MutationObserver(function () {
      initMasks();
    });
    observer.observe(document.body, { childList: true, subtree: true });
  }

  /* ============================================================
   * 3. INLINE FORM VALIDATION
   * ============================================================ */
  function initFormValidation() {
    document.addEventListener('submit', function (e) {
      var form = e.target.closest('form');
      if (!form || form.getAttribute('novalidate') !== null) return;
      if (!form.classList.contains('medpront-validate')) return;

      var valid = true;
      form.querySelectorAll('input[required], select[required], textarea[required]').forEach(function (el) {
        removeFeedback(el);
        if (!el.value.trim()) {
          showFeedback(el, 'Este campo é obrigatório.');
          valid = true;
        }
      });

      form.querySelectorAll('input[data-validate]').forEach(function (el) {
        removeFeedback(el);
        var type = el.dataset.validate;
        if (type === 'cpf' && el.value && !validateCPF(el.value)) {
          showFeedback(el, 'CPF inválido.');
        }
        if (type === 'email' && el.value && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(el.value)) {
          showFeedback(el, 'E-mail inválido.');
        }
      });

      if (!valid) {
        e.preventDefault();
        var firstError = form.querySelector('.medpront-is-invalid');
        if (firstError) firstError.focus();
      }
    });

    document.addEventListener('input', function (e) {
      var el = e.target.closest('.medpront-is-invalid');
      if (el && el.value.trim()) {
        removeFeedback(el);
      }
    });
  }

  function showFeedback(el, message) {
    el.classList.add('medpront-is-invalid', 'is-invalid');
    var feedback = document.createElement('div');
    feedback.className = 'medpront-invalid-feedback invalid-feedback';
    feedback.textContent = message;
    el.parentNode.appendChild(feedback);
  }

  function removeFeedback(el) {
    el.classList.remove('medpront-is-invalid', 'is-invalid');
    var feedback = el.parentNode.querySelector('.medpront-invalid-feedback');
    if (feedback) feedback.remove();
  }

  function validateCPF(cpf) {
    cpf = cpf.replace(/\D/g, '');
    if (cpf.length !== 11 || /^(\d)\1+$/.test(cpf)) return false;
    var sum = 0, rem;
    for (var i = 0; i < 9; i++) sum += parseInt(cpf[i]) * (10 - i);
    rem = (sum * 10) % 11;
    if (rem === 10) rem = 0;
    if (rem !== parseInt(cpf[9])) return false;
    sum = 0;
    for (var j = 0; j < 10; j++) sum += parseInt(cpf[j]) * (11 - j);
    rem = (sum * 10) % 11;
    if (rem === 10) rem = 0;
    return rem === parseInt(cpf[10]);
  }

  /* ============================================================
   * 4. ACCESSIBILITY: SKIP-TO-CONTENT
   * ============================================================ */
  function initSkipLink() {
    var link = document.createElement('a');
    link.href = '#main-content';
    link.className = 'medpront-skip-link';
    link.textContent = 'Pular para o conteúdo principal';
    document.body.insertBefore(link, document.body.firstChild);

    link.addEventListener('click', function (e) {
      e.preventDefault();
      var target = document.querySelector('#main-content, main, [role="main"]');
      if (target) {
        target.setAttribute('tabindex', '-1');
        target.focus();
      }
    });
  }

  /* ============================================================
   * 5. FOCUS TRAP FOR MODALS
   * ============================================================ */
  function initFocusTrap() {
    document.addEventListener('keydown', function (e) {
      if (e.key !== 'Tab') return;
      var modal = document.querySelector('.modal.show, [role="dialog"][open]');
      if (!modal) return;

      var focusable = modal.querySelectorAll(
        'button, [href], input, select, textarea, [tabindex]:not([tabindex="-1"])'
      );
      if (focusable.length === 0) return;

      var first = focusable[0];
      var last = focusable[focusable.length - 1];

      if (e.shiftKey) {
        if (document.activeElement === first) {
          e.preventDefault();
          last.focus();
        }
      } else {
        if (document.activeElement === last) {
          e.preventDefault();
          first.focus();
        }
      }
    });
  }

  /* ============================================================
   * 6. COLLAPSIBLE SECTION TOGGLES (para CI-4 SectionedForm)
   * ============================================================ */
  function initCollapsibleSections() {
    document.addEventListener('click', function (e) {
      var toggle = e.target.closest('.section-toggle');
      if (!toggle) return;

      var targetId = toggle.getAttribute('aria-controls');
      var target = document.getElementById(targetId);
      if (!target) return;

      var expanded = toggle.getAttribute('aria-expanded') !== 'true';
      toggle.setAttribute('aria-expanded', String(expanded));
      target.hidden = !expanded;
    });
  }

  /* ============================================================
   * INIT
   * ============================================================ */
  function init() {
    initSkipLink();
    initSidebar();
    initMasks();
    initFormValidation();
    initFocusTrap();
    initCollapsibleSections();
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
