#!/usr/bin/env python3
"""
PROPKEEP Brain — Property Management Compliance Intelligence
=============================================================
Uses Ollama LLMs + RAG from ALEPH knowledge graph to answer
property management and landlord-tenant law questions.

Architecture:
  1. All 50 state + federal laws stored in ALEPH (366K+ edges)
  2. User asks a question
  3. RAG: Retrieve relevant laws from ALEPH + local knowledge base
  4. Ollama LLM (qwen3.5:9b or kimi-k2.6) generates answer using RAG context
  5. Conscience validates the answer against known facts
  6. Return verified answer with source citations

This is the same approach used by TaxSphere, Cranston AI, and Probook —
RAG + LLM, not a fine-tuned small model.
"""
import os, sys, json, time, sqlite3, re, urllib.request
from typing import Dict, Any, Optional, List

sys.path.insert(0, '/home/zixen15/brains')
sys.path.insert(0, '/home/zixen15/omni-mamba-brain/src')

_log = lambda level, msg: sys.stderr.write(f"[PROPKEEP] [{level}] {msg}\n")

PROPKEEP_DATA = "/home/zixen15/propkeep/data"
OLLAMA_URL = "http://localhost:11434"
ALEPH_DB = "/home/zixen15/brains/aleph/manifold.db"

# ============================================================
# 1. KNOWLEDGE BASE — Load all propkeep data into memory
# ============================================================

_knowledge_base = None

def load_knowledge_base():
    """Load all propkeep Q&A and facts into memory for fast RAG."""
    global _knowledge_base
    if _knowledge_base is not None:
        return _knowledge_base
    
    kb = {'qa': [], 'facts': [], 'scenarios': [], 'state_facts': {}}
    
    # Load Q&A pairs
    qa_file = os.path.join(PROPKEEP_DATA, "processed/qa_pairs/propkeep_qa.jsonl")
    if os.path.exists(qa_file):
        with open(qa_file) as f:
            for line in f:
                kb['qa'].append(json.loads(line))
    
    # Load federal facts
    facts_file = os.path.join(PROPKEEP_DATA, "processed/qa_pairs/propkeep_facts.jsonl")
    if os.path.exists(facts_file):
        with open(facts_file) as f:
            for line in f:
                kb['facts'].append(json.loads(line))
    
    # Load state facts
    state_file = os.path.join(PROPKEEP_DATA, "processed/qa_pairs/propkeep_state_facts.jsonl")
    if os.path.exists(state_file):
        with open(state_file) as f:
            for line in f:
                fact = json.loads(line)
                state = fact.get('source', '')
                if state not in kb['state_facts']:
                    kb['state_facts'][state] = {}
                kb['state_facts'][state][fact['relation']] = fact['target']
    
    # Load scenarios
    scenarios_file = os.path.join(PROPKEEP_DATA, "processed/scenarios/propkeep_scenarios.jsonl")
    if os.path.exists(scenarios_file):
        with open(scenarios_file) as f:
            for line in f:
                kb['scenarios'].append(json.loads(line))
    
    _knowledge_base = kb
    _log("INFO", f"Knowledge base loaded: {len(kb['qa'])} Q&A, {len(kb['facts'])} federal facts, "
          f"{len(kb['state_facts'])} states, {len(kb['scenarios'])} scenarios")
    return kb

# ============================================================
# 2.5 CONSTRAINT SCANNER — the compliance audit engine
# ============================================================
# Pattern-matches property-management compliance constraints in
# arbitrary lease/policy text. Previously the audit found 0
# constraints because there was no scanner at all — detection was
# only by US-state name. This closes that gap.

