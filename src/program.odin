/*
 *  @Name:     program
 *  
 *  @Author:   Mikkel Hjortshoej
 *  @Email:    hoej@northwolfprod.com
 *  @Creation: 13-11-2017 01:07:05
 *
 *  @Last By:   Mikkel Hjortshoej
 *  @Last Time: 13-11-2017 03:39:20
 *  
 *  @Description:
 *      Executable for the otime library. This provides the timing begin and end as we know from Ctime.
 */

import "core:fmt.odin";
import "core:os.odin";

import "otime.odin";

VERSION_STR :: "v0.1";

Usage_Mode :: enum {
    Begin,
    End,
    Stats
}

usage :: proc() {
    fmt.fprintf( os.stderr, "Otime %s by Mikkel Hjortshoej\n", VERSION_STR);
    fmt.fprintln(os.stderr, "Usage:");
    fmt.fprintln(os.stderr, "\totime -begin <timing file>");
    fmt.fprintln(os.stderr, "\totime -end   <timing file> [error level]");
    fmt.fprintln(os.stderr, "\totime -stats <timing file>");
}

main :: proc() {
    args := os.args[1..];
    if len(args) != 2 && len(args) != 3 {
        usage();
        return;
    } else {
        mode : Usage_Mode;
        switch args[0] {
        case "-begin":
            mode = Usage_Mode.Begin;
        case "-end":
            mode = Usage_Mode.End;
        case "-stats":
            mode = Usage_Mode.Stats;
        }

        file := otime.File{};
        file.name = args[1]; //TODO(Hoej): Auto add extension of missing.
        ok : os.Errno; 
        file.handle, ok = os.open(file.name, os.O_RDWR);

        if ok == 0 {
            if !otime.read_header_and_validate(&file) {
                fmt.fprintf(os.stderr, "ERROR: Unable to verify that \"%s\" is a otime compatible file.\n", file.name); 
                os.close(file.handle);
                file.handle = os.INVALID_HANDLE;
            }
        } else if mode == Usage_Mode.Begin {
            file.handle, ok = os.open(file.name, os.O_RDWR | os.O_CREATE);
            if ok == 0 {
                if !otime.write_new_header_to_file(&file) {
                    fmt.fprintf(os.stderr, "ERROR: Unable to write header to \"%s\"\n", file.name);
                }
            } else {
                fmt.fprintf(os.stderr, "ERROR: Unable to create \"%s\".\n", file.name);
            }
        }

        if file.handle != os.INVALID_HANDLE {
            switch mode {
            case Usage_Mode.Begin:
                if !otime.write_new_entry_to_file(&file) {
                    fmt.fprintf(os.stderr, "ERROR: Unable to write new entry to \"%s\"\n", file.name);
                }

            case Usage_Mode.End:
                entry, read_ok := otime.read_last_entry_from_file(&file);
                if !read_ok {
                    fmt.fprintf(os.stderr, "ERROR: Unable to read last entry in \"%s\"\n", file.name);
                    break;
                } 
                err := len(args) == 3 ? args[2] : "0";
                already_closed, write_ok, time := otime.close_last_entry_in_file(&file, entry, err);
                if already_closed {
                    fmt.fprintf(os.stderr, "ERROR: Last entry in \"%s\" is already closed - unbalanced/overlapped -end calls?\n", file.name);
                } else if !write_ok {
                    fmt.fprintf(os.stderr, "ERROR: Unable to rewrite last entry in \"%s\"\n", file.name);
                } else {
                    fmt.print("OTIME: ");
                    MS_PER_SECOND : f64 : 1000;
                    MS_PER_MINUTE : f64 : 60*MS_PER_SECOND;
                    MS_PER_HOUR   : f64 : 60*MS_PER_MINUTE;
                    MS_PER_DAY    : f64 : 24*MS_PER_HOUR;
                    MS_PER_WEEK   : f64 : 7 *MS_PER_DAY;

                    print_part_of_time :: proc(name : string, time : f64, msper : f64) -> f64 {
                        part := f64(int(time / msper));
                        if part > 0 {
                            fmt.printf("%d %s%s, ", int(part), name, part == 1 ? "" : "s");
                        }
                        time -= part*msper;
                        return time;
                    }

                    time = print_part_of_time("week",   time, MS_PER_WEEK);
                    time = print_part_of_time("days",   time, MS_PER_DAY);
                    time = print_part_of_time("hour",   time, MS_PER_HOUR);
                    time = print_part_of_time("minute", time, MS_PER_MINUTE);

                    fmt.printf("%.1f seconds ", time / MS_PER_SECOND);

                    if file.header.timing_count % 10 == 0 {
                        fmt.printf("\nOTIME: Average over %d timings: ", file.header.timing_count);
                        time = print_part_of_time("week",   file.header.average_ms, MS_PER_WEEK);
                        time = print_part_of_time("days",   time, MS_PER_DAY);
                        time = print_part_of_time("hour",   time, MS_PER_HOUR);
                        time = print_part_of_time("minute", time, MS_PER_MINUTE);

                        fmt.printf("%.3f seconds ", time / MS_PER_SECOND);
                    }
                    fmt.printf("(%s)\n", file.name);

                }
            }
        }
    }
}