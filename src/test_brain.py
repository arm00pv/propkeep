import os, sys, torch
os.environ['HSA_OVERRIDE_GFX_VERSION'] = '12.0.0'
os.environ['CUDA_VISIBLE_DEVICES'] = '0'
os.environ['PYTORCH_CUDA_ALLOC_CONF'] = 'expandable_segments:True'

sys.path.insert(0, '/home/zixen15/omni-mamba-brain/src')
from omni_mamba import OmniMamba, OmniMambaConfig

BASE = '/home/zixen15/omni-mamba-brain'
PROPKEEP = '/home/zixen15/propkeep'

print("Loading model...", flush=True)
ckpt = torch.load(os.path.join(BASE, 'checkpoints/omni_v1_gpu_best.pt'), map_location='cuda:0', weights_only=False)
config = OmniMambaConfig(**ckpt['config'])
model = OmniMamba(config).to('cuda:0')
model.load_state_dict(ckpt['model'])

lora_ckpt = torch.load(os.path.join(PROPKEEP, 'checkpoints/omni_lora_propkeep.pt'), map_location='cuda:0', weights_only=False)
lora_state = lora_ckpt['lora_state']
with torch.no_grad():
    for name, param in model.named_parameters():
        if name in lora_state:
            param.data.copy_(lora_state[name])

print(f"PROPKEEP brain loaded (ce={lora_ckpt['best_ce']:.4f}, steps={lora_ckpt['steps']})", flush=True)
model.eval()

test_questions = [
    b"Q: How much can I charge for a security deposit in California?",
    b"Q: Can I refuse to rent to someone with children?",
    b"Q: Do I have to allow emotional support animals if I have a no-pet policy?",
    b"Q: What are the lead paint disclosure requirements?",
    b"Q: How long do I have to return a security deposit in Texas?",
    b"Q: Can I change the locks if a tenant hasn't paid rent?",
    b"Q: What is the implied warranty of habitability?",
    b"Q: Can I enter the rental unit without notice?",
]

print("=" * 70, flush=True)
print("PROPKEEP BRAIN TEST RESULTS", flush=True)
print("=" * 70, flush=True)

for q in test_questions:
    ids = torch.tensor([[b for b in q]], device='cuda:0')
    with torch.no_grad():
        for _ in range(150):
            logits, _ = model(ids[:, -256:])
            nid = logits[0, -1, :].argmax().item()
            if nid == 0:
                break
            ids = torch.cat([ids, torch.tensor([[nid]], device='cuda:0')], dim=1)
    
    result = bytes(ids[0].cpu().tolist()).decode('utf-8', errors='replace')
    new_text = result[len(q.decode()):].strip()
    print(f"\n  {q.decode()}", flush=True)
    print(f"  -> {new_text[:250]}", flush=True)
