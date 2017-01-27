/*
This is free and unencumbered software released into the public domain.

Anyone is free to copy, modify, publish, use, compile, sell, or
distribute this software, either in source code form or as a compiled
binary, for any purpose, commercial or non-commercial, and by any
means.

In jurisdictions that recognize copyright laws, the author or authors
of this software dedicate any and all copyright interest in the
software to the public domain. We make this dedication for the benefit
of the public at large and to the detriment of our heirs and
successors. We intend this dedication to be an overt act of
relinquishment in perpetuity of all present and future rights to this
software under copyright law.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
IN NO EVENT SHALL THE AUTHORS BE LIABLE FOR ANY CLAIM, DAMAGES OR
OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
OTHER DEALINGS IN THE SOFTWARE.

For more information, please refer to <http://unlicense.org>
*/

#import win32 "sys/windows.odin" when ODIN_OS == "windows";
#import util "win32_util.odin" when ODIN_OS == "windows";
#import "os.odin";
#import "fmt.odin";

atoi :: proc(a : string) -> i64 {
    r : i64 = 0;
    sign := if a[0] == '-' {give -1} else {give 1};
    i := if sign == -1 {give 1} else {give 0};

    for val, idx : 0..<a.count {
        r = r*10 + a[idx] as i64 - '0';
    }

    return sign as i64*r;
}

stat_group :: struct #ordered {
    count : u32;
    slowestMS : u32;
    fastestMS : u32;
    totalMS : f64;
}

GRAPH_HEIGHT :: 10;
GRAPH_WIDTH  :: 30;

graph :: struct #ordered {
    buckets : [GRAPH_WIDTH]stat_group;
}
// New magic value 0x185EA137 (otime v2)
// Old magic value 0xCA5E713F (ctime, otime v1)
MAGIC_VALUE         :: 0x185EA137;
MARKER_MAGIC_VALUE  :: 0x1204E;
ENTRY_MAGIC_VALUE   :: 0x11ADE2;

file_header :: struct #ordered {
    MagicValue : u32;
    AverageMS : u32;

    TotalEntries : u32;
}

file_date :: struct #ordered {
    E : [2]u32;
}

entry_flag :: enum {
    Complete = 0x1,
    NoErrors = 0x2,
}

file_entry :: struct #ordered {
    StartDate : file_date;
    Flags : u32;
    MillisecondsElapsed : u32;
    MarkerCount : u32;
    MagicValue : u32; // Important that this is in the bottom
}

file_entry_marker :: struct {
    MillisecondsElapsed : u32;
    Complete : bool;
    Name : string;
    MarkerOffset : u32;
    MagicValue : u32; // Important that this is in the bottom
}

entry_array :: struct #ordered {
    //EntryCount : i32; Not needed in Odin
    Entries : []file_entry;
}

GetClock :: proc () -> u32 {
    return util.timeGetTime();
}

GetDate :: proc() -> file_date {
    Result : file_date;
    FileTime : win32.FILETIME;
    util.GetSystemTimeAsFileTime(^FileTime);

    Result.E[0] = FileTime.lo;
    Result.E[1] = FileTime.hi;

    return Result;
}

PrintDate :: proc(date : file_date) {
    FileTime := win32.FILETIME{date.E[0], date.E[1]};
    SystemTime : util.SYSTEMTIME;

    util.FileTimeToLocalFileTime(^FileTime, ^FileTime);
    util.FileTimeToSystemTime(^FileTime, ^SystemTime);

    fmt.printf("%04d-%02d-%02d %02d:%02d.%02d",
               SystemTime.Year, SystemTime.Month, SystemTime.Day,
               SystemTime.Hour, SystemTime.Minute, SystemTime.Second); // HOW
}

MillisecondDifference :: proc(a : file_date, b : file_date) -> f64 {
    a64 := (a.E[1] << 32 | a.E[0]) as i64;
    b64 := (b.E[1] << 32 | b.E[0]) as i64;

    return (a64 - b64) as f64 * 0.0001;
}

DayIndex :: proc(a : file_date) -> u32 {
    FileTime := win32.FILETIME{a.E[0], a.E[1]};
    SystemTime : util.SYSTEMTIME;

    util.FileTimeToLocalFileTime(^FileTime, ^FileTime);
    util.FileTimeToSystemTime(^FileTime, ^SystemTime);

    SystemTime.Hour = 0;
    SystemTime.Minute = 0;
    SystemTime.Second = 0;

    util.SystemTimeToFileTime(^SystemTime, ^FileTime);
    a64 := (FileTime.hi << 32 | FileTime.lo) as i64;

    ad := ((a64 as f64) * (0.0001)) / (1000.0 * 60.0 * 60.0 * 24.0);
    return ad as u32;
}

