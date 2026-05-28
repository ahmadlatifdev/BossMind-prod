import requests

key = 'sk-79f877637729408cbbecfabdefeac663'
url = 'https://api.deepseek.com/v1/chat/completions'
headers = {
    'Authorization': f'Bearer {key}',
    'Content-Type': 'application/json'
}
data = {
    'model': 'deepseek-v4-flash',
    'messages': [{'role': 'user', 'content': 'Say OK'}],
    'max_tokens': 50
}
response = requests.post(url, headers=headers, json=data)
print(response.json()['choices'][0]['message']['content'])
