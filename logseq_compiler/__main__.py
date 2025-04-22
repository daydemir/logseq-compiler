import argparse
from pathlib import Path
from logseq_compiler.compiler import Graph, CompilerError

def main() -> None:
    import time
    t_compiler_start = time.time()
    parser = argparse.ArgumentParser(
        description="logseq-compiler: Convert Logseq JSON exports to Hugo-compatible Markdown."
    )
    parser.add_argument("graph_json_path", help="Path to Logseq graph JSON")
    parser.add_argument("assets_folder_path", help="Path to Logseq assets folder")
    parser.add_argument("destination_folder_path", help="Hugo content folder")
    parser.add_argument(
        "--assume-public",
        action="store_true",
        help="Assume public unless block states otherwise (default: off, requires public:: true to be included)",
    )

    args = parser.parse_args()
    try:
        graph = Graph(
            json_path=Path(args.graph_json_path).expanduser(),
            assets_folder=Path(args.assets_folder_path).expanduser(),
            destination_folder=Path(args.destination_folder_path).expanduser(),
        )
        graph.export_for_hugo(assume_public=args.assume_public)
        print("Done!")
    except CompilerError as ce:
        print(f"Error: {ce}")
    except Exception as e:
        print(f"Unexpected error: {e}")
    finally:
        print(f"[logseq-compiler] [main] DONE. Total compiler time elapsed: {time.time() - t_compiler_start:.2f}s")

if __name__ == "__main__":
    main()
