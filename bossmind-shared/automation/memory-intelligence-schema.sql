CREATE TABLE IF NOT EXISTS bossmind_memory_index (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  project_key TEXT,
  file_path TEXT UNIQUE,
  file_role TEXT,
  content_hash TEXT,
  content_preview TEXT,
  keywords TEXT,
  dependency_count INT DEFAULT 0,
  risk_level TEXT DEFAULT 'low',
  updated_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS bossmind_dependency_graph (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  project_key TEXT,
  source_file TEXT,
  dependency TEXT,
  dependency_type TEXT,
  created_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(source_file, dependency)
);

CREATE TABLE IF NOT EXISTS bossmind_impact_analysis (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  project_key TEXT,
  changed_file TEXT,
  file_role TEXT,
  risk_level TEXT,
  impacted_files TEXT,
  impacted_count INT DEFAULT 0,
  recommended_action TEXT,
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS bossmind_context_retrieval (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  project_key TEXT,
  query_text TEXT,
  matched_file TEXT,
  match_reason TEXT,
  recommended_fix_context TEXT,
  created_at TIMESTAMP DEFAULT NOW()
);

INSERT INTO bossmind_context_retrieval
(project_key, query_text, matched_file, match_reason, recommended_fix_context)
VALUES
('shared','safe fix context','D:\BossMind\bossmind-shared\automation','memory intelligence seed','Use validation guard, anti-leak snapshot, safe write staging, rollback, and dependency check before modifying automation files.');
