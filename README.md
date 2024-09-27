## VR MIDI Drummer

### VR drumming app with MIDI output (Made with [LÖVR](https://lovr.org/))
[NEW] It now includes build-in drum samples. To set the ouput mode to MIDI select the corresponding radio-button near the bottom of the UI panel.

**How to use:**

- Move a single kit piece: Point the right drumstick to a kit piece and hold `"a"` to move it

- Move the entire kit: Point the right drumstick to any kit piece and hold `"b"` to move

- Change UI interaction hand: Press either the left or right controller `trigger`

- Toggle UI interaction: Press the left `thumbstick` down

- Setup your DAW to accept input from the same MIDI port as the one selected in the app

- If you use Reaper you can use the `x` and `y` buttons on the left controller to Fast forward/Rewind the song you play along. To set this up follow [this](https://www.youtube.com/watch?v=YLQmzY_kWnk) guide. Other DAWs should be able to do that too 
  

NOTE: If you run the app from source you'll need `luamidi.dll` and `lua51.dll` on the same path as `lovr.exe`. Get it from the releases (inside the released app archive). Also, the source code targets the latest dev of LÖVR, so it won't work with stable v0.17.1 and lower.


**Example MIDI setup guide using Reaper:**

- Download and install [loopMIDI](https://www.tobias-erichsen.de/software/loopmidi.html)
- Click the `+` button on bottom left to add a MIDI port
- In Reaper create a new track and right-click on the tracks's Arm/Disarm button->`Input: MIDI`->`loopMIDI Port`->`All channels`
- Make sure to set your audio device to ASIO for low latency. If you don't have an ASIO capable interface you can use [ASIO4ALL](https://asio4all.org/about/download-asio4all/)
- Load your favorite drum VST (I'm using the free version of [Steven Slate Drums 5.5](https://stevenslatedrums.com/ssd5/#SSD5FREE))
- Arm the track and launch VR MIDI Drummer
- On the floating window under `MIDI Ports` select the `loopMIDI Port`
- You should now be able to hear the drum sounds (you might also need to set "Monitor input" to on)
- If you own a USB footpedal you can set it up to trigger a keyboard key by using [JoyToKey](https://joytokey.net/en/download) or a similar utility
- By default the kick is mapped to the `Space` key. You can change this mapping by selecting the kick piece in the floating window and clicking on the `Assign key...` button
- Similarly, the hihat open/closed is mapped to the `h` key by default

![vr_midi_drummer](https://i.imgur.com/62M2v9n.png)

**VR MIDI Drummer uses these libraries:**
- [lovr-phywire](https://github.com/jmiskovic/lovr-phywire)
- [json.lua](https://github.com/rxi/json.lua)
