#!/usr/bin/env python3
"""
PROPKEEP Data Builder — Generates training data for the Property Management Compliance Brain
============================================================================================

Creates a comprehensive training dataset from federal and state landlord-tenant law.
All data is public/legal — no copyrighted material.

Output format: JSON lines with Q&A pairs, compliance scenarios, and legal facts.
This will be used to:
  1. Train the Mamba-3 LoRA adapter (domain-specific knowledge)
  2. Populate ALEPH knowledge graph (for RAG retrieval)
  3. Create Conscience verified claims (anti-hallucination)
"""
import os, json, time

DATA_DIR = "/home/zixen15/propkeep/data"
OUTPUT_QA = os.path.join(DATA_DIR, "processed/qa_pairs/propkeep_qa.jsonl")
OUTPUT_FACTS = os.path.join(DATA_DIR, "processed/qa_pairs/propkeep_facts.jsonl")
OUTPUT_SCENARIOS = os.path.join(DATA_DIR, "processed/scenarios/propkeep_scenarios.jsonl")

os.makedirs(os.path.dirname(OUTPUT_QA), exist_ok=True)

# ============================================================
# 1. FEDERAL LAW FACTS
# ============================================================

FEDERAL_FACTS = [
    # Fair Housing Act
    {"source": "Fair Housing Act", "relation": "prohibits_discrimination_based_on", "target": "race, color, religion, sex, disability, familial status, national origin", "domain": "propkeep_federal", "confidence": 1.0},
    {"source": "Fair Housing Act", "relation": "protected_classes", "target": "7 classes: race, color, religion, sex, disability, familial status, national origin", "domain": "propkeep_federal", "confidence": 1.0},
    {"source": "Fair Housing Act", "relation": "applies_to", "target": "all rental housing, sales, advertising, and financing", "domain": "propkeep_federal", "confidence": 1.0},
    {"source": "Fair Housing Act", "relation": "exemption", "target": "owner-occupied buildings with 4 or fewer units (Mrs. Murphy exemption)", "domain": "propkeep_federal", "confidence": 0.9},
    {"source": "Fair Housing Act", "relation": "penalty", "target": "civil penalties up to $16,000 for first violation, $65,000 for subsequent", "domain": "propkeep_federal", "confidence": 0.95},
    {"source": "familial status", "relation": "means", "target": "households with children under 18, pregnant women, or those seeking custody", "domain": "propkeep_federal", "confidence": 1.0},
    {"source": "disability", "relation": "requires", "target": "reasonable accommodations and modifications at landlord expense for common areas, tenant expense for interior", "domain": "propkeep_federal", "confidence": 0.9},
    {"source": "assistance animals", "relation": "not_pet", "target": "emotional support and service animals are not pets under FHA, no pet fees allowed", "domain": "propkeep_federal", "confidence": 0.95},
    
    # ADA
    {"source": "Americans with Disabilities Act", "relation": "applies_to", "target": "public accommodations and commercial facilities, NOT private residential rentals", "domain": "propkeep_federal", "confidence": 0.9},
    {"source": "ADA", "relation": "rental_application_exception", "target": "applies to rental offices and common areas open to public, not individual units", "domain": "propkeep_federal", "confidence": 0.85},
    
    # Lead Paint Disclosure
    {"source": "Lead-Based Paint Hazard Reduction Act", "relation": "requires", "target": "landlords must disclose known lead-based paint for buildings built before 1978", "domain": "propkeep_federal", "confidence": 1.0},
    {"source": "Lead-Based Paint Hazard Reduction Act", "relation": "requires_form", "target": "EPA disclosure form must be signed by tenant before lease signing", "domain": "propkeep_federal", "confidence": 1.0},
    {"source": "Lead-Based Paint Hazard Reduction Act", "relation": "requires_pamphlet", "target": "EPA pamphlet 'Protect Your Family from Lead in Your Home' must be provided", "domain": "propkeep_federal", "confidence": 1.0},
    {"source": "Lead-Based Paint Hazard Reduction Act", "relation": "penalty", "target": "up to $16,000 per violation per day for non-disclosure", "domain": "propkeep_federal", "confidence": 0.9},
    {"source": "Lead-Based Paint Hazard Reduction Act", "relation": "exemption", "target": "buildings built after 1977 are exempt from lead paint disclosure requirements", "domain": "propkeep_federal", "confidence": 1.0},
    
    # HUD / Security Deposits (federal guidelines, state-specific)
    {"source": "HUD", "relation": "security_deposit_guideline", "target": "no federal limit on security deposit amount, states set their own limits", "domain": "propkeep_federal", "confidence": 0.9},
    {"source": "HUD", "relation": "habitability_standard", "target": "landlords must maintain rental units in habitable condition regardless of lease terms", "domain": "propkeep_federal", "confidence": 0.95},
    {"source": "implied warranty of habitability", "relation": "requires", "target": "working plumbing, heating, electrical, safe structure, hot water, trash receptacles", "domain": "propkeep_federal", "confidence": 0.9},
    
    # Eviction (federal due process)
    {"source": "federal eviction law", "relation": "requires", "target": "proper written notice before eviction, court process required for removal", "domain": "propkeep_federal", "confidence": 1.0},
    {"source": "federal eviction law", "relation": "prohibits", "target": "self-help evictions (changing locks, removing belongings, shutting off utilities)", "domain": "propkeep_federal", "confidence": 1.0},
    {"source": "self-help eviction", "relation": "penalty", "target": "tenant can sue for actual damages plus punitive damages in most states", "domain": "propkeep_federal", "confidence": 0.85},
    
    # Fair Credit Reporting Act (tenant screening)
    {"source": "Fair Credit Reporting Act", "relation": "requires", "target": "landlord must get written consent before pulling tenant credit report", "domain": "propkeep_federal", "confidence": 1.0},
    {"source": "FCRA", "relation": "adverse_action", "target": "if denied based on credit report, landlord must provide adverse action notice with report source", "domain": "propkeep_federal", "confidence": 0.95},
    {"source": "FCRA", "relation": "retention", "target": "tenant screening reports must be retained for minimum 5 years from date of report", "domain": "propkeep_federal", "confidence": 0.9},
]

