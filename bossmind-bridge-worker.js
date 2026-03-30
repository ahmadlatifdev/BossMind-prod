async function processQueue() {
  try {
    const res = await client.query(`
      SELECT * FROM bossmind_update_queue
      ORDER BY created_at ASC
      LIMIT 1
      ORDER BY created_at ASC
      LIMIT 1
    `);

    console.log("QUEUE CHECK:", res.rows);

    if (res.rows.length === 0) return;

    const job = res.rows[0];

    const fullPath = job.target_path;

    fs.mkdirSync(path.dirname(fullPath), { recursive: true });
    fs.writeFileSync(fullPath, job.file_content, "utf8");

    await client.query(`
      UPDATE bossmind_update_queue
      SET status = 'DONE'
      WHERE id = $1
    `, [job.id]);

    console.log("APPLIED:", job.target_path);

  } catch (err) {
    console.log("ERROR:", err.message);
  }
}