/* ============================================================
   DEBTORA CZ — Supabase API Client
   Replaces: js/api.js (Netlify Functions calls)
   
   Usage: Include supabase-config.js before this file:
   <script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2"></script>
   <script src="js/supabase-config.js"></script>
   <script src="js/api.js"></script>
   ============================================================ */

// ── Initialize Supabase Client ──
const SUPABASE_URL = window.DEBTORA_CONFIG?.SUPABASE_URL || 'https://YOUR_PROJECT.supabase.co';
const SUPABASE_ANON_KEY = window.DEBTORA_CONFIG?.SUPABASE_ANON_KEY || 'YOUR_ANON_KEY';

const supabase = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

// ── Public API (no auth required) ──
const API = {
  // ── LISTINGS ──
  async getListings(filters = {}) {
    let query = supabase
      .from('listings')
      .select('*')
      .eq('status', 'active')
      .order('created_at', { ascending: false });

    if (filters.type) query = query.eq('type', filters.type);
    if (filters.category) query = query.eq('category', filters.category);
    if (filters.location) query = query.ilike('location', `%${filters.location}%`);
    if (filters.min_price) query = query.gte('price', filters.min_price);
    if (filters.max_price) query = query.lte('price', filters.max_price);
    if (filters.limit) query = query.limit(filters.limit);

    const { data, error } = await query;
    if (error) throw new Error(error.message);
    return data || [];
  },

  async getListing(id) {
    // Increment view count
    await supabase.rpc('increment_views', { listing_id: id }).catch(() => {});
    
    const { data, error } = await supabase
      .from('listings')
      .select('*')
      .eq('id', id)
      .eq('status', 'active')
      .single();
    if (error) throw new Error(error.message);
    return data;
  },

  async createListing(listing) {
    const { data, error } = await supabase
      .from('listings')
      .insert([{ ...listing, status: 'pending' }])
      .select()
      .single();
    if (error) throw new Error(error.message);
    return data;
  },

  // ── USERS ──
  async registerUser(userData) {
    // Hash password client-side (in production, use Supabase Auth instead)
    const pwHash = await hashPassword(userData.password);
    delete userData.password;

    const { data, error } = await supabase
      .from('users')
      .insert([{ ...userData, password_hash: pwHash }])
      .select('id, email, name, company, account_type, created_at')
      .single();
    if (error) {
      if (error.code === '23505') throw new Error('E-mail je již registrován.');
      throw new Error(error.message);
    }
    return data;
  },

  // ── MESSAGES (contact form) ──
  async sendMessage(msgData) {
    const { data, error } = await supabase
      .from('messages')
      .insert([msgData])
      .select()
      .single();
    if (error) throw new Error(error.message);
    return { success: true, message: 'Zpráva byla odeslána. Odpovíme do 24 hodin.' };
  },

  // ── CONTENT (CMS) ──
  async getContent(blockKey) {
    if (blockKey) {
      const { data, error } = await supabase
        .from('content')
        .select('fields')
        .eq('block_key', blockKey)
        .single();
      if (error) return {};
      return data?.fields || {};
    }
    // Get all content blocks
    const { data, error } = await supabase
      .from('content')
      .select('block_key, fields');
    if (error) return {};
    const result = {};
    (data || []).forEach(row => { result[row.block_key] = row.fields; });
    return result;
  },

  // ── SETTINGS ──
  async getSettings(key) {
    if (key) {
      const { data } = await supabase
        .from('settings')
        .select('value')
        .eq('key', key)
        .single();
      return data?.value || {};
    }
    const { data } = await supabase.from('settings').select('key, value');
    const result = {};
    (data || []).forEach(row => { result[row.key] = row.value; });
    return result;
  }
};

