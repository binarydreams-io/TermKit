# TermKitPlayer

Run an adaptive terminal player that demonstrates public TermKit APIs.

## Run The Example

Run the executable from the repository root:

```bash
swift run --package-path Examples TermKitPlayer
```

The player adapts across full, medium, compact, and minimum layouts.
It uses original PNG and JPEG artwork, semantic controls, keyboard commands, pointer activation, and a scheduled spectrum.

Press Space to play or pause. Use `n` and `p` to change tracks, arrow keys to seek, and `q` or Escape to exit.

TermKitPlayer is a visual simulation. It does not load or produce audio.
