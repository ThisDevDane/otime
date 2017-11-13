/*
 *  @Name:     otime
 *  
 *  @Author:   Mikkel Hjortshoej
 *  @Email:    hoej@northwolfprod.com
 *  @Creation: 13-11-2017 01:06:46
 *
 *  @Last By:   Mikkel Hjortshoej
 *  @Last Time: 13-11-2017 18:24:17
 *  
 *  @Description:
 *      A timing to file library 
 */

import       "core:os.odin";
import       "core:math.odin";
import       "core:raw.odin";
import win32 "core:sys/windows.odin";

export "ctime_convert.odin";

VERSION_STR :: "v0.7.0";

OTM1_MAGIC_VALUE :: 0x4f544d31;  //Hex for "OTM1"

File :: struct {
    handle : os.Handle,
    name   : string,
    header : File_Header,
}

File_Header :: struct #ordered {
    magic : u32,
    total_ms : u32,
    timing_count : u32,
}

File_Entry_Flags :: enum u32 {
    Complete = 1 << 1,
    NoError  = 1 << 2,
}

File_Entry :: struct #ordered {
    date_raw     : [2]u32, //lo, hi
    time_elapsed : u32, //In milliseconds
    flags        : File_Entry_Flags
}

Stat_Group :: struct {
    name       : string,
    count      : int,
    total_ms   : u32,
    slowest_ms : u32,
    fastest_ms : u32,
    average_ms : u32,
}

Parsed_Timing :: struct {
    weeks   : int,
    days    : int,
    hours   : int,
    minutes : int,
    seconds : f64,
}

validate_as_otm :: proc(file : ^File) -> bool {
    _, ok := os.seek(file.handle, 0, 0);
    if ok != 0 {
        return false;
    }

    buf : [size_of(File_Header)]u8;
    _, err := os.read(file.handle, buf[..]);
    file.header = (cast(^File_Header)&buf[0])^;

    if file.header.magic != OTM1_MAGIC_VALUE {
        return false;
    } else {
        return true;
    }
}

add_new_header_to_file :: proc(file : ^File) -> bool {
    file.header = File_Header{};
    file.header.magic = OTM1_MAGIC_VALUE;

    return write_header_to_file(file);
}

add_new_entry_to_file :: proc(file : ^File) -> bool {
    entry := File_Entry{};
    
    ft : win32.Filetime;
    win32.get_system_time_as_file_time(&ft);

    entry.date_raw[0] = ft.lo;
    entry.date_raw[1] = ft.hi;
    entry.time_elapsed = win32.time_get_time();

    return write_entry_to_file(file, entry);
}

write_header_to_file :: proc(file : ^File) -> bool {
    _, ok := os.seek(file.handle, 0, 0);
    if ok != 0 {
        return false;
    }

    buf := transform_to_bytes(&file.header, size_of(file.header));
    written, err := os.write(file.handle, buf);
    if written == size_of(file.header) && err == 0 {
        return true;
    } else {
        return false;
    }
}

write_entry_to_file :: proc(file : ^File, entry : File_Entry) -> bool {
    buf := transform_to_bytes(&entry, size_of(entry));

    _, err := os.seek(file.handle, 0, 2);
    if err != 0 {
        return false;
    } else {
        written, err := os.write(file.handle, buf);
        if err == 0 && written == size_of(entry) {
            return true;
        } else {
            return false;
        }
    }
}

close_last_entry_in_file :: proc(file : ^File, entry : File_Entry, err_level : string) -> (already_closed : bool, write_ok : bool, ms : u32) {
    if is_entry_flag_set(entry.flags, File_Entry_Flags.Complete) {
        return true, false, 0;
    }

    start_time := entry.time_elapsed;
    end_time := win32.time_get_time();
    
    entry.time_elapsed = 0;
    if start_time < end_time {
        entry.time_elapsed = end_time - start_time;
    }

    if err_level == "0" {
        entry.flags |= File_Entry_Flags.NoError;
    }
    entry.flags |= File_Entry_Flags.Complete;

    _, err := os.seek(file.handle, -size_of(File_Entry), 2);
    buf := transform_to_bytes(&entry, size_of(entry));

    written, okw := os.write(file.handle, buf[..]);
    if written != size_of(entry) {
        return false, false, 0;
    }

    file.header.timing_count += 1;
    file.header.total_ms += entry.time_elapsed;
    write_header_to_file(file);

    return false, true, entry.time_elapsed;
}

