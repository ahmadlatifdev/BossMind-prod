"use client";

import { useState } from "react";

export default function RegisterPage() {
  const [form, setForm] = useState({
    name: "",
    email: "",
    password: "",
  });

  const handleSubmit = async (e: any) => {
    e.preventDefault();

    await fetch("/api/resumora/register", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify(form),
    });

    alert("Account created successfully");
  };

  return (
    <main className="min-h-screen bg-[#020b1c] flex items-center justify-center text-white">
      <form
        onSubmit={handleSubmit}
        className="bg-[#06152e] p-8 rounded-2xl border border-[#1a2c4a] w-full max-w-md"
      >
        <h1 className="text-2xl font-bold mb-6 text-center">Create Account</h1>

        <input
          placeholder="Full Name"
          className="w-full mb-4 p-3 rounded bg-[#020b1c] border border-[#1a2c4a]"
          onChange={(e) => setForm({ ...form, name: e.target.value })}
        />

        <input
          placeholder="Email"
          type="email"
          className="w-full mb-4 p-3 rounded bg-[#020b1c] border border-[#1a2c4a]"
          onChange={(e) => setForm({ ...form, email: e.target.value })}
        />

        <input
          placeholder="Password"
          type="password"
          className="w-full mb-6 p-3 rounded bg-[#020b1c] border border-[#1a2c4a]"
          onChange={(e) => setForm({ ...form, password: e.target.value })}
        />

        <button className="w-full py-3 bg-[#d4af37] text-black rounded font-bold">
          Register
        </button>
      </form>
    </main>
  );
}