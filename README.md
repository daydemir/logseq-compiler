# logseq-compiler

This command line tool takes a link to your logseq graph and processes all the pages and blocks and converts them into a set of Hugo-friendly sections and web pages.

Some features
- Recognizes public and private blocks using the `public::` property
- Collects links and backlinks
- Page URLs are derived from page title
- Every block can be referenced by its UUID, and thus has a unique URL
- Acts as a proper static site allowing for proper SEO

Future stuff
- Obfuscate names of links to private pages / blocks
- Enable grammar for semantic links using arrows (->)

command for local testing

export logseq notes to a json in the notes repo
```sh
lq sq --graph test-notes '[:find (pull ?p [*]) :where (?p :block/uuid ?id)]' | jet --to json > './test-notes/.export/graph.json'
```

```sh
poetry run python -m logseq_compiler ../test-notes/.export/graph.json ../test-notes/assets ../content
``` 


full notes testing
```sh
lq sq --graph life '[:find (pull ?p [*]) :where (?p :block/uuid ?id)]' | jet --to json > /Users/deniz/Library/Mobile\ Documents/iCloud~com~logseq~logseq/Documents/life/.export/graph-test.json
```

```sh
poetry run python -m logseq_compiler /Users/deniz/Library/Mobile\ Documents/iCloud~com~logseq~logseq/Documents/life/.export/graph-test.json /Users/deniz/Library/Mobile\ Documents/iCloud~com~logseq~logseq/Documents/life/assets ../content
```