from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Dict, List

from .block import Block
from .hugoblock import HugoBlock


class CompilerError(Exception):
    pass

class Graph:
    def __init__(self, json_path: Path, assets_folder: Path, destination_folder: Path) -> None:
        self.assets_folder = assets_folder
        self.destination_folder = destination_folder
        self.blocks: Dict[int, Block] = {}
        self.block_paths: Dict[int, str] = {}
        self.all_content: List[Any] = []  # Placeholder for HugoBlock equivalent
        self._load_blocks(json_path)
        self._calculate_block_hierarchies()

    def _load_blocks(self, json_path: Path) -> None:
        try:
            print(f"[logseq-compiler] Loading graph JSON from: {json_path}")
            with open(json_path, 'r', encoding='utf-8') as f:
                data = json.load(f)
            print(f"[logseq-compiler] JSON loaded. Type: {type(data)}")
            if not isinstance(data, list):
                raise CompilerError('Graph JSON must be a list of blocks')
            print(f"[logseq-compiler] Processing {len(data)} blocks from JSON...")
            self.blocks = {
                block_json['db/id']: Block.from_json(block_json)
                for block_json in data
                if 'db/id' in block_json and 'block/uuid' in block_json
            }
            print(f"[logseq-compiler] {len(self.blocks)} valid blocks loaded.")

            # Precompute backlinks, aliases, links, and sibling_index for all blocks
            self.backlinks_map = {block_id: [] for block_id in self.blocks}
            self.aliases_map = {block_id: [] for block_id in self.blocks}
            self.links_map = {block_id: [] for block_id in self.blocks}
            self.sibling_index_map = {}
            # Build backlinks and links
            for b in self.blocks.values():
                for linked_id in getattr(b, 'linked_ids', []):
                    if linked_id in self.blocks:
                        self.links_map[b.id].append(linked_id)
                        self.backlinks_map[linked_id].append(b.id)
                for alias_id in getattr(b, 'alias_ids', []):
                    if alias_id in self.blocks:
                        self.aliases_map[b.id].append(alias_id)
            # Build sibling_index: for each block, count siblings to the left
            parent_to_children = {}
            for b in self.blocks.values():
                parent_to_children.setdefault(b.parent_id, []).append(b)
            for siblings in parent_to_children.values():
                id_to_block = {b.id: b for b in siblings}
                left_id_to_block = {b.left_id: b for b in siblings if b.left_id is not None}
                sibling_ids = set(id_to_block)
                # Heads: left_id is None or not among sibling ids
                heads = [b for b in siblings if b.left_id is None or b.left_id not in sibling_ids]
                visited = set()
                idx = 0
                # Traverse from each head
                for head in heads:
                    current = head
                    while current and current.id not in visited:
                        self.sibling_index_map[current.id] = idx
                        visited.add(current.id)
                        current = left_id_to_block.get(current.id)
                        idx += 1
                # Orphans: assign index to any unvisited sibling
                for b in siblings:
                    if b.id not in visited:
                        self.sibling_index_map[b.id] = idx
                        idx += 1

            # Compute public_registry once here
            self.public_registry = {}
            import time
            print(f"[logseq-compiler] Computing effective public status for all blocks (optimized DFS)...")
            visited = set()
            checked_count = 0
            start_time = time.time()
            def compute_effective_public(block_id, parent_public=None):
                nonlocal checked_count
                if block_id in visited:
                    return  # already computed
                block = self.blocks[block_id]
                if 'public' in block.properties:
                    val = block.properties['public']
                    if isinstance(val, bool):
                        effective = val
                    else:
                        effective = str(val).lower() == 'true'
                elif parent_public is not None:
                    effective = parent_public
                else:
                    effective = False
                self.public_registry[block_id] = effective
                visited.add(block_id)
                checked_count += 1
                if checked_count % 1000 == 0:
                    print(f"[logseq-compiler] Checked {checked_count} blocks...")
                children = [b.id for b in self.blocks.values() if b.parent_id == block_id]
                for child_id in children:
                    compute_effective_public(child_id, effective)
            # Only start DFS from top-level blocks
            top_level_blocks = [b.id for b in self.blocks.values() if b.parent_id is None]
            for block_id in top_level_blocks:
                compute_effective_public(block_id)
            elapsed = time.time() - start_time
            print(f"[logseq-compiler] Done computing public status for all blocks. Time elapsed: {elapsed:.2f} seconds.")
        except Exception as e:
            print(f"[logseq-compiler] ERROR during block loading: {e}")
            raise CompilerError(f"Failed to load blocks: {e}")

    def _calculate_block_hierarchies(self) -> None:
        import time
        print("[logseq-compiler] [hierarchies] Starting _calculate_block_hierarchies...")
        t0 = time.time()
        notes_folder = "graph/"
        print("[logseq-compiler] [hierarchies] Building ancestor chains...")
        def all_ancestors(block: Block) -> List[Block]:
            parent = self.blocks.get(block.parent_id) if block.parent_id else None
            if parent:
                return all_ancestors(parent) + [block]
            return [block]
        print("[logseq-compiler] [hierarchies] Using precomputed public_registry from _load_blocks.")
        print("[logseq-compiler] [hierarchies] Building block_paths using public_registry...")
        self.block_paths = {
            block_id: notes_folder + "/".join(
                [b.path_component(self.public_registry) for b in all_ancestors(block)]
            )
            for block_id, block in self.blocks.items()
        }
        print("[logseq-compiler] [hierarchies] Done building block_paths.")
        elapsed = time.time() - t0
        print(f"[logseq-compiler] [hierarchies] Finished _calculate_block_hierarchies. Time elapsed: {elapsed:.2f} seconds.")

    def export_for_hugo(self, assume_public: bool = False) -> None:
        import shutil
        import time
        from pathlib import Path
        print("[logseq-compiler] [export] Starting export_for_hugo...")
        t_process_start = time.time()

        def is_public(block: Block) -> bool:
            props = block.properties or {}
            if assume_public:
                return not (str(props.get('public', 'true')).lower() == 'false')
            return str(props.get('public', 'false')).lower() == 'true'

        # Prepare destination: remove all except /files
        print("[logseq-compiler] [export] Preparing destination folder (deleting old content)...")
        t_prep = time.time()
        items = list(self.destination_folder.iterdir())
        print(f"[logseq-compiler] [export] Found {len(items)} items in destination folder.")
        deleted = 0
        for item in items:
            if item.name == 'files':
                continue
            if item.is_dir():
                shutil.rmtree(item)
            else:
                item.unlink()
            deleted += 1
            if deleted % 100 == 0:
                print(f"[logseq-compiler] [export] Deleted {deleted} items...")
        print(f"[logseq-compiler] [export] Done preparing destination. Deleted {deleted} items. Time elapsed: {time.time() - t_prep:.2f}s")

        print("[logseq-compiler] [export] ENTER: Building all_content as HugoBlock objects...")
        t_allcontent = time.time()
        all_content = [
            HugoBlock(
                block,
                self.blocks,
                backlinks=self.backlinks_map.get(block.id, []),
                aliases=self.aliases_map.get(block.id, []),
                links=self.links_map.get(block.id, []),
                sibling_index=self.sibling_index_map.get(block.id, 0)
            )
            for block in self.blocks.values() if block.showable()
        ]
        print(f"[logseq-compiler] [export] EXIT: Built all_content. Time elapsed: {time.time() - t_allcontent:.2f}s")

        print("[logseq-compiler] [export] ENTER: Building effective public_registry...")
        t_pubreg = time.time()
        # Efficient single-pass: build parent->children map
        parent_to_children = {}
        for b in self.blocks.values():
            parent_to_children.setdefault(b.parent_id, []).append(b.id)
        # Use explicit stack for DFS, avoid repeated children lookups
        registry = {}
        stack = []
        # Start with top-level blocks
        for block_id in [b.id for b in self.blocks.values() if b.parent_id is None]:
            stack.append((block_id, assume_public))
        while stack:
            block_id, parent_public = stack.pop()
            block = self.blocks[block_id]
            if 'public' in block.properties:
                val = block.properties['public']
                if isinstance(val, bool):
                    effective = val
                else:
                    effective = str(val).lower() == 'true'
            elif parent_public is not None:
                effective = parent_public
            else:
                effective = assume_public
            registry[block_id] = effective
            for child_id in parent_to_children.get(block_id, []):
                stack.append((child_id, effective))
        public_registry = registry
        print(f"[logseq-compiler] [export] EXIT: Built effective public_registry. Time elapsed: {time.time() - t_pubreg:.2f}s")

        print("[logseq-compiler] [export] ENTER: Filtering publishable (public) content...")
        t_filter = time.time()
        publishable_content = [hb for hb in all_content if public_registry.get(hb.block.id, False)]
        print(f"[logseq-compiler] [export] Found {len(publishable_content)} publishable blocks/pages.")
        print(f"[logseq-compiler] [export] EXIT: Filtering publishable content. Time elapsed: {time.time() - t_filter:.2f}s")

        print("[logseq-compiler] [export] ENTER: Exporting home page...")
        t_home = time.time()
        home_page = next((hb for hb in publishable_content if hb.is_home()), None)
        if home_page:
            dir_path = self.destination_folder
            dir_path.mkdir(parents=True, exist_ok=True)
            file_path = dir_path / '_index.md'
            with open(file_path, 'w', encoding='utf-8') as f:
                f.write(home_page.file(public_registry=self.public_registry))
        print(f"[logseq-compiler] [export] EXIT: Done exporting home page. Time elapsed: {time.time() - t_home:.2f}s")

        print("[logseq-compiler] [export] ENTER: Preparing notes_folder for export...")
        t_notes = time.time()
        notes_folder = self.destination_folder / 'graph'
        notes_folder.mkdir(parents=True, exist_ok=True)
        print(f"[logseq-compiler] [export] EXIT: notes_folder ready. Time elapsed: {time.time() - t_notes:.2f}s")

        print(f"[logseq-compiler] [export] ENTER: Exporting {len(publishable_content)} pages/blocks...")
        t_pages = time.time()
        for i, hb in enumerate(publishable_content):
            if hb.is_home():
                continue
            path = self.block_paths.get(hb.block.id, None)
            if not path:
                continue
            # For both pages and blocks: create a folder and write _index.md
            block_dir = self.destination_folder / path
            block_dir.mkdir(parents=True, exist_ok=True)
            file_path = block_dir / '_index.md'
            with open(file_path, 'w', encoding='utf-8') as f:
                f.write(hb.file(public_registry=self.public_registry))
            if (i+1) % 500 == 0:
                print(f"[logseq-compiler] [export] Exported {i+1} pages/blocks...")
        print(f"[logseq-compiler] [export] EXIT: Done exporting pages/blocks. Time elapsed: {time.time() - t_pages:.2f}s")

        print("[logseq-compiler] [export] ENTER: Copying referenced assets...")
        t_assets = time.time()
        # Asset copying logic: copy only assets referenced by public blocks or as the 'image' property of a public page (no regex)
        assets_src = self.assets_folder
        assets_dst = self.destination_folder / 'assets'
        referenced_assets = []
        if assets_src.exists() and assets_src.is_dir():
            assets_dst.mkdir(parents=True, exist_ok=True)
            for asset in assets_src.iterdir():
                if not asset.is_file():
                    continue
                referenced = False
                asset_patterns = [f'(assets/{asset.name})', f'(../assets/{asset.name})']
                # Check if referenced in content of any public block
                for hb in publishable_content:
                    content = hb.block.content or ''
                    if any(pat in content for pat in asset_patterns):
                        referenced = True
                        break
                # Also check if referenced as the 'image' property of any public page
                if not referenced:
                    for hb in publishable_content:
                        block = hb.block
                        if block.is_page():
                            image_prop = (block.properties or {}).get('image')
                            if isinstance(image_prop, str) and image_prop.endswith(asset.name):
                                referenced = True
                                break
                if referenced:
                    referenced_assets.append(asset)
            print(f"[logseq-compiler] [export] Found {len(referenced_assets)} public assets to copy.")
            for asset in referenced_assets:
                shutil.copy2(asset, assets_dst / asset.name)
        print(f"[logseq-compiler] [export] EXIT: Done copying referenced assets. Time elapsed: {time.time() - t_assets:.2f}s")

        print(f"[logseq-compiler] [export] DONE. Total export_for_hugo time elapsed: {time.time() - t_process_start:.2f}s")

def path_component(block: Block) -> str:
    return block.name or block.original_name or str(block.id)

def all_ancestors(block: Block, blocks: Dict[int, Block]) -> List[Block]:
    parent = blocks.get(block.parent_id) if block.parent_id else None
    if parent:
        return all_ancestors(parent, blocks) + [block]
    return [block]
