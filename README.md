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
