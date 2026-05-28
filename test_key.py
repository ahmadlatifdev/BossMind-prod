import requests

key = "sk-100fc369bcb843e5a6e9f90f338e3402"

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
result = response.json()
print(result)
