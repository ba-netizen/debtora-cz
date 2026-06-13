/* ============================================================
   DEBTORA CZ — API klient nad Supabase
   Frontend pouze ČTE přes RLS a INICIUJE akce (RPC / edge funkce).
   Service-role klíč zde NIKDY není (D3). Admin = přihlášený auth
   uživatel s řádkem v admin_users; píše přes admin_* RPC.

   Načti po:
     <script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2"></script>
     <script src="js/supabase-config.js"></script>
     <script src="js/api.js"></script>
   ============================================================ */

const SUPABASE_URL = window.DEBTORA_CONFIG?.SUPABASE_URL || 'https://YOUR_PROJECT.supabase.co';
const SUPABASE_ANON_KEY = window.DEBTORA_CONFIG?.SUPABASE_ANON_KEY || 'YOUR_ANON_KEY';

const sbClient = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
window.sbClient = sbClient;

const API = {
  // ═══════════ MARKETPLACE ═══════════

  // Veřejný NÁHLED — čte listings_preview (marketingové sloupce, bez detailů).
  async getListingsPreview(filters = {}) {
    let q = sbClient.from('listings_preview').select('*').order('created_at', { ascending: false });
    if (filters.type) q = q.eq('type', filters.type);
    if (filters.category) q = q.eq('category', filters.category);
    if (filters.location) q = q.ilike('location', `%${filters.location}%`);
    if (filters.storefront_id) q = q.eq('storefront_id', filters.storefront_id);
    if (filters.min_price) q = q.gte('price', filters.min_price);
    if (filters.max_price) q = q.lte('price', filters.max_price);
    if (filters.limit) q = q.limit(filters.limit);
    const { data, error } = await q;
    if (error) throw new Error(error.message);
    return data || [];
  },

  // Plný DETAIL — čte base listings (gated předplatným/vlastníkem).
  // Bez předplatného vrátí 0 řádků → { gated:true } pro CTA „Aktivovat Inzerci".
  async getListingDetail(id) {
    sbClient.rpc('increment_views', { p_listing: id }).then(() => {}, () => {});
    const { data, error } = await sbClient.from('listings').select('*').eq('id', id).maybeSingle();
    if (error) throw new Error(error.message);
    if (!data) return { gated: true };
    return { gated: false, listing: data };
  },

  // Tvorba inzerátu — JEDINÁ cesta je RPC create_listing.
  // Vrací { ok, listing_id, charged, error }.
  async createListing(listing) {
    const { data, error } = await sbClient.rpc('create_listing', { p_listing: listing });
    if (error) throw new Error(error.message);
    return data;
  },

  async getListingFiles(listingId) {
    const { data } = await sbClient.from('listing_files').select('*')
      .eq('listing_id', listingId).order('sort_order');
    return data || [];
  },

  // ═══════════ STOREFRONTY (/s/<slug>) ═══════════
  async getStorefront(slug) {
    const { data } = await sbClient.from('storefronts').select('*')
      .eq('slug', slug).eq('status', 'active').maybeSingle();
    return data || null;
  },
  async getMyStorefront() {
    const { data } = await sbClient.from('storefronts').select('*').maybeSingle();
    return data || null;
  },

  // ═══════════ ZPRÁVY / POPTÁVKY ═══════════
  async sendMessage(msg) {
    const { error } = await sbClient.from('messages').insert([msg]);
    if (error) throw new Error(error.message);
    return { success: true, message: 'Zpráva byla odeslána. Odpovíme do 24 hodin.' };
  },

  // ═══════════ OVĚŘENÍ (edge `verify`) ═══════════
  // subject: { type:'po', ico } | { type:'fo', firstName, lastName, birthDate, rc? }
  // level: 'foc_nologin'|'foc_login'|'basic'|'medium'|'full'
  //
  // Dvoufázový tok pro placené úrovně:
  //   1) const { quote, request_id } = await API.verify(subj, 'full');  // bez confirm
  //      → quote = { registries:[{registry,price}], total_credits } pro souhlas
  //   2) await API.verify(subj, 'full', { requestId: request_id, confirm: true });
  //      → { mode, level, risk_score, results }
  // FOC úrovně (cena 0) i krok 1 rovnou vrátí results (žádný quote).
  // request_id zajišťuje idempotenci (opakování nestrhne kredit 2×).
  newRequestId() {
    return (crypto.randomUUID && crypto.randomUUID()) ||
      ('rid-' + Date.now() + '-' + Math.random().toString(16).slice(2));
  },
  async verify(subject, level = 'basic', opts = {}) {
    const request_id = opts.requestId || this.newRequestId();
    const confirm = opts.confirm === true;
    const { data, error } = await sbClient.functions.invoke('verify', {
      body: { subject, level, request_id, confirm },
    });
    if (error) {
      // Non-2xx (429 rate limit, 402 nedostatek kreditů, 401 …) — vrať tělo
      // odpovědi (obsahuje rateLimited/error/quote), ať to UI umí zobrazit.
      try { const body = await error.context.json(); return { ...body, request_id }; } catch (_e) { /* fallthrough */ }
      throw new Error(error.message || 'Ověření se nezdařilo.');
    }
    return { ...data, request_id }; // { quote?, results?, risk_score?, mode, level }
  },

  async getVerificationHistory() {
    const { data } = await sbClient.from('verification_requests').select('*')
      .order('created_at', { ascending: false }).limit(50);
    return data || [];
  },

  async getRegistryConfig() {
    const { data } = await sbClient.from('registry_config').select('*').order('sort');
    return data || [];
  },

  // ═══════════ PLATBY (edge `payment-create`) ═══════════
  // product: 'single'|'pack5'|'pack20'|'pack50'|'sub_inzerce_monthly'
  async createPayment(product, { email, subject } = {}) {
    const { data, error } = await sbClient.functions.invoke('payment-create', {
      body: { action: 'create', product, email, subject },
    });
    if (error) throw new Error(error.message || 'Platbu se nepodařilo založit.');
    return data; // { redirect, token } | { error }
  },
  async paymentStatus(token) {
    const { data, error } = await sbClient.functions.invoke('payment-create', {
      body: { action: 'status', token },
    });
    if (error) throw new Error(error.message);
    return data;
  },

  // ═══════════ KREDITY ═══════════
  async getCreditBalance() {
    const { data } = await sbClient.from('user_credits').select('balance').maybeSingle();
    return data?.balance ?? 0;
  },
  async getCreditHistory() {
    const { data } = await sbClient.from('credit_transactions').select('*')
      .order('created_at', { ascending: false }).limit(100);
    return data || [];
  },

  // ═══════════ PŘEDPLATNÉ / IDENTITA (gating helpers) ═══════════
  async hasActiveSubscription(service = 'inzerce') {
    const user = (await sbClient.auth.getUser()).data.user;
    if (!user) return false;
    const { data } = await sbClient.rpc('has_active_subscription', { p_user: user.id, p_service: service });
    return data === true;
  },
  async getSubscription(service = 'inzerce') {
    const { data } = await sbClient.from('subscriptions').select('*').eq('service', service).maybeSingle();
    return data || null;
  },
  async isIdentityVerified(year = null) {
    const user = (await sbClient.auth.getUser()).data.user;
    if (!user) return false;
    const { data } = await sbClient.rpc('is_identity_verified', { p_user: user.id, p_year: year });
    return data === true;
  },

  // ═══════════ GDPR — smazání účtu (edge `delete-account`) ═══════════
  // Anonymizuje osobní údaje, zachová účetní audit, smaže auth.users.
  async deleteAccount() {
    const { data, error } = await sbClient.functions.invoke('delete-account', { body: {} });
    if (error) throw new Error(error.message || 'Smazání účtu se nezdařilo.');
    return data; // { ok, anonymized, authDeleted }
  },

  // ═══════════ CMS (čte cms.js) ═══════════
  async getContent(blockKey) {
    if (blockKey) {
      const { data } = await sbClient.from('content').select('fields').eq('block_key', blockKey).maybeSingle();
      return data?.fields || {};
    }
    const { data } = await sbClient.from('content').select('block_key, fields');
    const out = {};
    (data || []).forEach((r) => { out[r.block_key] = r.fields; });
    return out;
  },
  async getSettings(key) {
    if (key) {
      const { data } = await sbClient.from('settings').select('value').eq('key', key).maybeSingle();
      return data?.value || {};
    }
    const { data } = await sbClient.from('settings').select('key, value');
    const out = {};
    (data || []).forEach((r) => { out[r.key] = r.value; });
    return out;
  },
};

