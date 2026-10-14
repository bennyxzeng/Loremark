# Loremark README artwork

| File | Origin | Use |
| :--- | :--- | :--- |
| `loremark-hero.png` | Generated with the built-in image generation tool, using the supplied character sheet as a reference. | README banner. |
| `loremark-character-sheet.png` | Original character sheet supplied by the project team, copied without changes. | Expandable mascot reference. |
| `loremark-companion-portrait.png` | Generated with the built-in image generation tool from the original character sheet. | Original library portrait, retained as an alternate. |
| `loremark-companion-portrait-clean.png` | Edited with the built-in image generation tool from the original portrait. | Simplified landscape portrait, retained as an alternate. |
| `loremark-companion-portrait-square.png` | Vertically expanded with the built-in image generation tool from the simplified portrait. | Cream-background square portrait, retained as an alternate. |
| `loremark-companion-portrait-soft-library.png` | Edited with the built-in image generation tool from the square portrait. | Soft library background with a cream foreground, retained as an alternate. |
| `loremark-companion-portrait-desk.png` | Edited with the built-in image generation tool from the soft library portrait. | Wooden-desk portrait, retained as an alternate. |
| `loremark-companion-front-view.png` | High-resolution redraw with the built-in image generation tool, based on the leftmost front view in the original turnaround panel. | Current full-body character profile illustration; a generative redraw, not a pixel-exact upscale. |
| `loremark-chibi-moments.png` | Generated with the built-in image generation tool from the original character sheet. | Original three-moment illustration, retained as an alternate. |
| `loremark-chibi-moments-v2.png` | Generated with the built-in image generation tool using the character sheet's bottom-row chibi proportions. | Current three-moment strip with exaggerated big-head, tiny-body chibi proportions. |

The generated images are illustrations, not application screenshots. All assets are stored in this repository so the README does not depend on temporary image URLs. The character profile draws on the supplied sheet; English dialogue is translated or adapted from its Chinese character notes. The chibi captions are new editorial copy.

## Front-view character redraw prompt

```text
Use case: identity-preserve
Asset type: high-resolution full-body FRONT VIEW character illustration for a README profile.
Input: Loremark original character design sheet. The EXACT target is the LEFTMOST standing figure in the panel labeled "Turnaround" in the lower left, above the chibi row. Recreate ONLY this front-view figure at high resolution. All other figures in the sheet are reference for details, NOT output subjects.
Faithfully preserve the front figure's design: long ash-brown hair and side braids, amber eyes, dark forest-green bows, cream high-collar blouse with frilled cuffs, green neck bow and gold star brooch, fitted dark waist/bodice with gold fastenings, short pleated dark skirt with cream lace hem, long open dark olive cloak with gold embroidery and pointed hanging panels, black thigh-high stockings with original garter details, black heeled ankle boots with gold hardware. Standing straight facing camera, both hands relaxed naturally at sides, feet visible, gentle neutral smile, same original normal anime proportions (not chibi). Preserve original silhouette and clothing; do not redesign, add props, or change pose.
Create a crisp premium high-definition restoration/redraw with delicate precise linework and soft polished painterly shading. Output one single character, full body from crown to soles with modest even margins. Tall portrait aspect ratio 2:3, at least 1024x1536, preferably 1536x2304 if possible. Plain warm ivory parchment backdrop and a very subtle ground shadow. No library, no cat, no books, no text, no labels, no Japanese name, no panel borders, no side/back views, no watermark. Character fills height; use restrained quiet space on sides.
```

## Chibi moments v2 prompt

```text
Use case: illustration-story
Asset type: wide 3:1 chibi mascot triptych for README.
Reference image: mascot identity and clothing reference, especially the TINY SUPER-DEFORMED CHIBIS along the BOTTOM ROW. Match those bottom-row proportions, NOT the tall anime illustrations.
Generate three equally sized, extremely cute super-deformed chibi Loremark figures centered at exactly 1/6, 1/2, 5/6 of the canvas width. Each figure and its props must fit entirely within its own equal-width third with generous matching margins. All three share the same ground baseline.
TRUE CHIBI: approximately TWO HEADS TALL total standing height, enormous round head roughly half the entire height, tiny compact body, very short stubby arms and legs, mitten-like tiny hands, huge expressive amber eyes, simplified chunky locks of ash-brown hair, forest-green ribbons, tiny gold star brooch, cream blouse and modest dark olive cape dress. No realistic anatomy or long legs. Clean polished anime sticker illustration with confident delicate outlines, soft cel shading and restrained watercolor accents. Simple warm ivory background, no scenes, no ornate decorative clutter.
LEFT: seated chibi happily reading a large open dark-green book, eyes joyfully curved, tiny sleeping calico cat beside her.
CENTER: seated chibi wearing round spectacles, pondering a small notebook with a tiny pencil, one simple question mark above her.
RIGHT: seated chibi hugging a closed dark-green book, winking and making a playful hush gesture with a tiny finger near her lips, one small gold sparkle.
All full figures visible, consistent character size and art style, warm cream/sage/antique gold colors. No text captions, no panel borders, no lettering except the single question mark, no watermark. Distinctively adorable mascot sticker proportions, not merely a smaller normal anime girl.
```

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

