# Resumora Luxury Updates

1. [x] Logo top-left only — footer/sidebar brand hidden globally (`luxuryglobals.css`)
2. [x] Stripe EN/FR checkout — guest session; Price IDs from `.env.local`; locale on Checkout
3. [x] Upload fixed — `upload-client.js` HTTP bug; unlimited size; PDF/DOC/images
4. [x] Code complete — **deploy required** for resumora.net (see `bossmind-resumora/DEPLOY-LUXURY-URGENT.md`)

## Stripe Price IDs (.env.local + hosting)

- `NEXT_PUBLIC_STRIPE_PRICE_BASIC`
- `NEXT_PUBLIC_STRIPE_PRICE_PRO`
- `NEXT_PUBLIC_STRIPE_PRICE_ELITE`
- `NEXT_PUBLIC_STRIPE_PRICE_ESSENTIAL_ADVANCED`
- `STRIPE_SECRET_KEY` + `NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY`

## Test locally

```powershell
cd D:\BossMind\bossmind-resumora
npm run dev
```

Open http://localhost:3001/pricing → Select plan → Stripe
