import re
from typing import Any, Dict, List, Optional

from .block import Block

REDACTED_TEXT = 'redacted 😶‍🌫️'

def get_display_text(block: Block, blocks: Dict[int, Block], public_registry: dict = None) -> str:
    """
    Returns the display text for a block or page, redacting if private.
    """
    is_public = public_registry.get(block.id, False) if public_registry else False
    if is_public:
        if block.is_page():
            return block.original_name or block.name or ''
        else:
            content = (block.content or '').replace('"', '\"')
            first_line = content.split('\n', 1)[0]
            return first_line if first_line else '[block]'
    else:
        return REDACTED_TEXT

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
def _path_component(self, public_registry=None, context_block=None):
    # Public page: slugified name
    if self.is_page():
        is_public = False
        if public_registry is not None and hasattr(self, 'id'):
            is_public = public_registry.get(self.id, False)
        else:
            # fallback to property
            is_public = getattr(self, 'properties', {}).get('public', False)
        if is_public:
            return slugify(self.name or self.original_name or str(self.id))
        else:
            return self.uuid
    # Any block (public or private): uuid
    return self.uuid
setattr(Block, 'path_component', _path_component)


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
    # Deprecated: Use get_display_text instead
    return get_display_text(block, blocks, public_registry)


def readable_name_hover(block: Block) -> str:
    name_visible = block.properties.get('name-visible', 'false').lower() == 'true' if hasattr(block, 'properties') else False
    if name_visible or block.is_public():
        return ''
    return 'this block has not yet been made public by the author'

class HugoBlock:
    def __init__(self, block: Block, blocks: Dict[int, Block], backlinks=None, aliases=None, links=None, sibling_index=0):
        self.block = block
        self.blocks = blocks
        # backlinks, aliases, links are lists of block ids
        self.backlink_paths = {bid: self.path_for(blocks[bid]) for bid in backlinks or []}
        self.alias_paths = {bid: self.path_for(blocks[bid]) for bid in aliases or []}
        ns = namespace(block, blocks)
        self.namespace_path = self.path_for(ns) if ns else None
        self.link_paths = {bid: self.path_for(blocks[bid]) for bid in links or []}
        self.sibling_index = sibling_index


    def is_home(self) -> bool:
        return is_home(self.block)

    def path_for(self, block: Optional[Block]) -> str:
        if not block:
            return ''
        ancestors = all_ancestors(block, self.blocks)
        return 'graph/' + '/'.join([b.path_component() for b in ancestors])

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
        props['weight'] = self.sibling_index + 1
        # Always add title, matching Swift logic
        title = get_display_text(self.block, self.blocks, public_registry) or "Untitled"
        props['title'] = title
        hover = readable_name_hover(self.block)
        if hover:
            props['title-hover'] = hover
        return props

    def hugo_yaml(self, public_registry=None) -> str:
        import yaml
        yaml_props = dict(self.block.properties)
        # Move 'links' to 'external-links' for Hugo (leave value unchanged)
        if 'links' in yaml_props:
            yaml_props['external-links'] = yaml_props['links']
            del yaml_props['links']
        # Always move 'url' to 'external-url' for Hugo compatibility
        if 'url' in yaml_props:
            yaml_props['external-url'] = yaml_props['url']
            del yaml_props['url']
        # Fix location property: remove extraneous quotes
        if 'location' in yaml_props and isinstance(yaml_props['location'], str):
            loc = yaml_props['location']
            if (loc.startswith('"') and loc.endswith('"')) or (loc.startswith("'") and loc.endswith("'")):
                yaml_props['location'] = loc[1:-1]
        yaml_props.update(self.hugo_properties(public_registry=public_registry))
        return yaml.safe_dump(yaml_props, sort_keys=False, allow_unicode=True)

    def file(self, public_registry=None) -> str:
        yaml_header = self.hugo_yaml(public_registry=public_registry)
        content = self.block.content or ''
        # Apply all content transformations in Hugo order
        content = update_asset_links(content)
        content = update_links(content, self.link_paths, self.blocks, public_registry=public_registry)
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
    # Rewrite asset links to use /assets/... (site root) instead of relative or content/assets
    def asset_repl(m):
        alt, filename = m.group(1), m.group(2)
        return f'![{alt}](/assets/{filename})'
    # Replace ![alt](../assets/filename) and ![alt](assets/filename)
    content = re.sub(r'!\[(.*?)\]\(\.\./assets/([^\)]+)\)', asset_repl, content)
    content = re.sub(r'!\[(.*?)\]\(assets/([^\)]+)\)', asset_repl, content)
    return content

def update_links(content: str, link_paths: dict, blocks: dict, public_registry=None) -> str:
    # Replace [[Page Name]] and ((block-uuid)) with Hugo paths and correct redacted names
    def page_link_repl(m):
        name = m.group(1)
        for b in blocks.values():
            if b.name == name or b.original_name == name:
                path = link_paths.get(b.id)
                if path:
                    link_text = get_display_text(b, blocks, public_registry)
                    if link_text == REDACTED_TEXT:
                        return f'[{REDACTED_TEXT}](-)'
                    return f'[{link_text}]({path})'
        return m.group(0)
    def block_link_repl(m):
        uuid = m.group(1)
        for b in blocks.values():
            if b.uuid == uuid:
                path = link_paths.get(b.id)
                if path:
                    link_text = get_display_text(b, blocks, public_registry)
                    if link_text == REDACTED_TEXT:
                        return f'[{REDACTED_TEXT}](-)'
                    return f'[{link_text}]({path})'
        return m.group(0)
    content = re.sub(r'\[\[([^\]]+)\]\]', page_link_repl, content)
    content = re.sub(r'\(\(([^\)]+)\)\)', block_link_repl, content)
    return content


