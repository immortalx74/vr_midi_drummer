## VR MIDI Drummer

### VR drumming app with MIDI output (Made with [LÖVR](https://lovr.org/))

**How to use:**

- Move a single kit piece: Point the right drumstick to a kit piece and hold `"a"` to move it

- Move the entire kit: Point the right drumstick to any kit piece and hold `"b"` to move

- Change UI interaction hand: Press either the left or right controller `trigger`

- Toggle UI interaction: Press the left `thumbstick` down

- Setup your DAW to accept input from the same MIDI port as the one selected in the app
  

NOTE: If you run the app from source you'll need `luamidi.dll` and `lua51.dll` on the same path as `lovr.exe`. Get it from the releases (inside the released app archive)

![vr_midi_drummer](https://i.imgur.com/P9vXdjh.png)

**VR MIDI Drummer uses these libraries:**
- [lovr-phywire](https://github.com/jmiskovic/lovr-phywire)
- [json.lua](https://github.com/rxi/json.lua)