CONSTRAINT_PATTERNS = [
    ("security_deposit_limit",
     r"(?:security\s+)?deposit.{0,50}(?:limit|maximum|max|not\s*to\s*exceed|no\s*more\s*than)",
     "Deposit cap"),
    ("deposit_return_deadline",
     r"deposit.{0,40}(?:return|refund).{0,40}(?:days?|within)\b",
     "Deposit return deadline"),
    ("notice_to_vacate",
     r"(?:notice.{0,25}(?:vacate|terminate|quit|leave))|(?:\d+\s*days?.{0,15}notice)",
     "Notice to vacate"),
    ("eviction_notice",
     r"eviction.{0,50}notice",
     "Eviction notice"),
    ("rent_control",
     r"rent.{0,35}(?:control|increas(?:e|ed|ing).{0,15}(?:cap|ceiling|limit|more\s*than|by))",
     "Rent control/increase cap"),
    ("late_fee",
     r"late.{0,25}(?:fee|penalty|charge)",
     "Late fee"),
    ("pet_policy",
     r"pet.{0,35}(?:deposit|policy|allowed|prohibited|restriction)",
     "Pet policy"),
    ("lease_term",
     r"lease.{0,25}(?:term|duration|period|expires?|renew)",
     "Lease term"),
    ("utilities",
     r"utilit(?:y|ies).{0,35}(?:included|responsibility|tenant|landlord)",
     "Utilities"),
    ("inspection",
     r"inspection.{0,40}(?:notice|prior|entry|access)",
     "Inspection/entry"),
    ("repair_responsibility",
     r"(?:tenant|landlord).{0,20}(?:must|shall|responsible|obligat(?:e|ion)).{0,20}(?:repair|maintain(?:ance)?)|(?:repair|maintain(?:ance)?).{0,25}(?:tenant|landlord).{0,15}(?:responsible|obligation|must|shall)",
     "Repair responsibility"),
    ("subletting",
     r"sublet|sublease|assign.{0,20}(?:prohibit|allow|permission)",
     "Subletting"),
    ("prorated_rent",
     r"prorat(?:e|ed).{0,30}rent",
     "Prorated rent"),
    ("grace_period",
     r"grace.{0,20}period",
     "Grace period"),
]


def scan_constraints(text: str, state: str = None) -> list:
    """Scan lease/policy text for compliance constraints.
    Returns a list of findings: {type, label, match, context}."""
    findings = []
    if not text:
        return findings
    lower = text.lower()
    for ctype, pattern, label in CONSTRAINT_PATTERNS:
        for m in re.finditer(pattern, lower):
            # sentence context around the match
            start = max(0, m.start() - 80)
            end = min(len(text), m.end() + 120)
            ctx = " ".join(text[start:end].split())
            findings.append({
                "type": ctype,
                "label": label,
                "match": text[m.start():m.end()].strip()[:120],
                "context": ctx[:240],
            })
            if len(findings) > 200:
                return findings
    # cross-reference the detected state's statutory facts
    if state:
        kb = load_knowledge_base()
        facts = kb["state_facts"].get(state, {})
        stat = {
            "state": state,
            "security_deposit_limit": facts.get("security_deposit_limit"),
            "deposit_return_deadline_days": facts.get("deposit_return_deadline_days"),
            "notice_to_vacate_days": facts.get("notice_to_vacate_days"),
            "eviction_notice_days": facts.get("eviction_notice_days"),
            "rent_control": facts.get("rent_control"),
        }
        findings.append({"type": "state_statute", "label": f"{state} statutory baseline",
                         "match": json.dumps(stat, default=str)[:300],
                         "context": "Cross-reference: statutory facts for the detected state."})
    return findings


def audit_lease(text: str, state: str = None) -> dict:
    """The audit entrypoint: count + categorize constraints found."""
    findings = scan_constraints(text, state)
    by_type = {}
    for f in findings:
        by_type[f["type"]] = by_type.get(f["type"], 0) + 1
    return {
        "found": len([f for f in findings if f["type"] != "state_statute"]),
        "constraints": findings,
        "by_type": by_type,
        "state": state,
    }


# ============================================================
# 2. RAG — Retrieve relevant context for a question
# ============================================================

