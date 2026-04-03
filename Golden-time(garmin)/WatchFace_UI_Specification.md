# Garmin Watch Face UI Specification

This specification defines UI layout and drawing rules for the Golden-time watch face, based on Garmin Connect IQ UX guidelines and community best practices. Its purpose is to provide a clear, executable UI policy for Codex or other AI agents when modifying or implementing UI elements.

## 1. Drawing Order and Layering

- **Background first**: Always draw the background bitmap as the first layer.
  Example: `dc.drawBitmap(0, 0, background);`
- **Text and dynamic data after background**: All text, dynamic values, or UI components must be drawn after the background.
- Drawing order must not be reversed or interleaved to avoid text being occluded by later draw calls.

## 2. Coordinate System and Safe Area

- Garmin watch faces use screen coordinates where (0, 0) is the top-left corner and (width, height) is the bottom-right.
- For circle screens, ensure all text is within the **circular safe zone** (radius < device radius - margin).
- Never place important text less than 20px from the physical edge (safe margin).  
  This ensures text is not clipped on any device shape.

## 3. Fonts and Text Layout

### 3.1 Custom Font Loading & Usage

- Custom fonts must be loaded once via `Ui.loadResource()` and reused, not loaded every frame. This ensures performance and memory efficiency.  [oai_citation:1‡佳明论坛](https://forums.garmin.com/developer/connect-iq/f/discussion/401610/best-practice-for-loading-strings-fonts-and-settings-in-watch-face-with-background-and-typecheck/1887777?utm_source=chatgpt.com)
- When using custom fonts:
- Place `.fnt` and corresponding `.png` in `resources/fonts`.
- Reference in `resources.xml` and load in `onLayout()` or `initialize()` to avoid repeated loads.  [oai_citation:2‡佳明论坛](https://forums.garmin.com/developer/connect-iq/f/discussion/401610/best-practice-for-loading-strings-fonts-and-settings-in-watch-face-with-background-and-typecheck/1887777?utm_source=chatgpt.com)

### 3.2 Font Size & Cross-Device Consistency

- Built-in fonts map to different actual pixel sizes on different devices; for numbers/time consider using numeric fonts (e.g., `Graphics.FONT_NUMBER_*`) to reduce width variance across devices.  [oai_citation:3‡Garmin开发者](https://developer.garmin.com/connect-iq/connect-iq-faq/how-do-i-use-custom-fonts/?utm_source=chatgpt.com)
- For truly custom typography or branding, use multiple font sizes and load them selectively based on device resolution.

## 4. Resource Management

- Place bitmaps in `resources/drawables` and declare them in `drawables.xml`.
- Load resources once (e.g., in `onLayout` or `initialize`) and reuse the loaded object.
- Avoid loading bitmaps/fonts every frame, which negatively impacts performance.

### 4.1 Responsive Resource Variants

- You can define resource variants per device (e.g., high-resolution vs low-resolution) via separate folders and conditional resource naming. This helps maintain visual fidelity across screen sizes.

## 5. Color and Contrast

- Text must have sufficient contrast against the background for outdoor readability.
- Use predefined color constants when possible (e.g., `Gfx.COLOR_WHITE`, `Gfx.COLOR_YELLOW`).
- For dynamic labels such as Blue and Golden, assign distinct colors for difference:
  - Blue countdown: white
  - Golden countdown: yellow

## 6. Bottom Info Region Layout (Blue / Golden)

- The bottom region must be horizontally balanced: two columns (Blue / Golden).
- Use equal spacing between the two columns.
- Vertical spacing:
  - Label at baseline y
  - Value below label y + fontHeight(label) + fixedGap
- Do not use “fit to circle” per line; apply safe zone checks on the **entire block**.
- If the bottom block does not fit, shift the entire block upward, not individual lines.

### 6.1 Alternative Text Layout with TextArea

- For complex multi-text alignment, consider using `WatchUi.TextArea` instead of raw `dc.drawText`.  
  - A `TextArea` object can manage its own bounding box, justification, and layout, simplifying multi-line text.  [oai_citation:4‡Garmin开发者](https://developer.garmin.com/connect-iq/api-docs/Toybox/WatchUi/TextArea.html?utm_source=chatgpt.com)
  - Example: construct a `TextArea` with width/height constraints so text wraps or centers within a defined box.
- `TextArea` also allows dynamically updating text without manual coordinate recalculation.

## 7. Placeholder Display and Fallbacks

- If a dynamic value is missing, show a placeholder like `--:--`.
- Do not hide the text element entirely; hidden text can break layout balance.
- Always draw all regions even with placeholders.

## 8. Device Variants and Scaling

- Different Garmin devices have different resolutions; prefer dynamic layouts over hardcoding:
  - Use `dc.getWidth()` / `dc.getHeight()` as base.
  - Compute centered positions as `cx = width / 2`.
- On round devices, ensure x/y positions respect circular boundaries.
- For cross-device compatibility, compute relative positions e.g., center offsets based on total height.

### 8.1 Responsive Layout Strategies

- Use layout tiers based on screen height/width breakpoints. For example:
  - Small screens: smaller font sizes, tighter spacing
  - Medium screens: standard layout
  - Large screens: optional enhanced layout
- Avoid hard-coded pixel positions where possible; prefer ratios (e.g., 0.3 * width) so UI adapts fluidly.

### 8.2 Localization/Internationalization Considerations

- All user-visible strings (e.g., day names, labels) should use resources (`Rez.Strings.*`) and not be hard-coded.  [oai_citation:5‡Garmin开发者](https://developer.garmin.com/connect-iq/user-experience-guidelines/?utm_source=chatgpt.com)
- String length varies by language; account for multi-byte/long text in layout logic.

## 9. Performance and Update Frequency

- Watch face UI updates at regular intervals (often once per minute).  
- Avoid heavy computations in `onUpdate`.
- Precompute layout positions in `onLayout` if possible.

## 10. Text Rendering APIs

When using `WatchUi.TextArea`, follow API specs:
var ta = new WatchUi.TextArea({
:text => textValue,
:font => Graphics.FONT_MEDIUM,
:color => Graphics.COLOR_WHITE,
:justification => Graphics.TEXT_JUSTIFY_CENTER
});
ta.draw(dc);
(TextArea allows convenient bounding box layouts)  [oai_citation:0‡developer.garmin.com](https://developer.garmin.com/connect-iq/api-docs/Toybox/WatchUi/TextArea.html?utm_source=chatgpt.com)

### 10.1 Text Measurement & Performance

- Before placing text, measure its dimensions with `dc.getTextWidthInPixels()` and `dc.getFontHeight()`.  
  This supports responsive centering and avoids clipping.  [oai_citation:6‡Garmin开发者](https://developer.garmin.com/connect-iq/user-experience-guidelines/watch-faces/?utm_source=chatgpt.com)
- While `TextArea` simplifies layout, remember it still calls draw under the hood; minimize object creation per frame.

---

## Example Layout Rules (for Codex to implement)

- Time label:
  - Font: `Gfx.FONT_LARGE`
  - Center at `(screenWidth/2, timeY)`
- Date label:
  - Font: `Gfx.FONT_MEDIUM`
  - Center at `(screenWidth/2, dateY)`
- Blue / Golden bottom:
  - Left X = screenWidth * 0.30
  - Right X = screenWidth * 0.70
  - Labels top Y = bottomSafeZone
  - Values below labels with consistent gap

---

## Notes

- Layout may combine **layout.xml** and direct `dc.drawText` calls depending on project structure.
- XML layouts can define static positions, but dynamic text still needs measure checks in code.  [oai_citation:1‡medium.com](https://medium.com/%40JoshuaTheMiller/making-a-watchface-for-garmin-devices-8c3ce28cae08?utm_source=chatgpt.com)
- Custom fonts must be defined in resources and loaded using `Ui.loadResource`.  [oai_citation:2‡forums.garmin.com](https://forums.garmin.com/developer/connect-iq/f/discussion/2193/using-custom-fonts?utm_source=chatgpt.com)