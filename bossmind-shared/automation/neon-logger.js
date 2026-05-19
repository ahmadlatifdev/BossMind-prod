const http = require("http");
const fs = require("fs");

const PORT = 5051;

http.createServer((req, res) => {
  if (req.method === "POST" && req.url === "/logs") {
    let body = "";

    req.on("data", chunk => {
      body += chunk.toString();
    });

    req.on("end", () => {
      fs.appendFileSync(
        "D:/BossMind/bossmind-shared/logs/neon-log.json",
        body + "\n"
      );

      console.log("Log received:", body);

      res.writeHead(200, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ status: "saved" }));
    });
  } else {
    res.writeHead(404);
    res.end();
  }
}).listen(PORT, () => {
  console.log(`Neon Logger running at http://localhost:${PORT}`);
});