# ============================================================
# 2. STATE LAW FACTS (All 50 states — key compliance points)
# ============================================================

# Format: [state, security_deposit_limit, deposit_return_deadline_days, 
#          notice_to_vacate_days, rent_grace_period, late_fee_rules, 
#          eviction_process_days, rent_control]

STATE_DATA = [
    ["Alabama", "1 month rent", "35", "30", "none", "no statutory cap", "10", "none"],
    ["Alaska", "2 months rent (no children), 1 month (with children under 18)", "14", "30", "none", "no statutory cap", "10", "none"],
    ["Arizona", "1.5 months rent", "14", "30", "5 days", "reasonable, no cap", "5", "none"],
    ["Arkansas", "2 months rent", "60", "30", "none", "no statutory cap", "10", "none"],
    ["California", "2 months rent (unfurnished), 3 months (furnished), 1 month if 2+ years", "21", "30/60", "none", "no statutory cap", "3", "yes (15+ cities)"],
    ["Colorado", "2 months rent (maximum)", "30/60", "21", "none", "no statutory cap, must be in lease", "10", "none"],
    ["Connecticut", "2 months rent (tenants 65+ limited to 1 month)", "30", "30", "9 days", "no statutory cap", "15", "limited"],
    ["Delaware", "1 month rent", "20", "60", "none", "no statutory cap", "7", "none"],
    ["Florida", "1 month rent (no pet/no water furniture), more with conditions", "15/30/45", "30/60", "none", "no statutory cap, 5% of rent typical", "3", "none"],
    ["Georgia", "no statutory limit", "30", "30/60", "none", "no statutory cap, 10% typical", "7", "none"],
    ["Hawaii", "1 month rent", "14", "28/45", "none", "no statutory cap", "10", "none"],
    ["Idaho", "no statutory limit", "21", "30", "none", "no statutory cap", "3", "none"],
    ["Illinois", "no statutory limit", "30/45", "30/60", "5 days", "no statutory cap, $10/day typical", "5", "limited (Evanston)"],
    ["Indiana", "no statutory limit", "45", "30/60", "none", "no statutory cap", "10", "none"],
    ["Iowa", "2 months rent", "30", "30", "3 days", "no statutory cap, $10/day typical", "3", "none"],
    ["Kansas", "1 month rent (unfurnished), 1.5 months (furnished)", "30", "30/60", "none", "no statutory cap", "14", "none"],
    ["Kentucky", "no statutory limit", "30/60", "30", "none", "no statutory cap", "7", "none"],
    ["Louisiana", "no statutory limit", "30", "30/60", "5 days", "no statutory cap", "5", "none"],
    ["Maine", "2 months rent", "21", "30/90", "none", "no statutory cap, must be reasonable", "7", "limited"],
    ["Maryland", "1-2 months rent based on county", "45", "30/60", "none", "5% of monthly rent cap", "7", "yes (some counties)"],
    ["Massachusetts", "1 month rent", "30", "30/90 (week-to-week 7 or 30)", "none", "no statutory cap", "14", "yes (some cities)"],
    ["Michigan", "1.5 months rent", "30", "30/60", "none", "no statutory cap, 5% typical", "7", "none"],
    ["Minnesota", "no statutory limit generally", "21", "30/60", "none", "no statutory cap, $50 typical", "7", "limited"],
    ["Mississippi", "no statutory limit", "45", "30/60", "none", "no statutory cap", "3", "none"],
    ["Missouri", "2 months rent", "30", "30/60", "none", "no statutory cap, $5/day typical", "10", "none"],
    ["Montana", "1 month rent", "30", "30", "none", "no statutory cap, must be reasonable", "3", "none"],
    ["Nebraska", "1 month rent (unfurnished), 2 months (furnished)", "14", "30/60", "none (some cities 3 days)", "no statutory cap", "7", "none"],
    ["Nevada", "3 months rent", "30", "30/60", "none", "no statutory cap, $5/day typical", "5", "none"],
    ["New Hampshire", "1 month rent (or 1.5 with pets/furniture)", "30", "30/60", "none", "no statutory cap, must be reasonable", "7", "limited"],
    ["New Jersey", "1.5 months rent (up to 2.5 with conditions)", "30", "30/60", "5 days", "no statutory cap", "3", "yes (statewide)"],
    ["New Mexico", "1 month rent (no pet/furniture), 2 months with", "30", "30", "none", "no statutory cap", "7", "none"],
    ["New York", "1 month rent (up to 2 months for furnished)", "14/30/60", "30/60/90", "5 days", "no statutory cap", "14", "yes (statewide stabilized)"],
    ["North Carolina", "1.5 months rent (2 months if week-to-week)", "30", "30/60", "none", "no statutory cap, $5/day typical", "10", "none"],
    ["North Dakota", "1 month rent (or 2 with conditions)", "30", "30/60", "none", "no statutory cap, $25/day cap", "3", "none"],
    ["Ohio", "no statutory limit", "30", "30", "none", "no statutory cap", "3", "none"],
    ["Oklahoma", "no statutory limit", "30", "30/60", "none", "no statutory cap, $5/day typical", "5", "none"],
    ["Oregon", "1 month rent (1.5 with conditions)", "31", "30/60/90", "none", "no statutory cap, must be reasonable", "7", "yes (statewide)"],
    ["Pennsylvania", "2 months rent (first year), 1 month after", "30/60", "30/90", "none", "no statutory cap, must be reasonable", "10", "none"],
    ["Rhode Island", "1 month rent", "20", "30/60", "9 days", "no statutory cap", "5", "none"],
    ["South Carolina", "no statutory limit", "30", "30/60", "5 days", "no statutory cap, 5% of rent typical", "5", "none"],
    ["South Dakota", "1 month rent (or 2 with conditions)", "14/30", "30/60", "3 days", "no statutory cap, $25/day cap", "3", "none"],
    ["Tennessee", "no statutory limit", "30", "30/60", "none", "no statutory cap, 10% typical", "10", "none"],
    ["Texas", "no statutory limit generally", "30", "30/60", "none", "no statutory cap, 12% of rent typical", "3", "none"],
    ["Utah", "no statutory limit", "30", "30/60", "none", "no statutory cap, $50 typical", "3", "none"],
    ["Vermont", "no statutory limit (first month typical)", "14", "30/60/90", "none", "no statutory cap, must be reasonable", "14", "yes (Burlington)"],
    ["Virginia", "2 months rent", "45", "30/60", "5 days", "no statutory cap, 10% typical", "5", "none"],
    ["Washington", "1 month rent (unfurnished), 3 months (furnished)", "21", "20/30/60/90", "none", "no statutory cap, must be reasonable", "3", "limited (Seattle)"],
    ["West Virginia", "no statutory limit", "30/45", "30/60", "none", "no statutory cap", "10", "none"],
    ["Wisconsin", "no statutory limit generally", "21", "28/60/90", "none", "no statutory cap, $5/day typical", "5", "none"],
    ["Wyoming", "no statutory limit", "30/60", "30", "none", "no statutory cap", "3", "none"],
    ["Washington DC", "1 month rent", "45", "30/90", "none", "no statutory cap, 10% typical", "7", "yes (limited)"],
    ["Puerto Rico", "2 months rent (unfurnished), 3 months (furnished)", "30", "30/60", "none", "no statutory cap, must be reasonable", "5", "limited (rent stabilization in some municipalities)"],
]

