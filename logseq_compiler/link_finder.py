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
