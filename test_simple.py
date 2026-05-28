import requests
key = 'sk-86a0ce5e96fd4f43188c91'
url = 'https://api.deepseek.com/v1/chat/completions'
headers = {'Authorization': f'Bearer {key}', 'Content-Type': 'application/json'}
data = {'model': 'deepseek-v4-flash', 'messages': [{'role': 'user', 'content': 'Say OK'}], 'max_tokens': 10}
r = requests.post(url, headers=headers, json=data)
print(r.json().get('choices', [{}])[0].get('message', {}).get('content', 'ERROR'))
