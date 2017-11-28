/*
 *  @Name:     program
 *  
 *  @Author:   Mikkel Hjortshoej
 *  @Email:    hoej@northwolfprod.com
 *  @Creation: 13-11-2017 01:07:05
 *
 *  @Last By:   Mikkel Hjortshoej
 *  @Last Time: 28-11-2017 22:57:27
 *  
 *  @Description:
 *      Executable for the otime library. This provides the timing begin, end and stats as we know from Ctime.
 */

import "core:fmt.odin";
import "core:os.odin";

import "otime.odin";

Usage_Mode :: enum {
    Begin,
    End,
    Stats,
    Convert,
    Unknown,
}

usage :: proc(wrong := "") {
    if wrong != "" {
        fmt.fprintf(os.stderr, "%s is not a recognized command\n", wrong);
    }

    fmt.fprintf( os.stderr, "Otime %s by Mikkel Hjortshoej\n", otime.VERSION_STR);
    fmt.fprintln(os.stderr, "Usage:");
    fmt.fprintln(os.stderr, "    otime -begin   <timing file>");
    fmt.fprintln(os.stderr, "       Begins a timing, creates the file if missing.");
    fmt.fprintln(os.stderr, "    otime -end     <timing file> [error]");
    fmt.fprintln(os.stderr, "       Ends a timing, 0 in error is regarded as success.");
    fmt.fprintln(os.stderr, "    otime -stats   <timing file>");
    fmt.fprintln(os.stderr, "       Output various stats about your timings.");
    fmt.fprintln(os.stderr, "    otime -convert <timing file>");
    fmt.fprintln(os.stderr, "       Converts ctime files to otm1 files (which this program uses).");
}

print_time :: proc(name : string, ms : u32) {
    parsed := otime.parse_ms(ms);
    fmt.printf("%s ", name);
    print_part :: proc(name : string, t : int) {
        if t > 0 {
            fmt.printf("%d %s%s, ", t, name, t == 1 ? "" : "s");
        }
    }
    print_part("week",   parsed.weeks);
    print_part("day",    parsed.days);
    print_part("hour",   parsed.hours);
    print_part("minute", parsed.minutes);

    fmt.printf("%.3f %s%s\n", parsed.seconds, "second", parsed.seconds == 1 ? "" : "s");
}

end :: proc(file : ^otime.File, err_s : string) {
    err, ms := otime.end(file, err_s);
    switch err {
    case otime.ERR_OK :
        print_time("OTIME:", ms);
        if file.header.timing_count % 10 == 0 {
            fmt.printf("OTIME: Average over %d timings:", file.header.timing_count);
            print_time("", file.header.total_ms / file.header.timing_count);
        }
    case otime.ERR_READ_FAILED :
        fmt.fprintf(os.stderr, "ERROR: Unable to read last entry in \"%s\"\n", file.name);
    case otime.ERR_WRITE_FAILED :
        fmt.fprintf(os.stderr, "ERROR: Unable to rewrite last entry in \"%s\"\n", file.name);
    case otime.ERR_ENTRY_ALREADY_CLOSED :
        fmt.fprintf(os.stderr, "ERROR: Last entry in \"%s\" is already closed - unbalanced/overlapped -end calls?\n", file.name);
    }
}

stats :: proc(file : ^otime.File) {
    stat_groups, incomplete := otime.get_stat_groups(file);
    if stat_groups != nil {
        fmt.printf("\nStats from %s.\n\n", file.name);
        fmt.printf("Total timings: %d.\n", file.header.timing_count);
        fmt.printf("Total incomplete timings: %d.\n\n", incomplete);
        for group in stat_groups {
            if group.count > 0 {
                fmt.printf("Timings marked %s (%d):\n", group.name, group.count);
                print_time("  Slowest:", group.slowest_ms);
                print_time("  Fastest:", group.fastest_ms);
                print_time("  Average:", group.average_ms);
                print_time("  Total:  ", group.total_ms);
            } else {
                fmt.printf("No timings marked %s\n", group.name);
            }
            fmt.println();
        }
        print_time("Average of all groups: ", file.header.total_ms / file.header.timing_count);
        print_time("Total of all groups:   ", file.header.total_ms);
    } else {
        fmt.fprintf(os.stderr, "ERROR: Unable to read all entries from \"%s\"\n", file.name);
        return;
    }
}

