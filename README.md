# mkvremux
Remuxes any MKV (H.264, Full-HD) to H.264, Full-HD, AC3 audio (tracks: german/english)

### Requirements
Please install following packages:
* ``mkvtoolnix``
* ``libav-tools``

### Usage
``mkvremux.sh DIRECTORY``

Directory can be absolute or relative. The script searches for MKV-files recursively within the given directory. If something is found, it extracts only the video and audio tracks (ignores all the rest), converts the audio from whatever to AC3 (448kbps) and muxes a new MKV-file. The original MKV-file is stored with a BKP-suffix. The original MKV-file should contain at least:
* Video-Track (H.264, Full-HD)
* Audio-Track (6-Channel, german)
* Audio-Track (6-Channel, english)
The result will be:
* Video-Track (H.264, Full-HD)
* Audio-Track (AC3, 6-Channel, german)
* Audio-Track (AC3, 6-Channel, english)
* Default language is set to ``ger``

### License
Copyright (c) 2015 Daniel Prokscha

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.