# Texture synchronization preference

- The user requests that texture changes for this UGC project be synchronized into existing project assets during the same task.
- Prefer exact texture basenames. The confirmed wall-texture directory is `Asset/SceneStaticMesh/Classroom/TEX/Tile_Wall`. If no same-name asset exists, ask the user for the destination before creating it. Resolve ambiguous duplicate names with the user when context is insufficient.
- Preserve resource paths and material references. Back up packages, update through editor APIs, save, and verify. PNG bytes must never replace `.uasset` package bytes directly.
- Store the corresponding source PNGs under `ExtendResource/TextureSources/`, mirroring the asset folders.
- Preserve existing texture settings unless requested otherwise. Current synchronization details and verification notes are in `Docs/Texture_sync_rules.md`.
