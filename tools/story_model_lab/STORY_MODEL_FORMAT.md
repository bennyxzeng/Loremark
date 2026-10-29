# Story Model: file structure and labels

[![English](https://img.shields.io/badge/English-2563EB?style=for-the-badge)](STORY_MODEL_FORMAT.md) [![简体中文](https://img.shields.io/badge/%E7%AE%80%E4%BD%93%E4%B8%AD%E6%96%87-64748B?style=for-the-badge)](STORY_MODEL_FORMAT.zh-CN.md)

[Back to README](README.md) · [File structure](#file-structure) · [Characters and records](#characters-and-records) · [Events](#events) · [Labels](#labels) · [Revisions](#revisions) · [Single-chapter format](#single-chapter-format)

A Story Model records **who and what the text introduces, what happens, how entities relate, what remains uncertain, and which passages support each claim**. It also preserves when the reader learned something and how later sections change that knowledge.

The cumulative example is [`stores/86v1/story_model.json`](stores/86v1/story_model.json). [`ch2_story_model.md`](../../ch2_story_model.md) is a readable, static export. This guide primarily describes the cumulative **v2** format; the **v1** single-chapter format is explained at the end.

Two labels answer different questions: `assertion: "inferred"` means a claim is inferred from the text; `temporal_context: "past"` means it concerns the narrative's past, including a **flashback**. **`flashback` is not a stored enum value.** A past event can be `explicit`, `reported`, or `inferred`.

## File structure

### Files around the model

| Path | What it contains |
| --- | --- |
| `stores/<name>/story_model.json` | The latest committed cumulative model; this is the file to inspect for current accumulated knowledge. |
| `stores/<name>/revisions/<revision>-<id>.json` | A full snapshot of each committed revision, preserving what was known then. |
| `stores/<name>/inputs/<section>-<hash>.json` | Normalized section text and paragraph IDs used to check evidence. |
| `stores/<name>/provenance/` | Initial import and update artifacts, ID mappings, manifests, and correction history. |
| `runs/<run-id>/story_model.json` | A validated **v1 single-chapter** result from `generate`, before `init`. |
| `runs/<run-id>/story_model.after.json` | A candidate cumulative model from an update; its presence alone does not mean it was committed. |
| An exported `.md` file | A readable view of one revision; exporting again is required to refresh it. |

The tracked example JSON and revision snapshots are readable on their own. Running `show` or `update` also requires the matching local `inputs/` and `provenance/`; see [Sharing the model with teammates](README.md#sharing-the-model-with-teammates).

### Inside a v2 `story_model.json`

| Top-level field | Contents and purpose |
| --- | --- |
| `schema_version` | `"2.0"`: the file format version. |
| `scope` | `"cumulative"`: knowledge accumulated across processed sections. |
| `book` | `title` and `epub_sha256`, identifying the source book and exact EPUB file. |
| `revision` | `number`, `id`, `created_at`, `source_run_id`, `parent_snapshot_path`, and `parent_sha256`: this commit and its link to the previous snapshot. Parent fields are `null` for the first revision. |
| `processed_sections` | Each section's `section_id`, reading order (`section_order`), `chapter_number`, `title`, EPUB `href`/`fragment`, `text_sha256`, `extraction_version`, `paragraph_count`, saved input path/hash (`input_relative_path`, `input_file_sha256`), and `introduced_revision`. Non-numbered sections can have `chapter_number: null`. |
| `coverage` | `start_section_id` and `omitted_prefix_section_ids`: where extraction started and which earlier sections were not processed. |
| `entities` | Characters, locations, and organizations, each with a stable `id`, `kind`, and `introduced_revision`. Names and facts live separately in `records`. |
| `records` | Seven collections: `names`, `aliases`, `attributes`, `relationships`, `events`, `uncertainties`, and `identity_links`. Old records are retained unchanged. |
| `transitions` | Evidence-backed changes to earlier records: replacement, retraction, or resolution of a question. |
| `current` | A computed index containing `active_record_ids`, `resolved_uncertainty_ids`, and `identity_groups`. |
| `provenance` | `initial_run_id`, `migration_version`, `imported_manual_corrections`, and `update_manual_corrections`: origin and audit history. Older stores may omit `update_manual_corrections`. |

A **section** may be a chapter, prologue, or interlude. `section-004`, Chapter 1, and revision 1 describe different things: reading-order section ID, numbered chapter, and successful import/update count. Check `processed_sections` and `coverage` before assuming the model covers everything before a chapter.

## Characters and records

### Entity types and IDs

| `entities[].kind` | ID example | What belongs here |
| --- | --- | --- |
| `character` | `c001` | Individual people or beings treated as persons, including those only mentioned. |
| `location` | `l001` | Places: countries, cities, buildings, rooms, battlefields, etc. |
| `organization` | `g001` | Groups acting collectively: governments, militaries, squads, institutions, factions, etc. |

For example, a squad is an organization, its captain is a character, and its base is a location. Entity IDs stay stable across cumulative updates; changing a name does not change the entity's ID.

### The wrapper shared by every record

Each item in any of the seven `records` collections has these fields:

| Field | Meaning |
| --- | --- |
| `id` | Stable knowledge-record ID, such as `f000123`. This identifies one claim, not a character or event category. |
| `introduced_revision` | The revision in which this record was added. |
| `learned_in_section_id` | The section that revealed the information to the reader, even if the event happened much earlier in the story. |
| `legacy_id` | Original v1 ID when applicable, such as `r001` or `e001`; otherwise `null`. |
| `payload` | The claim itself, with fields determined by its collection. |
| `evidence` | Supporting passages: `{section_id, paragraph_id, quote}`. Paragraph IDs are local to a section, so use both IDs to locate a quote. |

Quotes must be exact, contiguous substrings of the cited paragraph, at most 300 characters. Every record needs evidence. New update records and transitions cite the **new section**. A matching quote proves that the words occur there; a reviewer must still judge whether they support the claim.

### The seven knowledge collections

| Collection | What it records | Fields inside `payload` |
| --- | --- | --- |
| `names` | An entity's primary name or designation, including a title or call sign when no personal name is known. | `entity_id`, `text` |
| `aliases` | Other designations shown by the text to refer to the same entity. | `entity_id`, `text` |
| `attributes` | Individual facts about an entity: age, rank, appearance, occupation, affiliation, ability, etc. | `entity_id`, `label`, `value`, `assertion`, `attributed_to_id` |
| `relationships` | Directed links between entities, with a one-sentence description and time context. | `source_id`, `target_id`, `label`, `description`, `assertion`, `attributed_to_id`, `temporal_context` |
| `events` | Individual actions, occurrences, or revelations, with participants, place, narrative order, and time context. | `description`, `participant_ids`, `location_id`, `narrative_order`, `temporal_context`, `story_time`, `assertion`, `attributed_to_id` |
| `uncertainties` | Open questions about identity, references, causes, or conflicting claims. | `question`, `related_entity_ids` |
| `identity_links` | Claims that two separately recorded entities are actually the same person, place, or organization. | `left_entity_id`, `right_entity_id`, `assertion`, `explanation` |

An attribute `label` such as `rank` and a relationship `label` such as `member_of` are descriptive strings, not fixed enum lists. Read a relationship as **source → label → target**: `c001 → member_of → g001` means the character belongs to the organization; reversing the endpoints changes the meaning. Relationships can connect any of the three entity kinds.

Not every collection carries every label: `assertion` appears on attributes, relationships, events, and identity links; `temporal_context` appears only on relationships and events. Names, aliases, and uncertainties have evidence but no `assertion` field. Attributes do not have a separate time-context field in this schema.

An alias names an entity already recognized as one entity. An identity link connects **two existing IDs** of the same kind. Only active `explicit` links produce `current.identity_groups`, whose fields are `canonical_id`, `member_ids`, and `link_record_ids`. The earliest-introduced entity supplies the canonical ID (ties use ID order); original entities and records remain intact. `reported` and `inferred` links do not merge identities for display.

## Events

| Event `payload` field | How to read it |
| --- | --- |
| `description` | One main action or occurrence, rather than a summary of an entire paragraph. |
| `participant_ids` | IDs of participating characters or organizations. |
| `location_id` | The location entity's ID, or `null` when the place is not identifiable. |
| `narrative_order` | Order in which this section tells the events: 1, 2, 3, …, with no gaps or repeats within that section. It is not a whole-book timeline. |
| `temporal_context` | Whether the event is current, past, future, hypothetical, or of unknown time relative to the section's present narrative. |
| `story_time` | Time wording supplied by the text, such as `"spring"` or `"nine years ago"`; `null` if unspecified. Dates are not calculated or invented. |
| `assertion` | Whether the event is directly stated, reported by a source, or inferred. |
| `attributed_to_id` | Character/organization making a `reported` claim, when known; otherwise `null`. |

This **synthetic example** is one record inside `records.events`; assume `c001` is Mira and `l001` is the harbor:

```json
{
  "id": "f000042",
  "introduced_revision": 2,
  "learned_in_section_id": "section-005",
  "legacy_id": null,
  "payload": {
    "description": "Mira witnessed a fire at the harbor as a child.",
    "participant_ids": ["c001"],
    "location_id": "l001",
    "narrative_order": 3,
    "temporal_context": "past",
    "story_time": "As a child",
    "assertion": "explicit",
    "attributed_to_id": null
  },
  "evidence": [
    {
      "section_id": "section-005",
      "paragraph_id": "p0012",
      "quote": "As a child, Mira watched the harbor burn."
    }
  ]
}
```

The reader learns this in `section-005`, where it is the third extracted event in narrative order. The fire belongs to the story's past. Its `past` label does not move it to an earlier extraction section or reveal it in a revision saved before `section-005`.

## Labels

### `assertion`: how the text supports a claim

| Value | Meaning | Synthetic example |
| --- | --- | --- |
| `explicit` | Narration states it directly. | The narrator says Mira is a captain. |
| `reported` | A character or in-world source makes a claim; it may be false, a rumor, or propaganda. | A broadcast claims that nobody died. |
| `inferred` | Not directly stated, but reasonably deduced from cited text. The wording should make the inference clear. | Several clues suggest that Mira knew the visitor. |

`attributed_to_id` identifies a known speaker or source for `reported`, using a character or organization ID; use `null` when the source is unknown. It must be `null` for `explicit` and `inferred`. Identity links do not have this field.

The distinction depends on the **claim being recorded**: “a broadcast announced zero casualties” can be an explicit event describing the announcement; “there were zero casualties” is a reported claim when supported only by that broadcast. `inferred` is not a confidence score, and the schema has no confidence percentages.

### `temporal_context`: when the claim holds in the story

| Value | Meaning | Synthetic example |
| --- | --- | --- |
| `current` | True or happening in the section's present narrative. | Mira enters the harbor now. |
| `past` | Earlier than the present narrative: flashback, memory, or backstory. | The text recalls the harbor fire from Mira's childhood. |
| `future` | Planned, scheduled, or predicted; this alone does not establish that it happens. | The squad plans to leave tomorrow. |
| `hypothetical` | Imagined, conditional, or counterfactual. | If the gate fell, the city would be exposed. |
| `unknown` | The text does not establish the time frame. | An incident is mentioned without enough context to place it. |

**Flashbacks use `past`; there is no separate `flashback` value.** These labels combine independently with `assertion`: `explicit` + `past` is a directly narrated past event; `reported` + `past` is someone's account of the past; `inferred` + `past` is a deduction about it. `future` can describe a plan already known at the reading cutoff; it does not mean the model has read later chapters.

Keep these three notions separate:

| Field | Question it answers |
| --- | --- |
| `learned_in_section_id` / `introduced_revision` | When did the reader learn this? |
| `temporal_context` / `story_time` | When does it happen or hold inside the story? |
| `current.active_record_ids` | Which records are still active in this saved revision? |

An active record may describe the past, a future plan, or an unconfirmed report. Being active does not establish truth or mean `temporal_context: "current"`.

## Revisions

Later sections add records and transitions instead of overwriting old claims. A transition has `id` (such as `t000001`), `introduced_revision`, `learned_in_section_id`, `target_record_id`, `action`, `replacement_record_id`, `resolution`, `reason`, and `evidence`.

| `action` | Meaning | Other fields |
| --- | --- | --- |
| `supersede` | A new record replaces an earlier active record, e.g. a new rank or a revealed primary name. | `replacement_record_id` points to the new record; `resolution` is `null`. |
| `retract` | A later section disproves an earlier claim without replacing it. | `replacement_record_id` and `resolution` are `null`. |
| `resolve` | A later section answers an open uncertainty. | `resolution` contains the answer; `replacement_record_id` is `null`. Only uncertainties can be resolved. |

Targets must be active records from an earlier revision. Replacement stays in the same collection and concerns the same subject: attributes keep the same entity and label; relationships keep the same direction, label, and time context. A relationship with a different label uses a retraction plus a new record. Replacing events or uncertainties still needs human review of whether they concern the same thing.

All three actions deactivate the target record without deleting it. Resolved questions also appear in `current.resolved_uncertainty_ids`; an answer that is itself a new fact needs its own record. The program computes `current` from this history. An unmentioned fact remains active. A flashback adds a `past` record rather than replacing a `current` relationship with a past one.

Use a saved revision to read the knowledge available then; a historical view must not borrow later names, identity links, or answers. Revision numbers count committed imports/updates, so an interlude also creates a revision.

## Single-chapter format

Before `init`, a successful `generate` run saves this **v1** envelope:

```text
story_model.json
├── schema_version: "1.0"
├── scope: "single_chapter"
├── source: book/chapter metadata, EPUB location, hashes, paragraph count
└── model
    ├── characters[]
    ├── locations[]
    ├── organizations[]
    ├── relationships[]
    ├── events[]
    └── uncertainties[]
```

Each character/location/organization contains `id`, an evidence-backed `name`, evidence-backed `aliases`, and `attributes` directly. Relationships use `r001`-style IDs and events use `e001`-style IDs. Uncertainties contain the question, related entity IDs, and evidence, without their own ID. Evidence is `{paragraph_id, quote}` because there is only one source section. The same assertion and time-context values apply.

V1 has no cumulative `records` wrapper, transitions, current index, or identity-link collection. `init` migrates it to v2: it preserves entity IDs, assigns `f…` record IDs, keeps applicable original IDs in `legacy_id`, and adds section IDs to evidence. Single-chapter IDs do not establish identity across independent runs.

The exact definitions are in [`schemas.py`](src/loremark_story_lab/schemas.py) (v1) and [`cumulative_schemas.py`](src/loremark_story_lab/cumulative_schemas.py) (v2). Extraction rules are in the [single-chapter prompt](src/loremark_story_lab/prompts/extract_story_v1.txt) and [update prompt](src/loremark_story_lab/prompts/update_story_v1.txt).
