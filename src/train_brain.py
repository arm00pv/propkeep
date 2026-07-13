#!/usr/bin/env python3
"""
PROPKEEP Brain Trainer — Fine-tunes Mamba-3 LoRA adapter on property management law
==================================================================================

Trains a specialized LoRA adapter on the propkeep dataset:
  - 24 federal law facts (Fair Housing, ADA, lead paint, eviction)
  - 255 state law facts (all 50 states + DC)
  - 316 Q&A pairs (common landlord questions with expert answers)
  - 8 compliance scenarios (correct actions, common mistakes, penalties)

The adapter is trained on the existing Mamba-3 base model (omni_v1_gpu_best.pt)
using the same LoRA infrastructure (rank=4, alpha=16) as the other brains.

Output: checkpoints/omni_lora_propkeep.pt
"""
import os, sys, time, math, json, random
import numpy as np
import torch
import torch.nn.functional as F

os.environ['HSA_OVERRIDE_GFX_VERSION'] = '12.0.0'
os.environ['CUDA_VISIBLE_DEVICES'] = '0'
os.environ['PYTORCH_CUDA_ALLOC_CONF'] = 'expandable_segments:True'

sys.path.insert(0, '/home/zixen15/omni-mamba-brain/src')
from omni_mamba import OmniMamba, OmniMambaConfig
from omni_mamba_v2_stable import inject_lora

BASE = "/home/zixen15/omni-mamba-brain"
PROPKEEP = "/home/zixen15/propkeep"
CKPT = os.path.join(BASE, "checkpoints/omni_v1_gpu_best.pt")

_log = lambda level, msg: sys.stderr.write(f"[PROPKEEP_TRAIN] [{level}] {msg}\n")

# ============================================================
# 1. LOAD TRAINING DATA
# ============================================================

def load_training_data():
    """Load all propkeep data and format as text for training."""
    texts = []
    
    # Load Q&A pairs (primary training data)
    qa_file = os.path.join(PROPKEEP, "data/processed/qa_pairs/propkeep_qa.jsonl")
    with open(qa_file) as f:
        for line in f:
            qa = json.loads(line)
            # Format as instruction-response
            text = f"Q: {qa['question']}\nA: {qa['answer']}"
            texts.append(text.encode('utf-8'))
    
    # Load federal facts
    facts_file = os.path.join(PROPKEEP, "data/processed/qa_pairs/propkeep_facts.jsonl")
    with open(facts_file) as f:
        for line in f:
            fact = json.loads(line)
            text = f"FACT: {fact['source']} {fact['relation']} {fact['target']}"
            texts.append(text.encode('utf-8'))
    
    # Load state facts
    state_file = os.path.join(PROPKEEP, "data/processed/qa_pairs/propkeep_state_facts.jsonl")
    with open(state_file) as f:
        for line in f:
            fact = json.loads(line)
            text = f"FACT: In {fact['source']}, {fact['relation']} is {fact['target']}"
            texts.append(text.encode('utf-8'))
    
    # Load scenarios
    scenarios_file = os.path.join(PROPKEEP, "data/processed/scenarios/propkeep_scenarios.jsonl")
    with open(scenarios_file) as f:
        for line in f:
            scenario = json.loads(line)
            text = f"SCENARIO: {scenario['scenario']}\nCORRECT ACTION: {scenario['correct_action']}\nMISTAKE: {scenario['common_mistake']}\nPENALTY: {scenario['penalty_if_wrong']}"
            texts.append(text.encode('utf-8'))
    
    _log("INFO", f"Loaded {len(texts)} training texts")
    return texts

# ============================================================
# 2. TRAINING
# ============================================================

