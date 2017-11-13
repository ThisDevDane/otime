/*
Original ctime concept and code by Casey Muratori
Odin rewrite by Mikkel Hjortshoej

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
#import       "os.odin";
#import       "fmt.odin";

VERSION_STR :: "v0.6";

GetCommandLineArguments :: proc() -> []string {
    to_odin_string :: proc(c: ^byte) -> string {
        s: string;
        s.data = c;
        for (c + s.count)^ != 0 {
            s.count += 1;
        }
        return s;
    }
    data := cast([]byte)to_odin_string(win32.GetCommandLineA());
    string_count, string_index: int;
    new_option: bool;

    new_option = true;
    for b, i in data {
        if b == ' '    {
            data[i] = 0;
            new_option = true;
        } else {
            if new_option {
                string_count += 1;
            }
            new_option = false;
        }
    }


    strings := new_slice(string, string_count);
    new_option = true;
    for b, i in data {
        if b == 0 {
            new_option = true;
        } else {
            if new_option {
                strings[string_index] = to_odin_string(^data[i]);
                string_index += 1;
            }
            new_option = false;
        }
    }

    return strings;
}

atoi :: proc(a : string) -> i64 {
    r : i64 = 0;
    sign := a[0] == '-' ? -1 : 1; 
    i := sign == -1 ? 1 : 0;

    for val, idx in 0..<a.count {
        r = r*10 + cast(i64)a[idx] - '0';
    }

    return cast(i64)sign*r;
}

stat_group :: struct #ordered {
    count : u32,
    slowestMS : u32,
    fastestMS : u32,
    totalMS : f64,
}

GRAPH_HEIGHT :: 10;
GRAPH_WIDTH  :: 30;

graph :: struct #ordered {
    buckets : [GRAPH_WIDTH]stat_group,
}

MAGIC_VALUE :: 0xCA5E713F;

timing_file_header :: struct #ordered {
    MagicValue : u32,
}

timing_file_date :: struct #ordered {
    E : [2]u32,
}

timing_file_entry_flag :: enum {
    Complete = 0x1,
    NoErrors = 0x2,
}

timing_file_entry :: struct #ordered {
    StartDate : timing_file_date,
    Flags : u32,
    MillisecondsElapsed : u32,
}

timing_entry_array :: struct #ordered {
    Entries : []timing_file_entry,
}

GetClock :: proc () -> u32 {
    return win32.timeGetTime();
}

GetDate :: proc() -> timing_file_date {
    Result : timing_file_date;
    FileTime : win32.FILETIME;
    win32.GetSystemTimeAsFileTime(^FileTime);

    Result.E[0] = FileTime.lo;
    Result.E[1] = FileTime.hi;

    return Result;
}

PrintDate :: proc(date : timing_file_date) {
    FileTime := win32.FILETIME{date.E[0], date.E[1]};
    SystemTime : win32.SYSTEMTIME;

    win32.FileTimeToLocalFileTime(^FileTime, ^FileTime);
    win32.FileTimeToSystemTime(^FileTime, ^SystemTime);

    fmt.printf("%d-%d-%d %d:%d.%d",
               SystemTime.year, SystemTime.month, SystemTime.day,
               SystemTime.hour, SystemTime.minute, SystemTime.second); // HOW
}

MillisecondDifference :: proc(a : timing_file_date, b : timing_file_date) -> f64 {
    a64 := cast(i64)(a.E[1] << 32 | a.E[0]);
    b64 := cast(i64)(b.E[1] << 32 | b.E[0]);

    return cast(f64)(a64 - b64) * 0.0001;
}

DayIndex :: proc(a : timing_file_date) -> u32 {
    FileTime := win32.FILETIME{a.E[0], a.E[1]};
    SystemTime : win32.SYSTEMTIME;

    win32.FileTimeToLocalFileTime(^FileTime, ^FileTime);
    win32.FileTimeToSystemTime(^FileTime, ^SystemTime);

    SystemTime.hour = 0;
    SystemTime.minute = 0;
    SystemTime.second = 0;

    win32.SystemTimeToFileTime(^SystemTime, ^FileTime);
    a64 := cast(i64)(FileTime.hi << 32 | FileTime.lo);

    ad := (cast(f64)a64 * (0.0001)) / (1000.0 * 60.0 * 60.0 * 24.0);
    return cast(u32)ad;
}

Usage :: proc() {
    fmt.fprintf( os.stderr, "oTime %s by Mikkel Hjortshoej\n", VERSION_STR);
    fmt.fprintln(os.stderr, "This tool is a rewrite of CTime by Casey Muratori in Odin");
    fmt.fprintln(os.stderr, "Usage:");
    fmt.fprintln(os.stderr, "  otime -begin <timing file>");
    fmt.fprintln(os.stderr, "  otime -end   <timing file> [error level]");
    fmt.fprintln(os.stderr, "  otime -stats <timing file>");
    fmt.fprintln(os.stderr, "  otime -csv   <timing file>");
}

ReadAllEntries :: proc(handle : os.Handle) -> timing_entry_array {
    Result : timing_entry_array;
    EntriesBegin : i64 = size_of(timing_file_header);
    FileSize, _ := os.seek(handle, 0, 2);
    if FileSize > 0 {
        EntriesSize := FileSize  - EntriesBegin; 
        Result.Entries = new_slice(timing_file_entry, EntriesSize / size_of(timing_file_entry));
        if(Result.Entries.data != nil) {
            os.seek(handle, EntriesBegin, 0);
            buf := new_slice(byte, EntriesSize);
            readSize, err := os.read(handle, buf);
            Result.Entries.data = cast(^timing_file_entry)buf.data;
            Result.Entries.count = cast(int)(EntriesSize / size_of(timing_file_entry));

            if cast(i64)readSize != EntriesSize {
                fmt.fprintln(os.stderr, "ERROR: Unable to read timing entries from file.");
            }
        } else {
            fmt.fprintf(os.stderr, "ERROR: Unable to allocate %d for storing timing entries.\n", EntriesSize);
        }
    } else {
        fmt.fprintln(os.stderr, "ERROR: Unable to determine file size of timing file.");
    }

    return Result;
}

FreeAllEntries :: proc(array : timing_entry_array) {
    free(array.Entries.data);
    array.Entries.count = 0;
}

CSV :: proc(array : timing_entry_array, timingFileName : string) {
    fmt.printf("%s Timings\n", timingFileName);
    fmt.println("ordinal, date, duration, status");
    for i := 0; i < array.Entries.count; i += 1 {
        entry := array.Entries[i];
        fmt.printf("%d, ", i);
        PrintDate(entry.StartDate);
        if entry.Flags & cast(u32)timing_file_entry_flag.Complete == cast(u32)timing_file_entry_flag.Complete {
            fmt.printf(", %fs, %s", cast(f64)entry.MillisecondsElapsed / 1000.0,
                    entry.Flags & cast(u32)timing_file_entry_flag.NoErrors ==  cast(u32)timing_file_entry_flag.NoErrors ? "succeeded" : "failed");
        } else {
            fmt.print(", (never completed), failed");
        }

        fmt.println();
    }
}

time_part :: struct {
    name : string,
    millisecondsPer : f64,
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
    for part in parts {
        msPer := part.millisecondsPer;
        this := cast(f64)(cast(int)(q / msPer));
        if this > 0 {
            fmt.printf("%d %s %s, ", cast(i32)this, part.name, this != 1 ? "s" : ""); 
        }

        q -= this*msPer;
    }

    fmt.printf("%f seconds", cast(f64)q / 1000.0);
}

PrintTimeStat :: proc(name : string, milliseconds : u32) {
    fmt.printf("%s: ", name);
    PrintTime(cast(f64)milliseconds);
    fmt.println();
}

PrintStatGroup :: proc(title : string, group : ^stat_group) {
    averageMS : u32 = 0;
    if group.count >= 1 {
        averageMS = cast(u32)(group.totalMS / cast(f64)group.count);
    }

    if group.count > 0 {
        fmt.printf("%s (%d):\n", title, group.count);
        PrintTimeStat("  Slowest", group.slowestMS);
        PrintTimeStat("  Fastest", group.fastestMS);
        PrintTimeStat("  Average", averageMS);
        PrintTimeStat("  Total", cast(u32)group.totalMS);
    }
}

UpdateStatGroup :: proc(group : ^stat_group, entry : ^timing_file_entry) {
    if group.slowestMS < entry.MillisecondsElapsed {
        group.slowestMS = entry.MillisecondsElapsed;
    }

    if group.fastestMS > entry.MillisecondsElapsed {
        group.fastestMS = entry.MillisecondsElapsed;
    }

    group.totalMS += cast(f64)entry.MillisecondsElapsed;
    group.count += 1;
}


PrintGraph :: proc(title : string, daySpan : f64, graph : ^graph) {
    maxCountInBucket : u32 = 0;
    slowestMS : u32 = 0;
    for group in graph.buckets {
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
    fmt.printf("\n%s (%f day%s/bucket):\n", title, dpb, dpb == 1 ? "" : "s");

    MapToDiscrete :: proc(value : f64, inMax : f64, outMax : f64) -> i32 {
        if inMax == 0 {
            inMax = 1;
        }

        result := cast(i32)((value  / inMax) * outMax);
        return result;
    }

    for lineIndex : i32 = GRAPH_HEIGHT - 1; lineIndex >= 0; lineIndex -= 1 {
        fmt.printf("%r", '|');
        for i := 0; i < graph.buckets.count; i += 1 {
            group := graph.buckets[i];
            this : i32 = -1;
            if group.count > 0 {
                this = MapToDiscrete(cast(f64)group.slowestMS, cast(f64)slowestMS, GRAPH_HEIGHT - 1);
            }
            fmt.printf("%r", this >= lineIndex ? '*' : ' ');
        }
        if lineIndex == (GRAPH_HEIGHT - 1) {
            fmt.printf("%r", ' ');
            PrintTime(cast(f64)slowestMS);
        }
        fmt.println();
    }

    fmt.printf("%r", '+');

    for i in 0..<GRAPH_WIDTH {
        fmt.printf("%r", '-');
    }

    fmt.print(' ');
    PrintTime(0);

    fmt.println();
    fmt.println();

    for lineIndex : i32 = GRAPH_HEIGHT - 1; lineIndex >= 0; lineIndex -= 1 {
        fmt.printf("%r", '|');
        for i := 0; i < graph.buckets.count; i += 1 {
            group := graph.buckets[i];
            this : i32 = -1;
            if group.count > 0 {
                this = MapToDiscrete(cast(f64)group.count, cast(f64)maxCountInBucket, GRAPH_HEIGHT - 1);
            }
            fmt.printf("%r", this >= lineIndex ? '*' : ' ');
        }

        if lineIndex == (GRAPH_HEIGHT - 1) {
            fmt.printf(" %d", maxCountInBucket);
        }
        fmt.println();
    }

    fmt.printf("%r", '+');
    for i in 0..<GRAPH_WIDTH {
        fmt.printf("%r", '-');
    }
    fmt.println(" 0");
}

Stats :: proc(array : timing_entry_array, timingFileName : string) {
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
        daySpanCount = cast(u32)(milliD / (1000.0 * 60.0 * 60.0 * 24.0));

        firstDayAt = cast(f64)DayIndex(array.Entries[0].StartDate);
        lastDayAt = cast(f64)DayIndex(array.Entries[array.Entries.count - 1].StartDate);
        daySpan = lastDayAt - firstDayAt;
    }

    daySpan += 1;

    for i := 0; i < array.Entries.count; i += 1 {
        entry : ^timing_file_entry = ^array.Entries[i];
        if(entry.Flags & cast(u32)timing_file_entry_flag.Complete) ==
           cast(u32)timing_file_entry_flag.Complete {
            group : ^stat_group;
            if (entry.Flags & cast(u32)timing_file_entry_flag.NoErrors) ==
                cast(u32)timing_file_entry_flag.NoErrors {
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

            allMS += cast(f64)entry.MillisecondsElapsed;

            {
                graphIndex := ((cast(f64)thisDayIndex - firstDayAt) / daySpan) * cast(f64)GRAPH_WIDTH;
                UpdateStatGroup(^totalGraph.buckets[cast(i32)graphIndex], entry);
            }

            {
                graphIndex := thisDayIndex - cast(u32)(lastDayAt - GRAPH_WIDTH + 1);
                if graphIndex >= 0 {
                    UpdateStatGroup(^recentGraph.buckets[graphIndex], entry);
                }
            }
        } else {
            incompleteCount += 1;
        }
    }

    fmt.printf("\n%s Statistics\n\n", timingFileName);
    fmt.printf("Total complete timings: %d\n", withErrors.count + noErrors.count);
    fmt.printf("Total incomplete timings: %d\n", incompleteCount);
    fmt.printf("Days with timings: %d\n", daysWithTimingCount);
    fmt.printf("Days between first and last timing: %d\n", daySpanCount);
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
    args := GetCommandLineArguments();
    if args.count == 3 || args.count == 4 {
        mode := args[1];
        modeIsBegin := mode == "-begin";
        timingFileName := args[2];
        header : timing_file_header;      

        handle, err := os.open(timingFileName, os.O_RDWR, 0);
        if err == 0 {
            buf : [size_of(timing_file_header)]byte;
            b, err := os.read(handle, buf[:]);
            header = (cast(^timing_file_header)^buf[0])^;
            if header.MagicValue != MAGIC_VALUE {
                fmt.fprintf(os.stderr, "ERROR: Unable to verify that \"%s\" is actually a ctime-compatible file.\n", timingFileName);

                os.close(handle);
                handle = -1;
            }
        } else if modeIsBegin {
            handle, err = os.open(timingFileName, os.O_RDWR|os.O_CREAT, 0); // create the missing file
            if err == 0 {
                header.MagicValue = MAGIC_VALUE;
                
                buf : []byte;
                buf.data = cast(^byte)^header;
                buf.count = size_of_val(header);
                written, err := os.write(handle, buf);

                if written != size_of(timing_file_header) {
                    fmt.fprintf(os.stderr, "ERROR: Unable to write header to \"%s\".\n", timingFileName);
                }
            } else {
                 fmt.fprintf(os.stderr, "ERROR: Unable to create timing file \"%s\".\n", timingFileName);
            }
        }

        if handle != os.INVALID_HANDLE {
            if modeIsBegin {
                new : timing_file_entry;
                new.StartDate = GetDate();
                new.MillisecondsElapsed = GetClock();

                fp, _ := os.seek(handle, 0, 2);
                buf : []byte;
                buf.data = cast(^byte)^new;
                buf.count = size_of_val(new);
                written, _ := os.write(handle, buf);
                if (fp < 0) && 
                   (written != size_of_val(new)) {
                    fmt.fprintf(os.stderr, "ERROR: Unable to append new entry to file \"%s\".\n", timingFileName);
                }
            } else if mode == "-end" {
                seek, err := os.seek(handle, -size_of(timing_file_entry), 2);
                buf : [size_of(timing_file_entry)]byte;
                read, err1 := os.read(handle, buf[:]);
                last := cast(timing_file_entry)(cast(^timing_file_entry)^buf[0])^;
                if (seek >= 0) &&
                   (read) == size_of(timing_file_entry) {
                    if (last.Flags & cast(u32)timing_file_entry_flag.Complete) != cast(u32)timing_file_entry_flag.Complete {
                        startClockD := last.MillisecondsElapsed;
                        endClockD := entryClock;
                        last.Flags |= cast(u32)timing_file_entry_flag.Complete;
                        
                        last.MillisecondsElapsed = 0;
                        if startClockD < endClockD {
                            last.MillisecondsElapsed = endClockD - startClockD;
                        }

                        if args.count == 3 || (args.count == 4 && (atoi(args[3]) == 0)) {
                            last.Flags |= cast(u32)timing_file_entry_flag.NoErrors;
                        }

                        fp, _ := os.seek(handle, -size_of(timing_file_entry), 2);
                        
                        buf : []byte;
                        buf.data = cast(^byte)^last;
                        buf.count = size_of_val(last);
                        written, err := os.write(handle, buf);
                        
                        if (fp >= 0) &&
                           (written == size_of_val(last)) {
                            fmt.print("OTIME: ");
                            PrintTime(cast(f64)last.MillisecondsElapsed);
                            fmt.printf(" (%s)\n", timingFileName);
                        } else {
                            fmt.fprintf(os.stderr, "ERROR: Unable to rewrite last entry to file \"%s\".\n", timingFileName);
                        }
                    } else {
                        fmt.fprintf(os.stderr, "ERROR: Last entry in file \"%s\" is already closed - unbalanced/overlapped calls?\n", timingFileName);
                    }
               } else {
                    fmt.fprintf(os.stderr, "ERROR: Unable to read last entry from file \"%s\".\n", timingFileName);
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
                fmt.fprintf(os.stderr, "ERROR: Unrecognized command \"%s\".\n", mode);
            }

            os.close(handle);
            handle = -1;
        } else {
            fmt.fprintf(os.stderr, "ERROR: Cannot open file \"%s\".\n", timingFileName);
        }
    } else {
        Usage();
    }
}