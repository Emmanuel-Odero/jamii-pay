/// Claim page: takes a claim code from URL (?code=, ?claim=, /c/:code,
/// /<code> path, #), previews via GET /claims/:code, then collects the
/// recipient's M-PESA number and posts the claim. No app install, no
/// wallet required — claiming attaches a smart account server-side.
///
/// 2026 fix: the old page rendered a dead "Claim now" button with no
/// handler and no phone input, and only accepted ?code=.
interface ClaimResponse {
  status: "claimed" | "already_claimed" | "invalid" | "expired";
  amount?: string;
  currency?: string;
  sender?: string;
  expiresInHours?: number;
}

const API_BASE = import.meta.env.VITE_API_BASE ?? "http://localhost:8080";

function esc(s: string): string {
  return s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function render(html: string): void {
  const app = document.getElementById("app");
  if (app) app.innerHTML = html;
}

function getCode(): string | null {
  const params = new URLSearchParams(window.location.search);
  const q = params.get("code") ?? params.get("claim");
  if (q) return q.trim();
  const hash = window.location.hash.match(/code=([^&]+)/);
  if (hash) return decodeURIComponent(hash[1]);
  // Path forms: /c/<code> or /<code> (prototype: claim.jamiipay.com/k4m2).
  const segs = window.location.pathname.split("/").filter(Boolean);
  if (segs.length === 2 && segs[0] === "c") return segs[1];
  if (segs.length === 1 && /^[A-Za-z0-9-]{4,64}$/.test(segs[0])) return segs[0];
  return null;
}

async function fetchClaimPreview(code: string): Promise<ClaimResponse> {
  const res = await fetch(`${API_BASE}/claims/${encodeURIComponent(code)}`);
  if (res.status === 404) return { status: "invalid" };
  if (res.status === 410) return { status: "expired" };
  if (!res.ok) throw new Error(`preview ${res.status}`);
  return (await res.json()) as ClaimResponse;
}

function card(inner: string, selected = false): string {
  return `<div class="card${selected ? " selected" : ""}" role="status">${inner}</div>`;
}

async function main(): Promise<void> {
  const app = document.getElementById("app");
  if (app) app.setAttribute("aria-live", "polite");

  const code = getCode();

  if (!code) {
    render(
      card(`<h1>Missing claim code</h1><p>Check the link you were sent — it should look like <b>jamiipay.com/c/abc123</b>. Ask the sender to resend it, or <a href="https://jamiipay.com/support">contact support</a>.</p>`)
    );
    return;
  }

  render(card(`<p>Loading your payment…</p>`));
  let preview: ClaimResponse;
  try {
    preview = await fetchClaimPreview(code);
  } catch {
    render(
      card(`<h1>You're offline or our server hiccuped</h1><p>Check your connection and try again.</p><button id="retry-btn">Retry</button>`)
    );
    document.getElementById("retry-btn")?.addEventListener("click", () => window.location.reload());
    return;
  }

  if (preview.status === "already_claimed") {
    render(
      card(`<h1>Already claimed</h1><p>This link has already been used. If that wasn't you, contact the person who sent it or <a href="https://jamiipay.com/support">support</a>.</p>`)
    );
    return;
  }

  if (preview.status === "expired") {
    render(
      card(`<h1>This link expired</h1><p>Claim links last 72 hours, then the money returns to the sender. Ask them to send it again.</p>`)
    );
    return;
  }

  if (preview.status !== "claimed") {
    render(
      card(`<h1>This claim link isn't valid</h1><p>It may have expired or been cancelled. Ask the sender to check, or <a href="https://jamiipay.com/support">contact support</a>.</p>`)
    );
    return;
  }

  const amount = esc(preview.amount ?? "");
  const currency = esc(preview.currency ?? "USD");
  const sender = preview.sender ? `<p>From <b>${esc(preview.sender)}</b></p>` : "";
  const expiry = preview.expiresInHours != null ? `<p class="muted">Expires in ~${preview.expiresInHours}h — then it returns to the sender.</p>` : "";

  render(
    card(
      `<p style="margin-bottom:0">You've got</p>
      <div class="amount" style="font-variant-numeric: tabular-nums">${amount} ${currency}</div>
      ${sender}
      <p style="margin-bottom:0">Enter your M-Pesa number to claim it — no app install needed.</p>
      ${expiry}
      <label class="field-label" for="phone">M-Pesa number</label>
      <input id="phone" inputmode="tel" autocomplete="tel" placeholder="+254 7xx xxx xxx" />
      <p class="field-hint" id="phone-hint">We'll send an M-Pesa prompt to this number.</p>
      <button id="claim-btn">Claim now</button>
      <p class="muted">No app, no password. Free to claim.</p>`,
      true
    )
  );

  const btn = document.getElementById("claim-btn") as HTMLButtonElement | null;
  const phone = document.getElementById("phone") as HTMLInputElement | null;
  btn?.addEventListener("click", async () => {
    const value = phone?.value.trim() ?? "";
    const digits = value.replace(/\D/g, "");
    if (digits.length < 9) {
      const hint = document.getElementById("phone-hint");
      if (hint) hint.textContent = "Enter a full M-Pesa number (+254 7xx xxx xxx).";
      phone?.focus();
      return;
    }
    if (!btn) return;
    btn.disabled = true;
    btn.textContent = "Claiming…";
    try {
      const res = await fetch(`${API_BASE}/claims/${encodeURIComponent(code)}/claim`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ phone: value }),
      });
      if (!res.ok) throw new Error(`claim ${res.status}`);
      render(
        card(`<h1>Claim received ✓</h1><p>Approve the M-Pesa prompt on <b>${esc(value)}</b> to finish. It usually arrives in ~15 seconds.</p><p class="muted">Nothing arrived? <a href="https://jamiipay.com/support">Get help</a>.</p>`)
      );
    } catch {
      btn.disabled = false;
      btn.textContent = "Claim now";
      render(
        card(`<h1>Something went wrong</h1><p>Please try again in a moment.</p><button id="retry-btn">Retry</button>`)
      );
      document.getElementById("retry-btn")?.addEventListener("click", () => window.location.reload());
    }
  });
}

main().catch(() => {
  render(`<div class="card"><h1>Something went wrong</h1><p>Please try again in a moment.</p><button id="retry-btn" onclick="location.reload()">Retry</button></div>`);
});
