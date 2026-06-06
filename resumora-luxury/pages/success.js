import { useEffect, useState } from 'react';
import { useRouter } from 'next/router';

export default function Success() {
  const router = useRouter();
  const { session_id } = router.query;
  const [plan, setPlan] = useState(null);

  useEffect(() => {
    if (!session_id) return;
    fetch(`/api/get-session?session_id=${session_id}`)
      .then(res => res.json())
      .then(data => setPlan(data.plan));
  }, [session_id]);

  if (!plan) return <div className="text-center py-20">Loading your order...</div>;

  return (
    <div className="max-w-2xl mx-auto px-6 py-16">
      <h1 className="text-4xl font-bold text-gold-500 mb-4">Thank you for your purchase!</h1>
      <p className="text-xl mb-2">You selected: <strong>{plan.name}</strong></p>
      <p className="text-lg text-gray-300 mb-8">Amount: ${(plan.amount / 100).toFixed(2)}</p>
      <div className="bg-white/5 p-6 rounded-lg">
        <h2 className="text-2xl font-semibold mb-3">Next steps</h2>
        <ul className="list-disc pl-6 space-y-2">
          <li>You will receive a confirmation email within 5 minutes.</li>
          <li>Upload your resume in the <a href="/studio" className="text-gold-500 underline">Client Studio</a>.</li>
          <li>Our team will deliver within 24‑48 hours.</li>
        </ul>
        {plan.name === 'Essential Advanced' && (
          <div className="mt-6 p-3 bg-gold-500/10 border border-gold-500 rounded">
            ✨ Executive upgrade lane included – we will contact you for interview prep scheduling.
          </div>
        )}
      </div>
    </div>
  );
}
