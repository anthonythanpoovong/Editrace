# Exporters

Export templates to professional editing software.

## Supported Formats

### OpenTimelineIO (OTIO) → DaVinci Resolve / Premiere / Final Cut Pro
- `otio_exporter.py` — Template → OTIO → FCPXML
- Exports cuts, speed ramps, text overlays
- Test suite for round-trip validation

### CapCut
- `capcut_exporter.py` — Template → CapCut draft format
- Generates downloadable CapCut project
- Version-pinned test suite

## Testing

- Round-trip tests on example templates
- Verify exported projects open correctly in target software
- Maintain test suite as software versions update

## Generated Code

Uses Pydantic models **generated from `schema/template.schema.json`**. Regenerate if schema changes.