Usage :: proc() {
    fmt.fprintln(os.stderr, "OTime v1.0 by Mikkel Hjortshoej");
    fmt.fprintln(os.stderr, "This tool is a rewrite of CTime by Casey Muratori in Odin");
    fmt.fprintln(os.stderr, "Usage:");
    fmt.fprintln(os.stderr, "  OTime -start <timing file>");
    fmt.fprintln(os.stderr, "  OTime -marker start <marker name> <timing file>");
    fmt.fprintln(os.stderr, "  OTime -marker end <marker name> <timing file>");
    fmt.fprintln(os.stderr, "  OTime -end <timing file> [error level]");
    fmt.fprintln(os.stderr, "  OTime -stats <timing file>");
    fmt.fprintln(os.stderr, "  OTime -csv <timing file>");
}

ReadAllEntries :: proc(handle : os.Handle) -> entry_array {
    Result : entry_array;
    EntriesBegin : i64 = size_of(file_header);
    FileSize, _ := os.seek(handle, 0, 2);
    if FileSize > 0 {
        EntriesSize := FileSize  - EntriesBegin; 
        Result.Entries = new_slice(file_entry, EntriesSize / size_of(file_entry));
        if(Result.Entries.data != nil) {
            os.seek(handle, EntriesBegin, 0);
            buf := new_slice(byte, EntriesSize);
            readSize, err := os.read(handle, buf);
            Result.Entries.data = buf.data as ^file_entry;
            Result.Entries.count = (EntriesSize / size_of(file_entry)) as int;

            if readSize as i64 != EntriesSize {
                fmt.fprintln(os.stderr, "ERROR: Unable to read timing entries from file.");
            }
        } else {
            fmt.fprintf(os.stderr, "ERROR: Unable to allocate % for storing timing entries.\n", EntriesSize);
        }
    } else {
        fmt.fprintln(os.stderr, "ERROR: Unable to determine file size of timing file.");
    }

    return Result;
}

FreeAllEntries :: proc(array : entry_array) {
    free(array.Entries.data);
    array.Entries.count = 0;
}

CSV :: proc(array : entry_array, timingFileName : string) {
    fmt.printf("% Timings\n", timingFileName);
    fmt.println("ordinal, date, duration, status");
    while i := 0; i < array.Entries.count {
        entry := array.Entries[i];
        fmt.printf("%, ", i);
        PrintDate(entry.StartDate);
        if entry.Flags & entry_flag.Complete as u32 == entry_flag.Complete as u32  {
            fmt.printf(", %0.3fs, %", entry.MillisecondsElapsed as f64 / 1000.0,
                    if entry.Flags & entry_flag.NoErrors as u32 == 
                       entry_flag.NoErrors as u32 
                    { give "succeeded" } 
                    else 
                    { give "failed" }); // precision
        } else {
            fmt.print(", (never completed), failed");
        }

        fmt.println();

        i += 1;
    }
}

time_part :: struct {
    name : string;
    millisecondsPer : f64;
}

PrintTime :: proc(milliseconds : f64) {
    MillisecondsPerSecond : f64 = 1000;
    MillisecondsPerMinute : f64 = 60*MillisecondsPerSecond;
    MillisecondsPerHour : f64   = 60*MillisecondsPerMinute;
    MillisecondsPerDay : f64    = 24*MillisecondsPerHour;
    MillisecondsPerWeek : f64   = 7*MillisecondsPerDay;

    parts := new_slice(time_part, 4);
    parts[0].name = "week"; 
    parts[0].millisecondsPer = MillisecondsPerWeek;  

    parts[1].name = "day"; 
    parts[1].millisecondsPer = MillisecondsPerDay;  

    parts[2].name = "hour"; 
    parts[2].millisecondsPer = MillisecondsPerHour;  

    parts[3].name = "minute"; 
    parts[3].millisecondsPer = MillisecondsPerMinute;  

    q := milliseconds;
    for part : parts {
        msPer := part.millisecondsPer;
        this := (q / msPer) as int as f64;
        if this > 0 {
            fmt.printf("% % %, ", this as i32, part.name, if this != 1 {give "s"} else {give ""}); 
        }

        q -= this*msPer;
    }

    fmt.printf("% seconds", q as f64 / 1000.0);
}