# ============================================================
# 3. Q&A PAIRS — Common landlord questions with expert answers
# ============================================================

# Generate Q&A pairs from state data
QA_PAIRS = []

for state_data in STATE_DATA:
    state, deposit_limit, return_days, notice_days, grace, late_fee, eviction_days, rent_control = state_data
    
    # Security deposit Q&A
    QA_PAIRS.append({
        "question": f"How much can I charge for a security deposit in {state}?",
        "answer": f"In {state}, the maximum security deposit is {deposit_limit}. This is set by state law and cannot be exceeded. Make sure to document the condition of the unit at move-in with photos and a written inspection to avoid disputes at move-out.",
        "domain": "propkeep_state",
        "state": state,
        "topic": "security_deposit",
        "confidence": 0.95,
    })
    
    # Deposit return Q&A
    QA_PAIRS.append({
        "question": f"How long do I have to return a security deposit in {state}?",
        "answer": f"In {state}, you must return the security deposit within {return_days} days of the tenant moving out. If you deduct anything, you must provide an itemized list of deductions with receipts. Failing to return the deposit on time can result in penalties including owing the tenant multiple times the deposit amount.",
        "domain": "propkeep_state",
        "state": state,
        "topic": "security_deposit",
        "confidence": 0.95,
    })
    
    # Notice to vacate Q&A
    QA_PAIRS.append({
        "question": f"How much notice must I give a tenant to vacate in {state}?",
        "answer": f"In {state}, the required notice to vacate is typically {notice_days} days. The exact requirement depends on the lease type (month-to-month vs fixed term) and whether the eviction is for non-payment, lease violation, or no-cause. Always check your specific lease terms and local ordinances which may require longer notice.",
        "domain": "propkeep_state",
        "state": state,
        "topic": "notice_eviction",
        "confidence": 0.9,
    })
    
    # Eviction process Q&A
    QA_PAIRS.append({
        "question": f"What is the eviction process timeline in {state}?",
        "answer": f"In {state}, the eviction process typically starts with a {eviction_days}-day notice to pay or quit for non-payment of rent. If the tenant doesn't comply, you must file an unlawful detainer lawsuit in court. You cannot use self-help measures like changing locks or shutting off utilities — this is illegal and can result in significant penalties. The entire process from notice to physical removal typically takes 3-8 weeks depending on court backlog.",
        "domain": "propkeep_state",
        "state": state,
        "topic": "eviction",
        "confidence": 0.9,
    })
    
    # Late fee Q&A
    QA_PAIRS.append({
        "question": f"Can I charge late fees in {state} and how much?",
        "answer": f"In {state}, late fees are {late_fee}. The grace period before late fees can be applied is {grace if grace != 'none' else 'not required by state law, but many leases specify 3-5 days'}. Late fees must be reasonable and proportional to the rent amount. Some states require the fee to be specified in the lease agreement. Excessive late fees may be unenforceable in court.",
        "domain": "propkeep_state",
        "state": state,
        "topic": "late_fees",
        "confidence": 0.85,
    })
    
    # Rent control Q&A
    if rent_control != "none":
        QA_PAIRS.append({
            "question": f"Does {state} have rent control?",
            "answer": f"Yes, {state} has rent control: {rent_control}. This means rent increases may be limited by local ordinance. You must check with your specific city or county for rent increase caps, registration requirements, and just-cause eviction rules. Violating rent control ordinances can result in fines and tenant lawsuits.",
            "domain": "propkeep_state",
            "state": state,
            "topic": "rent_control",
            "confidence": 0.9,
        })
    else:
        QA_PAIRS.append({
            "question": f"Does {state} have rent control?",
            "answer": f"No, {state} does not have statewide rent control. However, some cities or counties may have local rent stabilization ordinances. You should check your specific jurisdiction. Without rent control, you can generally set rent at market rate, but must provide proper notice (typically 30-60 days) before increasing rent.",
            "domain": "propkeep_state",
            "state": state,
            "topic": "rent_control",
            "confidence": 0.9,
        })