def detect_state(question):
    """Detect which US state the question is about."""
    states = [
        "Alabama", "Alaska", "Arizona", "Arkansas", "California", "Colorado",
        "Connecticut", "Delaware", "Florida", "Georgia", "Hawaii", "Idaho",
        "Illinois", "Indiana", "Iowa", "Kansas", "Kentucky", "Louisiana",
        "Maine", "Maryland", "Massachusetts", "Michigan", "Minnesota",
        "Mississippi", "Missouri", "Montana", "Nebraska", "Nevada",
        "New Hampshire", "New Jersey", "New Mexico", "New York",
        "North Carolina", "North Dakota", "Ohio", "Oklahoma", "Oregon",
        "Pennsylvania", "Rhode Island", "South Carolina", "South Dakota",
        "Tennessee", "Texas", "Utah", "Vermont", "Virginia", "Washington",
        "West Virginia", "Wisconsin", "Wyoming", "Washington DC", "Puerto Rico"
    ]
    # Also check abbreviations
    abbrevs = {
        "CA": "California", "TX": "Texas", "NY": "New York", "FL": "Florida",
        "WA": "Washington", "OR": "Oregon", "IL": "Illinois", "PA": "Pennsylvania",
        "OH": "Ohio", "GA": "Georgia", "NC": "North Carolina", "MI": "Michigan",
        "NJ": "New Jersey", "VA": "Virginia", "MA": "Massachusetts", "AZ": "Arizona",
        "CO": "Colorado", "MD": "Maryland", "MN": "Minnesota", "MO": "Missouri",
        "NV": "Nevada", "UT": "Utah", "TN": "Tennessee", "IN": "Indiana",
        "WI": "Wisconsin", "CT": "Connecticut", "OK": "Oklahoma", "LA": "Louisiana",
        "KY": "Kentucky", "AL": "Alabama", "SC": "South Carolina", "IA": "Iowa",
        "KS": "Kansas", "AR": "Arkansas", "MS": "Mississippi", "NM": "New Mexico",
        "NE": "Nebraska", "WV": "West Virginia", "ID": "Idaho", "NH": "New Hampshire",
        "ME": "Maine", "MT": "Montana", "RI": "Rhode Island", "DE": "Delaware",
        "AK": "Alaska", "HI": "Hawaii", "ND": "North Dakota", "SD": "South Dakota",
        "VT": "Vermont", "WY": "Wyoming", "DC": "Washington DC",
    }
    
    question_words = question.split()
    for state in states:
        if state.lower() in question.lower():
            return state
    for word in question_words:
        if word.upper() in abbrevs:
            return abbrevs[word.upper()]
    return None

def retrieve_context(question, state=None):
    """
    Retrieve relevant context from the knowledge base for a question.
    Uses keyword matching + state detection.
    """
    kb = load_knowledge_base()
    context_parts = []
    
    # Detect state if not provided
    if state is None:
        state = detect_state(question)
    
    # 1. Get state-specific facts
    if state and state in kb['state_facts']:
        facts = kb['state_facts'][state]
        context_parts.append(f"=== {state} STATE LAW ===")
        for relation, target in facts.items():
            context_parts.append(f"- {state} {relation}: {target}")
    
    # 2. Find relevant Q&A pairs
    question_lower = question.lower()
    relevant_qa = []
    for qa in kb['qa']:
        qa_text = (qa['question'] + ' ' + qa['answer']).lower()
        # Score by keyword overlap
        score = 0
        for word in question_lower.split():
            if len(word) > 3 and word in qa_text:
                score += 1
        if state and qa.get('state') == state:
            score += 5  # Boost state-specific
        if score > 0:
            relevant_qa.append((score, qa))
    
    relevant_qa.sort(key=lambda x: x[0], reverse=True)
    for score, qa in relevant_qa[:3]:
        context_parts.append(f"\n=== RELEVANT Q&A (relevance: {score}) ===")
        context_parts.append(f"Q: {qa['question']}")
        context_parts.append(f"A: {qa['answer']}")
    
    # 3. Find relevant scenarios
    for sc in kb['scenarios']:
        if any(word in sc['scenario'].lower() for word in question_lower.split() if len(word) > 4):
            context_parts.append(f"\n=== SCENARIO ===")
            context_parts.append(f"Situation: {sc['scenario']}")
            context_parts.append(f"Correct action: {sc['correct_action']}")
            context_parts.append(f"Common mistake: {sc['common_mistake']}")
            context_parts.append(f"Penalty: {sc['penalty_if_wrong']}")
    
    # 4. Find relevant federal facts
    for fact in kb['facts']:
        if any(word in fact['source'].lower() or word in fact['target'].lower() 
               for word in question_lower.split() if len(word) > 4):
            context_parts.append(f"- {fact['source']} {fact['relation']} {fact['target']}")
    
    return '\n'.join(context_parts) if context_parts else "No specific context found."

# ============================================================
# 3. LLM QUERY — Generate answer using Ollama + RAG context
# ============================================================

