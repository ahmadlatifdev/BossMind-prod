"use client";

import React from "react";

export default function MindstormButtonPanel() {

  const sendCommand = async (cmd) => {
    try {
      await fetch("/api/bossmind/command", {
        method: "POST",
        headers: {
          "Content-Type": "application/json"
        },
        body: JSON.stringify({ command: cmd })
      });

      alert("Command sent: " + cmd);

    } catch (err) {
      alert("Failed to send command");
    }
  };

  return (
    <div className="space-y-4">

      <button
        onClick={() => sendCommand("Write-Host BossMind TEST OK")}
        className="bg-green-600 px-4 py-2 rounded"
      >
        Test Command
      </button>

      <button
        onClick={() => sendCommand("git pull")}
        className="bg-blue-600 px-4 py-2 rounded"
      >
        Pull Latest Code
      </button>

      <button
        onClick={() => sendCommand("npm install")}
        className="bg-yellow-600 px-4 py-2 rounded"
      >
        Install Dependencies
      </button>

      <button
        onClick={() => sendCommand("pm2 restart all")}
        className="bg-red-600 px-4 py-2 rounded"
      >
        Restart Services
      </button>

    </div>
  );
}