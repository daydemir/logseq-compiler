from typing import Dict, Any, List, Optional
from .block import Block
import re
def slugify(value: str) -> str:
    import re
    value = value.lower()
    value = re.sub(r'[^\w\-]+', '-', value)  # replace non-word/space/hyphen with dash
    value = re.sub(r'-+', '-', value)  # collapse multiple dashes
    value = value.strip('-')
    return value


# Move path_component to Block, matching Swift
from urllib.parse import quote

def percent_encode(value: str) -> str:
    # For fallback, similar to Swift's percent encoding
    return quote(value, safe='')


# Add to Block:
setattr(Block, 'path_component', lambda self: (
    slugify(self.name or self.original_name or str(self.id)) if self.is_page() else self.uuid
))

def is_home(block: Block) -> bool:
    return bool(block.properties.get('home', False))



def all_ancestors(block: Block, blocks: Dict[int, Block]) -> List[Block]:
    parent = blocks.get(block.parent_id) if block.parent_id else None
    if parent:
        return all_ancestors(parent, blocks) + [block]
    return [block]

def backlinks(block: Block, blocks: Dict[int, Block]) -> List[Block]:
    return [b for b in blocks.values() if block.id in b.linked_ids]

def links(block: Block, blocks: Dict[int, Block]) -> List[Block]:
    return [blocks[bid] for bid in block.linked_ids if bid in blocks]

def aliases(block: Block, blocks: Dict[int, Block]) -> List[Block]:
    return [blocks[aid] for aid in block.alias_ids if aid in blocks]

def sibling_index(block: Block, blocks: Dict[int, Block]) -> int:
    if block.left_id and block.left_id in blocks:
        return sibling_index(blocks[block.left_id], blocks) + 1
    return 1

def namespace(block: Block, blocks: Dict[int, Block]) -> Optional[Block]:
    if block.namespace_id and block.namespace_id in blocks:
        return blocks[block.namespace_id]
    return None

def readable_name(block: Block, blocks: Dict[int, Block], public_registry: dict = None) -> str:
    # Check if block is public
    is_public = block.is_public() if hasattr(block, 'is_public') else False
    name_visible = block.properties.get('name-visible', 'false').lower() == 'true' if hasattr(block, 'properties') else False
    if is_public or name_visible:
        if block.is_page():
            return (block.original_name or block.name or '').replace('"', '\"')
        else:
            content = (block.content or '').replace('"', '\"')
            max_len = 100
            first_line = content.split('\n', 1)[0]
            if len(first_line) > max_len:
                return ' '.join(first_line[:max_len-3].split(' ')[:-1]) + '...'
            return first_line
    else:
        return '[redacted 😶‍🌫️]'

def readable_name_hover(block: Block) -> str:
    name_visible = block.properties.get('name-visible', 'false').lower() == 'true' if hasattr(block, 'properties') else False
    if name_visible or block.is_public():
        return ''
    return 'this block has not yet been made public by the author'