PrintTimeStat :: proc(name : string, milliseconds : u32) {
    fmt.printf("%: ", name);
    PrintTime(milliseconds as f64);
    fmt.println();
}

PrintStatGroup :: proc(title : string, group : ^stat_group) {
    averageMS : u32 = 0;
    if group.count >= 1 {
        averageMS = (group.totalMS / group.count as f64) as u32;
    }

    if group.count > 0 {
        fmt.printf("% (%):\n", title, group.count);
        PrintTimeStat("  Slowest", group.slowestMS);
        PrintTimeStat("  Fastest", group.fastestMS);
        PrintTimeStat("  Average", averageMS);
        PrintTimeStat("  Total", group.totalMS as u32);
    }
}

UpdateStatGroup :: proc(group : ^stat_group, entry : ^file_entry) {
    if group.slowestMS < entry.MillisecondsElapsed {
        group.slowestMS = entry.MillisecondsElapsed;
    }

    if group.fastestMS > entry.MillisecondsElapsed {
        group.fastestMS = entry.MillisecondsElapsed;
    }

    group.totalMS += entry.MillisecondsElapsed as f64;
    group.count += 1;
}


PrintGraph :: proc(title : string, daySpan : f64, graph : ^graph) {
    maxCountInBucket : u32 = 0;
    slowestMS : u32 = 0;
    for group : graph.buckets {
        if group.count > 0 {
            if maxCountInBucket < group.count {
                maxCountInBucket = group.count;
            }

            if slowestMS < group.slowestMS {
                slowestMS = group.slowestMS;
            }
        }
    }
    
    dpb := daySpan / GRAPH_WIDTH;
    fmt.printf("\n% (% day%/bucket):\n", title, dpb, if dpb == 1 {give ""} else {give "s"});

    MapToDiscrete :: proc(value : f64, inMax : f64, outMax : f64) -> i32 {
        if inMax == 0 {
            inMax = 1;
        }

        result := ((value  / inMax) * outMax) as i32;
        return result;
    }

    while lineIndex : i32 = GRAPH_HEIGHT - 1; lineIndex >= 0 {
        fmt.printf("%", "|");
        while i := 0; i < graph.buckets.count {
            group := graph.buckets[i];
            this : i32 = -1;
            if group.count > 0 {
                this = MapToDiscrete(group.slowestMS as f64, slowestMS as f64, GRAPH_HEIGHT - 1);
            }
            fmt.printf("%", if this >= lineIndex {give "*"} else {give " "});
            i += 1;
        }
        if lineIndex == (GRAPH_HEIGHT - 1) {
            fmt.printf("%", " ");
            PrintTime(slowestMS as f64);
        }
        fmt.println();

        lineIndex -= 1;
    }

    fmt.printf("%", "+");

    for i : 0..<GRAPH_WIDTH {
        fmt.printf("%", "-");
    }

    fmt.print(' ');
    PrintTime(0);

    fmt.println();
    fmt.println();

    while lineIndex : i32 = GRAPH_HEIGHT - 1; lineIndex >= 0 {
        fmt.printf("%", "|");
        while i := 0; i < graph.buckets.count {
            group := graph.buckets[i];
            this : i32 = -1;
            if group.count > 0 {
                this = MapToDiscrete(group.count as f64, maxCountInBucket as f64, GRAPH_HEIGHT - 1);
            }
            fmt.printf("%", if this >= lineIndex {give "*"} else {give " "});
            i += 1;
        }

        if lineIndex == (GRAPH_HEIGHT - 1) {
            fmt.printf(" %", maxCountInBucket);
        }
        fmt.println();
        lineIndex -= 1;
    }

    fmt.printf("%", "+");
    for i : 0..<GRAPH_WIDTH {
        fmt.printf("%", "-");
    }
    fmt.println(" 0");
}

