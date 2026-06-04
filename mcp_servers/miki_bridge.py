# D:\BossMind\mcp_servers\miki_bridge.py
import asyncio
from mcp.server.fastmcp import FastMCP

mcp = FastMCP("Miki-Bridge")

@mcp.tool()
async def ask_miki(prompt: str) -> str:
    """Delegate a quick task to Miki (fast assistant)."""
    # This will connect to your existing miki_production.py
    return f"[Miki response to: {prompt[:100]}...]"

if __name__ == "__main__":
    mcp.run()