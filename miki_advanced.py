import requests
import json
import threading
import time
import os
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
    data = {"model": MODEL, "messages": messages, "max_tokens": 2000, "temperature": 0.3}
    
    try:
        response = requests.post(URL, headers=headers, json=data, timeout=30)
        return response.json()['choices'][0]['message']['content']
    except Exception as e:
        return f"ERROR: {str(e)}"


class Blackboard:
    def __init__(self):
        self.tasks = {}
        self.results = {}
        self.messages = deque(maxlen=100)
        self.shared = {}
        self.task_counter = 0
        self.lock = threading.Lock()
        self.logs = []
    
    def add_task(self, task_type, input_data, priority=0):
        with self.lock:
            self.task_counter += 1
            task_id = f"task_{self.task_counter}"
            self.tasks[task_id] = {
                'id': task_id, 'type': task_type, 'input': input_data,
                'status': 'pending', 'priority': priority, 'created_at': str(datetime.now())
            }
            self._log(f"📋 Task added: {task_type}")
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
            self._log(f"🔄 {agent_name} started: {task['type']}")
            return task
    
    def submit_result(self, task_id, result, agent_name):
        with self.lock:
            self.tasks[task_id]['status'] = 'completed'
            self.results[task_id] = {'result': result, 'by': agent_name, 'at': str(datetime.now())}
            task_type = self.tasks[task_id]['type']
            self._log(f"✅ {agent_name} completed: {task_type}")
    
    def _log(self, msg):
        timestamp = datetime.now().strftime("%H:%M:%S")
        log_entry = f"[{timestamp}] {msg}"
        self.logs.append(log_entry)
        print(log_entry)
    
    def post(self, sender, recipient, content):
        self.messages.append({'from': sender, 'to': recipient, 'content': content, 'time': str(datetime.now())})
    
    def status(self):
        pending = len([t for t in self.tasks.values() if t['status'] == 'pending'])
        processing = len([t for t in self.tasks.values() if t['status'] == 'processing'])
        done = len([t for t in self.tasks.values() if t['status'] == 'completed'])
        return {'pending': pending, 'processing': processing, 'completed': done, 'total': len(self.tasks)}
    
    def show_dashboard(self):
        status = self.status()
        print("\n" + "="*50)
        print(f"📊 MIKI DASHBOARD")
        print("="*50)
        print(f"📋 Tasks: {status['total']} total | ⏳ {status['pending']} pending | 🔄 {status['processing']} processing | ✅ {status['completed']} completed")
        print("="*50 + "\n")


class Agent:
    def __init__(self, name, blackboard, capabilities, icon="🤖"):
        self.name = name
        self.blackboard = blackboard
        self.capabilities = capabilities
        self.icon = icon
        self.running = False
    
    def execute(self, task):
        prompt = f"Task: {task['type']}\nInput: {json.dumps(task['input'], indent=2)}\n\nRespond with result in JSON format."
        return call_deepseek(prompt, system="You are a helpful AI agent. Return valid JSON.")
    
    def run(self):
        self.running = True
        while self.running:
            task = self.blackboard.get_task(self.name)
            if task and task['type'] in self.capabilities:
                result = self.execute(task)
                self.blackboard.submit_result(task['id'], result, self.name)
            time.sleep(0.5)
    
    def start(self):
        self.thread = threading.Thread(target=self.run)
        self.thread.daemon = True
        self.thread.start()
        print(f"{self.icon} [{self.name}] Started | Capabilities: {self.capabilities}")
    
    def stop(self):
        self.running = False


# ========== BOSSMIND AGENTS ==========

class ResumoraAgent(Agent):
    def __init__(self, blackboard):
        super().__init__("Resumora", blackboard, ["parse_resume", "extract_skills", "match_job"], "📄")
    
    def execute(self, task):
        if task['type'] == "parse_resume":
            text = task['input'].get('text', '')[:3000]
            prompt = f"Extract from this resume: name, email, phone, skills (list), experience (years), education. Return JSON.\n\nResume:\n{text}"
            return call_deepseek(prompt, system="Return ONLY valid JSON. No extra text.")
        return super().execute(task)


