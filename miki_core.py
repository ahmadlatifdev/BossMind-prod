import requests
import json
import time

API_KEY = "sk-79f877637729408cbbecfabdefeac663"

def call_deepseek(prompt):
    headers = {
        "Authorization": f"Bearer {API_KEY}",
        "Content-Type": "application/json"
    }
    data = {
        "model": "deepseek-v4-flash",
        "messages": [{"role": "user", "content": prompt}],
        "max_tokens": 200
    }
    response = requests.post("https://api.deepseek.com/v1/chat/completions", headers=headers, json=data)
    return response.json()['choices'][0]['message']['content']

print("Miki Blackboard System Started")
print("Testing DeepSeek connection...")

result = call_deepseek("Say Hello from Miki")
print(f"Response: {result}")

print("Miki is ready!")
