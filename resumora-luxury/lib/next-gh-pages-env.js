/** @typedef {import('next').NextConfig} NextConfig */

const GH_PAGES_BASE = "/bossmind-resumora";

function isGhPagesBuild() {
  return process.env.GH_PAGES === "1";
}

/** @returns {Partial<NextConfig>} */
function ghPagesNextConfig() {
  if (!isGhPagesBuild()) return {};
  return {
    output: "export",
    basePath: GH_PAGES_BASE,
    assetPrefix: `${GH_PAGES_BASE}/`,
    images: { unoptimized: true },
    trailingSlash: true,
  };
}

module.exports = {
  GH_PAGES_BASE,
  isGhPagesBuild,
  ghPagesNextConfig,
};
