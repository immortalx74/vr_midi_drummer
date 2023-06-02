-- MIDI-controlled sampler
local sampler = {}
sampler.__index = sampler

sampler.logSamples = false

-- map from index to pitch, (C4 -> 1.0, C5 -> 2.0), equal temperament tuning
local function noteToPitch(noteIndex)
  return math.pow(math.pow(2, 1/12), noteIndex)
end


function sampler.new(settings)
  local self = setmetatable({}, sampler)
  self.synths = {} -- collection of sources in an array
  self.masterVolume = 1
  self.looped = settings.looped or false
  self.transpose = settings.transpose or 0
  self.envelope = settings.envelope or { attack  = 0,     -- default envelope best suited for
                                         decay   = 0,     -- one-shot samples, not for loopes
                                         sustain = 1,
                                         release = 0.35 }
  local synthCount  = settings.synthCount or 16

  self.samples = {}           -- list
  self.sample_from_note = {}  -- dict
  -- prepare samples that will be used by synths
  for i, sample in ipairs(settings) do
    sample.soundsource = lovr.audio.newSource(sample.path)
    sample.note = sample.note or 0
    sample.velocity  = sample.velocity or 0.8
    self.sample_from_note[sample.note] = sample
    table.insert(self.samples, sample)
  end

  -- initialize synths which will take care of playing samples as per notes
  for i=1, synthCount do
    self.synths[i] = {
      source = nil,
      volume = 0,
      active = false,
      duration = math.huge,
      enveloped = 0,
    }
  end
  return self
end


function sampler:findSample(note, velocity)
  local sample = self.sample_from_note[note]
  if not sample then return false end
  -- find sample with best match of desired velocity
  local bestFitness = math.huge
  local selected = nil
  for i, sample in ipairs(self.samples) do
    local fitness = math.abs(sample.velocity - velocity)
    if sample.note == note and fitness < bestFitness - .5 then
      selected = i
      bestFitness = fitness
    end
  end
  if sampler.logSamples then
    log(string.format('note = %d, pitch = %1.2f, sample = %s, distance = %d',
      note,
      noteToPitch(note - self.samples[selected].note),
      self.samples[selected].path,
      note - self.samples[selected].note
      ))
  end
  return self.samples[selected]
end


function sampler:playNote(id, note, velocity, location)
  self.location = Vec3(location)
  -- find synth with longest duration
  local maxDuration = -100
  local selected = nil
  for i, synth in ipairs(self.synths) do
    if synth.duration > maxDuration + (synth.active and 10 or 0) then
      maxDuration = synth.duration
      selected = i
    end
  end
  local synth = self.synths[selected]
  -- init and play
  if synth.source then
    synth.source:stop()
  end
  local sample = self:findSample(note, velocity or 1)
  if not sample then return end
  synth.path = sample.path
  synth.source = sample.soundsource:clone()
  synth.id = id
  synth.duration = 0
  synth.enveloped = 0
  synth.active = true
  synth.note = sample.note
  synth.source:setPosition(self.location)
  synth.source:setLooping(self.looped)
  synth.source:setVolume(velocity)
  synth.source:play()
  return synth
end


function sampler:applyEnvelope(dt, vol, active, duration)
  -- ADSR envelope
  if active then
    if self.envelope.attack == 0 and duration < 0.01 then             -- flat
      return self.envelope.sustain
    elseif duration < self.envelope.attack then                       -- attack
      return vol + 1 / self.envelope.attack * dt
    elseif duration < self.envelope.attack + self.envelope.decay then -- decay
      return vol - (1 - self.envelope.sustain) / self.envelope.decay * dt
    else                                                              -- sustain
      return vol
    end
  else                                                                -- release
    return math.max(0, vol - self.envelope.sustain / self.envelope.release * dt)
  end
end


-- The instance of sampler for a drum kit
local drum_sampler = sampler.new({
    {path='acustic/CyCdh_K3Kick-03.ogg',       note = 36},
    {path='acustic/CYCdh_LudSdStC-04.ogg',     note = 37},
    {path='acustic/CYCdh_K2room_Snr-01.ogg',   note = 38},
    {path='acustic/CYCdh_K2room_Snr-04.ogg',   note = 39},
    {path='acustic/CyCdh_K3Tom-05.ogg',        note = 41},
    {path='acustic/CYCdh_Kurz01-Tom03.ogg',    note = 43},
    {path='acustic/CYCdh_K2room_ClHat-05.ogg', note = 47},
    {path='acustic/CYCdh_Kurz03-Tom03.ogg',    note = 48},
    {path='acustic/KHats_Open-07.ogg',         note = 46},
    {path='acustic/CYCdh_K4-Trash10.ogg',      note = 49},
    {path='acustic/CYCdh_VinylK4-Ride01.ogg',  note = 51},
    {path='acustic/CYCdh_VinylK4-China.ogg',   note = 52},
    {path='acustic/CYCdh_VinylK1-Tamb.ogg',    note = 54},
    {path='acustic/CYCdh_TrashD-02.ogg',       note = 55},
    {path='acustic/CyCdh_K3Crash-02.ogg',      note = 57},
    {path='acustic/CYCdh_Kurz01-Ride01.ogg',   note = 59},
    envelope = { attack = 0, decay = 0, sustain = 1, release = 1.0 },
  })


-- adapter to interface the sampler by MIDI messages (RtMidi API)

local id = 0

local MIDIctrl = {}


function MIDIctrl.noteOff(note, velocity, channel)
  local source = self.sources[note]
  if source then
      source:stop()
  end
end


function MIDIctrl.noteOn(port, note, velocity, channel)
  if velocity == 0 then
    MIDIctrl.noteOff(note, velocity, channel)
    return
  end
  drum_sampler:playNote(id, note, velocity, pitch)
  id = id + 1
end


function MIDIctrl.sendMessage(status, data1, data2, channel)
  local status, data1, data2, channel = unpack(msg)
  local command = status - bit.lshift(bit.rshift(status, 4), 4)

  if command == 9 then -- Note on
      self:noteOn(data1, data2, channel)
  elseif command == 8 then -- Note off
      self:noteOff(data1, data2, channel)
  end
end


function MIDIctrl.getoutportcount()
  return 1
end


function MIDIctrl.getOutPortName(i)
  return ''
end


return MIDIctrl
