/*
 *  @Name:     program
 *  
 *  @Author:   Mikkel Hjortshoej
 *  @Email:    hoej@northwolfprod.com
 *  @Creation: 13-11-2017 01:07:05
 *
 *  @Last By:   Mikkel Hjortshoej
 *  @Last Time: 16-11-2017 01:55:07
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
}

usage :: proc() {
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

main :: proc() {
    make([]u8, 1); //FIXME For some reason it crashes at runtime if this is not here
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
        case "-convert":
            mode = Usage_Mode.Convert;
        }

        file : otime.File;
        file.name = args[1]; //TODO(Hoej): Auto add extension of missing.
        ok : os.Errno; 
        file.handle, ok = os.open(file.name, os.O_RDWR);

        if mode != Usage_Mode.Convert {
            if ok == 0 {
                if otime.get_file_type(&file) != otime.File_Types.Otm1 {
                    fmt.fprintf(os.stderr, "ERROR: Unable to verify that \"%s\" is a otime compatible file.\n", file.name); 
                    if otime.get_file_type(&file) != otime.File_Types.Ctime {
                        fmt.fprintf(os.stderr, "ERROR: This is a ctime file, please -convert it to continue usage.\n"); 
                    }
                    os.close(file.handle);
                    file.handle = os.INVALID_HANDLE;
                }
            } else if mode == Usage_Mode.Begin {
                file.handle, ok = os.open(file.name, os.O_RDWR | os.O_CREATE);
                if ok == 0 {
                    if otime.add_new_header_to_file(&file) != otime.ERR_OK {
                        fmt.fprintf(os.stderr, "ERROR: Unable to write header to \"%s\"\n", file.name);
                    }
                } else {
                    fmt.fprintf(os.stderr, "ERROR: Unable to create \"%s\".\n", file.name);
                }
            }
        }

        if file.handle != os.INVALID_HANDLE {
            switch mode {
            case Usage_Mode.Begin:
                if otime.begin(&file) != otime.ERR_OK {
                    fmt.fprintf(os.stderr, "ERROR: Unable to write new entry to \"%s\"\n", file.name);
                }

            case Usage_Mode.End:
                err := len(args) == 3 ? args[2] : "0";
                end(&file, err);
            case Usage_Mode.Stats :
                stats(&file);
            case Usage_Mode.Convert : 
                if otime.get_file_type(&file) == otime.File_Types.Ctime {
                    if otime.convert(&file, otime.File_Types.Ctime, otime.File_Types.Otm1) != otime.ERR_OK {
                        fmt.fprintf(os.stderr, "ERROR: Unable to convert ctime file to otm1 file.\n", file.name); 
                    }
                } else {
                    fmt.fprintf(os.stderr, "ERROR: Unable to verify that \"%s\" is a ctime compatible file.\n", file.name); 
                }
            }
        }

        os.close(file.handle);
    }
}