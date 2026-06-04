import requests

API_KEY = "sk-79f877637729408cbbecfabdefeac663"

url = "https://api.deepseek.com/v1/chat/completions"
headers = {
    "Authorization": f"Bearer {API_KEY}",
    "Content-Type": "application/json"
}
data = {
    "model": "deepseek-v4-flash",
    "messages": [{"role": "user", "content": "Say OK"}],
    "max_tokens": 10
}

response = requests.post(url, headers=headers, json=data)
print(response.json())



import requests

key = "sk-79f877637729408cbbecfabdefeac663"

headers = {
    "Authorization": f"Bearer {key}",
    "Content-Type": "application/json"
}

data = {
    "model": "deepseek-v4-flash",
    "messages": [{"role": "user", "content": "Say OK"}],
    "max_tokens": 10
}

response = requests.post("https://api.deepseek.com/v1/chat/completions", headers=headers, json=data)
print(response.json())










[{"id":"870b275f29c7384f915bc2d91ebfafb9","name":"Default","label":"Default","public":"870b275f29c7384f915bc2d91ebfafb9","secret":"ef61dd89510e97b873836830c3ed784a","projectId":4510794933731328,"isActive":true,"rateLimit":null,"dsn":{"secret":"https://870b275f29c7384f915bc2d91ebfafb9:ef61dd89510e97b873836830c3ed784a@o4510794909614080.ingest.us.sentry.io/4510794933731328","public":"https://870b275f29c7384f915bc2d91ebfafb9@o4510794909614080.ingest.us.sentry.io/4510794933731328","csp":"https://o4510794909614080.ingest.us.sentry.io/api/4510794933731328/csp-report/?sentry_key=870b275f29c7384f915bc2d91ebfafb9","security":"https://o4510794909614080.ingest.us.sentry.io/api/4510794933731328/security/?sentry_key=870b275f29c7384f915bc2d91ebfafb9","minidump":"https://o4510794909614080.ingest.us.sentry.io/api/4510794933731328/minidump/?sentry_key=870b275f29c7384f915bc2d91ebfafb9","nel":"https://o4510794909614080.ingest.us.sentry.io/api/4510794933731328/nel/?sentry_key=870b275f29c7384f915bc2d91ebfafb9","unreal":"https://o4510794909614080.ingest.us.sentry.io/api/4510794933731328/unreal/870b275f29c7384f915bc2d91ebfafb9/","crons":"https://o4510794909614080.ingest.us.sentry.io/api/4510794933731328/cron/___MONITOR_SLUG___/870b275f29c7384f915bc2d91ebfafb9/","cdn":"https://js.sentry-cdn.com/870b275f29c7384f915bc2d91ebfafb9.min.js","playstation":"https://o4510794909614080.ingest.us.sentry.io/api/4510794933731328/playstation/?sentry_key=870b275f29c7384f915bc2d91ebfafb9","integration":"https://o4510794909614080.ingest.us.sentry.io/api/4510794933731328/integration/","otlp_traces":"https://o4510794909614080.ingest.us.sentry.io/api/4510794933731328/integration/otlp/v1/traces","otlp_logs":"https://o4510794909614080.ingest.us.sentry.io/api/4510794933731328/integration/otlp/v1/logs"},"browserSdkVersion":"10.x","browserSdk":{"choices":[["10.x","10.x"],["9.x","9.x"],["8.x","8.x"],["7.x","7.x"]]},"dateCreated":"2026-01-29T17:41:02.969782Z","dynamicSdkLoaderOptions":{"hasReplay":true,"hasPerformance":true,"hasDebug":false,"hasFeedback":false,"hasLogsAndMetrics":false}}]