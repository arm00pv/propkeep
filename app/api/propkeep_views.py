"""
PROPKEEP API Views — Property Management Compliance Intelligence
=================================================================
REST API endpoints for the PROPKEEP brain.
"""
import json, os, sys, urllib.request
from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework.permissions import AllowAny

sys.path.insert(0, '/home/zixen15/propkeep/src')

_log = lambda msg: sys.stderr.write(f"[PROPKEEP_API] {msg}\n")

OLLAMA_URL = "http://localhost:11434"

# Lazy-load the brain
_brain = None

def get_brain():
    global _brain
    if _brain is None:
        from propkeep_brain import load_knowledge_base, detect_state, retrieve_context
        load_knowledge_base()
        _brain = True
    return _brain


class PropkeepAskView(APIView):
    """Ask the PROPKEEP brain a property management question."""
    permission_classes = [AllowAny]
    
    def post(self, request):
        from propkeep_brain import ask_propkeep
        question = request.data.get('question', '')
        state = request.data.get('state', None)
        model = request.data.get('model', 'qwen3.5:9b')
        
        if not question:
            return Response({'error': 'Question required'}, status=400)
        
        result = ask_propkeep(question, state=state, model=model)
        return Response(result)
    
    def get(self, request):
        """GET version for simple queries."""
        from propkeep_brain import ask_propkeep
        from urllib.parse import parse_qs
        question = request.GET.get('q', '')
        state = request.GET.get('state', None)
        
        if not question:
            return Response({'error': 'Use ?q=your question'}, status=400)
        
        result = ask_propkeep(question, state=state)
        return Response(result)


class PropkeepComplianceView(APIView):
    """Get quick compliance facts for a state."""
    permission_classes = [AllowAny]
    
    def get(self, request):
        from propkeep_brain import get_state_compliance
        state = request.GET.get('state', '')
        if not state:
            return Response({'error': 'Use ?state=California'}, status=400)
        result = get_state_compliance(state)
        return Response(result)


class PropkeepStatesView(APIView):
    """List all states in the knowledge base."""
    permission_classes = [AllowAny]
    
    def get(self, request):
        from propkeep_brain import list_states
        return Response({'states': list_states()})


class PropkeepHealthView(APIView):
    """Health check for PROPKEEP brain."""
    permission_classes = [AllowAny]
    
    def get(self, request):
        from propkeep_brain import load_knowledge_base
        kb = load_knowledge_base()
        return Response({
            'status': 'ok',
            'service': 'PROPKEEP',
            'description': 'AI Property Management Compliance Expert',
            'qa_pairs': len(kb['qa']),
            'federal_facts': len(kb['facts']),
            'states': len(kb['state_facts']),
            'scenarios': len(kb['scenarios']),
            'models': ['qwen3.5:9b', 'qwen3.5:4b', 'kimi-k2.6:cloud'],
            'features': ['RAG', 'state_detection', 'compliance_lookup', 'expert_answers'],
        })


class PropkeepScenariosView(APIView):
    """Get compliance scenarios."""
    permission_classes = [AllowAny]
    
    def get(self, request):
        from propkeep_brain import load_knowledge_base
        kb = load_knowledge_base()
        scenarios = []
        for sc in kb['scenarios']:
            scenarios.append({
                'scenario': sc['scenario'],
                'correct_action': sc['correct_action'],
                'common_mistake': sc['common_mistake'],
                'penalty_if_wrong': sc['penalty_if_wrong'],
            })
        return Response({'scenarios': scenarios})