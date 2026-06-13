/* ═══════════════════════════════════════════════════════
   DEBTORA CZ — transakční e-maily (Resend)
   FAIL-SOFT: chyba odeslání NESMÍ shodit platbu/kontrolu/moderaci.
   Auth e-maily (registrace, reset hesla) řeší Supabase Auth — sem nepatří.
   Env: RESEND_API_KEY, (volitelně) EMAIL_FROM.
   ═══════════════════════════════════════════════════════ */

const RESEND_ENDPOINT = "https://api.resend.com/emails";
const DEFAULT_FROM = "Debtora CZ <noreply@debtora.cz>";

export async function sendEmail(to: string, subject: string, html: string): Promise<boolean> {
  const key = Deno.env.get("RESEND_API_KEY");
  if (!key || !to) return false; // fail-soft: bez klíče/adresáta neodesíláme
  try {
    const res = await fetch(RESEND_ENDPOINT, {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${key}` },
      body: JSON.stringify({ from: Deno.env.get("EMAIL_FROM") ?? DEFAULT_FROM, to, subject, html }),
    });
    if (!res.ok) {
      console.error("[email] Resend HTTP", res.status, await res.text());
      return false;
    }
    return true;
  } catch (e) {
    console.error("[email] send failed:", e);
    return false; // fail-soft
  }
}

// ── Šablony (krátké, česky) ──
export function tplPaymentCredits(credits: number, balance: number): { subject: string; html: string } {
  return {
    subject: "Debtora CZ — platba přijata, kredity připsány",
    html: `<p>Děkujeme, platba proběhla úspěšně.</p>
<p>Připsáno <strong>${credits} kreditů</strong>. Aktuální zůstatek: <strong>${balance}</strong>.</p>
<p>— Debtora CZ</p>`,
  };
}

export function tplPaymentSubscription(periodEnd: string): { subject: string; html: string } {
  return {
    subject: "Debtora CZ — předplatné Inzerce aktivováno",
    html: `<p>Děkujeme, platba proběhla úspěšně.</p>
<p>Předplatné služby <strong>Inzerce</strong> je aktivní do <strong>${periodEnd}</strong>.</p>
<p>— Debtora CZ</p>`,
  };
}

export function tplPaymentSingle(): { subject: string; html: string } {
  return {
    subject: "Debtora CZ — platba přijata, kontrola probíhá",
    html: `<p>Děkujeme, platba proběhla úspěšně.</p>
<p>Výsledek kontroly najdete po přihlášení v historii, případně vám jej zašleme.</p>
<p>— Debtora CZ</p>`,
  };
}

export function tplListingModerated(approved: boolean, title: string): { subject: string; html: string } {
  return approved
    ? {
      subject: "Debtora CZ — inzerát schválen",
      html: `<p>Váš inzerát <strong>${title}</strong> byl schválen a je publikován na tržišti.</p><p>— Debtora CZ</p>`,
    }
    : {
      subject: "Debtora CZ — inzerát zamítnut",
      html: `<p>Váš inzerát <strong>${title}</strong> byl po kontrole zamítnut. V případě dotazů nás kontaktujte.</p><p>— Debtora CZ</p>`,
    };
}
