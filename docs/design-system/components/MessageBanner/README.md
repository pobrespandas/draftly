# MessageBanner

A dismissible floating message that an action shows with `app.displayInfoMessage` and related calls, in four severities.

Source: `Sources/Draftly/ActionMessageBanner.swift`. This card is an HTML rendition.

## Use

- Use one sentence. State the result, not the process ("Copied 230 characters to the clipboard.").
- Use `error` only when an action failed. Use `warning` when the person must know a limit.
- The severity symbol carries the meaning; color only supports it.

## Consumer provides

- `message` (string), `severity` (`info`, `success`, `warning`, `error`), and a `dismiss` callback.

## Anatomy and tokens

- Container: `material` fill, `radius-banner` (10px), 1px border in the severity color at 50%, `space-12` padding, `banner-max-width` 480px.
- Row: symbol, message, and an xmark dismiss button, `space-10` apart, top aligned.
- Severity: info `system-blue` + info.circle.fill; success `system-green` + checkmark.circle.fill; warning `system-orange` + exclamationmark.triangle.fill; error `system-red` + xmark.circle.fill.
- The symbol has an accessibility label with the severity name. The dismiss button is labeled "Dismiss message".
- In the High contrast theme, the border uses the full severity color, and error (`system-red`) and success (`system-green`) also differ in lightness.
