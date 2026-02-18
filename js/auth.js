/* ============================================================
   DEBTORA CZ — User Auth Session Manager
   Manages login/logout state in sessionStorage.
   Include AFTER supabase-config.js and api.js on all pages.
   ============================================================ */

// ── SHA-256 hash (standalone, no dependency on api.js) ──
async function hashPassword(password) {
  const encoder = new TextEncoder();
  const data = encoder.encode(password);
  const hashBuffer = await crypto.subtle.digest('SHA-256', data);
  const hashArray = Array.from(new Uint8Array(hashBuffer));
  return hashArray.map(b => b.toString(16).padStart(2, '0')).join('');
}

const Auth = {
  // Get current user from session
  getUser() {
    try {
      const raw = sessionStorage.getItem('debtora_user');
      return raw ? JSON.parse(raw) : null;
    } catch { return null; }
  },

  // Check if user is logged in
  isLoggedIn() {
    return !!this.getUser();
  },

  // Login — calls API and stores session
  async login(email, password) {
    const pwHash = await hashPassword(password);
    const { data, error } = await sbClient.rpc('user_login', {
      user_email: email,
      pw_hash: pwHash
    });
    if (error) throw new Error('Chyba připojení k serveru.');
    if (!data || !data.success) throw new Error(data?.error || 'Nesprávné přihlašovací údaje.');
    sessionStorage.setItem('debtora_user', JSON.stringify(data.user));
    this.updateNav();
    return data.user;
  },

  // Logout
  logout() {
    sessionStorage.removeItem('debtora_user');
    this.updateNav();
    window.location.href = 'prihlaseni.html';
  },

  // Update nav to show login/account state
  updateNav() {
    const user = this.getUser();
    document.querySelectorAll('.nav-auth-login').forEach(el => {
      el.style.display = user ? 'none' : '';
    });
    document.querySelectorAll('.nav-auth-account').forEach(el => {
      el.style.display = user ? '' : 'none';
    });
    document.querySelectorAll('.nav-auth-name').forEach(el => {
      if (user) el.textContent = user.name?.split(' ')[0] || 'Účet';
    });
  },

  // Require login — redirect if not authenticated
  requireLogin() {
    if (!this.isLoggedIn()) {
      sessionStorage.setItem('debtora_redirect', window.location.href);
      window.location.href = 'prihlaseni.html';
      return false;
    }
    return true;
  },

  // Redirect to saved URL after login
  redirectAfterLogin() {
    const url = sessionStorage.getItem('debtora_redirect');
    sessionStorage.removeItem('debtora_redirect');
    window.location.href = url || 'ucet.html';
  }
};

// Auto-update nav on page load
document.addEventListener('DOMContentLoaded', () => Auth.updateNav());
