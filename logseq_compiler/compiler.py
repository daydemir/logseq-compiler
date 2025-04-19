from __future__ import annotations
from typing import Dict, List, Any, Optional
from pathlib import Path
import json
from .block import Block

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
            with open(json_path, 'r', encoding='utf-8') as f:
                data = json.load(f)
            if not isinstance(data, list):
                raise CompilerError('Graph JSON must be a list of blocks')
            self.blocks = {
                block_json['db/id']: Block.from_json(block_json)
                for block_json in data
                if 'db/id' in block_json and 'block/uuid' in block_json
            }
        except Exception as e:
            raise CompilerError(f"Failed to load blocks: {e}")

    def _calculate_block_hierarchies(self) -> None:
        notes_folder = "graph/"
        def all_ancestors(block: Block) -> List[Block]:
            parent = self.blocks.get(block.parent_id) if block.parent_id else None
            if parent:
                return all_ancestors(parent) + [block]
            return [block]
        self.block_paths = {
            block_id: notes_folder + "/".join(
                [b.name or b.original_name or str(b.id) for b in all_ancestors(block)]
            )
            for block_id, block in self.blocks.items()
        }

    def export_for_hugo(self, assume_public: bool = False) -> None:
        import shutil
        import yaml
        from pathlib import Path

        def is_public(block: Block) -> bool:
            props = block.properties or {}
            # By default, require public:: true, unless assume_public is set
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

        # Filter public blocks
        public_blocks = [block for block in self.blocks.values() if is_public(block)]

        # Export each public block as a Markdown file
        for block in public_blocks:
            path_parts = self.block_paths.get(block.id, f"graph/{block.id}").split('/')
            # Use block name or id for filename
            filename = (block.name or block.original_name or str(block.id)) + ".md"
            # Directory for the block
            dir_path = self.destination_folder.joinpath(*path_parts[:-1])
            dir_path.mkdir(parents=True, exist_ok=True)
            file_path = dir_path / filename

            # YAML front matter
            front_matter = {
                'id': block.id,
                'uuid': block.uuid,
                'created_at': block.created_at,
                'updated_at': block.updated_at,
                'properties': block.properties,
            }
            yaml_str = yaml.safe_dump(front_matter, sort_keys=False, allow_unicode=True)
            content = block.content or ""

            # Write to file
            with open(file_path, 'w', encoding='utf-8') as f:
                f.write(f"---\n{yaml_str}---\n\n{content}\n")