class HugoBlock:
    def __init__(self, block: Block, blocks: Dict[int, Block]):
        self.block = block
        self.blocks = blocks
        self.backlink_paths = {b.id: self.path_for(b) for b in backlinks(block, blocks)}
        self.alias_paths = {b.id: self.path_for(b) for b in aliases(block, blocks)}
        ns = namespace(block, blocks)
        self.namespace_path = self.path_for(ns) if ns else None
        self.link_paths = {b.id: self.path_for(b) for b in links(block, blocks)}
        self.sibling_index = sibling_index(block, blocks)


    def is_home(self) -> bool:
        return is_home(self.block)

    def path_for(self, block: Optional[Block]) -> str:
        if not block:
            return ''
        ancestors = all_ancestors(block, self.blocks)
        return '/'.join([b.path_component() for b in ancestors])

    def hugo_properties(self, public_registry=None) -> Dict[str, Any]:
        props = {}
        if self.backlink_paths:
            if public_registry is not None:
                public_backlinks = [v for k, v in self.backlink_paths.items() if public_registry.get(k, False)]
                props['backlinks'] = public_backlinks
            else:
                props['backlinks'] = list(self.backlink_paths.values())
        if self.alias_paths:
            props['aliases'] = list(self.alias_paths.values())
        if self.namespace_path:
            props['namespace'] = self.namespace_path
        if self.link_paths:
            props['links'] = list(self.link_paths.values())
        props['collapsed'] = self.block.collapsed
        props['logseq-type'] = 'page' if self.block.is_page() else 'block'
        props['weight'] = self.sibling_index
        # Always add title, matching Swift logic
        title = readable_name(self.block, self.blocks) or "Untitled"
        props['title'] = title
        hover = readable_name_hover(self.block)
        if hover:
            props['title-hover'] = hover
        return props

    def hugo_yaml(self, public_registry=None) -> str:
        import yaml
        yaml_props = dict(self.block.properties)
        yaml_props.update(self.hugo_properties(public_registry=public_registry))
        return yaml.safe_dump(yaml_props, sort_keys=False, allow_unicode=True)

    def remove_private_links(self, public_registry: Dict[int, bool]) -> 'HugoBlock':
        # Redact links to private blocks/pages
        content = self.block.content or ''
        def redact(match):
            name = match.group(1)
            uid = match.group(2)
            if name:
                for b in self.blocks.values():
                    if b.name == name or b.original_name == name:
                        if not public_registry.get(b.id, False):
                            return '[REDACTED]'
                return match.group(0)
            if uid:
                for b in self.blocks.values():
                    if b.uuid == uid:
                        if not public_registry.get(b.id, False):
                            return '[REDACTED]'
                return match.group(0)
            return match.group(0)
        content = re.sub(r'\[\[([^\]]+)\]\]|\(\(([^\)]+)\)\)', redact, content)
        # Return a new HugoBlock with redacted content
        new_block = Block(
            uuid=self.block.uuid,
            id=self.block.id,
            name=self.block.name,
            original_name=self.block.original_name,
            content=content,
            page_id=self.block.page_id,
            parent_id=self.block.parent_id,
            left_id=self.block.left_id,
            namespace_id=self.block.namespace_id,
            properties=self.block.properties,
            preblock=self.block.preblock,
            format=self.block.format,
            collapsed=self.block.collapsed,
            updated_at=self.block.updated_at,
            created_at=self.block.created_at,
            linked_ids=self.block.linked_ids,
            inherited_linked_ids=self.block.inherited_linked_ids,
            alias_ids=self.block.alias_ids
        )
        return HugoBlock(new_block, self.blocks)

    def file(self, public_registry=None) -> str:
        yaml_header = self.hugo_yaml(public_registry=public_registry)
        content = self.block.content or ''
        # Apply all content transformations in Hugo order
        content = update_asset_links(content)
        content = update_links(content, self.link_paths, self.blocks)
        content = update_shortcodes(content)
        content = update_block_properties(content)
        return f"---\n{yaml_header}---\n\n{content}\n"

# --- Helpers to match Swift's link-finder.swift ---
def update_block_properties(content: str) -> str:
    # Remove block properties like "\nkey:: value"
    return re.sub(r'\n\S+::\s+\S+', '', content)

def update_shortcodes(content: str) -> str:
    # Replace {{youtube ...}}, {{twitter ...}}, {{vimeo ...}} with Hugo shortcodes
    def yt_repl(m):
        return f"{{< youtube {m.group(1).strip().split('/')[-1]} >}}"
    def tw_repl(m):
        # Extract user and tweet id
        parts = m.group(1).strip().split('/')
        if len(parts) >= 3:
            user = parts[-3]
            tweet_id = parts[-1]
            return f'{{< tweet user="{user}" id="{tweet_id}" >}}'
        return m.group(0)
    def vimeo_repl(m):
        return f"{{< vimeo {m.group(1).strip().split('/')[-1]} >}}"
    content = re.sub(r'\{\{youtube\s+(.*?)\}\}', yt_repl, content)
    content = re.sub(r'\{\{twitter\s+(.*?)\}\}', tw_repl, content)
    content = re.sub(r'\{\{vimeo\s+(.*?)\}\}', vimeo_repl, content)
    return content

def update_asset_links(content: str) -> str:
    # Minimal: replace asset links if needed for Hugo
    # (Extend as needed for your asset conventions)
    return content

def update_links(content: str, link_paths: dict, blocks: dict) -> str:
    # Replace [[Page Name]] and ((block-uuid)) with Hugo paths if public
    def page_link_repl(m):
        name = m.group(1)
        for b in blocks.values():
            if b.name == name or b.original_name == name:
                path = link_paths.get(b.id)
                if path:
                    return f'[{name}]({path})'
        return m.group(0)
    def block_link_repl(m):
        uuid = m.group(2)
        for b in blocks.values():
            if b.uuid == uuid:
                path = link_paths.get(b.id)
                if path:
                    return f'[block]({path})'
        return m.group(0)
    # Handle both [[Page Name]] and ((block-uuid))
    content = re.sub(r'\[\[([^\]]+)\]\]', page_link_repl, content)
    content = re.sub(r'\(\(([^\)]+)\)\)', block_link_repl, content)
    return content
