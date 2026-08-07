"""Haven Memory Knowledge Foundation v0.

Public surface: KnowledgeService (domain operations), AuthContext (server-side
identity), and run_worker (background pipeline). See
docs/specs/haven-memory-knowledge-foundation-v0.md.
"""

from .identity import AuthContext, clerk_context
from .service import KnowledgeService
from .worker import run_worker

__all__ = ["AuthContext", "KnowledgeService", "clerk_context", "run_worker"]
