# soundcrest

Live waveform in your terminal of whatever your Mac is playing. It stays in one
place: a flat line during silence that swells outward with the sound. Lows sit in
the centre and highs toward the edges. Audio is read in memory and never stored.

Requires macOS 14.2 or later. No BlackHole or other virtual audio device needed.

## Install

    brew tap carsonfischl/tap
    brew trust --formula carsonfischl/tap/soundcrest
    brew install soundcrest

Homebrew 7 refuses formulae from third-party taps until you trust them.

Homebrew builds it from source, which needs Xcode or the Command Line Tools. If
it reports the Xcode license has not been accepted, run the command it suggests.

On first use, allow your terminal app under System Settings > Privacy & Security
> System Audio Recording, then restart it.

## Use

    soundcrest               # desktop background plus the terminal view
    soundcrest --terminal    # terminal view only
    soundcrest --wallpaper   # desktop background only
    soundcrest --toggle      # turn the desktop background on or off
    soundcrest --pane on     # open new Terminal windows with a waveform pane
    soundcrest --pane off    # open them without it
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

## Pane

`--pane on` adds a block to `~/.zshrc` so each new Terminal.app window opens with
a small waveform at the top right. Your shell wraps before the right column.
`--pane off` removes the block. It needs tmux, which runs out of sight: your own
tmux setup is not used, and there is no status bar or prefix key.

Below the waveform, the right column takes turns between three views. Click
the right column, or press **⌥Tab** (Option-Tab), to move to the next one, or
click a name in the tab bar to jump to it. ⌥Tab needs "Use Option as Meta key"
on, under Terminal > Settings > Profiles > Keyboard. Typing always stays in
your shell.

- **info**: a neofetch-style summary of your Mac: OS, model, kernel, uptime,
  Homebrew packages, shell, CPU, memory, disk and battery.
- **weather**: current conditions and four days from
  [Open-Meteo](https://open-meteo.com), free and keyless. Units follow your
  region.
- **news**: headlines from BBC News, The New York Times, NPR and Google News,
  each with the start of the story, taking turns between outlets and paging
  every 20 seconds. Click an article to open it in your browser.

Each view uses the waveform's colours and drops lines when the window is short.
Turn any of them off or on:

    soundcrest --pane-info off
    soundcrest --pane-weather off
    soundcrest --pane-news off

Weather uses Location Services. macOS only asks apps, not command-line tools,
for your location, so soundcrest keeps a small helper app at
`~/Library/Application Support/soundcrest/soundcrest.app` and asks through
that. The first time you open the weather view, macOS asks whether
"soundcrest" may use your location. The position is rounded to about a
kilometre before it goes to Open-Meteo, and Apple's geocoder supplies the town
name. If you would rather not share it, name a place instead:

    soundcrest --weather-location "Montreal"
    soundcrest --weather-location auto       # back to Location Services

Choose news outlets from `bbc`, `nyt`, `npr`, `google`, `guardian`, `wapo`,
`wsj`, `ft` and `aljazeera`:

    soundcrest --news-sources bbc,guardian,ft

Changes reach open windows within a second. Weather refreshes every 15 minutes
and headlines every 10, shared by all windows through
`~/Library/Caches/local.soundcrest`.

### Playing from Spotify or YouTube

The waveform always shows your Mac's system audio. Click it to open a browser
in its place, sign in to Spotify or YouTube, and pick a song from your
playlists. Spotify songs play in the Spotify app and YouTube songs open in your
browser, so the waveform picks them up like any other sound. Click the header
row to go back, scroll with the trackpad or the ▴/▾ rows, and choose "System
audio" to close it.

Both services only let you in through an app you register yourself:

**Spotify** (needs Premium on the account that registers the app; up to 5 users)

1. Create an app at <https://developer.spotify.com/dashboard>, choosing Web API.
2. Add the redirect URI `http://127.0.0.1:47823/callback`.
3. Under User Management, add the Spotify account you'll sign in with.
4. Run `soundcrest --spotify-client-id YOUR_CLIENT_ID`.

Development-mode apps only see the contents of playlists you own or collaborate
on, plus Liked Songs. Playing a song asks once for permission for your terminal
to control Spotify.

**YouTube**

1. In <https://console.cloud.google.com>, create a project and enable the
   YouTube Data API v3.
2. Set up the OAuth consent screen (External, Testing) and add your Google
   account as a test user.
3. Create an OAuth client ID of type Desktop app.
4. Run `soundcrest --youtube-client CLIENT_ID CLIENT_SECRET`.

While the consent screen is in Testing, Google ends the sign-in after 7 days and
the pane asks you to sign in again.

Sign-ins are kept in `~/Library/Application Support/soundcrest/tokens.json`,
readable only by you. `soundcrest --music-sign-out spotify` (or `youtube`)
forgets one.

Hold Fn while dragging to select text across the window, or drag normally to copy
from your shell.

The pane is 48 columns by 12 rows. Change it for new windows with
`soundcrest --pane-size 60x16`. It narrows to leave your shell 40 columns, and
windows under 52 columns open without it.

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