Stats :: proc(array : entry_array, timingFileName : string) {
    withErrors : stat_group;
    noErrors : stat_group;
    allStats : stat_group;

    incompleteCount : u32 = 0;
    daysWithTimingCount : u32 = 0;
    daySpanCount : u32 = 0;

    lastDayIndex : u32 = 0;

    firstDayAt := 0.0;
    lastDayAt := 0.0;
    daySpan := 0.0;

    totalGraph : graph;
    recentGraph : graph;

    allMS := 0.0;

    withErrors.fastestMS = 0xFFFFFFFF;
    noErrors.fastestMS = 0xFFFFFFFF;

    if array.Entries.count >= 2 {
        milliD := MillisecondDifference(array.Entries[array.Entries.count - 1].StartDate, 
                                        array.Entries[0].StartDate);
        daySpanCount = (milliD / (1000.0 * 60.0 * 60.0 * 24.0)) as u32;

        firstDayAt = DayIndex(array.Entries[0].StartDate) as f64;
        lastDayAt = DayIndex(array.Entries[array.Entries.count - 1].StartDate) as f64;
        daySpan = lastDayAt - firstDayAt;
    }

    daySpan += 1;

    while i := 0; i < array.Entries.count {
        entry : ^file_entry = ^array.Entries[i];
        if(entry.Flags & entry_flag.Complete as u32) ==
           entry_flag.Complete as u32 {
            group : ^stat_group;
            if (entry.Flags & entry_flag.NoErrors as u32) ==
                entry_flag.NoErrors as u32 {
                group = ^noErrors;
            } else {
                group = ^withErrors;
            }

            thisDayIndex := DayIndex(entry.StartDate);
            if lastDayIndex != thisDayIndex {
                lastDayIndex = thisDayIndex;
                daysWithTimingCount += 1;
            }

            UpdateStatGroup(group, entry);
            UpdateStatGroup(^allStats, entry);

            allMS += entry.MillisecondsElapsed as f64;

            {
                graphIndex := ((thisDayIndex as f64 - firstDayAt) / daySpan) * GRAPH_WIDTH as f64;
                UpdateStatGroup(^totalGraph.buckets[graphIndex as i32], entry);
            }

            {
                graphIndex := thisDayIndex - (lastDayAt - GRAPH_WIDTH + 1) as u32;
                if graphIndex >= 0 {
                    UpdateStatGroup(^recentGraph.buckets[graphIndex], entry);
                }
            }
        } else {
            incompleteCount += 1;
        }

        i += 1;
    }

    fmt.printf("\n% Statistics\n\n", timingFileName);
    fmt.printf("Total complete timings: %\n", withErrors.count + noErrors.count);
    fmt.printf("Total incomplete timings: %\n", incompleteCount);
    fmt.printf("Days with timings: %\n", daysWithTimingCount);
    fmt.printf("Days between first and last timing: %\n", daySpanCount);
    PrintStatGroup("Timings marked successful", ^noErrors);
    PrintStatGroup("Timings marked failed", ^withErrors);

    PrintGraph("All", (lastDayAt - firstDayAt), ^totalGraph);
    PrintGraph("Recent", GRAPH_WIDTH, ^recentGraph);

    fmt.print("\nTotal time spent: ");
    PrintTime(allMS);
    fmt.println();
}

