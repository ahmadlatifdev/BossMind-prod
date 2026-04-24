import React, { useEffect, useState } from "react";

export default function MindstormButtonPanel() {
  const [buttons, setButtons] = useState([]);

  useEffect(() => {
    fetch("/api/mindstorm-buttons")
      .then((res) => res.json())
      .then((data) => {
        if (data?.success && Array.isArray(data.buttons)) {
          setButtons(data.buttons);
        }
      })
      .catch(() => {
        setButtons([]);
      });
  }, []);

  return (
    <section className="w-full rounded-2xl border border-yellow-500/30 bg-slate-950 p-6 shadow-lg">
      <div className="mb-5">
        <h2 className="text-2xl font-bold text-yellow-400">
          Mindstorm Optimization Center
        </h2>
        <p className="mt-2 text-sm text-slate-300">
          Controlled idea engine available for all BossMind projects.
        </p>
      </div>

      <div className="grid grid-cols-1 gap-4 md:grid-cols-2 xl:grid-cols-5">
        {buttons.map((button) => (
          <button
            key={button.projectKey}
            type="button"
            disabled={!button.available}
            className="rounded-xl border border-yellow-500/40 bg-slate-900 px-4 py-4 text-left transition hover:bg-yellow-500/10 disabled:opacity-40"
            onClick={() => {
              window.location.href = `/mindstorm?project=${button.projectKey}`;
            }}
          >
            <div className="text-sm text-slate-400">{button.projectKey}</div>
            <div className="mt-2 text-lg font-semibold text-yellow-300">
              🧠 {button.label}
            </div>
            <div className="mt-2 text-xs text-slate-400">
              Suggestion-only optimization engine
            </div>
          </button>
        ))}
      </div>
    </section>
  );
}