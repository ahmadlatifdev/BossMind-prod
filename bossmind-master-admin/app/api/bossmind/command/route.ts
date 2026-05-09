import { NextResponse } from "next/server";
import { Pool } from "pg";

const pool = new Pool({
  connectionString: process.env.NEON_DB,
  ssl: { rejectUnauthorized: false }
});

export async function POST(req: Request) {
  try {
    const body = await req.json();
    const command = body.command;

    if (!command) {
      return NextResponse.json({ error: "Missing command" }, { status: 400 });
    }

    await pool.query(`
      CREATE TABLE IF NOT EXISTS bossmind_command_queue (
        id SERIAL PRIMARY KEY,
        command TEXT NOT NULL,
        executed BOOLEAN DEFAULT FALSE,
        created_at TIMESTAMPTZ DEFAULT NOW(),
        executed_at TIMESTAMPTZ
      );
    `);

    await pool.query(
      "INSERT INTO bossmind_command_queue (command) VALUES ($1)",
      [command]
    );

    return NextResponse.json({ status: "queued" });

  } catch (err: any) {
    return NextResponse.json(
      { error: err.message },
      { status: 500 }
    );
  }
}