main :: proc () {
    entryClock := GetClock(); 
    args := util.GetCommandLineArguments();
    if args.count == 3 || args.count == 4 || args.count == 5{
        mode := args[1];
        timingFileName := args[2];
        header : file_header;
        
        to_c_string :: proc(s: string) -> []byte {
            c := new_slice(byte, s.count+1);
            copy(c, s as []byte);
            c[s.count] = 0;
            return c;
        }

        handle, err := os.open(timingFileName, os.O_RDWR, 0);
        if err == 0 {
            buf : [size_of(file_header)]byte;
            b, err := os.read(handle, buf[:]);
            header = (^buf[0] as ^file_header)^;
            if header.MagicValue != MAGIC_VALUE {
                fmt.fprintf(os.stderr, "ERROR: Unable to verify that \"%\" is actually a ctime-compatible file.\n", timingFileName);

                os.close(handle);
                handle = -1;
            }
        } else if mode == "-start" {
            handle, err = os.open(timingFileName, os.O_RDWR|os.O_CREAT, 0); // create the missing file
            if err == 0 {
                header.MagicValue = MAGIC_VALUE;
                
                buf : []byte;
                buf.data = ^header as ^byte;
                buf.count = size_of_val(header);
                written, err := os.write(handle, buf);

                if written != size_of(file_header) {
                    fmt.fprintf(os.stderr, "ERROR: Unable to write header to \"%\".\n", timingFileName);
                }
            } else {
                 fmt.fprintf(os.stderr, "ERROR: Unable to create timing file \"%\".\n", timingFileName);
            }
        }

        if handle != os.INVALID_HANDLE {
            if mode == "-start" {
                new : file_entry;
                new.StartDate = GetDate();
                new.MillisecondsElapsed = GetClock();
                new.MagicValue = ENTRY_MAGIC_VALUE;
                new.MarkerCount = 0;

                fp, _ := os.seek(handle, 0, 2);
                buf : []byte;
                buf.data = ^new as ^byte;
                buf.count = size_of_val(new);
                written, _ := os.write(handle, buf);
                if (fp < 0) && 
                   (written != size_of_val(new)) {
                    fmt.fprintf(os.stderr, "ERROR: Unable to append new entry to file \"%\".\n", timingFileName);
                }
            } else if mode == "-end" {
                //Check Magic Value
                seek, _ := os.seek(handle, -size_of(u32), 2);
                buf : [size_of(u32)]byte;
                read, _ := os.read(handle, buf[:]);
                value := (^buf[0] as ^u32)^ as u32;

                offset : i64 = 0;

                if value != ENTRY_MAGIC_VALUE {
                    if value == MARKER_MAGIC_VALUE {
                        seek, _ = os.seek(handle, -size_of(file_entry_marker), 2);
                        entry_buf : [size_of(file_entry_marker)]byte;
                        read, _ = os.read(handle, entry_buf[:]);
                        marker := (^entry_buf[0] as ^file_entry_marker)^ as file_entry_marker;

                        offset = -marker.MarkerOffset as i64;
                    } else {
                        fmt.fprintf(os.stderr, "ERROR: Unable to read last entry or marker from file \"%\".\n", timingFileName);
                        return;
                    }
                }

                offset -= size_of(file_entry);
                seek, _ = os.seek(handle, offset, 2);
                entry_buf : [size_of(file_entry)]byte;
                read, _ = os.read(handle, entry_buf[:]);
                last := (^entry_buf[0] as ^file_entry)^ as file_entry;

                if (seek >= 0) && (read) == size_of(file_entry) {
                    if (last.Flags & entry_flag.Complete as u32) != entry_flag.Complete as u32 {
                        startClockD := last.MillisecondsElapsed;
                        endClockD := entryClock;
                        last.Flags |= entry_flag.Complete as u32;
                        
                        last.MillisecondsElapsed = 0;
                        if startClockD < endClockD {
                            last.MillisecondsElapsed = endClockD - startClockD;
                        }

                        if args.count == 3 || (args.count == 4 && (atoi(args[3]) == 0)) {
                            last.Flags |= entry_flag.NoErrors as u32;
                        }

                        fp, _ := os.seek(handle, -size_of(file_entry), 2);
                        
                        buf : []byte;
                        buf.data = ^last as ^byte;
                        buf.count = size_of_val(last);
                        written, _ := os.write(handle, buf);
                        
                        if (fp >= 0) &&
                           (written == size_of_val(last)) {
                            fmt.print("OTIME: ");
                            PrintTime(last.MillisecondsElapsed as f64);
                            fmt.printf(" (%)\n", timingFileName);
                        } else {
                            fmt.fprintf(os.stderr, "ERROR: Unable to rewrite last entry to file \"%\".\n", timingFileName);
                        }
                    } else {
                        fmt.fprintf(os.stderr, "ERROR: Last entry in file \"%\" is already closed - unbalanced/overlapped calls?\n", timingFileName);
                    }
               } else {
                    fmt.fprintf(os.stderr, "ERROR: Unable to read last entry from file \"%\".\n", timingFileName);
               }
            } else if mode == "-marker" {
                if(args.count != 5) {
                    fmt.fprint(os.stderr, "Not enough arguments provided for -marker ie. -maker <start or end> <marker name> <timing file>");
                }

                isStart := args[2] == "start";
                if isStart {
                    
                } else {

                }

            } else if mode == "-stats" {
                array := ReadAllEntries(handle);
                Stats(array, timingFileName);
                FreeAllEntries(array);
            } else if mode == "-csv" {
                array := ReadAllEntries(handle);
                CSV(array, timingFileName);
                FreeAllEntries(array);
            } else {
                fmt.fprintf(os.stderr, "ERROR: Unrecognized command \"%\".\n", mode);
            }

            os.close(handle);
            handle = -1;
        } else {
            fmt.fprintf(os.stderr, "ERROR: Cannnot open file \"%\".\n", timingFileName);
        }
    } else {
        Usage();
    }
}