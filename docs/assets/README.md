# Loremark README artwork

| File | Origin | Use |
| :--- | :--- | :--- |
| `loremark-hero.png` | Generated with the built-in image generation tool, using the supplied character sheet as a reference. | README banner. |
| `loremark-character-sheet.png` | Original character sheet supplied by the project team, copied without changes. | Expandable mascot reference. |
| `loremark-companion-portrait.png` | Generated with the built-in image generation tool from the original character sheet. | Original library portrait, retained as an alternate. |
| `loremark-companion-portrait-clean.png` | Edited with the built-in image generation tool from the original portrait. | Simplified landscape portrait, retained as an alternate. |
| `loremark-companion-portrait-square.png` | Vertically expanded with the built-in image generation tool from the simplified portrait. | Cream-background square portrait, retained as an alternate. |
| `loremark-companion-portrait-soft-library.png` | Edited with the built-in image generation tool from the square portrait. | Soft library background with a cream foreground, retained as an alternate. |
| `loremark-companion-portrait-desk.png` | Edited with the built-in image generation tool from the soft library portrait. | Current character profile with a wooden reading desk. |
| `loremark-chibi-moments.png` | Generated with the built-in image generation tool from the original character sheet. | Three illustrated reading-companion moments. |

The generated images are illustrations, not application screenshots. All assets are stored in this repository so the README does not depend on temporary image URLs. The character profile draws on the supplied sheet; English dialogue is translated or adapted from its Chinese character notes. The chibi captions are new editorial copy.

## Wooden desk foreground edit prompt

```text
Use case: precise-object-edit
Edit target: supplied square anime Loremark portrait.
Change ONLY the cream fabric-covered foreground surface to an uncovered wooden reading desk. Replace all visible cream cloth below the character with a flat warm medium-walnut tabletop, restrained natural wood grain receding in correct perspective, softly polished matte finish and gentle window-light reflections. No cloth, no folds, no tablecloth. Keep the desk clean with no added objects.
Preserve exactly the square composition and framing, character identity, face, eyes, expression, hair, costume, hands, gold leaf bookmark and ribbon, held book, sleeping calico cat and its book. They rest naturally on the wooden surface with appropriate contact shadows. Preserve the existing softly blurred library background, window and warm afternoon lighting. Keep the character sharp and dominant. No changes to pose or scale, no extra props, no text, no watermark. High-quality anime illustration matching the original.
```

## Soft library background edit prompt

```text
Use case: precise-object-edit
Edit target: supplied square Loremark portrait.
Primary request: restore a cozy library background, but keep it simplified and subordinate to the character.
Preserve the square 1:1 canvas, framing, character size and position, entire visible hair, facial identity, amber eyes, smile, forest-green ribbons, cream blouse, olive and gold embroidered cloak, gold star brooch, both hands, offered gold leaf bookmark, held ornate book, sleeping calico cat and its book. Preserve the polished anime style and the simple cream tabletop foreground.
Replace only the plain cream backdrop with a tasteful softly defocused reading room: muted walnut bookshelves with a few broad groups of books on the left, a simple window with soft warm late-afternoon light on the right, quiet warm plaster wall around the head. Background has low contrast, reduced saturation, soft edges, shallow depth of field, large calm shapes. It is recognizable as a library but not filled with individually detailed objects. Keep the face, eyes, hands and bookmark sharply rendered and visually dominant. Harmonize lighting with warm gentle highlights and atmospheric background shadows. Maintain space above the head from the square composition. No additional foreground props, no hanging foliage, no intricate architecture, no candles, no large lamps, no clockwork, no magical particle clutter, no text or borders. Remove the isolated floating star accents if they compete with the scene. Elegant restrained background, richly detailed character. Do not revert to a landscape crop.
```

## Square companion portrait expansion prompt

```text
Use case: precise-object-edit
Edit target: supplied landscape Loremark character portrait.
Task: OUTPAINT vertically above and below to create a SQUARE 1:1 image, ideally 1536x1536, for a README two-column character profile. The original landscape composition should occupy the middle two thirds of the new square. Keep original horizontal field of view and subject scale; do not crop left or right, do not stretch or distort.
Preserve the same character identity, face, pose, amber eyes, ash-brown hair, ribbons, modest cream blouse, olive embroidered cape, gold star brooch, hands offering the leaf bookmark, held book, sleeping calico cat and its book. Extend the top to show the complete crown of her hair with comfortable headroom, seamlessly continuing the warm ivory background. Extend the bottom with a natural continuation of the cream tabletop, soft shadows, and the end of the ribbon/bookmark where appropriate. Redistribute added space tastefully, about half above and half below. Background must stay simple cream with the existing restrained gold stars; no library, no new decorations, no clutter. Preserve polished anime illustration quality, colors and gentle lighting. No text, no borders, no watermark. Opaque background. The critical change is increased image HEIGHT, square aspect ratio, NOT another landscape image.
```

