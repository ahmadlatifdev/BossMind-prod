import { useEffect, useState } from "react";
import Head from "next/head";
import Link from "next/link";
import { useRouter } from "next/router";
import MinimalAppChrome from "@/components/marketing/MinimalAppChrome";
import { useLanguage } from "@/context/LanguageContext";
import { getPostAuthRedirectPath } from "@/lib/marketing/checkout-plan-persistence";
import { translations } from "@/lib/marketing/site-copy";

const RESET_CTX_KEY = "rs_password_reset_ctx";

function firstQuery(value) {
  if (typeof value === "string") return value;
  if (Array.isArray(value) && typeof value[0] === "string") return value[0];
  return "";
}

function readResetContext() {
  if (typeof sessionStorage === "undefined") return null;
  try {
    const raw = sessionStorage.getItem(RESET_CTX_KEY);
    if (!raw) return null;
    return JSON.parse(raw);
  } catch {
    return null;
  }
}

function writeResetContext(patch) {
  const current = readResetContext() || {};
  if (typeof sessionStorage === "undefined") return;
  try {
    sessionStorage.setItem(
      RESET_CTX_KEY,
      JSON.stringify({
        ...current,
        ...patch,
        savedAt: Date.now(),
      })
    );
  } catch {
    /* ignore */
  }
}

function resolveRequestError(data, t) {
  if (data?.error === "phone_required") return t.forgotPasswordPhoneRequired;
  if (data?.error === "delivery_partial") return t.forgotPasswordDeliveryPartial;
  if (data?.error === "delivery_failed") return t.forgotPasswordDeliveryFailed;
  if (data?.error === "rate_limited") return t.forgotPasswordRateLimited;
  return t.errLoginGeneric;
}

function resolveVerifyError(error, t) {
  if (error === "code_expired") return t.resetPasswordCodeExpired;
  if (error === "too_many_attempts") return t.resetPasswordTooManyAttempts;
  if (error === "invalid_code") return t.resetPasswordInvalidCodeOnly;
  return t.resetPasswordInvalidCode;
}

