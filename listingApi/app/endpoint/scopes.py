"""Scope checks per caller (docs/llstingApi.md, section Auth), shared by the routers.

The UI reads and decides, the sync job creates listings and reports scans, the admin client
deletes. Searches: the UI reads and writes, the sync job reads the active ones.
"""

from fastapi import Depends

from app.api_layer.auth import require_scope

read = Depends(require_scope("read"))
decide = Depends(require_scope("decide"))
create = Depends(require_scope("create"))
admin = Depends(require_scope("admin"))
searches_read = Depends(require_scope("read", resource="searches"))
searches_write = Depends(require_scope("write", resource="searches"))
