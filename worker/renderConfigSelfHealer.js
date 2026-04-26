async function patchRenderServiceConfig({
  serviceId,
  rootDirectory,
  buildCommand,
  startCommand,
}) {
  const token = process.env.RENDER_API_KEY;

  if (!token) {
    return {
      ok: false,
      reason: "Missing RENDER_API_KEY",
    };
  }

  if (!serviceId) {
    return {
      ok: false,
      reason: "Missing Render serviceId",
    };
  }

  const body = {
    rootDir: rootDirectory,
    buildCommand,
    startCommand,
  };

  const res = await fetch(`https://api.render.com/v1/services/${serviceId}`, {
    method: "PATCH",
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  });

  const data = await res.json().catch(() => ({}));

  return {
    ok: res.ok,
    status: res.status,
    serviceId,
    updatedConfig: body,
    response: data,
  };
}

async function triggerRenderDeploy({ serviceId, clearCache = true }) {
  const token = process.env.RENDER_API_KEY;

  if (!token) {
    return {
      ok: false,
      reason: "Missing RENDER_API_KEY",
    };
  }

  const res = await fetch(
    `https://api.render.com/v1/services/${serviceId}/deploys`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        clearCache,
      }),
    }
  );

  const data = await res.json().catch(() => ({}));

  return {
    ok: res.ok,
    status: res.status,
    serviceId,
    clearCache,
    response: data,
  };
}

module.exports = {
  patchRenderServiceConfig,
  triggerRenderDeploy,
};