# Add federal Q&A pairs
QA_PAIRS.extend([
    {
        "question": "Can I refuse to rent to someone with children?",
        "answer": "No. Under the Fair Housing Act, familial status (having children under 18, being pregnant, or seeking custody) is a protected class. Refusing to rent to families with children is illegal discrimination, with penalties up to $16,000 for a first violation. The only exception is housing specifically designated for seniors under strict HUD guidelines (62+ or 55+ communities meeting specific requirements).",
        "domain": "propkeep_federal",
        "state": "federal",
        "topic": "fair_housing",
        "confidence": 1.0,
    },
    {
        "question": "Can I ask about a tenant's immigration status?",
        "answer": "Under the Fair Housing Act, national origin is a protected class. While you can verify identity and right to occupy, asking specifically about immigration status or requiring documents beyond standard ID may constitute discrimination based on national origin. HUD has guidance that housing providers should not use immigration status as a pretext for discrimination. Consult a fair housing attorney before implementing any immigration-related screening.",
        "domain": "propkeep_federal",
        "state": "federal",
        "topic": "fair_housing",
        "confidence": 0.85,
    },
    {
        "question": "Do I have to allow emotional support animals if I have a no-pet policy?",
        "answer": "Yes. Under the Fair Housing Act, emotional support animals (ESAs) and service animals are considered reasonable accommodations for tenants with disabilities, not pets. You cannot charge pet rent, pet deposits, or pet fees for ESAs. You can request documentation of the disability-related need from a healthcare professional. You can only deny if the animal poses a direct threat to others or would cause substantial property damage. Breed restrictions do not apply to ESAs.",
        "domain": "propkeep_federal",
        "state": "federal",
        "topic": "fair_housing",
        "confidence": 0.95,
    },
    {
        "question": "What are the lead paint disclosure requirements?",
        "answer": "For any residential property built before 1978, federal law requires: 1) Disclosure of any known lead-based paint hazards, 2) Providing the EPA pamphlet 'Protect Your Family from Lead in Your Home', 3) Including a lead warning statement in the lease, 4) Keeping disclosure records for 3 years. Violations can result in penalties of up to $16,000 per day per violation. Properties built 1978 or later are exempt. This applies to ALL landlords regardless of property size.",
        "domain": "propkeep_federal",
        "state": "federal",
        "topic": "lead_paint",
        "confidence": 1.0,
    },
    {
        "question": "Can I do a 'self-help eviction' by changing the locks?",
        "answer": "Absolutely not. Self-help evictions (changing locks, removing belongings, shutting off utilities, removing doors) are illegal in all 50 states. You must go through the court process: 1) Serve proper written notice, 2) File unlawful detainer if tenant doesn't comply, 3) Get a court judgment, 4) Have a sheriff/marshal physically remove the tenant. Self-help evictions can result in the tenant suing you for actual damages, punitive damages, and attorney fees. In some states, penalties are 2-3x the monthly rent.",
        "domain": "propkeep_federal",
        "state": "federal",
        "topic": "eviction",
        "confidence": 1.0,
    },
    {
        "question": "What is the implied warranty of habitability?",
        "answer": "The implied warranty of habitability is a legal doctrine requiring landlords to maintain rental units in a condition fit for human habitation. This includes: working plumbing, heating, electrical systems, safe structure, hot water, trash receptacles, smoke detectors, and freedom from pest infestations. This cannot be waived by lease terms — even if the tenant signed a lease saying they accept the unit 'as-is.' If the landlord fails to maintain habitability, the tenant may withhold rent, repair and deduct, or break the lease without penalty (remedies vary by state).",
        "domain": "propkeep_federal",
        "state": "federal",
        "topic": "habitability",
        "confidence": 0.95,
    },
    {
        "question": "Do I need to provide receipts for security deposit deductions?",
        "answer": "Yes, in almost all states. When deducting from a security deposit, you must provide an itemized list of deductions with supporting documentation (receipts, invoices, photos). 'Normal wear and tear' cannot be charged to the tenant — only damage beyond normal use. Common mistakes: charging for painting after 2-3 years (considered normal wear), charging for carpet cleaning (normal wear unless stained/damaged), not providing receipts, or missing the deadline to return the deposit. Many states penalize landlords 2-3x the deposit amount for failing to return it with itemization on time.",
        "domain": "propkeep_federal",
        "state": "federal",
        "topic": "security_deposit",
        "confidence": 0.95,
    },
    {
        "question": "Can I enter the rental unit without notice?",
        "answer": "No. In all 50 states, landlords must provide reasonable notice before entering a rental unit (typically 24-48 hours, except in emergencies like fire, flood, or gas leak). Entry without notice is considered a violation of the tenant's right to quiet enjoyment and can result in the tenant suing for damages or breaking the lease. The notice must state the date, time, and purpose of entry. Some states require specific notice periods for different purposes (e.g., 24 hours for repairs, 48 hours for showings).",
        "domain": "propkeep_federal",
        "state": "federal",
        "topic": "right_to_entry",
        "confidence": 0.95,
    },
    {
        "question": "What should I include in a rental lease agreement?",
        "answer": "A comprehensive lease should include: 1) Parties' names and contact info, 2) Property address, 3) Lease term (start/end dates or month-to-month), 4) Rent amount, due date, and late fee terms, 5) Security deposit amount and terms, 6) Utilities responsibility (who pays what), 7) Pet policy, 8) Maintenance responsibilities, 9) Entry notice requirements, 10) Subletting policy, 11) Lead paint disclosure (pre-1978), 12) Smoking policy, 13) Occupancy limits, 14) Lead-based paint disclosure form, 15) Move-in inspection checklist. State-specific addenda may be required.",
        "domain": "propkeep_general",
        "state": "general",
        "topic": "lease_agreement",
        "confidence": 0.9,
    },
    {
        "question": "How do I properly screen a tenant?",
        "answer": "Legal tenant screening includes: 1) Written application with consent for background/credit check (required by FCRA), 2) Credit report pull (must have written consent), 3) Income verification (typically 2.5-3x monthly rent), 4) Rental history verification (contact previous landlords), 5) Criminal background check (be careful — some states/cities ban criminal history screening or limit what you can consider), 6) Employment verification. You must apply screening criteria consistently to all applicants. If you deny based on credit report, you must provide an adverse action notice. Keep all screening records for 5 years (FCRA requirement). Never discriminate based on protected classes.",
        "domain": "propkeep_federal",
        "state": "federal",
        "topic": "tenant_screening",
        "confidence": 0.9,
    },
])

