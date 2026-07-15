from __future__ import annotations

import json
from dataclasses import dataclass, field
from typing import Any

MAX_TOOL_CALLS = 4
MAX_RESULT_CHARACTERS = 4_000
MAX_DESTINATIONS = 32
MAX_DESTINATION_CHARACTERS = 120
MAX_SEGMENT_CHARACTERS = 1_000
MAX_CONTENT_CHARACTERS = 12_000
MAX_TAXONOMY_ENTRIES = 64

SUPPORTED_TOOLS = {
    "destination_catalog", "file_metadata", "content_segment", "taxonomy_lookup",
}


@dataclass
class ToolContext:
    destinations: tuple[dict[str, str], ...]
    metadata: dict[str, str]
    content: str
    taxonomy: dict[str, str]
    calls: dict[str, int] = field(default_factory=dict)

    def __post_init__(self) -> None:
        if len(self.destinations) > MAX_DESTINATIONS:
            raise ValueError("destination catalog exceeds its entry limit")
        if any(len(item.get("folder", "")) > MAX_DESTINATION_CHARACTERS or
               len(item.get("description", "")) > MAX_DESTINATION_CHARACTERS
               for item in self.destinations):
            raise ValueError("destination catalog entry exceeds its length limit")
        if len(self.content) > MAX_CONTENT_CHARACTERS:
            raise ValueError("tool content exceeds its length limit")
        if len(self.taxonomy) > MAX_TAXONOMY_ENTRIES:
            raise ValueError("taxonomy exceeds its entry limit")
        if set(self.metadata) - {"extension", "size_bucket", "content_kind"}:
            raise ValueError("metadata contains a non-permitted field")

    def record(self, name: str) -> None:
        total = sum(self.calls.values())
        if total >= MAX_TOOL_CALLS:
            raise ValueError("tool call limit reached")
        self.calls[name] = self.calls.get(name, 0) + 1


def build_tools(names: tuple[str, ...], context: ToolContext) -> list[Any]:
    unknown = set(names) - SUPPORTED_TOOLS
    if unknown:
        raise ValueError(f"unsupported tools: {', '.join(sorted(unknown))}")
    import apple_fm_sdk as fm

    tools: list[Any] = []
    if "destination_catalog" in names:
        class DestinationCatalog(fm.Tool):
            name = "destination_catalog"
            description = "Lists only the user's permitted destination folders and descriptions. Cannot browse the filesystem."

            @fm.generable("Destination catalog request")
            class Arguments:
                scope: str = fm.guide("Catalog scope", anyOf=["all"])

            @property
            def arguments_schema(self):
                return self.Arguments.generation_schema()

            async def call(self, args):
                if args.value(str, for_property="scope") != "all":
                    raise ValueError("invalid destination catalog scope")
                context.record(self.name)
                return bounded_json(context.destinations)
        tools.append(DestinationCatalog())

    if "file_metadata" in names:
        allowed_fields = tuple(context.metadata) or ("extension",)

        class FileMetadata(fm.Tool):
            name = "file_metadata"
            description = "Reads one permitted, non-sensitive metadata field for the current file only. Cannot accept a path."

            @fm.generable("Bounded metadata request")
            class Arguments:
                field: str = fm.guide("Permitted metadata field", anyOf=list(allowed_fields))

            @property
            def arguments_schema(self):
                return self.Arguments.generation_schema()

            async def call(self, args):
                field = args.value(str, for_property="field")
                if field not in context.metadata:
                    raise ValueError("metadata field is not permitted")
                context.record(self.name)
                return bounded_json({field: context.metadata[field]})
        tools.append(FileMetadata())

    if "content_segment" in names:
        class ContentSegment(fm.Tool):
            name = "content_segment"
            description = "Reads one bounded segment from the already-extracted current-file text. Cannot accept a path."

            @fm.generable("Bounded content segment request")
            class Arguments:
                offset: int = fm.guide("Character offset", range=(0, MAX_CONTENT_CHARACTERS))
                length: int = fm.guide("Number of characters", range=(1, MAX_SEGMENT_CHARACTERS))

            @property
            def arguments_schema(self):
                return self.Arguments.generation_schema()

            async def call(self, args):
                offset = args.value(int, for_property="offset")
                length = args.value(int, for_property="length")
                if not 0 <= offset <= len(context.content) or not 1 <= length <= MAX_SEGMENT_CHARACTERS:
                    raise ValueError("content segment arguments are outside permitted bounds")
                context.record(self.name)
                return context.content[offset:offset + length]
        tools.append(ContentSegment())

    if "taxonomy_lookup" in names:
        if not context.taxonomy:
            raise ValueError("taxonomy_lookup requires a bounded corpus taxonomy")
        allowed_keys = tuple(context.taxonomy)

        class TaxonomyLookup(fm.Tool):
            name = "taxonomy_lookup"
            description = "Looks up one exact key in the user's bounded taxonomy. Cannot search external data."

            @fm.generable("Taxonomy lookup request")
            class Arguments:
                key: str = fm.guide("Exact permitted taxonomy key", anyOf=list(allowed_keys))

            @property
            def arguments_schema(self):
                return self.Arguments.generation_schema()

            async def call(self, args):
                key = args.value(str, for_property="key")
                if key not in context.taxonomy:
                    raise ValueError("taxonomy key is not permitted")
                context.record(self.name)
                return bounded_json({key: context.taxonomy[key]})
        tools.append(TaxonomyLookup())
    return tools


def bounded_json(value: Any) -> str:
    encoded = json.dumps(value, ensure_ascii=False, separators=(",", ":"))
    if len(encoded) > MAX_RESULT_CHARACTERS:
        raise ValueError("tool result exceeds its length limit")
    return encoded
