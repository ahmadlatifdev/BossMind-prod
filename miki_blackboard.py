import requests
import json
import threading
import time
from datetime import datetime
from collections import deque

API_KEY = "sk-79f877637729408cbbecfabdefeac663"
MODEL = "deepseek-v4-flash"
URL = "https://api.deepseek.com/v1/chat/completions"

def call_deepseek(prompt, system=None):
    messages = []
    if system:
        messages.append({"role": "system", "content": system})
    messages.append({"role": "user", "content": prompt})
    
    headers = {"Authorization": f"Bearer {API_KEY}", "Content-Type": "application/json"}
    data = {"model": MODEL, "messages": messages, "max_tokens": 1000, "temperature": 0.3}
    
    response = requests.post(URL, headers=headers, json=data)
    return response.json()['choices'][0]['message']['content']


class Blackboard:
    def __init__(self):
        self.tasks = {}
        self.results = {}
        self.messages = deque(maxlen=50)
        self.shared = {}
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
    
    def post(self, sender, recipient, content):
        self.messages.append({'from': sender, 'to': recipient, 'content': content, 'time': str(datetime.now())})
    
    def get_messages(self, agent):
        return [m for m in self.messages if m['to'] == agent or m['to'] == 'all']
    
    def status(self):
        pending = len([t for t in self.tasks.values() if t['status'] == 'pending'])
        done = len([t for t in self.tasks.values() if t['status'] == 'completed'])
        return {'pending': pending, 'completed': done, 'total': len(self.tasks)}


class Agent:
    def __init__(self, name, blackboard, capabilities):
        self.name = name
        self.blackboard = blackboard
        self.capabilities = capabilities
        self.running = False
    
    def execute(self, task):
        prompt = f"Task: {task['type']}\nInput: {json.dumps(task['input'])}\n\nRespond with result in JSON format."
        return call_deepseek(prompt, system="You are a helpful AI agent. Return valid JSON.")
    
    def run(self):
        self.running = True
        while self.running:
            task = self.blackboard.get_task(self.name)
            if task and task['type'] in self.capabilities:
                print(f"[{self.name}] Processing: {task['type']}")
                result = self.execute(task)
                self.blackboard.submit_result(task['id'], result, self.name)
                print(f"[{self.name}] Completed: {task['type']}")
            time.sleep(1)
    
    def start(self):
        self.thread = threading.Thread(target=self.run)
        self.thread.daemon = True
        self.thread.start()
        print(f"[{self.name}] Started")
    
    def stop(self):
        self.running = False


# ========== BOSSMIND AGENTS ==========

class ResumoraAgent(Agent):
    def __init__(self, blackboard):
        super().__init__("Resumora", blackboard, ["parse_resume", "extract_skills"])
    
    def execute(self, task):
        if task['type'] == "parse_resume":
            text = task['input'].get('text', '')[:2000]
            prompt = f"Extract: name, email, skills, years_experience from this resume:\n{text}\nReturn JSON."
            return call_deepseek(prompt, system="Return only valid JSON.")

class ElegancyartAgent(Agent):
    def __init__(self, blackboard):
        super().__init__("Elegancyart", blackboard, ["generate_portfolio", "create_hero"])
    
    def execute(self, task):
        if task['type'] == "generate_portfolio":
            brand = task['input'].get('brand', 'Portfolio')
            prompt = f"Generate HTML/CSS for a {brand} portfolio website. Hero section, gallery, contact."
            return call_deepseek(prompt, system="You are a web designer. Return complete HTML/CSS.")


# ========== RUN ==========

if __name__ == "__main__":
    print("=== Miki Blackboard System for BossMind ===\n")
    
    board = Blackboard()
    
    resumora = ResumoraAgent(board)
    elegancyart = ElegancyartAgent(board)
    
    resumora.start()
    elegancyart.start()
    
    # Add tasks
    task1 = board.add_task("parse_resume", {"text": "Jane Doe, Python Developer, 8 years experience"})
    task2 = board.add_task("generate_portfolio", {"brand": "Creative Studio"})
    
    print(f"Added task: {task1}")
    print(f"Added task: {task2}")
    
    # Wait for completion
    time.sleep(15)
    
    resumora.stop()
    elegancyart.stop()
    
    print("\n=== RESULTS ===")
    for task_id, result in board.results.items():
        print(f"{task_id}: {str(result['result'])[:200]}...")
    
    print(f"\n=== STATUS: {board.status()}")
    print("\nMiki Blackboard Ready for BossMind Automation")