# ============================================================
# 4. COMPLIANCE SCENARIOS
# ============================================================

SCENARIOS = [
    {
        "scenario": "A tenant requests an emotional support dog but my lease says no pets",
        "state": "all",
        "correct_action": "You must allow the ESA as a reasonable accommodation under the Fair Housing Act. Request a letter from a healthcare professional verifying the disability-related need. You cannot charge pet rent or pet deposit. You CAN require the tenant to clean up after the animal and can deny if the animal poses a direct threat or would cause substantial damage.",
        "common_mistake": "Denying the request or charging pet fees — this is FHA discrimination",
        "penalty_if_wrong": "Up to $16,000 first violation, $65,000 subsequent violations, plus tenant lawsuit damages",
        "domain": "propkeep_scenario",
    },
    {
        "scenario": "Tenant hasn't paid rent for 15 days, I want to change the locks",
        "state": "all",
        "correct_action": "Do NOT change the locks. This is an illegal self-help eviction. Serve the proper notice to pay or quit (check your state's required notice period — typically 3-14 days). If tenant doesn't pay within the notice period, file an unlawful detainer in court. Only a sheriff/marshal can physically remove a tenant after a court order.",
        "common_mistake": "Self-help eviction (changing locks, shutting off utilities, removing belongings) — illegal in all 50 states",
        "penalty_if_wrong": "Tenant can sue for actual damages, punitive damages, and attorney fees. Some states impose penalties of 2-3x monthly rent.",
        "domain": "propkeep_scenario",
    },
    {
        "scenario": "I'm renting a unit built in 1965 and didn't disclose lead paint",
        "state": "all",
        "correct_action": "Immediately provide the EPA disclosure form and pamphlet to current tenants. Going forward, always provide lead paint disclosure before lease signing for any property built before 1978. Keep records of disclosure for 3 years minimum.",
        "common_mistake": "Not providing lead paint disclosure for pre-1978 properties",
        "penalty_if_wrong": "Up to $16,000 per violation per day. Federal EPA enforcement.",
        "domain": "propkeep_scenario",
    },
    {
        "scenario": "Tenant is asking for a wheelchair ramp to the front entrance",
        "state": "all",
        "correct_action": "Under the Fair Housing Act, this is a reasonable modification request for a disability. The TENANT is generally responsible for paying for modifications inside the unit. For common area modifications (like a ramp to the entrance), the landlord must allow it and the tenant pays. You can require the tenant to restore the modification at move-out in some cases. You cannot deny without an individualized assessment of whether it's an undue financial/administrative burden.",
        "common_mistake": "Denying disability accommodation requests without individualized assessment",
        "penalty_if_wrong": "FHA discrimination penalty up to $16,000-$65,000 plus ADA-related damages",
        "domain": "propkeep_scenario",
    },
    {
        "scenario": "I want to raise rent by 20% for a month-to-month tenant",
        "state": "all",
        "correct_action": "Check if your state/city has rent control (if yes, increases may be capped). If no rent control: provide proper written notice (typically 30 days for increases under 10%, 60-90 days for increases over 10% in many states like California). The increase must take effect at the beginning of a rental period. Make sure the notice is delivered properly (certified mail, hand delivery, or as specified in lease).",
        "common_mistake": "Not providing adequate notice or exceeding rent control caps in regulated areas",
        "penalty_if_wrong": "In rent-controlled areas: fines, rent rollback, tenant lawsuit. In non-regulated areas: notice may be void, requiring you to start over.",
        "domain": "propkeep_scenario",
    },
    {
        "scenario": "Tenant moved out and left the unit damaged, I want to keep the entire deposit",
        "state": "all",
        "correct_action": "You can only deduct for damage BEYOND normal wear and tear. Document all damage with photos. Get repair estimates or receipts. Provide an itemized list of deductions within your state's deadline (14-60 days depending on state). Return the remaining deposit. Common mistake: charging for painting after 2+ years (normal wear) or carpet replacement without proof of damage beyond wear.",
        "common_mistake": "Keeping entire deposit without itemization, missing the return deadline, charging for normal wear and tear",
        "penalty_if_wrong": "Many states impose 2-3x penalty: if deposit is $2000 and you wrongfully keep it, you may owe $4000-$6000 plus attorney fees.",
        "domain": "propkeep_scenario",
    },
    {
        "scenario": "I want to show the unit to prospective tenants while current tenant still lives there",
        "state": "all",
        "correct_action": "Provide proper notice before each showing (typically 24 hours). Check your state's specific requirement — some require 24 hours, others 48. The lease may specify the notice period. You cannot enter without notice except in emergencies. You must show during reasonable hours (typically 9am-8pm). The tenant has the right to be present during the showing but cannot unreasonably refuse entry with proper notice.",
        "common_mistake": "Entering without notice, showing outside reasonable hours, or entering without a legitimate purpose",
        "penalty_if_wrong": "Tenant can sue for violation of quiet enjoyment, break the lease, or file for injunctive relief.",
        "domain": "propkeep_scenario",
    },
    {
        "scenario": "Tenant is running a business out of the rental unit",
        "state": "all",
        "correct_action": "Check your lease — most prohibit commercial activity. If the lease prohibits it, serve a notice to cure (violation notice). If the tenant doesn't stop, you can proceed with eviction for lease violation. However, be careful: some states protect home-based businesses that don't create nuisance or increased traffic. A tenant working from home on a laptop is generally acceptable; a tenant running a daycare or manufacturing is different. Consider whether the business creates nuisance, noise, or additional liability before acting.",
        "common_mistake": "Evicting without checking whether the state protects home-based businesses, or not having a lease clause prohibiting commercial use",
        "penalty_if_wrong": "Wrongful eviction lawsuit, especially if the activity is protected or the lease doesn't clearly prohibit it.",
        "domain": "propkeep_scenario",
    },
]

