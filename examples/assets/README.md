# Example Assets

`complex_demo_loop.wav` is bundled for repeatable file-audio testing.

For logos or show-specific art, place your own files in this directory and
reference them from a scene:

```ruby
layer :logo do
  type :svg
  file "assets/your_logo.svg"
  fit :contain
  map beat_pulse, to: :scale, range: 0.9..1.08
end
```

No copyrighted venue logos, artist marks, photos, or fonts are bundled with
Vizcore examples. Keep those assets local to your project unless you have the
right to redistribute them.