export default function ResetPasswordPage() {
  const router = useRouter();
  const { lang } = useLanguage();
  const t = translations[lang];
  const [email, setEmail] = useState("");
  const [channel, setChannel] = useState("email");
  const [phone, setPhone] = useState("");
  const [devCode, setDevCode] = useState("");
  const [error, setError] = useState("");
  const [message, setMessage] = useState("");
  const [resendMessage, setResendMessage] = useState("");
  const [resendError, setResendError] = useState("");
  const [busy, setBusy] = useState(false);
  const [resendBusy, setResendBusy] = useState(false);

  useEffect(() => {
    if (!router.isReady) return;
    const q = firstQuery(router.query.email);
    const ctx = readResetContext();
    if (q) setEmail(q);
    else if (ctx?.email) setEmail(ctx.email);
    if (ctx?.channel) setChannel(ctx.channel);
    if (ctx?.phone) setPhone(ctx.phone);
    if (ctx?.devCode) setDevCode(String(ctx.devCode));
  }, [router.isReady, router.query.email]);

  async function onResendCode() {
    setResendError("");
    setResendMessage("");
    const accountEmail = String(email || "").trim();
    if (!accountEmail) {
      setResendError(t.resetPasswordEmailRequired);
      return;
    }

    const useChannel = channel || "email";
    if ((useChannel === "sms" || useChannel === "both") && !String(phone || "").trim()) {
      setResendError(t.forgotPasswordPhoneRequired);
      return;
    }

    setResendBusy(true);
    try {
      const body = {
        email: accountEmail,
        channel: useChannel,
        lang,
        ...(phone ? { phone: String(phone).trim() } : {}),
      };
      const res = await fetch("/api/engagement/password-reset/request", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(body),
      });
      const data = await res.json().catch(() => ({}));
      if (res.status === 429) {
        setResendError(t.forgotPasswordRateLimited);
        return;
      }
      if (!res.ok) {
        setResendError(resolveRequestError(data, t));
        return;
      }
      setResendMessage(data.message || t.resetPasswordResent);
      if (data.devCode) {
        const nextDevCode = String(data.devCode);
        setDevCode(nextDevCode);
        writeResetContext({ email: accountEmail, channel: useChannel, phone, devCode: nextDevCode });
      } else {
        writeResetContext({ email: accountEmail, channel: useChannel, phone });
      }
    } catch {
      setResendError(t.forgotPasswordDeliveryFailed);
    } finally {
      setResendBusy(false);
    }
  }

  async function onSubmit(e) {
    e.preventDefault();
    setError("");
    setMessage("");
    setResendError("");
    setResendMessage("");
    const fd = new FormData(e.currentTarget);
    const code = String(fd.get("code") || "");
    const password = String(fd.get("password") || "");
    const confirm = String(fd.get("confirm") || "");
    const accountEmail = String(fd.get("email") || email).trim();

    if (!accountEmail) {
      setError(t.resetPasswordEmailRequired);
      return;
    }
    if (password.length < 8) {
      setError(t.resetPasswordTooShort);
      return;
    }
    if (password !== confirm) {
      setError(t.resetPasswordMismatch);
      return;
    }

    setBusy(true);
    try {
      const verifyRes = await fetch("/api/engagement/password-reset/verify", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ email: accountEmail, code }),
      });
      const verifyData = await verifyRes.json().catch(() => ({}));
      if (!verifyRes.ok) {
        setError(resolveVerifyError(verifyData.error, t));
        return;
      }

      const res = await fetch("/api/engagement/password-reset/complete", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        credentials: "same-origin",
        body: JSON.stringify({ email: accountEmail, code, password }),
      });
      const data = await res.json().catch(() => ({}));
      if (!res.ok) {
        if (data.error === "password_too_short") setError(t.resetPasswordTooShort);
        else setError(resolveVerifyError(data.error, t));
        return;
      }
      try {
        sessionStorage.removeItem(RESET_CTX_KEY);
      } catch {
        /* ignore */
      }
      setMessage(t.resetPasswordSuccess);
      await router.push(getPostAuthRedirectPath(router));
    } finally {
      setBusy(false);
    }
  }

  return (
    <MinimalAppChrome>
      <Head>
        <title>{t.resetPasswordTitle} · Resumora</title>
        <meta name="description" content={t.resetPasswordSubtitle} />
      </Head>
      <main className="rs-app-shell rs-app-shell--minimal-main" id="reset-password-main">
        <section className="rs-simple-card">
          <h1>{t.resetPasswordTitle}</h1>
          <p>{t.resetPasswordSubtitle}</p>
          <form className="rs-form-grid" onSubmit={onSubmit}>
            <input
              className="rs-input"
              name="email"
              type="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              placeholder={t.loginEmail}
              required
            />
            <input className="rs-input" name="code" inputMode="numeric" placeholder={t.resetPasswordCode} required />
            <input
              className="rs-input"
              name="password"
              type="password"
              placeholder={t.resetPasswordNew}
              autoComplete="new-password"
              required
            />
            <input
              className="rs-input"
              name="confirm"
              type="password"
              placeholder={t.resetPasswordConfirm}
              autoComplete="new-password"
              required
            />
            <button className="rs-btn-primary" type="submit" disabled={busy || resendBusy} aria-busy={busy}>
              {busy ? t.resetPasswordUpdating : t.resetPasswordSubmit}
            </button>
            <button
              className="rs-btn-ghost"
              type="button"
              disabled={busy || resendBusy}
              aria-busy={resendBusy}
              onClick={onResendCode}
            >
              {resendBusy ? t.resetPasswordResending : t.resetPasswordResend}
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
          {resendError ? (
            <p role="alert" style={{ color: "#f0a8a8", marginTop: "0.75rem", fontSize: "0.9rem" }}>
              {resendError}
            </p>
          ) : null}
          {resendMessage ? (
            <p role="status" style={{ color: "#7dd4a0", marginTop: "0.75rem", fontSize: "0.9rem" }}>
              {resendMessage}
            </p>
          ) : null}
          {devCode ? (
            <p role="status" style={{ color: "#c9b896", marginTop: "0.5rem", fontSize: "0.85rem" }}>
              {t.forgotPasswordDevCode} <strong>{devCode}</strong>
            </p>
          ) : null}
          <p style={{ marginTop: "0.75rem", display: "flex", flexDirection: "column", gap: "0.35rem" }}>
            <Link href="/forgot-password" className="rs-link-muted">
              {t.forgotPasswordTitle}
            </Link>
            <Link href="/login" className="rs-link-muted">
              {t.loginTitle}
            </Link>
          </p>
        </section>
      </main>
    </MinimalAppChrome>
  );
}