get_mode :: proc(arg : string) -> Usage_Mode {
    switch arg {
    case "-begin":
        return Usage_Mode.Begin;
    case "-end":
        return Usage_Mode.End;
    case "-stats":
        return Usage_Mode.Stats;
    case "-convert":
        return Usage_Mode.Convert;
    }

    return Usage_Mode.Unknown;
}

main :: proc() {
    make([]u8, 1); //FIXME For some reason it crashes at runtime if this is not here
    args := os.args[1..];
    if len(args) != 2 && len(args) != 3 {
        usage();
        return;
    } else {
        mode := get_mode(args[0]);

        if mode == Usage_Mode.Unknown {
            usage(args[0]);
            return;
        }

        file : otime.File;
        name := args[1]; //TODO(Hoej): Auto add extension of missing.
        handle, ok := os.open(name, os.O_RDWR);

        if ok != os.ERROR_NONE {
            switch mode {
            case Usage_Mode.Convert :
                fmt.fprintf(os.stderr, "ERROR: Unable to convert \"%s\" since it doesn't exist.\n", name);
                return;
            case Usage_Mode.Begin : 
                err : otime.Err;
                file, err = otime.create_file(name);
                switch err {
                case otime.ERR_WRITE_FAILED :
                    fmt.fprintf(os.stderr, "ERROR: Unable to write header to \"%s\".\n", file.name); 
                case otime.ERR_READ_FAILED :
                    fmt.fprintf(os.stderr, "ERROR: Unable to seek in \"%s\".\n", file.name); 
                }
                if err != otime.ERR_OK {
                    fmt.fprintf(os.stderr, "ERROR: Unable to create \"%s\".\n", file.name);
                    return;
                }
            case : 
                fmt.fprintf(os.stderr, "ERROR: Unable to open \"%s\".\n", name);
                return;
            }
        }

        if !file.initialized {
            file = otime.init_file(handle, name);
        }

        if file.initialized {
            switch mode {
            case Usage_Mode.Begin:
                if file.ftype != otime.File_Types.Otm1 {
                    fmt.fprintf(os.stderr, "ERROR: Unable to verify that \"%s\" is a otm1 file, was %v.\n", file.name, file.ftype); 
                    return;
                }
                if otime.begin(&file) != otime.ERR_OK {
                    fmt.fprintf(os.stderr, "ERROR: Unable to write new entry to \"%s\"\n", file.name);
                }
            case Usage_Mode.End:
                if file.ftype != otime.File_Types.Otm1 {
                    fmt.fprintf(os.stderr, "ERROR: Unable to verify that \"%s\" is a otm1 file, was %v.\n", file.name, file.ftype); 
                    return;
                }
                err := len(args) == 3 ? args[2] : "0";
                end(&file, err);
            case Usage_Mode.Stats :
                if file.ftype != otime.File_Types.Otm1 {
                    fmt.fprintf(os.stderr, "ERROR: Unable to verify that \"%s\" is a otm1 file, was %v.\n", file.name, file.ftype); 
                    return;
                }
                stats(&file);
            case Usage_Mode.Convert :
                if !otime.is_convertable_file(&file) {
                    fmt.fprintf(os.stderr, "ERROR: Unable to verify that \"%s\" is a convertable file, was %v.\n", file.name, file.ftype); 
                    break;
                } 
                if otime.convert(&file, otime.File_Types.Otm1) != otime.ERR_OK {
                    fmt.fprintf(os.stderr, "ERROR: Unable to convert ctime file to otm1 file.\n", file.name); 
                } else {
                    fmt.fprintf(os.stdout, "OTIME: \"%s\" was converted to %v.\n", file.name, file.ftype);
                }
            case : 
                usage();
            }
        } else {
            fmt.fprintf(os.stderr, "ERROR: Unable to open/initialize \"%s\"\n", name);
        }

        os.close(file.handle);
    }
}