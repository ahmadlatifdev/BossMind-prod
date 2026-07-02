import { useState } from "react";
import Head from "next/head";
import Link from "next/link";
import { useRouter } from "next/router";
import MinimalAppChrome from "@/components/marketing/MinimalAppChrome";
import { useLanguage } from "@/context/LanguageContext";
import { translations } from "@/lib/marketing/site-copy";

const RESET_CTX_KEY = "rs_password_reset_ctx";

function resolveError(data, t) {
  if (data?.error === "phone_required") return t.forgotPasswordPhoneRequired;
  if (data?.error === "delivery_partial") return t.forgotPasswordDeliveryPartial;
  if (data?.error === "delivery_failed") return t.forgotPasswordDeliveryFailed;
  if (data?.error === "rate_limited") return t.forgotPasswordRateLimited;
  return t.errLoginGeneric;
}

function saveResetContext({ email, channel, phone, devCode }) {
  if (typeof sessionStorage === "undefined") return;
  try {
    sessionStorage.setItem(
      RESET_CTX_KEY,
      JSON.stringify({
        email: String(email || "").trim(),
        channel: channel || "email",
        phone: phone || "",
        devCode: devCode || "",
        savedAt: Date.now(),
      })
    );
  } catch {
    /* ignore */
  }
}

export default function ForgotPasswordPage() {
  const router = useRouter();
  const { lang } = useLanguage();
  const t = translations[lang];
  const [error, setError] = useState("");
  const [message, setMessage] = useState("");
  const [busy, setBusy] = useState(false);

  async function onSubmit(e) {
    e.preventDefault();
    setError("");
    setMessage("");
    setBusy(true);
    const fd = new FormData(e.currentTarget);
    const channel = String(fd.get("channel") || "email");
    const phone = String(fd.get("phone") || "").trim();
    const body = {
      email: String(fd.get("email") || ""),
      phone: phone || undefined,
      channel,
      lang,
    };

    if ((channel === "sms" || channel === "both") && !phone) {
      setError(t.forgotPasswordPhoneRequired);
      setBusy(false);
      return;
    }

    try {
      const res = await fetch("/api/engagement/password-reset/request", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(body),
      });
      const data = await res.json().catch(() => ({}));
      if (res.status === 429) {
        setError(t.forgotPasswordRateLimited);
        return;
      }
      if (!res.ok) {
        setError(resolveError(data, t));
        return;
      }
      setMessage(data.message || t.forgotPasswordSent);
      saveResetContext({
        email: body.email,
        channel,
        phone,
        devCode: data.devCode ? String(data.devCode) : "",
      });
      const email = encodeURIComponent(body.email);
      await router.push(`/reset-password?email=${email}`);
    } catch {
      setError(t.forgotPasswordDeliveryFailed);
    } finally {
      setBusy(false);
    }
  }

  return (
    <MinimalAppChrome>
      <Head>
        <title>{t.forgotPasswordTitle} · Resumora</title>
        <meta name="description" content={t.forgotPasswordSubtitle} />
      </Head>
      <main className="rs-app-shell rs-app-shell--minimal-main" id="forgot-password-main">
        <section className="rs-simple-card">
          <h1>{t.forgotPasswordTitle}</h1>
          <p>{t.forgotPasswordSubtitle}</p>
          <form className="rs-form-grid" onSubmit={onSubmit}>
            <input className="rs-input" name="email" type="email" placeholder={t.forgotPasswordEmail} required />
            <input className="rs-input" name="phone" type="tel" placeholder={t.forgotPasswordPhone} autoComplete="tel" />
            <label className="rs-input" style={{ display: "flex", gap: "0.5rem", alignItems: "center" }}>
              <span>{t.forgotPasswordChannelEmail}</span>
              <input type="radio" name="channel" value="email" defaultChecked />
            </label>
            <label className="rs-input" style={{ display: "flex", gap: "0.5rem", alignItems: "center" }}>
              <span>{t.forgotPasswordChannelSms}</span>
              <input type="radio" name="channel" value="sms" />
            </label>
            <label className="rs-input" style={{ display: "flex", gap: "0.5rem", alignItems: "center" }}>
              <span>{t.forgotPasswordChannelBoth}</span>
              <input type="radio" name="channel" value="both" />
            </label>
            <button className="rs-btn-primary" type="submit" disabled={busy} aria-busy={busy}>
              {busy ? t.forgotPasswordSending : t.forgotPasswordSubmit}
            </button>
          </form>
          {error ? (
            <p role="alert" style={{ color: "#f0a8a8", marginTop: "0.75rem", fontSize: "0.9rem" }}>
              {error}
            </p>
          ) : null}
          {message ? (
            <p role="status" style={{ color: "#7dd4a0", marginTop: "0.75rem", fontSize: "0.9rem" }}>
              {message}
            </p>
          ) : null}
          <Link href="/login" className="rs-link-muted">
            {t.loginTitle}
          </Link>
        </section>
      </main>
    </MinimalAppChrome>
  );
}
