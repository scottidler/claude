# Advisor Configuration

## The problem

Setting `advisorModel` to anything other than Fable previously broke the ability to use
Fable as the main session model. To work around it, `advisorModel` was temporarily set
to `"fable"` (effectively disabling a separate advisor).

## The fix (2026-06-10)

`advisorModel` and `model` are completely independent settings:

- `model` - controls what model runs the main session
- `advisorModel` - controls what model backs the `advisor()` tool call only

Setting `advisorModel: "claude-opus-4-8"` does NOT affect `model`. Fable (or any other
model) can still be set as the main model without interference.

**Current state:**
```json
{
  "model": "opus",
  "advisorModel": "claude-opus-4-8"
}
```

## If advisor breaks Fable again

If setting `advisorModel` to a non-Fable model prevents Fable from being selected as
`model`, that is a Claude Code bug - not expected behavior. The two fields are documented
as independent in the settings schema. Revert `advisorModel` to `"fable"` as the
workaround until fixed.