def train_propkeep_brain():
    """Train the PROPKEEP LoRA adapter."""
    
    # Load base model
    _log("INFO", "Loading base model...")
    ckpt = torch.load(CKPT, map_location='cuda:0', weights_only=False)
    config = OmniMambaConfig(**ckpt['config'])
    base_state = ckpt['model']
    
    model = OmniMamba(config).to('cuda:0')
    model.load_state_dict(base_state)
    
    # Freeze base, inject LoRA
    for p in model.parameters():
        p.requires_grad = False
    
    lora_params = inject_lora(model, rank=4, alpha=16)
    for p in lora_params:
        p.data = p.data.to('cuda:0')
        p.requires_grad = True
    
    total, trainable = model.count_parameters()
    _log("INFO", f"LoRA: {trainable:,} trainable ({trainable/total*100:.2f}%)")
    
    # Load training data
    texts = load_training_data()
    
    # Convert texts to byte arrays for training
    all_data = b'\n\n'.join(texts)
    data_bytes = np.frombuffer(all_data, dtype=np.uint8)
    _log("INFO", f"Training data: {len(data_bytes)/1e6:.2f}MB from {len(texts)} items")
    
    # Training config
    STEPS = 3000
    LR = 3e-3
    BS = 4
    SL = 128  # sequence length
    
    def lr_ratio(step):
        if step < 50:
            return step / 50
        return max(0.01, 0.5 * (1 + math.cos(math.pi * (step - 50) / max(1, STEPS - 50))))
    
    optimizer = torch.optim.AdamW(
        [p for p in model.parameters() if p.requires_grad],
        lr=LR, weight_decay=0.01, betas=(0.9, 0.95), fused=True
    )
    scheduler = torch.optim.lr_scheduler.LambdaLR(optimizer, lr_ratio)
    
    def get_batch(bs, sl):
        """Get a batch of sequences from the training data."""
        xs, ys = [], []
        for _ in range(bs):
            i = np.random.randint(0, max(1, len(data_bytes) - sl - 1))
            xs.append(data_bytes[i:i+sl])
            ys.append(data_bytes[i+1:i+sl+1])
        return (
            torch.from_numpy(np.stack(xs).copy()).long().to('cuda:0'),
            torch.from_numpy(np.stack(ys).copy()).long().to('cuda:0'),
        )
    
    # Train
    model.train()
    t0 = time.time()
    best_ce = 999
    best_lora = None
    nan_count = 0
    
    _log("INFO", f"Starting PROPKEEP brain training: {STEPS} steps, lr={LR}")
    
    for step in range(1, STEPS + 1):
        x, y = get_batch(BS, SL)
        logits, jepa = model(x)
        ce = F.cross_entropy(logits.reshape(-1, 256), y.reshape(-1))
        loss = ce + 0.1 * jepa
        
        if torch.isnan(loss) or torch.isinf(loss):
            optimizer.zero_grad()
            nan_count += 1
            if nan_count > 100:
                _log("ERROR", f"Too many NaN ({nan_count}), stopping")
                break
            continue
        
        optimizer.zero_grad()
        loss.backward()
        torch.nn.utils.clip_grad_norm_(
            [p for p in model.parameters() if p.requires_grad], 0.5
        )
        optimizer.step()
        scheduler.step()
        
        if ce.item() < best_ce:
            best_ce = ce.item()
            best_lora = {
                n: p.data.clone()
                for n, p in model.named_parameters()
                if p.requires_grad and 'lora' in n.lower()
            }
        
        if step % 100 == 0:
            el = time.time() - t0
            sps = step / el
            eta = (STEPS - step) / sps / 60
            lr_now = optimizer.param_groups[0]['lr']
            _log("INFO", f"  s{step:>4} | ce={ce.item():.4f} best={best_ce:.4f} | "
                  f"lr={lr_now:.1e} | {sps:.1f}st/s | eta={eta:.0f}m | nan={nan_count}")
            
            # Save checkpoint every 500 steps
            if step % 500 == 0 and best_lora:
                save_path = os.path.join(PROPKEEP, f"checkpoints/omni_lora_propkeep_s{step}.pt")
                torch.save({
                    'lora_state': best_lora,
                    'config': config.__dict__,
                    'base_checkpoint': 'omni_v1_gpu_best.pt',
                    'rank': 4, 'alpha': 16,
                    'steps': step,
                    'best_ce': best_ce,
                    'trained_on': 'propkeep_property_management_law',
                    'training_items': len(texts),
                }, save_path)
                _log("INFO", f"  Checkpoint saved: {save_path}")
    
    # Final save
    if best_lora:
        save_path = os.path.join(PROPKEEP, "checkpoints/omni_lora_propkeep.pt")
        torch.save({
            'lora_state': best_lora,
            'config': config.__dict__,
            'base_checkpoint': 'omni_v1_gpu_best.pt',
            'rank': 4, 'alpha': 16,
            'steps': STEPS,
            'best_ce': best_ce,
            'trained_on': 'propkeep_property_management_law',
            'training_items': len(texts),
        }, save_path)
        _log("INFO", f"Final checkpoint saved: {save_path}")
    
    # ============================================================
    # 3. TEST THE BRAIN
    # ============================================================
    
    _log("INFO", "Testing PROPKEEP brain...")
    model.eval()
    
    test_questions = [
        b"Q: How much can I charge for a security deposit in California?",
        b"Q: Can I refuse to rent to someone with children?",
        b"Q: Do I have to allow emotional support animals?",
        b"Q: What are the lead paint disclosure requirements?",
        b"Q: How long do I have to return a security deposit in Texas?",
        b"Q: Can I change the locks if a tenant hasn't paid rent?",
        b"Q: What is the eviction process in Florida?",
        b"Q: Does New York have rent control?",
    ]
    
    print("\n" + "="*60)
    print("PROPKEEP BRAIN TEST RESULTS")
    print("="*60)
    
    for q in test_questions:
        ids = torch.tensor([[b for b in q]], device='cuda:0')
        with torch.no_grad():
            for _ in range(100):
                logits, _ = model(ids[:, -256:])
                nid = logits[0, -1, :].argmax().item()
                if nid == 0 or nid == 10:  # null or newline
                    break
                ids = torch.cat([ids, torch.tensor([[nid]], device='cuda:0')], dim=1)
        
        result = bytes(ids[0].cpu().tolist()).decode('utf-8', errors='replace')
        new_text = result[len(q.decode()):]
        print(f"\n  Q: {q.decode()[3:]}")
        print(f"  A: {new_text[:200]}")
    
    el = time.time() - t0
    _log("INFO", f"Done in {el/60:.1f}m | best ce={best_ce:.4f}")

if __name__ == '__main__':
    train_propkeep_brain()