import Stripe from 'stripe';

const stripe = new Stripe(process.env.STRIPE_SECRET_KEY);

export default async function handler(req, res) {
  const { session_id } = req.query;
  if (!session_id) return res.status(400).json({ error: 'Missing session_id' });
  try {
    const session = await stripe.checkout.sessions.retrieve(session_id, {
      expand: ['line_items.data.price.product']
    });
    const lineItem = session.line_items.data[0];
    const product = lineItem.price.product;
    const plan = {
      name: product.name,
      amount: lineItem.price.unit_amount,
      currency: lineItem.price.currency
    };
    res.status(200).json({ plan });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
}