class ElegancyartAgent(Agent):
    def __init__(self, blackboard):
        super().__init__("Elegancyart", blackboard, ["generate_portfolio", "design_hero", "create_gallery"], "🎨")
    
    def execute(self, task):
        if task['type'] == "generate_portfolio":
            brand = task['input'].get('brand', 'Portfolio')
            style = task['input'].get('style', 'modern minimalist')
            prompt = f"Generate complete HTML/CSS for a {style} portfolio website for '{brand}'. Include hero section, image gallery, contact form. Make it responsive."
            return call_deepseek(prompt, system="You are a web designer. Return complete HTML/CSS code.")
        return super().execute(task)


class VideoAgent(Agent):
    def __init__(self, blackboard):
        super().__init__("VideoGen", blackboard, ["analyze_scene", "generate_script"], "🎬")
    
    def execute(self, task):
        if task['type'] == "generate_script":
            topic = task['input'].get('topic', 'AI')
            duration = task['input'].get('duration', 60)
            prompt = f"Write a {duration}-second video script about '{topic}'. Include scene descriptions and voiceover text."
            return call_deepseek(prompt, system="You are a video script writer. Return JSON with 'scenes' array.")
        return super().execute(task)


class StockAgent(Agent):
    def __init__(self, blackboard):
        super().__init__("StockTrade", blackboard, ["analyze_trend", "risk_assessment"], "📈")
    
    def execute(self, task):
        if task['type'] == "analyze_trend":
            symbol = task['input'].get('symbol', 'AAPL')
            prompt = f"Analyze stock {symbol} trends. Return JSON with: sentiment (bullish/bearish/neutral), key_levels (support/resistance), risk_score (1-10)."
            return call_deepseek(prompt, system="Return ONLY valid JSON.")
        return super().execute(task)


class CoordinatorAgent(Agent):
    def __init__(self, blackboard):
        super().__init__("Coordinator", blackboard, ["orchestrate", "decompose", "merge"], "🎯")
    
    def execute(self, task):
        if task['type'] == "orchestrate":
            goal = task['input'].get('goal', '')
            prompt = f"Break this goal into subtasks for specialized agents (Resumora, Elegancyart, VideoGen, StockTrade):\n\nGoal: {goal}\n\nReturn JSON with 'subtasks' array, each with 'agent', 'type', 'input'."
            return call_deepseek(prompt, system="Return ONLY valid JSON.")
        return super().execute(task)


# ========== MAIN ==========

if __name__ == "__main__":
    print("\n" + "="*60)
    print("🧠 MIKI BLACKBOARD SYSTEM - BOSSMIND AI ORCHESTRATION")
    print("="*60 + "\n")
    
    board = Blackboard()
    
    # Create all agents
    agents = [
        ResumoraAgent(board),
        ElegancyartAgent(board),
        VideoAgent(board),
        StockAgent(board),
        CoordinatorAgent(board)
    ]
    
    # Start all agents
    for agent in agents:
        agent.start()
    
    time.sleep(1)
    print("\n" + "-"*40)
    print("🚀 SYSTEM READY - ADDING TASKS")
    print("-"*40 + "\n")
    
    # Add sample tasks
    board.add_task("parse_resume", {"text": "John Smith, Senior Data Scientist, 7 years experience in Python, SQL, ML. PhD in Computer Science."})
    board.add_task("generate_portfolio", {"brand": "Luna Creative", "style": "dark theme with neon accents"})
    board.add_task("generate_script", {"topic": "Future of AI in Healthcare", "duration": 90})
    board.add_task("analyze_trend", {"symbol": "NVDA"})
    
    # Show dashboard periodically
    for i in range(20):
        time.sleep(3)
        board.show_dashboard()
        if board.status()['pending'] == 0 and board.status()['processing'] == 0:
            break
    
    # Stop all agents
    for agent in agents:
        agent.stop()
    
    print("\n" + "="*60)
    print("📊 FINAL RESULTS")
    print("="*60)
    
    for task_id, result in board.results.items():
        task_type = board.tasks[task_id]['type']
        result_str = str(result['result'])[:300]
        print(f"\n📌 {task_type} ({task_id})")
        print(f"   {result_str}...")
    
    print(f"\n✅ Miki Blackboard Complete!")
    print(f"📈 Final Status: {board.status()}")
