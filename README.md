# soundcrest

Live waveform in your terminal of whatever your Mac is playing. It stays in one
place: a flat line during silence that swells outward with the sound. Lows sit in
the centre and highs toward the edges. Audio is read in memory and never stored.

Requires macOS 14.2 or later. No BlackHole or other virtual audio device needed.

## Install

    brew tap carsonfischl/tap
    brew install soundcrest

Homebrew builds it from source, which needs Xcode or the Command Line Tools. If
it reports the Xcode license has not been accepted, run the command it suggests.

On first use, allow your terminal app under System Settings > Privacy & Security
> System Audio Recording, then restart it.

## Use

    soundcrest               # desktop background plus the terminal view
    soundcrest --terminal    # terminal view only
    soundcrest --wallpaper   # desktop background only
    soundcrest --toggle      # turn the desktop background on or off
    soundcrest --autostart on   # start the desktop background at login
    soundcrest --autostart off  # stop starting it at login

Terminal keys: `m` switch view, `q` quit. `--scope` starts in oscilloscope view.

## Desktop background

Draws the waveform behind your desktop icons on every display and Space. It keeps
running after you close the terminal or quit the terminal app. Turn it off from
anywhere with **⌃⌥⌘W** (Control-Option-Command-W), the menu bar icon, or
`soundcrest --toggle`. It stops listening a few seconds after audio stops, so your
Mac can still sleep.

`--autostart on` adds a launchd agent at
`~/Library/LaunchAgents/local.soundcrest.plist`, and `off` removes it. Neither
changes a background that is already running. Once off, it stays off until your
next login.

**Known issue:** `--autostart` is experimental. In testing, soundcrest started by
launchd hung waiting on the audio service and system audio stopped working until
`sudo killall coreaudiod`. A missing audio permission is the suspected cause. If
this happens, run that command, then `soundcrest --autostart off`.

## Colours and backdrop

    soundcrest --color ember
    soundcrest --color ff0000,0000ff         # centre colour, edge colour
    soundcrest --backdrop transparent        # waveform over your own wallpaper
    soundcrest --backdrop translucent        # your wallpaper, dimmed

Colours: `aurora` (default), `ember`, `ocean`, `forest`, `violet`, `mono`, or hex.
Backdrops: `solid` (default), `translucent`, `transparent`. Your last choice is
remembered, and passing one to a running background restarts it with the new look.

## Build from source

    ./dev run            # build and start
    ./dev install        # copy to ~/.local/bin (set PREFIX to change)
    ./dev test

## Troubleshooting

If the line stays flat while music plays, open System Settings > Privacy &
Security > System Audio Recording and allow your terminal app, then restart it.

`soundcrest --probe 5` prints raw input levels. `frames` rising with `peak` at 0
means audio is arriving silent, which usually points to that permission.