## Simplified companion portrait edit prompt

```text
Use case: precise-object-edit
Edit target: the supplied Loremark companion portrait.
Primary request: simplify the busy background and foreground so the character stands out clearly in a README character profile.
Preserve exactly the same character identity, face, amber eyes, ash-brown hair, gentle smile, forest-green ribbons, modest cream blouse, embroidered olive cloak, star brooch, body pose, hands, ornate book held against her chest, and gold leaf-shaped bookmark being offered toward the viewer. Preserve the sleeping calico cat on the lower left.
Replace the entire detailed library background with a clean warm ivory/cream background, a very subtle diffuse warm glow, and only two or three tiny muted gold star accents. Remove all bookshelves, windows, buildings, hanging foliage, lamps, candles, clockwork, background furniture, and numerous sparkles. Simplify the cluttered foreground into a quiet cream surface with the cat resting on just one closed dark-green book. Remove the other foreground books, inkpots, objects and decorative flowers.
Keep the original polished anime drawing style and refined character detail. Soften the harsh orange rim lighting slightly to harmonize with the cream backdrop. Airy, calm, uncluttered character-card presentation. Keep landscape 3:2 framing and existing character scale. No text, no borders, no watermark. Background remains opaque.
```

## Companion portrait prompt

```text
Use case: illustration-story
Asset type: anime character introduction illustration for Loremark GitHub README, landscape 3:2.
Input image: identity, costume, palette, and style reference only. Create a NEW scene of the SAME mascot.
Primary request: premium anime visual-novel key art of Loremark, the gentle bookish reading companion. Long ash-brown wavy hair with side braids, large warm amber eyes, forest-green hair ribbons, cream high-collared blouse with green bow and gold star brooch, dark olive cloak with delicate gold botanical embroidery. Waist-up three-quarter portrait in a cozy antique library at twilight. She faces the viewer with an inviting small smile, holding an ornate closed dark book against her chest with one arm, offering a gold leaf-shaped bookmark in her other hand. Modest clothing, faithful reference likeness. A sleeping calico cat is nestled beside books on the desk. Warm lamp light and soft cool evening window light; detailed hair, luminous eyes, refined linework and delicate painterly shading. Sage, parchment, walnut, antique gold. Character fills central composition; uncluttered soft-focus bookshelves and tiny restrained gold sparkles. Finished collectible character-card art, no text, no logos, no watermark, no panels.
```

## Chibi moments prompt

```text
Use case: illustration-story
Asset type: wide anime chibi vignette strip for a GitHub README, aspect ratio 3:1.
Input image: original character design reference. Preserve this character's identity and costume in chibi form.
Primary request: three beautifully drawn separate full-body chibi vignettes of the same Loremark mascot arranged horizontally with generous spacing on a clean warm ivory parchment background. She has long ash-brown wavy hair, amber eyes, forest-green ribbons, cream blouse, a modest dark olive and gold embroidered cape dress, gold star brooch, dark boots. Left: she sits smiling while reading a large open book, a calico cat curled beside her. Center: wearing round reading glasses, she studies an open notebook with a thoughtful expression, holding a pencil, one tiny question-mark symbol above her. Right: delighted but gently protective, holding a closed ornate book with a leaf-shaped bookmark, one finger in front of her lips in a playful hush gesture and one small gold star sparkle. Each pose should be distinct and expressive like premium anime sticker art, full figures visible with no cropped hair or feet. Crisp delicate lines, detailed costume simplification, soft painterly warm shading, harmonious parchment, sage and antique gold palette. No text labels, no speech bubbles, no watermark, no panel frames.
```

## Final banner prompt

```text
Use case: illustration-story
Asset type: premium GitHub README hero banner, wide landscape 3:1 composition.
Input image: character identity and art style reference only; create a new illustration, not a character sheet.
Primary request: beautiful Loremark reading companion brand illustration matching the supplied mascot: long flowing ash-brown hair, warm amber eyes, dark forest-green ribbons, cream blouse, dark olive cape with restrained gold embroidery and gold star ornament. Seated waist-up on the right in a warm old library, gently smiling down at an open ornate book, with a sleeping calico cat and a few stacked books. Modest cozy outfit, welcoming literary atmosphere. Rich polished anime illustration with detailed soft painterly shading, warm golden afternoon light, cream parchment, sage green, antique gold and walnut colors. Left 45 percent is airy cream parchment with subtle botanical decoration. Large elegant dark serif title on left reading exactly "Loremark" and smaller line exactly "Your Story, Your Pace." Fine understated gold frame. Refined book-cover design, excellent legibility at GitHub width. No additional text, no watermarks, no panels, no character turnaround.
```