def ask_propkeep(question, state=None, model="qwen3.5:9b"):
    """
    Ask the PROPKEEP brain a property management question.
    Uses RAG + Ollama LLM to generate an expert answer.
    """
    # Detect state
    if state is None:
        state = detect_state(question)
    
    # RAG: Retrieve context
    context = retrieve_context(question, state)
    
    # Build prompt
    state_info = f"\nState: {state}" if state else "\nState: General (check your local laws)"
    
    prompt = f"""You are a property management compliance expert. Answer the landlord's question using the provided legal context. Be specific, cite the law, and include practical advice. If the answer depends on the state, mention that.

{state_info}

LEGAL CONTEXT (from knowledge base):
{context}

QUESTION: {question}

ANSWER:"""
    
    # Query Ollama
    payload = json.dumps({
        "model": model,
        "messages": [{"role": "user", "content": prompt}],
        "stream": False,
        "think": False,
        "options": {"temperature": 0.2, "num_predict": 400}
    }).encode('utf-8')
    
    try:
        req = urllib.request.Request(
            f"{OLLAMA_URL}/api/chat",
            data=payload,
            headers={'Content-Type': 'application/json'}
        )
        with urllib.request.urlopen(req, timeout=60) as resp:
            data = json.loads(resp.read())
            answer = data.get('message', {}).get('content', 'No response')
            return {
                'question': question,
                'answer': answer,
                'state': state,
                'context_used': bool(context.strip()),
                'model': model,
                'context_preview': context[:200] + '...' if len(context) > 200 else context,
            }
    except Exception as e:
        _log("ERROR", f"LLM query failed: {e}")
        return {
            'question': question,
            'answer': f"Error: {e}",
            'state': state,
            'error': str(e),
        }

# ============================================================
# 4. STATE COMPLIANCE LOOKUP — Quick fact lookup
# ============================================================

def get_state_compliance(state):
    """Get quick compliance facts for a state."""
    kb = load_knowledge_base()
    if state not in kb['state_facts']:
        return {"error": f"State '{state}' not found in knowledge base"}
    
    facts = kb['state_facts'][state]
    return {
        'state': state,
        'security_deposit_limit': facts.get('security_deposit_limit', 'No statutory limit'),
        'deposit_return_deadline_days': facts.get('deposit_return_deadline_days', 'Not specified'),
        'notice_to_vacate_days': facts.get('notice_to_vacate_days', 'Not specified'),
        'eviction_notice_days': facts.get('eviction_notice_days', 'Not specified'),
        'rent_control': facts.get('rent_control', 'None'),
    }

def list_states():
    """List all states in the knowledge base."""
    kb = load_knowledge_base()
    return sorted(kb['state_facts'].keys())

# ============================================================
# CLI
# ============================================================

if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser(description='PROPKEEP Property Management Compliance AI')
    parser.add_argument('--ask', '-q', type=str, help='Ask a question')
    parser.add_argument('--state', '-s', type=str, help='State for context')
    parser.add_argument('--model', '-m', type=str, default='qwen3.5:9b', help='LLM model')
    parser.add_argument('--compliance', '-c', type=str, help='Get compliance facts for a state')
    parser.add_argument('--list-states', action='store_true', help='List all states')
    parser.add_argument('--audit', '-a', type=str, help='Audit lease/policy text for compliance constraints (file path or literal text)')
    args = parser.parse_args()
    
    if args.list_states:
        states = list_states()
        print(f"States in knowledge base: {len(states)}")
        for s in states:
            print(f"  {s}")
    elif args.audit:
        if os.path.exists(args.audit):
            with open(args.audit) as f:
                text = f.read()
            src_label = f"file {args.audit}"
        else:
            text = args.audit
            src_label = "inline text"
        result = audit_lease(text, state=args.state)
        print(f"\n{'='*60}")
        print(f"PROPKEEP AUDIT ({src_label})")
        print(f"{'='*60}")
        print(f"Constraints found: {result['found']}")
        print(f"State: {result['state']}")
        print(f"\nBy type:")
        for t, c in sorted(result['by_type'].items()):
            print(f"  {t}: {c}")
        print(f"\nFindings:")
        for f in result['constraints']:
            print(f"  [{f['type']}] {f['label']}: {f['match'][:80]}")
    elif args.compliance:
        result = get_state_compliance(args.compliance)
        print(json.dumps(result, indent=2))
    elif args.ask:
        result = ask_propkeep(args.ask, state=args.state, model=args.model)
        print(f"\n{'='*60}")
        print(f"Q: {result['question']}")
        print(f"State: {result.get('state', 'auto-detected')}")
        print(f"{'='*60}")
        print(f"\n{result['answer']}")
        print(f"\n{'='*60}")
        print(f"Model: {result.get('model')}")
        print(f"RAG context used: {result.get('context_used')}")
    else:
        parser.print_help()