/* ════════════════════════════════════════════════════════════
   AdminAPI — pro přihlášeného admina (řádek v admin_users).
   ŽÁDNÝ service-role klíč: čtení přes RLS (is_admin policy),
   zápis přes admin_* SECURITY DEFINER RPC.
   ════════════════════════════════════════════════════════════ */
const AdminAPI = {
  async isAdmin() {
    const { data } = await sbClient.rpc('is_admin');
    return data === true;
  },

  // Čtení (admin RLS umožní vidět vše)
  async getListings() {
    const { data, error } = await sbClient.from('listings').select('*').order('created_at', { ascending: false });
    if (error) throw new Error(error.message);
    return data || [];
  },
  async getUsers() {
    const { data, error } = await sbClient.from('users').select('*').order('created_at', { ascending: false });
    if (error) throw new Error(error.message);
    return data || [];
  },
  async getMessages() {
    const { data, error } = await sbClient.from('messages').select('*').order('created_at', { ascending: false });
    if (error) throw new Error(error.message);
    return data || [];
  },

  // Zápis přes edge funkci (změní stav + pošle majiteli e-mail).
  async setListingStatus(id, status) {
    const { data, error } = await sbClient.functions.invoke('admin-moderate-listing', {
      body: { listing_id: id, status },
    });
    if (error) throw new Error(error.message);
    return data;
  },
  async updateContent(blockKey, fields) {
    const { data, error } = await sbClient.rpc('admin_update_content', { p_block_key: blockKey, p_fields: fields });
    if (error) throw new Error(error.message);
    return data;
  },
  async updateSettings(key, value) {
    const { data, error } = await sbClient.rpc('admin_update_settings', { p_key: key, p_value: value });
    if (error) throw new Error(error.message);
    return data;
  },
  async getRegistryConfig() {
    const { data, error } = await sbClient.rpc('admin_get_registry_config');
    if (error) throw new Error(error.message);
    return data;
  },
  async updateRegistryConfig(registry, enabled, price, levels) {
    const { data, error } = await sbClient.rpc('admin_update_registry_config', {
      p_registry: registry, p_enabled: enabled, p_price: price, p_levels: levels ?? null,
    });
    if (error) throw new Error(error.message);
    return data;
  },
};

// ── UI helpery (sdílené napříč stránkami) ──
function showToast(message, type = 'info') {
  const existing = document.querySelector('.toast');
  if (existing) existing.remove();
  const toast = document.createElement('div');
  toast.className = `toast toast-${type}`;
  toast.textContent = message;
  document.body.appendChild(toast);
  setTimeout(() => toast.classList.add('show'), 10);
  setTimeout(() => { toast.classList.remove('show'); setTimeout(() => toast.remove(), 300); }, 4000);
}
function setLoading(btn, loading) {
  if (loading) {
    btn.dataset.originalText = btn.textContent;
    btn.textContent = 'Načítání…';
    btn.disabled = true;
  } else {
    btn.textContent = btn.dataset.originalText || btn.textContent;
    btn.disabled = false;
  }
}

window.API = API;
window.AdminAPI = AdminAPI;
window.showToast = showToast;
window.setLoading = setLoading;
