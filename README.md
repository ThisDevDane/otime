<p align="center">
    <img src="https://otime.handmade.network/static/media/projects/dark-logo/otime.png?v=71663" alt="Otime logo" height=300px/>
    <br/>
    This program is a spirital successor for Casey Muratori's Ctime written in Odin
    <br/>
    <br/>
    <a href="https://github.com/ThisDrunkDane/otime/releases/latest">
        <img src="https://img.shields.io/github/release/thisdrunkdane/otime.svg">
    </a>
    <a href="https://github.com/ThisDrunkDane/otime/releases/latest">
        <img src="https://img.shields.io/badge/Platforms-Windows-green.svg">
    </a>
    <a href="https://github.com/ThisDrunkDane/otime/blob/master/LICENSE">
        <img src="https://img.shields.io/github/license/thisdrunkdane/otime.svg">
    </a>
</p>

```
otime -stats jaze.otm

Stats from jaze.otm.

Total timings: 6436.
Total incomplete timings: 107.

Timings marked successful (2701):
  Slowest: 22.326 seconds
  Fastest: 0.046 seconds
  Average: 2.443 seconds
  Total:   1 hour, 50 minutes, 0.810 seconds

Timings marked failed (3628):
  Slowest: 1 minute, 46.796 seconds
  Fastest: 0.016 seconds
  Average: 0.609 seconds
  Total:   36 minutes, 52.238 seconds

Average of all groups:  1.369 seconds
Total of all groups:    2 hours, 26 minutes, 53.048 seconds
```
# Usage
Otime will automatically create a file to store the data in when you start timing stuff.
You simply put a `otime -begin foo` and `otime -end foo.otm %err%` around what you're timing, with foo being the filename you want otime to use, and `%err%` being the error code returned by what you're timing, you can omit `%err%` and otime will just assume that the timing was successful.  
If want to see all options just write `otime` and it will print them.
