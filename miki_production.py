import requests
import json
import threading
import time
import os
from datetime import datetime
from collections import deque

# ========== FORCE LOAD NEW KEY ==========
API_KEY = "sk-100fc369bcb843e5a6e9f90f338e3402"
SENTRY_DSN = "https://87eb27529c7384f915bc2d91ebfafbs@o4512754909614080.ingest.us.sentry.io/451794933731328"
MODEL = "deepseek-v4-flash"
URL = "https://api.deepseek.com/v1/chat/completions"

print(f"✅ Using API Key: {API_KEY[:15]}...")

# ========== SENTRY ==========
if SENTRY_DSN:
    try:
        import sentry_sdk
        sentry_sdk.init(dsn=SENTRY_DSN, traces_sample_rate=0.5)
        print("✅ Sentry connected")
    except Exception as e:
        print(f"⚠️ Sentry error: {e}")

def call_deepseek(prompt, system=None):
    messages = []
    if system:
        messages.append({"role": "system", "content": system})
    messages.append({"role": "user", "content": prompt})
    
    headers = {"Authorization": f"Bearer {API_KEY}", "Content-Type": "application/json"}
    data = {"model": MODEL, "messages": messages, "max_tokens": 500, "temperature": 0.3}
    
    try:
        response = requests.post(URL, headers=headers, json=data, timeout=30)
        result = response.json()
        
        if 'choices' in result and len(result['choices']) > 0:
            return result['choices'][0].get('message', {}).get('content', 'No content')
        else:
            return f"ERROR: {result.get('error', {}).get('message', 'Unknown error')}"
    except Exception as e:
        return f"ERROR: {str(e)}"

class Blackboard:
    def __init__(self):
        self.tasks = {}
        self.results = {}
        self.task_counter = 0
        self.lock = threading.Lock()
    
    def add_task(self, task_type, input_data, priority=0):
        with self.lock:
            self.task_counter += 1
            task_id = f"task_{self.task_counter}"
            self.tasks[task_id] = {
                'id': task_id, 'type': task_type, 'input': input_data,
                'status': 'pending', 'priority': priority, 'created_at': str(datetime.now())
            }
            print(f"[{datetime.now().strftime('%H:%M:%S')}] 📋 Task: {task_type}")
            return task_id
    
    def get_task(self, agent_name):
        with self.lock:
            pending = [t for t in self.tasks.values() if t['status'] == 'pending']
            if not pending:
                return None
            pending.sort(key=lambda x: x['priority'], reverse=True)
            task = pending[0]
            task['status'] = 'processing'
            task['assigned_to'] = agent_name
            return task
    
    def submit_result(self, task_id, result, agent_name):
        with self.lock:
            self.tasks[task_id]['status'] = 'completed'
            self.results[task_id] = {'result': result, 'by': agent_name, 'at': str(datetime.now())}
            print(f"[{datetime.now().strftime('%H:%M:%S')}] ✅ {agent_name} done: {self.tasks[task_id]['type']}")
    
    def status(self):
        pending = len([t for t in self.tasks.values() if t['status'] == 'pending'])
        processing = len([t for t in self.tasks.values() if t['status'] == 'processing'])
        done = len([t for t in self.tasks.values() if t['status'] == 'completed'])
        return {'pending': pending, 'processing': processing, 'completed': done, 'total': len(self.tasks)}

class ResumoraAgent:
    def __init__(self, blackboard):
        self.name = "Resumora"
        self.blackboard = blackboard
        self.running = False
    
    def execute(self, task):
        text = task['input'].get('text', '')[:2000]
        prompt = f"Extract name, skills, years_experience from this resume. Return ONLY valid JSON.\n\nResume: {text}"
        return call_deepseek(prompt, system="You are a resume parser. Return only JSON. Example: {\"name\": \"...\", \"skills\": [...], \"years\": 0}")
    
    def run(self):
        self.running = True
        while self.running:
            task = self.blackboard.get_task(self.name)
            if task:
                result = self.execute(task)
                self.blackboard.submit_result(task['id'], result, self.name)
            time.sleep(0.5)
    
    def start(self):
        self.thread = threading.Thread(target=self.run)
        self.thread.daemon = True
        self.thread.start()
        print(f"📄 Resumora Agent started")

class ElegancyartAgent:
    def __init__(self, blackboard):
        self.name = "Elegancyart"
        self.blackboard = blackboard
        self.running = False
    
    def execute(self, task):
        brand = task['input'].get('brand', 'Portfolio')
        prompt = f"Generate HTML/CSS for a portfolio website for '{brand}'. Include hero section and gallery. Make it responsive. Return ONLY the HTML/CSS code."
        return call_deepseek(prompt, system="You are a web designer. Return only valid HTML/CSS code. No explanations.")
    
    def run(self):
        self.running = True
        while self.running:
            task = self.blackboard.get_task(self.name)
            if task:
                result = self.execute(task)
                self.blackboard.submit_result(task['id'], result, self.name)
            time.sleep(0.5)
    
    def start(self):
        self.thread = threading.Thread(target=self.run)
        self.thread.daemon = True
        self.thread.start()
        print(f"🎨 Elegancyart Agent started")

if __name__ == "__main__":
    print("\n" + "="*50)
    print("MIKI BLACKBOARD + SENTRY")
    print("="*50 + "\n")
    
    board = Blackboard()
    
    resumora = ResumoraAgent(board)
    elegancyart = ElegancyartAgent(board)
    
    resumora.start()
    elegancyart.start()
    
    board.add_task("parse_resume", {"text": "Jane Doe, Python Developer, 8 years experience"})
    board.add_task("generate_portfolio", {"brand": "Creative Studio"})
    
    time.sleep(20)
    
    print("\n" + "="*50)
    print("RESULTS")
    print("="*50)
    for task_id, result in board.results.items():
        print(f"\n{task_id}: {str(result['result'])[:300]}...")
    
    print(f"\n✅ Complete. Status: {board.status()}")
