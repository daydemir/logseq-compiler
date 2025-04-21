from __future__ import annotations
from dataclasses import dataclass, field
from typing import Optional, List, Dict, Any, TYPE_CHECKING

@dataclass(frozen=True)
class Block:
    # ... existing fields ...

    def is_page(self) -> bool:
        return self.page_id is None and self.parent_id is None

    def is_public(self, assume_public: bool = False) -> bool:
        if assume_public:
            if 'public' in self.properties:
                return bool(self.properties.get('public'))
            else:
                return True
        else:
            return bool(self.properties.get('public', False))

    def showable(self) -> bool:
        content = (self.content or '').strip()
        is_not_page_properties_and_has_content = not self.preblock and len(content) > 0
        return self.is_page() or is_not_page_properties_and_has_content

    uuid: str
    id: int
    name: Optional[str] = None
    original_name: Optional[str] = None
    content: Optional[str] = None
    page_id: Optional[int] = None
    parent_id: Optional[int] = None
    left_id: Optional[int] = None
    namespace_id: Optional[int] = None
    properties: Dict[str, Any] = field(default_factory=dict)
    preblock: bool = False
    format: Optional[str] = None
    collapsed: bool = False
    updated_at: Optional[float] = None
    created_at: Optional[float] = None
    linked_ids: List[int] = field(default_factory=list)
    inherited_linked_ids: List[int] = field(default_factory=list)
    alias_ids: List[int] = field(default_factory=list)

    @staticmethod
    def from_json(json_obj: Dict[str, Any]) -> Block:
        # Key mapping from Swift to Python
        k = {
            'uuid': 'block/uuid',
            'id': 'db/id',
            'name': 'block/name',
            'original_name': 'block/original-name',
            'content': 'block/content',
            'page_id': 'block/page',
            'parent_id': 'block/parent',
            'left_id': 'block/left',
            'namespace_id': 'block/namespace',
            'properties': 'block/properties',
            'preblock': 'block/pre-block?',
            'format': 'block/format',
            'collapsed': 'block/collapsed?',
            'updated_at': 'block/updated-at',
            'created_at': 'block/created-at',
            'refs': 'block/refs',
            'path_refs': 'block/path-refs',
            'alias': 'block/alias',
        }
        
        def get_id_field(obj, key):
            # Handles nested id fields
            val = obj.get(key)
            if isinstance(val, dict):
                return val.get(k['id'])
            return None
        
        def get_id_list(arr):
            return [item.get(k['id']) for item in arr if isinstance(item, dict) and k['id'] in item]
        
        return Block(
            uuid=json_obj[k['uuid']],
            id=json_obj[k['id']],
            name=(json_obj.get(k['name']) or '').strip() or None,
            original_name=(json_obj.get(k['original_name']) or '').strip() or None,
            content=json_obj.get(k['content']),
            page_id=get_id_field(json_obj, k['page_id']),
            parent_id=get_id_field(json_obj, k['parent_id']),
            left_id=get_id_field(json_obj, k['left_id']),
            namespace_id=get_id_field(json_obj, k['namespace_id']),
            properties=json_obj.get(k['properties'], {}),
            preblock=bool(json_obj.get(k['preblock'], False)),
            format=json_obj.get(k['format']),
            collapsed=bool(json_obj.get(k['collapsed'], False)),
            updated_at=json_obj.get(k['updated_at']),
            created_at=json_obj.get(k['created_at']),
            linked_ids=get_id_list(json_obj.get(k['refs'], [])),
            inherited_linked_ids=get_id_list(json_obj.get(k['path_refs'], [])),
            alias_ids=get_id_list(json_obj.get(k['alias'], [])),
        )
