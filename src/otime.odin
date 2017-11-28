/*
 *  @Name:     otime
 *  
 *  @Author:   Mikkel Hjortshoej
 *  @Email:    hoej@northwolfprod.com
 *  @Creation: 13-11-2017 01:06:46
 *
 *  @Last By:   Mikkel Hjortshoej
 *  @Last Time: 28-11-2017 22:56:32
 *  
 *  @Description:
 *      A timing to file library 
 *
 * SUGGESTION(J_vanRijn):
 *  If you changed that to `otime.begin('site')`, `otime.end('site')` and `otime.flush()`, 
 *  you could have it build up a bunch of metrics for calls to a site and then explicitly flush, 
 *  which the compilation driver would do or end might take an optional param that tells it to flush
 *
 * TODO(Hoej): Change error handling to be like add_new_header_to_file(file, &err); that way we can just 
 *             handle the err at the end, since each function will just return like fabian showed, main functions 
 *             should still return an Err
 */

import       "core:os.odin";
import       "core:fmt.odin";
import       "core:math.odin";
import       "core:raw.odin";
import win32 "core:sys/windows.odin";

import "otm1.odin"
import ctime "ctime_convert.odin"
export "otime_err.odin";

VERSION_STR :: "v0.7.0";

File :: struct {
    initialized : bool,
    handle : os.Handle,
    name   : string,
    ftype  : File_Types,
    header : otm1.Header,
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

File_Types :: enum {
    Otm1, 
    Ctime,
    Unknown
}

create_file :: proc(name : string) -> (File, Err) {
    handle, ok := os.open(name, os.O_RDWR | os.O_CREATE);
    if ok == os.ERROR_NONE {
        file := File{};
        file.handle = handle;
        file.name = name;
        err := add_new_header_to_file(&file);
        if err == ERR_READ_FAILED {
            err = ERR_OK;
        }
        if err == ERR_OK {
            file.initialized = true;
        }
        return file, err;
    } else {
        return File{}, ERR_WRITE_FAILED;
    }
}

init_file :: proc(handle : os.Handle, name : string) -> File {
    file := File{};
    file.handle = handle;
    file.name = name;
    file.ftype = get_file_type(&file);
    file.initialized = true;
    return file;
}

get_file_type :: proc(file : ^File) -> File_Types {
    if header, ok := otm1.validate_as_otm1(file.handle); ok {
        file.header = header;
        return File_Types.Otm1;
    }

    if ctime.validate_as_ctime(file.handle) {
        return File_Types.Ctime;
    }

    return File_Types.Unknown;
}

is_convertable_file :: proc(file : ^File) -> bool {
    using File_Types;
    switch file.ftype {
    case Ctime:
        return true;

    case:
        return false;
    }
}

convert :: proc(file : ^File, to : File_Types) -> Err {
    using File_Types;
    if file.ftype == Ctime && to == Otm1 {
        if err, header, entries := ctime.convert_to_otm1(file.handle, file.name); err == ERR_OK {
            file.header = header;
            file.ftype = Otm1;
            write_header_to_file(file);
            for e in entries {
                write_entry_to_file(file, e);
            }
            return ERR_OK;
        } else {
            return ERR_CONVERT_FAILED;
        }
    }

    return ERR_CONVERT_FAILED;
}

begin :: proc(file : ^File) -> Err {
    return add_new_entry_to_file(file);
}

//TODO(Hoej): Cache time earlier so we don't wait for File IO before time measurement
end :: proc(file : ^File, err : string) -> (err : Err, ms : u32) {
    entry, read_ok := read_last_entry_from_file(file);
    if !read_ok {
        return ERR_READ_FAILED, 0;
    }

    already_closed, write_ok, ms := close_last_entry_in_file(file, entry, err);
    if already_closed  {
        return ERR_ENTRY_ALREADY_CLOSED, 0;
    } else if !write_ok {
        return ERR_WRITE_FAILED, 0;
    } else {
        return ERR_OK, ms;
    }
}

add_new_header_to_file :: proc(file : ^File) -> Err {
    file.header = otm1.Header{};
    file.header.magic = otm1.MAGIC_VALUE;
    file.ftype = File_Types.Otm1;

    return write_header_to_file(file);
}

add_new_entry_to_file :: proc(file : ^File) -> Err {
    entry := otm1.Entry{};
    
    entry.time_elapsed = win32.time_get_time();
    
    ft : win32.Filetime;
    win32.get_system_time_as_file_time(&ft);
    entry.date_raw[0] = ft.lo;
    entry.date_raw[1] = ft.hi;

    return write_entry_to_file(file, entry);
}

write_header_to_file :: proc(file : ^File) -> Err {
    _, ok := os.seek(file.handle, 0, 0);
    if ok != 0 {
        return ERR_READ_FAILED;
    }

    buf := transform_to_bytes(&file.header, size_of(file.header));
    written, err := os.write(file.handle, buf);
    if written == size_of(file.header) && err == 0 {
        return ERR_OK;
    } else {
        return ERR_WRITE_FAILED;
    }
}

write_entry_to_file :: proc(file : ^File, entry : otm1.Entry) -> Err {
    buf := transform_to_bytes(&entry, size_of(entry));

    _, err := os.seek(file.handle, 0, 2);
    if err != 0 {
        return ERR_READ_FAILED;
    } else {
        written, err := os.write(file.handle, buf);
        if err == 0 && written == size_of(entry) {
            return ERR_OK;
        } else {
            return ERR_WRITE_FAILED;
        }
    }
}

close_last_entry_in_file :: proc(file : ^File, entry : otm1.Entry, err_level : string) -> (already_closed : bool, write_ok : bool, ms : u32) {
    if otm1.is_entry_flag_set(entry.flags, otm1.Entry_Flags.Complete) {
        return true, false, 0;
    }

    start_time := entry.time_elapsed;
    end_time := win32.time_get_time();
    
    entry.time_elapsed = 0;
    if start_time < end_time {
        entry.time_elapsed = end_time - start_time;
    }

    if err_level == "0" {
        entry.flags |= otm1.Entry_Flags.NoError;
    }
    entry.flags |= otm1.Entry_Flags.Complete;

    _, err := os.seek(file.handle, -size_of(otm1.Entry), 2);
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

read_last_entry_from_file :: proc(file : ^File) -> (otm1.Entry, bool) {
    _, err := os.seek(file.handle, -size_of(otm1.Entry), 2);
    if err != 0 {
        return otm1.Entry{}, false;
    }
    buf : [size_of(otm1.Entry)]u8;
    read : int;
    read, err = os.read(file.handle, buf[..]);
    if read == size_of(otm1.Entry) && err == 0 {
        entry : otm1.Entry = (cast(^otm1.Entry)&buf[0])^;
        return entry, true;
    } else {
        return otm1.Entry{}, false;
    }
}

read_all_entries_from_file :: proc(file : ^File) -> ([]otm1.Entry, bool) {
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
        len(buf) / size_of(otm1.Entry),
    };
        
    return transmute([]otm1.Entry)raw_entries, true;
}

get_stat_groups :: proc(file : ^File) -> ([]Stat_Group, int) {
    if entries, ok := read_all_entries_from_file(file); ok {
        return gather_stat_groups(entries);
    } else {
        return nil, 0;
    }
}

gather_stat_groups :: proc(entries : []otm1.Entry) -> ([]Stat_Group, int) {
    groups := make([]Stat_Group, 2);

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
        if !otm1.is_entry_flag_set(entry.flags, otm1.Entry_Flags.Complete) {
            count_of_non_complete += 1;
            continue;
        }

        if otm1.is_entry_flag_set(entry.flags, otm1.Entry_Flags.NoError) {
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
    };
    buf := transmute([]u8)buf_raw;
    return buf;
}

add_entry_to_stat_group :: proc(group : ^Stat_Group, entry : otm1.Entry) {
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
