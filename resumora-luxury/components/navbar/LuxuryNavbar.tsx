"use client";

import { useCallback, useMemo, useState } from "react";

import ResumoraLogo from "@/components/brand/ResumoraLogo";
import { useLanguage } from "@/context/LanguageContext";
import styles from "@/styles/luxury/navbar.module.css";

type Lang = "en" | "fr";

const NAV_COPY = {
  en: {
    home: "Home",
    pricing: "Pricing",
    faq: "FAQ",
    getStarted: "Get Started",
    homeAria: "Resumora home",
  },
  fr: {
    home: "Accueil",
    pricing: "Tarifs",
    faq: "FAQ",
    getStarted: "Commencer",
    homeAria: "Accueil Resumora",
  },
} as const;

type LuxuryNavbarProps = {
  langToggle?: React.ReactNode;
  appearanceToggle?: React.ReactNode;
};

export default function LuxuryNavbar({ langToggle, appearanceToggle }: LuxuryNavbarProps) {
  const [open, setOpen] = useState(false);
  const { lang } = useLanguage();
  const locale: Lang = lang === "fr" ? "fr" : "en";
  const copy = NAV_COPY[locale];

  const links = useMemo(
    () => [
      { href: "#hero", label: copy.home },
      { href: "#pricing", label: copy.pricing },
      { href: "#faq", label: copy.faq },
    ],
    [copy]
  );

  const scrollToPricing = useCallback((e: React.MouseEvent<HTMLAnchorElement>) => {
    e.preventDefault();
    setOpen(false);
    const target = document.getElementById("pricing");
    if (target) {
      target.scrollIntoView({ behavior: "smooth", block: "start" });
      window.history.replaceState(null, "", "#pricing");
      return;
    }
    window.location.hash = "#pricing";
  }, []);

  return (
    <header className={styles.navbar}>
      <div className="lux-container">
        <div className={`lux-glass ${styles.navbarInner}`}>
          <div className={styles.brand}>
            <ResumoraLogo
              variant="topbar"
              linkHome
              priority
              linkClassName={`${styles.brandLink} rs-logo-top-left-only`}
              className={styles.brandLogo}
              homeAriaLabel={copy.homeAria}
            />
            <a href="#hero" className={styles.brandName}>
              Resumora
            </a>
          </div>

          <nav aria-label="Primary">
            <ul className={styles.navLinks}>
              {links.map((link) => (
                <li key={link.href}>
                  <a href={link.href} className={styles.navLink}>
                    {link.label}
                  </a>
                </li>
              ))}
            </ul>
          </nav>

          <div className={styles.navActions}>
            {appearanceToggle}
            {langToggle}
            <a
              href="#pricing"
              className={styles.navCta}
              onClick={scrollToPricing}
              data-rs-cta="get-started"
              data-rs-lang={locale}
            >
              {copy.getStarted}
            </a>
            <button
              type="button"
              className={styles.menuButton}
              aria-expanded={open}
              aria-label="Toggle menu"
              onClick={() => setOpen((v) => !v)}
            >
              ☰
            </button>
          </div>
        </div>

        <div
          className={`lux-glass ${styles.mobilePanel} ${open ? styles.mobilePanelOpen : ""}`}
        >
          {links.map((link) => (
            <a
              key={link.href}
              href={link.href}
              className={styles.mobileLink}
              onClick={() => setOpen(false)}
            >
              {link.label}
            </a>
          ))}
          <a
            href="#pricing"
            className={styles.mobileCta}
            onClick={scrollToPricing}
            data-rs-cta="get-started"
            data-rs-lang={locale}
          >
            {copy.getStarted}
          </a>
        </div>
      </div>
    </header>
  );
}
