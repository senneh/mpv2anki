# mvp2anki
## Overview 
Inspired by subs2srs this script lets mpv users quickly creates notes for the Anki spaced.
## Requirements
* Linux (Windows *might* work, but is not officially supported)
* Anki
* The AnkiConnect plugin
* curl (required to connect to the AnkiConnect plugin)
## Usage
Save mpv2anki.lua in the mpv script folder (`~/.config/mpv/scripts/`). 
Configure the script either by editing the options in the script or by creating a config file in mpv's script-opts folder (`~/.config/mpv/script-opts/mpv2anki.conf`) as seen below
```
# This is the only required value. replace "user" and "profile" with your own.
# This must be an absolute path. '~' for home dir will NOT work
media_path=/home/user/.local/share/Anki2/profile/collection.media/

# These are the other options containing their default values.
deckname=mpv2anki
# The note type
modelName=mpv2anki
# You can use these options to remap the fields
field_audio=audio
field_snapshot=snapshot
field_subtitle1=subtitle1
field_subtitle2=subtitle2
field_start_time=start_time
field_end_time=end_time
field_snapshot_time=snapshot_time
field_title=title
# The font size used in the menu.
font_size=20
# The url and port AnkiConnect uses. This should be the default 
anki_url=localhost:8765
# audio & snapshot options
audio_bitrate=128k
snapshot_height=480
```

