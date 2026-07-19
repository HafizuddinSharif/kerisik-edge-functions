# 010 — Recipe Image Gallery

`20260719000000_add_recipe_image_gallery.sql` adds `kerisik.recipes.image_urls jsonb`, limited by a database check to ten entries. Existing `image_url` values are backfilled as a one-item gallery and remain the cover field for older clients.

The mobile implementation and verification notes are in `nak-beli-apa-v2/docs/010-recipe-image-gallery.md`.
