import re
from typing import Optional, List

class BlockPropertyFinder:
    @staticmethod
    def make_content_hugo_friendly(content: str) -> str:
        if not content:
            return content
        pattern = r"\n\S+::\s+\S+"
        return re.sub(pattern, '', content, flags=re.IGNORECASE)

class Shortcodes:
    YOUTUBE = 'youtube'
    TWITTER = 'twitter'
    VIMEO = 'vimeo'

    @staticmethod
    def shortcodes() -> List[str]:
        return [Shortcodes.YOUTUBE, Shortcodes.TWITTER, Shortcodes.VIMEO]

    @staticmethod
    def pattern(shortcode: str) -> str:
        patterns = {
            Shortcodes.YOUTUBE: r"\{\{youtube\s*(.*?)\s*\}\}",
            Shortcodes.TWITTER: r"\{\{twitter\s*(.*?)\s*\}\}",
            Shortcodes.VIMEO: r"\{\{vimeo\s*(.*?)\s*\}\}",
        }
        return patterns[shortcode]

    @staticmethod
    def process_link(shortcode: str, link: str) -> str:
        if shortcode in [Shortcodes.YOUTUBE, Shortcodes.VIMEO]:
            return link.strip().split('/')[-1]
        elif shortcode == Shortcodes.TWITTER:
            # e.g. https://twitter.com/SanDiegoZoo/status/1453110110599868418
            parts = link.strip().split('/')
            if len(parts) >= 2:
                id_ = parts[-1]
                user = parts[-3] if len(parts) >= 3 else ''
                return f'user="{user}" id="{id_}"'
            return link
        else:
            return link

    @staticmethod
    def replacement(shortcode: str, inside: str) -> str:
        replacements = {
            Shortcodes.YOUTUBE: f"{{{{< youtube {inside} >}}}}",
            Shortcodes.TWITTER: f"{{{{< tweet {inside} >}}}}",
            Shortcodes.VIMEO: f"{{{{< vimeo {inside} >}}}}",
        }
        return replacements[shortcode]


class LinkFinder:
    PAGE_EMBED = 'page_embed'
    PAGE_ALIAS = 'page_alias'
    PAGE_REFERENCE = 'page_reference'
    BLOCK_EMBED = 'block_embed'
    BLOCK_ALIAS = 'block_alias'
    BLOCK_REFERENCE = 'block_reference'

    def __init__(self, kind: str, name: Optional[str] = None, uuid: Optional[str] = None, content: Optional[str] = None, path: Optional[str] = None):
        self.kind = kind
        self.name = name
        self.uuid = uuid
        self.content = content
        self.path = path

    @staticmethod
    def page_link_checks(name: str, path: str) -> List['LinkFinder']:
        # Order matters
        return [
            LinkFinder(LinkFinder.PAGE_EMBED, name=name, path=path),
            LinkFinder(LinkFinder.PAGE_ALIAS, name=name, path=path),
            LinkFinder(LinkFinder.PAGE_REFERENCE, name=name, path=path),
        ]

    @staticmethod
    def block_link_checks(uuid: str, content: str, path: str) -> List['LinkFinder']:
        # Order matters
        return [
            LinkFinder(LinkFinder.BLOCK_EMBED, uuid=uuid, content=content, path=path),
            LinkFinder(LinkFinder.BLOCK_ALIAS, uuid=uuid, content=content, path=path),
            LinkFinder(LinkFinder.BLOCK_REFERENCE, uuid=uuid, content=content, path=path),
        ]

    def pattern(self) -> str:
        if self.kind == self.PAGE_EMBED:
            return r"\{\{embed\s*\[\[\s*" + re.escape(self.name or '') + r"\s*\]\]\s*\}\}"
        elif self.kind == self.PAGE_ALIAS:
            # Aliased page: [alias]([[actual page]])
            return r"\]\(\s*\[\[\s*" + re.escape(self.name or '') + r"\s*\]\]\s*\)"
        elif self.kind == self.PAGE_REFERENCE:
            return r"\[\[\s*" + re.escape(self.name or '') + r"\s*\]\]"
        elif self.kind == self.BLOCK_EMBED:
            return r"\{\{embed\s*\(\(\s*" + re.escape(self.uuid or '') + r"\s*\)\)\s*\}\}"
        elif self.kind == self.BLOCK_ALIAS:
            # Aliased block: [alias](((uuid)))
            return r"\]\(\s*\(\(\s*" + re.escape(self.uuid or '') + r"\s*\)\)\s*\)"
        elif self.kind == self.BLOCK_REFERENCE:
            return r"\(\(\s*" + re.escape(self.uuid or '') + r"\s*\)\)"
        else:
            return ''

    def readable(self) -> str:
        if self.kind == self.PAGE_EMBED or self.kind == self.PAGE_REFERENCE:
            return f"[[{self.name}]]"
        elif self.kind == self.PAGE_ALIAS:
            return "]"
        elif self.kind == self.BLOCK_EMBED:
            return self.content or ''
        elif self.kind == self.BLOCK_ALIAS:
            return "]"
        elif self.kind == self.BLOCK_REFERENCE:
            return self.shortened_block_content(self.content or '')
        else:
            return ''

    def shortened_block_content(self, content: str) -> str:
        return content.split('\n', 1)[0] if '\n' in content else content

    def hugo_friendly_link(self) -> str:
        if self.kind == self.PAGE_EMBED:
            return f"{{{{< links/page-embed \"{self.path}\" >}}}}"
        elif self.kind == self.PAGE_ALIAS:
            return f"]({self.path})"
        elif self.kind == self.PAGE_REFERENCE:
            return f"[{self.name}]({self.path})"
        elif self.kind == self.BLOCK_EMBED:
            return f"{{{{< links/block-embed \"{self.path}\" >}}}}"
        elif self.kind == self.BLOCK_ALIAS:
            return f"]({self.path})"
        elif self.kind == self.BLOCK_REFERENCE:
            return f"[{self.shortened_block_content(self.content or '')}]({self.path})"
        else:
            return ''

    def ranges(self, content: str) -> List[tuple]:
        pattern = self.pattern()
        matches = list(re.finditer(pattern, content, flags=re.IGNORECASE))
        return [(m.start(), m.end()) for m in matches]

    def make_content_hugo_friendly(self, content: str, no_links: bool = False) -> str:
        updated_content = content
        for _ in range(len(self.ranges(updated_content))):
            matches = list(re.finditer(self.pattern(), updated_content, flags=re.IGNORECASE))
            if matches:
                match = matches[0]
                replacement = self.readable() if no_links else self.hugo_friendly_link()
                updated_content = (
                    updated_content[:match.start()] + replacement + updated_content[match.end():]
                )
        return updated_content
