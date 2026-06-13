/* ============================================================
   DEBTORA CZ — Auth (Supabase Auth)
   Identita stojí na auth.users (D1). Žádné vlastní hashování hesel,
   žádný service-role klíč ve frontendu.
   Načti PO supabase-config.js a api.js (vytváří window.sbClient).
   ============================================================ */

const Auth = {
  _cachedUser: null,

  // ── Registrace přes Supabase Auth + doplnění profilu ──
  // profile: { name, company, ico, phone, account_type }
  async register(email, password, profile = {}) {
    const { data, error } = await sbClient.auth.signUp({
      email,
      password,
      options: { data: { name: profile.name ?? null } },
    });
    if (error) {
      if (/already registered/i.test(error.message)) throw new Error('E-mail je již registrován.');
      throw new Error(error.message);
    }
    // Profil v public.users zakládá DB trigger; doplníme rozšířené údaje.
    const uid = data.user?.id;
    if (uid && data.session) {
      await sbClient.from('users').update({
        name: profile.name ?? null,
        company: profile.company ?? null,
        ico: profile.ico ?? null,
        phone: profile.phone ?? null,
        account_type: profile.account_type ?? 'buyer',
      }).eq('id', uid);
    }
    return data.user;
  },

  // ── Přihlášení ──
  async login(email, password) {
    const { data, error } = await sbClient.auth.signInWithPassword({ email, password });
    if (error) throw new Error('Nesprávný e-mail nebo heslo.');
    this._cachedUser = data.user;
    await this.updateNav();
    return data.user;
  },

  // ── Odhlášení ──
  async logout(redirect = 'prihlaseni.html') {
    await sbClient.auth.signOut();
    this._cachedUser = null;
    await this.updateNav();
    if (redirect) window.location.href = redirect;
  },

  // ── Aktuální uživatel (auth.users) ──
  async getUser() {
    const { data } = await sbClient.auth.getUser();
    this._cachedUser = data.user ?? null;
    return this._cachedUser;
  },

  // ── Profil z public.users (company, IČO, kyc_status…) ──
  async getProfile() {
    const user = await this.getUser();
    if (!user) return null;
    const { data } = await sbClient.from('users').select('*').eq('id', user.id).single();
    return data ?? null;
  },

  async isLoggedIn() {
    const { data } = await sbClient.auth.getSession();
    return !!data.session;
  },

  // ── Ochrana stránek vyžadujících přihlášení ──
  async requireLogin(loginUrl = 'prihlaseni.html') {
    if (await this.isLoggedIn()) return true;
    sessionStorage.setItem('debtora_redirect', window.location.href);
    window.location.href = loginUrl;
    return false;
  },

  redirectAfterLogin(fallback = 'ucet.html') {
    const url = sessionStorage.getItem('debtora_redirect');
    sessionStorage.removeItem('debtora_redirect');
    window.location.href = url || fallback;
  },

  // ── Navigace login/účet ──
  async updateNav() {
    const user = await this.getUser();
    document.querySelectorAll('.nav-auth-login').forEach((el) => { el.style.display = user ? 'none' : ''; });
    document.querySelectorAll('.nav-auth-account').forEach((el) => { el.style.display = user ? '' : 'none'; });
    document.querySelectorAll('.nav-auth-name').forEach((el) => {
      if (user) el.textContent = (user.user_metadata?.name || user.email || 'Účet').split(' ')[0];
    });
  },

  // Reaguj na změny session (login v jiné záložce apod.)
  onChange(cb) {
    return sbClient.auth.onAuthStateChange((_event, session) => cb(session?.user ?? null));
  },
};

document.addEventListener('DOMContentLoaded', () => {
  Auth.updateNav();
  Auth.onChange(() => Auth.updateNav());
});

window.Auth = Auth;
