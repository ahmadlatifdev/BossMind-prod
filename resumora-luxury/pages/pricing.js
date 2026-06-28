import Head from "next/head";
import SiteChrome from "@/components/marketing/SiteChrome";
import PricingPanel from "@/components/marketing/sections/PricingPanel";
import { useLanguage } from "@/context/LanguageContext";
import { getSiteUrl } from "@/lib/marketing/seo-config";
import { brandAbsoluteUrl } from "@/lib/marketing/branding-assets";
import { translations } from "@/lib/marketing/site-copy";

export default function PricingPage() {
  const { lang } = useLanguage();
  const t = translations[lang];
  const siteUrl = getSiteUrl();
  const canonical = `${siteUrl}/pricing`;
  const ogImage = brandAbsoluteUrl(siteUrl, "/og-resumora-brand.png");
  const metaTitle =
    lang === "fr"
      ? "Tarifs · Basic, Standard, Professionnel, Entreprise | Resumora"
      : "Pricing · Basic, Standard, Professional, Enterprise | Resumora";
  const metaDescription =
    lang === "fr"
      ? "Quatre paliers : Basic (29 $), Standard (49 $), Professionnel (79 $), Entreprise (110 $). Paiement Stripe sécurisé."
      : "Four tiers: Basic ($29), Standard ($49), Professional ($79), Enterprise ($110). Stripe-secure checkout.";

  return (
    <SiteChrome>
      <Head>
        <title>{metaTitle}</title>
        <meta name="description" content={metaDescription} />
        <link rel="canonical" href={canonical} />
        <meta
          name="robots"
          content="index, follow, max-image-preview:large, max-snippet:-1, max-video-preview:-1"
        />
        <meta property="og:type" content="website" />
        <meta property="og:site_name" content="Resumora" />
        <meta property="og:title" content={metaTitle} />
        <meta property="og:description" content={metaDescription} />
        <meta property="og:url" content={canonical} />
        <meta property="og:image" content={ogImage} />
        <meta name="twitter:card" content="summary_large_image" />
        <meta name="twitter:title" content={metaTitle} />
        <meta name="twitter:description" content={metaDescription} />
        <meta name="twitter:image" content={ogImage} />
      </Head>
      <main>
        <section className="rs-section rs-pricing-page-hero rs-pricing-page-hero--centered">
          <div className="rs-container">
            <p className="rs-eyebrow">{t.navPricing}</p>
            <h1 className="rs-page-title">{t.pricingTitle}</h1>
            <p className="rs-lead rs-lead--pricing-tight">{t.pricingSubtitle}</p>
          </div>
        </section>
        <PricingPanel showHeader={false} />
      </main>
    </SiteChrome>
  );
}
