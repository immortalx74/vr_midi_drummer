## VR MIDI Drummer

### VR drumming app with MIDI output (Made with [LÖVR](https://lovr.org/))

**How to use:**

- Move a single kit piece: Point the right drumstick to a kit piece and hold `"a"` to move it

- Move the entire kit: Point the right drumstick to any kit piece and hold `"b"` to move

- Change UI interaction hand: Press either the left or right controller `trigger`

- Toggle UI interaction: Press the left `thumbstick` down

- Setup your DAW to accept input from the same MIDI port as the one selected in the app
  

NOTE: If you run the app from source you'll need `luamidi.dll` and `lua51.dll` on the same path as `lovr.exe`. Get it from the releases (inside the released app archive)


**Example setup guide using Reaper:**

- Download and install [loopMIDI](https://www.tobias-erichsen.de/software/loopmidi.html)
- Click the `+` button on bottom left to add a MIDI port
- In Reaper create a new track and right-click on the tracks's Arm/Disarm button->`Input: MIDI`->`loopMIDI Port`->`All channels`
- Make sure to set your audio device to ASIO for low latency. If you don't have an ASIO capable interface you can use [ASIO4ALL](https://asio4all.org/about/download-asio4all/)
- Load your favorite drum VST (I'm using the free version of [Steven Slate Drums 5.5](https://stevenslatedrums.com/ssd5/#SSD5FREE))
- Arm the track and launch VR MIDI Drummer
- On the floating window under `MIDI Ports` select the `loopMIDI Port`
- You should now be able to hear the drum sounds
- If you own a USB footpedal you can set it up to trigger a keyboard key by using [JoyToKey](https://joytokey.net/en/download) or a similar utility
- By default the kick is mapped to the `Space` key. You can change this mapping by selecting the kick piece in the floating window and clicking on the `Assign key...` button
- Hihat open/close isn't implemented for the time being

![vr_midi_drummer](https://i.imgur.com/P9vXdjh.png)

**VR MIDI Drummer uses these libraries:**
- [lovr-phywire](https://github.com/jmiskovic/lovr-phywire)
- [json.lua](https://github.com/rxi/json.lua)
