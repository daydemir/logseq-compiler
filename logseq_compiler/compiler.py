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
            # Compute public_registry once here
            self.public_registry = {}
            def compute_effective_public(block_id, parent_public=None, depth=0):
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
                children = [b.id for b in self.blocks.values() if b.parent_id == block_id]
                self.public_registry[block_id] = effective
                if depth < 2 or len(children) > 0:
                    print(f"[logseq-compiler] Block {block_id}: public={effective}, children={len(children)}")
                for child_id in children:
                    compute_effective_public(child_id, effective, depth=depth+1)
            print(f"[logseq-compiler] Computing effective public status for all blocks...")
            for idx, block_id in enumerate(self.blocks):
                if idx % 100 == 0 and idx > 0:
                    print(f"[logseq-compiler] Processed {idx} blocks for public status...")
                compute_effective_public(block_id)
            print(f"[logseq-compiler] Done computing public status for all blocks.")
        except Exception as e:
            print(f"[logseq-compiler] ERROR during block loading: {e}")
            raise CompilerError(f"Failed to load blocks: {e}")

    def _calculate_block_hierarchies(self) -> None:
        notes_folder = "graph/"
        def all_ancestors(block: Block) -> List[Block]:
            parent = self.blocks.get(block.parent_id) if block.parent_id else None
            if parent:
                return all_ancestors(parent) + [block]
            return [block]
        # Compute public_registry before calculating paths
        public_registry = {}
        def compute_effective_public(block_id, parent_public=None):
            block = self.blocks[block_id]
            if 'public' in block.properties:
                val = block.properties['public']
                # Accept bool or string values
                if isinstance(val, bool):
                    effective = val
                else:
                    effective = str(val).lower() == 'true'
            elif parent_public is not None:
                effective = parent_public
            else:
                # Top-level (page): default private
                effective = False
            # Recurse for children
            children = [b.id for b in self.blocks.values() if b.parent_id == block_id]
            public_registry[block_id] = effective
            for child_id in children:
                compute_effective_public(child_id, effective)
        for block_id in self.blocks:
            compute_effective_public(block_id)
        self.block_paths = {
            block_id: notes_folder + "/".join(
                [b.path_component(self.public_registry) for b in all_ancestors(block)]
            )
            for block_id, block in self.blocks.items()
        }

    def export_for_hugo(self, assume_public: bool = False) -> None:
        import shutil
        from pathlib import Path

        def is_public(block: Block) -> bool:
            props = block.properties or {}
            if assume_public:
                return not (str(props.get('public', 'true')).lower() == 'false')
            return str(props.get('public', 'false')).lower() == 'true'

        # Prepare destination: remove all except /files
        for item in self.destination_folder.iterdir():
            if item.name == 'files':
                continue
            if item.is_file():
                item.unlink()
            elif item.is_dir():
                shutil.rmtree(item)

        # Build all_content as HugoBlock objects
        all_content = [HugoBlock(block, self.blocks) for block in self.blocks.values() if block.showable()]

        # Build effective public registry (inheritance-based)
        def compute_effective_public(block_id, parent_public=None):
            block = self.blocks[block_id]
            if 'public' in block.properties:
                val = block.properties['public']
                # Accept bool or string values
                if isinstance(val, bool):
                    effective = val
                else:
                    effective = str(val).lower() == 'true'
            elif parent_public is not None:
                effective = parent_public
            else:
                # Top-level (page): use assume_public
                effective = assume_public
            # Recurse for children
            children = [b.id for b in self.blocks.values() if b.parent_id == block_id]
            registry[block_id] = effective
            for child_id in children:
                compute_effective_public(child_id, effective)
        registry = {}
        # Start recursion at all top-level pages
        top_level_blocks = [b.id for b in self.blocks.values() if b.parent_id is None]
        for block_id in top_level_blocks:
            compute_effective_public(block_id)
        public_registry = registry

        # Diagnostic: print all pages and their effective public status
        print("\n[DEBUG] Page public status:")
        for block in self.blocks.values():
            if block.is_page():
                name = block.name or block.original_name or str(block.id)
                print(f"Page ID: {block.id}, Name: {name}, public: {public_registry.get(block.id, None)}")

        # Only include public blocks
        publishable_content = [hb for hb in all_content if public_registry.get(hb.block.id, False)]

        # Debug printout of block_paths for all publishable blocks
        print("\n[DEBUG] Export paths for all publishable blocks:")
        for hb in publishable_content:
            path = self.block_paths.get(hb.block.id, None)
            print(f"Block ID: {hb.block.id}, Type: {'page' if hb.block.is_page() else 'block'}, Path: {path}")

        # Export home page
        home_page = next((hb for hb in publishable_content if hb.is_home()), None)
        if home_page:
            dir_path = self.destination_folder
            dir_path.mkdir(parents=True, exist_ok=True)
            file_path = dir_path / '_index.md'
            with open(file_path, 'w', encoding='utf-8') as f:
                f.write(home_page.file(public_registry=public_registry))

        # Export pages (excluding home)
        notes_folder = self.destination_folder / 'graph'
        notes_folder.mkdir(parents=True, exist_ok=True)
        for hb in publishable_content:
            if hb.is_home():
                continue
            if hb.block.is_page():
                # Use precomputed, slugified path for the page
                page_path = Path(self.block_paths[hb.block.id])
                page_dir = self.destination_folder / page_path
                page_dir.mkdir(parents=True, exist_ok=True)
                file_path = page_dir / '_index.md'
                with open(file_path, 'w', encoding='utf-8') as f:
                    f.write(hb.file(public_registry=public_registry))
            else:
                # Export block as markdown in its hierarchy (match Swift: use block_paths for all blocks)
                block_path = Path(self.block_paths[hb.block.id])
                block_dir = self.destination_folder / block_path
                block_dir.mkdir(parents=True, exist_ok=True)
                file_path = block_dir / '_index.md'
                with open(file_path, 'w', encoding='utf-8') as f:
                    f.write(hb.file(public_registry=public_registry))

        # Asset copying logic: copy only assets referenced by public blocks or as the 'image' property of a public page (no regex)
        assets_src = self.assets_folder
        assets_dst = self.destination_folder / 'assets'
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
                    shutil.copy2(asset, assets_dst / asset.name)

def path_component(block: Block) -> str:
    return block.name or block.original_name or str(block.id)

def all_ancestors(block: Block, blocks: Dict[int, Block]) -> List[Block]:
    parent = blocks.get(block.parent_id) if block.parent_id else None
    if parent:
        return all_ancestors(parent, blocks) + [block]
    return [block]