// ── ADMIN API (requires service_role or admin session) ──
const AdminAPI = {
  _token: null,

  setToken(token) { this._token = token; },
  getToken() { return this._token || localStorage.getItem('debtora_admin_token'); },

  // Create admin-level Supabase client with service role key
  _adminClient() {
    const serviceKey = this.getToken();
    if (!serviceKey) throw new Error('Not authenticated');
    return window.supabase.createClient(SUPABASE_URL, serviceKey);
  },

  async login(password) {
    // Verify against admin_users table using anon client + RPC
    const pwHash = await hashPassword(password);
    const { data, error } = await supabase.rpc('admin_login', {
      pw_hash: pwHash
    });
    if (error || !data) throw new Error('Nesprávné heslo');
    // Store the service role key returned by the function
    this._token = data.token;
    localStorage.setItem('debtora_admin_token', data.token);
    return data;
  },

  async logout() {
    this._token = null;
    localStorage.removeItem('debtora_admin_token');
  },

  // ── ADMIN: Stats ──
  async getStats() {
    const client = this._adminClient();
    const { data, error } = await client.from('admin_stats').select('*').single();
    if (error) throw new Error(error.message);
    return data;
  },

  // ── ADMIN: Listings CRUD ──
  async getListings(filters = {}) {
    const client = this._adminClient();
    let query = client.from('listings').select('*').order('created_at', { ascending: false });
    if (filters.status) query = query.eq('status', filters.status);
    if (filters.type) query = query.eq('type', filters.type);
    const { data, error } = await query;
    if (error) throw new Error(error.message);
    return data || [];
  },

  async updateListing(id, updates) {
    const client = this._adminClient();
    const { data, error } = await client
      .from('listings')
      .update(updates)
      .eq('id', id)
      .select()
      .single();
    if (error) throw new Error(error.message);
    return data;
  },

  async deleteListing(id) {
    const client = this._adminClient();
    const { error } = await client.from('listings').delete().eq('id', id);
    if (error) throw new Error(error.message);
    return { success: true };
  },

  // ── ADMIN: Users CRUD ──
  async getUsers() {
    const client = this._adminClient();
    const { data, error } = await client
      .from('users')
      .select('*')
      .order('created_at', { ascending: false });
    if (error) throw new Error(error.message);
    return data || [];
  },

  async updateUser(id, updates) {
    const client = this._adminClient();
    const { data, error } = await client
      .from('users')
      .update(updates)
      .eq('id', id)
      .select()
      .single();
    if (error) throw new Error(error.message);
    return data;
  },

  async deleteUser(id) {
    const client = this._adminClient();
    const { error } = await client.from('users').delete().eq('id', id);
    if (error) throw new Error(error.message);
    return { success: true };
  },

  // ── ADMIN: Messages ──
  async getMessages() {
    const client = this._adminClient();
    const { data, error } = await client
      .from('messages')
      .select('*')
      .order('created_at', { ascending: false });
    if (error) throw new Error(error.message);
    return data || [];
  },

  async updateMessage(id, updates) {
    const client = this._adminClient();
    const { data, error } = await client
      .from('messages')
      .update(updates)
      .eq('id', id)
      .select()
      .single();
    if (error) throw new Error(error.message);
    return data;
  },

  async deleteMessage(id) {
    const client = this._adminClient();
    const { error } = await client.from('messages').delete().eq('id', id);
    if (error) throw new Error(error.message);
    return { success: true };
  },

  // ── ADMIN: Content CMS ──
  async getContent(blockKey) {
    return API.getContent(blockKey);
  },

  async updateContent(blockKey, fields) {
    const client = this._adminClient();
    const { data, error } = await client
      .from('content')
      .upsert({ block_key: blockKey, fields }, { onConflict: 'block_key' })
      .select()
      .single();
    if (error) throw new Error(error.message);
    return data;
  },

  // ── ADMIN: Settings ──
  async getSettings(key) {
    return API.getSettings(key);
  },

  async updateSettings(key, value) {
    const client = this._adminClient();
    const { data, error } = await client
      .from('settings')
      .upsert({ key, value }, { onConflict: 'key' })
      .select()
      .single();
    if (error) throw new Error(error.message);
    return data;
  }
};

// ── Utility: SHA-256 hash ──
async function hashPassword(password) {
  const encoder = new TextEncoder();
  const data = encoder.encode(password);
  const hashBuffer = await crypto.subtle.digest('SHA-256', data);
  const hashArray = Array.from(new Uint8Array(hashBuffer));
  return hashArray.map(b => b.toString(16).padStart(2, '0')).join('');
}

// ── UI Helpers ──
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
    btn.textContent = 'Načítání...';
    btn.disabled = true;
  } else {
    btn.textContent = btn.dataset.originalText || btn.textContent;
    btn.disabled = false;
  }
}

// Expose globally
window.API = API;
window.AdminAPI = AdminAPI;
window.showToast = showToast;
window.setLoading = setLoading;
