# Writing Style Guidelines

When writing documentation for this project (Typst, Markdown, or any prose), follow
these rules:

## No bold

Avoid using bold text for emphasis. Instead, rephrase the sentence to naturally highlight
the important part.

## No colons mid-sentence

Do not use a colon in the middle of a running sentence. Rewrite so the thought flows
naturally. Use a full stop and start a new sentence instead.

- Instead of: "The idea is simple: every bit is a burst followed by a space."
  Write: "The idea is simple. Every bit is a burst followed by a space."

- Instead of: "The fix was a flag: repeats are only accepted after a valid frame."
  Write: "The fix was a flag. Repeats are only accepted after a valid frame."

## Avoid em dashes

Do not use em dashes (—) in running prose. Rewrite the sentence instead so it flows
naturally without them. For example:

- Instead of: "The other protocols follow the same idea — so NEC is covered here."
  Write: "The other protocols follow the same idea, so NEC is covered here."

- Instead of: "The frame doesn't repeat — instead it sends a repeat code."
  Write: "The frame doesn't repeat. Instead it sends a repeat code."

Em dashes are acceptable inside figure captions where they separate a label from a
short description (e.g. "NEC bit encoding — logical 1 uses 2.25 ms"), but avoid them
in regular paragraph text.

## Tone

Write in a natural, slightly conversational tone. Documentation should read like a
knowledgeable person explaining something clearly, not like a formal specification.
Short sentences are fine. Contractions (doesn't, it's) are allowed where they help
the text feel less stiff.