# ============================================================
# 5. WRITE ALL DATA TO FILES
# ============================================================

# Write federal facts
with open(OUTPUT_FACTS, 'w') as f:
    for fact in FEDERAL_FACTS:
        f.write(json.dumps(fact) + '\n')

# Write Q&A pairs
with open(OUTPUT_QA, 'w') as f:
    for qa in QA_PAIRS:
        f.write(json.dumps(qa) + '\n')

# Write scenarios
with open(OUTPUT_SCENARIOS, 'w') as f:
    for scenario in SCENARIOS:
        f.write(json.dumps(scenario) + '\n')

# Also write state data as facts
STATE_FACTS_FILE = os.path.join(DATA_DIR, "processed/qa_pairs/propkeep_state_facts.jsonl")
with open(STATE_FACTS_FILE, 'w') as f:
    for state_data in STATE_DATA:
        state, deposit_limit, return_days, notice_days, grace, late_fee, eviction_days, rent_control = state_data
        f.write(json.dumps({
            "source": state,
            "relation": "security_deposit_limit",
            "target": deposit_limit,
            "domain": "propkeep_state",
            "confidence": 0.95,
        }) + '\n')
        f.write(json.dumps({
            "source": state,
            "relation": "deposit_return_deadline_days",
            "target": return_days,
            "domain": "propkeep_state",
            "confidence": 0.95,
        }) + '\n')
        f.write(json.dumps({
            "source": state,
            "relation": "notice_to_vacate_days",
            "target": notice_days,
            "domain": "propkeep_state",
            "confidence": 0.9,
        }) + '\n')
        f.write(json.dumps({
            "source": state,
            "relation": "eviction_notice_days",
            "target": eviction_days,
            "domain": "propkeep_state",
            "confidence": 0.9,
        }) + '\n')
        f.write(json.dumps({
            "source": state,
            "relation": "rent_control",
            "target": rent_control,
            "domain": "propkeep_state",
            "confidence": 0.9,
        }) + '\n')

# Summary
print(f"╔══════════════════════════════════════════════════════════╗")
print(f"║  PROPKEEP DATA COLLECTION COMPLETE                        ║")
print(f"╚══════════════════════════════════════════════════════════╝")
print(f"")
print(f"  Federal facts:     {len(FEDERAL_FACTS)}")
print(f"  State facts:       {len(STATE_DATA) * 5} (5 per state × 50 states + DC)")
print(f"  Q&A pairs:         {len(QA_PAIRS)}")
print(f"  Scenarios:         {len(SCENARIOS)}")
print(f"")
print(f"  Total training items: {len(FEDERAL_FACTS) + len(STATE_DATA) * 5 + len(QA_PAIRS) + len(SCENARIOS)}")
print(f"")
print(f"Files created:")
print(f"  {OUTPUT_FACTS}")
print(f"  {OUTPUT_QA}")
print(f"  {OUTPUT_SCENARIOS}")
print(f"  {STATE_FACTS_FILE}")
print(f"")
print(f"Total data size: {os.path.getsize(OUTPUT_QA) + os.path.getsize(OUTPUT_FACTS) + os.path.getsize(OUTPUT_SCENARIOS) + os.path.getsize(STATE_FACTS_FILE)} bytes")