read_last_entry_from_file :: proc(file : ^File) -> (File_Entry, bool) {
    _, err := os.seek(file.handle, -size_of(File_Entry), 2);
    if err != 0 {
        return File_Entry{}, false;
    }
    buf : [size_of(File_Entry)]u8;
    read : int;
    read, err = os.read(file.handle, buf[..]);
    if read == size_of(File_Entry) && err == 0 {
        entry : File_Entry = (cast(^File_Entry)&buf[0])^;
        return entry, true;
    } else {
        return File_Entry{}, false;
    }
}

read_all_entries_from_file :: proc(file : ^File) -> ([]File_Entry, bool) {
    header_size, err := os.seek(file.handle, size_of(file.header), 0);
    if err != 0 {
        return nil, false;
    }
    total_size, ok := os.seek(file.handle, 0, 2);
    if ok != 0 {
        return nil, false;
    }

    data_size := total_size - header_size;
    _, err = os.seek(file.handle, size_of(file.header), 0);
    if err != 0 {
        return nil, false;
    }
    buf := make([]u8, data_size);
    _, err = os.read(file.handle, buf);
    if err != 0 {
        return nil, false;
    }
    
    raw_entries := raw.Slice{
        &buf[0],
        len(buf) / size_of(File_Entry),
        len(buf) / size_of(File_Entry),
    };

    return transmute([]File_Entry)raw_entries, true;
}

gather_stat_groups :: proc(file : ^File, entries : []File_Entry) -> ([]Stat_Group, int) {
    groups        := make([]Stat_Group, 2);

    success_group := &groups[0];
    success_group.name = "successful";
    success_group.slowest_ms = 0;
    success_group.fastest_ms = 0xFFFFFFFF;
    
    failed_group  := &groups[1];
    failed_group.name = "failed";
    failed_group.slowest_ms = 0;
    failed_group.fastest_ms = 0xFFFFFFFF;
    count_of_non_complete := 0;
    for entry in entries {
        if !is_entry_flag_set(entry.flags, File_Entry_Flags.Complete) {
            count_of_non_complete += 1;
            continue;
        }

        if is_entry_flag_set(entry.flags, File_Entry_Flags.NoError) {
            add_entry_to_stat_group(success_group, entry);
        } else {
            add_entry_to_stat_group(failed_group, entry);
        }
    }

    return groups, count_of_non_complete;
}

parse_ms :: proc(ms : u32) -> Parsed_Timing {
    MS_PER_WEEK   : f64 : 7   *MS_PER_DAY;
    MS_PER_DAY    : f64 : 24  *MS_PER_HOUR;
    MS_PER_HOUR   : f64 : 60  *MS_PER_MINUTE;
    MS_PER_MINUTE : f64 : 60  *MS_PER_SECOND;
    MS_PER_SECOND : f64 : 1000;

    res := Parsed_Timing{};

    res.weeks = int(f64(ms) / MS_PER_WEEK);
    ms -= u32(f64(res.weeks) * MS_PER_WEEK);

    res.days = int(f64(ms) / MS_PER_DAY);
    ms -= u32(f64(res.days) * MS_PER_DAY);

    res.hours = int(f64(ms) / MS_PER_HOUR);
    ms -= u32(f64(res.hours) * MS_PER_HOUR);

    res.minutes = int(f64(ms) / MS_PER_MINUTE);
    ms -= u32(f64(res.minutes) * MS_PER_MINUTE);

    res.seconds = f64(ms) / MS_PER_SECOND;
    return res;
}

transform_to_bytes :: proc(ptr : rawptr, size : int) -> []u8 {
    buf_raw := raw.Slice {
        ptr,
        size,
        size
    };
    buf := transmute([]u8)buf_raw;
    return buf;
}

is_entry_flag_set :: proc(data : File_Entry_Flags, flag : File_Entry_Flags) -> bool {
    return data & flag == flag;
}

add_entry_to_stat_group :: proc(group : ^Stat_Group, entry : File_Entry) {
    group.count += 1;
    group.total_ms += entry.time_elapsed;

    if entry.time_elapsed > group.slowest_ms {
        group.slowest_ms = entry.time_elapsed;
    }

    if entry.time_elapsed < group.fastest_ms {
        group.fastest_ms = entry.time_elapsed;
    }

    group.average_ms = group.total_ms / u32(group.count);
}

